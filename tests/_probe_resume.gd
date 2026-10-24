extends Node
## 批 7 窄入口：只跑少量套件，快速验证 台账机制 + 跳过接线 + 不破坏正常跑。
## 复用 test_runner 的 run_suite 通路（而非直接调 suite.run），这样每个套件都会
## 走 patch C 的台账写入，Resume 套件也会走 patch B 的跳过分支单测。

const SUITES := [
	["res://tests/suite_flight.gd", "Flight", false, false],
	["res://tests/suite_layout.gd", "Layout", false, true],
	# ---- 批 7 · 测试断点续跑（--resume 跳过上一轮已绿的套件）----
	["res://tests/suite_resume.gd", "Resume", false, true],
	# 必须排最后（会真的改 InputMap 与 user://keybinds.cfg）
	["res://tests/suite_keybind.gd", "Keybind", false, true],
]

func _ready() -> void:
	await get_tree().process_frame
	var t := T.new()
	if t.guard_single_instance():
		get_tree().quit(3)
		return
	t.resume = _want_resume()
	if t.resume:
		print("⚠️ --resume：上一轮已绿的套件将被跳过（本次非完整回归）")
		t.write_ledger_run_start()
	print("")
	print("================ GUNDAM 窄入口（批7验证） ================")
	for row: Array in SUITES:
		await t.run_suite(str(row[0]), str(row[1]), self, bool(row[2]), bool(row[3]))
	print("================================================")
	t.report()
	get_tree().quit(1 if t.failed > 0 else 0)

func _want_resume() -> bool:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if str(a) == "--resume":
			return true
	return false
