extends Node
## 浮游导弹**尾迹体积感**归因探针（轮 38）。
##
## ## 症状（用户原话）
## 「浮游导弹的尾迹烟雾还是不够厚，现在看还是没有体积感」。
##
## ⚠️ 这句话有**两层**，而且它们正交：
##   ① 「不够厚」= **量** —— 面积 / 密度 / 尺寸。上一轮（2026-09-22）已经加过：
##      粒子数 70→80、`spread` 12°→18°、出生尺寸 ×1.55、随龄扩散 1.0→1.3、色带加浓。
##   ② 「没有体积感」= **质** —— 这是本探针要证的东西。
##      一团又大又浓的**平面贴片**，读起来仍然是"一片纸"，不是"一团东西"。
##      **往①上继续加料不会解决②** —— 这正是本轮的出发点。
##
## ## 为什么怀疑材质（而不是粒子数）
## `FX.missile_trail()` 的粒子 mesh 是 `SphereMesh`（真正的 3D 球），
## 但它挂的 `_soft_smoke_mat()` 上有两行**互相抵消**的开关：
##   · `shading_mode = SHADING_MODE_UNSHADED` ⇒ 不受任何光照 ⇒ 球面**没有明暗梯度**；
##   · `billboard_mode = BILLBOARD_ENABLED`   ⇒ 永远正对相机 ⇒ 球体被**拍平成一个圆盘**。
##
## 两个开关加起来的效果：**不管 mesh 是不是球，屏幕上永远是一枚朝向一致的柔边圆斑。**
## 一堆"朝向一致 + 颜色一致 + 边缘一致"的圆斑叠起来，大脑只会读成"贴纸 / 一层薄雾"。
## 体积感的物理来源是"**同一个物体上有明暗层次**"，而这两个开关恰好把它抹掉了 ——
## 所以这是**原理性**问题，不是参数不够大。
##
## ## 本探针要量三件事（全部落在像素上）
##   ① **光照响应**：把场景主光 `world.sun.visible` 关掉，尾迹区域的像素变不变。
##      · unshaded 材质 ⇒ 变化 **恒为 0**（逐位相同，`diff = 0`）；
##      · 受光材质   ⇒ 变化 > 阈值。
##      这是"体积感"最直接的物理来源，也最可证伪（不需要主观判断"像不像烟"）。
##   ② **视角响应**：保持相机看向同一点、绕烟柱转 90°，尾迹像素变不变。
##      · billboard ⇒ 每颗粒子都正对相机 ⇒ 画面几乎不变；
##      · 真 3D 球 ⇒ 明暗分布重排 ⇒ 明显变化。
##   ③ 出图：柱体形态的 A/B/C，给人看，也给判据脚本裁 ROI 用。
##
## ## 跑法（⚠️ **不能加 `--headless`**：无头下 RenderingServer 是 dummy，出不了像素）
##   Godot_v4.7.1-stable_win64_console.exe --path . \
##       res://tools/probe_trail_volume.tscn -- <输出目录>
##
## ## 两个必须踩准的点
##   · **粒子在 `get_tree().paused = true` 之后仍然继续演化**（轮 37 的 A/B 探针被
##     这个坑污染过：尾焰自己变了半张图）。冻结粒子只能靠 `speed_scale = 0.0`
##     —— `emitting = false` 只是停止新生，已经生出来的还会继续飘、继续淡。
##   · **`Camera3D.far` 默认 4000**，本探针最远机位 400 m 够用，但仍显式抬到
##     20000（轮 37 踩过：100 km 机位拍出一片纯背景色，且**不报任何错**）。

const MAIN_SCENE := "res://scenes/main.tscn"
const SHOT_W := 1600
const SHOT_H := 900

## 手动推进的速度与时长。取 80 m/s × 2.8 s = **224 m 柱长**：
## `80` 与浮游导弹出膛的 `speed = 90`（`Missile.funnel()`）同量级，
## `2.8` 就是 `missile_trail()` 的 `lifetime` —— 走满一个寿命，柱子首尾都完整。
const SPEED := 80.0
const FLY_T := 2.8

var _main: Node = null
var _out := "user://probe_trail"
var _c: Node = null
var _m: Missile = null
var _shooter: FlightBody = null
var _t := 0.0
var _p0 := Vector3.ZERO
var _dir := Vector3.FORWARD
var _mid := Vector3.ZERO


func _ready() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	print("[tv] 输出目录 = ", _out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await get_tree().process_frame
	await get_tree().process_frame

	var ps := load(MAIN_SCENE) as PackedScene
	if ps == null:
		push_error("[tv] 加载主场景失败")
		get_tree().quit(4)
		return
	_main = ps.instantiate()
	add_child(_main)
	for i in 3:
		await get_tree().process_frame

	_main._on_start_match(0, 0, MapDef.Id.ULURU, Game.MatchMode.VERSUS)
	# 建图是协程（`apply_map_staged` 里夹着 await），不等够帧 `world.sun` 还是 null。
	for i in 20:
		await get_tree().process_frame
	if _main.world == null:
		push_error("[tv] world 为空 —— 没进 ULURU 图？")
		get_tree().quit(5)
		return

	_setup()
	await _fly()
	_freeze()
	await _shots()
	get_tree().quit(0)


# ------------------------------------------------------------ 造一条真尾迹

## ⚠️ 用**真** `Missile.funnel()`（不是手工 `FX.missile_trail()`）：
## 尾迹的 `scale` 参数（0.65）写在 `Missile._ready()` 里，手工调就会漏掉那一层，
## 那样量到的就不是玩家看到的东西。
func _setup() -> void:
	Game.reset()
	_c = _main.projectiles
	if _c == null:
		_c = Node3D.new()
		_c.name = "TrailProbeBox"
		_main.add_child(_c)

	# 载机：只当"发射者"用，立刻停掉物理，不让它自己飞走。
	_shooter = FlightBody.new()
	_shooter.team = 0
	_shooter.is_player = false
	_shooter.profile = SuitProfile.penelope()
	_shooter.display_name = "TrailShooter"
	_shooter.projectile_container = _c
	_c.add_child(_shooter)
	_p0 = Vector3(0.0, 3000.0, 0.0)
	_shooter.global_position = _p0
	_shooter.set_physics_process(false)
	_shooter.set_process(false)

	_dir = Vector3.FORWARD
	_m = Missile.funnel(_c, _p0, _dir, null, _shooter, 10.0)
	# 关掉弹体自己的物理与制导 —— 位移由探针手动给，这样柱长与朝向完全可控。
	_m.set_physics_process(false)
	_m.set_process(false)
	_m.global_position = _p0
	print("[tv] 导弹已生成：pos=%s  尾迹节点=%s" % [str(_p0), str(_m.get_node_or_null("MissileTrail"))])
	var tr := _m.get_node_or_null("MissileTrail") as GPUParticles3D
	if tr != null:
		print("[tv] 尾迹 amount=%d lifetime=%.2f scale_node=%s" % [tr.amount, tr.lifetime, str(tr.scale)])


## 手动匀速直线推进：`Missile._physics_process` 已停，位置只由这里给。
func _fly() -> void:
	while _t < FLY_T:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		_t += dt
		_m.global_position += _dir * SPEED * dt
	_mid = _p0 + _dir * (SPEED * FLY_T * 0.5)
	print("[tv] 飞完 %.2f s：柱长 %.0f m  中点=%s" % [_t, SPEED * FLY_T, str(_mid)])


## 冻结画面。
## ⚠️ `emitting = false` **不够**（只停新生），必须 `speed_scale = 0.0` 把演化也停住，
## 否则抓 A 图与抓 B 图之间那些已经存在的粒子会自己继续飘/继续淡 —— 判据就成了噪声。
func _freeze() -> void:
	_m.set_physics_process(false)
	_shooter.set_physics_process(false)
	get_tree().paused = true
	for p in _all_particles(_c):
		p.emitting = false
		p.speed_scale = 0.0
	print("[tv] 冻结：粒子发射器 %d 个，speed_scale 全部置 0" % _all_particles(_c).size())


func _all_particles(root: Node) -> Array[GPUParticles3D]:
	var out: Array[GPUParticles3D] = []
	if root == null:
		return out
	for ch in root.get_children():
		if ch is GPUParticles3D:
			out.append(ch as GPUParticles3D)
		out.append_array(_all_particles(ch))
	return out


# ------------------------------------------------------------ 出图

func _shots() -> void:
	if _main.canvas != null:
		_main.canvas.visible = false
	var wbx: Node = _main.world
	if wbx != null:
		var cr: Node = wbx.get("_cloud_root")
		if cr is Node3D:
			(cr as Node3D).visible = false
	var chase: Camera3D = _main.chase
	if chase == null:
		print("[tv] ⚠️ 没有 chase 相机")
		return
	chase.set_target(null)
	chase.set_physics_process(false)
	chase.set_process(false)
	chase.fov = 55.0
	chase.far = 20000.0
	chase.near = 1.0

	var sun: DirectionalLight3D = wbx.get("sun") if wbx != null else null
	# 侧视：视线 ⟂ 柱轴（柱沿 −Z 飞 ⇒ 相机放在 +X 侧）。
	var cam_side := _mid + Vector3(330.0, 70.0, 20.0)
	# 前视：绕柱轴转 90°（相机放到柱正前方，迎着柱飞来的方向看回去）。
	var cam_front := _mid + Vector3(0.0, 70.0, -330.0)

	_aim(cam_side, _mid)
	await _shot("a_side")

	if sun != null:
		var was := sun.visible
		sun.visible = false
		await _shot("b_side_nolight")
		sun.visible = was
		print("[tv] 主光开关判据：sun.visible %s → false → %s（图 a/b）" % [str(was), str(was)])

	_aim(cam_front, _mid)
	await _shot("c_front")

	# 英雄机位：给用户看的近景（略低、略近）。
	_aim(_mid + Vector3(190.0, 10.0, -150.0), _mid + Vector3(0.0, 10.0, 0.0))
	await _shot("d_hero")
	# ⚠️ 英雄机位**也要**拍一张关主光的配对图。
	# 为什么要专门加这一张：侧视机位（a/b）的 ROI 里混着地面，而地面自己会被主光点亮/熄灭，
	# 于是"光照参与度"这个判据会被背景污染（老版本实测 10.1% 就是这么来的 —— 纯烟本该是 0）。
	# 英雄机位里烟柱整个压在**纯黑天空**上，背景不参与 ⇒ 这个配对才是干净的。
	if sun != null:
		var was2 := sun.visible
		sun.visible = false
		await _shot("e_hero_nolight")
		sun.visible = was2

	# ⚠️ 这里**故意没有**"柱面特写"机位 —— 试了两版都失败，把路标留在下面，
	# 免得下一个人重走：
	#   · 第一版"柱正侧方 15 m"（`_mid + (15,3,0)` 看向 `_mid`）：拍出来**整幅是空的**，
	#     before/after 逐位相同（⇒ 那一格根本没有烟）。
	#   · 第二版"d_hero 方位缩到 ~1/12"：柱两端的 `unproject_position` 跑到画面**左外**
	#     （-48 / -755），于是只框到了天与地。
	#   ⚠️ 两版都伴随着同一个未解释的现象：**引擎给出的屏幕投影坐标，与肉眼在 PNG 上
	#     看到的烟位置对不上**（`d_hero` 投影说柱在 y≈478~500，而图上烟明显在 y≈300 一带）。
	#     怀疑与 viewport 逻辑尺寸 / 窗口尺寸不一致有关（本探针设了
	#     `window_set_size(1600,900)`，但没设 stretch），**没有查实之前不下结论**。
	#   ⇒ 特写改成**事后裁切** `d_hero`（Python 里裁一小块放大）：零风险，且完全等效。
	print("[tv] viewport 逻辑尺寸=%s  窗口尺寸=%s  出图尺寸=%dx%d"
		% [str(get_viewport().get_visible_rect().size), str(DisplayServer.window_get_size()),
			SHOT_W, SHOT_H])


func _aim(pos: Vector3, look: Vector3) -> void:
	var chase: Camera3D = _main.chase
	chase.global_position = pos
	# ⚠️ 用 `Basis.looking_at` 而不是手写欧拉：本探针的机位都是近水平的，
	# 视线与 UP 不可能共线，不会踩到 `look_at` 的退化。
	chase.global_transform.basis = Basis.looking_at(look - pos, Vector3.UP)
	chase.current = true
	# ⚠️ 每个机位都把柱两端的**屏幕投影**打出来 —— 判据脚本据此裁 ROI。
	# 第一版没打，我凭印象填 ROI，结果框在了纯星空上（ROI 里只有 286 个像素、
	# 而且 before/after 的数字逐位相同 ⇒ 那一格根本没烟）。**别猜像素坐标。**
	var tail := _p0
	var head := _p0 + _dir * (SPEED * FLY_T)
	print("[tv] cam@%s  柱尾端→%s  柱头端→%s"
		% [str(pos.round()), str(chase.unproject_position(tail).round()),
			str(chase.unproject_position(head).round())])


func _shot(name: String) -> void:
	for i in 8:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, name]
	img.save_png(path)
	print("[tv] 出图 %s  %dx%d" % [path, img.get_width(), img.get_height()])
