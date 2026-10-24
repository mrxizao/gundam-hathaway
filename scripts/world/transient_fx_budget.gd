extends Node
## Bounds visual-only bursts. Projectile simulation and damage never enter here.
var entries:Array[Dictionary]=[]
var clock:=0.0
var cadence:=0.0
var retired:=0
var frame_id:=-1
var frame_hits:=0
var frame_explosions:=0
var rejected:=0
static func track(effect:Node3D,lifetime:float,explosion:=false,channel:StringName=&"TransientFXBudget")->bool:
	if not effect.is_inside_tree():return true
	var root:=effect.get_tree().root
	var manager=root.get_node_or_null(NodePath(channel))
	if manager==null:
		manager=load("res://scripts/world/transient_fx_budget.gd").new();manager.name=channel;root.add_child(manager)
	return manager.admit(effect,lifetime,explosion)
func limit()->int:return 48 if Settings.effects_quality==0 else (96 if Settings.effects_quality==1 else 160)
func admit(effect:Node3D,lifetime:float,explosion:=false)->bool:
	var frame:=Engine.get_process_frames()
	if frame!=frame_id:frame_id=frame;frame_hits=0;frame_explosions=0
	if (explosion and frame_explosions>=maxi(6,limit()/8)) or (not explosion and frame_hits>=limit()/2):
		effect.queue_free();rejected+=1;return false
	if explosion:frame_explosions+=1
	else:frame_hits+=1
	set_process(true)
	prune()
	while entries.size()>=limit():retire(entries.pop_front())
	entries.append({"node":weakref(effect),"until":clock+maxf(lifetime,.1)})
	return true
func retire(item:Dictionary)->void:
	var node=item.node.get_ref()
	if is_instance_valid(node) and not node.is_queued_for_deletion():
		if node is Node3D:node.hide()
		node.queue_free();retired+=1
func prune()->void:
	for i in range(entries.size()-1,-1,-1):
		var item:Dictionary=entries[i];var node=item.node.get_ref()
		if not is_instance_valid(node) or node.is_queued_for_deletion():entries.remove_at(i)
		elif clock>=float(item.until):retire(item);entries.remove_at(i)
func _process(delta:float)->void:
	clock+=delta;cadence+=delta
	if cadence<.1:return
	cadence=0;prune()
	if entries.is_empty():set_process(false)
