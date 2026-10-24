shader_type spatial;
render_mode cull_back;
uniform int surface_role=0;
uniform vec4 base_color:source_color=vec4(0.52,0.55,0.55,1);
uniform vec3 color_gain=vec3(1);
uniform int building_quality=2;
uniform float tile_m=3.0;
uniform float floor_m=6.4;
uniform vec3 trim_means[8];
uniform float bay_m=12.0;
uniform sampler2D surface_albedo:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D surface_normal:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D surface_orm:filter_linear_mipmap_anisotropic,repeat_enable;
instance uniform float lod_fade:instance_index(0)=1.0;
instance uniform float lod_side:instance_index(1)=0.0;
varying vec3 local_p;
varying vec3 world_p;
float hash2(vec2 p){uvec2 c=uvec2(ivec2(p));uint h=c.x*1597334677u^c.y*3812015801u;h=(h^(h>>16u))*2246822519u;h=(h^(h>>13u))*3266489917u;return float((h^(h>>16u))&16777215u)/16777215.0;}
float noise2(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*f*(f*(f*6.-15.)+10.);return mix(mix(hash2(i),hash2(i+vec2(1,0)),f.x),mix(hash2(i+vec2(0,1)),hash2(i+vec2(1)),f.x),f.y);}
void vertex(){local_p=VERTEX;world_p=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;}
void fragment(){
 // Complementary opaque masks: old and new LOD never cover the same pixel.
 if(lod_fade<0.9999 || lod_side>0.5){float rank=hash2(floor(FRAGCOORD.xy));if((lod_side<0.5 && rank>=lod_fade)||(lod_side>0.5 && rank<lod_fade)){discard;}}
 float dist=length(VERTEX);
 float near_w=1.0-smoothstep(100.0,950.0,dist);
 vec2 uv=UV/max(tile_m,0.01),dx=dFdx(uv),dy=dFdy(uv);
 float macro=noise2(world_p.xz/130.0+local_p.yy/190.0);
 vec3 col=base_color.rgb*(0.95+0.10*macro);
 if(surface_role==3){col=base_color.rgb*trim_means[int(floor(COLOR.r*7.0+0.5))]*(0.95+0.10*macro);}
 float rough=0.88,metal=0.0,ao=1.0;
 float grain=0.0;
 if((surface_role<4 || surface_role>=5) && near_w>0.001){
  if(surface_role==3){
   float row=floor(COLOR.r*7.0+0.5);
   uv=vec2(UV.x/8.0,(row+0.08+UV2.y*0.84)/8.0);dx=dFdx(uv);dy=dFdy(uv);
  }
  vec3 tex=textureGrad(surface_albedo,uv,dx,dy).rgb*color_gain;
  if(surface_role<3 || surface_role>=5){tex=mix(vec3(1),clamp(tex,vec3(0.70),vec3(1.30)),surface_role==1?0.85:0.35);}
  col=mix(col,tex*base_color.rgb,near_w);
  if(building_quality>0){
   vec3 orm=textureGrad(surface_orm,uv,dx,dy).rgb;
   rough=mix(rough,clamp(orm.g,0.38,0.98),near_w);ao=mix(1.0,orm.r,near_w*0.40);
   metal=surface_role==2?0.32:surface_role==3?orm.b*near_w:surface_role==6?orm.b*0.65*near_w:0.0;
   float normal_w=1.0-smoothstep(65.0,building_quality==2?350.0:160.0,dist);
   if(normal_w>0.001){vec2 xy=textureGrad(surface_normal,uv,dx,dy).rg*2.0-1.0;vec3 n=vec3(xy,sqrt(max(0.0001,1.0-dot(xy,xy))));NORMAL_MAP=n*0.5+0.5;NORMAL_MAP_DEPTH=normal_w*0.35;}
  }
 }
 float dirt=(1.0-smoothstep(1.0,18.0,local_p.y))*0.14;
 col*=1.0-dirt;
 if(surface_role==4){
  vec2 grid=UV/vec2(bay_m,floor_m);
  vec2 fw=max(fwidth(grid),vec2(0.0001));
  vec2 edge=min(fract(grid),1.0-fract(grid));
  vec2 frame=1.0-smoothstep(vec2(0.025)-fw,vec2(0.025)+fw,edge);
  float visible=(1.0-smoothstep(0.12,0.55,max(fw.x,fw.y)))*(1.0-smoothstep(1500.0,9000.0,dist));
  float pane=hash2(floor(grid));
  col*=mix(0.93,0.70+0.40*pane,visible);
  col=mix(col,vec3(0.035,0.048,0.054),max(frame.x,frame.y)*0.70*visible);
  rough=0.28+0.08*pane*visible;metal=0.16;
 }else if(surface_role>=5){
  col*=0.96+0.06*macro;
  vec2 seam_uv=UV/vec2(surface_role==5?4.0:2.0,12.0);
  vec2 seam_aa=max(fwidth(seam_uv),vec2(0.001));
  float seam=1.0-smoothstep(0.012,0.012+max(seam_aa.x,seam_aa.y),min(fract(seam_uv.y),1.0-fract(seam_uv.y)));
  col*=1.0-seam*0.08*(1.0-smoothstep(0.08,0.30,max(seam_aa.x,seam_aa.y)));
 }
 ALBEDO=clamp(col,vec3(0.001),vec3(0.80));ROUGHNESS=rough;METALLIC=metal;AO=ao;SPECULAR=surface_role==4?0.55:0.24;
}
