extends RefCounted
## Mechanical poses in degrees. Physical movement and damage remain unchanged.
static func sample(body,heavy:bool)->Dictionary:
	var speed:float=clampf(body.fm.speed/maxf(body.profile.player_top_speed(),1.0),0,1)
	var local:Vector3=body.global_basis.inverse()*body._qb_dir
	var weight:=0.0
	if body._qb_timer>0:
		var time:float=body.QB_TIME-body._qb_timer
		weight=smoothstep(0,.08,time)*(1.0-smoothstep(body.QB_TIME-.14,body.QB_TIME,time))
	local*=weight
	var trim:Vector3=body.control_input
	# Assisted WASD is translation; that path deliberately clears control_input.
	if body.translate_mode:
		var move:Vector3=body.global_basis.inverse()*body.translate_dir
		trim=Vector3(move.z,move.y,-move.x)
	var recoil:float=exp(-body._gun_recoil_clock*12.0)*sin(clampf(body._gun_recoil_clock/.13,0,1)*PI*.5)
	if not heavy and body.nu_systems!=null and body.nu_systems.bazooka_pose_left>0:
		var time:float=.5-body.nu_systems.bazooka_pose_left
		recoil=maxf(recoil,sin(clampf(time/.10,0,1)*PI*.5)*exp(-time*7.0)*1.6)
	var gain:=.78 if heavy else 1.0
	var boost:float=speed*(1.0 if body.fm.boosting else 0.0)
	var torso:=Vector3(-speed*(22 if heavy else 28)-boost*6+local.z*14-local.y*7,-local.x*10,-local.x*16)+Vector3(trim.x*6-trim.y*3,trim.z*4,trim.z*7)
	var right:=Vector3(-speed*12-boost*6-local.z*25-local.y*18+trim.x*4,speed*3,-5-speed*3-local.x*15)*gain
	var left:=Vector3(-speed*27-boost*8+local.z*14+local.y*12-trim.x*3,-speed*3,5+speed*3-local.x*9)*gain
	var shin_r:=Vector3(-speed*43-boost*9-absf(local.z)*25-maxf(local.x,0)*18,0,0)*gain
	var shin_l:=Vector3(-speed*57-boost*12-absf(local.z)*12-maxf(-local.x,0)*28,0,0)*gain
	var arm:=Vector3.ZERO
	var forearm:=Vector3.ZERO
	var shoulder:=Vector3.ZERO
	if body.saber_active() or body._saber_visual_tail>0:
		var style:Dictionary=preload("res://scripts/flight/saber_motion.gd").style(body.profile)
		var phase:Dictionary=preload("res://scripts/flight/saber_motion.gd")._phase(body._saber_visual_clock,style)
		var torso_keys:=[Vector3.ZERO,Vector3(-6,-22,-8),Vector3(2,8,4),Vector3(9,24,10),Vector3(6,18,7),Vector3.ZERO]
		var arm_keys:=[Vector3.ZERO,Vector3(65,-32,-48),Vector3(15,8,-10),Vector3(-35,30,38),Vector3(-24,22,25),Vector3.ZERO]
		var fore_keys:=[Vector3.ZERO,Vector3(35,0,-15),Vector3(-12,0,0),Vector3(-42,0,15),Vector3(-25,0,8),Vector3.ZERO]
		var axe:bool=heavy and body.sazabi_systems.axe_swing
		if axe:
			torso_keys=[Vector3.ZERO,Vector3(-10,-34,-13),Vector3(3,12,6),Vector3(14,40,16),Vector3(10,28,10),Vector3.ZERO]
			arm_keys=[Vector3.ZERO,Vector3(92,-42,-58),Vector3(18,12,-12),Vector3(-48,42,48),Vector3(-32,30,30),Vector3.ZERO]
			fore_keys=[Vector3.ZERO,Vector3(48,0,-20),Vector3(-18,0,2),Vector3(-52,0,19),Vector3(-30,0,10),Vector3.ZERO]
		elif not heavy:
			torso_keys=[Vector3.ZERO,Vector3(-8,30,10),Vector3(4,-10,-5),Vector3(12,-35,-13),Vector3(8,-24,-8),Vector3.ZERO]
			arm_keys=[Vector3.ZERO,Vector3(85,35,55),Vector3(16,-12,10),Vector3(-42,-38,-44),Vector3(-27,-25,-28),Vector3.ZERO]
			fore_keys=[Vector3.ZERO,Vector3(44,0,18),Vector3(-16,0,-2),Vector3(-48,0,-16),Vector3(-28,0,-8),Vector3.ZERO]
		# Reserve most of the strike for a fast committed acceleration after windup.
		if phase.a==1:phase.blend=pow(float(phase.blend),1.45)
		var strength:=1.0
		torso+=torso_keys[phase.a].lerp(torso_keys[phase.b],phase.blend)*strength
		arm=arm_keys[phase.a].lerp(arm_keys[phase.b],phase.blend)*strength
		forearm=fore_keys[phase.a].lerp(fore_keys[phase.b],phase.blend)
		shoulder=Vector3(arm.x*.12,arm.y*.15,arm.z*.15)
		right.x+=arm.length()*.12;left.x-=arm.length()*.09
	if heavy and body.sazabi_systems!=null:
		var systems=body.sazabi_systems
		var held:float=clampf(systems.axe_held/systems.AXE_HOLD_SECONDS,0,1) if not systems._axe_thrown else 0.0
		if held>0 and systems.slot()=="saber":
			var draw:=smoothstep(0,.65,held)
			var prepare:=smoothstep(.65,1,held)
			arm=(Vector3(90,-40,-52)*draw).lerp(Vector3(20,-5,-15),prepare)
			forearm=(Vector3(40,0,-16)*draw).lerp(Vector3(-10,0,0),prepare)
			torso+=Vector3(-7,-27,-8).lerp(Vector3(2,-5,-2),prepare)*draw
		var age:float=systems.motion.throw_age
		if age<.68:
			var release:=smoothstep(0,.13,age)
			var recover:=1.0-smoothstep(.25,.68,age)
			arm=Vector3(20,-5,-15).lerp(Vector3(-46,32,35),release)*recover
			forearm=Vector3(-10,0,0).lerp(Vector3(-45,0,10),release)*recover
			torso+=Vector3(2,-5,-2).lerp(Vector3(10,26,9),release)*recover
			right.x+=12*recover;left.x-=8*recover
		shoulder=Vector3(arm.x*.12,arm.y*.15,arm.z*.15)
	# Both suits keep the shield on the left and commit the right arm to the cut.
	if heavy:
		return {"kick":recoil,"Pelvis":torso*.18,"Torso":torso*.72+Vector3(recoil*-3,0,0),"Head":torso*-.22,
			"Thigh_R":right,"Thigh_L":left,"Shin_R":shin_r,"Shin_L":shin_l,"Foot_R":Vector3(-shin_r.x*.25,0,0),"Foot_L":Vector3(-shin_l.x*.25,0,0),
			"UpperArm_R":arm+Vector3(-speed*5,0,-speed*4),"Forearm_R":forearm,"Shoulder_R":shoulder,"Shoulder_L":Vector3(-speed*3,0,speed*4),"Skirt_R":Vector3(right.x*.28,0,-absf(local.x)*8),"Skirt_L":Vector3(left.x*.28,0,absf(local.x)*8)}
	arm.y=-arm.y;arm.z=-arm.z;forearm.z=-forearm.z
	return {"kick":recoil,"Hips":torso*.18,"Spine":torso*.22,"Chest":torso*.60+Vector3(-recoil*3,0,0),
		"Thigh.R":right,"Thigh.L":left,"Shin.R":shin_r,"Shin.L":shin_l,"Foot.R":Vector3(-shin_r.x*.25,0,0),"Foot.L":Vector3(-shin_l.x*.25,0,0),
		"UpperArm.R":arm+Vector3(12+speed*17,0,-speed*9),"LowerArm.R":forearm+Vector3(18+speed*24,0,0),"Shoulder.R":Vector3(arm.x*.12,arm.y*.15,arm.z*.15),
		"UpperArm.L":Vector3(-speed*6,0,speed*7),"LowerArm.L":Vector3(speed*12,0,0),"Shoulder.L":Vector3.ZERO,"Hand.L":Vector3.ZERO}
