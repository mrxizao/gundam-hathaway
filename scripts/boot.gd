extends Control
## Small startup scene: render feedback before loading the main scene and world.
const MAIN := "res://scripts/main.gd"
const Screen := preload("res://scripts/ui/loading_screen.gd")
const Movie := preload("res://scripts/ui/startup_movie.gd")
var movie: Control
var failed := false
const PENDING := "user://startup.pending"
var screen: Control
var safe_mode := false
var status_log: FileAccess

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	safe_mode = FileAccess.file_exists(PENDING) or OS.get_cmdline_user_args().has("--safe-mode")
	var marker := FileAccess.open(PENDING,FileAccess.WRITE)
	if marker != null: marker.store_string("startup"); marker.close()
	status_log = FileAccess.open("user://startup_diagnostics.log",FileAccess.WRITE)
	_log("boot renderer="+RenderingServer.get_current_rendering_method()+" gpu="+RenderingServer.get_video_adapter_name()+" safe="+str(safe_mode))
	if safe_mode:
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		Settings.ssao = false
		Settings.cel_shading = false
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	add_child(overlay)
	screen = Screen.new()
	overlay.add_child(screen)
	screen.open("启动游戏" if not safe_mode else "启动游戏 · 稳定模式")
	set_process_input(false)
	var args := OS.get_cmdline_args()+OS.get_cmdline_user_args()
	if not safe_mode and DisplayServer.get_name()!="headless" and not args.has("--skip-intro"):
		movie = Movie.new()
		overlay.add_child(movie)
		if movie.begin(): screen.hide()
		else:
			movie.queue_free()
			movie = null
	_advance(0.02,"准备资源……")
	await get_tree().process_frame
	await get_tree().process_frame
	var err := ResourceLoader.load_threaded_request(MAIN,"Script")
	if err != OK:
		_fail("无法加载主场景（%d）" % err)
		return
	while true:
		var progress: Array = []
		var state := ResourceLoader.load_threaded_get_status(MAIN,progress)
		if state == ResourceLoader.THREAD_LOAD_LOADED: break
		if state == ResourceLoader.THREAD_LOAD_FAILED or state == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_fail("主场景资源加载失败，请检查游戏文件完整性")
			return
		if not progress.is_empty(): _advance(0.03+float(progress[0])*0.28,"加载游戏资源……")
		await get_tree().process_frame
	var main_script := ResourceLoader.load_threaded_get(MAIN) as Script
	if main_script == null or not main_script.can_instantiate():
		_fail("主场景资源无效")
		return
	_log("resources ready")
	_advance(0.32,"初始化界面……")
	await get_tree().process_frame
	var main := Node3D.new()
	main.name = "Main"
	main.set_script(main_script)
	main.staged_startup = true
	main.startup_stage.connect(_stage)
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	await main.startup_finished
	_log("startup complete")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PENDING))
	if is_instance_valid(movie):
		movie.set_loading_ready()
		if not movie.done: await movie.finished
	else:
		await screen.finish()
	main._show_menu()
	queue_free()

func _advance(frac: float, label: String) -> void:
	screen.advance(frac,label)
	if is_instance_valid(movie): movie.advance(frac,label)

func _stage(frac: float, label: String) -> void:
	_advance(frac,label)
	_log(label)

func _log(message: String) -> void:
	if status_log != null:
		status_log.store_line("%d %s" % [Time.get_ticks_msec(),message])
		status_log.flush()

func _fail(message: String) -> void:
	failed = true
	_log(message)
	if is_instance_valid(movie):
		movie.hide()
		movie.set_process_input(false)
		movie.set_process(false)
		if is_instance_valid(movie.video): movie.video.stop()
	screen.show()
	_advance(0.0,message+" · Esc 退出")
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if failed and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PENDING))
		get_tree().quit()


func _exit_tree() -> void:
	# A normal window close is not a crash. Native termination leaves the marker.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PENDING))
	if status_log != null: status_log.close()
