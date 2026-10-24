extends Node3D
## ★63-13 光束大炮**弹体形状（圆台：炮口细、末端 ×2）**真机取证。
##
## ⚠️ **不能加 `--headless`** —— dummy 渲染器一个像素都不产生，抓出来全黑。
##
## 跑法：godot --path <工程> res://tools/_r63_13_taper_shot.tscn -- <输出目录>
##
## ## 为什么是"独立最小场景 + 自己的 SubViewport"
## 要证的这件事 —— "柱体越远越粗" —— **只由 `BeamCannon._ready()` / `_place()` 决定**，
## 地图、HUD、追尾相机一个都不参与。柱体仍然走**产品那条工厂** `BeamCannon.launch(...)`。
##
## 前两版都栽在"抓帧"上（各自记一笔，别再踩）：
##   ① 接 `main.tscn`：画面被雾/地形糊成一片，相机 `current` 被游戏的追尾相机抢走；
##   ② 独立场景 + `get_viewport().get_texture().get_image()`：**抓到的帧与我设的相机无关** ——
##      连一个"4 m × 8 m 的纯绿自检盒子"都没渲染出来（同一机位连拍三张逐位相同，
##      而那三张之间 `visible` / `cam.size` 都改过）。诊断打印反而证明相机本身没问题
##      （`proj=1` 正交、`keep_aspect=1`、黑底、无雾、AABB 投影算得对）。
##   ⇒ 改成 `SubViewport`（★63-10 放大镜用过、本项目已证可读的那条路）：
##      相机放进子视口、`render_target_update_mode = UPDATE_ALWAYS`、`size` 由探针定死，
##      再从 `sub.get_texture().get_image()` 取图 —— 不依赖窗口尺寸与 stretch。
##
## ## 台子上有四样东西（**探针摆位，不是产品行为**）
##   1. **桩 shooter**：`BeamCannon._aim_dir()` 在 shooter 不是 `FlightBody` 时退到兜底分支
##      `-shooter.global_transform.basis.z` ⇒ 这个桩正好提供"柱朝 −Z 打"。
##      ⚠️ 必须是 `CollisionObject3D` 子类（`_physics_process()` 里有 `shooter.get_rid()`；
##      裸 `Node3D` 每帧抛 `SCRIPT ERROR`，而且**抛在射线之前** ⇒ `_place()` 一次都不跑、
##      柱长恒为 1.000 m）。
##   2. **挡板**：柱本来长 10 km，两端不可能同框 ⇒ 在柱前方 400 m 立一块**不可见的**
##      `StaticBody3D`（`collision_layer = WORLD_LAYER`）把柱截到 ~400 m。
##   3. **黑底 + 无环境光 + 关雾**：画面里除了柱体什么都没有。
##   4. **自检盒子**（4 m × 8 m 纯绿）：正交 20 m / 视口高 900 px ⇒ 应当是 180 × 360 像素。
##      它回答的是"台子坏没坏"这个**与柱体无关**的问题。
##      ⚠️ **它不会被"是绿的"找出来** —— 柱子是加法混合，外晕叠在盒子上把它洗成淡青
##      （实测"g > r+30 且 g > b+30"一个像素都找不到 ⇒ 差点把好台子判成坏台子）。
##      量的正确办法：`13_ref_box.png` 与 `13_near_on.png` **同机位同 size**，逐像素相减 =
##      盒子自己（`_physics_process` 已冻 ⇒ 柱体是静态的）。
##
## ## ⚠️ 量测站必须**关掉外晕**
## 外晕半径 8.6→17.2 m ⇒ 在两个测站处直径 **23.2 / 33.5 m**，比 `ORTHO_MEAS = 20 m`
## 的取景还大 ⇒ 整幅画面被光晕铺满，差分的"亮区"直接顶到画框上下沿（实测 837 / 900 px，
## 连阈值 0.50×峰值 都救不回来）。**要证的是"弹体"（内核 3.2→6.4 m），不是外晕** ⇒
## 两个测站的 on/off 四张图一律 `glow.visible = false`，帧里只剩内核（直径 8.6→12.5 m，装得下）。
##
## ## 为什么必须**正交相机**
## 要证"同一根柱上越远越粗"。透视相机下远端离相机更远，几何上必然更细 ——
## 两个效应混在一起，量出来的比值什么也证明不了。`PROJECTION_ORTHOGONAL` +
## `keep_aspect = KEEP_HEIGHT` ⇒ 像素宽 = 世界宽 × 常数（= 视口高 / `size`），与深度无关
## ⇒ **两个测站的读数天然可比**。
##
## ## 为什么量"差分"（带柱 − 卸柱）
## 柱体是加法混合、发光能量还在 `sin(_life * 41)` 呼吸 ⇒ 绝对亮度不稳。同一机位两张相减：
## 只剩柱体自己的贡献。"源判定"那张（卸柱）应当**纯黑**。
##
## ## 产物
##   13_wide_on.png        全柱侧视（看整体形状）
##   13_ref_box.png        自检盒（台子体检，与柱体无关）
##   13_near_on/_off.png   近端测站（带柱 / 卸柱）
##   13_far_on/_off.png    远端测站（同上）
##   taper_geom.txt        几何读数（给纯 Pillow 的量测脚本用，**不读被验证的源码**）

const FRAC_NEAR := 0.35
const FRAC_FAR := 0.95
const WALL_M := 400.0
const ORTHO_WIDE := 300.0
const ORTHO_MEAS := 20.0
const UP_SHIFT := 3.0
const VIEW_W := 1600
const VIEW_H := 900

var out := "user://r63_13_taper"
var sub: SubViewport
var cam: Camera3D
var cannon: BeamCannon
var last := Vector2i.ZERO


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(VIEW_W, VIEW_H))

	# ---- 黑底、无环境光、关雾 ----
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.0, 0.0, 0.0, 1.0)
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	we.environment = env
	add_child(we)

	# ---- 子视口：尺寸由探针定死，相机放它里面 ----
	sub = SubViewport.new()
	sub.name = "TaperViewport"
	sub.size = Vector2i(VIEW_W, VIEW_H)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.own_world_3d = false          # 继承父视口的世界 ⇒ 看得到主场景树里的柱体
	sub.transparent_bg = false
	add_child(sub)
	cam = Camera3D.new()
	cam.name = "TaperCam"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 1.0
	cam.far = 90000.0
	sub.add_child(cam)
	cam.make_current()

	# ---- 桩 shooter：给 `_aim_dir()` 的兜底分支提供朝向（朝 −Z 打）----
	var shooter := StaticBody3D.new()
	shooter.name = "StubShooter"
	add_child(shooter)
	shooter.global_position = Vector3.ZERO
	shooter.look_at(shooter.global_position + Vector3(0.0, 0.0, -1.0), Vector3.UP)

	# ---- 挡板（不可见，只截柱长）----
	var wall := StaticBody3D.new()
	wall.name = "StageWall"
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6000.0, 6000.0, 4.0)
	cs.shape = box
	wall.add_child(cs)
	wall.collision_layer = 1          # = BeamCannon.WORLD_LAYER
	wall.collision_mask = 0
	add_child(wall)
	wall.global_position = Vector3(0.0, 0.0, -(WALL_M + 2.0))

	# ---- 柱体：走产品那条工厂 ----
	var container := Node3D.new()
	container.name = "BeamContainer"
	add_child(container)
	var offs: Array[Vector3] = [Vector3.ZERO]
	cannon = BeamCannon.launch(container, shooter, offs, null, 35.0, 4.0,
		Color(0.68, 0.32, 1.0))
	if cannon == null:
		push_error("TAPER_SHOT_FAILED(launch returned null)")
		get_tree().quit(1)
		return
	await _frames(30)                 # 展开动画 0.12 s ≈ 7.2 帧 ⇒ 30 帧足够

	var core := cannon.get("_core") as MeshInstance3D
	var glow := cannon.get("_glow") as MeshInstance3D
	if core == null or glow == null:
		push_error("TAPER_SHOT_FAILED(no core/glow)")
		get_tree().quit(1)
		return
	var cm := core.mesh as CylinderMesh
	var gm := glow.mesh as CylinderMesh
	var beam_len := core.scale.y
	print("TAPER beam_len=%.3f m（期望 ≈ %.1f）  radius(判定)=%.1f"
		% [beam_len, WALL_M, cannon.radius])
	print("TAPER mesh core top=%.3f bottom=%.3f | glow top=%.3f bottom=%.3f height=%.3f"
		% [cm.top_radius, cm.bottom_radius, gm.top_radius, gm.bottom_radius, cm.height])
	cannon.set_physics_process(false)   # 冻住：之后长度/可见性都由探针说了算

	# ---- 自检盒子（4 m × 8 m 纯绿）----
	var refbox := MeshInstance3D.new()
	refbox.name = "RefBox"
	var bm := BoxMesh.new()
	bm.size = Vector3(4.0, 8.0, 4.0)
	refbox.mesh = bm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.1, 1.0, 0.2)
	refbox.material_override = rm
	add_child(refbox)
	refbox.global_position = Vector3(0.0, 0.0, -beam_len * FRAC_NEAR)
	refbox.visible = false

	_diag_rig(core, cm)

	var dir := Vector3(0.0, 0.0, -1.0)

	# ================= A 全柱（**带**外晕：看整体形状）=================
	cam.size = ORTHO_WIDE
	_cam_at(dir * (beam_len * 0.5), dir, 900.0)
	await _frames(4)
	await _shot("13_wide_on")

	# ================= 之后一律关外晕（见文件头：外晕会把整幅铺满）=================
	glow.visible = false
	await _frames(3)

	# ================= 自检盒（与 near 测站**同机位 / 同 size / 同外晕状态**）=================
	# 三者任一不同，`ref_box − near_on` 的差分就不干净（盒子本来就靠这个差分量）。
	cam.size = ORTHO_MEAS
	_cam_at(dir * (beam_len * FRAC_NEAR), dir, 400.0)
	refbox.visible = true
	await _frames(4)
	await _shot("13_ref_box")
	refbox.visible = false
	await _frames(3)

	# ================= B/C 两个测站 =================
	for tag in ["near", "far"]:
		var frac: float = FRAC_NEAR if tag == "near" else FRAC_FAR
		var pt := dir * (beam_len * frac)
		_cam_at(pt, dir, 400.0)
		await _frames(4)
		_report_station(tag, frac, pt, beam_len)
		await _shot("13_%s_on" % tag)
		core.visible = false
		await _frames(3)
		await _shot("13_%s_off" % tag)
		core.visible = true
		await _frames(3)
	glow.visible = true

	_write_geom(beam_len, dir)
	print("TAPER_DONE out=%s" % out)
	get_tree().quit(0)


## 台子的全部事实：视口 / 相机 / 环境 / 柱体 AABB 的屏幕投影。
## 出图出问题时最贵的一步是"猜" —— 这一段就是为了不猜。
func _diag_rig(core: MeshInstance3D, cm: CylinderMesh) -> void:
	print("DIAG 子视口 size=%s update_mode=%d own_world_3d=%s"
		% [str(sub.size), sub.render_target_update_mode, str(sub.own_world_3d)])
	print("DIAG 相机 proj=%d keep_aspect=%d near=%.2f far=%.2f ppm=%.3f px/m"
		% [cam.projection, cam.keep_aspect, cam.near, cam.far, float(VIEW_H) / ORTHO_MEAS])
	var e: Environment = get_world_3d().environment
	if e == null:
		print("DIAG 环境 = null（黑底设定没生效！）")
	else:
		print("DIAG 环境 bg_mode=%d bg_color=%s fog=%s vol_fog=%s"
			% [e.background_mode, str(e.background_color), str(e.fog_enabled),
				str(e.volumetric_fog_enabled)])
	print("DIAG 柱体子节点 %d 个：" % cannon.get_child_count())
	for ch in cannon.get_children():
		var extra := ""
		if ch is MeshInstance3D:
			var m := ch as MeshInstance3D
			extra = " aabb=%s visible=%s" % [str(m.get_aabb().size), str(m.visible)]
		print("DIAG   %s (%s)%s" % [ch.name, ch.get_class(), extra])
	var ab := core.get_aabb()
	print("DIAG core 网格 aabb=%s scale=%s（aabb.x = 2×top_radius = %.1f）"
		% [str(ab.size), str(core.scale), cm.top_radius * 2.0])


## 把相机放到柱体侧面（垂直于柱轴），并把取景推离画面正中 `UP_SHIFT` 米。
func _cam_at(pt: Vector3, dir: Vector3, dist: float) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	cam.global_position = pt + side * dist
	cam.look_at(pt, Vector3.UP)
	cam.global_position -= cam.global_transform.basis.y * UP_SHIFT


func _report_station(tag: String, frac: float, pt: Vector3, beam_len: float) -> void:
	var pxc := cam.unproject_position(pt)
	print("TAPER station=%s frac=%.2f 沿柱=%.2f m cam=%s size=%.1f ppm=%.3f"
		% [tag, frac, beam_len * frac, str(cam.global_position), cam.size,
			float(VIEW_H) / cam.size])
	print("TAPER   测站屏幕 x=%.1f（视口宽 %d ⇒ 正中 %d）" % [pxc.x, VIEW_W, VIEW_W / 2])
	var p0 := cam.unproject_position(Vector3.ZERO)
	var p1 := cam.unproject_position(Vector3(0.0, 0.0, -beam_len))
	print("TAPER   柱根屏幕 y=%.1f  柱端屏幕 y=%.1f（同一根柱，两端在屏幕上等高）" % [p0.y, p1.y])


func _write_geom(beam_len: float, dir: Vector3) -> void:
	var f := FileAccess.open(out.path_join("taper_geom.txt"), FileAccess.WRITE)
	if f == null:
		print("GEOM_WRITE_FAILED")
		return
	f.store_line("img_w=%d" % last.x)
	f.store_line("img_h=%d" % last.y)
	f.store_line("ortho_size=%.6f" % ORTHO_MEAS)
	f.store_line("beam_len=%.6f" % beam_len)
	f.store_line("muzzle=0,0,0")
	f.store_line("dir=%.6f,%.6f,%.6f" % [dir.x, dir.y, dir.z])
	f.store_line("frac_near=%.6f" % FRAC_NEAR)
	f.store_line("frac_far=%.6f" % FRAC_FAR)
	f.store_line("station_near_m=%.4f" % (beam_len * FRAC_NEAR))
	f.store_line("station_far_m=%.4f" % (beam_len * FRAC_FAR))
	f.store_line("wall_m=%.1f" % WALL_M)
	f.close()
	print("GEOM img=%dx%d ortho=%.3f ppm=%.4f"
		% [last.x, last.y, ORTHO_MEAS, float(last.y) / ORTHO_MEAS])


func _shot(name: String) -> void:
	# 子视口 UPDATE_ALWAYS ⇒ 每帧重画；等两帧确认这一帧真的画完了
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var tex := sub.get_texture()
	if tex == null:
		print("SHOT_FAILED(no texture) %s" % name)
		return
	var img := tex.get_image()
	if img == null:
		print("SHOT_FAILED(no image) %s" % name)
		return
	last = Vector2i(img.get_width(), img.get_height())
	var path := out.path_join("%s.png" % name)
	print("SHOT %s  %dx%d  err=%d" % [path, last.x, last.y, img.save_png(path)])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
