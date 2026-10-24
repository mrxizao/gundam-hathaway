extends Node3D
## Explicitly stepped intro; requested speed/height use the shared HUD display units.
const DISPLAY_CRUISE_KMH := 1800.0
const DISPLAY_ASCENT_M := 3000.0
const CRUISE_SPEED := DISPLAY_CRUISE_KMH / (3.6 * FlightHUD.SPEED_DISPLAY_SCALE)
const ASCENT_HEIGHT := DISPLAY_ASCENT_M / FlightHUD.ALT_DISPLAY_SCALE
const ASCENT_SECONDS := 24.0
const OPENING := ["davao_sibet_01", "davao_bridge_01", "davao_gawman_01"]
enum Shot { SEA, REVEAL, RADIO, SILENCE, ASCENT, HOTEL, PRAYER, PULLBACK, HOLD }
var main: Node3D
var shot := Shot.SEA
var time := 0.0
var total := 0.0
var radio_index := 0
var hotel := Vector3.ZERO
var origin := Vector3.ZERO
var heading := Basis.IDENTITY
var ascent_origin := Vector3.ZERO
var saved_fp := false
var saved_near := 0.1
var saved_fov := 68.0
var cleaned := false
var frozen: Dictionary = {}
var offsets: Dictionary = {}
var mesh_opacity: Dictionary = {}
var layer: CanvasLayer
var cockpit: FlightHUD
var black: ColorRect
var last_position := Vector3.ZERO
func setup(owner_main: Node3D) -> void:
	main = owner_main
func _ready() -> void:
	saved_fp = Settings.first_person
	Settings.first_person = false
	saved_near = main.chase.near
	saved_fov = main.chase.fov
	main.chase.externally_stepped = true
	main.chase.first_person = false
	main.chase._fpv_blend = 0.0
	main.chase.near = 0.15
	main.chase.set_head_look_active(false)
	main.chase.head_look = Vector2.ZERO
	var marker := get_tree().get_first_node_in_group("hotel_target")
	if is_instance_valid(marker): hotel = marker.global_position
	var radial: Vector3 = main.player.global_position - hotel
	radial.y = 0.0
	if radial.length() < 1.0: radial = Vector3(0, 0, 1)
	origin = hotel + radial.normalized() * maxf(radial.length(), 130000.0)
	origin.y = 65.0
	var forward: Vector3 = hotel - origin
	forward.y = 0.0
	heading = Basis.looking_at(forward.normalized(), Vector3.UP)
	for node in main.units_root.get_children():
		if node is FlightBody:
			frozen[node] = node.is_physics_processing()
			offsets[node] = node.global_position - main.player.global_position
			node.set_physics_process(false)
	for mesh: MeshInstance3D in main.player.find_children("*", "MeshInstance3D", true, false):
		mesh_opacity[mesh] = mesh.transparency
	main.player.controls_enabled = false
	main.hud.hide()
	main.hud.set_process(false)
	layer = CanvasLayer.new(); layer.layer = 60; add_child(layer)
	cockpit = FlightHUD.new(); cockpit.player = main.player; cockpit.camera = main.chase
	cockpit.cinematic_first_person = true
	layer.add_child(cockpit)
	cockpit.comms = main.hud.comms
	cockpit.set_process(false)
	black = ColorRect.new(); black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(black)
	last_position = origin
	_pose(0.0)
func _enter(next: int) -> void:
	shot = next; time = 0.0
	if shot == Shot.ASCENT: ascent_origin = main.player.global_position
	if shot == Shot.RADIO: _play_opening()
	if shot == Shot.PRAYER:
		main.hud.comms.push("davao_gawman_02", "为不幸卷入战火中的亡灵而祈祷")
func _play_opening() -> void:
	main.hud.comms.push(OPENING[radio_index])
	radio_index += 1
func _idle_radio() -> bool:
	return main.hud.comms.queued() == 0 and main.hud.comms.live().is_empty()
func step(delta: float) -> void:
	if cleaned: return
	cockpit.comms.tick(delta)
	cockpit.queue_redraw()
	time += delta; total += delta
	match shot:
		Shot.SEA:
			if time >= 4.5: _enter(Shot.REVEAL)
		Shot.REVEAL:
			if time >= 4.0: _enter(Shot.RADIO)
		Shot.RADIO:
			if _idle_radio():
				if radio_index < OPENING.size(): _play_opening()
				else: _enter(Shot.SILENCE)
		Shot.SILENCE:
			if time >= 3.0: _enter(Shot.ASCENT)
		Shot.ASCENT:
			if time >= ASCENT_SECONDS: _enter(Shot.HOTEL)
		Shot.HOTEL:
			if time >= 5.0: _enter(Shot.PRAYER)
		Shot.PRAYER:
			if _idle_radio(): _enter(Shot.PULLBACK)
		Shot.PULLBACK:
			if time >= 5.0: _enter(Shot.HOLD)
		Shot.HOLD:
			if time >= 3.0:
				main._finish_davao_intro()
				return
	_pose(delta)
func _pose(delta: float) -> void:
	var p: Vector3 = origin + (-heading.z) * (total * CRUISE_SPEED)
	if shot <= Shot.SILENCE: p.y = 65.0
	elif shot == Shot.ASCENT:
		p = ascent_origin + (-heading.z) * (time * CRUISE_SPEED)
		p.y = lerpf(65.0, ASCENT_HEIGHT, smoothstep(0.0, ASCENT_SECONDS, time))
	else: p.y = ASCENT_HEIGHT
	var climb_basis := heading
	if shot == Shot.ASCENT:
		climb_basis = heading * Basis(Vector3.RIGHT, deg_to_rad(25.0)*sin(PI*clampf(time/ASCENT_SECONDS,0.0,1.0)))
	# Preserve formation and actual mounted pedal models throughout ascent.
	for body in frozen:
		if is_instance_valid(body):
			body.global_position = p + offsets[body]
			body.global_basis = climb_basis
	main.player.global_position = p
	main.player.global_basis = climb_basis
	var velocity: Vector3 = (p-last_position)/delta if delta > 0.0 else -heading.z*CRUISE_SPEED
	main.player.velocity = velocity
	main.player.fm.velocity = velocity; main.player.fm.speed = velocity.length()
	last_position = p
	var eye: Vector3 = main.player.to_global(main.chase._fpv_eye_local())
	var cam: Camera3D = main.chase
	var cockpit_view: bool = shot in [Shot.RADIO, Shot.SILENCE, Shot.HOTEL, Shot.PRAYER]
	cockpit.visible = cockpit_view or (shot == Shot.PULLBACK and time < 2.0)
	cockpit.modulate.a = 1.0-smoothstep(0.0,2.0,time) if shot == Shot.PULLBACK else 1.0
	if is_instance_valid(main.player.pedal): main.player.pedal.visible = not cockpit_view
	main.player.set_model_visible(not cockpit_view)
	black.color.a = 1.0 - smoothstep(0.4, 2.0, time) if shot == Shot.SEA else 0.0
	cam.fov = 68.0
	match shot:
		Shot.SEA:
			var k := smoothstep(0.0,4.5,time)
			cam.global_position = origin + (-heading.z)*(total*CRUISE_SPEED) + Vector3.UP*lerpf(2.0,38.0,k)
			cam.global_position.y = lerpf(2.0,38.0,k)
			cam.global_basis = heading
			cam.fov = 82.0
		Shot.REVEAL:
			cam.global_position = p + heading * Vector3(lerpf(145.0,85.0,smoothstep(0.0,4.0,time)),30.0,-110.0)
			cam.look_at(p+Vector3.UP*8.0)
		Shot.RADIO, Shot.SILENCE:
			cam.global_position = eye; cam.global_basis = heading
		Shot.ASCENT:
			cam.global_position = p + heading*Vector3(145.0,30.0,15.0)
			cam.look_at(p + Vector3.UP*8.0)
		Shot.HOTEL, Shot.PRAYER:
			cam.global_position = eye
			var facing := Basis.looking_at(eye.direction_to(hotel), Vector3.UP)
			var k := smoothstep(0.0,5.0,time) if shot == Shot.HOTEL else 1.0
			# Sweep 70 degrees from cockpit to real hotel; telephoto focus at end.
			cam.global_basis = (Basis(Vector3.UP,deg_to_rad(70.0))*facing).slerp(facing,k)
			cam.fov = lerpf(68.0,18.0,k)
		Shot.PULLBACK, Shot.HOLD:
			var k := smoothstep(0.0,5.0,time) if shot == Shot.PULLBACK else 1.0
			cam.first_person = false; cam._fpv_blend = 0.0
			var target_position: Vector3 = cam._desired_position()-cam._target_velocity()/cam._pos_lag()
			cam.global_position = eye.lerp(target_position,k)
			var facing := Basis.looking_at(eye.direction_to(hotel),Vector3.UP)
			cam.global_basis = facing.slerp(cam._desired_basis(),k)
			cam.fov = lerpf(18.0,68.0,k)
	# Reveal the mounted mesh only after the camera clears the cockpit shell.
	var reveal := smoothstep(18.0,34.0,cam.global_position.distance_to(eye)) if shot == Shot.PULLBACK else 1.0
	for mesh in mesh_opacity:
		if is_instance_valid(mesh): mesh.transparency = lerpf(1.0,float(mesh_opacity[mesh]),reveal)
func skip_to_end()->void:
	if cleaned:return
	shot=Shot.HOLD;time=5.0;total=maxf(total,ASCENT_SECONDS)
	_pose(0.0)
	# Keep deduplication history, but retire the unfinished opening conversation.
	main.hud.comms._queue.clear();main.hud.comms._live.clear()

func cleanup(completed := false) -> void:
	if cleaned: return
	cleaned = true
	for mesh in mesh_opacity:
		if is_instance_valid(mesh): mesh.transparency = mesh_opacity[mesh]
	for body in frozen:
		if is_instance_valid(body): body.set_physics_process(frozen[body])
	main.player.set_model_visible(true)
	if is_instance_valid(main.player.pedal): main.player.pedal.show()
	main.chase.externally_stepped = false
	main.chase.near = saved_near; main.chase.fov = saved_fov
	main.chase.first_person = false; main.chase._fpv_blend = 0.0
	main.hud.set_process(true); main.hud.show()
	if completed:
		main._strike_view_restore = true if saved_fp else null
	else: Settings.first_person = saved_fp
	if is_instance_valid(layer): layer.hide()
