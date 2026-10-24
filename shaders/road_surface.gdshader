shader_type spatial;
render_mode cull_disabled;
// All distances and road-frame coordinates are final world metres.
uniform vec4 base_color=vec4(0.04,0.045,0.05,1);
uniform vec3 color_gain=vec3(1);
uniform int road_role=0; // asphalt, concrete, patch, paint, drainage metal
uniform int road_quality=2;
uniform int surface_family=2;
uniform int material_kind=4;
uniform int surface_detail=1;
uniform bool explicit_frame=false;
uniform bool local_z_frame=false;
uniform bool curved_frame=false;
uniform bool trial_enabled=true;
uniform float tile_m=2.35;
uniform float junction_grid=0.0;
uniform bool adelaide_mask=false;
uniform float emission_energy=0.0;
uniform vec4 emission_color=vec4(0);
uniform sampler2D surface_albedo:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D surface_normal:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D surface_orm:filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D junction_mask:filter_linear_mipmap,repeat_disable;
varying vec3 world_p;
varying vec3 world_n;
varying vec2 road_uv;
varying float road_width;
varying vec3 road_axis;
varying float junction;
float hash2(vec2 p){
 uvec2 c=uvec2(ivec2(p));uint h=c.x*1597334677u^c.y*3812015801u;
 h=(h^(h>>16u))*2246822519u;h=(h^(h>>13u))*3266489917u;
 return float((h^(h>>16u))&16777215u)/16777215.0;
}
float noise2(vec2 p){
 vec2 i=floor(p),f=fract(p);f=f*f*f*(f*(f*6.0-15.0)+10.0);
 return mix(mix(hash2(i),hash2(i+vec2(1,0)),f.x),mix(hash2(i+vec2(0,1)),hash2(i+vec2(1)),f.x),f.y);
}
void vertex(){
 world_p=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;
 world_n=normalize(MODEL_NORMAL_MATRIX*NORMAL);
 vec3 ax=normalize(MODEL_MATRIX[0].xyz),az=normalize(MODEL_MATRIX[2].xyz);
 float sx=length(MODEL_MATRIX[0].xyz),sz=length(MODEL_MATRIX[2].xyz);
 road_axis=sz>=sx?az:ax;
 vec3 across=sz>=sx?ax:az;
 road_uv=vec2(dot(world_p,road_axis),dot(world_p-MODEL_MATRIX[3].xyz,across));
 road_width=min(sx,sz);
 junction=step(max(sx,sz)*0.995,min(sx,sz));
 if(local_z_frame){road_axis=az;road_width=sx;road_uv=vec2(dot(world_p,az),dot(world_p-MODEL_MATRIX[3].xyz,ax));}
 if(explicit_frame){
  road_uv=UV;road_width=UV2.x;junction=UV2.y;
  // UV2.y stores orientation: 0 along Z, 1 along X; 2 = junction/deck without tracks.
  road_axis=UV2.y<0.5?vec3(0,0,1):vec3(1,0,0);
  junction=step(1.5,UV2.y);
 }
 if(curved_frame){
  float radius=length(world_p.xz);road_uv=vec2(atan(world_p.z,world_p.x)*radius,radius);
  road_axis=normalize(vec3(-world_p.z,0,world_p.x));junction=1.0;
 }
}
void fragment(){
 vec2 p=world_p.xz;
 float dist=length(VERTEX);
 float macro=noise2(mat2(vec2(0.8,0.6),vec2(-0.6,0.8))*p/95.0);
 float near_w=(1.0-smoothstep(120.0,950.0,dist));
 vec2 texture_p=p;
 vec3 face=abs(world_n);
 if(face.x>0.7){texture_p=world_p.zy;}else if(face.z>0.7){texture_p=world_p.xy;}
 vec2 uv=texture_p/max(tile_m,0.01),dx=dFdx(uv),dy=dFdy(uv);
 vec3 up=normalize(world_n);
 if(abs(up.y)>0.5 && up.y<0.0){up=-up;}
 NORMAL=normalize(mat3(VIEW_MATRIX)*up);
 vec3 albedo=base_color.rgb*(0.90+0.20*macro);
 float rough=0.91;
 float ao=1.0;
 if(trial_enabled && near_w>0.001 && road_role<3){
  vec3 tex=textureGrad(surface_albedo,uv,dx,dy).rgb*color_gain;
  albedo=mix(albedo,tex*(0.94+0.12*macro),near_w);
  if(road_quality>0){
   vec3 orm=textureGrad(surface_orm,uv,dx,dy).rgb;
   rough=mix(0.91,clamp(orm.g,0.70,0.98),near_w);ao=mix(1.0,orm.r,near_w*0.4);
   float normal_w=(1.0-smoothstep(70.0,road_quality==2?300.0:140.0,dist));
   if(normal_w>0.001 && abs(up.y)>0.5){
    vec2 xy=textureGrad(surface_normal,uv,dx,dy).rg*2.0-1.0;
    vec3 n=vec3(xy,sqrt(max(0.0001,1.0-dot(xy,xy))));
    vec3 t=normalize(vec3(1,0,0)-up*up.x),b=normalize(cross(t,up));
    NORMAL=normalize(mat3(VIEW_MATRIX)*normalize(up*max(n.z,0.2)+t*n.x*normal_w*0.30+b*n.y*normal_w*0.30));
   }
  }
 }
 float filtered=1.0-smoothstep(0.25,1.4,max(length(dFdx(road_uv)),length(dFdy(road_uv))));
 float junction_w=junction;
 if(junction_grid>0.0){
  vec2 cell=abs(mod(p+junction_grid*0.5,junction_grid)-junction_grid*0.5);
  junction_w=max(junction_w,1.0-smoothstep(road_width*0.50,road_width*0.72,min(cell.x,cell.y)));
 }
 if(adelaide_mask){junction_w=max(junction_w,texture(junction_mask,(p-vec2(-65000))/vec2(145000,130000)).r);}
 if(road_role==0 && trial_enabled){
  float edge=smoothstep(road_width*0.35,road_width*0.49,abs(road_uv.y));
  float tracks=exp(-pow((abs(road_uv.y)-road_width*0.24)/max(1.6,road_width*0.018),2.0));
  tracks*=(0.5+0.5*noise2(vec2(road_uv.x/48.0,road_uv.y/7.0)))*(1.0-smoothstep(0.7,4.0,max(length(dFdx(road_uv)),length(dFdy(road_uv)))))*(1.0-smoothstep(600.0,2400.0,dist));
  albedo*=1.0-0.16*tracks*(1.0-junction_w)-0.10*edge;
  // Soft repairs follow road direction; their boundary is filtered in motion.
  vec2 patch_uv=road_uv/vec2(70,26);
  float repair=smoothstep(0.65,0.78,noise2(patch_uv))*0.13;
  albedo*=1.0-repair*(1.0-junction_w)*(1.0-smoothstep(800.0,3000.0,dist));
 }else if(road_role==1 && trial_enabled){
  vec2 joint_uv=texture_p/6.0;
  vec2 fw=max(fwidth(joint_uv),vec2(0.0001));
  vec2 edge=abs(fract(joint_uv+0.5)-0.5);
  vec2 lines=1.0-smoothstep(vec2(0.006)-fw,vec2(0.006)+fw,edge);
  albedo*=1.0-max(lines.x,lines.y)*0.13*filtered;
 }else if(road_role==3 && trial_enabled){
  // Faded paint, never alpha discard: thin distant markings remain stable.
  float scuff=noise2(p/2.3);
  albedo*=mix(0.86,0.72+0.28*smoothstep(0.20,0.80,scuff),filtered*near_w);
  rough=0.89;
 }else if(road_role==4 && trial_enabled){
  float f=max(fwidth(road_uv.x/1.0),0.001);
  float slots=1.0-smoothstep(0.15-f,0.15+f,abs(fract(road_uv.x)-0.5));
  albedo*=1.0-slots*0.65*filtered;rough=0.79;
 }
 if(!trial_enabled){albedo=base_color.rgb;rough=0.90;}
 ALBEDO=clamp(albedo,vec3(0.001),vec3(0.86));
 ROUGHNESS=rough;SPECULAR=0.20;METALLIC=road_role==4?0.35:0.0;AO=ao;
 EMISSION=emission_color.rgb*emission_energy;
}
