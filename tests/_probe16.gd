extends Node
## **临时入口**（第十六轮自检用，跑完即删）。
##
## 为什么需要它：`tests/test_runner.gd` 会调用 `SuiteRound14`，而那个文件此刻正被
## **并行的第十四轮会话**改到一半（`--check-only` 报 `suite_round14.gd:533` 括号未闭合），
## 于是一整个工程都解析不了 —— 连"第十六轮到底绿不绿"都问不出来。
## 这里按 `test_runner.gd` 的**同一顺序**跑除 Round14 之外的全部套件，
## 把两个会话的落地解耦开（数字可以直接和全绿时的基线对照，只差 Round14 那一套）。

func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("================ GUNDAM 无头测试（第十六轮自检，只跳过 Round14） ================")
	var t := T.new()
	SuiteFlight.run(t)
	SuiteBallistics.run(t)
	SuiteRig.run(t)
	SuiteLayout.run(t, self)
	await SuiteDamage.run(t, self)
	await SuiteAbilities.run(t, self)
	await SuiteCombat.run(t, self)
	await SuiteAudio.run(t, self)
	await SuiteSettings.run(t, self)
	SuiteGamepad.run(t, self)
	await SuitePause.run(t, self)
	await SuiteInput.run(t, self)
	await SuiteRound.run(t, self)
	await SuiteRound16.run(t, self)
	print("================================================")
	t.report()
	get_tree().quit(1 if t.failed > 0 else 0)
