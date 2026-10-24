extends Node
## 验收工具：**奥恩贝利的水系**（运河 / 海湾 / 岸线）——
## 用**同一份脚本**在「改前」与「改后」两个工程里各跑一遍，
## 拿到**同机位、同增益**的两组图 + 一份数值 dump，做真正的 A/B。
##
## 跑法（**不能加 `--headless`**，headless 是 dummy 渲染器，抓出来全黑）：
##   godot --path <工程> res://tools/_oen_water.tscn -- <输出目录> <增益> <legacy 0/1>
##
## ## ⚠️⚠️ 这个脚本必须能**同时**在两版工程里跑 —— 所以有三条自我约束
## 1. **只许用两版都有的 API**：不许引用 `CITY_WATER_Y`（改前不存在）、
##    不许引用 `city_road_width()`（改前不存在）、不许引用 `CITY_SHAPE`（改前不存在）。
## 2. **机位坐标一律写字面量**，不读常量 —— 这样两版的机位**逐位相同**，
##    图与图之间才可比。（读常量的话，改后把常量一改，机位就跟着漂了。）
## 3. `_city_landform` / `is_water_at` 的**参数个数两版不同**（改前 2 个、改后 3 个），
##    所以一律用 `Callable.callv()` **动态**调 —— 静态调用会在编译期做元数检查，
##    改前那版会直接**解析失败**。
##
## ## 六张图，各看一件事
## | # | 机位 | 看什么 |
## |---|---|---|
## | W1 | 运河正上方 1.25 km，顺轴朝海湾 | 运河**是不是一条连续的水道**、尽头接不接得到海湾 |
## | W2 | 城心一侧朝运河斜看 | **运河横切面**：水 / 岸 / 坡 / 第一排楼 |
## | W3 | 海湾一侧朝河口看 | **河口**：水 → 口门 → 陆，两层水体的接法 |
## | W4 | 湾岸线斜看 | 岸线是不是一条干净的线（这条最容易被"水面偏高"污染） |
## | W5 | 西南高空斜看全城 | 城 + 运河 + 湾**同框**，读整座水系的结构 |
## | W6 | 城缘朝内陆平视 | **外围丘陵环带**的高度（这一条给"丘陵 ×3"用） |
##
## ## ⚠️ 增益必须两版**相同**
## 奥恩贝利是刻意的"阴天黄昏死城"，整帧亮度极低。存图时乘一个增益
##（`Image.adjust_bcs`，只动 PNG、不动渲染）是为了肉眼可判 ——
## **但两版必须取同一个增益**，否则"新旧哪个暗"这件事就被增益吃掉了，
## 对照图直接作废。增益会打进日志与文件名旁边。

## 数值 dump 的采样点数（`N × N`）。
## ⚠️ 这一份是**证据**：两版跑同一个网格、同一套格式 ⇒ 逐字节 `diff` 就能回答
## "河流/地形的几何到底动没动"。比看图猜可靠得多（图的差别可能是配色、光照、增益）。
const DUMP_N := 200
## 采样范围（米）。刻意**跨过运河两岸 + 河口 + 一段海湾**。
const DUMP_X0 := -20000.0
const DUMP_X1 := 40000.0
const DUMP_Z0 := -30000.0
const DUMP_Z1 := 40000.0

## 城域坐标（**字面量**，不读常量 —— 见函数头第 2 条）。
const CANAL_X := 14260.0
const CANAL_HALF := 2070.0
const CANAL_END_Z := 26450.0
const BAY_Z := 29900.0

var out_dir := "user://oen_water"
var gain := 2.0
var legacy := false
var _idx := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		gain = float(args[1])
	if args.size() > 2:
		legacy = args[2] == "1"
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var world := WorldBuilder.new()
	add_child(world)
	await get_tree().physics_frame
	world.apply_map(MapDef.oenbelli())
	await _frames(20)
	print("[water] 跑法：out=%s gain=%.2f legacy=%s" % [out_dir, gain, legacy])

	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 1.0
	cam.far = 400000.0
	add_child(cam)
	cam.current = true

	# W1 运河正上方，顺轴朝海湾（+Z 是水那一侧）。
	await _look(cam, Vector3(CANAL_X, 1250.0, 1000.0),
		Vector3(CANAL_X, 150.0, 31000.0), "W1_canal_axis_to_bay")
	# W2 从城心一侧朝运河斜看（横切面）。
	await _look(cam, Vector3(2000.0, 1000.0, 8000.0),
		Vector3(CANAL_X, 0.0, 4000.0), "W2_canal_across")
	# W3 从海湾一侧朝河口看（水 → 口门 → 陆）。
	await _look(cam, Vector3(CANAL_X, 1150.0, 34500.0),
		Vector3(CANAL_X, 0.0, 23000.0), "W3_canal_mouth")
	# W4 湾岸线斜看：岸线是不是一条干净线。
	await _look(cam, Vector3(-6000.0, 1300.0, 39000.0),
		Vector3(-12000.0, 250.0, 25000.0), "W4_bay_coast")
	# W5 西南高空斜看全城：城 + 运河 + 湾同框。
	await _look(cam, Vector3(-26000.0, 1400.0, -22000.0),
		Vector3(6000.0, 200.0, 10000.0), "W5_whole_sw")
	# W6 城缘朝内陆平视：外围丘陵环带的高度。
	await _look(cam, Vector3(0.0, 1350.0, -28000.0),
		Vector3(0.0, 700.0, -75000.0), "W6_hill_ring")

	await _dump()
	print("OEN_WATER_DONE -> ", out_dir)
	get_tree().quit(0)


## 200×200 个点的 `_city_landform` + `is_water_at`，写成 CSV。
##
## ⚠️ 格式必须是**两版能逐字节比**的形式：定点小数（不用 `str(float)` 的
## 默认科学计数）、固定列序、`\n` 行尾（Windows 上 `FileAccess` 默认就是 `\n`）。
func _dump() -> void:
	var f := FileAccess.open(out_dir.path_join("landform.csv"), FileAccess.WRITE)
	if f == null:
		print("[water] dump 打开失败")
		return
	# ⚠️ 动态调用：两版的参数个数不同（见文件头第 3 条）。
	var fn_land := Callable(WorldBuilder, "_city_landform")
	var fn_water := Callable(WorldBuilder, "is_water_at")
	f.store_line("# x,z,landform,is_water,legacy=%d" % (1 if legacy else 0))
	for j in DUMP_N:
		var z: float = DUMP_Z0 + (DUMP_Z1 - DUMP_Z0) * float(j) / float(DUMP_N - 1)
		for i in DUMP_N:
			var x: float = DUMP_X0 + (DUMP_X1 - DUMP_X0) * float(i) / float(DUMP_N - 1)
			var a: Array = [x, z]
			if not legacy:
				a.append(MapDef.CityLayout.OENBELLI)
			var h: float = float(fn_land.callv(a))
			var w: int = 1 if bool(fn_water.callv(a)) else 0
			f.store_line("%.4f,%.4f,%.4f,%d" % [x, z, h, w])
	f.close()
	print("[water] dump -> %s（%d 点）" % [out_dir.path_join("landform.csv"), DUMP_N * DUMP_N])


func _look(cam: Camera3D, from: Vector3, at: Vector3, shot_name: String) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	await _frames(8)
	await _shot(shot_name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(shot_name: String) -> void:
	_idx += 1
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null or vp.get_texture() == null:
		print("SHOT_FAILED ", shot_name)
		return
	var img := vp.get_texture().get_image()
	if img == null:
		print("SHOT_FAILED(img) ", shot_name)
		return
	# ⚠️ 增益只动存出来的 PNG，不动渲染、不动统计口径（见文件头）。
	if not is_equal_approx(gain, 1.0):
		img.adjust_bcs(gain, 1.0, 1.0)
	var p := out_dir.path_join("%02d_%s.png" % [_idx, shot_name])
	print("SHOT %s err=%d gain=%.2f" % [p, img.save_png(p), gain])
