extends SceneTree
const LEG_PARTS:=[2,3,4,9,12,13,17,28,31,32,35,38,40,45,46,49,50,58,68,71,72,77,79,102]
const WINGS:=[15,16,8,37,7,11]
var names:Dictionary={}
var rest:Dictionary={}
var sk:Skeleton3D
func bone(label:String,parent:String,at:Vector3)->void:
	var index:=sk.get_bone_count();sk.add_bone(label);names[label]=index;rest[label]=at
	if parent!="":sk.set_bone_parent(index,names[parent])
	sk.set_bone_rest(index,Transform3D(Basis.IDENTITY,at-(rest[parent] if parent!="" else Vector3.ZERO)))
func _init()->void:
	var source=load("res://assets/models/zorin/raw.scn").instantiate()
	var root:=Node3D.new();root.name="ZorinSkeletonRig"
	sk=Skeleton3D.new();sk.name="Skeleton";root.add_child(sk);sk.owner=root
	bone("root","",Vector3.ZERO);bone("pelvis","root",Vector3(.03,-.075,0));bone("spine","pelvis",Vector3(.025,.03,0));bone("torso","spine",Vector3(.04,.16,0));bone("neck","torso",Vector3(.075,.30,0));bone("head","neck",Vector3(.075,.345,0))
	for side in [-1,1]:
		var key:=str(side)
		bone("shoulder"+key,"torso",Vector3(.06,.245,side*.17));bone("arm"+key,"shoulder"+key,Vector3(.065,.225,side*.18));bone("fore"+key,"arm"+key,Vector3(.08,.095,side*.22));bone("hand"+key,"fore"+key,Vector3(.13,.018,side*.23))
		bone("leg"+key,"pelvis",Vector3(.075,-.12,side*.125));bone("shin"+key,"leg"+key,Vector3(.08,-.255,side*.145));bone("foot"+key,"shin"+key,Vector3(.075,-.423,side*.17))
		bone("armwing"+key,"fore"+key,Vector3(.02,.18,side*.29));bone("backwing"+key,"torso",Vector3(-.126,.31,side*.20));bone("skirtwing"+key,"pelvis",Vector3(-.094,-.02,side*.045))
	# Bone poses are absolute local poses in Godot; initialize them from rest.
	# Without this, default zero translations collapse the leg chain to the hips.
	sk.reset_bone_poses()
	var skin:=Skin.new()
	for label in names:skin.add_bind(names[label],Transform3D(Basis.IDENTITY,-rest[label]))
	var total:=0
	for node in source.find_children("*","MeshInstance3D",true,false):
		var id:=int(str(node.name).get_slice("_",2)) if str(node.name).begins_with("tripo_part_") else -1
		var transform:Transform3D=node.transform;var center:Vector3=transform*node.get_aabb().get_center();var side:=1 if center.z>0 else -1;var key:=str(side)
		var label:="pelvis"
		if id in WINGS:label=("armwing" if id in [15,16] else ("backwing" if id in [8,37] else "skirtwing"))+key
		elif id==-1:label="hand1" if side==1 else "fore-1"
		elif id in [5,6,20]:label="shoulder"+key
		elif absf(center.z)>.15 and center.y>-.1 and center.y<.34 and center.x>0:
			label=("arm" if center.y>.14 else ("fore" if center.y>.035 else "hand"))+key
		elif center.y>.30:label="head"
		elif center.y>.09:label="torso"
		elif center.y>-.035:label="spine"
		var mesh:=ArrayMesh.new()
		for surface in node.mesh.get_surface_count():
			var arrays:Array=node.mesh.surface_get_arrays(surface)
			var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL];var tangents:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT]
			var bones:=PackedInt32Array();var weights:=PackedFloat32Array();bones.resize(points.size()*4);weights.resize(points.size()*4)
			for i in points.size():
				points[i]=transform*points[i]
				if normals.size()>i:normals[i]=(transform.basis*normals[i]).normalized()
				if tangents.size()>i*4+2:
					var tangent:Vector3=transform.basis*Vector3(tangents[i*4],tangents[i*4+1],tangents[i*4+2]);tangents[i*4]=tangent.x;tangents[i*4+1]=tangent.y;tangents[i*4+2]=tangent.z
				if id in LEG_PARTS:
					var vertex_side:=str(-1 if points[i].z<0 else 1)
					var upper:=smoothstep(-.29,-.22,points[i].y);var foot:=1-smoothstep(-.445,-.405,points[i].y)
					bones[i*4]=names["leg"+vertex_side];bones[i*4+1]=names["shin"+vertex_side];bones[i*4+2]=names["foot"+vertex_side]
					weights[i*4]=upper;weights[i*4+1]=maxf(0,1-upper-foot);weights[i*4+2]=foot
				else:bones[i*4]=names[label];weights[i*4]=1.0
			arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TANGENT]=tangents;arrays[Mesh.ARRAY_BONES]=bones;arrays[Mesh.ARRAY_WEIGHTS]=weights
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh.surface_set_material(surface,node.mesh.surface_get_material(surface));total+=points.size()
		var copy:=MeshInstance3D.new();copy.name="Part"+str(id) if id>=0 else ("Pak43A" if side==1 else "Shield")
		if id in WINGS:copy.name="ZorinDock%d_part"%WINGS.find(id)
		copy.mesh=mesh;copy.skin=skin;sk.add_child(copy);copy.owner=root;copy.skeleton=NodePath("..")
		if id in WINGS:
			var attach:=BoneAttachment3D.new();attach.name="DockBone"+str(id);attach.bone_name=label;sk.add_child(attach);attach.owner=root
			var marker:=Marker3D.new();marker.name="Mount_nu_dock"+str(WINGS.find(id));attach.add_child(marker);marker.owner=root;marker.position=center-rest[label]
	for entry in [["muzzle_L","hand1",Vector3(.91,-.15,.20)],["hand_L","hand-1",Vector3(.15,.01,-.23)],["saber_R","hand-1",Vector3(.15,.01,-.23)]]:
		var attach:=BoneAttachment3D.new();attach.name="Anchor"+entry[0];attach.bone_name=entry[1];sk.add_child(attach);attach.owner=root
		var marker:=Marker3D.new();marker.name="Mount_"+entry[0];attach.add_child(marker);marker.owner=root;marker.position=entry[2]-rest[entry[1]]
		if entry[0]=="saber_R":marker.rotation.y=-PI/2
	var packed:=PackedScene.new();packed.pack(root)
	print("FULL_RIG_SAVE ",ResourceSaver.save(packed,"res://assets/models/zorin/body_rig.scn",ResourceSaver.FLAG_COMPRESS)," BONES ",sk.get_bone_count()," VERTICES ",total)
	source.free();root.free();quit()
