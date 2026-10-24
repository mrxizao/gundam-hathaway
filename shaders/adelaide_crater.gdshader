shader_type spatial;
render_mode cull_disabled;
uniform vec4 base_color : source_color = vec4(0.28,0.25,0.20,1.0);
varying vec3 world_pos;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 p=world_pos.xz;
 float coarse=noise(p*0.023);
 float clods=noise(p*0.12);
 float grains=noise(p*1.7);
 float near_detail=1.0-smoothstep(300.0,2200.0,length(VERTEX));
 float soot=smoothstep(0.3,0.68,noise(p*0.009+noise(p*0.04)));
 vec3 earth=base_color.rgb*(0.66+coarse*0.55+clods*0.20);
 earth=mix(earth,earth*vec3(0.46,0.46,0.44),soot*0.44);
 float gravel=smoothstep(0.76,0.9,grains)*near_detail;
 earth=mix(earth,vec3(0.40,0.37,0.31),gravel*0.45);
 ALBEDO=earth*(1.0+(grains-0.5)*0.19*near_detail);
 ROUGHNESS=0.98;
 SPECULAR=0.12;
 // Small shading perturbation reads as granular soil without extra geometry.
 NORMAL=normalize(NORMAL+vec3((grains-0.5)*0.065,(clods-0.5)*0.065,0.0)*near_detail);
}
