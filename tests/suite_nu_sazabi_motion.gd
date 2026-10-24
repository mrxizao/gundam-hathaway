extends RefCounted
static func run(t:T,host:Node)->void:
	Settings.begin_isolated();Game.reset()
	var old:=FlightBody.use_placeholder;FlightBody.use_placeholder=false
	var stage:=Node3D.new();host.add_child(stage)
	for profile in [SuitProfile.nu_gundam(),SuitProfile.sazabi()]:
		t.suite(profile.display_name+" / articulated combat motion and leg exhaust")
		var p:=PlayerController.new();p.profile=profile;p.is_player=true;stage.add_child(p)
		p.set_physics_process(false);p.set_process(false)
		var heavy:bool=profile.id==SuitProfile.Id.SAZABI
		var m=p.sazabi_systems.motion if heavy else p.nu_motion
		var count:=4 if heavy else 6
		t.eq(p._plume_fx.size(),count,"new lower-leg/sole outlets retain existing engines")
		p.fm.speed=0;p.fm.boosting=false
		var idle:Dictionary=preload("res://scripts/flight/nu_sazabi_pose.gd").sample(p,heavy)
		p.fm.speed=profile.player_top_speed()*.8
		var flight:Dictionary=preload("res://scripts/flight/nu_sazabi_pose.gd").sample(p,heavy)
		var torso:String="Torso" if heavy else "Chest"
		t.gt((idle[torso] as Vector3).distance_to(flight[torso]),3,"forward flight inclines the torso")
		p.fm.boosting=true
		var boost:Dictionary=preload("res://scripts/flight/nu_sazabi_pose.gd").sample(p,heavy)
		t.gt((flight[torso] as Vector3).distance_to(boost[torso]),2,"super acceleration adds a committed flight posture")
		p.control_input.z=.7
		var turn:Dictionary=preload("res://scripts/flight/nu_sazabi_pose.gd").sample(p,heavy)
		t.gt(absf((turn[torso] as Vector3).z),2,"flight responds to steering")
		p.fm.speed=0;p.fm.boosting=false;p.control_input=Vector3.ZERO
		p.translate_mode=true
		for direction in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT,Vector3.UP,Vector3.DOWN]:
			p.translate_dir=p.global_basis*direction
			var response:Dictionary=preload("res://scripts/flight/nu_sazabi_pose.gd").sample(p,heavy)
			t.gt((response[torso] as Vector3).length(),1,"assisted translation produces body response "+str(direction))
		p.translate_mode=false;p.translate_dir=Vector3.ZERO
		if not heavy:
			m.rotation_cache.clear();m.rotate_bone(p._model_skel,"Chest",Vector3.ZERO)
			m.rotate_bone(p._model_skel,"Chest",Vector3(30,0,0))
			var blended:float=rad_to_deg((m.rotation_cache.Chest as Quaternion).get_euler().x)
			t.gt(blended,0,"Nu starts moving towards the new pose")
			t.lt(blended,30,"Nu cannot snap to a new flight/dash pose in one frame")
		else:
			p.weapon_index=2;p.sazabi_systems.axe_held=.4;p.sazabi_systems._axe_thrown=false
			var wind:Dictionary=preload("res://scripts/flight/nu_sazabi_pose.gd").sample(p,true)
			m.throw_age=.13;p.sazabi_systems._axe_thrown=true
			var release:Dictionary=preload("res://scripts/flight/nu_sazabi_pose.gd").sample(p,true)
			t.gt((wind.UpperArm_R as Vector3).distance_to(release.UpperArm_R),80,"throw changes from rear windup to forward extension")
			m.throw_age=1;p.sazabi_systems.axe_held=0;p.weapon_index=0
			var recover:Dictionary=preload("res://scripts/flight/nu_sazabi_pose.gd").sample(p,true)
			t.lt((recover.UpperArm_R as Vector3).length(),1,"throw returns to neutral after follow-through")
		var samples:Array=[]
		for direction in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT,Vector3.UP,Vector3.DOWN,Vector3(-1,0,-1).normalized(),Vector3(1,0,1).normalized()]:
			p._qb_timer=p.QB_TIME-.14;p._qb_dir=direction
			if heavy:m.step(0)
			else:m._process_modification()
			var r:Transform3D=m.joints.Thigh_R.transform if heavy else m.final_poses["Thigh.R"]
			var l:Transform3D=m.joints.Thigh_L.transform if heavy else m.final_poses["Thigh.L"]
			t.gt(r.basis.get_rotation_quaternion().angle_to(l.basis.get_rotation_quaternion()),.02,"dash keeps asymmetric legs: "+str(direction))
			for prior in samples:t.gt(r.basis.get_rotation_quaternion().angle_to(prior),.001,"direction produces distinct right-leg response")
			samples.append(r.basis.get_rotation_quaternion())
		p._qb_timer=0;p._gun_recoil_clock=.07
		if heavy:m.step(0)
		else:p.weapon_index=0;m._process_modification()
		var firing:Transform3D=m.joints.UpperArm_R.transform if heavy else p._model_skel.get_bone_global_pose(p._model_skel.find_bone("UpperArm.R"))
		p._gun_recoil_clock=2
		if heavy:m.step(0)
		else:m._process_modification()
		var ready:Transform3D=m.joints.UpperArm_R.transform if heavy else p._model_skel.get_bone_global_pose(p._model_skel.find_bone("UpperArm.R"))
		t.gt(firing.basis.get_rotation_quaternion().angle_to(ready.basis.get_rotation_quaternion()),.001,"gunshot has arm recoil")
		p.saber_state=p.SaberState.CHARGE;p._saber_visual_clock=.20
		if heavy:m.step(0)
		else:m._process_modification()
		var windup:Transform3D=m.joints.UpperArm_R.transform if heavy else m.final_poses["UpperArm.R"]
		p._saber_visual_clock=.50
		if heavy:m.step(0)
		else:m._process_modification()
		var cut:Transform3D=m.joints.UpperArm_R.transform if heavy else m.final_poses["UpperArm.R"]
		t.gt(windup.basis.get_rotation_quaternion().angle_to(cut.basis.get_rotation_quaternion()),.5,"saber moves through windup and follow-through")
		if not heavy:
			p._show_blade();m._process_modification()
			var palm:Vector3=(p._model_skel.global_transform*p._model_skel.get_bone_global_pose(p._model_skel.find_bone("Hand.R"))).origin
			t.lt(p._blade_anchor.global_position.distance_to(palm),.001,"Nu saber follows the final right-hand pose")
		p.saber_state=p.SaberState.IDLE
		if heavy:
			p.sazabi_systems.scoped=true;p.aim_dir=Vector3(.3,.15,-1).normalized();m.step(0)
			t.gt(m.shotgun.global_basis.z.normalized().dot(p.aim_dir),.999,"scoped gun follows aim through torso motion")
			t.lt((m.shotgun.global_transform*Vector3(0,-.13,-.20)).distance_to(m.joints.Hand_R.global_position),.001,"aim correction preserves palm grip")
			p.sazabi_systems.scoped=false
		var fx:Dictionary=p._plume_fx[count-1]
		var at:Vector3=fx.local_at
		if heavy:m.pose("Shin_L",Vector3(.5,0,0),0)
		else:p._model_skel.set_bone_pose_rotation(p._model_skel.find_bone("Foot.L"),Quaternion(Vector3.RIGHT,.5))
		p._sync_xi_plumes()
		t.gt(at.distance_to(fx.local_at),.15,"new nozzle follows the moving leg")
		t.eq(fx.nozzle_node,m.joints.Shin_L if heavy else p._model_skel,"outlet is attached to actual rig")
		if not heavy:
			t.eq(fx.nozzle_bone,p._model_skel.find_bone("Foot.L"),"sole emitter binds to foot bone")
			p.weapon_index=2;p.nu_systems.bazooka_pose_left=.43
			var pose:Dictionary=preload("res://scripts/flight/nu_sazabi_pose.gd").sample(p,false)
			t.gt(pose.kick,.5,"bazooka firing produces stronger independent recoil")
		p.free()
	stage.free();await host.get_tree().process_frame
	FlightBody.use_placeholder=old;Settings.end_isolated();Game.reset()
