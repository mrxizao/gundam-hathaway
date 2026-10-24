extends Node
## **降级入口**（并行落地时用）：按 `test_runner.gd` 的同一顺序跑大部分套件，
## 只跳过明确坏掉的那一个。
##
## 它是什么时候需要：`test_runner.gd` 会调用全部 21 个套件，而**并行的另一个会话**
## 常常把某一个 suite 改到一半（第十七轮那次是 `suite_round17.gd:459` 的
## `var rel := wing.global_position - …` 推不出类型 → Parse Error）。那时全量入口
## 连「我这一轮到底绿不绿」都问不出来。
##
## ⚠️ 第十八·二十一轮起 `test_runner.gd` 已经**不会**被单个坏套件拖垮了
## （`T.run_suite()` 会把它记成一条 FAIL 并点名，其余照跑）—— 所以这个入口现在主要是
## **把"别人的套件"隔离掉**用：数字可以直接和全绿基线对照，只差被跳过的那几个。
##
## 跑法：
##   godot --headless --path <工程> res://tests/_probe15.tscn
##
## 跳过的：Round17（第十五轮当时的坏文件；现在它已经修好，但保留跳过不影响别的）
## 单实例闸门与全量入口一致（见 `tests/t.gd`）。

const SKIP := ["res://tests/suite_round17.gd"]

## 每行 = `[路径, 显示名, 是否 async, 是否传 host]`（后两项见 `test_runner.gd` 的说明：
## `Flight/Ballistics/Rig` 只收 `t`，其余收 `t, host`）
const SUITES := [
	["res://tests/suite_flight.gd", "Flight", false, false],
	["res://tests/suite_ballistics.gd", "Ballistics", false, false],
	["res://tests/suite_rig.gd", "Rig", false, false],
	["res://tests/suite_layout.gd", "Layout", false, true],
	["res://tests/suite_damage.gd", "Damage", true, true],
	["res://tests/suite_abilities.gd", "Abilities", true, true],
	["res://tests/suite_combat.gd", "Combat", true, true],
	["res://tests/suite_audio.gd", "Audio", true, true],
	["res://tests/suite_settings.gd", "Settings", true, true],
	["res://tests/suite_gamepad.gd", "Gamepad", false, true],
	["res://tests/suite_pause.gd", "Pause", true, true],
	["res://tests/suite_input.gd", "Input", true, true],
	["res://tests/suite_round.gd", "Round", true, true],
	["res://tests/suite_round14.gd", "Round14", true, true],
	["res://tests/suite_round15.gd", "Round15", true, true],
	["res://tests/suite_round16.gd", "Round16", true, true],
	["res://tests/suite_round17.gd", "Round17", true, true],
	["res://tests/suite_round18.gd", "Round18", true, true],
	["res://tests/suite_round19.gd", "Round19", true, true],
	["res://tests/suite_round20.gd", "Round20", true, true],
	["res://tests/suite_round21.gd", "Round21", true, true],
]


func _ready() -> void:
	await get_tree().process_frame
	var t := T.new()
	if t.guard_single_instance():
		get_tree().quit(3)
		return
	print("")
	print("================ GUNDAM 无头测试（降级入口 · 跳过 %s） ================" % str(SKIP))
	for row: Array in SUITES:
		if SKIP.has(str(row[0])):
			print("（按要求跳过 %s）" % str(row[1]))
			continue
		await t.run_suite(str(row[0]), str(row[1]), self, bool(row[2]), bool(row[3]))
	print("================================================")
	t.report()
	get_tree().quit(1 if t.failed > 0 else 0)
