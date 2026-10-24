shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D display_tex : source_color;
uniform vec4 region;
uniform vec3 upper_color : source_color = vec3(0.105, 0.12, 0.29);
uniform vec3 lower_color : source_color = vec3(0.012, 0.018, 0.043);

void fragment() {
	vec4 sample_color = texture(display_tex, region.xy + UV * region.zw);
	float value = max(sample_color.r, max(sample_color.g, sample_color.b));
	float chroma = value - min(sample_color.r, min(sample_color.g, sample_color.b));
	float neutral = 1.0 - smoothstep(0.025, 0.14, chroma);
	vec3 lavender = vec3(0.53, 0.49, 0.79) * value + vec3(0.016, 0.012, 0.045);
	vec3 ink = mix(sample_color.rgb, lavender, neutral);
	// The display substrate fades vertically; information does not.
	float fade = smoothstep(0.08, 0.93, UV.y);
	vec3 substrate = mix(upper_color, lower_color, fade);
	float edge = smoothstep(0.0, 0.06, UV.x) * smoothstep(0.0, 0.06, 1.0 - UV.x);
	substrate *= mix(0.68, 1.0, edge);
	float information = smoothstep(0.013, 0.075, value) * sample_color.a;
	ALBEDO = mix(substrate, ink, information);
}
