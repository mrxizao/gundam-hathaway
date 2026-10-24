extends RefCounted
class_name SuiteResume

## 批 7：测试断点续跑（--resume）机制。
##
## 两类断言都**不依赖真的跑过一次完整回归**，而是直接驱动 t.gd 末尾的台账
## 机制 + run_suite 的跳过接线；并严格「备份 / 还原」真实台账，避免污染
## 后续真正的 --resume（否则本套件写进去的假记录会让下次 --resume 误跳真实套件）。

static func run(t: T, host: Node) -> void:
	t.suite("断点续跑 / 台账机制与跳过接线（隔离）")
	_isolated(t, host)

## 在隔离环境下测台账读写与跳过接线：先把真实台账备份走、删掉，从干净状态测，最后还原。
static func _isolated(t: T, host: Node) -> void:
	var lp := t.ledger_path()
	var backup := lp + ".resume_test_bak"
	# 备份真实台账（若存在），再删掉，保证本套件的测试记录不污染后续 --resume
	if FileAccess.file_exists(lp):
		DirAccess.copy_absolute(lp, backup)
		DirAccess.remove_absolute(lp)

	# —— A. 台账读写与「同名取最新一条」语义 ——
	t.write_ledger_entry("ResLedA", 0, 100)
	t.write_ledger_entry("ResLedB", 3, 50)
	var d := t.read_ledger()
	t.ok(d.has("ResLedA"), "台账记录了 ResLedA")
	t.ok(d.has("ResLedB"), "台账记录了 ResLedB")
	t.ok(t.ledger_clean("ResLedA"), "ResLedA 是绿的（fail==0）→ ledger_clean 真")
	t.ok(not t.ledger_clean("ResLedB"), "ResLedB 有失败 → ledger_clean 假")
	t.write_ledger_entry("ResLedA", 2, 120)   # 同名再写一条，应取最新
	var d2 := t.read_ledger()
	t.ok(not t.ledger_clean("ResLedA"), "ResLedA 最新一条 fail=2 → 不再是绿的")

	# —— B. --resume 跳过接线 ——
	t.write_ledger_entry("ResumeSkipProbe", 0, 10)   # 一条已绿的探针记录
	t.resume = true
	var p0 := t.passed
	var f0 := t.failed
	# 不存在的路径 + 已绿记录：应命中跳过分支（不 load、不跑、断言计数不动）
	t.run_suite("res://tests/_never_exists_for_resume.gd", "ResumeSkipProbe", host, false, false)
	t.ok(t.passed == p0 and t.failed == f0, "已绿的探针套件被跳过（断言计数未动）")
	t.ok(t._skipped.has("ResumeSkipProbe"), "跳过名单里记录了该套件")
	# ⚠️ 这条探针是**本套件自己造出来的**（台账里那条记录也是 `write_ledger_entry`
	# 现写的），而 `t.report()` 会照着 `_skipped` 打印「本次**不是**完整回归」。
	# 不清掉的话，**每一次**完整回归的结尾都会挂一条假警报 ——
	# 实测：轮 22 的全量回归报了「跳过了 1 个」，而 316 节一个没少。
	# 那正好破坏本工程反复强调的「记录的条件必须等于实际发生的条件」。
	# 断言在上面已经取过值，清掉不影响它；真实 --resume 的跳过项不受影响
	#（那些是 `run_suite` 在**本套件之外**追加的）。
	t._skipped.clear()
	t.resume = false   # 复位，绝不影响后续（Keybind 等）套件的正常执行

	# —— 还原真实台账 ——
	if FileAccess.file_exists(backup):
		DirAccess.copy_absolute(backup, lp)
		DirAccess.remove_absolute(backup)
	else:
		# 原本就没有台账：把隔离期间写进去的测试记录清掉，避免污染
		DirAccess.remove_absolute(lp)
