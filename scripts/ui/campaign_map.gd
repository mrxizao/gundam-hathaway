extends Control
## 战役图页（DESIGN §6.1 的「[战役图] → 简报 → …」那个入口；§9.1 列为新增文件）。
##
## ## 它只做一件事：把 7 关摆出来，让玩家选一个**解锁了的**
## 全部判定走 `CampaignScript` 的现成纯函数（轮 0 就已落地）：
## `is_cleared()` / `is_unlocked()` / `current_id()` / `chapter_of()` / `chapter_title()`。
## **本页不自己算解锁** —— 解锁逻辑只有一份真源，否则"战役图上能选、进去说没解锁"
## 这种分家迟早出现（`by_id` 那类"两处各写一份"的坑已经吃过好几次）。
##
## ## 四态（§11.2 要求"四态可辨"）
## | 态 | 判据 | 玩家看到 |
## |---|---|---|
## | `CLEARED` | `is_cleared` | 亮 + 最好评价（`S` / `A` …） |
## | `CURRENT` | `id == current_id(progress)` | 高亮框（"该打这一关"） |
## | `OPEN` | `is_unlocked` 且未通关 | 普通可读 |
## | `LOCKED` | 其余 | 压暗 + 一把锁（**看得见但选不动**） |
##
## ⚠️ **压暗而不是隐藏**：玩家要知道"后面还有 6 关"，那是战役的驱动力。
## 隐藏掉的话，打完第一关会觉得"这游戏就一关"。
##
## ## 滚动窗口
## 7 关 + 2 个章节标题 = 9 行。1600×900 下排得下，但 1280×720 也排得下；
## 真正会溢出的是"以后关数变多"。⇒ 直接复用 `MainMenu.scroll_window()` 的
## 既有语义（**不新写一套滚动**）：`count <= n` 时窗口恒等于整份名单，
## 于是"现在只有 9 行"这件事的表现与不滚动**逐像素相同**。

signal mission_chosen(mission_id: String)
signal cancelled
signal difficulty_changed(level:int)
var super_hard_unlocked := false

## 光标的两种态：任务行 / 返回行（返回行恒在列表最后）。
const OPT_BACK := "< 返回>"

## 行高与容量。
const ROW_H := 34.0
const HEAD_H := 30.0
const FOOT_H := 56.0
## 列表区与脚注之间的间隔。
const BLOCK_GAP := 14.0

var active := false
## 玩家进度（`CampaignScript` 的那份字典）。**注入**，不自己去读盘 ——
## 于是测试可以喂一份构造好的进度，不必碰 `user://campaign.cfg`（§6.6 的污染坑）。
var progress: Dictionary = {}
## 光标停在第几个**任务**（0..6）。返回行用 `cursor == mission_ids().size()`。
var cursor := 0

## ★ 这一轮用哪个难度打（`Difficulty.Level`）。
##
## ## 为什么难度落**这一页**（轮 C 的入口修正）
##
## 它以前是主菜单旧挑战向导的第 4 页。轮 C 把剧情模式的入口换成"选完模式直接进战役图"
## 之后，那一步没了 —— 而**不能就这么算了**：难度是"玩家看不见却真实生效"的隐藏状态，
## 本工程把它列为**必须修掉的一类**（旧挑战只有 3 步没有难度页时，
## `_launch()` 照样把 `selected_level()` 传出去，踩过一次；见 `main_menu.step_labels()`）。
##
## 而战役图**本来就是循环的前门**（§6.1：`[战役图] → 简报 → … → 回战役图`）——
## "用哪个难度打这一关"属于"选关"这一屏，与"打哪一关"是同一个决定。
## ⇒ 它在这里显示、在这里切（左 / 右），并且随这一页一起被 `_sortie_campaign()` 读走。
##
## ⚠️ 名字的**唯一真源是 `Difficulty.make()`**（`name_cn`）—— 这里**不另抄一张表**，
## 否则"改一处漏一处"就是迟早的事（本仓库吃过好几次这种分家）。
var level := Difficulty.Level.NORMAL

## ★ 制作人模式（2026-09-30）。
##
## **注入**，不自己读 `Game`：与 `progress` 同一条分工 —— 这一页不认任何全局状态
##（"读盘 / 读全局"是 `main` 的事），于是测试可以喂一份"开着制作人模式"的页面
## 构造出任何组合，而不必去动 `Game`。
## 落值点：`main._open_campaign()`（`campaign_map.producer = Game.producer_mode`）。
##
## 它影响两件事：
##   ① **关卡锁全开**：`CampaignScript.can_enter()` 恒真（不存在的关除外）；
##   ② **军资显示 ∞**：`CampaignScript.credits_text()`。
##
## ⚠️ 它**不写盘**：这一页从头到尾没有一行"把 producer 存起来"的代码 ——
## 老板那句「制作人模式每次打开游戏都必须手动开启」就靠这个（见 `Game.producer_mode`）。
var producer := false

## ⚠️ **跨文件引用走 `preload`，不走 `class_name`**（本仓库统一纪律，理由见
## `campaign.gd` 里那段）：新加的 `class_name` 只有在编辑器重新扫过之后才进
## `.godot/global_script_class_cache.cfg`；在那之前任何 `CS.xxx`
## 都会**当场编译失败**，而 `--headless` 跑测试时没人会去刷新那份缓存。
## `preload` 按路径解析、与缓存无关 ⇒ 无头回归随时跑得起来。
## （`suite_campaign.gd` 用的也是同一条别名 `CS`，两处指向同一份真源。）
const MS := preload("res://scripts/data/mission_script.gd")
const CS := preload("res://scripts/data/campaign.gd")

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

## 打开。`p` 为空 ⇒ 现造一份空档（**不落盘**）。
##
## `keep_cursor`：从简报页返回时用 —— 玩家刚才停在哪一关就还在哪一关。
## 默认（false）会把光标挪到"当前该打的那一关"上。
func open(p: Dictionary, keep_cursor := false) -> bool:
	progress = p if not p.is_empty() else CS.new_progress()
	if not keep_cursor:
		# 光标默认停在"当前该打的那一关"上 —— 玩家回来看战役图，
		# 十次有九次是想接着打，不该让他每次自己找。
		cursor = clampi(CS.index_of(CS.current_id(progress)), 0,
			CS.mission_ids().size())
	active = true
	visible = true
	# ★ 摇杆播种（见 `_seed_pad()`）：`_process` 是**下一帧**才跑，
	# 所以只要在 `open()` 里落下即可 —— 但绝不能漏，漏了就"进门凭空跳一格"。
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


## 重新对准"当前关"（打完一关回战役图时用）。
func refresh() -> void:
	cursor = clampi(CS.index_of(CS.current_id(progress)), 0, CS.mission_ids().size())
	queue_redraw()


# ============================================================ 输入（键盘 / 手柄）

## ---- 手柄：动作名，不是按钮号 ----
##
## ★★ 这一页原来**只认 `InputEventKey`**（`if not (event is InputEventKey): return`），
## 于是**手柄一个键都进不来** —— 而页脚从落地那天就印着手柄文案
##（`_draw_hint()` 的 `InputSetup.hint()` 第二参数：`十字键选择 · 左右调难度 · A 出击 · B 返回`）。
## **提示承诺了、代码没实现** ⇒ 1.2 用户实测：「任务菜单选择的时候手柄按下没有反应」。
## 判据因此是"**页脚印的那几个键必须真的能用**"，下面认的动作就是页脚那一行里的那几个。
##
## ⚠️ 走的**不是** `InputEventJoypadButton.button_index`，而是
## `event.is_action_pressed("动作名")`，两个理由：
##   ① 手柄按键**可自定义**（`InputSetup.bound_pads()` / `pad_overrides`，批 10）——
##      写死按钮号会把玩家的重绑吃掉，症状是"改了没生效"，而这是本仓库反复吃过的坑；
##   ② 十字键在这一版被征用给了**飞行功能**（↑ 切目标 / ↓ 干扰弹 / ← 锁镜头 / → 换武器）
##      ⇒ 按钮号与"菜单里的意思"早就不是一一对应了，**动作名才是它的真源**。
##      这与 `MainMenu._nav_y()` 认 `switch_target`/`flares` 是同一张表
##      （菜单与飞行**阶段互斥**，所以一键两义在这里是安全的 —— 见 `main_menu.gd` 那段）。
##
## ⚠️ 键盘那一路**保持 keycode 不动**：页脚印的是 `W/S`、`A/D`，
## 而键盘本身也可重绑 ⇒ 两套并存、各认各的（`mission_title.gd` 早就是这个形状）。
const PAD_UP := "switch_target"       ## 十字键 ↑（同 `MainMenu.NAV_UP_ACTIONS`）
const PAD_DOWN := "flares"            ## 十字键 ↓
const PAD_LEFT := "missile_mode"      ## 十字键 ←
const PAD_RIGHT := "switch_weapon"    ## 十字键 →
## 确认的两个入口。与 `MainMenu` 逐字相同（A 与"右肩键"都算确认）。
const PAD_CONFIRM := ["confirm", "fire_gun"]


## 摇杆（轴）的边沿状态。
##
## ★ 轴**没有 `just_pressed` 的概念**，只能自己判"刚推过阈值的那一下"，
## 否则一直推着会每帧都触发、光标狂奔。判定**复用 `MainMenu._edge()`** ——
## 死区与边沿是同一个约束，不该在这里再写一份（"一个约束只能有一处算式"）。
var _pad_x_prev := 0.0
var _pad_y_prev := 0.0


## 进这一页时**把摇杆播种成当前值**。
##
## ⚠️ 少了它就会有一个"进页面凭空跳一格"的 bug：`_pad_*_prev` 的初值是 0.0，
## 而玩家进门时可能**正推着**摇杆 ⇒ 第一帧 `_edge(0.9, 0.0)` 判成"刚推过去"。
func _seed_pad() -> void:
	var dev := PlayerController.active_joypad()
	_pad_x_prev = 0.0 if dev < 0 else Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
	_pad_y_prev = 0.0 if dev < 0 else Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)


## 摇杆导航。**纵向优先**（与 `_input()` 里"上下选关 / 左右切难度"的分工一致）：
## 斜推时先选关，再调难度。
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
	if dy != 0:
		_move(dy)
	elif dx != 0:
		_cycle_diff(dx)


func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				cancelled.emit()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				get_viewport().set_input_as_handled()
				_choose()
			KEY_UP, KEY_W:
				_move(-1)
				get_viewport().set_input_as_handled()
			KEY_DOWN, KEY_S:
				_move(1)
				get_viewport().set_input_as_handled()
			# ★ 难度：左右切（与"上下选关"正交，所以不抢上下轴）。
			KEY_LEFT, KEY_A:
				_cycle_diff(-1)
				get_viewport().set_input_as_handled()
			KEY_RIGHT, KEY_D:
				_cycle_diff(1)
				get_viewport().set_input_as_handled()
		return
	_joy(event)


## 手柄按键那一路（摇杆在 `_process` 里，见上）。
##
## ⚠️ 只认**按下**（`pressed`），不认抬起 —— 菜单是"按一下走一步"，
## 抬起再响应会变成"松手才动"，手感上像是延迟了一拍。
## ⚠️ `is_action_pressed()` 的 `allow_echo` 默认 false，长按不会连发
##（手柄按键本来也没有键盘那种 `echo`，但这条要留给摇杆轴：它由 `_edge()` 管）。
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
	elif event.is_action_pressed(PAD_UP):
		get_viewport().set_input_as_handled()
		_move(-1)
	elif event.is_action_pressed(PAD_DOWN):
		get_viewport().set_input_as_handled()
		_move(1)
	elif event.is_action_pressed(PAD_LEFT):
		get_viewport().set_input_as_handled()
		_cycle_diff(-1)
	elif event.is_action_pressed(PAD_RIGHT):
		get_viewport().set_input_as_handled()
		_cycle_diff(1)


## 给事件一批动作名，任一命中即算（顺序 = 优先权）。
##
## ⚠️ 抽出来只为一件事：**判据能对着它逐条点名**（见 `suite_gamepad` 的
## 「页脚承诺的键」一节）—— 否则测试只能证明"按 A 有用"，
## 证明不了"页脚印的那一行字整行都兑现了"。
static func _joy_hit(event: InputEvent, actions: Array) -> bool:
	for a: String in actions:
		if event.is_action_pressed(a):
			return true
	return false


## 切难度后通知主流程；跨普通/超级困难时，由主流程注入对应存档。
func _cycle_diff(d: int) -> void:
	var next := cycle_difficulty(level, d, super_hard_unlocked)
	if next == level:
		return
	level = next
	difficulty_changed.emit(level)
	Audio.play_ui("ui_select")
	queue_redraw()


## 光标移动。**锁着的关也能停上去**（看得见为什么不能选），
## 但确认时不放行 —— "停不上"会让玩家以为那一关不存在。
func _move(d: int) -> void:
	var n := CS.mission_ids().size()
	var next := clampi(cursor + d, 0, n)     # n = 返回行
	if next == cursor:
		return
	cursor = next
	Audio.play_ui("ui_select")
	queue_redraw()


func _choose() -> void:
	var ids := CS.mission_ids()
	if cursor >= ids.size():
		cancelled.emit()
		return
	var id: String = ids[cursor]
	# ⚠️ 走 `CS.can_enter()`（不是 `is_unlocked()`）：它是**唯一**把
	# "进度允许吗"与"制作人模式打开了吗"合成一个答案的地方。
	# 直接写 `producer or CS.is_unlocked(...)` 也行，但那就把这层合成逻辑
	# 复制到每个调用点（今天有 3 个：这里、`state_of()`、脚注的着色）——
	# 迟早有一处忘了带上 `producer`，症状是"图上说可出击、按下去被拒"。
	if not CS.can_enter(progress, id, producer):
		# **明确拒绝**，不是"按了没反应"（§11.2 对机库页的同款要求：
		# 买不起的件要"显式不可点"，这里同理）。
		# ⚠️ 音效用 `ui_return` 而不是自造一个名：`SoundBank.SFX` 是**闭合表**，
		# 表里没有的名字 `play_self()` 只会静默无声（不报错）——
		# 菜单那一层用的也是 `ui_select` / `ui_confirm` / `ui_return` 这三个。
		Audio.play_ui("ui_return")
		return
	Audio.play_ui("ui_confirm")
	mission_chosen.emit(id)


# ============================================================ 版式（纯函数，可断言）

## 列表区与脚注区的矩形。
static func layout(view: Vector2) -> Dictionary:
	var l := UILayout.content_left(view)
	var w := UILayout.content_right(view) - l
	var top := UILayout.MARGIN + UILayout.PAD + 44.0
	var foot_y := view.y - UILayout.MARGIN - UILayout.PAD - FOOT_H
	return {
		"frame": Rect2(UILayout.MARGIN, UILayout.MARGIN,
			UILayout.frame_width(view), view.y - UILayout.MARGIN * 2.0),
		"list": Rect2(l, top, w, maxf(foot_y - BLOCK_GAP - top, 0.0)),
		"foot": Rect2(l, foot_y, w, FOOT_H),
	}


## 列表一次排得下几行（**物理容量**，不是"名单允许有几关"）。
static func max_rows(view: Vector2) -> int:
	var box: Rect2 = layout(view)["list"]
	return maxi(int(floor(box.size.y / ROW_H)), 1)


## 行结构：章节标题行 + 任务行（**两章 ⇒ 两个标题行**）。
##
## ⚠️ 结构只依赖 `CampaignScript` 的章节划分，**不依赖 progress** ——
## 于是"哪几行"是稳定的，"每行长什么样"才随进度变（两者分开才测得出）。
static func rows() -> Array:
	var out: Array = []
	var last := -1
	for id: String in CS.mission_ids():
		var ch := CS.chapter_of(id)
		if ch != last:
			out.append({"kind": "head", "id": "", "text": CS.chapter_title(ch)})
			last = ch
		out.append({"kind": "mission", "id": id})
	return out


## 某个任务在 `rows()` 里的下标（滚动窗口要按**行**算，不能按任务序号 —— 中间夹着标题行）。
static func row_index_of(id: String) -> int:
	var rs := rows()
	for i in rs.size():
		if str(rs[i].get("id", "")) == id:
			return i
	return 0


enum State { CLEARED, CURRENT, OPEN, LOCKED }

## 四态判定。**顺序有意义**：先判通关，再判"当前"，最后才看解没解锁。
##
## ⚠️ `producer`（制作人模式）**只影响第三档**：
##   已通关的照旧写"已通关"、"当前该打的那一关"照旧写"◀ 当前" ——
##   那两条是**事实**（`is_cleared` / `current_id`），不该因为开了制作人模式就消失。
##   变的只有"锁着的那 6 关现在能进"（`State.OPEN`）。
##   ⇒ 于是制作人模式开着时，**屏幕上不会再出现任何一把锁**，
##     而"我打到哪了"这条信息一个字都没丢。
static func state_of(progress: Dictionary, id: String, producer := false) -> int:
	if CS.is_cleared(progress, id):
		return State.CLEARED
	if id == CS.current_id(progress):
		return State.CURRENT
	if CS.can_enter(progress, id, producer):
		return State.OPEN
	return State.LOCKED


## 态 → 右侧那个短标签。**锁着的关也要给出理由**（"通关上一关"），
## 而不是一个孤零零的锁 —— 玩家得知道怎么才能开。
static func state_label(progress: Dictionary, id: String, producer := false) -> String:
	match state_of(progress, id, producer):
		State.CLEARED:
			# ⚠️ 显式过一道 `Dictionary` 类型：`progress.get()` 的返回值是 `Variant`，
			# 直接 `.get(id, "")` 在静态检查下不可靠（运行时能跑，但会在别处炸）。
			# ⚠️ 只认**真的字母**：存档里"还没成绩"写作 `-`（`CampaignScript._pack_grades`
			# 的占位符），而**手改档 / 半截档**完全可能把它带进来 ——
			# 那样会画出"已通关 -"，看着像这个字母就叫减号。
			var bg: Dictionary = progress.get("best_grade", {})
			var g := str(bg.get(id, ""))
			return ("已通关 %s" % g) if (not g.is_empty() and g != "-") else "已通关"
		State.CURRENT:
			return "◀ 当前"
		State.OPEN:
			return "可出击"
		_:
			return "需通关上一关"


## 任务行文案（不含状态标签；标签由 `_draw()` 右对齐画）。
static func line_of(id: String) -> String:
	var m: MS.Mission = MS.by_id(id)
	if m == null:
		# ⚠️ 表里没有这一关 ⇒ 用 id 兜底而不是空串：空串会让这一行**看不见**，
		# 而"少了一关"比"这一关名字难看"难查得多。
		return "%s  （数据缺失）" % id
	return "%s   %s" % [id, m.title]


## ★ 脚注上那一行「难度 ◀ 中等 ▶」。
##
## ⚠️ 名字**只从 `Difficulty.make()` 取**（`name_cn`）：`Difficulty` 是难度表的唯一真源，
## 这里再写一张 `{0:"简单",1:"中等",2:"困难"}` 就是第二份说法 ——
## 改了 `make()` 而忘了这里，图上就会印一个不存在的难度名，而且**不报错**。
static func difficulty_text(lv: int) -> String:
	return "难度  ◀ %s ▶" % Difficulty.make(lv).name_cn


## 难度在 `Difficulty.all_levels()` 上循环（左 −1 / 右 +1）。
## 不认识的 `lv`（手改档 / 将来加档）先落回"普通"再走，绝不返回非法值。
static func cycle_difficulty(lv: int, delta: int, unlocked:=false) -> int:
	var levels := Difficulty.all_levels(unlocked)
	var at := levels.find(lv)
	if at < 0:
		at = levels.find(Difficulty.Level.NORMAL)
	return levels[posmod(at + delta, levels.size())]


# ============================================================ 绘制

func _draw() -> void:
	if not active:
		return
	var l := layout(size)
	var frame: Rect2 = l["frame"]
	var list: Rect2 = l["list"]
	draw_rect(frame, Color(0.02, 0.03, 0.05, 0.86), true)
	draw_rect(frame, FlightHUD.deco_white(0.22), false, UILayout.LINE_STRUCT)

	# ---- 标题 + 军资余额（§11.2 明写要"军资余额显示"）----
	draw_string(_font, Vector2(UILayout.content_left(size), UILayout.MARGIN + UILayout.PAD + 8.0),
		("超级困难战役 · %s" if level==Difficulty.Level.SUPER_HARD else "战役 · %s") % CS.chapter_title(progress.get("chapter", 1)),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, FlightHUD.HUD)
	var money := credits_text()
	draw_string(_font, Vector2(UILayout.content_left(size) + 4.0,
		UILayout.MARGIN + UILayout.PAD + 32.0), money,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, FlightHUD.WARN)
	# ★ 制作人模式的标记：**开着就一定要能一眼看见**。
	# 少了它，开发者会在"自己改了进度吗、还是那只是制作人模式"之间反复怀疑 ——
	# 一个静默生效的调试开关比一个明显的调试开关危险得多
	#（本工程把"玩家看不见却真实生效的状态"列为必须修掉的一类）。
	if producer:
		# ⚠️ 右对齐**必须给一个正的宽度**（`-1` 或 `0` 时对齐参数会被忽略，文本从锚点往右画）。
		# 这里照 `_draw_foot()` 那条写：锚在内容区左边、宽度 = 内容区宽 ⇒ 落在右边界上。
		draw_string(_font, Vector2(UILayout.content_left(size),
			UILayout.MARGIN + UILayout.PAD + 8.0),
			"★ 制作人模式 · 全关卡解锁", HORIZONTAL_ALIGNMENT_RIGHT,
			UILayout.content_right(size) - UILayout.content_left(size), 19,
			FlightHUD.WARN)

	var rs := rows()
	var ids := CS.mission_ids()
	# 光标所在行（任务行 / 返回行）→ rows 里的下标，供窗口对齐
	var focus_row := row_index_of(ids[cursor]) if cursor < ids.size() else rs.size()
	var win := MainMenu.scroll_window(rs.size(), focus_row, max_rows(size))
	var y := list.position.y
	for i in range(win.x, mini(win.x + win.y, rs.size())):
		var row: Dictionary = rs[i]
		if str(row.get("kind", "")) == "head":
			draw_string(_font, Vector2(list.position.x + 2.0, y + 20.0), str(row["text"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, FlightHUD.HUD_DIM)
			y += HEAD_H
			continue
		_draw_mission_row(Rect2(list.position.x, y, list.size.x, ROW_H),
			str(row["id"]), ids[cursor] if cursor < ids.size() else "")
		y += ROW_H
	if cursor >= ids.size():
		_draw_back_row(Rect2(list.position.x, y, list.size.x, ROW_H))

	_draw_foot(l["foot"])
	_draw_hint()


func _draw_mission_row(box: Rect2, id: String, focused_id: String) -> void:
	var st := state_of(progress, id, producer)
	var hot := id == focused_id
	var col := FlightHUD.NEUTRAL
	if st == State.LOCKED:
		col = FlightHUD.deco_white(0.30)
	elif st == State.CLEARED:
		col = FlightHUD.HUD
	elif st == State.CURRENT:
		col = FlightHUD.WARN
	if hot:
		draw_rect(box, FlightHUD.deco_white(0.10), true)
		draw_rect(box, FlightHUD.deco_white(0.42), false, UILayout.LINE_STRUCT)
	draw_string(_font, Vector2(box.position.x + 12.0, box.position.y + 22.0), line_of(id),
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 200.0, 17, col)
	draw_string(_font, Vector2(box.position.x, box.position.y + 22.0),
		state_label(progress, id, producer), HORIZONTAL_ALIGNMENT_RIGHT, box.size.x - 12.0, 14,
		col if st != State.LOCKED else FlightHUD.deco_white(0.34))


func _draw_back_row(box: Rect2) -> void:
	draw_rect(box, FlightHUD.deco_white(0.10), true)
	draw_rect(box, FlightHUD.deco_white(0.42), false, UILayout.LINE_STRUCT)
	draw_string(_font, Vector2(box.position.x + 12.0, box.position.y + 22.0), OPT_BACK,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, FlightHUD.NEUTRAL)


## 脚注：**难度（恒显示）** + 选中那一关的目标摘要（**从 `Mission` 现读**，与简报页同源）。
func _draw_foot(foot: Rect2) -> void:
	# ★ 难度**先画、恒画** —— 停在"返回行"上也要看得见（玩家可能只是想调一下难度再走）。
	# ⚠️ 它与左边那句目标摘要共用一条基线，所以左边那句把宽度让出 260 px（见下）。
	draw_string(_font, Vector2(foot.position.x, foot.position.y + 20.0),
		difficulty_text(level), HORIZONTAL_ALIGNMENT_RIGHT, foot.size.x, 15, FlightHUD.HUD_DIM)
	var ids := CS.mission_ids()
	if cursor >= ids.size():
		return
	var m: MS.Mission = MS.by_id(ids[cursor])
	if m == null:
		return
	var parts: Array[String] = []
	for o: MS.Objective in m.objectives:
		# ⚠️ 走 `MS.plain()` —— 数据里的 `**强调**` 标记不该画到屏幕上
		#（渲染期的规范化只有那一处，见 `mission_script.plain()` 的注释）。
		parts.append(MS.plain(o.label))
	draw_string(_font, Vector2(foot.position.x, foot.position.y + 20.0),
		" · ".join(parts), HORIZONTAL_ALIGNMENT_LEFT, maxf(foot.size.x - 260.0, 0.0), 15,
		FlightHUD.NEUTRAL if CS.can_enter(progress, ids[cursor], producer)
			else FlightHUD.deco_white(0.34))


func _draw_hint() -> void:
	var s := InputSetup.hint("W/S 选择 · ←/→ 难度 · Enter 出击 · Esc 返回",
		"十字键选择 · 左右调难度 · A 出击 · B 返回")
	var pos := Vector2(UILayout.content_right(size) - _font.get_string_size(
		s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, size.y - UILayout.MARGIN - 18.0)
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, FlightHUD.HUD_FAINT)


# ============================================================ 读数口（测试与探针）

func selected_id() -> String:
	var ids := CS.mission_ids()
	return ids[cursor] if cursor < ids.size() else ""

func focus_text() -> String:
	return line_of(selected_id()) if not selected_id().is_empty() else OPT_BACK

## 军资那一行的读数。
##
## ⚠️ 走 `CampaignScript.credits_text()`（数据层）而不是在这里拼字符串：
## 制作人模式下它要显示 `军资 ∞`，而"制作人模式该显示什么"只该有一份说法
##（见 `campaign.gd` 的 `credits_of()` 与那条"绝不写进存档"的纪律）。
func credits_text() -> String:
	return CS.credits_text(progress, producer)

## 脚注上那一行的读数（`level` 是实例字段，`difficulty_text()` 是纯函数 ⇒ 两者都要有，
## 断言既能逐点验纯函数，也能验"实例身上记着的是哪一个难度"）。
func level_label() -> String:
	return difficulty_text(level)

func visible_rows() -> Array:
	var rs := rows()
	var ids := CS.mission_ids()
	var focus_row := row_index_of(ids[cursor]) if cursor < ids.size() else rs.size()
	var win := MainMenu.scroll_window(rs.size(), focus_row, max_rows(size))
	var out: Array = []
	for i in range(win.x, mini(win.x + win.y, rs.size())):
		out.append(str(rs[i].get("id", "")) if str(rs[i].get("kind", "")) == "mission"
			else "— %s —" % str(rs[i].get("text", "")))
	return out
