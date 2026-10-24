extends SceneTree
var metadata:Dictionary
var build_dir:="res://"
func reduced(source:Mesh,label:String)->ArrayMesh:
	var im:=ImporterMesh.new()
	for surface in source.get_surface_count():
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES,source.surface_get_arrays(surface),[],{},source.surface_get_material(surface))
	im.generate_lods(60.0,60.0,[])
	var result:=ArrayMesh.new()
	var count:=0
	for surface in im.get_surface_count():
		var arrays:=im.get_surface_arrays(surface)
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var target:=20000 if "tripo_node" in label else 2500
		var best_score:=absf(log(maxf(indices.size()/3.0,1.0)/target))
		for lod in im.get_surface_lod_count(surface):
			var candidate:=im.get_surface_lod_indices(surface,lod)
			var score:=absf(log(maxf(candidate.size()/3.0,1.0)/target))
			if score<best_score:indices=candidate;best_score=score
		arrays[Mesh.ARRAY_INDEX]=indices
		count+=indices.size()/3
		# Native deindex/index discards unused high-resolution vertices and keeps UVs/skin.
		var temporary:=ArrayMesh.new();temporary.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var tool:=SurfaceTool.new();tool.create_from(temporary,0);tool.deindex();tool.index()
		tool.set_material(im.get_surface_material(surface));tool.commit(result)
	print("DECIMATE ",label," -> ",count)
	return result
func pose_clip(model:Node3D,skel:Skeleton3D,poses:Array,length:float,looped:bool)->Animation:
	var clip:=Animation.new();clip.length=length;clip.loop_mode=Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
	var base:=str(model.get_path_to(skel))
	for bone in mini(39,skel.get_bone_count()):
		var name:=str(skel.get_bone_name(bone));var track:=clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track,NodePath(base+":"+name))
		for i in poses.size():
			var degrees:Vector3=poses[i].get(name,Vector3.ZERO)
			clip.track_insert_key(track,length*float(i)/maxi(1,poses.size()-1),Quaternion.from_euler(degrees*PI/180.0))
	return clip
func mount(model:Node3D,skel:Skeleton3D,bone:String,title:String,world:Vector3)->void:
	var attach:=BoneAttachment3D.new();attach.name="NuAnchor_"+title;attach.bone_name=bone;skel.add_child(attach);attach.owner=model
	var marker:=Marker3D.new();marker.name="Mount_"+title;attach.add_child(marker);marker.owner=model
	marker.position=skel.get_bone_global_rest(skel.find_bone(bone)).affine_inverse()*world
func animate(model:Node3D)->void:
	var skel:Skeleton3D=model.find_children("*","Skeleton3D",true,false)[0]
	var ap:=AnimationPlayer.new();ap.name="AnimationPlayer";model.add_child(ap);ap.owner=model
	var lib:=AnimationLibrary.new();ap.add_animation_library("",lib)
	var fly:Dictionary={"Chest":Vector3(5,0,0),"Thigh.L":Vector3(-12,0,-3),"Thigh.R":Vector3(-7,0,3),"Shin.L":Vector3(25,0,0),"Shin.R":Vector3(18,0,0),"Foot.L":Vector3(-10,0,0),"Foot.R":Vector3(-8,0,0)}
	lib.add_animation("fly",pose_clip(model,skel,[fly,fly],2.4,true))
	var boost:=fly.duplicate();boost["Chest"]=Vector3(12,0,0);boost["Thigh.L"]=Vector3(-25,0,-5);boost["Thigh.R"]=Vector3(-18,0,5)
	lib.add_animation("burst",pose_clip(model,skel,[boost,boost],1.8,true));lib.add_animation("burst_cruise",pose_clip(model,skel,[boost,boost],1.8,true))
	var shoot:=fly.duplicate();shoot["Shoulder.R"]=Vector3(10,0,0);shoot["UpperArm.R"]=Vector3(15,0,0);shoot["Hand.R"]=Vector3(65,0,0)
	var recoil:=shoot.duplicate();recoil["UpperArm.R"]=Vector3(18,0,0)
	lib.add_animation("shoot",pose_clip(model,skel,[shoot,recoil,shoot,shoot],.36,false))
	var shield:=fly.duplicate();shield["Shoulder.L"]=Vector3(0,0,30);shield["UpperArm.L"]=Vector3(80,0,0);shield["LowerArm.L"]=Vector3(-80,0,0)
	lib.add_animation("shield",pose_clip(model,skel,[shield,shield],1.0,true))
	var wind:=fly.duplicate();wind["UpperArm.R"]=Vector3(-55,-25,-15);wind["Hand.R"]=Vector3(65,0,0);wind["Chest"]=Vector3(5,-16,0)
	var slash:=wind.duplicate();slash["UpperArm.R"]=Vector3(115,30,5);slash["LowerArm.R"]=Vector3(30,0,0);slash["Chest"]=Vector3(10,18,0)
	lib.add_animation("slash",pose_clip(model,skel,[wind,wind,slash,fly],.8,false))
	for direction in ["f","b","l","r","u","d","fl","fr","bl","br","ul","ur","dl","dr"]:
		var dash:=boost.duplicate();var side:float=-1 if "l" in direction else (1 if "r" in direction else 0)
		dash["Chest"]=Vector3(-10 if direction=="b" else 16,side*8,side*-10)
		dash["Thigh.L"]=Vector3(-38 if direction=="u" else -18,0,-12);dash["Thigh.R"]=Vector3(15 if direction=="d" else -10,0,12)
		lib.add_animation("dash_"+direction,pose_clip(model,skel,[fly,dash,dash,fly],.75,false))
	mount(model,skel,"Head","head",skel.get_bone_global_rest(skel.find_bone("Head")).origin)
	for side in ["R","L"]:mount(model,skel,"Hand."+side,"hand_"+side,skel.get_bone_global_rest(skel.find_bone("Hand."+side)).origin)
	mount(model,skel,"NuRifle","muzzle_R",Vector3(metadata.rifle_muzzle[0],metadata.rifle_muzzle[1],metadata.rifle_muzzle[2]))
	mount(model,skel,"NuBazooka","nu_bazooka",Vector3(metadata.bazooka_muzzle[0],metadata.bazooka_muzzle[1],metadata.bazooka_muzzle[2]))
	for i in 6:mount(model,skel,"NuDock"+str(i),"nu_dock"+str(i),skel.get_bone_global_rest(skel.find_bone("NuDock"+str(i))).origin)
	for i in 4:
		var bone:="Backpack" if i<2 else ("Shin.L" if i==2 else "Shin.R")
		var at:Vector3=skel.get_bone_global_rest(skel.find_bone(bone)).origin+Vector3((-.04 if i%2==0 else .04) if i<2 else 0,-.04,.06)
		mount(model,skel,bone,"plume"+str(i),at)
func _initialize()->void:
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():build_dir=args[0]
	metadata=JSON.parse_string(FileAccess.get_file_as_string(build_dir.path_join("metadata.json")))
	for label in ["nu_rigged","fin_0","fin_1","fin_2","fin_3","fin_4","fin_5"]:
		var doc:=GLTFDocument.new();var state:=GLTFState.new();assert(doc.append_from_file(build_dir.path_join(label+".glb"),state)==OK)
		var model:=doc.generate_scene(state);assert(model!=null)
		for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):mesh.mesh=reduced(mesh.mesh,str(mesh.name))
		if label=="nu_rigged":animate(model)
		var packed:=PackedScene.new();assert(packed.pack(model)==OK)
		assert(ResourceSaver.save(packed,build_dir.path_join(("nu_gundam" if label=="nu_rigged" else label)+".scn"),ResourceSaver.FLAG_COMPRESS)==OK)
		print("SAVED ",label);model.free()
	quit()
