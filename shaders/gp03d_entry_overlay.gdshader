shader_type canvas_item;
render_mode unshaded, blend_add;
uniform float sequence_time=0.0;
uniform vec2 aspect=vec2(1.77778,1.0);
uniform vec2 spark_center=vec2(0.5,0.5);
uniform float approach=0.0;
uniform float streaks=0.0;
uniform float detail_focus=0.0;
uniform float line_open=0.0;
uniform float rush=0.0;
uniform vec2 trail_points[25];
uniform float trail_alpha=0.0;
uniform float eye_flash=0.0;
uniform vec2 eye_center=vec2(0.5,0.5);
float hash(float n){return fract(sin(n*127.1)*43758.5453);}
void fragment(){
 vec2 p=(UV-spark_center)*aspect/(1.0+rush*5.0);
 float d=length(p);
 float spark=(0.00005/(d*d+0.000035)+exp(-abs(p.x)*300.0-abs(p.y)*25.0)*1.4+exp(-abs(p.y)*280.0-abs(p.x)*30.0))*approach;
 float trail=0.0;
 for(int i=0;i<24;i++){
  vec2 a=trail_points[i]*aspect;vec2 b=trail_points[i+1]*aspect;
  vec2 v=b-a;vec2 q=UV*aspect-a;
  float along=clamp(dot(q,v)/max(dot(v,v),0.0000001),0.0,1.0);
  float distance_to_tail=length(q-v*along);
  trail+=exp(-distance_to_tail*distance_to_tail/0.000015)*pow(1.0-float(i)/24.0,2.0)*.8;
 }
 vec2 q=(UV-vec2(0.5))*aspect;
 float r=length(q);float angle=atan(q.y,q.x);
 float lane=floor((angle+3.141593)*48.0);
 float width=abs(fract((angle+3.141593)*48.0)-0.5);
 float phase=fract(r*.85-sequence_time*(.5+hash(lane)*.7)+hash(lane+3.0));
 float detail_mask=mix(1.0,smoothstep(.28,.68,r),detail_focus);
 float ray=detail_mask*(1.0-smoothstep(.02,.075,width))*smoothstep(.72,.9,phase)*(1.0-smoothstep(.95,1.0,phase))*smoothstep(.09,.5,r)*streaks;
 float horizon=exp(-abs(q.y)*1200.0)*(1.0-smoothstep(line_open*.95,line_open*.95+.04,abs(q.x)))*line_open;
 vec2 e=(UV-eye_center)*aspect;
 float eye=exp(-abs(e.y)*700.0)*exp(-abs(e.x)*8.0)*eye_flash;
 float eye_core=exp(-dot(e,e)/.00012)*eye_flash;
 float eye_halo=exp(-dot(e,e)/.003)*eye_flash;
 vec3 color=vec3(.35,.65,1.0)*(spark+trail*trail_alpha)+vec3(.4,.62,.9)*ray*.55+vec3(.4,.65,1.0)*horizon*2.0;
 color+=vec3(.55,1.0,.12)*(eye*5.0+eye_halo*.6)+vec3(1.0)*eye_core*4.0;
 COLOR=vec4(color,1.0);
}
