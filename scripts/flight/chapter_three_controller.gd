extends Node3D
const RULES := preload("res://scripts/data/chapter_three_rules.gd")
const COMMS := preload("res://scripts/data/comms.gd")
var main: Node3D
var mission
var foes: Array[FlightBody] = []
var allies: Array[FlightBody] = []
var target: FlightBody
var festival := RULES.FESTIVAL
var target_point := RULES.S18
var destroyed_foes := {}
var messer_down := 0
var radio_index := 0
var radio_clock := 0.0
var elapsed := 0.0
var retreat := false
var radio_sent := {}
var cleaned := false
var layer: CanvasLayer
var overlay: Control
var precision_radio:Node
func setup(owner_main: Node3D, data) -> void:
	main=owner_main; mission=data
func deploy() -> void:
	main.hud.reset_sortie_messages()
	var marker: Node = main.world.find_child("FestivalCentre",true,false)
	if is_instance_valid(marker): festival=marker.global_position
	Game.challenge_total=mission.total_enemies(); Game.challenge_killed=0
	Game.challenge_wave=0; Game.challenge_wave_remaining=Game.challenge_total
	main.wave_units.clear()
	var start := festival+Vector3(-24000,3500,0)
	if mission.chapter_three_mode=="return": start=festival+Vector3(0,3500,24000)
	if mission.chapter_three_mode=="defend": start=festival+Vector3(0,4000,9000)
	if mission.chapter_three_mode=="duel": start=RULES.DUEL_START
	if mission.chapter_three_mode=="lure": start=RULES.LURE_START
	var look := festival+Vector3.UP*3500
	if mission.chapter_three_mode=="lure": look=target_point
	if mission.chapter_three_mode=="duel": look=start+Vector3(7000,500,0)
	main._place(main.player,start,look)
	for i in mission.enemy_roster.size():
		var sid: int=mission.enemy_roster[i]
		var position := festival+Vector3(-2500+float(i%2)*2400,3500+float(i)*120,(-1.5+float(i))*1400)
		if mission.chapter_three_mode=="defend": position=festival+Vector3(-9000+float(i)*900,3500,float(i)*1300)
		if mission.chapter_three_mode=="duel": position=start+Vector3(7000,500,0)
		if mission.chapter_three_mode=="lure": position=start-start.direction_to(target_point)*5000.0
		var foe: FlightBody=main._attach_ai(sid,position,start,"ThirdFoe%d"%i)
		foes.append(foe); main.wave_units.append(foe)
		if i==0:
			target=foe; main.enemy=foe
			if mission.chapter_three_mode in ["duel","defend"]: foe.damaged.connect(_target_damaged)
		if mission.chapter_three_mode=="lure":
			foe.target_override=main.player
			foe.set_enemy_speed_mult(1.1)
			foe.set_state(BanditAI.State.ATTACK)
	for i in mission.ally_roster.size():
		var ally: FlightBody=main._attach_ai(mission.ally_roster[i],start+Vector3(700+float(i)*450,-250,-float(i)*600),festival,"ThirdAlly%d"%i)
		ally.team=main.player.team
		allies.append(ally)
	Game.unit_destroyed.connect(_unit_destroyed)
	layer=CanvasLayer.new();layer.layer=63;add_child(layer)
	overlay=preload("res://scripts/ui/chapter_three_hud.gd").new()
	overlay.controller=self;layer.add_child(overlay)
	if mission.id=="M09":
		precision_radio=preload("res://scripts/flight/m09_radio.gd").new()
		precision_radio.setup(self);add_child(precision_radio)
	Game.log_event("第三章 · %s · %s"%[mission.title,mission.enemy_suit_name()])
func _radio(speaker: String,text: String) -> void:
	var key := speaker+":"+text
	if main.hud.comms==null or radio_sent.has(key): return
	radio_sent[key]=true
	main.hud.comms.enqueue_line({"id":"%s_adapted_%s"%[mission.id,text],"speaker":speaker,
		"text":text,"src":"adaptation:下册战斗节选剧本","style":COMMS.STYLE_RADIO,
		"secs":COMMS.hold_secs(text,COMMS.STYLE_RADIO)})
func tick(delta: float) -> void:
	if cleaned or main.phase!=main.Phase.FIGHT or Game.phase!=Game.Phase.FIGHT: return
	elapsed+=delta; radio_clock+=delta
	var lines: Array=RULES.RADIO.get(mission.id,[])
	if radio_index<lines.size() and radio_clock>=float(lines[radio_index][0]) \
			and main.hud.comms.queued()==0 and main.hud.comms.live().is_empty():
		_radio(str(lines[radio_index][1]),str(lines[radio_index][2]));radio_index+=1
	if mission.chapter_three_mode in ["raid","return"]:
		if RULES.in_city(main.player.global_position,festival) and not bool(Game.mission_events.get("sector",false)):
			Game.mission_events["sector"]=true
			_radio("哈萨维","第一攻击完成。后续小队进入。" if mission.id=="M08" else "就是现在！")
	if mission.chapter_three_mode in ["defend","duel"] and is_instance_valid(target) and target.alive and not target.invincible:
		_target_damaged(0.0,null,Damage.Type.RAM)
		if main.phase!=main.Phase.FIGHT: return
	if retreat and is_instance_valid(target):
		var velocity:=Vector3(-750,80,0)
		target.global_position+=velocity*delta
		target.velocity=velocity;target.fm.velocity=velocity
		if target.global_position.distance_to(festival)>30000.0: target.hide()
	if mission.chapter_three_mode=="lure" and is_instance_valid(target) and target.alive:
		if RULES.in_lure_zone(target.global_position,target_point):
			Game.mission_events["lure"]=true
			target.invincible=true;target.set_scripted(true);target.set_physics_process(false)
			main.player.controls_enabled=false
			overlay.barrier_flash=0.32
			Game.log_event("凯奈斯：启动！")
			Game.log_event("通讯员：目标坠落！")
			Game.log_event("凯奈斯：确认驾驶舱。我要活的俘虏。")
			Game.log_event("S18防御壁启动：柯西进入4km范围，诱导作战完成")
	_check_end()
func _target_damaged(_amount: float,_source: Node3D,_type: int) -> void:
	if cleaned or Game.phase!=Game.Phase.FIGHT or not is_instance_valid(target): return
	if retreat or bool(Game.mission_events.get("duel",false)): return
	var threshold: float=RULES.REPEL_HP if mission.chapter_three_mode=="defend" else RULES.DUEL_HP
	if not RULES.below_hp(target.hp_ratio(),threshold): return
	# Synchronous damage callback prevents a single fatal hit bypassing the threshold ending.
	target.hp=maxf(target.hp,target.max_hp*0.01);target.invincible=true
	target.set_scripted(true);target.set_physics_process(false)
	if mission.chapter_three_mode=="defend":
		Game.mission_events["xi_repelled"]=true;retreat=true
		if is_instance_valid(precision_radio):precision_radio.notify("xi_retreat",true)
		else:
			_radio("哈萨维","各机撤退！空母进入收容位置！我来牵制追兵！")
			_radio("雷恩","他没有追我……他在保护撤退的人。")
	else:
		Game.mission_events["duel"]=true
		Game.log_event("凯奈斯：告诉雷恩，把高达带到S18！")
	_check_end()
func _unit_destroyed(unit: Node3D,_killer: Node3D) -> void:
	if cleaned or not foes.has(unit) or destroyed_foes.has(unit.get_instance_id()): return
	destroyed_foes[unit.get_instance_id()]=true
	if unit==target and mission.chapter_three_mode=="defend": Game.mission_events["xi_repelled"]=true
	if unit==target and mission.chapter_three_mode=="duel": Game.mission_events["duel"]=true
	main._notify_enemy_down(unit)
	Game.challenge_killed+=1;Game.challenge_wave_remaining=maxi(Game.challenge_wave_remaining-1,0)
	if unit.profile.id in [SuitProfile.Id.MESSER_M01,SuitProfile.Id.MESSER_CMD,SuitProfile.Id.MESSER_F01]:
		messer_down+=1
		if is_instance_valid(precision_radio):precision_radio.notify("first_down",true)
		if messer_down==1 and not is_instance_valid(precision_radio): _radio("加乌曼","多梅斯奇！……其他人散开！别留在爆炸下面！")
		if messer_down==2 and not is_instance_valid(precision_radio): _radio("雷蒙德","艾美？……艾美拉尔达，回答。")
		Game.mission_events["messer_down"]=messer_down>=3
	if mission.chapter_three_mode=="lure" and unit==target:
		Game.mission_events["lure"]=true
		Game.log_event("柯西已被击毁：诱导作战完成")
	_check_end()
func _check_end() -> void:
	if Game.phase!=Game.Phase.FIGHT: return
	Game.recheck_end()
	if Game.phase==Game.Phase.WIN:
		main.player.controls_enabled=false
		for foe in foes:
			if is_instance_valid(foe): foe.set_scripted(true)
		main._finish_round()
func cleanup() -> void:
	if cleaned: return
	cleaned=true
	if is_instance_valid(precision_radio):precision_radio.queue_free()
	if Game.unit_destroyed.is_connected(_unit_destroyed): Game.unit_destroyed.disconnect(_unit_destroyed)
	if is_instance_valid(target) and target.damaged.is_connected(_target_damaged): target.damaged.disconnect(_target_damaged)
	if is_instance_valid(layer): layer.hide()
