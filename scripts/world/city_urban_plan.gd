extends RefCounted
## Deterministic street-block subdivision. Major roads and landmark reservations
## remain owned by WorldBuilder; parcels and internal lanes share this plan.

static func district(gx: int, gz: int, layout: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	var dx := int(floor(float(gx)/3.0))
	var dz := int(floor(float(gz)/3.0))
	rng.seed = seed_value ^ (dx*73856093) ^ (dz*19349663) ^ 0x3A1D907B
	var pick := rng.randf()
	var kind := "mixed"
	if layout == 0:
		if gx < -7: kind = "campus"
		elif gz < -8: kind = "courtyard"
		elif gz >= 3: kind = "waterfront"
		else: kind = "campus" if pick<0.30 else ("courtyard" if pick<0.55 else "mixed")
	else:
		kind = "lanes" if pick<0.46 else ("courtyard" if pick<0.72 else "mixed")
	var headings := [-12.0,0.0,9.0,18.0] if layout==0 else [-18.0,-7.0,0.0,13.0,26.0]
	return {"kind":kind,"heading":headings[rng.randi_range(0,headings.size()-1)]}

static func make(plan: Dictionary, layout: int, seed_value: int, safe_size: Vector2) -> Dictionary:
	var gx: int = plan["gx0"]
	var gz: int = plan["gz0"]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ (gx*92837111) ^ (gz*689287499) ^ 0x29B48F17
	var area := Vector2(float(plan["edge"]),float(plan["edge_z"]))
	var origin: Vector2 = Vector2(plan["pos"].x,plan["pos"].z)
	var zone := district(gx,gz,layout,seed_value)
	var kind: String = zone["kind"]
	var heading := float(zone["heading"])
	var angle := deg_to_rad(heading)
	var ca0 := absf(cos(angle))
	var sa0 := absf(sin(angle))
	var rotated_size := Vector2(ca0*area.x+sa0*area.y,sa0*area.x+ca0*area.y)
	var root_fit := minf(1.0,minf(safe_size.x/rotated_size.x,safe_size.y/rotated_size.y))*0.98
	area*=root_fit
	rotated_size*=root_fit
	# Setbacks follow one frontage rather than keeping every group at the cell centre.
	var room := (safe_size-rotated_size)*0.5
	var frontage := rng.randi_range(0,3)
	if frontage==0: origin.x -= room.x*0.85
	elif frontage==1: origin.x += room.x*0.85
	elif frontage==2: origin.y -= room.y*0.85
	else: origin.y += room.y*0.85
	var root := Rect2(origin-area*0.5,area)
	var count: int = plan["grade"]["n"]
	var public_space := count>=4 and (kind!="lanes" or rng.randf()<0.35)
	var leaves: Array[Rect2] = [root]
	var lanes: Array[Dictionary] = []
	var lane_width := clampf(minf(area.x,area.y)*0.034,42.0,100.0)
	# Unequal recursive splits yield T junctions, deep plots and different frontages.
	while leaves.size()<count+(1 if public_space else 0):
		var largest := 0
		for n in leaves.size():
			if leaves[n].get_area()>leaves[largest].get_area(): largest=n
		var r: Rect2 = leaves[largest]
		var along_x := r.size.x>r.size.y
		if maxf(r.size.x,r.size.y)/minf(r.size.x,r.size.y)<1.5 and rng.randf()<0.30:
			along_x = not along_x
		var split := rng.randf_range(0.34,0.66)
		var first: Rect2
		var second: Rect2
		var a: Vector2
		var b: Vector2
		if along_x:
			var cut := r.position.x+r.size.x*split
			first=Rect2(r.position,Vector2(cut-r.position.x-lane_width*0.5,r.size.y))
			second=Rect2(Vector2(cut+lane_width*0.5,r.position.y),Vector2(r.end.x-cut-lane_width*0.5,r.size.y))
			a=Vector2(cut,r.position.y); b=Vector2(cut,r.end.y)
		else:
			var cut := r.position.y+r.size.y*split
			first=Rect2(r.position,Vector2(r.size.x,cut-r.position.y-lane_width*0.5))
			second=Rect2(Vector2(r.position.x,cut+lane_width*0.5),Vector2(r.size.x,r.end.y-cut-lane_width*0.5))
			a=Vector2(r.position.x,cut); b=Vector2(r.end.x,cut)
		if minf(first.size.x,first.size.y)<90 or minf(second.size.x,second.size.y)<90: break
		leaves.remove_at(largest)
		leaves.append(first); leaves.append(second)
		lanes.append({"a":a,"b":b,"width":lane_width})
	# Rotate streets and plots together. Every lane that reaches an outer
	# block edge extends to its perimeter road, including parallel branches.
	var street: Rect2 = plan["street_bounds"]
	for lane: Dictionary in lanes:
		var local_a: Vector2 = lane["a"]
		var local_b: Vector2 = lane["b"]
		var a := origin+(local_a-origin).rotated(-angle)
		var b := origin+(local_b-origin).rotated(-angle)
		var direction := (b-a).normalized()
		if _on_edge(local_a,root): a=_exit_to_street(a,-direction,street)
		if _on_edge(local_b,root): b=_exit_to_street(b,direction,street)
		lane["a"]=a; lane["b"]=b
	var reserve := -1
	if public_space:
		reserve=0
		for n in leaves.size():
			if leaves[n].get_center().distance_squared_to(root.get_center())<leaves[reserve].get_center().distance_squared_to(root.get_center()): reserve=n
	var parcels: Array[Dictionary] = []
	var greens: Array[Rect2] = []
	var anchor := -1
	for n in leaves.size():
		if n!=reserve and (anchor<0 or leaves[n].get_area()>leaves[anchor].get_area()): anchor=n
	for n in leaves.size():
		var plot: Rect2 = leaves[n]
		if n==reserve:
			var inner := plot.grow(-lane_width*0.45)
			var green_fit := minf(inner.size.x/(ca0*inner.size.x+sa0*inner.size.y),inner.size.y/(sa0*inner.size.x+ca0*inner.size.y))
			var green_size := inner.size*green_fit
			var green_center := origin+(inner.get_center()-origin).rotated(-angle)
			greens.append(Rect2(green_center-green_size*0.5,green_size))
			continue
		var yaw := rng.randf_range(-2.0,2.0)
		if kind=="courtyard" and n%2==1: yaw+=90
		var size := plot.size*Vector2(rng.randf_range(0.69,0.89),rng.randf_range(0.63,0.88))
		if kind=="campus" and n==anchor: size=plot.size*Vector2(0.90,0.78)
		var rad := deg_to_rad(yaw)
		var ca := absf(cos(rad)); var sa := absf(sin(rad))
		var extent := Vector2(ca*size.x+sa*size.y,sa*size.x+ca*size.y)
		var fit := minf(1.0,minf(plot.size.x*0.89/extent.x,plot.size.y*0.89/extent.y))
		size*=fit; extent*=fit
		var gap := (plot.size-extent)*0.5
		var p := plot.get_center()+Vector2(gap.x*rng.randf_range(-0.7,0.7),gap.y*rng.randf_range(-0.7,0.7))
		var height := rng.randf_range(0.27,0.77)
		if n==anchor: height=rng.randf_range(0.88,1.0)
		elif kind=="campus" or kind=="waterfront": height=rng.randf_range(0.22,0.48)
		elif kind=="courtyard": height=rng.randf_range(0.28,0.55)
		var local_bounds := Rect2(p-extent*0.5,extent)
		p=origin+(p-origin).rotated(-angle)
		yaw+=heading
		var wrad := deg_to_rad(yaw)
		extent=Vector2(absf(cos(wrad))*size.x+absf(sin(wrad))*size.y,absf(sin(wrad))*size.x+absf(cos(wrad))*size.y)
		parcels.append({"slot":n,"plot":plot,"local_bounds":local_bounds,"pos":p,"size":size,"bounds":Rect2(p-extent*0.5,extent),"yaw":yaw,"height":height,"lowrise":height<0.48})
	return {"kind":kind,"root":root,"heading":heading,"parcels":parcels,"lanes":lanes,"greens":greens}

static func _on_edge(p: Vector2, r: Rect2) -> bool:
	return absf(p.x-r.position.x)<0.1 or absf(p.x-r.end.x)<0.1 or absf(p.y-r.position.y)<0.1 or absf(p.y-r.end.y)<0.1

static func _exit_to_street(p: Vector2, d: Vector2, street: Rect2) -> Vector2:
	var distance := INF
	if d.x>0.0001: distance=minf(distance,(street.end.x-p.x)/d.x)
	elif d.x< -0.0001: distance=minf(distance,(street.position.x-p.x)/d.x)
	if d.y>0.0001: distance=minf(distance,(street.end.y-p.y)/d.y)
	elif d.y< -0.0001: distance=minf(distance,(street.position.y-p.y)/d.y)
	return p+d*(maxf(0,distance)+12.0)

## Partition each arterial district independently. The same cell ownership drives
## building placement and suppression of old internal grid roads on both axes.
static func blocks(valid: Dictionary, seed_value: int, half: int) -> Dictionary:
	var owners: Dictionary = {}
	var start := int(floor(float(-half)/5.0))*5
	for ax in range(start,half,5):
		for az in range(start,half,5):
			var lo := Vector2i(maxi(ax,-half),maxi(az,-half))
			var hi := Vector2i(mini(ax+5,half),mini(az+5,half))
			if hi.x<=lo.x or hi.y<=lo.y: continue
			var rng := RandomNumberGenerator.new()
			rng.seed=seed_value ^ (ax*73856093) ^ (az*19349663) ^ 0x63BE91F
			_split_block(Rect2i(lo,hi-lo),valid,owners,rng)
	return owners

static func _split_block(r: Rect2i, valid: Dictionary, owners: Dictionary, rng: RandomNumberGenerator) -> void:
	var all_valid := true
	for x in range(r.position.x,r.end.x):
		for z in range(r.position.y,r.end.y):
			if not valid.has(Vector2i(x,z)): all_valid=false
	var area := r.size.x*r.size.y
	var keep := all_valid and r.size.x<=3 and r.size.y<=3 and area<=6
	if keep and area>2: keep=rng.randf()>0.20
	if area==1:
		if all_valid: owners[r.position]=r
		return
	if keep:
		for x in range(r.position.x,r.end.x):
			for z in range(r.position.y,r.end.y): owners[Vector2i(x,z)]=r
		return
	var along_x := r.size.x>r.size.y
	if r.size.x==r.size.y: along_x=rng.randf()<0.5
	if r.size.x==1: along_x=false
	if r.size.y==1: along_x=true
	var cut := rng.randi_range(1,(r.size.x if along_x else r.size.y)-1)
	if along_x:
		_split_block(Rect2i(r.position,Vector2i(cut,r.size.y)),valid,owners,rng)
		_split_block(Rect2i(r.position+Vector2i(cut,0),Vector2i(r.size.x-cut,r.size.y)),valid,owners,rng)
	else:
		_split_block(Rect2i(r.position,Vector2i(r.size.x,cut)),valid,owners,rng)
		_split_block(Rect2i(r.position+Vector2i(0,cut),Vector2i(r.size.x,r.size.y-cut)),valid,owners,rng)
