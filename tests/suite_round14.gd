class_name SuiteRound14
extends RefCounted
## 第十四轮（1.1）回归门：玩家反馈台账 `gundam-round14-player-feedback.md` 里
## **A 包 + B 包**的每一改动各一组断言，再加老板中途追加的光照要求。
##
## 这一套的写法沿用工程既有规矩：**每条都冲着"旧行为下必红"去的**。
## 所以每条断言旁边都写清楚"旧的是什么"，否则过两轮就没人知道它为什么存在。
##
## 分组与方案文档的编号一一对应：
##   A1 夜海可读性 · A2 拉起告警 · A3 摇杆死区与滚转回正
##   A5 云影（自机/敌机/地表/海面共用一个场）· 光照（自机比环境更黑）
##   B5 敌机速度天花板 · B6 军刀空挥回收

static func run(t: T, host: Node) -> void:
	t.suite("Round14 / A1 夜海：看得见，且分得出地平线")
	_night_ocean(t)

	t.suite("Round14 / A2 拉起告警：按预测高度触发、带数字")
	_pull_up(t)

	t.suite("Round14 / A3 摇杆死区与滚转回正")
	_roll_assist(t, host)

	t.suite("Round14 / A5 云影与自机压暗")
	await _cloud_shade(t, host)

	t.suite("Round14 / B5 敌机速度天花板")
	await _speed_ceiling(t, host)

	t.suite("Round14 / B6 军刀空挥回收")
	await _saber_recovery(t, host)

	t.suite("Round14 / C1 辅助模式：压杆不夺杆，一松手立刻改出")
	await _assist_ground_guard(t, host)

	t.suite("Round14 / C2 艾尔斯岩地面是暗红色（不是灰）")
	await _desert_dark_red(t, host)

	t.suite("Round14 / C3 太平洋群岛删掉小岛（海面保留）")
	await _pacific_no_islands(t, host)

	Game.reset()


# ============================================================ A1

static func _night_ocean(t: T) -> void:
	var night := TimeOfDay.night()
	var day := TimeOfDay.day()

	# ① 抬亮。旧值是 ocean_deep = (0.004, 0.012, 0.030) —— 近似纯黑。
	t.gt(night.ocean_deep.g, 0.030, "夜海深色抬亮到可读（旧值 0.012，基本是纯黑）")
	t.gt(night.ocean_crest.b, 0.15, "夜海浪峰跟着抬亮（旧值 0.095）")
	# ② 仍然保持"夜比昼暗"（别为了看得见把夜战改成白天）
	t.lt(night.ocean_deep.r, day.ocean_deep.r, "夜海仍然比白天暗")
	t.lt(night.ocean_sky.r, day.ocean_sky.r, "夜海反射的天色仍然比白天暗")

	# ③ **海天亮度分离** —— 这一条才是"地平线看得见"的判据。
	#    旧值：海面地平 0.090 vs 天空地平 0.070（1.29 倍，糊在一起）。
	var ratio := night.ocean_horizon.g / maxf(night.sky_horizon.g, 0.0001)
	t.gt(ratio, 1.5,
		"夜海的地平色明显亮于天空地平色（%.2f 倍）—— 只抬亮不拉开这一档，地平线照样找不到" % ratio)

	# ④ 月光镜面带：解决"哪个方向是水"
	t.gt(night.ocean_glitter, 0.0, "夜晚打开月光镜面带")
	t.near(day.ocean_glitter, 0.0, 0.0001, "白天不开镜面带（太阳直射的高光本来就够亮）")
	t.between(night.ocean_glitter_sharp, 8.0, 512.0, "镜面高光的锐度在 shader 允许的范围内")

	# ⑤ 天体方向：镜面带的方向源，必须是可算的纯函数
	var moon := WorldBuilder.celestial_dir(night.sun_rotation_deg)
	t.near(moon.length(), 1.0, 0.001, "天体方向是单位向量")
	t.gt(moon.y, 0.5, "夜里天体在地平线之上（月光确实是从上方照下来的）")
	t.not_ok(WorldBuilder.celestial_dir(day.sun_rotation_deg).is_equal_approx(moon),
		"换时段天体方向真的变了（不是把同一个常量抄两遍）")


# ============================================================ A2

static func _pull_up(t: T) -> void:
	# 旧判据 = "当前高度 < 420 且机头没有上仰（forward().y < 0.05）"。
	# 它在**俯冲进海**这一类上是不报的：高度还在 500 m，人已经快贴水了。
	t.lt(FlightHUD.pull_up_clearance(500.0, -200.0), FlightHUD.PULL_UP_ALTITUDE,
		"500 m 但以 −200 m/s 下坠 → 预测高度已低于告警线（旧判据在这里不报）")
	t.lt(FlightHUD.pull_up_clearance(300.0, 0.0), FlightHUD.PULL_UP_ALTITUDE,
		"低空平飞要报（和旧判据一致的部分）")
	t.gt(FlightHUD.pull_up_clearance(2000.0, 0.0), FlightHUD.PULL_UP_ALTITUDE,
		"高空平飞不报")
	t.gt(FlightHUD.pull_up_clearance(300.0, 200.0), FlightHUD.PULL_UP_ALTITUDE,
		"300 m 但在爬升 → 不报（预测高度高于当前高度，所以不需要再单独判机头朝向）")
	t.near(FlightHUD.PULL_UP_LOOKAHEAD, BanditAI.PULL_UP_LOOKAHEAD, 0.0001,
		"玩家告警与 AI 避地用的是同一个外推时间（两套数就会互相矛盾）")


# ============================================================ A3

static func _roll_assist(t: T, host: Node) -> void:
	# ---- 死区：这是"手没碰摇杆、机子自己在转圈"的直接原因 ----
	t.gt(PlayerController.PAD_DEADZONE, 0.19,
		"摇杆死区 ≥ 0.20（旧值 0.12 会把旧手柄的回中误差逐帧积分成持续滚转）")
	t.near(PlayerController._dead(0.15), 0.0, 0.0001,
		"死区内的偏移视为 0 —— 这条就是那个一直顺时针转的回归门")
	t.near(PlayerController._dead(0.40), 0.40, 0.0001, "死区外原样透传，不会被削成阶梯")
	t.near(PlayerController._dead(0.19), 0.0, 0.0001, "刚好在死区内侧仍然归零")
	t.near(PlayerController._dead(0.15, PlayerController.PAD_DEADZONE_YAW), 0.0, 0.0001,
		"偏航那一档的死区也起作用")

	# ---- 滚转回正 ----
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.profile = SuitProfile.xi()
	pc.is_player = true
	pc.team = 0
	pc.roll_level_assist = true
	c.add_child(pc)
	# 自己手动喂 delta，不让物理帧跑飞行模型（否则机体会自己动，量出来的坡度是别人的）
	pc.set_physics_process(false)
	pc.global_transform = Transform3D(Basis(Vector3.FORWARD, deg_to_rad(45.0)), Vector3(0, 3000, 0))

	var bank: float = pc.call("_bank_angle")
	t.near(absf(bank), PI * 0.25, 0.02, "45° 坡度能量出来（实得 %.1f°）" % rad_to_deg(absf(bank)))

	# ① 玩家在滚 → 原样透传，空闲计时清零
	t.near(pc.call("_roll_assist", 0.5, 0.1), 0.5, 0.0001, "玩家在滚时原样透传输入，不做任何干预")
	# ② 刚松杆 → 还不介入（短暂松杆是正常操纵）
	t.near(pc.call("_roll_assist", 0.0, 0.1), 0.0, 0.0001, "松杆 0.1 s 不介入")
	# ③ 松杆满延迟 → 给出与坡度反向的修正
	var corr := 0.0
	for i in 12:
		corr = pc.call("_roll_assist", 0.0, 0.1)
	t.not_ok(is_zero_approx(corr),
		"松杆满 %.1f s 后开始回正（实得修正 %.3f）" % [PlayerController.ROLL_LEVEL_DELAY, corr])
	t.lt(corr * bank, 0.0, "回正方向与坡度相反（bank=%.3f corr=%.3f）" % [bank, corr])
	# ④ 关掉辅助 → 再也不会介入
	pc.roll_level_assist = false
	t.near(pc.call("_roll_assist", 0.0, 0.1), 0.0, 0.0001, "关掉辅助后不再回正")

	c.free()


# ============================================================ A5 + 光照

static func _cloud_shade(t: T, host: Node) -> void:
	var w := WorldBuilder.new()
	w.initial_map = MapDef.Id.PACIFIC
	host.add_child(w)
	await host.get_tree().process_frame

	# ---- 覆盖图真的烘出来了 ----
	var res := WorldBuilder.CLOUD_FIELD_RES
	var field: PackedFloat32Array = w.get("_cloud_field")
	t.eq(field.size(), res * res, "云影覆盖图烘出来了（%d² 网格）" % res)
	var ft = w.get("_cloud_shade_tex")
	t.ok(ft is ImageTexture, "覆盖图上传成了纹理（GPU 侧地表/海面要采样它）")

	# ---- 场里确实有深格子，而且世界坐标查得回来 ----
	var best := 0.0
	var bi := 0
	for i in field.size():
		if field[i] > best:
			best = field[i]
			bi = i
	t.gt(best, 0.2, "场上有明显的云影格（最深 %.2f）" % best)
	var cell: float = w.cloud_field_span / float(res)
	var wx := (float(bi % res) + 0.5) * cell - w.cloud_field_span * 0.5
	var wz := (float(bi / res) + 0.5) * cell - w.cloud_field_span * 0.5
	t.gt(w.cloud_shade_at(Vector3(wx, 9000.0, wz)), 0.2, "最深那格的世界坐标查出来就是有云影")
	t.near(w.cloud_shade_at(Vector3(1000000.0, 9000.0, 1000000.0)), 0.0, 0.0001,
		"覆盖图之外是 0（云只撒在竞技场半径内）")

	# ---- uniform 真的灌进去了（不是只在本地变量里改了个值）----
	#
	# ⚠️ **判据要分地图看**（第十四轮踩到）：群岛图的岛删掉之后，那张图的地表
	# **只剩海面**，而海面走的是 `_ocean_mat`（另一条线），**不进 `_terrain_mats`**。
	# 所以"地表材质拿到了云影"这条必须用**有地表材质**的图（沙漠）来测 ——
	# 否则会得到一个 `0 > 0` 的假红（第一版就是这样红的）。
	var om = w.get("_ocean_mat")
	t.ok(om is ShaderMaterial, "海面是 ShaderMaterial（云影与镜面带都要靠它）")
	if om is ShaderMaterial:
		t.gt(float((om as ShaderMaterial).get_shader_parameter("cloud_shade_strength")), 0.0,
			"海面接上了云影（删岛之后，海面就是这张图唯一的地表）")
		t.gt(float((om as ShaderMaterial).get_shader_parameter("glitter_strength")), 0.0,
			"夜海打开了月光镜面带（uniform 真的传进去了）")

	w.apply_map(MapDef.uluru())
	await host.get_tree().process_frame
	var mats: Array = w.get("_terrain_mats")
	t.gt(mats.size(), 0, "沙漠图的地表材质登记进了云影名单（%d 份）" % mats.size())
	var wired := 0
	for m in mats:
		if float((m as ShaderMaterial).get_shader_parameter("cloud_shade_strength")) > 0.0:
			wired += 1
	t.eq(wired, mats.size(), "每一份地表材质都拿到了云影强度（%d/%d）" % [wired, mats.size()])

	# ---- 自机压暗 + 机体云影（CPU 那条路）----
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.profile = SuitProfile.xi()
	pc.is_player = true
	pc.team = 0
	c.add_child(pc)
	pc.set_physics_process(false)
	await host.get_tree().physics_frame

	var shade_mats: Array = pc.get("_shade_mats")
	var bases: Array = pc.get("_shade_base")
	t.gt(shade_mats.size(), 0, "自机的每个 surface 都留了一份可改的材质")
	t.eq(bases.size(), shade_mats.size(), "原值数组与材质数组一一对应（云影要从原值算，不能一路乘下去）")

	var src := _first_source_material(pc)
	t.ok(src != null, "拿得到模型原始材质（对照用）")
	if src != null:
		var m0 := shade_mats[0] as StandardMaterial3D
		t.near(m0.albedo_color.r / maxf(src.albedo_color.r, 0.0001),
			FlightBody.PLAYER_ALBEDO_SCALE, 0.01,
			"自机反照率 = 原始 ×0.6（老板要求：玩家主体比环境更黑）")
		t.near(m0.albedo_color.a, src.albedo_color.a, 0.0001,
			"alpha 没被一起乘掉（Color * float 会连 alpha 一起乘，这是个真坑）")

	var m0b := shade_mats[0] as StandardMaterial3D
	var base0: Color = bases[0]
	var r0 := m0b.albedo_color.r
	pc.set_cloud_shade(1.0)
	t.near(m0b.albedo_color.r, base0.r * (1.0 - FlightBody.CLOUD_SHADE_DEPTH), 0.001,
		"云影打在自机身上：albedo 真的被乘下去了")
	pc.set_cloud_shade(0.0)
	t.near(m0b.albedo_color.r, base0.r, 0.001,
		"出了云影恢复原值（不是在一路乘下去 —— 那样几秒就全黑）")
	t.near(m0b.albedo_color.r, r0, 0.001, "云影来回不会改变最终颜色")

	# ---- 敌机只改暖色，不压暗 ----
	var foe := FlightBody.new()
	foe.team = 1
	foe.profile = SuitProfile.penelope()
	foe.projectile_container = c
	c.add_child(foe)
	await host.get_tree().physics_frame
	var foe_src := _first_source_material(foe)
	var foe_mats: Array = foe.get("_shade_mats")
	if foe_src != null and foe_mats.size() > 0:
		var fm0 := foe_mats[0] as StandardMaterial3D
		t.not_ok(is_equal_approx(fm0.albedo_color.r / maxf(foe_src.albedo_color.r, 0.0001),
			FlightBody.PLAYER_ALBEDO_SCALE),
			"敌机不走自机那条压暗（它只有一段很轻的暖色偏移）")
		t.lt(fm0.albedo_color.b, foe_src.albedo_color.b + 0.0001, "敌机的蓝通道被暖色偏移压低")

	c.free()
	w.free()
	await host.get_tree().process_frame


## 取模型第一个 surface 的**原始**材质。
## `_apply_owner_materials()` 走的是 `set_surface_override_material`，
## 所以 mesh 自己的材质没有被改过 —— 它就是"原始值"的可靠来源。
static func _first_source_material(fb: FlightBody) -> StandardMaterial3D:
	var root = fb.get("model_root")
	if root == null or not is_instance_valid(root):
		return null
	for n: Node in (root as Node).find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var m := mi.mesh.surface_get_material(0)
		if m is StandardMaterial3D:
			return m as StandardMaterial3D
	return null


# ============================================================ B5

static func _speed_ceiling(t: T, host: Node) -> void:
	var easy := Difficulty.make(Difficulty.Level.EASY)
	var normal := Difficulty.make(Difficulty.Level.NORMAL)
	var hard := Difficulty.make(Difficulty.Level.HARD)
	var xi := SuitProfile.xi()

	t.near(SuitProfile.enemy_speed_ceiling(xi.player_boost_speed()),
		xi.player_boost_speed() * SuitProfile.ENEMY_SPEED_CEILING_RATIO, 0.01,
		"天花板 = 玩家加力上限 ×0.92（留 8% 追击余量：只是更快而追不近，等于没修）")

	# ---- 全组合不变量：玩家机体 × 敌机机体 × 难度 ----
	#
	# 这就是方案里那条"把追不上从手感问题变成红线"的门。
	# 旧行为下（没有天花板）中等/困难的佩涅罗佩与阿利宙斯巡航态**必然红**。
	var players: Array[SuitProfile] = [
		SuitProfile.xi(),
		SuitProfile.penelope(),
		SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE),
	]
	var enemies: Array[SuitProfile] = [
		SuitProfile.xi(),
		SuitProfile.penelope(),
		SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE),
	]
	var bad := 0
	var worst := ""
	for p: SuitProfile in players:
		for e: SuitProfile in enemies:
			for d: Difficulty in [easy, normal, hard]:
				var capped: float = e.enemy_top_speed_capped(d.speed_mult, p.player_boost_speed())
				if capped > p.player_boost_speed() * 0.95:
					bad += 1
					worst = "%s vs %s @%s = %.0f" % [e.display_name, p.display_name, d.name_cn, capped]
	t.eq(bad, 0,
		"玩家机体 × 敌机机体 × 难度 的**全部组合**都满足：敌机上限 ≤ 玩家加力 ×0.95（例外 %d%s）"
			% [bad, "" if worst.is_empty() else "，例如 " + worst])
	# 难度契约本身没被抹掉：简单难度下柯西敌机仍然是"基准 × 机体速度系数"的原始值
	#（2026-09-22：柯西 speed_scale 上调到 1.50 —— 断言改成符号式，不再写死 420）
	t.near(xi.enemy_top_speed_capped(easy.speed_mult, xi.player_boost_speed()),
		xi.enemy_top_speed(easy.speed_mult), 0.01,
		"简单难度柯西敌机 = 原始难度表（没被天花板碰到）")
	t.near(xi.enemy_top_speed(hard.speed_mult),
		SuitProfile.XI_REFERENCE_SPEED * hard.speed_mult * xi.speed_scale
			* SuitProfile.SPEED_REAL_MULT, 0.01,
		"难度表的**原始**契约原样保留（菜单数值列读的还是它；显示域由 speed_to_display 除回去）")

	# ---- 走真实路径：AI 实际配出来的速度上限 ----
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.profile = SuitProfile.xi()
	pc.is_player = true
	pc.team = 0
	c.add_child(pc)
	pc.set_physics_process(false)
	await host.get_tree().physics_frame

	var ai := BanditAI.new()
	ai.name = "Round14Bandit"
	ai.team = 1
	ai.profile = SuitProfile.penelope()
	ai.difficulty = normal
	ai.projectile_container = c
	c.add_child(ai)
	await host.get_tree().physics_frame

	var ceiling: float = SuitProfile.xi().player_boost_speed() * 0.95
	t.lt(ai.fm.max_speed, ceiling,
		"中等难度佩涅罗佩敌机的**实际**上限被压住（%.0f < %.0f）—— 旧行为这里是 737 m/s，而玩家只有 630"
			% [ai.fm.max_speed, ceiling])
	t.gt(ai.fm.max_speed, SuitProfile.xi().player_top_speed(),
		"但仍然比玩家**巡航**上限快（%.0f > %.0f）：必须用加力才追得上，难度感没被抹平"
			% [ai.fm.max_speed, SuitProfile.xi().player_top_speed()])

	c.free()
	await host.get_tree().process_frame
	Game.reset()


# ============================================================ B6

static func _saber_recovery(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)

	# ---- ① 玩家空挥：宽限期后必须交还控制权（旧行为是笔直飞满 2.4 s）----
	var me := _unit(c, SuitProfile.xi(), 0, true)
	me.global_position = Vector3(0, 3000, 0)
	t.ok(me.try_saber(null), "空挥可以起手")
	var frames := 0
	while me.saber_active() and frames < 200:
		await host.get_tree().physics_frame
		frames += 1
	t.not_ok(me.saber_active(), "空挥会结束（不会一直挂在突进状态）")
	t.lt(float(frames) / 60.0, 1.0,
		"空挥占用时间 < 1.0 s（实得 %.2f s；旧行为是整整 2.4 s 的直线冲刺）" % (float(frames) / 60.0))
	t.gt(float(frames) / 60.0, FlightBody.SABER_MISS_GRACE - 0.15,
		"宽限期内确实留了起手窗口（实得 %.2f s，不是按下就取消）" % (float(frames) / 60.0))
	# 冷却照旧：空挥不是免费的
	t.not_ok(me.try_saber(null), "空挥照样吃冷却（收回控制权不等于这一刀没成本）")

	# ---- ② 有吸附目标时**不**被宽限期打断 ----
	var me2 := _unit(c, SuitProfile.xi(), 0, true)
	me2.global_position = Vector3(0, 3000, 0)
	var foe := _unit(c, SuitProfile.penelope(), 1)
	foe.global_position = Vector3(0, 3000, -1200)
	t.ok(me2.try_saber(foe), "锁定目标在 1200 m（吸附范围内）时可以起手")
	t.eq(me2.saber_target, foe, "确实吸附上了")
	var f2 := 0
	while me2.saber_active() and f2 < 40:
		await host.get_tree().physics_frame
		f2 += 1
	t.ok(me2.saber_active(),
		"有吸附目标时宽限期不中断突进（第 %d 帧仍在突进 —— 否则『远处砍不到』会回来）" % f2)

	# ---- ③ 空挥回收是**玩家专属**：AI 的突进时长不能被带跑 ----
	#    AI 突进期间不接受转向、没有避地能力，"中途放开"会重现"AI 一头扎海"。
	var bot := _unit(c, SuitProfile.xi(), 1)
	bot.global_position = Vector3(0, 4000, 0)
	t.ok(bot.try_saber(null), "AI 侧空挥同样能起手")
	var f3 := 0
	while bot.saber_active() and f3 < 300:
		await host.get_tree().physics_frame
		f3 += 1
	t.gt(float(f3) / 60.0, 1.2,
		"AI 的突进时长没被玩家那条改动影响（实得 %.2f s，profile 给的是 1.5 s）" % (float(f3) / 60.0))

	c.free()
	await host.get_tree().process_frame
	Game.reset()


# ============================================================ C1 辅助模式防撞地

## 老板两次澄清后的最终口径（第一版我做错过，这里把两种口径都写下来）：
##
## > ① "如果玩家手动撞地是可以的，但是辅助模式就是要有防撞地。"
## > ② "玩家在辅助模式下主动冲向地面哪怕离地面只有 10 m，**只要玩家松手就要立刻抬升海拔**。"
##
## ❌ 第一版（错）：到危险高度就夺杆 —— 会在玩家主动俯冲时把杆抢走。
## ⚠️ 第二版（也过头了）：只要求"没在爬升"，于是**平飞松手也夺杆** ——
##    老板 2026-09-21 的原话是"辅助飞行很容易抢控制权。**飞到一半就是自动改出**"。
## ⚠️ 第三版（这一版）：再加一条**绝对的高度门** —— 老板："防撞地的阈值改到 **50 m**。
##    **高于这个值就别改出了**。" 于是 50 m 以上什么都不做（不管下坠多快）。
## ✅ 现在：**压杆期间一点不干预；松手要满足「对地高度 ≤ 50 m + 真的在下坠（> DIVE_SINK）
##    + 维持了宽限期（RELEASE_GRACE）」才接管**，且接管/交还的提示走左上角系统提示行。
##
## 这条测试不靠"跑一遍看飞不飞得出来"（工程里有教训：靠跑一遍的测试修复前后都通过），
## 所以分四层：纯函数 → 辅助自己的软避让不抢杆 → 控制器状态机 → 真飞一段。
static func _assist_ground_guard(t: T, host: Node) -> void:
	# ---- ① 纯函数：触发看的是**输入**，不是高度 ----
	t.ok(FlightAssist.needs_release_pull_up(0.0, 0.2, -100.0), "松手 + 0.2 s 后撞地 + 在下坠 → 拉")
	t.ok(FlightAssist.needs_release_pull_up(0.0, 0.01, -900.0),
		"哪怕只剩 10 m（0.01 s）：松手就要拉 —— 这是老板点名的那一条")
	t.not_ok(FlightAssist.needs_release_pull_up(-0.8, 0.2, -100.0),
		"**还在压杆 → 一点都不干预**（主动冲向地面是玩家的自由）")
	t.not_ok(FlightAssist.needs_release_pull_up(0.8, 0.2, -100.0), "还在拉杆抬头时不接管")
	t.not_ok(FlightAssist.needs_release_pull_up(0.0, 9.0, -100.0), "离地还远时不干预")
	t.not_ok(FlightAssist.needs_release_pull_up(0.0, 0.2, 60.0), "已经在爬升就不用拉")
	t.near(FlightAssist.RELEASE_PULL_TIME, FlightAssist.GROUND_TIME, 0.001,
		"触发窗口 = 地面探头的视界（两套数不一致就会出现『探头看见了却不拉』）")

	# ---- ①b 2026-09-21 收紧：平飞不许夺杆 + 松手要有宽限期 ----
	#
	# 老板原话："辅助飞行很容易抢控制权。**飞到一半就是自动改出**。"
	# 根因是原来只要求"没在爬升"（`vertical_speed < 1.0`），**平飞**（下坠 ≈ 0）也满足，
	# 而中低空本来就在地面探头的 2.8 s 视界里 —— 于是"平飞时松手"必然夺杆。
	t.not_ok(FlightAssist.needs_release_pull_up(0.0, 0.2, 0.0),
		"**平飞**（下坠 0）松手 → **不接管**（这就是「飞到一半被夺杆」那条）")
	t.not_ok(FlightAssist.needs_release_pull_up(0.0, 0.2, -10.0),
		"轻微掉高度（-10 m/s）也**不算俯冲**，不接管")
	t.ok(FlightAssist.needs_release_pull_up(0.0, 0.2, -(FlightAssist.DIVE_SINK + 1.0)),
		"真的在下坠（超过 DIVE_SINK=%.0f m/s）→ 才轮到接管" % FlightAssist.DIVE_SINK)
	t.not_ok(FlightAssist.needs_release_pull_up(0.0, 0.2, -100.0, 0.0),
		"刚松手 0 s **不接管**（先过 %.2f s 的宽限期）" % FlightAssist.RELEASE_GRACE)
	t.not_ok(FlightAssist.needs_release_pull_up(0.0, 0.2, -100.0,
		FlightAssist.RELEASE_GRACE - 0.01), "差一点点不够宽限期 → 仍然不接管")
	t.ok(FlightAssist.needs_release_pull_up(0.0, 0.2, -100.0, FlightAssist.RELEASE_GRACE),
		"松手满宽限期 + 在下坠 + 探头看得见地 → 接管")
	t.gt(FlightAssist.DIVE_SINK, 0.0, "`DIVE_SINK` 是正数（按下降量比较，别写反）")

	# ---- ①c 2026-09-21 老板：「防撞地的阈值改到 **50 m**。**高于这个值就别改出了**」----
	#
	# 这是**绝对口径**：50 m 以上，松手再久、下坠再快、探头看得见地面，都不动手。
	t.near(FlightAssist.GROUND_GUARD_ALT, 50.0, 0.001, "门槛就是老板说的 50 m")
	t.not_ok(FlightAssist.needs_release_pull_up(0.0, 0.2, -100.0, 999.0, 200.0),
		"离地 200 m：**一律不改出**（「高于这个值就别改出」就是这条）")
	t.not_ok(FlightAssist.needs_release_pull_up(0.0, 0.2, -100.0, 999.0,
		FlightAssist.GROUND_GUARD_ALT + 0.1), "只高一点点（50.1 m）也不改出")
	t.ok(FlightAssist.needs_release_pull_up(0.0, 0.2, -100.0, 999.0,
		FlightAssist.GROUND_GUARD_ALT), "正好 50 m：允许改出（门槛是「不超过即可」）")
	t.ok(FlightAssist.needs_release_pull_up(0.0, 0.2, -100.0, 999.0, 30.0),
		"离地 30 m：改出")
	# 探头没打到地（高空 / 探头对着天空）不算危险 —— 这一条同时守住"INF 不会被当成 0"
	t.not_ok(FlightAssist.needs_release_pull_up(0.0, 0.2, -100.0, 999.0, INF),
		"探头没打到地（INF）：不改出")
	# 高度门**压过**其他所有条件：高空中即使下坠极快也不动手
	t.not_ok(FlightAssist.needs_release_pull_up(0.0, 0.01, -900.0, 999.0, 300.0),
		"离地 300 m、下坠 -900 m/s：仍然**不改出**（高度门是绝对的）")

	# ---- ② 辅助自己的软避让**不许跟主动俯冲抢** ----
	var dive_dir := Vector3(0, -1, 0)
	var by_player: Dictionary = FlightAssist.correction_for(
		dive_dir, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, 1000.0, 4000.0, INF, 0.2, true)
	t.lt(float(by_player["pitch"]), 0.05,
		"玩家在压杆时，辅助不强行加抬杆（否则玩家拿到的不是他要的俯冲）")
	var by_assist: Dictionary = FlightAssist.correction_for(
		dive_dir, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, 1000.0, 4000.0, INF, 0.2, false)
	t.gt(float(by_assist["pitch"]), 0.5,
		"但**目标在下方**时辅助自己的俯冲指令仍然被否决（1.2 那条『偶尔往地上撞』的修复保留）")

	# ---- ③ 控制器状态机（真实地面 + 手动喂帧）----
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var ground := StaticBody3D.new()
	ground.collision_layer = FlightBody.WORLD_LAYER
	ground.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8000.0, 40.0, 8000.0)
	cs.shape = box
	ground.add_child(cs)
	c.add_child(ground)
	ground.global_position = Vector3(0, -20.0, 0)     # 顶面正好是 y = 0，好算
	await host.get_tree().physics_frame

	var pc := PlayerController.new()
	pc.name = "GuardProbe"
	# 批 8：柯西的辅助驾驶改成了平移模式（_tick_assist 直接早退），
	# 这里要测的是**老的姿态接管路径** —— 换成仍走老路的阿利宙斯巡航形态。
	pc.profile = SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE)
	pc.is_player = true
	pc.team = 0
	pc.projectile_container = c
	c.add_child(pc)
	# 关掉物理帧，`_think()` 就不会跑 —— 于是 `control_input` 完全由测试来写，
	# 可以精确摆出"压着杆"和"松手"两种状态。
	pc.set_physics_process(false)
	pc.assist_on = true
	pc.global_position = Vector3(0, 600, 0)
	pc.fm.speed = 700.0
	pc.fm.velocity = Vector3(0, -300.0, -600.0)
	await host.get_tree().physics_frame
	var notices: Array[String] = []
	pc.notice.connect(func(text: String, _s: float) -> void: notices.append(text))

	# 辅助关着：手动撞地必须仍然可以
	pc.assist_on = false
	pc.control_input = Vector3(-1.0, 0.0, 0.0)
	pc.call("_tick_assist", 0.016)
	t.near(pc.control_input.x, -1.0, 0.0001, "辅助关闭：俯冲指令一点没被改（手动撞地是允许的）")

	# 辅助开着 + 压着杆 → 不接管
	pc.assist_on = true
	pc.control_input = Vector3(-1.0, 0.0, 0.0)
	pc.call("_tick_assist", 0.016)
	t.not_ok(pc.get("_auto_pull_up"), "压着杆俯冲到 600 m：**不接管**（这是他主动要下去的）")
	t.lt(pc.control_input.x, 0.0, "俯冲指令还在，辅助没把它掰成正的")

	# ---- 高度门（2026-09-21）：600 m 上松手 1 秒也不许改出 ----
	#
	# 老板原话："防撞地的阈值改到 50 m。**高于这个值就别改出了**。"
	# 这一条把"中高空松手"整个排除掉 —— 也是这次改动**唯一**想要的行为变化。
	for i in 20:
		pc.control_input = Vector3(0.0, 0.0, 0.0)
		pc.call("_tick_assist", 0.05)          # 松手累计 1.0 s，早就过了宽限期
	t.not_ok(pc.get("_auto_pull_up"),
		"离地 600 m 松手 1 秒（下坠 -300 m/s）：**一点都没改出** —— 高度门在工作")
	t.lt(pc.control_input.x, 0.5, "而且没偷偷把机头掰上去")

	# 辅助开着 + 松手 → **过宽限期之后**才接管（2026-09-21：不再"下一帧就夺杆"）
	# ⚠️ 位置要挪到 50 m 以下，否则被上面的高度门挡住（那正是它该做的）。
	# ⚠️ 还要**先把宽限期计时清零**：上面那 20 帧已经松手累计了 1 s，
	# 不清零的话"刚松手 1 帧不接管"这条根本测不到（第一版就这么红了一次）。
	pc.global_position = Vector3(0, 40.0, 0)
	pc.control_input = Vector3(-0.5, 0.0, 0.0)
	pc.call("_tick_assist", 0.016)
	t.not_ok(pc.get("_auto_pull_up"), "压着杆：不接管（顺带把宽限期计时清零）")
	pc.control_input = Vector3(0.0, 0.0, 0.6)
	pc.call("_tick_assist", 0.016)
	t.not_ok(pc.get("_auto_pull_up"),
		"刚松手 1 帧**不接管**（宽限期 %.2f s，防手抖/推一下杆）" % FlightAssist.RELEASE_GRACE)
	var waited := 0.016
	while waited < FlightAssist.RELEASE_GRACE + 0.06 and not pc.get("_auto_pull_up"):
		pc.control_input = Vector3(0.0, 0.0, 0.6)
		pc.call("_tick_assist", 0.05)
		waited += 0.05
	t.ok(pc.get("_auto_pull_up"),
		"离地 40 m、松手满 %.2f s（下坠 -300 m/s）→ 接管" % FlightAssist.RELEASE_GRACE)
	t.near(pc.control_input.x, 1.0, 0.0001, "接管 = 满抬头")
	# ⚠️ 用 `near` 而不是 `between`：`clampf` 返回的是 **float32** 的 0.4
	# （= 0.40000000596…），而 `between` 的上界是 float64 的字面量 0.4 ——
	# 正好卡在边界上会被判成越界（第一版就红在这里，测试报的是 0.4 "不在" [-0.4, 0.4]）。
	t.near(pc.control_input.z, 0.4, 0.001, "同时压平坡度（侧倾拉杆的转弯半径会被重力吃掉）")
	t.not_ok(pc.fm.boosting, "接管期间不保持加速（加速会把拉升半径撑大）")
	# ⚠️ 2026-09-21：提示从**中央那摞 toast** 搬到了左上角的**系统提示行**（老板要求移开）。
	# 所以这里断言的是"有提示"，而不是"toast 里有"。
	t.ok(str(pc.system_event).contains("接管"),
		"接管时**有提示**（走左上角那一行）：%s" % str(pc.system_event))
	t.eq(notices.count("自动改出 · 接管俯仰"), 0,
		"**不再往中央 toast 里塞**（它现在是系统提示行的事）")
	# 这条通道**不止给辅助用**：切模式 / 切武器也走它 ——
	# 老板第二轮的反馈就是"切换拦截系统和切换手柄操作的这些提示都还在中间"。
	# 直接调 `switch_weapon()` 量一次（它不需要注入输入）。
	pc.call("switch_weapon")
	t.ok(str(pc.system_event).contains("武器"),
		"切武器的提示走**同一条**系统提示行（%s）" % str(pc.system_event))
	t.eq(notices.count("武器：光束军刀"), 0,
		"切武器也**不再进中央 toast**")

	# 贴地也照样拉
	pc.global_position = Vector3(0, 30.0, 0)
	pc.control_input = Vector3(0.0, 0.0, 0.0)
	pc.call("_tick_assist", 0.016)
	t.ok(pc.get("_auto_pull_up"), "贴地 30 m 松手：照样立刻接管（不像上一版那样只认高度）")

	# 危险解除后才交还，而且有最短保持时间
	pc.global_position = Vector3(0, 4000.0, 0)
	pc.fm.velocity = Vector3(0, 120.0, -300.0)        # 在爬升 + 探头看不到地面
	pc.control_input = Vector3(0.0, 0.0, 0.0)
	pc.call("_tick_assist", 0.016)
	t.ok(pc.get("_auto_pull_up"),
		"刚脱离危险时仍保持接管（最短 %.1f s，防贴地抽搐）" % PlayerController.AUTO_PULL_MIN_HOLD)
	for i in 120:
		pc.call("_tick_assist", 0.05)
		if not pc.get("_auto_pull_up"):
			break
	t.not_ok(pc.get("_auto_pull_up"), "保持时间过后交还操纵")
	t.ok(str(pc.system_event).contains("交还"),
		"交还时也有提示（玩家要知道操纵什么时候回来的）：%s" % str(pc.system_event))

	# ---- ④ 真飞一段：压杆冲到低空 → 松手 → **一路掉到 50 m 以下才改出** ----
	#（2026-09-21 之前这里写的是"松手立刻抬升"；老板把门槛改成 50 m 之后，
	#  700 m 上松手就该**什么都不做**，所以这一段整个反过来了。）
	var fly := PlayerController.new()
	fly.name = "GuardFly"
	# 同上（批 8）：真飞一段也要走老辅助路径，柯西已经改成平移模式了。
	fly.profile = SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE)
	fly.is_player = true
	fly.team = 0
	fly.projectile_container = c
	c.add_child(fly)
	fly.controls_enabled = true
	fly.assist_on = true
	# ⚠️ 高度余量必须**按速度给**，不能写死。
	#
	# 原因是纯物理的：**拉起半径 ∝ 速度**（转弯率是绝对的 rad/s，
	# 见 `suite_flight._handling_baseline` 那条"滚转角速率不随机体尺度变"），
	# 所以"有多少米可以掉"必须跟速度同比放大。沿革：
	#   老柯西极速 630 时代：起始 3500 / 松手 700
	#   ×1.6（巡航形态极速 1006）：起始 3500 / 松手 2000  ← 上一轮手动抬的
	#   ×2.4（巡航形态极速 1609）：起始 3500 不够了，机头还没拉平就落海
	#     （实测 `y=15 m`、`[destroy] ... 撞海`）
	# 写成"极速 × 秒数"之后这条比例**自动跟着倍率走**，下次提速不用再来手抬一次。
	var cruise_top := fly.profile.player_top_speed()
	fly.global_position = Vector3(0, cruise_top * 3.5, 0)      # ×2.4 ⇒ 5632 m
	fly.fm.speed = 600.0
	fly.look_at(fly.global_position + Vector3(0, -0.45, -1.0), Vector3.UP)
	fly.fm.align_velocity(fly.forward())
	Input.action_press("pitch_nose_down")
	var dived := 0
	while fly.alive and fly.global_position.y > cruise_top * 2.0 and dived < 600:
		await host.get_tree().physics_frame
		dived += 1
	t.ok(fly.alive, "压着杆俯冲到 %.0f m 还活着（%d 帧）" % [cruise_top * 2.0, dived])
	t.not_ok(fly.get("_auto_pull_up"), "全程压杆期间没有接管（主动俯冲是允许的）")
	Input.action_release("pitch_nose_down")
	# ⚠️ 2026-09-21 的新口径：**50 m 以上不改出**。松开杆之后先确认它真的不管 ——
	# 这正是老板报的"飞到一半就被自动改出"，只不过这次发生在 700 m。
	var idle_frames := 0
	while idle_frames < 90 and fly.alive and fly.global_position.y > 200.0:
		await host.get_tree().physics_frame
		idle_frames += 1
	t.not_ok(fly.get("_auto_pull_up"),
		"松手后一路掉到 %.0f m（%d 帧）：**始终没有改出**（高度门生效）"
			% [fly.global_position.y, idle_frames])
	# ⚠️ **这里不追"掉到 50 m 就一定接管"** —— 辅助的**软避障**（`correction_for()` 里
	# `ground_time < AVOID_TIME` 那一条抬杆）本来就会先把机头托起来。
	# 实测：松手后它一路爬回 6000 m 以上（`y=6050 m`），**根本不会让你掉到 50 m**。
	#
	# 那条软避障**故意没跟着收紧**：它管的是"辅助自己别把机头往地里按"，
	# 也就是帮助面板上写着的"**规避障碍物**" —— 把它也砍到 50 m 等于删掉一个广告功能。
	# 所以硬接管（50 m 那条门）由上面控制器那一段（600 m 不改出 / 40 m 才改出）
	# 和纯函数那组负责；这里只断言这个场景里真能观察到的事：**它活着**。
	for i in 120:
		await host.get_tree().physics_frame
		if not fly.alive:
			break
	t.ok(fly.alive,
		"松手之后没有撞地（这时是**软避障**在托，不是硬接管）：y=%.0f m" % fly.global_position.y)
	# ⚠️ **不断言"一定没撞地"**：50 m 才开拉，而满杆拉升的转弯半径按几百米算 ——
	# 救不救得回来取决于当时的速度，那是物理不是逻辑。这条改动的承诺只有一句：
	# "高于 50 m 不动手，低于才动手"。

	c.free()
	await host.get_tree().process_frame
	Game.reset()


# ============================================================ C2 沙漠暗红

## 老板原话："艾尔斯岩的地面得是暗红色啊，现在有点太白了。"
##
## 判据刻意**不是**"R 比 G 大"这种弱条件 —— 旧值（实测渲出来 R=87 G=67 B=66）
## 也满足它。真正的判据要复现根因：夜光每通道增益是 `WorldBuilder.NIGHT_CHANNEL_GAIN`
## （红 0.30 / 绿 0.45 / 蓝 0.92），把 albedo 过一遍这个增益之后**还剩多少红**。
## 旧值算出来 R/B = 1.17（正好是灰）→ 这条在旧值下必红。
static func _desert_dark_red(t: T, host: Node) -> void:
	var gain := WorldBuilder.NIGHT_CHANNEL_GAIN
	# 旧值：留在这里当"这条断言确实在抓那个病"的证据
	var old_ratio := (0.86 * gain.r) / (0.24 * gain.b)
	t.lt(old_ratio, 1.5, "对照组：旧的反照率过完夜光增益只剩 R/B = %.2f（就是灰的）" % old_ratio)

	# 走**真实路径**（`apply_map(ULURU)`）而不是直接调 `_build_desert()`：
	# 后者需要 `_terrain_root` 已就绪，硬调会在没进树的实例上崩 —— 而且真实路径
	# 顺带把"换图之后这些值确实被设上了"也测了。
	var w := WorldBuilder.new()
	w.initial_map = MapDef.Id.PACIFIC
	host.add_child(w)
	await host.get_tree().process_frame
	w.apply_map(MapDef.uluru())
	await host.get_tree().process_frame

	var bands: Array = [w.get("_land_dark"), w.get("_land_mid"), w.get("_land_light")]
	var names := ["洼地", "主体", "丘顶"]
	for i in bands.size():
		var c: Color = bands[i]
		# 反照率本身必须够"不自然"：这是唯一有效的旋钮（压亮度治不了）
		t.gt(c.r / maxf(c.b, 0.0001), 12.0,
			"%s：反照率 R/B = %.1f（够不自然才够红）" % [names[i], c.r / maxf(c.b, 0.0001)])
		var rendered := (c.r * gain.r) / maxf(c.b * gain.b, 0.0001)
		t.gt(rendered, 3.0,
			"%s：过完夜光增益仍是红（R/B = %.1f，旧值 1.17）" % [names[i], rendered])
	# 整体亮度必须真的下来了（老板说"太白"，不只是色相问题）
	t.lt(float((w.get("_land_light") as Color).r), 0.5,
		"丘顶反照率压到 0.5 以下（旧值 0.86 —— 那是『太白』的直接来源）")
	# 远景地坪是同一个病：它占了画面上大半地面像素
	var found := false
	var root: Node = w.get("_terrain_root")
	if root != null:
		for n: Node in root.get_children():
			var mi := n as MeshInstance3D
			if mi != null and mi.name == "GroundFar" and mi.mesh is PlaneMesh:
				var mat := (mi.mesh as PlaneMesh).material as ShaderMaterial
				if mat != null:
					var tint: Color = mat.get_shader_parameter("albedo_tint")
					found = true
					t.gt((tint.r * gain.r) / maxf(tint.b * gain.b, 0.0001), 3.0,
						"远景地坪也过完增益仍然红（R/B = %.1f）"
							% ((tint.r * gain.r) / maxf(tint.b * gain.b, 0.0001)))
	t.ok(found, "远景地坪材质找得到并且判过了（找不到时上面那条不会静默跳过）")
	w.free()
	await host.get_tree().process_frame


# ============================================================ C3 删岛

## 老板原话："太平洋地图的小岛要删掉，不好看"。
##
## 关键是**成对**断言：岛没了，海面必须还在。
## `_build_islands()` 是"海面 + 岛"一起建的，只钉"岛为 0"的话，
## 把整个函数从 `apply_map()` 里摘掉也能通过 —— 那样这张图会变成空的。
static func _pacific_no_islands(t: T, host: Node) -> void:
	t.eq(WorldBuilder.ISLAND_COUNT, 0, "群岛图的岛数 = 0（第十四轮：小岛删掉）")
	var m := MapDef.pacific()
	t.not_ok(m.blurb.contains("岛"), "地图文案里的岛也去掉了（否则说明书还在说掠岛）")

	var w := WorldBuilder.new()
	w.initial_map = MapDef.Id.PACIFIC
	host.add_child(w)
	await host.get_tree().process_frame
	t.ok(w.ocean != null, "**海面还在**（删岛不能把海面一起删掉）")
	var ir: Node = w.get("islands_root")
	t.ok(ir != null, "islands_root 仍然建出来（空容器）")
	if ir != null:
		t.eq(ir.get_child_count(), 0, "一座岛都没有")
	# 顺带确认这张图还能正常玩：出生点仍然是有效坐标
	var sp := w.spawn_point(-95.0, 9000.0, 2600.0)
	t.near(sp.y, 2600.0, 0.001, "出生点（高度由调用方给）没有被删岛影响")
	w.free()
	await host.get_tree().process_frame


static func _unit(container: Node3D, suit: SuitProfile, team: int, as_player := false) -> FlightBody:
	var u := FlightBody.new()
	u.team = team
	u.is_player = as_player
	u.profile = suit
	u.projectile_container = container
	container.add_child(u)
	u.global_position = Vector3(0, 3000, 0)
	u.fm.speed = 260.0
	u.fm.throttle = 0.78
	u.fm.align_velocity(u.forward())
	return u
