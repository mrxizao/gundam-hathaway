extends RefCounted
## Traditional three-screen cabin. Peripheral consoles leave the aiming lane
## clear; the central pedestal starts below 82% of screen height.
const METAL := Color(.19,.24,.29)
const EDGE := Color(.36,.43,.48)
const DARK := Color(.032,.045,.063)
static func layout(v: Vector2) -> Dictionary:
	return {"center":Rect2(v*Vector2(.449,.86),v*Vector2(.102,.13)),
		"left":Rect2(v*Vector2(.105,.675),v*Vector2(.122,.255)),
		"right":Rect2(v*Vector2(.773,.675),v*Vector2(.122,.255)),
		"left_aux":Rect2(v*Vector2(.238,.69),v*Vector2(.086,.225)),
		"right_aux":Rect2(v*Vector2(.676,.69),v*Vector2(.086,.225)),
		"upper_left":Rect2(v*Vector2(.402,.065),v*Vector2(.077,.065)),
		"upper_right":Rect2(v*Vector2(.521,.065),v*Vector2(.077,.065))}

static func build(h) -> void:
	var v: Vector2 = h.last_size
	var k := minf(v.x/1280.0,v.y/720.0)
	h.model.name="FullArmorTB_ThreeScreenCockpit"
	var modules := layout(v)
	h.surface.modules=modules;h.surface.set_meta("full_armor_source",h.hud)
	plate(h,[Vector2(0,0),Vector2(.32,0),Vector2(.285,.04),Vector2(.035,.045),Vector2(0,.1)],-12,METAL)
	plate(h,[Vector2(1,0),Vector2(.68,0),Vector2(.715,.04),Vector2(.965,.045),Vector2(1,.1)],-12,METAL)
	plate(h,[Vector2(.273,0),Vector2(.293,0),Vector2(.3,.12),Vector2(.299,.735),Vector2(.279,.77),Vector2(.281,.14)],8,METAL)
	plate(h,[Vector2(.727,0),Vector2(.707,0),Vector2(.7,.12),Vector2(.701,.735),Vector2(.721,.77),Vector2(.719,.14)],8,METAL)
	plate(h,[Vector2(.294,0),Vector2(.706,0),Vector2(.685,.048),Vector2(.315,.048)],12,EDGE)
	h._box(Rect2(v*Vector2(.315,.037),v*Vector2(.37,.009)),10,19,DARK)
	# Cast outer shells, an inset sloped face, and a separate palm-rest shelf.
	for side: float in [-1.0,1.0]:
		var mirror: bool=side>0
		mirror_plate(h,[Vector2(0,.77),Vector2(.09,.64),Vector2(.29,.655),Vector2(.326,.755),Vector2(.337,1),Vector2(0,1)],mirror,-15,METAL)
		mirror_plate(h,[Vector2(.062,.79),Vector2(.105,.67),Vector2(.30,.687),Vector2(.325,.77),Vector2(.322,.925),Vector2(.07,.952)],mirror,2,Color(.105,.14,.18))
		mirror_plate(h,[Vector2(.055,.952),Vector2(.318,.918),Vector2(.331,.97),Vector2(.082,1)],mirror,23,EDGE)
		mirror_plate(h,[Vector2(.064,.965),Vector2(.316,.935),Vector2(.318,.943),Vector2(.068,.975)],mirror,28,DARK)
		# Side kick panel and upper vents remain beyond the central viewing lane.
		for n in 6:
			var x: float = (.04 if not mirror else .925)*v.x
			h._box(Rect2(x,v.y*(.805+n*.014),.035*v.x,2*k),2,13,DARK)
		for lamp in 4:
			h._box(Rect2(v.x*(.5+side*.211)-6*k,v.y*(.45+lamp*.029),12*k,15*k),5,24,Color(.65,.72,.75))
		for n in 5:
			h._box(Rect2(v.x*(.5+side*.34)-27*k,v.y*.026+n*4*k,54*k,2*k),2,14,DARK)
		# Raised keyboard tray, with individual key wells and pale caps.
		var tray := Rect2(v*Vector2(.222 if not mirror else .692,.933),v*Vector2(.086,.053))
		h._shell(tray.grow(3*k),9,35)
		for row in 2:
			for col in 3:
				var cell := Rect2(tray.position+Vector2((col+.12)*tray.size.x/3,(row+.18)*tray.size.y/2),Vector2(tray.size.x*.28,tray.size.y*.32))
				h._box(cell.grow(k),3,40,DARK)
				h._box(cell,3,43,Color(.67,.70,.69) if col!=2 else Color(.35,.42,.47))
		stick(h,Vector2(v.x*(.5+side*.417),v.y*.928),side,k)
		console_details(h,mirror,k)
		# Recessed utility switches, screw heads and metal edge seams.
		for n in 4:
			var at:=Vector2(v.x*(.5+side*.455),v.y*(.89+n*.021))
			h._box(Rect2(at,Vector2(11,8)*k),4,26,DARK)
			h._box(Rect2(at+Vector2(2,2)*k,Vector2(7,4)*k),3,30,Color(.23,.40,.62))
		for n in 5:
			disc(h,Vector2(v.x*(.5+side*.195),v.y*(.736+n*.037)),2*k,2*k,22,EDGE)
	# Lowered center pedestal has no opaque geometry above y=0.82.
	plate(h,[Vector2(.372,1),Vector2(.411,.855),Vector2(.437,.823),Vector2(.563,.823),Vector2(.589,.855),Vector2(.628,1)],-12,METAL)
	plate(h,[Vector2(.422,.855),Vector2(.444,.838),Vector2(.556,.838),Vector2(.578,.855),Vector2(.562,.995),Vector2(.438,.995)],4,DARK)
	for key in modules:
		var r: Rect2=modules[key]
		if key in ["left","left_aux","right","right_aux"]:
			angled_screen(h,r,key.begins_with("right"),k)
		else:
			h._shell(r.grow(6*k),13*k,15)
			h._screen(r,29)
	# A shallow circular bezel gives the central radar a round physical aperture.
	var radar: Rect2=modules.center
	ring(h,radar.get_center(),minf(radar.size.x,radar.size.y)*.43,minf(radar.size.x,radar.size.y)*.49,34,EDGE)
	h._box(Rect2(v*Vector2(.391,.055),v*Vector2(.218,.087)),10,-4,EDGE)
	h._box(Rect2(v*Vector2(.489,.069),v*Vector2(.022,.018)),3,23,Color(.68,.71,.7))
	for n in 2:
		h._box(Rect2(v*Vector2(.489+n*.015,.108),Vector2(6,2)*k),3,24,DARK)
	# Emergency switches and side strips sit below the visible combat window.
	for side: float in [-1.0,1.0]:
		for n in 4:
			h._box(Rect2(v.x*(.5+side*.08)-7*k,v.y*.943+n*9*k,14*k,5*k),3,28,Color(.64,.69,.71))
	for screen: ShaderMaterial in h.surfaces:
		screen.shader=preload("res://shaders/full_armor_display.gdshader")
	var overlay:=preload("res://scripts/ui/full_armor_cockpit_overlay.gd").new()
	overlay.hud=h.hud;overlay.size=v;overlay.show_behind_parent=true;h.texture_rect.add_child(overlay)

static func plate(h, points: Array, z: float, color: Color) -> void:
	var polygon:=PackedVector2Array()
	for p: Vector2 in points: polygon.append(p*h.last_size)
	h._neue_console_plate(polygon,z,color)
static func mirror_plate(h,points: Array,mirrored: bool,z: float,color: Color) -> void:
	var result: Array=[]
	for p: Vector2 in points: result.append(Vector2(1-p.x if mirrored else p.x,p.y))
	plate(h,result,z,color)
static func vertex(h,p: Vector2,z: float) -> Vector3:
	return Vector3(p.x-h.last_size.x/2,h.last_size.y/2-p.y,z)
static func add_mesh(h,st: SurfaceTool,color: Color,name: String) -> MeshInstance3D:
	st.generate_normals()
	var instance:=MeshInstance3D.new();instance.mesh=st.commit();instance.name=name
	var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.58;mat.metallic=.3;mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	instance.material_override=mat;h.model.add_child(instance)
	return instance
static func angled_screen(h,r: Rect2,mirrored: bool,k: float) -> void:
	var local := [Vector2(0,.09),Vector2(.88,0),Vector2(1,.91),Vector2(.16,1)]
	var points: Array[Vector2]=[]
	for p: Vector2 in local:
		points.append(r.position+Vector2(1-p.x if mirrored else p.x,p.y)*r.size)
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var j: int=(i+1)%4
		var a: Vector2=r.get_center()+(points[i]-r.get_center())*1.1
		var b: Vector2=r.get_center()+(points[j]-r.get_center())*1.1
		for tri in [[vertex(h,a,33),vertex(h,b,33),vertex(h,points[i],24)],
			[vertex(h,points[i],24),vertex(h,b,33),vertex(h,points[j],24)],
			[vertex(h,a,10),vertex(h,b,33),vertex(h,a,33)],
			[vertex(h,a,10),vertex(h,b,10),vertex(h,b,33)]]:
			for p: Vector3 in tri: st.add_vertex(p)
	add_mesh(h,st,EDGE,"SlopedMonitorBezel")
	# A second inset seal separates the glass from the metal frame.
	st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var j: int=(i+1)%4
		var a: Vector2=r.get_center()+(points[i]-r.get_center())*1.027
		var b: Vector2=r.get_center()+(points[j]-r.get_center())*1.027
		for point: Vector3 in [vertex(h,a,27),vertex(h,b,27),vertex(h,points[i],26.5),vertex(h,points[i],26.5),vertex(h,b,27),vertex(h,points[j],26.5)]:st.add_vertex(point)
	add_mesh(h,st,DARK,"InsetGlassSeal")
	# A real projecting brow and return flange, rather than a flat display rim.
	st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a: Vector2=points[0];var b: Vector2=points[1]
	var ua: Vector2=a+Vector2(0,-9*k);var ub: Vector2=b+Vector2(0,-9*k)
	for triangle in [[vertex(h,ua,20),vertex(h,ub,20),vertex(h,a,43)],
		[vertex(h,a,43),vertex(h,ub,20),vertex(h,b,43)],
		[vertex(h,a,39),vertex(h,b,43),vertex(h,a,43)],
		[vertex(h,a,39),vertex(h,b,39),vertex(h,b,43)]]:
		for point: Vector3 in triangle:st.add_vertex(point)
	add_mesh(h,st,METAL,"MonitorSunshade")
	st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uv: Array[Vector2]=[Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]
	for i in [0,1,2,0,2,3]:
		st.set_uv(Vector2(1-uv[i].x,uv[i].y) if mirrored else uv[i]);st.add_vertex(vertex(h,points[i],25))
	var glass:=add_mesh(h,st,DARK,"SlopedMonitorGlass")
	var material:=ShaderMaterial.new();material.shader=preload("res://shaders/full_armor_display.gdshader")
	material.set_shader_parameter("display_tex",h.surface_view.get_texture())
	material.set_shader_parameter("region",Vector4(r.position.x/h.last_size.x,r.position.y/h.last_size.y,r.size.x/h.last_size.x,r.size.y/h.last_size.y))
	glass.material_override=material;h.surfaces.append(material)
	for at in points:
		var bolt: Vector2=r.get_center()+(at-r.get_center())*1.055
		disc(h,bolt,2*k,2*k,35,EDGE)
		h._box(Rect2(bolt-Vector2(1.4,.35)*k,Vector2(2.8,.7)*k),1,37,DARK)

static func disc(h,at: Vector2,radius: float,depth: float,z: float,color: Color) -> void:
	var mesh:=CylinderMesh.new();mesh.top_radius=radius*.87;mesh.bottom_radius=radius;mesh.height=depth;mesh.radial_segments=16
	var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.6;mesh.material=mat
	var instance:=MeshInstance3D.new();instance.mesh=mesh;instance.position=vertex(h,at,z);instance.rotation_degrees.x=90;h.model.add_child(instance)
static func ring(h,at: Vector2,inner: float,outer: float,z: float,color: Color) -> void:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 48:
		var a:=Vector2.from_angle(i*TAU/48);var b:=Vector2.from_angle((i+1)*TAU/48)
		for p in [vertex(h,at+a*outer,z),vertex(h,at+b*outer,z),vertex(h,at+a*inner,z+3),vertex(h,at+a*inner,z+3),vertex(h,at+b*outer,z),vertex(h,at+b*inner,z+3)]:st.add_vertex(p)
	add_mesh(h,st,color,"RadarAperture")
static func stick(h,base: Vector2,side: float,k: float) -> void:
	h._shell(Rect2(base-Vector2(19,5)*k,Vector2(38,36)*k),12,35)
	disc(h,base,17*k,8*k,46,DARK);disc(h,base,12*k,6*k,52,EDGE)
	for rib in 5:
		disc(h,base-Vector2(side*rib*.5,rib*3.5)*k,(10-rib*.65)*k,3*k,56+rib,DARK)
	var grip:=base-Vector2(side*6,49)*k
	var mesh:=CapsuleMesh.new();mesh.radius=11*k;mesh.height=58*k;mesh.radial_segments=12;mesh.rings=4
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.065,.085,.11);mat.roughness=.9;mesh.material=mat
	var instance:=MeshInstance3D.new();instance.name="SculptedGrip";instance.mesh=mesh;instance.position=vertex(h,grip,68);instance.rotation.z=side*.17;h.model.add_child(instance)
	engrave(h,base+Vector2(0,26)*k,49,"RCS",k)
	# Overmoulded cheeks, a wraparound trigger guard and a ribbed rear spine.
	var first: int=h.model.get_child_count()
	h._shell(Rect2(grip+Vector2(-12,-14)*k,Vector2(24,32)*k),10*k,76)
	var cheek: MeshInstance3D=h.model.get_child(first)
	cheek.material_override.albedo_color=Color(.085,.105,.13)
	var guard: Array[Vector2]=[Vector2(side*9,-18),Vector2(side*19,-12),Vector2(side*22,9),Vector2(side*12,20)]
	for n in guard.size()-1:pipe(h,grip+guard[n]*k,grip+guard[n+1]*k,2.2*k,84,DARK)
	for n in 3:
		h._box(Rect2(grip+Vector2(-10,-7+n*8)*k,Vector2(2,5)*k),3,85,Color(.14,.17,.19))
	# Curved red thumb guard sits proud of the black top housing.
	var red_guard: Array[Vector2]=[Vector2(-10,-23),Vector2(-8,-30),Vector2(6,-31),Vector2(11,-26)]
	for n in red_guard.size()-1:pipe(h,grip+red_guard[n]*k,grip+red_guard[n+1]*k,2.0*k,87,Color(.47,.07,.055))
	disc(h,grip+Vector2(-side*5,-21)*k,4.3*k,2*k,88,DARK)
	disc(h,grip+Vector2(-side*5,-21)*k,2.8*k,3*k,90,Color(.71,.10,.065))
	# Separate palm heel, trigger, thumb hat and guarded red fire button.
	h._box(Rect2(grip+Vector2(-12,12)*k,Vector2(24,12)*k),14*k,72,DARK)
	h._box(Rect2(grip+Vector2(side*13-2,-9)*k,Vector2(4,20)*k),5*k,75,EDGE)
	h._box(Rect2(grip+Vector2(-10,-28)*k,Vector2(20,6)*k),8*k,73,Color(.16,.18,.21))
	disc(h,grip+Vector2(-side*6,-25)*k,3.2*k,3*k,80,Color(.72,.11,.07))
	disc(h,grip+Vector2(side*6,-18)*k,2.5*k,3*k,80,Color(.46,.53,.58))
	for i in 3:
		h._box(Rect2(grip+Vector2(-8,-6+i*8)*k,Vector2(16,1)*k),2,77,Color(.11,.13,.15))


static func console_details(h,mirror: bool,k: float) -> void:
	var v: Vector2=h.last_size
	var side: float=1.0 if mirror else -1.0
	# Separate crown casting and recessed service access above both displays.
	mirror_plate(h,[Vector2(.087,.69),Vector2(.115,.622),Vector2(.285,.64),Vector2(.324,.676),Vector2(.318,.697),Vector2(.281,.66),Vector2(.12,.646),Vector2(.103,.7)],mirror,22,EDGE)
	mirror_plate(h,[Vector2(.127,.635),Vector2(.203,.643),Vector2(.218,.661),Vector2(.132,.653)],mirror,26,DARK)
	for n in 3:
		var x: float=(.143+n*.019) if not mirror else (1-.143-n*.019-.012)
		h._box(Rect2(v*Vector2(x,.647),v*Vector2(.012,.003)),2,29,Color(.26,.31,.35))
	# Thick outside cheek with a recessed switch bank and raised safety toggle.
	mirror_plate(h,[Vector2(.021,.808),Vector2(.065,.747),Vector2(.091,.785),Vector2(.071,.94),Vector2(.025,.966)],mirror,20,Color(.13,.17,.21))
	for n in 3:
		var at:=Vector2(v.x*(.5+side*.452),v.y*(.79+n*.025))
		h._shell(Rect2(at,Vector2(13,9)*k),4,26)
		h._box(Rect2(at+Vector2(3,2)*k,Vector2(7,5)*k),3,31,Color(.62,.69,.72))
	var toggle:=Vector2(v.x*(.5+side*.458),v.y*.865)
	disc(h,toggle,6*k,3*k,32,DARK)
	pipe(h,toggle,toggle+Vector2(-side*3,-8)*k,1.8*k,38,EDGE)
	engrave(h,Vector2(v.x*(.835 if mirror else .165),v.y*.646),31,"MFD / 02" if mirror else "MFD / 01",k)
	# Raised rotary controls on a separate side service module.
	var dial_x: float=v.x*(.972 if mirror else .028)
	h._shell(Rect2(dial_x-8*k,v.y*.865,16*k,49*k),7,24)
	for dial in 3:
		var at:=Vector2(dial_x,v.y*.88+dial*14*k)
		disc(h,at,5.4*k,4*k,31,DARK)
		disc(h,at,3.8*k,3*k,35,EDGE)
		h._box(Rect2(at-Vector2(.5,2.5)*k,Vector2(1,4)*k),1,38,Color(.73,.76,.73))
	# Routed grip harness, rubber grommets and chassis retaining clips.
	var points: Array[Vector2]=[]
	for at: Vector2 in [Vector2(.078,.965),Vector2(.055,.944),Vector2(.045,.904),Vector2(.052,.86),Vector2(.072,.838)]:
		points.append(Vector2(1-at.x if mirror else at.x,at.y)*v)
	for i in points.size()-1:pipe(h,points[i],points[i+1],2.4*k,37,DARK)
	for i in [0,2,4]:disc(h,points[i],4*k,3*k,40,Color(.22,.26,.29))
	# A small inner service bay and separate bevelled hinge blocks.
	var x: float=v.x*(.5+side*.177)
	h._box(Rect2(x-10*k,v.y*.787,20*k,41*k),8,14,DARK)
	for n in 3:h._box(Rect2(x-7*k,v.y*.797+n*9*k,14*k,4*k),3,20,Color(.35,.41,.45))

static func pipe(h,a: Vector2,b: Vector2,radius: float,z: float,color: Color) -> void:
	var start:=vertex(h,a,z);var end:=vertex(h,b,z)
	var mesh:=CylinderMesh.new();mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=start.distance_to(end);mesh.radial_segments=10
	var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.8;mesh.material=mat
	var instance:=MeshInstance3D.new();instance.name="HarnessOrGuard";instance.mesh=mesh;instance.position=(start+end)*.5;instance.quaternion=Quaternion(Vector3.UP,start.direction_to(end));h.model.add_child(instance)

static func engrave(h,at: Vector2,z: float,caption: String,k: float) -> void:
	var mesh:=TextMesh.new();mesh.text=caption;mesh.font=ThemeDB.fallback_font;mesh.font_size=14;mesh.pixel_size=.42*k;mesh.depth=.18*k
	var material:=StandardMaterial3D.new();material.albedo_color=Color(.61,.68,.71);material.roughness=.9;material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var instance:=MeshInstance3D.new();instance.name="HardwareLegend";instance.mesh=mesh;instance.material_override=material;instance.position=vertex(h,at,z);h.model.add_child(instance)
