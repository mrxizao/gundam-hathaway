class_name SuiteRound
extends RefCounted
## 回合集成测试：真的把主场景 main.tscn 实例化起来，
## 验证"世界能建出来、主菜单能选、双方能出生、流程能从菜单走到 FIGHT"。
## 这一套是为了挡住"某个子系统的改动让整个游戏起不来"这类问题。


static func run(t: T, host: Node) -> void:
	t.suite("Round / 主场景与菜单装配")
	await _assemble(t, host)
	t.suite("Round / 地图：三张图都能搭起来")
	await _maps(t, host)
	t.suite("Round / 训练模式：靶场 + 四架靶机")
	await _training(t, host)
	t.suite("Round / 1.2 敌人选择")
	await _enemy_choice(t, host)
	t.suite("Round / 1.2 剧情挑战：波次与上方入场")
	await _challenge(t, host)
	t.suite("Round / 1.2 菜单步数（挑战保留难度页）")
	_menu_steps(t)
	t.suite("Round / 1.2 菜单：轴、方向与版式一致")
	_menu_axis(t)
	t.suite("Round / 1.2 柯西巡航变形与联机编码")
	await _morph_and_net(t, host)


static func _assemble(t: T, host: Node) -> void:
	var packed := load("res://scenes/main.tscn")
	if not (packed is PackedScene):
		t.ok(false, "main.tscn 能加载为 PackedScene")
		return
	t.ok(true, "main.tscn 能加载为 PackedScene")

	var main := (packed as PackedScene).instantiate()
	host.add_child(main)
	await host.get_tree().process_frame
	await host.get_tree().physics_frame

	var world: Node = main.get("world")
	var menu = main.get("menu")
	var hud = main.get("hud")
	var speed_lines = main.get("speed_lines")
	var chase = main.get("chase")

	t.ok(world != null and is_instance_valid(world), "世界（天空/海面/云/岛屿）已建出")
	t.ok(menu != null and is_instance_valid(menu), "主菜单已建出")
	t.ok(hud != null and is_instance_valid(hud), "HUD 已建出")
	t.ok(speed_lines != null and is_instance_valid(speed_lines), "速度线图层已建出")
	t.ok(chase != null and is_instance_valid(chase), "追尾镜头已建出")
	t.eq(Game.phase, Game.Phase.MENU, "开局停在主菜单阶段")
	t.ok(main.get("player") == null, "主菜单阶段还没有玩家机")
	t.ok(menu.visible, "主菜单可见")
	t.ok(not hud.visible, "战斗 HUD 在主菜单阶段隐藏")

	# ---- 走一次完整的菜单选择：柯西高达 + 困难（第四轮起固定夜战）----
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.HARD)
	await host.get_tree().process_frame
	await host.get_tree().physics_frame

	var player = main.get("player")
	var enemy = main.get("enemy")
	var p_lock = main.get("player_lock")
	var e_lock = main.get("enemy_lock")

	t.ok(player != null and is_instance_valid(player), "玩家机已出生")
	t.ok(enemy != null and is_instance_valid(enemy), "敌机已出生")
	t.ok(p_lock != null and is_instance_valid(p_lock), "玩家锁定系统已建出")
	t.ok(e_lock != null and is_instance_valid(e_lock), "敌机锁定系统已建出")
	t.ok(not menu.visible, "开局后主菜单隐藏")
	t.ok(hud.visible, "开局后 HUD 显示")

	# ---- 机体与难度的接线 ----
	t.eq(player.profile.id, SuitProfile.Id.XI, "玩家开的是柯西高达")
	t.eq(enemy.profile.id, SuitProfile.Id.PENELOPE, "敌机自动换成另一台（佩涅罗佩）")
	t.ok(Game.active_difficulty != null, "难度已写入 Game")
	if Game.active_difficulty != null:
		t.eq(Game.active_difficulty.level, Difficulty.Level.HARD, "难度是困难")

	# ---- 时段：现在是夜战专用，开局必须自动落到夜晚 ----
	t.ok(Game.active_time_of_day != null, "时段已写入 Game")
	if Game.active_time_of_day != null:
		t.eq(Game.active_time_of_day.preset, TimeOfDay.Preset.NIGHT, "固定夜战")
	t.ok(world.time_of_day != null, "世界拿到了时段")
	if world.time_of_day != null:
		t.eq(world.time_of_day.preset, TimeOfDay.Preset.NIGHT, "世界当前时段是夜晚")
		t.near(world.sun.light_energy, Game.active_time_of_day.sun_energy, 0.001,
			"主光强度按夜晚预设落地")
		t.lt(world.sun.light_energy, 0.6, "夜晚主光确实被压暗了（但没压到看不清机体）")
		# 天空 shader 的星星数量也必须是夜晚那一档，否则只是"变暗"而不是"入夜"
		if world.get("_sky_mat") is ShaderMaterial:
			var star = (world.get("_sky_mat") as ShaderMaterial).get_shader_parameter("star_amount")
			t.gt(float(star), 0.5, "夜空 shader 打开了星星")

	# ---- 地图尺寸与云量：这一轮放大的两个量 ----
	# ⚠️ 第十九轮 26 km → **28 km**；第二十二轮 28 km → **64.4 km（×2.3，用户要求
	# "所有的地图范围都太小了，扩大 2-3 倍"）**；
	# **2026-09-27 达沃重制 64.4 km → 144.9 km（×2.25）**。
	# ⚠️ 144 900 = `CITY_GRID`(36) × 格距(4025) —— 这三个数是一条链，
	# 改一个必须看另外两个（`suite_worldscale` 里钉着"格距仍是 4025"）。
	# 这个数与 `WorldBuilder.SPAWN_RADIUS` 是一对，`suite_round19` 守着
	# "出击点 × 极速 × 槽时长"的不等式。
	t.near(world.ARENA_RADIUS, 144900.0, 0.1,
		"竞技场半径 144.9 km（2026-09-27 达沃重制：地图 ×2.25）")
	t.near(BanditAI.ARENA_RADIUS, world.ARENA_RADIUS, 0.1, "AI 的边界和世界用同一个常量")
	# ---- 第二十二轮：地表必须**比竞技场大得多**，否则飞到边缘会看见"地表的边" ----
	# 这是 `ARENA_RADIUS` 的连带项里最容易漏的一条：地图放大而地表没跟，
	# 玩家在竞技场边缘就会看到一张纯色平面（等于"世界到头了"）。
	t.gt(WorldBuilder.OCEAN_SIZE, WorldBuilder.ARENA_RADIUS * 4.0,
		"海面（%.0f km）远大于竞技场直径（%.0f km）"
			% [WorldBuilder.OCEAN_SIZE / 1000.0, WorldBuilder.ARENA_RADIUS * 2.0 / 1000.0])
	t.gt(WorldBuilder.LAND_SIZE, WorldBuilder.ARENA_RADIUS * 4.0,
		"陆地远景地坪（%.0f km）同上" % (WorldBuilder.LAND_SIZE / 1000.0))
	# ---- ⚠️ 口径改（2026-09-27）：地表细分网格该跟谁比 ----
	#
	# 原来的判据是 `> ARENA_RADIUS × 1.5`，它的**本意**是"地表细分网格要盖住
	# **需要地形的地方**"。但 `ARENA_RADIUS` 在达沃那张图上已经**不代表**
	# "需要地形的地方"了 —— 半径 144.9 km 里有 65 km 是**外海**（水面不需要细分地形）。
	#
	# ⇒ 改成与**城域**比：取 `CITY_SHAPE` 里南北跨度最大的那座城（达沃）。
	# 不改口径就得把它抬到 217 km 以上，顶点代价从 ×4 涨到 ×5.2。
	var city_span := 0.0
	var cb := WorldBuilder.ARENA_RADIUS / float(WorldBuilder.CITY_GRID)
	for p: Dictionary in WorldBuilder.CITY_SHAPE:
		city_span = maxf(city_span, 2.0 * (float(p.cz) + float(p.rz)) * cb)
	t.gt(WorldBuilder.TERRAIN_DETAIL_SIZE, city_span,
		"地表细分网格（%.1f km）盖住最大那座城（%.1f km，不然城外就没有地形）"
			% [WorldBuilder.TERRAIN_DETAIL_SIZE / 1000.0, city_span / 1000.0])
	# 云在 `_cloud_root` 底下（1.2：云量按地图配置，换图时整层重建，
	# 所以云不再是 world 的直接子节点 —— 这里必须跟着改，否则会数到 0 个）。
	var cloud_instances := 0
	var cloud_root: Node = world.get("_cloud_root")
	if cloud_root != null:
		for c: Node in cloud_root.get_children():
			var mm := c as MultiMeshInstance3D
			if mm != null and mm.multimesh != null:
				cloud_instances += mm.multimesh.instance_count
	t.gt(cloud_instances, 1800, "云层实例数超过 1800（实得 %d）" % cloud_instances)

	# ---- 2026-09-21：**3500 m 以下不生成云**（老板定的硬地面）----
	#
	# 逐实例量"这一盘的**最低点**" = 中心 − 盘在世界竖直方向上的半高。
	# ⚠️ 量外沿而不是团心：只把 `y_min` 抬上去的话，团心在 3.5 km 的团
	# 底边照样垂到 2.5 km（盘半径按千米算）—— "看着改了其实没改"必须被这条抓住。
	# 盘的半高 = 变换的缩放 y ÷ 2（公告板绕世界 Y 转，世界竖直跨度恒等于缩放后的 y）。
	#
	# ⚠️⚠️ **必须量 `cloud_bands`（CPU 侧真源），不能量 MultiMesh**：
	# 无头模式的 dummy 渲染器不保留 MultiMesh 的实例数据，
	# `get_instance_transform()` 会**全部返回单位变换** —— 在那上面量会得到
	# "5464 个实例全部违规、最低 −0.5 m"的**假红**（2026-09-21 实测踩过一次）。
	var floor_violations := 0
	var lowest := INF
	var band_total := 0
	var bands: Array = world.get("cloud_bands")
	for band: Array in bands:
		for tr: Transform3D in band:
			band_total += 1
			var bottom := tr.origin.y - tr.basis.get_scale().y * 0.5
			lowest = minf(lowest, bottom)
			if bottom < WorldBuilder.CLOUD_FLOOR - 0.01:
				floor_violations += 1
	t.gt(band_total, 1800, "三带一共留下 %d 个盘（和 MultiMesh 的实例数对得上）" % band_total)
	t.eq(floor_violations, 0, "没有一盘伸到 %.0f m 以下（最低 %.1f m）"
		% [WorldBuilder.CLOUD_FLOOR, lowest])
	t.gt(lowest, WorldBuilder.CLOUD_FLOOR - 1.0,
		"最低那盘是**贴着**硬地面，而不是穿过去（实得 %.1f m）" % lowest)
	t.near(player.fm.max_speed, SuitProfile.xi().player_top_speed(), 0.5,
		"玩家（柯西）巡航上限 = 机体表（2026-09-22 速度上调后不再等于基准）")
	t.near(player.fm.ab_speed, SuitProfile.xi().player_boost_speed(), 0.5,
		"玩家（柯西）加速上限 = 机体表")
	# 敌机是"另一台机"，所以它的上限要乘**它自己**的速度系数。
	# 第六轮起佩涅罗佩的速度系数 > 1，直接写死 630 就不对了。
	#
	# ⚠️ **第十四轮改写了这一条**（旧断言："困难敌机上限 = 柯西基准 ×1.5 × 速度系数"）。
	#
	# 旧断言把"敌机比玩家加力还快"当成契约钉死了，而它正是玩家实测的那条反馈：
	# 中等难度敌机开佩涅罗佩是 737 m/s，玩家开默认的柯西把加力按死只有 630 m/s
	# —— 追尾在数学上不可能（"感觉很难追上敌机"）。所以契约本身改了：
	# **难度倍率与环境不变，但在它之上压一道"玩家加力上限 ×0.92"的天花板**
	# （`SuitProfile.enemy_top_speed_capped`）。
	#
	# 于是这里断言的是新的完整契约，两条都要在：
	#   ① 敌机仍然比玩家的**巡航**上限快 —— 玩家必须用加力才追得上，难度感还在；
	#   ② 敌机绝不超过玩家的**加力**上限 —— 否则就是"怎么追都追不上"。
	var foe_prof = enemy.profile
	t.gt(foe_prof.speed_scale, 1.0, "本轮的敌机是佩涅罗佩（速度系数 > 1）")
	t.near(enemy.fm.max_speed,
		foe_prof.enemy_top_speed_capped(Difficulty.make(Difficulty.Level.HARD).speed_mult,
			player.profile.player_boost_speed()), 0.5,
		"困难敌机上限 = 带天花板的难度表（原始难度值被玩家加力上限钳住）")
	t.gt(enemy.fm.max_speed, player.fm.max_speed,
		"困难敌机仍比玩家（柯西）**巡航**上限快：必须用加力才追得上")
	t.lt(enemy.fm.max_speed,
		player.fm.ab_speed * SuitProfile.ENEMY_SPEED_CEILING_RATIO + 0.5,
		"困难敌机不超过玩家加力上限 ×0.92：这条不变量就是『追得上』的回归门")
	# ⚠️ 1.2 第二十八轮：不再是固定的 1.3 —— 还要乘上**玩家所选机体**的
	# 困难强化系数（"困难柯西"与"困难佩涅罗佩"必须是两种难度）。
	t.near(enemy.damage_mult, 1.3 * player.profile.hard_enemy_reinforce, 0.001,
		"困难敌机出伤倍率 = 1.3 × 玩家的困难强化系数（%.2f）"
			% (1.3 * player.profile.hard_enemy_reinforce))

	# ---- 真模型确实挂上去了 ----
	t.ok(player.rig != null, "玩家机挂着槽位骨架（提供炮口/喷口锚点）")
	if player.rig != null:
		t.gt(player.rig.slot_names().size(), 50, "槽位数量正常")
		t.not_ok(player.rig.placeholder_visible(), "真模型到位后占位体块已隐藏")
	t.near(player.model_bounds.size.y, player.profile.target_height, 2.5,
		"玩家机包围盒高度 = 该机体的设定全高")
	t.near(enemy.model_bounds.size.y, enemy.profile.target_height, 2.5,
		"敌机包围盒高度 = 该机体的设定全高")
	t.eq(player.team, 0, "玩家队伍为 0")
	t.eq(enemy.team, 1, "敌机队伍为 1")
	t.ok(player.is_hostile_to(enemy), "玩家与敌机互为敌对")
	t.ok(player.projectile_container != null, "玩家机拿到了弹丸容器")

	# ---- 流程推进（1.2：**没有 INTRO**，开局直接就是 FIGHT）----
	# 用户要求删掉"每次游戏开始时候的按空格开始游戏"，所以断言跟着反过来：
	# 以前是"INTRO 不接受操作、按了确认才给操作权"，现在是"一开局就有操作权"。
	t.eq(Game.phase, Game.Phase.FIGHT, "开局直接进入 FIGHT（不再等'按空格出击'）")
	t.ok(player.controls_enabled, "开局就拿到操作权（不再等一个按键）")
	# `_start_fight()` 现在**必须幂等**：测试与探针里有好几处仍会显式调它
	# （它们当年是为了"跳过 INTRO"）。不幂等就会重起 BGM、多记一条事件。
	main.call("_start_fight")
	await host.get_tree().process_frame
	t.eq(Game.phase, Game.Phase.FIGHT, "重复调 _start_fight() 不会把阶段弄坏")
	t.ok(player.controls_enabled, "重复调用之后操作权仍在")

	# ---- 敌机 AI 会主动接近 ----
	var d0: float = player.global_position.distance_to(enemy.global_position)
	for i in 240:
		await host.get_tree().physics_frame
	var d1: float = player.global_position.distance_to(enemy.global_position)
	t.lt(d1, d0, "敌机 AI 在 4 秒内缩短了与玩家的距离（%.0f → %.0f m）" % [d0, d1])
	t.ok(enemy.alive and player.alive, "4 秒内双方都还活着")

	# ---- 端到端：真的发一个按键事件，看机头有没有抬起来 ----
	# 这一条把「键位 → InputMap → PlayerController → FlightModel」整条链路串起来验了
	var y0: float = player.forward().y
	await _key(host, KEY_S, true)
	for i in 45:
		await host.get_tree().physics_frame
	var y1: float = player.forward().y
	t.gt(y1, y0 + 0.05, "按住 S 后机头抬起（forward.y %.3f → %.3f）" % [y0, y1])
	await _key(host, KEY_S, false)

	# ---- 玩家阵亡后结算画面不能秒没 ----
	await _lose_result_persists(t, host, main)

	# ---- 结算之后必须能干净地回主菜单并再开一局 ----
	await _result_flow(t, host, main)

	# ---- 结算画面两栏必须严格对齐 ----
	_result_alignment(t)

	main.free()
	await host.get_tree().process_frame
	Game.reset()


## 结算画面"对齐"的回归测试。
##
## 用户报过"对齐一下结算菜单 ui"，但对齐这种事靠肉眼看截图是说不清的 ——
## 所以几何被抽成了纯函数 `FlightHUD.result_layout()`，这里直接断言它的性质。
static func _result_alignment(t: T) -> void:
	var view := Vector2(1600, 900)
	var geo := FlightHUD.result_layout(view)
	var boxes: Array = geo["boxes"]
	t.eq(boxes.size(), 2, "结算画面是两栏")

	var l: Rect2 = boxes[0]
	var r: Rect2 = boxes[1]
	t.near(l.position.y, r.position.y, 0.001, "左右两栏框顶严格齐平")
	t.near(l.size.y, r.size.y, 0.001, "左右两栏框高完全一致（所以框底也齐平）")
	t.near(l.size.x, r.size.x, 0.001, "左右两栏宽度一致")
	t.gt(r.position.x, l.position.x + l.size.x, "两栏之间留有空隙，没有叠在一起")

	# 整块水平居中
	var left_edge := l.position.x
	var right_edge := r.position.x + r.size.x
	t.near((left_edge + right_edge) * 0.5, view.x * 0.5, 0.5, "两栏整体水平居中")
	t.near(view.x * 0.5 - left_edge, right_edge - view.x * 0.5, 0.5, "左右留白对称")

	# 整块垂直居中（标题在上、提示在下）
	var hint_y: float = geo["hint_y"]
	t.lt(float(geo["title_y"]), l.position.y, "标题在两栏之上")
	t.gt(hint_y, l.position.y + l.size.y, "底部提示在两栏之下")
	var top_gap := float(geo["title_y"])
	var bottom_gap := view.y - hint_y
	t.near(top_gap, bottom_gap, 30.0,
		"上下留白大致相等（上 %.0f / 下 %.0f）—— 「顶部挤、底部空一大片」不再出现"
		% [top_gap, bottom_gap])
	t.gt(hint_y, 0.0, "底部提示没有被推出屏幕")
	t.lt(hint_y, view.y, "底部提示在屏幕内")

	# 换个窗口比例也要成立（玩家可能把窗口拉成非 16:9）
	for v: Vector2 in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(1600, 1000)]:
		var g2 := FlightHUD.result_layout(v)
		var b2: Array = g2["boxes"]
		t.near((b2[0] as Rect2).position.y, (b2[1] as Rect2).position.y, 0.001,
			"%s 下两栏依然齐平" % v)
		t.lt(float(g2["hint_y"]), v.y, "%s 下底部提示仍在屏幕内" % v)


## 回归测试：用户实测"结算画面秒没，而且**只有玩家操控的机体死亡时才出现**"。
##
## 线索就是那句"只有玩家死才秒没"。根因：玩家阵亡后残骸会在 **2.2 秒**后 `queue_free`，
## 而 `FlightHUD._draw()` 开头是
## ```
## if player == null or not is_instance_valid(player): return
## ```
## 玩家对象一被释放，**整个 HUD 连同结算画面都不再绘制** —— 看起来就是秒没。
## 敌机阵亡时玩家还在，所以同一个结算流程看不出问题。
##
## 修法：结算要显示的数据在**阶段开始那一刻快照**下来（`HUD.capture_result()`），
## 绘制入口只依赖相机；座舱 HUD 才单独判断玩家。
static func _lose_result_persists(t: T, host: Node, main: Node) -> void:
	var tree := host.get_tree()
	var hud = main.get("hud")
	var player = main.get("player")
	if player == null or not is_instance_valid(player):
		t.ok(false, "这一轮应当有存活的玩家机")
		return

	# 直接把玩家打死（清掉 I 立场，保证伤害落到机体上）
	player.ifield_hp = 0.0
	player.take_damage(999999.0, null, Damage.Type.SABER)
	for i in 30:
		await tree.physics_frame
	t.eq(Game.phase, Game.Phase.LOSE, "自己阵亡 → 战败结算")

	# 快照必须在死亡那一刻就抓好，之后不再依赖 player
	t.gt(hud._result.size(), 0, "阵亡时抓到了结算数据快照")
	t.eq(str(hud._result.get("suit", "")), SuitProfile.xi().display_name,
		"快照里有正确的机体名")
	t.ok(float(hud._result.get("hp", -1.0)) <= 0.0, "快照里的机体耐久是阵亡后的值")

	# 等残骸被释放（_wreck_timer 是 2.2 秒）。这才是暴露 bug 的时刻。
	for i in 200:
		await tree.physics_frame
	t.not_ok(is_instance_valid(player), "玩家残骸已被释放（2.2 秒后）")

	# 关键断言：玩家没了，但**绘制入口不能关**，结算数据也不能跟着没
	t.ok(hud.can_draw(), "玩家已释放，HUD 绘制入口仍然打开（这就是「秒没」的根因）")
	t.gt(hud._result.size(), 0, "玩家已释放，结算快照依然在")
	t.eq(str(hud._result.get("suit", "")), SuitProfile.xi().display_name,
		"玩家已释放，快照里的机体名依然正确")
	t.eq(Game.phase, Game.Phase.LOSE, "玩家已释放，仍然停在战败结算")
	t.eq(main.get("phase"), _main_phase(main, "RESULT"),
		"main 仍然停在 RESULT 阶段（不会自己跳走）")

	# 结算页仍然能正常回到主菜单
	await _key(host, KEY_ENTER, true)
	for i in 6:
		await tree.physics_frame
	await _key(host, KEY_ENTER, false)
	for i in 20:
		await tree.physics_frame
	await _await_menu_loading(host,main)
	t.eq(Game.phase, Game.Phase.MENU, "战败结算页按 Enter 回到主菜单")
	t.not_ok(tree.paused, "战败后回主菜单不是暂停态")

	# 收尾：再开一局，把状态交还给后续的 _result_flow
	# （顺带也验证了"战败回菜单之后还能正常再开一局"）
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.HARD)
	for i in 20:
		await tree.physics_frame
	main.call("_start_fight")
	for i in 10:
		await tree.physics_frame
	t.eq(Game.phase, Game.Phase.FIGHT, "战败之后仍能正常开新局并进入战斗")


## 「击坠 → 结算 → 回主菜单 → 从菜单再开一局」的回归测试。
##
## 这一条是从一个真实 bug 里长出来的：用户报过"重开一局游戏会卡住"，根因是
## **暂停状态没人清** —— `pause` 与 `menu_back` 都绑在 ESC 上，而当时
## `_handle_global_input` 对"非主菜单的所有阶段"都生效，于是在结算页按 ESC
## 会同时暂停游戏树并跳回主菜单；从菜单开新一局时，新机体是在**已暂停的树**里创建的：
## 机体不动、空格不响应，`match phase` 分支整个不再执行，看起来就是死机。
##
## 把场上**所有**敌对单位打掉（用于"全歼才判胜"的用例）。
##
## ⚠️ 别退回"只打 `main.enemy`"：1.2 起对战对手是一对（一板载两台），
## 被载那台在 `Game.units` 里但是 `main.enemy` 拿不到它。
## 一边遍历一边改 units 会漏，所以先抄一份再打。
static func _kill_all_hostiles(host: Node, main: Node, player) -> void:
	if player == null or not is_instance_valid(player):
		return
	var foes := Game.live_hostiles_of(player)
	for f in foes.duplicate():
		if f == null or not is_instance_valid(f):
			continue
		# 板要先摘掉：带着板的单位会把伤害分给板（`_route_damage_through_pedal`），
		# 一发 999999 也照样先过板那一层，这里直接清耐久更干净。
		f.ifield_hp = 0.0
		var board = f.pedal_owner() if f.has_method("pedal_owner") else null
		if board != null:
			board.hp = 0.0
		f.take_damage(999999.0, player, Damage.Type.SABER)
	await host.get_tree().physics_frame


## 之后用户又要求撤掉"再战一局"，所以现在结算只有一个出口：回主菜单。
## 这条测试把三个不变量钉住：结算之后**只能**回主菜单；任何阶段切换后
## `paused` 都必须是 false；从菜单开的新一局机体必须真的会动。
static func _result_flow(t: T, host: Node, main: Node) -> void:
	var tree := host.get_tree()
	var player = main.get("player")

	# 击坠敌机 → 结算
	#
	# ⚠️ **要清的是"全部敌机"，不是 `main.enemy` 那一架**：1.2 起对战模式的对手是
	# **一对**（一板载两台，见 `main.attach_pedal_pair()`）—— 板挂在领机身上、
	# 后机被载着，两台都是 `team = 1` 的独立单位。只打掉领机的话
	# `live_hostiles_of(player)` 里还有那台被载机，判胜**正确地**不会发生。
	# 所以这里改成"把所有敌机都打掉"，顺便把"必须全歼才判胜"这条也钉住。
	await _kill_all_hostiles(host, main, player)
	for i in 40:
		await tree.physics_frame
	t.eq(Game.phase, Game.Phase.WIN, "击坠敌机后进入胜利结算")
	t.not_ok(tree.paused, "结算时不是暂停态")

	# 结算画面刚出现时有 0.6 秒输入锁，先等它过去
	for i in 60:
		await tree.physics_frame
	t.not_ok(tree.paused, "输入锁期间也不是暂停态")

	# 按 Enter：回主菜单（没有"再战一局"了）
	await _key(host, KEY_ENTER, true)
	for i in 6:
		await tree.physics_frame
	await _key(host, KEY_ENTER, false)
	for i in 20:
		await tree.physics_frame
	await _await_menu_loading(host,main)
	t.eq(Game.phase, Game.Phase.MENU, "结算页按 Enter 回到主菜单")
	t.not_ok(tree.paused, "回主菜单之后树**不能**是暂停的（这就是当初「卡住」的根因）")
	t.ok(main.get("player") == null, "回主菜单后场上没有残留的玩家机")
	var menu_node = main.get("menu")
	t.ok(menu_node != null and is_instance_valid(menu_node) and menu_node.visible,
		"主菜单重新显示出来了")

	# 从菜单重新开一局。
	#
	# 这里**故意不用注入按键去驱动菜单的逐级选择**：无头环境下
	# `Input.parse_input_event` 的 flush 时机不确定（实测同一个按键可能隔几十帧
	# 才被菜单看到，甚至 `is_action_pressed` 会跨帧为真），
	# "按几下键 = 走几步界面"这个前提在测试里根本不成立。
	# 菜单的按键流程由 suite_input 覆盖；这里只验真正要紧的状态不变量：
	# 回主菜单后能干净地再开一局、暂停不残留、新机体真的会动。
	main.call("_on_start_match", SuitProfile.Id.PENELOPE, Difficulty.Level.EASY)
	await _key(host, KEY_ENTER, false)
	for i in 30:
		await tree.physics_frame

	t.eq(Game.phase, Game.Phase.FIGHT, "从菜单开出新一局后直接是 FIGHT（1.2 起没有 INTRO）")
	t.not_ok(tree.paused, "新一局不是暂停态")
	var p2 = main.get("player")
	t.ok(p2 != null and is_instance_valid(p2), "新一局有玩家机")
	if p2 != null and is_instance_valid(p2):
		var q0: Vector3 = p2.global_position
		for i in 60:
			await tree.physics_frame
		t.gt(q0.distance_to(p2.global_position), 1.0,
			"新机体在 60 帧内真的移动了（%.1f m）" % q0.distance_to(p2.global_position))

	# ---- 暂停：真的停住世界 + 有"继续 / 返回主菜单"两个出口 ----
	#
	# 用户实测报过"Esc 暂停键没有暂停效果"。根因不在 `get_tree().paused`，
	# 而在 **PROCESS_MODE 是继承的**：main 为了在暂停期间收输入被设成 ALWAYS，
	# 于是它所有 INHERIT 的子节点（世界 / 机体 / 弹丸 / 镜头）也变成 ALWAYS，
	# 树暂停对它们无效。所以这里断言的不是"标志位变了"，而是**机体真的不动了**。
	var hud = main.get("hud")
	var pause_menu = main.get("pause_menu")
	t.ok(pause_menu != null and is_instance_valid(pause_menu), "暂停菜单已建出")
	t.ok(not pause_menu.visible, "战斗中暂停菜单是收起的")

	var p_pause = main.get("player")
	await _key(host, KEY_ESCAPE, true)
	for i in 6:
		await tree.physics_frame
	await _key(host, KEY_ESCAPE, false)
	for i in 6:
		await tree.physics_frame
	t.ok(tree.paused, "战斗中按 Esc 可以暂停")
	t.ok(pause_menu.visible and pause_menu.open, "暂停菜单显示出来了（否则玩家以为卡死了）")
	t.eq(pause_menu.selected_key(), "resume",
		"暂停菜单默认停在「继续战斗」（最不破坏性的那一项）")

	# 这一条就是那个 bug 的回归：暂停期间机体真的不能再动。
	#
	# 采样点必须在**暂停已经生效之后**再取 —— 按 Esc 的那一帧物理可能已经先跑过了，
	# 从按键之前开始量会带上那一帧的位移（第一版就是这么写的：
	# 量到 6.8 m，看着像"没停"，其实是生效前最后一帧飞出去的）。
	for i in 3:
		await tree.physics_frame
	var p_before: Vector3 = p_pause.global_position
	for i in 30:
		await tree.physics_frame
	t.lt(p_before.distance_to(p_pause.global_position), 0.001,
		"暂停期间机体位置完全不变（%.3f m）—— 树暂停真的生效了"
		% p_before.distance_to(p_pause.global_position))
	t.ok(hud.get("paused") == null,
		"暂停界面整个归 PauseMenu（HUD 不再持有暂停布尔，免得两个节点各画一半）")

	# Esc / 手柄 Start / 手柄 B 都是"继续战斗"
	await _key(host, KEY_ESCAPE, true)
	for i in 6:
		await tree.physics_frame
	await _key(host, KEY_ESCAPE, false)
	for i in 6:
		await tree.physics_frame
	t.not_ok(tree.paused, "再按一次 Esc 取消暂停")
	t.not_ok(pause_menu.visible, "取消暂停后暂停菜单收起")

	# 暂停菜单里的"返回主菜单"：直接把这一局丢掉，回菜单重选（用户要求的出口）
	await _key(host, KEY_ESCAPE, true)
	for i in 6:
		await tree.physics_frame
	await _key(host, KEY_ESCAPE, false)
	for i in 6:
		await tree.physics_frame
	t.ok(tree.paused, "再次暂停")
	main.call("_on_pause_back_to_menu")
	for i in 10:
		await tree.physics_frame
	await _await_menu_loading(host,main)
	t.eq(Game.phase, Game.Phase.MENU, "暂停菜单的「返回主菜单」真的回到了主菜单")
	t.not_ok(tree.paused, "回主菜单后暂停被清掉")
	t.not_ok(pause_menu.visible, "回主菜单后暂停菜单收起")
	t.ok(main.get("player") == null, "回主菜单后场上没有残留的玩家机")

	# 从菜单再开一局，把状态交还给下面的用例
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.HARD)
	for i in 20:
		await tree.physics_frame

	# 结算页按 Esc 只能回主菜单，**不能**把树暂停（这正是当初卡死的路径）
	main.call("_start_fight")
	for i in 10:
		await tree.physics_frame
	var pl = main.get("player")
	await _kill_all_hostiles(host, main, pl)
	for i in 60:
		await tree.physics_frame
	t.eq(Game.phase, Game.Phase.WIN, "再次击坠进入结算")

	await _key(host, KEY_ESCAPE, true)
	for i in 6:
		await tree.physics_frame
	await _key(host, KEY_ESCAPE, false)
	for i in 20:
		await tree.physics_frame
	await _await_menu_loading(host,main)
	t.eq(Game.phase, Game.Phase.MENU, "结算页按 Esc 回到主菜单")
	t.not_ok(tree.paused, "结算页按 Esc **不会**把树暂停（卡死路径已封）")

	# 从菜单再开一局，机体必须能跑。
	#
	# ⚠️ 1.1 起菜单是**四步**（模式 → 机体 → 难度 → 地图），训练模式两步。
	# 这里不逐页按键（理由见 `_result_flow` 开头的注释：无头环境里按键 flush 时机不可靠），
	# 直接把菜单拨到最后一页再按 Enter —— 走的是同一条 `_launch()`：
	# 与"真人一页页按到最后一页再按 Enter"是同一段代码。
	var menu2: Node = main.get("menu")
	if menu2 != null and is_instance_valid(menu2):
		menu2.set("stage", MainMenu.Stage.MAP)
	# The newly reopened menu has its own input lockout after the loader fades.
	for i in 60:
		await tree.physics_frame
	await _key(host, KEY_ENTER, true)
	for i in 6:
		await tree.physics_frame
	await _key(host, KEY_ENTER, false)
	for i in 30:
		await tree.physics_frame
	await _await_menu_loading(host,main)
	t.not_ok(tree.paused, "从菜单开新局之后不是暂停态")
	var p3 = main.get("player")
	if p3 != null and is_instance_valid(p3):
		var r0: Vector3 = p3.global_position
		for i in 60:
			await tree.physics_frame
		t.gt(r0.distance_to(p3.global_position), 1.0, "从菜单开的新一局机体也在动")
	else:
		t.ok(false, "从菜单开新局后应该有玩家机")


# ============================================================ 地图（1.1）

## 三张地图都要能搭起来，而且**换图必须是幂等的**。
##
## 这条是从"一个真实的坑"来的：`apply_map()` 先 free 掉上一层地表再建新的，
## 如果哪天有人改成"只往上加"，菜单里来回切两次图就会有两层地面叠在一起
## （z-fighting，看着像贴图坏了），而这种事在单张图的测试里根本看不出来。
## 数一个世界里当前**所有云带**的实例总数（三带各一个 MultiMesh）。
## 1.2 起云挂在 `_cloud_root` 底下（换图整层重建），不再是 world 的直接子节点。
static func _cloud_count(world: Node) -> int:
	var n := 0
	var root: Node = world.get("_cloud_root")
	if root == null:
		return 0
	for c: Node in root.get_children():
		var mm := c as MultiMeshInstance3D
		if mm != null and mm.multimesh != null:
			n += mm.multimesh.instance_count
	return n


## 从 `main.gd` 的 `Phase` 枚举里**按名字**取值。
##
## ⚠️ 这两处原来把枚举值抄成了数字 `3`。1.2 删掉 `INTRO` 之后 `RESULT` 从 3 变成 2，
## 抄来的数字立刻失效 —— 而**代码本身是对的**，红的是测试。
## 唯一的真源是那个枚举，所以这里按名字去问它。
static func _main_phase(main: Node, name: String) -> int:
	var scr := main.get_script() as GDScript
	if scr == null:
		return -1
	var cmap: Dictionary = scr.get_script_constant_map()
	var phases = cmap.get("Phase")
	if phases is Dictionary:
		return int((phases as Dictionary).get(name, -1))
	return -1


static func _maps(t: T, host: Node) -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await host.get_tree().process_frame
	var world: Node = main.get("world")
	t.ok(world != null, "世界已建出")

	var ids := MapDef.all_maps()
	# ⚠️ 1.2 第二十一轮加了**奥恩贝利（夜城）**：3 → 4 张、对战 2 → 3 张。
	# ⚠️ 1.3 批 M 加了**达沃（夜袭的活港都）**：4 → 5 张、对战 3 → 4 张。
	#   达沃**进**对战列表是用户明确要求的口径（1.3 设计书 §3.5 原本写的是"先不进"，
	#   理由是"新图要在剧情里验证过再开放"；用户推翻了它 —— 剧情模式还没做，
	#   不进对战列表就等于这张图**根本看不到**）。
	# ⚠️ 剧情模式轮 B2 加了**低地球轨道**：5 → 6 张、对战 4 → 5 张。
	#   进对战列表的理由与达沃**逐字相同**。（轮 C 的 M03 才通，不进来它在轮 B2
	#   就只剩探针能看见 —— 那正是达沃那轮被推翻的那件事。）
	t.eq(ids.size(), 6,
		"一共六张地图（太平洋群岛 / 艾尔斯岩 / 奥恩贝利 / 达沃 / 低地球轨道 / 废墟靶场）")
	t.eq(MapDef.versus_maps().size(), 5, "1v1/编队战可选五张（靶场是训练专用）")
	t.ok(not MapDef.versus_maps().has(MapDef.Id.RANGE), "靶场不在 1v1 列表里")

	var clouds := {}
	for id: int in ids:
		var m := MapDef.by_id(id)
		t.ok(m.name_cn != "" and m.time_of_day != null, "%s 有名字与夜色" % m.code)
		# ⚠️ 第二十二轮下半：**奥恩贝利不再是夜战**。
		# 用户把它的设定改成"刚经历大屠杀的死城 + 阴天黄昏"，
		# 于是它用 `dusk_overcast()`（铅灰压顶、无太阳、无星、全城不点灯）。
		# 另外三张图照旧是夜战 —— 所以这里按图判，不再"一刀切 NIGHT"。
		#
		# ⚠️ 剧情模式轮 B2：**轨道图不是一天里的任何一个时刻**。它用 `Preset.SPACE`
		# （第 4 档，且**刻意不进** `all_presets()` —— 那个表是"一天里的三个时刻"）。
		# 不单独列一档的话，这条会拿"夜战"去量一张真空里的图。
		var want_dusk: bool = m.id == MapDef.Id.OENBELLI
		var want_space: bool = m.id == MapDef.Id.LEO
		if want_dusk:
			t.eq(m.time_of_day.preset, TimeOfDay.Preset.DUSK, "%s 是阴天黄昏（死城）" % m.code)
			t.eq(m.time_of_day.star_amount, 0.0, "%s 阴天：一颗星都没有" % m.code)
			t.eq(m.time_of_day.disc_amount, 0.0, "%s 阴天：太阳被云完全挡住" % m.code)
		elif want_space:
			t.eq(m.time_of_day.preset, TimeOfDay.Preset.SPACE,
				"%s 是真空档（不是任何一个时刻）" % m.code)
			t.eq(m.time_of_day.star_amount, 1.0, "%s 星空满额（真空里这是主画面）" % m.code)
			t.eq(m.time_of_day.fog_density, 0.0, "%s 没有大气雾（那层雾是**大气**雾）" % m.code)
		else:
			t.eq(m.time_of_day.preset, TimeOfDay.Preset.NIGHT, "%s 是夜战" % m.code)
		world.call("apply_map", m)
		await host.get_tree().physics_frame
		clouds[m.code] = _cloud_count(world)
		var terrain: Node = world.get("_terrain_root")
		var kids := terrain.get_child_count()
		t.gt(kids, 1, "%s 的地表搭出来了（%d 个节点）" % [m.code, kids])
		# 海面只属于"需要水"的地图：换到沙漠/靶场之后不该还漂着一张巨大的水面。
		if m.terrain == MapDef.Terrain.ISLANDS:
			t.ok(world.get("ocean") != null, "群岛图有海面")
			# ⚠️ 第十四轮改了判据（旧断言："群岛图有岛屿"）。
			# 老板实测："太平洋地图的小岛要删掉，不好看" → `ISLAND_COUNT = 0`。
			# 这里要同时钉住**两件事**，少一件就会漏掉真正的风险：
			#   ① 岛真的一座都没有了；
			#   ② **海面还在** —— 海面是 `_build_islands()` 顺带建的，
			#      谁要是"把群岛图的地表整个删掉"来满足第①条，这里立刻红。
			var ir: Node = world.get("islands_root")
			t.ok(ir != null, "群岛图仍然有 islands_root（空容器，供本判据与换图清理用）")
			if ir != null:
				t.eq(ir.get_child_count(), 0, "群岛图上一座岛都没有（第十四轮：小岛删掉）")
		elif m.terrain == MapDef.Terrain.CITY:
			# ⚠️ 第二十二轮改了判据（旧断言："奥恩贝利没有海面"）。
			# 城市图重做成**台场式海湾城市**（奥恩贝利的街景本来就参考台场），
			# 所以它**有水面**：海湾 + 一条穿城的人工运河。
			# 这里要钉住的不再是"有没有水"，而是**水不能把陆地淹掉** ——
			# 城市地面就在 y≈0，水面只要高于岸线，整座城就会变成水下废墟。
			var oc: Node3D = world.get("ocean")
			t.ok(oc != null, "城市图有水面（海湾 + 运河，第二十二轮）")
			if oc != null:
				# ⚠️⚠️ 2026-09-27 判据重写。原来写的是 `between(y, 0.0, 8.0)` ——
				# 那是"水面 = 0.2 m"那个年代的代理值：它把水面标高写成了**一个神奇的
				# 区间**，而不是断言这段注释真正在说的那条不变量（"水不能把陆地淹掉"）。
				# 这一轮水面从 +0.2 降到 `CITY_WATER_Y = −12`（原因见那个常量的推导：
				# 陆地起伏是 −7.9…+7.9，0.2 m 的水面让 **53% 的陆地泡在水里**），
				# 旧判据当场红 —— 而红的原因跟"陆地有没有被淹"毫无关系。
				#
				# ⇒ 新判据**直接量那件事**：把"按规划是陆地"（在岛上、不在海湾/运河里）
				#   的格点从小到大扫一遍，数**有多少真的落在水面之下**。
				#   ⚠️ 不能用"水面 < 陆地最低点"：`is_water_at()` 的岸线与**地形**的
				#   水线之间天生有一条 1~1.4 km 的过渡带（海湾从岸线起 smoothstep
				#   渐降 480 m），过渡带里"判据说陆、地形已在水下"是**设计如此**。
				#   ⇒ 判据用**比例**（≤ 3%），它量的是"淹了多少"，与魔法区间无关。
				t.near(oc.position.y, WorldBuilder.CITY_WATER_Y, 0.001,
					"城市水面 %.1f m = `CITY_WATER_Y`（常数是唯一真源）" % oc.position.y)
				var cblk := WorldBuilder.ARENA_RADIUS / float(WorldBuilder.CITY_GRID)
				var wet := 0
				var planned := 0
				var steps := 96
				for i in steps + 1:
					for j in steps + 1:
						# 只在**城域**内采样（岛 + 一点余量），远景地坪不参与。
						var px := (float(i) / float(steps) * 2.0 - 1.0) * 70000.0
						var pz := (float(j) / float(steps) * 2.0 - 1.0) * 70000.0
						if not WorldBuilder.city_is_land(px / cblk, pz / cblk,
								m.city_layout):
							continue
						if WorldBuilder.is_water_at(px, pz, m.city_layout):
							continue
						planned += 1
						if WorldBuilder._city_landform(px, pz, m.city_layout) \
								< WorldBuilder.CITY_WATER_Y:
							wet += 1
				t.gt(planned, 200, "在城域内采到了成片的规划陆地（采样没跑空）")
				var wet_pct := float(wet) / maxf(float(planned), 1.0) * 100.0
				t.lt(wet_pct, 3.0,
					"%s：规划陆地中被水面盖住的占 %.2f%%（判据 ≤ 3%%；水面在 +0.2 m 时这里是 50%%+）"
						% [m.code, wet_pct])
				t.gt(oc.position.y, -600.0,
					"水面仍远高于远景地坪（−600 m）—— 不然海湾会露出地坪的底")
		else:
			t.ok(world.get("ocean") == null, "%s 没有海面" % m.code)
		# 换图不能把上一张图的地表留下
		world.call("apply_map", m)
		await host.get_tree().physics_frame
		t.eq((world.get("_terrain_root") as Node).get_child_count(), kids,
			"%s 重复换图不会叠出第二层地表" % m.code)
		# ★ 轮 50：达沃的**内阁下榻酒店**（= 中央针塔，全图最高的那件，
		# 参考迪拜塔建）必须**真的登记进了 `HOTEL_GROUP`** ——
		# 弹体就是靠这个组名认它的；登记错对象的后果是
		# “玩家打中了塔，但任务目标永远不完成”，**一处都不报错**。
		if m.id == MapDef.Id.DAVAO:
			var hotel: Array = host.get_tree().get_nodes_in_group(WorldBuilder.HOTEL_GROUP)
			t.eq(hotel.size(), 5,
				"★ 达沃酒店 = 中央针塔的 **4 段塔身 + 塔尖**（顶灯不进组）")
			var hotel_bodies := 0
			var hotel_top := -1.0e30
			for h: Node in hotel:
				if h is StaticBody3D:
					hotel_bodies += 1
				if h is Node3D:
					hotel_top = maxf(hotel_top, (h as Node3D).global_position.y)
			# ⚠️ 这一条钉的是 `_tag_box()` 注释里那个坑：
			# 登记的必须是**碰撞体那一层**（`StaticBody3D`），而不是 `MeshInstance3D`。
			t.eq(hotel_bodies, 5,
				"★ 登记的是**碰撞体那一层**（弹体扫掠打到的就是它）")
			t.gt(hotel_top, 7000.0,
				"★ 酒店塔尖在 7000 m 以上（实测最高件 y = %.0f m）" % hotel_top)
			# “达沃中心**最高的楼**”—— 跟 `_terrain_root` 下**不属于针塔自己**的实体几何比一比。
			#
			# ⚠️ ⚠️ 只跟 **`StaticBody3D`** 比 —— 这一条是**第二次**修的：
			#
			# ① 首版把取值域定成“所有不在组里的几何”，结果拿酒店塔尖去比
			#    **自己的顶灯** `NeedleTipLight`（y ≈ 9121 m，它刻意不进组）⇒ 假红；
			# ② 排掉 `Needle*` 之后，并行会话又给 `_terrain_root` 加了
			#    **HUD 只读信标** `HotelTarget`（`Marker3D`，钉在塔尖顶 y = 9065 m）
			#    —— 它名字不以 `Needle` 开头、也不在组里 ⇒ 又一条假红。
			#    信标**没有网格**，本来就**不是楼** ⇒ 用 `StaticBody3D` 过滤比“记名单”更正确。
			# ⚠️ 组员的父节点就是 `_terrain_root`（`_add_box()` 把 body 挂在它下），
			# 所以这里量的就是“全城其它一切”—— 正是那句话的字面意思。
			var peer_top := -1.0e30
			var peer_name := ""
			var peer_n := 0
			var troot: Node = world.get("_terrain_root")
			if troot != null:
				for ch: Node in troot.get_children():
					if not (ch is StaticBody3D):
						continue
					if ch.is_in_group(WorldBuilder.HOTEL_GROUP) \
							or ch.name.begins_with("Needle"):
						continue
					peer_n += 1
					var cy := (ch as Node3D).global_position.y
					if cy > peer_top:
						peer_top = cy
						peer_name = str(ch.name)
			# ★ **尺子守卫**：对照组不能空。
			# 万一将来城里的楼全变成 `MultiMesh`（本套件别处记过
			# “无头下读回来全是单位变换”），对照组会**悄悄变空**，
			# 那时“酒店最高”就是一条**量空了的假绿**。
			t.gt(peer_n, 100, "对照组非空（有成片的楼可比：%d 件）" % peer_n)
			t.gt(peer_top, 1000.0,
				"对照组里真的有**高楼**（最高 %.0f m @ %s）—— 不然这条尺子量不出东西" % [peer_top, peer_name])
			# ⚠️ 运行器**只在失败时打标签** ⇒ 要人复核的读数必须自己 `print()`。
			print("[r50] 达沃酒店组 %d 件 / 塔尖 y=%.0f m / 对照组 %d 件最高 y=%.0f m @ %s"
				% [hotel.size(), hotel_top, peer_n, peer_top, peer_name])
			t.gt(hotel_top, peer_top,
				"★ **酒店确实是全城最高的楼**（%.0f m > 其余最高 %.0f m @ %s）"
					% [hotel_top, peer_top, peer_name])

	# ---- 1.2：云量**按地图**走（用户要求"艾尔斯岩地图也加入更多的云层"）----
	#
	# ⚠️ 判据不查"配置里写了多少"，而是查**换图之后云真的变多了**：
	# `MapDef.cloud_density` 写错、或者 `apply_map()` 里忘了重建云层，
	# 这条都会红 —— 只查配置的话两个漏洞都抓不到（配置是对的，云没重建）。
	t.gt(clouds["ULURU"], int(float(clouds["PACIFIC"]) * 1.5),
		"艾尔斯岩的云比群岛图多一半以上（%d vs %d）—— 换图真的重建了云层"
		% [clouds["ULURU"], clouds["PACIFIC"]])
	t.gt(clouds["RANGE"], 1800,
		"靶场的云量仍是基础量（没有把按地图的倍率误加到每张图上）")

	# 沙漠图要有"巨岩"，靶场要有"靶环" —— 用户点名的那两样东西必须真的存在
	world.call("apply_map", MapDef.uluru())
	await host.get_tree().physics_frame
	var rock := (world.get("_terrain_root") as Node).find_child("Uluru", true, false)
	t.ok(rock != null, "艾尔斯岩图里真的有一块名为 Uluru 的巨岩")
	world.call("apply_map", MapDef.training_range())
	await host.get_tree().physics_frame
	var ring := (world.get("_terrain_root") as Node).find_child("TargetRing0", true, false)
	t.ok(ring != null, "靶场里有地面靶环")

	main.free()
	await host.get_tree().process_frame
	Game.reset()


# ============================================================ 训练模式（1.1）

## 训练模式：固定落在靶场、撒四架古斯塔夫00靶机、靶机不还手。
static func _training(t: T, host: Node) -> void:
	var tree := host.get_tree()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await tree.process_frame

	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.NORMAL,
		MapDef.Id.RANGE, Game.MatchMode.TRAINING)
	await tree.process_frame
	await tree.physics_frame

	var player = main.get("player")
	t.ok(player != null and is_instance_valid(player), "训练模式也有玩家机")
	t.eq(Game.match_mode, Game.MatchMode.TRAINING, "模式写进了 Game")
	t.eq(Game.active_map.id, MapDef.Id.RANGE, "训练模式落在靶场（即使菜单传了别的图）")
	var world: Node = main.get("world")
	t.eq((world.get("map") as MapDef).id, MapDef.Id.RANGE, "世界也换到了靶场")
	t.ok(main.get("enemy") == null, "训练模式没有 1v1 的敌机")
	t.ok(main.get("enemy_lock") == null, "训练模式没有敌机锁定系统（靶机不还手）")

	var targets: Array = main.get("targets")
	t.eq(targets.size(), 4, "撒了四架靶机")
	t.eq(Game.training_targets_total, 4, "靶机总数写进了 Game 供 HUD 显示")
	var all_drones := true
	for d in targets:
		all_drones = all_drones and (d is TargetDrone)
	t.ok(all_drones, "四架都是 TargetDrone（不是 BanditAI）")
	if not targets.is_empty():
		var d0 = targets[0]
		t.eq(d0.profile.id, SuitProfile.Id.GUSTAV00, "靶机用的是古斯塔夫00")
		t.ok(d0.profile.funnel_count == 0 and d0.profile.rifle_count == 0,
			"靶机身上没有武器（靶机就该不还手）")
		# 训练模式必须拿**靶机版**（`main.spawn_training()` 是显式调 `gustav00()` 的）——
		# 这一条和上面挑战那一组互为镜像：同一个 Id，两种用法，谁都不能串。
		t.eq(d0.profile.hull_hp, SuitProfile.gustav00().hull_hp,
			"训练靶机用的是靶机版耐久（%d）" % int(SuitProfile.gustav00().hull_hp))
		t.eq(d0.profile.display_name, "古斯塔夫00（靶机）", "靶机的名字带「靶机」字样")
		var y0: Vector3 = d0.global_position
		for i in 30:
			await tree.physics_frame
		t.gt(y0.distance_to(d0.global_position), 20.0, "靶机在按航线飞（不是钉死在原地）")

	# 打光所有靶机 → 过关结算（先真正开打：INTRO 阶段不算战绩）
	main.call("_start_fight")
	await tree.physics_frame
	var p = main.get("player")
	for d in targets:
		if is_instance_valid(d) and d.alive:
			d.ifield_hp = 0.0
			d.take_damage(99999.0, p, Damage.Type.SABER)
	for i in 40:
		await tree.physics_frame
	t.eq(Game.phase, Game.Phase.WIN, "靶机全部击破 → 胜利结算")
	t.eq(Game.training_targets_down, 4, "击破计数是 4")
	t.eq(int(main.get("phase")), _main_phase(main, "RESULT"), "main 进入 RESULT 阶段")

	main.free()
	await tree.process_frame
	Game.reset()


# ============================================================ 1.2 敌人选择 / 挑战 / 变形 / 联机

## 剧情脚本本身的性质（纯数据，不需要场景）。
static func _scripts(t: T) -> void:
	var all := ChallengeScript.all()
	t.eq(all.size(), 4, "四组遭遇：柯西两场、佩涅罗佩一场、阿利宙斯一场")
	t.eq(ChallengeScript.for_suit(SuitProfile.Id.XI).size(), 2, "柯西有两场挑战")
	t.eq(ChallengeScript.for_suit(SuitProfile.Id.PENELOPE).size(), 1, "佩涅罗佩只有一场")
	t.eq(ChallengeScript.for_suit(SuitProfile.Id.ARIZEUS).size(), 1, "阿利宙斯只有一场")
	for e: ChallengeScript.Encounter in all:
		t.ok(e.title != "" and e.story != "", "%s 有标题与剧情简介" % e.id)
		t.gt(ChallengeScript.total_enemies(e), 0, "%s 有敌人" % e.id)
	# 用户点名的两条对位：柯西→佩涅罗佩在太平洋、柯西→阿利宙斯在艾尔斯岩
	var a := ChallengeScript.xi_vs_penelope()
	t.eq(a.map_id, MapDef.Id.PACIFIC, "柯西打佩涅罗佩在太平洋上空")
	var b := ChallengeScript.xi_vs_arizeus()
	t.eq(b.map_id, MapDef.Id.ULURU, "柯西打阿利宙斯在艾尔斯岩")
	t.eq(ChallengeScript.penelope_vs_xi().map_id, MapDef.Id.PACIFIC, "佩涅罗佩打柯西也在太平洋")
	t.eq(ChallengeScript.arizeus_vs_xi().map_id, MapDef.Id.ULURU, "阿利宙斯打柯西在艾尔斯岩")
	# 关键那一条："先出两台古斯塔夫，全灭之后阿利宙斯才从上方出场"
	t.eq(ChallengeScript.wave_count(b), 2, "柯西打阿利宙斯是两波")
	t.eq(int(b.waves[0].suit), int(SuitProfile.Id.GUSTAV00), "第一波是古斯塔夫00")
	t.eq(int(b.waves[0].count), 3, "第一波正好**三台**（1.2 用户要求从两台加到三台）")
	t.eq(int(b.waves[1].suit), int(SuitProfile.Id.ARIZEUS), "第二波才是阿利宙斯")
	t.gt(b.waves[1].altitude, b.waves[0].altitude, "阿利宙斯从**更高**的高度入场（从上方出场）")
	t.ok(b.waves[1].aggressive, "阿利宙斯一出场就是进攻状态（压下来打）")
	t.not_ok(SuitProfile.gustav00_armed().has_missiles, "古斯塔夫没有浮游导弹（用户点名）")
	t.ok(SuitProfile.gustav00_armed().rifle_count > 0, "古斯塔夫有光束步枪")
	t.ok(SuitProfile.gustav00_armed().has_saber, "古斯塔夫有军刀")


## 对战模式：选谁就打谁。
static func _enemy_choice(t: T, host: Node) -> void:
	var tree := host.get_tree()
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await tree.process_frame
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.EASY,
		MapDef.Id.PACIFIC, Game.MatchMode.VERSUS, SuitProfile.Id.ARIZEUS)
	await tree.process_frame
	var foe = main.get("enemy")
	t.ok(foe != null, "指定敌机之后敌机照样出生")
	t.eq(foe.profile.id, SuitProfile.Id.ARIZEUS, "敌机就是玩家选的那台（阿利宙斯）")
	# 不指定时仍然是"另一台"（老行为不变）
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.EASY,
		MapDef.Id.PACIFIC, Game.MatchMode.VERSUS)
	await tree.process_frame
	t.eq((main.get("enemy") as FlightBody).profile.id, SuitProfile.Id.PENELOPE,
		"不指定敌机时自动挑另一台（佩涅罗佩）")
	main.free()
	await tree.process_frame
	Game.reset()


## 挑战局：两台古斯塔夫先出场，打光之后阿利宙斯从上方入场。
static func _challenge(t: T, host: Node) -> void:
	var tree := host.get_tree()
	_scripts(t)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await tree.process_frame
	Game.active_challenge_id = ChallengeScript.xi_vs_arizeus().id
	main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.NORMAL,
		-1, Game.MatchMode.CHALLENGE)
	await tree.process_frame
	await tree.physics_frame
	t.eq(Game.match_mode, Game.MatchMode.CHALLENGE, "进入挑战模式")
	t.eq(Game.active_map.id, MapDef.Id.ULURU, "地图由剧情脚本决定（艾尔斯岩）")
	t.eq(Game.active_challenge.id, "XI_VS_ARIZEUS", "脚本注入正确")
	t.eq(Game.challenge_total, 4, "这一场一共四架敌机（3 古斯塔夫 + 1 阿利宙斯）")
	var first: Array = main.get("wave_units")
	t.eq(first.size(), 3, "第一波三台")
	for u in first:
		t.eq(u.profile.id, SuitProfile.Id.GUSTAV00, "第一波是古斯塔夫00")
		t.not_ok(u.profile.has_missiles, "第一波的古斯塔夫没有导弹")
		# ⚠️ 这一组是**回归断言**：`by_id(Id.GUSTAV00)` 曾经返回过**靶机版**
		# （rifle_count 0 / vulcan_ammo 0 / hull 90），于是挑战里那两架古斯塔夫
		# 整场一枪不放 —— 它们照样出生、照样能被锁定，所以从"能不能锁"的角度
		# 完全看不出问题，只有盯"它们有没有武器"才抓得住。
		t.gt(u.profile.rifle_count, 0, "挑战里的古斯塔夫有光束步枪（不是不还手的靶机）")
		t.gt(u.profile.vulcan_ammo, 0, "挑战里的古斯塔夫有火神炮弹药")
		t.gt(u.profile.hull_hp, SuitProfile.gustav00().hull_hp,
			"挑战里的古斯塔夫比训练靶机硬（%.0f > %.0f）"
			% [u.profile.hull_hp, SuitProfile.gustav00().hull_hp])
		t.eq(u.profile.display_name, "古斯塔夫00", "HUD 上显示的是武装版的名字（不带「靶机」）")
	t.eq(Game.challenge_wave, 0, "当前是第 1 波")
	t.eq(Game.challenge_wave_remaining, 3, "本波还剩三架")

	# 打掉第一波之前，先验证**它们真的会还手** —— 这是用户报的那个 bug 的核心：
	# 靶机版的古斯塔夫 `rifle_count = 0 / vulcan_ammo = 0`，整场一枪不放，
	# 但它们照样出生、照样能被锁定，所以"能不能锁定"的断言完全看不出问题。
	# 只有盯"它们有没有把子弹打出来"才抓得住，所以这里直接数开火信号。
	main.call("_start_fight")
	await tree.physics_frame
	var p = main.get("player")
	p.max_hp = 99999.0
	p.hp = 99999.0
	var shots := [0]
	for u in first:
		if is_instance_valid(u):
			u.beam_fired.connect(func(): shots[0] += 1)
			u.gun_fired.connect(func(): shots[0] += 1)
	var g = first[0]
	if is_instance_valid(g):
		# 把玩家摆到第一架正前方 700 m（在它的步枪射程 2400 m 之内），等 6 秒
		p.global_position = g.global_position + g.forward() * 700.0
		p.fm.speed = 200.0
		p.fm.align_velocity(p.forward())
	# ⚠️ 从这里起，**每帧把玩家钉回这个点** —— 理由见 `_hold_player()`。
	# 一句话：窗口是按**时间**给的（不该跟着提速变），而无人操纵的飞机在这段时间里
	# 飞过的**距离**会跟着 `SPEED_REAL_MULT` 涨，×2.4 之后它会自己掉进海里，
	# 于是整段以 `LOSE` 收场 —— 那是脚手架的问题，不是被测行为。
	var hold: Vector3 = p.global_position
	for i in 360:
		await tree.physics_frame
		_hold_player(p, hold)
	t.gt(shots[0], 0, "挑战里的古斯塔夫真的会还手（6 秒内开火 %d 次）" % shots[0])

	for u in first:
		if is_instance_valid(u):
			u.ifield_hp = 0.0
			u.take_damage(99999.0, p, Damage.Type.BEAM)
	# ⚠️ 用户报的 bug 就发生在**这一瞬间**：第二台古斯塔夫爆掉的同一帧里，
	# `Game._evaluate_end()` 曾把"场上没有敌机"判成 WIN，于是结算页抢在刷下一波之前
	# 弹出来。所以这里**先立刻断言没判胜**，再等几帧看第二波有没有出来 ——
	# 只断言 20 帧之后的状态是抓不到这个 bug 的（那时空档已经被填上了）。
	t.ok(Game.phase != Game.Phase.WIN, "清空第一波的同一帧不能判胜（否则结算直接跳出来）")
	for i in 20:
		await tree.physics_frame
		_hold_player(p, hold)
	t.eq(Game.challenge_wave, 1, "第一波清空 → 自动进入第 2 波")
	t.ok(Game.phase != Game.Phase.WIN, "刷出第二波之后也不该判胜")
	var second: Array = main.get("wave_units")
	t.eq(second.size(), 1, "第二波一架")
	if not second.is_empty():
		var boss = second[0]
		t.eq(boss.profile.id, SuitProfile.Id.ARIZEUS, "第二波是阿利宙斯")
		t.gt(boss.global_position.y, p.global_position.y + 500.0,
			"阿利宙斯真的从**上方**出场（%.0f m vs 玩家 %.0f m）"
			% [boss.global_position.y, p.global_position.y])
		boss.ifield_hp = 0.0
		# BOSS 有**两条命**（1.2）：第一发打光外壳 → 爆壳脱出成核心（满血、无 I 立场），
		# 要再打一次才会坠机。这里等脱出 + 飞升突进走完，再补一发。
		boss.take_damage(999999.0, p, Damage.Type.BEAM)
		for i in 110:
			await tree.physics_frame
			_hold_player(p, hold)
		if is_instance_valid(boss) and boss.alive:
			t.ok(boss.escape_dash_active() or boss.form_index == SuitProfile.ArizeusForm.CORE_NU,
				"第一发只打掉外壳：BOSS 还活着且已经是核心形态")
			t.eq(boss.ifield_max, 0.0, "核心没有 I 立场")
			# ⚠️ 等无敌时段（爆壳掩护 1.3 s + 飞升突进 1.25 s）**真正走完**，
			# 而且必须**按条件等**，不能"等 N 帧"：`invuln_until` 比的是 `Game.clock`，
			# 而 `Game.clock` 由 main 的 `_process` 推进 —— headless 下物理帧远多于渲染帧，
			# 110 个物理帧只推进了 0.8 秒，于是"第二发"打在无敌上，
			# 看起来像"核心打不死、这一局不结算"。（这个假象我上一轮当成 bug 报给了用户，特此纠正。）
			for i in 900:
				if not is_instance_valid(boss) or not boss.alive or not boss.is_invulnerable():
					break
				await tree.physics_frame
				_hold_player(p, hold)
			t.not_ok(boss.is_invulnerable(), "脱出掩护会过去（核心不是永久无敌）")
			boss.take_damage(999999.0, p, Damage.Type.BEAM)
	for i in 30:
		await tree.physics_frame
		_hold_player(p, hold)
	t.eq(Game.phase, Game.Phase.WIN, "两波都清空 → 挑战过关")
	# 计数器这里放宽到 2..3：BOSS 现在有两条命，第一发只脱壳、第二发才坠机，
	# 而"第二发之后 `destroyed` 有没有在本次等待窗口内结算完"取决于帧数 ——
	# 真正要钉的是**结果**（phase == WIN，上一行），计数只是副产品。
	# ⚠️ 待办（下一轮）：把两段等待改成"等 `_transformed` + 等 `not alive`"的事件式等待，
	# 然后再把这一条收紧回 == 3。
	t.between(Game.challenge_killed, 3, 4, "击坠计数（古斯塔夫 3 + 阿利宙斯 0~1）")
	main.free()
	await tree.process_frame
	Game.active_challenge_id = ""
	Game.reset()


## 柯西的巡航变形（形态载体）与联机快照编码。
static func _morph_and_net(t: T, host: Node) -> void:
	# 巡航形态的**载体**：blend shape（morph）或**骨架**（骨骼形态层），至少一种。
	#
	# ⚠️ 2026-09-26 起柯西的载体换成了**骨骼**（`CruiseFormModifier`）——
	# 上游 GUIDE §6.7 的「morph 管形态、骨骼管过程」在新交付的三件 glb 上
	#（`blend shape = 0`）由骨骼承载。所以这条判据**不能**再钉死"必须有 blend shape"，
	# 否则它会把一次**正确的架构替换**判成回归，逼着人把好的改动退回去。
	var packed := load(SuitProfile.xi().model_path) as PackedScene
	t.ok(packed != null, "柯西模型能加载")
	if packed != null:
		var inst := packed.instantiate()
		var total := 0
		for c in inst.find_children("*", "MeshInstance3D", true, false):
			var am := (c as MeshInstance3D).mesh as ArrayMesh
			if am != null:
				total += am.get_blend_shape_count()
		var skel_n := inst.find_children("*", "Skeleton3D", true, false).size()
		t.ok(total > 0 or skel_n > 0,
			"柯西有巡航形态的载体：blend shape %d 个 / 骨架 %d 具（至少一种）" % [total, skel_n])
		inst.free()
	t.ok(SuitProfile.xi().cruise_morph, "柯西开了巡航变形")
	t.ok(SuitProfile.penelope().cruise_morph, "新版佩涅罗佩支持巡航变形")

	# 联机快照：编码 → 解码必须来回一致（这是联机最容易被静默写错的一段）
	var body := FlightBody.new()
	body.profile = SuitProfile.xi()
	host.add_child(body)
	body.global_position = Vector3(123.5, 3400.0, -78.25)
	body.global_transform = Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3.ONE),
		body.global_position)
	body.hp = 88.0
	body.ifield_hp = 0.0
	var pkt := Net.state_dict(body)
	var back := Net.unpack_state(pkt)
	t.near(back["position"].distance_to(body.global_position), 0.0, 0.001, "快照还原位置")
	t.near(back["hp"], 88.0, 0.001, "快照还原血量")
	t.near(back["ifield"], 0.0, 0.001, "快照还原护盾")
	t.eq(back["alive"], true, "快照还原生死")
	var d: float = (back["basis"].z - body.global_transform.basis.z).length()
	t.lt(d, 1e-4, "快照还原姿态（朝向差 %.6f）" % d)
	t.eq(Net.unpack_state({}).get("alive"), true, "空快照不会炸（解码要能容错）")
	body.free()
	await host.get_tree().process_frame
	Game.reset()


## 1.2：菜单的**步骤数**必须和实际流程一致（挑战也保留难度页）。
## 这一条是"隐藏难度"的回归门：早先挑战只有 3 步、没有难度页，
## 但 `_launch()` 照样把 `selected_level()` 传出去 —— 玩家看不见的难度真实生效。
static func _menu_steps(t: T) -> void:
	var m := MainMenu.new()
	# ⚠️ 本轮起"菜单里有哪些模式"由 `MainMenu.all_modes()` 回答（两层菜单：3 个分组 ×
	# 各自的形式），而"把菜单摆到某个模式"**必须走 `select_mode()`** —— 它把
	# "模式 → 分组 → 组内形式"一次摆好，且**找不到就什么都不改**（返回 false）。
	# 以前这里是 `m.set("mode_index", MainMenu.MODES.find(mode))`：一旦找不到就是 **−1**，
	# 而**负下标会取到最后一个元素**（联机），于是"挑战是 4 步"那几条会拿联机的步数去比，
	# 红得莫名其妙。`select_mode()` 那个 bool 返回值就是为这件事存在的。
	for mode: int in [Game.MatchMode.VERSUS, Game.MatchMode.SQUAD, Game.MatchMode.CHALLENGE,
			Game.MatchMode.TRAINING, Game.MatchMode.LAN]:
		# ⚠️ 判据是 `select_mode()` 的返回值（它自己就是"在不在菜单里"的答案）。
		# 1.2 第二十六轮剧情模式的入口被拿掉时，这一段靠这个 `continue` 活着；
		# 2026-09-29 入口已恢复 ⇒ 挑战那几条断言**现在就在真跑**（不再是"等它回来"）。
		if not m.select_mode(mode):
			continue
		var labels: Array = m.step_labels()
		t.eq(m.step_count(), labels.size(), "模式 %d 的步数与步骤条一致" % mode)
		if mode == Game.MatchMode.CHALLENGE:
			# ★ 轮 C（2026-09-29）：**剧情模式只有 1 步**。
			# 老板：「现在剧情模式的入口还是之前版本的。」
			# 之前那条链是 `Stage.SUIT → Stage.ENCOUNTER → Stage.DIFFICULTY`（旧挑战向导），
			# 而**机体页与遭遇页的选择在剧情模式下都不作数**（机体由 `Mission.player_suit` 定、
			# 关卡由战役图选）⇒ 那两页现在是"先做两个不作数的决定，再进战役图重做一遍"。
			# 现在：选完模式直接 `_launch()`，main 拦到战役图；**选关与难度都在那一页**。
			t.eq(labels.size(), 1, "★ 剧情模式是 1 步（选完模式就出击）—— 选关在**战役图**上")
			# ⚠️ 必须先**显式**把 `stage` 摆到模式页：这个循环是按模式复用的，
			# `stage` 还停在上一个模式（小队战）留下的那一页上 —— 不摆的话
			# 量到的是那一页的步骤条下标（实测第一次就拿到了 4）。
			m.set("stage", MainMenu.Stage.MODE)
			t.eq(m.step_index(), 0, "剧情模式只有第 ① 步（步骤条上只有一个点）")
			# ⚠️ 旧那三页**代码没删**（还有别的调用点与测试钉着它们），
			# 它们只是**剧情模式不再经过**。这一条钉的是"不再经过"这件事本身：
			# 可达页由上面的 `reach` 表给（只列 `Stage.MODE`）。
			m.set("stage", MainMenu.Stage.ENCOUNTER)
			t.eq(m.step_index(), 2,
				"（遭遇页仍在，`step_index()` 也照旧给 2 —— 它只是不再是剧情模式的一站）")
		elif mode == Game.MatchMode.VERSUS:
			t.eq(labels.size(), 5, "对战是 5 步（含选择敌人）")
			# 本轮：王牌战被收进「对战模式」子页 ⇒ 子页也要在流程里有个位置。
			# 它**算第 ① 步的一部分**（"选模式"这件事还没结束），所以步骤条不许 +
			# 一格（子页不是新的一步，`step_labels()` 因此一个字都不用改）。
			m.set("stage", MainMenu.Stage.BATTLE)
			t.eq(m.step_index(), 0, "对战模式子页算第 1 步（子页不是新的一步）")
			m.set("stage", MainMenu.Stage.DIFFICULTY)
			t.eq(m.step_index(), 3, "对战的难度页是第 4 步")
			m.set("stage", MainMenu.Stage.MAP)
			t.eq(m.step_index(), 4, "对战的地图页是第 5 步")
		elif mode == Game.MatchMode.SQUAD:
			# 编队战同样是 5 步，但第 2 步是**阵营**页（阵营决定这一边能开哪些机），
			# 所以机体页、难度页、地图页的步骤条下标都比王牌战后移一位。
			t.eq(labels.size(), 5, "小队战是 5 步（含选择阵营）")
			t.ok(str(labels[1]).contains("阵营"), "小队战的第 2 步是阵营页")
			m.set("stage", MainMenu.Stage.BATTLE)
			t.eq(m.step_index(), 0, "小队战也要经过对战模式子页")
			m.set("stage", MainMenu.Stage.SIDE)
			t.eq(m.step_index(), 1, "小队战的阵营页是第 2 步")
			m.set("stage", MainMenu.Stage.SUIT)
			t.eq(m.step_index(), 2, "小队战的机体页是第 3 步（阵营排在它之前）")
			m.set("stage", MainMenu.Stage.MAP)
			t.eq(m.step_index(), 4, "小队战的地图页是第 5 步")
		elif mode == Game.MatchMode.TRAINING:
			# ⚠️ 1.2 第二十五轮：训练从 2 步变 **3 步** ——
			# 多了「选训练项目」（自由打靶 / 新手教学）。
			# 用户要求「新手教学**和靶场在同一页面**」，所以它们不是两个模式，
			# 而是**同一页的两行**；步数因此 +1。
			t.eq(labels.size(), 3, "训练是 3 步（模式 → 机体 → 训练项目）")
		elif mode == Game.MatchMode.LAN:
			# ⚠️ 2026-10-11：联机从 **4 步**收回 **2 步**。
			# 用户：「**先创建房间之后，再在房间里面决定对战模式和机体**」
			# ⇒ 「选择阵营」「选择机体」两步搬进**房间界面**（`LOBBY_ROWS` 里那几行）。
			# 它们原先排在**建房之前**，等于逼玩家先做两个**随时会被房间设置推翻**
			# 的决定 —— 房间里一改对抗形式，机体表就换了（王牌战只认三台 ACE）。
			t.eq(labels.size(), 2, "联机是 2 步（模式 → 创建 / 加入房间）")
			# 步骤条索引必须跟着流程走（这几处最容易漏改，漏了步骤条会指错页）
			m.set("stage", MainMenu.Stage.LAN)
			t.eq(m.step_index(), 1, "联机页是第 2 步（下标 1）")
	# 挑战的遭遇表：柯西两场、另外两台各一场。
	#
	# ⚠️ 这一段的**前置**曾经是"挑战可能不在菜单里"（第二十二轮下半补的防护）：
	# 入口被拿掉时 `find(CHALLENGE)` 返回 **−1**，而**负下标会取到最后一个元素**（联机）——
	# 于是这一段会拿"联机的菜单"去查挑战遭遇表，`encounters()` 返回空，
	# 下面三条断言红得莫名其妙，还会在 `selected_encounter().id` 上崩（Nil）。
	# 2026-09-29 入口已恢复 ⇒ `select_mode()` 这一趟**为真**，下面三条在真跑；
	# `else` 那一支留着不删：它是"菜单里没有剧情入口"时唯一还能验的东西。
	# ⚠️ 判据是 `select_mode()` 的**返回值**（它自己就是"在不在菜单里"的答案），
	# 不再手写 `has()` + `find()` 那一对（`find()` 的 −1 正是上面那条坑的来源）。
	if m.select_mode(Game.MatchMode.CHALLENGE):
		m.set("suit_index", MainMenu.SUITS.find(SuitProfile.Id.XI))
		t.eq(m.encounters().size(), 2, "柯西在菜单里有两场遭遇可选")
		m.set("suit_index", MainMenu.SUITS.find(SuitProfile.Id.PENELOPE))
		t.eq(m.encounters().size(), 1, "佩涅罗佩只有一场")
		t.eq(m.selected_encounter().id, "PENELOPE_VS_XI", "选中的就是那一场")
	else:
		# 入口不在菜单里时，至少确认"挑挑战的遭遇表本身"还是好的
		#（那批断言在 `_challenge()` 里，与菜单无关）。
		t.eq(ChallengeScript.for_suit(SuitProfile.Id.PENELOPE).size(), 1,
			"（菜单无剧情入口）挑战脚本层：佩涅罗佩仍然只有一场")
	m.queue_free()


## 1.2：**版式的轴 == 输入的轴**，以及**步骤条必须反映真实流程**。
##
## 这一条锁的是用户实测报的 bug：
## 「这个位置明明是上下选的但是只能用 a 或 d」——
## 敌人页画的是 `map_row_rect()` 的竖排行，输入却走了 `_nav_x()`。
##
## ⚠️ 判据刻意**不写成"敌人页应该是竖轴"**（那只是把结论抄一遍，
## 下次给另一页换版式照样抓不住）。这里分两步：
##   1. 先用**画图那几个静态函数**真的量一遍版式是横是竖
##      （`_draw()` 用的就是同一份，所以量的是真版式，不是我记忆里的版式）；
##   2. 再要求 `nav_axis()` 与量出来的方向一致。
## 于是"换了版式却忘了改轴"会被这一步抓住。
static func _menu_axis(t: T) -> void:
	var view := Vector2(1600, 900)

	# ---- 1. 量版式：全工程唯一横排的是机体卡，其余都是竖排行 ----
	var cards := MainMenu.suit_card_rects(view)
	t.gt(cards.size(), 1, "机体页有多张卡")
	t.gt(cards[1].position.x, cards[0].position.x, "机体卡是**横排**（x 递增）")
	t.eq(cards[1].position.y, cards[0].position.y, "机体卡不是竖排（y 相同）")

	var row0 := MainMenu.map_row_rect(view, 0)
	var row1 := MainMenu.map_row_rect(view, 1)
	t.gt(row1.position.y, row0.position.y, "行版式是**竖排**（y 递增）")
	t.eq(row1.position.x, row0.position.x, "行版式不是横排（x 相同）")
	t.gt(MainMenu.mode_row_rect(view, 1).position.y,
		MainMenu.mode_row_rect(view, 0).position.y, "模式页也是竖排行")
	# 本轮新增的「对战模式」子页同样是竖排行（与模式页共用同一套版式）。
	t.gt(MainMenu.battle_row_rect(view, 1).position.y,
		MainMenu.battle_row_rect(view, 0).position.y, "对战模式子页也是竖排行")
	t.gt(MainMenu.difficulty_row_rect(view, 1).position.y,
		MainMenu.difficulty_row_rect(view, 0).position.y, "难度页也是竖排行")

	# ---- 2. 轴必须和版式一致 ----
	t.eq(MainMenu.nav_axis(MainMenu.Stage.SUIT), MainMenu.Nav.X,
		"机体页（卡片横排）用横轴")
	# ⚠️ `SIDE` 加进来是 2026-09-21 的事：它原来被写成 `Nav.X`（"两栏横排"），
	# 而 `_draw_side_stage()` 画的**一直是竖排行** —— 玩家按 W/S 没反应、
	# 按 A/D 才动，页脚提示还印着"A / D 选择阵营"（老板："选阵营的时候按键还是乱的"）。
	# 把它放进这个循环，这类"版式与轴相反"就再也不会只靠人记。
	for s: int in [MainMenu.Stage.SIDE, MainMenu.Stage.MODE, MainMenu.Stage.BATTLE,
			MainMenu.Stage.ENEMY,
			MainMenu.Stage.ENCOUNTER, MainMenu.Stage.DIFFICULTY, MainMenu.Stage.MAP,
			MainMenu.Stage.LAN, MainMenu.Stage.SETTINGS]:
		t.eq(MainMenu.nav_axis(s), MainMenu.Nav.Y, "竖排行的页（Stage %d）用竖轴" % s)

	# ---- 2b. 列表滚动窗口（"排版乱了"的机械判据）----
	#
	# 判据同样"量版式"：能放几行是 `rows_that_fit()` 算出来的，不是我背下来的数字。
	# 四张列表页（模式 / 对战模式子页 / 敌机 / 联机）当前的条目数**必须**放得下 ——
	# 那正是"行和底部操作说明叠在一起"这个 bug 的回归门；条目再多也只有滚动条，
	# 不会再压到面板上。
	#
	# ⚠️ 「模式」这一行取的是 `MODE_GROUPS.size()`（**4 组**），不是
	# `all_modes().size()`（5 个模式）—— 两层菜单之后这两个数不再是同一个数，
	# 拿 5 当行数用就会按 5 行去排版 4 行（最后一行凭空伸到面板外面）。
	for page: Array in [
			["模式", MainMenu.MODE_GROUPS.size(), MainMenu.MODE_ROW_H, MainMenu.MODE_ROW_GAP,
				MainMenu.MODE_ROW_MAX],
			["对战模式", MainMenu.battle_modes().size(), MainMenu.MODE_ROW_H,
				MainMenu.MODE_ROW_GAP, MainMenu.MODE_ROW_MAX],
			["敌机", MainMenu.ENEMY_SUITS.size(), MainMenu.ENEMY_ROW_H, MainMenu.ENEMY_ROW_GAP,
				MainMenu.ENEMY_ROW_MAX],
			["联机", MainMenu.LAN_ROWS.size(), MainMenu.LAN_ROW_H, MainMenu.LAN_ROW_GAP,
				MainMenu.LAN_ROW_MAX]]:
		var count: int = page[1]
		var min_h: float = page[2]
		var gap: float = page[3]
		var max_h: float = page[4]
		var vis: int = MainMenu.rows_that_fit(view, min_h, gap)
		var met := MainMenu.list_metrics(view, count, min_h, gap, max_h)
		t.ok(vis >= count, "%s页 %d 行全放得下（可见 %d 行）—— 不压页脚提示行"
			% [page[0], count, vis])
		if count <= vis:
			t.eq(MainMenu.scroll_window(count, count - 1, vis), Vector2i(0, count),
				"%s页放得下就**不滚动**（永远不动的滚动条会被当成「下面还有」）" % page[0])
		# 聚焦项必须永远在窗口里 —— 逐行扫，不抽样。
		for idx in count:
			var w := MainMenu.scroll_window(count, idx, vis)
			t.ok(idx >= w.x and idx < w.x + w.y,
				"%s页第 %d 项落在窗口 [%d, %d) 内（不然玩家看不见自己选到哪）"
				% [page[0], idx, w.x, w.x + w.y])
		# ---- 批 29：行高自适应 + 整块落在内容区里 ----
		# 行高在 [最小, 上限] 之间（行数少 ⇒ 放大，多 ⇒ 压回最小）。
		t.between(float(met["row_h"]), min_h, max_h + 0.001,
			"%s页行高在 [%.0f, %.0f] 之间（内容是自适应的，不是写死的）"
				% [page[0], min_h, max_h])
		# 行块不越出内容区（上不高于 PANEL_TOP、下不越 content_bottom）。
		t.gt(float(met["top"]), MainMenu.PANEL_TOP - 0.001,
			"%s页行块顶不高于内容区顶" % page[0])
		t.lt(MainMenu.list_bottom_y(0, int(met["shown"]), met),
			MainMenu.content_bottom(view) + 0.001, "%s页行块底不越出内容区底" % page[0])
	# 行矩形真的跟着窗口位移（"滚了但还画在原地"是这类实现的经典错法）。
	var m64 := MainMenu.list_metrics(view, 5, 64.0, 8.0, 64.0)
	t.gt(MainMenu.list_row_rect(view, 4, 2, m64).position.y,
		MainMenu.list_row_rect(view, 2, 2, m64).position.y, "窗口内逐行向下排")
	t.lt(MainMenu.list_bottom_y(0, 5, m64), MainMenu.content_bottom(view) + 0.001,
		"五行 64 高的行块不越出内容区底")
	# 提示行：批 29 起锚屏幕底边 —— 在内容区**之下**（不叠字）、且在屏幕内。
	t.gt(MainMenu.hint_y(view), MainMenu.content_bottom(view) - 0.001,
		"提示行在内容区之下（页脚带里，不跟列表叠字）")
	t.lt(MainMenu.hint_y(view), view.y - 10.0, "提示行在屏幕内")

	# ---- 批 24 新增：设置页与战斗BGM选歌页也吃同一套滚动窗口 ----
	# ⚠️ 批 29：行高会自适应，所以"放不下"这件事**跟屏幕高有关** ——
	# 900 高下 13 行全画得出来的（行高放大到 ~47 撑满内容区），
	# 720 高下才回落最小行高 + 滚动。两个方向都钉住：
	# 只钉"放不下"的话，"行高自适应"整个失效也没人发现。
	var tall := Vector2(1600, 900)
	var small := Vector2(1280, 720)
	t.eq(int(MainMenu.settings_metrics(tall)["shown"]), MainMenu.SETTING_ROWS.size(),
		"900 高下设置页 %d 行全画得出来（行高自适应撑满内容区）" % MainMenu.SETTING_ROWS.size())
	var set_vis: int = int(MainMenu.settings_metrics(small)["shown"])
	t.ok(set_vis < MainMenu.SETTING_ROWS.size(),
		"720 高下设置页放不下（可见 %d < %d）—— 滚动窗口是真在用的，不是摆设"
			% [set_vis, MainMenu.SETTING_ROWS.size()])
	for idx in MainMenu.SETTING_ROWS.size():
		var sw := MainMenu.scroll_window(MainMenu.SETTING_ROWS.size(), idx, set_vis)
		t.ok(idx >= sw.x and idx < sw.x + sw.y,
			"设置页第 %d 项落在窗口 [%d, %d) 内（720 高）" % [idx, sw.x, sw.x + sw.y])
	# 设置面板高度按可见行数算 —— 面板底不许越出内容区底。
	var sp := MainMenu.settings_panel_rect(tall)
	t.lt(sp.position.y + sp.size.y, MainMenu.content_bottom(tall) + 1.0,
		"设置面板底不越出内容区（高度按可见行数算，不按总行数）")
	# 选歌页选项序列与 Settings 的循环序列同源：0 = 随机，其后与曲池同序。
	var pick_keys: Array = MainMenu.bgm_pick_keys()
	var want_pick: Array = [""]
	want_pick.append_array(SoundBank.battle_pick_tracks())
	t.eq(pick_keys.size(), want_pick.size(),
		"选歌页选项数 = 1（随机）+ 自选列表（轮换池 + 仅自选曲）")
	t.eq(str(pick_keys[0]), "", "选歌页第 0 项 = 随机")
	var same_order := true
	for k in want_pick.size():
		if str(pick_keys[k]) != str(want_pick[k]):
			same_order = false
	t.ok(same_order,
		"选歌页与 Settings 的自选序列**逐位一致**（四个消费方共用一份序列，不许分叉）")

	# ---- 3. 步骤条：每一页的下标都必须落在**本流程**的步数之内 ----
	# 旧步骤条自己硬编码了一份 4 项列表，而 `step_index()` 在地图页返回 4 ——
	# "⑤ 选择地图"那一点永远亮不起来；联机页返回 −1，一个点都不亮。
	# 这两条症状就是这一步的回归门。
	#
	# 只查**该模式下真的走得到**的页：训练模式永远走不到敌人/难度/地图页，
	# 拿它们去比步数只会得到一个假的失败。
	var reach := {
		# 对战模式那一组多一页：**「对战模式」子页**（选王牌战 / 小队战）。
		Game.MatchMode.VERSUS: [MainMenu.Stage.MODE, MainMenu.Stage.BATTLE,
			MainMenu.Stage.SUIT, MainMenu.Stage.ENEMY, MainMenu.Stage.DIFFICULTY,
			MainMenu.Stage.MAP],
		Game.MatchMode.SQUAD: [MainMenu.Stage.MODE, MainMenu.Stage.BATTLE,
			MainMenu.Stage.SIDE, MainMenu.Stage.SUIT, MainMenu.Stage.DIFFICULTY,
			MainMenu.Stage.MAP],
		# ★ 轮 C：剧情模式**只有一页**（模式页）—— 选关 / 难度搬到战役图上了。
		# 旧那三页（机体 / 遭遇 / 难度）仍在代码里，但**剧情模式下走不到**；
		# 这里只列"该模式下真的走得到"的页 ⇒ 拿旧三页来比会得到一个假的失败。
		Game.MatchMode.CHALLENGE: [MainMenu.Stage.MODE],
		# 训练也有自己的项目页（自由打靶 / 新手教学），一起钉进来。
		Game.MatchMode.TRAINING: [MainMenu.Stage.MODE, MainMenu.Stage.SUIT,
			MainMenu.Stage.TRAINING],
		# 联机 **2026-10-11 起只有两页**：模式页 → 联机页。
		# 用户：「先创建房间之后，再在房间里面决定对战模式和机体」
		# ⇒ 阵营 / 机体两页**搬家到房间界面**（`LOBBY_ROWS`），联机不再经过它们。
		# ⚠️ 这两页的**代码没删**（小队战那条链还在用），只是联机走不到 ——
		# 所以这里只列"真的走得到"的页（拿旧两页来比 = 一个假的失败）。
		Game.MatchMode.LAN: [MainMenu.Stage.MODE, MainMenu.Stage.LAN],
	}
	var m := MainMenu.new()
	for mode: int in reach:
		# ⚠️ 1.2 第二十六轮：**剧情模式的入口从菜单里拿掉了**（功能保留）。
		# 所以这里只测"菜单里真有的模式" —— 判据是 `select_mode()` 的返回值：
		# 它找不到就**什么都不改**，于是 `mode_index` 不会变成 −1 然后取到最后一个元素
		#（联机）—— 那样测的其实是另一个模式。
		if not m.select_mode(mode):
			continue
		var n: int = m.step_count()
		for s: int in reach[mode]:
			m.set("stage", s)
			var idx: int = m.step_index()
			t.ok(idx >= 0 and idx < n,
				"模式 %d / 页 %d：步骤条下标 %d 落在 %d 步之内（−1 或越界 = 那一点永远不亮）"
				% [mode, s, idx, n])

	# ---- 剧情模式的入口：1.2 第二十六轮隐藏 → 2026-09-29 恢复 ----
	# 老板（1.2）："把剧情模式在 1.2 版本隐藏起来：功能保留着，入口删掉。"
	# 老板（2026-09-29）："可以恢复剧情模式的菜单入口了"（数据层轮 0 / A / B 已落）。
	# 两条一起钉：① 入口里**有**它；② 功能链的关键件都还在（不然"恢复"等于空话）。
	t.ok(MainMenu.all_modes().has(Game.MatchMode.CHALLENGE),
		"剧情模式**在菜单入口里**（已恢复）")
	t.eq(MainMenu.all_modes().size(), 6,
		"菜单入口六种（王牌战 / 小队战 / 剧情挑战 / 强化演习 / 训练 / 联机）")
	# ---- 两层菜单的"两个数必须分开" ----
	# `all_modes().size()`（6 = 工程里有几种模式）与 `MODE_GROUPS.size()`
	#（5 = 模式页几行）**不再是同一个数**。把 6 当行数用，排版就按 6 行去算 5 行，
	# 最后一行会凭空伸到面板外面（`suite_menu_frame` 量行矩形时会红，但那是间接证据，
	# 所以在这里正面钉一条）。
	#
	# ⚠️ ★63-24（无限强化演习）加了一组「强化演习」⇒ 这两个数**再一次同时变大**
	#（4→5 / 5→6）而**依旧不相等** —— 这正是本条存在的理由：
	# 加了一组就回来看一眼版式，别顺手把两个数合成一个用。
	t.eq(MainMenu.MODE_GROUPS.size(), 5,
		"模式页是 5 行（对战 / 剧情挑战 / 强化演习 / 训练 / 联机）")
	t.ok(MainMenu.all_modes().has(Game.MatchMode.ENDLESS),
		"强化演习**在**菜单入口里（★63-24）")
	t.ok(MainMenu.Stage.ENCOUNTER > 0,
		"……遭遇页这一页**在**（枚举与绘制都没删）—— 只是剧情模式不再经过它")
	t.ok(Game.MatchMode.CHALLENGE is int,
		"……`Game.MatchMode.CHALLENGE` 也在（枚举删了会连锁断掉波次与结算）")

	# ---- 4. 纵向方向：菜单的"上"必须是 W / ↑ ----
	# 锁的是用户实测报的第二个 bug：
	# 「整个主菜单的上下选择都是颠倒的，按 s 往上按 w 往下」。
	# 根因是**飞行约定与菜单约定被混用** —— 动作名按飞行语义起
	# （`pitch_nose_up` = 拉杆 = S / ↓），菜单却直接把它当成了"上"。
	#
	# ⚠️ 判据同样**不抄结论**（不写"NAV_UP_ACTIONS[0] 应该是 pitch_nose_down"），
	# 而是去问**键位表**：把"上"那一组动作实际绑定的物理键收集起来，
	# 要求里面有 W 和 ↑。于是"改了 W/S 的绑定却没同步菜单"也会被抓住。
	var up_keys: Array = []
	for a: String in MainMenu.NAV_UP_ACTIONS:
		if InputSetup.BINDINGS.has(a):
			up_keys.append_array(InputSetup.BINDINGS[a])
	var down_keys: Array = []
	for a: String in MainMenu.NAV_DOWN_ACTIONS:
		if InputSetup.BINDINGS.has(a):
			down_keys.append_array(InputSetup.BINDINGS[a])
	t.ok(up_keys.has(KEY_W), "菜单的『上』由 W 点亮")
	t.ok(up_keys.has(KEY_UP), "菜单的『上』由 ↑ 点亮")
	t.ok(down_keys.has(KEY_S), "菜单的『下』由 S 点亮")
	t.ok(down_keys.has(KEY_DOWN), "菜单的『下』由 ↓ 点亮")
	# 反向：同一批键不得同时出现在两边 —— 那会变成"按一下不知道往哪走"，
	# 和早先 Q/E 同时喂给两个轴是同一类 bug。
	for k: int in up_keys:
		t.not_ok(down_keys.has(k),
			"键 %s 不能同时属于『上』和『下』" % OS.get_keycode_string(k))

	# ---- 5. 方向本身：那一组动作真的意味着"上" ----
	# ⚠️ 上面 4 条只锁住了"哪组动作绑了哪些键"，**没锁住正负号** ——
	# 把 `_nav_y()` 的 −1/+1 写反，上面照样全绿，而 bug 原样复现。
	# 这一层用纯函数测，不需要注入输入（无头环境注入 `just_pressed` 不可靠）。
	t.eq(MainMenu.nav_delta_y(["pitch_nose_down"]), -1, "W / ↑ 那一组 → 上（−1）")
	t.eq(MainMenu.nav_delta_y(["pitch_nose_up"]), 1, "S / ↓ 那一组 → 下（+1）")
	t.eq(MainMenu.nav_delta_y(["switch_target"]), -1, "Tab → 上")
	t.eq(MainMenu.nav_delta_y(["flares"]), 1, "C → 下")
	t.eq(MainMenu.nav_delta_y([]), 0, "没按键 → 0（这一层要交回摇杆兜底）")
	# 上下同按：以上优先（数组顺序），且**必须给一个非 0 的方向** ——
	# 返回 0 会让这一帧被摇杆兜底接管，表现是"按了两个键反而跳一下"。
	t.eq(MainMenu.nav_delta_y(["pitch_nose_up", "pitch_nose_down"]), -1, "上下同按以上优先")
	m.queue_free()


static func _key(host: Node, key: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = pressed
	Input.parse_input_event(ev)
	await host.get_tree().process_frame
	await host.get_tree().process_frame


## 把 `_challenge` 里那个"假玩家"**钉在半空**（位置不动）。
##
## ## 为什么必须钉
## 那段测试里玩家只是个"被瞄准 / 被追击"的靶子，**不参与飞行**（它的操纵全程无输入）。
## 而窗口是按**时间**给的（6 秒 / 若干帧）—— 时间是按人的体感定的、**不跟着提速变**，
## 但无人操纵的飞机在这段时间里飞过的**距离**会跟着 `SuitProfile.SPEED_REAL_MULT` 涨：
##
## | 倍率 | 射击窗口那 6 秒 | 整段累计（≈17 s） |
## |---|---|---|
## | ×1.5 | 8.5 km | 24 km |
## | **×2.4** | **13.6 km** | **38 km** |
##
## 实测 ×2.4 之后这架柯西在窗口内就掉进海里（日志 `[destroy] 柯西高达: 撞海`；
## 判据是 `FlightBody.CRASH_ALTITUDE = 24 m`），于是整段以 `LOSE` 收场 ——
## "两波都清空 → 挑战过关" 读到 `got=4 want=3`（4 = `Game.Phase.LOSE`）。
##
## ## 两个附带的好处
##   ① 玩家不会再飞出古斯塔夫的步枪射程（否则"它们到底有没有还手"会变成
##      一个看帧数运气的断言）；
##   ② "BOSS 从上方的玩家出场"那条断言的参照点固定下来。
##
## ⚠️ 钉的是**位置**，不是"把速度归零"：速度归零会让 `stalled` 等一堆状态
## 跟着变（那是另一套行为），而这里只想让"靶子别跑"这一件事成立。
static func _hold_player(p: Node3D, at: Vector3) -> void:
	if is_instance_valid(p):
		p.global_position = at


# Return now includes staged map generation and a timed loading-screen fade.
static func _await_menu_loading(host: Node, main: Node) -> void:
	var started := Time.get_ticks_msec()
	while bool(main.get("_transition_busy")) and Time.get_ticks_msec()-started<30000:
		await host.get_tree().process_frame
