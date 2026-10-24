class_name SuiteLockManual
extends RefCounted
## **锁定系统重修：锁定对象只由玩家切换**（轮 36）。
##
## ## 用户要的东西，一句话
##
## > 「锁定系统重修，**除非玩家手动切换锁定，不然不会自动切换锁定对象**」
##
## 追问之后的四条口径：
##
## | # | 口径 | 落点 |
## |---|---|---|
## | ① | 丢目标后 =**空锁但保住组**（不自动提主目标；组内其余成员与进度保留） | `LockOnSystem._remove_group_member()` |
## | ② | 鼠标**只管准星**（不再参与锁定） | 删掉 `PlayerController._read_lock_input()` |
## | ③ | 进场**自动锁一次**，之后没了就交给玩家 | `auto_engage_limit = 1` |
## | ④ | AI 侧行为**一点不变** | `auto_engage_limit` 默认 `-1` |
##
## 本轮撤掉了**三条**旧的自动行为，它们各自都有旧测试在钉：
## 自动接战（`_set_main(candidates[0])`）、顺位补位（组 0 号换人）、鼠标罩住即选。
## 所以本套件既是"新口径钉死"，也是"旧口径已撤"的**双向**清单。
##
## ## ⚠️ 为什么第 ③ 节要写成**源码**断言
##
## 玩家侧的锁定入口是**每帧跑**的（`_read_lock_input()` 当年就是每帧选的）。
## 行为断言只能证明"这一帧没换目标"—— 它证明不了"这段代码已经没了"：
## 哪天有人把 `_read_lock_input()` 加回来，只要测试那一刻光标恰好没罩住敌机，
## 行为断言照样是绿的。**"功能已删除"只能靠源码断言。**

const ALT := 3000.0


static func run(t: T, host: Node) -> void:
	t.suite("LockManual / 自动接战的次数上限（-1 / 1 / 0）")
	await _auto_engage_counts(t, host)
	t.suite("LockManual / 丢目标不补位：组与进度都留着，Tab 瞬间切回")
	await _no_auto_switch(t, host)
	t.suite("LockManual / 鼠标只管准星：那三样已经不存在了")
	_mouse_source(t)
	t.suite("LockManual / 默认就是 AI 的行为（改动面只有一个字段）")
	_default_is_ai(t)


# ============================================================ 工具

## 一台可被打的机体（与 `suite_multi_lock._new_unit()` 同构）。
##
## `is_player` / `profile` / `team` **必须在 `add_child()` 之前**设好 ——
## `FlightBody._ready()` 会读它们决定进哪个分组、加载哪个模型、血量多少。
## I 立场关掉（`ifield_max = 0`），让断言直接落在机体血上（护盾由 suite_damage 测）。
static func _new_unit(container: Node3D, team: int, pos: Vector3, hp := 400.0,
		as_player := false) -> FlightBody:
	var u := FlightBody.new()
	u.team = team
	u.is_player = as_player
	u.profile = SuitProfile.penelope() if team == 0 else SuitProfile.xi()
	u.display_name = "T%d" % team
	u.projectile_container = container
	container.add_child(u)
	u.global_position = pos
	u.max_hp = hp
	u.hp = hp
	u.ifield_max = 0.0
	u.ifield_hp = 0.0
	u.fm.speed = 260.0
	u.fm.throttle = 0.78
	u.fm.align_velocity(u.forward())
	return u


## 挂一套火控。`lock_time` 压到 0.05（3 帧就锁上）——
## 本套件测的是**谁在什么条件下被选成锁定对象**，不是质量条的累积速度
##（那在 `suite_combat / 锁定手感底线`）。
static func _new_lock(host: Node, unit: FlightBody, limit: int) -> LockOnSystem:
	var lk := LockOnSystem.new()
	lk.lock_time = 0.05
	lk.auto_engage_limit = limit
	host.add_child(lk)
	lk.setup(unit)
	return lk


static func _frames(host: Node, n: int) -> void:
	for i in n:
		await host.get_tree().physics_frame


## 把一个临时场景整块拆掉（机体 + 火控），并空转两帧让删除生效。
static func _teardown(host: Node, lk: LockOnSystem, c: Node3D) -> void:
	lk.free()
	c.free()
	await _frames(host, 2)
	Game.reset()


static func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## 去掉**整行注释**与**行尾注释**之后的源码。
##
## ⚠️ 所有「源码里有没有 X」的断言都必须走这里。理由与 `SuiteUiStyle._code()` 同源：
## 注释里提到某个名字恰恰说明它被慎重考虑过 —— 那不该算违规。
##（本套件里就有活例子：`player_controller.gd` 的鼠标区注释**特意**写着
##  "轮 36 删掉的三样东西"并逐个点名，走原文扫描会把自己判失败。）
##
## 与 `SuiteUiStyle._code()` 不共享实现是**故意的**：套件之间不互相依赖 ——
## 那边是 UI 风格套件，这边是锁定套件，谁改了都不该惊动对方。
static func _code(path: String) -> String:
	var out: Array = []
	for line in _src(path).split("\n"):
		var s := str(line)
		if s.strip_edges().begins_with("#"):
			continue
		out.append(_strip_inline(s))
	return "\n".join(out)


## 去掉行尾注释（`#` 落在字符串里的时候不算注释）。
##
## 内外靠**引号计数**判断：`#` 前面若有奇数个引号，说明它在字符串里。
## 这不是完整的词法分析，但对"代码行里混一句中文注释"这种实际情况够用。
static func _strip_inline(line: String) -> String:
	var quotes := 0
	for i in line.length():
		var c := line[i]
		if c == "\"" or c == "'":
			quotes += 1
		elif c == "#" and quotes % 2 == 0:
			return line.substr(0, i)
	return line


## 某个顶层函数的**函数体**（从 `header` 起，到下一个行首 `func` 为止）。
##
## ⚠️ 用它是为了把"某一段里不许有 X"写准。本轮踩过一次活例：
## 断言「HUD 里不再有 `lock.lock_ratio()`」是**过宽**的 ——
## **目标框**上的质量环就该用它（那是锁定对象自己的进度读数）。
## 要删的只是**准星上**那个（"光标罩住的那台正在锁"的进度环）。
## "整份文件里不许有"与"这一段里不许有"是两条不同的断言。
static func _func_body(src: String, header: String) -> String:
	var i := src.find(header)
	if i < 0:
		return ""
	var rest := src.substr(i)
	var j := rest.find("\nfunc ", 1)
	return rest if j < 0 else rest.substr(0, j)


# ============================================================ ① 自动接战的次数上限

static func _auto_engage_counts(t: T, host: Node) -> void:
	# ---- limit = 1：进场自动锁一次，之后不再自动咬 ----
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var me := _new_unit(c, 0, Vector3(0, ALT, 0), 400.0, true)
	var e1 := _new_unit(c, 1, Vector3(0, ALT, -2000.0))
	var e2 := _new_unit(c, 1, Vector3(0, ALT, -3000.0))
	var lk := _new_lock(host, me, 1)

	await _frames(host, 3)
	t.eq(lk.lock_group.size(), 1, "limit=1：进场自动接战，组里一个人")
	t.eq(lk.target, e1, "……接的是正前方最近的 e1")

	e1.take_damage(9999.0, me)
	await _frames(host, 12)
	t.ok(lk.lock_group.is_empty(), "limit=1：打掉目标 ⇒ 组空")
	t.eq(lk.target, null, "limit=1：**不自动咬下一个**（自动接战只用一次）")
	t.not_ok(lk.lock_group.has(e2), "……e2 就在正前方、也没被自动接战进组")
	t.eq(lk.tier_of(e2), LockOnSystem.Tier.LOCK,
		"（对照）e2 自己的质量条其实早就满了 —— 挡住它的不是航迹门槛，而是「不自动接战」")

	lk.cycle_target()
	t.eq(lk.target, e2, "玩家按一下 Tab ⇒ 才接战到 e2（手动发起完全不受这个上限约束）")

	await _teardown(host, lk, c)

	# ---- limit = -1：不限次（AI 的现状行为）----
	Game.reset()
	var c2 := Node3D.new()
	host.add_child(c2)
	var me2 := _new_unit(c2, 0, Vector3(0, ALT, 0), 400.0, true)
	var f1 := _new_unit(c2, 1, Vector3(0, ALT, -2000.0))
	var f2 := _new_unit(c2, 1, Vector3(0, ALT, -3000.0))
	var ai := _new_lock(host, me2, -1)

	await _frames(host, 3)
	t.eq(ai.target, f1, "limit=-1（AI）：自动接战")
	f1.take_damage(9999.0, me2)
	await _frames(host, 12)
	t.eq(ai.target, f2, "limit=-1（AI）：打掉目标后**继续**自动接战下一个（与改动前逐位相同）")

	await _teardown(host, ai, c2)

	# ---- limit = 0：从不自动（留给"一律手动"的将来）----
	Game.reset()
	var c3 := Node3D.new()
	host.add_child(c3)
	var me3 := _new_unit(c3, 0, Vector3(0, ALT, 0), 400.0, true)
	var g1 := _new_unit(c3, 1, Vector3(0, ALT, -2000.0))
	var no := _new_lock(host, me3, 0)

	await _frames(host, 8)
	t.ok(no.lock_group.is_empty(), "limit=0：从不自动接战 ⇒ 组一直是空的")
	t.eq(no.target, null, "limit=0：……锁定对象也是空的")
	t.not_ok(no.lock_group.has(g1), "……g1 从没被自动接战进组（组外候选只是自己在涨质量条）")
	no.cycle_target()
	t.eq(no.target, g1, "limit=0：玩家按 Tab 仍然能手动接战（这道门只挡自动那一半）")

	await _teardown(host, no, c3)


# ============================================================ ② 丢目标不补位

static func _no_auto_switch(t: T, host: Node) -> void:
	Game.reset()
	var c := Node3D.new()
	host.add_child(c)
	var me := _new_unit(c, 0, Vector3(0, ALT, 0), 400.0, true)
	var a := _new_unit(c, 1, Vector3(0, ALT, -2000.0))
	var b := _new_unit(c, 1, Vector3(0, ALT, -3000.0))
	var d := _new_unit(c, 1, Vector3(0, ALT, -4000.0))
	# 不限次：这一节要验的是**补位**，不是接战次数（那是上一节的事）
	var lk := _new_lock(host, me, -1)

	await _frames(host, 4)
	t.eq(lk.target, a, "（前提）自动接战到 a")

	# 把 b、d 锁进组 —— 走 `add_lock()`，与玩家长按 Tab 是同一条路
	t.ok(lk.add_lock(b), "把 b 加进锁定组")
	await _frames(host, 30)                 # ≫ ADD_LOCK_COOLDOWN
	t.ok(lk.add_lock(d), "把 d 加进锁定组")
	await _frames(host, 30)
	t.eq(lk.lock_group.size(), 3, "（前提）组里三个人")
	t.eq(lk.locked_in_group().size(), 3, "（前提）三个都已经稳定锁定")

	# ---- 打掉**锁定对象** a ----
	a.take_damage(9999.0, me)
	await _frames(host, 4)
	t.eq(lk.target, null, "锁定对象被击坠 ⇒ **不补位**，锁定对象变空")
	t.eq(lk.lock_group.size(), 2, "组里还剩 b 和 d（成员一个都没丢）")
	t.ok(lk.lock_group.has(b) and lk.lock_group.has(d), "……确实就是 b 和 d")
	t.eq(lk.tier_of(b), LockOnSystem.Tier.LOCK, "b 的锁定**进度保留**（层级还是 LOCK）")
	t.eq(lk.tier_of(d), LockOnSystem.Tier.LOCK, "d 同理")
	t.not_ok(lk.locked, "没有锁定对象 ⇒ 导弹 / 军刀门禁关闭")

	# ---- 关键：不补位是**稳态**，不是"晚一帧就好了" ----
	await _frames(host, 30)
	t.eq(lk.target, null, "等半秒之后**仍然没有**锁定对象 —— 不补位是稳态")
	t.eq(lk.lock_group.size(), 2, "……组也仍然是两个人")

	# ---- 玩家手动切 ⇒ 瞬间切到组内的人（进度是现成的）----
	lk.cycle_target()
	t.eq(lk.target, b, "按一下 Tab ⇒ 队首的 b 立刻成为锁定对象")
	t.eq(lk.lock_group.size(), 2, "……组没被清（切过去是瞬间的，不必重锁）")
	t.eq(lk.tier_of(lk.target), LockOnSystem.Tier.LOCK, "……而且它已经是稳定锁定")
	t.ok(lk.locked, "……门禁跟着打开")

	lk.cycle_target()
	t.eq(lk.target, d, "再按一下 Tab ⇒ 组内轮转到 d")
	t.eq(lk.lock_group.size(), 2, "……轮转同样不清组")

	await _teardown(host, lk, c)


# ============================================================ ③ 鼠标只管准星（源码）

static func _mouse_source(t: T) -> void:
	var pc := _code("res://scripts/flight/player_controller.gd")
	t.not_ok(pc.contains("_read_lock_input"), "鼠标选锁定目标那条路（`_read_lock_input`）已经整段删除")
	t.not_ok(pc.contains("MOUSE_PICK_RADIUS"), "……`MOUSE_PICK_RADIUS`（「光标罩住即选中」的半径）已删")
	t.not_ok(pc.contains("MOUSE_SWITCH_HYSTERESIS"), "……`MOUSE_SWITCH_HYSTERESIS`（换目标的像素迟滞）已删")
	t.not_ok(pc.contains("_suppress_mouse_lock"), "……`_suppress_mouse_lock`（跨帧压制鼠标）已删 —— 没有第二个写者了")
	t.ok(pc.contains("select_target"), "（对照）数字键那条路仍在：`select_contact()` → `select_target()`")
	t.ok(pc.contains("aim_cursor"), "准星仍然记光标位置（鼠标的活只剩「打哪儿」）")
	t.ok(pc.contains("project_ray_normal(aim_cursor)"),
		"……弹道方向仍然跟着光标（轮 41 起改由**准星像素的相机射线**给出：准星画在哪、子弹打向哪）")

	var hud := _code("res://scripts/ui/hud.gd")
	t.not_ok(hud.contains("MOUSE_PICK_RADIUS"), "HUD 不再借玩家的鼠标拾取半径（那个常量已经不存在了）")
	# ⚠️ 「不许出现在**整份文件**里」与「不许出现在**这一段**里」是两条不同的断言。
	# `lock.lock_ratio()` 在**目标框**上是合法且必需的（锁定对象自己的进度环），
	# 要删的只是**准星**上那个（"光标罩住的那台正在锁"）—— 所以这里必须限定函数体。
	var cursor_fn := _func_body(hud, "func _draw_aim_cursor")
	t.not_ok(cursor_fn.is_empty(), "（前提）抓到了 `_draw_aim_cursor()` 的函数体")
	t.not_ok(cursor_fn.contains("draw_arc"), "准星上不再画任何环（「罩住就能锁」的外圈 + 锁定进度环都已删）")
	t.not_ok(cursor_fn.contains("lock_ratio"), "……准星也不再读质量条（那是目标框那一套的活）")
	t.ok(hud.contains("lock.lock_ratio()"), "（对照）**目标框**上的质量环仍然保留 —— 那是锁定对象的读数，不是准星的承诺")
	t.ok(hud.contains("CURSOR_HOVER_RADIUS"), "准星变色改用 HUD 自己的常量（纯视觉，不带锁定语义）")
	t.ok(hud.contains("_draw_target"), "（对照）目标框仍由 `_draw_target()` 画（锁定对象为空时它自己 return）")

	var los := _code("res://scripts/combat/lock_on_system.gd")
	t.ok(los.contains("auto_engage_limit"), "锁定系统有「自动接战次数上限」这个字段")
	t.ok(los.contains("_can_auto_engage"), "……以及它对应的判定函数")
	t.ok(los.contains("_set_main_in_group"), "……以及「把组内成员提为锁定对象」那条路（不清组、不动进度）")
	t.ok(los.contains("var _main: FlightBody = null"), "……锁定对象的真源是**可空**的 `_main`，不再是 `lock_group[0]` 的别名")

	var ms := _code("res://scripts/main.gd")
	t.ok(ms.contains("player_lock.auto_engage_limit = 1"), "玩家火控在 `main.gd` 里被设成「只自动一次」")
	t.not_ok(ms.contains("lk.auto_engage_limit"), "敌方火控**不设**这个字段（保持默认不限次）")


# ============================================================ ④ 默认值 = AI 的行为

static func _default_is_ai(t: T) -> void:
	var lk := LockOnSystem.new()
	t.eq(lk.auto_engage_limit, -1,
		"`LockOnSystem` 的默认值是 -1（不限次）—— AI 一个字不改就保持改动前的行为")
	t.eq(lk._main, null, "初始没有锁定对象")
	t.ok(lk.lock_group.is_empty(), "初始锁定组为空")
	t.eq(lk._auto_engages, 0, "初始自动接战次数是 0")
	lk.free()

	var ai := _code("res://scripts/ai/bandit_ai.gd")
	t.not_ok(ai.contains("auto_engage_limit"), "AI 侧确实没有碰过这个字段（改动面 = 只有一个写入点）")
