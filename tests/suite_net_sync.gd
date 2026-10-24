class_name SuiteNetSync
extends RefCounted
## 局域网**代理同步**（批 2）—— 用户报的「进入联机后，双方在对方视角上都是卡着不动的」。
##
## ## 这一套守的是哪件事
## 同一症状有**两条完全独立、各自都足以单独造成它**的断线，只修一条现象照旧：
##
## ① **快照根本没发出去**。`NetSession._ready()` 与 `close()` 都写死 `set_process(false)`，
##    而 `net_session.gd` 里没有第二处 `set_process(true)` ⇒ `_process()` 永不执行 ⇒ 20 Hz 快照一发不发。
## ② **代理收到了也不会动**。`NetProxyBody.apply_state()` 只写"目标值"（`_want_*`），
##    真正让它"走过去"的是 `interp()` —— 而全工程 `.interp(` 零调用方
##    （`main.gd` 只在 `_on_net_state()` 里 `apply_state`，没人每帧推它）。
##
## ## 为什么"血条会掉、但人不动"
## `apply_state()` 里血量 / 形态 / 阵亡那几行**是生效的**，只有位移这条链断着 ——
## 所以"对面能被我打掉血、但一动不动"恰好是这两条断线的指纹。
##
## ## 判据为什么能变红
## ① 走**真开一次主机**（端口 0 = 随机），断言 `Net.is_processing()` 真的是 true，
##    `close()` 后真的是 false —— 只数源码里的 `set_process` 是数不出语义倒置的；
## ② 行为断言**真的造一台 `NetProxyBody`**、喂一份远处快照、跑 30 帧，量位移比：
##    30 帧应走完差值的 99.7%（`1-exp(-12×0.5)`），1 帧应是 18.1% ——
##    后一条专门抓"改过头变成瞬移"。
##
## ⚠️ 判据 5（双开两进程的实战位移）**不在这里**：那只能在两台机器上真跑。
## 本套件覆盖的是它的**充分前置**（快照发得出去 + 代理会走）。

const MAIN_SRC := "res://scripts/main.gd"
const NET_SRC := "res://scripts/autoload/net_session.gd"


static func run(t: T, host: Node) -> void:
	t.suite("NetSync / 断线①：快照发送开关必须真的打开")
	_switch(t)
	t.suite("NetSync / 断线②：代理每帧被推向最近一份快照")
	await _interp(t, host)
	t.suite("NetSync / 回归保护：非联机模式不碰网络层")
	await _offline(t, host)
	t.suite("NetSync / 远端看得见的武器表（漏一件 = 对面看不到那一件）")
	_visible_weapons(t)


# ============================================================ ① 发送开关

static func _switch(t: T) -> void:
	var net_src := _code(NET_SRC)
	var host_body := _func_body(net_src, "func host_game(")
	var join_body := _func_body(net_src, "func join_game(")
	var close_body := _func_body(net_src, "func close(")
	t.ok(host_body.contains("set_process(true)"), "`host_game()` 打开 `_process`（曾经是永久关）")
	t.ok(join_body.contains("set_process(true)"), "`join_game()` 同样打开")
	t.ok(close_body.contains("set_process(false)"), "`close()` 关掉（开 / 关成对，不是只改一处）")
	t.gt(float(net_src.count("set_process(true)")), 1.0,
		"至少两处能打开（主机 · 加入）—— 只补一处会漏掉另一半")

	# ⚠️ "同一件事两个写法"是本工程反复点名的一类风险：
	# 曾经 `_process()` 就地 `rpc(...)`，而 `send_state()` 是个零调用方的死路。
	var proc_body := _func_body(net_src, "func _process(")
	t.ok(proc_body.contains("send_state("), "`_process()` 走 `send_state()`，不就地 `rpc`")
	t.ok(_func_body(net_src, "func send_state(").contains("rpc(\"_rpc_state\""),
		"`send_state()` 才是 `_rpc_state` 的发送点")
	t.eq(net_src.count("rpc(\"_rpc_state\""), 1, "全文件只发一处 `_rpc_state`（双写法消掉）")

	# —— 行为：真的是"在不在线"，不是"永久关" ——
	#
	# ⚠️ 这里走 `join_game()`（客户端）而不是 `host_game()`：客户端**不监听端口**
	#（只是往外连），不会触发 Windows 防火墙弹窗；两者打开开关的那一行是同一件事，
	# 而且"`host_game()` 也会打开"已经由上面的源码扫描守住了。
	var keep := Net.is_processing()
	t.eq(Net.join_game("127.0.0.1", 47655), OK, "`join_game()`（连一个没人听的端口）建得起来")
	t.ok(Net.is_processing(),
		"加入后 `Net.is_processing() == true` —— 快照才可能发得出去")
	Net.close()
	t.not_ok(Net.is_processing(), "`Net.close()` 后又变回 false")
	t.eq(Net.role, Net.Role.NONE, "`close()` 把角色复位成 NONE")
	# 不留一个开着的连接给后面的套件（本套件只该动自己的那一份状态）。
	if keep:
		Net.set_process(true)


# ============================================================ ② 每帧插值

static func _interp(t: T, host: Node) -> void:
	var main_src := _code(MAIN_SRC)
	t.ok(_func_body(main_src, "func _process(").contains("_tick_remote_proxies(delta)"),
		"`_process()` 的每帧路径上确实调了 `_tick_remote_proxies(delta)`")
	var tick_body := _func_body(main_src, "func _tick_remote_proxies(")
	t.ok(tick_body.contains(".interp("), "`_tick_remote_proxies()` 里真的调 `interp()`")
	t.ok(tick_body.contains("p.interp(delta)"), "         …对每个代理调 `p.interp(delta)`")

	Game.reset()
	var m: Node = load("res://scenes/main.tscn").instantiate()
	host.add_child(m)
	var container := Node3D.new()
	host.add_child(container)
	await host.get_tree().physics_frame
	var proxies: Array = m.get("remote_proxies")

	# ⚠️ 下面驱动的是**真调用点**（`main._tick_remote_proxies`），不是直接调 `interp()`：
	# 只验 `interp()` 自己的数学，验不出"main 到底有没有接上"—— 而那正是本项的
	# **第二条**断线。所以代理要挂进 `main.remote_proxies` 再推。
	#
	# —— 行为 A：30 帧（0.5 s）要走完差值的 99.7% ——
	var a := _new_proxy(container)
	t.ok(a != null, "造出一台代理机体")
	if a != null:
		proxies.append(a)
		a.global_position = Vector3.ZERO
		var target := Vector3(300, 50, -400)
		a.apply_state(Net.unpack_state(_packet(target, a.form_index)))
		t.not_ok(a.global_position.is_equal_approx(target),
			"收下快照**不瞬移**（只记目标值 ⇒ 必须有别的每帧调用）")
		for i in 30:
			m.call("_tick_remote_proxies", 1.0 / 60.0)
		var total := Vector3.ZERO.distance_to(target)
		var ratio := Vector3.ZERO.distance_to(a.global_position) / maxf(total, 0.001)
		t.gt(ratio, 0.997, "30 帧后走完 %.1f%%（阈值 99.7%%）" % (ratio * 100.0))
		proxies.erase(a)
		a.queue_free()
		await host.get_tree().physics_frame

	# —— 行为 B：1 帧 ≈ 18.1%（抓"改过头变瞬移"）——
	var b := _new_proxy(container)
	if b != null:
		proxies.append(b)
		b.global_position = Vector3.ZERO
		var target := Vector3(300, 0, 0)
		b.apply_state(Net.unpack_state(_packet(target, b.form_index)))
		m.call("_tick_remote_proxies", 1.0 / 60.0)
		var k := 1.0 - exp(-b.interp_rate / 60.0)
		var got := b.global_position.distance_to(Vector3.ZERO) / 300.0
		t.near(got, k, 0.01, "1 帧位移 = 差值的 %.1f%%（理论 %.1f%%）" % [got * 100.0, k * 100.0])
		t.between(got, 0.10, 0.30, "落在 10%~30% 这一档（插值率没被改飞）")
		proxies.erase(b)
		b.queue_free()
		await host.get_tree().physics_frame

	container.queue_free()
	m.queue_free()
	await host.get_tree().physics_frame


# ============================================================ ③ 非联机回归保护

static func _offline(t: T, host: Node) -> void:
	var m: Node = load("res://scenes/main.tscn").instantiate()
	host.add_child(m)
	await host.get_tree().physics_frame
	# 单机 / 训练 / 挑战一分流就不碰网络层（见 `net_session.gd` 文件头）。
	# ⚠️ 这里**不写死** `Net.is_processing() == false`：那是自动加载的开关状态，
	# 与"这一局碰不碰网络"不是一回事。真正的判据是"代理列表为空 ⇒ 每帧调用空转"。
	t.eq(m.get("remote_proxies").size(), 0, "非联机的 `remote_proxies` 是空的")
	m.call("_tick_remote_proxies", 0.016)
	t.ok(true, "空表下每帧调用只空转（不报错、不碰网络）")
	m.queue_free()
	await host.get_tree().physics_frame


# ============================================================ 小工具

## 造一台代理机体（`_ready()` 会自己补 profile / 碰撞 / 模型）。
static func _new_proxy(container: Node3D) -> NetProxyBody:
	var p := NetProxyBody.new()
	p.team = 1
	p.is_player = false
	p.profile = SuitProfile.penelope()
	p.projectile_container = container
	container.add_child(p)
	return p


## 组一份**上线报文**（`Net.unpack_state()` 的输入格式）。
##
## ⚠️ `apply_state()` 吃的是 `Net.unpack_state()` 的**产物**（键名是 `position` /
## `basis` / `velocity`…），不是这份报文（键名是 `p` / `b` / `v`…）。
## 直接喂报文会当场 KeyError，而症状是"代理一动不动" —— 与本套件要抓的真断线
## **长得一模一样**（实测踩过：18 PASS / 3 FAIL，三条全是位移 0）。
## 所以这里只造报文，调用点一律显式套一层 `Net.unpack_state()`。
##
## ⚠️ `f` 用**代理当前的形态值**：写死 0 会在形态数 ≠ 1 的机体上触发一次
## `switch_form()`（重建模型），把"插值"这条判据污染成"变身"。
static func _packet(p: Vector3, form: int) -> Dictionary:
	return {
		"p": [p.x, p.y, p.z],
		"b": [1, 0, 0, 0, 1, 0, 0, 0, 1],
		"v": [0, 0, 0],
		"hp": 100.0, "if": 0.0, "f": form, "a": true,
	}


static func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## 去掉**整行注释**与**行尾注释**之后的源码。
##
## ⚠️ 凡是「源码里有没有 X」的断言**必须**走这里 —— 实测踩过：
## 本套件的判据注释里为了解释"以前是永久关"写了 `` `set_process(true)` ``，
## 于是拆掉真实代码之后，`host_body.contains("set_process(true)")` **照样为真**，
## 判据假绿。注释里点名某个名字恰恰说明它被慎重考虑过，不该算"存在"。
##
## ★ 与 `SuiteAudio._code()` / `SuiteUiStyle._code()` **不共享实现是故意的** ——
## 套件之间不互相依赖（那边就是被并行会话改崩过一次，导致判据静默消失）。
static func _code(path: String) -> String:
	var out: Array = []
	for line in _src(path).split("\n"):
		var s := str(line)
		if s.strip_edges().begins_with("#"):
			continue
		out.append(_strip_inline(s))
	return "\n".join(out)


## 去行尾注释（`#` 落在字符串里时不算注释；靠引号计数判断）。
static func _strip_inline(line: String) -> String:
	var quotes := 0
	for i in line.length():
		var c := line[i]
		if c == "\"" or c == "'":
			quotes += 1
		elif c == "#" and quotes % 2 == 0:
			return line.substr(0, i)
	return line


## 取一个函数体的源码（从 `head` 到下一个顶层 `func` 之前）。
##
## ★ 与 `SuiteMenuFrame._func_body()` 不共享实现是**故意的** —— 套件之间不互相依赖。
static func _func_body(src: String, head: String) -> String:
	var at := src.find(head)
	if at < 0:
		return ""
	var rest := src.substr(at + head.length())
	var nxt := rest.find("\nfunc ")
	return rest.substr(0, nxt) if nxt >= 0 else rest


# ============================================================ 远端"看得见"的武器表

## 每一件**玩家会看到对面在打**的武器：函数名 → 报文里的 `kind`。
##
## ⚠️ 这张表是"对面看不到某件武器"这类 bug 的**唯一防线**：漏一件的症状是
## **单机一切正常、联机里那一件完全不存在**，而且两边都不报错。
## 用户 2026-10-11 实测报的两条：「露维杰露和 gp03 对战看不到导弹和线控炮」——
## 柯西 / 佩涅罗佩的浮游导弹走 `fire_funnel()` 早就报了（`"funnel"`），
## 而这两台 MA 的专属武器当时**一处都没报**。
##
## ⚠️ **GP03D 的抓钩（`try_gp03_grapple()`）刻意不在表里**：它是一根"缆"，
## 远端复制要连被抓的目标一起摆位，而用户没报它 —— 留着这一行是为了下次有人
## 加武器时知道"要不要进这张表"是**一个要回答的问题**，不是忘了。
const VISIBLE_WEAPONS := [
	{"fn": "func fire_beam(", "kind": "beam"},
	{"fn": "func _fire_vulcan_round(", "kind": "gun"},
	{"fn": "func fire_cannon(", "kind": "cannon"},
	{"fn": "func fire_bazooka(", "kind": "bazooka"},
	{"fn": "func fire_gp03s_bazookas(", "kind": "gp03s_bazookas"},
	{"fn": "func fire_funnel(", "kind": "funnel"},
	{"fn": "func _fire_neue_missiles(", "kind": "missile"},
	{"fn": "func _fire_gp03d_pods(", "kind": "pod"},
	{"fn": "func fire_wire_arms(", "kind": "wire"},
]


## 取一段函数体（到下一个 `func` / `static func` 为止）。
static func _body(src: String, header: String) -> String:
	var i := src.find(header)
	if i < 0:
		return ""
	var out: Array = []
	for line: String in src.substr(i).split("\n"):
		if out.size() > 0 and (line.begins_with("func ") or line.begins_with("static func ")):
			break
		out.append(line)
	return "\n".join(out)


static func _visible_weapons(t: T) -> void:
	var fb := _code("res://scripts/flight/flight_body.gd")   # 既有的 `_code(path)` 会剥整行 + 行尾注释
	var mn := _code("res://scripts/main.gd")   # 既有的 `_code(path)` 会剥整行 + 行尾注释
	var wire := _code("res://scripts/combat/neue_wire_arms.gd")   # 既有的 `_code(path)` 会剥整行 + 行尾注释

	# ---- ① 每一件都要有上报 ----
	for row: Dictionary in VISIBLE_WEAPONS:
		var fn := str(row["fn"])
		var kind := str(row["kind"])
		var body := _body(fb, fn)
		t.ok(body.length() > 0, "取到 `" + fn + "` 的体")
		t.ok(body.contains("_net_report_fire(\"%s\"" % kind),
			"%s 里有 `_net_report_fire(\"%s\")` —— 少这一句对面**什么都看不到**" % [fn, kind])

	# ---- ② 远端要有对应分支（"报了但没人接" = 一样看不见）----
	var handler := _body(mn, "func _on_net_fire(")
	t.ok(handler.length() > 0, "取到 `_on_net_fire()` 的体")
	var kinds: Array = []
	for row: Dictionary in VISIBLE_WEAPONS:
		if not kinds.has(str(row["kind"])):
			kinds.append(str(row["kind"]))
	for k: String in kinds:
		t.ok(handler.contains("\"%s\":" % k),
			"`_on_net_fire()` 有 `\"%s\"` 分支（报了没人接 = 一样看不见）" % k)

	# ---- ③ 远端复制必须是**纯视觉**（否则双倍伤害，且不报错）----
	t.ok(handler.contains("wave.damage = 0.0"),
		"集束弹仓在远端把 `damage` 归零 —— 那一仓会在本地 `take_damage`，不归零就是双倍")
	t.ok(handler.contains("arms.visual_only = true"),
		"线控炮在远端打开 `visual_only` —— 它会就地发光束结算伤害，不开就是双倍")
	t.ok(wire.contains("shot.visual_only = visual_only"),
		"远端线控炮保留可见光束，并禁止伤害和拦截")
