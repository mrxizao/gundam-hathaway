extends Node3D
## Four articulated hidden subarms, plus the two original claw arms when docked.
const CLAW_BLADE_WIDTH := 5.4
const CLAW_BLADE_LENGTH := 3.0
var clock := 0.0
var limbs: Array[Dictionary] = []
var claw_blades: Array[Node3D] = []
var steel := StandardMaterial3D.new()
func _ready() -> void:
	var body := get_parent()
	name = "NeueSixSabers"
	steel.albedo_color = Color(0.12,0.15,0.14)
	steel.metallic = 0.75
	steel.roughness = 0.5
	for side in [-1.0,1.0]:
		for upper in [true,false]:
			var root_arm := Node3D.new()
			root_arm.name = ("Left" if side<0.0 else "Right")+("UpperAuxArm" if upper else "LowerAuxArm")
			add_child(root_arm)
			var a := _rod(0.55)
			var b := _rod(0.40)
			root_arm.add_child(a)
			root_arm.add_child(b)
			var blade := FX.beam_blade_pair(32.0,0.0,body.profile.saber_beam_color)
			root_arm.add_child(blade)
			# Guard prongs distinguish the mechanical hand from its beam blade.
			for sign_v in [-1.0,1.0]:
				var guard := _rod(0.18)
				guard.scale = Vector3(1,2.8,1)
				guard.position = Vector3(sign_v*0.9,0,-0.8)
				guard.rotation_degrees.x = 90
				blade.add_child(guard)
			limbs.append({"root":root_arm,"a":a,"b":b,"blade":blade,"side":side,"upper":upper})
	if not is_instance_valid(body.active_wire_arms):
		for side in ["L","R"]:
			var arm := body.find_child("WireArm_"+side,true,false) as Node3D
			if arm == null:
				continue
			var blade := FX.beam_blade_pair(32.0,0.0,body.profile.saber_beam_color)
			blade.name = "ClawBeamSaber"
			add_child(blade)
			claw_blades.append(blade)
	_update_limbs()

func _rod(radius: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.height = 1.0
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.radial_segments = 8
	mesh.material = steel
	node.mesh = mesh
	return node

func _segment(node: Node3D, a: Vector3, b: Vector3) -> void:
	var dir := b-a
	node.position = (a+b)*0.5
	node.basis = Basis(Quaternion(Vector3.UP,dir.normalized()))
	node.scale = Vector3(1,dir.length(),1)

func _process(delta: float) -> void:
	clock += delta
	_update_limbs()

func _update_limbs() -> void:
	var deploy := smoothstep(0.0,0.18,clock)
	var body := get_parent()
	var style := preload("res://scripts/flight/saber_motion.gd").style(body.profile)
	var cut_time: float = body._saber_visual_clock
	var phase := preload("res://scripts/flight/saber_motion.gd")._phase(cut_time,style)
	var sweep_keys := [0.0,-0.65,0.15,0.72,0.62,0.0]
	var sweep: float = lerpf(sweep_keys[phase.a],sweep_keys[phase.b],phase.blend)
	for limb in limbs:
		var side: float = limb.side
		var level := 1.0 if limb.upper else -1.0
		# Mounts sit inside the shoulder armor; two arms per side, separate from forearms.
		var start := Vector3(side*15.39,18.0+level*6.0,-3.0)
		var elbow := start+Vector3(side*10.0,level*6.0,-6.0)*deploy
		var tip := elbow+Vector3(side*(11.0-4.0*sweep),level*(7.0-3.0*sweep),-10.0-5.0*sweep)*deploy
		_segment(limb.a,start,elbow+Vector3(0,0,-0.001))
		_segment(limb.b,elbow,tip+Vector3(0,0,-0.001))
		var blade: Node3D = limb.blade
		blade.position = tip
		blade.basis = Basis.looking_at(Vector3(side*(0.8+sweep),level*0.6,-1.0).normalized(),Vector3.UP)
		blade.scale = Vector3.ONE*maxf(deploy,0.001)
	var owner_body := get_parent() as Node3D
	for i in claw_blades.size():
		var arm := owner_body.find_child("WireArm_"+("L" if i==0 else "R"),true,false) as Node3D
		if arm == null:
			continue
		var tip := arm.get_node("CannonTip") as Node3D
		claw_blades[i].global_transform = Transform3D(owner_body.global_basis.orthonormalized().scaled_local(Vector3(CLAW_BLADE_WIDTH,CLAW_BLADE_WIDTH,CLAW_BLADE_LENGTH)),tip.global_position)
