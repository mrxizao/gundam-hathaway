shader_type canvas_item;
render_mode unshaded;

// Rotate glyphs as one text plane, then project them back into the menu.
uniform vec2 pivot = vec2(0.0);
uniform vec2 tilt = vec2(0.0);
uniform float camera_distance = 400.0;

void vertex() {
	vec2 p = VERTEX - pivot;
	float sx = sin(tilt.x);
	float cx = cos(tilt.x);
	float sy = sin(tilt.y);
	float cy = cos(tilt.y);
	vec3 rotated = vec3(p.x * cy + p.y * sx * sy, p.y * cx, -p.x * sy + p.y * sx * cy);
	float perspective = camera_distance / (camera_distance - rotated.z);
	VERTEX = pivot + rotated.xy * perspective;
}
