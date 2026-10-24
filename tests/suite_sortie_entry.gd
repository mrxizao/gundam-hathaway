extends RefCounted
static func run(t:T,host:Node)->void:
	Settings.begin_isolated();var previous_placeholder:=FlightBody.use_placeholder;FlightBody.use_placeholder=false
	t.suite("Sortie / actual game entry and map lifecycle")
	var main:=preload("res://scripts/main.gd").new();host.add_child(main)
	main._on_start_match(SuitProfile.Id.XI,Difficulty.Level.NORMAL,MapDef.Id.PACIFIC,Game.MatchMode.VERSUS)
	var fleet:Node=main.world._terrain_root.get_node_or_null("PacificFleet")
	t.ok(fleet!=null,"Pacific map creates persistent ships and airbase")
	var previous:Vector3=main.player.global_position
	main._begin_sortie_or_fight(true)
	t.eq(main.phase,main.Phase.SORTIE,"real entry selects sortie phase")
	t.eq(Game.phase,Game.Phase.INTRO,"combat timer remains stopped")
	t.not_ok(main.player.controls_enabled,"weapons and piloting gated during intro")
	main._sortie_director.time=.7;main._sortie_director.finish()
	t.eq(main.phase,main.Phase.FIGHT,"skip reaches actual combat phase")
	t.ok(main.player.controls_enabled,"player controls return")
	t.ok(main.player.global_position.x>0 and main.player.global_position.z>0,"Pacific handoff occurs in southeast")
	t.ok(main.player.global_position.y>150,"skip advances to safe departure altitude")
	t.ok(main.player.global_position.distance_to(fleet.ships[0].global_position)<2000,"Xi really departs from Valiant")
	t.ok(main.player.global_position.distance_to(previous)>1000,"handoff uses ship departure, not old spawn")
	var timeline=preload("res://scripts/data/sortie_script.gd")
	for number in range(1,13):
		var mission:="M%02d" % number
		t.eq(timeline.supported_in_mission(SuitProfile.xi(),mission),number<8,"Xi carrier launch availability "+mission)
		t.ok(timeline.supported_in_mission(SuitProfile.penelope(),mission),"other suits keep launch scenes "+mission)
	t.ok(timeline.supported_in_mission(SuitProfile.xi(),""),"non-campaign Xi launch stays available")
	for mission in ["M08","M12"]:
		main._campaign_mission_id=mission
		main._begin_sortie_or_fight(true)
		t.eq(main.phase,main.Phase.FIGHT,"late campaign Xi goes straight to battle "+mission)
		t.eq(main._sortie_director,null,"late campaign Xi creates no carrier cinematic "+mission)
		t.ok(main.player.controls_enabled,"late campaign battle starts with control "+mission)
	main._campaign_mission_id=""
	main._clear_match();await host.get_tree().process_frame
	main.world.apply_map(MapDef.uluru())
	t.eq(main.world._terrain_root.get_node_or_null("PacificFleet"),null,"changing maps removes Pacific fleet")
	main.free();await host.get_tree().process_frame
	FlightBody.use_placeholder=previous_placeholder;Settings.end_isolated()
