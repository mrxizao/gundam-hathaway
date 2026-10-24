extends Node
## 局域网联机（1.2）—— 两台机器直连的 1v1。
##
## ## 设计：**各自模拟自己的机体**，不做服务端权威
##
## 这是这个项目里"最省事但站得住"的联机模型：
##   - 每个 peer 只模拟**自己那一台**（飞行、武器、命中判定都在本地跑）；
##   - 对手那台在本地是一个**代理机体**（`NetProxyBody`）：不吃气动、不做物理，
##     位置/姿态直接按收到的快照插值过去；
##   - 开火：谁开的枪谁算命中 —— 打中了就 RPC 告诉对面"你掉血了"，
##     对面打到**自己那台**上（所以血条永远由本人维护，不存在两套血量打架）。
## 代价是双方看到的对手有一帧到几十毫秒的延迟（局域网里肉眼基本看不出来），
## 好处是不需要回滚/预测/权威裁决那一整套，代码量少一个数量级。
## 单机、训练、挑战三种模式**完全不碰网络层**（`Game.match_mode` 一分流就完事）。
##
## ## 开局前的"选择交换"（本轮补的）
## 这一局是按**双方的选择**算出来的（`LanPlan.build()`：机体 / 阵营 / 对战形式 →
## 一份部署方案），所以**出生之前两台机器必须交换完选择**。做法：
##   - 菜单在按下「主机 / 加入」时把本机的三个选择交给网络层（`announce_choice()`）；
##   - 谁先连上谁先发（主机在 `_on_peer_connected()`、加入方在 `_on_connected_to_server()`）；
##   - 菜单**等到 `choices_ready()` 为真才出击**（`MainMenu` 的 `_lan_wait`）。
##
## ⚠️ 这一条是**必须**的，不是"锦上添花"：出生之后再改选择就得重建整场，
## 而少一条选择会让 `LanPlan` 退到兜底值 —— 两台机器于是各算出一局不同的对局
##（一边场上 2 台、另一边 14 台），**两边都不报错**。
##
## ## 传输
## Godot 的 ENet 高层多人 API：主机 `create_server`，加入方 `create_client`。
## 快照 20 Hz（`SNAPSHOT_HZ`）—— 60 Hz 在局域网上也能跑，但没必要；
## 代理机体自己做插值，20 Hz 看起来已经是连续的。
##
## ⚠️ 这个 autoload 的名字**必须**叫 `Net`：
## `multiplayer` 这个名字是 Node 自带的属性，重名会直接把引擎的多人系统遮住。

const DEFAULT_PORT := 27015
const MAX_PEERS := 1 # One guest; the server itself is not counted.
## 快照发送频率（Hz）。
const SNAPSHOT_HZ := 20.0

## 房间号 / 密码 / 广播报文的**规则层**（见该文件头）。本文件只调它，不重写规则：
## 「端口 = f(房间号)」与「密码怎么比」各写一份，就是两台机器算不到一起的老路。
const LanRoom := preload("res://scripts/data/lan_room.gd")

enum Role { NONE, HOST, CLIENT }

signal lobby_changed()          ## 有人连上 / 断开
signal match_ready()            ## 双方都到位，可以开打了
signal remote_state(pkt: Dictionary)
signal remote_fire(kind: String, origin: Vector3, dir: Vector3)
signal remote_damage(amount: float, damage_type: int)

var role: int = Role.NONE
var port := DEFAULT_PORT
var address := "127.0.0.1"
## 本机在对局里的编号：主机 0、加入方 1（也就是 team）。
var local_team := 0
## 对手是否已经连上。
var peer_ready := false
## 对手选的机体（收到之后才知道）。
var remote_suit := -1
## 对手选的**阵营**（多人玩法：阵营是同乘判定的前提之一，必须同步）。
## −1 = 还没收到。收到之前双方都按"不同阵营"处理（即正常对打）。
var remote_side := -1
## 对手选的**对战形式**（`LanPlan.Form`）。−1 = 还没收到。
##
## ⚠️ 它必须同步，而且必须**在出生之前**同步到：出生之后再改就得重建整场
##（"一边场上 2 台、另一边 14 台"这种分叉没有任何运行时报错会提醒你）。
## 这是菜单里"等双方选择到齐再出击"（`choices_ready()`）存在的理由。
var remote_form := -1
## **本机开局前的选择**（菜单在按下主机 / 加入之后写进来）。
##
## ⚠️ 为什么不直接读 `Game.active_suit`：真正写那几个字段的是
## `main._resolve_match()`，而它在**出击那一刻**才跑 —— 也就是说"主机等待对手加入"
## 和"加入方等待主机"这两段等待期间，`Game.*` 里还是**上一局**的值。
## 第一版就用它发握手，结果是主机永远显示对手开的是上一局那台机。
var local_ready := false
var remote_ready := false
var start_committed := false
var squad_bodies: Dictionary = {}
var squad_tombstones: Dictionary = {}
var _choice: Dictionary = {}
var _send_accum := 0.0
var _remote_flash_armed := false
## **本机的密码哈希**（`LanRoom.auth_hash()` 的产物）—— 握手包里带出去的那一份。
##
## ⚠️ 公开房也带（带的是 `LanRoom.PUBLIC_AUTH`）：留空 = "我不要求密码"，
## 而不是"这个字段没有值"。少一个字段与"值是空"在对面看来必须是两件事。
var _my_auth: int = LanRoom.PUBLIC_AUTH
## **主机侧的期望密码哈希**。只有主机读它。
var _expected_auth: int = LanRoom.PUBLIC_AUTH
## 主机侧：这个对手**验过密码了吗**。
##
## ⚠️ 它是「密码是不是一道门」的**唯一开关**：三条老握手 RPC
##（`_rpc_hello` / `_rpc_hello_side` / `_rpc_hello_form`）都拿它当闸门。
## 不设这道闸的话，客户端只要**跳过** `_rpc_hello4`、直接发那三条老包，
## 就能把 `remote_suit/side/form` 全填上 ⇒ `choices_ready()` 为真 ⇒ 密码形同不存在。
## 加入方（客户端）恒为 true：它没有"门"要守。
var _admitted := false
## 本机开的 / 加入的**房间号**（只用于上屏与广播，不参与判定）。
var room_code := ""


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	set_process(false)


## 开主机。返回错误码（OK = 成功）。
func host_game(p := DEFAULT_PORT, expected_auth := -1) -> int:
	close()
	_expected_auth = _norm_auth(expected_auth)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(p, MAX_PEERS)
	if err != OK:
		Game.lan_status = "开主机失败（端口 %d 被占用？err=%d）" % [p, err]
		lobby_changed.emit()
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	local_team = 0
	port = p
	peer_ready = false
	# 主机自己是"已验过"的一方（它不需要向自己证明什么）。
	_admitted = true
	# ⚠️ **必须在这里开 `_process`**：`_ready()` 与 `close()` 都写死了 `set_process(false)`，
	# 而本文件里没有第二处 `set_process(true)` —— 曾经的结果是 `_process()` 永不执行，
	# 20 Hz 快照一发都发不出去，对面看到的就是"卡着不动的代理"。
	#（别的文件各有自己的开关，与本处无关 —— UI 那几处 false/true/false 的写法正是本处要照抄的。）
	#
	# 语义现在是"**在不在线**"（而不是"永久关"）：开主机 / 加入时打开，
	# `close()` 关掉。`_process()` 自己还有 `is_online()` 兜底（连接没建好就空转），
	# 所以这里打开不会产生半边连接下的误发。
	set_process(true)
	Game.lan_status = "主机 · 端口 %d · 等待对手加入" % p
	lobby_changed.emit()
	return OK


## 加入主机。
func join_game(addr := "127.0.0.1", p := DEFAULT_PORT, my_auth := -1) -> int:
	close()
	_my_auth = _norm_auth(my_auth)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(addr, p)
	if err != OK:
		Game.lan_status = "连接失败（%s:%d err=%d）" % [addr, p, err]
		lobby_changed.emit()
		return err
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	local_team = 1
	address = addr
	port = p
	peer_ready = false
	# 加入方没有门要守（门在主机那头），所以**恒为已验过**。
	_admitted = true
	# 与 `host_game()` 同一处理由：不在线时 `_process()` 靠 `is_online()` 空转，
	# 一旦握上手就自动开始发快照 —— 不要在这里再写一次 `set_process(false)`。
	set_process(true)
	Game.lan_status = "正在连接 %s:%d …" % [addr, p]
	lobby_changed.emit()
	return OK


## 按**房间号**开主机（端口由 `LanRoom.port_of_room()` 导出 —— 那是映射的唯一真源）。
##
## ⚠️ 为什么要有这个包装而不是"菜单自己算端口再调 `host_game(p)`"：
## 菜单一旦自己算，就出现了第二处"房间号 ⇒ 端口"的写法，
## 而两台机器对同一个房间号算出不同端口时，**两边都不报错**。
func host_room(code: String, auth := -1) -> int:
	room_code = LanRoom.sanitize_code(code)
	return host_game(LanRoom.port_of_room(room_code), auth)


## 按**房间号 + 主机地址**加入（端口同样由 `LanRoom` 导出）。
func join_room(code: String, addr := "127.0.0.1", auth := -1, discovered_port := -1) -> int:
	room_code = LanRoom.sanitize_code(code)
	var destination_port := discovered_port if discovered_port > 0 and discovered_port <= 65535 else LanRoom.port_of_room(room_code)
	return join_game(addr, destination_port, auth)


## 把 -1（"没传"）折成公开房的哈希。**唯一的折法**，别在两处各写一次。
static func _norm_auth(a: int) -> int:
	return a if a >= 0 else LanRoom.PUBLIC_AUTH


func close() -> void:
	_remote_flash_armed = false
	set_process(false)
	local_ready = false
	remote_ready = false
	start_committed = false
	squad_bodies.clear()
	squad_tombstones.clear()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	role = Role.NONE
	peer_ready = false
	remote_suit = -1
	remote_side = -1
	remote_form = -1
	# ⚠️ 门也要重新关上：换一个对手就是重新验一次密码。
	_admitted = false
	# ⚠️ **故意不清 `_choice`**：`host_game()` / `join_game()` 的第一件事就是
	# 调 `close()`，清了它，"先写选择再开主机"这条顺序就没得用了。
	# 菜单每次开主机 / 加入都会重新写一遍，所以它不会留到下一局之外。
	Game.lan_status = ""
	lobby_changed.emit()


func is_online() -> bool:
	return role != Role.NONE and multiplayer.multiplayer_peer != null \
		and multiplayer.multiplayer_peer.get_connection_status() \
			== MultiplayerPeer.CONNECTION_CONNECTED


## 对方连接标识（1v1 里就是唯一那个 peer id）。
func remote_id() -> int:
	if role == Role.HOST:
		var ids := multiplayer.get_peers()
		return ids[0] if not ids.is_empty() else 0
	return 1


# ============================================================ 回调

func _on_peer_connected(id: int) -> void:
	# Clients send once from connected_to_server; peer_connected(1) is the
	# same connection, not a second handshake.
	if role != Role.HOST: return
	_admitted = false
	peer_ready = true
	Game.lan_status = "对手已加入（peer %d）" % id
	lobby_changed.emit()
	# 主机主动把"我是谁、开什么机、打哪种形式"告诉对方，双方就有了对称的开局信息
	_send_hello(id)


func _on_peer_disconnected(_id: int) -> void:
	peer_ready = false
	local_ready = false
	remote_ready = false
	start_committed = false
	_admitted = role != Role.HOST
	# ⚠️ 对手走了，他那份选择也就作废了 —— 留着它，"等选择到齐"会拿到上一个人的答案。
	remote_suit = -1
	remote_side = -1
	remote_form = -1
	Game.lan_status = "对手已断开"
	lobby_changed.emit()


func _on_connected_to_server() -> void:
	peer_ready = true
	Game.lan_status = "已连接 %s:%d" % [address, port]
	lobby_changed.emit()
	# ⚠️ **加入方也要主动握手**（不能只等主机的）：
	# 主机得先知道"对面开什么、打哪种形式"才能在**出生前**把这一局定下来。
	# 主机的握手在 `_on_peer_connected()` 里发，那一头是"有人连上"；这一头是"我连上了"。
	_send_hello()


func _on_connection_failed() -> void:
	close()
	Game.lan_status = "连接失败：检查主机地址、房间号及 UDP 防火墙"


func _on_server_disconnected() -> void:
	close()
	Game.lan_status = "主机已关闭或连接中断"


func _process(delta: float) -> void:
	if not is_online():
		return
	_send_accum += delta
	if _send_accum < 1.0 / SNAPSHOT_HZ:
		return
	_send_accum = 0.0
	if start_committed and role == Role.HOST and not squad_bodies.is_empty():
		var batch := squad_tombstones.duplicate()
		for key in squad_bodies:
			var ai = squad_bodies[key]
			if is_instance_valid(ai):
				batch[key] = state_dict(ai)
				if not ai.alive: squad_tombstones[key] = batch[key]
		rpc("_rpc_squad_state", batch)
	var body = _local_body()
	if start_committed and body != null and is_instance_valid(body):
		# ⚠️ 走 `send_state()` 而不是就地 `rpc(...)`：曾经这里是唯一发送点，
		# 而 `send_state()` 是个**零调用方的死路**（同一件事两个写法）。
		# 现在只有 `send_state()` 一处发快照 —— 改协议只改一个地方。
		send_state(state_dict(body))


# ============================================================ RPC
#
# 全部走 `rpc` + `MultiplayerPeer.TRANSFER_MODE_UNRELIABLE`（默认 reliable 也行，
# 但状态快照丢一帧无所谓 —— 下一帧就补上了；开火与伤害则**必须可靠**，
# 所以它们用默认的 reliable 通道）。

## 快照：位置 / 姿态 / 速度 / 血 / 盾 / 形态 / 生死。
## **只传叶子数据**，不传节点引用（对面的节点在本机根本不存在）。
static func state_dict(body) -> Dictionary:
	return {
		"p": [body.global_position.x, body.global_position.y, body.global_position.z],
		"b": [body.global_transform.basis.x.x, body.global_transform.basis.x.y, body.global_transform.basis.x.z,
			body.global_transform.basis.y.x, body.global_transform.basis.y.y, body.global_transform.basis.y.z,
			body.global_transform.basis.z.x, body.global_transform.basis.z.y, body.global_transform.basis.z.z],
		"v": [body.fm.velocity.x, body.fm.velocity.y, body.fm.velocity.z],
		"hp": body.hp,
		"if": body.ifield_hp,
		"f": body.form_index,
		"a": body.alive,
		"tb": body.thunderbolt_systems.snapshot() if body.thunderbolt_systems!=null else {},
		"nu": body.nu_systems.snapshot() if is_instance_valid(body.nu_systems) else {},
		"cb": PackedFloat32Array([body.combat_buffs.gauge, body.combat_buffs.resonance_left, body.combat_buffs.protection_left, body.combat_buffs.kick_left]),
	}


## 反解一份快照（纯函数，便于单测）。
static func unpack_state(pkt: Dictionary) -> Dictionary:
	var p: Array = pkt.get("p", [0, 0, 0])
	var b: Array = pkt.get("b", [1, 0, 0, 0, 1, 0, 0, 0, 1])
	var v: Array = pkt.get("v", [0, 0, 0])
	# Four floats avoid pushing the frequent state packet over the ENet MTU.
	var cb: PackedFloat32Array = pkt.get("cb", PackedFloat32Array([0,0,0,0]))
	if cb.size() != 4: cb = PackedFloat32Array([0,0,0,0])
	return {
		"position": Vector3(p[0], p[1], p[2]),
		"basis": Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), Vector3(b[6], b[7], b[8])),
		"velocity": Vector3(v[0], v[1], v[2]),
		"hp": float(pkt.get("hp", 0.0)),
		"ifield": float(pkt.get("if", 0.0)),
		"form": int(pkt.get("f", 0)),
		"alive": bool(pkt.get("a", true)),
		"tb": pkt.get("tb",{}),
		"nu": pkt.get("nu",{}),
		"combat": {"gauge":cb[0], "resonance":cb[1], "protection":cb[2], "kick":cb[3]},
	}


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(suit_id: int) -> void:
	# ⚠️ 闸门（见 `_admitted`）：主机侧没验过密码的 peer，这条包一律不作数。
	if role == Role.HOST and not _admitted:
		return
	remote_suit = suit_id
	Game.lan_status = "对手：%s" % SuitProfile.by_id(suit_id).display_name
	lobby_changed.emit()
	if not peer_ready:
		peer_ready = true
	match_ready.emit()


## 对手选了什么阵营（多人玩法，第二十二轮下半）。
##
## ⚠️ 与 `_rpc_hello` **分开**两条 RPC，而不是塞进同一个包里：
## `hello` 是 1v1 就有的老协议，测试与旧存档路径都在用它；
## 加字段会让"只发机体"那条路带一个默认值，反而更容易被误读。
@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello_side(side: int) -> void:
	if role == Role.HOST and not _admitted:
		return
	remote_side = side
	lobby_changed.emit()


## 对手选了什么**对战形式**（`LanPlan.Form`）。
##
## ⚠️ 与另两条握手同样是**分开的一条 RPC**，理由同 `_rpc_hello_side`：
## 老协议（只有机体）的路径不能被塞进一个带默认值的新字段 —— 默认值恰好是
## "小队战"，那会让"其实还没收到"和"收到的是小队战"变成同一个状态。
@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello_form(form: int) -> void:
	if role == Role.HOST and not _admitted:
		return
	remote_form = form
	lobby_changed.emit()


## 菜单在按下「主机 / 加入」之后调用：**把本机这一局的选择交给网络层**。
##
## 传进来的三个值就是菜单上选的那三个（机体 / 阵营 / 对战形式），
## 它们会成为之后所有握手包的内容 —— 包括"对端刚连上时补发的那一次"。
## 见 `_choice` 的注释：不这么做，握手包里装的是**上一局**的机体。
func announce_choice(suit_id: int, side: int, form: int) -> void:
	if start_committed:
		return
	if role == Role.CLIENT and remote_form >= 0:
		form = remote_form
	if _choice != {"suit": suit_id, "side": side, "form": form}:
		local_ready = false
		remote_ready = false
	_choice = {"suit": suit_id, "side": side, "form": form}
	# 连接还没建立时**只存不发** —— 真正把它送出去的是 `_on_connected_to_server()`
	#（加入方连上的那一刻）与 `_on_peer_connected()`（主机侧看到对端连上）。
	# 没连上就 `rpc()` 会当场报错，而那种错误在联机里最难查：游戏照样跑完。
	if is_online():
		_send_hello()


## **本机这一票**里的一项（`_choice` 优先，没写过就退回 `fallback`）。
##
## ⚠️ **`main` 组这一局的方案时必须读它，不能读 `Game.*`**：
## `announce_choice()` 是本机选择的**唯一真源**（它就是发出去的那一份），
## 而 `Game.active_suit` / `active_side` / `active_lan_form` 是**另一条链**上的值，
## 两者可能不一致 —— 实测过两处：
##   - **`Game.active_side` 在联机这条路里从来没人写过**（菜单的 `_launch()` 只给
##     小队战写它）：于是本机那一票的阵营恒为兜底值，而对面那一票是**真的**。
##     两台机器于是按不同的 (host_side, client_side) 分配编制 ——
##     正是"两台机器各算出一局不同的对局、两边都不报错"那件事；
##   - `Game.active_lan_form` 同理（它会一直是 `SQUAD`，"王牌战"永远算不出来）。
## 读这一份则天然对称：本机读自己的 `_choice`、对面读 `remote_*`，两条都是**同一个包**。
##
## [param fallback] = `_choice` 里没有这一项时用的值（调用方一般传 `Game.*`，
## 于是不走菜单的测试 / 探针路径逐位保持原行为）。
func choice_of(key: String, fallback: int) -> int:
	return int(_choice.get(key, fallback))


func _send_hello(only_to := 0) -> void:
	# ⚠️ 定点发送（`only_to > 0`）**不查 `is_online()`**：主机在 `_on_peer_connected()`
	# 里发这一包时，"本端是服务器"这个状态与"我连上了别人"不是同一回事，
	# 早先那版就是不加判据直接发的 —— 加判据反而可能让主机那一包悄悄不发。
	if multiplayer.multiplayer_peer == null:
		return
	if only_to <= 0 and not is_online():
		return
	var s := choice_of("suit", Game.active_suit)
	var sd := choice_of("side", Game.active_side)
	var fm := choice_of("form", Game.active_lan_form)
	# ⚠️ **只发一条**（四合一）。`suite_lan_room` 有一条源码扫描钉着这里的包数：
	# 拆回三条就会重新出现"少一条就静默退到兜底值 ⇒ 两台机器算出两局不同对局"。
	if only_to > 0:
		rpc_id(only_to, "_rpc_hello4", s, sd, fm, _my_auth)
	else:
		rpc("_rpc_hello4", s, sd, fm, _my_auth)


## **双方的选择都到齐了吗** —— 规则的**本体**（纯函数，不读全局）。
##
## 判据是**三样都在**（机体 / 阵营 / 形式），不是只看 `peer_ready`：
## `peer_ready` 只说明"连接通了"，而这一局是按双方选择**算**出来的
##（`LanPlan.build()`），少一样就会退到兜底值 —— 于是两台机器各算出一局不同的对局
##（一边场上 2 台、另一边 14 台），**两边都不报错**。
##
## ⚠️ 抽成 static 纯函数是为了让这条规则**能被单测直接喂数断言**：
## 它守的是"两台机器算同一局"，而这件事只有两台机器才能验 ——
## 至少要让判据本身可测（测试见 `suite_ace_duel`）。
## `choices_ready()` 只是把**本机当前状态**填进去，规则只有这一份。
static func launch_ready(net_online: bool, suit: int, side: int, form: int) -> bool:
	return net_online and suit >= 0 and side >= 0 and form >= 0


## 上面那条规则在**本机当前状态**下的答案 —— 菜单用它决定"能不能出击"。
func choices_ready() -> bool:
	return peer_ready and _admitted and launch_ready(is_online(), remote_suit, remote_side, remote_form)


## 等对手的选择到齐的时限（秒）。
##
## ⚠️ 不设它就是"永久卡住"：等待态的**正常**出口是 `choices_ready()`，而对手
## 始终不进房间时那几个 `remote_*` 永远是 −1 ⇒ 那个出口永远不成立。
## 加入方还有一条"连接失败 / 主机已关"的出口（那两条回调都会 `close()` ⇒ `role` 回 NONE），
## 但**主机**那一侧 `role` 恒为 `HOST` ⇒ 只有时限能救它。
##（用户报的「对方没有进房间就会一直卡住，没有退出的办法」正是这一条。）
const LAN_WAIT_TIMEOUT := 20.0


## **等对手等过头了吗** —— 纯函数，**只比时间**。
##
## ⚠️ **“已经断开”不在这里判** —— 那件事由 `wait_exit()` 的 ③ 号出口负责。
## 两处都判的代价不是啰嗦，是**可证伪性**：实测把 `wait_exit()` 的 ③④ 对调，
## 整份套件照样 161 PASS / 0 FAIL —— 因为这道 NONE 门先替它挡了。
## ⇒ 一条规则一处判，位置才断得住。
static func lan_wait_timed_out(elapsed: float, timeout: float) -> bool:
	return elapsed >= timeout


## 等对手的那一刻，**该走哪条出口**。
enum WaitExit {
	STAY,       ## 继续等
	LAUNCH,     ## 双方选择到齐 ⇒ 出击
	LINK_LOST,  ## 连接没了（加入方连不上 / 主机已关）⇒ 回可操作态
	TIMEOUT,    ## 等过头了 ⇒ 收拾干净、停在联机页
	CANCEL,     ## 玩家按了返回 ⇒ 回机体选择页
}


## 上面那张表的**次序本体**（纯 static，不读输入也不读本机状态）。
##
## 抽成纯函数的唯一理由：**可测**。调用它的是 `MainMenu._read_lan_input()`，那一段
## 读的是 `Input.is_action_just_pressed` —— 而注入按键在无头下不可靠
##（`tutorial_director.gd:48` 实测：连注 40 次一次不触发；工程里
## `nav_delta_y()` / `submit_password()` / `launch_ready()` 三处先例同源）。
##
## ⚠️⚠️ **下面这个次序就是 bug 本体**：历史实现把"继续等"写在了玩家取消之前
##（等待态无条件 `return`）⇒ `_lan_wait` 置真之后**没有任何函数能把它置回假**，
## 于是"建了房、没人进来"永久卡住。所以每一条的**相对位置**都要有断言看着 ——
## 只断"CANCEL 这一支存在"是不够的（挪到末尾照样存在）。
static func wait_exit(back_pressed: bool, choices_ready: bool, role_now: int,
		elapsed: float, timeout := LAN_WAIT_TIMEOUT) -> int:
	# ① 玩家按了返回：**最优先**。他刚做出的意图压过"对面刚好也在这一帧到齐"；
	#    排在后面的话这一帧就出击了，那一下 Esc 会被彻底吃掉。
	if back_pressed:
		return WaitExit.CANCEL
	# ② 双方选择到齐 ⇒ 正常出口。
	if choices_ready:
		return WaitExit.LAUNCH
	# ③ 连接没了 ⇒ 回可操作态。
	#
	# ⚠️ 这一支**必须排在超时之前**，而且**不许把它搬进 `lan_wait_timed_out()`**：
	#    · 排到后面 ⇒ 明明已经断开还要干等满 20 s（负对照 NC-C 实测会红）；
	#    · 搬进去   ⇒ 两条出口的相对次序就**不可证伪**了（对调 ③④ 照样全绿 —— 本轮第一版就是那么写的）。
	if role_now == Role.NONE:
		return WaitExit.LINK_LOST
	# ④ 等过头了。走到这里 `role` 必然是 HOST / CLIENT。
	if lan_wait_timed_out(elapsed, timeout):
		return WaitExit.TIMEOUT
	return WaitExit.STAY


## 告诉对方"我选的是哪台机"（开局前调用）。
func announce_suit(suit_id: int) -> void:
	if is_online():
		rpc("_rpc_hello", suit_id)


## 告诉对方"我选的是哪个阵营"（多人玩法的同乘判定要用）。
func announce_side(side: int) -> void:
	if is_online():
		rpc("_rpc_hello_side", side)


## **四合一握手**（轮 63-6 批 4 §六 新增）：机体 / 阵营 / 形式 / 密码哈希。
##
## ## 为什么把三条老包合成这一条
## 老的 `_send_hello()` 一次发 **3 个 rpc**。三条**各自都可能**因为
## "对面还没准备好 / 顺序错"而落到兜底值上（`choice_of()` 的 fallback），
## 于是两台机器**各算出一局不同的对局、两边都不报错** ——
## 那正是 `_choice` 那段注释里点名过的事故。合成一条之后，
## **"收到"这件事本身就是原子**：要么四样全到，要么等于没收到。
##
## ## 密码在哪一步判定
## 主机（`Role.HOST`）收到后先比 `auth`：
##   - 通过 ⇒ `_admitted = true`，四条老闸门同时打开；
##   - 不通过 ⇒ **主机主动把该 peer 踢掉**并把原因写进 `Game.lan_status`。
##     ⚠️ **绝不允许"客户端自己退出"** —— 那等于没有密码（改客户端就绕过了）。
##
## 老三条 RPC **保留**（`announce_suit` / `announce_side` 还在用，且
## `suite_ace_duel` 断着"形式是单独一条"这条语义）；它们现在只服务
## **入局之后**的单字段更新，并且以 `_admitted` 为闸门。
@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello4(suit_id: int, side: int, form: int, auth: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	if role == Role.HOST and not LanRoom.accepts(_expected_auth, auth):
		# ⚠️ 只说"密码不对"，**不说差在哪**（位数 / 前缀）—— 那等于把密码告诉猜的人。
		Game.lan_status = "对手密码不正确，已拒绝（peer %d）" % from
		_kick(from)
		lobby_changed.emit()
		return
	if start_committed:
		return
	if form not in [LanPlan.Form.ACE_DUEL, LanPlan.Form.SQUAD] or suit_id not in SuitProfile.Id.values() or side not in BattleFormation.Side.values():
		return
	_admitted = true
	if remote_suit != suit_id or remote_side != side or remote_form != form:
		local_ready = false
		remote_ready = false
	remote_suit = suit_id
	remote_side = side
	remote_form = choice_of("form", form) if role == Role.HOST else form
	if role == Role.CLIENT:
		_choice["form"] = form
	Game.lan_status = "对手：%s" % SuitProfile.by_id(suit_id).display_name
	lobby_changed.emit()
	if not peer_ready:
		peer_ready = true
	match_ready.emit()


## 把某个 peer 请出去（密码不对时主机唯一的正确动作）。
##
## ⚠️ 用 `has_method` 兜一层：ENet 的 `disconnect_peer` 是本工程的依赖，
## 但探针 / 单测里 `multiplayer_peer` 可能是别的实现 ——
## 那种情况下**至少要把状态写清楚**，而不是崩在一个不存在的方法上
##（联机路径上的崩溃是最难归因的一类：游戏照样跑完）。
func _kick(id: int) -> void:
	if id <= 0 or id not in multiplayer.get_peers():
		return
	var peer := multiplayer.multiplayer_peer
	if peer != null and peer.has_method("disconnect_peer"):
		peer.disconnect_peer(id, true)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rpc_state(pkt: Dictionary) -> void:
	remote_state.emit(pkt)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_fire(kind: String, origin: Vector3, dir: Vector3) -> void:
	remote_fire.emit(kind, origin, dir)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_damage(amount: float, damage_type: int) -> void:
	remote_damage.emit(amount, damage_type)


# ---- 对外发送 ----

## 发一份状态快照（**唯一发送点**，由 `_process()` 以 20 Hz 调用）。
##
## ⚠️ 曾经它是一个**零调用方的死路**，而 `_process()` 里另有一句就地 `rpc(...)` ——
## 同一件事两个写法。现在 `_process()` 走这里，改协议（或加重发 / 补包）只改一处。
func send_state(pkt: Dictionary) -> void:
	if is_online():
		rpc("_rpc_state", pkt)


## 别人开火：本机在**他那一台代理机体**的位置生成同样的弹丸（只做视觉/声音，
## 命中判定在他那边完成 —— 谁开的枪谁算命中，见文件头）。
func send_fire(kind: String, origin: Vector3, dir: Vector3) -> void:
	if is_online():
		rpc("_rpc_fire", kind, origin, dir)


## 我打中了对方：把伤害交给**对方本人**结算（他的血条他维护）。
func send_thunder_status(kind:String,direction:Vector3)->void:
	if is_online():rpc("_rpc_thunder_status",kind,direction)

@rpc("any_peer","call_remote","reliable")
func _rpc_thunder_status(kind:String,direction:Vector3)->void:
	if not is_online() or multiplayer.get_remote_sender_id()!=remote_id() or not is_instance_valid(Game.player):return
	if (kind=="sting" and remote_suit==SuitProfile.Id.PSYCHO_ZAKU_TB) or (kind=="ram" and remote_suit==SuitProfile.Id.FULL_ARMOR_TB):
		if direction.is_finite():Game.player.apply_thunder_status(kind,direction)

func send_damage(amount: float, damage_type: int) -> void:
	if is_online():
		rpc("_rpc_damage", amount, damage_type)


## 对局结束时互相通知（谁赢谁输由双方各自判定，这里只是把"我没了"说出来）。
func send_defeat() -> void:
	if is_online():
		rpc("_rpc_defeat")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_defeat() -> void:
	Game.lan_remote_dead = true


func _local_body() -> Node3D:
	return Game.player


# Room settings are host-owned. Either player may request a change; changing
# either loadout invalidates both confirmations. Ready packets name the exact
# pair of choices so an old confirmation cannot launch a revised room.
func room_signature() -> String:
	var mine := "%d/%d/%d" % [choice_of("suit",-1),choice_of("side",-1),choice_of("form",-1)]
	var other := "%d/%d/%d" % [remote_suit,remote_side,remote_form]
	return mine + ":" + other if role == Role.HOST else other + ":" + mine

func request_form(form: int) -> void:
	if start_committed or form not in [LanPlan.Form.ACE_DUEL, LanPlan.Form.SQUAD]: return
	if role == Role.CLIENT:
		if choices_ready(): rpc_id(1, "_rpc_request_form", form)
	elif role == Role.HOST:
		remote_form = form if remote_form >= 0 else -1
		announce_choice(choice_of("suit",0), choice_of("side",0), form)
		local_ready = false
		remote_ready = false
		lobby_changed.emit()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_form(form: int) -> void:
	if role == Role.HOST and _admitted: request_form(form)

func set_ready(value: bool) -> void:
	if start_committed: return
	if not choices_ready():
		Game.lan_status = "连接已建立，正在同步双方选择，请稍后准备" if peer_ready else "尚未连接到对手，请等待连接完成"
		lobby_changed.emit()
		return
	if value and not valid_pair():
		Game.lan_status = invalid_pair_reason()
		return
	local_ready = value
	rpc_id(remote_id(), "_rpc_ready", value, room_signature())
	lobby_changed.emit()
	_try_start()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_ready(value: bool, signature: String) -> void:
	if start_committed or not choices_ready() or signature != room_signature(): return
	remote_ready = value
	lobby_changed.emit()
	_try_start()

func _try_start() -> void:
	if role != Role.HOST or start_committed or not choices_ready() or not local_ready or not remote_ready or not valid_pair(): return
	var guest := {"suit":remote_suit,"side":remote_side,"form":remote_form}
	rpc_id(remote_id(), "_rpc_start", _choice, guest)
	start_committed = true
	match_ready.emit()

@rpc("authority", "call_remote", "reliable")
func _rpc_start(host_choice: Dictionary, guest_choice: Dictionary) -> void:
	if role != Role.CLIENT or start_committed or not local_ready: return
	if guest_choice != _choice: return
	remote_suit = int(host_choice["suit"])
	remote_side = int(host_choice["side"])
	remote_form = int(host_choice["form"])
	remote_ready = true
	start_committed = true
	match_ready.emit()


static func valid_room_choice(suit: int, side: int, form: int) -> bool:
	if form == LanPlan.Form.ACE_DUEL:
		return suit in [SuitProfile.Id.FULL_ARMOR_TB,SuitProfile.Id.PSYCHO_ZAKU_TB,SuitProfile.Id.XI, SuitProfile.Id.XI_FINAL,SuitProfile.Id.REGZ_CUSTOM,SuitProfile.Id.NU_GUNDAM,SuitProfile.Id.SAZABI,SuitProfile.Id.ZORIN_SOUL,SuitProfile.Id.PENELOPE,SuitProfile.Id.ARIZEUS,SuitProfile.Id.GP03D,SuitProfile.Id.NEUE_ZIEL]
	return BattleFormation.belongs_to(side, suit) and suit not in [SuitProfile.Id.GP03D,SuitProfile.Id.NEUE_ZIEL]

func valid_pair() -> bool:
	var suit := choice_of("suit",-1)
	if SuitProfile.is_thunderbolt(suit) or SuitProfile.is_thunderbolt(remote_suit):
		return choice_of("form",-1)==LanPlan.Form.ACE_DUEL and remote_form==LanPlan.Form.ACE_DUEL and SuitProfile.is_thunderbolt(suit) and remote_suit==SuitProfile.thunderbolt_opponent(suit)
	var form := choice_of("form",-1)
	if not valid_room_choice(suit,choice_of("side",-1),form) or not valid_room_choice(remote_suit,remote_side,form): return false
	var ma := [SuitProfile.Id.GP03D,SuitProfile.Id.NEUE_ZIEL]
	return (suit in ma and remote_suit in ma) if suit in ma or remote_suit in ma else true

func invalid_pair_reason() -> String:
	if SuitProfile.is_thunderbolt(choice_of("suit",-1)) or SuitProfile.is_thunderbolt(remote_suit):return "雷霆宙域机体仅限王牌战：全装备高达与精神力扎古互相对决"
	var ma := [SuitProfile.Id.GP03D,SuitProfile.Id.NEUE_ZIEL]
	if choice_of("suit",-1) in ma or remote_suit in ma:
		return "GP03D / 露维杰露仅支持近地轨道镜像战或互相对战；小队战请选阵营机体"
	return "机体或阵营不适用于当前形式，请选择王牌战或重新选择阵营机体"

static func requires_axis(a:int,b:int)->bool:
	var suits := [SuitProfile.Id.NU_GUNDAM,SuitProfile.Id.SAZABI]
	return a in suits and b in suits

static func requires_colony(a:int,b:int)->bool:
	return SuitProfile.is_thunderbolt(a) and SuitProfile.is_thunderbolt(b)

func match_map() -> int:
	# Restrict only pairs where both pilots chose Nu or Sazabi.
	var pair := [choice_of("suit",-1), remote_suit]
	if requires_colony(pair[0],pair[1]):
		return MapDef.Id.COLONY_RUINS
	if requires_axis(pair[0],pair[1]):
		return MapDef.Id.AXIS
	return MapDef.Id.LEO if SuitProfile.Id.GP03D in pair or SuitProfile.Id.NEUE_ZIEL in pair else MapDef.Id.PACIFIC


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _rpc_squad_state(batch: Dictionary) -> void:
	if not start_committed: return
	for key in batch:
		var ai = squad_bodies.get(key)
		if is_instance_valid(ai): ai.receive_snapshot(batch[key])

func send_ai_damage(key: String, amount: float, damage_type: int) -> void:
	if start_committed and is_online(): rpc_id(1,"_rpc_ai_damage",key,amount,damage_type)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_ai_damage(key: String, amount: float, damage_type: int) -> void:
	if role != Role.HOST or not start_committed or not _admitted or not is_finite(amount) or amount <= 0: return
	var ai = squad_bodies.get(key)
	if is_instance_valid(ai):
		var source: Node3D = null
		for body in get_tree().get_nodes_in_group("units"):
			if body is NetProxyBody: source = body; break
		ai.take_damage(amount, source, damage_type)

# Victim acknowledges actual accepted damage; rejected hits grant no resonance.
func send_resonance_credit(amount: float) -> void:
	if is_online(): rpc("_rpc_resonance_credit",amount)
@rpc("any_peer", "call_remote", "reliable")
func _rpc_resonance_credit(amount: float) -> void:
	if not is_online() or not is_finite(amount) or amount <= 0.0: return
	var body = Game.player
	if is_instance_valid(body) and body.is_nu(): body.combat_buffs.gain(body,minf(amount,100.0))

func send_kick_confirmation() -> void:
	if is_online(): rpc("_rpc_kick_confirmation")
@rpc("any_peer", "call_remote", "reliable")
func _rpc_kick_confirmation() -> void:
	if not is_online() or not start_committed: return
	var body = Game.player
	if is_instance_valid(body) and body.profile.id == SuitProfile.Id.SAZABI:
		body.combat_buffs.kick_cd = body.combat_buffs.KICK_COOLDOWN
		body.notice.emit("夏亚飞踢生效 · 20秒", 2.0)


# Reliable launch/burst ordering keeps the remote projectile and whiteout in sync.
func send_flashbang_event(action: String,origin: Vector3,direction: Vector3) -> void:
	if is_online():rpc("_rpc_flashbang_event",action,origin,direction)

@rpc("any_peer","call_remote","reliable")
func _rpc_flashbang_event(action: String,origin: Vector3,direction: Vector3) -> void:
	if not is_online() or not start_committed or not _admitted or multiplayer.get_remote_sender_id()!=remote_id():return
	if remote_suit!=SuitProfile.Id.FULL_ARMOR_TB or Game.phase!=Game.Phase.FIGHT or not origin.is_finite() or not direction.is_finite():return
	if action=="launch" and direction.length_squared()>0.01:
		_remote_flash_armed=true
		remote_fire.emit("tb_flash_launch",origin,direction.normalized())
	elif action=="burst" and _remote_flash_armed:
		_remote_flash_armed=false
		remote_fire.emit("tb_flash_burst",origin,Vector3.ZERO)
		if is_instance_valid(Game.player):Game.player.apply_flashbang(origin)
