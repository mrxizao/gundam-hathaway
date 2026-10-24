class_name SuiteUiStyle
extends RefCounted
## §4.7 · UI 风格约束（1.2.1 批 3）。
##
## ## 为什么"风格"也要写成测试
## 需求原话是「我其实想做的更风格化的同时更严肃一点」。这种话没法直接验收 ——
## 同一张截图给两个人看，一个说「更严肃了」，另一个说「变简陋了」。
## 所以设计文档 §4.7 把它翻译成**六条可执行的约束**，本套件逐条钉住：
##
## | 约束 | 本套件怎么验 |
## |---|---|
## | 颜色只用 5 个语义色 | 对调色板做**色相聚类**，必须恰好 5 簇；且不许有表外颜色常量 |
## | 一套对齐线 | 三个 UI 脚本里不许出现 `HORIZONTAL_ALIGNMENT_RIGHT`（那是修过的 bug）|
## | 字重只有两档 | `UILayout.outline_for()` 是唯一入口；源码里不许再写 `, 2, OUTLINE)` |
## | 线宽只有两档 | **扫源码**：宽度实参里一个数字都不许有，且只许出现那两个常量 |
## | 发光只用于信息 | 三个 UI 脚本里没有加色混合；唯一那处辉光是细圈 |
## | 一组等宽数字 | 右端全落 `content_right()`，且默认字体的十个数字确实等宽 |
## | 语音必须配字幕 | `VOICE_FOR` 的每个 key 都能在 `WARN_TEXT` 里找到文案 |
##
## ## 两条判据是**反着写**的，理由值得单独记
##   - **颜色那条不是「数常量个数」**：`HUD` / `HUD_DIM` / `HUD_FAINT` 是同一个青绿的
##     三个透明度，数常量会得到 8，而约束要的是 5。必须数**色相**。
##   - **线宽那条不能靠运行时反射**：这个 HUD 是全代码绘制的，线宽是散在四十多处
##     `draw_line()` 里的东西，运行时没有任何结构能枚举它们。只能扫源码。
##
## ⚠️ 扫源码的测试有个通病：**扫到 0 条也全绿**。所以下面专门有一节
## （`_scanner`）用一个构造出来的片段去钉住扫描器本身 —— 包括
## 「`draw_arc` 的线宽在第 7 个实参（不是第 4 个）」这种抄错就静默失效的细节。

## **有数值列**的两个界面 —— 只有它们需要 `_text_right()` 这条通道。
##
## ⚠️ 暂停菜单**不在内**：它整屏没有一列数字（只有「继续 / 返回」两行），
## 本来就没有右对齐需求，也不该为了凑齐"三屏一致"而硬塞一个用不到的函数。
## 而「不许用 `HORIZONTAL_ALIGNMENT_RIGHT`」那条**对三屏都成立**（见 `_one_grid`）。
const RIGHT_ALIGNED_FILES := [
	"res://scripts/ui/hud.gd",
	"res://scripts/ui/main_menu.gd",
]

## 三套界面的绘制代码。§4.7 的约束对这三份**同时**成立 ——
## 只把它们加到 HUD 上、留着菜单任写宽度的话，切屏时会觉得"两套 UI 不是一个人做的"。
const UI_FILES := [
	"res://scripts/ui/hud.gd",
	"res://scripts/ui/main_menu.gd",
	"res://scripts/ui/pause_menu.gd",
]

## 允许出现的颜色常量名（§4.7 的 5 个语义色 + 各自的降透明度版本 + 描边色）。
##
## ⚠️ 这张名字表**不是**第二真源：真正的判据是下面的色相聚类（它对"多加一个颜色"
## 敏感，而列名字只对"改名"敏感）。它存在的意义是那条**最强的**守卫：
## 「三个 UI 脚本里不许出现表外的颜色常量」—— 那正是 §4.7 说的"不要加第 6 个"。
const ALLOWED_COLORS := [
	"HUD", "HUD_DIM", "HUD_FAINT", "WARN", "DANGER", "NEUTRAL", "IFIELD", "IFIELD_DIM",
	"OUTLINE",
]

## 线宽实参里**只允许**出现的三个记号。
##
## `lw` 也在内，但它是 `_bracket()` 的形参 —— 所以 `_provenance()` 里额外断言
## "hud.gd 里给 `lw` 赋值的每一行都赋值成了 `UILayout.LINE_*`"，
## 否则把 `lw` 加进白名单就等于开了一个后门。
const WIDTH_TOKENS := ["UILayout.LINE_HAIR", "UILayout.LINE_STRUCT", "lw"]

## 色相聚类的容差（度）。取 30° 的理由是它刚好能把 `WARN`(40.0°) 与 `DANGER`(3.2°)
## 分开（相距 36.8°），又不把 `HUD`(142.9°) 与 `HUD_DIM`(148.4°) 拆开（相距 5.6°）。
## —— 这两个数是算出来的，不是"看着差不多"。
const HUE_TOL := 30.0
## 低于这个彩度就当"无彩"（白 / 灰）。`NEUTRAL` 的 s ≈ 0.08，阈值必须高于它。
const SAT_MIN := 0.15
## 低于这个最亮通道就当"无彩"（描边近黑）。
##
## ⚠️ 少了这一条会踩一个数学陷阱：`OUTLINE`(0.0, 0.05, 0.02) 的彩度**恰好是 1.0**
## —— 近黑点的彩度数学上拉满，但它没有任何色相意义。不加这个判据，
## 它会变成一个"深绿色相"，于是"5 个语义色"被数成 6 个。
const VALUE_MIN := 0.12


static func run(t: T, _host: Node) -> void:
	t.suite("UI 风格 / 颜色只用五个语义色")
	_colors(t)
	t.suite("UI 风格 / 一套对齐线")
	_one_grid(t)
	t.suite("UI 风格 / 字重只有两档")
	_weights(t)
	t.suite("UI 风格 / 线宽只有两档")
	_widths(t)
	t.suite("UI 风格 / 线宽扫描器本身是对的")
	_scanner(t)
	t.suite("UI 风格 / 发光只用于信息")
	_glow(t)
	t.suite("UI 风格 / 一组等宽数字")
	_metrics(t)
	t.suite("UI 风格 / 语音必须配字幕")
	_subtitles(t)
	_display_scale(t)
	_cel_shading(t)


# ============================================================ 工具

static func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)


static func _short(path: String) -> String:
	return path.get_file()


## 扫描结果里第 n 行的**第一条**实参原文（没有就返回空串）。
static func _at(found: Dictionary, line: int) -> String:
	var arr: Array = found.get(line, [])
	return str(arr[0]) if not arr.is_empty() else ""


## 去掉**整行注释**与**行尾注释**之后的源码。
##
## ⚠️ 所有「源码里有没有 X」的断言都必须走这里。这条是我自己踩出来的：
## `hud.gd` 里 `_text_right` 上面的注释**特意**写着它原来用的是
## `HORIZONTAL_ALIGNMENT_RIGHT, -1`（那是这个 bug 的根因记录），
## 于是「不许出现 HORIZONTAL_ALIGNMENT_RIGHT」这条断言被一句**注释**判了失败。
## 注释里提到某个名字恰恰说明它被慎重考虑过 —— 那不该算违规。
static func _code(path: String) -> String:
	var out: Array = []
	for line in _src(path).split("\n"):
		var s := str(line)
		if s.strip_edges().begins_with("#"):
			continue
		out.append(_strip_inline_comment(s))
	return "\n".join(out)


## 去掉行尾注释（`#` 落在字符串里的时候不算注释）。
##
## 内外靠**引号计数**判断：`#` 前面若有奇数个引号，说明它在字符串里。
## 这不是完整的词法分析，但对「代码行里混一句中文注释」这种实际情况够用。
static func _strip_inline_comment(line: String) -> String:
	var quotes := 0
	for i in line.length():
		var c := line[i]
		if c == "\"" or c == "'":
			quotes += 1
		elif c == "#" and quotes % 2 == 0:
			return line.substr(0, i)
	return line


## 一段线宽实参里的**违规数字**。
##
## 数字分两类，只有一类是违规的：
##   - **比较运算的操作数**（`tk >= 30.0` 里的 30.0）—— 它说的是"哪个刻度算长刻度"，
##     属于刻度的语义，不是版式，**不算违规**；
##   - 其余任何数字（`0.8`、`1.0 if major else 0.7` 的两个分支）—— 都是线宽字面量，违规。
##
## ⚠️ 这个区分是必要的：为了迁就 lint 而把那个 30.0 抽成常量，
## 等于让测试规定代码该长什么样 —— 顺序应该反过来。
static func _width_literals(raw: String) -> Array:
	var re := RegEx.new()
	re.compile("[<>=!]=?\\s*-?\\d+(?:\\.\\d+)?")
	return UILayout.numbers_in(re.sub(raw, " ", true))


## 色相环上的**循环**距离（0–180）。跨 0° 的两色（红 3° 与品红 355°）不该判成很远。
static func _hue_gap(a: float, b: float) -> float:
	var d := absf(a - b)
	return minf(d, 360.0 - d)


## `hud.gd` 的语义调色板（运行时取 —— 跨类的常量不能用在 `const` 初始化式里）。
static func _palette() -> Dictionary:
	return {
		"HUD": FlightHUD.HUD,
		"HUD_DIM": FlightHUD.HUD_DIM,
		"HUD_FAINT": FlightHUD.HUD_FAINT,
		"WARN": FlightHUD.WARN,
		"DANGER": FlightHUD.DANGER,
		"NEUTRAL": FlightHUD.NEUTRAL,
		"IFIELD": FlightHUD.IFIELD,
		"IFIELD_DIM": FlightHUD.IFIELD_DIM,
		"OUTLINE": FlightHUD.OUTLINE,
	}


## 按"色相 + 有没有彩度"聚类。
## 返回 `{"hues": {代表色相: [名字...]}, "achromatic": [名字...]}`。
static func _cluster(pal: Dictionary) -> Dictionary:
	var hues := {}
	var achromatic: Array = []
	for name: String in pal:
		var c: Color = pal[name]
		if c.s < SAT_MIN or c.v < VALUE_MIN:
			achromatic.append(name)
			continue
		var hue := c.h * 360.0
		var found := false
		for rep: float in hues:
			if _hue_gap(hue, rep) <= HUE_TOL:
				(hues[rep] as Array).append(name)
				found = true
				break
		if not found:
			hues[hue] = [name]
	return {"hues": hues, "achromatic": achromatic}


## 某个名字落在哪个色相簇（返回代表色相；无彩 / 没收录返回 -1）。
static func _cluster_of(hues: Dictionary, name: String) -> float:
	for rep: float in hues:
		if (hues[rep] as Array).has(name):
			return rep
	return -1.0


## 源码里 `const NAME := Color(...)` 的所有 NAME。
static func _color_const_names(src: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("(?m)^const\\s+(\\w+)\\s*:=\\s*Color\\(")
	for m: RegExMatch in re.search_all(src):
		out.append(m.get_string(1))
	return out


# ============================================================ 1. 五个语义色

static func _colors(t: T) -> void:
	var pal := _palette()
	var res := _cluster(pal)
	var hues: Dictionary = res["hues"]
	var achromatic: Array = res["achromatic"]

	t.eq(hues.size(), 4, "有彩色的色相恰好 4 个 —— 实际：%s" % [hues.keys()])
	# ⚠️ 数的是**档**，不是名字：无彩那一档里躺着两个名字（NEUTRAL 白 + OUTLINE 描边黑），
	# 而它们共用「无彩」这一个语义位。按名字数会得到 6，然后你会以为自己数错了。
	t.eq(hues.size() + 1, 5, "4 个色相档 + 1 档无彩 = **5 个语义色**（无彩里有 %d 个名字）"
		% achromatic.size())
	t.ok(not achromatic.is_empty(), "无彩那一档不是空的（白 / 描边黑都该在这里）")

	# 四个色相各自是谁、值也要对 —— 只数个数的话，"把 WARN 换成紫色"也能过。
	var want := {"HUD": 142.9, "WARN": 40.0, "DANGER": 3.2, "IFIELD": 194.5}
	for k: String in want:
		var c: Color = pal[k]
		t.near(c.h * 360.0, float(want[k]), 8.0, "%s 的色相（青绿 / 琥珀 / 红 / 青蓝）" % k)

	# 降透明度的版本**不许偏色**：它们必须和本体落在同一个色相簇里。
	for pair: Array in [["HUD_DIM", "HUD"], ["HUD_FAINT", "HUD"], ["IFIELD_DIM", "IFIELD"]]:
		var a := _cluster_of(hues, str(pair[0]))
		var b := _cluster_of(hues, str(pair[1]))
		t.ok(a >= 0.0 and a == b, "%s 与 %s 同色相（只是 alpha 不同）" % [pair[0], pair[1]])

	# `NEUTRAL` 与 `OUTLINE` 必须被判成"无彩"，而不是各自变成一个色相。
	t.ok(achromatic.has("NEUTRAL"), "NEUTRAL（白）算无彩，不是一个淡蓝色相")
	t.ok(achromatic.has("OUTLINE"), "OUTLINE（描边近黑）算无彩，不是一个深绿色相")

	# 最强的那道守卫：脚本里不许冒出表外的颜色常量。
	# 少了它，"加第 6 个语义色"不会被聚类发现（聚类只看 `_palette()` 里列了谁）。
	for path: String in UI_FILES:
		var names := _color_const_names(_src(path))
		var extra: Array = []
		for n: String in names:
			if not ALLOWED_COLORS.has(n):
				extra.append(n)
		t.ok(extra.is_empty(), "%s 没有表外的颜色常量（越界：%s）" % [_short(path), extra])
	# 而 `hud.gd` 自己必须**恰好**是那 9 个（8 语义 + 1 描边）——
	# 少一个说明有人把某个语义色的定义搬走了，那会绕过上面所有断言。
	t.eq(_color_const_names(_src(UI_FILES[0])).size(), 9,
		"hud.gd 的颜色常量恰好 9 个（5 语义 + 3 降透明度 + 1 描边）")


# ============================================================ 2. 一套对齐线

static func _one_grid(t: T) -> void:
	for path: String in UI_FILES:
		var src := _code(path)
		var name := _short(path)
		t.gt(float(src.length()), 0.0, "能读到 %s 的源码" % name)
		# ⚠️ 这一条是**回归**，不是洁癖：`draw_string(..., HORIZONTAL_ALIGNMENT_RIGHT, -1, ...)`
		# 在 Godot 里**不会**右对齐（宽度 -1 时对齐参数被忽略），文本会从锚点往右画 ——
		# 于是右半边整片冲出屏幕。修法是先量字符串宽度、再自己往左挪（各文件的 `_text_right()`）。
		# 只要有人"顺手"改回对齐参数，这个 bug 就会原样回来。
		t.eq(src.count("HORIZONTAL_ALIGNMENT_RIGHT"), 0,
			"%s 的**代码**里不出现 HORIZONTAL_ALIGNMENT_RIGHT" % name)
		t.gt(float(src.count("HORIZONTAL_ALIGNMENT_LEFT")), 0.0,
			"%s 走的是先量宽再往左挪那条路" % name)

	# 三屏的列确实落在同一条线上（`suite_layout` 有更细的断言；这里保留最关键的几条，
	# 好让本套件单独读也能自证"一套对齐线"不是口号）。
	for view: Vector2 in SuiteLayout.VIEWS:
		var geo := FlightHUD.result_layout(view)
		t.near(float(UILayout.ammo_columns(view)["value"]), UILayout.content_right(view), 0.001,
			"%s：HUD 弹药栏数值列 = content_right" % view)
		t.near(float(geo["value_x"]), UILayout.content_right(view), 0.001,
			"%s：结算数值列 = content_right（同一根线）" % view)
		t.near(float(geo["label_x"]), UILayout.content_left(view), 0.001,
			"%s：结算行标签 = content_left" % view)


# ============================================================ 3. 字重两档

static func _weights(t: T) -> void:
	t.eq(UILayout.WEIGHT_BODY, 0, "正文 = 0")
	t.eq(UILayout.WEIGHT_EMPH, 1, "强调 = 1")
	t.eq(UILayout.OUTLINE_BODY, 2, "正文描边 2 px")
	t.eq(UILayout.OUTLINE_EMPH, 3, "强调描边 3 px")
	t.eq(UILayout.OUTLINE_EMPH - UILayout.OUTLINE_BODY, 1,
		"两档只差 1 px —— 差多了会像换了一种字体，而工程只有一份字体")

	t.eq(UILayout.outline_for(UILayout.WEIGHT_BODY), UILayout.OUTLINE_BODY, "正文 → 2")
	t.eq(UILayout.outline_for(UILayout.WEIGHT_EMPH), UILayout.OUTLINE_EMPH, "强调 → 3")
	# ⚠️ 兜底方向是**正文**：宁可少强调一处，也不要凭空冒出第三档字重 ——
	# 那正好是这条约束要防的事。
	t.eq(UILayout.outline_for(999), UILayout.OUTLINE_BODY, "未知字重兜底到正文")
	t.eq(UILayout.outline_for(-1), UILayout.OUTLINE_BODY, "不传（-1）就是正文")

	for path: String in UI_FILES:
		var src := _code(path)
		var name := _short(path)
		t.eq(src.count(", 2, OUTLINE)") + src.count(", 3, OUTLINE)"), 0,
			"%s 不再手写描边宽度（全部走 UILayout.outline_for）" % name)
		t.eq(src.count("draw_string_outline"), src.count("UILayout.outline_for("),
			"%s：每处 draw_string_outline 都过 outline_for()" % name)

	# "强调"这一档必须真的有用户 —— 定义了一个没人用的档位等于没有这一档。
	t.gt(float(_code(UI_FILES[0]).count("UILayout.WEIGHT_EMPH")), 0.0,
		"HUD 里有真的走强调档的文字（中央告警）")


# ============================================================ 4. 线宽两档

static func _widths(t: T) -> void:
	t.near(UILayout.LINE_HAIR, 0.5, 0.001, "分隔线 0.5 px")
	t.near(UILayout.LINE_STRUCT, 1.0, 0.001, "结构线 1.0 px")
	t.eq(UILayout.LINE_WIDTHS.size(), 2, "允许值集合只有两个元素")
	t.near(UILayout.line_width(UILayout.LINE_HAIR), UILayout.LINE_HAIR, 0.001, "角色 → 分隔线")
	t.near(UILayout.line_width(UILayout.LINE_STRUCT), UILayout.LINE_STRUCT, 0.001, "角色 → 结构线")
	t.near(UILayout.line_width(7.0), UILayout.LINE_HAIR, 0.001, "未知角色兜底到分隔线")

	t.ok(UILayout.is_line_width_ok(0.5), "0.5 合法")
	t.ok(UILayout.is_line_width_ok(1.0), "1.0 合法")
	t.ok(not UILayout.is_line_width_ok(1.4), "1.4 **不**合法（它曾经真的在代码里）")
	t.ok(not UILayout.is_line_width_ok(2.2), "2.2 不合法")
	t.ok(not UILayout.is_line_width_ok(0.0), "0 不合法")

	var total := 0
	for path: String in UI_FILES:
		var name := _short(path)
		var found := UILayout.scan_line_widths(_code(path))
		var with_digits: Array = []
		var off_token: Array = []
		for ln: int in found:
			for raw: String in found[ln]:
				total += 1
				var nums := _width_literals(raw)
				if not nums.is_empty():
					with_digits.append("L%d=%s" % [ln, raw])
				var ok := false
				for tok: String in WIDTH_TOKENS:
					if raw.contains(tok):
						ok = true
						break
				if not ok:
					off_token.append("L%d=%s" % [ln, raw])
		# ⚠️ 这一条是核心：**一个数字都不许有**。
		# 转换之前这里躺着 0.7 / 0.8 / 1.0 / 1.2 / 1.3 / 1.4 / 1.6 / 1.8 / 2.0 / 2.2 十种宽度。
		t.ok(with_digits.is_empty(), "%s 的线宽实参里没有数字（越界：%s）" % [name, with_digits])
		# 而"没有数字"还不够 —— 得证明它换成了**那两个**个常量之一。
		t.ok(off_token.is_empty(), "%s 的线宽只来自 UILayout 常量（越界：%s）" % [name, off_token])

	# ⚠️ 这条守的是**测试自己**：一处都扫不到也"全绿"的话，上面两条断言是假的。
	# 40 是**下界**而不是准确值（准确值随版式改动而变，写死它等于每次改 UI 都要改测试）。
	t.gt(float(total), 40.0, "三个脚本合计扫到 %d 处线宽实参（下界 40）" % total)

	# `lw` 在白名单里，所以必须证明它只会被赋成那两个常量 —— 否则白名单就是后门。
	for line in _code(UI_FILES[0]).split("\n"):
		if (line as String).contains("var lw"):
			t.ok((line as String).contains("UILayout.LINE_"),
				"hud.gd 的 lw 只由常量赋值：%s" % (line as String).strip_edges())


# ============================================================ 5. 扫描器自检

static func _scanner(t: T) -> void:
	# 实参表切割：括号里的逗号不算分隔符（`draw_rect(Rect2(..), ..)` 全靠这一条）。
	t.eq(UILayout.split_top_level("p, 22.0, a0, a0 + TAU * f(), 24, WARN, 2.2, true").size(), 8,
		"顶层逗号切出 8 段（`f()` 里的逗号不算）")
	t.eq(UILayout.split_top_level("a").size(), 1, "只有一段也返回一段")
	t.eq(UILayout.split_top_level("r.grow(3.0 + 2.0), col, false, 1.0)").size(), 4,
		"嵌套括号里的逗号不切")

	# 一个构造出来的片段：每一行钉住一个函数的**线宽实参下标**。
	var src := "\n".join([
		"func f():",
		"\tdraw_line(a, b, COL, 1.4, true)",
		"\tdraw_line(a, b,",
		"\t\tCOL, 0.5, true)",
		"\tdraw_arc(c, 22.0, 0.0, TAU, 24, WARN, 2.2, true)",
		"\tdraw_rect(r, COL, false, 1.0)",
		"\tdraw_dashed_line(a, b, COL, 1.4, 5.0, true, true)",
		"\tdraw_circle(p, 9.0, COL, false, 1.0, true)",
		"\tdraw_line(a, b, COL, lw, true)",
		"\tdraw_circle(p, 1.8, COL)",
		"\tdraw_line(a, b, COL, 1.0 if m else 0.5, true)",
	])
	var got := UILayout.scan_line_widths(src)

	t.eq(got.size(), 8, "扫到 8 行有宽度实参 —— 实际：%s" % [got.keys()])
	t.eq(_at(got, 2), "1.4", "draw_line 的线宽在第 4 个实参")
	t.eq(_at(got, 3), "0.5", "**跨行**的调用也能扫到（行号算调用的起始行）")
	# ⚠️ 这一条是本节的**全部意义**：`draw_arc` 的线宽在第 7 个实参上。
	# 抄成"第 4 个"的话，扫到的会是 `0.0`（end_angle）与 `24`（point_count），
	# 既漏报又误报 —— 而误报出来的数字看起来很"像线宽"，非常难查。
	t.eq(_at(got, 5), "2.2", "draw_arc 的线宽在第 7 个实参（不是 22.0 这个半径、也不是 24）")
	t.eq(_at(got, 6), "1.0", "draw_rect 的线宽在第 4 个实参")
	t.eq(_at(got, 7), "1.4", "draw_dashed_line 的线宽在第 4 个实参")
	t.eq(_at(got, 8), "1.0", "draw_circle 的线宽在第 5 个实参（不是半径 9.0）")
	t.eq(_at(got, 9), "lw", "宽度写成变量时，把**变量名**抓出来（于是谁给 lw 赋值是可追的）")
	t.ok(not got.has(10), "只有三参的 draw_circle 不会顺着往下乱认一个参数")
	t.eq(UILayout.numbers_in(_at(got, 11)).size(), 2,
		"三元里的**两个**字面量都能挖出来（不这样写的话 else 那一支会溜过去）")


# ============================================================ 6. 发光只用于信息

static func _glow(t: T) -> void:
	for path: String in UI_FILES:
		var src := _code(path)
		var name := _short(path)
		# "装饰性发光"的实现手段就是加色混合 —— 三个 UI 脚本里一处都不该有。
		t.eq(src.count("BLEND_MODE_ADD"), 0, "%s 没有加色混合（发光不做装饰）" % name)
		t.eq(src.count("CanvasItemMaterial"), 0, "%s 不自己造材质" % name)

	# 全工程唯一一处"辉光"是主菜单的聚焦外圈。它**承载信息**
	#（"这一行是当前选中的"），所以保留；但必须是**细圈**，不能是 bloom。
	var menu := _code(UI_FILES[1])
	var glow := ""
	for line in menu.split("\n"):
		if (line as String).contains("grow(glow)"):
			glow = (line as String).strip_edges()
	t.ok(glow != "", "主菜单有聚焦辉光外圈（grow(glow)）")
	t.ok(glow.contains("LINE_STRUCT"), "聚焦辉光走结构线那一档：%s" % glow)
	t.ok(glow.contains("0.22"), "聚焦辉光 alpha = 0.22（细圈，不是 bloom）")


# ============================================================ 7. 一组等宽数字

static func _metrics(t: T) -> void:
	var font := ThemeDB.fallback_font
	t.ok(font != null, "默认字体可用（工程只带这一份，见 UILayout 的字重注释）")
	if font != null:
		var lo := 9999.0
		var hi := 0.0
		for d in range(10):
			var w := font.get_char_size("0123456789".unicode_at(d), 13).x
			lo = minf(lo, w)
			hi = maxf(hi, w)
		# 十个数字**必须等宽**：否则同一列里 "1111" 与 "8888" 的宽度不同，
		# 右对齐只保证右端对齐，位数会在框内左右飘。这是"等宽数字"的事实判据。
		t.near(hi, lo, 1.0, "默认字体的十个数字等宽（宽 %.2f / %.2f）" % [lo, hi])

	# 数值列一律右对齐 —— 右对齐比等宽字体更彻底地解决"数字跳"。
	for view: Vector2 in SuiteLayout.VIEWS:
		t.near(float(UILayout.ammo_columns(view)["value"]), UILayout.content_right(view), 0.001,
			"%s：弹药数值列右端 = content_right" % view)
	for path: String in RIGHT_ALIGNED_FILES:
		t.gt(float(_code(path).count("func _text_right(")), 0.0,
			"%s 有 _text_right()（右对齐的唯一通道）" % _short(path))


# ============================================================ 8. 语音必须配字幕

static func _subtitles(t: T) -> void:
	# 字幕 ⊇ 语音：有语音的必有字幕（玩家可能静音），反过来可以有（护盾击穿）。
	t.eq(FlightHUD.WARN_TEXT.size(), FlightHUD.WARN_PRIORITY.size(),
		"每条告警都有字幕（%d 条）" % FlightHUD.WARN_PRIORITY.size())
	for key: String in FlightHUD.WARN_PRIORITY:
		t.ok(FlightHUD.WARN_TEXT.has(key), "%s 有字幕" % key)

	for key: String in FlightHUD.VOICE_FOR:
		t.ok(FlightHUD.WARN_TEXT.has(key), "有语音的 %s 必有字幕" % key)
		var voice := str(FlightHUD.VOICE_FOR[key])
		t.ok(voice.begins_with("voice_"), "%s → %s 走的是座舱语音通道" % [key, voice])
		# ⚠️ 录音没到之前不许变成"告警没了"：降级路径必须存在。
		t.ok(SoundBank.voice_or_fallback(voice, "") != "",
			"%s 有降级路径（录音缺失时顶上合成警报）" % voice)

	# 字幕不许是缩写。设计要求原话是"语音必须配字幕"——
	# 一旦简写成 MSL，它就不再是字幕，而是一个要玩家现场解码的暗号。
	for key: String in FlightHUD.WARN_TEXT:
		var s := str(FlightHUD.WARN_TEXT[key])
		t.ok(not s.contains("."), "字幕「%s」不是缩写（没有点号）" % s)
		t.gt(float(s.length()), 3.0, "字幕「%s」是完整词" % s)

	# 逐条对应：告警成立时，字幕文本**就是** `warn_subtitle()` 给的那一句。
	var st := FlightHUD.no_warn_state()
	st["missile"] = true
	var lines := FlightHUD.warn_lines(st, 0.0, "地面")
	t.eq(lines.size(), 1, "只有 missile 成立时只出一行")
	if lines.size() == 1:
		var row: Dictionary = lines[0]
		t.eq(str(row["key"]), "missile", "那一行是 missile")
		t.eq(str(row["text"]), FlightHUD.warn_subtitle("missile"),
			"字幕文本 == warn_subtitle(missile)")
		t.eq(str(row["text"]), "MISSILE ALERT", "而且是完整句，不是 MSL")

	# 拉起告警必须带预测高度 —— 玩家原话「它说我撞海我都不知道海在哪」，
	# 那个数字不是装饰，是这一条的全部意义。
	var sub := FlightHUD.warn_subtitle("pull_up", 350.0, "海面")
	t.ok(sub.contains("PULL UP"), "拉起字幕含 PULL UP：%s" % sub)
	t.ok(sub.contains("350"), "拉起字幕含预测高度：%s" % sub)
	t.ok(sub.contains("海面"), "拉起字幕含地形词（海面 / 地面由地形决定）：%s" % sub)

	t.eq(FlightHUD.warn_lines(FlightHUD.no_warn_state(), 0.0, "地面").size(), 0,
		"没有任何告警时一行都不出")

	# 绘制顺序按 `WARN_ORDER`，与语音仲裁用的 `WARN_PRIORITY` **有意不同**。
	st = FlightHUD.no_warn_state()
	st["missile"] = true
	st["pull_up"] = true
	lines = FlightHUD.warn_lines(st, 0.0, "地面")
	t.eq(lines.size(), 2, "两条同时成立时出两行")
	if lines.size() == 2:
		t.eq(str((lines[0] as Dictionary)["key"]), "missile", "第一行是 missile（绘制顺序）")
		t.eq(str((lines[1] as Dictionary)["key"]), "pull_up", "第二行是 pull_up")
	t.eq(FlightHUD.WARN_ORDER[0], "missile", "WARN_ORDER 的第一条确实是 missile")
	t.eq(FlightHUD.WARN_PRIORITY[0], "pull_up",
		"而 WARN_PRIORITY 的第一条是 pull_up —— 两张表的差别是**有意的**")
	t.eq(FlightHUD.WARN_ORDER.size(), FlightHUD.WARN_STYLE.size(), "每条告警都有样式")
	for i in FlightHUD.WARN_ORDER.size():
		var k := str(FlightHUD.WARN_ORDER[i])
		t.ok(FlightHUD.WARN_STYLE.has(k), "%s 有字号 / 闪烁 / 行距" % k)

	# 护盾击穿是"有字幕但没有语音"的那一条：它已经有合成警报在响，
	# 再加一条人声会打架（§4.3.3）。
	st = FlightHUD.no_warn_state()
	st["ifield_down"] = true
	lines = FlightHUD.warn_lines(st, 0.0, "地面")
	t.eq(lines.size(), 1, "护盾击穿有字幕")
	t.ok(not FlightHUD.VOICE_FOR.has("ifield_down"),
		"护盾击穿**故意**没有语音（避免与合成警报打架）")


# ---------------------------------------------------------------- 显示缩放（批 12）

static func _display_scale(t: T) -> void:
	t.suite("UIStyle / 显示缩放（速度 ×0.6 · 高度 ×0.15，只改显示不改数值）")
	# 用户指定的两个数（初版 0.4/0.1，后微调抬档）。想微调就改 hud.gd 常量区这两个值
	# —— 判定/几何一概不走它们。
	#
	# ⚠️ 2026-09-25（1.3 批 M）：机体**实际**飞行速度整体 ×1.5（`SPEED_REAL_MULT`），
	# 而用户要求"**前端数据同步下调，和现在保持差不多的数值**"。
	# ⇒ `SPEED_DISPLAY_SCALE` 从 0.6 变成 `0.6 / 1.5 = 0.4`，**但显示出来的速度不变**。
	# 所以这一条不再写死 0.6（那会让"按用户要求把显示保持不变"这一步变成红），
	# 改成钉住**那个不变式**：`显示系数 × 实际倍率 == 0.6`。
	# ⚠️ 这才是这条断言的**本意** —— 它要防的是"有人顺手改了显示系数、玩家看到的数变了"，
	# 而不是"0.6 这个字面量本身"。
	t.near(FlightHUD.SPEED_DISPLAY_SCALE * SuitProfile.SPEED_REAL_MULT, 0.6, 0.0001,
		"显示系数 × 实际倍率 = 0.6（实际提速 150% 之后，**玩家看到的数一个没变**）")
	t.near(FlightHUD.ALT_DISPLAY_SCALE, 0.15, 0.0001, "高度显示系数 = 0.15（用户指定）")
	# ⚠️ 右栏是互相咬合的读数组：大数字 / VS / 高度带刻度 / 地面线距离
	# **必须同乘** ALT_DISPLAY_SCALE，否则"ALT÷VS≈几秒撞地"的心算和
	# 高度带的参照系直接错 10 倍。逐个显示点钉死（源码扫描）。
	# ⚠️ 按本套件的规矩走 `_code()`（剥注释）—— 注释里提到某个名字不算数。
	var src := _code("scripts/ui/hud.gd")
	# ⚠️ 2026-09-30 晚：大速度数字的**输入有两个来源**（机体空速 / 发射段火箭
	# `cockpit_readout`），所以字面量从 `airspeed_kmh() * SPEED_DISPLAY_SCALE`
	# 拆成"赋值"与"缩放"两半 —— 两半都钉住，规则反而比原来更紧。
	t.ok(src.contains("kmh = player.airspeed_kmh()"), "大速度数字的输入是机体空速")
	t.ok(src.contains("int(kmh * SPEED_DISPLAY_SCALE)"), "大速度数字走显示缩放")
	t.ok(src.contains("int(alt * ALT_DISPLAY_SCALE)"), "大高度数字走显示缩放")
	t.ok(src.contains("int(vs * ALT_DISPLAY_SCALE)"), "VS 与高度同缩（心算不失效）")
	t.ok(src.contains("a * ALT_DISPLAY_SCALE"), "高度带刻度标注与高度同缩")
	t.ok(src.contains("maxf(cur, 0.0) * ALT_DISPLAY_SCALE"), "地面线距离标注与高度同缩")
	# 判定逻辑必须**不**缩：PULL UP 的预测式保持真实米（字幕与阈值同一套单位）
	t.ok(src.contains("return alt + vertical_speed * PULL_UP_LOOKAHEAD"),
		"拉起告警判定仍走真实米（显示缩放不进判定）")


static func _cel_shading(t: T) -> void:
	t.suite("UIStyle / 三渲二渲染管线（cel-shading 后处理 + 机体 TOON 材质）")
	# 用户指定的视觉方向（教程 BV1PGBiBvEFG 的 cel-shading 思路）：
	# 双层落地 —— ① 全屏后处理（描边+色阶量化，覆盖整个 3D 画面）；
	# ② 机体材质切内置 TOON（真·光照色阶，比后处理量化干净）。
	# ⚠️ 无头环境不渲染，但 **shader 资源在 load 时会解析** ——
	# 语法错误会直接 load 出 null，这一条就是编译守卫。
	var cel := load("res://shaders/cel_post.gdshader") as Shader
	t.ok(cel != null, "cel_post.gdshader 解析通过（无头环境也能抓 shader 语法错）")
	# ⚠️ 无头只能验"能 load"，验不了"能编译"——headless 的 RenderingServer 是
	# dummy，shader 编译错误（比如 canvas_item 不支持 hint_depth_texture 这种）
	# 只在真渲染时报。批 19 的"进图全屏白光"就是这么漏进来的。
	# 改 shader 后必须跑一次真渲染探针（见验收报告 §15.15）。
	var shader_src := _src("shaders/cel_post.gdshader")
	# ⚠️ 后处理必须是 spatial 全屏面片（批 19 重写）：canvas_item 在 4.7
	# 不支持 hint_depth_texture，编译失败 → ColorRect 白屏。
	t.ok(shader_src.contains("shader_type spatial"),
		"cel 后处理是 spatial shader（canvas_item 不支持深度纹理，白屏教训）")
	t.ok(shader_src.contains("POSITION = vec4(UV"),
		"顶点写 clip space 铺满屏幕（与 FOV/分辨率/裁剪面无关）")
	t.ok(shader_src.contains("hint_depth_texture") and shader_src.contains("hint_screen_texture"),
		"后处理读深度 + 背缓冲（深度描边方案的两大输入）")
	t.ok(not shader_src.contains("hint_normal_roughness"),
		"法线边退役（G-buffer 法线在 spatial 读不到；内边交给 TOON rim）")
	# 机体 TOON：批 18 起实现收进 FX.toonify 单一真源（机体与踏板烤制模型共用），
	# 按本套件的规矩走 _code（剥注释）。
	var fb := _code("scripts/flight/flight_body.gd")
	t.ok(fb.contains("FX.toonify(mat)"), "机体受光材质走 FX.toonify 单一真源")
	t.ok(_code("scripts/world/fx.gd").contains("static func toonify"),
		"toonify 实现住在 FX（机体与踏板共用一份参数）")
	t.ok(_code("scripts/flight/flight_pedal.gd").contains("FX.toonify"),
		"踏板烤制的梅萨/古斯塔夫也走 TOON（同屏不割裂两种画风）")
	# 运行时行为：受光材质切 TOON+rim；unshaded（FX additive）豁免；幂等
	var toon_m := StandardMaterial3D.new()
	FX.toonify(toon_m)
	t.ok(toon_m.diffuse_mode == BaseMaterial3D.DIFFUSE_TOON
		and toon_m.specular_mode == BaseMaterial3D.SPECULAR_TOON
		and toon_m.rim_enabled, "运行时：受光材质切 TOON + 边缘光")
	var fx_m := StandardMaterial3D.new()
	fx_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	FX.toonify(fx_m)
	t.ok(fx_m.diffuse_mode == BaseMaterial3D.DIFFUSE_BURLEY,
		"运行时：unshaded（尾焰/爆闪/光晕）豁免，不吃 TOON")
	FX.toonify(toon_m)
	t.ok(toon_m.diffuse_mode == BaseMaterial3D.DIFFUSE_TOON,
		"运行时：toonify 幂等（踏板换载人状态重建模型时重复走无副作用）")
	# 全屏面片挂载：必须挂相机下（spatial 渲染），接设置开关；
	# extra_cull_margin 必须巨大（顶点被 vertex() 强制写 clip space，
	# 模型 AABB 其实在近平面之前，不保护会被视锥剔除整个吞掉）
	var main := _code("scripts/main.gd")
	t.ok(main.contains("cel_quad") and main.contains("CEL_POST_SHADER"),
		"main 挂载全屏 cel 面片并接设置开关")
	t.ok(main.contains("extra_cull_margin"),
		"cel 面片有视锥剔除保护（clip space 顶点的模型 AABB 在近平面前）")
	t.ok(main.contains("chase.add_child(cel_quad)"),
		"cel 面片挂在相机下（spatial 渲染管线，不是 HUD CanvasLayer）")
	# 设置页有开关行 + 持久化
	t.ok(_code("scripts/ui/main_menu.gd").contains("\"cel\""),
		"设置页有「三渲二渲染」行")
	t.ok(_code("scripts/autoload/settings.gd").contains("cel_shading"),
		"开关进 Settings 并持久化")
	# ========================================================================
	# ⚠️⚠️ 批 K · 轮 4：**上面这 19 条全是"接线"断言，一条都没在问"它真的在画吗"**
	# ========================================================================
	#
	# 正因为如此，本效果**从批 17 立项起一直没渲染过**（顶点翻 y ⇒ 屏幕空间绕序
	# 反转 ⇒ 被 `cull_back` 整片剔除），而套件从第一天起就是全绿 ——
	# 无头环境的 RenderingServer 是 dummy，**不编译 shader、不画一个像素**。
	#
	# 修活的当场就炸了（用户："地图光照一塌糊涂，什么都看不见了"：
	# 棕色天空被逐通道量化拆成饱和红、楼体暗面整片归零）。
	#
	# ⇒ 加下面四条**代码级**断言钉住那次修复，并把"默认值"钉成 **false**。
	#    （真渲染验证只能在 `tests/pixprobe.tscn` 里做 —— 见验收报告 §16。）

	# ① 绕序：两个分量都不许翻转。翻 y 就是把整个面片交给背面剔除。
	t.ok(shader_src.contains("POSITION = vec4(UV.x * 2.0 - 1.0, UV.y * 2.0 - 1.0, 0.0, 1.0);"),
		"顶点写的是 (2u−1, 2v−1) —— **两个分量都不翻**（翻 y 会被背面剔除以至一个像素都不画）")
	t.ok(shader_src.contains("blend_mix, cull_disabled"),
		"render_mode 带 cull_disabled（顶点写 clip space 时绕序不可控，剔除必须关掉）")

	# ② 量化必须在**亮度域**做，不能逐通道。
	#    逐通道在阴天黄昏的低亮度区会把三通道打到不同的阶上 ⇒ **拆色相**
	#    （实测：(0.30,0.24,0.20) 的棕天空 → (0.333,0.167,0.167) 的饱和红），
	#    并且把 `1/(2×阶数)` 以下的通道**整段归零** ⇒ 地面楼体全黑。
	t.ok(shader_src.contains("floor(enc * color_steps + 0.5) / color_steps"),
		"色阶量化在**感知域亮度**上做（`enc = pow(lum, 1/2.2)`），不是逐通道 floor(c×steps)")
	t.ok(shader_src.contains("pow(lum, 1.0 / 2.2)"),
		"感知域变换在位（保暗部：最暗一阶边界从 0.083 降到 ~0.006 线性）")
	t.ok(shader_src.contains("mix(1.0, saturation, intensity)"),
		"饱和度受 `intensity` 控制（原来漏了 ⇒ 总开关 0 时画面仍被改色）")

	# ③ 默认值：**关**。见 `settings.gd` 那段注释的完整理由。
	#    ⚠️ 这条**故意钉得死**：把它改回 true 之前先回答"云为什么不见了"。
	var set_code := _code("scripts/autoload/settings.gd")
	t.ok(set_code.contains("var cel_shading := false"),
		"三渲二后处理**默认关**（screen_texture 快照里没有透明几何 ⇒ 云会全部消失）")
	t.ok(set_code.contains("cel_migrated"),
		"老存档一次性迁移到位（旧档里的 `true` 是空操作时期写下的，不是玩家的有效选择）")
	# ⚠️ 近战黑屏修复守卫（批 19）：深度描边必须带**绝对米数下限**。
	# 纯相对差在近战（相机距机体 5 m ⇒ 阈值 ≈ 2 cm）下全屏过阈 → 整屏被
	# 描成边 ⇒ "近战斗什么都看不到"。这条钉死 shader 里必须有下限比较，
	# 想动它先想清楚是不是真的要恢复那个全屏黑的 bug。
	t.ok(shader_src.contains("outline_min_depth_diff"),
		"深度描边有绝对米数下限（outline_min_depth_diff，近战黑屏修复）")
	t.ok(shader_src.contains("diff < outline_min_depth_diff"),
		"下限真正参与深度差判定（不只是声明了没用）")
	# ⚠️ 进战斗地图黑屏修复守卫（批 19）：深度描边必须是**二阶差分**（对称外推）。
	# 一阶相对差在海洋图上被掠射渐变全屏击穿（俯角 10° 的海面相邻像素深度差
	# ≈ 4 m，相对差 >> 阈值）→ 大半屏被描成边 → "进战斗地图什么都看不到"。
	# 二阶差分对平滑渐变外推恒准、对跳变必偏——这是不能回退的算法级修复。
	t.ok(shader_src.contains("depth_edge_pair") and shader_src.contains("pred"),
		"深度描边走二阶差分（对称外推，平滑渐变不描、跳变才描）")
	t.ok(not shader_src.contains("depth_rel("),
		"一阶相对差描边已退役（它是进图黑屏的元凶）")
