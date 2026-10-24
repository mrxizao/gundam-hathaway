shader_type spatial;
render_mode cull_disabled;
varying vec3 world_pos;
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float ripple=sin(world_pos.x*0.012+TIME*0.7)*sin(world_pos.z*0.017-TIME*0.5);
 ALBEDO=mix(vec3(0.045,0.16,0.17),vec3(0.09,0.24,0.25),ripple*0.12+0.5);
 ROUGHNESS=0.32; METALLIC=0.12; SPECULAR=0.48;
}
