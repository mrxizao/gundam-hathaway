class_name SuiteReverseFly
extends RefCounted
## ★63-9 · D2「辅助驾驶模式下 CTRL 切换成"倒着飞"」。
##
## ## 用户原话
## 「在辅助驾驶模式下，CTRL 键按下可以切换飞行模式：按下 ctrl 会变成倒着飞，
## w 就变成减速，s 就变成加速。」
##
## ## 拍板口径（设计文档 §3.2 的 ①(b) + ②(a)）
## **只翻速度方向，机头一个字节不动** ⇒ 锁定 / 弹道 / 军刀吸附 / 炮口锚点
## 全部逐位不变（这是唯一不需要改 `README.md` 需求 4 的那条路）。
##
## ## ⚠️ 门是 `translate_mode`，不是"辅助开着"
## CTRL（动作名 `hover`）在普通飞行里是**悬停**，只有平移模式下它是**空键**
##（`_read_translate_input()` 全文不读 `hover`）。阿利宙斯巡航形态与骑飞行踏板
## 时辅助也开着，但那两支走普通飞行读取 ⇒ 在那些形态里让 CTRL 变空键比今天的悬停更糟。
##
## ## ⚠️ 无锁定目标时的**自旋坑**（这一段是本轮最值钱的一条）
## 平移模式无目标时，机头追**速度矢量**；底速一反过来，真实速度也是反的
## ⇒「机头追速度」每帧都在追一个与自己差 180° 的方向 ⇒ **连续自旋**（不是抖动）。
## 正解：倒飞时水平朝向改追**等效正向速度**（`vref`）。
## ⑤ 段的"机头不许转超过 15°"就是这条的牙齿 —— 去掉 `vref` 那一笔它必红。
##
## ## 五段判据
##   ① 结构：门 / 键位不冲突 / 写入点只有 3 处且都在该在的地方；
##   ② 纯函数：`translate_base_dir(fwd, false)` **逐位**等于今天 + 语义量化；
##   ③ 清零：关辅助 / 禁控 ⇒ `translate_reverse` 归 false（防语义残留）；
##   ④ 真机：CTRL ⇒ `fm.velocity · forward()` **变号** + 左上角提示；再按复原；
##   ⑤ HUD：三个 x 偏移的**大小关系**（"倒飞格挤到系统提示行上"= 等于没画）。
##
## ## 负对照（六个，每个只许红它该红的那几条）
##   `nc_pure_hard`     `translate_base_dir()` 写死 `-fwd` ⇒ 只红 ② 第一条
##   `nc_no_clear`      砍掉 `_tick_reverse_toggle()` 的归零 ⇒ 只红 ③
##   `nc_no_guard`      砍掉 `_think()` 哨兵段的归零 ⇒ 只红 ③ 第二条
##   `nc_hover_in_tx`   把 `hover` 读进平移路 ⇒ 只红 ① 的关键位不冲突
##   `nc_no_vref`       去掉 `vref` 那一笔（用真实速度）⇒ 只红 ⑤ 的机头不转
##   `nc_hud_stack`     把 `ASSIST_REVERSE_X` 改成 260（压到提示行上）⇒ 只红 ④ 的位置关系
##   `nc_no_flip`       `_apply_translate()` 里底速不取反 ⇒ 只红 ⑤ 的变号

const PC_SRC := "res://scripts/flight/player_controller.gd"
const FB_SRC := "res://scripts/flight/flight_body.gd"
const HUD_SRC := "res://scripts/ui/hud.gd"
const HELP_SRC := "res://scripts/autoload/input_setup.gd"

## 真机段：跑这么多帧再看速度（底速换向的追随速率 `TRANSLATE_RESPONSE = 3.2`
## ⇒ 0.16 s 过零、1.0 s 到位 ~93%）。
const LIVE_FRAMES := 75
## 固定高度：平移模式一直往前飞，不钉位置会飞出场景 / 撞边界。
const LIVE_Y := 900.0


static func run(t: T, host: Node) -> void:
	t.suite("ReverseFly / ① 结构：门是 translate_mode、hover 仍只在手动路（D2）")
	_structure(t)
	t.suite("ReverseFly / ② 纯函数：关着时逐位等于今天 + W/S 语义量化（D2）")
	_pure(t)
	t.suite("ReverseFly / ③ 清零：关辅助 / 禁控 ⇒ 不留倒飞状态（D2）")
	await _clear(t, host)
	t.suite("ReverseFly / ④ 真机：CTRL ⇒ 速度变号 + 再按复原 + 提示（D2）")
	await _live(t, host)
	t.suite("ReverseFly / ⑤ 自旋守卫 + HUD 三个 x 的位置关系（D2）")
	await _spin(t, host)
	_hud(t)


# ================================================================ 工具

## 取某个函数的**函数体**（从标题之后到下一个 `func ` 之前）。
##
## ⚠️ 必须配 `SuiteUiStyle._code()` 用 —— 本轮的注释里到处都在提 `hover` /
## `translate_reverse`，不剥注释的话"平移路里没有 hover"这条断言会被注释判红。
static func _body(src: String, header: String) -> String:
	var i := src.find(header)
	if i < 0:
		return ""
	var rest := src.substr(i + header.length())
	var j := rest.find("\nfunc ")
	return rest if j < 0 else rest.substr(0, j)


## 从源码里读一个 `const X := <数>` 的值（**只给 HUD 的三个 x 偏移用**）。
##
## 为什么不直接从 `FlightHUD.ASSIST_STATE_X` 取：本工程的反自证规矩 ——
## 判据的目标值若从被验常量里取，把常量改坏时判据会跟着一起变（永远绿）。
## 这里是"三个数的大小关系"，所以要**从源码文本解析**再比。
static func _const_num(src: String, name: String) -> float:
	var head := "const %s := " % name
	var i := src.find(head)
	if i < 0:
		return -1.0
	var rest := src.substr(i + head.length())
	var j := 0
	while j < rest.length() and rest[j] != "\n" and rest[j] != "\r":
		j += 1
	return float(rest.substr(0, j))


## 一个玩家机 + 一块空地（顶面在 y = 0），物理帧先跑起来再交给测试。
##
## ⚠️ `set_physics_process(true)`（默认）：`_think()` 必须**真的跑** ——
## `translate_mode` / `translate_reverse` 都写在它里面，手摆字段只能骗自己。
static func _stage(host: Node, pos: Vector3, assist: bool) -> Dictionary:
	Game.reset()
	var c := Node3D.new()
	c.name = "ReverseFlyStage"
	host.add_child(c)
	var pc := PlayerController.new()
	pc.name = "ReverseProbe"
	pc.profile = SuitProfile.xi()
	pc.is_player = true
	pc.team = 0
	pc.projectile_container = c
	c.add_child(pc)
	pc.controls_enabled = true
	pc.assist_on = assist
	pc.global_position = pos
	# ⚠️ **必须等两帧**：`physics_frame` 信号是在各节点 `_physics_process`
	# **之前**发出的 ⇒ 只等一帧时协程先于 `_think()` 恢复，读到的是上一帧的状态
	#（第一版就是这么翻的：③ 的"前置：进了平移模式"红，而 ④ 跑完却又是对的）。
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	return {"c": c, "pc": pc}


static func _teardown(host: Node, st: Dictionary) -> void:
	(st["c"] as Node).free()
	await host.get_tree().process_frame
	Game.reset()


# ================================================================ ① 结构

static func _structure(t: T) -> void:
	var pc_src := SuiteUiStyle._code(PC_SRC)
	var fb_src := SuiteUiStyle._code(FB_SRC)
	var tx := _body(pc_src, "func _read_translate_input")
	var fl := _body(pc_src, "func _read_flight_input")
	var tk := _body(pc_src, "func _think")
	var tg := _body(pc_src, "func _tick_reverse_toggle")

	# ---- 前置：函数体真的取到了（取不到时下面全是"空串里没有 X"的恒真）----
	t.gt(tx.length(), 200, "取到了 `_read_translate_input()` 的函数体（%d 字符）" % tx.length())
	t.gt(fl.length(), 200, "取到了 `_read_flight_input()` 的函数体（%d 字符）" % fl.length())
	t.gt(tg.length(), 50, "取到了 `_tick_reverse_toggle()` 的函数体（%d 字符）" % tg.length())

	# ---- 键位不冲突：hover 只许出现在手动路（设计文档 §3.2 判据 3）----
	t.not_ok(tx.contains("\"hover\""),
		"`_read_translate_input()` 里**不出现** `\"hover\"` —— 平移模式下 CTRL 是空键")
	t.not_ok(tx.contains("KEY_CTRL"),
		"`_read_translate_input()` 里也不出现裸键码 `KEY_CTRL`")
	t.ok(fl.contains("Input.is_action_pressed(\"hover\")"),
		"`_read_flight_input()` 仍然读 `hover` ⇒ 手动路的悬停语义一字未改")

	# ---- 读**动作名**不读键码（改绑之后倒飞跟着走）----
	t.ok(tg.contains("Input.is_action_just_pressed(\"hover\")"),
		"开关读的是动作名 `hover`（just_pressed = 点按切换，不是按住）")
	t.not_ok(tg.contains("KEY_CTRL"),
		"开关**不读键码** —— 玩家把悬停改绑到别的键之后倒飞照样能用")

	# ---- 门与顺序：`translate_mode` 先写、开关随后读它 ----
	t.ok(tk.contains("_tick_reverse_toggle()"),
		"`_think()` 里真的调了开关（漏了它 = 纯函数全绿、游戏里按 CTRL 没反应）")
	t.gt(tk.find("_tick_reverse_toggle()"), tk.find("translate_mode = assist_on"),
		"调用点在 `translate_mode = ...` **之后**（判据同源：开关读的就是刚写好的那个字段）")

	# ---- 写入点：只有 3 处，且都在该在的地方 ----
	t.eq(tg.count("translate_reverse ="), 2,
		"开关函数里 2 处写入（离开平移模式归零 / 点按取反）")
	t.eq(tk.count("translate_reverse ="), 1,
		"`_think()` 哨兵段 1 处归零（禁控期间不留状态）")
	t.eq(pc_src.count("translate_reverse ="), 3,
		"整个控制器只有 3 处写入 —— 它**不是**每帧输入，读输入的两个函数里一处都没有")
	t.not_ok(tx.contains("translate_reverse") or fl.contains("translate_reverse"),
		"两个输入读取函数里都没有 `translate_reverse`（否则开关会被每帧覆盖）")
	t.eq(fb_src.count("translate_reverse ="), 0,
		"`FlightBody` 自己是**零写入**（只有 `:= false` 声明与读取）—— 单一写入点")

	# ---- 产品路径：底速真的用了那个方向 ----
	var body := _body(fb_src, "func _apply_translate")
	t.ok(body.contains("translate_base_dir(fwd, translate_reverse)"),
		"`_apply_translate()` 里用 `translate_base_dir(fwd, translate_reverse)` 算底速方向")
	t.ok(body.contains("target = base_dir * auto_speed"),
		"自动飞行底速写的是 `base_dir * auto_speed`（咬在产品那条路径上）")
	t.ok(fb_src.contains("static func translate_base_dir("),
		"`translate_base_dir()` 是**静态**函数（测试能直接调，不需要实例）")

	# ---- 说明书那一行（数据表，无绘制消费者，靠测试守）----
	var help := SuiteUiStyle._code(HELP_SRC)
	t.eq(help.count("\u53cd\u5411\u5de1\u822a\uff08\u518d\u6309\u6062\u590d\uff09"), 1,
		"操作说明里**恰好一行**印了「反向巡航（再按恢复）」—— 少了玩家不知道 CTRL 的新含义")
	t.ok(help.contains("R3\"]"),
		"那一行的手柄列写的是 R3（手柄上同一个 `hover` 动作）")



# ================================================================ ② 纯函数

static func _pure(t: T) -> void:
	# 硬编码口径（⛔ 不从 `SuitProfile` / `FlightBody` 的常量取 —— 本工程踩过
	# "目标值跟着被验常量一起变"的自证假绿）：柯西巡航 1512 = 420×1.5×2.4，
	# 加力 2268 = ×1.5，TRANSLATE_OFFSET 0.65，TRANSLATE_FWD_SCALE 0.15。
	const TOP_XI := 1512.0
	const BOOST_XI := 2268.0
	const FULL := 0.65
	const FWD := 0.15
	var off: float = TOP_XI * FULL                     # 982.8
	var f := Vector3.FORWARD

	# ---- 关着时必须**逐位**等于今天（判据 1）----
	var odd := Vector3(0.123456789, -0.987654321, 3.3333)
	var same := FlightBody.translate_base_dir(odd, false)
	t.eq(same, odd,
		"`translate_base_dir(v, false)` 逐位返回 v（%s）" % str(same))
	t.eq(same.x, odd.x, "  · x 分量逐位相同")
	t.eq(same.y, odd.y, "  · y 分量逐位相同")
	t.eq(same.z, odd.z, "  · z 分量逐位相同")
	var rev := FlightBody.translate_base_dir(f, true)
	t.eq(rev, -f, "`translate_base_dir(f, true)` = −f（倒飞 = 沿机尾）")
	t.eq(FlightBody.translate_base_dir(Vector3.ZERO, true), Vector3.ZERO,
		"零向量取反仍是零（`_apply_translate()` 有 `length_squared` 兜底，不炸）")

	# ---- 语义量化：只翻底速方向 ⇒ W/S 自动互换 ----
	#
	# W 的修正是**沿屏幕前（≈机头方向）的加法**（`translate_offset_vec` 的
	# `fwd_part` 那一份还要再打 0.15 折）⇒ 底速一反过来，W 就变成"顶住底速"=减速。
	var w_corr := FlightBody.translate_offset_vec(f, f, off)
	var s_corr := FlightBody.translate_offset_vec(-f, Vector3.ZERO, off)
	t.near(w_corr.length(), off * FWD, off * 0.001,
		"满杆 W 的修正幅度 %.2f（满权重的 15%%）—— 倒飞不改它的幅度" % w_corr.length())
	t.near(s_corr.length(), off, off * 0.001,
		"满杆 S 的修正幅度 %.2f（满权重）" % s_corr.length())
	var base_fwd := FlightBody.translate_base_dir(f, false) * BOOST_XI
	var base_rev := FlightBody.translate_base_dir(f, true) * BOOST_XI
	t.near((base_fwd + w_corr).dot(f), BOOST_XI + off * FWD, 1.0,
		"正向 + W = %.1f ⇒ **加速** %.1f m/s（与今天逐位相同）"
			% [(base_fwd + w_corr).dot(f), off * FWD])
	t.near((base_rev + w_corr).dot(f), -(BOOST_XI - off * FWD), 1.0,
		"倒飞 + W = %.1f ⇒ **减速** %.1f m/s（= 底速的 %.1f%%）"
			% [(base_rev + w_corr).dot(f), off * FWD, off * FWD / BOOST_XI * 100.0])
	t.near((base_rev + s_corr).dot(f), -(BOOST_XI + off), 1.0,
		"倒飞 + S = %.1f ⇒ **加速** %.1f m/s（= 底速的 %.1f%%）"
			% [(base_rev + s_corr).dot(f), off, off / BOOST_XI * 100.0])
	t.ok((base_rev + w_corr).dot(f) < 0.0 and (base_rev + s_corr).dot(f) < 0.0,
		"倒飞时两条都仍是**沿机尾**（没有哪一条把速度掰回正向）")
	t.lt(absf((base_rev + w_corr).dot(f)), absf(base_rev.dot(f)),
		"W 在倒飞里是**减速**：%.1f < 底速 %.1f"
			% [absf((base_rev + w_corr).dot(f)), absf(base_rev.dot(f))])
	t.gt(absf((base_rev + s_corr).dot(f)), absf(base_rev.dot(f)),
		"S 在倒飞里是**加速**：%.1f > 底速 %.1f"
			% [absf((base_rev + s_corr).dot(f)), absf(base_rev.dot(f))])
	# 正向那一侧也要**符号相反**：否则"只翻底速"这条实现可能被写成"翻修正"
	t.gt((base_fwd + w_corr).dot(f), absf(base_fwd.dot(f)),
		"正向 + W 仍是**加速**：%.1f > 底速 %.1f"
			% [(base_fwd + w_corr).dot(f), absf(base_fwd.dot(f))])
	print("        [纯函数] 底速 ±%.0f ｜ W 修正 ±%.1f（%.1f%%）｜ S 修正 ±%.1f（%.1f%%）"
		% [BOOST_XI, off * FWD, off * FWD / BOOST_XI * 100.0, off, off / BOOST_XI * 100.0])


# ================================================================ ③ 清零

static func _clear(t: T, host: Node) -> void:
	var st: Dictionary = await _stage(host, Vector3(0, LIVE_Y, 0), true)
	var pc: PlayerController = st["pc"]
	t.ok(pc.translate_mode, "前置：辅助开 + 柯西 ⇒ 进了平移模式")
	t.not_ok(pc.translate_reverse, "前置：默认**不是**倒飞（开机不许自己倒着飞）")

	pc.translate_reverse = true
	await host.get_tree().physics_frame
	t.ok(pc.translate_reverse, "摆上去之后照旧是真的（开关不是每帧输入，不会被覆盖）")

	# ---- ① 关掉辅助 ⇒ 离开平移模式 ⇒ 必须归零 ----
	pc.assist_on = false
	await host.get_tree().physics_frame
	t.not_ok(pc.translate_mode, "关辅助 ⇒ 离开平移模式")
	t.not_ok(pc.translate_reverse,
		"★ 关辅助 ⇒ `translate_reverse` 归 false（不清就会「又变回悬停」与「机体还在倒飞」同时发生）")

	# ---- ② 禁控（结算 / 暂停）⇒ 哨兵段也要归零 ----
	pc.assist_on = true
	await host.get_tree().physics_frame
	t.ok(pc.translate_mode, "再打开辅助 ⇒ 又进平移模式")
	pc.translate_reverse = true
	await host.get_tree().physics_frame
	t.ok(pc.translate_reverse, "前置：禁控之前先把状态置真")
	pc.controls_enabled = false
	await host.get_tree().physics_frame
	t.not_ok(pc.translate_reverse,
		"★ `controls_enabled = false` ⇒ `_think()` 哨兵段把倒飞一并清掉")
	pc.controls_enabled = true
	await _teardown(host, st)


# ================================================================ ④ 真机

static func _live(t: T, host: Node) -> void:
	var st: Dictionary = await _stage(host, Vector3(0, LIVE_Y, 0), true)
	var pc: PlayerController = st["pc"]
	var stage := st["c"] as Node3D

	# ---- 舞台：正前方 40 km 摆一台"靶机"（走 `face_target_override` 测试通道）----
	# 有目标时平移模式的底速方向 = 朝目标的**全 3D 机头**，机头由 `_face()` 钉住、
	# 不会自己转 ⇒ 这一段只验"速度变号"。
	# ⚠️ "无目标时会不会自旋"归 ⑤ 段 —— 两段舞台必须分开，否则 ⑤ 的负对照会把 ④ 一起判红。
	var foe := Node3D.new()
	foe.name = "ReverseFoe"
	stage.add_child(foe)
	foe.global_position = Vector3(0.0, LIVE_Y, -40000.0)
	pc.face_target_override = foe
	t.ok(pc.face_target_override == foe,
		"前置：朝向目标走的是 `face_target_override`（测试通道，优先级高于 lock）")

	# ---- 基线：正向（不改任何东西）⇒ 速度沿机头 ----
	for i in LIVE_FRAMES:
		pc.global_position = Vector3(0, LIVE_Y, 0)
		await host.get_tree().physics_frame
	var along_fwd := pc.fm.velocity.dot(pc.forward())
	var speed0 := pc.fm.velocity.length()
	t.gt(along_fwd, 0.0,
		"基线：正向飞行 `velocity · forward() = +%.1f`（速度 %.1f）" % [along_fwd, speed0])
	t.near(along_fwd, speed0, speed0 * 0.02,
		"基线：速度基本全在机头方向上（%.1f / %.1f）" % [along_fwd, speed0])

	# ---- 按一次 CTRL（= 动作 `hover`）----
	Input.action_press("hover")
	# ⚠️ 等两帧（同 `_stage()` 那条注释）：只等一帧时协程先于 `_think()` 恢复，
	# `is_action_just_pressed` 读到的是"还没按"。
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	Input.action_release("hover")
	t.ok(pc.translate_reverse, "★ 按一次 CTRL ⇒ 进入倒飞")
	var state: Dictionary = pc.assist_state()
	t.eq(bool(state.get("reverse", false)), true,
		"`assist_state()[\"reverse\"]` 同步为真（HUD 那一格读的就是它）")
	t.ok(str(pc.system_event).contains("\u53cd\u5411\u5de1\u822a"),
		"左上角提示行给了话：%s" % str(pc.system_event))

	for i in LIVE_FRAMES:
		pc.global_position = Vector3(0, LIVE_Y, 0)
		await host.get_tree().physics_frame
	var along_rev := pc.fm.velocity.dot(pc.forward())
	t.lt(along_rev, 0.0,
		"★ 倒飞：`velocity · forward() = %.1f` **变号**了（机头仍在原方向、速度反了）"
			% along_rev)
	var to_foe := (foe.global_position - pc.global_position).normalized()
	t.gt(pc.forward().dot(to_foe), 0.99,
		"★ 倒飞期间机头**仍钉在目标上**（dot = %.4f）—— 只翻速度、不翻机头"
			% pc.forward().dot(to_foe))
	t.near(absf(along_rev), pc.profile.player_boost_speed(), pc.profile.player_boost_speed() * 0.1,
		"倒飞速度 %.1f ≈ 加力极速 %.1f（自动飞行底速一个字节没削）"
			% [absf(along_rev), pc.profile.player_boost_speed()])
	print("        [真机读数] 正向 v·f = %+.1f ｜ 倒飞 v·f = %+.1f ｜ 提示 = %s"
		% [along_fwd, along_rev, str(pc.system_event)])

	# ---- 再按一次 ⇒ 复原 ----
	Input.action_press("hover")
	# ⚠️ 等两帧（同 `_stage()` 那条注释）：只等一帧时协程先于 `_think()` 恢复，
	# `is_action_just_pressed` 读到的是"还没按"。
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	Input.action_release("hover")
	t.not_ok(pc.translate_reverse, "再按一次 ⇒ 退出倒飞")
	for i in LIVE_FRAMES:
		pc.global_position = Vector3(0, LIVE_Y, 0)
		await host.get_tree().physics_frame
	var back := pc.fm.velocity.dot(pc.forward())
	t.gt(back, 0.0, "复原：`velocity · forward() = %+.1f` 又沿机头了" % back)
	t.ok(absf(back - along_fwd) < speed0 * 0.15,
		"复原后与基线同一量级（%.1f vs %.1f）" % [back, along_fwd])
	await _teardown(host, st)


# ================================================================ ⑤ 自旋守卫

## ⚠️ 本段是本轮**最容易被写漏**的一条：无锁定目标时，底速反向会让
## 「机头追速度矢量」与「底速沿机头」互相咬成**连续自旋**（每帧追一个差 180° 的方向）。
## 判据用"机头相对初始朝向转了没有"来抓 —— 自旋几十帧就会转出 90° 以上。
static func _spin(t: T, host: Node) -> void:
	var st: Dictionary = await _stage(host, Vector3(0, LIVE_Y, 0), true)
	var pc: PlayerController = st["pc"]
	for i in 20:
		pc.global_position = Vector3(0, LIVE_Y, 0)
		await host.get_tree().physics_frame
	t.ok(pc.get("face_target") == null and pc.face_target_override == null,
		"前置：无锁定目标 ⇒ 走的是「机头追速度矢量」那一支（自旋只在这里发生）")
	var f0 := pc.forward()
	pc.translate_reverse = true
	var min_dot := 1.0
	for i in 120:
		pc.global_position = Vector3(0, LIVE_Y, 0)
		await host.get_tree().physics_frame
		min_dot = minf(min_dot, pc.forward().dot(f0))
	var along := pc.fm.velocity.dot(f0)
	print("        [自旋读数] 120 帧后 机头·初始 = %.4f（角度 %.2f°）｜ v·f = %+.1f"
		% [min_dot, rad_to_deg(acos(clampf(min_dot, -1.0, 1.0))), along])
	t.gt(min_dot, 0.96,
		"★ 倒飞 120 帧机头**没有转起来**（最大偏转 %.2f° < 16°）—— 自旋坑被 `vref` 挡住了"
			% rad_to_deg(acos(clampf(min_dot, -1.0, 1.0))))
	t.lt(along, 0.0, "而且速度确实是反的（v·f = %+.1f）" % along)
	await _teardown(host, st)


# ================================================================ ⑤ HUD 位置关系

static func _hud(t: T) -> void:
	var raw := SuiteUiStyle._code(HUD_SRC)
	var body := _body(raw, "func _draw_assist_block")
	t.gt(body.length(), 500, "取到了 `_draw_assist_block()` 的函数体（%d 字符）" % body.length())

	var st_x := _const_num(raw, "ASSIST_STATE_X")
	var rv_x := _const_num(raw, "ASSIST_REVERSE_X")
	var ev_x := _const_num(raw, "ASSIST_EVENT_X")
	t.gt(st_x, 0.0, "读到 `ASSIST_STATE_X = %.1f`" % st_x)
	t.gt(rv_x, 0.0, "读到 `ASSIST_REVERSE_X = %.1f`" % rv_x)
	t.gt(ev_x, 0.0, "读到 `ASSIST_EVENT_X = %.1f`" % ev_x)
	t.lt(st_x, rv_x, "★ 位置关系：状态字(%.0f) < 倒飞格(%.0f)" % [st_x, rv_x])
	t.lt(rv_x, ev_x, "★ 位置关系：倒飞格(%.0f) < 系统提示行(%.0f) —— 挤上去就等于没画"
		% [rv_x, ev_x])
	# 画的顺序：状态字先、倒飞格后（后画的压在上面；也证明这一格长在那一行上）
	var i_state := body.find("ASSIST_STATE_X, y), state_text")
	var i_rev := body.find("\u53cd\u5411\u5de1\u822a")
	t.gt(i_state, 0, "函数体里画状态字用的是 `ASSIST_STATE_X` 常量（不是字面量 82）")
	t.gt(i_rev, i_state, "★ 倒飞格画在状态字**之后**（同一行右侧）")
	t.ok(body.contains("if rev:"), "倒飞格挂在 `rev` 上（不常驻、只在倒飞时出现）")
	t.ok(body.contains("st.get(\"reverse\", false)"),
		"`rev` 读的是 `assist_state()[\"reverse\"]`（与 PlayerController 同源）")
