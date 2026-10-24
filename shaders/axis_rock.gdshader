shader_type spatial;
render_mode cull_back;
varying vec3 rock_pos;
float hash(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
float noise(vec3 p){vec3 i=floor(p);vec3 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);}
void vertex(){rock_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float strata=noise(rock_pos*0.025+vec3(0.0,noise(rock_pos*0.007)*3.0,0.0));
 float broad=noise(rock_pos*0.009);
 float fine=noise(rock_pos*0.12);
 float veins=smoothstep(0.28,0.72,strata);
 vec3 base=mix(vec3(0.018,0.022,0.016),vec3(0.095,0.11,0.060),broad);
 ALBEDO=base*mix(0.63,1.08,veins)*mix(0.82,1.12,fine);
 ROUGHNESS=0.98;
 NORMAL_MAP=normalize(vec3((noise(rock_pos*0.08+vec3(3,0,0))-0.5)*0.30,(fine-0.5)*0.30,1.0))*0.5+0.5;
 NORMAL_MAP_DEPTH=0.45;
}
