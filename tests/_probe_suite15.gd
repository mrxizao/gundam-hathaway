extends Node
## 单套件跑手（只跑 suite_round15，不跑 18 分钟全量）。
##   godot --headless --path <工程> res://tests/_probe_suite15.tscn
func _ready() -> void:
	var t := T.new()
	await t.run_suite("res://tests/suite_round15.gd", "Round15", self, true, true)
	t.report()
	get_tree().quit()
