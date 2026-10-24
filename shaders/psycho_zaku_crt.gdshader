shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D display_tex : source_color, filter_linear;
uniform vec4 region;
uniform bool round_screen = false;
void fragment() {
 vec4 data = texture(display_tex,region.xy+UV*region.zw);
 ALBEDO=mix(vec3(.009,.004,.002),data.rgb,data.a);
 EMISSION=data.rgb*data.a*.10;
 ALPHA=round_screen ? 1.0-smoothstep(.482,.497,length(UV-vec2(.5))) : 1.0;
 ALPHA_SCISSOR_THRESHOLD=.5;
}
