shader_type canvas_item;
render_mode unshaded, blend_add;
uniform float sequence_time=0.0;
uniform float smoke=0.0;
uniform float eye_flash=0.0;
uniform vec2 eye_center=vec2(.5);
uniform float streaks=0.0;
uniform float beam_rush=0.0;
uniform vec2 aspect=vec2(1.77778,1);
float hash(float x){return fract(sin(x*127.1)*43758.5453);}
void fragment(){
 vec2 p=(UV-vec2(.5))*aspect;float r=length(p);float angle=atan(p.y,p.x);
 float lane=floor((angle+3.14159)*35.0);float width=abs(fract((angle+3.14159)*35.0)-.5);
 float phase=fract(r*.7-sequence_time*(.7+hash(lane)));
 float lines=(1.0-smoothstep(.01,.07,width))*smoothstep(.75,.9,phase)*smoothstep(.15,.7,r)*streaks;
 float green=0.0;
 for(int i=0;i<8;i++){float direction=float(i)*.7854+sequence_time*.025;vec2 ray=vec2(cos(direction),sin(direction));float perpendicular=abs(dot(p,vec2(-ray.y,ray.x)));float along=dot(p,ray);green+=exp(-perpendicular*perpendicular/(.00003+.0015*r*r))*smoothstep(.08,.6,along)*smoothstep(.3,.8,fract(along*.65-sequence_time*1.5+float(i)*.13));}
 vec2 e=(UV-eye_center)*aspect;
 float eye=(exp(-abs(e.y)*700.0-abs(e.x)*12.0)*3.0+exp(-dot(e,e)/.00015)*5.0+exp(-dot(e,e)/.003)*.5)*eye_flash;
 float vapor=exp(-dot(p,p)*1.5)*(.3+.2*sin(p.x*18.0+sequence_time*3.0)*sin(p.y*17.0-sequence_time))*smoke;
 vec3 color=vec3(.6,.68,.8)*lines*.35+vec3(.4,1.0,.03)*green*beam_rush*2.0+vec3(1.0,.06,.65)*eye+vec3(.32,.3,.36)*vapor;
 COLOR=vec4(color,1.0);
}
