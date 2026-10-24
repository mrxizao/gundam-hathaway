shader_type spatial;
render_mode cull_disabled;
uniform vec4 base_color : source_color = vec4(0.2,0.23,0.25,1.0);
uniform float metalness = 0.25;
varying vec3 map_position;
float hash31(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float noise3(vec3 p) {
 vec3 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash31(i),hash31(i+vec3(1,0,0)),f.x),mix(hash31(i+vec3(0,1,0)),hash31(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash31(i+vec3(0,0,1)),hash31(i+vec3(1,0,1)),f.x),mix(hash31(i+vec3(0,1,1)),hash31(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex(){ map_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
 float broad=noise3(map_position*0.045);
 float grain=noise3(map_position*1.8);
 ALBEDO=base_color.rgb*mix(0.32,1.12,broad)*mix(0.82,1.08,grain);
 METALLIC=metalness;
 ROUGHNESS=mix(0.72,0.97,grain);
}
