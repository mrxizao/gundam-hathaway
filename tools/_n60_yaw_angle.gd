extends Node
## **N60** 梅萨三台「朝向」的**角度量**真机探针 —— 替换 N58 那个二值判据。
##
## ## 为什么必须换判据（★ T86）
## N58 / N59 用的判据是「拍正面照，人眼看有没有脸」。那是个**二值判据**，
## 理论分辨率**天生只有 180°** —— **25° 的偏航在正交视图里看起来仍然是「正脸」**
## （单眼面罩 / 头冠 / 眼罩全都在）。⇒ 「能看到脸」≠「朝向正确」。
## N58 就是因此漏掉了 `model_yaw_deg` 多转了一刀（25.1°），
## 直到老板真机看到「向左偏」才暴露。
##
## 本探针改成**角度量**：从生产实例的 `Skeleton3D`（`body._model_skel`）取 5 根骨的
## **世界坐标**，算机体的解剖朝向，再与工程约定「机头朝世界 −Z」量**夹角**。
##   · S = hand_R − hand_L      （侧向）
##   · U = Head  − Hips         （竖直）
##   · F = S × U                （前后，符号用**背部**骨 `RearWaist` 校正）
##   ⇒ 机头方向 = F 投影到水平面；读数 = ∠(机头, −Z)
##
## ★ 与 `_relay/tmp/yaw_recheck2.py`（纯 Python 解 glb）**同一套量法**，
##   但那条只证「**资产层**」；这条证「**装进游戏、经过 `ModelYaw` 那一层之后**」——
##   数据层写对 ≠ 接得进去（这正是 `suite_messer_roster.gd` 的 `_fly()` 存在的理由）。
##
## ## 判据（每条都**能变红**）
##   ① **三台相等**：cmd / f01 与 m01 的读数差 **< 0.1°**（m01 是老板确认过的标尺）
##   ② **证伪条**：把 cmd 的 yaw 故意改成 **95**（+5）⇒ 读数必须相对 90 变 **−5.0°**
##      （yaw 加 Δ ⇒ 机头方位角减 Δ）。★ 不写这条，「没超差」不算数。
##   ③ **回归证明**：把 cmd 的 yaw 设回 N58 的错误值 **115.1** ⇒ 读数必须变 **−25.1°**
##      —— 把老板看到的「向左偏 25°」在机上**复现**出来。
##   ④ **人眼**：三台同相机、同参数并排拍 front / back / side。
##
## ## 读数怎么读
## 有向读数 > 0 ⇒ 机头偏向 **+X**。工程的第三人称相机在机体**后方**看向 −Z，
## 此时 **+X 落在屏幕右侧** ⇒ 正的有向读数 = 老板说的「**偏朝右**」，
## 负的 = 「**向左偏**」。（所以 115.1 那一档必须读出 **约 −20°** ＝ 「向左偏 25°」。）
##
## ⚠️ **别只看「读数接近 0」**：yaw=95 那一档的绝对读数只有 0.05°，比正确的 4.95° **更接近 0**，
##   但它是**错的** —— 那 4.95° 是三台资产**共有**的残余（m01 自己也带，老板认可）。
##   ⇒ 判据必须是**相对**的（三台相等 / 相对基准的变化量）。
##
## ## 跑法（**不能加 --headless**，dummy 渲染器抓出来是空的）
##   Godot_v4.7.1-stable_win64_console.exe --path <工程> \
##       res://tools/_n60_yaw_angle.tscn -- <输出目录>
##
## ## 起始高度（T31）
## 机体建在 **y = 3000**：`y == 0` 会当场撞海 `die()` ⇒ 模型隐藏 ⇒ 量不到骨，**且不报错**。

const W := 560
const H := 720

## 量朝向要用的 5 根骨。三类都取，是为了不让量法依赖任何单一族的指派结果：
##   `Head` / `Hips` 是 **CORE** 骨 · `hand_R` / `hand_L` 是**锚点骨** · `RearWaist` 是 **BODY** 骨。
var need_bones := ["hand_L", "hand_R", "Hips", "Head", "RearWaist"]

## 条目：[tag, SuitProfile.Id, yaw 覆盖（NAN = 用 profile 里的真值）, 说明, 参考 tag, 期望 Δ]
## ⚠️ 写成 `var` 而不是 `const`：里面引用了另一个全局类 `SuitProfile` 的枚举。
var entries := [
	["m01", SuitProfile.Id.MESSER_M01, NAN, "标尺（老板看图确认过 90° 就是正的）", "", NAN],
	["cmd", SuitProfile.Id.MESSER_CMD, NAN, "本轮修复对象", "", NAN],
	["f01", SuitProfile.Id.MESSER_F01, NAN, "本轮修复对象", "", NAN],
	["cmd@95", SuitProfile.Id.MESSER_CMD, 95.0,
		"★ 证伪条：故意偏 +5° ⇒ 读数必须相对 cmd 变 −5.0°", "cmd", -5.0],
	["cmd@115.1", SuitProfile.Id.MESSER_CMD, 115.1,
		"★ 回归证明：N58 的错误值 ⇒ 读数必须变 −25.1°（老板的「向左偏」）", "cmd", -25.1],
	["f01@115.15", SuitProfile.Id.MESSER_F01, 115.15,
		"★ 回归证明（F01）：N58 的错误值 ⇒ 读数必须变 −25.15°", "f01", -25.15],
]

var out_dir := "user://n60_yaw"
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
	print("N60_YAW_DONE -> ", out_dir)
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
	#   不指的话它渲染那个空世界的背景色（拍出来纯色，且**不报错**）。
	vp.world_3d = get_viewport().world_3d
	add_child(vp)

	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)


func _run() -> void:
	_say("N60 · 梅萨三台朝向 —— **角度量**（真 FlightBody，走生产路径）")
	_say("输出目录：%s" % out_dir)
	_say("")
	_say("读法：有向读数 > 0 ⇒ 机头偏 +X（第三人称在机后看 = 屏幕**右**）；< 0 ⇒ 「向左偏」。")
	_say("      判据是**相对**的（三台相等 / 相对基准的变化量），⛔ 不是「越接近 0 越好」。")
	_say("")
	_say("%-10s %8s %11s %11s %10s  %s"
		% ["tag", "设定yaw", "有向读数", "绝对读数", "Δ(对参考)", "说明"])
	_say("-".repeat(104))

	var rec := {}
	var order: Array = []
	for e: Array in entries:
		var tag: String = e[0]
		var id: int = e[1]
		var yaw_ov: float = e[2]
		var note: String = e[3]
		var ref: String = e[4]
		var exp_d: float = e[5]
		var r: Dictionary = await _one(tag, id, yaw_ov)
		r["note"] = note
		r["ref"] = ref
		r["exp_d"] = exp_d
		rec[tag] = r
		order.append(tag)

	# ---- 出表（Δ 一律对同一条目声明的参考算；没有参考的就不填）----
	for tag: String in order:
		var r: Dictionary = rec[tag]
		if not r["ok"]:
			_say("%-10s %8s %11s %11s %10s  ⚠️ %s"
				% [tag, "-", "-", "-", "-", r["why"]])
			continue
		var ref: String = r["ref"]
		var dstr := "-"
		if ref != "" and rec.has(ref) and rec[ref]["ok"]:
			dstr = "%+.3f" % (r["signed"] - rec[ref]["signed"])
		_say("%-10s %8.2f %11.3f %11.3f %10s  %s"
			% [tag, r["yaw"], r["signed"], r["mag"], dstr, r["note"]])

	# ---- 判据 ①②③ ----
	_say("")
	_say("=== 判据 ===")
	var base: Dictionary = rec["m01"]
	var all_pass := true
	if not base["ok"]:
		_say("  ⛔ 标尺 m01 没量到，后面全部不作数：%s" % base["why"])
		all_pass = false
	else:
		for tag: String in ["cmd", "f01"]:
			var r: Dictionary = rec[tag]
			if not r["ok"]:
				_say("  ⛔ ① %s：没量到（%s）" % [tag, r["why"]])
				all_pass = false
				continue
			var d: float = absf(r["signed"] - base["signed"])
			var good := d < 0.1
			all_pass = all_pass and good
			_say("  %s ① 三台相等：%s 与 m01 的读数差 = %.4f°（阈值 0.1°）"
				% ["✓" if good else "✗", tag, d])
		for tag: String in order:
			var r: Dictionary = rec[tag]
			if r["ref"] == "" or not r["ok"]:
				continue
			var got: float = r["signed"] - rec[r["ref"]]["signed"]
			var exp_d: float = r["exp_d"]
			var good2: bool = absf(got - exp_d) < 0.5
			all_pass = all_pass and good2
			_say("  %s ②③ %s：实测 Δ = %+.3f°  期望 %+.2f°（容差 0.5°）"
				% ["✓" if good2 else "✗", tag, got, exp_d])
	_say("")
	_say("VERDICT: %s" % ("PASS" if all_pass else "FAIL"))
	_say("★ 说明：修复后三台的绝对读数都应落在 +4.95° 附近（三台资产共有的残余，")
	_say("  m01 自己也带、老板认可），**不是 0** —— 所以判据看的是「三台相等」与「Δ 对得上」。")


## 造一台真机 → 量朝向角 → 拍 front / back / side。
## `yaw_ov` 非 NAN 时**临时改** `model_yaw_deg`（`by_id()` 每次新建实例 ⇒ 不会污染别处）。
func _one(tag: String, id: int, yaw_ov: float) -> Dictionary:
	for c: Node in holder.get_children():
		c.queue_free()
	await get_tree().process_frame

	var p: SuitProfile = SuitProfile.by_id(id)
	if not is_nan(yaw_ov):
		p.model_yaw_deg = yaw_ov

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
	# ★★ 量测与拍照前**冻结物理**：机体以几十 m/s 在飞，一帧能挪出**半个取景框**
	#（实测：相机按旧中心摆好，等一帧 `frame_post_draw` 后机体已横向挪 44 m >
	# 取景宽 27.5 m ⇒ 拍出**纯背景**图，且不报错）。
	body.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().process_frame

	_say("  [%s] yaw=%.2f 位置=%s 可见网格=%d 高=%.3f 炮口=%d"
		% [tag, p.model_yaw_deg, str(body.global_position.snappedf(0.01)), _n_mesh(body),
			body.model_bounds.size.y, body._muzzle_local.size()])

	# —— 角度量 ——
	var m := _measure(body)
	if m["ok"]:
		_say("        └ 骨世界坐标：手距 %.4f ｜ 头-髋 %.4f ｜ 背向校正 dot=%+.3f"
			% [m["hand_gap"], m["up_len"], m["back_dot"]])

	# —— 出图（人眼判据，判据④）——
	await _shot(body, "front", tag)
	await _shot(body, "back", tag)
	await _shot(body, "side", tag)
	await _shot(body, "q34", tag)

	var out := {
		"ok": m["ok"],
		"why": m.get("why", ""),
		"yaw": p.model_yaw_deg,
		"signed": m.get("signed", NAN),
		"mag": m.get("mag", NAN),
	}
	body.queue_free()
	await get_tree().process_frame
	return out


## 量机头方向与**世界 −Z** 的夹角。返回 {"ok", "signed", "mag", ...}。
func _measure(body: Node3D) -> Dictionary:
	var skel: Skeleton3D = body._model_skel
	if skel == null:
		return {"ok": false, "why": "`body._model_skel` 为空（模型骨架没接上）"}
	var wp := {}
	for nm: String in need_bones:
		var i := skel.find_bone(nm)
		if i < 0:
			return {"ok": false,
				"why": "模型骨架里找不到骨 `%s`（共 %d 根）" % [nm, skel.get_bone_count()]}
		# ★ `Skeleton3D` 的 bone pose 是**该骨架节点局部空间**里的绝对变换（T34）
		#   ⇒ 世界坐标 = skel.global_transform × bone_global_pose.origin。
		wp[nm] = skel.global_transform * skel.get_bone_global_pose(i).origin

	var s: Vector3 = wp["hand_R"] - wp["hand_L"]
	var u: Vector3 = wp["Head"] - wp["Hips"]
	var back: Vector3 = wp["RearWaist"] - wp["Hips"]
	if s.length() < 1e-6 or u.length() < 1e-6:
		return {"ok": false, "why": "手/头髋连线退化（骨没接上或被隐藏）"}
	var f: Vector3 = s.normalized().cross(u.normalized())
	# 符号：机头必须**背向** `RearWaist`（背在后方）
	var back_dot: float = f.dot(back)
	if back_dot > 0.0:
		f = -f
		back_dot = -back_dot
	var fwd: Vector3 = Vector3(f.x, 0.0, f.z).normalized()   # 投影到水平面
	var tgt := Vector3(0.0, 0.0, -1.0)                       # 工程约定：机头朝 −Z
	var rel: Vector3 = fwd.cross(tgt)
	var cosv: float = clampf(fwd.dot(tgt), -1.0, 1.0)
	# ★ 夹角用 atan2(|cross|, dot)，⛔ **不用 acos**：`acos` 在近 0° 处把 float 误差
	#   **开平方**放大（T63：实测虚高 1511 倍）。
	var mag := rad_to_deg(atan2(rel.length(), cosv))
	# 有向：绕 +Y 从「机头」转到「−Z」。+  ⇒ 机头偏 +X ⇒ 机后视角下 = 屏幕右。
	var sgn := rad_to_deg(atan2(rel.dot(Vector3.UP), cosv))
	return {
		"ok": true,
		"mag": mag,
		"signed": sgn,
		"fwd": fwd,
		"back_dot": back_dot,
		"hand_gap": (wp["hand_R"] - wp["hand_L"]).length(),
		"up_len": (wp["Head"] - wp["Hips"]).length(),
	}


## 拍一张（`view` ∈ {"front","back","side"}；front = 相机站在 −Z，看到**正脸**）。
func _shot(body: Node3D, view: String, tag: String) -> void:
	# ★ 取景用 `body.model_bounds`（**游戏自己的量**，`_center_and_measure()` 算的），
	#   不是我另数一遍网格 —— 那样会**静默**取到空盒 ⇒ span=0 ⇒ 相机 size=0
	#   ⇒ 拍出纯背景图，而且**不报任何错**。
	var box: AABB = body.model_bounds
	var ctr: Vector3 = body.global_transform * box.get_center()
	var span: float = maxf(box.size.y, maxf(box.size.x, box.size.z))
	if span < 0.001:
		push_error("N60: %s %s 取景跨度为 0 —— 拍出来会是空图" % [tag, view])
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
	# ⚠️ `frame_post_draw` 才是"这一帧真的画完了"；少等一拍会拿到上一张或半张（不报错）。
	await RenderingServer.frame_post_draw

	var vp: SubViewport = cam.get_parent()
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.save_png("%s/%s_%s.png" % [out_dir, _slug(tag), view])
	var prof := _profile(img)
	_say("        [%s/%s] span=%.3f 中心=%s 墨迹合计=%.1f"
		% [tag, view, span, str(ctr.snappedf(0.1)), _ink_total(prof)])


func _n_mesh(root: Node) -> int:
	return root.find_children("*", "MeshInstance3D", true, false).size()


func _slug(s: String) -> String:
	return s.replace("@", "_").replace(".", "p")


## 剖面墨迹总和。**它是"这张图是不是空的"的唯一告警**：
## 空图的镜像残差恰好是 1.0，与"完美对称"同值 ⇒ 只看残差会把空图读成"正对相机"。
func _ink_total(p: Array) -> float:
	var s := 0.0
	for v: float in p:
		s += v
	return s


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
