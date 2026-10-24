extends Node
func _ready()->void:
	await get_tree().process_frame
	var t:=T.new()
	for row in [["stability_20261018",true,true],["weapon_mounted_origins",true,true],["loading",true,true],["day7_performance",true,true],["cinematic_performance",true,true]]:
		if "--focus" in OS.get_cmdline_user_args() and row[0]!="stability_20261018":continue
		if "--loading-only" in OS.get_cmdline_user_args() and row[0]!="loading":continue
		await t.run_suite("res://tests/suite_"+row[0]+".gd",row[0],self,row[1],row[2])
	for i in 4:await get_tree().process_frame
	if "--orphans" in OS.get_cmdline_user_args():Node.print_orphan_nodes()
	t.report();get_tree().quit(1 if t.failed>0 else 0)
