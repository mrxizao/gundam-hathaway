shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled;
uniform float age = 0.0;
uniform float lifetime = 2.8;
uniform float strength = 1.0;
uniform float initial_radius = 12.0;
uniform float expansion = 42.0;
uniform float stretch = 1.0;
uniform float phase = 0.0;
uniform float directional = 0.0;
varying float crest;
varying float angle;
varying vec3 wave_pos;
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i,vec2(127.1,311.7))) * 43758.5453);
	float b = fract(sin(dot(i+vec2(1,0),vec2(127.1,311.7))) * 43758.5453);
	float c = fract(sin(dot(i+vec2(0,1),vec2(127.1,311.7))) * 43758.5453);
	float d = fract(sin(dot(i+vec2(1,1),vec2(127.1,311.7))) * 43758.5453);
	return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}
void vertex() {
	float t = clamp(age / lifetime, 0.0, 1.0);
	angle = UV.y * 6.283185;
	float irregular = 1.0 + 0.05 * sin(angle * 5.0 + phase) + 0.025 * sin(angle * 11.0 - phase);
	float radius = (initial_radius + expansion * age) * irregular;
	float radial = mix(0.72, 1.16, UV.x);
	VERTEX.x = cos(angle) * radius * radial;
	VERTEX.z = sin(angle) * radius * radial * stretch;
	crest = pow(max(sin(UV.x * 3.14159265), 0.0), 3.0);
	VERTEX.y = crest * (2.0 + 8.0 * strength) * pow(1.0 - t, 1.6);
	NORMAL = normalize(vec3(-cos(angle) * cos(UV.x * 3.14159) * 0.45, 1.0, -sin(angle) * cos(UV.x * 3.14159) * 0.45));
	wave_pos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
}
void fragment() {
	float t = clamp(age / lifetime, 0.0, 1.0);
	float broken = noise2(wave_pos.xz * 0.16 + vec2(phase)) * 0.7 + noise2(wave_pos.xz * 0.43) * 0.3;
	float foam = smoothstep(0.45, 0.92, crest) * smoothstep(0.28, 0.68, broken);
	float edge = smoothstep(0.0, 0.10, UV.x) * (1.0 - smoothstep(0.84, 1.0, UV.x));
	float fade = smoothstep(0.0, 0.012, age) * pow(1.0 - t, 1.3);
	ALBEDO = mix(vec3(0.09, 0.29, 0.36), vec3(0.78, 0.88, 0.91), foam);
	ROUGHNESS = mix(0.20, 0.85, foam);
	METALLIC = 0.0;
	EMISSION = ALBEDO * (0.06 + foam * 0.10);
	float arc = mix(1.0, 0.18 + 0.82 * smoothstep(-0.65, 0.1, -sin(angle)), directional);
	float gaps = 0.35 + 0.65 * smoothstep(-0.7, 0.2, sin(angle * 3.0 + phase));
	ALPHA = edge * fade * strength * (0.10 + 0.65 * foam) * arc * gaps;
}
