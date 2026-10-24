extends SkeletonModifier3D
var body
var rifle_meshes:Array[Node3D]=[]
var bazooka_meshes:Array[Node3D]=[]
var final_poses:Dictionary={}
var rotation_cache:Dictionary={}
var rotation_inputs:Dictionary={}
var sampling:=false
func install(unit)->void:
	body=unit
	if unit._model_skel==null:
		queue_free();return
	unit._model_skel.add_child(self)
func rotate_bone(s:Skeleton3D,name:String,degrees:Vector3)->void:
	var bone:=s.find_bone(name)
	if bone>=0:
		var target:=Quaternion.from_euler(degrees*PI/180.0)
		var previous:Quaternion=(rotation_inputs if sampling else rotation_cache).get(name,target)
		var dt:=clampf(get_process_delta_time(),1.0/240.0,.05)
		var result:=previous.slerp(target,1.0-exp(-18.0*dt))
		rotation_cache[name]=result;s.set_bone_pose_rotation(bone,result)
func place(s:Skeleton3D,name:String,wanted:Transform3D)->void:
	var bone:=s.find_bone(name)
	if bone<0:return
	var parent:=s.get_bone_parent(bone)
	var local:Transform3D=s.get_bone_global_pose(parent).affine_inverse()*wanted
	s.set_bone_pose_position(bone,local.origin);s.set_bone_pose_rotation(bone,local.basis.orthonormalized().get_rotation_quaternion())
func _process_modification()->void:
	if not is_instance_valid(body):return
	rotation_inputs=rotation_cache.duplicate();sampling=true
	var s:=get_skeleton();var systems=body.nu_systems
	var slot:String=body.current_slot() if body.has_method("current_slot") else ("bazooka" if systems!=null and systems.bazooka_pose_left>0 else "rifle")
	var scoped:bool=body.has_method("precision_view_active") and body.precision_view_active()
	if systems!=null and systems.visual_only:slot=systems.remote_slot;scoped=systems.remote_scope
	var pose:Dictionary=preload("res://scripts/flight/nu_sazabi_pose.gd").sample(body,false)
	for joint in ["Hips","Spine","Chest","Thigh.R","Thigh.L","Shin.R","Shin.L","Foot.R","Foot.L"]:
		rotate_bone(s,joint,pose.get(joint,Vector3.ZERO))
	for joint in ["Shoulder.L","UpperArm.L","LowerArm.L","Hand.L","Shoulder.R","UpperArm.R","LowerArm.R"]:
		rotate_bone(s,joint,pose.get(joint,Vector3.ZERO))
	if (scoped or slot=="bazooka" or body._gun_recoil_clock<.4) and not (body.saber_active() or body._saber_visual_tail>0):
		rotate_bone(s,"Shoulder.R",Vector3(10,0,0));rotate_bone(s,"UpperArm.R",Vector3(35+float(pose["kick"])*12,0,0))
		rotate_bone(s,"LowerArm.R",Vector3(45-float(pose["kick"])*8,0,0));rotate_bone(s,"Hand.R",Vector3.ZERO)
	if body.shield_up:
		rotate_bone(s,"Shoulder.L",Vector3(10,0,-10))
		rotate_bone(s,"UpperArm.L",Vector3(55,0,0));rotate_bone(s,"LowerArm.L",Vector3(25,0,0))
		var left:int=s.find_bone("LowerArm.L")
		place(s,"NuShield",Transform3D(Basis(Vector3.UP,-PI*.5),s.get_bone_global_pose(left).origin))
	else:
		var shield:int=s.find_bone("NuShield")
		s.set_bone_pose_position(shield,s.get_bone_rest(shield).origin);s.set_bone_pose_rotation(shield,Quaternion.IDENTITY)
	var hand:int=s.find_bone("Hand.R");var backpack:int=s.find_bone("Backpack")
	if hand<0 or backpack<0:sampling=false;return
	var rifle:int=s.find_bone("NuRifle");var bazooka:int=s.find_bone("NuBazooka")
	if slot=="rifle":
		if scoped or body._gun_recoil_clock<.4 or body.fm.speed>body.profile.player_top_speed()*.25:
			var aim:Vector3=(s.global_basis.inverse()*body.aim_dir).normalized()
			if aim.length_squared()<.1:aim=(s.global_basis.inverse()*body.forward()).normalized()
			place(s,"Hand.R",Transform3D(Basis(Quaternion(Vector3(.012,-.9803,-.1971).normalized(),aim)),s.get_bone_global_pose(hand).origin))
		if rifle>=0:s.set_bone_pose_position(rifle,s.get_bone_rest(rifle).origin);s.set_bone_pose_rotation(rifle,Quaternion.IDENTITY)
	else:
		place(s,"NuRifle",s.get_bone_global_pose(backpack)*Transform3D(Basis.from_euler(Vector3(0,0,PI)),Vector3(.12,-.08,.10)))
	if slot=="bazooka":
		var aim:Vector3=(s.global_basis.inverse()*body.aim_dir).normalized()
		if aim.length_squared()<.1:aim=(s.global_basis.inverse()*body.forward()).normalized()
		place(s,"NuBazooka",Transform3D(Basis(Quaternion(Vector3(.0014,-.9998,-.0219).normalized(),aim)),s.get_bone_global_pose(hand).origin))
	elif bazooka>=0:
		s.set_bone_pose_position(bazooka,s.get_bone_rest(bazooka).origin);s.set_bone_pose_rotation(bazooka,Quaternion.IDENTITY)
	# SkeletonModifier results are transient after rendering; retain the final
	# mechanical transforms for equipment debris and model verification.
	for bone_name in ["NuRifle","NuShield","NuBazooka","Chest","Thigh.R","Thigh.L","Foot.R","Foot.L","UpperArm.L","UpperArm.R"]:
		final_poses[bone_name]=s.get_bone_global_pose(s.find_bone(bone_name))
	if is_instance_valid(body._blade_anchor) and (body.saber_active() or body._saber_visual_tail>0):
		var palm:Transform3D=s.global_transform*s.get_bone_global_pose(hand)
		body._blade_anchor.global_transform=Transform3D(palm.basis.orthonormalized()*Basis(Vector3.RIGHT,-PI*.5),palm.origin)
	# Emitters must see the modifier result before Godot restores the input pose.
	body._sync_xi_plumes()
	sampling=false
