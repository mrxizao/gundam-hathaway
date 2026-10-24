class_name SuiteRound17
extends RefCounted
## 第十七轮：**梅萨M01（第四台可选机体）+ 飞行踏板（敌方装备）**。
##
## ⚠️ 这一轮有一次**实测撞墙**，值得记在这里：
## 飞行踏板的第一版给的是"最高速 ×1.25"，落地后 `suite_round` 与 `suite_round14`
## **两条断言同时红**（实测 724.5 > 580.1）—— 它顶穿的是第十四轮那条
## "敌机上限 ≤ 玩家加力上限 ×0.92"，也就是玩家实测"怎么追都追不上"的修复。
##
## 所以这一轮真正的设计决定是：**踏板不给最高速，给油门响应**
## （`FlightPedal.RIDE_THROTTLE_RESPONSE`）。下面第五组断言就是这条红线的回归门 ——
## 以后谁再想给骑板敌机加最高速，这里会先红。
##
## 分六组测，因为坏起来的样子完全不同：
##   1. **伤害分流**（纯函数）—— 骑乘伤害怎么切给踏板与机体。
##   2. **梅萨M01 的 profile** —— 模型 / 尺寸 / 定位 / 分母。
##   3. **无限弹**（`rifle_ammo_infinite`）—— profile 级开关不许误伤别的机体。
##   4. **菜单接线** —— 1v1 只列三台 ACE，而编队战/剧情/训练仍然用两台量产机。
##   5. **红线：骑板敌机不得越过速度天花板**（本轮踩的那条）+ 加成幂等。
##   6. **骑乘状态**（真起 AI）—— 挂载 / 分流 / 打爆脱板 / 门禁 / 无限弹真机验证。

static func run(t: T, host: Node) -> void:
	t.suite("Round17 / 飞行踏板：伤害分流（纯函数）")
	_damage_split(t)
	t.suite("Round17 / 梅萨M01：profile 与模型")
	_messer(t)
	t.suite("Round17 / 无限弹：开关不许误伤")
	_ammo_switch(t)
	t.suite("Round17 / 菜单接线：1v1 只列 ACE、编队战保留量产机")
	await _wiring(t, host)
	t.suite("Round17 / 红线：骑板敌机不得越过速度天花板")
	await _ceiling(t, host)
	t.suite("Round17 / 飞行踏板：真机挂载与脱板")
	await _live(t, host)
	t.suite("Round17 / 两种板：按阵营选模型")
	_two_boards(t)
	t.suite("Round17 / 两台各带一块板：各板各账、各自脱落")
	await _pair(t, host)
	t.suite("Round17 / 骑乘资格：ACE 机不可骑")
	_ride_eligibility(t)
	t.suite("Round17 / 对战模式：1v1 只有一架敌机")
	await _versus_pair(t, host)
	t.suite("Round17 / 梅萨M01：步枪打不光（真机）")
	await _ammo_live(t, host)


# ---------------------------------------------------------------- 1b 两种板

static func _two_boards(t: T) -> void:
	# "谁骑哪块"的唯一真源。**按阵营**：马夫蒂方（柯西 / 梅萨M01）→ 马夫蒂板；
	# 联邦·喀耳刻部队（佩涅罗佩 / **阿利宙斯** / 古斯塔夫）→ 喀耳刻部队板。
	#
	# ⚠️ **阿利宙斯 2026-09-21 从马夫蒂那边搬过来了**。老板原话：
	# "阿利宙斯居然在马夫蒂里面，问题是阿利宙斯是喀耳刻部队的"。
	# 这一条以前写的是 `Kind.MAFTY` + "阿利宙斯 → 马夫蒂板" —— 版本化的错误，
	# 修的是同一件事的两处（另一处是 `BattleFormation.mafty().aces`）。
	t.eq(FlightPedal.kind_for_suit(SuitProfile.Id.XI), FlightPedal.Kind.MAFTY, "柯西 → 马夫蒂板")
	t.eq(FlightPedal.kind_for_suit(SuitProfile.Id.ARIZEUS), FlightPedal.Kind.KILCE,
		"阿利宙斯 → **喀耳刻板**（它与佩涅罗佩同属喀耳刻部队，不是马夫蒂的）")
	t.eq(FlightPedal.kind_for_suit(SuitProfile.Id.MESSER_M01), FlightPedal.Kind.MAFTY, "梅萨M01 → 马夫蒂板")
	t.eq(FlightPedal.kind_for_suit(SuitProfile.Id.PENELOPE), FlightPedal.Kind.KILCE, "佩涅罗佩 → 喀耳刻板")
	t.eq(FlightPedal.kind_for_suit(SuitProfile.Id.GUSTAV00), FlightPedal.Kind.KILCE, "古斯塔夫00 → 喀耳刻板")

	# 两块板的模型都要真的能加载 + 原生高度对得上探针实测值
	# （改模型不重跑 `probe_model` 的话，这里会红）。
	t.ok(ResourceLoader.exists(FlightPedal.model_path_of(FlightPedal.Kind.MAFTY)),
		"马夫蒂板模型可加载")
	t.ok(ResourceLoader.exists(FlightPedal.model_path_of(FlightPedal.Kind.KILCE)),
		"喀耳刻板模型可加载")
	t.ok(FlightPedal.model_path_of(FlightPedal.Kind.MAFTY).contains("mafty"),
		"马夫蒂板指向 mafty 模型")
	t.ok(FlightPedal.model_path_of(FlightPedal.Kind.KILCE).contains("kilce"),
		"喀耳刻板指向 kilce 模型")
	t.near(FlightPedal.NATIVE_HEIGHT_MAFTY, 0.3062, 0.001, "马夫蒂板原生高 = 探针实测")
	t.near(FlightPedal.NATIVE_HEIGHT_KILCE, 0.3159, 0.001, "喀耳刻板原生高 = 探针实测（两块不一样！）")
	t.not_ok(is_equal_approx(FlightPedal.NATIVE_HEIGHT_MAFTY, FlightPedal.NATIVE_HEIGHT_KILCE),
		"两块板的高度**必须分开记**（写成一个常量会让其中一块静默缩放）")

	# 一块板两个挂位（第二十四轮：座次由**分状态模型**给出）。
	var pd := FlightPedal.new()
	pd.kind = FlightPedal.Kind.KILCE
	t.eq(pd.slot_count(), 2, "一块板有**两个**挂位")
	var s0 := pd.slot_offset(0)
	var s1 := pd.slot_offset(1)

	# ---- 座次：**两族的方位不同**（1.2 第二十四轮：用户给了明确的座次语义）----
	#
	# 用户原话：「**喀耳刻的踏板一号机就是左边的，二号机就是右边的；
	# 马夫蒂的踏板一号机就是前面的，二号机就是后面的**」。
	#
	# 实测两族的座位都沿**模型局部 X** 分开（−X 侧 = 一号机、+X 侧 = 二号机），
	# 于是"同一个局部 X"要分别读成"前后"与"左右" ⇒
	# **两个模型相对飞行方向差 90°**（靠各自的 `MODEL_YAW_DEG` 修正）。
	#
	# 所以这里不再断言"两块板都一样"，而是**分别钉住各自的方位** ——
	# 这条正是用户那句话的可执行版本。
	var m_off := FlightPedal.new()
	m_off.kind = FlightPedal.Kind.MAFTY
	var m0 := m_off.slot_offset(0)
	var m1 := m_off.slot_offset(1)
	# ⚠️ 不要断言"另一轴严格为 0 / 两座位严格等高"：**模型自己就不是那样摆的**
	#（实测马夫蒂两座的 Y 差 0.0255 原生、Z 差 0.0454；喀耳刻也有小的交叉分量）。
	# 判据要钉的是**主方位**：两个座位主要沿哪个轴分开。
	t.gt(absf(m0.z - m1.z), 5.0, "马夫蒂：两个座位主要沿 **Z（前后）** 分开")
	t.lt(absf(m0.x - m1.x), absf(m0.z - m1.z) * 0.5,
		"马夫蒂：X 上的分量**远小于** Z（所以读起来是前后、不是左右）")
	t.gt(absf(s0.x - s1.x), 5.0, "喀耳刻：两个座位主要沿 **X（左右）** 分开")
	t.lt(absf(s0.z - s1.z), absf(s0.x - s1.x) * 0.5,
		"喀耳刻：Z 上的分量**远小于** X（所以读起来是左右、不是前后）")
	# 一号机永远在"负侧"（马夫蒂 = 前、喀耳刻 = 左）—— 两族一致。
	#
	# ⚠️ 这条**必须**有：四选一出图只能分出"轴对不对"，分不出"朝前还是朝后"；
	# 第一次跑（马夫蒂用 90°）就是红的 —— 一号机落到了 +Z（机尾）。
	t.lt(m0.z, m1.z, "马夫蒂：**一号机在前**（−Z 是前）")
	t.lt(s0.x, s1.x, "喀耳刻：**一号机在左**（−X 是左）")
	m_off.free()

	# ---- 间距**由模型量出**（第二十四轮改成"分状态模型自带座次"）----
	#
	# ⚠️ 这里曾经钉过两版会过时的东西：先是写死的 9.0 m、后是"板长 × 0.28"。
	# 现在**座次就是模型自己的属性**（`STATE_RIDER_POS`），
	# 所以我方摆位的自由度归零 —— 断言改成"座次与模型一致、且随缩放走"。
	for k: int in [FlightPedal.Kind.MAFTY, FlightPedal.Kind.KILCE]:
		var pose: Array = FlightPedal.STATE_RIDER_POS[k]
		t.eq(pose.size(), 2, "%s：模型里有**两个**座位" % FlightPedal.kind_name(k))
		# 座次在模型里就是分开的（否则用户那套分状态模型没有意义）
		t.gt((Vector3(pose[1]) - Vector3(pose[0])).length(), 0.1,
			"%s：模型里两个座位确实分开了" % FlightPedal.kind_name(k))
		# 世界间距 = 原生间距 × 载人缩放
		var want := (Vector3(pose[1]) - Vector3(pose[0])).length() \
			* FlightPedal.loaded_scale_of(k)
		t.near(FlightPedal.slot_separation_m(k), want, 0.01,
			"%s：座位间距 = 模型原生间距 × 载人缩放" % FlightPedal.kind_name(k))
		t.gt(FlightPedal.slot_separation_m(k), 5.0,
			"%s：座位间距 > 5 m（两台不会叠在一起）" % FlightPedal.kind_name(k))
	pd.free()


# ---------------------------------------------------------------- 1 伤害分流

static func _damage_split(t: T) -> void:
	# 没骑板 = 伤害全进机体
	var none: Dictionary = FlightPedal.damage_split(100.0, 0.0, false)
	t.near(float(none["to_pedal"]), 0.0, 0.001, "没骑板：进踏板的伤害是 0")
	t.near(float(none["to_hull"]), 100.0, 0.001, "没骑板：伤害全进机体")

	# 踏板还活着 = 按 PEDAL_SHARE 切
	var share := FlightPedal.PEDAL_SHARE
	var mid: Dictionary = FlightPedal.damage_split(100.0, 999.0, true)
	t.near(float(mid["to_pedal"]), 100.0 * share, 0.001,
		"骑板：进踏板的份额 = %.0f%%" % (share * 100.0))
	t.near(float(mid["to_hull"]), 100.0 * (1.0 - share), 0.001, "骑板：其余进机体")
	t.near(float(mid["to_pedal"]) + float(mid["to_hull"]), 100.0, 0.001,
		"骑板：两份加起来**不许凭空多打或少打**（守恒）")

	# 踏板只剩一点血 = 只能吃掉它剩的，**多出来的必须漏给机体**（不许吞伤害）
	var last: Dictionary = FlightPedal.damage_split(100.0, 5.0, true)
	t.near(float(last["to_pedal"]), 5.0, 0.001, "打爆踏板的那一发：踏板只吃自己剩的 5 点")
	t.near(float(last["to_hull"]), 95.0, 0.001,
		"打爆踏板的那一发：剩下 95 点**漏给机体**（不能白打一发）")

	# 踏板已爆（hp=0）= 全部进机体
	var gone: Dictionary = FlightPedal.damage_split(100.0, 0.0, true)
	t.near(float(gone["to_hull"]), 100.0, 0.001, "踏板已爆：伤害全进机体")
	t.near(float(gone["to_pedal"]), 0.0, 0.001, "踏板已爆：进踏板的是 0")

	# 份额必须是个"真选择"而不是唯一解
	t.gt(float(mid["to_hull"]), 0.0, "不管踏板的话机体**照样在掉血**（不是必须先拆踏板的解谜）")
	t.gt(float(mid["to_pedal"]), float(mid["to_hull"]),
		"但踏板吃的是大头（专心打它才是有效率的）")


# ---------------------------------------------------------------- 2 梅萨 profile

static func _messer(t: T) -> void:
	var m := SuitProfile.messer_m01()
	t.eq(m.id, SuitProfile.Id.MESSER_M01, "id 是 MESSER_M01")
	t.eq(m.display_name, "梅萨M01", "显示名是梅萨M01")
	t.ok(ResourceLoader.exists(m.model_path), "模型路径存在：%s" % m.model_path)
	t.ok(m.model_path.contains("messer"), "模型指向 messer 目录（没接错别人的模型）")

	# 尺寸口径：`scale = target_height / model_native_height`，
	# 两个数是**成对**的，改一个会静默缩放整台机。这里钉住探针量到的原生值。
	t.near(m.model_native_height, 0.9995, 0.0005,
		"model_native_height 等于 probe_model 实测值（改模型必须重跑探针）")
	t.near(m.target_height, 22.0, 0.001, "全高 22.0 m（量产机档，与古斯塔夫00 同档）")

	# ---- 朝向修正（`model_yaw_deg`）----
	#
	# 这个模型**不是**朝工程的约定方向（−Z），实测是朝 **+X** ——
	# 老板原话："梅萨的模型方向不对，现在是左边朝前面了"。
	# 绕 Y 转 +90° 把 +X 对到 −Z。数值由老板看
	# `tools/yaw_choices.tscn` 的"yaw = 0 / 90 / 180 / 270 四格图"指定（**第二格**）。
	t.near(m.model_yaw_deg, 90.0, 0.001,
		"梅萨需要 90° 朝向修正（模型朝 +X，工程约定朝 −Z）")
	# 其余三台**都按约定朝 −Z**，不得被动到 —— 它们从来没歪过。
	for p: SuitProfile in [SuitProfile.penelope(),
			SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL), SuitProfile.gustav00_armed()]:
		t.near(p.model_yaw_deg, 0.0, 0.001, "%s 不需要朝向修正（保持 0）" % p.display_name)
	# 柯西：2026-09-26 换了带骨的新资产（`xi_fly.glb`）之后**这条值变了** ——
	# 新资产原生框架正面朝 **+Z**，与工程约定（−Z）差 180°。
	# ⚠️ 别把这条读成"柯西以前歪过"：老资产 `rx105_xi_gundam.glb` 一直是 0°、
	# 且显示正常。**换模型就要重量朝向** —— 不同 glb 的原生框架不保证一致
	#（梅萨M01 是朝 +X ⇒ 90°，见上面那条）。
	t.near(SuitProfile.xi().model_yaw_deg, 180.0, 0.001,
		"柯西需要 180° 朝向修正（新资产朝 +Z，工程约定朝 −Z）")

	# 定位：四台里**最耐打、最慢**
	var xi := SuitProfile.xi()
	t.gt(m.hull_hp + m.ifield_hp, xi.hull_hp + xi.ifield_hp, "总耐久高于柯西")
	t.lt(m.speed_scale, xi.speed_scale, "速度系数低于柯西（它是四台里最慢的）")
	t.lt(m.speed_scale, SuitProfile.penelope().speed_scale, "也低于佩涅罗佩")
	t.near(m.turn_scale, 1.15, 0.001, "转向系数 1.15（比两台主力机钝）")

	# 武器：一把不能丢的枪 + 火神炮 + 军刀，**没有导弹**
	t.eq(m.rifle_count, 1, "只带一把光束步枪")
	t.not_ok(m.can_discard_rifle, "不能丢枪（马夫蒂的量产机没资格丢）")
	t.ok(m.has_vulcan(), "装了火神炮")
	t.ok(m.has_saber, "装了光束军刀")
	t.not_ok(m.has_missiles, "**没有浮游导弹**")
	t.eq(m.funnel_count, 0, "导弹载弹为 0")

	# 数值条的分母必须跟着新机走，否则"改了数值忘了改分母"会让条形图静默失效
	t.gt(SuitProfile.hull_bar_ref(), m.hull_hp, "机体耐久条的分母 ≥ 梅萨的耐久（条画得出来）")
	t.gt(SuitProfile.ifield_bar_ref(), m.ifield_hp, "I 立场条的分母 ≥ 梅萨的护盾")

	# by_id 接线
	t.eq(SuitProfile.by_id(SuitProfile.Id.MESSER_M01).display_name, "梅萨M01",
		"by_id 能查到梅萨（挑战/联机都走这条）")
	t.eq(SuitProfile.forms_of(SuitProfile.Id.MESSER_M01).size(), 1, "是单形态机体")


# ---------------------------------------------------------------- 3 无限弹开关

static func _ammo_switch(t: T) -> void:
	var m := SuitProfile.messer_m01()
	t.ok(m.rifle_ammo_infinite, "梅萨的 rifle_ammo_infinite = true")

	# 其余机体不得被这条影响（共用一份 SuitProfile 类，最容易误伤）
	for p: SuitProfile in [SuitProfile.xi(), SuitProfile.penelope(),
			SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL),
			SuitProfile.gustav00_armed()]:
		t.not_ok(p.rifle_ammo_infinite, "%s 仍然要换弹（没被梅萨的无限弹带跑）" % p.display_name)


# ---------------------------------------------------------------- 4 菜单接线

static func _wiring(t: T, host: Node) -> void:
	# ⚠️ **第二十二轮下半：量产机从对战菜单里撤掉了**（用户要求）。
	# 原话：「把**王牌机对战**里面的古斯塔夫和梅萨都移除，**敌人选择**里面的也一样」。
	# 于是机体页与敌机页都只剩**三台 ACE**（柯西 / 佩涅罗佩 / 阿利宙斯）。
	#
	# ⚠️ 撤掉的**只是"可选"**，两台量产机本身还在工程里：
	#   - 编队战的编制表（`BattleFormation`）与剧情波次仍然用它们；
	#   - 训练模式的四架**靶机**仍然是古斯塔夫00（不还手的那份）。
	# 所以下面那组"武装版古斯塔夫仍然可用"的断言**照旧保留**。
	t.eq(MainMenu.SUITS.size(), 5, "机体页五台 ACE（含GP03D与露维杰露）")
	t.ok(not MainMenu.SUITS.has(SuitProfile.Id.MESSER_M01), "SUITS 里**没有**梅萨M01")
	t.ok(not MainMenu.SUITS.has(SuitProfile.Id.GUSTAV00), "SUITS 里**没有**古斯塔夫00")
	t.eq(MainMenu.ENEMY_SUITS.size(), 5, "敌机页五台 ACE（含GP03D与露维杰露）")
	t.ok(not MainMenu.ENEMY_SUITS.has(SuitProfile.Id.MESSER_M01), "敌机页没有梅萨M01")
	t.ok(not MainMenu.ENEMY_SUITS.has(SuitProfile.Id.GUSTAV00), "敌机页没有古斯塔夫00")
	# 两台 ACE 主机一台都不能少（撤过量产机会让人以为"顺手也把 ACE 删了"）。
	for ace: int in [SuitProfile.Id.XI, SuitProfile.Id.PENELOPE, SuitProfile.Id.ARIZEUS]:
		t.ok(MainMenu.SUITS.has(ace), "SUITS 里仍然有 ACE %d" % ace)
		t.ok(MainMenu.ENEMY_SUITS.has(ace), "ENEMY_SUITS 里仍然有 ACE %d" % ace)

	# ⚠️ **1v1 的对手池也撤掉了这两台**（`Main.versus_opponent_of`）——
	# 否则"敌机页选不到梅萨，但打 1v1 时它还是会冒出来当对手"，那就自相矛盾。
	#
	# ⚠️ 这里**不能写 `Main.versus_opponent_of(...)`**：`main.gd` 挂在场景根节点上、
	# **没有 `class_name`**，静态上下文里根本没有 `Main` 这个名字
	#（`suite_round19` 第一版就是这么红的：`Identifier "Main" not declared`）。
	# 正解：把 `main.tscn` 实例化出来，**从实例上取那个静态方法**。
	var main_scene: Node = load("res://scenes/main.tscn").instantiate()
	host.add_child(main_scene)
	await host.get_tree().physics_frame
	# 判据：拿每一台可选机体去要对手，结果都必须是**三台 ACE 之一**。
	for id: int in MainMenu.SUITS:
		var foe: int = main_scene.call("versus_opponent_of", id)
		t.ok(foe != SuitProfile.Id.MESSER_M01 and foe != SuitProfile.Id.GUSTAV00,
			"玩家开 %d 时的对手不是量产机（%d）" % [id, foe])
		t.ok(MainMenu.ENEMY_SUITS.has(foe) or foe == id,
			"对手 %d 落在敌机页的池子里" % foe)
	main_scene.queue_free()
	await host.get_tree().physics_frame

	# ⚠️ 玩家选到的古斯塔夫必须是**武装版**：`by_id` 的默认分支决定这件事，
	# 而靶机版（不还手）只能由训练模式显式索取（`gustav00()`）。
	#（它现在不在对战菜单里了，但这条性质仍然被剧情/编队战用到。）
	var g := SuitProfile.by_id(SuitProfile.Id.GUSTAV00)
	t.ok(g.rifle_count > 0, "可选的那份古斯塔夫**有武器**（不是靶机版）")
	t.ok(g.has_vulcan() or g.has_saber, "它至少有一门能开火的装备")
	t.not_ok(g.display_name.contains("靶机"), "显示名里没有「靶机」字样")
	t.ok(SuitProfile.gustav00().display_name.contains("靶机"),
		"（对照）靶机版仍然叫「古斯塔夫00（靶机）」")

	# 三台机的数值都能取到（卡片绘制会逐张读 profile，取不到会画出空卡）
	for id: int in MainMenu.SUITS:
		var p := SuitProfile.by_id(id)
		t.ok(p != null and p.display_name != "", "SUITS 里的 id %d 能取到 profile" % id)

	# ---- ⚠️ 反向的一半：**编队战里两台量产机必须还在** ----
	# 用户特意补了一句："**小队作战里面的保留**"。
	# 所以这里要同时钉住两件相反的事，少钉一件就会出事：
	#   ① 1v1 菜单里**没有**量产机（上面那组）；
	#   ② 编队战的编制表里**有**量产机（这一组）。
	# 如果只钉 ①，以后有人"顺手统一一下"把编制表里的量产机也删掉，
	# 编队战就会变成"两边都只有 ACE"——而那正是用户不要的。
	var maf := BattleFormation.roster_of(BattleFormation.Side.MAFTY)
	var fed := BattleFormation.roster_of(BattleFormation.Side.FEDERATION)
	t.ok(maf.mass_production.has(SuitProfile.Id.MESSER_M01),
		"编队战·马夫蒂侧仍然有梅萨M01（保留）")
	t.ok(fed.mass_production.has(SuitProfile.Id.GUSTAV00),
		"编队战·联邦侧仍然有古斯塔夫00（保留）")
	# 而且它们要能被菜单列出来（`all_suits()` 是编队战机体页的真源）。
	t.ok(maf.all_suits().has(SuitProfile.Id.MESSER_M01),
		"马夫蒂的编队菜单列得出梅萨M01")
	t.ok(fed.all_suits().has(SuitProfile.Id.GUSTAV00),
		"联邦的编队菜单列得出古斯塔夫00")
	t.ok(maf.all_suits().size() >= 2 and fed.all_suits().size() >= 3,
		"两侧编队菜单都至少是「ACE + 量产机」（马夫蒂 %d / 联邦 %d）"
			% [maf.all_suits().size(), fed.all_suits().size()])


# ---------------------------------------------------------------- 5 红线（本轮踩的）

static func _ceiling(t: T, host: Node) -> void:
	# 先钉住常量本身：**踏板不许改最高速**。
	# 这条断言是"本轮那次撞墙"的可执行形式 —— 第一版这里是 1.25，两条断言当场红。
	t.not_ok("RIDE_SPEED_MUL" in FlightPedal,
		"FlightPedal **没有**最高速倍率这个常量（有就是又要把天花板顶穿了）")
	t.gt(FlightPedal.RIDE_THROTTLE_RESPONSE, 1.0, "踏板的收益是油门响应（>1.0）")
	t.lt(FlightPedal.RIDE_TURN_MUL, 1.0, "踏板的代价是转向（<1.0）——有收益就必须有代价")

	# 再走真实路径：起一台带踏板的敌机，量它实际的 max_speed
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
	ai.name = "Round17PedalBandit"
	ai.team = 1
	ai.profile = SuitProfile.penelope()
	ai.difficulty = Difficulty.make(Difficulty.Level.HARD)
	ai.projectile_container = c
	c.add_child(ai)
	# ⚠️ **必须摆到巡航高度**：AI 出生在原点的话，第一个物理帧就低于
	# `FlightBody.CRASH_ALTITUDE`（24 m）→ 直接撞地死掉，
	# 而 `take_damage()` 对已死的机体会静默返回（本轮就是这么踩的：
	# 10 条断言全红，第一条是"挨打完全没反应"）。
	ai.global_position = Vector3(0.0, 3200.0, 0.0)
	await host.get_tree().physics_frame

	ai.configure_pedal()
	ai._apply_top_speed()
	await host.get_tree().physics_frame

	t.ok(ai.alive, "敌机还活着（没在第一个物理帧撞地）")
	t.ok(ai.has_pedal(), "敌机挂上了踏板")
	var ceiling: float = SuitProfile.xi().player_boost_speed() * SuitProfile.ENEMY_SPEED_CEILING_RATIO
	t.lt(ai.fm.max_speed, ceiling + 0.5,
		"**挂着踏板的敌机**仍然不超过玩家加力 ×0.92（这就是本轮踩的那条红线）")
	t.near(ai.fm.max_speed,
		ai.profile.enemy_top_speed_capped(ai.difficulty.speed_mult,
			SuitProfile.xi().player_boost_speed()), 0.5,
		"骑板敌机的上限 == 不带踏板的难度表值（踏板真的没碰最高速）")

	# 油门响应必须**真的**被贴上，而且**只能贴一次**
	var m := FlightPedal.RIDE_THROTTLE_RESPONSE
	t.near(ai.fm.accel, ai.fm.max_speed * 0.17 * m, 0.5, "骑板：加速贴上响应倍率")
	t.near(ai.fm.ab_accel, ai.fm.max_speed * 0.36 * m, 0.5, "骑板：加力加速贴上响应倍率")
	t.near(ai.fm.brake, ai.fm.max_speed * 0.27 * m, 0.5, "骑板：减速贴上响应倍率")

	# 幂等：再贴两次不许继续变大（累乘会让敌机变成火箭）
	ai.apply_pedal_flight_bonus()
	ai._apply_top_speed()
	t.near(ai.fm.accel, ai.fm.max_speed * 0.17 * m, 0.5,
		"重复贴加成是幂等的（写成累乘的话变形两次之后敌机就成火箭了）")

	# 转向折扣：与"同 profile、同难度、不骑板"的对照机体比，比值必须正好是 RIDE_TURN_MUL
	var ref := BanditAI.new()
	ref.name = "Round17RefBandit"
	ref.team = 1
	ref.profile = SuitProfile.penelope()
	ref.difficulty = Difficulty.make(Difficulty.Level.HARD)
	ref.projectile_container = c
	c.add_child(ref)
	ref.global_position = Vector3(0.0, 3200.0, 0.0)
	await host.get_tree().physics_frame
	t.near(ai.fm.pitch_rate / ref.fm.pitch_rate, FlightPedal.RIDE_TURN_MUL, 0.01,
		"骑板的俯仰角速率 = 不骑板的 ×RIDE_TURN_MUL（转向折扣只贴一次）")
	t.near(ai.fm.roll_rate / ref.fm.roll_rate, FlightPedal.RIDE_TURN_MUL, 0.01, "滚转同理")
	t.near(ai.fm.yaw_rate / ref.fm.yaw_rate, FlightPedal.RIDE_TURN_MUL, 0.01, "偏航同理")

	c.queue_free()


# ---------------------------------------------------------------- 6 真机挂载与脱板

static func _live(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var ai := BanditAI.new()
	ai.name = "Round17RideBandit"
	ai.team = 1
	ai.profile = SuitProfile.messer_m01()
	ai.difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	ai.projectile_container = c
	c.add_child(ai)
	# ⚠️ 同 `_ceiling`：不摆高就是"出生即撞地"，后面的伤害断言会被 `alive` 静默挡掉。
	ai.global_position = Vector3(0.0, 3200.0, 0.0)
	await host.get_tree().physics_frame

	# 没挂之前
	t.not_ok(ai.has_pedal(), "默认**没有**踏板（挂载是一个显式动作）")
	t.not_ok(ai.pedal_restricts_melee(), "没骑板时不限制军刀")
	t.ok(ai.alive, "敌机还活着（可以安全地做伤害断言）")

	ai.configure_pedal()
	await host.get_tree().physics_frame
	t.ok(ai.has_pedal(), "configure_pedal() 之后骑上了")
	t.near(ai.pedal.max_hp, ai.max_hp * FlightPedal.HP_RATIO, 0.01,
		"踏板耐久 = 骑手最大耐久 × HP_RATIO")
	t.near(ai.pedal.ratio(), 1.0, 0.001, "刚装上是满耐久")

	# 骑板时**不再**禁止军刀（1.2 第十九轮推翻了那条规则：量产机要骑板赶路，
	# 禁刀 = 那六台整场近战残废，而且让相杀对骑板者永远不可达）。
	# 踏板现在的取舍只剩"转向钝 + 不能悬停"，见 `FlightBody.try_saber()` 的注释。
	t.not_ok(ai.pedal_restricts_melee(), "骑板**不再**限制军刀（第十九轮改的）")
	t.ok(ai.try_saber(null), "骑板时**挥得出**光束军刀")
	ai.abort_saber()
	await host.get_tree().physics_frame

	# 伤害走分流：踏板掉血，机体**也要**掉血
	var hull_before := ai.hp
	var ifield_before := ai.ifield_hp
	var pedal_before := ai.pedal.hp
	ai.take_damage(100.0, null, Damage.Type.BEAM)
	t.lt(ai.pedal.hp, pedal_before, "挨打之后踏板掉血了")
	t.ok(ai.hp < hull_before or ai.ifield_hp < ifield_before,
		"挨打之后机体侧也扣了（不管踏板是打得到人的）")

	# 把踏板打爆 → 脱板 + 失能 + 被抛出
	var target := ai.pedal
	t.gt(Game.pedals_destroyed, -1, "结算统计字段存在（pedals_destroyed）")
	# 一发足够大的伤害把它打光
	ai.take_damage(400.0, null, Damage.Type.BEAM)
	await host.get_tree().physics_frame
	t.not_ok(ai.has_pedal(), "打爆之后**不再是骑乘状态**")
	t.ok(ai.is_staggered(), "脱板之后进入失能（玩家能抓住的窗口）")
	t.ok(ai.stagger_left() > 0.0 and ai.stagger_left() <= FlightPedal.STAGGER_TIME + 0.001,
		"失能剩余在 (0, STAGGER_TIME] 之间")
	t.not_ok(is_instance_valid(target) and target.is_alive(), "踏板节点已经不活了")
	# HUD 的目标读数会调 `t.pedal.ratio()`：脱板后 `t.pedal` 必须是 null，
	# 否则 HUD 会在 `has_pedal()` 之外再碰一次已释放的节点（那类崩溃只在画帧时炸）。
	t.not_ok(ai.has_pedal(), "脱板后 has_pedal() == false（HUD 读它之前会先判这个）")
	# 抛出：这一帧的物理还没走完，速度会立刻被气动拉一点，所以给宽一点的容差，
	# 断言的是"速度被换成了抛出量级"（撞地/未抛出时这里会是几百甚至 0）。
	t.near(ai.fm.speed, FlightPedal.THROW_SPEED, 60.0, "骑手被按抛出速度甩出去")

	# 失能期间打不出东西
	t.not_ok(ai.fire_beam(true, null), "失能期间**打不出光束**")
	t.not_ok(ai.fire_gun(true, null), "失能期间**打不出火神炮**")
	t.not_ok(ai.try_saber(null), "失能期间**挥不出军刀**")

	# 失能结束后门禁放开
	ai._stagger_timer = 0.0
	t.not_ok(ai.is_staggered(), "失能可以结束（倒计时归零）")
	t.not_ok(ai.pedal_restricts_melee(), "脱板之后不再限制军刀")

	c.queue_free()


# ---------------------------------------------------------------- 6b 一板载两台

static func _pair(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)

	# 两台**各带一块板**（当前路线：每台机体带自己的模型，各自能独立开火/脱落）
	var lead := BanditAI.new()
	lead.name = "Round17PairLead"
	lead.team = 1
	lead.profile = SuitProfile.messer_m01()
	lead.difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	lead.projectile_container = c
	c.add_child(lead)
	lead.global_position = Vector3(0.0, 3200.0, 0.0)
	await host.get_tree().physics_frame
	lead.configure_pedal()

	var wing := BanditAI.new()
	wing.name = "Round17PairWing"
	wing.team = 1
	wing.profile = SuitProfile.messer_m01()
	wing.difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	wing.projectile_container = c
	c.add_child(wing)
	wing.global_position = Vector3(FlightPedal.SLOT_SPREAD_X_M, 3200.0, 0.0)
	await host.get_tree().physics_frame
	wing.configure_pedal()
	await host.get_tree().physics_frame

	var board_l := lead.pedal_owner()
	var board_w := wing.pedal_owner()
	t.ok(board_l != null and board_w != null, "两台**都**骑上了板")
	t.ok(board_l != board_w, "两台**各自**一块板（不是共用一块）")
	t.eq(board_l.riders.size(), 1, "领机那块板上只有他自己")
	t.eq(board_w.riders.size(), 1, "后机那块板上只有他自己")
	t.ok(lead.has_pedal() and wing.has_pedal(), "两台 has_pedal() 都为真")

	# 阵营必须成对：梅萨是马夫蒂方 ⇒ 两块都是马夫蒂板
	t.eq(board_l.kind, FlightPedal.Kind.MAFTY, "梅萨的板是马夫蒂那块")
	t.eq(board_w.kind, FlightPedal.Kind.MAFTY, "后机同理（阵营一致）")

	# **并排**：两台的挂位在 X 上分开（用户给的是"并排"不是前后）
	# 座次：第二十四轮起是**分状态模型自带**的，所以只钉"两个座位确实分开"
	# 与"主要沿哪个轴分"—— 不断言"另一轴严格为 0 / 两座位严格等高"
	#（模型自己就不是那样摆的）。
	var s0 := board_l.slot_offset(0)
	var s1 := board_l.slot_offset(1)
	t.gt((s0 - s1).length(), 1.0, "两个座位确实分开了")
	# 梅萨是马夫蒂方 ⇒ 主方位是**前后（Z）**。
	t.gt(absf(s0.z - s1.z), 5.0, "马夫蒂板：两个座位主要沿 Z 分开（前后）")

	# 踏板武器由**板上第二位骑手**负责；单骑时退回他自己
	t.ok(board_l.gun_operator() == lead, "只有一台骑手时，踏板武器归他自己")
	board_w.add_rider(lead)
	t.ok(board_w.gun_operator() == lead, "板上两位时，武器归 **riders[1]**（后一位）")
	board_w.remove_rider(lead)

	# 伤害各进各的板
	var hp_l := board_l.hp
	var hp_w := board_w.hp
	wing.take_damage(120.0, null, Damage.Type.BEAM)
	t.lt(board_w.hp, hp_w, "打后机 → 后机那块板掉耐久")
	t.near(board_l.hp, hp_l, 0.001, "（领机那块板没被碰到：各板各账）")

	# 板爆 → 只有那台被放下来
	wing.take_damage(900.0, null, Damage.Type.BEAM)
	await host.get_tree().physics_frame
	t.not_ok(wing.has_pedal(), "后机的板爆了，他脱板")
	t.ok(lead.has_pedal(), "**领机还在板上**（不会被别人的板牵连）")
	t.ok(wing.is_staggered(), "脱板之后进入失能")
	t.ok(Game.pedals_destroyed > 0, "击毁踏板计入结算统计")

	c.queue_free()


# ---------------------------------------------------------------- 6b2 骑乘资格

static func _ride_eligibility(t: T) -> void:
	# 用户指定："AI 僚机能用，玩家在操控**古斯塔夫和梅萨**的时候也能用，
	# 但是操控 **ACE 机（柯西 / 佩涅罗佩 / 阿利宙斯）不能用**"。
	var ace: Array = [SuitProfile.xi(), SuitProfile.penelope(),
		SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL)]
	for p: SuitProfile in ace:
		t.ok(p.is_ace(), "%s 是 ACE 机" % p.display_name)
		t.not_ok(p.can_ride_pedal(), "%s **不可**骑踏板" % p.display_name)
	var mp: Array = [SuitProfile.messer_m01(), SuitProfile.gustav00_armed(),
		SuitProfile.gustav00()]
	for p: SuitProfile in mp:
		t.not_ok(p.is_ace(), "%s 不是 ACE 机（量产机）" % p.display_name)
		t.ok(p.can_ride_pedal(), "%s **可以**骑踏板" % p.display_name)
	# 判据方向：写成"是不是 ACE"（黑名单式）= 新机体**默认能骑**。
	# 反过来写成白名单的话，忘登记的代价是"这台机莫名其妙骑不了"（难查得多）。
	t.not_ok(SuitProfile.xi().can_ride_pedal(), "ACE 机的判据真的被 `can_ride_pedal()` 读到了")


# ---------------------------------------------------------------- 6c 对战模式真的出一对

static func _versus_pair(t: T, host: Node) -> void:
	Game.reset()
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main_scene)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame

	# ⚠️ **1v1 必须只有一架敌机。**
	#
	# 这里曾经断言"对手是一对（2 台）"—— 那是第十七轮的历史：当时工程里还没有
	# "编队"这个概念，我把"两台"塞进了 1v1。用户随后实测报障：
	# **"游戏的 1v1 对战模式会多一台敌机"**。
	#
	# 第二十轮给"多台 + 踏板 + 编队"做了**独立模式**（`MatchMode.SQUAD`），
	# 所以 1v1 回到纯 1v1，这条断言也跟着反过来钉住"**只有一架**"。
	main_scene.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.NORMAL,
		MapDef.Id.PACIFIC, Game.MatchMode.VERSUS, SuitProfile.Id.MESSER_M01)
	for i in 12:
		await host.get_tree().physics_frame

	var player = main_scene.get("player")
	t.ok(player != null, "对战局建起来了")
	t.not_ok(player.has_pedal(), "玩家开**柯西（ACE）** ⇒ 他自己没有板")
	var foes := Game.live_hostiles_of(player)
	t.eq(foes.size(), 1, "1v1 的对手**只有一架**（回归门：曾经多出一台僚机）")

	# 那一架骑着自己的板（梅萨是量产机 ⇒ 骑得了板）。
	var lead: BanditAI = main_scene.get("enemy")
	if lead != null and is_instance_valid(lead):
		t.eq(foes[0], lead, "那唯一一架就是 `main.enemy`")
		t.ok(lead.has_pedal(), "它是量产机 ⇒ 骑着自己的板")
		t.eq(lead.pedal_owner().kind, FlightPedal.Kind.MAFTY,
			"梅萨骑的是马夫蒂那块板（按阵营）")

	# 对照：**编队战**才应该出多台（见 `suite_round20`）。
	# 这里只确认"模式不同、编制不同"这件事是由模式决定的，而不是随机撒。
	t.eq(Game.squad_units_per_side, 0, "1v1 里没有编队规模（`squad_units_per_side` = 0）")

	main_scene.queue_free()
	await host.get_tree().physics_frame


# ---------------------------------------------------------------- 7 无限弹（真机）
## 单独跑，因为它要一台**完整**的机体（有 `projectile_container` 与炮口）。
static func _ammo_live(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var pc := PlayerController.new()
	pc.name = "Round17AmmoMesser"
	pc.profile = SuitProfile.messer_m01()
	pc.is_player = true
	pc.team = 0
	pc.projectile_container = c
	c.add_child(pc)
	await host.get_tree().physics_frame

	t.ok(pc.has_infinite_rifle_ammo(), "梅萨：has_infinite_rifle_ammo() = true")
	t.eq(pc.rifle_mag, pc.profile.rifle_magazine, "弹匣初始是满的")
	t.near(pc.mag_ratio(), 1.0, 0.001, "弹匣条恒满（HUD 另画 ∞）")
	t.not_ok(pc.reload_rifle(), "无限弹的机体**换不了弹**（弹匣恒满，这是正确行为）")

	# 连开三枪：弹匣不许掉（这是"打不光"的字面验证）
	var before := pc.rifle_mag
	for i in 3:
		pc.rifle_cooldown = 0.0
		pc.fire_beam(true, null)
	t.eq(pc.rifle_mag, before,
		"连打三枪之后弹匣**一点没掉**（打不光）——掉任意一点都说明消耗没接对")

	# 对照组：柯西打两枪会掉两发（证明上面"没掉"是因为无限弹，不是因为打不出去）
	var c2 := Node3D.new()
	host.add_child(c2)
	var pc2 := PlayerController.new()
	pc2.name = "Round17AmmoXiRef"
	pc2.profile = SuitProfile.xi()
	pc2.is_player = true
	pc2.team = 0
	pc2.projectile_container = c2
	c2.add_child(pc2)
	await host.get_tree().physics_frame
	var mag_before := pc2.rifle_mag
	for i in 2:
		pc2.rifle_cooldown = 0.0
		pc2.fire_beam(true, null)
	t.eq(pc2.rifle_mag, mag_before - 2,
		"对照组：柯西连打两枪**掉两发**（说明上面那条不是'根本没打出去'）")

	c.queue_free()
	c2.queue_free()
