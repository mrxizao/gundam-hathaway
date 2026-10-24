extends Node
## 轮 54 真机出图：**关卡里量产机踩着飞行踏板出击**。
##
## 为什么要出图：这一轮的改动小到只有一行（`spawn_challenge()` 里给玩家配板），
## 而"配上了"（`has_pedal()` 为真）与"**看上去人是站在板上的**"是两件事 ——
## 板与骑手对不齐、插进机体里、偏到机身后方，这些**一个错都不报**，
## 只有画出来才算数（`FlightPedal._align_to_rider()` 那一整套几何是照
## 骑手 `model_bounds` 反推的，各机包围盒不一样）。
##
## 拍四张：
##   ① M02 喀耳刻出击 · **默认追逐机位**（玩家自己的视角 —— 古斯塔夫 + 脚下的喀耳刻板）
##   ② M02 · **侧视挂位**（停掉追逐相机、另摆一台贴近看"人是不是真的站在板上"）
##   ③ M01 夜袭达沃 · 默认机位（马夫蒂板 + 板上**两台**：玩家与僚机共用一块）
##   ④ M01 · 侧视挂位（同上，看两台各自的挂位）
##
## ⚠️ **不能加 `--headless`** —— dummy 渲染器一个像素都不产生，抓出来全黑。
##
## 跑法：
##   godot --path <工程> res://tools/_r54_pedal_shot.tscn -- <输出目录>

var out := "user://r54_pedal_shot"
var main: Node
var _idx := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(1600, 900))

	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _frames(10)

	await _mission("M02", "M02_KILCE")
	await _mission("M01", "M01_MAFTY")
	# ★ M03：老板点名的第二关。玩家开**梅萨指挥官型**（马夫蒂阵营）⇒ 板型应为**马夫蒂**，
	#   而这一关的地图是**低地球轨道**（太空、无大气、背景全星空）⇒ 侧视诊断机位那盏
	#   "跟着镜头走"的平行光在这里格外必要（否则深色机体贴在星空上什么都看不出来）。
	#   ⚠️ M03 还带一段**海面发射升段演出**，演出如果接管相机，`_side_cam()` 的
	#   "遍历摘 current + 出图前重设 + 打印 `cur_cam_now`" 三件套就是自证手段。
	await _mission("M03", "M03_MAFTY")

	print("R54_SHOT_DONE -> %s" % out)
	get_tree().quit(0)


func _mission(id: String, tag: String) -> void:
	if not bool(main.call("_resolve_campaign_match", id)):
		print("SHOT_FAILED(%s 解析失败)" % id)
		return
	main.call("_launch_match")
	await _frames(120)
	var pl = main.get("player")
	if pl == null or not is_instance_valid(pl):
		print("SHOT_FAILED(%s 玩家没起来)" % id)
		return
	var board = pl.pedal_owner() if pl.has_pedal() else null
	# ★ 这一段 print 就是"图里该有什么"的文字对照：有板 / 板型 / 板上几人 / 板在谁身上。
	print("[shot] %s  player=%s  has_pedal=%s  board=%s  riders=%d  owner_in_tree=%s"
		% [id, str(pl.get("display_name")), str(pl.has_pedal()),
			FlightPedal.kind_name(board.kind) if board != null else "-",
			board.riders.size() if board != null else 0,
			str(board.get_parent() == pl) if board != null else "-"])

	# ---- ① 默认机位（真实游戏视角 —— 座舱 HUD 上那行「N 已骑乘 … T 脱离」本身就是证据）----
	_idx += 1
	await _shot("%02d_%s_cockpit" % [_idx, tag])

	# ---- ② 侧视挂位（**关 HUD**，把几何看清）----
	var keep := _side_cam(pl)
	await _frames(8)
	_reaim_side(keep)
	await _frames(1)
	_idx += 1
	await _shot("%02d_%s_side" % [_idx, tag])
	_reaim_side(keep)
	print("[side] %s 出图后 cur_cam_now=%s" % [tag, str(get_viewport().get_camera_3d())])
	_restore_cams(keep)


## 摆一台"从侧上方看骑手"的相机，并**把原来那些相机全部摘掉 current**。
##
## ⚠️ 只停 `chase` 的 `_process` 是不够的 —— 必须**遍历把每台 `Camera3D` 的 current
## 都摘掉**，并关掉 HUD。第一版没做这一步：侧视图拍回来**还是座舱视角、连 HUD 都在**
## （渲染用的压根不是我那台相机）。实测本场景 `find_children("*", "Camera3D")` 只找到
## **1 台** —— 但**别写死"只有一台"**，遍历摘才是稳的。
## ⇒ 出图前后都打印 `get_viewport().get_camera_3d()` 自证"渲染的确实是这台"。
func _side_cam(pl) -> Dictionary:
	var keep := {"cams": [], "hud": null}
	for c in main.find_children("*", "Camera3D", true, false):
		if c is Camera3D:
			keep["cams"].append({"cam": c, "cur": (c as Camera3D).current})
			(c as Camera3D).current = false
	var hud = main.get("hud")
	if hud != null and is_instance_valid(hud):
		keep["hud"] = hud
		hud.visible = false
	var cam := Camera3D.new()
	cam.name = "R54SideCam"
	cam.fov = 45.0
	# ★★ 必须**挂在机体身上**，不能挂 `main`。
	#    前两版都是 `main.add_child(cam)` 之后按**世界坐标**摆在机体侧后方 44 m ——
	#    机体以 558 km/h（≈155 m/s）在飞，等 8 个物理帧出图时机体已经跑掉几十米，
	#    相机被**甩在身后** ⇒ 画面里只剩星空。⚠️ 那时读数**一切正常**
	#    （`cur_cam_now=R54SideCam` 确实是我这台、`cam` 与目标只差 44 m、`cams=1`），
	#    唯一能看出毛病的地方是「**星空里没有挡掉星星的黑块**」—— 说明机体压根不在画面内，
	#    不是"太暗看不见"。挂在机体下 ⇒ 相对位姿恒定，跑多远都跟着。
	pl.add_child(cam)
	var right: Vector3 = pl.right() if pl.has_method("right") else Vector3.RIGHT
	cam.global_position = pl.global_position + right * 40.0 + Vector3.UP * 7.0
	cam.look_at(pl.global_position - Vector3.UP * 4.0, Vector3.UP)
	cam.current = true
	# ⚠️ M01/M02 都是**夜间图**，机体落在受光面之外 ⇒ 深色机体贴在深色星空上。
	#    ⇒ 诊断机位自带一盏"跟着镜头走"的平行光（`DirectionalLight3D` 沿自身 −Z 发射，
	#    挂在相机下 ⇒ 方向恰好 = 相机朝向 ⇒ 把朝向镜头那一面照亮）。诊断图不追求好看。
	#    ⛔ 但这盏灯**只解决"受光"**：前两版的纯黑是**不在画面内**，补光一点忙都帮不上
	#    ⇒ 先判掉"在不在画面内"（看星空里有没有黑块），再考虑补光。
	var key := DirectionalLight3D.new()
	key.name = "R54SideKey"
	key.light_energy = 1.2        # 2.6 会把装甲打成一片白，分件全糊掉
	key.shadow_enabled = false
	key.light_specular = 0.0
	cam.add_child(key)
	keep["mine"] = cam
	keep["pl"] = pl
	return keep


## 出图前**再对一次准**（读数同时证明"出图那一刻用的是我这台相机"）。
func _reaim_side(keep: Dictionary) -> void:
	var cam = keep.get("mine")
	var pl = keep.get("pl")
	if cam == null or pl == null or not is_instance_valid(cam) or not is_instance_valid(pl):
		print("[side] REAIM_FAILED")
		return
	var right: Vector3 = pl.right() if pl.has_method("right") else Vector3.RIGHT
	cam.global_position = pl.global_position + right * 40.0 + Vector3.UP * 7.0
	cam.look_at(pl.global_position - Vector3.UP * 4.0, Vector3.UP)
	var board = pl.pedal_owner() if pl.has_pedal() else null
	print("[side] target=%s pos=%s right=%s cam=%s cur_cam_now=%s board_pos=%s"
		% [str(pl.name), str(pl.global_position), str(right), str(cam.global_position),
			str(get_viewport().get_camera_3d()),
			str(board.global_position) if board != null else "-"])


func _restore_cams(keep: Dictionary) -> void:
	var cam = keep.get("mine")
	if cam != null and is_instance_valid(cam):
		cam.queue_free()
	for e in keep.get("cams", []):
		if e["cam"] != null and is_instance_valid(e["cam"]):
			(e["cam"] as Camera3D).current = e["cur"]
	var hud = keep.get("hud")
	if hud != null and is_instance_valid(hud):
		hud.visible = true


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null:
		print("SHOT_FAILED(no viewport) ", name)
		return
	var tex := vp.get_texture()
	if tex == null:
		print("SHOT_FAILED(no texture) ", name)
		return
	var img := tex.get_image()
	if img == null:
		print("SHOT_FAILED(no image) ", name)
		return
	var path := out.path_join("%s.png" % name)
	print("SHOT %s  %dx%d  err=%d"
		% [path, img.get_width(), img.get_height(), img.save_png(path)])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
