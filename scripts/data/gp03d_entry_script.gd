extends RefCounted
## A meteor prelude followed by one uninterrupted camera move around the MA.
const DURATION:=12.0
const REVEAL:=4.15
const NOZZLE_RISE_END:=4.85
const LINE_START:=3.15
const ENDS:=[4.15,5.1,7.35,DURATION]
const TITLES:=["高速接近","六喷口推进","雄蕊核心启动","GP03D · 战场突入"]
# time, camera, look target, vertical FOV. Shared tangents preserve C1 continuity.
const KEYS:=[
 [4.15,Vector3(-38,-42,66),Vector3(-9,-7,43),52.0],
 [4.85,Vector3(-38,-20,66),Vector3(-9,-7,43),52.0],
 [5.1,Vector3(-30,-15,62),Vector3(-6,-5,40),52.0],
 [5.55,Vector3(-32,-2,13),Vector3(-2,-1,16),48.0],
 [6.05,Vector3(-20,6,-22),Vector3(-.1,3.5,-4.5),42.0],
 [6.55,Vector3(-2,4,-11.8),Vector3(-.1,3.5,-4.5),32.0],
 [6.9,Vector3(-.2,4,-10.8),Vector3(-.1,3.5,-4.5),30.0],
 [7.35,Vector3(-.2,4,-10.8),Vector3(-.1,3.5,-4.5),30.0],
 [8.0,Vector3(-32,-8,-50),Vector3(0,1,-17),35.0],
 [8.9,Vector3(-66,-37,-108),Vector3(0,-2,-23),40.0],
 [12.0,Vector3(-74,-62,-112),Vector3(0,-2,-23),40.0]]
static func tangent(index:int,column:int)->Variant:
 if index==0 or index==KEYS.size()-1:return KEYS[index][column]*0.0
 if KEYS[index][column]==KEYS[index-1][column] or KEYS[index][column]==KEYS[index+1][column]:return KEYS[index][column]*0.0
 return (KEYS[index+1][column]-KEYS[index-1][column])/float(KEYS[index+1][0]-KEYS[index-1][0])
static func curve(t:float,column:int)->Variant:
 var i:=0
 while i<KEYS.size()-2 and t>float(KEYS[i+1][0]):i+=1
 var span:float=KEYS[i+1][0]-KEYS[i][0]
 var u:=clampf((t-float(KEYS[i][0]))/span,0.0,1.0)
 return (2*u*u*u-3*u*u+1)*KEYS[i][column]+(u*u*u-2*u*u+u)*span*tangent(i,column)+(-2*u*u*u+3*u*u)*KEYS[i+1][column]+(u*u*u-u*u)*span*tangent(i+1,column)
static func meteor(time:float)->Vector2:
 var u:=smoothstep(.2,3.15,time)
 return pow(1-u,3)*Vector2(1.04,-.06)+3*pow(1-u,2)*u*Vector2(.65,.2)+3*(1-u)*u*u*Vector2(.76,.8)+u*u*u*Vector2(.5,.5)
static func sample(time:float)->Dictionary:
 var t:=clampf(time,0.0,DURATION)
 var motion:=t
 var shot:=0
 for end in ENDS:
  if t<float(end):break
  shot+=1
 shot=mini(shot,3)
 var camera:=Vector3(0,8,180)
 var target:=Vector3(0,0,-6800)
 var fov:=52.0
 if t>=REVEAL:
  camera=curve(motion,1);target=curve(motion,2);fov=curve(motion,3)
 var detail:=smoothstep(5.3,6.5,motion)*(1.0-smoothstep(7.35,8.9,motion))
 var streak_weight:=lerpf(.48,.035,detail)*(1.0-.45*smoothstep(8.9,9.4,motion))
 var eye:=sin(PI*smoothstep(6.9,7.35,motion)) if motion>=6.9 and motion<=7.35 else 0.0
 return {"shot":shot,"motion_time":motion,"position":Vector3.ZERO,"camera":camera,"target":target,"fov":fov,"power":1.0,"roll":deg_to_rad(-6)*smoothstep(7.35,8.9,motion),"eye":eye,"spark":meteor(t),"streaks":streak_weight*smoothstep(LINE_START,3.7,t)*(1.0-smoothstep(DURATION-1.0,DURATION,t)),"line":smoothstep(LINE_START,3.5,t)*(1.0-smoothstep(4.0,REVEAL,t)),"rush":smoothstep(3.45,4.1,t)}
