extends Node3D
## ★63-21 步骤 0b：**实测 `BaseMaterial3D` 的距离淡出语义**（不凭记忆写引擎行为）。
##
## ## 为什么重写（第一版的教训，留着）
## 第一版凭记忆把 `distance_fade_mode` 写在 **`GeometryInstance3D`** 上 ⇒ 当场
## `Parse Error: Cannot find member "DISTANCE_FADE_PIXEL_ALPHA"`。
## `tools/_r63_21_apidump.gd`（**可以** `--headless`）查下来：那套属性在
## **`BaseMaterial3D`** 上，`GeometryInstance3D` 根本没有。
##
## ## 要回答的三个问题
##   ① 反着给 min/max（min=60 > max=3）真的能得到「近处淡」吗？
##   ② `DISTANCE_FADE_PIXEL_ALPHA` 是**逐片元**吗（⇒ 一条带子上近处淡、远处不淡）？
##   ③ 它吃不吃 **`GPUParticles3D`**（粒子层能不能靠它做，而不是写着色器）？
##
## ## 版面：**一张图扫完整个距离序列**
## 每个距离一个物体，**角尺寸恒定**（世界尺寸 ∝ 距离）、方位角逐个错开 ⇒
## 屏幕上位置/大小都固定，唯一变量是它离相机多远。
## 探针打 `RECT=` 行（屏幕圆心 + 像素半径）给量测脚本用，**不重算**。
##
## ## 三个 `kind`
##   · `quad`      —— `ImmediateMesh` + 顶点色 alpha=0.308 + 羽化遮罩 = **烟带配方**
##   · `sphere`    —— `SphereMesh` + 烟配方、albedo alpha=0.308 = **粒子配方（静态替身）**
##   · `particles` —— 真实 `GPUParticles3D`，但 **`randomness=0` + 速度 0 + 重力 0**
##                    ⇒ 所有粒子叠在同一点 ⇒ **逐位可复现**（这是"粒子层做不了 A/B"
##                    那条结论的例外：那条说的是**真配置**有随机场）
##
## 跑法：godot --path <工程> res://tools/_r63_21_fade_probe.tscn -- <输出目录> <mode> <kind>
##   mode ∈ pixel_rev / pixel_fwd / off

var out := "user://r63_21_fade_probe"
var mode := "pixel_rev"
var kind := "quad"

const DISTS: Array[float] = [2.0, 3.0, 5.0, 10.0, 20.0, 30.0, 45.0, 60.0, 90.0, 150.0]
const CAM_FOV := 60.0
## 需求的两个锚点。
const FADE_NEAR := 3.0
const FADE_FAR := 60.0
const ANG_HALF_W := 0.030
const ANG_HALF_H := 0.015
const ROW_STEP := 0.075
const ALPHA0 := 0.308

var cam: Camera3D
var _mats: Array[BaseMaterial3D] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = str(args[0])
	if args.size() > 1:
		mode = str(args[1])
	if args.size() > 2:
		kind = str(args[2])
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(1600, 900))

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.0, 0.0, 0.0, 1.0)
	we.environment = env
	add_child(we)

	cam = Camera3D.new()
	cam.name = "Cam"
	cam.fov = CAM_FOV
	cam.position = Vector3.ZERO
	add_child(cam)
	cam.make_current()

	var half := float(DISTS.size() - 1) * 0.5
	for k in DISTS.size():
		var d: float = DISTS[k]
		var az := (float(k) - half) * ROW_STEP
		var node := _make(d)
		add_child(node)
		node.global_position = Vector3(sin(az) * d, 0.0, -cos(az) * d)
		node.name = "%s_d%.0f" % [kind, d]
	print("[probe] mode=%s kind=%s dists=%s" % [mode, kind, str(DISTS)])

	await _frames(40)
	_report()
	await _snap("%s_%s" % [mode, kind])
	print("R63_21_FADE_PROBE_DONE -> %s" % out)
	get_tree().quit(0)


func _fade_mode() -> int:
	match mode:
		"pixel_fwd":
			return BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		"pixel_rev":
			return BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		_:
			return BaseMaterial3D.DISTANCE_FADE_DISABLED


## 距离淡出挂在**材质**上（`BaseMaterial3D`），不在节点上。
func _apply_fade(mat: BaseMaterial3D) -> void:
	mat.distance_fade_mode = _fade_mode() as BaseMaterial3D.DistanceFadeMode
	if mode == "pixel_fwd":
		mat.distance_fade_min_distance = FADE_NEAR
		mat.distance_fade_max_distance = FADE_FAR
	else:
		# 反着给：min（远）> max（近）—— 本步骤要问的就是这一条
		mat.distance_fade_min_distance = FADE_FAR
		mat.distance_fade_max_distance = FADE_NEAR
	_mats.append(mat)


func _make(d: float) -> Node3D:
	var hw := ANG_HALF_W * d
	if kind == "particles":
		return _make_particles(hw)
	if kind == "sphere":
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = hw
		sm.height = 2.0 * hw
		sm.material = _smoke_mat()
		s.mesh = sm
		return s
	var q := MeshInstance3D.new()
	q.top_level = true
	var im := ImmediateMesh.new()
	q.mesh = im
	# ⚠️ `ImmediateMesh` 没法设 `material`（那是 `SurfaceTool`/带 surface 的 mesh 才有）
	# ⇒ 用 `material_override`。距离淡出挂在**材质对象**上，与挂在哪一层无关。
	q.material_override = _ribbon_mat()
	var hh := ANG_HALF_H * d
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_qv(im, Vector3(-hw, -hh, 0.0), Vector2(0.0, 0.0))
	_qv(im, Vector3(hw, -hh, 0.0), Vector2(1.0, 0.0))
	_qv(im, Vector3(hw, hh, 0.0), Vector2(1.0, 1.0))
	_qv(im, Vector3(-hw, -hh, 0.0), Vector2(0.0, 0.0))
	_qv(im, Vector3(hw, hh, 0.0), Vector2(1.0, 1.0))
	_qv(im, Vector3(-hw, hh, 0.0), Vector2(0.0, 1.0))
	im.surface_end()
	return q


func _qv(im: ImmediateMesh, p: Vector3, uv: Vector2) -> void:
	im.surface_set_color(Color(0.80, 0.80, 0.84, ALPHA0))
	im.surface_set_uv(uv)
	im.surface_add_vertex(p)


## 确定性粒子团：`randomness=0` + 速度 0 + 重力 0 + 点发射 ⇒ 全叠在一处。
## ⚠️ 不确定的属性一律走 `.set()`（动态），免得又吃到 Parse Error。
func _make_particles(hw: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 6
	p.lifetime = 30.0
	p.emitting = true
	p.local_coords = false
	p.fixed_fps = 30
	p.explosiveness = 0.0
	p.set("randomness", 0.0)
	p.set("interpolate", false)
	var sm := SphereMesh.new()
	sm.radius = hw
	sm.height = 2.0 * hw
	sm.material = _smoke_mat()
	p.draw_pass_1 = sm
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 0.0, -1.0)
	pm.spread = 0.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 1.0
	pm.scale_max = 1.0
	pm.angle_min = 0.0
	pm.angle_max = 0.0
	pm.set("randomness", 0.0)
	p.process_material = pm
	return p


## 烟带配方（照抄 `MissileRibbon._shared_mat()` + `_edge_mask()`）
func _ribbon_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = MissileRibbon._edge_mask()
	mat.disable_receive_shadows = true
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_apply_fade(mat)
	return mat


## 粒子配方（照抄 `FX._trail_smoke_mat()` 的关键项）
func _smoke_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.80, 0.80, 0.84, ALPHA0)
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_apply_fade(mat)
	return mat


func _report() -> void:
	var sz := get_viewport().get_visible_rect().size
	print("[probe] viewport=%dx%d" % [int(sz.x), int(sz.y)])
	if not _mats.is_empty():
		var m := _mats[0]
		print("[probe] 材质回读: mode=%d min=%.1f max=%.1f transp=%d"
			% [m.distance_fade_mode, m.distance_fade_min_distance,
				m.distance_fade_max_distance, m.transparency])
	for k in DISTS.size():
		var d: float = DISTS[k]
		var az := (float(k) - float(DISTS.size() - 1) * 0.5) * ROW_STEP
		var pos := Vector3(sin(az) * d, 0.0, -cos(az) * d)
		var c := cam.unproject_position(pos)
		var edge := cam.unproject_position(pos + Vector3(ANG_HALF_W * d, 0.0, 0.0))
		print("RECT=%.1f %6.1f %6.1f %7.2f" % [d, c.x, c.y, absf(edge.x - c.x)])


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null:
		print("SHOT_FAILED(no viewport) ", name)
		return
	var img := vp.get_texture().get_image()
	if img == null:
		print("SHOT_FAILED(no image) ", name)
		return
	var path := out.path_join("%s.png" % name)
	print("SHOT %s  %dx%d  err=%d"
		% [path, img.get_width(), img.get_height(), img.save_png(path)])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
