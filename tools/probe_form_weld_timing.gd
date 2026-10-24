extends Node
## 判据探针（轮 42·第二问）：**「每帧焊」要焊在哪个时机？**
##
## ## 前一问的结论（`_r42/pfl_3.txt`，已跑通）
##
## 三组对照把根因夹死了：
##   · `dash_f` 播着 + `SkeletonModifier3D` 写巡航 ⇒ 读到常态（141.30°）—— **关不关轨道都一样**
##   · `AnimationPlayer.stop()` + 手写巡航 ⇒ 读到巡航（**0.00°**）
##   · `dash_f` 播着 + **手写**巡航 ⇒ 读到巡航（**0.00°**）
## ⇒ **形态层这条路是死的**（动画求值链在它之后无条件重写这批骨，
##   连 `track_set_enabled(false)` 都没用——禁用轨道被写回"动画开始时的值"）；
##   **唯一有效的位置是"动画求值之后、直接写骨"**。
##
## ## 本探针只问一件事：**「之后」到底要多后**
##
## 探针节点是模型实例的**父**节点。Godot 的 `_process_group` 是按树顺序（父→子）
## 派发通知的，所以"父的 `_process`"与"子的 `AnimationPlayer`（internal process）"
## 谁先谁后，**不能靠推理，必须实测**。四种时机各跑一遍：
##
## | 时机 | 做法 | 若有效说明 |
## |------|------|------------|
## | W0 | 不焊（对照）| 基线：应停在常态 141° |
## | W1 | 本节点 `_process()` 里焊 | 内部/普通通知是**两趟**，位置不敏感 ⇒ 直接改 `FlightBody` |
## | W2 | `_whip.call_deferred()` | 延迟队列比两趟都晚 ⇒ 得走 deferred |
## | W3 | 帧末（`process_frame` 信号之后）焊 | 只有帧末有效 ⇒ 得动 `process_priority` |
##
## W0 是**负对照**：它必须停在 141°，否则说明"焊不焊都一样"，整篇读数作废。
##
## 用法（**不要加 `--headless`** —— 骨架求值链由渲染端推）：
##   "C:/Users/MSIPC/Desktop/Godot_v4.7.1-stable_win64_console.exe" \
##     --path . res://tools/probe_form_weld_timing.tscn

const MODEL := "res://assets/models/xi_movie/xi_movie_rigged.scn"
const CRUISE_IDLE := "res://assets/models/xi/anim/xi_cruise_idle.glb"
const DASH_F := "res://assets/models/xi/anim/xi_dash_f.glb"

const FORM_BONES := [
	"Wing.L", "Wing.R",
	"BinderBack.L", "BinderBack.R",
	"BinderFront.L", "BinderFront.R",
	"RearHang.L", "RearHang.R",
]

## 焊接时机：0 = 不焊，1 = `_process` 内，2 = deferred，3 = 帧末。
var _weld := 0

var _skel: Skeleton3D
var _ma: ModelAnimator
var _mod: CruiseFormModifier
var _normal := {}
var _cruise := {}
var _res := {}


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
		_say("模型里没有 Skeleton3D")
		_finish(1)
		return

	print("")
	print("########## 轮 42：每帧焊的时机（父节点 _process vs 子节点 AnimationPlayer）##########")
	print("")

	_ma = ModelAnimator.setup(inst, [CRUISE_IDLE, DASH_F])
	if not (_ma.has("fly") and _ma.has("cruise_idle") and _ma.has("dash_f")):
		_say("动作缺件 ⇒ 判不了")
		_finish(1)
		return
	_normal = _ma.rotations_at("fly", 0.0)
	_cruise = _ma.rotations_at("cruise_idle")
	_mod = CruiseFormModifier.setup(_skel, _normal, _cruise)
	if _mod == null:
		_say("形态层建不起来（只为读 residual_deg，不参与写入）")
		_finish(1)
		return
	_skel.add_child(_mod)
	_say("① 建体：骨 %d 根 ｜ 探针节点 = 模型实例的**父**（树顺序上先于模型）"
		% _skel.get_bone_count())
	_say("   形态骨 %d 根 ｜ 本探针所有焊接都是**绝对写巡航**" % _mod.form_bone_count())
	print("")

	await _play("dash_f", 10)

	await _phase("W0 不焊（负对照）", 0, 30)
	await _phase("W1 `_process` 内焊", 1, 30)
	await _phase("W2 deferred 焊", 2, 30)
	await _phase("W3 帧末焊", 3, 30)

	print("---- 判决 ----")
	for k in ["W0", "W1", "W2", "W3"]:
		print("  %-3s 离巡航 %7.2f° ｜ Wing.L 骨端 %s" % [k, float(_res[k]), _vfmt(_tip_of("Wing.L"))])
	print("  （巡航真值 0.00° ｜ 常态真值 ≈ 141.36°）")
	print("")
	var r0 := float(_res["W0"])
	var r1 := float(_res["W1"])
	var r2 := float(_res["W2"])
	var r3 := float(_res["W3"])
	if r0 < 8.0:
		print("VERDICT: R42-TIMING-INVALID（W0 负对照没停在常态 ⇒ 读数作废）")
	elif r1 <= 8.0 and r2 <= 8.0 and r3 <= 8.0:
		print("VERDICT: R42-TIMING-ANY（四种时机等效 ⇒ 直接改 `FlightBody._tick_model_anim` 最省）")
	elif r3 <= 8.0 and r1 > 8.0:
		print("VERDICT: R42-TIMING-LATE-ONLY（只有帧末有效 ⇒ 要动 `process_priority` 或 deferred）")
	elif r2 <= 8.0 and r1 > 8.0:
		print("VERDICT: R42-TIMING-DEFERRED（`_process` 太早、deferred 够晚 ⇒ 用 `call_deferred`）")
	else:
		print("VERDICT: R42-TIMING-WEIRD（组合出乎意料，逐条看上面）")
	_finish(0)


## 一个相位：设好焊接时机，跑 `n` 帧，收读数。
func _phase(name: String, mode: int, n: int) -> void:
	print("---- %s ----" % name)
	_weld = mode
	if mode == 1:
		set_process(true)
	else:
		set_process(false)
	_ma.play_loop("dash_f", 0.0, true)
	for i in n:
		await get_tree().process_frame
		if mode == 3:
			_whip("cruise")
		if i % 15 == 14:
			_say("         …帧 %3d ｜ 离巡航 %7.2f° ｜ Wing.L 骨端 %s"
				% [i + 1, _mod.residual_deg(_skel), _vfmt(_tip_of("Wing.L"))])
	_res[name.substr(0, 2)] = _mod.residual_deg(_skel)
	print("")


func _process(_delta: float) -> void:
	if _weld == 1:
		_whip("cruise")
	elif _weld == 2:
		_whip.call_deferred("cruise")


func _play(an: String, n: int) -> void:
	_ma.play_loop(an, 0.0, true)
	await get_tree().process_frame
	for i in n:
		await get_tree().process_frame


## 直接、**绝对**写形态骨（不读当前值）。
func _whip(which: String) -> void:
	for bn in _mod.form_bones(_skel):
		var q: Quaternion = _normal[bn] if which == "normal" else _cruise[bn]
		_skel.set_bone_pose_rotation(_skel.find_bone(bn), q)


func _tip_of(bn: String) -> Vector3:
	var bi := _skel.find_bone(bn)
	if bi < 0:
		return Vector3.ZERO
	var gp := _skel.get_bone_global_pose(bi)
	var l := _skel.get_bone_rest(bi).origin.length()
	return gp.origin + gp.basis * Vector3(0.0, l, 0.0)


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
