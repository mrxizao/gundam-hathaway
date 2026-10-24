extends Node3D
const Meshes:=preload("res://scripts/world/adelaide_building_mesh.gd")
const Materials:=preload("res://scripts/world/adelaide_building_material.gd")
const TARGETS:={"parcel_15_27":4,"parcel_15_30":2,"parcel_15_33":0,"parcel_16_31":4,"parcel_16_35":0,"parcel_17_24":1,"parcel_17_25":0,"parcel_17_30":2,"parcel_17_33":2,"parcel_17_34":1,"parcel_18_24":5,"parcel_18_26":3,"parcel_18_27":4,"parcel_18_29":3,"parcel_18_30":3,"parcel_18_31":5,"parcel_18_32":1,"parcel_19_24":0,"parcel_19_25":1,"parcel_19_26":0,"parcel_19_27":5,"parcel_19_29":2,"parcel_19_31":4,"parcel_19_32":3,"parcel_19_34":5,"parcel_19_35":2,"parcel_20_22":5,"parcel_20_24":3,"parcel_20_26":2,"parcel_20_27":1,"parcel_20_32":0,"parcel_20_33":1,"parcel_21_21":3,"parcel_21_26":4,"parcel_22_22":4,"parcel_22_23":5,"parcel_22_24":5,"parcel_23_21":1,"parcel_23_22":3,"parcel_23_23":4,"parcel_23_24":2,"parcel_24_21":0,"parcel_24_22":2,"parcel_24_23":5,"parcel_24_24":4,"parcel_25_21":1,"parcel_25_22":0,"parcel_25_23":3}
const DAY4_TARGETS:={"parcel_16_31":4,"parcel_16_35":0,"parcel_17_30":2,"parcel_17_33":2,"parcel_17_34":1,"parcel_18_26":3,"parcel_18_31":5,"parcel_19_25":1,"parcel_19_26":0,"parcel_20_22":5,"parcel_21_21":3,"parcel_22_22":4,"parcel_22_23":5,"parcel_23_21":1,"parcel_23_22":3,"parcel_23_23":4,"parcel_24_21":0,"parcel_24_22":2}
const LIMIT:=48
const DetailModules:=preload("res://scripts/world/adelaide_detail_modules.gd")
var detail_writers:Dictionary={}
var detail_regions:Array[Node3D]=[]
var detail_instances:=0
var detail_mesh_triangles:=0
var layout_rows:Array[Dictionary]=[]
const NEAR_LIMIT:=6
var entries:Array[Dictionary]=[]
var materials:Dictionary={}
var last_quality:=-1
var force_lod:=-1
var _clock:=0.0
var _selection:Array[Dictionary]=[]
var _candidates:Array[Dictionary]=[]
static func route_distance(point:Vector2)->float:
	var points:Array[Vector2]=[Vector2(-10800,11000),Vector2(-12500,2500),Vector2(-6000,-16000),Vector2(5000,-30000)]
	var best:=INF
	for i in points.size()-1:best=minf(best,point.distance_to(Geometry2D.get_closest_point_to_segment(point,points[i],points[i+1])))
	return best
static func district_for(point:Vector2)->int:
	var stations:Array[Vector2]=[Vector2(-11000,-5000),Vector2(-8500,-13000),Vector2(-1000,-20000)]
	var best:=0;var distance:=INF
	for i in stations.size():
		var value:=point.distance_to(stations[i])
		if value<distance:best=i;distance=value
	return best
static func style_for(parcel:Dictionary)->int:
	if TARGETS.has(parcel.id):return TARGETS[parcel.id]
	var district:=district_for(parcel.bounds.get_center())
	var seed_value:int=posmod(int(parcel.seed)^(district*19349663),2147483647)
	if parcel.height>720:return 3
	var weights:Array=[ [4,4,2,0,1,5], [0,1,1,2,3,5], [0,1,2,3,5,5] ]
	return weights[district][seed_value%6]
static func choose(records:Array[Dictionary])->Array[Dictionary]:
	var chosen:Array[Dictionary]=[];var used:={};var counts:=[0,0,0,0,0,0]
	for parcel:Dictionary in records:
		if parcel.damaged or not DAY4_TARGETS.has(parcel.id):continue
		var copy:=parcel.duplicate();copy["style"]=DAY4_TARGETS[parcel.id];chosen.append(copy);used[copy.id]=true;counts[copy.style]+=1
	var stations:Array[Vector2]=[Vector2(-11000,-5000),Vector2(-8500,-13000),Vector2(-1000,-20000)]
	for district in 3:
		var existing:=0
		for row:Dictionary in chosen:
			if district_for(row.bounds.get_center())==district:existing+=1
		var ranked:Array[Dictionary]=[]
		for parcel:Dictionary in records:
			if parcel.damaged or used.has(parcel.id) or district_for(parcel.bounds.get_center())!=district:continue
			if route_distance(parcel.bounds.get_center())>5000:continue
			var copy:=parcel.duplicate();copy["rank"]=parcel.bounds.get_center().distance_to(stations[district])+(5000 if parcel.height>720 else 0);ranked.append(copy)
		ranked.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.rank<b.rank if not is_equal_approx(a.rank,b.rank) else String(a.id)<String(b.id))
		for i in mini(16-existing,ranked.size()):
			var row:Dictionary=ranked[i];var best:=0
			for kind in 6:
				if counts[kind]<counts[best]:best=kind
			row["style"]=best;counts[best]+=1;chosen.append(row);used[row.id]=true
	return chosen

func wants(parcel:Dictionary)->bool:
	return not bool(parcel.damaged) and TARGETS.has(parcel.id)
func replace(parcel:Dictionary)->bool:
	if not wants(parcel):return false
	var visual:=parcel.duplicate(true);visual["style"]=TARGETS[parcel.id]
	_selection.append(visual);add_parcel(visual);collect_details(visual)
	return true
func collect(parcel:Dictionary)->void:
	_candidates.append(parcel.duplicate(true))
func build()->void:
	_selection=choose(_candidates)
	for parcel:Dictionary in _selection:add_parcel(parcel)
	last_quality=-1
	refresh_quality()
func selected_ids()->Array[String]:
	var ids:Array[String]=[]
	for p:Dictionary in _selection:ids.append(p.id)
	return ids
func add_parcel(parcel:Dictionary)->void:
	var rect:Rect2=parcel.bounds;var dims:=Vector3(rect.size.x,parcel.height,rect.size.y)
	var root:=Node3D.new();root.name=parcel.id;root.position=Vector3(rect.get_center().x,25,rect.get_center().y);add_child(root)
	var levels:Array[MeshInstance3D]=[]
	for level in 3:
		var mesh:ArrayMesh=Meshes.new().build(dims,parcel.style,level)
		for s in mesh.get_surface_count():mesh.surface_set_material(s,material(int(mesh.surface_get_name(s)),parcel.style))
		if level>0:mesh=merge_surfaces(mesh,parcel.style)
		var mi:=MeshInstance3D.new();mi.name="LOD"+str(level);mi.mesh=mesh;mi.visible=level==2;mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(mi);levels.append(mi)
	# One position-only opaque surface casts the complete near silhouette without
	# repeating every facade material in each directional shadow cascade.
	var shadow:=MeshInstance3D.new();shadow.name="ShadowCaster"
	shadow.mesh=shadow_mesh(levels[0].mesh)
	shadow.material_override=StandardMaterial3D.new()
	shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	root.add_child(shadow)
	entries.append({"id":parcel.id,"style":parcel.style,"record":parcel,"root":root,"levels":levels,"level":2,"old":-1,"blend":1.0,"distance":INF})
func material(role:int,style:int)->ShaderMaterial:
	var key:=str(role)+"/"+str(style)
	if not materials.has(key):materials[key]=Materials.material(role,style)
	return materials[key]
func refresh_quality()->void:
	last_quality=clampi(Settings.effects_quality,0,2)
	for region:Node3D in detail_regions:
		region.visible=last_quality>0
		for mesh:MeshInstance3D in region.get_children():mesh.visibility_range_end=4500.0 if last_quality==2 else 1800.0;mesh.visibility_range_end_margin=400.0
	for m:ShaderMaterial in materials.values():m.set_shader_parameter("building_quality",last_quality)
func _process(delta:float)->void:
	if last_quality!=Settings.effects_quality:refresh_quality()
	_clock-=delta
	if _clock<=0.0:
		_clock=.12
		update_lods(get_viewport().get_camera_3d())
	for entry:Dictionary in entries:
		if entry.old<0:continue
		entry.blend=minf(1.0,entry.blend+delta/.35)
		entry.levels[entry.old].set_instance_shader_parameter("lod_fade",entry.blend)
		entry.levels[entry.level].set_instance_shader_parameter("lod_fade",entry.blend)
		if entry.blend>=1.0:entry.levels[entry.old].visible=false;entry.old=-1;entry.levels[entry.level].set_instance_shader_parameter("lod_side",0.0)
func update_lods(camera:Camera3D)->void:
	if force_lod>=0:
		for entry:Dictionary in entries:set_lod(entry,clampi(force_lod,0,2),false)
		return
	if camera==null:return
	var near_candidates:Array[Dictionary]=[]
	var viewport_height:=float(get_viewport().get_visible_rect().size.y)
	for entry:Dictionary in entries:
		var rect:Rect2=entry.record.bounds;var h:float=entry.record.height
		var p:Vector3=camera.global_position-entry.root.global_position
		var closest:=Vector3(clampf(p.x,-rect.size.x*.5,rect.size.x*.5),clampf(p.y,0,h),clampf(p.z,-rect.size.y*.5,rect.size.y*.5))
		entry.distance=p.distance_to(closest)
		var center:Vector3=entry.root.global_position+Vector3.UP*h*.5
		var projected:=h*viewport_height/(maxf(1.0,camera.global_position.distance_to(center))*2.0*tan(deg_to_rad(camera.fov)*.5))
		var enter:float=1900.0 if entry.level==0 else 1600.0
		var pixels:float=160.0 if entry.level==0 else 200.0
		var target:=1 if entry.distance<(11500.0 if entry.level==1 else 9500.0) and projected>30 else 2
		if last_quality==0:target=2
		if last_quality==2 and entry.distance<enter and projected>pixels and (entry.distance<400.0 or camera.is_position_in_frustum(center)):near_candidates.append(entry)
		entry["target"]=target
	near_candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.distance<b.distance)
	for i in mini(NEAR_LIMIT,near_candidates.size()):near_candidates[i].target=0
	for entry:Dictionary in entries:set_lod(entry,entry.target,true)
func set_lod(entry:Dictionary,wanted:int,smooth:bool=true)->void:
	if entry.level==wanted and entry.old<0:return
	if not smooth:
		for i in 3:entry.levels[i].visible=i==wanted;entry.levels[i].set_instance_shader_parameter("lod_fade",1.0);entry.levels[i].set_instance_shader_parameter("lod_side",0.0)
		entry.level=wanted;entry.old=-1;entry.blend=1.0;return
	if entry.level==wanted:return
	if entry.old>=0:entry.levels[entry.old].visible=false
	entry.old=entry.level;entry.level=wanted;entry.blend=0.0
	entry.levels[entry.old].visible=true;entry.levels[entry.old].set_instance_shader_parameter("lod_side",1.0);entry.levels[entry.old].set_instance_shader_parameter("lod_fade",0.0)
	entry.levels[wanted].visible=true;entry.levels[wanted].set_instance_shader_parameter("lod_side",0.0);entry.levels[wanted].set_instance_shader_parameter("lod_fade",0.0)

static func shadow_mesh(source:ArrayMesh)->ArrayMesh:
	var vertices:=PackedVector3Array()
	for surface in source.get_surface_count():vertices.append_array(source.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices
	var result:=ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	result.set_meta("triangles",vertices.size()/3)
	return result

func collect_details(parcel:Dictionary)->void:
	var rect:Rect2=parcel.bounds;var center:Vector2=rect.get_center()
	var cell:=Vector2i(floori(center.x/6000.0),floori(center.y/6000.0))
	var origin:=Vector3((cell.x+.5)*6000.0,0,(cell.y+.5)*6000.0)
	if not detail_writers.has(cell):detail_writers[cell]={"writer":Meshes.new(),"origin":origin}
	var writer:Object=detail_writers[cell].writer
	for placement:Dictionary in DetailModules.placements(parcel):
		var local:Vector3=Vector3(center.x,25,center.y)+placement.position-origin
		DetailModules.emit(writer,placement.kind,local,int(parcel.seed))
		layout_rows.append({"parcel":parcel.id,"kind":placement.kind,"position":Vector3(center.x,25,center.y)+placement.position})
		detail_instances+=1
func finish_details()->void:
	for cell:Vector2i in detail_writers:
		var data:Dictionary=detail_writers[cell];var mesh:ArrayMesh=data.writer.finish_mesh()
		for surface in mesh.get_surface_count():mesh.surface_set_material(surface,material(int(mesh.surface_get_name(surface)),0))
		var root:=Node3D.new();root.name="DetailRegion_%d_%d"%[cell.x,cell.y];root.position=data.origin;add_child(root);detail_regions.append(root)
		var visual:=MeshInstance3D.new();visual.name="BatchedModules";visual.mesh=mesh;visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(visual)
		var shadow:=MeshInstance3D.new();shadow.name="ShadowCaster";shadow.mesh=shadow_mesh(mesh);shadow.material_override=StandardMaterial3D.new();shadow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY;root.add_child(shadow)
		detail_mesh_triangles+=int(mesh.get_meta("triangles"))
	detail_writers.clear();refresh_quality()

func merge_surfaces(source:ArrayMesh,style:int)->ArrayMesh:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array();arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array();arrays[Mesh.ARRAY_TANGENT]=PackedFloat32Array();arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array();arrays[Mesh.ARRAY_TEX_UV2]=PackedVector2Array();arrays[Mesh.ARRAY_COLOR]=PackedColorArray()
	for surface in source.get_surface_count():
		var data:=source.surface_get_arrays(surface);var role:=int(source.surface_get_name(surface));var mat:ShaderMaterial=source.surface_get_material(surface);var color:Color=mat.get_shader_parameter("base_color");color=color.srgb_to_linear()
		for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:arrays[channel].append_array(data[channel])
		for original:Color in data[Mesh.ARRAY_COLOR]:
			var value:=color
			if role==3:
				var mean:Vector3=Materials.TRIM_MEANS[int(round(original.r*7.0))];value=Color(color.r*mean.x,color.g*mean.y,color.b*mean.z,1)
			value.a=float(role)/8.0;arrays[Mesh.ARRAY_COLOR].append(value)
	var merged:=ArrayMesh.new();merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	for key:StringName in source.get_meta_list():merged.set_meta(key,source.get_meta(key))
	var material_key:="merged/"+str(style)
	if not materials.has(material_key):materials[material_key]=Materials.merged_material(style)
	merged.surface_set_material(0,materials[material_key]);return merged
