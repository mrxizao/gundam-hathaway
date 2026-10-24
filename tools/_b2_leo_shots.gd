extends Node
## 判据图：**低地球轨道**（`Id.LEO` / `Terrain.SPACE`）—— 剧情模式轮 B2。
##
## 跑法（**不能加 `--headless`**：headless 是 dummy 渲染器，抓出来全黑）：
##   godot --path <工程> res://tools/_b2_leo_shots.tscn -- <输出目录>
##
## ## 为什么必须出图，而不是只跑断言
## 本轮那 123 条断言能证明"**没有**建出地表 / 海面 / 碰撞地板 / 云"，但证明不了
## **"剩下的东西看起来像不像轨道"**。设计稿 §4.8.8 点名要看的正是后者。
##
## ## 六张图各自的判据（没有一张是"顺手拍的"）
## | # | 名 | 机位 | 要读出什么 |
## |---|---|---|---|
## | 0 | `overview_belt` | 场心上方 42 km、俯角 35° | **尺度参照**：碎片带 + 运输仓 + 卫星在一片黑里可读；**底下没有地表** |
## | 1 | `level_along_belt` | 出生高度 3 200 m、出生环上沿**切向**看 | 开局那一眼：参照物在 km 级、能读出"我在动" |
## | 2 | `hug_reentry_line` | **320 m 贴再入线**（与图 1 同方位、同朝向） | ★ 底下**什么都没有** —— 没有海面、没有地平线、没有碰撞地板 |
## | 3 | `look_up_stars` | 3 200 m，抬头 **90°** | ★ 天顶真空黑 + 星空满额（`star_amount = 1.0`） |
## | 4 | `look_down_earth` | 3 200 m，低头 **90°** | ★ 全屏 = **地球反照色**（往下看是地球本体，不是更黑） |
## | 5 | `earth_limb_band` | 3 200 m，俯角 **12°** | ★ 那条**有厚度的临边亮带**（`ground_blend = 0.55`，默认 0.18 的三倍厚） |
##
## ## ⚠️ 三条自我约束（前两条是**这个工程已经踩过的坑**）
## 1. **不抬头/低头用 `look_at()`**。`look_at(from + UP)` 与 `up = UP` **共线** ⇒
##    朝向退化成未定义（`godot-headless-probe-shots` 记过这一类静默失败：
##    不报错、不警告，相机"看着像动了"其实是随便一个朝向）。
##    ⇒ 图 3 / 图 4 一律**直接写 `rotation_degrees`**（±90° 是解析式可验的）。
## 2. **增益一律 1.0，不做「为了看得清」的提亮**。这一轮要证的**恰恰是"黑"**
##    （真空、没有地表）。给一张"真空黑"的图乘 2.5 倍增益，等于把判据本身改掉。
##    ⇒ 取而代之：每张图**打印像素读数**（均值 / p99 / 亮像素占比），
##       让"黑"是一个**数**，而不是"我看着挺黑的"。
## 3. **落位不写坐标**：出生环半径取 `WorldBuilder.SPAWN_RADIUS`、高度取
##    `PLAYER_START_ALT`、再入线取 `MissionScript.REENTRY_ALT`、
##    运输仓取 `WorldBuilder.SPACE_POD_POS` —— 全是真源。
##    唯一写字面量的是**取景偏移**（那是相机的事，不是地图的坐标）。

var out_dir := "user://b2_leo_shots"
var _idx := 0
var _world: WorldBuilder


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	# ⚠️⚠️ **必须同时切窗口模式与尺寸** —— 只设尺寸的话，若玩家设置里是全屏
	# （`Settings.fullscreen`），窗口仍是全屏。本探针第一版就漏了这一行，
	# 于是"1600×900 的判据图"实际是 **2560×1600**（笔记本屏原生分辨率），
	# 而日志里一个警告都没有 —— 它只是让每张图多算了 2.8 倍的像素（A/B 逐像素比更慢），
	# 以及让"占画面千分之几"这类结论的**分母**与别的探针不可比。
	# 这段被 `tests/pixprobe.gd:141` 的原话记着，照抄它即可（同一个坑，第二次踩）。
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	_world = WorldBuilder.new()
	add_child(_world)
	await get_tree().physics_frame
	_world.apply_map(MapDef.leo())
	await _frames(24)

	# ---- 先自证前提：这一局真的是那张图，而且真的没有地表 ----
	var m: MapDef = _world.get("map")
	print("[b2] 地图 = %s（%s）terrain = %d  has_ground = %s  cloud_density = %.2f"
		% [m.code, m.name_cn, m.terrain, str(m.has_ground), m.cloud_density])
	var terrain: Node = _world.get("_terrain_root")
	print("[b2] `_terrain_root` 下 %d 个节点；`ocean` = %s；`_cloud_root` 下 %d 个节点"
		% [terrain.get_child_count(), str(_world.get("ocean")),
			(_world.get("_cloud_root") as Node).get_child_count()])
	for bad: String in ["Islands", "GroundFar", "GroundCollision", "Ocean"]:
		var hit := terrain.find_child(bad, true, false) != null \
			or (bad == "Ocean" and _world.get("ocean") != null)
		print("[b2]   %-16s %s" % [bad, "**在** ⚠️" if hit else "不在 ✓"])

	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 1.0
	cam.far = 900000.0
	add_child(cam)
	cam.current = true

	await _overview(cam)
	await _level(cam)
	await _pitch(cam)

	print("B2_LEO_SHOTS_DONE -> ", out_dir)
	get_tree().quit(0)


# ------------------------------------------------------------- ⓪ 场地总览

## 从场心正上方俯看：**碎片带是一整圈、运输仓在正中** —— 尺度参照本身要被看见。
func _overview(cam: Camera3D) -> void:
	var b := WorldBuilder.SPACE_BELT_R
	print("[b2] 碎片带 R = %.0f m（= SPAWN_RADIUS）、件数 %d、尺寸 %.0f…%.0f m；运输仓在 %s"
		% [b, WorldBuilder.SPACE_BELT_N, WorldBuilder.SPACE_DEBRIS_MIN,
			WorldBuilder.SPACE_DEBRIS_MAX, str(WorldBuilder.SPACE_POD_POS)])
	# 俯角 35° ⇒ 机位水平偏移 = H / tan 35°。取 H = 42 km ⇒ 偏移 60 km（各轴 42.4 km），
	# 整圈（R = 46.6 km ⇒ 直径 93 km）在 60° 竖 fov 下框得住。
	var off := 42400.0
	await _look(cam, Vector3(-off, 42000.0, -off), Vector3.ZERO, "00_overview_belt")


# ------------------------------------------------------------- ① 平飞（两档高度）

## 同一个方位、同一个朝向，只换高度：**3 200 m（出生）** 与 **320 m（贴再入线）**。
##
## 两张成对看才有意义 —— 如果下方真有一层地表，320 m 那张的**下缘**必然出现地面/海面；
## 它什么都没有，才是"底下真的没有东西"。
func _level(cam: Camera3D) -> void:
	var r: float = WorldBuilder.SPAWN_RADIUS
	var a := -95.0
	var from := _world.spawn_point(a, r, WorldBuilder.PLAYER_START_ALT)
	# 切向 = (cos(θ+90°), 0, sin(θ+90°))，θ = −95° ⇒ (0.9962, 0, −0.0872)。
	var th := deg_to_rad(a + 90.0)
	var tang := Vector3(cos(th), 0.0, sin(th))
	var base := Vector3(from.x, 0.0, from.z)
	print("[b2] 出生点（方位 %.0f°，R %.0f）= (%.0f, %.0f, %.0f)；切向 = (%.4f, 0, %.4f)"
		% [a, r, from.x, from.y, from.z, tang.x, tang.z])
	print("[b2] 再入线（`MS.REENTRY_ALT`）= %.0f m；地面杀线（`FlightBody.CRASH_ALTITUDE`）= %.0f m"
		% [MissionScript.REENTRY_ALT, FlightBody.CRASH_ALTITUDE])

	# ① 出生高度：远处 30 km 处压低 1 200 m ⇒ 俯角 ≈ 2.3°（**近乎水平**）。
	await _look(cam, from, from + tang * 30000.0 + Vector3.DOWN * 1200.0,
		"01_level_along_belt_3200")
	# ★ 立刻做一次 A/B 诊断：**碎片带到底在不在画面里**。
	# 首跑的读数暴露了一个真问题 —— 同朝向、只把机位从 3 200 m 降到 320 m，
	# 整帧均值一模一样（0.06403）。那说明这一帧**几乎全是天空**（天空只与**朝向**有关），
	# 而"尺度参照"（碎片带）在画面上**约等于零**。⇒ 必须先量清楚是**没进画面**
	# 还是**进了但看不见**，否则"补一个更亮的材质"这种改法可能修的是另一个问题。
	await _debris_diag(cam)
	# ★ 再量设计稿真正关心的那件事：「**读得出速度与远近**」（§4.8.6 的措辞）。
	await _motion_diag(cam)
	# ② 贴再入线：只把高度换成 320 m（≈ 再入线之上 320 m，仍是"平飞"）。
	await _look(cam, Vector3(base.x, 320.0, base.z),
		Vector3(base.x, 320.0, base.z) + tang * 30000.0 + Vector3.DOWN * 1200.0,
		"02_hug_reentry_line_320")


# ------------------------------------------------------------- ② 抬头 / 低头

## 三张**纯朝向**图，机位固定在出生点上（不挪位 ⇒ 三张互为严格对照）。
##
## ⚠️ 不 `look_at`（见文件头第 1 条），直接写 `rotation_degrees`：
## 相机沿 −Z 看；绕 X 转 +90° 把 −Z 送到 **+Y**（抬头），−90° 送到 **−Y**（低头）。
func _pitch(cam: Camera3D) -> void:
	var p := _world.spawn_point(-95.0, WorldBuilder.SPAWN_RADIUS, WorldBuilder.PLAYER_START_ALT)
	print("[b2] 抬头/低头三张的机位都固定在 (%.0f, %.0f, %.0f)（只改朝向）"
		% [p.x, p.y, p.z])
	# ③ 抬头 90°：天顶真空黑 + 星空。yaw 取 −95° 与出生方位一致，三张同 yaw。
	cam.global_position = p
	cam.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	await _frames(10)
	await _shot(cam, "03_look_up_stars", "pitch +90°（天顶）")
	# ④ 低头 90°：全屏应当是**地球反照色**（不是黑）。
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	await _frames(10)
	await _shot(cam, "04_look_down_earth", "pitch −90°（正下方）")
	# ⑤ 俯角 12°：把**临边那条有厚度的带**拍进来（`ground_blend = 0.55`）。
	#    ⚠️ 这条带只在 **up ≈ 0** 附近成立（`sky.gdshader:74`：
	#    `mix(col, ground, smoothstep(0.015, -ground_blend, up))`）——
	#    正下方（up = −1）已经是纯 `ground` 色，**拍不到带**。
	#    ⇒ 必须稍微偏离水平，"临边"才在画面里。
	cam.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	await _frames(10)
	await _shot(cam, "05_earth_limb_band", "pitch −12°（临边带）")


# ------------------------------------------------------------- 诊断：碎片带到底在不在画面里

## **两个读数分开量**，因为它们的修法完全不同：
##   ① `in_frustum` —— 有几件真在视锥里（= 0 就是**摆位**问题）；
##   ② `ab_px`     —— 把碎片带 `visible = false` 前后**逐像素比**，数出真正变了多少像素
##                    （= 这是**唯一**能区分"画了但看不见"和"压根没画"的读数）。
##
## ⚠️⚠️ **② 必须先把动画时钟冻住** —— 这是本函数第一次写就踩的坑。
## 第一版直接 `visible = false` 之后 `await` 几帧再抓图，报出 **11 604** 个像素变了、
## 最大单像素变化 0.698。看上去是"碎片带画得好好的"，其实**这 11 604 里有绝大部分是
## 星空自己在闪**（`_advance_anim_time()` 每帧推进 `sky_time`，星点是 1 像素级的硬点，
## 抖动幅度接近 1.0）。**判据被它自己的被测量污染了** —— 与 `suite_scene_gain` 那条
## "增益必须进材质缓存 key，否则探针同一次运行里扫第二档会拿到第一档"是同一类错。
## ⇒ 先 `set_process(false)` 掐掉时钟，再抓 A/B；比完恢复。
##
## ⚠️ 也不用"均值差"代替逐像素比：碎片只占画面千分之几，均值差会被量化噪声吃掉
##（首跑那两张平飞图均值一字不差，但 md5 不同、文件大小差 111 字节 —— 差异真的存在，
##  只是**低于均值这个统计量能分辨的尺度**）。这正是"换一个判据才看得见"的典型。
func _debris_diag(cam: Camera3D) -> void:
	var mm := _world.find_child("SpaceDebris", true, false) as MultiMeshInstance3D
	if mm == null:
		print("[b2][diag] **没找到 SpaceDebris**")
		return
	var n := mm.multimesh.instance_count
	var in_frustum := 0
	var nearest := 1.0e18
	var far_most := 0.0
	var on_screen := ""
	for i in n:
		var t := mm.multimesh.get_instance_transform(i)
		var wp := mm.global_transform * t.origin
		var d := cam.global_position.distance_to(wp)
		nearest = minf(nearest, d)
		far_most = maxf(far_most, d)
		if cam.is_position_in_frustum(wp):
			in_frustum += 1
			on_screen += "%.1fkm " % (d / 1000.0)
	print("[b2][diag] 碎片带 %d 件；到机位 %.1f…%.1f km" % [n, nearest / 1000.0, far_most / 1000.0])
	print("[b2][diag] ① 在视锥里 = **%d / %d**（距离：%s）" % [in_frustum, n, on_screen.strip_edges()])

	# ---- ② A/B（**时钟冻住**，见函数头那段）----
	_world.set_process(false)
	await RenderingServer.frame_post_draw
	var a := get_viewport().get_texture().get_image()
	if a == null:
		_world.set_process(true)
		print("[b2][diag] 取不到 A 帧")
		return
	a = a.duplicate() as Image
	mm.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var b := get_viewport().get_texture().get_image()
	mm.visible = true
	_world.set_process(true)
	if b == null:
		print("[b2][diag] 取不到 B 帧")
		return
	b = b.duplicate() as Image

	var diff := 0
	var max_d := 0.0
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-1, -1)
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var dd := maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), absf(ca.b - cb.b))
			if dd > 1.0 / 255.0:
				diff += 1
				max_d = maxf(max_d, dd)
				lo.x = mini(lo.x, x)
				lo.y = mini(lo.y, y)
				hi.x = maxi(hi.x, x)
				hi.y = maxi(hi.y, y)
	print("[b2][diag] ② 拿掉碎片带之后变了 **%d** 个像素（占 %.3f%%）；最大单像素变化 %.3f"
		% [diff, 100.0 * float(diff) / float(a.get_width() * a.get_height()), max_d])
	if diff == 0:
		print("[b2][diag] ⇒ **一件都没画出像素**：材质 / 可见性问题，不是「不够亮」")
	else:
		print("[b2][diag] ⇒ 分布范围 x [%d, %d] × y [%d, %d]（视口 %d×%d）"
			% [lo.x, hi.x, lo.y, hi.y, a.get_width(), a.get_height()])
		# ---- 放大裁剪：**碎片在画面里的实际大小**必须能被人眼读到 ----
		# ⚠️ 用**最近邻**放大（`Image.resize(..., INTERPOLATE_NEAREST)`）：
		# 插值放大出来的"柔边碎片"会让人误以为它们比实际更清楚。
		var pad := 60
		var r := Rect2i(lo - Vector2i(pad, pad),
			Vector2i(hi.x - lo.x + 1 + pad * 2, hi.y - lo.y + 1 + pad * 2))
		r = r.intersection(Rect2i(0, 0, a.get_width(), a.get_height()))
		var crop := a.get_region(r)
		crop.resize(crop.get_width() * 3, crop.get_height() * 3,
			Image.INTERPOLATE_NEAREST)
		var cp := out_dir.path_join("01b_debris_crop_x3.png")
		print("[b2][diag] ⇒ 放大 3× 裁剪 %s（源区 %d×%d）err=%d"
			% [cp, r.size.x, r.size.y, crop.save_png(cp)])


# ------------------------------------------------------------- 诊断：读得出"我在动"吗

## ## ⚠️⚠️ 关键设计：**相机一动不动，平移的是世界**
##
## 直觉写法是"把相机沿飞行方向往前推 Δ"。**它是错的**，而错法很隐蔽：
## 实测噪声底 = **813 像素**（相机平移 4 km、且**整棵地表树藏起来**时仍然变了 813 个像素）。
## 根因：程序化天空是从视图矩阵的**逆**里反解方向的，而星空是**像素级高频**图案 ——
## 相机原点一动，float 精度上的微小差异就会让一大批**星点整颗翻转**。
## ⇒ 于是"平移 4 km 变 1990 像素"里，**813 是噪声**，真正的视差只有 1 177 ——
## 而判据阈值恰好是 1 000，**判据本身站在噪声里**。（这正是本工程反复吃的那类亏。）
##
## **正确写法**：相机固定，把 `_terrain_root` 整体反向平移。相对几何与"飞了 Δ"逐位相同，
## 而天空的视图矩阵**一个字节都没变** ⇒ 噪声底**按构造为 0**，对照那条真的能测出 0。
##
## ## 为什么这个判据是干净的（三条前提缺一不可）
##   ① **相机不动、只动世界**（同上：天空逐位不变 ⇒ 任何变化只能来自物体）；
##   ② **时钟冻住**（`set_process(false)`）—— 否则星空自己在闪（见 `_debris_diag()` 头那段：
##      首版因此把 1 936 读成 11 604）；
##   ③ **有一个"按构造应当为 0"的对照**：把地表树藏起来再平移同样的距离，必须**逐位不变**。
##
## ## 判据阈值（不是拍的，是"降一个数量级"的意思）
## 4 km 处若连 **1 000** 个像素都变不了（= 画面 0.07%），那就是"一片黑"，
## 与太平洋删岛之后老板读到的是同一件事。
func _motion_diag(cam: Camera3D) -> void:
	var mm := _world.find_child("SpaceDebris", true, false) as MultiMeshInstance3D
	var terrain: Node3D = _world.get("_terrain_root")
	if terrain == null:
		print("[b2][motion] 没找到 `_terrain_root`")
		return
	var a := -95.0
	var from := _world.spawn_point(a, WorldBuilder.SPAWN_RADIUS, WorldBuilder.PLAYER_START_ALT)
	var th := deg_to_rad(a + 90.0)
	var tang := Vector3(cos(th), 0.0, sin(th))
	# 机位**在整个函数里一动不动**（与图 1 同姿态）。
	cam.global_position = from
	cam.look_at(from + tang * 30000.0 + Vector3.DOWN * 1200.0, Vector3.UP)
	await _frames(4)

	_world.set_process(false)
	await RenderingServer.frame_post_draw
	var ref_img := get_viewport().get_texture().get_image()
	if ref_img == null:
		_world.set_process(true)
		print("[b2][motion] 取不到基准帧")
		return
	ref_img = ref_img.duplicate() as Image
	print("[b2][motion] 基准帧 %d×%d（**相机不动**，平移地表树；时钟已冻住）"
		% [ref_img.get_width(), ref_img.get_height()])

	var d4 := Vector3.ZERO
	for d: float in [250.0, 1000.0, 4000.0]:
		d4 = -tang * d
		terrain.position = d4
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img == null:
			print("[b2][motion]   平移 %.0f m：取不到帧" % d)
			continue
		var n := _diff_px(ref_img, img)
		print("[b2][motion]   平移 **%5.0f m** ⇒ 变化 %5d 像素（占 %.3f%%）%s"
			% [d, n, 100.0 * float(n) / float(ref_img.get_width() * ref_img.get_height()),
				"" if d < 4000.0 else ("  ★ 判据 ≥1000 ⇒ **%s**"
					% ("通过：读得出动" if n >= 1000 else "不通过：等于一片黑"))])

	# ---- 分工：这一步量的是"**大件**贡献了多少" ----
	# （`SpaceDebris` 只是这一张图里的**一件**东西；6 件大残骸 / 运输仓 / 卫星是**另外的节点**，
	#   它们本来就有视差。首版把"只藏碎片带"当成了"应当为 0"的对照，于是判据自报
	#   "测到了别的东西在动" —— 那不是 bug，是把对照写错了。）
	var only_big := -1
	if mm != null:
		var keep := mm.visible
		mm.visible = false
		terrain.position = d4
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var b2 := get_viewport().get_texture().get_image()
		if b2 != null:
			only_big = _diff_px(ref_img, b2.duplicate() as Image)
		mm.visible = keep
		print("[b2][motion] 分工：**只留大件**（残骸 / 运输仓 / 卫星）平移 4 km ⇒ %d 像素"
			% only_big)

	# ---- ★ 真对照：地表树藏起来 ⇒ 天空之外什么都没有 ⇒ **必须逐位为 0** ----
	#
	# ⚠️⚠️ 对照的两帧**必须同类相比**。本函数第二版拿"地表树藏起来"这一帧去和
	# `ref_img`（**东西都在**）比，于是把"物体消失"这件事读成了 819 像素的"杂源" ——
	# 而它其实只是在量"这一张图里的物体一共出多少像素"。**对照写错方向，读数就反了。**
	# ⇒ 正解：先在 `position = 0` 上抓一张**同样什么都没有**的帧当基准，
	#    然后把它平移到 −tang×d，两帧都无物体 ⇒ 差异**只能**来自天空。
	terrain.visible = false
	terrain.position = Vector3.ZERO
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var sky_ref := get_viewport().get_texture().get_image()
	terrain.position = d4
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var sky_moved := get_viewport().get_texture().get_image()
	var sky_still := -1
	if sky_ref != null and sky_moved != null:
		sky_still = _diff_px(sky_ref.duplicate() as Image, sky_moved.duplicate() as Image)
	terrain.visible = true
	terrain.position = Vector3.ZERO
	_world.set_process(true)
	var all_gone := -1
	if sky_ref != null:
		all_gone = _diff_px(ref_img, sky_ref.duplicate() as Image)
	print("[b2][motion] 对照 A（**无物体**帧 × 平移 4 km / 无物体帧）⇒ 变化 %d 像素 —— **必须为 0**"
		% sky_still)
	if sky_still != 0:
		print("[b2][motion]   ⚠️ 不为 0 ⇒ 天空（或后处理）自己就有平移视差，上面的数要按它打折")
	else:
		print("[b2][motion]   ✓ 为 0 ⇒ 噪声底为零：上面的变化**全部**来自世界里的物体")
	print("[b2][motion] 对照 B（基准帧 ↔ **无物体**帧）⇒ %d 像素 = 这张图里**所有物体**的总出像素量"
		% all_gone)



## 两张同尺寸图里"差异超过 1/255"的像素个数。
func _diff_px(x: Image, y: Image) -> int:
	if x == null or y == null or x.get_size() != y.get_size():
		return -1
	var n := 0
	for j in x.get_height():
		for i in x.get_width():
			var ca := x.get_pixel(i, j)
			var cb := y.get_pixel(i, j)
			if maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), absf(ca.b - cb.b)) > 1.0 / 255.0:
				n += 1
	return n


# ------------------------------------------------------------- 机位 / 出图 / 读数

func _look(cam: Camera3D, from: Vector3, at: Vector3, shot_name: String) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	await _frames(10)
	await _shot(cam, shot_name,
		"机位 (%.0f, %.0f, %.0f) → 目标 (%.0f, %.0f, %.0f) 俯角 %.1f°"
			% [from.x, from.y, from.z, at.x, at.y, at.z,
				rad_to_deg(asin(clampf((from.y - at.y)
					/ maxf(from.distance_to(at), 1.0), -1.0, 1.0)))])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## 存图 + **读像素**。增益恒为 1.0（见文件头第 2 条），读数才是判据的载体。
##
## 读的三项：
##   · `mean` —— 整帧平均相对亮度（真空图应当**极低**）；
##   · `p99`  —— 第 99 百分位（星空图里它是"星点有多亮"）；
##   · `n_hi` —— 相对亮度 > 0.25 的像素占比（低头那张应当是**满屏**）。
func _shot(cam: Camera3D, shot_name: String, note: String) -> void:
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
	var lum := _luminances(img)
	lum.sort()
	var n := lum.size()
	var sum := 0.0
	for v: float in lum:
		sum += v
	var mean := sum / float(maxi(n, 1))
	var p50 := lum[int(float(n) * 0.50)]
	var p99 := lum[int(float(n) * 0.99)]
	var n_hi := 0
	var n_mid := 0
	for v: float in lum:
		if v > 0.25:
			n_hi += 1
		if v > 0.02:
			n_mid += 1
	var p := out_dir.path_join("%s.png" % shot_name)
	print("SHOT %s err=%d gain=1.00 | %s" % [p, img.save_png(p), note])
	print("      读数：mean %.5f  p50 %.5f  p99 %.5f | 亮(>0.25) %.2f%%  中(>0.02) %.2f%%"
		% [mean, p50, p99, 100.0 * float(n_hi) / float(maxi(n, 1)),
			100.0 * float(n_mid) / float(maxi(n, 1))])


## 逐像素相对亮度（Rec. 709，与 `Color.get_luminance()` 同一套权重）。
##
## ⚠️ 用**整数像素**遍历，不做 `img.resize()` 降采样：降采样会把稀疏的星点抹掉
##（一张满屏星点、均值 0.004 的图，缩到 1/8 之后星点全没了，读数变成"纯黑"）。
func _luminances(img: Image) -> Array[float]:
	var out: Array[float] = []
	out.resize(img.get_width() * img.get_height())
	var k := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			out[k] = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			k += 1
	return out
