shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D display_tex : source_color, filter_linear;
uniform vec4 region;
void fragment() {
	vec4 data = texture(display_tex, region.xy + UV * region.zw);
	float edge = smoothstep(0.0,0.035,UV.x)*smoothstep(0.0,0.035,1.0-UV.x);
	vec3 substrate = vec3(0.003,0.009,0.026)*mix(0.6,1.0,edge);
	ALBEDO = mix(substrate,data.rgb,data.a);
}
