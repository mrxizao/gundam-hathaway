extends RefCounted
const DURATION:=15.2
const ENDS:=[4.5,5.6,6.6,9.8,11.6,12.9,15.2]
const TITLES:=["弧线接近","推进烟雾散开","独眼启动","NEUE ZIEL · 全机展开","高速突入 / 光束齐射","回旋加速","进入战场"]
static func position_at(t:float)->Vector3:
 if t<4.5:
  var u:=smoothstep(0.0,4.5,maxf(t,0.0))
  return Vector3(sin(t*1.6)*300*(1-u),cos(t*1.2)*190*(1-u),-6500*pow(1-u,2))
 if t<9.8:return Vector3.ZERO
 var a:=t-9.8
 return Vector3(sin(a*2.1)*90*smoothstep(1.3,2.0,a),sin(a*1.7)*40,-a*a*180)
static func sample(time:float)->Dictionary:
 var t:=clampf(time,0.0,DURATION);var shot:=0
 for end in ENDS:
  if t<float(end):break
  shot+=1
 shot=mini(shot,6)
 var position:=position_at(t)
 var camera:=Vector3(0,35,500);var target:=position;var fov:=52.0
 var rotation:=Vector3.ZERO
 if shot==0:rotation.z=sin(t*1.6)*.2
 elif shot==1:
  camera=Vector3(-85,25,-110);target=Vector3(0,12,0);fov=44
 elif shot==2:
  # Replaced with the live head anchor by the director.
  camera=Vector3(-12,3,-24);target=Vector3(0,0,-3);fov=34
 elif shot==3:
  var u:=smoothstep(6.6,9.8,t)
  camera=Vector3(-12,20,-145).lerp(Vector3(12,30,-190),u);target=Vector3(0,4,0);fov=40
 elif shot==4:
  camera=position+Vector3(0,35,-260);target=position+Vector3(0,16,0);fov=52
  rotation=Vector3(.08,0,-.18*smoothstep(10.2,11.0,t))
 elif shot==5:
  camera=Vector3(90,90,200);target=position;fov=46
  rotation=Vector3(.15,sin(t*1.7)*.18,sin(t*2.3)*.45)
 else:
  camera=position+Vector3(0,6,-55);target=camera+Vector3(0,0,-1800);fov=65
 return {"shot":shot,"position":position,"camera":camera,"target":target,"fov":fov,"rotation":rotation,"power":1.0,"eye":sin(PI*smoothstep(5.75,6.5,t)) if t>5.75 and t<6.5 else 0.0,"smoke":smoothstep(4.35,4.65,t)*(1.0-smoothstep(4.7,5.5,t)),"streaks":smoothstep(9.8,10.5,t),"beam_rush":smoothstep(12.9,13.5,t)}
