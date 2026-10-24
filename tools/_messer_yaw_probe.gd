extends Node
## 梅萨朝向的**引擎内**核验：把同一台机按若干 yaw 从"正面相机"（站在 −Z）拍下来，
## ① 算轮廓的左右镜像残差（最小 ⇒ 正对相机）② 与**已知正确**的 M01 正面/背面对照。
##
## 跑法（**不能加 --headless**，dummy 渲染器抓出来是空的）：
##   godot --path <工程> res://tools/_messer_yaw_probe.tscn -- <输出目录>
##
## ## 为什么要这一道
## 纯 Python 的两条量（镜像对称 / 脚尖-脚跟比）都过了合成回环自检，但那是**离屏点云**。
## 本探针在**真引擎**里再量一遍 —— 它同时验掉三件离屏量不到的事：
##   ① 朝向修正公式 `yaw = phi + 90` 的符号（Godot 绕 Y 是 θ→θ−yaw）
##   ② 导入后的旋转轴是不是真的 Y（不是某个带倾斜的父子链）
##   ③ 轮廓级证据（可与老板肉眼判据对齐）
##
## ⚠️ 镜像残差对「正对」和「背对」**都**最小（左右对称的机体背面也对称）
## ⇒ 它只定「左右轴」，**定不了前/后**。前后由 ② 的对照解决：
##    把候选朝向的轮廓分别与 M01 的正面/背面比，像哪边就是哪边。

const W := 480
const H := 640

const MODELS := [
	# tag, 路径, [候选 yaw 列表]
	#
	# ⚠️⚠️ 2026-09-30（N60）**改过这两行**：cmd / f01 的路径从**未摆正的 Tripo 原样件**
	#   （`messer_cmd.glb` / `messer_f01.glb`）换成**绑定成品** `<name>_fly.glb`
	#   —— 摆正已把脸转到 +X 并**烘进顶点** ⇒ **导出件 φ = 0**，候选角度随之由
	#   `[90, 115.1, 270, 295.1]` 改成 `[90, 270]`。
	#   ⛔ 用**旧的那一对**（原样件 + 115.1）会得到「115.1 才是正脸」的结论 ——
	#   那正是 N58 翻车的原因：**同一刀切了两次**（一次在 Blender 摆正、一次在
	#   `model_yaw_deg`）。生产 `model_path` 现在指向 `_fly.glb`，**朝向以它为准**。
	#   ⇒ 本探针是**轮廓二值判据**（分辨率天生 180°，只能分"朝前 / 朝后"）；
	#     要量**角度**（能抓 25° 那种偏）请用 `tools/_n60_yaw_angle.gd`（T86）。
	["fly", "res://assets/models/messer/messer_fly.glb", [90.0, 270.0]],
	["cmd", "res://assets/models/messer_cmd/messer_cmd_fly.glb", [90.0, 270.0]],
	["f01", "res://assets/models/messer_f01/messer_f01_fly.glb", [90.0, 270.0]],
]

var out_dir := "user://messer_yaw"
var holder: Node3D
var cam: Camera3D


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out_dir = a[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(W, H))
	_build_env()
	await _run()
	print("MESSER_YAW_DONE -> ", out_dir)
	get_tree().quit(0)


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
	vp.world_3d = get_viewport().world_3d
	add_child(vp)

	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)


func _run() -> void:
	var profiles := {}
	var order: Array = []
	for entry: Array in MODELS:
		var tag: String = entry[0]
		var path: String = entry[1]
		for yaw: float in entry[2]:
			var key := "%s@%.2f" % [tag, yaw]
			order.append([tag, yaw, key])
			profiles[key] = await _shot(path, yaw, key)
	print("")
	print("%-16s %8s %10s   %s" % ["样本", "yaw", "镜像残差", "注"])
	print("-".repeat(72))
	for e: Array in order:
		var tag: String = e[0]
		var key: String = e[2]
		var pr: Array = profiles[key]
		var a: float = pr[1]
		print("%-16s %8.2f %10.4f   %s" % [key, e[1], a, "对称(正对/背对)" if a < 0.02 else ""])

	print("")
	print("=== 前后符号判定：候选朝向 vs M01 的正面(90) / 背面(270) 轮廓相关 ===")
	print("-".repeat(72))
	var fly_f: Array = profiles["fly@90.00"][0]
	var fly_b: Array = profiles["fly@270.00"][0]
	for entry: Array in MODELS:
		var tag: String = entry[0]
		if tag == "fly":
			continue
		for pair: Array in [[entry[2][0], "候选A(90)"], [entry[2][1], "候选B(270)"]]:
			var key := "%s@%.2f" % [tag, pair[0]]
			var p: Array = profiles[key][0]
			var cf := _corr(p, fly_f)
			var cb := _corr(p, fly_b)
			print("  %-14s 与 fly 正面 r=%+.4f / 与 fly 背面 r=%+.4f  => 更像%s  (%s)"
				% [key, cf, cb, "正面" if cf > cb else "背面",
					"★ 符号正确" if cf > cb else "⚠ 符号反了"])


## 拍一张，返回 [列墨迹剖面, 镜像残差]
func _shot(path: String, yaw: float, key: String) -> Array:
	for c: Node in holder.get_children():
		c.queue_free()
	await get_tree().process_frame
	var ps: PackedScene = load(path)
	var root := ps.instantiate() as Node3D
	holder.add_child(root)
	await get_tree().process_frame
	root.rotation_degrees = Vector3(0.0, yaw, 0.0)
	await get_tree().process_frame

	var box := _aabb(root)
	var ctr := box.get_center()
	var span: float = maxf(box.size.y, maxf(box.size.x, box.size.z))
	cam.size = span * 1.25
	cam.near = 0.01
	cam.far = span * 40.0
	cam.global_position = ctr + Vector3(0, 0, -span * 6.0)
	cam.look_at(ctr, Vector3.UP)
	await RenderingServer.frame_post_draw

	var vp: SubViewport = cam.get_parent()
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.save_png("%s/%s.png" % [out_dir, key.replace("@", "_")])

	var prof := _profile(img)
	var resid := _mirror_resid(prof)
	return [prof, resid]


func _aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv: Transform3D = root.global_transform.affine_inverse()
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
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
			# 与背景色的"距离"当墨迹量（背景是纯色，机体是亮色/彩色）
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
