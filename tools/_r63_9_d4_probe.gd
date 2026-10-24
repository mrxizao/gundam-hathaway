extends Node
## ★63-9 · D4 侦查探针（**只读**，不改任何产品源码）。
##
## ## 它要回答的唯一问题
## `main._on_enemy_destroyed()` 里那行 `_finish_round()` **是不是无条件结束这一局**？
##
## 这决定了 D4「敌方坠毁提醒」的落点：
##   · 若小队战"掉一架就结束" ⇒ `_on_enemy_destroyed` 这条路上**永远是终结性击毁**
##     ⇒ 提醒必须放在 `_finish_round()` **之前**还是**之后**，结论完全不同；
##   · 若不是 ⇒ 非终结性击毁会出现在这条路上，放哪都行（但放前面更自然）。
##
## ## 为什么必须实测
## 只读源码只能读到"这一行接上去了、那一行调了 `_finish_round()`"，
## 读不到"那一刻 `Game.phase` 到底是什么"。而 `Game.notify_destroyed()`（先跑）
## 与 `destroyed.emit()`（后跑）在**同一帧**里前后脚，中间的 `_evaluate_end()`
## 可能已经把 phase 翻成 WIN —— 这正是 D4「与结算冲突」的根因所在。
##
## 跑法：
##   godot --headless --path <工程> res://tools/_r63_9_d4_probe.tscn

func _ready() -> void:
	# 探针是场景 root ⇒ 默认比子节点 main **先跑**（本工程栽过，见 notes/09 的六坑之一）
	process_priority = 1000
	var tree := get_tree()
	await tree.process_frame

	await _squad(tree)

	await _challenge(tree)

	print("D4_PROBE_END")
	tree.quit()


func _squad(tree: SceneTree) -> void:
	print("==== SQUAD ====")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await tree.process_frame
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.EASY,
		MapDef.Id.PACIFIC, Game.MatchMode.SQUAD, -1)
	await tree.process_frame
	await tree.physics_frame
	main.call("_start_fight")
	await tree.physics_frame
	var p = main.get("player")
	var hud = main.get("hud")
	var foes: Array = Game.live_hostiles_of(p)
	print("  开局：敌机 %d 台 · Game.phase=%d · main.phase=%d"
		% [foes.size(), Game.phase, main.get("phase")])

	var victim = foes[0]
	var vname: String = victim.display_name
	victim.destroy(p)
	print("  击坠 1 台（%s）**同一帧**：Game.phase=%d · main.phase=%d · 残留敌机=%d"
		% [vname, Game.phase, main.get("phase"), Game.live_hostiles_of(p).size()])
	# 再等几帧，看 `_finish_round()` 有没有在别处补刀
	for i in 4:
		await tree.physics_frame
	print("  4 帧之后：Game.phase=%d · main.phase=%d · 残留敌机=%d"
		% [Game.phase, main.get("phase"), Game.live_hostiles_of(p).size()])
	print("  hud._notices = %s" % str(hud.get("_notices")))

	main.free()
	await tree.process_frame
	Game.reset()
	await tree.process_frame


func _challenge(tree: SceneTree) -> void:
	print("==== CHALLENGE (XI_VS_ARIZEUS) ====")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await tree.process_frame
	Game.active_challenge_id = ChallengeScript.xi_vs_arizeus().id
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.NORMAL,
		-1, Game.MatchMode.CHALLENGE)
	await tree.process_frame
	await tree.physics_frame
	main.call("_start_fight")
	await tree.physics_frame
	var p = main.get("player")
	var hud = main.get("hud")
	var wave: Array = main.get("wave_units")
	print("  第 1 波 %d 台 · Game.challenge_wave=%d · remaining=%d · Game.phase=%d"
		% [wave.size(), Game.challenge_wave, Game.challenge_wave_remaining, Game.phase])

	var victim = wave[0]
	var vname: String = victim.display_name
	victim.destroy(p)
	print("  击坠 1 台（%s）**同一帧**：Game.phase=%d · main.phase=%d · remaining=%d"
		% [vname, Game.phase, main.get("phase"), Game.challenge_wave_remaining])
	for i in 4:
		await tree.physics_frame
	print("  4 帧之后：Game.phase=%d · main.phase=%d · remaining=%d · 敌机=%d"
		% [Game.phase, main.get("phase"), Game.challenge_wave_remaining,
			Game.live_hostiles_of(p).size()])
	print("  hud._notices = %s" % str(hud.get("_notices")))

	# 把第一波剩下的两台也清掉 → 看"最后一架"那一帧的 phase
	for u in wave:
		if is_instance_valid(u) and u.is_alive():
			u.destroy(p)
	print("  清空第 1 波**同一帧**：Game.phase=%d · main.phase=%d · wave=%d"
		% [Game.phase, main.get("phase"), Game.challenge_wave])
	for i in 4:
		await tree.physics_frame
	print("  4 帧之后：Game.phase=%d · main.phase=%d · wave=%d · 敌机=%d"
		% [Game.phase, main.get("phase"), Game.challenge_wave, Game.live_hostiles_of(p).size()])
	print("  hud._notices = %s" % str(hud.get("_notices")))

	main.free()
	await tree.process_frame
	Game.reset()
	await tree.process_frame
