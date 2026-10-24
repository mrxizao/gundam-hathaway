extends Node
## **临时窄入口**（批 4 施工自检用）。**不是判据** —— 判据永远是
## `tests/test_runner.tscn` 的 `PASS / FAIL` 汇总行。
##
## 跑法：`godot --headless --path <工程> res://tests/_probe_b4.tscn`
##
## 选这几套的理由（每一条都对着一处改动）：
##   - `Input`     —— ensure_all / _prune_action 改读权威表的第一现场；
##                     残留检查也改成了 bound_*()（§4.8.10）
##   - `Gamepad`   —— 帮助面板消费方（it[2] 手柄列不受影响的那半）
##   - `Round15`   —— 说明书按第一列文本查行（改走 help_text()）
##   - `Round16`   —— 同上（begins_with("G") 那一行）
##   - `UiStyle`   —— main_menu 加了整页新绘制代码，源码扫描（对齐线 /
##                     线宽 / 字重）必须仍然绿
##   - `Keybind`   —— 本批新套件。**放最后**：它会改 InputMap 与 keybinds.cfg
##
## ⚠️ 这一轮动了输入地基：先跑 --import 刷 class 缓存，再跑本入口。

func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("========= GUNDAM 无头测试（批 4 窄入口，**不是判据**）=========")
	var t := T.new()
	await SuiteInput.run(t, self)
	SuiteGamepad.run(t, self)
	await SuiteRound15.run(t, self)
	await SuiteRound16.run(t, self)
	SuiteUiStyle.run(t, self)
	SuiteKeybind.run(t, self)
	print("============================================================")
	t.report()
	get_tree().quit(1 if t.failed > 0 else 0)
