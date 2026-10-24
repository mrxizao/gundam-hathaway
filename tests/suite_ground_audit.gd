extends RefCounted
static func run(t: T, host: Node) -> void:
	t.suite("Ground audit / every suit and form, 235m display and HUD warnings")
	Settings.begin_isolated();Game.reset()
	var old_map = Game.active_map;Game.active_map = null
	var previous := FlightBody.use_placeholder;FlightBody.use_placeholder = false
	for id in SuitProfile.Id.values():
		var base := SuitProfile.by_id(id)
		for form in range(maxi(base.form_count,1)):
			var unit := PlayerController.new();unit.profile = SuitProfile.by_id_form(id,form)
			unit.is_player = true;unit.controls_enabled = true;unit.assist_on = true
			host.add_child(unit);unit.set_process(false);unit.set_physics_process(false)
			for cruise in [false,true]:
				unit.cruise_morph = 1.0 if cruise else 0.0
				for alt in [235.0,235.0/FlightHUD.ALT_DISPLAY_SCALE,1000.0]:
					unit.position = Vector3(0,alt,0);unit.fm.velocity = Vector3(0,-2000,0)
					unit._collision_guard.reset()
					t.not_ok(unit._before_flight_move(1.0/60.0),"no early protection %s/%s/%s at %s" % [id,form,cruise,alt])
					t.eq(unit.fm.velocity,Vector3(0,-2000,0),"descent remains under player control")
					t.not_ok(FlightHUD.warn_state(alt,-2000.0,false,false,1.0,true)["pull_up"],"no HUD text or voice warning at steep dive")
				unit.position = Vector3(0,235.0/FlightHUD.ALT_DISPLAY_SCALE,0);unit.fm.velocity = Vector3(0,-10000,0)
				t.ok(unit._before_flight_move(0.3),"long frame crosses threshold safely")
				t.lt(unit.fm.velocity.y,0.0,"even long frames do not ascend at displayed 235m")
				unit.position += unit.fm.velocity*0.3
				t.near(unit.position.y,30.0,0.002,"crossing step ends at 30m, not explosion line")
				unit._before_flight_move(1.0/60.0)
				t.gt(unit.fm.velocity.y,0.0,"only the next boundary frame ascends")
				unit._check_ceiling();t.ok(unit.alive,"boundary protection remains alive")
			unit.free()
	FlightBody.use_placeholder = previous;Game.active_map = old_map
	Settings.end_isolated();Game.reset()

