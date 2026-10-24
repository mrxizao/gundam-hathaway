class_name HoldAction
extends RefCounted
## 长按识别（1.2）：**点按 / 长按**两义一键，带进度。
##
## # 为什么需要一个专门的类
##
## 工程里原来只有 `is_action_just_pressed`（点按）与 `is_action_pressed`（按住状态），
## 没有"按住够久才算数"这种东西。而这一轮要加的几个动作**必须**是长按：
##
##   - **丢弃光束步枪**（柯西）：不可逆的资源损失。长按 `R` 换弹的人按久了会误丢枪，
##     所以既要"按住 0.6 s 才触发"，也要把进度画在 HUD 上（`progress()` 就是给它用的）——
##     没有那个提示，这个改键一定会被骂。
##   - **飞行辅助开关 / 选威胁**（下一轮）：都是"按住才进"的动作，不能一碰就翻。
##
## # 用法
##
## ```gdscript
## var hold := HoldAction.new()
## hold.configure(0.6)
## # 每帧（不管按没按都要 tick，松手的那一帧才是 SHORT 事件）：
## match hold.tick(delta, Input.is_action_pressed("reload")):
##     HoldAction.Result.LONG:  _discard_rifle()
##     HoldAction.Result.SHORT: _reload()
## ```
##
## ⚠️ 一条容易写错的语义：**长按触发过之后，松手不再补一次 SHORT**。
## 否则"按住 R 丢枪"会在松手时又换一次弹 —— 那是两个动作都执行了。

enum Result { NONE, SHORT, LONG }

## 触发长按需要的按住时长（秒）。
var threshold := 0.45

var _held := 0.0
var _long_fired := false


func configure(seconds: float) -> void:
	threshold = seconds


## 每帧调用。`pressed` = 这个动作此刻是否被按住。
func tick(delta: float, pressed: bool) -> int:
	if pressed:
		_held += delta
		if not _long_fired and _held >= threshold:
			_long_fired = true
			return Result.LONG
		return Result.NONE
	var was := _held
	_held = 0.0
	if _long_fired:
		# 长按已经响应过 → 松手不再报 SHORT（见文件头那条警告）
		_long_fired = false
		return Result.NONE
	if was > 0.0 and was < threshold:
		return Result.SHORT
	return Result.NONE


## 当前已按住多久。
func held() -> float:
	return _held


## 长按进度 0..1（HUD 画环/条用）。
func progress() -> float:
	return clampf(_held / maxf(threshold, 0.001), 0.0, 1.0)


## 是否正在按住（还没到阈值也算）。
func holding() -> bool:
	return _held > 0.0


## 复位（换局 / 菜单打开时清掉半按状态，否则回来会瞬间触发）。
func reset() -> void:
	_held = 0.0
	_long_fired = false
