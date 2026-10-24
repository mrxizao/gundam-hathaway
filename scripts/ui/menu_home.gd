extends Control
## Homepage and its tools. Match configuration and audio data remain in MainMenu/Settings.
const VISUALS := preload("res://scripts/ui/menu_visuals.gd")
const TILT := preload("res://shaders/menu_text_tilt.gdshader")
const WHITE := Color("edf0ed")
const MUTED := Color("8b9aa6")
const GOLD := Color("dec38d")
const LINE := Color("33414e")
const TABS := ["画面", "声音", "操作", "其他", "性能"]
var menu: Variant
var nav_index := 0
var content_focus := false
var settings_tab := 0
var content_index := 0
var scroll_first := 0
var query := ""
var selected_only := false
var feedback := ""
var confirm_clear := false
var confirm_quit := false
var cancel_selected := true
var _last_stage := -1
var _last_sub := -1
var _choice := ""
var _age := 0.0
var _pointer := Vector2.ZERO
var _pointer_active := false
var _tilt := Vector2.ZERO
var _click := ""
var _wheel := 0
var _drag_bus := ""
var _drag_rect := Rect2()
var _ignore_frame := -1
var _hover_sound_frame := -1
var _font: Font
var _focus_label: Label
var _material: ShaderMaterial
var _search: LineEdit

func setup(owner_menu: Control) -> void:
	menu = owner_menu
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	font.font_weight = 400
	_font = font
	_focus_label = Label.new()
	_focus_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = TILT
	_focus_label.material = _material
	VISUALS.prepare_selected_text(_focus_label, _font, Color(0,0,0,0.8))
	_focus_label.add_theme_constant_override("outline_size", 0)
	add_child(_focus_label)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索曲目…"
	_search.add_theme_font_override("font", _font)
	_search.add_theme_font_size_override("font_size", 16)
	for style in ["normal", "focus"]:
		var line := StyleBoxFlat.new()
		line.bg_color = Color.TRANSPARENT
		line.border_color = GOLD if style == "focus" else LINE
		line.border_width_bottom = 1
		_search.add_theme_stylebox_override(style, line)
	_search.text_changed.connect(func(value: String) -> void:
		query = value
		content_index = 0
		scroll_first = 0
		_sync_row()
		queue_redraw())
	add_child(_search)
	set_process(false)

func handles_stage() -> bool:
	return menu.stage in [menu.Stage.MODE, menu.Stage.BGM, menu.Stage.SETTINGS]

func can_adjust() -> bool:
	return content_focus and not _search.has_focus() and not confirm_quit and not confirm_clear

func entries() -> Array:
	var result: Array = []
	for group: Dictionary in menu.MODE_GROUPS:
		var title := str(group["name"])
		result.append(title)
	result.append_array(["出击音乐", "歌单设置", "设置", "退出游戏"])
	return result

func home_rect(index: int) -> Rect2:
	var row_h := clampf(size.y * 0.053333, 34, 48)
	var top := size.y * 0.26 + 24.0
	var modes: int = menu.MODE_GROUPS.size()
	var y := top + index * row_h
	if index >= modes: y += 58.0
	if index == modes + 3: y += 16.0
	return Rect2(size.x * 0.06, y, clampf(size.x * 0.28, 290, 450), row_h)

func body_rect() -> Rect2:
	return Rect2(size.x * 0.43, size.y * 0.26, size.x * 0.51, size.y * 0.64)

func body_row_rect(index: int) -> Rect2:
	var area := body_rect()
	return Rect2(area.position.x, area.position.y + 174 + (index - scroll_first) * 46, area.size.x, 46)

func visible_rows() -> int:
	return maxi(1, int((body_rect().size.y - 174 - (92 if menu.stage == menu.Stage.BGM else 0)) / 46))

func setting_indices() -> Array[int]:
	var keys: Array = []
	match settings_tab:
		0: keys = ["resolution", "fullscreen", "ssao", "cel", "motion"]
		1: keys = ["bgm", "sfx", "volume"]
		2: keys = ["cam_roll", "cam_shake", "keys"]
		3: keys = ["back", "quit", menu.PRODUCER_KEY]
		4: keys = ["low_end_60", "render_scale", "dynamic_resolution", "shadows", "effects", "magnifier_quality"]
	var result: Array[int] = []
	for key: String in keys:
		for i in menu.SETTING_ROWS.size():
			if menu.SETTING_ROWS[i]["key"] == key: result.append(i)
	return result

func body_rows() -> Array:
	var result: Array = []
	if menu.stage == menu.Stage.BGM:
		var keys: Array = menu.bgm_pick_keys()
		for i in keys.size():
			var key := str(keys[i])
			if menu.bgm_sub == menu.BGM_SUB_LIST and key.is_empty(): continue
			if menu.bgm_sub == menu.BGM_SUB_LIST and selected_only and not Settings.in_playlist(key): continue
			var title: String = "随机" if key.is_empty() else SoundBank.battle_track_label(key)
			if not query.is_empty() and not title.to_lower().contains(query.to_lower()): continue
			result.append({"title": title, "index": i, "key": key})
	elif menu.stage == menu.Stage.SETTINGS:
		if menu.settings_sub == menu.SET_SUB_VOLUME:
			var rows: Array = menu.volume_rows()
			for i in rows.size(): result.append({"title": rows[i]["label"], "index": i, "key": rows[i]["bus"]})
		else:
			for i in setting_indices(): result.append({"title": menu.setting_label(i), "index": i, "key": menu.SETTING_ROWS[i]["key"]})
	return result

func _sync_row() -> void:
	var rows := body_rows()
	content_index = clampi(content_index, 0, maxi(rows.size()-1,0))
	if rows.is_empty(): return
	var i := int(rows[content_index]["index"])
	if menu.stage == menu.Stage.BGM:
		menu._bgm_write_row(i) # Browsing does not start playback; preview is explicit.
	elif menu.settings_sub == menu.SET_SUB_VOLUME: menu.volume_row = i
	else: menu.setting_row = i
	if content_index < scroll_first: scroll_first = content_index
	if content_index >= scroll_first + visible_rows(): scroll_first = content_index - visible_rows() + 1

func sync(delta: float) -> void:
	visible = menu.visible and handles_stage()
	if not visible:
		_search.hide()
		if _last_stage == menu.Stage.BGM:
			Audio.stop_preview()
			Audio.set_menu_duck(0.0)
			_last_stage = menu.stage
		return
	if _last_stage != menu.stage or _last_sub != _sub():
		_last_stage = menu.stage
		_last_sub = _sub()
		feedback = ""
		confirm_clear = false
		if menu.stage == menu.Stage.MODE:
			content_focus = false
		elif menu.stage == menu.Stage.SETTINGS:
			nav_index = menu.MODE_GROUPS.size() + 2
			content_focus = true
			content_index = 0
			var current := body_rows()
			for i in current.size():
				if int(current[i]["index"]) == (menu.volume_row if menu.settings_sub == menu.SET_SUB_VOLUME else menu.setting_row): content_index = i
			scroll_first = 0
			_sync_row()
	var music: bool = menu.stage == menu.Stage.BGM
	_search.visible = music
	if music:
		_search.position = body_rect().position + Vector2(0,118)
		_search.size = Vector2(maxf(body_rect().size.x-370,100),34)
		Audio.set_menu_duck(-18.0 if not Audio.preview_track().is_empty() else 0.0)
	var choice := "%d:%d:%d:%s" % [menu.stage, nav_index, content_index, str(content_focus)]
	if choice != _choice:
		_choice = choice
		_age = 0
	else: _age += delta
	var target := Vector2.ZERO
	if _pointer_active and not confirm_quit:
		var r := body_row_rect(content_index) if content_focus else home_rect(nav_index)
		target = VISUALS.tilt_target(_pointer, r, Settings.reduce_motion)
	_tilt = Vector2.ZERO if Settings.reduce_motion else _tilt.lerp(target, 1.0-exp(-14*delta))
	queue_redraw()

func _sub() -> int:
	if menu.stage == menu.Stage.BGM: return menu.bgm_sub
	if menu.stage == menu.Stage.SETTINGS: return menu.settings_sub
	return 0

func open_entry(index: int) -> void:
	if menu.stage == menu.Stage.BGM:
		Audio.stop_preview()
		Audio.set_menu_duck(0.0)
	_search.release_focus()
	nav_index = clampi(index,0,entries().size()-1)
	confirm_quit = false
	feedback = ""
	query = ""
	selected_only = false
	_search.text = ""
	content_index = 0
	scroll_first = 0
	var modes: int = menu.MODE_GROUPS.size()
	if nav_index < modes:
		menu.mode_index = nav_index
		menu.stage = menu.Stage.MODE
		content_focus = false
		# ⚠️ 2026-10-11：这里**不再自己判** —— 走 `MainMenu.mode_entry_stage()`。
		# 首页是模式页的**第二个入口**（它自己接输入、自己设 `stage`），
		# 各写一遍 if/elif 的后果是"改一处、从另一处进去还是老流程"：
		# 从首页点「局域网联机」曾经仍然先走 阵营 → 机体 两页（看起来像没改）。
		# `-1` 与主入口同义：直接出击（剧情模式）。
		var nxt: int = menu.mode_entry_stage()
		if nxt < 0: menu._launch()
		else: menu.stage = nxt
	elif nav_index == modes + 3:
		confirm_quit = true
		cancel_selected = true
	elif nav_index == modes + 2:
		menu._settings_return_stage = menu.Stage.MODE
		menu.settings_sub = menu.SET_SUB_MAIN
		menu.stage = menu.Stage.SETTINGS
		content_focus = true
	else:
		menu.stage = menu.Stage.BGM
		menu.bgm_sub = menu.BGM_SUB_PICK if nav_index == modes else menu.BGM_SUB_LIST
		content_focus = true
		if menu.bgm_sub == menu.BGM_SUB_PICK:
			var rows := body_rows()
			for i in rows.size():
				if rows[i]["key"] == Settings.battle_bgm_pick: content_index = i
		_sync_row()
	Audio.play_ui("ui_confirm")

func back() -> void:
	_search.release_focus()
	if confirm_quit or confirm_clear:
		confirm_quit = false
		confirm_clear = false
		return
	if menu.stage == menu.Stage.SETTINGS and menu.settings_sub == menu.SET_SUB_VOLUME:
		menu.settings_sub = menu.SET_SUB_MAIN
	elif menu.stage == menu.Stage.SETTINGS:
		menu.stage = menu._settings_return_stage
	else: menu.stage = menu.Stage.MODE
	content_focus = false
	Audio.stop_preview()
	Audio.set_menu_duck(0.0)
	Audio.play_ui("ui_return")

func _preview() -> void:
	var rows := body_rows()
	if rows.is_empty(): return
	var key := str(rows[clampi(content_index,0,rows.size()-1)]["key"])
	if key.is_empty():
		Audio.stop_preview()
		feedback = "随机首曲没有固定音源，请选择一首歌曲试听。"
	elif Audio.preview_track() == key:
		Audio.stop_preview()
		feedback = ""
	else:
		Audio.preview_bgm(key)
		feedback = "" if Audio.preview_track() == key else "这首歌曲暂时无法试听。"

func _toggle_selected_filter() -> void:
	selected_only = not selected_only
	content_index = 0
	scroll_first = 0
	_sync_row()

func music_choice_rect(row: Rect2) -> Rect2:
	return Rect2(row.end.x-124,row.position.y+5,124,row.size.y-10)

func music_preview_rect(row: Rect2) -> Rect2:
	return Rect2(row.end.x-184,row.position.y+5,52,row.size.y-10)

func _fit(text: String, width: float, fs: int) -> String:
	var label := text
	while label.length()>1 and _font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x > width:
		label = label.left(label.length()-2)+"…"
	return label

func _confirm_body() -> void:
	var rows := body_rows()
	if rows.is_empty(): return
	_sync_row()
	if menu.stage == menu.Stage.BGM:
		var key := str(rows[content_index]["key"])
		if menu.bgm_sub == menu.BGM_SUB_LIST:
			var was_selected := Settings.in_playlist(key)
			menu._playlist_toggle_row(int(rows[content_index]["index"]))
			feedback = menu.bgm_msg if not menu.bgm_msg.is_empty() else ("已移出歌单" if was_selected else "已加入歌单")
			_sync_row()
		else:
			Settings.set_battle_bgm_index(int(rows[content_index]["index"]))
			feedback = "已设为首曲 · " + str(rows[content_index]["title"])
			Audio.play_ui("ui_confirm")
	elif menu.settings_sub == menu.SET_SUB_MAIN:
		var key := str(rows[content_index]["key"])
		if key == "keys":
			menu.stage = menu.Stage.KEYS
			menu.keys_row = 0
			menu.keys_slot = 0
			menu.keys_scroll = 0
			menu.keys_msg = ""
		elif key == "volume": menu.settings_sub = menu.SET_SUB_VOLUME
		elif key == "back": back()
		elif key == "quit":
			confirm_quit = true
			cancel_selected = true
		elif key == menu.PRODUCER_KEY: menu._activate_producer()
		else: menu._apply_setting_delta(1,true)

func read_input() -> void:
	if Engine.get_process_frames() == _ignore_frame: return
	if _search.has_focus():
		if Input.is_action_just_pressed("menu_back"):
			_search.release_focus()
		return
	if confirm_quit or confirm_clear:
		var d: int = menu._axis_delta(menu.Nav.X)
		if d != 0: cancel_selected = not cancel_selected
		var click := _click
		_click = ""
		if Input.is_action_just_pressed("menu_back") or menu._mi_back or click in ["cancel","back"]:
			confirm_quit = false
			confirm_clear = false
		elif Input.is_action_just_pressed("confirm") or click == "accept":
			if cancel_selected and click != "accept":
				confirm_quit = false
				confirm_clear = false
			elif confirm_quit: menu.quit_game()
			else:
				Settings.clear_playlist()
				confirm_clear = false
				feedback = "歌单已清空，战斗将使用默认轮换池。"
				_sync_row()
		return
	if Input.is_action_just_pressed("menu_back") or menu._mi_back or _click == "back":
		_click = ""
		if menu.stage == menu.Stage.MODE:
			confirm_quit = true
			cancel_selected = true
		else: back()
		return
	if Input.is_action_just_pressed("open_settings"):
		if menu.stage == menu.Stage.SETTINGS: back()
		else: open_entry(menu.MODE_GROUPS.size()+2)
		return
	var d: int = menu._axis_delta(menu.Nav.Y)
	if d == 0: d = _wheel
	_wheel = 0
	if d != 0:
		_pointer_active = false
		if content_focus:
			var count := body_rows().size()
			if count > 0: content_index = posmod(content_index+d,count)
			_sync_row()
		else: nav_index = posmod(nav_index+d,entries().size())
		Audio.play_ui("ui_select")
	var click := _click
	_click = ""
	if click == "preview": _preview()
	elif click == "stop": Audio.stop_preview(); feedback = ""
	elif click == "filter": _toggle_selected_filter()
	elif click == "clear":
		if menu.bgm_sub == menu.BGM_SUB_LIST:
			confirm_clear = true
			cancel_selected = true
		else: Settings.set_battle_bgm_index(0)
	elif click == "minus" or click == "plus":
		var step := -1 if click == "minus" else 1
		if menu.settings_sub == menu.SET_SUB_VOLUME:
			var row: Dictionary = body_rows()[content_index]
			Settings.set_volume(str(row["key"]),Settings.volume(str(row["key"]))+step*Settings.VOLUME_STEP)
		else: menu._apply_setting_delta(step,true)
	elif Input.is_action_just_pressed("confirm") or menu._mi_ok or click == "confirm":
		if content_focus: _confirm_body()
		else: open_entry(nav_index)

func _hover_sound(changed: bool) -> void:
	if changed and _hover_sound_frame != Engine.get_process_frames():
		_hover_sound_frame = Engine.get_process_frames()
		Audio.play_ui("ui_select")

func route_event(event: InputEvent) -> void:
	if not menu.visible: return
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_pointer_active = false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _search.has_focus():
			_search.release_focus()
			_ignore_frame = Engine.get_process_frames()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_TAB and not _search.has_focus():
			content_focus = not content_focus if menu.stage != menu.Stage.MODE else false
			get_viewport().set_input_as_handled()
		if event.keycode in [KEY_PAGEUP,KEY_PAGEDOWN] and menu.stage == menu.Stage.SETTINGS:
			settings_tab = posmod(settings_tab + (1 if event.keycode == KEY_PAGEDOWN else -1),TABS.size())
			content_index = 0
			scroll_first = 0
			menu.settings_sub = menu.SET_SUB_MAIN
			_sync_row()
		if event.keycode == KEY_SPACE and menu.stage == menu.Stage.BGM and not _search.has_focus(): _click = "preview"
	if menu.stage == menu.Stage.BGM and not _search.has_focus():
		if event is InputEventJoypadButton and event.pressed:
			if event.button_index == JOY_BUTTON_X: _click = "preview"
			elif event.button_index == JOY_BUTTON_Y: _click = "stop"
			elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER and menu.bgm_sub == menu.BGM_SUB_LIST: _click = "filter"
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_F and menu.bgm_sub == menu.BGM_SUB_LIST: _click = "filter"
	if not (event is InputEventMouse): return
	if event is InputEventMouseMotion and not _pointer_active and event.position.distance_to(_pointer) < 0.5:
		return
	_pointer = event.position
	_pointer_active = true
	if event is InputEventMouseMotion:
		if not _drag_bus.is_empty():
			Settings.set_volume(_drag_bus,clampf((_pointer.x-_drag_rect.position.x)/_drag_rect.size.x,0,1))
			return
		if menu._time < menu._hover_mute_until: return
		if confirm_quit or confirm_clear: return
		for i in entries().size():
			if home_rect(i).has_point(_pointer):
				_hover_sound(nav_index != i or content_focus)
				nav_index = i
				content_focus = false
				return
		if menu.stage != menu.Stage.MODE:
			for i in range(scroll_first,mini(body_rows().size(),scroll_first+visible_rows())):
				if body_row_rect(i).has_point(_pointer):
					_hover_sound(content_index != i or not content_focus)
					content_focus = true
					content_index = i
					_sync_row()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_drag_bus = ""
		return
	if not (event is InputEventMouseButton) or not event.pressed: return
	if not (menu.active and menu.input_lockout <= 0.0 and not menu._await_release): return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_click = "back"
		return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		menu._hover_mute_until = menu._time + menu.WHEEL_HOVER_MUTE
		_wheel += -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
		return
	if event.button_index != MOUSE_BUTTON_LEFT: return
	if confirm_quit or confirm_clear:
		if _dialog_button(false).has_point(_pointer): _click = "cancel"
		elif _dialog_button(true).has_point(_pointer): _click = "accept"
		return
	for i in entries().size():
		if home_rect(i).has_point(_pointer):
			nav_index = i
			content_focus = false
			_search.release_focus()
			_click = "confirm"
			return
	if menu.stage == menu.Stage.MODE: return
	if menu.stage == menu.Stage.SETTINGS and menu.settings_sub == menu.SET_SUB_MAIN:
		for i in TABS.size():
			if _tab_rect(i).has_point(_pointer):
				settings_tab = i
				content_index = 0
				scroll_first = 0
				content_focus = true
				_sync_row()
				return
	for action: String in ["back","clear","preview","stop","filter"]:
		if action_rect(action).has_point(_pointer):
			_search.release_focus()
			_click = action
			return
	for i in range(scroll_first,mini(body_rows().size(),scroll_first+visible_rows())):
		var r := body_row_rect(i)
		if r.has_point(_pointer):
			_search.release_focus()
			content_focus = true
			content_index = i
			_sync_row()
			if menu.stage == menu.Stage.BGM:
				var checkbox := Rect2(r.position,Vector2(30,r.size.y))
				_click = "confirm" if music_choice_rect(r).has_point(_pointer) or checkbox.has_point(_pointer) else "preview"
				return
			if menu.stage == menu.Stage.SETTINGS:
				var key := str(body_rows()[i]["key"])
				if (menu.settings_sub == menu.SET_SUB_VOLUME or key in ["bgm","sfx"]) and _volume_rect(r).has_point(_pointer):
					_drag_bus = key if menu.settings_sub == menu.SET_SUB_VOLUME else (Settings.BUS_BGM if key == "bgm" else Settings.BUS_SFX)
					_drag_rect = _volume_rect(r)
					Settings.set_volume(_drag_bus,clampf((_pointer.x-_drag_rect.position.x)/_drag_rect.size.x,0,1))
					return
				if menu.settings_sub == menu.SET_SUB_VOLUME or not menu._setting_is_action(key) and key != "volume":
					_click = "minus" if _pointer.x < r.end.x-180 and _pointer.x > r.end.x-240 else "plus"
				else: _click = "confirm"
			else: _click = "confirm"
			return

func _volume_rect(row: Rect2) -> Rect2:
	return Rect2(row.end.x-200,row.position.y+8,105,row.size.y-16)

func _tab_rect(i: int) -> Rect2:
	return Rect2(body_rect().position+Vector2(i*100,112),Vector2(92,38))

func action_rect(action: String) -> Rect2:
	var r := body_rect()
	match action:
		"back": return Rect2(r.position+Vector2(r.size.x-80,0),Vector2(80,38))
		"clear": return Rect2(r.position+Vector2(r.size.x-126,118),Vector2(126,34)) if menu.stage == menu.Stage.BGM else Rect2()
		"preview": return Rect2(r.position+Vector2(0,r.size.y-62),Vector2(170,30)) if menu.stage == menu.Stage.BGM else Rect2()
		"stop": return Rect2(r.position+Vector2(180,r.size.y-62),Vector2(80,30)) if menu.stage == menu.Stage.BGM else Rect2()
		"filter": return Rect2(r.end.x-350,r.position.y+118,180,34) if menu.stage == menu.Stage.BGM and menu.bgm_sub == menu.BGM_SUB_LIST else Rect2()
	return Rect2()

func _dialog_button(accept: bool) -> Rect2:
	return Rect2(body_rect().position+Vector2(180 if accept else 0,150),Vector2(150,46))

func _text(at: Vector2, text: String, fs: int, color := WHITE, focused := false) -> void:
	if focused:
		var extent := Vector2(_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x,_font.get_height(fs))
		var scale := VISUALS.focus_scale(_age,true,Settings.reduce_motion)
		_focus_label.text = text
		_focus_label.add_theme_font_size_override("font_size",fs)
		_focus_label.size = extent
		_focus_label.scale = Vector2.ONE*scale
		_focus_label.position = at-Vector2(0,_font.get_ascent(fs))-extent*(scale-1)*0.5
		_material.set_shader_parameter("pivot",extent*0.5)
		_material.set_shader_parameter("tilt",_tilt)
		_material.set_shader_parameter("camera_distance",maxf(320,extent.x*2))
		_focus_label.show()
	else: draw_string(_font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,color)

func _right(at: Vector2,text: String,fs: int,color := MUTED) -> void:
	_text(at-Vector2(_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x,0),text,fs,color)

func _draw() -> void:
	if not is_instance_valid(_focus_label): return
	_focus_label.hide()
	var tex: Texture2D = menu.title_texture()
	if tex != null: draw_texture_rect(tex,Rect2(Vector2(54,72),Vector2(96*float(tex.get_width())/tex.get_height(),96)),false)
	_text(Vector2(420,126),"MAIN MENU",13,MUTED)
	var modes: int = menu.MODE_GROUPS.size()
	_text(home_rect(0).position+Vector2(18,-14),"出  击",11,MUTED)
	var line_y := home_rect(modes).position.y-30
	draw_line(Vector2(home_rect(0).position.x+18,line_y),Vector2(home_rect(0).end.x-18,line_y),LINE,1)
	_text(home_rect(modes).position+Vector2(18,-14),"准  备",11,MUTED)
	var labels := entries()
	for i in labels.size():
		var r := home_rect(i)
		var selected := i == nav_index
		if selected:
			draw_rect(Rect2(r.position+Vector2(0,r.size.y*0.5-10),Vector2(2,20)),GOLD)
			_text(Vector2(r.end.x-6,r.get_center().y+6),"›",20,GOLD)
		_text(Vector2(r.position.x+18,r.get_center().y+4),"%02d" % (i+1) if i < modes+3 else "—",11,GOLD if selected else MUTED)
		var fs := 17 if i == modes+3 else int(clampf(size.x*0.01625,21,26))
		_text(Vector2(r.position.x+58,r.get_center().y+fs*0.35),str(labels[i]),fs,WHITE if selected else MUTED,selected and not content_focus and not confirm_quit and not confirm_clear)
	# The user removed the homepage control hint; no instruction footer is drawn.
	_right(Vector2(size.x*0.94,size.y-40),"首曲：%s  /  歌单：%s" % [Settings.battle_bgm_label(),Settings.playlist_label()],11,MUTED)
	if confirm_quit or confirm_clear:
		_draw_dialog()
	elif menu.stage != menu.Stage.MODE:
		_draw_body()

func _draw_dialog() -> void:
	var at := body_rect().position
	_text(at+Vector2(0,30),"退出游戏？" if confirm_quit else "清空战斗歌单？",28)
	_text(at+Vector2(0,78),"取消将返回当前页面。" if confirm_quit else "清空后使用模式默认曲池。",14,MUTED)
	for accept in [false,true]:
		var r := _dialog_button(accept)
		draw_line(r.position+Vector2(0,r.size.y),r.end,GOLD if accept != cancel_selected else LINE,1)
		_text(r.position+Vector2(12,30),"退出" if confirm_quit and accept else ("清空" if accept else "取消"),19,WHITE if accept != cancel_selected else MUTED)

func _draw_body() -> void:
	var r := body_rect()
	var is_music: bool = menu.stage == menu.Stage.BGM
	var title := "歌单设置" if is_music and menu.bgm_sub == menu.BGM_SUB_LIST else ("出击音乐" if is_music else "设置")
	if not is_music and menu.settings_sub == menu.SET_SUB_VOLUME: title = "音量细分"
	_text(r.position+Vector2(0,30),title,28)
	_right(r.position+Vector2(r.size.x,28),"返回",14)
	var subtitle := "决定每场战斗的首曲；专属剧情音乐仍优先。" if is_music else "改动立即生效并保存。"
	if not is_music and settings_tab==4: subtitle = "低画质面向750 Ti；机体贴图预算下次出击生效，界面保持清晰。"
	if is_music and menu.bgm_sub == menu.BGM_SUB_LIST: subtitle = "最多 6 首 · 每轮随机播放一遍，再重新洗牌循环。"
	_text(r.position+Vector2(0,70),subtitle,13,MUTED)
	if is_music:
		_right(r.position+Vector2(r.size.x,100),"当前："+ (Settings.playlist_label() if menu.bgm_sub == menu.BGM_SUB_LIST else Settings.battle_bgm_label()),13,GOLD)
		_right(r.position+Vector2(r.size.x,142),"清空歌单" if menu.bgm_sub == menu.BGM_SUB_LIST else "恢复随机",14)
		if menu.bgm_sub == menu.BGM_SUB_LIST:
			_text(action_rect("filter").position+Vector2(0,22),"✓ 仅看已选" if selected_only else "仅看已选",13,GOLD if selected_only else MUTED)
		_draw_music_player()
	else:
		if menu.settings_sub == menu.SET_SUB_MAIN:
			for i in TABS.size():
				var tab := _tab_rect(i)
				_text(tab.position+Vector2(0,25),TABS[i],15,WHITE if i == settings_tab else MUTED)
				if i == settings_tab: draw_line(tab.position+Vector2(0,35),tab.position+Vector2(40,35),GOLD,1)
	var rows := body_rows()
	for i in range(scroll_first,mini(rows.size(),scroll_first+visible_rows())):
		var rr := body_row_rect(i)
		draw_line(Vector2(rr.position.x,rr.end.y),rr.end,Color(LINE,0.6),1)
		var row: Dictionary = rows[i]
		var key := str(row["key"])
		if not is_music and key == menu.PRODUCER_KEY and not Game.producer_mode: continue
		var selected := content_focus and i == content_index
		var left := rr.position.x
		if is_music:
			var chosen: bool = Settings.in_playlist(key) if menu.bgm_sub == menu.BGM_SUB_LIST else Settings.battle_bgm_pick == key
			_text(Vector2(left,rr.get_center().y+6),"✓" if chosen else "○",16,GOLD if chosen else MUTED)
			left += 30
		var label := str(row["title"])
		var max_width := rr.size.x-240
		while label.length()>1 and _font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x > max_width: label = label.left(label.length()-2)+"…"
		_text(Vector2(left,rr.get_center().y+6),label,18,WHITE if selected else MUTED,selected)
		var value := ""
		if is_music:
			var playing := Audio.preview_track() == key and not key.is_empty()
			_text(music_preview_rect(rr).position+Vector2(4,24),"■" if playing else ("▶" if not key.is_empty() else "—"),15,GOLD if playing else MUTED)
			if menu.bgm_sub == menu.BGM_SUB_LIST: value = "移出歌单" if Settings.in_playlist(key) else "＋ 加入歌单"
			else: value = "✓ 当前首曲" if Settings.battle_bgm_pick == key else "设为首曲"
		elif menu.settings_sub == menu.SET_SUB_VOLUME: value = "%d%%" % int(round(Settings.volume(key)*100))
		elif menu._setting_is_action(key) or key == "volume": value = "打开" if key in ["keys","volume"] else "确认"
		else: value = menu._setting_value_text(key)
		var adjustable: bool = not is_music and (menu.settings_sub == menu.SET_SUB_VOLUME or not menu._setting_is_action(key) and key != "volume")
		if adjustable:
			_text(Vector2(rr.end.x-218,rr.get_center().y+5),"‹",18,GOLD if selected else MUTED)
			_text(Vector2(rr.end.x-22,rr.get_center().y+5),"›",18,GOLD if selected else MUTED)
			if menu.settings_sub == menu.SET_SUB_VOLUME or key in ["bgm","sfx"]:
				var bus := key if menu.settings_sub == menu.SET_SUB_VOLUME else (Settings.BUS_BGM if key == "bgm" else Settings.BUS_SFX)
				var track := _volume_rect(rr)
				var start := Vector2(track.position.x,track.get_center().y)
				draw_line(start,start+Vector2(track.size.x,0),LINE,1)
				draw_line(start,start+Vector2(track.size.x*Settings.volume(bus),0),GOLD if selected else MUTED,2)
		_right(Vector2(rr.end.x-(42 if adjustable else 14),rr.get_center().y+5),value,14,GOLD if selected else MUTED)
	if rows.is_empty(): _text(r.position+Vector2(0,210),"暂无已选歌曲，请关闭筛选后添加。" if is_music and selected_only and query.is_empty() else "没有匹配的曲目",16,MUTED)
	if rows.size() > visible_rows():
		_right(r.position+Vector2(r.size.x,r.size.y-90 if is_music else r.size.y+26),"%d / %d" % [content_index+1,rows.size()],12,MUTED)
	if not feedback.is_empty(): _text(r.position+Vector2(0,100 if is_music else r.size.y+54),_fit(feedback,r.size.x-260 if is_music else r.size.x,12),12,GOLD)

func _draw_music_player() -> void:
	var r := body_rect()
	var status: Dictionary = Audio.preview_status()
	var key := str(status["track"])
	var rows := body_rows()
	var selected_key := str(rows[clampi(content_index,0,rows.size()-1)]["key"]) if not rows.is_empty() else ""
	var title := "未在试听 · 点击曲名或按空格 / X" if key.is_empty() else "正在试听 · " + SoundBank.battle_track_label(key)
	_text(Vector2(r.position.x,r.end.y-78),_fit(title,r.size.x-100,12),12,GOLD if not key.is_empty() else MUTED)
	if not key.is_empty(): _right(Vector2(r.end.x,r.end.y-78),"%02d / %02d 秒" % [int(status["elapsed"]),int(status["duration"])],11,MUTED)
	_text(action_rect("preview").position+Vector2(0,21),"■ 停止试听" if not selected_key.is_empty() and selected_key == key else "▶ 试听选中曲目",13)
	_text(action_rect("stop").position+Vector2(0,21),"■ 停止",13,MUTED)
	var hint := "Enter / A 加入或移出 · F / RB 已选" if menu.bgm_sub == menu.BGM_SUB_LIST else "Enter / A 设为首曲"
	_text(Vector2(r.position.x+280,r.end.y-41),_fit(hint,r.size.x-280,11),11,MUTED)
	var start := Vector2(r.position.x,r.end.y-18)
	draw_line(start,start+Vector2(r.size.x,0),LINE,2)
	draw_line(start,start+Vector2(r.size.x*float(status["progress"]),0),GOLD,2)
