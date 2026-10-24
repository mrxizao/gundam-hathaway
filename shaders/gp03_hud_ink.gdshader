shader_type canvas_item;
// GP03 cockpit ink only. Red/amber alerts keep their combat meaning.
uniform vec3 blue_ink : source_color = vec3(0.38, 0.68, 1.0);
void fragment() {
	vec4 ink = COLOR;
	float value = max(ink.r, max(ink.g, ink.b));
	bool warm_alert = ink.r > ink.g * 1.12 && ink.r > ink.b * 1.15;
	if (!warm_alert) {
		ink.rgb = blue_ink * value;
	}
	COLOR = ink;
}
