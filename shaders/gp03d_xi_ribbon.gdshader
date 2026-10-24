shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, skip_vertex_transform;
uniform sampler2D path_points : filter_nearest, repeat_disable;
uniform sampler2D path_meta : filter_nearest, repeat_disable;
uniform sampler2D edge_mask : filter_linear, repeat_disable;
uniform int segments_per_missile=511;
uniform float simulation_time=0.0;
uniform float half_width=6.0;
uniform float base_alpha=.308;
uniform float hold_seconds=1.5;
uniform float fade_seconds=1.6;
uniform float fade_near=3.0;
uniform float fade_full=60.0;
varying float opacity;
varying vec3 world_point;
void vertex(){
 int missile=INSTANCE_ID/segments_per_missile;
 int segment=INSTANCE_ID%segments_per_missile;
 float count=texelFetch(path_meta,ivec2(missile,0),0).r;
 vec4 p0=texelFetch(path_points,ivec2(segment,missile),0);
 vec4 p1=texelFetch(path_points,ivec2(segment+1,missile),0);
 bool inactive=float(segment+1)>=count || simulation_time-p1.w>hold_seconds+fade_seconds || distance(p0.xyz,p1.xyz)<.01;
 if(inactive){VERTEX=vec3(0,0,-1);opacity=0.0;world_point=vec3(0);}
 else {
 vec3 difference=p1.xyz-p0.xyz;
 float along=UV.y;
 float factor=.15+.85*(float(segment)+along)/max(count-1.0,1.0);
 vec3 center=mix(p0.xyz,p1.xyz,along);
 vec3 to_camera=INV_VIEW_MATRIX[3].xyz-center;
 vec3 side=cross(difference,to_camera);
 if(dot(side,side)<.0001)side=cross(difference,vec3(0,1,0));
 if(dot(side,side)<.0001)side=vec3(1,0,0);
 world_point=center+normalize(side)*(UV.x*2.0-1.0)*half_width*(.55+.45*factor);
 VERTEX=(VIEW_MATRIX*vec4(world_point,1.0)).xyz;
 float age=max(simulation_time-mix(p0.w,p1.w,along),0.0);
 opacity=base_alpha*factor*(1.0-smoothstep(hold_seconds,hold_seconds+fade_seconds,age));
 }
}
void fragment(){
 ALBEDO=vec3(.80,.80,.84);
 float distance_to_camera=length(world_point-INV_VIEW_MATRIX[3].xyz);
 ALPHA=opacity*texture(edge_mask,vec2(UV.x,.5)).a*smoothstep(fade_near,fade_full,distance_to_camera);
}
