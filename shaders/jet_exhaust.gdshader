shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;

uniform bool billboard = false;
uniform float gain = 1.15;
uniform float flow_speed = 7.0;
uniform float turbulence = 0.35;
instance uniform float age_end = 1.0;
varying vec4 flame_color;
varying float phase;
varying float age;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() {
	flame_color = COLOR;
	phase = float(INSTANCE_ID) * 0.6180339;
	age = INSTANCE_CUSTOM.y;
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
			INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
			INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}
void fragment() {
	// Smooth silhouette removes the opaque bead/rod appearance. Noise advects along the jet.
	float facing = pow(clamp(abs(dot(normalize(NORMAL),normalize(VIEW))),0.0,1.0),1.35);
	vec2 q = vec2(UV.x*9.0 + phase, (1.0-UV.y)*5.0 - TIME*flow_speed);
	float flow = noise(q) * 0.65 + noise(q*2.13 + 4.7) * 0.35;
	float wisps = smoothstep(0.12,0.85,flow);
	float body = mix(0.58,1.0,wisps);
	float edge = smoothstep(0.02,0.45,facing);
	float hot = pow(facing,3.0) * (0.28 + 0.12*wisps);
	vec3 color = mix(flame_color.rgb,vec3(0.80,0.90,1.0),hot);
	EMISSION = color * gain * body;
	ALBEDO = color * gain * body;
	ALPHA = 0.18 * flame_color.a * facing * edge * mix(1.0,body,turbulence)
		* (1.0-smoothstep(age_end*0.6,age_end,age));
}
