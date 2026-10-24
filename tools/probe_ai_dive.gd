extends Node
## 诊断探针：跑一组"敌机可能扎海"的场景，逐个报告最低高度与死因。
## 跑法：godot --headless --path <工程> res://tools/probe_ai_dive.tscn
##
## 用途：定位"柯西自己撞海自爆"这类问题的真实触发条件。
## 只靠猜会修错地方 —— 这一条就是吃过亏才写的。

const SCENARIOS := [
	{"name": "高空陡俯冲 / 玩家 120m", "alt": 2600.0, "pitch": -55.0, "speed": 600.0,
		"dist": 2500.0, "player_alt": 120.0, "lock_player": false},
	{"name": "中空俯冲 / 玩家 120m", "alt": 1500.0, "pitch": -35.0, "speed": 520.0,
		"dist": 2500.0, "player_alt": 120.0, "lock_player": false},
	{"name": "贴海平飞 / 玩家 120m", "alt": 320.0, "pitch": -6.0, "speed": 630.0,
		"dist": 2500.0, "player_alt": 120.0, "lock_player": false},
	{"name": "近距离锁定→军刀突进", "alt": 500.0, "pitch": 0.0, "speed": 500.0,
		"dist": 420.0, "player_alt": 150.0, "lock_player": true},
	{"name": "被玩家锁定→EVADE（低空）", "alt": 900.0, "pitch": -10.0, "speed": 560.0,
		"dist": 2000.0, "player_alt": 150.0, "lock_player": true},
	{"name": "玩家贴着海面 60m", "alt": 1600.0, "pitch": -25.0, "speed": 630.0,
		"dist": 2200.0, "player_alt": 60.0, "lock_player": false},
	{"name": "军刀突进 / 玩家 60m", "alt": 420.0, "pitch": 0.0, "speed": 520.0,
		"dist": 430.0, "player_alt": 60.0, "lock_player": true},
	{"name": "军刀突进 / 玩家 40m", "alt": 300.0, "pitch": -8.0, "speed": 560.0,
		"dist": 480.0, "player_alt": 40.0, "lock_player": true},
	{"name": "军刀突进 / 玩家 35m 更近", "alt": 200.0, "pitch": -12.0, "speed": 600.0,
		"dist": 300.0, "player_alt": 35.0, "lock_player": true},
	{"name": "低空缠斗 / 玩家 35m", "alt": 700.0, "pitch": -30.0, "speed": 630.0,
		"dist": 600.0, "player_alt": 35.0, "lock_player": true},
]


func _ready() -> void:
	var main := Node3D.new()
	main.name = "Arena"
	add_child(main)
	await _f(2)

	print("%-26s | 最低高度 | 结局" % "场景")
	print("---------------------------|----------|------")
	for sc: Dictionary in SCENARIOS:
		await _run(main, sc)
	print("PROBE_DONE")
	get_tree().quit(0)


func _run(arena: Node3D, sc: Dictionary) -> void:
	Game.reset()
	var c := Node3D.new()
	arena.add_child(c)

	# 玩家：低空诱饵
	var me := FlightBody.new()
	me.team = 0
	me.is_player = true
	me.profile = SuitProfile.penelope()
	me.projectile_container = c
	c.add_child(me)
	me.global_position = Vector3(0, float(sc["player_alt"]), -float(sc["dist"]))
	me.fm.speed = 300.0
	me.fm.align_velocity(me.forward())
	Game.mark_player(me)

	var foe := BanditAI.new()
	foe.team = 1
	foe.profile = SuitProfile.xi()
	foe.difficulty = Difficulty.make(Difficulty.Level.HARD)   # 630 m/s
	foe.projectile_container = c
	c.add_child(foe)
	foe.global_position = Vector3(0, float(sc["alt"]), 0)
	var a := deg_to_rad(float(sc["pitch"]))
	foe.look_at(foe.global_position + Vector3(0, sin(a), -cos(a)), Vector3.UP)
	foe.fm.speed = float(sc["speed"])
	foe.fm.throttle = 1.0
	foe.fm.align_velocity(foe.forward())

	var me_lock := LockOnSystem.new()
	arena.add_child(me_lock)
	me_lock.setup(me)
	me_lock.lock_time = 0.05
	Game.register_lock(me, me_lock)
	me.set("lock", me_lock)
	var foe_lock := LockOnSystem.new()
	arena.add_child(foe_lock)
	foe_lock.setup(foe)
	foe_lock.lock_time = 0.05
	Game.register_lock(foe, foe_lock)
	foe.lock = foe_lock

	var min_alt: float = foe.global_position.y
	var saber_used := false
	for i in 720:
		await _f(1)
		if not foe.alive:
			break
		min_alt = minf(min_alt, foe.global_position.y)
		if foe.saber_active():
			saber_used = true

	var ending := "存活"
	if not foe.alive:
		ending = "坠毁"
	print("%-26s | %8.0f | %s%s" % [sc["name"], min_alt, ending,
		"（用过军刀突进）" if saber_used else ""])

	me_lock.free()
	foe_lock.free()
	c.free()
	await _f(2)


func _f(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
