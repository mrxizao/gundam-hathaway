extends RefCounted
const Movie = preload("res://scripts/ui/startup_movie.gd")
static func run(t: T, host: Node) -> void:
	t.suite("PerformanceLoading / startup movie gate")
	var movie := Movie.new()
	host.add_child(movie)
	var key := InputEventKey.new()
	key.pressed = true; key.keycode = KEY_SPACE
	movie._input(key)
	t.not_ok(movie.done,"未加载完成时不能按键跳过")
	movie._on_video_finished()
	t.not_ok(movie.done,"影片先结束时仍等待加载")
	movie.set_loading_ready()
	t.ok(movie.done,"影片结束且加载完成后自动继续")
	movie.free()
	movie = Movie.new(); host.add_child(movie)
	movie.set_loading_ready()
	var axis := InputEventJoypadMotion.new()
	movie._input(axis)
	t.not_ok(movie.done,"手柄漂移不会跳过")
	key.echo = true; movie._input(key)
	t.not_ok(movie.done,"加载完成后长按回声不会误跳过")
	key.echo = false; movie._input(key)
	t.ok(movie.done,"加载完成后接受新的任意键按下")
	movie.free()
	t.suite("PerformanceLoading / AI targeting cadence")
	var ai := BanditAI.new()
	ai._target_scan_left = 0.1
	ai._refresh_target(0.01)
	t.near(ai._target_scan_left,0.09,0.0001,"没有目标时也限制空扫描频率")
	ai._refresh_target(0.2)
	t.gt(ai._target_scan_left,0.19,"到期才重新扫描阵营目标")
	ai.free()
	t.suite("PerformanceLoading / city stages")
	var w := WorldBuilder.new(); w.defer_initial_map = true
	host.add_child(w)
	t.eq(w._terrain_root.get_child_count(),0,"启动可延后首张地图生成")
	var stages: Array[String] = []
	var progress: Array[float] = []
	w.build_stage.connect(func(frac: float,label: String) -> void: stages.append(label); progress.append(frac))
	await w.apply_map_staged(MapDef.davao())
	t.gt(w._city_lot_built,1000,"分帧建图仍生成完整城市")
	t.gt(stages.size(),10,"城市加载在重阶段内持续报告进度")
	var monotonic := true
	for i in range(1,progress.size()):
		if progress[i]<progress[i-1]: monotonic=false
	t.ok(monotonic,"加载进度单调前进")
	var ground: MeshInstance3D = w._terrain_root.get_node("CityGround")
	var arrays := ground.mesh.surface_get_arrays(0)
	t.gt(arrays[Mesh.ARRAY_INDEX].size(),0,"城市地形使用索引复用顶点")
	t.gt(arrays[Mesh.ARRAY_INDEX].size(),arrays[Mesh.ARRAY_VERTEX].size()*4,"在保持三角形数量时显著减少重复顶点")
	w.free()
	await host.get_tree().process_frame
