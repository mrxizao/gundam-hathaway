# =====================================================================
#  scripts/flight/comms_director.gd —— **通讯播放器**（轮 E 的落点）
#
#  它管三件事：
#    ① **队列**：谁先播、谁等谁（四种样式各有自己的"兰"）；
#    ② **在场时间**：一条台词显示多久、打字机打到第几个字；
#    ③ **触发器演出侧**：把 `Mission.triggers` 里 `radio:` 那一条**吃掉**，
#       并把没接管的动作原样交还给调用方。
#
#  ## 为什么它自己不做 `_draw()`
#
#  它是**纯状态机**（`RefCounted`，不 extends Control、不持节点）——
#  这样套件能在**不进游戏**的情况下把"队列顺序 / 在场时长 / 去重 / 打字机"
#  逐点喂出来。怎么画归 `hud.gd`（本工程所有面板都是这套分工：
#  `MissionRating` ↔ `hud._draw_result`、`UILayout` ↔ 各 `_draw_*`）。
#
#  ## ★ 三条不许违反的规矩
#
#  1. **`fired` 只有这一个持有人**。`Trigger` 数据里**不存** `fired`
#     （`mission_script.gd` 头部第 3 条坑标：数据被 7 关共享，
#     把"已触发"写进数据 = 第二局带着第一局的触发记录）。
#     运行时的"已触发"记在 `_fired`（本对象），main **不许再记一份**。
#  2. **查不到台词就不播、并且要说出来**。`COMMS.radio()` 对不认识的 id
#     返回空字典（不兜到别的 id 上）。症状"这一关少了半场戏"必须能被
#     `warnings()` 抓到，而不是让玩家自己去察觉。
#  3. **不落盘**。本对象整个是会话级内存；`Game.reset()` 时由调用方 `clear()`。
# =====================================================================
extends RefCounted

const COMMS := preload("res://scripts/data/comms.gd")
const MS := preload("res://scripts/data/mission_script.gd")
# ⚠️ `UILayout` **不 preload**：`scripts/ui/ui_layout.gd` 自己有 `class_name UILayout`，
# 全工程都直接用这个全局类（`hud.gd` 也这么用）。再 `const UILayout := preload(...)`
# 会与全局类**撞名**（而且新类走 `class_name` 在本仓库的并行编辑下不稳 ——
# 但 `UILayout` 是**既有**类，早就进了 `.godot/global_script_class_cache.cfg`）。


# ============================================================ 节拍
## 一条台词**出场**的淡入时长（秒）。
const FADE_IN := 0.16
## **退场**淡出时长（秒）。退场比进场慢：进场是"突然出现"，退场要留下余韵。
const FADE_OUT := 0.32
## 两条台词之间的最小间隔（秒）—— 同一队列连着播时不至于糊成一条。
const GAP := 0.22
## 队列上限。电台是"事件推的"，一关里理论上最多几十条；
## 真被灌爆时丢**最老的**，因为最新的一条才是当前战场态势。
const MAX_QUEUE := 24


# ============================================================ 版式（纯函数）
#
# 只给**几何**，不给颜色/字号（那是 hud 的事）。四个函数都是纯的，
# 所以"压没压到姿态仪""1280 下排得下几条"可以直接断言，不用截图。

## 电台框宽度。
const RADIO_W := 380.0
## 电台框单条高度。
##
## 62 = 呼号行（13 px 字，落在 +16）+ 正文两行（15 px 字，落在 +36 / +56）+
## 下沿 6 px 余量。**不是随手定的**：正文折行上限就是 2 行
## （`hud._wrap(..., COM_RADIO_MAX_LINES)`），框高必须刚好容下它，
## 少一行会把第二行截掉（`draw_string` 不会自己收边），多一行则三条排不下。
const RADIO_ROW_H := 62.0
## 电台框之间的缝。
const RADIO_GAP := 6.0
## **电台同时最多几条**。三条以上读不过来，而且会顶到速度块上去
##（`radio_columns()` 会按窗口高度再收紧一次，这里只是硬上限）。
const RADIO_MAX := 3
## 电台框底边与血条块顶边的距离。
const RADIO_BOTTOM_PAD := 18.0
## 电台框左边缘相对内容区左边距的缩进。
##
## ⚠️ **必须让开姿态仪**：姿态仪盘心在 `content_left + ATTITUDE_RADIUS`，
## 直径 112 —— 电台从 `content_left` 起画就会把它盖掉一半。
## 136 = 一盘（112）+ 24 缝。这个数写死在这里是**有意的**：
## 它引用的是 `hud.ATTITUDE_RADIUS`，而那份常量在本文件之外，跨文件引用
## 只能靠这个数 + 注释同步（改姿态仪半径时**这一行要一起看**）。
const RADIO_LEFT_INSET := 136.0
## 字幕条宽度上限与距屏幕左右的最小留白。
const SUBTITLE_MAX_W := 920.0
const SUBTITLE_MARGIN := 40.0
## 一行文字的行高（画的时候字号 ≤ 18，所以一行 26 够）。
const LINE_H := 26.0
## 文本条上下内边距合计。
const BAND_PAD := 18.0


## 这一屏电台最多排几条（1..RADIO_MAX）。
##
## 上界是血条块顶边，下界是**速度块的最低一行**（`hud.SPEED_BLOCK_BOTTOM_PAD`
## 那套口径 —— 速度块在屏幕左中，电台在它下方，两个都不许被压）。
## 1280×720 下这里会收到 **1** 条，1600×900 下是 3 条。
## ⚠️ 那两个数是**算出来的**（2026-09-30 用 `tools/shots_comms.gd` 的读数核过），
## 不是拍的：1600×900 的可用高 = 774 − 570 = 204 ⇒ 204/68 = 3.0 → 3；
## 1280×720 的可用高 = 594 − 480 = 114 ⇒ 114/68 = 1.67 → **1**
## （两条要 62×2 + 6 = 130 > 114）。本注释曾写"720 下 2 条"，是错的。
##
## ⚠️ 这里刻意**不写死** `speed_block_bottom` 的算式，只接受调用方算好传进来的
## 下界（`floor_y`）—— HUD 那边有 `attitude_center()` 已经把同一套约束算过一遍，
## 两边各写一份必有一天对不上。**一个约束只能有一处算式**。
static func radio_columns(view: Vector2, floor_y: float, ceil_y: float) -> int:
	var avail := ceil_y - floor_y
	if avail <= 0.0:
		return 1
	var n := int(avail / (RADIO_ROW_H + RADIO_GAP))
	return clampi(n, 1, RADIO_MAX)


## 电台框（第 `i` 条，共 `n` 条）。**从下往上**排：最新的在最下面。
##
## 从下往上而不是从上往下，是因为底边由血条块定死（它是常驻的），
## 而"上面还有多少空间"会随左上角那个游标（辅助驾驶/踏板/系统/教学）变化 ——
## 从上往下排的话，游标一长电台就整体下移，读的人每次都要重新找位置。
static func radio_rect(view: Vector2, i: int, n: int, ceil_y: float) -> Rect2:
	var cnt := clampi(n, 1, RADIO_MAX)
	var idx := clampi(i, 0, cnt - 1)
	var bottom := ceil_y
	var x := UILayout.content_left(view) + RADIO_LEFT_INSET
	var w := minf(RADIO_W, maxf(view.x - x - UILayout.MARGIN, 60.0))
	var y := bottom - float(cnt - idx) * (RADIO_ROW_H + RADIO_GAP) + RADIO_GAP
	return Rect2(x, y, w, RADIO_ROW_H)


## 字幕 / 对白 / 播报条：**居中**、给定底边。
##
## `bottom_y` 由调用方给（HUD 知道第一人称时底下有一整条座舱仪表台，
## 字幕要抬到它上面）—— 见本文件头部"一个约束只能有一处算式"。
static func centered_rect(view: Vector2, bottom_y: float, lines: int,
		max_w := SUBTITLE_MAX_W) -> Rect2:
	var n := maxi(lines, 1)
	var h := BAND_PAD + LINE_H * float(n)
	var w := minf(max_w, maxf(view.x - SUBTITLE_MARGIN * 2.0, 120.0))
	return Rect2((view.x - w) * 0.5, bottom_y - h, w, h)


## 播报条（SPTV 这类**单向**播报）：贴屏幕上方。
##
## 为什么不放底下：播报与"说话人"没有互动关系，放在字幕位会让人以为
## 是场内谁在说话。放上方 + 没有呼号，一眼就分清是"外面传进来的"。
static func alert_rect(view: Vector2, lines: int, top_y: float) -> Rect2:
	var n := maxi(lines, 1)
	var h := BAND_PAD + LINE_H * float(n)
	var w := minf(SUBTITLE_MAX_W, maxf(view.x - SUBTITLE_MARGIN * 2.0, 120.0))
	return Rect2((view.x - w) * 0.5, top_y, w, h)


## 字幕与对白**同时在场**时，字幕让到对白上面几像素。
##
## 为什么不是"贴在一起"：两条都有外框（`draw_rect(..., false, LINE_STRUCT)`），
## 零距离时两根框线会叠成一根更粗的线，看起来像一条框画歪了。
const BAND_STACK_GAP := 8.0


## 电台兰的下界与下中那条带之间留的缝。
const RADIO_BAND_GAP := 10.0


## 电台兰的**上界**（`ceil_y`）：既不许压血条，也不许与下中那条带相交。
##
## ## 为什么需要它（2026-09-30 由 `tools/shots_comms.gd` 的 `05_all_lanes` 抓到）
## 电台兰在**左**（`x ∈ [content_left + RADIO_LEFT_INSET, + RADIO_W]`，
## 1600 宽下是 `190..570`），下中那条带**居中且宽**（`SUBTITLE_MAX_W = 920`
## ⇒ `x ∈ [340, 1260]`）。两者**竖直方向本来就该错开**，但
## "电台下界 = 血条上方"（774）与"带子底边 = `_band_bottom_y()`"（768）
## 几乎重合 ⇒ 只要有一行字幕/对白在场，两个框就会在 `x ∈ [340, 570]`
## 这一段**横着切过去**（字幕框的左边线压在电台框上）。
##
## 这不是"某一兰画错了"，是"**四条兰互不相干**"这句话本身不成立 ——
## 左兰与下中兰在几何上是有交集的，必须由**一处算式**决定谁让谁。
## 这里让**电台抬上去**（下中那条带是"贴下沿"的语义，抬不动）。
##
## `band_top` 用 `INF` 表示"下中那条带不在场"。
##
## ⚠️ 代价是**电台条数会随字幕出现而减少**（1600×900：无字幕 3 条、
## 一行字幕 2 条、三行字幕 1 条）—— 这是有意的降级：宁可少显示几条电台，
## 也不能让两块字压在同一个像素上。
static func radio_ceil_y(blood_ceil: float, band_top: float) -> float:
	return minf(blood_ceil, band_top - RADIO_BAND_GAP)


## 屏幕下中那**一条带**上两条的框：`{"subtitle": Rect2, "dialogue": Rect2}`。
## 不在场的那条给**空 `Rect2()`**（`size == Vector2.ZERO`）。
##
## ## 为什么要合成一个函数
## 字幕与人物对话**是同一条带上的两条**：都居中、都用 `centered_rect()`、
## 宽度都由同一个 `max_w` 决定。各自拿 `base_y` 当底边的话 ——
## **同时在场时会像素级精确重叠**（不是"挨着"，是两条框完全重合、外面那圈
## 框线叠在一起、字号大的那行直接压住字号小的那行）。
##
## ⚠️ 这个错**单拍任何一张图都看不出来**：只出"字幕"或只出"对白"时各自都完美。
## 它只在四条兰一起摆上时才现形 —— `tools/shots_comms.gd` 的 `05_all_lanes`
## 就是为这一条存在的，也是它先抓到的问题（2026-09-30）。
##
## ## 谁在下面
## **对白在下**（贴 `base_y`）、**字幕让到它上面**。对白带名字牌、字号更大，
## 是"有人在跟你说话"这条主通道；字幕那条在这里是压画面的单向播报。
static func band_stack(view: Vector2, base_y: float, sub_lines: int, dlg_lines: int,
		max_w := SUBTITLE_MAX_W) -> Dictionary:
	var out := {"subtitle": Rect2(), "dialogue": Rect2()}
	var dlg := Rect2()
	if dlg_lines > 0:
		dlg = centered_rect(view, base_y, dlg_lines, max_w)
		out["dialogue"] = dlg
	if sub_lines > 0:
		var bottom := base_y
		if dlg_lines > 0:
			# 对白在场 ⇒ 字幕抬到对白框**上沿之上**（不是"底边减个高度"：
			# 对白框高随折行数变，拿一个常量去顶必然有一天差一截）
			bottom = dlg.position.y - BAND_STACK_GAP
		out["subtitle"] = centered_rect(view, bottom, sub_lines, max_w)
	return out


# ============================================================ 在场时间（纯函数）
## 一条台词**总共占屏**多久（淡入 + 停留 + 淡出）。
static func life_secs(line: Dictionary) -> float:
	return float(line.get("secs", 2.0)) + FADE_IN + FADE_OUT


## 当前的**不透明度**（0..1）。三段：淡入 → 满 → 淡出。
##
## ⚠️ 淡出段的长度不许超过 `life - FADE_IN`（`minf` 那一行）：
## 台词极短（`secs` 被下限托到 1.6）时，硬按 `FADE_OUT` 算会让"淡出"从第 1.44 秒
## 就开始 —— 读的人在字还没打完时就看到它开始消失。
static func alpha_of(t: float, line: Dictionary) -> float:
	var secs := float(line.get("secs", 2.0))
	var out_len := minf(FADE_OUT, maxf(secs, 0.05) * 0.5)
	if t < FADE_IN:
		return clampf(t / FADE_IN, 0.0, 1.0)
	if t < FADE_IN + secs:
		return 1.0
	var k := (t - FADE_IN - secs) / out_len
	return clampf(1.0 - k, 0.0, 1.0)


## 打字机已经打出来的字数。**取整**而不是插值 —— 字是整数个。
static func reveal_of(t: float, line: Dictionary) -> int:
	var elapsed := t - FADE_IN
	var txt := str(line.get("text", ""))
	return COMMS.reveal_count(txt, elapsed)


## 这一帧要画的文本（打字机截断后的）。
static func shown_text(t: float, line: Dictionary) -> String:
	var txt := str(line.get("text", ""))
	return txt.substr(0, reveal_of(t, line))


# ============================================================ 状态
## 待播队列（Dictionary = `COMMS.radio()` 的产物）。
var _queue: Array = []
## 正在显示的：`[{"line": Dictionary, "t": float}]`。
var _live: Array = []
## 已经播过的 id（电台一句只说一次；场景同理）。
var _seen: Dictionary = {}
## `mission_id -> {trigger_index: true}`（见头部规矩 1）。
var _fired: Dictionary = {}
## 查不到的 id（id -> 次数）。**不报错但记下来**，套件与调试面板读它。
var _missing: Dictionary = {}
## 全局时钟（HUD 的闪烁之类的相位用）。
var _clock := 0.0
## 总开关（暂停/结算时不播）。
var _enabled := true


func set_enabled(v: bool) -> void:
	_enabled = v


func is_enabled() -> bool:
	return _enabled


func clock() -> float:
	return _clock


func queued() -> int:
	return _queue.size()


func live() -> Array:
	return _live


## 某个样式正在显示的条目（HUD 逐样式取）。
func live_of(style: String) -> Array:
	var out: Array = []
	for e in _live:
		if str((e["line"] as Dictionary).get("style", "")) == style:
			out.append(e)
	return out


func seen_count() -> int:
	return _seen.size()


func has_seen(id: String) -> bool:
	return _seen.has(id)


## 查不到的 id 及其次数。**空字典 = 没出过问题**。
func missing() -> Dictionary:
	return _missing


func clear_seen() -> void:
	_seen.clear()


# ============================================================ 入队
## 推一条**电台/通讯**台词（`radio:ken_01` 或 `ken_01` 都行）。
##
## 返回"真的排上了吗"。三种返回 false 的情况**都是正常业务**，不是错误：
##   - 查不到这个 id（**已记进 `missing()`**）；
##   - 这一句已经播过（`_seen`）；
##   - 总开关关着。
func push(id: String, text_override := "") -> bool:
	if not _enabled:
		return false
	var line := COMMS.radio(id)
	if line.is_empty():
		var k := COMMS.bare_id(id)
		_missing[k] = int(_missing.get(k, 0)) + 1
		return false
	var lid := str(line["id"])
	if _seen.has(lid):
		return false
	_seen[lid] = true
	if text_override != "":
		line["text"] = text_override
		line["secs"] = COMMS.hold_secs(text_override, str(line["style"]))
	_enqueue(line)
	return true


## 直接入队一条**已经组好的**台词（场景用；不查库、不查 `_seen`）。
func enqueue_line(line: Dictionary) -> void:
	if line.is_empty():
		return
	_enqueue(line)


## 播一段场景（`COMMS.SCENES` 里的 id）。返回**排上几条**。
##
## ⚠️ 场景里某条在库里查不到时会被 `COMMS.scene()` 跳过（它就不出现在 `lines` 里），
## 于是这里数出来的条数会**少于** `SCENES[id]["ids"].size()` ——
## 套件正是用这个差值把"库里 id 对不上"抓出来的。
func play_scene(id: String) -> int:
	if not _enabled:
		return 0
	var sc := COMMS.scene(id)
	if sc.is_empty():
		_missing["scene:" + id] = int(_missing.get("scene:" + id, 0)) + 1
		return 0
	var n := 0
	for line in sc["lines"]:
		_enqueue(line)
		n += 1
	return n


func _enqueue(line: Dictionary) -> void:
	_queue.append(line)
	while _queue.size() > MAX_QUEUE:
		_queue.pop_front()


## 清空**一切**（队列 + 在场 + 去重 + 触发记录）。`Game.reset()` 时调。
##
## ⚠️ `_missing` **不清**：它是"这一局数据有没有写错"的证据，
## 跨局保留才看得见"每一局都在同一个 id 上失败"。
func clear() -> void:
	_queue.clear()
	_live.clear()
	_seen.clear()
	_fired.clear()
	_clock = 0.0


# ============================================================ 每帧
func tick(delta: float) -> void:
	_clock += delta
	# 1) 推进在场条目，过期的扔掉
	var keep: Array = []
	for e in _live:
		e["t"] = float(e["t"]) + delta
		if float(e["t"]) < life_secs(e["line"]) + GAP:
			keep.append(e)
	_live = keep
	# 2) 从队列里**按样式**补位
	#
	# ⚠️ 这里**不是**严格 FIFO：队列里第 1 条是字幕、第 2 条是电台时，
	# 若字幕的位子还占着，严格 FIFO 会让电台一直等 —— 而电台是战场态势，
	# 等一条字幕放完再报"敌机接近"是本末倒置。
	# 四种样式是四条**互不相干的视觉兰**，所以"跨样式插队"不会乱序；
	# 每种样式**内部**仍严格 FIFO。
	var rest: Array = []
	for line in _queue:
		var st := str(line.get("style", ""))
		if _slot_free(st):
			_live.append({"line": line, "t": 0.0})
		else:
			rest.append(line)
	_queue = rest


## 这个样式还有没有空位。
func _slot_free(style: String) -> bool:
	var cap := RADIO_MAX if style == COMMS.STYLE_RADIO else 1
	return live_of(style).size() < cap


# ============================================================ 触发器 · 演出侧
## 求值一关的触发器，**只吃掉 `radio:`**，其余原样交还。
##
## ## 返回值
## `[{"index": int, "kind": String, "arg": String, "id": String}, ...]`
## —— 这一帧**触发**了但本对象**没接管**的动作，交给调用方（`main`）去执行
## （`spawn_wave` / `spawn` / `objective` / `zone` / `music` / `cutscene` / `end`）。
##
## ## 为什么是"交还"而不是"全吃掉再回调"
## `main` 本来就持有刷波次 / 切目标 / 结束一局所需的全部东西
##（`_spawn_wave()` / `Game.challenge_wave` / `_finish_round()`…）。
## 让本对象去回调等于把"流程"搬进"演出"，两边都会变得说不清。
##
## ## ⚠️ `fired` 记在**这里**，不是记在 main
## 一条触发器的"已触发"只能有一个持有人（头部规矩 1）。这里的约定是：
## **本函数只要被调过，这条就算触发过了** —— 所以 main 必须**每帧调一次**，
## 并且**不许**自己再判一次 `when`。
func tick_mission(mission, state: Dictionary) -> Array:
	var out: Array = []
	if mission == null:
		return out
	var triggers = mission.triggers
	if triggers == null:
		return out
	var mid := str(mission.id)
	var done: Dictionary = _fired.get(mid, {})
	for i in triggers.size():
		if done.has(i):
			continue
		var tr = triggers[i]
		if not MS.Trigger.eval(str(tr.when), state):
			continue
		if bool(tr.once):
			done[i] = true
		var kind := MS.Trigger.action_kind(str(tr.do_what))
		var arg := MS.Trigger.action_arg(str(tr.do_what))
		if kind == "radio":
			push(arg)
		else:
			out.append({"index": i, "kind": kind, "arg": arg, "id": str(tr.id)})
	_fired[mid] = done
	return out


## 某一关已经触发过几条（调试与判据用）。
func fired_count(mission_id: String) -> int:
	var d: Dictionary = _fired.get(mission_id, {})
	return d.size()


func is_fired(mission_id: String, index: int) -> bool:
	var d: Dictionary = _fired.get(mission_id, {})
	return d.has(index)
