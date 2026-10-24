extends Node
## 验收工具：**四块人工岛 + 出生点搬到丘陵之上**（2026-09-28 那一轮）。
##
## 跑法（**不能加 `--headless`**，headless 是 dummy 渲染器，抓出来全黑）：
##   godot --path <工程> res://tools/_r5_shots.tscn -- <输出目录> [增益]
##
## ## 拍什么
## | # | 机位 | 看什么 |
## |---|---|---|
## | S1 | 西北高空 92 km / 俯角 56°，**天气层关** | **四块人工岛 + 三条块间运河**的总平面 |
## | S2 | 同上压到 34 km | 运河**三条各自的走向**（远图里只是三道缝） |
## | S3 | 出生点侧上方 2.5 km + 探针标注 | 出生点**压在丘陵上**（脚下是山、余量 1 500 m） |
## | S4 | 出生点位置上朝城平视 | 出生点在**城外**的丘陵带里（城在 90 km 外） |
## | S5 | 台场 / 青海之间那条运河低空 | 运河**是可读的水道**：两岸护岸 + 两侧第一排楼 |
## | S6 | 海湾里朝岸斜看（两档） | **岸线是一条干净的线** + 彩虹桥跨在海湾上 |
## | S7 | 海滨公园一带（两档，2026-09-28 改口径） | **旧女神格是空地** + **彩虹桥侧视**（桥已改沿 Z） |
##
## ## ⚠️ 五条自我约束（前两条是**踩过的坑**，不是预防性提醒）
## 1. **总平面必须关掉天气层**（云带 + 体积雾 + 海雾）。第一版在 56 km 高度上
##    拍的是一整张米色，什么都读不出 —— 而要证明的"四块岛 + 三条运河"是**几何**、
##    不是天气。关掉的只有 S1 / S2，**S3 之后一律恢复**（那几张必须是"游戏里的样子"）。
## 2. **机位不能落在市中心楼群里**。第一版 S7 站在 1 200 m 上朝女神看，前景被一栋
##    市中心塔（downtown 档 1 620~2 500 × 1.22 × 噪声 ⇒ 最高 ≈ 3 780 m）整个挡住。
##    ⇒ 凡是要"看过楼群"的机位，一律抬到 **4 600 m** 以上。
## 3. **没有一张正俯视，全部保证有侧面入画** —— 死城的掠射天光下 MultiMesh 的
##    **顶面几乎不受光**，正俯视会拍出一张纯黑（`_park_shots.gd` 那一轮踩过：
##    `err=0`、退出码 0、不报任何错）。总平面取 **俯角 56°**，不是 90°。
## 4. **增益只动存出来的 PNG**（`Image.adjust_bcs`），不动渲染、不动任何判据。
##    奥恩贝利是刻意的"阴天黄昏死城"（全城无一盏灯），实拍整帧亮度在 0.003 量级。
##    增益会打进日志与文件名旁边 —— **比图之前先看增益**。
## 5. **落位一律走 `_city_cell_center()` / `match_spawn_radius()` / `OENB_BLOCKS`**，
##    不抄坐标：抄一遍就是第二份真源，格表一改这里就拍到隔壁去。
##    （唯一写字面量的是**取景偏移** —— 那不是"城市的坐标"，是相机的事。）
##    出生点那个标方块 + 细柱**只在 S3 / S4 存在**（拍完 `queue_free()`）：
##    它是探针自己的标注、不是游戏里的东西，绝不能留在"真实画面"那几张里。

var _cb := 0.0
var out_dir := "user://r5_shots"
var gain := 2.5
var _idx := 0
var _world: WorldBuilder


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		gain = float(args[1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_world = WorldBuilder.new()
	add_child(_world)
	await get_tree().physics_frame
	_world.apply_map(MapDef.oenbelli())
	await _frames(24)
	_cb = WorldBuilder.ARENA_RADIUS / float(WorldBuilder.CITY_GRID)
	print("[r5] out=%s 增益=%.2f 格距=%.1f m" % [out_dir, gain, _cb])

	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 1.0
	cam.far = 900000.0
	add_child(cam)
	cam.current = true

	await _overviews(cam)
	await _spawn_shots(cam)
	await _water_shots(cam)

	print("R5_SHOTS_DONE -> ", out_dir)
	get_tree().quit(0)


# ---------------------------------------------------------------- ① 总平面

## 四块岛：西边**有明**、中间**台场**、东边**青海**、南边**东八潮**，
## 块与块之间各留一格（4 025 m）—— 那三格就是运河。
func _overviews(cam: Camera3D) -> void:
	for row: String in _blocks_table():
		print("      " + row)
	var bb := _blocks_aabb()
	var c := (bb[0] + bb[1]) * 0.5
	print("[r5] 岛群包围盒 x[%.0f, %.0f] z[%.0f, %.0f]，中心 (%.0f, %.0f)"
		% [bb[0].x, bb[1].x, bb[0].z, bb[1].z, c.x, c.z])

	_set_weather(false)
	# S1 的高度 / 俯角是**算出来的**，不是试出来的：
	#   城域 x 跨 124.8 km、z 跨 96.6 km（从块表算）。
	#   垂直 fov 60° ⇒ 水平 fov = 2·atan(tan 30° × 16/9) = **91.5°**。
	#   俯角 56° ⇒ 机位到中心的水平距离 = H / tan 56° = 0.675H，
	#   该处半幅 = 0.675H × tan 45.75° = 0.693H ⇒ 全幅 1.386H ≥ 124.8 ⇒ **H ≥ 90 km**。
	#   深度方向：近缘 86° ⇒ 6.4 km 处、远缘 26° ⇒ 188 km 处（H = 92 km）
	#   —— 中心落在 62 km 处，整簇（±55 km）都在框内 ✓。
	await _look(cam, Vector3(c.x - 43900.0, 92000.0, c.z - 43900.0),
		Vector3(c.x, 0.0, c.z), "S1_overview_plan")
	# S2 中景：**压到某一条运河的正上方** —— 远图里运河只是"三道缝"，
	#   要证明"它就是**一格宽（4 025 m）**、两岸都有楼、两岸都有护岸"，
	#   必须把机位中心放在运河中线上。
	#   取 H = 11 km、俯角 60° ⇒ 机位水平偏移 11 000 / tan 60° = 6 351 m（各轴 4 491）。
	#   斜距 12.7 km ⇒ 全幅 14.7 km（竖）× 26.1 km（横）⇒ 运河占画幅宽 **15%** ✓。
	#   ⚠️ 仍不是正俯视（60°）—— 见文件头第 3 条。
	var cx_e := 7.5 * _cb
	print("[r5] S2 中心放在台场-青海那条运河的中线 x = %.0f（= 7.5 × 格距）" % cx_e)
	await _look(cam, Vector3(cx_e + 4491.0, 11000.0, c.z + 4491.0),
		Vector3(cx_e, 0.0, c.z), "S2_canal_plan")
	_set_weather(true)


# ---------------------------------------------------------------- ② 出生点

## 出生点**按图给**：`match_spawn_radius()`（奥恩贝利 90 000 m）+ `spawn_point()`。
## 丘陵是**径向**环带 82 000 … 96 000 m ⇒ 出生环落在环带中段。
func _spawn_shots(cam: Camera3D) -> void:
	var r: float = _world.match_spawn_radius()
	var sp := _world.spawn_point(-95.0, r, WorldBuilder.PLAYER_START_ALT)
	var g: float = WorldBuilder._city_landform(sp.x, sp.z, MapDef.CityLayout.OENBELLI)
	print("[r5] 出生点 (%.0f, %.1f, %.0f)  半径 %.0f m  脚下地形 %.1f m  余量 %.1f m"
		% [sp.x, sp.y, sp.z, r, g, sp.y - g])
	var marks := _spawn_marker(sp, g)
	# S3 侧上方 2.5 km：读**山脊剖面** —— 标方块落在山脊上、细柱把 1 500 m 的余量画出来。
	#   切向 = (cos(θ+90°), 0, sin(θ+90°))，θ = −95° ⇒ (0.996, 0, −0.087)。
	await _look(cam, sp + Vector3(24000.0, 2500.0, -2100.0),
		sp + Vector3(0.0, -200.0, 0.0), "S3_spawn_on_ridge")
	# S4 站在出生点位置上朝城平视：城在 90 km 外 ⇒ 出生点**在城之外**的丘陵带里。
	await _look(cam, sp + Vector3(0.0, 120.0, 0.0),
		Vector3(0.0, 900.0, sp.z + 90000.0), "S4_spawn_look_city")
	for n: Node3D in marks:
		n.queue_free()
	await _frames(4)


# ---------------------------------------------------------------- ③ 水系与地标

func _water_shots(cam: Camera3D) -> void:
	# 三条运河的**中线**：全部由**块表**算（"两块面对面取中"），**不写格号**。
	# ⚠️ 第一版把三条写成 ±7.5 / −8.5 格，其中**两条是错的**：
	#   台场 gx[−6,6] ↔ 有明 gx[−15,−8] ⇒ 中间那格是 gx = −7 ⇒ 中线 **−6.5 格**
	#    （−7.5 格已经落在**有明岛上**）；
	#   台场 gz[−7,7] ↔ 东八潮 gz[−16,−9] ⇒ 中间那格是 gz = −8 ⇒ 中线 **−7.5 格**
	#    （−8.5 格已经在**东八潮岛上**）。
	# 写错只会让**标注**错（拍到的还是那条运河的 x 线上的东西），但标注错就是证据错。
	var cx_e := _canal_mid(0, 3, true)      # 台场 ↔ 青海（+X 那条）
	var cx_w := _canal_mid(2, 0, true)      # 有明 ↔ 台场（−X 那条）
	var cz_s := _canal_mid(1, 0, false)     # 东八潮 ↔ 台场（−Z 那条）
	print("[r5] 运河中线（由块表算）：东 x = %.0f / 西 x = %.0f / 南向 z = %.0f（格距 %.0f）"
		% [cx_e, cx_w, cz_s, _cb])
	# S5 低空顺**东**那条运河朝海湾（+Z）：两岸护岸 + 两侧第一排楼。
	await _look(cam, Vector3(cx_e, 800.0, cz_s - 6000.0),
		Vector3(cx_e, 0.0, cz_s + 26000.0), "S5_canal_low_along")

	# S6 海湾里朝岸斜看：**岸线是一条干净的线** + 彩虹桥跨在海湾上。
	#   台场最外一排北缘 / 盒 +Z 边都从块表算，岸线（正弦）夹在两者之间。
	var ne := _north_edge()
	print("[r5] 台场最外一排北缘 z = %.0f；`OENB_BOX` +Z 边 = %.0f（正弦岸线夹在两者之间）"
		% [ne, (float(int(WorldBuilder.OENB_BOX[3])) + 1.0) * _cb])
	await _look(cam, Vector3(20000.0, 6000.0, ne + 23000.0),
		Vector3(0.0, 0.0, ne - 6000.0), "S6a_bay_coast")
	await _look(cam, Vector3(30000.0, 1500.0, ne + 18000.0),
		Vector3(6000.0, 500.0, ne - 2000.0), "S6b_bay_coast_low")

	# ---- S7 海滨公园一带（**2026-09-28 已改口径**）----------------------------
	# ⚠️⚠️ 原来的 S7 是「自由女神 + 彩虹大桥同框」；**女神整座已删**（用户 2026-09-28
	#   拍板：那一格 `(-4,6)` **留作空地**），所以这一组现在的判据变了：
	#     S7a 证明"**那一格确实是空地**"（同一格里不许再有像体 / 台座 / 广场雕塑）；
	#     S7b 拍**彩虹桥本体** —— 桥在 R7 v3 已**转 90°（改沿 Z）**，
	#         原来的横拍机位会拍成"顺着桥身看一条线"，等于没拍到桥。
	#   ⚠️ 落位走 `_city_cell_center(-4, 6)` —— 与建城侧**同一个函数**，
	#   不抄格号（文件头第 5 条）。
	var lot := WorldBuilder._city_cell_center(-4, 6)
	var bz: float = WorldBuilder.CITY_BRIDGE_Z
	var bdy: float = WorldBuilder.CITY_BRIDGE_DECK_Y
	var bty: float = WorldBuilder.CITY_BRIDGE_TOWER_Y
	print("[r5] 空地格 (-4,6) 格心 (%.0f, %.0f)；桥沿 **Z** 走、桥心 z = %.0f、桥面 y = %.0f、主塔顶 %.0f"
		% [lot.x, lot.z, bz, bdy, bty])
	#   S7a **空地上方俯看**：机位在**海那一侧**（+Z）朝 −Z 回看，正对那块地。
	#   ⚠️ 高度 4 600 m：低于市中心塔（最高 ≈ 3 780 m）就会拍到"一堵墙"（见文件头第 2 条）。
	await _look(cam, Vector3(lot.x, 4600.0, lot.z + 13000.0),
		Vector3(lot.x, 60.0, lot.z), "S7a_vacant_lot")
	#   S7b **彩虹桥侧视**：桥沿 Z ⇒ 机位必须**横着挪到一侧**（这里站到海湾西侧的
	#   水上空，x ≈ −21 km、z ≈ 40 km，那一片是湾里的水，不是岛），
	#   才能把"主跨 + 双塔 + 斜拉索"看成一座桥，而不是"一条向北消失的线"。
	await _look(cam, Vector3(-21000.0, 2400.0, 40000.0),
		Vector3(0.0, bdy + 400.0, bz), "S7b_rainbow_bridge_side")


# ---------------------------------------------------------------- 机位小工具

## ⚠️ 落位与朝向一律显式给（不用"绕原点转一圈"那类自动机位）：
## 这套图是**判据图**，机位本身要写进交付说明，自动机位没法复现。
func _look(cam: Camera3D, from: Vector3, at: Vector3, shot_name: String) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	await _frames(10)
	await _shot(shot_name)
	print("[r5]   %s 机位 (%.0f, %.0f, %.0f) → 目标 (%.0f, %.0f, %.0f)"
		% [shot_name, from.x, from.y, from.z, at.x, at.y, at.z])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(shot_name: String) -> void:
	_idx += 1
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null or vp.get_texture() == null:
		print("SHOT_FAILED ", shot_name)
		return
	var img := vp.get_texture().get_image()
	if img == null:
		print("SHOT_FAILED(img) ", shot_name)
		return
	if not is_equal_approx(gain, 1.0):
		img.adjust_bcs(gain, 1.0, 1.0)
	var p := out_dir.path_join("%02d_%s.png" % [_idx, shot_name])
	print("SHOT %s err=%d gain=%.2f" % [p, img.save_png(p), gain])


## 天气层（云带 / 体积雾 / 海雾）开关。**只给 S1 / S2 关**（见文件头第 1 条）。
##
## ⚠️ 三个都要关：`fog_enabled` 只是距离雾，`volumetric_fog_enabled` 是那一遍 pass，
## `_sea_mist` 是贴海那条 `FogVolume` —— 漏掉任一个，高空俯视都还是糊的。
func _set_weather(on: bool) -> void:
	if _world._cloud_root != null:
		_world._cloud_root.visible = on
	if _world._sea_mist != null:
		_world._sea_mist.visible = on
	if _world._env != null:
		_world._env.fog_enabled = on
		_world._env.volumetric_fog_enabled = on
	print("[r5] 天气层（云 / 体积雾 / 海雾）= %s" % ("开" if on else "**关**（总平面判据图）"))


## 出生点标注：**顶上一个方块 + 一根从地面长上来的细柱**。
## ⚠️ 只有方块的话它在画面上"浮"在离地 1.5 km 的空中 —— 肉眼读不出那是**余量**，
## 只会读成"这个模型悬空了"。细柱把那 1 500 m 画出来。
##
## ⚠️ 它**自发光**，而这是一座"死城不点灯"的图 —— 所以它绝不能留在
## 那几张"真实画面"的图里（文件头第 5 条）。
func _spawn_marker(pos: Vector3, ground_y: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var h := maxf(pos.y - ground_y, 1.0)
	var cm := BoxMesh.new()
	cm.size = Vector3(150.0, h, 150.0)
	var cmi := MeshInstance3D.new()
	cmi.mesh = cm
	cmi.material_override = _marker_mat(0.55)
	add_child(cmi)
	cmi.global_position = Vector3(pos.x, ground_y + h * 0.5, pos.z)
	out.append(cmi)
	var bm := BoxMesh.new()
	bm.size = Vector3(900.0, 900.0, 900.0)
	var bmi := MeshInstance3D.new()
	bmi.mesh = bm
	bmi.material_override = _marker_mat(1.6)
	add_child(bmi)
	bmi.global_position = pos
	out.append(bmi)
	print("[r5] 出生点标注：方块 + 余量柱（高 %.0f m）@ (%.0f, %.0f, %.0f)（**仅探针**，拍完即删）"
		% [h, pos.x, pos.y, pos.z])
	return out


func _marker_mat(energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.22, 0.10)
	m.emission_enabled = true
	m.emission = Color(0.90, 0.14, 0.04)
	m.emission_energy_multiplier = energy
	return m


# ---------------------------------------------------------------- 从块表算几何

func _blocks_table() -> Array[String]:
	var out: Array[String] = []
	for b: Array in WorldBuilder.OENB_BLOCKS:
		out.append("块 格 [%d, %d] × [%d, %d]  ⇒  x [%.0f, %.0f]  z [%.0f, %.0f]"
			% [int(b[0]), int(b[1]), int(b[2]), int(b[3]),
				float(int(b[0])) * _cb, (float(int(b[1])) + 1.0) * _cb,
				float(int(b[2])) * _cb, (float(int(b[3])) + 1.0) * _cb])
	return out


## 两块"面对面"之间那一格的中线（米）。`along_x = true` 取 x（竖运河），否则取 z。
## 下标与 `OENB_BLOCKS` 的顺序一致：0 台场 / 1 东八潮 / 2 有明 / 3 青海。
##
## ⚠️ 由**块表**算而不是在调用处写格号：写死就是第二份真源，块表一挪就错，
## 而且错的方式很阴（读出来是"岛面高度"，看着像"运河没挖"）。
func _canal_mid(ia: int, ib: int, along_x: bool) -> float:
	var a: Array = WorldBuilder.OENB_BLOCKS[ia]
	var b: Array = WorldBuilder.OENB_BLOCKS[ib]
	var ea: float
	var eb: float
	if along_x:
		ea = (float(int(a[1])) + 1.0) * _cb
		eb = float(int(b[0])) * _cb
	else:
		ea = (float(int(a[3])) + 1.0) * _cb
		eb = float(int(b[2])) * _cb
	return (minf(ea, eb) + maxf(ea, eb)) * 0.5


## 四块岛的 AABB（米）：`[min, max]`。
func _blocks_aabb() -> Array[Vector3]:
	var lo := Vector3(1.0e9, 0.0, 1.0e9)
	var hi := Vector3(-1.0e9, 0.0, -1.0e9)
	for b: Array in WorldBuilder.OENB_BLOCKS:
		lo.x = minf(lo.x, float(int(b[0])) * _cb)
		hi.x = maxf(hi.x, (float(int(b[1])) + 1.0) * _cb)
		lo.z = minf(lo.z, float(int(b[2])) * _cb)
		hi.z = maxf(hi.z, (float(int(b[3])) + 1.0) * _cb)
	return [lo, hi]


## 四块岛在 **+Z** 方向的最外缘（米）= 海湾那一侧的岛缘。
## ⚠️ 只用 **+Z**：海湾在 +Z（见 `CITY_BAY_Z` 的注释），±X 与 −Z 的岛缘与岸线无关。
func _north_edge() -> float:
	var m := 0.0
	for b: Array in WorldBuilder.OENB_BLOCKS:
		m = maxf(m, (float(int(b[3])) + 1.0) * _cb)
	return m
