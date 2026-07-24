// Cheap, texture-free nebula impostors for the 3D combat renderer.
//
// This shader deliberately has its own entry points and instance format so it
// can be profiled before it is added to the combat pass.  It expects a unit
// sphere proxy, no face culling, depth testing enabled, depth writes disabled,
// and premultiplied-alpha blending:
//
//   srcColor = ONE, dstColor = ONE_MINUS_SRC_ALPHA
//
// A nebula is assembled from a small number of overlapping ellipsoids.  Each
// covered pixel performs one analytic ray/ellipsoid intersection and exactly
// six density evaluations; there is no SDF march, texture fetch, or simulation
// state.

struct CombatPush {
    float4x4 view_projection;
    // xy = framebuffer size, z = deterministic combat seed.
    float4 viewport_seed;
    float4 glow;
    // xyz = world-space camera position.
    float4 camera_position;
    float4 dark_light_position;
};
[[vk::push_constant]] ConstantBuffer<CombatPush> push;

struct NebulaVertexInput {
    float3 local_position : POSITION;
    float3 center : TEXCOORD0;
    // xyz = ellipsoid radii, w = optical density.
    float4 radii_density : TEXCOORD1;
    // x = identity seed, y = filament scale, z = edge-light strength,
    // w = maximum opacity.
    float4 style : TEXCOORD2;
    float3 color : COLOR0;
};

struct NebulaOutput {
    float4 position : SV_Position;
    float3 local_position : TEXCOORD0;
    nointerpolation float3 local_camera : TEXCOORD1;
    nointerpolation float4 style : TEXCOORD2;
    nointerpolation float optical_density : TEXCOORD3;
    nointerpolation float3 color : COLOR0;
};

float srgb_channel_to_linear(float c) {
    return c <= .04045 ? c / 12.92 : pow((c + .055) / 1.055, 2.4);
}

float3 srgb_to_linear(float3 c) {
    return float3(
        srgb_channel_to_linear(c.r),
        srgb_channel_to_linear(c.g),
        srgb_channel_to_linear(c.b)
    );
}

[shader("vertex")]
NebulaOutput nebula_vertex(NebulaVertexInput input) {
    NebulaOutput output;
    float3 radii = max(input.radii_density.xyz, float3(.001));
    float3 world = input.center + input.local_position * radii;
    output.position = mul(push.view_projection, float4(world, 1.0));
    output.local_position = input.local_position;
    output.local_camera = (push.camera_position.xyz - input.center) / radii;
    output.style = input.style;
    output.optical_density = max(input.radii_density.w, 0.0);
    output.color = input.color;
    return output;
}

float hash31(float3 p) {
    p = frac(p * .1031);
    p += dot(p, p.yzx + 33.33);
    return frac((p.x + p.y) * p.z);
}

float nebula_value_noise(float3 p, float seed) {
    float3 cell = floor(p);
    float3 f = frac(p);
    float3 u = f * f * (3.0 - 2.0 * f);
    float3 seed_offset = seed * float3(.017, .031, .047);
    float n000 = hash31(cell + float3(0,0,0) + seed_offset);
    float n100 = hash31(cell + float3(1,0,0) + seed_offset);
    float n010 = hash31(cell + float3(0,1,0) + seed_offset);
    float n110 = hash31(cell + float3(1,1,0) + seed_offset);
    float n001 = hash31(cell + float3(0,0,1) + seed_offset);
    float n101 = hash31(cell + float3(1,0,1) + seed_offset);
    float n011 = hash31(cell + float3(0,1,1) + seed_offset);
    float n111 = hash31(cell + float3(1,1,1) + seed_offset);
    float nx00 = lerp(n000,n100,u.x);
    float nx10 = lerp(n010,n110,u.x);
    float nx01 = lerp(n001,n101,u.x);
    float nx11 = lerp(n011,n111,u.x);
    return lerp(lerp(nx00,nx10,u.y),lerp(nx01,nx11,u.y),u.z);
}

float nebula_fast_noise(float3 p, float seed) {
    float3 phase = p + seed * float3(.017,.029,.043);
    float3 folded = sin(phase + sin(phase.yzx * 1.37 + seed * .011));
    return .5+.5*sin(dot(folded,float3(2.17,2.83,3.41)));
}

// Returns the interval occupied by the unit sphere in ellipsoid-local space.
bool nebula_ray_interval(
    float3 ray_origin,
    float3 ray_direction,
    out float entry,
    out float exit)
{
    float origin_projection = dot(ray_origin, ray_direction);
    float c = dot(ray_origin, ray_origin) - 1.0;
    float discriminant = origin_projection * origin_projection - c;
    if (discriminant <= 0.0) {
        entry = 0.0;
        exit = 0.0;
        return false;
    }

    float root = sqrt(discriminant);
    entry = max(-origin_projection - root, 0.0);
    exit = -origin_projection + root;
    return exit > entry;
}

// A monumental engraved cloud field: nested warped billows provide the body,
// hard density transitions create chiaroscuro, and curved isobar-like cuts
// suggest burin marks wrapping around the cloud. Large portions of the
// ellipsoid remain empty by construction.
float2 nebula_density(float3 p, float seed, float filament_scale) {
    float radius_squared = dot(p, p);

    // One interpolated lattice field is the only value-noise evaluation in a
    // density sample. Smaller billows come from cheap analytic folds below.
    float warp = nebula_value_noise(p * 2.15 + float3(7.1,-3.7,5.3), seed);
    float3 q = p + (warp - .5) * float3(.34,.27,.31);
    // Displace the nominal sphere before applying its falloff. This makes the
    // silhouette share the broad internal billows instead of advertising the
    // smooth ellipsoid proxy. The proxy remains a conservative hard bound.
    float edge_fold = sin(
        p.x*3.7-p.y*2.9+p.z*4.3+seed*.041) * .055;
    float displaced_radius =
        radius_squared-(warp-.5)*.48-edge_fold;
    float envelope = saturate(1.0-displaced_radius);
    envelope *= envelope;
    float broad = warp;
    float middle = nebula_value_noise(
        q*5.1+float3(11.3,4.7,-8.1),seed+43.0);
    float fine = .5+.5*sin(
        q.y*9.7-q.z*8.3+sin(q.x*6.1-seed*.059)*1.12);

    // Low-frequency volume carries the mass; the ridged middle octave carves
    // nested cauliflower shoulders, and the fine octave roughens only their
    // transitions. Thresholding preserves black caves between towers.
    float ridge = 1.0 - abs(middle * 2.0 - 1.0);
    float billow = broad * .64 + ridge * .27 + fine * .09;
    // A narrow threshold gives the volume a cut-paper silhouette.  The broad
    // field still moves that silhouette, but does not wash the whole proxy in
    // grey.
    float body = smoothstep(.585, .705, billow);
    float cavity = smoothstep(.10,.52,
        sin(q.x*1.7-q.y*2.0+q.z*1.4+seed*.127));
    body *= cavity * cavity;

    // Broken contour cuts follow density isobars. A second curved family and
    // rare point marks appear only in shadow, producing localized manga-style
    // engraving rather than luminous ribbons across the whole cloud.
    float frequency = max(filament_scale, .1);
    float contour_distance = abs(frac(
        billow * 9.0 * frequency + q.z * .65) - .5);
    float contour = 1.0-smoothstep(.025, .075, contour_distance);
    float hatch_phase = atan2(q.y,q.x) * 8.0 + q.z * 13.0 +
        warp * 5.0 + seed * .071;
    float cross_phase = atan2(q.z,q.x) * 9.0 - q.y * 15.0 -
        middle * 6.0 - seed * .053;
    float hatch = 1.0-smoothstep(.035,.14,abs(sin(hatch_phase)));
    float crosscut = 1.0-smoothstep(.035,.13,abs(sin(cross_phase)));
    float shadow = 1.0-smoothstep(.44,.62,billow);
    float broken = step(.36,hash31(
        floor(q*8.0)+seed*float3(.019,.037,.061)));
    float stipple = step(.965,
        hash31(floor(q * 31.0) + seed * float3(.013,.029,.041)));
    float engraved = max(contour * broken,
        max(hatch * shadow * broken,
            crosscut * shadow * shadow * broken * .68));
    engraved = max(engraved,stipple * shadow * .72);

    return float2(envelope * body, envelope * body * engraved);
}

struct NebulaFragmentOutput {
    float4 color : SV_Target;
};

[shader("fragment")]
NebulaFragmentOutput nebula_fragment(
    NebulaOutput input,
    bool is_front_face : SV_IsFrontFace)
{
    NebulaFragmentOutput output;
    // With culling disabled, render exactly one proxy crossing. Outside the
    // ellipsoid that is its front face; inside it is the back face. Drawing
    // both integrates the same analytic interval twice and exposes proxy
    // triangles as bright facets.
    bool camera_inside = dot(input.local_camera,input.local_camera) < 1.0;
    if (is_front_face == camera_inside) discard;
    float3 ray_direction =
        normalize(input.local_position - input.local_camera);
    float entry, exit;
    if (!nebula_ray_interval(
            input.local_camera, ray_direction, entry, exit)) {
        discard;
    }

    const int SAMPLE_COUNT = 6;
    float segment_length = exit - entry;
    float step_length = segment_length / float(SAMPLE_COUNT);

    // Fine interleaved pixel jitter breaks six-slice banding without the large
    // discontinuous blocks produced by quantized ray directions.
    float jitter = frac(52.9829189 * frac(
        dot(floor(input.position.xy),float2(.06711056,.00583715)) +
        input.style.x*.0001));

    float transmittance = 1.0;
    float scattered = 0.0;
    float engraved = 0.0;
    float relief = 0.0;
    float previous_density = 0.0;
    float3 mark_position_sum = 0.0;
    float mark_weight = 0.0;
    float strongest_rise = -1.0;
    float3 shoulder_position = 0.0;

    [unroll]
    for (int sample_index = 0; sample_index < SAMPLE_COUNT; ++sample_index) {
        float sample_fraction =
            (float(sample_index) + jitter) / float(SAMPLE_COUNT);
        float3 sample_position = input.local_camera +
            ray_direction * (entry + sample_fraction * segment_length);
        float2 field = nebula_density(
            sample_position, input.style.x, input.style.y);

        float extinction =
            field.x * step_length * input.optical_density;
        float absorbed = transmittance *
            (1.0 - exp2(-extinction * 1.442695));
        scattered += absorbed;
        engraved += absorbed * field.y;
        mark_position_sum += sample_position * absorbed;
        mark_weight += absorbed;
        // Rising density along the viewing ray approximates a lit cloud
        // shoulder. It produces strong chiaroscuro relief from the same six
        // samples instead of spending more evaluations on a gradient.
        float density_rise = max(field.x-previous_density,0.0);
        relief += transmittance * density_rise;
        if (density_rise > strongest_rise) {
            strongest_rise = density_rise;
            shoulder_position = sample_position;
        }
        previous_density = field.x;
        transmittance *= exp2(-extinction * 1.442695);
    }

    float raw_alpha = min(
        1.0 - transmittance,
        saturate(input.style.w));
    float alpha = raw_alpha * .46;
    if (alpha < .002) discard;

    // Broad graphite absorption stays subdued.  Only sparse filament samples
    // approach cold silver, preserving black negative space and the game's
    // engraved rather than airbrushed visual language.
    float filament_light = saturate(
        engraved * input.style.z * 4.20);
    float3 base_color = srgb_to_linear(input.color);
    float3 silver = srgb_to_linear(float3(.78, .80, .79));
    // Engraving depends on separated value planes, not a continuous fog ramp:
    // almost-black absorption, a narrow graphite shoulder, then sparse white
    // cuts.  Quantizing the diffuse body also hides six-sample integration
    // softness without exposing the proxy mesh.
    float body_tone = smoothstep(.22,.48,scattered);
    float graphite_plane =
        smoothstep(.16,.30,scattered) * (1.0-smoothstep(.46,.72,scattered));
    float3 mark_position = strongest_rise > .0
        ? shoulder_position
        : mark_position_sum / max(mark_weight,.0001);
    float hatch_warp =
        sin(mark_position.y*7.0+mark_position.z*5.0+input.style.x*.037)*1.6;
    float hatch_a = 1.0-smoothstep(.035,.14,abs(sin(
        mark_position.x*29.0+mark_position.y*12.0+hatch_warp)));
    float hatch_b = 1.0-smoothstep(.035,.13,abs(sin(
        mark_position.x*-17.0+mark_position.z*31.0-hatch_warp*.73)));
    float hatch_break = step(.42,hash31(
        floor(mark_position*19.0)+input.style.x*float3(.011,.023,.041)));
    float hatch_region = smoothstep(.54,.72,nebula_value_noise(
        mark_position*3.2+float3(7.0,-11.0,5.0),input.style.x+251.0));
    float object_cross_gate = smoothstep(.14,.42,1.0-body_tone);
    float shadow_hatch = max(hatch_a,hatch_b*object_cross_gate) *
        hatch_break * hatch_region * smoothstep(.03,.38,body_tone);
    float2 pixel = floor(input.position.xy);
    float screen_hatch_a = 1.0-smoothstep(.085,.27,abs(sin(
        pixel.x*.31+pixel.y*.105+input.style.x*.071)));
    float screen_hatch_b = 1.0-smoothstep(.075,.25,abs(sin(
        pixel.x*-.13+pixel.y*.34-input.style.x*.053)));
    float crosshatch_gate = smoothstep(.20,.68,1.0-body_tone);
    float print_hatch = max(
        screen_hatch_a,screen_hatch_b*crosshatch_gate) *
        hatch_region * smoothstep(.03,.38,body_tone);
    float stipple_random = hash31(float3(
        floor(pixel*.5),input.style.x*.017));
    float stipple = step(lerp(.995,.91,body_tone),stipple_random) *
        smoothstep(.40,.64,hatch_region);
    // A broken corona helps the cloud read at tactical scale, but a continuous
    // one would reveal the ellipsoid. Gate it through a separate coarse field
    // so only irregular fragments survive around the silhouette.
    float rim_band = smoothstep(.035,.11,raw_alpha) *
        (1.0-smoothstep(.14,.25,raw_alpha));
    float rim_break = smoothstep(.54,.72,nebula_value_noise(
        mark_position*4.6+float3(-3.0,9.0,13.0),input.style.x+419.0));
    // One severe key light binds all overlapping proxies into the same storm
    // front. The local radial direction is only an approximate normal, but the
    // noisy density shoulders keep it from reading as sphere lighting.
    float3 approximate_normal = normalize(mark_position+float3(.001));
    float key_light = smoothstep(-.18,.58,dot(
        approximate_normal,normalize(float3(-.62,.73,.28))));
    float optical_rim = rim_band * rim_break * key_light;
    float shoulder_light = smoothstep(.055,.19,
        saturate(relief*input.style.z)) *
        (1.0-smoothstep(.34,.68,saturate(relief*input.style.z))) *
        smoothstep(.012,.14,body_tone);
    float3 radiance =
        base_color * graphite_plane * .020 +
        silver * (filament_light * alpha * 1.28 +
                  shoulder_light * key_light * alpha * .88 +
                  optical_rim * .075 +
                  shadow_hatch * lerp(.52,.27,key_light) +
                  print_hatch * lerp(.11,.052,key_light) +
                  stipple * .10);

    // Premultiplied output is order-stable within a lobe.  The eventual combat
    // integration should still sort overlapping lobes back-to-front.
    output.color = float4(radiance, alpha);
    return output;
}

// Diagnostic entry used to separate capture-loop failures from fragment cost.
// It is not part of the normal Makefile targets.
[shader("fragment")]
NebulaFragmentOutput nebula_debug_fragment(NebulaOutput input) {
    NebulaFragmentOutput output;
    float envelope = saturate(1.0-dot(input.local_position,input.local_position));
    output.color = float4(float3(.08,.09,.085)*envelope,envelope*.18);
    return output;
}

// Fullscreen development preview. This reuses the exact six-sample density
// function without requiring the eventual instanced combat pipeline. It may be
// compiled temporarily in place of the combat background fragment.
struct NebulaPreviewInput {
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

float4 preview_lobe(float2 point, float2 center, float2 radii, float seed) {
    float2 local_xy = (point - center) / radii;
    float radial = dot(local_xy, local_xy);
    if (radial >= 1.0) return 0.0;
    float half_depth = sqrt(1.0 - radial);
    float step_length = half_depth * 2.0 / 6.0;
    float transmittance = 1.0;
    float engraved = 0.0;
    float relief = 0.0;
    float previous_density = 0.0;
    [unroll]
    for (int i = 0; i < 6; ++i) {
        float z = -half_depth + (float(i) + .5) * step_length;
        float2 field = nebula_density(float3(local_xy, z), seed, .88);
        float extinction = field.x * step_length * 2.35;
        float absorbed = transmittance *
            (1.0 - exp2(-extinction * 1.442695));
        engraved += absorbed * field.y;
        relief += transmittance * max(field.x-previous_density, 0.0);
        previous_density = field.x;
        transmittance *= exp2(-extinction * 1.442695);
    }
    float alpha = min(1.0 - transmittance, .48);
    float silver = saturate(engraved * 1.8);
    return float4(alpha * .08 + silver * .34 + saturate(relief)*.62, alpha, 0.0, 0.0);
}

[shader("fragment")]
float4 nebula_preview_fragment(NebulaPreviewInput input) : SV_Target {
    float2 aspect = float2(
        push.viewport_seed.x / max(push.viewport_seed.y, 1.0), 1.0);
    float2 point = (input.uv * 2.0 - 1.0) * aspect;
    float seed = push.viewport_seed.z;
    float4 accumulated = 0.0;
    accumulated += preview_lobe(point, float2(-.68, .15), float2(.82, .52), seed + 11.0);
    accumulated += preview_lobe(point, float2(-.05, -.18), float2(.76, .43), seed + 37.0);
    accumulated += preview_lobe(point, float2(.52, .10), float2(.68, .48), seed + 71.0);
    accumulated += preview_lobe(point, float2(.87, -.30), float2(.58, .36), seed + 103.0);

    float graphite = smoothstep(.10,.40,saturate(accumulated.y));
    float silver = saturate(accumulated.x);
    float3 color = float3(.0042, .0045, .0044);
    color += float3(.085, .09, .087) * graphite;
    color += float3(.53, .56, .55) * silver;
    return float4(color, 1.0);
}
