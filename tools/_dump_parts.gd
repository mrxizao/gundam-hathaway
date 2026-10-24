extends SceneTree
## 一次性工具：把某个 GLB 的**部件名 + 各自 AABB**全部打出来。
## 用途：找"喷口/推进器"这类可以在名字上认出来的部件。
##
## 用法：godot --headless --path <工程> --script res://tools/_dump_parts.gd -- <res://模型路径> [关键词]

const KEYWORDS := ["nozzle", "thruster", "vernier", "booster", "burner", "exhaust",
	"スラスタ", "バーニア", "ノズル", "噴射", "推進", "喷射", "推进", "尾"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("用法：-- <res://模型路径> [关键词]")
		quit(1)
		return
	var path := args[0]
	var ps := load(path) as PackedScene
	if ps == null:
		print("load 失败：", path)
		quit(1)
		return
	var root := ps.instantiate() as Node3D
	print("\n=== %s ===" % path)
	var aabb := _aabb_of(root)
	print("整体 AABB  pos=(%.4f, %.4f, %.4f)  size=(%.4f, %.4f, %.4f)" % [
		aabb.position.x, aabb.position.y, aabb.position.z,
		aabb.size.x, aabb.size.y, aabb.size.z])
	var hit := 0
	var total := 0
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		total += 1
		var a: AABB = mi.mesh.get_aabb()
		var g := mi.global_transform
		var nm := str(mi.name)
		var pn := str(mi.get_parent().name) if mi.get_parent() != null else ""
		var low := (nm + " " + pn).to_lower()
		var kw := false
		for k: String in KEYWORDS:
			if low.contains(k.to_lower()):
				kw = true
				break
		if kw:
			hit += 1
			print("★ %-40s parent=%-28s  world_c=(%.3f, %.3f, %.3f)  aabb=(%.3f, %.3f, %.3f)" % [
				nm, pn, g.origin.x, g.origin.y, g.origin.z,
				a.size.x, a.size.y, a.size.z])
	print("…… 网格总数 %d，名字命中关键词 %d" % [total, hit])
	print("---- 全部部件名（前 120 个）----")
	var n := 0
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		n += 1
		if n > 120:
			break
		var g2 := mi.global_transform
		print("  [%3d] %-42s world_c=(%7.3f, %7.3f, %7.3f)" % [
			n, str(mi.name), g2.origin.x, g2.origin.y, g2.origin.z])
	quit(0)


func _aabb_of(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in node.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	if first:
		out = AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	return out
