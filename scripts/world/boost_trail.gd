class_name BoostTrail
extends MeshInstance3D
## 冲刺 / 超级加速的**连贯拖尾光条**（2026-09-21，用户要求
## "冲刺的时候背后尾迹变成连贯拖尾的光条。超级加速模式也是"）。
##
## ## 为什么不是粒子
## 粒子（加力尾焰、导弹烟柱）是"一串点"，快到一定速度后点与点之间是断的 ——
## 用户点名要的是**连贯的光条**。所以这里用 ImmediateMesh 手工拼丝带：
## 每帧把机体尾部位置推进历史队列，相邻两个采样点连成一段**面向相机的四边形**，
## 宽度与透明度从头（新）到尾（旧）衰减 —— 连续、无缝、随速度拉长。
##
## ## 生命周期
##   - `push(tip, true, delta)`：按采样间距推入新点，光条随飞行路径生长；
##   - `push(tip, false, delta)`：不再进新点，**从最旧一端逐帧收回**
##     （"光条被吸回去"，比"原地淡掉"干净）；残余点超龄后自动清空。
##
## ## 世界空间
## `top_level = true`：节点不继承机体的位移/旋转，顶点直接用**世界坐标** ——
## 光条留在飞过的地方，而不是跟着机体跑。
##
## 本类不读输入、不依赖物理，无头测试可以直接 new 出来喂点、数顶点。

## 最多保留多少个采样点（光条最长 ≈ MAX_POINTS × SPACING 米）。
const MAX_POINTS := 40
## 两个采样点的最小间距（米）。间距越小光条越贴合转弯轨迹，顶点也越多。
const SPACING := 8.0
## 单个采样点的寿命（秒）。决定松开冲刺后光条多久收干净。
const LIFE := 0.55
## 光条在头部（最新一端）的半宽（米）。机体 20~40 m 高，2.6 m 的光带才看得见。
const WIDTH := 2.6

var _pts: Array[Vector3] = []
var _ages: Array[float] = []
## 光条颜色（机体强调色偏白一档，见 FlightBody._reposition_attachments）。
var _base := Color(0.8, 0.9, 1.0)
var _imm: ImmediateMesh


func _init() -> void:
	name = "BoostTrail"
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_imm = ImmediateMesh.new()
	mesh = _imm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# 加色混合：光条叠在夜景/机体上只会变亮，不会遮挡 —— 和加力尾焰同一条路。
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	material_override = mat


func set_base_color(c: Color) -> void:
	_base = c


## 当前历史点数（测试用：active 喂点应增长，inactive 收回应归零）。
func point_count() -> int:
	return _pts.size()


## 每物理帧调一次。
## `tip` = 世界系的**尾喷口**位置；`active` = 本帧是否在冲刺/超级加速。
func push(tip: Vector3, active: bool, delta: float) -> void:
	for i in _ages.size():
		_ages[i] += delta
	if active:
		if _pts.is_empty():
			_pts.append(tip)
			_ages.append(0.0)
		else:
			var head := _pts[_pts.size() - 1]
			if head.distance_to(tip) >= SPACING:
				_pts.append(tip)
				_ages.append(0.0)
				if _pts.size() > MAX_POINTS:
					_pts.remove_at(0)
					_ages.remove_at(0)
			else:
				# 还没飞出一个采样间距：把头点贴到当前位置（静止时头点不堆积）
				_pts[_pts.size() - 1] = tip
				_ages[_ages.size() - 1] = 0.0
	else:
		# 松开 → 从最旧一端逐帧收回
		if not _pts.is_empty():
			_pts.remove_at(0)
			_ages.remove_at(0)
	# 超龄的点从旧端清掉（active 连续喂点时旧点也会超龄）
	while not _ages.is_empty() and _ages[0] > LIFE:
		_pts.remove_at(0)
		_ages.remove_at(0)
	_rebuild()


func _rebuild() -> void:
	_imm.clear_surfaces()
	if _pts.size() < 2:
		return
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var n := _pts.size()
	_imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, n):
		var p0 := _pts[i - 1]
		var p1 := _pts[i]
		var seg := p1 - p0
		var seg_len := seg.length()
		if seg_len < 0.01:
			continue
		var dir := seg / seg_len
		# 丝带的"横向"向量：与这段轨迹垂直、又尽量面向相机（头灯无相机时退回水平）
		var to_cam := (p1 + Vector3.UP * 500.0) - (p0 + p1) * 0.5
		if cam != null:
			to_cam = cam.global_position - (p0 + p1) * 0.5
		var side := dir.cross(to_cam)
		if side.length_squared() < 0.0001:
			side = dir.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		side = side.normalized()
		var w_head := WIDTH * _fade(i)
		var w_tail := WIDTH * _fade(i - 1)
		var c_head := Color(_base.r, _base.g, _base.b, 0.85 * _fade(i))
		var c_tail := Color(_base.r, _base.g, _base.b, 0.85 * _fade(i - 1))
		var a := p0 - side * w_tail
		var b := p0 + side * w_tail
		var c := p1 + side * w_head
		var d := p1 - side * w_head
		_imm.surface_set_color(c_tail)
		_imm.surface_add_vertex(a)
		_imm.surface_set_color(c_tail)
		_imm.surface_add_vertex(b)
		_imm.surface_set_color(c_head)
		_imm.surface_add_vertex(c)
		_imm.surface_set_color(c_tail)
		_imm.surface_add_vertex(b)
		_imm.surface_set_color(c_head)
		_imm.surface_add_vertex(c)
		_imm.surface_set_color(c_head)
		_imm.surface_add_vertex(d)
	_imm.surface_end()


## 第 idx 个点的亮度/宽度系数 0..1：新（靠数组尾）亮而宽，旧（靠头）暗而细。
func _fade(idx: int) -> float:
	var t := 1.0 - clampf(_ages[idx] / LIFE, 0.0, 1.0)
	var taper := float(idx + 1) / float(_pts.size())
	return t * clampf(taper, 0.15, 1.0)
