shader_type spatial;
render_mode blend_mix, depth_draw_never, depth_test_disabled, cull_front, unshaded, shadows_disabled, fog_disabled;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.85);
uniform vec3 shade_color : source_color = vec3(0.72, 0.78, 0.88);
uniform float softness = 0.35;
uniform vec3 sun_dir = vec3(0.35, 0.62, 0.70);
uniform vec3 light_color : source_color = vec3(1.0,0.90,0.78);
uniform float sun_shade = 1.0;
uniform float surface_detail = 1.0;
uniform int cloud_quality = 2;
uniform vec3 air_color : source_color = vec3(0.52,0.61,0.68);
uniform float air_density = 0.00001;
// Offline hash lattice, linear data (not sRGB). Original analytic fallback is retained.
uniform sampler3D noise_lut_a : filter_nearest, repeat_disable;
uniform sampler3D noise_lut_b : filter_nearest, repeat_disable;
uniform bool use_noise_lut = false;
varying vec3 local_point;
varying flat vec3 centre;
varying flat vec3 extent;
varying flat vec3 camera_local;
varying flat vec3 seed;
float hash_cloud(vec3 p) {
 p=fract(p*vec3(0.1031,0.1030,0.0973));
 p+=dot(p,p.yxz+33.33);
 return fract((p.x+p.y)*p.z);
}
float noise3(vec3 p) {
 vec3 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
 // Domain of both octaves lies within [-16,175]. Cache each corner expression.
 if(use_noise_lut){
  vec4 a=texelFetch(noise_lut_a,ivec3(i)+ivec3(16),0);
  vec4 b=texelFetch(noise_lut_b,ivec3(i)+ivec3(16),0);
  return mix(mix(mix(a.r,a.g,f.x),mix(a.b,a.a,f.x),f.y),mix(mix(b.r,b.g,f.x),mix(b.b,b.a,f.x),f.y),f.z);
 }
 return mix(mix(mix(hash_cloud(i),hash_cloud(i+vec3(1,0,0)),f.x),mix(hash_cloud(i+vec3(0,1,0)),hash_cloud(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash_cloud(i+vec3(0,0,1)),hash_cloud(i+vec3(1,0,1)),f.x),mix(hash_cloud(i+vec3(0,1,1)),hash_cloud(i+vec3(1,1,1)),f.x),f.y),f.z);
}
float body(vec3 p,float detail_weight) {
 if(surface_detail<0.5){return 1.0-smoothstep(0.54,0.96,length(p));}
 float broad=noise3(p*3.2+seed);
 float detail=broad;
 if(detail_weight>0.001){detail=mix(broad,noise3(p*8.5+seed*1.7),detail_weight);}
 float edge=length(p)+(0.5-broad)*0.36;
 float envelope=1.0-smoothstep(0.45,0.99,edge);
 return envelope*(1.0-smoothstep(0.88,1.0,length(p)))*smoothstep(0.10,0.80,broad*0.82+detail*0.18);
}
float direct_light(vec3 p,vec3 light_dir,float cover){
 float b=dot(p,light_dir);
 float path=max(0.0,-b+sqrt(max(0.0,b*b+1.0-dot(p,p))));
 return exp(-path*(0.75+cover*0.85)*2.2*clamp(sun_shade,0.0,1.0));
}
void vertex() {
 local_point=VERTEX;
 centre=MODEL_MATRIX[3].xyz;
 extent=max(vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz)),vec3(0.001));
 camera_local=(INV_VIEW_MATRIX[3].xyz-centre)/extent;
 seed=mod(centre*0.0071,vec3(97.0));
}
void fragment() {
 vec3 ray=normalize(local_point-camera_local);
 float b=dot(camera_local,ray);
 float discriminant=b*b-dot(camera_local,camera_local)+0.25;
 if(discriminant<=0.0){discard;}
 float root=sqrt(discriminant);
 float start=max(0.0,-b-root),end=-b+root;
 float depth=textureLod(scene_depth,SCREEN_UV,0.0).r;
 #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
 bool has_geometry=depth<0.999999;
 float clip_depth=depth*2.0-1.0;
#else
 bool has_geometry=depth>0.000001;
 float clip_depth=depth;
#endif
 if(has_geometry){
  vec4 view_point=INV_PROJECTION_MATRIX*vec4(SCREEN_UV*2.0-1.0,clip_depth,1.0);
  vec3 world_point=(INV_VIEW_MATRIX*vec4(view_point.xyz/view_point.w,1.0)).xyz;
  vec3 scene_local=(world_point-centre)/extent;
  end=min(end,dot(scene_local-camera_local,ray));
 }
 if(end<=start){discard;}
 float step_size=(end-start)/8.0;
 float transmittance=1.0;
 vec3 radiance=vec3(0.0);
 vec3 light_dir=normalize(sun_dir/extent);
 vec3 first=(camera_local+ray*start)*2.0;
 vec3 last=(camera_local+ray*end)*2.0;
 // Two coarse lighting samples; keep the existing eight integration steps.
 float shadow_start=noise3((first+light_dir*0.35)*3.2+seed);
 float shadow_end=noise3((last+light_dir*0.35)*3.2+seed);
 float detail_weight=smoothstep(0.35,0.85,length(camera_local)*2.0)*(1.0-smoothstep(3.0,7.0,length(camera_local)));
 float light_start=direct_light(first,light_dir,shadow_start);
 float light_middle=direct_light((first+last)*0.5,light_dir,(shadow_start+shadow_end)*0.5);
 float light_end=direct_light(last,light_dir,shadow_end);
 float optical_scale=4.4*clamp(length(ray*extent)/2200.0,0.85,1.25);
 float forward_phase=pow(max(dot(normalize(ray*extent),normalize(sun_dir)),0.0),8.0);
 vec3 lit=tint.rgb*mix(vec3(1.0),light_color,0.22);
 for(int i=0;i<8;i++){
  if(transmittance<0.035){break;}
  float fraction=(float(i)+0.5)/8.0;
  vec3 p=(camera_local+ray*(start+(float(i)+0.5)*step_size))*2.0;
  float density=body(p,detail_weight);
  if(density<0.0001){continue;}
  float absorb=1.0-exp(-density*step_size*optical_scale);
  float direct=mix(mix(light_start,light_middle,clamp(fraction*2.0,0.0,1.0)),mix(light_middle,light_end,clamp(fraction*2.0-1.0,0.0,1.0)),step(0.5,fraction));
  float upper=smoothstep(-0.8,0.9,p.y);
  float illumination=clamp(0.05+direct*0.85+upper*0.05,0.0,1.0);
  vec3 sample_color=mix(shade_color*0.38,lit,illumination);
  sample_color+=lit*forward_phase*direct*(1.0-exp(-density*1.5))*0.18;
  radiance+=transmittance*absorb*sample_color;
  transmittance*=1.0-absorb;
 }
 float alpha=1.0-transmittance;
 vec3 color=radiance/max(alpha,0.001);
 float air=clamp(1.0-exp(-max(start,0.0)*length(ray*extent)*max(air_density,0.0)),0.0,0.30);
 ALBEDO=mix(color,air_color,air);
 ALPHA=alpha*tint.a;
 ROUGHNESS=1.0;SPECULAR=0.0;
}
