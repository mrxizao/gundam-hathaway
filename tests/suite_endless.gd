class_name SuiteEndless
extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## ★63-24「无限强化演习」—— 判据（设计文档 §13）
##
## 口径沿用本项目既有做法：**纯函数直测 + 源码扫描接线 + 负对照**。
##
## ## 两条从 ★63-19 学来的纪律（设计 §13 末尾点名）
##
## 1. 判 CRLF / 行尾相关的断言要用 Python 读 `"rb"`（`io.open(encoding=...)` 会折掉 `\r\n`）。
## 2. 本工程测试分节的"打印形"是 `^--- 名字 ---`，源码写法是 `t.suite("Suite / 小节名")`
##    —— **数分节要数日志里的 `^--- `，不要 grep 源码**。
##
## ## ⚠️ 分节分两批落地（诚实交代，见 `upgrade_card.gd` 文件头"本轮覆盖范围"）
##
## **R2a / R2b 接线落地之后补上的四个分节**（本轮新增）：
##
##   · `NO_WIN`    演习**永不判胜** —— 行为三态 + 负对照 + 源码切片钉"守卫的位置"
##   · `RESET`     局间逐字段归零 + 「请求通道」是**唯一**故意活着的例外
##   · `NOCARRY`   局内即焚：不写 `campaign.cfg` / 那个全局乘法只乘进 `damage_mult`
##   · `LAYOUT`    模式页 5 行 / 步骤条 / 导航轴 / 鼠标几何不落 `Geo.NONE`
##
## ## **R3（本轮）补上的三个分节** —— 间歇轮三选一落地之后：
##
##   · `INTERMISSION`         倒计时 / 操作暂停 / 耗时回补 / 轮型 / 张数 / 焦点 / 收轮
##     （§7.2 的两条边界逐条喂边界值钉死；原先是只有"基础时长 10 s"两行的空壳）
##   · `INTERMISSION_WIRING`  状态机与面板的**接线**（源码扫描）——
##     这几条的共同症状是「测试全绿、游戏里少一块」：`CLEARING` 还直接刷下一波、
##     `_take_endless_card()` 少一句 `refresh_profile_stats()`、HUD 只接了一条绘制路径
##   · `INTERMISSION_UI`      三选一面板的版式与鼠标命中（纯函数，三种窗口尺寸）
##
## **仍然故意没有的**（"接线还没落地、写了就是假绿"）：
##
##   · `AMMO_LAND`   第 ②~④ 条要真 `FlightBody` 发射 ⇒ 本轮只钉住第 ① 条（默认 3）
##   · `ENEMY_IDEM`  要敌机切形态 ⇒ 等 `bandit_ai` 接线轮

const XI := SuitProfile.Id.XI
const PENELOPE := SuitProfile.Id.PENELOPE
const MESSER := SuitProfile.Id.MESSER_M01
const GUSTAV := SuitProfile.Id.GUSTAV00
const Intensity := preload("res://scripts/ui/endless_intensity_hud.gd")


static func run(t: T, _host: Node) -> void:
	t.suite("Endless / 品质抽取（pick_tier 边界）")
	_tier_bounds(t)
	t.suite("Endless / RADICAL 第四档（全局唯一 + 已持有不再刷新）")
	_radical(t)
	t.suite("Endless / POOL 芯片库完整性（20 格）")
	_pool(t)
	t.suite("Endless / POOL_SRC 落点必须指到真实符号")
	_pool_src(t)
	t.suite("Endless / AMMO 不许把无限弹药当成本")
	_ammo(t)
	t.suite("Endless / HEAL 回血走既有修复包体系")
	_heal(t)
	t.suite("Endless / WAVE 波次阵容（两池交集为空）")
	_wave(t)
	t.suite("Endless / WAVE_GUSTAV 静默失败门")
	_wave_gustav(t)
	t.suite("Endless / ENEMY_SCALE 时间档爬升")
	_enemy_scale(t)
	t.suite("Endless / INTENSITY_UI clock, levels and viewport layout")
	_intensity(t)
	t.suite("Endless / ENEMY_COUNT 数量爬升 + 软上限")
	_enemy_count(t)
	t.suite("Endless / BONUS 奖励轮")
	_bonus(t)
	t.suite("Endless / INTERMISSION 倒计时 / 回补 / 轮型 / 张数（§7.2 边界表）")
	_intermission(t)
	t.suite("Endless / INTERMISSION_WIRING 状态机与面板的接线（源码扫描）")
	_intermission_wiring(t)
	t.suite("Endless / INTERMISSION_UI 三选一面板的版式与命中（纯函数）")
	_intermission_layout(t)
	t.suite("Endless / IDEMPOTENT 同一批卡重复施加逐位一致")
	_idempotent(t)
	t.suite("Endless / DURABILITY 装甲卡的 setter 坑")
	_durability(t)
	t.suite("Endless / NO_LEAK 不污染静态工厂与敌机实例")
	_no_leak(t)
	t.suite("Endless / WIRING 字段提升的接线（源码扫描）")
	_wiring(t)
	t.suite("Endless / NO_WIN 演习永不判胜（三态 + 负对照 + 源码位置）")
	_no_win(t)
	t.suite("Endless / RESET 局间归零（请求通道是唯一例外）")
	_reset(t)
	t.suite("Endless / NOCARRY 局内即焚（不写盘 / 那个乘法不外溢）")
	_nocarry(t)
	t.suite("Endless / LAYOUT 模式页与开局配置页的版式接线")
	_layout(t)


# ═══════════════════════════ 分节实现 ═══════════════════════════

static func _intensity(t: T) -> void:
	t.eq(MainMenu.ENDLESS_TITLE,"无限激化模拟","one mode title across menu configuration")
	t.eq(MainMenu.mode_info(Game.MatchMode.ENDLESS)["name"],MainMenu.ENDLESS_TITLE,"mode detail matches homepage title")
	for sample: Array in [[0.0,1,"00:00","05:00",1.0], [299.9,1,"04:59","00:01",1.0], [300.0,2,"05:00","05:00",1.1], [600.0,3,"10:00","05:00",1.21], [3600.0,13,"60:00","05:00",pow(1.1,12)]]:
		var d := Intensity.readout(sample[0])
		t.eq(d["level"],sample[1],"HUD level changes at actual rule boundary")
		t.eq(d["elapsed"],sample[2],"survival timer uses run clock")
		t.eq(d["next_in"],sample[3],"next tier countdown rounds up")
		t.near(d["damage"],sample[4],0.00001,"display multiplier matches damage rule")
		t.ok(d["progress"] >= 0 and d["progress"] < 1,"progress resets within valid range")
		var current := 0
		for row: Dictionary in d["rows"]:
			if row["current"]:
				current += 1
				t.eq(row["level"],d["level"],"highlight follows current unbounded tier")
				t.near(row["damage"],d["damage"],0.00001,"highlighted cell matches actual multiplier")
		t.eq(current,1,"exactly one tier is highlighted")
	t.eq(Intensity.readout(-1)["elapsed"],"00:00","negative time safely clamps")
	for view: Vector2 in [Vector2(1280,720),Vector2(2560,1600),Vector2(3440,1440),Vector2(1280,960)]:
		var g := FlightHUD.ThirdPersonHUD.layout(view)
		var r := Intensity.panel_rect(view)
		t.ok(Rect2(Vector2.ZERO,g["view"]).encloses(r),"intensity panel fits viewport")
		t.ok(not r.has_point(g["center"]),"panel leaves central aim area open")
		for key in ["ap","radar","weapons","energy","speed","alt"]:
			t.ok(not r.intersects(g[key]),"intensity table avoids "+key)
		var mag := FlightHUD.ThirdPersonHUD.magnifier_rect(view)
		var u: float = g["scale"]
		t.ok(not r.intersects(Rect2(mag.position/u,mag.size/u)),"table avoids magnifier")

static func _tier_bounds(t: T) -> void:
	var B := UpgradeCard.Tier.BASIC
	var A := UpgradeCard.Tier.ADVANCED
	var P := UpgradeCard.Tier.PERFECT
	var R := UpgradeCard.Tier.RADICAL
	t.eq(EndlessScript.pick_tier(0.0, false), B, "roll 0.0 → 基础")
	t.eq(EndlessScript.pick_tier(0.299, false), B, "roll 0.299 → 基础")
	t.eq(EndlessScript.pick_tier(0.30, false), A, "roll 0.30 → 进阶（边界归上档）")
	t.eq(EndlessScript.pick_tier(0.799, false), A, "roll 0.799 → 进阶")
	t.eq(EndlessScript.pick_tier(0.80, false), P, "roll 0.80 → 完美")
	t.eq(EndlessScript.pick_tier(0.899, false), P, "roll 0.899 → 完美")
	t.eq(EndlessScript.pick_tier(0.90, false), R, "roll 0.90 → 激进")
	t.eq(EndlessScript.pick_tier(0.9999, false), R, "roll 0.9999 → 激进")
	# 权重和必须正好 100 —— 加档不改权重 = 静默把概率全挤到激进上
	t.eq(EndlessScript.weights_sum(false), 100, "普通间歇轮权重和 == 100")
	t.eq(EndlessScript.weights_sum(true), 100, "已持有激进时权重和 == 100")
	# 用户点名："和完美一样都是 10%"
	t.eq(int(UpgradeCard.TIER_WEIGHTS[R]), int(UpgradeCard.TIER_WEIGHTS[P]),
		"激进权重 == 完美权重（对照：改成 5 就是红的）")
	t.eq(int(UpgradeCard.TIER_WEIGHTS[R]), 10, "激进 == 10%")
	t.eq(int(UpgradeCard.TIER_WEIGHTS[B]), 30, "基础 == 30%（不能被动过）")
	# ★ Q17：同一个 roll、只翻一个入参，结果必须不同
	t.eq(EndlessScript.pick_tier(0.85, false), P, "0.85 + 未持有 → 完美")
	t.eq(EndlessScript.pick_tier(0.85, true), A, "0.85 + 已持有 → 进阶（那 10% 原路还给进阶）")
	t.eq(EndlessScript.pick_tier(0.90, true), P, "0.90 + 已持有 → 完美（不再出激进）")
	t.eq(EndlessScript.pick_tier(0.9999, true), P, "0.9999 + 已持有 → 完美")


static func _radical(t: T) -> void:
	var R := UpgradeCard.Tier.RADICAL
	# ① 每类型的激进格非空 + 代价列非空 + id 形如 rad_*
	for ty in UpgradeCard.TYPE_COUNT:
		var pool := UpgradeCard.pool_of(ty, R)
		t.ok(pool.size() > 0, "%s 的激进格非空" % UpgradeCard.TYPE_NAMES[ty])
		for c in pool:
			t.ok(c.cost != "", "%s 有代价列（非空）" % c.id)
			t.ok(c.id.begins_with("rad_"), "%s 的 id 形如 rad_*" % c.id)
			t.ok(c.line != "", "%s 有收益说明" % c.id)
	# ②-a 已持有 ⇒ 连喂 200 次，激进产出数 == 0
	var hit_locked := 0
	var hit_open := 0
	for i in 200:
		var roll := float(i) / 200.0
		if EndlessScript.pick_tier(roll, true) == R:
			hit_locked += 1
		if EndlessScript.pick_tier(roll, false) == R:
			hit_open += 1
	t.eq(hit_locked, 0, "②-a 已持有激进 ⇒ 200 次抽取里激进产出 == 0")
	# ②-b 负对照：未持有时同一批 roll **必须**有激进产出
	t.gt(hit_open, 0, "②-b 负对照：未持有时同一批 roll 里有激进（同一序列、只翻一个入参）")
	# ②-c "曾出现"不算 —— 判据是"已持有"
	var only_seen: Array = []
	var held: Array = [UpgradeCard.pool_of(0, R)[0]]
	t.not_ok(EndlessScript.player_has_radical(only_seen), "②-c 只见过没选 ⇒ 不算持有")
	t.ok(EndlessScript.player_has_radical(held), "②-c 拿在手里 ⇒ 算持有")
	t.eq(EndlessScript.pick_tier(0.95, EndlessScript.player_has_radical(only_seen)), R,
		"②-c 只见过 ⇒ 后面还能抽到激进")
	t.eq(EndlessScript.pick_tier(0.95, EndlessScript.player_has_radical(held)),
		UpgradeCard.Tier.PERFECT, "②-c 已持有 ⇒ 抽到的是完美（整档消失）")
	# ④ 三个"归零代价"装上后逐位读得到
	var p := SuitProfile.by_id(PENELOPE)
	_find(UpgradeCard.Type.ARMOR, R, "rad_a1").apply.call(p)
	t.near(p.get(&"_ifield_hp"), 0.0, 1e-9, "④ R-A1『弃盾』⇒ I 立场 == 0")
	var q := SuitProfile.by_id(PENELOPE)
	_find(UpgradeCard.Type.MECH, R, "rad_m3").apply.call(q)
	t.eq(q.has_missiles, false, "④ R-M3『弃浮游』⇒ has_missiles == false")
	var r := SuitProfile.by_id(PENELOPE)
	_find(UpgradeCard.Type.FIRE, R, "rad_f1").apply.call(r)
	t.eq(r.rifle_count, 0, "④ R-F1『弃枪从刃』⇒ rifle_count == 0")


static func _pool(t: T) -> void:
	var cells := 0
	var ids := {}
	for ty in UpgradeCard.TYPE_COUNT:
		for tier in UpgradeCard.TIER_COUNT:
			var pool := UpgradeCard.pool_of(ty, tier)
			cells += 1
			var label := "%s·%s" % [UpgradeCard.TYPE_NAMES[ty], UpgradeCard.TIER_NAMES[tier]]
			t.ok(pool.size() > 0, "%s 格子非空（%d 张）" % [label, pool.size()])
			for c in pool:
				t.ok(c.apply.is_valid(), "%s 的 apply 非 null" % c.id)
				t.ok(c.land != "", "%s 有落点" % c.id)
				t.ok(c.name != "", "%s 有芯片名" % c.id)
				t.ok(c.line != "", "%s 有一行说明" % c.id)
				t.eq(c.type, ty, "%s 的类型归属正确" % c.id)
				t.eq(c.tier, tier, "%s 的品质归属正确" % c.id)
				if tier != UpgradeCard.Tier.RADICAL:
					ids[c.id] = true
	t.eq(cells, UpgradeCard.TYPE_COUNT * UpgradeCard.TIER_COUNT, "格子数 == 20（5 类型 × 4 品质）")
	# ② 同一类型、同一品质内**不许出现两行同落点**（§5.4.5.5 / Q13）
	for ty in UpgradeCard.TYPE_COUNT:
		var seen := {}
		for c in UpgradeCard.pool_of(ty, UpgradeCard.Tier.ADVANCED):
			t.not_ok(seen.has(c.land), "%s 内落点 %s 不重复" % [UpgradeCard.TYPE_NAMES[ty], c.land])
			seen[c.land] = true
	# ③ 激进那几格的 id 与其它格**零重叠**
	for ty in UpgradeCard.TYPE_COUNT:
		for c in UpgradeCard.pool_of(ty, UpgradeCard.Tier.RADICAL):
			t.not_ok(ids.has(c.id), "激进 %s 的 id 与普通格零重叠" % c.id)


static func _pool_src(t: T) -> void:
	var src := FileAccess.get_file_as_string("res://scripts/data/suit_profile.gd")
	t.ok(src.length() > 0, "读得到 suit_profile.gd 源码")
	for c in UpgradeCard.all_cards():
		if c.land.begins_with("radical:"):
			continue
		t.ok(src.contains("var " + c.land),
			"落点 %s（%s）在 SuitProfile 上真实存在" % [c.land, c.id])


static func _ammo(t: T) -> void:
	# 本作弹药全部无限（§5.4.5.1 三条铁证）⇒ 卡面文案卖"补弹/省弹"就是卖一个不存在的成本
	var banned := ["补弹", "省弹", "加弹药", "弹药 +", "弹药+", "回 1 发", "回1发", "满弹"]
	for c in UpgradeCard.all_cards():
		var blob := c.name + "｜" + c.line + "｜" + c.cost
		for b in banned:
			t.not_ok(blob.contains(b), "%s 的文案不含『%s』" % [c.id, b])
	# 负对照：确认这套扫描**真的能红**（拿一条真含禁词的假文案试）
	var fake := "击杀回 1 发"
	var hit := false
	for b in banned:
		if fake.contains(b):
			hit = true
	t.ok(hit, "负对照：把『击杀回 1 发』塞回卡池 ⇒ 本分节必须红")


static func _heal(t: T) -> void:
	var armor := UpgradeCard.pool_of(UpgradeCard.Type.ARMOR, UpgradeCard.Tier.ADVANCED)
	var ids := {}
	for c in armor:
		ids[c.id] = true
	t.ok(ids.has("rep_packs") or ids.has("rep_frac") or ids.has("rep_time"),
		"HEAL：A7/A8/A9 至少一条在池中")
	# 三张都必须是"扩展既有修复包体系"，落点是那三个字段而不是新造
	t.ok(ids.has("rep_packs"), "A7『修复包增备』在池中（落点 repair_packs）")
	t.ok(ids.has("rep_frac"), "A8『修复效率』在池中（落点 repair_fraction）")
	t.ok(ids.has("rep_time"), "A9『快修通道』在池中（落点 repair_time）")
	# 负对照：起点改成 0 ⇒ 修完仍是 0
	var p := SuitProfile.by_id(XI)
	var saves := p.repair_packs
	p.repair_packs = 0
	_find(UpgradeCard.Type.ARMOR, UpgradeCard.Tier.BASIC, "rep_packs").apply.call(p)
	t.eq(p.repair_packs, 4, "rep_packs 是**绝对置值**（0 → 4），不是相对加")
	p.repair_packs = saves


static func _wave(t: T) -> void:
	var mp := EndlessScript.minor_pool()
	var ap := EndlessScript.ace_pool()
	t.eq(mp.size(), 4, "小波池 4 台（古斯塔夫 + 三台梅萨）")
	t.eq(ap.size(), 5, "强敌波池包含最终决战柯西和灵格斯特装型")
	t.ok(ap.has(SuitProfile.Id.REGZ_CUSTOM), "灵格斯特装型进入强敌波池")
	for m in ap:
		t.not_ok(mp.has(m), "两池交集为空（ACE 不会出现在小波里）")
	t.ok(EndlessScript.is_ace_wave(5), "第 5 波是强敌波")
	t.ok(EndlessScript.is_ace_wave(10), "第 10 波是强敌波")
	t.not_ok(EndlessScript.is_ace_wave(4), "第 4 波不是强敌波")
	t.not_ok(EndlessScript.is_ace_wave(0), "第 0 波（未开局）不是强敌波")
	# 阵容只从对应池里取
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261008
	for n in [1, 2, 3, 4, 5, 9, 10]:
		var suits := EndlessScript.wave_suits(n, 0.0, rng)
		t.eq(suits.size(), EndlessScript.wave_count_of(n, 0.0), "第 %d 波台数 == wave_count_of" % n)
		var src_pool: Array[int] = ap if EndlessScript.is_ace_wave(n) else mp
		for s in suits:
			t.ok(src_pool.has(s), "第 %d 波只从对应池里取（%d）" % [n, s])


static func _wave_gustav(t: T) -> void:
	var g := SuitProfile.by_id(GUSTAV)
	t.gt(g.rifle_count, 0, "GUSTAV00 走武装版（rifle_count > 0，不是靶机版）")
	t.gt(g.vulcan_ammo, 0, "GUSTAV00 有火神炮弹（不是靶机版）")


static func _enemy_scale(t: T) -> void:
	t.eq(EndlessScript.enemy_step(0.0), 0, "t=0 ⇒ 0 档")
	t.eq(EndlessScript.enemy_step(299.9), 0, "t=299.9 ⇒ 0 档")
	t.eq(EndlessScript.enemy_step(300.0), 1, "t=300.0 ⇒ 1 档")
	t.eq(EndlessScript.enemy_step(599.9), 1, "t=599.9 ⇒ 1 档")
	t.eq(EndlessScript.enemy_step(600.0), 2, "t=600.0 ⇒ 2 档")
	var eps := 1e-6
	t.near(EndlessScript.enemy_damage_mult(299.9), 1.000, eps, "乘算：t=299.9 ⇒ ×1.000")
	t.near(EndlessScript.enemy_damage_mult(300.0), 1.100, eps, "乘算：t=300.0 ⇒ ×1.100")
	t.near(EndlessScript.enemy_damage_mult(599.9), 1.100, eps, "乘算：t=599.9 ⇒ ×1.100")
	t.near(EndlessScript.enemy_damage_mult(600.0), 1.210, eps, "乘算：t=600.0 ⇒ ×1.210（1.1²）")
	# Q10：只涨伤害 ⇒ 耐久恒 1.0
	t.near(EndlessScript.enemy_hull_mult(3600.0), 1.0, eps, "Q10 只涨伤害：耐久倍率恒 1.0")
	# 非演习模式恒 1.0 的语义：0 档就是 1.0
	t.near(EndlessScript.enemy_reinforce(0.0), 1.0, eps, "t=0 ⇒ reinforce == 1.0（非演习模式逐位不变）")


static func _enemy_count(t: T) -> void:
	t.eq(EndlessScript.minor_count(1, 0.0), 2, "第 1 波、t=0 ⇒ 2 架")
	t.eq(EndlessScript.minor_count(1, 300.0), 3, "每过一个 300 s 恰好 +1")
	t.eq(EndlessScript.minor_count(1, 600.0), 4, "再过一个 300 s 再 +1")
	t.eq(EndlessScript.minor_count(4, 0.0), 3, "波次项：int(4/3) = 1 ⇒ 2+1 = 3")
	t.eq(EndlessScript.minor_count(99, 100000.0), EndlessScript.WAVE_MINOR_MAX,
		"软上限生效（16），不再增长")
	t.ok(EndlessScript.ace_count(5, 0.0) >= 1, "强敌波至少 1 台 ACE")


static func _bonus(t: T) -> void:
	t.eq(EndlessScript.bonus_picks(0.0), 1, "<15 min ⇒ 选 1 张")
	t.eq(EndlessScript.bonus_picks(899.9), 1, "899.9 s ⇒ 选 1 张")
	t.eq(EndlessScript.bonus_picks(900.0), 2, "900.0 s ⇒ 选 2 张")
	t.eq(EndlessScript.bonus_picks(1199.9), 2, "1199.9 s ⇒ 选 2 张")
	t.eq(EndlessScript.bonus_picks(1200.0), 3, "1200.0 s ⇒ 选 3 张")
	t.ok(EndlessScript.is_bonus_wave(5), "第 5 波清空后是奖励轮")
	t.not_ok(EndlessScript.is_bonus_wave(4), "第 4 波清空后不是奖励轮")
	# 奖励轮**强制完美**，跳过抽取
	t.eq(EndlessScript.tier_for(5, 0.0, false), UpgradeCard.Tier.PERFECT,
		"奖励轮：roll=0.0 也给完美（不参与抽取）")
	t.eq(EndlessScript.tier_for(5, 0.9999, false), UpgradeCard.Tier.PERFECT,
		"奖励轮：roll=0.9999 也给完美（激进不给保底）")
	t.eq(EndlessScript.tier_for(4, 0.0, false), UpgradeCard.Tier.BASIC,
		"非奖励轮：正常走抽取")


static func _intermission(t: T) -> void:
	t.near(EndlessScript.INTERMISSION_BASE, 10.0, 1e-9, "间歇轮基础 == 10.0 s（用户逐字）")
	t.near(EndlessScript.CLEARING_SECS, 1.2, 1e-9, "收尾过渡 == 1.2 s")
	# ⚠️ 宽限**必须非零**：按键是离散事件，两帧之间必然"没按"。
	# 取 0 = 倒计时永远在走，"操作时暂停"整条规则等于没写。
	t.gt(EndlessScript.OPERATE_GRACE, 0.0, "★ 操作宽限 > 0（= 0 会让「操作时暂停」形同虚设）")

	# ───── ① 倒计时的纯减法（喂边界值，不起场景）─────
	t.near(EndlessScript.tick_remaining(10.0, 6.0, false), 4.0, 1e-9,
		"不操作 ⇒ 剩余 -= delta")
	t.near(EndlessScript.tick_remaining(10.0, 6.0, true), 10.0, 1e-9,
		"★ 操作中 ⇒ 剩余**原样**返回（绝不出现「正在看卡，时间到了被强制关掉」）")
	t.near(EndlessScript.tick_remaining(1.0, 5.0, false), 0.0, 1e-9,
		"减到 0 就停住，不会变成负数")

	# ───── ② `operating` 的判据是 `idle`，不是"这一帧按了没" ─────
	var dt := 1.0 / 60.0
	var g := EndlessScript.OPERATE_GRACE
	var s0: Dictionary = EndlessScript.intermission_step(10.0, dt, false, 0.0, g, 0, 3)
	t.ok(not bool(s0["operating"]),
		"★ 起点钉在宽限值本身 ⇒ 开局**不**暂停（起点写 0 会白送每轮 0.6 s）")
	var s1: Dictionary = EndlessScript.intermission_step(10.0, dt, true, 0.0, 5.0, 0, 3)
	t.ok(bool(s1["operating"]), "按下的那一帧立刻算「正在操作」（`idle` 被清零）")
	# ⚠️ 分界要**算上这一帧的 `delta`**：`intermission_step()` 先做
	# `idle = idle + delta` 再判 `operating` —— 因为宽限是"距**上一次按键**过了多久"，
	# 而"上一次按键"到这一帧之间已经过了一个 `delta`。少算这一格，
	# 判据量的就是"上一帧的状态"，两种写法在真机上差 16 ms、在边界上差一整格。
	var s2: Dictionary = EndlessScript.intermission_step(10.0, dt, false, 0.0,
		g - dt - 1e-6, 0, 3)
	t.ok(bool(s2["operating"]), "宽限之内（含这一帧的 delta）⇒ 仍在操作、倒计时暂停")
	var s3: Dictionary = EndlessScript.intermission_step(10.0, dt, false, 0.0, g - dt, 0, 3)
	t.ok(not bool(s3["operating"]), "……正好越过 ⇒ 恢复递减（同一个 delta，只挪 `idle` 一格）")

	# ───── ③ §7.2 边界表第 1 行：一直不动 ⇒ 到点自动选**焦点那张** ─────
	var left := EndlessScript.INTERMISSION_BASE
	var secs := 0.0
	var idle := g
	var focus := 1
	var expired_at := -1
	var auto := -1
	for k in 900:
		var st: Dictionary = EndlessScript.intermission_step(left, dt, false, secs, idle,
			focus, 3)
		left = float(st["left"])
		secs = float(st["secs"])
		idle = float(st["idle"])
		if bool(st["expired"]):
			expired_at = k
			auto = int(st["auto"])
			break
	t.gt(float(expired_at), 0.0, "一直不动 ⇒ **会**到点（不是永远停在 10 s）")
	t.eq(auto, focus, "★ 到点自动选的就是**当前焦点那张**（不惩罚、不阻塞）")
	t.near(secs, 0.0, 1e-9, "一直不动 ⇒ 一秒都没「暂停掉」（`secs` 是回补账，不是操作时间）")
	t.near(left, 0.0, 1e-9, "到点时剩余归零")
	# 到点那一帧即使焦点越界（手牌短了），也必须给一个**合法**下标 ——
	# 给 −1 的话 main 会走去 `_finish_endless_round()`，奖励轮里就"少拿一张"。
	var sx: Dictionary = EndlessScript.intermission_step(0.0, dt, false, 0.0, g, 9, 3)
	t.eq(int(sx["auto"]), 2, "焦点越界 ⇒ `auto` 被 clamp 回最后一张（不是 −1）")

	# ───── ④ §7.2 边界表第 2 行：一直动手不选 ⇒ **不设上限** ─────
	left = EndlessScript.INTERMISSION_BASE
	secs = 0.0
	idle = 0.0
	var ever_expired := false
	for k in 1200:
		var sy: Dictionary = EndlessScript.intermission_step(left, dt, true, secs, idle,
			focus, 3)
		left = float(sy["left"])
		secs = float(sy["secs"])
		idle = float(sy["idle"])
		if bool(sy["expired"]):
			ever_expired = true
	t.ok(not ever_expired, "★ 一直动手 ⇒ 20 s 里**一次都没**到点（不设操作时长上限）")
	t.near(left, EndlessScript.INTERMISSION_BASE, 1e-6, "一直动手 ⇒ 剩余时间一格不掉")
	t.gt(secs, 15.0, "这 20 s 全记在「待回补」的账上（选定时要还回去）")

	# ───── ⑤ 回补（读法 A）：暂停掉多少就还多少 ─────
	t.near(EndlessScript.refund_time(4.0, 2.5), 6.5, 1e-9, "回补 = 剩余 + 这一段操作秒数")
	t.near(EndlessScript.refund_time(4.0, -1.0), 4.0, 1e-9,
		"负账不吃（防御式：真出现负值时不能倒扣玩家时间）")
	# 完整链路：操作 3 s 后选定 ⇒ 剩余**比没操作时多 3 s**
	left = EndlessScript.INTERMISSION_BASE
	secs = 0.0
	idle = g
	for k in 180:
		var sz: Dictionary = EndlessScript.intermission_step(left, dt, true, secs, idle, 0, 3)
		left = float(sz["left"])
		secs = float(sz["secs"])
		idle = float(sz["idle"])
	t.near(secs, 3.0, 1e-3, "操作 3 s ⇒ 账上正好 3 s")
	t.near(EndlessScript.refund_time(left, secs), 13.0, 1e-3,
		"★ 选定 ⇒ 剩余回到 13 s（**比基础 10 s 还多** —— 这是读法 A 的正常表现，绘制侧必须 clamp）")

	# ───── ⑥ 焦点循环（3 张上"到头停住"等于按键坏了）─────
	t.eq(EndlessScript.cycle_focus(2, 3, 1), 0, "★ 最后一张再往后 ⇒ 回绕到第 1 张（不是停住）")
	t.eq(EndlessScript.cycle_focus(0, 3, -1), 2, "第 1 张往前 ⇒ 回绕到最后一张")
	t.eq(EndlessScript.cycle_focus(1, 3, 0), 1, "step = 0 ⇒ 不动")
	t.eq(EndlessScript.cycle_focus(0, 0, 1), 0, "手牌为空 ⇒ 返回 0（**不给负下标**）")

	# ───── ⑦ 轮型 / 张数 / 品质 ─────
	t.eq(EndlessScript.round_phase(4), EndlessScript.Phase.INTERMISSION, "第 4 波清空 ⇒ 普通间歇轮")
	t.eq(EndlessScript.round_phase(5), EndlessScript.Phase.BONUS, "第 5 波（强敌波）清空 ⇒ **奖励轮**")
	t.eq(EndlessScript.round_phase(10), EndlessScript.Phase.BONUS, "第 10 波同上（与 `is_ace_wave` 同周期）")
	t.eq(EndlessScript.round_picks(4, 1200.0), 1,
		"★ 普通轮**恒** 1 张 —— 哪怕局内时间早就过了三张的门槛")
	t.eq(EndlessScript.round_picks(5, 899.9), 1, "奖励轮 · 14:59.9 ⇒ 1 张")
	t.eq(EndlessScript.round_picks(5, 900.0), 2, "奖励轮 · 15:00.0 ⇒ 2 张（边界含等号）")
	t.eq(EndlessScript.round_picks(5, 1199.9), 2, "奖励轮 · 19:59.9 ⇒ 仍是 2 张")
	t.eq(EndlessScript.round_picks(5, 1200.0), 3, "奖励轮 · 20:00.0 ⇒ 3 张")
	# 奖励轮**强制完美**：三个不同的 roll（含必然抽到 BASIC / ADVANCED 的那两段）都得 PERFECT
	for roll: float in [0.0, 0.31, 0.79, 0.99]:
		t.eq(EndlessScript.tier_for(5, roll, false), UpgradeCard.Tier.PERFECT,
			"★ 奖励轮 roll=%.2f ⇒ 恒 PERFECT（跳过抽取）" % roll)
	t.eq(EndlessScript.tier_for(4, 0.0, false), UpgradeCard.Tier.BASIC,
		"负对照：**普通轮**同一个 roll 走正常抽取 ⇒ BASIC")

	# ───── ⑧ 这一轮收没收 ─────
	t.ok(EndlessScript.round_done(1, 1, 3), "拿满 ⇒ 收")
	t.ok(EndlessScript.round_done(0, 1, 0),
		"★ 手牌空 ⇒ **也必须收**（这是「卡死在间歇轮里」唯一的兜底出口）")
	t.ok(not EndlessScript.round_done(0, 3, 2), "奖励轮还差两张、手牌还有 ⇒ 不收")
	t.ok(EndlessScript.round_done(0, 0, 3), "want = 0 ⇒ 立刻收（不空转）")


## ★63-24：间歇轮的**源码接线**（面板与状态机都接上了没有）。
##
## ⚠️ 这一节存在的理由与 `NO_WIN` 的源码切片同一条：**行为测不出来的东西用源码钉**。
## 下面每一条在"没接上"的时候都有同一个症状 —— **测试全绿、游戏里少一块**：
##   · `_tick_endless()` 的 `CLEARING` 直接刷下一波 ⇒ 选卡面板永远不弹（旧版就是这样）；
##   · `_take_endless_card()` 少一句 `refresh_profile_stats()` ⇒ 装甲卡加血静默失效；
##   · HUD 只接了一条绘制路径 ⇒ 默认视角下看不到面板（切 F1 才出现）。
static func _intermission_wiring(t: T) -> void:
	var main_src := SuiteUiStyle._code("scripts/main.gd")
	var tick_round := SuiteMenuFrame._func_body(main_src, "func _tick_endless_round(")
	t.ok(tick_round.contains("EndlessScript.intermission_step("),
		"★ `_tick_endless_round()` 用的是**同一个** `intermission_step()`，不是它的副本")
	t.ok(tick_round.contains("_take_endless_card("), "……并且真的会去选卡")
	t.ok(tick_round.contains("_read_endless_round_input()"), "……并且真的读输入")

	# ① 旧版那条"直接刷下一波"必须已经撤掉
	var tick := SuiteMenuFrame._func_body(main_src, "func _tick_endless(")
	t.ok(tick.contains("_begin_endless_round("), "★ `CLEARING` 走完 ⇒ 开间歇轮")
	t.ok(not tick.contains("_spawn_endless_wave("),
		"★ 而**不再**直接刷下一波（这一行还在 = 选卡面板永远不弹，且测试全绿）")
	t.ok(tick.contains("Game.phase == Game.Phase.FIGHT"),
		"★ 开轮前先确认**这一局还活着**（收尾那 1.2 s 里被打死 ⇒ 开出来的轮永远走不动）")

	# ①b 鼠标闩要在"这一屏之外"的每一帧放平（否则下一轮第一下点击被吞）
	#
	# ⚠️ 数的是 `_endless_lmb_held =`（**赋值**，不含声明行的 `:=`）——
	# 两处写法本来就不同：`_process` 里直接赋 `Input.is_mouse_button_pressed(...)`，
	# 选卡那边赋的是它自己量好的局部变量 `lmb`。数"整句一样"会漏掉其中一处。
	t.eq(main_src.count("_endless_lmb_held ="), 2,
		"★ 鼠标闩有两个写入点：`_process` 里每帧放平 + 选卡时自己量边沿")
	var proc_body0 := SuiteMenuFrame._func_body(main_src, "func _process(")
	t.ok(proc_body0.contains("_endless_lmb_held = Input.is_mouse_button_pressed("),
		"……而且那个放平点就在 `_process` 里（`main` 是 `PROCESS_MODE_ALWAYS`，"
		+ "所以暂停期间也会被放到平）")

	# ② `_process` 的两条钟：顺序必须是先 `_tick_endless` 后 `_tick_endless_round`
	var proc_body := SuiteMenuFrame._func_body(main_src, "func _process(")
	var at_a := proc_body.find("_tick_endless(")
	var at_b := proc_body.find("_tick_endless_round(")
	t.gt(float(at_a), -1.0, "`_process()` 里调了波次钟")
	t.gt(float(at_b), -1.0, "`_process()` 里调了间歇轮钟")
	t.lt(float(at_a), float(at_b), "★ 波次钟在前 —— 否则「这一帧刚开的轮」要等下一帧才开始走")

	# ③ 选一张卡必须做齐三件事
	var take := SuiteMenuFrame._func_body(main_src, "func _take_endless_card(")
	t.ok(take.contains("Game.endless_owned_tier.append("),
		"★ 记账时**成对写品质**（只写 id 会让局内的高档卡静默退化成基础档）")
	t.ok(take.contains("EndlessScript.refund_time("), "★ 耗时回补（读法 A 的全部内容）")
	t.ok(take.contains("player.refresh_profile_stats()"),
		"★ 把新读数重抄进机体（少这一句 = 装甲卡的加血一个点都不生效）")
	t.ok(take.contains("_apply_endless_cards("), "……而且卡是**整批重算**的（幂等的正解）")
	t.ok(take.contains("round_done("), "……并且判了这一轮收没收")

	# ④ `_apply_endless_cards()` 不许再写死基础档
	var apply_body := SuiteMenuFrame._func_body(main_src, "func _apply_endless_cards(")
	t.ok(apply_body.contains("_owned_cards()"), "★ 按品质取卡走 `_owned_cards()`")
	t.ok(not apply_body.contains("Tier.BASIC"),
		"★ 里面**不再**出现 `Tier.BASIC`（写死 = 局内抽到的完美卡退化成基础档）")
	var owned := SuiteMenuFrame._func_body(main_src, "func _owned_cards(")
	t.ok(owned.contains("Game.endless_owned_tier"),
		"……而且真的读的是那个**平行数组**")

	# ⑤ 开局那三张的记账也必须成对
	var at_spawn := main_src.find("func spawn_round(")
	# ⚠️ 切片终点用"下一个 `func `"现找，**不写死某个函数名** ——
	# 写死的话那个函数一旦被挪到前面（`_leave_campaign_result` 就排在上面），
	# `find` 返回 −1，切片变成空串，两条断言**一起变绿**（假绿）。
	var at_next := main_src.find("\nfunc ", at_spawn + 1)
	var spawn_sect := main_src.substr(at_spawn, maxi(at_next - at_spawn, 0))
	t.ok(spawn_sect.contains("Game.endless_owned.append_array(")
		and spawn_sect.contains("Game.endless_owned_tier.append("),
		"★ `spawn_round()` 里两个数组是**同一条路上成对写**的")

	# ⑥ 转向系数：累乘的根因必须已经修掉（否则"局内每拿一张卡舵效 ×1.38"）
	var prof_body := SuiteMenuFrame._func_body(SuiteUiStyle._code("scripts/flight/flight_body.gd"),
		"func _apply_profile_to_flight(")
	t.ok(not prof_body.contains("*="),
		"★ `_apply_profile_to_flight()` 里**没有** `*=`（累乘会让舵效随调用次数翻倍）")
	t.ok(prof_body.contains("FlightModel.PITCH_RATE_BASE"),
		"★ 改成「基值 × `turn_scale`」的**赋值**（幂等）")
	var model_src := SuiteUiStyle._code("scripts/flight/flight_model.gd")
	for c: String in ["PITCH_RATE_BASE", "ROLL_RATE_BASE", "YAW_RATE_BASE"]:
		t.ok(model_src.contains("const " + c), "`FlightModel` 有常量 %s（基值的唯一真源）" % c)

	# ⑦ `refresh_profile_stats()` 必须在 FlightBody 上真的存在且读 profile
	var fb_src := SuiteUiStyle._code("scripts/flight/flight_body.gd")
	var refresh := SuiteMenuFrame._func_body(fb_src, "func refresh_profile_stats(")
	t.ok(refresh.contains("profile.hull_hp"),
		"`refresh_profile_stats()` 从 profile 重算上限（不是累乘）")
	t.ok(refresh.contains("_apply_profile_to_flight()"),
		"……顺带把飞行性能也重贴一次（「姿态喷口」那张卡才不是死卡）")

	# ⑧ HUD：**两条绘制路径都要接**（默认视角走的是第三人称那一条）
	var hud_src := SuiteUiStyle._code("scripts/ui/hud.gd")
	t.eq(hud_src.count("func _draw_endless_intermission("), 1, "面板只定义一次")
	# ⚠️ 数的是**带前导 tab 的那种**（调用点缩进一级）；定义行是顶层 `func`，不带 tab
	# ⇒ 这个数**正好等于调用次数**。直接数字符串的话定义行也被数进去（会多 1）。
	t.eq(hud_src.count("\t_draw_endless_intermission()"), 2,
		"★ `_draw_endless_intermission()` 在**两条**绘制路径里都被调用"
		+ "（只接 `_draw()` 的话，默认（第三人称）视角下永远看不到面板）")
	t.ok(SuiteMenuFrame._func_body(hud_src, "func _draw_third_person(")
		.contains("_draw_endless_intermission()"), "……第三人称那一条确实在里面")
	t.ok(SuiteMenuFrame._func_body(hud_src, "func intermission_hit(")
		.contains("intermission_layout("),
		"★ 鼠标命中共用 `intermission_layout()`（两个真源会让「看着点中了却没反应」）")
	t.ok(SuiteMenuFrame._func_body(hud_src, "func _draw_endless_intermission(")
		.contains("clampf("),
		"★ 倒计时条的比例**必须 clamp**（回补会把 `left` 顶到 `total` 之上）")

	# ⑨ 配色单源：菜单那一侧改成转调 `CardStyle`
	var cc := SuiteMenuFrame._func_body(SuiteUiStyle._code("scripts/ui/main_menu.gd"),
		"static func card_color(")
	t.ok(cc.contains("CardStyle.type_color("), "★ 菜单的 `card_color()` 转调 `CardStyle`")
	t.ok(not cc.contains("Color("),
		"★ 里面**不再**自己写颜色（有第二份真源就会出现「菜单一套色、局内另一套色」）")


## ★63-24：间歇轮面板的**版式**（纯函数 ⇒ 不必画像素）。
##
## 这一节盯的是"窗口小的时候会不会画到屏幕外"与"鼠标点得中点不中"：
## 两者在真机上都是**静默失败**（画到外面不报错，点不到也不报错）。
static func _intermission_layout(t: T) -> void:
	for v: Vector2 in [Vector2(1280, 720), Vector2(960, 540), Vector2(640, 480)]:
		var lay := FlightHUD.intermission_layout(v, 3)
		var cards: Array = lay["cards"]
		t.eq(cards.size(), 3, "三张卡就画三个框（%.0f×%.0f）" % [v.x, v.y])
		var ok_inside := true
		var ok_disjoint := true
		for i in cards.size():
			var r: Rect2 = cards[i]
			if r.position.x < 0.0 or r.end.x > v.x or r.position.y < 0.0 or r.end.y > v.y:
				ok_inside = false
			if r.size.x <= 0.0 or r.size.y <= 0.0:
				ok_inside = false
			for j in range(i + 1, cards.size()):
				if r.intersects(cards[j] as Rect2):
					ok_disjoint = false
		t.ok(ok_inside, "★ %.0f×%.0f：三张卡**都在窗口内**且尺寸为正" % [v.x, v.y])
		t.ok(ok_disjoint, "★ %.0f×%.0f：三张卡**两两不相交**" % [v.x, v.y])
		# 倒计时条在卡块**上方**、提示在卡块**下方** —— 三块不叠
		var bar: Rect2 = lay["bar"]
		t.lt(bar.end.y, (cards[0] as Rect2).position.y, "%.0f×%.0f：条在卡上面" % [v.x, v.y])
		t.lt((cards[0] as Rect2).end.y, float(lay["hint_y"]),
			"%.0f×%.0f：按键提示在卡下面" % [v.x, v.y])
		# 鼠标：每张卡的中心都必须命中**自己那一张**
		for i in cards.size():
			var c: Rect2 = cards[i]
			t.eq(FlightHUD.intermission_hit(v, 3, c.position + c.size * 0.5), i,
				"%.0f×%.0f：点第 %d 张的中心命中第 %d 张" % [v.x, v.y, i + 1, i + 1])
		# 负对照：卡块外、窗口正中央偏上（标题带）不该命中任何一张
		t.eq(FlightHUD.intermission_hit(v, 3, Vector2(v.x * 0.5, float(lay["title_y"]))), -1,
			"%.0f×%.0f：点在标题上不算选中任何一张" % [v.x, v.y])

	# 手牌为 0 时也**必须给一个槽**（返回空数组会让 `lay["cards"][0]` 在别处炸）
	t.eq((FlightHUD.intermission_layout(Vector2(1280, 720), 0)["cards"] as Array).size(), 1,
		"`count = 0` ⇒ 仍返回 1 个槽（调用方不会拿到空数组）")

	# 标题：奖励轮与普通轮必须是**两句不同的话**
	var a := FlightHUD.intermission_title(EndlessScript.Phase.INTERMISSION)
	var b := FlightHUD.intermission_title(EndlessScript.Phase.BONUS)
	t.ok(a != b, "★ 奖励轮的标题与普通轮不同（`%s` / `%s`）" % [a, b])
	# ⚠️ 比的是**去掉空格之后**的形式：标题是美术排版（`奖 励 轮 · 完 美`，
	# 与「演 习 终 止」同一种字距），直接 `contains("奖励")` 永远不成立 ——
	# 而那种"判据写错了所以一直红"最后往往被人改成删除判据。
	t.ok(b.replace(" ", "").contains("奖励轮"), "奖励轮那句明说「奖励轮」")

	# 倒计时读数：暂停中必须**明说**为什么条不动
	t.ok(FlightHUD.intermission_timer_text(5.0, true).contains("暂停"),
		"★ 操作中 ⇒ 读数里写明「暂停」（不写的话玩家以为卡住了）")
	t.ok(not FlightHUD.intermission_timer_text(5.0, false).contains("暂停"),
		"负对照：没在操作时不写")

	# 配色：四品质两两不同 / 五类型与菜单逐位一致
	var tiers := {}
	for k in UpgradeCard.TIER_COUNT:
		tiers[str(CardStyle.tier_color(k))] = true
	t.eq(tiers.size(), UpgradeCard.TIER_COUNT, "四档品质各有各的颜色（两两不同）")
	var same := true
	for ty in UpgradeCard.TYPE_COUNT:
		if CardStyle.type_color(ty) != MainMenu.card_color(ty):
			same = false
	t.ok(same, "★ `CardStyle.type_color()` 与 `MainMenu.card_color()` 逐位一致（转调真的接上了）")



static func _idempotent(t: T) -> void:
	var factory := SuitProfile.by_id(PENELOPE)
	var p := SuitProfile.by_id(PENELOPE)
	var cards: Array = [
		_find(UpgradeCard.Type.ARMOR, UpgradeCard.Tier.BASIC, "hull"),
		_find(UpgradeCard.Type.FIRE, UpgradeCard.Tier.ADVANCED, "rifle_dmg"),
		_find(UpgradeCard.Type.SABER, UpgradeCard.Tier.PERFECT, "saber_dmg"),
	]
	EndlessScript.apply_run(p, factory, cards)
	var a := EndlessScript.snapshot(p)
	EndlessScript.apply_run(p, factory, cards)
	EndlessScript.apply_run(p, factory, cards)
	var b := EndlessScript.snapshot(p)
	t.eq(str(a), str(b), "同一批卡连续施加 1 次与 3 次 ⇒ 字段逐位一致")
	# 且确实变了（不是"两边都没生效"）
	t.not_ok(str(a) == str(EndlessScript.snapshot(factory)), "卡确实生效了（快照与出厂值不同）")


static func _durability(t: T) -> void:
	var p := SuitProfile.by_id(XI)
	var before := p.hull_hp
	_find(UpgradeCard.Type.ARMOR, UpgradeCard.Tier.BASIC, "hull").apply.call(p)
	var r := p.hull_hp / before
	t.near(r, 1.10, 0.002, "装甲增厚基础卡 ⇒ hull_hp 比值**恰好 1.10**")
	t.not_ok(absf(r - 1.21) < 0.005, "**不是** 1.10²（setter 没被二次乘 —— §5.5 坑 1）")
	var q := SuitProfile.by_id(XI)
	var ib := q.ifield_hp
	_find(UpgradeCard.Type.ARMOR, UpgradeCard.Tier.ADVANCED, "ifield").apply.call(q)
	t.near(q.ifield_hp / ib, 1.28, 0.003, "立场扩容进阶卡 ⇒ ifield_hp 比值恰好 1.28（不是 1.28²）")


static func _no_leak(t: T) -> void:
	var enemy_before := EndlessScript.snapshot(SuitProfile.by_id(MESSER))
	var factory_xi_before := EndlessScript.snapshot(SuitProfile.xi())
	var p := SuitProfile.by_id(XI)
	for c in UpgradeCard.all_cards():
		if c.apply.is_valid():
			c.apply.call(p)
	# ① 静态工厂新实例逐位不变
	t.eq(str(EndlessScript.snapshot(SuitProfile.xi())), str(factory_xi_before),
		"施加全部卡后，SuitProfile.xi() 新实例逐位不变")
	# ② 敌方实例逐位不变（梅萨 M01 既是玩家可选机、也是敌机）
	t.eq(str(EndlessScript.snapshot(SuitProfile.by_id(MESSER))), str(enemy_before),
		"施加全部卡后，敌机实例（梅萨 M01）逐位不变")


static func _wiring(t: T) -> void:
	var sp := FileAccess.get_file_as_string("res://scripts/data/suit_profile.gd")
	var fb := FileAccess.get_file_as_string("res://scripts/flight/flight_body.gd")
	var los := FileAccess.get_file_as_string("res://scripts/combat/lock_on_system.gd")
	var pc := FileAccess.get_file_as_string("res://scripts/flight/player_controller.gd")
	var bc := FileAccess.get_file_as_string("res://scripts/combat/beam_cannon.gd")
	# 字段提升（§5.9.6 的 7 个 + repair_packs / repair_fraction / repair_time / max_locks）
	for f in ["funnel_per_shot", "player_saber_magnet", "player_saber_dash_time",
			"saber_sweep_radius", "saber_min_closing", "saber_miss_grace",
			"clash_cooldown", "beam_cannon_radius", "repair_packs",
			"repair_fraction", "repair_time", "max_locks"]:
		t.ok(sp.contains("var " + f), "SuitProfile 有字段 %s" % f)
	# ⚠️ 玩家那一支的**两处口径**都要落到新字段（漏一处 = 「吸附了却没提示」）
	t.ok(fb.contains("profile.player_saber_magnet"), "fb 的 saber_magnet_range() 走 profile")
	t.ok(pc.contains("profile.player_saber_magnet"), "player_controller 的吸附提示也走 profile")
	t.ok(not pc.contains("profile.saber_magnet_range"), "player_controller 里不再裸读旧字段")
	t.ok(fb.contains("func funnel_per_shot()"), "fb 有 funnel_per_shot() helper")
	t.ok(not fb.contains("mini(SuitProfile.MISSILE_PER_SHOT"), "fb 的 _funnel_plan 不再直读常量")
	t.ok(los.contains("var max_locks := MAX_LOCKS"), "LockOnSystem 把 MAX_LOCKS 提升为实例字段")
	t.ok(bc.contains("radius_value"), "BeamCannon.launch() 收 radius 形参")
	t.ok(fb.contains("profile.beam_cannon_radius"), "fb 发射大炮时传 profile.beam_cannon_radius")
	t.ok(fb.contains("repair_packs = profile.repair_packs"), "fb 取初值时从 profile 读修复包个数")
	t.ok(fb.contains("func repair_time_secs()"), "fb 的修复通道时长走 helper")


# ═══════════════════ NO_WIN：演习永不判胜 ═══════════════════

## 这一节钉的是设计 §10 + §4.3 点名的**最高风险处**。
##
## 演习**不走**挑战波次管线（`active_challenge` 恒为 `null`）⇒ `game.gd` 里那条
## 「还有没刷出来的波次时不许判胜」的守卫**第一个条件就不成立** ⇒
## 清空第一波的那一帧（场上恰好空场）会**直接弹胜利结算**。
##
## ⚠️ 行为测得到"结果"，**测不到"顺序"** —— 所以两条都要：
##   ① 行为：演习下一律 `FIGHT`；负对照换成王牌战**必须**判胜（证明求值真的跑了）；
##   ② 源码切片：守卫必须夹在判负**之后**、判胜**之前**（拦太早会连终止一起拦掉）。
static func _no_win(t: T) -> void:
	# 动 `Game` 全局状态 ⇒ 存还原（同 `suite_campaign` ⑪ 的先例）
	#
	# ⚠️ 还原一律走 `Game.set("字段", 值)` 而不是 `Game.player = ...`：
	# `player` / `active_mission` 这几个字段带**强类型**，从局部变量赋回去是
	# 一次 Variant → 具体类的赋值，静态检查会拦（而 `set()` 走的是动态那一层）。
	var keep_mode := Game.match_mode
	var keep_phase := Game.phase
	var keep_player = Game.player
	var keep_mission = Game.active_mission
	var keep_challenge = Game.active_challenge
	var keep_wave := Game.challenge_wave
	var probe := _ProbeBody.new()

	# ---- ⓪ 前提：演习局根本没有挑战对象
	#
	# 少了这一条，后面那几条就是在测**挑战那条守卫**，而不是新加的演习守卫。
	Game.reset()
	Game.match_mode = Game.MatchMode.ENDLESS
	t.ok(Game.active_challenge == null,
		"★ 演习局 `active_challenge` 恒为 `null` ⇒ 挑战那条守卫形同虚设（本节的由来）")

	# ---- ① 零敌机 + 玩家健在 ⇒ 不判胜
	Game.reset()
	Game.set_phase(Game.Phase.FIGHT)
	Game.player = probe
	Game.match_mode = Game.MatchMode.ENDLESS
	Game.recheck_end()
	t.eq(Game.phase, Game.Phase.FIGHT,
		"★ 演习：清空一波那一帧（场上零敌机）⇒ 不判胜（否则第一波清完就弹胜利结算）")
	Game.recheck_end()
	Game.recheck_end()
	t.eq(Game.phase, Game.Phase.FIGHT, "★ 反复求值也不会「晚一帧就赢」（幂等那一路照样拦住）")

	# ---- ② 负对照：同一个桩、同一时刻，**只把模式换成王牌战** ⇒ 必须判胜
	#
	# ⚠️ 少了这一条，① 在「求值根本没跑」或「所有人都不判胜」时**照样是绿的**。
	Game.match_mode = Game.MatchMode.VERSUS
	Game.recheck_end()
	t.eq(Game.phase, Game.Phase.WIN,
		"★ 负对照：同一个人 + 零敌机 + 换成王牌战 ⇒ 立刻判胜（① 不是「什么都没判」）")

	# ---- ③ 终止条件没被一起拦掉：玩家没了 ⇒ 照旧判负
	Game.reset()
	Game.set_phase(Game.Phase.FIGHT)
	Game.match_mode = Game.MatchMode.ENDLESS
	Game.player = null
	Game.recheck_end()
	t.eq(Game.phase, Game.Phase.LOSE,
		"★ 演习：玩家被击坠 ⇒ 照旧 LOSE（守卫拦的是「判胜」，不是「终止」）")

	# ---- ④ 源码切片：守卫的**位置**
	#
	# 行为看不到顺序：把守卫挪到最上面，①③ **一样绿**（判负也一起被拦）。
	# 而「玩家死了不判负」是本模式唯一终点 ⇒ 那是比原 bug 更严重的事故。
	var body := SuiteMenuFrame._func_body(
		FileAccess.get_file_as_string("res://scripts/autoload/game.gd"),
		"func _evaluate_end()")
	t.ok(body != "", "切得出 `_evaluate_end()` 的函数体")
	var at_lose := body.find("set_phase(Phase.LOSE)")
	var at_guard := body.find("if match_mode == MatchMode.ENDLESS:")
	var at_win := body.find("live_hostiles_of(player).is_empty()")
	t.ok(at_lose >= 0, "`_evaluate_end()` 里有判负那一条")
	t.ok(at_guard >= 0, "……也有演习的守卫")
	t.ok(at_win >= 0, "……也有判胜那一条")
	t.ok(at_guard > at_lose, "★ 守卫在判负**之后**（拦太早 = 玩家死了不判负）")
	t.ok(at_guard < at_win, "★ 守卫在判胜**之前**（这是它存在的全部理由）")
	t.ok(body.substr(at_guard, at_win - at_guard).contains("return"),
		"★ 守卫那一段里是 `return`（写了判断却忘了 return = 一行不生效的注释）")

	# ---- 还原
	Game.reset()
	Game.set("match_mode", keep_mode)
	Game.set_phase(keep_phase)
	Game.set("player", keep_player)
	Game.set("active_mission", keep_mission)
	Game.set("active_challenge", keep_challenge)
	Game.set("challenge_wave", keep_wave)
	# ⚠️ 桩机体**显式释放**：`free()` 而不是 `queue_free()` —— 它从没进过场景树，
	# 而本工程的测试跑在无头单帧里，deferred 的队列可能永远不执行（= 泄漏告警）。
	probe.free()


# ═══════════════════ RESET：局间归零 + 请求通道 ═══════════════════

## 这一批字段全是 `Game` 上的 autoload 变量 ⇒ **跨局是活的**。不清的话第二局开局
## 就带着上一局的波次号 / 已拿卡 / 敌机强化倍率，而画面看起来一切正常。
##
## 两个反直觉点各有一条断言：
##   ① `endless_enemy_reinforce` 是**钉回 1.0**，不是清零 —— 它是乘法因子，
##      0 会让敌机强化变成「完全不开火」；1.0 才等于「没有这个模式之前」。
##   ② `endless_pick_request` **故意不清** —— 链路是「菜单写请求 → `reset()`
##      → 消费」，清了 = 玩家开局自选的 3 张卡永远收不到（`tutorial_requested` 同款坑）。
static func _reset(t: T) -> void:
	# ---- ① 出厂的一组数（先 reset 一次记下来）
	Game.reset()
	var base := _endless_snapshot()

	# ---- ② 污染：把**每一个**字段都写上一个「上一局留下的值」
	_soil()

	# ---- ③ 再 reset ⇒ 与 ① 逐字段一致
	Game.reset()
	t.eq(str(_endless_snapshot()), str(base),
		"★ `reset()` 之后逐字段回到出厂值（快照全等）")
	# 逐项点名 —— 上面那条挂了之后，这一批告诉你**是哪一项**漏了
	t.eq(Game.endless_phase, 0, "`endless_phase` 归 0（IDLE）")
	t.eq(Game.endless_wave, 0, "`endless_wave` 归 0（第 1 波由 `spawn_endless()` 开）")
	t.near(Game.endless_elapsed, 0.0, 1e-9,
		"`endless_elapsed` 归 0.0（不清 ⇒ 下一局开局就在高档位）")
	t.eq(Game.endless_wave_remaining, 0, "`endless_wave_remaining` 归 0")
	t.eq(Game.endless_wave_total, 0, "`endless_wave_total` 归 0")
	t.eq(Game.endless_owned.size(), 0, "`endless_owned` 清空（不清 ⇒ 下一局白拿上一局的卡）")
	t.eq(Game.endless_hand.size(), 0, "`endless_hand` 清空")
	t.near(Game.endless_intermission_left, 0.0, 1e-9, "间歇轮倒计时归 0")
	t.near(Game.endless_intermission_total, 0.0, 1e-9, "间歇轮总时长归 0")

	# ---- ④ 唯一那个**乘法因子**是钉回 1.0，不是清零
	t.near(Game.endless_enemy_reinforce, 1.0, 1e-9,
		"★ `endless_enemy_reinforce` 钉回 **1.0**（不是写到 0）")
	t.ok(absf(Game.endless_enemy_reinforce) > 1e-9,
		"★ ……而且不是 0：0 会让敌机那一档变成「完全不开火」")
	t.near(Game.endless_enemy_reinforce, EndlessScript.enemy_reinforce(0.0), 1e-9,
		"★ ……正好等于「0 档」的倍率 ⇒ 与非演习模式**逐位相同**（判据 NO_TOUCH_OTHERS）")

	# ---- ⑤ 请求通道：**故意**跨局活着（真链路的四步全走一遍）
	#
	# 菜单 `_launch()` 写 `endless_pick_request` → `spawn_round()` 第一步 `reset()`
	#（它**必须**不清）→ `spawn_endless()` 落成 `endless_owned` 并清空请求。
	var req: Array[String] = ["hull", "rifle_dmg", "saber_dmg"]
	Game.endless_pick_request = req
	Game.reset()
	t.eq(Game.endless_pick_request.size(), 3,
		"★ `reset()` 故意**不清** `endless_pick_request`（清了 = 自选 3 张永远收不到）")
	t.eq(str(Game.endless_pick_request), str(req), "……而且内容一个字都没动")
	# 消费那一步（`main.spawn_round()` 里那三行）
	Game.endless_owned.clear()
	Game.endless_owned.append_array(Game.endless_pick_request)
	var empty: Array[String] = []
	Game.endless_pick_request = empty
	t.eq(Game.endless_owned.size(), 3, "…落地之后 `endless_owned` 收到 3 张")
	t.eq(Game.endless_pick_request.size(), 0, "…请求被消费掉（不会二次生效）")
	Game.reset()
	t.eq(Game.endless_owned.size(), 0, "…再 reset 就干净了（局内即焚）")

	# ---- ⑥ 那 3 个 id 真的能按**基础档**找回来
	#
	# ⚠️ `UpgradeCard.by_id()` 的 `tier` 默认就是第一档 —— 正好是"开局自选"那一档。
	# 换个档找回来是**另一张卡**，而全程不报错（这正是 `by_id` 要带 `tier` 的理由）。
	for cid: String in req:
		var c := UpgradeCard.by_id(cid, UpgradeCard.Tier.BASIC)
		if c == null:
			continue
		t.eq(c.tier, UpgradeCard.Tier.BASIC, "`by_id(%s, BASIC)` 找回的是基础档那一张" % cid)
	# 菜单勾得出来的 id 一定找得回来（否则 `_apply_endless_cards()` 会静默丢卡）
	for c in MainMenu.endless_pool(SuitProfile.Id.XI):
		t.ok(UpgradeCard.by_id(c.id, UpgradeCard.Tier.BASIC) != null,
			"菜单能勾的 `%s` 一定找得回来（否则开局那一张静默消失）" % c.id)


# ═══════════════════ NOCARRY：局内即焚 ═══════════════════

## 「局内即焚」是设计给这一模式的标签（`mode_info()` 的 `tag2`）。它有两层意思：
##
##   ① **不写盘**：演习不碰 `user://campaign.cfg`（战役进度是**另一个模式**的账）；
##   ② **不外溢**：演习那一个全局乘法（`endless_enemy_reinforce`）不许渗进别的模式
##      —— 它乘进 `damage_mult` 是**唯一**的用法，而且不许并进 `reinforce`
##      （那个变量下面还会算 `max_hp` ⇒ 并进去 = 「敌人血也涨」，而 Q10 只涨伤害）。
##
## ⚠️ 本套件**没有 host、不建 main** ⇒ 跑不完整一局真场景。所以这里用
## 「把能调的都调一遍 + 逐字节核对存档 + 源码切片」三条一起兜（照 `suite_campaign` ⑪）。
static func _nocarry(t: T) -> void:
	# ---- ① 逐字节：把演习这一侧能调的都调一遍，`campaign.cfg` 一个字节都不许动
	var hero := SuitProfile.by_id(XI)
	var before := _file_hex(CampaignScript.PATH)
	var prog_before := str(Game.campaign_progress)
	Game.reset()
	_soil()
	EndlessScript.apply_run(hero, SuitProfile.by_id(XI), UpgradeCard.basic_pool(hero))
	for c in UpgradeCard.all_cards():
		if c.apply.is_valid():
			c.apply.call(hero)
	Game.reset()
	t.eq(_file_hex(CampaignScript.PATH), before,
		"★ 演习这一圈跑完，`user://campaign.cfg` **逐字节不变**（演习不写战役档）")
	t.eq(str(Game.campaign_progress), prog_before,
		"★ ……内存里的 `campaign_progress` 也一个字段都没动")

	# ---- ② 源码切片：演习那一节里**没有任何「写账」的动作**
	#
	# `_code()` 会先剥掉整行注释与行尾注释 ⇒ 命中的一定是**真代码**，不是说明文字。
	var main_src := SuiteUiStyle._code("scripts/main.gd")
	var at_a := main_src.find("func spawn_endless(")
	var at_b := main_src.find("static func versus_opponent_of(")
	t.ok(at_a >= 0 and at_b > at_a, "切得出 `main.gd` 的演习那一节")
	var sect := main_src.substr(at_a, at_b - at_a)
	for banned in ["_settle_campaign", "CampaignScript", "campaign_progress",
			"FileAccess", "user://", "store_string", "save_to_file"]:
		t.not_ok(sect.contains(banned),
			"★ 演习那一节里不含 `%s`（一局打完不留账）" % banned)
	# 负对照：那段切片的边界是真的（真"写账"的代码在同文件的别处，扫得到）
	t.ok(main_src.contains("_settle_campaign"),
		"★ 负对照：`_settle_campaign` 在 `main.gd` 里确实存在（②不是扫了个空字符串）")

	# ---- ③ 不外溢：那个全局乘法**只**乘进 `damage_mult`
	var ai_body := SuiteMenuFrame._func_body(
		SuiteUiStyle._code("scripts/ai/bandit_ai.gd"), "func _apply_difficulty()")
	t.ok(ai_body.contains("Game.endless_enemy_reinforce"),
		"`_apply_difficulty()` 读得到演习那一个倍率")
	var lines_hit := 0
	for raw in ai_body.split("\n"):
		var line := str(raw).strip_edges()
		if not line.contains("endless_mult"):
			continue
		lines_hit += 1
		t.ok(line.begins_with("damage_mult =") or line.begins_with("var endless_mult"),
			"★ 提到 `endless_mult` 的**只有**「声明」与「乘进 damage_mult」两种行（实际：%s）"
				% line)
	t.eq(lines_hit, 2,
		"★ `endless_mult` 在 `_apply_difficulty()` 里只出现 2 次（多一处就是并进了别的地方）")
	t.ok(ai_body.contains("damage_mult = difficulty.damage_mult * reinforce * endless_mult"),
		"★ 它就是乘进 `damage_mult`（不是并进 `reinforce` ⇒ 敌人耐久不动）")

	# ---- ④ 演习的「失败」照旧走 `_settle_campaign()`，但它在 `active_mission == null`
	#        （演习恒成立）时**第一行就早退**
	var settle := SuiteMenuFrame._func_body(main_src, "func _settle_campaign(")
	t.ok(settle.contains("if m == null:"), "`_settle_campaign()` 开头就判 `active_mission` 为空")
	var at_ret := settle.find("sally_result = {}")
	var at_book := settle.find("CS.settle(")
	t.ok(at_ret >= 0, "…为空时只清 `sally_result`")
	t.ok(at_book > at_ret,
		"★ ……早退在 `CS.settle()` **之前**（否则演习的败仗会记账进战役进度）")


# ═══════════════════ LAYOUT：模式页与配置页的版式 ═══════════════════

## 这一节挡的都是**静默**的形状：
##   · `step_index()` 漏分支 ⇒ 返回 −1 ⇒ 步骤条**一个点都不亮**（联机页的前车之鉴）；
##   · `nav_axis()` 与版式相反 ⇒ 按 W/S 没反应、按 A/D 才动（阵营页踩过）；
##   · `_list_geometry()` 漏分支 ⇒ 落 `Geo.NONE` ⇒ **鼠标完全点不到这一页**
##     （键盘照旧好用 ⇒ 最难查的那一种）。
static func _layout(t: T) -> void:
	# ---- ① 模式页：加了一组之后"两个数"又在 5 / 6
	t.eq(MainMenu.MODE_GROUPS.size(), 5, "模式页 5 行")
	t.eq(MainMenu.all_modes().size(), 6, "工程里 6 种模式")
	t.not_ok(MainMenu.MODE_GROUPS.size() == MainMenu.all_modes().size(),
		"★ 这两个数**不相等**了（分组之后拿模式数当行数用 ⇒ 最后一行排到面板外）")
	t.ok(MainMenu.all_modes().has(Game.MatchMode.ENDLESS), "★ 演习在入口表里")
	var grp := -1
	for i in MainMenu.MODE_GROUPS.size():
		if MainMenu.MODE_GROUPS[i]["modes"] == [Game.MatchMode.ENDLESS]:
			grp = i
	t.eq(grp, 2, "★ 演习**自成一组**（模式页第 3 行）⇒ 它在模式页上有自己的一行")
	t.not_ok(MainMenu.battle_modes().has(Game.MatchMode.ENDLESS),
		"★ 演习**不在**「对战模式」子页里（它不是一种对战形式）")

	# ---- ② 步骤条
	var m := MainMenu.new()
	t.ok(m.select_mode(Game.MatchMode.ENDLESS), "菜单能摆到演习")
	t.ok(m.endless_mode(), "…而且 `endless_mode()` 认得它")
	t.eq(m.step_labels().size(), 3, "★ 演习三步：选模式 → 选机体 → 改装配置")
	t.eq(str(m.step_labels()[2]), "③ 改装配置", "…第三步是「改装配置」")
	t.not_ok(str(m.step_labels()).contains("地图"),
		"★ 流程里没有「选地图」（地图由 `main._resolve_match()` 强制给一张）")
	t.not_ok(str(m.step_labels()).contains("难度"),
		"★ 也没有「选难度」（强度曲线只有「局内时间」一条轴）")
	m.set("stage", MainMenu.Stage.MODE)
	t.eq(m.step_index(), 0, "模式页 = 第 ① 步")
	m.set("stage", MainMenu.Stage.SUIT)
	t.eq(m.step_index(), 1, "机体页 = 第 ② 步")
	m.set("stage", MainMenu.Stage.ENDLESS)
	t.eq(m.step_index(), 2, "★ 配置页 = 第 ③ 步（返回 −1 的话步骤条一个点都不亮）")
	t.eq(m.step_count(), 3, "……而总步数就是 3（不是 5 —— 那是别的模式的标签表）")

	# ---- ③ 轴：配置页画的是竖排卡行 ⇒ 竖轴
	t.eq(MainMenu.nav_axis(MainMenu.Stage.ENDLESS), MainMenu.Nav.Y,
		"★ 配置页用竖轴（与 `_draw_endless_stage()` 的竖排行一致）")

	# ---- ④ 鼠标几何：不许落 `Geo.NONE`
	var g: Dictionary = m._list_geometry()
	t.not_ok(int(g["kind"]) == MainMenu.Geo.NONE,
		"★ 配置页有鼠标几何（落 `Geo.NONE` ⇒ 鼠标完全点不到这一页）")
	t.eq(int(g["count"]), m.endless_row_count(), "…几何里的行数 = 卡池 + 行动行")
	t.eq(m.endless_row_count(), m.endless_pool_now().size() + 1,
		"…最后那一行是「出击」行动行（勾卡与出击共用一个确认键）")

	# ---- ⑤ 卡池放不下就**分屏**（不是把行挤到面板外），且焦点行永远在窗口里
	#
	# ⚠️ 这一页**天然是长列表**（开局卡池 = 5 类型 × BASIC 档的全部词条），
	# 所以"全画得出来"是**错的期望** —— 该钉的是：
	#   ① 一屏 = `min(总行数, 放得下的行数)`（不是硬塞）；② 行块整体在内容区里；
	#   ③ **任意焦点行**都在窗口内（靠 `scroll_window()`）；④ 滚到底能按到「出击」。
	var n := m.endless_row_count()
	t.ok(n >= 2, "卡池非空 ⇒ 至少「一张卡 + 出击」两行")
	for view: Vector2 in [Vector2(1600, 900), Vector2(1280, 720), Vector2(1920, 1080)]:
		var fit := MainMenu.rows_that_fit(view, MainMenu.ENDLESS_ROW_H, MainMenu.ENDLESS_ROW_GAP)
		var met := MainMenu.list_metrics(view, n, MainMenu.ENDLESS_ROW_H,
			MainMenu.ENDLESS_ROW_GAP, MainMenu.ENDLESS_ROW_MAX)
		t.ok(fit >= 1, "%s：至少放得下一行" % view)
		t.eq(int(met["shown"]), mini(n, fit),
			"%s：一屏行数 = min(%d 行, 放得下的 %d 行)" % [view, n, fit])
		var bottom := MainMenu.list_bottom_y(0, int(met["shown"]), met)
		t.lt(bottom, MainMenu.content_bottom(view) + 0.001, "%s：行块底不越出内容区" % view)
		t.lt(bottom, MainMenu.hint_y(view), "%s：行块不压页脚提示行" % view)
		t.gt(float(met["top"]), MainMenu.PANEL_TOP - 0.001, "%s：行块顶不高于内容区顶" % view)
		# 焦点落到任意一行（含最后那一行「出击」）时都必须在可见窗口内
		for idx: int in [0, n >> 1, n - 1]:
			var win := MainMenu.scroll_window(n, idx, int(met["shown"]))
			t.ok(idx >= win.x and idx < win.x + win.y,
				"%s：焦点在第 %d 行时它落在窗口 [%d, %d) 里" % [view, idx, win.x, win.x + win.y])
		var win_last := MainMenu.scroll_window(n, n - 1, int(met["shown"]))
		t.ok(win_last.x + win_last.y >= n,
			"%s：滚到底时「出击」行动行在窗口内（勾满了却按不到出击 = 死胡同）" % view)

	# ---- ⑤b 长列表 ⇒ 绘制侧必须画滚动指示（不画 = 玩家不知道下面还有）
	t.ok(n > MainMenu.rows_that_fit(Vector2(1280, 720), MainMenu.ENDLESS_ROW_H,
		MainMenu.ENDLESS_ROW_GAP),
		"★ 卡池在 720 高的一屏里放不下（%d 行）⇒ 下面那条不是空转" % n)
	var draw_body := SuiteMenuFrame._func_body(
		SuiteUiStyle._code("scripts/ui/main_menu.gd"), "func _draw_endless_stage()")
	t.ok(draw_body.contains("_draw_scroll_indicator("),
		"★ 配置页画滚动指示（放不下时这是「下面还有」的唯一提示）")

	# ---- ⑥ 五类卡五种颜色（配色只有一份真源，不在绘制侧各写一遍）
	var cols := {}
	for ty in UpgradeCard.TYPE_COUNT:
		cols[str(MainMenu.card_color(ty))] = true
	t.eq(cols.size(), UpgradeCard.TYPE_COUNT,
		"★ 五类卡五种颜色（撞色 ⇒ 玩家分不清这是哪一类芯片）")

	# ---- ⑦ 勾选：满了不再接受新的 + 同一张再按一次 = 取消
	var ids: Array[String] = []
	for c in m.endless_pool_now():
		ids.append(c.id)
	t.ok(ids.size() >= MainMenu.ENDLESS_PICK_COUNT,
		"开局卡池至少 3 张（不足 3 张就永远出击不了 ⇒ 这一页是个死胡同）")
	t.eq(m.endless_picks.size(), 0, "开局没有勾选")
	for i in MainMenu.ENDLESS_PICK_COUNT:
		t.ok(m.endless_toggle(ids[i]), "勾上第 %d 张（%s）" % [i + 1, ids[i]])
	t.ok(m.endless_ready(), "★ 勾满 3 张 ⇒ 出击闸门打开")
	t.eq(m.endless_missing(), 0, "…页脚印「还差 0 张」")
	t.not_ok(m.endless_toggle(ids[MainMenu.ENDLESS_PICK_COUNT]),
		"★ 满了**不再接受新的**（不是顶掉一张 —— 顶掉哪一张没法解释给玩家听）")
	t.eq(m.endless_picks.size(), MainMenu.ENDLESS_PICK_COUNT, "…选择数没变")
	t.ok(m.endless_toggle(ids[0]), "同一张再按一次 = 取消")
	t.eq(m.endless_picks.size(), MainMenu.ENDLESS_PICK_COUNT - 1, "…选择数减 1")
	t.not_ok(m.endless_ready(), "…闸门重新关上")
	t.eq(m.endless_missing(), 1, "…页脚印「还差 1 张」")

	# ---- ⑧ 换机体 ⇒ 卡池换 ⇒ 勾选按 **id** 剔除
	#
	# ⚠️ 先证明"确实存在一张跨机体的卡"，**否则这一条是空转**（两台机池子一样就剔不掉东西）。
	var pen := _pool_ids(SuitProfile.Id.PENELOPE)
	var xi := _pool_ids(SuitProfile.Id.XI)
	var foreign := ""
	for cid: String in pen:
		if not xi.has(cid):
			foreign = cid
			break
	t.ok(foreign != "",
		"佩涅罗佩的池里有柯西装不上的（柯西没有大炮 ⇒ `viable_for` 过 `cannon_enabled`）")
	var lst := m.active_suit_list()
	var at_pen := lst.find(SuitProfile.Id.PENELOPE)
	var at_xi := lst.find(SuitProfile.Id.XI)
	t.ok(at_pen >= 0 and at_xi >= 0, "机体页同时列着佩涅罗佩与柯西")
	m.set("suit_index", at_pen)
	t.eq(m.selected_suit(), SuitProfile.Id.PENELOPE, "菜单摆到佩涅罗佩")
	m.endless_picks.clear()
	t.ok(m.endless_toggle(foreign), "在佩涅罗佩上勾上那张重炮卡")
	m.set("suit_index", at_xi)
	t.eq(m.selected_suit(), SuitProfile.Id.XI, "菜单摆到柯西")
	m.endless_prune_picks()
	t.not_ok(m.endless_has(foreign),
		"★ 换机体之后那张装不上的卡**被剔掉**（不剔 ⇒ 交给 main 一张这台机没有的卡，而 `by_id` 照样找得到）")
	t.ok(m.endless_index < m.endless_pool_now().size(),
		"…焦点行也被钳回卡池内（不然焦点停在「出击」上，玩家一按就出击了）")

	# ⚠️ 同 `NO_WIN`：`MainMenu` 实例从没进过场景树 ⇒ 用 `free()` 而不是 `queue_free()`，
	# 否则无头单帧里它会一直挂在 ObjectDB 上（退出时的泄漏告警）。
	m.free()


# ═══════════════════════════ 工具 ═══════════════════════════

static func _find(ty: int, tier: int, id: String) -> UpgradeCard:
	for c in UpgradeCard.pool_of(ty, tier):
		if c.id == id:
			return c
	return null


## 一局的演习状态快照（**只含 `Game` 上那些**，不含"请求通道"）。
##
## ⚠️ 字典的 `str()` 顺序 = 插入顺序 ⇒ 可以整串比对（`RESET` 分节要的就是"逐字段一致"）。
static func _endless_snapshot() -> Dictionary:
	return {
		"phase": Game.endless_phase,
		"wave": Game.endless_wave,
		"elapsed": Game.endless_elapsed,
		"remaining": Game.endless_wave_remaining,
		"total": Game.endless_wave_total,
		"owned": str(Game.endless_owned),
		"hand": str(Game.endless_hand),
		"im_left": Game.endless_intermission_left,
		"im_total": Game.endless_intermission_total,
		"reinforce": Game.endless_enemy_reinforce,
	}


## 把每一个 endless 局内字段都写上一个"上一局留下的值"（`RESET` 分节用）。
##
## ⚠️ 每一项都必须是**非出厂值**，否则"reset 生效了没有"这一问就问不出来。
static func _soil() -> void:
	var owned: Array[String] = ["hull", "rifle_dmg"]
	var hand: Array[String] = ["saber_dmg"]
	Game.match_mode = Game.MatchMode.ENDLESS
	Game.endless_phase = EndlessScript.Phase.INTERMISSION
	Game.endless_wave = 7
	Game.endless_elapsed = 123.5
	Game.endless_wave_remaining = 2
	Game.endless_wave_total = 3
	Game.endless_owned = owned
	Game.endless_hand = hand
	Game.endless_intermission_left = 4.5
	Game.endless_intermission_total = 10.0
	Game.endless_enemy_reinforce = 2.5


## `user://` 某个文件的十六进制全文（不存在 ⇒ `"<absent>"`）。
static func _file_hex(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "<absent>"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "<unreadable>"
	return f.get_buffer(f.get_length()).hex_encode()


## 某台机的"开局自选"基础卡池 id 集合（`LAYOUT` 分节的"换机体"那一条用）。
static func _pool_ids(suit_id: int) -> Dictionary:
	var out := {}
	for c in MainMenu.endless_pool(suit_id):
		out[c.id] = true
	return out


## 只实现 `Game.live_player()` 真正调用的那一个方法（照 `suite_campaign._ProbeBody`）。
##
## ⚠️ 不直接 `FlightBody.new()`：那个类在树外构造要带飞行模型 / 模型场景，
## 而 `NO_WIN` 分节只验「判胜那一条路」。
class _ProbeBody extends Node3D:
	func is_alive() -> bool:
		return true

	func is_hostile_to(_other: Node3D) -> bool:
		return false
