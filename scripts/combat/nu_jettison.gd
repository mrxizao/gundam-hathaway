extends Node3D
var velocity:=Vector3.ZERO
var spin:=Vector3.ZERO
var life:=5.0
func _physics_process(delta:float)->void:
	global_position+=velocity*delta
	velocity.y-=6.0*delta
	rotate_object_local(Vector3.UP,spin.y*delta);rotate_object_local(Vector3.RIGHT,spin.x*delta)
	life-=delta
	if life<=0:queue_free()
static func spawn(body,bone_name:String,side:float)->void:
	var sk:Skeleton3D=body._model_skel
	if sk==null:return
	var bone:=sk.find_bone(bone_name)
	if bone<0:return
	var debris=load("res://scripts/combat/nu_jettison.gd").new()
	body.projectile_container.add_child(debris);debris.global_position=body.global_position
	debris.velocity=body.fm.velocity+body.right()*side*26.0+Vector3.DOWN*12.0;debris.spin=Vector3(.8,side*1.1,0)
	var final:Transform3D=body.nu_motion.final_poses.get(bone_name,sk.get_bone_global_pose(bone)) if is_instance_valid(body.nu_motion) else sk.get_bone_global_pose(bone)
	var posed:Transform3D=sk.global_transform*final*sk.get_bone_global_rest(bone).affine_inverse()*sk.global_transform.affine_inverse()
	for mesh:MeshInstance3D in body.model_root.find_children(bone_name+"_*","MeshInstance3D",true,false):
		var clone:=MeshInstance3D.new();clone.mesh=mesh.mesh;clone.material_override=mesh.material_override;debris.add_child(clone)
		clone.global_transform=posed*mesh.global_transform
