extends Node
## 量一个模型资源在**自身单位**下的包围盒，用来定 `SuitProfile.model_native_height`。
##
## 跑法：
##   godot --headless --path <工程> res://tools/probe_model.tscn -- res://assets/models/xxx.glb [...]
##
## ## 为什么需要它
## `SuitProfile.model_native_height` 是**写死的**，而游戏是拿它算缩放：
##   scale = target_height / model_native_height
## 换一次模型资产，这个数就必须跟着换 —— 写错了的表现是"机体整体变大/变小"，
## 而代码不会报任何错。
##
## ⚠️ 口径必须和用户那条模型管线（`高达模型/gundam11_export2.py` → `pipeline.py`）一致：
## 管线只做"X/Z 居中、脚底落 Y=0、正面朝 −Z"，**不做尺寸归一**，
## 报告里的 `height_m` 就是这里的 `size.y`。两边对不上说明拿错了口径。

const DEFAULT_MODELS := [
	"res://assets/models/arizeus_v2/arizeus_v2_rigged.scn",
	"res://assets/models/arizeus/tx_ff104_arizeus_cruise.glb",
	"res://assets/models/arizeus/rx_94_mass_production_nu.glb",
]


func _ready() -> void:
	var paths: Array = OS.get_cmdline_user_args()
	if paths.is_empty():
		paths = DEFAULT_MODELS
	print("%-46s %8s %8s %8s   %s" % ["模型", "X", "Y(高)", "Z", "网格数"])
	print("-".repeat(96))
	for p: String in paths:
		_measure(p)
	print("PROBE_DONE")
	get_tree().quit(0)


func _measure(path: String) -> void:
	var ps := load(path)
	if ps == null or not (ps is PackedScene):
		print("%-46s 加载失败" % path)
		return
	var root := (ps as PackedScene).instantiate() as Node3D
	add_child(root)
	var aabb := AABB()
	var first := true
	var meshes := 0
	var inv: Transform3D = root.global_transform.affine_inverse()
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		meshes += 1
		# 用**相对 root** 的变换：这样量到的是模型自身坐标系下的盒子
		var t: Transform3D = inv * mi.global_transform
		var box: AABB = t * mi.mesh.get_aabb()
		if first:
			aabb = box
			first = false
		else:
			aabb = aabb.merge(box)
	print("%-46s %8.4f %8.4f %8.4f   %d" % [
		path.get_file(), aabb.size.x, aabb.size.y, aabb.size.z, meshes])
	_bottom_band(root, aabb)
	root.queue_free()


## 把模型沿高度切成 20 层，逐层打印顶点数与水平占地。
##
## ⚠️ 为什么必须查：模型管线把**整个包围盒的最低点**对齐到 Y=0（"脚底落地"）。
## 只要有任何部件（比如**垂直尾翼**）比脚还低，管线就会连着机体一起抬起来 ——
## 表现是**机体悬空**（脚底板离地），而代码不会报任何错。
## 逐层看就能一眼分辨：**脚**所在的那层占地宽（接近整个机体宽度），
## **尾翼/天线/碎片**那几层占地很窄（一条线）。
func _bottom_band(root: Node3D, aabb: AABB) -> void:
	var inv: Transform3D = root.global_transform.affine_inverse()
	var pts: PackedVector3Array = PackedVector3Array()
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var t: Transform3D = inv * mi.global_transform
		for v: Vector3 in mi.mesh.get_faces():
			pts.append(t * v)
	if pts.is_empty():
		return
	var bins := 20
	var cnt := PackedInt32Array()
	cnt.resize(bins)
	var lo := []
	var hi := []
	for i in bins:
		lo.append(Vector3(INF, INF, INF))
		hi.append(Vector3(-INF, -INF, -INF))
	var step := maxf(aabb.size.y, 0.0001) / float(bins)
	for p: Vector3 in pts:
		var b := clampi(int((p.y - aabb.position.y) / step), 0, bins - 1)
		cnt[b] += 1
		lo[b] = Vector3(minf(lo[b].x, p.x), minf(lo[b].y, p.y), minf(lo[b].z, p.z))
		hi[b] = Vector3(maxf(hi[b].x, p.x), maxf(hi[b].y, p.y), maxf(hi[b].z, p.z))
	print("      %-6s %-7s %7s %7s  %s" % ["层", "y范围", "顶点", "占地X", "占地Z / 判读"])
	var first_wide := -1
	for i in bins:
		if cnt[i] == 0:
			continue
		var sx: float = hi[i].x - lo[i].x
		var sz: float = hi[i].z - lo[i].z
		var wide := sx > aabb.size.x * 0.45
		if wide and first_wide < 0:
			first_wide = i
		print("      %-6d %.3f~%.3f %7d %7.3f %7.3f  %s" % [
			i, lo[i].y, hi[i].y, cnt[i], sx, sz,
			"← 宽（脚/腿）" if wide else "窄（尾翼/天线/碎片）"])
	if first_wide > 0:
		print("      ⚠️ 最低的 %d 层都是窄的 → Y=0 落在**非脚**的部件上，机体离地约 %.3f" % [
			first_wide, lo[first_wide].y - aabb.position.y])
