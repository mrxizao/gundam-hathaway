shader_type spatial;
render_mode cull_back;
uniform int building_quality=2;
uniform float bay_m=12.0;
instance uniform float lod_fade:instance_index(0)=1.0;
instance uniform float lod_side:instance_index(1)=0.0;
varying vec3 world_p;
varying vec3 local_p;
float hash2(vec2 p){uvec2 c=uvec2(ivec2(p));uint h=c.x*1597334677u^c.y*3812015801u;h=(h^(h>>16u))*2246822519u;h=(h^(h>>13u))*3266489917u;return float((h^(h>>16u))&16777215u)/16777215.0;}
float noise2(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*f*(f*(f*6.-15.)+10.);return mix(mix(hash2(i),hash2(i+vec2(1,0)),f.x),mix(hash2(i+vec2(0,1)),hash2(i+vec2(1)),f.x),f.y);}
uniform sampler2D role_0_albedo:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D role_0_normal:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D role_0_orm:filter_linear_mipmap_anisotropic,repeat_enable;
uniform vec3 gain_0=vec3(1);
uniform sampler2D role_1_albedo:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D role_1_normal:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D role_1_orm:filter_linear_mipmap_anisotropic,repeat_enable;
uniform vec3 gain_1=vec3(1);
uniform sampler2D role_2_albedo:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D role_2_normal:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D role_2_orm:filter_linear_mipmap_anisotropic,repeat_enable;
uniform vec3 gain_2=vec3(1);
uniform sampler2D role_5_albedo:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D role_5_normal:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D role_5_orm:filter_linear_mipmap_anisotropic,repeat_enable;
uniform vec3 gain_5=vec3(1);
uniform sampler2D role_6_albedo:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D role_6_normal:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D role_6_orm:filter_linear_mipmap_anisotropic,repeat_enable;
uniform vec3 gain_6=vec3(1);
void vertex(){world_p=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;local_p=VERTEX;}
void fragment(){
 if(lod_fade<.9999 || lod_side>.5){float rank=hash2(floor(FRAGCOORD.xy));if((lod_side<.5 && rank>=lod_fade)||(lod_side>.5 && rank<lod_fade)){discard;}}
 int role=int(floor(COLOR.a*8.0+.5));float dist=length(VERTEX);
 float macro=noise2(world_p.xz/130.0+local_p.yy/190.0);
 vec3 base=COLOR.rgb;vec3 col=base*(.95+.10*macro);float rough=.88,metal=0.0,ao=1.0;
 float near_w=1.0-smoothstep(100.0,950.0,dist);
 if(role!=3 && role!=4 && near_w>.001){
  vec3 tex=vec3(1),orm=vec3(1,.88,0),sample_n=vec3(.5,.5,1);float normal_w=1.0-smoothstep(65.0,building_quality==2?350.0:160.0,dist);
  if(role==0){vec2 uv=UV/3.0;vec2 dx=dFdx(uv),dy=dFdy(uv);tex=textureGrad(role_0_albedo,uv,dx,dy).rgb*gain_0;if(building_quality>0){orm=textureGrad(role_0_orm,uv,dx,dy).rgb;if(normal_w>.001){sample_n=textureGrad(role_0_normal,uv,dx,dy).rgb;}}}
else if(role==1){vec2 uv=UV/3.0;vec2 dx=dFdx(uv),dy=dFdy(uv);tex=textureGrad(role_1_albedo,uv,dx,dy).rgb*gain_1;if(building_quality>0){orm=textureGrad(role_1_orm,uv,dx,dy).rgb;if(normal_w>.001){sample_n=textureGrad(role_1_normal,uv,dx,dy).rgb;}}}
else if(role==2){vec2 uv=UV/2.0;vec2 dx=dFdx(uv),dy=dFdy(uv);tex=textureGrad(role_2_albedo,uv,dx,dy).rgb*gain_2;if(building_quality>0){orm=textureGrad(role_2_orm,uv,dx,dy).rgb;if(normal_w>.001){sample_n=textureGrad(role_2_normal,uv,dx,dy).rgb;}}}
else if(role==5){vec2 uv=UV/4.0;vec2 dx=dFdx(uv),dy=dFdy(uv);tex=textureGrad(role_5_albedo,uv,dx,dy).rgb*gain_5;if(building_quality>0){orm=textureGrad(role_5_orm,uv,dx,dy).rgb;if(normal_w>.001){sample_n=textureGrad(role_5_normal,uv,dx,dy).rgb;}}}
else if(role==6){vec2 uv=UV/2.0;vec2 dx=dFdx(uv),dy=dFdy(uv);tex=textureGrad(role_6_albedo,uv,dx,dy).rgb*gain_6;if(building_quality>0){orm=textureGrad(role_6_orm,uv,dx,dy).rgb;if(normal_w>.001){sample_n=textureGrad(role_6_normal,uv,dx,dy).rgb;}}}
  tex=mix(vec3(1),clamp(tex,vec3(.70),vec3(1.30)),role==1?.85:.35);
  col=mix(col,tex*base,near_w);
  if(building_quality>0){rough=mix(rough,clamp(orm.g,.38,.98),near_w);ao=mix(1.0,orm.r,near_w*.40);metal=role==2?.32:role==6?orm.b*.65*near_w:0.0;
   if(normal_w>.001){vec2 xy=sample_n.rg*2.0-1.0;NORMAL_MAP=vec3(xy,sqrt(max(.0001,1.0-dot(xy,xy))))*.5+.5;NORMAL_MAP_DEPTH=normal_w*.35;}
  }
 }
 col*=1.0-(1.0-smoothstep(1.0,18.0,local_p.y))*.14;
 if(role==4){vec2 grid=UV/vec2(bay_m,6.4);vec2 fw=max(fwidth(grid),vec2(.0001));vec2 edge=min(fract(grid),1.0-fract(grid));vec2 frame=1.0-smoothstep(vec2(.025)-fw,vec2(.025)+fw,edge);float visible=(1.0-smoothstep(.12,.55,max(fw.x,fw.y)))*(1.0-smoothstep(1500.0,9000.0,dist));float pane=hash2(floor(grid));col*=mix(.93,.70+.40*pane,visible);col=mix(col,vec3(.035,.048,.054),max(frame.x,frame.y)*.70*visible);rough=.28+.08*pane*visible;metal=.16;}
 else if(role>=5){col*=.96+.06*macro;vec2 seam_uv=UV/vec2(role==5?4.0:2.0,12.0);vec2 aa=max(fwidth(seam_uv),vec2(.001));float seam=1.0-smoothstep(.012,.012+max(aa.x,aa.y),min(fract(seam_uv.y),1.0-fract(seam_uv.y)));col*=1.0-seam*.08*(1.0-smoothstep(.08,.30,max(aa.x,aa.y)));}
 ALBEDO=clamp(col,vec3(.001),vec3(.8));ROUGHNESS=rough;METALLIC=metal;AO=ao;SPECULAR=role==4?.55:.24;
}
