extends Node
## N42·二十一 **轨道覆盖 & 真实 pose** 全量 dump（无渲染依赖，可 `--headless`）。
##
## ## 为什么要它（实机判决留下的矛盾）
##
## 源 glb `xi_cruise_idle.glb` 有 **51 根骨的 rotation 通道**（`probe_glb_channels.py` 实测），
## 但 Godot 侧 `ModelAnimator.rotations_at('cruise_idle')` 只返回 **19 根骨**。
## ⇒ Godot 的 glTF 导入器**丢掉了「整段恒定 = rest」的通道**（51 − 32 = 19）。
##
## ## 为什么这会是缺陷
##
## `AnimationPlayer` 换动作时，**新动作没有轨道的属性保持上一动作的值**（不归 rest）。
## 于是：
##   * `fly`        只覆盖 26 根骨（实测）⇒ 其余 25 根停在 rest；
##   * `form_on`    —— 若导入后同样丢掉恒定通道，则**它也没法把身体归位**；
##   * `cruise_idle` 19 根 ⇒ 32 根身体骨**没人管**。
## 表现 = 「翼展开了，但身体还停在上一段的姿势」。
##
## ## 三种可能，本探针一次分清
##
##   ① 恒定通道被丢 ⇒ 身体骨无轨道 ⇒ 换动作时不归位（**本探针量的是这个**）；
##   ② 轨道都在，只是 `rotations_at()` 的过滤写错；
##   ③ 都在、也归位了 —— 那屏幕差异另有原因。
##
## ## 跑法
##
##   godot --headless --path <工程> res://tools/_n42_21_tracks.tscn

## 判「这跟骨被写了吗」的阈值（度）。float32 + 插值噪声底 < 1e-3°。
const EPS_DEG := 0.01

var _all_bones: PackedStringArray = []


func _ready() -> void:
	print("")
	print("########## N42·二十一 轨道覆盖 & 真实 pose ##########")
	await _dump_files()
	await _dump_live()
	print("")
	print("VERDICT: N42-21-TRACKS-DONE")
	get_tree().quit(0)


## ------------------------------ ① 各 glb 的轨道覆盖 ------------------------------

func _dump_files() -> void:
	var files: Array = ["res://assets/models/xi_movie/xi_movie_rigged.scn"]
	var d := DirAccess.open("res://assets/models/xi/anim")
	var lst: Array = []
	if d != null:
		for f in d.get_files():
			var nm := str(f)
			if nm.ends_with(".glb"):
				lst.append("res://assets/models/xi/anim/" + nm)
	lst.sort()
	files.append_array(lst)
	print("")
	print("---- ① 逐个 glb 的 Animation 轨道覆盖 ----")
	for p in files:
		var ps := load(str(p)) as PackedScene
		if ps == null:
			print("  !! 载入失败 %s" % p)
			continue
		var inst := ps.instantiate()
		add_child(inst)
		var ap := _find_player(inst)
		if ap == null:
			print("  %-34s 无 AnimationPlayer" % str(p).get_file())
			remove_child(inst)
			inst.free()
			continue
		for an_name in ap.get_animation_list():
			var a := ap.get_animation(an_name)
			if a == null:
				continue
			var rot: Array = []
			var tra: Array = []
			for tr in a.get_track_count():
				var b := _bone_of(a, tr)
				match a.track_get_type(tr):
					Animation.TYPE_ROTATION_3D:
						rot.append(b)
					Animation.TYPE_POSITION_3D:
						tra.append(b)
			rot.sort()
			tra.sort()
			print("  %-30s anim=%-16s 轨道 %3d ｜ rot %2d 根 ｜ pos %2d 根 ｜ len=%.4f s loop=%d"
				% [str(p).get_file(), str(an_name), a.get_track_count(),
				   rot.size(), tra.size(), a.length, a.loop_mode])
			if str(an_name) == "cruise_idle" or str(an_name) == "form_on" or str(an_name) == "fly":
				print("        rot 骨表：%s" % ", ".join(PackedStringArray(rot)))
		remove_child(inst)
		inst.free()


## ------------------------------ ② 真实 pose（生产链路） ------------------------------

func _dump_live() -> void:
	print("")
	print("---- ② 生产链路（ModelAnimator + extras）逐骨真实 pose ----")
	var ps := load("res://assets/models/xi_movie/xi_movie_rigged.scn") as PackedScene
	if ps == null:
		print("  !! 主模型载入失败")
		return
	var inst := ps.instantiate() as Node3D
	add_child(inst)
	await get_tree().process_frame
	var sk := _find_skel(inst)
	if sk == null:
		print("  !! 找不到 Skeleton3D")
		return
	for i in sk.get_bone_count():
		_all_bones.append(sk.get_bone_name(i))
	print("  骨架：%d 骨" % _all_bones.size())

	var extras: Array = SuitProfile.xi().model_anim_files
	var ma := ModelAnimator.setup(inst, extras)
	ma.idle_action = "fly"
	ma.burst_action = "burst"
	ma.burst_cruise_action = "burst_cruise"
	ma.idle_cruise_action = "cruise_idle"
	ma.form_on_action = "form_on"
	ma.prepare_loops()
	print("  ModelAnimator ready=%s ｜ 动作表 %d 个" % [str(ma.ready), ma.action_names().size()])

	# 逐动作：先 stop 清干净，再播 + 定格，量**每一根骨**的局部旋转角。
	for nm in ["fly", "form_on", "cruise_idle", "burst_cruise"]:
		if not ma.has(nm):
			print("  [%s] 不在动作表" % nm)
			continue
		ma.stop()
		for i in sk.get_bone_count():
			sk.set_bone_pose_rotation(i, Quaternion())
			sk.set_bone_pose_position(i, Vector3.ZERO)
		await get_tree().process_frame
		ma.player.play(nm, 0.0, 1.0, false)
		ma.player.seek(_len(ma, nm), true)
		await get_tree().process_frame
		await get_tree().process_frame
		var moved: Array = []
		var worst := 0.0
		var worst_b := ""
		for i in sk.get_bone_count():
			var q := sk.get_bone_pose_rotation(i)
			var deg := rad_to_deg(2.0 * acos(clampf(absf(q.w if absf(q.w) <= 1.0 else 1.0),
				-1.0, 1.0)))
			# ⚠️ `Quaternion.w` 直接取有符号；用 `get_angle()` 更稳。
			deg = rad_to_deg(q.get_angle())
			var p := sk.get_bone_pose_position(i)
			if deg > EPS_DEG or p.length() > 1e-5:
				moved.append("%s(%.2f°,%.3fm)" % [sk.get_bone_name(i), deg, p.length()])
			if deg > worst:
				worst = deg
				worst_b = sk.get_bone_name(i)
		print("  [%s] len=%.4f s ｜ 姿态非 rest 的骨 %d / %d ｜ 最大角 %.2f° (%s)"
			% [nm, _len(ma, nm), moved.size(), sk.get_bone_count(), worst, worst_b])
		print("        %s" % ", ".join(PackedStringArray(moved)))
	print("")
	print("  ---- 交叉对照：`fly` 与 `cruise_idle` 各自把哪些骨写成了非 rest ----")
	print("  （若两者都有一个共同的「非 rest 集合」交集，那部分骨在巡航时**不会**被归位）")
	remove_child(inst)
	inst.free()


func _len(ma: ModelAnimator, nm: String) -> float:
	var a := ma.player.get_animation(nm)
	return a.length if a != null else 0.0


func _find_player(root: Node) -> AnimationPlayer:
	for c in root.find_children("*", "AnimationPlayer", true, false):
		return c as AnimationPlayer
	return null


func _find_skel(root: Node) -> Skeleton3D:
	for c in root.find_children("*", "Skeleton3D", true, false):
		return c as Skeleton3D
	return null


func _bone_of(a: Animation, tr: int) -> String:
	var p := a.track_get_path(tr)
	if p.get_subname_count() >= 1:
		return str(p.get_subname(0))
	var s := str(p)
	var i := s.rfind(":")
	return s.substr(i + 1) if i >= 0 else ""
