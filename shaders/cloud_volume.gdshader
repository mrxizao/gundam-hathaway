shader_type fog;
uniform float density_scale = 0.0;
uniform vec3 cloud_tint : source_color = vec3(0.2, 0.24, 0.32);
void fog() {
	vec3 q = UVW * 2.0 - 1.0;
	float radius = length(q);
	float coarse = sin(q.x * 4.3 + q.y * 2.1) * sin(q.z * 3.7 - q.y * 1.4);
	float detail = sin(q.x * 9.1 - q.z * 4.7) * sin(q.y * 7.3 + q.z * 5.1);
	float shape = 1.0 - smoothstep(0.28, 1.0, radius + coarse * 0.16 + detail * 0.04);
	shape *= 1.0 - smoothstep(0.80, 1.0, max(max(abs(q.x), abs(q.y)), abs(q.z)));
	DENSITY = shape * (0.88 + coarse * 0.19 + detail * 0.09) * density_scale;
	ALBEDO = mix(vec3(0.42,0.48,0.56),vec3(0.72,0.76,0.80),smoothstep(-0.65,0.85,q.y));
	EMISSION = cloud_tint * 0.10 * DENSITY;
}
