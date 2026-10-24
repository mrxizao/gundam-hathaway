extends Control
var clock := 0.0
var cloud := 0.0
var impact := 0.0
var damage := 0.0
var blackout := false
var black_amount := 0.0
var mark := Vector2(-999,-999)
var marked := false
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func _draw() -> void:
	if cloud > 0.001:
		draw_rect(Rect2(Vector2.ZERO,size),Color(.26,.30,.37,cloud*.75))

	if impact>0.001:
		draw_rect(Rect2(Vector2.ZERO,size),Color(1,.78,.95,impact*.60))
	if damage>0.001:
		draw_rect(Rect2(Vector2(12,12),size-Vector2(24,24)),Color(1,.24,.13,damage*.6),false,2.0)
	if marked:
		var col := Color(.78,.72,1.0,.95)
		for v in [Vector2(-35,-27),Vector2(35,-27),Vector2(0,35)]:
			var a: Vector2 = v.rotated(TAU/3.0)
			var b: Vector2 = v.rotated(-TAU/3.0)
			draw_line(mark+v,mark+v.lerp(a,.32),col,2,true)
			draw_line(mark+v,mark+v.lerp(b,.32),col,2,true)
		draw_string(ThemeDB.fallback_font,mark+Vector2(-25,-38),"LOCK",HORIZONTAL_ALIGNMENT_LEFT,-1,14,col)
	if black_amount > 0.001: draw_rect(Rect2(Vector2.ZERO,size),Color(0,0,0,black_amount))
