extends Control
## Transparent, perspective-projected panoramic display. The exterior stays visible.
var view: SubViewport
var eye: Camera3D
var body: MeshInstance3D
var horizon: MeshInstance3D
var composite: TextureRect
var family := -1
var no_graduations := false
var _vertices := PackedVector3Array()
var _colors := PackedColorArray()
const RADIUS := 10.0

static func sphere_dir(azimuth: float, elevation: float) -> Vector3:
	var a := deg_to_rad(azimuth)
	var e := deg_to_rad(elevation)
	return Vector3(sin(a)*cos(e),sin(e),-cos(a)*cos(e))

func sync(hud: Control, enabled: bool, cabin_roll := 0.0) -> void:
	enabled = enabled and is_instance_valid(hud.camera) and is_instance_valid(hud.player)
	visible = enabled
	if not enabled:
		if is_instance_valid(view): view.render_target_update_mode=SubViewport.UPDATE_DISABLED
		return
	if not is_instance_valid(view): _create_view()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	var resolution := Vector2i(hud.size)
	if view.size!=resolution:
		view.size=resolution
		composite.size=hud.size
	eye.fov=hud.camera.fov
	eye.keep_aspect=hud.camera.keep_aspect
	eye.basis=hud.camera.global_transform.basis.orthonormalized()
	# Hull seams live in camera space, while horizon rails stay in world space.
	# Never stabilize the gameplay camera: the exterior must show the full maneuver.
	body.basis=eye.basis*Basis(Vector3.BACK,cabin_roll)
	var next_family: int = preload("res://scripts/ui/cockpit_3d.gd").cockpit_family(hud.player.profile.id)
	var next_no_graduations: bool = hud.player.profile.id in [SuitProfile.Id.NU_GUNDAM,SuitProfile.Id.SAZABI]
	horizon.visible = next_family != 2 and not next_no_graduations
	if family!=next_family or no_graduations!=next_no_graduations:
		family=next_family
		no_graduations=next_no_graduations
		_build_body()
		_build_world_rails()

func _create_view() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	view=SubViewport.new()
	view.transparent_bg=true
	view.gui_disable_input=true
	view.own_world_3d=true
	view.msaa_3d=Viewport.MSAA_4X
	add_child(view)
	eye=Camera3D.new()
	eye.near=0.1
	eye.far=25
	view.add_child(eye)
	eye.current=true
	var environment := WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_CLEAR_COLOR
	view.add_child(environment)
	var shader := Shader.new()
	shader.code="""shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
void fragment() { ALBEDO=COLOR.rgb; ALPHA=COLOR.a; }
"""
	var material := ShaderMaterial.new()
	material.shader=shader
	body=MeshInstance3D.new()
	body.name="PanoramicDisplay"
	body.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.material_override=material
	view.add_child(body)
	horizon=MeshInstance3D.new()
	horizon.name="WorldAttitudeRails"
	horizon.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	horizon.material_override=material
	view.add_child(horizon)
	_build_world_rails()
	composite=TextureRect.new()
	composite.mouse_filter=Control.MOUSE_FILTER_IGNORE
	composite.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	composite.texture=view.get_texture()
	add_child(composite)

func _triangle(a: Vector3,b: Vector3,c: Vector3,color: Color) -> void:
	_vertices.append(a*RADIUS)
	_vertices.append(b*RADIUS)
	_vertices.append(c*RADIUS)
	for i in 3: _colors.append(color)

func _line(points: PackedVector3Array,width: float,color: Color) -> void:
	for i in points.size()-1:
		var a := points[i]
		var b := points[i+1]
		var tangent := b-a
		if tangent.length_squared()<0.00000001: continue
		var offset := tangent.cross(a+b).normalized()*deg_to_rad(width)*0.5
		_triangle((a-offset).normalized(),(a+offset).normalized(),(b+offset).normalized(),color)
		_triangle((a-offset).normalized(),(b+offset).normalized(),(b-offset).normalized(),color)

func _finish_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=_vertices
	arrays[Mesh.ARRAY_COLOR]=_colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_vertices=PackedVector3Array()
	_colors=PackedColorArray()
	return mesh

func _latitude(el: float, width: float, color: Color) -> void:
	var points := PackedVector3Array()
	for a in 181: points.append(sphere_dir(a*2,el))
	_line(points,width,color)

func _meridian(az: float, width: float, color: Color) -> void:
	var points := PackedVector3Array()
	for n in 85: points.append(sphere_dir(az,-84+n*2))
	_line(points,width,color)

func _glyph(az: float,el: float,offsets: Array) -> PackedVector3Array:
	var normal := sphere_dir(az,el)
	var right := normal.cross(Vector3.UP)
	if right.length_squared()<0.0001: right=Vector3.RIGHT
	right=right.normalized()
	var up := right.cross(normal).normalized()
	var points := PackedVector3Array()
	for p: Vector2 in offsets:
		points.append((normal+right*tan(deg_to_rad(p.x))+up*tan(deg_to_rad(p.y))).normalized())
	return points

func _symbol(az: float,el: float,offsets: Array,width: float,color: Color) -> void:
	_line(_glyph(az,el,offsets),width,color)

func _patch(az: float,el: float,offsets: Array,color: Color) -> void:
	var points := _glyph(az,el,offsets)
	for i in range(1,points.size()-1): _triangle(points[0],points[i],points[i+1],color)

func _circle(az: float,el: float,radius: float,width: float,color: Color) -> void:
	var points: Array=[]
	for n in 97:
		var a := float(n)*TAU/96
		points.append(Vector2(cos(a),sin(a))*radius)
	_symbol(az,el,points,width,color)

func _build_body() -> void:
	if family == 3:
		_build_gp03_body()
		return
	if family == 2:
		_build_neue_cabin()
		return
	var ink := Color(0.63,0.67,0.75,0.54) if family==0 else Color(0.64,0.61,0.80,0.54)
	var faint := Color(ink,0.16)
	# Thin seams indicate display sectors, never opaque window pillars.
	for quadrant in 4:
		for side: float in [-1.0,1.0]:
			var az := quadrant*90+side*32
			_meridian(az,0.075,faint)
			_meridian(az+side*0.65,0.075,faint)
			# The reference has an inset band of clipped slats next to each seam.
			for n in 54:
				var el := -79+n*3.0
				var slat := [Vector2(side*0.9,-0.8),Vector2(side*2.8,-0.65),Vector2(side*3.1,-0.35),Vector2(side*2.9,0.55),Vector2(side*1.0,0.8),Vector2(side*0.75,0.45)]
				_patch(az,el,slat,Color(0.20,0.23,0.32,0.11))
				_symbol(az,el,[slat[0],slat[1],slat[2]],0.045,Color(ink,0.10))
			for n in 61:
				var el := -75+n*2.5
				var length := 1.1 if n%4==0 else 0.5
				_line(PackedVector3Array([sphere_dir(az,el),sphere_dir(az+side*length,el)]),0.11,ink)
	# Double bus with U-shaped expansion joints and a muted inner conductor.
	_equatorial_bus(ink,faint)
	for quadrant in 4:
		var az := float(quadrant)*90
		# Repeated angular display glyphs also exist behind the pilot.
		for side: float in [-1.0,1.0]:
			for n in 2:
				var x := side*(7.0+n*4.0)
				var shape := [Vector2(x-side*1.3,0.8),Vector2(x-side*0.6,1),Vector2(x+side*1.2,0.25),Vector2(x+side*1.2,-0.25),Vector2(x-side*0.6,-1),Vector2(x-side*1.3,-0.8),Vector2(x-side*1.3,0.8)]
				_patch(az,26,shape.slice(0,6),Color(ink,0.10))
				_symbol(az,26,shape,0.13,ink)
				var inset: Array=[]
				for point: Vector2 in shape: inset.append(Vector2(x,0)+(point-Vector2(x,0))*0.72)
				_symbol(az,26,inset,0.08,faint)
				for k in 2:
					_symbol(az,26,[Vector2(x-side*(0.65-k*0.3),-0.25),Vector2(x+side*(0.10+k*0.2),0),Vector2(x-side*(0.65-k*0.3),0.25)],0.07,Color(ink,0.34))
		_symbol(az,26,[Vector2(-1,0.8),Vector2(0,-0.5),Vector2(1,0.8)],0.15,ink)
		_symbol(az,26,[Vector2(-3,-1.5),Vector2(3,-1.5)],0.08,faint)
		for side: float in [-1.0,1.0]:
			for row in 2:
				for col in 3:
					var x := side*(15.5+col*0.8)
					var y := -2+row*0.8
					_patch(az,26,[Vector2(x,y),Vector2(x+0.35,y),Vector2(x+0.35,y+0.35),Vector2(x,y+0.35)],Color(ink,0.2))
	# Clipped, tapered petals match the side-view monitor instead of rectangular wedges.
	for az: float in [90,180,270]:
		for n in 84:
			var a := float(n)*TAU/84
			var p := Vector2(cos(a),sin(a))*22.0
			_patch(az,0,[p+Vector2(-0.13,0),p+Vector2(0,0.13),p+Vector2(0.13,0),p+Vector2(0,-0.13)],Color(ink,0.48))
		for n in 20:
			var a := float(n)*TAU/20
			var points := [Vector2.from_angle(a-0.085)*15.2,Vector2.from_angle(a+0.085)*15.2,Vector2.from_angle(a+0.115)*14.5,Vector2.from_angle(a+0.055)*11.0,Vector2.from_angle(a)*10.2,Vector2.from_angle(a-0.055)*11.0,Vector2.from_angle(a-0.115)*14.5]
			_patch(az,0,points,Color(ink,0.19))
			points.append(points[0])
			_symbol(az,0,points,0.055,Color(ink,0.22))
			var notch := [Vector2.from_angle(a-0.012)*14.1,Vector2.from_angle(a+0.012)*14.1,Vector2.from_angle(a+0.01)*13.3,Vector2.from_angle(a-0.01)*13.3]
			_patch(az,0,notch,Color(0.025,0.035,0.06,0.32))
		_circle(az,0,2.7,0.07,Color(ink,0.26))
		_circle(az,0,3.3,0.045,Color(ink,0.12))
		for side: float in [-1.0,1.0]:
			_symbol(az,0,[Vector2(side*0.6,0),Vector2(side*2.1,0)],0.075,Color(ink,0.42))
			_symbol(az,0,[Vector2(0,side*0.6),Vector2(0,side*2.1)],0.075,Color(ink,0.42))
		# Short radial fiducials in the open center preserve the reference's sparse layout.
		for n in 6:
			var a := n*TAU/6+0.2
			_symbol(az,0,[Vector2.from_angle(a)*7.6,Vector2.from_angle(a)*8.7],0.06,Color(ink,0.23))
	# Crown and lower hemisphere have the same calibration language: no polar blind spots.
	for el: float in [-90,90]:
		_circle(0,el,12,0.08,faint)
		for a in 12:
			var p := Vector2.from_angle(a*TAU/12)*12
			_symbol(0,el,[p*0.9,p],0.12,ink)
	body.mesh=_finish_mesh()

func _equatorial_bus(ink: Color, faint: Color) -> void:
	var lower := PackedVector3Array()
	var conductor := PackedVector3Array()
	var upper := PackedVector3Array([sphere_dir(6,-9.4)])
	for n in 175:
		lower.append(sphere_dir(6+n*2,-10.6))
		conductor.append(sphere_dir(6+n*2,-10.0))
	for az in range(10,351,10):
		upper.append(sphere_dir(az-0.18,-9.4))
		upper.append(sphere_dir(az-0.18,-8.95))
		upper.append(sphere_dir(az+0.18,-8.95))
		upper.append(sphere_dir(az+0.18,-9.4))
	upper.append(sphere_dir(354,-9.4))
	_line(lower,0.12,Color(ink,0.50))
	_line(upper,0.12,Color(ink,0.50))
	_line(conductor,0.06,Color(0.65,0.38,0.47,0.18))
	for n in 144:
		var az := n*2.5
		if az<6 or az>354: continue
		_line(PackedVector3Array([sphere_dir(az,-9.0),sphere_dir(az,-8.0 if n%4==0 else -8.5)]),0.09,Color(ink,0.45))
		_line(PackedVector3Array([sphere_dir(az,-10.9),sphere_dir(az,-11.5 if n%4==0 else -11.2)]),0.075,Color(ink,0.30))
	# Paired clipped end blocks and inward amber chevrons at the front bus gap.
	for side: float in [-1.0,1.0]:
		var center := side*7.5
		var outline := [Vector2(-1.1,-0.7),Vector2(0.4,-1.1),Vector2(1.1,-0.5),Vector2(1.1,0.5),Vector2(0.4,1.1),Vector2(-1.1,0.7),Vector2(-1.1,-0.7)]
		for i in outline.size(): outline[i].x*=side
		_patch(center,-10,outline.slice(0,6),Color(ink,0.14))
		_symbol(center,-10,outline,0.10,ink)
		_symbol(center,-10,[Vector2(-side*0.3,-0.3),Vector2(side*0.3,0),Vector2(-side*0.3,0.3)],0.07,faint)
		_symbol(side*5.3,-10,[Vector2(side*0.45,-0.65),Vector2(-side*0.15,0),Vector2(side*0.45,0.65)],0.14,Color(0.86,0.76,0.43,0.58))

func _build_world_rails() -> void:
	if no_graduations:
		horizon.mesh=null
		return
	if family == 3:
		for el: float in [-30,0,30]:
			_latitude(el,0.065,Color(0.28,0.61,1.0,0.16 if el == 0 else 0.055))
		horizon.mesh = _finish_mesh()
		return
	# Attitude rails stay level in world space while the spherical display follows the suit.
	for el: float in [-60,-30,0,30,60]:
		_latitude(el,0.13 if el==0 else 0.065,Color(0.74,0.77,0.84,0.48 if el==0 else 0.11))
		for n in 72:
			var a := n*5.0
			_line(PackedVector3Array([sphere_dir(a,el),sphere_dir(a,el+(1.0 if n%6==0 else 0.4))]),0.09,Color(0.74,0.77,0.84,0.26))
	for n in 8: _meridian(n*45,0.06,Color(0.7,0.74,0.84,0.075))
	horizon.mesh=_finish_mesh()

func _build_gp03_body() -> void:
	# Physical-looking display rails sit outside the forward aiming corridor.
	var shell := Color(0.55,0.57,0.61,0.94)
	var shadow := Color(0.035,0.044,0.06,0.98)
	var cyan := Color(0.28,0.61,1.0,0.48)
	for el: float in [-35,34]:
		_latitude(el,1.25,shadow)
		_latitude(el,0.82,shell)
		_latitude(el+0.35,0.07,Color(0.83,0.84,0.86,0.8))
		if not no_graduations:
			for az in range(0,360,15):
				_symbol(az,el,[Vector2(0,-0.48),Vector2(0,0.48)],0.12,shadow)
	if no_graduations:
		body.mesh=_finish_mesh()
		return
	# Cyan calibration ladders are short, sparse, and never cross the reticle.
	for az: float in [-25,25,90,180,270]:
		_symbol(az,0,[Vector2(0,-14),Vector2(0,14)],0.075,Color(cyan,0.20))
		for n in range(-7,8):
			_symbol(az,n*2,[Vector2(0,0),Vector2(1.8 if n%5==0 else 0.8,0)],0.09,cyan)
		for el: float in [-22,22]:
			_symbol(az,el,[Vector2(-2,0),Vector2(2,0)],0.10,cyan)
	body.mesh = _finish_mesh()


# Four planar displays in a forward-tapering cabin; only Neue Ziel uses this mesh.
static func neue_faces() -> Dictionary:
	var fl := Vector3(-4.2,-1.5,-8.5)
	var fr := Vector3(4.2,-1.5,-8.5)
	var tl := Vector3(-5.8,2.3,-8.5)
	var tr := Vector3(5.8,2.3,-8.5)
	var bl := Vector3(-8,-5,2)
	var br := Vector3(8,-5,2)
	var ul := Vector3(-8,7,2)
	var ur := Vector3(8,7,2)
	return {"front":[fl,fr,tr,tl],"left":[bl,fl,tl,ul],
		"right":[fr,br,ur,tr],"top":[tl,tr,ur,ul],
		"floor":[bl,br,fr,fl],"rear":[br,bl,ul,ur]}


func _neue_quad(points: Array, color: Color) -> void:
	_triangle(points[0]/RADIUS,points[1]/RADIUS,points[2]/RADIUS,color)
	_triangle(points[0]/RADIUS,points[2]/RADIUS,points[3]/RADIUS,color)


func _neue_beam(a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var offset := (b-a).cross((a+b)*0.5).normalized()*width*0.5
	_neue_quad([a-offset,b-offset,b+offset,a+offset],color)


func _neue_display_frame(points: Array) -> void:
	var center := Vector3.ZERO
	for p: Vector3 in points: center += p*0.25
	var inner: Array = []
	for p: Vector3 in points: inner.append(center+(p-center)*0.94)
	# Flat trapezoidal aperture, with straight raised rails around the whole panel.
	for i in 4:
		var j := (i+1)%4
		_neue_quad([points[i],points[j],inner[j],inner[i]],Color(0.13,0.15,0.115,1))
		_neue_beam(inner[i],inner[j],0.055,Color(0.38,0.39,0.28,1))
		_neue_beam(points[i],points[j],0.16,Color(0.035,0.045,0.03,1))
		# Segmented beam sleeves and fasteners track the straight window frame.
		for n in 4:
			var q: Vector3 = points[i].lerp(points[j],0.12+n*0.25)
			var tangent: Vector3 = (points[j]-points[i]).normalized()
			_neue_beam(q-tangent*0.12,q+tangent*0.12,0.23,Color(0.27,0.29,0.21,1))
			_neue_disc(q*0.996,0.042,Color(0.055,0.065,0.04,1))


func _build_neue_cabin() -> void:
	var faces := neue_faces()
	# Exactly four large monitor apertures: forward, left, right and overhead.
	for key in ["front","left","right","top"]:
		_neue_display_frame(faces[key])
	_neue_quad(faces["floor"],Color(0.075,0.09,0.07,1))
	_neue_quad(faces["rear"],Color(0.11,0.13,0.10,1))
	# The overhead equipment bridge is narrow, leaving most of the top display open.
	var roof: Array = faces["top"]
	var l: Vector3 = roof[0].lerp(roof[3],0.24)
	var r: Vector3 = roof[1].lerp(roof[2],0.24)
	_neue_beam(l,r,0.58,Color(0.19,0.21,0.15,1))
	for n in 5:
		var p0 := l.lerp(r,0.40)+Vector3(0,0,0.045*n-0.09)
		var p1 := l.lerp(r,0.60)+Vector3(0,0,0.045*n-0.09)
		_neue_beam(p0,p1,0.018,Color(0.04,0.05,0.035,1))
	# Roof bridge: bevelled central service panel, circular control and side insets.
	var center := (l+r)*0.5
	var along := (r-l).normalized()
	var up := along.cross(center).normalized()
	_neue_quad([center-along*1.5-up*0.28,center+along*1.5-up*0.28,center+along*1.25+up*0.32,center-along*1.25+up*0.32],Color(0.27,0.29,0.21,1))
	_neue_disc(center*0.99,0.19,Color(0.07,0.08,0.055,1))
	_neue_disc(center*0.985,0.115,Color(0.40,0.41,0.29,1))
	for side: float in [-1.0,1.0]:
		var c := center+along*side*2.1
		_neue_beam(c-along*0.34,c+along*0.34,0.24,Color(0.07,0.085,0.055,1))
		for n in 3:
			var q := c+along*(-0.22+n*0.22)
			_neue_beam(q-up*0.07,q+up*0.07,0.025,Color(0.44,0.45,0.32,1))
	# Rear bulkhead seams and service vent remain opaque when looking back.
	for y: float in [-2,0,2,4]:
		_neue_beam(Vector3(-7.5,y,1.98),Vector3(7.5,y,1.98),0.055,Color(0.23,0.25,0.18,1))
	_neue_disc(Vector3(-5,3.6,1.96),0.65,Color(0.055,0.065,0.045,1))
	for n in 6:
		_neue_beam(Vector3(-5.45,3.2+n*0.15,1.94),Vector3(-4.55,3.2+n*0.15,1.94),0.035,Color(0.38,0.40,0.28,1))
	# Small front reticle remains on the front plane, without panoramic rings.
	_neue_beam(Vector3(-0.35,0,-8.49),Vector3(0.35,0,-8.49),0.008,Color(0.7,0.77,0.59,0.6))
	_neue_beam(Vector3(0,-0.25,-8.49),Vector3(0,0.25,-8.49),0.008,Color(0.7,0.77,0.59,0.6))
	body.mesh = _finish_mesh()


func _neue_disc(center: Vector3, radius: float, color: Color) -> void:
	var normal := center.normalized()
	var right := normal.cross(Vector3.UP).normalized()
	if right.length_squared()<0.01: right = Vector3.RIGHT
	var up := right.cross(normal).normalized()
	for n in 16:
		var a := TAU*n/16.0
		var b := TAU*(n+1)/16.0
		_triangle(center/RADIUS,(center+(right*cos(a)+up*sin(a))*radius)/RADIUS,(center+(right*cos(b)+up*sin(b))*radius)/RADIUS,color)


