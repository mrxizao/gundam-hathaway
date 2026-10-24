extends Node
## N52 诊断（**headless · 纯读数**）：位置基准表到底有没有建起来。
##
## 症状：`FormWeld` 加了位置写入之后，`probe_wing_pos.gd` 段 2 的
## 「离巡航位置」读数**一字未变**（31.2373）⇒ 位置通路压根没启用。
##
## 最可疑的一处：`CruiseFormModifier.setup()` 的整表自检 ——
## 只要有**一根**形态骨缺位置基准，`_normal_pos` 就会比 `_idx` 短 ⇒ 自检失败 ⇒
## `clear()` ⇒ **整条位置通路被禁掉**。
##
## 跑法（headless 即可，不出图）：
##   godot --headless --path <工程> res://tools/_n52_diag.tscn

const FORM := ["Wing.L", "Wing.R", "BinderFront.L", "BinderFront.R",
	"BinderBack.L", "BinderBack.R", "RearHang.L", "RearHang.R"]


func _ready() -> void:
	FlightBody.use_placeholder = false
	var holder := Node3D.new()
	add_child(holder)
	var fb := FlightBody.new()
	fb.team = 0
	fb.profile = SuitProfile.xi()
	holder.add_child(fb)
	fb.global_transform = Transform3D(Basis(), Vector3(0.0, 3000.0, 0.0))
	fb.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame

	var ma := fb.model_anim
	if ma == null or not ma.ready:
		print("FATAL: model_anim 没就绪")
		get_tree().quit(1)
		return
	print("=== ModelAnimator ===")
	print("idle_action=%s  idle_cruise_action=%s" % [ma.idle_action, ma.idle_cruise_action])

	for pair in [[ma.idle_action, 0.0], [ma.idle_cruise_action, -1.0]]:
		var act: String = pair[0]
		var t: float = pair[1]
		var r := ma.rotations_at(act, t)
		var p := ma.locations_at(act, t)
		print("\n--- %s (t=%s) ---" % [act, "首帧" if t >= 0.0 else "末帧"])
		print("  rotations=%d  locations=%d" % [r.size(), p.size()])
		var only_r: Array = []
		for b in r.keys():
			if not p.has(b):
				only_r.append(b)
		var only_p: Array = []
		for b in p.keys():
			if not r.has(b):
				only_p.append(b)
		print("  ★ 有旋转无位置（%d）: %s" % [only_r.size(), str(only_r)])
		print("    有位置无旋转（%d）: %s" % [only_p.size(), str(only_p)])
		print("  ★ 8 根形态骨里缺位置的: %s" % str(_missing(FORM, p)))
		# 抽 3 根看值
		for b in ["RearHang.R", "BinderBack.L", "Wing.L"]:
			print("     %-14s rot=%s  loc=%s" % [b,
				str(r.get(b, "—")), str(p.get(b, "—"))])
		# 轨道类型普查
		var a: Animation = ma.player.get_animation(act)
		if a != null:
			var cnt := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0}
			for tr in a.get_track_count():
				var tt := a.track_get_type(tr)
				cnt[tt] = int(cnt.get(tt, 0)) + 1
			print("  轨道类型分布 (0=VALUE 1=POS 2=ROT 3=SCALE 4=BLEND): %s" % str(cnt))

	print("\n=== FormWeld ===")
	var w: FormWeld = fb._form_weld
	if w == null:
		print("  _form_weld = null")
	else:
		print("  形态骨=%d  被门槛滤掉=%s" % [w.form_bone_count(), str(w.skipped)])
		print("  ★ has_positions=%s" % str(w.has_positions()))
		print("  _idx=%d  _normal=%d  _cruise=%d  _normal_pos=%d  _cruise_pos=%d" % [
			w._idx.size(), w._normal.size(), w._cruise.size(),
			w._normal_pos.size(), w._cruise_pos.size()])
		print("  residual_pos()=%.4f（-1 = 位置通路未启用）" % w.residual_pos())
	# 顺手看 CruiseFormModifier（未挂树的那个是 `pick`，这里看树上那个）
	print("\n=== 树上是否有挂着的 CruiseFormModifier ===")
	var found := 0
	if fb._model_skel != null:
		for c in fb._model_skel.get_children():
			if c is CruiseFormModifier:
				found += 1
				var cm: CruiseFormModifier = c
				print("  %s: bones=%d has_positions=%s pos_tbl=%d" % [
					c.name, cm.form_bone_count(), str(cm.has_positions()),
					cm._normal_pos.size()])
	print("  共 %d 个" % found)

	# ---- 各动作的位置轨骨名普查（判「位置基准该取哪个动作」+「焊缝会不会冻住别的骨」）----
	#
	# 两个问题一次看清：
	#   ① 常态 / 巡航两侧的位置轨到底覆盖哪几根骨（缺的靠 rest 补）；
	#   ② `Shoulder.L` 这类「旋转差够、位置没轨」的骨，会不会被**方向动作**写位置
	#      —— 若会，焊缝把它钉在 rest 就冻住了它的运动（H1 风险）。
	print("\n=== 位置轨骨名普查 ===")
	for act in ["fly", "cruise_idle", "form_on", "form_off",
			"dash_f", "dash_b", "dash_l", "fly_f", "turn_yaw_L"]:
		if not ma.actions.has(act):
			print("  %-12s （未登记）" % act)
			continue
		var a2: Animation = ma.player.get_animation(act)
		var names: Array = []
		for tr in a2.get_track_count():
			if a2.track_get_type(tr) != Animation.TYPE_POSITION_3D:
				continue
			names.append(String(a2.track_get_path(tr)).split(":")[-1])
		print("  %-12s POS=%d  %s" % [act, names.size(), str(names)])
	_dir_family_check(ma, fb._model_skel)
	get_tree().quit(0)


## 方向动作族对 8 根形态骨写了什么位置（验证「恒定写在常态位置」这条断言）。
func _dir_family_check(ma: ModelAnimator, skel: Skeleton3D) -> void:
	print("\n=== 方向动作族 · 形态骨的 translation 取值 ===")
	var rest := {}
	for b in FORM:
		var bi: int = skel.find_bone(b) if skel != null else -1
		if bi >= 0:
			rest[b] = skel.get_bone_rest(bi).origin
	print("  rest 基准: %s" % str(rest))
	for act in ["cruise_idle", "dash_f", "dash_b", "dash_l", "fly_f"]:
		if not ma.actions.has(act):
			print("  %-12s （未登记）" % act)
			continue
		var p := ma.locations_at(act, 0.0)
		var miss: Array = []
		var worst := ""
		var worst_d := -1.0
		for b in FORM:
			if not p.has(b):
				miss.append(b)
				continue
			var d: float = (p[b] as Vector3).distance_to(rest[b] as Vector3)
			if d > worst_d:
				worst_d = d
				worst = b
		print("  %-12s 覆盖 %d/8  缺=%s  ★离 rest 最远=%s %.4f" % [
			act, 8 - miss.size(), str(miss), worst, worst_d])


func _missing(want: Array, has: Dictionary) -> Array:
	var out: Array = []
	for b in want:
		if not has.has(b):
			out.append(b)
	return out
