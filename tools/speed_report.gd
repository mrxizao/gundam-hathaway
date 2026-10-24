extends SceneTree
## 机体「**实际 / 显示**」两域的速度报表。
##
## ## 为什么要有它（2026-09-25 两次提速时加的）
## 提速这件事的验收条件有**两半，而且是反向的**：
##   ① **实际**速度要涨（后台真的变快）；
##   ② **屏上**那个数不能变（HUD 的 KM/H、主菜单的「巡航 N m/s」）。
## 测试只能给「是 / 否」，说明不了「到底涨了多少」；手算的数又和代码里的符号脱钩
##（改一个 `speed_scale`，手算就过期了）。这个报表**直接读 `SuitProfile` 的返回值**，
## 所以它就是「代码此刻到底是多少」的凭证。
##
## ## 用法（提速前后各跑一次，把两份输出 diff 一下）
##     godot --headless --path . --script res://tools/speed_report.gd
##     输出是纯文本，直接重定向落盘即可 diff。
##
## ⚠️ 它**不是测试**（没有断言、也不进任何套件的台账）。要断言请去
## `suite_assist_drive` / `suite_flight` / `suite_round19`。
##
## ⚠️ 全脚本**只依赖 `SuitProfile`**（纯数据、不碰 autoload）。
## 尤其是刻意**不**去读 `WorldBuilder.SPAWN_RADIUS` —— `world_builder.gd` 引用
## `Settings` autoload，而 `--script` 独立模式里 autoload 不存在，直接引用会连带
## 编译失败、刷一堆 SCRIPT ERROR（第一版就是这样）。所以只从源码里把那一个常量
## 抠出来（见 `_spawn_radius()`），不加载那个文件。
##
## ⚠️ HUD 那一列读的是「`FlightHUD.SPEED_DISPLAY_SCALE` × 倍率 = **0.6**」这个
## **不变量**（`suite_ui_style` 钉着它），而不是去 `load()` HUD 脚本 ——
## HUD 同样依赖 autoload。

## [显示名, 机体 Id, 形态, 是否靶机版]
const FORMS := [
	["柯西高达", SuitProfile.Id.XI, -1, false],
	["佩涅罗佩", SuitProfile.Id.PENELOPE, -1, false],
	["阿利宙斯·巡航", SuitProfile.Id.ARIZEUS, SuitProfile.ArizeusForm.CRUISE, false],
	["阿利宙斯·常态", SuitProfile.Id.ARIZEUS, SuitProfile.ArizeusForm.NORMAL, false],
	["阿利宙斯·核心", SuitProfile.Id.ARIZEUS, SuitProfile.ArizeusForm.CORE_NU, false],
	["梅萨M01", SuitProfile.Id.MESSER_M01, -1, false],
	["古斯塔夫00(武装)", SuitProfile.Id.GUSTAV00, -1, false],
	["古斯塔夫00(靶机)", SuitProfile.Id.GUSTAV00, -1, true],
]
const FORMS_FOR_TRAVEL := [
	["梅萨M01", SuitProfile.Id.MESSER_M01, -1, false],
	["古斯塔夫00(武装)", SuitProfile.Id.GUSTAV00, -1, false],
]


func _initialize() -> void:
	var m := SuitProfile.SPEED_REAL_MULT
	var mp := SuitProfile.SPEED_REAL_MULT_PREV
	var bar := "=".repeat(104)
	print(bar)
	print("机体速度报表 —— 实际域 / 显示域。SPEED_REAL_MULT = %.2f（上一版 %.2f，本次增量 ×%.2f）"
		% [m, mp, m / mp])
	print(bar)

	# ---------------------------------------------------------------- 机体
	print("")
	print("【机体】显示域 = 菜单/HUD 上印的那些数；实际域 = 飞机真正飞的。")
	print("        HUD 那一列 = 显示域巡航 × 3.6 × 0.6（0.6 = SPEED_DISPLAY_SCALE × 倍率，恒等）")
	print("        ⇒ 它**不含**任何实际域的因子，所以与倍率无关、两版必须逐位相同")
	print("        ⚠️ 取整方式**照抄 HUD**：`int()` 截断，不是四舍五入 ——")
	print("           柯西 1360.8 在屏上是 **1360**（`hud.gd` 写的是 `\"%4d\" % int(...)`）。")
	print("")
	print("%-18s %6s %10s %10s %10s %10s %10s %9s %10s"
		% ["机体", "系数", "显示巡航", "上版实际", "本版实际", "显示极速", "本版极速", "失速线", "HUD km/h"])
	print("-".repeat(104))
	for row: Array in FORMS:
		var p := _profile(row)
		var dc := SuitProfile.speed_to_display(p.player_top_speed())
		var db := SuitProfile.speed_to_display(p.player_boost_speed())
		# ⚠️ `%10d % int(...)` —— 与 `hud.gd` 的 `"%4d" % int(...)` 同口径（截断）。
		# 第一版这里写的是 `%10.0f`（printf 四舍五入），柯西印成 1361，
		# 而屏上其实是 1360。报表的职责是"屏上是什么"，差 1 就是不忠实。
		print("%-18s %6.3f %10.1f %10.1f %10.1f %10.1f %10.1f %9.1f %10d"
			% [row[0], p.speed_scale, dc, dc * mp, p.player_top_speed(), db,
				p.player_boost_speed(), p.player_top_speed() * 0.18, int(dc * 3.6 * 0.6)])

	# ---------------------------------------------------------------- 出生初速
	print("")
	print("【出生初速】`SuitProfile.spawn_speed()` vs 每台机的失速线")
	print("            判据：出生初速必须 > 失速线，否则**出生第一帧**就 stalled")
	var spawn := SuitProfile.spawn_speed()
	print("  出生初速 = %.1f m/s（显示域 %.1f；×1.5 时代是 260 m/s）"
		% [spawn, SuitProfile.speed_to_display(spawn)])
	var min_margin := INF
	var min_who := ""
	for row: Array in FORMS:
		var p2 := _profile(row)
		var stall := p2.player_top_speed() * 0.18
		var margin := spawn - stall
		if margin < min_margin:
			min_margin = margin
			min_who = row[0]
		print("    %-18s 失速线 %7.1f   余量 %7.1f%s"
			% [row[0], stall, margin, "   <<< 越线，一出生就是失速" if margin <= 0.0 else ""])
	print("  ⇒ 最小余量 %.1f m/s（%s）" % [min_margin, min_who])

	# ---------------------------------------------------------------- 武器
	print("")
	print("【武器 / 弹道】凡是「成比例」的都必须跟着倍率走，「时间」不跟")
	print("  %-28s %12s %14s %14s" % ["项", "显示域基准", "上版实际", "本版实际"])
	print("  " + "-".repeat(72))
	var xi := SuitProfile.xi()
	var rng := SuitProfile.RIFLE_DEFAULT_RANGE
	_weapon_line("火神炮弹速", SuitProfile.VULCAN_BASE_SPEED, m, mp)
	_weapon_line("步枪出膛段", SuitProfile.RIFLE_LAUNCH_BASE_SPEED, m, mp)
	print("  %-28s %12s %14.1f %14.1f"
		% ["步枪出膛段上限 (m)", "—", SuitProfile.RIFLE_LAUNCH_MAX_LEN / m * mp,
			SuitProfile.RIFLE_LAUNCH_MAX_LEN])
	print("  %-28s %12s %14.0f %14.0f"
		% ["步枪中段（近光速）", "—", SuitProfile.RIFLE_FAST_SPEED, SuitProfile.RIFLE_FAST_SPEED])
	print("  %-28s %12s %14s %14.0f"
		% ["步枪等效弹速 @%.0f m" % rng, "—", "—", SuitProfile.rifle_effective_speed(rng)])
	print("  %-28s %12s %14s %14.4f"
		% ["步枪飞行时间 @%.0f m (s)" % rng, "—", "—", SuitProfile.rifle_flight_time(rng)])
	_weapon_line("军刀突进", 1150.0, m, mp)
	_weapon_line("榴弹出膛", 260.0, m, mp)
	print("  %-28s %12s %14s %14.0f"
		% ["浮游导弹（从机体推导）", "—", "—", SuitProfile.missile_speed()])
	print("  ⚠️ 步枪中段、等效弹速、飞行时间、导弹**不直接写倍率** ——")
	print("     前三个是「接近光速」的观感常量，导弹是从佩涅罗佩巡航推出来的。")

	# ---------------------------------------------------------------- 次序
	print("")
	print("【次序不变量】")
	var fastest := maxf(SuitProfile.penelope().player_boost_speed(), xi.player_boost_speed())
	var beam := SuitProfile.rifle_effective_speed(rng)
	var mis := SuitProfile.missile_speed()
	print("  光束等效 %.0f  >  导弹 %.0f  >  机体加力 %.0f    ⇒ %s"
		% [beam, mis, fastest, "OK" if beam > mis and mis > fastest else "**次序坏了**"])
	print("  出膛段 %.0f ≈ 柯西巡航 %.0f（比值 %.3f，设计值就是「约等于」）"
		% [SuitProfile.RIFLE_LAUNCH_SPEED, xi.player_top_speed(),
			SuitProfile.RIFLE_LAUNCH_SPEED / xi.player_top_speed()])
	print("  军刀突进 %.0f  >  柯西加力 %.0f    ⇒ %s"
		% [xi.saber_dash_speed, xi.player_boost_speed(),
			"OK" if xi.saber_dash_speed > xi.player_boost_speed() else "**突进比加力还慢**"])

	# ---------------------------------------------------------------- 赶路
	var spawn_r := _spawn_radius()
	print("")
	if spawn_r > 0.0:
		print("【开局赶路】出击点 %.0f m（从 `world_builder.gd` 源码里读出的 SPAWN_RADIUS）" % spawn_r)
		print("  %-18s %10s %10s %11s %11s" % ["机体", "加力极速", "横穿(s)", "槽程(km)", "槽程占比"])
		print("  " + "-".repeat(64))
		for row: Array in FORMS_FOR_TRAVEL:
			var p3 := _profile(row)
			var b := p3.player_boost_speed()
			var reach := p3.jet_seconds * b
			print("  %-18s %10.1f %10.1f %11.2f %10.1f%%"
				% [row[0], b, spawn_r / b, reach / 1000.0, reach / spawn_r * 100.0])
		print("  ⚠️ 核心守卫是「槽程 < 出击距离」（自己飞不到 ⇒ 必须靠踏板）；")
		print("     「槽程占比」只是粗估，会随提速漂高 —— 详见 suite_round19 的注释。")
	else:
		print("【开局赶路】**跳过**：没从源码里读到 `WorldBuilder.SPAWN_RADIUS`。")

	print("")
	print(bar)
	quit()


## 打印一行"显示域基准 × 倍率"的武器速度（两版并排）。
func _weapon_line(name: String, base: float, m: float, mp: float) -> void:
	print("  %-28s %12.0f %14.0f %14.0f" % [name, base, base * mp, base * m])


## 出击点距离（米）。**真源是 `WorldBuilder.SPAWN_RADIUS`**。
##
## ⚠️ 刻意不写成 `WorldBuilder.SPAWN_RADIUS`：`world_builder.gd` 引用 `Settings`
## autoload，而 `--script` 独立模式里 autoload 不存在 ⇒ 引用它会连带编译失败、
## 刷 SCRIPT ERROR。所以改成**只从源码里把那一个常量抠出来**（不加载那个文件）。
## 正则容忍"有没有类型标注"两种写法；读不到就返回 0，让调用方**明确跳过**这一段
## —— 宁可少打一列，也不给一个编出来的数。
func _spawn_radius() -> float:
	var src := FileAccess.get_file_as_string("res://scripts/world/world_builder.gd")
	if src.is_empty():
		return 0.0
	var re := RegEx.new()
	if re.compile("(?m)^const\\s+SPAWN_RADIUS\\s*(?::[^=]+)?=\\s*([0-9_.]+)") != OK:
		return 0.0
	var hit := re.search(src)
	if hit == null:
		return 0.0
	return float(hit.get_string(1))


func _profile(row: Array) -> SuitProfile:
	if bool(row[3]):
		return SuitProfile.gustav00()
	if int(row[2]) >= 0:
		return SuitProfile.by_id_form(row[1], row[2])
	return SuitProfile.by_id(row[1])
