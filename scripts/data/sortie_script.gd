extends RefCounted
const NEUE_ENTRY:=preload("res://scripts/data/neue_entry_script.gd")
const GP03_ENTRY:=preload("res://scripts/data/gp03d_entry_script.gd")
## Shared timing: both lighting variants use identical geometry and motion.
const RUNWAY_STAGES := ["机库开启", "牵引出库", "跑道就位", "滑行加速", "离地爬升", "进入战场"]
const DECK_STAGES := ["甲板待命", "解除固定", "推进点火", "垂直升空", "离舰加速", "进入战场"]
const XI_STAGES := ["甲板待命", "解除固定", "推进点火", "垂直升空", "展开巡航形态", "离舰加速", "进入战场"]
const XI_ENDS := [1.2,2.3,3.1,5.3,6.5,8.2,9.7]
const XI_FORM_START := 5.3
const XI_FORM_END := 6.5
const RUNWAY_ENDS := [1.4,4.0,9.0,12.0,14.0,16.0]
const DECK_ENDS := [1.2,2.3,3.1,5.3,7.0,8.5]
static func supported(p:SuitProfile)->bool:
	return p!=null and not (p.id==SuitProfile.Id.PENELOPE and p.form!=0) and not (p.id==SuitProfile.Id.ARIZEUS and p.form==SuitProfile.ArizeusForm.CORE_NU) and p.id in [SuitProfile.Id.XI,SuitProfile.Id.PENELOPE,SuitProfile.Id.ARIZEUS,SuitProfile.Id.GUSTAV00,SuitProfile.Id.MESSER_M01,SuitProfile.Id.MESSER_CMD,SuitProfile.Id.MESSER_F01,SuitProfile.Id.REGZ_CUSTOM,SuitProfile.Id.GP03D,SuitProfile.Id.NU_GUNDAM,SuitProfile.Id.NEUE_ZIEL,SuitProfile.Id.SAZABI]
static func deck(p:SuitProfile)->bool:
	return p.id in [SuitProfile.Id.XI,SuitProfile.Id.MESSER_M01,SuitProfile.Id.MESSER_CMD,SuitProfile.Id.MESSER_F01]
static func pedal(p:SuitProfile)->bool:
	return p.id in [SuitProfile.Id.GUSTAV00,SuitProfile.Id.MESSER_M01,SuitProfile.Id.MESSER_CMD,SuitProfile.Id.MESSER_F01]
static func cruise(p:SuitProfile)->bool:
	return p.id in [SuitProfile.Id.PENELOPE,SuitProfile.Id.ARIZEUS,SuitProfile.Id.REGZ_CUSTOM]
static func profile(p:SuitProfile)->SuitProfile:
	if p.id==SuitProfile.Id.ARIZEUS:return SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE)
	if p.id==SuitProfile.Id.REGZ_CUSTOM:return SuitProfile.regz_custom(1)
	return SuitProfile.by_id(p.id)
static func duration(p:SuitProfile)->float:
	if p.id==SuitProfile.Id.NEUE_ZIEL:return NEUE_ENTRY.DURATION
	return GP03_ENTRY.DURATION if p.id==SuitProfile.Id.GP03D else (9.7 if p.id==SuitProfile.Id.XI else (8.5 if deck(p) else 16.0))
static func stage_at(p:SuitProfile,time:float)->int:
	if p.id==SuitProfile.Id.NEUE_ZIEL:return NEUE_ENTRY.sample(time).shot
	if p.id==SuitProfile.Id.GP03D:return GP03_ENTRY.sample(time).shot
	var ends:Array=XI_ENDS if p.id==SuitProfile.Id.XI else (DECK_ENDS if deck(p) else RUNWAY_ENDS)
	for i in ends.size():
		if time<float(ends[i]):return i
	return ends.size()-1
static func version(p:SuitProfile,night:bool)->Array[String]:
	if p.id==SuitProfile.Id.NEUE_ZIEL:
		var titles:Array[String]=[];titles.assign(NEUE_ENTRY.TITLES);return titles
	if p.id==SuitProfile.Id.GP03D:
		var titles:Array[String]=[];titles.assign(GP03_ENTRY.TITLES);return titles
	var names:Array=XI_STAGES if p.id==SuitProfile.Id.XI else (DECK_STAGES if deck(p) else RUNWAY_STAGES)
	var result:Array[String]=[]
	for item in names:result.append(str(item)+(" · 阿德莱德机库" if not deck(p) else "")+(" · 夜间" if night else " · 白天"))
	return result
static func sample(p:SuitProfile,time:float)->Dictionary:
	if p.id==SuitProfile.Id.NEUE_ZIEL:
		var shot:Dictionary=NEUE_ENTRY.sample(time)
		shot["pitch"]=shot.rotation.x;shot["stage"]=shot.shot;shot["cruise_morph"]=-1.0
		return shot
	if p.id==SuitProfile.Id.GP03D:
		var shot:Dictionary=GP03_ENTRY.sample(time)
		shot["pitch"]=0.0;shot["stage"]=shot.shot;shot["cruise_morph"]=-1.0
		return shot
	var t:=clampf(time,0,duration(p));var position:=Vector3.ZERO
	var pitch:=0.0;var power:=0.05
	if deck(p):
		var lift:=clampf((t-3.1)/2.2,0,1)
		var departure:float=XI_FORM_END if p.id==SuitProfile.Id.XI else 5.3
		var forward:=maxf(t-departure,0)
		position=Vector3(0,65*lift*lift+forward*forward*14,-forward*forward*65)
		pitch=deg_to_rad(8.0)*smoothstep(departure,departure+1.9,t)
		power=lerpf(.08,1.0,smoothstep(2.3,3.4,t))
	else:
		var convoy:=tow_pose(t)
		var roll:=maxf(t-9.0,0)
		var air:=maxf(t-12.0,0)
		position=convoy.position+Vector3(0,air*air*65,-roll*roll*220)
		pitch=deg_to_rad(9.0)*smoothstep(11.5,13.0,t)
		power=lerpf(.05,1.0,smoothstep(8.7,10.0,t))
	return {"position":position,"pitch":pitch,"power":power,"stage":stage_at(p,t),"cruise_morph":smoothstep(XI_FORM_START,XI_FORM_END,t) if p.id==SuitProfile.Id.XI else -1.0}


## One convoy path drives tractor, trailer and cargo until runway release.
static func tow_pose(time:float)->Dictionary:
	var position:=Vector3(-5490*smoothstep(4.0,8.0,time),0,-990*smoothstep(1.4,4.0,time))
	var yaw:=PI*.5*smoothstep(4.0,4.6,time)*(1.0-smoothstep(7.4,8.0,time))
	return {"position":position,"yaw":yaw}


## Valiant has been sunk by M08; Xi no longer has a carrier departure scene.
static func supported_in_mission(p:SuitProfile,mission_id:String)->bool:
	if not supported(p):return false
	if p.id==SuitProfile.Id.XI and mission_id.begins_with("M"):
		var number:=mission_id.substr(1)
		if number.is_valid_int() and number.to_int()>=8:return false
	return true
