extends Node3D
const SazabiDrone=preload("res://scripts/combat/sazabi_funnel.gd")
var actors:Array[BanditAI]=[]
var shots:Node3D
var camera:Camera3D
var running:=false
var start_us:=0
var last_us:=0
var pulse:=0.0
var report_clock:=0.0
var frames:Array[float]=[]
var peak_missiles:=0
var peak_funnels:=0
var launched:=0
var stop_fire:=false
func _ready()->void:
	seed(18102026)
	Settings.begin_isolated();Settings.set_quality_preset(0);FlightBody.use_placeholder=false
	if "--pacific" in OS.get_cmdline_user_args():
		var world:=WorldBuilder.new();world.defer_initial_map=true;add_child(world)
		Game.active_map=MapDef.pacific();await world.apply_map_staged(Game.active_map)
	Game.match_mode=Game.MatchMode.SQUAD
	Game.set_phase(Game.Phase.FIGHT)
	shots=Node3D.new();add_child(shots)
	var ids=[SuitProfile.Id.XI,SuitProfile.Id.PENELOPE,SuitProfile.Id.SAZABI,SuitProfile.Id.NU_GUNDAM]
	var warm=await preload("res://scripts/flight/loadout_warmup.gd").warm(self,preload("res://scripts/flight/loadout_warmup.gd").paths(ids))
	for team in 2:
		for i in 4:
			var a:=BanditAI.new();a.profile=SuitProfile.by_id(ids[i]);a.team=team;a.projectile_container=shots;a.difficulty=Difficulty.make(Difficulty.Level.HARD)
			add_child(a);a.position=Vector3(i*550,4000,team*7000);a.look_at(Vector3(i*550,4000,(1-team)*7000));a.hp=1000000;a.max_hp=1000000
			actors.append(a);a._hard_rng.seed=18102026+team*4+i
	warm.clear()
	for i in 8:actors[i].target_override=actors[(i+4)%8]
	camera=Camera3D.new();add_child(camera);camera.far=60000;camera.fov=70;camera.make_current()
	if not "--pacific" in OS.get_cmdline_user_args():
		var light:=DirectionalLight3D.new();add_child(light);light.rotation_degrees=Vector3(-40,-30,0)
		var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.09,.16,.24);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=.8;add_child(env)
	print("COMBAT_PID ",OS.get_process_id())
	start_us=Time.get_ticks_usec();last_us=start_us;running=true
func _process(delta:float)->void:
	if not running:return
	var now:=Time.get_ticks_usec();var seconds:=float(now-start_us)/1000000.0
	if seconds>10 and seconds<70:frames.append(float(now-last_us)/1000.0)
	last_us=now
	camera.global_position=actors[0].global_position+Vector3(150,100,350);camera.look_at(actors[0].global_position+actors[0].forward()*1000)
	pulse+=delta;report_clock+=delta
	if seconds<70 and pulse>=.6:
		pulse=0
		for i in 8:
			var a=actors[i];var target=actors[(i+4)%8]
			if a.profile.has_missiles:
				a.funnel_cooldown=0;a.funnel_reload_left=0;a.funnel_count=300
				if a.fire_funnel(target):launched+=3
			if a.sazabi_systems!=null:
				a.sazabi_systems.target=target;a.sazabi_systems.launch()
			if a.nu_systems!=null:a.nu_systems.deploy(target)
	if seconds>=70 and not stop_fire:
		stop_fire=true
		for a in actors:
			a.scripted=true;a.set_physics_process(false)
			if a.sazabi_systems!=null:a.sazabi_systems._dock()
			if a.nu_systems!=null:a.nu_systems._begin_cooldown(20,true)
	if report_clock>=1:
		report_clock=0
		var missiles:=0;var funnels:=0;var smokes:=0
		for n in shots.get_children():
			if n is Missile:missiles+=1
			if n.has_node("SmokeEmbers"):smokes+=1
			if n is SazabiDrone:funnels+=1
		peak_missiles=maxi(peak_missiles,missiles);peak_funnels=maxi(peak_funnels,funnels)
		print("SAMPLE ",int(seconds)," missiles=",missiles," sazabi_funnels=",funnels," smokes=",smokes," nodes=",int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))," static_bytes=",int(Performance.get_monitor(Performance.MEMORY_STATIC))," physics_ms=",Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
	if seconds>=90:
		running=false;frames.sort();var sum:=0.0;var slow:=0;var worst:=0.0
		for v in frames:sum+=v;worst=maxf(worst,v);slow+=int(v>33.33)
		print("RESULT ",JSON.stringify({"frames":frames.size(),"average_ms":sum/maxi(1,frames.size()),"p95_ms":frames[int(frames.size()*.95)],"p99_ms":frames[int(frames.size()*.99)],"max_ms":worst,"over_33ms":slow,"peak_missiles":peak_missiles,"peak_sazabi_funnels":peak_funnels,"forced_launches":launched}))
		for a in actors:a.queue_free()
		shots.queue_free()
		for i in 5:await get_tree().process_frame
		Settings.end_isolated();get_tree().quit()




