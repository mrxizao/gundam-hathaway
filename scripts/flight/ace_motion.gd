extends RefCounted
## Locomotion variants are private playback aliases; form baselines stay authored.
const Math := preload("res://scripts/flight/saber_motion.gd")
const Sample := preload("res://scripts/flight/gun_motion.gd")
static var _cache: Dictionary = {}
static func supports(p: SuitProfile) -> bool:
	return p.id not in [SuitProfile.Id.GP03D,SuitProfile.Id.NEUE_ZIEL,SuitProfile.Id.GP03S]
static func install(anim: ModelAnimator, body) -> bool:
	if anim == null or not anim.ready or body._model_skel == null or not supports(body.profile): return false
	var sk: Skeleton3D=body._model_skel
	var root: Transform3D=body.global_transform.affine_inverse()*sk.global_transform
	if anim.has("dash_f"):
		for name in ["dash_u","dash_d"]:
			if anim.has(name): continue
			var source: Animation=anim.player.get_animation("dash_f").duplicate()
			anim.player.get_animation_library(ModelAnimator.DEFAULT_LIBRARY).add_animation(name,source)
			anim.actions[name]=true
	var key: String=body.profile.model_path+":"+anim._track_base()
	if not _cache.has(key):
		var clips: Dictionary={}
		for action in anim.actions:
			var n:=str(action)
			if n.begins_with("dash_") or (body.profile.id in [SuitProfile.Id.XI,SuitProfile.Id.XI_FINAL] and (n=="fly" or n.begins_with("fly_") or n.begins_with("turn_"))):
				clips[n]=build(sk,root,body.profile,anim._track_base(),n,anim.player.get_animation(n))
		_cache[key]=clips
	var library:=anim.player.get_animation_library(ModelAnimator.DEFAULT_LIBRARY)
	for n in _cache[key]:
		var alias: String="__ace_"+str(n)
		library.add_animation(alias,_cache[key][n]);anim.pose_overrides[str(n)]=alias
	anim.motion_skeleton=sk
	anim.motion_suit=int(body.profile.id)
	return true
static func direction(name: String) -> Vector2:
	var suffix:=name.trim_prefix("dash_").trim_prefix("fly_")
	return Vector2((-1.0 if suffix.contains("l") else 0.0)+(1.0 if suffix.contains("r") else 0.0),(1.0 if suffix.contains("f") else 0.0)-(1.0 if suffix.contains("b") else 0.0)).normalized()
static func pose(sk: Skeleton3D,root: Transform3D,p: SuitProfile,name: String,time: float) -> Dictionary:
	var v:=Sample._sample(sk,null,0)
	var r: Array[Quaternion]=v["r"]
	var pos: Array[Vector3]=v["p"]
	var scale: Array[Vector3]=v["s"]
	var heavy: bool=(p.id==SuitProfile.Id.PENELOPE and p.form==0) or p.id==SuitProfile.Id.GUSTAV00 or (p.id==SuitProfile.Id.ARIZEUS and p.form==SuitProfile.ArizeusForm.NORMAL)
	var final_xi := p.id == SuitProfile.Id.XI_FINAL
	var dash:=name.begins_with("dash_")
	var turn:=name.begins_with("turn_")
	var vertical:=1.0 if name=="dash_u" else (-1.0 if name=="dash_d" else 0.0)
	var dir:=Vector2.ZERO if name=="fly" or turn else direction(name)
	var launch: float=0.16 if heavy else 0.11
	var kick: float=Math._smooth(clampf(time/launch,0,1)) * (1.0-0.38*Math._smooth((time-0.30)/0.22)) if dash else 1.0
	var compress: float=sin(clampf(time/launch,0,1)*PI) if dash else 0.0
	var brake: float=sin(PI*clampf((time-0.30)/0.22,0,1)) if dash else 0.0
	var character: float=0.85 if p.id==SuitProfile.Id.GUSTAV00 else (1.12 if p.id==SuitProfile.Id.MESSER_F01 else (0.95 if p.id==SuitProfile.Id.MESSER_CMD else 1.0))
	var trim:=sin(TAU*time/2.8)*0.35 if not dash else 0.0
	var pitch: float=-dir.y*(13.0 if dash else 6.0)*(0.72 if heavy else 1.0)*kick
	pitch-=vertical*5.0*kick
	if dash: pitch=(pitch+dir.y*4.0*brake)*character
	var bank: float=-dir.x*(14.0 if dash else 8.0)*(0.70 if heavy else 1.0)*kick
	var yaw: float=-dir.x*(4.0 if heavy else 7.0)*kick
	if dash: bank=(bank+dir.x*3.0*brake)*character
	if final_xi:
		pitch *= 1.18
		bank *= 1.12
	if turn:
		if name.ends_with("pitch_up"): pitch=7.0
		elif name.ends_with("pitch_down"): pitch=-7.0
		elif name.ends_with("yaw_L"): yaw=6.0;bank=3.0
		elif name.ends_with("yaw_R"): yaw=-6.0;bank=-3.0
		elif name.ends_with("roll_L"): bank=9.0
		elif name.ends_with("roll_R"): bank=-9.0
	for part in [["Hips",0.60],["Spine",0.25],["Chest",0.15]]:
		Math._rotate_body_axis(sk,part[0],Vector3.RIGHT,deg_to_rad((pitch+trim-3.0*compress)*part[1]),r,pos,scale,root)
		Math._rotate_body_axis(sk,part[0],Vector3.UP,deg_to_rad(yaw*part[1]),r,pos,scale,root)
		Math._rotate_body_axis(sk,part[0],Vector3.BACK,deg_to_rad(bank*part[1]),r,pos,scale,root)
	Math._rotate_body_axis(sk,"Head",Vector3.RIGHT,deg_to_rad(-pitch*0.45),r,pos,scale,root)
	Math._rotate_body_axis(sk,"Head",Vector3.BACK,deg_to_rad(-bank*0.50),r,pos,scale,root)
	for side in ["L","R"]:
		var sign_x:=1.0 if side=="R" else -1.0
		var knee: float=(16.0 if heavy else 22.0)+(17.0 if dash else 0.0)*kick+12.0*compress+7.0*brake+dir.x*sign_x*7.0*kick
		var hip: float=-5.0-dir.y*(18.0 if dash else 7.0)*kick+dir.x*sign_x*9.0*kick-6.0*compress+4.0*brake
		hip+=vertical*14.0*kick
		knee+=(18.0 if vertical>0.0 else -12.0)*absf(vertical)*kick
		# Reverse thrust braces the knees forward, rather than mirroring a forward lean.
		if dash and dir.y<0: hip+=10.0*absf(dir.y)*kick;knee+=8.0*absf(dir.y)*kick
		# Final-battle Xi uses a planted lead leg and a trailing tucked leg.
		# The lead stays fixed through a burst; this is thrust trim, not a running cycle.
		if final_xi:
			var lead_right := dir.x >= 0.0 if absf(dir.x)>0.1 else dir.y >= 0.0
			var lead := sign_x * (1.0 if lead_right else -1.0)
			var stagger := 7.0 + (18.0*kick if dash else 0.0)
			hip += lead*stagger
			knee += lead*(4.0 + (11.0*kick if dash else 0.0))
			knee = clampf(knee,10.0,78.0)
		Math._rotate_body_axis(sk,"Thigh."+side,Vector3.RIGHT,deg_to_rad(hip+trim),r,pos,scale,root)
		Math._rotate_body_axis(sk,"Thigh."+side,Vector3.BACK,deg_to_rad(sign_x*(3.0 if heavy else 5.0)-dir.x*4.0*kick),r,pos,scale,root)
		Math._rotate_body_axis(sk,"Shin."+side,Vector3.RIGHT,deg_to_rad(-knee),r,pos,scale,root)
		Math._rotate_body_axis(sk,"Foot."+side,Vector3.RIGHT,deg_to_rad(knee*0.35),r,pos,scale,root)
	Math._rotate_body_axis(sk,"UpperArm.L",Vector3.BACK,deg_to_rad(-10.0-(5.0 if dash else 0.0)*kick),r,pos,scale,root)
	Math._rotate_body_axis(sk,"LowerArm.L",Vector3.RIGHT,deg_to_rad((22.0 if final_xi else 16.0)+5.0*compress),r,pos,scale,root)
	return v
static func build(sk: Skeleton3D,root: Transform3D,p: SuitProfile,base: String,name: String,source: Animation) -> Animation:
	var clip: Animation=source.duplicate()
	var dash:=name.begins_with("dash_")
	clip.length=0.52 if dash else 2.8
	clip.loop_mode=Animation.LOOP_NONE if dash else Animation.LOOP_LINEAR
	var owned: Array[String]=["Root","Hips","Spine","Chest","Neck","Head","Thigh.L","Thigh.R","Shin.L","Shin.R","Foot.L","Foot.R","Toe.L","Toe.R","UpperArm.L","LowerArm.L"]
	for tr in range(clip.get_track_count()-1,-1,-1):
		var path:=clip.track_get_path(tr)
		if path.get_subname_count()==1 and str(path.get_subname(0)) in owned: clip.remove_track(tr)
	var tracks: Dictionary={}
	for name_bone in owned:
		var bone:=sk.find_bone(name_bone)
		if bone<0: continue
		var tr:=clip.add_track(Animation.TYPE_ROTATION_3D);clip.track_set_path(tr,NodePath(base+":"+name_bone));tracks[bone]=tr
		for type in [Animation.TYPE_POSITION_3D,Animation.TYPE_SCALE_3D]:
			var channel:=clip.add_track(type);clip.track_set_path(channel,NodePath(base+":"+name_bone))
			clip.track_insert_key(channel,0.0,sk.get_bone_rest(bone).origin if type==Animation.TYPE_POSITION_3D else sk.get_bone_rest(bone).basis.get_scale())
	for frame in range(ceili(clip.length*60)+1):
		var time:=minf(float(frame)/60.0,clip.length)
		var values:=pose(sk,root,p,name,time)
		for bone: int in tracks: clip.track_insert_key(tracks[bone],time,values["r"][bone])
	return clip

static func finish(anim: ModelAnimator,body) -> void:
	if anim==null or not anim.ready or body.profile.id not in [SuitProfile.Id.XI,SuitProfile.Id.XI_FINAL,SuitProfile.Id.PENELOPE] or body._model_skel==null: return
	var sk: Skeleton3D=body._model_skel
	var root: Transform3D=body.global_transform.affine_inverse()*sk.global_transform
	var library:=anim.player.get_animation_library(ModelAnimator.DEFAULT_LIBRARY)
	var key: String="%s:%s:%.4f:%.4f" % [body.profile.model_path,anim._track_base(),body.profile.target_height,body.profile.model_yaw_deg]
	var weapon: Dictionary=Sample._weapons.get(key,{})
	# Right-hand firearm stays safely lowered while the left arm owns melee.
	var slash:=Sample.build(sk,root,body.profile,anim._track_base(),anim.player.get_animation("slash"),false,weapon,true)
	library.remove_animation("slash");library.add_animation("slash",slash)
	var idle: String=anim.idle_action if not anim.idle_action.is_empty() else str(ModelAnimator.REST_CLIP)
	var flight:=Sample._sample(sk,anim.player.get_animation(anim.playback_name(idle)),0.0)
	var saber:=Sample._sample(sk,slash,0.0)
	for name in ["trans_fly_to_slash","trans_slash_to_fly"]:
		if not anim.has(name): continue
		var reverse: bool=name=="trans_slash_to_fly"
		var clip:=Animation.new();clip.length=0.34 if reverse else 0.30
		if body.profile.id==SuitProfile.Id.PENELOPE: clip.length+=0.06
		var start: Dictionary=saber if reverse else flight
		var end: Dictionary=flight if reverse else saber
		for bone in sk.get_bone_count():
			for type in [Animation.TYPE_ROTATION_3D,Animation.TYPE_POSITION_3D,Animation.TYPE_SCALE_3D]:
				var tr:=clip.add_track(type);clip.track_set_path(tr,NodePath(anim._track_base()+":"+str(sk.get_bone_name(bone))))
				for frame in range(ceili(clip.length*60)+1):
					var time:=minf(frame/60.0,clip.length);var t:=Math._smooth(time/clip.length)
					var value: Variant=(start["r"][bone] as Quaternion).slerp(end["r"][bone],t)
					if type==Animation.TYPE_POSITION_3D: value=(start["p"][bone] as Vector3).lerp(end["p"][bone],t)
					elif type==Animation.TYPE_SCALE_3D: value=(start["s"][bone] as Vector3).lerp(end["s"][bone],t)
					clip.track_insert_key(tr,time,value)
		var alias: String="__ace_"+name
		library.add_animation(alias,clip);anim.pose_overrides[name]=alias

static func cruise_ready(body) -> bool:
	return body.model_anim != null and body.model_anim.has("dash_cruise_f")

## A private cruise family keeps the authored wing/shoulder/weapon baseline.
## Only locomotion joints receive deltas; a dash alone never raises the rifle.
static func install_cruise(anim: ModelAnimator, body) -> void:
	if not supports(body.profile) or body._model_skel == null or not anim.has_cruise_hold(): return
	var sk: Skeleton3D = body._model_skel
	var root: Transform3D = body.global_transform.affine_inverse()*sk.global_transform
	var hold := anim.player.get_animation(ModelAnimator.CRUISE_HOLD_CLIP)
	if body.profile.id == SuitProfile.Id.XI_FINAL:
		# Keep every authored cruise panel channel; trim only the leg chain.
		var authored := Sample._sample(sk,hold,0.0)
		var flight := pose(sk,root,body.profile,"fly_f",0.0)
		var rest := Sample._sample(sk,null,0.0)
		var trimmed: Animation = hold.duplicate()
		var legs := ["Thigh.L","Thigh.R","Shin.L","Shin.R","Foot.L","Foot.R"]
		for track in range(trimmed.get_track_count()-1,-1,-1):
			var path := trimmed.track_get_path(track)
			if trimmed.track_get_type(track)==Animation.TYPE_ROTATION_3D and path.get_subname_count()==1 and str(path.get_subname(0)) in legs:
				trimmed.remove_track(track)
		for name in legs:
			var bone := sk.find_bone(name)
			if bone<0: continue
			var delta: Quaternion = (rest["r"][bone] as Quaternion).inverse()*(flight["r"][bone] as Quaternion)
			var rotation: Quaternion = (authored["r"][bone] as Quaternion)*Quaternion.IDENTITY.slerp(delta,.65)
			var track := trimmed.add_track(Animation.TYPE_ROTATION_3D)
			trimmed.track_set_path(track,NodePath(anim._track_base()+":"+name))
			trimmed.track_insert_key(track,0.0,rotation.normalized())
			trimmed.track_insert_key(track,trimmed.length,rotation.normalized())
		var library := anim.player.get_animation_library(ModelAnimator.DEFAULT_LIBRARY)
		library.remove_animation(ModelAnimator.CRUISE_HOLD_CLIP)
		library.add_animation(ModelAnimator.CRUISE_HOLD_CLIP,trimmed)
		hold = trimmed
	var baseline := Sample._sample(sk,hold,0.0)
	var lib := anim.player.get_animation_library(ModelAnimator.DEFAULT_LIBRARY)
	var names := ["Hips","Spine","Chest","Head","Thigh.L","Thigh.R","Shin.L","Shin.R","Foot.L","Foot.R"]
	for direction_name in body.DASH_DIR_NAMES:
		var action: String = "dash_cruise_"+direction_name
		var clip := Animation.new()
		clip.length = 0.52
		var channels: Dictionary = {}
		for bone in sk.get_bone_count():
			var tracks: Array[int] = []
			for kind in [Animation.TYPE_ROTATION_3D,Animation.TYPE_POSITION_3D,Animation.TYPE_SCALE_3D]:
				var track := clip.add_track(kind)
				clip.track_set_path(track,NodePath(anim._track_base()+":"+str(sk.get_bone_name(bone))))
				tracks.append(track)
			channels[bone] = tracks
		var first := pose(sk,root,body.profile,"dash_"+direction_name,0.0)
		for frame in range(33):
			var time := minf(frame/60.0,clip.length)
			var movement := pose(sk,root,body.profile,"dash_"+direction_name,time)
			var recovery := Math._smooth(clampf((clip.length-time)/0.16,0.0,1.0))
			for bone: int in channels:
				var rotation: Quaternion = baseline["r"][bone]
				if str(sk.get_bone_name(bone)) in names:
					var delta: Quaternion = (first["r"][bone] as Quaternion).inverse()*(movement["r"][bone] as Quaternion)
					rotation = (rotation*Quaternion.IDENTITY.slerp(delta,recovery)).normalized()
				clip.track_insert_key(channels[bone][0],time,rotation)
				clip.track_insert_key(channels[bone][1],time,baseline["p"][bone])
				clip.track_insert_key(channels[bone][2],time,baseline["s"][bone])
		lib.add_animation(action,clip)
		anim.actions[action] = true

static func cruise_owns_ancestors(body) -> bool:
	if not cruise_ready(body): return false
	var action: String = body.model_anim.current
	# The complete hold clip also owns recovery blends from the contextual shot.
	return action.begins_with("dash_cruise_") or action == "shoot" or action == str(ModelAnimator.CRUISE_HOLD_CLIP)
