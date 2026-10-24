extends Node

## 临时诊断（不属交付）：`suite_friendly_fire / _projectile` 的**敌机那一发**为什么不掉血。
##
## 复刻套件第 2 节的时序，逐件打印：谁在场上 / 各自在哪 / 队伍 / 有没有板 /
## 弹丸的起点终点 / 3 帧后**每一个单位**的血量变化。
##
## ⚠️ 必须带窗口或用真场景跑（`--script` 模式下 autoload 不实例化 ⇒ 编译不过）。
## ⚠️ 看门狗必须有：`_ready()` 里抛错会静默中断协程、`quit()` 永不到达。

var _log_lines: Array[String] = []


func _say(s: String) -> void:
	_log_lines.append(s)
	print("[ffdiag] " + s)


func _ready() -> void:
	var wd := Timer.new()
	wd.wait_time = 30.0
	wd.one_shot = true
	wd.timeout.connect(_finish)
	add_child(wd)
	wd.start()
	_run()


func _finish() -> void:
	if not _log_lines.is_empty():
		var f := FileAccess.open("user://_ff_diag.txt", FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(_log_lines) + "\n")
			f.close()
	get_tree().quit()


func _pool(u: Node) -> float:
	var fb := u as FlightBody
	if fb == null:
		return -1.0
	var sum: float = fb.hp + fb.ifield_hp
	if fb.has_method("has_pedal") and fb.has_pedal():
		var board = fb.pedal_owner()
		if board != null and is_instance_valid(board):
			sum += float(board.hp)
	return sum


func _dump_units(tag: String) -> void:
	var i := 0
	for u: Node3D in Game.units:
		if not is_instance_valid(u) or u.is_queued_for_deletion():
			continue
		var fb := u as FlightBody
		if fb == null:
			_say("%s  [%d] %s（不是 FlightBody）pos=%v" % [tag, i, u.name, u.global_position])
			i += 1
			continue
		_say("%s  [%d] %s  cls=%s team=%d pool=%.1f hp=%.1f ifield=%.1f pedal=%s pos=%v" % [
			tag, i, fb.name, fb.get_class(), fb.team, _pool(fb), fb.hp, fb.ifield_hp,
			str(fb.has_pedal()) if fb.has_method("has_pedal") else "?", fb.global_position])
		i += 1


func _run() -> void:
	Game.reset()
	Game.active_suit = SuitProfile.Id.MESSER_M01
	Game.active_side = BattleFormation.Side.MAFTY
	var m := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(m)
	await get_tree().physics_frame
	await get_tree().physics_frame
	m.call("_on_start_match", SuitProfile.Id.MESSER_M01, Difficulty.Level.NORMAL,
		MapDef.Id.PACIFIC, Game.MatchMode.SQUAD, -1)
	for i in 16:
		await get_tree().physics_frame

	_say("弹速 vulcan_speed() = %.1f m/s" % SuitProfile.vulcan_speed())
	_dump_units("开局")

	var player: FlightBody = m.get("player")
	var wing: FlightBody = null
	var foe: FlightBody = null
	for u: Node3D in Game.units:
		if not is_instance_valid(u) or u.is_queued_for_deletion():
			continue
		if not u.has_method("is_alive") or not u.is_alive():
			continue
		var fb := u as FlightBody
		if fb == null or fb == player:
			continue
		if fb.team == player.team and wing == null:
			wing = fb
		elif fb.team != player.team and foe == null:
			foe = fb
	_say("player=%s wing=%s foe=%s" % [str(player), str(wing), str(foe)])
	if player == null or wing == null or foe == null:
		_say("★ 前提不成立，到此为止")
		_finish()
		return

	player.global_position = Vector3(0.0, 3000.0, 0.0)
	wing.global_position = Vector3(150.0, 3000.0, 0.0)
	foe.global_position = Vector3(9000.0, 3000.0, 0.0)
	for fb: FlightBody in [player, wing, foe]:
		fb.set_physics_process(false)
		fb.fm.velocity = Vector3.ZERO
		fb.fm.speed = 0.0
		fb.velocity = Vector3.ZERO
	await get_tree().physics_frame
	_say("摆位后：player=%v wing=%v foe=%v" % [
		player.global_position, wing.global_position, foe.global_position])

	# ---- 与套件**逐字相同**的那一发 ----
	var before_foe := _pool(foe)
	var before_player := _pool(player)
	var before_wing := _pool(wing)
	var dir := (foe.global_position - player.global_position).normalized()
	var from := foe.global_position - dir * 8.0
	_say("发射：from=%v dir=%v shooter=%s" % [from, dir, player.name])
	var pellet := Projectile.vulcan(foe.get_parent(), from, dir, player, 50.0)
	_say("弹丸建出：%s pos=%s" % [
		str(pellet), str(pellet.global_position) if pellet != null else "null"])
	for i in 3:
		await get_tree().physics_frame
		_say("  帧 %d：弹丸存活=%s pos=%s | foe pool=%.2f" % [
			i + 1,
			("true" if (pellet != null and is_instance_valid(pellet)) else "false"),
			(str(pellet.global_position) if (pellet != null and is_instance_valid(pellet)) else "-"),
			_pool(foe)])

	_say("Δ player=%.3f  wing=%.3f  foe=%.3f" % [
		_pool(player) - before_player, _pool(wing) - before_wing, _pool(foe) - before_foe])

	# ---- 对照：同一发弹，但**起点退到 100 m 外** ----
	# 100 m 意味着一帧（56 m）**到不了**靶机 ⇒ 靶机会落在某一帧扫掠区间的**中段**
	# 而不是"第一帧就整段越过它"。这一条把"速度太快隧穿"与"测试摆位太近"分开。
	await get_tree().physics_frame
	var b2 := _pool(foe)
	var from2 := foe.global_position - dir * 100.0
	_say("对照发（100 m 外）：from=%v" % from2)
	var p2 := Projectile.vulcan(foe.get_parent(), from2, dir, player, 50.0)
	for i in 3:
		await get_tree().physics_frame
		_say("  帧 %d：存活=%s pos=%s | foe.pool=%.2f" % [
			i + 1,
			("true" if (p2 != null and is_instance_valid(p2)) else "false"),
			(str(p2.global_position) if (p2 != null and is_instance_valid(p2)) else "-"),
			_pool(foe)])
	_say("对照发 Δfoe = %.3f" % (_pool(foe) - b2))
	_finish()
