class_name SuiteMissionSpeed
extends RefCounted
## ★63-9 · D1「m02 的梅萨一直逃跑、追不上打不死」。
##
## 四段判据（对着设计文档 §3.1）：
##   ① 数据：m02 的 `enemy_speed_mult == 0.75`，**其余全部关卡（含字段默认值）逐位是 1.0**，
##      机型四件套一个字不动（不换机）。
##   ② 进攻欲望：本关那一波 `aggressive == true`（出场即 ATTACK）。
##   ③ 算式：复刻 `suit_profile.gd` 的速度函数 ⇒ 敌机极速 ≤ 玩家巡航 × 1.05，
##      且中/困难档加力接近速度 ≥ 380 m/s。
##   ④ 端到端：给一台真 `BanditAI` 走产品的 setter，`fm.max_speed` 必须真的降到 ×0.75，
##      且乘子写回 1.0 时**逐位**回到原值。
##
## ⚠️⚠️ **施工期实测修正（两处，都写在这里防止下一个人照着旧口径改回去）**
##
## **(1) m02 的玩家是「古斯塔夫 00 武装版」，不是靶机版。**
## 剧情关的玩家机走 `main.spawn_challenge()` 的 `SuitProfile.by_id(Game.active_suit)`，
## 而 `by_id(Id.GUSTAV00)` **默认给 `gustav00_armed()`**（`speed_scale 0.85`）——
## 靶机版（`gustav00()`，0.55）只有训练场显式索取。
## 设计文档 §3.1 把它写成了 0.55，于是那张对局表的**绝对速度全错**
##（554 / 832 / 765 应为 **856.8 / 1285.2 / 1182.384**）。
## ⚠️ 只有绝对值错了：**「敌机极速 = 玩家巡航 × 1.38」这个比例正好与 `speed_scale` 无关**
##（= `PLAYER_BOOST_MULT 1.5 × ENEMY_SPEED_CEILING_RATIO 0.92`），所以结论没变。
##
## **(2) 那条「三档难度下敌机极速完全相同」只对旧口径成立。**
## 天花板 `0.92 × 加力` 要**先咬住**敌机自己的上限才会出现"三档一致"：
##   · 玩家 0.55 时天花板 765.07 < 梅萨下限 927.36 ⇒ 三档都被咬 ⇒ 一致；
##   · 玩家 0.85 时天花板 1182.384 **>** 简单档的 927.36 ⇒ **简单档不被咬，三档不一致**。
## ⇒ 本套件按真口径断：现状 = **1.082 / 1.380 / 1.380** 倍巡航，
## 其中只有中等与困难两档真正"追不上"（简单档加力接近速度 357.8 本来就能追上）。
##
## ⚠️ 第三条口径：`player_top_speed()` / `enemy_top_speed_capped()` 返回的
## **已经是引擎速度域**（`suit_profile.gd` 原话：「2026-09-25 起这两个数**是实际速度**
## （已含 `SPEED_REAL_MULT`）」）⇒ 这里**不再乘 2.4**。
##
## 本关的绝对账（引擎速度域，出生间距用 `world.match_spawn_radius() * 0.85`）：
##   攻击间距 ≈ 46 575 × 0.85 = 39 588.75 m（DAVAO 的 `spawn_r`）
##   · 中等现状：39 588.75 / 102.816 ≈ **385 s**（6.4 分钟，追不上）
##   · 中等本关：39 588.75 / 398.412 ≈ **99 s**（1.7 分钟）
##   ⚠️ 这是**最坏情况**（敌机一直全速直逃）；实战里只有 EXTEND / EVADE 才踩满油门，
##   其余时候（SEEK ≤ 0.92 / ATTACK 不 boosting）⇒ 实际更快咬上。

const MS := preload("res://scripts/data/mission_script.gd")

const SUIT_GUSTAV := SuitProfile.Id.GUSTAV00
const SUIT_MESSER := SuitProfile.Id.MESSER_M01
const M02_MULT := 0.75
## DAVAO 的出击半径（`world_builder.gd` 的 `CITY_SHAPE[DAVAO].spawn_r` = 全局 `SPAWN_RADIUS`）。
const DAVAO_SPAWN_R := 46575.0
## 每一档的（现状敌机极速, 本关敌机极速），手算表 —— 与产品函数对账用。
const CAPPED_NOW := [927.36, 1182.384, 1182.384]
const CAPPED_NEW := [695.52, 886.788, 886.788]


static func run(t: T, _host: Node) -> void:
	t.suite("MissionSpeed / 数据：m02 专属乘子与不换机（D1）")
	_data(t)
	t.suite("MissionSpeed / 进攻欲望：出场即 ATTACK（D1）")
	_aggr(t)
	t.suite("MissionSpeed / 算式：追得上（D1）")
	_math(t)
	t.suite("MissionSpeed / 端到端：真 BanditAI 真的变慢（D1）")
	_runtime(t)


# ================================================================ ① 数据
static func _data(t: T) -> void:
	var m02: MS.Mission = MS.by_id("M02")
	t.eq(m02.enemy_speed_mult, M02_MULT, "m02 本关速度乘子 = 0.75（P5 拍板）")
	t.eq(MS.Mission.new().enemy_speed_mult, 1.0,
		"字段默认 1.0 —— 防「顺手把默认值改掉」一次放倒全部关卡")

	# ---- 其余关卡一格不动 ----
	var others := 0
	for m: MS.Mission in MS.all():
		if m.id == "M02":
			continue
		others += 1
		t.eq(m.enemy_speed_mult, 1.0, "%s 的速度乘子仍是 1.0（逐位不变）" % m.id)
	t.gt(float(others), 5.0, "确实遍历到了其余六关（%d 关，不是空循环）" % others)

	# ---- 不换机型（四件套一个字不动的可证伪版）----
	t.eq(m02.waves.size(), 1, "仍然只有一波")
	t.eq(m02.waves[0].count, 1, "仍然只出一架")
	t.eq(m02.waves[0].suit, SUIT_MESSER,
		"真正撒出来的那一台仍是梅萨（`waves[].suit` 才是真源，`Mission.enemy_suit` 只给简报）")
	t.eq(m02.enemy_suit, SUIT_MESSER, "简报上的敌机仍是梅萨")
	t.eq(m02.player_suit, SUIT_GUSTAV, "玩家机仍是古斯塔夫 00（速度账的另一半）")


# ================================================================ ② 进攻欲望
static func _aggr(t: T) -> void:
	var m02: MS.Mission = MS.by_id("M02")
	t.eq(m02.waves[0].aggressive, true,
		"m02 的梅萨出场就进入 ATTACK（用户要的「增强一点他的进攻欲望」）")
	t.eq(MS.DAVAO_INTERCEPT_SHAPE[0]["aggr"], true,
		"形状表里的 aggr 也是 true —— 两处不要各说一套（`main._spawn_wave()` 读的是 Wave）")
	# 负对照的静态版：把 aggr 写回 false ⇒ 上面两条同时红。
	# 这不是「顺手调数」能糊过去的：aggr 直接决定 `set_state(ATTACK)` 那一行跑不跑。


# ================================================================ ③ 算式
static func _math(t: T) -> void:
	# ⚠️ 走**产品那条路**：剧情关的玩家机就是 `by_id(GUSTAV00)`（= 武装版 0.85）。
	var player := SuitProfile.by_id(SUIT_GUSTAV)
	var enemy := SuitProfile.by_id(SUIT_MESSER)
	var boost := player.player_boost_speed()
	var cruise := player.player_top_speed()
	# ⚠️ 乘子**取自产品数据**（不是套件里再抄一个常量）——
	# 否则把 m02 的字段改回 1.0 时这一段会照样绿（判据没咬在产品路径上）。
	var mult: float = MS.by_id("M02").enemy_speed_mult
	t.near(mult, M02_MULT, 0.0000001, "算式用的乘子取自产品数据 m02 字段 = 0.75")

	# ---- (1) 先钉住「玩家是武装版」这条口径（否则整张表的绝对值会再次漂）----
	t.near(player.speed_scale, 0.85, 0.0005,
		"m02 玩家机 = 古斯塔夫 00 武装版（speed_scale 0.85，**不是**靶机的 0.55）")
	t.near(boost, 1285.2, 0.05, "武装版加力 = 420 × 1.5 × 0.85 × 2.4 = 1285.2")
	t.near(cruise, 856.8, 0.05, "武装版巡航 = 420 × 0.85 × 2.4 = 856.8")

	var levels := [Difficulty.Level.EASY, Difficulty.Level.NORMAL, Difficulty.Level.HARD]
	var tags := ["简单", "中等", "困难"]
	for i in 3:
		var d: Difficulty = Difficulty.make(int(levels[i]))
		var tag := str(tags[i])
		var capped_now: float = enemy.enemy_top_speed_capped(d.speed_mult, boost)
		var capped_new: float = capped_now * mult
		# 与手算表对账（防「算式本身被改了却没人发现」）
		t.near(capped_now, float(CAPPED_NOW[i]), 0.5, "[%s] 现状敌机极速（对账手算表）" % tag)
		t.near(capped_new, float(CAPPED_NEW[i]), 0.5, "[%s] 本关敌机极速（对账手算表）" % tag)
		# 现状：**都比玩家巡航快** —— 这就是「不按加力永远追不上」的根
		t.gt(capped_now / cruise, 1.0, "[%s] 现状：敌机比玩家巡航快（%.3f 倍）" % [tag, capped_now / cruise])
		# 判据 (a)：本关敌机极速 ≤ 玩家巡航 × 1.05
		t.lt(capped_new / cruise, 1.05, "[%s] 本关：降到 %.3f 倍巡航（< 1.05）" % [tag, capped_new / cruise])

	# ---- (2) 「有牙齿」：改动前这些**本来就是红的** ----
	for i in 3:
		var d: Difficulty = Difficulty.make(int(levels[i]))
		var before: float = enemy.enemy_top_speed_capped(d.speed_mult, boost)
		t.gt(before / cruise, 1.05,
			"★ 现状(%s) %.3f 倍巡航 > 1.05 ⇒ 判据(a) 本来是红的（改这个值真能变绿）" % [str(tags[i]), before / cruise])

	# ---- (3) 中/困难：真正追不上的那两档 ----
	var normal: Difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	var capped_n: float = enemy.enemy_top_speed_capped(normal.speed_mult, boost)
	var new_n: float = capped_n * mult
	var close_now: float = boost - capped_n
	var close_new: float = boost - new_n
	t.near(close_now, 102.816, 0.5, "中等现状：加力接近速度只有 102.8 m/s（**有牙齿**）")
	t.near(close_new, 398.412, 0.5, "中等本关：加力接近速度 398.4 m/s")
	t.gt(close_new, 380.0, "中等本关：加力接近速度 > 380 m/s")
	t.gt(close_new / close_now, 3.5, "中等本关：接近速度提到 %.2f 倍（> 3.5）" % (close_new / close_now))

	# ⚠️ 简单档不被天花板咬住（敌机自己的 927.36 < 天花板 1182.384）⇒
	# 它**本来就不是追不上**（加力接近速度 357.8）⇒ 改善只有 1.65 倍，这是几何事实。
	var easy: Difficulty = Difficulty.make(Difficulty.Level.EASY)
	var capped_e: float = enemy.enemy_top_speed_capped(easy.speed_mult, boost)
	t.near(boost - capped_e, 357.84, 0.5, "简单现状：加力接近速度 357.8（本来就能追上，只是慢）")
	t.gt(boost - capped_e * mult, 550.0, "简单本关：589.7 m/s（更宽裕）")

	# ---- 出生间距口径 ----
	var gap := DAVAO_SPAWN_R * 0.85
	t.near(gap, 39588.75, 0.05, "DAVAO 攻击间距 = 46 575 × 0.85 = 39 588.75 m")
	t.gt(gap / close_now, 300.0, "中等现状：纯追击最坏情况 ≈ %.0f s（6 分钟级，追不上）" % (gap / close_now))
	t.lt(gap / close_new, 150.0, "中等本关：纯追击最坏情况 ≈ %.0f s（1.7 分钟）" % (gap / close_new))


# ================================================================ ④ 端到端
static func _runtime(t: T) -> void:
	var enemy := SuitProfile.by_id(SUIT_MESSER)
	var ai := BanditAI.new()
	ai.profile = enemy
	ai.difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	ai._apply_top_speed()
	var base: float = ai.fm.max_speed

	t.gt(base, 0.0, "先拿到一台真 BanditAI 的基线极速（%.3f）" % base)

	ai.set_enemy_speed_mult(M02_MULT)
	var after: float = ai.fm.max_speed
	t.near(after, base * M02_MULT, 0.01,
		"产品那个 setter 真的把 top_speed 乘了 0.75（%.3f → %.3f）" % [base, after])
	t.lt(after, base, "而且真的变小了")

	# ⚠️ **必须逐位相等**：乘子 1.0 时 `x * 1.0 == x` —— 这就是
	# 「其余全部对局一格不动」的机械保证（那条 27 组合不变量表就靠它）。
	ai.set_enemy_speed_mult(1.0)
	t.eq(ai.fm.max_speed, base, "乘子写回 1.0 ⇒ max_speed 逐位回到原值（其余对局不变）")

	# 钳位：0 / 负数不许把敌机钉死在空中
	ai.set_enemy_speed_mult(0.0)
	t.gt(ai.fm.max_speed, 0.0, "乘子给 0 也被钳到 ≥0.01（敌机不会停在空中）")
	ai.set_enemy_speed_mult(-5.0)
	t.gt(ai.fm.max_speed, 0.0, "乘子给负数同样被钳住（不会翻向）")

	# ---- 接线：产品真的读了这个字段（否则它是死数据）----
	var main_src := _read("res://scripts/main.gd")
	t.eq(main_src.count("set_enemy_speed_mult"), 1,
		"`main._spawn_wave()` 里恰好一处调 set_enemy_speed_mult（多于一处 = 重复缩放）")
	var ai_src := _read("res://scripts/ai/bandit_ai.gd")
	t.eq(ai_src.count("top *= enemy_speed_mult"), 1,
		"`_apply_top_speed()` 里恰好一处乘子")
	t.eq(ai_src.count("func set_enemy_speed_mult"), 1, "setter 只有一个定义")

	ai.free()


static func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()
