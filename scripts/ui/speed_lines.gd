class_name SpeedLines
extends Control
## 加速模式的全屏速度线 + 柔和暗角。
##
## 速度线：从屏幕中心向外的放射状线段，每条有自己的相位，随时间向外流动；
## 透明度在屏幕中部为 0、靠近边缘才拉满 —— 需求要的是"屏幕**周围**的速度线"，
## 铺满全屏会让准星区域看不清目标。
##
## 暗角：**必须是一块平滑的径向渐变，不能画成四条硬边矩形**。
## 第一版图省事，直接在四边 `draw_rect` 了四条半透明色带，结果加速时屏幕周围
## 出现一圈非常明显的方形边框 —— 那不是"速度感"，那是素材没处理干净的样子。
## 现在走 `shaders/vignette.gdshader`，径向 smoothstep，任何尺寸下都看不出边界。

const VIGNETTE_SHADER := "res://shaders/vignette.gdshader"

var intensity := 0.0
## 冲刺增益 0..1（辅助驾驶的**闪避冲刺** / **超级加速**）：它**不改总强度**
##（那还是 `intensity` 说了算），只改速度线的**形态** —— 线更密、更长、流得更快、
## 更粗、色温更白。
##
## 与尾焰"形态 A（巡航锥）/ 形态 B（冲刺束）"是同一件事的屏幕层：
## 一次冲刺必须在**整块屏幕**上读得出来，而不是只有机尾那一点变了。
var dash := 0.0
var _time := 0.0
var _vignette: ColorRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_vignette = ColorRect.new()
	_vignette.name = "Vignette"
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(VIGNETTE_SHADER):
		var mat := ShaderMaterial.new()
		mat.shader = load(VIGNETTE_SHADER)
		_vignette.material = mat
	add_child(_vignette)


func set_intensity(v: float) -> void:
	intensity = clampf(v, 0.0, 1.0)
	visible = intensity > 0.01
	if _vignette != null and _vignette.material is ShaderMaterial:
		(_vignette.material as ShaderMaterial).set_shader_parameter("intensity", intensity)


## `v` 由 `main._update_camera_assist` 按 `FlightBody.is_dashing()` 每帧写。
func set_dash(v: float) -> void:
	dash = clampf(v, 0.0, 1.0)


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	if intensity <= 0.01:
		return
	var c := size * 0.5
	var max_r := c.length()
	if max_r < 1.0:
		return

	const N := 72
	# 冲刺时线**更密、更长、流得更快、更粗、色温更白** —— 五个一起动，读起来才是
	# "换了一种状态"。只加数量会像"撒得更开"，只加长度会像"没对齐"。
	var n := N + int(round(40.0 * dash))
	var len_k := 1.0 + 0.95 * dash
	var spd_k := 1.0 + 0.85 * dash
	var alpha_k := 1.0 + 0.55 * dash
	var wide_k := 1.0 + 0.45 * dash
	var tint := Color(0.86, 0.94, 1.0).lerp(Color(1.0, 1.0, 1.0), dash * 0.75)
	for i in n:
		# 黄金角撒点，每条的相位与速度都不同，避免看出周期性
		var ang := float(i) * 2.3999632
		var speed := (1.25 + fmod(float(i) * 0.37, 1.0) * 1.1) * spd_k
		var phase := fmod(_time * speed + fmod(float(i) * 0.61, 1.0), 1.0)
		var r0: float = lerpf(max_r * 0.18, max_r * 0.98, phase)
		var r1: float = r0 + max_r * (0.08 + 0.20 * phase) * len_k
		# 越靠边越明显，中心留白
		var edge: float = smoothstep(0.30, 0.92, r0 / max_r)
		# ⚠️ 上限 0.92：冲刺把 `alpha_k` 抬上去之后，满相位那几条会直接到 1.0，
		# 屏幕边缘出现一圈**实心白边**（那正是第一版暗角踩过的坑的另一种形态）。
		var alpha: float = minf(intensity * edge * 0.55 * (1.0 - phase * 0.45) * alpha_k, 0.92)
		if alpha <= 0.004:
			continue
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(c + dir * r0, c + dir * r1,
			Color(tint.r, tint.g, tint.b, alpha),
			(1.4 + 2.4 * intensity) * wide_k, true)
