extends RefCounted
var body
var joints:Dictionary={}
var rest:Dictionary={}
var docks:Array[Node3D]=[]
var shotgun:Node3D
var sniper:Node3D
var shield:Node3D
var saber:Node3D
var axe:Node3D
var muzzle:Marker3D
var belly_muzzle:Marker3D
# Front lip of the central abdominal port (tripo_part_69), relative to the torso joint.
const BELLY_PORT:=Vector3(0,-.011,-.165)
var clock:=0.0
var throw_age:=10.0
var shield_rest:=Basis.IDENTITY
func install(unit)->void:
	body=unit
	for name in ["Pelvis","Torso","Head","Backpack","Shoulder_R","Shoulder_L","UpperArm_R","UpperArm_L","Forearm_R","Forearm_L","Hand_R","Hand_L","Thigh_R","Thigh_L","Shin_R","Shin_L","Foot_R","Foot_L","Skirt_R","Skirt_L"]:
		var node:=unit.model_root.find_child(name,true,false) as Node3D
		if node!=null:joints[name]=node;rest[name]=node.transform
	for i in 6:
		var dock:=unit.model_root.find_child("FunnelDock%d" % i,true,false) as Node3D
		if dock!=null:
			_keep_funnel_carrier_on_backpack(dock)
			docks.append(dock)
	if joints.has("Torso"):
		belly_muzzle=Marker3D.new();belly_muzzle.name="SazabiBellyMuzzle"
		joints.Torso.add_child(belly_muzzle);belly_muzzle.position=BELLY_PORT
	if not joints.has("Hand_R"):return
	shotgun=load(preload("res://scripts/flight/low_texture_models.gd").resolve_model("res://data/sazabi_models/shotgun.scn")).instantiate();shotgun.name="ShotgunHeld";joints.Hand_R.add_child(shotgun);shotgun.scale=Vector3.ONE*.34;shotgun.position=Vector3(0,.02,-.10)
	shotgun.basis=Basis(Vector3.RIGHT,-1.2)*Basis(Vector3.UP,PI)*Basis.from_scale(Vector3.ONE*.34)
	shotgun.position=-(shotgun.basis*Vector3(0,-.13,-.20))
	sniper=load(preload("res://scripts/flight/low_texture_models.gd").resolve_model("res://data/sazabi_models/sniper.scn")).instantiate();sniper.name="SniperHeld";joints.Hand_R.add_child(sniper);sniper.scale=Vector3.ONE*.46;sniper.position=Vector3(0,.02,-.18)
	sniper.basis=Basis(Vector3.RIGHT,-1.2)*Basis(Vector3.UP,PI)*Basis.from_scale(Vector3.ONE*.46)
	sniper.position=-(sniper.basis*Vector3(0,-.075,-.265))
	shield=load(preload("res://scripts/flight/low_texture_models.gd").resolve_model("res://data/sazabi_models/shield.scn")).instantiate();shield.name="ShieldHeld";joints.Hand_L.add_child(shield)
	var q:=Quaternion(-.14373346,.52414286,-.22993667,.80730671)
	var canonical:=Basis(Vector3.UP,PI*.5)
	shield.basis=canonical*Basis(q)*Basis.from_scale(Vector3(.702375,.706880,.652622))
	shield_rest=shield.basis
	shield.position=Vector3(-.248626,.550295,-.121095)-Vector3(-.245,.524258,-.14)
	saber=make_blade(false);saber.name="SaberHeld";joints.Hand_R.add_child(saber)
	axe=make_blade(true);axe.name="AxeHeld";joints.Hand_R.add_child(axe)
	muzzle=Marker3D.new();muzzle.name="SazabiRifleMuzzle";joints.Hand_R.add_child(muzzle)
	step(0)
## The imported docks include slices of the two fixed black launch containers.
## Only their six red canisters belong to the detachable weapon visuals.
static func _keep_funnel_carrier_on_backpack(dock:Node3D)->void:
	var backpack:=dock.get_parent() as Node3D
	for part:Node in dock.get_children():
		if part is MeshInstance3D and (str(part.name).begins_with("FunnelPart_3_") or str(part.name).begins_with("FunnelPart_9_")):
			var fixed_transform:Transform3D=dock.transform*part.transform
			dock.remove_child(part);backpack.add_child(part)
			part.transform=fixed_transform

static func make_blade(is_axe:bool)->Node3D:
	if is_axe:return load(preload("res://scripts/flight/low_texture_models.gd").resolve_model("res://data/sazabi_models/axe.scn")).instantiate() as Node3D
	var root:=Node3D.new()
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.65,1,.38);mat.emission_enabled=true;mat.emission=mat.albedo_color;mat.emission_energy_multiplier=2.0
	var shaft:=MeshInstance3D.new();var cylinder:=CylinderMesh.new();cylinder.top_radius=.008;cylinder.bottom_radius=.01;cylinder.height=.26 if is_axe else .33
	shaft.mesh=cylinder;shaft.material_override=mat;shaft.rotation.x=PI*.5;shaft.position.z=-cylinder.height*.5;root.add_child(shaft)
	if is_axe:
		var blade:=MeshInstance3D.new();var mesh:=ImmediateMesh.new();mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,mat)
		for side in [-1.0,1.0]:
			for i in 16:
				var a:float=lerpf(-1.15,1.15,i/16.0);var b:float=lerpf(-1.15,1.15,(i+1)/16.0)
				for p in [Vector3(side*.015,0,-.22),Vector3(side*(.015+cos(a)*.10),0,-.22+sin(a)*.10),Vector3(side*(.015+cos(b)*.10),0,-.22+sin(b)*.10)]:mesh.surface_add_vertex(p)
		mesh.surface_end();mat.cull_mode=BaseMaterial3D.CULL_DISABLED;blade.mesh=mesh;root.add_child(blade)
	return root
func pose(name:String,angles:Vector3,delta:float)->void:
	if not joints.has(name):return
	var goal:Transform3D=rest[name];goal.basis=goal.basis*Basis.from_euler(angles)
	joints[name].transform=joints[name].transform.interpolate_with(goal,1.0-exp(-14.0*delta) if delta>0 else 1.0)
func step(delta:float)->void:
	clock+=delta;throw_age+=delta
	if joints.is_empty():return
	var systems=body.sazabi_systems
	var slot:String=systems.slot()
	var melee:bool=body.saber_active()
	var axe_active:bool=systems.axe_swing and melee
	var motion:Dictionary=preload("res://scripts/flight/nu_sazabi_pose.gd").sample(body,true)
	for joint in ["Pelvis","Torso","Head","Thigh_R","Thigh_L","Shin_R","Shin_L","Foot_R","Foot_L","Shoulder_R","Shoulder_L","Skirt_R","Skirt_L"]:
		pose(joint,motion.get(joint,Vector3.ZERO)*PI/180.0,delta)
	var belly:bool=slot=="cannon" or (is_instance_valid(body.active_cannon) and body.active_cannon.get("sazabi_belly")==true)
	var kick:float=motion.kick
	pose("UpperArm_R",Vector3(.08 if belly else .35+kick*.20+clampf(body.fm.speed/maxf(body.profile.player_top_speed(),1),0,1)*.14,-.10,-.07)+motion.get("UpperArm_R",Vector3.ZERO)*PI/180.0,delta)
	pose("Forearm_R",Vector3(.12 if belly else .85-kick*.12,0,-.10)+motion.get("Forearm_R",Vector3.ZERO)*PI/180.0,delta)
	pose("Hand_R",motion.get("Hand_R",Vector3.ZERO)*PI/180.0,delta)
	pose("UpperArm_L",Vector3(.65 if body.shield_up else .10,.08,.12),delta)
	pose("Forearm_L",Vector3(.95 if body.shield_up else .12,0,.1),delta)
	shotgun.visible=slot=="rifle" and not melee;sniper.visible=slot=="sniper" and not melee
	saber.visible=slot=="saber" and not axe_active and systems.axe_held<=0
	axe.visible=axe_active or (slot=="saber" and systems.axe_held>0 and not systems._axe_thrown)
	shield.basis=Basis(Vector3.RIGHT,-1.38 if body.shield_up else 0.0)*shield_rest
	if not melee and slot in ["rifle","sniper"] and (systems.scoped or body._gun_recoil_clock<.4 or body.fm.speed>body.profile.player_top_speed()*.25):
		var gun:Node3D=sniper if slot=="sniper" else shotgun
		var aim:Vector3=body.aim_dir.normalized()
		if aim.length_squared()>.5:
			var correction:=Basis(Quaternion(gun.global_basis.z.normalized(),aim))
			joints.Hand_R.global_basis=correction*joints.Hand_R.global_basis
	muzzle.global_position=(sniper if slot=="sniper" else shotgun).global_transform*Vector3(0,.02,.49)
func belly_muzzle_local()->Vector3:
	return body.to_local(belly_muzzle.global_position) if is_instance_valid(belly_muzzle) else Vector3(0,3.4,-5.4)
func muzzle_local()->Vector3:
	return body.to_local(muzzle.global_position) if is_instance_valid(muzzle) else Vector3(3,2,-8)
