// Sparse procedural debris for the true-3D tactical display.
//
// Draw six vertices per particle with no vertex buffer. Each DebrisField
// occupies one draw call; firstInstance selects the field and instanceCount
// selects its particle budget. Particle placement is a pure function of the
// field seed and SV_InstanceID, so captures and replays remain deterministic.

struct CombatPush {
    float4x4 view_projection;
    // xy = framebuffer viewport size, z = deterministic mission seed,
    // w = authoritative presentation time in seconds.
    float4 viewport_seed;
    float4 glow;
    float4 camera_position;
    float4 dark_light_position;
};
[[vk::push_constant]] ConstantBuffer<CombatPush> push;

struct DebrisField {
    // xyz = world-space center, w = radial extent.
    float4 center_radius;
    // x = half-height, y = field seed, z = density/opacity, w = drift rate.
    float4 shape_seed;
    // rgb = semantic tint in sRGB, a = particle size multiplier.
    float4 color_size;
};
[[vk::binding(2,0)]] StructuredBuffer<DebrisField> debris_fields;

float hash11(float p) {
    p = frac(p * .1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

float3 hash31(float p) {
    return frac(sin(float3(p, p + 17.17, p + 43.43)) *
                float3(43758.5453, 22578.1459, 19642.3491));
}

float srgb_channel_to_linear(float c) {
    return c <= .04045 ? c / 12.92 : pow((c + .055) / 1.055, 2.4);
}

float3 srgb_to_linear(float3 c) {
    return float3(
        srgb_channel_to_linear(c.r),
        srgb_channel_to_linear(c.g),
        srgb_channel_to_linear(c.b));
}

struct DebrisOutput {
    float4 position : SV_Position;
    float2 local : TEXCOORD0;
    float3 world_position : TEXCOORD1;
    nointerpolation float4 material : TEXCOORD2;
    nointerpolation float3 color : COLOR0;
};

[shader("vertex")]
DebrisOutput debris_vertex(
    uint vertex_id : SV_VertexID,
    uint particle_id : SV_InstanceID)
{
    DebrisOutput output;
    DebrisField field = debris_fields[0];

    static const float2 corners[6] = {
        float2(-1,-1), float2(1,-1), float2(1,1),
        float2(-1,-1), float2(1,1), float2(-1,1)
    };
    float2 corner = corners[vertex_id];

    float key = float(particle_id) + field.shape_seed.y * 131.0 +
                push.viewport_seed.z * .017;
    float3 random = hash31(key);
    // sqrt gives even areal distribution; a modest center bias keeps the
    // silhouette irregular without turning the entire field into grey fog.
    float angle = random.x * 6.28318530718;
    float radius = sqrt(random.y) * field.center_radius.w;
    float3 center = field.center_radius.xyz + float3(
        cos(angle) * radius,
        sin(angle) * radius,
        (random.z * 2.0 - 1.0) * field.shape_seed.x);

    // Slow, bounded tumbling. Position does not advect, so tactical geometry
    // and deterministic picking never disagree with the visual field.
    float reduced_motion = step(field.shape_seed.w, 0.0);
    float time = push.viewport_seed.w * max(field.shape_seed.w, 0.0) *
                 (1.0 - reduced_motion);
    float phase = hash11(key + 71.0) * 6.28318530718 + time;
    float2 shard_axis = float2(cos(phase), sin(phase));
    float2 shard_side = float2(-shard_axis.y, shard_axis.x);

    float size = lerp(1.6, 7.5, pow(hash11(key + 19.0), 2.2)) *
                 field.color_size.a;
    float aspect = lerp(.16, .48, hash11(key + 29.0));

    // Camera-facing flakes remain spatial particles, but their severe,
    // needle-like silhouettes read as etched wreckage rather than soft motes.
    float3 view = normalize(push.camera_position.xyz - center);
    float3 right = normalize(cross(float3(0,0,1), view));
    if (dot(right,right) < .01) right = float3(1,0,0);
    float3 up = normalize(cross(view, right));
    float2 flake = shard_axis * corner.x + shard_side * corner.y * aspect;
    float3 world = center + (right * flake.x + up * flake.y) * size;

    output.position = mul(push.view_projection, float4(world, 1));
    output.local = corner;
    output.world_position = world;
    output.material = float4(
        hash11(key + 41.0), field.shape_seed.z, size,
        hash11(key + 53.0));
    output.color = field.color_size.rgb;
    return output;
}

[shader("fragment")]
float4 debris_fragment(DebrisOutput input) : SV_Target {
    // Cut an asymmetric, chipped silhouette from the billboard.
    float edge = max(abs(input.local.x), abs(input.local.y));
    float chip = sin(input.local.x * 7.0 + input.material.x * 13.0) *
                 sin(input.local.y * 9.0 - input.material.w * 11.0);
    if (edge + chip * .10 > .91) discard;

    // One bone-white rim and two dry engraved cuts communicate rotation and
    // material while leaving most of the particle black.
    float rim_width = max(fwidth(edge) * 1.4, .035);
    float rim = smoothstep(.91 - rim_width, .91, edge);
    float hatch_a = 1.0 - smoothstep(.055, .11,
        abs(frac((input.local.x * 1.7 + input.local.y * .8) * 2.5 +
                 input.material.x) - .5));
    float hatch_b = 1.0 - smoothstep(.04, .09,
        abs(frac((input.local.x * -1.1 + input.local.y) * 1.8 +
                 input.material.w) - .5));
    float engraving = max(rim, max(hatch_a * .48, hatch_b * .30));

    float distance_to_eye = length(push.camera_position.xyz-input.world_position);
    float distance_fade = saturate(1.25-distance_to_eye/4200.0);
    float alpha = engraving * input.material.y * distance_fade;
    if (alpha < .018) discard;

    float3 bone = lerp(input.color, float3(.82,.80,.73), rim * .72);
    return float4(srgb_to_linear(bone), alpha);
}
