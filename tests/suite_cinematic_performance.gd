extends RefCounted
static func run(t:T,host:Node) -> void:
	t.suite("CinematicPerformance / shared cloud lattice and fallback")
	var lut=load("res://assets/textures/cloud_noise_lut_0.res") as Texture3D
	var lut_b=load("res://assets/textures/cloud_noise_lut_1.res") as Texture3D
	t.ok(lut!=null,"offline cloud lattice loads as a real 3D texture")
	if lut!=null:
		t.eq(lut.get_width(),192,"lattice width covers seed domain")
		t.eq(lut.get_height(),192,"lattice height covers seed domain")
		t.eq(lut.get_depth(),192,"lattice depth covers seed domain")
		t.eq(lut.get_format(),Image.FORMAT_RGBA8,"four corner expressions in each texel")
		t.not_ok(lut.has_mipmaps(),"retain cubic hash interpolation without unrelated mip blur")
		t.ok(lut_b!=null and lut_b.get_width()==192 and lut_b.get_depth()==192,"second four-corner texture has matching dimensions")
	var saved_preset:=Settings.quality_preset
	Settings.quality_preset=2
	var w:=WorldBuilder.new();w.defer_initial_map=true;host.add_child(w)
	var a:=w._make_cloud_material(Color.WHITE,Color(.7,.8,.9),.35)
	var b:=w._make_cloud_material(Color(.4,.5,.6),Color(.2,.3,.4),.35)
	t.ok(a.get_shader_parameter("noise_lut_a")==lut,"first actual cloud material binds shared resource")
	t.ok(b.get_shader_parameter("noise_lut_a")==lut,"other cloud material reuses resource, not a second allocation")
	t.ok(a.get_shader_parameter("noise_lut_b")==lut_b and b.get_shader_parameter("noise_lut_b")==lut_b,"second resource is shared across materials too")
	t.eq(a.get_shader_parameter("use_noise_lut"),true,"actual material enables lattice")
	var bare:=ShaderMaterial.new();bare.shader=load("res://shaders/cloud.gdshader")
	bare.set_shader_parameter("use_noise_lut",false)
	t.eq(bare.get_shader_parameter("use_noise_lut"),false,"standalone material can explicitly select analytic fallback")
	w.free();await host.get_tree().process_frame
	Settings.quality_preset=saved_preset

	t.suite("CinematicPerformance / real detail range hysteresis and style changes")
	var old_mode:=Settings.low_end_60
	Settings.low_end_60=false
	var body:=FlightBody.new();body.profile=SuitProfile.xi_final()
	body.model_root=Node3D.new();host.add_child(body.model_root)
	body.rig=SuitRig.new();body.model_root.add_child(body.rig)
	var parts:Array[MeshInstance3D]=[]
	for side in [.02,1.0,8.0,80.0]:
		var mesh:=MeshInstance3D.new();var cube:=BoxMesh.new();cube.size=Vector3.ONE*side;mesh.mesh=cube
		body.model_root.add_child(mesh);parts.append(mesh)
	body._apply_owner_materials()
	var ends:Array[float]=[];var margins:Array[float]=[]
	for mesh in parts:
		var range_end:=FlightBody.detail_range_end(FlightBody.part_radius_m(mesh),false)
		ends.append(range_end);margins.append(mesh.visibility_range_end_margin)
		t.near(mesh.visibility_range_end,range_end,.001,"original size-based cutoff retained")
		t.gt(mesh.visibility_range_end_margin,0.0,"nonzero hysteresis for remote detail")
		t.ok(mesh.visibility_range_end_margin<=120.0,"hysteresis bounded; not arbitrary long-range geometry retention")
		t.eq(mesh.visibility_range_fade_mode,GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED,"does not add transparent geometry passes")
	body._apply_owner_materials(false)
	for i in parts.size():
		t.near(parts[i].visibility_range_end,ends[i],.001,"material style update preserves cutoff")
		t.near(parts[i].visibility_range_end_margin,margins[i],.001,"material style update preserves hysteresis")
	t.near(FlightBody.detail_range_margin(0),0,.001,"disabled cutoff has no margin")
	var controller=load("res://scripts/flight/distant_model_lod.gd").new();body.model_root.add_child(controller)
	controller.setup(body)
	t.ok(controller.lod!=null,"existing real-model low-end silhouette still available")
	Settings.low_end_60=true;controller._apply()
	for mesh in parts:
		t.near(mesh.visibility_range_end,1200,.001,"low-end paired silhouette boundary retained")
		t.near(mesh.visibility_range_end_margin,0,.001,"low-end pair does not acquire unmatched hysteresis gap")
	Settings.low_end_60=false;controller._apply()
	for i in parts.size():
		t.near(parts[i].visibility_range_end,ends[i],.001,"switching back restores original cutoff")
		t.near(parts[i].visibility_range_end_margin,margins[i],.001,"switching back restores hysteresis")
	Settings.low_end_60=old_mode
	body.model_root.free();body.model_root=null;body.rig=null;body.free()
	await host.get_tree().process_frame

	t.suite("CinematicPerformance / magnifier restores original layers after form replacement")
	var focus=load("res://scripts/ui/magnifier_focus.gd").new()
	var target:=FlightBody.new();target.model_root=Node3D.new();host.add_child(target.model_root)
	var original:=MeshInstance3D.new();original.mesh=BoxMesh.new();original.layers=5;target.model_root.add_child(original)
	focus.sync(target)
	t.eq(original.layers,5|focus.LAYER,"magnifier target marking preserves original layers")
	var replaced_root:=target.model_root
	target.model_root=Node3D.new();host.add_child(target.model_root)
	var next:=MeshInstance3D.new();next.mesh=BoxMesh.new();next.layers=3;target.model_root.add_child(next)
	focus.sync(target)
	t.eq(original.layers,5,"changing target form restores previous model layers")
	t.eq(next.layers,3|focus.LAYER,"new target form participates in magnifier")
	focus.clear()
	t.eq(next.layers,3,"disabling magnifier restores next form layers")
	focus.clear();t.eq(focus.saved.size(),0,"repeated clear is safe")
	replaced_root.free();target.model_root.free();target.model_root=null;target.free()
	await host.get_tree().process_frame

	t.suite("CinematicPerformance / magnifier time cadence and disabled render gate")
	var original_quality:=Settings.magnifier_quality
	var fixture=load("res://tests/suite_magnifier.gd")._make_stage(host,"Day6Cadence")
	var hud:FlightHUD=fixture.hud;hud.set_process(false)
	if fixture.foe.model_root==null:
		fixture.foe.model_root=Node3D.new();fixture.foe.add_child(fixture.foe.model_root)
	var focus_geometry:=MeshInstance3D.new();focus_geometry.mesh=BoxMesh.new();fixture.foe.model_root.add_child(focus_geometry)
	t.ok(hud.magnifier_active(),"real HUD/lock/player fixture activates the magnifier")
	for quality in [0,1,2]:
		Settings.magnifier_quality=quality
		for fps in [30,60,144]:
			hud._mag_elapsed=0;hud._mag_was_active=false
			var requests:=0
			for frame in fps:
				# RenderServer consumes UPDATE_ONCE after each real rendered frame.
				hud._mag_vp.render_target_update_mode=SubViewport.UPDATE_DISABLED
				hud._tick_magnifier(1.0/float(fps))
				if hud._mag_vp.render_target_update_mode==SubViewport.UPDATE_ONCE:requests+=1
			t.near(requests,minf(float(fps),Settings.magnifier_hz()),1.0,"one second respects refresh Hz and available frames at %d FPS / quality %d"%[fps,quality])
	t.suite("CinematicPerformance / dimmed portrait suspends and recovers immediately")
	var old_fpv:=Settings.first_person;Settings.first_person=false
	hud._mag_opacity=.05;hud._mag_vp.render_target_update_mode=SubViewport.UPDATE_DISABLED
	hud._tick_magnifier(.1)
	t.ok(hud.magnifier_active(),"5% portrait remains logically active")
	t.eq(hud._mag_vp.render_target_update_mode,SubViewport.UPDATE_DISABLED,"5% portrait does not request invisible 3D renders")
	t.ok(hud._mag_render_suspended,"render suspension is recorded")
	t.eq(hud._mag_focus.saved.size(),0,"suspended render releases target-only layer scope")
	var hidden_requests:=0
	for frame in 30:
		hud._mag_vp.render_target_update_mode=SubViewport.UPDATE_DISABLED;hud._tick_magnifier(1.0/60.0)
		if hud._mag_vp.render_target_update_mode==SubViewport.UPDATE_ONCE:hidden_requests+=1
	t.eq(hidden_requests,0,"half a second while dimmed has zero refresh requests")
	hud._mag_opacity=.06;hud._tick_magnifier(1.0/144.0)
	t.eq(hud._mag_vp.render_target_update_mode,SubViewport.UPDATE_ONCE,"recovery refreshes on first frame even before normal interval")
	t.not_ok(hud._mag_render_suspended,"recovery clears suspension")
	t.gt(hud._mag_focus.saved.size(),0,"recovery rebinds current target layers")
	hud._mag_opacity=.05;hud._tick_magnifier(.1)
	Settings.first_person=true;hud._tick_magnifier(.001)
	t.eq(hud._mag_vp.render_target_update_mode,SubViewport.UPDATE_ONCE,"first-person magnifier never inherits third-person suspension")
	Settings.first_person=old_fpv
	hud.visible=false;hud._tick_magnifier(.1)
	t.eq(hud._mag_vp.render_target_update_mode,SubViewport.UPDATE_DISABLED,"hidden HUD never requests another 3D render")
	t.eq(hud._mag_focus.saved.size(),0,"hidden magnifier removes target-only layer scope")
	t.not_ok(hud._mag_render_suspended,"inactive magnifier resets suspension")
	Settings.magnifier_quality=original_quality
	fixture.stage.free();await host.get_tree().process_frame
