class_name SuiteMenuGroups
extends RefCounted
## 主菜单**「对战模式」子页** —— 把王牌战 / 小队战收进一个小菜单。
##
## ## 这一套守的是哪件事
## 老板：「把**王牌战和小队战整合到一个对战模式的小菜单中**」。
## 表面上只是"多一层菜单"，真正会出事的是**两个数不再是同一个数**：
##
## | 数 | 答的是 | 现在 |
## |---|---|---|
## | `MODE_GROUPS.size()` | 模式页**有几行** | **5** |
## | `all_modes().size()` | 工程里有**几种模式** | **6** |
##
## 分组之前它们恰好相等（都是 `MODES.size()`），所以全工程到处可以互换着用；
## 一旦分组，任何一处拿 6 当行数用都会**静默**把最后一行排到面板外面。
## 所以断言分三类：**数据**（分组表）、**合成**（两层 → 一个答案）、
## **版式**（行数该取哪个数）。
##
## ⚠️ ★63-24 又加了一组「强化演习」⇒ 这两个数**再次同时变大、依旧不相等**
##（5 行 / 6 个模式）。这一套的断言全部写成"跟着 `MODE_GROUPS` 走"的形式，
## 所以只有那几条**写死了 4 / 5 的口径断言**需要跟着改 —— 它们本来就是用来
## 逼人"加了一组就回来看一眼版式"的。
##
## ## 另外两条一起钉住
##   ① **单项分组不弹子页**（剧情挑战 1 项 / 强化演习 1 项 / 训练 1 项 / 联机 1 项）：
##      判据是**数据**（`modes.size() > 1`），不是在输入里点名"对战模式"；
##   ② **剧情挑战（`CHALLENGE`）恢复入口之后必须真的连得上**：它在 1.2 第二十轮被
##      隐藏、2026-09-29 加回来 —— 所以这里既钉"它在表里"（`all_modes()` 含它），
##      也钉"它不在对战模式那一组里"（挑战不是对战的一种形式）。
##      ⚠️ "在不在菜单里"这件事**不许用真模式当反例**去测：
##      `all_modes()` 现在把 6 个合法取值全收了 ⇒ 反例只能用**不存在的编号**。
##
## ⚠️ 按**主题命名**（本仓库有并行会话，两侧都按轮次占号时撞过一次文件）。

const GROUPS := "MenuGroups / 分组表：5 行 = 5 类玩法"
const COMPOSE := "MenuGroups / 两层合成一个答案（分组 + 形式）"
const LAYOUT := "MenuGroups / 版式：行数取哪一层"
const WIRING := "MenuGroups / 绘制与输入接线（源码扫描）"


static func run(t: T, _host: Node) -> void:
	t.suite(GROUPS)
	_groups(t)
	t.suite(COMPOSE)
	_compose(t)
	t.suite(LAYOUT)
	_layout(t)
	t.suite(WIRING)
	_wiring(t)


# ---------------------------------------------------------------- 1 分组表

static func _groups(t: T) -> void:
	# ---- ① 模式页 4 行 ----
	t.eq(MainMenu.MODE_GROUPS.size(), 5, "五个玩法分组；音乐和设置不是玩法")
	var names: Array = []
	for i in MainMenu.MODE_GROUPS.size():
		names.append(str(MainMenu.group_info(i)["name"]))
	t.eq(names, ["对战模式", "剧情挑战", "无限激化模拟", "训练模式", "局域网联机"], "包含无尽模式的五组显示顺序")
	# ★ 2026-10-01 老板要求「剧情挑战放到第二位，训练模式放到第三位」——
	# 主玩法（战役）往上提一格，训练是练习用的旁支，跟在它后面更顺。
	# ⚠️ 这两条**不是在争「哪个模式更该排前面」**（那是产品口味，谁也说不准），
	# 而是在钉**数据表与显示顺序一致**：顺序只有 `MODE_GROUPS` 一份真源。
	t.eq(names.find("剧情挑战"), 1, "剧情挑战在第二位（对战模式之后、训练模式之前）")
	t.eq(names.find("训练模式"), 3, "无尽模式第三位，训练模式第四位")

	# ---- ② 摊平 = 5 种模式 ----
	t.eq(MainMenu.all_modes(),
		[Game.MatchMode.VERSUS, Game.MatchMode.SQUAD, Game.MatchMode.CHALLENGE,
			Game.MatchMode.ENDLESS, Game.MatchMode.TRAINING, Game.MatchMode.LAN],
		"摊平六种玩法，包含无尽")
	t.eq(MainMenu.all_modes().size(), 6, "五组对应六种玩法")
	# 恢复入口之后**反过来钉**：它必须在入口里（"藏起来"这件事结束了）。
	t.ok(MainMenu.all_modes().has(Game.MatchMode.CHALLENGE),
		"剧情挑战**在**入口里（1.2 隐藏 → 2026-09-29 恢复）")
	# 而且它**自成一组**：挑战不是"对战"的第三种形式，塞进对战模式子页会让
	# "选形式"那一步冒出一个不是形式的选项。
	t.not_ok(MainMenu.battle_modes().has(Game.MatchMode.CHALLENGE),
		"剧情挑战**不在**「对战模式」子页里（它不是对战的一种形式）")
	# 摊平不许有重复（重复 = 两个分组指向同一个模式，`select_mode()` 只认第一个）
	var uniq := {}
	for mode: int in MainMenu.all_modes():
		uniq[mode] = true
	t.eq(uniq.size(), MainMenu.all_modes().size(), "摊平后没有重复的模式")

	# ---- ③ 「对战模式」那一组恰好两项 ----
	t.eq(MainMenu.battle_modes(), [Game.MatchMode.VERSUS, Game.MatchMode.SQUAD],
		"「对战模式」子页 = 王牌战 + 小队战（顺序即显示顺序）")
	t.eq(int(MainMenu.battle_modes()[0]), Game.MatchMode.VERSUS,
		"子页第 0 项是王牌战（光标默认停这儿，且它是 `Game.MatchMode` 的本意）")
	t.ok(MainMenu.battle_modes() == MainMenu.MODE_GROUPS[MainMenu.BATTLE_GROUP]["modes"],
		"`battle_modes()` 就是那一组的 `modes` —— 不是第二份名单")
	t.eq(MainMenu.BATTLE_GROUP, 0, "「对战模式」是模式页第 0 行（`in_battle_group()` 读它）")

	# ---- ④ "要不要子页"由**数据**决定：全表只有一组超过一项 ----
	var multi := 0
	for g: Dictionary in MainMenu.MODE_GROUPS:
		var ms: Array = g["modes"]
		t.gt(float(ms.size()), 0.0,
			"分组「%s」至少有一项（空分组 = 按下去没反应）" % str(g["name"]))
		if ms.size() > 1:
			multi += 1
	t.eq(multi, 1, "全表只有一组有子页（多一组就多一层没人测的菜单）")

	# ---- ⑤ 单项分组**借** `mode_info()` 的文案，不写第二份 ----
	#
	# 这一条挡的是"同一件事有两种说法"：模式页上的「训练模式」必须是训练模式自己的
	# 文案，在这里另写一份就会改一处、另一处不动（本工程反复出问题的形状）。
	for i in MainMenu.MODE_GROUPS.size():
		var ms2: Array = MainMenu.MODE_GROUPS[i]["modes"]
		if ms2.size() != 1:
			continue
		var info := MainMenu.group_info(i)
		var mi := MainMenu.mode_info(int(ms2[0]))
		t.eq(str(info["name"]), str(mi["name"]),
			"单项分组第 %d 行的名字取自 `mode_info()`" % i)
		t.eq(info["lines"], mi["lines"],
			"……说明文字也是同一份（改一处不会两处对不上）")
	# 有子页的那一组用自己的文案（名字是"对战模式"，不是"王牌战"或"小队战"）
	t.eq(str(MainMenu.group_info(MainMenu.BATTLE_GROUP)["name"]), "对战模式",
		"有子页的那一行显示的是**类名**（对战模式），不是组内某一项的名字")
	t.gt(float(MainMenu.group_info(MainMenu.BATTLE_GROUP)["lines"].size()), 0.0,
		"那一行有说明文字（玩家要能看出进去是选什么的）")

	# ---- ⑥ 越界下标不许崩 ----
	var last := str(MainMenu.group_info(MainMenu.MODE_GROUPS.size() - 1)["name"])
	t.eq(str(MainMenu.group_info(99)["name"]), last, "越界的分组下标钳到最后一个（不是崩）")
	t.eq(str(MainMenu.group_info(-5)["name"]), str(MainMenu.group_info(0)["name"]),
		"负下标也钳到第 0 个（`clampi`，不是取到最后一个元素）")

	# ---- ⑦ 标题带下的面包屑：**从表里现推**，不是第二份名单 ----
	#
	# 这段字原来是写死的字符串，于是"恢复剧情挑战入口"之后**模式页四行、
	# 图上还三项** —— 而且**不报错**，只有人眼能看出来。
	# 判据两面一起钉：**内容对**（每一组都在、顺序对）**且**绘制侧调的是这个函数
	# （后者在 WIRING 分节里扫源码）。
	var crumb := MainMenu.modes_breadcrumb()
	var segs := crumb.split(" · ")
	t.eq(segs.size(), MainMenu.MODE_GROUPS.size(),
		"面包屑的段数 = 分组数（往表里加一组就自动多一段）")
	for i in MainMenu.MODE_GROUPS.size():
		var nm := str(MainMenu.group_info(i)["name"])
		t.ok(str(segs[i]).begins_with(nm), "第 %d 段以「%s」开头" % [i, nm])
	t.ok(crumb.contains("剧情挑战"), "面包屑里有「剧情挑战」（恢复入口之后它必须出现）")
	t.ok(crumb.contains("王牌战") and crumb.contains("小队战"),
		"有子页的那一组把两项都列出来（`对战模式（王牌战 / 小队战）`）")


# ---------------------------------------------------------------- 2 两层合成

static func _compose(t: T) -> void:
	var m := MainMenu.new()

	# ---- ① 王牌战 / 小队战是**同一个分组的两项** ----
	t.ok(m.select_mode(Game.MatchMode.VERSUS), "菜单能摆到王牌战")
	t.eq(int(m.get("mode_index")), MainMenu.BATTLE_GROUP, "王牌战在「对战模式」那一组")
	t.eq(int(m.get("battle_index")), 0, "王牌战是组内第 0 项")
	t.eq(m.selected_mode(), Game.MatchMode.VERSUS, "两层合成 ⇒ 王牌战")
	t.ok(m.in_battle_group(), "……而且 `in_battle_group()` 为真")

	t.ok(m.select_mode(Game.MatchMode.SQUAD), "菜单能摆到小队战")
	t.eq(int(m.get("mode_index")), MainMenu.BATTLE_GROUP, "小队战也在「对战模式」那一组")
	t.eq(int(m.get("battle_index")), 1, "小队战是组内第 1 项")
	t.eq(m.selected_mode(), Game.MatchMode.SQUAD, "两层合成 ⇒ 小队战")
	# 组内来回切**不换组**（换组会让"上一步按返回"回到错的地方）
	t.ok(m.select_mode(Game.MatchMode.VERSUS), "再切回王牌战")
	t.eq(int(m.get("mode_index")), MainMenu.BATTLE_GROUP, "组内切换不改分组")

	# ---- ② 单项分组（训练 / 联机）不看 `battle_index` ----
	#
	# ⚠️ 先把 `battle_index` 摆成"上次在王战页选的是小队战"，再切到训练：
	# 如果 `selected_mode()` 对单项分组也读 `battle_index`，它会越界或被钳成
	# 那一组唯一的一项（此刻恰好都是训练），于是**这条错会静默通过** ——
	# 所以判据要两条一起：结果对**且**那个下标没被顺手改掉。
	m.set("battle_index", 1)
	t.ok(m.select_mode(Game.MatchMode.TRAINING), "菜单能摆到训练")
	t.eq(m.selected_mode(), Game.MatchMode.TRAINING, "训练局不受上次「小队战」的影响")
	t.eq(int(m.get("battle_index")), 1, "……也没有顺手把组内下标改掉（下次回王战页还记得）")
	t.ok(m.training_mode(), "`training_mode()` 与 `selected_mode()` 一致")
	t.not_ok(m.in_battle_group(), "训练不在对战模式那一组")

	t.ok(m.select_mode(Game.MatchMode.LAN), "菜单能摆到联机")
	t.eq(m.selected_mode(), Game.MatchMode.LAN, "两层合成 ⇒ 联机")
	t.eq(int(m.get("mode_index")), MainMenu.MODE_GROUPS.size() - 1, "联机是模式页最后一行")
	t.not_ok(m.in_battle_group(), "联机不在对战模式那一组")

	# ---- ③ 找不到的模式：**什么都不改**（这条是"负下标"那个坑的门）----
	#
	# 老写法 `mode_index = MODES.find(mode)` 一旦找不到就是 **−1**，
	# 而 `current_group()` 用 `clampi` 读它 ⇒ 悄悄变成**第 0 组**（对战模式）——
	# 于是"测的是别的、实际测的是王牌战"。
	#
	# ⚠️ 反例**只能用不存在的编号**：剧情挑战恢复入口之后 `all_modes()` 已经把 5 个
	# 合法取值全收进去了 —— 再拿"某个真模式"当"找不到"的例子，这条门就自己消失了，
	# 而它守的恰恰是"将来谁又把某个模式挪出菜单"。
	var keep := int(m.get("mode_index"))
	var keep_mode := m.selected_mode()
	t.not_ok(m.select_mode(99), "不存在的模式编号 ⇒ `select_mode()` 返回 false")
	t.eq(int(m.get("mode_index")), keep, "……而且 `mode_index` 一个字都没改（不是 −1）")
	t.eq(m.selected_mode(), keep_mode, "……选中项照旧")
	# 负下标同样什么都不改 —— 而且它更危险：`clampi` 会把它读成第 0 组（对战模式）。
	t.not_ok(m.select_mode(-1), "负下标 ⇒ 也返回 false")
	t.eq(int(m.get("mode_index")), keep, "……`mode_index` 照样没动")

	# ---- ④ 四个 `*_mode()` 谓词：任意时刻**至多一个**为真 ----
	for mode: int in MainMenu.all_modes():
		t.ok(m.select_mode(mode), "菜单能摆到模式 %d" % mode)
		var hits := 0
		if m.squad_mode():
			hits += 1
		if m.training_mode():
			hits += 1
		if m.challenge_mode():
			hits += 1
		if m.lan_mode():
			hits += 1
		if m.endless_mode():
			hits += 1
		t.ok(hits <= 1, "模式 %d：四个谓词至多一个为真（两个 = 有两条路指向同一局）" % mode)
		if mode != Game.MatchMode.VERSUS:
			# 王牌战是"其它都不是"的那一支，所以它自己 0 个也算对。
			t.eq(hits, 1, "模式 %d 有且只有一个谓词认得它" % mode)
		# 剧情挑战**自己当然认得自己** —— 这一条只对别的模式成立。
		if mode != Game.MatchMode.CHALLENGE:
			t.not_ok(m.challenge_mode(), "模式 %d 不会被当成剧情挑战" % mode)

	# ---- ⑤ 子页**不是新的一步** ----
	#
	# 步骤条按"这件事做完没有"亮灯：子页还属于"① 选择模式"，所以步数不许 +1，
	# 否则整条流程条会指着后面所有页错一格（而且只在"对战模式"这一组错）。
	m.select_mode(Game.MatchMode.VERSUS)
	t.eq(m.step_count(), 5, "对战是 5 步（子页没有让它变成 6 步）")
	m.set("stage", MainMenu.Stage.BATTLE)
	t.eq(m.step_index(), 0, "子页算第 ① 步的一部分")
	m.select_mode(Game.MatchMode.SQUAD)
	m.set("stage", MainMenu.Stage.BATTLE)
	t.eq(m.step_index(), 0, "小队战走子页时也是第 ① 步")

	m.queue_free()


# ---------------------------------------------------------------- 3 版式

static func _layout(t: T) -> void:
	for view: Vector2 in [Vector2(1600, 900), Vector2(1280, 720), Vector2(1920, 1080)]:
		# ---- ① 4 行全放得下、不滚动（放不下就是"行和页脚提示叠在一起"）----
		var vis := MainMenu.rows_that_fit(view, MainMenu.MODE_ROW_H, MainMenu.MODE_ROW_GAP)
		t.ok(vis >= MainMenu.MODE_GROUPS.size(),
			"%s：模式页 %d 行全放得下（可见 %d 行）"
				% [view, MainMenu.MODE_GROUPS.size(), vis])
		t.eq(MainMenu.scroll_window(MainMenu.MODE_GROUPS.size(),
			MainMenu.MODE_GROUPS.size() - 1, vis),
			Vector2i(0, MainMenu.MODE_GROUPS.size()),
			"%s：模式页放得下 ⇒ 不滚动（永远不动的滚动条会被当成「下面还有」）" % view)

		# ---- ② 四行的行块整体落在内容区里 ----
		var met := MainMenu.list_metrics(view, MainMenu.MODE_GROUPS.size(), MainMenu.MODE_ROW_H,
			MainMenu.MODE_ROW_GAP, MainMenu.MODE_ROW_MAX)
		t.eq(int(met["shown"]), MainMenu.MODE_GROUPS.size(),
			"%s：四行全都真画得出来（没有行被挤出面板）" % view)
		t.gt(float(met["top"]), MainMenu.PANEL_TOP - 0.001, "%s：模式页行块顶不高于内容区顶" % view)
		t.lt(MainMenu.list_bottom_y(0, int(met["shown"]), met),
			MainMenu.content_bottom(view) + 0.001, "%s：模式页行块底不越出内容区底" % view)
		for i in MainMenu.MODE_GROUPS.size():
			var r: Rect2 = MainMenu.mode_row_rect(view, i)
			t.gt(r.position.y, MainMenu.PANEL_TOP - 0.001, "%s：模式页第 %d 行不高于内容区顶" % [view, i])
			t.lt(r.position.y + r.size.y, MainMenu.content_bottom(view) + 0.001,
				"%s：模式页第 %d 行不越出内容区底" % [view, i])
			t.lt(r.position.y + r.size.y, MainMenu.hint_y(view),
				"%s：模式页第 %d 行不压页脚提示行" % [view, i])

		# ---- ③ 子页两行：与模式页**同一套**版式（同一个 `_draw_list_row()`）----
		var b0 := MainMenu.battle_row_rect(view, 0)
		var b1 := MainMenu.battle_row_rect(view, 1)
		t.gt(b1.position.y, b0.position.y, "%s：子页竖排（y 递增）" % view)
		t.eq(b1.position.x, b0.position.x, "%s：子页不是横排（x 相同）" % view)
		t.gt(b1.position.y + 0.001, b0.position.y + b0.size.y,
			"%s：子页两行一行接一行（不重叠）" % view)
		t.lt(b1.position.y + b1.size.y, MainMenu.content_bottom(view) + 0.001,
			"%s：子页第二行不越出内容区底" % view)
		t.lt(b1.position.y + b1.size.y, MainMenu.hint_y(view), "%s：子页不压页脚提示行" % view)
		# 子页与模式页的行矩形必须是**同一套版式参数**：行数不同时"行高"可以不同
		#（自适应），但行的**左边界与宽度**是同一个 —— 差一档就会一眼看出没排过版。
		t.eq(b0.position.x, MainMenu.mode_row_rect(view, 0).position.x,
			"%s：子页与模式页左边界对齐" % view)
		t.eq(b0.size.x, MainMenu.mode_row_rect(view, 0).size.x,
			"%s：子页与模式页行宽一致" % view)

	# ---- ④ 轴：子页画的是竖排行 ⇒ 必须走竖轴 ----
	#
	# "版式与轴相反"在这个工程里踩过两次（敌人页、阵营页）。判据不是"抄结论"，
	# 而是上面的几何量法 + 这里的轴必须一致。
	t.eq(MainMenu.nav_axis(MainMenu.Stage.BATTLE), MainMenu.Nav.Y,
		"「对战模式」子页用竖轴（W / S，与它画出来的竖排行一致）")
	t.not_ok(MainMenu.nav_axis(MainMenu.Stage.BATTLE) == MainMenu.Nav.X,
		"……不是横轴")


# ---------------------------------------------------------------- 4 接线扫描

## 绘制与输入的接线：这类"改一处漏一处"的地方只能扫源码。
static func _wiring(t: T) -> void:
	var src := SuiteUiStyle._code("scripts/ui/main_menu.gd")

	# ---- ① 两页都有绘制分支 ----
	var draw_body := SuiteMenuFrame._func_body(src, "func _draw()")
	t.ok(draw_body.contains("Stage.BATTLE:"), "`_draw()` 里有「对战模式」子页的分支")
	t.ok(draw_body.contains("_draw_battle_stage()"), "         …并调 `_draw_battle_stage()`")
	t.ok(src.contains("func _draw_battle_stage()"), "`_draw_battle_stage()` 存在")
	# 子页也要有页脚提示（漏了的表现是"这一页没有操作说明"）
	t.ok(SuiteMenuFrame._func_body(src, "func _draw_battle_stage()").contains("_draw_hint("),
		"子页有页脚操作说明（走 `_draw_hint()`）")

	# ---- ② 行数取的是**分组数**，不是模式数 ----
	#
	# 这一条是整套里最要紧的一条：把 5（模式数）当行数用，最后一行就会排到面板外面，
	# 而**画的时候看不出来**（多画的一行在窗口外，恰好也不报错）。
	t.ok(SuiteMenuFrame._func_body(src, "func _draw_mode_stage()").contains("MODE_GROUPS.size()"),
		"模式页按 `MODE_GROUPS.size()`（4）画")
	t.ok(SuiteMenuFrame._func_body(src, "func mode_row_rect(").contains("MODE_GROUPS.size()"),
		"`mode_row_rect()` 也按 `MODE_GROUPS.size()` 算（测试量的是绘制侧那个函数）")
	t.ok(SuiteMenuFrame._func_body(src, "func battle_row_rect(").contains("battle_modes().size()"),
		"子页按 `battle_modes().size()`（2）算行数")
	# `all_modes()` 只用来回答"哪些模式存在"，**不许**出现在版式里
	for head: String in ["func _draw_mode_stage()", "func _draw_battle_stage()",
			"func _draw_lan_stage()"]:
		t.not_ok(SuiteMenuFrame._func_body(src, head).contains("all_modes().size()"),
			"`%s` 里没有拿 `all_modes().size()` 当行数用" % head)

	# ---- ③ 「要不要子页」由数据决定，不点名"对战模式" ----
	var mode_body := SuiteMenuFrame._func_body(src, "func _read_input()")
	# ⚠️ 2026-10-11：这条规则搬进了 `mode_entry_stage()`（模式页两个入口共用
	# ⇒ 唯一真源）。判据跟着规则走，扫的还是同一句话。
	t.ok(SuiteMenuFrame._func_body(src, "func mode_entry_stage(")
			.contains("current_group()[\"modes\"].size() > 1"),
		"确认键按**数据**决定进不进子页（`modes.size() > 1`）")

	# ---- ④ 子页的输入分支在位（上下选 + 确认 + 返回）----
	var battle_in := mode_body.substr(mode_body.find("Stage.BATTLE:"))
	t.ok(battle_in.contains("battle_modes().size()"), "子页的上下键按 `battle_modes().size()` 循环")
	t.ok(battle_in.contains("Stage.MODE"), "子页按返回回到模式页")
	t.ok(battle_in.contains("side_filters_suits()"),
		"子页确认时按「要不要阵营页」分流（小队战要、王牌战不要）")

	# ---- ⑤ 从子页进去的页，返回要回子页 ----
	# 漏了的表现是"从王战页选机体、按返回跳回模式页"（少一层，玩家要多按一次）。
	var back_to_sub := src.count("Stage.BATTLE if in_battle_group() else Stage.MODE")
	t.ok(back_to_sub >= 2,
		"阵营页与机体页的返回都按「来的那一组」回（找到 %d 处）" % back_to_sub)

	# ---- ⑥ 模式页的面包屑不许是字面量 ----
	# 它以前是写死的，所以"恢复剧情挑战入口"之后模式页四行、图上还三项 —— 不报错。
	# 这一条与上面 `_groups()` 的 ⑦ 是一对：那边验内容，这边验**来源**。
	t.ok(src.contains("static func modes_breadcrumb()"), "`modes_breadcrumb()` 存在")
	t.ok(SuiteMenuFrame._func_body(src, "func _draw_mode_stage()").contains("modes_breadcrumb()"),
		"模式页的面包屑调 `modes_breadcrumb()`（不是写死的字符串）")
	t.not_ok(SuiteMenuFrame._func_body(src, "func _draw_mode_stage()").contains("训练模式 · "),
		"……而且那里**没有**手写那串名字（有一份字面量就还有第二份真源）")
