extends Node
var main
var actors:Array[FlightBody]=[]
var refs:Array[WeakRef]=[]
var running:=false
var clock:=0.0
var round_start:=0
var previous:=0
var burst:=0.0
var interval:=0.0
var frames:Array[float]=[]
var part:Array[float]=[]
var round_index:=0
var combat_seconds:=45.0
var rounds:=6
var resets:=0
var peak_missiles:=0
var safety_repositions:=0
func _ready()->void:
	Settings.begin_isolated();Settings.set_quality_preset(0);FlightBody.use_placeholder=false
	if "--long" in OS.get_cmdline_user_args():combat_seconds=300;rounds=1
	if "--profile" in OS.get_cmdline_user_args():
		combat_seconds=35;rounds=1;preload("res://tools/flight_stage_profiler.gd").enabled=true
	main=load("res://scenes/main.tscn").instantiate();main.staged_startup=true;add_child(main)
	await main.startup_finished
	Node.print_orphan_nodes()
	main.menu.close_menu()
	main._resolve_match(SuitProfile.Id.XI,Difficulty.Level.HARD,MapDef.Id.PACIFIC,Game.MatchMode.VERSUS,SuitProfile.Id.XI)
	var warm=await preload("res://scripts/flight/loadout_warmup.gd").warm(self,preload("res://scripts/flight/loadout_warmup.gd").paths([SuitProfile.Id.XI,SuitProfile.Id.PENELOPE,SuitProfile.Id.SAZABI,SuitProfile.Id.NU_GUNDAM]))
	print("ENDURANCE_PID ",OS.get_process_id()," rounds=",rounds," combat_seconds=",combat_seconds)
	for cycle in rounds:
		if "--extended" in OS.get_cmdline_user_args():combat_seconds=300.0 if cycle==0 else 45.0
		round_index=cycle+1
		print("ROUND_LOADING ",round_index," unix=",Time.get_unix_time_from_system())
		main._resolve_match(SuitProfile.Id.XI,Difficulty.Level.HARD,MapDef.Id.PACIFIC,Game.MatchMode.VERSUS,SuitProfile.Id.XI)
		main.spawn_round();main._start_fight();main.player.controls_enabled=false;main.player.set_physics_process(false)
		actors=[main.player]
		var ids=[SuitProfile.Id.PENELOPE,SuitProfile.Id.SAZABI,SuitProfile.Id.NU_GUNDAM]
		for id in ids:
			var a=main._attach_ai(id,Vector3(0,5000,0),Vector3(0,5000,7000),"StressAlly",-1,false);a.team=0;actors.append(a)
		actors.append(main.enemy)
		for id in ids:actors.append(main._attach_ai(id,Vector3(0,5000,7000),Vector3(0,5000,0),"StressFoe",-1,false))
		seed(18102026)
		for i in 8:
			var a=actors[i];a.hp=1000000;a.max_hp=1000000
			refs.append(weakref(a));refs.append(weakref(a.model_root))
			if a is BanditAI:a.target_override=actors[(i+4)%8];a._hard_rng.seed=18102026+i
		place_actors()
		main.player_lock.target=actors[4]
		warm.clear();clock=0;burst=0;interval=0;frames.clear();part.clear();peak_missiles=0;resets=0;safety_repositions=0
		if "--foreground" in OS.get_cmdline_user_args():get_window().grab_focus()
		round_start=Time.get_ticks_usec();previous=round_start;running=true
		print("ROUND_BEGIN ",round_index," unix=",Time.get_unix_time_from_system())
		while float(Time.get_ticks_usec()-round_start)/1000000.0<combat_seconds:await get_tree().process_frame
		running=false
		print("ROUND_RESULT ",JSON.stringify(stats(frames).merged({"round":round_index,"peak_missiles":peak_missiles,"alive":living(),"projectiles":main.projectiles.get_child_count(),"safety_repositions":safety_repositions})))
		Game.set_phase(Game.Phase.INTRO)
		for n in main.projectiles.get_children():refs.append(weakref(n))
		main._clear_match();actors.clear();Game.reset()
		for i in 5:await get_tree().process_frame
		await get_tree().create_timer(2.0).timeout
		var live:=0
		for ref in refs:
			if ref.get_ref()!=null:live+=1
		print("ROUND_CLEAR ",JSON.stringify({"round":round_index,"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"orphans":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),"static_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"tracked_alive":live,"game_units":Game.units.size(),"locks":Game._locks.size() if "_locks" in Game else -1,"units_children":main.units_root.get_child_count(),"projectile_children":main.projectiles.get_child_count()}))
		refs.clear()
		await get_tree().create_timer(3.0).timeout
		print("ROUND_SETTLED ",JSON.stringify({"round":round_index,"unix":Time.get_unix_time_from_system(),"static_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"orphans":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),"audio_cache":Audio._streams.size(),"audio_keys":Audio._streams.keys(),"bgm":Audio.current_bgm_track()}))
		Node.print_orphan_nodes()
		if "--reload-map" in OS.get_cmdline_user_args() and cycle in [1,3]:
			var old_ocean:WeakRef=weakref(main.world.ocean)
			print("MAP_RETURN_BEGIN ",round_index," unix=",Time.get_unix_time_from_system())
			await main._return_to_menu_loading()
			main.menu.close_menu()
			for i in 5:await get_tree().process_frame
			print("MAP_RETURN_END ",JSON.stringify({"after_round":round_index,"old_ocean_alive":old_ocean.get_ref()!=null,"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"orphans":int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),"static_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC))}))
	main.queue_free()
	for i in 8:await get_tree().process_frame
	Node.print_orphan_nodes()
	print("ENDURANCE_DONE")
	if "--profile" in OS.get_cmdline_user_args():print("FLIGHT_STAGES ",JSON.stringify(preload("res://tools/flight_stage_profiler.gd").values))
	Settings.end_isolated();get_tree().quit()
func living()->int:
	var count:=0
	for a in actors:
		if is_instance_valid(a) and a.alive:count+=1
	return count
func place_actors()->void:
	for i in actors.size():
		var a=actors[i];var side:=i/4;var p:=Vector3((i%4)*550,5000,side*7000)
		main._place(a,p,Vector3((i%4)*550,5000,(1-side)*7000))
func stats(values:Array[float])->Dictionary:
	if values.is_empty():return {}
	var sorted:=values.duplicate();sorted.sort();var sum:=0.0;var slow:=0;var huge:=0
	for v in sorted:sum+=v;slow+=int(v>33.33);huge+=int(v>100)
	return {"frames":sorted.size(),"average_ms":sum/sorted.size(),"p95_ms":sorted[int(sorted.size()*.95)],"p99_ms":sorted[int(sorted.size()*.99)],"max_ms":sorted[-1],"over33":slow,"over100":huge}
func _process(delta:float)->void:
	if not running:return
	var now:=Time.get_ticks_usec();clock=float(now-round_start)/1000000.0
	for i in actors.size():
		var actor=actors[i]
		if not is_instance_valid(actor) or not actor.alive:
			running=false;push_error("Endurance fixture lost an actor; reduced-load results are invalid");get_tree().quit(2);return
		# Fixture-only safety: keep all eight actors away from terrain and the 10 km transport pod.
		if actor.global_position.y<3500 or actor.global_position.y>8000:
			main._place(actor,Vector3((i%4)*550,5000,(i/4)*7000),actors[(i+4)%8].global_position);safety_repositions+=1
	var ms:=float(now-previous)/1000;previous=now
	if clock>5:frames.append(ms);part.append(ms)
	burst+=delta;interval+=delta
	if clock>float(resets+1)*60:
		place_actors();resets+=1
	if burst>=.6:
		burst=0
		for i in actors.size():
			var a=actors[i];var target=actors[(i+4)%8]
			if not is_instance_valid(a) or not a.alive:continue
			if a.profile.has_missiles:
				a.funnel_cooldown=0;a.funnel_reload_left=0;a.funnel_count=300;a.fire_funnel(target)
			if a.sazabi_systems!=null:a.sazabi_systems.target=target;a.sazabi_systems.launch()
			if a.nu_systems!=null:a.nu_systems.deploy(target)
		main.player.rifle_cooldown=0;main.player.rifle_count=100;main.player.fire_beam(true,actors[4],false)
	if interval>=5:
		interval=0;var missiles:=0
		for n in main.projectiles.get_children():
			if n is Missile:missiles+=1
		peak_missiles=maxi(peak_missiles,missiles)
		print("WINDOW ",JSON.stringify(stats(part).merged({"round":round_index,"second":int(clock),"missiles":missiles,"alive":living(),"nodes":int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),"static_bytes":int(Performance.get_monitor(Performance.MEMORY_STATIC)),"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000})))
		print("RENDER_SAMPLE ",JSON.stringify({"round":round_index,"second":int(clock),"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()),"focused":DisplayServer.window_is_focused(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"render_scale":get_viewport().scaling_3d_scale,"rifle_pending":Game.rifle_stats.pending.size(),"rifle_groups":Game.rifle_stats.groups.size(),"rifle_history":Game.rifle_stats.history.size()}))
		part.clear()

