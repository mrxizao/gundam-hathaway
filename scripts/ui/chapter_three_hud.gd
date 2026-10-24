extends Control
var controller: Node3D
var barrier_flash := 0.0
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
func _process(delta: float) -> void:
	barrier_flash=maxf(0.0,barrier_flash-delta*1.8)
	queue_redraw()
func _draw() -> void:
	if not is_instance_valid(controller) or controller.cleaned: return
	var main=controller.main
	if main.phase!=main.Phase.FIGHT:
		if barrier_flash>0: draw_rect(Rect2(Vector2.ZERO,size),Color(0.63,0.8,1.0,barrier_flash))
		return
	var font: Font=main.hud._font
	var width:=minf(600.0,size.x*.54)
	var at:=Vector2((size.x-width)*.5,74.0)
	var height: float=34.0+controller.mission.objectives.size()*23.0
	draw_rect(Rect2(at,Vector2(width,height)),Color(0.025,0.04,0.055,0.68))
	draw_line(at,at+Vector2(width,0),Color(.8,.91,1,.6),1.0)
	draw_string(font,at+Vector2(12,20),controller.mission.title,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color(.87,.94,1))
	var state: Dictionary=Game._end_state()
	var y:=at.y+43.0
	for objective in controller.mission.objectives:
		var done: bool=preload("res://scripts/data/mission_script.gd").Objective.done(objective,state)
		var label: String=objective.label
		if objective.kind==preload("res://scripts/data/mission_script.gd").Objective.Kind.DESTROY_ALL:
			label+="  %d/%d"%[Game.challenge_killed,Game.challenge_total]
		if objective.target=="messer_down": label+="  %d/3"%controller.messer_down
		draw_string(font,Vector2(at.x+12,y),("✓ " if done else "· ")+label,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color(.45,1,.72) if done else Color(.86,.91,.95))
		y+=23.0
	var point: Vector3=controller.target_point if controller.mission.chapter_three_mode=="lure" else controller.festival+Vector3.UP*2500
	if controller.mission.chapter_three_mode in ["raid","return","lure"]:
		var behind: bool=main.chase.is_position_behind(point)
		var marker: Vector2=main.chase.unproject_position(point)
		if behind:
			var local: Vector3=main.chase.global_basis.inverse()*(point-main.chase.global_position)
			var direction:=Vector2(local.x,-local.y)
			if direction.length_squared()<0.001: direction=Vector2.DOWN
			marker=size*.5+direction.normalized()*minf(size.x,size.y)*.42
		marker=marker.clamp(Vector2(34,175),size-Vector2(34,150))
		var color:=Color(.65,.9,1,.95)
		var diamond:=PackedVector2Array([marker+Vector2(0,-10),marker+Vector2(10,0),marker+Vector2(0,10),marker+Vector2(-10,0),marker+Vector2(0,-10)])
		draw_polyline(diamond,color,1.5,true)
		var label: String="S18 · 4km诱导区" if controller.mission.chapter_three_mode=="lure" else "节日中心 · 突入12km空域"
		if controller.mission.chapter_three_mode=="lure" and is_instance_valid(controller.target):
			label+=" · 柯西距目标 %.1fkm"%(controller.target.global_position.distance_to(point)/1000.0)
		if controller.mission.chapter_three_mode!="lure":
			var offset: Vector3=controller.main.player.global_position-controller.festival
			offset.y=0
			label+=" · %.1fkm"%(offset.length()/1000.0)
		var label_width:=font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
		var label_at:=Vector2(clampf(marker.x+14,18,maxf(18,size.x-label_width-18)),marker.y+25)
		draw_string(font,label_at,label,HORIZONTAL_ALIGNMENT_LEFT,-1,13,color)
	if barrier_flash>0: draw_rect(Rect2(Vector2.ZERO,size),Color(.63,.8,1,barrier_flash))
