extends Node3D
## Platform propulsion: measured rear mouths, one set per board.
var board: FlightPedal
var jets: Array[Dictionary] = []
var anchors: Array[Dictionary] = []
var glow_material: StandardMaterial3D

func bind(platform: FlightPedal, model: Node3D) -> void:
	board = platform
	for child in get_children():
		remove_child(child)
		child.queue_free()
	jets.clear()
	anchors.clear()
	glow_material = FX.plume_material(Color(0.48,0.64,1.0,0.45))
	# Coordinates are local to the shared engine housing meshes, so empty/one/two-rider
	# models retain their own transforms and scale without using the rider bounds.
	var housings := [
		["tripo_part_6",[-0.04021,0.02979,-0.00521],[0.007027,-0.048973,-0.021973],0.027],
		["tripo_part_34",[-0.03662,0.03438,-0.00062],[0.000772,-0.055228,-0.028228],0.012]]
	var mounts: Array = []
	if board.kind in [FlightPedal.Kind.KILCE,FlightPedal.Kind.ODYSSEUS]:
		for housing: Array in housings:
			for xy: Vector2i in [Vector2i(0,0),Vector2i(1,0),Vector2i(0,1),Vector2i(1,1),Vector2i(2,2)]:
				mounts.append([housing[0],Vector3(housing[1][xy.x],housing[2][xy.y],housing[3])])
	else:
		# Mafty / commander share the same divided central outlet and platform geometry.
		mounts = [["tripo_part_16",Vector3(0.028146,0.043236,-0.131506)],
			["tripo_part_128",Vector3(0.000312,0.060271,-0.017693)]]
	var radius := 0.55 if board.kind in [FlightPedal.Kind.KILCE,FlightPedal.Kind.ODYSSEUS] else 0.90
	var amount := 16 if board.kind in [FlightPedal.Kind.KILCE,FlightPedal.Kind.ODYSSEUS] else 48
	for mount: Array in mounts:
		var mesh := model.find_child(mount[0],true,false) as Node3D
		if mesh == null:
			push_warning("PedalPropulsion: missing nozzle housing " + str(mount[0]))
			continue
		var point: Vector3 = mount[1]
		var at := to_local(mesh.to_global(point))
		anchors.append({"mesh":mesh,"point":point})
		var smoke := FX.exhaust_smoke(self,at,Vector3.BACK,radius,8)
		var flame := FX.afterburner(self,at,Vector3.BACK,radius,Color(0.48,0.64,1.0,1),amount)
		var dash := FX.afterburner_dash(self,at,Vector3.BACK,radius,Color(0.48,0.64,1.0,1),amount)
		var glow := FX.nozzle_glow(self,at,glow_material,radius*0.73)
		smoke.emitting = false
		flame.emitting = false
		dash.emitting = false
		glow.visible = false
		jets.append({"smoke":smoke,"flame":flame,"dash":dash,"glow":glow})

func _process(_delta: float) -> void:
	var rider: FlightBody = board.owner_rider if is_instance_valid(board) else null
	var active := is_instance_valid(board) and board.is_alive() and board.is_ridden() and is_instance_valid(rider) and rider.alive
	var thrust := active and rider.fm.throttle > 0.05
	var boosting := active and rider.fm.boosting
	var dashing := active and (rider.assist_dashing() or rider.super_dashing())
	for i in jets.size():
		var jet: Dictionary = jets[i]
		var anchor: Dictionary = anchors[i]
		if is_instance_valid(anchor.mesh):
			var at := to_local(anchor.mesh.to_global(anchor.point))
			for key in ["smoke","flame","dash","glow"]: jet[key].position = at
		jet.smoke.emitting = thrust
		jet.flame.emitting = (thrust or boosting) and not dashing
		jet.flame.amount_ratio = 1.0 if boosting else 0.35
		jet.flame.speed_scale = 1.0 if boosting else 0.65
		jet.dash.emitting = dashing
		jet.glow.visible = active
	glow_material.emission_energy_multiplier = 1.25 if boosting or dashing else 0.55
