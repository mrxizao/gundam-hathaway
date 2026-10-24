extends Control
## 轮 63-6 · 批 4 §六「房间 + 密码」的**真机判据图台**。
##
## ## 为什么不去 boot `main.tscn`
## 本轮判据**只在菜单上**（`Stage.LAN` 的三个子屏）。`MainMenu` 是自带 `_ready()`、
## `_draw()` 无守卫的 `Control`，`new` 出来挂树上就能画 —— 沿用 `tools/menu_shot.gd`
## 那条已验过的路（⚠️ 本台子**只能验菜单**，别拿它去验世界里的东西）。
##
## ## ⚠️ 本台子是**真机台**：不能加 `--headless`
## dummy 渲染器一个像素都不产生。跑法：
##   Godot_v4.7.1-stable_win64_console.exe --path <工程> --resolution 2560x1600 \
##       res://tools/_r63_6_lan_shots.tscn -- <输出目录>
##
## ## ★ 房间列表那一档走的是**真实广播链路**，不是手塞数组
## 判据 6 要证明的是「搜到的房能画出来」。手填 `lan_rooms` 只证明**绘制函数会画数组**，
## 证明不了 `收到 UDP → JSON → LanRoom.parse_beacon() → rooms() → 画` 这条链。
## ⇒ 本台子当**发送方**：自建一个 `PacketPeerUDP`，把 `LanRoom.beacon()` 造的包
## 发到 `127.0.0.1:27016`，`LanBrowser` 那边真收、真解析。
## （回环直投而不是 `255.255.255.255`：受限广播在单机上不保证回环给本机监听者。）
## 同时故意混一份**魔数不对**的包进去 —— 它必须**不出现在**列表里（拒收那一半）。
##
## ## ⚠️ 探针摆位声明
## `02/03/04/05/06` 那几档的 `lan_row` / `lan_editing` / `lan_pass` 是**探针直接摆的**。
## 玩家当然也能这么走到（都是合法输入路径），但本台子**不是从标题页一路按进来的** ——
## 摆位只是为了让每一行的读数在同一批图里各出现一次。
## 打字一律走**产品函数** `_lan_type()`（不直接赋 `lan_code`），这样"回显"与"洗输入"
## 走的是同一条代码。

const LanRoom := preload("res://scripts/data/lan_room.gd")

## ⚠️ 渲染历史（TAA）要几十帧才收敛。菜单是 2D 静态层本来不敏感，但这条别改小。
const SETTLE := 40

var _out := ""
var _menu: MainMenu
var _stub: PacketPeerUDP = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://_r63_6_shots"
	DirAccess.make_dir_recursive_absolute(_out)
	printerr("[lanshot] out = %s" % _out)
	printerr("[lanshot] window = %s  viewport = %s" % [
		str(DisplayServer.window_get_size()), str(get_viewport().get_visible_rect().size)])
	await _run()
	printerr("[lanshot] DONE")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## 截当前视口。⚠️ 必须等 `frame_post_draw`：早一帧拿到的是上一帧的画布。
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png("%s/%s.png" % [_out, name])
	printerr("[lanshot] %-22s %dx%d  err=%d" % [
		name, img.get_width(), img.get_height(), err])


## 当"另一台机器"：把一份广播投到本机 27016。
func _send_beacon(info: Dictionary) -> void:
	if _stub == null:
		_stub = PacketPeerUDP.new()
		_stub.set_broadcast_enabled(true)
	_stub.set_dest_address("127.0.0.1", LanRoom.DISCOVERY_PORT)
	_stub.put_packet(JSON.stringify(info).to_utf8_buffer())


## 原始文本包（用来喂"魔数不对"的垃圾）。
func _send_raw(txt: String) -> void:
	if _stub == null:
		_stub = PacketPeerUDP.new()
		_stub.set_broadcast_enabled(true)
	_stub.set_dest_address("127.0.0.1", LanRoom.DISCOVERY_PORT)
	_stub.put_packet(txt.to_utf8_buffer())


## 摆一档：切子屏 / 换选中行 / 重置字段，然后等画面稳定、出图。
func _stage_shot(name: String, sub: int, row: int) -> void:
	_menu.stage = MainMenu.Stage.LAN
	_menu.lan_sub = sub
	_menu.lan_row = row
	_menu.lan_editing = false
	_menu.queue_redraw()
	await _frames(SETTLE)
	await _shot(name)


func _run() -> void:
	_menu = MainMenu.new()
	_menu.name = "LanProbe"
	add_child(_menu)
	await _frames(4)
	printerr("[lanshot] 菜单进树：visible=%s size=%s" % [str(_menu.visible), str(_menu.size)])

	_menu.stage = MainMenu.Stage.LAN
	_menu.lan_sub = MainMenu.LAN_SUB_MAIN
	_menu.lan_row = MainMenu.LAN_ROW_CREATE
	_menu.lan_code = ""
	_menu.lan_pass = ""
	_menu.lan_form_choice = 0
	_menu.lan_adv_row = MainMenu.LAN_ADV_ADDR

	# ======================================================== 一、主列表 7 行
	await _stage_shot("01_主列表_默认",
		MainMenu.LAN_SUB_MAIN, MainMenu.LAN_ROW_CREATE)

	# ---- 房间号：**编辑中**（读数尾部会多一条光标 `_`，这是"能不能输"的唯一视觉证据）----
	# 打字一律走 `_lan_type()`；先 `lan_editing = true` 让 `_lan_field()` 认这一行。
	_menu.lan_row = MainMenu.LAN_ROW_CODE
	_menu.lan_editing = true
	for ch in "042517":
		_menu._lan_type(ch)
	printerr("[lanshot] 输 6 位后 lan_code=%s  field=%d" % [
		_menu.lan_code, _menu._lan_field()])
	_menu.queue_redraw()
	await _frames(SETTLE)
	await _shot("02_房间号_编辑中")

	# ---- 密码：已填（读数应为 ● 串，明文一个字都不上屏）----
	_menu.lan_row = MainMenu.LAN_ROW_PASS
	_menu.lan_editing = true
	for ch in "8351":
		_menu._lan_type(ch)
	printerr("[lanshot] 输密码后 len=%d 值=%s" % [
		_menu.lan_pass.length(), _menu.lan_pass])
	_menu.lan_editing = false
	_menu.queue_redraw()
	await _frames(SETTLE)
	await _shot("03_密码_已输入")

	# ---- 密码：留空（= 公开房）----
	_menu.lan_pass = ""
	_menu.lan_editing = false
	_menu.queue_redraw()
	await _frames(SETTLE)
	await _shot("04_密码_留空")

	# ---- 加入行：房间号**没输满** ⇒ 读数必须是那句指路，而不是一个必然连不上的地址 ----
	_menu.lan_code = ""
	_menu.lan_editing = true
	for ch in "0425":
		_menu._lan_type(ch)
	_menu.lan_editing = false
	_menu.lan_row = MainMenu.LAN_ROW_JOIN
	printerr("[lanshot] 只输 4 位：code_ok=%s 读数=%s" % [
		str(LanRoom.code_ok(_menu.lan_code)), _menu.lan_row_value(MainMenu.LAN_ROW_JOIN)])
	_menu.queue_redraw()
	await _frames(SETTLE)
	await _shot("05_加入行_未输满")

	# ---- 形式行：左右拨到「王牌战」----
	_menu.lan_code = "042517"
	_menu.lan_form_choice = 1
	_menu.queue_redraw()
	await _stage_shot("06_形式_王牌战",
		MainMenu.LAN_SUB_MAIN, MainMenu.LAN_ROW_FORM)
	_menu.lan_form_choice = 0

	# ======================================================== 二、高级子页
	await _stage_shot("07_高级子页_地址",
		MainMenu.LAN_SUB_ADV, MainMenu.LAN_ROW_CREATE)
	_menu.lan_adv_row = MainMenu.LAN_ADV_PORT
	_menu.queue_redraw()
	await _frames(SETTLE)
	await _shot("08_高级子页_端口")
	_menu.lan_adv_row = MainMenu.LAN_ADV_ADDR

	# ======================================================== 三、房间列表
	# 先起"搜索"——这一步**真的绑 27016**。绑不上就当场知道（不静默）。
	var ok := LanBrowser.start_browse()
	printerr("[lanshot] start_browse() = %s  browsing=%s" % [
		str(ok), str(LanBrowser.is_browsing())])
	await _frames(SETTLE)
	printerr("[lanshot] 搜索页刚起来：rooms=%d" % LanBrowser.rooms().size())
	await _stage_shot("09_房间列表_空", MainMenu.LAN_SUB_ROOMS, MainMenu.LAN_ROW_CREATE)

	# ---- 当"另外三台机器"各广播一次；再混一份**魔数不对**的垃圾 ----
	var beacons: Array = [
		LanRoom.beacon("042517", LanRoom.PORT_BASE + 17, 1, 2, true),
		LanRoom.beacon("318204", LanRoom.PORT_BASE + 4, 0, 3, false),
		LanRoom.beacon("770031", LanRoom.PORT_BASE + 31, 0, 1, true),
	]
	for b: Dictionary in beacons:
		_send_beacon(b)
		await _frames(2)
	# 垃圾包：魔数不对 ⇒ `parse_beacon()` 必须返回空 ⇒ **不许进列表**
	_send_raw(JSON.stringify({"m": "SOME_OTHER_APP", "code": "999999",
		"port": LanRoom.PORT_BASE + 99, "form": 0, "players": 1, "locked": false}))
	# 越界端口的假包：魔数对、端口不在本协议值域 ⇒ 也必须拒
	_send_raw(JSON.stringify(LanRoom.beacon("111111", 65535, 0, 1, false)))
	await _frames(SETTLE)

	var got := LanBrowser.rooms()
	printerr("[lanshot] 收到 %d 间（期望 3；垃圾包与越界端口包都必须在门外）" % got.size())
	for r: Dictionary in got:
		printerr("[lanshot]   %s" % str(r))
	# 产品函数 `_read_lan_rooms_input()` 每帧重取，这里也读一遍同一口径。
	_menu.lan_rooms = LanBrowser.rooms()
	_menu.lan_room_sel = 1
	_menu.queue_redraw()
	await _frames(SETTLE)
	await _shot("10_房间列表_三个房")

	# 收尾：不要把 27016 留着（后面还有别的台子要跑）。
	LanBrowser.stop()
	_stub = null
	printerr("[lanshot] stop 后 is_active=%s" % str(LanBrowser.is_active()))
	printerr("[lanshot] LAN 行数=%d  子屏数=%d" % [
		MainMenu.LAN_ROWS.size(), 3])
