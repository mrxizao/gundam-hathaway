extends Node3D
const Pulse=preload("res://scripts/combat/funnel_beam.gd")
var count:=0
var failed:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label);count+=int(ok);failed+=int(not ok)
func body(profile:SuitProfile,team:int,at:Vector3)->FlightBody:
	var u:=FlightBody.new();u.profile=profile;u.team=team;add_child(u);u.global_position=at;u.set_physics_process(false);u.invuln_until=-1;u.ifield_hp=0
	if is_instance_valid(u.nu_systems):u.nu_systems.set_physics_process(false)
	return u
func _ready()->void:
	Settings.begin_isolated();Game.reset();Game.phase=Game.Phase.FIGHT;FlightBody.use_placeholder=true
	var owner:=body(SuitProfile.nu_gundam(),0,Vector3(0,5000,0));var victim:=body(SuitProfile.xi(),1,Vector3(0,5000,-100))
	var emitter:=Node3D.new();add_child(emitter);emitter.position=owner.position
	var beam=Pulse.pulse(self,owner,emitter.position,Vector3.FORWARD,27,Color.YELLOW,1.15,emitter);beam.set_physics_process(false)
	var hp:=victim.hp
	beam._physics_process(.15)
	check(is_equal_approx(hp-victim.hp,13.5),"Half pulse applies half damage")
	check(is_equal_approx(beam._core.scale.y,1500),"Continuous column reaches full range immediately")
	check(not beam.is_queued_for_deletion(),"Pulse stays alive before 0.3 seconds")
	emitter.position.x=3;beam._physics_process(.2)
	check(is_equal_approx(hp-victim.hp,27),"Large final frame clamps to original 27 total damage")
	check(beam.is_queued_for_deletion() and is_equal_approx(beam._life,.3),"Pulse expires at 0.3 seconds")
	check(beam.origin==emitter.position,"Column follows funnel muzzle")
	var remote=Pulse.pulse(self,owner,owner.position,Vector3.FORWARD,27,Color.YELLOW,1.15,null,true);remote.set_physics_process(false);hp=victim.hp;remote._physics_process(.3)
	check(victim.hp==hp,"Remote replicas never apply damage")
	var blocked:=StaticBody3D.new();blocked.collision_layer=1;var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(100,100,2);shape.shape=box;blocked.add_child(shape);add_child(blocked);blocked.position=Vector3(0,5000,-50)
	await get_tree().physics_frame
	var wall=Pulse.pulse(self,owner,owner.position,Vector3.FORWARD,27,Color.YELLOW,1.15);wall.set_physics_process(false);hp=victim.hp;wall._physics_process(.1)
	check(victim.hp==hp and wall._core.scale.y<51,"World geometry truncates visual and damage")
	blocked.free();wall.queue_free()
	var zorin=Pulse.pulse(self,owner,owner.position,Vector3.FORWARD,48.6,Color.YELLOW,1.15);zorin.set_physics_process(false);hp=victim.hp;zorin._physics_process(.3)
	check(is_equal_approx(hp-victim.hp,48.6),"Zorin retains 1.8 times damage")
	var main=load("res://scripts/main.gd").new();main.projectiles=self
	var proxy:=NetProxyBody.new();proxy.profile=SuitProfile.sazabi();proxy.team=1;add_child(proxy);proxy.set_physics_process(false);main.remote_proxy=proxy
	for event in ["nu_fin","zorin_fin","sazabi_fin"]:
		main._on_net_fire(event,owner.position,Vector3.FORWARD)
		var child=get_children().filter(func(n):return n is BeamCannon).back()
		check(child is BeamCannon and child.visual_only and child.duration==.3,"Network continuous beam "+event)
		child.queue_free()
	main.free();Settings.end_isolated();print("PULSE_DONE ",count," PASS / ",failed," FAIL");get_tree().quit(failed)

