extends Node
## N56 追问：**为什么探针里开火抬枪 89.53°，真机上用户却说"手臂完全不动"**。
##
## ## 与 `probe_n56_cruise_aim_shot.gd` 的关键区别（这就是要验的差异）
##
## 出图探针为了"可复现的轨迹"做了两件事：
##   ① `fb.set_physics_process(false)` —— 把宿主每帧的推进整个关掉；
##   ② 自己在 `_settle()` 里手推 `_tick_cruise_morph()` / `_tick_model_anim()`。
##
## ★ 本轮查明：`_tick_cruise_morph()` 与 `_tick_model_anim()` **是在 `_physics_process()`
##   → `_tick_effects()` 里调的**（`flight_body.gd:2352/2356/3139`，源码注释写的
##   "`_process` 链"是**过时措辞**，实际按物理帧走）。
##   ⇒ 关掉 `_physics_process` 就**同时关掉了 `_tick_weapons()`**，
##     而 `stow_idle`（收枪窗计时）**只在 `_tick_weapons()` 里推进**
##     ⇒ 出图探针里"滞留窗"永不结束（枪永远举着），**与真机不是同一段时间轴**。
##
## ⇒ 本探针**什么都不关、什么都不手推**：只 `await physics_frame`，让宿主自己跑。
##   并且像真机一样在开火时写 `rifle_cooldown = profile.rifle_interval`，
##   让 `_tick_weapons()` 自己把 `stow_idle` 计出来（收枪窗 = 冷却归零 + `STOW_DELAY`）。
##
## 纯读数 ⇒ **可以 `--headless`**（不需要出图，也不依赖渲染器）。
##
## 用法：
##   EXE --headless --path <proj> res://tools/probe_n56_fire_trace.tscn

const DT := 1.0 / 60.0
const ARM_BONES := ["UpperArm.R", "LowerArm.R", "Hand.R"]
const LEG_BONES := ["Thigh.L", "Shin.L", "Foot.L"]
const GUN_BONES := ["muzzle_L", "muzzle_R", "fire_point_1", "fire_point_2"]

var _ref := {}


func _ready() -> void:
	FlightBody.use_placeholder = false
	var fb := await _mount(SuitProfile.xi())

	# ---- 前置：骨架 / 归位段 ----
	var skel: Skeleton3D = fb._model_skel
	if skel == null:
		print("FATAL: 没拿到骨架")
		get_tree().quit(1)
		return
	if fb.model_anim == null or not fb.model_anim.has_cruise_hold():
		print("FATAL: 巡航归位段没建出来")
		get_tree().quit(1)
		return
	print("骨架骨数=%d 骨名[0..3]=%s" % [skel.get_bone_count(),
		str([skel.get_bone_name(0), skel.get_bone_name(1),
			skel.get_bone_name(2), skel.get_bone_name(3)])])

	# ---- ★★ 帧末焊到底焊了哪些骨（用户症状的第一嫌疑）----
	_print_weld(fb, skel)

	# ---- 等巡航稳态（只 await，不手推）----
	fb.translate_dir = Vector3.ZERO
	var steady := await _wait_cruise(fb, 12.0)
	print("巡航稳态=%s morph=%.4f state=%s current='%s'" % [
		str(steady), fb.cruise_morph, fb.model_fsm.state_name(), fb.model_anim.current])
	if not steady:
		print("FATAL: 没到巡航稳态 ⇒ 后面读数无意义")
		get_tree().quit(1)
		return
	_snapshot(fb, skel)
	await _pump(20)
	var drift := _gap(fb, skel, ARM_BONES + LEG_BONES)
	print("基线自检：再推 20 帧臂/腿漂移 %.4f°（应 ≈ 0）" % drift)

	# ---- 开火（与真机同一条调用；并像真机一样写冷却）----
	var interval: float = fb.profile.rifle_interval
	fb.rifle_cooldown = interval
	var ok := fb.play_model_action("shoot", true)
	print("play_model_action(\"shoot\", true) = %s ｜ rifle_interval=%.2f stow_idle=%.3f" % [
		str(ok), interval, fb.stow_idle])
	if not ok:
		get_tree().quit(1)
		return

	# ---- 逐帧轨迹 ----
	print("\n%-4s %-9s %-9s %-18s %-6s %-7s %-8s %-7s %-7s %-6s %s" % [
		"帧", "state", "action", "anim.current", "pos", "speed", "臂离基准", "腿离基准",
		"stow", "can", "weld"])
	var peak_arm := 0.0
	var peak_at := -1
	var prev := ""
	for i in 200:
		await get_tree().physics_frame
		var pl: AnimationPlayer = fb.model_anim.player
		var w := fb._form_weld
		var line := "%d %s %s %s %.3f %.2f %.2f %.2f %d %s %d/%d" % [
			i, fb.model_fsm.state_name(), fb.model_fsm.current_action(),
			fb.model_anim.current, pl.current_animation_position,
			(pl.get_playing_speed() if pl.has_method("get_playing_speed") else 0.0),
			_gap(fb, skel, ARM_BONES), _gap(fb, skel, LEG_BONES),
			fb.model_fsm.stow_stage(), str(fb.model_fsm._can_stow),
			(0 if w == null else w.welds), (0 if w == null else w.ancestor_writes)]
		var key := "%s|%s|%s|%d" % [fb.model_fsm.state_name(),
			fb.model_fsm.current_action(), fb.model_anim.current,
			fb.model_fsm.stow_stage()]
		var g_arm := _gap(fb, skel, ARM_BONES)
		if g_arm > peak_arm:
			peak_arm = g_arm
			peak_at = i
		# 状态没变就每 2 帧打一行（省得刷屏），变了必打
		if key != prev or i % 2 == 0:
			print(line)
			prev = key
		if i > 120 and fb.model_fsm.stows >= 1 and fb.model_fsm.state == ModelAnimFSM.State.IDLE:
			print("（收枪完成，提前结束）")
			break
	print("\n★ 开火窗内臂峰值 %.2f°（第 %d 帧）｜收枪 stows=%d" % [
		peak_arm, peak_at, fb.model_fsm.stows])
	print("★ 判据：peak_arm ≥ 20° ⇒ 开火时手臂**真的抬起来了**（%s）" % str(peak_arm >= 20.0))

	# ---- ② 边飞边打（真机上玩家常是一边按 W 一边开火）----
	#
	# 为什么必须补这一段：① 是在 `translate_dir = ZERO`（悬停）下打的，
	# 而真机里 `translate_dir` 非零 ⇒ `_tick_model_anim` 每帧还会喂
	# `set_dash(_dash_anim_dir)` / `set_turn(...)`。虽然 `ACTION` 排在 `DASH` **之前**
	# （先判先 return），理论上抢不走 —— 但"理论上"不算证据（T35 精神）。
	fb.translate_dir = Vector3(0.0, 0.0, -1.0)
	var steady2 := await _wait_cruise(fb, 8.0)
	print("\n② 边飞边打：巡航稳态=%s state=%s current='%s'" % [
		str(steady2), fb.model_fsm.state_name(), fb.model_anim.current])
	_snapshot(fb, skel)
	await _pump(10)
	fb.rifle_cooldown = fb.profile.rifle_interval
	var ok2 := fb.play_model_action("shoot", true)
	print("   play_model_action = %s（translate_dir=%s，fly_dir 被抑制 ⇒ 送进去的是 \"\"）" % [
		str(ok2), str(fb.translate_dir)])
	var peak2 := 0.0
	var peak2_at := -1
	for i in 200:
		await get_tree().physics_frame
		var g := _gap(fb, skel, ARM_BONES)
		if g > peak2:
			peak2 = g
			peak2_at = i
		if i > 120 and fb.model_fsm.stows >= 1 and fb.model_fsm.state == ModelAnimFSM.State.IDLE:
			break
	print("★ ② 边飞边打：臂峰值 %.2f°（第 %d 帧）⇒ %s" % [
		peak2, peak2_at,
		"同样抬起来了（DASH 抢不走 ACTION）" if peak2 >= 20.0 else "★ 没抬起来 ⇒ 找到了！"])

	print("\nN56_FIRE_TRACE_DONE  (① 悬停 %.2f° / ② 飞行 %.2f°)" % [peak_arm, peak2])
	get_tree().quit(0)


func _print_weld(fb: FlightBody, skel: Skeleton3D) -> void:
	var w := fb._form_weld
	if w == null:
		print("★ 帧末焊：**没有** `_form_weld`（本机不走焊缝那条路）")
		return
	var fbs: Array = w.form_bones()
	var ans: Array = w.ancestor_bones()
	print("★ 帧末焊：形态骨 %d = %s" % [w.form_bone_count(), str(fbs)])
	print("★ 帧末焊：祖先骨 %d = %s" % [w.ancestor_count(), str(ans)])
	for b in ARM_BONES + LEG_BONES:
		var in_form := fbs.has(b)
		var in_anc := ans.has(b)
		print("    %-12s 在形态骨里=%-5s 在祖先骨里=%s %s" % [
			b, str(in_form), str(in_anc),
			"  ← ★★ 被判据量、又被焊缝每帧覆盖！" if (in_form or in_anc) else ""])


## 等巡航稳态。★ 只 `await`，**不手推** —— 本探针要的就是真机的时序。
func _wait_cruise(fb: FlightBody, max_sec: float) -> bool:
	var budget := int(round(max_sec * 60.0))
	for i in budget:
		if fb.cruise_morph >= 0.999 and fb.model_fsm != null \
				and fb.model_fsm.state == ModelAnimFSM.State.IDLE \
				and fb.model_anim != null \
				and fb.model_anim.current == str(ModelAnimator.CRUISE_HOLD_CLIP):
			return true
		await get_tree().physics_frame
	return false


func _mount(p: SuitProfile) -> FlightBody:
	var holder := Node3D.new()
	add_child(holder)
	var fb := FlightBody.new()
	fb.team = 0
	fb.profile = p
	holder.add_child(fb)
	fb.global_transform = Transform3D(Basis(), Vector3(0.0, 3000.0, 0.0))
	# ★★ 与出图探针**故意相反**：**不关** `_physics_process`（那才是真机条件）。
	#    `_tick_weapons()` / `_tick_cruise_morph()` / `_tick_model_anim()` 全由宿主自己跑。
	for i in 5:
		await get_tree().physics_frame
	fb.fm.boosting = true
	fb.fm.hovering = false
	fb.control_input = Vector3.ZERO
	fb.translate_dir = Vector3.ZERO
	return fb


func _pump(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## ★★ 用**良性**夹角量具 `4·asin(‖a−b‖/2)`，⛔ 不用 `Quaternion.angle_to()`
##（后者近单位元病态，会把"逐分量只差 1e-8"印成 0.0396°）。详见 skill §1.6。
func _gap(fb: FlightBody, skel: Skeleton3D, bones: Array) -> float:
	if _ref.is_empty():
		return -1.0
	var mx := 0.0
	for b: String in bones:
		var bi := skel.find_bone(b)
		if bi < 0 or not _ref.has(b):
			continue
		mx = maxf(mx, _q_angle_deg(skel.get_bone_pose_rotation(bi), _ref[b] as Quaternion))
	return mx


static func _q_angle_deg(a: Quaternion, b: Quaternion) -> float:
	var q := b
	if a.dot(b) < 0.0:
		q = -b
	return rad_to_deg(4.0 * asin(clampf((a - q).length() * 0.5, 0.0, 1.0)))


func _snapshot(fb: FlightBody, skel: Skeleton3D) -> void:
	_ref.clear()
	for b in ARM_BONES + LEG_BONES + GUN_BONES:
		var bi := skel.find_bone(b)
		if bi >= 0:
			_ref[b] = skel.get_bone_pose_rotation(bi)
