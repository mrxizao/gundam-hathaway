extends Node
## 判据探针（轮 42）：**形态层写进去的骨姿态，留得住吗？**
##
## ## 背景（一句话）
##
## N42·二十一「方案 B」让 `FlightBody._setup_cruise_form()` 早退 ⇒ 柯西**没有形态层**，
## 8 根形态骨完全由动画说话 ⇒ 一按方向键（`dash_*`）就被写回常态 = 用户报的"翼关上"。
##
## ## 本探针要分辨的**两个**根因（它们的修法完全不同）
##
##   ① **时机/覆盖**：形态层写了，但动画（或引擎求值）在它之后又写了一遍 ⇒ **关掉轨道**即可。
##   ② **写入本身无效**：`SkeletonModifier3D` 的写入压根留不住（跨帧被回滚）⇒ 关轨道没用，
##      只能改在**别的位置**每帧焊（`FlightBody._process` 链）。
##
## ## 相位表（⓪① 是**读数校准**，必须先过）
##
## | 相位 | 在播什么 | 每帧额外做什么 | 期望 | 它在证什么 |
## |------|----------|----------------|------|------------|
## | ⓪ | `cruise_idle` | — | 离巡航 ≈ **0°** | 读数下端（翼开）|
## | ① | `fly` | — | 离巡航 ≈ **141°** | 读数上端（翼关）⇒ 读数**有分辨力** |
## | A | `dash_f`（轨道开）| modifier `morph=1` | 若 ≈141° ⇒ 动画赢 | 复核 N42 的判定 |
## | C | `dash_f`（**轨道关**）| modifier `morph=1` | ≈0° ⇒ 关轨道就够 | **控制变量**：唯一变量 = 轨道开关 |
## | E | **stop（不播）** | 手写巡航 | ≈0° ⇒ 写入留得住 | 隔离"有没有动画"这一个变量 |
## | F | `dash_f`（轨道开）| 手写巡航 | ≈0° ⇒ **每帧焊**可行 | 若 ≈141° ⇒ 动画每帧回写，焊也没用 |
##
## **A 与 C 只差一个变量**，**C 与 E 只差"有没有动画"**，**E 与 F 只差"播不播"**
## —— 三组对照把根因夹死。
##
## ## 为什么必须**窗口模式**跑（不能加 `--headless`）
##
## `SkeletonModifier3D._process_modification()` 由引擎在骨架求值链上驱动，
## 而求值链是渲染端推的。headless（dummy renderer）下它到底跑不跑，
## `cruise_form_modifier.gd` 的文件头里明写着"必须实测，不能假定"。
## 所以本探针**打印 `calls`**：`calls == 0` ⇒ 回调压根没被调（驱动问题），
## 与"被覆盖"是两种根因。
##
## 用法（**不要加 `--headless`**）：
##   "C:/Users/MSIPC/Desktop/Godot_v4.7.1-stable_win64_console.exe" \
##     --path . res://tools/probe_form_layer_vs_anim.tscn

const MODEL := "res://assets/models/xi_movie/xi_movie_rigged.scn"
const CRUISE_IDLE := "res://assets/models/xi/anim/xi_cruise_idle.glb"
const DASH_F := "res://assets/models/xi/anim/xi_dash_f.glb"

const FORM_BONES := [
	"Wing.L", "Wing.R",
	"BinderBack.L", "BinderBack.R",
	"BinderFront.L", "BinderFront.R",
	"RearHang.L", "RearHang.R",
]

var _skel: Skeleton3D
var _ma: ModelAnimator
var _mod: CruiseFormModifier
var _normal := {}
var _cruise := {}

var _res := {}
var _tip := {}


func _ready() -> void:
	var ps := load(MODEL) as PackedScene
	if ps == null:
		_say("模型载不进来：%s" % MODEL)
		_finish(1)
		return
	var inst := ps.instantiate() as Node3D
	add_child(inst)
	await get_tree().process_frame
	_skel = _find_skel(inst)
	if _skel == null:
		_say("模型里没有 Skeleton3D：%s" % MODEL)
		_finish(1)
		return

	print("")
	print("########## 轮 42：形态层写入留不留得住（三组对照）##########")
	print("")

	_ma = ModelAnimator.setup(inst, [CRUISE_IDLE, DASH_F])
	_say("① 建体：骨 %d 根 ｜ 摘到的动作 %s" % [_skel.get_bone_count(), str(_ma.action_names())])
	if not (_ma.has("fly") and _ma.has("cruise_idle") and _ma.has("dash_f")):
		_say("动作缺件 ⇒ 判不了")
		_finish(1)
		return
	_normal = _ma.rotations_at("fly", 0.0)
	_cruise = _ma.rotations_at("cruise_idle")

	_mod = CruiseFormModifier.setup(_skel, _normal, _cruise)
	if _mod == null:
		_say("形态层建不起来 ⇒ 判不了")
		_finish(1)
		return
	_skel.add_child(_mod)
	_say("   形态层：形态骨 %d 根 ｜ active=%s ｜ 绑到骨架 %s"
		% [_mod.form_bone_count(), str(_mod.active), str(_mod.get_skeleton() != null)])
	var dmax := 0.0
	for b in _mod.form_bones(_skel):
		if _normal.has(b) and _cruise.has(b):
			dmax = maxf(dmax, rad_to_deg((_cruise[b] as Quaternion).angle_to(_normal[b] as Quaternion)))
	_say("   两基准最大夹角 %.2f°（读数能分辨的最大幅度）" % dmax)
	print("")

	# ---- ⓪ 读数下端：巡航待机 ----
	print("---- ⓪ 校准：播 `cruise_idle`（真巡航姿态）----")
	await _play("cruise_idle", 60)
	_grab("0_cruise")
	print("")

	# ---- ① 读数上端：常态待机 ----
	print("---- ① 校准：播 `fly`（真常态姿态）----")
	await _play("fly", 60)
	_grab("1_normal")
	print("")

	# ---- A：轨道开 + morph=1 ----
	print("---- A：`dash_f`【轨道开】+ 形态层 morph=1.00 ----")
	await _play("dash_f", 10)
	_mod.morph = 1.0
	await _pump(30)
	_grab("A_open")
	print("")

	# ---- C：轨道关 + morph=1（唯一变量 = 轨道开关）----
	print("---- C：`dash_f`【轨道关】+ 形态层 morph=1.00 ★控制变量★ ----")
	var muted := _mute_form_tracks("dash_f")
	_say("   关掉形态骨旋转轨道 %d 条" % muted)
	await _play("dash_f", 10)
	_mod.morph = 1.0
	await _pump(45)
	_grab("C_mute")
	print("")

	# ---- E：不播（stop）+ 手写巡航 ----
	print("---- E：`stop()` 不播任何动作 + 手写巡航（绝对写）----")
	_ma.stop()
	await get_tree().process_frame
	for i in 30:
		await get_tree().process_frame
		_whip("cruise")
	_grab("E_stop_whip")
	print("")

	# ---- F：播 dash_f（轨道开）+ 手写巡航 ----
	print("---- F：`dash_f`【轨道开】+ 手写巡航（绝对写 · 每帧焊）----")
	await _play("dash_f", 10)
	for i in 30:
		await get_tree().process_frame
		_whip("cruise")
	_grab("F_play_whip")
	print("")

	# ---- 判决 ----
	print("---- 判决 ----")
	for k in ["0_cruise", "1_normal", "A_open", "C_mute", "E_stop_whip", "F_play_whip"]:
		print("  %-14s 离巡航 %7.2f° ｜ Wing.L 骨端 %s"
			% [k, float(_res[k]), _vfmt(_tip[k] as Vector3)])
	print("  形态层回调累计被调用 %d 次" % _mod.calls)
	print("")
	var r0 := float(_res["0_cruise"])
	var r1 := float(_res["1_normal"])
	var rC := float(_res["C_mute"])
	var rE := float(_res["E_stop_whip"])
	var rF := float(_res["F_play_whip"])
	var cal_ok := r0 <= 8.0 and r1 >= 130.0
	if not cal_ok:
		print("VERDICT: R42-CALIBRATION-BROKEN（⓪① 两端没拉开 ⇒ 读数不可信，先修探针）")
	elif rE <= 8.0 and rF <= 8.0:
		print("VERDICT: R42-WRITE-HOLDS（写入留得住 ⇒ 修法 = 每帧焊；关不关轨道都能生效）")
	elif rE <= 8.0:
		print("VERDICT: R42-ANIM-OVERWRITES（不播时留得住、播着留不住 ⇒ 动画每帧回写 ⇒ 必须【关轨道 + 形态层】）")
	elif rC <= 8.0:
		print("VERDICT: R42-MUTE-ENOUGH（关轨道后形态层生效 ⇒ 锁骨法可行）")
	else:
		print("VERDICT: R42-WRITE-BOUNCED（连不播时手写都留不住 ⇒ 问题不在动画，在写法/骨架求值链）")
	_finish(0)


## 播一段并推进 `n` 帧（`dash_f` 是循环动作，不会自己结束）。
func _play(an: String, n: int) -> void:
	_ma.play_loop(an, 0.0, true)
	await get_tree().process_frame
	await _pump(n)


func _pump(n: int) -> void:
	for i in n:
		await get_tree().process_frame
		if i % 15 == 14:
			_say("         …帧 %3d ｜ 离巡航 %7.2f° ｜ Wing.L 骨端 %s"
				% [i + 1, _mod.residual_deg(_skel), _vfmt(_tip_of("Wing.L"))])


func _grab(key: String) -> void:
	_res[key] = _mod.residual_deg(_skel)
	_tip[key] = _tip_of("Wing.L")

## 把某个动作里**形态骨的旋转轨道**全部关掉。返回关掉的条数。
##
## 安全：`ModelAnimator.setup()` 第一件事就是 `_own_default_library()`（深拷私有化），
## 所以这里改的是**本实例私有**的那一份，不会串到别的机体。
func _mute_form_tracks(an: String) -> int:
	if _ma.player == null:
		return 0
	var a := _ma.player.get_animation(an)
	if a == null:
		return 0
	var n := 0
	for tr in a.get_track_count():
		if a.track_get_type(tr) != Animation.TYPE_ROTATION_3D:
			continue
		if FORM_BONES.has(_bone_of(a, tr)):
			a.track_set_enabled(tr, false)
			n += 1
	return n


## 直接、**绝对**写形态骨（不读当前值）。
func _whip(which: String) -> void:
	for bn in _mod.form_bones(_skel):
		var q: Quaternion = _normal[bn] if which == "normal" else _cruise[bn]
		_skel.set_bone_pose_rotation(_skel.find_bone(bn), q)


## 某根骨的**骨端**位置（相对 Skeleton3D 原点）。
##
## ⚠️ 读的是 `get_bone_global_pose()` —— 它由 `Skeleton3D` 在求值链里算好后**缓存**。
## 所以在回调外写 pose 之后立刻读它，可能读到**上一轮**的值（缓存未刷新）。
## 这正是本探针要连读多帧的原因：真的生效会**稳定**停在新位置，假的只会在旧位置附近抖。
func _tip_of(bn: String) -> Vector3:
	var bi := _skel.find_bone(bn)
	if bi < 0:
		return Vector3.ZERO
	var gp := _skel.get_bone_global_pose(bi)
	var l := _skel.get_bone_rest(bi).origin.length()
	return gp.origin + gp.basis * Vector3(0.0, l, 0.0)


## 从动画轨道路径里取骨名（`Skeleton3D:Wing.L` → `Wing.L`）。
## 与 `tools/_n42_21_tracks.gd` / `probe_wing_tracks.gd` 逐字同一套写法。
func _bone_of(a: Animation, tr: int) -> String:
	var p := a.track_get_path(tr)
	if p.get_subname_count() >= 1:
		return str(p.get_subname(0))
	var s := str(p)
	var i := s.rfind(":")
	return s.substr(i + 1) if i >= 0 else ""


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null


func _vfmt(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


func _say(s: String) -> void:
	print(s)


func _finish(code: int) -> void:
	print("")
	get_tree().quit(code)
