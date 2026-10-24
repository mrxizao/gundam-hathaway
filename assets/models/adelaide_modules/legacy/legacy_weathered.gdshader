shader_type spatial;
render_mode cull_disabled;
uniform vec4 base_color : source_color = vec4(0.5,0.5,0.4,1.0);
uniform int material_kind = 0;
varying vec3 world_pos;
varying vec3 world_normal;
float hash(vec2 p) {return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p) {
 vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
 float broad=noise(world_pos.xz*0.00035);
 float upward=abs(world_normal.y);
 // Derivative-based band limiting prevents hash noise from becoming pixel blocks.
 vec2 detail_uv=world_pos.xz*0.035;
 float footprint=max(length(dFdx(detail_uv)),length(dFdy(detail_uv)));
 float band=1.0-smoothstep(0.15,0.65,footprint);
 float distance_fade=1.0-smoothstep(250.0,1800.0,length(VERTEX));
 float grit=noise(detail_uv);
 vec3 col=base_color.rgb*(0.94+0.10*broad+(grit-0.5)*0.06*band*distance_fade);
 float grime=noise(world_pos.xz*0.002+world_pos.yy*vec2(0.001,0.004));
 col*=mix(0.88+0.12*grime,1.0,upward);
 float vegetation=step(base_color.r*1.08,base_color.g);
 col=mix(col,mix(col,vec3(0.34,0.32,0.24),smoothstep(0.48,0.85,broad)*0.16),vegetation*upward);

 vec2 facade=mix(world_pos.zy,world_pos.xy,step(abs(world_normal.x),abs(world_normal.z)));
 float detail_visibility=(1.0-smoothstep(700.0,4500.0,length(VERTEX)));
 float pattern=1.0;
 if(material_kind==1){
  // Staggered masonry courses; analytic filtering keeps distant facades stable.
  vec2 uv=facade/vec2(12.0,6.0);
  uv.x+=mod(floor(uv.y),2.0)*0.5;
  vec2 edge=min(fract(uv),1.0-fract(uv));
  vec2 aa=max(fwidth(uv)*1.5,vec2(0.005));
  float mortar=1.0-smoothstep(0.025,0.025+max(aa.x,aa.y),min(edge.x,edge.y));
  float visible=1.0-smoothstep(0.15,0.45,max(aa.x,aa.y));
  pattern=1.0-mortar*0.11*visible*detail_visibility;
  col*=pattern;
  col*=0.96+noise(facade*0.008)*0.08;
 }else if(material_kind==2){
  // Muted glass reflection tint with a stable frame grid.
  col=mix(col,vec3(0.25,0.34,0.36),0.28);
 }else if(material_kind==3){
  vec2 uv=world_pos.xz/vec2(18.0,12.0);
  float edge=min(fract(uv.x),1.0-fract(uv.x));
  float aa=max(fwidth(uv.x),0.006);
  float seam=1.0-smoothstep(0.025,0.025+aa,edge);
  col*=1.0-seam*0.12*detail_visibility*(1.0-smoothstep(0.1,0.4,aa));
 }else if(material_kind==4){
  float weather=noise(world_pos.xz*0.0018);
  col*=0.93+weather*0.12;
  // Broad tyre/oil mottling stays low-frequency; aggregate is screen-space filtered.
  float aggregate=noise(world_pos.xz*0.09);
  float aa=max(length(dFdx(world_pos.xz*0.09)),length(dFdy(world_pos.xz*0.09)));
  col*=1.0+(aggregate-0.5)*0.065*detail_visibility*(1.0-smoothstep(0.15,0.5,aa));
 }else if(material_kind==7){
  vec2 uv=world_pos.xz/vec2(25.0,25.0);
  vec2 e=min(fract(uv),1.0-fract(uv));
  float aa=max(max(fwidth(uv).x,fwidth(uv).y),0.008);
  float seam=1.0-smoothstep(0.018,0.018+aa,min(e.x,e.y));
  col*=1.0-seam*0.09*detail_visibility*(1.0-smoothstep(0.1,0.5,aa));
 }else if(material_kind==8){
  col*=0.91+noise(world_pos.xz*0.014)*0.12;
 }else if(material_kind==6){
  col*=0.96+noise(world_pos.xz*0.02)*0.04*detail_visibility;
 }else if(material_kind==10){
  // Concrete slabs use metre-based joints, stable at grazing angles and distance.
  vec2 uv=world_pos.xz/24.0;
  vec2 edge=min(fract(uv),1.0-fract(uv));
  float aa=max(max(fwidth(uv).x,fwidth(uv).y),0.001);
  float joint=1.0-smoothstep(0.003,0.003+aa,min(edge.x,edge.y));
  float visible=1.0-smoothstep(0.08,0.32,aa);
  float slab=hash(floor(uv));
  col*=0.98+(slab-0.5)*0.10*visible;
  col*=1.0-joint*0.28*visible;
  float wear=noise(world_pos.xz*0.012);
  col*=0.93+0.10*wear;
 }else if(material_kind==11){
  // Industrial coated steel: vertical flutes, sheet seams and restrained foot grime.
  vec2 uv=facade/vec2(2.6,12.0);
  vec2 aa=max(fwidth(uv),vec2(0.002));
  float visible=1.0-smoothstep(0.10,0.40,max(aa.x,aa.y));
  float rib=0.5+0.5*cos(uv.x*6.2831853);
  col*=1.0+(rib-0.5)*0.16*visible;
  float edge=min(fract(uv.y),1.0-fract(uv.y));
  float seam=1.0-smoothstep(0.006,0.006+aa.y,edge);
  col*=1.0-seam*0.12*visible;
  col*=mix(0.78,1.0,smoothstep(26.0,40.0,world_pos.y));
 }else if(material_kind==5){
  col*=0.95+noise(facade*0.018)*0.1*detail_visibility;
 }

 ALBEDO=mix(col,vec3(dot(col,vec3(0.299,0.587,0.114))),0.13);
 ROUGHNESS=0.92;
 SPECULAR=0.18;
 if(material_kind==2){ROUGHNESS=0.28;SPECULAR=0.55;}
 if(material_kind==3){ROUGHNESS=0.66;METALLIC=0.12;SPECULAR=0.32;}
 if(material_kind==4){ROUGHNESS=0.94;SPECULAR=0.16;}
 if(material_kind==10){ROUGHNESS=0.85+0.10*grime;SPECULAR=0.23;}
 if(material_kind==11){ROUGHNESS=0.57+0.13*grime;METALLIC=0.20;SPECULAR=0.38;}
 if(material_kind==5){ROUGHNESS=0.58;METALLIC=0.25;}
 if(material_kind==9){EMISSION=base_color.rgb*0.65;ROUGHNESS=0.4;}
}
