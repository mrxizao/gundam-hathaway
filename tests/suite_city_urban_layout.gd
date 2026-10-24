extends RefCounted
const Urban = preload("res://scripts/world/city_urban_plan.gd")

static func run(t: T) -> void:
	for mp: MapDef in [MapDef.oenbelli(),MapDef.davao()]:
		t.suite("CityUrbanLayout / "+mp.name_cn)
		var w := WorldBuilder.new()
		w.map=mp
		var ownership: Dictionary = {}
		var kinds: Dictionary = {}
		var shapes: Dictionary = {}
		var headings: Dictionary = {}
		var count := 0
		var checks := {"deterministic":true,"reserved":true,"plots":true,"overlap":true,"street_safe":true,"access":true,"height":true}
		var cb := float(WorldBuilder.CITY_CBLOCK)
		for x in range(-18,18):
			for z in range(-18,18):
				var p := w.city_block_plan(x,z)
				if bool(p["ok"])!=w._city_cell_buildable(x,z): checks["reserved"]=false
				if not p.get("ok",false) or not p["anchor"]: continue
				var ax: int=p["gx0"]; var az: int=p["gz0"]
				var nx: int=p["used"]; var nz: int=p["used_z"]
				shapes[Vector2i(nx,nz)]=true
				for xx in range(ax,ax+nx):
					for zz in range(az,az+nz):
						var cell := Vector2i(xx,zz)
						if ownership.has(cell): checks["overlap"]=false
						ownership[cell]=true
				var lo := Vector2(ax*cb+w.city_road_width(ax)*0.5,az*cb+w.city_road_width(az)*0.5)
				var hi := Vector2((ax+nx)*cb-w.city_road_width(ax+nx)*0.5,(az+nz)*cb-w.city_road_width(az+nz)*0.5)
				p["street_bounds"]=Rect2(lo,hi-lo)
				var safe := Vector2(w.city_block_ceiling(cb,ax,ax+nx),w.city_block_ceiling(cb,az,az+nz))
				var u := Urban.make(p,mp.city_layout,mp.city_seed,safe)
				var again := Urban.make(p,mp.city_layout,mp.city_seed,safe)
				if var_to_bytes(u)!=var_to_bytes(again): checks["deterministic"]=false
				kinds[u["kind"]]=true; headings[u["heading"]]=true
				var parcels: Array=u["parcels"]
				for i in parcels.size():
					var parcel: Dictionary=parcels[i]
					count+=1
					if not Rect2(parcel["plot"]).encloses(parcel["local_bounds"]): checks["plots"]=false
					if not Rect2(p["street_bounds"]).encloses(parcel["bounds"]): checks["street_safe"]=false
					if float(parcel["height"])<=0 or float(parcel["height"])>1: checks["height"]=false
					for j in range(i):
						if Rect2(parcel["local_bounds"]).intersects(parcels[j]["local_bounds"]): checks["overlap"]=false
				var lanes: Array=u["lanes"]
				for i in range(1,lanes.size()):
					var connected := not Rect2(p["street_bounds"]).has_point(lanes[i]["a"]) or not Rect2(p["street_bounds"]).has_point(lanes[i]["b"])
					for j in range(i):
						for tip: Vector2 in [lanes[i]["a"],lanes[i]["b"]]:
							var nearest := Geometry2D.get_closest_point_to_segment(tip,lanes[j]["a"],lanes[j]["b"])
							if tip.distance_to(nearest)<=float(lanes[j]["width"])*0.51+0.1: connected=true
					if not connected: checks["access"]=false
		for key: String in checks: t.ok(checks[key],key+" across every generated block")
		t.gt(count,1000,"over 1000 planned buildings")
		t.gt(shapes.size(),5,"different block dimensions on both axes")
		t.gt(kinds.size(),2,"distinct neighborhood types")
		t.gt(headings.size(),2,"multiple coherent street headings")
		var removed := Vector2i.ZERO
		var wrong := 0
		for axis in 2:
			for gi in range(-18,19):
				for gk in range(-18,18):
					if not w._city_road_inner_suppressed(axis,gi,gk): continue
					removed[axis]+=1
					if w.city_road_width(gi)!=WorldBuilder.CITY_ROAD_W_LOCAL: wrong+=1
					var a := Vector2i(gi-1,gk) if axis==0 else Vector2i(gk,gi-1)
					var b := a+(Vector2i(1,0) if axis==0 else Vector2i(0,1))
					if not w._city_cell_buildable(a.x,a.y) or not w._city_cell_buildable(b.x,b.y): wrong+=1
					var pa := w.city_block_plan(a.x,a.y); var pb := w.city_block_plan(b.x,b.y)
					if pa.get("gx0")!=pb.get("gx0") or pa.get("gz0")!=pb.get("gz0"): wrong+=1
		t.gt(removed.x,30,"x grid roads replaced by shared local access")
		t.gt(removed.y,30,"z grid roads replaced by shared local access")
		t.eq(wrong,0,"arterials and reserved cells remain connected")
		print("CITY_PLAN_METRICS ",mp.name_cn," buildings=",count," shapes=",shapes.keys()," kinds=",kinds.keys()," removed=",removed)
		w.free()

	preload("res://tests/suite_city_placement.gd").run(t)
