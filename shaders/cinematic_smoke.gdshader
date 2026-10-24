shader_type spatial;
render_mode blend_mix,depth_draw_never,cull_disabled,shadows_disabled,diffuse_lambert_wrap;
uniform sampler2D grain : source_color,repeat_enable,filter_linear_mipmap;
uniform sampler2D scene_depth : hint_depth_texture,repeat_disable,filter_nearest;
uniform float opacity=0.34;
uniform float contact_softness=3.0;
varying vec4 smoke_color;
varying float phase;
void vertex(){
 smoke_color=COLOR;phase=float(INSTANCE_ID)*0.6180339;
 float wrinkle=sin(VERTEX.x*1.8+phase*6.0)*sin(VERTEX.z*2.1-phase*3.0);
 VERTEX*=1.0+wrinkle*0.10;
}
void fragment(){
 vec4 cloud=texture(grain,UV*vec2(1.3,1.1)+vec2(phase,phase*0.37));
 float facing=pow(clamp(abs(dot(normalize(NORMAL),normalize(VIEW))),0.0,1.0),2.0);
 float edge=smoothstep(0.18,0.65,facing);
 float wisps=smoothstep(0.48,0.82,cloud.r);
 float soft=1.0;
 float depth=textureLod(scene_depth,SCREEN_UV,0.0).r;
 #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
 bool has_geometry=depth<0.999999;
 float clip_depth=depth*2.0-1.0;
#else
 bool has_geometry=depth>0.000001;
 float clip_depth=depth;
#endif
 if(has_geometry){
  vec4 point=INV_PROJECTION_MATRIX*vec4(SCREEN_UV*2.0-1.0,clip_depth,1.0);
  soft=clamp((-point.z/point.w+VERTEX.z)/max(contact_softness,0.01),0.0,1.0);
 }
 float near_fade=smoothstep(0.8,7.0,length(VERTEX));
 ALBEDO=smoke_color.rgb*mix(0.80,1.12,cloud.r);
 ALPHA=smoke_color.a*cloud.a*opacity*facing*edge*wisps*soft*near_fade;
 ROUGHNESS=1.0;SPECULAR=0.0;METALLIC=0.0;
}
