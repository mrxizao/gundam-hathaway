extends Node
## **B7 路面 / 高架 / 肌理 的三件取证**（2026-09-28 · 用户第 ①②③ 条）。
##
## ## 为什么要重做一次
## `_b7_shots.tscn` 那七张实景图**读不出来**：夜战低照度下近处地面与沥青
## 都压进 0~60/255 一档，于是「沥青太黑」与「沥青根本没建」在图上**长得一样**。
## `_b7_road_ab.tscn` 的 A/B 更糟 —— 它的机位在 `(12075, 4000, 12075)`，
## 正落在市中心楼群里（downtown 最高 ≈ 3 780 m），**大部分像素是楼顶**，
## 所以"藏掉沥青只变了 0.13% 的像素"这句话量的是楼顶，不是路面。
##
## ⇒ 本探针把三件事拆成**互相独立、各自可解释**的读数：
##
## | 段 | 做什么 | 回答什么 |
## |---|---|---|
## | **校准** | 打印 `window / visible_rect / texture / image` 四个尺寸 + 用 `unproject_position` 反推 m/px | `unproject` 与图像**不同分辨率**时取样坐标会整体错位（上一版就踩了） |
## | **A 路面** | **只留地面 + 三层路面**（楼/高架/港口/灯全关），正俯视 1 200 m | 四档（地面 / 路肩 / 沥青 / 标线）在 8 位画面里**差多少级** |
## | **B A/B** | 同机位分别藏沥青 / 藏路肩+标线 | "看不见"是**没几何**还是**没对比度** |
## | **C 隔离** | 只留一层 + 无光照洋红 | 每层的**覆盖范围**（连续带？碎片？） |
##
## ⚠️ **正俯视的相机必须显式给 `Basis`**：`look_at()` 在"看向正下方"时是退化情形，
## Godot 会随手滚一个角（上一版滚了 45°），屏幕轴与世界轴对不上 ⇒ 行/列剖面无法解释。
##
## 跑法（**不能加 `--headless`**，dummy 渲染器抓出来全黑）：
##   godot --path <工程> res://tools/_b7_iso.tscn -- <输出目录> [oenb|davao]

const ISO_COL := Color(1.0, 0.12, 0.85)
## A 段只留这几层。⚠️ 名字要**逐个核对**（`CityGround` 是城市地面网格、
## `Ocean` 是海面、`GroundFar` 是远景地面）。
const KEEP_ROAD := ["CityGround", "Ocean", "GroundFar",
	"CityRoads", "CityRoadKerbs", "CityRoadMarks"]

var out_dir := "user://b7_iso"
var city := "oenb"
var world: WorldBuilder
var cam: Camera3D
## ⚠️ 收的是 **`GeometryInstance3D`** 而不是 `VisualInstance3D`：
## `DirectionalLight3D`（太阳）也是 `VisualInstance3D`，但它**没有 `material_override`**
## ⇒ 上一版在这里抛 `Invalid access to property or key` 然后协程静默中断、进程卡死。
var _vis: Array[GeometryInstance3D] = []
var _orig: Dictionary = {}
var _orig_mat: Dictionary = {}
var _idx := 0
var _iso_mat: StandardMaterial3D
## 每像素的世界米数（由校准段实测，见 `_pass_calib()`）。
var _mpp_x := 0.0
var _mpp_z := 0.0


func _ready() -> void:
	# ⚠️⚠️ **看门狗**：带窗口跑时 `_ready()` 里任何一条抛错都会静默中断协程，
	# 而 `quit()` 在最后一行 ⇒ 进程**永远不退出**（实测卡过 14 分钟）。
	get_tree().create_timer(420.0).timeout.connect(_on_watchdog)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		city = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	world = WorldBuilder.new()
	add_child(world)
	await get_tree().physics_frame
	world.apply_map(MapDef.oenbelli() if city == "oenb" else MapDef.davao())
	await _frames(20)

	_collect(world, _vis)
	for x in _vis:
		_orig[x] = x.visible
		_orig_mat[x] = x.material_override
	print("== B7 取证：%s / 可见几何节点 %d 个 / 一格 %.0f m"
		% [world.map.name_cn, _vis.size(), WorldBuilder.CITY_CBLOCK])

	cam = Camera3D.new()
	cam.fov = 60.0
	cam.near = 1.0
	cam.far = 400000.0
	add_child(cam)
	cam.current = true

	await _pass_calib()
	await _pass_road()
	await _pass_iso()

	print("B7_ISO_DONE -> ", out_dir)
	get_tree().quit(0)


# ------------------------------------------------------------------ 校准

func _pass_calib() -> void:
	print("---- 校准 ----")
	await _cam_down(0.0, 0.0, 1200.0)
	var img: Image = await _grab()
	var vp := get_viewport()
	var vis := vp.get_visible_rect().size
	var tex := vp.get_texture().get_size()
	print("  window %s / visible_rect %s / texture %s / image %s"
		% [str(DisplayServer.window_get_size()), str(vis), str(tex), str(img.get_size())])
	var c := cam.unproject_position(Vector3(0.0, 0.0, 0.0))
	var e := cam.unproject_position(Vector3(1000.0, 0.0, 0.0))
	var n := cam.unproject_position(Vector3(0.0, 0.0, 1000.0))
	var kx := float(img.get_width()) / maxf(vis.x, 1.0)
	var ky := float(img.get_height()) / maxf(vis.y, 1.0)
	_mpp_x = 1000.0 / maxf(absf(e.x - c.x), 0.001) / kx
	_mpp_z = 1000.0 / maxf(absf(n.y - c.y), 0.001) / ky
	print("  unproject：中心 %s / +x1km %s / +z1km %s" % [str(c), str(e), str(n)])
	print("  ⇒ 缩放 kx %.4f / ky %.4f ⇒ 图像空间 **%.4f m/px（x）/ %.4f m/px（z）**"
		% [kx, ky, _mpp_x, _mpp_z])


# ------------------------------------------------------------------ A/B 路面

## A 段要量的七个**世界坐标矩形**（在 1200 m 正俯视下都是固定像素区）。
## ⚠️ 它们**全都落在主干道十字附近**（画面只覆盖 ±1108 m）：
##   · `ground` 取块内（楼已关）—— 唯一的"纯地面"基准；
##   · `asphalt_x` 是沿 z 那条主干道的沥青；`asphalt_z` 是沿 x 那条；
##   · `kerb_xR/L` 是前者两侧 175 m 的路肩；`kerb_z` 是后者的路肩。
## ⚠️ `ground` 那一格会被"块内 ≠ 空"误导：楼关掉之后看到的就是**地形本身**，
## 而地形顶点色只由高度定 ⇒ 与楼有没有建无关，可以当基准。
const REGIONS := [
	["ground  ", 600.0, 1000.0, 480.0, 660.0],
	["asph_x  ", -60.0, 60.0, 480.0, 660.0],
	["mark_x  ", 2.0, 20.0, 480.0, 660.0],
	["kerb_xR ", 250.0, 390.0, 480.0, 660.0],
	["kerb_xL ", -390.0, -250.0, 480.0, 660.0],
	["asph_z  ", 600.0, 1000.0, -60.0, 60.0],
	["kerb_z  ", 600.0, 1000.0, -390.0, -250.0],
]


func _pass_road() -> void:
	var rr: float = WorldBuilder.CITY_SHAPE[world.map.city_layout].via_ring_r
	print("---- A/B 路面（只留地面 + 三层路面，楼/高架/港口/灯全关）----")
	await _cam_down(0.0, 0.0, 1200.0)
	var ground_only := ["CityGround", "Ocean", "GroundFar"]
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(1.0, 1.0, 1.0)
	white.roughness = 0.9

	# ---- A0 只有地面（**唯一的地面基准**）----
	_only(ground_only, null)
	var a0: Image = await _grab()
	_shot_img(a0, "A0_ground_only")
	_regions(a0, "A0 只有地面")

	# ---- A1 全开 ----
	_only(KEEP_ROAD, null)
	var a1: Image = await _grab()
	_shot_img(a1, "A1_trunk_cross")
	_regions(a1, "A1 地面+沥青+路肩+标线")

	# ---- A2 藏沥青 ----
	_only(["CityGround", "Ocean", "GroundFar", "CityRoadKerbs", "CityRoadMarks"], null)
	var a2: Image = await _grab()
	_shot_img(a2, "A2_no_asphalt")
	_regions(a2, "A2 无沥青")
	# ---- A3 只沥青 ----
	_only(["CityGround", "Ocean", "GroundFar", "CityRoads"], null)
	var a3: Image = await _grab()
	_shot_img(a3, "A3_asphalt_only")
	_regions(a3, "A3 只沥青")
	print("  [A2] 藏沥青      → 相对 A1 变了 %.2f%% 的像素" % _diff_pct(a2, a1))
	print("  [A3] 藏路肩+标线 → 相对 A2 变了 %.2f%% 的像素（此时画面只剩沥青+地面）"
		% _diff_pct(a3, a2))

	# ---- A4/A5 **反照率上限实验**：把某层换成**纯白 1.0**，看它的区域能亮到多少 ----
	# 这一发是**分水岭**：白得起来 ⇒ 材质/几何/光照都正常，问题只在"比地亮多少"；
	# 白不起来 ⇒ 那一层根本没画在这些像素上（被挡住 / 没出 / 别的东西盖着）。
	_set_override("CityRoadKerbs", white)
	_shot_img(await _grab(), "A4_kerb_white")
	_regions(_last, "A4 路肩→纯白")
	_set_override("CityRoadKerbs", null)
	_set_override("CityRoads", white)
	_shot_img(await _grab(), "A5_asphalt_white")
	_regions(_last, "A5 沥青→纯白")
	_set_override("CityRoads", null)
	_set_override("CityRoadMarks", white)
	_shot_img(await _grab(), "A6_mark_white")
	_regions(_last, "A6 标线→纯白")
	_set_override("CityRoadMarks", null)
	_set_override("CityGround", white)
	_shot_img(await _grab(), "A7_ground_white")
	_regions(_last, "A7 地面→纯白")
	_set_override("CityGround", null)
	_only(KEEP_ROAD, null)

	# ---- A8 低空斜视 ----
	await _cam_to(Vector3(0.0, 300.0, -6000.0), Vector3(0.0, 0.0, 20000.0))
	_shot_img(await _grab(), "A8_low_oblique")

	# ---- A9 环线桥面 ----
	_only(["CityGround", "Ocean", "GroundFar", "CityViaductRing"], null)
	await _cam_down(rr, 0.0, 1800.0)
	var a9: Image = await _grab()
	_shot_img(a9, "A9_ring_section")
	print("  [A9] 环线断面 相机 (%.0f, 1800, 0) / 桥宽 %.0f m"
		% [rr, WorldBuilder.CITY_VIA_W])
	_row_profile(a9, "行= 桥面断面（沿 x）", 128)


## 按节点名前缀找节点，改它的 `material_override`（`null` = 还原）。
func _set_override(prefix: String, m: StandardMaterial3D) -> void:
	for x in _vis:
		if String(x.name).begins_with(prefix):
			x.material_override = m if m != null else _orig_mat.get(x, null)


var _last: Image = null


## 七个矩形的平均亮度（%d 级）。`_mpp_x/_mpp_z` 由校准段实测。
func _regions(img: Image, label: String) -> void:
	if img == null:
		print("  %s：没有帧" % label)
		return
	var out := PackedStringArray()
	for r: Array in REGIONS:
		out.append("%s %5.1f" % [r[0], _patch(img, r[1], r[2], r[3], r[4])])
	print("  %-24s | %s" % [label, " | ".join(out)])


func _patch(img: Image, x0: float, x1: float, z0: float, z1: float) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var c0 := clampi(int(round(float(w) * 0.5 + x0 / _mpp_x)), 0, w - 1)
	var c1 := clampi(int(round(float(w) * 0.5 + x1 / _mpp_x)), c0 + 1, w)
	var r0 := clampi(int(round(float(h) * 0.5 + z0 / _mpp_z)), 0, h - 1)
	var r1 := clampi(int(round(float(h) * 0.5 + z1 / _mpp_z)), r0 + 1, h)
	var acc := 0.0
	var n := 0
	for y in range(r0, r1, 3):
		for x in range(c0, c1, 3):
			var p := img.get_pixel(x, y)
			acc += 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b
			n += 1
	return acc / float(maxi(n, 1)) * 255.0


# ------------------------------------------------------------------ C 隔离图

const ISO_SETS := [
	["roads", ["CityRoads"], ["cross", "obl"]],
	["kerbs", ["CityRoadKerbs"], ["cross", "obl"]],
	["marks", ["CityRoadMarks"], ["cross", "obl"]],
	["ring", ["CityViaductRing"], ["ring", "ringfar"]],
	["via_route", ["CityViaductDeck", "CityViaductRail", "ViaductPier"], ["obl"]],
	["roofs", ["CityRoofs", "CityRoofMech"], ["cross", "blocks", "island"]],
]


func _pass_iso() -> void:
	print("---- C 隔离图（只留一层 + 无光照洋红）----")
	var rr: float = WorldBuilder.CITY_SHAPE[world.map.city_layout].via_ring_r
	var cams := {
		"cross": ["down", Vector3(0.0, 1200.0, 0.0)],
		"obl": ["look", Vector3(-5200.0, 1500.0, -5200.0), Vector3(4200.0, 0.0, 4200.0)],
		"ring": ["down", Vector3(rr, 1800.0, 0.0)],
		"ringfar": ["down", Vector3(rr, 7000.0, 0.0)],
		"blocks": ["down", Vector3(0.0, 9000.0, 0.0)],
		"island": ["down", Vector3(0.0, 26000.0, 0.0)],
	}
	for set_def: Array in ISO_SETS:
		var set_name: String = set_def[0]
		var prefixes: Array = set_def[1]
		var n := _only(prefixes, _iso_material())
		print("  [%s] 只留 %s ⇒ 节点 %d 个" % [set_name, str(prefixes), n])
		for cam_name: String in set_def[2]:
			var cfg: Array = cams[cam_name]
			if cfg[0] == "down":
				await _cam_down(cfg[1].x, cfg[1].z, cfg[1].y)
			else:
				await _cam_to(cfg[1], cfg[2])
			var img: Image = await _grab()
			_shot_img(img, "C_%s_%s" % [set_name, cam_name])
	_restore()


# ------------------------------------------------------------------ 工具

func _collect(n: Node, out: Array[GeometryInstance3D]) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			out.append(c)
		_collect(c, out)


func _show_all() -> void:
	for x in _vis:
		x.visible = _orig.get(x, true)
		x.material_override = _orig_mat.get(x, null)


func _restore() -> void:
	_show_all()


## 只让名字以 `prefixes` 里任一项开头的节点可见。
## `m` 非 null 时给它们套上洋红无光照材质（隔离图用）。
func _only(prefixes: Array, m: StandardMaterial3D) -> int:
	var n := 0
	for x in _vis:
		var nm := String(x.name)
		var on := false
		for p: String in prefixes:
			if nm.begins_with(p):
				on = true
				break
		x.visible = on
		if on:
			n += 1
			if m != null:
				x.material_override = m
	return n


func _iso_material() -> StandardMaterial3D:
	if _iso_mat == null:
		_iso_mat = StandardMaterial3D.new()
		_iso_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_iso_mat.albedo_color = ISO_COL
		_iso_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _iso_mat


## 正俯视：**显式给基**（见文件头）。世界 +X → 屏幕右，世界 +Z → 屏幕下。
func _cam_down(x: float, z: float, h: float) -> void:
	cam.global_transform = Transform3D(
		Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0)),
		Vector3(x, h, z))
	await _frames(6)


func _cam_to(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	await _frames(6)


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null or vp.get_texture() == null:
		return null
	return vp.get_texture().get_image()


## 逐像素差（百分比，按 4 像素步长采样）。⚠️ 必须**同一机位**连拍才成立。
func _diff_pct(a: Image, b: Image) -> float:
	if a == null or b == null:
		return -1.0
	var w := mini(a.get_width(), b.get_width())
	var h := mini(a.get_height(), b.get_height())
	var n := 0
	var tot := 0
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.02:
				n += 1
			tot += 1
	return 100.0 * float(n) / float(maxi(tot, 1))


func _row_profile(img: Image, label: String, nbins: int) -> void:
	if img == null:
		return
	_profile(img, img.get_height() / 2, true, label, nbins)


func _col_profile(img: Image, label: String, nbins: int) -> void:
	if img == null:
		return
	_profile(img, img.get_width() / 2, false, label, nbins)


func _profile(img: Image, fixed: int, horizontal: bool, label: String,
		nbins: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var span := w if horizontal else h
	var step := float(span) / float(nbins)
	var out := PackedStringArray()
	for b in nbins:
		var a0 := int(b * step)
		var a1 := maxi(int(minf((b + 1) * step, float(span))), a0 + 1)
		var acc := 0.0
		var n := 0
		for a in range(a0, a1):
			var c := img.get_pixel(a, fixed) if horizontal else img.get_pixel(fixed, a)
			acc += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
		out.append("%d" % int(round(acc / float(n) * 255.0)))
	var mpp := _mpp_x if horizontal else _mpp_z
	print("  [剖面 %s] %d bin，每 bin %.1f m；中心 bin = 世界 %s %.0f（bin 0 在 −%.0f m）"
		% [label, nbins, step * mpp, "x" if horizontal else "z",
			cam.global_position.x if horizontal else cam.global_position.z,
			span * 0.5 * mpp])
	print("    " + " ".join(out))


func _shot_img(img: Image, shot_name: String) -> void:
	_idx += 1
	_last = img
	if img == null:
		print("SHOT_FAILED ", shot_name)
		return
	var p := out_dir.path_join("%02d_%s.png" % [_idx, shot_name])
	print("SHOT %s err=%d" % [p, img.save_png(p)])


func _on_watchdog() -> void:
	print("WATCHDOG_TIMEOUT")
	get_tree().quit(3)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
