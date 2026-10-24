class_name SuitePause
extends RefCounted
## 暂停菜单的状态机测试。
##
## 单独一套的理由：**"暂停"这件事已经出过两次事故**。
##   1. 第一次：`pause` 与 `menu_back` 都绑在 Esc 上，结算页按 Esc 同时暂停并回菜单，
##      暂停状态一路带到下一局 → 看起来游戏卡死（见 suite_round 的说明）。
##   2. 第二次：暂停的开关是有了，但**世界根本没停** —— main 为了收输入设成
##      `PROCESS_MODE_ALWAYS`，子节点继承之后树暂停对机体无效（那条回归在 suite_round）。
##   3. 用户又提出"暂停要能返回主菜单"，于是多了一条出口、也就多了一个可能出错的状态。
##
## 这一套只钉"界面自己的状态"，不碰真输入（无头环境下按键 flush 时机不确定，
## 见 suite_round 里那段说明）；真输入路径由 suite_round 端到端跑。

static func run(t: T, host: Node) -> void:
	t.suite("Pause / 菜单项")
	_rows(t)
	t.suite("Pause / 开合状态")
	_state(t, host)


static func _rows(t: T) -> void:
	t.eq(PauseMenu.ROWS.size(), 2, "暂停菜单有两项")
	t.eq(str(PauseMenu.ROWS[0]["key"]), "resume",
		"第一项是「继续战斗」—— 默认项必须是最不破坏性的那个")
	t.eq(str(PauseMenu.ROWS[1]["key"]), "menu", "第二项是「返回主菜单」（用户要的出口）")
	for row: Dictionary in PauseMenu.ROWS:
		t.ok(str(row.get("label", "")) != "" and str(row.get("note", "")) != "",
			"菜单项 %s 标题与说明都齐" % row.get("key", "?"))


static func _state(t: T, host: Node) -> void:
	var pm := PauseMenu.new()
	host.add_child(pm)
	await host.get_tree().process_frame

	t.not_ok(pm.open, "刚建出来是收起的")
	t.not_ok(pm.visible, "刚建出来不可见")

	pm.row = 1
	pm.open_pause()
	t.ok(pm.open, "open_pause() 之后是打开状态")
	t.ok(pm.visible, "打开后可见（否则玩家什么都看不到）")
	t.eq(pm.row, 0, "每次打开都回到第一项：默认动作是「继续战斗」")
	t.ok(pm._await_release, "打开时要先等按键松开，否则按下的那一下 Esc 会立刻把它关掉")
	t.eq(pm.selected_key(), "resume", "选中项是「继续战斗」")

	# 选中项越界要夹住，不能崩（posmod 之外还可能有直接赋值）
	pm.row = 99
	t.eq(pm.selected_key(), "menu", "行号越界时夹到最后一项")
	pm.row = -5
	t.eq(pm.selected_key(), "resume", "行号越界时夹到第一项")

	# 没有按键按着时，"等松开"这道闸门应当立刻放行（否则菜单会永远不接受输入）
	t.not_ok(pm._any_accept_key_held(), "无按键按下时闸门是开的")

	pm.close_pause()
	t.not_ok(pm.open, "close_pause() 之后是收起状态")
	t.not_ok(pm.visible, "收起后不可见")
	t.not_ok(pm.active, "收起后不再处理输入")

	# 开→关→再开必须回到干净状态（多次暂停不能残留上一次的选择）
	pm.row = 1
	pm.open_pause()
	pm.close_pause()
	pm.open_pause()
	t.eq(pm.row, 0, "反复开关之后仍然默认停在「继续战斗」")
	t.ok(pm._await_release, "反复开关之后闸门重新上锁")
	pm.close_pause()

	pm.free()
	await host.get_tree().process_frame
