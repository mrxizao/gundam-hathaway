extends RefCounted
## MS-06R: five bounded forward monitors, sealed steel shell, circular CRT bank.
const STEEL=Color(.055,.060,.068)
const EDGE=Color(.115,.12,.13)
const BLACK=Color(.006,.008,.011)
const PLATE=Color(.09,.09,.105)
static func layout(v:Vector2)->Dictionary:
	return {"center":Rect2(v*Vector2(.42,.585),v*Vector2(.16,.14)),"dial_l":Rect2(v*Vector2(.308,.59),v*Vector2(.064,.102)),"dial_r":Rect2(v*Vector2(.628,.59),v*Vector2(.064,.102)),"lower_l":Rect2(v*Vector2(.265,.718),v*Vector2(.085,.13)),"lower_r":Rect2(v*Vector2(.65,.718),v*Vector2(.085,.13))}
static func plate(h,points:Array,z:float,color:Color)->void:
	# Raised inset face, bevel and extruded sidewall give every access panel real edge depth.
	var v:Vector2=h.last_size;var k:float=v.y/720
	var outer:Array[Vector3]=[];var inner:Array[Vector3]=[]
	var center:=Vector3.ZERO
	for p:Vector2 in points:
		var at:=Vector3(p.x*v.x-v.x/2,v.y/2-p.y*v.y,z)
		outer.append(at);center+=at
	center/=points.size()
	for at:Vector3 in outer:
		var ratio:=clampf(3*k/maxf(at.distance_to(center),1),0,.20)
		inner.append(at.lerp(center,ratio)+Vector3(0,0,4*k))
	var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var face_center:=center+Vector3(0,0,4*k)
	for i in outer.size():
		var j: int=(i+1)%outer.size()
		var a:Vector3=outer[i];var b:Vector3=outer[j];var ai:Vector3=inner[i];var bi:Vector3=inner[j]
		for triangle in [[face_center,bi,ai],[a,b,bi],[a,bi,ai],[a-Vector3(0,0,12*k),b-Vector3(0,0,12*k),b],[a-Vector3(0,0,12*k),b,a]]:
			for vertex:Vector3 in triangle:tool.add_vertex(vertex)
	tool.generate_normals()
	var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.72;mat.metallic=.25;mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	var instance:=MeshInstance3D.new();instance.mesh=tool.commit();instance.material_override=mat;h.model.add_child(instance)
static func box(h,x:float,y:float,w:float,t:float,z:float,color:Color,depth:float=8)->void:
	h._box(Rect2(h.last_size*Vector2(x,y),h.last_size*Vector2(w,t)),depth,z,color)
static func circle(h,at:Vector2,r:float,z:float,vent:bool)->void:
	var v:Vector2=h.last_size
	var ring:=TorusMesh.new();ring.inner_radius=r*.89;ring.outer_radius=r;ring.rings=32;ring.ring_segments=8
	var mat:=StandardMaterial3D.new();mat.albedo_color=EDGE;mat.roughness=.68;mat.metallic=.35;ring.material=mat
	var instance:=MeshInstance3D.new();instance.mesh=ring;instance.position=Vector3(at.x-v.x/2,v.y/2-at.y,z);instance.rotation.x=PI/2;h.model.add_child(instance)
	var disc:=CylinderMesh.new();disc.top_radius=r*.89;disc.bottom_radius=r*.89;disc.height=5;disc.radial_segments=32;disc.rings=1
	var dark:=StandardMaterial3D.new();dark.albedo_color=BLACK;dark.roughness=.7;disc.material=dark
	var face:=MeshInstance3D.new();face.mesh=disc;face.position=instance.position-Vector3(0,0,2);face.rotation.x=PI/2;h.model.add_child(face)
	if vent:
		for n in range(-3,4):
			var yy:=float(n)*r*.2;var half:=sqrt(maxf(0,r*r*.70-yy*yy))
			h._box(Rect2(at+Vector2(-half,yy),Vector2(half*2,2)),2,z+3,STEEL)
static func build(h)->void:
	var v:Vector2=h.last_size;var k:=v.y/720.0
	h.model.name="PsychoZaku_SealedFiveMonitorCockpit"
	h.surface.modules=layout(v)
	# Overscan seals the image edges during the small camera-space cabin bank.
	box(h,-.12,-.15,1.24,.155,-30,BLACK,8)
	box(h,-.12,.992,1.24,.16,-30,BLACK,8)
	box(h,-.12,-.15,.125,1.30,-30,BLACK,8)
	box(h,.995,-.15,.125,1.30,-30,BLACK,8)
	# Solid roof: not a spherical panorama. The five monitor apertures share the live scene.
	plate(h,[Vector2(0,0),Vector2(1,0),Vector2(1,.055),Vector2(.81,.14),Vector2(.62,.18),Vector2(.38,.18),Vector2(.19,.14),Vector2(0,.055)],-15,BLACK)
	plate(h,[Vector2(.02,0),Vector2(.98,0),Vector2(.95,.04),Vector2(.79,.115),Vector2(.62,.15),Vector2(.38,.15),Vector2(.21,.115),Vector2(.05,.04)],-2,STEEL)
	# Top armour tiles, seams, fasteners and overhead conduit runs.
	for n in 13:
		var x:=.025+n*.073
		var lower:=.065+.065*sin((x+.035)*PI)
		box(h,x,.004,.066,lower,3,PLATE,12)
		for dx in [.005,.058]:
			box(h,x+dx,.012,.003,.004,12,BLACK,2)
			box(h,x+dx,lower-.009,.003,.004,12,BLACK,2)
	for row in 2:
		box(h,.28,.108+row*.02,.44,.008,16,EDGE,9)
		for n in 6:box(h,.29+n*.077,.104+row*.02,.009,.017,21,BLACK,5)
	box(h,.455,.042,.09,.055,25,BLACK,14)
	box(h,.464,.05,.072,.036,36,STEEL,5)
	for yy in [.11,.131]:pipe(h,Vector2(.255,yy),Vector2(.745,yy),3*k,30)
	for mirror in [false,true]:
		var points:Array=[Vector2(.03,.023),Vector2(.17,.063),Vector2(.23,.118),Vector2(.26,.12)]
		for i in points.size()-1:
			var a:Vector2=points[i];var z:Vector2=points[i+1]
			if mirror:a.x=1-a.x;z.x=1-z.x
			pipe(h,a,z,4*k,29)
	# Angled outer mullions plus the two inner jambs create five flat screens.
	for mirror in [false,true]:
		var pts:Array=[]
		for p:Vector2 in [Vector2(.19,.135),Vector2(.198,.137),Vector2(.178,.54),Vector2(.169,.54)]:pts.append(Vector2(1-p.x if mirror else p.x,p.y))
		plate(h,pts,15,EDGE)
		var inner:=.382 if not mirror else .613
		box(h,inner,.172,.005,.368,15,BLACK,11)
		box(h,.002 if not mirror else .989,.04,.009,.515,22,STEEL,18)
	box(h,0,.539,1,.018,22,BLACK,20)
	box(h,0,.557,1,.008,28,EDGE,11)
	box(h,0,.565,1,.44,-25,BLACK,6)
	# Sloping console wings rise toward the front monitor sill, then wrap back around the pilot.
	plate(h,[Vector2(0,.56),Vector2(.29,.56),Vector2(.4,.72),Vector2(.34,1),Vector2(0,1)],-6,STEEL)
	plate(h,[Vector2(1,.56),Vector2(.71,.56),Vector2(.6,.72),Vector2(.66,1),Vector2(1,1)],-6,STEEL)
	plate(h,[Vector2(.28,.76),Vector2(.41,.735),Vector2(.59,.735),Vector2(.72,.76),Vector2(.83,1),Vector2(.17,1)],-10,BLACK)
	plate(h,[Vector2(.365,.775),Vector2(.635,.775),Vector2(.785,1),Vector2(.215,1)],1,PLATE)
	plate(h,[Vector2(.4,.79),Vector2(.6,.79),Vector2(.68,.935),Vector2(.32,.935)],10,EDGE)
	plate(h,[Vector2(.32,.947),Vector2(.68,.947),Vector2(.725,1),Vector2(.275,1)],13,PLATE)
	# Centre radar sits in a broad hexagonal coaming, with a small ledge underneath.
	plate(h,[Vector2(.411,.576),Vector2(.589,.576),Vector2(.605,.61),Vector2(.602,.707),Vector2(.588,.734),Vector2(.412,.734),Vector2(.398,.707),Vector2(.395,.61)],18,EDGE)
	box(h,.411,.739,.178,.016,26,BLACK,18)
	box(h,.432,.744,.136,.006,37,PLATE,5)
	for side in [-1.0,1.0]:
		# Three stepped circular monitor/vent pods, not one flat row.
		for i in 3:
			var at:=v*Vector2(.5+side*(.272+i*.085),.607+i*.026)
			var r:float=(.041+i*.008)*v.y
			var pod_start:int=h.model.get_child_count()
			var housing:=Rect2(at-Vector2(r+10*k,r+12*k),Vector2(r*2+20*k,r*2+24*k))
			h._shell(housing,25*k,18)
			h._box(housing.grow(-5*k),9,30,BLACK)
			circle(h,at,r,43,true)
			for dx in [-1.0,1.0]:
				for dy in [-1.0,1.0]:screw(h,at+Vector2(dx,dy)*(r+4*k),2*k,38)
			var pod_pivot:=Vector3(at.x-v.x/2,v.y/2-at.y,40)
			var pod_turn:=Basis(Vector3.UP,deg_to_rad(-side*(8+i*8)))*Basis(Vector3.RIGHT,deg_to_rad(-5))
			var pod_transform:=Transform3D(pod_turn,pod_pivot-pod_turn*pod_pivot+Vector3(0,0,24))
			for part:Node3D in h.model.get_children().slice(pod_start):part.transform=pod_transform*part.transform
		# Broad, solid armour covers replace the rectangular monitors and the two control sticks.
		for panel in [
			[Vector2(.014,.77),Vector2(.155,.716),Vector2(.252,.788),Vector2(.309,.904),Vector2(.296,.986),Vector2(.018,1)],
			[Vector2(.028,.783),Vector2(.153,.737),Vector2(.229,.798),Vector2(.267,.875),Vector2(.025,.914)],
			[Vector2(.027,.928),Vector2(.272,.890),Vector2(.294,.974),Vector2(.03,.99)],
			[Vector2(.218,.865),Vector2(.269,.845),Vector2(.36,.992),Vector2(.298,1)]
		]:
			var mirrored:Array=[]
			for q:Vector2 in panel:mirrored.append(Vector2(q.x if side<0 else 1-q.x,q.y))
			plate(h,mirrored,36 if panel.size()==6 else 48,Color(.12,.115,.13))
		# Bolts, small recessed seams and a protected grab recess follow the sloping covers.
		for q:Vector2 in [Vector2(.039,.795),Vector2(.15,.758),Vector2(.231,.816),Vector2(.25,.867),Vector2(.043,.946),Vector2(.264,.956)]:
			var qx:float=q.x if side<0 else 1-q.x
			screw(h,v*Vector2(qx,q.y),1.8*k,62)
		var recessed_x:float=.068 if side<0 else .854
		box(h,recessed_x,.936,.078,.01,59,BLACK,5)
		box(h,recessed_x+.006,.937,.066,.004,64,EDGE,3)
		# Tangible switch rows, toggle stalks and guarded orange warning lamps.
		for row in 2:
			for i in 7:
				var xx:float=.05+i*.019 if side<0 else .829+i*.019
				box(h,xx,.724+row*.018,.013,.012,39,BLACK,7)
				box(h,xx+.004,.725+row*.018,.004,.007,47,EDGE,6)
				if row==0 and i in [0,3,6]:lamp(h,xx+.002,.725,.009,.003,53)
		var xx:=.385 if side<0 else .592
		box(h,xx,.61,.024,.087,29,BLACK,12)
		for n in 8:box(h,xx+.003,.615+n*.009,.018,.003,38,STEEL,2)
		# Exposed conduits curve around the outer side racks and are clamped to the console.
		var px:float=.018 if side<0 else .982
		pipe(h,Vector2(px,.705),Vector2(px,.944),4*k,37)
		pipe(h,Vector2(px+side*.009,.717),Vector2(px+side*.009,.954),3*k,34)
		for n in 5:box(h,px-.006,.728+n*.045,.012,.009,44,EDGE,5)
	# One central radar and four circular CRT instruments; no rectangular side displays.
	for key in h.surface.modules:
		var r:Rect2=h.surface.modules[key]
		var first:int=h.model.get_child_count()
		if key in ["dial_l","dial_r","lower_l","lower_r"]:
			circle(h,r.get_center(),minf(r.size.x,r.size.y)*.54,37,false)
		else:
			h._shell(r.grow(7*k),17,41)
			for x in [r.position.x-3*k,r.end.x+3*k]:
				for y in [r.position.y-3*k,r.end.y+3*k]:screw(h,Vector2(x,y),1.8*k,54)
		h._screen(r,58)
		var screen:ShaderMaterial=h.surfaces.back()
		screen.shader=preload("res://shaders/psycho_zaku_crt.gdshader")
		screen.set_shader_parameter("display_tex",h.surface_view.get_texture())
		screen.set_shader_parameter("region",Vector4(r.position.x/v.x,r.position.y/v.y,r.size.x/v.x,r.size.y/v.y))
		screen.set_shader_parameter("round_screen",key in ["dial_l","dial_r","lower_l","lower_r"])
	# Three separate floor access plates, recessed fasteners, raised seams and traction slats.
	for side in [-1.0,1.0]:
		pipe(h,Vector2(.5+side*.104,.802),Vector2(.5+side*.195,.947),2*k,20)
		for n in 4:screw(h,v*Vector2(.5+side*(.107+n*.026),.807+n*.044),1.5*k,22)
	for n in 9:box(h,.355+n*.032,.987,.023,.004,22,BLACK,2)
	# Consolidate static metal geometry by finish; the live screen materials stay separate.
	batch_static(h)
	expand_sight(h)
# Raise the roof and lower the console without opening the sealed cockpit.
static func sight_y(y:float)->float:
	if y <= .18:return y * .60
	if y <= .565:return .108 + (y - .18) * (.592 / .385)
	return .70 + (y - .565) * (.30 / .435)
static func expand_sight(h)->void:
	var v:Vector2=h.last_size
	for node in h.model.get_children():
		if not node is MeshInstance3D:continue
		var result:=ArrayMesh.new()
		for surface in node.mesh.get_surface_count():
			var arrays:Array=node.mesh.surface_get_arrays(surface)
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			for i in vertices.size():
				var world:Vector3=node.transform*vertices[i]
				var y:float=.5-world.y/v.y
				world.y=(.5-sight_y(y))*v.y
				vertices[i]=world
			arrays[Mesh.ARRAY_VERTEX]=vertices
			var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			for i in normals.size():normals[i]=(node.basis*normals[i]).normalized()
			arrays[Mesh.ARRAY_NORMAL]=normals
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			result.surface_set_material(surface,node.mesh.surface_get_material(surface))
		node.mesh=result;node.transform=Transform3D.IDENTITY
	var index:=0
	for key in h.surface.modules:
		var r:Rect2=h.surface.modules[key]
		var top:=sight_y(r.position.y/v.y)*v.y
		var bottom:=sight_y(r.end.y/v.y)*v.y
		r=Rect2(r.position.x,top,r.size.x,bottom-top)
		h.surface.modules[key]=r
		h.surfaces[index].set_shader_parameter("region",Vector4(r.position.x/v.x,r.position.y/v.y,r.size.x/v.x,r.size.y/v.y))
		index+=1

static func batch_static(h)->void:
	var groups:Dictionary={}
	for node in h.model.get_children():
		if not node is MeshInstance3D:continue
		var mat:Material=node.material_override if node.material_override!=null else node.mesh.surface_get_material(0)
		if not mat is StandardMaterial3D:continue
		var key:String=mat.albedo_color.to_html()+str(mat.cull_mode)
		if not groups.has(key):groups[key]={"tool":SurfaceTool.new(),"mat":mat,"nodes":[]};groups[key].tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		groups[key].tool.append_from(node.mesh,0,node.transform);groups[key].nodes.append(node)
	for key in groups:
		var group:Dictionary=groups[key];var merged:=MeshInstance3D.new();merged.name="SteelBatch_"+str(key);merged.mesh=group.tool.commit();merged.material_override=group.mat;h.model.add_child(merged)
		for node in group.nodes:h.model.remove_child(node);node.queue_free()

static func pipe(h,from:Vector2,to:Vector2,radius:float,z:float)->void:
	var v:Vector2=h.last_size
	var a:=Vector3(from.x*v.x-v.x/2,v.y/2-from.y*v.y,z)
	var b:=Vector3(to.x*v.x-v.x/2,v.y/2-to.y*v.y,z)
	var mesh:=CylinderMesh.new();mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=a.distance_to(b);mesh.radial_segments=10;mesh.rings=1
	var mat:=StandardMaterial3D.new();mat.albedo_color=EDGE;mat.metallic=.4;mat.roughness=.65;mesh.material=mat
	var instance:=MeshInstance3D.new();instance.mesh=mesh;instance.position=(a+b)*.5;instance.quaternion=Quaternion(Vector3.UP,a.direction_to(b));h.model.add_child(instance)

static func screw(h,at:Vector2,radius:float,z:float)->void:
	var mesh:=CylinderMesh.new();mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=2;mesh.radial_segments=8;mesh.rings=1
	var mat:=StandardMaterial3D.new();mat.albedo_color=EDGE;mat.roughness=.65;mat.metallic=.4;mesh.material=mat
	var instance:=MeshInstance3D.new();instance.mesh=mesh;instance.rotation.x=PI/2;instance.position=Vector3(at.x-h.last_size.x/2,h.last_size.y/2-at.y,z);h.model.add_child(instance)
	h._box(Rect2(at-Vector2(radius*.65,.5),Vector2(radius*1.3,1)),1,z+2,BLACK)
static func lamp(h,x:float,y:float,w:float,t:float,z:float)->void:
	box(h,x,y,w,t,z,Color(.45,.13,.035),2)
	var node:MeshInstance3D=h.model.get_child(h.model.get_child_count()-1)
	var mat:StandardMaterial3D=node.mesh.surface_get_material(0)
	mat.emission_enabled=true;mat.emission=Color(1,.14,.025);mat.emission_energy_multiplier=.45
