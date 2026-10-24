shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, skip_vertex_transform;
uniform sampler2D missile_state : filter_nearest, repeat_disable;
uniform sampler2D smoke_grain : filter_linear, repeat_disable;
uniform float simulation_time = 0.0;
uniform int particles_per_missile = 32;
uniform float smoke_lifetime = 0.128;
varying float opacity;
varying vec3 smoke_color;
void vertex() {
 int missile = INSTANCE_ID / particles_per_missile;
 int particle = INSTANCE_ID % particles_per_missile;
 vec4 point = texelFetch(missile_state, ivec2(missile,0),0);
 vec3 velocity = texelFetch(missile_state, ivec2(missile,1),0).xyz;
 float seed = fract(sin(float(INSTANCE_ID)*12.9898+0.37)*43758.5453);
 float age = (float(particle)+fract(simulation_time/smoke_lifetime+seed))/float(particles_per_missile);
 float stale = max(simulation_time-point.w,0.0);
 float fade = clamp(1.0-stale/smoke_lifetime,0.0,1.0);
 float diameter = 1.8*mix(3.2,8.5,seed)*0.65*mix(0.55,1.3,age);
 vec3 center = point.xyz-velocity*(age*smoke_lifetime)+vec3(sin(seed*40.0),age*2.0,cos(seed*29.0))*age;
 vec4 view_center = VIEW_MATRIX*vec4(center,1.0);
 VERTEX = view_center.xyz+vec3(VERTEX.xy*diameter,0.0);
 opacity = (age<.45 ? mix(.88,.56,age/.45) : mix(.56,0.0,(age-.45)/.55))*fade;
 smoke_color = mix(vec3(0.86,0.86,0.89),vec3(0.62,0.62,0.67),age);
}
void fragment() {
 float radius = length(UV-vec2(0.5))*2.0;
 ALBEDO = smoke_color;
 ALPHA = opacity*(1.0-smoothstep(0.25,1.0,radius))*mix(.55,1.0,texture(smoke_grain,UV).r);
}
