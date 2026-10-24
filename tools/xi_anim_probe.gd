extends Node
## 柯西模型骨骼动画的**集成探针**（棒 12 测试官 · 2026-09-26）。
##
## ## 它回答两个问题
##
##   ① **动作进引擎之后真的在动吗**（N28：全仓 0 个 `AnimationPlayer.play()`，
##      交付的 `fly` / `burst` / `burst_cruise` 原本是孤儿）；
##   ② **锚点跟着动作走吗**（N30：`rig_anchor()` 取的是程序化 `SuitRig` 的
##      硬编码佩涅罗佩槽位表，与真模型解剖无关 ⇒ "子弹从肚子里出来"）。
##
## ## 跑法
##
##   # ① 数值（无头，几十秒）
##   Godot_v4.7.1-stable_win64_console.exe --headless --path <工程> \
##       res://tools/xi_anim_probe.tscn
##
##   # ② 出图（**不能加 --headless**，headless 是 dummy 渲染器，抓出来是空的）
##   Godot_v4.7.1-stable_win64_console.exe --path <工程> \
##       res://tools/xi_anim_probe.tscn -- --shots C:/绝对/输出目录
##
## 出图会在每个锚点位置放一颗**彩色小球**（炮口=红、喷口=蓝、其余=黄），
## 于是"锚点落在哪"变成一件肉眼可判的事 —— 数值只能证明"它动了"，
## 证明不了"它动对了"。
##
## ## 为什么它自己造一台机体，而不是去跑一局
##
## 跑一局要地图、要敌人、要胜负条件，噪声大、条件不好复算。这里**只造
## `FlightBody` 本身**：模型装配、包围盒居中、锚点求解、动画绑定全部走
## **生产代码同一条路**（`_build_visual()` → `_setup_model_anim()` →
## `rig_anchor()`），所以量到的是真东西，而不是探针自己搭的平行实现。
##
## ⚠️ 2026-09-26（棒 12）：`profile.model_path` 现在**生产侧也是**带骨的那件了
##（见 `SuitProfile.xi()`），所以这里已经不算"作弊"。仍保留 `--model=` 覆盖，
## 用途改成"对照老资产 `rx105_xi_gundam.glb`"——`--model` 指过去就能量到
## "无骨架、无动作、没形态层"那条完全不同的路径。

const XI_DIR := "res://assets/models/xi/"
## 主实例（它自带的 `fly` 就是待机）。
const PRIMARY := "res://assets/models/xi_movie/xi_movie_rigged.scn"
## ⚠️ 这里**原本有一个 `EXTRAS` 常量**（指向 `XI_DIR` 根目录的 `xi_burst.glb` /
## `xi_burst_cruise.glb`），2026-09-27 删除 —— 两个理由：
##   ① 它**全仓无引用**：本探针的 extras 一律走 `SuitProfile.xi()` 的生产配置
##      （见 `_build_body()` 里的说明，那里也写着「探针不自己再拼一份」）；
##   ② 它指的是 **v12 旧骨架**的完整版，而生产 extras 已是 v14 的 `anim/` 剥壳件。
##      留着一个指向旧骨架的 extras 清单 = 留一个**「半升级」的温床**
##      （N42·十二 的「巡航太丑」就是这么踩进去的：一侧 v12、一侧 v14，**不报错**）。
## ⛔ **`assets/models/xi/xi_burst*.glb` 是 v12 死件，不许再当 extras 用。**

## 要量"锚点跟随"的槽位 —— 与 `SuitProfile` 的 13 根锚点骨同名。
const ANCHORS := [
	"head", "chest", "waist",
	"hand_L", "hand_R", "shield_L", "shield_R",
	"muzzle_L", "muzzle_R",
	"thruster_L", "thruster_R",
	"vulcan_port", "vulcan_stbd",
]

## 出图时每个动作抓几帧。
const SHOT_FRAMES := 5
const SHOT_W := 640
const SHOT_H := 720

## 相机视距余量：`距焦点 = |包围盒对角线| × 本系数`。
##
## ⚠️ 第一版取 1.05，实测**几乎贴脸**：`|对角线| = 41 m ⇒ 距焦点 43 m`，
## 而垂直 fov 34° 在 45.8 m 处才刚好装下 28 m 高的机体 —— 于是机体
## 顶天立地把画面塞满，锚点标记球互相重叠，"机体是什么姿态"反而看不出来。
## 出图是给**人眼**判的，宁可留白也不能塞满。
const SHOT_CAM_MARGIN := 1.7

## 采样窗口（物理帧数，60 Hz）—— 要覆盖最长的动作（`fly` 2.0 s = 120 帧）。
const SAMPLE_FRAMES := 130

var shots_dir := ""
## `--model=<res:// 路径>`：临时换掉 `model_path` 做对照（例如换回生产在用的老资产）。
var model_override := ""
## `--zoom=<系数>`：覆盖相机视距余量。出图取景靠它调。
var shot_margin := SHOT_CAM_MARGIN
var body: FlightBody
var _skel: Skeleton3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var a := str(args[i])
		if a == "--shots" and i + 1 < args.size():
			shots_dir = str(args[i + 1])
		elif a == "--model" and i + 1 < args.size():
			model_override = str(args[i + 1])
		elif a == "--zoom" and i + 1 < args.size():
			shot_margin = float(args[i + 1])

	print("")
	print("################ 柯西骨骼动画 · 集成探针 ################")
	_build_body()
	_checkpoint("建体后")
	# 两帧让场景就绪（模型进树、包围盒量好）。
	await get_tree().physics_frame
	await get_tree().physics_frame
	_checkpoint("两个物理帧后")
	if body == null:
		print("!! 机体没建起来，探针无法继续")
		print("VERDICT: XI-ANIM-PROBE-ABORTED")
		get_tree().quit(2)
		return

	_report_binding()
	_report_anchors()
	_checkpoint("锚点段后")
	await _report_playback()
	_checkpoint("采样段后")
	_report_muzzles()
	_report_extent()
	await _report_form_gap()
	await _report_form_bones()
	await _report_form_layer()
	await _report_tick_progress()
	if shots_dir != "":
		await _shoot()
	# 收尾：把机体与模型的资源显式放掉再退。
	# 不这样做，退出时 Godot 会刷几百行
	# `RID allocations ... were leaked at exit` / `Leaked instance dependency`
	# —— 那是**正常的**（dummy 渲染器 + 进程直接退），但会把真报错淹掉。
	if body != null and is_instance_valid(body):
		body.free()
	body = null
	_skel = null
	await get_tree().process_frame
	print("")
	print("VERDICT: XI-ANIM-PROBE-DONE")
	get_tree().quit(0)


## 探针各段之间的**体检点**。
##
## 存在的理由：`model_root.visible` 一旦被翻成 false，`_measure_visible_meshes()`
## 就返回空盒子、出图取景崩掉，而**代码不发任何警告**。2026-09-26 出图第一版
## 拍到的就是"一片粉色圆盘"（事后查明是别处的销毁特效），排查花了很久，
## 根子就是"没有分段体检、不知道是什么时候翻的"。
func _checkpoint(tag: String) -> void:
	if body == null:
		print("[体检:%s] body = null" % tag)
		return
	var vis := "?"
	var n := 0
	if is_instance_valid(body.model_root):
		vis = str(body.model_root.visible)
		n = body.model_root.find_children("*", "MeshInstance3D", true, false).size()
	print("[体检:%s] model_root.visible=%s  MeshInstance3D=%d  hp=%.1f  物理=%s  self=%d  root=%d"
		% [tag, vis, n, body.hp, str(body.is_physics_processing()), body.get_instance_id(),
		   body.model_root.get_instance_id() if is_instance_valid(body.model_root) else -1])


## 用生产代码组装一台柯西：**只把 model_path 换成带骨的那件**。
func _build_body() -> void:
	var p := SuitProfile.xi()
	# ⚠️ **只改 `model_path`**：`model_anim_files` 已经在 `SuitProfile.xi()` 里
	# 配好了（`fly` 来自主实例、另两件靠 `ModelAnimator` 摘过来）。
	# 探针不自己再拼一份，免得"探针里的配置"和"生产里的配置"分叉 ——
	# 那正是这个工程反复吃亏的一类 bug。
	p.model_path = PRIMARY
	if model_override != "":
		p.model_path = model_override
		print("[装配] ⚠️ model_path 被命令行覆盖为 %s" % model_override)
	var holder := Node3D.new()
	holder.name = "Holder"
	add_child(holder)
	body = FlightBody.new()
	body.name = "XiBody"
	body.profile = p
	body.is_player = true
	body.use_placeholder = false
	# 出图/量锚点时把前倾角归零：18° 的飞行姿态会让"炮口朝哪"更难读。
	body.flight_pitch_deg = 0.0
	holder.add_child(body)
	# ⚠️⚠️ **进来就把物理冻住，而且全程不许解冻。**
	#
	# 探针造的是一个**没有地图、没有海面的空世界**。物理一开，机体在第一个
	# 物理帧就往下掉，几帧内触发 `destroy(null, "撞海")` —— 而 `destroy()`
	# 做的第一件事就是 `model_root.visible = false`。
	#
	# 后果是**出图彻底不可用且不报任何错**：`_measure_visible_meshes()` 返回空盒子、
	# 相机取景按空盒子算、抓到的"机体"其实是 `FX.explosion` 的爆炸碎片云
	#（一片粉色圆盘，2026-09-26 出图第一版就是这个，排查代价很高）。
	#
	# 探针只关心**局部姿态与锚点**，不关心世界位置 ⇒ 冻结没有副作用。
	body.set_physics_process(false)
	# `display_name` 的 `@export` 默认值是 `"MESSER"`，正常流程靠 `_begin_form()`
	# 从 profile 覆盖；探针不走进场流程 ⇒ 不显式设一下，日志里这台柯西会自称
	# "梅萨"，排查时会被带偏（这次就被带偏了）。
	body.display_name = p.display_name
	print("[装配] profile=%s  model=%s" % [p.display_name, p.model_path])
	print("        model_anim_files=%s" % str(p.model_anim_files))


func _report_binding() -> void:
	print("")
	print("========== ① 绑定实况 ==========")
	print("  rig（占位骨架）      = %s" % ("有" if body.rig != null else "无"))
	_skel = null
	if body.model_anim == null:
		print("  !! model_anim 为空 —— 绑定没建起来")
		return
	print("  model_anim.ready     = %s" % body.model_anim.ready)
	var sk := body._model_skel as Skeleton3D
	_skel = sk
	print("  模型自带 Skeleton3D  = %s" % ("有，%d 根骨" % sk.get_bone_count() if sk != null else "无"))
	print("  可播动作             = %s" % str(body.model_anim.action_names()))
	print("  当前动作             = '%s'" % body.model_anim.current)
	# 锚点来源必须逐条点名：这是"绑定到底生效没有"的唯一直接证据。
	var from_model := 0
	for a: String in ANCHORS:
		var ok: bool = body.anchor_from_model(a)
		if ok:
			from_model += 1
		print("    锚点 %-13s 来源 = %s" % [a, "模型骨架" if ok else "占位骨架(回退)"])
	print("  ⇒ 从模型骨架取的锚点 = %d / %d" % [from_model, ANCHORS.size()])


## 锚点"取自哪里"只说明接线对了，还要说明**它和不取模型骨架时差多少**
## —— 差得越多，说明原来错得越多。
func _report_anchors() -> void:
	print("")
	print("========== ② 锚点：模型骨架 vs 占位骨架 ==========")
	var h := maxf(body.model_bounds.size.y, 0.001)
	print("  （偏差按机体全高 %.2f m 折算百分比。占位骨架是一张**佩涅罗佩线稿**表，" % h)
	print("    柯西与它解剖不对上 —— 所以这些差值就是「原来的锚点跑偏量」。）")
	print("  %-13s %-26s %10s %9s" % ["槽位", "模型锚点 (x, y, z) m", "偏差(m)", "占全高"])
	var worst := 0.0
	var worst_name := ""
	for a: String in ANCHORS:
		var m: Vector3 = body.rig_anchor(a)
		var s: Vector3 = _suit_rig_anchor(a)
		var d := m.distance_to(s)
		if d > worst:
			worst = d
			worst_name = a
		print("  %-13s (%8.2f,%8.2f,%8.2f) %10.3f %8.2f%%" % [
			a, m.x, m.y, m.z, d, d / h * 100.0])
	print("  ⇒ 最大偏差 %.3f m（%s）= 全高的 %.1f%%" % [worst, worst_name, worst / h * 100.0])
	# 柯西单手持枪 ⇒ 两个槽位语义相同，应当**重合**（BONE-SPEC §7.4·N5）。
	var ml: Vector3 = body.rig_anchor("muzzle_L")
	var mr: Vector3 = body.rig_anchor("muzzle_R")
	print("  muzzle_L 与 muzzle_R 距离 = %.9f m（模型骨架；N5 单手持枪 ⇒ 应当 0）"
		% ml.distance_to(mr))
	var sl: Vector3 = _suit_rig_anchor("muzzle_L")
	var sr: Vector3 = _suit_rig_anchor("muzzle_R")
	print("  同上（占位骨架）           = %.3f m（佩涅罗佩两门前臂炮，本来就不重合）"
		% sl.distance_to(sr))
	# 锚点跟随误差：反算回世界坐标，与骨的真实世界位姿比。同源 ⇒ 应当 ≈ 0。
	print("  anchor_follow_error（与世界骨位姿之差，米）：")
	for a: String in ["muzzle_L", "muzzle_R", "thruster_L", "hand_R", "head"]:
		print("    %-11s = %.9f" % [a, body.anchor_follow_error(a)])


## 逐动作播一遍，量"骨头到底动没动"。
##
## ⚠️ 采的是**骨架空间**的骨原点（`get_bone_global_pose().origin`），
## 不是世界坐标 —— 世界坐标里含着"机体自己在飞"的位移，
## 会把"动作没播"伪装成"动了很多"。
func _report_playback() -> void:
	print("")
	print("========== ③ 动作真的在播吗 ==========")
	if _skel == null:
		print("  !! 没有骨架，跳过")
		return
	# 让位：把 FlightBody 的每帧逻辑停掉，免得它的 `_tick_model_anim()`
	# 把一次性动作播完就切回待机（那会把采样窗口截断）。
	body.set_physics_process(false)
	var n := _skel.get_bone_count()
	var names: Array = body.model_anim.action_names()
	print("  %-16s %8s %7s %10s %12s %12s" % [
		"动作", "时长(s)", "轨道", "动过的骨", "最大位移(m)", "锚点行程(m)"])
	for nm: String in names:
		var ap := body.model_anim.player
		var anim := ap.get_animation(nm)
		ap.play(nm)
		ap.seek(0.0, true)
		await get_tree().process_frame
		var first := _origins()
		var muzzle0: Vector3 = body.rig_anchor("muzzle_R")
		var thr0: Vector3 = body.rig_anchor("thruster_L")
		var suit0: Vector3 = _suit_rig_anchor("muzzle_R")
		var skel0: Vector3 = _skel.global_transform.origin
		var mb := body._bone_index("muzzle_R")
		var moved := {}
		var max_disp := 0.0
		var muzzle_travel := 0.0
		var thr_travel := 0.0
		var bone_travel := 0.0
		var skel_travel := 0.0
		var suit_travel := 0.0
		for _f in SAMPLE_FRAMES:
			await get_tree().process_frame
			var cur := _origins()
			for i in n:
				var a0: Vector3 = first[i]
				var a1: Vector3 = cur[i]
				var d: float = a0.distance_to(a1)
				if d > 1.0e-5:
					moved[i] = true
				if d > max_disp:
					max_disp = d
			if mb >= 0:
				var bm: Vector3 = first[mb]
				var bc: Vector3 = cur[mb]
				bone_travel = maxf(bone_travel, bm.distance_to(bc))
			skel_travel = maxf(skel_travel, skel0.distance_to(_skel.global_transform.origin))
			muzzle_travel = maxf(muzzle_travel, muzzle0.distance_to(body.rig_anchor("muzzle_R")))
			thr_travel = maxf(thr_travel, thr0.distance_to(body.rig_anchor("thruster_L")))
			# ★ 对照：**同一时刻**占位骨架那条路的炮口行程。它恒为 0
			#（占位槽位是静态 Node3D，动作带不动它）—— 这就是 N30 那句
			# "动作播起来时模型在动、锚点不动"的实测读数。
			suit_travel = maxf(suit_travel, suit0.distance_to(_suit_rig_anchor("muzzle_R")))
		print("  %-16s %8.4f %7d %10d %12.4f %12.4f" % [
			nm, anim.length, anim.get_track_count(), moved.size(), max_disp, muzzle_travel])
		print("       （轨道明细：%d 条；位移 %d / 旋转 %d）"
			% [anim.get_track_count(), _track_count(anim, Animation.TYPE_POSITION_3D),
				_track_count(anim, Animation.TYPE_ROTATION_3D)])
		# ⚠️ 全部是**世界米**（同一口径）。`skeleton 节点位移` 是自检疫：
		# 它不为 0 就说明"机体自己在飞"混进了读数，锚点行程要打折看。
		print("       （muzzle_R 骨 idx=%d 骨位移 %.4f m · 锚点行程 %.4f m · thruster_L 锚点行程 %.4f m · skeleton 节点位移 %.4f m）"
			% [mb, bone_travel, muzzle_travel, thr_travel, skel_travel])
		print("       ★ 对照：同一动作下**占位骨架**的炮口行程 = %.4f m（旧路径，恒 0 ⇒ N30 成立）"
			% suit_travel)
		ap.stop()
	# ⚠️ **这里不恢复 `set_physics_process(true)`。**
	# 恢复的话，下一个物理帧机体就会坠落 → `destroy("撞海")` → `model_root.visible = false`
	# → 后面的 `_report_extent()` 与出图全部作废（见 `_build_body()` 里那段说明）。
	# 采样靠的是 `AnimationPlayer` 自己的 `_process`，与物理无关。


func _track_count(a: Animation, type: int) -> int:
	var c := 0
	for i in a.get_track_count():
		if a.track_get_type(i) == type:
			c += 1
	return c


## **旧路径**：完全照抄 `FlightBody.rig_anchor()` 在绑定之前的算法
##（`model_pivot.transform * (model_root.position + rig.transform * s.position)`）。
##
## 留一份在这里，是为了能在**同一时刻同一动作**下拿到 A/B 两个读数 ——
## 没有它，"锚点现在会跟了"只是一句没有对照的话。
func _suit_rig_anchor(slot: String) -> Vector3:
	if body.rig == null:
		return Vector3.ZERO
	var s := body.rig.slot(slot)
	if s == null:
		return Vector3.ZERO
	return body.model_pivot.transform * (body.model_root.position + body.rig.transform * s.position)


## 骨原点，**世界空间**（= 游戏米）。
##
## ⚠️ 第一版取的是 `get_bone_global_pose().origin`，那是**骨架空间**、
## 单位是**模型原生单位**（本机全高 0.9814）。而 `rig_anchor()` 返回的是
## **游戏米**，中间隔着 `inst.scale = target_height / native_height ≈ 28.53` 倍。
## 两个口径混在一条表里会读成"骨头只动了 0.125 m、锚点却动了 3.58 m"，
## 差**正好 28.53 倍** —— 那 28.53 就是缩放，不是 bug。
## 统一到世界空间之后两个数直接可比（实测 `skeleton 节点位移 = 0`，
## 即"机体自己在飞"没有污染读数）。
func _origins() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var xf := _skel.global_transform
	for i in _skel.get_bone_count():
		out.append((xf * _skel.get_bone_global_pose(i)).origin)
	return out


## 生产侧真正会用的那两个开火点。
func _report_muzzles() -> void:
	print("")
	print("========== ④ 生产侧实际用的炮口（`_muzzle_local`） ==========")
	var ms: Array = body._muzzle_local
	if ms.is_empty():
		print("  !! 空 —— `_collect_muzzles()` 没产出炮口")
		return
	for i in ms.size():
		var v: Vector3 = ms[i]
		print("  muzzle[%d] = (%.4f, %.4f, %.4f)  离原点 %.4f m  占全高 %.1f%%" % [
			i, v.x, v.y, v.z, v.length(), v.length() / maxf(body.model_bounds.size.y, 0.001) * 100.0])
	if ms.size() >= 2:
		print("  两开火点间距 = %.6f m" % (ms[0] as Vector3).distance_to(ms[1]))


## 包围盒复核 —— **这一段的唯一目的，是抓"建体时把零件量漏了"这个时序坑。**
##
## `model_bounds` 是在 `_center_and_measure()` 那一刻量的，之后模型可能：
##   * 有零件才变可见（`is_visible_in_tree()` 当时还是 false ⇒ 被 `continue` 跳过）；
##   * 有零件的位置才被父级摆好。
## 两种都会让 `model_bounds` **偏小**，而 **`model_bounds` 正是出图取景的依据**
## ⇒ 相机贴着机体拍，抓出来一片认不出的碎片，**且不报任何错**。
##
## 所以这里"再量一次"，让两者之差变成一个可读的数（应当 ≈ 0）。
func _report_extent() -> void:
	print("")
	print("========== ⑥ 包围盒复核（查量漏零件） ==========")
	var b := body.model_bounds
	print("  model_bounds（建体时记下） = pos %s  size %s" % [str(b.position), str(b.size)])
	var now := body._measure_visible_meshes()
	print("  现在再量一次（可见网格并集）= pos %s  size %s" % [str(now.position), str(now.size)])
	var d := (now.size - b.size).length()
	print("  尺寸之差 = %.4f m（应当 ≈ 0；明显 > 0 ⇒ 建体时量漏了零件）" % d)
	var n := 0
	for c: Node in body.model_root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi != null and mi.mesh != null and mi.is_visible_in_tree():
			n += 1
	print("  当前可见 MeshInstance3D = %d 个" % n)
	# ---- 诊断：把 `model_root` 这一支的实况摊开 ----
	print("  --- 诊断 ---")
	print("  body.visible = %s  body.is_visible_in_tree() = %s"
		% [str(body.visible), str(body.is_visible_in_tree())])
	if is_instance_valid(body.model_pivot):
		print("  model_pivot('%s').visible = %s  子节点 = %d"
			% [body.model_pivot.name, str(body.model_pivot.visible), body.model_pivot.get_child_count()])
	else:
		print("  !! model_pivot 无效")
	if is_instance_valid(body.model_root):
		print("  model_root('%s').visible = %s  子节点 = %d"
			% [body.model_root.name, str(body.model_root.visible), body.model_root.get_child_count()])
		for c: Node in body.model_root.get_children():
			print("     - %s (%s) 子 = %d" % [c.name, c.get_class(), c.get_child_count()])
		print("  model_root 全部后代 = %d 个" % body.model_root.find_children("*", "", true, false).size())
		var meshes := body.model_root.find_children("*", "MeshInstance3D", true, false)
		print("  MeshInstance3D 后代 = %d 个" % meshes.size())
		var vis := 0
		for m: Node in meshes:
			if (m as MeshInstance3D).is_visible_in_tree():
				vis += 1
		print("  其中 is_visible_in_tree() = %d 个" % vis)
	else:
		print("  !! model_root 无效")
	if d > 1.0:
		print("  ★★ 结论：包围盒**确实量漏了** —— 出图取景会贴着机体，必须先修这个。")
	else:
		print("  ⇒ 包围盒一致，取景依据可信。")


## ⑦ 巡航姿态 vs 常态姿态：**交付里没有"巡航版循环动作"时，跳变有多大**。
##
## ## 这一段的由来
##
## 交付的三个动作里，`burst_cruise` 是**一次性**的巡航发射动作（40 帧），
## `fly` 是**常态**的待机循环。**没有一个"巡航待机循环"动作** —— 但这没关系，
## 上游 GUIDE §6.7 的架构本来就是「**morph 管形态、骨骼管过程**」：
## 待机永远播 `fly`，巡航的形态由**另一层**叠加上去。
##
## 柯西的巡航形态有**两条并列的载体**（`_tick_cruise_morph()` 里谁在场谁生效）：
##   ① **blend shape**（morph）—— 老资产 `rx105_xi_gundam.glb` 带 1 个，
##      `cruise_morph` 0→1 驱动它；
##   ② **骨骼形态层** —— 新资产（`blend shape = 0`）走这条。这一层自身还有
##      **两档**（在 `_setup_cruise_form()` 里二选一）：
##        * **曲线层** `FormCurveModifier`（N42·十三）：沿 `xi_morph_anim3.glb`
##          的变形曲线走 ⇒ 翼板**分段**展开（先肩板 `Binder*`、再翼板 `Wing*`）；
##        * **两点层** `CruiseFormModifier`：常态 → 巡航**匀速 slerp**（回退路径）。
##      两者都按 `cruise_morph` 驱动，形态骨 6 根（读数见 ⑩ 段）。
##
## ⚠️ 2026-09-26 之前这里写的是"新资产上 `cruise_morph` 完全不产生作用" ——
## 那是**当时的实况**，现在已经被 ② 补上（见本文件 ⑩ 段与 `xi_form_*.png`）。
## 本段（⑦）的读数仍然有效：它量的是**动作本身**的姿态差，不含形态层。
##
## 这段把那个跳变**量成一个数**，而不是留一句"应该会跳"。
func _report_form_gap() -> void:
	print("")
	print("========== ⑦ 巡航姿态 vs 常态姿态（形态跳变量） ==========")
	# ---- 先实测：这个模型上到底有几个 blend shape ----
	var bs := 0
	var mesh_n := 0
	for c: Node in body.model_root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var am := (mi.mesh as ArrayMesh) if mi != null else null
		if am != null:
			mesh_n += 1
			bs += am.get_blend_shape_count()
	print("  模型 blend shape 总数 = %d（ArrayMesh %d 个）" % [bs, mesh_n])
	print("  profile.cruise_morph（柯西跑不跑 morph 链）= %s  当前 cruise_morph = %.3f"
		% [str(body.profile.cruise_morph), body.cruise_morph])
	if bs == 0:
		print("  ⇒ 本模型**没有 blend shape** ⇒ 它的巡航形态**由骨骼承载**：")
		print("     `cruise_morph` 在这里不写 blend shape，而是喂给骨骼形态层")
		print("     （形态层两档：曲线层 FormCurveModifier ／ 两点层 CruiseFormModifier；")
		print("       见 ⑩ 段）—— 两条并列通路，谁在场谁生效。")
	var ap := body.model_anim.player
	if ap == null:
		print("  !! 没有播放器，跳过")
		return
	# ---- 自检：`seek` 到底生不生效 ----
	# 拿 `fly` 自己两个时刻比。差为 0 ⇒ seek 没生效，下面的对比全部无意义。
	var fly_a: Dictionary = await _anchors_at(ap, "fly", 0.0)
	var fly_b: Dictionary = await _anchors_at(ap, "fly", 1.0)
	var selfmax := 0.0
	for a: String in ANCHORS:
		var va: Vector3 = fly_a[a]
		var vb: Vector3 = fly_b[a]
		selfmax = maxf(selfmax, va.distance_to(vb))
	print("  [自检] fly 自身 t=0 与 t=1.0 的锚点最大差 = %.4f m（必须 > 0，否则 seek 没生效）"
		% selfmax)
	if selfmax < 1.0e-4:
		print("  ★★ 自检失败：seek 没有驱动骨架 ⇒ 下面的对比无意义，先修探针。")
		return
	# ---- ① 起始姿态：两个动作是不是从同一个基准起手 ----
	var fly0: Dictionary = fly_a
	var bc0: Dictionary = await _anchors_at(ap, "burst_cruise", 0.0)
	if fly0.is_empty() or bc0.is_empty():
		print("  !! 取不到动作，跳过")
		return
	var start_max := 0.0
	for a: String in ANCHORS:
		var v0: Vector3 = fly0[a]
		var v1: Vector3 = bc0[a]
		start_max = maxf(start_max, v0.distance_to(v1))
	print("  ① 起始姿态：fly 首帧 vs burst_cruise 首帧，13 个锚点最大差 = %.4f m" % start_max)
	if start_max < 1.0e-4:
		print("     ⇒ 两个动作都从**同一个基准姿态**起手（不是各存了一版形态）。")
		print("       所以「差异」只能靠动作过程体现，拿首帧判形态是判不出来的。")
	else:
		print("     ⇒ 两者起始姿态不同。")

	# ---- ② ★ 真正会发生的跳变：burst_cruise 播完 → 状态机回待机播 fly ----
	# 这才是"巡航姿态用得对不对"的实际后果：巡航发射一结束，模型会切回 fly 的骨骼，
	# 也就是切回**常态布局**。量它有多大。
	var fly_start := await _bones_at(ap, "fly", 0.0)
	var bc_len := ap.get_animation("burst_cruise").length
	var bc_end := await _bones_at(ap, "burst_cruise", bc_len)
	if fly_start.is_empty() or fly_start.size() != bc_end.size():
		print("  !! 全骨采集失败，跳过 ②")
		return
	var worst := 0.0
	var worst_i := -1
	var sum := 0.0
	for i in fly_start.size():
		var dd := fly_start[i].distance_to(bc_end[i])
		sum += dd
		if dd > worst:
			worst = dd
			worst_i = i
	var h2 := maxf(body.model_bounds.size.y, 0.001)
	var bn := "?"
	if _skel != null and worst_i >= 0:
		bn = _skel.get_bone_name(worst_i)
	print("  ② 【跳变】burst_cruise 末帧 → fly 首帧（= 状态机回待机时的实际切换）：")
	print("     全身 %d 根骨：最大位移 %.3f m（骨 %s）= 全高的 %.1f%%，平均 %.3f m"
		% [fly_start.size(), worst, bn, worst / h2 * 100.0, sum / float(fly_start.size())])
	if worst > 1.0:
		print("     ⇒ 这是**动作本身**的姿态差（`burst_cruise` 末帧 vs `fly` 首帧）。")
		print("       ⚠️ 本段走帧边界读骨位，**不含**巡航形态层的贡献 —— 所以它")
		print("          量的是「如果只做动作混合会差多少」，是最坏情况。")
		print("       主贡献正是 ⑨ 段那 8 根形态骨，也就是「巡航形态 vs 常态形态」的差；")
		print("       形态层（⑩ 段）接住它之后，巡航形态下播 `fly` 画面上不再被压回常态。")
		print("       残余的是腿/手等**过程骨**的小差异，量级见 ⑨ 段的第 9 名往后。")
	else:
		print("     ⇒ 跳变很小，巡航/常态互切可以接受。")


## ⑩ 「巡航形态层」实测：它到底有没有把形态骨改到位，以及**会不会漂移**。
##
## ⚠️ 量的是**形态骨的世界位置**，不是锚点 —— 形态骨（`Wing` / `Binder` /
## `RearHang`）**全在 13 个锚点之外**，所以 `rig_anchor()` 根本看不到形态。
## "锚点都对"证明不了"形态对"。这是上一轮把缺口漏掉的直接原因之一。
## 取当前的形态层实例。
##
## ★ 形态层**有两档**（N42·十三）：**曲线层** `FormCurveModifier`（沿
## `xi_morph_anim3.glb` 的变形曲线走）优先，建不起来就**回退**两点层
## `CruiseFormModifier`。两档的**公共接口刻意同构**
##（`form_bones` / `cruise_rotation_of` / `morph` / `calls` /
## `read_residual_deg` / `last_applied_deg` / `_process_modification`），
## 所以这里统一返回基类、用 `call()`/`get()`/`set()` 动态访问 ——
## **不必为两档写两遍报告**（写两遍迟早会漏判一档）。
func _form_layer() -> SkeletonModifier3D:
	if body._form_curve != null:
		return body._form_curve
	return body._cruise_form


## 形态层当前走的是哪一档（人读）。
func _form_layer_kind() -> String:
	if body._form_curve != null:
		return "**曲线层** FormCurveModifier（N42·十三 · 沿 xi_morph_anim3 曲线行走）"
	if body._cruise_form != null:
		return "两点层 CruiseFormModifier（常态→巡航匀速 slerp · 曲线层不可用时的回退）"
	return "无"


## 在**指定 morph** 下、某根形态骨的目标姿态。
##
## 两档的取法不同（曲线层是在曲线上按 `morph` 取点；两点层是
## `slerp(常态, 巡航, morph)`），但**语义相同**：`morph=0` ⇒ 常态、
## `morph=1` ⇒ 巡航形态。做成 helper 是为了让上面那张表**只写一次**。
func _form_target_at(bone_idx: int, morph: float, normal: Dictionary,
		cruise: Dictionary, bone_name: String) -> Quaternion:
	if body._form_curve != null:
		var keep: float = body._form_curve.morph
		body._form_curve.morph = morph
		var q := body._form_curve.curve_target_of(bone_idx)
		body._form_curve.morph = keep
		return q
	# 两点层：与 `CruiseFormModifier._process_modification()` 同式。
	var q0: Quaternion = normal[bone_name]
	var q1: Quaternion = cruise[bone_name]
	return q0.slerp(q1, clampf(morph, 0.0, 1.0))


func _report_form_layer() -> void:
	print("")
	print("========== ⑩ 巡航形态层实测 ==========")
	var ap := body.model_anim.player
	var mod := _form_layer()
	print("  形态层档位：%s" % _form_layer_kind())
	if mod == null:
		print("  !! 形态层没建起来（`_setup_cruise_form()` 没产出）")
		print("     可能原因：无骨架 / 无 idle 动作 / 无巡航版发射动作 / 挑不出形态骨")
		return
	if _skel == null or ap == null:
		print("  !! 缺骨架或播放器")
		return
	var bones: Array = mod.call("form_bones", _skel)
	print("  形态层判定出 **%d 根**形态骨：" % bones.size())
	var bl := PackedStringArray()
	for b in bones:
		bl.append(str(b))
	print("    %s" % ", ".join(bl))
	# ---- 曲线层独有的两条读数 ----
	if mod.get("key_count") != null:
		print("  [曲线层] 各骨关键帧数（取最小）%s ｜ 端点自检最大偏差 %.3f°"
			% [str(mod.get("key_count")), float(mod.get("endpoint_max_deg"))])
		print("           ← Godot 对 CUBICSPLINE 会**抽稀**，各骨帧数**不同**、间隔不等；")
		print("             曲线层按**真实时间轴**取值，所以各骨节奏仍然对齐。")
		print("           在变形动画里没有独立曲线、退回两点线性的骨 = %s"
			% str(mod.get("fell_back")))
		# ★ 分段演出的**数值证据**：逐档打印各形态骨的目标角（相对常态）。
		# 两点层是**线性**的（各骨同比例）；曲线层是**分段**的
		#（Binder 先动完、Wing 还没动）。这一条比出图更早、更硬。
		var normal := body.model_anim.rotations_at(body.model_anim.idle_action, 0.0)
		var cruise := body.model_anim.rotations_at(body.model_anim.burst_cruise_action)
		print("  [曲线形状] 各形态骨在 morph 各档下、离常态的角度（°）")
		print("     ★ 两点层会是**每列同比例增长**；曲线层是**分段**的"
			+ "（Binder 先动完时 Wing 仍是 0）。")
		var hdr := "    %-16s" % "骨(morph→)"
		for s in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]:
			hdr += "%9.2f" % float(s)
		print(hdr)
		for b: String in bl:
			var bi := _skel.find_bone(b)
			if bi < 0 or not normal.has(b) or not cruise.has(b):
				continue
			var q0: Quaternion = normal[b]
			var row := "    %-16s" % b
			for s in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]:
				var q := _form_target_at(bi, float(s), normal, cruise, b)
				row += "%9.2f" % rad_to_deg(q.angle_to(q0))
			print(row)
		# 复位，免得影响后面的读数
		mod.set("morph", 0.0)
	var c0: int = mod.get("calls")
	print("  [驱动] 进入本段时 `_process_modification()` 已被调用 %d 次" % c0)
	# ---- 同期诊断：同一帧内手动调一次回调，立刻回读 raw pose ----
	# 目的：把「回调压根没跑」与「跑了但写不进 / 被覆盖」分开。
	# 这是本类最容易踩的一刀 —— `SkeletonModifier3D` 的写入只影响
	# **求值链里的那次求值**，而 `get_bone_pose_rotation()` 是 raw 数据，
	# 帧边界读很可能读不到它，从而把"生效"误判成"没生效"。
	var tb: int = -1
	for b: String in bones:
		tb = _skel.find_bone(b)
		if tb >= 0:
			break
	if tb >= 0:
		var qb := _skel.get_bone_pose_rotation(tb)
		var qtarget: Quaternion = mod.call("cruise_rotation_of", tb)
		mod.set("morph", 1.0)
		mod.call("_process_modification")
		var qa := _skel.get_bone_pose_rotation(tb)
		print("  [同期诊断] 手动调一次回调，骨 %s：" % _skel.get_bone_name(tb))
		print("     离巡航姿态 %.2f° → %.2f°（有效的话应变成 ≈0）"
			% [rad_to_deg(qb.angle_to(qtarget)), rad_to_deg(qa.angle_to(qtarget))])
		print("     `last_applied_deg`（回调内部算的）= %.2f°" % float(mod.get("last_applied_deg")))
		if rad_to_deg(qa.angle_to(qtarget)) < 1.0:
			print("     ⇒ 写入路径**有效**（同一帧内写进去、读得到）。")
			print("       那么帧边界读不到，只说明写入被 AnimationPlayer 每帧覆盖 ——")
			print("       这在渲染求值链里是**正常**的，最终出图会体现。")
		else:
			print("     ★★ 写入路径**无效**：同一帧内写进去也读不到。")
	# ---- 冻结播放头（`speed_scale = 0`），让读数不受 fly 自身进度干扰 ----
	ap.play("fly")
	ap.seek(0.0, true)
	ap.speed_scale = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	var idxs: Array[int] = []
	for b: String in bones:
		idxs.append(_skel.find_bone(b))
	var p0 := _bone_world(idxs)
	mod.set("morph", 1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var p1 := _bone_world(idxs)
	var h := maxf(body.model_bounds.size.y, 0.001)
	var worst := 0.0
	var worst_b := ""
	var tot := 0.0
	print("  %-16s %10s %10s %10s" % ["骨名", "常态 y(m)", "巡航 y(m)", "位移(m)"])
	for i in idxs.size():
		var d: float = p0[i].distance_to(p1[i])
		tot += d
		if d > worst:
			worst = d
			worst_b = bones[i]
		print("  %-16s %10.3f %10.3f %10.3f" % [bones[i], p0[i].y, p1[i].y, d])
	print("  ⇒ 最大位移 %.4f m（%s）= 全高的 %.1f%%；平均 %.4f m"
		% [worst, worst_b, worst / h * 100.0, tot / float(maxi(idxs.size(), 1))])
	if worst < 0.01:
		print("  ⚠️ 帧边界读到的世界位置**没有变化**。这不是实现失败，是**观测口径**问题：")
		print("     `_process_modification()` 的写入只在**渲染求值链那次求值**里生效；")
		print("     帧边界的 raw pose / global pose 已被 `AnimationPlayer` 每帧覆盖。")
		print("     ⇒ 本段能证明「形态骨挑对了」「写入路径有效」（见上面的同期诊断），")
		print("       证明不了「画面上生效了」—— 那一半在 ⑤ 段的 `xi_form_m*.png` 对照图里。")
	else:
		print("  ✓ 形态层生效（连帧边界都读到了变位）。")
	# ---- ★ 漂移自检（**必须读回调内部的读数**）----
	# 帧边界的 `residual_deg()` 永远是原始值，读不出漂移 —— 只有
	# `read_residual_deg`（回调内记录的第一根骨夹角）在帧间的变化才算数：
	#   稳定 ⇒ 每帧都从动画原始值出发 ✓；单调减向 0 ⇒ 读到了自己上一帧写的值 ✗。
	mod.set("morph", 0.5)
	var seq: Array[float] = []
	for i in 6:
		await get_tree().process_frame
		seq.append(float(mod.get("read_residual_deg")))
	var drift := seq[seq.size() - 1] - seq[0]
	var line := ""
	for v in seq:
		line += "%.2f " % v
	print("  [漂移自检] morph=0.5，回调**内部**读到的残余角连续 6 帧（°）：%s" % line)
	print("             首末差 = %+.3f°（应 ≈ 0；单调减向 0 ⇒ 漂移，时机不对必须修）" % drift)
	if absf(drift) > 1.0:
		print("  ★★ 漂移确认：`_process_modification()` 读到了自己上一帧写的值。")
	elif int(mod.get("calls")) - c0 == 0:
		print("  ★★ 回调**一次都没被调** ⇒ 引擎没在驱动它（headless？没进求值链？）")
	else:
		print("  ✓ 无漂移：每帧都从动画原始值出发，形态稳定。")
	print("  [驱动] 本段结束时 `_process_modification()` 调用次数 = %d（比进入时 +%d）"
		% [int(mod.get("calls")), int(mod.get("calls")) - c0])
	mod.set("morph", 0.0)
	ap.speed_scale = 1.0
	ap.stop()


## 若干根骨的**世界原点**（形态层效果只能从这里看）。
func _bone_world(idxs: Array[int]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if _skel == null or not is_instance_valid(_skel):
		return out
	var xf := _skel.global_transform
	for i in idxs:
		out.append((xf * _skel.get_bone_global_pose(i)).origin)
	return out


## ⑨ 形态骨清单：**引擎实测**，不照抄上游 `ref_pose_cruise.json`。
##
## 做法：同一具骨架，比 `fly` 首帧 与 `burst_cruise` 末帧 的**逐骨局部旋转**。
## 差显著的骨就是"形态骨" —— 巡航形态的真正载体。
##
## ⚠️ **不能用世界位置差**：位置会把"父级带动"算进来（父级转了、子骨没转，
## 位置照样差）。形态层要叠加的是**旋转**，所以必须比旋转。
## 这一步也是给 2026-09-26「巡航形态在 Godot 侧没接」提供**引擎侧的第一手清单**。
func _report_form_bones() -> void:
	print("")
	print("========== ⑨ 形态骨清单（引擎实测：fly 首帧 vs burst_cruise 末帧） ==========")
	var ap := body.model_anim.player
	if ap == null or _skel == null or not is_instance_valid(_skel):
		print("  !! 没有播放器/骨架，跳过")
		return
	if not ap.has_animation("fly") or not ap.has_animation("burst_cruise"):
		print("  !! 动作不全，跳过")
		return
	var r_norm := await _bone_rots_at(ap, "fly", 0.0)
	var bc_len := ap.get_animation("burst_cruise").length
	var r_cruise := await _bone_rots_at(ap, "burst_cruise", bc_len)
	if r_norm.is_empty() or r_norm.size() != r_cruise.size():
		print("  !! 采不到，跳过")
		return
	# 自检：同动作两个时刻必须不同，否则又是「seek 没生效」那类假读数
	var r_fly1 := await _bone_rots_at(ap, "fly", 1.0)
	var selfmax := 0.0
	for i in r_norm.size():
		selfmax = maxf(selfmax, r_norm[i].angle_to(r_fly1[i]))
	print("  [自检] fly 自身 t=0 vs t=1.0 的最大骨旋转差 = %.4f°（必须 > 0）"
		% rad_to_deg(selfmax))
	if selfmax < 1.0e-5:
		print("  ★★ 自检失败：seek 没驱动骨架，下面的清单无意义，先修探针。")
		return
	# `fly` 动过的骨（= 微摆 key 落点）：这批会**把形态压回常态**，是叠加层的作用范围依据
	var fly_bones := _keyed_bone_set(ap, "fly")
	var rows: Array = []
	for i in r_norm.size():
		rows.append({
			"i": i,
			"name": _skel.get_bone_name(i),
			"deg": rad_to_deg(r_norm[i].angle_to(r_cruise[i])),
		})
	rows.sort_custom(func(a, b): return float(a["deg"]) > float(b["deg"]))
	print("  %-4s %-16s %10s  %s" % ["idx", "骨名", "旋转差°", "fly 里有关键帧"])
	var n_form := 0
	var n_keyed := 0
	for r in rows:
		if float(r["deg"]) < 0.5:
			break
		n_form += 1
		var keyed := fly_bones.has(r["name"])
		if keyed:
			n_keyed += 1
		print("  %-4d %-16s %10.2f  %s" % [r["i"], r["name"], r["deg"], "✔ 会压回常态" if keyed else "-"])
	print("  ⇒ 形态骨（差 > 0.5°）= **%d 根** / 共 %d 根；其中 **%d 根**在 fly 里被打了 key"
		% [n_form, rows.size(), n_keyed])
	if n_form == 0:
		print("  ★★ 一根都没有 ⇒ burst_cruise 末帧与 fly 首帧同姿态，形态层无从下手。")
		return
	print("  ⇒ 这 %d 根就是「巡航形态层」要叠加的对象：把它们从 fly 的姿态" % n_form)
	print("     slerp 到 burst_cruise 末帧的姿态，插值系数用 cruise_morph。")


## 采某个动作某一时刻的**全骨局部旋转**（形态层叠加的是旋转，不是位置）。
func _bone_rots_at(ap: AnimationPlayer, nm: String, t: float) -> Array[Quaternion]:
	var out: Array[Quaternion] = []
	if ap == null or not ap.has_animation(nm) or _skel == null or not is_instance_valid(_skel):
		return out
	ap.play(nm)
	ap.seek(t, true)
	await get_tree().process_frame
	ap.seek(t, true)          # 拉回 t（理由同 `_anchors_at`）
	for i in _skel.get_bone_count():
		out.append(_skel.get_bone_pose_rotation(i))
	ap.stop()
	return out


## 某个动作**动到过**的骨名集合（从轨道路径里解出来）。
##
## 用途：区分"这根骨在 fly 里有关键帧（会被动作覆盖）"和"动作压根不碰它"。
## 前者才是叠加层**必须**干预的（否则形态被压回常态）；后者可以不管。
func _keyed_bone_set(ap: AnimationPlayer, nm: String) -> Dictionary:
	var out := {}
	if ap == null or not ap.has_animation(nm):
		return out
	var a := ap.get_animation(nm)
	for t in a.get_track_count():
		var p := a.track_get_path(t)
		if p.get_subname_count() >= 1:
			out[str(p.get_subname(0))] = true
	return out


## 把某个动作定到指定时刻，采全部锚点。
##
## ⚠️ 第一版在这里写了 `ap.pause()`（想冻住播放头），结果**两次采样读到的完全一样**
## —— `pause()` 之后 `seek(t, true)` 不再驱动骨架，于是"巡航 vs 常态"量出来
## 全篇 `0.000 m`，看着像"两者姿态一模一样"这种**假结论**。
##
## 正确做法：`seek` **不要** pause，而是**等一帧再 seek 一次**把播放头拉回 `t`
##（`await` 期间 `_process` 会把播放头往前带）。
## 调用方另有自检（同动作两个时刻的差必须非零）。
func _anchors_at(ap: AnimationPlayer, nm: String, t: float) -> Dictionary:
	var out := {}
	if ap == null or not ap.has_animation(nm):
		return out
	ap.play(nm)
	ap.seek(t, true)
	await get_tree().process_frame
	ap.seek(t, true)          # ← 拉回 t：上面那一帧把播放头带走了
	for a: String in ANCHORS:
		out[a] = body.rig_anchor(a)
	ap.stop()
	return out


## 某个动作在 `t` 时刻的**全骨世界布局**（全部 50 根骨）。
##
## ⚠️ 用全骨而不是那 13 个锚点：形态差异（巡航 vs 常态）是**全身重排**，
## 只看锚点表会漏掉翼 / 裙甲 / 腿这些没进锚点表的骨 ——
## 而它们恰恰是"形态变没变"最直观的地方。
func _bones_at(ap: AnimationPlayer, nm: String, t: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if ap == null or not ap.has_animation(nm):
		return out
	if _skel == null or not is_instance_valid(_skel):
		return out
	ap.play(nm)
	ap.seek(t, true)
	await get_tree().process_frame
	ap.seek(t, true)          # 拉回 t（理由同 `_anchors_at`）
	out = _origins()
	ap.stop()
	return out


## ⑧ "动作真的在播吗"的**逐帧实况**。
##
## 数值上"锚点行程 3.58 m"只说明"首末两点的距离"，说明不了"中间一直在走"。
## 这一段把**播放头**与**锚点坐标**一起按时间打出来，于是"卡在第一帧"
## （播放头不动）与"在播但骨骼没被驱动"（播放头动、锚点不动）能分开识别。
func _report_tick_progress() -> void:
	print("")
	print("========== ⑧ 动作真的在播吗（逐帧实况） ==========")
	var ap := body.model_anim.player
	if ap == null or not ap.has_animation("fly"):
		print("  !! 没有 fly 动作，跳过")
		return
	var total := ap.get_animation("fly").length
	print("  播 `fly`（全长 %.4f s），每 15 帧采一次：" % total)
	print("  %5s %10s  %-26s %10s" % ["帧", "播放头(s)", "muzzle_R 锚点 (x,y,z) m", "距首帧(m)"])
	ap.play("fly")
	ap.seek(0.0, true)
	# ⚠️ 这里故意**不** pause —— 要看的正是"它自己会不会往前走"。
	var first := Vector3.ZERO
	var advanced := 0
	var samples := 0
	var last_head := 0.0
	for f in 130:
		if f % 15 == 0:
			var head := ap.current_animation_position
			var m: Vector3 = body.rig_anchor("muzzle_R")
			if f == 0:
				first = m
			var dd := first.distance_to(m)
			if head > last_head + 1.0e-4:
				advanced += 1
			last_head = head
			samples += 1
			print("  %5d %10.4f  (%8.3f,%8.3f,%8.3f) %10.4f" % [f, head, m.x, m.y, m.z, dd])
		await get_tree().process_frame
	var end_m: Vector3 = body.rig_anchor("muzzle_R")
	print("  ⇒ 播放头推进的采样点 = %d / %d，末次播放头 %.4f s（全长 %.4f s）"
		% [advanced, samples, ap.current_animation_position, total])
	print("  ⇒ 首帧到末帧，muzzle_R 锚点位移 %.4f m" % first.distance_to(end_m))
	if advanced >= samples - 1 and first.distance_to(end_m) > 0.01:
		print("  ★★ 结论：**动作确实在播** —— 播放头在推进，且骨骼带着锚点在走。")
	elif advanced >= samples - 1:
		print("  ⚠️ 播放头在推进，但锚点几乎不动 ⇒ 动作播了却没驱动骨骼（查 root_node）。")
	else:
		print("  ⚠️ 播放头没有推进 ⇒ 动作卡住了。")
	ap.stop()


# ============================================================ 出图

## 在每个锚点位置放一颗彩色小球，然后逐动作抓帧。
##
## 为什么必须出图：数值能证明"锚点动了 X 米"，但证明不了"锚点落在枪口上"。
## 而"子弹从枪管里出来"这件事，只有眼睛能判。
func _shoot() -> void:
	print("")
	print("========== ⑤ 出图 ==========")
	# ⚠️ 出图期间必须冻住机体。`_report_playback()` 收尾时把 `physics_process`
	# 打开了，若不在这里再关掉，机体就会**一边飞一边被拍** —— 相机与机体的
	# 相对位姿每帧都在漂，"锚点落在机体哪个部位"就无从判起。
	body.set_physics_process(false)
	DirAccess.make_dir_recursive_absolute(shots_dir)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	_build_env()
	var markers := _build_markers()
	var cam := _build_camera()
	var names: Array = body.model_anim.action_names()
	if names.is_empty():
		# 没有动作（老资产 / 没绑上）⇒ 仍然出一张**静态外形图**：
		# "新模型与老模型长得一不一样"这句话，没有对照就只是一句话。
		names = [""]
	for nm: String in names:
		var total := 0.0
		if nm != "":
			body.model_anim.player.play(nm)
			body.model_anim.player.seek(0.0, true)
			total = body.model_anim.player.get_animation(nm).length
		for f in SHOT_FRAMES:
			var t := total * float(f) / float(maxi(SHOT_FRAMES - 1, 1))
			if nm != "":
				body.model_anim.player.seek(t, true)
			_update_markers(markers)
			cam.look_at(body.global_position + _focus_offset(), Vector3.UP)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			if img == null:
				push_error("抓图失败")
				continue
			img.convert(Image.FORMAT_RGBA8)
			var tag := nm if nm != "" else "static"
			var out := "%s/xi_%s_f%02d.png" % [shots_dir, tag, f]
			var e := img.save_png(out)
			print("  saved %s  (t=%.3fs, err=%d)" % [out, t, e])
		if nm != "":
			body.model_anim.player.stop()
	await _shoot_form_compare(cam, markers)
	print("  ⇒ 输出目录 %s" % shots_dir)


## ★ 巡航形态层的**出图对照**（同一帧、同一相机，只改 `morph`）。
##
## 为什么非要出图：`_process_modification()` 的写入只在**渲染求值链**里生效，
## 帧边界回读 raw pose 只会拿到 `AnimationPlayer` 覆盖后的原值（探针 ⑩ 段的
## 同期诊断已证明写入有效）。所以"形态到底有没有出现在机体上"这件事，
## **代码侧读不到**，只能画出来看。
##
## 两组视角，因为形态骨（翼板 / 后挂架）长在**背部**：
##   * 全身 —— 判断整体轮廓；
##   * 尾部特写 —— 判断那 8 根长板到底展开了没有。
func _shoot_form_compare(cam: Camera3D, markers: Array) -> void:
	var mod := _form_layer()
	print("")
	print("  ---- 巡航形态层对照（只改 morph，其余全冻结）----")
	print("  档位：%s" % _form_layer_kind())
	if mod == null:
		print("  形态层不存在，跳过（老资产/单形态模型都走这里）。")
		return
	var ap := body.model_anim.player
	if ap == null or not ap.has_animation("fly"):
		print("  没有 fly 动作，跳过。")
		return
	# 定格待机首帧：`fly` 自己的呼吸微摆会盖过形态差异，必须冻住。
	ap.play("fly")
	ap.seek(0.0, true)
	ap.speed_scale = 0.0
	var tail := _build_tail_camera()
	var cams := [[cam, "full"], [tail, "tail"]]
	for pair in cams:
		var c: Camera3D = pair[0]
		var tag := str(pair[1])
		c.current = true
		# ★ 5 档（原来 3 档）：曲线层是**分段**的（先 Binder、后 Wing），
		# 只打 0 / 0.5 / 1 会看不出"morph=0.5 时 Wing 根本还没动"这件事。
		for s in [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]:
			var sf := float(s)
			mod.set("morph", sf)
			_update_markers(markers)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			if img == null:
				continue
			img.convert(Image.FORMAT_RGBA8)
			# ★ `%.2f` 而不是 `%.1f`：档位里有 0.25 / 0.75，一位小数会写成
			# `m0.2` / `m0.8` —— 文件名与实际 morph 不符。出图是**证据**，
			# 证据的名字必须准（沿用一位小数等于给后人埋雷）。
			var out := "%s/xi_form_%s_m%.2f.png" % [shots_dir, tag, sf]
			var e := img.save_png(out)
			print("  saved %s  (morph=%.1f, err=%d)" % [out, sf, e])
	mod.set("morph", 0.0)
	ap.speed_scale = 1.0
	ap.stop()


## 尾部特写相机。形态骨（`Wing` / `BinderFront` / `BinderBack` / `RearHang`）
## 全在**背部上侧**，全身视角下只占几十像素，看不出"展开没展开"。
##
## 机体正面朝 −Z（见 `_build_camera()` 的方位角说明），所以背后是 **+Z**。
func _build_tail_camera() -> Camera3D:
	var c := Camera3D.new()
	c.fov = 38.0
	c.near = 0.05
	c.far = 4000.0
	var focus := body.global_position + _focus_offset()
	var b := body.model_bounds
	# 从后上方看，距离取"够装下背板"的量级（全高的 1.1 倍）。
	var d := maxf(b.size.y * 1.1, 1.0)
	# ⚠️ 必须先 `add_child` 再设 `global_position` / `look_at`：
	# 这两者都要 `get_global_transform()`，节点不在树里会直接报
	# `Condition "!is_inside_tree()" is true` 然后**静默返回单位变换** ——
	# 相机于是停在原点朝 −Z，拍出来是个大特写碎片，而且不报致命错。
	add_child(c)
	c.global_position = focus + Vector3(0.0, b.size.y * 0.55, d)
	c.look_at(focus + Vector3(0.0, b.size.y * 0.22, 0.0), Vector3.UP)
	c.current = true
	return c


func _focus_offset() -> Vector3:
	var b := body.model_bounds
	return body.global_transform.basis * Vector3(b.get_center().x, b.get_center().y, b.get_center().z)


func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.63, 0.66)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.85)
	env.ambient_light_energy = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 132, 0)
	sun.light_energy = 1.5
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, -60, 0)
	fill.light_energy = 0.55
	fill.light_color = Color(0.7, 0.8, 1.0)
	add_child(fill)


## 炮口红 / 喷口蓝 / 其余黄。半径按全高的 2% —— 全高 28 m ⇒ 球径约 0.56 m，
## 在 640×720 的画面上够醒目，又不至于把机体挡掉。
func _build_markers() -> Array:
	var out := []
	var r := maxf(body.model_bounds.size.y * 0.02, 0.05)
	for a: String in ANCHORS:
		var mi := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = r
		sp.height = r * 2.0
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if a.begins_with("muzzle"):
			mat.albedo_color = Color(1.0, 0.15, 0.10)
		elif a.begins_with("thruster"):
			mat.albedo_color = Color(0.15, 0.45, 1.0)
		else:
			mat.albedo_color = Color(1.0, 0.85, 0.10)
		sp.material = mat
		mi.mesh = sp
		mi.name = "MK_" + a
		mi.set_meta("slot", a)
		add_child(mi)
		out.append({"node": mi, "slot": a})
	return out


func _update_markers(markers: Array) -> void:
	for m: Dictionary in markers:
		var mi := m["node"] as MeshInstance3D
		mi.global_position = body.global_transform * body.rig_anchor(str(m["slot"]))


## 相机取景：整机装得下，并且**不能接近旋转轴**（本项目踩过：
## 观察方向接近旋转轴时，零件只是原地打转，前后两帧肉眼完全一样）。
##
## ⚠️ **必须先把相机 `add_child` 进树，再设 `global_position` / `look_at`。**
## 不在树里的 `Node3D` 没有全局变换，Godot 4 会直接报
## `Node not inside tree. Use look_at_from_position() instead.` ——
## 而**报错只打在日志里、不影响退出码**：相机于是停在原点朝 −Z，
## 抓出来的图是被放大到认不出机体的碎片。
## 第一版就是这么错的：15 张图全部"保存成功、err=0"，但没有一张能判。
func _build_camera() -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.near = 0.05
	cam.far = 4000.0
	add_child(cam)
	var b := body.model_bounds
	var focus: Vector3 = body.global_position + _focus_offset()
	var radius := maxf(b.size.length() * shot_margin, 1.0)
	# 方位角 200°（左前方俯视）—— 与机体 −Z 正面差 20°，能同时看到正面与左侧。
	var a := deg_to_rad(200.0)
	cam.global_position = focus + Vector3(sin(a) * radius, b.size.y * 0.55, cos(a) * radius)
	cam.look_at(focus, Vector3.UP)
	cam.current = true
	print("  [取景] bounds.size = %s  center = %s" % [str(b.size), str(b.get_center())])
	print("         body.global_position = %s  focus = %s" % [str(body.global_position), str(focus)])
	print("         radius = %.4f  cam.global_position = %s  距焦点 %.4f m"
		% [radius, str(cam.global_position), cam.global_position.distance_to(focus)])
	return cam
