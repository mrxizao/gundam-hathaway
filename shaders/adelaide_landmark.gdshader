shader_type spatial;
render_mode cull_back;
uniform int detail_quality=2;
uniform int theme=0;
uniform sampler2D wear_masks:filter_linear_mipmap,repeat_disable;
uniform sampler2D concrete_diff:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D concrete_normal:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D concrete_orm:filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D metal_diff:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D metal_normal:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D metal_orm:filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D roof_diff:source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D roof_normal:hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D roof_orm:filter_linear_mipmap_anisotropic,repeat_enable;
varying vec3 local_p;
float h2(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
vec3 wear(vec2 p,float tile){
 vec2 cell=vec2(mod(tile,4.0),floor(tile/4.0));
 // Inset avoids neighbouring atlas cells in mipmaps; fade fine details before unresolved levels.
 vec2 q=fract(p)*0.90+0.05;
 return textureGrad(wear_masks,(cell+q)/vec2(4,3),dFdx(p)*0.90/vec2(4,3),dFdy(p)*0.90/vec2(4,3)).rgb;
}
void vertex(){local_p=VERTEX;}
void fragment(){
 int role=int(round(COLOR.r*8.0));float pattern=round(COLOR.g*12.0);
 float dist=length(VERTEX);float near_w=1.0-smoothstep(250.,2200.,dist);
 float normal_w=detail_quality==0?0.0:1.0-smoothstep(80.,detail_quality==2?650.:260.,dist);
 vec2 uv=UV/3.0;vec2 dx=dFdx(uv),dy=dFdy(uv);
 vec3 base=vec3(.245,.270,.268);float rough=.87,metal=0.,ao=1.;vec3 normal_tex=vec3(.5,.5,1.);
 if(role==1 || role==5 || role==8){
  base=role==8?vec3(.46,.31,.075):role==5?vec3(.18,.12,.08):vec3(.12,.17,.19);
  vec3 tex=textureGrad(metal_diff,uv,dx,dy).rgb/vec3(.21615,.22966,.23924);
  base*=mix(vec3(1),clamp(tex,vec3(.7),vec3(1.3)),near_w*.48);
  vec3 orm=textureGrad(metal_orm,uv,dx,dy).rgb;rough=mix(.70,clamp(orm.g,.48,.90),near_w);metal=.35;ao=mix(1.,orm.r,near_w*.30);
  if(normal_w>.001)normal_tex=textureGrad(metal_normal,uv,dx,dy).rgb;
 }else if(role==6){
  base=vec3(.070,.084,.093);vec2 ru=UV/4.;
  base*=mix(vec3(1),clamp(textureGrad(roof_diff,ru,dFdx(ru),dFdy(ru)).rgb/vec3(.04326,.03733,.03538),vec3(.72),vec3(1.28)),near_w*.55);
  vec3 orm=textureGrad(roof_orm,ru,dFdx(ru),dFdy(ru)).rgb;rough=mix(.91,clamp(orm.g,.65,.98),near_w);ao=mix(1.,orm.r,near_w*.3);
  if(normal_w>.001)normal_tex=textureGrad(roof_normal,ru,dFdx(ru),dFdy(ru)).rgb;
 }else if(role!=2){
  base=role==3?(theme==0?vec3(.040,.050,.055):vec3(.055,.050,.044)):role==4?vec3(.30,.27,.22):role==7?vec3(.095,.11,.11):theme==1?vec3(.33,.34,.31):vec3(.245,.270,.268);
  vec3 sample_a=textureGrad(concrete_diff,uv,dx,dy).rgb/vec3(.63371,.49810,.35719);
  vec2 secondary=uv*.731+vec2(.319,.713);
  vec3 sample_b=textureGrad(concrete_diff,secondary,dx*.731,dy*.731).rgb/vec3(.63371,.49810,.35719);
  // Neutral, low-contrast aggregate; the broad photographic stains must not form wallpaper.
  float aggregate=dot(mix(sample_a,sample_b,.5),vec3(.2126,.7152,.0722));
  base*=mix(1.,clamp(aggregate,.8,1.2),near_w*(role==4?.35:.16));
  vec3 orm=textureGrad(concrete_orm,uv,dx,dy).rgb;rough=mix(.9,clamp(orm.g,.65,.98),near_w);ao=mix(1.,orm.r,near_w*.10);
  if(normal_w>.001)normal_tex=textureGrad(concrete_normal,uv,dx,dy).rgb;
 }
 float dirt=0.0;
 if(detail_quality>0 && near_w>.001 && role!=2){
  vec2 cell_uv=UV/(role==0?vec2(137.,91.):vec2(36.,42.));
  vec3 deposit=wear(cell_uv,pattern);
  float detail_resolve=1.-smoothstep(.08,.28,max(length(dFdx(cell_uv)),length(dFdy(cell_uv))));
  dirt=deposit.r*near_w*detail_resolve*(role==4?.26:role==3?.25:.18);
  float base_dirt=(1.-smoothstep(0.,14.,local_p.y))*wear(UV/70.,1.).r*.12;
  dirt+=base_dirt;
  rough=clamp(rough+deposit.b*(pattern==6.0?-.20:.09)*near_w,.48,.99);
  if(pattern==10.0)base=mix(base,base*1.13,deposit.r*near_w*.35);
  if(pattern==8.0)base=mix(base,vec3(.20,.105,.045),deposit.r*near_w*.20);
 }
 base*=1.-dirt;
 if(role==2){
  vec2 grid=UV/vec2(14.,6.4);vec2 edge=min(fract(grid),1.-fract(grid));
  vec2 aa=max(fwidth(grid),vec2(.0001));float frame=max(1.-smoothstep(.012,.012+aa.x,edge.x),1.-smoothstep(.018,.018+aa.y,edge.y));
  float resolved=1.-smoothstep(.08,.40,max(aa.x,aa.y));
  float pane=h2(floor(grid));base=vec3(.055,.115,.15)*mix(1.,.7+.6*pane,resolved);
  base=mix(base,vec3(.08,.10,.105),frame*resolved);rough=.24+.10*pane;metal=.18;
 }
 EMISSION=role==8?vec3(1.,.80,.53)*1.6:vec3(0.);
 ALBEDO=clamp(base,vec3(.001),vec3(.65));ROUGHNESS=rough;METALLIC=metal;AO=ao;SPECULAR=role==2?.55:.25;
 if(normal_w>.001 && role!=2){vec2 xy=normal_tex.rg*2.-1.;NORMAL_MAP=vec3(xy,sqrt(max(.0001,1.-dot(xy,xy))))*.5+.5;NORMAL_MAP_DEPTH=normal_w*(role==0?.10:role==3||role==4?.18:.32);}
}
