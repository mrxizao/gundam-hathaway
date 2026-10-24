extends RefCounted
static func run(t: T,host: Node) -> void:
	t.suite("ArizeusV2 / geometry, rebound motion and form lifecycle")
	var previous := FlightBody.use_placeholder
	FlightBody.use_placeholder=false
	var stage := Node3D.new()
	host.add_child(stage)
	var body := PlayerController.new()
	body.is_player=true
	body.profile=SuitProfile.arizeus()
	body.projectile_container=stage
	stage.add_child(body)
	body.set_process(false)
	body.set_physics_process(false)
	body.position.y=3000.0
	var sk := body._model_skel
	var anim := body.model_anim
	anim.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	t.ok(body.profile.model_path.ends_with("arizeus_v2_rigged.scn"),"normal form loads the new model")
	t.eq(ResourceLoader.get_dependencies(body.profile.model_path).size(),0,"runtime scene embeds all visual resources")
	t.eq(sk.get_bone_count(),47,"compatible combat skeleton retained")
	var mesh_count := 0
	for mesh: MeshInstance3D in body.model_root.find_children("*","MeshInstance3D",true,false):
		if mesh.skin != null: mesh_count+=1
	t.eq(mesh_count,104,"all new skinned parts rendered")
	t.near(body.model_bounds.size.y,40.05,0.05,"configured overall height retained")
	t.eq(body._plume_fx.size(),8,"normal v2 has its own eight nozzle outlets")
	var nozzle := preload("res://scripts/flight/rear_nozzle_plume.gd")
	for i in body._plume_fx.size():
		var item:Dictionary=body._plume_fx[i]
		t.ok(item.has("nozzle_bone"),"normal nozzle is skeleton bound")
		var bone:int=item["nozzle_bone"]
		var point:Vector3=sk.get_bone_global_rest(bone)*item["nozzle_point"]
		t.lt(point.distance_to(nozzle.ARIZEUS_NORMAL[i][1]),.00001,"new-model nozzle centre preserved")
	var right_hand := sk.find_bone("Hand.R")
	var anchor := sk.find_bone("hand_R")
	t.eq(sk.get_bone_parent(anchor),right_hand,"saber anchor follows the actual wrist")
	var bind := sk.get_bone_global_rest(right_hand).affine_inverse()*sk.get_bone_global_rest(anchor)
	for action in ["shoot","slash","shield","dash_f","dash_b","dash_l","dash_r","dash_fl","dash_fr","dash_bl","dash_br","fly_f","fly_b","fly_l","fly_r","turn_yaw_L","turn_pitch_up"]:
		t.ok(anim.has(action),"action loaded: "+action)
		anim.play_once(action,0.0,true)
		anim.player.advance(0.0)
		for moment in [0.0,0.15,0.3,0.5]:
			anim.player.seek(moment,true)
			anim.player.advance(0.0)
			for item:Dictionary in body._plume_fx:
				nozzle.sync(body,item)
				var frame:Transform3D=body.global_transform.affine_inverse()*sk.global_transform*sk.get_bone_global_pose(item["nozzle_bone"])
				var axis:Vector3=(frame.basis*item["nozzle_axis"]).normalized()
				var expected_at:Vector3=frame*item["nozzle_point"]+axis*.04
				t.lt(item["local_at"].distance_to(expected_at),.0001,"nozzle follows animated bones during "+action)
			for bone in sk.get_bone_count():t.ok(sk.get_bone_global_pose(bone).is_finite(),"finite pose during "+action)
			var expected := sk.get_bone_global_pose(right_hand)*bind
			t.lt(expected.origin.distance_to(sk.get_bone_global_pose(anchor).origin),0.0001,"blade remains in the new palm during "+action)
	# Z uses the existing cruise model, then returns to the new normal model.
	t.ok(body.switch_form(SuitProfile.ArizeusForm.CRUISE),"normal to cruise still works")
	t.ok(body.profile.model_path.ends_with("tx_ff104_arizeus_cruise.glb"),"cruise asset remains loadable")
	t.eq(body._plume_fx.size(),16,"cruise retains its separate sixteen outlets")
	t.ok(body.switch_form(SuitProfile.ArizeusForm.NORMAL),"cruise returns to normal")
	t.ok(body.profile.model_path.ends_with("arizeus_v2_rigged.scn"),"return restores the new normal model")
	await _check_nozzle_switches(t,host,body)
	body.ifield_hp=0.0
	body._apply_damage(body.max_hp*2.0,null,Damage.Type.BEAM)
	t.ok(body.alive and body._transformed,"shell destruction still escapes to core")
	body._tick_transform(SuitProfile.TRANSFORM_COVER+0.01)
	t.eq(body.profile.form,SuitProfile.ArizeusForm.CORE_NU,"core escape form retained")
	await host.get_tree().process_frame
	stage.free()
	await host.get_tree().process_frame
	FlightBody.use_placeholder=previous

# Actual meshes and the complete form lifecycle, including the deferred-free frame.
static func _check_nozzle_switches(t:T,host:Node,body:PlayerController)->void:
	var old_body:Transform3D=body.transform
	for cycle in 3:
		for form in [SuitProfile.ArizeusForm.CRUISE,SuitProfile.ArizeusForm.NORMAL]:
			var retired:Array[Node3D]=[]
			for item:Dictionary in body._plume_fx:
				for key in ["fx","glow","boost","ab","dash"]:
					var effect:Node3D=item.get(key) as Node3D
					if is_instance_valid(effect):retired.append(effect)
			t.ok(body.switch_form(form),"repeat form switch "+str(cycle))
			for effect in retired:
				t.ok(not effect.visible,"previous form's jet hidden immediately")
				if effect is GPUParticles3D:t.ok(not effect.emitting,"previous form's particles stop immediately")
			t.eq(body._plume_fx.size(),16 if form==SuitProfile.ArizeusForm.CRUISE else 8,"correct nozzle count after each switch")
			for angles in [Vector3.ZERO,Vector3(65,120,-42),Vector3(-75,-140,78)]:
				body.rotation_degrees=angles
				body.position=Vector3(120,3000,-80)
				body.model_pivot.rotation_degrees=Vector3(angles.x*.4,-angles.y*.2,angles.z*.6)
				body.spin_pivot.rotation_degrees=Vector3(12,angles.y*.8,-8)
				body._sync_xi_plumes()
				for index in body._plume_fx.size():
					var item:Dictionary=body._plume_fx[index]
					var anchor:Node3D=item["nozzle_node"]
					t.ok(is_instance_valid(anchor) and body.model_root.is_ancestor_of(anchor),"new jet bound to current model only")
					var frame:Transform3D=anchor.global_transform
					if item["nozzle_bone"]>=0:frame=frame*anchor.get_bone_global_pose(item["nozzle_bone"])
					if form==SuitProfile.ArizeusForm.CRUISE:
						var mesh:MeshInstance3D=anchor as MeshInstance3D
						var box:AABB=mesh.mesh.get_aabb()
						var centre:Vector3=box.position+body.profile.engine_plumes[index]*box.size
						t.lt(centre.distance_to(item["nozzle_point"]),.00001,"cruise nozzle retains measured mesh-local centre")
					var world_axis:Vector3=(frame.basis*item["nozzle_axis"]).normalized()
					var at:Vector3=frame*item["nozzle_point"]+world_axis*.04
					for key in ["fx","glow","boost","ab","dash"]:
						var effect:Node3D=item.get(key) as Node3D
						if not is_instance_valid(effect):continue
						t.lt(effect.global_position.distance_to(at),.002,"jet root follows translation, pitch, yaw, roll and visual spin")
						t.gt(effect.global_basis.z.normalized().dot(world_axis),.9999,"jet axis rotates with the nozzle")
						if effect is GPUParticles3D:t.ok(effect.local_coords,"flame and smoke remain in rotating nozzle space")
			await host.get_tree().process_frame
			for effect in retired:t.ok(not is_instance_valid(effect),"old form's jet removed after deferred frame")
	body.transform=old_body
