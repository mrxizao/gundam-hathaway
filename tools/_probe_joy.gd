extends SceneTree
## 一次性探针：手工造的 InputEventJoypadButton 能不能被 is_action_pressed() 认出来。
## 判据全靠这一条 —— 认不出来的话，注入式测试就证明不了任何事。
##
## ⚠️ `--script` **不启动 autoload** ⇒ 必须自己跑一遍 `InputSetup.ensure_all()`，
## 否则 `missile_mode` 这类"只在运行时注册进 InputMap"的动作会报
## "The InputMap action doesn't exist" —— 那是**假阴性**（本仓库记过的老坑）。

const ISU := preload("res://scripts/autoload/input_setup.gd")


func _initialize() -> void:
	var added := ISU.ensure_all()
	print("ensure_all 新注册了 %d 个动作" % added.size())
	var probes: Array = [
		["confirm", JOY_BUTTON_A],
		["fire_gun", JOY_BUTTON_RIGHT_SHOULDER],
		["menu_back", JOY_BUTTON_B],
		["switch_target", JOY_BUTTON_DPAD_UP],
		["flares", JOY_BUTTON_DPAD_DOWN],
		["missile_mode", JOY_BUTTON_DPAD_LEFT],
		["switch_weapon", JOY_BUTTON_DPAD_RIGHT],
	]
	for p: Array in probes:
		var act := str(p[0])
		var btn := int(p[1])
		var ev := InputEventJoypadButton.new()
		ev.button_index = btn
		ev.pressed = true
		var hit := ev.is_action_pressed(act)
		var raw := InputMap.has_action(act)
		print("  %-16s btn=%-3d 动作存在=%s  is_action_pressed=%s" % [act, btn, str(raw), str(hit)])
	# 反面：不该串的
	var ev2 := InputEventJoypadButton.new()
	ev2.button_index = JOY_BUTTON_B
	ev2.pressed = true
	print("  反面 B is confirm? ", ev2.is_action_pressed("confirm"))
	print("  反面 A is menu_back? ", InputEventJoypadButton.new().is_action_pressed("menu_back"))
	# 反面：没按下的按键不该算
	var ev3 := InputEventJoypadButton.new()
	ev3.button_index = JOY_BUTTON_A
	ev3.pressed = false
	print("  反面 未按下的 A is confirm? ", ev3.is_action_pressed("confirm"))
	quit()
