extends RefCounted
## Main-menu presentation only. Hit regions and input remain in MainMenu.
const TEXT := Color(0.93, 0.94, 0.92)
const MUTED := Color(0.53, 0.62, 0.69)
const FOCUS := Color(0.93, 0.79, 0.52)
const EDGE := Color(0.23, 0.31, 0.38)

static func prepare_selected_text(label: Label, font: Font, outline: Color) -> void:
	label.add_theme_font_override("font", font)
	label.add_theme_color_override("font_color", TEXT)
	label.add_theme_color_override("font_shadow_color", Color(0,0.005,0.012,0.75))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 4)
	label.add_theme_color_override("font_outline_color", outline)
	label.add_theme_constant_override("outline_size", UILayout.outline_for(-1))

static func focus_scale(age: float, focused: bool, reduced: bool) -> float:
	if not focused: return 1.0
	return 1.0 + 0.08 * (1.0 if reduced else smoothstep(0.0, 0.18, age))

static func tilt_target(pointer: Vector2, row: Rect2, reduced: bool) -> Vector2:
	if reduced or not row.has_point(pointer): return Vector2.ZERO
	var offset := (pointer - row.get_center()) / (row.size * 0.5)
	return Vector2(deg_to_rad(-16.0 * offset.y), deg_to_rad(24.0 * offset.x))

static func row(canvas: CanvasItem, r: Rect2, accent: Color, focused: bool, primary := false) -> void:
	var c := FOCUS if primary else accent
	var cut := minf(12.0, r.size.y * 0.16)
	var points := PackedVector2Array([r.position, Vector2(r.end.x - cut, r.position.y),
		Vector2(r.end.x, r.position.y + cut), r.end, Vector2(r.position.x + cut, r.end.y),
		Vector2(r.position.x, r.end.y - cut)])
	canvas.draw_colored_polygon(points, Color(0.065, 0.090, 0.12, 0.96) if focused else Color(0.028, 0.046, 0.065, 0.62))
	var outline := points.duplicate()
	outline.append(points[0])
	canvas.draw_polyline(outline, Color(c, 0.58) if focused else Color(EDGE, 0.55), UILayout.LINE_HAIR, true)
	if focused:
		canvas.draw_rect(Rect2(r.position.x, r.position.y + 14.0, 3.0, r.size.y - 28.0), c)
		canvas.draw_line(r.position + Vector2(16, 0), r.position + Vector2(minf(96.0, r.size.x * 0.15), 0), c, UILayout.LINE_STRUCT, true)
		if primary:
			var at := Vector2(r.end.x - 34.0, r.get_center().y)
			canvas.draw_polyline(PackedVector2Array([at + Vector2(-5,-6), at + Vector2(1,0), at + Vector2(-5,6)]), c, UILayout.LINE_STRUCT, true)

static func panel(canvas: CanvasItem, r: Rect2) -> void:
	canvas.draw_rect(r, Color(0.035, 0.055, 0.078, 0.94))
	canvas.draw_rect(r, Color(EDGE, 0.9), false, UILayout.LINE_HAIR)
	canvas.draw_line(r.position, r.position + Vector2(minf(100.0, r.size.x * 0.15),0), FOCUS, UILayout.LINE_STRUCT)

static func selected_line(canvas: CanvasItem, r: Rect2) -> void:
	canvas.draw_rect(Rect2(r.position.x + 8, r.position.y + 2, r.size.x - 16, r.size.y - 4), Color(FOCUS, 0.08))
	canvas.draw_rect(Rect2(r.position.x + 8, r.position.y + 6, 2, r.size.y - 12), FOCUS)
