extends RefCounted
## 批 10（2026-09-22）：读条系统。
##
## 用户需求："做读条系统，辅助游戏加载，在进入战斗地图之前进入读条。"
##
## 四组断言：
##   1. **读条界面本体**（LoadingScreen）：初始隐藏 → open 显示 → advance 后
##      进度条向目标缓动（在动、且不超过目标）→ finish 后收起；
##   2. **分阶段建图**（WorldBuilder.apply_map_staged）：进度信号单调递增到 1.0，
##      且建出来的世界与同步版 `apply_map()` **结构一致**（同一套阶段函数）；
##   3. **玩家真实入口**（_begin_match_loading 协程）：菜单信号确实接到了读条路径，
##      走完整流程后玩家/敌机就位、阶段 FIGHT、读条自己收起；
##      顺带回归守卫同步入口的配置解析（训练强制靶场）；
##   4. **铺满与尺寸**（`_geometry`，2026-10-01 轮 61 补）：读条层挂进 CanvasLayer 后
##      size == 视口可见区域、源码里没有硬编码画布尺寸。
##      ⚠️ 这一节存在的原因：本 bug（读条底部露出 100 px）**复发过两次**
##      （2026-09-22 设计文档已逐字定位、从未落盘；2026-10-01 用户肉眼发现）——
##      旧的三节 33 条**全是流程、一条几何都没有**，所以它能一路绿到用户看见。
##
## ⚠️ 本套件含协程：SUITES 表里 async 标志必须是 true，且 run 里必须显式 await
## （批 8 的教训：漏了的话断言一条都不会执行，还无声无息）。

static func run(t: T, host: Node) -> void:
	await _loading_screen(t, host)
	await _staged_map(t, host)
	await _match_flow(t, host)
	await _geometry(t, host)


## ① 读条界面本体。
static func _loading_screen(t: T, host: Node) -> void:
	t.suite("Loading / 读条界面本体")
	var ls := LoadingScreen.new()
	ls.name = "LoadingProbe"
	host.add_child(ls)
	await host.get_tree().process_frame
	t.not_ok(ls.is_showing(), "初始隐藏（不该有凭空出现的读条）")
	ls.open("测试地图 · 夜")
	t.ok(ls.is_showing(), "open() 后显示")
	t.near(ls.shown_progress(), 0.0, 0.02, "初始进度为 0")
	ls.advance(0.5, "半程……")
	for i in 6:
		await host.get_tree().process_frame
	var mid := ls.shown_progress()
	t.gt(mid, 0.03, "进度条在向目标推进（%.2f）—— 不是死图" % mid)
	t.ok(mid <= 0.51, "显示值不超过目标（缓动而不是跳变）")
	ls.advance(1.0, "收尾")
	# finish() 会等条走满 + 最短显示时间 + 淡出 —— 全部完成才算过
	await ls.finish()
	t.near(ls.shown_progress(), 1.0, 0.01, "finish() 后条走满")
	t.not_ok(ls.is_showing(), "finish() 后读条自己收起（淡出结束）")
	ls.free()
	await host.get_tree().process_frame


## ② 分阶段建图：进度信号 + 与同步版结构一致。
static func _staged_map(t: T, host: Node) -> void:
	t.suite("Loading / 分阶段建图（apply_map_staged）")
	var root := Node3D.new()
	root.name = "StagedMapProbe"
	host.add_child(root)
	var w := WorldBuilder.new()
	root.add_child(w)
	await host.get_tree().process_frame
	# w._ready() 已经按 initial_map 同步建了太平洋 —— 换艾尔斯岩走分阶段
	var fracs: Array[float] = []
	var labels: Array[String] = []
	w.build_stage.connect(func(f: float, s: String) -> void:
		fracs.append(f)
		labels.append(s))
	await w.apply_map_staged(MapDef.uluru())
	t.eq(w.map.id, MapDef.Id.ULURU, "staged 后 map 已登记为艾尔斯岩")
	t.ok(fracs.size() >= 4, "进度信号 ≥ 4 条（四阶段）")
	var mono := true
	for i in range(1, fracs.size()):
		if fracs[i] < fracs[i - 1]:
			mono = false
	t.ok(mono, "进度单调递增（%s）" % [fracs])
	t.near(fracs[fracs.size() - 1], 1.0, 0.001, "最后一条进度到 1.0")
	t.ok(labels[labels.size() - 1] != "", "进度带阶段文字")
	t.ok(w._terrain_root.get_child_count() > 0, "staged 建出了地表")
	t.ok(w._cloud_root.get_child_count() > 0, "staged 建出了云层")
	t.ok(w.time_of_day != null, "staged 应用了时段")
	# ---- 结构等价：同一张图，同步版建出来的结构必须一模一样 ----
	var w2 := WorldBuilder.new()
	root.add_child(w2)
	await host.get_tree().process_frame
	w2.apply_map(MapDef.uluru())
	t.eq(w._terrain_root.get_child_count(), w2._terrain_root.get_child_count(),
		"staged 与同步版地表节点数一致（共用同一套阶段函数）")
	t.eq(w._cloud_root.get_child_count(), w2._cloud_root.get_child_count(),
		"staged 与同步版云层带数一致")
	t.eq(w.ocean == null, w2.ocean == null, "海面有无一致（沙漠图都没有海面实例）")
	# ---- 幂等回归：沙漠 staged 完再 staged 回太平洋（海面图），旧图必须被清干净 ----
	await w.apply_map_staged(MapDef.pacific())
	t.eq(w.map.id, MapDef.Id.PACIFIC, "再 staged 回太平洋")
	t.ok(w.ocean != null and is_instance_valid(w.ocean), "海面图 staged 后海面就位")
	t.gt(w._terrain_root.get_child_count(), 0, "换回海岛图地表重建")
	root.free()
	await host.get_tree().process_frame


## ③ 玩家真实入口：菜单信号 → 读条协程 → FIGHT。
static func _match_flow(t: T, host: Node) -> void:
	t.suite("Loading / 开局流程接线")
	var packed := load("res://scenes/main.tscn")
	if not (packed is PackedScene):
		t.ok(false, "main.tscn 能加载为 PackedScene")
		return
	var main := (packed as PackedScene).instantiate()
	host.add_child(main)
	await host.get_tree().process_frame
	await host.get_tree().physics_frame

	# ---- 菜单信号必须接在读条路径上（而不是测试用的同步入口）----
	# ⚠️ main.get() 返回 Variant，链式取到的 start_match / get_connections() 都是无类型
	# —— `var conns := ...` 推不出类型会整文件编译不过（1.2 里"三元与类型推断"同款）。
	var conns: Array = main.get("menu").start_match.get_connections()
	var wired := false
	for c in conns:
		if str(c["callable"].get_method()) == "_begin_match_loading":
			wired = true
	t.ok(wired, "menu.start_match 已接到 _begin_match_loading（读条路径）")
	var loading = main.get("loading")
	t.ok(loading != null and is_instance_valid(loading), "读条层已建出")
	t.not_ok(loading.is_showing(), "主菜单阶段读条隐藏")

	# ---- 配置解析回归（同步纯函数，不建节点）----
	main.call("_resolve_match", SuitProfile.Id.MESSER_M01, Difficulty.Level.NORMAL,
		-1, Game.MatchMode.TRAINING)
	t.eq(Game.active_map.id, MapDef.Id.RANGE, "训练模式强制靶场（门禁仍在）")
	main.call("_resolve_match", SuitProfile.Id.XI, Difficulty.Level.NORMAL)
	t.eq(Game.active_map.id, MapDef.Id.PACIFIC, "对战模式默认太平洋")

	var built_ocean: Array[int] = [0]
	main.world.build_stage.connect(func(frac: float, _label: String) -> void:
		if frac >= 1.0 and is_instance_valid(main.world.ocean): built_ocean[0] = main.world.ocean.get_instance_id())
	# ---- 走真实玩家入口（协程）----
	var retired_unit:=Node3D.new();main.units_root.add_child(retired_unit)
	var retired_projectile:=Node3D.new();main.projectiles.add_child(retired_projectile)
	main.call("_begin_match_loading", SuitProfile.Id.XI, Difficulty.Level.NORMAL)
	await host.get_tree().process_frame
	t.not_ok(is_instance_valid(retired_unit),"next load retires previous units before reading large resources")
	t.not_ok(is_instance_valid(retired_projectile),"next load retires previous projectiles before reading large resources")
	t.ok(loading.is_showing(), "进入读条（协程第一段已执行）")
	# 等协程走完：FIGHT + 读条收起。上限 600 帧防死循环。
	var fought_behind_loading := false
	var waited := 0
	while waited < 600:
		await host.get_tree().process_frame
		waited += 1
		if loading.is_showing() and Game.phase == Game.Phase.FIGHT: fought_behind_loading = true
		if Game.phase == Game.Phase.FIGHT and not loading.is_showing():
			break
	t.eq(main.world.ocean.get_instance_id(),built_ocean[0],"出击直接复用读条已建好的地图，没有第二次重建")
	t.not_ok(fought_behind_loading,"读条淡出完成前不运行战斗")
	t.eq(Game.phase, Game.Phase.FIGHT, "读条流程结束 → FIGHT")
	t.not_ok(loading.is_showing(), "开局后读条已收起")
	t.ok(main.get("player") != null and is_instance_valid(main.get("player")),
		"玩家机已出生（读条路径与同步路径等价）")
	t.ok(main.get("hud").visible, "HUD 已显示")
	t.ok(not main.get("menu").visible, "主菜单已隐藏")
	t.ok(main.get("player").controls_enabled, "玩家可以操控（_start_fight 已跑）")

	main.call("_show_menu")
	main.free()
	await host.get_tree().process_frame

## ④ 铺满与尺寸（2026-10-01 轮 61 补）。
##
## 本 bug 的门 = 「挂进 CanvasLayer 后 size == 视口可见区域」。Control 的布局是**引擎侧**
## 算的 ⇒ 这条判据**无需渲染**，无头一样跑得了，而它恰好一条就能抓住 `set_anchors_preset`
## 那一整类错（size 恒为 0）。
static func _geometry(t: T, host: Node) -> void:
	t.suite("Loading / 铺满与尺寸")
	# 真实场景：读条层挂在 main 的 HUDLayer（CanvasLayer）里，不是挂在普通 Node 下。
	var layer := CanvasLayer.new()
	layer.name = "LoadingGeomProbe"
	host.add_child(layer)
	var ls := LoadingScreen.new()
	layer.add_child(ls)
	await host.get_tree().process_frame

	var vp := host.get_viewport().get_visible_rect().size
	t.gt(vp.x, 0.0, "视口可见宽 > 0（本断言有意义的前提）")
	# ---- 判据 1：铺满 ----
	# 这三条就是本 bug 的门。用 `set_anchors_preset` 时 `ls.size` 恒为 (0,0) ⇒ 全红。
	t.gt(ls.size.x, 0.0, "读条层宽 > 0 —— 不是 (0,0)")
	t.gt(ls.size.y, 0.0, "读条层高 > 0 —— 不是 (0,0)")
	t.near(ls.size.x, vp.x, 0.5, "读条层宽 == 视口宽（铺满）")
	t.near(ls.size.y, vp.y, 0.5, "读条层高 == 视口高（铺满）")
	# offsets 不许被反算成负值 —— 那正是 `set_anchors_preset` 的症状
	# （它把 anchors 设成 0/0/1/1 后反算 offsets 去凑出「当前这个 0×0 的矩形」）。
	t.near(ls.offset_right, 0.0, 0.01, "offset_right == 0（没被反算成负的视口宽）")
	t.near(ls.offset_bottom, 0.0, 0.01, "offset_bottom == 0（没被反算成负的视口高）")
	# ---- 判据 2：源码里不许再有硬编码画布尺寸 ----
	# ⚠️ 只扫**代码部分**：先去掉行内 `#` 之后的东西。因为本节注释与 `loading_screen.gd`
	# 的注释都要写「1600×900」来讲清根因，不剔除的话断言会被自己的注释弄红。
	# ⚠️ 同理，去掉后再找也不能用带中文字符的串比 —— 这里比的是纯 ASCII 数字，安全。
	var src := FileAccess.get_file_as_string("res://scripts/ui/loading_screen.gd")
	t.ok(src != "", "loading_screen.gd 源码读得到（判据 2 的前提）")
	var code := ""
	for raw_line in src.split("\n"):
		code += str(raw_line.split("#")[0]) + "\n"
	t.ok(not code.contains("1600"), "代码里没有硬编码 1600（兜底已改为从父级推）")
	t.ok(not code.contains("900"), "代码里没有硬编码 900")
	# ---- 判据 3：兜底路径的**行为**（判据 2 只是扫文本，这条是正面表述）----
	# 把 size 人为清 0（模拟锚点写法被人改回 `set_anchors_preset`），`_view_size()`
	# 必须仍然给出「铺满视口」的那个矩形 —— 硬编码兜底在这里必红。
	var keep := ls.size
	ls.size = Vector2.ZERO
	var vs := ls._view_size()
	ls.size = keep
	t.near(vs.x, vp.x, 0.5, "size 被清 0 时读条仍按视口宽铺满（兜底不硬编码）")
	t.near(vs.y, vp.y, 0.5, "size 被清 0 时读条仍按视口高铺满")
	# ---- 兜底**源**确实是那个正确的矩形 ----
	var pa := ls.get_parent_area_size()
	t.near(pa.x, vp.x, 0.5, "兜底源的宽 == 视口宽（不是某个常数）")
	t.near(pa.y, vp.y, 0.5, "兜底源的高 == 视口高（不是某个常数）")
	layer.free()
	await host.get_tree().process_frame

