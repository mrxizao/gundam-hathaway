extends RefCounted
static func run(t: T, host: Node) -> void:
	t.suite("XiFinal / roster, imported model, cruise and sequential charges")
	var old := FlightBody.use_placeholder
	FlightBody.use_placeholder = false
	var stage := Node3D.new()
	host.add_child(stage)
	var body := PlayerController.new()
	body.profile = SuitProfile.by_id(SuitProfile.Id.XI_FINAL)
	body.projectile_container = stage
	stage.add_child(body)
	body.set_process(false);body.set_physics_process(false)
	body.position = Vector3(0,3000,0)
	var p := body.profile
	t.eq(p.display_name,"柯西（最终决战样式）","independent roster identity")
	t.eq(p.funnel_count,300,"300 missile magazine")
	t.ok(p.is_ace(),"ace classification")
	t.ok(BattleFormation.mafty().all_suits().has(p.id),"available in Mafty roster")
	t.not_ok(body.discard_rifle(),"cannot discard rifle")
	t.eq(body.rifle_count,p.rifle_count,"discard cannot consume or hide rifle")
	t.eq(ResourceLoader.get_dependencies(p.model_path).size(),0,"portable embedded model")
	var lod_path := "res://assets/models/distant_lod/"+p.model_path.md5_text()+".res"
	t.ok(ResourceLoader.exists(lod_path),"new suit has its own distant model")
	var lod: ArrayMesh=load(lod_path)
	t.eq(lod.get_surface_count(),1,"distant model uses one surface")
	t.lt(lod.surface_get_array_len(0)/3,60000,"distant silhouette stays within triangle budget")
	var sk := body._model_skel
	t.ok(sk != null,"actual new model is rigged")
	if sk == null:
		body.free();stage.free();FlightBody.use_placeholder=old;return
	t.eq(sk.get_bone_count(),62,"independent anatomical skeleton plus 9 source cruise hinges")
	var count := 0
	for mesh in body.model_root.find_children("*","MeshInstance3D",true,false):
		if mesh.skin != null: count += 1
	t.eq(count,253,"all final battle mesh parts retained")
	for pair in [["tripo_part_28","Hand.R"],["tripo_part_191","Shin.R"],["tripo_part_24","Weapon.R"],["tripo_part_190","Thigh.R"],["tripo_part_169","UpperArm.R"],["tripo_part_117","Thigh.L"],["tripo_part_156","Shin.L"]]:
		var mesh: MeshInstance3D=body.model_root.find_child(pair[0],true,false)
		t.ok(mesh != null,"anatomical part present: "+pair[0])
		if mesh == null: continue
		var votes := {}
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
			for index in range(0,bones.size(),4):
				var name := str(mesh.skin.get_bind_name(bones[index]))
				if name.is_empty(): name=str(sk.get_bone_name(mesh.skin.get_bind_bone(bones[index])))
				if weights[index] > 0.5: votes[name]=int(votes.get(name,0))+1
		var dominant := ""
		for name in votes:
			if dominant.is_empty() or votes[name] > votes[dominant]: dominant=name
		if dominant.begins_with("Movie_Final_"):
			dominant=str(sk.get_bone_name(sk.get_bone_parent(sk.find_bone(dominant))))
		t.eq(dominant,pair[1],"actual visible mesh follows anatomical joint: "+pair[0])
	var anim := body.model_anim
	anim.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	t.ok(anim.has_cruise_hold(),"ordinary Xi cruise baseline installed")
	for action in ["shoot","slash","dash_f","dash_l","dash_cruise_f","dash_cruise_l","form_on"]:
		t.ok(anim.has(action),"action connected: "+action)
		anim.play_once(action,0.0,true);anim.player.advance(0.0);anim.player.seek(0.20,true)
		for bone in ["Hand.R","Hand.L","Wing.L","Wing.R"]:
			t.ok(sk.get_bone_global_pose(sk.find_bone(bone)).is_finite(),"finite pose: "+action+"/"+bone)
	anim.play_once("shoot",0.0,true);anim.player.advance(0.0)
	for frame in 30:
		anim.player.seek(minf(frame/60.0,0.48),true)
		var hand := sk.get_bone_global_pose(sk.find_bone("Hand.R"))
		var root := body.global_transform.affine_inverse()*sk.global_transform
		var axis := (root.basis*hand.basis*body._gun_barrel_in_hand).normalized()
		t.lt(rad_to_deg(axis.angle_to(Vector3.FORWARD)),6.0,"new rifle mesh remains aimed during recoil")
	# Inspect evaluated foot positions, rather than only differing Euler angles.
	for action in ["dash_f","dash_b","dash_l","dash_r","dash_u","dash_d","dash_cruise_f","dash_cruise_b","dash_cruise_l","dash_cruise_r"]:
		anim.play_once(action,0.0,true);anim.player.advance(0.0);anim.player.seek(.18,true)
		sk.force_update_all_bone_transforms()
		var left := (body.global_transform.affine_inverse()*sk.global_transform)*sk.get_bone_global_pose(sk.find_bone("Foot.L")).origin
		var right := (body.global_transform.affine_inverse()*sk.global_transform)*sk.get_bone_global_pose(sk.find_bone("Foot.R")).origin
		t.gt(absf(left.z-right.z),p.target_height*.035,"dash keeps feet staggered in depth: "+action)
		t.gt(left.distance_to(right),p.target_height*.15,"dash retains a stable leg spread: "+action)
		anim.play_once("shoot",0.0,true);anim.player.advance(.14)
		var aim_root := body.global_transform.affine_inverse()*sk.global_transform
		var aimed := (aim_root.basis*sk.get_bone_global_pose(sk.find_bone("Hand.R")).basis*body._gun_barrel_in_hand).normalized()
		t.lt(rad_to_deg(aimed.angle_to(Vector3.FORWARD)),6.0,"staggered dash retains rifle aim: "+action)
	anim.play_loop("fly_f",0.0,true);anim.player.advance(0.0)
	var start_left := sk.get_bone_pose_rotation(sk.find_bone("Thigh.L"))
	anim.player.seek(2.8,true)
	t.near(start_left.angle_to(sk.get_bone_pose_rotation(sk.find_bone("Thigh.L"))),0.0,.001,"flight loop closes without stepping")
	t.eq(SuitProfile.xi().full_salvo_capacity,1,"ordinary Xi keeps original single cooldown")
	anim.hold_cruise(0.0,true);anim.player.advance(0.0)
	body.cruise_morph=1.0
	body._form_weld.weld(1.0)
	sk.force_update_all_bone_transforms()
	var expected = JSON.parse_string(FileAccess.get_file_as_string("res://tests/xi_final_reference_expected.json"))
	for part in expected:
		var value: Array=expected[part]
		var target := Transform3D(Basis(Vector3(value[0],value[1],value[2]),Vector3(value[4],value[5],value[6]),Vector3(value[8],value[9],value[10])),Vector3(value[12],value[13],value[14]))
		var actual := sk.get_bone_global_pose(sk.find_bone("Movie_Final_"+part))
		t.near(actual.origin.distance_to(target.origin),0.0,0.0001,"cruise hinge reaches supplied model location: "+part)
		t.near(actual.basis.get_rotation_quaternion().angle_to(target.basis.get_rotation_quaternion()),0.0,0.001,"cruise hinge matches supplied angle: "+part)
	body._form_weld.weld(0.0)
	body.cruise_morph=0.0
	body._start_dash_spin(Vector3.LEFT)
	t.near(body._dash_spin_t,0.0,0.001,"normal left dash never spins")
	body._start_dash_spin(Vector3.RIGHT)
	t.near(body._dash_spin_t,0.0,0.001,"normal right dash never spins")
	body.cruise_morph=1.0
	body._start_dash_spin(Vector3.LEFT)
	t.gt(body._dash_spin_t,0.0,"cruise retains ordinary Xi spin")
	body._dash_spin_t=0.0
	body.cruise_morph=0.0
	var target := Node3D.new();stage.add_child(target);target.position=body.position+Vector3(0,0,-1000)
	t.eq(body.full_salvo_charges,3,"three ready charges at spawn")
	for index in 3:
		t.ok(body.fire_full_salvo(target),"stored charge fires without waiting for recharge")
		t.eq(body.funnel_count,300-(index+1)*100,"each salvo consumes 100 actual missiles")
		body._full_salvo_left=0 # Simulate completion of the existing batch emitter.
	t.eq(body.full_salvo_charges,0,"three consecutive uses exhaust charges")
	t.not_ok(body.fire_full_salvo(target),"fourth salvo is blocked")
	body._tick_full_salvo(19.99)
	t.eq(body.full_salvo_charges,0,"no early recharge")
	body._tick_full_salvo(0.01)
	t.eq(body.full_salvo_charges,1,"only first charge returns at 20 seconds")
	t.near(body.full_salvo_cooldown,20.0,0.001,"next charge starts a fresh sequential timer")
	body._tick_full_salvo(20.0)
	t.eq(body.full_salvo_charges,2,"second returns at 40 seconds")
	body._tick_full_salvo(20.0)
	t.eq(body.full_salvo_charges,3,"third returns at 60 seconds")
	t.near(body.full_salvo_cooldown,0.0,0.001,"full storage stops timer")
	body.full_salvo_charges=1;body.full_salvo_cooldown=10.0;body.funnel_reload_left=0;body.funnel_count=300
	t.ok(body.fire_full_salvo(target),"last stored charge usable while another recharges")
	t.near(body.full_salvo_cooldown,10.0,0.001,"spending another charge cannot reset active timer")
	body._full_salvo_left=0;body._tick_full_salvo(50.0)
	t.eq(body.full_salvo_charges,3,"large delta preserves serial recharge overflow")
	body.free();stage.free()
	FlightBody.use_placeholder=old
