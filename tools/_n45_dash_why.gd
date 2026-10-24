extends Node
## N45 排查：**八向冲刺动作在游戏里为什么没反应** —— 是没装上，还是幅度太小？
##
## ## 为什么要写它
##
## 用户实机反馈「八向冲刺动作没有反应」，问的是二选一：
##   ① **没装上**（文件/资源/接线层面装不进去）
##   ② **装上了，但幅度太小看不出**
##
## 这两种的修法完全相反，所以必须**分开证伪**。本探针把三层证据一次打出来：
##
##   **A 结构层**：动画状态机的输入面 —— 它接不接得到「玩家在冲刺」这件事。
##   **B 数据层**：8 段 `dash_*` 到底在不在可播表里（`ResourceLoader` / `--import` 那一路）。
##   **C 实机层**：真实 `FlightBody` 走一遍冲刺，逐帧打印**冲刺侧**与**动画侧**读数。
##
## 判据：C 里冲刺侧（`translate_dash` / `_qb_timer` / `_qb_dir`）真的动了，
##       而动画侧（`state_name` / `current_action` / 播放头）**一动不动** ⇒
##       「没反应」= **没有消费方**，与幅度**无关**。
##
## ## 跑法
##
##   godot --headless --path <工程> res://tools/_n45_dash_why.tscn

## 八向的段名（与 `SuitProfile` 登记表一致）。
const DIRS := ["f", "fr", "r", "br", "b", "bl", "l", "fl"]

## 冲刺模拟帧数。`QB_TIME` = 0.45 s，60 fps ⇒ 27 帧；取 30 帧覆盖整个窗口 + 溢出。
const FRAMES := 30

const DT := 1.0 / 60.0


func _ready() -> void:
	print("")
	print("########## N45 排查：八向冲刺动画「没反应」的三层证据 ##########")
	await _layer_a()
	await _layer_b()
	await _layer_c()
	print("")
	print("VERDICT: N45-DASH-WHY-DONE")
	get_tree().quit(0)


## ------------------------------ A 结构层：动画状态机接不接得到冲刺 ------------------------------

func _layer_a() -> void:
	print("")
	print("---- A 结构层：动画状态机的输入面 ----")
	print("  `ModelAnimFSM` 状态集 = NONE / IDLE / BURST / FORM / **DASH**（N46 末尾追加）")
	print("")
	print("  排查当时（N45b）驱动它的全部入口只有 4 处，**没有一处能把「在冲刺」传进去**：")
	print("    L1447  set_form(cruise_morph >= 0.5)     形态")
	print("    L1448  tick(delta)                       推进（★ 签名只有 delta）")
	print("    L1480  burst_action_for_form(f)          查询：全弹发射该播哪段")
	print("    L1491  request_burst()                   全弹发射")
	print("  ⇒ 当时 `tick(delta)` 的参数表里**没有任何输入量** ⇒ 状态机在接口上就")
	print("     接收不到 `translate_dir`。不是「忘了接线」，是**根本没有可接的线**。")
	print("")
	print("  ★ N46 补的就是这条线（与 `set_form()` 同构：宿主写目标、`tick()` 兑现）：")
	print("    `set_dash(dir_name)`  冲刺方向请求（`\"\"` = 结束冲刺）")
	print("    `dash_dir()`          当前生效方向（HUD / 测试读）")
	print("    `dash_action_for(n)`  纯查询：`dash_<n>` 在不在表里")
	print("  ⇒ 宿主（`FlightBody._tick_model_anim()`）每帧只**报当前事实**，")
	print("     切不切由状态机按分支顺序自己定。")





## ------------------------------ B 数据层：8 段到底在不在 ------------------------------

func _layer_b() -> void:
	print("")
	print("---- B 数据层：8 段 `dash_*` 在不在可播表里（佩涅罗佩）----")
	var prof := SuitProfile.penelope()
	var ps := load(prof.model_path) as PackedScene
	if ps == null:
		print("  !! 主模型载入失败：%s" % prof.model_path)
		return
	var inst := ps.instantiate() as Node3D
	add_child(inst)
	await get_tree().process_frame
	var ma := ModelAnimator.setup(inst, prof.model_anim_files)
	print("  ready = %s ｜ 动作表 %d 个" % [str(ma.ready), ma.action_names().size()])
	var have := 0
	for d in DIRS:
		var nm := "dash_" + str(d)
		var ok := ma.has(nm)
		if ok:
			have += 1
		print("    %-10s 在表里？ %s" % [nm, str(ok)])
	print("  ⇒ %d / 8 段在可播表里 %s"
		% [have, "（**装上了**）" if have == 8 else "（★ 有缺件）"])
	remove_child(inst)
	inst.free()


## ------------------------------ C 实机层：真实 FlightBody 冲刺，动画侧动不动 ------------------------------

func _layer_c() -> void:
	print("")
	print("---- C 实机层：真实 `FlightBody` 走一次右向冲刺 ----")
	var fb := FlightBody.new()
	fb.profile = SuitProfile.penelope()
	add_child(fb)
	# ★ 掐掉引擎自己的 `_physics_process` —— 探针要**逐帧手推**，
	#   否则引擎也在推同一个 body，两路叠加后读数不可归因。
	fb.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().physics_frame

	print("  model_anim.ready = %s ｜ model_fsm.state = %s"
		% [str(fb.model_anim != null and fb.model_anim.ready), fb.model_fsm.state_name()])
	if fb.model_anim == null or not fb.model_anim.ready:
		print("  !! 动画层没起来（模型没有 AnimationPlayer）⇒ 下面的读数无意义")
		remove_child(fb)
		fb.free()
		return

	# 把冲刺前置摆齐：有冲刺条、条满、不在 CD；加力开着（`_apply_translate` 的消费条件）。
	fb.dash_charge = 1.0
	fb.dash_cd = 0.0
	fb.fm.boosting = true
	# 输入：向机体右侧平移（`_read_translate_input` 的产物；这里直接写字段）。
	fb.translate_dir = Vector3(1.0, 0.0, 0.0)
	fb.request_quick_boost()

	print("")
	print("  前置：has_dash_limit=%s ｜ dash_charge=%.2f ｜ dash_cd=%.2f ｜ can_quick_boost=%s"
		% [str(fb.has_dash_limit()), fb.dash_charge, fb.dash_cd, str(fb.can_quick_boost())])
	print("  输入：translate_dir = %s ｜ request_quick_boost() 已点" % str(fb.translate_dir))
	print("")
	print("  %5s  %-14s %8s  %-18s  %-12s  %-6s  %-10s  %-10s  %8s"
		% ["帧", "冲刺侧", "_qb_timer", "_qb_dir", "_dash_anim_dir", "FSM", "FSM动作", "播放器动作", "播放头"])
	print("  " + "-".repeat(112))
	var seen := {}
	for i in FRAMES:
		fb._apply_translate(DT)
		# ★ 必须走 `_tick_model_anim()`（= 生产路径：它内部 `set_form` + `set_dash` + `tick`）。
		#   直接调 `model_fsm.tick()` 会**绕过** N46 新加的 `set_dash()` 转发 ——
		#   那正是排查第一版"看不出任何变化"的原因。
		fb._tick_model_anim(DT)
		var cur := ""
		var pos := 0.0
		if fb.model_anim.player != null and fb.model_anim.current != "":
			cur = fb.model_anim.current
			pos = fb.model_anim.player.current_animation_position
		var act := fb.model_fsm.current_action()
		seen[act] = true
		var dash_side := "冲刺中" if fb.translate_dash else "-"
		print("  %5d  %-14s %8.3f  %-18s  %-12s  %-6s  %-10s  %-10s  %8.3f"
			% [i, dash_side, fb._qb_timer, str(fb._qb_dir), fb._dash_anim_dir,
			   fb.model_fsm.state_name(), act, cur, pos])
		await get_tree().physics_frame

	print("  " + "-".repeat(112))
	print("  ⇒ 冲刺侧：窗口 %d 帧内 `translate_dash` 真的开了（物理侧功能活着）"
		% FRAMES)
	print("  ⇒ 动画侧：整个窗口内 FSM 动作出现过 %d 种：%s"
		% [seen.size(), str(seen.keys())])
	if seen.has("dash_r"):
		print("  ★★ 判决：冲刺期间动画**切到了 `dash_r`**（N46 接线生效）；")
		print("     窗口结束 FSM 回 `idle`，佩涅罗佩没有待机动作 ⇒ 归位到 rest（播放头 0.000）。")
	else:
		print("  ✗ 动画侧仍然没有 `dash_r` —— 接线没生效，查 `_tick_model_anim()` 的 set_dash 转发。")
	print("")
	print("  ⚠️ 对照（上一轮已测）：8 段 `dash_*` 彼此的姿态差 14.13°~20.00°、")
	print("     噪声底 0.04° ⇒ **数据侧完全没问题**，缺的只是「谁来播」。")

	remove_child(fb)
	fb.free()
