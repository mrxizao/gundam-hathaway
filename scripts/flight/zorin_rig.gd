extends Node3D
## Complete GPU-skinned mechanical skeleton. Bone translations always retain rest lengths.
var host:FlightBody
var raw:Node3D
var flight:Node3D
var skeleton:Skeleton3D
var leg_skeleton:Skeleton3D
var joints:Dictionary={}
var rifle:MeshInstance3D
var clock:=0.0
func _init()->void:
	flight=Node3D.new();flight.name="FlightPose";add_child(flight)
	raw=load("res://assets/models/zorin/body_rig.scn").instantiate();flight.add_child(raw)
	skeleton=raw.get_node("Skeleton");leg_skeleton=skeleton
	skeleton.reset_bone_poses()
	for i in skeleton.get_bone_count():joints[skeleton.get_bone_name(i)]=i
	var box:=AABB();var first:=true
	for mesh in skeleton.get_children():
		if not mesh is MeshInstance3D:continue
		box=mesh.get_aabb() if first else box.merge(mesh.get_aabb());first=false
	raw.rotation.y=PI/2;raw.scale=Vector3.ONE*(25.0/box.size.y);raw.position.y=-box.get_center().y*raw.scale.y
	rifle=skeleton.get_node("Pak43A")
func _ready()->void:
	var node:Node=get_parent()
	while node!=null:
		if node is FlightBody:host=node;break
		node=node.get_parent()
## One pose source for keyboard, gamepad and AI. Local +X in the model is forward.
static func sample_pose(body)->Dictionary:
	var local:Vector3=body.global_basis.orthonormalized().inverse()*body.translate_dir
	if not body.translate_mode:local=Vector3(-body.control_input.z,body.control_input.y,body.control_input.x)
	if is_instance_valid(body.nu_systems) and body.nu_systems.pilot_intent_valid:local=body.nu_systems.pilot_intent
	var forward:=clampf(-local.z,-1,1);var lateral:=clampf(local.x,-1,1);var lift:=clampf(local.y,-1,1)
	var dash:float=1.0 if body._qb_timer>0 else 0.0
	if dash>0:
		local=body.global_basis.orthonormalized().inverse()*body._qb_dir.normalized()
		forward=-local.z;lateral=local.x;lift=local.y
	var speed:=clampf(body.fm.speed/maxf(body.profile.player_top_speed(),1),0,1)
	var boost:=1.0 if body.fm.boosting else 0.0
	var pose:Dictionary={
		"flight":Vector3(-forward*(12.0+dash*5.0)-lift*5.0,-lateral*3.0,-lateral*(18.0+dash*7.0)),
		"torso":Vector3(-lateral*2,lateral*5,-speed*2-boost-forward*3),
		"head":Vector3(0,-lateral*4,forward*3)}
	# Both legs trail the same flight vector. Small asymmetry gives balance,
	# without splitting the stance into opposing kicks.
	for side in [-1,1]:
		var key:=str(side)
		pose["arm"+key]=Vector3(-side*(6+absf(lateral)*12+dash*4)-lateral*6,lateral*8,-5-forward*14+maxf(-forward,0)*14+side*lateral*10)
		pose["fore"+key]=Vector3(0,0,22+boost*3+dash*5+maxf(-forward,0)*10+maxf(forward,0)*8+side*lateral*8)
		pose["leg"+key]=Vector3(-side*(4+absf(lateral)*12),lateral*9,-5-forward*(27+dash*11)+side*lateral*11+lift*15+maxf(-forward,0)*12+maxf(-forward,0)*dash*14)
		pose["shin"+key]=Vector3(0,0,-minf(78.0,22+dash*23+side*lateral*16+maxf(-forward,0)*35+maxf(forward,0)*25+maxf(lift,0)*18+maxf(-forward,0)*dash*11))
		pose["foot"+key]=Vector3(0,0,-pose["shin"+key].z*.4)
	# Wrist compensation lets the arm bend visibly while keeping the rifle supported.
	pose.hand1=Vector3(0,0,clampf(8.0-pose.arm1.z-pose.fore1.z,-45.0,30.0))
	# Rifle aim and recoil; the shield retains its separate left arm.
	if body.rifle_cooldown>0:pose.arm1+=Vector3(0,-3,15);pose.fore1+=Vector3(0,0,-8)
	if body.shield_up:
		pose["arm-1"]=Vector3(-20,-24,55);pose["fore-1"]=Vector3(0,-8,-47)
	var attacking:bool=body.saber_active() or body._saber_visual_tail>0 or (is_instance_valid(body.nu_systems) and body.nu_systems.visual_only and body.nu_systems.remote_swing)
	if attacking:
		var phase:Dictionary=preload("res://scripts/flight/saber_motion.gd")._phase(body._saber_visual_clock,preload("res://scripts/flight/saber_motion.gd").style(body.profile))
		var arm_keys:=[Vector3(-5,0,0),Vector3(-22,-38,105),Vector3(-8,5,65),Vector3(18,48,12),Vector3(12,32,8),Vector3(-5,0,0)]
		var fore_keys:=[Vector3(0,0,18),Vector3(0,-5,40),Vector3(0,3,12),Vector3(0,8,8),Vector3(0,5,12),Vector3(0,0,18)]
		var torso_keys:=[Vector3.ZERO,Vector3(-2,-16,4),Vector3(0,4,-4),Vector3(3,20,-8),Vector3(2,12,-4),Vector3.ZERO]
		pose["arm-1"]=arm_keys[phase.a].lerp(arm_keys[phase.b],phase.blend)*Vector3(-1,-1,1)
		pose["fore-1"]=fore_keys[phase.a].lerp(fore_keys[phase.b],phase.blend)*Vector3(1,-1,1)
		pose["hand-1"]=Vector3(0,-15,0)
		pose.arm1=Vector3(-5,0,-5);pose.fore1=Vector3(0,0,18);pose.hand1=Vector3(0,0,-5)
		pose.torso+=torso_keys[phase.a].lerp(torso_keys[phase.b],phase.blend)*Vector3(-1,-1,1)
		pose.flight=Vector3(-4,0,0)
		pose.leg1=Vector3(-4,0,-5);pose["leg-1"]=Vector3(4,0,5)
		pose.shin1=Vector3(0,0,-20);pose["shin-1"]=Vector3(0,0,-24)
	return pose

func _process(delta:float)->void:
	if is_instance_valid(host):step(delta)
func step(delta:float)->void:
	clock+=delta
	var remote:bool=is_instance_valid(host.nu_systems) and host.nu_systems.visual_only
	var swinging:bool=host.saber_active() or host._saber_visual_tail>0 or (remote and host.nu_systems.remote_swing)
	if remote:
		if host.nu_systems.remote_swing and not is_instance_valid(host._blade_anchor):host._show_blade()
		elif not swinging and is_instance_valid(host._blade_anchor):host._hide_blade()
	var pose:=sample_pose(host)
	var blend:=1.0-exp(-(24.0 if swinging else 10.0)*delta)
	flight.quaternion=flight.quaternion.slerp(Quaternion.from_euler(pose.flight*PI/180.0),blend)
	for label in joints:
		var index:int=joints[label]
		var rotation:Vector3=pose.get(label,Vector3.ZERO)*PI/180.0
		var wanted:=Quaternion.from_euler(rotation)
		skeleton.set_bone_pose_rotation(index,skeleton.get_bone_pose_rotation(index).slerp(wanted,blend))
	# Rest translations are never overwritten by animation. Only rotations change.
	skeleton.force_update_all_bone_transforms()
	# Left hand owns the saber; right hand continues to hold Pak43A.
	rifle.visible=true
	if is_instance_valid(host._blade_anchor):host._sync_blade_anchor()
