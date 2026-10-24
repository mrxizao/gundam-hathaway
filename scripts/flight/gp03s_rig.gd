extends Node3D
## Rigid-part articulation for the supplied, unskinned GP03S asset.
var joints: Dictionary = {}
var rifle: Node3D
var shield: Node3D
var launchers: Array[Node3D] = []
var host: FlightBody
var raw: Node3D
var clock := 0.0
var preview_pose := ""
var preview_direction := Vector3(0,0,-1)
var preview_time := 0.0
var dash_clock := 0.0
var was_dash := false
func _init() -> void:
	raw = Node3D.new();raw.name="ArticulatedBody";add_child(raw)
	var body: Node3D = load("res://assets/models/gp03s/body.scn").instantiate();raw.add_child(body)
	# Source faces +X; game faces -Z. Preserve supplied proportions.
	var box := AABB()
	var first := true
	for m in body.find_children("*","MeshInstance3D",true,false):
		var b: AABB = m.transform * m.get_aabb()
		box = b if first else box.merge(b);first=false
	raw.scale=Vector3.ONE*(18.2/box.size.y)
	raw.rotation.y=PI/2
	raw.position.y=-box.position.y*raw.scale.y
	for side in [-1,1]:
		_joint("arm"+str(side),body,Vector3(0.14,0.28,side*0.17))
		_joint("fore"+str(side),joints["arm"+str(side)],Vector3(0.16,0.09,side*0.18)-Vector3(0.14,0.28,side*0.17))
		_joint("leg"+str(side),body,Vector3(0.09,-0.10,side*0.13))
		_joint("shin"+str(side),joints["leg"+str(side)],Vector3(0.03,-0.19,side*0.035))
	for m in body.find_children("*","MeshInstance3D",true,false):
		var c: Vector3 = m.position + m.get_aabb().get_center()
		var side := 1 if c.z>=0 else -1
		var part := ""
		if absf(c.z)>0.12 and c.y> -0.15 and c.y<0.37 and c.x>0.035:
			part=("fore" if c.y<0.095 else "arm")+str(side)
		elif c.y< -0.14 and absf(c.z)>0.075 and c.x> -0.02:
			part=("shin" if c.y< -0.29 else "leg")+str(side)
		if part!="":
			var saved: Transform3D=m.transform
			var pivot: Node3D=joints[part]
			var pivot_in_body := pivot.transform
			if pivot.get_parent()!=body: pivot_in_body=pivot.get_parent().transform*pivot.transform
			m.owner=null;m.get_parent().remove_child(m);pivot.add_child(m);m.transform=pivot_in_body.affine_inverse()*saved
	var right: Node3D=joints["fore1"]
	var left: Node3D=joints["fore-1"]
	# Grip locations relative to elbow; weapons rotate with the actual forearms.
	rifle=_weapon(right,"rifle",0.49,Vector3(-0.02,-0.14,0),Vector3(0,PI/2,-PI/2))
	shield=_weapon(left,"shield",0.42,Vector3(-0.01,-0.13,-0.085),Vector3(0,PI/2,0))
	for side in [1,-1]:
		var launcher := _weapon(body,"bazooka",1.215,Vector3(0.20,0.35,side*0.245),Vector3(0,PI/2,0))
		launchers.append(launcher)
		_marker(launcher,"bazooka_R" if side==1 else "bazooka_L",Vector3(0,0,0.49))
	_marker(rifle,"muzzle_L",Vector3(0,0,0.49))
	_marker(rifle,"muzzle_R",Vector3(0,0,0.49))
	_marker(right,"hand_L",Vector3(0,-0.20,0)) # Legacy melee alias; physical right hand.
	_marker(right,"hand_R",Vector3(0,-0.20,0))
	_marker(left,"shield_L",Vector3(0,-0.20,0))
	_marker(right,"saber_R",Vector3(0,-0.20,0))
	right.get_node("Mount_saber_R").rotation.y = -PI/2
	_marker(raw,"plume0",Vector3(-0.16,0.21,0.06))
	_marker(raw,"plume1",Vector3(-0.16,0.21,-0.06))
	_marker(joints["shin1"],"plume2",Vector3(-0.08,-0.04,0))
	_marker(joints["shin-1"],"plume3",Vector3(-0.08,-0.04,0))
	_marker(raw,"engine_back",Vector3(-0.14,0.20,0))
	_marker(raw,"engine_left",Vector3(-0.13,0.22,-0.06))
	_marker(raw,"engine_right",Vector3(-0.13,0.22,0.06))
func _joint(key: String,parent: Node3D,pos: Vector3) -> void:
	var n:=Node3D.new();n.name=key;parent.add_child(n);n.position=pos;joints[key]=n
func _weapon(parent: Node3D,key: String,length: float,pos: Vector3,angles: Vector3) -> Node3D:
	var pivot:=Node3D.new();pivot.name=key;parent.add_child(pivot);pivot.position=pos;pivot.basis=Basis(Vector3.BACK,angles.z)*Basis(Vector3.UP,angles.y)*Basis(Vector3.RIGHT,angles.x);pivot.scale=Vector3.ONE*length
	var mesh: Node3D=load("res://assets/models/gp03s/"+key+".scn").instantiate();pivot.add_child(mesh)
	for part in mesh.find_children("*","MeshInstance3D",true,false): part.set_meta("gp03s_weapon",true)
	return pivot
func _marker(parent: Node3D,key: String,pos: Vector3) -> void:
	var marker:=Marker3D.new();marker.name="Mount_"+key;parent.add_child(marker);marker.position=pos
func _ready() -> void:
	var n: Node=get_parent()
	while n!=null:
		if n is FlightBody: host=n;break
		n=n.get_parent()
	animate(0.0)
	# Calibrate the articulated rest pose, excluding carried weapons from hull dimensions.
	var box := AABB()
	var first := true
	var inv := global_transform.affine_inverse()
	for part in raw.find_children("*","MeshInstance3D",true,false):
		if part.get_meta("gp03s_weapon",false): continue
		var b: AABB = (inv * part.global_transform) * part.get_aabb()
		box=b if first else box.merge(b);first=false
	if box.size.y>0.001: raw.scale *= 18.2/box.size.y
func _process(delta: float) -> void:
	animate(delta)
## Pose clock comes from combat, never a free-running sine wave.
func animate(delta: float) -> void:
	clock += delta
	var equipped := preview_pose if preview_pose in ["rifle","bazooka","saber"] else "rifle"
	var blade := preview_pose == "slash"
	var guard := preview_pose == "shield"
	var steer := Vector3.ZERO
	var direction := preview_direction
	var dash := preview_pose == "dash"
	var cut_time := preview_time
	var recoil := 0.0
	if is_instance_valid(host):
		equipped = host.gp03s_equipped()
		blade = host.saber_active() or host._saber_visual_tail > 0.0
		guard = host.shield_up
		steer = host.control_input
		dash = host.fm.boosting or host._qb_timer > 0.0 or host._dash_anim_dir != ""
		direction = Vector3(steer.z,steer.x,-1.0)
		var dirs := {"f":Vector3(0,0,-1),"fr":Vector3(1,0,-1),"r":Vector3(1,0,0),"br":Vector3(1,0,1),"b":Vector3(0,0,1),"bl":Vector3(-1,0,1),"l":Vector3(-1,0,0),"fl":Vector3(-1,0,-1)}
		if host._qb_timer > 0.0:
			direction = host.global_basis.inverse() * host._qb_dir
		elif dirs.has(host._dash_anim_dir):
			direction = dirs[host._dash_anim_dir]
		elif host.translate_dir.length_squared() > 0.001:
			direction = host.global_basis.inverse() * host.translate_dir
		cut_time = host._saber_visual_clock
		recoil = maxf(host.rifle_cooldown / host.profile.rifle_interval,host.bazooka_cd / 1.1)
	if dash and not was_dash: dash_clock = 0.0
	if dash: dash_clock += delta
	was_dash = dash
	var response := 1.0-exp(-delta*18.0) if delta>0 else 1.0
	var drive := direction.normalized() if dash else Vector3.ZERO
	# A brief compression precedes full extension; pose then settles under thrust.
	var launch := clampf(dash_clock/0.13,0.0,1.0) if dash else 0.0
	if not is_instance_valid(host) and dash: launch = clampf(preview_time/0.13,0.0,1.0)
	var compression := sin(launch*PI)*0.22
	var recovery: float = 1.0-0.30*smoothstep(0.28,0.52,dash_clock) if dash else 1.0
	drive *= recovery
	var body_pose := Vector3(drive.x*0.20,PI/2+drive.x*0.10,drive.z*0.30-drive.y*0.18)
	var cut := slash_pose(cut_time)
	if blade: body_pose += cut["body"]
	raw.rotation = raw.rotation.lerp(body_pose,response)
	for side in [1,-1]:
		var arm: Node3D = joints["arm"+str(side)]
		var fore: Node3D = joints["fore"+str(side)]
		var leg: Node3D = joints["leg"+str(side)]
		var shin: Node3D = joints["shin"+str(side)]
		var a := Vector3(steer.z*side*0.10,0,0.10+steer.x*0.08)
		var f := Vector3(0,0,0.30)
		var l := Vector3(-drive.x*side*0.22,drive.y*side*0.13,drive.z*0.35+drive.y*0.28-0.08-compression)
		var k := Vector3(0,0,-0.10-absf(drive.z)*0.32-maxf(drive.y,0.0)*0.40-compression)
		if dash:
			a += Vector3(-drive.x*side*0.25,drive.y*0.15,-drive.z*0.16)
			l.z += drive.x*side*0.26
			k.z -= compression*0.70
			k.z -= maxf(drive.x*side,0.0)*0.22
		if equipped == "rifle" and side==1:
			a.z = 0.55-recoil*0.08; f.z = 0.95+recoil*0.10
		if equipped == "saber" and side==1:
			a = Vector3(0.12,-0.12,0.55); f.z = 0.55
		if guard and side==-1:
			a.z = 0.65; f.z = 1.00
		if equipped == "bazooka":
			a = Vector3(side*0.10,side*0.12,1.05-recoil*0.12); f.z = 0.80+recoil*0.15
		if blade:
			if side==1:
				a = cut["arm"]; f = cut["fore"]
			else:
				a = Vector3(-0.12,0.18,0.50); f.z = 0.75
			l.z += side*cut["brace"]; k.z -= absf(cut["brace"])*0.65
		arm.rotation = arm.rotation.lerp(a,response)
		fore.rotation = fore.rotation.lerp(f,response)
		leg.rotation = leg.rotation.lerp(l,response)
		shin.rotation = shin.rotation.lerp(k,response)
	rifle.visible = equipped == "rifle" and not blade
	shield.visible = equipped != "bazooka"
	for launcher in launchers:
		launcher.visible = equipped == "bazooka"
		launcher.position.x = 0.20-recoil*0.018 if equipped=="bazooka" else 0.20
	# The blade must see this frame's articulated wrist, including recovery.
	if is_instance_valid(host): host._sync_blade_anchor()

static func slash_pose(time: float) -> Dictionary:
	var times := [0.0,0.20,0.38,0.54,0.61,1.08]
	var arms := [Vector3(0.12,-0.12,0.55),Vector3(-0.38,-0.85,1.65),Vector3(0.55,0.48,0.70),Vector3(0.65,0.85,-0.05),Vector3(0.65,0.85,-0.05),Vector3(0.12,-0.12,0.55)]
	var torsos := [Vector3.ZERO,Vector3(-0.08,-0.28,-0.12),Vector3(0.10,0.20,0.18),Vector3(0.13,0.34,0.21),Vector3(0.10,0.29,0.17),Vector3.ZERO]
	var elbows := [0.55,1.10,0.28,0.18,0.18,0.55]
	var brace := [0.0,0.24,-0.18,-0.28,-0.23,0.0]
	var i := 0
	while i<times.size()-2 and time>times[i+1]: i+=1
	var t := clampf((time-times[i])/(times[i+1]-times[i]),0.0,1.0)
	t = t*t*t*(t*(t*6.0-15.0)+10.0)
	return {"arm":arms[i].lerp(arms[i+1],t),"fore":Vector3(0,0,lerpf(elbows[i],elbows[i+1],t)),"body":torsos[i].lerp(torsos[i+1],t),"brace":lerpf(brace[i],brace[i+1],t)}
