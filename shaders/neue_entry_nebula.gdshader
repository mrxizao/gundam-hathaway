shader_type canvas_item;
render_mode unshaded;
float hash(vec3 p){return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453);}
float noise3(vec3 p){vec3 i=floor(p);vec3 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);}
void fragment(){vec3 direction=vec3((UV-.5)*vec2(3.2,1.8),.7);vec3 p=direction*2.0;float n=0.0;float a=.5;for(int i=0;i<4;i++){n+=noise3(p)*a;p=p*2.1+vec3(1.7);a*=.5;}float m=noise3(direction*1.5+vec3(9.0));vec3 color=vec3(.014,.023,.055)+mix(vec3(.11,.025,.17),vec3(.015,.13,.12),m)*smoothstep(.2,.8,n)*1.5;COLOR=vec4(color,1.0);}
