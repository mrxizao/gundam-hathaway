shader_type spatial;
render_mode cull_disabled;

uniform vec4 base_color : source_color=vec4(0.4,0.47,0.29,1.0);
uniform int material_kind=0;
uniform int surface_family=1;
uniform bool trial_enabled=true;
uniform int surface_detail=1;
uniform int ground_quality=2;
uniform float tile_m=2.0;
uniform sampler2D surface_albedo : source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D surface_normal : hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D surface_orm : filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D dry_albedo : source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D dry_normal : hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D dry_orm : filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D soil_albedo : source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D soil_normal : hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D soil_orm : filter_linear_mipmap_anisotropic,repeat_enable;
// R/G: nearest hard-surface/parcel distance in 0..512 m; B: damp riverbank; A: airport.
uniform sampler2D ground_mask : filter_linear_mipmap,repeat_disable;
uniform vec4 mask_bounds=vec4(-65000.0,-65000.0,145000.0,130000.0);
uniform vec3 green_gain=vec3(1.0);
uniform vec3 dry_gain=vec3(1.0);
uniform vec3 soil_gain=vec3(1.0);
uniform vec3 green_mean=vec3(0.12,0.145,0.065);
uniform vec3 dry_mean=vec3(0.19,0.165,0.095);
uniform vec3 soil_mean=vec3(0.105,0.078,0.052);
varying vec3 ground_position;
varying vec3 ground_normal;

float lattice_hash(vec2 p){
 uvec2 cell=uvec2(ivec2(p));
 uint h=cell.x*1597334677u ^ cell.y*3812015801u;
 h=(h^(h>>16u))*2246822519u;
 h=(h^(h>>13u))*3266489917u;
 return float((h^(h>>16u))&16777215u)/16777215.0;
}
float ground_noise(vec2 p){
 vec2 i=floor(p),f=fract(p);
 f=f*f*f*(f*(f*6.0-15.0)+10.0);
 return mix(mix(lattice_hash(i),lattice_hash(i+vec2(1,0)),f.x),mix(lattice_hash(i+vec2(0,1)),lattice_hash(i+vec2(1,1)),f.x),f.y);
}
void vertex(){
 ground_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 ground_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment(){
 vec2 p=ground_position.xz;
 float distance_m=length(VERTEX);
 mat2 turn=mat2(vec2(0.8,0.6),vec2(-0.6,0.8));
 vec2 macro=turn*p/650.0;
 vec2 warp=vec2(ground_noise(macro*0.43+vec2(13.7,5.2)),ground_noise(macro*0.43+vec2(-9.4,24.6)))-0.5;
 float drought=0.65*ground_noise(macro+warp*0.9)+0.35*ground_noise(macro*2.71+vec2(17.3,-9.2));
 vec2 mid_uv=turn*p/24.0;
 float mid_footprint=max(length(dFdx(mid_uv)),length(dFdy(mid_uv)));
 float mid_visibility=(1.0-smoothstep(0.15,0.8,mid_footprint))*(1.0-smoothstep(600.0,3200.0,distance_m));
 float clumps=ground_noise(mid_uv+warp*2.0);

 vec2 mask_uv=(p-mask_bounds.xy)/mask_bounds.zw;
 float inside=step(0.0,mask_uv.x)*step(mask_uv.x,1.0)*step(0.0,mask_uv.y)*step(mask_uv.y,1.0);
 vec4 zones=mix(vec4(1,1,0,0),texture(ground_mask,clamp(mask_uv,vec2(0),vec2(1))),inside);
 float road_distance=zones.r*512.0;
 float parcel_distance=zones.g*512.0;
 float river=zones.b;
 float airport=zones.a;
 float festival_park=1.0-smoothstep(6500.0,10000.0,length(p-vec2(5400,-30600)));
 float park_ring=length(p/vec2(46800,50400));
 float park=max(festival_park,smoothstep(0.80,0.87,park_ring)*(1.0-smoothstep(1.01,1.07,park_ring)));

 float dry_weight=clamp(0.26+0.46*drought-0.19*park-0.12*airport-0.33*river+(clumps-0.5)*0.32*mid_visibility*(1.0-0.7*airport),0.04,0.76);
 float road_edge=1.0-smoothstep(12.0,80.0,road_distance);
 float wall_edge=1.0-smoothstep(8.0,65.0,parcel_distance);
 float disturbed=max(road_edge,wall_edge*0.60);
 float erosion=0.81+0.38*(ground_noise(turn*p/16.0+warp)-0.5)*mid_visibility;
 float soil_weight=clamp(disturbed*erosion*0.78+river*0.13*mix(0.5,clumps,mid_visibility),0.0,0.84);
 vec3 weights=vec3((1.0-dry_weight)*(1.0-soil_weight),dry_weight*(1.0-soil_weight),soil_weight);
 float variation=(0.94+0.12*drought)*(1.0-0.10*river);
 vec3 far_color=(green_mean*weights.x+dry_mean*weights.y+soil_mean*weights.z)*variation;

 vec3 up=normalize(ground_normal);
 if(up.y<0.0){up=-up;}
 NORMAL=normalize(mat3(VIEW_MATRIX)*up);
 ALBEDO=far_color;
 ROUGHNESS=0.94;
 SPECULAR=0.17;
 METALLIC=0.0;
 float near_visibility=1.0-smoothstep(180.0,1800.0,distance_m);
 vec2 uv=p/max(tile_m,0.01);
 vec2 dx=dFdx(uv),dy=dFdy(uv);
 mat2 detail_turn=mat2(vec2(0.6,0.8),vec2(-0.8,0.6));
 vec2 uv2=detail_turn*uv*0.71+vec2(0.27,0.41);
 vec2 dx2=detail_turn*dx*0.71,dy2=detail_turn*dy*0.71;
 if(trial_enabled && near_visibility>0.001){
  vec3 green=textureGrad(surface_albedo,uv,dx,dy).rgb*green_gain;
  vec3 soil=textureGrad(soil_albedo,uv,dx,dy).rgb*soil_gain;
  vec3 dry=green*(dry_mean/max(green_mean,vec3(0.01)));
  if(ground_quality>0){dry=textureGrad(dry_albedo,uv,dx,dy).rgb*dry_gain;}
  if(ground_quality>1){
   float anti_repeat=(1.0-smoothstep(120.0,450.0,distance_m))*0.32;
   if(anti_repeat>0.001){
   green=mix(green,textureGrad(surface_albedo,uv2,dx2,dy2).rgb*green_gain,anti_repeat);
   dry=mix(dry,textureGrad(dry_albedo,uv2,dx2,dy2).rgb*dry_gain,anti_repeat);
   soil=mix(soil,textureGrad(soil_albedo,uv2,dx2,dy2).rgb*soil_gain,anti_repeat);
   }
  }
  ALBEDO=mix(far_color,(green*weights.x+dry*weights.y+soil*weights.z)*variation,near_visibility);
  float response=(1.0-smoothstep(100.0,400.0,distance_m))*near_visibility;
  if(surface_detail>0 && ground_quality>0 && response>0.001){
   vec3 orm=textureGrad(surface_orm,uv,dx,dy).rgb*weights.x+textureGrad(dry_orm,uv,dx,dy).rgb*weights.y+textureGrad(soil_orm,uv,dx,dy).rgb*weights.z;
   ROUGHNESS=mix(0.94,clamp(orm.g,0.84,0.99),response);
   AO=mix(1.0,orm.r,response*0.22);
   float normal_visibility=(1.0-smoothstep(35.0,ground_quality>1?240.0:130.0,distance_m))*response;
   // Explicit gradients remain valid at distance/quality branches and triangle edges.
   if(normal_visibility>0.001){
    vec2 bump=(textureGrad(surface_normal,uv,dx,dy).rg*2.0-1.0)*weights.x+(textureGrad(dry_normal,uv,dx,dy).rg*2.0-1.0)*weights.y+(textureGrad(soil_normal,uv,dx,dy).rg*2.0-1.0)*weights.z;
    bump*=normal_visibility*(0.38-0.12*airport);
    vec3 tangent=normalize(vec3(1,0,0)-up*up.x);
    vec3 bitangent=normalize(cross(tangent,up));
    vec3 perturbed=normalize(tangent*bump.x+bitangent*bump.y+up*sqrt(max(0.0001,1.0-dot(bump,bump))));
    NORMAL=normalize(mat3(VIEW_MATRIX)*perturbed);
   }
  }
 }
 if(!trial_enabled){ALBEDO=base_color.rgb*(0.94+0.10*drought);}
}
