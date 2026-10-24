extends RefCounted

static func run(t: T, _host: Node) -> void:
	t.suite("Music scope / menu, training and sortie")
	var old_list: Array[String] = Settings.battle_playlist.duplicate()
	var old_pick := Settings.battle_bgm_pick
	var old_mode := Game.match_mode
	var old_phase := Game.phase
	var old_mission = Game.active_mission
	Settings.set_battle_playlist(["tracer"])
	Settings.battle_bgm_pick = "senkou"
	var menu_tracks: Array = []
	for i in 3:
		Audio.play_bgm(Audio.Bgm.MENU, 0.0, true)
		menu_tracks.append(Audio.current_bgm_track())
		t.ok(SoundBank.MENU_TRACKS.has(Audio.current_bgm_track()), "Menu ignores sortie playlist")
	for track in SoundBank.MENU_TRACKS:
		t.ok(menu_tracks.has(track), "Original menu songs rotate once per bag")
	var main = load("res://scripts/main.gd").new()
	Game.match_mode = Game.MatchMode.TRAINING
	Game.active_mission = null
	main._start_fight()
	t.eq(Audio.current_bgm_track(), "sweet_child", "Training ignores sortie opening and playlist")
	Audio._on_bgm_finished(Audio._bgm_players[Audio._bgm_active])
	t.eq(Audio.current_bgm_track(), "sweet_child", "Training never rotates into sortie playlist")
	Game.match_mode = Game.MatchMode.VERSUS
	main.phase = main.Phase.MENU
	main._start_fight()
	t.eq(Audio.current_bgm_track(), "senkou", "Sortie honors selected opening")
	Audio._on_bgm_finished(Audio._bgm_players[Audio._bgm_active])
	t.eq(Audio.current_bgm_track(), "tracer", "Sortie rotates into custom playlist")
	main.free()
	Audio.stop_bgm(0.0)
	Settings.set_battle_playlist(old_list)
	Settings.battle_bgm_pick = old_pick
	Game.match_mode = old_mode
	Game.active_mission = old_mission
	Game.set_phase(old_phase)
