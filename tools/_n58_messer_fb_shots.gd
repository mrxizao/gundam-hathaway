extends Node
## **N58** 梅萨指挥官型 / F01 型的**真机**取证：把三台梅萨都用**生产路径**（`FlightBody`
## ＋ `SuitProfile`）造出来，出"朝向 / 比例 / 骨确实跟动"三件事的图与量。
##
## ## 为什么不能只用"离屏 / 裸实例"的证据
##
## 本轮（装骨架 + 换 `model_path` + 改 `model_yaw_deg`）已经有一批**离屏**证据：
##   · Blender 侧 `transfer_rig_ms.py` 的出口判据（保方向 1.9e-05° / 5.2e-05°）
##   · 纯 Python 的 `glb_joint_cmp.py`（逐关节静息局部旋转 max 0.001815°）
##   · Blender 渲染的 `n58_facing/*_sheet.png`（正脸 / 背喷口）
## 这些都**没有经过游戏**：朝向是写在 `SuitProfile.model_yaw_deg` 上的，由
## `FlightBody._build_visual()` 加到 *`ModelYaw` 那一层*；骨架/动画由
## `ModelAnimator.setup()` 从**导入后的实例**里找。**数据层写对 ≠ 接得进去**
##（`tests/suite_messer_roster.gd` 的 `_fly()` 就是因为这条才存在）。
##
## 所以本探针专门干**只有真机才能干**的三件事：
##   ① **朝向**：相机站在游戏前方（−Z）拍"正面照"，量**左右镜像残差**（正对 ⇒ 最小）
##      ＋ 与 M01 正面/背面轮廓的**相关**（定 180° 二义）。
##   ② **比例**：`model_bounds.size.y` 与 `profile.target_height` 的差 —— 缩放口径
##      是 `target_height / model_native_height`，换件后 `model_native_height` 改了
##      ⇒ 只有在这里才量得到"换件有没有把机体缩错"。
##   ③ **骨跟不跟动**（N47 要求"启动动画后骨位姿确实跟动"）：
##      走**生产入口** `FlightBody.play_model_action("slash")`（`player_controller`
##      射击时走的就是它，内部转 `ModelAnimFSM.request_action()` ⇒ ACTION 态），
##      逐帧采一根手的骨的世界坐标，量**峰峰值**；再拿"不喊动作的同一段空转"当
##      **阴性对照**。⛔ 不直调 `model_anim.play_*()`（那会让状态机记一次 `desyncs`，
##      见 `flight_body.gd:478`）。
##
## ## 跑法（**不能加 --headless**，dummy 渲染器抓出来是空的）
##   Godot_v4.7.1-stable_win64_console.exe --path <工程> \
##       res://tools/_n58_messer_fb_shots.tscn -- <输出目录>
##
## ## 起始高度（T31）
## 机体建在 **y = 3000**：`y == 0` 会当场撞海 `die()` ⇒ 模型隐藏 ⇒ 动作链永不触发
## **且不报错**。3 s 的自由落体只掉 ~44 m，离海面还很远。

const W := 560
const H := 720

## 三台梅萨。tag → SuitProfile.Id（M01 是**阳性对照**：它的朝向是老板看图确认过的）。
## ⚠️ 写成 `var` 而不是 `const`：里面引用了 `SuitProfile.Id.*`（另一个全局类里的枚举）。
var suits := [
	["m01", SuitProfile.Id.MESSER_M01],
	["cmd", SuitProfile.Id.MESSER_CMD],
	["f01", SuitProfile.Id.MESSER_F01],
]

## 采样骨骼：`slash` 挥军刀时右手的位移最大，用它当"骨到底动不动"的指针。
const PROBE_BONE := "Hand.R"
## 动作段名（`messer_slash.glb` 里那一族）。
const ACTION_NAME := "slash"

var out_dir := "user://n58_fb"
var holder: Node3D
var cam: Camera3D
var lines: Array[String] = []


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out_dir = a[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(W, H))
	_build_env()
	await _run()
	print("\n".join(lines))
	print("N58_FB_DONE -> ", out_dir)
	get_tree().quit(0)


func _say(s: String) -> void:
	lines.append(s)


func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 145, 0)
	sun.light_energy = 1.6
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -55, 0)
	fill.light_energy = 0.5
	fill.light_color = Color(0.7, 0.8, 1.0)
	add_child(fill)

	holder = Node3D.new()
	holder.name = "Holder"
	add_child(holder)

	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# ★ 必须在**建完** `holder` 之后再指过来：SubViewport 自带一个空 World3D，
	#   不指的话它渲染的是那个空世界的背景色（拍出来纯色，且**不报错**）。
	vp.world_3d = get_viewport().world_3d
	add_child(vp)

	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)


func _run() -> void:
	_say("N58 · 梅萨三台（真 FlightBody）出图与量化")
	_say("输出目录：%s" % out_dir)
	_say("")
	_say("=== ① 比例口径 + ② 朝向（相机站 −Z 拍正面，站 +Z 拍背面）===")
	_say("%-6s %9s %9s %9s %9s %11s %11s %11s"
		% ["tag", "设定yaw", "目标高", "测得高", "高差", "mirror(正)", "mirror(背)", "r(正/对M01正)"])
	_say("-".repeat(96))

	var prof := {}
	for entry: Array in suits:
		var tag: String = entry[0]
		var p := SuitProfile.by_id(entry[1])
		prof[tag] = await _one(tag, p)

	var m01_front: Array = prof["m01"]["front_prof"]
	var m01_back: Array = prof["m01"]["back_prof"]
	for entry: Array in suits:
		var tag: String = entry[0]
		var rec: Dictionary = prof[tag]
		_say("%-6s %9.2f %9.1f %9.3f %9.3f %11.4f %11.4f %11.4f"
			% [tag, rec["yaw"], rec["target_h"], rec["meas_h"],
				rec["meas_h"] - rec["target_h"], rec["front_resid"], rec["back_resid"],
				_corr(rec["front_prof"], m01_front)])
		var rf := _corr(rec["front_prof"], m01_front)
		var rb := _corr(rec["front_prof"], m01_back)
		var rb2 := _corr(rec["back_prof"], m01_back)
		var rf2 := _corr(rec["back_prof"], m01_front)
		_say("        └ 正面照更像 M01 的 **%s**（r %.4f vs %.4f）；背面照更像 M01 的 **%s**（%.4f vs %.4f）"
			% ["正面" if rf > rb else "背面", rf, rb,
				"背面" if rb2 > rf2 else "正面", rb2, rf2])
		if tag != "m01":
			var face := "单眼面罩正脸 + 右手步枪 + 左臂大盾" if tag == "cmd" else "红色头冠 + 金色眼罩正脸"
			_say(("          ⚠️⚠️ 上面这行**只在 m01 自比（=1.0000）时有意义**：跨机体的一维剖面相关"
				+ "**没有区分度**。2026-09-30 实测两台都被它读成「正面照更像 M01 的**背面**」"
				+ "（0.9296 / 0.9131 vs 0.8479 / 0.8427，**只差 0.08**），而人眼看 `%s_front.png` 就是**%s**。"
				+ " ⇒ 定朝向**一律以出图人眼为准**（正脸 vs 背包双圆喷口），⛔ **不用这个数**。")
				% [tag, face])

	_say("")
	_say("=== ③ 骨到底跟不跟动（生产入口 play_model_action，逐帧采 %s 世界坐标）===" % PROBE_BONE)
	_say("%-6s %16s %16s %8s   %s" % ["tag", "空转峰峰(m)", "slash峰峰(m)", "比值", "注"])
	_say("-".repeat(96))
	for entry: Array in suits:
		var tag: String = entry[0]
		var rec: Dictionary = prof[tag]
		var idle: float = rec["idle_p2p"]
		var act: float = rec["act_p2p"]
		var ratio := act / maxf(idle, 1e-6)
		_say("%-6s %16.6f %16.6f %8.2f   %s"
			% [tag, idle, act, ratio,
				"★ 动作确实驱动了骨" if act > idle * 5.0 else "⚠ 骨没跟动"])

	_say("")
	_say("锚点：%s" % str(prof["cmd"]["muzzle"]))


## 造一台真机，拍 4 张正/背/侧/三四，量比例、镜像残差、骨峰峰值。
func _one(tag: String, p: SuitProfile) -> Dictionary:
	for c: Node in holder.get_children():
		c.queue_free()
	await get_tree().process_frame

	var body := FlightBody.new()
	body.name = "FB_%s" % tag
	body.profile = p
	body.use_placeholder = false
	body.flight_pitch_deg = 0.0
	body.position = Vector3(0, 3000, 0)
	holder.add_child(body)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# —— 等它进入稳态（形态混合 / 待机动作都到位）——
	for i in 40:
		await get_tree().physics_frame
	# ★★ 拍照阶段**冻结物理**：机体以几十 m/s 在飞，一帧能挪出**半个取景框**
	#（实测 side 镜：相机按旧的中心摆好，等一帧 `frame_post_draw` 之后机体已
	# 沿屏幕横向挪了 44 m > 取景宽度 27.5 m ⇒ 拍出一张**纯背景**图，且不报错）。
	body.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().process_frame

	var rec := {
		"yaw": p.model_yaw_deg,
		"target_h": p.target_height,
		"meas_h": body.model_bounds.size.y,
		"muzzle": body._muzzle_local.size(),
	}
	# 用"看不见的世界坐标"确认模型真在场景里（避免拍到空背景还浑然不觉）
	_say("  [%s] 位置=%s 可见网格=%d" % [tag, str(body.global_position.snappedf(0.01)), _n_mesh(body)])

	# ---- 正面 / 背面：同一台机，只差 180° ----
	var front := await _shot(body, "front", tag, "_front")
	var back := await _shot(body, "back", tag, "_back")
	rec["front_prof"] = front[0]
	rec["front_resid"] = front[1]
	rec["back_prof"] = back[0]
	rec["back_resid"] = back[1]

	# 侧面 / 三四（人眼核验用）
	await _shot(body, "side", tag, "_side")
	await _shot(body, "q34", tag, "_q34")

	# ---- 骨跟不跟动：先空转，再走生产入口喊 slash ----
	#
	# ⚠️ 采的是**机体本地坐标系**里的位置：机体在飞，世界坐标的峰峰值量到的是
	#    飞行位移（实测 429 m），跟骨头一点关系都没有。
	body.set_physics_process(true)
	await get_tree().physics_frame
	var idle := await _bone_span(body, 0)
	rec["idle_name"] = idle[1]
	var act := await _bone_span(body, 24)
	rec["idle_p2p"] = idle[0]
	rec["act_p2p"] = act[0]
	rec["act_pre"] = act[1]
	rec["act_post"] = act[2]
	rec["act_end"] = act[3]
	_say("  [%s] 动作名册 %d 段；空转在播「%s」｜ 触发前「%s」→ 触发后第 6 帧「%s」→ 窗口末「%s」"
		% [tag, body.model_anim.action_names().size(), idle[1], act[1], act[2], act[3]])
	_say("        ★ 判据：触发后那一栏**必须**变成 `%s`（不再是 `__rest__`）——段名切了 = 动作真被播了"
		% ACTION_NAME)

	body.queue_free()
	await get_tree().process_frame
	return rec


## 拍一张，返回 [列墨迹剖面, 镜像残差]。
## `view` ∈ {"front","back","side","q34"}；`front` = 相机站在游戏**前方**（−Z）。
func _shot(body: Node3D, view: String, tag: String, suffix: String) -> Array:
	# ★ 取景用 `body.model_bounds`（**游戏自己的量**，`_center_and_measure()` 算的），
	#   不是我再数一遍网格 —— 那样会**静默**取到空盒 ⇒ `span = 0` ⇒ 相机 size=0
	#   ⇒ 拍出一张纯背景的图，而且**不报任何错**（本轮第一次跑就是这样）。
	var box: AABB = body.model_bounds
	if box.size.length() < 0.001:
		box = _visible_aabb(body)
	var ctr: Vector3 = body.global_transform * box.get_center()
	var span: float = maxf(box.size.y, maxf(box.size.x, box.size.z))
	if span < 0.001:
		push_error("N58: %s %s 取景跨度为 0 —— 拍出来会是空图" % [tag, view])
	var dir := Vector3(0, 0, -1)
	match view:
		"back":
			dir = Vector3(0, 0, 1)
		"side":
			dir = Vector3(1, 0, 0)
		"q34":
			dir = Vector3(-1, -0.35, -1).normalized()
	cam.size = span * 1.25
	cam.near = 0.01
	cam.far = span * 40.0
	cam.global_position = ctr + dir * span * 6.0
	cam.look_at(ctr, Vector3.UP)
	# ⚠️ `frame_post_draw` 才是"这一帧真的画完了"的信号；少等一拍会拿到**上一张**
	#    或半张（且不报错）。
	await RenderingServer.frame_post_draw

	var vp: SubViewport = cam.get_parent()
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.save_png("%s/%s%s.png" % [out_dir, tag, suffix])
	var prof := _profile(img)
	_say("    [%s] %s 取景 span=%.3f 中心=%s 墨迹合计=%.1f"
		% [tag, suffix, span, str(ctr.snappedf(0.1)), _ink_total(prof)])
	return [prof, _mirror_resid(prof)]


## 采 `PROBE_BONE` 在**机体本地坐标系**里的峰峰值（m）。
## `after_frames > 0` 时先走生产入口 `play_model_action()` 喊一次动作。
func _bone_span(body: Node3D, after_frames: int) -> Array:
	var skel: Skeleton3D = body._model_skel
	if skel == null:
		return [0.0, "(无骨架)"]
	var idx := skel.find_bone(PROBE_BONE)
	if idx < 0:
		return [0.0, "(找不到骨 %s)" % PROBE_BONE, "", ""]
	var inv: Transform3D
	var mn := Vector3.INF
	var mx := -Vector3.INF
	var frames := 70
	# ★★ 三个采样点 —— 原版**只有一个**，而且它采在**触发之前**、文案却写成"触发之后"
	#   ⇒ 读起来像"喊了动作却没生效"（2026-09-30 实测踩到）。
	#   `pre_name`  = 触发**之前**在播什么
	#   `post_name` = 触发后第 6 帧在播什么（**这才是"动作到底切没切段"的读数**）
	#   `end_name`  = 窗口最后一帧在播什么（看得出动作播完有没有回收）
	var pre_name := ""
	var post_name := ""
	var end_name := ""
	for i in frames:
		if i == 8:
			pre_name = str(body.model_anim.current)
			if after_frames > 0:
				body.play_model_action(ACTION_NAME, false)
		await get_tree().physics_frame
		if i == 14 and after_frames > 0:
			post_name = str(body.model_anim.current)
		if i == frames - 1:
			end_name = str(body.model_anim.current)
		if i < 6:
			continue
		# ⚠️ `inv` 必须**每帧重取**：机体的 global_transform 在动，循环外取一次
		#    等于拿一个**过期的逆变换**去"本地化"后面的每一点 ⇒ 位移原样漏进来。
		inv = body.global_transform.affine_inverse()
		var w: Vector3 = inv * (skel.global_transform * skel.get_bone_global_pose(idx).origin)
		mn = mn.min(w)
		mx = mx.max(w)
	var span: Vector3 = mx - mn
	return [maxf(span.x, maxf(span.y, span.z)), pre_name, post_name, end_name]


func _n_mesh(root: Node) -> int:
	return root.find_children("*", "MeshInstance3D", true, false).size()


## 剖面墨迹总和。**它是"这张图是不是空的"的唯一告警**：
## 空图的镜像残差恰好是 1.0，与"完美对称"同值 ⇒ 只看残差会把空图读成"正对相机"。
func _ink_total(p: Array) -> float:
	var s := 0.0
	for v: float in p:
		s += v
	return s


func _visible_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv: Transform3D = root.global_transform.affine_inverse()
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var t: Transform3D = inv * mi.global_transform
		var b: AABB = t * mi.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _profile(img: Image) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var p := []
	p.resize(w)
	p.fill(0.0)
	var bg := Color(0.05, 0.05, 0.07)
	for x in w:
		var s := 0.0
		for y in h:
			var c := img.get_pixel(x, y)
			var d: float = absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b)
			if d > 0.06:
				s += minf(d, 1.0)
		p[x] = s
	return p


func _mirror_resid(p: Array) -> float:
	var w := p.size()
	var tot := 0.0
	for v: float in p:
		tot += v * v
	if tot <= 0.0:
		return 1.0
	var best := 1e30
	var c := float(w) * 0.35
	while c <= float(w) * 0.65:
		var s := 0.0
		for x in w:
			var xr := c - float(x)
			var i := int(floor(xr))
			if i < 0 or i + 1 >= w:
				continue
			var f := xr - float(i)
			var pv: float = p[i] * (1.0 - f) + p[i + 1] * f
			var d: float = p[x] - pv
			s += d * d
		if s < best:
			best = s
		c += 0.5
	return best / tot


func _corr(a: Array, b: Array) -> float:
	var n: int = mini(a.size(), b.size())
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += a[i]
		mb += b[i]
	ma /= float(n)
	mb /= float(n)
	var num := 0.0
	var da := 0.0
	var db := 0.0
	for i in n:
		var x: float = a[i] - ma
		var y: float = b[i] - mb
		num += x * y
		da += x * x
		db += y * y
	if da <= 0.0 or db <= 0.0:
		return 0.0
	return num / sqrt(da * db)
