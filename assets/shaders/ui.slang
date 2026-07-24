struct UiPush {
    float4 viewport;       // logical xy, framebuffer zw
    float4 texture_hatch;  // textured, hatched, antialiased, invert
    float4 hatch_shape;    // spacing, line width, softness, strength
    float4 hatch_tone;     // contrast, brightness, rotation, layer count
    float4 hatch_offset;   // xy offset, edge softness, stroke irregularity
    float4 hatch_angles;   // radians, one per layer
    float4 hatch_levels;   // darkness thresholds, one per layer
};
[[vk::binding(0, 0)]] Texture2D<float4> ui_texture;
[[vk::binding(1, 0)]] SamplerState ui_sampler;
[[vk::push_constant]] ConstantBuffer<UiPush> push;
struct VertexInput { float2 position : POSITION; float2 uv : TEXCOORD0; float4 color : COLOR0; };
struct VertexOutput { float4 position : SV_Position; float2 uv : TEXCOORD0; float4 color : COLOR0; };
float srgb_channel_to_linear(float c) { return c <= .04045 ? c / 12.92 : pow((c + .055) / 1.055, 2.4); }
float3 srgb_to_linear(float3 c) { return float3(srgb_channel_to_linear(c.r), srgb_channel_to_linear(c.g), srgb_channel_to_linear(c.b)); }
[shader("vertex")] VertexOutput vertex_main(VertexInput input) {
    VertexOutput output; float2 pixel = round(input.position / push.viewport.xy * push.viewport.zw);
    float2 ndc = pixel / push.viewport.zw * 2.0 - 1.0; output.position = float4(ndc, 0, 1);
    output.uv = input.uv; output.color = input.color; return output;
}
[shader("vertex")] VertexOutput post_vertex(uint vertex_id : SV_VertexID) {
    VertexOutput output; float2 position=vertex_id==0?float2(-1,-1):vertex_id==1?float2(3,-1):float2(-1,3);
    // The offscreen HDR attachment uses the opposite Y convention from the
    // swapchain. Correct only that axis; flipping X here mirrors every label.
    output.position=float4(position,0,1); output.uv=position*.5+.5; output.color=1; return output;
}
float hatch_line(
    float2 pixel, float angle, float spacing, float width, float softness,
    float irregularity, bool antialiased, out float stroke_lane, out float stroke_along
) {
    float2 axis = float2(cos(angle), sin(angle));
    float2 tangent = float2(-axis.y, axis.x);
    // A low-frequency, sub-pixel phase displacement keeps the strokes stable
    // while avoiding ruler-perfect lines. It is derived entirely from logical
    // position, so panning and Retina scaling cannot introduce shimmer.
    float along = dot(pixel, tangent);
    float across = dot(pixel, axis);
    float lane = floor(across / spacing + .5);
    // Return the exact geometric lane identity to the erosion pass. Recomputing
    // it with a different quantizer can assign opposite halves of one cut to
    // different wear histories and leave a dark seam down its center.
    stroke_lane = lane;
    stroke_along = along;
    float lane_phase = lane * 1.6180339 + angle * 7.3;
    // Each cut starts with a small stable registration error. Varying lane
    // centers, rather than only bending every otherwise-perfectly spaced line,
    // breaks the mechanical diamond grid formed by crossed layers.
    float lane_registration = frac(sin(lane * 19.193 + angle * 23.117) * 43758.5453) - .5;
    float lane_offset = lane_registration * spacing * irregularity * .65;
    // Two incommensurate hand-pressure frequencies avoid the telltale single
    // sinusoid visible across large Dark laminae. Lane phase keeps neighboring
    // cuts from swelling and bending in unison.
    float wobble = (sin(along * .073 + lane_phase) * .78
                  + sin(along * .137 - lane_phase * .61) * .43) * irregularity;
    // A much slower lane-specific bow keeps long cuts from resolving into a
    // ruler-parallel screen across large cropped shells. Scale its amplitude
    // with authored spacing so the bend remains proportional at every hatch
    // density; the lane phase makes neighboring cuts converge and separate
    // independently instead of warping the whole layer as one sine sheet.
    float long_bow = sin(along * .011 + lane_phase * .37)
                   * spacing * irregularity * .34;
    wobble += long_bow;
    // A drypoint cut does not meander as one perfect oscillator. Give each
    // lane a few long, softly joined registration shifts so its local bearing
    // changes independently. The coarse knots are deterministic and blended,
    // avoiding both animation shimmer and visible angular corners.
    float knot_coordinate = along / 47.0 + (lane_registration + .5) * 2.0;
    float knot = floor(knot_coordinate);
    float knot_t = frac(knot_coordinate);
    float knot_blend = knot_t * knot_t * (3.0 - 2.0 * knot_t);
    float knot_a = frac(sin(knot * 41.713 + lane * 11.131 + angle * 9.17) * 43758.5453) - .5;
    float knot_b = frac(sin((knot + 1.0) * 41.713 + lane * 11.131 + angle * 9.17) * 43758.5453) - .5;
    wobble += lerp(knot_a, knot_b, knot_blend) * spacing * irregularity * .42;
    // Registration, bow, and drypoint drift are authored independently. At the
    // most damaged settings their unconstrained sum can exceed half a lane,
    // causing neighboring cuts to exchange identities and form a hard phase
    // seam. Preserve heavy bending but keep every center inside its own cell.
    float displacement_limit = spacing * .42;
    float raw_displacement = lane_offset + wobble;
    // Smooth saturation avoids the flat crests and derivative corners produced
    // by a hard clamp while retaining the same asymptotic topology bound.
    float displacement = displacement_limit * tanh(raw_displacement / displacement_limit);
    float phase = (across + displacement) / spacing;
    float distance_to_line = abs(frac(phase + .5) - .5) * spacing;
    // Slight nib pressure variation makes neighboring cuts breathe
    // independently without changing their authored average line weight.
    float nib_pressure = sin(along * .113 + lane_phase * .73) * .65
                       + sin(along * .047 - lane_phase * 1.17) * .35;
    float nib = 1.0 + nib_pressure * irregularity * .2;
    float half_width = width * .5 * nib;
    if (!antialiased) return distance_to_line <= half_width ? 1.0 : 0.0;
    float filter_width = max(fwidth(phase) * spacing * softness, .0001);
    return 1.0 - smoothstep(half_width - filter_width, half_width + filter_width, distance_to_line);
}
float hatch_stroke_erosion(float lane, float along, float layer, float irregularity) {
    if (irregularity <= .001) return 1.0;
    // Quantized positions make stable gaps along a stroke instead of noisy
    // per-pixel transparency. Layer and lane salts prevent aligned holes at
    // crossovers while preserving deterministic captures. Lane and along are
    // supplied by hatch_line so geometry and wear cannot disagree.
    // Each engraved lane has its own tooth spacing and starting phase. This
    // avoids synchronized dotted bands on narrow forms while retaining stable,
    // chunky losses rather than dissolving strokes into per-pixel noise.
    float lane_seed = frac(sin(lane * 31.417 + layer * 17.173) * 43758.5453);
    float segment_length = 3.2 + lane_seed * 3.6;
    float segment_phase = (lane_seed - .5) * segment_length * 2.0;
    float segment_coordinate = (along + segment_phase) / segment_length;
    float segment = floor(segment_coordinate);
    float segment_position = frac(segment_coordinate);
    float grain = frac(sin(segment * 12.9898 + lane * 78.233 + layer * 37.719) * 43758.5453);
    // Slow pressure drift groups missing teeth into natural worn stretches
    // rather than distributing identical losses evenly down the stroke.
    float wear = sin(along * .031 + lane_seed * 11.0 + layer * 2.37) * .5 + .5;
    float erosion_threshold = irregularity * (.34 + wear * .24);
    float retained = smoothstep(erosion_threshold, erosion_threshold + .10, grain);
    // Taper only where a retained tooth borders a missing one. Applying a nib
    // envelope to every segment exposes the quantization as regular dashes;
    // neighbor-aware ramps leave consecutive retained segments continuous and
    // soften only genuine erosion boundaries.
    float previous_grain = frac(sin((segment - 1.0) * 12.9898 + lane * 78.233 + layer * 37.719) * 43758.5453);
    float next_grain = frac(sin((segment + 1.0) * 12.9898 + lane * 78.233 + layer * 37.719) * 43758.5453);
    float previous_retained = smoothstep(erosion_threshold, erosion_threshold + .10, previous_grain);
    float next_retained = smoothstep(erosion_threshold, erosion_threshold + .10, next_grain);
    float leading = lerp(smoothstep(0.0, .18, segment_position), 1.0, previous_retained);
    float trailing = lerp(1.0 - smoothstep(.82, 1.0, segment_position), 1.0, next_retained);
    return retained * leading * trailing;
}
float volume_hash(float3 p, float seed) {
    p = frac(p * .1031 + seed * .00137);
    p += dot(p, p.yzx + 33.33);
    return frac((p.x + p.y) * p.z);
}
float volume_noise(float3 p, float seed) {
    float3 cell = floor(p); float3 f = frac(p); f = f*f*(3.0-2.0*f);
    float n000=volume_hash(cell+float3(0,0,0),seed), n100=volume_hash(cell+float3(1,0,0),seed);
    float n010=volume_hash(cell+float3(0,1,0),seed), n110=volume_hash(cell+float3(1,1,0),seed);
    float n001=volume_hash(cell+float3(0,0,1),seed), n101=volume_hash(cell+float3(1,0,1),seed);
    float n011=volume_hash(cell+float3(0,1,1),seed), n111=volume_hash(cell+float3(1,1,1),seed);
    return lerp(lerp(lerp(n000,n100,f.x),lerp(n010,n110,f.x),f.y),lerp(lerp(n001,n101,f.x),lerp(n011,n111,f.x),f.y),f.z);
}
float volume_fbm(float3 p, float seed) {
    float value=0.0, weight=.55;
    [unroll] for (int octave=0; octave<3; ++octave) {value += volume_noise(p,seed+octave*19.0)*weight;p=p*2.03+float3(7.1,3.7,5.3);weight*=.48;}
    return value;
}
float3 volume_hash3(float3 p, float seed) {
    float3 q=float3(dot(p,float3(127.1,311.7,74.7)),dot(p,float3(269.5,183.3,246.1)),dot(p,float3(113.5,271.9,124.6)));
    return frac(sin(q+seed*float3(.071,.113,.173))*43758.5453);
}
float voronoi_voxel_density(float3 p,float seed,float smoothing,out float cell_edge) {
    float3 base=floor(p),local=frac(p);float weighted=0.0,total=0.0;float nearest=99.0,second=99.0;
    float kernel=max(smoothing,.025);
    [unroll] for(int z=-1;z<=1;++z)[unroll] for(int y=-1;y<=1;++y)[unroll] for(int x=-1;x<=1;++x) {
        float3 offset=float3(x,y,z);float3 cell=base+offset;float3 feature=offset+volume_hash3(cell,seed)-local;float distance2=dot(feature,feature);
        if(distance2<nearest){second=nearest;nearest=distance2;}else if(distance2<second){second=distance2;}
        float occupancy=volume_hash(cell+float3(19.1,7.7,31.3),seed+47.0);
        // Gaussian reconstruction turns discrete Voronoi voxels into joined
        // lobes while retaining broad cell-shaped cavities.
        float weight=exp(-distance2/kernel);weighted+=weight*smoothstep(.34,.72,occupancy);total+=weight;
    }
    cell_edge=saturate((sqrt(second)-sqrt(nearest))*3.5);
    return weighted/max(total,.0001);
}
float volume_material_density(float3 p,float kind,float noise_scale,float seed,float cell_smoothing,float edge,out float structure,out float cell_edge) {
    structure=voronoi_voxel_density(p*noise_scale+seed*.013,seed,cell_smoothing,cell_edge);float sdf=length(p)-1.0;
    if(kind<.5){float broken=sdf+(structure-.5)*.42;float clumps=smoothstep(.22,.68,structure)*(1.0-cell_edge*.28);return(1.0-smoothstep(-.04,edge,broken))*clumps*1.4;}
    if(kind<1.5){float soft=sdf+(structure-.5)*.62;return(1.0-smoothstep(-.18,edge+.16,soft))*(.18+structure*.92);}
    float shell=exp(-abs(sdf+(structure-.5)*.1)*18.0);float core=(1.0-smoothstep(-.3,.08,sdf))*.12;return(shell+core)*(.35+structure*.7)*(1.0-cell_edge*.18);
}
float4 sdf_volume(VertexOutput input) {
    float kind=push.texture_hatch.y, density_scale=max(push.texture_hatch.z,0.0), seed=push.texture_hatch.w;
    float noise_scale=max(push.hatch_shape.x,.1), edge=max(push.hatch_shape.y,.001), depth=max(push.hatch_shape.z,.15),cell_smoothing=max(push.hatch_shape.w,.025);
    float2 xy=(input.uv-.5)*2.0; if (dot(xy,xy)>1.08) discard;
    float step_size=2.4/40.0,alpha=0.0,light_accum=0.0,shadow_accum=0.0,last_shadow=1.0;float3 light_direction=normalize(float3(-.58,-.66,-.48));
    [loop] for (int i=0;i<40;++i) {
        float z=-1.2+(i+.5)*step_size;float3 p=float3(xy,z/depth);float n,cell_edge;float sample_density=volume_material_density(p,kind,noise_scale,seed,cell_smoothing,edge,n,cell_edge);
        if(sample_density>.015&&(i&1)==0){float optical_depth=0.0;[unroll] for(int shadow_step=1;shadow_step<=3;++shadow_step){float3 shadow_p=p+light_direction*(shadow_step*.16);float shadow_n,shadow_edge;optical_depth+=volume_material_density(shadow_p,kind,noise_scale,seed,cell_smoothing,edge,shadow_n,shadow_edge)*density_scale*.16;}last_shadow=exp(-optical_depth*1.35);}
        sample_density*=density_scale*step_size;float transmit=1.0-alpha;alpha+=transmit*sample_density;
        float etched=.5+.36*smoothstep(.25,.72,n)+cell_edge*.14;light_accum+=transmit*sample_density*etched*last_shadow;shadow_accum+=transmit*sample_density*(1.0-last_shadow);
        if(alpha>.965) break;
    }
    float boundary=1.0-smoothstep(.86,1.04,length(xy));alpha*=boundary;
    float shadow=saturate(shadow_accum/max(alpha,.001));float2 pixel=input.position.xy*push.viewport.xy/push.viewport.zw;float hatch_coverage=0.0,hatch_sum=0.0;
    [unroll] for(int layer=0;layer<3;++layer){float threshold=layer==0?.12:layer==1?.38:.64;if(shadow>=threshold){float angle=layer==0?-1.012291:layer==1?.4712389:-.2094395;float lane,along;float line=hatch_line(pixel,angle,6.0-layer*.35,1.05,.9,.22,true,lane,along);line*=hatch_stroke_erosion(lane,along,(float)layer,.18);hatch_coverage=max(hatch_coverage,line);hatch_sum+=line;}}
    float secondary=max(hatch_sum-hatch_coverage,0.0)*.22;float crosshatch=saturate(hatch_coverage*.72+secondary);
    float3 tint=srgb_to_linear(input.color.rgb);float luminance=saturate(light_accum/max(alpha,.001));float shade=.34+luminance*.66;shade*=1.0-crosshatch*shadow*.48;
    return float4(tint*shade,alpha*input.color.a);
}
float planet_fbm(float3 p, float seed) {
    float value=0.0, amplitude=.55;
    [unroll] for(int octave=0;octave<5;++octave) {
        value += (volume_noise(p,seed+octave*31.0)*2.0-1.0)*amplitude;
        p=p*2.07+float3(13.7,7.3,19.1); amplitude*=.48;
    }
    return value;
}
float planet_crater(float3 surface, float seed, float radius, out float bowl) {
    float3 center=normalize(volume_hash3(float3(seed*.013,seed*.029,seed*.047),seed)*2.0-1.0);
    float angular=acos(clamp(dot(surface,center),-1.0,1.0));
    float rim=exp(-abs(angular-radius)*95.0);
    bowl=1.0-smoothstep(radius*.18,radius,angular);
    return rim;
}
float planet_crater_relief(float3 surface,float3 light,float seed,float radius,
                           out float rim,out float bowl,out float terraces,out float ejecta) {
    float3 center=normalize(volume_hash3(float3(seed*.013,seed*.029,seed*.047),seed)*2.0-1.0);
    float cosine=clamp(dot(surface,center),-1.0,1.0);
    float angular=acos(cosine);
    float normalized_radius=angular/max(radius,.001);
    float3 radial=center-surface*cosine;
    float radial_length=max(length(radial),.0001);
    float slope_light=dot(radial/radial_length,light);
    rim=exp(-abs(normalized_radius-1.0)*18.0);
    bowl=1.0-smoothstep(.16,1.0,normalized_radius);
    float inner_wall=smoothstep(.18,.48,normalized_radius)*(1.0-smoothstep(.78,.98,normalized_radius));
    terraces=(.5+.5*cos(normalized_radius*31.4159))*inner_wall;
    terraces=pow(saturate(terraces),7.0);
    float3 reference=abs(center.y)<.88?float3(0,1,0):float3(1,0,0);
    float3 basis_x=normalize(cross(reference,center));
    float3 basis_y=cross(center,basis_x);
    float azimuth=atan2(dot(surface,basis_y),dot(surface,basis_x));
    float ray_count=floor(lerp(7.0,13.0,volume_hash(float3(seed*.01,5.0,23.0),seed+31.0)));
    float ray_pattern=pow(abs(sin(azimuth*ray_count+seed*.071)),22.0);
    ejecta=ray_pattern*smoothstep(1.02,1.12,normalized_radius)
          *(1.0-smoothstep(1.18,2.45,normalized_radius));
    float rim_relief=rim*slope_light;
    float wall_relief=inner_wall*slope_light*(1.0-normalized_radius)*1.7;
    float floor_shadow=bowl*smoothstep(-.15,.55,-slope_light);
    return rim_relief*.62+wall_relief*.48+terraces*.11-floor_shadow*.16+ejecta*.075;
}
float planet_engraved_line(float2 chart, float angle, float spacing, float width,
                           float relief, float layer, float seed, out float lane, out float along) {
    float2 axis=float2(cos(angle),sin(angle));
    float2 tangent=float2(-axis.y,axis.x);
    along=dot(chart,tangent); float coordinate=dot(chart,axis)+relief;
    lane=floor(coordinate/spacing+.5);
    // A real burin never travels as a mathematically perfect isoline. Give
    // each cut a stable hand, then let that hand wander very slightly along
    // the stroke. The amplitudes stay beneath the line spacing so the field
    // remains fine rather than turning into noisy rope.
    float lane_character=.88+.22*volume_hash(float3(lane,layer*17.0,seed*.007),seed+1103.0);
    float slow_drift=sin(along*.031+lane*1.117+layer*2.73)*.16;
    float tooth_drift=sin(along*.109+lane*.613+seed*.019)*.055;
    coordinate+=slow_drift+tooth_drift;
    lane=floor(coordinate/spacing+.5);
    float pressure=(sin(along*.083+lane*1.73+layer*2.19)*.1+1.0)*lane_character;
    float distance_to_cut=abs(frac(coordinate/spacing+.5)-.5)*spacing;
    float aa=max(fwidth(coordinate)*.62,.055);
    return 1.0-smoothstep(width*.5*pressure-aa,width*.5*pressure+aa,distance_to_cut);
}
float planet_micro_stipple(float2 chart,float seed,float density) {
    float cell_size=5.1;
    float2 cell=floor(chart/cell_size);
    float3 random=volume_hash3(float3(cell,17.0),seed+419.0);
    float2 point=.18+random.xy*.64;
    float distance_to_point=length((frac(chart/cell_size)-point)*cell_size);
    float aa=max(fwidth(distance_to_point)*.7,.045);
    float dot_coverage=1.0-smoothstep(.12-aa,.31+aa,distance_to_point);
    return random.z<density?dot_coverage:0.0;
}
// Reconstruct a mature gas flow directly from the seed. This is a frozen
// backward-advection model, not a time-stepped runtime simulation.
float planet_wrap_longitude(float longitude) {
    return atan2(sin(longitude),cos(longitude));
}
float2 planet_gas_velocity(float2 coordinate,float seed,float ice_giant) {
    float longitude=coordinate.x,latitude=coordinate.y;
    float jet_count=lerp(11.0,6.0,ice_giant);
    float jet_phase=latitude*jet_count*2.0+seed*.017;
    float polar_drag=cos(latitude); polar_drag*=polar_drag;
    float2 velocity=float2((.072+.026*sin(latitude*3.0+seed*.011))*sin(jet_phase)*polar_drag,0.0);
    velocity.y+=sin(longitude*3.0+seed*.023+sin(latitude*5.0))*cos(jet_phase*.5)*.008*polar_drag;
    [unroll] for(int vortex=0;vortex<5;++vortex) {
        float salt=(float)vortex*37.0;
        float center_longitude=(volume_hash(float3(salt+3.0,seed*.007,11.0),seed+salt)*2.0-1.0)*3.14159265;
        float center_latitude=(volume_hash(float3(salt+17.0,seed*.013,29.0),seed+salt+19.0)*2.0-1.0)*.86;
        float scale=vortex==0?.30:lerp(.09,.17,volume_hash(float3(salt,7.0,seed*.003),seed+71.0));
        scale*=lerp(1.0,.72,ice_giant);
        float dx=planet_wrap_longitude(longitude-center_longitude)*cos(center_latitude);
        float dy=latitude-center_latitude;
        float aspect=vortex==0?1.75:1.35;
        float radius2=dx*dx/(aspect*aspect)+dy*dy;
        float influence=exp(-radius2/max(scale*scale,.0001));
        float spin=((vortex&1)==0?1.0:-1.0)*(vortex==0?.105:.052)*influence;
        velocity+=float2(-dy,dx/(aspect*aspect))*spin/max(scale,.03);
        float downstream=planet_wrap_longitude(longitude-center_longitude)*sign(velocity.x+.0001);
        float wake=exp(-dy*dy/max(scale*scale*.34,.0001))*smoothstep(-.08,.15,downstream)*exp(-abs(downstream)*.72);
        velocity.y+=sin(downstream*18.0/scale+salt)*wake*.006;
    }
    return velocity;
}
float2 planet_advected_gas_coordinate(float2 coordinate,float seed,float ice_giant) {
    float2 traced=coordinate;
    float age=3.4+volume_hash(float3(seed*.01,5.0,17.0),seed+307.0)*2.8;
    [unroll] for(int step=0;step<4;++step) {
        float2 v0=planet_gas_velocity(traced,seed,ice_giant);
        float2 midpoint=traced-v0*(age*.125);
        midpoint.x=planet_wrap_longitude(midpoint.x);
        float2 v1=planet_gas_velocity(midpoint,seed,ice_giant);
        traced-=v1*(age*.25);
        traced.x=planet_wrap_longitude(traced.x);
        traced.y=clamp(traced.y,-1.5533,1.5533);
    }
    return traced;
}
float3 planet_spherical_coordinate(float2 coordinate) {
    float latitude_radius=cos(coordinate.y);
    return float3(sin(coordinate.x)*latitude_radius,sin(coordinate.y),cos(coordinate.x)*latitude_radius);
}
float2 atmosphere_atlas_uv(float3 d,bool composition) {
    float3 a=abs(d);float face;float2 uv;
    if(a.x>=a.y&&a.x>=a.z) {if(d.x>=0){face=0;uv=float2(-d.z,-d.y)/a.x;}else{face=1;uv=float2(d.z,-d.y)/a.x;}}
    else if(a.y>=a.z) {if(d.y>=0){face=2;uv=float2(d.x,d.z)/a.y;}else{face=3;uv=float2(d.x,-d.z)/a.y;}}
    else {if(d.z>=0){face=4;uv=float2(d.x,-d.y)/a.z;}else{face=5;uv=float2(-d.x,-d.y)/a.z;}}
    uv=uv*.5+.5;
    // Keep bilinear filtering inside a face; direction reprojection handles
    // topology while this half-texel inset prevents unrelated atlas bleed.
    uv=clamp(uv,1.0/64.0,63.0/64.0);
    float2 tile=float2(fmod(face,3.0),floor(face/3.0));
    tile.x+=composition?3.0:0.0;
    return (tile+uv)/float2(6,2);
}
float4 atmosphere_sample_raw(float3 d,bool composition) { return ui_texture.Sample(ui_sampler,atmosphere_atlas_uv(normalize(d),composition)); }
float4 atmosphere_sample_region(float3 d,bool composition) {
    float3 n=normalize(d);
    float4 center=atmosphere_sample_raw(n,composition);
    // Bilinear sampling is deliberately clamped inside each cubed-sphere tile
    // to prevent atlas bleed. Near a face join, reconstruct the missing cross-
    // edge footprint in direction space so a dense cloud bank cannot reveal the
    // cube as a straight engraved scar. Most fragments retain the single tap.
    float3 a=abs(n);
    float largest=max(a.x,max(a.y,a.z));
    float smallest=min(a.x,min(a.y,a.z));
    float second=a.x+a.y+a.z-largest-smallest;
    float seam=1.0-smoothstep(.018,.072,(largest-second)/max(largest,.0001));
    if(seam<=.001) return center;
    float3 reference=a.y<.86?float3(0,1,0):float3(1,0,0);
    float3 tangent=normalize(cross(reference,n));
    float3 bitangent=cross(n,tangent);
    float footprint=.018;
    float4 across=(atmosphere_sample_raw(n+tangent*footprint,composition)
                  +atmosphere_sample_raw(n-tangent*footprint,composition)
                  +atmosphere_sample_raw(n+bitangent*footprint,composition)
                  +atmosphere_sample_raw(n-bitangent*footprint,composition))*.25;
    return lerp(center,across,seam*.82);
}
float4 atmosphere_sample(float3 d) {return atmosphere_sample_region(d,false);}
float4 atmosphere_composition_sample(float3 d) {return atmosphere_sample_region(d,true);}
float3 planet_cloud_detail_coordinate(float3 surface,float seed,float motion,float signed_vorticity) {
    // Carry sub-atlas engraving texture with the prevailing zonal circulation.
    // This is deliberately much slower than surface rotation and seed-stable;
    // the simulation atlas still owns fronts, while this prevents those fronts
    // from dissolving over a stationary bed of procedural paper grain.
    float drift_sign=volume_hash(float3(seed*.017,43.0,19.0),seed+1489.0)>.5?1.0:-1.0;
    float angle=motion*.0027*drift_sign;
    float ca=cos(angle),sa=sin(angle);
    float3 advected=float3(surface.x*ca+surface.z*sa,surface.y,-surface.x*sa+surface.z*ca);
    // Signed atlas vorticity bends fine fronts around the local tangent frame.
    // The displacement stays smaller than one simulation cell: it supplies a
    // cyclonic gesture without inventing a second weather system or breaking
    // the deterministic large-scale cloud mass.
    float3 reference=abs(advected.y)<.86?float3(0,1,0):float3(1,0,0);
    float3 east=normalize(cross(reference,advected));
    float3 north=cross(advected,east);
    float curl=signed_vorticity*.027;
    float curl_phase=motion*.006+seed*.011+advected.y*9.0;
    return normalize(advected+east*curl+north*curl*.44*sin(curl_phase));
}
float2 planet_atmosphere_limb_fields(float3 surface,float seed,float motion) {
    // Upper-aerosol gaps live on the atmosphere sphere rather than on a fixed
    // screen-space ring. A slow seed-stable zonal drift keeps them coherent
    // with weather animation and freezes automatically with reduced motion.
    float drift_sign=volume_hash(float3(seed*.021,59.0,31.0),seed+1511.0)>.5?1.0:-1.0;
    float angle=motion*.0013*drift_sign;
    float ca=cos(angle),sa=sin(angle);
    float3 advected=float3(surface.x*ca+surface.z*sa,surface.y,-surface.x*sa+surface.z*ca);
    float broad=planet_fbm(advected*2.7+float3(seed*.0021,7.0,13.0),seed+1361.0)*.5+.5;
    float fine=volume_noise(advected*11.0+float3(5.0,seed*.0043,17.0),seed+1409.0);
    float density=saturate(.48+broad*.43+(fine-.5)*.18);
    float etched_break=volume_noise(advected*23.0+float3(19.0,3.0,seed*.0061),seed+1451.0);
    return float2(density,etched_break);
}
float planet_default_mark(float kind,int slot) {
    if(kind<.5) return slot==0?2.0:slot==3?2.0:1.0;
    if(kind<1.5) return slot==0?3.0:slot==1?4.0:slot==3?3.0:1.0;
    if(kind<2.5) return slot==0?6.0:slot==1||slot==3?4.0:1.0;
    if(kind<3.5) return slot==0?5.0:slot==3?2.0:1.0;
    return slot==0?6.0:slot==1?4.0:slot==3?6.0:1.0;
}
float planet_resolve_mark(float encoded,float kind,int slot) {return encoded>.5?encoded:planet_default_mark(kind,slot);}
float planet_mark_angle(float mark,int layer,float neutral_angle) {
    if(mark<1.5) return neutral_angle;
    float primary=mark==3.0?-.78:mark==4.0?1.5708:mark==6.0?1.5708:mark==7.0?.96:.96;
    if(layer>=2) {if(mark==5.0||mark==6.0) return -.78;if(mark==7.0) return 1.5708;}
    return primary;
}
float planet_mark_spacing(float mark) {return mark==2.0?1.12:mark==3.0?.96:mark==4.0?.82:mark==5.0?1.08:mark==6.0?.86:mark==7.0?1.04:1.0;}
float planet_mark_wear(float mark) {return mark==3.0||mark==5.0||mark==6.0?.12:0.0;}
float planet_mark_stipple(float mark) {return mark==2.0||mark==5.0||mark==7.0?.055:0.0;}
float3 planet_mark_tint(float mark) {
    // Muted component hues preserve the bone-white engraving value structure
    // while making the observed material readable at a glance.
    float3 color=mark==2.0?float3(1.0,.43,.31)
                :mark==3.0?float3(.46,.86,.55)
                :mark==4.0?float3(.38,.63,1.0)
                :mark==5.0?float3(1.0,.78,.34)
                :mark==6.0?float3(.38,.86,1.0)
                :mark==7.0?float3(1.0,.46,.80)
				:mark==8.0?float3(.76,.72,.65)
				:mark==9.0?float3(.67,.32,.20)
				:mark==10.0?float3(.16,.32,.46)
				:mark==11.0?float3(.90,.94,.96)
				:mark==12.0?float3(.90,.72,.18)
				:mark==13.0?float3(.12,.13,.13)
				:mark==14.0?float3(.92,.95,.96)
				:mark==15.0?float3(.94,.92,.84)
				:mark==16.0?float3(.25,.38,.22)
				:mark==17.0?float3(.52,.68,.69)
                :float3(1.0,1.0,1.0);
    return srgb_to_linear(color);
}
float3 planet_cloud_composition_tint(float4 mixture) {
    float total=dot(mixture,float4(1.0));
    if(total<=.001) return float3(1.0);
    mixture/=total;
    // Water and ammonia stay close to the plate's bone-white ink; methane and
    // sulfur introduce the scarce cold and cautionary hues used by the UI.
	float3 water=srgb_to_linear(float3(.94,.96,.97));
	float3 ammonia=srgb_to_linear(float3(.96,.94,.86));
	// Methane is colorless; this subdued cyan represents red absorption through
	// a deep methane-bearing atmosphere, not the intrinsic color of the gas.
	float3 methane=srgb_to_linear(float3(.62,.75,.76));
	// The cloud component represents pale sulfuric-acid/SO2 condensates. Bright
	// elemental sulfur remains a distinct solid-surface material.
	float3 sulfur=srgb_to_linear(float3(.96,.91,.76));
    return water*mixture.x+ammonia*mixture.y+methane*mixture.z+sulfur*mixture.w;
}
float4 procedural_planet(VertexOutput input) {
    float kind=push.texture_hatch.y, seed=push.texture_hatch.z, phase=push.texture_hatch.w;
    float tilt=push.hatch_shape.x, atmosphere=saturate(push.hatch_shape.y);
    float cloud_cover=saturate(push.hatch_shape.z), banding=saturate(push.hatch_shape.w);
    float ocean_fraction=saturate(push.hatch_tone.x), rings=saturate(push.hatch_tone.y);
    float has_atmosphere_atlas=push.hatch_angles.x;
    float atmosphere_lerp=saturate(push.hatch_angles.y);
    float cloud_altitude=push.hatch_angles.z>0?push.hatch_angles.z:.018;
    float atmosphere_motion=push.hatch_angles.w;
    float ground_mark=planet_resolve_mark(push.hatch_levels.x,kind,0);
    float secondary_mark=planet_resolve_mark(push.hatch_levels.y,kind,1);
    float cloud_mark=planet_resolve_mark(push.hatch_levels.z,kind,2);
    float encoded_accent=push.hatch_levels.w;
    float geometric_albedo=frac(encoded_accent)*10.0;
    if(geometric_albedo<.01) geometric_albedo=kind<.5?.14:kind<1.5?.36:kind<2.5?.55:kind<3.5?.48:.46;
    float accent_mark=planet_resolve_mark(floor(encoded_accent+.001),kind,3);
    float2 q=(input.uv-.5)*2.0;
    float configured_flattening=push.hatch_tone.z;
    float flattening=configured_flattening>.1?configured_flattening:(kind>=2.5?.94:1.0);
    float2 body_q=float2(q.x,q.y/flattening);
    float r2=dot(body_q,body_q);
    float radius=push.hatch_tone.w>.1?push.hatch_tone.w:.82;
    float configured_ring_inner=push.hatch_offset.x;
    float configured_ring_outer=push.hatch_offset.y;
    float ring_density_control=push.hatch_offset.z>0.0?saturate(push.hatch_offset.z):.65;
    float ring_structure=push.hatch_offset.w>0.0?saturate(push.hatch_offset.w):.55;
    // Authored cloud altitude is also our best proxy for atmospheric scale
    // height. Calibrate Earth-like .018 to the former .055 envelope, while
    // allowing hot/low-gravity worlds to carry visibly broader upper air.
    float atmosphere_scale_height=clamp(.039+cloud_altitude*.9,.045,.075);
    float outer=radius+atmosphere*atmosphere_scale_height;
    float3 tint=srgb_to_linear(input.color.rgb);
    float3 planet_light=normalize(float3(-.68,-.36,.64));
    // A projected annulus made from several dry engraved ringlets. The old
    // treatment was one thick ellipse, which read as a flat UI bracket rather
    // than particulate orbital material.
    float ring_plane_y=q.y+q.x*sin(tilt)*.16;
    float ring_metric=length(float2(q.x/.995,ring_plane_y/.235));
    float ring_aa=max(fwidth(ring_metric)*.85,.0015);
    // Saturn's visible system runs from the faint D ring at 1.11 planetary
    // radii through the F ring at 2.32. Its dense C/B/A annulus begins at
    // 1.239 radii. Other generated ring systems keep the compact proportions.
    float saturn_proportions=(kind>=2.5&&kind<3.5&&abs(configured_ring_outer-2.32)<.03)?1.0:0.0;
    float inner_ratio=configured_ring_inner>1.0?configured_ring_inner:1.18;
    float outer_ratio=configured_ring_outer>inner_ratio?configured_ring_outer:1.92;
    float ring_inner_radius=radius*lerp(inner_ratio,1.239,saturn_proportions);
    float faint_inner_radius=radius*inner_ratio;
    float ring_outer_radius=radius*outer_ratio;
    float ring_width=ring_outer_radius-ring_inner_radius;
    float ringlet0=1.0-smoothstep(.003-ring_aa,.003+ring_aa,abs(ring_metric-faint_inner_radius));
    float ringlet1=1.0-smoothstep(.003-ring_aa,.003+ring_aa,abs(ring_metric-lerp(ring_inner_radius,ring_outer_radius,.34)));
    float ringlet2=1.0-smoothstep(.004-ring_aa,.004+ring_aa,abs(ring_metric-lerp(ring_inner_radius,ring_outer_radius,.74)));
    float ringlet3=1.0-smoothstep(.0025-ring_aa,.0025+ring_aa,abs(ring_metric-lerp(ring_inner_radius,ring_outer_radius,.985)));
    float annulus=smoothstep(ring_inner_radius,ring_inner_radius+.012,ring_metric)
                 *(1.0-smoothstep(ring_outer_radius-.009,ring_outer_radius,ring_metric));
    float radial_coordinate=saturate((ring_metric-ring_inner_radius)/ring_width);
    float generated_ringlet_count=lerp(18.0,58.0,ring_structure);
    float radial_phase=radial_coordinate*lerp(generated_ringlet_count,31.0,saturn_proportions);
    // Four phase samples resolve ringlets while they are still wide enough to
    // engrave. Once a pixel spans most of a radial period, converge on the
    // pulse train's mean coverage instead of widening individual lines. This
    // is a band-limited signal: distant/shallow ringlets become an optical
    // tone and cannot beat against the pixel grid to form moire waves.
    float radial_footprint=max(fwidth(radial_phase),.001);
    float sample_span=min(radial_footprint,1.0);
    float radial_d0=abs(frac(radial_phase-sample_span*.375+.5)-.5);
    float radial_d1=abs(frac(radial_phase-sample_span*.125+.5)-.5);
    float radial_d2=abs(frac(radial_phase+sample_span*.125+.5)-.5);
    float radial_d3=abs(frac(radial_phase+sample_span*.375+.5)-.5);
    float sampled_ringlets=(1.0-smoothstep(.06,.12,radial_d0)
                           +1.0-smoothstep(.06,.12,radial_d1)
                           +1.0-smoothstep(.06,.12,radial_d2)
                           +1.0-smoothstep(.06,.12,radial_d3))*.25;
    float unresolved=smoothstep(.42,1.05,radial_footprint);
    float fine_ringlets=lerp(sampled_ringlets,.18,unresolved);
    float radial_lane=floor(radial_phase);
    float lane_pressure=.34+.66*volume_hash(float3(radial_lane,seed*.013,31.0),seed+577.0);
    lane_pressure=lerp(lane_pressure,.67,unresolved);
    // Measured Saturn structure, normalized from the C-ring inner edge
    // (1.239 R) to the F ring (2.320 R). Narrow divisions remain black rather
    // than being painted as decorative hoops.
    float gap0_center=.12+.18*volume_hash(float3(seed*.011,7.0,1.0),seed+701.0);
    float gap1_center=.38+.18*volume_hash(float3(seed*.013,11.0,2.0),seed+709.0);
    float gap2_center=.62+.15*volume_hash(float3(seed*.017,17.0,3.0),seed+719.0);
    float gap3_center=.82+.11*volume_hash(float3(seed*.019,23.0,4.0),seed+727.0);
    float generated_gap_width=lerp(.008,.026,ring_structure);
    float generated_gaps=smoothstep(generated_gap_width*.35,generated_gap_width,abs(radial_coordinate-gap0_center))
                        *smoothstep(generated_gap_width*.5,generated_gap_width*1.5,abs(radial_coordinate-gap1_center))
                        *smoothstep(generated_gap_width*.3,generated_gap_width*.9,abs(radial_coordinate-gap2_center))
                        *smoothstep(generated_gap_width*.2,generated_gap_width*.65,abs(radial_coordinate-gap3_center));
    float maxwell_gap=smoothstep(.003,.009,abs(radial_coordinate-.197));
    float cassini_gap=smoothstep(.02,.043,abs(radial_coordinate-.695));
    float encke_gap=smoothstep(.0025,.007,abs(radial_coordinate-.902));
    float keeler_gap=smoothstep(.0015,.0045,abs(radial_coordinate-.949));
    float saturn_gaps=maxwell_gap*cassini_gap*encke_gap*keeler_gap;
    float measured_gaps=lerp(generated_gaps,saturn_gaps,saturn_proportions);
    float a_ring_outer=lerp(1.0,1.0-smoothstep(.948,.958,radial_coordinate),saturn_proportions);
    fine_ringlets*=annulus*lane_pressure*measured_gaps*a_ring_outer;
    // Particles vary non-periodically around the orbit and by radial optical
    // depth. Unlike the former sine terms, this field has no coherent diagonal
    // wavelength that can beat against the engraved ringlets.
    float ring_azimuth=atan2(ring_plane_y/.235,q.x/.995);
    float radial_density=.42+.58*volume_noise(float3(radial_coordinate*9.7,seed*.0017,47.0),seed+601.0);
    float particulate=.82+.18*volume_noise(float3(cos(ring_azimuth)*23.0,sin(ring_azimuth)*23.0,radial_coordinate*17.0),seed+653.0);
    float generated_profile=.22+.78*volume_noise(float3(radial_coordinate*lerp(3.5,8.0,ring_structure),seed*.0023,61.0),seed+677.0);
    float family0=smoothstep(0.0,.07,radial_coordinate)*(1.0-smoothstep(.28,.38,radial_coordinate));
    float family1=smoothstep(.3,.4,radial_coordinate)*(1.0-smoothstep(.64,.74,radial_coordinate));
    float family2=smoothstep(.66,.76,radial_coordinate)*(1.0-smoothstep(.94,1.0,radial_coordinate));
    float generated_optical_depth=(family0*.48+family1*.92+family2*.62)*generated_profile*ring_density_control;
    float c_ring=1.0-smoothstep(.245,.275,radial_coordinate);
    float b_ring=smoothstep(.245,.275,radial_coordinate)*(1.0-smoothstep(.645,.675,radial_coordinate));
    float a_ring=smoothstep(.725,.755,radial_coordinate)*(1.0-smoothstep(.948,.958,radial_coordinate));
    float saturn_optical_depth=(c_ring*.34+b_ring*.92+a_ring*.58)*radial_density*ring_density_control;
    float optical_depth=lerp(generated_optical_depth,saturn_optical_depth,saturn_proportions)*measured_gaps;
    float ring_cut=saturate((ringlet0*.16+ringlet1*.5+ringlet2*.62+ringlet3*.34
                           +fine_ringlets*lerp(1.0,.38,saturn_proportions)*(.32+.3*radial_density)
                           +annulus*lerp(.095,.22,saturn_proportions)*optical_depth*a_ring_outer)
                           *particulate*measured_gaps)*rings;
    float ring_opacity=saturate((optical_depth*.92+ringlet3*.12)*particulate*rings);
    // Illuminate the particulate sheet from the same star as the globe. A ray
    // from each ring sample toward the star tests against Saturn's unit sphere,
    // producing the long planetary shadow on the far ansa instead of an
    // uniformly bright decal.
    float3 ring_plane_normal=normalize(float3(sin(tilt)*.16,1.0,0.0));
    float ring_depth=(ring_plane_y/.235)*.995;
    float3 ring_position=float3(q.x/radius,-q.x*sin(tilt)*.16/radius,ring_depth/radius);
    float ring_ray_b=dot(ring_position,planet_light);
    float ring_ray_c=dot(ring_position,ring_position)-1.0;
    float ring_ray_discriminant=ring_ray_b*ring_ray_b-ring_ray_c;
    float ring_ray_t=-ring_ray_b-sqrt(max(ring_ray_discriminant,0.0));
    float planet_shadow_on_ring=(ring_ray_t>0.0?1.0:0.0)*smoothstep(-.018,.035,ring_ray_discriminant);
    float ring_incidence=abs(dot(ring_plane_normal,planet_light));
    float ring_illumination=(.16+.84*sqrt(saturate(ring_incidence)))*(1.0-planet_shadow_on_ring*.9);
    ring_cut*=ring_illumination;
    if(r2>outer*outer) {
        if(ring_cut<=.001) discard;
        return float4(tint*ring_cut,ring_cut*input.color.a*.78);
    }
    if(r2>radius*radius) {
        float3 halo_normal=normalize(float3(body_q,0.0));
        float halo_ct=cos(tilt),halo_st=sin(tilt);
        // The aerosol envelope is illuminated in view space, like the globe
        // and inner rim. Axial tilt rotates weather coordinates below, not the
        // star-facing side of the projected atmosphere itself.
        float halo_light=dot(halo_normal,planet_light);
        float3 halo_tilted=float3(halo_normal.x,halo_normal.y*halo_ct-halo_normal.z*halo_st,halo_normal.y*halo_st+halo_normal.z*halo_ct);
        float hcp=cos(phase),hsp=sin(phase);
        float3 halo_surface=float3(halo_tilted.x*hcp+halo_tilted.z*hsp,halo_tilted.y,-halo_tilted.x*hsp+halo_tilted.z*hcp);
        float2 halo_fields=planet_atmosphere_limb_fields(halo_surface,seed,atmosphere_motion);
        float halo_density=halo_fields.x,halo_break=halo_fields.y;
        // Atmospheric radiance accumulates along the tangent path and falls
        // exponentially with altitude. This concentrates the envelope against
        // the globe instead of filling the whole annulus with a smooth wash.
        // A second angular field opens dry gaps through its upper veil, matching
        // the broken-edge language of the engraved surface below.
        float halo_height=saturate((sqrt(r2)-radius)/max(outer-radius,.001));
        float tangent_depth=exp(-halo_height*4.2)*(1.0-smoothstep(.78,1.0,halo_height));
        float halo_veil=lerp(.28,1.0,smoothstep(.18,.66,halo_density+(halo_break-.5)*.38-halo_height*.1));
        float halo=tangent_depth*halo_veil;
        float halo_day=smoothstep(-.42,.46,halo_light);
        float sunward_halo=halo*halo_density*atmosphere*(.003+.57*halo_day);
        float shell_radius=radius*(1.0+cloud_altitude*atmosphere);
        float shell_z=sqrt(max(shell_radius*shell_radius-r2,0.0))/shell_radius;
        float3 shell_view=normalize(float3(body_q/shell_radius,shell_z));
        float3 shell_tilted=float3(shell_view.x,shell_view.y*halo_ct-shell_view.z*halo_st,shell_view.y*halo_st+shell_view.z*halo_ct);
        float3 shell_surface=float3(shell_tilted.x*hcp+shell_tilted.z*hsp,shell_tilted.y,-shell_tilted.x*hsp+shell_tilted.z*hcp);
        float4 shell_weather=has_atmosphere_atlas>0?atmosphere_sample(shell_surface):0;
        // Atlas cloud density already incorporates the authored cover in the
        // deterministic simulation; applying it again here would square the
        // control and erase moderate Earth-like systems.
        float shell_cloud=lerp(shell_weather.r,shell_weather.g,atmosphere_lerp);
        // The simulation atlas is intentionally low resolution. Reintroduce
        // deterministic, advected-looking breakup at the projected cloud shell
        // so its silhouette reads as weather rather than a second smooth disc.
        float shell_signed_vorticity=(shell_weather.a-.5)*2.0;
        float3 shell_detail_surface=planet_cloud_detail_coordinate(shell_surface,seed,atmosphere_motion,shell_signed_vorticity);
        float shell_detail=planet_fbm(shell_detail_surface*18.0+float3(seed*.0017,3.0,7.0),seed+1237.0)*.5+.5;
        float shell_vorticity=abs(shell_signed_vorticity);
        float shell_pressure_cloud_bias=(.5-shell_weather.b)*.14;
        shell_cloud=saturate((shell_cloud-.16)*1.28
                           +(shell_detail-.5)*(.16+.18*shell_vorticity)
                           +shell_pressure_cloud_bias);
        float shell_light=saturate(dot(shell_view,planet_light));
        float shell_edge=max(fwidth(r2)*2.0,.0005);
        float shell_band=smoothstep(radius*radius,shell_radius*shell_radius,r2)
                        *(1.0-smoothstep(shell_radius*shell_radius-shell_edge,shell_radius*shell_radius,r2));
        float shell_ink=shell_cloud*shell_band*(.06+.72*shell_light);
        float aerosol_rim=pow(saturate(halo),1.65)*atmosphere*halo_density*(.004+.19*halo_day);
        float etch_wear=smoothstep(.24,.62,halo_density)
                       *smoothstep(.08,.32,halo_break);
        float outer_etch=(1.0-smoothstep(.0,max(fwidth(r2)*3.0,.0012),abs(r2-outer*outer)))
                         *atmosphere*etch_wear*(.004+.39*halo_day);
        float combined=max(max(max(sunward_halo,aerosol_rim),max(shell_ink,outer_etch)),ring_cut);
        float combined_alpha=max(max(max(sunward_halo*.8,aerosol_rim),max(shell_ink,outer_etch)),ring_cut*.78);
        float4 shell_composition=atmosphere_composition_sample(shell_surface);
        float3 shell_component_tint=planet_cloud_composition_tint(shell_composition);
        float shell_luminance=dot(shell_component_tint,float3(.2126,.7152,.0722));
        float3 shell_value_tint=shell_component_tint/max(shell_luminance,.08);
        float shell_share=saturate(shell_ink/max(combined,.001));
        float3 shell_tint=tint*lerp(float3(1.0),shell_value_tint,.45*shell_share);
        return float4(shell_tint*combined,combined_alpha*input.color.a);
    }
    float z=sqrt(max(radius*radius-r2,0.0))/radius;
    float3 view_normal=normalize(float3(body_q/radius,z));
    float3 normal=view_normal;
    // Axial tilt belongs to the rotating surface coordinate, not the light.
    // Keeping the illumination normal in view space prevents retrograde worlds
    // such as Venus from incorrectly changing phase when their axis flips.
    float ct=cos(tilt),st=sin(tilt);
    float3 tilted_normal=float3(normal.x,normal.y*ct-normal.z*st,normal.y*st+normal.z*ct);
    float cp=cos(phase),sp=sin(phase); float3 surface=float3(tilted_normal.x*cp+tilted_normal.z*sp,tilted_normal.y,-tilted_normal.x*sp+tilted_normal.z*cp);
    // Weather is sampled in the tilted, rotating atlas frame. Transform the
    // stellar direction through that same frame before using it for atlas-space
    // cloud-shadow parallax; adding a view-space vector to `surface` made the
    // shadow bearing drift whenever phase or axial tilt changed.
    float3 tilted_surface_light=float3(planet_light.x,
                                       planet_light.y*ct-planet_light.z*st,
                                       planet_light.y*st+planet_light.z*ct);
    float3 surface_light=float3(tilted_surface_light.x*cp+tilted_surface_light.z*sp,
                                tilted_surface_light.y,
                                -tilted_surface_light.x*sp+tilted_surface_light.z*cp);
    // Reconstruct the visible cloud shell independently of the ground sphere.
    // The differing z intersection produces real near-limb parallax and joins
    // continuously to the off-disk shell path above.
    float cloud_shell_radius=radius*(1.0+cloud_altitude*atmosphere);
    float cloud_shell_z=sqrt(max(cloud_shell_radius*cloud_shell_radius-r2,0.0))/cloud_shell_radius;
    float3 cloud_view_normal=normalize(float3(body_q/cloud_shell_radius,cloud_shell_z));
    float3 cloud_tilted=float3(cloud_view_normal.x,cloud_view_normal.y*ct-cloud_view_normal.z*st,cloud_view_normal.y*st+cloud_view_normal.z*ct);
    float3 cloud_surface=float3(cloud_tilted.x*cp+cloud_tilted.z*sp,cloud_tilted.y,-cloud_tilted.x*sp+cloud_tilted.z*cp);
    float3 light=planet_light;
    float lambert=saturate(dot(normal,light));
    float limb=pow(saturate(z),.42); float night_glance=.035+atmosphere*.045*(1.0-z);
    // Each seed selects a geological/meteorological regime as well as a noise
    // offset. Varying the octave scale is what makes silhouettes of continents,
    // plates, and belts differ materially instead of merely sliding the same
    // texture around the globe.
    float style0=volume_hash(float3(seed*.017,11.0,37.0),seed+401.0);
    float style1=volume_hash(float3(seed*.031,29.0,7.0),seed+457.0);
    float style2=volume_hash(float3(seed*.007,53.0,19.0),seed+503.0);
    float broad_scale=lerp(1.55,3.45,style0);
    float detail_scale=lerp(5.4,11.8,style1);
    float broad=planet_fbm(surface*broad_scale,seed);
    float detail=planet_fbm(surface*detail_scale,seed+71.0);
    float latitude=abs(surface.y); float material=.52, feature_edge=0.0, striation=0.0;
    float mark_secondary_mask=0.0,mark_accent_mask=0.0;
    float engraving_region=.5, engraving_groove=0.0;
    float2 flow_engraving_coordinate=float2(atan2(surface.x,surface.z),asin(clamp(surface.y,-1.0,1.0)));
    float flow_engraving_strength=0.0;
    if(kind<.5) {
        float fault_cells;
        float fault_field=voronoi_voxel_density(surface*lerp(2.1,6.2,style2)+seed*.003,
                                                seed+619.0,.14,fault_cells);
        float faults=(1.0-smoothstep(.018,.095,fault_cells))*smoothstep(.22,.58,style1);
        float highlands=smoothstep(lerp(-.28,.02,style2),lerp(.28,.56,style2),broad+detail*.24);
        float ridges=smoothstep(lerp(.38,.57,style0),lerp(.66,.84,style0),abs(detail+broad*.18));
        float bowl0,bowl1,bowl2,bowl3,terrace0,terrace1,terrace2,terrace3,ejecta0,ejecta1,ejecta2,ejecta3;
        float crater0,crater1,crater2,crater3;
        float relief0=planet_crater_relief(surface,light,seed+17.0,lerp(.075,.16,style0),crater0,bowl0,terrace0,ejecta0);
        float relief1=planet_crater_relief(surface,light,seed+53.0,lerp(.055,.12,style1),crater1,bowl1,terrace1,ejecta1);
        float relief2=planet_crater_relief(surface,light,seed+101.0,lerp(.14,.27,style2),crater2,bowl2,terrace2,ejecta2);
        float relief3=planet_crater_relief(surface,light,seed+149.0,lerp(.24,.43,style1),crater3,bowl3,terrace3,ejecta3);
        float crater3_presence=smoothstep(.55,.82,style2);
        crater3*=crater3_presence; relief3*=crater3_presence; terrace3*=crater3_presence; ejecta3*=crater3_presence;
        float maria=bowl3*smoothstep(.4,.72,style2);
        float crater_relief=relief0+relief1+relief2+relief3;
        float crater_terraces=max(max(terrace0,terrace1),max(terrace2,terrace3));
        float crater_ejecta=max(max(ejecta0,ejecta1),max(ejecta2,ejecta3));
        material=.34+highlands*.27+ridges*.13+faults*.08+crater_relief*.3
                -(bowl0*.09+bowl1*.07+bowl2*.08+maria*.16);
        feature_edge=max(max(ridges*.32,faults*.58),max(max(max(crater0,crater1),max(crater2,crater3))*.9,
                                                        max(crater_terraces*.48,crater_ejecta*.36)));
        striation=saturate(ridges+faults*.7+bowl0*.25+bowl1*.2+bowl2*.22+maria*.18
                          +crater_terraces*.46+crater_ejecta*.32);
        engraving_region=saturate(highlands*.72+ridges*.28);
        mark_accent_mask=saturate(ridges+faults*.6+max(max(crater0,crater1),max(crater2,crater3))*.7);
    } else if(kind<1.5) {
        float archipelago=planet_fbm(surface*lerp(13.0,24.0,style2),seed+733.0);
        float field=broad+detail*lerp(.09,.25,style1)+archipelago*lerp(.03,.2,style2);
        float coast=.27-ocean_fraction*.25+lerp(-.08,.09,style0);
        float land=smoothstep(coast-.08,coast+.08,field);
        float polar=smoothstep(.72,.94,latitude+detail*.035);
        float mountain_field=detail+broad*lerp(.15,.48,style2);
        float mountain_axis=abs(mountain_field);
        float foothills=land*smoothstep(lerp(.32,.48,style0),lerp(.58,.72,style0),mountain_axis);
        float mountains=land*smoothstep(lerp(.46,.62,style0),lerp(.68,.86,style0),mountain_axis);
        float mountain_spine=land*smoothstep(.79,.96,mountain_axis);
        float mountain_contours=foothills*pow(.5+.5*cos(mountain_axis*34.0),8.0);
        float mountain_face=mountains*sign(mountain_field)*lerp(-.055,.075,saturate(dot(surface,light)*.5+.5));
        material=lerp(.32,.7,land)+mountains*.13+mountain_spine*.1+mountain_face;
        material=max(material,polar*.88);
        feature_edge=max(max(1.0-smoothstep(.008,.028,abs(field-coast)),
                             max(mountains*.48,mountain_spine*.72)),max(mountain_contours*.3,polar*.28));
        striation=land*saturate(smoothstep(.5,.8,abs(detail))+mountains*.55
                               +mountain_spine*.5+mountain_contours*.36);
        engraving_region=saturate(land+polar*.4);
        mark_secondary_mask=1.0-land;mark_accent_mask=saturate(mountains+mountain_spine+polar*.45);
    } else if(kind<2.5) {
        float ice_cells;
        float ice_structure=voronoi_voxel_density(surface*lerp(2.4,7.1,style0)+seed*.003,seed+83.0,
                                                  lerp(.1,.29,style1),ice_cells);
        float fractures=1.0-smoothstep(.035,.2,ice_cells);
        float latitude_rifts=pow(abs(sin(atan2(surface.x,surface.z)*lerp(2.0,7.0,style2)
                                            +surface.y*lerp(5.0,14.0,style1)+detail*1.7)),18.0)
                            *smoothstep(.38,.7,style2);
        fractures=max(fractures,latitude_rifts);
        engraving_groove=1.0-smoothstep(.014,.065,ice_cells);
        engraving_groove=max(engraving_groove,latitude_rifts*.72);
        float polar=smoothstep(.5,.94,latitude);
        material=.57+ice_structure*.16+polar*.13-fractures*.09;
        feature_edge=fractures*.62; striation=saturate(fractures*.72+abs(detail)*.18);
        engraving_region=saturate(ice_structure*.7+fractures*.18);
        mark_secondary_mask=fractures;mark_accent_mask=saturate(fractures*.7+polar*.35);
    } else {
        float longitude=atan2(surface.x,surface.z), latitude_signed=asin(clamp(surface.y,-1.0,1.0));
        float ice_giant=kind>=3.5?1.0:0.0;
        float2 advected=planet_advected_gas_coordinate(float2(longitude,latitude_signed),seed,ice_giant);
        flow_engraving_coordinate=advected;
		// Weather advection owns the material fields, but only bends the burin
		// plate gently. A full backtrace stretches a few cuts across hemispheres
		// and tears where longitude wraps.
		flow_engraving_strength=ice_giant>.5?.10:.18;
        float3 tracer_surface=planet_spherical_coordinate(advected);
        float jet_frequency=lerp(lerp(17.0,29.0,style0),lerp(8.0,16.0,style0),ice_giant);
        float tracer_noise=planet_fbm(tracer_surface*float3(3.1,8.4,3.1),seed+131.0);
        float fine_noise=planet_fbm(tracer_surface*float3(8.7,18.0,8.7),seed+197.0);
        float jet_phase=advected.y*jet_frequency+tracer_noise*lerp(lerp(1.9,3.8,style1),lerp(.8,1.8,style1),ice_giant);
        float jets=sin(jet_phase);
        float belt_boundary=pow(1.0-abs(jets),6.0);
        float shear_filaments=smoothstep(.44,.82,abs(fine_noise+tracer_noise*.35));
        float2 flow=planet_gas_velocity(float2(longitude,latitude_signed),seed,ice_giant);
        float flow_energy=saturate(length(flow)*8.0);
        float belt_contrast=lerp(.7,1.45,style2);
        material=.49+jets*(.085+.13*banding)*belt_contrast+tracer_noise*.12+fine_noise*.055;
        material+=flow_energy*(tracer_noise*.12+fine_noise*.07);
        feature_edge=max(belt_boundary*(.34+.5*banding),shear_filaments*flow_energy*.48);
        striation=saturate(abs(jets)*.58+shear_filaments*.28+flow_energy*.42);
        engraving_region=saturate(.35+flow_energy*.45+shear_filaments*.2);
        mark_secondary_mask=smoothstep(-.18,.18,jets);
        // Long-lived storms give seeds a few large, memorable landmarks rather
        // than leaving every atmosphere as an anonymous stack of belts.
        float storm_bowl0,storm_bowl1,storm_bowl2;
        float storm0=planet_crater(surface,seed+811.0,lerp(.075,.18,style0),storm_bowl0);
        float storm1=planet_crater(surface,seed+877.0,lerp(.045,.11,style1),storm_bowl1)
                    *smoothstep(.28,.52,style2);
        float storm2=planet_crater(surface,seed+941.0,lerp(.055,.14,style2),storm_bowl2)
                    *smoothstep(.58,.78,style0);
        float storm_core=storm_bowl0+storm_bowl1*.72+storm_bowl2*.6;
        float storm_rims=max(storm0,max(storm1,storm2));
        material+=storm_core*lerp(.055,.15,style1)-storm_rims*.035;
        feature_edge=max(feature_edge,storm_rims*lerp(.42,.82,style0));
        striation=saturate(striation+storm_core*.3+storm_rims*.48);
        engraving_region=saturate(engraving_region+storm_core*.28);
        mark_accent_mask=saturate(storm_core+storm_rims);
        if(kind>=3.5) {
            float polar_hood=smoothstep(.42,.88,latitude);
            material=lerp(material,.72,polar_hood*.62);
            feature_edge=max(feature_edge,(1.0-smoothstep(.025,.11,abs(latitude-.57)))*.38);
            striation*=.52;
        }
    }
    float cloud_field=planet_fbm(cloud_surface*lerp(3.6,8.2,style2)+float3(2.7,0,1.3),seed+211.0);
    float cloud_threshold=.6+(1.0-cloud_cover)*.22;
    float clouds=smoothstep(cloud_threshold-.055,cloud_threshold+.055,cloud_field);
    float cloud_edge=1.0-smoothstep(.012,.042,abs(cloud_field-cloud_threshold));
    float2 cloud_gradient=float2(ddx(clouds),ddy(clouds));
    float2 projected_cloud_light=normalize(float2(planet_light.x,planet_light.y*flattening));
    float cloud_gradient_length=length(cloud_gradient);
    float cloud_front_facing=smoothstep(-.18,.62,-dot(cloud_gradient/max(cloud_gradient_length,.0001),projected_cloud_light))
                            *smoothstep(.0005,.006,cloud_gradient_length);
    float cloud_shadow=0.0;
    float cloud_vorticity=0.0,cloud_spin=0.0,cloud_relief=cloud_field*.35;
    float cloud_lambert=saturate(dot(cloud_view_normal,planet_light));
    if(has_atmosphere_atlas>0) {
        float4 weather=atmosphere_sample(cloud_surface);
        clouds=lerp(weather.r,weather.g,atmosphere_lerp);
        // Preserve the large simulated pressure systems, but cut their soft
        // texels into fronts, cells, and torn anvils. Vorticity controls how
        // aggressively the small-scale structure breaks up.
        cloud_spin=(weather.a-.5)*2.0;
        float3 cloud_detail_surface=planet_cloud_detail_coordinate(cloud_surface,seed,atmosphere_motion,cloud_spin);
        float cloud_detail=planet_fbm(cloud_detail_surface*18.0+float3(seed*.0017,3.0,7.0),seed+1237.0)*.5+.5;
        float cloud_filament=planet_fbm(cloud_detail_surface*41.0+float3(11.0,seed*.0011,5.0),seed+1291.0)*.5+.5;
        cloud_vorticity=abs(cloud_spin);
        // The blue atlas channel is pressure normalized around .5. Low pressure
        // consolidates and raises cloud systems; high pressure opens restrained
        // clear cells. Keep this subordinate to simulated condensate mass.
        float pressure_cloud_bias=(.5-weather.b)*.14;
        clouds=saturate((clouds-.13)*1.24
                       +(cloud_detail-.5)*(.18+.2*cloud_vorticity)
                       +(cloud_filament-.5)*.075
                       +pressure_cloud_bias);
        cloud_relief=(cloud_detail-.5)*1.7+(cloud_filament-.5)*.55
                    +(.5-weather.b)*.8+(weather.a-.5)*clouds*.7;
        // The atlas describes a vertically active weather layer, not paint on
        // a smooth glass sphere. Promote its relief into a restrained embossed
        // normal: sunward faces of tall fronts catch the burin-white key while
        // their lee sides stay cut into the plate. Clamp the screen derivative
        // so low-resolution atlas texels cannot become faceted polygons.
        float2 cloud_relief_slope=clamp(float2(ddx(cloud_relief),ddy(cloud_relief))*5.2,-.24,.24);
        float3 cloud_lighting_normal=normalize(cloud_view_normal
                                             +float3(-cloud_relief_slope.x,
                                                     -cloud_relief_slope.y/flattening,
                                                     0.0));
        cloud_lambert=saturate(dot(cloud_lighting_normal,planet_light));
        // A surface point receives shadow from the cloud volume encountered
        // along its ray toward the star. Intersect that ray with the elevated
        // cloud sphere exactly: shadows stay close beneath the substellar point
        // and lengthen naturally at grazing incidence near the terminator.
        float local_cloud_height=saturate(.38+clouds*.34+cloud_relief*.16);
        float shadow_shell_radius=1.0+cloud_altitude*atmosphere*lerp(.58,1.22,local_cloud_height);
        float shadow_ray_b=dot(surface,surface_light);
        float shadow_ray_t=-shadow_ray_b+sqrt(max(shadow_ray_b*shadow_ray_b
                                                 +shadow_shell_radius*shadow_shell_radius-1.0,0.0));
        float3 shadow_direction=normalize(surface+surface_light*shadow_ray_t);
        float4 shadow_weather=atmosphere_sample(shadow_direction);
        float shadow_cloud=lerp(shadow_weather.r,shadow_weather.g,atmosphere_lerp);
        float shadow_spin=(shadow_weather.a-.5)*2.0;
        float3 shadow_detail_surface=planet_cloud_detail_coordinate(shadow_direction,seed,atmosphere_motion,shadow_spin);
        float shadow_detail=planet_fbm(shadow_detail_surface*18.0+float3(seed*.0017,3.0,7.0),seed+1237.0)*.5+.5;
        float shadow_filament=planet_fbm(shadow_detail_surface*41.0+float3(11.0,seed*.0011,5.0),seed+1291.0)*.5+.5;
        float shadow_vorticity=abs(shadow_spin);
        float shadow_pressure_cloud_bias=(.5-shadow_weather.b)*.14;
        shadow_cloud=saturate((shadow_cloud-.13)*1.24
                             +(shadow_detail-.5)*(.18+.2*shadow_vorticity)
                             +(shadow_filament-.5)*.075
                             +shadow_pressure_cloud_bias);
        cloud_shadow=shadow_cloud*lambert;
        cloud_gradient=float2(ddx(clouds),ddy(clouds));
        cloud_gradient_length=length(cloud_gradient);
        cloud_edge=saturate((abs(cloud_gradient.x)+abs(cloud_gradient.y))*15.0)*smoothstep(.10,.38,clouds);
        cloud_front_facing=smoothstep(-.18,.62,-dot(cloud_gradient/max(cloud_gradient_length,.0001),projected_cloud_light))
                          *smoothstep(.0005,.006,cloud_gradient_length);
        float cloud_light=.1+.9*cloud_lambert;
        float lee_relief=saturate(dot(cloud_view_normal-cloud_lighting_normal,planet_light)*3.2);
        float self_shadow=1.0-smoothstep(.42,1.0,clouds)*(.28+.18*lee_relief);
        material=lerp(material,.9,clouds*cloud_light*self_shadow*.82);
        float silver_lining=cloud_edge*clouds*pow(cloud_lambert,.65)*cloud_front_facing;
        material+=silver_lining*.12;
        float cloud_edge_pressure=kind<2.5?.48+.22*cloud_vorticity:.12+.12*cloud_vorticity;
        feature_edge=max(feature_edge,cloud_edge*cloud_edge_pressure);
        striation=saturate(striation+abs(weather.a-.5)*clouds*.42);
    } else if(kind<2.5) {
        material=lerp(material,.88,clouds*cloud_cover*.76);
        feature_edge=max(feature_edge,cloud_edge*cloud_cover*.44);
    }
    // Trace the sunward ray into the ring plane, then treat the annulus as a
    // particulate optical depth rather than an opaque sheet. A deterministic
    // particle sample turns local lane density into the chance that this ray
    // is occluded, so dense lanes gather into dark bands while gaps and thin
    // lanes transmit flecks of direct light.
    float ring_denominator=dot(ring_plane_normal,light);
    float ring_t=-dot(ring_plane_normal,normal)/ring_denominator;
    float3 ring_hit=normal+light*ring_t;
    float ring_hit_radius=length(ring_hit);
    float ring_inner_ratio=max(1.01,ring_inner_radius/radius);
    float ring_outer_ratio=ring_outer_radius/radius;
    float ring_shadow_envelope=(ring_t>0.0?1.0:0.0)*smoothstep(ring_inner_ratio,ring_inner_ratio+.055,ring_hit_radius)
                              *(1.0-smoothstep(ring_outer_ratio-.075,ring_outer_ratio,ring_hit_radius));
    float ring_shadow_coordinate=saturate((ring_hit_radius-ring_inner_ratio)/max(ring_outer_ratio-ring_inner_ratio,.001));
    float ring_shadow_gaps=smoothstep(.003,.009,abs(ring_shadow_coordinate-.197))
                          *smoothstep(.02,.043,abs(ring_shadow_coordinate-.695))
                          *smoothstep(.0025,.007,abs(ring_shadow_coordinate-.902))
                          *smoothstep(.0015,.0045,abs(ring_shadow_coordinate-.949));
    float ring_shadow_a_outer=lerp(1.0,1.0-smoothstep(.948,.958,ring_shadow_coordinate),saturn_proportions);
    float shadow_lane_phase=ring_shadow_coordinate*67.0;
    float shadow_lane=floor(shadow_lane_phase);
    float shadow_lane_pressure=.24+.7*volume_hash(float3(shadow_lane,seed*.013,31.0),seed+577.0);
    float shadow_fine_lane=1.0-smoothstep(.07,.2,abs(frac(shadow_lane_phase+.5)-.5));
    float2 particle_chart=float2(atan2(ring_hit.z,ring_hit.x)*173.0,ring_hit_radius*241.0);
    float2 particle_cell=floor(particle_chart);
    float particle_density=saturate((.12+shadow_lane_pressure*.68+shadow_fine_lane*.18)
                                  *ring_shadow_gaps*ring_shadow_a_outer*ring_shadow_envelope);
    float particle_chance0=volume_hash(float3(particle_cell,shadow_lane),seed+883.0);
    float particle_chance1=volume_hash(float3(particle_cell+float2(19.0,7.0),shadow_lane+11.0),seed+929.0);
    float particle_chance2=volume_hash(float3(particle_cell+float2(-5.0,23.0),shadow_lane+29.0),seed+971.0);
    float particle_block=(smoothstep(particle_chance0-.11,particle_chance0+.11,particle_density)
                         +smoothstep(particle_chance1-.11,particle_chance1+.11,particle_density)
                         +smoothstep(particle_chance2-.11,particle_chance2+.11,particle_density))/3.0;
    float ring_shadow=rings*ring_shadow_envelope*ring_shadow_gaps*particle_block;
    float illumination=(night_glance+lambert*.95)*(1.0-ring_shadow*.62)*(1.0-cloud_shadow*.34);
    float tone=saturate(illumination*limb*(.55+material*.5));
    // Engraved cuts live in the illuminated value groups. The unlit hemisphere
    // remains genuinely black; extra crossed layers accumulate toward the key
    // light instead of turning shadow into a bright wire mesh.
    float2 spherical_chart=float2(atan2(view_normal.x,max(view_normal.z,.001)),asin(clamp(view_normal.y,-1.0,1.0)));
    // Gas cuts follow the backward-advected atmosphere. This turns ruler-flat
    // latitude strokes into swept filaments that curl around vortices while
    // keeping solid worlds on a stable geographic engraving plate.
	float flow_longitude_delta=planet_wrap_longitude(flow_engraving_coordinate.x-spherical_chart.x);
	float flow_latitude_delta=clamp(flow_engraving_coordinate.y-spherical_chart.y,-.22,.22);
	float2 engraving_coordinate=spherical_chart
		+float2(flow_longitude_delta,flow_latitude_delta)*flow_engraving_strength;
	engraving_coordinate.x=planet_wrap_longitude(engraving_coordinate.x);
    // Cloud cuts occupy their own high shell. A slight seed-stable shear and
    // curl keeps them from sharing the exact registration of coastlines and
    // mountain hatching underneath.
    float cloud_shear=(cloud_relief+cloud_vorticity*.35)*.024;
    float2 cloud_spherical_chart=float2(atan2(cloud_view_normal.x,max(cloud_view_normal.z,.001)),asin(clamp(cloud_view_normal.y,-1.0,1.0)));
    float2 cloud_coordinate=cloud_spherical_chart+float2(cloud_shear+cloud_spin*.012,-cloud_shear*.46+cloud_spin*.006);
    float cloud_plate=smoothstep(.18,.58,clouds);
	// Giant planets have no visible solid ground: even relatively clear cells
	// look into deeper cloud and haze decks. Keep the plate continuous and let
	// fronts/vorticity control added detail, instead of swapping entire hatch
	// systems in and out as a camouflage mask.
	if(kind>=2.5&&kind<3.5) cloud_plate=lerp(.72,1.0,cloud_plate);
	else if(kind>=3.5) cloud_plate=lerp(.46,.9,cloud_plate);
	float2 engraving_chart_coordinate=lerp(engraving_coordinate,cloud_coordinate,cloud_plate);
	float2 chart=engraving_chart_coordinate*182.0;
	// Longitude/latitude collapses every longitude onto a single point at each
	// pole. As on the stellar plate, blend complete strokes into an azimuthal
	// cap chart before reaching that singularity. This retains the etched flow
	// without producing a false rosette or bundle of converging cuts.
	float engraving_latitude=clamp(engraving_chart_coordinate.y,-1.57079633,1.57079633);
	float engraving_cap_radius=1.57079633-abs(engraving_latitude);
	float2 engraving_cap_direction=float2(sin(engraving_chart_coordinate.x),cos(engraving_chart_coordinate.x));
	float2 engraving_cap_chart=engraving_cap_direction*engraving_cap_radius*182.0;
	if(engraving_latitude<0.0) engraving_cap_chart.y=-engraving_cap_chart.y;
	float engraving_cap_blend=smoothstep(.76,1.12,abs(engraving_latitude));
    float relief=(broad*.7+detail*.3)*3.6+(material-.5)*5.2+feature_edge*1.4
                +cloud_relief*cloud_plate*2.1;
	// Spend complexity on additional stable passes in genuinely structured
	// regions instead of manufacturing detail by distorting the base chart.
	float high_detail=saturate(feature_edge*.72+striation*.38+engraving_region*.24
		+cloud_plate*(cloud_edge*.5+cloud_vorticity*.32));
    float local_mark=ground_mark;
    if(mark_secondary_mask>.5) local_mark=secondary_mark;
    if(mark_accent_mask>.52) local_mark=accent_mark;
	if(clouds>.28||kind>=2.5) local_mark=cloud_mark;
    float coverage=0.0, sum=0.0, master_coverage=0.0;
    [unroll] for(int layer=0;layer<4;++layer) {
        float threshold=layer==0?.075:layer==1?.27:layer==2?.49:.7;
        if(layer>=2) {
            float relief_recruitment=kind<2.5?engraving_region*.18:engraving_region*.105;
			threshold=max(.12,threshold-relief_recruitment-high_detail*(layer==2?.24:.38));
        }
        if(tone>=threshold) {
            float angle;
            if(kind>=2.5) angle=layer<=1?1.5708:layer==2?1.24:.12;
            else if(kind<.5) angle=layer<=1?-.92+broad*.17:layer==2?.28+detail*.24:-.46+broad*.2;
            else if(kind<1.5) angle=layer<=1?-1.02+broad*.12+detail*.045
                                              :layer==2?.18+detail*.2:-.34+broad*.18;
            else angle=layer<=1?-.82+broad*.1:layer==2?.42+detail*.16:-.2+broad*.14;
            angle=planet_mark_angle(local_mark,layer,angle);
            // The reference plates build value from hundreds of hair-fine
            // cuts. Keep gas a touch broader so its streams remain legible,
            // but make solid worlds dense enough to read as engraving rather
            // than a contour-map overlay.
            float class_spacing=kind>=3.5?3.75:kind>=2.5?3.2:2.72;
            float spacing_scale;
            if(kind>=2.5) spacing_scale=layer<=1?1.0:layer==2?.91:1.12;
            else spacing_scale=layer<=1?1.0:layer==2?.79:1.23;
            float lane,along; float spacing=class_spacing*spacing_scale*planet_mark_spacing(local_mark);
            float nib=layer==0?.235:layer==1?.19:layer==2?.165:.14;
            float phase_offset=layer==1?spacing*.5:0.0;
			float line=planet_engraved_line(chart,angle,spacing,nib,relief*(1.0+layer*.19)+phase_offset,(float)layer,seed,lane,along);
			float stroke_wear=(layer<2?.1:.27)+planet_mark_wear(local_mark);
			line*=hatch_stroke_erosion(lane,along,(float)layer,stroke_wear);
			if(engraving_cap_blend>0.0) {
				float cap_lane,cap_along;
				float cap_line=planet_engraved_line(engraving_cap_chart,angle,spacing,nib,relief*(1.0+layer*.19)+phase_offset,(float)layer,seed,cap_lane,cap_along);
				cap_line*=hatch_stroke_erosion(cap_lane,cap_along,(float)layer,stroke_wear);
				line=lerp(line,cap_line,engraving_cap_blend);
			}
            float layer_pressure=layer==0?1.0:layer==1?.64:layer==2?.5:.31;
            // Material owns the density of the plate. Oceans retain long,
            // quiet cuts; continents and rocky uplands recruit crossed burin
            // work; ice stays pale between its sharper crystalline seams.
            float regional_pressure=1.0;
            if(kind<.5) regional_pressure=layer<2?lerp(.72,1.0,engraving_region):lerp(.24,1.0,engraving_region);
            else if(kind<1.5) regional_pressure=layer<2?lerp(.58,1.0,engraving_region):lerp(.12,1.0,engraving_region);
            else if(kind<2.5) regional_pressure=layer<2?lerp(.66,.9,engraving_region):lerp(.1,.52,engraving_region);
			else regional_pressure=layer<2?1.0:lerp(.22,1.0,high_detail);
            if(cloud_plate>0.0) {
                // Dense fronts receive one confident contour family; thinner
                // cloud banks retain broken hairlines and black breathing room.
                float cloud_pressure=layer<2?lerp(.42,1.08,clouds):lerp(.08,.56,clouds);
                regional_pressure=lerp(regional_pressure,cloud_pressure,cloud_plate);
            }
            float value_pressure=smoothstep(threshold,threshold+.16,tone);
            line*=layer_pressure*regional_pressure*value_pressure;
            coverage=max(coverage,line); sum+=line;
            if(layer==0&&!(kind>=1.5&&kind<2.5)) {
                // Sparse master cuts organize the bed of hairlines the way an
                // engraver periodically leans on the burin. They share the
                // local relief, but never become a uniform second grid.
                float master_lane,master_along;
                float master=planet_engraved_line(chart,angle,spacing*7.0,nib*1.9,
                    relief*1.08,(float)layer+7.0,seed+43.0,master_lane,master_along);
                master*=hatch_stroke_erosion(master_lane,master_along,7.0,.08);
				if(engraving_cap_blend>0.0) {
					float master_cap_lane,master_cap_along;
					float master_cap=planet_engraved_line(engraving_cap_chart,angle,spacing*7.0,nib*1.9,
						relief*1.08,(float)layer+7.0,seed+43.0,master_cap_lane,master_cap_along);
					master_cap*=hatch_stroke_erosion(master_cap_lane,master_cap_along,7.0,.08);
					master=lerp(master,master_cap,engraving_cap_blend);
				}
                float master_region=kind<.5?lerp(.28,.62,engraving_region)
                                  :kind<1.5?lerp(.12,.52,engraving_region)
                                  :kind>=2.5?lerp(.24,.46,engraving_region):0.0;
                master_coverage=max(master_coverage,master*master_region*value_pressure);
            }
        }
    }
    float hatch=saturate(coverage*.68+max(sum-coverage,0.0)*.24+master_coverage*.38);
	// One hair-fine diagnostic pass belongs only to genuinely complex material.
	// It reveals storm rims, shear fronts, mountain spines and fractures without
	// bending the long base strokes or screening the quiet regions uniformly.
	if(high_detail>.16&&tone>.16) {
		float detail_lane,detail_along;
		float detail_angle=kind>=2.5?.28+detail*.10:.46+striation*.18;
		float detail_cut=planet_engraved_line(chart,detail_angle,1.42,.082,relief*1.31,11.0,seed+1607.0,detail_lane,detail_along);
		detail_cut*=hatch_stroke_erosion(detail_lane,detail_along,11.0,.34);
		if(engraving_cap_blend>0.0) {
			float detail_cap_lane,detail_cap_along;
			float detail_cap=planet_engraved_line(engraving_cap_chart,detail_angle,1.42,.082,relief*1.31,11.0,seed+1607.0,detail_cap_lane,detail_cap_along);
			detail_cap*=hatch_stroke_erosion(detail_cap_lane,detail_cap_along,11.0,.34);
			detail_cut=lerp(detail_cut,detail_cap,engraving_cap_blend);
		}
		hatch=saturate(hatch+detail_cut*smoothstep(.16,.72,high_detail)*.34);
	}
    float contour=1.0-smoothstep(.006,.024,abs(sqrt(r2)-radius));
    float contour_light=.7*smoothstep(-.055,.48,dot(normal,light));
    float contour_break=.72+.28*volume_hash(float3(floor(chart.y*.18),floor(chart.x*.11),seed*.01),seed+1327.0);
    contour_light*=contour_break;
    float topographic=feature_edge*lambert*(1.0-ring_shadow*.62)*(.075+.095*striation);
    float stipple_density=kind<.5?saturate(.035+striation*.12+engraving_region*.035)*smoothstep(.1,.58,tone)
                         :kind<1.5?saturate(.012+cloud_edge*.09+striation*.045)*smoothstep(.16,.64,tone)
                         :kind<2.5?saturate(.008+feature_edge*.04)*smoothstep(.22,.68,tone)
                         :saturate(.008+feature_edge*.055+striation*.018)*smoothstep(.18,.66,tone);
    stipple_density=saturate(stipple_density+planet_mark_stipple(local_mark)*smoothstep(.16,.64,tone));
    float stipple=planet_micro_stipple(chart,seed,stipple_density);
	if(engraving_cap_blend>0.0) stipple=lerp(stipple,planet_micro_stipple(engraving_cap_chart,seed,stipple_density),engraving_cap_blend);
    float ink;
    if(kind>=1.5&&kind<2.5) {
        // Ice is the light-ground plate in the family: broad bone-white planes
        // catch the sun, while fractures and restrained hatch are incised back
        // into them. This keeps it unmistakable beside dark rocky worlds.
        float ice_day=smoothstep(.025,.16,tone);
        float ice_plate_grain=.94+.06*planet_fbm(surface*31.0,seed+1201.0);
        float ice_ground=ice_day*(.16+.8*pow(tone,.68))*ice_plate_grain;
        float ice_incisions=saturate(engraving_groove*.58+feature_edge*.1
                                   +hatch*(.17+.15*(1.0-tone))+stipple*.16);
        ink=saturate(ice_ground*(1.0-ice_incisions)+contour*contour_light+topographic*.2);
    } else {
        ink=saturate(tone*.035+hatch*(.34+.74*tone)+contour*contour_light
                   +topographic*1.28+stipple*.34);
    }
	// The unlit hemisphere remains an engraved plate, not a flat black cutout.
	// Sparse broken marks gather near the terminator and real material detail,
	// then disappear again toward the deepest core shadow.
	float signed_light=dot(normal,light);
	float shadow_side=1.0-smoothstep(-.06,.10,signed_light);
	float shadow_reach=smoothstep(-.82,-.12,signed_light);
	float shadow_visibility=shadow_side*shadow_reach*(.38+.62*high_detail);
	if(shadow_visibility>.001) {
		float shadow_lane,shadow_along;
		float shadow_angle=kind>=2.5?1.48:.18+striation*.16;
		float shadow_cut=planet_engraved_line(chart,shadow_angle,5.4,.105,relief*.72,17.0,seed+2089.0,shadow_lane,shadow_along);
		shadow_cut*=hatch_stroke_erosion(shadow_lane,shadow_along,17.0,.62);
		if(engraving_cap_blend>0.0) {
			float shadow_cap_lane,shadow_cap_along;
			float shadow_cap=planet_engraved_line(engraving_cap_chart,shadow_angle,5.4,.105,relief*.72,17.0,seed+2089.0,shadow_cap_lane,shadow_cap_along);
			shadow_cap*=hatch_stroke_erosion(shadow_cap_lane,shadow_cap_along,17.0,.62);
			shadow_cut=lerp(shadow_cut,shadow_cap,engraving_cap_blend);
		}
		float shadow_stipple=planet_micro_stipple(chart,seed+2141.0,.018+.045*high_detail);
		if(engraving_cap_blend>0.0) shadow_stipple=lerp(shadow_stipple,planet_micro_stipple(engraving_cap_chart,seed+2141.0,.018+.045*high_detail),engraving_cap_blend);
		ink=saturate(ink+(shadow_cut*.085+shadow_stipple*.045)*shadow_visibility);
	}
    // A long grazing path through a solid world's atmosphere suppresses
    // low-altitude ground engraving before the bright limb is laid back in.
    // Elevated cloud plates retain most of their pressure, giving the weather
    // layer real depth instead of fading surface and clouds as one flat decal.
    if(kind<2.5) {
        float aerial_path=pow(1.0-z,3.2)*atmosphere*lerp(.22,.58,atmosphere);
        float ground_fraction=1.0-cloud_plate*.78;
        ink*=1.0-saturate(aerial_path*ground_fraction);
    }
    // The leading edge of a cloud bank receives one restrained burin-bright
    // cut. It remains subordinate to the hatch field but separates weather
    // fronts from coastlines at modal delivery size.
    float cloud_front_class=kind<2.5?1.0:.16;
    float cloud_front=cloud_edge*smoothstep(.16,.52,clouds)*pow(cloud_lambert,.58)
                     *(.055+.12*cloud_vorticity)*cloud_front_class*cloud_front_facing;
    ink=saturate(ink+cloud_front*(1.0-ink*.55));
    float atmosphere_day=smoothstep(-.3,.62,dot(normal,light));
    float2 limb_fields=planet_atmosphere_limb_fields(surface,seed,atmosphere_motion);
    float limb_veil=lerp(.42,1.0,smoothstep(.18,.66,limb_fields.x+(limb_fields.y-.5)*.38));
    float limb_pressure=limb_fields.x*limb_veil*lerp(1.0,1.08,clouds);
    float atmosphere_rim=pow(1.0-z,6.0)*atmosphere*limb_pressure*(.012+.55*atmosphere_day);
    // A narrow bright line nested inside the broader haze gives the limb the
    // cut-metal hierarchy of the rest of the survey plate.
    float limb_etch=smoothstep(.08,.38,limb_fields.y);
    atmosphere_rim+=pow(1.0-z,18.0)*atmosphere*limb_pressure*limb_etch*(.02+.31*atmosphere_day);
    ink=max(ink,atmosphere_rim);
    // Geometric albedo controls broad daylight value independently of hue.
    // The display-space curve keeps low-albedo worlds readable without making
    // them as reflective as the cloud decks of Venus or the giant planets.
    float local_albedo=clamp(geometric_albedo*lerp(.72,1.34,material),.025,.92);
    float perceived_albedo=pow(local_albedo,1.0/2.2);
    float reflected_floor=tone*perceived_albedo*.24;
    ink=saturate(max(ink,reflected_floor)*lerp(.82,1.18,perceived_albedo));
    // The globe occludes the rear half. Only the near-side projected arcs cross
    // its lower hemisphere, preserving an immediate front/back depth read.
    float near_ring=ring_plane_y>0.0?ring_cut:0.0;
    float near_ring_opacity=ring_plane_y>0.0?ring_opacity:0.0;
    ink=saturate(ink*(1.0-near_ring_opacity*.96)+near_ring*.94);
    float3 component_tint=planet_mark_tint(local_mark);
	if(has_atmosphere_atlas>0&&atmosphere>0.0) {
		float4 atmospheric_mixture=atmosphere_composition_sample(surface);
		float3 atmospheric_tint=planet_cloud_composition_tint(atmospheric_mixture);
		// Methane colors a planet through accumulated absorption along the whole
		// optical path, not by painting methane ice or isolated cloud marks blue.
		// Sulfur-bearing aerosol contributes a weaker cream veil; water and
		// ammonia remain primarily cloud-local effects.
		float absorption_path=atmosphere*saturate(atmospheric_mixture.z*1.2+atmospheric_mixture.w*.32);
		component_tint=lerp(component_tint,atmospheric_tint,absorption_path*.68);
	}
    if(has_atmosphere_atlas>0&&cloud_plate>0.0) {
        float3 cloud_component_tint=planet_cloud_composition_tint(atmosphere_composition_sample(cloud_surface));
        component_tint=lerp(component_tint,cloud_component_tint,cloud_plate);
    }
    float component_luminance=dot(component_tint,float3(.2126,.7152,.0722));
	// Preserve the etched light hierarchy, but do not normalize very dark
	// materials all the way back to white: carbon and deep ocean must remain
	// materially darker than silicate even where their hatch density matches.
	float3 value_preserving_tint=component_tint/max(component_luminance,.35);
    float3 engraved_tint=tint*lerp(float3(1.0,1.0,1.0),value_preserving_tint,.45);
    return float4(engraved_tint*saturate(ink),input.color.a);
}
// Approximate a blackbody's display color. Real stellar colors are mostly
// near-white: temperature shifts the balance without producing neon primaries.
float3 star_blackbody_srgb(float kelvin) {
    float t=clamp(kelvin,1000.0,40000.0)/100.0;
    float red=t<=66.0?1.0:saturate(1.292936186*pow(t-60.0,-.1332047592));
    float green=t<=66.0?saturate(.390081579*log(t)-.631841444):saturate(1.129890861*pow(t-60.0,-.0755148492));
    float blue=t>=66.0?1.0:t<=19.0?0.0:saturate(.543206789*log(t-10.0)-1.196254089);
    return float3(red,green,blue);
}
// Project a point on the apparent stellar limb back onto the rotating sphere
// and sample the low-rate surface magnetogram. Returns signed radial field and
// magnitude, allowing coronal loops to require plausible bipolar footpoints.
float2 star_limb_flux(float limb_angle,float rotation,float phase) {
    float3 n=float3(cos(limb_angle),sin(limb_angle),0.0);
    float cr=cos(rotation),sr=sin(rotation);
    n=float3(n.x,n.y*cr-n.z*sr,n.y*sr+n.z*cr);
    float cp=cos(phase),sp=sin(phase);
    float3 surface=float3(n.x*cp+n.z*sp,n.y,-n.x*sp+n.z*cp);
    float latitude=asin(clamp(surface.y,-1.0,1.0));
    float longitude=atan2(surface.x,surface.z);
    float2 uv=float2(frac(longitude/(2.0*3.14159265)+.5),latitude/3.14159265+.5);
    float4 flux=ui_texture.Sample(ui_sampler,uv);
    return float2(flux.r*2.0-1.0,flux.g);
}
float4 procedural_star(VertexOutput input) {
    float kind=push.texture_hatch.y,seed=push.texture_hatch.z,phase=push.texture_hatch.w;
	// Additional evolutionary plates share the photospheric machinery of their
	// nearest physical class, then add their own large-scale structure below.
	bool stripped_star=kind>=5.5&&kind<6.5;
	bool protostar=kind>=6.5;
	if(stripped_star) kind=2.0;
	if(protostar) kind=0.0;
    float activity=saturate(push.hatch_shape.x),spots=saturate(push.hatch_shape.y);
    float granulation=saturate(push.hatch_shape.z),corona=saturate(push.hatch_shape.w);
    float rotation=push.hatch_tone.x,radius=push.hatch_tone.y>.1?push.hatch_tone.y:.70;
    float default_temperature=kind<.5?5772.0:kind<1.5?3900.0:kind<2.5?18000.0:kind<3.5?10000.0:kind<4.5?600000.0:1000.0;
    float temperature=push.hatch_tone.z>100.0?push.hatch_tone.z:default_temperature;
    float luminosity=max(push.hatch_tone.w,.0001),mass=max(push.hatch_offset.x,.0001),physical_radius=max(push.hatch_offset.y,.000001);
    float stellar_time=push.hatch_offset.z,rotation_rate=push.hatch_offset.w;
    float surface_gravity=mass/(physical_radius*physical_radius);
    float2 q=(input.uv-.5)*2.0; float distance=length(q);
    float3 authored_tint=srgb_to_linear(input.color.rgb);
    float3 blackbody=srgb_to_linear(star_blackbody_srgb(temperature));
    // Disk-integrated stellar colors are subtle to a broadband-adapted eye.
    // Retain enough chroma to order temperature in the midtones, but keep hot
    // luminous bodies near white instead of rendering them as blue UI lamps.
    float chroma_strength=kind<.5?.43:kind<1.5?.64:kind<2.5?.36:kind<3.5?.22:.32;
    float3 observed_blackbody=lerp(float3(1.0),blackbody,chroma_strength);
    float3 tint=authored_tint*observed_blackbody;
    if(kind>=4.5) {
        float spin=phase+stellar_time*rotation_rate;
        float2 axis=float2(cos(rotation),sin(rotation));
        float along=dot(q,axis),across=q.x*axis.y-q.y*axis.x;
        float disk_radius=radius*3.25,disk_thickness=.035+.09*abs(along)/max(disk_radius,.001);
        float disk=exp(-abs(across)/disk_thickness)*(1.0-smoothstep(disk_radius*.78,disk_radius,abs(along)))*smoothstep(radius*.55,radius*.82,abs(along));
        float approaching=along<0.0?1.0:.38;
        float grain=.7+.3*volume_noise(float3(along*18.0,across*40.0,seed*.01+spin),seed+2707.0);
        float lens=exp(-abs(distance-radius*.72)*72.0)*3.2;
        float shadow=1.0-smoothstep(radius*.45,radius*.68,distance);
        float radiance=disk*approaching*grain*6.5+lens;
        if(shadow>.02) return float4(float3(.002),1.0);
        if(radiance<.002) discard;
        float3 disk_ink=lerp(float3(.82,.78,.65),float3(.92,.94,.91),saturate(abs(along)/disk_radius));
        return float4(disk_ink*radiance,saturate(radiance)*input.color.a);
    }
    // A neutron star is not a textured miniature sun. Its readable structure
    // is the rotating magnetosphere and two relativistically bright hot caps.
    if(kind>=3.5) {
        float spin=phase+stellar_time*rotation_rate;
        float2 axis=normalize(float2(cos(spin),sin(spin)*.42));
        float beam_perpendicular=q.x*axis.y-q.y*axis.x;
        float beam_signed=dot(q,axis),beam_along=abs(beam_signed);
        float cone_width=.012+beam_along*.075;
        float cone_wall=exp(-abs(abs(beam_perpendicular)-cone_width)*310.0);
        float cone_fill=exp(-beam_perpendicular*beam_perpendicular/max(cone_width*cone_width,.00002))*.12;
        float beam_extent=smoothstep(.055,.13,beam_along)*(1.0-smoothstep(.72,1.03,beam_along));
        float approaching=beam_signed>=0.0?1.0:.27;
        float pulse_break=.56+.44*volume_noise(float3(beam_along*18.0,beam_perpendicular*31.0,seed*.019),seed+2531.0);
        float beam=(cone_wall+cone_fill)*beam_extent*approaching*pulse_break;
        float cap_offset=radius*.11;
        float near_cap=exp(-dot(q-axis*cap_offset,q-axis*cap_offset)/max(radius*radius*.018,.00001))*5.2;
        float far_cap=exp(-dot(q+axis*cap_offset,q+axis*cap_offset)/max(radius*radius*.022,.00001))*2.1;
        float compact_disk=exp(-distance*distance/max(radius*radius*.13,.0001))*1.25;
        float lens=exp(-abs(distance-radius*.34)*105.0)*.42;
        float parallel=dot(q,axis),perpendicular=q.x*axis.y-q.y*axis.x;
        float shell_coordinate=sqrt(pow(parallel/max(radius*2.35,.001),2.0)+pow(perpendicular/max(radius*1.18,.001),2.0));
        float shell_a=exp(-abs(shell_coordinate-1.0)*42.0);
        float shell_b=exp(-abs(shell_coordinate-1.48)*35.0)*.52;
        float shell_angle=atan2(perpendicular/max(radius*1.18,.001),parallel/max(radius*2.35,.001));
        float shell_break=smoothstep(.18,.62,volume_noise(float3(cos(shell_angle)*5.0,sin(shell_angle)*5.0,seed*.021),seed+2557.0));
        float magnetosphere=(shell_a+shell_b)*shell_break*(.11+.15*activity);
        float core=near_cap+far_cap+compact_disk;
        float radiance=core+lens+beam*2.35+magnetosphere;
        if(radiance<.002) discard;
        return float4(lerp(tint,float3(1),saturate(core*.42))*radiance,saturate(radiance)*input.color.a);
    }
	// A protostar is read by its occulting formation disk and bipolar cavities,
	// not by turning the whole plate orange. Broken etched bands preserve black
	// space and keep the treatment archival rather than nebular.
	if(protostar&&distance>radius) {
		float disk_y=q.y*cos(rotation)-q.x*sin(rotation);
		float disk_x=q.x*cos(rotation)+q.y*sin(rotation);
		float disk_extent=radius*1.46;
		float disk_edge=(1.0-smoothstep(disk_extent*.76,disk_extent,abs(disk_x)));
		float disk_lane=exp(-abs(disk_y)/(.018+abs(disk_x)*.055))*disk_edge*smoothstep(radius*.72,radius*.98,abs(disk_x));
		float etched=.48+.52*volume_noise(float3(disk_x*21.0,disk_y*53.0,seed*.017),seed+2819.0);
		float proto_radiance=disk_lane*etched*.72;
		if(proto_radiance>.003) return float4(tint*proto_radiance,saturate(proto_radiance*2.4)*input.color.a);
	}
    float angle=atan2(q.y,q.x);
    // Low surface gravity lets a giant's photospheric edge follow its largest
    // convection cells. This is a small material displacement, not a noisy
    // decorative outline, and it evolves on the same slow deterministic clock.
    float pulsation=kind>.5&&kind<1.5?sin(stellar_time*.17+seed*.01)*.012:0.0;
    float giant_limb_noise=volume_noise(float3(cos(angle)*1.7,sin(angle)*1.7,seed*.011+stellar_time*.006),seed+2381.0)*2.0-1.0;
    float giant_limb_detail=volume_noise(float3(cos(angle)*4.3,sin(angle)*4.3,seed*.019-stellar_time*.004),seed+2417.0)*2.0-1.0;
    float limb_deformation=kind>.5&&kind<1.5?giant_limb_noise*.015+giant_limb_detail*.004:0.0;
    radius*=1.0+pulsation+limb_deformation;
    // A handful of independent magnetic active regions replace the old
    // periodic spoke function. Each loop owns its longitude, footpoint span,
    // reach, curvature, brightness, and lifecycle; no opposite-side copy is
    // implied, so the corona cannot settle into rotational symmetry.
    float corona_noise=planet_fbm(float3(cos(angle)*2.1,sin(angle)*2.1,seed*.003),seed+1709.0)*.5+.5;
    float wind_axis=(volume_hash(float3(seed*.013,17.0,5.0),seed+2441.0)*2.0-1.0)*3.14159265;
    float wind_offset=atan2(sin(angle-wind_axis),cos(angle-wind_axis));
    float wind_lobe=exp(-wind_offset*wind_offset/.16)*(0.62+0.38*corona_noise);
    float corona_extent=radius*(1.10+corona*(.22+.19*corona_noise));
    if(kind>=1.5&&kind<2.5) corona_extent+=radius*(stripped_star?.62:.34)*wind_lobe;
    // Optical bloom is distinct from the structured corona: a smooth,
    // temperature-colored envelope produced by the overbright photosphere.
    // Keep it local enough that the surrounding black field remains useful.
    float bloom_width=lerp(.085,.145,saturate(activity*.55+corona*.45));
    if(kind>=2.5&&kind<3.5) bloom_width*=.72;
    float bloom_extent=radius+bloom_width*3.2;
    if(distance>radius) {
        if(distance>max(corona_extent,bloom_extent)) discard;
        float falloff=1.0-smoothstep(radius,corona_extent,distance);
        float height=max(distance-radius,0.0);
        float magnetic_structure=0.0,footpoint_light=0.0,ejecta=0.0;
        [unroll] for(int region=0;region<5;++region) {
            float salt=(float)region*67.0;
            float region_gate=region==0?1.0:step(.62,volume_hash(float3(salt+5.0,seed*.023,71.0),seed+1999.0));
            // Candidate existence and lifecycle are uniform for the whole
            // draw. Skip dormant regions before their magnetogram samples and
            // strand noise; this keeps rare flares rare computationally too.
            if(region_gate<=0.0) continue;
            float life=lerp(38.0,125.0,volume_hash(float3(salt,seed*.011,3.0),seed+2011.0));
            float age_coordinate=stellar_time/life+volume_hash(float3(salt,7.0,seed*.017),seed+2027.0)*3.0;
            float cycle=floor(age_coordinate),age=frac(age_coordinate);
            float cycle_seed=seed+salt+cycle*131.0;
            float center=(volume_hash(float3(salt+11.0,cycle,seed*.003),cycle_seed)*2.0-1.0)*3.14159265;
            center+=stellar_time*rotation_rate*lerp(.72,1.18,volume_hash(float3(salt,cycle,19.0),cycle_seed));
            float angular_offset=atan2(sin(angle-center),cos(angle-center));
            float half_span=lerp(.045,.19,volume_hash(float3(salt+23.0,cycle,5.0),cycle_seed));
            float normalized=angular_offset/half_span;
            // Loop strands are zero beyond |normalized|=1.05. Rare ejecta
            // have a wider Gaussian tail, but by five spans their maximum
            // possible contribution is below the visible/opacity threshold.
            // Reject those fragments before magnetogram reads and strand
            // noise so each pixel evaluates only nearby active regions.
            if(abs(normalized)>5.0) continue;
            if(push.hatch_angles.x>.5) {
                float2 foot_a=star_limb_flux(center-half_span*.82,rotation,phase);
                float2 foot_b=star_limb_flux(center+half_span*.82,rotation,phase);
                float opposite_polarity=smoothstep(.035,.22,abs(foot_a.x-foot_b.x));
                float footpoint_strength=smoothstep(.018,.20,max(foot_a.y,foot_b.y));
                float magnetic_anchor=saturate(opposite_polarity*.68+footpoint_strength*.52);
                region_gate*=.08+.92*magnetic_anchor;
            }
            float envelope=smoothstep(0.0,.14,age)*(1.0-smoothstep(.62,1.0,age))*region_gate;
            if(envelope<=.0001) continue;
            float reach=radius*lerp(.045,.22,volume_hash(float3(salt+31.0,cycle,13.0),cycle_seed))*lerp(.55,1.0,activity);
            float skew=lerp(-.7,.7,volume_hash(float3(salt+41.0,cycle,17.0),cycle_seed));
            float arch_height=reach*saturate(1.0-normalized*normalized)*(1.0+skew*normalized*.35);
            float corrugation=sin(normalized*11.0+cycle_seed*.019)*.045+sin(normalized*23.0-cycle_seed*.011)*.018;
            arch_height*=1.0+corrugation;
            float thickness=lerp(.004,.014,volume_hash(float3(salt+47.0,cycle,29.0),cycle_seed))*radius;
            float primary_strand=exp(-abs(height-arch_height)/max(thickness,.001));
            float strand_split=thickness*(2.2+volume_hash(float3(salt,cycle,61.0),cycle_seed)*2.8);
            float secondary_strand=exp(-abs(height-(arch_height+strand_split))/max(thickness*.62,.001))*.42;
            float dry_break=.58+.42*volume_noise(float3(normalized*19.0,height/max(reach,.001)*13.0,cycle_seed*.007),cycle_seed+71.0);
            float loop=(primary_strand+secondary_strand)*dry_break*(1.0-smoothstep(.88,1.05,abs(normalized)));
            float pressure=lerp(.16,.72,volume_hash(float3(salt+53.0,cycle,37.0),cycle_seed));
            magnetic_structure+=loop*envelope*pressure;
            float feet=exp(-height*height/max(thickness*thickness*8.0,.00001))*exp(-abs(abs(normalized)-.82)*18.0);
            footpoint_light+=feet*envelope*pressure;
            // Rare one-sided mass ejections broaden and bend as they climb.
            float eruptive=step(.78,volume_hash(float3(salt+59.0,cycle,43.0),cycle_seed))*smoothstep(.16,.34,age)*(1.0-smoothstep(.58,.82,age));
            float plume_center=center+skew*height/max(radius,.001)*.9;
            float plume_offset=atan2(sin(angle-plume_center),cos(angle-plume_center));
            float plume_width=half_span*(.32+height/max(reach,.001)*1.4);
            float plume=exp(-plume_offset*plume_offset/max(plume_width*plume_width,.0001))*exp(-height/max(reach*1.7,.001));
            ejecta+=plume*eruptive*pressure;
        }
        float magnetic_class=kind>.5&&kind<1.5?.62:kind>=1.5&&kind<2.5?.38:kind>=2.5?.055:1.0;
        float wind_class=kind>=1.5&&kind<2.5?1.8:1.0;
        float quiet_corona=falloff*corona*(.018+.032*corona_noise)*wind_class;
        // Hot luminous stars drive line-accelerated winds. Render the dominant
        // lobe as several dry, diverging cuts rather than a symmetric aura.
        float normalized_height=height/max(radius,.001);
        float wind_bend=sin(normalized_height*5.2+seed*.071)*.012;
        float fan_coordinate=(wind_offset-wind_bend)*82.0/(1.0+normalized_height*.52)+seed*.037;
        float wind_comb=pow(.5+.5*cos(fan_coordinate),13.0);
        float central_ray=exp(-abs(wind_offset-wind_bend)*260.0);
        float ray_id=floor((fan_coordinate+3.14159265)/(2.0*3.14159265));
        float ray_character=volume_hash(float3(ray_id,seed*.017,31.0),seed+2503.0);
        float ray_survival=step(.18,ray_character);
        float ray_reach=lerp(.105,.34,ray_character);
        float wind_filaments=(wind_comb*.72*ray_survival+central_ray*.34)*exp(-normalized_height/ray_reach);
        float wind_break=.68+.32*volume_noise(float3(wind_offset*11.0,normalized_height*15.0,seed*.023),seed+2473.0);
        float blue_wind=kind>=1.5&&kind<2.5?wind_lobe*(.012*exp(-normalized_height/.19)+(stripped_star?.52:.31)*wind_filaments)*wind_break*corona:0.0;
        // Resolve the chromosphere as a forest of short, individually seeded
        // spicules. Each cut has its own reach, lean, pressure, and survival;
        // the angular carrier only distributes candidates and is never shown
        // as a complete radial comb. Magnetic limb flux preferentially lights
        // active plage without forcing bilateral symmetry.
        float spicule_class=kind<.5?1.0:kind<1.5?.72:kind<2.5?.24:0.0;
        float spicule_count=157.0;
        float spicule_coordinate=(angle+3.14159265)/(2.0*3.14159265)*spicule_count;
        float spicule_id=floor(spicule_coordinate);
        float spicule_character=volume_hash(float3(spicule_id,seed*.019,47.0),seed+2671.0);
        float spicule_lean=lerp(-1.35,1.35,volume_hash(float3(spicule_id,seed*.031,53.0),seed+2683.0));
        float spicule_lane=abs(frac(spicule_coordinate+normalized_height*spicule_lean)-.5)*2.0;
        float spicule_reach=radius*lerp(.009,.041,spicule_character)*lerp(.62,1.0,activity);
        float spicule_profile=exp(-height/max(spicule_reach,.0005))*(1.0-smoothstep(spicule_reach*.72,spicule_reach*1.28,height));
        float spicule_cut=1.0-smoothstep(.055,.18,spicule_lane);
        float spicule_break=.38+.62*volume_noise(float3(spicule_id*.31,normalized_height*93.0,seed*.013),seed+2699.0);
        float spicule_survival=step(.43,spicule_character);
        float limb_flux_gain=1.0;
        if(push.hatch_angles.x>.5) {
            float2 local_limb_flux=star_limb_flux(angle,rotation,phase);
            limb_flux_gain=.58+.82*smoothstep(.025,.24,local_limb_flux.y);
        }
        float spicules=spicule_cut*spicule_profile*spicule_break*spicule_survival*limb_flux_gain*spicule_class*(.10+.22*activity);
        float streamer=quiet_corona+blue_wind+spicules+(magnetic_structure*.62+footpoint_light*.28+ejecta*.34)*magnetic_class;
        float rim_break=smoothstep(.18,.72,volume_noise(float3(cos(angle)*5.0,sin(angle)*5.0,seed*.009),seed+2213.0));
        float rim=exp(-abs(distance-radius)*145.0)*(.065+.19*corona)*(.32+.68*rim_break);
        float bloom_distance=max(distance-radius,0.0);
        float bloom_core=exp(-bloom_distance*bloom_distance/(2.0*bloom_width*bloom_width));
        float bloom_outer=exp(-bloom_distance/max(bloom_width*1.75,.001));
        float bloom=(bloom_core*.72+bloom_outer*.28)*lerp(.15,.29,saturate(activity*.45+corona*.55));
        float structured=max(streamer,rim);
        float opacity=saturate(structured+bloom);
        // The inner aureole tends toward white from exposure while its outer
        // falloff retains the star's temperature color.
        float3 bloom_tint=lerp(tint,float3(1.0),bloom_core*.32);
        return float4(bloom_tint*(structured+bloom),opacity*input.color.a);
    }
    float z=sqrt(max(radius*radius-distance*distance,0.0))/radius;
    float3 normal=normalize(float3(q/radius,z));
    float cr=cos(rotation),sr=sin(rotation); normal=float3(normal.x,normal.y*cr-normal.z*sr,normal.y*sr+normal.z*cr);
    float cp=cos(phase),sp=sin(phase); float3 surface=float3(normal.x*cp+normal.z*sp,normal.y,-normal.x*sp+normal.z*cp);
    float evolution=stellar_time*lerp(.018,.065,activity);
    float3 evolved_surface=surface+float3(sin(evolution+surface.y*3.0),cos(evolution*.73+surface.x*4.0),sin(evolution*.41))*activity*.018;
    float convection=planet_fbm(evolved_surface*lerp(4.0,9.0,granulation)+evolution*.12,seed+1511.0)*.5+.5;
    float meso_convection=planet_fbm(evolved_surface*(kind>.5&&kind<1.5?2.25:13.5)+float3(19.0,7.0,31.0)+evolution*.07,seed+1543.0)*.5+.5;
    float cells=convection*.58+meso_convection*.42;
    float cell_edge=0.0;
    if(kind>.5&&kind<1.5) {
        // Only a low-gravity giant benefits from resolvable, immense cell
        // territories. Other classes use the advected turbulent fields above,
        // avoiding an expensive Voronoi solve whose geometry is intentionally
        // invisible in the final engraving.
        float giant_edge;
        float giant_cells=voronoi_voxel_density(evolved_surface*3.7+seed*.001,seed+1409.0,.08,giant_edge);
        float secondary_edge;
        float3 secondary_domain=evolved_surface.yzx*4.65+float3(7.1,13.7,3.9)+seed*.0017;
        float secondary_cells=voronoi_voxel_density(secondary_domain,seed+1451.0,.17,secondary_edge);
        float broad_warp=planet_fbm(evolved_surface*1.7+float3(5.0,11.0,2.0),seed+1471.0)*.5+.5;
        giant_cells=lerp(giant_cells,secondary_cells,.28+.22*broad_warp);
        cells=lerp(cells,giant_cells,.27);
        cell_edge=lerp(giant_edge,secondary_edge,.35);
        float edge_break=smoothstep(.48,.72,planet_fbm(evolved_surface*8.7+float3(5.0,23.0,11.0),seed+1567.0)*.5+.5);
        cell_edge*=edge_break*.24;
    }
    float latitude=asin(clamp(surface.y,-1.0,1.0)); float longitude=atan2(surface.x,surface.z);
    float2 surface_flux_uv=float2(frac(longitude/(2.0*3.14159265)+.5),latitude/3.14159265+.5);
    float4 surface_flux=float4(.5,0.0,.5,1.0);
    if(push.hatch_angles.x>.5) {
        surface_flux=ui_texture.Sample(ui_sampler,surface_flux_uv);
        float simulated_thermal=surface_flux.b*2.0-1.0;
        float thermal_response=kind<.5?.46:kind<1.5?.44:kind<2.5?.10:0.0;
        convection=saturate(convection+simulated_thermal*thermal_response);
        cells=saturate(cells+simulated_thermal*thermal_response*.35);
    }
    float differential=longitude+sin(latitude*2.0)*activity*.55;
    float belts=.5+.5*sin(latitude*lerp(8.0,15.0,activity)+convection*2.4);
    float spot_field=planet_fbm(surface*4.1+float3(9.0+stellar_time*rotation_rate,3.0,17.0),seed+1601.0)*.5+.5;
    float active_latitudes=smoothstep(.12,.42,abs(latitude))*(1.0-smoothstep(.72,1.1,abs(latitude)));
    float spot_threshold=.76-activity*.1;
    float spot_mask=smoothstep(spot_threshold,.88-spots*.06,spot_field)*spots*active_latitudes;
    float penumbra=(1.0-smoothstep(.035,.13,abs(spot_field-spot_threshold)))*spots*active_latitudes;
    float facula=(1.0-smoothstep(.018,.085,abs(spot_field-(spot_threshold-.055))))*pow(1.0-z,1.7);
    float magnetic_inversion=0.0;
    if(push.hatch_angles.x>.5) {
        // A low-rate surface-flux-transport plate supplies magnetic history.
        // R stores signed radial field and G stores its magnitude. Bilinear
        // sampling lets this intentionally coarse simulation steer fine ink
        // without revealing the transport grid itself.
        float2 flux_uv=surface_flux_uv;
        float4 flux=surface_flux;
        float signed_flux=flux.r*2.0-1.0,flux_magnitude=flux.g;
        float flux_east=ui_texture.Sample(ui_sampler,flux_uv+float2(1.0/64.0,0)).r*2.0-1.0;
        float flux_north=ui_texture.Sample(ui_sampler,flux_uv+float2(0,1.0/32.0)).r*2.0-1.0;
        float inversion=saturate((abs(signed_flux-flux_east)+abs(signed_flux-flux_north))*2.2);
        magnetic_inversion=inversion;
        float magnetic_core=smoothstep(.07,.34,flux_magnitude)*active_latitudes;
        float magnetic_fringe=smoothstep(.018,.10,flux_magnitude)*(1.0-smoothstep(.16,.38,flux_magnitude));
        spot_mask=max(spot_mask*.28,magnetic_core*spots);
        penumbra=max(penumbra*.24,magnetic_fringe*spots*(.5+.5*inversion));
        facula=max(facula*.3,(magnetic_fringe*.62+inversion*.25)*pow(1.0-z,1.45)*activity);
    }
    float filament=pow(abs(sin(differential*9.0+latitude*13.0+convection*4.0)),18.0)*activity;
    // A quadratic visible-light limb law gives each atmosphere a materially
    // different edge without drawing a UI-like outline. Coefficients are
    // restrained broadband approximations: cool extended atmospheres darken
    // more strongly, while hot radiative envelopes remain comparatively flat.
    float limb_u1=kind<.5?.47:kind<1.5?.64:kind<2.5?.29:.52;
    float limb_u2=kind<.5?.22:kind<1.5?.16:kind<2.5?.12:.24;
    float limb_mu=1.0-saturate(z);
    float limb=saturate(1.0-limb_u1*limb_mu-limb_u2*limb_mu*limb_mu);
    float material=.38+cells*.26+convection*.18-cell_edge*.08;
    if(kind>.5&&kind<1.5) material=.40+cells*.23+convection*.14-cell_edge*.035;
    else if(kind>=1.5&&kind<2.5) {material=.56+convection*.045;spot_mask*=.18;}
    else if(kind>=2.5&&kind<3.5) {material=.78+convection*.018;spot_mask*=.04;facula*=.12;}
    float tone=saturate(material*limb-spot_mask*.34+facula*.09+filament*.08);
    // Longitude/latitude is useful around the stellar belts but singular at
    // either pole: every stroke otherwise converges into a false engraved
    // pinch. Blend to an azimuthal-equidistant cap chart before reaching the
    // singularity. The cap remains rotationally continuous and has finite,
    // nearly uniform mark spacing at its center.
    float2 belt_chart=float2(longitude,latitude)*radius*115.0;
    float cap_radius=1.57079633-abs(latitude);
    float2 cap_direction=length(surface.xz)>.0001?normalize(surface.xz):float2(1.0,0.0);
    float2 cap_chart=cap_direction*cap_radius*radius*115.0;
    if(latitude<0.0) cap_chart.y=-cap_chart.y;
    float cap_blend=smoothstep(.76,1.12,abs(latitude));
    // Translate continuous convection into discrete plate values. A seeded
    // micro-dither breaks the band edges without reintroducing a grey wash;
    // radiative and degenerate photospheres remain smoother by design.
    float plate_dither=planet_fbm(surface*47.0+float3(13.0,5.0,19.0),seed+2591.0)*.5+.5;
    float plate_steps=kind<.5?8.0:kind<1.5?5.0:0.0;
    float engraved_tone=plate_steps>0.0?saturate((floor(tone*plate_steps+plate_dither*.24)+.22)/plate_steps):tone;
    float plate_mix=kind<.5?.32:kind<1.5?.18:0.0;
    float ground_tone=lerp(tone,engraved_tone,plate_mix);
    float detail_island=smoothstep(.22,.72,planet_fbm(surface*2.7+float3(17.0,5.0,9.0),seed+1877.0)*.5+.5);
    // Share one coherent pressure field across all eight plate passes. The
    // former per-layer FBM repeated an expensive multi-octave evaluation up to
    // eight times for every photospheric pixel. Phase-shifted low-cost waves
    // still give each pass independent broken territories without paying for
    // another turbulent volume.
    float plate_phase=longitude*2.37+latitude*3.11+convection*4.7+meso_convection*2.3+seed*.013;
    // Eight quantized values do not require eight simultaneously evaluated
    // stroke families. Five nested main-sequence passes retain all eight ground
    // transitions while removing three costly line/erosion evaluations.
    int class_layer_limit=kind>.5&&kind<1.5?3:kind>=1.5&&kind<2.5?4:kind>=2.5?1:5;
    float class_spacing=kind>.5&&kind<1.5?1.48:kind>=1.5&&kind<2.5?1.22:kind>=2.5?1.7:1.0;
    float flow_bearing=.31*sin(latitude*2.7+convection*2.1)+.17*sin(longitude*1.9-seed*.007);
    float coverage=0.0,sum=0.0;
    [unroll] for(int layer=0;layer<8;++layer) {
        // Eight deliberately uneven value steps, like successive passes over
        // a plate. The passes stay nearly parallel to the local plasma flow;
        // value comes from offset broken cuts and pressure, not crossed families
        // that would resolve into a cartographic mesh on the bright disk.
        float threshold=layer==0?.055:layer==1?.13:layer==2?.215:layer==3?.315:
                        layer==4?.43:layer==5?.56:layer==6?.70:.835;
        float family_angle=layer%3==0?-.14:layer%3==1?-.015:.105;
        float angle=family_angle+flow_bearing;
        if(layer<class_layer_limit&&engraved_tone>=threshold) {
            float spacing=(2.68+layer*.19)*class_spacing;
            float nib=lerp(.16,.082,(float)layer/7.0);
            float belt_lane,belt_along;
            float belt_line=planet_engraved_line(belt_chart,angle,spacing,nib,convection*.7,(float)layer,seed+1801.0,belt_lane,belt_along);
            belt_line*=hatch_stroke_erosion(belt_lane,belt_along,(float)layer,.15+layer*.034);
            float line=belt_line;
            if(cap_blend>0.0) {
                float cap_lane,cap_along;
                float cap_line=planet_engraved_line(cap_chart,angle,spacing,nib,convection*.7,(float)layer,seed+1801.0,cap_lane,cap_along);
                cap_line*=hatch_stroke_erosion(cap_lane,cap_along,(float)layer,.15+layer*.034);
                // Cross-fade complete marks rather than interpolating chart
                // coordinates. This avoids shearing either projection into a
                // false collar around the pole.
                line=lerp(belt_line,cap_line,cap_blend);
            }
            float layer_wave=.5+.5*sin(plate_phase+layer*2.399+sin(longitude*(1.3+layer*.07)-latitude*2.1));
            float layer_island=saturate(detail_island*.68+layer_wave*.32);
            float local_plate_pressure=lerp(.28,.88,detail_island);
            if(layer>2) local_plate_pressure*=smoothstep(.42+.025*layer,.79,layer_island+cell_edge*.12);
            // Leave truly overexposed material as open bone-white ground.
            // Without this reserve the brightest band becomes the busiest.
            float white_reserve=1.0-smoothstep(.86,.985,engraved_tone);
            line*=smoothstep(threshold,threshold+.085,engraved_tone)*local_plate_pressure*white_reserve;
            coverage=max(coverage,line);sum+=line;
        }
    }
    float hatch=saturate(coverage*.58+max(sum-coverage,0.0)*.085);
    // The plate cannot carry an equally dense screen over an incandescent
    // photosphere. Reserve irregular central fields where exposure burns
    // through the ink, while retaining cuts around magnetic and convective
    // structure. This prevents the uniformly textured, reflected-light read
    // of an engraved moon.
    float exposure_field=planet_fbm(surface*1.85+float3(29.0,7.0,13.0),seed+2633.0)*.5+.5;
    float hot_reserve=smoothstep(.57,.90,z)*smoothstep(.44,.76,ground_tone*.76+exposure_field*.24);
    hatch*=1.0-hot_reserve*.63;
    if(kind>.5&&kind<1.5) hatch*=.48;
    if(kind>=2.5) hatch*=.08;
    else if(kind>=1.5) hatch*=.58;
    float magnetic_stipple=(spot_mask*.25+penumbra*.13+magnetic_inversion*.09)*smoothstep(.08,.62,activity);
    float stipple_density=saturate(.012+magnetic_stipple+cell_edge*.028);
    float stipple=planet_micro_stipple(belt_chart,seed+1901.0,stipple_density);
    if(cap_blend>0.0) stipple=lerp(stipple,planet_micro_stipple(cap_chart,seed+1901.0,stipple_density),cap_blend);
    float contour_grain=smoothstep(.16,.68,volume_noise(float3(cos(angle)*7.0,sin(angle)*7.0,seed*.013),seed+2297.0));
    float contour_break=smoothstep(.28,.61,volume_noise(float3(cos(angle)*13.0,sin(angle)*13.0,seed*.017),seed+2333.0));
    float contour=(1.0-smoothstep(.004,.019,abs(distance-radius)))*(.025+.11*contour_grain)*contour_break;
    if(kind>=2.5&&kind<3.5) contour*=.16;
    // A star emits across its whole disk. Preserve dark engraved cuts and
    // spots, but give the photosphere a luminous ground instead of treating it
    // like a planet lit from outside.
    float center_emission=pow(z,.62);
    float luminous_ground=(.16+.58*pow(ground_tone,.76))*lerp(.64,1.12,center_emission);
    luminous_ground+=hot_reserve*(.09+.15*exposure_field);
    luminous_ground*=1.0-spot_mask*.62-penumbra*.12;
    float ink=saturate(luminous_ground+hatch*(.28+.43*engraved_tone)+stipple*.24+contour+facula*.075-penumbra*.055);
    float exposure=smoothstep(.48,.94,ink)*(.25+.24*center_emission+.18*facula);
    float3 photosphere=lerp(tint,float3(1.0),exposure);
    float class_radiance=kind<.5?2.05:kind<1.5?1.62:kind<2.5?2.58:3.15;
    // Emit genuine HDR energy rather than a display-range painted disk. Bright
    // photospheric ground drives bloom and tends toward white after tone map;
    // magnetic cuts receive less gain and retain their engraved structure.
    float exposure_shape=.74+.48*pow(ground_tone,2.2);
    float emitted_radiance=ink*(1.0+facula*1.05+pow(ground_tone,8.0)*.62)*class_radiance*exposure_shape;
    return float4(photosphere*emitted_radiance,input.color.a);
}
float graph_sample(int index) {
    if(index<4)return push.hatch_shape[index];if(index<8)return push.hatch_tone[index-4];
    if(index<12)return push.hatch_offset[index-8];return push.hatch_levels[index-12];
}
float graph_segment_distance(float2 p,float2 a,float2 b){float2 ab=b-a;float t=saturate(dot(p-a,ab)/max(dot(ab,ab),.00001));return length(p-(a+ab*t));}
float4 procedural_graph(VertexOutput input) {
    int kind=clamp((int)round(push.texture_hatch.y),0,5),count=clamp((int)round(push.texture_hatch.z),1,16);
    float value_min=graph_sample(0),value_max=value_min;
    [unroll]for(int i=1;i<16;++i)if(i<count){float v=graph_sample(i);value_min=min(value_min,v);value_max=max(value_max,v);}
    if(push.hatch_angles.y>push.hatch_angles.x){value_min=push.hatch_angles.x;value_max=push.hatch_angles.y;}
    float range=max(value_max-value_min,.00001),baseline=saturate((push.hatch_angles.z-value_min)/range);
    float packed=max(push.hatch_angles.w,0.0);int grid_count=(int)floor(packed+.0001);float fill_alpha=frac(packed);if(kind==2&&fill_alpha<.01)fill_alpha=.22;
    float2 dimensions=1.0/max(fwidth(input.uv),float2(.00001));float2 p=float2(input.uv.x*dimensions.x,(1.0-input.uv.y)*dimensions.y);
    float half_width=max(push.texture_hatch.w,.5)*.5,coverage=0.0,fill=0.0;
    if(kind!=0&&grid_count>0)[unroll]for(int grid=0;grid<8;++grid)if(grid<grid_count){float y=dimensions.y*(grid+1.0)/(grid_count+1.0);coverage=max(coverage,(1.0-smoothstep(.35,1.1,abs(p.y-y)))*.18);}
    if(kind==3){
        float slot=dimensions.x/count;int index=clamp((int)floor(input.uv.x*count),0,count-1);float value=saturate((graph_sample(index)-value_min)/range);float center=(index+.5)*slot;
        float low=min(value,baseline)*dimensions.y,high=max(value,baseline)*dimensions.y,inset=max(slot*.18,1.0);
        coverage=max(coverage,(1.0-smoothstep(slot*.5-inset,slot*.5-inset+.8,abs(p.x-center)))*smoothstep(low-1.0,low,p.y)*(1.0-smoothstep(high,high+1.0,p.y)));
    }else{
        if(count==1){float y=saturate((graph_sample(0)-value_min)/range)*dimensions.y;coverage=max(coverage,1.0-smoothstep(half_width+1.0,half_width+2.0,length(p-float2(dimensions.x*.5,y))));}
        [unroll]for(int i=0;i<15;++i)if(i<count-1){float x0=(float)i/max((float)(count-1),1.0),x1=(float)(i+1)/max((float)(count-1),1.0);float y0=saturate((graph_sample(i)-value_min)/range),y1=saturate((graph_sample(i+1)-value_min)/range);float2 a=float2(x0*dimensions.x,y0*dimensions.y),b=float2(x1*dimensions.x,y1*dimensions.y);
            if(kind==4){float2 corner=float2(b.x,a.y);coverage=max(coverage,1.0-smoothstep(half_width,half_width+1.0,min(graph_segment_distance(p,a,corner),graph_segment_distance(p,corner,b))));}else coverage=max(coverage,1.0-smoothstep(half_width,half_width+1.0,graph_segment_distance(p,a,b)));
            if(kind==2&&input.uv.x>=x0&&input.uv.x<=x1){float t=saturate((input.uv.x-x0)/max(x1-x0,.00001));fill=max(fill,input.uv.y>=1.0-lerp(y0,y1,t)?fill_alpha:0.0);}
        }
        if(kind==5)[unroll]for(int i=0;i<16;++i)if(i<count){float x=(i/max((float)(count-1),1.0))*dimensions.x,y=saturate((graph_sample(i)-value_min)/range)*dimensions.y;float stem=(1.0-smoothstep(half_width,half_width+1.0,abs(p.x-x)))*step(min(baseline*dimensions.y,y),p.y)*step(p.y,max(baseline*dimensions.y,y));float dot=1.0-smoothstep(half_width*2.0+1.0,half_width*2.0+2.0,length(p-float2(x,y)));coverage=max(coverage,max(stem*.72,dot));}
    }
    return float4(srgb_to_linear(input.color.rgb),saturate(max(coverage,fill))*input.color.a);
}
float4 gaussian_surfel(VertexOutput input) {
    // Carrier vertices cover +/-3 standard deviations along both projected
    // covariance axes. Alpha compositing integrates overlapping surfels.
    float2 q = (input.uv - .5) * 6.0;
    float coverage = exp(-.5 * dot(q, q));
    if (coverage < 1.0 / 255.0) discard;
    return float4(srgb_to_linear(input.color.rgb), input.color.a * coverage);
}
[shader("fragment")] float4 fragment_main(VertexOutput input) : SV_Target {
    if (push.texture_hatch.x < -4.5) return gaussian_surfel(input);
    if (push.texture_hatch.x < -3.5) return procedural_graph(input);
    if (push.texture_hatch.x < -2.5) return procedural_star(input);
    if (push.texture_hatch.x < -1.5) return procedural_planet(input);
    if (push.texture_hatch.x < -.5) return sdf_volume(input);
    float4 sampled = push.texture_hatch.x > .5 ? ui_texture.Sample(ui_sampler, input.uv) : float4(1);
    // Source atlases provide form and alpha; presentation code owns the rare
    // semantic color. This keeps ships, markings, and icons in the same ink
    // language even when a legacy source contains baked paint colors.
    float ink = dot(sampled.rgb, float3(.2126, .7152, .0722));
    sampled.rgb = float3(ink, ink, ink);
    if (push.texture_hatch.y > .5) {
        float tone = saturate((ink - .5) * push.hatch_tone.x + .5 + push.hatch_tone.y);
        float darkness = push.texture_hatch.w > .5 ? tone : 1.0 - tone;
        // SV_Position is in framebuffer pixels, while UI geometry, spacing,
        // and offsets are authored in logical pixels. Evaluate the pattern in
        // that same logical space so Retina scaling does not double density or
        // make an object-anchored hatch slide as it pans.
        float2 pixel = input.position.xy * push.viewport.xy / push.viewport.zw + push.hatch_offset.xy;
        float coverage = 0.0;
        float accumulated_coverage = 0.0;
        int layer_count = clamp((int)round(push.hatch_tone.w), 1, 4);
        bool antialiased = push.texture_hatch.z > .5;
        [unroll] for (int layer = 0; layer < 4; ++layer) {
            if (layer < layer_count && darkness >= push.hatch_levels[layer]) {
                float angle = push.hatch_angles[layer] + push.hatch_tone.z;
                // Slightly incommensurate spacing keeps crossed layers from
                // locking into a repeated diamond lattice. Ratios are fixed,
                // so depth still maps cleanly to the number of active cuts.
                float spacing_scale = layer == 0 ? 1.0 : layer == 1 ? .92 : layer == 2 ? 1.08 : .86;
                float layer_spacing = max(push.hatch_shape.x * spacing_scale, 1.0);
                float stroke_lane, stroke_along;
                float line_coverage = hatch_line(pixel, angle,
                    layer_spacing, max(push.hatch_shape.y, .01),
                    max(push.hatch_shape.z, .01), saturate(push.hatch_offset.w), antialiased,
                    stroke_lane, stroke_along);
                line_coverage *= hatch_stroke_erosion(stroke_lane, stroke_along,
                    (float)layer, saturate(push.hatch_offset.w));
                coverage = max(coverage, line_coverage);
                accumulated_coverage += line_coverage;
            }
        }
        if (push.texture_hatch.x <= .5 && push.texture_hatch.w > .5) {
            // Procedural silhouettes have no paper texture to preserve. Emit
            // light engraved strokes into transparency. Preserve the strongest
            // stroke and add restrained pressure from subsequent layers; a raw
            // sum makes every crossover twice as bright and exposes a diamond
            // lattice before the viewer reads the engraved form.
            // Average secondary pressure across the remaining active layers.
            // Without normalization, three- and four-way crossings clamp into
            // white knots, making Deep/Open marks look filled rather than more
            // densely engraved. Layer count should change cut density, not the
            // peak value of coincident strokes.
            float secondary_layers = max((float)(layer_count - 1), 1.0);
            float secondary_coverage = max(accumulated_coverage - coverage, 0.0)
                                     / secondary_layers;
            float hatch_coverage = saturate((coverage * .72 + secondary_coverage * .28)
                * saturate(push.hatch_shape.w));
            float edge_softness = saturate(push.hatch_offset.z);
            if (edge_softness > 0) {
                float local_radius = length((input.uv - .5) * 2.0);
                // An evenly radial fade makes a damaged membrane end in a soft
                // vector halo. Abrade the terminal band with two long material-
                // aligned frequencies instead. `pixel` already includes the
                // object's hatch offset, so the chipped edge remains attached
                // while panning; authored rotation keeps the wear from becoming
                // another screen-space texture. The deliberately small amplitude
                // vanishes on contacts but resolves across large cropped shells.
                float2 edge_axis = float2(cos(push.hatch_tone.z), sin(push.hatch_tone.z));
                float2 edge_tangent = float2(-edge_axis.y, edge_axis.x);
                float edge_along = dot(pixel, edge_tangent);
                float edge_across = dot(pixel, edge_axis);
                float edge_wear = sin(edge_along * .071 + edge_across * .019) * .62
                                + sin(edge_along * .137 - edge_across * .043) * .38;
                float worn_radius = local_radius + edge_wear * edge_softness
                                  * saturate(push.hatch_offset.w) * .08;
                hatch_coverage *= 1.0 - smoothstep(1.0 - edge_softness, 1.0, worn_radius);
            }
            sampled = float4(1, 1, 1, hatch_coverage);
        } else {
            float hatch_coverage = coverage * saturate(push.hatch_shape.w);
            sampled.rgb = lerp(float3(1), float3(0), hatch_coverage);
        }
    }
    return float4(srgb_to_linear(input.color.rgb), input.color.a) * sampled;
}
float3 bloom_source(float2 uv) {
    float3 c=ui_texture.Sample(ui_sampler,uv).rgb;
    float brightest=max(c.r,max(c.g,c.b)),darkest=min(c.r,min(c.g,c.b));
    float saturation=(brightest-darkest)/max(brightest,.001);
    // Only the scarce semantic inks excite the simulated phosphor. Neutral
    // paper, text, rules, and monochrome illustrations remain clean and do not
    // acquire the soft photographic bloom used by the colored status marks.
    float chroma_mask=smoothstep(.08,.24,saturation)*smoothstep(.06,.32,brightest);
    return c*chroma_mask;
}
float3 tube_bloom_source(float2 uv) {
    float3 c=ui_texture.Sample(ui_sampler,uv).rgb;
    float luminance=dot(c,float3(.2126,.7152,.0722));
    // A CRT beam broadens around high current, including neutral white. Keep
    // this above mid-tones so ordinary text stems stay crisp.
    return c*smoothstep(.58,.94,luminance);
}
[shader("fragment")] float4 post_fragment(VertexOutput input) : SV_Target {
    float2 texel=1.0/push.viewport.zw;
    float2 glass_uv=input.uv;
    float2 uv=glass_uv;
    float trinitron=step(.5,push.texture_hatch.x);
    if(trinitron>.5){
        // A restrained curved face: enough edge compression to read as glass,
        // but not enough to bend the archival UI out of alignment.
        float2 p=uv*2.0-1.0;
        // Classic Trinitron glass is principally cylindrical: curved across
        // the horizontal axis rather than inflated equally in both axes. Keep
        // both horizontal edges fixed and never scale Y: T mode must preserve
        // the source framebuffer's exact aspect ratio and bounds.
        float horizontal_curve=p.x*p.x;
        p.x*= (1.0+.052*horizontal_curve)/1.052;
        uv=p*.5+.5;
        if(any(uv<0.0)||any(uv>1.0)) return float4(0,0,0,1);
        if(push.hatch_shape.y<.5){
            // A well-adjusted monitor is stable, but the deflection and mains
            // cadence are not mathematically motionless. Keep displacement
            // well below one physical pixel and brightness variation below 1%.
            uv.x+=sin(push.hatch_shape.x*6.2831853*1.7+uv.y*5.0)*texel.x*.16;
        }
    }
    float3 scene=ui_texture.Sample(ui_sampler,uv).rgb;
    float3 bloom=bloom_source(uv)*.05;
    // A tight phosphor fringe and a much weaker broad tail suggest a CRT
    // without softening the underlying one-pixel marks or introducing scanline
    // shading. The slight horizontal bias follows the display's raster axis.
    float2 near_x=texel*float2(3.0,0.0),near_y=texel*float2(0.0,2.0);
    float2 far_x=texel*float2(16.0,0.0),far_y=texel*float2(0.0,10.0);
    bloom+=(bloom_source(uv+near_x)+bloom_source(uv-near_x))*.055;
    bloom+=(bloom_source(uv+near_y)+bloom_source(uv-near_y))*.04;
    bloom+=(bloom_source(uv+far_x)+bloom_source(uv-far_x))*.014;
    bloom+=(bloom_source(uv+far_y)+bloom_source(uv-far_y))*.01;
    float3 hdr=scene+bloom*.72;
    if(trinitron>.5){
        float2 beam_x=texel*float2(2.0,0.0);
        float2 beam_y=texel*float2(0.0,1.5);
        float3 tube_glow=tube_bloom_source(uv)*.025;
        tube_glow+=(tube_bloom_source(uv+beam_x)+tube_bloom_source(uv-beam_x))*.022;
        tube_glow+=(tube_bloom_source(uv+beam_y)+tube_bloom_source(uv-beam_y))*.014;
        hdr+=tube_glow;
    }
    float3 mapped=saturate((hdr*(2.51*hdr+.03))/(hdr*(2.43*hdr+.59)+.14));
    if(trinitron>.5){
        // Quantize the grille and raster in physical framebuffer space. They
        // are parts of the tube and must not swim with the curved source UV.
        float2 pixel=glass_uv*push.viewport.zw;
        // Sony aperture-grille tubes use uninterrupted vertical phosphor
        // stripes. Keep the mask subtle so one-pixel type and etched marks
        // remain legible, then add a lighter horizontal raster modulation.
        // The aperture grille exposes continuous vertical RGB phosphor stripes.
        // Each triad averages to neutral at viewing distance; unlike chromatic
        // aberration, this color structure stays registered to the glass.
        float phase=fmod(floor(pixel.x),3.0);
        // One output pixel cannot resolve a phosphor stripe and its optical
        // spread independently. These lanes represent the integrated footprint
        // of continuous R/G/B stripes, not opaque colored LCD columns.
        float3 grille=phase<1.0?float3(1.0,.72,.72):(phase<2.0?float3(.72,1.0,.72):float3(.72,.72,1.0));
        // Tie raster pitch to logical source lines so HiDPI output does not
        // accidentally turn a 720-line image into a coarse 360-line mask.
        float line_pitch=max(push.viewport.w/max(push.viewport.y,1.0),1.0);
        float beam=abs(frac(pixel.y/line_pitch)-.5)*2.0;
        float scan=.82+.18*smoothstep(.10,.70,beam);
        float2 edge=abs(glass_uv*2.0-1.0);
        float vignette=1.0-.28*smoothstep(.48,1.02,max(edge.x,edge.y));
        // Across a complete RGB stripe period every channel averages to one.
        // This preserves neutral whites at viewing distance while retaining
        // the vertically continuous aperture-grille structure in a 1:1 crop.
        mapped*=grille*1.2295082*scan*vignette;
        // Tensioned aperture grilles need horizontal stabilizing wires. A
        // 20-inch-class monitor commonly reveals two faint lines near thirds.
        float wire_distance=min(abs(glass_uv.y-1.0/3.0),abs(glass_uv.y-2.0/3.0))*push.viewport.w;
        float damper_wire=1.0-.16*(1.0-smoothstep(.35,1.25,wire_distance));
        mapped*=damper_wire;
        // The phosphor field ends inside a rounded glass face rather than at a
        // perfect modern-panel rectangle. Preserve only a very low reflected
        // black floor within that face.
        float2 face=max(abs(glass_uv*2.0-1.0)-float2(.94,.94),0.0);
        float face_mask=1.0-smoothstep(.068,.088,length(face));
        mapped=(mapped+bloom*.16+.0025)*face_mask;
        if(push.hatch_shape.y<.5){
            mapped*=.994+.006*sin(push.hatch_shape.x*6.2831853*59.94);
        }
    }
    return float4(mapped,1);
}
