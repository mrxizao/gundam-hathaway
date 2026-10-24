extends Node
## An isolated cinematic world keeps combat physics and targeting untouched.
signal finished
const Timeline:=preload("res://scripts/data/sortie_script.gd")
const Actor:=preload("res://scripts/cinematics/sortie_actor.gd")
const Stage:=preload("res://scripts/cinematics/sortie_stage.gd")
var main
var profile:SuitProfile
var night:=false
var time:=0.0
var cleaned:=false
var viewport:SubViewport
var scene:Node3D
var stage:Node3D
var actor:FlightBody
var camera:Camera3D
var layer:CanvasLayer
var title:Label
var status:Label
var fade:ColorRect
var origin:=Vector3.ZERO
var saved_units_mode:int
var saved_projectile_mode:int
var saved_camera_mode:int
var saved_hud_mode:int
var saved_hud_visible:bool
var saved_controls:bool
var paused_audio:Dictionary={}
var last_camera:=Vector3.ZERO
func setup(owner_main,force_night:Variant=null)->void:
	main=owner_main;profile=main.player.profile
	var tod:TimeOfDay=main.world.time_of_day
	night=tod!=null and tod.preset==TimeOfDay.Preset.NIGHT
	if force_night!=null:night=bool(force_night)
func _ready()->void:
	saved_units_mode=main.units_root.process_mode;saved_projectile_mode=main.projectiles.process_mode
	saved_camera_mode=main.chase.process_mode;saved_hud_mode=main.hud.process_mode
	saved_hud_visible=main.hud.visible;saved_controls=main.player.controls_enabled
	main.units_root.process_mode=Node.PROCESS_MODE_DISABLED;main.projectiles.process_mode=Node.PROCESS_MODE_DISABLED
	for sound in main.units_root.find_children("*","AudioStreamPlayer3D",true,false):
		paused_audio[sound]=sound.stream_paused;sound.stream_paused=true
	main.chase.process_mode=Node.PROCESS_MODE_DISABLED;main.hud.process_mode=Node.PROCESS_MODE_DISABLED;main.hud.hide();main.player.controls_enabled=false
	viewport=SubViewport.new();viewport.own_world_3d=true;viewport.audio_listener_enable_3d=true;viewport.size=Vector2i(main.get_viewport().get_visible_rect().size);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;viewport.positional_shadow_atlas_size=2048;add_child(viewport)
	scene=Node3D.new();viewport.add_child(scene)
	stage=_create_stage();scene.add_child(stage)
	actor=Actor.new();actor.profile=Timeline.profile(profile);scene.add_child(actor)
	if Timeline.pedal(profile):
		actor.configure_pedal(FlightPedal.kind_for_profile(actor.profile),true)
		actor.pedal.set_process(false);actor.pedal.set_physics_process(false)
	actor.animate_sortie(.01,0.0,Timeline.cruise(profile))
	if Timeline.cruise(profile):
		actor.cruise_morph=1.0;actor.penelope_cruise_enabled=true;actor._tick_cruise_morph(1.0)
		if actor.model_anim!=null and actor.model_anim.ready:actor.model_anim.hold_cruise(0.0,true);actor.model_anim.player.advance(0.0)
	if actor._form_curve!=null:actor._form_curve._process_modification()
	elif actor._cruise_form!=null:actor._cruise_form._process_modification()
	if actor._model_skel!=null:actor._model_skel.force_update_all_bone_transforms()
	var bounds:=visible_bounds(actor)
	stage.fit_transport_support(bounds)
	origin=stage.launch_point+Vector3(0,-bounds.position.y+(3 if stage.runway else 0),0)
	camera=Camera3D.new();camera.near=.2;camera.far=20000;camera.fov=58;scene.add_child(camera);camera.current=true
	layer=CanvasLayer.new();layer.layer=70;add_child(layer)
	var screen:=TextureRect.new();screen.texture=viewport.get_texture();screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);screen.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;screen.stretch_mode=TextureRect.STRETCH_SCALE;screen.mouse_filter=Control.MOUSE_FILTER_IGNORE;layer.add_child(screen)
	for top in [true,false]:
		var bar:=ColorRect.new();bar.color=Color(.005,.008,.012,.9);bar.mouse_filter=Control.MOUSE_FILTER_IGNORE;layer.add_child(bar)
		bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		if top:bar.offset_bottom=65
		else:bar.offset_top=-65
	title=Label.new();title.text=profile.display_name;title.position=Vector2(35,14);title.add_theme_font_size_override("font_size",23);layer.add_child(title)
	status=Label.new();status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT);status.position=Vector2(35,-49);status.add_theme_font_size_override("font_size",18);layer.add_child(status)
	var hint:=Label.new();hint.text=InputSetup.hint("空格 / Esc 跳过","A / B 跳过");hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT);hint.position=Vector2(-240,-47);layer.add_child(hint)
	fade=ColorRect.new();fade.color=Color.BLACK;fade.mouse_filter=Control.MOUSE_FILTER_IGNORE;fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layer.add_child(fade)
	pose(0.0)
func visible_bounds(root:Node3D)->AABB:
	var result:=AABB();var first:=true
	var cloud:Array[Vector3]=[]
	var visible_root:Node3D=root.pedal._model if root.has_pedal() else root.model_root
	var skeleton:Skeleton3D=root._model_skel
	for mesh:MeshInstance3D in visible_root.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null or not mesh.is_visible_in_tree():continue
		if mesh.skin==null or skeleton==null:
			var bounds:AABB=root.global_transform.affine_inverse()*mesh.global_transform*mesh.mesh.get_aabb()
			cloud.append_array(preload("res://scripts/flight/weapon_emitters.gd").mesh_points(root,mesh))
			result=bounds if first else result.merge(bounds);first=false
			continue
		var binds:Array[Transform3D]=[]
		for bind in mesh.skin.get_bind_count():
			var bone:int=skeleton.find_bone(mesh.skin.get_bind_name(bind)) if not str(mesh.skin.get_bind_name(bind)).is_empty() else mesh.skin.get_bind_bone(bind)
			binds.append(root.global_transform.affine_inverse()*skeleton.global_transform*skeleton.get_bone_global_pose(bone)*mesh.skin.get_bind_pose(bind))
		for surface in mesh.mesh.get_surface_count():
			var arrays:=mesh.mesh.surface_get_arrays(surface)
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES];var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
			if bones.is_empty():continue
			var stride:int=bones.size()/vertices.size()
			for index in range(0,vertices.size(),maxi(1,vertices.size()/400)):
				var point:=Vector3.ZERO
				for j in stride:
					var offset:int=index*stride+j
					if weights[offset]>.0001:point+=(binds[bones[offset]]*vertices[index])*weights[offset]
				cloud.append(point)
				result=AABB(point,Vector3.ZERO) if first else result.expand(point);first=false
	return preload("res://scripts/flight/weapon_emitters.gd").box_of(cloud) if not cloud.is_empty() else root.model_bounds
func pose(delta:float)->void:
	var sample:Dictionary=Timeline.sample(profile,time)
	stage.sample(time)
	actor.position=origin+sample["position"]
	actor.rotation.x=sample["pitch"]
	actor.rotation.y=Timeline.tow_pose(time)["yaw"] if stage.adelaide_launch and time<9.0 else 0.0
	var before:Vector3=Timeline.sample(profile,maxf(time-.01,0))["position"]
	var after:Vector3=Timeline.sample(profile,minf(time+.01,Timeline.duration(profile)))["position"]
	actor.fm.velocity=(after-before)/.02
	actor.animate_sortie(delta,sample["power"],Timeline.cruise(profile) or (profile.id==SuitProfile.Id.XI and time>=Timeline.XI_FORM_START),sample["cruise_morph"])
	var h:float=profile.target_height
	var at:=actor.position+Vector3(0,h*.16,0)
	var segment:int=sample["stage"]
	var offset:=Vector3(h*1.6,h*.65,-h*2.4)
	if segment==0 and stage.runway:offset=Vector3(minf(h*.9,38),h*.45,-minf(h*1.15,44))
	elif segment==1:offset=Vector3(h*2.1,h*.35,h*.8)
	elif segment==2:offset=Vector3(h*2.8,h*.8,h*2.4)
	if stage.adelaide_launch and time<9.0:
		at+=Basis(Vector3.UP,actor.rotation.y)*Vector3(0,0,-28)
		offset=Basis(Vector3.UP,actor.rotation.y)*Vector3(h*2.8,h*.8,h*2.4)
	elif profile.id==SuitProfile.Id.XI and segment==4:offset=Vector3(h*2.2,h*.65,h*1.4)
	elif segment==3:offset=Vector3(h*2.5,h*.65,h*1.0)
	elif segment>=4:offset=Vector3(h*.75,h*.65,h*2.8)
	# Each shot has its own framing; last shot settles behind the launch path.
	var desired:Vector3=at+offset
	camera.position=desired if delta<=0 else camera.position.lerp(desired,1.0-exp(-delta*4.0))
	camera.look_at(at,Vector3.UP)
	status.text=Timeline.version(profile,night)[segment]
	fade.color.a=maxf(1.0-time/.4,smoothstep(Timeline.duration(profile)-.35,Timeline.duration(profile),time))
func step(delta:float)->void:
	if cleaned:return
	time=minf(time+maxf(delta,0.0),Timeline.duration(profile))
	pose(delta)
	if time>=Timeline.duration(profile):finish()
func _unhandled_input(event:InputEvent)->void:
	if cleaned or time<.4:return
	var skip:bool=event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE,KEY_ESCAPE]
	skip=skip or (event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_A,JOY_BUTTON_B])
	if skip:get_viewport().set_input_as_handled();finish()
func finish()->void:
	if cleaned:return
	time=Timeline.duration(profile);pose(0.0)
	cleanup(true);finished.emit()
func cleanup(handoff:=false)->void:
	if cleaned:return
	cleaned=true
	if handoff and is_instance_valid(main.player):
		var unit:FlightBody=main.player
		if profile.id==SuitProfile.Id.ARIZEUS and unit.profile.form!=SuitProfile.ArizeusForm.CRUISE:unit.switch_form(SuitProfile.ArizeusForm.CRUISE,true,false)
		elif profile.id==SuitProfile.Id.REGZ_CUSTOM and unit.profile.form!=1:unit.switch_form(1,true,false)
		elif profile.id==SuitProfile.Id.XI:
			unit.fm.boosting=true;unit.fm.hovering=false;unit.cruise_morph=1.0;unit._tick_cruise_morph(0.0)
			unit._weld_form_bones()
		elif profile.id==SuitProfile.Id.PENELOPE:
			unit.penelope_cruise_enabled=true;unit.cruise_morph=1.0;unit._tick_cruise_morph(1.0)
		if Timeline.pedal(profile) and not unit.has_pedal():unit.configure_pedal(FlightPedal.kind_for_profile(unit.profile),true)
		# In ordinary Pacific battles, the cinematic and battle share the actual
		# southeast departure sites. Authored mission spawn points stay intact.
		if not stage.runway and main.world is WorldBuilder and Game.active_map!=null and Game.active_map.id==MapDef.Id.PACIFIC and Game.match_mode==Game.MatchMode.VERSUS:
			var fleet:Node=main.world._terrain_root.get_node_or_null("PacificFleet")
			if fleet!=null:
				var departure:Node3D=fleet.airbase if stage.runway else fleet.ships[0 if profile.id==SuitProfile.Id.XI else 1]
				unit.global_transform=departure.global_transform*actor.transform
				unit.fm.velocity=departure.global_basis*actor.fm.velocity
				main.chase.set_target(unit)
	for sound in paused_audio:
		if is_instance_valid(sound):sound.stream_paused=paused_audio[sound]
	main.units_root.process_mode=saved_units_mode;main.projectiles.process_mode=saved_projectile_mode
	main.chase.process_mode=saved_camera_mode;main.hud.process_mode=saved_hud_mode;main.hud.visible=saved_hud_visible
	if is_instance_valid(main.player):main.player.controls_enabled=saved_controls
	if is_instance_valid(layer):layer.hide()
	if is_instance_valid(viewport):viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED

## Specialized intros can reuse pause, skip and cleanup without building an airport.
func _create_stage()->Node3D:
	var result:=Stage.new()
	result.adelaide_launch=not Timeline.deck(profile);result.night=night
	result.runway=not Timeline.deck(profile);result.set_meta("xi",profile.id==SuitProfile.Id.XI)
	return result
