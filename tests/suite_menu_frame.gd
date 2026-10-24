class_name SuiteMenuFrame
extends RefCounted
## 主菜单**纵向骨架**测试（批 29："下面这块太空了"的机械判据）。
##
## ## 这一套守的是哪件事
## 用户报的是"主菜单下面这部分太空了，各个子菜单也一样"。这条反馈**不是审美**，
## 而是三个可量的几何事实叠在一起：
##   ① 内容区底边是**写死的 660**（`LIST_END`）—— 900 高的窗口里 660..900 永远空着；
##   ② 页脚提示行"跟在内容下面"，于是内容短的时候它浮在屏幕中上部；
##   ③ 星空也只铺到 660，那一带连背景颗粒都没有。
##
## 所以判据全部落在**几何**上：内容区随屏幕高伸缩、行高自适应、整块居中、
## 提示行锚底、行块不越界。`suite_layout` / `suite_round` 继续守"对齐线"，
## 这一套守"纵向分配"。
##
## ⚠️ 这里同样**不写死数字结论**：能放几行、行高多少，都是从
## `MainMenu.list_metrics()` 现算的。测试只断言"性质"（在范围内 / 不越界 / 居中对齐），
## 这样下次改内容（加模式、加机体、加设置项）不会先把测试改一遍。

const VIEWS := [Vector2(1600, 900), Vector2(1280, 720), Vector2(1920, 1080), Vector2(1600, 1000)]

## `_pages()` 里"这一行用哪个行矩形函数"的三种取值。
##
## ⚠️ 本轮把原来那个 bool（`true` = 模式页 / `false` = 难度页）换成三值枚举，
## 是因为**模式页与「对战模式」子页共用同一个 `mode_row_rect()` 已经不够了** ——
## 子页的行数不同（2 行 vs 4 行），量它必须用 `battle_row_rect()`。
## 仍然留着 bool 会让"子页其实量的是模式页的版式"这种错**静默通过**。
const _ROW_MODE := 0
const _ROW_BATTLE := 1
const _ROW_DIFF := 2


## 按 `_ROW_*` 选行矩形函数（`_pages()` 用；三者的版式必须同源）。
static func _row_rect(kind: int, view: Vector2, i: int) -> Rect2:
	match kind:
		_ROW_BATTLE:
			return MainMenu.battle_row_rect(view, i)
		_ROW_DIFF:
			return MainMenu.difficulty_row_rect(view, i)
	return MainMenu.mode_row_rect(view, i)


static func run(t: T, _host: Node) -> void:
	t.suite("MenuFrame / 内容区随屏幕高伸缩")
	_content_band(t)
	t.suite("MenuFrame / 列表版式引擎")
	_metrics(t)
	t.suite("MenuFrame / 各页行块都落在内容区内")
	_pages(t)
	t.suite("MenuFrame / 绘制侧接线（源码扫描）")
	_wiring(t)


## 内容区三段：标题带 → 内容区 → 页脚提示带。**底边由屏幕高算**，不是常数。
static func _content_band(t: T) -> void:
	for view: Vector2 in VIEWS:
		var want := view.y - UILayout.MARGIN - MainMenu.HINT_BAND
		t.near(MainMenu.content_bottom(view), want, 0.001,
			"%s：内容区底边 = 屏幕高 − MARGIN − 页脚带" % view)
		t.near(MainMenu.content_height(view), want - MainMenu.PANEL_TOP, 0.001,
			"%s：内容区高度 = 底边 − PANEL_TOP" % view)
		# 内容区必须"装得住东西"：批 24 那版只有 436（190..626），
		# 而且 900 高下它下面还白白空着 240。这里钉住"至少不比那版小"。
		t.gt(MainMenu.content_height(view), 430.0, "%s：内容区高度 ≥ 430（不是一条缝）" % view)
		# 内容区底边必须在屏幕内（离底还有 MARGIN + 页脚带）
		t.lt(MainMenu.content_bottom(view), view.y - UILayout.MARGIN - 20.0,
			"%s：内容区底边在屏幕底之上（页脚带留给提示行）" % view)
		# 提示行锚底：在内容区**之下**、屏幕**之内**。
		var hy := MainMenu.hint_y(view)
		t.near(hy, view.y - MainMenu.HINT_BASELINE_LIFT, 0.001,
			"%s：提示行锚定屏幕底边" % view)
		t.gt(hy, MainMenu.content_bottom(view) - 0.001,
			"%s：提示行在内容区之下（不跟列表叠字）" % view)
		t.lt(hy, view.y - 10.0, "%s：提示行在屏幕内（下面还留得出呼吸）" % view)
	# 标题带与内容区不重叠（页面切换时"上面的字不跳"，这条一直成立）
	t.lt(MainMenu.TITLE_TOP + MainMenu.TITLE_BAND, MainMenu.PANEL_TOP,
		"标题带在内容区之上（每页都一样高）")


## 列表版式引擎：`list_metrics()` 的性质。**不写死任何数字结论**。
static func _metrics(t: T) -> void:
	var min_h := MainMenu.MODE_ROW_H
	var gap := MainMenu.MODE_ROW_GAP
	var max_h := MainMenu.MODE_ROW_MAX
	for view: Vector2 in VIEWS:
		var prev_h := INF
		for count in range(1, 15):
			var m := MainMenu.list_metrics(view, count, min_h, gap, max_h)
			var row_h := float(m["row_h"])
			var shown := int(m["shown"])
			var top := float(m["top"])
			var block := float(m["block_h"])

			t.between(row_h, min_h, max_h + 0.001,
				"%s / %d 行：行高钳在 [min, max] 内" % [view, count])
			t.between(float(shown), 1.0, float(count) + 0.001,
				"%s / %d 行：至少画 1 行、不多于总数" % [view, count])
			t.ok(block <= MainMenu.content_height(view) + 0.001,
				"%s / %d 行：整块装得进内容区（%.1f ≤ %.1f）"
					% [view, count, block, MainMenu.content_height(view)])
			t.gt(top, MainMenu.PANEL_TOP - 0.001, "%s / %d 行：行块顶不高于内容区顶" % [view, count])
			t.lt(top + block, MainMenu.content_bottom(view) + 0.001,
				"%s / %d 行：末行底不越出内容区底" % [view, count])
			# 放得下的行数：行数越多，行高**单调不增**（这就是"自适应"的定义）
			t.ok(row_h <= prev_h + 0.001,
				"%s：%d 行的行高 ≤ %d 行（行多则矮）" % [view, count, count - 1])
			prev_h = row_h
			# `fit` 与 `rows_that_fit()` 必须同源（两处算法分家就是两个真源）
			t.eq(int(m["fit"]), MainMenu.rows_that_fit(view, min_h, gap),
				"%s / %d 行：fit 与 rows_that_fit() 同源" % [view, count])
		# 居中：上留白 ≈ 下留白（内容块在内容区里垂直居中，不许偏一头）
		var m2 := MainMenu.list_metrics(view, 3, 96.0, 16.0, 136.0)
		var up := float(m2["top"]) - MainMenu.PANEL_TOP
		var down := MainMenu.content_bottom(view) - (float(m2["top"]) + float(m2["block_h"]))
		t.near(up, down, 1.0, "%s：三行的行块在内容区里居中（上 %.1f / 下 %.1f）" % [view, up, down])
		# reserve（列表面板的内边距）要算进总高：面板高 = 行块 + 上下内边距
		var m3 := MainMenu.list_metrics(view, 13, 36.0, 0.0, 52.0,
			MainMenu.PANEL_PAD_TOP, MainMenu.PANEL_PAD_BOTTOM)
		t.ok(float(m3["block_h"]) + MainMenu.PANEL_PAD_TOP + MainMenu.PANEL_PAD_BOTTOM
			<= MainMenu.content_height(view) + 0.001,
			"%s：带内边距的列表面板也装得进内容区" % view)
	# 至少一行（空列表也不许变成"什么都没画"的空页）
	var empty := MainMenu.list_metrics(Vector2(1600, 900), 0, min_h, gap, max_h)
	t.eq(int(empty["shown"]), 1, "0 行的页也保底画 1 行（空页比排得难看更难查）")


## 各页的行矩形：都在内容区里，且**提示行不压最后一行的底**。
static func _pages(t: T) -> void:
	for view: Vector2 in VIEWS:
		# 模式 / 难度 / 地图（静态行矩形函数就是绘制侧用的那一个）
		#
		# ⚠️ 模式页的行数是 `MODE_GROUPS.size()`（**4 组**），不是
		# `all_modes().size()`（5 个模式）—— 把「王牌战 / 小队战」收进一个
		# 「对战模式」子页、又恢复剧情挑战入口之后，这两个数就不是同一个数了。
		# 「对战模式」子页与模式页**共用同一套版式**（同一个 `_draw_list_row()`），
		# 所以它也一起量。
		for pair: Array in [["模式", MainMenu.MODE_GROUPS.size(), _ROW_MODE],
				["对战模式", MainMenu.battle_modes().size(), _ROW_BATTLE],
				["难度", MainMenu.LEVELS.size(), _ROW_DIFF]]:
			var count: int = pair[1]
			for i in count:
				var r: Rect2 = _row_rect(int(pair[2]), view, i)
				t.gt(r.position.y, MainMenu.PANEL_TOP - 0.001, "%s：第 %d 行不高于内容区顶" % [pair[0], i])
				t.lt(r.position.y + r.size.y, MainMenu.content_bottom(view) + 0.001,
					"%s：第 %d 行不越出内容区底" % [pair[0], i])
		# 行矩形是**竖排**且互不重叠（版式换了但没换轴的那类事故由 suite_round 抓）
		t.gt(MainMenu.mode_row_rect(view, 1).position.y + 0.001,
			MainMenu.mode_row_rect(view, 0).position.y + MainMenu.mode_row_rect(view, 0).size.y,
			"%s：模式行一行接一行（不重叠）" % view)
		# 「对战模式」子页同理 —— 它与模式页共用 `_draw_list_row()`，
		# 所以只有行数不同（2 行 vs 4 行），版式必须一样规整。
		t.gt(MainMenu.battle_row_rect(view, 1).position.y + 0.001,
			MainMenu.battle_row_rect(view, 0).position.y
				+ MainMenu.battle_row_rect(view, 0).size.y,
			"%s：对战模式子页两行也不重叠" % view)

		# 机体卡：等高、够宽、在内容区里（卡高由内容区算）
		var cards := MainMenu.suit_card_rects(view)
		t.between(MainMenu.card_h(view), MainMenu.CARD_H_MIN, MainMenu.CARD_H_MAX + 0.001,
			"%s：卡片高度钳在 [CARD_H_MIN, CARD_H_MAX]" % view)
		t.gt(MainMenu.cards_top(view), MainMenu.PANEL_TOP - 0.001, "%s：卡片顶不高于内容区顶" % view)
		t.lt(MainMenu.cards_top(view) + cards[0].size.y, MainMenu.content_bottom(view) + 0.001,
			"%s：卡片底不越出内容区底" % view)
		for i in cards.size():
			t.near(cards[i].size.y, MainMenu.card_h(view), 0.001, "%s：第 %d 张卡高 = card_h()" % [view, i])

		# 列表面板（设置 / 选歌 / 重绑）：面板整体在内容区里
		var sm := MainMenu.settings_metrics(view)
		var sp := MainMenu.settings_panel_rect(view)
		t.gt(sp.position.y, MainMenu.PANEL_TOP - 0.001, "%s：设置面板顶不高于内容区顶" % view)
		t.lt(sp.position.y + sp.size.y, MainMenu.content_bottom(view) + 1.0,
			"%s：设置面板底不越出内容区底" % view)
		t.lt(MainMenu.list_bottom_y(0, int(sm["shown"]), sm), MainMenu.content_bottom(view) + 0.001,
			"%s：设置页末行不越出内容区底" % view)

		# 提示行不压内容：最后一行的底 < 提示行基线
		var last_bottom := MainMenu.list_bottom_y(0, int(sm["shown"]), sm)
		t.lt(last_bottom, MainMenu.hint_y(view), "%s：设置页末行底在提示行之上" % view)
		var dm := MainMenu.list_metrics(view, MainMenu.LEVELS.size(), MainMenu.ROW_H,
			MainMenu.ROW_GAP, MainMenu.ROW_MAX)
		t.lt(MainMenu.list_bottom_y(0, int(dm["shown"]), dm), MainMenu.hint_y(view),
			"%s：难度页末行底在提示行之上" % view)


## 绘制侧接线：源码扫描。
##
## 这几条都是"改版之后容易漏掉、但玩家一眼看得出来"的地方 ——
## 例如星空忘了铺满（下半屏一片黑）、某页忘了改提示行（提示行留在屏幕中上部）。
static func _wiring(t: T) -> void:
	var src := SuiteUiStyle._code("scripts/ui/main_menu.gd")

	# ① 星空铺满整个屏幕：用 `size.y`，不许再出现写死的 660 / LIST_END。
	var star := _func_body(src, "func _draw_starfield()")
	t.ok(star.contains("size.y"), "星空按屏幕高铺满（不再是 660 那一条线）")
	t.not_ok(star.contains("660"), "星空里没有写死的 660")

	# ② 旧的"列表安全线"常量彻底退役（留着它就会有人再拿它算布局）
	t.not_ok(src.contains("const LIST_END"), "`LIST_END` 常量已退役（底边由屏幕高算）")
	t.not_ok(src.contains("func list_bottom()"), "旧的 `list_bottom()` 已退役")

	# ③ 提示行一律锚底：各页都走 `_draw_hint()`（它内部取 `hint_y(size)`），
	#    少数几页直接在页脚画状态文字（重绑页的冲突提示、模式页的退出确认）
	#    也必须落在同一个 y 上 —— 所以 `hint_y(size)` 本身也要在源码里出现。
	t.gt(float(src.count("_draw_hint(")), 10.0,
		"各页页脚都走 `_draw_hint()`（找到 %d 处）" % src.count("_draw_hint("))
	t.gt(float(src.count("hint_y(size)")), 1.0,
		"页脚 y 由 `hint_y(size)` 给（锚定屏幕底边）")
	var m := RegEx.new()
	m.compile("_draw_hint\\(\\s*[^\"\\n]*position\\.y")
	t.eq(m.search_all(src).size(), 0,
		"没有哪一页还在用「面板底」当提示行的 y（那种写法会让提示行浮在半空）")

	# ④ 行内基线走助手：行高会变，写死 `r.position.y + 38.0` 会让字贴在行顶
	t.gt(float(src.count("text_vcenter(")), 5.0,
		"行内单行文字用 `text_vcenter()`（找到 %d 处）" % src.count("text_vcenter("))
	t.gt(float(src.count("baseline_block(")), 5.0,
		"行内多行文字块用 `baseline_block()`（找到 %d 处）" % src.count("baseline_block("))

	# ⑤ 列表页统一走引擎：不许有页面自己"按行号手算 y"
	t.gt(float(src.count("list_metrics(")), 8.0,
		"各列表页都从 `list_metrics()` 取版式（找到 %d 处）" % src.count("list_metrics("))


## 取一个函数体的源码（从 `head` 到下一个顶层 `func` 之前）。
static func _func_body(src: String, head: String) -> String:
	var at := src.find(head)
	if at < 0:
		return ""
	var rest := src.substr(at + head.length())
	var nxt := rest.find("\nfunc ")
	return rest.substr(0, nxt) if nxt >= 0 else rest
