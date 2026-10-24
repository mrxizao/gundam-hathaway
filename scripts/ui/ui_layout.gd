class_name UILayout
extends RefCounted
## 三套界面的**公共版式网格** —— 主菜单 / 战斗 HUD / 结算菜单都从这里取数。
##
## ## 为什么要有一个文件专门管这件事
## 之前主菜单、战斗 HUD、结算菜单各写各的坐标：
## 帮助面板左边距 24、HUD 的信息块 54、结算两栏是"居中倒推"出来的。
## 单看每一屏都能看，**来回切换就会觉得"每屏都在飘"** —— 这就是"对齐"要解决的问题。
##
## ## 网格只有两级（记住这两个数就够）
## ```
##   屏幕边缘 ──24──▶ 面板外框 ──30──▶ 内容列 / 数值列右边界
## ```
##   - `MARGIN` = 24：屏幕外框留白。**所有面板的外框**都落在这条线上
##     （主菜单底部的操作说明面板、结算菜单的两栏）。
##   - `PAD` = 30：面板内部、外框到内容的留白。
##   - 于是内容区左右边界 = `content_left()` / `content_right()` = 距屏幕边缘 **54 px**。
##
## ## 三条对齐规则（`suite_layout.gd` 逐条断言，不许漂）
## 1. **外框对齐**：结算菜单两栏的外框 == 主菜单操作说明面板的外框 == `[MARGIN, 宽−MARGIN]`。
## 2. **数值列对齐**：战斗 HUD 右下角弹药栏的数值列、右上角高度块的数值、
##    结算菜单"损耗与战果"的数值列 —— 右端**全部**落在 `content_right()` 上。
## 3. **标签列对齐**：HUD 左上角机名、左下角血条、结算菜单两栏的行标签 ——
##    左端**全部**落在 `content_left()` 上。
##
## ⚠️ 常量是**在 1600×900 基准下调好的**，所有取数都写成"相对屏幕尺寸"的形式，
## 所以窗口被拉成别的比例时不会错位。

## 屏幕外框留白：所有面板的外边界。
const MARGIN := 24.0
## 面板内部的内容留白：外框到内容列的距离。
##
## 它同时是 24（外框）之后的那一段，所以内容区距屏幕边缘 = 24 + 30 = 54 ——
## **这个 54 就是 HUD 信息块一直用的 HUD_EDGE**。
## 以前两边各写一个数（24 与 54），结果结算面板里的数值列和 HUD 的数值列差了十几像素，
## 切屏时右边的数字会"跳一下"。
const PAD := 30.0

## ---- 战斗 HUD 右下角弹药栏 ----
##
## 三列**全部右对齐**。三列的位置一律相对 `content_right()` 反推，
## 这样数值列的右端天然与结算菜单的数值列在同一条线上。
##
## ⚠️ **弹匣条占的就是"数值列"那一段**（右端 = 数值列右端，宽度 = `AMMO_BAR_W`），
## 所以名称列往回让的距离**必须大于条宽**，否则条会盖到名称上。
## 这里踩过一次：名称列只让了 82 px 而条宽 116 px，"换弹"两个字被条压掉一半，
## 看起来就是"子弹 UI 和文字重叠"（用户报的正是这个）。
## `suite_layout` 里有断言盯着这条不等式。
const AMMO_BAR_W := 116.0
## 名称列右端距数值列右端的距离。= 条宽 + 10 px 间隙。
const AMMO_NAME_BACK_FROM_VALUE := AMMO_BAR_W + 10.0
## 键位列右端距数值列右端的距离。名称最宽 4 个汉字（"浮游导弹" @14px ≈ 56 px），
## 让 230 px 之后键位列与名称列之间还有 40 px 以上余量。
const AMMO_KEY_BACK_FROM_VALUE := 230.0
## 弹药栏首行距屏幕底边的高度，以及行距。
const AMMO_TOP_FROM_BOTTOM := 208.0
const AMMO_ROW_STEP := 23.0

## ---- 战斗 HUD 右上角的垂直高度带（§4.2.2）----
##
## ⚠️ 高度带**紧贴屏幕右缘**，右边界落在 `view.x − MARGIN` 上 ——
## 那条线是**外框线**（= 主菜单帮助面板 / 结算两栏的外框），不是内容列。
## 所以高度块的数值列**必须往回让出带宽**，否则五个数字会整排压在刻度上。
## 「让多少」这件事只能有一个真源，见下面的 `alt_value_right()`。
##
## 这三个数放在 `UILayout` 而不是 `hud.gd` 里，理由和 AMMO_* 完全一样：
## `suite_layout` 要断言"HUD 高度块的数值列用的是让位之后的那条线"，
## 而断言必须读得到同一个常量。
const ALT_TAPE_W := 46.0
## 高度带的长度。380 px 在 900 高的窗口里正好卡在右上角敌机列表与右下角装备栏之间。
const ALT_TAPE_H := 380.0
## 高度带覆盖的高度跨度（米）。380 px / 5000 m ⇒ 每 500 m 一道 38 px 的刻度。
const ALT_TAPE_SPAN_M := 5000.0


static func content_left(_view: Vector2) -> float:
	return MARGIN + PAD


static func content_right(view: Vector2) -> float:
	return view.x - MARGIN - PAD


## 内容区宽度。结算两栏、主菜单帮助面板都用它，于是三者左右边界**严格一致**。
static func content_width(view: Vector2) -> float:
	return view.x - (MARGIN + PAD) * 2.0


## 面板外框宽度（左右各留 MARGIN）。结算两栏与主菜单帮助面板的外框都用它。
static func frame_width(view: Vector2) -> float:
	return view.x - MARGIN * 2.0


## 弹药栏三列的**右端** x 坐标（键位 / 名称 / 数值）。
## 抽成函数是为了能被测试直接断言"数值列 == 结算菜单的数值列"。
static func ammo_columns(view: Vector2) -> Dictionary:
	var v := content_right(view)
	return {
		"key": v - AMMO_KEY_BACK_FROM_VALUE,
		"name": v - AMMO_NAME_BACK_FROM_VALUE,
		"value": v,
	}


## 垂直高度带的外框：**紧贴屏幕右缘**、竖直居中。
##
## ## 两个竖直方向的约束，都是算出来的（不靠"看着差不多"）
##   - **下缘**让开右下角弹药栏的首行（`AMMO_TOP_FROM_BOTTOM`）。
##     ⚠️ 这一条不是洁癖：高度带的 x 区间（1600 宽时 [1530, 1576]）与弹药栏
##     数值列的右端（1546）**真的重叠**，而带是画在弹药栏**之前**的 ——
##     纵容下去就是"刻度横穿弹药数值"。两个约束冲突时（1280×720 会冲突）
##     **上移整条带**，因为"带短一截/贴到别处"比"读数被划掉"轻得多。
##   - **上缘**留 `MARGIN`。
##
## 右上角的敌机列表**不参与**约束，理由：它在 `_draw()` 里排在高度带**之后**，
## 字是画在带上层的，所以最多是"带从名单下面透出来"，不会挡掉名单。
static func alt_tape_rect(view: Vector2) -> Rect2:
	var top_limit := MARGIN
	var bottom_limit := view.y - AMMO_TOP_FROM_BOTTOM - MARGIN
	var x := view.x - MARGIN - ALT_TAPE_W
	var avail := maxf(bottom_limit - top_limit, 0.0)
	if avail <= 0.0:
		# 窗口矮到装不下任何东西（理论上不会发生）—— 返回一条零高的带，
		# 而不是返回一个越界的矩形让调用方画到屏幕外面去。
		return Rect2(x, view.y * 0.5, ALT_TAPE_W, 0.0)
	var h := minf(ALT_TAPE_H, avail)
	var cy := clampf(view.y * 0.5, top_limit + h * 0.5, bottom_limit - h * 0.5)
	return Rect2(x, cy - h * 0.5, ALT_TAPE_W, h)


## **高度块数值列的右端** = 高度带左边缘再往回让 8 px。
##
## HUD 的 `_draw_altitude_block()` 必须用它，**不许用 `content_right()`**：
## `content_right()` 在高度带**里面**（1600 宽时 content_right = 1546，
## 而带宽是 [1530, 1576]）。原来那五个数字直接用 content_right，
## 加上高度带之后就会整排压在刻度上。
##
## 代价是"HUD 高度块不再与结算菜单的数值列同一条线"—— 这是**有意的取舍**：
## 三屏对齐的规矩（`suite_layout`）改成
## 「HUD 弹药栏 == 结算数值列 == `content_right()`」，
## 高度块单列一条线并把理由写在这里。两件事都比"数字压在刻度上"好。
static func alt_value_right(view: Vector2) -> float:
	return alt_tape_rect(view).position.x - 8.0


# ============================================================ 视觉语言约束（§4.7 · 批 3）
#
# 需求原话是「我其实想做的更风格化的同时更严肃一点」。审美争论没法验收，
# 所以设计文档把它翻译成**六条可执行的约束**。这一节是其中三条的**唯一落点**：
#
#   ① **颜色只用 5 个语义色** —— 真源在 `hud.gd:14-21`（那边恰好就是 5 个 + 两个降透明度版本）。
#      `UILayout` 不放颜色，只放"这条约束是什么"的说明；由 `suite_ui_style` 用
#      **色相聚类**去核对"没有长出第 6 个色相"（不是数常量个数 —— 那样一加 alpha 版本就假红）。
#   ② **线宽只有两档** —— `LINE_HAIR` / `LINE_STRUCT`。
#   ③ **字重只有两档** —— `WEIGHT_BODY` / `WEIGHT_EMPH`（见下面的说明：工程只有一份字体，
#      所以"强调"是**加深描边**，不是换字体）。
#
# 另外三条（一套对齐线 / 发光只做信息 / 等宽数字）本来就是既有事实：
# 对齐线就是本文件上面那些 `content_*()`，发光在 `hud.gd` 里只用于告警与护盾，
# 数值列一律右对齐（右对齐比等宽字体更彻底地解决"数字跳"）。`suite_ui_style` 逐条核对。

## 线宽只有两档。
##
## - `LINE_HAIR`：**分隔线** —— 把一组信息和下一组分开（两档字重之外的层级手段）；
## - `LINE_STRUCT`：**结构线** —— 面板外框、表头、指针、刻度基线。
##
## ⚠️ 为什么要规定成"只有两档"：这个 HUD 全代码绘制，`draw_line()` 的宽度是**散在各处**的
## 字面量（0.5 / 1.0 / 1.5 / 2.0 都有过）。宽度一多，层级就读不出来了 ——
## "哪条线是框、哪条线是分隔"变成靠粗细差几像素去猜。两档之后就只剩"结构 / 分隔"两种语义。
const LINE_HAIR := 0.5
const LINE_STRUCT := 1.0


## 字重只有两档。
##
## ⚠️ **工程只带一份默认字体**（`ThemeDB.fallback_font`，没有 bold 变体，也不允许带字体文件 ——
## 这条规矩和"地形天空 HUD 全程序化"是同一条）。所以"强调"只能靠**描边加粗**表达：
## 描边宽 2 是正文，宽 3 是强调。视觉上差一档，而信息层级读得出来。
const WEIGHT_BODY := 0
const WEIGHT_EMPH := 1
## 描边宽度表。**唯一的入口** —— `hud.gd` 的 `_text()` 只认这两个值。
const OUTLINE_BODY := 2
const OUTLINE_EMPH := 3


## 字重 → 描边宽度。`hud._text()` 读它。
##
## 未知值兜底到正文：宁可少强调一处，也不要出现"第三档字重"
## （那正好是本约束要防的事）。
static func outline_for(weight: int) -> int:
	return OUTLINE_EMPH if weight == WEIGHT_EMPH else OUTLINE_BODY


## 线宽角色 → px。同理，未知值兜底到分隔线。
static func line_width(role: int) -> float:
	return LINE_STRUCT if role == LINE_STRUCT else LINE_HAIR


## 允许出现的线宽**全集** —— 就是那两档。
##
## 它是"只有两档"这句话的可断言形式：`suite_ui_style` 拿它去扫三个 UI 脚本的
## **源码**（见 `scan_line_widths()`），扫出集合以外的字面量就 FAIL。
##
## ⚠️ 为什么非得去扫源码：这个 HUD 是**全代码绘制**的，线宽是散在四十多处
## `draw_line()` / `draw_arc()` 里的字面量，运行时没有任何结构能枚举它们。
## 不去扫，"只有两档"就退化成一句注释 —— 而它曾经真的是八种宽度
## （0.7 / 0.8 / 1.0 / 1.2 / 1.3 / 1.4 / 1.6 / 1.8 / 2.0 / 2.2）。
const LINE_WIDTHS := [LINE_HAIR, LINE_STRUCT]


## 这个宽度是不是合法的那两档之一。
static func is_line_width_ok(w: float) -> bool:
	for v: float in LINE_WIDTHS:
		if absf(w - v) <= 0.001:
			return true
	return false


## `draw_*` 函数名 → **线宽实参的下标**（从 0 数）。
##
## ⚠️ 每个函数的位置都不一样，抄错一个就会把 `point_count`（24）当成线宽，
## 于是"扫出一堆非法宽度"—— 而这个扫法唯一的价值就是位置准，所以逐个写下来：
## ```
##   draw_line(from, to, color, width, antialiased)               → 3
##   draw_dashed_line(from, to, color, width, dash, ...)          → 3
##   draw_rect(rect, color, filled, width, antialiased)           → 3
##   draw_arc(center, r, from, to, points, color, width, aa)      → 6
##   draw_polyline(points, color, width, antialiased)             → 2
##   draw_circle(pos, r, color, filled, width, antialiased)       → 4
## ```
const WIDTH_ARG := {
	"draw_line": 3,
	"draw_dashed_line": 3,
	"draw_rect": 3,
	"draw_arc": 6,
	"draw_polyline": 2,
	"draw_circle": 4,
}


## 从一段 GDScript 源码里扫出所有 `draw_*` 的**线宽实参原文**。
##
## 返回 `{行号: [实参原文, ...]}`（原文已 strip）。一处调用给出一条原文 ——
## `draw_rect(r, c, false, 2.0 if focused else 1.0)` 拿到的是
## `"2.0 if focused else 1.0"` 这**一条**，而 `numbers_in()` 能从里面挖出两个数。
##
## ## 为什么返回"原文"而不是"数字"
## 这一轮之后工程里**不应该再有任何线宽数字**（全部走 `LINE_HAIR` / `LINE_STRUCT`），
## 于是断言分两层，而**两层都需要原文**：
##   ① 「一个数字都没有」—— 对原文跑 `numbers_in()`，必须为空；
##   ② 「用的就是那两个常量」—— 看原文里出现的是哪个标识符。
## 只返回数字的话，第 ① 层会退化成"什么都没扫到也算过"—— 那是假的绿。
##
## ## 它认什么、不认什么
##   - 认**字面量**，也认**标识符**（`lw`、`UILayout.LINE_HAIR`）—— 原文原样给。
##   - 跨行的调用能处理：先把源码压成一条、按括号配平切实参，行号靠逐字符记录回推。
##   - 宽度位置**取不到**（实参个数不够，比如只有三参的 `draw_circle`）时跳过，
##     不会顺着往下乱认一个参数。
##
## ⚠️ 一个**真实的**坑：`draw_arc` 的线宽在第 7 个实参上，而它的**半径**在第 2 个。
## 早先按"第 4 个"去扫，扫到的是 `end_angle`（0.0）与 `point_count`（24）——
## 既漏报又误报，而误报出来的数字看起来"挺像线宽"，很难查。
static func scan_line_widths(src: String) -> Dictionary:
	var out := {}
	var flat := ""
	var line_of: PackedInt32Array = PackedInt32Array()
	var lines := src.split("\n")
	for i in lines.size():
		var text: String = lines[i]
		flat += text
		for _c in text.length():
			line_of.append(i + 1)
		flat += "\n"
		line_of.append(i + 1)

	for fn: String in WIDTH_ARG:
		var needle := fn + "("
		var from := 0
		while true:
			var at := flat.find(needle, from)
			if at < 0:
				break
			from = at + needle.length()
			# ⚠️ 必须是**调用**、不是名字的一部分（`my_draw_line(` 不算）。
			var prev := flat[at - 1] if at > 0 else " "
			if prev == "_" or (prev >= "a" and prev <= "z") or (prev >= "A" and prev <= "Z"):
				continue
			var args := _arg_text(flat, at + needle.length() - 1)
			if args == "":
				continue
			var parts := split_top_level(args)
			var idx: int = int(WIDTH_ARG[fn])
			if parts.size() <= idx:
				continue
			var raw := str(parts[idx]).strip_edges()
			if raw == "":
				continue
			var ln := line_of[at]
			var bucket: Array = out.get(ln, [])
			bucket.append(raw)
			out[ln] = bucket
	return out


## 按**顶层逗号**切实参表（括号 / 方括号里的逗号不算分隔符）。
##
## 抽成 public 而不是内联：`suite_ui_style` 要单独测它 ——
## 切错了的话扫出来的线宽会整体错位，而症状是"报了一堆不存在的非法宽度"，
## 那种失败比"少扫一条"难查得多。
static func split_top_level(s: String) -> Array:
	var parts: Array = []
	var depth := 0
	var cur := ""
	for c in s:
		if c == "(" or c == "[" or c == "{":
			depth += 1
		elif c == ")" or c == "]" or c == "}":
			depth -= 1
		if c == "," and depth == 0:
			parts.append(cur)
			cur = ""
			continue
		cur += c
	parts.append(cur)
	return parts


## 一段文本里的所有数字字面量（含负号、含小数；不认 `1e-3` 这种科学计数）。
##
## `suite_ui_style` 用它把"线宽实参原文"里的数字挖出来 —— 这一轮转换完成之后，
## 那些原文里**一个数字都不该有**。
static func numbers_in(s: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("-?\\d+(?:\\.\\d+)?")
	for m: RegExMatch in re.search_all(s):
		out.append(float(m.get_string()))
	return out


## `open_idx` 指向 `(`，返回它到配对 `)` 之间的文本（不含括号）。
##
## ⚠️ 有**上限**：超过 400 字符还配不平就放弃（说明括号真的没配平，比如源码
## 本身就是坏的）。没有这个上限的话，一个多余的 `(` 会让扫描器一路吃到文件末尾。
static func _arg_text(s: String, open_idx: int) -> String:
	var depth := 0
	var stop := mini(s.length(), open_idx + 400)
	for i in range(open_idx, stop):
		var c := s[i]
		if c == "(":
			depth += 1
		elif c == ")":
			depth -= 1
			if depth == 0:
				return s.substr(open_idx + 1, i - open_idx - 1)
	return ""


# ============================================================ 折行
## 按**像素宽度**折行。中文没有空格，不能按词断，只能逐字量宽度。
##
## ## 为什么在 `UILayout` 里（而不是各屏自己写一份）
##
## 这个算法原先只有主菜单有一份（`main_menu._wrap()`）。加通讯字幕时如果照抄一份，
## 就会出现"同一段文字在主菜单和字幕里断行位置不同" —— 这种错**没有判据会红**，
## 只能靠人眼在两张图上比。所以两个函数签名一起收在这里，调用方只传字体。
##
## ## 两个行为要记住
## - 文案里的 `\n` 是"作者希望的段落"，**先按它切开再逐段折**（不是当普通字符）；
## - `max_lines` 是**硬上限**，到顶就返回 —— 不返回的话长句会把框撑破。
static func wrap(font: Font, text: String, max_w: float, fs: int,
		max_lines: int) -> Array[String]:
	var out: Array[String] = []
	if font == null or max_lines <= 0:
		return out
	for para: String in text.split("\n"):
		var cur := ""
		for ch: String in para:
			var probe := cur + ch
			if cur != "" and font.get_string_size(
					probe, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
				out.append(cur)
				if out.size() >= max_lines:
					return out
				cur = ch
			else:
				cur = probe
		if cur != "":
			out.append(cur)
			if out.size() >= max_lines:
				return out
	return out
