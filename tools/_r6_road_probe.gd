extends Node
## 读数探针：**路网与高架的三件用户投诉**（2026-09-28）。
##
## ⚠️⚠️ 2026-09-28：**必须带窗口跑**（不能 `--headless`）。
## 这里量过一次 headless：`get_instance_transform()` 在 dummy 渲染器下**全回单位变换**
## ⇒ `origin` 全在 (0,0,0) ⇒ 读数长成"**实有 1 段 = 0.0%**""**到图心距离 0…0 m**"
##"**偏航角 0°×139**"—— 三个数**都像结论**，实际全是同一个原因。
##（`instance_count` 是属性、headless 下仍准确 ⇒ 只有"按位置推出来的量"会假。）
##
##   godot --path <工程> res://tools/_r6_road_probe.tscn
##
## ## 为什么不能靠看图
## 用户报的三件事（「道路在地上**断断续续**」「楼房间有**穿插**的断断续续的高架桥」
## 「高架桥**也都是直直的**」）在画面上都只是"哪里怪怪的"，而在源码里分别对应
## **三个完全不同的机制**。靠看图会把它们混成一句话；靠读源码会漏掉"程度"。
## 所以这里**从建好的场景里把几何读回来**，逐条给数：
##
## | # | 量什么 | 为什么是它 |
## |---|---|---|
## | 1 | 每条格线上**缺了哪几段**、缺口有多长、缺口处是水还是地 | "断断续续"的**位置与原因** |
## | 2 | 路面段落在**半径 > `CITY_HILL_IN`**（山陵内缘）的数量 | 路铺到了山上（另一件不报错的错） |
## | 3 | 桥面段与**楼体 AABB 真正相交**的数量 | "穿插"的**硬证据**（不是"看起来穿"） |
## | 4 | 桥面段的**偏航角直方图** | "都是直直的"—— 环线若全落在 0°，说明它**根本没沿切线转** |
## | 5 | 桥墩落在**楼体占地之内**的数量 | 墩插在楼里（"幽灵碰撞"的另一半） |

var _w: WorldBuilder
var _unit := AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
var _city := "oenb"
var _map: MapDef
var LAY := MapDef.CityLayout.OENBELLI


func _ready() -> void:
	# ---- 2026-09-28 B5：加 `--city=`（原来硬绑奥恩贝利 ⇒ 达沃的路网没有"新口径"读数，
	#      而 `_r8_davao_probe` §4 是**自己复刻了一遍源侧筛选**（旧口径、第二真源）。
	#      现在两城共用这一份判据：`godot --path . res://tools/_r6_road_probe.tscn -- --city=davao`
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--city="):
			_city = a.substr(7)
	_map = MapDef.davao() if _city == "davao" else MapDef.oenbelli()
	LAY = MapDef.CityLayout.DAVAO if _city == "davao" else MapDef.CityLayout.OENBELLI
	_w = WorldBuilder.new()
	add_child(_w)
	await get_tree().physics_frame
	_w.apply_map(_map)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var cb: float = WorldBuilder.ARENA_RADIUS / float(WorldBuilder.CITY_GRID)
	var hill_in: float = WorldBuilder.CITY_HILL_IN
	var rr_ring: float = WorldBuilder.CITY_SHAPE[LAY].via_ring_r
	print("==== 0 · 常量 ====")
	print("  图：%s" % _map.name_cn)
	print("  格距 %.1f m   CITY_GRID %d" % [cb, WorldBuilder.CITY_GRID])
	print(("  ⚠️ `CITY_VIA_DECK_Y = %.1f` **已弃用**（桥面改成沿线剖面）"
		+ " —— 本探针**不再读它**当标高判据（读了会出**假 0**）")
		% WorldBuilder.CITY_VIA_DECK_Y)
	print("  高架桥面：**沿线剖面**（下界 %.0f m / 净空 %.0f m / 限坡 %.1f%%）"
		% [WorldBuilder.CITY_VIA_MIN_Y, WorldBuilder.CITY_VIA_CLEARANCE,
			WorldBuilder.CITY_VIA_MAX_GRADE * 100.0])
	print("  桥宽 %.1f m   环线半径 %.0f m / %d 段"
		% [WorldBuilder.CITY_VIA_W, rr_ring, WorldBuilder.CITY_VIA_RING_SEGS])
	print("  丘陵内缘 CITY_HILL_IN = %.0f m（路铺到它外面 = 铺到山上）" % hill_in)

	# ---------------------------------------------------------------- 楼体 AABB
	var bld: Array[AABB] = []
	for b: Node in _w.find_children("*", "StaticBody3D", true, false):
		var nm := String(b.name)
		if not (nm.begins_with("Podium_") or nm.begins_with("Tower_")
				or nm.begins_with("Setback_")):
			continue
		var mi := b.get_child(0) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		bld.append(_box_aabb(mi.global_transform, mi.mesh.get_aabb()))
	print("")
	print("==== 1 · 楼体 ====")
	print("  裙房 / 塔 / 退台 的 AABB 共 %d 个" % bld.size())

	# ---------------------------------------------------------------- 路网
	print("")
	print("==== 2 · 路网：逐条格线数缺段 ====")
	_run_audit(cb, WorldBuilder.CITY_GRID / 2)
	var road_mm := _w.find_child("CityRoads", true, false) as MultiMeshInstance3D
	if road_mm == null:
		print("  **没找到 `CityRoads` 节点**（名字变了？）")
	else:
		_road_report(road_mm, cb, hill_in)

	# ---------------------------------------------------------------- 高架
	print("")
	print("==== 3 · 高架：桥面 / 墩 / 穿楼 ====")
	var deck_mm := _w.find_child("CityViaductDeck", true, false) as MultiMeshInstance3D
	var rail_mm := _w.find_child("CityViaductRail", true, false) as MultiMeshInstance3D
	# ⚠️⚠️ 2026-09-28：**这一段原来是靠"尺寸"认墩的**，因为
	# `_add_box("ViaductPier", …)` 在同一个父节点下被调 N 次 ⇒ Godot 4.7 把后来者
	# 改名成 `@StaticBody3D@1346`（**丢掉原名**）⇒ `find_children("ViaductPier*")`
	# 只回 **1** 个 —— 而"1 根墩"这个读数**完全不刺眼**（本工程最贵的一种错：静默低报）。
	# ⇒ 现在建城侧给墩名**都加了序号**（`ViaductPier0`…）⇒ 回到**按名字**认，
	# 它是**精确**的。而"120 m 见方"这个签名在 B1 / B3 之后**已经不唯一**
	#（`CanalBridgePier` 与 `BridgeRampPier` 都是 120 见方）⇒ 继续用尺寸认会**多收**。
	var piers: Array[Node] = _w.find_children("ViaductPier*", "StaticBody3D", true, false)
	var by_size := 0
	var at_n := 0
	var fam := {}
	for b: Node in _w.find_children("*", "StaticBody3D", true, false):
		var nm := String(b.name)
		if nm.begins_with("@"):
			at_n += 1
		var mi2 := b.get_child(0) as MeshInstance3D
		if mi2 != null \
				and absf(mi2.scale.x - WorldBuilder.CITY_VIA_PIER_W) < 0.01 \
				and absf(mi2.scale.z - WorldBuilder.CITY_VIA_PIER_W) < 0.01:
			by_size += 1
		for key: String in ["ViaductPier", "CanalBridgePier", "BridgeRampPier",
				"MonorailPylon", "BridgePylon"]:
			if nm.begins_with(key):
				fam[key] = int(fam.get(key, 0)) + 1
	print("  支撑件（**按名字精确数**）：%s" % str(fam))
	print("  ⚠️ 名字被引擎改成 `@…` 的 StaticBody3D = **%d**（这个数以前是 104）"
		% at_n)
	print("  ⚠️ `%.0f m 见方`的 StaticBody3D = %d（**三个族混在一起**，不能当墩数）"
		% [WorldBuilder.CITY_VIA_PIER_W, by_size])
	var tr := _w.find_child("Terrain", false, false) as Node3D
	if tr != null:
		var pre := {}
		for c in tr.get_child_count():
			var nm2 := String(tr.get_child(c).name)
			var k2 := nm2.substr(0, 12)
			pre[k2] = int(pre.get(k2, 0)) + 1
		print("  `Terrain` 直接子节点 %d 个；名字前 12 字直方图（取前 8 种）：%s"
			% [tr.get_child_count(), str(pre.keys().slice(0, 8))])
		var t_pier := 0
		var t_sb := 0
		for c in tr.get_child_count():
			var nm3 := String(tr.get_child(c).name)
			if tr.get_child(c) is StaticBody3D:
				t_sb += 1
			if nm3.contains("Pier"):
				t_pier += 1
		print("  `Terrain` 直接子节点里：StaticBody3D %d 个，名字含 `Pier` 的 **%d** 个"
			% [t_sb, t_pier])
		# ---- 决定性一问：重名的节点被引擎改成什么了？----
		var at := 0
		var tail: Array[String] = []
		for c in tr.get_child_count():
			var nm4 := String(tr.get_child(c).name)
			if nm4.begins_with("@"):
				at += 1
			if c >= tr.get_child_count() - 6:
				tail.append(nm4)
		print("  名字以 `@` 开头的子节点 = %d 个；最后 6 个子节点名 = %s"
			% [at, str(tail)])
		var at_names: Array[String] = []
		var mid_names: Array[String] = []
		for c in tr.get_child_count():
			var nm5 := String(tr.get_child(c).name)
			if nm5.begins_with("@") and at_names.size() < 6:
				at_names.append(nm5)
			if c >= 1195 and c < 1205:
				mid_names.append("%d:%s" % [c, nm5])
		print("  `@` 开头的前 6 个 = %s" % str(at_names))
		print("  第 1195…1204 个子节点 = %s" % str(mid_names))
	var deck_n := deck_mm.multimesh.instance_count if deck_mm != null else -1
	var rail_n := rail_mm.multimesh.instance_count if rail_mm != null else -1
	print("  桥面段 %d   护栏段 %d   墩 %d" % [deck_n, rail_n, piers.size()])
	# ⚠️⚠️ 2026-09-28：y 判据**不能再读 `CITY_VIA_DECK_Y`** —— 那个常量**已弃用**
	#（桥面改成沿线剖面，奥恩贝利实测 **240…1 321 m**，达沃到 **2 332 m**）。
	# 读它（360）会让"楼体在 y 上包住桥面"这件事**恒为假** ⇒ 满篇"0 处穿楼"，
	# 而这个 0 是**假的**、还长得特别像好消息（文档 §0.5 静默陷阱 ③ 记的就是这一条）。
	# ⇒ 一律用**那一段自己的 y**（桥面取段变换原点；墩取自己的顶面）。
	var pier_real := 0
	for p: Node in piers:
		var pn := p as Node3D
		var pmi := pn.get_child(0) as MeshInstance3D
		var ptop := pn.global_position.y \
			+ (pmi.scale.y * 0.5 if pmi != null else 0.0)
		var pos := pn.global_position
		for ba: AABB in bld:
			if pos.x >= ba.position.x and pos.x <= ba.position.x + ba.size.x \
					and pos.z >= ba.position.z and pos.z <= ba.position.z + ba.size.z \
					and ba.position.y <= ptop and ba.position.y + ba.size.y >= ptop:
				pier_real += 1
				break
	print("  ⚠️ **立在楼体占地之内的墩（按**顶面标高**判的）= %d / %d**"
		% [pier_real, piers.size()])
	if deck_mm != null:
		var hit_seg := 0
		var hit_max := 0
		var hit_exact := 0
		var hit_exact_max := 0
		var deep_exact := 0
		var min_depth := 1.0e18
		var yaw_hist := {}
		var cross_seg := 0
		var ring_seg := 0
		var pier_total := 0
		var pier_in_bld := 0
		var ring_sched := 0
		for i in deck_n:
			var t := deck_mm.multimesh.get_instance_transform(i)
			var ab := _box_aabb(t, _unit)
			var bq := _box_quad(t, _unit)
			var bys := _box_yspan(t, _unit)
			var k := int(round(rad_to_deg(t.basis.get_euler().y) / 5.0)) * 5
			yaw_hist[k] = int(yaw_hist.get(k, 0)) + 1
			var rr_seg := sqrt(t.origin.x * t.origin.x + t.origin.z * t.origin.z)
			if rr_ring > 0.0 and absf(rr_seg - rr_ring) < cb * 0.5:
				ring_seg += 1
			else:
				cross_seg += 1
			# ---- 两个口径并排：旧的 AABB（**会膨胀**）与新的精确 SAT ----
			var n := 0
			var n_ex := 0
			var depth := 1.0e18
			for ba: AABB in bld:
				if ab.intersects(ba):
					n += 1
				# y 区间先粗筛（省 8 轴 SAT），再过 XZ 精确
				if bys.x > ba.position.y + ba.size.y or ba.position.y > bys.y:
					continue
				var dp := _quad_depth(bq, _aabb_quad(ba))
				if dp > 0.0:
					n_ex += 1
					depth = minf(depth, dp)
			if n > 0:
				hit_seg += 1
				hit_max = maxi(hit_max, n)
			if n_ex > 0:
				hit_exact += 1
				hit_exact_max = maxi(hit_exact_max, n_ex)
				deep_exact += 1 if depth > 120.0 else 0
				min_depth = minf(min_depth, depth)
			# ---- 墩落点：`_append_via_seg()` 把墩放在**段中点**，
			#      "这一段排到墩吗" × "中点落不落进楼体占地" 就决定它建不建。
			#      ⚠️ 判据**用建城侧那个函数本身**（`_city_via_lot_top`），
			#      不在这里再写一遍"点在不在矩形里"—— 那会变成**第二份真源**
			#      （旧版就是这么写的：它判的是"段中点在有路的楼里"，而建城侧判的是
			#        "420 宽的带子撞到楼" ⇒ 两个数差 2 处，谁也不知道差在哪）。
			var has_pier := true
			if rr_ring > 0.0 and absf(rr_seg - rr_ring) < cb * 0.5:
				var idx := roundi(atan2(t.origin.z, t.origin.x) / TAU
					* float(WorldBuilder.CITY_VIA_RING_SEGS))
				has_pier = posmod(idx, WorldBuilder.CITY_VIA_RING_PIER_EVERY) == 0
				if has_pier:
					ring_sched += 1
			if has_pier:
				pier_total += 1
				if _w._city_via_lot_top(t.origin.x, t.origin.z) > 0.0:
					pier_in_bld += 1
		print("  十字主线段 %d   环线段 %d" % [cross_seg, ring_seg])
		print("  ── 桥面 ∩ 楼体：**两个口径并排**（同一份场景，同一个数不该差这么多）──")
		print("     · 旧口径（**轴对齐包围盒**相交）= %d / %d = %.1f%%（单段最多 %d 栋）"
			% [hit_seg, deck_n, 100.0 * float(hit_seg) / float(deck_n), hit_max])
		print("     · **精确口径**（真实四角 XZ 的 SAT ＋ y 区间）= **%d / %d = %.1f%%**"
			% [hit_exact, deck_n, 100.0 * float(hit_exact) / float(deck_n)])
		if hit_exact > 0:
			print("       （单段最多撞 %d 栋；**最小重叠深度 %.1f m**；其中 > 120 m 的段 %d 个）"
				% [hit_exact_max, min_depth, deep_exact])
		else:
			print("       ⇒ 旧口径那些全是**旋转板的 AABB 膨胀**造出来的假阳性"
				+ "（420×2 414 转 45° ⇒ AABB 变 2 004×2 004）")
		print("  环线**计划**墩位 %d（`CITY_VIA_RING_PIER_EVERY = %d`）"
			% [ring_sched, WorldBuilder.CITY_VIA_RING_PIER_EVERY])
		print("  ⚠️ **计划墩位（段中点）落进楼体占地的 = %d / %d**（判据 = 建城侧的"
			% [pier_in_bld, pier_total]
			+ " `_city_via_lot_top()`；旧算法遇此**丢墩** ⇒ 实建 %d 根）" % piers.size())
		var keys: Array = yaw_hist.keys()
		keys.sort()
		var parts: Array[String] = []
		for k: int in keys:
			parts.append("%d°×%d" % [k, yaw_hist[k]])
		print("  桥面偏航角直方图（量化 5°）：%s" % "  ".join(parts))

	get_tree().quit(0)


## 逐条格线统计：缺了哪几段、缺口多长、缺口处是水还是地。
## == 路网覆盖：**与实现无关**的口径（2026-09-28 重写）==
##
## ⚠️⚠️ 原来的写法是"逐条格线 × 逐格看那一格有没有路面段"。它在 B1 之后**失效**了：
## B1 把路面从"逐格小段"改成 `_append_road_span()` 的**一条跨段长盒**
## ⇒ "一格"这个单位在建出来的几何里**不存在**了，而旧探针仍按格去数 ——
## 读数长成"实有 1564 段 = 58.7%""缺 1 段 × 86 处"，
## 而 1564 其实约等于**段数**（1600）、不是格数：**整套百分比是在量一个幻觉**。
## （这正是"探针是第二份真源"的典型 —— 它复刻了旧实现的结构。）
##
## ## 新口径：**区间覆盖**（只问"这条线上被铺装盖住了多长"）
## 对每条格线：把落在它上面的所有路面盒的 `[起, 止]` 投影到线轴上 →
## **排序后合并**成若干覆盖区间 → 与"这条线上**应该**有路的区间"做差集 = 缺口。
## 每条盒的**线号**与**长度**都从变换里读（`basis.z` 的朝向定轴线、`scale.z` 是长度）
## ⇒ 既不依赖"一格"这种实现细节，也不依赖任何节点命名。
##
## ## "应该有路"的区间怎么定
## = 该线**在半径门 `CITY_ROAD_R` 之内**的那一段（C4 的门是 `x² + z² < R²`）
## ⇒ 线上应当有路的部分就是 `t ∈ [−√(R²−line²), +√(R²−line²)]`。
## 门**由常量读**、不写死 ⇒ 门一改，这里的判据跟着改。
##
## ## 判据（"道路在地上**断断续续**"的机械表达）
## | 量 | 期望 |
## |---|---|
## | **陆上缺口** | **0** —— 水上的缺口是设计（海湾 / 运河 / 外海） |
## | **一条陆上缺口都没有的格线** | 越多越好；逐缺口按中点判 `city_is_dry()` 分类 |
## **按 run 对账**：把"干区"当**整体**看，问"这条干区有没有被铺满"。
## == 路网口径的第三版，也是最该看的那一版（2026-09-28 · B6）==
##
## ## 为什么前两版都不够
## | 口径 | 问的问题 | 错在哪 |
## |---|---|---|
## | ① 逐格（第一版） | "这一格有没有路面盒" | B1 之后一格可能出**好几段**盒 ⇒ 分母是幻觉 |
## | ② 区间覆盖（第二版） | "两段路之间空了多少" | 缺口里的"干"采样点可能是**格边界上的孤立干点**（`100000001`）⇒ 把水里的一格读成"干区占比 ≥ 50%"的**假缺口** |
## ⇒ 两版的共同病根：**都在按格 / 按缝看，而建城侧的错恰恰是"按格看"**。
##
## ## 这一版
## 逐条格线**跨格**取**极大连续干燥 run**（同相位、同步长，与建城侧同一个 `_city_road_ok`）
## → 每个 run 里数"有多少个采样点被路面盖住"。**干区被当整体**，于是
## "一条干区被格边界切成两片、两片各自过不了 `MIN_SPAN`"这件事**必然显形**。
##
## ## 覆盖从哪来（**不读 MultiMesh**）
## `WorldBuilder._city_dry_spans` —— 建城侧每出一段路面就记一条
## `{axis, gi, line, w, t0, t1}`。它是**数组** ⇒ **headless 下照样准确**
##（对比 MultiMesh：headless 全是单位变换）。所以本节可以 `--headless` 跑，秒级。
func _run_audit(cb: float, half: int) -> void:
	var min_span: float = WorldBuilder.CITY_ROAD_MIN_SPAN
	var ns: int = WorldBuilder.CITY_ROAD_SAMPLES
	var st: float = cb / float(ns - 1)
	var tot := (half * 2) * (ns - 1) + 1
	# ---- 落盘区间 → 按 (axis, gi) 分组合并 ----
	var by_line := {}
	for e: Dictionary in _w._city_dry_spans:
		var key := "%d_%d" % [int(e["axis"]), int(e["gi"])]
		if not by_line.has(key):
			by_line[key] = []
		(by_line[key] as Array).append([float(e["t0"]), float(e["t1"])])
	var run_all := 0
	var run_keep := 0
	var run_dry := 0.0
	var miss_n := 0
	var miss_len := 0.0
	var hole_n := 0
	var hole_len := 0.0
	var hole_worst: Array = []
	var short_n := 0
	var short_len := 0.0
	var short_worst: Array = []
	var worst: Array = []
	for axis in 2:
		for gi in range(-half, half + 1):
			var line := float(gi) * cb
			var iv: Array = by_line.get("%d_%d" % [axis, gi], [])
			iv.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
			var merged: Array = []
			for e2: Array in iv:
				if merged.is_empty():
					merged.append([float(e2[0]), float(e2[1])])
					continue
				var last: Array = merged[merged.size() - 1]
				if float(e2[0]) <= float(last[1]) + 1.0:
					last[1] = maxf(float(last[1]), float(e2[1]))
				else:
					merged.append([float(e2[0]), float(e2[1])])
			var dry := PackedByteArray()
			dry.resize(tot)
			for k in tot:
				var tt := -float(half) * cb + st * float(k)
				dry[k] = 1 if _w._city_road_ok(
					line if axis == 0 else tt, tt if axis == 0 else line) else 0
			var k2 := 0
			while k2 < tot:
				if dry[k2] == 0:
					k2 += 1
					continue
				var ke := k2
				while ke + 1 < tot and dry[ke + 1] == 1:
					ke += 1
				var m := ke - k2 + 1
				var span := float(m - 1) * st
				run_all += 1
				if span >= min_span:
					run_keep += 1
					run_dry += span
					var cov_col: Array = []
					for j in range(k2, ke + 1):
						var tj := -float(half) * cb + st * float(j)
						var hit := false
						for iv4: Array in merged:
							if tj >= float(iv4[0]) - 0.5 and tj <= float(iv4[1]) + 0.5:
								hit = true
								break
						cov_col.append(hit)
					var cov_n := 0
					for c8: bool in cov_col:
						if c8:
							cov_n += 1
					if cov_n < m:
						var lost := float(m - cov_n) * st
						miss_n += 1
						miss_len += lost
						worst.append([lost, axis, gi, float(k2), float(ke),
							cov_n, m, span])
					# ---- **精确口径**：一个"做对的实现"对这条 run 只会在**两端各少盖
					#      1 个采样点**（首末点落在 `inset` 外 —— 路不该伸进水里），
					#      即应覆盖 `m − 2` 个点。**少一个都是缺陷**（= 跨格被切碎后
					#      某一片没过 `MIN_SPAN` 而被丢掉）。
					#      这一条不另设阈值：`inset` 与 `MIN_SPAN` 都是建城侧的符号，
					#      而"2 个点"是采样步长与 `inset ≤ 230 m < 503 m` 的直接推论。
					if m > 2:
						var ideal := m - 2
						if cov_n < ideal:
							short_n += 1
							short_len += float(ideal - cov_n) * st
							short_worst.append([float(ideal - cov_n) * st, axis, gi,
								float(k2), float(ke), cov_n, m, span])
					# 附带：内部是否存在"连续未盖 ≥ MIN_SPAN"的洞（更严格的一问）
					if m > 3:
						var h0 := -1
						for j2 in range(1, m - 1):
							if not cov_col[j2]:
								if h0 < 0:
									h0 = j2
								continue
							if h0 >= 0:
								var hl := float(j2 - h0) * st
								if hl >= min_span:
									hole_n += 1
									hole_len += hl
									hole_worst.append([hl, axis, gi,
										-float(half) * cb + st * float(k2 + h0),
										-float(half) * cb + st * float(k2 + j2 - 1)])
								h0 = -1
						if h0 >= 0:
							var hl2 := float((m - 2) - h0) * st
							if hl2 >= min_span:
								hole_n += 1
								hole_len += hl2
								hole_worst.append([hl2, axis, gi,
									-float(half) * cb + st * float(k2 + h0),
									-float(half) * cb + st * float(k2 + m - 2)])
				k2 = ke + 1
	worst.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	hole_worst.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	short_worst.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	print("")
	print("==== 2b · 路网：**按 run 对账**（只用建城侧自己的账 `_city_dry_spans`，可 headless）====")
	print("  极大连续干燥 run 共 **%d 条**（其中 ≥ %.0f m 的 **%d 条** = 该铺的路段）"
		% [run_all, min_span, run_keep] + "，干区总长 %.0f m" % run_dry)
	print("  · 毛漏铺（含**两端本该收掉的 `inset`**）= %d 条 / %.0f m（%.2f%%）—— **这个数不能当结论**"
		% [miss_n, miss_len, 100.0 * miss_len / maxf(run_dry, 1.0)]
		+ "：每条 run 两端各有一点落在 `inset` 里，205 条 × 1 006 m ≈ 20.6 万 m，"
		+ "实测正好就是 20.5 万 m ⇒ **毛数几乎全部来自设计内的收口**。")
	print("  ⚠️ **精确口径：理想实现应覆盖 `m − 2` 个点（两端各 1 点落在 `inset` 外），"
		+ "少一个都是缺陷 ⇒ 短缺 run = %d 条 / %.0f m**" % [short_n, short_len])
	if short_worst.is_empty():
		print("     ⇒ **0 处**：干区被铺满了。")
	else:
		print("     最重的 8 条（短缺 / 轴 / 格线 / 干区起止 / 实际盖住 / 总点数 / 干区长度）：")
		for i in mini(8, short_worst.size()):
			var s: Array = short_worst[i]
			print("    %7.0f m  轴 %d · gi = %+d · %9.0f…%9.0f · %d/%d 点 · 干区 %.0f m"
				% [float(s[0]), int(s[1]), int(s[2]),
					-float(half) * cb + st * float(s[3]),
					-float(half) * cb + st * float(s[4]),
					int(s[5]), int(s[6]), float(s[7])])
	print("  · 附加（更严的一问）：内部连续未盖 ≥ %.0f m 的洞 = **%d 处 / %.0f m**"
		% [min_span, hole_n, hole_len])
	print("  最重的 4 条 run（毛漏 / 轴 / 格线 / 干区起止 / 盖住点数 / 干区长度）：")
	for i in mini(4, worst.size()):
		var w: Array = worst[i]
		print("    %7.0f m  轴 %d · gi = %+d · %9.0f…%9.0f · %d/%d 点 · 干区 %.0f m"
			% [float(w[0]), int(w[1]), int(w[2]),
				-float(half) * cb + st * float(w[3]),
				-float(half) * cb + st * float(w[4]),
				int(w[5]), int(w[6]), float(w[7])])


func _road_report(mm: MultiMeshInstance3D, cb: float, hill_in: float) -> void:
	var gate: float = WorldBuilder.CITY_ROAD_R
	var half: int = WorldBuilder.CITY_GRID / 2
	# "axis_gi" → 覆盖区间表 [[起, 止], …]（米，沿线轴）
	var cov := {}
	var beyond_hill := 0
	var beyond_ring := 0
	var r_min := 1.0e18
	var r_max := 0.0
	for i in mm.multimesh.instance_count:
		var t := mm.multimesh.get_instance_transform(i)
		var sc := t.basis.get_scale()
		var bz := t.basis.z
		# 局部 +Z 是**长度方向**：它指向世界 X ⇒ 这条线沿 X 走（箱子的线号看 z）
		var axis := 1 if absf(bz.x) > absf(bz.z) else 0
		var line := t.origin.x if axis == 0 else t.origin.z
		var ctr := t.origin.z if axis == 0 else t.origin.x
		var gi := roundi(line / cb)
		var key := "%d_%d" % [axis, gi]
		if not cov.has(key):
			cov[key] = []
		(cov[key] as Array).append([ctr - sc.z * 0.5, ctr + sc.z * 0.5])
		var rr := sqrt(t.origin.x * t.origin.x + t.origin.z * t.origin.z)
		r_min = minf(r_min, rr)
		r_max = maxf(r_max, rr)
		if rr > hill_in:
			beyond_hill += 1
		if rr > WorldBuilder.CITY_HILL_OUT:
			beyond_ring += 1
	var seg_total: int = mm.multimesh.instance_count
	var lines_total := 0
	var lines_no_land_gap := 0
	var land_gaps: Array = []
	var water_gaps := 0
	var water_len := 0.0
	var land_len := 0.0
	var ghist := {}
	for axis in 2:
		for gi in range(-half, half + 1):
			lines_total += 1
			var line := float(gi) * cb
			var gi_line := float(gi) * cb
			var iv: Array = cov.get("%d_%d" % [axis, gi], [])
			iv.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
			var merged: Array = []
			for e: Array in iv:
				if merged.is_empty():
					merged.append([float(e[0]), float(e[1])])
					continue
				var last: Array = merged[merged.size() - 1]
				if float(e[0]) <= float(last[1]) + 1.0:
					last[1] = maxf(float(last[1]), float(e[1]))
				else:
					merged.append([float(e[0]), float(e[1])])
			# ---- **只取内部缺口**：两侧都铺着路、中间空一段 ----
			#
			# ⚠️⚠️ 这一步是判据的关键，第一版写错过：那时拿"该线**穿过半径门**的整段"
			# 当"应该有路"，于是把"**城外本来就没有路**"也算成缺口 ——
			# 读数长成"陆上缺口 1386 处 / 2 773 km"，最长的"缺口" **133 km**，
			# 而那些根本不是洞，是"那里不是城"。**判据的分母错了，数就全错了。**
			# ⇒ 正确的问法是：**两段路之间有没有空档**（外部空档不算）。
			var gaps: Array = []
			for k in range(1, merged.size()):
				# ⚠️ `var a := merged[k-1]` 推不出类型（Array 元素是 Variant）
				# ⇒ 必须显式标注（GDScript 的老坑：`:=` + Variant = Parse Error）。
				var a: Array = merged[k - 1]
				var b: Array = merged[k]
				gaps.append([float(a[1]), float(b[0])])
			var has_defect := false
			for g: Array in gaps:
				var gl := float(g[1]) - float(g[0])
				var mid := (float(g[0]) + float(g[1])) * 0.5
				var px := gi_line if axis == 0 else mid
				var pz := mid if axis == 0 else gi_line
				# ---- ⚠️⚠️ 判"该不该有路"**必须用建城侧同一套判据** ----
				#
				# 第一版这里只问"缺口中点干不干"—— **错的**，而且错得很像对的：
				# 岸线（正弦）上一条 **300 m 宽**的干地，中点当然是干的，
				# 但 `CITY_ROAD_MIN_SPAN`（1 006 m）说它**太短、本来就不该铺**。
				# 只问中点 ⇒ 把整条海岸线读成"1287 处陆上缺口、2497 km"，
				# 而**那次最长的"缺口"定点诊断打出来是 `000000001` / `110000000`**
				# —— 干点只占 1/9、2/9，全是岸线细条。
				# ⇒ 正确问法：缺口里**存在一段够长、够干、在门内**的地吗？
				# （用 `_city_road_ok()` 与 `CITY_ROAD_MIN_SPAN` **两个建城侧的符号**，
				#   所以判据只有一份，探针没有引入第二份真源。）
				var ns: int = WorldBuilder.CITY_ROAD_SAMPLES
				var st: float = cb / float(ns - 1)
				# ---- ⚠️⚠️ 2026-09-28（B6-0）：**采样必须与建城侧同相位、且不许越界** ----
				#
				# 原来是从**缺口起点**起算（`tt = g0 + st·si`）⇒ 与建城侧错开一个
				# 不足一格的相位。而建城侧的采样点恒落在 `n·st` 上（`cb / st = 8`
				# **整好整除** ⇒ 连格边界都是网格点）。相位一错，同一片**正弦海岸**
				# 在两侧读出的干/湿**可以完全不同** ⇒ `dry_len` 只在"缺口正好落在
				# 网格上"时才可信。
				#
				# 更糟的是 `steps = ceil(gl/st) + 1` ⇒ **多采最多一格**，而那些多出来的点
				# 落在缺口**外面**（= 邻格那块有路的干地）⇒ 被计入 `dry_len`。
				# 两条叠加：最长那处"真缺口"的定点诊断打出来是 `000000001`
				#（**干点只 1/9**），却因为越界采样 + 相位错开被算成"干区占比 ≥ 50%"。
				# ⇒ 起止**取整到网格**、只采缺口内的点；再补一个**缺口中点**
				#（缺口短于一格时网格点可能一个都落不进去 ⇒ 没有中点就会**漏掉短缝**）。
				var k0 := int(ceil(float(g[0]) / st - 1.0e-4))
				var k1 := int(floor(float(g[1]) / st + 1.0e-4))
				var dry_n := 0
				var dry_len := 0.0
				var mid_g := (float(g[0]) + float(g[1])) * 0.5
				for kk in range(k0, k1 + 1):
					var tt := st * float(kk)
					var okp: bool = _w._city_road_ok(
						gi_line if axis == 0 else tt, tt if axis == 0 else gi_line)
					if okp:
						dry_n += 1
						dry_len += st
				if k1 < k0:
					# 缺口比一个采样步还短 ⇒ 网格点上没有代表点，用中点代表整条缝
					var okm: bool = _w._city_road_ok(
						gi_line if axis == 0 else mid_g, mid_g if axis == 0 else gi_line)
					if okm:
						dry_len = gl
				# ---- 判"这是不是一处**该有路却没有**的缺口 ----
				#
				# 判据只有一条：**缺口里大部分是陆地，却空着**（干区占比 ≥ 50%）。
				# 一条判据同时覆盖四种情形，而且四种都能自证：
				# | 情形 | 缺口长 | 干区占比 | 判定 |
				# |---|---|---|---|
				# | **接口缝**（相邻两格各自收了 `inset`） | 110…460 m | ≈100% | **缺陷** ✓ |
				# | **整格丢失**（那一格全湿 / 被 MIN_SPAN 丢掉） | ≈4 025 m | ≈100% | **缺陷** ✓ |
				# | 岸线细条（正弦海岸上一条 300 m 干地） | 4 000+ m | ≈11% | 设计如此 ✓ |
				# | 洋面上一座 1 km 小岛 | 100 000+ m | ≈0.8% | 设计如此 ✓ |
				#
				# ⚠️ 我在这条判据上**改了两轮**，两轮都是"数看着像结论"的错：
				#   第一轮用"缺口中点干不干" ⇒ 把整条海岸线读成 1 287 处 / 2 497 km；
				#   第二轮用"缺口里**存在** ≥ `CITY_ROAD_MIN_SPAN` 的干地"
				#     ⇒ 133 km 的洋面只要有 1 km 干地就中招（点诊断显示那格 0/9 干）。
				#   两轮的共同病根：**判据在问"有没有"，而这题要问"是不是主要成分"。**
				var defect := gl >= 10.0 and dry_len * 2.0 >= gl
				# 细分档：**缝**（<100 m，多半是两块路面接头的量测差）
				# / 小洞 / 一格宽（≈4 km，"缺一格"那种）/ 更大的洞
				var bucket := 0
				if gl < 100.0:
					bucket = 0
				elif gl < 1000.0:
					bucket = 1
				elif gl < 3000.0:
					bucket = 2
				elif gl < 6000.0:
					bucket = 3
				else:
					bucket = 4
				if defect:
					ghist[bucket] = int(ghist.get(bucket, 0)) + 1
					land_gaps.append([gl, axis, gi, mid, px, pz, dry_len])
					land_len += gl
					has_defect = true
				else:
					water_gaps += 1
					water_len += gl
			if not has_defect:
				lines_no_land_gap += 1
	var bk: Array = ghist.keys()
	bk.sort()
	var bp: Array[String] = []
	for k: int in bk:
		bp.append("%s × %d 处" % [_bucket_name(k), ghist[k]])
	print("  格线 %d 条（每轴 %d 条）【**区间覆盖**口径】"
		% [lines_total, half * 2 + 1])
	print("  路面盒 %d 个；到图心距离 %.0f … %.0f m（门 CITY_ROAD_R = %.0f m）"
		% [seg_total, r_min, r_max, gate])
	print("  ⚠️ **一条陆上缺口都没有的格线 = %d / %d = %.1f%%**" % [
		lines_no_land_gap, lines_total,
		100.0 * float(lines_no_land_gap) / float(lines_total)])
	print("  ⚠️ **真缺口（缺口内有 ≥ %.0f m 的连续可铺地）= %d 处，合计 %.0f m**"
		% [WorldBuilder.CITY_ROAD_MIN_SPAN, land_gaps.size(), land_len])
	print("  设计如此的空档（内部最长可铺段 < %.0f m：岸线细条 / 水面 / 运河）= %d 处，合计 %.0f m"
		% [WorldBuilder.CITY_ROAD_MIN_SPAN, water_gaps, water_len])
	print("  缺口长度分布（只统计**真缺口**）：%s" % "   ".join(bp))
	land_gaps.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	print("  最长的 10 处真缺口（长度 / 轴 / gi / 中点 / 缺口内最长可铺段）：")
	for i in mini(10, land_gaps.size()):
		var g: Array = land_gaps[i]
		print("    %8.0f m  轴 %d · gi = %+d · (%.0f, %.0f)  可铺 %.0f m"
			% [float(g[0]), int(g[1]), int(g[2]), float(g[4]), float(g[5]),
				float(g[6]) if g.size() > 6 else 0.0])
	# ---- 定点诊断：最长真缺口所在那一格 + 左右两格的 **9 点采样模式** ----
	#
	# 目的：区分两种完全不同的写法错（读数一模一样）：
	#   · 采样点本身不全干 ⇒ 那一段本来就不该铺（只是中点恰好干）；
	#   · 9 点全干、却**没有路面盒** ⇒ C1 的"出段"逻辑漏了（真 bug）。
	# 逐格打印 `ok` 的 9 位二进制（`1` = `_city_road_ok` 为真）。
	if not land_gaps.is_empty():
		var g0: Array = land_gaps[0]
		var ax0: int = int(g0[1])
		var gi0: int = int(g0[2])
		var line0 := float(gi0) * cb
		var mid0 := float(g0[3])
		var gk0 := int(floor(mid0 / cb))
		var n0: int = WorldBuilder.CITY_ROAD_SAMPLES
		var st0: float = cb / float(n0 - 1)
		print("  ⚠️ 最长缺口定点诊断：轴 %d · gi = %+d（线 %.0f）· 缺口 %.0f…%.0f"
			% [ax0, gi0, line0, mid0 - float(g0[0]) * 0.5, mid0 + float(g0[0]) * 0.5])
		for dgk in range(gk0 - 1, gk0 + 2):
			var ta := float(dgk) * cb
			var pat := ""
			var ndry := 0
			for kk in n0:
				var tt := ta + st0 * float(kk)
				var okk: bool = _w._city_road_ok(
					line0 if ax0 == 0 else tt, tt if ax0 == 0 else line0)
				pat += "1" if okk else "0"
				if okk:
					ndry += 1
			print("      格 gk = %+d（t %.0f…%.0f）采样 %s  干 %d/9"
				% [dgk, ta, ta + cb, pat, ndry])
	print("  ⚠️ 路面盒落在 `CITY_HILL_IN`(%.0f m) 之外的 = **%d / %d = %.1f%%**"
		% [hill_in, beyond_hill, seg_total,
			100.0 * float(beyond_hill) / float(seg_total)])
	print("  ⚠️ 其中在环带外缘 `CITY_HILL_OUT`(%.0f m) 之外的 = %d 个"
		% [WorldBuilder.CITY_HILL_OUT, beyond_ring])


## 内部缺口的**长度分档**名字。第 0 档（<100 m）多半是**两块路面接头**的量测差
##（相邻路面盒之间的亚像素缝 / 6 m 搭接被 pitch 投影吃掉），不是"洞"；
## 第 3 档（3…6 km）正好是**一格宽**（4 025 m），也就是"**缺一格**"。
func _bucket_name(k: int) -> String:
	match k:
		0:
			return "< 100 m（缝）"
		1:
			return "0.1…1 km"
		2:
			return "1…3 km"
		3:
			return "3…6 km（≈缺一格）"
	return "> 6 km"


static func _quad_hit(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	return _quad_depth(a, b) > 0.0


## 两个凸多边形（这里都是矩形/四边形）的 **SAT 最小重叠深度**（米）。
## 返回 ≤ 0 表示**不相交**（值是间隙的负数，未做精确计算，只保证符号正确）。
##
## ## ⚠️⚠️ 为什么不能拿 AABB 判（2026-09-28 · B6-0）
## 桥面是**旋转的板**：420 m 宽 × 2 414 m 长，环线上转 45° ⇒ 它的**轴对齐包围盒**
## 变成 2 004 × 2 004（膨胀 **4.8 倍**面积）⇒ 与附近楼体的 AABB 相交是**必然**，
## 但那 4 个角上根本没有桥面。实测"桥面 ∩ 楼体 AABB = 16/139"里
## **大部分是这么来的假阳性**。墩同理（120×600 转 79° ⇒ AABB 612×235）。
## ⇒ 一律用**真实四角 + SAT**；AABB 只许当"粗筛"。
static func _quad_depth(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var best := 1.0e18
	for poly: PackedVector2Array in [a, b]:
		var m := poly.size()
		for i in m:
			var e := poly[(i + 1) % m] - poly[i]
			var axis := Vector2(-e.y, e.x)
			var la := axis.length()
			if la < 1.0e-6:
				continue
			axis /= la
			var a0 := 1.0e18
			var a1 := -1.0e18
			for p: Vector2 in a:
				var pa := axis.dot(p)
				a0 = minf(a0, pa)
				a1 = maxf(a1, pa)
			var b0 := 1.0e18
			var b1 := -1.0e18
			for p2: Vector2 in b:
				var pb := axis.dot(p2)
				b0 = minf(b0, pb)
				b1 = maxf(b1, pb)
			var ov := minf(a1, b1) - maxf(a0, b0)
			if ov <= 0.0:
				return -1.0
			best = minf(best, ov)
	return best


## 一个**旋转盒子**（`xf` × `unit`）的 **XZ 四角**（真变换，不是轴对齐包围盒）。
static func _box_quad(xf: Transform3D, unit: AABB) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 4:
		var p := Vector3(
			unit.position.x + unit.size.x * float(i & 1),
			unit.position.y,
			unit.position.z + unit.size.z * float((i >> 1) & 1))
		var q := xf * p
		out.append(Vector2(q.x, q.z))
	return out


## 一个**旋转盒子**的 y 区间（真变换；带俯仰角时两端不等高）。
static func _box_yspan(xf: Transform3D, unit: AABB) -> Vector2:
	var lo := 1.0e18
	var hi := -1.0e18
	for i in 4:
		var p := Vector3(
			unit.position.x + unit.size.x * float(i & 1),
			unit.position.y + unit.size.y * float((i >> 1) & 1),
			unit.position.z + unit.size.z * float(((i >> 1) & 1)))
		var q := xf * p
		lo = minf(lo, q.y)
		hi = maxf(hi, q.y)
	return Vector2(lo, hi)


## 一个**轴对齐盒子**的 XZ 四角。
static func _aabb_quad(ab: AABB) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(ab.position.x, ab.position.z),
		Vector2(ab.position.x + ab.size.x, ab.position.z),
		Vector2(ab.position.x + ab.size.x, ab.position.z + ab.size.z),
		Vector2(ab.position.x, ab.position.z + ab.size.z),
	])


func _box_aabb(xf: Transform3D, unit: AABB) -> AABB:
	var mn := Vector3(1.0e18, 1.0e18, 1.0e18)
	var mx := Vector3(-1.0e18, -1.0e18, -1.0e18)
	for i in 8:
		var p := unit.position + Vector3(
			unit.size.x * float(i & 1),
			unit.size.y * float((i >> 1) & 1),
			unit.size.z * float((i >> 2) & 1))
		var q := xf * p
		mn = mn.min(q)
		mx = mx.max(q)
	return AABB(mn, mx - mn)
