struct CombatPush {
    float4x4 view_projection;
    // xy = framebuffer viewport size, z = deterministic mission seed,
    // w = authoritative fixed-step Dark time (zero outside the Dark).
    float4 viewport_seed;
    // xy = halo offset in normalized clip space, z = halo intensity.
    float4 glow;
    // xyz = world-space camera origin. Kept in the shared push block so the
    // Dark can raymarch implicit sections inside its depth-tested proxy mesh.
    float4 camera_position;
    // xyz = expedition lamp in world space, w = enabled intensity.
    float4 dark_light_position;
};
[[vk::push_constant]] ConstantBuffer<CombatPush> push;

struct DarkRenderGlobals {
    float4 anchor_band;
    float4 fleet_depth;
    float4 environment;
    float4 presentation;
};
[[vk::binding(1,0)]] ConstantBuffer<DarkRenderGlobals> dark;

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

struct VertexInput {
    float3 position : POSITION;
    float4 color : COLOR0;
};
struct VertexOutput {
    float4 position : SV_Position;
    float4 color : COLOR0;
    float3 world_position : TEXCOORD0;
    float4 dark_course : TEXCOORD1;
};

float black_fog_density(float3 p) {
    float strata = .5+.5*sin(dot(p,float3(.0061,.0043,.0053))+
        sin(dot(p,float3(-.0027,.0059,.0031)))*1.7+
        push.viewport_seed.z*.0013);
    return lerp(.46,1.82,strata);
}

float black_fog_visibility(float3 world_position) {
    float3 eye = push.camera_position.xyz;
    float3 sightline = world_position-eye;
    float distance_to_observer = length(sightline);
    // Integrate a few deterministic density samples along the viewing ray.
    // This allows a black stratum between camera and target to obscure it even
    // when the target's own position lies in a clearer pocket.
    float integrated_density =
        black_fog_density(eye+sightline*.28)*.30+
        black_fog_density(eye+sightline*.56)*.40+
        black_fog_density(eye+sightline*.82)*.30;
    // Preserve a navigable near bubble; beyond it, optical depth accumulates
    // rapidly enough that distant contacts become uncertain silhouettes.
    float optical_depth = max(distance_to_observer-900.0,0.0)*.00138*integrated_density;
    return saturate(exp2(-optical_depth));
}

struct LineVertexInput {
    // x = endpoint interpolation, y = ribbon side (-1 or +1).
    float2 parameter : POSITION;
    float3 start_position : TEXCOORD0;
    float3 end_position : TEXCOORD1;
    float4 color : COLOR0;
    float4 dark_course : TEXCOORD2;
};

[shader("vertex")]
VertexOutput line_vertex(LineVertexInput input) {
    VertexOutput output;
    float4 start_clip = mul(push.view_projection, float4(input.start_position, 1));
    float4 end_clip = mul(push.view_projection, float4(input.end_position, 1));
    output.position = lerp(start_clip, end_clip, input.parameter.x);
    output.world_position = lerp(input.start_position,input.end_position,input.parameter.x);
    float2 start_ndc = start_clip.xy / max(start_clip.w, .0001);
    float2 end_ndc = end_clip.xy / max(end_clip.w, .0001);
    float2 screen_direction = (end_ndc - start_ndc) * push.viewport_seed.xy;
    float direction_length = max(length(screen_direction), .0001);
    float2 perpendicular = float2(-screen_direction.y, screen_direction.x) / direction_length;
    float half_width_px = lerp(.72, 1.08, step(.70, input.color.a));
    float2 ribbon_ndc = perpendicular * input.parameter.y * half_width_px * 2.0 / max(push.viewport_seed.xy, 1.0);
    output.position.xy += ribbon_ndc * output.position.w;
    output.color = input.color;
    output.dark_course = float4(
        lerp(input.dark_course.x,input.dark_course.y,input.parameter.x),
        lerp(input.dark_course.z,input.dark_course.w,input.parameter.x),
        input.parameter.x,input.parameter.y);
    // Minor construction/grid lines are intentionally low-alpha. Let their
    // depth in the perspective projection attenuate them while semantic and
    // major grid marks remain stable and readable.
    float minor_line = 1.0 - step(.30, input.color.a);
    float distance_fade = saturate(1.35 - output.position.w / 3600.0);
    output.color.a *= lerp(1.0, distance_fade, minor_line);
    if (push.glow.z > 0) {
        output.position.xy += push.glow.xy * output.position.w;
        float emission = step(.86, input.color.a);
        output.color.a *= push.glow.z * emission;
    }
    return output;
}

struct ContactVertexInput {
    float2 local_position : POSITION;
    float3 instance_position : TEXCOORD0;
    // xy = cos/sin heading, z = role scale.
    float4 facing_scale : TEXCOORD1;
    float4 color : COLOR0;
};

[shader("vertex")]
VertexOutput contact_vertex(ContactVertexInput input) {
    VertexOutput output;
    float2 local = input.local_position * input.facing_scale.z;
    float2 rotated = float2(
        local.x * input.facing_scale.x - local.y * input.facing_scale.y,
        local.x * input.facing_scale.y + local.y * input.facing_scale.x
    );
    // Preserve heading in XY while canting the glyph a bounded amount toward
    // the observer so extreme orbital views never collapse it edge-on.
    float3 world = input.instance_position + float3(rotated, local.y * input.facing_scale.w);
    float4 center_clip = mul(push.view_projection, float4(input.instance_position, 1));
    output.position = mul(push.view_projection, float4(world, 1));
    output.world_position = world;
    // Enforce a small screen-space floor for distant command contacts. This
    // changes only presentation size; picking remains a world-space ray test.
    float2 center_ndc = center_clip.xy / center_clip.w;
    float2 vertex_ndc = output.position.xy / output.position.w;
    float2 delta_ndc = vertex_ndc - center_ndc;
    float target_ndc = length(input.local_position) * 8.0 / max(min(push.viewport_seed.x, push.viewport_seed.y), 1.0);
    float expansion = min(2.5, max(1.0, target_ndc / max(length(delta_ndc), .00001)));
    output.position.xy = (center_ndc + delta_ndc * expansion) * output.position.w;
    output.color = input.color;
    output.dark_course = 0;
    return output;
}

[shader("vertex")]
VertexOutput vertex_main(VertexInput input) {
    VertexOutput output;
    output.position = mul(push.view_projection, float4(input.position, 1));
    output.world_position = input.position;
    output.color = input.color;
    output.dark_course = 0;
    if (push.glow.z > 0) {
        output.position.xy += push.glow.xy * output.position.w;
        // Construction lines and the reference grid stay matte. Only strong
        // semantic marks emit into the additive halo pass.
        float emission = step(.86, input.color.a);
        output.color.a *= push.glow.z * emission;
    }
    return output;
}

[shader("fragment")]
float4 fragment_main(VertexOutput input) : SV_Target {
    float visibility = black_fog_visibility(input.world_position);
    float3 color=input.color.rgb;
    float alpha=input.color.a;
    bool depth_course=dark.presentation.z>.5 &&
        any(abs(input.dark_course.xy)>float2(.0001,.0001));
    if (depth_course) {
        float band_spacing=max(dark.anchor_band.w/44.0,.01);
        float band_phase=input.dark_course.x/band_spacing;
        float crossing_distance=abs(frac(band_phase+.5)-.5);
        float crossing=1.0-smoothstep(.035,.085,crossing_distance);
        float coherence=dark.environment.y;
        float3 crossing_color=coherence>=1.0
            ?float3(.78,.34,.24):coherence>=.72?float3(.80,.67,.37):color;
        color=lerp(color,crossing_color,crossing*.88);
        alpha=max(alpha,crossing*.92);
    }
    return float4(srgb_to_linear(color)*visibility,alpha*visibility);
}

struct TerrainVertexInput {
    float3 local_position : POSITION;
    float3 center : TEXCOORD0;
    // x = radius, y = half-height, z = kind, w = seed.
    float4 shape : TEXCOORD1;
    // x = noise scale, y = density, z = alpha, w = sensor confidence.
    float4 style : TEXCOORD2;
    float3 color : COLOR0;
};
struct TerrainOutput {
    float4 position : SV_Position;
    float3 local_position : TEXCOORD0;
    float4 terrain : TEXCOORD1;
    float4 color : COLOR0;
    nointerpolation float3 local_camera : TEXCOORD2;
    nointerpolation float3 world_center : TEXCOORD3;
    nointerpolation float3 world_scale : TEXCOORD4;
    nointerpolation float sensor_confidence : TEXCOORD5;
};

struct TerrainFragmentOutput {
    float4 color : SV_Target;
    float depth : SV_Depth;
};

[shader("vertex")]
TerrainOutput terrain_vertex(TerrainVertexInput input) {
    TerrainOutput output;
    float3 world = input.center + float3(
        input.local_position.xy * input.shape.x,
        input.local_position.z * input.shape.y
    );
    output.position = mul(push.view_projection, float4(world, 1));
    output.local_position = input.local_position;
    output.terrain = float4(input.shape.z, input.shape.w, input.style.x, input.style.y);
    output.color = float4(input.color, input.style.z);
    output.local_camera = (push.camera_position.xyz - input.center) /
        max(float3(input.shape.x, input.shape.x, input.shape.y), .0001);
    output.world_center = input.center;
    output.world_scale = float3(input.shape.x, input.shape.x, input.shape.y);
    output.sensor_confidence = input.style.w;
    return output;
}

float hash31(float3 p) {
    p = frac(p * .1031);
    p += dot(p, p.yzx + 33.33);
    return frac((p.x + p.y) * p.z);
}

static const float DARK_VOLUME_MEMBRANE = 3.0;
static const float DARK_VOLUME_DOOR_ALIGNMENT = 10.0;
static const float DARK_VOLUME_MEMBRANE_SURVEY = 11.0;
static const float DARK_VOLUME_GENERATED_CREATURE = 12.0;

struct CreatureGene {
    float4 meta;
    float4 center;
    float4 radius;
    float4 rotation_a;
    float4 rotation_b;
    float4 motion_a;
    float4 motion_b;
};
[[vk::binding(0,0)]] StructuredBuffer<CreatureGene> creature_genes;

float creature_smooth_min(float a,float b,float k) {
    if (k<=0.0) return min(a,b);
    float h=saturate(.5+.5*(b-a)/k);
    return lerp(b,a,h)-k*h*(1.0-h);
}
float creature_smooth_max(float a,float b,float k) {return -creature_smooth_min(-a,-b,k);}
float4 creature_rotate_pair(float4 p,int a,int b,float angle) {
    float c=cos(angle),s=sin(angle),va=p[a],vb=p[b];
    p[a]=c*va+s*vb;p[b]=-s*va+c*vb;return p;
}
float creature_primitive(CreatureGene gene,float4 point,float time,int detail) {
    float4 center=gene.center,radius=max(gene.radius,.04);
    int motion=(int)gene.motion_a.x,axis=(int)gene.motion_a.y;
    float phase=gene.motion_a.z+time*gene.motion_a.w,amplitude=gene.motion_b.x;
    if (motion==1) radius*=clamp(1.0+amplitude*sin(phase),.55,1.45);
    else if (motion==2) center[axis]+=amplitude*sin(phase);
    else if (motion==3) {center[axis]+=amplitude*sin(phase);center[(axis+1)&3]+=amplitude*cos(phase);}
    else if (motion==4) {center.x+=amplitude*sin(phase)*.55;center.y+=amplitude*sin(phase+.83)*.55;center.z+=amplitude*sin(phase+1.66)*.55;center.w+=amplitude*sin(phase+2.49)*.55;}
    float4 p=point-center;
    p=creature_rotate_pair(p,0,1,gene.rotation_a.x);p=creature_rotate_pair(p,0,2,gene.rotation_a.y);
    p=creature_rotate_pair(p,0,3,gene.rotation_a.z);p=creature_rotate_pair(p,1,2,gene.rotation_a.w);
    p=creature_rotate_pair(p,1,3,gene.rotation_b.x);p=creature_rotate_pair(p,2,3,gene.rotation_b.y);
    float minimum_radius=min(min(radius.x,radius.y),min(radius.z,radius.w));
    float4 q=p/radius;int primitive=(int)gene.meta.x;float smoothing=gene.rotation_b.z;
    if (primitive==0) return (length(q)-1.0)*minimum_radius;
    if (primitive==1) {
        int longest=radius.y>radius.x?1:0;longest=radius.z>radius[longest]?2:longest;longest=radius.w>radius[longest]?3:longest;
        float axial=max(abs(q[longest])-.58,0.0);float radial=dot(q,q)-q[longest]*q[longest];
        return (sqrt(radial+axial*axial)-.64)*minimum_radius;
    }
    if (primitive==2) {float4 o=max(abs(q)-.82,0.0);float largest=max(max(abs(q.x),abs(q.y)),max(abs(q.z),abs(q.w)));return (length(o)+min(largest-.82,0.0)-.18)*minimum_radius;}
    if (primitive==3) {float ring=length(q.xy)-.62;return (length(float3(ring,q.z,q.w))-.38)*minimum_radius*2.2;}
    if (primitive==4) {float sum=dot(q*q,q*q);return (pow(sum,.25)-1.0)*minimum_radius;}
    if (primitive==5) {int longest=radius.y>radius.x?1:0;longest=radius.z>radius[longest]?2:longest;longest=radius.w>radius[longest]?3:longest;float4 l=q,r=q;l[longest]-=.48;r[longest]+=.48;return creature_smooth_min(length(l)-.72,length(r)-.72,smoothing*.6)*minimum_radius;}
    if (primitive==6) {float2 rings=float2(length(q.xy)-.64,length(q.zw)-.64);return (length(rings)-.28)*minimum_radius*1.8;}
    if (primitive==7) {int thin=radius.y<radius.x?1:0;thin=radius.z<radius[thin]?2:thin;thin=radius.w<radius[thin]?3:thin;float broad=dot(q,q)-q[thin]*q[thin];return max(sqrt(broad)-1.0,abs(q[thin])-.18)*minimum_radius;}
    if (primitive==8) {float d=1000.0;[unroll] for(int arm=0;arm<4;++arm){float axial=max(abs(q[arm])-.70,0.0);float radial=dot(q,q)-q[arm]*q[arm];d=creature_smooth_min(d,sqrt(radial+axial*axial)-.22,smoothing*.35);}return d*minimum_radius;}
    float fractal_phase=gene.motion_b.w+(motion==5?amplitude*4.5*sin(phase):0.0);
    float fold_scale=clamp(gene.rotation_b.w*(motion==5?1.0+amplitude*.32*cos(phase):1.0),1.35,1.95);
    int iterations=min((int)gene.meta.w,detail);
    if (primitive==9) {float4 z=q;float d=(length(z)-.20)*minimum_radius,scale=1.0;[loop] for(int i=0;i<5;++i){if(i>=iterations)break;float a=fractal_phase+i*.91,c=cos(a),s=sin(a);z.xy=float2(c*z.x-s*z.y,s*z.x+c*z.y);a*=.73;c=cos(a);s=sin(a);z.zw=float2(c*z.z-s*z.w,s*z.z+c*z.w);z=abs(z);if(z.x<z.y)z.xy=z.yx;if(z.z<z.w)z.zw=z.wz;z=(z-float4(.48,.31,.25,.17))*fold_scale;scale*=fold_scale;float bud=(length(z)-(.26-i*.018))/scale*minimum_radius;d=creature_smooth_min(d,bud,smoothing*.38);}return d;}
    if (primitive==10) {float4 z=q;[loop] for(int i=0;i<5;++i){if(i>=iterations)break;float a=fractal_phase+i*1.17,c=cos(a),s=sin(a);z.xz=float2(c*z.x-s*z.z,s*z.x+c*z.z);z=abs(z)-float4(.16,.11,.08,.06);}float corr=abs(z.x+z.y-z.z-z.w)*.055;return (abs(length(q)-.72)-(.105+corr))*minimum_radius;}
    return 1000.0;
}
float generated_creature_sdf(float3 p,float slice,int base,int count,float time,int detail) {
    float distance=1000.0;[loop] for(int i=0;i<12;++i){if(i>=count)break;CreatureGene gene=creature_genes[base+i];float operand=creature_primitive(gene,float4(p,slice),time,detail);float smoothness=gene.rotation_b.z;if(gene.motion_b.z>0.0){float td=(abs(time-gene.motion_b.y)-gene.motion_b.z)*.18;operand=creature_smooth_max(operand,td,smoothness);}int combine=(int)gene.meta.y;if(i==0)distance=operand;else if(combine==0)distance=creature_smooth_min(distance,operand,smoothness);else if(combine==1)distance=min(distance,operand);else if(combine==2)distance=creature_smooth_max(distance,-operand,smoothness);else if(combine==3)distance=max(distance,-operand);else if(combine==4)distance=creature_smooth_max(distance,operand,smoothness);else distance=max(distance,operand);}return distance;
}

float4 dark_clifford_coordinates(float3 p, float slice, float seed) {
    // The field is a 5D world-tube: four spatial coordinates plus deterministic
    // simulation time. Seeded rates keep each lamina's evolution persistent and
    // replayable instead of tying it to render time.
    float temporal_rate = lerp(.012, .031, frac(seed * .6180339));
    float angle = seed * .071 + push.viewport_seed.w * temporal_rate;
    float c = cos(angle), s = sin(angle);
    return float4(c * p.x - s * p.z, p.y, s * p.x + c * p.z, slice);
}

float dark_clifford_envelope(float4 q) {
    float2 rings = float2(length(q.xy) - .58, length(q.zw) - .58);
    return length(rings) - .205;
}

float dark_laminar_fractal_sdf(float3 p, float slice, float seed) {
    // The Clifford torus remains the lawful 4D boundary, but it is no longer
    // the visible skin. Three recursively gated laminar levels inhabit the
    // envelope. Their frequencies approximately double while their thickness
    // halves, preserving a readable hierarchy instead of uniform noise.
    float4 q = dark_clifford_coordinates(p, slice, seed);
    float2 rings = float2(length(q.xy) - .58, length(q.zw) - .58);
    float temporal_rate = lerp(.017, .043, frac(seed * .4142136));
    float temporal_phase = push.viewport_seed.w * temporal_rate;
    float w_phase = q.w * 5.4 + seed * .037 + temporal_phase;

    float warp0 = sin(q.x * 4.1 + q.z * 2.7 + w_phase) * .040
                + sin(q.y * 3.3 - q.z * 3.8 - w_phase * .63) * .025;
    // These are broad planes intersecting the toroidal volume, not contour
    // bands following its tube. Their clipped edges imply the envelope while
    // their faces read as torn strata.
    float primary_axis = q.y * .82 + q.z * .28 + warp0;
    float primary_a = abs(primary_axis - sin(w_phase * .71) * .115) - .017;
    float primary_b = abs(q.x * .46 - q.y * .23 + q.z * .75
                        + cos(w_phase * .83 + q.y * 2.2) * .135) - .013;
    float primary_c = abs(q.x * -.31 + q.y * .71 + q.z * .54
                        - sin(w_phase * 1.07 - q.x * 2.0) * .155) - .010;
    float level0 = min(primary_a, min(primary_b, primary_c));

    // Child strata can only exist in the correspondence neighborhood of a
    // primary sheet. Along W they migrate between parents and form reversible
    // bridges instead of crawling as a surface texture.
    float child_phase = q.x * 15.0 - q.z * 10.0
                      + sin(q.x * 7.0 + q.y * 5.0 + w_phase) * 1.15
                      + temporal_phase * .37;
    float child_a = abs(sin(child_phase + w_phase * 1.6)) * .052 - .0055;
    float child_b = abs(sin(child_phase * .83 - q.z * 6.0 - w_phase * 1.25)) * .047 - .0048;
    float parent_gate = abs(primary_axis) - .175;
    float level1 = max(min(child_a, child_b), parent_gate);

    // The final level is sparse and parent-gated. It supplies seams and nested
    // apertures without turning the entire field into a fractal thicket.
    float fine_phase = q.x * 29.0 + q.z * 25.0
                     + sin(q.y * 13.0 - q.z * 9.0 + w_phase * 1.9) * 1.4
                     - temporal_phase * .61;
    float fine_sheet = abs(sin(fine_phase)) * .030 - .0026;
    float child_gate = min(abs(sin(child_phase + w_phase * 1.6)),
                           abs(sin(child_phase * .83 - q.z * 6.0 - w_phase * 1.25))) - .43;
    float sparse_gate = sin(q.x * 9.0 + seed * .11) *
                        sin(q.y * 8.0 - q.w * 5.0) - .18;
    float level2 = max(fine_sheet, max(child_gate * .10, sparse_gate * .045));

    float lamina = min(level0, min(level1, level2));

    // Remove broad, deterministic angular sectors. Without this negative-space
    // gate even thin sheets collectively redraw the entire toroidal silhouette.
    float theta_xy = atan2(q.y,q.x);
    float theta_zw = atan2(q.w,q.z);
    float sector_signal = sin(theta_xy*2.0+seed*.021)*.64
                        + sin(theta_zw*3.0-seed*.016)*.36;
    lamina = max(lamina,(sector_signal-.10)*.055);

    // Condition-selected cavities cut through every recursive level. Their W
    // motion makes small holes align into a large passage and then separate.
    float3 aperture_center = float3(
        sin(w_phase * .77 + seed * .013) * .18,
        cos(w_phase * .61 - seed * .019) * .14,
        sin(w_phase * .93) * .12);
    float3 aperture_scale = float3(.72, 1.08, .64);
    float aperture = length((p - aperture_center) * aperture_scale) - .205;
    float cavity_a = length(float3(
        q.x + sin(q.w * 4.0 + seed * .03) * .22,
        q.y - cos(q.w * 3.3 - seed * .02) * .18,
        q.z) * float3(1.0, 1.35, .82)) - .105;
    float cavity_b = length(float3(
        q.x - cos(q.w * 3.7 - seed * .017) * .24,
        q.y,
        q.z + sin(q.w * 4.4 + seed * .021) * .19)
        * float3(1.25, .86, 1.0)) - .082;
    lamina = max(lamina, -min(aperture, min(cavity_a, cavity_b)));

    return max(lamina, dark_clifford_envelope(q));
}

float dark_membrane_survey_sdf(float3 p, float slice, float seed, float confidence) {
    // Survey uncertainty displaces the inferred field, never the physical one.
    // The smallest strata disagree first; the primary structure remains useful.
    float uncertainty = 1.0 - saturate(confidence);
    float3 displacement = float3(
        sin(p.y * 13.0 + slice * 7.0 + seed * .13),
        sin(p.z * 11.0 - slice * 5.0 - seed * .09),
        cos(p.x * 15.0 + slice * 6.0 + seed * .07)) * (.004 + uncertainty * .016);
    return dark_laminar_fractal_sdf(p + displacement, slice, seed)
         - (.002 + uncertainty * .004);
}

float dark_volume_sdf(float3 p, float slice, float seed, float kind, float survey_confidence) {
    if (kind > 11.5) return generated_creature_sdf(p,slice,(int)seed,(int)survey_confidence,push.viewport_seed.w,5);
    if (kind < 3.5) return dark_laminar_fractal_sdf(p, slice, seed);
    float phase = seed * .071;
    if (kind < 4.5) {
        // Wake film: a broad, nearly weightless lamina with fibrous buckling.
        return abs(p.z + sin(p.x * 5.0 + phase) * .045 + sin(p.y * 7.0 - phase) * .025)
             - (.035 + (1.0 - saturate(length(p.xy))) * .025);
    }
    if (kind < 5.5) {
        // Lantern grazer: asymmetric pressure body with two feeding cavities.
        float body = length(float3(p.x * .78, p.y * 1.18, p.z)) - .58;
        float cavity_a = length(p - float3(.30,.08,.02)) - .24;
        float cavity_b = length(p - float3(-.18,-.24,.10)) - .18;
        return max(body, -min(cavity_a,cavity_b));
    }
    if (kind < 6.5) {
        // Hush colony: several joined cells share one continuous membrane.
        float a=length(p-float3(-.28,.04,0))-.38;
        float b=length(p-float3(.24,.18,.08))-.34;
        float c=length(p-float3(.08,-.28,-.10))-.31;
        return min(a,min(b,c)) + sin((p.x+p.y+p.z)*13.0+phase)*.018;
    }
    if (kind < 7.5) {
        // Shear hunter: a narrow bilateral wedge with an axial cut.
        float blade=max(abs(p.y)-(.12+(.72-abs(p.x))*.24),abs(p.z)-(.10+(.72-abs(p.x))*.18));
        float extent=abs(p.x)-.72;
        float body=max(blade,extent);
        float axial=length(p.yz)-.055;
        return max(body,-axial);
    }
    if (kind < 8.5) {
        // Grave reef: thick ossified shell with lawful perforation channels.
        float shell=abs(length(float3(p.x*.88,p.y,p.z*1.12))-.58)-.095;
        float pores=min(length(p.xy)-.12,min(length(p.yz)-.10,length(p.xz)-.11));
        return max(shell,-pores);
    }
    if (kind < 9.5) {
        // Expedition pressure hull. Unlike the linework laid over it, this
        // union has real volume and writes the same ray-hit depth as organisms.
        float hull = length(float3(p.x*.48,p.y*1.92,p.z*1.92))-.36;
        float reactor = length(float3((p.x+.30)*1.2,p.y,p.z))-.25;
        float nose = length(float3((p.x-.48)*.82,p.y*2.55,p.z*2.55))-.23;
        float3 qa = abs(p-float3(.02,.43,0))-float3(.34,.105,.035);
        float radiator_a = length(max(qa,0))+min(max(qa.x,max(qa.y,qa.z)),0);
        float3 qb = abs(p-float3(.02,-.43,0))-float3(.34,.105,.035);
        float radiator_b = length(max(qb,0))+min(max(qb.x,max(qb.y,qb.z)),0);
        float3 qm = abs(p-float3(.08,0,.34))-float3(.045,.045,.24);
        float mast = length(max(qm,0))+min(max(qm.x,max(qm.y,qm.z)),0);
        return min(min(hull,reactor),min(nose,min(radiator_a,min(radiator_b,mast))));
    }
    if (kind < 10.5) {
        // A door is a temporary alignment between two membrane collars, not a
        // freestanding portal ring. Nested apertures share an axis while torn
        // sheet edges and sparse bridges preserve the laminar grammar.
        float radial = length(p.xy);
        float warp = sin(atan2(p.y,p.x)*5.0 + phase) * .025;
        float near_sheet = max(abs(p.z - .12 + warp) - .026,
                               abs(radial - .58) - .14);
        float far_sheet = max(abs(p.z + .13 - warp*.7) - .021,
                              abs(radial - .43) - .105);
        float bridge_pattern = abs(sin(atan2(p.y,p.x)*7.0 + phase));
        float bridges = max(abs(radial-.50)-.075,
                            max(abs(p.z)-.15, bridge_pattern*.09-.018));
        return min(near_sheet,min(far_sheet,bridges));
    }
    return dark_membrane_survey_sdf(p, slice, seed, survey_confidence);
}

float3 dark_4d_normal(float3 p, float slice, float seed) {
    const float e = .006;
    return normalize(float3(
        dark_laminar_fractal_sdf(p + float3(e, 0, 0), slice, seed) - dark_laminar_fractal_sdf(p - float3(e, 0, 0), slice, seed),
        dark_laminar_fractal_sdf(p + float3(0, e, 0), slice, seed) - dark_laminar_fractal_sdf(p - float3(0, e, 0), slice, seed),
        dark_laminar_fractal_sdf(p + float3(0, 0, e), slice, seed) - dark_laminar_fractal_sdf(p - float3(0, 0, e), slice, seed)
    ));
}

float3 dark_volume_normal(float3 p, float slice, float seed, float kind, float scale) {
    const float e=.006;
    return normalize(float3(
        dark_volume_sdf(p+float3(e,0,0),slice,seed,kind,scale)-dark_volume_sdf(p-float3(e,0,0),slice,seed,kind,scale),
        dark_volume_sdf(p+float3(0,e,0),slice,seed,kind,scale)-dark_volume_sdf(p-float3(0,e,0),slice,seed,kind,scale),
        dark_volume_sdf(p+float3(0,0,e),slice,seed,kind,scale)-dark_volume_sdf(p-float3(0,0,e),slice,seed,kind,scale)
    ));
}

float3 dark_thin_film_spectrum(
    float thickness_nm,
    float cos_incident,
    float cos_view,
    float spectral_strength)
{
    // Optical path through a clear polymer film over a reflective inclusion.
    // RGB wavelengths are sufficient at this delivery size; the half-wave
    // phase reversal approximates reflection at the denser flake boundary.
    const float film_ior = 1.48;
    const float3 wavelength_nm = float3(650.0, 530.0, 460.0);
    float angular_path = max((cos_incident + cos_view) * .5, .08);
    float3 phase = 12.5663706 * film_ior * thickness_nm * angular_path /
                   wavelength_nm + 3.1415927;
    float3 interference = .5 + .5 * cos(phase);
    // A silver substrate keeps destructive wavelengths from becoming black.
    // Slight channel overlap avoids synthetic, fully saturated RGB specks.
    float3 broadened = interference * .72 + interference.yzx * .18 +
                       interference.zxy * .10;
    return lerp(float3(.72, .76, .78), broadened, spectral_strength);
}

float3 dark_lamina_microbeads(
    float3 surface_position,
    float3 view_direction,
    float3 lamp_direction,
    float lamp_irradiance,
    float slice,
    float seed,
    float kind)
{
    // Only the physical membrane carries this material. Survey traces, doors,
    // wake films, organisms, and the expedition retain their own responses.
    if (kind < 2.5 || kind > 3.5) return 0.0;

    const float3 engraving_light = normalize(float3(-.46,-.58,.67));
    // A single seeded XYZ point field fills the lamina material. There are no
    // authored depth planes: the current ray hit merely reveals the bead cell
    // intersected by this 4D section.
    float3 bead_coordinate = surface_position * 112.0 +
        float3(slice * 37.0,slice * -23.0,slice * 31.0);
    float3 cell = floor(bead_coordinate);
    float occupancy = hash31(cell + seed * float3(.017,.037,.061));
    if (occupancy < .996) return 0.0;

    // Occupied cells contain one genuinely tiny round bead, not a colored
    // voxel. Stable sub-cell centers prevent a regular glitter lattice.
    float3 bead_center = float3(
        hash31(cell.yzx + seed * .113),
        hash31(cell.zxy - seed * .079),
        hash31(cell.xyz + seed * .137));
    float bead_distance = length(frac(bead_coordinate)-bead_center);
    float bead_mask = 1.0-smoothstep(.18,.32,bead_distance);
    if (bead_mask <= 0.0) return 0.0;

    float3 bead_normal = normalize(float3(
        hash31(cell.yzx + seed * .181),
        hash31(cell.zxy - seed * .149),
        hash31(cell.xyz + seed * .223)) * 2.0 - 1.0);
    bead_normal *= sign(dot(bead_normal,view_direction));

    float3 ambient_half = normalize(view_direction+engraving_light);
    float3 lamp_half = normalize(view_direction+lamp_direction);
    float ambient_alignment = pow(saturate(dot(bead_normal,ambient_half)),36.0);
    float lamp_alignment = pow(saturate(dot(bead_normal,lamp_half)),24.0);
    float response = ambient_alignment*.48 +
        lamp_alignment*sqrt(max(lamp_irradiance,0.0))*2.40;
    if (response <= .0001) return 0.0;

    float thickness_nm = lerp(185.0,880.0,
        hash31(cell * float3(.67,1.23,.89) + seed * .031 + slice));
    float active_light = lamp_alignment*lamp_irradiance >
                         ambient_alignment*.05
        ? saturate(dot(bead_normal,lamp_direction))
        : saturate(dot(bead_normal,engraving_light));
    float cos_view = saturate(dot(bead_normal,view_direction));
    return dark_thin_film_spectrum(
        thickness_nm,active_light,cos_view,.96) * bead_mask * response;
}

float3 dark_organism_holo_flakes(
    float3 surface_position,
    float3 ray_direction,
    float3 view_direction,
    float3 light_direction,
    float slice,
    float seed,
    float kind,
    float scale)
{
    // Organisms alone carry this response. Membranes, wake films, doors, and
    // the expedition remain materially distinct.
    if (kind < 4.5 || (kind > 8.5 && kind < 11.5)) return 0.0;

    float3 result = 0.0;
    float3 half_vector = normalize(view_direction + light_direction);
    [unroll]
    for (int layer = 0; layer < 3; ++layer) {
        // Follow the viewing ray beneath the visible intersection. These are
        // suspended inclusions, not noise painted over the front surface.
        float depth = .012 + float(layer) * .019;
        float3 p = surface_position + ray_direction * depth;
        if (dark_volume_sdf(p, slice, seed, kind, scale) > .006) continue;

        // Including the 4D slice in the cell address makes particles enter and
        // leave the observed cross-section lawfully as W changes.
        float3 cell = floor(p * 78.0 + float3(slice * 29.0, slice * -17.0, slice * 23.0));
        float occupancy = hash31(cell + seed * float3(.013, .029, .047));
        if (occupancy < .982) continue;

        float3 flake_normal = normalize(float3(
            hash31(cell.yzx + seed * .071),
            hash31(cell.zxy - seed * .053),
            hash31(cell.xyz + seed * .097)) * 2.0 - 1.0);
        flake_normal *= sign(dot(flake_normal, view_direction));
        float alignment = pow(saturate(dot(flake_normal, half_vector)), 48.0);
        float thickness_nm = lerp(220.0, 760.0,
            hash31(cell * float3(.73,1.17,.91) + seed * .019 + slice));
        float cos_incident = saturate(dot(flake_normal,light_direction));
        float cos_view = saturate(dot(flake_normal,view_direction));
        float attenuation = exp2(-float(layer) * .82);
        result += dark_thin_film_spectrum(thickness_nm,cos_incident,cos_view,.46) *
                  alignment * attenuation;
    }
    return result;
}

[shader("fragment")]
TerrainFragmentOutput terrain_fragment(TerrainOutput input) {
    TerrainFragmentOutput output;
    float kind = input.terrain.x;
    float seed = input.terrain.y;
    float scale = input.terrain.z;
    float density = input.terrain.w;
    if (kind > 2.5) {
        // Membranes are true sections of a fixed 4D field: density carries the
        // normalized coordinate along the hidden W axis. Organism manifestation
        // retains its narrower correspondence band and separate 4D rules.
        float slice_extent = (kind < 3.5 || kind > 10.5) ? 1.0 : .72;
        float slice = (density * 2.0 - 1.0) * slice_extent;
        float3 direction = normalize(input.local_position - input.local_camera);
        float3 sample_position = input.local_position + direction * .012;
        bool hit = false;
        [loop]
        for (int step_index = 0; step_index < 52; ++step_index) {
            float distance_to_field = dark_volume_sdf(sample_position, slice, seed, kind, scale);
            if (abs(distance_to_field) < .012) { hit = true; break; }
            sample_position += direction * max(abs(distance_to_field) * .58, .009);
            if (dot(sample_position, sample_position) > 1.18) break;
        }
        if (!hit) discard;
        if (kind > 11.5) {
            // A weak fix yields an incomplete engraved plate rather than a
            // simulation-perfect body. Gaps live in the creature's local 3D
            // surface, so they remain attached under camera orbit instead of
            // reading as screen snow.
            float uncertainty = 1.0-saturate(input.sensor_confidence);
            float registration = hash31(floor(sample_position*float3(17.0,13.0,19.0))+seed);
            float striation = abs(sin(sample_position.x*29.0+sample_position.y*17.0
                                -sample_position.z*23.0+seed*.19));
            float retained = registration*.62+striation*.38;
            if (retained < uncertainty*.82) discard;
            // W separation changes the mark grammar before it changes the
            // lawful section geometry. Near intersection the plate connects;
            // farther inward/outward it separates into stable contour islands.
            float section_separation=saturate(abs(slice));
            float island=hash31(floor(sample_position*float3(9.0,11.0,7.0))+seed*.37);
            float arc=abs(sin(sample_position.x*19.0-sample_position.y*23.0+
                              sample_position.z*17.0+seed*.11));
            float manifestation_retained=lerp(1.0,max(island,arc*.72),section_separation);
            if (manifestation_retained < section_separation*.58) discard;
        }
        float3 normal = dark_volume_normal(sample_position, slice, seed, kind, scale);
        if (kind > 10.5 && kind < 11.5) {
            float confidence = saturate(scale);
            float uncertainty = 1.0-confidence;
            float trace_a = abs(sin(sample_position.x*37.0 + sample_position.y*19.0
                                  - sample_position.z*13.0 + seed*.17));
            float trace_b = abs(sin(sample_position.x*-23.0 + sample_position.y*31.0
                                  + sample_position.z*17.0 - seed*.11));
            float trace_width = .055 + fwidth(trace_a)*1.6;
            float registered = 1.0-smoothstep(trace_width,trace_width*2.2,trace_a);
            float duplicate = (1.0-smoothstep(trace_width*.8,trace_width*2.0,trace_b))*uncertainty;
            float gap_cell = hash31(floor(sample_position*float3(11.0,13.0,9.0))+seed);
            if (max(registered,duplicate)<.18 || gap_cell < (.12+uncertainty*.34)) discard;
            float3 hit_world = input.world_center + sample_position * input.world_scale;
            float4 hit_clip = mul(push.view_projection,float4(hit_world,1.0));
            float alpha = input.color.a * max(registered,duplicate*.65) *
                          lerp(.72,.42,uncertainty);
            output.color=float4(srgb_to_linear(input.color.rgb),alpha);
            output.depth=hit_clip.z/hit_clip.w;
            return output;
        }
        float light = saturate(dot(normal, normalize(float3(-.46, -.58, .67)))) * .7 + .3;
        // SDF ambient occlusion samples actual empty space along the surface
        // normal. Concave joins and correspondence bores retain less light;
        // exposed convex faces remain untouched. This is geometric depth
        // information, not a screen-space vignette.
        float occlusion = 0.0;
        [unroll]
        for (int ao_index=1; ao_index<=3; ++ao_index) {
            float ao_distance = float(ao_index)*.032;
            float clearance = dark_volume_sdf(
                sample_position+normal*ao_distance,slice,seed,kind,scale);
            occlusion += max(0.0,ao_distance-clearance)/float(ao_index);
        }
        float ambient_access = 1.0-saturate(occlusion*5.2);
        light *= lerp(.58,1.0,ambient_access);
        // A real point light rides with the expedition. Convert it into each
        // implicit volume's coordinates so normal response and attenuation
        // remain spatial under non-uniform scaling and camera orbit.
        float3 dark_light_local = (push.dark_light_position.xyz-input.world_center) /
            max(input.world_scale,.0001);
        float3 to_dark_light = dark_light_local-sample_position;
        float dark_light_distance = length(to_dark_light);
        float dark_light_falloff = exp2(-dark_light_distance*dark_light_distance*.42);
        float dark_light = saturate(dot(normal,normalize(to_dark_light))) *
            dark_light_falloff * push.dark_light_position.w;
        light = saturate(light + dark_light*1.15);
        // Broader, slower cuts on the hero remain readable after the viewport
        // is composited into the command UI. Their phase is evaluated in local
        // 3D coordinates, so orbiting reveals the marks wrapping the surface.
        float cut_scale = kind < 3.5 ? .72 : .44;
        float contour_phase = (sample_position.x * 71.0 + sample_position.y * 39.0
                            + sample_position.z * 23.0) * cut_scale + seed
                            + sin(sample_position.y * 8.7 + seed * .11) * .82
                            + sin(sample_position.z * 13.1 - seed * .07) * .43;
        float crosscut_phase = (sample_position.x * -31.0 + sample_position.y * 53.0
                             - sample_position.z * 41.0) * cut_scale + seed * .37
                             + sin(sample_position.x * 10.3 - seed * .05) * .71;
        float contour_width = max(fwidth(contour_phase) * (kind < 3.5 ? .66 : .62), .024);
        float crosscut_width = max(fwidth(crosscut_phase) * (kind < 3.5 ? .52 : .60), .022);
        // Distance to the zero crossings produces narrow burin cuts. The old
        // crest threshold selected broad half-waves and read as painted bands.
        float contour = 1.0 - smoothstep(contour_width, contour_width * 2.7, abs(sin(contour_phase)));
        float crosscut = 1.0 - smoothstep(crosscut_width, crosscut_width * 2.5, abs(sin(crosscut_phase)));
        float reliable_marks=saturate(dark_light_falloff*dark.environment.x);
        if (kind<3.5) {
            float fragment_cell=hash31(floor(sample_position*float3(13.0,11.0,17.0))+seed);
            contour*=step(lerp(.76,.08,reliable_marks),fragment_cell);
            crosscut*=smoothstep(.42,.72,reliable_marks);
        }
        // Cross-hatching accumulates where the form turns from the controlled
        // light. Lit passages retain one confident contour family and more
        // untouched black between marks.
        float confidence=saturate(input.sensor_confidence);
        crosscut *= smoothstep(.38, .78, 1.0 - light) *
                    (kind>11.5?lerp(.12,1.0,confidence):1.0);
        float stipple = step(lerp(.998,.982,reliable_marks),
                             hash31(floor(sample_position * 92.0) + seed));
        // Low-confidence plates retain principal contours while secondary
        // cuts and stipple disappear first. A small object-space phase echo
        // supplies registration error without screen-space shimmer.
        float registration_echo=0.0;
        if (kind>11.5) {
            float echo_phase=contour_phase+(1.0-confidence)*.34;
            registration_echo=(1.0-smoothstep(contour_width,contour_width*2.7,
                                abs(sin(echo_phase))))*(1.0-confidence)*.42;
        }
        float ink = lerp(.30, 1.0, max(max(max(contour,registration_echo),
                         crosscut * .58), stipple * .72*confidence));
        float edge = 1.0 - smoothstep(.006, .026, abs(dark_volume_sdf(sample_position, slice, seed, kind, scale)));
        // The intersection is an etched solid, not smoke. Retain a quiet base
        // plate through its shadow side, then let contour cuts and grazing
        // light build toward bone white. This keeps occlusion readable against
        // black without flattening the lawful topology into a glowing blob.
        float cut = max(max(contour, crosscut * .58), stipple * .68);
        float material = lerp(.42, 1.0, saturate(light * ink));
        // The hero must survive the presentation pass's dark composite without
        // becoming a flat translucent plate.  Its extra opacity is still
        // evaluated only at the raymarched surface, so holes, back faces, and
        // overlaps continue to reveal true 3D self-occlusion while orbiting.
        float surface_floor = kind < 3.5 ? .46 : kind > 9.5 && kind < 11.5 ? .68 : .52;
        float alpha = input.color.a * material * max(edge, surface_floor);
        float fresnel = pow(1.0 - saturate(abs(dot(normal, -direction))), 3.0);
        bool special_solid = kind > 9.5 && kind < 11.5;
        float body_tone = (kind < 3.5 ? .10 : special_solid ? .34 : .15) +
            light * (kind < 3.5 ? .25 : special_solid ? .38 : .28);
        float engraved_tone = lerp(body_tone,special_solid ? 1.34 : kind < 3.5 ? 1.16 : 1.30,cut)+edge*.16;
        engraved_tone += fresnel * (kind < 3.5 ? .42 : special_solid ? .64 : .40);
        // Treat grazing incidence as a pale burin edge on the hero. This is
        // evaluated from the ray-hit normal, so exterior silhouettes and the
        // back rims of real tunnel cavities emerge and move under camera orbit.
        float grazing_ink = smoothstep(.12,.72,fresnel);
        if (kind < 3.5)
            engraved_tone = max(engraved_tone,.40+grazing_ink*.72);
        float3 hit_world = input.world_center + sample_position * input.world_scale;
        float4 hit_clip = mul(push.view_projection, float4(hit_world, 1.0));
        // Sparse semantic warmth belongs only to photons arriving from the
        // expedition lamp. Because `dark_light` is evaluated at the 3D hit,
        // the amber patch moves across curvature under orbit and cannot behave
        // like a screen-space bloom decal.
        float3 lamp_warmth = float3(.15,.095,.026) * dark_light *
            lerp(.42,1.0,max(cut,fresnel));
        float3 holo_flakes = dark_organism_holo_flakes(
            sample_position,direction,-direction,normalize(to_dark_light),
            slice,seed,kind,scale);
        // Keep color semantic and scarce: flakes are normally cold silver and
        // reveal their restrained spectrum only inside the expedition lamp.
        float flake_irradiance = dark_light_falloff * push.dark_light_position.w;
        holo_flakes *= sqrt(flake_irradiance) * .16;
        float3 lamina_glitter = dark_lamina_microbeads(
            sample_position,-direction,normalize(to_dark_light),
            flake_irradiance,slice,seed,kind);
        float3 surface_srgb = saturate(
            input.color.rgb*engraved_tone+lamp_warmth+holo_flakes+lamina_glitter);
        float fog_visibility = black_fog_visibility(hit_world);
        output.color = float4(srgb_to_linear(surface_srgb)*fog_visibility,alpha*fog_visibility);
        output.depth = hit_clip.z / hit_clip.w;
        return output;
    }
    float3 cell = floor((input.local_position + 1.0) * scale * 5.0);
    float noise = hash31(cell + seed * float3(.017, .031, .047));
    float radial = length(input.local_position.xy);
    float edge = saturate((1.0 - radial) * 7.0);
    float retained;
    if (kind < .5) {
        // Low-density terrain is wreckage, while the denser kind-zero volumes
        // are contact hulls. Break the former into nested, uneven plate scales
        // and preserve broad black channels between them. A directional gate
        // prevents the surviving cells from reading as uniform screen noise.
        if (density < .5) {
            float3 coarse_cell = floor((input.local_position + 1.0) *
                                      float3(scale * 2.1, scale * 2.8, scale * 1.7));
            float coarse = hash31(coarse_cell + seed * float3(.031,.017,.043));
            float diagonal = .5 + .5 * sin(
                input.local_position.x * 11.0 -
                input.local_position.y * 7.0 +
                input.local_position.z * 13.0 + seed * .013);
            float cluster_gate = coarse * .72 + diagonal * .28;
            // Two gates make dense local archipelagos with empty corridors,
            // rather than evenly salted noise over the whole proxy sphere.
            float archipelago = step(lerp(.70,.52,density),cluster_gate);
            float chip = .5+.5*sin(
                input.local_position.x*29.0+
                input.local_position.y*17.0-
                input.local_position.z*23.0+coarse*9.0);
            // Coherent chips survive minification; an additional high-frequency
            // random gate collapsed into imperceptible salt at tactical scale.
            retained = archipelago * step(.43,chip);
        } else {
            retained = step(1.0 - density, noise);
        }
    } else if (kind < 1.5) {
        float band = .5 + .5 * sin((input.local_position.z * 11.0 + noise * 5.0 + seed * .01));
        retained = step(1.0 - density, noise * .65 + band * .35);
    } else {
        float lane_rule = step(.72, hash31(float3(cell.xy, seed * .01)));
        retained = lerp(.18, .55, lane_rule);
    }
    float engraving = 1.0;
    float3 terrain_color = input.color.rgb;
    if (kind < .5 && density < .5) {
        // Bone-white chipped rims and two sparse burin families make the
        // fragments read as etched plates rather than grey volumetric fog.
        float hatch_a = 1.0-smoothstep(.055,.145,
            abs(sin(input.local_position.x*47.0+
                    input.local_position.y*23.0+seed*.17)));
        float hatch_b = 1.0-smoothstep(.040,.110,
            abs(sin(input.local_position.y*39.0-
                    input.local_position.z*31.0-seed*.11)));
        float silhouette = pow(1.0-saturate(abs(dot(
            normalize(input.local_position),
            normalize(input.local_camera-input.local_position)))),3.0);
        float chipped_rim = 1.0-smoothstep(.07,.18,abs(sin(
            input.local_position.x*19.0-
            input.local_position.y*27.0+
            input.local_position.z*13.0+seed*.071)));
        float cut = max(max(hatch_a,hatch_b*.64),
                        max(silhouette,chipped_rim*.78));
        engraving = .16 + cut*2.15;
        terrain_color = lerp(input.color.rgb*.34,float3(.91,.88,.79),
                             saturate(cut));
    }
    float alpha = input.color.a * retained * edge * engraving;
    if (kind < .5 && density < .5) {
        // The tactical viewport is composited through a deliberately dark
        // archival pass. Give actual wreckage enough plate opacity to survive
        // that delivery transform; untouched cells remain fully black.
        alpha = max(input.color.a,.22) * retained * edge *
                (.18+saturate((engraving-.16)/2.15)*1.24);
    }
    clip(alpha - .006);
    float3 proxy_world = input.world_center+input.local_position*input.world_scale;
    float fog_visibility = black_fog_visibility(proxy_world);
    output.color = float4(srgb_to_linear(terrain_color)*fog_visibility,alpha*fog_visibility);
    output.depth = input.position.z;
    return output;
}

struct BackgroundOutput {
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

float hash21(float2 p) {
    p = frac(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return frac(p.x * p.y);
}

[shader("vertex")]
BackgroundOutput background_vertex(uint vertex_id : SV_VertexID) {
    BackgroundOutput output;
    float2 position = float2((vertex_id << 1) & 2, vertex_id & 2);
    output.uv = position;
    output.position = float4(position * 2.0 - 1.0, .9999, 1);
    return output;
}

[shader("fragment")]
float4 background_fragment(BackgroundOutput input) : SV_Target {
    float2 size = max(push.viewport_seed.xy, 1.0);
    float2 pixel = input.uv * size;
    float seed = push.viewport_seed.z;

    // Leave the depth-tested tactical SDF/volume work on an unframed field.
    // Exterior stars are hard single-pixel pinpricks, never soft particles.
    float star_random = hash21(floor(pixel) + seed * .031);
    float star = step(.99935, star_random);
    float grain = hash21(pixel + seed) - .5;
    float luminance = .0045 + star * .24 + grain * .003;
    if (dark.presentation.z>.5) {
        // Archival plate finish: seed-stable sparse silver grain and generous
        // black corners. This overlay never samples or distorts the world/UI.
        float2 centered=input.uv*2.0-1.0;
        float corner=smoothstep(.62,1.38,dot(centered,centered));
        luminance*=lerp(1.0,.58,corner);
        float plate=step(.9987,hash21(floor(pixel*.5)+seed*.071));
        luminance+=plate*.035;
    }

    return float4(float3(luminance * .92, luminance * .94, luminance), 1);
}
