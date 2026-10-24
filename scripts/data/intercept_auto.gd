class_name InterceptAuto
extends RefCounted
## 手柄 L1 的双模状态机：**点按 = 拦一发；按住 = 自动拦截（与浮游飞弹同间隔 0.42 s）**。
##
## # 为什么不能用 `HoldAction`
##
## `HoldAction` 的语义是"**松手**才判定点按 / 长按"（见它自己的文件头），
## 而 L1 的第一发必须**按下即发** —— 拦截是抢时间的动作，等到松手就晚了。
## 所以这是一个"按下沿立刻出手 + 持续按住转循环"的状态机，与 `HoldAction`
## 各管一摊、互不影响（那边三个使用者：丢枪 ×2 / 辅助飞行，一行都不用动）。
##
## # 语义（老板 2026-09-19 定稿）
##
## | 操作 | 出手 |
## |---|---|
## | 按下 L1 | **立刻 1 发**（打"当前选中"；没有选中则由调用方取最危险的一枚） |
## | 按住 ≥ `HOLD_ENTER` | 进入**自动模式**，之后**每 `SHOT_INTERVAL` 秒一发**，目标由调用方挑 |
## | 松手 | 立即退出自动模式（计时全部归零） |
##
## 时间轴（按住不放）：`t=0` 1 发 → `0.45`（进自动）1 发 → `0.87` → `1.29` → …
## 进入自动模式之后**与浮游飞弹同间隔**（0.42 s 一发，批 26 用户指定；
## 历史：老板 2026-09-20 曾把射速提到 5 枚/秒，批 26 因"一秒射很多"撤回）。
##
## # 冷却（批 26 更新：拦截弹间隔与浮游飞弹对齐）
##
## 批 21 曾把玩家拦截弹 CD 改 0，结果键鼠长按 F 每帧过闸、一秒泼出一堆飞弹。
## 批 26 定稿：
##   · **非自动路径**（点按 F / 右键 / 长按 F）→ 走通用发射器冷却 0.42 s（与浮游飞弹同闸）；
##   · **自动拦截路径** → 发射传 0，节奏由 `SHOT_INTERVAL`（0.42 s）等价表达。
## 连续发不出去仍会放弃（`GIVE_UP_SHOTS`）—— 剩下的闸只有换弹 / 变形 / 眩晕。
## AI 仍走自己的 `ai_cd`，不受影响。
##
## # 返回值 = 本帧要打几发
##
## 0 或 1。**调用方每发都要走一次完整的"写 `_intercept_pending` → 发扳机 → 武装"**
## （见 `PlayerController._read_weapon_input`），中间不能跨帧，
## 否则会武装到上一次打出的那一发。
##
## # 发不出去时（冷却中 / 打空 / 未锁定敌机）
##
## 本帧不发，但**不静默**：连续 `GIVE_UP_SHOTS` 次都发不出去 → `exhausted` 置真、
## 自动模式退出。调用方读到 `exhausted` 必须给一句 notice 并调 `clear_exhausted()`。
## —— 手柄上"按着没反应"是最难自己发现的一类失败，工程里已经栽过好几次。

## 按住多久进自动模式（秒）。和工程里另外三个长按动作同一个量级（0.45）。
const HOLD_ENTER := 0.45
## 自动模式每发间隔（秒）。批 26（2026-09-22 用户指定）：**与浮游飞弹的发射间隔
## （`profile.funnel_interval` = 0.42）对齐** ——「拦截飞弹开枪间隔和浮游飞弹一样」。
## （历史：老板 2026-09-20 曾提过 5 枚/秒（0.2 s），批 21 又把 CD 改 0 让它跑满；
##  实机观感"一秒射很多"被撤回，本值回到与通用冷却同一条线。）
## ⚠️ 自动路径的发射因此**传 0**（CD 不设防）：扳机整拍落在 0.42 上，
## 若走通用冷却就是浮点赛跑，输两次自动模式直接放弃 —— 见 PlayerController 的 salvo。
const SHOT_INTERVAL := 0.42
## 连续几发发不出去就放弃（0.42 s 间隔下 ≈ 0.84 秒）。
const GIVE_UP_SHOTS := 2

## 是否处于自动模式（HUD 靠它画"自动拦截 ON"）。
var active := false
## 是否因为"发不出去"而放弃。调用方读完请调 `clear_exhausted()`。
var exhausted := false

var _held := 0.0
var _next_shot := 0.0
var _blocked := 0
var _was_pressed := false
## 这一次按住**已经放弃过**了：松手之前不再试。
##
## 没有它的话，`reset()` 会把计时归零 —— 于是"按住不放"会每 1.4 秒重新进一次自动模式、
## 再放弃一次，**提示会反复弹**（`exhausted` 被反复置真），玩家以为游戏坏了。
var _gave_up := false


## 自动模式的射速（发/秒）。HUD 与测试用它，而不是各写一遍 `1.0 / 0.5`。
static func shots_per_second() -> float:
	return 1.0 / SHOT_INTERVAL


## 每帧调用，不管按没按都要调（松手的那一帧要靠它归零）。
##
## `pressed`  = L1 此刻是否被按住
## `can_fire` = **此刻**发得出去吗（冷却已好 ∧ 还有弹 ∧ 已锁定敌机 ∧ 场上有目标）
##
## 返回本帧要打几发（0 / 1）。
func update(delta: float, pressed: bool, can_fire: bool) -> int:
	if not pressed:
		_was_pressed = false
		_gave_up = false
		reset()
		return 0
	if _gave_up:
		# 这一次按住已经放弃过了 —— 松手之前不再试（否则提示会反复弹，见 `_gave_up`）
		return 0
	if not _was_pressed:
		# ---- 按下沿：立刻出手一发 ----
		# ⚠️ 这里**不看** `active`：点按与长按共用这一发，长按的第一发就是它。
		_was_pressed = true
		_held = delta
		_next_shot = SHOT_INTERVAL
		return 1 if can_fire else 0

	_held += delta
	if not active:
		if _held < HOLD_ENTER:
			return 0
		active = true
	if _held + 0.000001 < _next_shot:
		return 0
	# 从 `_next_shot` 起按 `SHOT_INTERVAL` 整拍推进；
	# 进自动模式那一刻 `_held`（≥0.45）已经超过 `_next_shot`（0.2），所以**当帧就出第一发**，
	# 不会白等一个间隔。
	_next_shot = _held + SHOT_INTERVAL
	if can_fire:
		_blocked = 0
		return 1
	_blocked += 1
	if _blocked >= GIVE_UP_SHOTS:
		exhausted = true
		_gave_up = true
		reset()
	return 0


## 归零（松手 / 换局 / 暂停菜单打开时都要调）。
## ⚠️ **不清 `exhausted`** —— 那是留给调用方读的状态，读走再 `clear_exhausted()`，
## 否则"连发两次都打不出去"这条告警会被下一次 `reset()` 顺手抹掉。
func reset() -> void:
	active = false
	_held = 0.0
	_next_shot = 0.0
	_blocked = 0


func clear_exhausted() -> void:
	exhausted = false


## 当前按住已多久（HUD 画进度条用）。
func held() -> float:
	return _held


## 进自动模式的进度 0..1。
func progress() -> float:
	return clampf(_held / HOLD_ENTER, 0.0, 1.0)
