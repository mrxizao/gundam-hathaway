extends Node
## 一次性诊断探针：完整走一遍「开局 → 击坠 → 结算 → 再战一局」，
## 每一步打印状态，用来定位"再战一局卡住"。
## 跑法：godot --headless --path <工程> res://tools/probe_replay.tscn


func _ready() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _f(20)
	print("1. 主菜单就绪  Game.phase=%d  paused=%s" % [Game.phase, str(get_tree().paused)])

	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.HARD)
	await _f(20)
	var p1 = main.get("player")
	print("2. 出生完成  player=%s  phase=%d" % [str(p1 != null), Game.phase])

	main.call("_start_fight")
	await _f(40)
	print("3. 战斗中  phase=%d" % Game.phase)

	var e = main.get("enemy")
	e.ifield_hp = 0.0
	e.take_damage(999999.0, p1, Damage.Type.SABER)
	await _f(60)
	print("4. 击坠后  Game.phase=%d  paused=%s  main.phase=%d"
		% [Game.phase, str(get_tree().paused), main.get("phase")])

	# 等结算输入锁（0.6 s）过期
	await _f(60)
	print("5. 输入锁已过  lockout=%s" % str(main.get("_phase_lockout")))

	_press(KEY_ENTER, true)
	await _f(6)
	_press(KEY_ENTER, false)
	await _f(40)

	print("6. 再战之后  Game.phase=%d  paused=%s  main.phase=%d"
		% [Game.phase, str(get_tree().paused), main.get("phase")])
	var p2 = main.get("player")
	var ok := p2 != null and is_instance_valid(p2)
	print("   新机体=%s" % str(ok))
	if ok:
		var pos0: Vector3 = p2.global_position
		var spd0: float = p2.fm.speed
		await _f(60)
		var moved: float = pos0.distance_to(p2.global_position)
		print("   60 帧内位移 %.2f m（速度 %.0f → %.0f）" % [moved, spd0, p2.fm.speed])
		print("   >> %s" % ("机体在动，游戏没卡" if moved > 1.0 else "【机体没动 —— 这就是卡住】"))
		print("   physics_process=%s  process_mode=%d"
			% [str(p2.is_physics_processing()), p2.process_mode])
		var e2 = main.get("enemy")
		print("   敌机=%s  移动=%s" % [str(e2 != null),
			str(e2 != null and is_instance_valid(e2) and e2.is_physics_processing())])

	print("PROBE_DONE")

	# ---- 第二轮：专门验"结算页按 Esc"这条路径（怀疑的卡死来源）----
	print("")
	print("=== 第二轮：结算页按 Esc ===")
	var e3 = main.get("enemy")
	e3.ifield_hp = 0.0
	e3.take_damage(999999.0, p2, Damage.Type.SABER)
	await _f(60)
	print("7. 再次击坠  Game.phase=%d  main.phase=%d  paused=%s"
		% [Game.phase, main.get("phase"), str(get_tree().paused)])

	await _f(60)   # 等输入锁
	_press(KEY_ESCAPE, true)
	await _f(6)
	_press(KEY_ESCAPE, false)
	await _f(30)
	print("8. 结算页按 Esc  Game.phase=%d  main.phase=%d  paused=%s  menu.visible=%s"
		% [Game.phase, main.get("phase"), str(get_tree().paused),
			str((main.get("menu") as Node).visible)])
	print("   >> %s" % ("暂停已正确清除" if not get_tree().paused else "【仍然处于暂停 —— 就是这里卡死的】"))

	# 从菜单开新一局：Enter 选机体 → Enter 选难度
	_press(KEY_ENTER, true); await _f(6); _press(KEY_ENTER, false); await _f(20)
	_press(KEY_ENTER, true); await _f(6); _press(KEY_ENTER, false); await _f(40)
	var p3 = main.get("player")
	var ok3 := p3 != null and is_instance_valid(p3)
	print("9. 菜单开新局  新机体=%s  paused=%s" % [str(ok3), str(get_tree().paused)])
	if ok3:
		var q0: Vector3 = p3.global_position
		await _f(60)
		var moved3: float = q0.distance_to(p3.global_position)
		print("   60 帧内位移 %.2f m  >> %s"
			% [moved3, "在动，没卡" if moved3 > 1.0 else "【没动 —— 卡住】"])

	print("PROBE_DONE2")
	get_tree().quit(0)


func _f(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _press(key: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = pressed
	Input.parse_input_event(ev)
