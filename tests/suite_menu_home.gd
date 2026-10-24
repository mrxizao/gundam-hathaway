extends RefCounted
## Actual home controller: reachability, return targets and shared settings data.
static func run(t: T, host: Node) -> void:
	var menu := MainMenu.new()
	host.add_child(menu)
	menu.set_process(false)
	menu.set_process_input(false)
	var ui: Control = menu._home_view
	t.suite("MenuHome / 一级入口及响应式布局")
	t.eq(ui.entries(),["对战模式","剧情挑战","无限激化模拟","训练模式","局域网联机","出击音乐","歌单设置","设置","退出游戏"],"五个玩法、三个工具、退出")
	for view in [Vector2(1280,720),Vector2(1600,900),Vector2(2560,1440)]:
		ui.size = view
		for i in 9:
			var r: Rect2 = ui.home_rect(i)
			t.ok(r.position.y >= 190 and r.end.y <= view.y-50,"入口 %d 在 %s 可见" % [i,view])
			if i > 0: t.ok(r.position.y + 0.01 >= ui.home_rect(i-1).end.y,"入口不重叠")
	t.suite("MenuHome / 工具直接打开并返回首页")
	ui.open_entry(5)
	ui.sync(0)
	t.eq(menu.stage,MainMenu.Stage.BGM,"音乐直达")
	t.eq(menu.bgm_sub,MainMenu.BGM_SUB_PICK,"音乐选择首曲")
	t.eq(menu._bgm_focus_row(),Settings.battle_bgm_index(),"聚焦已保存首曲")
	ui.back()
	t.eq(menu.stage,MainMenu.Stage.MODE,"首曲退到首页")
	ui.open_entry(6)
	ui.sync(0)
	t.eq(menu.bgm_sub,MainMenu.BGM_SUB_LIST,"歌单直达")
	t.eq(ui.body_rows().size(),MainMenu.bgm_pick_keys().size()-1,"歌单不含不可加入的随机项")
	ui.query = "tracer"
	t.eq(ui.body_rows().size(),1,"曲目搜索不分大小写")
	t.eq(ui.body_rows()[0]["key"],"tracer","过滤保留真实曲目键")
	ui.back()
	t.eq(menu.stage,MainMenu.Stage.MODE,"歌单直接退首页")
	ui.open_entry(7)
	ui.sync(0)
	t.eq(menu.stage,MainMenu.Stage.SETTINGS,"设置一级入口")
	var seen: Array = []
	for tab in 4:
		ui.settings_tab = tab
		for i in ui.setting_indices(): seen.append(MainMenu.SETTING_ROWS[i]["key"])
	for row: Dictionary in MainMenu.SETTING_ROWS:
		if row["key"] in ["battle_bgm","battle_playlist"]: t.not_ok(seen.has(row["key"]),"音乐已迁移到首页")
		else: t.ok(seen.has(row["key"]),"原设置保留："+str(row["key"]))
	menu.settings_sub = MainMenu.SET_SUB_VOLUME
	ui.sync(0)
	t.eq(ui.body_rows().size(),MainMenu.volume_rows().size(),"全部混音通道保留")
	ui.back()
	t.eq(menu.settings_sub,MainMenu.SET_SUB_MAIN,"混音只退一级")
	ui.back()
	t.eq(menu.stage,MainMenu.Stage.MODE,"设置退首页")
	menu.stage = MainMenu.Stage.SETTINGS
	menu._settings_return_stage = MainMenu.Stage.SUIT
	ui.back()
	t.eq(menu.stage,MainMenu.Stage.SUIT,"快捷设置回出击准备页")
	t.suite("MenuHome / 玩法链路与安全退出")
	ui.open_entry(0)
	t.eq(menu.stage,MainMenu.Stage.BATTLE,"对战先选形式")
	ui.open_entry(2)
	t.ok(menu.endless_mode(),"无尽使用真实模式枚举")
	t.eq(menu.stage,MainMenu.Stage.SUIT,"无尽沿用选机流程")
	ui.open_entry(3)
	t.ok(menu.training_mode(),"训练入口未移错")
	ui.open_entry(4)
	t.ok(menu.lan_mode(),"联机入口未移错")
	menu.stage = MainMenu.Stage.MODE
	ui.open_entry(8)
	t.ok(ui.confirm_quit and ui.cancel_selected,"退出默认取消")
	ui.back()
	t.not_ok(ui.confirm_quit,"可取消退出")
	_music(t,menu,ui)
	menu.free()

static func _music(t: T, menu: MainMenu, ui: Control) -> void:
	t.suite("MenuHome / music preview and playlist intent")
	var saved_pick := Settings.battle_bgm_pick
	var saved_list := Settings.battle_playlist.duplicate()
	Settings.set_battle_playlist([])
	ui.open_entry(6)
	ui.sync(0)
	var rows: Array = ui.body_rows()
	var first: String = rows[0]["key"]
	ui.content_index = 0
	ui._preview()
	t.eq(Audio.preview_track(),first,"explicit preview starts focused song")
	t.eq(Settings.battle_playlist.size(),0,"preview does not add song")
	t.eq(Settings.battle_bgm_pick,saved_pick,"preview does not change first song")
	t.eq(Audio.preview_status()["track"],first,"playback status reflects actual preview")
	ui._preview()
	t.eq(Audio.preview_track(),"","same song preview toggles stop")
	t.near(Audio.preview_status()["progress"],0,0.0001,"stop clears progress")
	ui._confirm_body()
	t.ok(Settings.in_playlist(first),"confirm explicitly adds song")
	ui._toggle_selected_filter()
	t.eq(ui.body_rows().size(),1,"selected filter shows actual playlist")
	ui._confirm_body()
	t.eq(ui.body_rows().size(),0,"removing last selected song empties filter safely")
	ui._preview()
	t.eq(Audio.preview_track(),"","empty filtered list cannot start phantom playback")
	ui._toggle_selected_filter()
	menu.active = true
	menu.input_lockout = 0
	menu._await_release = false
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var row: Rect2 = ui.body_row_rect(0)
	click.position = row.position + Vector2(90,23)
	ui.route_event(click)
	ui.read_input()
	t.eq(Settings.battle_playlist.size(),0,"clicking song title previews without modifying playlist")
	t.eq(Audio.preview_track(),first,"mouse title click previews the intended song")
	click.position = ui.music_choice_rect(row).get_center()
	ui.route_event(click)
	ui.read_input()
	t.ok(Settings.in_playlist(first),"separate row action adds song")
	Audio.stop_preview(0)
	ui.content_index = 1
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_X
	pad.pressed = true
	ui.route_event(pad)
	ui.read_input()
	t.eq(Audio.preview_track(),str(ui.body_rows()[1]["key"]),"gamepad X previews selected song")
	pad.button_index = JOY_BUTTON_Y
	ui.route_event(pad)
	ui.read_input()
	t.eq(Audio.preview_track(),"","gamepad Y stops preview")
	for view: Vector2 in [Vector2(1280,720),Vector2(1600,900),Vector2(2560,1600)]:
		ui.size = view
		ui.scroll_first = 0
		var last: Rect2 = ui.body_row_rect(ui.visible_rows()-1)
		t.ok(last.end.y <= ui.body_rect().end.y-90,"rows leave room for preview player")
		for action in ["preview","stop","filter","clear"]:
			t.ok(Rect2(Vector2.ZERO,view).encloses(ui.action_rect(action)),"music action fits "+action)
		t.ok(not ui.music_preview_rect(last).intersects(ui.music_choice_rect(last)),"preview and selection targets stay separate")
	ui.open_entry(5)
	ui.sync(0)
	ui.content_index = 0
	ui._preview()
	t.eq(Audio.preview_track(),"","random first-song option has no false preview")
	t.ok(not ui.feedback.is_empty(),"random choice explains why no song is previewed")
	ui.content_index = 1
	ui._preview()
	ui.back()
	t.eq(Audio.preview_track(),"","leaving music stops preview")
	Settings.set_battle_playlist(saved_list)
	Settings.battle_bgm_pick = saved_pick
