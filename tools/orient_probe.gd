extends Node
## **一次性**诊断：判「某个 glb 模型正面朝哪一轴」—— **不靠看图**，靠**骨名自带的方位语义**。
##
## ## 为什么不用肉眼
## `tools/yaw_choices.gd` 的注释里写着：看渲染图判朝向**误判过两次**（把背面看成脸、
## 又把侧面看成脸）。四选一工具是为了绕过这个不可靠环节而存在的。
## 但四选一本身也只做到「给你四张图」，**最后一步还是眼睛**。
##
## 这里换一条**可自证**的路：模型的骨架上有一批**名字里带方位词**的骨 ——
## `RearHang`（后挂架）、`BinderBack`（后束甲）、`BinderFront`（前束甲）……
## 「Rear/Back」这类骨按语义一定长在机体的**后方**。
## 只要量出它们在**模型根坐标系**里的 Z 分量，就知道模型的后方是 +Z 还是 −Z，
## 于是正面（机头）方向也就定了 —— 全程是数字，没有一处需要"我觉得像脸"。
##
## ## 为什么量「模型根坐标系」而不是骨架本地坐标系
## `FlightBody._build_visual()` 把朝向修正加在 **`inst` 的父节点**（`ModelYaw`）上，
## 所以「模型正面朝哪」要在**实例根那一层**才说得通：
## glTF 导入器可能给实例根塞了旋转，骨架本地坐标看不到那一层。
## 这里用 `node.get_global_transform()`（相对本探针的根，根是单位阵）来拿，
## 等于「把实例当成放在原点的单位变换」时的世界位置 —— 正是我们要的那个坐标系。
##
## 跑法（**可以加 --headless**，本探针不出图）：
##   godot --headless --path <工程> res://tools/orient_probe.tscn -- <model_path> [<model_path> ...]
##
## 例：godot --headless --path . res://tools/orient_probe.tscn -- res://assets/models/xi_movie/xi_movie_rigged.scn

## 方位词表。分三组，用来给每根骨打标签（只打印命中的，避免 200+ 根刷屏）。
const REAR_WORDS := ["rear", "back", "tail", "aft"]
const FRONT_WORDS := ["front", "head", "chest", "neck", "nose", "face", "vis", "coc"]
const SIDE_WORDS := ["wing", "binder", "hang", "shoulder", "arm", "leg", "foot", "hand", "thruster", "nozzle", "booster"]

var _out: Array[String] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("用法：-- <model_path> [<model_path> ...]")
		get_tree().quit(1)
		return
	# ⚠️ **必须 await**：`_probe()` 里有 `await get_tree().process_frame`，
	# 不 await 的话它在第一个 await 处就返回了，下面的打印会**在探测完成前**跑完
	# （拿到半份输出，且没有任何报错）。这类"协程没接住"的坑在 GDScript 里是静默的。
	for p in args:
		await _probe(p)
	for line in _out:
		print(line)
	get_tree().quit(0)


func _probe(path: String) -> void:
	_out.append("")
	_out.append("================ %s ================" % path)
	var ps: PackedScene = load(path)
	if ps == null:
		_out.append("  !! load 失败")
		return
	var inst := ps.instantiate()
	add_child(inst)
	# 让变换生效（`_build_visual` 那边踩过 bound_box 陈旧的坑，这里统一刷一次）。
	await get_tree().process_frame

	var skels: Array[Skeleton3D] = []
	_collect(inst, skels)
	if skels.is_empty():
		_out.append("  !! 没有 Skeleton3D（无骨资产，走 blend shape 那条路）")
	# ⚠️ AABB **必须放在无骨架的提前 return 之前**：对无骨资产（佩涅罗佩 / 古斯塔夫 /
	# 梅萨 / 老柯西）来说，几何包围盒是**唯一**能拿到的量 —— 先 return 就等于
	# 对这批资产什么都不输出，而我正是要靠它给喷口分数当参照。
	var aabb := _subtree_aabb(inst)
	_out.append("  -- 实例根坐标系里的几何 AABB: pos=%s size=%s" % [_v(aabb.position), _v(aabb.size)])
	if skels.is_empty():
		inst.queue_free()
		return
	# 多个骨架时全部列出（实际资产通常只有一个）。
	for skel in skels:
		_dump_skeleton(inst, skel)
	inst.queue_free()


func _dump_skeleton(root: Node3D, skel: Skeleton3D) -> void:
	_out.append("  -- 骨架 %s（%d 骨）" % [skel.name, skel.get_bone_count()])
	# 骨架自身的变换（相对实例根）+ 每根骨的**全局**静止变换 ⇒ 骨在实例根坐标系里的位置。
	#
	# ⚠️ **必须用 `get_bone_global_rest()`，不能用 `get_bone_rest()`。**
	# 后者返回的是**相对父骨**的变换（"我离我爸多远"），拿它当绝对位置用，
	# 排出来的解剖顺序是**乱的** —— 本轮真踩过：`Foot.L` 的 y（0.2169）
	# 比 `head` 的 y（0.1877）还高，脚跑到头上面去了；
	# 而且 `Hand.L`/`hand_L`、`Chest`/`chest` 这种**同名重复骨**会显示成"逐位相同"
	# （它们只是恰好挂在同一个父骨下的同一偏移处）。
	# 这类错误**不会报任何错**，只会给出一张看起来挺像回事、其实全是垃圾的表。
	var skel_xf := _xf_in_root(root, skel)
	var rear_z: Array[float] = []
	var front_z: Array[float] = []
	var all: Array = []
	for i in skel.get_bone_count():
		var bn := skel.get_bone_name(i)
		var g := skel.get_bone_global_rest(i)
		var pos: Vector3 = skel_xf * g.origin
		all.append({"n": bn, "i": i, "p": pos})
		var low := bn.to_lower()
		if _has_any(low, REAR_WORDS):
			rear_z.append(pos.z)
		if _has_any(low, FRONT_WORDS):
			front_z.append(pos.z)
	# 只打印「方位词命中」的骨。
	var shown := 0
	for e in all:
		var low: String = (e["n"] as String).to_lower()
		if _has_any(low, REAR_WORDS) or _has_any(low, FRONT_WORDS) or _has_any(low, SIDE_WORDS):
			_out.append("     %-28s idx=%-4d p=(%.4f, %.4f, %.4f)" % [e["n"], e["i"], (e["p"] as Vector3).x, (e["p"] as Vector3).y, (e["p"] as Vector3).z])
			shown += 1
	if shown == 0:
		_out.append("     （没有命中方位词的骨，全部 %d 根骨名见下）" % all.size())
		for e in all:
			_out.append("     %-28s idx=%-4d p=(%.4f, %.4f, %.4f)" % [e["n"], e["i"], (e["p"] as Vector3).x, (e["p"] as Vector3).y, (e["p"] as Vector3).z])

	# ---- 自检：解剖顺序合不合理 ----
	#
	# **没有这道自检，上面那张表是没法被质疑的** —— 数字看起来总是"挺合理"。
	# 判据是**跟方位无关**的两条硬约束：最高的骨应当是头/颈，最低的骨应当是脚/小腿。
	# 违反了就说明「骨静止位置 → 实例根坐标系」这一步的假设错了（坐标系、缩放、
	# 或 API 语义），此时**后面所有关于 ±Z 的结论一律作废**，直接打警告。
	var top: Dictionary = all[0]
	var bot: Dictionary = all[0]
	for e in all:
		if (e["p"] as Vector3).y > (top["p"] as Vector3).y:
			top = e
		if (e["p"] as Vector3).y < (bot["p"] as Vector3).y:
			bot = e
	var top_ok := _has_any((top["n"] as String).to_lower(), ["head", "neck", "chest"]) or (top["p"] as Vector3).y > 0.5
	var bot_ok := _has_any((bot["n"] as String).to_lower(), ["foot", "leg", "knee", "ankle", "thigh"]) or (bot["p"] as Vector3).y < 0.25
	_out.append("  -- 自检（解剖顺序）：最高骨=%s y=%.4f %s ；最低骨=%s y=%.4f %s" % [
		top["n"], (top["p"] as Vector3).y, "OK" if top_ok else "**可疑**",
		bot["n"], (bot["p"] as Vector3).y, "OK" if bot_ok else "**可疑**"])
	if not (top_ok and bot_ok):
		_out.append("     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
		_out.append("     !! 自检未过 ⇒ 下面的 ±Z 判据**不可信**，请先修坐标换算。")
		_out.append("     !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")

	# ---- 判据汇总 ----
	_out.append("  -- 判据：")
	_stat("REAR 词骨（应位于机体后方）", rear_z)
	_stat("FRONT 词骨（应位于机体前方）", front_z)


func _stat(label: String, zs: Array[float]) -> void:
	if zs.is_empty():
		_out.append("     %s：0 根（无法据此判定）" % label)
		return
	var s := 0.0
	for z in zs:
		s += z
	var avg := s / zs.size()
	var verdict := "+Z" if avg > 0.0 else "−Z"
	_out.append("     %s：%d 根，z 均值 %+.4f ⇒ 这些骨在 %s 侧" % [label, zs.size(), avg, verdict])


func _has_any(low: String, words: Array) -> bool:
	for w: String in words:
		if low.contains(w):
			return true
	return false


func _collect(n: Node, out: Array[Skeleton3D]) -> void:
	if n is Skeleton3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


## 把 `n` 的变换表达在 `root` 的坐标系里（假设 root 是 Node3D 且我们想要的是
## 「root 为原点、单位朝向」下的位置）。
func _xf_in_root(root: Node3D, n: Node3D) -> Transform3D:
	var xf := n.global_transform
	# 去掉 root 自己的变换 ⇒ 得到「相对实例根」的变换。
	var inv := root.global_transform.affine_inverse()
	return inv * xf


func _subtree_aabb(root: Node3D) -> AABB:
	var res := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n
			if mi.mesh == null:
				continue
			var xf: Transform3D = inv * mi.global_transform
			var a := xf * mi.get_aabb()
			if first:
				res = a
				first = false
			else:
				res = res.merge(a)
	return res


func _v(v: Vector3) -> String:
	return "(%.4f, %.4f, %.4f)" % [v.x, v.y, v.z]
