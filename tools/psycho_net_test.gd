extends Node3D
var p: PlayerController
var proxy: NetProxyBody
var failures:=0
func check(ok:bool,label:String)->void:
	print("NET_PASS " if ok else "NET_FAIL ",label)
	if not ok: failures+=1
func wait_sec()->void:
	await get_tree().create_timer(.4).timeout
func _ready()->void:
	Settings.begin_isolated();Game.reset();Game.phase=Game.Phase.FIGHT;FlightBody.use_placeholder=true
	var host:=OS.get_cmdline_user_args()[0]=="host"
	p=PlayerController.new();p.profile=SuitProfile.nu_gundam() if host else SuitProfile.sazabi();p.is_player=true;p.team=0 if host else 1;add_child(p);p.set_physics_process(false);p.set_process(false);p.position.y=5000;p.invuln_until=-1;Game.player=p
	if is_instance_valid(p.nu_systems):p.nu_systems.set_physics_process(false)
	proxy=NetProxyBody.new();proxy.profile=SuitProfile.sazabi() if host else SuitProfile.nu_gundam();proxy.team=1-p.team;add_child(proxy);proxy.set_physics_process(false);proxy.position=Vector3(0,5000,-500)
	if is_instance_valid(proxy.nu_systems):proxy.nu_systems.set_physics_process(false)
	Net.remote_damage.connect(func(amount,kind):p.take_damage(amount,proxy,kind))
	Net.remote_state.connect(func(pkt):proxy.apply_state(Net.unpack_state(pkt)))
	var err:=Net.host_game(28871) if host else Net.join_game("127.0.0.1",28871)
	check(err==OK,"ENet startup")
	for i in 300:
		if Net.peer_ready:break
		await get_tree().create_timer(.02).timeout
	check(Net.peer_ready,"Peers connected")
	Net.start_committed=true
	if not host:return
	await wait_sec()
	var before:float=p.hp
	rpc("stage","kick")
	await wait_sec()
	check(p.combat_buffs.kick_left==20 and is_equal_approx(p.hp,before-1),"Two remote melee hits apply status without bonus damage")
	check(proxy.combat_buffs.kick_cd==10,"Receiver owns trigger cooldown")
	p.combat_buffs.gauge=0
	proxy.take_damage(10,p,Damage.Type.BEAM)
	await wait_sec()
	check(is_equal_approx(p.combat_buffs.gauge,5),"Accepted damage returns exactly five percent resonance through RPC")
	p.combat_buffs.gain(p,100)
	await wait_sec()
	proxy.take_damage(10,p,Damage.Type.BEAM)
	await wait_sec()
	rpc("stage","check_damage")
	before=p.hp
	rpc("stage","immune")
	await wait_sec()
	check(p.hp==before,"Remote damage rejected by resonance protection")
	rpc("stage","finish")
	await wait_sec()
	print("NET_DONE HOST failures=",failures)
	Net.close();Settings.end_isolated();get_tree().quit(failures)
@rpc("any_peer","call_remote","reliable")
func stage(action:String)->void:
	if action=="kick":
		p.ifield_hp=0
		proxy.take_damage(1,p,Damage.Type.SABER);proxy.take_damage(1,p,Damage.Type.SABER)
	elif action=="check_damage":
		check(is_equal_approx(p.max_hp-p.hp,22.5),"Remote boosted damage applied exactly once")
		check(p.combat_buffs.kick_cd==10,"Trigger confirmation reaches Sazabi")
		check(proxy.combat_buffs.active() and proxy.combat_buffs.immune(),"Resonance snapshot reaches opponent")
	elif action=="immune":proxy.take_damage(100,p,Damage.Type.BEAM)
	elif action=="finish":
		print("NET_DONE CLIENT failures=",failures)
		Settings.end_isolated();get_tree().quit(failures)
