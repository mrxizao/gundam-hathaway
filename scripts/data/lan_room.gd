extends RefCounted
## **局域网房间 + 密码**的纯数据层 —— 规则与判定形态的**唯一真源**。
##
## ## 需求原文（老板，2026-10-03 设计文档 §六）
## > 「局域网改成**房间 + 密码**：房间号 = 主路径，IP/端口退到「高级」。」
##
## 老板当轮拍板的四条：
##   1. **做**广播房间列表（UDP 27016，自动发现）；
##   2. 房间号 = **主机生成 + 可复制**（不是玩家自定）；
##   3. 密码 **允许留空**（空 = 公开房），填了就是 **4~8 位**；
##   4. 菜单里「地址 / 端口」两行**收进「高级」子页**。
##
## ## 这一个文件负责三件事（每一件都只有这一份）
## 1. **房间号 ↔ 端口**（`sanitize_code` / `code_ok` / `port_of_room` / `new_code`）；
## 2. **密码**（`sanitize_pass` / `pass_ok` / `auth_hash` / `accepts`）；
## 3. **发现广播的报文格式**（`beacon()` / `parse_beacon()`）——
##    主机与客户端两侧都调它，所以"两边对同一个包的理解"不可能分家。
##
## ## ⚠️ 密码**不是安全设施**
## ENet 不加密，房间号与端口在局域网上是明文可探测的 —— 而且本机就能随便试密码。
## 密码只做"别让隔壁工位的人误入"这一件事。**上屏文案必须把这个说清楚**
##（`PASS_NOTE`），否则玩家会以为它是隐私保护。
##
## ## ⚠️ 房间号只有**低两位**决定端口
## `port = 27015 + (code mod 100)` ⇒ 同一台机器上最多 100 个房间不撞。
## 后果：`123456` 与 `223456` **落在同一个端口上**（这是设计，不是 bug）。
## 因此**能唯一确定端口的只有低两位**；高四位是给人念/给人抄的。
## 广播发现那条路会把**真实端口**一起带回来，所以"搜索房间"没有这个歧义。
##
## ## ⚠️ 跨文件引用走 `preload`，不走 `class_name`
## 与 `producer.gd` / `campaign.gd` 同一条纪律：本仓库是并行编辑的，
## 新加的 `class_name` 要等编辑器扫过才会进 `.godot/global_script_class_cache.cfg`，
## 而 `--headless` 跑测试时没人刷那份缓存 ⇒ 那样写会当场 `Identifier not found`。

## 房间号位数（6 位十进制）。
const CODE_DIGITS := 6
## 房间号的最大值（6 位 ⇒ 0..999999）。
const CODE_MAX := 999999

## 端口基数 = `NetSession.DEFAULT_PORT`。**刻意在这里抄一份而不是引用它**：
## 本文件是纯数据层、不 import 任何 autoload；两边一旦不一致，
## 判据 `port_of_room()` 的值域断言会当场红。
const PORT_BASE := 27015
## 房间槽位数（100 个房间不撞）。
const PORT_SPAN := 100

## 广播发现的端口（与 ENet 的 27015 是**两套 socket**，别混）。
const DISCOVERY_PORT := 27016
## 广播报文里用来认领的魔数。收到不认识的头一律丢掉 ——
## 局域网里会有别的程序在广播，不筛的话菜单会列出乱七八糟的东西。
const BEACON_MAGIC := "GUNDAM_LAN_V1"

## 密码位数下限 / 上限。**空串是合法的**（= 公开房），见 `pass_ok()`。
const PASS_MIN := 4
const PASS_MAX := 8

## 空密码的哈希值 = FNV-1a 32 位的偏移基数（空串不进循环，原样返回）。
## ⇒ 公开房的判据就是一个常数比较，不必每次都重算一遍哈希。
## `suite_lan_room` 里有一条断言把这两个钉在一起（防它俩悄悄漂开）。
const PUBLIC_AUTH := 2166136261

## 上屏用的说明。⚠️ **必须说"不是安全"** —— 见文件头。
const PASS_NOTE := "密码只是门槛：局域网里未加密，挡的是误入不是攻击"
## 公开房（不设密码）时密码栏的读数。
const PASS_OPEN_TEXT := "（空 = 公开房）"


## 房间号洗成"可判定的形态"：**只留数字**，截到 `CODE_DIGITS`。
##
## ⚠️ 它同时是**回显**与**判定**的上游（两处都调它）—— 只在判定里洗、
## 回显里不洗，就会出现"框里是 `12a3`、判定按 `123` 算"这种没人查得出来的错位
##（`producer.gd` 开头那段说的是同一条纪律）。
static func sanitize_code(raw: String) -> String:
	return _digits(raw, CODE_DIGITS)


## 房间号是否合法：**恰好 6 位**（不多不少）。
##
## ⚠️ 不满 6 位**不算合法**：房间号是"两个人之间的凭据"，
## 允许 3 位的话 `001234` 与 `1234` 会变成两个不同的房间号却指向同一端口，
## 玩家照着念的时候必然出事。
static func code_ok(raw: String) -> bool:
	return sanitize_code(raw).length() == CODE_DIGITS


## 房间号 ⇒ 端口。**唯一的映射真源**（`Net.host_game` / `Net.join_game` 都调它）。
##
## 非法房间号退回端口基数（而不是报错）：菜单在玩家还没输满 6 位时就会画读数，
## 那时它得有一个确定的值可显示。**判定合法性是 `code_ok()` 的事**，别在这里混。
static func port_of_room(raw: String) -> int:
	var c := sanitize_code(raw)
	if c.length() == 0:
		return PORT_BASE
	return PORT_BASE + (int(c) % PORT_SPAN)


## 主机生成一个房间号。
##
## ⚠️ 传 `RandomNumberGenerator` 进来而不是用全局 `randi()`：
## 判据要能**喂定种子复现**（`suite_lan_room` 就靠这条验证"生成的一定合法"），
## 而全局随机源在测试里被别的套件动过之后就不确定了。
static func new_code(rng: RandomNumberGenerator) -> String:
	return "%0*d" % [CODE_DIGITS, rng.randi_range(0, CODE_MAX)]


## 密码洗成"可判定的形态"：**只留数字**，截到 `PASS_MAX`。
##
## ⚠️ 截到 8 而不是"8+2"：8 就是上限，第 9 下按不进去是**对的**；
## 而退格永远能用（`producer.gd` 那两格余量是给它那个"判定只看 8 位、
## 但允许输入更多"的场景准备的，本处不需要）。
static func sanitize_pass(raw: String) -> String:
	return _digits(raw, PASS_MAX)


## 密码是否合法：**空**（公开房）或者 **4~8 位**。
##
## ⚠️ 1~3 位**不合法**：那种密码在局域网里等同于没有，
## 却会让房主以为"我设了密码"。宁可在这里拦住。
static func pass_ok(raw: String) -> bool:
	var p := sanitize_pass(raw)
	if p.length() == 0:
		return true
	return p.length() >= PASS_MIN and p.length() <= PASS_MAX


## 密码 ⇒ 32 位 FNV-1a 哈希（**确定性纯函数**）。
##
## ⚠️ 说清它**不是**加密：目的是"别把明文密码塞进握手包和日志"，
## 不是防谁。真正的问题（ENet 明文、本机可爆破）它一条都解决不了。
static func auth_hash(raw: String) -> int:
	var s := sanitize_pass(raw)
	var h := 2166136261
	for i in s.length():
		h = (h ^ s.unicode_at(i)) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	return h


## 主机侧判定：这一个握手该不该放进来。
##
## ⚠️ 两条规则，顺序不能反：
##   ① **本房是公开房（`expected == PUBLIC_AUTH`）⇒ 任何人可进**。
##      不这么写的话，"房主没设密码、客人却手滑输了密码"会被拒 ——
##      而玩家的心智模型是"公开房谁都能进"，被拒只会以为程序坏了。
##   ② 否则必须**逐位相同**。
static func accepts(expected_auth: int, got_auth: int) -> bool:
	if expected_auth == PUBLIC_AUTH:
		return true
	return expected_auth == got_auth


## 广播报文（主机定期广播 / 收到询问时回一份）。
##
## ⚠️ 只放"客户端决定要不要进"所需的字段，**不放密码、也不放密码哈希**：
## 哈希虽然不可逆，但局域网内录下来离线对 4 位数字爆破是几毫秒的事。
## `locked` 只回答"要不要密码"，进门靠握手时的 `auth_hash`。
static func beacon(code: String, port: int, form: int, players: int,
		locked: bool, status := "") -> Dictionary:
	return {
		"m": BEACON_MAGIC,
		"code": sanitize_code(code),
		"port": port,
		"form": form,
		"players": players,
		"locked": locked,
		"status": status,
	}


## 反解一份广播。**认不出就返回空字典**（调用方判 `is_empty()`）——
## 乱丢报文的程序在局域网上到处都是，这里不能抛错也不能猜。
##
## 与 `beacon()` 成对：字段名的唯一真源就是上面那个函数，
## 所以"两边对同一个包的理解"不可能分家。
static func parse_beacon(d: Dictionary) -> Dictionary:
	if String(d.get("m", "")) != BEACON_MAGIC:
		return {}
	var code := sanitize_code(String(d.get("code", "")))
	if not code_ok(code):
		return {}
	var port := int(d.get("port", 0))
	# ⚠️ 端口必须落在**本协议自己的值域**里：广播这东西谁都能伪造，
	# 不筛的话"搜索房间"列表里会出现端口 0 或 65535 的幽灵房，
	# 点进去就是一次必失败的连接。
	if port < PORT_BASE or port >= PORT_BASE + PORT_SPAN:
		return {}
	return {
		"code": code,
		"port": port,
		"form": int(d.get("form", 0)),
		"players": int(d.get("players", 0)),
		"locked": bool(d.get("locked", false)),
		"status": String(d.get("status", "")),
	}


## 房间列表里一行的显示文本（**唯一写法**：菜单与测试都读它）。
static func room_line(code: String, form: int, players: int, locked: bool) -> String:
	var form_txt := "王牌战" if form == 1 else "小队战"
	var lock_txt := "需密码" if locked else "公开"
	return "%s · %s · %d 人 · %s" % [code, form_txt, players, lock_txt]


## 只留数字，截到 `n` 位。上面几个 `sanitize_*` 的共用实现。
static func _digits(raw: String, n: int) -> String:
	var out := ""
	for i in raw.length():
		var c := raw[i]
		if c >= "0" and c <= "9":
			out += c
			if out.length() >= n:
				break
	return out
