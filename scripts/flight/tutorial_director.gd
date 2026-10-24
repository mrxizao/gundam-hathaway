class_name TutorialDirector
extends RefCounted
## **新手教学导演**（1.2 第二十六轮）。
##
## 用户原话：「新手教程关要有按键引导教学，玩家按下按键触发对应之后，
## 才提示下一步。通过新手教程让玩家知道这个游戏的按键有什么功能。
## 同时新手教程的靶机都是无限血量的。」
##
## ## 它替掉了什么
##
## 旧教学是 `SuitProfile.tutorial_steps()` 的一张**静态清单**，十几条一次性
## 全糊在屏幕上 —— 新手读不完，也不知道"现在该按哪个"。
## 本类把同一套内容改成**一关一关的引导**：
##   - 屏幕上只出现**当前这一步**（外加最近几步的 ✓ 存根）；
##   - 每步要么盯着一个**输入动作**（`Input.is_action_just_pressed`），
##     要么盯一个**游戏状态**（锁定过 / 命中过 / 切到军刀 / 燃料槽开始掉）；
##   - 完成当前步 ⇒ 才推进到下一步；全部完成 ⇒ `done`，HUD 画完成态。
##
## ## 数据驱动（与 `tutorial_steps()` 同一纪律）
##
## 步骤按 `SuitProfile` 的字段裁剪：没有导弹的机体不出现导弹步骤、
## ACE 机没有燃料槽 / 踏板步骤 —— **绝不能教玩家按一个它按不出的功能**。
##
## ⚠️ 步骤里的动作名都是 InputMap 的真动作（`input_setup.BINDINGS`），
## `suite_tutorial` 会逐个 `InputMap.has_action()` 钉死 —— 动作名手滑写错的
## 症状是"按了没反应、教学卡死"，那种故障新手自己绝对绕不出来。

## 教学步骤。元素：`{ "text": String, "actions": Array[String] }`（按键步）
## 或 `{ "text": String, "check": String }`（状态步；
## check ∈ lock / hit / saber / jet / assist / translate_move / qb_dash /
## super_boost / never）。
var steps: Array[Dictionary] = []
## 当前步下标。done 之后停在最后一步（"自由练习"）。
var idx := 0
## 全部完成（进入"自由练习"）。
var done := false

## 基线：start() 那一刻的本局统计。check 步只认**增量** ——
## 否则"进教学之前锁过定 / 打中过"的存量会把教学直接跳穿。
var _base_locks := 0
var _base_dealt := 0.0
## "jet" 步：按住 boost 的连续秒数（松手清零 —— 要的是"一直按到槽开始掉"）。
var _boost_held := 0.0

## **输入探针（测试注入点）**：默认 `Callable()` = 走真实 Input。
##
## 为什么要有这条缝：无头回归里 `Input.action_press` 的 just_pressed 帧戳
## **实测不可靠**（连续注入 40 次一次都不触发，症状随引擎版本/上下文漂移）。
## 与其在测试里赌引擎时序，不如把"动作名是不是真键位"交给
## `InputMap.has_action` 断言 + 源码扫描守卫（见 suite_tutorial），
## 推进逻辑用探针桩做**确定性**验证。生产代码永远走默认分支。
var input_probe: Callable = Callable()


func _just_pressed(a: String) -> bool:
	if input_probe.is_valid():
		return bool(input_probe.call(a))
	return Input.is_action_just_pressed(a)


func _boost_pressed() -> bool:
	if input_probe.is_valid():
		return bool(input_probe.call("boost"))
	return Input.is_action_pressed("boost")


## 按机体字段裁剪出教学步骤。顺序仍是"先会飞、再会打、最后保命"。
static func build_steps(profile: SuitProfile) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# ---- ① 会飞 ----
	out.append({
		"text": "起飞与转向：W / S 俯仰、A / D 横滚 —— 让机体动起来",
		"actions": ["pitch_nose_down", "pitch_nose_up", "roll_left", "roll_right"],
	})
	out.append({
		"text": "加速与减速：按住 Shift（手柄 X）加速，松开回到巡航",
		"actions": ["boost"],
	})
	# ---- ①' 辅助驾驶（批 27，2026-09-22 用户要求并入教学）----
	# 所有机体都能开辅助（长按 flight_assist 0.45 s 翻转 `assist_on`）；
	# 开启后的操作**按形态分岔**（`PlayerController.assist_uses_translation`，
	# 与实机同一条判据）：
	#   · 常规形态 → **平移模式**：WASD/QE 平移 + Shift 点按闪避冲刺；
	#   · 阿利宙斯巡航形态 → 老辅助（自动飞行 + 常驻加力），Shift = 超级加速。
	# ⚠️ 判定全部盯**真实状态**（assist_on / translate_dir / translate_dash /
	# super_boost），不盯按键 —— "长按才开"的节奏交给实机，教学只认结果。
	out.append({
		"text": "辅助驾驶：长按 G（手柄长按 A）开启 —— 机体自动加速飞行",
		"check": "assist",
	})
	if PlayerController.assist_uses_translation(profile):
		out.append({
			"text": "辅助驾驶中：WASD 前后左右、QE 升降 —— 推一下就平移修正位置",
			"check": "translate_move",
		})
		out.append({
			"text": "闪避冲刺：辅助驾驶中点按 Shift（手柄 X）—— 朝输入方向短距爆冲",
			"check": "qb_dash",
		})
	else:
		out.append({
			"text": "超级加速：辅助驾驶中按住 Shift —— 巡航形态的极速冲刺",
			"check": "super_boost",
		})
	# ---- ② 会打 ----
	out.append({
		"text": "锁定：把准星罩到靶机身上，等锁定框咬住它",
		"check": "lock",
	})
	out.append({
		"text": "开火：锁定后按住 鼠标左键（手柄 R2）开火",
		"actions": ["fire_primary"],
	})
	out.append({
		"text": "提前量：对着横向移动的靶机打提前量 —— 命中一次即过",
		"check": "hit",
	})
	if profile.has_missiles:
		out.append({
			"text": "浮游导弹：按 F（手柄 L2）全弹发射 —— 弹夹 150 发，打空自动换弹",
			"actions": ["fire_missile"],
		})
	out.append({
		"text": "火神炮：按住 空格（手柄 R1）连发 —— 无限弹，留意过热条",
		"actions": ["fire_gun"],
	})
	if profile.has_saber:
		out.append({
			"text": "军刀：按 切换武器键 把武器换到光束军刀（切过去即过）",
			"check": "saber",
		})
	# ---- ③ 机体特色 / 保命 ----
	if profile.has_jet_gauge:
		out.append({
			"text": "燃料槽：按死 Shift 直到槽开始掉 —— 它只够 %.0f 秒" % profile.jet_seconds,
			"check": "jet",
		})
	if profile.can_ride_pedal():
		out.append({
			"text": "飞行踏板：按 N 呼叫踏板，它会从天而降飞到你身边",
			"actions": ["ride_pedal"],
		})
	if profile.cruise_morph:
		out.append({
			"text": "变形：按 Z 变形 —— 巡航形态更快更钝，再按一次变回来",
			"actions": ["transform"],
		})
	out.append({
		"text": "举盾：按住 T（手柄对应键）举盾减伤 —— I 立场碎了之后的保命手段",
		"actions": ["shield"],
	})
	# ---- ④ 收尾（最后一步：进入它即视为教学完成）----
	out.append({
		"text": "自由练习：全部学会！靶机是无限血的，随便打",
		"check": "never",
	})
	return out


## 开教：裁剪步骤 + 记统计基线。每局 HUD 重建时会重新调一次。
func start(profile: SuitProfile) -> void:
	steps = build_steps(profile)
	idx = 0
	done = false
	_base_locks = Game.locks_acquired
	_base_dealt = Game.damage_dealt + Game.ifield_dealt
	_boost_held = 0.0


## 当前步骤的文案（done 之后是"自由练习"那条）。
func current_text() -> String:
	if steps.is_empty() or idx >= steps.size():
		return ""
	return str(steps[idx]["text"])


## 每帧喂一次。返回 true 表示**这一帧推进了一步**（调用方可以拿它刷提示）。
## `player` 允许为 null（单元测试用）—— 但军刀步因此推不动，属预期防跳穿。
func poll(player: PlayerController, delta: float) -> bool:
	if done or idx >= steps.size():
		return false
	var step := steps[idx]
	# 按键步：任一动作"刚按下"即完成（新手按一下就算会了，不要求连招）。
	if step.has("actions"):
		for a: String in step["actions"]:
			if InputMap.has_action(a) and _just_pressed(a):
				_advance()
				return true
		return false
	# 状态步：盯真实游戏状态，不是盯按键。
	match str(step.get("check", "")):
		"lock":
			if Game.locks_acquired > _base_locks:
				_advance()
				return true
		"hit":
			if Game.damage_dealt + Game.ifield_dealt > _base_dealt + 0.5:
				_advance()
				return true
		"saber":
			if player != null and player.current_slot() == "saber":
				_advance()
				return true
		"jet":
			if _boost_pressed():
				_boost_held += delta
				if _boost_held >= 2.0:
					_advance()
					return true
			else:
				_boost_held = 0.0
		# ---- 辅助驾驶三连（批 27）—— 全部盯真实状态，player 为 null 一律推不动
		#（防教学跳穿；真局里这些状态由玩家真实操作写出来）。
		"assist":
			if player != null and player.assist_on:
				_advance()
				return true
		"translate_move":
			# 平移输入在动（WASD/QE）就过；`fm.boosting` 兜底是给
			# 阿利宙斯巡航形态的老辅助（它替玩家常驻压着加速）留的口子。
			if player != null and player.assist_on \
					and (player.translate_dir.length_squared() > 0.001
						or player.fm.boosting):
				_advance()
				return true
		"qb_dash":
			# 闪避冲刺窗口进行中（FlightBody 在 QB 爆冲期间自动置真）。
			if player != null and player.translate_dash:
				_advance()
				return true
		"super_boost":
			# 阿利宙斯巡航形态：Shift = 超级加速（fm.super_boost 由实机置真）。
			if player != null and player.fm.super_boost and player.fm.boosting:
				_advance()
				return true
		"never":
			pass  # 最后一步不是任务，是收尾文案；进到它时 _advance 已置 done
	return false


## 推进一步。进入**最后一步**（自由练习）即视为教学完成：
## 最后一步不再是要完成的任务，done 之后 poll 短路、HUD 画完成态。
func _advance() -> void:
	idx += 1
	_boost_held = 0.0
	if idx >= steps.size() - 1:
		idx = steps.size() - 1
		done = true
