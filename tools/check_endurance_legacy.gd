extends Node
func _ready()->void:
	await get_tree().process_frame
	var t:=T.new()
	await preload("res://tests/suite_combat.gd")._beam_radius_decouple(t,self)
	for i in 5:await get_tree().process_frame
	t.report();get_tree().quit(1 if t.failed else 0)
