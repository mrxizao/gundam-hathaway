extends RefCounted
## One camera-space solid shell. Display apertures remain transparent to the game.
var host: Control
var tool: SurfaceTool
var scale_factor: float

func build(cockpit: Control) -> void:
	host = cockpit
	scale_factor = minf(host.last_size.x/1280.0,host.last_size.y/720.0)
	tool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Shared vertices, one rail per edge: no doubled coplanar frames at the corners.
	var corners: Array[Vector3] = [Vector3(-318,109,-60),Vector3(318,109,-60),Vector3(439,-167,-60),Vector3(-439,-167,-60),Vector3(-800,520,-95),Vector3(800,520,-95),Vector3(800,-520,-95),Vector3(-800,-520,-95)]
	for edge: Vector2i in [Vector2i(0,1),Vector2i(1,2),Vector2i(2,3),Vector2i(3,0),Vector2i(0,4),Vector2i(1,5),Vector2i(2,6),Vector2i(3,7),Vector2i(4,7),Vector2i(5,6),Vector2i(6,7)]:
		beam(corners[edge.x],corners[edge.y],8.0,Color(0.12,0.15,0.095))
	# Opaque triangular cheek walls beside the forward monitor, per the marked reference.
	# The outer edge stays nearly vertical; the inner edge follows the tapering frame.
	for side: float in [-1.0,1.0]:
		var a := Vector3(side*439,-167,-60)
		var b := Vector3(side*318,109,-60)
		var c := Vector3(side*439,192,-67)
		var color := Color(0.12,0.15,0.095)
		for point: Vector3 in [a,b,c]: vertex(point,color)
		# Closed side walls give the cheek panel thickness instead of a flat mask.
		var back := Vector3(0,0,-12)
		for edge: Array in [[a,b],[b,c],[c,a]]:
			quad(edge[0],edge[1],edge[1]+back,edge[0]+back,color.darkened(0.3))
		beam(a,c,5.0,Color(0.30,0.33,0.22))
		beam(b,c,5.0,Color(0.20,0.23,0.15))
		# Narrow inset rib follows the solid triangle without entering the display.
		beam(a.lerp(c,0.23)+Vector3(-side*10,0,2),a.lerp(c,0.78)+Vector3(-side*10,0,2),2.0,Color(0.14,0.17,0.105))
		# Inset triangular lining, split into two service panels along the original ribs.
		var center := (a+b+c)/3.0
		var inset: Array[Vector3] = []
		for point: Vector3 in [a,b,c]: inset.append(center+(point-center)*0.77+Vector3(0,0,3))
		for point: Vector3 in inset: vertex(point,Color(0.20,0.23,0.15))
		for n in 3:
			beam(inset[n],inset[(n+1)%3],1.4,Color(0.10,0.13,0.075))
		var split := a.lerp(c,0.64)+Vector3(0,0,5)
		beam(split,b.lerp(c,0.60)+Vector3(0,0,5),2,Color(0.12,0.15,0.085))
		for t: float in [0.28,0.58,0.85]:
			hub(a.lerp(c,t)+Vector3(-side*7,0,5),3)
		# Small stamped access grip sits entirely on the opaque lower triangle.
		beam(Vector3(side*404,83,-42),Vector3(side*404,116,-42),3,Color(0.10,0.13,0.08))
		beam(Vector3(side*398,85,-32),Vector3(side*398,113,-32),2,Color(0.32,0.35,0.23))
	# Solid tapered lower fascia continues all the way to the console base.
	quad(corners[0],corners[1],Vector3(800,520,-95),Vector3(-800,520,-95),Color(0.035,0.045,0.033))
	# Broad ceiling equipment band shares exact endpoints with the sloping roof rails.
	var upper_l: Vector3 = corners[3].lerp(corners[7],0.40)
	var upper_r: Vector3 = corners[2].lerp(corners[6],0.40)
	var lower_l: Vector3 = corners[3].lerp(corners[7],0.19)
	var lower_r: Vector3 = corners[2].lerp(corners[6],0.19)
	quad(upper_l,upper_r,lower_r,lower_l,Color(0.12,0.15,0.095))
	beam(upper_l,upper_r,6.0,Color(0.32,0.35,0.24))
	beam(lower_l,lower_r,7.5,Color(0.19,0.22,0.145))
	for pair: Array in [[upper_l,lower_l],[upper_r,lower_r]]:
		beam(pair[0],pair[1],7.0,Color(0.30,0.33,0.22))
	for point: Vector3 in [upper_l,upper_r,lower_l,lower_r,corners[0],corners[1],corners[2],corners[3]]:
		hub(point,11.0)
	var y := (upper_l.y+lower_l.y)*0.5
	# Recessed central service panel and round control, as in the animation setting.
	ceiling_panel(Vector2(0,y),Vector2(254,54),-40,Color(0.12,0.15,0.09))
	ceiling_panel(Vector2(0,y),Vector2(236,40),-32,Color(0.56,0.53,0.41))
	for n in 4:
		beam(Vector3(-90,y-12+n*8,-20),Vector3(-28,y-12+n*8,-20),1.4,Color(0.09,0.12,0.07))
	hub(Vector3(24,y,-15),13)
	beam(Vector3(24,y-8,0),Vector3(24,y+8,0),2,Color(0.06,0.08,0.04))
	for side: float in [-1.0,1.0]:
		ceiling_panel(Vector2(side*240,y),Vector2(122,38),-38,Color(0.075,0.095,0.055))
		for n in 8:
			var x := side*240-45+n*13
			beam(Vector3(x,y-11,-24),Vector3(x,y+11,-24),2.2,Color(0.32,0.35,0.235))
		# End access covers, seams and captive fasteners fill the broad ceiling surface.
		ceiling_panel(Vector2(side*406,y),Vector2(116,44),-41,Color(0.22,0.25,0.16))
		for dx: float in [-44,44]:
			hub(Vector3(side*406+dx,y,-28),3.5)
	# Repeated captive fasteners and black inner gasket outline the forward aperture.
	for edge: Vector2i in [Vector2i(0,1),Vector2i(1,2),Vector2i(2,3),Vector2i(3,0)]:
		var a := corners[edge.x]
		var b := corners[edge.y]
		var mid := (a+b)*0.5
		var inward := Vector3(-mid.x,-mid.y,0).normalized()*5
		beam(a+inward+Vector3(0,0,2),b+inward+Vector3(0,0,2),1.4,Color(0.055,0.075,0.045))
		for t: float in [0.22,0.50,0.78]:
			hub(a.lerp(b,t)+Vector3(0,0,9),3)
	# Lower fascia carries recessed banks between the instruments and console keys.
	for side: float in [-1.0,1.0]:
		ceiling_panel(Vector2(side*324,178),Vector2(122,42),-49,Color(0.075,0.095,0.055))
		for n in 5:
			var x := side*324-43+n*21
			ceiling_panel(Vector2(x,178),Vector2(12,23),-35,Color(0.28,0.30,0.20))
			beam(Vector3(x,173,-22),Vector3(x,181,-22),2,Color(0.09,0.12,0.065))
		# Rounded pressure dial beside the auxiliary screen; no extra HUD text clutter.
		hub(Vector3(side*485,272,-30),14)
		hub(Vector3(side*485,272,-15),10)
		beam(Vector3(side*485,272,0),Vector3(side*480,265,0),1.3,Color(0.045,0.06,0.03))
	# Machined cooling strips occupy only the solid ceiling band between access covers.
	for side: float in [-1.0,1.0]:
		ceiling_panel(Vector2(side*326,y),Vector2(30,40),-30,Color(0.055,0.07,0.045))
		for n in 6:
			var vy := y-13+n*5
			beam(Vector3(side*326-9,vy,-20),Vector3(side*326+9,vy,-20),0.85,Color(0.27,0.29,0.20))
		# Fine seams and latch pockets stay on the opaque cheek panels.
		var latch := Vector3(side*417,144,-35)
		ceiling_panel(Vector2(latch.x,latch.y),Vector2(13,23),latch.z,Color(0.065,0.085,0.05))
		beam(latch+Vector3(-3,-6,5),latch+Vector3(3,-6,5),1.2,Color(0.38,0.40,0.27))
		beam(latch+Vector3(-3,6,5),latch+Vector3(3,6,5),1.2,Color(0.38,0.40,0.27))
		# Calibrated pressure dial: short engraved divisions, with a longer index.
		var dial := Vector3(side*485,272,-2)
		for n in 9:
			var angle := lerpf(-PI*0.8,PI*0.8,float(n)/8.0)
			var radial := Vector3(sin(angle),-cos(angle),0)
			beam(dial+radial*10.5,dial+radial*(13.0 if n%2==0 else 12.0),0.45,Color(0.55,0.55,0.38))
	tool.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "NeueUnifiedShell"
	mesh.mesh = tool.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.78
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.model.add_child(mesh)

func vertex(p: Vector3, color: Color) -> void:
	tool.set_color(color)
	tool.add_vertex(Vector3(p.x*scale_factor,-p.y*scale_factor,p.z*scale_factor))

func quad(a: Vector3,b: Vector3,c: Vector3,d: Vector3,color: Color) -> void:
	for p: Vector3 in [a,b,c,a,c,d]: vertex(p,color)

func beam(a: Vector3,b: Vector3,radius: float,color: Color) -> void:
	var tangent := (b-a).normalized()
	var across := tangent.cross(Vector3(0,0,1)).normalized()
	var depth := tangent.cross(across).normalized()
	# Octagonal cross-section provides real bevels and shaded side walls.
	for n in 8:
		var angle := TAU*n/8.0+PI/8.0
		var next := TAU*(n+1)/8.0+PI/8.0
		var u := (across*cos(angle)+depth*sin(angle))*radius
		var v := (across*cos(next)+depth*sin(next))*radius
		quad(a+u,b+u,b+v,a+v,color)

func hub(center: Vector3,radius: float) -> void:
	# Rounded corner cap covers intersecting ends without protruding square patches.
	for n in 12:
		var a := TAU*n/12.0
		var b := TAU*(n+1)/12.0
		var p := center+Vector3(cos(a),sin(a),0)*radius
		var q := center+Vector3(cos(b),sin(b),0)*radius
		var inner := center+Vector3(0,0,10)
		vertex(inner,Color(0.29,0.31,0.22))
		vertex(p,Color(0.21,0.24,0.16))
		vertex(q,Color(0.21,0.24,0.16))
	# Captive hardware has a dark recessed drive and a narrow machined rim.
	if radius <= 4.0:
		var face := center+Vector3(0,0,10.6)
		for n in 12:
			var a := TAU*n/12.0
			var b := TAU*(n+1)/12.0
			vertex(face,Color(0.07,0.085,0.05))
			vertex(face+Vector3(cos(a),sin(a),0)*radius*0.52,Color(0.10,0.12,0.07))
			vertex(face+Vector3(cos(b),sin(b),0)*radius*0.52,Color(0.10,0.12,0.07))
		beam(face+Vector3(-radius*0.55,0,0.3),face+Vector3(radius*0.55,0,0.3),radius*0.12,Color(0.025,0.035,0.02))

func ceiling_panel(center: Vector2,size: Vector2,z: float,color: Color) -> void:
	var points: Array[Vector3] = []
	var h := size*0.5
	for p: Vector2 in [Vector2(-h.x+7,-h.y),Vector2(h.x-7,-h.y),Vector2(h.x,-h.y+7),Vector2(h.x,h.y-7),Vector2(h.x-7,h.y),Vector2(-h.x+7,h.y),Vector2(-h.x,h.y-7),Vector2(-h.x,-h.y+7)]:
		points.append(Vector3(center.x+p.x,center.y+p.y,z))
	for n in 8:
		var a := points[n]
		var b := points[(n+1)%8]
		vertex(Vector3(center.x,center.y,z),color)
		vertex(a,color)
		vertex(b,color)
		quad(a,b,b+Vector3(0,0,-7),a+Vector3(0,0,-7),color.darkened(0.3))
		# A fine raised lip catches light; the inset gasket separates adjacent surfaces.
		beam(a+Vector3(0,0,0.8),b+Vector3(0,0,0.8),0.65,color.lightened(0.13))
