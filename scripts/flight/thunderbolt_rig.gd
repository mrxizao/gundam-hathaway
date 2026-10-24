extends Node3D
@export var psycho:=false
var host:FlightBody
var model:Node3D
var joints:Dictionary={}
var rests:Dictionary={}
var axe:Node3D
var struts:Array[MeshInstance3D]=[]
var _motion := Vector3.ZERO
var _turn := 0.0
var _last_forward := Vector3.FORWARD
var _shot_blend := 0.0
# Model-space centers measured on the actual colored nozzle rims. Each anchor
# belongs to its mesh, so flame origins and axes follow the animated hardware.
# Full Armor: shoulder/upper back 4, round lower ports 2, waist 2,
# calf rectangular ports 2, calf side verniers 4, sole ports 2 = 16.
const ARMOR_NOZZLES := [
	[2,Vector3(-2.2,7.65,4.05),Vector3.BACK],
	[22,Vector3(2.15,7.55,4.1),Vector3.BACK],
	[40,Vector3(-1.95,1.0,2.55),Vector3.BACK],
	[49,Vector3(1.85,1.0,2.56),Vector3.BACK],
	[2,Vector3(-5.57,7.2,2.75),Vector3(-.9,0,.43589),1.15],
	[22,Vector3(5.62,7.2,2.75),Vector3(.9,0,.43589),1.15],
	[31,Vector3(-4.2,1.0,4.24),Vector3.BACK,.8],
	[30,Vector3(4.1,1.0,4.15),Vector3.BACK,.8],
	[21,Vector3(-3.4,-5.8,2.68),Vector3.BACK,.8],
	[53,Vector3(2.95,-5.8,2.65),Vector3.BACK,.8],
	[60,Vector3(-5.14,-5.6,1.14),Vector3.LEFT,.6],
	[39,Vector3(-1.53,-5.8,.7),Vector3.RIGHT,.6],
	[41,Vector3(5.04,-5.6,1.1),Vector3.RIGHT,.6],
	[37,Vector3(1.45,-5.8,.65),Vector3.LEFT,.6],
	[28,Vector3(-3.8,-10.83,1.55),Vector3.DOWN,.85],
	[29,Vector3(3.7,-10.85,1.5),Vector3.DOWN,.85]]
# Psycho Zaku: fuel tanks 5, main pack 4, lower pack 8, legs 6 = 23.
const ZAKU_NOZZLES := [
	[11,Vector3(-2.47,3.7,32.82),Vector3.BACK,1.35],
	[36,Vector3(1.43,3.7,32.8),Vector3.BACK,1.35],
	[39,Vector3(-.52,5.68,32.7),Vector3.BACK,1.35],
	[54,Vector3(-.52,2.24,32.72),Vector3.BACK,1.1],
	[5,Vector3(-3.2,13.8,21.45),Vector3.BACK,.75],
	[1,Vector3(2.1,13.8,21.5),Vector3.BACK,.75],
	[0,Vector3(-.5,9.85,26.48),Vector3.BACK,.7],
	[0,Vector3(-.5,11.1,26.48),Vector3.BACK,.7],
	[0,Vector3(-.5,12.65,26.48),Vector3.BACK,.7],
	[2,Vector3(-1.1,-3.15,18.65),Vector3.BACK,.5],
	[2,Vector3(.05,-3.15,18.65),Vector3.BACK,.5],
	[2,Vector3(-.52,-4.4,19.6),Vector3.BACK,.75],
	[2,Vector3(-.5,-5.6,19.25),Vector3(0,-.5,.866025),.65],
	[2,Vector3(-2.1,-4.6,17.9),Vector3(-.7,0,.714143),.45],
	[2,Vector3(.9,-4.6,17.9),Vector3(.7,0,.714143),.45],
	[2,Vector3(-1.75,-5.35,17.55),Vector3(-.5,-.5,.707107),.45],
	[2,Vector3(.65,-5.35,17.65),Vector3(.5,-.5,.707107),.45],
	[19,Vector3(-6.2,-7.8,2.95),Vector3(-.4,-.5,.768115),.65],
	[12,Vector3(-3.75,-8.5,3.8),Vector3(0,-.45,.893029),.75],
	[74,Vector3(-1.95,-8.95,2.64),Vector3(0,-.65,.759934),.6],
	[62,Vector3(6.35,-7.8,3.08),Vector3(.4,-.5,.768115),.65],
	[15,Vector3(3.7,-8.5,3.8),Vector3(0,-.45,.893029),.75],
	[15,Vector3(1.95,-8.95,2.64),Vector3(0,-.65,.759934),.6]]

func _calibrate_nozzles()->void:
	for old in model.find_children("Mount_plume*","Marker3D",true,false):old.free()
	var entries = ZAKU_NOZZLES if psycho else ARMOR_NOZZLES
	for index in entries.size():
		var entry=entries[index]
		var part=model.find_child("Part_%03d"%entry[0],true,false) as Node3D
		if part==null:continue
		var marker=Marker3D.new();marker.name="Mount_plume"+str(index);part.add_child(marker)
		var axis:Vector3=entry[2].normalized()
		marker.set_meta("plume_radius",float(entry[3]) if entry.size()>3 else 1.0)
		marker.global_transform=model.global_transform*Transform3D(Basis(Quaternion(Vector3.BACK,axis)),entry[1])

func _ready()->void:
	model=load("res://assets/models/thunderbolt/"+("psycho_zaku" if psycho else "full_armor")+"_rig.scn").instantiate();add_child(model)
	for title in ["Torso","Head","Cannon","ArmL","ArmR","ForeL","ForeR","HandL","HandR","LegL","LegR","ShinL","ShinR","FootL","FootR","ShieldL","ShieldR"]:
		var joint=model.find_child(title,true,false)
		joints[title]=joint;rests[title]=joint.transform
	if not psycho:
		for i in 2:
			var strut=MeshInstance3D.new();var cylinder=CylinderMesh.new();cylinder.top_radius=.13;cylinder.bottom_radius=.17;cylinder.height=1
			strut.mesh=cylinder;var mat=StandardMaterial3D.new();mat.albedo_color=Color(.2,.22,.23);mat.metallic=.75;strut.material_override=mat
			model.add_child(strut);struts.append(strut)
	var node=get_parent()
	while node!=null:
		if node is FlightBody:host=node;break
		node=node.get_parent()
	if psycho:
		axe=load("res://assets/models/thunderbolt/heat_axe.scn").instantiate();joints.HandL.add_child(axe)
		axe.scale=Vector3.ONE*7.0;axe.position=Vector3(0,-2,-1);axe.visible=false
	_calibrate_nozzles()
	if is_instance_valid(host):_last_forward=host.forward()
func _process(delta:float)->void:
	if not is_instance_valid(host):return
	var local:Vector3=host.global_basis.orthonormalized().inverse()*host.translate_dir
	if not host.translate_mode:local=Vector3(-host.control_input.z,host.control_input.y,host.control_input.x)
	var system=host.thunderbolt_systems
	if system!=null and system.visual_only:local=system.remote_motion
	_motion=_motion.lerp(local.limit_length(1.0),1.0-exp(-6.0*delta))
	var f=clampf(-_motion.z,-1,1);var lateral=clampf(_motion.x,-1,1)
	var vertical=clampf(_motion.y,-1,1)
	var facing=host.forward()
	var turn=clampf(_last_forward.cross(facing).y/maxf(delta,.001),-1.0,1.0)
	_last_forward=facing
	_turn=lerpf(_turn,turn,1.0-exp(-5.0*delta))
	var body_gain:=1.12 if psycho else 1.22
	var limb_gain:=1.30 if psycho else 1.22
	var rotation=Vector3(-f*.27-vertical*.16,_turn*.09,-lateral*.14-_turn*.11)*body_gain
	var dash_weight:=0.0
	var dash_direction:=Vector3.ZERO
	var dash:float=system.remote_dash if system!=null and system.visual_only else host._qb_timer
	if dash>0:
		var progress=1.0-dash/host.QB_TIME
		var d:Vector3=system.remote_dash_direction if system!=null and system.visual_only else host.global_basis.inverse()*host._qb_dir
		dash_weight=smoothstep(0.0,.18,progress)*(1.0-smoothstep(.65,1.0,progress))
		dash_direction=d.normalized()
		rotation+=Vector3(d.z*.36-d.y*.26,-d.x*.07,-d.x*.18)*dash_weight*body_gain
	model.quaternion=model.quaternion.slerp(Quaternion.from_euler(rotation),1.0-exp(-8.0*delta))
	var shooting=system!=null and system.shot_pose>0
	_shot_blend=lerpf(_shot_blend,1.0 if shooting else 0.0,1.0-exp(-(18.0 if shooting else 7.0)*delta))
	if not psycho:joints.Cannon.rotation.x=lerpf(joints.Cannon.rotation.x,-.45 if is_instance_valid(host.active_cannon) else 0.0,1-exp(-12*delta))
	for side in [-1,1]:
		var suffix="R" if side==1 else "L"
		var poses={"Arm":Vector3(.15+f*.2,0,-side*.12-lateral*.15),"Fore":Vector3(.20,0,0),"Hand":Vector3.ZERO,"Leg":Vector3(-.15-f*.35+side*lateral*.2,0,-side*.08-lateral*.12),"Shin":Vector3(.30+maxf(f,0)*.4,0,0),"Foot":Vector3(-.18,0,0)}
		# Amplify directional motion around the neutral pose, keeping firing and melee separate.
		poses.Arm.x+=f*.16*limb_gain
		poses.Arm.z-=lateral*.12*limb_gain
		poses.Leg.x+=(-f*.17+side*lateral*.16)*limb_gain
		poses.Leg.z-=lateral*.10*limb_gain
		poses.Shin.x+=maxf(f,0)*.20*limb_gain
		# Offset knees and feet instead of a rigid, symmetrical plank pose.
		poses.Leg.x+=side*(absf(f)*.20+dash_weight*.40)+dash_direction.z*dash_weight*.32
		poses.Leg.z-=dash_direction.x*dash_weight*.26
		poses.Leg.x-=dash_direction.y*dash_weight*.20
		poses.Shin.x+=absf(vertical)*.30+dash_weight*(.60 if side==1 else .32)
		poses.Foot.x-=dash_weight*.22+absf(vertical)*.10
		poses.Arm.x+=vertical*.22+dash_weight*.24
		poses.Arm.z-=dash_direction.x*dash_weight*.18
		poses.Fore.x+=dash_weight*.14
		if side==1:
			poses.Arm.x=lerpf(poses.Arm.x,1.2,_shot_blend)
			poses.Fore.x=lerpf(poses.Fore.x,.12,_shot_blend)
		if side==-1 and host.saber_active():
			var swing=clampf(host._saber_visual_clock/.7,0,1)
			poses.Arm=Vector3(lerpf(2.3,-.65,smoothstep(.20,.80,swing)),.35,-.25)
			poses.Fore=Vector3(.5,0,0)
		for title in poses:
			var joint=joints[title+suffix]
			joint.quaternion=joint.quaternion.slerp(Quaternion.from_euler(poses[title]),1.0-exp(-10*delta))
		var shield=joints["Shield"+suffix];var rest:Transform3D=rests["Shield"+suffix]
		shield.position=shield.position.lerp(Vector3(side*2.5,2.5,-7) if host.shield_up else rest.origin,1-exp(-9*delta))
		if not psycho:
			var strut=struts[0 if side==-1 else 1]
			var start=joints.Torso.to_global(rest.origin)
			var end:Vector3=shield.global_position
			strut.visible=start.distance_to(end)>.2
			if strut.visible:
				strut.global_transform=Transform3D(Basis(Quaternion(Vector3.UP,start.direction_to(end))),(start+end)*.5)
				strut.scale=Vector3(1,start.distance_to(end),1)
	if axe!=null:axe.visible=host.saber_active()
	if psycho:
		for index in [83,84]:
			var bazooka=model.find_child("Part_%03d"%index,true,false)
			if bazooka!=null:bazooka.visible=system!=null and system.secondary_missiles

	# Run after the final joint pose to avoid a one-frame gap between jets and nozzles.
	host._sync_thunderbolt_plumes()
