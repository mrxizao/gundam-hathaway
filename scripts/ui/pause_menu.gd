class_name PauseMenu
extends Control
## 战斗中的暂停菜单（INTRO / FIGHT 阶段按 `Esc` 或手柄 `Start` 打开）。
##
## ## 为什么单独一个节点，而不是继续画在 HUD 里
## 暂停期间**世界是真的停住的**（`get_tree().paused = true`，见 main.gd 的
## PROCESS_MODE 说明）。这时还在 `_process` 的只有主控、HUD、主菜单、以及这里。
## 既然"暂停"是一个有选项的界面，它就该像主菜单一样有所有权清晰的开关
## （`open_pause()` / `close_pause()`），而不是一个贴在 HUD 上的布尔值 ——
## 早先那版只有一个 `hud.paused` 布尔，玩家按 Esc 之后既看不出发生了什么，
## 也没有"返回主菜单"的出口。
##
## ## 输入为什么必须等一次"松开"
## 打开它的那一下 `Esc` / `Start`，同一个事件在同一帧也会被本节点看到。
## 不等松开的话，按下暂停的瞬间就会被自己当成"继续"再关掉 —— 表现就是
## "按 Esc 没反应"。这跟主菜单踩过的"同一个按键被两个界面各吃一次"是同一类坑
## （见 main_menu.gd 的 `_await_release`），所以这里用同一条边沿判定，
## 不依赖计时器（无头环境下按键事件的 flush 时机不确定，计时根本挡不住）。

signal resume_requested
signal menu_requested

## 菜单项。**第一项必须是"继续战斗"**：默认动作要是最不破坏性的那个，
## 玩家按 Esc 打开菜单之后再按一次 Enter，应该回到战斗而不是丢掉本局。
const ROWS := [
	{"key": "resume", "label": "继续战斗", "note": "回到座舱"},
	{"key": "menu", "label": "返回主菜单", "note": "放弃本局 · 重选机体与难度"},
]

const HUD := Color(0.58, 1.0, 0.74)
const HUD_DIM := Color(0.40, 0.78, 0.58, 0.72)
const NEUTRAL := Color(0.92, 0.95, 1.0)
const WARN := Color(1.0, 0.74, 0.22)
const OUTLINE := Color(0.0, 0.02, 0.04, 0.9)

var open := false
## 当前选中的行。
var row := 0
var active := false
var _await_release := true

var _font: Font
var _time := 0.0
var _pad_dy := 0
var _pad_y_prev := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	if _font == null:
		_font = ThemeDB.fallback_font
	visible = false
	set_process(false)


## 由 main 调用：进入暂停界面。每次打开都回到第一项（继续战斗）。
func open_pause() -> void:
	open = true
	row = 0
	active = true
	_await_release = true
	_pad_y_prev = _pad_axis_y()
	visible = true
	set_process(true)
	queue_redraw()


## 由 main 调用：离开暂停界面（继续战斗、返回主菜单、或任何强制解除暂停的路径）。
func close_pause() -> void:
	open = false
	active = false
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	_time += delta
	_update_pad_edge()
	# 打开它的那一下按键必须先被观察到松开，否则会被自己立刻关掉
	if _await_release and not _any_accept_key_held():
		_await_release = false
	if active and not _await_release:
		_read_input()
	queue_redraw()


## 会"确认 / 返回"的那几个动作。任何一个还按着都说明上一个界面的那一下还没结束。
func _any_accept_key_held() -> bool:
	return Input.is_action_pressed("confirm") or Input.is_action_pressed("menu_back") \
		or Input.is_action_pressed("pause")


func selected_key() -> String:
	return str(ROWS[clampi(row, 0, ROWS.size() - 1)]["key"])


func _read_input() -> void:
	var ny := _nav_y()
	if ny != 0:
		row = posmod(row + ny, ROWS.size())
		Audio.play_ui("ui_select")
	if Input.is_action_just_pressed("confirm"):
		if selected_key() == "menu":
			Audio.play_ui("ui_confirm")
			menu_requested.emit()
		else:
			Audio.play_ui("ui_confirm")
			resume_requested.emit()
		return
	# Esc / 手柄 Start / 手柄 B 都是"继续战斗" —— 返回上一层在这里等于关掉暂停。
	if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("menu_back"):
		Audio.play_ui("ui_return")
		resume_requested.emit()


# ============================================================ 手柄导航

## 左摇杆"刚推过去"的那一下（轴没有 just_pressed，只能自己判边沿）。
## 十字键不用管：它已经绑在 pitch_nose_* 上，所以下面的动作查询直接就认了。
func _update_pad_edge() -> void:
	var y := _pad_axis_y()
	_pad_dy = MainMenu._edge(y, _pad_y_prev)
	_pad_y_prev = y


func _pad_axis_y() -> float:
	var dev := PlayerController.active_joypad()
	return 0.0 if dev < 0 else Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)


## 纵向导航。**符号约定和主菜单完全一致**（`MainMenu._nav_y`），
## 否则玩家在两屏之间来回切时会觉得"上下颠倒了"。
func _nav_y() -> int:
	var d := 0
	if Input.is_action_just_pressed("pitch_nose_up") or Input.is_action_just_pressed("yaw_left"):
		d = -1
	elif Input.is_action_just_pressed("pitch_nose_down") or Input.is_action_just_pressed("yaw_right"):
		d = 1
	return d if d != 0 else _pad_dy


# ============================================================ 绘制

func _draw() -> void:
	# 整屏压暗：暂停必须"一眼可见"，这是当初"卡住"和"暂停"分不出来的修法
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.60), true)

	var panel_w := 460.0
	var row_h := 66.0
	var head := 118.0
	var foot := 56.0
	var panel_h := head + row_h * float(ROWS.size()) + foot
	var px := size.x * 0.5 - panel_w * 0.5
	var py := size.y * 0.5 - panel_h * 0.5
	draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.03, 0.06, 0.10, 0.95), true)
	draw_rect(Rect2(px, py, panel_w, panel_h), Color(HUD.r, HUD.g, HUD.b, 0.45), false, UILayout.LINE_STRUCT)
	draw_rect(Rect2(px, py, panel_w, 4.0), HUD, true)

	_text_center(Vector2(size.x * 0.5, py + 52.0), "已 暂 停", 32, NEUTRAL)
	_text_center(Vector2(size.x * 0.5, py + 80.0),
		"PAUSED", 13, HUD_DIM)

	for i in ROWS.size():
		var r := Rect2(px + 14.0, py + head + row_h * float(i), panel_w - 28.0, row_h - 8.0)
		var on := i == row
		if on:
			draw_rect(r, Color(HUD.r, HUD.g, HUD.b, 0.10), true)
			draw_rect(Rect2(r.position, Vector2(4.0, r.size.y)), HUD, true)
		var col := NEUTRAL if on else Color(0.62, 0.72, 0.84)
		_text(Vector2(r.position.x + 28.0, r.position.y + 30.0), str(ROWS[i]["label"]), 20, col)
		_text(Vector2(r.position.x + 28.0, r.position.y + 50.0), str(ROWS[i]["note"]), 12,
			WARN if on else Color(0.45, 0.54, 0.66))

	var blink := HUD if int(_time * 2.0) % 2 == 0 else HUD_DIM
	_text_center(Vector2(size.x * 0.5, py + panel_h - 22.0),
		InputSetup.hint("W / S 选择 · Enter 确认 · Esc 继续",
			"十字键 / 左摇杆 选择 · A 确认 · B 继续"), 14, blink)


# ============================================================ 文本工具

func _text(pos: Vector2, s: String, fs: int, col: Color, weight := -1) -> void:
	draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		UILayout.outline_for(weight), OUTLINE)
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _text_center(pos: Vector2, s: String, fs: int, col: Color, weight := -1) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_text(pos - Vector2(w * 0.5, 0), s, fs, col, weight)
