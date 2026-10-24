extends Control
func _ready():
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func _process(_delta:float):queue_redraw()
func _draw():
	var body=get_parent().player
	if not is_instance_valid(body) or not body.alive:return
	var guard=body.melee_guard
	var font=get_theme_default_font()
	if guard.impact_left>0:
		draw_string(font,Vector2(size.x*0.5-95,size.y*0.70),"光束军刀受限  %.1fs"%guard.impact_left,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color(1,0.65,0.35))
	if guard.slow_left>0:
		draw_string(font,Vector2(size.x*0.5-95,size.y*0.74),"减速90%%  %.1fs"%guard.slow_left,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color(1,0.74,0.42))
	if guard.elapsed>=guard.BAR_TIME:return
	var rect=Rect2(Vector2(size.x*0.5-170,size.y*0.64),Vector2(340,14))
	draw_style_box(panel(),rect.grow(7))
	draw_rect(rect,Color(0.12,0.18,0.23,0.95))
	var width:float=guard.WINDOW/guard.BAR_TIME*rect.size.x
	var green=Rect2(Vector2(rect.position.x+(guard.center-guard.WINDOW*0.5)/guard.BAR_TIME*rect.size.x,rect.position.y),Vector2(width,rect.size.y))
	var green_color:=Color(0.24,0.87,0.58,0.9)
	if (guard.attempted or guard.impact_left>0) and guard.result not in ["格挡成功","举盾防御","举盾防御成功"]: green_color=Color(0.25,0.31,0.29,0.8)
	draw_rect(green,green_color)
	var x:float=rect.position.x+guard.elapsed/guard.BAR_TIME*rect.size.x
	draw_line(Vector2(x,rect.position.y-5),Vector2(x,rect.end.y+5),Color.WHITE,3,true)
	var label:String=guard.result if guard.result!="" else ("近战键：格挡（踏板上不能举盾）" if body.has_pedal() else "近战键：格挡 / 举盾键：防御")
	draw_string(font,rect.position+Vector2(0,-14),label,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color(0.92,0.97,1))
func panel()->StyleBoxFlat:
	var style=StyleBoxFlat.new()
	style.bg_color=Color(0.01,0.025,0.04,0.82)
	style.set_corner_radius_all(5)
	return style
