extends Node
## **B6-0 定点诊断**：把某条格线的"9 点采样模式"与"建城侧实际落盘的干燥区间"
## （`WorldBuilder._city_dry_spans`）并排打出来。
##
## ## 为什么必须这么做（而不是继续读 MultiMesh 覆盖）
## `_r6_road_probe` 走的是"从场景里把路面盒读回来"的口径 —— 它**必须带窗口**
##（headless 下 `get_instance_transform()` 全回单位变换），而且路面盒要经过
## "合并区间"这一步 ⇒ 看到的只是"哪里被盖住了"，**看不到"为什么"**。
## 而 `_city_dry_spans` 是**建城侧自己写的账**：每出一条路面就记一条
## `{axis, gi, line, w, t0, t1}` —— 它是**数组**，headless 下照样读得到（不用渲染器）。
## ⇒ 本探针对"某条线上到底出了哪几段"这个问题是**决定性**的，而且秒级。
##
## ## 顺便回答的问题
## `_city_road_ok()` 在**格边界点**（`t = k·4025`）上给出 `true` 而格内部是 `false`
## —— 看上去像"水里的孤岛"，但那不可能（岸线连续）。所以这里把
## `gx / gz / city_is_land()` / `city_is_dry()` / `_city_landform()` **全打出来**，
## 一眼就能看出干湿判据到底是不是**按格**的。
##
##   godot --headless --path <工程> res://tools/_b6_road_cell_probe.tscn
##   godot --headless --path <工程> res://tools/_b6_road_cell_probe.tscn -- --city=davao

var _w: WorldBuilder
var _map: MapDef
var LAY := MapDef.CityLayout.OENBELLI


func _ready() -> void:
	var city := "oenb"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--city="):
			city = a.substr(7)
	_map = MapDef.davao() if city == "davao" else MapDef.oenbelli()
	LAY = MapDef.CityLayout.DAVAO if city == "davao" else MapDef.CityLayout.OENBELLI
	_w = WorldBuilder.new()
	add_child(_w)
	await get_tree().physics_frame
	_w.apply_map(_map)
	await get_tree().physics_frame

	var cb: float = WorldBuilder.ARENA_RADIUS / float(WorldBuilder.CITY_GRID)
	var half: int = WorldBuilder.CITY_GRID / 2
	var ns: int = WorldBuilder.CITY_ROAD_SAMPLES
	var st: float = cb / float(ns - 1)
	print("==== B6 定点诊断 · %s ====" % _map.name_cn)
	print("  格距 %.3f m  一格 %d 个采样点（步长 %.3f m，`cb/step = %.4f` ⇒ %s）"
		% [cb, ns, st, cb / st,
			"**整好整除 ⇒ 格边界也是采样点**"
				if absf(cb / st - float(ns - 1)) < 1.0e-6 else "**不整除**"])
	print("  `_city_dry_spans` 共 %d 条（建城侧自己的账）" % _w._city_dry_spans.size())

	# ---- 1 · 落盘区间按 (axis, gi) 分组，找"最可疑"的那条线 ----
	# 可疑 = 这条线上**有 ≥ 3 个连续干的采样点却没出路面**的格最多。
	var by_line := {}
	for e: Dictionary in _w._city_dry_spans:
		var key := "%d_%d" % [int(e["axis"]), int(e["gi"])]
		if not by_line.has(key):
			by_line[key] = []
		(by_line[key] as Array).append([float(e["t0"]), float(e["t1"]), float(e["w"])])

	var worst: Array = []
	for axis in 2:
		for gi in range(-half, half + 1):
			var line := float(gi) * cb
			var key2 := "%d_%d" % [axis, gi]
			var spans: Array = by_line.get(key2, [])
			var naked := 0
			var naked_run := 0
			var worst_run := 0
			for gk in range(-half, half):
				var ta := float(gk) * cb
				for kk in ns:
					var tt := ta + st * float(kk)
					var okk: bool = _w._city_road_ok(
						line if axis == 0 else tt, tt if axis == 0 else line)
					if okk:
						naked += 1
						naked_run += 1
						worst_run = maxi(worst_run, naked_run)
					else:
						naked_run = 0
			# 排除全干的线（那种线本该全铺满）
			var covered := 0.0
			for s: Array in spans:
				covered += float(s[1]) - float(s[0])
			var dry_len := 0.0
			for gk2 in range(-half, half):
				var ta2 := float(gk2) * cb
				for kk2 in range(1, ns):
					var ok2: bool = _w._city_road_ok(
						line if axis == 0 else ta2 + st * float(kk2),
						(ta2 + st * float(kk2)) if axis == 0 else line)
					if ok2:
						dry_len += st
			if dry_len > 0.0 and covered < dry_len * 0.5:
				worst.append([dry_len - covered, axis, gi, dry_len, covered,
					worst_run, spans.size()])
	worst.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	print("")
	print("==== 1 · 最可疑的 6 条线（干区长度 − 实铺长度 最大）====")
	for i in mini(6, worst.size()):
		var w: Array = worst[i]
		print("  线(轴 %d, gi = %+d)：干区 %.0f m / 实铺 %.0f m / 差 %.0f m / "
			% [int(w[1]), int(w[2]), float(w[3]), float(w[4]), float(w[0])]
			+ "最长连续干 %d 点 / %d 段路面" % [int(w[5]), int(w[6])])

	if worst.is_empty():
		print("  ⇒ 空：没有「干区一大片却没铺」的线")
		get_tree().quit(0)
		return

	# ---- 2 · 把第一名那条线逐格摊开 ----
	var ax: int = int(worst[0][1])
	var gi0: int = int(worst[0][2])
	var line0 := float(gi0) * cb
	print("")
	print("==== 2 · 逐格摊开：轴 %d · gi = %+d（线 %.0f m）====" % [ax, gi0, line0])
	var spans0: Array = by_line.get("%d_%d" % [ax, gi0], [])
	spans0.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	print("  建城侧落盘的 %d 段路面：" % spans0.size())
	for s: Array in spans0:
		print("    进 %9.1f … %9.1f（长 %8.1f m，宽 %.0f）"
			% [float(s[0]), float(s[1]), float(s[1]) - float(s[0]), float(s[2])])
	print("  逐格 9 点采样（`1` = `_city_road_ok` 真；右侧给该格内的落盘段数）：")
	for gk in range(-half, half):
		var ta := float(gk) * cb
		var pat := ""
		var n_in := 0
		for s2: Array in spans0:
			if float(s2[1]) > ta + 1.0 and float(s2[0]) < ta + cb - 1.0:
				n_in += 1
		for kk in ns:
			var tt := ta + st * float(kk)
			var okk: bool = _w._city_road_ok(
				line0 if ax == 0 else tt, tt if ax == 0 else line0)
			pat += "1" if okk else "0"
		if pat.contains("1") or n_in > 0:
			print("    gk = %+3d（t %9.0f…%9.0f）  %s   落盘 %d 段"
				% [gk, ta, ta + cb, pat, n_in])


	get_tree().quit(0)
