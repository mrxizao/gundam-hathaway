extends RefCounted
## Shared plan-view reservation index for surface streets and elevated transport.
## Footprints are oriented rectangles; the broad phase uses the existing grid.
const BUCKET := 4025.0
var corridors: Array[Dictionary] = []
var buckets: Dictionary = {}

static func footprint(center: Vector2, size: Vector2, yaw: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for corner: Vector2 in [Vector2(-0.5,-0.5),Vector2(0.5,-0.5),Vector2(0.5,0.5),Vector2(-0.5,0.5)]:
		points.append(center+(corner*size).rotated(-deg_to_rad(yaw)))
	return points

static func transformed_footprint(t: Transform3D) -> PackedVector2Array:
	var points := PackedVector2Array()
	for corner: Vector3 in [Vector3(-0.5,0,-0.5),Vector3(0.5,0,-0.5),Vector3(0.5,0,0.5),Vector3(-0.5,0,0.5)]:
		var p := t*corner
		points.append(Vector2(p.x,p.z))
	return points

static func bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0],Vector2.ZERO)
	for p: Vector2 in poly: r=r.expand(p)
	return r

static func overlaps(a: PackedVector2Array, b: PackedVector2Array, margin := 0.0) -> bool:
	for poly: PackedVector2Array in [a,b]:
		for i in 2:
			var edge := poly[i+1]-poly[i]
			var axis := Vector2(-edge.y,edge.x).normalized()
			var alo := INF; var ahi := -INF
			var blo := INF; var bhi := -INF
			for p: Vector2 in a:
				var d := p.dot(axis)
				alo=minf(alo,d); ahi=maxf(ahi,d)
			for p: Vector2 in b:
				var d := p.dot(axis)
				blo=minf(blo,d); bhi=maxf(bhi,d)
			if ahi+margin<=blo or bhi+margin<=alo: return false
	return true

func add_polygon(poly: PackedVector2Array, kind: String) -> void:
	var r := bounds(poly)
	var id := corridors.size()
	corridors.append({"poly":poly,"bounds":r,"kind":kind})
	for x in range(int(floor(r.position.x/BUCKET)),int(floor(r.end.x/BUCKET))+1):
		for z in range(int(floor(r.position.y/BUCKET)),int(floor(r.end.y/BUCKET))+1):
			var key := Vector2i(x,z)
			if not buckets.has(key): buckets[key]=[]
			buckets[key].append(id)

func add_segment(a: Vector2, b: Vector2, width: float, kind: String) -> void:
	var d := b-a
	if d.length_squared()<0.01: return
	add_polygon(footprint((a+b)*0.5,Vector2(width,d.length()),rad_to_deg(atan2(d.x,d.y))),kind)

func conflict(poly: PackedVector2Array, clearance := 24.0) -> String:
	var r := bounds(poly).grow(clearance)
	var visited: Dictionary = {}
	for x in range(int(floor(r.position.x/BUCKET)),int(floor(r.end.x/BUCKET))+1):
		for z in range(int(floor(r.position.y/BUCKET)),int(floor(r.end.y/BUCKET))+1):
			for id: int in buckets.get(Vector2i(x,z),[]):
				if visited.has(id): continue
				visited[id]=true
				var road: Dictionary=corridors[id]
				if r.intersects(road["bounds"]) and overlaps(poly,road["poly"],clearance): return road["kind"]
	return ""
