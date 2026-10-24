extends RefCounted
static func run(t:T,host:Node) -> void:
	t.suite("XiFinalTail / actual missile bay, movement, animation and launch anchors")
	var previous:=FlightBody.use_placeholder
	FlightBody.use_placeholder=false
	var stage:=Node3D.new();host.add_child(stage)
	var body:=FlightBody.new();body.profile=SuitProfile.xi_final();body.projectile_container=stage;stage.add_child(body)
	body.set_process(false);body.set_physics_process(false);body.position=Vector3(0,3000,0)
	var sk:=body._model_skel
	var motion=body._form_weld._tail_motion
	t.ok(motion!=null,"current final-battle rig installs the articulated tail")
	if motion==null:stage.free();FlightBody.use_placeholder=previous;return
	var tail:=sk.find_bone("Tail")
	t.eq(motion._tail,tail,"uses existing Tail joint")
	t.eq(str(sk.get_bone_name(sk.get_bone_parent(tail))),"Backpack","hinge remains attached to backpack")
	var position:=sk.get_bone_pose_position(tail)
	var anim:=body.model_anim
	anim.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim.hold_rest(0.0,true);anim.player.advance(0.0)
	var sample:=Vector3.ZERO
	var tail_vertices:=0
	var tail_bounds:=AABB()
	for mesh:MeshInstance3D in body.model_root.find_children("*","MeshInstance3D",true,false):
		if mesh.skin==null:continue
		for surface in mesh.mesh.get_surface_count():
			var arrays:=mesh.mesh.surface_get_arrays(surface)
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES]
			var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
			for i in vertices.size():
				var bind:=bones[i*4]
				if weights[i*4]<.99 or mesh.skin.get_bind_bone(bind)!=tail:continue
				var p:Vector3=mesh.skin.get_bind_pose(bind)*vertices[i]
				if tail_vertices==0:tail_bounds=AABB(p,Vector3.ZERO)
				else:tail_bounds=tail_bounds.expand(p)
				tail_vertices+=1
				if p.length()>sample.length():sample=p
	t.gt(tail_vertices,100000,"real missile bay geometry follows the tail bone")
	for side in [-1.0,1.0]:
		t.ok(tail_bounds.grow(.02).has_point(Vector3(side*.105,-.12,-.14)),"outlet is on missile-bay envelope")
	for form in [0.0,.5,1.0]:
		body.cruise_morph=form
		motion.tail_angles=Vector3.ZERO;motion._tail_speed=Vector3.ZERO;motion._sampled=false
		body.velocity=Vector3.ZERO;body.basis=Basis.IDENTITY;body._gun_recoil_clock=1.0
		body._form_weld.weld(form);body._form_weld.step_motion(1.0/60.0)
		var rest:=sk.get_bone_global_pose(tail)*sample
		for frame in 90:
			body.rotate_y(.025)
			body._form_weld.step_motion(1.0/60.0)
			anim.play_loop("fly_f",0.0,true);anim.player.advance(1.0/60.0)
		t.gt(motion.tail_angles.length(),.10,"turning deflects bay in normal, transition and cruise")
		t.gt((sk.get_bone_global_pose(tail)*sample).distance_to(rest),.025,"evaluated visible tail geometry moves")
		t.lt(sk.get_bone_pose_position(tail).distance_to(position),.00001,"root hinge never translates")
		var port:=body.rig_anchor("funnel_L")
		var expected:Vector3=body.global_transform.affine_inverse()*sk.global_transform*sk.get_bone_global_pose(tail)*Vector3(.105,-.12,-.14)
		t.lt(port.distance_to(expected),.001,"missile port follows evaluated moving bay")
		var q:=sk.get_bone_pose_rotation(tail)
		for repeat in 30:body._weld_form_bones()
		t.gt(absf(q.dot(sk.get_bone_pose_rotation(tail))),.99999,"frame-end writes cannot accumulate")
		for action in ["shoot","slash","dash_f","dash_cruise_l","form_on"]:
			anim.play_once(action,0.0,true);anim.player.advance(.2)
			var deflected:=sk.get_bone_global_pose(tail).basis.orthonormalized().get_rotation_quaternion()
			var saved:Vector3=motion.tail_angles
			motion.tail_angles=Vector3.ZERO;body._form_weld.weld(form)
			var neutral:=sk.get_bone_global_pose(tail).basis.orthonormalized().get_rotation_quaternion()
			var actual:Quaternion=deflected*neutral.inverse()
			t.lt(actual.angle_to(Quaternion.from_euler(saved)),.001,"combat mixer preserves global deflection: "+action)
			motion.tail_angles=saved;body._form_weld.weld(form)
		body._sync_xi_plumes()
		var nozzles:=0
		for item:Dictionary in body._plume_fx:
			if item.get("nozzle_bone",-1)!=tail:continue
			nozzles+=1
			var frame:Transform3D=body.global_transform.affine_inverse()*sk.global_transform*sk.get_bone_global_pose(tail)
			var axis:Vector3=(frame.basis*item.nozzle_axis).normalized()
			t.lt((frame*item.nozzle_point+axis*.04).distance_to(item.local_at),.001,"rear nozzle stays on moving tail")
		t.eq(nozzles,3,"all three tail nozzles remain bound")
		for frame in 180:body._form_weld.step_motion(1.0/60.0)
		t.lt(motion.tail_angles.length(),.0002,"tail smoothly returns to rest")
	var rate_results:Array[Vector3]=[]
	for fps in [30,60,120]:
		motion.tail_angles=Vector3.ZERO;motion._tail_speed=Vector3.ZERO;motion._sampled=false
		body.basis=Basis.IDENTITY;body.velocity=Vector3.ZERO
		motion.step_motion(1.0/fps)
		for frame in fps:
			body.rotate_y(1.5/fps);body.velocity+=Vector3(0,900.0/fps,0)
			motion.step_motion(1.0/fps)
			t.ok(motion.tail_angles.is_finite(),"finite at 30/60/120 FPS")
			var usage:=Vector3(motion.tail_angles.x/.56,motion.tail_angles.y/.42,motion.tail_angles.z/.16).length()
			t.lt(usage,1.05,"combined steering remains mechanically bounded")
		rate_results.append(motion.tail_angles)
	t.lt(rate_results[0].distance_to(rate_results[2]),.003,"inertia agrees across frame rates")
	body.velocity=Vector3.ZERO;body._qb_dir=Vector3.UP;body._qb_timer=body.QB_TIME*.6
	motion._sampled=false;motion.tail_angles=Vector3.ZERO;motion._tail_speed=Vector3.ZERO
	for frame in 45:motion.step_motion(1.0/60.0)
	t.gt(absf(motion.tail_angles.x),.08,"vertical dash visibly flexes tail")
	body._qb_timer=0.0;body._gun_recoil_clock=1.0
	for frame in 60:
		body.rotate_y(.025);body._tick_effects(1.0/60.0);anim.player.advance(1.0/60.0)
	t.gt(motion.tail_angles.length(),.10,"production effects and mixer pipeline animates tail")
	var target:=Node3D.new();stage.add_child(target);target.position=body.position+body.forward()*1000
	var outlets:=[body.global_transform*body.rig_anchor("funnel_L"),body.global_transform*body.rig_anchor("funnel_R")]
	var magazine:=body.funnel_count
	t.ok(body.fire_funnel(target),"moving tail can fire real missiles")
	var emitted:=0
	for child in stage.get_children():
		if child is Missile:
			emitted+=1
			t.lt(minf(child.global_position.distance_to(outlets[0]),child.global_position.distance_to(outlets[1])),.001,"actual missile spawns at moving outlet")
	t.eq(emitted,magazine-body.funnel_count,"inventory matches actual emitted missiles")
	body._qb_timer=0.0;body.alive=false
	for frame in 180:motion.step_motion(1.0/60.0)
	t.lt(motion.tail_angles.length(),.0002,"dead body cannot keep forcing the tail")
	var other:=FlightBody.new();other.profile=SuitProfile.xi();stage.add_child(other);other.set_process(false);other.set_physics_process(false)
	t.ok(other._form_weld._tail_motion==null,"ordinary Xi retains original motion")
	body._release_model_anim()
	t.not_ok(motion.attached(),"model release detaches borrowed skeleton safely")
	motion.step_motion(.016)
	stage.free();FlightBody.use_placeholder=previous
