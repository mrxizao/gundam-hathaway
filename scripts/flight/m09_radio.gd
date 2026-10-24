extends Node
## M09 event observer. Combat state is read-only; dialogue never changes damage or AI.
const Dialogue:=preload("res://scripts/data/m09_dialogue.gd")
const Comms:=preload("res://scripts/flight/comms_director.gd")
var controller:Node3D
var pending:Array[int]=[]
var fired:Dictionary={}
var sent:Dictionary={}
var context:Dictionary={}
var elapsed:=0.0
var scan_left:=0.0
var was_close:=false
var won:=false
var result_layer:CanvasLayer
var result_panel:Control
func setup(owner_controller:Node3D)->void:
	controller=owner_controller
func _ready()->void:
	process_mode=Node.PROCESS_MODE_PAUSABLE
	result_layer=CanvasLayer.new();result_layer.layer=64;add_child(result_layer)
	result_panel=preload("res://scripts/ui/m09_radio_panel.gd").new();result_layer.add_child(result_panel);result_panel.hide()
	var player:PlayerController=controller.main.player
	player.damaged.connect(_player_hit);player.beam_fired.connect(_beam)
func notify(event:String,urgent:=false)->void:
	if fired.has(event) or not Dialogue.GROUPS.has(event):return
	fired[event]=true
	var ids:Array=Dialogue.GROUPS[event]
	if urgent:
		for i in range(ids.size()-1,-1,-1):
			var number:int=ids[i]
			if not sent.has(number) and not pending.has(number):pending.push_front(number)
	else:
		for number:int in ids:
			if not sent.has(number) and not pending.has(number):pending.append(number)
func observe(state:Dictionary)->void:
	context=state
	if state.get("elapsed",0.0)>=.5:notify("opening")
	if state.get("city_distance",INF)<22000 and state.get("messer_alive",0)>0:notify("city",true)
	if state.get("messer_distance",INF)<11000 and fired.has("city"):notify("engage")
	if state.get("messer_distance",INF)<2800:
		was_close=true;notify("counterattack")
	if state.get("messer_down",0)>=1:
		notify("first_down",true)
		if state.get("messer_alive",0)>0:notify("next_targets")
		if state.get("messer_alive",0)==2:notify("two_left")
		if state.get("dashing",false):notify("overspeed")
	if state.get("xi_distance",INF)<13000 and state.get("messer_down",0)>=2:notify("xi_close",true)
	if state.get("hp",1.0)<.65 and state.get("missiles",1)<=0:notify("limited")
	if was_close and state.get("messer_alive",0)>0 and state.get("messer_distance",0)>9000:notify("escape")
	if state.get("airport_explosion",false):notify("airport_hit",true)
func valid_line(number:int)->bool:
	if won:return number>=44
	if number==39:return context.get("messer_alive",0)==2
	if number in [25,26,27,29,33,34,35]:return context.get("messer_alive",0)>0
	return true
func drain(comms)->void:
	if comms==null or comms.queued()>0 or not comms.live().is_empty():return
	while not pending.is_empty():
		var number:int=pending.pop_front()
		if sent.has(number) or not valid_line(number):continue
		comms.enqueue_line(Dialogue.packet(number));sent[number]=true
		break
func begin_result(comms)->void:
	if won:return
	won=true;pending.clear();comms.clear()
	# Preserve unspoken withdrawal lines before the closing cockpit reflections.
	for number:int in Dialogue.GROUPS.xi_retreat:
		if not sent.has(number):pending.append(number)
	notify("win")
func _process(delta:float)->void:
	if not is_instance_valid(controller) or controller.cleaned:return
	var main=controller.main
	if not is_instance_valid(main) or not is_instance_valid(main.player):return
	if Game.phase==Game.Phase.WIN:
		begin_result(main.hud.comms);drain(main.hud.comms)
		var rows:Array[Dictionary]=[]
		for entry:Dictionary in main.hud.comms.live():
			var line:Dictionary=entry.line
			if not str(line.id).begins_with("m09_script_"):continue
			var row:Dictionary=line.duplicate();row["alpha"]=Comms.alpha_of(entry.t,line);rows.append(row)
		result_panel.rows=rows;result_panel.visible=not rows.is_empty();result_panel.queue_redraw()
		return
	result_panel.hide()
	if Game.phase!=Game.Phase.FIGHT or main.phase!=main.Phase.FIGHT:return
	elapsed+=delta;scan_left-=delta
	if scan_left<=0:
		scan_left=.5;observe(_context())
	drain(main.hud.comms)
func _context()->Dictionary:
	var player:PlayerController=controller.main.player
	var nearest:=INF;var alive:=0
	for foe:FlightBody in controller.foes:
		if not is_instance_valid(foe) or not foe.alive or foe.profile.id==SuitProfile.Id.XI:continue
		alive+=1;nearest=minf(nearest,player.global_position.distance_to(foe.global_position))
	var xi_distance:=INF
	if is_instance_valid(controller.target) and controller.target.alive:xi_distance=player.global_position.distance_to(controller.target.global_position)
	var airport_explosion:=false
	for effect:Node3D in controller.main.projectiles.find_children("Explosion","Node3D",true,false):
		var offset:Vector3=effect.global_position-Vector3(-11000,0,4000);offset.y=0
		if offset.length()<4500:airport_explosion=true;break
	return {"elapsed":elapsed,"city_distance":player.global_position.distance_to(controller.festival),"messer_distance":nearest,
		"messer_alive":alive,"messer_down":controller.messer_down,"xi_distance":xi_distance,"hp":player.hp_ratio(),
		"missiles":player.funnel_count,"dashing":player.assist_dashing(),"airport_explosion":airport_explosion}
func _player_hit(_amount:float,source:Node3D,type:int)->void:
	if Game.phase!=Game.Phase.FIGHT:return
	notify("hit",true)
	if type==Damage.Type.SABER and is_instance_valid(source):
		var player:PlayerController=controller.main.player
		var relative:Vector3=player.global_basis.inverse()*(source.global_position-player.global_position)
		if relative.x>0 and relative.y<5:notify("right_hit",true)
func _beam()->void:
	if Game.phase==Game.Phase.FIGHT and context.get("messer_distance",INF)<4500 and context.get("elapsed",0)>20:notify("exchange")
