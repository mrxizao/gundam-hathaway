extends Node
class LaunchWorld extends WorldBuilder:
	var builds:=0
	func _ready()->void:pass
	func apply_map_staged(_map:MapDef)->void:
		builds+=1;await get_tree().process_frame
class LaunchOwner extends "res://scripts/main.gd":
	var handoffs:=0
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _finish_launch()->void:handoffs+=1;phase=Phase.FIGHT
class Movie extends Control:
	var _armed:=true
	var _done:=false
	var _skipping:=false
	func skip()->void:_done=true
class Title extends Control:
	var active:=true
	func skip()->void:active=false
class Stub extends Node:
	var ended:=0
	func skip_to_end()->void:ended+=1
	func finish()->void:ended+=1
class Owner extends Node:
	enum Phase { MENU, CAMPAIGN, BRIEF, LAUNCH, FIGHT, RESULT, POD_STRIKE, DAVAO_INTRO, SORTIE }
	var phase:=Phase.MENU
	var _paused:=false
	var mission_title:Control
	var _strike_director:Stub
	var _davao_director:Stub
	var _sortie_director:Stub
	var calls:=0
	func _skip_story_launch()->void:calls+=1
	func _finish_pod_strike()->void:calls+=1
	func _finish_davao_intro()->void:calls+=1
func _ready()->void:
	var t:=T.new();t.suite("Story skip / shared input and all cinematic routes")
	var script:=preload("res://scripts/ui/story_skip.gd")
	var key:=InputEventKey.new();key.pressed=true
	for code in [KEY_SPACE,KEY_ESCAPE]:key.keycode=code;t.ok(script.skip_event(key),"keyboard skip")
	key.echo=true;t.not_ok(script.skip_event(key),"ignore held key repeats")
	var pad:=InputEventJoypadButton.new();pad.pressed=true
	for code in [JOY_BUTTON_A,JOY_BUTTON_B]:pad.button_index=code;t.ok(script.skip_event(pad),"controller skip")
	t.not_ok(script.skip_event(InputEventJoypadMotion.new()),"stick drift cannot skip")
	var owner:=Owner.new();add_child(owner)
	owner._strike_director=Stub.new();owner.add_child(owner._strike_director)
	owner._davao_director=Stub.new();owner.add_child(owner._davao_director)
	owner._sortie_director=Stub.new();owner.add_child(owner._sortie_director)
	var skip=script.new();skip.setup(owner);add_child(skip)
	for row in [[Owner.Phase.LAUNCH,"launch"],[Owner.Phase.POD_STRIKE,"pod"],[Owner.Phase.DAVAO_INTRO,"davao"],[Owner.Phase.SORTIE,"sortie"]]:
		owner.phase=row[0];skip.blocked_until=0
		t.eq(skip.kind(),row[1],"cinematic route detected")
		skip.skip();t.ok(skip.blocks_input(),"skip key cannot trigger battle pause")
		var before:int=owner.calls;skip.skip();t.eq(owner.calls,before,"repeated skip is ignored")
	t.eq(owner.calls,3,"launch, pod and Davao finish through native handoff")
	t.eq(owner._strike_director.ended,1,"pod reaches final pose")
	t.eq(owner._davao_director.ended,1,"Davao reaches final pose")
	t.eq(owner._sortie_director.ended,1,"sortie uses original finish")
	owner.phase=Owner.Phase.FIGHT;t.eq(skip.kind(),"","combat radio remains playable")
	owner.phase=Owner.Phase.CAMPAIGN;skip.blocked_until=0
	var movie:=Movie.new();add_child(movie);movie.add_to_group("story_skip_movies")
	t.eq(skip.kind(),"movie","campaign video shares the skip button");skip.skip();t.ok(movie._done,"video skips through original completion")
	movie.free();skip.blocked_until=0
	owner.mission_title=Title.new();owner.add_child(owner.mission_title)
	t.eq(skip.kind(),"title","mission title shares the skip button");skip.skip();t.not_ok(owner.mission_title.active,"mission title exits normally")
	skip.free();owner.free()
	var launch:=LaunchOwner.new();add_child(launch);launch.phase=launch.Phase.LAUNCH
	var world:=LaunchWorld.new();launch.add_child(world);launch.world=world;launch.rocket=RocketBody.new()
	launch._skip_story_launch();launch._skip_story_launch()
	t.ok(launch._story_launch_skipping,"rocket skip waits for destination world")
	launch._tick_launch(.016);t.eq(launch.handoffs,0,"cannot enter battle before map construction")
	for i in 5:await get_tree().process_frame
	t.eq(world.builds,1,"skip builds orbit map exactly once")
	t.ok(launch._orbit_swap_done,"orbit map ready before handoff")
	launch._tick_launch(.016);t.eq(launch.handoffs,1,"rocket reaches native finish once")
	t.not_ok(launch._story_launch_skipping,"pending skip state clears")
	launch.rocket.free();launch.free()
	if "--skip-only" in OS.get_cmdline_user_args():
		t.report();get_tree().quit(1 if t.failed>0 else 0);return
	for row in [["davao_intro",false,false],["pod_strike",false,false],["rocket_launch",true,true],["m09_launch",false,false]]:
		await t.run_suite("res://tests/suite_"+row[0]+".gd",row[0],self,row[1],row[2])
	t.report();get_tree().quit(1 if t.failed>0 else 0)
