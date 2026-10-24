extends Node
func _ready()->void:
	await get_tree().process_frame
	var t:=T.new()
	for suite in ["nu_sazabi_motion","nu_model","sazabi_model","sazabi_belly","sazabi","nu_gundam"]:
		await t.run_suite("res://tests/suite_"+suite+".gd",suite,self,true,true)
	for i in 4:await get_tree().process_frame
	t.report();get_tree().quit(1 if t.failed>0 else 0)
