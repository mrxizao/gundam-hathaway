class_name SuitRig
extends Node3D
## 机体占位槽（placeholder slot rig）。
##
## 为什么不是随便堆几个方块：真模型（佩涅罗佩 GLB）还在处理中，但**炮口在哪、
## 喷口在哪、肩甲多宽**这些接口数据现在就要定下来。所以这里把机体拆成一组**具名槽位**：
##
##   SuitRig (Node3D)
##   ├─ slot: head / chest / waist / thigh_L / ...     ← 圆柱·方块占位件
##   └─ slot(name) -> Node3D                          ← 给外部取锚点用
##
## 真模型到位后调 `set_placeholder_visible(false)` 再挂 GLB 实例即可，
## `slot()` 返回的锚点（炮口、喷口）继续可用，飞行/武器逻辑一行不用改。
##
## 坐标：+X 右，+Y 上，−Z 前。原点在胸口（约为全高 55% 处），全高约 34.5 m，
## 比例参照万代 HGUC 1/144 ペーネロペー 说明书线稿与官方设定（头顶 26.0 m / 含 FF 单元全高 32.5 m）。

## 万代官方涂装色指定（见 penelope_model/README.md 第 3 节）
const PALETTE := {
	"white": Color("#EFF1F4"),
	"navy": Color("#3951AD"),
	"yellow": Color("#F5C518"),
	"red": Color("#B3121E"),
	"gray": Color("#5C5C68"),
	"black": Color("#454549"),
	"pink": Color("#F2969F"),
	"gold": Color("#C08A2E"),
	"nozzle": Color("#7A7A82"),
}

## 部件表。`mirror=true` 会自动生成 x 取反、名字 `_L`→`_R` 的镜像件。
const PARTS: Array = [
	# ---------------- 头部 ----------------
	{"slot": "head", "shape": "box", "pos": Vector3(0, 12.0, 0.3), "size": Vector3(4.2, 4.4, 5.0), "color": "white"},
	{"slot": "head_visor", "shape": "box", "pos": Vector3(0, 12.6, -2.2), "size": Vector3(3.0, 1.7, 0.9), "color": "pink"},
	{"slot": "head_fin", "shape": "box", "pos": Vector3(0, 13.8, 1.4), "size": Vector3(0.7, 3.0, 2.6), "color": "yellow"},
	{"slot": "head_boom", "shape": "box", "pos": Vector3(0, 12.2, -7.6), "size": Vector3(1.6, 1.6, 10.0), "color": "gray"},
	{"slot": "vulcan_port", "shape": "cyl", "pos": Vector3(0.55, 12.2, -12.4), "size": Vector3(0.32, 1.6, 0.32), "color": "black", "axis": "z"},
	{"slot": "vulcan_stbd", "shape": "cyl", "pos": Vector3(-0.55, 12.2, -12.4), "size": Vector3(0.32, 1.6, 0.32), "color": "black", "axis": "z"},

	# ---------------- 躯干 ----------------
	{"slot": "neck", "shape": "cyl", "pos": Vector3(0, 8.7, 0.4), "size": Vector3(1.7, 2.6, 1.7), "color": "black"},
	{"slot": "chest", "shape": "box", "pos": Vector3(0, 4.0, 0.0), "size": Vector3(11.0, 9.0, 8.2), "color": "white"},
	{"slot": "chest_collar", "shape": "box", "pos": Vector3(0, 8.2, -1.4), "size": Vector3(9.0, 1.6, 5.4), "color": "navy"},
	{"slot": "chest_boom", "shape": "box", "pos": Vector3(0, 4.6, -7.8), "size": Vector3(2.3, 2.3, 8.4), "color": "navy"},
	{"slot": "monoeye", "shape": "box", "pos": Vector3(0, 4.6, -12.0), "size": Vector3(1.5, 1.5, 0.6), "color": "red"},
	{"slot": "chest_duct_L", "shape": "box", "pos": Vector3(3.6, 6.6, -3.0), "size": Vector3(1.4, 4.0, 1.4), "color": "yellow", "mirror": true},
	{"slot": "abdomen", "shape": "box", "pos": Vector3(0, -1.2, 0.2), "size": Vector3(7.6, 5.2, 6.2), "color": "navy"},
	{"slot": "waist", "shape": "box", "pos": Vector3(0, -4.4, 0.2), "size": Vector3(10.2, 2.8, 7.0), "color": "white"},

	# ---------------- 裙甲 ----------------
	{"slot": "skirt_front", "shape": "box", "pos": Vector3(0, -6.2, -3.4), "size": Vector3(7.6, 5.4, 2.0), "color": "white"},
	{"slot": "skirt_back", "shape": "box", "pos": Vector3(0, -6.2, 3.6), "size": Vector3(7.6, 5.0, 2.0), "color": "white"},
	{"slot": "skirt_side_L", "shape": "box", "pos": Vector3(4.8, -6.4, 0.4), "size": Vector3(2.4, 6.4, 6.6), "color": "navy", "mirror": true},

	# ---------------- 背包 / 喷口 ----------------
	{"slot": "backpack", "shape": "box", "pos": Vector3(0, 4.6, 6.0), "size": Vector3(9.2, 9.4, 3.8), "color": "gray"},
	{"slot": "back_fin", "shape": "box", "pos": Vector3(0, 10.0, 6.6), "size": Vector3(0.8, 6.0, 3.0), "color": "yellow"},
	{"slot": "thruster_L", "shape": "nozzle", "pos": Vector3(2.8, 4.4, 8.6), "size": Vector3(2.4, 4.6, 2.4), "color": "nozzle", "axis": "z", "mirror": true},

	# ---------------- 肩部 / 米诺夫斯基单元 / funnel ----------------
	{"slot": "shoulder_L", "shape": "box", "pos": Vector3(7.7, 7.0, 0.2), "size": Vector3(7.4, 7.0, 7.6), "color": "white", "mirror": true},
	{"slot": "shoulder_cap_L", "shape": "box", "pos": Vector3(7.7, 10.6, 0.2), "size": Vector3(7.8, 1.4, 8.0), "color": "navy", "mirror": true},
	## 宽幅层叠翼板（米诺夫斯基飞行单元）—— 金色内衬从板缝里露出来
	{"slot": "wing_L", "shape": "box", "pos": Vector3(11.6, 9.4, 0.6), "size": Vector3(13.0, 1.9, 8.6), "color": "white",
		"rot": Vector3(0, 0, -14.0), "mirror": true},
	{"slot": "wing_gold_L", "shape": "box", "pos": Vector3(11.6, 8.2, 0.6), "size": Vector3(12.0, 0.7, 7.6), "color": "gold",
		"rot": Vector3(0, 0, -14.0), "mirror": true},
	## funnel 远距离攻击单元：细长刀状挂架，根部带推进器
	{"slot": "funnel_L", "shape": "box", "pos": Vector3(14.6, 8.8, 1.6), "size": Vector3(1.3, 15.0, 2.4), "color": "white",
		"rot": Vector3(0, 0, 8.0), "mirror": true},
	{"slot": "funnel_tip_L", "shape": "box", "pos": Vector3(15.6, 16.0, 1.6), "size": Vector3(0.9, 2.2, 1.6), "color": "red",
		"rot": Vector3(0, 0, 8.0), "mirror": true},

	# ---------------- 手臂 ----------------
	{"slot": "arm_upper_L", "shape": "cyl", "pos": Vector3(8.8, 2.2, 0.2), "size": Vector3(1.9, 8.8, 1.9), "color": "white", "mirror": true},
	{"slot": "elbow_L", "shape": "box", "pos": Vector3(8.8, -2.6, 0.2), "size": Vector3(3.4, 2.6, 3.6), "color": "navy", "mirror": true},
	{"slot": "arm_fore_L", "shape": "cyl", "pos": Vector3(8.8, -6.6, 0.0), "size": Vector3(2.0, 6.6, 2.0), "color": "white", "mirror": true},
	## 前臂盾（内藏光束军刀）—— 同时作为机炮炮口
	{"slot": "shield_L", "shape": "box", "pos": Vector3(11.2, -6.6, -0.6), "size": Vector3(1.6, 9.0, 6.2), "color": "white", "mirror": true},
	{"slot": "muzzle_L", "shape": "cyl", "pos": Vector3(10.6, -6.6, -4.6), "size": Vector3(0.6, 1.6, 0.6), "color": "black",
		"axis": "z", "mirror": true},
	{"slot": "hand_L", "shape": "box", "pos": Vector3(8.8, -10.4, 0.0), "size": Vector3(2.6, 2.8, 2.8), "color": "gray", "mirror": true},

	# ---------------- 腿 ----------------
	{"slot": "hip_L", "shape": "box", "pos": Vector3(3.3, -5.6, 0.2), "size": Vector3(3.8, 3.4, 4.4), "color": "gray", "mirror": true},
	{"slot": "thigh_L", "shape": "cyl", "pos": Vector3(3.3, -8.4, 0.2), "size": Vector3(2.6, 5.4, 2.6), "color": "white", "mirror": true},
	{"slot": "knee_L", "shape": "box", "pos": Vector3(3.3, -11.4, -0.8), "size": Vector3(4.0, 3.2, 4.6), "color": "navy", "mirror": true},
	{"slot": "shin_L", "shape": "cyl", "pos": Vector3(3.3, -14.4, 0.2), "size": Vector3(2.5, 5.6, 2.5), "color": "white", "mirror": true},
	{"slot": "leg_unit_L", "shape": "box", "pos": Vector3(6.2, -13.6, 0.6), "size": Vector3(1.8, 7.6, 4.0), "color": "navy", "mirror": true},
	{"slot": "ankle_L", "shape": "box", "pos": Vector3(3.3, -17.2, 0.2), "size": Vector3(3.2, 1.6, 3.4), "color": "gray", "mirror": true},
	{"slot": "foot_L", "shape": "box", "pos": Vector3(3.3, -18.4, -1.4), "size": Vector3(4.2, 2.2, 7.6), "color": "white", "mirror": true},
	{"slot": "foot_tip_L", "shape": "box", "pos": Vector3(3.3, -18.6, -5.4), "size": Vector3(3.8, 1.8, 1.4), "color": "red", "mirror": true},
]

var _slots := {}
var _placeholder_root: Node3D


func _ready() -> void:
	build()


func build() -> void:
	if _placeholder_root != null:
		return
	_placeholder_root = Node3D.new()
	_placeholder_root.name = "Placeholder"
	add_child(_placeholder_root)
	for p: Dictionary in PARTS:
		_spawn(p, false)
		if p.get("mirror", false):
			_spawn(p, true)


func _spawn(p: Dictionary, mirrored: bool) -> void:
	var slot_name: String = p["slot"]
	if mirrored:
		slot_name = slot_name.replace("_L", "_R")
	var holder := Node3D.new()
	holder.name = slot_name
	var pos: Vector3 = p["pos"]
	if mirrored:
		pos = Vector3(-pos.x, pos.y, pos.z)
	holder.position = pos
	if p.has("rot"):
		var rot: Vector3 = p["rot"]
		if mirrored:
			rot = Vector3(rot.x, -rot.y, -rot.z)
		holder.rotation_degrees = rot
	_placeholder_root.add_child(holder)
	_slots[slot_name] = holder

	var mi := MeshInstance3D.new()
	mi.name = "mesh"
	var size: Vector3 = p.get("size", Vector3.ONE)
	var shape: String = p.get("shape", "box")
	var axis: String = p.get("axis", "y")
	var color: Color = PALETTE.get(p.get("color", "white"), Color.WHITE)
	mi.mesh = _make_mesh(shape, size, color)
	# 圆柱默认沿 +Y；axis="z" 时躺倒，轴线指向 ±Z（炮口朝前 / 喷口朝后）
	if (shape == "cyl" or shape == "nozzle") and axis == "z":
		mi.rotation_degrees = Vector3(90, 0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	holder.add_child(mi)


## size 约定：圆柱/喷口用 size.y 作长度、size.x 作直径；方块用 size 作三边。
func _make_mesh(shape: String, size: Vector3, color: Color) -> Mesh:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.42
	mat.metallic = 0.15
	if shape == "cyl" or shape == "nozzle":
		var c := CylinderMesh.new()
		c.radial_segments = 16
		c.rings = 1
		c.height = size.y
		if shape == "nozzle":
			c.top_radius = size.x * 0.34
			mat.metallic = 0.85
			mat.roughness = 0.28
		else:
			c.top_radius = size.x * 0.5
		c.bottom_radius = size.x * 0.5
		c.material = mat
		return c
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	return b


## 取槽位锚点。返回 null 表示该槽不存在（真模型替换后仍应保留同名锚点）。
func slot(name: String) -> Node3D:
	if _slots.has(name):
		return _slots[name]
	return find_child(name, true, false) as Node3D


func has_slot(name: String) -> bool:
	return slot(name) != null


## 真模型到位后调用：隐藏占位件，但槽位节点与锚点全部保留。
func set_placeholder_visible(v: bool) -> void:
	if _placeholder_root != null:
		_placeholder_root.visible = v


func placeholder_visible() -> bool:
	return _placeholder_root != null and _placeholder_root.visible


func slot_names() -> Array:
	return _slots.keys()


## 全部占位件的合并包围盒（机体局部空间）。
## 注意要连 mesh 子节点自身的变换一起算 —— axis="z" 的圆柱/喷口是靠
## MeshInstance3D 的 90° 旋转躺倒的，漏掉它包围盒就是错的。
func local_bounds() -> AABB:
	var out := AABB()
	var first := true
	for name: String in _slots:
		var holder: Node3D = _slots[name]
		var mi := holder.get_node_or_null("mesh") as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var a: AABB = (holder.transform * mi.transform) * mi.mesh.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out
