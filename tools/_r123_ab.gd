extends Node
## A/B 诊断：`CityRoads` 到底在画面里是哪一块？
##
## 起因：验收图里，城市地层上有一层**等距的蓝色网格状亮斑**，位置与"路网"可疑地吻合；
## 但路材质是接近黑的 `(0.055, 0.053, 0.052)`，按理不该发亮。
## ⇒ 同一机位拍两张：**路面开** / **路面关**（把 `Terrain/CityRoads` 隐藏）。
##   差在哪，那一块就是路面。
##
## 跑法（不能 `--headless`）：
##   godot --path <工程> res://tools/_r123_ab.tscn -- <输出目录>

var out_dir := "user://r123_ab"
var _world: WorldBuilder


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_world = WorldBuilder.new()
	add_child(_world)
	await get_tree().physics_frame
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 1.0
	cam.far = 900000.0
	add_child(cam)
	cam.current = true
	_world.apply_map(MapDef.davao())
	await _frames(20)
	# 站在支路那一格的正上方斜看（这一格里，路是最主要的水平面）
	cam.global_position = Vector3(4025.0, 900.0, 1500.0)
	cam.look_at(Vector3(4025.0, 0.0, 900.0), Vector3.UP)
	await _frames(14)
	var roads := _find(_world, "CityRoads")
	print("[ab] CityRoads 节点 = ", roads)
	await _shot("roads_ON", 1.8)
	if roads != null:
		roads.visible = false
		await _frames(14)
		await _shot("roads_OFF", 1.8)
		print("[ab] 已隐藏 CityRoads 再拍一张")
	print("AB_DONE -> ", out_dir)
	get_tree().quit(0)


func _find(n: Node, want: String) -> Node:
	if n.name == want:
		return n
	for c in n.get_children():
		var hit := _find(c, want)
		if hit != null:
			return hit
	return null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name: String, gain: float) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var shot := img
	if not is_equal_approx(gain, 1.0):
		shot = img.duplicate() as Image
		shot.adjust_bcs(gain, 1.0, 1.0)
	var p := out_dir.path_join("%s.png" % name)
	print("SHOT %s err=%d" % [p, shot.save_png(p)])
