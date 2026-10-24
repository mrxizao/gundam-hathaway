class_name T

extends RefCounted

## 极简断言器。故意不用任何测试框架 —— 本工程的规矩是

## `godot --headless --path . res://tests/test_runner.tscn` 一条命令跑完，

## 判据只看自己打印的汇总行，不看退出码（退出码在各项目里写法从来不统一）。

var passed := 0

var failed := 0

var failures: Array[String] = []

var _suite := ""

## 每个套件跑了多少条断言。

##

## 为什么要记：**断言总数会变**（有的套件在 `while` 帧循环里断言、有的按集合大小展开），

## 所以"上轮多少条"本身不是一个稳定的量 —— 少了 100 条有可能是某个套件提前退出了，

## 而不是"测试变少了"。没有这张表就只能盯着总数猜（第十四轮真的为这个卡过一次）。

var _suite_counts: Dictionary = {}

var _suite_start := 0

## 断点续跑：是否处 --resume 模式（见脚本末尾「测试断点续跑」一节）。

var resume := false

## --resume 模式下被跳过的套件（报告里单列）。

var _skipped: Array[String] = []

func suite(name: String) -> void:

	_close_suite()

	_suite = name

	_suite_start = passed + failed

	print("--- %s ---" % name)

func _close_suite() -> void:

	if _suite != "":

		_suite_counts[_suite] = _suite_counts.get(_suite, 0) + (passed + failed - _suite_start)

func ok(cond: bool, label: String) -> void:

	if cond:

		passed += 1

	else:

		failed += 1

		failures.append("%s / %s" % [_suite, label])

		print("  FAIL  %s" % label)

func not_ok(cond: bool, label: String) -> void:

	ok(not cond, label)

func near(actual: float, expected: float, tol: float, label: String) -> void:

	var good := absf(actual - expected) <= tol

	if not good:

		failed += 1

		failures.append("%s / %s (got %.4f want %.4f ±%.4f)" % [_suite, label, actual, expected, tol])

		print("  FAIL  %s  got=%.4f want=%.4f ±%.4f" % [label, actual, expected, tol])

	else:

		passed += 1

func eq(actual: Variant, expected: Variant, label: String) -> void:

	if actual == expected:

		passed += 1

	else:

		failed += 1

		failures.append("%s / %s" % [_suite, label])

		print("  FAIL  %s  got=%s want=%s" % [label, str(actual), str(expected)])

func lt(actual: float, bound: float, label: String) -> void:

	ok(actual < bound, "%s (%.4f < %.4f)" % [label, actual, bound])

func gt(actual: float, bound: float, label: String) -> void:

	ok(actual > bound, "%s (%.4f > %.4f)" % [label, actual, bound])

func between(actual: float, lo: float, hi: float, label: String) -> void:

	ok(actual >= lo and actual <= hi, "%s (%.4f in [%.4f, %.4f])" % [label, actual, lo, hi])

func report() -> void:

	_close_suite()

	print("")

	print("按套件统计（断言条数）：")

	var total := 0

	for k: String in _suite_counts:

		total += int(_suite_counts[k])

		print("  %-42s %4d" % [k, int(_suite_counts[k])])

	print("  %-42s %4d" % ["合计", total])

	if not missing_suites.is_empty():

		print("")

		print("⚠️ 未能执行的套件（这些**没有**被验证）：")

		for m in missing_suites:

			print("  - " + m)

	print("")

	if not _skipped.is_empty():
		print("")
		print("⚠️ RESUME 模式：跳过了 %d 个上一轮已绿的套件（本次**不是**完整回归）：" % _skipped.size())
		for s in _skipped:
			print("  - " + s)
		print("  要权威结果，请不带 --resume 再跑一次。")

	print("%d PASS / %d FAIL" % [passed, failed])

	if failed > 0:

		print("失败清单：")

		for f: String in failures:

			print("  - " + f)

# ============================================================ 测试入口的守卫与韧性

#

# 这一节是第十八·二十一轮加的，起因是 2026-09-20 那天「Godot 特别容易崩」：

#

#   ① 编辑器与无头测试**同时**跑同一个工程 —— 双方都在写 `.godot/`

#      （`global_script_class_cache.cfg` / `uid_cache.bin` / `imported/`），

#      于是 autoload 与 class_name 解析不到，满屏 `Identifier not found: Game`，

#      进程看起来就是「崩了」（崩的其实是脚本编译，不是引擎）。

#   ② `test_runner.gd` 当时**无条件顺序调用 21 个套件**：其中任何一个编译不过，

#      `SuiteXxx.run` 就成了「GDScript 上不存在的函数」→ **整轮当场中断**，

#      连「哪些是绿的」都问不出来。

#

# 所以这里立两条规矩：`guard_single_instance()` 与 `run_suite()`。

## `tasklist` 的落盘位置（见 `_godot_processes()`：不用管道，改成写文件再读）。

const TASKLIST_OUT := "user://dsh_tasklist.txt"

## 未能执行的套件（报告里单独列一段）。

var missing_suites: Array[String] = []

## 同一时刻只允许一个 Godot 碰这个工程。返回 true = **必须中止**（原因已经打印）。

##

## 判据是**数进程**（`tasklist`，一次拿全）：

##   - 有 **GUI 版**（`Godot_*win64.exe`，不带 `_console`）= 编辑器或跑起来的游戏在跑 → 拒绝；

##   - **console 版**（带 `_console`）≥ 2 个 = 另一个**测试**在跑（`1` 就是我们自己）→ 拒绝。

## 探针失败一律**放行**（fail-open）：宁可偶尔打架，也不要因为探针失效让测试根本跑不起来。

##

## ⚠️ 早先这里用的是"租约文件 + 15 分钟过期"，**已废弃**：

## 进程被强杀（超时/任务管理器）时租约留在磁盘上没人清 → 之后 15 分钟的测试全被自己挡住。

## 数进程没有这个失效模式：进程没了，"锁"自动就没了。

##

## `--allow-concurrent` 可以强行跳过（验证改动、或明知在用工程副本时用）。

func guard_single_instance() -> bool:

	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():

		if str(a) == "--allow-concurrent":

			print("⚠️ --allow-concurrent：跳过单实例检查 —— 别在编辑器开着时这么跑")

			return false

	var info := _godot_processes()

	if not bool(info.get("ok", false)):

		print("⚠️ 进程探针不可用 —— 跳过单实例检查（请自己确认没有别的 Godot 在跑）")

		return false

	if int(info.get("gui", 0)) > 0:

		_halt_notice("检测到 **GUI 版 Godot** 正在跑（编辑器 / 游戏）",

			"两个实例同时写 .godot 缓存 → autoload 与 class_name 解析不到，\n"

			+ "表现就是满屏 Identifier not found 与「进程崩了」")

		return true

	if int(info.get("console", 0)) > 1:

		_halt_notice("另一个**测试进程**正在用这个工程",

			"同时跑两轮测试同样会抢 .godot 缓存（console 版进程数 = %d）" % int(info["console"]))

		return true

	return false

func _halt_notice(why: String, detail: String) -> void:

	print("")

	print("================================================")

	print("测试**没有运行**：%s" % why)

	for line in detail.split("\n"):

		print("  " + line)

	print("  请先关掉它；确要并行请用**工程副本**。")

	print("================================================")

## 数一下本机有多少 Godot 在跑：`{ok, gui, console}`。

##

## ⚠️ **绝不要用带 `output` 数组的 `OS.execute`**：在受限环境里通过**管道**收子进程输出

## 会被挡，表现是整轮测试**卡死到超时**（本机实测踩到过 —— 比它要解决的问题更糟）。

## 所以让 `tasklist` **重定向写进一个临时文件**，再读文件：完全绕开管道。

func _godot_processes() -> Dictionary:

	var zero := {"ok": false, "gui": 0, "console": 0}

	var abs := ProjectSettings.globalize_path(TASKLIST_OUT)

	OS.execute("cmd", ["/c", "tasklist /NH > \"%s\"" % abs])

	var f := FileAccess.open(TASKLIST_OUT, FileAccess.READ)

	if f == null:

		return zero

	var text := f.get_as_text()

	f = null

	DirAccess.remove_absolute(abs)

	if text.strip_edges() == "":

		return zero

	var info := {"ok": true, "gui": 0, "console": 0}

	for line in text.split("\n"):

		var l := line.strip_edges()

		if not l.begins_with("Godot"):

			continue

		if l.contains("_console"):

			info["console"] = int(info["console"]) + 1     # 我们自己也是其中之一

		elif l.contains("win64.exe"):

			info["gui"] = int(info["gui"]) + 1

	return info

## 跑一个套件。**坏掉的套件只丢它自己**，而且大声报出来（记一条 FAIL）。

##

## 判据用**断言计数有没有动**，不用反射：编译失败的脚本在 Godot 里仍然是一个

## 「能加载但没有方法」的 GDScript 对象，调它的 `run` 只会打印一行引擎错误然后返回 null

## —— 拿计数判断最可靠，而且不依赖任何易变的反射 API。

##

## ⚠️ 判据是**调用前探测方法是否存在**（`_has_method`），不是"事后数断言"。

##

## 为什么不能用"事后数断言"（我第一版就是这么写的，自检当场抓出来）：

## `load()` 对解析失败的脚本**不返回 null，而是一个桩**（引擎打印

## "Failed to load script … Parse error"，但返回值非空），而**调用一个不存在的方法

## 会把当前函数直接中止** —— 于是"事后那段检查"根本执行不到，坏套件被静默吞掉。

##

## 实测（`_probe_guard` 自检）：好脚本的 `get_script_method_list()` 里有 `run`

## （静态函数也在列表里，`suite_flight.gd` 的实测结果含 `run` 与 9 个别的方法），

## 坏脚本返回的是**空数组**。用它当闸门，一次实测就够定案。

func run_suite(path: String, label: String, host: Node, async_call := true, with_host := true) -> void:

	if resume and ledger_clean(label):

		print("（跳过 %s：上一轮已绿，--resume）" % label)

		_skipped.append(label)

		return

	var before := passed + failed

	var f_before := failed

	var scr: Variant = load(path)

	if scr != null and _has_method(scr, "run"):

		if async_call:

			if with_host:

				await scr.call("run", self, host)

			else:

				await scr.call("run", self)

		else:

			if with_host:

				scr.call("run", self, host)

			else:

				scr.call("run", self)

	if passed + failed <= before:

		missing_suites.append(label)

		suite("测试入口 / 套件未能执行")

		ok(false, "[套件缺失] %s（%s）**一条断言都没跑** —— 大概率是编译不过；本轮**没有**验证它"

			% [label, path])

	var f_delta := failed - f_before
	var tot_delta := (passed + failed) - before
	write_ledger_entry(label, f_delta, tot_delta)

## 这个脚本里有没有定义某个方法（静态函数也算）。

## 见 `run_suite()` 的注释：这是"坏套件"唯一可靠的判据。

func _has_method(scr: Variant, want: String) -> bool:

	var ml: Variant = scr.call("get_script_method_list")

	if not (ml is Array):

		return false

	for m: Variant in ml:

		if m is Dictionary and str(m.get("name", "")) == want:

			return true

	return false

# ============================================================ 测试断点续跑（--resume）
#
# 机制：平时（不带 --resume）每跑完一个套件就往 user://regression_ledger.txt
# 追加一行 "<label>\t<fail>\t<total>\t<ts>"；带 --resume 时，凡是"上一轮
# 最后一条记录 fail==0"的套件直接跳过（不 load、不跑），报告末尾单列跳过名单。
#
# 设计原则：**fail-open、非侵入**。不带旗标时行为完全不变（只是多写一行台账）；
# 带旗标时也只跳过"已知全绿"的套件，任何解析失败都按"没跳过"处理，绝不丢套件。

const LEDGER_PATH := "user://regression_ledger.txt"

func ledger_path() -> String:
	return ProjectSettings.globalize_path(LEDGER_PATH)

## 解析台账：返回 { label: {fail, total, ts} }，同名取最新一条，跳过 "===" 分隔行。
func read_ledger() -> Dictionary:
	var out: Dictionary = {}
	var f := FileAccess.open(LEDGER_PATH, FileAccess.READ)
	if f == null:
		return out
	var text := f.get_as_text()
	f = null
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("==="):
			continue
		var cols := line.split("\t")
		if cols.size() < 3:
			continue
		var label := cols[0]
		var fail := int(cols[1])
		var total := int(cols[2])
		out[label] = {"fail": fail, "total": total, "ts": cols[3] if cols.size() > 3 else ""}
	return out

## 该套件上一轮最后一条记录是否全绿（fail==0）。解析失败一律返回 false（不跳过）。
func ledger_clean(label: String) -> bool:
	var d := read_ledger()
	if not d.has(label):
		return false
	return int(d[label].get("fail", 1)) == 0

func _ledger_open_append() -> FileAccess:
	var f: FileAccess
	if FileAccess.file_exists(LEDGER_PATH):
		f = FileAccess.open(LEDGER_PATH, FileAccess.READ_WRITE)
	else:
		f = FileAccess.open(LEDGER_PATH, FileAccess.WRITE)
	return f

## 追加一行台账。READ_WRITE + seek_end 实现追加（FileAccess 没有独立 APPEND 模式）。
func write_ledger_entry(label: String, fails: int, total: int) -> void:
	var f := _ledger_open_append()
	if f == null:
		return
	f.seek_end(0)
	var ts := Time.get_datetime_string_from_system()
	f.store_line("%s\t%d\t%d\t%s" % [label, fails, total, ts])
	f = null

## 一次 --resume 运行的开始标记（便于人工区分台账里的多次运行）。
func write_ledger_run_start() -> void:
	var f := _ledger_open_append()
	if f == null:
		return
	f.seek_end(0)
	f.store_line("=== run %s ===" % Time.get_datetime_string_from_system())
	f = null
