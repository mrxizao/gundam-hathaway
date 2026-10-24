extends RefCounted
## Measured against the current final-Xi skeleton and the actual Re-GZ nozzle meshes.
## Points are bone/mesh local, so model motion and either Re-GZ form stay attached.
const XI := [
	["Chest",Vector3(-0.00014076,0.02056850,-0.07129055),Vector3(0,0,-1),0.75],
	["Tail",Vector3(-0.00014072,-0.19517675,-0.24609794),Vector3(0,0,-1),1],
	["Tail",Vector3(0.07733428,-0.24105930,-0.25113606),Vector3(0,0,-1),0.9],
	["Tail",Vector3(-0.07761572,-0.23845580,-0.25914878),Vector3(0,0,-1),0.9],
	["Backpack",Vector3(-0.00014070,-0.56996894,-0.42962492),Vector3(0,0,-1),0.85]]
const REGZ := [
	["tripo_part_51",Vector3(-0.01421616,-0.02538153,0.00211222),Vector3(-0.48241230,-0.87116117,0.09141441),1.0],
	["tripo_part_50",Vector3(-0.01364132,-0.02574440,0.00670272),Vector3(-0.46518591,-0.86014238,0.20918213),1.0],
	["tripo_part_69",Vector3(-0.01077058,-0.01046891,0.00039534),Vector3(-0.73406675,-0.67696958,0.05346211),.6],
	["tripo_part_68",Vector3(-0.01057288,-0.01254570,-0.00317845),Vector3(-0.63115794,-0.74411425,-0.21893749),.6]]
# Normal 2.0: six rear backpack mouths and two rear waist outlets.
# Native model-space centres, measured on the new mesh (not the cruise AABB).
const ARIZEUS_NORMAL := [
	["Wing.L",Vector3(-.2207,.185,-.002),Vector3.BACK,.65],
	["Wing.L",Vector3(-.1620,.180,-.001),Vector3.BACK,.65],
	["Wing.L",Vector3(-.1049,.170,-.001),Vector3.BACK,.65],
	["Wing.R",Vector3(.0955,.170,.003),Vector3.BACK,.65],
	["Wing.R",Vector3(.1609,.170,.003),Vector3.BACK,.65],
	["Wing.R",Vector3(.2289,.180,.006),Vector3.BACK,.65],
	["SideArmor.L",Vector3(-.0665,.050,.286),Vector3.BACK,.75],
	["Backpack",Vector3(.0533,.050,.286),Vector3.BACK,.75]]
static func install(body,item:Dictionary,index:int)->bool:
	var spec:Array
	if body.profile.id==SuitProfile.Id.NU_GUNDAM:
		if index>=4:
			if body._model_skel==null:return false
			var foot:int=body._model_skel.find_bone("Foot.R" if index==4 else "Foot.L")
			if foot<0:return false
			item["nozzle_node"]=body._model_skel;item["nozzle_bone"]=foot
			item["nozzle_point"]=Vector3(0,-.025,-.025);item["nozzle_axis"]=Vector3.DOWN;item["nozzle_size"]=.65
			sync(body,item);return true
		var marker:Node3D=body.model_root.find_child("Mount_plume"+str(index),true,false)
		if marker==null:return false
		spec=["",Vector3.ZERO,Vector3.BACK,1.0]
		item["nozzle_node"]=marker;item["nozzle_bone"]=-1
	elif body.profile.id==SuitProfile.Id.SAZABI:
		if index<2:return false
		var shin:Node3D=body.model_root.find_child("Shin_R" if index==2 else "Shin_L",true,false)
		if shin==null:return false
		# Inner lower-leg outlets, carried by each mechanical shin joint.
		spec=["",Vector3(-.055 if index==2 else .055,-.13,.055),Vector3(0,-.35,1).normalized(),.65]
		item["nozzle_node"]=shin;item["nozzle_bone"]=-1
	elif body.profile.id==SuitProfile.Id.XI_FINAL:
		if body._model_skel==null or index>=XI.size():return false
		spec=XI[index]
		var bone:int=body._model_skel.find_bone(spec[0])
		if bone<0:return false
		item["nozzle_node"]=body._model_skel;item["nozzle_bone"]=bone
	elif body.profile.id==SuitProfile.Id.REGZ_CUSTOM:
		if index>=REGZ.size():return false
		spec=REGZ[index]
		var mesh:Node3D=body.model_root.find_child(spec[0],true,false)
		if mesh==null:return false
		item["nozzle_node"]=mesh;item["nozzle_bone"]=-1
	elif body.profile.id==SuitProfile.Id.ARIZEUS and body.profile.form==SuitProfile.ArizeusForm.CRUISE:
		# This form is one rigid mesh without a skeleton. Bind in the mesh's
		# own uncentred coordinates, so pitch/bank/spin and a rebuilt pivot
		# cannot reuse the previous form's frame or model bounds.
		if index>=body.profile.engine_plumes.size():return false
		var mesh:MeshInstance3D=null
		for candidate in body.model_root.find_children("*","MeshInstance3D",true,false):
			if candidate.mesh!=null and candidate.is_visible_in_tree():
				mesh=candidate;break
		if mesh==null:return false
		var box:AABB=mesh.mesh.get_aabb()
		var point:Vector3=box.position+body.profile.engine_plumes[index]*box.size
		spec=["",point,Vector3.BACK,1.0]
		item["nozzle_node"]=mesh;item["nozzle_bone"]=-1
	elif body.profile.id==SuitProfile.Id.ARIZEUS and body.profile.form==SuitProfile.ArizeusForm.NORMAL:
		if body._model_skel==null or index>=ARIZEUS_NORMAL.size():return false
		spec=ARIZEUS_NORMAL[index].duplicate()
		var bone:int=body._model_skel.find_bone(spec[0])
		if bone<0:return false
		var rest:Transform3D=body._model_skel.get_bone_global_rest(bone)
		spec[1]=rest.affine_inverse()*spec[1]
		spec[2]=rest.basis.inverse()*spec[2]
		item["nozzle_node"]=body._model_skel;item["nozzle_bone"]=bone
	else:return false
	item["nozzle_point"]=spec[1];item["nozzle_axis"]=spec[2];item["nozzle_size"]=spec[3]
	sync(body,item)
	return true
static func sync(body,item:Dictionary)->void:
	var node=item.get("nozzle_node")
	if not is_instance_valid(node):return
	var frame:Transform3D=body.global_transform.affine_inverse()*node.global_transform
	if item["nozzle_bone"]>=0:frame=frame*node.get_bone_global_pose(item["nozzle_bone"])
	var axis:Vector3=(frame.basis*item["nozzle_axis"]).normalized()
	var at:Vector3=frame*item["nozzle_point"]+axis*.04
	var up:=Vector3.UP if absf(axis.dot(Vector3.UP))<.98 else Vector3.FORWARD
	var basis:=Basis.looking_at(-axis,up)
	item["local_at"]=at;item["axis"]=axis;item["plume_basis"]=basis
	for key in ["fx","glow","boost","ab","dash"]:
		var effect:Node3D=item.get(key) as Node3D
		if is_instance_valid(effect):effect.transform=Transform3D(basis*float(item["nozzle_size"]),at)
