extends Node
## **路面 A/B 取证**：路面到底"没渲染"还是"渲染了但看不见"（B7 · 2026-09-28）。
##
## ## 为什么必须做这个 A/B
## 用户："**路面和地面依旧没做区分还是没做出来，现在还是看不到公路路面**"。
## 上一轮 `_b6_road_view` 已经把**数据侧**量清了（`_city_dry_spans` 在点上、路面顶
## 比地形高 5.5 m），但定点图上**读不出路面**。剩下的可能只有两条：
##
## | 假设 | 预测 |
## |---|---|
## | **H1 几何缺失/被剔除** | 把 `CityRoads` 材质换成纯红之后，**画面里没有红带** |
## | **H2 几何在、对比度太低** | 红带**出现**，且位置/宽度与 `_city_dry_spans` 的预测重合 |
##
## 判据不能靠看 —— 所以本探针同时打**三样读数**：
##   ① `CityRoads` 的实例数 / 反照率 / `custom_aabb`；
##   ② 定点附近**实例变换**（真值：实例中心的 x/z/y 与尺寸）；
##   ③ 同一机位两张图（基线 / 纯红）的**逐像素差**（用 Python 事后算），
##      以及"红带在画面里的列区间"（探针自己扫一遍像素给出行剖面）。
##
## 跑法（**不能加 `--headless`**，dummy 渲染器抓出来全黑）：
##   godot --path <工程> res://tools/_b7_road_ab.tscn -- <输出目录> [city]

const AIM_X := 12075.0
const AIM_Z := 12075.0

var out_dir := "user://b7_road_ab"
var _idx := 0
var world: WorldBuilder


func _ready() -> void:
	# ⚠️⚠️ **看门狗**：带窗口跑时，`_ready()` 里任何一条抛错都会让协程**静默中断** ——
	# 而 `get_tree().quit()` 在最后一行 ⇒ 进程**永远不退出**（实测卡了 14 分钟，
	# 得手工 taskkill）。所以第一件事就是挂一个超时自杀。
	get_tree().create_timer(300.0).timeout.connect(_on_watchdog)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var city := "oenb"
	if args.size() > 1:
		city = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	# ⚠️ `window_set_size` 在本工程**不生效**（实测出图恒 2560×1600）⇒ 别按它算取景。
	DisplayServer.window_set_size(Vector2i(1600, 900))
	world = WorldBuilder.new()
	add_child(world)
	await get_tree().physics_frame
	world.apply_map(MapDef.oenbelli() if city == "oenb" else MapDef.davao())
	await _frames(20)

	print("==== ① CityRoads 节点 ====")
	var node := world.find_child("CityRoads", true, false)
	if node == null:
		print("  ⚠️ 节点 `CityRoads` **不存在** ⇒ H1 成立")
		get_tree().quit(0)
		return
	var mmi := node as MultiMeshInstance3D
	var mm: MultiMesh = mmi.multimesh
	var mo := mmi.material_override
	print("  实例数 = %d" % mm.instance_count)
	print("  transform_format = %d / 网格 AABB = %s"
		% [mm.transform_format, str(mm.mesh.get_aabb())])
	# ⚠️ `MultiMesh.custom_aabb` 默认是**空的** `AABB(0,0,0 / 0,0,0)`，
	# 而 `MultiMeshInstance3D` **没有** `custom_aabb_mode` 这个属性
	#（上一版探针按 3.x 的记忆写了它 ⇒ `Invalid access to property`，
	#  而带窗口跑时那一条错就让 `_ready()` 静默中断、进程卡死）。
	# 要读"实际用的剔除盒"就读 `GeometryInstance3D.get_aabb()`。
	print("  实例 AABB（Godot 自己算的）= %s" % str(mm.custom_aabb))
	print("  几何 AABB（实际用于剔除）= %s" % str(mmi.get_aabb()))
	print("  可见 = %s / 层 = %d" % [str(mmi.visible), mmi.layers])
	for nm: String in ["CityRoadKerbs", "CityRoadMarks", "CityViaductRing"]:
		var n2 := world.find_child(nm, true, false)
		if n2 == null:
			print("  `%s`：**不存在**" % nm)
		elif n2 is MultiMeshInstance3D:
			print("  `%s`：%d 个实例" % [nm,
				(n2 as MultiMeshInstance3D).multimesh.instance_count])
		elif n2 is MeshInstance3D:
			var ms: Mesh = (n2 as MeshInstance3D).mesh
			print("  `%s`：%d 个面 / %d 个顶点" % [nm, ms.get_surface_count(),
				ms.get_faces().size()])
	if mo is StandardMaterial3D:
		var sm := mo as StandardMaterial3D
		print("  反照率 = %s（**Godot 会把 albedo_color 当 sRGB→线性**：线性值 %.5f）"
			% [str(sm.albedo_color), _srgb_to_linear(sm.albedo_color.r)])
		print("  自发光 = %s / 粗糙 %.2f" % [str(sm.emission), sm.roughness])
	else:
		print("  材质类型 = %s" % ("null" if mo == null else mo.get_class()))

	print("==== ② 定点附近的实例变换（真值）====")
	var near_n := 0
	for i in mm.instance_count:
		var xf := mm.get_instance_transform(i)
		var o := xf.origin
		if absf(o.x - AIM_X) <= 4300.0 and absf(o.z - AIM_Z) <= 4300.0:
			var sc := xf.basis.get_scale()
			print("  #%d 中心 (%.0f, %.1f, %.0f) 尺寸 (%.0f, %.0f, %.0f)"
				% [i, o.x, o.y, o.z, sc.x, sc.y, sc.z])
			near_n += 1
			if near_n >= 8:
				break
	print("  附近实例（±4 300 m）= %d 个" % near_n)

	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 1.0
	cam.far = 400000.0
	add_child(cam)
	cam.current = true

	# ---- ③ 基线图：**正俯视一个十字路口**，覆盖 4 格就是 16 km ⇒ 整幅都是路面走廊 ----
	# 高度取 4 000 m：fov 60 ⇒ 竖向 2×4000×tan30 = 4 619 m，一格 4 025 m 正好铺满。
	var from := Vector3(AIM_X + 0.5, 4000.0, AIM_Z + 0.5)
	cam.global_position = from
	cam.look_at(Vector3(AIM_X, 0.0, AIM_Z), Vector3.UP)
	await _frames(8)
	await _shot("01_topdown_baseline")
	await RenderingServer.frame_post_draw
	var base_img := _grab()

	# ---- ④ **逐层可见性**：每次只藏一层，用"变了多少像素"量各层的**覆盖面积** ----
	#
	# 这一步是上一轮最缺的东西：光看"变红了多少像素"分不清
	# "沥青没渲染"和"沥青被路肩/标线盖住了"。
	# ---- ④a 纯红 A/B（沥青层）----
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(1.0, 0.0, 0.0)
	red.roughness = 0.9
	mmi.material_override = red
	await _frames(8)
	await _shot("02_topdown_red_asphalt")
	await RenderingServer.frame_post_draw
	var red_img := _grab()
	mmi.material_override = mo
	# ---- ④b 藏沥青（其余不动）----
	mmi.visible = false
	await _frames(8)
	await _shot("03_topdown_no_asphalt")
	await RenderingServer.frame_post_draw
	var no_asp := _grab()
	mmi.visible = true
	# ---- ④c 藏路肩 + 标线（只留沥青）----
	var k_node := world.find_child("CityRoadKerbs", true, false)
	var m_node := world.find_child("CityRoadMarks", true, false)
	print("  藏层前：kerbs=%s marks=%s"
		% ["无" if k_node == null else str(k_node.visible),
			"无" if m_node == null else str(m_node.visible)])
	if k_node != null:
		k_node.visible = false
	if m_node != null:
		m_node.visible = false
	await _frames(8)
	await _shot("04_topdown_asphalt_only")
	await RenderingServer.frame_post_draw
	var only_asp := _grab()
	if k_node != null:
		k_node.visible = true
	if m_node != null:
		m_node.visible = true

	if base_img != null and red_img != null and no_asp != null and only_asp != null:
		print("==== ③ 逐层覆盖（采样步长 2）====")
		_report("沥青（纯红 A/B，几何在不在）", base_img, red_img, 1)
		_report("沥青（藏掉沥青 → 画面变了）", base_img, no_asp, 2)
		_report("路肩 + 标线（藏掉 → 画面变了）", base_img, only_asp, 2)

	print("B7_ROAD_AB_DONE -> ", out_dir)
	get_tree().quit(0)


## 逐像素比两张图，打"变了多少像素 / 变了多少亮度"，
## 并给出**变化像素处**与**全图**的基线亮度 —— 这就是"这一层看不看得见"的读数。
func _report(label: String, a: Image, b: Image, thr: int) -> void:
	var w := a.get_width()
	var h := a.get_height()
	var n := 0
	var tot := 0
	var delta := 0.0
	var lum_hit := 0.0
	var lum_all := 0.0
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			var la := (p.r + p.g + p.b) / 3.0
			lum_all += la
			tot += 1
			var dm := absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)
			if dm > 0.012 * float(thr):
				n += 1
				delta += dm / 3.0
				lum_hit += la
	print("  %s：变了 %d / %d 个采样像素（%.2f%%）"
		% [label, n, tot, 100.0 * float(n) / float(maxi(tot, 1))])
	if n > 0:
		print("      变化量均值 %.3f（%.0f/255 每通道）；**该层像素的基线亮度 %.0f/255**（全图 %.0f/255）"
			% [delta / float(n), delta / float(n) * 255.0,
				lum_hit / float(n) * 255.0, lum_all / float(maxi(tot, 1)) * 255.0])


func _srgb_to_linear(c: float) -> float:
	if c <= 0.04045:
		return c / 12.92
	return pow((c + 0.055) / 1.055, 2.4)


## 见 `_ready()` 开头那段 ⚠️：带窗口的探针必须能**自己结束**。
## ⚠️ 用 `create_timer().timeout.connect()` 而**不是** `await` ——
## 协程写成 `_watchdog()` 再"裸调用"会踩 `RETURN_VALUE_DISCARDED` 那类警告，
## 而本工程把 GDScript 警告当错误处理，不值得为一行看门狗冒险。
func _on_watchdog() -> void:
	print("WATCHDOG_TIMEOUT")
	get_tree().quit(3)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## ⚠️ 这里**不能**带 `await` —— 带 await 的函数是**协程**，
## 调用点必须 `await _grab()`，否则 `var img := _grab()` 直接是 Parse Error
##（本轮实测踩过：`Function "_grab()" is a coroutine, so it must be called with "await"`）。
## 取帧的等待因此放在**调用点**（`await RenderingServer.frame_post_draw`）。
func _grab() -> Image:
	var vp := get_viewport()
	if vp == null or vp.get_texture() == null:
		return null
	return vp.get_texture().get_image()


func _shot(shot_name: String) -> void:
	_idx += 1
	await RenderingServer.frame_post_draw
	var img := _grab()
	if img == null:
		print("SHOT_FAILED ", shot_name)
		return
	var p := out_dir.path_join("%02d_%s.png" % [_idx, shot_name])
	print("SHOT %s err=%d" % [p, img.save_png(p)])
