extends Node
## N44 佩涅罗佩：**主模型换代 + 动作全部装载**的实机判据（无渲染依赖，可 `--headless`）。
##
## ## 为什么非有它不可
##
## 本轮的失败模式**全部是静默的**：
##
##   ① 主模型若没有 `AnimationPlayer`（= 拿了 0 动画的 `penelope_rig_v3.glb`），
##      `ModelAnimator.setup()` 在 `if ap == null: return ma` 就返回了，
##      `ready` 保持 **false** ⇒ `_graft_extras()` 根本不被调用 ⇒ **27 段一段都不在表里**，
##      **不报错、不 push_warning**。⇒ 判据 = `ma.ready` + 动作表条数。
##
##   ② 新装的 glb 若没跑过一次 `--import`，Godot 不生成 `.import` ⇒
##      `ResourceLoader.exists()` 返回 **false** ⇒ `_graft_extras()` 只 `push_warning`
##      就 `continue` ⇒ 动作表少几件、**全链不报错**（N42·二十二 踩过）。
##      ⇒ 判据 = 逐条 `ResourceLoader.exists()`。
##
##   ③ 换模型后 `model_bounds` 变了 ⇒ 喷口/炮口那批**包围盒归一化分数**会整体错位，
##      而屏幕投影可能"看着还挺对"（本工程 `XI_PLUMES` §① 的旧账）。
##      ⇒ 本探针把 `model_bounds` 打出来，供与 `_relay/log_pen_geom.txt` 的实测值对账。
##
##   ④ ★ `get_bone_pose_rotation()` 是**绝对节点变换**、不是"相对 rest 的偏移"
##      （rest 本身非零，`Hips` rest 就是好几度）⇒ **"非 rest 骨"不是有效筛选口径**。
##      判"这个动作到底动没动"必须**与基准动作（`fly`）比差**，本探针就是这么做的。
##
## ## 跑法
##
##   godot --headless --path <工程> res://tools/_n44_pen.tscn

## 「这跟骨被写动了」的阈值（度）。float32 + 插值噪声底 < 1e-3°。
const EPS_DEG := 0.01

## 与基准（`fly`）比差超过这个度数才算"这个动作有自己的姿态"。
const DIFF_DEG := 0.5

## 交付契约：本机骨架骨数（`penelope_rig_v3` / 39 骨）。
## ⚠️ 柯西是 51 —— 这里写死是为了**当场发现"装错了机体的动作"**（骨名/骨数对不上）。
const BONE_COUNT := 39

var _bones: PackedStringArray = []


func _ready() -> void:
	print("")
	print("########## N44 佩涅罗佩 模型换代 + 动作装载 ##########")
	var prof := SuitProfile.penelope()
	print("  model_path        = %s" % prof.model_path)
	print("  model_native_height = %.4f   target_height = %.2f" % [prof.model_native_height, prof.target_height])
	print("  model_yaw_deg     = %.1f  （rig 已把 +90° 烘进 rest ⇒ 必须 0）" % prof.model_yaw_deg)
	print("  model_anim_files  = %d 条" % prof.model_anim_files.size())
	print("  burst/burst_cruise = %s / %s  （本机没有这两段 ⇒ 期望退化成不播、不报错）"
		% [prof.model_anim_burst, prof.model_anim_burst_cruise])
	print("  idle_cruise/form_on/form_off  = %s / %s / %s  （无巡航形态 ⇒ 期望全空）"
		% [prof.model_anim_idle_cruise, prof.model_anim_form_on, prof.model_anim_form_off])
	await _check_exists(prof)
	await _dump_files()
	await _dump_live(prof)
	print("")
	print("VERDICT: N44-PEN-DONE")
	get_tree().quit(0)


## ------------------------------ ① 逐条 `ResourceLoader.exists()` ------------------------------

func _check_exists(prof: SuitProfile) -> void:
	print("")
	print("---- ① 资源可达性（`--import` 漏跑 ⇒ 这里全 false，而全链不报错）----")
	var miss: Array = []
	var paths: Array = [prof.model_path]
	paths.append_array(prof.model_anim_files)
	for p in paths:
		if not ResourceLoader.exists(str(p)):
			miss.append(str(p))
	print("  检查 %d 条（主模型 1 + 动作表 %d）｜ 不可达 %d 条"
		% [paths.size(), prof.model_anim_files.size(), miss.size()])
	for m in miss:
		print("    ✗ %s" % m)
	print("  ==> %s" % ("PASS（全部可达）" if miss.is_empty() else "FAIL（有件不可达）"))


## ------------------------------ ② 各 glb 的轨道覆盖 ------------------------------

func _dump_files() -> void:
	print("")
	print("---- ② 逐个 glb 的 Animation 轨道覆盖 ----")
	var files: Array = ["res://assets/models/penelope_movie/penelope_movie_rigged.scn"]
	var d := DirAccess.open("res://assets/models/penelope/anim")
	var lst: Array = []
	if d != null:
		for f in d.get_files():
			var nm := str(f)
			if nm.ends_with(".glb"):
				lst.append("res://assets/models/penelope/anim/" + nm)
	lst.sort()
	files.append_array(lst)
	print("  主模型 1 件 + anim/ %d 件 = %d 件" % [lst.size(), files.size()])
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
			print("  %-30s anim=%-20s 轨道 %3d ｜ rot %2d 根 ｜ pos %2d 根 ｜ len=%.4f s loop=%d"
				% [str(p).get_file(), str(an_name), a.get_track_count(),
				   rot.size(), tra.size(), a.length, a.loop_mode])
		remove_child(inst)
		inst.free()


## ------------------------------ ③ 生产链路（真实 pose） ------------------------------

func _dump_live(prof: SuitProfile) -> void:
	print("")
	print("---- ③ 生产链路（ModelAnimator.setup + extras + prepare_loops）----")
	var ps := load(prof.model_path) as PackedScene
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
	var meshes := inst.find_children("*", "MeshInstance3D", true, false).size()
	for i in sk.get_bone_count():
		_bones.append(sk.get_bone_name(i))
	print("  骨架 %d 骨 ｜ 可见网格 %d 件  ⇒ 骨数判据 %d %s"
		% [_bones.size(), meshes, BONE_COUNT,
		   "PASS" if _bones.size() == BONE_COUNT else "FAIL"])

	# ---- ★ 核心：生产接线（与 `FlightBody._setup_model_anim()` 逐行对应）----
	var ma := ModelAnimator.setup(inst, prof.model_anim_files)
	ma.idle_action = prof.model_anim_idle
	ma.burst_action = prof.model_anim_burst
	ma.burst_cruise_action = prof.model_anim_burst_cruise
	ma.idle_cruise_action = prof.model_anim_idle_cruise
	ma.form_on_action = prof.model_anim_form_on
	ma.form_off_action = prof.model_anim_form_off
	ma.prepare_loops()

	var want: int = prof.model_anim_files.size() + 1     # 主模型自带 `fly` + 27
	print("")
	print("  ★ ready = %s   （**false ⇒ 27 段一段都装不进去**，这是本轮最大的坑）" % str(ma.ready))
	print("  ★ 动作表 %d 个（期望 %d = 主模型自带 1 + 登记 %d）⇒ %s"
		% [ma.action_names().size(), want, prof.model_anim_files.size(),
		   "PASS" if ma.action_names().size() == want else "FAIL"])
	print("      %s" % ", ".join(PackedStringArray(ma.action_names())))
	var fly_loop := -1
	if ma.has("fly"):
		var fa := ma.player.get_animation("fly")
		if fa != null:
			fly_loop = fa.loop_mode
	print("  ★ `fly` loop_mode = %d  （要 1 = LOOP_LINEAR；漏设 ⇒ 待机播完停在末帧、不报错）" % fly_loop)
	print("  缺件检查：`burst` 在表里？ %s ｜ `burst_cruise`？ %s  （本机期望都 false）"
		% [str(ma.has("burst")), str(ma.has("burst_cruise"))])

	# ---- 基准：`fly` 在中点的逐骨四元数 ----
	var base := await _pose_at(ma, sk, "fly")
	var fly_bones: Array = _rot_bones(ma, "fly")
	# ★ 管线自检：**同一个动作采两次必须逐位相同**（差 0）。
	#   不验这一条的话，"所有动作都差 90°"这种读数分不清是**动作真不同**、
	#   还是**采样管线本身有问题**（清场没生效 / seek 没落地 / 读的是残留值）。
	var again := await _pose_at(ma, sk, "fly")
	var self_max := 0.0
	for k in base:
		self_max = maxf(self_max, _qd(base[k], again.get(k, Quaternion())))
	print("")
	print("  ★ 管线自检：`fly` 采两次 → 最大差 %.4f°  （必须 ≈ 0，否则下面的读数全不可信）" % self_max)
	print("  基准 `fly`（t=50%%）有 rot 轨道的骨 %d / %d" % [fly_bones.size(), _bones.size()])
	print("  ⚠️ 判据 = 骨对骨 `2·acos|dot|`（双覆盖归一），**不是**「与 rest 的角相减」——")
	print("     后者对「绕不同轴」会虚高、对「对称相反的旋转」会抵消。")

	print("")
	print("  %-22s %8s %8s %8s  %s" % ["动作", "最大差(°)", "超差骨", "轨道骨", "该骨"])
	print("  " + "-".repeat(74))
	var uniq := 0
	for nm in ma.action_names():
		if str(nm) == "fly":
			continue
		var pose := await _pose_at(ma, sk, str(nm))
		var worst := 0.0
		var worst_b := ""
		var n := 0
		for k in base:
			var d: float = _qd(base[k], pose.get(k, Quaternion()))
			if d > DIFF_DEG:
				n += 1
			if d > worst:
				worst = d
				worst_b = str(k)
		if worst > DIFF_DEG:
			uniq += 1
		print("  %-22s %8.2f %8d %8d  %s"
			% [str(nm), worst, n, _rot_bones(ma, str(nm)).size(), worst_b])
	print("  " + "-".repeat(74))
	print("  ⇒ %d / %d 段动作与基准 `fly` 有可分辨差异" % [uniq, ma.action_names().size() - 1])

	# ---- ★ 归位覆盖：换回 `fly` 时，别的动作动过的骨会不会被漏掉 ----
	# 没轨道的骨在换动作时**保持上一段的残留值**（Godot 导入器丢了「恒定 = rest」的通道）。
	print("")
	print("  ---- ★ 归位覆盖：`fly` 的 rot 骨表 vs 各动作（差集 = 可能残留的骨）----")
	var fly_set := {}
	for b in fly_bones:
		fly_set[b] = true
	var risky := {}
	for nm in ma.action_names():
		var s := str(nm)
		if s == "fly":
			continue
		for b in _rot_bones(ma, s):
			if not fly_set.has(b):
				if not risky.has(b):
					risky[b] = []
				risky[b].append(s)
	if risky.is_empty():
		print("    ✓ 没有被 `fly` 漏掉的骨：任何动作动过的骨，`fly` 都管得住。")
	else:
		print("    ⚠️ 这是**平台级现象，不是本轮引入**（柯西 `fly` 26/51 轨也一样）：")
		print("       Godot 的 glTF 导入器丢掉「整段恒定 = rest」的 rotation 通道，")
		print("       而 `AnimationPlayer` 换动作时**没有轨道的属性保持当前值**（不归 rest）")
		print("       ⇒ 先播过 `slash` 再切回 `fly`，下面这些骨会停在 `slash` 的末值。")
		print("       残留幅度 ≈ 上表里该骨那一行的「最大差」")
		print("       （基准 `fly` 对它们读的是清场后的 identity ⇒ 这个差 = 该动作让它转过的角）。")
		for b in risky:
			print("    ⚠️ %-16s 被 %2d 段动过、但 `fly` 无轨道：%s"
				% [str(b), risky[b].size(), ", ".join(PackedStringArray(risky[b]))])

	remove_child(inst)
	inst.free()


## 把某动作定格在 t=50%，返回 `{骨名: Quaternion}`（**原始四元数**，不是角度）。
##
## ⚠️ 为什么返回四元数而不是"与 rest 的角"：两个「与 rest 的角」**相减不等于**
##    两个姿态之差 —— 绕相反方向各转 40° 的两段，角度值都是 40°（差 0，**低估**）；
##    而绕不同轴的两段又会差出虚高的数。**唯一正确的口径是骨对骨的
##    `2·acos|dot(q1, q2)|`**（双覆盖归一）。
##
## ⚠️ `seek()` 之后**要等一帧**骨架才被写进去（N42 探针踩过）⇒ 这里等两帧。
func _pose_at(ma: ModelAnimator, sk: Skeleton3D, nm: String) -> Dictionary:
	var out := {}
	if not ma.has(nm):
		return out
	# 清场：把每根骨按回 identity，这样**没有轨道的骨**在两次采样里读数一致（= 差 0），
	# 不会把"这个动作根本没碰这根骨"误读成"差异很大"。
	ma.stop()
	for i in sk.get_bone_count():
		sk.set_bone_pose_rotation(i, Quaternion())
		sk.set_bone_pose_position(i, Vector3.ZERO)
	await get_tree().process_frame
	var a := ma.player.get_animation(nm)
	if a == null:
		return out
	# ★ `custom_speed = 0.0` 把**播放头钉死** —— 否则 `play()` 之后它每帧继续前进，
	#   而下面要 `await` 两帧才读得到（`seek()` 的结果要下一帧才写进骨架）⇒
	#   两次采样落在**不同的播放时刻**上，读数会带一个 0.5° 量级的伪差
	#   （实测：不钉住时自检 = 0.5367°，钉住后 = 0.0000°）。
	#   `seek()` 是直接设播放头位置，与 `speed` 无关 ⇒ 定位照样生效。
	ma.player.play(nm, 0.0, 0.0, false)
	ma.player.seek(a.length * 0.5, true)
	await get_tree().process_frame
	await get_tree().process_frame
	for i in sk.get_bone_count():
		out[sk.get_bone_name(i)] = sk.get_bone_pose_rotation(i)
	return out


## 两个姿态之间的角（度），**双覆盖归一**：`q` 与 `−q` 是同一旋转 ⇒ 取 `|dot|`。
func _qd(a: Quaternion, b: Quaternion) -> float:
	return rad_to_deg(2.0 * acos(clampf(absf(a.dot(b)), 0.0, 1.0)))


## 某动作在 **Godot 侧**有 rotation 轨道的骨名集合。
##
## ⚠️ 源 glb 每件 78 通道（39 rot + 39 trans），但 Godot 导入器**会丢掉「整段恒定 = rest」
##    的通道**（N42·二十二 T10）⇒ 这里只有 21~27 根 rot、pos **0 根**。
##    丢 trans 无害（本机骨骼位置恒定 = 纯旋转驱动）；丢 rot 要小心：
##    **换动作时没轨道的骨保持上一段的残留值**。
func _rot_bones(ma: ModelAnimator, nm: String) -> Array:
	var out: Array = []
	if not ma.has(nm):
		return out
	var a := ma.player.get_animation(nm)
	if a == null:
		return out
	for tr in a.get_track_count():
		if a.track_get_type(tr) == Animation.TYPE_ROTATION_3D:
			var b := _bone_of(a, tr)
			if b != "" and not out.has(b):
				out.append(b)
	out.sort()
	return out


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
