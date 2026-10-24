extends Node
## 局域网**广播发现**（设计文档 §六「发现」那一行）—— 让"加入房间"不用手抄 IP 与端口。
##
## ## 为什么单开一个 autoload，而不是塞进 `NetSession`
## 1. **两套 socket**：ENet 在 27015，发现广播在 27016。混在一个类里，
##    生命周期会被 `Net.close()` 一起带走（而"关掉这局、回去搜别的房"是正常操作）；
## 2. `net_session.gd` 已经 400+ 行、且被 `suite_ace_duel` **逐行扫过**，
##    往里加无关职责会把那套断言变成噪声源。
##
## ## 协议：**主机单向广播，客户端只听**（不做"询问—应答"）
##
## 早先想过让客户端广播"谁在开房"、主机回一份。改成单向广播是因为
## **端口占用**：询问式要求主机**绑定** 27016 才能收到询问，
## 而客户端也要绑 27016 才能收应答 ⇒ 同机双开（本工程唯一的实测手段）直接撞死。
## 现在主机用**临时端口**往外发（`set_broadcast_enabled`），
## 只有"正在搜索房间"的那一方占用 27016 ⇒ 同机双开也跑得起来。
##
## ## 报文格式的**唯一真源**是 `lan_room.gd`
## 本文件只负责"把 `LanRoom.beacon()` 造出来的字典发出去 / 收回来"，
## 一个字段都不在这里拼。两边对同一个包的理解因此不可能分家。
##
## ## ⚠️ 广播内容**不含密码、也不含密码哈希**
## 只回答"要不要密码"（`locked`）。理由见 `LanRoom.beacon()`。
##
## ## ⚠️ 懒开 socket
## `_ready()` 里**什么都不建**，`set_process(false)`。只有真的
## 「创建房间」（`host_beacon`）或「搜索房间」（`start_browse`）才动 socket。
## 否则每一个场景 —— 包括 480 多个测试套件 —— 都要为一个用不上的 UDP 端口付代价。

const LanRoom := preload("res://scripts/data/lan_room.gd")

## 一份广播在列表里能活多久（毫秒）。主机每 `BEACON_HZ` 秒发一次，
## 3 秒收不到就当它关了 —— 房主强杀进程时不会留下一个点不进去的幽灵房。
const ROOM_TTL_MS := 3000
## 主机广播频率（Hz）。1 Hz 足够：列表刷新本来就是给人看的。
const BEACON_HZ := 1.0

signal rooms_changed()          ## 列表内容变了（新增 / 过期 / 人数变了）
signal browse_failed(reason: String)

## 收到的房间：`code` → `{"info": {...}, "seen": 毫秒}`
var _found: Dictionary = {}
## 正在搜索房间（占用 27016）。
var _browsing := false
## 正在广播（主机侧，占用临时端口）。
var _beaconing := false
var _beacon_accum := 0.0
var _beacon_pkt: Dictionary = {}


func _ready() -> void:
	set_process(false)


# ============================================================ 搜索侧

## 开始搜索局域网里的房间。返回是否成功（失败时 `browse_failed` 也发一次）。
func start_browse() -> bool:
	stop()
	var udp := PacketPeerUDP.new()
	# ⚠️ 绑 `0.0.0.0` 而不是某个网卡地址：局域网里"我在哪张卡上"是玩家管不着的事，
	# 只绑回环的话，另一台机器发来的广播永远收不到（而菜单上什么都看不出来）。
	var err := udp.bind(LanRoom.DISCOVERY_PORT, "0.0.0.0")
	if err != OK:
		browse_failed.emit("搜索失败（端口 %d 被占用？err=%d）" % [LanRoom.DISCOVERY_PORT, err])
		return false
	_sock = udp
	_browsing = true
	_found.clear()
	set_process(true)
	return true


## 停止搜索（离开这一页 / 加入成功之后）。
func stop_browse() -> void:
	if not _browsing:
		return
	_browsing = false
	_found.clear()
	_maybe_idle()


## 当前搜到的房间，按房间号排序（**稳定顺序**：不给列表加"每次刷新都跳一下"的毛病）。
##
## 返回 `[{code, port, form, players, locked, status}]`（`LanRoom.parse_beacon()` 的形态）。
func rooms() -> Array:
	var now := Time.get_ticks_msec()
	var out: Array = []
	for code in _found.keys():
		var e: Dictionary = _found[code]
		if now - int(e.get("seen", 0)) > ROOM_TTL_MS:
			continue
		out.append(e.get("info", {}))
	out.sort_custom(func(a, b): return String(a.get("code", "")) < String(b.get("code", "")))
	return out


# ============================================================ 广播侧（主机）

## 开始广播本房。`locked` 只表示"本房要密码"，**不传密码本身**。
func host_beacon(code: String, port: int, form: int, locked: bool) -> void:
	stop()
	var udp := PacketPeerUDP.new()
	# ⚠️ 不 bind：让系统给一个临时端口，这样"同机双开"时主机与搜索方不抢 27016。
	# 代价是主机收不到任何东西 —— 它也不需要收，单向广播。
	# ⚠️ `set_broadcast_enabled()` 在 Godot 4.7 里返回 **void**（不是 `Error`）——
	# 写成 `var err := udp.set_broadcast_enabled(true)` 会当场
	# `Parse Error: Cannot get return value of call to ... because it returns "void"`，
	# 整个 autoload 加载不了（`LanBrowser` 变成 Nil，菜单里第一处用到它的分支才炸）。
	udp.set_broadcast_enabled(true)
	_sock = udp
	_beaconing = true
	_beacon_pkt = LanRoom.beacon(code, port, form, 1, locked)
	_beacon_accum = BEACON_HZ          # 立刻发第一份，不等 1 秒
	set_process(true)


## 房间里的人数变了 / 换了形式 ⇒ 更新广播内容（下一拍就带出去）。
func update_beacon(players: int, form := -1) -> void:
	if not _beaconing:
		return
	_beacon_pkt["players"] = players
	if form >= 0: _beacon_pkt["form"] = form


func stop_beacon() -> void:
	if not _beaconing:
		return
	_beaconing = false
	_beacon_pkt = {}
	_maybe_idle()


## 收摊：两边都停了就关 socket、停 `_process`。
func stop() -> void:
	_browsing = false
	_beaconing = false
	_found.clear()
	_beacon_pkt = {}
	_sock = null
	set_process(false)


# ============================================================ 每帧

var _sock: PacketPeerUDP = null


func _process(delta: float) -> void:
	if _browsing:
		_poll()
	if _beaconing:
		_beacon_accum += delta
		if _beacon_accum >= 1.0 / BEACON_HZ:
			_beacon_accum = 0.0
			_send_beacon()


## 把排队里的广播全部收下来。
##
## ⚠️ 用 `while` 而不是 `if`：一帧里可能积压好几份（另一台机器 1 Hz、
## 但主线程卡一下就会攒两三个），只取一个的话列表刷新会慢半拍。
func _poll() -> void:
	if _sock == null:
		return
	var changed := false
	while _sock.get_available_packet_count() > 0:
		var buf := _sock.get_packet()
		var txt := buf.get_string_from_utf8()
		var parsed = JSON.parse_string(txt)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue                   # 局域网里别人发的垃圾，丢掉就是了
		var info := LanRoom.parse_beacon(parsed)
		if info.is_empty():
			continue                   # 不是本协议的包（含魔数不符 / 端口越界）
		# ⚠️ **必须把发包方 IP 带上**：拿到它，"选中即加入"就不用玩家再抄一遍地址，
		# 而且它比"房间号反推端口"更准（广播带回来的是**真实端口**）。
		# `parse_beacon()` 是白名单反解，所以这一项要在这里补。
		info["ip"] = _sock.get_packet_ip()
		var code := String(info["code"])
		var prev: Dictionary = _found.get(code, {})
		var prev_info: Dictionary = prev.get("info", {})
		_found[code] = {"info": info, "seen": Time.get_ticks_msec()}
		if prev_info != info:
			changed = true             # 人数 / 形式变了，要刷列表
	if changed or _expire():
		rooms_changed.emit()


## 把过期的那几条摘掉。返回是否真的摘掉了东西。
func _expire() -> bool:
	var now := Time.get_ticks_msec()
	var dead: Array = []
	for code in _found.keys():
		if now - int(_found[code].get("seen", 0)) > ROOM_TTL_MS:
			dead.append(code)
	for code in dead:
		_found.erase(code)
	return not dead.is_empty()


func _send_beacon() -> void:
	if _sock == null or _beacon_pkt.is_empty():
		return
	var txt := JSON.stringify(_beacon_pkt)
	# ⚠️ 广播地址写 `255.255.255.255`（受限广播）。局域网里"本网段的广播地址"
	# 要靠掩码算，而玩家改子网掩码这件事我们管不着；受限广播由系统按每张网卡
	# 各自发一份，跨网段仍然是收不到的（那是 IP 与端口的活，见「高级」子页）。
	_sock.set_dest_address("255.255.255.255", LanRoom.DISCOVERY_PORT)
	_sock.put_packet(txt.to_utf8_buffer())


## 只有一边在用时也把 `_process` 关掉（两边都停 ⇒ 完全静默）。
func _maybe_idle() -> void:
	if not _browsing and not _beaconing:
		_sock = null
		_found.clear()
		set_process(false)


## 有没有在干活（给测试与菜单读的口径）。
func is_active() -> bool:
	return _browsing or _beaconing


func is_browsing() -> bool:
	return _browsing


func is_beaconing() -> bool:
	return _beaconing
