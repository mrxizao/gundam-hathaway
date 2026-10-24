extends Node
## N46 排查：**柯西「转身结束之后背后飞翼反复抽搐」** —— 用净效应隔离定因。
##
## ## 嫌疑链路（读代码得到，本探针负责证伪）
##
## `_tick_cruise_morph()` 里有一段「左右转身期间把形态压回常态」（轮 34）：
##
##     var want := 1.0 if (fm.boosting and not fm.hovering) else 0.0
##     if _dash_spin_t > 0.0:
##         want = 0.0                                    # ← 窗口内：收
##         secs = minf(secs, DASH_SPIN_STOW_SECONDS)     #   0.15 s（比默认快）
##     cruise_morph = move_toward(cruise_morph, want, rate * delta)
##
## 窗口（`_dash_spin_t` = QB_TIME 0.45 s）一结束，`want` 立刻回到常态逻辑 ⇒ **再展开**
##（柯西 = 走 `form_on`，0.4333 s）。
##
## 而 `_tick_model_anim()` 每帧把 **`cruise_morph >= 0.5`** 喂给状态机当形态：
## 掉过 0.5 ⇒ 播 `form_off`；涨过 0.5 ⇒ 播 `form_on`。⇒ **一次冲刺 = 一收一放两条过渡动作**。
##
## ## 为什么怀疑是 N46 引入的
##
## N46 给状态机加了 `DASH` 态，且**冲刺优先于形态切换**（有意：避免 0.45 s 的冲刺
## 被 0.43 s 的过渡拦腰截断）。副作用是形态切换被**推迟到冲刺窗口结束之后**，
## 于是"放"（0.45 s）与 `form_off`（0.4333 s）在时间上**重叠** —— 两条几乎等长、
## 方向相反的过程叠在一起，正是"反复抽搐"的典型形状。
##
## ## 判据（净效应隔离）
##
## 同一个场景跑两遍，**唯一变量 = N46 的 `set_dash` 转发**：
##   A 接线开（当前代码）
##   B 接线关（每帧强制 `_dash_anim_dir = ""`，等价于 N46 之前）
##
## 两边的 `_history()` 与迁移序列逐条对比 ⇒ 抽搐若只在 A 出现，就是 N46 引入的。
##
## ## 跑法
##
##   godot --headless --path <工程> res://tools/_n46_xi_twitch.tscn

const DT := 1.0 / 60.0
## 预热帧数：让形态爬到巡航（`cruise_morph_seconds` 0.45 s ⇒ 30 帧足够）。
const WARM := 40
## 观察帧数：冲刺窗口 0.45 s + 两条过渡各 0.4333 s ⇒ 3 s 足够看完整条链。
const WATCH := 180


func _ready() -> void:
	print("")
	print("########## N46 排查：柯西「转身后飞翼反复抽搐」 ##########")
	await _run("A 接线开（N46 现状）", true)
	await _run("B 接线关（等价 N46 之前）", false)
	print("")
	print("VERDICT: N46-XI-TWITCH-DONE")
	get_tree().quit(0)


func _run(label: String, wired: bool) -> void:
	print("")
	print("================ %s ================" % label)
	var fb := FlightBody.new()
	fb.profile = SuitProfile.xi()
	fb.use_placeholder = false
	fb.is_player = false
	fb.translate_mode = true
	add_child(fb)
	fb.set_physics_process(false)
	# ★★ 出生点必须抬到高空（本工程的老坑）：默认位置 y=0 就在海面上，
	#   而 `_apply_translate()` 末尾会 `_check_collisions()` ⇒ 判**撞海** ⇒ `die()`
	#   ⇒ `set_model_visible(false)` ⇒ `_start_dash_spin()` 早退 ⇒ 转身整条链不触发。
	#   （症状与"探针拍到的全是空图 / 机体不动"是同一个根因，见 memory。）
	fb.global_position = Vector3(0.0, 600.0, 0.0)
	fb.set_model_visible(true)
	await get_tree().process_frame
	await get_tree().physics_frame

	if fb.model_anim == null or not fb.model_anim.ready:
		print("  !! 动画层没起来（缺 AnimationPlayer）⇒ 本组无意义")
		remove_child(fb)
		fb.free()
		return
	print("  动作表 %d ｜ 有 form_on=%s form_off=%s cruise_idle=%s"
		% [fb.model_anim.action_names().size(), str(fb.model_anim.has("form_on")),
		   str(fb.model_anim.has("form_off")), str(fb.model_anim.has("cruise_idle"))])

	fb.dash_charge = 1.0
	fb.dash_cd = 0.0
	fb.fm.boosting = true
	fb.fm.hovering = false

	# ---- 预热：进巡航形态并稳定 ----
	for _i in WARM:
		fb.global_position = Vector3(0.0, 600.0, 0.0)
		fb._apply_translate(DT)
		fb._tick_cruise_morph(DT)
		fb._tick_model_anim(DT)
		await get_tree().physics_frame
	print("  预热后：cruise_morph=%.3f ｜ FSM=%s / form=%s → want=%s ｜ 动作=%s"
		% [fb.cruise_morph, fb.model_fsm.state_name(), fb.model_fsm.form_name(),
		   fb.model_fsm.want_form_name(), fb.model_fsm.current_action()])
	var base_trans := fb.model_fsm.transitions

	# ---- 冲刺（右向）----
	fb.translate_dir = Vector3(1.0, 0.0, 0.0)
	fb.request_quick_boost()
	print("")
	print("  ★ 诊断（冲刺前）：dash_spin_visual=%s ｜ model_visible=%s ｜ dash_spin=%.3f"
		% [str(fb.profile.dash_spin_visual), str(fb.model_visible()), fb.dash_spin])
	print("     basis=%s" % str(fb.global_transform.basis))
	print("")
	print("  %4s  %6s  %6s  %7s  %-6s  %-7s  %-7s  %-10s" % [
			"帧", "morph", "spin_t", "过渡窗", "FSM", "form", "want", "动作"])
	print("  " + "-".repeat(74))
	var seq: Array = []
	var spin_on := false
	for i in WATCH:
		fb.global_position = Vector3(0.0, 600.0, 0.0)
		fb._apply_translate(DT)
		fb._tick_cruise_morph(DT)
		if not wired:
			# ★ 净效应隔离：唯一变量 —— 把 N46 新增的方向转发掐掉。
			fb._dash_anim_dir = ""
		fb._tick_model_anim(DT)
		var act := fb.model_fsm.current_action()
		if seq.is_empty() or str(seq[seq.size() - 1]) != act:
			seq.append(act)
		# 打前 45 帧（覆盖冲刺窗口）+ 之后每 15 帧，免得 180 帧刷屏
		var show := i < 45 or (i % 15 == 0)
		if show:
			print("  %4d  %6.3f  %6.3f  %7s  %-6s  %-7s  %-7s  %-10s" % [
					i, fb.cruise_morph, fb._dash_spin_t,
					"收" if fb._dash_spin_t > 0.0 else "-",
					fb.model_fsm.state_name(), fb.model_fsm.form_name(),
					fb.model_fsm.want_form_name(), act])
			spin_on = spin_on or fb._dash_spin_t > 0.0
		await get_tree().physics_frame

	print("  " + "-".repeat(74))
	print("  ★ 动作序列（去重相邻同名）：")
	print("      %s" % str(seq))
	print("  ★ 迁移次数（冲刺起算）：%d" % (fb.model_fsm.transitions - base_trans))
	var flips := 0
	for k in range(1, seq.size()):
		var a := str(seq[k - 1])
		var b := str(seq[k])
		if (a == "form_on" and b == "form_off") or (a == "form_off" and b == "form_on"):
			flips += 1
	print("  ★ 「来回」次数 = %d  %s" % [flips,
			"（★ 抽搐确认）" if flips >= 2 else "（一次往返，属设计行为）"])

	remove_child(fb)
	fb.free()
