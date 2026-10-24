extends Node
func _ready() -> void:
	var t := T.new()
	await preload("res://tests/suite_odysseus_pedal.gd").run(t,self)
	t.report()
	get_tree().quit(1 if t.failed>0 else 0)
