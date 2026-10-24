extends Node
## 验收工具：**奥恩贝利的那座地面停车场**（2026-09-28 取代 1:1 独角兽立像）。
##
## 跑法（**不能加 `--headless`**，headless 是 dummy 渲染器，抓出来全黑）：
##   godot --path <工程> res://tools/_park_shots.tscn -- <输出目录> [增益]
##
## ## 三个机位，各看一件事
## | # | 机位 | 看什么 |
## |---|---|---|
## | P1 | 西南斜上方 900 m / 俯角 ~20° | **整个场地**：铺装 + 车位网格 + 停着的车 + 四根灯柱 |
## | P2 | 低空 260 m 顺边掠过 | 车位矮墙的**侧面**（这是"线"看得见的原因）+ 车的体量 |
## | P3 | 南侧 1 300 m 陡俯角 ~43° | **场地里没有楼**（那一格在地标表里被压抑掉了）+ 背后的商场 |
## | P4 | 西南 3.6 km 外低空 | 它**相对周围楼群**的位置与尺度（别只是一块贴在地上的板） |
##
## ## ⚠️ 为什么没有"正俯视"那一档
## 场地的构件里，车位线是 `MultiMesh`、铺装是 `_add_box` —— 两者的**顶面**在
## 死城的掠射天光下**几乎不受光**（`_build_city_street_infra` 那一轮的坑：
## 正俯视拍路面拍出一张纯黑，`err=0`、退出码 0、不报错）。
## ⇒ 机位全部保持 **≥ 20° 的俯角之外仍然有侧面入画**，不加正俯视那一档。
##
## ## ⚠️ 关于**存图增益**
## 奥恩贝利是刻意的"阴天黄昏死城"（全城没有一盏灯），实拍整帧亮度只有 0.003 量级。
## 这里对**存出来的 PNG**乘一个增益（`Image.adjust_bcs`，只动图片、不动渲染），
## 并把增益打进日志 —— 后人比图前必须先看增益。

## ⚠️ 2026-09-28（四块岛那一轮）：格号 **0,3 → 4,2**。
## 依据是详规 §E.1 #4 —— `(4, 2)` 是**独角兽立像本来该在的位**，
## 而这一轮用户的口径是"**拆像换成停车场**"⇒ 换上停车场、**站位不动**。
## 旧格 `(0,3)` 已经归还给住宅地块（`_city_landmark_cell()` 里删掉了），
## 拿旧格号跑这个脚本会拍到一片**正常楼群**、还会以为"停车场没建出来"。
const CELL_GX := 4
const CELL_GZ := 2

var out_dir := "user://park_shots"
var gain := 2.5
var _idx := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		gain = float(args[1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var world := WorldBuilder.new()
	add_child(world)
	await get_tree().physics_frame
	world.apply_map(MapDef.oenbelli())
	await _frames(20)

	# 场地落位：与 `_build_city_landmarks_oenbelli()` 里那一次调用**同一个函数**，
	# 而不是把坐标抄一遍（抄一遍就成了第二份真源，位置一改就对不上）。
	var base := WorldBuilder._city_cell_center(CELL_GX, CELL_GZ)
	var top := base.y + 20.0                      # `ParkDeck` 的顶面
	print("[park] 场地格 (%d,%d) 格心 %s，铺装顶面 %.1f m" % [
		CELL_GX, CELL_GZ, str(base), top])

	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 1.0
	cam.far = 400000.0
	add_child(cam)
	cam.current = true

	# P1 西南斜上方：整场入画
	await _look(cam, base + Vector3(-2100.0, 900.0, -2100.0),
		base + Vector3(0.0, top + 40.0, 0.0), "P1_lot_oblique")
	# P2 低空顺边掠过：车位矮墙的侧面
	await _look(cam, base + Vector3(0.0, top + 240.0, -2500.0),
		base + Vector3(0.0, top + 30.0, 0.0), "P2_lot_low")
	# P3 南侧陡俯角：场地里不许有楼
	await _look(cam, base + Vector3(0.0, 1300.0, 1500.0),
		base + Vector3(0.0, top, -300.0), "P3_lot_steep")
	# P4 远景：它相对周围楼群的位置与尺度
	await _look(cam, base + Vector3(-3500.0, 620.0, -3500.0),
		base + Vector3(0.0, 180.0, 0.0), "P4_lot_in_city")

	print("PARK_SHOTS_DONE -> ", out_dir)
	get_tree().quit(0)


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
	if not is_equal_approx(gain, 1.0):
		img.adjust_bcs(gain, 1.0, 1.0)
	var p := out_dir.path_join("%02d_%s.png" % [_idx, shot_name])
	print("SHOT %s err=%d gain=%.2f" % [p, img.save_png(p), gain])
