shader_type spatial;
render_mode blend_add,unshaded,depth_draw_never,cull_disabled,shadows_disabled;
uniform vec4 tint : source_color=vec4(0.5,0.75,1.0,1.0);
uniform float length_m=15.0;
uniform float exhaust_speed=80.0;
uniform float shocks=0.0;
instance uniform float brightness=1.0;
instance uniform float strength=0.0;
instance uniform vec3 bend=vec3(0.0);
instance uniform vec3 flow_curve=vec3(0.0);
varying float axial;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){
 axial=clamp(VERTEX.y/max(length_m,0.01)+0.5,0.0,1.0);
 float travel=TIME*exhaust_speed/max(length_m,0.01);
 float shear=sin(axial*34.0-travel*8.0+UV.x*6.2831853)*0.035*axial;
 VERTEX.xz*=1.0+shear;
 VERTEX+=flow_curve*(axial*axial);
}
void fragment(){
 float f=axial;
 float edge=pow(abs(dot(normalize(NORMAL),normalize(VIEW))),1.35);
 float travel=TIME*exhaust_speed/max(length_m,0.01);
 float stream=noise(vec2(UV.x*14.0,f*11.0-travel*2.0));
 float streak=noise(vec2(UV.x*27.0,f*5.0-travel*1.7));
 float detail=mix(0.56,1.08,stream)*mix(0.82,1.0,streak);
 float pulse=0.96+0.04*sin(TIME*43.0);
 float fade=pow(1.0-f,1.15)*smoothstep(0.0,0.045,f);
 // Compression cells stay near the nozzle; the shear texture travels downstream.
 float cells=pow(max(0.0,cos(f*38.0)),7.0);
 float diamond=cells*smoothstep(0.04,0.16,f)*(1.0-f);
 vec3 colored=tint.rgb*mix(vec3(1.0),vec3(0.85,0.92,1.0),f);
 vec3 hot=vec3(0.86,0.94,1.0);
 vec3 c=mix(colored,hot,pow(edge,3.0)*(0.20+0.25*exp(-f*3.0)));
 ALBEDO=c*(1.25+shocks*diamond*1.05)*brightness*pulse;
 ALPHA=clamp(strength*fade*edge*(detail+shocks*diamond*0.35)*0.72,0.0,0.82);
}
