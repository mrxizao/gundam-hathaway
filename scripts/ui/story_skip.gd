extends CanvasLayer
## One visible skip entry for authored scenes; combat dialogue is not a cutscene.
var main
var button:Button
var blocked_until:=0
var changed_at:=0
var last_kind:=""
func setup(owner_main)->void:main=owner_main
func _ready()->void:
	layer=200;process_mode=Node.PROCESS_MODE_ALWAYS
	button=Button.new();button.text=InputSetup.hint("跳过演出  [空格 / Esc]","跳过演出  [A / B]")
	add_child(button);button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	button.position=Vector2(-310,24);button.size=Vector2(280,42);button.focus_mode=Control.FOCUS_NONE
	button.pressed.connect(skip);button.hide()
static func skip_event(event:InputEvent)->bool:
	return (event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE,KEY_ESCAPE]) or (event is InputEventJoypadButton and event.pressed and event.button_index in [JOY_BUTTON_A,JOY_BUTTON_B])
func movie()->Node:
	for node in get_tree().get_nodes_in_group("story_skip_movies"):
		if node._armed and not node._done and not node._skipping:return node
	return null
func kind()->String:
	if not is_instance_valid(main) or main._paused:return ""
	if movie()!=null:return "movie"
	if is_instance_valid(main.mission_title) and main.mission_title.active:return "title"
	match main.phase:
		main.Phase.LAUNCH:return "launch"
		main.Phase.POD_STRIKE:return "pod"
		main.Phase.DAVAO_INTRO:return "davao"
		main.Phase.SORTIE:return "sortie"
	return ""
func blocks_input()->bool:return Time.get_ticks_msec()<blocked_until
func _process(_delta:float)->void:
	var current:=kind()
	if current!=last_kind:last_kind=current;changed_at=Time.get_ticks_msec()
	button.visible=not current.is_empty() and not blocks_input()
func _input(event:InputEvent)->void:
	if not skip_event(event):return
	if blocks_input():get_viewport().set_input_as_handled();return
	if kind().is_empty() or Time.get_ticks_msec()-changed_at<350:return
	get_viewport().set_input_as_handled();skip()
func skip()->void:
	if blocks_input():return
	var current:=kind()
	if current.is_empty():return
	blocked_until=Time.get_ticks_msec()+300
	match current:
		"movie":movie().skip()
		"title":main.mission_title.skip()
		"launch":main._skip_story_launch()
		"pod":
			if is_instance_valid(main._strike_director):main._strike_director.skip_to_end()
			main._finish_pod_strike()
		"davao":
			if is_instance_valid(main._davao_director):main._davao_director.skip_to_end()
			main._finish_davao_intro()
		"sortie":
			if is_instance_valid(main._sortie_director):main._sortie_director.finish()
