shader_type spatial;
render_mode blend_mix, cull_disabled;
uniform float clock = 0.0;
uniform float lifetime = 3.6;
varying float life;
varying vec3 wp;
void vertex() {
	float age = max(clock - UV2.x, 0.0);
	life = clamp(1.0 - age / lifetime, 0.0, 1.0);
	vec2 lateral = vec2(cos(UV2.y),sin(UV2.y));
	float side = COLOR.r * 2.0 - 1.0;
	float spread = 13.0 + age * 42.0;
	float width = 7.0 + age * 12.0;
	VERTEX.xz += lateral * (side * spread + (UV.x * 2.0 - 1.0) * width);
	VERTEX.y += pow(max(sin(UV.x * 3.14159),0.0),2.0) * 3.5 * life * COLOR.g;
	wp = VERTEX;
}
void fragment() {
	float strands = 0.55 + 0.45 * sin(wp.x * 0.22 + sin(wp.z * 0.19) * 2.0);
	float fine = 0.65 + 0.35 * sin(wp.z * 0.71 + wp.x * 0.43);
	float edge = smoothstep(0.0,0.20,UV.x) * (1.0 - smoothstep(0.72,1.0,UV.x));
	ALBEDO = mix(vec3(0.19,0.42,0.50),vec3(0.79,0.89,0.92),strands);
	EMISSION = ALBEDO * 0.10;
	ROUGHNESS = 0.78;
	ALPHA = edge * pow(life,0.8) * COLOR.g * (0.34 + 0.52 * strands * fine);
}
