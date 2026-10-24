class_name SuiteReloadGauge
extends RefCounted
## 批 28（2026-09-22 用户指定）：「给换弹和浮游飞弹重新装填重新做一个滚动读条效果」。
##
## 这条需求补的是两处**看不见的进度** —— 两处都不是"画得不好看"，而是**没有读数**：
##
##   1. **光束步枪换弹**（按 R，`rifle_reloading`）：那一条画的是 `mag_ratio()`，
##      而"打空才换弹"意味着它在那两秒里**恒为 0** —— 玩家看到的是一条空着的静止条，
##      「还剩多久」完全没有读数。
##   2. **浮游导弹装填**（打空自动装，`funnel_reload_left`）：`flight_body.gd` 的注释
##      明明写着「HUD 浮游导弹一行会读 `funnel_reload_left` 显示进度」，
##      **而 HUD 从来没画过** —— 装填那几秒里那一行只有个停在 0 的数字。
##
## 分三组，因为这三件事坏起来的样子完全不同：
##
## | 组 | 坏了会怎样 |
## |---|---|
## | **换算**（`funnel_reload_progress()`）| 条走完了弹夹还没满（读条撒谎）|
## | **接线**（扫源码）| 换算对了但 HUD 没调它 —— 症状与需求原状**一模一样** |
## | **版式** | 条压在名称列的字上；或换弹开始/结束瞬间整行左右跳一格 |
##
## ⚠️ **绘制本身测不了**：`_draw()` 在无头环境里画不出东西（没有帧缓冲，
## `can_draw()` 还可能为假）。所以"斜纹够不够清楚、亮边会不会太扎眼"归人眼试玩；
## 能测的那半边（进度数学 / 调用点 / 几何不等式）全在这一套里。
## 这个切法与 `SuiteHudInstruments` 完全一致 —— 本工程一贯如此。

const HUD_PATH := "res://scripts/ui/hud.gd"
const BODY_PATH := "res://scripts/flight/flight_body.gd"


static func run(t: T, host: Node) -> void:
	t.suite("批 28 / 装填进度：换算只有一处真源")
	await _progress(t, host)
	t.suite("批 28 / 接线：两条读条都真的画出来")
	_wiring(t)
	t.suite("批 28 / 版式：不压字、右端同线")
	_layout(t)


# ------------------------------------------------------------ 工具

## 去注释的源码。与 `SuiteUiStyle._code()` 同一套做法：
## 这个 HUD 是**全代码绘制**的，"有没有调用"运行时反射不出来，只能扫源码。
##
## ⚠️ 必须先剔注释 —— 本工程为这个坑栽过一次（`hud.gd` 的注释里特意写着
## 改前的错误写法，于是"源码里不许出现 X"那条断言被一句注释判了失败）。
static func _code(path: String) -> String:
	var out: Array = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var s := str(line)
		if s.strip_edges().begins_with("#"):
			continue
		out.append(s)
	return "\n".join(out)


## `from` 所在行自己的缩进（`from` 必须出现在该行的行首缩进之后）。
static func _indent_of(src: String, at: int) -> String:
	var ls := src.rfind("\n", at) + 1
	var indent := ""
	for k in range(ls, at):
		var ch := src[k]
		if ch == "\t" or ch == " ":
			indent += ch
		else:
			break
	return indent


## 取 `from` 之后到**同缩进的 `else:`** 之前那一段（≈ "这个 if 的分支体"）。
##
## 用来钉「读条只在**装填中**才画」—— 只断言"文件里有 `_draw_roll_bar`"是不够的：
## 调用点挪到 `if` 外面，条就会**一直挂着**，而那看起来仍然"画出来了"。
##
## ⚠️ 缩进必须按 `from` 那一行**实测**：写死 `"\n\telse:"` 的话，
## 两层的 `if`（`\n\t\telse:`）根本匹配不上，函数会把手伸到文件末尾 ——
## 于是后面每一条 `contains()` 都变成"几乎必然为真"的假断言。
static func _block(src: String, from: String) -> String:
	var i := src.find(from)
	if i < 0:
		return ""
	var rest := src.substr(i + from.length())
	var j := rest.find("\n" + _indent_of(src, i) + "else:")
	return rest if j < 0 else rest.substr(0, j)


## 取一个函数体：从 `sig` 起，到下一个顶层 `func` / `const` / `var` 之前。
## 这样 `contains()` 只在那一个函数里找 —— 否则"在整份文件里找 `_time`"
## 是一条永远为真的空断言。
static func _func_body(src: String, sig: String) -> String:
	var i := src.find(sig)
	if i < 0:
		return ""
	var rest := src.substr(i)
	var end := -1
	for marker in ["\nfunc ", "\nstatic func ", "\nconst ", "\nvar "]:
		var k := rest.find(marker)
		if k > 0 and (end < 0 or k < end):
			end = k
	return rest if end < 0 else rest.substr(0, end)


## 与 `SuiteAbilities._unit()` 同形的最小夹具：`profile` 必须在 `add_child` 之前给上
## （`_ready()` 按它铺弹匣与备弹 —— 默认 `rifle_count` / `rifle_mag` 都是 0）。
static func _unit(container: Node3D, suit: SuitProfile, team: int) -> FlightBody:
	var u := FlightBody.new()
	u.team = team
	u.is_player = false
	u.profile = suit
	u.projectile_container = container
	container.add_child(u)
	u.global_position = Vector3(0, 3000, 0)
	return u


# ------------------------------------------------------------ ① 换算

static func _progress(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var u := _unit(c, SuitProfile.xi(), 1)

	# ---- 步枪换弹：0 → 1，单调，中途可读 ----
	t.eq(u.reload_progress(), 0.0, "（基线）没换弹时步枪进度 = 0，也就是「不要画读条」")
	u.rifle_mag = 0
	t.ok(u.reload_rifle(), "弹匣打空 → 可以换弹（前置）")
	t.eq(u.rifle_reloading, true, "换弹标记置位（HUD 的门控就读它）")
	t.between(u.reload_progress(), 0.0, 0.05, "刚按下时进度贴着 0（条从空槽里长出来）")

	var prev := u.reload_progress()
	var mono := true
	var hit_mid := false
	var steps := 0
	while u.rifle_reloading and steps < 400:
		var p := u.reload_progress()
		if p < prev - 0.0001:
			mono = false
		if p > 0.45 and p < 0.55:
			hit_mid = true
		prev = p
		u._tick_weapons(0.05)
		steps += 1
	t.ok(mono, "进度单调不回头（读条倒着走是最刺眼的一类错）")
	t.ok(hit_mid, "中途能读到 ~50% 的进度（不是「一格跳到满」）")
	t.eq(u.rifle_reloading, false, "换弹结束")
	t.eq(u.reload_progress(), 0.0, "结束后进度归 0（读条收起，弹匣 %d 发）" % u.rifle_mag)

	# ---- 浮游导弹装填：**批 28 新增**的换算，必须与步枪那条同形 ----
	t.eq(u.funnel_reload_progress(), 0.0, "（基线）没装填时导弹进度 = 0")
	u.funnel_count = 0
	u.funnel_reload_left = 0.0
	u._funnel_check_reload()
	t.gt(u.funnel_reload_left, 0.0, "弹夹打空触发装填（前置）")
	t.eq(u.funnel_reload_progress(), 0.0, "装填刚开始进度贴 0")

	var fprev := 0.0
	var fmono := true
	var fmax := 0.0
	var fsteps := 0
	while u.funnel_reload_left > 0.0 and fsteps < 400:
		var fp := u.funnel_reload_progress()
		if fp < fprev - 0.0001:
			fmono = false
		fmax = maxf(fmax, fp)
		fprev = fp
		u._tick_weapons(0.05)
		fsteps += 1
	t.ok(fmono, "装填进度单调")
	t.gt(fmax, 0.9, "收口前冲到 0.9 以上（条走满 = 弹夹满，两边同一个时刻）")
	t.eq(u.funnel_reload_left, 0.0, "装填计时收口（不留残态）")
	t.eq(u.funnel_reload_progress(), 0.0, "装填结束后进度归 0（读条收起）")
	t.eq(u.funnel_count, u.funnel_mag_size, "装填完弹夹满上（%d 发）" % u.funnel_count)

	# 步数对账：0.05 s 步进下，两条都该在"时长 / 0.05"附近走完。
	# 差得远说明换弹时长或 `_tick_weapons` 的推进有一边改了（读条会跟着撒谎）。
	t.near(float(steps) * 0.05, u.profile.rifle_reload_time, 1.0,
		"步枪换弹步数 × 0.05 s ≈ profile 的换弹时长")
	t.near(float(fsteps) * 0.05, u.profile.funnel_reload_time, 1.0,
		"导弹装填步数 × 0.05 s ≈ profile 的装填时长")

	c.free()
	await host.get_tree().process_frame


# ------------------------------------------------------------ ② 接线（扫源码）

static func _wiring(t: T) -> void:
	var src := _code(HUD_PATH)
	t.ok(src.contains("func _draw_roll_bar("), "HUD 有滚动读条本体")
	# 1 处定义 + 2 处调用。只断言"存在"的话，删掉任何一条读条都照样绿。
	t.eq(src.count("_draw_roll_bar("), 3, "读条本体被两条路径调用（定义 1 + 调用 2）")

	# ---- 换弹那条 ----
	var rifle := _block(src, "if player.rifle_reloading:")
	t.ok(rifle.contains("_draw_roll_bar("), "**换弹中**才画读条（门控 = `rifle_reloading`）")
	t.ok(rifle.contains("player.reload_progress()"), "换弹读条读机身给的进度（不自己算）")
	t.ok(rifle.contains("IFIELD"), "换弹读条用 IFIELD（青 = 系统在处理）")
	t.ok(rifle.contains("换弹 %d%%"), "百分比补在名称列（条只有 10 px 高，塞不下 14 号的字）")
	# 读条**复用弹匣条那个矩形**（左端与宽度都从它来）：另起一个 rect 就会两处各调一次，
	# 迟早调出"换弹前后条左右跳一格"—— 那正是 §4.7 一条对齐线要防的。
	t.ok(rifle.contains("bar.position.x") and rifle.contains("mag_w"),
		"换弹读条挂在弹匣条的矩形上（不另算一处 x / 宽度）")

	# ---- 装填那条 ----
	t.ok(src.contains("player.funnel_reload_left > 0.0"), "装填门控读的是装填剩余时间")
	var funnel := _block(src, "if rearming:")
	t.ok(funnel.contains("_draw_roll_bar("), "**装填中**才画读条")
	t.ok(funnel.contains("player.funnel_reload_progress()"), "装填读条读机身给的进度（不自己算）")
	t.ok(funnel.contains("WARN"), "装填读条用 WARN（橙 = 发射器在忙，与换弹的青色区分开）")
	t.ok(funnel.contains("装填 %d%%"), "装填的百分比同样在名称列")

	# ---- 「进度换算只有一处真源」----
	# HUD 里出现这两个 profile 字段 = 有人又在 HUD 里除了一遍换弹时长。
	# 那种写法的症状是"条走完了弹夹还没满"，而且改时长时要改两个地方。
	t.eq(src.count("rifle_reload_time"), 0, "HUD 不自己除步枪换弹时长")
	t.eq(src.count("funnel_reload_time"), 0, "HUD 不自己除浮游装填时长")
	# 反证：机身那边**必须**有这两个换算（上面两条不能靠"两边都没有"通过）。
	var body := _code(BODY_PATH)
	t.ok(body.contains("func reload_progress("), "机身提供步枪换弹进度")
	t.ok(body.contains("func funnel_reload_progress("), "机身提供浮游装填进度（批 28 新增）")

	# ---- 「滚动」二字的实现 ----
	var roll := _func_body(src, "func _draw_roll_bar(")
	t.ok(roll.contains("_time"), "滚动相位来自 `_time`（帧时钟），不是自造计时器")
	t.ok(roll.contains("fmod("), "相位取模 —— 不取模的话几分钟后斜纹整个跑出填充段")
	t.ok(roll.contains("clampf(") and roll.contains("minf(") and roll.contains("maxf("),
		"斜纹被裁在填充段内（出了前沿就不该有纹，否则看着像已经填满）")
	t.ok(roll.contains("LINE_STRUCT"), "前沿亮边与外框走结构线那一档（§4.7 只许两档线宽）")
	t.eq(src.count("ROLL_STRIPE_SPEED"), 2, "滚动速度只有定义 + 使用两处（没有第二份速度）")


# ------------------------------------------------------------ ③ 版式

static func _layout(t: T) -> void:
	var src := _code(HUD_PATH)

	# 两条读条与弹匣条**共用同一条右端线**：弹匣条与浮游装填条都从 `cols["value"]`
	# 往左挂；换弹那条复用弹匣条的矩形（上面已单独钉住）。
	# 不共用的话，换弹开始/结束的那一瞬间那一行会左右跳一格。
	t.eq(src.count("float(cols[\"value\"]) - "), 2,
		"弹匣条与浮游装填条都从数值列右端往左挂（同一列，行与行才齐）")

	for view: Vector2 in SuiteLayout.VIEWS:
		var cols := UILayout.ammo_columns(view)
		var bar_left := float(cols["value"]) - UILayout.AMMO_BAR_W
		var name_right := float(cols["name"])
		# 这条不等式与 `suite_layout` 盯着弹匣条的那条同源：读条占的是数值列那一段，
		# 名称列必须整个在它左边 —— 否则「换弹 62%」会被条压住。
		t.gt(bar_left - name_right, 0.0,
			"%s：读条左端在名称列右侧（%.1f > %.1f）" % [view, bar_left, name_right])

		# 名称列那段要放得下最长的读数：「装填 100%」。字号 14 下的实测宽度。
		var font := ThemeDB.fallback_font
		if font != null:
			var gap := name_right - float(cols["key"])
			var w := font.get_string_size("装填 100%", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			t.lt(w, gap, "%s：「装填 100%%」放得进名称列那段（%.1f < %.1f px）" % [view, w, gap])

	# 读条必须比弹匣条**高**一点：斜纹要有地方待在条内（等高会把纹挤成实心块）。
	t.gt(_roll_bar_h(), 9.0, "读条高度 > 弹匣条的 9 px（常量 ROLL_BAR_H）")


## 读条高度。测试**不能**直接 import `hud.gd`（它 extends CanvasItem，
## 实例化要走场景树），所以照 `SuiteUiStyle` 的老办法扫源码取值 ——
## 于是"高度被改回 9 px"这种回退能被抓住，而不是静默通过。
static func _roll_bar_h() -> float:
	for line in _code(HUD_PATH).split("\n"):
		var s := (line as String).strip_edges()
		if s.begins_with("const ROLL_BAR_H := "):
			var v := s.trim_prefix("const ROLL_BAR_H := ")
			var sp := v.find(" ")
			if sp > 0:
				v = v.substr(0, sp)
			return float(v)
	return 0.0
