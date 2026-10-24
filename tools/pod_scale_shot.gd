extends Node
## 出图探针：**运输仓（真模型）vs 柯西本体**的尺度对照 + **半剖**证明"机体真在里面"。
##
## 判据在 `suite_space_map.gd`（量真建出来的 AABB）；本探针只负责**让比例一眼看见**——
## 判据给红绿，图给"是不是这么回事"。
##
## ## 轮 46：从"开口方筒"换成**闭合实体**，出图方式也得跟着换
## 轮 45 是壳式方筒（+Z 开口），所以当时那两张图是"**从开口看进去**"。
## 真模型是**闭合实体**（垂直长轴过轴心的射线只穿 2 面）⇒ 没有开口可看，
## 侧视**必然**只看到壳。用户拍板的证据形式是 **半剖出图 + 顶点覆盖读数**。
##
## ★ 剖法：**不动资产一个三角**，靠 `set_surface_override_material()` 换一只
## `discard` 掉「模型局部 z > 0」那半边的着色器 —— 这只作用于**显示**，
## 碰撞体、AABB、GLB 文件全都不受影响（`suite_space_map` 那批判据用不到覆盖材质）。
## ⚠️ 必须 `cull_disabled`：剖开之后看到的是**内壁**（法线朝里），
## 默认背面剔除会把它整片剔掉 ⇒ 剖图变成一堆空洞。
## ⚠️ 必须 `unshaded` + 假光照：本图时段是 `TimeOfDay.space()`，
## 真空没有环境光 ⇒ 真光照下内壁全黑，读不出形状。
##
## 用法：godot --path <工程> res://tools/pod_scale_shot.tscn -- <输出目录>
## ⚠️ **不能加 `--headless`**：dummy 渲染器抓出来是空图（本工程记过这条）。

const SHOT_W := 1600
const SHOT_H := 900

## 半剖着色器：丢掉「模型局部 z > cut_z」或「y > cut_y」的部分，并把内壁涂成暖褐。
##
## ⚠️ 两个 cut 都要能"关掉"：传 1.0（远超模型 AABB 的半尺寸 0.225 / 0.203）即等于不切。
## ⚠️ 为什么需要**两种切法**：半剖面正好过筒轴时，机体是**贴壁**的
##（筒最窄处直径 21.2 m vs 柯西截面 20.8 × 21.65 m）⇒ 侧看总有半截探在壳外。
## 所以：**侧视切 z**（看在槽里的样子）、**俯视切 y**（机体的投影落进"槽"的轮廓里）。
const CUT_SHADER := """
shader_type spatial;
render_mode cull_disabled, unshaded;
uniform float cut_z = 1.0;
uniform float cut_y = 1.0;
uniform vec3 inner_warm : source_color = vec3(0.85, 0.60, 0.33);
uniform vec3 inner_cool : source_color = vec3(0.26, 0.30, 0.38);
varying vec3 lpos;
varying vec3 lnrm;
void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
}
void fragment() {
	if (lpos.z > cut_z || lpos.y > cut_y) {
		discard;
	}
	// 假光照：只为了让"内壁的朝向"一眼读得出来（真空里真光照会全黑）
	float lum = 0.30 + 0.70 * clamp(abs(dot(normalize(lnrm), vec3(0.55, 0.35, 1.0))), 0.0, 1.0);
	ALBEDO = mix(inner_cool, inner_warm, lum);
}
"""

var out_dir := "user://pod_scale"
var _world: WorldBuilder
var _terrain: Node
var _xi: Node3D
var _center := Vector3.ZERO
var _hull: Node3D
var _cut_mat: ShaderMaterial


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	# ⚠️ 窗口模式与尺寸**都要设**（只设尺寸的话，玩家设置是全屏时窗口仍全屏，
	# 于是"1600×900 的判据图"实际是屏幕原生分辨率，日志里一个警告都没有）。
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	_world = WorldBuilder.new()
	add_child(_world)
	await get_tree().physics_frame
	_world.apply_map(MapDef.leo())
	await _frames(20)
	_terrain = _world.get("_terrain_root")

	# ---- ① 运输仓：量出它现在多大、中心在哪 ----
	var pod := _pods_aabb()
	_center = pod.position + pod.size * 0.5
	print("[pair] 运输仓 AABB X=%.2f Y=%.2f Z=%.2f m   最长边 %.2f m   中心 (%.1f, %.1f, %.1f)"
		% [pod.size.x, pod.size.y, pod.size.z,
		   maxf(pod.size.x, maxf(pod.size.y, pod.size.z)),
		   _center.x, _center.y, _center.z])
	print("[pair] 模型 AABB × 缩放 = %.2f x %.2f x %.2f（POD_SCALE %.3f）"
		% [WorldBuilder.POD_BOX.x, WorldBuilder.POD_BOX.y, WorldBuilder.POD_BOX.z,
		   WorldBuilder.POD_SCALE])
	_hull = _terrain.find_child("PodHull", true, false) as Node3D

	# ---- ② 柯西本体：按 `SuitProfile` 的缩放摆到同一个中心 ----
	await _place_xi()

	var cam := Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	cam.current = true

	# ---- ③ 机位 ----
	# 柯西摆在**仓的中心**（`_place_xi()` 对齐到 `_center`），
	# 所以下面每一张都在回答同一个问题：**机体有没有被仓包住**。
	#
	# 机位 1（**空壳对照**）：完整壳 + **侧视**（垂直于筒轴）—— 机体一个部件都不露。
	#
	# ⚠️⚠️ **机位必须跟着"筒轴是哪一根"改** —— 这是本轮第二次栽在同一处：
	# 上一版程序化方筒的**长轴是 Z**，于是当时 `_center + (132, 8, 0)` 是"侧视"；
	# 真模型的长轴是 **X** ⇒ 同一个机位变成了**沿筒轴端视**（拍到七喷口推进簇填满画面，
	# 筒身完全看不见，这张图的意义就没了）。凡是"侧视"都要显式说明**垂直于哪根轴**：
	# 筒轴 = X ⇒ 侧视机位沿 **Z** 或 **Y** 偏。
	#
	# ⚠️ 受光面在 +X（见 `_look` 上面那段）。所以侧视取 **+Z**，
	# 太阳从 +X 打过来恰好是侧顺光。
	await _cut(false)
	await _look(cam, _center + Vector3(0.0, 10.0, 120.0), _center, "pod_solid_side", 1.0, 2000.0)
	# 机位 2（**主证据**）：半剖（丢掉局部 z>0 那半边），相机从 **+Z** 看进去。
	# ⇒ 壳变成一只"开口朝相机的半槽"，柯西**整台躺在里面**（身高轴沿仓的长轴）。
	# ⚠️ 它是**躺着**的，不是站着 —— 这条是**量出来的**：同一支探针把身高轴改成沿
	# 仓的 Y（站着），在工程 k 下最优只覆盖 **0.9927**（58 个顶点露在外面），
	# 要 k = **91.53**（躺着的 1.27 倍）才装得下（筒最窄处直径 21.2 m < 柯西身高 28 m）。
	await _cut(true, 0.0, 1.0)
	await _look(cam, _center + Vector3(0.0, 24.0, 62.0), _center, "pod_halfcut_side", 1.0, 2000.0)
	# 机位 3：**切上半**（留一只"槽"）+ **正上方俯视** —— 沿长轴躺着的全景。
	# ⚠️ 俯视要切 **y** 而不是 z：切 z 是"把靠近相机的半边拿掉"，
	# 而俯视的"靠近"方向是 +Y。切 y 之后机体整台的**投影落在槽的轮廓里**，
	# 一眼读成"躺在里面"；切 z 的话会有半截探到壳外（半剖面正好过筒轴）。
	#
	# ⚠️ `up` **必须换掉 `Vector3.UP`**：机位在正上方、视线几乎与 UP 平行 ⇒
	# `look_at` 的基退化，画面会随机打滚（第一版就是这么拍的：机体看着"探出筒外"，
	# 其实只是画面转了）。俯视一律给 `up = -Z`。
	await _cut(true, 1.0, 0.0)
	await _look(cam, _center + Vector3(0.0, 78.0, 6.0), _center, "pod_halfcut_top", 1.0, 2000.0,
		Vector3(0.0, 0.0, -1.0))
	# 机位 4（**对照**）：同侧视机位，把柯西**移出仓外**、**并排摆在筒上方**。
	# ⇒ 证明机位 1"看不到机体"是因为它真在里面，而不是因为没摆进去。
	# ⚠️ 平移方向要**垂直于视线**才有"并排"效果：视线沿 -Z ⇒ 沿 **+Y** 抬出去。
	#（上一版沿 -Z 平移 = 往镜头里推，是给"长轴 Z"那版几何写的。）
	await _cut(false)
	await _shift_xi(Vector3(0.0, 44.0, 0.0))
	await _look(cam, _center + Vector3(0.0, 10.0, 120.0), _center, "pod_pair_out", 1.0, 2000.0)
	await _shift_xi(Vector3(0.0, -44.0, 0.0))
	# 机位 5：从出生环回看（46.6 km）—— **真实比例的代价**：远处只剩一个点。
	var spawn := Vector3(WorldBuilder.SPAWN_RADIUS, WorldBuilder.SPACE_ORBIT_ALT, 0.0)
	await _look(cam, spawn, _center, "pod_from_spawn", 10.0, 300000.0)
	# ★ "只剩一个点"要**量在屏幕上**：把仓的 8 个 AABB 角**投影**成像素包围盒，
	# 不要拿"角径公式套一对猜的轴"。第一版正是套错了轴 —— 从出生环看过去是
	# **沿筒轴端视**，屏幕横向是筒的**直径 34 m** 而不是**筒长 74 m**，
	# 于是横向像素被算成 1.59 px（真值 0.96 px）。这一行数字就是
	# `pod_marker_shot.gd` 那套 HUD 目标指示存在的理由。
	var box := _pods_aabb()
	var x0 := INF
	var y0 := INF
	var x1 := -INF
	var y1 := -INF
	for i in 8:
		var corner := box.position + Vector3(
			box.size.x if (i & 1) else 0.0,
			box.size.y if (i & 2) else 0.0,
			box.size.z if (i & 4) else 0.0)
		var sp := cam.unproject_position(corner)
		x0 = minf(x0, sp.x)
		y0 = minf(y0, sp.y)
		x1 = maxf(x1, sp.x)
		y1 = maxf(y1, sp.y)
	print("[pair] 出生环 %.0f m 处：仓在屏幕上 **%.2f × %.2f px**（把 AABB 八角**投影**量的）"
		% [spawn.distance_to(_center), x1 - x0, y1 - y0])

	print("POD_SCALE_SHOTS_DONE -> ", out_dir)
	get_tree().quit(0)


# ------------------------------------------------------------- 半剖（只改显示）


## 装上 / 摘掉半剖覆盖材质。**只作用于显示**：GLB 文件、碰撞体、AABB 都不动。
##
## `cut_z` / `cut_y` 传 1.0 = 该方向**不切**（远超模型 AABB 半尺寸 0.225 / 0.203）。
func _cut(on: bool, cut_z := 1.0, cut_y := 1.0) -> void:
	if _hull == null:
		print("[pair] ⚠️ 找不到 PodHull，半剖不生效")
		return
	if on and _cut_mat == null:
		var sh := Shader.new()
		sh.code = CUT_SHADER
		_cut_mat = ShaderMaterial.new()
		_cut_mat.shader = sh
	if on:
		_cut_mat.set_shader_parameter("cut_z", cut_z)
		_cut_mat.set_shader_parameter("cut_y", cut_y)
	for mi in _meshes_deep(_hull):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			m.set_surface_override_material(si, _cut_mat if on else null)
	print("[pair] 半剖 = %s  cut_z=%.3f cut_y=%.3f" % [on, cut_z, cut_y])


# ------------------------------------------------------------- 摆位


## 把柯西摆到运输仓中心。
##
## ⚠️ 缩放系数**不是**"随便挑一个好看的"：`SuitProfile.xi()` 的
## `target_height / model_native_height` 就是游戏里那台机体的缩放
##（`SuitRig` 用的是同一个口径）⇒ 本图里的柯西与玩家驾驶的那台**同尺寸**。
##
## ⚠️ 对齐用**实测的全局 AABB 中心**，不猜模型原点在脚底还是胯下。
func _place_xi() -> void:
	var xi := SuitProfile.xi()
	var ps := load(xi.model_path) as PackedScene
	if ps == null:
		print("[pair] ⚠️ 读不到柯西模型：", xi.model_path)
		return
	_xi = ps.instantiate() as Node3D
	var k: float = xi.target_height / xi.model_native_height
	# ★★ **人体位姿必须与 `tools/pod_fit_check.py` 验证过的那个方位逐字一致**，
	# 否则这张图展示的是一个**从没被验证过**的装填方式（"图对了、口径没验"）。
	# 探针的方位：**身高轴 ↦ 仓的长轴 X**（机体是**躺**着的），另两轴绕仓轴滚 φ。
	# 探针里 `pod_y = X·cos φ + Z·sin φ` / `pod_z = X·sin φ − Z·cos φ` ⇒ 基的**列**是：
	#   机体X ↦ (0, cos φ, sin φ)   机体Y ↦ (1, 0, 0)   机体Z ↦ (0, sin φ, −cos φ)
	# 行列式 = +1（正当旋转，不是镜像 —— 第一版探针在这上面栽过，见那份的 docstring）。
	#
	# ⚠️ **不再单独叠 `model_yaw_deg`**：躺下之后机体的"上"就是仓的长轴，
	# 而 yaw（绕机体 Y 转）与摆位滚转（绕仓 X 转）**转的是同一根轴** ⇒ 二者合并成
	# `POD_CARGO_ROLL_DEG` 一个角，探针扫的就是这个最终角。
	var f := deg_to_rad(WorldBuilder.POD_CARGO_ROLL_DEG)
	var c := cos(f)
	var s := sin(f)
	var basis := Basis(Vector3(0.0, c, s), Vector3(1.0, 0.0, 0.0), Vector3(0.0, s, -c))
	assert(absf(basis.determinant() - 1.0) < 0.001,
		"摆位基的行列式 %.4f ≠ +1 ⇒ 这是**镜像**，读数与图都会偏" % basis.determinant())
	_xi.basis = basis.scaled(Vector3.ONE * k)
	_terrain.add_child(_xi)
	await _frames(2)
	var b := _aabb_global(_xi)
	_xi.global_position += _center - (b.position + b.size * 0.5)
	await _frames(2)
	var b2 := _aabb_global(_xi)
	print("[pair] 柯西 AABB X=%.2f Y=%.2f Z=%.2f m   中心 (%.1f, %.1f, %.1f)   缩放 k=%.3f（= %.1f / %.4f）"
		% [b2.size.x, b2.size.y, b2.size.z,
		   b2.position.x + b2.size.x * 0.5, b2.position.y + b2.size.y * 0.5,
		   b2.position.z + b2.size.z * 0.5, k, xi.target_height, xi.model_native_height])
	print("[pair] ⇒ 最长边之比：仓 %.2f / 柯西 %.2f = **%.3f**"
		% [maxf(_pods_aabb().size.x, maxf(_pods_aabb().size.y, _pods_aabb().size.z)),
		   maxf(b2.size.x, maxf(b2.size.y, b2.size.z)),
		   maxf(_pods_aabb().size.x, maxf(_pods_aabb().size.y, _pods_aabb().size.z))
			/ maxf(b2.size.x, maxf(b2.size.y, b2.size.z))])


# ------------------------------------------------------------- 工具


## 把柯西整体沿世界系平移（用于"并排对比"那个机位）。
func _shift_xi(off: Vector3) -> void:
	if _xi == null:
		return
	_xi.global_position += off
	await _frames(2)


## ⚠️ **`near` / `far` 必须按机位给合理值**：
## 第一版照抄了 `leo_earth_shot.gd` 的 `near = 0.5` + `far = ChaseCamera.ORBIT_FAR`
##（10000 km）⇒ 比值 **2×10⁷**，`rendering_light_culler` 当场算出 8 条
## `create_frustum_points` 错误，**视锥判定失效 ⇒ 运输仓与柯西整块被剔除**，
## 出图只剩星空 + 地球（而相机几何其实是对的：物体就在正前方 47.9 m、占画面 34° 宽）。
## ⇒ 近景 far = 2 km、出生环那机位 far = 300 km。
func _look(cam: Camera3D, from: Vector3, at: Vector3, shot_name: String,
		near := 1.0, far := 2000.0, up := Vector3.UP) -> void:
	cam.near = near
	cam.far = far
	cam.global_position = from
	# ⚠️ `up` 默认 `Vector3.UP`，但**俯视机位必须换**：视线与 UP 平行 ⇒ `look_at`
	# 的基退化、画面随机打滚（看着像"机体探出了筒外"，其实只是画面转了）。
	cam.look_at(at, up)
	await _frames(2)
	var sp := cam.unproject_position(at)
	print("  %s: near=%.1f far=%.0f   目标投影 (%.0f, %.0f) / %d×%d"
		% [shot_name, near, far, sp.x, sp.y, SHOT_W, SHOT_H])
	await _frames(10)
	await _shot(shot_name, "机位 (%.0f, %.0f, %.0f)" % [from.x, from.y, from.z])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(shot_name: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null or vp.get_texture() == null:
		print("SHOT_FAILED ", shot_name)
		return
	var img := vp.get_texture().get_image()
	if img == null:
		print("SHOT_FAILED(img) ", shot_name)
		return
	print("SHOT %s err=%d | %s" % [out_dir.path_join("%s.png" % shot_name),
		img.save_png(out_dir.path_join("%s.png" % shot_name)), note])


## `Pod*` 全部节点合并后的世界系 AABB（与 `suite_space_map._pods_aabb()` 同一套口径）。
func _pods_aabb() -> AABB:
	var box := AABB()
	var found := false
	var stack: Array[Node] = [_terrain]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and str(n.name).begins_with("Pod"):
			var b := _aabb_global(n as Node3D)
			box = b if not found else box.merge(b)
			found = true
			continue
		for c in n.get_children():
			stack.append(c)
	return box


func _aabb_global(root: Node3D) -> AABB:
	var out := AABB()
	var found := false
	for n in _meshes_deep(root):
		var mi := n as MeshInstance3D
		var src := mi.get_aabb()
		var xf := mi.global_transform
		for i in 8:
			var c := src.position + Vector3(
				src.size.x if (i & 1) else 0.0,
				src.size.y if (i & 2) else 0.0,
				src.size.z if (i & 4) else 0.0)
			var wp: Vector3 = xf * c
			if not found:
				out = AABB(wp, Vector3.ZERO)
				found = true
			else:
				out = out.expand(wp)
	return out


func _meshes_deep(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes_deep(c))
	return out
