extends Control
## 任务标题卡（DESIGN §7.4）：`MISSION 04` + 任务名 + 地图名，黑底白字，2 秒，可跳过。
##
## ## 为什么是"一页纯 `_draw()` + 一个计时器"
## §7.4 的原话：「做法：一页纯 `_draw()`（与 `MainMenu` 同款）+ 一个
## `await get_tree().create_timer()`。**不引入任何新的 UI 框架。**」
## 于是这里没有 Tween、没有 AnimationPlayer、没有独立场景档 ——
## `_process` 累一个 `_t`，够 2 秒就收尾。整个"演出层"就是这一页。
##
## ## ⚠️ 无头下必须**同步跳过**
## 本页的收尾信号是 `main` 继续往下走的唯一依据。无头里若把它挂住，
## **整条回归会在"出击"这一步停住**（而且没报错，看起来像跑得很慢）。
## ⇒ 判据抽成纯函数 `should_play()`，`main` 在**调用之前**就问它，
## 不起播就不 await（见 `main._sally_sequence()`）。
##
## ⚠️ 与 `IntroMovie` 同一个坑：**任意键跳过要吃掉那一下按键**
##（`set_input_as_handled()`），否则底下的暂停菜单/菜单会**再读一次**同一个按键。

signal finished

## 任务数据层与简报页（借它的 `time_label()` —— 时段键→中文的真源只有一处，
## 标题卡与简报页**不许各写一份**，否则"简报说夜间、标题卡说按地图默认"迟早出现）。
##
## ⚠️ 两个都走 `preload` 而**不是** `class_name`：本仓库并行编辑，新加的 `class_name`
## 在编辑器重新扫描类缓存之前不在全局表里，跨文件引用会当场编译失败。
const MS := preload("res://scripts/data/mission_script.gd")
const Brief := preload("res://scripts/ui/mission_brief.gd")

## 停留时长（秒）。§7.4 定的 2 秒。
const HOLD := 2.0

## 标题排版（黑底白字，三行）。
const FS_BIG := 34
const FS_MID := 22
const FS_SMALL := 15

var active := false
var mission_id := ""
var _t := 0.0
var _font: Font


## **纯函数**：要不要起播。两条否决，各自独立可验（与 `IntroMovie` 同款写法）。
##
## - `headless`：无头下既画不出东西、又会把 `await` 挂住 ⇒ 必须同步跳过。
## - `suppressed`：`--skip-cutscenes`（开发时不想一遍遍看）。
static func should_play(headless: bool, suppressed: bool) -> bool:
	return not headless and not suppressed


static func should_play_now() -> bool:
	return should_play(DisplayServer.get_name() == "headless", has_skip_flag())


## `--skip-cutscenes` 的判定。**两张命令行表都要扫**（同 `IntroMovie._has_skip_flag()`：
## Godot 把 `--` 之后的参数放进 `get_cmdline_user_args()`，只看前者会静默失效）。
static func has_skip_flag() -> bool:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if str(a) == "--skip-cutscenes":
			return true
	return false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	if _font == null:
		_font = ThemeDB.fallback_font
	visible = false
	set_process(false)
	set_process_input(false)


## 起播。返回 false = 没起播（**调用方不要 await `finished`**）。
func play(m_id: String) -> bool:
	if m_id.is_empty():
		return false
	mission_id = m_id
	_t = 0.0
	active = true
	visible = true
	set_process(true)
	set_process_input(true)
	queue_redraw()
	return true


func skip() -> void:
	if not active:
		return
	_finish()


func _process(delta: float) -> void:
	_t += delta
	# 只在**整秒**时重画一次即可；每帧重画没有意义（文案不变）
	if _t >= HOLD:
		_finish()


func _input(event: InputEvent) -> void:
	if not active:
		return
	var hit := false
	if event is InputEventKey:
		hit = (event as InputEventKey).pressed and not (event as InputEventKey).echo
	elif event is InputEventJoypadButton:
		hit = (event as InputEventJoypadButton).pressed
	elif event is InputEventMouseButton:
		hit = (event as InputEventMouseButton).pressed
	if not hit:
		return
	# ⚠️ 吃掉这一下（同 `IntroMovie`）：不然暂停菜单也会看到这一次按键。
	get_viewport().set_input_as_handled()
	_finish()


func _finish() -> void:
	if not active:
		return
	active = false
	visible = false
	set_process(false)
	set_process_input(false)
	finished.emit()


# ============================================================ 绘制

func _draw() -> void:
	if not active:
		return
	# 黑底：整屏不透明。标题卡的作用就是"把上一屏和下一屏隔开"，
	# 留一点透明度反而会让人以为画面卡住了。
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 1.0), true)
	var m: MS.Mission = MS.by_id(mission_id)
	var big := "MISSION %02d" % (m.index if m != null else 0)
	var mid := m.title if m != null else mission_id
	# ⚠️ 不写成跨行的三元：`m.map_name()` 在 `m == null` 时会炸，
	# 而跨行三元的求值顺序读起来不明显（惰性是对的，但"读不出来"本身就是缺陷）。
	var small := ""
	if m != null:
		small = "%s · %s" % [m.map_name(), Brief.time_label(m.time_key)]
	# 三行竖直居中成一束（把整束的中心放在屏幕中心，而不是让第一行居中）
	var cx := size.x * 0.5
	var cy := size.y * 0.5
	_center(big, cy - 36.0, FS_BIG, FlightHUD.NEUTRAL)
	_center(mid, cy + 4.0, FS_MID, FlightHUD.HUD)
	_center(small, cy + 34.0, FS_SMALL, FlightHUD.HUD_DIM)
	# 标题束上下各一条极细横线（本工程"线语言"：细线只做结构，不做装饰）
	var half := minf(size.x * 0.18, 260.0)
	var top := cy - 62.0
	var bot := cy + 56.0
	draw_line(Vector2(cx - half, top), Vector2(cx + half, top),
		FlightHUD.deco_white(0.28), UILayout.LINE_HAIR)
	draw_line(Vector2(cx - half, bot), Vector2(cx + half, bot),
		FlightHUD.deco_white(0.28), UILayout.LINE_HAIR)


func _center(text: String, y: float, fs: int, col: Color) -> void:
	if text.is_empty():
		return
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(_font, Vector2(size.x * 0.5 - w * 0.5, y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UILayout.OUTLINE_EMPH, FlightHUD.OUTLINE)
	draw_string(_font, Vector2(size.x * 0.5 - w * 0.5, y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


# ============================================================ 读数口

## 三行文案（测试与探针读它，不去截屏认字）。
func lines() -> Array:
	var m: MS.Mission = MS.by_id(mission_id)
	if m == null:
		return ["", mission_id, ""]
	return ["MISSION %02d" % m.index, m.title,
		"%s · %s" % [m.map_name(), Brief.time_label(m.time_key)]]


func progress_ratio() -> float:
	return clampf(_t / HOLD, 0.0, 1.0)
