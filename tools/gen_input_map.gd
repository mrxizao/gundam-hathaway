extends SceneTree
## 把 InputSetup.BINDINGS 固化进 project.godot 的 [input] 段。
##
## 跑法：
##   godot --headless --path <工程> --script res://tools/gen_input_map.gd
##
## 为什么还要固化一份：运行时的 InputSetup autoload 是**唯一真源**（保证游戏在任何
## 情况下都有键位），但编辑器"项目设置 → 输入映射"面板读的是 project.godot。
## 不固化的话，打开编辑器看到的是空的，接手的人会以为没做输入。
##
## 注意：ProjectSettings.save() 会用 Godot 自己的格式重写整个 project.godot，
## 手写的注释会丢 —— 所以这个脚本只在键位变动时跑，跑完记得把文件头的注释补回去。

func _initialize() -> void:
	var scr := load("res://scripts/autoload/input_setup.gd")
	if scr == null:
		printerr("找不到 res://scripts/autoload/input_setup.gd")
		quit(1)
		return

	var added: Array = scr.ensure_all()
	print("运行时补齐的 action：", added)

	var written := 0
	for action: String in scr.all_actions():
		if not InputMap.has_action(action):
			continue
		var events: Array = []
		for ev: InputEvent in InputMap.action_get_events(action):
			events.append(ev)
		ProjectSettings.set_setting("input/" + action, {
			"deadzone": InputMap.action_get_deadzone(action),
			"events": events,
		})
		written += 1

	# 废弃动作要从 project.godot 里删掉 —— 留着的话下次启动它又会把键吃回去
	for a: String in scr.RETIRED_ACTIONS:
		if ProjectSettings.has_setting("input/" + a):
			ProjectSettings.set_setting("input/" + a, null)
			print("移除废弃动作：", a)

	var err := ProjectSettings.save()
	print("固化 %d 个 action，save() err=%d" % [written, err])
	quit(0 if err == OK else 1)
