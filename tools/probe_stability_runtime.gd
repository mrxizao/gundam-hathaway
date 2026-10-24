extends Node3D
var elapsed:=0.0
var burst:=0.0
var samples:Array[float]=[]
var p:PlayerController
var peak_effects:=0
var peak_objects:=0
var start_memory:=0
var end_memory:=0
var scene:Node3D
var rng:=RandomNumberGenerator.new()
var ready_probe:=false
var previous_us:=0
func _ready()->void:
	Settings.begin_isolated();Settings.set_quality_preset(0);FlightBody.use_placeholder=false
	var warmed:=await preload("res://scripts/flight/loadout_warmup.gd").warm(self,preload("res://scripts/flight/loadout_warmup.gd").paths([SuitProfile.Id.SAZABI]))
	p=PlayerController.new();p.profile=SuitProfile.sazabi();p.is_player=true;add_child(p);p.set_physics_process(false);p.set_process(false)
	p.fm.speed=p.profile.player_top_speed()*.8;p.fm.boosting=true;p.fm.throttle=1
	warmed.clear();scene=Node3D.new();add_child(scene)
	var cam:=Camera3D.new();add_child(cam);cam.position=Vector3(26,12,-50);cam.look_at(Vector3.ZERO);cam.fov=45;cam.make_current()
	var light:=DirectionalLight3D.new();add_child(light);light.rotation_degrees=Vector3(-30,-35,0);light.light_energy=1.7
	var environment:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.05,.07,.11);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_energy=.7;environment.environment=env;add_child(environment)
	rng.seed=18102026;previous_us=Time.get_ticks_usec();ready_probe=true
func _process(delta:float)->void:
	if not ready_probe:return
	var now:=Time.get_ticks_usec();var wall_ms:=float(now-previous_us)/1000.0;previous_us=now
	elapsed+=delta;burst+=delta;p._tick_effects(delta)
	if burst>=.25:
		burst=0
		for i in 60:FX.hit_spark(scene,Vector3(rng.randf_range(-12,12),rng.randf_range(-9,12),rng.randf_range(-8,8)))
	if elapsed>=5 and elapsed<25:
		samples.append(wall_ms)
		if start_memory==0:start_memory=int(Performance.get_monitor(Performance.MEMORY_STATIC))
		peak_objects=maxi(peak_objects,int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		var budget=get_tree().root.get_node_or_null("TransientFXBudget")
		if budget!=null:peak_effects=maxi(peak_effects,budget.entries.size())
	if elapsed>=25:
		ready_probe=false;end_memory=int(Performance.get_monitor(Performance.MEMORY_STATIC))
		samples.sort();var total:=0.0
		for value in samples:total+=value
		print("GPU_STRESS frames=",samples.size()," average_ms=",total/maxi(samples.size(),1)," p95_ms=",samples[int(samples.size()*.95)]," peak_transient_fx=",peak_effects," peak_nodes=",peak_objects," memory_start=",start_memory," memory_end=",end_memory)
		p.free();scene.free()
		for i in 4:await get_tree().process_frame
		Settings.end_isolated();get_tree().quit()
