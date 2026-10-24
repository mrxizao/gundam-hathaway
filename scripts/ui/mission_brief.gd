extends Control
## 任务简报页（DESIGN §6.1 的 **BRIEF** 段；§9.1 把它列为本轮新增文件）。
##
## ## 它读什么、不写什么
## **只读** `MissionScript.Mission`，一个字都不改 —— 简报页是"把数据摆出来"，
## 不是"再算一遍"。目标清单直接取 `Objective.label`（§5.2 的原话：
## 「HUD 上那一行（**玩家看到的唯一文案**）」）⇒ 简报页与 HUD 目标栏
## **天然同源**，不会出现"简报里说打捞、进游戏却让你击毁全部"。
##
## ## 与 `ChallengeScript` 那个旧"任务介绍"的区别
## 旧版把 `Encounter.brief` 当成一行 `notice` 弹一下就没了（`main._start_fight()` 里那句
## `player.notice.emit("%s —— %s" % [enc.title, enc.brief], 3.4)`）。
## 简报页要的是**停一屏**：任务名 / 地图 / 目标 / 敌情 / 电台预告各占一块，
## 玩家看完按确认才出击。
##
## ## 判据（DESIGN §11.2）
## `_draw()` 在无头下画不出东西 ⇒ 版式判据走**纯函数**：
## 本文件把"画哪些行、画在哪"全部抽成 `layout()` / `objective_lines()`，
## `_draw()` 只负责照着画。于是"目标清单可读、超长不溢出"可以被逐点验。
##
## ⚠️ 线宽与颜色一律走 `UILayout` / `FlightHUD` 的常量，不写字面量 ——
##   本文件暂时不在 `suite_ui_style.UI_FILES` 的扫描名单里，但规矩照守：
##   将来把它加进名单时，不会因此变红。

## 出击（玩家看完简报按了确认）。
signal confirmed
## 返回（Esc / 返回键）。
signal cancelled

const MS := preload("res://scripts/data/mission_script.gd")
## 战役层（借它的 `chapter_title()` —— 章节名的真源只有一处）。
## ⚠️ 走 `preload` 不走 `class_name`（同 `mission_title.gd` 那段说明）。
const CS := preload("res://scripts/data/campaign.gd")

## 是否吃输入、是否绘制。与 `MainMenu.active` 同一套语义：
## 关着的时候**既不画也不读键**（否则"按下确认"会被两个界面各吃一次）。
var active := false
## 当前展示的任务（`open()` 注入）。
var mission: MS.Mission = null
## 光标停在哪一行（本页只有"出击 / 返回"两个选项，对齐 `MainMenu` 的双选一做法）。
var cursor := 0

const OPTIONS := ["出击", "返回"]

## 屏幕上一次能放几条目标（**纯函数**，供测试逐 view 量）。
##
## ⚠️ 它答的是"**物理容量**"，与 `MainMenu.max_cards()` 同款语义：
## 排不下的部分走 `objective_lines()` 的截断提示，**不是**"这份目标不合法"。
const ROW_H := 30.0
const BLOCK_GAP := 16.0
const HEAD_H := 64.0
const FOOT_H := 52.0

## 电台预告那条带的高度。
##
## 算法：`_block()` 的标题画在 `+14`、分隔线在 `+22`、第一行基线在 `+58`
## ⇒ 要放下一行，**至少 62**。取 76 是留了那一行的下沿与带底的余量。
##
## ⚠️ 它必须**从正文里扣出来**，不能"看正文底下还有没有空地"。理由见 `layout()`。
const STORY_H := 76.0

var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	if _font == null:
		_font = ThemeDB.fallback_font
	visible = false
	set_process(false)
	set_process_input(false)


# ============================================================ 开关

## 打开简报页。`m` 为空 ⇒ 打开失败（调用方不该走到这一步）。
func open(m: MS.Mission) -> bool:
	if m == null:
		return false
	mission = m
	cursor = 0
	active = true
	visible = true
	# ★ 摇杆播种 —— 与战役图同一处纪律（见 `_seed_pad()`）。`_process` 下一帧才跑。
	_seed_pad()
	set_process(true)
	set_process_input(true)
	queue_redraw()
	return true


func close() -> void:
	active = false
	visible = false
	set_process(false)
	set_process_input(false)
	mission = null


# ============================================================ 输入（键盘 / 手柄）

## ---- 手柄：动作名，不是按钮号 ----
##
## ★★ 与 `campaign_map.gd` 同一条事故：这一页原来**只认 `InputEventKey`**
##（`if event is InputEventKey and ...`），手柄进不来 —— 而页脚早就印着
##「A 出击 / B 返回」（`_draw_hint()` 的 `InputSetup.hint()` 第二参数）。
## ⇒ 1.2 用户实测的「任务菜单选择的时候手柄按下没有反应」，这一页也在里面
##（它是选完关卡的下一页，同一个流程）。
##
## ⚠️ 认**动作名**不认按钮号的两个理由（可自定义重绑 / 十字键已被飞行功能征用）
## 与 `campaign_map.gd` 那段逐字相同，不在这里重写一遍 —— 只留这一行指针。
const PAD_LEFT := "missile_mode"      ## 十字键 ←
const PAD_RIGHT := "switch_weapon"    ## 十字键 →
const PAD_CONFIRM := ["confirm", "fire_gun"]

## 摇杆边沿状态（轴没有 `just_pressed`，只能自己判"刚过阈值的那一下"）。
var _pad_x_prev := 0.0
var _pad_y_prev := 0.0


## 进这一页时把摇杆播种成当前值（理由同 `campaign_map._seed_pad()`：
## 玩家进门时可能正推着摇杆，不播种会在第一帧凭空翻一次选项）。
func _seed_pad() -> void:
	var dev := PlayerController.active_joypad()
	_pad_x_prev = 0.0 if dev < 0 else Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
	_pad_y_prev = 0.0 if dev < 0 else Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)


## 摇杆：本页只有「出击 / 返回」两格，横竖都算"翻一下"。
## ⚠️ 横竖都收，是因为版式上这两格是**左右并排**的，而玩家推竖向也多半是想翻它们
##（只收横向的话，推上/下会是"完全没反应"——正是本轮要修的那种症状）。
func _process(_delta: float) -> void:
	var dev := PlayerController.active_joypad()
	if dev < 0:
		return
	var x := Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
	var y := Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
	var dx := MainMenu._edge(x, _pad_x_prev)
	var dy := MainMenu._edge(y, _pad_y_prev)
	_pad_x_prev = x
	_pad_y_prev = y
	if dx != 0 or dy != 0:
		_toggle()


## 翻一下「出击 ⇄ 返回」。
##
## ⚠️ 原来这个动作写死在 `_input()` 的分支里（`cursor = 1 - cursor; queue_redraw()`），
## 现在键盘 / 十字键 / 摇杆三处都要用它 ⇒ 抽成一个函数。
## 它不是"顺手重构"：三处各抄一遍的话，将来加第三格就会漏一处
##（`main_menu._nav_x/_nav_y` 那两个轴分家的教训，本仓库吃过两次）。
func _toggle() -> void:
	cursor = 1 - cursor
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			cancelled.emit()
			return
		if k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
			get_viewport().set_input_as_handled()
			_choose()
			return
		if k == KEY_LEFT or k == KEY_RIGHT or k == KEY_A or k == KEY_D:
			_toggle()
			get_viewport().set_input_as_handled()
			return
		return
	_joy(event)


## 手柄按键那一路（摇杆在 `_process` 里）。只认**按下**，理由同 `campaign_map._joy()`。
static func _joy_hit(event: InputEvent, actions: Array) -> bool:
	for a: String in actions:
		if event.is_action_pressed(a):
			return true
	return false


func _joy(event: InputEvent) -> void:
	if not (event is InputEventJoypadButton):
		return
	if not (event as InputEventJoypadButton).pressed:
		return
	if _joy_hit(event, PAD_CONFIRM):
		get_viewport().set_input_as_handled()
		_choose()
	elif event.is_action_pressed("menu_back"):
		get_viewport().set_input_as_handled()
		cancelled.emit()
	elif event.is_action_pressed(PAD_LEFT) or event.is_action_pressed(PAD_RIGHT):
		_toggle()
		get_viewport().set_input_as_handled()


func _choose() -> void:
	if cursor == 0:
		confirmed.emit()
	else:
		cancelled.emit()


# ============================================================ 版式（纯函数，可断言）

## 各块的矩形。**唯一的坐标真源** —— `_draw()` 只照着它画，
## 所以"超长不溢出"这件事可以被测试直接读 `layout()` 断言，不用截图。
##
## 布局：顶部标题条 → 左「地图 / 敌情」右「目标」→ 底部电台预告 → 脚注操作行。
static func layout(view: Vector2) -> Dictionary:
	var l := UILayout.content_left(view)
	var r := UILayout.content_right(view)
	var w := r - l
	var top := UILayout.MARGIN + UILayout.PAD
	var title := Rect2(l, top, w, HEAD_H)
	var body_top := title.position.y + title.size.y + BLOCK_GAP
	var foot_y := view.y - UILayout.MARGIN - UILayout.PAD - FOOT_H
	# ★ 电台预告**独占正文最底下那一条带**（在脚注之上）——
	# 而这一条带是**从正文里扣出来**的，不是"看正文底下还剩没剩地方"。
	#
	# ⚠️ 这一处踩过的坑（轮 C 出图时抓到的）：原来的写法是
	#     `story_y = foot_y - BLOCK_GAP - 30; if story_y > left.end.y: 画`
	# 而 `left`/`right` 本来就占满 `body_top … foot_y - BLOCK_GAP`
	# ⇒ `story_y > left.end.y` 在**所有分辨率下恒假**（1600×900 差 30 px、1280×720 也差 30 px）
	# ⇒ `Mission.story` **一次都没画出来过**。而画面上看不出"少了一块"——
	#   正文栏本来就只排 3 行，下面那片空地看着就像留白。
	#   这就是本工程最怕的形状：**装了、没显示、不报错**。
	# 现在它有了自己的矩形（`story_box()`），"画不画"由**版式**回答，
	# 于是 `suite_sally` 能对着一个纯函数断言，而不是对着一个恒假的条件。
	var story_y := foot_y - BLOCK_GAP - STORY_H
	var body_h := maxf(story_y - BLOCK_GAP - body_top, 0.0)
	# 左栏窄、右栏宽（目标清单是这一页的主体）
	var left_w := w * 0.34
	var right_w := w - left_w - UILayout.PAD
	var left := Rect2(l, body_top, left_w, body_h)
	var right := Rect2(l + left_w + UILayout.PAD, body_top, right_w, body_h)
	return {
		"frame": Rect2(UILayout.MARGIN, UILayout.MARGIN,
			UILayout.frame_width(view), view.y - UILayout.MARGIN * 2.0),
		"title": title,
		"left": left,
		"right": right,
		"story": Rect2(l, story_y, w, STORY_H),
		"foot": Rect2(l, foot_y, w, FOOT_H),
	}


## 左栏里「地图卡」与「敌情」两块的分界 y。
static func left_split(view: Vector2) -> float:
	var box: Rect2 = layout(view)["left"]
	return box.position.y + minf(box.size.y * 0.42, 150.0)


## 目标清单区（右栏里标题行之下）。
static func objective_box(view: Vector2) -> Rect2:
	var box: Rect2 = layout(view)["right"]
	var head := 34.0
	return Rect2(box.position.x, box.position.y + head,
		box.size.x, maxf(box.size.y - head - BLOCK_GAP, 0.0))


## 右栏一次排得下几行目标。**下界至少 1** —— 0 行等于"这一页什么都看不到"，
## 那比"最后一行贴着底边"糟得多。
static func max_rows(view: Vector2) -> int:
	return maxi(int(floor(objective_box(view).size.y / ROW_H)), 1)


## ★ 电台预告区（正文最底下那一条带，在脚注之上）。
##
## 抽成纯函数的理由与 `objective_box()` 一样：**"画不画"必须由版式回答**，
## 而不是由 `_draw()` 里一个当场写的条件回答 —— 那种条件没人测，恒假了也没人知道
##（这正是这一块原来的状态：`Mission.story` 一次都没画出来过，见 `layout()` 的注释）。
static func story_box(view: Vector2) -> Rect2:
	return layout(view)["story"]


## 目标行文案。**主要目标在前、次要目标在后**（玩家先看必做的那几条）。
##
## ⚠️ 主次要**不靠排序稳定**去猜，而是显式分桶 —— 否则将来 `objectives` 数组里
## 主次交错时，玩家会看到"次要目标排在主要目标上面"。
##
## 超出容量时**截断并补一行提示**（`…还有 N 条`），于是返回的行数**永不超容量**：
## 这条就是"超长不溢出"的可断言形式。
static func objective_lines(m: MS.Mission, view: Vector2) -> Array:
	if m == null:
		return []
	var req: Array = []
	var opt: Array = []
	for o: MS.Objective in m.objectives:
		if o.required:
			req.append(o)
		else:
			opt.append(o)
	var all: Array = []
	for o2: MS.Objective in req:
		all.append("[主] %s" % MS.plain(o2.label))
	for o3: MS.Objective in opt:
		all.append("[次] %s" % MS.plain(o3.label))
	var cap := max_rows(view)
	if all.size() <= cap:
		return all
	# 至少留一行给提示 ⇒ 内容行最多 cap - 1 条
	var keep := maxi(cap - 1, 0)
	var cut: Array = all.slice(0, keep)
	cut.append("…还有 %d 条" % (all.size() - keep))
	return cut


## 敌情行。**全部取自 `Mission` 已有字段**，不新增统计（与 §6.3 硬约束 2 同一条规矩）。
##
## ★ 轮 50：**“没有敌人”的关要如实说**（M01「夜袭达沃」）。
## 老写法无条件吐 “敌方：古斯塔夫00” + “波次 1 · 共 3 台”，
## 而 M01 现在**一架敌机都没有** ⇒ 简报页会在玩家出发前就撒一个谎，
## 而“目标只有一条、对面无人”正是这一关的全部设定。
##
## ⚠️ 判据走 `Mission.has_enemies()`（= `waves` 非空）而不是“看看能不能数出人” ——
## 两者字面上等价，但前者是**数据层的公开口**（`suite_campaign` 钉着它）。
## ⚠️ “无敌人”时**波次那两行一并撤掉**（不是改写成“波次 0 · 共 0 台”）——
## 报一个“0 台”会让人以为加载失败，而它是设定。
static func enemy_lines(m: MS.Mission) -> Array:
	if m == null:
		return []
	var out: Array = []
	if m.has_enemies():
		out.append("敌方：%s" % m.enemy_suit_name())
		out.append("波次 %d · 共 %d 台" % [m.wave_count(), m.total_enemies()])
	else:
		# ⚠️ 这一句的用词是**刻意**的：要让玩家读出“这是设定”而不是“加载不出来”。
		out.append("敌方：无 —— 本次是纯突袭")
	if m.is_pov():
		out.append("视角：%s" % m.player_suit_name())
	else:
		out.append("自机：%s" % m.player_suit_name())
	return out


## 地图行。
static func map_lines(m: MS.Mission) -> Array:
	if m == null:
		return []
	var out: Array = [m.map_name()]
	out.append("%s · %s" % [m.arena, time_label(m.time_key)])
	return out


## 时段键 → 中文。**`""` 表示"用地图自带的"**（`Mission.time_key` 的语义）。
static func time_label(key: String) -> String:
	match key:
		"night":
			return "夜"
		"dusk_overcast":
			return "阴天黄昏"
		"space":
			return "轨道（无昼夜）"
		_:
			return "按地图默认"


## 标题行文案（`MISSION 04 · 打捞`）。**编号取 `Mission.index`，不取数组下标** ——
## 章内序号是数据的一部分（§4.2 的表里 `M#` 与章内序号并不总相等）。
static func title_line(m: MS.Mission) -> String:
	if m == null:
		return ""
	return "MISSION %02d · %s" % [m.index, m.title]


## 章节键 → 「第一章 · 正当的预言之王」。
##
## ⚠️ 两个字段都取自 `CampaignScript.CHAPTERS`（`label` 与 `title`），**不另抄一份字面量** ——
## 战役图页那边只用了 `title`，这里两个都要，于是简报页上能同时看到
## "第几章"和"这一章叫什么"。
static func chapter_name(n: int) -> String:
	for c: Dictionary in CS.CHAPTERS:
		if int(c["n"]) == n:
			return "%s · %s" % [str(c["label"]), str(c["title"])]
	return ""


## 章节行（`第一章 · 正当的预言之王 · 第 4 关`）。
##
## ⚠️ 编号取 `Mission.index`（**章内序号**）—— 它与 `M#` 并不总相等
##（M05 是第二章的第 1 关），MISSION xx 那一行用的是 `index`，两处必须一致。
static func chapter_line(m: MS.Mission) -> String:
	if m == null:
		return ""
	var ch := chapter_name(m.chapter)
	if ch.is_empty():
		# 章号不认识（数据出错）⇒ 退回只写序号，而不是把整行画成空白
		return "第 %d 关" % m.index
	return "%s · 第 %d 关" % [ch, m.index]


# ============================================================ 绘制

func _draw() -> void:
	if not active or mission == null:
		return
	var l := layout(size)
	var frame: Rect2 = l["frame"]
	var title: Rect2 = l["title"]
	var left: Rect2 = l["left"]
	var right: Rect2 = l["right"]
	var foot: Rect2 = l["foot"]

	# ---- 背板与总外框（与主菜单/结算同一套网格：左右边缘都落在 MARGIN 上）----
	draw_rect(frame, Color(0.02, 0.03, 0.05, 0.86), true)
	draw_rect(frame, FlightHUD.deco_white(0.22), false, UILayout.LINE_STRUCT)

	# ---- 标题条 ----
	draw_string(_font, title.position + Vector2(0.0, 26.0), title_line(mission),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, FlightHUD.HUD)
	draw_string(_font, title.position + Vector2(0.0, 50.0), chapter_line(mission),
		HORIZONTAL_ALIGNMENT_RIGHT, title.size.x, 14, FlightHUD.NEUTRAL)
	var ul := title.position.y + title.size.y - 6.0
	draw_line(Vector2(frame.position.x, ul), Vector2(frame.end.x, ul),
		FlightHUD.deco_white(0.22), UILayout.LINE_HAIR)

	# ---- 左栏：地图卡 + 敌情 ----
	var split := left_split(size)
	_block(Rect2(left.position, Vector2(left.size.x, split - left.position.y)),
		"战场", map_lines(mission))
	_block(Rect2(Vector2(left.position.x, split),
			Vector2(left.size.x, left.end.y - split)), "敌情", enemy_lines(mission))

	# ---- 右栏：目标清单 ----
	_block(right, "目标", objective_lines(mission, size), true)

	# ---- 电台预告（`Mission.story` 的位子）----
	# ★ 它有自己的矩形（`story_box()`）⇒ "画不画"是**版式**说了算，不是一个现场条件。
	# 原文案里的 `**强调**` 由 `MS.plain()` 去掉（那是全工程唯一一处做这件事的地方）。
	_block(story_box(size), "电台预告", story_lines(mission))

	# ---- 脚注：两个选项 ----
	_draw_foot(foot)
	_draw_hint()


func _block(box: Rect2, head: String, lines: Array, emph := false) -> void:
	if box.size.y <= 0.0:
		return
	draw_string(_font, box.position + Vector2(0.0, 14.0), head,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		FlightHUD.HUD_DIM if emph else FlightHUD.HUD_FAINT)
	draw_line(Vector2(box.position.x, box.position.y + 22.0),
		Vector2(box.end.x, box.position.y + 22.0),
		FlightHUD.deco_white(0.18), UILayout.LINE_HAIR)
	for i in lines.size():
		var y := box.position.y + 40.0 + ROW_H * float(i) + 18.0
		if y > box.end.y - 2.0:
			break
		draw_string(_font, Vector2(box.position.x + 4.0, y), str(lines[i]),
			HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 8.0, 17, FlightHUD.NEUTRAL)


func _draw_foot(foot: Rect2) -> void:
	var x := foot.position.x
	for i in OPTIONS.size():
		var label := "[ %s ]" % OPTIONS[i]
		var col := FlightHUD.HUD if i == cursor else FlightHUD.HUD_DIM
		draw_string(_font, Vector2(x, foot.position.y + 26.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
		var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		x += w + 26.0


func _draw_hint() -> void:
	var s := InputSetup.hint("Enter 出击 / Esc 返回", "A 出击 / B 返回")
	var pos := Vector2(UILayout.content_right(size) - _font.get_string_size(
		s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, size.y - UILayout.MARGIN - 18.0)
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, FlightHUD.HUD_FAINT)


# ============================================================ 读数口（测试与探针）

## 画布上真正会出现的文案（`_draw()` 私有，断言要有一个稳定的读法）。
##
## ⚠️ 返回 `Dictionary` 而不是 `Array`：这两样东西在这一页上语义不同
## （一个是"标题那一行"，一个是"目标那几行"），用一个字典带名字取，
## 断言里写 `s["objectives"]` 比 `s[2]` 清楚得多，也不会因为加一块而全体错位。
func shown_lines() -> Dictionary:
	return {
		"title": title_line(mission),
		"chapter": chapter_line(mission),
		"objectives": objective_lines(mission, size),
		"enemies": enemy_lines(mission),
		"maps": map_lines(mission),
		"story": story_text(),
		"story_rows": story_lines(mission),
	}


func story_text() -> String:
	return MS.plain(mission.story) if mission != null else ""


## 电台预告区会画出的那几行。
##
## ⚠️ 它**不是**"把 story 按宽度折行" —— `draw_string()` 不折行，
## 超出给定宽度就**裁掉**（不是绕下去）。所以这里老老实实一行，
## 而带宽（`STORY_H`）是按一行定的。7 关的 `story` 最长的也就 30 来字，
## 在最小支持宽度（1280 → 内容区 1172 px）下绰绰有余。
static func story_lines(m: MS.Mission) -> Array:
	if m == null:
		return []
	var s := MS.plain(m.story)
	return [s] if not s.is_empty() else []


func option_text() -> Array:
	return OPTIONS.duplicate()
