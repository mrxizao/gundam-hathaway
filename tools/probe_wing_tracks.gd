extends Node
## 判据探针：**方向动作族（`dash_*` / `fly_*` / `turn_*`）到底有没有把 8 根形态骨写回常态。**
##
## ## 为什么单开这一个（用户原话，轮 42）
##
##   「现在是辅助飞行模式下，按哪个键都会关上飞行翼了，
##     我怀疑是不是之前另外一个会话导入了飞行动作，和巡航模式的模型冲突了。」
##
## ## 归因链（前两环已经钉死，这一环是第三环）
##
##   ① 用户看到的「飞行翼关上」 = `Wing.L/R`、`BinderBack.L/R`、`BinderFront.L/R`、
##      `RearHang.L/R` 这 **8 根形态骨**从巡航姿态回到了常态姿态。
##   ② 柯西的形态**不再由 `SkeletonModifier3D` 表达** ——
##      `FlightBody._setup_cruise_form()` 有一条早退：
##      `if model_anim.idle_cruise_action != "" and model_anim.has(...): return`
##      （N42·二十一「方案 B」：形态改由 `cruise_idle` **动作**表达，形态层整个让位）
##      ⇒ **一旦离开 `cruise_idle`，就没有任何东西能压住那 8 根骨**。
##   ③ 于是问题只剩一个可证伪的问句：**方向动作族里到底有没有那 8 根骨的轨道？**
##      有 ⇒ 换了动作就一定被写回它自己的姿态（= 常态）⇒ 用户的症状成立。
##      没有 ⇒ 那 8 根骨保持上一动作的值 ⇒ 本轮归因**不成立**，要另找。
##
## ## 为什么读「轨道」而不是读「实时 pose」
##
## `AnimationPlayer` 每帧写一遍骨 pose，而 `SkeletonModifier3D._process_modification()`
## 跑在更晚的骨架求值阶段 ⇒ 在**帧边界**读 `get_bone_pose_rotation()` 只会读到
## 动画刚写进去的值，读不出形态层有没有生效（N42 的注释里记过这条）。
## 而「这根骨有没有轨道」是**静态事实**，不存在时序问题 ⇒ 本探针只量它，
## 量到的结果不会因为读的时机而变。这也让它天然可用于回归。
##
## 判据：
##   · 某个方向动作在 8 根形态骨上**有**旋转轨道 ⇒ 播它就会把翼带回它自己的姿态
##   · 且它的姿态 ≈ `fly`（常态）而不是 `cruise_idle`（巡航）⇒ 就是「把翼关上」
##
## 用法：
##   "C:/Users/MSIPC/Desktop/Godot_v4.7.1-stable_win64_console.exe" \
##     --headless --path . res://tools/probe_wing_tracks.tscn

## 柯西的 8 根形态骨（与 `cruise_form_modifier.gd` 文件头记的是同一批）。
const FORM_BONES := [
	"Wing.L", "Wing.R",
	"BinderBack.L", "BinderBack.R",
	"BinderFront.L", "BinderFront.R",
	"RearHang.L", "RearHang.R",
]

const CRUISE_REF := "res://assets/models/xi/anim/xi_cruise_idle.glb"
## ⚠️ 常态基准用的是**主模型** `xi_fly.glb`（它在 `xi/` 根下，不在 `anim/`）——
## 里面的 `fly` 就是常态待机动作。写成 `anim/xi_fly.glb` 会静默读不到
##（`load()` 返回 null、每根骨都报"无轨道"），整张表的对照列就全是假的。
const NORMAL_REF := "res://assets/models/xi_movie/xi_movie_rigged.scn"
const FORM_ON := "res://assets/models/xi/anim/xi_form_on.glb"

## 方向动作族（用户按一个键就播其中一段）：
##   `dash_*` = 平移模式的闪避冲刺八向；`fly_*` = 常态平飞方向八向；`turn_*` = 姿态微调六向。
const FAMILY := [
	"res://assets/models/xi/anim/xi_dash_f.glb",
	"res://assets/models/xi/anim/xi_dash_b.glb",
	"res://assets/models/xi/anim/xi_dash_l.glb",
	"res://assets/models/xi/anim/xi_dash_r.glb",
	"res://assets/models/xi/anim/xi_fly_f.glb",
	"res://assets/models/xi/anim/xi_fly_b.glb",
	"res://assets/models/xi/anim/xi_fly_l.glb",
	"res://assets/models/xi/anim/xi_fly_r.glb",
	"res://assets/models/xi/anim/xi_turn_yaw_L.glb",
	"res://assets/models/xi/anim/xi_turn_pitch_up.glb",
]


## 一次性把某个 .glb 里、`bones` 这些骨的**首帧局部旋转**全读出来。
## 返回 `{骨名: Quaternion}`；缺轨道的骨**不进字典**（调用方用 `has()` 判）。
##
## ⚠️ 每个 .glb **只实例化一次**：按骨逐个实例化会白跑 8 遍场景构建。
func _quats_of(path: String, bones: Array) -> Dictionary:
	var out := {}
	var ps := load(path) as PackedScene
	if ps == null:
		return out
	var inst := ps.instantiate()
	add_child(inst)
	var ap := _find_player(inst)
	if ap != null:
		for an_name in ap.get_animation_list():
			var a := ap.get_animation(an_name) as Animation
			if a == null:
				continue
			for tr in a.get_track_count():
				if a.track_get_type(tr) != Animation.TYPE_ROTATION_3D:
					continue
				var bn := _bone_of(a, tr)
				if bones.has(bn) and not out.has(bn):
					out[bn] = a.track_get_key_value(tr, 0) as Quaternion
		ap.stop()
	remove_child(inst)
	inst.free()
	return out


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_player(c)
		if r != null:
			return r
	return null


## 从动画轨道路径里取骨名（`Skeleton3D:Wing.L` → `Wing.L`）。
## 与 `tools/_n42_21_tracks.gd` 逐字同一套写法。
func _bone_of(a: Animation, tr: int) -> String:
	var p := a.track_get_path(tr)
	if p.get_subname_count() >= 1:
		return str(p.get_subname(0))
	var s := str(p)
	var i := s.rfind(":")
	return s.substr(i + 1) if i >= 0 else ""


func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("########## 轮 42：方向动作族对 8 根形态骨的轨道 ##########")
	print("")

	# ---- 基准：巡航 / 常态 ----
	print("---- ① 两个基准（后面所有动作都拿它们比）----")
	var cruise := _quats_of(CRUISE_REF, FORM_BONES)
	var normal := _quats_of(NORMAL_REF, FORM_BONES)
	for b in FORM_BONES:
		var gap := -1.0
		if cruise.has(b) and normal.has(b):
			gap = rad_to_deg((cruise[b] as Quaternion).angle_to(normal[b] as Quaternion))
		print("  %-14s 巡航 %-22s 常态 %-22s 差 %7.2f°"
			% [b, _fmt(cruise.get(b)), _fmt(normal.get(b)), gap])
	print("  ↑ 两基准差得越多，这跟骨越是「形态骨」（挑形态骨的门限就是 0.5°）")
	print("")

	# ---- 主表 ----
	print("---- ② 方向动作族：它把形态骨写到哪一边 ----")
	print("  读法：「离巡航」= 这个动作的姿态与巡航基准的夹角 ——")
	print("        0° ⇒ 它就是巡航姿态（翼开着）；≈ 基准差 ⇒ 它是常态姿态（翼关着）。")
	print("")
	var offenders := 0
	var bones_hit := 0
	for path in FAMILY:
		var nm := (path as String).get_file().get_basename()
		var qs := _quats_of(path, FORM_BONES)
		var worst := 0.0
		var worst_b := "—"
		var hit := 0
		for b in FORM_BONES:
			if not qs.has(b):
				print("        %-14s 无轨道" % b)
				continue
			hit += 1
			bones_hit += 1
			var q: Quaternion = qs[b]
			var to_cruise := -1.0
			var to_normal := -1.0
			if cruise.has(b):
				to_cruise = rad_to_deg(q.angle_to(cruise[b] as Quaternion))
			if normal.has(b):
				to_normal = rad_to_deg(q.angle_to(normal[b] as Quaternion))
			var side := "常态（翼关）" if to_normal < to_cruise else "巡航（翼开）"
			print("        %-14s 离巡航 %7.2f° ｜ 离常态 %7.2f°  ⇒ %s"
				% [b, to_cruise, to_normal, side])
			if to_cruise > worst:
				worst = to_cruise
				worst_b = b
		print("  ── %-14s 8 根形态骨里有轨道 %d 根 ｜ 最远离巡航 %.2f°（%s）"
			% [nm, hit, worst, worst_b])
		if hit > 0:
			offenders += 1
	print("")
	print("  ⇒ 带形态骨轨道的方向动作：**%d / %d** ｜ 命中的骨-动作对 **%d / %d**"
		% [offenders, FAMILY.size(), bones_hit, FORM_BONES.size() * FAMILY.size()])
	print("     只要 > 0，播它就会把翼写回**它自己的姿态** —— 静态事实，与读的时机无关。")

	# ---- 交叉验证 ----
	print("")
	print("---- ③ 交叉验证：`form_on`（常态→巡航的过渡）首帧应落在**常态**基准上 ----")
	var fo := _quats_of(FORM_ON, ["Wing.L", "BinderBack.L"])
	for b in ["Wing.L", "BinderBack.L"]:
		if not fo.has(b):
			print("  %-14s 无轨道" % b)
			continue
		var q: Quaternion = fo[b]
		print("  %-14s `form_on` 首帧 离巡航 %7.2f° ｜ 离常态 %7.2f°"
			% [b, rad_to_deg(q.angle_to(cruise[b] as Quaternion)),
				rad_to_deg(q.angle_to(normal[b] as Quaternion))])
	print("  （首帧 = 常态 ⇒ 「离常态」应 ≈ 0；这条若不对，说明基准取法有问题）")

	print("")
	print("VERDICT: R42-WING-TRACKS-DONE")
	get_tree().quit(0)


func _fmt(q: Variant) -> String:
	if q == null:
		return "（无轨道）"
	var v := q as Quaternion
	return "q(%+.3f,%+.3f,%+.3f,%+.3f)" % [v.x, v.y, v.z, v.w]
