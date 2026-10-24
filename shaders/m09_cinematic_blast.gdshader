shader_type spatial;
render_mode unshaded,blend_mix,cull_disabled,depth_draw_never,shadows_disabled;
uniform float heat=1.0;
uniform float seed=0.0;
uniform float age=0.0;
varying vec3 object_point;
float hash(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
float noise3(vec3 p){vec3 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);}
void vertex(){object_point=VERTEX;}
void fragment(){
 vec3 p=object_point*4.0+vec3(seed,age*.9,seed*.41);
 float n=noise3(p)*.57+noise3(p*2.13)*.29+noise3(p*4.21)*.14;
 float facing=clamp(abs(dot(normalize(NORMAL),normalize(VIEW))),0.0,1.0);
 float edge=smoothstep(.04,.68,facing);
 float mask=smoothstep(.2,.72,n)*edge;
 float hot=clamp(n*.9+facing*.65-age*.16,0.0,1.0);
 vec3 flame=mix(vec3(.16,.025,.004),vec3(1.0,.3,.025),smoothstep(.15,.6,hot));
 flame=mix(flame,vec3(1.0,.88,.48),smoothstep(.7,1.0,hot));
 vec3 ash=mix(vec3(.018,.023,.03),vec3(.13,.12,.105),n);
 ALBEDO=mix(ash,flame,heat);EMISSION=flame*heat*2.2*hot;
 ALPHA=mask*mix(.76,.96,heat);ROUGHNESS=1.0;
}
