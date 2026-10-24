class_name SuiteLayout
extends RefCounted
## 三屏对齐测试：**主菜单 / 战斗 HUD / 结算菜单**共用同一套版式网格。
##
## ## 为什么这件事要写成测试
## 用户报的是"对齐一下结算菜单 ui、战斗界面的弹药 ui、开始菜单的 ui"。
## 对齐靠肉眼看截图是说不清的 —— 截图里差 6 像素和差 30 像素都只是"有点怪"。
## 所以版式被抽成纯函数（`UILayout` / `FlightHUD.result_layout` / `MainMenu.settings_panel_rect`），
## 这里直接断言三条线在三个界面上**是同一个数**：
##
##   1. 外框线：结算两栏 == 主菜单各面板 == `[MARGIN, view.x − MARGIN]`
##      （1.2.1 批 2 起**高度带**也落在这一条线上：它紧贴屏幕右缘）
##   2. 数值线：HUD 弹药栏数值列 == 结算"损耗与战果"数值列 == `content_right()`
##      ⚠️ **HUD 高度块是例外**：它让开了高度带的带宽，用 `UILayout.alt_value_right()`。
##      这不是"对齐松了口"，而是"带压住数字"与"差 16 px"之间选了后者 ——
##      见 `alt_value_right()` 的注释。下面仍然对它有断言（必须在带左侧）。
##   3. 标签线：HUD 左侧信息块 == 结算两栏行标签 == `content_left()`
##
## 顺带钉住一个真踩过的 bug：`draw_string(..., HORIZONTAL_ALIGNMENT_RIGHT, -1, ...)`
## 在 Godot 里**不会**右对齐（宽度为 −1 时对齐参数被忽略），文本依旧从锚点往右画 ——
## 于是 HUD 右半边和结算数值列全都冲出屏幕。这个只能靠"右端位置"的断言兜住，
## 所以下面连"右端不越界"也一起断言。

const VIEWS := [Vector2(1600, 900), Vector2(1280, 720), Vector2(1920, 1080), Vector2(1600, 1000)]


static func run(t: T, _host: Node) -> void:
	t.suite("Layout / 网格常量")
	_constants(t)
	t.suite("Layout / 三屏共用同一条外框线")
	_frames(t)
	t.suite("Layout / 三屏共用同一条数值线与标签线")
	_columns(t)
	t.suite("Layout / 右对齐不越界")
	_bounds(t)
	t.suite("Layout / 主菜单也在同一套网格上")
	_menu(t)
	t.suite("Layout / 主菜单标题 LOGO")
	_logo(t)


static func _constants(t: T) -> void:
	var view := Vector2(1600, 900)
	t.near(UILayout.MARGIN, 24.0, 0.001, "屏幕外框留白 24")
	t.near(UILayout.PAD, 30.0, 0.001, "面板内容留白 30")
	t.near(UILayout.content_left(view), 54.0, 0.001, "内容区左边界 = 24 + 30 = 54")
	t.near(UILayout.content_right(view), view.x - 54.0, 0.001, "内容区右边界 = 1600 − 54")
	t.near(UILayout.content_width(view), view.x - 108.0, 0.001, "内容区宽度 = 屏幕宽 − 108")
	t.near(UILayout.frame_width(view), view.x - 48.0, 0.001, "面板外框宽度 = 屏幕宽 − 48")


## 外框线：结算两栏的最外两条边 == `[MARGIN, view.x − MARGIN]`。
## ⚠️ 批 24：主菜单底部「操作说明」面板已删除（用户："这块板没人看"），
## 帮助面板的对齐断言随之退役 —— 外框线对齐改由设置面板（`_menu`）继续看守。
static func _frames(t: T) -> void:
	for view: Vector2 in VIEWS:
		var boxes: Array = FlightHUD.result_layout(view)["boxes"]
		var l: Rect2 = boxes[0]
		var r: Rect2 = boxes[boxes.size() - 1]

		t.near(l.position.x, UILayout.MARGIN, 0.001, "%s：结算左栏外框 = MARGIN" % view)
		t.near(r.position.x + r.size.x, view.x - UILayout.MARGIN, 0.001,
			"%s：结算右栏外框 = 屏幕宽 − MARGIN" % view)


## 数值线 / 标签线：三屏的列必须落同一个 x。
static func _columns(t: T) -> void:
	for view: Vector2 in VIEWS:
		var geo := FlightHUD.result_layout(view)
		var cols := UILayout.ammo_columns(view)
		var want_value := UILayout.content_right(view)
		var want_label := UILayout.content_left(view)

		# 战斗 HUD：右下角弹药栏的数值列（这一条与结算菜单**严格同线**）
		t.near(float(cols["value"]), want_value, 0.001,
			"%s：HUD 弹药栏数值列右端 = content_right" % view)
		# 战斗 HUD：右上角高度块 —— 批 2 起它让开了高度带的带宽，
		# 所以它落的是 `alt_value_right()` 而不是 `content_right()`。
		# 两条都必须由 `UILayout` 唯一给出，否则"高度带压住数字"会以
		# "看着有点挤、但说不上哪挤"的形式回来。
		var av := UILayout.alt_value_right(view)
		t.lt(av, UILayout.alt_tape_rect(view).position.x,
			"%s：HUD 高度块数值列在高度带左侧" % view)
		t.lt(av, want_value, "%s：HUD 高度块数值列在 content_right 左侧" % view)
		t.gt(av, want_value - 40.0, "%s：高度块只让开带宽那一段（不留空沟）" % view)
		# 结算菜单：右栏数值列的右端
		t.near(float(geo["value_x"]), want_value, 0.001,
			"%s：结算数值列右端 = HUD 弹药栏数值列（同一根线）" % view)
		# 结算菜单：行标签的左端 = HUD 左侧信息块（content_left）
		t.near(float(geo["label_x"]), want_label, 0.001,
			"%s：结算行标签左端 = content_left" % view)

		# 列间距仍然是"键位在最左、数值在最右"，且不重叠
		t.lt(float(cols["key"]), float(cols["name"]), "%s：键位列在名称列左侧" % view)
		t.lt(float(cols["name"]), float(cols["value"]), "%s：名称列在数值列左侧" % view)
		# ⚠️ **弹匣条占的就是数值列那一段**，所以名称列必须整个让开它。
		# 这一条是用户报的"光束步枪子弹 UI 和文字冲突重叠"的回归：
		# 名称列原本只往回让 82 px，而条宽 116 px —— 条直接盖在"换弹"两个字上。
		t.gt(UILayout.AMMO_NAME_BACK_FROM_VALUE, UILayout.AMMO_BAR_W,
			"名称列右端在弹匣条左侧（让开 %.0f > 条宽 %.0f）"
			% [UILayout.AMMO_NAME_BACK_FROM_VALUE, UILayout.AMMO_BAR_W])
		t.gt(UILayout.AMMO_KEY_BACK_FROM_VALUE - UILayout.AMMO_NAME_BACK_FROM_VALUE,
			64.0, "键位列与名称列之间容得下最长的名称（4 个汉字 ≈ 56 px）")
		# 结算数值列必须落在右栏**里面**
		var boxes: Array = geo["boxes"]
		var r: Rect2 = boxes[1]
		t.gt(float(geo["value_x"]), r.position.x, "%s：结算数值列在右栏内（左端）" % view)
		t.lt(float(geo["value_x"]), r.position.x + r.size.x + 0.001,
			"%s：结算数值列不越出右栏（右端）" % view)


## 右对齐的"不越界"：所有右对齐锚点都必须留出 MARGIN 的余量，
## 否则 `draw_string` 只要不走右对齐就会把字画出屏幕（这正是修掉的那个 bug）。
static func _bounds(t: T) -> void:
	for view: Vector2 in VIEWS:
		var right := UILayout.content_right(view)
		t.lt(right, view.x - UILayout.MARGIN, "%s：数值线离屏幕右缘还有 MARGIN 余量" % view)
		t.gt(right, view.x * 0.5, "%s：数值线在屏幕右半边（不会跑到中间去）" % view)
		var cols := UILayout.ammo_columns(view)
		t.gt(float(cols["key"]), view.x * 0.5, "%s：弹药栏三列都在右半边" % view)
		t.gt(float(cols["key"]), float(cols["value"]) - UILayout.AMMO_KEY_BACK_FROM_VALUE - 10.0,
			"%s：键位列不会离数值列更远（弹药栏不会散开）" % view)


## 主菜单同样不许"自成一格"。
##
## 改之前它一屏里有四个宽度：机体卡 500×2（居中）、难度行 760（居中）、
## 设置面板 620（居中）、底部操作说明面板通栏 —— 四条互不重合的边。
## 现在四块面板全部铺到外框线，卡片里的数值列还落在全局数值线上。
##
## 1.1：机体卡从两张变三张（加进阿利宙斯），所以断言改成**对任意张数都成立**
## 而不是写死"第一张贴左线、第二张贴右线"—— 写死的话下次加一台机又要改一遍测试。
static func _menu(t: T) -> void:
	for view: Vector2 in VIEWS:
		var cards := MainMenu.suit_card_rects(view)
		var rows: Array[Rect2] = []
		for i in 3:
			rows.append(MainMenu.difficulty_row_rect(view, i))
		var settings := MainMenu.settings_panel_rect(view)
		var n := cards.size()

		# 1) 面板外框线：四块面板全在同一条线上。
		#    机体卡是"拼"出来的（首卡贴左线、末卡贴右线、中间留缝），所以分开断言。
		t.eq(n, MainMenu.SUITS.size(), "机体卡张数 = 可选机体数（%d）" % n)
		for r: Rect2 in ([cards[0], rows[0], settings] as Array[Rect2]):
			t.near(r.position.x, UILayout.MARGIN, 0.001, "%s：面板左边 = MARGIN" % view)
		for r: Rect2 in ([cards[n - 1], rows[0], settings] as Array[Rect2]):
			t.near(r.position.x + r.size.x, view.x - UILayout.MARGIN, 0.001,
				"%s：面板右边 = 屏幕宽 − MARGIN" % view)
		var span: float = cards[n - 1].position.x + cards[n - 1].size.x - cards[0].position.x
		t.near(span, UILayout.frame_width(view), 0.001,
			"%s：全部机体卡 + 缝隙 = 整个外框宽度" % view)

		# 2) 卡片等宽等高、彼此不重叠
		for i in n:
			t.near(cards[i].size.x, cards[0].size.x, 0.001, "%s：第 %d 张卡与首卡等宽" % [view, i])
			t.near(cards[i].size.y, cards[0].size.y, 0.001, "%s：第 %d 张卡与首卡等高" % [view, i])
		for i in range(1, n):
			t.gt(cards[i].position.x, cards[i - 1].position.x + cards[i - 1].size.x,
				"%s：第 %d 张卡与前一张之间有间隙" % [view, i])
			t.near(cards[i].position.x, cards[i - 1].position.x + cards[i - 1].size.x
				+ MainMenu.PANEL_GAP, 0.001, "%s：第 %d 张卡紧跟上一张（间隔 = PANEL_GAP）" % [view, i])

		# 3) 卡片里的文字：左端 = content_left，数值列右端 = content_right（全局数值线）
		t.near(cards[0].position.x + UILayout.PAD, UILayout.content_left(view), 0.001,
			"%s：卡片内文字左端 = content_left" % view)
		var last: Rect2 = cards[n - 1]
		t.near(last.position.x + last.size.x - UILayout.PAD, UILayout.content_right(view), 0.001,
			"%s：卡片内数值列右端 = content_right（与 HUD/结算同一条线）" % view)

		# 3.5) 卡片数：**物理容量是 3，但"名单可以有 4 台"**（2026-09-29 加横向窗口之后）。
		#
		#      这一段在 2026-09-29 改过一次口径，值得写清楚**为什么不是放宽**：
		#      原来是"每一份在用的名单都必须 ≤ max_cards"。马夫蒂侧加进梅萨指挥官型 /
		#      F01型之后变成 4 台，那条断言当场成了障碍 —— 但障碍的**根因不是门槛太高**，
		#      而是当时的版式**没有"放不下"的出路**（§4.7 第 5 项当年两条都不做）。
		#      现在出路有了（`MainMenu.suit_window()`），门槛**换了位置**：
		#        从「名单 ≤ 容量」换成「容量 ≤ 物理容量 ∧ 名单里每一台都能滚进窗口」。
		#      ⇒ 新口径**更强**：它逐台量"选得到"，而不只是量总数。
		#      ① 常量本身是被算出来的，所以重算一遍核对（防止有人顺手调松它）：
		var calc := (UILayout.frame_width(Vector2(1280, 720))
			- MainMenu.PANEL_GAP * 2.0) / 3.0
		t.near(MainMenu.CARD_MIN_W, calc, 0.001,
			"CARD_MIN_W = 1280 宽下三张卡的实际宽度（%.3f）" % calc)
		#      ② 物理天花板仍然是 3：**不许靠压窄卡片来多塞一台**（那会破上面的下限）。
		t.eq(MainMenu.max_cards(Vector2(1280, 720)), 3,
			"%s：1280 下最多排 3 张（第 4 台靠窗口滚，不靠压窄）" % view)
		t.lt(MainMenu.max_cards(Vector2(1280, 720)), 4,
			"%s：第 4 台排不下（上一条的反面，写出来给下一个加机的人看）" % view)
		#      ③ **每一份真在用的名单、每一台机体，都必须能被选到**。
		#      名单放得下 ⇒ 窗口 = 整份名单，直接列出来；
		#      放不下（马夫蒂 4 台 / 1280·1600）⇒ 靠 `suit_window()` 滚过去。
		var rosters: Array = [MainMenu.SUITS, MainMenu.ENEMY_SUITS,
			BattleFormation.roster_of(BattleFormation.Side.MAFTY).all_suits(),
			BattleFormation.roster_of(BattleFormation.Side.FEDERATION).all_suits()]
		var cap := MainMenu.max_cards(view)
		for roster: Array in rosters:
			for i in roster.size():
				var w := MainMenu.suit_window(roster.size(), i, view)
				# ⚠️ `suit_window()` 的第二分量是**张数**，不是末位下标
				#（`scroll_window` 的契约：`Vector2i(首行, 行数)`）。
				# 第一版这里写成了 `i < w.y`，于是 4 台/容量 3 时的窗口 `(1,3)`
				# —— 它覆盖的是下标 1、2、3 —— 被读成"下标 [1,3) 不含 3"，
				# 于是**实现没坏而断言假红**。窗口覆盖范围是 `[w.x, w.x + w.y)`。
				t.ok(w.y <= cap,
					"%s：%d 台名单第 %d 台 —— 窗口装 %d 张 ≤ 物理容量 %d"
						% [view, roster.size(), i, w.y, cap])
				t.ok(i >= w.x and i < w.x + w.y,
					"%s：%d 台名单第 %d 台能滚进窗口 [%d,%d)"
						% [view, roster.size(), i, w.x, w.x + w.y])
			# 放得下的名单必须是**逐台都同屏**的（窗口不许无故裁掉能显示的机型）
			if roster.size() <= cap:
				var wide := MainMenu.suit_window(roster.size(), 0, view)
				t.eq(wide, Vector2i(0, roster.size()),
					"%s：%d 台名单排得下 ⇒ 窗口 = 整份名单（不裁）" % [view, roster.size()])
			else:
				# ③.5 **滚动指示器要装得下**（只有放不下的名单才有它）。
				#
				# 这条对应 `_draw_suit_scroll()` 里的早退判据 `y >= content_bottom() − 6` ——
				# 那条早退是**安全阀**（宁可没有指示器，也不要压住卡片/提示行），
				# 但"安全阀被触发"意味着**玩家看不到自己还有几台机没翻到**。
				# 所以断言的是"工程支持的每一个分辨率下，安全阀**都不该被触发**"。
				#
				# ⚠️ 这一段原本是探针出图人眼看的（`tools/_messer_menu_shots.gd`）。
				# 但探针靠 `DisplayServer.window_set_size()` 改分辨率，实测**改不动**
				#（截图尺寸确实变成 1920×1080，而菜单那个 Control 的 `size` 仍是 1600×900）
				# ⇒ 那几张图的版式判据**无效**。搬进测试才对：这里覆盖 `VIEWS` 的四个
				#    分辨率，全部由纯函数量出，不依赖窗口真的改得了尺寸。
				var card_bottom := MainMenu.cards_top(view) + MainMenu.card_h(view)
				var sc_y := card_bottom + 16.0
				t.gt(sc_y, card_bottom,
					"%s：%d 台名单要滚动 ⇒ 指示器在卡片行**下面**（不压卡片）"
						% [view, roster.size()])
				t.lt(sc_y, MainMenu.content_bottom(view) - 6.0,
					"%s：%d 台名单的滚动指示器 y=%.1f 装得进内容区（底边 %.1f）"
						% [view, roster.size(), sc_y, MainMenu.content_bottom(view)])
				t.lt(sc_y + 8.0, MainMenu.hint_y(view),
					"%s：指示器（含标签）在提示行之上（不和 A/D 提示打架）" % view)
		#      ④ 卡片本身也得够宽（与 ② 同源，但读起来直观）
		t.ok(cards[0].size.x >= MainMenu.CARD_MIN_W,
			"%s：每张卡 %.1f px ≥ 可读下限 %.1f" % [view, cards[0].size.x, MainMenu.CARD_MIN_W])

		# 4) 标题带在主面板之上、互不重叠
		t.lt(MainMenu.TITLE_TOP + MainMenu.TITLE_BAND, MainMenu.PANEL_TOP,
			"%s：标题带在主面板之上" % view)
		t.lt(MainMenu.STEP_Y, MainMenu.TITLE_TOP, "%s：步骤条在标题带之上" % view)

		# 5) 提示行：批 29 起**锚定屏幕底边**（所有页面共用同一条底线）。
		#    它必须落在内容区底边**之下**（页脚带里），否则就会和列表打架。
		var hint := MainMenu.hint_y(view)
		t.lt(hint, view.y - 10.0, "%s：提示行在屏幕内" % view)
		t.gt(hint, MainMenu.content_bottom(view) - 1.0,
			"%s：提示行在内容区之下（页脚带里）" % view)
		# 提示行不许压到内容区底边以外（页脚带预留了高度，提示行必须装得下）
		t.lt(MainMenu.HINT_BAND, MainMenu.HINT_BASELINE_LIFT + 20.0,
			"%s：页脚带高度装得下提示行" % view)

		# 6) 内容区边界：面板/卡片**上下都不越界**。
		#    这一条是"下面太空"的另一面 —— 改版之后内容会被放大、居中，
		#    最怕的是反过来"撑过头"从底边掉出去。
		t.near(cards[0].size.y, MainMenu.card_h(view), 0.001,
			"%s：卡片高度 = card_h()（内容区自适应）" % view)
		t.gt(MainMenu.content_bottom(view), MainMenu.PANEL_TOP + 100.0,
			"%s：内容区留得住东西（不是一条缝）" % view)
		for r2: Rect2 in ([cards[0], rows[0], settings] as Array[Rect2]):
			t.gt(r2.position.y, MainMenu.PANEL_TOP - 1.0, "%s：面板顶不高于内容区顶" % view)
			t.lt(r2.position.y + r2.size.y, MainMenu.content_bottom(view) + 1.0,
				"%s：面板底不越出内容区底" % view)


## 主菜单标题 LOGO（用户给的 `title.png`）。
##
## 这张图原来是**白字黑底、不透明**，由 `tools/make_title_logo.gd` 按亮度抠成
## 带 alpha 的贴图再放进工程。这里钉住三件事：资源真的能加载、是横版、装得进标题带。
static func _logo(t: T) -> void:
	var tex := MainMenu.title_texture()
	t.ok(tex != null, "标题 LOGO 能加载：%s" % MainMenu.TITLE_LOGO_PATH)
	if tex == null:
		return
	var ar := float(tex.get_width()) / float(tex.get_height())
	t.between(ar, 2.5, 4.5, "LOGO 是横版（%.2f : 1）" % ar)
	t.lt(MainMenu.TITLE_LOGO_H, MainMenu.TITLE_BAND, "LOGO 高度装得进标题带")
	var w := MainMenu.TITLE_LOGO_H * ar
	t.lt(w, UILayout.content_width(Vector2(1280, 720)),
		"最小窗口（1280）下 LOGO 也顶不出去（宽 %.0f px）" % w)
