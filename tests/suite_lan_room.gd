class_name SuiteLanRoom
extends RefCounted
## 局域网**房间 + 密码**（轮 63-6 批 4 §六）——用户报的"联机要手输 IP 与端口，太麻烦"。
##
## ## 这一套守的是哪几件事
## 1. **房间号 ⇒ 端口**是**一处**映射（两台机器对同一个房间号必须算出同一个端口，
##    否则"连不上"而两边都不报错）；
## 2. **密码是一道门，不是装饰**：主机侧判定不通过就必须**主机主动踢人** ——
##    "客户端自己退出"等于没有密码（改客户端就绕过了）；
## 3. **握手只发一个包**：老结构一次发 3 个 rpc，任何一条落到兜底值，
##    两台机器就会各算出一局不同的对局（`net_session.gd` 头部那段注释点名过的事故）；
## 4. **行下标只有一处真源**：历史上地址 / 端口的下标 2 / 3 在两个函数里各写了一遍，
##    "改漏一处"的症状是**某一栏收不到键盘**（页面上完全看不出来）；
## 5. **广播发现真的懒开 socket**：480 多个套件都跑在同一个进程里，
##    一个 autoload 在 `_ready()` 就绑端口是在给所有场景收税。
##
## ## 判据为什么能变红
## 纯函数那一半直接喂数（`port_of_room` / `accepts` / `parse_beacon`）；
## 接线那一半扫**代码正文**（去掉注释行），因为"两个写法都在、但只有一处被调用"
## 正是本工程反复吃亏的那类 bug。
##
## ⚠️ **判据 7（双开两进程实测建房 / 输错密码被拒）不在这里**：那只能在两台机器上真跑。
## 本套件覆盖的是它的**充分前置**（端口映射唯一 + 验密门存在且会踢人 + 报文能往返）。

const LanRoom := preload("res://scripts/data/lan_room.gd")
const MENU_SRC := "res://scripts/ui/main_menu.gd"
const NET_SRC := "res://scripts/autoload/net_session.gd"
const BROWSER_SRC := "res://scripts/autoload/lan_browser.gd"
const PROJ_SRC := "res://project.godot"


static func run(t: T, host: Node) -> void:
	t.suite("房间号 ⇒ 端口（纯函数）")
	_room(t)
	t.suite("密码与验密（纯函数）")
	_pass(t)
	t.suite("广播报文（往返 + 拒收）")
	_beacon(t)
	t.suite("握手合成一个包 + 主机验密门")
	_handshake(t)
	t.suite("行下标只有一处真源")
	_rows(t)
	t.suite("每一行都有绘制消费者")
	_consumers(t)
	t.suite("发现广播是懒开 socket 的")
	_browse(t)
	t.suite("等待态有出口（返回 / 超时）")
	_wait_exit(t)


# ============================================================ ① 房间号 ⇒ 端口

static func _room(t: T) -> void:
	# 洗输入：只留数字、截到 6 位。
	t.eq(LanRoom.sanitize_code("12a3b4"), "1234", "洗输入只留数字")
	t.eq(LanRoom.sanitize_code("1234567890"), "123456", "截到 6 位")
	t.eq(LanRoom.sanitize_code("abc"), "", "一个数字都没有 ⇒ 空")

	# 合法性：**恰好 6 位**。
	t.ok(LanRoom.code_ok("000000"), "000000 合法（前导零也是 6 位）")
	t.ok(LanRoom.code_ok("999999"), "999999 合法")
	t.ok(not LanRoom.code_ok("12345"), "5 位不合法")
	t.ok(not LanRoom.code_ok(""), "空不合法")
	t.ok(LanRoom.code_ok("1234567"), "超长会被洗成 6 位 ⇒ 仍然合法（洗输入在判定之前）")

	# 值域：100 个槽位，全部落在 [27015, 27114]。
	var lo := 1 << 30
	var hi := -1
	for i in 100:
		var p := LanRoom.port_of_room("%06d" % i)
		lo = mini(lo, p)
		hi = maxi(hi, p)
	t.eq(lo, LanRoom.PORT_BASE, "最小端口 == 端口基数 27015")
	t.eq(hi, LanRoom.PORT_BASE + LanRoom.PORT_SPAN - 1, "最大端口 == 27114")
	t.eq(LanRoom.port_of_room(""), LanRoom.PORT_BASE,
		"空房间号退回端口基数（菜单在玩家没输满时也要有个确定读数）")

	# **低两位决定端口**：100 个不同低两位 ⇒ 100 个互不相同的端口。
	var seen: Dictionary = {}
	var dup := 0
	for i in 100:
		var p2 := LanRoom.port_of_room("%06d" % i)
		if seen.has(p2):
			dup += 1
		seen[p2] = true
	t.eq(dup, 0, "低两位互不相同的房间号不撞端口（100 个全跑）")
	t.eq(seen.size(), LanRoom.PORT_SPAN, "⇒ 值域正好 100 个端口")

	# ⚠️ 反过来：高四位不同、低两位相同的房间号**必然**同端口。
	# 这是设计（同机最多 100 个房间），不是 bug —— 但必须写成断言，
	# 否则下一个人会以为"房间号唯一 ⇒ 端口唯一"，从而删掉广播里那个**真实端口**。
	t.eq(LanRoom.port_of_room("123456"), LanRoom.port_of_room("223456"),
		"高四位不同、低两位相同 ⇒ 同一个端口（设计如此，故广播必须带真实端口）")

	# 生成：固定种子也要保证合法（判据要可复现）。
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261003
	var bad := 0
	for i in 200:
		if not LanRoom.code_ok(LanRoom.new_code(rng)):
			bad += 1
	t.eq(bad, 0, "生成 200 次全都是合法的 6 位")


# ============================================================ ② 密码与验密

static func _pass(t: T) -> void:
	t.ok(LanRoom.pass_ok(""), "空密码合法（= 公开房）")
	t.ok(not LanRoom.pass_ok("1"), "1 位不合法")
	t.ok(not LanRoom.pass_ok("123"), "3 位不合法（宁可在门口拦住）")
	t.ok(LanRoom.pass_ok("1234"), "4 位合法（下限）")
	t.ok(LanRoom.pass_ok("12345678"), "8 位合法（上限）")
	t.eq(LanRoom.sanitize_pass("123456789"), "12345678", "洗输入截到 8 位")
	t.eq(LanRoom.sanitize_pass("12a34"), "1234", "只留数字")

	# 哈希是确定性纯函数。
	t.eq(LanRoom.auth_hash("1234"), LanRoom.auth_hash("1234"), "同一个密码 ⇒ 同一个哈希")
	t.ok(LanRoom.auth_hash("1234") != LanRoom.auth_hash("12345"), "不同密码 ⇒ 不同哈希")
	t.eq(LanRoom.auth_hash(""), LanRoom.PUBLIC_AUTH,
		"⚠️ 空密码的哈希 == 公开房常数（这两个必须钉在一起，否则公开房判不出来）")
	t.eq(LanRoom.auth_hash("12a34"), LanRoom.auth_hash("1234"), "哈希也先洗输入（与判定同源）")

	# 验密的三条路。
	t.ok(LanRoom.accepts(LanRoom.PUBLIC_AUTH, LanRoom.auth_hash("")),
		"公开房 + 客户端没输密码 ⇒ 放行")
	t.ok(LanRoom.accepts(LanRoom.PUBLIC_AUTH, LanRoom.auth_hash("9999")),
		"⚠️ 公开房 + 客户端手滑输了密码 ⇒ 照样放行（公开房的语义是谁都能进）")
	t.ok(LanRoom.accepts(LanRoom.auth_hash("1234"), LanRoom.auth_hash("1234")),
		"要密码 + 密码正确 ⇒ 放行")
	t.ok(not LanRoom.accepts(LanRoom.auth_hash("1234"), LanRoom.auth_hash("5678")),
		"要密码 + 密码不对 ⇒ 拒绝")
	t.ok(not LanRoom.accepts(LanRoom.auth_hash("1234"), LanRoom.PUBLIC_AUTH),
		"要密码 + 客户端没输 ⇒ 拒绝（不是「没输就默认放行」）")

	# ⚠️ 判据 2 的后半句：**被拒的那一方也要知道自己被拒了**。
	# 主机 `_kick()` 把 peer 踹掉 ⇒ 客户端那条连接以 `server_disconnected`
	#（或 `connection_failed`）结束 —— 两者都**必须**走 `close()`，而
	# `close()` 里 `role = Role.NONE`。少了这一环，加入方会**停在 CLIENT 角色上、
	# 一直显示「已连接」**，主机那边却已经在等下一个对手 —— 页面上完全看不出错。
	# 这条链是**本轮才被走到的**（批 2 之前没有「主机踢人」这个动作），必须钉住。
	var net := _code_only(NET_SRC)
	t.ok(_func_body(net, "func _on_server_disconnected(").contains("close()"),
		"被主机踢掉 ⇒ 加入方 `_on_server_disconnected()` 走 `close()`（角色回到 NONE）")
	t.ok(_func_body(net, "func _on_connection_failed(").contains("close()"),
		"连不上 ⇒ `_on_connection_failed()` 走 `close()`")
	t.ok(_func_body(net, "func close(").contains("role = Role.NONE"),
		"`close()` 把角色复位成 NONE（这是「被拒」能被看见的唯一落点）")


# ============================================================ ③ 广播报文

static func _beacon(t: T) -> void:
	var b := LanRoom.beacon("123456", 27071, 1, 1, true)
	t.eq(String(b.get("m", "")), LanRoom.BEACON_MAGIC, "报文带魔数")
	t.ok(not b.has("pass"), "⚠️ 报文里没有密码字段")
	t.ok(not b.has("auth"), "⚠️ 也没有密码哈希（局域网录下来能离线爆破 4 位数字）")
	t.ok(bool(b.get("locked", false)), "只回答「要不要密码」")

	var back := LanRoom.parse_beacon(b)
	t.ok(not back.is_empty(), "自己发的包自己认得")
	t.eq(String(back.get("code", "")), "123456", "房间号往返一致")
	t.eq(int(back.get("port", 0)), 27071, "端口往返一致")
	t.eq(int(back.get("form", 0)), 1, "形式往返一致")
	t.eq(int(back.get("players", 0)), 1, "人数往返一致")
	t.ok(bool(back.get("locked", false)), "要不要密码往返一致")

	# 拒收：局域网里别人发的垃圾。
	t.ok(LanRoom.parse_beacon({}).is_empty(), "空字典 ⇒ 认不出")
	t.ok(LanRoom.parse_beacon({"m": "别的程序"}).is_empty(), "魔数不符 ⇒ 认不出")
	var bad_code := b.duplicate()
	bad_code["code"] = "12"
	t.ok(LanRoom.parse_beacon(bad_code).is_empty(), "房间号不是 6 位 ⇒ 认不出")
	var bad_port := b.duplicate()
	bad_port["port"] = 65535
	t.ok(LanRoom.parse_beacon(bad_port).is_empty(), "端口越界 ⇒ 认不出（防幽灵房）")
	var bad_port2 := b.duplicate()
	bad_port2["port"] = 0
	t.ok(LanRoom.parse_beacon(bad_port2).is_empty(), "端口 0 ⇒ 认不出")

	# 列表一行的文本。
	var line := LanRoom.room_line("123456", 1, 2, false)
	t.ok(line.contains("123456") and line.contains("王牌战") and line.contains("公开"),
		"列表行含房间号 / 形式 / 是否加密：" + line)


# ============================================================ ④ 握手合包 + 验密门

static func _handshake(t: T) -> void:
	var src := _code_only(NET_SRC)
	var body := _func_body(src, "func _send_hello(")
	t.ok(body != "", "找得到 `_send_hello()`（找不到说明它被改名/删了）")

	# 判据 3：**只发一个包**。
	t.eq(body.count("_rpc_hello4"), 2,
		"`_send_hello()` 里 `_rpc_hello4` 恰好两次（定点一次、广播一次）")
	t.eq(body.count("\"_rpc_hello\""), 0, "不再发旧三条之一：`_rpc_hello`")
	t.eq(body.count("\"_rpc_hello_side\""), 0, "不再发旧三条之一：`_rpc_hello_side`")
	t.eq(body.count("\"_rpc_hello_form\""), 0, "不再发旧三条之一：`_rpc_hello_form`")
	t.eq(body.count("rpc_id("), 1, "定点发送只有一句")
	t.eq(body.count("rpc_id(") + body.count("\t\trpc(\""), 2,
		"全函数只有两条发送语句（定点 / 广播各一）")

	# 判据 3b：四字段齐全。
	t.ok(src.contains("func _rpc_hello4(suit_id: int, side: int, form: int, auth: int) -> void:"),
		"`_rpc_hello4` 四个字段齐全（机体 / 阵营 / 形式 / 密码哈希）")

	# 主机侧验密 —— 门的**本体**。
	var h4 := _func_body(src, "func _rpc_hello4(")
	t.ok(h4.contains("LanRoom.accepts(_expected_auth, auth)"),
		"主机拿 `LanRoom.accepts()` 比密码（规则不在这里重写）")
	t.ok(h4.contains("_kick(from)"), "密码不对 ⇒ 主机主动踢人")
	t.ok(not h4.contains("close()"),
		"⚠️ 被拒时不是把整条连接关掉（那会把主机自己也断了）")
	t.ok(h4.contains("Game.lan_status"), "被拒的原因写进 `Game.lan_status`（菜单上看得见）")

	# 闸门：三条老握手 RPC 都要验过密码才作数。
	for fn in ["func _rpc_hello(", "func _rpc_hello_side(", "func _rpc_hello_form("]:
		t.ok(_func_body(src, fn).contains("if role == Role.HOST and not _admitted:"),
			fn + " 有验密闸门（否则跳过 hello4 直接发老包就能绕过密码）")

	# 房间号进屋：端口只由 LanRoom 导出。
	t.ok(src.contains("func host_room("), "有 `host_room()`（房间号 ⇒ 端口，菜单不自己算）")
	t.ok(src.contains("func join_room("), "有 `join_room()`")
	t.eq(src.count("LanRoom.port_of_room("), 2,
		"端口映射恰好两处调用（开主机 / 加入），没有第三份实现")
	t.eq(src.count("% 100"), 0, "⚠️ 代码里没有第二处 `% 100`（映射不许抄第二遍）")
	t.ok(src.contains("_admitted = false"), "`close()` 会把门重新关上（换对手就重新验）")


# ============================================================ ⑤ 行下标只有一处真源

static func _rows(t: T) -> void:
	var menu := _code_only(MENU_SRC)

	for name in ["LAN_ROW_CREATE", "LAN_ROW_JOIN", "LAN_ROW_CODE", "LAN_ROW_PASS",
			"LAN_ROW_SEARCH", "LAN_ROW_ADV", "LAN_ADV_ADDR",
			"LAN_ADV_PORT", "LAN_FIELD_NONE", "LAN_FIELD_ADDR", "LAN_FIELD_PORT",
			"LAN_FIELD_CODE", "LAN_FIELD_PASS"]:
		t.ok(menu.contains("const " + name + " :="), "有常量 " + name)

	# `_input()`（原始字符输入）不再自己看下标。
	var inp := _func_body(menu, "func _input(")
	t.ok(inp.contains("_lan_backspace()"), "`_input()` 的退格走 `_lan_backspace()`")
	t.ok(inp.contains("_lan_type("), "`_input()` 的字符输入走 `_lan_type()`")
	t.ok(not inp.contains("lan_row == 2"), "⚠️ `_input()` 里没有字面量 `lan_row == 2`")
	t.ok(not inp.contains("lan_row == 3"), "⚠️ `_input()` 里没有字面量 `lan_row == 3`")
	t.ok(not inp.contains("lan_adv_row == 0"), "⚠️ 也没有字面量 `lan_adv_row == 0`")

	# 字段判定只有一份。
	var fld := _func_body(menu, "func _lan_field(")
	t.eq(fld.count("LAN_FIELD_ADDR"), 1, "`_lan_field()` 只有一处 ADDR 判定")
	t.eq(fld.count("LAN_FIELD_PORT"), 1, "`_lan_field()` 只有一处 PORT 判定")
	t.ok(fld.contains("lan_adv_row == LAN_ADV_ADDR"), "高级子页用命名常量判地址行")

	# 主列表那七行的读数都走命名常量。
	var val := _func_body(menu, "func lan_row_value(")
	for name in ["LAN_ROW_CREATE", "LAN_ROW_JOIN", "LAN_ROW_CODE", "LAN_ROW_PASS",
			"LAN_ROW_SEARCH", "LAN_ROW_ADV"]:
		t.ok(val.contains(name), "`lan_row_value()` 覆盖 " + name)


# ============================================================ ⑥ 每一行都有绘制消费者

static func _consumers(t: T) -> void:
	t.eq(MainMenu.LAN_ROWS.size(), 6,
		"联机页 6 行（建房 / 加入 / 房间号 / 密码 / 搜索 / 高级）")
	t.eq(MainMenu.LAN_ADV_ROWS.size(), 2, "高级子页 2 行（地址 / 端口）")
	# ⚠️ 2026-10-11：形式那一行**已搬进房间界面**（见 `LOBBY_ROWS`）。
	# 这一条防的是"把行加回来"——加回来就说明有人把流程改回"建房前先选形式"了。
	t.not_ok(str(MainMenu.LAN_ROWS).contains("对战形式"),
		"联机页没有「对战形式」行（它搬进房间了）")
	t.eq(MainMenu.LAN_ROW_CODE, 2, "房间号是下标 2")
	t.eq(MainMenu.LAN_ROW_PASS, 3, "密码是下标 3")

	# ⚠️ 这一条防的是"加了行但没画"：每一行都得**算得出读数**。
	var m := MainMenu.new()
	for i in MainMenu.LAN_ROWS.size():
		var v: String = m.lan_row_value(i)
		t.ok(v != "", "主列表第 " + str(i) + " 行「"
			+ String(MainMenu.LAN_ROWS[i]) + "」有读数：" + v)
	for i in MainMenu.LAN_ADV_ROWS.size():
		t.ok(m.lan_adv_value(i) != "", "高级第 " + str(i) + " 行有读数")
	m.free()

	# 三条子屏都不新增 `Stage` 枚举值（加一个要同步改四处消费面）。
	var menu := _code_only(MENU_SRC)
	t.ok(menu.contains("var lan_sub := LAN_SUB_MAIN"), "子屏是 `Stage.LAN` 内部的 `lan_sub`")
	t.ok(menu.contains("const LAN_SUB_ADV := 1"), "高级子屏")
	t.ok(menu.contains("const LAN_SUB_ROOMS := 2"), "房间列表子屏")

	# 状态行把 `Game.lan_status` 印出来 —— 这是「密码不正确」能被玩家看见的**唯一**落点。
	# ⚠️ 只断言"写进了 Game.lan_status"是不够的：还得有人**画**它。
	#（本工程反复吃过「数据留了、绘制撤了」和反过来的亏。）
	t.ok(_func_body(menu, "func _draw_lan_footer(").contains("Game.lan_status"),
		"状态行真的画 `Game.lan_status`（否则拒绝原因永远上不了屏）")


# ============================================================ ⑦ 发现广播

static func _browse(t: T) -> void:
	var src := _code_only(BROWSER_SRC)
	var ready_body := _func_body(src, "func _ready(")
	t.ok(ready_body.contains("set_process(false)"),
		"⚠️ `_ready()` 不干活（480 多个套件共用一个进程，绑端口是收税）")
	t.ok(not ready_body.contains("bind("), "⚠️ `_ready()` 里不绑 socket")
	t.ok(src.contains("func start_browse("), "有 `start_browse()`")
	t.ok(_func_body(src, "func start_browse(").contains("bind("), "`start_browse()` 才绑端口")
	t.ok(src.contains("func stop() -> void:"), "有 `stop()`（离开这一页要收摊）")

	# autoload 真的注册了（否则菜单里 `LanBrowser` 是未定义标识符 ⇒ 整块 Parse Error）。
	t.ok(_code_only(PROJ_SRC).contains("LanBrowser=\"*res://scripts/autoload/lan_browser.gd\""),
		"`project.godot` 里注册了 LanBrowser autoload")

	# 行为：默认不活跃，开了才活跃，关了回到不活跃。
	t.ok(not LanBrowser.is_active(), "一开始不活跃")
	var bind_ok: bool = LanBrowser.start_browse()
	t.ok(bind_ok, "`start_browse()` 能绑上监听端口 " + str(LanRoom.DISCOVERY_PORT))
	t.ok(LanBrowser.is_browsing(), "开起来之后处于「在搜索」状态")
	LanBrowser.stop()
	t.ok(not LanBrowser.is_active(), "`stop()` 之后回到不活跃")


# ============================================================ ⑧ 等待态有出口

## 用户报的「联机对战如果对方没有进房间就会一直卡住，没有退出的办法」。
##
## ## 根因不是"少写了一个判断"，是**次序**：等待态曾经无条件 `return`，
## 把同函数下方唯一的返回出口变成死代码 ⇒ `_lan_wait` 置真之后，除了"对面到齐"
## 与"连接失败"两条回调，**没有任何函数能把它置回假**。
##
## ## 为什么判据钉在纯函数上
## 现场那一段读的是 `Input.is_action_just_pressed`，而**注入按键在无头下不可靠**
##（`tutorial_director.gd:48` 实测：连注 40 次一次不触发）。工程里三处先例
##（`nav_delta_y()` / `submit_password()` / `launch_ready()`）都是同一个取舍：
## **次序钉在纯函数上，输入那一层只钉接线**。
##
## ⚠️ 只断「CANCEL 这一支存在」是**不够**的 —— 把它挪到函数末尾照样存在。
##    所以下面每一条都在断**相对次序**。
static func _wait_exit(t: T) -> void:
	var HOST: int = Net.Role.HOST
	var NONE: int = Net.Role.NONE
	var CANCEL: int = Net.WaitExit.CANCEL
	var LAUNCH: int = Net.WaitExit.LAUNCH
	var LINK_LOST: int = Net.WaitExit.LINK_LOST
	var TIMEOUT: int = Net.WaitExit.TIMEOUT
	var STAY: int = Net.WaitExit.STAY

	# ---- (a) 超时规则本身 ----
	t.ok(Net.lan_wait_timed_out(25.0, 20.0), "等 25 s > 20 s ⇒ 超时")
	t.not_ok(Net.lan_wait_timed_out(10.0, 20.0), "等 10 s ⇒ 不超时")
	t.ok(Net.lan_wait_timed_out(20.0, 20.0),
		"正好 20 s ⇒ 算超时（`>=` 而不是 `>`：到点就走，不留一帧）")
	# ⚠️ “已经断开”**不**在上面那个纯函数里判（它只比时间）——
	#   那条规则只在下面 (b) 段用 `wait_exit()` 断；两处都判就会变成不可证伪。

	# ---- (b) 次序（本节的重点）----
	t.eq(Net.wait_exit(true, false, HOST, 0.0), CANCEL,
		"★ 等待态里按返回 ⇒ CANCEL（这条在本 bug 修掉之前必然红过）")
	t.eq(Net.wait_exit(true, true, HOST, 0.0), CANCEL,
		"⚠️ 取消**优先于**「刚好到齐」—— 排在后面的话这一帧就出击了，那下 Esc 会被吃掉")
	t.eq(Net.wait_exit(false, true, HOST, 0.0), LAUNCH, "双方选择到齐 ⇒ 出击（正常出口没被改坏）")
	t.eq(Net.wait_exit(false, false, NONE, 0.0), LINK_LOST, "连接没了 ⇒ 回可操作态")
	# ⚠️ 这条断的是**位置**：把 `wait_exit()` 的 ③④ 对调 ⇒ 本条必须红。
	#   （它之前只能靠 `lan_wait_timed_out()` 里那道 NONE 门代替，而那样就不可证伪了）
	t.eq(Net.wait_exit(false, false, NONE, 25.0), LINK_LOST,
		"★ 断开**优先于**超时（超满也不报「超时」）")
	t.eq(Net.wait_exit(false, false, HOST, 25.0), TIMEOUT,
		"★ 没人来 + 等过头 ⇒ 超时（**只有主机那侧走得到**：加入方断开时 role 已回 NONE）")
	t.eq(Net.wait_exit(false, false, HOST, 5.0), STAY, "没人来 + 还没到点 ⇒ 继续等")
	t.eq(Net.wait_exit(false, false, HOST, 0.0, 0.0), TIMEOUT,
		"时限是**参数**（默认值取 `LAN_WAIT_TIMEOUT`）：喂 0 就立刻到点 ⇒ 判据可复算")

	# Room input keeps cancel before the host's start commit.
	var menu := _code_only(MENU_SRC)
	var lan_body := _func_body(menu, "func _read_lan_room_input(")
	t.ok(lan_body.contains("Net.start_committed"), "only committed ready room launches")
	t.ok(lan_body.find('Input.is_action_just_pressed("menu_back")') < lan_body.find("Net.start_committed"), "cancel precedes launch")

	# ---- (d) 收摊必须成套（少一件 = 幽灵房 / 幽灵连接）----
	var td := _func_body(menu, "func _lan_teardown(")
	for name in ["_lan_wait = false", "LanBrowser.stop()", "Net.close()"]:
		t.ok(td.contains(name), "`_lan_teardown()` 里有 " + name)
	t.ok(_func_body(menu, "func _cancel_lan(").contains("stage = Stage.MODE"),
		"`_cancel_lan()` 回**模式页**（联机现在从模式页直接进，不再经过机体页）")
	t.ok(_func_body(menu, "func _begin_lan_wait(").contains("_lan_wait_elapsed = 0.0"),
		"开始等待时秒表归零（否则第二次建房一进去就「超时」）")

	# ---- (e) 第三层保险：Esc 保险丝覆盖联机页 ----
	var inp := _func_body(menu, "func _input(")
	t.ok(inp.contains("or stage == Stage.LAN"), "`_input()` 的 Esc 保险丝覆盖 `Stage.LAN`")
	t.ok(inp.contains("_cancel_lan()"), "Esc 在联机页走 `_cancel_lan()`（与 `menu_back` 同一条路）")
	t.ok(inp.contains("_esc_fuse_frame = Engine.get_process_frames()"),
		"⚠️ 保险丝要**告诉轮询路径**它已经处理过（否则同一帧退两层）")
	t.ok(_func_body(menu, "func _read_lan_input(").contains("_esc_fuse_frame"),
		"…而轮询路径真的看这个标记")

	# Hosts keep rooms open; only unconnected guest attempts time out.
	t.ok(_func_body(menu,"func _lan_hint_key(").contains("Esc 离开房间"), "room has a visible exit")
	var m := MainMenu.new()
	var role_was: int = Net.role
	m._lan_wait = true
	Net.role = HOST
	m._lan_wait_elapsed = Net.LAN_WAIT_TIMEOUT + 5.0
	m._read_lan_input()
	t.ok(m._lan_wait,"host room remains open while waiting")
	Net.role = Net.Role.CLIENT
	Net.peer_ready = false
	m._read_lan_input()
	t.not_ok(m._lan_wait,"unconnected guest times out")
	t.eq(Net.role,NONE,"timeout closes guest connection")
	t.ok(Game.lan_status.contains("连接超时"),"timeout reason remains visible")
	Net.role = role_was
	m.free()


# ============================================================ 只读工具

static func _code(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


## 去掉**整行注释**之后的源码。
##
## ⚠️ 源码计数必须在**代码**上数：一句"文档里提到这个名字"就能把计数喂饱 ——
## 本工程吃过这种亏（断言测的是仪器不是产品）。
static func _code_only(path: String) -> String:
	var out: Array[String] = []
	for line in _code(path).split("\n"):
		if line.strip_edges(true, false).begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)


## 取一个函数的正文（到下一个顶层 `func` / `@rpc` / `const` 行为止）。
##
## ⚠️ 只用来做"这条语句在不在里面"的源码扫描 ——
##「两个写法都在、但只有一处被调用」只有扫正文才看得见。
static func _func_body(src: String, header: String) -> String:
	var i := src.find(header)
	if i < 0:
		return ""
	var from := i + header.length()
	var end := src.length()
	for marker in ["\nfunc ", "\n@rpc", "\nconst "]:
		var j := src.find(marker, from)
		if j >= 0:
			end = mini(end, j)
	return src.substr(i, end - i)
