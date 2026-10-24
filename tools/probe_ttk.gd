extends Node
## 实测一场 1v1 要打多久。
##
## 跑法：godot --headless --path <工程> res://tools/probe_ttk.tscn
##
## ## 为什么用"两个 AI 对打"
## 第一版是手写一个"简易驾驶员"当普通玩家的代理，结果它整场 0 开火：
## 手写的瞄准/开火/换弹逻辑绕过了真实代码路径，测出来的时长毫无意义。
## 改成让**两个真正的 BanditAI 互相打**（靠 `target_override` 指定对手）——
## 这样用的就是真实的提前量解算、真实的换弹、真实的躲避，
## 量出来的是"双方都打得准"的**下限**。真人只会更慢，不会更快。
##
## ## 判读
## 目标 4-6 分钟 = 240-360 秒。如果连 AI 对打都打不到，那这个目标**一定**没达成。

const TIME_LIMIT := 600.0


func _ready() -> void:
	var arena := Node3D.new()
	arena.name = "Arena"
	add_child(arena)
	await _f(2)

	print("难度 | 用时 | 结果 | 剩余耐久")
	print("-----|------|------|------")
	for level: int in [Difficulty.Level.EASY, Difficulty.Level.NORMAL, Difficulty.Level.HARD]:
		await _run(arena, level)
	print("PROBE_DONE")
	get_tree().quit(0)


func _run(arena: Node3D, level: int) -> void:
	Game.reset()
	var c := Node3D.new()
	arena.add_child(c)
	var diff := Difficulty.make(level)

	# 双方都是真 AI：一台佩涅罗佩、一台柯西，互为目标
	var a := _mk(c, arena, SuitProfile.penelope(), diff, Vector3(0, 3200, -1800))
	var b := _mk(c, arena, SuitProfile.xi(), diff, Vector3(0, 3200, 1800))
	a.target_override = b
	b.target_override = a
	a.look_at(b.global_position, Vector3.UP)
	a.fm.align_velocity(a.forward())
	b.look_at(a.global_position, Vector3.UP)
	b.fm.align_velocity(b.forward())
	# 只需要一个"玩家位"让 Game 的世界判定有东西可算；这里指给 b
	Game.mark_player(b)

	var t := 0.0
	while t < TIME_LIMIT and a.alive and b.alive:
		await _f(1)
		t += 1.0 / 60.0

	var outcome := "和局（到时限）"
	if not a.alive and not b.alive:
		outcome = "同归于尽"
	elif not a.alive:
		outcome = "佩涅罗佩阵亡"
	elif not b.alive:
		outcome = "柯西阵亡"
	print("%-4s | %s | %s | 佩涅罗佩 %.0f/%.0f · 柯西 %.0f/%.0f"
		% [diff.name_cn, _fmt(t), outcome,
			a.hp + a.ifield_hp, a.max_hp + a.ifield_max,
			b.hp + b.ifield_hp, b.max_hp + b.ifield_max])

	c.free()
	await _f(2)


func _mk(c: Node3D, arena: Node3D, prof: SuitProfile, diff: Difficulty, pos: Vector3) -> BanditAI:
	var u := BanditAI.new()
	u.team = 0
	u.profile = prof
	u.difficulty = diff
	u.projectile_container = c
	c.add_child(u)
	u.global_position = pos
	u.fm.speed = 400.0
	var lk := LockOnSystem.new()
	arena.add_child(lk)
	lk.setup(u)
	Game.register_lock(u, lk)
	u.lock = lk
	return u


func _fmt(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]


func _f(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
