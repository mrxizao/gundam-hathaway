extends Node
## 验收工具：**奥恩贝利夜城**（1.2 第二十二轮精细化之后）搭出来什么样。
##
## 八个机位，各看一件事：
##   ① **高空全景**：岛 + 海湾 + 运河的轮廓读不读得出来（这是"城市"的第一眼）；
##   ② **彩虹桥**：跨海湾的桥、桥下能不能穿；
##   ③ **富士台大楼**：球体瞭望室在不在；
##   ④ **地面停车场**：2026-09-28 拆掉 1:1 独角兽立像之后原地块改成的停车场；
##   ⑤ **会展中心**：四塔 + 倒金字塔；
##   ⑥ **市中心俯瞰**：裙房/退台/窗带/路灯叠出来的层次；
##   ⑦ **低空贴楼**：这张图的主玩法 —— 楼要在视野里"挡路"；
##   ⑧ **中央广场**：树 + 浅水池 + 低层住宅。
##
## 跑法（**不能加 --headless**，headless 是 dummy 渲染器，抓出来全黑）：
##   godot --path <工程> res://tools/city_shots.tscn -- <输出目录>

var out_dir := "user://city_shots"
var _idx := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var world := WorldBuilder.new()
	add_child(world)
	await get_tree().physics_frame
	world.apply_map(MapDef.oenbelli())
	await _frames(20)

	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 1.0
	cam.far = 400000.0
	add_child(cam)
	cam.current = true

	# ⚠️ **机位按"离城市中心的距离"给**，不按竞技场半径。
	# 第二十二轮把整张图放大 2.3 倍时，第一批机位是直接乘 2.3 的 —— 结果
	# ①号（全景）跑到了 70 km 外，城市在雾里缩成一小片、整张图像夜景噪声。
	# 正确的关系是：**机位是去看"那座城"的，城没变大**（`CITY_*` 里只有平面坐标
	# 跟着放大，楼高与街道的观感比例不变），所以机位就该留在原来的米数上。
	# ②③④⑤⑦⑧ 因此全部用**原值**（这些是"贴着地标看"的近景）；
	# 只有 ①（全景）要按城自己的半径放大 —— 用 `CITY_ISLAND_RX` 而不是竞技场半径。
	# ⚠️⚠️ 2026-09-27（达沃重制）：这个 `s` **不能**再写成 `ARENA_RADIUS / 28000.0`。
	#
	# 它想表达的是"把第二十一轮的机位换到**当前城域尺度**"。而 2026-09-27 这一轮
	# 竞技场又 ×2.25（64 400 → 144 900），可是**奥恩贝利的城域坐标一个字没动**
	#（城域坐标按图给，默认 = 现值 —— 见 `WorldBuilder.CITY_SHAPE`）。
	# ⇒ 照旧写法 `s` 会从 2.3 变成 5.175，机位跑到 2.25 倍远，**地标全部出画**。
	# ⇒ 锚定城域：第二十二轮把城域坐标放大 2.3 倍，本轮没动，所以它就是 **2.3**。
	var s := 2.3
	var cblock := WorldBuilder.ARENA_RADIUS / float(WorldBuilder.CITY_GRID)
	var island := WorldBuilder.CITY_ISLAND_RX * cblock
	# ① 高空全景：站到岛缘外侧的斜上方，把整座岛 + 海湾收进画面。
	# ⚠️ 高度**不要超过岛半径的 0.4**：再高就变成"垂直俯视"，塔楼会被压成
	# 地面上的小方块，看不出这是一座立体城市（第一版就压到了 0.62）。
	await _look(cam, Vector3(0.0, island * 0.38, island * 1.18),
		Vector3(0.0, island * 0.06, island * 0.05), "01_overview_island_bay")
	# ② 彩虹桥：⚠️ 2026-09-28 桥**转了 90°（改沿 Z 走、桥心 x = 0）** ⇒ 机位必须跟着转。
	#   旧机位 `(−2000, 1200, 8000) → (7000, 900, CITY_BRIDGE_Z)` 在旧朝向（桥沿 X）
	#   下正好是**侧视**；桥转到 Z 之后这同一条视线变成"**顺着桥身望过去**"，
	#   拍到的是**一条向北消失的带子** —— 看不出这是一座桥（而且斜距 48 km，
	#   双塔都糊在雾里）。⇒ 机位横着挪到**海湾西侧的水上空**（x = −21 km、z = 40 km
	#   那一片是湾里的水，不是岛），目标点抬到桥面以上，让主跨 + 双塔 + 斜拉索入画。
	await _look(cam, Vector3(-21000.0, 2400.0, 40000.0),
		Vector3(0.0, WorldBuilder.CITY_BRIDGE_DECK_Y + 400.0, WorldBuilder.CITY_BRIDGE_Z),
		"02_rainbow_bridge")
	# ③ 富士台大楼（球体）
	await _look(cam, Vector3(2200.0, 1400.0, 1400.0) * s,
		Vector3(-3500.0, 1200.0, -3500.0) * s, "03_fuji_tv_sphere")
	# ④ 地面停车场（2026-09-28：立像已拆，原地块改成停车场）
	# ⚠️ 落位读的是 `_city_cell_center(0, 3)` —— 与 `_build_city_landmarks_oenbelli()`
	# 里那一次调用**同一个函数**。原来这里写的是立像的 `(300, 300, 4900) * s`，
	# 那个位置既不是立像真正该在的格、现在也没有东西可看了。
	var lot := WorldBuilder._city_cell_center(0, 3)
	await _look(cam, lot + Vector3(-2100.0, 900.0, -2100.0),
		lot + Vector3(0.0, 60.0, 0.0), "04_parking_lot")
	# ⑤ 会展中心（Big Sight）：倒金字塔
	await _look(cam, Vector3(-2200.0, 1600.0, -6200.0) * s,
		Vector3(-7200.0, 900.0, -9500.0) * s, "05_big_sight")
	# ⑥ 市中心俯瞰：裙房/退台/窗带/路灯的层次
	await _look(cam, Vector3(5200.0, 3400.0, 4600.0) * s,
		Vector3(-1200.0, 700.0, -1200.0) * s, "06_downtown_layers")
	# ⑦ 低空贴楼：**沿 z = 0 那条主干道看**（主干道在 0），楼要挡路
	await _look(cam, Vector3(7600.0, 620.0, 60.0) * s, Vector3(-2400.0, 620.0, 0.0) * s,
		"07_low_along_main_street")
	# ⑧ 中央广场：树 / 浅水池 / 低层住宅
	await _look(cam, Vector3(0.0, 2600.0, 7200.0) * s, Vector3(0.0, 200.0, 0.0),
		"08_central_plaza")

	print("CITY_SHOTS_DONE -> ", out_dir)
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
	var p := out_dir.path_join("%02d_%s.png" % [_idx, shot_name])
	print("SHOT %s err=%d" % [p, img.save_png(p)])
