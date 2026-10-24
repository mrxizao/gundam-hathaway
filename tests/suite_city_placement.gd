extends RefCounted
const Placement = preload("res://scripts/world/city_placement.gd")
static func run(t: T) -> void:
	t.suite("CityPlacement / oriented reservations")
	var index := Placement.new()
	index.add_segment(Vector2(-200,-200),Vector2(200,200),40,"test")
	t.eq(index.conflict(Placement.footprint(Vector2.ZERO,Vector2(60,60),0),0),"test","crossing street blocks placement")
	t.eq(index.conflict(Placement.footprint(Vector2(100,-100),Vector2(20,20),45),0),"","rotated AABB overlap alone does not reject a plot")
	var a := Placement.footprint(Vector2.ZERO,Vector2(100,100),0)
	t.not_ok(Placement.overlaps(a,Placement.footprint(Vector2(110,0),Vector2(100,100),0)),"separated rectangles")
	t.ok(Placement.overlaps(a,Placement.footprint(Vector2(110,0),Vector2(100,100),0),12),"clearance includes roadside margin")
	index.add_segment(Vector2(-5000,4100),Vector2(5000,4100),180,"long")
	t.eq(index.conflict(Placement.footprint(Vector2(4000,4100),Vector2(200,200),17),0),"long","index covers bucket boundaries and long road segments")
	for mp: MapDef in [MapDef.oenbelli(),MapDef.davao()]:
		t.suite("CityPlacement / "+mp.name_cn)
		var w := WorldBuilder.new(); w.map=mp
		w._city_prepare_placement()
		t.gt(w._city_placement.corridors.size(),2000,"complete streets prepared before houses")
		var accepted := 0; var relocated := 0; var failures := 0
		for urban: Dictionary in w._city_urban_cache.values():
			for parcel: Dictionary in urban["parcels"]:
				var fit := w._city_fit_parcel(urban,parcel)
				if not fit["ok"]: continue
				accepted+=1
				if fit["relocated"]: relocated+=1
				if w._city_placement.conflict(Placement.footprint(fit["pos"],fit["size"],parcel["yaw"]))!="": failures+=1
				if not w._city_surface_rect_clear(fit["pos"],fit["size"],parcel["yaw"],12): failures+=1
				var origin := Rect2(urban["root"]).get_center()
				var local_at: Vector2=origin+(Vector2(fit["pos"])-origin).rotated(deg_to_rad(float(urban["heading"])))
				var local_poly := Placement.footprint(local_at,fit["size"],float(parcel["yaw"])-float(urban["heading"]))
				if not Rect2(parcel["plot"]).encloses(Placement.bounds(local_poly)): failures+=1
		t.gt(accepted,1000,"city retains populated neighborhoods")
		t.gt(relocated,10,"blocked houses are moved inside their own plots")
		t.eq(failures,0,"every accepted footprint avoids all roads and water")
		var asphalt := w.city_road_width(1)
		t.gt(w.city_road_half_extent(1),asphalt*0.5+89,"sidewalks included in building setbacks")
		var found_mask := 0
		for x in range(-18,19):
			for z in range(-18,19):
				var px := x*w.CITY_CBLOCK; var pz := z*w.CITY_CBLOCK
				if w.is_water_at(px,pz,mp.city_layout):
					found_mask+=1
					if w._city_road_ok(px,pz): failures+=1
		t.gt(found_mask,10,"water samples cover each map")
		t.eq(failures,0,"planned water never accepts a surface road")
		if mp.city_layout==MapDef.CityLayout.OENBELLI:
			var ramps: Array[Transform3D]=[]; var piers: Array[Vector3]=[]
			var sh: Dictionary=w.CITY_SHAPE[mp.city_layout]
			w._build_bridge_ramps_oenbelli(sh.bridge_center,sh.bridge_span,sh.bridge_deck_y,sh.bridge_pos,ramps,piers)
			var wet_low := 0
			for tr: Transform3D in ramps:
				if tr.origin.y>100 or tr.origin.z>60000: continue
				for q: Vector2 in Placement.transformed_footprint(tr):
					if w.is_water_at(q.x,q.y,mp.city_layout): wet_low+=1
			t.eq(wet_low,0,"low spiral ramp and exit are inland")
		else:
			var cell: Vector2i=w.CITY_DAVAO_HOTEL_CELL
			var center := w._city_cell_center(cell.x,cell.y)
			var width := 900.0*float(w.CITY_SHAPE[mp.city_layout]["needle_mul"])
			t.ok(w._city_surface_rect_clear(Vector2(center.x,center.z),Vector2(width,width*0.86),0,24),"hotel foundation lies entirely on dry land")
			t.eq(w._city_placement.conflict(Placement.footprint(Vector2(center.x,center.z),Vector2(width,width*0.86),0)),"","hotel clears surface streets and transport")
		print("CITY_PLACEMENT_CHECK ",mp.name_cn," accepted=",accepted," relocated=",relocated)
		w.free()
