extends RefCounted
## Visible weapon ports, kept separate from camera rays and locomotion anchors.
static var _bindings:Dictionary={}
var host
var head_bone := -1
var head_node: Node3D
var head_points: Array[Vector3] = []
var head_box := AABB()
var head_signatures := {}
var rifle_signatures := {}
var rifle_bone := -1
var rifle_point := Vector3.ZERO
var mounted_id := 0
var mounted_head: MeshInstance3D
var mounted_rifle: MeshInstance3D

static func signature(mesh: Mesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count(): count+=mesh.surface_get_array_index_len(surface)
	return count

static func box_of(points: Array[Vector3]) -> AABB:
	if points.is_empty(): return AABB()
	var axes: Array = [[],[],[]]
	for point in points:
		for axis in 3: axes[axis].append(point[axis])
	var lo := Vector3.ZERO
	var hi := Vector3.ZERO
	for axis in 3:
		axes[axis].sort()
		lo[axis]=axes[axis][int((points.size()-1)*.01)]
		hi[axis]=axes[axis][int((points.size()-1)*.99)]
	return AABB(lo,hi-lo)

static func skin_bone(sk: Skeleton3D, skin: Skin, bind: int) -> int:
	var name := str(skin.get_bind_name(bind))
	return sk.find_bone(name) if not name.is_empty() else skin.get_bind_bone(bind)

static func below(sk: Skeleton3D, bone: int, ancestor: int) -> bool:
	while bone>=0:
		if bone==ancestor:return true
		bone=sk.get_bone_parent(bone)
	return false

static func mesh_points(body, mesh: MeshInstance3D) -> Array[Vector3]:
	var points: Array[Vector3]=[]
	var xf: Transform3D=body.global_transform.affine_inverse()*mesh.global_transform
	for point in preload("res://scripts/flight/mesh_sample_cache.gd").sample(mesh.mesh):
		points.append(xf*point)
	return points

static func barrel_tip(points: Array[Vector3], grip: Vector3) -> Vector3:
	if points.is_empty(): return grip
	var center:=Vector3.ZERO
	for p in points:center+=p
	center/=points.size()
	var axis:=Vector3(.31,.73,.51).normalized()
	for iteration in 24:
		var next:=Vector3.ZERO
		for p in points:
			var d:=p-center;next+=d*d.dot(axis)
		if next.length_squared()<.000001:break
		axis=next.normalized()
	var projected: Array[float]=[]
	for p in points:projected.append((p-center).dot(axis))
	projected.sort()
	var lo:float=projected[int((points.size()-1)*.01)]
	var hi:float=projected[int((points.size()-1)*.99)]
	var positive:bool=(center+axis*hi).distance_squared_to(grip)>(center+axis*lo).distance_squared_to(grip)
	var tip:=Vector3.ZERO;var count:=0
	for p in points:
		var value:float=(p-center).dot(axis)
		if value>=hi if positive else value<=lo:
			tip+=p;count+=1
	return tip/maxi(count,1)

func bind(body) -> void:
	host=body
	var sk:Skeleton3D=body._model_skel
	if sk!=null:
		head_bone=sk.find_bone("Head")
		# Penelope's legacy Head also drives its large flight nose. The visible
		# MS helmet has its own mechanical joint below that imported rig.
		if body.profile.id==SuitProfile.Id.PENELOPE and body.profile.form==0:
			var helmet:int=sk.find_bone("Movie_tripo_part_50")
			if helmet>=0:head_bone=helmet
	if body._regz_motion!=null and body._regz_motion.ready and body._regz_motion.joints.has("Head"):
		head_node=body._regz_motion.joints["Head"]
	var key:String=str(body.profile.model_path)+"|"+str(body.profile.form)+"|"+str(body.profile.target_height)+"|"+str(body.model_bounds)
	if _bindings.has(key):
		var cached:Dictionary=_bindings[key]
		head_points.assign(cached["points"]);head_box=cached["box"]
		head_signatures=cached["heads"];rifle_signatures=cached["rifles"]
		rifle_bone=cached["rifle_bone"];rifle_point=cached["rifle_point"]
		if head_bone<0 and not is_instance_valid(head_node):head_node=body.model_pivot
		return
	var points:Array[Vector3]=[]
	for mesh:MeshInstance3D in body.model_root.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null:continue
		var on_head:=is_instance_valid(head_node) and head_node.is_ancestor_of(mesh)
		var on_rifle:bool=str(mesh.name)=="Penelope_Rifle" or (body.profile.id==SuitProfile.Id.PENELOPE and body.profile.form==0 and str(mesh.name)=="tripo_part_11")
		if sk!=null and mesh.skin!=null:
			var head_hits:=0;var samples:=0;var rifle_hits:=0
			var xf:Transform3D=body.global_transform.affine_inverse()*mesh.global_transform
			for surface in mesh.mesh.get_surface_count():
				var arrays:=mesh.mesh.surface_get_arrays(surface)
				var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES]
				var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
				if bones.is_empty():continue
				var stride:int=bones.size()/vertices.size()
				for vertex in range(0,vertices.size(),maxi(1,vertices.size()/1200)):
					var best:=vertex*stride
					for j in range(best,best+stride):
						if weights[j]>weights[best]:best=j
					var bone:=skin_bone(sk,mesh.skin,bones[best]);samples+=1
					if head_bone>=0 and below(sk,bone,head_bone):
						points.append(xf*vertices[vertex]);head_hits+=1
					if bone>=0 and str(sk.get_bone_name(bone)) in ["Weapon.R","Hand.R"]:rifle_hits+=1
			if head_hits>samples*.6:head_signatures[signature(mesh.mesh)]=true
			if rifle_hits>samples*.6 and mesh.mesh.get_aabb().size.length()>body.profile.model_native_height*.18:rifle_signatures[signature(mesh.mesh)]=true
		elif on_head:
			points.append_array(mesh_points(body,mesh));head_signatures[signature(mesh.mesh)]=true
		if on_rifle:
			rifle_signatures[signature(mesh.mesh)]=true
			if body.profile.id==SuitProfile.Id.PENELOPE and body.profile.form==0 and sk!=null:
				rifle_bone=sk.find_bone("Movie_tripo_part_11")
				if rifle_bone>=0:
					var rest:Transform3D=body.global_transform.affine_inverse()*sk.global_transform*sk.get_bone_global_rest(rifle_bone)
					rifle_point=rest.affine_inverse()*barrel_tip(mesh_points(body,mesh),body.rig_anchor("Hand.R"))
	# Imported head bones can also parent folded armour. Keep only the physical
	# head neighbourhood so a distant shield/antenna cannot become a gun port.
	if sk!=null and head_bone>=0 and body.profile.id==SuitProfile.Id.ARIZEUS and body.profile.form==1:
		var center:Vector3=body.rig_anchor("head")
		var extent:Vector3=Vector3(.065,.065,.065)*body.profile.target_height
		var nearby:Array[Vector3]=[]
		for point in points:
			if AABB(center-extent,extent*2.0).has_point(point):nearby.append(point)
		points=nearby
	if points.size()>10:head_box=box_of(points)
	else:
		var center:Vector3=body.rig_anchor("head") if body.anchor_from_model("head") or body.rig!=null else body.model_bounds.get_center()
		if sk==null and head_node==null and not body.anchor_from_model("head"):
			center=body.model_bounds.position+body.model_bounds.size*Vector3(.5,.72,.35)
		var size:Vector3=Vector3.ONE*body.profile.target_height*.12
		head_box=AABB(center-size*.5,size)
	if head_bone<0 and not is_instance_valid(head_node):head_node=body.model_pivot
	for side in [-1.0,1.0]:
		var point:=head_box.get_center()+Vector3(side*head_box.size.x*.24,head_box.size.y*.12,-head_box.size.z*.5)
		if head_bone>=0:
			var rest:Transform3D=body.global_transform.affine_inverse()*sk.global_transform*sk.get_bone_global_rest(head_bone)
			point=rest.affine_inverse()*point
		elif is_instance_valid(head_node):point=head_node.to_local(body.to_global(point))
		head_points.append(point)
	if _bindings.size()>=96:_bindings.erase(_bindings.keys()[0])
	_bindings[key]={"points":head_points.duplicate(),"box":head_box,"heads":head_signatures,"rifles":rifle_signatures,"rifle_bone":rifle_bone,"rifle_point":rifle_point}

func head_local(index: int) -> Vector3:
	_update_mounted()
	if is_instance_valid(mounted_head):
		if not mounted_head.has_meta("head_port_local_points"):
			var box:=box_of(mesh_points(host,mounted_head))
			var ports:Array[Vector3]=[]
			for side in [-1.0,1.0]:
				var at:=box.get_center()+Vector3(side*box.size.x*.24,box.size.y*.12,-box.size.z*.5)
				ports.append(mounted_head.to_local(host.to_global(at)))
			mounted_head.set_meta("head_port_local_points",ports)
		return host.to_local(mounted_head.to_global(mounted_head.get_meta("head_port_local_points")[index%2]))
	var point:Vector3=head_points[index%head_points.size()]
	if head_bone>=0:
		return host.global_transform.affine_inverse()*host._model_skel.global_transform*host._model_skel.get_bone_global_pose(head_bone)*point
	if is_instance_valid(head_node):return host.to_local(head_node.to_global(point))
	if is_instance_valid(host.spin_pivot):return host.spin_pivot.transform.basis*point
	return point

func rifle_local() -> Variant:
	_update_mounted()
	if is_instance_valid(mounted_rifle):
		if not mounted_rifle.has_meta("barrel_tip_local"):
			var grip:Vector3=host.to_global(host._live_weapon_anchor("Hand.R"))
			var points:=mesh_points(host,mounted_rifle)
			var tip:=barrel_tip(points,host.to_local(grip))
			mounted_rifle.set_meta("barrel_tip_local",mounted_rifle.to_local(host.to_global(tip)))
		return host.to_local(mounted_rifle.to_global(mounted_rifle.get_meta("barrel_tip_local")))
	if rifle_bone>=0:
		return host.global_transform.affine_inverse()*host._model_skel.global_transform*host._model_skel.get_bone_global_pose(rifle_bone)*rifle_point
	return null

func _update_mounted() -> void:
	var board:FlightPedal=host.pedal_owner() if host.has_pedal() and host.rider_hidden else null
	var model:Node3D=board._model if is_instance_valid(board) else null
	var id:int=model.get_instance_id() if is_instance_valid(model) else 0
	if id==mounted_id:return
	mounted_id=id;mounted_head=null;mounted_rifle=null
	if id==0:return
	var head_distance:=INF;var rifle_distance:=INF
	var fallback_rifle:MeshInstance3D
	var fallback_score:=INF
	var grip:Vector3=host.to_global(host._live_weapon_anchor("Hand.R"))
	var expected_head:Vector3=host.to_global(head_box.get_center())
	for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null:continue
		var key:=signature(mesh.mesh)
		var center:Vector3=mesh.to_global(mesh.mesh.get_aabb().get_center())
		# Older loaded platform assets use separately simplified rifle meshes,
		# so topology cannot match the animated source. Select the long rigid
		# barrel nearest the right hand, excluding the platform-sized hull.
		var dimensions:Array[float]=[mesh.mesh.get_aabb().size.x,mesh.mesh.get_aabb().size.y,mesh.mesh.get_aabb().size.z]
		dimensions.sort()
		var world_length:float=dimensions[2]*mesh.global_basis.get_scale().length()/sqrt(3.0)
		if dimensions[2]>dimensions[1]*2.6 and world_length>host.profile.target_height*.23 and world_length<host.profile.target_height*.9:
			var score:float=center.distance_to(grip)
			if score<fallback_score:fallback_score=score;fallback_rifle=mesh
		if head_signatures.has(key) and center.distance_to(expected_head)<head_distance:
			head_distance=center.distance_to(expected_head);mounted_head=mesh
		if (rifle_signatures.has(key) or str(mesh.name)=="Penelope_Rifle") and center.distance_to(host.global_position)<rifle_distance:
			rifle_distance=center.distance_to(host.global_position);mounted_rifle=mesh

	if not is_instance_valid(mounted_rifle) and fallback_score<host.profile.target_height*.7:mounted_rifle=fallback_rifle
