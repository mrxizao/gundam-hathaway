extends Control
## Startup-only player. Loading gates input; campaign movies keep their old rules.
signal finished
const Playlist = preload("res://scripts/data/intro_playlist.gd")
var video: VideoStreamPlayer
var loading_ready := false
var ended := false
var done := false
var progress := 0.0
var step_text := "准备资源……"
var elapsed := 0.0
var watchdog := 300.0
var font: Font

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font
	set_process(false)
	set_process_input(false)

func begin() -> bool:
	var clip: Dictionary = Playlist.pick_random()
	var path: String = clip["path"]
	if not ResourceLoader.exists(path): return false
	var stream := load(path) as VideoStream
	if stream == null: return false
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var holder := AspectRatioContainer.new()
	holder.ratio = 16.0/9.0
	holder.stretch_mode = AspectRatioContainer.STRETCH_FIT
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	video = VideoStreamPlayer.new()
	video.expand = true
	video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	video.bus = Settings.BUS_BGM
	video.volume_db = linear_to_db(maxf(Settings.bgm_volume,0.0001))
	video.stream = stream
	holder.add_child(video)
	video.finished.connect(_on_video_finished)
	var length := video.get_stream_length()
	if length>0.0: watchdog=length+5.0
	# A separate last child paints the status over video instead of underneath it.
	var status := Control.new()
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)
	status.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	status.draw.connect(_draw_status)
	status.set_meta("startup_status",true)
	video.play()
	set_process(true)
	set_process_input(true)
	return true

func advance(value: float, label: String) -> void:
	progress = maxf(progress,clampf(value,0.0,1.0))
	step_text = label
	_refresh_status()

func set_loading_ready() -> void:
	loading_ready = true
	progress = 1.0
	_refresh_status()
	if ended: _finish()

func _on_video_finished() -> void:
	ended = true
	if loading_ready: _finish()
	else: _refresh_status()

func _process(delta: float) -> void:
	elapsed += delta
	if not ended and elapsed>watchdog:
		video.stop()
		_on_video_finished()

func _input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) or (event is InputEventJoypadButton and event.pressed)
	if not pressed or done: return
	get_viewport().set_input_as_handled()
	if loading_ready: _finish()

func _finish() -> void:
	if done: return
	done = true
	set_process(false)
	set_process_input(false)
	if is_instance_valid(video): video.stop()
	finished.emit()

func _refresh_status() -> void:
	for child: Node in get_children():
		if child.has_meta("startup_status"): child.queue_redraw()

func _draw_status() -> void:
	var target: Control = get_child(get_child_count()-1)
	var width := minf(360.0,maxf(size.x-64.0,80.0))
	var pos := Vector2(size.x-width-32.0,size.y-58.0)
	var text := "加载完成 · 按任意键跳过" if loading_ready else ("影片已结束 · "+step_text if ended else step_text)
	target.draw_rect(Rect2(pos-Vector2(12,25),Vector2(width+24,54)),Color(0.02,0.025,0.045,0.75))
	target.draw_string(font,pos,text,HORIZONTAL_ALIGNMENT_LEFT,width,17,Color(0.85,0.89,0.97))
	target.draw_rect(Rect2(pos+Vector2(0,12),Vector2(width,2)),Color(0.25,0.28,0.35))
	target.draw_rect(Rect2(pos+Vector2(0,12),Vector2(width*progress,2)),Color(0.65,0.77,0.92))
