shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float strength = 0.0;
uniform float clock = 0.0;
uniform bool trail = false;
// Continuous turbulence avoids precision-sensitive hash blocks on long quads.
float fbm(vec2 p){
 float a=sin(p.x*1.17+sin(p.y*.83));
 float b=sin(p.y*1.31+sin(p.x*.71));
 float c=sin(p.x*2.13+p.y*1.67+sin(p.y*2.41));
 return clamp(.5+.22*a+.18*b+.10*c,0.0,1.0);
}
void vertex(){if(trail) MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);}
void fragment(){
 float n=fbm(UV*vec2(12.0,12.0)+vec2(0,clock*3.0));
 float heat=0.0;
 if(trail){
  float bend=sin(UV.y*16.0-clock*3.0)*.018+sin(UV.y*31.0+clock)*.012;
  float width=mix(.025,.34,pow(UV.y,.8));
  float radial=abs(UV.x-.5+bend);
  float envelope=1.0-smoothstep(width*.35,width,radial);
  float flow=fbm(vec2(UV.x*12.0,UV.y*8.0+clock*4.0));
  heat=envelope*smoothstep(.02,.20,UV.y)*smoothstep(.0,.20,1.0-UV.y)*mix(.15,.7,flow);
 }else{
  vec2 p=(UV-vec2(.5,.5))*vec2(1.0,1.0);
  float r=length(p); float rim=.37+(n-.5)*.16;
  heat=(1.0-smoothstep(rim,rim+.055,r))*smoothstep(.16,.27,r);
 }
 float edge=smoothstep(0.0,.045,UV.x)*smoothstep(0.0,.045,1.0-UV.x)*smoothstep(0.0,.045,UV.y)*smoothstep(0.0,.045,1.0-UV.y);
 ALBEDO=mix(vec3(.85,.08,.005),vec3(1.0,.93,.68),smoothstep(.20,.85,heat));
 EMISSION=ALBEDO*(trail?1.25:2.2);
 ALPHA=clamp(heat*strength*edge,0.0,.90);
}
