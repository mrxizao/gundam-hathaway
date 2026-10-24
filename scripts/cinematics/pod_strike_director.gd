extends Node3D
const PS := preload("res://scripts/data/pod_strike_script.gd")
# HUD-only pilot: never registers a phantom combatant, collider or engine.
class CinematicPilot extends PlayerController:
	func _ready() -> void:
		pass
var main: Node3D
var pod: Node3D
var foe: FlightBody
var orbit_light: DirectionalLight3D
var earth: MeshInstance3D
var fire: MeshInstance3D
var fire_mat: ShaderMaterial
var trail: MeshInstance3D
var trail_mat: ShaderMaterial
var fire_bottom := -35.0
var sparks: GPUParticles3D
var beam: MeshInstance3D
var beam_core: MeshInstance3D
var charge_glow: MeshInstance3D
var charge_light: OmniLight3D
var debris: Array[MeshInstance3D] = []
var hit_played := false
var overlay: Control
var interior_black: ColorRect
var cinematic_hud: FlightHUD
var proxy: PlayerController
var layer: CanvasLayer
const ORBIT_LAYER := 1 << 19
var old_cull_mask := 1
var orbital_meshes: Dictionary = {}
var old_environment: Environment
var old_far := 0.0
var old_near := 0.0
var saved_first_person := false
const Dialogue = preload("res://scripts/data/pod_strike_dialogue.gd")
var radio_overlay: Control
var insert_video: Control
var insert_started := false
var insert_active := false
var insert_done := false
var last_time := 0.0
var cloud_anchor := Vector3.ZERO
var foe_mesh_transparency: Dictionary = {}
var cleaned := false
var saved_player_physics := true
var saved_foe_physics := true
var orbit_environment: Environment
func setup(owner_main: Node3D, body: Node3D, enemy: FlightBody) -> void:
	main=owner_main; pod=body; foe=enemy
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_PAUSABLE
	saved_first_person=Settings.first_person
	old_environment=main.chase.environment
	old_cull_mask=main.chase.cull_mask
	old_far=main.chase.far
	old_near=main.chase.near
	saved_player_physics=main.player.is_physics_processing()
	main.player.set_physics_process(false)
	if is_instance_valid(foe):
		saved_foe_physics=foe.is_physics_processing()
		foe.set_physics_process(false)
	main.hud.hide()
	main.chase.near=.1
	layer=CanvasLayer.new(); layer.layer=60; add_child(layer)
	proxy=CinematicPilot.new(); proxy.profile=foe.profile if is_instance_valid(foe) else SuitProfile.by_id(SuitProfile.Id.PENELOPE); proxy.placeholder_only=true
	proxy.controls_enabled=false; proxy.visible=false
	add_child(proxy); proxy.set_physics_process(false); proxy.set_process(false)
	proxy.max_hp=proxy.profile.hull_hp; proxy.hp=proxy.max_hp
	proxy.ifield_max=proxy.profile.ifield_hp; proxy.ifield_hp=proxy.ifield_max
	proxy.display_name=proxy.profile.display_name
	proxy.rifle_mag=proxy.profile.rifle_magazine
	if proxy._engine != null: proxy._engine.stop()
	interior_black=ColorRect.new(); interior_black.color=Color.BLACK
	interior_black.mouse_filter=Control.MOUSE_FILTER_IGNORE
	interior_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(interior_black)
	cinematic_hud=FlightHUD.new(); cinematic_hud.player=main.player; cinematic_hud.camera=main.chase
	cinematic_hud.cinematic_first_person=true
	layer.add_child(cinematic_hud)
	overlay=preload("res://scripts/cinematics/pod_strike_overlay.gd").new(); layer.add_child(overlay)
	orbit_environment=Environment.new(); orbit_environment.background_mode=Environment.BG_COLOR
	orbit_environment.background_color=Color(.001,.002,.006)
	orbit_environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	orbit_environment.ambient_light_color=Color(.20,.27,.38)
	orbit_environment.ambient_light_energy=0.55
	_build_earth(); _build_fire(); _build_beam(); _build_charge_and_debris()
	if is_instance_valid(pod):
		for mesh: MeshInstance3D in pod.find_children("*","MeshInstance3D",true,false):
			orbital_meshes[mesh]=mesh.layers
			mesh.layers=mesh.layers | ORBIT_LAYER
	if is_instance_valid(foe):
		for mesh: MeshInstance3D in foe.find_children("*","MeshInstance3D",true,false):
			foe_mesh_transparency[mesh]=mesh.transparency
	insert_video=preload("res://scripts/cinematics/pod_strike_video.gd").new()
	layer.add_child(insert_video)
	insert_video.completed.connect(_insert_finished)
	radio_overlay=preload("res://scripts/cinematics/pod_strike_radio.gd").new()
	layer.add_child(radio_overlay)
	_choose_cloud_anchor()
func _choose_cloud_anchor() -> void:
	if not is_instance_valid(foe) or main.world.cloud_bands.size()<2: return
	var time: float=(PS.T_FLYOUT+PS.T_XI_FRONT)*0.5
	var at:=PS.pod_pos(time)
	var position:=PS.foe_pos(time,at)
	var basis:=Basis.looking_at(at-position,Vector3.UP)
	var eye:=position+basis*foe.rig_anchor("head")
	var xi:=Transform3D(Basis.looking_at(Vector3(-140,120,-340),Vector3.UP),PS.escape_pos(time))
	var ideal:=PS.fly_camera(time,eye,basis,xi)
	var best:=INF
	for xf: Transform3D in main.world.cloud_bands[1]:
		if xf.origin.y<3500.0 or xf.origin.y>7500.0: continue
		var score:=ideal.distance_squared_to(xf.origin)
		if score<best:
			best=score; cloud_anchor=xf.origin
func _build_earth() -> void:
	earth=MeshInstance3D.new(); earth.name="ReentryEarth"
	var sphere:=SphereMesh.new()
	sphere.radius=WorldBuilder.SPACE_BODY_R*WorldBuilder.SPACE_EARTH_VISUAL_SCALE
	sphere.height=sphere.radius*2.0; sphere.radial_segments=384; sphere.rings=192
	earth.mesh=sphere; earth.position.y=-sphere.radius
	earth.layers=ORBIT_LAYER
	orbit_light=DirectionalLight3D.new()
	orbit_light.layers=ORBIT_LAYER; orbit_light.light_cull_mask=ORBIT_LAYER
	orbit_light.rotation_degrees=Vector3(-35,-35,0)
	orbit_light.light_color=Color(.78,.87,1.0); orbit_light.light_energy=1.0
	add_child(orbit_light)
	var mat:=ShaderMaterial.new(); mat.shader=load("res://scripts/world/earth.gdshader")
	mat.set_shader_parameter("sun_dir",Vector3(.7,.4,.5).normalized()); earth.material_override=mat
	earth.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(earth)
func _build_fire() -> void:
	fire=MeshInstance3D.new(); fire.name="ReentryFireEnvelope"
	var quad:=QuadMesh.new(); quad.size=Vector2(260,260); fire.mesh=quad
	# The heat shield is a horizontal surface beneath the large end of the pod.
	fire.rotation.x=-PI*.5
	var bounds:=AABB()
	var has_bounds:=false
	if is_instance_valid(pod):
		for child in pod.find_children("*","MeshInstance3D",true,false):
			var local_box: AABB=(pod.global_transform.affine_inverse()*child.global_transform)*child.get_aabb()
			bounds=bounds.merge(local_box) if has_bounds else local_box
			has_bounds=true
	if has_bounds:
		fire_bottom=bounds.position.y-2.0
		var diameter:=maxf(bounds.size.x,bounds.size.z)*1.45
		quad.size=Vector2(diameter,diameter)
	fire_mat=ShaderMaterial.new(); fire_mat.shader=load("res://scripts/cinematics/reentry_fire.gdshader")
	fire.material_override=fire_mat; fire.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fire)
	trail=MeshInstance3D.new(); trail.name="LongReentryTail"
	var tail_quad:=QuadMesh.new(); tail_quad.size=Vector2(320,1400); trail.mesh=tail_quad
	trail_mat=fire_mat.duplicate(); trail_mat.set_shader_parameter("trail",true)
	trail.material_override=trail_mat; trail.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(trail)
	sparks=GPUParticles3D.new(); sparks.amount=80; sparks.lifetime=1.8; sparks.visibility_aabb=AABB(Vector3(-200,-300,-200),Vector3(400,900,400))
	var pm:=ParticleProcessMaterial.new(); pm.direction=Vector3.UP; pm.spread=24
	pm.initial_velocity_min=60; pm.initial_velocity_max=160; pm.gravity=Vector3(0,20,0)
	pm.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis=Vector3.UP; pm.emission_ring_radius=62; pm.emission_ring_inner_radius=40; pm.emission_ring_height=8
	pm.scale_min=1; pm.scale_max=3; pm.color=Color(1,.6,.15)
	sparks.process_material=pm
	var spark_mesh:=SphereMesh.new(); spark_mesh.radius=.7; spark_mesh.height=1.4
	var sm:=StandardMaterial3D.new(); sm.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; sm.albedo_color=Color(1,.8,.3); sm.emission_enabled=true; sm.emission=Color(1,.4,.05)
	spark_mesh.material=sm; sparks.draw_pass_1=spark_mesh; sparks.emitting=false; add_child(sparks)
func _build_beam() -> void:
	beam=MeshInstance3D.new(); beam.name="RapidSweepBeam"
	var mesh:=CylinderMesh.new(); mesh.top_radius=3.0; mesh.bottom_radius=3.0; mesh.height=1.0
	beam.mesh=mesh
	var mat:=StandardMaterial3D.new(); mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; mat.albedo_color=Color(.95,.24,1,.75)
	mat.emission_enabled=true; mat.emission=Color(1,.2,1); mat.emission_energy_multiplier=5
	beam.material_override=mat; beam.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(beam)
	beam_core=MeshInstance3D.new(); beam_core.mesh=mesh
	var white:=mat.duplicate(); white.albedo_color=Color(1,.88,1); white.emission=Color(1,.8,1)
	beam_core.material_override=white; beam.add_child(beam_core); beam_core.scale=Vector3(.30,1,.30)
func _build_charge_and_debris() -> void:
	charge_glow=MeshInstance3D.new(); charge_glow.name="CannonCharge"
	var ball:=QuadMesh.new(); ball.size=Vector2(5,5); charge_glow.mesh=ball
	var mat:=StandardMaterial3D.new(); mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; mat.albedo_color=Color(1,.3,1,.8)
	mat.blend_mode=BaseMaterial3D.BLEND_MODE_ADD; mat.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
	var gradient:=Gradient.new()
	gradient.offsets=PackedFloat32Array([0.0,.25,.65,1.0])
	gradient.colors=PackedColorArray([Color(1,1,1,1),Color(1,1,1,.7),Color(1,1,1,.12),Color(1,1,1,0)])
	var texture:=GradientTexture2D.new(); texture.gradient=gradient; texture.width=64; texture.height=64
	texture.fill=GradientTexture2D.FILL_RADIAL; texture.fill_from=Vector2(.5,.5); texture.fill_to=Vector2(1,.5)
	mat.albedo_texture=texture
	mat.emission_enabled=true; mat.emission=Color(1,.3,1); mat.emission_energy_multiplier=4
	charge_glow.material_override=mat; charge_glow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(charge_glow)
	charge_light=OmniLight3D.new(); charge_light.light_color=Color(1,.25,1); charge_light.omni_range=65; charge_glow.add_child(charge_light)
	for i in 6:
		var shard:=MeshInstance3D.new(); shard.name="EscapeDebris"+str(i)
		var panel:=BoxMesh.new(); panel.size=Vector3(6.0+i*1.2,1.2,9.0+i)
		shard.mesh=panel
		var metal:=StandardMaterial3D.new(); metal.albedo_color=Color(.32,.35,.40); metal.metallic=.7; metal.roughness=.5
		shard.material_override=metal; shard.visible=false; add_child(shard); debris.append(shard)
func _step_charge_and_debris(t: float) -> void:
	charge_glow.visible=is_instance_valid(foe) and t>=PS.T_CHARGE and t<PS.T_FIRE
	if charge_glow.visible:
		var strength:=PS.shot_ease(t,PS.T_CHARGE,PS.T_FIRE)
		charge_glow.global_position=foe.global_transform*foe.cannon_muzzles()[0]
		charge_glow.scale=Vector3.ONE*lerpf(.2,1.8,strength)
		charge_light.light_energy=2.0*strength
	for i in debris.size():
		var shard:=debris[i]; shard.visible=t>=PS.T_ESCAPE and t<PS.T_XI_FRONT
		if not shard.visible:continue
		var dt:=t-PS.T_ESCAPE; var angle:=TAU*i/debris.size()
		var velocity:=Vector3(cos(angle)*90.0,30.0+i*8.0,sin(angle)*90.0)
		shard.global_position=PS.pod_pos(PS.T_ESCAPE)+Vector3(cos(angle)*25,0,sin(angle)*25)+velocity*dt+Vector3.DOWN*9.8*dt*dt*.5
		shard.rotation=Vector3(.3+i*.15,.4+i*.2,.5-i*.1)*dt
func skip_to_end()->void:
	if cleaned:return
	insert_active=false;insert_started=true;insert_done=true
	if is_instance_valid(insert_video):insert_video._finished()
	step(PS.TOTAL,0.0)

func advance_timeline(clock: float, delta: float) -> float:
	if insert_active:return Dialogue.INSERT_AT
	if not insert_started and clock+delta>=Dialogue.INSERT_AT:
		insert_started=true;insert_active=true
		if not insert_video.begin():_insert_finished()
		return Dialogue.INSERT_AT
	return clock+delta
func _insert_finished() -> void:
	insert_active=false;insert_done=true
func set_paused(value: bool) -> void:
	# Cinematic layers sit above the normal pause menu; reveal it during pause.
	layer.visible=not value
	insert_video.set_paused(value)
func step(t: float,delta: float) -> void:
	if not is_instance_valid(main.player): return
	last_time=t
	radio_overlay.in_video=insert_active
	radio_overlay.clock=insert_video.clock() if insert_active else t
	radio_overlay.queue_redraw()
	var player: PlayerController=main.player
	var at:=PS.pod_pos(t)
	if is_instance_valid(pod):
		pod.global_position=at; pod.rotation=Vector3(0,0,PS.tilt_rad(t))
		pod.visible=not PS.inside_pod(t)
	if is_instance_valid(main._strike_pod_tag): main._strike_pod_tag.global_position=at
	player.global_position=at if t<PS.T_ESCAPE else PS.escape_pos(t)
	player.velocity=(PS.pod_pos(t+0.005)-PS.pod_pos(t-0.005))/0.01 if t<PS.T_ESCAPE else Vector3(-140,120,-340)
	player.fm.velocity=player.velocity
	player.fm.speed=player.velocity.length()
	if t>=PS.T_ESCAPE: player.look_at(player.global_position+Vector3(-140,120,-340),Vector3.UP)
	player.model_root.visible=t>=PS.T_ESCAPE
	if is_instance_valid(foe):
		foe.global_position=PS.foe_pos(t,at); foe.look_at(at,Vector3.UP); foe.velocity=Vector3.ZERO
		foe.set_aim_direction((PS.sweep_aim(t,at)-foe.global_position).normalized())
		foe.model_root.visible=true
	_step_charge_and_debris(t)
	earth.visible=t<PS.T_ORBIT_END
	orbit_light.visible=earth.visible
	main.chase.cull_mask=ORBIT_LAYER if t<PS.T_ORBIT_END else old_cull_mask
	main.chase.environment=orbit_environment if t<PS.T_PACIFIC else old_environment
	main.chase.far=12000000.0 if t<PS.T_ORBIT_END else old_far
	main.chase.near=100.0 if t<PS.T_ORBIT_END else 0.15
	fire.global_position=pod.global_transform*Vector3(0,fire_bottom,0) if is_instance_valid(pod) else at+Vector3(0,fire_bottom,0)
	if is_instance_valid(pod): fire.global_basis=pod.global_basis*Basis(Vector3.RIGHT,-PI*.5)
	fire.visible=t>=PS.T_BURN and t<PS.T_ESCAPE_END
	fire_mat.set_shader_parameter("clock",t)
	fire_mat.set_shader_parameter("strength",lerpf(.2,1.0,PS.shot_ease(t,PS.T_BURN,PS.T_INTERCEPT)))
	trail.global_position=fire.global_position+Vector3(0,700,0); trail.visible=fire.visible
	trail_mat.set_shader_parameter("clock",t)
	trail_mat.set_shader_parameter("strength",PS.shot_ease(t,PS.T_BURN,PS.T_INTERCEPT))
	sparks.global_position=fire.global_position; sparks.emitting=fire.visible
	beam.visible=PS.beam_alive(t)
	if beam.visible and is_instance_valid(foe):
		var origin: Vector3=foe.global_transform*foe.cannon_muzzles()[0]
		var aim:=PS.sweep_aim(t,at)
		var dir:=origin.direction_to(aim)
		beam.global_position=origin+dir*6000.0
		beam.quaternion=Quaternion(Vector3.UP,dir); beam.scale=Vector3(1,12000,1)
	if t>=PS.T_HIT and not hit_played:
		hit_played=true
		Audio.play_self("boom_l",-2.0)
		Audio.play_3d("beam_rifle",at,-2.0)
	_camera(t,at)
	overlay.clock=t; overlay.blackout=PS.stage_at(t)==PS.Stage.BLACK
	overlay.impact=PS.impact_flash(t); overlay.damage=PS.cockpit_damage(t)
	overlay.black_amount=PS.transition_black(t)
	interior_black.visible=PS.inside_pod(t)
	overlay.cloud=clampf(1.0-(t-PS.T_PACIFIC)/(PS.T_REVEAL-PS.T_PACIFIC),0,1) if t>=PS.T_PACIFIC and t<PS.T_REVEAL else 0.0
	overlay.marked=t>=PS.T_ESCAPE and t<PS.T_FLYOUT and not main.chase.is_position_behind(player.global_position)
	if overlay.marked: overlay.mark=main.chase.unproject_position(player.global_position)
	overlay.queue_redraw()
func _camera(t: float,at: Vector3) -> void:
	var cam: ChaseCamera=main.chase
	cam.externally_stepped=true
	cam.first_person=false; cam._fpv_blend=0.0
	cinematic_hud.visible=false; cinematic_hud.modulate.a=1.0
	if t<PS.T_ORBIT_END:
		var k:=smoothstep(0.0,PS.T_ORBIT_END,t)
		cam.fov=lerpf(65.0,58.0,k); cam.global_position=at+Vector3(120,95,380).lerp(Vector3(170,110,430),k)
		cam.look_at(at+Vector3(0,-20000,-65000),Vector3.UP)
	elif PS.inside_pod(t):
		cinematic_hud.visible=true; cinematic_hud.player=main.player
		cam.first_person=true; cam._fpv_blend=1.0; cam.fov=68.0
		cam.global_transform=main.player.global_transform
		cam.global_position=main.player.global_transform*main.player.rig_anchor("head")
		var gain:=Settings.cam_shake_scale()*(lerpf(.20,.65,PS.shot_ease(t,PS.T_ORBIT_END,PS.T_PACIFIC)) if t<PS.T_PACIFIC else .06+1.2*exp(-(t-PS.T_XI_REACT)*1.8))
		if t>=PS.T_XI_REACT:
			cinematic_hud.modulate.a=lerpf(.55,1.0,PS.shot_ease(t,PS.T_XI_REACT,PS.T_XI_REACT+2.0))
		cam.rotate_object_local(Vector3.RIGHT,sin(t*18.0)*.016*gain)
		cam.rotate_object_local(Vector3.FORWARD,sin(t*23.0)*.020*gain)
	elif t>=PS.T_ENEMY_WIDE and is_instance_valid(foe):
		var enemy_eye: Vector3=foe.global_transform*foe.rig_anchor("head")
		var xi_look: Vector3=main.player.global_position+Vector3.UP*8.0
		proxy.global_transform=foe.global_transform; cinematic_hud.player=proxy
		if t<PS.T_ENEMY_EYE:
			var k:=PS.shot_ease(t,PS.T_ENEMY_WIDE,PS.T_ENEMY_EYE)
			var start: Vector3=foe.global_transform*Vector3(0,35,210)
			cam.global_position=start.lerp(enemy_eye,k)
			var outside_basis:=Basis.looking_at(foe.global_position+Vector3.UP*15.0-start,Vector3.UP)
			var inside_basis:=Basis.looking_at(at-enemy_eye,Vector3.UP)
			cam.global_basis=outside_basis.slerp(inside_basis,k)
			cam.fov=lerpf(58.0,45.0,k)
			cinematic_hud.visible=k>0.70; cinematic_hud.modulate.a=smoothstep(.70,1.0,k)
		elif t<PS.T_FLYOUT:
			cam.global_position=enemy_eye
			cam.look_at(at.lerp(xi_look,smoothstep(PS.T_ESCAPE,PS.T_ESCAPE+.3,t)),Vector3.UP)
			cam.fov=45.0; cinematic_hud.visible=true
		elif t<PS.T_XI_FRONT:
			cam.global_position=PS.fly_camera(t,enemy_eye,foe.global_basis,main.player.global_transform,cloud_anchor)
			cam.look_at(xi_look,Vector3.UP)
			var k:=PS.shot_ease(t,PS.T_FLYOUT,PS.T_XI_FRONT)
			cam.fov=lerpf(45.0,56.0,k)+sin(k*PI)*22.0*Settings.cam_motion_scale()
			cinematic_hud.modulate.a=1.0-smoothstep(PS.T_FLYOUT,PS.T_FLYOUT+.45,t)
			cinematic_hud.visible=cinematic_hud.modulate.a>0.001
		else:
			var k:=PS.shot_ease(t,PS.T_XI_FRONT,PS.T_ORBIT_FINISH)
			var angle:=PI*(1.0-k)
			var radius:=lerpf(110.0,cam.offset.z,k)
			var local_offset:=Vector3(sin(angle)*radius,lerpf(18.0,cam.offset.y,k),cos(angle)*radius)
			cam.global_position=main.player.global_transform*local_offset
			cam.target=main.player
			var normal_position: Vector3=cam._desired_position()-cam._target_velocity()/maxf(cam._pos_lag(),.001)
			cam.global_position=cam.global_position.lerp(normal_position,k)
			var facing:=Basis.looking_at(xi_look-cam.global_position,Vector3.UP)
			cam.global_basis=facing.slerp(cam._desired_basis(),smoothstep(.65,1.0,k))
			cam.fov=lerpf(56.0,cam.base_fov,k)
		cam.first_person=cinematic_hud.visible; cam._fpv_blend=1.0 if cam.first_person else 0.0
		foe.model_root.visible=true
		var visibility:=smoothstep(foe.profile.target_height*.65,foe.profile.target_height*1.8,cam.global_position.distance_to(enemy_eye))
		for mesh in foe_mesh_transparency:
			if is_instance_valid(mesh): mesh.transparency=lerpf(1.0,float(foe_mesh_transparency[mesh]),visibility)
	else:
		cam.fov=PS.camera_fov(t)
		cam.global_position=PS.cam_pos(t,at); cam.look_at(PS.cam_look(t,at,Vector3.ZERO),Vector3.UP)

func cleanup() -> void:
	if cleaned: return
	cleaned=true
	for mesh in foe_mesh_transparency:
		if is_instance_valid(mesh): mesh.transparency=foe_mesh_transparency[mesh]
	foe_mesh_transparency.clear()
	for mesh in orbital_meshes:
		if is_instance_valid(mesh): mesh.layers=orbital_meshes[mesh]
	orbital_meshes.clear()
	if is_instance_valid(main):
		if is_instance_valid(main.player):
			main.player.model_root.visible=true if last_time>=PS.TOTAL else not saved_first_person; main.player.set_physics_process(saved_player_physics)
		if is_instance_valid(foe): foe.model_root.visible=true; foe.set_physics_process(saved_foe_physics)
		if is_instance_valid(main.chase):
			main.chase.environment=old_environment; main.chase.far=old_far; main.chase.near=old_near
			main.chase.cull_mask=old_cull_mask
			var final_first_person:=saved_first_person
			if last_time>=PS.TOTAL:
				# This sortie hands over in third person without permanently changing preferences.
				main._strike_view_restore=Settings.first_person if Settings.first_person else null
				Settings.first_person=false
				final_first_person=false
			main.chase.first_person=final_first_person; main.chase._fpv_blend=1.0 if final_first_person else 0.0; main.chase.target=main.player
			main.chase.set_head_look_active(false); main.chase.head_look=Vector2.ZERO
		if is_instance_valid(main.hud): main.hud.show()
	if is_instance_valid(pod): pod.visible=true
func _exit_tree() -> void: cleanup()
