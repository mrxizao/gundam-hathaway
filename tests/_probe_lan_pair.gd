extends Node
## **跨进程**联机探针 —— 两份真进程、走真 ENet/UDP 回环（127.0.0.1）。
##
## 一次性探针，**故意不注册进** `tests/test_runner.gd` 的 `SUITES`（它需要两个进程）。
##
## ## 为什么必须有它
##
## 工程里已有 456 条联机断言（`suite_net_sync` 21 / `suite_lan_plan` 125 /
## `suite_lan_room` 154 / `suite_lan_spawn` 19 / `suite_lan_lobby` 20 / `suite_ace_duel` 117），
## 但它们**全在同一个进程里**：`Net` 是个 autoload，测试直接改它的字段，
## RPC 从来没真的走过一次序列化 + socket + 对端反序列化。
##
## ⇒ 这一层只有"两个进程"能证：ENet 握手、`_rpc_hello4` 的**真序列化**、
##    密码门在真连接上的表现（踢人 → 对端回到 NONE）、
##    "主机拥有房间设置"在真链路上传不传得过去、双方 ready 一起提交。
##
## ## 跑法（**必须先起主机**，隔 ~1.5 s 再起客机）
##
## ```
## GODOT="C:/Users/MSIPC/Desktop/Godot_v4.7.1-stable_win64_console.exe"
## "$GODOT" --headless --path "C:/Users/MSIPC/Documents/gundam" res://tests/_probe_lan_pair.tscn \
##     -- --role=host --scenario=happy --port=27015 --out=C:/tmp/lan_host.json
## sleep 1.5
## "$GODOT" --headless --path "C:/Users/MSIPC/Documents/gundam" res://tests/_probe_lan_pair.tscn \
##     -- --role=guest --scenario=happy --port=27015 --out=C:/tmp/lan_guest.json
## ```
##
## 三个场景：`happy`（双方准备 → 开局）· `badpass`（密码不对 ⇒ 主机踢人 + 客机回 NONE）·
## `formswap`（**主机**改对战形式 ⇒ 客机必须跟着改；这条是"房间设置归主机"在真链路上的判据）。
##
## ⚠️ 探针**只驱动生产 API**（`Net.*`），一个替身都没有 —— 与 `_probe_overfire.gd` 同一条纪律。

const LanRoom := preload("res://scripts/data/lan_room.gd")

## ACE 战合法机体（`NetSession.valid_room_choice()` 白名单里的两台，且都不是大型 MA）。
const ACE_A := SuitProfile.Id.XI
const ACE_B := SuitProfile.Id.PENELOPE
## 小队战的两台合法"阵营机体"（各自属于自己那一侧）。
const SQUAD_A := SuitProfile.Id.MESSER_M01        # 马夫蒂
const SQUAD_B := SuitProfile.Id.GUSTAV00          # 地球联邦

var _role := "host"
var _scenario := "happy"
var _port := 27015
var _addr := "127.0.0.1"
var _out := ""
var _budget := 20.0

var _t0 := 0
var _steps: Array[String] = []
var _fail := ""


func _ready() -> void:
	_parse()
	await _run()


func _parse() -> void:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--role="): _role = s.substr(7)
		elif s.begins_with("--scenario="): _scenario = s.substr(11)
		elif s.begins_with("--port="): _port = int(s.substr(7))
		elif s.begins_with("--addr="): _addr = s.substr(7)
		elif s.begins_with("--out="): _out = s.substr(6)
		elif s.begins_with("--budget="): _budget = float(s.substr(9))


func _p(msg: String) -> void:
	_steps.append("%6d ms  %s" % [Time.get_ticks_msec() - _t0, msg])
	print("[LAN:%s] %s" % [_role, msg])


## 等到 `cond` 为真或超时。返回是否等到。
func _until(what: String, cond: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			_p("WAIT ok  : %s" % what)
			return true
		await get_tree().process_frame
	_p("WAIT fail: %s（超时 %.1f s）" % [what, seconds])
	if _fail == "":
		_fail = what
	return false


func _run() -> void:
	_t0 = Time.get_ticks_msec()
	Game.reset()
	Net.close()
	var is_host := _role == "host"

	# ---- 建房 / 加入 ----
	if is_host:
		# ⚠️ badpass 场景：**主机用正确密码**，客机用错的 —— 门才有的可踢。
		var hp := "2468" if _scenario == "badpass" else "1357"
		var e := Net.host_game(_port, LanRoom.auth_hash(hp))
		_p("host_game(port=%d, pass=%s) -> err=%d  status=%s" % [_port, hp, e, Game.lan_status])
		if e != OK:
			_fail = "host_game 失败"
	else:
		var gp := "9999" if _scenario == "badpass" else "1357"
		var e := Net.join_game(_addr, _port, LanRoom.auth_hash(gp))
		_p("join_game(%s:%d, pass=%s) -> err=%d  status=%s" % [_addr, _port, gp, e, Game.lan_status])
		if e != OK:
			_fail = "join_game 失败"

	# ---- 报出本机这一票 ----
	var side_a := BattleFormation.Side.MAFTY
	var side_b := BattleFormation.Side.FEDERATION
	var form := LanPlan.Form.ACE_DUEL if _scenario != "formswap" else LanPlan.Form.SQUAD
	var suit := ACE_A if is_host else ACE_B
	var side := side_a if is_host else side_b
	if _scenario == "formswap":
		suit = SQUAD_A if is_host else SQUAD_B
	Net.announce_choice(suit, side, form)
	_p("announce_choice(suit=%d, side=%d, form=%d)" % [suit, side, form])

	if _scenario == "badpass":
		await _badpass(is_host)
		_finish()
		return

	# ---- 双方选择到齐 ----
	await _until("choices_ready()", func(): return Net.choices_ready(), 10.0)

	if _scenario == "formswap":
		await _formswap(is_host, side_a, side_b)

	# ---- 一起准备 ----
	if not await _until("可以按下准备（choices_ready）", func(): return Net.choices_ready(), 5.0):
		_finish()
		return
	Net.set_ready(true)
	_p("set_ready(true) -> local=%s remote=%s status=%s"
		% [Net.local_ready, Net.remote_ready, Game.lan_status])

	# ---- 双方准备 ⇒ 开局 ----
	await _until("start_committed（双方准备后开局）", func(): return Net.start_committed, 12.0)
	if Net.start_committed:
		_p("开局：本机 form=%d suit=%d side=%d｜对方 suit=%d side=%d form=%d"
			% [Net.choice_of("form", -1), Net.choice_of("suit", -1), Net.choice_of("side", -1),
				Net.remote_suit, Net.remote_side, Net.remote_form])
	_finish()


## 密码门：主机必须**主动踢**，客机必须**回到 NONE**（不许停在"已连接"）。
func _badpass(is_host: bool) -> void:
	if is_host:
		await _until("Game.lan_status 里出现「密码不正确」",
			func(): return String(Game.lan_status).contains("密码不正确"), 10.0)
	else:
		await _until("被拒后 role 回到 NONE（不是一直停在 CLIENT）",
			func(): return Net.role == Net.Role.NONE, 10.0)
	_p("badpass 收尾：status=%s role=%d" % [Game.lan_status, Net.role])


## **主机拥有房间设置**：主机改形式 ⇒ 客机必须跟着改（否则两台机器算两局）。
func _formswap(is_host: bool, side_a: int, side_b: int) -> void:
	if is_host:
		_p("主机 request_form(ACE_DUEL)")
		Net.request_form(LanPlan.Form.ACE_DUEL)
		_p("  ⇒ 本机 local_ready=%s remote_ready=%s（改设置必须把**双方**的准备清掉）"
			% [Net.local_ready, Net.remote_ready])
		# 主机这一侧没有"要等的东西"（房间设置是它自己写的），
		# 给它 1.2 s 让 hello 往返一趟，再去改报机体。
		await get_tree().create_timer(1.2).timeout
		# 换成对 ACE_DUEL 合法的机体（小队机体在王牌战里不合法 ⇒ 必须重选）
		Net.announce_choice(ACE_A, side_a, LanPlan.Form.ACE_DUEL)
		_p("主机改报 (suit=%d, form=ACE_DUEL)" % ACE_A)
	else:
		await _until("客机跟上了主机的形式（choice_of(\"form\") == ACE_DUEL）",
			func(): return Net.choice_of("form", -1) == LanPlan.Form.ACE_DUEL, 10.0)
		Net.announce_choice(ACE_B, side_b, LanPlan.Form.ACE_DUEL)
		_p("客机改报 (suit=%d, form=ACE_DUEL)" % ACE_B)


func _finish() -> void:
	var res := {
		"role": _role,
		"scenario": _scenario,
		"port": _port,
		"fail": _fail,
		"start_committed": Net.start_committed,
		"choices_ready": Net.choices_ready(),
		"peer_ready": Net.peer_ready,
		"local_ready": Net.local_ready,
		"remote_ready": Net.remote_ready,
		"role_end": Net.role,
		"own_suit": Net.choice_of("suit", -1),
		"own_side": Net.choice_of("side", -1),
		"own_form": Net.choice_of("form", -1),
		"remote_suit": Net.remote_suit,
		"remote_side": Net.remote_side,
		"remote_form": Net.remote_form,
		"status": Game.lan_status,
		"ms": Time.get_ticks_msec() - _t0,
		"steps": _steps,
	}
	# ⚠️ 结果**同时**打一行带标记的 JSON 到 stdout：
	#    跨进程比对不能依赖文件（写不出来 / 路径带盘符 / 权限都可能出事），
	#    而 stdout 是两份进程都必然有的东西。驱动脚本只 grep 这一行。
	var line := JSON.stringify(res)
	print("LANRESULT %s" % line)
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(res, "  "))
		f.close()
		print("[LAN:%s] 写出 %s" % [_role, _out])
	else:
		print("[LAN:%s] ⚠️ 写不出 %s（以 LANRESULT 那一行为准）" % [_role, _out])
	Net.close()
	await get_tree().process_frame
	get_tree().quit(0)
