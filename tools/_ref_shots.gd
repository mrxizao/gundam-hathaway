extends Node3D
## 给「别人做的巡航参照模型」出图，与主模型**同相机**对比。
##
## 为什么不用 `res://` 加载：参照在工程**之外**
##（`...\闪哈游戏\柯西与佩涅罗佩\柯西模型\柯西巡航2.0.glb`）⇒ 用 `GLTFDocument.append_from_file()` 读绝对路径。
##
## ★ 参照是**未烘 +90°** 的朝向：实测「转 −90° 后与主模型 183/203 件位置完全一致
##   （残余中位 0.0000）」⇒ 出图时给它 `rotation.y = -90°`，否则两张图朝向不同、没法比。
##
## 用法：godot --path . res://tools/_ref_shots.tscn -- --out <目录>

const REF_PATH := "C:/Users/MSIPC/Desktop/游戏/闪哈游戏/柯西与佩涅罗佩/柯西模型/柯西巡航2.0.glb"
const MAIN_PATH := "res://assets/models/xi_movie/xi_movie_rigged.scn"
## 参照相对主模型的朝向修正（实测 −90°）。
const REF_YAW_DEG := -90.0

var out_dir := ""
var _cam: Camera3D = null

## 视角：[名, 方位角°, 仰角°, 距离系数]
const VIEWS := [
	["top", 0.0, 89.0, 0.95],
	["side", 200.0, 6.0, 1.05],
	["front", 300.0, 6.0, 1.05],
	["q", 150.0, 22.0, 1.05],
]


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size():
			out_dir = a[i + 1]
	if out_dir == "":
		print("!! 需要 --out <目录>")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_dir.replace("\\", "/"))
	# 出图尺寸：带窗跑才有渲染；太小看不清翼板。
	var win := get_window()
	if win != null:
		win.size = Vector2i(1600, 1000)
	await _run()
	get_tree().quit(0)


func _load_glb(path: String) -> Node3D:
	if path.begins_with("res://"):
		var ps := load(path) as PackedScene
		if ps == null:
			return null
		return ps.instantiate() as Node3D
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(path, st)
	if err != OK:
		print("!! GLTFDocument 读失败 err=%d %s" % [err, path])
		return null
	return doc.generate_scene(st) as Node3D


func _bbox(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var b := mi.get_aabb()
		var bb := Transform3D(mi.global_transform.basis, mi.global_transform.origin) * b
		if first:
			out = bb
			first = false
		else:
			out = out.merge(bb)
	return out


func _shoot(tag: String, root: Node3D) -> void:
	root.position = Vector3.ZERO
	root.rotation = Vector3.ZERO
	if tag == "ref":
		root.rotation.y = deg_to_rad(REF_YAW_DEG)
	add_child(root)
	await get_tree().process_frame
	await get_tree().process_frame

	var b := _bbox(root)
	var focus := b.get_center()
	var radius: float = maxf(b.size.length() * 0.5, 0.5)
	print("  [%s] bounds center=%s size=%s radius=%.3f"
		% [tag, str(focus), str(b.size), radius])

	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 34.0
		_cam.near = 0.05
		_cam.far = 5000.0
		add_child(_cam)
	for v in VIEWS:
		var name := str(v[0])
		var az := deg_to_rad(float(v[1]))
		var el := deg_to_rad(float(v[2]))
		var k := float(v[3])
		var dir := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
		_cam.global_position = focus + dir * radius * 2.6 * k
		_cam.look_at(focus, Vector3.UP)
		_cam.current = true
		await get_tree().process_frame
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var p: String = out_dir.path_join("%s_%s.png" % [tag, name])
		img.save_png(p)
		print("    saved %s" % p)
	remove_child(root)
	root.queue_free()


func _run() -> void:
	print("")
	print("########## 巡航参照 vs 主模型 · 同相机出图 ##########")
	var ref := _load_glb(REF_PATH)
	if ref == null:
		print("!! 参照加载失败：%s" % REF_PATH)
		return
	await _shoot("ref", ref)
	var m := _load_glb(MAIN_PATH)
	if m == null:
		print("!! 主模型加载失败")
		return
	await _shoot("main", m)
	print("")
	print("VERDICT: REF-SHOTS-DONE")
