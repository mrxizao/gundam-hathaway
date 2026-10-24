extends Node
## 量"敌方 AI 的进攻欲望"。
##
## ## 跑法（**必须带 `--fixed-fps`**，否则 60 秒模拟要等满 60 秒挂钟）
## ```
## godot --headless --fixed-fps 60 --path C:\Users\MSIPC\Documents\gundam \
##     res://tools/probe_aggression.tscn [每个场景的模拟秒数，默认 60]
## ```
##
## ## 为什么需要这个探针
## "进攻欲望"在这台 AI 上**没有对应变量** —— 它就是"一场战斗里处于 ATTACK 的时间占比"。
## 没有可量的定义，「再强 30%」就只是一句话：改完既不知道强没强，也不知道强了多少。
##
## ## 怎么量
## 和 `probe_ttk` 同一套机制：**两个真 `BanditAI` 互为目标**。
## 用真机而不是手写一个"简易驾驶员"当代理，是为了走真实代码路径
## （提前量解算 / 换弹 / 丢枪 / 避地全在）—— `probe_ttk` 的注释里记着这条教训：
## 手写的代理整场 0 开火，量出来的东西和游戏无关。
##
## ⚠️ **为什么要跑三个初始态势**：只给一个"双方镜像对头"的初始条件时，
## 两台机的状态机会**永远同步**（状态迁移只看距离/角度/是否被威胁，全是对称量），
## 实测两列数字会一模一样 —— 那等于只量了一条确定性轨迹，太单薄。
## 三个不同距离与高度差的态势各跑一遍再取均值，才有一点统计意义。
##
## ⚠️ **判读方式**：这是 **AI 对 AI**，双方都在机动躲闪，所以绝对值天然偏低。
## 判据是**同一套场景改前 / 改后的比值**，不是绝对值。

const DEFAULT_SECONDS := 60.0

## 三个初始态势：(佩涅罗佩位置, 柯西位置)。刻意不做镜像 —— 见文件头的说明。
const SCENARIOS := [
	[Vector3(0.0, 3200.0, -1800.0), Vector3(0.0, 3200.0, 1800.0)],
	[Vector3(-2400.0, 3000.0, -600.0), Vector3(2400.0, 3400.0, 600.0)],
	[Vector3(900.0, 2600.0, -2600.0), Vector3(-900.0, 3800.0, 2600.0)],
]


func _ready() -> void:
	var seconds := DEFAULT_SECONDS
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seconds = maxf(float(args[0]), 1.0)

	var arena := Node3D.new()
	arena.name = "Arena"
	add_child(arena)
	await _f(2)

	print("每个难度跑 %d 个初始态势 × %.0f s（60 Hz 物理帧计数）" % [SCENARIOS.size(), seconds])
	print("")
	print("难度 | ATTACK%% 均值 | 躲+脱离%% 均值 | 平均交战距离 | 样本帧")
	print("-----|--------------|---------------|--------------|--------")
	var total := 0.0
	var total_n := 0
	for level: int in [Difficulty.Level.EASY, Difficulty.Level.NORMAL, Difficulty.Level.HARD]:
		var r := await _run(arena, level, seconds)
		total += r[0] * float(r[2])
		total_n += int(r[2])
	print("")
	print("**全部难度 ATTACK 占比均值 = %.1f%%**（%d 帧）" % [total / maxf(float(total_n), 1.0), total_n])
	print("PROBE_DONE")
	get_tree().quit(0)


## 返回 [ATTACK% 均值, 躲+脱离% 均值, 帧数, 平均距离]
func _run(arena: Node3D, level: int, seconds: float) -> Array:
	var diff := Difficulty.make(level)
	var atk_sum := 0.0
	var esc_sum := 0.0
	var dist_sum := 0.0
	var n := 0
	var dist_frames := 0

	for sc: Array in SCENARIOS:
		Game.reset()
		var c := Node3D.new()
		arena.add_child(c)

		var a := _mk(c, arena, SuitProfile.penelope(), diff, sc[0])
		var b := _mk(c, arena, SuitProfile.xi(), diff, sc[1])
		a.target_override = b
		b.target_override = a
		a.look_at(b.global_position, Vector3.UP)
		a.fm.align_velocity(a.forward())
		b.look_at(a.global_position, Vector3.UP)
		b.fm.align_velocity(b.forward())
		Game.mark_player(b)

		# 四态各自计帧：[SEEK, ATTACK, EVADE, EXTEND]
		var ca := [0, 0, 0, 0]
		var cb := [0, 0, 0, 0]
		var m := 0
		for i in int(seconds * 60.0):
			await _f(1)
			if not (a.alive and b.alive):
				break
			ca[a.state] += 1
			cb[b.state] += 1
			dist_sum += a.global_position.distance_to(b.global_position)
			dist_frames += 1
			m += 1

		if m > 0:
			# 两台机各算一个样本：同一态势下左边那台与右边那台是两条不同的轨迹
			for counts: Array in [ca, cb]:
				atk_sum += 100.0 * float(counts[BanditAI.State.ATTACK])
				esc_sum += 100.0 * float(counts[BanditAI.State.EVADE] + counts[BanditAI.State.EXTEND])
				n += m

		c.free()
		await _f(2)

	if n <= 0:
		print("%-4s | 无样本" % diff.name_cn)
		return [0.0, 0.0, 0.0, 0.0]

	var frames := float(n)
	var atk := atk_sum / frames
	var esc := esc_sum / frames
	var dist := dist_sum / maxf(float(dist_frames), 1.0)
	print("%-4s | %11.1f%% | %12.1f%% | %11.0f m | %d"
		% [diff.name_cn, atk, esc, dist, n])
	return [atk, esc, frames, dist]


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


func _f(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
