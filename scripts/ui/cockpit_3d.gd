extends Control
## Camera-space instruments: isolated world, stable orthographic projection.
var messer: Control
var panorama: Control
var hud: Control
var view: SubViewport
var surface_view: SubViewport
var surface: Control
var camera_3d: Camera3D
var model: Node3D
var last_size := Vector2.ZERO
var last_family := -1
var surfaces: Array[ShaderMaterial] = []
const INSTRUMENT_HZ := 30.0
var _redraw_left := 0.0
var _shell_roll := 0.0
const SHELL_BANK_LIMIT := deg_to_rad(3.0)
var texture_rect: TextureRect
var _gp03_hud_material: ShaderMaterial
var _saved_hud_material: Material
var _gp03_tint_active := false

func setup(source: Control) -> void:
	hud = source
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panorama = load("res://scripts/ui/cockpit_panorama.gd").new()
	add_child(panorama)
	view = SubViewport.new()
	view.transparent_bg = true
	view.gui_disable_input = true
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_2X
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(view)
	surface_view = SubViewport.new()
	surface_view.transparent_bg = true
	surface_view.gui_disable_input = true
	surface_view.disable_3d = true
	surface_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(surface_view)
	surface = load("res://scripts/ui/zorin_cockpit_surface.gd").new()
	surface_view.add_child(surface)
	camera_3d = Camera3D.new()
	camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera_3d.position.z = 1000
	camera_3d.near = 1
	camera_3d.far = 2000
	view.add_child(camera_3d)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25,-30,0)
	light.light_energy = 1.4
	view.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55,0.59,0.75)
	environment.environment.ambient_light_energy = 0.65
	view.add_child(environment)
	texture_rect = TextureRect.new()
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.texture = view.get_texture()
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(texture_rect)
	messer = preload("res://scripts/ui/messer_cockpit.gd").new()
	add_child(messer)
	messer.hide()
	set_process(true)

func _process(delta: float) -> void:
	var enabled: bool = Game.phase in [Game.Phase.INTRO,Game.Phase.FIGHT] and hud.visible and hud.first_person_view() and not hud.cockpit_only and is_instance_valid(hud.player) and hud.can_draw()
	if enabled:
		enabled = hud.player.profile.id in [SuitProfile.Id.FULL_ARMOR_TB,SuitProfile.Id.PSYCHO_ZAKU_TB,SuitProfile.Id.XI,SuitProfile.Id.XI_FINAL,SuitProfile.Id.REGZ_CUSTOM,SuitProfile.Id.PENELOPE,SuitProfile.Id.ARIZEUS,SuitProfile.Id.GP03D,SuitProfile.Id.NEUE_ZIEL,SuitProfile.Id.GP03S,SuitProfile.Id.NU_GUNDAM,SuitProfile.Id.SAZABI,SuitProfile.Id.ZORIN_SOUL,SuitProfile.Id.MESSER_M01,SuitProfile.Id.MESSER_CMD,SuitProfile.Id.MESSER_F01]
	_sync_gp03_ink(enabled and hud.player.profile.id in [SuitProfile.Id.GP03D,SuitProfile.Id.NU_GUNDAM,SuitProfile.Id.SAZABI])
	visible = enabled
	# World-space combat cues and readouts must remain above the solid cockpit.
	z_index = -1 if enabled and hud.player.profile.id == SuitProfile.Id.NEUE_ZIEL else 0
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	surface_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var use_messer: bool = enabled and preload("res://scripts/ui/messer_cockpit.gd").supports(hud.player.profile.id)
	messer.sync(hud,use_messer,delta)
	texture_rect.visible = not use_messer
	if use_messer:
		z_index = -1
		panorama.sync(hud,false)
		return
	# Camera-space cabin stays level; real attitude is retained by world rails and HUD.
	var target_roll := shell_roll_target(hud.player.global_basis,Settings.cam_motion_scale()) if enabled else 0.0
	_shell_roll = lerpf(_shell_roll,target_roll,1.0-exp(-4.5*maxf(delta,0.0)))
	panorama.sync(hud,enabled and cockpit_family(hud.player.profile.id) not in [2,5,6],_shell_roll)
	if not enabled:
		_redraw_left = 0.0
		return
	var family := cockpit_family(hud.player.profile.id)
	if last_size != hud.size or family != last_family:
		last_size = hud.size
		last_family = family
		_rebuild()
		_redraw_left = 0.0
	model.rotation.z = _shell_roll
	_redraw_left -= delta
	if _redraw_left > 0.0: return
	_redraw_left = 1.0/(12.0 if family == 2 else INSTRUMENT_HZ)
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	surface_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	for key in ["player","lock","camera","cockpit_basis","cockpit_readout"]:
		surface.set(key,hud.get(key))
	surface.queue_redraw()

func _sync_gp03_ink(enabled: bool) -> void:
	if enabled and not _gp03_tint_active:
		_saved_hud_material = hud.material
		if _gp03_hud_material == null:
			_gp03_hud_material = ShaderMaterial.new()
			_gp03_hud_material.shader = preload("res://shaders/gp03_hud_ink.gdshader")
		hud.material = _gp03_hud_material
		_gp03_tint_active = true
	elif not enabled and _gp03_tint_active:
		if hud.material == _gp03_hud_material: hud.material = _saved_hud_material
		_saved_hud_material = null
		_gp03_tint_active = false

func _exit_tree() -> void:
	if is_instance_valid(hud): _sync_gp03_ink(false)

func _rebuild() -> void:
	for overlay in texture_rect.get_children():
		texture_rect.remove_child(overlay)
		overlay.queue_free()
	view.size = Vector2i(last_size)
	surface_view.size = view.size
	surface.size = last_size
	texture_rect.size = last_size
	# KEEP_HEIGHT makes size the vertical span, independent of gameplay FOV.
	camera_3d.keep_aspect = Camera3D.KEEP_HEIGHT
	camera_3d.size = last_size.y
	if is_instance_valid(model):
		view.remove_child(model)
		model.queue_free()
	model = Node3D.new()
	view.add_child(model)
	surfaces.clear()
	if last_family == 6:
		preload("res://scripts/ui/psycho_zaku_cockpit.gd").build(self)
		return
	if last_family == 5:
		preload("res://scripts/ui/full_armor_cockpit.gd").build(self)
		return
	var modules := neue_instrument_layout(last_size) if last_family == 2 else instrument_layout(last_size)
	surface.modules = modules
	for key in ["center","left","right"]:
		var rect: Rect2 = modules[key]
		if rect.size.x < 8: continue
		if last_family == 2:
			_neue_shaped_panel(rect,key)
			continue
		var first_part := model.get_child_count()
		var frame := rect.grow(5 if last_family == 0 else 8)
		_shell(frame, 9 if last_family == 0 else 14, 0)
		_shell(rect.grow(2), 4, 7)
		_screen(rect,12)
		_bezel(rect,key == "center")
		# Lower stand and corner fasteners are real depth geometry.
		_box(Rect2(rect.get_center().x-7,rect.end.y,14,12),14,-4,Color(0.08,0.09,0.12))
		for x in [frame.position.x+5,frame.end.x-5]:
			for y in [frame.position.y+5,frame.end.y-5]:
				_box(Rect2(x-2,y-2,4,4),2,11,Color(0.19,0.2,0.25))
		# Visible lower mounting cradle, separate from the display housing.
		_box(Rect2(rect.get_center().x-23,rect.end.y+4,46,5),17,3,Color(0.045,0.052,0.065))
		if key == "center":
			_box(Rect2(rect.get_center().x-28,rect.position.y-5,56,3),3,20,Color(0.022,0.025,0.035))
		# Rotate the complete assembly, including glass, lip, screws and cradle.
		var parts := model.get_children().slice(first_part)
		var panel := Node3D.new()
		panel.name = "Panel_"+key
		panel.position = Vector3(rect.get_center().x-last_size.x/2,last_size.y/2-rect.get_center().y,0)
		model.add_child(panel)
		for part: Node3D in parts: part.reparent(panel,true)
		if key != "center":
			panel.rotation_degrees.y = (12.0 if key == "left" else -12.0) if last_family == 3 else (7.0 if key == "left" else -7.0)
	if last_family == 3:
		preload("res://scripts/ui/gp03_cockpit_details.gd").build(self, modules)
	elif last_family == 2:
		preload("res://scripts/ui/neue_cockpit_shell.gd").new().build(self)
		var side_marks := preload("res://scripts/ui/neue_side_screen_marks.gd").new()
		side_marks.size = last_size
		texture_rect.add_child(side_marks)
		_neue_console()

func _neue_console() -> void:
	var k := minf(last_size.x/1280.0,last_size.y/720.0)
	var cx := last_size.x*0.5
	var top := last_size.y*0.64
	# The console follows the floor wedge below the four displays and shaped instruments.
	for side: float in [-1.0,1.0]:
		var points := PackedVector2Array()
		for p: Vector2 in [Vector2(510,177),Vector2(290,104),Vector2(130,157),Vector2(150,247),Vector2(470,247),Vector2(540,214)]:
			points.append(Vector2(cx+side*p.x*k,top+p.y*k))
		_neue_console_plate(points,-16,Color(0.17,0.20,0.15))
		var x := cx+side*320*k
		# Two staggered banks of pale keys and recessed warning switches.
		for row in 3:
			for n in 9:
				var px := x+side*(-58+n*16)*k
				var py := top+(153+row*13+n*2)*k
				_box(Rect2(px-7*k,py-3*k,14*k,7*k),4,1,Color(0.65,0.61,0.46) if n%4 else Color(0.76,0.40,0.13))
		# Auxiliary teal monitor and its recessed housing.
		var aux_x := cx+side*420*k
		_box(Rect2(aux_x-28*k,top+190*k,56*k,31*k),9,0,Color(0.035,0.045,0.035))
		_box(Rect2(aux_x-23*k,top+195*k,46*k,21*k),2,6,Color(0.07,0.29,0.27))
		for n in 4:
			_box(Rect2(aux_x+(-19+n*12)*k,top+220*k,7*k,4*k),3,7,Color(0.57,0.58,0.42))
		# Circular knobs have raised hubs and a slot rather than drawn flat circles.
		for n in 3:
			var knob := Vector2(cx+side*(214+n*34)*k,top+218*k)
			_neue_console_knob(knob,10*k,k)
		# Reserve a separate inner bay for each stick; the nearest knob is 56 units away.
		var grip := Vector2(cx+side*158*k,top+177*k)
		_neue_console_knob(grip+Vector2(0,37*k),15*k,k)
		_box(Rect2(grip.x-4*k,grip.y+12*k,8*k,24*k),12,20,Color(0.29,0.31,0.23))
		_box(Rect2(grip.x-10*k,grip.y-8*k,20*k,27*k),20,27,Color(0.105,0.12,0.09))
		_box(Rect2(grip.x-6*k,grip.y-8*k,12*k,5*k),3,39,Color(0.69,0.40,0.12))
	# Recessed tape transport; bezel, reels and controls remain below the sightline.
	_box(Rect2(cx-88*k,top+145*k,176*k,17*k),8,1,Color(0.52,0.49,0.37))
	_box(Rect2(cx-66*k,top+147*k,132*k,12*k),2,7,Color(0.025,0.032,0.028))
	for side: float in [-1.0,1.0]:
		_neue_console_knob(Vector2(cx+side*40*k,top+153*k),5*k,k)
		for stripe in 3:
			_box(Rect2(cx+side*300*k,top+(123+stripe*4)*k,68*k,3*k),1,2,[Color(0.88,0.61,0.23),Color(0.74,0.35,0.12),Color(0.40,0.20,0.12)][stripe])
	# Central lower keyboard sits beneath, and clear of, the trapezoidal display.
	_box(Rect2(cx-103*k,top+166*k,206*k,61*k),15,-6,Color(0.12,0.15,0.11))
	for row in 3:
		for n in 12:
			_box(Rect2(cx+(-94+n*16)*k,top+(174+row*13)*k,11*k,7*k),3,6,Color(0.39,0.43,0.31))


func _neue_console_plate(points: PackedVector2Array, z: float, color: Color) -> void:
	var indices := Geometry2D.triangulate_polygon(points)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in indices:
		var p := points[index]
		st.add_vertex(Vector3(p.x-last_size.x/2,last_size.y/2-p.y,z))
	for i in points.size():
		var a := points[i]
		var b := points[(i+1)%points.size()]
		for p: Vector3 in [Vector3(a.x,a.y,z),Vector3(b.x,b.y,z),Vector3(a.x,a.y,z-15),Vector3(a.x,a.y,z-15),Vector3(b.x,b.y,z),Vector3(b.x,b.y,z-15)]:
			st.add_vertex(Vector3(p.x-last_size.x/2,last_size.y/2-p.y,p.z))
	st.generate_normals()
	var instance := MeshInstance3D.new()
	instance.name = "NeueLowerConsole%d" % model.get_child_count()
	instance.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.72
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = mat
	model.add_child(instance)


func _neue_console_knob(point: Vector2, radius: float, k: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius*0.82
	mesh.bottom_radius = radius
	mesh.height = 7*k
	mesh.radial_segments = 16
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.29,0.32,0.24)
	mat.roughness = 0.7
	mesh.material = mat
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = Vector3(point.x-last_size.x/2,last_size.y/2-point.y,8)
	instance.rotation_degrees.x = 90
	model.add_child(instance)
	_box(Rect2(point.x-radius*0.6,point.y-1.5*k,radius*1.2,3*k),2,13,Color(0.045,0.055,0.035))


func _bezel(rect: Rect2, notched: bool) -> void:
	var border := 9.0 if last_family == 0 else 13.0
	var outer := rect.grow(border)
	# Matching contour vertices form a real open frame, not a solid plate.
	var contour := [Vector2(0.03,0),Vector2(0.39,0),Vector2(0.39,0),Vector2(0.61,0),Vector2(0.61,0),Vector2(0.97,0),Vector2(1,0.03),Vector2(1,0.97),Vector2(0.97,1),Vector2(0.03,1),Vector2(0,0.97),Vector2(0,0.03)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in contour.size():
		var next := (i+1)%contour.size()
		var a: Vector2 = outer.position+contour[i]*outer.size
		var b: Vector2 = outer.position+contour[next]*outer.size
		if notched:
			if i in [2,3]: a.y += border*0.7
			if next in [2,3]: b.y += border*0.7
		var c: Vector2 = rect.position+contour[i]*rect.size
		var d: Vector2 = rect.position+contour[next]*rect.size
		# Front lip slopes inward toward the recessed glass.
		for tri in [[Vector3(a.x,a.y,23),Vector3(b.x,b.y,23),Vector3(c.x,c.y,14)],[Vector3(c.x,c.y,14),Vector3(b.x,b.y,23),Vector3(d.x,d.y,14)],[Vector3(a.x,a.y,4),Vector3(b.x,b.y,23),Vector3(a.x,a.y,23)],[Vector3(a.x,a.y,4),Vector3(b.x,b.y,4),Vector3(b.x,b.y,23)]]:
			for p: Vector3 in tri: st.add_vertex(Vector3(p.x-last_size.x/2,last_size.y/2-p.y,p.z))
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "RecessedBezel%d" % model.get_child_count()
	mesh.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32,0.35,0.39) if last_family == 3 else Color(0.085,0.105,0.105)
	mat.metallic = 0.25
	mat.roughness = 0.58
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	model.add_child(mesh)

static func cockpit_family(suit_id: int) -> int:
	if suit_id == SuitProfile.Id.PSYCHO_ZAKU_TB: return 6
	if suit_id == SuitProfile.Id.FULL_ARMOR_TB: return 5
	if preload("res://scripts/ui/messer_cockpit.gd").supports(suit_id): return 4
	if suit_id in [SuitProfile.Id.GP03D,SuitProfile.Id.NU_GUNDAM,SuitProfile.Id.SAZABI]: return 3
	if suit_id == SuitProfile.Id.NEUE_ZIEL: return 2
	return 0 if suit_id in [SuitProfile.Id.XI,SuitProfile.Id.XI_FINAL,SuitProfile.Id.ZORIN_SOUL] else 1

static func instrument_layout(view_size: Vector2) -> Dictionary:
	var scale := minf(1.0,view_size.x/1280.0)
	var w := 360.0*scale
	var h := 280.0*scale
	var side_w := 190.0*scale
	var side_h := 176.0*scale
	var bottom := view_size.y-14
	var cx := view_size.x*0.5
	return {"center":Rect2(cx-w/2,bottom-h,w,h),"left":Rect2(cx-w/2-side_w-32,bottom-side_h,side_w,side_h),"right":Rect2(cx+w/2+32,bottom-side_h,side_w,side_h)}

func _box(rect: Rect2, depth: float, z: float, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(rect.size.x,rect.size.y,depth)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.62
	material.metallic = 0.3
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = Vector3(rect.get_center().x-last_size.x/2,last_size.y/2-rect.get_center().y,z)
	model.add_child(instance)

func _shell(rect: Rect2, depth: float, z: float) -> void:
	# Bevelled octagonal slab, including separate front bevel and side faces.
	var b := minf(9,rect.size.x/8)
	var points := PackedVector2Array([Vector2(b,0),Vector2(rect.size.x-b,0),Vector2(rect.size.x,b),Vector2(rect.size.x,rect.size.y-b),Vector2(rect.size.x-b,rect.size.y),Vector2(b,rect.size.y),Vector2(0,rect.size.y-b),Vector2(0,b)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := rect.get_center()
	for i in 8:
		var a := rect.position+points[i]
		var c := rect.position+points[(i+1)%8]
		var ai := center+(a-center)*0.98
		var ci := center+(c-center)*0.98
		for triangle in [[Vector3(center.x,center.y,z+depth/2),Vector3(ci.x,ci.y,z+depth/2),Vector3(ai.x,ai.y,z+depth/2)],[Vector3(a.x,a.y,z),Vector3(ci.x,ci.y,z+depth/2),Vector3(c.x,c.y,z)],[Vector3(a.x,a.y,z),Vector3(ai.x,ai.y,z+depth/2),Vector3(ci.x,ci.y,z+depth/2)],[Vector3(a.x,a.y,z-depth),Vector3(a.x,a.y,z),Vector3(c.x,c.y,z)],[Vector3(a.x,a.y,z-depth),Vector3(c.x,c.y,z),Vector3(c.x,c.y,z-depth)]]:
			for p: Vector3 in triangle:
				st.add_vertex(Vector3(p.x-last_size.x/2,last_size.y/2-p.y,p.z))
	st.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.57,0.59,0.62) if last_family == 3 else (Color(0.05,0.065,0.07) if last_family == 0 else Color(0.065,0.08,0.08))
	material.roughness = 0.7
	material.metallic = 0.25
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = material
	model.add_child(instance)

func _screen(rect: Rect2,z: float) -> void:
	var quad := QuadMesh.new()
	quad.size = rect.size
	var instance := MeshInstance3D.new()
	instance.mesh = quad
	instance.position = Vector3(rect.get_center().x-last_size.x/2,last_size.y/2-rect.get_center().y,z)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/cockpit_display.gdshader")
	material.set_shader_parameter("display_tex",surface_view.get_texture())
	if last_family in [3,5]:
		material.set_shader_parameter("upper_color",Vector3(0.024,0.045,0.085))
		material.set_shader_parameter("lower_color",Vector3(0.006,0.012,0.026))
	elif last_family == 2:
		material.shader = preload("res://shaders/neue_crt.gdshader")
		material.set_shader_parameter("upper_color",Vector3(0.055,0.11,0.085))
		material.set_shader_parameter("lower_color",Vector3(0.008,0.022,0.017))
	material.set_shader_parameter("region",Vector4(rect.position.x/last_size.x,rect.position.y/last_size.y,rect.size.x/last_size.x,rect.size.y/last_size.y))
	instance.material_override = material
	model.add_child(instance)
	surfaces.append(material)


static func neue_instrument_layout(view_size: Vector2) -> Dictionary:
	var k := minf(view_size.x/1280.0,view_size.y/720.0)
	var cx := view_size.x*0.5
	var top := view_size.y*0.64
	return {"center":Rect2(cx-120*k,top,240*k,142*k),
		"left":Rect2(cx-239*k,top+12*k,95*k,126*k),
		"right":Rect2(cx+144*k,top+12*k,95*k,126*k)}


static func neue_panel_outline(key: String) -> Array[Vector2]:
	if key == "center":
		return [Vector2(0,0),Vector2(1,0),Vector2(0.87,1),Vector2(0.13,1)]
	if key == "left":
		return [Vector2(0.08,0),Vector2(0.75,0.07),Vector2(1,1),Vector2(0,0.65)]
	return [Vector2(0.25,0.07),Vector2(0.92,0),Vector2(1,0.65),Vector2(0,1)]


func _neue_shaped_panel(rect: Rect2, key: String) -> void:
	var outline := neue_panel_outline(key)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := rect.get_center()
	for i in 4:
		var j := (i+1)%4
		var a: Vector2 = rect.position+outline[i]*rect.size
		var b: Vector2 = rect.position+outline[j]*rect.size
		var oa := center+(a-center)*1.07
		var ob := center+(b-center)*1.07
		# Recessed glass, sloping rim and extruded outer wall share the same outline.
		for tri in [[Vector3(oa.x,oa.y,21),Vector3(ob.x,ob.y,21),Vector3(a.x,a.y,12)],
			[Vector3(a.x,a.y,12),Vector3(ob.x,ob.y,21),Vector3(b.x,b.y,12)],
			[Vector3(oa.x,oa.y,-6),Vector3(ob.x,ob.y,21),Vector3(oa.x,oa.y,21)],
			[Vector3(oa.x,oa.y,-6),Vector3(ob.x,ob.y,-6),Vector3(ob.x,ob.y,21)]]:
			for v: Vector3 in tri: st.add_vertex(Vector3(v.x-last_size.x/2,last_size.y/2-v.y,v.z))
	st.generate_normals()
	var frame := MeshInstance3D.new()
	frame.name = "NeueShapedBezel_"+key
	frame.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.56,0.53,0.40)
	mat.roughness = 0.65
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	frame.material_override = mat
	model.add_child(frame)
	_screen(rect,12)
	var screen := model.get_child(model.get_child_count()-1) as MeshInstance3D
	screen.name = "NeueShapedGlass_"+key
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in [0,1,2,0,2,3]:
		# UVs warp the existing instrument surface into the shaped glass.
		var uv: Vector2 = [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)][index]
		var point: Vector2 = (outline[index]-Vector2(0.5,0.5))*rect.size
		glass.set_uv(uv)
		glass.set_normal(Vector3(0,0,1))
		glass.add_vertex(Vector3(point.x,-point.y,0))
	screen.mesh = glass.commit()


## Bounded bank cue: continuous through inverted flight, independent of yaw/pitch.
static func shell_roll_target(attitude: Basis, motion_scale: float) -> float:
	return clampf(attitude.orthonormalized().x.y,-1.0,1.0)*SHELL_BANK_LIMIT*clampf(motion_scale,0.0,1.0)
