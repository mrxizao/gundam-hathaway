extends Node3D
## Game-scale Adelaide: independent land/road/parcel plan and cinematic-ready airport.
const HORIZONTAL_SCALE := 3.0
const MAP_SCALE := 9.0
const CITY_SCALE := 18.0
var geometry_scale := MAP_SCALE
var material_kind := 0
const SurfaceCatalog := preload("res://scripts/world/adelaide_surface_catalog.gd")
var surface_family := 0
var trial_surfaces_enabled := true
var _surface_materials: Array[ShaderMaterial] = []
var parcel_records: Array[Dictionary] = []
## Return true after supplying a replacement visual; legacy collision still builds.
var parcel_visual_factory: Callable
var emit_visual_geometry := true
var building_modules_enabled:=true
var building_library:Node3D
var _preserve_roof_y:=INF
const BuildingLibrary:=preload("res://scripts/world/adelaide_building_library.gd")
const LandmarkDetail:=preload("res://scripts/world/adelaide_landmark_detail.gd")
var landmark_details_enabled:=true
var landmark_detail:Node3D
const CityMaterial:=preload("res://scripts/world/adelaide_city_material.gd")
var building_style_counts:Array[int]=[0,0,0,0,0,0]
var _city_shared_materials:Array[ShaderMaterial]=[]
const AIRPORT := Rect2(-5500,200,3100,5800)
const RUNWAY := Rect2(-5050,450,120,5000)
const FESTIVAL := Vector3(300,26,-1700)
var roads: Array[Rect2] = []
var buildings: Array[Rect2] = []
var rng := RandomNumberGenerator.new()
var batches: Dictionary = {}
var solid := PackedVector3Array()
var serial := 0
var damaged_buildings := 0
var bridge_sites: Array[float] = []
# Additive, non-colliding details use local batches instead of one city-wide AABB.
var detail_region := ""
var airport_detail_bays := 0
var detailed_roofs := 0
var roadside_modules := 0
var impact_sites: Array[Vector2] = [Vector2(-900,-400),Vector2(1700,1200),Vector2(500,-1700)]

static func height_at(x: float,z: float) -> float:
	var ground := base_height(x/MAP_SCALE,z/MAP_SCALE)
	var cx := x/CITY_SCALE
	var cz := z/CITY_SCALE
	if cx > -3375 and cx < 4125 and cz > -2062.5 and cz < -750:
		return river_ground(cx,cz)
	return ground

static func river_z(x: float) -> float:
	return -1450.0+sin(x/520.0)*115.0+sin(x/1300.0)*65.0

static func river_ground(x: float,z: float) -> float:
	var distance := absf(z-river_z(x))
	return minf(base_height(x*CITY_SCALE/MAP_SCALE,z*CITY_SCALE/MAP_SCALE),lerpf(-18.0,25.0,smoothstep(48.0,115.0,distance)))

static func base_height(x: float,z: float) -> float:
	if x < -6300: return -40.0
	if x < -6050: return lerpf(-40,25,(x+6300)/250.0)
	var hill := smoothstep(8000,14000,x)*450.0
	return 25.0+hill*(0.65+0.35*sin(z/1200.0)*sin(x/1700.0))

func build() -> void:
	prepare()
	land()
	airport()
	city()
	forest()
	finish()

func build_staged() -> void:
	prepare()
	land()
	await get_tree().process_frame
	airport()
	await get_tree().process_frame
	city()
	await get_tree().process_frame
	forest()
	finish()

func prepare() -> void:
	name = "Adelaide"
	if not Settings.changed.is_connected(refresh_surface_quality):
		Settings.changed.connect(refresh_surface_quality)
	if landmark_details_enabled:
		landmark_detail=LandmarkDetail.new();landmark_detail.name="AdelaideLandmarkDetail";add_child(landmark_detail)
	rng.seed = 20261013
	if building_modules_enabled and not parcel_visual_factory.is_valid():
		building_library=BuildingLibrary.new();building_library.name="AdelaideBuildingModules";add_child(building_library)
	# Unequal historical blocks, offsets and suburban roads; parcels read this same plan.
	for x: float in [-1830,-1390,-860,-260,410,1170,1780,2460,3280]:
		roads.append(Rect2(x-12,-3200,24,6100))
	for z: float in [-2940,-2420,-1950,-1280,-620,80,690,1430,2180,2800]:
		roads.append(Rect2(-1950,z-12,5400,24))
	roads.append(Rect2(-1390,480,620,14))
	

	# Short secondary lanes break the oversized uniform street grid into districts.
	for n in 13:
		var x := -1540.0+n*320
		var z := -2600.0+float((n*7)%9)*490
		roads.append(Rect2(x-4,z,8,850+float(n%3)*170))
	# Expanded city roads must not cut through the unchanged military reservation.
	var reserve := Rect2(AIRPORT.position*(HORIZONTAL_SCALE/CITY_SCALE),AIRPORT.size*(HORIZONTAL_SCALE/CITY_SCALE))
	var clipped: Array[Rect2] = []
	for road in roads:
		if not road.intersects(reserve):
			clipped.append(road)
			continue
		var overlap := road.intersection(reserve)
		if road.size.x > road.size.y:
			if overlap.position.x>road.position.x: clipped.append(Rect2(road.position,Vector2(overlap.position.x-road.position.x,road.size.y)))
			if overlap.end.x<road.end.x: clipped.append(Rect2(Vector2(overlap.end.x,road.position.y),Vector2(road.end.x-overlap.end.x,road.size.y)))
		else:
			if overlap.position.y>road.position.y: clipped.append(Rect2(road.position,Vector2(road.size.x,overlap.position.y-road.position.y)))
			if overlap.end.y<road.end.y: clipped.append(Rect2(Vector2(road.position.x,overlap.end.y),Vector2(road.size.x,road.end.y-overlap.end.y)))
	# River corridor: roads terminate at banks; through roads use explicit bridges.
	var bank_roads: Array[Rect2] = []
	for road in clipped:
		if road.size.y>road.size.x:
			var y := river_z(road.get_center().x)
			if road.position.y<y-135 and road.end.y>y+135:
				bank_roads.append(Rect2(road.position,Vector2(road.size.x,y-135-road.position.y)))
				bank_roads.append(Rect2(Vector2(road.position.x,y+135),Vector2(road.size.x,road.end.y-y-135)))
				bridge_sites.append(road.get_center().x)
			else: bank_roads.append(road)
		else:
			var count := maxi(1,int(ceil(road.size.x/40.0)))
			for n in count:
				var width := road.size.x/count
				var part := Rect2(road.position+Vector2(n*width,0),Vector2(width,road.size.y))
				if absf(part.get_center().y-river_z(part.get_center().x))>145: bank_roads.append(part)
	roads = bank_roads

func land() -> void:
	geometry_scale = MAP_SCALE
	surface_family = SurfaceCatalog.GRASS
	# Extends beyond the match spawn ring, with a continuous west-facing coastline.
	for ix in 80:
		for iz in 80:
			var x := -15000.0+ix*375
			var z := -15000.0+iz*375
			# Replace this aligned strip with a denser carved river mesh below.
			if x>=-6750 and x<8250 and z>=-4125 and z< -1500: continue
			var pts: Array[Vector3] = []
			for offset: Vector2 in [Vector2.ZERO,Vector2(375,0),Vector2(375,375),Vector2(0,375)]:
				pts.append(Vector3(x+offset.x,base_height(x+offset.x,z+offset.y),z+offset.y))
			var color := Color(0.40,0.47,0.29) if x > -6050 else Color(0.68,0.64,0.45)
			quad(pts[3],pts[2],pts[1],pts[0],color,true)
	build_river()
	geometry_scale = CITY_SCALE
	material_kind = 4
	for road in roads:
		surface_family = SurfaceCatalog.ASPHALT
		box(Vector3(road.get_center().x,25.4,road.get_center().y),Vector3(road.size.x,0.6,road.size.y),Color(0.20,0.21,0.20),false)
		surface_family = 0
		# Sparse dashed lane marks keep street direction legible from low altitude.
		var horizontal := road.size.x > road.size.y
		var length := road.size.x if horizontal else road.size.y
		for n in int(length/55):
			var p := Vector3(road.position.x+float(n)*55,25.8,road.get_center().y) if horizontal else Vector3(road.get_center().x,25.8,road.position.y+float(n)*55)
			box(p,Vector3(16,0.15,0.6) if horizontal else Vector3(0.6,0.15,16),Color(0.78,0.76,0.60),false)

	road_details()

func airport() -> void:
	material_kind = 0
	geometry_scale = HORIZONTAL_SCALE
	var airport_root := Node3D.new()
	airport_root.name = "AdelaideAirport"
	add_child(airport_root)
	surface_family = SurfaceCatalog.GRASS
	box(Vector3(-3950,25.3,3100),Vector3(3100,0.5,5800),Color(0.36,0.40,0.28),false)
	surface_family = SurfaceCatalog.ASPHALT
	material_kind = 4
	box(Vector3(RUNWAY.get_center().x,26, RUNWAY.get_center().y),Vector3(120,1,5000),Color(0.12,0.14,0.15),true)
	box(Vector3(-4670,26,2950),Vector3(65,1,5000),Color(0.22,0.24,0.24),true)
	material_kind = 10
	surface_family = 0
	box(Vector3(-3800,26,3250),Vector3(1550,1,3100),Color(0.40,0.42,0.41),true)
	material_kind = 6
	for n in 49:
		box(Vector3(-4990,26.7,530+n*100),Vector3(3,0.2,42),Color(0.91,0.90,0.80),false)
	for z: float in [620,5260]:
		for n in 8: box(Vector3(-5035+n*13,26.8,z),Vector3(7,0.2,95),Color(0.94,0.93,0.86),false)
	material_kind = 4
	surface_family = SurfaceCatalog.ASPHALT
	for z: float in [1400,2900,4400]:
		box(Vector3(-4560,26, z),Vector3(900,1,65),Color(0.24,0.26,0.25),true)
	box(Vector3(-6505,25.9,2920),Vector3(3710,0.8,84),Color(0.20,0.21,0.20),false)
	surface_family = 0
	# Six open-front hangars: no front wall across the MS departure corridor.
	for n in 6:
		var z := 1500.0+n*540
		var x := -3160.0
		material_kind = 11
		for dx: float in [-180,180]: box(Vector3(x+dx,106,z),Vector3(12,160,340),Color(0.64,0.66,0.61),true)
		box(Vector3(x,106,z+164),Vector3(360,160,12),Color(0.54,0.57,0.54),true)
		hangar_details(x,z,n+1)
		material_kind = 10
		box(Vector3(x,26.8,z-220),Vector3(270,0.2,230),Color(0.30,0.33,0.32),false)
		material_kind = 6
		for dx: float in [-130,130]: box(Vector3(x+dx,27,z-220),Vector3(3,0.3,230),Color(0.89,0.71,0.23),false)
		marker(airport_root,"MSStand%02d" % (n+1),Vector3(x,27,z-30))
		marker(airport_root,"HangarExit%02d" % (n+1),Vector3(x,27,z-360))
		material_kind = 5
		var crane := Vector3(x+150,70,z-120)
		box(crane,Vector3(8,86,8),Color(0.65,0.55,0.29),true)
		box(crane+Vector3(-45,43,0),Vector3(95,7,8),Color(0.65,0.55,0.29),true)
	material_kind = 0
	# Terminal, control tower, warehouses sit outside runway and launch route.
	box(Vector3(-2750,50,800),Vector3(400,48,220),Color(0.73,0.71,0.63),true)
	box(Vector3(-2640,85,1120),Vector3(38,118,38),Color(0.67,0.65,0.57),true)
	box(Vector3(-2640,148,1120),Vector3(65,20,65),Color(0.23,0.35,0.37),true)
	for n in 7: box(Vector3(-2850,45,4900+n*125),Vector3(260,38,85),Color(0.55,0.56,0.51),true)
	marker(airport_root,"LaunchStart",Vector3(-4200,28,4300))
	marker(airport_root,"LaunchHold",Vector3(-4670,28,4300))
	marker(airport_root,"LaunchRunway",Vector3(-4990,28,4300))
	marker(airport_root,"LaunchAirborne",Vector3(-4990,220,1800))
	marker(airport_root,"LaunchDeparture",Vector3(-4990,900,-400))
	marker(airport_root,"CameraHangar",Vector3(-3500,95,900))
	marker(airport_root,"CameraRunway",Vector3(-5200,85,3600))
	marker(airport_root,"CameraDeparture",Vector3(-5400,350,1600))
	var path := Path3D.new()
	path.name = "MSSortiePath"
	path.curve = Curve3D.new()
	for point: Vector3 in [Vector3(-4200,28,4300),Vector3(-4670,28,4300),Vector3(-4990,28,4300),Vector3(-4990,220,1800),Vector3(-4990,900,-400)]: path.curve.add_point(Vector3(point.x*HORIZONTAL_SCALE,point.y,point.z*HORIZONTAL_SCALE))
	airport_root.add_child(path)
	military_base_details(airport_root)
	cinematic_airport_details()

func city() -> void:
	material_kind = 0
	geometry_scale = CITY_SCALE
	# Explicit cultural landmark and reserved parkland instead of buildings in every cell.
	for n in 5:
		var pos := FESTIVAL+Vector3((n-2)*100,35,absf(float(n-2))*40)
		# Remove the oversized decorative white canopy; mission marker and collision stay.
		material_kind = 1
		box(pos,Vector3(95,70,145),Color(0.52,0.55,0.56),true)
	material_kind = 0
	marker(self,"FestivalCentre",FESTIVAL)
	for iz in 71:
		for ix in 66:
			var x := -1900.0+ix*80+rng.randf_range(-14,14)
			var z := -2850.0+iz*80+rng.randf_range(-14,14)
			var park_r := Vector2(x/2600,z/2800).length()
			# North Adelaide remains lower and more open than the southern business core.
			if z<river_z(x)-150 and rng.randf()<0.22: continue
			if park_r > 0.86 and park_r < 1.02: continue
			if Vector2(x-FESTIVAL.x,z-FESTIVAL.z).length()<460: continue
			var district := Vector2(x/1400,z/1600).length()
			var empty_chance := 0.18 if district<1.0 else 0.37
			if rng.randf()<empty_chance: continue
			var width := rng.randf_range(25,49)
			var depth := rng.randf_range(28,53)
			var rect := Rect2(x-width/2,z-depth/2,width,depth)
			if not parcel_clear(rect): continue
			buildings.append(rect)
			var h := rng.randf_range(240,520)
			if absf(x)<1100 and absf(z)<1000 and rng.randf()<0.12: h=rng.randf_range(900,1600)
			var color := Color(0.58,0.49,0.37).lerp(Color(0.77,0.72,0.60),rng.randf())
			box(Vector3(x,25.18,z),Vector3(width+3,0.3,depth+3),Color(0.42,0.40,0.34),false)
			if z<river_z(x): h *= 0.72
			var parcel: Dictionary = SurfaceCatalog.parcel_record(ix,iz,rect,h,color)
			parcel_records.append(parcel)
			var previous_visual := emit_visual_geometry
			var blast := damage_strength(Vector2(x,z))
			var damaged:=blast > 0.15 and float(posmod(ix*37+iz*71,100))/100.0 < blast
			parcel["damaged"]=damaged
			if not damaged:building_style_counts[BuildingLibrary.style_for(parcel)]+=1
			if parcel_visual_factory.is_valid():
				emit_visual_geometry = not bool(parcel_visual_factory.call(self,parcel))
			elif is_instance_valid(building_library):
				emit_visual_geometry=not building_library.replace(parcel)
			_preserve_roof_y=25.0+h if not emit_visual_geometry else INF
			if damaged:
				ruined_building(Vector3(x,25,z),Vector3(width,h,depth),ix+iz*66)
				damaged_buildings += 1
				parcel["damaged"] = true
				emit_visual_geometry = previous_visual
				_preserve_roof_y=INF
				continue
			material_kind = 12+BuildingLibrary.style_for(parcel)
			box(Vector3(x,25+h/2,z),Vector3(width,h,depth),CityMaterial.PALETTE[material_kind-12],true)
			building_details(Vector3(x,25,z),Vector3(width,h,depth),ix+iz*66)
			# Restrained cornices and porch columns create old street-front silhouettes.
			if h<75 and rng.randf()<0.45:
				box(Vector3(x,31,z-depth/2-3),Vector3(width,1.2,7),Color(0.72,0.68,0.56),false)
				for dx: float in [-0.4,0.4]: box(Vector3(x+width*dx,28,z-depth/2-5),Vector3(0.8,6,0.8),Color(0.72,0.68,0.56),false)

			emit_visual_geometry = previous_visual
			_preserve_roof_y=INF
	material_kind = 0
	# Impact marks stay on city land and outside the fixed military airport.
	for site in impact_sites:
		for n in 7:
			var p := site+Vector2(cos(float(n)*2.4),sin(float(n)*2.4))*float(40+n*36)
			if parcel_clear(Rect2(p-Vector2(24,24),Vector2(48,48))): impact_crater(p,16+float(n%3)*5)

func parcel_clear(rect: Rect2) -> bool:
	if absf(rect.get_center().y-river_z(rect.get_center().x)) < 150+rect.size.y*0.5: return false
	if rect.position.x*CITY_SCALE < -6050*MAP_SCALE or Rect2(AIRPORT.position*(HORIZONTAL_SCALE/CITY_SCALE),AIRPORT.size*(HORIZONTAL_SCALE/CITY_SCALE)).grow(5).intersects(rect): return false
	for road in roads:
		if road.grow(8).intersects(rect): return false
	return true

func forest() -> void:
	material_kind = 0
	geometry_scale = MAP_SCALE
	for n in 2200:
		var x := rng.randf_range(-5900,10000)
		var z := rng.randf_range(-6500,6500)
		var rect := Rect2(x-8,z-8,16,16)
		var city_rect := Rect2(rect.position*(MAP_SCALE/CITY_SCALE),rect.size*(MAP_SCALE/CITY_SCALE))
		if not parcel_clear(city_rect): continue
		var blocked := false
		for building in buildings:
			if building.grow(7).intersects(city_rect):
				blocked = true
				break
		if blocked or Vector2(x-FESTIVAL.x,z-FESTIVAL.z).length()<270: continue
		var y := base_height(x,z)
		var h := rng.randf_range(12,24)
		box(Vector3(x,y+h/2,z),Vector3(1.5,h,1.5),Color(0.39,0.38,0.29),false)
		roof(Vector3(x,y+h*0.6,z),Vector3(13,h*0.65,13),Color(0.27,0.36,0.24))

func marker(parent: Node3D,label: String,p: Vector3) -> void:
	var m := Marker3D.new()
	m.name = label
	m.position = Vector3(p.x*geometry_scale,p.y,p.z*geometry_scale)
	parent.add_child(m)

var _road_frame := Vector4(0,0,1,2)

func triangle(a: Vector3,b: Vector3,c: Vector3,color: Color,collision := false) -> void:
	if collision:
		for p: Vector3 in [a,b,c]: solid.append(Vector3(p.x*geometry_scale,p.y,p.z*geometry_scale))
	if not emit_visual_geometry: return
	var key := SurfaceCatalog.batch_key(color,material_kind,detail_region,surface_family)
	if not batches.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)
		batches[key] = st
	var st: SurfaceTool = batches[key]
	for p: Vector3 in [a,b,c]:
		var world:=Vector3(p.x*geometry_scale,p.y,p.z*geometry_scale)
		if surface_family>=SurfaceCatalog.ASPHALT:
			st.set_uv(Vector2(world.z,world.x-_road_frame.x) if _road_frame.w<0.5 else Vector2(world.x,world.z-_road_frame.y))
			st.set_uv2(Vector2(_road_frame.z,_road_frame.w))
		st.add_vertex(world)

func quad(a: Vector3,b: Vector3,c: Vector3,d: Vector3,color: Color,collision := false) -> void:
	triangle(a,b,c,color,collision)
	triangle(a,c,d,color,collision)

func box(center: Vector3,size: Vector3,color: Color,collision: bool) -> void:
	var previous_emission:=emit_visual_geometry
	if not emit_visual_geometry and collision and center.y-size.y*.5>=_preserve_roof_y-.001:emit_visual_geometry=true
	var previous_family:=surface_family
	var previous_frame:=_road_frame
	# Thin ground surfaces only: no rooftop plant, sign or structural wall can enter this family.
	if surface_family==0 and center.y<=28.0 and size.y<=2.0:
		if material_kind in [7,10]:surface_family=SurfaceCatalog.CONCRETE
		elif material_kind==8:surface_family=SurfaceCatalog.PATCH
		elif material_kind==6:surface_family=SurfaceCatalog.PAINT
		elif material_kind==5 and size.y<0.3:surface_family=SurfaceCatalog.DRAIN
		elif material_kind==4 and color.r>0.6:surface_family=SurfaceCatalog.PAINT
	_road_frame=Vector4(center.x*geometry_scale,center.z*geometry_scale,minf(size.x,size.z)*geometry_scale,1.0 if size.x>size.z else 0.0)
	if minf(size.x,size.z)>maxf(size.x,size.z)*0.9:_road_frame.w=2.0
	# Quantize palette so the entire city stays within a small draw-call budget.
	color = Color(snappedf(color.r,0.08),snappedf(color.g,0.08),snappedf(color.b,0.08))
	var h := size*0.5
	var v: Array[Vector3] = []
	for p: Vector3 in [Vector3(-1,-1,-1),Vector3(1,-1,-1),Vector3(1,1,-1),Vector3(-1,1,-1),Vector3(-1,-1,1),Vector3(1,-1,1),Vector3(1,1,1),Vector3(-1,1,1)]: v.append(center+p*h)
	for face: Array in [[0,3,2,1],[4,5,6,7],[0,4,7,3],[1,2,6,5],[3,7,6,2],[0,1,5,4]]: quad(v[face[0]],v[face[1]],v[face[2]],v[face[3]],color,collision)
	surface_family=previous_family
	_road_frame=previous_frame
	emit_visual_geometry=previous_emission

func roof(p: Vector3,size: Vector3,color: Color) -> void:
	var a := p+Vector3(-size.x/2,0,-size.z/2)
	var b := p+Vector3(size.x/2,0,-size.z/2)
	var c := p+Vector3(size.x/2,0,size.z/2)
	var d := p+Vector3(-size.x/2,0,size.z/2)
	var e := p+Vector3(0,size.y,0)
	for edge: Array in [[a,b],[b,c],[c,d],[d,a]]: triangle(edge[1],edge[0],e,color)

func finish() -> void:
	for key in batches:
		var st: SurfaceTool = batches[key]
		st.generate_normals()
		var mesh := MeshInstance3D.new()
		mesh.name = "AdelaideBatch%02d" % serial
		if not key.split("|")[2].is_empty():
			mesh.name = "AdelaideDetail_"+key.split("|")[2]+"_%02d" % serial
			mesh.set_meta("cinematic_detail",true)
			mesh.visibility_range_end = 14000.0
			mesh.visibility_range_end_margin = 1500.0
		serial += 1
		mesh.mesh = st.commit()
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/adelaide_weathered.gdshader")
		var color_key: String = key.split("|")[0]
		if color_key in [Color(0.28,0.25,0.20).to_html(),Color(0.12,0.12,0.10).to_html(),Color(0.34,0.30,0.24).to_html()]:
			mat.shader = preload("res://shaders/adelaide_crater.gdshader")
		mat.set_shader_parameter("base_color",Color.html(color_key))
		if mat.shader == preload("res://shaders/adelaide_weathered.gdshader"):
			mat.set_shader_parameter("material_kind",int(key.split("|")[1]))
			if int(key.split("|")[3])==0:
				CityMaterial.bind(mat,int(key.split("|")[1]));_city_shared_materials.append(mat)
		var family := int(key.split("|")[3])
		mesh.set_meta("surface_family",family)
		if family != 0:
			mat = SurfaceCatalog.material(family,Color.html(color_key),int(key.split("|")[1]))
			_surface_materials.append(mat)
		mesh.material_override = mat
		add_child(mesh)
	batches.clear()
	if is_instance_valid(building_library):building_library.finish_details()
	if is_instance_valid(landmark_detail):landmark_detail.finish()
	refresh_surface_quality()
	var body := StaticBody3D.new()
	body.name = "AdelaideCollision"
	body.collision_layer = 1
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(solid)
	shape.backface_collision = true
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	add_child(body)
	solid.clear()

func building_details(p: Vector3,s: Vector3,index: int) -> void:
	var trim := Color(0.72,0.68,0.56)
	var glass := Color(0.19,0.27,0.28)
	var top := p.y+s.y
	var front := p.z-s.z/2-0.16
	box(Vector3(p.x,top-1.0,p.z),Vector3(s.x+0.6,1.8,s.z+0.6),trim,false)
	material_kind = 20 if index%3==0 and s.y<600 else 19
	# Three roof families: pitched old houses, stepped parapets, commercial flat roofs.
	if index%3==0 and s.y<600:
		gable_roof(Vector3(p.x,top,p.z),Vector3(s.x+1,10,s.z+1),Color(0.42,0.31,0.24),false)
		box(Vector3(p.x+s.x*0.22,top+7,p.z+s.z*0.18),Vector3(2.5,13,2.5),Color(0.48,0.38,0.30),false)
	else:
		box(Vector3(p.x,top+0.8,p.z),Vector3(s.x-1.2,1.6,s.z-1.2),Color(0.35,0.36,0.33),false)
		for side: float in [-1,1]:
			box(Vector3(p.x+side*(s.x/2-0.4),top+2,p.z),Vector3(0.8,4,s.z),trim,false)
		box(Vector3(p.x+s.x*0.15,top+3,p.z),Vector3(s.x*0.24,5,s.z*0.22),Color(0.46,0.48,0.44),false)
	material_kind = 2
	var rows := mini(int(s.y/24),12)
	for row in rows:
		var y := p.y+(row+1)*s.y/(rows+1)
		for col in 4:
			var x := p.x+s.x*(-0.36+col*0.24)
			box(Vector3(x,y,front),Vector3(s.x*0.13,12,0.18),glass,false)
			if s.y<600:
				material_kind = 0
				box(Vector3(x,y-6.7,front-0.16),Vector3(s.x*0.15,0.5,0.3),trim,false)
				material_kind = 2
		# Side window strip keeps the volume readable from oblique flight views.
		box(Vector3(p.x+s.x/2+0.1,y,p.z),Vector3(0.2,4,s.z*0.65),glass,false)
	box(Vector3(p.x,p.y+4,front-0.08),Vector3(3,8,0.3),Color(0.22,0.23,0.20),false)
	building_model_details(p,s,index)
	material_kind = 0

func gable_roof(p: Vector3,s: Vector3,color: Color,collision: bool) -> void:
	var a := p+Vector3(-s.x/2,0,-s.z/2)
	var b := p+Vector3(s.x/2,0,-s.z/2)
	var c := p+Vector3(s.x/2,0,s.z/2)
	var d := p+Vector3(-s.x/2,0,s.z/2)
	var e := p+Vector3(0,s.y,-s.z/2)
	var f := p+Vector3(0,s.y,s.z/2)
	quad(a,e,f,d,color,collision)
	quad(e,b,c,f,color,collision)
	triangle(a,b,e,color.darkened(0.15),collision)
	triangle(d,f,c,color.darkened(0.15),collision)

func hangar_details(x: float,z: float,number: int) -> void:
	var steel := Color(0.36,0.40,0.40)
	var pale := Color(0.69,0.71,0.65)
	material_kind = 3
	gable_roof(Vector3(x,186,z),Vector3(390,42,365),pale,true)
	material_kind = 5
	# Repeated buttresses and roof ribs articulate the long industrial building.
	for n in 7:
		var zz := z-155+n*52
		for side: float in [-1,1]:
			box(Vector3(x+side*187,107,zz),Vector3(8,162,10),steel,true)
			box(Vector3(x+side*132,196,zz),Vector3(105,6,5),steel,false)
		box(Vector3(x,228,zz),Vector3(16,6,8),steel,false)
	# Heavy portal frame and stacked sliding doors leave the center open.
	box(Vector3(x,175,z-177),Vector3(360,20,12),steel,true)
	for side: float in [-1,1]:
		box(Vector3(x+side*171,100,z-177),Vector3(18,148,18),steel,true)
		for leaf in 3:
			box(Vector3(x+side*(151+leaf*6),99,z-183-leaf*2),Vector3(5,142,6),pale,true)
		for n in 6:
			box(Vector3(x+side*171,40+n*22,z-188),Vector3(13,9,0.8),Color(0.78,0.60,0.16) if n%2==0 else Color(0.13,0.16,0.15),false)
		box(Vector3(x+side*140,164,z-190),Vector3(16,3,3),Color(0.89,0.86,0.66),false)
	# Clerestory glazing, sign plate, maintenance cabinets and bridge-crane rail.
	material_kind = 2
	box(Vector3(x,197,z-184),Vector3(100,9,1),Color(0.22,0.34,0.36),false)
	material_kind = 5
	box(Vector3(x,175,z-185),Vector3(32,12,2),Color(0.17,0.22,0.23),false)
	for n in number: box(Vector3(x-10+n*4,175,z-187),Vector3(2,6,0.5),Color(0.90,0.84,0.55),false)
	box(Vector3(x,150,z+90),Vector3(310,8,10),Color(0.66,0.55,0.25),true)
	for side: float in [-1,1]:
		box(Vector3(x+side*143,39,z+110),Vector3(20,26,32),steel,true)
		box(Vector3(x+side*143,54,z+110),Vector3(21,3,34),pale,false)
	material_kind = 0

func damage_strength(p: Vector2) -> float:
	var strength := 0.0
	for site in impact_sites: strength = maxf(strength,(1.0-smoothstep(100,650,p.distance_to(site)))*0.82)
	return strength

func ruined_building(p: Vector3,size: Vector3,index: int) -> void:
	if is_instance_valid(landmark_detail):landmark_detail.add_ruin(p,size,index)
	material_kind = 0
	var charred := Color(0.24,0.23,0.20)
	var concrete := Color(0.43,0.40,0.34)
	var remnant := size.y*(0.22+float(index%5)*0.1)
	# Irregular surviving wall lengths leave genuinely open roofless volumes.
	box(p+Vector3(-size.x*0.43,remnant/2,0),Vector3(size.x*0.14,remnant,size.z),concrete,true)
	box(p+Vector3(size.x*0.27,remnant*0.32,size.z*0.42),Vector3(size.x*0.42,remnant*0.64,size.z*0.15),charred,true)
	for side: float in [-1,1]:
		box(p+Vector3(side*size.x*0.33,size.y*0.31,size.z*0.31),Vector3(1.5,size.y*0.62,1.5),charred,true)
	box(p+Vector3(0,0.3,0),Vector3(size.x,0.6,size.z),charred,false)
	for n in 9:
		var x := sin(float(index+n)*2.7)*size.x*0.36
		var z := cos(float(index+n)*1.9)*size.z*0.36
		var h := 2.0+float((index+n)%5)*1.7
		box(p+Vector3(x,h/2,z),Vector3(size.x*0.14,h,size.z*0.17),concrete if n%2==0 else charred,n<3)
		roof(p+Vector3(x,h,z),Vector3(size.x*0.14,h*0.5,size.z*0.17),concrete)

func impact_crater(p: Vector2,radius: float) -> void:
	# Raised broken rim and dark basin; static geometry has no particle cost.
	for n in 24:
		var a := TAU*n/24.0
		var b := TAU*(n+1)/24.0
		var inner_a := Vector3(p.x+cos(a)*radius*0.55,25.3,p.y+sin(a)*radius*0.55)
		var inner_b := Vector3(p.x+cos(b)*radius*0.55,25.3,p.y+sin(b)*radius*0.55)
		var ra := radius*(1.0+0.10*sin(a*5)+0.06*cos(a*9))
		var rb := radius*(1.0+0.10*sin(b*5)+0.06*cos(b*9))
		var rim_a := Vector3(p.x+cos(a)*ra,28.0+sin(a*5)*1.8,p.y+sin(a)*ra)
		var rim_b := Vector3(p.x+cos(b)*rb,28.0+sin(b*5)*1.8,p.y+sin(b)*rb)
		quad(inner_a,inner_b,rim_b,rim_a,Color(0.28,0.25,0.20))
		triangle(Vector3(p.x,25.25,p.y),inner_b,inner_a,Color(0.12,0.12,0.10))
		var outer_a := Vector3(p.x+cos(a)*ra*(1.4+0.13*sin(a*7)),25.2,p.y+sin(a)*ra*(1.4+0.13*sin(a*7)))
		var outer_b := Vector3(p.x+cos(b)*rb*(1.4+0.13*sin(b*7)),25.2,p.y+sin(b)*rb*(1.4+0.13*sin(b*7)))
		quad(rim_a,rim_b,outer_b,outer_a,Color(0.34,0.30,0.24))
		if n%4==0:
			roof(rim_a+Vector3(0,0.4,0),Vector3(radius*0.18,2.0+float(n%3),radius*0.12),Color(0.28,0.25,0.20))

func build_river() -> void:
	geometry_scale = CITY_SCALE
	# Fine terrain replaces the removed coarse strip, including riverbed collision.
	for ix in 200:
		for iz in 35:
			var x := -3375.0+ix*37.5
			var z := -2062.5+iz*37.5
			var pts: Array[Vector3] = []
			for off: Vector2 in [Vector2.ZERO,Vector2(37.5,0),Vector2(37.5,37.5),Vector2(0,37.5)]:
				pts.append(Vector3(x+off.x,river_ground(x+off.x,z+off.y),z+off.y))
			quad(pts[3],pts[2],pts[1],pts[0],Color(0.40,0.47,0.29),true)
	surface_family = 0
	var water := SurfaceTool.new()
	water.begin(Mesh.PRIMITIVE_TRIANGLES)
	water.set_smooth_group(-1)
	for n in 200:
		var x := -3375.0+n*37.5
		var nx := x+37.5
		var a := Vector3(x*CITY_SCALE,1.0,(river_z(x)-69)*CITY_SCALE)
		var b := Vector3(nx*CITY_SCALE,1.0,(river_z(nx)-69)*CITY_SCALE)
		var c := Vector3(nx*CITY_SCALE,1.0,(river_z(nx)+69)*CITY_SCALE)
		var d := Vector3(x*CITY_SCALE,1.0,(river_z(x)+69)*CITY_SCALE)
		for v: Vector3 in [a,c,b,a,d,c]: water.add_vertex(v)
	water.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "RiverTorrens"
	mesh.mesh = water.commit()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/adelaide_river.gdshader")
	mesh.material_override = mat
	add_child(mesh)
	for x in bridge_sites:
		var z := river_z(x)
		surface_family=SurfaceCatalog.ASPHALT
		box(Vector3(x,29,z),Vector3(28,6,280),Color(0.39,0.40,0.38),true)
		surface_family=0
		for side: float in [-1,1]:
			box(Vector3(x+side*14,35,z),Vector3(1.2,7,280),Color(0.55,0.55,0.49),true)
			box(Vector3(x,7,z+side*43),Vector3(12,40,7),Color(0.45,0.45,0.40),true)
		# Short ramps join the 32 m deck to the 25 m road without an abrupt ledge.
		for side: float in [-1,1]:
			var near_z := z+side*140
			var far_z := z+side*180
			surface_family=SurfaceCatalog.ASPHALT
			_road_frame=Vector4(x*CITY_SCALE,z*CITY_SCALE,28.0*CITY_SCALE,0)
			quad(Vector3(x-14,32,near_z),Vector3(x+14,32,near_z),Vector3(x+14,25.7,far_z),Vector3(x-14,25.7,far_z),Color(0.39,0.40,0.38),true)
			surface_family=0
	marker(self,"RiverTorrensCentre",Vector3(300,1,river_z(300)))

func building_model_details(p: Vector3,s: Vector3,index: int) -> void:
	var trim := Color(0.66,0.64,0.56)
	var glass := Color(0.19,0.27,0.28)
	var front := p.z-s.z/2
	var top := p.y+s.y
	material_kind = 0
	# Foundation courses, narrow sidewalks and roof cornice have actual depth.
	box(p+Vector3(0,3,0),Vector3(s.x+0.7,6,s.z+0.7),Color(0.42,0.42,0.38),false)
	box(p+Vector3(0,0.55,-s.z/2-1.6),Vector3(s.x+2,1.1,3.2),trim,false)
	for side: float in [-1,1]:
		box(Vector3(p.x+side*s.x*0.46,p.y+s.y*0.5,front-0.35),Vector3(0.8,s.y,0.7),trim,false)
		box(Vector3(p.x+side*s.x*0.46,p.y+s.y*0.5,p.z+s.z/2+0.35),Vector3(0.8,s.y,0.7),trim,false)
	# Recessed entrance surround with canopy, steps and solid side cheeks.
	box(Vector3(p.x,p.y+16,front-1.8),Vector3(10,2,5),trim,false)
	for side: float in [-1,1]: box(Vector3(p.x+side*4.5,p.y+7,front-1.6),Vector3(0.6,14,0.6),trim,false)
	box(Vector3(p.x,p.y+0.7,front-2),Vector3(9,1.4,4),Color(0.48,0.48,0.43),false)
	# Side and rear windows avoid the single decorated-front appearance.
	var floors := mini(int(s.y/32),10)
	for row in floors:
		var y := p.y+(row+1)*s.y/(floors+1)
		material_kind = 2
		for col in 3:
			var offset := (-0.3+col*0.3)
			box(Vector3(p.x+offset*s.x,y,p.z+s.z/2+0.18),Vector3(s.x*0.12,12,0.25),glass,false)
			box(Vector3(p.x-s.x/2-0.18,y,p.z+offset*s.z),Vector3(0.25,12,s.z*0.12),glass,false)
		material_kind = 0
		if index%4==0:
			box(Vector3(p.x,y-7,front-1.2),Vector3(s.x*0.84,1,2.4),trim,false)
			box(Vector3(p.x,y-2,front-2.2),Vector3(s.x*0.84,0.7,0.5),trim,false)
	# Alternate facade families introduce bay windows and projecting shop awnings.
	if index%5==0:
		material_kind = 0
		for side: float in [-1,1]:
			box(Vector3(p.x+side*s.x*0.32,p.y+s.y*0.45,front-1.1),Vector3(s.x*0.13,s.y*0.72,2.2),trim,false)
			material_kind = 2
			for row in 8:
				var y := p.y+s.y*(0.16+row*0.08)
				box(Vector3(p.x+side*s.x*0.32,y,front-2.25),Vector3(s.x*0.10,s.y*0.052,0.2),glass,false)
			material_kind = 0
	if index%7==0:
		material_kind = 5
		box(Vector3(p.x,p.y+23,front-2.2),Vector3(s.x*0.65,2,4.5),Color(0.39,0.42,0.35),false)
	if index%6==0:
		material_kind = 1
		var setback_height := minf(s.y*0.14,95)
		box(Vector3(p.x+s.x*0.12,top+setback_height/2,p.z+s.z*0.14),Vector3(s.x*0.40,setback_height,s.z*0.42),Color(0.55,0.53,0.46),true)
		material_kind = 3
		box(Vector3(p.x+s.x*0.12,top+setback_height+1,p.z+s.z*0.14),Vector3(s.x*0.42,2,s.z*0.44),trim,false)
	# Setback rooftop rooms and ventilation ducts vary the aerial silhouette.
	material_kind = 5
	if index%3!=0:
		box(Vector3(p.x-s.x*0.18,top+7,p.z+s.z*0.1),Vector3(s.x*0.22,14,s.z*0.25),Color(0.48,0.50,0.47),false)
		for n in 3:
			box(Vector3(p.x+s.x*0.21,top+5,p.z+(-0.2+n*0.17)*s.z),Vector3(3,10,3),Color(0.38,0.42,0.41),false)
		box(Vector3(p.x,top+2.6,p.z),Vector3(s.x*0.4,2.5,1.3),Color(0.38,0.42,0.41),false)
	cinematic_roof_details(p,s,index)

func road_crossing(point: Vector2,own: Rect2) -> bool:
	for other in roads:
		if other == own: continue
		if other.grow(19).has_point(point): return true
	return false

func road_details() -> void:
	var crossings := {}
	geometry_scale = CITY_SCALE
	for road in roads:
		var horizontal := road.size.x > road.size.y
		var length := road.size.x if horizontal else road.size.y
		if length < 10: continue
		var width := road.size.y if horizontal else road.size.x
		var steps := maxi(1,int(length/36))
		for n in steps:
			var distance := (float(n)+0.5)*length/steps
			var p := road.position+Vector2(distance,road.size.y*0.5) if horizontal else road.position+Vector2(road.size.x*0.5,distance)
			if road_crossing(p,road): continue
			material_kind = 7
			# Pavement/kerbs are interrupted at intersections, never walls across a crossing.
			for side: float in [-1,1]:
				var curb := p+Vector2(0,side*(width/2+0.55)) if horizontal else p+Vector2(side*(width/2+0.55),0)
				box(Vector3(curb.x,26.1,curb.y),Vector3(length/steps-1,0.9,1.1) if horizontal else Vector3(1.1,0.9,length/steps-1),Color(0.48,0.47,0.42),false)
				material_kind = 6
				var line := p+Vector2(0,side*(width/2-1.5)) if horizontal else p+Vector2(side*(width/2-1.5),0)
				box(Vector3(line.x,25.85,line.y),Vector3(length/steps-2,0.14,0.18) if horizontal else Vector3(0.18,0.14,length/steps-2),Color(0.76,0.74,0.64),false)
				material_kind = 7
			if n%3==1: cinematic_road_module(p,horizontal,width)
			if n%6==2:
				material_kind = 8
				box(Vector3(p.x,25.82,p.y),Vector3(8,0.12,width*0.35) if horizontal else Vector3(width*0.35,0.12,8),Color(0.17,0.18,0.17),false)
			if n%9==3:
				material_kind = 5
				var drain := p+Vector2(0,width*0.43) if horizontal else p+Vector2(width*0.43,0)
				box(Vector3(drain.x,25.88,drain.y),Vector3(1.5,0.16,0.8),Color(0.22,0.25,0.24),false)
		# Crosswalks at genuine intersecting roads, deduplicated per through-road.
		if not horizontal: continue
		material_kind = 6
		for other in roads:
			if other.size.y<=other.size.x or not road.intersects(other): continue
			var x := other.get_center().x
			var z := road.get_center().y
			var crossing_key := Vector2(x,z)
			if crossings.has(crossing_key): continue
			crossings[crossing_key] = true
			for side: float in [-1,1]:
				for stripe in 7:
					box(Vector3(x+side*(other.size.x/2+4),25.97,z-width*0.38+stripe*width*0.12),Vector3(3,0.16,width*0.065),Color(0.80,0.78,0.68),false)
	material_kind = 0

func military_base_details(root: Node3D) -> void:
	geometry_scale = HORIZONTAL_SCALE
	var concrete := Color(0.48,0.49,0.44)
	var steel := Color(0.30,0.35,0.33)
	# Perimeter is broken at the existing west access road, not across it.
	material_kind = 5
	for side: float in [-1,1]:
		var x := -5400.0 if side<0 else -2460.0
		for n in 61:
			var z := 400.0+n*90
			if side<0 and absf(z-2920)<150: continue
			box(Vector3(x,33,z),Vector3(2,16,2),steel,false)
			box(Vector3(x,32,z+42),Vector3(0.65,1,84),steel,false)
			box(Vector3(x,39,z+42),Vector3(0.65,1,84),steel,false)
	for z: float in [400,5900]:
		for n in 32:
			box(Vector3(-5400+n*92,33,z),Vector3(2,16,2),steel,false)
			box(Vector3(-5354+n*92,38,z),Vector3(90,1,0.8),steel,false)
	# Security gate and guard facilities sit beside the road gap.
	material_kind = 0
	for z: float in [2770,3070]:
		box(Vector3(-5350,39,z),Vector3(40,28,35),concrete,true)
		box(Vector3(-5350,55,z),Vector3(45,4,40),Color(0.29,0.33,0.30),false)
		material_kind = 2
		box(Vector3(-5371,44,z),Vector3(0.4,8,22),Color(0.19,0.27,0.28),false)
		material_kind = 0
		for n in 5: box(Vector3(-5400+n*22,30,z+(-24 if z<2920 else 24)),Vector3(16,8,7),concrete,true)
	# Six work bays: service gantries and cabinets hug walls, preserving center clearance.
	for n in 6:
		var x := -3160.0
		var z := 1500.0+n*540
		material_kind = 5
		for side: float in [-1,1]:
			box(Vector3(x+side*138,50,z+10),Vector3(30,4,180),steel,true)
			for zz: float in [-65,75]: box(Vector3(x+side*138,38,z+zz),Vector3(3,24,3),steel,true)
			box(Vector3(x+side*137,64,z+10),Vector3(1,2,178),steel,false)
			for step in 9: box(Vector3(x+side*166,29+step*2.6,z-70+step*3),Vector3(14,2,3),steel,false)
			for cabinet in 3:
				box(Vector3(x+side*145,36,z+90+cabinet*18),Vector3(14,20,12),Color(0.38,0.42,0.37),true)
				box(Vector3(x+side*136,38,z+90+cabinet*18),Vector3(0.5,3,8),Color(0.18,0.23,0.21),false)
		material_kind = 6
		for side: float in [-1,1]:
			box(Vector3(x+side*95,27.2,z-35),Vector3(1.5,0.2,210),Color(0.82,0.66,0.22),false)
			for mark in 6: box(Vector3(x+side*112,27.2,z-100+mark*25),Vector3(9,0.2,3),Color(0.82,0.66,0.22),false)
		material_kind = 9
		for dx: float in [-130,130]: box(Vector3(x+dx,158,z-80),Vector3(4,3,140),Color(0.78,0.77,0.62),false)
		base_label(root,"MS %02d" % (n+1),Vector3(x,177,z-190),30)
	# Fuel yard, berm enclosure and pipes remain away from sortie corridors.
	material_kind = 5
	for n in 3:
		var pos := Vector3(-2830+n*105,26,4580)
		base_cylinder(pos,36,42,Color(0.52,0.55,0.49))
		box(pos+Vector3(0,43,0),Vector3(32,2,3),steel,false)
		box(pos+Vector3(0,2,-60),Vector3(5,4,120),steel,false)
	material_kind = 0
	for side: float in [-1,1]:
		box(Vector3(-2725,30,4580+side*74),Vector3(350,8,5),concrete,true)
		box(Vector3(-2725+side*175,30,4580),Vector3(5,8,150),concrete,true)
	# Logistics park: containers and service trucks between stores and perimeter.
	for n in 7:
		var z := 4900.0+n*125
		material_kind = 5
		box(Vector3(-2600,35,z),Vector3(42,18,22),Color(0.36,0.42,0.34),true)
		for rib in 7: box(Vector3(-2618+rib*6,35,z-11.5),Vector3(0.5,16,0.7),steel,false)
		box(Vector3(-2535,32,z+30),Vector3(12,10,30),Color(0.38,0.42,0.37),true)
		box(Vector3(-2535,34,z+10),Vector3(12,14,10),Color(0.38,0.42,0.37),true)
		material_kind = 2
		box(Vector3(-2535,37,z+4.8),Vector3(9,4,0.4),Color(0.19,0.27,0.28),false)
		material_kind = 0
		for dx: float in [-6.5,6.5]:
			for zz: float in [17,40]: box(Vector3(-2535+dx,28,z+zz),Vector3(2,5,5),Color(0.13,0.15,0.14),false)
	# Runway edge markers are emissive geometry; no hundreds of dynamic lights.
	material_kind = 9
	for n in 35:
		for dx: float in [-67,67]: box(Vector3(-4990+dx,27.5,500+n*140),Vector3(2,1.3,2),Color(0.72,0.76,0.63),false)
	material_kind = 5
	for z: float in [1000,2300,3700,5100]:
		box(Vector3(-4230,55,z),Vector3(2,60,2),steel,false)
		box(Vector3(-4230,85,z),Vector3(22,2,3),steel,false)
		material_kind = 9
		for dx: float in [-8,8]: box(Vector3(-4230+dx,84,z),Vector3(6,3,4),Color(0.78,0.77,0.62),false)
		material_kind = 5
	base_label(root,"MS OPERATIONS",Vector3(-2750,82,685),38)
	material_kind = 0

## Local detail modules use the existing map coordinates, without collision or RNG draws.
## Chunked independently so rooftop clutter is culled outside the flight corridor.
func cinematic_route_distance(point: Vector2) -> float:
	var route: Array[Vector2] = [Vector2(-10800,11000),Vector2(-12500,2500),Vector2(-6000,-16000),Vector2(5000,-30000)]
	var distance := INF
	for i in route.size()-1:
		var ab := route[i+1]-route[i]
		var fraction := clampf((point-route[i]).dot(ab)/ab.length_squared(),0.0,1.0)
		distance = minf(distance,point.distance_to(route[i]+ab*fraction))
	return distance

func detail_chunk(point: Vector2) -> String:
	return "R%d_%d" % [floori(point.x/4000.0),floori(point.y/4000.0)]

func detail_beam(a: Vector3,b: Vector3,width: float,color: Color) -> void:
	var start := Vector3(a.x*geometry_scale,a.y,a.z*geometry_scale)
	var end := Vector3(b.x*geometry_scale,b.y,b.z*geometry_scale)
	var axis := (end-start).normalized()
	var cross_axis := Vector3.UP if absf(axis.y)<0.95 else Vector3.RIGHT
	var u := axis.cross(cross_axis).normalized()*width*0.5
	var v := axis.cross(u.normalized()).normalized()*width*0.5
	var previous_scale := geometry_scale
	geometry_scale = 1.0
	var vertices: Array[Vector3] = [start-u-v,start+u-v,start+u+v,start-u+v,end-u-v,end+u-v,end+u+v,end-u+v]
	for face: Array in [[0,3,2,1],[4,5,6,7],[0,4,7,3],[1,2,6,5],[3,7,6,2],[0,1,5,4]]:
		quad(vertices[face[0]],vertices[face[1]],vertices[face[2]],vertices[face[3]],color,false)
	geometry_scale = previous_scale

func cinematic_airport_details() -> void:
	geometry_scale = HORIZONTAL_SCALE
	var concrete := Color(0.48,0.50,0.49)
	var steel := Color(0.25,0.30,0.33)
	var sheet := Color(0.57,0.62,0.63)
	for n in 6:
		detail_region = "Hangar%02d" % (n+1)
		var x := -3160.0
		var z := 1500.0+n*540.0
		# Footings and wall plinths sit on the slab; never cross the open portal.
		material_kind = 10
		for side: float in [-1,1]:
			box(Vector3(x+side*180,28.5,z),Vector3(18,4,350),concrete,false)
			for bay in 7:
				var zz := z-155+bay*52
				box(Vector3(x+side*188,29.5,zz),Vector3(15,6,18),concrete,false)
		material_kind = 5
		for side: float in [-1,1]:
			# Downpipes and eaves follow the actual sloping roof's 186 m edge.
			box(Vector3(x+side*195,185,z),Vector3(2,3,365),steel,false)
			for zz: float in [-148,148]:
				box(Vector3(x+side*196,106,z+zz),Vector3(1.2,158,1.2),steel,false)
			for bay in 3:
				var zz := z-130+bay*104
				detail_beam(Vector3(x+side*191,40,zz),Vector3(x+side*191,170,zz+90),4.0,steel)
		# Roof trusses remain above the pre-existing portal clearance.
		for zz: float in [-140,-40,60,140]:
			detail_beam(Vector3(x-176,187,z+zz),Vector3(x,225,z+zz),4.0,steel)
			detail_beam(Vector3(x,225,z+zz),Vector3(x+176,187,z+zz),4.0,steel)
			detail_beam(Vector3(x-170,187,z+zz),Vector3(x+170,187,z+zz),3.0,steel)
		# Low ridge ventilator, with dark louvres and a raised rain cap.
		material_kind = 11
		box(Vector3(x,231,z+10),Vector3(26,6,235),sheet,false)
		material_kind = 5
		for side: float in [-1,1]:
			box(Vector3(x+side*13.2,232,z+10),Vector3(0.7,3.2,218),steel,false)
		material_kind = 3
		box(Vector3(x,235.5,z+10),Vector3(32,3,245),sheet,false)
		# Service skylight frames sit on the roof plane, not floating above it.
		for side: float in [-1,1]:
			for bay in 3:
				var zz := z-105+bay*95
				material_kind = 5
				detail_beam(Vector3(x+side*34,220.7,zz),Vector3(x+side*101,206.2,zz),5.0,steel)
				for edge: float in [-22,22]:
					detail_beam(Vector3(x+side*37,220.9,zz+edge),Vector3(x+side*98,207.8,zz+edge),3.0,steel)
				for end: Vector2 in [Vector2(37,220.9),Vector2(98,207.8)]:
					detail_beam(Vector3(x+side*end.x,end.y,zz-22),Vector3(x+side*end.x,end.y,zz+22),3.0,steel)
				material_kind = 2
				var a := Vector3(x+side*37,220.6,zz-22)
				var b := Vector3(x+side*98,207.5,zz-22)
				var c := b+Vector3(0,0,44)
				var d := a+Vector3(0,0,44)
				quad(a,b,c,d,Color(0.23,0.32,0.36),false)
		# Expansion strips and wheel-stop pads stay flush with existing apron.
		material_kind = 10
		for side: float in [-1,1]:
			box(Vector3(x+side*148,27.15,z-260),Vector3(16,0.3,135),concrete,false)
		material_kind = 5
		for side: float in [-1,1]:
			for cabinet in 2:
				var p := Vector3(x+side*155,38,z+30+cabinet*30)
				box(p,Vector3(13,22,19),sheet,false)
				for slot in 4:
					box(p+Vector3(-side*6.6,-5+slot*3,0),Vector3(0.4,0.7,13),steel,false)
		airport_detail_bays += 1
	detail_region = "Apron"
	# Long drainage channels align with the side of the existing hardstand.
	material_kind = 5
	for n in 12:
		box(Vector3(-4505,27.05,1750+n*220),Vector3(2,0.15,180),steel,false)
	material_kind = 10
	for n in 10:
		var p := Vector3(-4070+n%5*90,27.05,5000+floori(n/5.0)*75)
		box(p,Vector3(72,0.3,52),concrete,false)
		material_kind = 5
		box(p+Vector3(0,3,0),Vector3(22,6,18),sheet,false)
		material_kind = 10
	detail_region = ""
	material_kind = 0

func cinematic_roof_details(p: Vector3,s: Vector3,index: int) -> void:
	var world_center := Vector2(p.x,p.z)*CITY_SCALE
	if cinematic_route_distance(world_center)>2800.0: return
	if index%3==0 and s.y<600: return
	if detailed_roofs>=72: return
	detailed_roofs += 1
	detail_region = detail_chunk(world_center)
	geometry_scale = CITY_SCALE
	var top := p.y+s.y
	var steel := Color(0.29,0.34,0.36)
	var pale := Color(0.55,0.60,0.60)
	# Reusable rooftop plant: raised footings, paired air handlers and connecting ducts.
	var pad := Vector3(p.x-s.x*0.24,top+1.6,p.z-s.z*0.23)
	material_kind = 10
	box(pad,Vector3(s.x*0.20,1.6,s.z*0.20),Color(0.48,0.49,0.46),false)
	material_kind = 5
	for unit in 2:
		var pos := pad+Vector3((-0.045+unit*0.09)*s.x,5,0)
		box(pos,Vector3(s.x*0.075,9,s.z*0.16),pale,false)
		for slot in 4:
			box(pos+Vector3(0,-2+slot*1.6,-s.z*0.081),Vector3(s.x*0.061,0.6,0.06),steel,false)
	box(pad+Vector3(s.x*0.15,2,s.z*0.015),Vector3(s.x*0.18,3,0.28),pale,false)
	# A small access core and its service door stay inside the existing parcel.
	material_kind = 11
	var core := Vector3(p.x+s.x*0.27,top+11,p.z-s.z*0.27)
	box(core,Vector3(s.x*0.15,20,s.z*0.14),pale,false)
	material_kind = 3
	box(core+Vector3(0,11,0),Vector3(s.x*0.16,2,s.z*0.15),steel,false)
	material_kind = 5
	box(core+Vector3(0,-3,-s.z*0.071),Vector3(0.22,12,0.06),steel,false)
	# Roof edge coping and one antenna make the silhouette readable in motion.
	material_kind = 10
	for side: float in [-1,1]:
		box(Vector3(p.x,top+2,p.z+side*(s.z/2-0.4)),Vector3(s.x,4,0.8),pale,false)
	material_kind = 5
	if index%4==1:
		var mast := Vector3(p.x-s.x*0.35,top+17,p.z+s.z*0.29)
		box(mast,Vector3(0.08,32,0.08),steel,false)
		box(mast+Vector3(0,7,0),Vector3(1.2,0.6,0.08),pale,false)
	detail_region = ""
	material_kind = 0

func cinematic_road_module(point: Vector2,horizontal: bool,width: float) -> void:
	var world_point := point*CITY_SCALE
	if roadside_modules>=48 or cinematic_route_distance(world_point)>1800.0: return
	roadside_modules += 1
	detail_region = detail_chunk(world_point)
	geometry_scale = CITY_SCALE
	var curb := point+Vector2(0,width/2+2.2) if horizontal else point+Vector2(width/2+2.2,0)
	var steel := Color(0.31,0.35,0.37)
	material_kind = 10
	box(Vector3(curb.x,26.4,curb.y),Vector3(1.1,1.2,1.1),Color(0.49,0.49,0.45),false)
	material_kind = 5
	box(Vector3(curb.x,37,curb.y),Vector3(0.07,22,0.07),steel,false)
	box(Vector3(curb.x,47.5,curb.y),Vector3(0.65,0.7,0.07),steel,false)
	box(Vector3(curb.x+0.25,47,curb.y),Vector3(0.3,0.6,0.15),Color(0.64,0.66,0.61),false)
	box(Vector3(curb.x+0.8,28.6,curb.y+0.7),Vector3(0.4,5.4,0.35),steel,false)
	detail_region = ""
	material_kind = 7

func base_cylinder(p: Vector3,radius: float,height: float,color: Color) -> void:
	for n in 16:
		var a := TAU*n/16.0
		var b := TAU*(n+1)/16.0
		var u := Vector3(cos(a)*radius,0,sin(a)*radius)
		var v := Vector3(cos(b)*radius,0,sin(b)*radius)
		quad(p+v,p+u,p+u+Vector3.UP*height,p+v+Vector3.UP*height,color,true)
		triangle(p+Vector3.UP*height,p+v+Vector3.UP*height,p+u+Vector3.UP*height,color,true)

func base_label(parent: Node3D,text: String,p: Vector3,font_size: int) -> void:
	var label := Label3D.new()
	label.name = "Sign_"+text.replace(" ","_")
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.5
	label.modulate = Color(0.86,0.84,0.65)
	label.outline_size = 3
	label.position = Vector3(p.x*HORIZONTAL_SCALE,p.y,p.z*HORIZONTAL_SCALE)
	label.rotation.y = PI
	parent.add_child(label)

func refresh_surface_quality() -> void:
	for material:ShaderMaterial in _city_shared_materials:material.set_shader_parameter("city_quality",clampi(Settings.effects_quality,0,2))
	for material: ShaderMaterial in _surface_materials:
		material.set_shader_parameter("trial_enabled",trial_surfaces_enabled)
		material.set_shader_parameter("surface_detail",1 if Settings.effects_quality>0 else 0)
		if material.shader.resource_path.ends_with("adelaide_ground.gdshader"):
			material.set_shader_parameter("ground_quality",clampi(Settings.effects_quality,0,2))
		elif material.shader.resource_path.ends_with("road_surface.gdshader"):
			material.set_shader_parameter("road_quality",clampi(Settings.effects_quality,0,2))

func set_surface_trials_enabled(enabled: bool) -> void:
	trial_surfaces_enabled = enabled
	refresh_surface_quality()
