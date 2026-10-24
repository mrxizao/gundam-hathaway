class_name PodStrikeScript
extends RefCounted
## M04: orbit -> Xi cockpit -> cloud reveal -> fiery descent -> rapid beam sweep
## -> Penelope cockpit/escape -> Xi cockpit -> third-person handoff.
const BGM := "xi"
const T_ORBIT_END := 17.0
const T_PACIFIC := 23.0
const T_REVEAL := 30.0
const T_BURN := 34.0
const T_INTERCEPT := 42.0
const T_FIRE := 52.0
const T_HIT := 52.4
const T_CUT := 52.8
const T_XI_REACT := T_CUT
const T_ENEMY_WIDE := 60.0
const T_ENEMY_EYE := 66.0
const T_ESCAPE := 72.0
const T_FLYOUT := 75.0
const T_CLOUD_RUSH := 78.0
const T_XI_FRONT := 84.0
const T_ORBIT_FINISH := 88.0
const TOTAL := 90.0
# Compatibility names; the final shot is a continuous front-to-back orbit.
const T_ESCAPE_END := T_XI_FRONT
const T_XI_EYE := T_XI_REACT
const T_PULLBACK := T_XI_FRONT
const FOE_DIST := 9500.0
const CAM_FOV := 34.0
const CAM_DIST := 3500.0
const SINK_DEPTH := 4000.0
const TILT_MAX := 0.08
# Legacy names retain callers without coupling the cinematic to weapon cooldowns.
const T_APPROACH := T_INTERCEPT
const T_CHARGE := T_FIRE - 1.7

enum Stage { ORBIT, XI_SHAKE, CLOUD, FALL, BURN, FIRE, XI_REACT, ENEMY_PUSH, ENEMY_EYE, ESCAPE, FLYOUT, CLOUD_RUSH, XI_FRONT, HANDOFF, BLACK, INTERCEPT }
static func stage_at(t: float) -> int:
	if t < T_ORBIT_END: return Stage.ORBIT
	if t < T_PACIFIC: return Stage.XI_SHAKE
	if t < T_REVEAL: return Stage.CLOUD
	if t < T_BURN: return Stage.FALL
	if t < T_INTERCEPT: return Stage.BURN
	if t < T_FIRE: return Stage.INTERCEPT
	if t < T_CUT: return Stage.FIRE
	if t < T_ENEMY_WIDE: return Stage.XI_REACT
	if t < T_ENEMY_EYE: return Stage.ENEMY_PUSH
	if t < T_ESCAPE: return Stage.ENEMY_EYE
	if t < T_FLYOUT: return Stage.ESCAPE
	if t < T_CLOUD_RUSH: return Stage.FLYOUT
	if t < T_XI_FRONT: return Stage.CLOUD_RUSH
	if t < T_ORBIT_FINISH: return Stage.XI_FRONT
	return Stage.HANDOFF
static func inside_pod(t: float) -> bool:
	return (t >= T_ORBIT_END and t < T_PACIFIC) or (t >= T_XI_REACT and t < T_ENEMY_WIDE)
static func shot_ease(t: float, start: float, end: float) -> float:
	var u := clampf((t-start)/maxf(end-start,0.001),0.0,1.0)
	return u*u*u*(u*(u*6.0-15.0)+10.0)
static func fly_camera(t: float, enemy_eye: Vector3, enemy_basis: Basis, xi: Transform3D, cloud_anchor:=Vector3.ZERO) -> Vector3:
	var front := xi * Vector3(0,18,-110)
	var forward := -xi.basis.z
	var points: Array[Vector3] = [enemy_eye,
		enemy_eye+enemy_basis.z*100.0,
		enemy_eye+enemy_basis.z*480.0+Vector3(0,-300,0),
		front+forward*2600.0+Vector3(0,-4500,0),
		front+forward*500.0+Vector3(0,-200,0),front]
	if cloud_anchor!=Vector3.ZERO:
		var midpoint: Vector3=(points[0]+points[1]*5.0+points[2]*10.0+points[3]*10.0+points[4]*5.0+points[5])/32.0
		var correction: Vector3=(cloud_anchor-midpoint)/0.625
		points[2]+=correction; points[3]+=correction
	var u := shot_ease(t,T_FLYOUT,T_XI_FRONT)
	# Quintic Bezier: exit backwards first, accelerate through cloud, settle in front.
	for width in range(points.size()-1,0,-1):
		for i in width: points[i]=points[i].lerp(points[i+1],u)
	return points[0]
static func done(t: float) -> bool: return t >= TOTAL
static func beam_alive(t: float) -> bool: return t >= T_FIRE and t < T_CUT
static func beam_secs() -> float: return T_CUT - T_FIRE
static func charge_secs() -> float: return 1.7
static func burning(t: float) -> bool: return t >= T_BURN
static func altitude(t: float) -> float:
	var times := [0.0,T_ORBIT_END,T_PACIFIC,T_REVEAL,T_BURN,T_HIT,T_ESCAPE,TOTAL]
	var heights := [300000.0,120000.0,12000.0,8500.0,7400.0,6000.0,4800.0,3500.0]
	for i in range(1,times.size()):
		if t <= times[i]: return lerpf(heights[i-1],heights[i],shot_ease(t,times[i-1],times[i]))
	return heights[-1]
static func pod_pos(t: float) -> Vector3:
	return Vector3((t-T_PACIFIC)*18.0,altitude(t),0.0)
static func sink_offset(t: float) -> float: return altitude(t)-10000.0
static func tilt_rad(t: float) -> float: return sin(t*0.8)*TILT_MAX
static func foe_pos(_t: float, pod: Vector3) -> Vector3:
	var range_m := lerpf(FOE_DIST,6500.0,shot_ease(_t,T_INTERCEPT,T_CHARGE))
	return pod + Vector3(-0.62,0.30,-0.725).normalized()*range_m
static func foe_aim(pod: Vector3) -> Vector3: return pod
static func sweep_aim(t: float, pod: Vector3) -> Vector3:
	var k := clampf((t-T_FIRE)/beam_secs(),0,1)
	return pod + Vector3(1.0,0.8,-0.52).normalized()*lerpf(-800.0,800.0,k)
static func escape_pos(t: float) -> Vector3:
	var origin := pod_pos(T_ESCAPE)
	var dt := maxf(0.0,t-T_ESCAPE)
	return origin + Vector3(-140.0,120.0,-340.0)*dt
# A continuous tracking shot tightens through cloud clearance, charge and impact.
static func cam_pos(t: float, pod: Vector3) -> Vector3:
	var reveal := shot_ease(t,T_PACIFIC,T_REVEAL)
	var burn := shot_ease(t,T_REVEAL,T_INTERCEPT)
	var overview := pod+Vector3(2400,700,-2600).lerp(Vector3(1600,420,-1850),reveal)
	overview=overview.lerp(pod+Vector3(1100,100,-1450),burn)
	if t < T_INTERCEPT: return overview
	if t >= T_FIRE: return pod+Vector3(800,150,-1000)
	var enemy := foe_pos(t,pod)
	var frame := Basis.looking_at(pod-enemy,Vector3.UP)
	var close := enemy+frame*Vector3(125,45,-200).lerp(Vector3(60,18,-110),shot_ease(t,47.0,T_FIRE))
	return overview.lerp(close,shot_ease(t,T_INTERCEPT,47.0))
static func cam_look(t: float,pod: Vector3,_foe: Vector3) -> Vector3:
	if t < T_INTERCEPT or t >= T_FIRE: return pod+Vector3(0,18,0)
	return (pod+Vector3(0,18,0)).lerp(foe_pos(t,pod)+Vector3.UP*8.0,shot_ease(t,T_INTERCEPT,47.0))
static func camera_fov(t: float) -> float:
	if t >= T_FIRE: return 38.0
	return lerpf(42.0,48.0,shot_ease(t,T_INTERCEPT,47.0))
static func impact_flash(t: float) -> float:
	return (1.0-shot_ease(t,T_HIT,T_HIT+0.25)) if t>=T_HIT and t<T_HIT+0.25 else 0.0
static func cockpit_damage(t: float) -> float:
	if t<T_XI_REACT or t>=T_ENEMY_WIDE:return 0.0
	return (0.35+0.15*sin(t*7.0))*shot_ease(t,T_XI_REACT,T_XI_REACT+0.3)
static func transition_black(t: float) -> float:
	# Only the two requested hard cuts; never black out the continuous fly-through.
	for cut: float in [T_XI_REACT,T_ENEMY_WIDE]:
		if absf(t-cut)<0.12:
			return smoothstep(cut-.10,cut,t)*(1.0-smoothstep(cut,cut+.12,t))
	return 0.0
static func stage_name(s: int) -> String:
	return ["轨道下坠","运输仓内部","穿云","下坠","再入燃烧","光束扫击","仓内受击","佩涅罗佩推进","佩涅罗佩驾驶舱","柯西脱仓","退出座舱","穿云追踪","柯西正面与环绕","第三人称待交接","转场","佩涅罗佩截击"][clampi(s,0,15)]
