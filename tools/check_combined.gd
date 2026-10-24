extends Node
func _ready()->void:
	await get_tree().process_frame
	var t:=T.new()
	var rng:=RandomNumberGenerator.new();rng.seed=18102026
	var rejected:=0;var missed:=0
	for i in 12000:
		var a:=Vector3(rng.randf_range(-100,100),rng.randf_range(-100,100),rng.randf_range(-100,100))
		var b:=a+Vector3(rng.randf_range(-100,100),rng.randf_range(-100,100),rng.randf_range(-100,100))
		var c:=Vector3(rng.randf_range(-100,100),rng.randf_range(-100,100),rng.randf_range(-100,100))
		var d:=c+Vector3(rng.randf_range(-100,100),rng.randf_range(-100,100),rng.randf_range(-100,100))
		if not Ballistics.swept_bounds_overlap(a,b,c,d,20):
			rejected+=1
			if Ballistics.segment_distance(a,b,c,d)<=20:missed+=1
	t.eq(missed,0,"swept bounds never reject an exact hit across 12000 segment pairs")
	t.ok(rejected>6000,"broad phase rejects most distant pairs")
	t.ok(Ballistics.swept_bounds_overlap(Vector3.ZERO,Vector3(100,0,0),Vector3(50,-100,0),Vector3(50,100,0),0),"crossing fast projectiles retained")
	t.ok(Ballistics.swept_bounds_overlap(Vector3.ZERO,Vector3.ZERO,Vector3(80,0,0),Vector3(80,0,0),80),"exact fuse boundary retained")
	var tick:=Time.get_ticks_usec();var hits:=0
	for i in 60000:
		if Ballistics.segment_distance(Vector3.ZERO,Vector3(0,0,100),Vector3(1000,i%100,0),Vector3(1000,i%100,100))<=80:hits+=1
	var original_ms:=float(Time.get_ticks_usec()-tick)/1000;tick=Time.get_ticks_usec()
	for i in 60000:
		var c:=Vector3(1000,i%100,0);var d:=Vector3(1000,i%100,100)
		if Ballistics.swept_bounds_overlap(Vector3.ZERO,Vector3(0,0,100),c,d,80) and Ballistics.segment_distance(Vector3.ZERO,Vector3(0,0,100),c,d)<=80:hits+=1
	print("INTERCEPT_BENCH exact_ms=",original_ms," broadphase_ms=",float(Time.get_ticks_usec()-tick)/1000," hits=",hits)
	Settings.begin_isolated();Settings.set_quality_preset(0)
	var root:=Node3D.new();add_child(root)
	for i in 200:FX.smoke_burst(root,Vector3(i*100,0,0),1,.15,18)
	await get_tree().process_frame
	var budget=get_tree().root.get_node("SmokeBurstBudget")
	t.ok(budget.entries.size()<=48,"missile smoke burst count bounded")
	# Stop GPU playback to reproduce offscreen/paused emitters that never send finished.
	for n in root.get_children():
		for p in n.get_children():
			if p is GPUParticles3D:p.speed_scale=0
	await get_tree().create_timer(.7).timeout
	await get_tree().process_frame
	t.eq(root.get_child_count(),0,"smoke watchdog frees stalled GPU emitters")
	root.queue_free();Settings.end_isolated()
	for row in [["stability_20261018",true,true],["ballistics",false,false],["funnel_guidance",true,true],["sazabi",true,true],["nu_gundam",true,true]]:
		await t.run_suite("res://tests/suite_"+row[0]+".gd",row[0],self,row[1],row[2])
	for i in 4:await get_tree().process_frame
	if "--orphans" in OS.get_cmdline_user_args():Node.print_orphan_nodes()
	t.report();get_tree().quit(1 if t.failed else 0)



