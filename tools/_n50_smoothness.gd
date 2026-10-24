extends Node
## N50 动作过渡平滑度探针：把"过渡生硬"变成一个**可读的数**。
##
## ## 为什么要写它（而不是"看着差不多就提交"）
##
## 用户报的是「**每个动作过渡都有点生硬**」。这是主观词，直接改常数就是瞎调。
## 把它翻译成一个物理量：**姿态活动的二阶差分（jerk）**。
##
##   A[i] = Σ_骨 angle( q_骨[i-1], q_骨[i] )   ← 这一帧"全身一共转了多少度"
##   J[i] = A[i] - A[i-1]                       ← 这一帧的"活动量跳变"
##
## 混合充分 ⇒ 切换前后 A 连续变化，J 平稳；混合不足（或零混合硬切）
## ⇒ 切换那一帧出现一个**孤立尖峰**（J 骤大）。
## "生硬"的观感，就是这个尖峰。
##
## ## 三类被测过渡
##
## | 类 | 例子 | 改前的做法 |
## |---|---|---|
## | 进入 | rest → `dash_f` / `shoot` | `play(..., blend=0.12)` |
## | 族内改向 | `dash_f` → `dash_fr`；`fly_f` → `fly_br` | `play(..., blend=0.12, restart)` |
## | **收尾回位** | `shoot` 播完 → 空待机 | ★ **`reset_to_rest()` 瞬间硬切** |
##
## 第三类是重点：五台机体（佩涅罗佩 / 量产牛 / 阿利宙斯常态 / 古斯塔夫 / 梅萨）
## 的 `model_anim_idle` 是空串（用户要求不播飞行待机）⇒ 走的是
## `ModelAnimFSM._enter_idle()` 里那条 `anim.reset_to_rest()` 分支 ——
## `stop()` + `reset_bone_poses()`，**零混合**。
## 而 `shoot` 只有 0.4 s ⇒ 点一下射击，0.4 s 后整机"啪"一声僵回绑定姿态。
##
## ## ⚠️ 时间轴必须稳住：`--fixed-fps 60`
##
## N49 那次探针的播放头读数是**浮动**的（`await process_frame` 的真实 delta
## 取决于引擎跑多快，headless 下不可控）。本探针要量"逐帧变化率"，
## 帧长必须恒定 ⇒ **必须带 `--fixed-fps 60` 跑**：
##
##   godot --headless --fixed-fps 60 --path <工程> res://tools/_n50_smoothness.tscn
##
## 不带这个参数时读数只是一堆噪声，**结论不可用**（脚本会打印告警）。
##
## ## ⚠️ T31：探针必须掐掉引擎自己的 `_physics_process`
##
## 否则出生点 `y == 0` 被判撞海 ⇒ `die()` ⇒ 模型隐藏 ⇒ **动作链永不触发且不报错**。
## 这里既关 `set_physics_process(false)`，也把机体抬到 `y = 600`。

const DT := 1.0 / 60.0
const DEG := 180.0 / PI

## 判"回位"用的：`anim.current` 从这个（非空）变成那个（空）。
const LIVE_NONE := ""

var _last_key := ""


func _ready() -> void:
	print("")
	print("########## N50 动作过渡平滑度：过渡瞬间的姿态活动跳变 ##########")
	print("  判据：A[i] = Σ骨 angle(q[i-1],q[i])；J[i] = A[i]-A[i-1]")
	print("  尖峰比 = 切换后峰窗内 A 峰值 ÷ 切换前基窗内 A 中位数（越接近 1 越顺）")
	print("  ⚠️ 本次 delta = %.4f s（%.0f fps）｜ 必须用 --fixed-fps 60 跑"
		% [DT, 1.0 / DT])
	await _probe(SuitProfile.messer_m01(), "梅萨 M01 · 空待机（动作结束 ⇒ 硬切 rest）")
	await _probe(SuitProfile.xi(), "Ξ 柯西 · 有待机 fly（动作结束 ⇒ 交叉淡入）")
	print("")
	print("VERDICT: N50-SMOOTHNESS-DONE")
	get_tree().quit(0)


func _probe(prof: SuitProfile, label: String) -> void:
	var fb := FlightBody.new()
	fb.profile = prof
	fb.use_placeholder = false
	add_child(fb)
	# ★ T31：掐掉引擎的路，探针逐帧手推，两路同时推没法归因。
	fb.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().physics_frame
	fb.global_position = Vector3(0.0, 600.0, 0.0)   # T31 第二道保险：抬离海面
	if fb.model_anim == null or not fb.model_anim.ready:
		print("  !! %s 动画层没起来，跳过" % label)
		remove_child(fb)
		fb.free()
		return
	var skel: Skeleton3D = fb._model_skel
	print("")
	print("==== %s ====" % label)
	print("  骨 %d ｜ 动作 %d 个 ｜ idle=%s"
		% [skel.get_bone_count(), fb.model_anim.action_names().size(),
			("\"\"" if fb.profile.model_anim_idle == "" else fb.profile.model_anim_idle)])
	var got := await _run(fb, skel)
	_report(got[0], got[1], skel.get_bone_count(), got[2])
	remove_child(fb)
	fb.free()


## 驱动一整条序列并逐帧采样。返回 `[quats, marks, phases]`。
func _run(fb: FlightBody, skel: Skeleton3D) -> Array:
	var quats: Array = []
	var keys: Array = []
	var marks: Array = []
	var phases: Array = []
	_last_key = "\u0000"
	var dirs := _dirs_of(fb)

	# ---- 1 起步（rest，什么都没有）----
	_clear(fb)
	phases.append("① 起步 rest")
	await _adv(fb, skel, quats, keys, marks, 30)

	# ---- 2 进冲刺（进入混合）----
	fb._dash_anim_dir = "f"
	phases.append("② rest → dash_f（进入）")
	await _adv(fb, skel, quats, keys, marks, 30)

	# ---- 3 冲刺族内改向 ----
	fb._dash_anim_dir = "fr"
	phases.append("③ dash_f → dash_fr（族内改向）")
	await _adv(fb, skel, quats, keys, marks, 30)

	# ---- 4 跨族：冲刺 → 平飞 ----
	fb._dash_anim_dir = ""
	fb.translate_dir = dirs["f"]
	phases.append("④ dash_fr → fly_f（跨族）")
	await _adv(fb, skel, quats, keys, marks, 40)

	# ---- 5 平飞族内改向 ----
	fb.translate_dir = dirs["br"]
	phases.append("⑤ fly_f → fly_br（族内改向）")
	await _adv(fb, skel, quats, keys, marks, 40)

	# ---- 6 ★ 出族回位（空待机 ⇒ 硬切 rest）----
	fb.translate_dir = Vector3.ZERO
	phases.append("⑥ fly_br → 回位 ★")
	await _adv(fb, skel, quats, keys, marks, 40)

	# ---- 7 ★ 射击（0.4 s）播完回位 ----
	fb.play_model_action("shoot")
	phases.append("⑦ shoot 起 → 播完回位 ★")
	await _adv(fb, skel, quats, keys, marks, 45)

	# ---- 8 ★ 挥刀（1.5 s）播完回位 ----
	fb.play_model_action("slash")
	phases.append("⑧ slash 起 → 播完回位 ★")
	await _adv(fb, skel, quats, keys, marks, 115)

	# ---- 9 ★ 举盾（1.87 s）播完回位 ----
	fb.play_model_action("shield")
	phases.append("⑨ shield 起 → 播完回位 ★")
	await _adv(fb, skel, quats, keys, marks, 135)

	# ---- 10 姿态微调进入 ----
	fb.control_input = Vector3(0, 0, 1)
	phases.append("⑩ rest → turn_roll_L（进入）")
	await _adv(fb, skel, quats, keys, marks, 40)

	# ---- 11 ★ 松舵回位 ----
	fb.control_input = Vector3.ZERO
	phases.append("⑪ turn_roll_L → 回位 ★")
	await _adv(fb, skel, quats, keys, marks, 40)

	# ---- 12 收尾静置 ----
	phases.append("⑫ 静置")
	await _adv(fb, skel, quats, keys, marks, 30)

	return [quats, marks, phases]


## 推进 `n` 帧：每帧走**生产路径**（`_tick_model_anim` = set_form/set_dash/set_fly_dir/
## set_turn/tick 五件事，顺序有意义），给引擎一帧让它推播放头，然后采样全骨姿态。
func _adv(fb: FlightBody, skel: Skeleton3D, quats: Array, keys: Array,
		marks: Array, n: int) -> void:
	for k in n:
		fb._tick_model_anim(DT)
		await get_tree().process_frame
		quats.append(_q_of(skel))
		var key := "%s|%s|%s" % [fb.model_fsm.state_name(), fb.model_fsm.current_action(),
			fb.model_anim.current]
		keys.append(key)
		if key != _last_key:
			marks.append([quats.size() - 1, _last_key, key])
			_last_key = key


func _q_of(skel: Skeleton3D) -> PackedFloat32Array:
	var n := skel.get_bone_count()
	var out := PackedFloat32Array()
	out.resize(n * 4)
	for i in n:
		var q := skel.get_bone_pose_rotation(i)
		out[i * 4] = q.x
		out[i * 4 + 1] = q.y
		out[i * 4 + 2] = q.z
		out[i * 4 + 3] = q.w
	return out


func _clear(fb: FlightBody) -> void:
	fb._dash_anim_dir = ""
	fb.translate_dir = Vector3.ZERO
	fb.control_input = Vector3.ZERO


## 机体自身基向量下的八向（世界坐标）。不写死世界轴（同 N49 探针的理由）。
func _dirs_of(fb: FlightBody) -> Dictionary:
	var b := fb.global_transform.basis
	var f := -b.z.normalized()
	var r := b.x.normalized()
	var fh := Vector3(f.x, 0.0, f.z).normalized()
	var rh := Vector3(r.x, 0.0, r.z).normalized()
	return {
		"f": fh, "b": -fh, "r": rh, "l": -rh,
		"fr": (fh + rh).normalized(), "fl": (fh - rh).normalized(),
		"br": (fh - rh) * -1.0, "bl": (fh + rh) * -1.0,
	}


# ============================================================ 指标

func _report(quats: Array, marks: Array, nb: int, phases: Array) -> void:
	var n := quats.size()
	if n < 5:
		print("  !! 采样为空")
		return
	# A[i] = 全骨帧间转角总和（度）
	var A := PackedFloat32Array()
	A.resize(n)
	for i in range(1, n):
		var a: PackedFloat32Array = quats[i - 1]
		var b: PackedFloat32Array = quats[i]
		var s := 0.0
		for j in nb:
			var q1 := Quaternion(a[j * 4], a[j * 4 + 1], a[j * 4 + 2], a[j * 4 + 3])
			var q2 := Quaternion(b[j * 4], b[j * 4 + 1], b[j * 4 + 2], b[j * 4 + 3])
			s += q1.angle_to(q2) * DEG
		A[i] = s
	# 静止帧（模型没在动）的 A ≈ 0 ⇒ 用"活动帧"的中位数当基准，否则除零。
	var act: Array = []
	for i in range(1, n):
		if A[i] > 1e-4:
			act.append(A[i])
	act.sort()
	var med := 0.0
	if not act.is_empty():
		med = act[act.size() / 2]
	print("  采样 %d 帧（%.2f s）｜ 活动帧 %d ｜ A 中位数 %.3f°" % [n, n * DT, act.size(), med])

	# J[i] = A[i] - A[i-1]
	var J := PackedFloat32Array()
	J.resize(n)
	for i in range(1, n):
		J[i] = A[i] - A[i - 1]
	var absJ: Array = []
	for i in range(1, n):
		absJ.append(absf(J[i]))
	var sortedJ := absJ.duplicate()
	sortedJ.sort()
	var jmax: float = sortedJ[-1] if not sortedJ.is_empty() else 0.0
	var p95: float = sortedJ[int(float(sortedJ.size()) * 0.95)] if not sortedJ.is_empty() else 0.0
	print("  全局 |J| 最大 %.3f ｜ p95 %.3f ｜ 均值 %.4f"
		% [jmax, p95, _mean(absJ)])

	print("")
	print("  %-4s %-6s %-34s %9s %9s %9s %9s"
		% ["#", "帧", "切换", "基窗A", "峰窗A", "尖峰比", "J@切换"])
	print("  " + "-".repeat(86))
	var worst := 0.0
	var worst_i := -1
	for mi in marks.size():
		var m: Array = marks[mi]
		var f: int = m[0]
		if f <= 0:
			continue
		var lo0: int = maxi(1, f - 3)
		var hi0: int = f + 18
		var peak := 0.0
		for i in range(lo0, mini(n, hi0)):
			peak = maxf(peak, A[i])
		var base := 0.0
		var bl: Array = []
		for i in range(maxi(1, f - 34), maxi(1, f - 3)):
			if A[i] > 1e-4:
				bl.append(A[i])
		bl.sort()
		if not bl.is_empty():
			base = bl[bl.size() / 2]
		elif med > 0.0:
			base = med
		var ratio := 0.0 if base <= 1e-6 else (peak / base)
		var to_rest := str(m[2]).ends_with("|" + LIVE_NONE) and not str(m[1]).ends_with("|" + LIVE_NONE)
		var tag := " ← ★回位硬切" if to_rest else ""
		print("  %-4d %-6d %-34s %9.3f %9.3f %9.2f %9.3f%s"
			% [mi + 1, f, ("%s → %s" % [m[1], m[2]]).substr(0, 33), base, peak, ratio, J[f], tag])
		if to_rest and ratio > worst:
			worst = ratio
			worst_i = mi + 1
	print("")
	print("  ★ 回位类最差尖峰比 = %.2f（第 %d 次切换）" % [worst, worst_i])

	# ★ 定位 |J| 前 5 大帧，并标出它离**最近的切换帧**有多少帧。
	#   用途：把"过渡硬切"与"动作本身的急起/急停"分开 —— 只有后者
	#   不属于"过渡生硬"，也不该算进本轮的账单。
	var mf: Array = []
	for m in marks:
		mf.append(int(m[0]))
	print("")
	print("  |J| 前 5 大帧（看它是不是落在切换帧上）：")
	var used := {}
	for _k in 5:
		var bi := -1
		var bv := -1.0
		for i in range(1, n):
			if used.has(i):
				continue
			if absf(J[i]) > bv:
				bv = absf(J[i])
				bi = i
		if bi < 0:
			break
		used[bi] = true
		var near := 99999
		for f2 in mf:
			near = mini(near, absi(int(f2) - bi))
		print("    帧 %-5d |J| = %8.3f ｜ 离最近切换帧 %s 帧%s"
			% [bi, bv, str(near), "   ← 就是切换帧" if near == 0 else ""])
	print("  SUMMARY: frames=%d |J|max=%.3f p95=%.3f rest_peak_ratio=%.2f"
		% [n, jmax, p95, worst])


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()
