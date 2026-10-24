shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D display_tex : source_color;
uniform vec4 region;
uniform vec3 upper_color : source_color;
uniform vec3 lower_color : source_color;
void fragment() {
 vec4 src = texture(display_tex, region.xy + UV * region.zw);
 float step_time = floor(TIME * 12.0);
 float noise = fract(sin(dot(floor(UV*vec2(480.0,280.0)),vec2(12.9898,78.233))+step_time)*43758.5453);
 float scan = mix(0.83,1.0,step(0.38,fract(UV.y*140.0)));
 float edge = smoothstep(0.0,0.10,UV.x)*smoothstep(0.0,0.10,1.0-UV.x)*smoothstep(0.0,0.10,UV.y)*smoothstep(0.0,0.10,1.0-UV.y);
 vec3 phosphor = src.rgb * scan * (0.96+noise*0.04);
 ALBEDO = (phosphor + vec3(0.002,0.008,0.004)) * mix(0.62,1.0,edge);
}
