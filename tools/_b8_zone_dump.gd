## 达沃 / 奥恩贝利的**街廓划分**导出器（2026-09-28 深夜 · 用户 "A. 你先划分"）。
##
## ## 它解决什么
## 用户要的是"**哪个格子是大格、哪个格子是小格**"，并且"大格地块面积比小格大得多"。
## 那件事在**渲染图**上很难读（楼一多就成一片），必须给一张**划分图** ——
## 一格一块的矩形，标上大 / 小与边长。本工具导出那张图要用的原始数据。
##
## ## ⚠️⚠️ 它**不自己判**"谁是大格"
## 逐格调 `WorldBuilder.city_block_plan()` —— 与 `_build_city_blocks()` **同一份**判定。
## 在这里重写一遍判定是**最危险**的做法：分岔之后画出来的划分图与真正建出来的城
## 对不上，而**看图完全看不出来**（只能逐格对账）。
##
## ## 输出（`<输出目录>/zones.csv`）
## `gx,gz,ok,anchor,gx0,used,big,n,nx,nz,fill,edge,edge_z,cx,cz,tower_lo,tower_hi`
##   · `ok=0` → 这一格不建城（岛外 / 水 / 广场 / 公园 / 绿地 / 地标）
##   · `anchor=1` → 这一行是**一块地**（`ok=1, anchor=0` 的行是"被主角盖住"的格子）
##   · `edge / edge_z` = 块的 x / z 边长（米）；`cx / cz` = 块心世界坐标
##   · `tower_lo / tower_hi` = 该块最粗的塔的宽度区间（按子地块占地比 × 塔身倍率算）
##
## ## 跑法（**数据工具，可以 `--headless`**）
##   godot --headless --path <工程> res://tools/_b8_zone_dump.tscn -- <输出目录> [oenb|davao]
##
## ## 交叉核对（**必须做，否则等于没验**）
## 把终端里 `[city] xxx：N 个街廓（大 A / 小 B）` 与末行 `== 街廓 N（大 A / 小 B）`
## 对一遍 —— 两个数不一致就说明 `city_block_plan()` 与 `_build_city_blocks()` 已经分岔。
extends Node

const TOWER_LO := 0.30   # `_city_block_at()` 里塔身占子地块的比例下限
const TOWER_HI := 0.46   # …上限（与那条"塔恒在裙房内"的不等式同源）

var world: WorldBuilder


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://b8_zone"
	var city: String = args[1] if args.size() > 1 else "davao"
	DirAccess.make_dir_recursive_absolute(out_dir)
	world = WorldBuilder.new()
	add_child(world)
	await get_tree().physics_frame
	world.apply_map(MapDef.oenbelli() if city == "oenb" else MapDef.davao())
	await get_tree().physics_frame

	var mp: MapDef = world.map
	var half: int = WorldBuilder.CITY_GRID / 2
	var rows := PackedStringArray()
	rows.append("gx,gz,ok,anchor,gx0,used,big,n,nx,nz,fill,edge,edge_z,cx,cz,tower_lo,tower_hi")
	var n_block := 0
	var n_big := 0
	var n_small := 0
	var area_big := 0.0
	var area_small := 0.0
	# ---- ① 逐格导出（这是给划分图用的主表）----
	for gx in range(-half, half):
		for gz in range(-half, half):
			var p: Dictionary = world.city_block_plan(gx, gz)
			if not bool(p["ok"]):
				rows.append("%d,%d,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0" % [gx, gz])
				continue
			var g: Dictionary = p["grade"]
			var anchor := bool(p["anchor"])
			var e: float = p["edge"]
			var ez: float = p["edge_z"]
			var cy: Vector3 = p["pos"]
			var sub := float(g["fill"]) * WorldBuilder.CITY_SUB_FILL_HI
			if anchor:
				n_block += 1
				if bool(p["big"]):
					n_big += 1
					area_big += e * ez
				else:
					n_small += 1
					area_small += e * ez
			rows.append("%d,%d,1,%d,%d,%d,%d,%d,%d,%d,%.4f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f"
				% [gx, gz, 1 if anchor else 0, int(p["gx0"]), int(p["used"]),
					1 if bool(p["big"]) else 0, int(g["n"]), int(g["nx"]), int(g["nz"]),
					float(g["fill"]), e, ez, cy.x, cy.z,
					sub * TOWER_LO * mp.city_tower_w,
					sub * TOWER_HI * mp.city_tower_w])
	# ---- 「内部支路被吃」的自查（= `suite_round20` 那条哨兵的**同一份**读数）----
	#
	# ⚠️ 这一遍**刻意照抄 `_build_city_street_infra()` 的循环范围**
	#（`for gi in range(-half, half + 1)`，37 条格线，**含 +half**）——
	# 只有这样打出来的数才该与游戏日志里 `内部街：… 吃掉 N 截支路` **逐字相等**。
	# 若这里也写 36（像上面建块那一遍），会少 1 截，看着像"分岔了"，其实只是范围差一格。
	var sent_on := 0
	var sent_big_split := 0
	var sent_small := 0
	var bad := 0
	var span_dv: int = maxi(1, mp.city_block_span_x)
	for gi in range(-half, half + 1):
		for g in range(-half, half + 1):
			var on: bool = world._city_road_inner_suppressed(0, gi, g)
			if on:
				sent_on += 1
				# 反向：只有"组首格是大格且合并成功"才许吃
				var gx0 := gi - 1
				var okbig := posmod(gx0, span_dv) == 0
				if okbig:
					var pp: Dictionary = world.city_block_plan(gx0, g)
					okbig = bool(pp["ok"]) and bool(pp["big"]) and bool(pp["merged"])
				if not okbig:
					bad += 1
					var _p: Dictionary = world.city_block_plan(gx0, g)
					print("!! 反向违例 (gi=%d, gz=%d)：组首格 %d → ok=%s big=%s merged=%s ／ 内部线宽 %.0f m"
						% [gi, g, gx0, str(_p.get("ok")), str(_p.get("big")),
							str(_p.get("merged")), WorldBuilder.city_road_width(gi)])
			elif world._city_road_inner_suppressed(1, gi, g):
				bad += 1
	for gi in range(-half, half + 1):
		for g in range(-half, half + 1):
			if posmod(gi - 1, span_dv) != 0:
				continue
			var pp2: Dictionary = world.city_block_plan(gi - 1, g)
			if not bool(pp2["ok"]):
				continue
			if bool(pp2["big"]):
				if not bool(pp2["merged"]):
					sent_big_split += 1
			else:
				sent_small += 1
	var path := out_dir.path_join("zones.csv")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(rows) + "\n")
	f.close()
	print("== 划分导出 %s → %s" % [mp.name_cn, path])
	print("== 街廓 %d（大 %d / 小 %d）｜大格地均 %.2f km² ／ 小格地均 %.2f km² ⇒ 面积比 **%.1f×**"
		% [n_block, n_big, n_small,
			(area_big / maxf(1.0, float(n_big))) / 1.0e6,
			(area_small / maxf(1.0, float(n_small))) / 1.0e6,
			(area_big / maxf(1.0, float(n_big))) / maxf(1.0, area_small / maxf(1.0, float(n_small)))])
	print("== span_x = %d ／ 大格栋数 %s ／ 小格栋数 %s ／ 街区 %.0f m"
		% [mp.city_block_span_x, str(mp.city_block_big_n), str(mp.city_block_small_n),
			float(WorldBuilder.CITY_CBLOCK)])
	print(("== 内部支路：吃掉 **%d** 截（**未加「路面干燥」门**；游戏日志那个数过了一遍"
		+ " `_city_road_ok` 的连续干燥 run，所以只会 ≤ 这个数）｜反向违例 %d（必须为 0）"
		+ "｜大格未合并（内部是干道）%d 组 ／ 小格 %d 组（这两类**不许**吃）")
		% [sent_on, bad, sent_big_split, sent_small])
	get_tree().quit()
