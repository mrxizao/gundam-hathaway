extends Control
## Full-text cinematic/result radio card; the normal battle HUD keeps its own lanes.
var rows:Array[Dictionary]=[]
var cockpit_view:=false
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func _draw()->void:
	var width:float=minf(860,size.x*.78)
	var font:Font=ThemeDB.fallback_font
	for line in rows:
		var alpha:float=line.get("alpha",1.0)
		var wrapped=UILayout.wrap(font,line.text,width-36,20,4)
		var height:float=45+wrapped.size()*27
		var at:=Vector2((size.x-width)*.5,size.y*(.69 if cockpit_view else .83)-height)
		var panel:=StyleBoxFlat.new();panel.bg_color=Color(.012,.025,.04,.9*alpha);panel.set_corner_radius_all(4)
		draw_style_box(panel,Rect2(at,Vector2(width,height)))
		draw_line(at+Vector2(1,8),at+Vector2(1,height-8),Color(.68,.87,1,alpha),2,true)
		draw_string(font,at+Vector2(18,23),line.speaker,HORIZONTAL_ALIGNMENT_LEFT,width-36,15,Color(.65,.83,.93,alpha))
		for i in wrapped.size():draw_string(font,at+Vector2(18,50+i*27),wrapped[i],HORIZONTAL_ALIGNMENT_LEFT,width-36,20,Color(.96,.98,1,alpha))
