extends Node
## 轮 56：巡航形态「按 WASD **不举枪**」＋「射击后**收枪**」——真机判据图（2 排 × 4 格）。
##
## ## 判据自由度 → 机位必须先算一遍
##
## 「举枪」＝ **手臂俯仰**（`UpperArm.R` 相对巡航位抬 **89.53°**），它落在**矢状面**
## （Y-Z 平面）里 ⇒ 机位必须**垂直于矢状面**，即**沿 ±X 看 = 侧视**。
## 追尾机位（沿 ±Z）与视线里的手臂俯仰**共面**，在原理上量不出它 —— 那一排只做交代。
##（轮 33 / 34 / 42 同一条规矩：**判一个自由度，机位要垂直于它**。）
##
## ## 三段式（缺一段都不算证）
##
## | 格 | 状态 | 期望 | 它在证 |
## |----|------|------|--------|
## | ① | 巡航待机 | 臂放下 | 基准（① 自拍自校准，不引任何外部姿态表） |
## | ② | 按 W · **抑制开**（生产代码） | 臂**仍贴在巡航** | ★ 用户报的 bug 治好了 |
## | ③ | 按 W · **抑制关**（负对照） | 臂**抬起来** | ★ ② 不是恒真断言 —— 因果闭合 |
## | ④ | 射击 → 滞留 → 倒放 0.40 s → 归位 | 臂 / 腿**回到巡航** | ★ 收枪真的把枪放下了 |
##
## ② 与 ③ 是**同一段方向、同一台机体、唯一变量 = 抑制那一行** ⇒ 两者之差只能归因给它。
##
## ## ③ 的「抑制关」是怎么做的（⛔ 不给生产代码加开关）
##
## 抑制那一行只在 `FlightBody._tick_model_anim()` 里。③ 不去改生产文件，而是
## **逐字复刻那 6 行调用、只把 `set_fly_dir` 的实参从 `""` 换回 `_fly_dir8()`**
## —— 与 S3 的 A/B① 是同一次改动的两种做法（那里是临时改文件，这里是临时绕一行）。
##
## ## ④ 的收枪窗口怎么快进
##
## 生产里窗口是 `FlightBody.stow_idle >= STOW_DELAY`，而 `stow_idle` 由
## `_tick_weapons()` 按 `rifle_cooldown` 累计。探针**不跑**武器 tick ⇒
## 直接写这两个公开字段即可（⛔ 不自己拍秒数、不跳过倒放那一段）。
##
## ## 跑法（**不能加 --headless**：dummy 渲染器抓出来是空的）
##   godot --path <工程> res://tools/probe_n56_cruise_aim_shot.tscn -- <输出目录>

const W := 400
const H := 470
## 侧视机位的仰角（留一点俯角，免得两臂在屏幕上完全重叠）。
const ELEV_DEG := 8.0
## 手动 tick 的固定步长：与物理帧率 60 Hz 一致 ⇒「帧数」直接就是模拟秒。
const DT := 1.0 / 60.0
## 判据链：举枪 = 这三根一起被带走（实测 `UpperArm.R` 89.53°）。
const ARM_BONES := ["UpperArm.R", "LowerArm.R", "Hand.R"]
## 用户同时要「双腿保持现状」⇒ 腿也进判据（实测被带走 25.92%）。
const LEG_BONES := ["Thigh.L", "Shin.L", "Foot.L"]
const COLS := ["1 巡航待机", "2 按W·抑开", "3 按W·抑关(负对照)", "4 开火(枪举起)", "5 收枪完成"]
## 每排 = [机位名, 说明, **取景倍率**, 焦点抬高(占包围盒高的比例), **仰角°**]。
##
## ★ 第 3 排「上半身特写」是**必须的**：判据（手臂俯仰）落在**矢状面**，
##   但在全机取景（`cam.size = 整机包围盒 × 1.25 ≈ 35`）下，柯西的整条手臂只占
##   画面里 **~120 px**，"举枪 vs 不举枪"在成品图里**肉眼判不了**
##   —— 实测把第 2 排裁出来放大到 1.9× 也没用，因为**源分辨率**就在那儿。
##   特写排按 0.38 倍收紧取景（`cam.size ≈ 13.3`）⇒ 手臂占 ~290 px。
##
## ⚠️ 特写排的仰角**故意置 0**（其余排 8°）：仰角一抬，视线就不再垂直于
##   矢状面，盾牌会插到手臂前面把它挡掉（第一版特写排实测就是这个毛病：
##   `elev = 8°` ＋ 抬高焦点 ⇒ 成了 3/4 俯视，盾牌占画面正中，手臂看不见）。
##
## ⚠️ 特写排**不能**与其它排比像素数、**不能**跨排做差分 —— 取景不同。
##   它的差分只在**排内**比（①↔② 当地板、②↔③/②↔④ 当信号），与第 2 排同理。
const ROWS := [
	["tail", "追尾机位(交代)", 1.0, 0.0, ELEV_DEG],
	["side", "侧视机位(判据)", 1.0, 0.0, ELEV_DEG],
	["close", "侧视特写·上半身(判据)", 0.38, 0.30, 0.0],
]

var out_dir := "user://n56_shot"
var _ref := {}
var _ok_all := true


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(W, H))

	_build_env()
	await get_tree().physics_frame

	FlightBody.use_placeholder = false
	var fb := await _mount(SuitProfile.xi())

	var bounds: AABB = fb.model_bounds
	var focus: Vector3 = fb.global_position \
		+ Vector3(0.0, bounds.position.y + bounds.size.y * 0.5, 0.0)
	var cam_size: float = maxf(maxf(bounds.size.x, bounds.size.y), bounds.size.z) * 1.25
	print("DIAG bounds size=(%.1f, %.1f, %.1f)  cam.size=%.2f" % [
		bounds.size.x, bounds.size.y, bounds.size.z, cam_size])

	# ---- 前置自检：这三条不成立 ⇒ 这图什么都不用看了 ----
	var skel := fb._model_skel
	if skel == null:
		print("FATAL: 没拿到骨架")
		get_tree().quit(1)
		return
	var miss: Array = []
	for b in ARM_BONES + LEG_BONES:
		if skel.find_bone(b) < 0:
			miss.append(b)
	if not miss.is_empty():
		print("FATAL: 骨架缺骨 %s" % str(miss))
		get_tree().quit(1)
		return
	if fb.model_anim == null or not fb.model_anim.has_cruise_hold():
		print("FATAL: 巡航归位段没建出来 ⇒ 收枪那格无意义")
		get_tree().quit(1)
		return
	print("DIAG 骨架骨数=%d 归位段=%s" % [skel.get_bone_count(), str(fb.model_anim.has_cruise_hold())])

	# 平移模式 ⇒ 巡航形态常驻（照抄 `fm` 的前提）。
	fb.fm.boosting = true
	fb.fm.hovering = false
	fb.control_input = Vector3.ZERO

	var shots: Array = []

	# ---- ① 巡航待机（基准）----
	#
	# ★★ 这里踩过一次「基线自己会说谎」（N55·⑤㉛ 同族）：
	#   第一版只推 90 帧就取基准，实测 `cruise_morph = 0.0370`、状态机还在
	#   **常态**（`fly`）—— 因为形态过渡要等 `form_on` 播完（0.4333 s）＋ morph 爬升，
	#   90 帧（1.5 s）**不够**。于是基准取在「常态举枪位」，后面每一格的读数
	#   全部错位（② 读出 75.80° 而不是 0°）。⇒ 必须**等稳态**，且**当场自检**。
	fb.translate_dir = Vector3.ZERO
	await _wait_cruise(fb, 8.0)
	await _settle(fb, 30)   # 归位段混合走完（`BLEND_BURST_OUT` 0.18 s）
	print("DIAG ① state=%s action='%s' morph=%.4f anim.current='%s'" % [
		fb.model_fsm.state_name(), fb.model_fsm.current_action(), fb.cruise_morph,
		fb.model_anim.current])
	_snapshot_ref(fb)
	# ★ 基线**当场再抓一次**自检：再推 15 帧，姿态必须一模一样。
	#   不一致就说明"差分基线"这件事本身不成立，后面所有读数都不用看了。
	await _settle(fb, 15)
	var drift := _gap(fb, ARM_BONES + LEG_BONES)
	_ok_all = _judge("★① 基线稳定：再推 15 帧，臂/腿漂移 %.4f° ≤ 0.01（基线本身没说谎）" % drift,
		drift <= 0.01) and _ok_all
	await _capture(fb, bounds, focus, cam_size, shots, 0)

	# ---- ② 按 W · 抑制开（生产路径）----
	fb.translate_dir = Vector3(0.0, 0.0, -1.0)
	var fd := fb._fly_dir8()
	print("DIAG ② _fly_dir8(-Z)='%s'（抑制开 ⇒ 送进状态机的是 \"\"）" % fd)
	if fd == "":
		print("FATAL: 拿不到前向名 ⇒ ② 测的是空气")
		get_tree().quit(1)
		return
	await _settle(fb, 45)
	print("DIAG ② state=%s action='%s'" % [
		fb.model_fsm.state_name(), fb.model_fsm.current_action()])
	await _capture(fb, bounds, focus, cam_size, shots, 1)

	# ---- ③ 按 W · 抑制关（负对照：逐字复刻 `_tick_model_anim()`，只放行 fly 族）----
	await _settle_ungated(fb, 45, fd)
	print("DIAG ③ state=%s action='%s'" % [
		fb.model_fsm.state_name(), fb.model_fsm.current_action()])
	await _capture(fb, bounds, focus, cam_size, shots, 2)

	# ---- 回巡航稳态（把方向族收回去，走生产路径）----
	fb.translate_dir = Vector3.ZERO
	await _wait_cruise(fb, 6.0)
	print("DIAG ④前 state=%s action='%s' morph=%.4f" % [
		fb.model_fsm.state_name(), fb.model_fsm.current_action(), fb.cruise_morph])

	# ---- ④ 开火 → 滞留（枪举着，等收枪窗）----
	#
	# ★★★ 这一格是**用户本轮真机反馈逼出来的**：他报「开枪还是没有抬手动作」。
	#   旧版探针只判了「收枪完之后回到巡航」，**从来没判过"开火时手臂抬没抬"**
	#   —— 判据覆盖不到的地方就是没验过的地方。而"最终回到巡航"这一条
	#   **与"根本没播过 shoot"完全无法区分**（两者终态一样）⇒ 是个恒真断言（T35）。
	#
	# ⚠️ 滞留期间**不写** `stow_idle`：真实游戏里 `_tick_weapons()` 因为
	#   `rifle_cooldown > 0` 把它压在 0（flight_body.gd:2865）⇒ 收枪窗不开、
	#   枪一直举着约 1.03 s。探针不跑 `_tick_weapons`，所以**只要别去写它**
	#   就复刻了那段真实状态（⛔ 不是"造一个假状态"）。
	fb.rifle_cooldown = 0.0
	fb.stow_idle = 0.0
	if not fb.play_model_action("shoot", true):
		print("FATAL: shoot 起播失败")
		get_tree().quit(1)
		return
	# ★ 逐帧轨迹：把「开火期间手臂到底抬没抬」打成**可复核的时间序列**。
	#   ⛔ 只报终态不够 —— 必须能看出"什么时候抬起来、抬了多大、什么时候放下"。
	var trace: Array = []
	var hold_frames := -1
	var peak_arm := 0.0
	for i in 240:
		fb._tick_model_anim(DT)
		await get_tree().physics_frame
		var pl: AnimationPlayer = fb.model_anim.player
		var g_arm := _gap(fb, ARM_BONES)
		var g_leg := _gap(fb, LEG_BONES)
		peak_arm = maxf(peak_arm, g_arm)
		trace.append([i, fb.model_fsm.state_name(), fb.model_fsm.current_action(),
			fb.model_anim.current, pl.current_animation_position,
			(pl.get_playing_speed() if pl.has_method("get_playing_speed") else 0.0),
			g_arm, g_leg])
		if fb.model_fsm.stow_stage() == 0:
			hold_frames = i
			break
	print("DIAG ④ 滞留达成=%s（%d 帧后）state=%s ｜ 开火窗内臂峰值 %.2f°" % [
		str(hold_frames >= 0), hold_frames, fb.model_fsm.state_name(), peak_arm])
	print("  开火窗逐帧轨迹（每 2 帧一行；arm=臂离①° leg=腿离①° pos=播放头速度）")
	print("    %-5s %-10s %-10s %-18s %-7s %-7s %-8s %s" % [
		"帧", "state", "action", "anim.current", "pos", "speed", "arm", "leg"])
	for k in trace.size():
		if k % 2 != 0 and k != trace.size() - 1:
			continue
		var r: Array = trace[k]
		print("    %-5d %-10s %-10s %-18s %-7.3f %-7.2f %-8.2f %.2f" % [
			int(r[0]), str(r[1]), str(r[2]), str(r[3]),
			float(r[4]), float(r[5]), float(r[6]), float(r[7])])
	await _capture(fb, bounds, focus, cam_size, shots, 3)

	# ---- ⑤ 开收枪窗 → 倒放 → 归位 ----
	# 生产里由 `_tick_weapons()` 累计 ⇒ 探针不跑武器 tick，直接写公开字段（等价于"冷却走完又等了 0.25 s"）。
	fb.rifle_cooldown = 0.0
	fb.stow_idle = FlightBody.STOW_DELAY
	var stow_frames := -1
	for i in 300:
		fb._tick_model_anim(DT)
		await get_tree().physics_frame
		if fb.model_fsm.state == ModelAnimFSM.State.IDLE and fb.model_fsm.stows >= 1:
			stow_frames = i
			break
	await _settle(fb, 36)   # 归位混合走完（`BLEND_BURST_OUT` 0.18 s ⇒ 留 0.6 s）
	print("DIAG ⑤ 收枪完成=%s（%d 帧）stows=%d 最终 state=%s action='%s'" % [
		str(stow_frames >= 0), stow_frames, fb.model_fsm.stows,
		fb.model_fsm.state_name(), fb.model_fsm.current_action()])
	await _capture(fb, bounds, focus, cam_size, shots, 4)

	# ================================================================ 拼图
	var cols := COLS.size()
	var rows := ROWS.size()
	var sheet := Image.create(W * cols, H * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.09, 0.10, 0.12))
	var got := 0
	for s in shots.size():
		var rec: Dictionary = shots[s]
		var img: Image = rec["img"]
		if img == null:
			continue
		got += 1
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, Vector2i(W, H)),
			Vector2i(W * int(rec["stage"]), H * int(rec["view"])))
	for ci in range(1, cols):
		sheet.fill_rect(Rect2i(W * ci, 0, 2, H * rows), Color(0.42, 0.48, 0.58))
	for ri in range(1, rows):
		sheet.fill_rect(Rect2i(0, H * ri, W * cols, 2), Color(0.42, 0.48, 0.58))

	print("\n=== N56 巡航「不举枪 / 收枪」判据（全机基准取景 cam.size=%.2f；特写排 = ×%.2f）==="
		% [cam_size, float(ROWS[2][2])])
	print("%-18s %-22s %-7s %-8s %-8s %-8s %-7s %-7s %s" % [
		"机位", "格", "覆盖%", "臂离①°", "腿离①°", "胸腹带宽", "morph", "stows", "状态/动作"])
	var by: Dictionary = {}
	for s in shots.size():
		var r: Dictionary = shots[s]
		by["%d_%d" % [int(r["view"]), int(r["stage"])]] = r
		print("%-18s %-22s %-7.2f %-8.2f %-8.2f %-8d %-7.4f %-7d %s / %s" % [
			ROWS[int(r["view"])][1], COLS[int(r["stage"])], float(r["cov"]) * 100.0,
			float(r["gap_arm"]), float(r["gap_leg"]), int(r["bandw"]), float(r["morph"]),
			int(r["stows"]), str(r["state"]), str(r["action"])])

	print("\n--- 自动判据（侧视机位;侧视垂直于「手臂俯仰」这个自由度）---")
	# ★★ 自检先行：**骨骼读数与机位无关** ⇒ 同一格的两个机位必须读出同一个数。
	#   不等 ⇒ 取图期间姿态在变。本探针**第一次跑就是这么翻车的**：
	#   5 处 `_settle()` 忘了 `await`（它们是协程）⇒ 它们与取图循环**并发**推进状态机
	#   ⇒ ③ 追尾那一格读到 0.08°（还停在巡航）、侧视读到 89.53°（已经播上 `fly_f`）。
	#   这一条把那个 bug 变成 4 条会变红的断言（skill v3.1 ㊹ 的变体）。
	#
	# ★★ 另一次变红（加特写排那轮）：腿读数 `0.00° / 0.04°`，而两个四元数逐分量
	#   只差 1e-8 ⇒ **红是量具造成的**（`angle_to()` 近单位元病态，见 `_q_angle_deg`）。
	#   改掉量具而不是放宽阈值 —— 后者会把**真的** 0.04° 变化一并放行。
	#   这条断言同时也是"量具没被换坏"的看守：③ 那格必须还能报出 89.53°。
	for st in COLS.size():
		var a0 := float(by["0_%d" % st]["gap_arm"])
		var b0 := float(by["1_%d" % st]["gap_arm"])
		var a1 := float(by["0_%d" % st]["gap_leg"])
		var b1 := float(by["1_%d" % st]["gap_leg"])
		_ok_all = _judge("★ 自检·第 %d 格两机位读到同一姿态（臂 %.2f° / %.2f°、腿 %.2f° / %.2f°）"
			% [st + 1, a0, b0, a1, b1],
			absf(a0 - b0) < 0.01 and absf(a1 - b1) < 0.01) and _ok_all
	var g2 := float(by["1_1"]["gap_arm"])
	var g3 := float(by["1_2"]["gap_arm"])
	var g4 := float(by["1_3"]["gap_arm"])
	var g5 := float(by["1_4"]["gap_arm"])
	var l2 := float(by["1_1"]["gap_leg"])
	var l3 := float(by["1_2"]["gap_leg"])
	var l4 := float(by["1_3"]["gap_leg"])
	var l5 := float(by["1_4"]["gap_leg"])
	_ok_all = _judge("★★② 按 W·抑制开 ⇒ 臂/腿**仍贴在巡航**（臂 %.2f°、腿 %.2f°，各 ≤ 2°）"
		% [g2, l2], g2 <= 2.0 and l2 <= 2.0) and _ok_all
	# ★ ③ 的阈值写成「**相对判据**（≥ 10× ②）＋ 一个地板（≥ 20°）」而不是拍一个绝对值：
	#   它唯一的职责是"证明 ② 不是恒真断言"，所以真正要钉的是"③ 和 ② 显著不同"。
	_ok_all = _judge("★★③ 按 W·抑制关（负对照）⇒ 臂**被抬起来**（%.2f° ≥ 20° 且 > ②的 %.2f° × 10；腿 %.2f° ≥ 5°）"
		% [g3, g2, l3], g3 >= 20.0 and g3 > g2 * 10.0 and l3 >= 5.0) and _ok_all
	_ok_all = _judge("③ 负对照确实播的是常态方向族（action='%s'）" % str(by["1_2"]["action"]),
		str(by["1_2"]["action"]) == "fly_f") and _ok_all
	# ★★★ ④ 这一条就是**用户实测反馈的对应判据**（原话：「开枪还是没有抬手动作」）。
	#   ⛔ 旧版这里判的是"收枪完之后回到巡航" —— 那个判据**与"根本没播过 shoot"无法区分**
	#     （两者终态逐位一样）⇒ 恒真（T35）。开火**当时**手臂抬没抬，当时就要量。
	_ok_all = _judge("★★★④ 开火 ⇒ 臂**真的抬起来**（%.2f° ≥ 20° 且 > ②的 %.2f° × 10；腿 %.2f° ≥ 5°）"
		% [g4, g2, l4], g4 >= 20.0 and g4 > g2 * 10.0 and l4 >= 5.0) and _ok_all
	_ok_all = _judge("④ 开火那一格确实在播射击动作（state='%s' action='%s'）"
		% [str(by["1_3"]["state"]), str(by["1_3"]["action"])],
		str(by["1_3"]["state"]) == "unaction" and str(by["1_3"]["action"]) == "shoot") and _ok_all
	_ok_all = _judge("★★⑤ 收枪（倒放＋归位）⇒ 臂/腿**回到巡航**（臂 %.2f°、腿 %.2f°，各 ≤ 2°；stows=%d）"
		% [g5, l5, int(by["1_4"]["stows"])], g5 <= 2.0 and l5 <= 2.0
		and int(by["1_4"]["stows"]) >= 1) and _ok_all
	# ---- 辅助：像素层面也看得出来（否则「只在数据上成立」）----
	#
	# ★ 口径 = **逐像素差分**，⛔ 不是"剪影宽/高/胸腹带宽"这类聚合量。
	#   理由：第一版用「胸腹带横向跨度」，方向**猜反了** —— 手臂垂下时它撑在身侧、
	#   抬起后并到胸前，带宽反而从 297 降到 286 px（−3.7%）。聚合量把"手臂动没动"
	#   与"躯干在哪"混在一起，**不可归因**（与 N55「量具粒度要匹配被测对象」同源）。
	#   逐像素差分直接回答用户要判的那句话：「画面上看不看得出来」。
	#
	# ★★ 噪声地板：① 与 ② 是**同一种状态**（巡航待机，唯一差别是中间按过一次 W
	#   而抑制把它挡掉了）⇒ 它俩的差分就是这台探针的**地板**，不用另开一次跑。
	var s1: Image = by["1_0"]["img"]
	var s2: Image = by["1_1"]["img"]
	var s3: Image = by["1_2"]["img"]
	var s4: Image = by["1_3"]["img"]
	var s5: Image = by["1_4"]["img"]
	var d12 := _diff_frac(s1, s2)
	var d23 := _diff_frac(s2, s3)
	var d24 := _diff_frac(s2, s4)
	var d25 := _diff_frac(s2, s5)
	print("  像素差分（侧视）：①↔②=地板 %.3f%%  ②↔③=%.3f%%  ②↔④=%.3f%%  ②↔⑤=%.3f%%"
		% [d12 * 100.0, d23 * 100.0, d24 * 100.0, d25 * 100.0])
	var floor_ok := maxf(0.002, d12 * 3.0)
	_ok_all = _judge("辅助（像素）：③ 与 ② 的侧视图有 %.3f%% 的像素不同（≥ 2%% ⇒ 肉眼看得见手臂抬起）"
		% (d23 * 100.0), d23 >= 0.02) and _ok_all
	_ok_all = _judge("辅助（像素）：④ 与 ② 明显不同（%.3f%% ≥ 2%% ⇒ 开火时画面上真的抬了枪）"
		% (d24 * 100.0), d24 >= 0.02) and _ok_all
	_ok_all = _judge("辅助（像素）：⑤ 与 ② 几乎逐像素相同（%.3f%% ≤ 地板 %.3f%% ⇒ 枪真的放下了）"
		% [d25 * 100.0, floor_ok * 100.0], d25 <= floor_ok) and _ok_all
	_ok_all = _judge("辅助（像素）：地板本身很小（①↔② = %.3f%% < 1%% ⇒ 上面几条不是被噪声淹没）"
		% (d12 * 100.0), d12 < 0.01) and _ok_all

	# ★ 特写排（第 3 排）**自成一套**差分，地板同样内建在 ①↔②。
	#   为什么另开一套：全机取景那一条回答的是"整体明显不一样"，而用户原话是
	#   **「不要举枪」/「开枪才举枪」** —— 要判的是**手臂/枪**。特写排把取景收紧到上半身，
	#   手臂差在两个状态之间就占主导 ⇒ 阈值可以钉得比全机排高（≥ 5% vs ≥ 2%）。
	#   ⛔ 绝不跨排比像素数（取景不同）。
	var c1: Image = by["2_0"]["img"]
	var c2: Image = by["2_1"]["img"]
	var c3: Image = by["2_2"]["img"]
	var c4: Image = by["2_3"]["img"]
	var c5: Image = by["2_4"]["img"]
	var e12 := _diff_frac(c1, c2)
	var e23 := _diff_frac(c2, c3)
	var e24 := _diff_frac(c2, c4)
	var e25 := _diff_frac(c2, c5)
	print("  像素差分（侧视特写·上半身）：①↔②=地板 %.3f%%  ②↔③=%.3f%%  ②↔④=%.3f%%  ②↔⑤=%.3f%%"
		% [e12 * 100.0, e23 * 100.0, e24 * 100.0, e25 * 100.0])
	var cfloor := maxf(0.002, e12 * 3.0)
	_ok_all = _judge("辅助（像素·特写）：③ 与 ② 有 %.3f%% 的像素不同（≥ 5%% ⇒ 手臂/枪的位置肉眼就看得见）"
		% (e23 * 100.0), e23 >= 0.05) and _ok_all
	_ok_all = _judge("辅助（像素·特写）：④ 与 ② 有 %.3f%% 的像素不同（≥ 5%% ⇒ **开火时枪真的抬起来了**）"
		% (e24 * 100.0), e24 >= 0.05) and _ok_all
	_ok_all = _judge("辅助（像素·特写）：⑤ 与 ② 几乎逐像素相同（%.3f%% ≤ 地板 %.3f%% ⇒ 收枪收干净了）"
		% [e25 * 100.0, cfloor * 100.0], e25 <= cfloor) and _ok_all
	print("  追尾机位（只做交代，不判）：①②③ 高 %.0f / %.0f / %.0f px"
		% [float(by["0_0"]["bh"]), float(by["0_1"]["bh"]), float(by["0_2"]["bh"])])

	var out := out_dir.path_join("n56_cruise_aim_cmp.png")
	print("\nSHOT %s err=%d  拍到 %d 格  ALL_OK=%s" % [out, sheet.save_png(out), got, _ok_all])
	print("  排 1 = 追尾(交代) · 排 2 = 侧视(判据·全机) · 排 3 = 侧视特写·上半身(判据)；"
		+ "列 = ① 巡航待机 ② 按W·抑开 ③ 按W·抑关 ④ 开火(枪举起) ⑤ 收枪完成")
	print("N56_SHOT_DONE -> ", out_dir)
	get_tree().quit(0 if (got > 0 and _ok_all) else 1)


# ================================================================ 读数

## 把 6 根关键骨的**局部旋转**记成基准（① 巡航待机调用一次）。
## 自校准：不引任何外部姿态表 ⇒ 与"焊缝取 `form_on` 末帧"这条约定互不依赖。
func _snapshot_ref(fb: FlightBody) -> void:
	_ref.clear()
	var skel := fb._model_skel
	if skel == null:
		return
	for b in ARM_BONES + LEG_BONES:
		var bi := skel.find_bone(b)
		if bi >= 0:
			_ref[b] = skel.get_bone_pose_rotation(bi)


func _gap(fb: FlightBody, bones: Array) -> float:
	if _ref.is_empty():
		return -1.0
	var skel := fb._model_skel
	if skel == null:
		return -1.0
	var mx := 0.0
	for b: String in bones:
		var bi := skel.find_bone(b)
		if bi < 0 or not _ref.has(b):
			continue
		mx = maxf(mx, _q_angle_deg(skel.get_bone_pose_rotation(bi), _ref[b] as Quaternion))
	return mx


## 两个四元数之间的夹角（度）。**既精确又低噪声**的版本，专门给「判有没有变」用。
##
## ★★★ 这个函数是**对拍出来的**（`_relay/_n56_angle_metric_cmp.py`），不是推出来的。
##   三个候选在「绕同轴 90°、起点相位 45°」与「逐分量扰动 1e-7」两组用例下：
##
##   | 量具 | 大角 90° 真值 | 噪声地板 |
##   |---|---|---|
##   | A `2·acos(\|dot\|)`（= `Quaternion.angle_to()`）| **90.000** 精确 | **0.026°** 大 |
##   | B `2·asin(max\|Δc\|)`（我一度换上的）| **65.530** ❌ 低估 27% | 0.000011° |
##   | **C `4·asin(‖a−b‖/2)`（本函数）** | **90.000** 精确 | **0.000020°** |
##
##   ★ A 的问题：`acos(1−ε) ≈ √(2ε)` 把误差**开平方根** ⇒ pose 四元数的 float32
##     模长缺陷(~2e-7) 被放大成 **0.026°** 的假夹角
##     ⇒ 实测「两机位读到同一姿态」在腿上报 `0.00° / 0.04°` 而逐分量只差 1e-8。
##   ★ B 的问题：`max|Δc| = sin(θ/2)` **只在"起点与终点同轴"时成立**；一般情形
##     `max|Δc| = 2·sin(θ/4)·max(|cos ψ|,|sin ψ|)`，ψ = 相位 ⇒ 最坏低估到 `θ/√2`
##     （实测 90° 读成 65.53°）。我当时只验了"轴对齐"那一个特例就换上了
##     —— ⛔ **改量具不能只用一组用例验**。
##   ★ C 的正确性：`‖a−b‖² = 2−2·dot`，翻正到 `dot = cos(θ/2)` 后
##     `‖a−b‖² = 4·sin²(θ/4)` ⇒ `θ = 4·asin(‖a−b‖/2)`，对任意相位**逐点精确**；
##     而小角度下 `θ ≈ 2‖a−b‖` 是**线性**的，不放大 float32 噪声。
##
##   ⚠️ 换量具会让**历史读数全部失效**：本次 ③ 那格从 `89.53°` 变成过 `57.38°`
##     （B 的低估）—— 差 32° 会让人误判"抑制没生效"。**量具错了，读数全是假的。**
static func _q_angle_deg(a: Quaternion, b: Quaternion) -> float:
	var q := b
	# 双覆盖：`q` 与 `−q` 是同一次旋转 ⇒ 先翻到 `dot ≥ 0` 那一支，`‖a−b‖²` 才是 `4 sin²(θ/4)`。
	if a.dot(b) < 0.0:
		q = -b
	return rad_to_deg(4.0 * asin(clampf((a - q).length() * 0.5, 0.0, 1.0)))


func _judge(label: String, cond: bool) -> bool:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	return cond


# ================================================================ 工具

## ★ 负对照：逐字复刻 `FlightBody._tick_model_anim()` 的 6 行调用，
## **唯一差别**是 `set_fly_dir` 的实参 —— 生产代码送 `""`（抑制），这里送真实方向名。
## ⛔ 不碰生产文件、不加开关：要测的就是"那一行到底管不管用"。
func _step_ungated(fb: FlightBody, fd: String) -> void:
	fb.model_fsm.set_form(fb.in_cruise_form())
	fb.model_fsm.set_dash(fb._dash_anim_dir)
	fb.model_fsm.set_fly_dir(fd)
	fb.model_fsm.set_turn(fb._turn_dir())
	fb.model_fsm.set_can_stow(fb.in_cruise_form() and fb.stow_idle >= FlightBody.STOW_DELAY)
	fb.model_fsm.tick(DT)


func _settle_ungated(fb: FlightBody, n: int, fd: String) -> void:
	for i in n:
		fb._tick_cruise_morph(DT)
		_step_ungated(fb, fd)
		await get_tree().physics_frame


func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.60, 0.63, 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.84, 0.87, 0.94)
	env.ambient_light_energy = 1.20
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, 20.0, 0.0)
	key.light_energy = 1.8
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10.0, 200.0, 0.0)
	fill.light_energy = 0.6
	fill.light_color = Color(0.74, 0.84, 1.0)
	add_child(fill)


## 摆一台**真的** FlightBody（走 `_build_visual()`，model_root / 骨架 / 动画都在链上）。
##
## ⚠️ 三个必踩的坑（抄自 `dash_stow_shot.gd` / `form_weld_shot.gd` 的现场记录）：
##   · 机体不能摆 y=0 —— `CRASH_ALTITUDE` 会在第一个物理帧判"撞海"并 `destroy()`
##     （症状是满屏爆炸花瓣、`--shots` 却一切正常）；
##   · `set_physics_process(false)` 要在 `add_child` **之后**立刻设；
##   · `_hover_pose` 初值是 0，不显式补这一下，拍到的是"竖直站立"。
func _mount(p: SuitProfile) -> FlightBody:
	var holder := Node3D.new()
	add_child(holder)
	var fb := FlightBody.new()
	fb.team = 0
	fb.profile = p
	holder.add_child(fb)
	fb.global_transform = Transform3D(Basis(), Vector3(0.0, 3000.0, 0.0))
	fb.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame
	fb._hover_pose = fb.flight_pitch_deg
	return fb


## 推进 `n` 个固定步长的"逻辑帧"（不依赖真实帧率 ⇒ 轨迹可复现）。
func _settle(fb: FlightBody, n: int) -> void:
	for i in n:
		fb._tick_cruise_morph(DT)
		fb._tick_model_anim(DT)
		await get_tree().physics_frame


## 一直推到「巡航稳态 ＋ 归位段在跑」为止（或耗尽 `max_sec` 模拟秒）。
##
## ⚠️ **不能只推固定帧数**：形态过渡是 `form_on`（0.4333 s）＋ morph 爬升两段，
##   实测推 90 帧（1.5 s）时 `cruise_morph` 还只有 **0.037**、状态机还在常态（`fly`）
##   ⇒ 基准会取在「常态举枪位」上，后面每一格全部错位
##（第一次跑：② 读出 75.80° 而不是 0°）。这是 N55·⑤㉛「基线必须当场自检」的同族坑。
func _wait_cruise(fb: FlightBody, max_sec: float) -> void:
	var budget := int(round(max_sec * 60.0))
	for i in budget:
		if fb.cruise_morph >= 0.999 and fb.model_fsm != null \
				and fb.model_fsm.state == ModelAnimFSM.State.IDLE \
				and fb.model_anim != null \
				and fb.model_anim.current == str(ModelAnimator.CRUISE_HOLD_CLIP):
			return
		fb._tick_cruise_morph(DT)
		fb._tick_model_anim(DT)
		await get_tree().physics_frame
	print("WARN: _wait_cruise 超时（morph=%.4f state=%s current='%s'）" % [
		fb.cruise_morph, fb.model_fsm.state_name(), fb.model_anim.current])


## 同一台机体、同一时刻、逐排取图。同一排内**共用** `focus` 与 `cam_size`
## ⇒ 排内的格与格之间尺寸可直接相减，"变窄/变矮"不可能是取景变了。
## ⛔ 跨排不可比（第 3 排是特写，见 `ROWS` 的说明）。
func _capture(fb: FlightBody, bounds: AABB, focus: Vector3, cam_size: float,
		shots: Array, stage: int) -> void:
	for ri in ROWS.size():
		var v: String = ROWS[ri][0]
		var rc := _row_cam(ri, bounds, focus, cam_size)
		var img := await _shoot(fb, v, rc[0], rc[1], rc[2])
		var rec := {
			"view": ri, "stage": stage, "img": img,
			"bw": 0, "bh": 0, "cov": 0.0, "bandw": 0,
			"morph": fb.cruise_morph,
			"stows": (fb.model_fsm.stows if fb.model_fsm != null else -1),
			"state": (fb.model_fsm.state_name() if fb.model_fsm != null else "?"),
			"action": (fb.model_fsm.current_action() if fb.model_fsm != null else "?"),
			"gap_arm": _gap(fb, ARM_BONES),
			"gap_leg": _gap(fb, LEG_BONES),
		}
		if img != null:
			var box := _bbox_of_subject(img)
			rec["bw"] = box[0]
			rec["bh"] = box[1]
			rec["cov"] = box[2]
			rec["bandw"] = _band_width(img, 0.35, 0.75)
			_draw_text(img, 12, H - 16, str(int(box[0])))
		shots.append(rec)


## 第 `ri` 排自己的 `[焦点, cam.size, 仰角°]`。**每排一个取景**，同一排内保持一致
## ⇒ 排内可差分、排间不可比（见 `ROWS` 的长说明）。
func _row_cam(ri: int, bounds: AABB, focus: Vector3, cam_size: float) -> Array:
	var zoom := float(ROWS[ri][2])
	var lift := float(ROWS[ri][3])
	var elev := float(ROWS[ri][4])
	var f: Vector3 = focus + Vector3(0.0, bounds.size.y * lift, 0.0)
	return [f, cam_size * zoom, elev]


## 拍一张。`view` = **`"tail"`**（追尾，+Z 侧）；**其余一律按侧视**（+X 侧）。
##
## ⚠️ 这里踩过一次：第一版写成 `if view == "side": … else: 追尾`，
##   而特写排的机位名是 **`"close"`** ⇒ 它掉进 `else` 被当成**追尾**拍了，
##   于是"上半身特写"整排是**前视图** —— 而前视**垂直于**"手臂前伸"这个自由度
##   （手臂朝镜头伸，投影长度几乎不变）⇒ 那一排的差分虽然还很大（盾 / 翼在动），
##   但它**不构成"手臂抬起来了"的证据**。
##   ⇒ 判据必须**默认**走严格的那个分支：只对 `"tail"` 特判，别的都当侧视。
func _shoot(fb: FlightBody, view: String, focus: Vector3, cam_size: float,
		elev_deg: float) -> Image:
	var d := maxf(cam_size, 1.0) * 2.2
	var el := deg_to_rad(elev_deg)
	var off: Vector3
	if view == "tail":
		off = Vector3(0.0, sin(el), cos(el)) * d
	else:
		off = Vector3(cos(el), sin(el), 0.0) * d

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = cam_size
	cam.near = 0.05
	cam.far = 9000.0
	add_child(cam)
	cam.global_position = focus + off
	cam.transform = cam.transform.looking_at(focus, Vector3.UP)
	cam.current = true
	for f in 3:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	cam.queue_free()
	await get_tree().physics_frame
	if img == null:
		return null
	img.convert(Image.FORMAT_RGBA8)
	# ⚠️ 必须缩放再贴：`window_set_size()` 在 Windows 上会被系统 DPI 顶掉。
	img.resize(W, H, Image.INTERPOLATE_LANCZOS)
	return img


## 主体（非背景）像素的包围盒宽 / 高 / 覆盖率。背景是**纯色**（无天空、无阴影）
## ⇒ 通道绝对差之和 > 0.06 就足够干净。⛔ 别用"亮度"当判据（机体上有比背景更暗的深蓝）。
func _bbox_of_subject(img: Image) -> Array:
	var bg := Vector3(0.60, 0.63, 0.68)
	var x0 := 1 << 30
	var y0 := 1 << 30
	var x1 := -1
	var y1 := -1
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var dd := absf(c.r - bg.x) + absf(c.g - bg.y) + absf(c.b - bg.z)
			if dd > 0.06:
				n += 1
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return [0, 0, 0.0]
	return [x1 - x0 + 1, y1 - y0 + 1,
			float(n) / float(img.get_width() * img.get_height())]


## 只统计**一条横带**（`y0f`..`y1f` 是高度的分数）里非背景像素的横向跨度。
##
## ⚠️ **只作交代，不作判据**：实测这一轮的结论与直觉相反（手臂抬起后带宽
## 297 → 286 px，因为垂下时它撑在身侧、抬起后并到胸前）⇒ 聚合量不可归因，
## 判"看不看得出来"要用 `_diff_frac()` 的逐像素差分。
func _band_width(img: Image, y0f: float, y1f: float) -> int:
	var bg := Vector3(0.60, 0.63, 0.68)
	var y0 := clampi(int(float(img.get_height()) * y0f), 0, img.get_height() - 1)
	var y1 := clampi(int(float(img.get_height()) * y1f), y0, img.get_height() - 1)
	var x0 := 1 << 30
	var x1 := -1
	for y in range(y0, y1 + 1):
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var dd := absf(c.r - bg.x) + absf(c.g - bg.y) + absf(c.b - bg.z)
			if dd > 0.06:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
	return 0 if x1 < 0 else (x1 - x0 + 1)


## 两张图**逐像素**不同的比例（通道绝对差之和 > 0.06 视为"变了"）。
##
## 这是回答"画面上看不看得出来"最直接的一把尺子 —— 它不含任何关于"该往哪变"的假设
##（`_band_width()` 那种聚合量就栽在这个假设上）。
func _diff_frac(a: Image, b: Image) -> float:
	if a == null or b == null:
		return -1.0
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06:
				n += 1
	return float(n) / float(a.get_width() * a.get_height())


## 极简 5×7 点阵（数字 + 负号，工具自包含、不引字体资源）。
func _draw_text(img: Image, x: int, y: int, text: String) -> void:
	var glyphs := {
		"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
		"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
		"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
		"3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
		"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
		"5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
		"6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
		"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
		"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
		"9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
		"－": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	}
	var cx := x
	for ch in text:
		var rows: Array = glyphs.get(ch, glyphs["0"])
		for ry in rows.size():
			var row: String = rows[ry]
			for rx in row.length():
				if row[rx] == "1":
					img.set_pixel(cx + rx, y + ry, Color(1.0, 0.85, 0.35))
		cx += 7
