extends Node3D
## 柯西喷口几何扫描（轮 30）：在 **`FlightBody` 同一口径**下把机体的后半球做成正交深度栅格，
## 用来找「喷口开口」在**包围盒归一化坐标**里的位置 —— 也就是 `SuitProfile.engine_plumes`
## 要的那种分数。
##
## ## 为什么不能直接用 `tools/nozzle_scan.tscn`
## 那个探针吃的是**裸 glb**，自己复刻了 `FlightBody._center_and_measure()` 的居中，
## 但**不知道 `SuitProfile.model_yaw_deg`**（也不该知道 —— 它是通用工具）。
## 柯西在 2026-09-26 换了资产（`rx105_xi_gundam.glb` → `xi_fly.glb`），
## 新资产机头朝 **+Z**、要靠 `model_yaw_deg = 180` 掰回来。
## ⇒ **只有走真实 `FlightBody` 实例扫出来的分数，才是 `engine_plumes` 那一套口径。**
##
## ## 做法（与 `nozzle_scan` 同源：正交 ⇒ 像素↔模型坐标严格线性）
##   1. 真实建一台柯西 `FlightBody`（`use_placeholder = false`），冻结物理；
##   2. 取它的 `model_bounds`（**这就是运行时那一份**，含 yaw / 居中 / 缩放）；
##   3. 每个视图一台正交相机机位，逐像素打射线记 `t` ⇒ 深度栅格落盘；
##   4. `view_*.txt` 落盘全部投影参数，Python 侧据此把像素反解成归一化分数。
##
## ⚠️ 深度是「相机到表面的距离」⇒ **凹陷 = 深度比邻域大**。
##
## ## 跑法
##   godot [--headless] --path . res://tools/xi_nozzle_probe.tscn -- <输出目录> [y0,y1] [视图...]
##   `y0,y1` = **高度归一化裁剪区间**（默认 0,1 = 整机）。给 `0.05,0.45` 就把正交窗口
##   压在腿部那一带 ⇒ 同样的 512 栅格下小腿的分辨率翻好几倍。
##   视图写法 `仰角:方位角`（度），仰角**正 = 相机在上方**、方位角**正 = 相机偏 +X 侧**。
##   默认 `0:0 12:0 30:0 0:90 0:-90`。
##
## 深度图**不需要**渲染器（`Image.save_png` 自己写盘）⇒ `--headless` 也能出图。
## ⚠️ 但**开口长什么样**只有受光图能看出来：不加 `--headless` 时**额外**落盘
## `preview_*.png`（同一台正交相机的同一套投影参数），像素↔坐标与深度图逐点对应。

## 分辨率：1024 是给**腿部特写**选的（512 下一条小腿只有 ~100 px 宽，
## 那个尺度看不出"圆柱形喷口"的形状）。整机单视图的代价约 1M 次射线，可接受。
const GRID := 1024
const MARGIN := 1.06

var out_dir := "user://xi_nozzle"
var crop := Vector2(0.0, 1.0)
var views: Array[Vector2] = []
var want_preview := true


## N63 起支持环境变量 `NOZZLE_SUIT` 选机体（**默认 xi，不影响老用法**）：
##   `NOZZLE_SUIT=arizeus_normal` ／ `arizeus_cruise` ／ `penelope` ／ `xi`
func _pick_profile() -> SuitProfile:
	match OS.get_environment("NOZZLE_SUIT"):
		"arizeus_normal":
			return SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL)
		"arizeus_cruise":
			return SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE)
		"penelope":
			return SuitProfile.penelope()
		_:
			return SuitProfile.xi()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else out_dir
	DirAccess.make_dir_recursive_absolute(out_dir)
	if args.size() > 1:
		var cp := String(args[1]).split(",")
		if cp.size() == 2:
			crop = Vector2(float(cp[0]), float(cp[1]))
	if args.size() > 2:
		for i in range(2, args.size()):
			var parts := String(args[i]).split(":")
			if parts.size() == 2:
				views.append(Vector2(float(parts[0]), float(parts[1])))
	if views.is_empty():
		views = [Vector2(0, 0), Vector2(12, 0), Vector2(30, 0), Vector2(0, 90), Vector2(0, -90)]
	# 无头下 `RenderingServer` 是 dummy（一个像素都不产生）⇒ 预览图只真机跑。
	want_preview = DisplayServer.get_name() != "headless"
	print("### ARGS n=%d  views=%d  crop=%.2f,%.2f  driver=%s  preview=%s" % [
		args.size(), views.size(), crop.x, crop.y, DisplayServer.get_name(),
		"on" if want_preview else "off"])
	if want_preview:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(GRID, GRID))
		_build_env()

	var u := FlightBody.new()
	u.name = "Suit_xi"
	u.team = 0
	u.is_player = true
	u.profile = _pick_profile()
	u.display_name = "xi"
	u.use_placeholder = false
	# 与 `tools/plume_nozzle_shot.gd` 同一套：不俯冲 ⇒ 正交窗口与扫描口径严格对应。
	u.set("flight_pitch_deg", 0.0)
	add_child(u)
	u.global_position = Vector3.ZERO
	u.max_hp = 1000.0
	u.hp = 1000.0
	u.ifield_max = 0.0
	u.ifield_hp = 0.0
	# 冻住物理：`FlightBody.CRASH_ALTITUDE`(24 m) 会在第一个物理帧判"撞海"把模型拆走。
	u.set_physics_process(false)
	u.set_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if u.model_pivot != null:
		u.model_pivot.rotation_degrees = Vector3.ZERO
	# ---- 停在**绑定姿态**（rest pose）----
	#
	# 用户圈喷口用的是**模型绑定姿态**的截图（站姿、腿伸直），而游戏里模型在播 `fly`
	# 待机循环（腿弯曲后掠）—— 两者看到的"小腿后侧"不是同一块面。
	# 量几何要量的正是**绑定姿态**下那处开口 ⇒ 先停掉动画并复位骨骼。
	_stop_pose(u)

	var b: AABB = u.model_bounds
	print("### BOUNDS pos=(%.5f, %.5f, %.5f)  size=(%.5f, %.5f, %.5f)" % [
		b.position.x, b.position.y, b.position.z, b.size.x, b.size.y, b.size.z])
	_dump_table(u, b)
	_dump_bones(u, b)

	var n_shape := 0
	for c in u.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		mi.create_trimesh_collision()
		n_shape += 1
	print("### COLLIDERS %d" % n_shape)
	# 尾焰（含喷口常亮光晕）**一律遮掉**：它们会盖住真正的开口轮廓，
	# 而本探针要看的正是几何本身。`_tick_effects()` 没被调用 ⇒ 粒子本来就不发射，
	# 但光晕是 `MeshInstance3D`，建出来就是亮的。
	_hide_plumes(u)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# ⚠️ **必须 `await`**：`_scan()` 在真机（`want_preview`）下含 `await`，
	# 不接住的话它在第一个 `await` 处就返回，`quit(0)` 当场执行 ——
	# 症状是"只扫了第一个视图就 DONE、预览图一张没有"，**不报任何错**。
	# 同一个坑 `tools/orient_probe.gd` 的注释里也记着。
	await _scan(b, u)
	print("### DONE -> %s" % out_dir)
	get_tree().quit(0)


## 把**现有表**与它的镜像各算一遍世界坐标 —— 换资产/换 yaw 之后，"落点对不对"
## 的第一判据就是：喷口世界 z 在机体的哪一侧（工程约定**机头 −Z**）。
func _dump_table(u: FlightBody, b: AABB) -> void:
	var prof := _pick_profile()
	print("### TABLE %s  n=%d  yaw=%.1f" % [prof.display_name, prof.engine_plumes.size(), prof.model_yaw_deg])
	for i in prof.engine_plumes.size():
		var uv: Vector3 = prof.engine_plumes[i]
		var w: Vector3 = b.position + uv * b.size
		var mir := Vector3(1.0 - uv.x, uv.y, 1.0 - uv.z)
		print("    [%d] uv=(%.4f, %.4f, %.4f) -> world=(%.3f, %.3f, %.3f)   |  镜像 uv=(%.4f, %.4f, %.4f) -> world=(%.3f, %.3f, %.3f)" % [
			i, uv.x, uv.y, uv.z, w.x, w.y, w.z,
			mir.x, mir.y, mir.z,
			b.position.x + mir.x * b.size.x, b.position.y + mir.y * b.size.y,
			b.position.z + mir.z * b.size.z])
	print("    （工程约定机头 = −Z ⇒ 尾部喷口的世界 z 应当 **为正**）")


## 模型自带骨在 FlightBody 空间里的**静止**位置（用 rest，不受待机动画影响）。
## 只打印方位 / 腿部相关的骨，避免 50 根刷屏。
func _dump_bones(u: FlightBody, b: AABB) -> void:
	var skel := _find_skel(u)
	if skel == null:
		print("### BONES 没有 Skeleton3D")
		return
	var inv := u.global_transform.affine_inverse()
	print("### BONES（FlightBody 空间；x/y/z 为包围盒归一化分数）")
	for i in skel.get_bone_count():
		var bn := skel.get_bone_name(i)
		var low := bn.to_lower()
		var hit := false
		for w: String in ["thruster", "nozzle", "leg", "knee", "ankle", "foot",
				"back", "rear", "hip", "waist", "booster", "calf", "shin", "thigh"]:
			if low.contains(w):
				hit = true
				break
		if not hit:
			continue
		var gp: Vector3 = (skel.global_transform * skel.get_bone_global_rest(i)).origin
		var p: Vector3 = inv * gp
		# ⚠️ 同时给出**当前姿态**（rest 化之前那一瞬）的位置差：
		# `engine_plumes` 是**静态的模型本地坐标**，不跟随骨骼动画 ——
		# 若待机循环把小部位移拉得很开，喷口就会"挂在空气里"（背包口没这个问题，
		# 因为背包不在任何动画骨链上）。这个差就是那个风险的量。
		var gc: Vector3 = (skel.global_transform * skel.get_bone_global_pose(i)).origin
		var q: Vector3 = inv * gc
		print("    %-26s n=(%.4f, %.4f, %.4f)  动画位移 %.2f m" % [
			bn, (p.x - b.position.x) / b.size.x, (p.y - b.position.y) / b.size.y,
			(p.z - b.position.z) / b.size.z, q.distance_to(p)])


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null


## 把所有 `AnimationPlayer` 停掉 + 骨架复位到 rest ⇒ 模型停在绑定姿态。
func _stop_pose(u: FlightBody) -> void:
	var n_ap := 0
	for c in u.find_children("*", "AnimationPlayer", true, false):
		var ap := c as AnimationPlayer
		if ap != null:
			ap.stop()
			ap.active = false
			n_ap += 1
	var skel := _find_skel(u)
	if skel != null:
		# ⚠️ Godot 4 的 `Skeleton3D` **没有** `pose_reset()` / `clear_bones_pose()` /
		# `reset_bone_poses()` 这类"一键复位"（三个名字都试过，全是 SCRIPT ERROR，
		# 而函数会**当场中断**、后面的语句静默不执行 —— 看起来像"忘了写"）。
		#
		# ⚠️ 而且 `set_bone_pose_position(i, Vector3.ZERO)` **不等于复位**：
		# Godot 4 的 bone pose 是**相对父骨的局部变换**（不是"叠加在 rest 上的偏移"）。
		# 写零 = 把所有骨堆到父骨原点 ⇒ 模型当场塌成一团（实测 `thruster_L` 偏离
		# 绑定姿态 **25 m**）。正确做法 = 把 rest 的**局部**值写回去。
		for i in skel.get_bone_count():
			var r := skel.get_bone_rest(i)
			skel.set_bone_pose_position(i, r.origin)
			skel.set_bone_pose_rotation(i, r.basis.get_rotation_quaternion())
			skel.set_bone_pose_scale(i, r.basis.get_scale())
		skel.force_update_all_bone_transforms()
	print("### REST_POSE anim_players=%d skel=%s" % [
		n_ap, "yes" if skel != null else "no"])


## 逐视图做正交深度栅格。像素映射与 `nozzle_scan` 逐字一致（那边已验证过）。
func _scan(b: AABB, u_node: FlightBody) -> void:
	var space := get_world_3d().direct_space_state
	var c0 := b.get_center()
	var cy := b.position.y + (crop.x + crop.y) * 0.5 * b.size.y
	var center := Vector3(c0.x, cy, c0.z)
	var hh := (crop.y - crop.x) * 0.5 * b.size.y * MARGIN
	var hw := hh
	var diag := b.size.length()
	var big := diag * 2.0

	for vi in views.size():
		var v := views[vi]
		var el := deg_to_rad(v.x)
		var az := deg_to_rad(v.y)
		var k := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)).normalized()
		var cam_dir := -k
		var right := Vector3.UP.cross(k)
		if right.length() < 0.001:
			right = Vector3.RIGHT
		right = right.normalized()
		var up := k.cross(right).normalized()

		var depth := PackedByteArray()
		depth.resize(GRID * GRID * 3)
		var hit_count := 0
		var t_min := INF
		var t_max := -INF
		for j in GRID:
			for i in GRID:
				var uu := (float(i) + 0.5) / float(GRID) * 2.0 - 1.0
				var vv := 1.0 - (float(j) + 0.5) / float(GRID) * 2.0
				var o := center + right * (uu * hw) + up * (vv * hh) - cam_dir * big
				var q := PhysicsRayQueryParameters3D.create(o, o + cam_dir * (big * 2.0))
				q.collision_mask = 0xFFFFFFFF
				var r := space.intersect_ray(q)
				var idx := (j * GRID + i) * 3
				if r.is_empty():
					depth[idx] = 0
					depth[idx + 1] = 0
					depth[idx + 2] = 0
					continue
				var hitp: Vector3 = r["position"]
				var t := (hitp - o).dot(cam_dir)
				hit_count += 1
				t_min = minf(t_min, t)
				t_max = maxf(t_max, t)
				var norm := clampf(t / (big * 2.0), 0.0, 1.0)
				var q16 := int(round(norm * 65535.0))
				depth[idx] = (q16 >> 8) & 0xFF
				depth[idx + 1] = q16 & 0xFF
				depth[idx + 2] = 255
		var vname := "el%+d_az%+d" % [int(v.x), int(v.y)]
		var dimg := Image.create_from_data(GRID, GRID, false, Image.FORMAT_RGB8, depth)
		dimg.save_png(out_dir.path_join("depth_%s.png" % vname))

		var f := FileAccess.open(out_dir.path_join("view_%s.txt" % vname), FileAccess.WRITE)
		f.store_line("name %s" % vname)
		f.store_line("col %d" % vi)
		f.store_line("el %.6f" % v.x)
		f.store_line("az %.6f" % v.y)
		f.store_line("grid %d" % GRID)
		f.store_line("center %.6f %.6f %.6f" % [center.x, center.y, center.z])
		f.store_line("right %.8f %.8f %.8f" % [right.x, right.y, right.z])
		f.store_line("up %.8f %.8f %.8f" % [up.x, up.y, up.z])
		f.store_line("cam_dir %.8f %.8f %.8f" % [cam_dir.x, cam_dir.y, cam_dir.z])
		f.store_line("hw %.6f" % hw)
		f.store_line("hh %.6f" % hh)
		f.store_line("big %.6f" % big)
		f.store_line("crop %.6f %.6f" % [crop.x, crop.y])
		f.store_line("bounds_pos %.6f %.6f %.6f" % [b.position.x, b.position.y, b.position.z])
		f.store_line("bounds_size %.6f %.6f %.6f" % [b.size.x, b.size.y, b.size.z])
		f.close()
		print("### VIEW %-12s hits=%6d  t_min=%.3f t_max=%.3f" % [vname, hit_count, t_min, t_max])
		_dump_bone_screen(u_node, b, center, right, up, hw, hh, vname)
		if want_preview:
			await _snap_view(center, k, hh, up, vname)

	var head := FileAccess.open(out_dir.path_join("META.txt"), FileAccess.WRITE)
	head.store_line("bounds_pos %.6f %.6f %.6f" % [b.position.x, b.position.y, b.position.z])
	head.store_line("bounds_size %.6f %.6f %.6f" % [b.size.x, b.size.y, b.size.z])
	head.store_line("crop %.6f %.6f" % [crop.x, crop.y])
	head.store_line("views %d" % views.size())
	head.close()


## 把骨（rest 位置）投影成**预览图的像素坐标**落盘。
##
## 为什么要这一步：预览图上的腿是"一大块蓝色装甲"，光看形状认不出
## `Shin` / `Foot` / `RearHang` 各在哪 —— 而"小腿后侧的喷口"必须相对**骨**说才不歧义。
## 有了这张表，Python 把标记画到预览图上，位置就是可核对的数字。
func _dump_bone_screen(u: FlightBody, b: AABB, center: Vector3, right: Vector3,
		up: Vector3, hw: float, hh: float, vname: String) -> void:
	var skel := _find_skel(u)
	if skel == null:
		return
	var f := FileAccess.open(out_dir.path_join("bones_%s.txt" % vname), FileAccess.WRITE)
	f.store_line("grid %d" % GRID)
	var inv := u.global_transform.affine_inverse()
	for i in skel.get_bone_count():
		var bn := skel.get_bone_name(i)
		var p: Vector3 = inv * (skel.global_transform * skel.get_bone_global_rest(i)).origin
		var d := p - center
		var uu := d.dot(right) / hw
		var vv := d.dot(up) / hh
		var pi := (uu + 1.0) * 0.5 * float(GRID) - 0.5
		var pj := (1.0 - vv) * 0.5 * float(GRID) - 0.5
		f.store_line("%-28s %.3f %.3f  n=(%.4f, %.4f, %.4f)" % [
			bn, pi, pj, (p.x - b.position.x) / b.size.x, (p.y - b.position.y) / b.size.y,
			(p.z - b.position.z) / b.size.z])
	f.close()


## 同一台正交相机、同一套投影参数 ⇒ 预览图上的像素与深度图上的像素**逐点对应**，
## Python 侧反解出来的分数可以直接在预览图上标位。
func _snap_view(center: Vector3, k: Vector3, hh: float, up: Vector3, vname: String) -> void:
	# ⚠️ **用 `SubViewport`，不用主视口**：本工程设了窗口拉伸，
	# `DisplayServer.window_set_size()` 只是"请求"，**窗口会被系统/上次运行留下的尺寸接管**
	#（实测第一次 512×512、第二次变 215×64 ⇒ 抓回来的图糊到没法用）。
	# `SubViewport.size` 是**硬尺寸**，而且把 `world_3d` 指向主世界就能拍到同一批物体
	#（不必把机体搬进来，射线也仍然用主世界的 `direct_space_state`）。
	var vp := SubViewport.new()
	vp.size = Vector2i(GRID, GRID)
	vp.world_3d = get_world_3d()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.0 * hh
	cam.near = 0.01
	cam.far = 6000.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	vp.add_child(cam)
	cam.global_position = center + k * 300.0
	cam.look_at(center, up)
	cam.current = true
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img == null:
		push_error("预览抓图失败：%s" % vname)
	else:
		img.convert(Image.FORMAT_RGBA8)
		img.save_png(out_dir.path_join("preview_%s.png" % vname))
		print("### PREVIEW %-12s %dx%d" % [vname, img.get_width(), img.get_height()])
	vp.queue_free()


func _hide_plumes(u: FlightBody) -> void:
	var n := 0
	for item: Dictionary in (u.get("_plume_fx") as Array):
		for k: String in ["fx", "glow", "boost", "ab", "dash"]:
			var node := item.get(k) as Node3D
			if node != null and is_instance_valid(node):
				node.visible = false
				n += 1
	print("### HIDDEN plume nodes %d" % n)


func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.80, 0.85, 0.92)
	env.ambient_light_energy = 1.15
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 155, 0)
	key.light_energy = 1.7
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -50, 0)
	fill.light_energy = 0.65
	fill.light_color = Color(0.72, 0.82, 1.0)
	add_child(fill)
