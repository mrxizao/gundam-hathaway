extends Control
const Dialogue = preload("res://scripts/data/pod_strike_dialogue.gd")
var clock := 0.0
var in_video := false
func _ready() -> void:
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func _draw() -> void:
 var rows:=Dialogue.active_lines(clock,in_video)
 var width:=minf(900.0,size.x*.82)
 var height:=72.0
 var y:=size.y*.89-rows.size()*(height+8.0)
 for line in rows:
  var a:float=line.alpha
  var panel:=StyleBoxFlat.new()
  panel.bg_color=Color(.012,.025,.04,.88*a)
  panel.set_corner_radius_all(5)
  var rect:=Rect2(Vector2((size.x-width)*.5,y),Vector2(width,height))
  draw_style_box(panel,rect)
  draw_line(rect.position+Vector2(1,9),rect.position+Vector2(1,height-9),Color(.68,.87,1,a),2,true)
  draw_string(ThemeDB.fallback_font,rect.position+Vector2(18,23),"电台 · "+line.speaker,HORIZONTAL_ALIGNMENT_LEFT,width-36,15,Color(.65,.83,.93,a))
  draw_string(ThemeDB.fallback_font,rect.position+Vector2(18,53),line.text,HORIZONTAL_ALIGNMENT_LEFT,width-36,22,Color(.95,.97,1,a))
  y+=height+8
