extends RefCounted
static func run(t: T, host: Node) -> void:
	t.suite("ReGZ precision / form-specific pursuit, camera framing and release")
	Settings.begin_isolated();Settings.first_person=false;Game.reset()
	var stage:=Node3D.new();host.add_child(stage)
	var prev:=FlightBody.use_placeholder;FlightBody.use_placeholder=false
	var unit:=PlayerController.new();unit.profile=SuitProfile.regz_custom();unit.is_player=true;unit.team=0;unit.controls_enabled=true;unit.assist_on=true;stage.add_child(unit);unit.set_process(false);unit.set_physics_process(false);unit.position=Vector3(0,3000,0)
	unit.fm.velocity=Vector3.ZERO;unit.fm.speed=0
	FlightBody.use_placeholder=true
	var foe:=FlightBody.new();foe.profile=SuitProfile.gustav00();foe.team=1;stage.add_child(foe);foe.set_process(false);foe.set_physics_process(false);foe.position=unit.position+Vector3(6000,0,0)
	FlightBody.use_placeholder=false
	var locking:=LockOnSystem.new();stage.add_child(locking);locking.setup(unit);locking.select_target(foe)
	var cam:=ChaseCamera.new();stage.add_child(cam);cam.target=unit;cam.set_physics_process(false);cam.make_current();unit.setup_refs(locking,cam)
	for frame in 90:cam.step_now(1.0/60.0)
	unit.regz_weapons.held=true;unit.regz_weapons.irradiation=false
	t.eq(unit.precision_focus_target(),foe,"existing lock is followed without an extra click")
	t.eq(unit._face(),foe,"normal assisted form turns its hull toward precision lock")
	unit.translate_mode=true
	var origin := unit.position
	for frame in 60:
		unit._apply_translate(1.0/60.0)
		unit.position=origin
		cam.step_now(1.0/60.0)

	t.gt(unit.forward().dot(unit.global_position.direction_to(foe.global_position)),.95,"normal hull actually converges onto locked target")
	unit.switch_form(1);unit.regz_weapons.held=true;unit.regz_weapons.irradiation=false
	unit.global_basis=Basis.IDENTITY;unit.translate_mode=false;unit.fm.velocity=Vector3.ZERO;unit.control_input=Vector3.ZERO;unit.fm.speed=0
	var hull:=unit.global_basis
	t.eq(unit._face(),null,"cruise precision does not request hull pursuit")
	unit._tick_assist(1.0/60.0)
	t.lt(unit.control_input.length(),.001,"cruise autopilot does not steer toward scoped enemy")
	for direction in [Vector3.RIGHT,Vector3.BACK,Vector3.UP,Vector3(-1,.3,-1).normalized()]:
		foe.position=unit.position+direction*1200
		var visible_through_turn := true
		# The close shoulder rig reserves wing clearance before turning; allow the smooth transition to settle.
		var old_span := cam.global_position.distance_to(unit.global_transform*unit.model_bounds.get_center())
		var bounded_zoom := true
		for frame in 90:
			cam.step_now(1.0/60.0)
			visible_through_turn=visible_through_turn and cam.is_position_in_frustum(unit.global_position)
			var span := cam.global_position.distance_to(unit.global_transform*unit.model_bounds.get_center())
			if frame>0: bounded_zoom = bounded_zoom and absf(span-old_span)<0.5
			old_span = span
		t.ok(visible_through_turn,"camera pan keeps the hull visible throughout transition")
		t.ok(bounded_zoom,"precision transition changes distance gradually")
		var sight:=cam.global_position.direction_to(foe.global_position)
		t.gt((-cam.global_basis.z).dot(sight),.95,"camera settles onto side/rear/vertical target after smooth shoulder transition")
		t.lt(unit.global_basis.get_rotation_quaternion().angle_to(hull.get_rotation_quaternion()),.0001,"camera tracking leaves cruise hull untouched")
		t.ok(cam.is_position_in_frustum(unit.global_position),"cruise hull stays inside camera frustum")
		var full_hull := true
		for corner in 8:
			var point := unit.model_bounds.position+unit.model_bounds.size*Vector3(float(corner&1),float((corner>>1)&1),float((corner>>2)&1))
			full_hull=full_hull and cam.is_position_in_frustum(unit.global_transform*point)
		t.ok(full_hull,"entire cruise hull bounds remain inside camera")
		t.gt(cam.global_position.distance_to(unit.global_position),20.0,"orbit avoids passing through the hull")
	t.suite("ReGZ precision / lock gain and loss share the shoulder rig")
	for locked in [false,true]:
		locking.target = foe if locked else null
		unit.regz_weapons.selected = null
		var visible := true
		var clear_reticle := true
		var gradual := true
		var previous_span := cam.global_position.distance_to(unit.global_transform*unit.model_bounds.get_center())
		for frame in 120:
			cam.step_now(1.0/60.0)
			var span := cam.global_position.distance_to(unit.global_transform*unit.model_bounds.get_center())
			gradual = gradual and absf(span-previous_span)<0.5
			previous_span = span
			var box := Rect2(cam.unproject_position(unit.global_transform*unit.model_bounds.position),Vector2.ZERO)
			for corner in 8:
				var point := unit.model_bounds.position+unit.model_bounds.size*Vector3(float(corner&1),float((corner>>1)&1),float((corner>>2)&1))
				var world_point := unit.global_transform*point
				visible = visible and cam.is_position_in_frustum(world_point)
				box = box.expand(cam.unproject_position(world_point))
			clear_reticle = clear_reticle and not box.grow(8).has_point(cam.get_viewport().get_visible_rect().size*0.5)
		t.ok(visible,"lock gain/loss keeps hull visible throughout transition")
		t.ok(clear_reticle,"lock gain/loss keeps center reticle clear")
		t.ok(gradual,"lock gain/loss does not jump camera distance")
	unit.regz_weapons.cancel()
	for frame in 90:cam.step_now(1.0/60.0)
	t.near(cam._precision_blend,0.0,.001,"right release exits precision blend")
	t.lt(cam.global_position.distance_to(cam._desired_position()),.1,"right release returns to ordinary follow position")
	foe.free()
	t.eq(unit.precision_focus_target(),null,"lost target leaves no stale precision focus")
	stage.free();FlightBody.use_placeholder=prev;Settings.end_isolated()
