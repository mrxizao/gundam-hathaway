extends Node
## N49 接线实机验证：**五族动作在真实 `FlightBody` 上到底会不会被播**。
##
## ## 为什么必须写它
##
## N45b 的教训（已记进规范 T27）：`model_anim_files` 里登记了 ≠ 运行时会播 ——
## 登记只把动作挂上 `AnimationPlayer`，**不产生任何调用方**。
## 所以「装上了」这件事**单元测试证明不了**，得让真实机体走一遍生产路径
##（`FlightBody._tick_model_anim()`），再把状态机动作名与播放头读出来。
##
## ## 为什么用梅萨 M01 当样本
##
## 三类战斗动作要**走真实触发函数**才作数，于是机体必须同时满足：
##   · `has_saber == true` —— 梅萨 ✓ ／ **古斯塔夫是靶机，`has_saber = false`**
##     （第一版拿它测挥刀，`try_saber()` 在第一条门禁就早退、返回 false，
##      探针只能读到上一段动作 `shield` —— 那是**探针选错样本**，不是接线错）
##   · 有盾（`shield_reduction > 0`）—— 梅萨 ✓
##   · 是 N49 新装的四台之一 —— 梅萨 ✓
##
## ## 被测的五族（都走 `_tick_model_anim()` = 生产路径）
##
## | # | 族 | 宿主给的事实 | 期望动作 |
## |---|---|---|---|
## | ① | 平飞八向 | `translate_dir`（世界方向） | `fly_<dir>` |
## | ② | 姿态微调 | `control_input`（三轴） | `turn_<轴>` |
## | ③ | 优先级 | 两类事实同时给 | 平移族赢（`fly_*`） |
## | ④ | 举盾 | `raise_shield()` | `shield` |
## | ⑤ | 挥刀 | `try_saber()` | `slash` |
## | ⑥ | 射击 / 军刀过渡 | `play_model_action()` | `shoot` / `trans_*` |
##
## ## 判据
##
## 每一族都必须出现**它自己的动作名**；读到 `""`（= 还是 IDLE）就是**没接上**。
## ⚠️ 只看 `state_name()` 不够 —— `idle` 本身是"没错也没对"，必须读到具体动作名。
## ⚠️ 播放头必须 > 0 —— 那是"真的在动"的独立证据（N28 的核心）。
##    读它有个前提：**必须给引擎帧**（`await process_frame`），否则 `AnimationPlayer`
##    的播放头永远停在 0，把"接上了"误读成"没动"（本探针第一版就是这么误报 8 条的）。
##
## ## 跑法
##
##   godot --headless --path <工程> res://tools/_n49_wiring.tscn

const DT := 1.0 / 60.0

## 八向名（与 `FlightBody.DASH_DIR_NAMES` 同序）。
const DIR_NAMES := ["f", "fr", "r", "br", "b", "bl", "l", "fl"]

## 六轴姿态输入 → 期望的 `turn_*` 名。
## 符号照 `player_controller` 的实源码：`.x` 正 = 抬头、`.y` 正 = 左偏航、`.z` 正 = 左滚。
const AXES := {
	"pitch_up": Vector3(1, 0, 0), "pitch_down": Vector3(-1, 0, 0),
	"yaw_L": Vector3(0, 1, 0), "yaw_R": Vector3(0, -1, 0),
	"roll_L": Vector3(0, 0, 1), "roll_R": Vector3(0, 0, -1),
}

var _fails: Array[String] = []


func _ready() -> void:
	print("")
	print("########## N49 接线实机验证：五族动作会不会被播 ##########")
	var fb := await _make_body()
	if fb == null:
		print("VERDICT: N49-WIRING-ABORTED")
		get_tree().quit(3)
		return
	_sanity(fb)
	await _fly_dirs(fb)
	await _turn_axes(fb)
	await _priority(fb)
	await _actions(fb)
	remove_child(fb)
	fb.free()
	print("")
	if _fails.is_empty():
		print("✅ 五族 + 优先级 全部命中，0 处不合格")
		print("VERDICT: N49-WIRING-OK")
		get_tree().quit(0)
	else:
		print("⛔ %d 处不合格：" % _fails.size())
		for f in _fails:
			print("   -", f)
		print("VERDICT: N49-WIRING-FAILED")
		get_tree().quit(3)


## 建一台**已经接线**的机体（梅萨 M01），关掉引擎自己的推帧。
func _make_body() -> FlightBody:
	var fb := FlightBody.new()
	fb.profile = SuitProfile.messer_m01()
	fb.use_placeholder = false
	add_child(fb)
	# ★ 掐掉引擎的 `_physics_process`：探针要逐帧手推，两路同时推没法归因。
	#   （顺带避开 T31：`_physics_process` 里的碰撞检测会把出生点 y=0 判成撞海，
	#     于是模型被隐藏、动作链永不触发且不报错。）
	fb.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().physics_frame
	if fb.model_anim == null or not fb.model_anim.ready:
		print("  !! 动画层没起来（模型没有 AnimationPlayer）⇒ 全套读数无意义")
		remove_child(fb)
		fb.free()
		return null
	return fb


func _sanity(fb: FlightBody) -> void:
	print("")
	print("---- 0 前置：这台机体的动画层 ----")
	print("  profile          = %s" % fb.profile.display_name)
	print("  model_path       = %s" % fb.profile.model_path.get_file())
	print("  model_anim.ready = %s" % str(fb.model_anim.ready))
	print("  动作表 %d 个" % fb.model_anim.action_names().size())
	print("  has_saber        = %s ｜ shield_reduction = %.2f"
		% [str(fb.profile.has_saber), fb.profile.shield_reduction])
	print("  model_anim_idle  = %s（空 = 不播飞行待机，N49 用户指定）"
		% ("\"\"" if fb.profile.model_anim_idle == "" else fb.profile.model_anim_idle))
	if fb.profile.model_anim_idle != "":
		_fails.append("飞行待机没被置空（model_anim_idle = %s）" % fb.profile.model_anim_idle)
	if not fb.profile.has_saber:
		_fails.append("样本没有军刀 ⇒ 挥刀那一条没法测（换机体）")


## 手推一帧生产路径，给引擎一帧让播放头真的走，返回 [FSM 态, 状态机动作, 播放器动作, 播放头]。
func _step(fb: FlightBody) -> Array:
	# ★ 必须走 `_tick_model_anim()` = 生产路径（它内部 set_form / set_dash / set_fly_dir /
	#   set_turn / tick 五件事，顺序有意义）。直接调 `model_fsm.tick()` 会绕过全部转发。
	fb._tick_model_anim(DT)
	# ★★ 给引擎**两帧**。`AnimationPlayer` 的播放头是引擎在 PROCESS_IDLE 里推的，
	#    而 `play_loop(..., restart=true)` 刚起播那一帧位置**必是 0** ——
	#    只等一帧读到的还是 0（本探针第二版就是这么误报的：头部两段读到 0.000、
	#    后面的段才读到 0.007）。这不是接线问题，是**读数的采样时机**问题。
	await get_tree().process_frame
	await get_tree().process_frame
	var cur := ""
	var pos := 0.0
	if fb.model_anim.player != null and fb.model_anim.current != "":
		cur = fb.model_anim.current
		pos = fb.model_anim.player.current_animation_position
	return [fb.model_fsm.state_name(), fb.model_fsm.current_action(), cur, pos]


## 机体自身基向量下的八向（世界坐标）。
## ⚠️ 不写死世界轴：机体出生朝向变了（或将来给某台烘了整机 yaw）这套就废了。
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


## ------------------------------ ① 平飞八向 ------------------------------

func _fly_dirs(fb: FlightBody) -> void:
	print("")
	print("---- ① 平飞八向：给 `translate_dir`，看会不会播 `fly_<dir>` ----")
	var dirs := _dirs_of(fb)
	print("  %-8s %-12s %-12s %-12s %8s" % ["方向", "FSM", "FSM动作", "播放器", "播放头"])
	print("  " + "-".repeat(58))
	for d in DIR_NAMES:
		fb.control_input = Vector3.ZERO
		fb.translate_dir = dirs[d]
		await _step(fb)
		var r := await _step(fb)
		print("  %-8s %-12s %-12s %-12s %8.3f" % [d, r[0], r[1], r[2], r[3]])
		var want := "fly_" + str(d)
		if r[1] != want:
			_fails.append("平飞 %s：期望 %s，实得 %s" % [d, want, r[1]])
		if r[3] <= 0.0:
			_fails.append("平飞 %s：播放头 %0.3f（没在动）" % [d, r[3]])
	fb.translate_dir = Vector3.ZERO
	await _step(fb)
	var r0 := await _step(fb)
	print("  %-8s %-12s %-12s %-12s %8.3f" % ["(松开)", r0[0], r0[1], r0[2], r0[3]])
	if fb.model_fsm.state_name() != "idle":
		_fails.append("松开平移后仍在 %s（应回 idle）" % fb.model_fsm.state_name())


## ------------------------------ ② 姿态微调 ------------------------------

func _turn_axes(fb: FlightBody) -> void:
	print("")
	print("---- ② 姿态微调：给 `control_input`，看会不会播 `turn_<轴>` ----")
	print("  %-12s %-22s %-10s %-16s %8s" % ["轴", "输入(pitch,yaw,roll)", "FSM", "FSM动作", "播放头"])
	print("  " + "-".repeat(74))
	for ax in AXES:
		fb.translate_dir = Vector3.ZERO
		fb.control_input = AXES[ax]
		await _step(fb)
		var r := await _step(fb)
		print("  %-12s %-22s %-10s %-16s %8.3f"
			% [ax, str(AXES[ax]), r[0], r[1], r[3]])
		var want := "turn_" + str(ax)
		if r[1] != want:
			_fails.append("姿态 %s：期望 %s，实得 %s" % [ax, want, r[1]])
	# 死区：三轴都在死区里 ⇒ 不播
	fb.control_input = Vector3(0.1, 0.0, 0.0)
	await _step(fb)
	var r0 := await _step(fb)
	print("  %-12s %-22s %-10s %-16s %8.3f"
		% ["(0.1 死区)", str(Vector3(0.1, 0, 0)), r0[0], r0[1], r0[3]])
	if r0[1] != "":
		_fails.append("死区内仍播了 %s（应该什么都不播）" % r0[1])
	fb.control_input = Vector3.ZERO


## ------------------------------ ③ 优先级 ------------------------------

func _priority(fb: FlightBody) -> void:
	print("")
	print("---- ③ 优先级：平移与姿态同时给 ----")
	var dirs := _dirs_of(fb)
	fb.translate_dir = dirs["f"]
	fb.control_input = Vector3(0, 0, 1)          # 前飞 + 左滚
	await _step(fb)
	var r := await _step(fb)
	print("  前飞 + 左滚 ⇒ FSM=%s 动作=%s（期望 `fly_f`：平移优先）" % [r[0], r[1]])
	if r[1] != "fly_f":
		_fails.append("平移优先失效：期望 fly_f，实得 %s" % r[1])
	fb.translate_dir = Vector3.ZERO
	fb.control_input = Vector3.ZERO


## ------------------------------ ④⑤⑥ 战斗动作 ------------------------------

func _actions(fb: FlightBody) -> void:
	print("")
	print("---- ④⑤⑥ 战斗动作：走真实触发函数 ----")
	print("  %-38s %-8s %-9s %-22s %8s" % ["触发", "返回", "FSM", "FSM动作", "播放头"])
	print("  " + "-".repeat(90))

	# ④ 举盾
	fb.shield_cooldown = 0.0
	fb.shield_up = false
	var ok_shield := fb.raise_shield()
	var r1 := await _step(fb)
	print("  %-38s %-8s %-9s %-22s %8.3f"
		% ["raise_shield()", str(ok_shield), r1[0], r1[1], r1[3]])
	if r1[1] != "shield":
		_fails.append("举盾：期望 shield，实得 %s" % r1[1])

	# ⑤ 挥刀（给 null 目标 = 原地挥）
	fb.saber_state = FlightBody.SaberState.IDLE
	fb.saber_cooldown = 0.0
	var ok_saber := fb.try_saber(null)
	var r2 := await _step(fb)
	print("  %-38s %-8s %-9s %-22s %8.3f"
		% ["try_saber(null)", str(ok_saber), r2[0], r2[1], r2[3]])
	if not ok_saber:
		_fails.append("try_saber() 返回 false（机体/状态不满足，测不到挥刀）")
	elif r2[1] != "slash":
		_fails.append("挥刀：期望 slash，实得 %s" % r2[1])

	# ⑥ 射击 / 军刀过渡 —— 都走 `play_model_action()`
	for nm in ["shoot", "trans_fly_to_slash", "trans_slash_to_fly"]:
		fb.model_fsm.stop()
		var ok := fb.play_model_action(nm)
		var r := await _step(fb)
		print("  %-38s %-8s %-9s %-22s %8.3f" % ["play_model_action(%s)" % nm, str(ok), r[0], r[1], r[3]])
		if r[1] != nm:
			_fails.append("play_model_action(%s)：实得 %s" % [nm, r[1]])

	# ⚠️ 反例：不存在的动作名必须安全返回 false，且不改变状态。
	fb.model_fsm.stop()
	var ok_bad := fb.play_model_action("no_such_action")
	var r4 := await _step(fb)
	print("  %-38s %-8s %-9s %-22s %8.3f"
		% ["play_model_action(不存在)", str(ok_bad), r4[0], r4[1], r4[3]])
	if ok_bad or r4[1] != "":
		_fails.append("不存在的动作名没有被安全拒绝（返回 %s / 动作 %s）" % [str(ok_bad), r4[1]])
