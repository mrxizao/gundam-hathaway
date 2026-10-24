extends Node
## ★63-9 B1 真机出图：**踏板上的骑手只有一个轮廓**（不叠影）。
##
## ## 为什么要出图
##
## B1 的现场是「古斯塔夫、梅萨在踏板上的时候会穿模看到梅萨和古斯塔夫的胸部模型」——
## 那是**像素**上的事。无头套件能断"骑手自己的模型不可见"（`model_root` 在树里可见性为假），
## 但"看不见"这件事**只有画出来才算数**（挂件判据的老教训：只断节点存在会两条都绿却看不见）。
##
## ## 每关拍四张
##
##   ① **座舱/追逐机位**（HUD 在）—— 玩家当初报问题时的视角；
##   ② **宽景侧视**（HUD 关，瞄**板**）—— 板与骑手的整体关系；
##   ③ **近景侧视**（瞄**骑手**）—— 判"踏板区域有几个机体轮廓"，**这是主判据图**；
##   ④ **负对照**：把骑手的判据**人为撤销**（`set_rider_hidden(false)`，等价于修复前
##      `main` 每帧把模型顶回来的效果）⇒ **同一台相机、同一个体位**，只差"藏/没藏"一个变量。
##
## ③④ 逐位对照 ⇒ 差异只可能来自叠影。判据图就是这一对。
##
## ⚠️ 近景**必须瞄骑手**：板长 50~57 m、骑手只有 22 m，只瞄板的话骑手小到数不清轮廓。
## ⚠️ 不能加 `--headless`：dummy 渲染器一个像素都不产生，抓出来全黑。
##
## 跑法：
##   godot --path <工程> res://tools/_r63_9_b1_shot.tscn -- <输出目录>

var out := "user://r63_9_b1_shot"
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

	# ⚠️ M02/M03 带**发射升段演出**（演出期间相机被接管）⇒ 多等一会儿，
	# 等演出走完、机体姿态稳定下来再摆诊断机位。
	await _mission("M02", "M02_KILCE", 330)
	await _mission("M01", "M01_MAFTY")
	await _mission("M03", "M03_MAFTY", 240)

	print("R63_9_B1_SHOT_DONE -> %s" % out)
	get_tree().quit(0)


func _mission(id: String, tag: String, settle := 120) -> void:
	if not bool(main.call("_resolve_campaign_match", id)):
		print("SHOT_FAILED(%s 解析失败)" % id)
		return
	main.call("_launch_match")
	await _frames(settle)
	var pl = main.get("player")
	if pl == null or not is_instance_valid(pl):
		print("SHOT_FAILED(%s 玩家没起来)" % id)
		return
	var board = pl.pedal_owner() if pl.has_pedal() else null
	if board == null:
		print("SHOT_SKIP(%s 玩家没有板)" % id)
		return

	# ★ 这一段 print 就是"图里该有什么"的文字对照。
	#   `model_visible()` = 骑手**自己那台**模型在树里可不可见；
	#   `hidden` = 两条判据里"板上有人吗"那一条。
	print("[shot] %s player=%s board=%s vis=%d riders=%d"
		% [id, str(pl.profile.display_name), FlightPedal.kind_name(board.kind),
			board.vis_state(), board.riders.size()])
	_dump_riders(board, tag, "fixed")

	# ---- ① 座舱/追逐机位（玩家当初报问题的视角，HUD 留着）----
	_idx += 1
	await _shot("%02d_%s_cockpit" % [_idx, tag])

	# ---- 建诊断相机（只有一台 ⇒ `cur_cam_now` 的自证只需一次）----
	var keep := _side_cam(pl, board)
	await _frames(8)

	# ---- ② 宽景：瞄**板**（板与骑手的整体关系）----
	await _pose(keep, board, 67.0, 26.0)
	_idx += 1
	await _shot("%02d_%s_wide" % [_idx, tag])

	# ---- ③ 近景：瞄**骑手**（主判据图 —— 数轮廓）----
	await _pose(keep, pl, 34.0, 9.0)
	_idx += 1
	await _shot("%02d_%s_close_fixed" % [_idx, tag])

	# ---- ④ 负对照：同一机位、只剩"藏/没藏"一个变量 ----
	for r in board.riders:
		if r != null and is_instance_valid(r):
			r.set_rider_hidden(false)
	_dump_riders(board, tag, "negctrl")
	await _pose(keep, pl, 34.0, 9.0)
	_idx += 1
	await _shot("%02d_%s_close_NEGCTRL" % [_idx, tag])

	# 还原判据（免得影响下一关）
	for r in board.riders:
		if r != null and is_instance_valid(r):
			r.set_rider_hidden(true)
	print("[side] %s 出图后 cur_cam_now=%s" % [tag, str(get_viewport().get_camera_3d())])
	_restore_cams(keep)


func _dump_riders(board, tag: String, why: String) -> void:
	print("[%s] %s riders=%d" % [why, tag, board.riders.size()])
	for i in board.riders.size():
		var r = board.riders[i]
		if r == null or not is_instance_valid(r):
			continue
		print("       rider[%d] slot=%d suit=%s hidden=%s model_visible=%s in_tree=%s"
			% [i, r.pedal_slot, str(r.profile.display_name), str(r.rider_hidden),
				str(r.model_visible()),
				str(r.model_root.is_visible_in_tree()) if r.model_root != null else "-"])


## 摆一台诊断相机（**挂在机体身上**），并**把原来那些相机全部摘掉 current**。
##
## ⚠️ 必须**遍历摘**（别写死"只有一台"）；出图前后都打印 `get_viewport().get_camera_3d()`
## 自证"渲染的确实是这台"（之前的探针踩过"相机不是它、读数却全对"的坑）。
## ⚠️ 挂 `pl` 而不是 `main`：按世界坐标摆的话，等 8 个物理帧出图时机体已经跑掉几十米，
## 相机被甩在身后 ⇒ 画面里只剩星空（★63-9 之前实测过，而且那时读数一切正常）。
func _side_cam(pl, board) -> Dictionary:
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
	cam.name = "R63_9SideCam"
	cam.fov = 45.0
	pl.add_child(cam)
	cam.current = true
	# 诊断机位自带一盏跟着镜头走的平行光（深色机体贴在深色背景上什么都看不出来）。
	var key := DirectionalLight3D.new()
	key.name = "R63_9SideKey"
	key.light_energy = 1.2
	key.shadow_enabled = false
	key.light_specular = 0.0
	cam.add_child(key)
	keep["mine"] = cam
	keep["pl"] = pl
	keep["board"] = board
	return keep


## 把诊断相机摆到"从机体右侧、抬高若干米、看向 `aim_node`"。
##
## ∧ 出图**前**再对一次准（读数同时证明"出图那一刻用的是我这台相机"）。
func _pose(keep: Dictionary, aim_node, dist: float, up: float) -> void:
	var cam = keep.get("mine")
	var pl = keep.get("pl")
	if cam == null or not is_instance_valid(cam) or not is_instance_valid(pl):
		print("[side] REAIM_FAILED")
		return
	var aim: Vector3 = aim_node.global_position if aim_node != null \
		and is_instance_valid(aim_node) else pl.global_position
	# ⚠️⚠️ **不许用 `pl.right()`** —— 它跟着机体的**滚转**走：机体一旦压坡度转弯，
	# `right` 就指向上/下，相机跑到机体的**正上（下）方**俯视，画面里骑手缩成一小块，
	# 根本数不清轮廓（实测 M02 就是这样，M01/M03 当时恰好是平的才没事）。
	# ⇒ 一律用**水平面内的右向量**（由水平航向算出）⇒ 机位恒在"侧面"，
	# 不受滚转/俯仰影响，三关的图才可比。
	var right := _flat_right(pl)
	cam.global_position = aim + right * dist + Vector3.UP * up
	cam.look_at(aim, Vector3.UP)
	await _frames(6)
	print("[side] aim=%s d=%.1f up=%.1f cam=%s cur_cam_now=%s"
		% [str(aim_node.name) if aim_node != null else "-", dist, up,
			str(cam.global_position), str(get_viewport().get_camera_3d())])


## 机体在**水平面内**的右向量（不受滚转/俯仰影响）。
##
## 退化情况（机体正朝上/朝下飞）回落到机体自身的右向量 —— 那种姿态下"侧面"本来就没有定义，
## 至少保证不崩、不报 colinear 警告。
func _flat_right(pl) -> Vector3:
	var fwd: Vector3 = -pl.global_transform.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length() < 0.05:
		return pl.right() if pl.has_method("right") else Vector3.RIGHT
	return flat.normalized().cross(Vector3.UP).normalized()


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
