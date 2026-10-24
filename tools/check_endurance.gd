extends Node
var removed_calls:=0
var spatial_test:T
signal spatial_finished
func _physics_process(_delta:float)->void:
	if spatial_test==null:return
	var t:=spatial_test;spatial_test=null
	var index=preload("res://scripts/combat/missile_spatial_index.gd")
	index.clear()
	var stage:=Node3D.new();add_child(stage)
	var missiles:Array[Missile]=[];var rng:=RandomNumberGenerator.new();rng.seed=18102026
	for i in 160:
		var m:=Missile.new();m.trail_level=Missile.Trail.LOW;stage.add_child(m);m.set_physics_process(false)
		m.global_position=Vector3(rng.randf_range(-10000,10000),5000+rng.randf_range(-1000,1000),rng.randf_range(-10000,10000))
		m._prev_pos=m.global_position+Vector3(rng.randf_range(-150,150),rng.randf_range(-150,150),rng.randf_range(-150,150));missiles.append(m)
	var checks:=0;var misses:=0;var reduced:=0
	for query in 160:
		var from:=missiles[query].global_position+Vector3(-300,0,0);var to:=from+Vector3(600,0,0)
		var candidates:Array=index.query(get_tree(),from,to,80)
		if candidates.size()<80:reduced+=1
		var exact:Array=[];var filtered:Array=[]
		for m in missiles:
			if Ballistics.segment_distance(from,to,m._prev_pos,m.global_position)<=80:exact.append(m)
		for m in candidates:
			if Ballistics.segment_distance(from,to,m._prev_pos,m.global_position)<=80:filtered.append(m)
		checks+=1
		if exact!=filtered:misses+=1
	t.eq(misses,0,"160 spatial queries preserve exact hits and original tie order")
	t.eq(reduced,checks,"spread-out projectiles avoid scanning most missiles")
	var moving:=missiles[0];moving._prev_pos=Vector3(-200,5000,0);moving.global_position=Vector3(200,5000,0);index.moved(moving)
	t.ok(index.query(get_tree(),Vector3(0,5000,-100),Vector3(0,5000,100),80).has(moving),"same-step movement updates swept-cell coverage")
	moving._prev_pos=Vector3(-1000000,5000,0);moving.global_position=Vector3(1000000,5000,0);index.moved(moving)
	t.ok(index.query(get_tree(),Vector3(0,5000,-100),Vector3(0,5000,100),80).has(moving),"exceptionally long sweeps use bounded wide bucket")
	var long_query:Array=index.query(get_tree(),Vector3(-1000000,-1000000,-1000000),Vector3(1000000,1000000,1000000),80)
	t.eq(long_query.size(),160,"very long query falls back without dropping missiles")
	moving.free()
	var valid:=true
	for m in index.query(get_tree(),Vector3.ZERO,Vector3(0,5000,0),80):
		if not is_instance_valid(m):valid=false
	t.ok(valid,"same-frame free never returns freed candidates")
	stage.free()
	t.eq(index.nodes.size(),0,"match cleanup releases spatial index node references")
	t.eq(index.cells.size(),0,"last missile cleanup releases all spatial buckets")
	spatial_finished.emit()
func _ready()->void:
	await get_tree().process_frame
	var t:=T.new();t.suite("Endurance / cache lifecycle, swept broad phase and smoke budgets")
	var stage:=Node.new();add_child(stage)
	var first:=Node.new();stage.add_child(first);first.add_to_group("endurance_cache")
	var second:=Node.new();stage.add_child(second);second.add_to_group("endurance_cache")
	var a:=Game.group_snapshot(get_tree(),"endurance_cache")
	t.eq(a.size(),2,"initial group membership")
	t.ok(is_same(a,Game.group_snapshot(get_tree(),"endurance_cache")),"same-frame snapshot identity reused")
	var unrelated:=Node.new();stage.add_child(unrelated);unrelated.free()
	t.ok(is_same(a,Game.group_snapshot(get_tree(),"endurance_cache")),"unrelated particle/UI removal does not rebuild missile cache")
	var other:=Node.new();stage.add_child(other);other.add_to_group("endurance_other")
	Game.group_snapshot(get_tree(),"endurance_other");other.free()
	t.ok(is_same(a,Game.group_snapshot(get_tree(),"endurance_cache")),"removal from another cached group preserves this group's snapshot")
	first.free()
	var b:=Game.group_snapshot(get_tree(),"endurance_cache")
	t.eq(b.size(),1,"same-frame free immediately invalidates cached snapshot")
	t.ok(b[0]==second,"surviving typed member remains valid")
	stage.remove_child(second)
	t.eq(Game.group_snapshot(get_tree(),"endurance_cache").size(),0,"removing live member from tree also invalidates cache")
	second.free();stage.free()
	var crowd:=Node.new();add_child(crowd)
	for i in 400:
		var n:=Node.new();crowd.add_child(n);n.add_to_group("endurance_benchmark")
	var snap:=Game.group_snapshot(get_tree(),"endurance_benchmark")
	var begin:=Time.get_ticks_usec()
	for i in 10000:
		for n in snap:
			if not is_instance_valid(n):break
	var old_ms:=float(Time.get_ticks_usec()-begin)/1000;begin=Time.get_ticks_usec()
	for i in 10000:Game.group_snapshot(get_tree(),"endurance_benchmark")
	print("SNAPSHOT_BENCH old_validity_scan_ms=",old_ms," event_invalidated_ms=",float(Time.get_ticks_usec()-begin)/1000," members=400 calls=10000")
	for cycle in 100:
		var node:=crowd.get_child(0);node.free();var current:=Game.group_snapshot(get_tree(),"endurance_benchmark")
		t.eq(current.size(),399-cycle,"repeated same-frame removals do not leave stale references")
	crowd.free()
	t.eq(Game.group_snapshot(get_tree(),"endurance_benchmark").size(),0,"full cleanup releases snapshot members")
	var tick:=Time.get_ticks_usec()
	for i in 300:
		FX._burst_template_cache.clear();FX._smoke_burst_assets(.35)
	var fresh_ms:=float(Time.get_ticks_usec()-tick)/1000;tick=Time.get_ticks_usec()
	for i in 300:FX._smoke_burst_assets(.35)
	print("SMOKE_TEMPLATE_BENCH fresh_ms=",fresh_ms," reused_ms=",float(Time.get_ticks_usec()-tick)/1000," calls=300")
	var assets:=FX._smoke_burst_assets(.35)
	t.ok(is_same(assets,FX._smoke_burst_assets(.35)),"same exact scale shares immutable resources")
	t.near(assets[0].emission_sphere_radius,2.8,.0001,"launch smoke emission radius preserved")
	t.eq(assets[1].radial_segments,12,"launch smoke sphere detail preserved")
	t.eq(assets[1].rings,6,"launch smoke sphere rings preserved")
	t.near(assets[2].initial_velocity_max,19.25,.0001,"ember velocity preserved")
	t.not_ok(is_same(assets[0],FX._smoke_burst_assets(1.8)[0]),"different smoke scales retain independent parameters")
	var smoke_root:=Node3D.new();add_child(smoke_root)
	var s1:=FX.smoke_burst(smoke_root,Vector3.ZERO,.35,1.2,18)
	var s2:=FX.smoke_burst(smoke_root,Vector3.RIGHT*100,.35,2.6,150)
	var p1:=s1.get_child(0) as GPUParticles3D;var p2:=s2.get_child(0) as GPUParticles3D
	t.ok(p1.process_material==p2.process_material and p1.draw_pass_1==p2.draw_pass_1,"factory reuses materials and meshes")
	t.near(p1.lifetime,1.2,.0001,"first burst lifetime remains per instance")
	t.near(p2.lifetime,2.6,.0001,"second burst lifetime remains per instance")
	t.eq(p1.amount,18,"first burst particle count preserved")
	t.eq(p2.amount,150,"second burst particle count preserved")
	smoke_root.free()
	for i in 100:FX._smoke_burst_assets(float(i)+.123)
	t.eq(FX._burst_template_cache.size(),FX.MAX_BURST_TEMPLATES,"arbitrary scale templates remain bounded")
	FX._burst_template_cache.clear()
	spatial_test=t
	await spatial_finished
	if "--focus" in OS.get_cmdline_user_args():
		await preload("res://tests/suite_combat.gd")._perf_cache(t,self)
	for suite in ([] if "--focus" in OS.get_cmdline_user_args() else [["combat",true,true],["rifle_accuracy",true,true],["funnel_guidance",true,true]]):
		await t.run_suite("res://tests/suite_"+suite[0]+".gd",suite[0],self,suite[1],suite[2])
	for i in 8:await get_tree().process_frame
	Node.print_orphan_nodes();t.report();get_tree().quit(1 if t.failed else 0)
