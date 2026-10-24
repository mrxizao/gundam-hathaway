extends RefCounted
## Two views replay one hangar impact; only the exterior launch advances flight.
const EXTERIOR := 4.0
const IMPACT := 6.4
const REPLAY := 8.8
const REPLAY_IMPACT := 9.0
const FADE_START := 11.1
const BLACK := 13.1
const IGNITION := 14.0
const ASCENT_END := 22.0
const ORBIT_END := 26.0
const HOLD := 3.0
const TOTAL := ORBIT_END+HOLD
const DISPLAY_ALTITUDE := 700.0
const WORLD_ALTITUDE := DISPLAY_ALTITUDE/FlightHUD.ALT_DISPLAY_SCALE
const BASE_WORLD := Vector3(-9480,21,4410)
static func cockpit(t:float)->bool:
	return t<EXTERIOR or (t>=REPLAY and t<IGNITION)
static func impact_age(t:float)->float:
	return t-REPLAY_IMPACT if t>=REPLAY else t-IMPACT
static func blackout(t:float)->float:
	if t>=IGNITION:return 0.0
	return smoothstep(FADE_START,BLACK,t)
static func stage_name(t:float)->String:
	if t<EXTERIOR:return "机库待命"
	if t<REPLAY:return "机库遇袭"
	if t<IGNITION:return ""
	if t<ASCENT_END:return "紧急升空"
	return "迎击准备"
static func sample(t:float,home:Vector3)->Dictionary:
	t=clampf(t,0,TOTAL)
	var p:=home
	var pitch:=0.0
	var roll:=0.0
	var u:=clampf((t-IGNITION)/(ASCENT_END-IGNITION),0,1)
	if t<IGNITION:
		var age:=impact_age(t)
		var hit:=sin(PI*clampf(age/1.8,0,1)) if age>=0 else 0.0
		p+=Vector3(7,2,12)*hit
		roll=deg_to_rad(-11)*hit
	else:
		var airborne:=Vector3(-850,WORLD_ALTITUDE-BASE_WORLD.y,-2200)
		p=Vector3(0,home.y,-900).lerp(airborne,u*u*(3-2*u))
		pitch=deg_to_rad(48)*sin(PI*u)
		if t>=ASCENT_END:p.z-=minf(t-ASCENT_END,ORBIT_END-ASCENT_END)*85.0
	return {"position":p,"pitch":pitch,"roll":roll,"power":smoothstep(IGNITION,IGNITION+.8,t),"morph":smoothstep(IGNITION,IGNITION+1.8,t)}
