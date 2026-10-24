shader_type spatial;
render_mode blend_mix, cull_disabled;
uniform float clock = 0.0;
uniform float strength = 0.0;
uniform float pulse = 0.0;
uniform float span = 12.0;
uniform float length_scale = 18.0;
varying vec3 cloud_pos;
float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f*f*(3.0-2.0*f);
	float n = dot(i,vec3(1.0,57.0,113.0));
	vec4 a = fract(sin(vec4(n,n+1.0,n+57.0,n+58.0))*43758.5453);
	vec4 b = fract(sin(vec4(n+113.0,n+114.0,n+170.0,n+171.0))*43758.5453);
	return mix(mix(mix(a.x,a.y,f.x),mix(a.z,a.w,f.x),f.y),mix(mix(b.x,b.y,f.x),mix(b.z,b.w,f.x),f.y),f.z);
}
// Nested low-density layers approximate vapor thickness without a hard cone wall.
varying float layer;
void vertex() {
 layer = UV2.x;
 float angle = UV.y * 6.283185;
 float swirl = sin(angle*5.0 + UV.x*9.0 - clock*2.2 + layer*3.0);
 float radius = span * (0.10+0.90*UV.x) * (0.68+layer*0.32);
 radius *= 1.0 + swirl*0.065*UV.x;
 VERTEX = vec3(cos(angle)*radius,sin(angle)*radius*0.74,(UV.x-0.43)*length_scale + layer*length_scale*0.10);
 NORMAL = normalize(vec3(cos(angle),sin(angle)/0.74,-span/length_scale));
 cloud_pos = VERTEX;
}
void fragment() {
 vec3 p = cloud_pos / max(span,0.01);
 // Noise advects aft: larger soft billows with fine turbulent wisps.
 vec3 flow = vec3(p.xy*3.2,p.z*2.0-clock*1.3+layer*2.7);
 float large = noise3(flow);
 float fine = noise3(flow*2.7+vec3(large*0.8,layer*4.0,-clock*0.4));
 float density = large*0.72+fine*0.28;
 float front = smoothstep(0.04,0.32,UV.x);
 float rear = 1.0-smoothstep(0.40+large*0.18,0.94,UV.x);
 float mist = smoothstep(0.18,0.85,density);
 float shock = exp(-pow((UV.x-0.50-(large-0.5)*0.13)/0.15,2.0));
 // Suppress grazing-angle highlights that made the old surface look like plastic.
 float grazing = abs(dot(normalize(NORMAL),normalize(VIEW)));
 float softness = smoothstep(0.0,0.35,grazing);
 float camera_fade = smoothstep(1.0,3.0,length(VERTEX));
 ALBEDO = mix(vec3(0.69,0.76,0.81),vec3(0.91,0.95,0.97),density);
 EMISSION = vec3(0.008,0.010,0.012);
 ROUGHNESS = 1.0;
 ALPHA = front*rear*mist*(strength*0.082+shock*pulse*0.15)*softness*camera_fade;
}
