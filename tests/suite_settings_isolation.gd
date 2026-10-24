class_name SuiteSettingsIsolation
extends RefCounted
## ★ 轮 63-11（2026-10-04）：**套件不许读玩家的持久化状态**。
##
## ## 病（本轮实测复现，不是推演）
## `suite_rocket_launch` 里有一条对照断言：`t.ok(not Settings.first_person, …默认也是 false)`。
## 它读的是**运行时值**，而运行时值来自玩家的 `user://settings.cfg`。
## 实测：把玩家档里的 `first_person` 改成 `true`、**工程源码一行没动**
## ⇒ `--only=suite_rocket_launch` 读 `440 PASS / 1 FAIL`。
## 这类红**长得和回归一模一样**（数字在同一个量级、失败项也在套件里），
## 最贵的地方是它会让人去查代码 —— 而代码是对的。
##
## ## 药
## `Settings.begin_isolated()` / `end_isolated()`（`tests/test_runner.gd` 的 `_ready()`
## 起止各一句）：跑测试期间把 12 个持久化变量钉回**声明默认**，
## 并把读写路径重定向到临时档 ⇒ ①「断言默认值」天然成立；② 玩家的档**一个字节都不碰**
##（连「写完再还原」都不需要 —— 因为从来没写过它）。
##
## ## 本套件钉三件事
## 1. **接线**（`_wiring`）：跑测试时隔离**真的是开着的**、路径真的指到临时档，
##    而且 `test_runner.gd` 里那两句真的**在循环前后**（防「函数写好了、没人调」）；
## 2. **语义**（`_semantics`）：进入隔离 ⇒ 值 = **声明默认**、写盘只落临时档；
##    退出 ⇒ 还原进入前的值；嵌套只计数；
## 3. **闸门**（`_gate`）：`save_config()` 写出的变量集合 **逐个**都在 `PERSISTED_VARS` 里，
##    且两条路径函数都用 `_config_path` —— 否则将来加一个持久化项，隔离会**静默漏掉它**。
##
## ⚠️ 本套件**只读 `Settings` 状态 + 扫源码**，不进树、不 await、不需要 `host`
##（注册表第 3、4 列都写 `false`）。

## ⚠️ 走**路径字符串 + `load()`**，不走 `class_name`：新脚本在编辑器重新扫描之前
## 不在全局类缓存里（同 `suite_campaign` / `suite_pod_strike` 头注那条）。
const SETTINGS_SRC := "res://scripts/autoload/settings.gd"
const RUNNER_SRC := "res://tests/test_runner.gd"

## `save_config()` 里**不是变量**的实参（写成字面量的迁移标记）—— 对账时要排除。
const LITERAL_ARGS := ["true", "false"]


static func run(t: T) -> void:
	t.suite("SettingsIsolation / 接线（跑测试时隔离必须是开着的）")
	_wiring(t)

	t.suite("SettingsIsolation / 语义（默认值 · 只写临时档 · 嵌套 · 还原）")
	_semantics(t)

	t.suite("SettingsIsolation / 闸门（清单对账 · 路径同源 · 默认值不写死）")
	_gate(t)


# ============================================================ 1. 接线

static func _wiring(t: T) -> void:
	t.ok(Settings.is_isolated(),
		"★★ 跑测试时 `Settings.is_isolated()` 为真 ⇒ runner 真的调了 `begin_isolated()`")
	t.eq(Settings.config_path(), Settings.ISOLATED_PATH,
		"★★ 隔离期的读写路径 = 临时档（不是玩家的 `%s`）" % Settings.CONFIG_PATH)
	t.ok(Settings.ISOLATED_PATH != Settings.CONFIG_PATH,
		"（对照）临时档与产品真档**不是同一个路径**（同路径的话隔离等于没做）")

	var rs := FileAccess.get_file_as_string(RUNNER_SRC)
	t.ok(rs != "", "（对照）读得到 `test_runner.gd`（否则下面三条是在空串上找子串）")
	t.ok(rs.contains("Settings.begin_isolated()"),
		"★ `test_runner.gd` 里有 `Settings.begin_isolated()`")
	t.ok(rs.contains("Settings.end_isolated()"),
		"★ ……也有 `Settings.end_isolated()`（只有 begin 的话玩家的值就永远回不去）")
	var i_loop := rs.find("for row: Array in SUITES:")
	t.ok(rs.find("Settings.begin_isolated()") < i_loop,
		"★★ `begin_isolated()` 在**跑套件之前**（写在循环后面的话，第一条套件就已经读到玩家档了）")
	t.ok(rs.find("Settings.end_isolated()") > i_loop,
		"★★ `end_isolated()` 在**跑套件之后**")


# ============================================================ 2. 语义

static func _semantics(t: T) -> void:
	# ---- ① autoload 这一层：写盘只落临时档，玩家的档逐位不动 ----
	var real_before := _file_md5(Settings.CONFIG_PATH)
	Settings.save_config()          # 隔离期 ⇒ 应落到临时档
	t.eq(Settings.config_path(), Settings.ISOLATED_PATH,
		"★★ 隔离期 `save_config()` 写的是**临时档**")
	t.eq(_file_md5(Settings.CONFIG_PATH), real_before,
		"★★ 因此玩家的 `settings.cfg` **一个字节都没变**（md5 逐位相同）")
	t.ok(FileAccess.file_exists(Settings.ISOLATED_PATH),
		"★ 临时档真的被写出来了（上面那条不是因为「谁都没写」而空过）")

	# 负对照：md5 这把尺子得能看出变化，否则上面那条「md5 不变」毫无意义
	var tmp_before := _file_md5(Settings.ISOLATED_PATH)
	t.ok(tmp_before != real_before,
		"（对照）临时档与真档的 md5 **本来就不同**（两把尺子量的不是同一个文件）")
	DirAccess.remove_absolute(Settings.ISOLATED_PATH)
	t.ok(_file_md5(Settings.ISOLATED_PATH) != tmp_before,
		"（负对照）md5 这把尺子能看出临时档**变了/没了** ⇒ 尺子有牙齿")
	Settings.save_config()          # 把它恢复出来，后面的套件还要用

	# ---- ② 隔离代码本身的往返：用一个**干净副本**跑，不动 runner 那一层 ----
	#
	# ⚠️ 用副本而不是在 autoload 上退到 0 层再进：那样会让后面所有套件在一小段时间里
	# 看见玩家的真值（正是我们要消灭的东西）。副本跑的是**同一份代码**，语义等价。
	var scr: GDScript = load(SETTINGS_SRC) as GDScript
	t.ok(scr != null, "（对照）能加载 `settings.gd`（下面几条跑的就是产品里那份代码）")
	if scr == null:
		return
	var copy: Node = scr.new() as Node
	t.ok(copy != null, "（对照）能造出副本实例")
	if copy == null:
		return

	copy.set("first_person", true)                 # 假装「玩家把它开过了」
	copy.call("begin_isolated")
	t.ok(copy.call("is_isolated"),
		"★★ 副本 `begin_isolated()` ⇒ 进入隔离态")
	t.not_ok(bool(copy.get("first_person")),
		"★★ 进入隔离 ⇒ `first_person` 被置回**声明默认**（不是保留刚写进去的 true）")
	var declared: Variant = _declared_default(scr, "first_person")
	t.eq(bool(copy.get("first_person")), bool(declared),
		"★★ 而且那个值 == `settings.gd` 里 `var first_person := …` 的字面量（%s）" % str(declared))

	copy.call("end_isolated")
	t.not_ok(copy.call("is_isolated"), "★ `end_isolated()` ⇒ 退出隔离态")
	t.ok(bool(copy.get("first_person")),
		"★★ 退出隔离 ⇒ 还原成**进入前**的值（刚写进去的 true），不是停在默认上")

	# 嵌套：只计数、不重复快照（重复快照会把「外层进入前」的值弄丢）
	copy.set("first_person", false)
	copy.call("begin_isolated")
	copy.set("first_person", true)                 # 内层自己改一下
	copy.call("begin_isolated")                    # 再进一层：只 +1
	t.eq(int(copy.get("_isolate_depth")), 2, "★ 嵌套进入 ⇒ 层数 = 2")
	copy.call("end_isolated")                      # 退一层
	t.eq(int(copy.get("_isolate_depth")), 1, "★ 退一层 ⇒ 层数 = 1")
	t.ok(bool(copy.get("first_person")),
		"★★ 只退一层时**还没还原**（值仍是我在内层写进去的 true）")
	copy.call("end_isolated")                      # 退到 0
	t.ok(bool(copy.get("first_person")) == false,
		"★★ 退到 0 层 ⇒ 还原成**最外层**进入前的值（false），不是内层的 true")
	copy.free()

	# ---- ③ 副本的 end 把临时档删了 ⇒ 补回来（后续套件还要用它读存档）----
	if not FileAccess.file_exists(Settings.ISOLATED_PATH):
		Settings.save_config()
	t.ok(FileAccess.file_exists(Settings.ISOLATED_PATH),
		"收尾：临时档已恢复（后面的 `suite_settings` 还要在它上面做存档往返）")
	t.eq(_file_md5(Settings.CONFIG_PATH), real_before,
		"收尾：玩家的档**全程没被写过**（再核一次 md5）")


# ============================================================ 3. 闸门

static func _gate(t: T) -> void:
	var src := FileAccess.get_file_as_string(SETTINGS_SRC)
	t.ok(src != "", "（对照）读得到 `settings.gd`")

	# ---- ① 产品真档路径常量没被动 ----
	t.ok(src.contains('const CONFIG_PATH := "user://settings.cfg"'),
		"★ 产品真档路径常量仍是 `user://settings.cfg`（没被顺手改掉）")
	t.ok(src.contains('const ISOLATED_PATH := "user://settings.cfg.suiteiso"'),
		"★ 临时档常量存在")

	# ---- ② 两条路径函数都用 `_config_path`（隔离才生效）----
	var save_body := _func_body(src, "save_config")
	var load_body := _func_body(src, "load_config")
	t.ok(save_body != "" and load_body != "", "（对照）两个函数的正文都切出来了")
	t.ok(save_body.contains("cfg.save(_config_path)"),
		"★★ `save_config()` 写的是 `_config_path`（写死 `CONFIG_PATH` 的话隔离静默失效）")
	t.ok(load_body.contains("cfg.load(_config_path)"),
		"★★ `load_config()` 读的是 `_config_path`（否则套件里一次 `load_config()` 就把玩家值读回内存、隔离破功）")
	t.ok(not save_body.contains("cfg.save(CONFIG_PATH)"),
		"★★ 且**没有**回退成写死 `CONFIG_PATH`")

	# ---- ③ 默认值取自「新实例」而不是写死常量 ----
	var begin_body := _func_body(src, "begin_isolated")
	t.ok(begin_body.contains("new()"),
		"★★ 默认值取自**新实例**（`new()`）⇒ `settings.gd` 改默认值时隔离自动跟上，不会静默不同步")

	# ---- ④ 清单对账：`save_config()` 写出的变量 == `PERSISTED_VARS` ----
	var written := _written_vars(save_body)
	t.gt(float(written.size()), 0.0, "（对照）从 `save_config()` 里扫到了写盘项")
	var declared: Array = Settings.PERSISTED_VARS
	var missing: Array = []
	for w: String in written:
		if not declared.has(w):
			missing.append(w)
	t.eq(missing.size(), 0,
		"★★ `save_config()` 写出的每一项都在 `PERSISTED_VARS` 里（漏掉的：%s）" % str(missing))
	var stale: Array = []
	for d: String in declared:
		if not written.has(d):
			stale.append(d)
	t.eq(stale.size(), 0,
		"★★ 反向也对账：`PERSISTED_VARS` 里没有多余项（多余的：%s）" % str(stale))
	t.eq(declared.size(), 19,
		"★ 清单长度 = 19（本轮口径；加持久化项时这里会一起红 —— 那正是它存在的意义）")


# ============================================================ 工具

## 文件的 md5；文件不存在时返回一个**不可能撞上**的哨兵。
static func _file_md5(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "<absent>"
	return FileAccess.get_md5(path)


## 从源码里切出 `func <name>(` 之后、下一个顶层 `func ` 之前的正文。
static func _func_body(src: String, name: String) -> String:
	var head := src.find("func %s(" % name)
	if head < 0:
		return ""
	var nxt := src.find("\nfunc ", head + 1)
	if nxt < 0:
		return src.substr(head)
	return src.substr(head, nxt - head)


## 扫 `save_config()` 正文里 `cfg.set_value("段", "键", <实参>)` 的**实参**（= 变量名）。
## ⚠️ 写成字面量的迁移标记（`true` / `false`）不是变量，排除掉。
static func _written_vars(body: String) -> Array:
	var out: Array = []
	for line: String in body.split("\n"):
		var s := line.strip_edges()
		if not s.begins_with("cfg.set_value("):
			continue
		var parts := s.split(",")
		if parts.size() < 3:
			continue
		var tail := parts[2].strip_edges().trim_suffix(")")
		if LITERAL_ARGS.has(tail):
			continue
		if not out.has(tail):
			out.append(tail)
	return out


## `settings.gd` 里 `var <name> := <字面量>` 的字面量（= 声明侧默认值）。
static func _declared_default(scr: GDScript, name: String) -> Variant:
	var fresh: Node = scr.new() as Node
	if fresh == null:
		return null
	var v: Variant = fresh.get(name)
	fresh.free()
	return v
