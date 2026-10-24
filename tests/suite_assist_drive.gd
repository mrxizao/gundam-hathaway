extends RefCounted
## 批 8（2026-09-22）：辅助驾驶平移模式 + 三机速度收敛 + 拖尾光条。
##
## 三块用户需求，各一组断言：
##   1. "辅助驾驶模式开启之后，wasd 键就变为前后左右，qe 就是上升和下降，
##      shift 就变为朝着输入方向冲刺，但是阿利宙斯变形之后的辅助模式依然保持现状，
##      不过他的 shift 就变成超级加速" → **形态分界** + **超级加速**的飞行模型行为；
##   2. "把三台机体的速度都加速一遍，再都调为近似值" → 三机五形态全部比旧值快、
##      且收敛在一个窄带里（次序保留）；
##   3. "冲刺的时候背后尾迹变成连贯拖尾的光条。超级加速模式也是" → BoostTrail
##      喂点生长 / 松开收干净。
##
## ⚠️ 平移的"每帧输入读取"（_read_translate_input）读 Input.get_axis / 手柄轴，
## 无头环境里恒为 0 —— 它的正确性靠 FlightBody._apply_translate 的纯数值行为
## 与形态分界函数兜住；真手柄手感归试玩。
##
## 二调（2026-09-22 晚）：辅助驾驶改为**自动加速飞行**（无输入不停机），Shift 改
## **装甲核心式点按闪避**（QB_TIME/QB_SPEED_MULT/QB_JET_COST）—— 见 _auto_flight。

static func run(t: T, host: Node) -> void:
	_assist_gate(t)
	# ⚠️ 必须显式 await：_wiring 里有 await（真跑物理帧），不 await 的话协程
	# 在第一个 await 处挂起、run 直接继续 —— 断言一条都不会执行。
	await _wiring(t, host)
	await _auto_flight(t, host)
	await _dash_limit(t, host)
	_speed_band(t)
	_super_boost(t)
	_boost_trail(t, host)
	# ⚠️ 挂最末：`t.suite()` 开新节时会结算**上一节**，插中间会打乱既有小节归属。
	await _dash_spin(t, host)
	# 轮 34 同样挂最末（理由同上）。
	await _dash_stow(t, host)
	# 轮 37 同样挂最末（理由同上）。
	await _pedal_assist(t, host)
	# ★ 2026-09-29 用户要求「除了柯西以外的其他机体都不做翻滚转身」，
	#   同日追加「阿利宙斯可以做左右冲刺转身」—— 同样挂最末。
	await _dash_spin_policy(t, host)
	# ★ 2026-09-29（同日稍后）用户要求「辅助驾驶模式下按 w 的加速速率下调到 15% 左右」，
	#   同样挂最末。
	await _fwd_offset(t, host)


## ②b 自动飞行 + 闪避冲刺（2026-09-22 二调，用户反馈驱动）：
##   "辅助驾驶模式下依然保持加速飞行啊，自动飞行" → 无输入也永远以加力极速自动飞；
##   "shift 键就变成类似装甲核心闪避/冲刺一样的功能" → 点按触发、窗口直冲、回落。
## 真跑物理帧（_apply_translate 的行为，纯函数测不出来）。
static func _auto_flight(t: T, host: Node) -> void:
	t.suite("AssistDrive / 自动飞行 + 闪避冲刺（_apply_translate）")
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.name = "AutoFlyProbe"
	pc.profile = SuitProfile.xi()
	pc.is_player = true
	pc.team = 0
	pc.controls_enabled = true
	c.add_child(pc)
	pc.assist_on = true
	pc.global_position = Vector3(0, 900, 0)
	# ---- 自动飞行：无输入，机体也必须以加力极速在飞（不是停下来悬停）----
	for i in 240:
		await host.get_tree().physics_frame
	t.ok(pc.translate_mode, "辅助开 → 平移模式（接线仍在）")
	var ab := pc.profile.player_boost_speed()
	t.near(pc.fm.speed, ab, ab * 0.08,
		"无输入 %.0f m/s ≈ 加力极速 %.0f —— 自动加速飞行，不是悬停" % [pc.fm.speed, ab])
	# ---- 闪避冲刺：点按请求 → 窗口内冲上 加力极速 × QB_SPEED_MULT ----
	pc.request_quick_boost()
	await host.get_tree().physics_frame
	t.ok(pc.translate_dash, "点按请求 → 闪避窗口开启")
	for i in 15:
		await host.get_tree().physics_frame
	var qb_want := ab * FlightBody.QB_SPEED_MULT
	t.gt(pc.fm.speed, ab * 1.15,
		"闪避中 %.0f 明显快过底速 %.0f（目标 %.0f）—— QB 档位真的存在"
			% [pc.fm.speed, ab, qb_want])
	# ---- 窗口结束：窗口关闭、回落自动飞行底速（不是停、也不是永冲）----
	for i in 100:
		await host.get_tree().physics_frame
	t.not_ok(pc.translate_dash, "窗口结束 → 闪避关闭")
	t.near(pc.fm.speed, ab, ab * 0.12,
		"回落到底速（%.0f ≈ %.0f）—— 闪避是一下，不是新常态" % [pc.fm.speed, ab])
	# ---- 机头朝向锁定敌机（二调：AC 标准模式）----
	# 假敌机摆在需要同时偏航 + 俯仰才能对准的位置；给足收敛时间后
	# 机头方向必须指向它。无目标时回落"机头跟速度"的老行为（上面已隐式验证）。
	var foe := PlayerController.new()
	foe.name = "FaceFoe"
	foe.profile = SuitProfile.xi()
	c.add_child(foe)
	foe.global_position = Vector3(900, 1250, -500)
	pc.face_target_override = foe
	for i in 180:
		await host.get_tree().physics_frame
	var to_foe: Vector3 = (foe.global_position - pc.global_position).normalized()
	var nose: Vector3 = -pc.global_transform.basis.z
	t.gt(nose.dot(to_foe), 0.95,
		"机头持续朝向锁定敌机（dot=%.3f）—— AC 标准模式接管机头" % nose.dot(to_foe))
	pc.face_target_override = null
	foe.free()
	pc.free()
	c.free()
	await host.get_tree().process_frame
	Game.reset()


## ②c 冲刺限制条（批 10，用户要求）：ACE 机的闪避不再是无限的。
## 静态门禁（谁装条）+ 真跑物理帧的"6 连闪 → 烧干 → CD → 回充"全流程。
static func _dash_limit(t: T, host: Node) -> void:
	# ---- 门禁：谁装条（纯函数）----
	t.suite("AssistDrive / 冲刺限制条 · 谁装")
	t.ok(SuitProfile.xi().has_dash_limit(), "柯西：装条（无燃料槽的 ACE 机）")
	t.ok(SuitProfile.penelope().has_dash_limit(), "佩涅罗佩：装条")
	t.ok(SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL).has_dash_limit(),
		"阿利宙斯常态：装条（用户澄清：只有巡航的超级加速没有燃料槽）")
	t.ok(SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU).has_dash_limit(),
		"阿利宙斯核心形态：装条")
	t.not_ok(SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE).has_dash_limit(),
		"阿利宙斯巡航形态：唯一豁免（Shift 是超级加速，无限制条）")
	t.not_ok(SuitProfile.messer_m01().has_dash_limit(), "量产机不装条（走燃料槽）")
	var n_from_full := 1.0 / FlightBody.QB_CHARGE_COST
	t.ok(n_from_full >= 5.9 and n_from_full <= 7.5,
		"满条次数 = %.1f，落在用户要的 6-7 次这一档" % n_from_full)
	# ---- 行为：满条连闪 6 次 + 第 7 次烧干 → CD → 回充 ----
	t.suite("AssistDrive / 冲刺限制条 · 消耗与冷却（真跑物理帧）")
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.name = "DashLimitProbe"
	pc.profile = SuitProfile.xi()
	pc.is_player = true
	pc.team = 0
	pc.controls_enabled = true
	c.add_child(pc)
	pc.assist_on = true
	pc.global_position = Vector3(0, 900, 0)
	for i in 60:
		await host.get_tree().physics_frame
	t.ok(pc.translate_mode, "柯西进入平移模式（前置）")
	t.ok(pc.can_quick_boost(), "满条可以闪避")
	# 连闪 6 次：每次请求后等 30 帧（窗口 27 帧 + 余量）。窗口内不回充，
	# 但窗口间的零星回充会带进浮点尾巴 —— 所以这里只断言"每次都扣了条"，
	# "烧干"的判定放在下面精确置数的那一发。
	for i in 6:
		var before_dash := pc.dash_charge
		pc.request_quick_boost()
		for f in 30:
			await host.get_tree().physics_frame
		t.lt(pc.dash_charge, before_dash,
			"第 %d 次闪避扣条（%.3f → %.3f）" % [i + 1, before_dash, pc.dash_charge])
		t.gt(pc.dash_charge, 0.0, "第 %d 次后没烧干（不进 CD）" % (i + 1))
	# 最后一发：把条精确置为"恰好一次的量"→ 这次闪避把它烧到 0 → 强制 CD。
	# （浮点上 x - x 恒等于 0，判定 0.0001 的阈值必然命中。）
	pc.dash_charge = FlightBody.QB_CHARGE_COST
	pc.request_quick_boost()
	for f in 30:
		await host.get_tree().physics_frame
	t.near(pc.dash_charge, 0.0, 0.001, "烧干：条归零")
	t.gt(pc.dash_cd, 0.0, "烧干 → 进入长冷却（%.1f 秒）" % FlightBody.QB_CHARGE_CD)
	t.not_ok(pc.can_quick_boost(), "CD 中不能闪避")
	# CD 中的请求必须被拒：记下窗口状态，再等 10 帧确认没有窗口开启
	for f in 10:
		await host.get_tree().physics_frame
	t.not_ok(pc.translate_dash, "CD 中点按不会开启闪避窗口")
	# 缩短 CD 验证"CD 结束 → 从 0 回充"
	pc.dash_cd = 0.2
	for f in 30:
		await host.get_tree().physics_frame
	t.near(pc.dash_cd, 0.0, 0.001, "CD 结束")
	t.gt(pc.dash_charge, 0.0, "CD 结束后从 0 开始回充（%.2f）" % pc.dash_charge)
	var before := pc.dash_charge
	for f in 30:
		await host.get_tree().physics_frame
	t.gt(pc.dash_charge, before, "持续回充（%.2f → %.2f）" % [before, pc.dash_charge])
	pc.free()
	c.free()
	await host.get_tree().process_frame
	Game.reset()


## ① 形态分界：谁走平移、谁保持现状。
static func _assist_gate(t: T) -> void:
	t.suite("AssistDrive / 平移模式的形态分界（静态纯函数）")
	t.ok(PlayerController.assist_uses_translation(SuitProfile.xi()),
		"柯西：辅助走平移（WASD/QE/冲刺）")
	t.ok(PlayerController.assist_uses_translation(SuitProfile.penelope()),
		"佩涅罗佩：辅助走平移")
	t.ok(PlayerController.assist_uses_translation(
		SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL)),
		"阿利宙斯常态：辅助走平移")
	t.ok(PlayerController.assist_uses_translation(
		SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU)),
		"阿利宙斯核心形态：辅助走平移")
	t.ok(PlayerController.assist_uses_translation(null),
		"没有机体表：默认平移（不炸、有兜底）")
	t.not_ok(PlayerController.assist_uses_translation(
		SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE)),
		"阿利宙斯巡航形态（变形之后）：辅助保持现状 —— Shift 是超级加速，不是冲刺")


## ② 接线守卫：真 `_think()` 一帧，`translate_mode` 必须真的翻到 FlightBody 上。
##
## ⚠️ 批 8 首版把开关写漏了 —— 纯函数/字段测试全绿，游戏里 WASD/Shift 却全没反应。
## 这组断言守的就是"输入读取 ↔ FlightBody 分支"这根线：辅助开 + 非巡航形态
## → `translate_mode == true`；辅助关或巡航形态 → 必须是 false（AI 不受影响）。
static func _wiring(t: T, host: Node) -> void:
	t.suite("AssistDrive / 平移开关接线（_think → FlightBody）")
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var cases := [
		[SuitProfile.xi(), true, true],
		[SuitProfile.penelope(), true, true],
		[SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE), true, false],
		[SuitProfile.xi(), false, false],
	]
	var idx := 0
	for case: Array in cases:
		idx += 1
		var pc := PlayerController.new()
		pc.name = "WiringProbe"
		pc.profile = case[0]
		pc.is_player = true
		pc.team = 0
		pc.controls_enabled = true
		c.add_child(pc)
		pc.assist_on = case[1]
		await host.get_tree().physics_frame
		await host.get_tree().physics_frame
		t.eq(pc.translate_mode, case[2],
			"第 %d 例：辅助=%s → translate_mode 必须=%s（开关真的接到机体上）"
				% [idx, case[1], case[2]])
		pc.free()
	c.free()
	await host.get_tree().process_frame
	Game.reset()


## ③ 三机速度：都加速一遍 + 收敛为近似值（次序保留）。
static func _speed_band(t: T) -> void:
	t.suite("AssistDrive / 三机速度：加速一遍 + 近似值")
	var xi := SuitProfile.xi()
	var pen := SuitProfile.penelope()
	var cruise := SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE)
	var normal := SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL)
	var core := SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU)
	# ---- "加速一遍"：每个形态都比自己 2026-09-22 之前的旧巡航上限快 ----
	# 旧值：柯西 420 / 佩涅罗佩 567 / 巡航 635 / 常态 454 / 核心 319（m/s）
	#
	# ⚠️ 2026-09-25 修正比法：实际速度整体乘了 `SPEED_REAL_MULT`（**现为 2.4**），
	# 而**屏上那个数字没变**。所以"比旧值快"这条必须拿**显示域**的数来比
	#（`speed_to_display()`）—— 否则它比的是"被乘过的数"，这条断言就变成
	# 一句永远为真的空话（旧值 420 乘以倍率之后当然大于 420）。
	t.gt(SuitProfile.speed_to_display(xi.player_top_speed()), 420.0,
		"柯西巡航 %.0f > 旧值 420" % SuitProfile.speed_to_display(xi.player_top_speed()))
	t.gt(SuitProfile.speed_to_display(pen.player_top_speed()), 567.0,
		"佩涅罗佩巡航 %.0f > 旧值 567" % SuitProfile.speed_to_display(pen.player_top_speed()))
	t.gt(SuitProfile.speed_to_display(cruise.player_top_speed()), 635.0,
		"巡航形态 %.0f > 旧值 635" % SuitProfile.speed_to_display(cruise.player_top_speed()))
	t.gt(SuitProfile.speed_to_display(normal.player_top_speed()), 454.0,
		"常态 %.0f > 旧值 454" % SuitProfile.speed_to_display(normal.player_top_speed()))
	t.gt(SuitProfile.speed_to_display(core.player_top_speed()), 319.0,
		"核心形态 %.0f > 旧值 319" % SuitProfile.speed_to_display(core.player_top_speed()))
	# ---- 实际 / 显示分离（2026-09-25）：实际 = 显示 × 1.5，且**反算得回原值** ----
	t.near(xi.player_top_speed(), 420.0 * xi.speed_scale * SuitProfile.SPEED_REAL_MULT, 0.01,
		"柯西实际巡航 = 显示域基准 × 系数 × SPEED_REAL_MULT（%.1f）"
			% SuitProfile.SPEED_REAL_MULT)
	t.near(SuitProfile.speed_to_display(xi.player_top_speed()), 420.0 * xi.speed_scale, 0.01,
		"屏上那个数（除回去）就是旧口径 —— 玩家看到的数字没变")
	# ---- 2026-09-25 **第二次**提速：在 ×1.5 之上再 ×1.6 ⇒ 累计 ×2.4 ----
	#
	# 老板原话："所有机体速度再增加 60%，但是前端数据根据提升的量同步下调和现在保持
	# 差不多的数值。" 口径经确认为**累加**（"再"叠在 ×1.5 之上）。
	# 三条一起才算把这件事钉住：倍率是多少 / 增量是不是 +60% / 方向是往上。
	t.near(SuitProfile.SPEED_REAL_MULT, 2.4, 0.0001,
		"实际倍率 = 1.5 × 1.6 = 2.4")
	t.near(SuitProfile.SPEED_REAL_MULT / SuitProfile.SPEED_REAL_MULT_PREV, 1.6, 0.0001,
		"**这一次**的增量正好是 +60%%（%.2f ÷ %.2f）"
			% [SuitProfile.SPEED_REAL_MULT, SuitProfile.SPEED_REAL_MULT_PREV])
	t.gt(SuitProfile.SPEED_REAL_MULT, SuitProfile.SPEED_REAL_MULT_PREV,
		"方向是**上调**（不是有人把它悄悄改回来）")
	# ---- 提速不能只提机体：**成比例的东西必须同步** ----
	#
	# 弹速 / 冲刺 / 出膛段 / 出生初速全部写成"显示域基准 × 倍率"，
	# 所以它们必须**逐条**跟着走。漏一条就会出现"飞机飞过自己打出去的弹"
	# 或者"突进比巡航还慢"这类**看着就不对**的事 —— 这类疏漏不会报错，
	# 只会静默地难看，所以每一条都要单独钉住。
	t.near(SuitProfile.vulcan_speed(), 1400.0 * SuitProfile.SPEED_REAL_MULT, 0.01,
		"火神炮弹速跟着倍率（%.0f m/s）" % SuitProfile.vulcan_speed())
	t.near(SuitProfile.RIFLE_LAUNCH_SPEED, 1200.0 * SuitProfile.SPEED_REAL_MULT, 0.01,
		"步枪出膛段跟着倍率（%.0f m/s）" % SuitProfile.RIFLE_LAUNCH_SPEED)
	t.near(SuitProfile.xi().saber_dash_speed, 1150.0 * SuitProfile.SPEED_REAL_MULT, 0.01,
		"军刀突进跟着倍率（%.0f m/s）" % SuitProfile.xi().saber_dash_speed)
	t.near(SuitProfile.new().grenade_speed, 260.0 * SuitProfile.SPEED_REAL_MULT, 0.01,
		"榴弹出膛跟着倍率（%.0f m/s）" % SuitProfile.new().grenade_speed)
	# 出生初速的判据写成**显示域**的数（173.25）而不是"倍率 × 某个数"：
	# 要守的性质正是"屏上读到的出生速度不随倍率变"，写成显示域就一眼看得出。
	t.near(SuitProfile.speed_to_display(SuitProfile.spawn_speed()), 173.25, 0.05,
		"出生初速（显示域 %.1f；实际 %.0f m/s）与倍率无关"
			% [SuitProfile.speed_to_display(SuitProfile.spawn_speed()),
				SuitProfile.spawn_speed()])
	# 而且它们与机体的**比例**是对的：突进快过加力、**出膛段快过全部形态的加力极速**。
	#（"突进比巡航还慢"、"机体飞过自己的光束"正是这一整条规矩存在的理由。）
	t.gt(SuitProfile.xi().saber_dash_speed, SuitProfile.xi().player_boost_speed(),
		"军刀突进 %.0f > 加力 %.0f（否则「高速突进」比巡航还慢）"
			% [SuitProfile.xi().saber_dash_speed, SuitProfile.xi().player_boost_speed()])
	# ⚠️⚠️ 轮 13 **反向重写**这条断言。
	#
	# 旧版是 `RIFLE_LAUNCH_SPEED / xi.player_top_speed() ≈ 0.95`，文案写着
	# "出膛段 ≈ 柯西巡航 —— 这就是「光弹刚从炮口推出来」"。那正是用户报的硬伤本身：
	# 出膛段（1440）只有最快机体加力极速（2414）的 **60%** ⇒
	# **机体飞得比自己的光束还快**，屏幕上看到的是光束往后飘。
	#
	# 现在要守的是不等式，而且必须拿**最快的那台**去比：
	# 最快的是阿利宙斯**巡航**形态（佩涅罗佩系数 ×1.03），拿柯西比会正好漏掉快 6% 的
	# 那一档 —— 那正是"断言看起来在守、其实守不住"的典型。
	var fastest_boost: float = maxf(pen.player_boost_speed(),
		maxf(xi.player_boost_speed(), cruise.player_boost_speed()))
	t.gt(SuitProfile.RIFLE_LAUNCH_SPEED, fastest_boost,
		"步枪出膛段 %.0f > 最快机体的加力极速 %.0f（否则「机体飞的比初始弹速还快」）"
			% [SuitProfile.RIFLE_LAUNCH_SPEED, fastest_boost])
	# ---- "近似值"：五份速度系数落在一条窄带里（极差 ≤ 15%）----
	var scales: Array[float] = [xi.speed_scale, pen.speed_scale, cruise.speed_scale,
		normal.speed_scale, core.speed_scale]
	var lo: float = scales.min()
	var hi: float = scales.max()
	t.between(lo, 1.40, 1.65, "最慢的系数 %.3f 也在 1.40 以上（整体上调）" % lo)
	t.lt(hi / lo, 1.15, "系数极差 %.3f ≤ 15%%（近似值，块头差异只剩一档）" % (hi / lo))
	# ---- 次序保留：近似 ≠ 打平，`suite_abilities` 也在盯这三条 ----
	t.gt(cruise.player_top_speed(), pen.player_top_speed(), "巡航形态仍是最快")
	t.gt(pen.player_top_speed(), xi.player_top_speed(), "佩涅罗佩仍快过柯西")
	t.lt(core.player_top_speed(), xi.player_top_speed(), "核心形态仍是最慢")
	# 导弹与光束的次序不能被机体提速追平（`MISSILE_SPEED_MULT` 从佩涅罗佩推导，
	# 会自动跟着走 —— 这条是保险，不是主门）
	t.gt(SuitProfile.missile_speed(), cruise.player_boost_speed(),
		"导弹仍比最快机体的极速快")


## ④ 超级加速：FlightModel 的新档位（纯数值，无头可测）。
static func _super_boost(t: T) -> void:
	t.suite("AssistDrive / 超级加速（FlightModel 档位）")
	var fm := FlightModel.new()
	var top := 600.0
	var boost := 900.0
	fm.configure(top, boost)
	fm.throttle = 1.0
	fm.boosting = true
	for i in 600:
		fm.advance(1.0 / 60.0, Basis.IDENTITY, Vector3.ZERO)
	t.near(fm.speed, boost, 5.0, "普通加力收敛到加力上限 900")
	fm.super_boost = true
	for i in 900:
		fm.advance(1.0 / 60.0, Basis.IDENTITY, Vector3.ZERO)
	var want := boost * FlightModel.SUPER_BOOST_MULT
	t.gt(fm.speed, boost + 5.0,
		"超级加速冲过了普通加力上限（%.0f > 900）—— 档位真的存在" % fm.speed)
	t.near(fm.speed, want, want * 0.03,
		"收敛到 加力上限 ×%.2f = %.0f（天花板已跟着抬，不再被 ×1.25 截住）"
			% [FlightModel.SUPER_BOOST_MULT, want])
	t.near(fm.max_reachable_speed(), want, 0.01, "max_reachable_speed 报超级档（引擎音量/HUD 用它）")
	fm.super_boost = false
	t.near(fm.max_reachable_speed(), boost, 0.01, "关掉超级 → 立刻回落普通加力档")


## ⑤ 拖尾光条：喂点生长 / 松开收干净。
static func _boost_trail(t: T, host: Node) -> void:
	t.suite("AssistDrive / 拖尾光条（BoostTrail）")
	var trail := BoostTrail.new()
	host.add_child(trail)
	# 冲刺 30 帧、每帧 10 m：远超采样间距 8 m → 应推入多个点
	var p := Vector3.ZERO
	for i in 30:
		p += Vector3(10, 0, 0)
		trail.push(p, true, 1.0 / 60.0)
	t.gt(trail.point_count(), 5,
		"连续冲刺喂点 → 光条生长（%d 个采样点）" % trail.point_count())
	# 松开冲刺：逐帧收回，LIFE=0.55 s（33 帧）内必清空
	for i in 120:
		trail.push(p, false, 1.0 / 60.0)
	t.eq(trail.point_count(), 0, "松开冲刺 → 光条收干净（不留残点、不漏帧）")
	# 顶点真的在长（ImmediateMesh 建出来了，不是空壳）
	for i in 20:
		p += Vector3(10, 0, 0)
		trail.push(p, true, 1.0 / 60.0)
	t.gt(trail.mesh.get_surface_count() if trail.mesh != null else 0, 0,
		"冲刺中 ImmediateMesh 有面（连贯光条，不是一串点）")
	trail.queue_free()


## 轮 33（用户要求，含一次口径修正）：
##   「左右冲刺的时候朝冲刺方向机体水平旋转 360°（前后冲刺的时候不用）」
##   「第一人称的视角不受影响」
##   → 「**不是机体翻跟头，而是转身**」
##
## 五条口径，缺一条就说明实现跑偏：
##   ① 左右冲刺**真的在转身**（走满一圈、左右反向、窗口结束精确回正）；
##   ② 转的是**竖直轴**（机身水平扫，不是桶滚）—— 用"转身层的上轴必须与机体上轴
##      重合"来钉：绕 Z 的桶滚会把上轴甩到侧面，这条立刻红；
##   ③ 前后 / 升降冲刺**一点都不转**（用户："前后冲刺的时候不用"）；
##   ④ 转身**只在视觉层**：枪口锚点一个字节不受影响，相机源码里也找不到转身层 ——
##      这两条合起来就是"第一人称（以及追尾）视角不受影响"的落点；
##   ⑤ 座舱视角（模型不可见）不转，且中途关辅助不留残留角度。
##
## ⚠️ 真跑物理帧：`_apply_translate` 的行为纯函数测不出来。
static func _dash_spin(t: T, host: Node) -> void:
	t.suite("AssistDrive / 左右冲刺的机身转身（轮 33）")
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.name = "SpinProbe"
	pc.profile = SuitProfile.xi()
	pc.is_player = true
	pc.team = 0
	pc.controls_enabled = true
	c.add_child(pc)
	pc.assist_on = true
	pc.global_position = Vector3(0, 900, 0)
	for i in 240:
		await host.get_tree().physics_frame
	t.ok(pc.translate_mode, "辅助开 → 平移模式（接线仍在）")
	# ---- 转身层的挂法：必须在 `model_pivot` **之上** ----
	# 挂下面 / 挂在 model_root 上的后果见 `dash_spin` 的说明（轴会带前倾、轴心会跑到脚底）。
	t.ok(pc.spin_pivot != null and is_instance_valid(pc.spin_pivot), "转身层存在")
	t.ok(pc.spin_pivot.get_parent() == pc, "spin_pivot 直接挂在机体下（在 model_pivot 之上）")
	t.ok(pc.model_pivot.get_parent() == pc.spin_pivot, "model_pivot 改挂到 spin_pivot 下")
	t.ok(pc.model_root.get_parent() == pc.model_pivot, "model_root 仍挂在 model_pivot 下")
	t.near(pc.dash_spin, 0.0, 1.0e-9, "未冲刺时转身角为 0")

	# ---- ① 向左冲刺 → 向左转身一圈 ----
	Input.action_press("roll_left")
	for i in 6:
		await host.get_tree().physics_frame
	pc.request_quick_boost()
	var peak := 0.0
	var minv := 0.0
	var drift := 0.0
	var axis_off := 0.0
	for i in 44:
		await host.get_tree().physics_frame
		peak = maxf(peak, pc.dash_spin)
		minv = minf(minv, pc.dash_spin)
		# ⚠️ **同一帧内**比"带转身"与"把转身层归零"两次读数：机体姿态在这一帧里
		# 不会变，所以只要锚点公式里出现了 `spin_pivot`，这个差值立刻不为 0。
		var a_spin: Vector3 = pc.rig_anchor("muzzle_L")
		var keep: Vector3 = pc.spin_pivot.rotation
		pc.spin_pivot.rotation = Vector3.ZERO
		drift = maxf(drift, pc.rig_anchor("muzzle_L").distance_to(a_spin))
		pc.spin_pivot.rotation = keep
		# ② 转的是竖直轴：转身层的上轴必须**始终与机体上轴重合**。
		# 绕 Z 的桶滚会把上轴甩到侧面，这一项会直接跳到 1 附近。
		axis_off = maxf(axis_off,
			1.0 - pc.spin_pivot.global_transform.basis.y.dot(pc.global_transform.basis.y))
	t.gt(peak, 5.5, "左冲刺 → 走满一圈（峰值 %.3f rad ≈ %.0f°）" % [peak, rad_to_deg(peak)])
	t.gt(minv, -1.0e-9, "左冲刺全程角度不为负（向左转，不甩反）")
	t.near(pc.dash_spin, 0.0, 1.0e-9, "窗口结束 → 精确回正（不停在半圈上）")
	t.near(pc.spin_pivot.rotation_degrees.y, 0.0, 0.001, "视觉层与逻辑角同步回正")
	t.lt(axis_off, 1.0e-6,
		"转身层上轴与机体上轴始终重合（偏差 %.8f）—— 转的是竖直轴，不是桶滚" % axis_off)
	# 门限 5 cm 的来历：两条路径各自要做一次 `affine_inverse()` + 两次矩阵连乘，
	# 机体坐标在 y≈900 量级 ⇒ 实测舍入 2.1 mm（1/10000 机体尺度）。
	# 判据取"差三个数量级"：若转身真被算进锚点，转 180° 时枪口会横移
	# **两倍于枪口到机体中轴的距离**（米级）—— 数米与 2 mm 分辨得开。
	t.lt(drift, 0.05,
		"转身期间枪口锚点与「把转身层归零」一致（差 %.6f m）—— 锚点不吃转身" % drift)
	Input.action_release("roll_left")
	for i in 30:
		await host.get_tree().physics_frame

	# ---- ①b 向右冲刺 → 反向转 ----
	Input.action_press("roll_right")
	for i in 6:
		await host.get_tree().physics_frame
	pc.request_quick_boost()
	var low_r := 0.0
	var high_r := 0.0
	for i in 44:
		await host.get_tree().physics_frame
		low_r = minf(low_r, pc.dash_spin)
		high_r = maxf(high_r, pc.dash_spin)
	t.lt(low_r, -5.5, "右冲刺 → 反向转一圈（谷值 %.3f rad）" % low_r)
	t.lt(high_r, 1.0e-9, "右冲刺全程角度不为正（向右转）")
	Input.action_release("roll_right")
	for i in 30:
		await host.get_tree().physics_frame

	# ---- ③ 向前冲刺：一点都不转 ----
	Input.action_press("pitch_nose_down")
	for i in 6:
		await host.get_tree().physics_frame
	pc.request_quick_boost()
	var peak_f := 0.0
	for i in 36:
		await host.get_tree().physics_frame
		peak_f = maxf(peak_f, absf(pc.dash_spin))
	t.near(peak_f, 0.0, 1.0e-9, "向前冲刺全程不转（峰值 %.9f rad）" % peak_f)
	Input.action_release("pitch_nose_down")
	for i in 20:
		await host.get_tree().physics_frame

	# ---- ③b 上升冲刺：也不转（用户："只有左右转"）----
	Input.action_press("yaw_left")
	for i in 6:
		await host.get_tree().physics_frame
	pc.request_quick_boost()
	var peak_u := 0.0
	for i in 36:
		await host.get_tree().physics_frame
		peak_u = maxf(peak_u, absf(pc.dash_spin))
	t.near(peak_u, 0.0, 1.0e-9, "上升冲刺不转（峰值 %.9f rad）" % peak_u)
	Input.action_release("yaw_left")
	for i in 20:
		await host.get_tree().physics_frame

	# ---- ④ 转身是纯视觉：把转身层拧到 180°，机体 transform 一个字节不动 ----
	var g_now: Transform3D = pc.global_transform
	pc.spin_pivot.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	t.ok(pc.global_transform.is_equal_approx(g_now),
		"把转身层拧到 180° → 机体 transform 不变（转身没进 global_transform）")
	pc.spin_pivot.rotation_degrees = Vector3.ZERO
	# 相机只吃 `global_transform` —— 源码级证据：它压根不知道有转身层这回事。
	# 这就是「第一人称的视角不受影响」在代码上的落点（座舱相机读的是同一个 basis）。
	var cam_src := FileAccess.get_file_as_string("res://scripts/flight/chase_camera.gd")
	t.not_ok(cam_src.contains("spin_pivot"),
		"相机源码不出现 spin_pivot —— 镜头不可能跟着转")
	t.ok(cam_src.contains("t.global_transform.basis"),
		"相机读的仍是机体 transform（口径没换）")

	# ---- ⑤ 座舱视角（模型不可见）不转 ----
	pc.set_model_visible(false)
	t.ok(not pc.model_visible(), "模型已隐藏（座舱视角）")
	Input.action_press("roll_left")
	for i in 6:
		await host.get_tree().physics_frame
	pc.request_quick_boost()
	var peak_c := 0.0
	for i in 36:
		await host.get_tree().physics_frame
		peak_c = maxf(peak_c, absf(pc.dash_spin))
	t.near(peak_c, 0.0, 1.0e-9, "座舱视角下左右冲刺不转（峰值 %.9f rad）" % peak_c)
	Input.action_release("roll_left")
	pc.set_model_visible(true)
	for i in 20:
		await host.get_tree().physics_frame

	# ---- ⑥ 中途关辅助：转身状态不许残留（否则下次进平移模式会"歪着转一段"）----
	Input.action_press("roll_left")
	for i in 6:
		await host.get_tree().physics_frame
	pc.request_quick_boost()
	for i in 4:
		await host.get_tree().physics_frame
	var mid_spin := absf(pc.dash_spin)
	pc.assist_on = false
	for i in 3:
		await host.get_tree().physics_frame
	t.gt(mid_spin, 0.05, "关辅助前确实在转（%.3f rad）—— 这条断言才有意义" % mid_spin)
	t.near(pc.dash_spin, 0.0, 1.0e-9, "中途关辅助 → 转身角立刻归零，不留残留")
	t.near(pc.spin_pivot.rotation_degrees.y, 0.0, 0.001, "视觉层同步归零")
	Input.action_release("roll_left")
	c.free()


## 轮 34（用户要求）：
##   「左右转身的时候快速从巡航态的模型恢复成飞行态再变成巡航态
##    （飞行翼和肩甲先从展开状态收起，到转身完之后再展开）」
##
## ## 实现只有**一个杠杆**
##
## 形态的单一进度量是 `FlightBody.cruise_morph`（1 = 巡航态 / 翼展开，
## 0 = 飞行态 / 收起）。它同时驱动三条通路 ——
##   ① blend shape（老资产）、
##   ② 骨骼形态层（`FormCurveModifier` / `CruiseFormModifier`）、
##   ③ `model_fsm.set_form(cruise_morph >= 0.5)` 决定的**待机动作**
##      （柯西 = `cruise_idle` ↔ `fly`，中间还有 `form_on` 过渡）。
## ⇒ 在转身窗口里把这**一个**量压到 0，就三条通路一起收 —— 一行都不用碰形态层、
##   也不用碰 FSM。这是为什么这套断言只盯着 `cruise_morph` 一个读数。
##
## ## 五条口径
##   ① 平移模式下巡航态是**常驻**的（`PlayerController._read_translate_input()`
##      末尾把 `fm.boosting` 写死 true）⇒ 转身前必定是巡航态，与用户描述一致；
##   ② 窗口内**快速**收到 0（0.15 s ≈ 5 帧，而默认速率要 14 帧才跌破一半）；
##   ③ 窗口走完**自动回到巡航态**（「到转身完之后再展开」）—— 不必写收尾代码，
##      `want` 回到常态逻辑本身就是展开；
##   ④ 前后 / 升降冲刺**一点都不收**（它们没有转身窗口）；
##   ⑤ 座舱视角（模型不可见）不收 —— 与转身本身同一条判据（模型都看不见）。
##
## ⚠️ 真跑物理帧：`_apply_translate` 逐帧推进 `_dash_spin_t`，纯函数测不出来。
static func _dash_stow(t: T, host: Node) -> void:
	t.suite("AssistDrive / 转身期间形态收起再展开（轮 34）")
	Game.reset()
	# `use_placeholder` 是 **static**：显式写死，免得被别的套件留的脏值影响。
	FlightBody.use_placeholder = false
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.name = "StowProbe"
	pc.profile = SuitProfile.xi()
	pc.is_player = true
	pc.team = 0
	pc.controls_enabled = true
	c.add_child(pc)
	pc.assist_on = true
	pc.global_position = Vector3(0, 900, 0)
	for i in 240:
		await host.get_tree().physics_frame

	# ---- 前置：形态系统在场，且处巡航态 ----
	t.ok(pc.profile.cruise_morph, "前置：柯西开着 cruise_morph")
	t.ok(pc.translate_mode, "前置：平移模式")
	t.gt(pc.cruise_morph, 0.99,
		"★ 平移模式下巡航态**常驻**（morph %.3f ≈ 1）—— 这就是用户说的“巡航态的模型”"
			% pc.cruise_morph)
	# “看得见”的前提：形态得有载体。柯西当前走**动作**那条（`cruise_idle` ↔ `fly`），
	# 但这里不钉死是哪一条 —— 判据写成“至少一条在场”，换载体时这条仍然成立。
	var armed := pc._form_curve != null or pc._cruise_form != null
	if not armed and pc.model_anim != null and pc.model_anim.ready:
		var ca: String = pc.model_anim.idle_cruise_action
		armed = ca != "" and pc.model_anim.has(ca)
	t.ok(armed,
		"★ 至少一条形态载体在场（骨骼形态层 或 巡航待机动作 cruise_idle）"
			+ " —— 否则 morph 动了屏幕也不变")

	# ---- ① 不冲刺时形态不动（防“常驻收起”这类低级错）----
	for i in 30:
		await host.get_tree().physics_frame
	t.gt(pc.cruise_morph, 0.99, "无冲刺 30 帧 → 形态不动（不误收）")

	# ---- ② 向左冲刺：窗口内快速收起 ----
	Input.action_press("roll_left")
	for i in 6:
		await host.get_tree().physics_frame
	var was_cruise := pc.cruise_morph
	pc.request_quick_boost()
	var min_morph := 1.0
	var tail_morph := 1.0
	var frames_in_window := 0
	var frames_to_half := -1
	var want_normal := false
	for i in 44:
		await host.get_tree().physics_frame
		if pc._dash_spin_t > 0.0:
			frames_in_window += 1
			min_morph = minf(min_morph, pc.cruise_morph)
			tail_morph = pc.cruise_morph
			if frames_to_half < 0 and pc.cruise_morph < 0.5:
				frames_to_half = frames_in_window
			if pc.model_fsm.want_form_name() == "normal":
				want_normal = true
	t.gt(was_cruise, 0.99,
		"冲刺前一帧是巡航态（morph %.3f）—— 这是“从巡航态收起”的前提" % was_cruise)
	t.gt(frames_in_window, 20,
		"冲刺窗口真的开着（%d 帧 ≈ %.2f s）" % [frames_in_window, frames_in_window / 60.0])
	t.lt(min_morph, 0.01,
		"★ 窗口内收到**完全收起**（谷值 %.4f ≈ 0 = 飞行态）—— 飞行翼 / 肩甲收起来了"
			% min_morph)
	t.lt(tail_morph, 0.01,
		"★ 收起后**整个窗口都保持收起**（窗口末帧 %.4f）—— 是先收好再转完，不是边转边收"
			% tail_morph)
	t.gt(frames_to_half, 0, "窗口内确实经过“正在收”的中间态（不是瞬间跳）")
	# 默认速率（`cruise_morph_seconds` 0.45 s）要 14 帧才跌破一半；收起是 5 帧。
	# 门限取 8 ⇒ 两边都留余量，且**默认速率一定红**。
	t.lt(frames_to_half, 8,
		"★ 收起**快**：%d 帧（%.2f s）跌破一半，明显快于默认的 %.2f s"
			% [frames_to_half, frames_to_half / 60.0, pc.profile.cruise_morph_seconds])
	t.ok(want_normal, "★ 状态机收到“切常态”请求（待机动作 cruise_idle → fly）")

	# ---- ③ 窗口走完 → 自动回到巡航态（“到转身完之后再展开”）----
	for i in 90:
		await host.get_tree().physics_frame
	t.gt(pc.cruise_morph, 0.99,
		"★ 窗口走完自动**再展开**回巡航态（morph %.3f）—— 不需要任何收尾代码"
			% pc.cruise_morph)
	# 一行诊断：断言只给"过/不过"，这里给出**实测值**（交付说明与回归日志要引用）。
	#
	# ⚠️ **必须先拼好再格式化**，不能写成 `"…" + "…" % [...]`。
	#    GDScript 里 `%` 的结合力**强于 `+`** ⇒ 那种写法会解析成 `A + (B % [...])`：
	#    只有 B 吃到参数，且 B 的占位符数与数组长度不匹配时 Godot 会报
	#    `not all arguments converted during string formatting` 并**原样返回**整串 ——
	#    现象是日志里印出一条带着 `%d` / `%.4f` 的**模板**，看起来"有诊断"、其实是死的。
	#    （实测复现见 `tools/gdscript_fmt_precedence.gd`；本轮就是踩了这条，第一版全量日志里那行是模板。）
	var diag := "  [轮34] 窗口 %d 帧(%.2f s) | 收起 %.4f → 谷 %.4f | 第 %d 帧(%.2f s) 跌破一半" \
		+ " | 窗口末帧 %.4f | 展开后 %.4f"
	print(diag % [frames_in_window, frames_in_window / 60.0, was_cruise, min_morph,
		frames_to_half, frames_to_half / 60.0, tail_morph, pc.cruise_morph])
	t.eq(pc.model_fsm.want_form_name(), "cruise", "状态机目标形态回到 cruise")
	Input.action_release("roll_left")
	for i in 20:
		await host.get_tree().physics_frame

	# ---- ④ 向前冲刺：一点都不收 ----
	Input.action_press("pitch_nose_down")
	for i in 6:
		await host.get_tree().physics_frame
	pc.request_quick_boost()
	var min_f := 1.0
	for i in 44:
		await host.get_tree().physics_frame
		min_f = minf(min_f, pc.cruise_morph)
	t.gt(min_f, 0.99,
		"★ 向前冲刺全程**不收**（谷值 %.4f）—— 前后冲刺没有转身窗口" % min_f)
	Input.action_release("pitch_nose_down")
	for i in 20:
		await host.get_tree().physics_frame

	# ---- ④b 上升冲刺：也不收（与转身同一条“只有左右”口径）----
	Input.action_press("yaw_left")
	for i in 6:
		await host.get_tree().physics_frame
	pc.request_quick_boost()
	var min_u := 1.0
	for i in 44:
		await host.get_tree().physics_frame
		min_u = minf(min_u, pc.cruise_morph)
	t.gt(min_u, 0.99, "上升冲刺也不收（谷值 %.4f）" % min_u)
	Input.action_release("yaw_left")
	for i in 20:
		await host.get_tree().physics_frame

	# ---- ⑤ 座舱视角（模型不可见）：不收 ----
	pc.set_model_visible(false)
	Input.action_press("roll_left")
	for i in 6:
		await host.get_tree().physics_frame
	pc.request_quick_boost()
	var min_c := 1.0
	for i in 44:
		await host.get_tree().physics_frame
		min_c = minf(min_c, pc.cruise_morph)
	t.gt(min_c, 0.99,
		"★ 座舱视角不收（谷值 %.4f）—— 模型本来就看不见，收了也白收" % min_c)
	Input.action_release("roll_left")
	pc.set_model_visible(true)
	for i in 30:
		await host.get_tree().physics_frame
	c.free()


## 轮 37（用户要求）：
##   「**飞行踏板在辅助驾驶模式下操控方式和阿利宙斯巡航态一样**」
##
## ## 为什么骑板要归到「保持飞行操纵」那一档
##
## 踏板的两条特性都长在**气动**上 —— `RIDE_THROTTLE_RESPONSE`（加速 / 减速响应
## ×1.45）与 `RIDE_TURN_MUL`（转向 ×0.8）是 `apply_pedal_flight_bonus()` 乘在
## `fm.accel / fm.pitch_rate` 上的；而平移模式**不走气动**（`FlightBody._apply_translate()`
## 直接改 `fm.velocity`）⇒ 站在板上却按平移开，踏板等于不存在。
## 设定上它与阿利宙斯巡航形态本来就是同一类（高速直冲、转弯吃亏），
## 所以归到同一档。完整理由见 `PlayerController.assist_uses_translation` 的注释。
##
## ## 两组断言，缺一组就不算验完
##   ① **纯函数门禁**：骑板 → 不走平移；而且判据是「**此刻在不在板上**」，
##      不是「这台机骑不骑得了板」—— 同一台梅萨在两个状态下必须给出**相反**的答案。
##   ② **真机接线**：编队战里玩家开局就是骑着板的领机，这一节直接在真 `main.tscn`
##      上开一局，断言 `translate_mode` 跟着**装板 / 脱板 / 再装板**翻转。
##      ⚠️ 只测①会漏掉「忘了把 `has_pedal()` 传进去」这一类接线疏漏 ——
##      批 8 首版正是「纯函数全绿、游戏里按键全没反应」。
##
## ⚠️ 真跑物理帧：`translate_mode` 由 `_think()` 每帧重写，纯函数测不出来。
static func _pedal_assist(t: T, host: Node) -> void:
	t.suite("AssistDrive / 骑飞行踏板时的操纵分界（轮 37）")

	# ---- ① 纯函数门禁 ----
	t.not_ok(PlayerController.assist_uses_translation(SuitProfile.messer_m01(), true),
		"梅萨骑板 → 不走平移（保持飞行操纵）")
	t.not_ok(PlayerController.assist_uses_translation(SuitProfile.gustav00(), true),
		"古斯塔夫骑板 → 不走平移")
	t.ok(PlayerController.assist_uses_translation(SuitProfile.messer_m01()),
		"**同一台梅萨、不在板上** → 仍然走平移（判据是「此刻在不在板上」，不是型号）")
	t.ok(PlayerController.assist_uses_translation(null, false),
		"没有机体表 → 默认平移（兜底没被这条改动弄坏）")
	t.not_ok(PlayerController.assist_uses_translation(
		SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE), true),
		"巡航形态 + 骑板 → 仍不走平移（两条例外不打架）")

	# ---- ② 真机接线：编队战里的玩家就是骑着板的领机 ----
	Game.reset()
	Game.active_suit = SuitProfile.Id.MESSER_M01
	Game.active_side = BattleFormation.Side.MAFTY
	var m := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(m)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	m.call("_on_start_match", SuitProfile.Id.MESSER_M01, Difficulty.Level.NORMAL,
		MapDef.Id.PACIFIC, Game.MatchMode.SQUAD, -1)
	for i in 16:
		await host.get_tree().physics_frame
	var rider: PlayerController = m.get("player") as PlayerController
	if rider == null:
		t.ok(false, "**没拿到玩家机** —— 本节前提不成立")
		m.queue_free()
		return
	t.ok(rider.controls_enabled, "前置：玩家已可控（INTRO 已过）")
	t.ok(rider.has_pedal(), "前置：编队战里玩家是领机 ⇒ **开局就骑着板**")

	rider.assist_on = true
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	t.ok(rider.assist_on, "前置：辅助确实开着（免得「没开所以没进平移」蒙对）")
	t.not_ok(rider.translate_mode, "★ 辅助开 + 骑板 → **不走平移**（走巡航态那套操纵）")

	# 脱板（T 键 / 手柄 B 那条路的核心就是 `release_pedal()`）
	rider.release_pedal()
	for i in 4:
		await host.get_tree().physics_frame
	t.not_ok(rider.has_pedal(), "已脱板（板自由滑飞 5 s 后消失）")
	t.ok(rider.translate_mode, "★ 脱板 → **回到平移**（分界跟着真状态走）")

	# 再装回去：`spawn_with_pedal()` 正是 `main._spawn_side()` 给领机配板的那条路
	var again := rider.spawn_with_pedal()
	t.ok(again != null and rider.has_pedal(), "重新装板（走生产路径 spawn_with_pedal）")
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	t.not_ok(rider.translate_mode, "★ 再骑上 → 又回到飞行操纵（可反复，不是一次性）")

	m.queue_free()
	await host.get_tree().physics_frame
	Game.reset()


## ★ 2026-09-29（用户要求）：「除了柯西以外的其他机体都不做翻滚转身」
##    ＋ **同日追加**：「阿利宙斯可以做左右冲刺转身」。
##
## 配置层的单一真源 = `SuitProfile.dash_spin_visual`（**默认 `false`**；
## 显式打开的只有 `SuitProfile.xi()` 与 `SuitProfile.arizeus()` **两处**），
## 消费点**唯一** = `FlightBody._start_dash_spin()` 的早退。
##
## ## 为什么断言必须**全枚举**，不能列几台
## 用户要的是「**全部**非白名单机体」。逐台列举的话，**以后新增一台机体**（或在
## `by_id_form()` 里多一个形态）会**静默地**继承到转身 —— 这条需求刚落地就会被
## 后来的代码悄悄破掉，而且没人会想起来补断言（同 N49 的 T13：登记了但没人消费）。
## ⇒ 遍历 `by_id_form()` 能到达的**每一个 profile**，只允许白名单里的那两台开着。
##
## ## 为什么光有配置断言不够
## 配置对 ≠ 行为对（字段写对了但消费点读错字段，效果一样是 0）。
## ⇒ **两个方向各真跑一台代表机体**：
##    · **不该转**的（梅萨M01）⇒ `dash_spin` 峰值**精确为 0**；
##    · **该转**的（阿利宙斯常态）⇒ 峰值 > 5.5 rad（≈315°）＋ 被消费层同步。
##    ★ 两条都**可证伪**：① 把 `dash_spin_visual` 的默认值改回 `true` ⇒ 上面那条红；
##      ② 删掉 `arizeus()` 里那行 ⇒ 下面那条红（A/B 记录见
##      `_relay/REPORT-N53-dash-spin-fleet.md` 与 `2026-09-29.md`）。
##    ★ 每条前面都有一行 `translate_mode` **保险**：没进平移模式时「不转」是**恒真**的。
static func _dash_spin_policy(t: T, host: Node) -> void:
	t.suite("AssistDrive / 柯西与阿利宙斯做左右冲刺转身（2026-09-29）")
	# `use_placeholder` 是 **static**：显式写死，免得被别的套件留的脏值影响。
	FlightBody.use_placeholder = false

	# ---- ① 配置层：全枚举（判据按**机体**归组，形态只作附加检查）----
	# ⚠️ 用户说的是"**哪几台机体**能转" ⇒ 断言的主语必须是机体，不是形态。
	var ids := [SuitProfile.Id.XI, SuitProfile.Id.PENELOPE, SuitProfile.Id.ARIZEUS,
		SuitProfile.Id.GUSTAV00, SuitProfile.Id.MESSER_M01]
	var turned_ids: Array = []
	var turned: Array = []
	var arizeus_forms := 0
	var arizeus_on := 0
	var n := 0
	for id in ids:
		var any_on := false
		for form in SuitProfile.forms_of(id):
			var p := SuitProfile.by_id_form(id, form)
			n += 1
			if id == SuitProfile.Id.ARIZEUS:
				arizeus_forms += 1
				if p.dash_spin_visual:
					arizeus_on += 1
			if p.dash_spin_visual:
				any_on = true
				turned.append("%s(form %d)" % [p.display_name, form])
		if any_on:
			turned_ids.append(id)
	t.eq(n, 8, "枚举到 8 个机体形态（实测 %d）—— 漏掉形态 = 这条断言白写" % n)
	# ⚠️ 必须有「**恰好几台**」这一半：只查"其余都是 false"的话，**全关**（柯西也关）
	#    同样通过，而用户要的是"柯西 ＋ 阿利宙斯保留"。
	t.eq(turned_ids.size(), 3, "全工程恰好 3 台机体开着转身（实测 %d：%s）" % [turned_ids.size(), str(turned_ids)])
	t.ok(turned_ids.has(SuitProfile.Id.XI), "白名单里有柯西")
	t.ok(turned_ids.has(SuitProfile.Id.ARIZEUS), "白名单里有阿利宙斯（2026-09-29 追加）")
	# ⚠️ 阿利宙斯**三个形态全部**开着（含巡航），这是**故意**的：巡航形态在
	#    `PlayerController.assist_uses_translation()` 里恒 `false` ⇒ 结构上进不了
	#    平移模式 ⇒ 配置空转。约束的**真源留在那一处**，⛔ 不在这里重复写第二遍
	#    （重复 = 以后放行巡航形态时静默不转）。
	t.eq(arizeus_forms, 3, "阿利宙斯有 3 个形态（实测 %d）" % arizeus_forms)
	t.eq(arizeus_on, arizeus_forms,
		"阿利宙斯三个形态**全部**开着（%d/%d）—— `arizeus()` 有意不按形态分支" % [arizeus_on, arizeus_forms])
	# 靶机版古斯塔夫是 `by_id()` **不给**的那一副面孔（`by_id` 给武装版）⇒ 单独钉一下。
	t.ok(not SuitProfile.gustav00().dash_spin_visual, "古斯塔夫（训练靶机版）不转")
	t.ok(not SuitProfile.gustav00_armed().dash_spin_visual, "古斯塔夫（武装版）不转")
	# 佩涅罗佩那行显式 `= false` 只是"可 grep 的记录"、与默认值相同 ⇒ 顺带钉住它没被翻成 true。
	t.ok(SuitProfile.penelope().dash_spin_visual, "新版佩涅罗佩左右冲刺转身")

	# ---- ② 行为层：两个方向各跑一台 ----
	# ②a **不该转**的：梅萨M01（非白名单代表）。
	var m := await _dash_spin_burst(host, SuitProfile.messer_m01())
	t.ok(bool(m["translate"]), "前置：梅萨进了平移模式（没进的话下面那条「不转」是恒真的）")
	t.near(float(m["peak"]), 0.0, 1.0e-9, "梅萨左右冲刺全程不转身（峰值 %.9f rad）" % float(m["peak"]))
	t.near(float(m["pivot"]), 0.0, 0.001, "被消费层（`spin_pivot.rotation_degrees.y` 峰值）同样不转")
	# ②b **该转**的：阿利宙斯常态（本轮新增的白名单成员）。
	var az := await _dash_spin_burst(host, SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL))
	t.ok(bool(az["translate"]), "前置：阿利宙斯**常态**进了平移模式（它不该被 `assist_uses_translation` 挡掉）")
	t.gt(float(az["peak"]), 5.5,
		"阿利宙斯常态左右冲刺**真的转**（峰值 %.3f rad ≈ %.0f°）" % [float(az["peak"]), rad_to_deg(float(az["peak"]))])
	t.gt(float(az["pivot"]), 350.0,
		"被消费层同步（`spin_pivot.rotation_degrees.y` 峰值 %.1f°）" % float(az["pivot"]))


## 真跑一记向左冲刺，返回 `{translate, peak, pivot}`（`peak` = `dash_spin` 弧度峰值，
## `pivot` = 被消费层 `spin_pivot.rotation_degrees.y` 的角度峰值）。
##
## ⚠️ 走的是**生产链路**：`Input`（roll_left）+ `request_quick_boost()` ⇒ `_apply_translate()`
##    ⇒ `_start_dash_spin(_qb_dir)` ⇒ 逐帧推进。⛔ 直接写 `pc.dash_spin` 只能证明"赋值能生效"。
## ⚠️ 峰值取整个窗口（不是取末帧）：窗口走完时两个量都会回到 0，取末帧对**转过的**机体
##    也是 0 ⇒ 那才是恒真断言。
static func _dash_spin_burst(host: Node, prof: SuitProfile) -> Dictionary:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.name = "SpinPolicyProbe"
	pc.profile = prof
	pc.is_player = true
	pc.team = 0
	pc.controls_enabled = true
	c.add_child(pc)
	pc.assist_on = true
	pc.global_position = Vector3(0, 900, 0)
	for i in 240:
		await host.get_tree().physics_frame
	var tm := pc.translate_mode
	Input.action_press("roll_left")
	for i in 6:
		await host.get_tree().physics_frame
	pc.request_quick_boost()
	var peak := 0.0
	var pivot := 0.0
	for i in 36:
		await host.get_tree().physics_frame
		peak = maxf(peak, absf(pc.dash_spin))
		if pc.spin_pivot != null and is_instance_valid(pc.spin_pivot):
			pivot = maxf(pivot, absf(pc.spin_pivot.rotation_degrees.y))
	Input.action_release("roll_left")
	c.free()
	await host.get_tree().physics_frame
	Game.reset()
	return {"translate": tm, "peak": peak, "pivot": pivot}


## ③ W（向前）的提速幅度降档（2026-09-29 用户要求）。
##
## 用户原话：「辅助驾驶模式下按 w 的加速速率下调到 15% 左右」。
## 口径经确认：降的是**提速幅度**（不是速度追随速率 `TRANSLATE_RESPONSE`），
## 且**只降 W** —— 后退 / 横移 / 升降一个字节不动。
##
## ## 三组判据，各钉一件事
##   A **纯函数**：`translate_offset_vec()` 的四档分档（W 降 15% / S·D·升 满权重）
##      + 满杆 W+D 的归一化耦合（前向那一份必须跟着缩，否则对角输入下等于没降）；
##   B **真机**：`Input` 按住 W / S 各跑一段**物理帧**，读出的**速度增量**比 15%；
##   C **接线**：`translate_fwd` 真的被 `_read_translate_input()` 写了（W 有 / D 无）。
##
## ⚠️ 目标值全部**硬编码**（1512 / 0.65 / 0.15 / 2268），
##    ⛔ 不从 `FlightBody.TRANSLATE_FWD_SCALE` 之类的常量里取 ——
##    否则"把它改回 1.0"时目标值会跟着一起变，判据永远是绿的（本工程踩过的自证假绿）。
## ⚠️ `Input.action_press` 在无头环境里是有效的（`_dash_spin_burst` 已用 roll_left 先例）；
##    但 `_read_translate_input` 每帧重写 `translate_dir` / `translate_fwd`，
##    所以要测"按住了"就必须真的按着跑物理帧，不能手写字段。
static func _fwd_offset(t: T, host: Node) -> void:
	t.suite("AssistDrive / W 的提速幅度降档（只 W · 2026-09-29）")
	# 硬编码口径：柯西巡航极速 × 满权重 = 满速修正；× 0.15 = 降档后的 W 修正。
	const TOP_XI := 1512.0            # 420 × 1.50 × 2.4（三处基值，刻意写死不从配置取）
	const FULL := 0.65                # TRANSLATE_OFFSET 的口径值
	const FWD := 0.15                 # TRANSLATE_FWD_SCALE 的口径值
	const BOOST_XI := 2268.0          # 420 × 1.5 × 1.50 × 2.4
	var off := TOP_XI * FULL
	var f := Vector3.FORWARD
	var r := Vector3.RIGHT
	var u := Vector3.UP

	# ---- A 纯函数：四档 ----
	var w_only := FlightBody.translate_offset_vec(f, f, off)
	t.near(w_only.length(), off * FWD, off * 0.001,
		"纯 W：修正 %.2f = 满权重 %.2f 的 15%%（目标 %.2f）" % [w_only.length(), off, off * FWD])
	t.ok(w_only.dot(f) > 0.0, "纯 W：方向仍是向前（没被反号）")
	var s_only := FlightBody.translate_offset_vec(-f, Vector3.ZERO, off)
	t.near(s_only.length(), off, off * 0.001,
		"纯 S：仍是满权重 %.2f —— 降档不许漏到后退上" % off)
	t.ok(s_only.dot(f) < 0.0, "纯 S：方向仍是向后")
	var d_only := FlightBody.translate_offset_vec(r, Vector3.ZERO, off)
	t.near(d_only.length(), off, off * 0.001, "纯 D（横移）：仍是满权重 %.2f" % off)
	var q_only := FlightBody.translate_offset_vec(u, Vector3.ZERO, off)
	t.near(q_only.length(), off, off * 0.001, "纯 Q（上升）：仍是满权重 %.2f" % off)
	# 满杆 W+D：PlayerController 会把输入归一化（系数 k = 1/√2），前向那一份要一起缩。
	# 这里手工复现同一条算式（k 由对角线长度给出），钉住"横移不被牵连、前向确按 15%"。
	var diag := f + r
	var k := 1.0 / diag.length()
	var d2 := diag * k                # = translate_dir（长度 1）
	var f2 := f * k                   # = translate_fwd（前向那一份，已被 k 缩过）
	t.near(f2.length(), 0.70711, 0.0005, "对角 W+D：前向那一份被同一系数缩到 0.7071")
	var got := FlightBody.translate_offset_vec(d2, f2, off)
	t.near(absf(got.dot(r)), off * 0.70711, off * 0.002,
		"对角 W+D：横移仍是满权重（%.2f）—— 没被 W 的降档牵连" % (off * 0.70711))
	t.near(absf(got.dot(f)), off * FWD * 0.70711, off * 0.002,
		"对角 W+D：前向只有 15%%（%.2f）" % (off * FWD * 0.70711))
	# 常量本身也钉一下（防"改了常量却没改判据"这种半升级）
	t.near(FlightBody.TRANSLATE_FWD_SCALE, FWD, 1.0e-9,
		"TRANSLATE_FWD_SCALE = 0.15（实测 %.4f）" % FlightBody.TRANSLATE_FWD_SCALE)
	t.near(FlightBody.TRANSLATE_OFFSET, FULL, 1.0e-9,
		"TRANSLATE_OFFSET 仍是 0.65 —— 其余方向不许被动" )
	# 读数（runner 只在失败时打标签 ⇒ 数字在这里显式打出来，复核时一眼可见）
	print("        [纯函数] 满权重修正 %.1f ｜ W 档修正 %.1f（%.1f%%）｜ S·D·升 各 %.1f"
		% [off, w_only.length(), w_only.length() / off * 100.0, s_only.length()])

	# ---- B + C 真机：按住 W / S 各跑一段物理帧，读速度 ----
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.name = "FwdOffsetProbe"
	pc.profile = SuitProfile.xi()
	pc.is_player = true
	pc.team = 0
	pc.controls_enabled = true
	c.add_child(pc)
	pc.assist_on = true
	# 起点摆在高空：平移模式是"一直往前飞"，贴地跑会撞地自毁（撞了就测不到速度了）。
	# 每帧把位置拉回原点：速度是 `fm.velocity` 的独立状态，复位位置不影响读数，
	# 但能保证 120 帧 × ~2400 m/s 的位移不会飞出场景 / 触发边界。
	for i in 120:
		pc.global_position = Vector3(0, 900, 0)
		await host.get_tree().physics_frame
	t.ok(pc.translate_mode, "前置：辅助开 → 进了平移模式（没进的话下面全是恒真）")
	var v_base := pc.fm.speed
	t.near(v_base, BOOST_XI, BOOST_XI * 0.02,
		"无输入底速 %.1f ≈ 加力极速 %.1f（自动飞行没被动过）" % [v_base, BOOST_XI])

	# 按 W（pitch_nose_down = 前）：增量必须只有满权重的 15%
	Input.action_press("pitch_nose_down")
	for i in 3:
		await host.get_tree().physics_frame
	t.near(pc.translate_fwd.length(), 1.0, 0.02,
		"接线：按 W 时 translate_fwd 被填满（长度 %.3f）" % pc.translate_fwd.length())
	t.gt(pc.translate_dir.dot(pc.translate_fwd), 0.999,
		"接线：translate_fwd 与 translate_dir 同向（dot=%.4f）"
			% pc.translate_dir.dot(pc.translate_fwd))
	for i in 120:
		pc.global_position = Vector3(0, 900, 0)
		await host.get_tree().physics_frame
	var v_w := pc.fm.speed
	var gain_w := v_w - v_base
	t.near(gain_w, off * FWD, off * FWD * 0.05,
		"真机按 W：速度增量 %.1f ≈ 满权重的 15%%（目标 %.1f）" % [gain_w, off * FWD])
	Input.action_release("pitch_nose_down")

	# 按 D（横移）：前向分量为零 = "降档只认 W"的直接证据
	Input.action_press("roll_right")
	for i in 3:
		await host.get_tree().physics_frame
	t.near(pc.translate_fwd.length(), 0.0, 1.0e-6,
		"接线：按 D 时 translate_fwd = 0（横移不算向前）")
	Input.action_release("roll_right")

	# 按 S（pitch_nose_up = 后）：增量仍是**满**权重（没被误降）
	for i in 60:
		pc.global_position = Vector3(0, 900, 0)
		await host.get_tree().physics_frame
	Input.action_press("pitch_nose_up")
	for i in 120:
		pc.global_position = Vector3(0, 900, 0)
		await host.get_tree().physics_frame
	var v_s := pc.fm.speed
	var drop_s := v_base - v_s
	t.near(drop_s, off, off * 0.05,
		"真机按 S：速度降幅 %.1f ≈ 满权重 %.1f —— S 一个字没动" % [drop_s, off])
	Input.action_release("pitch_nose_up")
	print("        [真机] 底速 %.1f ｜ 按 W %.1f（增量 %+.1f）｜ 按 S %.1f（降幅 %.1f）｜ 增量比 %.4f"
		% [v_base, v_w, gain_w, v_s, drop_s, gain_w / maxf(drop_s, 0.001)])

	# 比值：这才是用户那句"下调到 15% 左右"的字面判据（不依赖任何绝对量）
	if absf(drop_s) > 1.0:
		t.near(gain_w / drop_s, FWD, 0.01,
			"W 的增量 ÷ S 的降幅 = %.3f（目标 0.15）" % (gain_w / drop_s))
	else:
		t.ok(false, "S 的降幅 ≈ 0（%.2f）—— 前置不成立，比值判据没意义" % drop_s)

	c.free()
	await host.get_tree().physics_frame
	Game.reset()
