class_name SuiteAbilities
extends RefCounted
## 本轮新增能力的测试：军刀吸附突进、丢枪脱锁、难度表、武器门禁，
## 外加 1.1 的阿利宙斯三形态（数值 / 变形 / 武器门禁 / 爆壳变身）。


static func run(t: T, host: Node) -> void:
	t.suite("Abilities / 难度表")
	_difficulty_table(t)
	t.suite("Abilities / 1.2 辅助飞行（朝向 / 距离 / 规避）")
	_assist(t)
	t.suite("Abilities / 1.2 辅助飞行的地面探头（带姿态）")
	await _assist_probe(t, host)
	t.suite("Abilities / 1.2 近战重做（扫掠判定 / 距离 / 伤害）")
	await _melee_sweep(t, host)
	t.suite("Abilities / 批 10 打击感（分级顿帧 / 光刃 / 相杀对称）")
	await _hit_feel(t, host)
	t.suite("Abilities / 1.2 锁定效率与 AI 误差（方案 B）")
	await _lock_economy(t, host)
	t.suite("Abilities / 武器门禁")
	await _weapon_gates(t, host)
	t.suite("Abilities / 批 14 武器经济（弹夹 / 过热 / 全弹 CD）")
	await _weapon_economy(t, host)
	t.suite("Abilities / 光束步枪换弹")
	await _reload(t, host)
	t.suite("Abilities / 时段预设")
	_time_presets(t)
	t.suite("Abilities / 光束军刀吸附突进")
	await _saber_magnet(t, host)
	t.suite("Abilities / 丢弃光束步枪")
	await _discard_rifle(t, host)
	t.suite("Abilities / 敌机按难度丢枪")
	await _ai_discard(t, host)
	t.suite("Abilities / 丢枪规则表")
	_discard_rules(t)
	t.suite("Abilities / 敌机不会扎进海里")
	await _terrain_avoidance(t, host)
	t.suite("Abilities / 阿利宙斯三形态数值")
	_arizeus_numbers(t)
	t.suite("Abilities / 阿利宙斯变形与武器门禁")
	await _arizeus_forms(t, host)
	t.suite("Abilities / 阿利宙斯残血爆壳变身")
	await _arizeus_transform(t, host)
	t.suite("Abilities / 光束军刀配色（按机体可指定）")
	_saber_color(t)
	t.suite("Abilities / 光束配色（步枪弹体 + 大炮光柱）")
	_beam_color(t)
	t.suite("Abilities / 军刀刀身挂点（真手骨 + 柯西双头剑）")
	await _saber_blade_attach(t, host)
	# ---- ★63-14 追加：挂在**最后**（`t.suite()` 在下一节开始前结算累积断言）----
	t.suite("Abilities / ★63-14 核心·量产型ν高达（军刀挂点 + 大炮）")
	await _core_nu_weapons(t, host)


# ------------------------------------------------------------ 阿利宙斯（1.1）
#
# 用户给的三个数：
#   "巡航模式直线速度比佩涅罗佩快 1.4 倍，但是转角能力差"
#   "量产牛模式下速度是柯西的 95%"
#   "量产牛模式下不能使用导弹，只能使用光束步枪和火神炮"
# 这一组断言**直接对着这三句话**写，所以以后调平衡时，只要这三条性质还在，
# 测试就依然成立（不去钉具体的 m/s 数字，那些是派生量）。

static func _arizeus_numbers(t: T) -> void:
	var cruise := SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE)
	var normal := SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL)
	var core := SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU)
	var pen := SuitProfile.penelope()
	var xi := SuitProfile.xi()

	t.eq(cruise.id, SuitProfile.Id.ARIZEUS, "巡航形态属于阿利宙斯")
	t.eq(cruise.form_count, 3, "阿利宙斯是三个形态")
	t.eq(cruise.form_names.size(), 3, "三个形态都有名字")
	# 巡航速度 = 佩涅罗佩 × ARIZEUS_CRUISE_VS_PENELOPE（批 8：三机速度上调并收敛，
	# 差距收到 1.03 倍 —— 旧的 1.4 × 0.8 削弱公式已废除，NERF 归 1.0）
	t.near(cruise.player_top_speed(),
		pen.player_top_speed() * SuitProfile.ARIZEUS_CRUISE_VS_PENELOPE, 0.5,
		"巡航速度 = 佩涅罗佩 × %.2f（%.0f vs %.0f）"
		% [SuitProfile.ARIZEUS_CRUISE_VS_PENELOPE, cruise.player_top_speed(), pen.player_top_speed()])
	t.gt(cruise.player_top_speed(), pen.player_top_speed(),
		"巡航形态仍然比佩涅罗佩快（这是用户指定的相对关系）")
	# 三个形态都要吃到这次削弱（用户说的是"阿利宙斯"整机，不是某一个形态）
	for pr: SuitProfile in [cruise, normal, core]:
		t.near(pr.speed_scale, SuitProfile.arizeus_speed_scale(pr.form), 0.0001,
			"%s 的速度系数走的是同一条削弱路径" % pr.form_names[pr.form])
	# 转角能力差：巡航形态的转向系数明显低于常态
	t.lt(cruise.turn_scale, normal.turn_scale, "巡航形态转角能力比常态差")
	t.gt(normal.turn_scale, pen.turn_scale * 0.8, "常态的转向不比佩涅罗佩差")
	# 核心形态速度 = 柯西 × ARIZEUS_CORE_VS_XI（批 8：收敛到 0.97 倍）
	t.near(core.player_top_speed(),
		xi.player_top_speed() * SuitProfile.ARIZEUS_CORE_VS_XI, 0.5,
		"核心速度 = 柯西 × %.2f（%.0f vs %.0f）"
		% [SuitProfile.ARIZEUS_CORE_VS_XI, core.player_top_speed(), xi.player_top_speed()])
	t.lt(core.player_top_speed(), xi.player_top_speed(), "核心形态比柯西慢")
	t.gt(core.turn_scale, xi.turn_scale, "核心形态比柯西灵（小一圈）")
	# 武器门禁
	t.not_ok(core.has_missiles, "核心形态没有浮游导弹（用户要求）")
	t.ok(core.has_saber, "★63-14：核心形态**有**光束军刀（用户追补：给量产型牛高达加军刀）")
	t.eq(core.funnel_count, 0, "核心形态的导弹挂架是空的")
	t.gt(core.rifle_magazine, 0, "核心形态仍有光束步枪")
	t.gt(core.vulcan_ammo, 0, "核心形态仍有火神炮")
	# 另外两个形态武器齐全（只是不能手动变到核心）
	t.ok(normal.has_missiles and normal.has_saber, "常态武器齐全")
	t.ok(cruise.has_missiles and cruise.has_saber, "巡航形态武器齐全")
	# 外壳（巡航 / 常态）的耐久完全一致：变形不改血条，只有"爆壳"才改
	t.near(cruise.hull_hp, normal.hull_hp, 0.001, "巡航与常态共用同一份机体耐久")
	t.near(cruise.ifield_hp, normal.ifield_hp, 0.001, "巡航与常态共用同一份 I 立场")
	t.gt(normal.hull_hp, core.hull_hp, "外壳比核心硬（核心是最后一条命）")
	# 三个形态的模型都真的能加载（模型路径写错不会报错，只会静默变占位骨架）
	for p: SuitProfile in [cruise, normal, core]:
		t.ok(ResourceLoader.exists(p.model_path), "%s 的模型存在：%s" % [p.display_name, p.model_path])
	t.ok(normal.transform_hull_ratio > 0.0, "外壳有「战损爆壳」的血线")
	t.eq(normal.transform_to_form, SuitProfile.ArizeusForm.CORE_NU, "爆壳之后变成核心形态")
	t.eq(core.transform_hull_ratio, 0.0, "核心形态不会再爆一次壳")

	# ---- 双联背部炮（用户指定，**只给常态 / 巡航**）----
	#
	# 用户原话："阿利宙斯在常态和巡航模式下，光束步枪发射一次为两发子弹，
	# 从背上并排射出，子弹弹体更大，伤害更高，但是射击间隔久，
	# 而且一发弹夹也只能发射两次。"
	for p: SuitProfile in [normal, cruise]:
		var tag: String = p.display_name
		t.eq(p.rifle_pellets, 2, "%s：一次扳机打出 2 道" % tag)
		t.ok(p.rifle_back_mount, "%s：炮口在背包上方" % tag)
		t.eq(p.rifle_magazine, 2, "%s：一匣只能发射两次" % tag)
		t.gt(p.rifle_scale, 1.0, "%s：弹体比原来大（%.1f×）" % [tag, p.rifle_scale])
		t.gt(p.rifle_damage, xi.rifle_damage,
			"%s：每道伤害高于原来（%.0f > %.0f）" % [tag, p.rifle_damage, xi.rifle_damage])
		t.gt(p.rifle_interval, xi.rifle_interval * 3.0,
			"%s：射击间隔明显变久（%.2fs vs %.2fs）"
			% [tag, p.rifle_interval, xi.rifle_interval])
		# 紫色（用户指定）：蓝通道要明显高于绿通道，且必须**单独指定**过 ——
		# 不能靠改 `accent`，那个颜色还管着主菜单卡片与 HUD 强调色。
		t.gt(p.rifle_beam_color.a, 0.0, "%s：单独指定了光束颜色" % tag)
		t.gt(p.rifle_beam_color.b, p.rifle_beam_color.g + 0.3,
			"%s：光束是紫色（b=%.2f 明显高于 g=%.2f）" % [tag, p.rifle_beam_color.b, p.rifle_beam_color.g])
	# 核心形态**不参与**（用户只点名常态 / 巡航）—— 它必须还是老的单管
	t.eq(core.rifle_pellets, 1, "核心形态仍是单管")
	t.not_ok(core.rifle_back_mount, "核心形态的炮口仍在前臂盾")
	t.eq(core.rifle_scale, 1.0, "核心形态的弹体尺寸不变")
	t.eq(core.rifle_beam_color.a, 0.0, "核心形态不改光束颜色（仍用 accent）")
	# ---- 巡航态背后 16 个推进器喷口（用户指定：淡紫发光 + 喷射轨迹）----
	t.eq(cruise.engine_plumes.size(), 16, "巡航态有 16 个喷口特效位置")
	t.eq(normal.engine_plumes.size(), 10,
		"常态有 10 个喷口（2026-10-09 用户后视图圈点指定：背包 8 + 侧腰 2）")
	t.eq(core.engine_plumes.size(), 0, "核心形态也不做")
	var outside := 0
	for u: Vector3 in cruise.engine_plumes:
		if u.x < 0.0 or u.x > 1.0 or u.y < 0.0 or u.y > 1.0 or u.z < 0.0 or u.z > 1.0:
			outside += 1
	t.eq(outside, 0, "16 个喷口坐标都落在包围盒归一化区间 0..1 内（否则会飘到机体外）")
	t.gt(cruise.engine_plume_color.b, cruise.engine_plume_color.g, "喷口色偏紫（蓝通道 > 绿通道）")
	# 另外两台机：**杆塔配置**不受影响（仍单管、炮口仍在前臂盾）。
	#
	# ⚠️ 但 `engine_plumes` 这**一条必须反过来写**。原来这里是
	# `t.eq(p.engine_plumes.size(), 0, "%s：没有多喷口特效")` —— 那是 2026-09-25 之前的
	# 事实。用户当天指定"柯西的尾焰特效也应该在背部喷口处 / 佩涅罗佩……在机体上的这个位置"
	# 之后，这两台机**有**喷口表了（各 2 个）。留着旧断言，本节就会以
	# "改对了却报红"的方式卡在那里 —— 而它比"漏测"更糟：**它会把正确的改动指成错的**。
	for p: SuitProfile in [xi, SuitProfile.penelope()]:
		t.eq(p.rifle_pellets, 1, "%s：仍是单管" % p.display_name)
		t.not_ok(p.rifle_back_mount, "%s：炮口仍在前臂盾" % p.display_name)
		# ⚠️ 喷口个数**逐机不同**（2026-09-27 起）：柯西 4 个（背包 2 + 小腿后侧 2），
		# 佩涅罗佩仍是 2 个。这里原先把 2 写死在循环里，柯西加口后会红 ——
		# 而它红的正是**对的那一次改动**，比漏测更误导。
		var want_plumes := 4 if p.id == SuitProfile.Id.XI else 2
		t.eq(p.engine_plumes.size(), want_plumes,
			"%s：**有**喷口表（%d 个）—— 2026-09-25 起尾焰按喷口铺开"
				% [p.display_name, want_plumes])
		# ⚠️ 这里**没有** `t.le` —— `tests/t.gd` 只提供 ok / not_ok / near / eq / lt / gt / between。
		# 写 `t.le` 不会红，它会**抛 SCRIPT ERROR 并把后面几条断言一起吃掉**
		#（本节实测：363 而不是 365，还多了一条 SCRIPT ERROR）。用 `t.ok` 把不等式写全。
		t.ok(p.engine_plumes.size() <= FlightBody.PLUME_SHAPE_MAX_NOZZLES,
			"%s：在上限之内 ⇒ 形状层逐口铺开（两形区分照样成立）" % p.display_name)
	# 阿利宙斯**核心**仍然是空表（本节开头那条断言管的就是它）；
	# 常态 2026-10-09 起有 10 个口、走"逐口加力焰"那一支（>4 口，与巡航 16 同支）。
	# "机尾单点尾焰"那一支另有 `_plain_unit` 的空表机在测（suite_fx_plume 第四、五节）。


static func _arizeus_forms(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var u := _unit(c, SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL), 0, true)
	t.eq(u.form_index, SuitProfile.ArizeusForm.NORMAL, "出场是常态")
	t.eq(u.form_count(), 3, "机体知道自己是三形态")

	# ---- 双联齐射的**行为**（不只是 profile 里的数字）----
	# "数字改对了、`fire_beam()` 却忘了循环"是这类改动最容易复发的地方，
	# 所以这里真的开一枪、数码体、看弹匣。
	var beams0 := _beam_count(c)
	var mag0 := u.rifle_mag
	u.rifle_cooldown = 0.0
	t.ok(u.fire_beam(true, null), "常态能开火")
	await host.get_tree().physics_frame
	t.eq(_beam_count(c) - beams0, 2, "一次扳机真的生成 2 道光束")
	t.eq(u.rifle_mag, mag0 - 1, "一次扳机只吃 1 发弹匣（一匣两次扳机 = 4 道光束）")
	# 一匣只够两次
	u.rifle_cooldown = 0.0
	t.ok(u.fire_beam(true, null), "同一匣还能打第二次")
	await host.get_tree().physics_frame
	t.eq(u.rifle_mag, 0, "两次扳机之后弹匣见底")
	u.rifle_cooldown = 0.0
	t.not_ok(u.fire_beam(true, null), "弹匣空了打不出第三发")
	u.rifle_mag = mag0
	u.rifle_cooldown = 0.0

	# ---- 两个炮口的间距：**半间距 = 光束半径 × 3**（用户指定的规则）----
	#
	# ⚠️ 判据直接写成那条规则（而不是写死一个米数），所以它有双重作用：
	#   1. 光束被调大时，间距必须跟着放大 —— 否则两道光糊成一道粗的；
	#   2. "半径"取**可视半径**（光束宽的一半），不是 `hit_radius()`。
	#      后者刻意比可视半宽大一倍（让"擦着机翼过去"的弹也算命中），
	#      拿它乘 3 会算出 75 m 轴距 —— 比整台机还宽。
	var mz2: Array = u.get("_muzzle_local")
	t.eq(mz2.size(), 2, "双联炮口有 2 个")
	if mz2.size() == 2:
		var sep: float = (mz2[0] - mz2[1]).length()
		var vis_r: float = Projectile.BEAM_VIS_RADIUS * u.profile.rifle_scale
		t.near(sep * 0.5, vis_r * 3.0, 0.01,
			"半间距 = 光束可视半径 × 3（%.2f m = 3 × %.2f m）" % [sep * 0.5, vis_r])
		t.gt(sep - vis_r * 2.0, 2.0,
			"两道光束之间有明显空隙（%.1f m 轴距 − %.1f m 光径 = **%.1f m 空隙**）"
			% [sep, vis_r * 2.0, sep - vis_r * 2.0])
		# 炮口高度**上下都要卡**（两个都是"代码不报错、但一眼就错"的故障）：
		#   - **低于 60%**：炮口落到腰以下，光束从小腹射出、前半段埋在机体里
		#     （第一版用骨架锚点定位就是这个症状，追尾镜头里什么都看不见）；
		#   - **高于 92%**：跑到凸出物（天线/尾翼尖）上了。
		#
		# ⚠️ 上界只能这么松，是因为**百分比是相对包围盒的**，而包围盒会被凸出物撑长：
		# 尾翼恢复后包围盒向下多了 0.196（脚底之上 7.05 m），于是正常值就从
		# 0.84 挪到了 0.868。真正"位置对不对"还得靠 `tools/probe_twin` + 截图。
		var mb := u.model_bounds
		var rel: float = (mz2[0].y - mb.position.y) / maxf(mb.size.y, 0.01)
		t.gt(rel, 0.6, "炮口在模型高度的 %.0f%%（上半身，光束不会被机体挡住）" % (rel * 100.0))
		t.lt(rel, 0.92, "炮口没跑到模型顶部（%.0f%% < 92%%，没架在尾翼尖上）" % (rel * 100.0))

	# 玩家只能手动切"前两个形态"；核心形态必须靠爆壳（否则等于白送一条命）
	t.eq(u.switchable_forms().size(), 2, "可手动切换的形态只有两个（核心不在其中）")
	t.ok(u.toggle_form(), "Z 键能把常态切成巡航形态")
	t.eq(u.form_index, SuitProfile.ArizeusForm.CRUISE, "当前形态变成巡航")
	t.near(u.fm.max_speed, SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE).player_top_speed(), 0.5,
		"变形之后速度上限**当场**换成巡航形态的值（不是换个模型就算）")

	# ---- 加力焰分散（用户 2026-09-22：喷气口的"光源"在各喷口上，不再聚在机尾一团）----
	# 切到巡航形态会触发 `_reposition_attachments` → `_rebuild_plumes`，
	# 所以这里能直接读到运行时建的特效组。
	var plumes: Array[Dictionary] = u.get("_plume_fx")
	t.eq(plumes.size(), 16, "巡航态建了 16 组喷口特效")
	var with_boost := 0
	var offset_bad := 0
	for it: Dictionary in plumes:
		var bf := it.get("boost") as GPUParticles3D
		var gl := it.get("glow") as Node3D
		if bf != null and is_instance_valid(bf):
			with_boost += 1
			if gl != null and is_instance_valid(gl) \
					and bf.position.distance_to(gl.position) > 0.01:
				offset_bad += 1
	t.eq(with_boost, 16, "每个喷口都有一簇自己的加力焰")
	t.eq(offset_bad, 0, "加力焰与光晕同点（光源确实在喷口上，不是又聚回一处）")
	var ab := u.get("_afterburner_fx") as GPUParticles3D
	t.ok(ab != null and not ab.emitting, "多喷口形态下单点尾焰退场（机尾不再有那一团白）")

	# 变形冷却 4 秒（用户指定）
	t.eq(u.form_cooldown, SuitProfile.FORM_COOLDOWN, "变形之后进入 4 秒冷却")
	t.not_ok(u.toggle_form(), "冷却期间按 Z 不再变形")
	t.eq(u.form_index, SuitProfile.ArizeusForm.CRUISE, "冷却期间形态没有变化")
	for i in 60:
		await host.get_tree().physics_frame
	t.ok(u.form_cooldown > 0.0 and u.form_cooldown < SuitProfile.FORM_COOLDOWN,
		"冷却在随时间减少（%.2fs）" % u.form_cooldown)

	# 冷却走完 → 能再切（测试里直接清掉冷却，不真等 4 秒）
	u.form_cooldown = 0.0
	t.ok(u.toggle_form(), "冷却走完之后再按一次切回常态")
	t.eq(u.form_index, SuitProfile.ArizeusForm.NORMAL, "回到常态")
	t.near(u.fm.max_speed, SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL).player_top_speed(), 0.5,
		"速度上限跟着回来")

	# 玩家入口（toggle_form）永远不会落到核心形态 —— 否则等于白送一条命。
	# 循环固定次数而不是 `while`：toggle 在两个形态之间来回切时**每次都会返回 true**，
	# 写成 while 就是一个死循环（写测试的时候差点踩进去）。
	# 每次循环前手动清掉冷却：这里测的是"路径"，不是"节奏"（节奏上面已经测过）。
	var visited := {}
	for i in 8:
		u.form_cooldown = 0.0
		u.toggle_form()
		visited[u.form_index] = true
	t.ok(visited.has(SuitProfile.ArizeusForm.NORMAL), "循环变形会经过常态")
	t.ok(visited.has(SuitProfile.ArizeusForm.CRUISE), "循环变形会经过巡航形态")
	t.not_ok(visited.has(SuitProfile.ArizeusForm.CORE_NU),
		"循环变形一次都没落到核心形态（只有爆壳能到）")
	# 而内部入口 `switch_form` 是允许切到核心的：爆壳变身与 AI 都走它
	t.ok(u.switch_form(SuitProfile.ArizeusForm.CORE_NU, true),
		"内部入口允许切到核心形态（爆壳变身要用）")

	# 核心形态的武器门禁
	var core := _unit(c, SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU), 1)
	core.fm.align_velocity(core.forward())
	t.eq(core.funnel_count, 0, "核心形态导弹数为 0")
	t.not_ok(core.fire_funnel(u), "核心形态打不出浮游导弹（门禁在 FlightBody 里）")
	t.ok(core.try_saber(u), "★63-14：核心形态**劈得出**光束军刀")
	t.ok(core.fire_beam(true, null), "核心形态的光束步枪正常")
	await host.get_tree().physics_frame
	t.ok(core.fire_gun(true, null), "核心形态的火神炮正常")

	c.free()
	await host.get_tree().physics_frame


static func _arizeus_transform(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var shell := _unit(c, SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL), 1, false)
	shell.max_hp = SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL).hull_hp
	shell.hp = shell.max_hp
	shell.ifield_hp = 0.0
	shell.ifield_max = 0.0
	var fired := [0]
	shell.transform_started.connect(func(_to): fired[0] += 1)

	# 打掉外壳：本体降到 1% 线以下触发脱出
	shell.take_damage(shell.max_hp * 0.995, null, Damage.Type.BEAM)
	await host.get_tree().physics_frame
	t.eq(fired[0], 1, "血量降到血线以下触发一次爆壳（只一次）")
	t.ok(shell.in_transform(), "爆壳有一段时间的烟雾掩护（此刻正在变身中）")
	t.ok(shell.is_invulnerable(), "变身掩护期间无敌（否则等于在爆炸那一帧被补死）")
	var during := shell.hp
	shell.take_damage(999.0, null, Damage.Type.BEAM)
	t.near(shell.hp, during, 0.001, "掩护期间吃不到伤害")

	# 掩护走完 → 形态真的换了，而且耐久按比例带过来
	for i in 120:
		await host.get_tree().physics_frame
	t.eq(shell.form_index, SuitProfile.ArizeusForm.CORE_NU, "掩护结束后已经是核心形态")
	t.eq(shell.profile.display_name, "核心 · 量产型ν高达", "机体名也跟着换")
	t.near(shell.max_hp, SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU).hull_hp, 0.001,
		"耐久上限换成核心的")
	# 1.2 用户改了口径："阿利宙斯的血条是在扣完之后，才变成量产牛高达的血条" ——
	# 所以核心拿到的是**它自己的一条满血**（第二条命），不再按比例带过来。
	t.near(shell.hp_ratio(), 1.0, 0.001, "核心是满血（血条扣完之后才换成核心自己的血条）")
	t.eq(shell.ifield_max, 0.0, "核心没有 I 立场（用户点名）")
	t.not_ok(shell.has_ifield(), "核心的 I 立场判定为无")
	t.ok(shell.escape_dash_active() or shell.fm.speed > 0.0, "脱出后有一段自动的上拉升突进")
	t.gt(shell.hp, 0.0, "变身之后还活着（不是变身即死）")

	# 爆过壳之后不会再爆第二次
	shell.take_damage(shell.max_hp * 0.4, null, Damage.Type.BEAM)
	await host.get_tree().physics_frame
	t.eq(fired[0], 1, "整局只爆一次壳")

	c.free()
	await host.get_tree().physics_frame


## 容器里还活着的弹丸数（数 `Projectile` 子节点）。用于"双联齐射真的生成两道"。
static func _beam_count(container: Node) -> int:
	var n := 0
	for ch in container.get_children():
		if ch is Projectile:
			n += 1
	return n


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


# ------------------------------------------------------------ 1.2：方案 B（AI 也要为锁定付钱）

## 用户拍板的三个数（1.80 / 1.25 / 0.70 → 1.53 / 1.06 / 0.60 s），
## 加上"猎杀锁定不受难度影响"这条例外。这一组是**AI 侧**的代价，
## 和玩家侧的质量条（`LockOnSystem`）必须成对存在 —— 少了它，
## 方案 A 只会让 AI 更容易锁玩家、玩家更难锁 AI。
static func _lock_economy(t: T, host: Node) -> void:
	var base := LockOnSystem.BASE_LOCK_TIME
	var easy := Difficulty.make(Difficulty.Level.EASY)
	var normal := Difficulty.make(Difficulty.Level.NORMAL)
	var hard := Difficulty.make(Difficulty.Level.HARD)
	# 三个难度给的倍率 → 实际耗时
	t.near(base * easy.lock_time_mult, 1.53, 0.02, "简单：敌机锁定耗时 1.53 s")
	t.near(base * normal.lock_time_mult, 1.06, 0.02, "中等：敌机锁定耗时 1.06 s")
	t.near(base * hard.lock_time_mult, 0.60, 0.02, "困难：敌机锁定耗时 0.60 s")
	t.gt(easy.lock_time_mult, hard.lock_time_mult, "简单难度锁得**更慢**（不是敌人变脆）")
	# 反应延迟与机头抖动：简单难度"眼神差、反应慢"
	t.gt(easy.ai_reaction_lag, hard.ai_reaction_lag, "简单难度 AI 反应更慢")
	t.gt(easy.ai_point_noise_deg, hard.ai_point_noise_deg, "简单难度 AI 机头抖得更厉害")
	t.near(hard.ai_point_noise_deg, 0.5, 0.01, "困难难度几乎不抖（0.5°）")
	t.near(easy.ai_point_noise_deg, 3.0, 0.01, "简单难度抖 3°")
	t.gt(easy.relock_lockout, hard.relock_lockout, "简单难度掉锁后要更久才能重新起锁")

	# ---- AI 侧接线：锁定参数必须**每帧**同步（lock 是 main 后设的，_ready 时还是 null）----
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var ai := BanditAI.new()
	ai.team = 1
	ai.profile = SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE)
	ai.difficulty = hard
	ai.projectile_container = c
	c.add_child(ai)
	var lk := LockOnSystem.new()
	host.add_child(lk)
	lk.setup(ai)
	ai.lock = lk               # ← 模拟 main._attach_ai() 的赋值顺序
	ai.set_physics_process(true)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	t.near(lk.lock_time, base * hard.lock_time_mult, 0.02,
		"AI 的锁定耗时按难度落到自己的锁定系统上（每帧同步）")
	t.near(lk.outer_deg, hard.lock_outer_deg, 0.01, "AI 的锁定锥按难度给")
	t.near(lk.decay_rate, lk.BASE_DECAY * hard.lock_decay_mult, 0.01, "AI 的质量衰减按难度给")

	# ---- 猎杀规则：阿利宙斯对残血柯西（<40%）→ 绝对覆盖 0.30，不乘难度 ----
	# 用 `target_override` 显式指定目标：`BanditAI` 的这个入口本来就是给
	# "TTK 探针 / 将来的僚机"用的，也让这一组断言不依赖 Game 的玩家登记时序。
	var xi := _unit(c, SuitProfile.xi(), 0, true)
	ai.target_override = xi
	xi.hp = xi.max_hp
	await host.get_tree().physics_frame
	t.near(ai.hunt_lock_mult(), 1.0, 0.001, "柯西满血时不触发猎杀")
	xi.hp = xi.max_hp * 0.55
	t.near(ai.hunt_lock_mult(), 1.0, 0.001, "柯西 55% 血还不触发（阈值是 40%）")
	xi.hp = xi.max_hp * 0.39
	print("[dbg] hunt=", ai.hunt_lock_mult(), " tgt=", ai.get("_target"), " prof=", ai.profile.id, " xi=", xi.profile.id, " hp=", xi.hp_ratio())
	ai.set("_target", xi)
	t.near(ai.hunt_lock_mult(), 0.30, 0.001, "柯西 39% 血 → 猎杀锁定生效")
	# 三个难度都给同一个绝对覆盖（用户点名：不乘难度）。
	#
	# ⚠️ 这里**停掉 AI 的物理帧**再手动调 `_sync_lock_params()`：
	# `_target` 是 `_think()` 每帧从 `Game.live_player()` 取的，在测试场景里
	# 那条路径依赖"玩家登记时序"（实测会拿到 null），于是断言会变成
	# "在测 Game 的登记"而不是"在测猎杀规则"。停帧 + 手动同步之后，
	# 这一组就只验证**规则本身**；真实对局里 `_target` 由 `Game.live_player()` 提供。
	ai.set_physics_process(false)
	for lv: int in [Difficulty.Level.EASY, Difficulty.Level.NORMAL, Difficulty.Level.HARD]:
		ai.difficulty = Difficulty.make(lv)
		ai.set("_target", xi)
		ai.call("_sync_lock_params")
		t.near(lk.lock_time, base * 0.30, 0.02,
			"难度 %d 下猎杀锁定都是 0.255 s（绝对覆盖，不乘难度）" % lv)
	# 换一台不是阿利宙斯的敌机 → 规则不触发
	ai.profile = SuitProfile.penelope()
	ai.difficulty = Difficulty.make(Difficulty.Level.HARD)
	ai.set("_target", xi)
	ai.call("_sync_lock_params")
	t.near(ai.hunt_lock_mult(), 1.0, 0.001, "佩涅罗佩没有猎杀规则")
	t.near(lk.lock_time, base * Difficulty.make(Difficulty.Level.HARD).lock_time_mult, 0.02,
		"非猎杀目标时回到按难度算的耗时")
	ai.set_physics_process(true)

	c.free()
	await host.get_tree().physics_frame




static func _difficulty_table(t: T) -> void:
	var easy := Difficulty.make(Difficulty.Level.EASY)
	var normal := Difficulty.make(Difficulty.Level.NORMAL)
	var hard := Difficulty.make(Difficulty.Level.HARD)

	t.near(easy.speed_mult, 1.0, 0.001, "简单：敌机速度 = 柯西基准 ×1.0")
	t.near(easy.damage_mult, 1.0, 0.001, "简单：敌机伤害 ×1.0")
	t.near(normal.speed_mult, 1.3, 0.001, "中等：速度 ×1.3")
	t.near(normal.damage_mult, 1.1, 0.001, "中等：伤害 ×1.1")
	t.near(hard.speed_mult, 1.5, 0.001, "困难：速度 ×1.5")
	t.near(hard.damage_mult, 1.3, 0.001, "困难：伤害 ×1.3")

	var base := SuitProfile.XI_REFERENCE_SPEED
	# 2026-09-22：三机速度"加速一遍 + 近似值"——柯西 speed_scale 变成 1.50，
	# 所以难度表与玩家上限都要乘上它（符号式，别再写死 420）。
	var xs := SuitProfile.xi().speed_scale
	# 2026-09-25：实际速度又整体乘了 `SPEED_REAL_MULT`（1.5）。
	# ⚠️ 它是**实际域**的系数，进 `enemy_top_speed()` / `player_top_speed()` 的返回值，
	# 但**不进** `XI_REFERENCE_SPEED` 本身（那个是显示域基准，`suite_worldscale` 钉着 420）。
	var sm := SuitProfile.SPEED_REAL_MULT
	t.near(SuitProfile.xi().enemy_top_speed(easy.speed_mult), base * xs * sm, 0.01,
		"简单难度敌机速度 = 柯西基准 × 机体速度系数 × 实际倍率")
	t.near(SuitProfile.xi().enemy_top_speed(normal.speed_mult), base * 1.3 * xs * sm, 0.01,
		"中等难度敌机速度 = 柯西基准 ×1.3 × 机体速度系数 × 实际倍率")
	t.near(SuitProfile.xi().enemy_top_speed(hard.speed_mult), base * 1.5 * xs * sm, 0.01,
		"困难难度敌机速度 = 柯西基准 ×1.5 × 机体速度系数 × 实际倍率")
	t.near(SuitProfile.xi().player_top_speed(), base * xs * sm, 0.01,
		"柯西：玩家巡航上限 = 柯西基准 × 机体速度系数（%.2f）× 实际倍率（%.2f）" % [xs, sm])
	t.near(SuitProfile.xi().player_boost_speed(), base * 1.5 * xs * sm, 0.01,
		"柯西：玩家加速上限 = 巡航 ×1.5")

	# ---- 第七轮：转向统一 130%；佩涅罗佩 血量/护盾 130%、速度 150%、伤害相当 ----
	var xi := SuitProfile.xi()
	var pen := SuitProfile.penelope()
	t.near(xi.turn_scale, 1.30, 0.001, "柯西转向系数 1.30")
	t.near(pen.turn_scale, 1.30, 0.001, "佩涅罗佩转向系数 1.30")
	t.near(xi.turn_scale, pen.turn_scale, 0.0001,
		"两台机的操控/转向性能完全相同（用户要求统一到一个水平）")

	t.near(pen.hull_hp / xi.hull_hp, 1.30, 0.01, "佩涅罗佩血量 = 柯西 ×1.30")
	t.near(pen.ifield_hp / xi.ifield_hp, 1.30, 0.01, "佩涅罗佩护盾 = 柯西 ×1.30")
	# 耐久是"为了打多久"调的，一共动过**五次**（详见 SuitProfile 里 `DURABILITY_MULT`）：
	#   115/190 --×3--> 345/570 --×0.63--> 217/359 --×1.35--> 293/485 --×1.60--> **347/574**
	#   （第二十二轮下半用户："**所有机体血条和护盾量都调高**"）
	# 用户第八轮的指令是"血量和护盾砍到现在的 63%"，第十八轮与第二十二轮又要求上调
	#（都走统一倍率 `DURABILITY_MULT`）。所以这里断言的是
	# **"血与盾被同一个比例处理"**、再乘上那个统一倍率 —— 以后再调平衡，
	# 只要这两条性质还在，检查就依然有意义。
	var dm := SuitProfile.DURABILITY_MULT
	t.near(xi.hull_hp / (345.0 * dm), 0.63, 0.01, "柯西血量 = 上一版的 63%（再乘统一倍率）")
	t.near(xi.ifield_hp / (570.0 * dm), 0.63, 0.01, "柯西护盾 = 上一版的 63%（再乘统一倍率）")
	t.near(pen.hull_hp / (449.0 * dm), 0.63, 0.01, "佩涅罗佩血量 = 上一版的 63%")
	t.near(pen.ifield_hp / (741.0 * dm), 0.63, 0.01, "佩涅罗佩护盾 = 上一版的 63%")
	t.near(xi.hull_hp / (115.0 * dm), 1.89, 0.02, "柯西血量 = 最初值 ×1.89（3 × 0.63）")
	t.near(xi.ifield_hp / (190.0 * dm), 1.89, 0.02, "柯西护盾 = 最初值 ×1.89（3 × 0.63）")
	t.gt(dm, 1.0, "统一耐久倍率是**上调**（当前 %.2f）" % dm)
	# ⚠️ 第二十二轮新增：**每一次"调高耐久"都必须先想清楚"一局会变多长"**。
	# 这项被实测否过一次（第八轮的"11 分钟还是太漫长"），所以给倍率封一个上限：
	# 再往上就必须先拿到 `probe_ttk` 的实测读数，不能凭手感推。
	t.lt(dm, 1.80, "统一倍率 %.2f < 1.80（再高就必须先拿 probe_ttk 的实测）" % dm)
	t.gt(dm, SuitProfile.DURABILITY_MULT_PREV,
		"倍率相对上一轮（%.2f）确实是**调高**了" % SuitProfile.DURABILITY_MULT_PREV)

	# 主菜单的耐久条：分母必须跟着数值走，否则两条都顶满、条形图白画。
	# 这条是"改了数值忘了改分母"那类静默失效的保险（分母现在由 SuitProfile 提供）。
	t.between(xi.hull_hp / SuitProfile.hull_bar_ref(), 0.55, 1.0,
		"柯西耐久条：不满格，也不瘦成一条")
	t.between(pen.hull_hp / SuitProfile.hull_bar_ref(), 0.55, 1.0,
		"佩涅罗佩耐久条：不满格，也不瘦成一条")
	t.gt(pen.hull_hp / SuitProfile.hull_bar_ref(), xi.hull_hp / SuitProfile.hull_bar_ref(),
		"佩涅罗佩的耐久条比柯西长（两台机的差别要看得出来）")
	t.between(xi.ifield_hp / SuitProfile.ifield_bar_ref(), 0.55, 1.0,
		"柯西 I 立场条：不满格，也不瘦成一条")
	t.between(pen.ifield_hp / SuitProfile.ifield_bar_ref(), 0.55, 1.0,
		"佩涅罗佩 I 立场条：不满格，也不瘦成一条")
	# 浮游导弹数量必须跟着耐久涨，否则"35 发打不穿"（这是 ×4 那次翻车的原因）
	# ⚠️ 批 14 后总量无限，"够不够"看的是**弹夹数**：一个弹夹（150 发）不够，
	# 两个弹夹必须够 —— 护栏的本意（伤害足以击穿耐久）不变，单位换成弹夹。
	t.gt(2.0 * float(xi.funnel_count) * xi.funnel_damage / 0.70,
		pen.hull_hp + pen.ifield_hp,
		"两个弹夹的浮游导弹足够打穿佩涅罗佩（总量无限后按弹夹数算）")
	t.near(pen.speed_scale / xi.speed_scale, 1.55 / 1.50, 0.001,
		"佩涅罗佩速度系数 = 柯西 ×(1.55/1.50)（2026-09-22 三机速度收敛为近似值，次序保留）")
	t.gt(pen.player_top_speed(), xi.player_top_speed(),
		"佩涅罗佩常态速度比柯西快（%.0f > %.0f）"
		% [pen.player_top_speed(), xi.player_top_speed()])
	t.gt(pen.player_boost_speed(), xi.player_boost_speed(),
		"佩涅罗佩极速也比柯西快（%.0f > %.0f）"
		% [pen.player_boost_speed(), xi.player_boost_speed()])
	# 速度系数对敌机侧同样成立 —— "谁开这台机"不影响这台机有多快
	t.gt(pen.enemy_top_speed(hard.speed_mult), xi.enemy_top_speed(hard.speed_mult),
		"困难难度下敌机开佩涅罗佩同样比开柯西快")
	t.near(xi.enemy_top_speed(hard.speed_mult), base * 1.5 * xs * sm, 0.01,
		"敌机开柯西时仍然是「柯西基准 ×1.5 × 机体速度系数 × 实际倍率」（难度倍率契约没变，基准跟着机体走）")

	# ---- 弹速（第八轮用户要求）----
	#
	#   "导弹和光束步枪的弹速要比柯西和佩涅罗佩快；光束最快，然后是导弹；
	#    导弹要比佩涅罗佩快 2 倍"
	#
	# 判据全部由 profile 推导，不写死数字 —— 佩涅罗佩速度系数一改，
	# 这几条依然成立（导弹速度是跟着它算的，见 SuitProfile.missile_speed()）。
	# ⚠️ 2026-09-25 之后**光束没有"一个弹速"了**（出膛段慢、中段接近光速），
	# 所以"光束最快"这条必须拿**等效平均弹速**在常规交战距离上取 ——
	# 拿任何单档去比都是错的：拿出膛段 2880 比会得出"光束比导弹慢"的**假结论**，
	# 拿中段 9×10⁴ 比又等于没验任何东西。
	var beam: float = SuitProfile.rifle_effective_speed(SuitProfile.RIFLE_DEFAULT_RANGE)
	var missile: float = SuitProfile.missile_speed()
	# "比柯西和佩涅罗佩快"：拿两台机**最快的状态**（加速上限）来比才算数
	var fastest_suit: float = maxf(pen.player_boost_speed(), xi.player_boost_speed())
	t.near(missile / pen.player_top_speed(), 2.6, 0.001,
		"导弹弹速 = 佩涅罗佩巡航上限 ×2.6（%.0f = %.0f ×2.6，提速追得上 QB）"
		% [missile, pen.player_top_speed()])
	t.gt(missile, fastest_suit, "导弹比两台机的加速上限都快（%.0f > %.0f）" % [missile, fastest_suit])
	t.gt(beam, missile, "光束（常规距离上的等效弹速 %.0f）比导弹（%.0f）还快" % [beam, missile])
	t.gt(beam, fastest_suit, "光束步枪比两台机的加速上限都快（%.0f > %.0f）" % [beam, fastest_suit])
	# ---- 两段式弹道的**形状**（替掉旧的"两台机同速"）----
	# 旧断言是"柯西与佩涅罗佩的 `rifle_speed` 相等"—— 那个字段已随"常弹速"这个
	# 假设一起删除。现在真正要守的是**形状**：出膛段 = 弹道的 30%、封顶 864 m、比中段慢。
	t.near(SuitProfile.rifle_launch_len(1000.0), 300.0, 0.001,
		"1000 m 弹道的出膛段 = 30%%（300 m）")
	t.ok(SuitProfile.rifle_launch_len(99999.0) <= SuitProfile.RIFLE_LAUNCH_MAX_LEN,
		"出膛段封顶 %.0f m（远距离不会变成「弹丸在路上散步」，实测 %.0f m）"
			% [SuitProfile.RIFLE_LAUNCH_MAX_LEN, SuitProfile.rifle_launch_len(99999.0)])
	t.lt(SuitProfile.RIFLE_LAUNCH_SPEED, SuitProfile.RIFLE_FAST_SPEED,
		"出膛段慢于中段（%.0f < %.0f）" % [SuitProfile.RIFLE_LAUNCH_SPEED, SuitProfile.RIFLE_FAST_SPEED])
	t.gt(SuitProfile.RIFLE_FAST_SPEED, missile * 10.0,
		"中段弹速 %.0f 远高于导弹（%.0f）—— 这就是用户要的「接近光速」"
			% [SuitProfile.RIFLE_FAST_SPEED, missile])
	t.gt(missile, xi.player_top_speed() * 2.0,
		"导弹连柯西巡航的两倍都快（顺手守住「弹速得远高于机体」这条）")

	# ---- 两段式弹道下的**提前量几乎归零**（这是弹道变快的必然结果，不是 bug）----
	#
	# 1500 m 处横向 260 m/s 的目标：老口径（常弹速 2100）要提前 ~185 m，
	# 新口径只要 ~39 m —— 1 km 打过去只要 11 ms，当然不用提前量。
	# 写死成断言，免得以后有人把它"修"回一个明显的提前量。
	var tp := Vector3(0.0, 1000.0, -1500.0)
	var tv := Vector3(0.0, 0.0, 260.0)
	var lead := Ballistics.beam_lead_point(Vector3.ZERO, tp, tv)
	t.lt(lead.distance_to(tp), 60.0,
		"1500 m 处的提前量只有 %.1f m（老口径下是 185 m）—— 弹道快到不需要提前量"
			% lead.distance_to(tp))
	t.gt(lead.distance_to(tp), 0.0, "但仍然不是零（飞行时间不为零，模型自洽）")

	# 耐久与速度涨上去了，但**伤害两台机差不多**（用户明确要求）
	t.near(pen.rifle_damage / xi.rifle_damage, 1.0, 0.08, "两机的光束步枪伤害相当")
	t.near(pen.saber_damage / xi.saber_damage, 1.0, 0.10, "两机的军刀伤害相当")
	t.eq(pen.funnel_damage, xi.funnel_damage, "两机的浮游导弹伤害完全相同")

	t.eq(easy.discard_rules.size(), 1, "简单：只有半血一次丢枪")
	t.eq(normal.discard_rules.size(), 2, "中等：半血 + 残血两次丢枪")
	t.eq(hard.discard_rules.size(), 3, "困难：首次被锁定 + 半血 + 残血三次丢枪")
	t.near(float(easy.discard_rules[0]["unlock"]), 0.0, 0.001, "简单丢枪只解除锁定，不给不可锁定窗口")
	t.near(float(normal.discard_rules[0]["unlock"]), 7.0, 0.001, "中等丢枪 7 秒不可被锁定")
	t.eq(hard.discard_rules[0]["trigger"], Difficulty.TRIGGER_FIRST_LOCKED, "困难第一次被玩家锁定就丢枪")


# ------------------------------------------------------------ 武器门禁

static func _weapon_gates(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var u := _unit(c, SuitProfile.xi(), 1)

	t.eq(u.rifle_count, 3, "柯西开局 3 把光束步枪")
	# ---- 批 14：浮游导弹**总量无限**，profile.funnel_count 改语义为**弹夹容量** ----
	t.eq(u.funnel_count, 150, "柯西弹夹 = 150 发（用户指定：每个弹夹 150 发）")
	t.eq(SuitProfile.penelope().funnel_count, 150, "佩涅罗佩同一份弹夹容量")
	t.gt(SuitProfile.xi().funnel_reload_time, 0.0, "换弹耗时为正（打空自动换弹）")

	# ---- 1.2 弹幕化三件套（伤害与分发规则不变；"总载弹"概念随批 14 作废）----
	t.eq(SuitProfile.MISSILE_PER_SHOT, 3, "一次扳机 3 发")
	t.near(SuitProfile.MISSILE_DAMAGE_MULT, 0.3, 0.001, "每发伤害 ×0.3（降低 70%）")
	# ⚠️ 这条护栏是历次数值改动的**合力**，也是最容易被后人改坏的：
	# 一次扳机的伤害 = 3 发 × 0.3 = 0.9 倍于原来单发 —— **历次改弹夹都没动它**。
	t.near(float(SuitProfile.MISSILE_PER_SHOT) * SuitProfile.MISSILE_DAMAGE_MULT,
		0.9, 0.001, "一次扳机的总伤害 ≈ 原来单发的 0.9 倍（伤害降 70% 与三发相抵）")

	t.ok(u.fire_beam(true), "有枪时能打光束步枪")
	t.not_ok(u.fire_beam(true), "步枪射击间隔内无法连发")

	u.rifle_cooldown = 0.0
	u.rifle_count = 0
	t.not_ok(u.fire_beam(true), "枪丢光之后无法再进行光束步枪射击")

	var foe := _unit(c, SuitProfile.penelope(), 0)
	var before := u.funnel_count
	t.ok(u.fire_funnel(foe), "能发射浮游导弹")
	# 断言**紧跟发射**：导弹在 `_ready()` 里就进组（missile.gd:99），
	# 而过一帧之后它可能已经命中（这一对单位的出生点是同一个坐标）或者自毁 ——
	# 那时"进没进组"这件事已经看不出来了，断言会莫名其妙地红。
	t.gt(host.get_tree().get_nodes_in_group("missiles").size(), 0, "浮游导弹进入了 missiles 组")
	t.eq(u.funnel_count, before - 3, "一次扳机扣 3 发（1.2：每次发射三发）")

	# ---- 火神炮：无限弹（1.2 用户指定）----
	#
	# 判据是"**装弹量不再是限制**"，所以把装弹量压到 5 再连打 20 次。
	# 直接打 900 次会生成 900 个弹丸，测试跑不动，而且证明的是同一件事。
	var g := _unit(c, SuitProfile.xi(), 1)
	g.profile.vulcan_ammo = 5
	var fired_n := 0
	for i in 20:
		g.gun_cooldown = 0.0
		if g.fire_gun(true):
			fired_n += 1
	t.eq(fired_n, 20, "火神炮无限弹：装弹量填 5 也照样连打 20 次")
	t.ok(g.profile.has_vulcan(), "装弹量 > 0 = 装了这门炮")
	# ⚠️ 而"没装炮"必须仍然打不出来：靶机版古斯塔夫就是靠 `vulcan_ammo = 0`
	# 表达"整场一枪不放"，把 0 当成"打空了"会让训练模式的靶机开始还击。
	g.profile.vulcan_ammo = 0
	g.gun_cooldown = 0.0
	t.not_ok(g.profile.has_vulcan(), "装弹量 = 0 = 没装这门炮")
	t.not_ok(g.fire_gun(true), "没装火神炮的机体仍然打不出来（靶机不会还击）")

	c.free()
	await host.get_tree().process_frame


# ------------------------------------------------------------ 批 14 武器经济
#
# 用户四条："浮游导弹数量改为无限，但是需要换弹，每个弹夹150发浮游导弹。
# 全弹发射的cd改为30s。火神炮也改为无限子弹，但是加入过热条和cd。敌方机体也改。"
#
# ⚠️ 四条全在 **FlightBody / PlayerController 的共用路径**上 —— "敌方机体也改"
# 不需要单独实现：AI 走的就是同一条 `fire_gun()` / `fire_funnel()`，
# 过热与换弹对它自动生效。

static func _weapon_economy(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var u := _unit(c, SuitProfile.xi(), 1)
	var foe := _unit(c, SuitProfile.penelope(), 0)

	# ---- ① 浮游导弹：总量无限、弹夹 150、打空自动换弹 ----
	t.eq(u.funnel_mag_size, 150, "（前提）弹夹容量已随 profile 装载")
	u.funnel_count = 3
	u.funnel_cooldown = 0.0
	t.ok(u.fire_funnel(foe), "弹夹只剩 3 发也照常打（总量无限，只看弹夹）")
	t.eq(u.funnel_count, 0, "这一梭正好打空弹夹")
	t.gt(u.funnel_reload_left, 0.0, "打空后自动开始换弹")
	t.not_ok(u.fire_funnel(foe), "换弹中不能发射")
	for i in 80:
		u._tick_weapons(0.1)   # 8 s > 换弹 5 s，一次 tick 就够走完
	t.eq(u.funnel_count, u.funnel_mag_size, "换弹完成后弹夹重新满上")
	t.eq(u.funnel_reload_left, 0.0, "换弹计时收口（不留残态）")

	# ---- ② 全弹发射：CD 30 s；打空弹夹与单发路径共用同一个换弹触发 ----
	t.eq(PlayerController.FULL_SALVO_COOLDOWN, 30.0, "全弹发射 CD = 30 s（用户指定）")
	u.funnel_count = 100
	u.funnel_reload_left = 0.0
	u._funnel_check_reload()
	t.eq(u.funnel_reload_left, 0.0, "弹夹没空不触发换弹（全弹 100/150 还剩 50）")
	u.funnel_count = 0
	u._funnel_check_reload()
	t.gt(u.funnel_reload_left, 0.0, "打空即触发（fire_full_salvo 与 fire_funnel 同路）")

	# ---- ③ 火神炮：无限弹 + 过热 + 卡住 CD ----
	var g := _unit(c, SuitProfile.xi(), 1)
	var fired := 0
	var jammed := false
	for i in 200:
		g.gun_cooldown = 0.0
		if g.fire_gun(true):
			fired += 1
		else:
			jammed = true
			break
	t.ok(jammed, "连续开火最终会过热卡住（第 %d 发）" % fired)
	t.ok(g.vulcan_overheated, "过热标记置位")
	t.gt(fired, 40, "过热不是几发就触发（要留出 ~3 s 点射的空间）")
	t.lt(fired, 80, "过热也不会迟迟不来（无限弹不能退化成无代价）")
	t.not_ok(g.fire_gun(true), "过热期间不能开火（这就是 CD）")
	for i in 14:
		g._tick_weapons(0.1)   # 1.4 s < VULCAN_JAM_MIN 1.5 s
	t.gt(g.vulcan_jam_left, 0.0, "（前置）最短卡住时间还没走完")
	t.near(g.vulcan_heat, 1.0, 0.001, "卡住期间热量不冷却（红着一条顶满是过热的视觉本体）")
	var resumed := false
	for i in 300:
		g._tick_weapons(0.1)
		if not g.vulcan_overheated:
			resumed = true
			break
	t.ok(resumed, "冷却到阈值以下后解除过热（VULCAN_JAM_MIN + 降温 ≈ 2.8 s 的代价）")
	t.lt(g.vulcan_heat, FlightBody.VULCAN_RESUME + 0.01, "解除时热量已在阈值以下")
	g.gun_cooldown = 0.0
	t.ok(g.fire_gun(true), "解除后能再次开火（不是永久报废）")

	c.free()
	await host.get_tree().process_frame


# ------------------------------------------------------------ 换弹

static func _reload(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var u := _unit(c, SuitProfile.xi(), 1)

	t.eq(u.rifle_mag, u.profile.rifle_magazine, "开局弹匣是满的")

	var fired := 0
	for i in u.profile.rifle_magazine + 3:
		u.rifle_cooldown = 0.0
		if u.fire_beam(true):
			fired += 1
	t.eq(fired, u.profile.rifle_magazine, "一匣只能打出弹匣容量那么多发")
	t.eq(u.rifle_mag, 0, "打完后弹匣为空")
	u.rifle_cooldown = 0.0
	t.not_ok(u.fire_beam(true), "弹匣空了就打不出光束步枪")

	t.ok(u.rifle_reloading, "打空后自动开始换弹")
	t.not_ok(u.reload_rifle(), "换弹过程中不能重复触发")
	t.gt(u.reload_progress(), -0.001, "换弹进度可读")

	var frames := int(u.profile.rifle_reload_time * 60.0) + 8
	for i in frames:
		await host.get_tree().physics_frame
	t.ok(not u.rifle_reloading, "换弹完成")
	t.eq(u.rifle_mag, u.profile.rifle_magazine, "换弹后弹匣恢复满")
	u.rifle_cooldown = 0.0
	t.ok(u.fire_beam(true), "换弹后又能射击")

	# 弹匣满的时候换弹应被拒绝（上面那一发把弹匣打成了 5 发，先补满再测）
	u.rifle_mag = u.profile.rifle_magazine
	t.not_ok(u.reload_rifle(), "弹匣已满时换弹返回 false")

	# 丢枪会打断换弹
	u.rifle_mag = 0
	u.rifle_cooldown = 0.0
	t.ok(u.reload_rifle(), "再次进入换弹")
	u.discard_cooldown = 0.0
	t.ok(u.discard_rifle(), "丢枪成功")
	t.not_ok(u.rifle_reloading, "丢枪会打断换弹")

	c.free()
	await host.get_tree().process_frame


# ------------------------------------------------------------ 时段预设

static func _time_presets(t: T) -> void:
	var day := TimeOfDay.day()
	var dusk := TimeOfDay.dusk()
	var night := TimeOfDay.night()

	t.eq(day.preset, TimeOfDay.Preset.DAY, "白天预设编号正确")
	t.eq(dusk.preset, TimeOfDay.Preset.DUSK, "黄昏预设编号正确")
	t.eq(night.preset, TimeOfDay.Preset.NIGHT, "夜晚预设编号正确")
	t.eq(night.name_cn, "夜晚", "夜晚名称正确")
	t.eq(TimeOfDay.make(TimeOfDay.Preset.NIGHT).preset, TimeOfDay.Preset.NIGHT, "make() 按预设取")

	t.near(day.star_amount, 0.0, 0.001, "白天没有星星")
	t.gt(night.star_amount, 0.5, "夜晚有星空")
	t.gt(dusk.star_amount, day.star_amount, "黄昏开始出现星星")

	t.lt(night.sun_energy, day.sun_energy, "夜间主光更弱（弱月光）")
	t.lt(dusk.sun_energy, day.sun_energy, "黄昏主光弱于白天")
	t.gt(night.exposure, day.exposure, "夜间曝光抬高，否则暗部全是纯黑看不清机体")
	t.lt(night.ambient_energy, day.ambient_energy, "夜间环境光更暗")

	t.lt(night.ocean_deep.r, day.ocean_deep.r, "夜间海面更暗")
	t.lt(night.ocean_sky.r, day.ocean_sky.r, "夜间海面反射的天色也更暗")

	t.eq(night.cloud_tints.size(), 3, "三带云层都有夜间配色")
	t.eq(night.cloud_shades.size(), 3, "三带云层都有夜间阴影色")
	t.lt(night.cloud_tints[1].r, day.cloud_tints[1].r, "夜间云层被压暗")

	t.eq(TimeOfDay.all_presets().size(), 3, "一共三个时段")


# ------------------------------------------------------------ 军刀吸附

static func _saber_magnet(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)

	# --- 吸附：目标在 620 m 内 ---
	var me := _unit(c, SuitProfile.xi(), 0)
	var foe := _unit(c, SuitProfile.penelope(), 1)
	foe.global_position = me.global_position + Vector3(0, 0, -400.0)
	var d0 := me.global_position.distance_to(foe.global_position)

	t.ok(me.try_saber(foe), "挥刀成功")
	t.ok(me.saber_active(), "进入突进状态")
	t.eq(me.saber_target, foe, "锁定且在吸附范围内 → 吸附到目标")
	var hp0 := foe.hp
	var shield0 := foe.ifield_hp

	var frames := 0
	while me.saber_active() and frames < 180:
		await host.get_tree().physics_frame
		frames += 1
	# 第四轮起军刀不再穿盾：它劈的是 I 立场，机体在护盾破之前一滴血不掉
	t.lt(foe.ifield_hp, shield0, "吸附突进后劈中目标（I 立场掉了 %.1f，用了 %d 帧）"
		% [shield0 - foe.ifield_hp, frames])
	t.near(foe.hp, hp0, 0.001, "护盾未破时军刀也不掉机体血")
	t.lt(me.global_position.distance_to(foe.global_position), d0, "突进确实缩短了距离")

	# --- 超范围：不吸附，但依然能挥空刀 ---
	var me2 := _unit(c, SuitProfile.xi(), 0)
	var far := _unit(c, SuitProfile.penelope(), 1)
	far.global_position = me2.global_position + Vector3(0, 0, -2500.0)
	t.ok(me2.try_saber(far), "超出吸附范围依然能挥刀")
	t.eq(me2.saber_target, null, "超出吸附范围不会吸附（只是一次普通突刺）")

	# --- 没有目标 ---
	var me3 := _unit(c, SuitProfile.xi(), 0)
	t.ok(me3.try_saber(null), "没有目标也能挥空刀")
	t.eq(me3.saber_target, null, "没有目标时不吸附")

	# --- 冷却 ---
	t.not_ok(me3.try_saber(null), "军刀冷却中无法再次挥刀")

	c.free()
	await host.get_tree().process_frame


# ------------------------------------------------------------ 丢枪

static func _discard_rifle(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)

	var xi := _unit(c, SuitProfile.xi(), 0, true)
	var foe := _unit(c, SuitProfile.penelope(), 1)
	foe.global_position = xi.global_position + Vector3(0, 0, -1200.0)

	# 让对手（佩涅罗佩）锁住柯西
	var foe_lock := LockOnSystem.new()
	host.add_child(foe_lock)
	foe_lock.setup(foe)
	Game.register_lock(foe, foe_lock)
	foe_lock.target = xi

	t.eq(xi.rifle_count, 3, "柯西开局 3 把步枪")
	t.ok(xi.discard_rifle(), "柯西可以丢枪")
	t.eq(xi.rifle_count, 2, "丢枪后剩 2 把")
	t.ok(xi.is_unlockable(), "丢枪后进入不可被锁定状态")
	t.near(xi.unlockable_seconds_left(), 15.0, 0.4, "玩家丢枪的不可锁定时间是 15 秒")
	t.eq(foe_lock.target, null, "丢枪强制解除了对手的锁定")
	t.not_ok(xi.discard_rifle(), "丢枪冷却中无法连丢")

	# 枪丢光之后不能再射击
	xi.discard_cooldown = 0.0
	xi.discard_rifle()
	xi.discard_cooldown = 0.0
	xi.discard_rifle()
	t.eq(xi.rifle_count, 0, "连续丢枪后步枪清零")
	xi.discard_cooldown = 0.0
	t.not_ok(xi.discard_rifle(), "没有步枪时可以丢枪失败")
	t.not_ok(xi.fire_beam(true), "步枪丢光后无法射击")

	# 佩涅罗佩没有这个技能，而且用户要求它只带一把枪
	# （不能丢枪的机体带三把没有意义）
	var pen := _unit(c, SuitProfile.penelope(), 0, true)
	t.not_ok(pen.discard_rifle(), "佩涅罗佩没有丢枪技能")
	t.eq(pen.rifle_count, 1, "佩涅罗佩只带一把光束步枪")
	t.eq(SuitProfile.xi().rifle_count, 3, "柯西带三把（丢枪要用）")

	foe_lock.free()
	c.free()
	await host.get_tree().process_frame

	# ---- ★63-9 B6：**T（举盾）不许再触发丢枪** ----
	#
	# 用户实测：「把长按 t 的丢枪去掉，保留 t 撑盾的功能」。
	# ⚠️ 为什么这条写成**源码级接线断言**：`_tick_holds()` 读的是
	# `Input.is_action_pressed()`，而本工程实测**无头下注入输入不可靠**（`tutorial_director.gd` 那条：
	# 连续注入 40 次一次不触发）⇒ 判定抽成可测的纯件（这次就是 `HoldAction`）、
	# 输入那一层只钉接线。与 `MainMenu.nav_delta_y()` / `NetSession.wait_exit()` 同一取舍。
	var pc_src := FileAccess.get_file_as_string("res://scripts/flight/player_controller.gd")
	var pc_code := ""
	for ln in pc_src.split("\n"):
		if not str(ln).strip_edges().begins_with("#"):
			pc_code += str(ln) + "\n"
	t.eq(pc_code.count("_hold_discard_b"), 0,
		"`_hold_discard_b` 整个删掉（不是加条件）—— 留一个空实例就是留一条死路径")

	# 取 `_tick_holds()` 的正文（从 `func _tick_holds(` 到下一个列首 `func `）
	var body := ""
	var started := false
	for ln in pc_code.split("\n"):
		if str(ln).begins_with("func _tick_holds("):
			started = true
		elif started and str(ln).begins_with("func "):
			break
		if started:
			body += str(ln) + "\n"
	t.ok(body != "", "取到了 `_tick_holds()` 的正文")
	t.eq(body.count("\"shield\""), 0,
		"`_tick_holds()` 里一个 `shield` 都不读 —— 举盾现在只归 `raise_shield()` 管")
	t.gt(body.count("\"reload\""), 0, "丢枪读的是 `reload`（键盘 R / 手柄 Y）")
	t.eq(body.count("_try_discard_rifle()"), 1,
		"整段只有**一个** `_try_discard_rifle()` 调用点（多一个就是又分了个家）")
	t.eq(body.count("maxf("), 0, "进度不再取两个 HoldAction 的最大值（那是实打实的误报）")

	# ---- 运行时段：`HoldAction` 这个“纯件”的行为（丢枪判定的底座）----
	var h := HoldAction.new()
	h.configure(0.6)
	t.eq(h.tick(0.3, true), HoldAction.Result.NONE, "按住 0.3 s 还不算长按")
	t.near(h.progress(), 0.5, 0.02, "进度过半 = 0.5（HUD 预警看的就是它）")
	t.eq(h.tick(0.4, true), HoldAction.Result.LONG, "累计 0.7 s ≥ 0.6 ⇒ 判定为长按")
	t.eq(h.tick(0.4, true), HoldAction.Result.NONE, "继续按住**不重复触发**（丢一把就够了）")
	t.eq(h.tick(0.01, false), HoldAction.Result.NONE,
		"长按触发后松手**不补一次短按** —— 否则丢完枪又换一次弹")
	t.near(h.progress(), 0.0, 0.0001, "松手后进度归零")
	var h2 := HoldAction.new()
	h2.configure(0.6)
	h2.tick(0.2, true)
	t.eq(h2.tick(0.01, false), HoldAction.Result.SHORT, "半途松手 = 短按（R 的换弹走这条）")

	# ---- 说明书不许撒谎：手柄列必须是「长按 Y」----
	var pad_col := ""
	var b_rows := ""
	for sec: Dictionary in InputSetup.HELP_SECTIONS:
		for it: Array in sec["items"]:
			if str(it[2]) == "长按 B":
				b_rows += str(it[1]) + "|"
			if str(it[1]).contains("丢弃步枪"):
				pad_col = str(it[2])
	t.eq(pad_col, "长按 Y",
		"帮助面板印的是「长按 Y」（`reload` 的手柄键），**不是 B（举盾）**")
	# ⚠️ 这里必须**整串相等**地比，不能用 `contains("长按 B")` ——
	# 那样会被「长按 Back」（第一人称那一行）当场吃掉。
	# 实测：第一版就是 `contains`，跑出来 489 PASS / 1 FAIL，报的正是这一条。
	# 本工程栽过同款的前缀坑（`--only` 匹配路径子串），别再犯。
	t.eq(b_rows, "",
		"没有任何一行的手柄列是「长按 B」（B 现在只是举盾 / 菜单返回）")


# ------------------------------------------------------------ 避地

## 回归测试：用户实测"柯西总是自己一头撞进海里自爆"。
##
## 真凶不是俯冲角度，而是**军刀吸附突进根本没有避地能力**：
## 突进是"朝目标 1150 m/s 直线冲 1.5 秒"（约 1.7 km），期间 `_step_saber`
## 完全接管速度矢量、不接受任何转向输入。旧代码在目标贴海时会一路冲到 27~30 m
## 然后撞海（撞海线 24 m）。
##
## ⚠️ 这条测试**不靠"跑一遍看它飞不飞得出来"** —— 那样写过一次，结果是
## 修复前后都通过：AI 在测试环境里侥幸拉起来了（186 m），在探针里却崩（27 m），
## 对偶然状态太敏感，等于没写。所以这里直接断言**修复机制本身**：
##   1. 门禁：目标或自己太低时不该起手劈；
##   2. 掐断：突进途中高度进入危险区能被直接中断；
##   3. 预判：高速下沉时要按趋势提前拉升，而不是等高度真的掉下来。
## 场景只留两个当冒烟测试。量化用的探针留在 tools/probe_ai_dive.tscn。
static func _terrain_avoidance(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var me := _unit(c, SuitProfile.penelope(), 0, true)
	Game.mark_player(me)
	var foe := BanditAI.new()
	foe.team = 1
	foe.profile = SuitProfile.xi()
	foe.difficulty = Difficulty.make(Difficulty.Level.HARD)   # 630 m/s
	foe.projectile_container = c
	c.add_child(foe)
	foe.global_position = Vector3(0, 1200, 0)
	var lock := LockOnSystem.new()
	host.add_child(lock)
	lock.setup(foe)
	Game.register_lock(foe, lock)
	foe.lock = lock

	# ---- 1. 军刀门禁 ----
	me.global_position = Vector3(0, 2200, -400)
	t.ok(foe.call("_saber_is_viable"), "目标在高空时允许军刀突进")
	me.global_position = Vector3(0, 60, -400)
	t.not_ok(foe.call("_saber_is_viable"), "目标贴着海面（60 m）时禁止军刀突进")
	me.global_position = Vector3(0, 2200, -400)
	foe.global_position = Vector3(0, 500, 0)
	t.not_ok(foe.call("_saber_is_viable"), "自己高度不够时也禁止军刀突进")

	# ---- 2. 突进途中可以掐断 ----
	foe.global_position = Vector3(0, 1400, 0)
	foe.fm.speed = 500.0
	foe.fm.align_velocity(foe.forward())
	t.ok(me.global_position.y > BanditAI.SABER_MIN_TARGET_ALTITUDE, "目标确实在高空")
	t.ok(foe.try_saber(me), "高空目标可以起手军刀突进")
	t.ok(foe.saber_active(), "进入突进状态")
	foe.global_position = Vector3(0, 300, 0)
	t.ok(foe.call("_needs_pull_up"), "突进途中掉到 300 m 会判定为需要拉升")
	foe.abort_saber()
	t.not_ok(foe.saber_active(), "危险高度上突进能被直接掐断")

	# ---- 3. 预判式拉升：按趋势而不是当前高度 ----
	# 这是第二个关键点。旧代码只看当前高度，1500 m 看着很安全，
	# 可是以 -400 m/s 下沉，2.6 秒后就只剩 460 m 了 —— 而 630 m/s 下的
	# 转弯半径就有 360 m，那时候再拉已经来不及。
	foe.global_position = Vector3(0, 4000, 0)
	foe.fm.velocity = Vector3(0, -300.0, -200.0)
	t.not_ok(foe.call("_needs_pull_up"), "4000 m 平缓下沉还不需要紧急拉升")
	foe.global_position = Vector3(0, 1500, 0)
	foe.fm.velocity = Vector3(0, -400.0, -200.0)
	t.ok(foe.call("_needs_pull_up"),
		"1500 m 但以 -400 m/s 下沉时会提前拉升（只看当前高度是看不出来的）")
	foe.global_position = Vector3(0, 650, 0)
	foe.fm.velocity = Vector3(0, 0, -200.0)
	t.ok(foe.call("_needs_pull_up"), "低于临界高度一律拉升")
	t.gt(BanditAI.SAFE_ALTITUDE, BanditAI.CRITICAL_ALTITUDE,
		"外推安全线必须高于临界线")
	t.gt(BanditAI.PULL_UP_LOOKAHEAD, 0.0, "外推时间是正的（否则等于没有预判）")

	# ---- 3.5 地形探头（批 16 防撞地）----
	# 海平面外推（上面 1~3 节测的那套）看不见**山**：山脊上的机 y 很高、
	# 离地可能只有几十米。批 16 给 AI 加了与 FlightAssist 同款的射线探头。
	# 这里铺一块**顶面在 y=0** 的地板，把 foe 放到离地 200 m 平飞：
	# 前下探头（俯角 0.55）在 ~415 m 处触地，300 m/s 下 ≈ 1.4 s，
	# 低于紧急线 TERRAIN_PULL_TIME=2.0 —— 应判紧急拉升。
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(8000, 200, 8000)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3(0, -100, 0)   # 盒子顶面正好 y=0
	floor_body.add_child(floor_shape)
	floor_body.collision_layer = 1               # WORLD 层（探头只打它）
	c.add_child(floor_body)
	foe.global_position = Vector3(0, 200, 0)
	foe.look_at(foe.global_position + Vector3(0, 0, -1), Vector3.UP)
	foe.fm.speed = 300.0
	foe.fm.velocity = foe.forward() * 300.0
	await host.get_tree().physics_frame
	var tt: float = foe.call("_probe_terrain")
	foe.terrain_time = tt                        # 显式喂给软性避地（_think 也会喂，这里求确定）
	t.gt(tt, 0.5, "探头给的秒数是正经的正数（0 或负数说明射线/折算有毛病）")
	t.lt(tt, BanditAI.TERRAIN_PULL_TIME,
		"离地 200 m 平飞：前下探头 %.2f s 内看到地板（< 紧急线 %.1f s）——海平面外推看不见的这一层它看得见"
		% [tt, BanditAI.TERRAIN_PULL_TIME])
	var d1: Vector3 = foe.call("_blend_safety", Vector3(0, 0, -1))
	t.gt(d1.y, 0.3,
		"地形探头到点后，软性避地把期望方向朝上揉（y=%.2f）—— 不夺杆但至少别再往下扎" % d1.y)
	# 地板拿走 → 回到 INF。**空场景不误报**是老冒烟测试（第 4 节）的依赖语义。
	floor_body.queue_free()
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	var tt2: float = foe.call("_probe_terrain")
	t.eq(tt2, INF, "视界内没有地形时探头返回 INF（空场景不误报）")

	# ---- 4. 冒烟：低空诱饵下真飞一遍 ----
	me.global_position = Vector3(0, 60.0, -430.0)
	me.fm.speed = 300.0
	me.fm.align_velocity(me.forward())
	foe.global_position = Vector3(0, 420, 0)
	foe.look_at(foe.global_position + Vector3(0, 0, -1), Vector3.UP)
	foe.fm.speed = 520.0
	foe.fm.throttle = 1.0
	foe.fm.align_velocity(foe.forward())
	var min_alt: float = foe.global_position.y
	for i in 720:
		await host.get_tree().physics_frame
		if not foe.alive:
			break
		min_alt = minf(min_alt, foe.global_position.y)
	t.ok(foe.alive and foe.global_position.y > FlightBody.CRASH_ALTITUDE,
		"低空诱饵下飞 12 秒没有扎进海里（最低 %.0f m，存活=%s）" % [min_alt, str(foe.alive)])

	lock.free()
	c.free()
	await host.get_tree().process_frame


# ------------------------------------------------------------ 丢枪规则表

## 用户明确重申过的三条规则。这里直接查**规则表**，不跑模拟 ——
## 规则表就是"需求的可执行形式"，跑模拟会因为 AI 的行为掺进来而变得不稳定。
##
## 背景：丢枪只对柯西有意义（佩涅罗佩 `can_discard_rifle == false`，而且只带一把枪）。
## 玩家自己操控柯西是**随时可丢、脱锁 15 秒**；下面这三条管的是**敌机柯西**。
static func _discard_rules(t: T) -> void:
	var easy := Difficulty.make(Difficulty.Level.EASY)
	var normal := Difficulty.make(Difficulty.Level.NORMAL)
	var hard := Difficulty.make(Difficulty.Level.HARD)

	t.eq(easy.discard_rules.size(), 1, "简单：只丢一次枪")
	t.eq(float(easy.discard_rules[0]["threshold"]), 0.50, "简单：半血时丢")
	t.eq(float(easy.discard_rules[0]["unlock"]), 0.0,
		"简单：这一次丢枪**只解除锁定**，不给不可锁定状态")

	t.eq(normal.discard_rules.size(), 2, "中等：丢两次枪")
	t.eq(float(normal.discard_rules[0]["threshold"]), 0.50, "中等：半血丢一次")
	t.eq(float(normal.discard_rules[1]["threshold"]), 0.10, "中等：低于 10% 再丢一次")
	for r: Dictionary in normal.discard_rules:
		t.eq(float(r["unlock"]), 7.0, "中等：丢枪后 7 秒不可被锁定")

	t.eq(hard.discard_rules.size(), 3, "困难：丢三次枪")
	t.eq(str(hard.discard_rules[0]["trigger"]), Difficulty.TRIGGER_FIRST_LOCKED,
		"困难：开局第一次被玩家锁定就丢")
	t.eq(float(hard.discard_rules[0]["unlock"]), 7.0, "困难：首次丢枪也是 7 秒不可锁定")
	t.eq(float(hard.discard_rules[1]["threshold"]), 0.50, "困难：半血丢一次")
	t.eq(float(hard.discard_rules[2]["threshold"]), 0.10, "困难：低于 10% 再丢一次")

	# 技能归属
	t.ok(SuitProfile.xi().can_discard_rifle, "柯西可以丢枪")
	t.not_ok(SuitProfile.penelope().can_discard_rifle, "佩涅罗佩不能丢枪")
	t.ok(SuitProfile.xi().rifle_count >= hard.discard_rules.size(),
		"柯西带的枪够困难难度丢满 %d 次" % hard.discard_rules.size())
	# 玩家侧与敌机侧是两套数字：玩家随时可丢、脱锁 15 秒
	t.eq(SuitProfile.xi().discard_unlockable_seconds, 15.0, "玩家自己丢枪脱锁 15 秒")


# ------------------------------------------------------------ 敌机按难度丢枪

static func _ai_discard(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)

	var me := PlayerController.new()
	me.team = 0
	me.is_player = true
	me.profile = SuitProfile.penelope()
	me.projectile_container = c
	c.add_child(me)
	me.global_position = Vector3(0, 3000, 0)
	me.fm.speed = 260.0
	me.fm.throttle = 0.78
	me.fm.align_velocity(me.forward())

	var foe := BanditAI.new()
	foe.team = 1
	foe.profile = SuitProfile.xi()
	foe.difficulty = Difficulty.make(Difficulty.Level.HARD)
	foe.projectile_container = c
	c.add_child(foe)
	foe.global_position = me.global_position + Vector3(0, 0, -1500.0)
	foe.look_at(me.global_position, Vector3.UP)
	foe.fm.speed = 300.0
	foe.fm.align_velocity(foe.forward())
	Game.mark_player(me)

	t.near(foe.fm.max_speed,
		SuitProfile.xi().enemy_top_speed_capped(Difficulty.make(Difficulty.Level.HARD).speed_mult,
			SuitProfile.penelope().player_boost_speed()), 0.5,
		"困难难度敌机的速度上限 = 原始难度表被玩家（佩涅罗佩）加力天花板钳住")
	# ⚠️ 1.2 第二十八轮：出伤倍率**不再是固定的 1.3**，而是
	# `1.3 × 玩家所选机体的 hard_enemy_reinforce` ——
	# 用户要求"困难"要**按玩家选的机体分档**（困难柯西已很难、困难佩涅罗佩太简单）。
	# 这个用例里 `Game.mark_player(me)` 挂的是哪台机，倍率就跟着哪台走，
	# 所以判据要写成"1.3 × 那个系数"，不能写死 1.3。
	t.near(foe.damage_mult, 1.3 * me.profile.hard_enemy_reinforce, 0.001,
		"困难敌机出伤倍率 = 1.3 × 玩家的困难强化系数（%.2f）"
			% (1.3 * me.profile.hard_enemy_reinforce))
	t.eq(foe.rifle_count, 3, "敌机柯西开局 3 把步枪")

	var me_lock := LockOnSystem.new()
	host.add_child(me_lock)
	me_lock.setup(me)
	me_lock.lock_time = 0.1
	Game.register_lock(me, me_lock)
	me.lock = me_lock   # AI 判断"我是否被玩家锁定"就是读这一条
	var foe_lock := LockOnSystem.new()
	host.add_child(foe_lock)
	foe_lock.setup(foe)
	foe_lock.lock_time = 0.1
	Game.register_lock(foe, foe_lock)
	foe.lock = foe_lock

	var frames := 0
	while foe.rifle_count >= 3 and frames < 200:
		await host.get_tree().physics_frame
		frames += 1
	t.lt(foe.rifle_count, 3, "困难难度：第一次被玩家锁定就丢枪（用了 %d 帧）" % frames)
	t.ok(foe.is_unlockable(), "敌机丢枪后同样进入不可被锁定状态")
	t.near(foe.unlockable_seconds_left(), 7.0, 0.6, "敌机丢枪的不可锁定时间是 7 秒")

	me_lock.free()
	foe_lock.free()
	c.free()
	await host.get_tree().process_frame
	Game.reset()
## 近战重做（1.2 用户："近处反应不过来 / 远处砍不到 / 没有打击感"）的三条回归门。
static func _melee_sweep(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var me := _unit(c, SuitProfile.xi(), 0, true)
	var foe := _unit(c, SuitProfile.penelope(), 1)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame

	# ① 玩家吸附距离 620 → 1400（"远处砍不到"），但 **AI 必须还是 620**：
	#    AI 突进期间不接受转向、没有避地能力，放宽它就会重现"AI 一头扎海"。
	t.near(me.saber_magnet_range(), 1400.0, 0.1, "玩家的军刀吸附距离 = 1400 m（放宽）")
	var ai := BanditAI.new()
	ai.team = 1
	ai.profile = SuitProfile.xi()
	ai.difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	c.add_child(ai)
	t.near(ai.saber_magnet_range(), 620.0, 0.1, "**AI 的军刀吸附距离仍然是 620 m**（安全约束）")
	t.near(me.saber_dash_seconds(), 2.4, 0.01, "玩家突进时长 2.4 s")
	t.near(ai.saber_dash_seconds(), 1.5, 0.01, "AI 突进时长仍是 1.5 s")

	# ② 没锁定 + 3 m 掠过 → **必须命中**。
	#    旧实现只对锁定目标判距离，这一条在旧行为下必红 —— 它就是"近处反应不过来"的根因。
	me.global_position = Vector3(0, 3000.0, 0)
	foe.global_position = Vector3(3.0, 3000.0, -30.0)
	me.fm.speed = 600.0
	me.fm.velocity = me.forward() * 600.0
	var hp0 := foe.hp + foe.ifield_hp
	t.ok(me.try_saber(null), "没有锁定也能起手劈砍（判定不再依赖锁定）")
	for i in 40:
		await host.get_tree().physics_frame
	t.lt(foe.hp + foe.ifield_hp, hp0,
		"没锁定 + 3 m 掠过 → 命中（%.0f → %.0f）" % [hp0, foe.hp + foe.ifield_hp])

	# ③ 伤害不再是"挠痒"：一刀 22（原来是 9，而盾有 359~467）
	t.near(SuitProfile.xi().saber_damage, 22.0, 0.01, "柯西军刀一刀 22（原 9）")
	t.near(SuitProfile.penelope().saber_damage, 22.0, 0.01, "佩涅罗佩军刀一刀 22")
	t.near(SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL).saber_damage, 22.0, 0.01,
		"阿利宙斯军刀一刀 22")
	t.near(SuitProfile.xi().saber_interval, 3.2, 0.01, "军刀间隔 2.1 → 3.2 s（否则它会变最优解）")
	c.free()
	await host.get_tree().physics_frame
	Game.reset()


# ------------------------------------------------------------ 批 10：打击感

## 分级顿帧 + 光刃 + 相杀顿帧对称。全部走**直接调用**（不靠帧推进），
## 顿帧值是"当帧读数"，用帧推进等命中会撞上"0.16 s 内就衰减完了"的时序坑。
static func _hit_feel(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)

	# ---- ① 顿帧梯度：相杀 > 军刀 > 默认 ----
	t.gt(FlightBody.HITSTOP_TIME_CLASH, FlightBody.HITSTOP_TIME_SABER,
		"顿帧梯度：相杀比军刀重")
	t.gt(FlightBody.HITSTOP_TIME_SABER, FlightBody.HITSTOP_TIME,
		"顿帧梯度：军刀比默认档重")
	var probe := _unit(c, SuitProfile.xi(), 0, true)
	probe.begin_hitstop()
	t.near(probe._hitstop, FlightBody.HITSTOP_TIME, 0.001, "begin_hitstop() 缺省 = 默认档")
	probe.begin_hitstop(FlightBody.HITSTOP_TIME_CLASH)
	t.near(probe._hitstop, FlightBody.HITSTOP_TIME_CLASH, 0.001,
		"begin_hitstop(时长) 传入什么用什么（分级入口生效）")

	# ---- ② 光刃：起手挂上、收刀摘除 ----
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	var me := _unit(c, SuitProfile.xi(), 0, true)
	var foe := _unit(c, SuitProfile.penelope(), 1)
	foe.global_position = Vector3(0, 3000.0, -400.0)   # 吸附距离内
	await host.get_tree().physics_frame
	t.ok(me.try_saber(foe), "起手成功")
	t.ok(me._blade != null and is_instance_valid(me._blade), "突进期间手上有光束刃")
	t.ok(me._blade.is_inside_tree(), "光刃挂在模型树里（跟随手部锚点）")
	me.abort_saber()
	t.ok(me._blade == null, "收刀（含中断）后光刃摘除")
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame

	# ---- ③ 军刀命中：双方进 0.16 档 + 命中白闪落地 ----
	me.global_position = Vector3(0, 3000.0, 0)
	foe.global_position = Vector3(3.0, 3000.0, -30.0)
	foe.ifield_hp = 0.0   # 清盾：白闪只在**破盾砍到肉**的分支（盾上走 beam_impact 力场波纹）
	me.fm.speed = 600.0
	me.fm.velocity = me.forward() * 600.0
	var hp0 := foe.hp + foe.ifield_hp
	me._slash(foe)
	t.near(me._hitstop, FlightBody.HITSTOP_TIME_SABER, 0.001, "军刀命中：砍的人进 0.16 档")
	t.near(foe._hitstop, FlightBody.HITSTOP_TIME_SABER, 0.001, "军刀命中：被砍的人同档")
	t.lt(foe.hp + foe.ifield_hp, hp0, "命中掉了血（场景有效性自检）")
	var fx_n := 0
	for ch in c.get_children():
		if ch.name == "ImpactFlash":
			fx_n += 1
	t.ok(fx_n >= 1, "命中点落了白闪特效")

	# ---- ④ 相杀：**双方**都进 0.24 档（对称性）+ 冲击波落地 ----
	var a := _unit(c, SuitProfile.xi(), 0, true)
	var b := _unit(c, SuitProfile.penelope(), 1)
	await host.get_tree().physics_frame
	a._begin_clash(b)
	t.near(a._hitstop, FlightBody.HITSTOP_TIME_CLASH, 0.001, "相杀：先检测方进 0.24 档")
	t.near(b._hitstop, FlightBody.HITSTOP_TIME_CLASH, 0.001,
		"相杀：**另一方也顿**（对称性 —— 旧实现只顿一方）")
	var wave := 0
	for ch in c.get_children():
		if ch.name == "ClashShockwave":
			wave += 1
	t.ok(wave >= 1, "拼刀点落了冲击波环")
	t.ok(a._blade == null and b._blade == null, "相杀收刀后双方光刃都摘除")

	c.free()
	await host.get_tree().physics_frame
	Game.reset()


## 辅助飞行（1.2）：四条需求各一条断言。测的是**纯函数核心**，
## 不依赖场景 —— 射线那部分只是"把世界问一遍再喂给它"。
static func _assist(t: T) -> void:
	var fwd := Vector3(0, 0, -1)
	var right := Vector3(1, 0, 0)
	var up := Vector3(0, 1, 0)
	var pref := 3600.0

	# ① 调朝向：目标在斜上右 → 抬杆 + 右滚转
	var c := FlightAssist.correction_for(Vector3(1, 1, -1), fwd, right, up, pref, pref, INF)
	t.gt(c["pitch"], 0.0, "目标在斜上方 → 辅助抬杆")
	t.gt(c["roll"], 0.0, "目标在右前方 → 辅助向右滚转")
	var cl := FlightAssist.correction_for(Vector3(-1, -1, -1), fwd, right, up, pref, pref, INF)
	t.lt(cl["pitch"], 0.0, "目标在斜下方 → 辅助压杆")
	t.lt(cl["roll"], 0.0, "目标在左前方 → 辅助向左滚转")

	# ② **修正量受限** —— 这条是"玩家仍能操控上下左右"的量化保证：
	#    辅助最多出到 CAP（0.55），玩家满杆 ±1.0 永远盖得过。
	t.near(c["pitch"], FlightAssist.CAP, 0.001, "大幅偏差时抬杆修正被夹在 CAP")
	t.near(c["roll"], FlightAssist.CAP, 0.001, "滚转修正也被夹在 CAP")
	t.lt(FlightAssist.CAP, 1.0, "CAP 必须小于 1 —— 否则辅助就会「盖过」玩家")

	# ③ 保持索敌距离：太近减油门、太远加油门、带内不干预
	t.lt(FlightAssist.correction_for(fwd, fwd, right, up, 800.0, pref, INF)["throttle"], 0.0,
		"太近 → 减油门（拉开距离）")
	t.gt(FlightAssist.correction_for(fwd, fwd, right, up, 9000.0, pref, INF)["throttle"], 0.0,
		"太远 → 加油门（追上去）")
	t.eq(FlightAssist.correction_for(fwd, fwd, right, up, pref, pref, INF)["throttle"], 0.0,
		"带内不干预（死区，留给玩家自己飞）")
	# 没有目标时不做距离干预（否则会莫名其妙地加油门）
	t.eq(FlightAssist.correction_for(Vector3.ZERO, fwd, right, up, 0.0, pref, INF)["throttle"], 0.0,
		"没有锁定目标时不动油门")

	# ④ 规避障碍物：越近抬得越狠
	var near := FlightAssist.correction_for(fwd, fwd, right, up, pref, pref, 0.20)
	var far := FlightAssist.correction_for(fwd, fwd, right, up, pref, pref, 9.0)
	t.gt(near["pitch"], far["pitch"], "障碍越近抬杆越多")
	t.gt(near["pitch"], 0.5, "秒级障碍 → 明显抬杆（躲得开）")
	t.near(far["pitch"], 0.0, 0.001, "远处没有障碍 → 不干预")

	# ⑤ **地面否决式兜底**（1.2 用户实测"偶尔会自己往地上撞"）。
	#    根因：朝向修正会把机头指向目标，目标在下方时那就是一条俯冲指令，
	#    而规避只是"追加"抬杆 —— 加不过俯冲。所以近地时必须**否决**：
	#    抬杆修正不允许为负。这一条在旧实现下必红（旧实现给的是负值 → 往地里按）。
	var dive_low := FlightAssist.correction_for(Vector3(0, -1, -1), fwd, right, up, pref, pref,
		9.0, 0.25)
	t.gt(dive_low["pitch"], 0.0, "近地时即使目标在下方，辅助也只许抬杆（不许俯冲）")
	var dive_high := FlightAssist.correction_for(Vector3(0, -1, -1), fwd, right, up, pref, pref,
		9.0, 9.0)
	t.lt(dive_high["pitch"], 0.0, "高空时俯冲指令照旧生效（兜底不能把正常瞄准也锁死）")

	Game.reset()
## 辅助飞行的**地面探头**：带姿态的断言（1.2）。
##
## 为什么必须有这一条：纯函数断言（`_assist` 里那两条）传的是"我算出来的 ground_time"，
## 所以它**永远绿** —— 它测的是"我算得对不对"，测不到"**射线有没有打中地面**"。
## 而这里恰恰出过一个真 bug：两条探头原来沿**机体自己的 up** 往下打，
## 一压坡度 `basis.y` 就接近水平，射线朝侧面飞出去 → 平飞有效、**侧倾等于失效**。
## 所以这一条专测姿态：平飞 / 侧倾 80° / 倒飞，三种都必须探到地面。
static func _assist_probe(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	# 一块静态"地面"，放在机体下方 400 m
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6000.0, 40.0, 6000.0)
	cs.shape = box
	ground.add_child(cs)
	c.add_child(ground)
	ground.global_position = Vector3(0, -400, 0)
	var pc := PlayerController.new()
	pc.profile = SuitProfile.xi()
	pc.is_player = true
	pc.team = 0
	c.add_child(pc)
	pc.set_physics_process(false)
	pc.global_position = Vector3.ZERO
	# 探头长度 = 速度 × 视界：速度给 300，视界 2.8 s → 840 m > 400 m，够得着
	pc.fm.speed = 300.0
	await host.get_tree().physics_frame
	var probe := FlightAssist.new()
	var flat: float = probe.call("_probe_down", pc, Vector3.UP)
	t.lt(flat, 400.0, "平飞：探到地面（%.2f s 后撞）" % flat)
	# **侧倾 80°** —— 旧实现（沿机体 up）在这里必然返回 INF
	pc.global_transform = Transform3D(
		Basis(Vector3.FORWARD, deg_to_rad(80.0)), pc.global_position)
	var rolled: float = probe.call("_probe_down", pc, pc.global_transform.basis.y)
	t.lt(rolled, 400.0,
		"侧倾 80° 仍然探到地面（%.2f s）—— 必须沿**世界**向下，不能沿机体 up" % rolled)
	# 倒飞
	pc.global_transform = Transform3D(Basis(Vector3.FORWARD, PI), pc.global_position)
	var inverted: float = probe.call("_probe_down", pc, pc.global_transform.basis.y)
	t.lt(inverted, 400.0, "倒飞仍然探到地面（%.2f s）" % inverted)
	# 把机体抬到地面 5 km 之上 → 应当探不到（别把"永远返回有限值"当成通过）
	pc.global_transform = Transform3D(Basis(), pc.global_position + Vector3(0, 5000.0, 0))
	var high: float = probe.call("_probe_down", pc, Vector3.UP)
	t.eq(high, INF, "高空：探不到地面（返回 INF，不做无谓的抬杆）")
	c.free()
	Game.reset()


# ------------------------------------------------------------ 光束军刀配色（2026-09-29）
#
# 用户原话：「柯西的光束军刀应该是绿色的」
#           「佩涅罗佩的是粉色的，阿利宙斯的是紫色的」。
#
# 改动把军刀刃色做成**按机体可指定**（`SuitProfile.saber_beam_color`，alpha=0 = 没指定）。
# 判据同时钉住**五件事**，少一件就会漏：
#   ① 三台机**各自**指定了正确主色（不是"碰巧 accent 对上了"）；
#   ② 没被点名的机体**没被连带改色**（含阿利宙斯的**核心形态**）；
#   ③ `FX` 在**没指定**时逐位等于老粉白 —— 否则等于偷偷改了所有机体；
#   ④ 指定了主色时内芯 / 残影 / 点光**由主色推**（否则绿刀配粉芯，additive 下会串色）；
#   ⑤ **材质**上真的被写进去了（不是只改了数据字段）。
static func _saber_color(t: T) -> void:
	# =========================================================== ① 三台机各自的主色
	#
	# 判据用**色相关系**（谁比谁高）而不是钉死 RGB —— 以后微调色值不会假红；
	# 但"没指定 / 指定错 / 抄错通道"都能让它变红。
	# ---- 柯西：绿色（g 独高）----
	var xi := SuitProfile.xi()
	t.gt(xi.saber_beam_color.a, 0.0, "柯西：单独指定了军刀颜色（alpha > 0）")
	t.gt(xi.saber_beam_color.g, xi.saber_beam_color.r + 0.3,
		"柯西：军刀是**绿色**（g=%.2f 明显高于 r=%.2f）"
		% [xi.saber_beam_color.g, xi.saber_beam_color.r])
	t.gt(xi.saber_beam_color.g, xi.saber_beam_color.b + 0.3,
		"柯西：军刀是**绿色**（g=%.2f 明显高于 b=%.2f）"
		% [xi.saber_beam_color.g, xi.saber_beam_color.b])
	t.eq(xi.saber_beam_color.a, 1.0, "柯西：alpha = 1（不是半透明）")

	# ---- 佩涅罗佩：粉色（r 最高、b 居中、g 最低）----
	var pe := SuitProfile.penelope()
	t.gt(pe.saber_beam_color.a, 0.0, "佩涅罗佩：单独指定了军刀颜色")
	t.gt(pe.saber_beam_color.r, pe.saber_beam_color.g + 0.3,
		"佩涅罗佩：军刀是**粉色**（r=%.2f 明显高于 g=%.2f）"
		% [pe.saber_beam_color.r, pe.saber_beam_color.g])
	t.gt(pe.saber_beam_color.b, pe.saber_beam_color.g + 0.3,
		"佩涅罗佩：军刀是**粉色**（b=%.2f 也高于 g=%.2f —— 粉是「红+蓝」不是纯红）"
		% [pe.saber_beam_color.b, pe.saber_beam_color.g])
	t.lt(pe.saber_beam_color.g, xi.saber_beam_color.g, "佩涅罗佩的绿通道低于柯西（粉 ≠ 绿）")

	# ---- 阿利宙斯：紫色（b 与 r 都高于 g）----
	var az := SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL)
	var azc := SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE)
	for p: SuitProfile in [az, azc]:
		t.gt(p.saber_beam_color.a, 0.0, "%s：单独指定了军刀颜色" % p.display_name)
		t.gt(p.saber_beam_color.b, p.saber_beam_color.g + 0.3,
			"%s：军刀是**紫色**（b=%.2f 明显高于 g=%.2f）"
			% [p.display_name, p.saber_beam_color.b, p.saber_beam_color.g])
		t.gt(p.saber_beam_color.r, p.saber_beam_color.g + 0.3,
			"%s：军刀是紫色（r=%.2f 也高于 g —— 紫是「红+蓝」不是纯蓝）"
			% [p.display_name, p.saber_beam_color.r])
	# 与它自己的**步枪光束同色**：一台机的能量兵器应当同色。
	# ⚠️ 只比 RGB：步枪那个的 alpha 是 0.96（弹体带一点透明），
	# 军刀的 alpha 是 1.0（不透明由材质管）—— 那个差异不是 bug，别钉掉。
	t.near(az.saber_beam_color.r, az.rifle_beam_color.r, 0.001,
		"阿利宙斯：军刀 r = 步枪 r")
	t.near(az.saber_beam_color.g, az.rifle_beam_color.g, 0.001,
		"阿利宙斯：军刀 g = 步枪 g")
	t.near(az.saber_beam_color.b, az.rifle_beam_color.b, 0.001,
		"阿利宙斯：军刀 b = 步枪 b（同机能量兵器同色）")
	t.eq(az.saber_beam_color.a, 1.0, "阿利宙斯：军刀 alpha = 1")

	# =========================================================== ② 改色不许溢出
	#
	# ⚠️ 这一条才是"改色不许溢出"的守卫：柯西的 accent 是琥珀橙，
	# 若军刀色写成 `accent` 兜底，阿利宙斯常态（橙）/ 梅萨（红）的刀会跟着变。
	for p: SuitProfile in [
			SuitProfile.gustav00(),
			SuitProfile.gustav00_armed(),
			SuitProfile.messer_m01()]:
		t.eq(p.saber_beam_color.a, 0.0,
			"%s：没被点名 ⇒ 不指定军刀色（走默认粉白）" % p.display_name)
	# ★ 核心形态：★63-14 之前它在本名单里（"同一个 profile 函数的另一个分支，
	# 最容易被给阿利宙斯加色时顺手带上" —— 那时它没有军刀，上色没有意义）。
	# 它拿到军刀之后**方向反过来**：现在必须**有色**，而且要与阿利宙斯本体同色
	#（用户 2026-10-05 拍板：「紫（跟阿利宙斯本体）」，为的是保住"绿 / 粉 / 紫不撞色"）。
	# ⚠️ 这一条同时是"顺手带上"的**正向**守卫：核心掉回默认粉白（alpha 0）会让它红。
	var core_nu_p := SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU)
	t.gt(core_nu_p.saber_beam_color.a, 0.0,
		"★ 阿利宙斯·核心形态**有**军刀色了（★63-14：它拿到军刀）")
	t.eq(core_nu_p.saber_beam_color,
		SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL).saber_beam_color,
		"★ 核心与阿利宙斯本体**军刀同色**（用户拍板：紫）")
	# 三台机的主色互不相同（防复制粘贴把三台设成同一个色）
	t.ok(xi.saber_beam_color != pe.saber_beam_color
			and pe.saber_beam_color != az.saber_beam_color
			and xi.saber_beam_color != az.saber_beam_color,
		"三台机的主色两两不同（绿 / 粉 / 紫）")

	# =========================================================== ③ FX 默认色逐位不变
	var none := Color(0.0, 0.0, 0.0, 0.0)
	t.eq(FX.saber_tint_of(none), Color(1.0, 0.45, 0.9), "FX：没指定 ⇒ 刃色逐位 = 老粉白")
	t.eq(FX.saber_core_of(none), Color(1.0, 0.92, 1.0), "FX：没指定 ⇒ 内芯逐位 = 老近白")
	t.eq(FX.saber_ghost_of(none), Color(1.0, 0.72, 0.96), "FX：没指定 ⇒ 残影逐位 = 老淡粉")
	t.eq(FX.saber_light_of(none), Color(1.0, 0.6, 0.95), "FX：没指定 ⇒ 点光逐位 = 老粉光")

	# =========================================================== ④ 指定了 ⇒ 全套由主色推
	var green := Color(0.40, 1.0, 0.50, 1.0)
	var bt := FX.saber_tint_of(green)
	t.near(bt.r, 0.40, 0.001, "FX：指定 ⇒ 刃色 r 跟着主色")
	t.near(bt.g, 1.00, 0.001, "FX：指定 ⇒ 刃色 g 跟着主色")
	t.near(bt.b, 0.50, 0.001, "FX：指定 ⇒ 刃色 b 跟着主色")
	t.eq(bt.a, 1.0, "FX：指定 ⇒ alpha 归一到 1（半透明的主色也当实色用）")
	var bc := FX.saber_core_of(green)
	t.gt(bc.g, bc.r + 0.10, "FX：指定绿主色 ⇒ 内芯**不带粉**（g 高于 r）")
	t.lt(absf(bc.b - bc.r), 0.08, "FX：内芯的 r 与 b 接近（不偏色）")
	t.gt(bc.g, 0.95, "FX：内芯仍很亮（additive 下才读得出「高温细芯」）")
	var bg := FX.saber_ghost_of(green)
	t.gt(bg.g, bg.r + 0.05, "FX：指定绿主色 ⇒ 残影也是绿的（g 高于 r）")
	var bl := FX.saber_light_of(green)
	t.gt(bl.g, bl.r + 0.05, "FX：指定绿主色 ⇒ 点光也是绿的（g 高于 r）")
	# ★ 三台机的主色各推一套：证明「跟着主色走」不是只对绿色成立的巧合
	for c: Color in [xi.saber_beam_color, pe.saber_beam_color, az.saber_beam_color]:
		var core := FX.saber_core_of(c)
		var tint := FX.saber_tint_of(c)
		t.eq(signf(core.r - core.b), signf(tint.r - tint.b),
			"内芯的 r/b 偏向与主色同号（主色 %s）" % str(c))
		t.gt(core.g, 0.78, "内芯仍是亮色（g=%.2f）" % core.g)

	# =========================================================== ⑤ 材质上真的生效
	var blade := FX.beam_blade(15.0, green)
	t.ok(blade != null, "FX：能建出刀刃")
	if blade != null:
		t.eq(blade.get_child_count(), 2, "刀刃 = 外层刃 + 内芯两层")
		var outer := blade.get_child(0) as MeshInstance3D
		var mat := outer.mesh.material as StandardMaterial3D
		t.near(mat.albedo_color.g, 1.0, 0.001, "刀刃外层材质：g = 1.0（绿）")
		t.gt(mat.albedo_color.g, mat.albedo_color.r + 0.3, "刀刃外层材质：g 明显高于 r")
		t.near(mat.emission.g, 1.0, 0.001, "刀刃外层自发光也跟着变绿")
		var inner := blade.get_child(1) as MeshInstance3D
		var mat_in := inner.mesh.material as StandardMaterial3D
		t.gt(mat_in.albedo_color.g, mat_in.albedo_color.r + 0.10,
			"刀刃内芯材质也是绿的（不串粉）")
		blade.free()
	# ★ 换**阿利宙斯的紫**再走一遍（换一种色相，证明不是"绿写死了"）
	var blade_az := FX.beam_blade(15.0, az.saber_beam_color)
	var outer_az := blade_az.get_child(0) as MeshInstance3D
	var mat_az := outer_az.mesh.material as StandardMaterial3D
	t.gt(mat_az.albedo_color.b, mat_az.albedo_color.g + 0.3,
		"紫主色 ⇒ 刀刃材质 b 明显高于 g（材质真的跟着机体走）")
	blade_az.free()
	# 负对照：不传 tint ⇒ 材质必须**逐位**回到老粉白
	var blade_def := FX.beam_blade()
	var outer_def := blade_def.get_child(0) as MeshInstance3D
	var mat_def := outer_def.mesh.material as StandardMaterial3D
	t.eq(mat_def.albedo_color, Color(1.0, 0.45, 0.9),
		"不传 tint ⇒ 刀刃材质逐位 = 老粉白（其余机体零影响）")
	var inner_def := blade_def.get_child(1) as MeshInstance3D
	var mat_def_in := inner_def.mesh.material as StandardMaterial3D
	t.eq(mat_def_in.albedo_color, Color(1.0, 0.92, 1.0),
		"不传 tint ⇒ 内芯材质逐位 = 老近白")
	blade_def.free()


static func _beam_color(t: T) -> void:
	# =========================================================== (1) 数据侧：她是粉紫
	#
	# 用户 2026-09-30：「佩涅罗佩的光束大炮和光束步枪的子弹颜色都改成粉紫色」。
	#
	# ★ 一个字段管**两条**通道：`rifle_beam_color` 经 `beam_color()` 同时喂
	#   步枪弹体（`FlightBody.fire_beam` -> `Projectile.beam`）与大炮光柱
	#   （`FlightBody.fire_cannon` -> `BeamCannon.launch`）=> "两样都改"只需一行。
	#   真机像素上**分别**验这两条通道的是 `tools/penelope_beam_color_shot.gd`。
	#
	# ★ 判据取**通道主导**而不是色相：她那支粉紫（290°）与阿利宙斯的紫（272°）
	#   在真机像素上会被渲染管线压到同一格（见 skill `godot-additive-fx-color-verdict`），
	#   而"谁比谁高"这条通道关系是**保序**的 => 判它。
	var pe := SuitProfile.penelope()
	var pe_beam: Color = pe.beam_color()
	t.gt(pe_beam.a, 0.0, "佩涅罗佩：单独指定了光束颜色（没退回 accent）")
	t.eq(pe.rifle_beam_color.a, 1.0, "佩涅罗佩：光束色是实色（alpha = 1）")
	t.gt(pe_beam.r, pe_beam.g, "佩涅罗佩：光束 R > G（不是老兜底那个蓝 —— 它 R<G）")
	t.gt(pe_beam.b, pe_beam.g, "佩涅罗佩：光束 B > G（不是绿）")
	t.gt(pe_beam.b, pe_beam.r, "佩涅罗佩：光束 B > R（偏紫那一头）")
	t.gt(pe_beam.r, 0.80, "佩涅罗佩：R 也被抬起（%.2f > 0.80）—— 这是「粉」的成分" % pe_beam.r)
	t.gt(pe_beam.b, 0.99, "佩涅罗佩：B 满格（%.2f）" % pe_beam.b)
	# 三台机的主色**不能撞**：她与阿利宙斯的光束色必须是两个不同的值。
	t.ok(pe_beam != SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL).beam_color(),
		"佩涅罗佩的光束色 != 阿利宙斯的紫（两台机不撞色）")
	# ★ **写穿的守卫**（这一条才是真判据，不是同义反复）：
	#   历史坑是"为了改光束色去动 `accent`"，而那个颜色同时管主菜单卡片 / 敌机列表 /
	#   HUD 强调色。若有人把 accent 改成粉紫，`beam_color()` 照样是粉紫 ——
	#   上面那些通道判据**全都还会绿**，只有本条会红。
	t.eq(pe.accent, Color(0.52, 0.76, 1.0),
		"佩涅罗佩的 accent 未被改动（仍是老蓝 —— 光束色没写穿到 UI 配色）")
	t.ok(pe_beam != pe.accent, "光束色与 accent 是两个不同的值（改的是字段不是 accent）")

	# =========================================================== (2) 改色不许溢出到别的机体
	#
	# 与 `_saber_color` 的第 (2) 节同源：只有**被点名**的机体才显式指定。
	for p: SuitProfile in [
			SuitProfile.xi(),
			SuitProfile.gustav00(),
			SuitProfile.gustav00_armed(),
			SuitProfile.messer_m01(),
			SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU)]:
		t.eq(p.rifle_beam_color.a, 0.0,
			"%s：没被点名 => 不单独指定光束色（仍走 accent 兜底）" % p.display_name)
	# 柯西是"另一台玩家机"，最容易被"给佩涅罗佩加色"顺手带上 => 单独再钉一遍。
	t.eq(SuitProfile.xi().beam_color(), SuitProfile.xi().accent,
		"柯西：光束色仍 = 它自己的 accent（一个字节都没动）")

	# =========================================================== (3) 接线：两条通道同源
	#
	# 守的是"**改了一个、漏了另一个**"：需求说"两样都改"，产品侧是**共用**一个取色口。
	# 谁哪天把某一条改成别的颜色（或写死），这里必须红。
	var fb := _code("res://scripts/flight/flight_body.gd")
	t.ok(fb != "", "读到了 flight_body.gd 且剥掉了注释行")
	var beam_body := _fn_body(fb, "func fire_beam(")
	var cannon_body := _fn_body(fb, "func fire_cannon(")
	t.ok(beam_body != "", "取到了 fire_beam() 的函数体")
	t.ok(cannon_body != "", "取到了 fire_cannon() 的函数体")
	t.ok(beam_body.contains("profile.beam_color()"),
		"★ 步枪弹体（fire_beam）读的就是 profile.beam_color()")
	t.ok(cannon_body.contains("profile.cannon_color()"),
		"大炮光柱读取 profile.cannon_color()，允许步枪与照射独立配色")
	# 反面：这两条不许出现写死的粉紫（那正是"漏了一条"的样子）。
	t.ok(not beam_body.contains("Color(0.90"),
		"fire_beam 没把粉紫写死（必须走 profile）")
	t.ok(not cannon_body.contains("Color(0.90"),
		"fire_cannon 没把粉紫写死（必须走 profile）")

	# ------------------------------------------------------------ 已知边界（不是缺陷）
	#
	# 联机里"对面那一发"走的是 `main.gd::_on_net_fire()`，它用的是一个**与机体无关**的
	# 固定观感色（`SuitProfile.penelope().accent`）—— 那是"对手的弹道"的统一配色，
	# 不是"佩涅罗佩的子弹"。本轮需求只管她自己的武器，所以**刻意不动它**。
	# 这里只把边界写下来，免得下一个人以为它是被漏掉的。
	print("  NOTE  联机观感弹丸（main.gd::_on_net_fire）用的是固定色，与本需求无关（刻意不动）")


static func _code(path: String) -> String:
	# 剥掉**整行注释**后的源码（与 `suite_penelope_cannon._code()` 同一口径）。
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt := f.get_as_text()
	f.close()
	var out := ""
	for line in txt.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out += line + "\n"
	return out


static func _fn_body(src: String, header: String) -> String:
	# 取 `header` 起、到**下一个顶层函数**之前的一段。
	# 终止符两个都要找：`\nfunc ` 匹配不到 `\nstatic func `。
	var i := src.find(header)
	if i < 0:
		return ""
	var j := src.length()
	var seps: Array[String] = ["\nfunc ", "\nstatic func "]
	for sep: String in seps:
		var k := src.find(sep, i + 1)
		if k >= 0 and k < j:
			j = k
	return src.substr(i, j - i)


## 军刀**刀身**的挂点（轮 63-4）。用户原话：
##「光束军刀刀身在游戏内不显示（柯西是双头剑，上长下短）」
##
## ## 这一节存在的全部理由：**旧断言测的是仪器、不是产品**
##
## 旧的两条（`_hit_feel` 里）只问"`_blade` 节点存在吗 / 在树里吗"。
## 而刀原来是挂在 `rig`（**占位骨架**）的 `hand_L` 槽位上的 —— 只要有真模型
##（= **所有机体的常态**），`FlightBody:1231` 的 `set_placeholder_visible(false)`
## 就把整棵占位子树隐藏了 ⇒ 两条断言**全绿**、刀**一个像素都不显示**。
##
## 所以这里一律问"**看得见吗**"与"**在对的位置吗**"：
##   ① `_blade.is_visible_in_tree()`（这一条就是用户报的那个 bug）；
##   ② 刀根贴着**真骨** `hand_L` 的世界原点（挂回占位骨架 ⇒ 位置对不上 ⇒ 红）；
##   ③ 柯西是双头剑：前 15 / 后 9、两段严格反向（点积 ≈ −1）；
##   ④ 其余机体仍是单头剑（`saber_double == false`、后刃 0、前刃 15.0）。
static func _saber_blade_attach(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	# ⚠️ `use_placeholder` 是 **static**：显式写死，免得被别的套件留的脏值影响
	#（"有真模型"是本节整节的前置 —— 它不成立的话本节会退化成"在仪器上绿"）。
	var prev_placeholder: bool = FlightBody.use_placeholder
	FlightBody.use_placeholder = false

	var me := _unit(c, SuitProfile.xi(), 0, true)
	var foe := _unit(c, SuitProfile.penelope(), 1)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	foe.global_position = Vector3(0, 3000.0, -400.0)   # 吸附距离内
	await host.get_tree().physics_frame

	# ---- 前置：柯西必须真的加载了骨架 ----
	t.ok(me._model_skel != null, "（前置）柯西加载了真模型骨架 `_model_skel`")
	t.ok(me._bone_index("hand_L") >= 0, "（前置）真骨架里有 `hand_L` 骨（挂在 `LowerArm.L` 下）")
	if me._model_skel == null or me._bone_index("hand_L") < 0:
		FlightBody.use_placeholder = prev_placeholder
		c.free()
		return

	t.ok(me.try_saber(foe), "起手成功")
	t.ok(me._blade != null and is_instance_valid(me._blade), "突进期间手上有光束刃")

	# ---- ① 可见性：**用户报的就是这一条** ----
	t.ok(me._blade.is_visible_in_tree(),
		"光刃**在树里可见**（旧实现挂在被隐藏的占位骨架上 ⇒ 恒 false）")
	# ---- ①②的路径守卫：必须走"真骨 + 独立锚点"那条路 ----
	t.ok(me._blade_anchor != null and is_instance_valid(me._blade_anchor),
		"真模型路径下用**独立锚点**（`_blade_anchor`），不是占位骨架")
	t.ok(me._blade.get_parent() == me._blade_anchor,
		"刀挂在锚点下 —— 挂回占位骨架 `rig.slot()` 这条会红")
	if me.rig != null:
		t.ok(not me.rig.is_ancestor_of(me._blade),
			"刀**不是**占位骨架 `rig` 的后代（旧实现就是它，整棵子树被隐藏）")

	# ---- ② 位置：贴着**真骨** hand_L（与 `rig_anchor()` 同口径）----
	var idx := me._bone_index("hand_L")
	var bone_world: Vector3 = (me._model_skel.global_transform
		* me._model_skel.get_bone_global_pose(idx)).origin
	var off: float = me._blade.global_position.distance_to(bone_world)
	t.lt(off, 0.5, "刀根贴着真骨 `hand_L` 的世界原点（差 %.3f m ≤ 0.5 m）" % off)

	# ---- ③ 双头剑：柯西 前 15 / 后 9，两段严格反向 ----
	var meshes: Array = []
	for ch in me._blade.get_children():
		if ch is MeshInstance3D:
			meshes.append(ch)
	t.eq(meshes.size(), 4, "双头剑 = 4 段网格（前刃外/芯 + 后刃外/芯）")
	var f_len := 0.0
	var r_len := 0.0
	var f_dir := Vector3.ZERO
	var r_dir := Vector3.ZERO
	for mi: MeshInstance3D in meshes:
		var cyl := mi.mesh as CylinderMesh
		if cyl == null or is_zero_approx(mi.position.z):
			continue
		# 「刃尖朝向」= 圆柱收细那一端（`bottom_radius` = 局部 −Y）在世界里的方向
		var tip: Vector3 = -(mi.global_transform.basis.y).normalized()
		if mi.position.z < 0.0:
			f_len = maxf(f_len, cyl.height)
			f_dir = tip
		else:
			r_len = maxf(r_len, cyl.height)
			r_dir = tip
	var xi := SuitProfile.xi()
	t.near(f_len, xi.saber_blade_front, 0.01,
		"前刃长 == `saber_blade_front` = %.1f m" % xi.saber_blade_front)
	t.near(r_len, xi.saber_blade_rear, 0.01,
		"后刃长 == `saber_blade_rear` = %.1f m" % xi.saber_blade_rear)
	t.gt(f_len, r_len, "上/前刃比下/后刃**长**（用户：「上长下短」）")
	t.near(f_dir.dot(r_dir), -1.0, 0.01,
		"两段刀身**严格反向**（刃尖方向点积 = %.4f ≈ −1）" % f_dir.dot(r_dir))

	# ---- ④ 默认不回归：其余机体仍是单头剑 ----
	for p: SuitProfile in [SuitProfile.penelope(), SuitProfile.gustav00(),
			SuitProfile.messer_m01(), SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL),
			SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE),
			SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU)]:
		t.not_ok(p.saber_double, "%s：不是双头剑" % p.display_name)
		t.near(p.saber_blade_rear, 0.0, 0.0001, "%s：后刃 0（不画后刃）" % p.display_name)
		t.near(p.saber_blade_front, 15.0, 0.0001,
			"%s：前刃仍是 15.0 m（与新增字段之前逐位一致）" % p.display_name)

	me.abort_saber()
	FlightBody.use_placeholder = prev_placeholder
	c.free()
	await host.get_tree().physics_frame


# ------------------------------------------------------------ ★63-14 核心 · 量产型ν高达

## ★63-14：核心 · 量产型ν高达 拿到**光束军刀 + 光束大炮**。
##
## 用户原话：「给量产型牛高达增加光束军刀和光束大炮」。
##
## ## 为什么它配得上单独一节
## 核心形态是本工程**唯一**一个"先被产品显式关掉武器、又被要求打开"的形态：
## `p.has_saber = false` 那一行在 `arizeus()` 里躺了整整一轮，而且有**三条下游**
## 在替它说话（文件顶部的形态说明 / `lore` / `blurb`）。翻正它要同时守住四件事：
##
##   ① **数据层**：`has_saber` / `cannon_enabled` 为真，而 `rifle_fire_on_release`
##      **仍为假** —— 否则 8 发 / 0.62 s 的连发枪被静默废掉，玩家读不出原因；
##   ② **门禁**：军刀挥得出（`try_saber`）、大炮放得出（满弹匣），且硬门槛不松；
##   ③ **挂点**：核心的模型是 `nu_mp_fly.glb`，刀必须挂在**它的真骨** `hand_L` 上。
##      挂回占位骨架就是"刀一个像素都不显示"那个老坑，而且**断言全绿**；
##   ④ **文案**：`lore` / `blurb` 不许再说"只剩光束步枪与火神炮"。
##
## ⚠️ **负对照**：把 `p.has_saber` 改回 `false` ⇒ ①②③ 三条一起红（本节就是靶子）。
## ⚠️ 大炮的**路由**判据在 `suite_penelope_cannon.gd`（它走的是佩涅罗佩那条条件路由），
##    数据层与门禁判据在 `suite_arizeus_cannon.gd`；本节只补"核心自己这一台"的账。
static func _core_nu_weapons(t: T, host: Node) -> void:
	var core := SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU)
	var normal := SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL)

	# ---- ① 数据层 ----
	t.ok(core.has_saber, "★63-14 ① 核心有光束军刀")
	t.ok(core.cannon_enabled, "★63-14 ① 核心有蓄力激光炮")
	t.not_ok(core.rifle_fire_on_release,
		"★63-14 ① 但它**没有**变成松手单发（8 发 / 0.62 s 的连发枪不能被静默废掉）")
	var slots := core.weapon_slots()
	t.eq(slots.size(), 2, "★63-14 ① 武器槽 = 2 件（没有手雷 / 导弹槽）")
	t.ok(slots.has("rifle") and slots.has("saber"), "★63-14 ① 两件就是步枪 + 军刀")
	t.eq(core.saber_beam_color, normal.saber_beam_color,
		"★63-14 ① 军刀与阿利宙斯本体**同色**（用户拍板：紫）")

	# ---- ④ 玩家可见文案：不许再撒谎 ----
	t.not_ok(core.lore.contains("没有浮游导弹与光束军刀"),
		"★63-14 ④ `lore` 不再说「没有浮游导弹与光束军刀」")
	t.not_ok(core.blurb.contains("但只有光束步枪与火神炮"),
		"★63-14 ④ `blurb` 不再说「但只有光束步枪与火神炮」")

	# ---- ②③ 运行时：真模型 + 真骨挂点 + 挥得出刀 ----
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	# ⚠️ `use_placeholder` 是 **static**：显式写死，免得被别的套件留的脏值影响
	#（"有真模型"是本节 ③ 的前置 —— 它不成立的话本节会退化成"在仪器上绿"）。
	var prev_placeholder: bool = FlightBody.use_placeholder
	FlightBody.use_placeholder = false

	var me := _unit(c, core, 0, true)
	var foe := _unit(c, SuitProfile.penelope(), 1)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	foe.global_position = Vector3(0, 3000.0, -400.0)   # 吸附距离内
	await host.get_tree().physics_frame

	t.ok(me._model_skel != null, "★63-14 ③ 核心加载了真模型骨架")
	t.ok(me._bone_index("hand_L") >= 0,
		"★63-14 ③ `nu_mp_fly.glb` 里有**真骨** `hand_L`（没有它刀会挂回被隐藏的占位骨架）")
	t.ok(me.try_saber(foe), "★63-14 ② 核心劈得出光束军刀")
	t.ok(me._blade != null and is_instance_valid(me._blade), "突进期间手上有光束刃")
	t.ok(me._blade.is_visible_in_tree(), "★63-14 ③ 光刃**在树里可见**")
	t.ok(me._blade_anchor != null and is_instance_valid(me._blade_anchor),
		"★63-14 ③ 走的是**真骨锚点**那条路（`_blade_anchor`）")
	if me.rig != null:
		t.ok(not me.rig.is_ancestor_of(me._blade),
			"★63-14 ③ 刀**不是**占位骨架 `rig` 的后代")
	if me._model_skel != null and me._bone_index("hand_L") >= 0:
		var idx := me._bone_index("hand_L")
		var bone_world: Vector3 = (me._model_skel.global_transform
			* me._model_skel.get_bone_global_pose(idx)).origin
		var off: float = me._blade.global_position.distance_to(bone_world)
		t.lt(off, 0.5, "★63-14 ③ 刀根贴着核心真骨 `hand_L`（差 %.3f m ≤ 0.5 m）" % off)
	# 挥砍动作：`nu_mp_slash.glb` 必须真的被摘进动作库（登记了但摘不到 = 挥刀无动作）
	t.ok(me.model_anim != null and me.model_anim.has("slash"),
		"★63-14 ② 核心的动作库里有 `slash`（`nu_mp_slash.glb`）")

	# ---- ② 大炮：满弹匣放得出、打剩一发放不出 ----
	var c2 := Node3D.new()
	host.add_child(c2)
	var can := _unit(c2, core, 0)
	await host.get_tree().physics_frame
	t.ok(can.cannon_available(), "★63-14 ② 核心 `cannon_available()` 为真")
	t.ok(can.cannon_ready(), "★63-14 ② 出场满弹匣（%d 发）⇒ 就绪" % core.rifle_magazine)
	t.ok(can.fire_cannon(null), "★63-14 ② 核心放得出大炮")
	t.gt(can.cannon_cd_left, 0.0, "★63-14 ② 放完进冷却")
	t.ok(can.rifle_reloading, "★63-14 ② 放完步枪过热换弹")
	can.cannon_cd_left = 0.0
	can.rifle_reloading = false
	can.reload_timer = 0.0
	can.rifle_mag = core.rifle_magazine - 1
	t.not_ok(can.cannon_ready(), "★63-14 ② 弹夹不满 ⇒ 又放不出（硬门槛仍是「全满」）")

	me.abort_saber()
	FlightBody.use_placeholder = prev_placeholder
	c.free()
	c2.free()
	await host.get_tree().physics_frame
