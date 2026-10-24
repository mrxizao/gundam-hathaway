extends Node
## 决定性实验（轮 47）：**脚本注入的「按下 / 松开边沿」到底在哪一物理帧、被谁看得见。**
##
## 为什么需要它：`penelope_cannon_shot.gd` 卡在"按住左键 1.9 s，`rifle_press_is_cannon()`
## 恒 false、弹匣照旧掉 3 发"。老探针（阿利宙斯 `cannon_shot.gd`）从没暴露这件事，
## 因为它的路由 `rifle_fire_on_release` 是**静态恒真**、根本不读按下边沿。
##
## ## 判据（一张表三条读数，缺一不可）
##   1. `pressed` 什么时候变 true —— **与边沿是不是同一帧**，这是关键。
##      真人的按下是：`pressed` 与 `just_pressed` **同帧**都为真。
##      若注入方式让 `pressed` 先真、边沿**晚一帧**才到，那么
##      「按住就连发」的那条老路会**在边沿到达之前先打掉一发** ——
##      任何"门禁依赖满弹匣"的路由（佩涅罗佩的蓄力炮就是）当场被静默判死。
##   2. `just_pressed` / `just_released` 各落在哪一帧。
##   3. `leaf`（root 的**子节点**，模拟 `main` 里的玩家）看到的是不是同一帧。
##
## 跑法（`mode` 必填，CLI 参数只能 ASCII）：
##   godot --path <工程> res://tools/_probe_input_edge.tscn -- <mode>
##   mode = act   `Input.action_press()` / `action_release()`
##        | evt   `InputEventAction` 走 `Input.parse_input_event()`
##        | mouse `InputEventMouseButton` 走 `Input.parse_input_event()`

const PRESS_AT := 5
const RELEASE_AT := 11
const WATCH_TO := 40


## 一只"最下游消费者"：与真实玩家一样在 `_physics_process` 里读边沿。
class Leaf extends Node:
	var just_frames := PackedInt32Array()
	var rel_frames := PackedInt32Array()
	var first_held := -1
	var last_held := -1

	func _physics_process(_d: float) -> void:
		var f := Engine.get_physics_frames()
		if Input.is_action_just_pressed("fire_primary"):
			just_frames.append(f)
		if Input.is_action_just_released("fire_primary"):
			rel_frames.append(f)
		if Input.is_action_pressed("fire_primary"):
			if first_held < 0:
				first_held = f
			last_held = f


var mode := "act"
var leaf: Leaf = null
var _pf := 0
var _press_frame := -1
var _rel_frame := -1
var _print_press := -1


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	leaf = Leaf.new()
	leaf.name = "Leaf"
	add_child(leaf)
	print("=== MODE %s  (PRESS_AT=%d RELEASE_AT=%d WATCH_TO=%d) ==="
		% [mode, PRESS_AT, RELEASE_AT, WATCH_TO])


func _do(down: bool) -> void:
	match mode:
		"act":
			if down:
				Input.action_press("fire_primary")
			else:
				Input.action_release("fire_primary")
		"evt":
			var e := InputEventAction.new()
			e.action = "fire_primary"
			e.pressed = down
			e.strength = 1.0
			Input.parse_input_event(e)
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = MOUSE_BUTTON_LEFT
			m.pressed = down
			m.position = Vector2(800.0, 450.0)
			m.global_position = m.position
			Input.parse_input_event(m)
		_:
			push_error("未知 mode：%s" % mode)


func _physics_process(_d: float) -> void:
	_pf += 1
	var f := Engine.get_physics_frames()
	var top_just := Input.is_action_just_pressed("fire_primary")
	var top_rel := Input.is_action_just_released("fire_primary")
	var top_held := Input.is_action_pressed("fire_primary")

	var injected := ""
	if _pf == PRESS_AT:
		_press_frame = f
		_do(true)
		injected = " <<< 注入 PRESS"
	elif _pf == RELEASE_AT:
		_rel_frame = f
		_do(false)
		injected = " <<< 注入 RELEASE"

	var aft_just := Input.is_action_just_pressed("fire_primary")
	var aft_rel := Input.is_action_just_released("fire_primary")
	var aft_held := Input.is_action_pressed("fire_primary")

	# 只印"有变化"的帧 + 注入帧，免得刷屏。
	var changed := (aft_just != top_just) or (aft_rel != top_rel) \
		or (aft_held != top_held) or injected != ""
	if changed or _pf <= PRESS_AT:
		print("F pf=%d top(just=%s rel=%s held=%s) after(just=%s rel=%s held=%s)%s"
			% [f, str(top_just), str(top_rel), str(top_held),
				str(aft_just), str(aft_rel), str(aft_held), injected])

	if _pf == WATCH_TO:
		print("SUMMARY 注入帧 press=%d release=%d" % [_press_frame, _rel_frame])
		print("SUMMARY leaf.just=%s" % str(leaf.just_frames))
		print("SUMMARY leaf.rel=%s" % str(leaf.rel_frames))
		print("SUMMARY leaf 按住帧区间 [%d, %d]" % [leaf.first_held, leaf.last_held])
		print("=== 判读：just 与 held 的**起始帧**若相同 ⇒ 与真人一致（可用）；"
			+ "held 早于 just 一帧 ⇒ 老路会抢先打一发，边沿敏感的路由必被静默判死 ===")
		get_tree().quit(0)
