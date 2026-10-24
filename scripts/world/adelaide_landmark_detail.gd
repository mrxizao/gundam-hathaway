extends Node3D
## Additive non-colliding landmark skins; old launch geometry and mission anchors are untouched.
const Writer:=preload("res://scripts/world/adelaide_building_mesh.gd")
# Carry the pattern in the temporary surface key: vertex colour storage may clamp values above 1.
class WearWriter extends Writer:
	func quad(a:Vector3,b:Vector3,c:Vector3,d:Vector3,n:Vector3,role:int,row:int=0)->void:
		super.quad(a,b,c,d,n,role*16+row,0)
const SHADER:=preload("res://shaders/adelaide_landmark.gdshader")
const WEAR_NAMES:=["雨水纵向流痕","墙脚积灰","混凝土板缝","细裂纹","维修补片","双轮胎印","机油沉积","检修足迹","金属氧化","烟熏边缘","排水泛碱","屋面搭接"]
var materials:Dictionary={}
var region_writers:Dictionary={}
var landmark_meshes:Array[MeshInstance3D]=[]
var optional_meshes:Array[MeshInstance3D]=[]
var ruin_records:Array[Dictionary]=[]
var practical_lights:Array[SpotLight3D]=[]
var _light_clock:=0.0
var hangar_count:=0
var festival_count:=0
var triangles:=0
func _ready()->void:
	if not Settings.changed.is_connected(refresh_quality):Settings.changed.connect(refresh_quality)
func material(theme:int)->ShaderMaterial:
	if materials.has(theme):return materials[theme]
	var m:=ShaderMaterial.new();m.shader=SHADER;m.set_shader_parameter("theme",theme)
	m.set_shader_parameter("wear_masks",load("res://assets/materials/adelaide_pbr/adelaide_wear_masks.png"))
	for pair in [["concrete","concrete_wall_003"],["metal","painted_metal_shutter"],["roof","bitumen"]]:
		for channel in [["diff","diff"],["normal","nor_gl"],["orm","arm"]]:m.set_shader_parameter(pair[0]+"_"+channel[0],load("res://assets/materials/adelaide_pbr/"+pair[1]+"_"+channel[1]+"_2k.png"))
	materials[theme]=m;return m
func commit(writer:Object,label:String,at:Vector3,theme:int,optional:bool=false)->void:
	if writer.tools.is_empty():return
	var source:ArrayMesh=writer.finish_mesh()
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array();arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array();arrays[Mesh.ARRAY_TANGENT]=PackedFloat32Array();arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array();arrays[Mesh.ARRAY_TEX_UV2]=PackedVector2Array();arrays[Mesh.ARRAY_COLOR]=PackedColorArray()
	for surface in source.get_surface_count():
		var data:=source.surface_get_arrays(surface);var encoded:=int(source.surface_get_name(surface));var role:=encoded/16;var pattern:=posmod(encoded,16)
		for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:arrays[channel].append_array(data[channel])
		for color:Color in data[Mesh.ARRAY_COLOR]:arrays[Mesh.ARRAY_COLOR].append(Color(float(role)/8.0,float(pattern)/12.0,0,1))
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node:=MeshInstance3D.new();node.name=label;node.mesh=mesh;node.material_override=material(theme);node.position=at
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Existing collision-bearing structure already casts shadows. Overlays do not double the shadow pass.
	node.visibility_range_end=14000 if optional else 45000
	add_child(node);triangles+=arrays[Mesh.ARRAY_VERTEX].size()/3
	if optional:optional_meshes.append(node)
	else:landmark_meshes.append(node)
func add_hangar(index:int)->void:
	var w:=WearWriter.new();var at:=Vector3(-9480,26,(1500+index*540)*3)
	w.box(Vector3(0,1.04,0),Vector3(1042,.08,1000),7,7)
	# Preserve the entire open portal. Skins cover only the existing side/back slabs.
	for side:float in [-1,1]:
		w.box(Vector3(side*540,80,0),Vector3(36.3,160,1020.3),1,0)
		w.box(Vector3(side*520.9,14,0),Vector3(.5,28,1016),0,1)
	w.box(Vector3(0,80,492),Vector3(1080.3,160,36.3),1,0)
	# Real roof plane follows the original 42m ridge; no floating cap.
	for side:float in [-1,1]:
		var a:=Vector3(0,202.3,-547.5);var b:=Vector3(side*585,160.3,-547.5);var c:=b+Vector3(0,0,1095);var d:=a+Vector3(0,0,1095)
		w.quad(a,b,c,d,Vector3(side*42,585,0).normalized(),1,11)
	# Structural piers, panel seams and recessed clerestory remain beside the centre flight corridor.
	for side:float in [-1,1]:
		for bay in 7:
			var z:float=-465+bay*156
			w.box(Vector3(side*560,78,z),Vector3(9,156,5),1,2)
			w.box(Vector3(side*519.7,112,z),Vector3(.6,26,112),2)
			w.box(Vector3(side*558.45,112,z),Vector3(.3,26,112),2)
			w.box(Vector3(side*519,126,z),Vector3(2,2,116),1)
			w.box(Vector3(side*519,98,z),Vector3(2,2,116),1)
		# Exterior downpipe brackets and internal service panels.
		for z:float in [-444,444]:
			w.box(Vector3(side*590,76,z),Vector3(3,150,3),5,8)
			for y:float in [35,80,125]:w.box(Vector3(side*588,y,z),Vector3(8,1,8),1)
		for z:float in [70,200]:
			w.box(Vector3(side*480,15,z),Vector3(20,30,38),1,4)
			w.box(Vector3(side*469.7,16,z),Vector3(.4,22,31),5,8)
		# Apron tyre and oil patterns are material-only skins directly on the existing pad.
		w.box(Vector3(side*220,1.04,-660),Vector3(55,.08,250),7,5)
		w.box(Vector3(side*330,1.04,-515),Vector3(30,.08,38),7,6)
	# Reference: dark industrial roof panels, I-beams, crane rails and multi-level service bays.
	for column in 3:
		for bay in 4:w.box(Vector3(-310+column*310,162,-355+bay*220),Vector3(296,2.4,208),3,2)
	for z:float in [-450,-230,-10,210,430]:
		w.box(Vector3(0,153,z),Vector3(980,1.4,7),1)
		w.box(Vector3(0,158,z),Vector3(980,1.4,7),1)
		w.box(Vector3(0,155.5,z),Vector3(980,5,1.8),1)
	for side:float in [-1,1]:
		w.box(Vector3(side*108,151,0),Vector3(6,4,900),1,8)
		w.box(Vector3(side*330,146,0),Vector3(4,4,900),1,8)
		for z:float in [-260,260]:w.box(Vector3(side*85,147.5,z),Vector3(2.4,.5,68),8)
		for level in 3:
			var y:float=18+level*21
			w.box(Vector3(-112 if side<0 else 330,y,80),Vector3(42,2.2,270),1,7)
			w.box(Vector3(-90.5 if side<0 else 308.5,y+2.5,80),Vector3(.7,4.5,270),1)
			for z:float in [-54,214]:w.box(Vector3(-112 if side<0 else 330,y+2.5,z),Vector3(42,4.5,.7),1)
		for z:float in [-50,80,210]:w.box(Vector3(-130 if side<0 else 348,75,z),Vector3(4,150,4),1)
		# Low service carts and tool cabinets stay outside the 170m clear centre corridor.
		var cart:=Vector3(side*116,4,-115)
		w.box(cart,Vector3(10,4,17),1,4)
		w.box(cart+Vector3(0,3,-4),Vector3(8,4,7),1)
		w.box(cart+Vector3(0,3,-7.6),Vector3(6.6,2,.2),2)
		for wheel_side:float in [-1,1]:
			for z:float in [-5,5]:w.box(cart+Vector3(wheel_side*5, -1,z),Vector3(1.3,2.5,2.5),3)
		for z:float in [-155,245]:w.box(Vector3(side*130,5,z),Vector3(8,10,11),1,4)
		for z:float in [-275,270]:w.box(Vector3(side*103,1.10,z),Vector3(1,.08,110),5,8)
		# Two warm work lights per bay, with a global nearest-bay budget.
		var light:=SpotLight3D.new();light.name="HangarWork_%02d_%s"%[index+1,int(side)]
		light.position=at+Vector3(side*55,146,-90);light.rotation.x=-PI*.5
		light.light_color=Color(1,.82,.61);light.light_energy=6.0
		light.spot_range=185;light.spot_angle=40;light.spot_attenuation=.35
		light.shadow_enabled=false;light.distance_fade_enabled=true;light.distance_fade_begin=750;light.distance_fade_length=500
		light.set_meta("bay",index);add_child(light);practical_lights.append(light)
	# Bridge crane above existing portal headroom, with the trolley and hoist retracted.
	w.box(Vector3(0,150.5,140),Vector3(270,5,12),1,4)
	w.box(Vector3(0,147.5,140),Vector3(19,3,25),1,8)
	commit(w,"HangarSkin%02d"%(index+1),at,0);hangar_count+=1
func add_festival(index:int)->void:
	var at:=Vector3((300+(index-2)*100)*18,26,(-1700+absi(index-2)*40)*18)
	var w:=WearWriter.new();var width:=1710.;var depth:=2610.
	# Five original solid masses; no spanning decorative canopy is introduced.
	w.box(Vector3(0,35,0),Vector3(width+.24,70,depth+.24),0,0)
	w.box(Vector3(0,2,0),Vector3(width+.32,4,depth+.32),0,1)
	w.box(Vector3(0,70.22,0),Vector3(width,.4,depth),6,11)
	for side:float in [-1,1]:
		w.box(Vector3(0,34,side*(depth*.5+.20)),Vector3(width-18,29,.16),2)
		w.box(Vector3(side*(width*.5+.20),34,0),Vector3(.16,29,depth-18),2)
		for y:float in [18.5,49.5,68.5]:
			w.box(Vector3(0,y,side*(depth*.5+.35)),Vector3(width,1.6,.5),0,10)
			w.box(Vector3(side*(width*.5+.35),y,0),Vector3(.5,1.6,depth),0,10)
		for bay in 19:
			w.box(Vector3(-width*.5+12+bay*(width-24)/18,34,side*(depth*.5+.4)),Vector3(3.4,32,.6),0,2)
		for bay in 28:
			w.box(Vector3(side*(width*.5+.4),34,-depth*.5+12+bay*(depth-24)/27),Vector3(.6,32,3.4),0,2)
		# Entrance sits flush against the existing volume; visual-only, no new curb collision.
		w.box(Vector3(side*140,10,-depth*.5-.30),Vector3(34,20,.3),2)
		w.box(Vector3(side*140,21,-depth*.5-.45),Vector3(38,1.2,.3),1)
		# Low parapet is confined to its own roof and never bridges neighbouring buildings.
		w.box(Vector3(0,71.5,side*(depth*.5-1)),Vector3(width,3,2),0,10)
		w.box(Vector3(side*(width*.5-1),71.5,0),Vector3(2,3,depth),0,10)
	for x:float in [-width*.30,width*.30]:
		w.box(Vector3(x,70.48,-depth*.26),Vector3(42,.12,110),6,7)
		w.box(Vector3(x,73,-depth*.26),Vector3(22,5,24),1,4)
	commit(w,"FestivalSkin%02d"%(index+1),at,1);festival_count+=1
func add_ruin(p:Vector3,size:Vector3,index:int)->void:
	var origin:=Vector3(p.x*18,p.y,p.z*18);var extent:=Vector3(size.x*18,size.y,size.z*18)
	var key:=Vector2i(floori(origin.x/6000),floori(origin.z/6000))
	if not region_writers.has(key):region_writers[key]={"writer":WearWriter.new(),"origin":Vector3(key.x*6000,0,key.y*6000)}
	var row:Dictionary=region_writers[key];var w:Object=row.writer;var at:Vector3=origin-row.origin
	var h:=size.y*(.22+float(index%5)*.1)
	# Dark inside lining lies on the existing wall's exposed inner face.
	w.box(at+Vector3(-extent.x*.36+.18,h*.5,0),Vector3(.24,h,extent.z-.3),3,9)
	w.box(at+Vector3(extent.x*.27,h*.32,extent.z*.345-.18),Vector3(extent.x*.42,h*.64,.24),3,9)
	var segments:=clampi(int(ceil(extent.z/42.0)),14,24)
	for n in segments:
		var z:float=-extent.z*.5+(n+.5)*extent.z/segments
		var rise_a:=1.1+float(posmod(index*31+n*7,23))*.24
		var rise_b:=.8+float(posmod(index*17+n*13,19))*.27
		var x:float=-extent.x*.43
		# Slanted, uneven exposed edges; the original collision remnant remains below.
		fracture_piece(w,at+Vector3(x,h-.05,z),extent.x*.139,extent.z/segments*.995,rise_a,rise_b)
		if n%3==0:
			w.box(at+Vector3(x+extent.x*.035,h+rise_a+1.8,z),Vector3(.6,3.6,.6),5,8)
	# Ribs against the inner wall and exposed floor sections add depth, no spanning ceilings.
	for floor_index in 3:
		var y:float=h*(.22+floor_index*.24)
		w.box(at+Vector3(-extent.x*.325,y,0),Vector3(extent.x*.07,1.8,extent.z*.93),4,10)
	ruin_records.append({"origin":origin,"extent":extent,"index":index,"remnant":h})
func fracture_piece(w:Object,p:Vector3,width:float,depth:float,front_h:float,back_h:float)->void:
	var a:=width*.5;var b:=depth*.5
	var vertices:Array[Vector3]=[
		p+Vector3(-a,0,-b),p+Vector3(a,0,-b),p+Vector3(a,front_h,-b),p+Vector3(-a,front_h,-b),
		p+Vector3(-a,0,b),p+Vector3(a,0,b),p+Vector3(a,back_h,b),p+Vector3(-a,back_h,b)]
	for face:Array in [[0,3,2,1],[4,5,6,7],[0,4,7,3],[1,2,6,5],[3,7,6,2],[0,1,5,4]]:
		var normal:Vector3=(vertices[face[1]]-vertices[face[0]]).cross(vertices[face[2]]-vertices[face[0]]).normalized()
		w.quad(vertices[face[0]],vertices[face[1]],vertices[face[2]],vertices[face[3]],normal,4,3)
func finish()->void:
	for n in 6:add_hangar(n)
	for n in 5:add_festival(n)
	for key:Vector2i in region_writers:
		var row:Dictionary=region_writers[key];commit(row.writer,"RuinRegion_%s_%s"%[key.x,key.y],row.origin,2,true)
	region_writers.clear();refresh_quality()
func refresh_quality()->void:
	var quality:=clampi(Settings.effects_quality,0,2)
	refresh_lights()
	for m:ShaderMaterial in materials.values():m.set_shader_parameter("detail_quality",quality)
	for node:MeshInstance3D in optional_meshes:
		node.visible=quality>0;node.visibility_range_end=6500 if quality==2 else 3500
func _process(delta:float)->void:
	_light_clock+=delta
	if _light_clock>=.12:_light_clock=0;refresh_lights()
func refresh_lights()->void:
	var camera:=get_viewport().get_camera_3d()
	var quality:=clampi(Settings.effects_quality,0,2)
	var closest:=-1;var nearest:=INF
	if is_visible_in_tree() and camera!=null and quality>0:
		for light:SpotLight3D in practical_lights:
			var distance:=camera.global_position.distance_squared_to(light.global_position)
			if distance<nearest:nearest=distance;closest=int(light.get_meta("bay"))
	var shown:=0;var budget:=2 if quality==2 else 1 if quality==1 else 0
	for light:SpotLight3D in practical_lights:
		var active:=int(light.get_meta("bay"))==closest and nearest<1250.0*1250.0 and shown<budget
		light.visible=active
		if active:shown+=1
