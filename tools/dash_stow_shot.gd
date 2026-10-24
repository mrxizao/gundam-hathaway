extends Node
## 轮 34：**左右转身期间形态收起再展开** —— 真机判据图（2 排 × 4 格）。
##
## ## 出图布局
##   排 1：**追尾机位**（玩家看到的那一面）
##   排 2：**俯视机位**（看翼展最直观）
##   四列 = **同一条时间线上的四个阶段**：
##     ① 巡航态（翼展开）   ② 转身窗口内·已收起（飞行态）
##     ③ 转身窗口刚走完·展开中   ④ 展开完成（回到巡航态）
##
## ★ **八格来自同一台机体、同一条时间线** —— 不是八次独立摆拍。
##   所以"第 2 格比第 1 格窄"只可能是形态真的收了，不可能是取景变化。
##
## ## 读法（自洽判据，不用我解释）
##   · **判据看排 2（俯视）**：
##       ① 与 ④ 几乎一样（都回到巡航态，投影面积 17.69% / 17.69%）；
##       ② 的投影面积明显变小（**17.69% → 10.24%，−42%**，前后向 416 → 342 px
##          —— 飞行翼沿机身轴收起、肩甲收拢，剪影变"瘦"）；
##       ③ 是 `form_on` 的中间姿态（进度 0.28）。⚠️ 它**不是**"介于 ② 与 ④ 之间"：
##          实测面积 18.56%、前后向 468 px，**比两个端点都大** ——
##          翼板绕枢轴**扫**过来时会甩到比任一稳定姿态都靠外。见下方自动判据的注释。
##   · 排 1（追尾）是**玩家实际视角长什么样**的交代，不是判据：它的包围盒几乎不动
##     （宽 163 / 190 / 171 / 163 px）。原因：形态差主要落在
##     "翼板沿机身轴展开 ⇄ 收起"这个自由度上，追尾机位对它不敏感。
##     ⇒ 与轮 33 同源的那条规矩：**判一个几何自由度，机位必须垂直于它。**
##   · 每格左下打印该格**非背景像素的包围盒宽度**（像素）—— 判据可复算。
##
## ## 为什么"不转身"
##   本图要量的是**翼展**。若同时把机体转到 90°，翼展在屏幕上的投影会跟着变，
##   量出来的宽度就同时含"转了多少"和"收了多少"两个因素 —— 不可归因。
##   转身本身见轮 33 的 `84_冲刺转身_追尾机位_玩家视角.png` / `85_…机头扫一圈.png`；
##   两者可叠加（转身写在 `spin_pivot` 节点上、形态写在骨骼姿态上，互不干涉）。
##
## ## 为什么手动 tick 而不是真跑一次冲刺
##   真跑冲刺机体以 ~3500 m/s 位移，几个物理帧就飞出取景框。
##   这里调的是 `_tick_effects()` **内部那两个函数、同一个顺序**
##  （`_tick_cruise_morph` → `_tick_model_anim`），只是不跑与本图无关的视觉 tick
##  （拖尾 / 尾焰 / 闪光）—— 免得粒子污染"非背景像素"的测量。
##
## ## 跑法（**不能加 --headless**：dummy 渲染器抓出来是空的）
##   godot --path <工程> res://tools/dash_stow_shot.tscn -- <输出目录>

const W := 400
const H := 470
## 追尾机位的仰角（与轮 33 的判据图同一档，便于对照）。
const TAIL_ELEV_DEG := 12.0
## 手动 tick 的固定步长：与物理帧率 60 Hz 一致，于是"帧数"直接就是时间。
const DT := 1.0 / 60.0
## 四列的阶段名（只用于日志表，图上用数字）。
const STAGES := ["1 巡航态", "2 转身中·已收起", "3 展开中", "4 展开完成"]
## 两排：[机位名, 中文名]
const ROWS := [["tail", "追尾机位"], ["top", "俯视机位"]]

var out_dir := "user://dash_stow"
var _dt_used := DT


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(W, H))

	_build_env()
	await get_tree().physics_frame

	# `use_placeholder` 是 static：显式写死，保证摆的是真模型。
	FlightBody.use_placeholder = false
	var fb := await _mount(SuitProfile.xi())

	# ---- 取景：整个序列**共用**一套（焦点与 cam.size 都定死）----
	# 若按每格自己的包围盒取景，"收窄"与"被缩小"就分不出来（轮 33 踩过）。
	var bounds: AABB = fb.model_bounds
	var focus: Vector3 = fb.global_position \
		+ Vector3(0.0, bounds.position.y + bounds.size.y * 0.5, 0.0)
	# ⚠️ 取三轴最大值再放 1.25 倍：机体在巡航态翼展接近静态包围盒的**上限**，
	# 只按 `size.y` 取景会把翼尖裁掉（裁掉就把"宽"量小了 —— 恰好抵消要证的结论）。
	var cam_size: float = maxf(maxf(bounds.size.x, bounds.size.y), bounds.size.z) * 1.25
	print("DIAG bounds size=(%.1f, %.1f, %.1f)  共用 cam.size=%.2f" % [
		bounds.size.x, bounds.size.y, bounds.size.z, cam_size])

	# ---- 诊断：形态载体是哪一条（决定"看得见"靠谁）----
	print("DIAG cruise_morph=%.4f  _form_curve=%s  _cruise_form=%s" % [
		fb.cruise_morph,
		"yes" if fb._form_curve != null else "null",
		"yes" if fb._cruise_form != null else "null"])
	if fb.model_anim != null:
		print("DIAG anim.ready=%s idle=%s idle_cruise=%s(has=%s) form_on=%s(has=%s)" % [
			fb.model_anim.ready, fb.model_anim.idle_action,
			fb.model_anim.idle_cruise_action,
			fb.model_anim.has(fb.model_anim.idle_cruise_action),
			fb.model_anim.form_on_action,
			fb.model_anim.has(fb.model_anim.form_on_action)])

	# ================================================================ 时间线
	# 平移模式下 `fm.boosting` 恒 true（`_read_translate_input()` 末尾写死）
	# ⇒ 巡航态是常驻的。这里照抄那个前提。
	fb.fm.boosting = true
	fb.fm.hovering = false

	var shots: Array = []          # [{view, stage, img, w, h, cov, action}]
	## ③ 捕获时 `form_on` 的实际播放进度（−1 = 没抓到）。
	var mid_progress := -1.0

	# ---- ① 巡航态：先让形态稳到 1 ----
	_settle(fb, 60)
	await _wait_action(fb, "cruise_idle", 2.0)
	await _wait_seconds(fb, 0.30)  # ⚠️ 让交叉淡入**落定**（见 `_wait_seconds` 的说明）
	await _capture(fb, focus, cam_size, shots, 0)

	# ---- ② 进入转身窗口：收起 ----
	fb._dash_spin_t = FlightBody.QB_TIME
	_settle(fb, 12)                # 0.20 s > DASH_SPIN_STOW_SECONDS 0.15 ⇒ 必已收到 0
	await _wait_action(fb, "fly", 2.0)
	await _wait_seconds(fb, 0.40)  # 收起那一下也要落定（交叉淡入 0.18 s / `form_off` 播完）
	await _capture(fb, focus, cam_size, shots, 1)

	# ---- ③ 窗口走完 → 展开中（截在 `form_on` 的前段）----
	fb._dash_spin_t = 0.0
	# ⚠️ 不能只等固定帧数：`morph` 越过 0.5 之后状态机才去播 `form_on`，
	#    而 `form_on` 本身 0.4333 s。这里**直接读状态机自己的 `progress()`** 等它播到指定比例
	#    —— 那个量就是要展示的东西，与实时帧率无关（按秒数等就是赌帧率是 60）。
	#
	# ⚠️ 取样点取 **0.25 而不是 0.50**：`form_on` 的翼展曲线是**前快后慢**（ease-out），
	#    实测播到 0.526 时翼展已回到 17.80%（≈ 终态 17.69%）—— 那一格看图"已经展开完了"，
	#    拿它当"展开中"是自欺。0.25 才落在"确实收着、正在张"的区间。
	mid_progress = await _wait_form_mid(fb, 0.25, 900)
	await _capture(fb, focus, cam_size, shots, 2)

	# ---- ④ 展开完成 ----
	await _wait_action(fb, "cruise_idle", 3.0)
	await _wait_seconds(fb, 0.30)
	await _capture(fb, focus, cam_size, shots, 3)

	# ================================================================ 拼图
	var cols := STAGES.size()
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

	# ---- 打印证据表（两个机位分开，因为两者的敏感度差别很大）----
	print("\n=== 形态收起判据（非背景像素；取景全程共用 cam.size=%.2f）===" % cam_size)
	print("%-8s %-18s %-6s %-6s %-8s %-8s %s" % [
		"机位", "阶段", "宽", "高", "覆盖%", "morph", "当时在播的动作"])
	var by: Dictionary = {}
	for s in shots.size():
		var r: Dictionary = shots[s]
		by["%d_%d" % [int(r["view"]), int(r["stage"])]] = r
		print("%-8s %-18s %-6d %-6d %-8.2f %-8.4f %s" % [
			ROWS[int(r["view"])][1], STAGES[int(r["stage"])], int(r["bw"]), int(r["bh"]),
			float(r["cov"]) * 100.0, float(r["morph"]), str(r["action"])])

	# ---- 自动判据（出图脚本自己先判一遍，别让人肉看图）----
	#
	# ★ 判据**只取俯视那一排**（view=1）。实测两排的敏感度差 10 倍以上：
	#   俯视的投影面积 17.69% → 10.45%（−41%）；而追尾机位的包围盒宽 163/163/169/163 px（±4%）。
	#   原因：形态差主要落在"翼板朝后展开 ⇄ 朝前收起"这个自由度上，它在**俯视投影**
	#   里最敏感（沿机身轴方向），在追尾视角里几乎只是厚度变化。
	#   ⇒ 追尾那一排是"玩家视角长什么样"的交代，**不是**判据。
	#   这与轮 33 的教训同源：判一个几何自由度，机位必须**垂直于**那个自由度。
	# ---- 诊断：状态机的迁移轨迹（比"某时刻在播什么"更强 —— 它是**顺序**证据）----
	if fb.model_fsm != null:
		print("\nDIAG ③ 捕获时 form_on 进度=%.3f | 状态机累计迁移=%d"
			% [mid_progress, fb.model_fsm.transitions])
		print("DIAG 状态机历史（尾部）: %s" % str(fb.model_fsm.history()))

	print("\n--- 自动判据（俯视机位）---")
	var ok_all := true
	var c1 := float(by["1_0"]["cov"])
	var c2 := float(by["1_1"]["cov"])
	var c3 := float(by["1_2"]["cov"])
	var c4 := float(by["1_3"]["cov"])
	var h1 := float(by["1_0"]["bh"])
	var h2 := float(by["1_1"]["bh"])
	ok_all = _judge("② 收起后投影面积明显变小（%.2f%% < %.2f%% × 0.80）"
		% [c2 * 100.0, c1 * 100.0], c2 < c1 * 0.80) and ok_all
	ok_all = _judge("② 机身前后向长度也变短（%.0f px < %.0f px × 0.90）" % [h2, h1],
		h2 < h1 * 0.90) and ok_all
	ok_all = _judge("③ 截到的是过渡前段（form_on 进度 %.2f ∈ [0.25, 1.00)）" % mid_progress,
		mid_progress >= 0.25 and mid_progress < 1.0) and ok_all
	# ---- 判据：③ "展开中"----
	#
	# ⚠️ **不要写成"③ 介于 ② 与 ④ 之间"** —— 这是个看起来对、实际错的判据。
	#    实测：`form_on` 播到 28% 时俯视面积 **18.57%**、前后向 **468 px**，
	#    比两个**端点都大**（② 10.23% / 342 px，④ 17.69% / 416 px）。
	#    原因：翼板是绕枢轴**扫**过来的，中途会甩到比任一稳定姿态都靠外的位置
	#    ⇒ **过渡中间态不服从端点的单调性**，用"夹在中间"去判它必然误判。
	#    （与轮 33 那条同源：判一个量，先确认它在被判的区间里真的单调/敏感。）
	#
	#    改成两条真正表达"离开了起点、又没到终点"的判据：
	#      ① 已显著大于收起态（张开已经开始）；
	#      ② 与终态的差异超出测量噪声（还没到终态）。
	ok_all = _judge("③ 已离开收起态（%.2f%% > %.2f%% × 1.15）" % [c3 * 100.0, c2 * 100.0],
		c3 > c2 * 1.15) and ok_all
	ok_all = _judge("③ 尚未到终态（|%.2f%%−%.2f%%| = %.2f%% > 2%% 相对差）"
		% [c3 * 100.0, c1 * 100.0, absf(c3 - c1) / c1 * 100.0],
		absf(c3 - c1) > c1 * 0.02) and ok_all
	ok_all = _judge("④ 展开完成回到①（|%.2f%%−%.2f%%| ≤ ①的 5%%）" % [c4 * 100.0, c1 * 100.0],
		absf(c4 - c1) <= c1 * 0.05) and ok_all
	ok_all = _judge("morph 走完 1 → 0 → 1（%.4f / %.4f / %.4f）" % [
		float(by["1_0"]["morph"]), float(by["1_1"]["morph"]), float(by["1_3"]["morph"])],
		float(by["1_0"]["morph"]) > 0.99 and float(by["1_1"]["morph"]) < 0.01
			and float(by["1_3"]["morph"]) > 0.99) and ok_all
	# 追尾机位自洽性：① 与 ④ 是同一个形态、隔了一秒多，必须长得一样。
	ok_all = _judge("追尾机位 ①④ 一致（宽 %.0f vs %.0f px）" % [
		float(by["0_0"]["bw"]), float(by["0_3"]["bw"])],
		int(by["0_0"]["bw"]) == int(by["0_3"]["bw"])) and ok_all

	var out := out_dir.path_join("dash_stow_cmp.png")
	print("\nSHOT %s err=%d  拍到 %d 格  ALL_OK=%s" % [out, sheet.save_png(out), got, ok_all])
	print("  排 1 = 追尾机位 · 排 2 = 俯视机位；列 = ① 巡航态 ② 转身中·已收起 ③ 展开中 ④ 展开完成")
	print("DASH_STOW_SHOT_DONE -> ", out_dir)
	get_tree().quit(0 if (got > 0 and ok_all) else 1)


func _judge(label: String, cond: bool) -> bool:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	return cond


# ================================================================ 工具

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


## 摆一台**真的** FlightBody（走 `_build_visual()`，`model_root` / 骨架 / 动画都在链上）。
##
## ⚠️ 三个必踩的坑（抄自 `suit_orient_shot.gd` / `dash_spin_shot.gd` 的现场记录）：
##   · 机体不能摆 y=0 —— `CRASH_ALTITUDE` 会在第一个物理帧判"撞海"并 `destroy()`；
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


## 推进 `n` 个固定步长的"逻辑帧"（不依赖真实帧率，所以形态轨迹可复现）。
##
## 调的是 `_tick_effects()` 内部那两个函数、同一个顺序。
func _settle(fb: FlightBody, n: int) -> void:
	for i in n:
		fb._tick_cruise_morph(DT)
		fb._tick_model_anim(DT)
		await get_tree().physics_frame


## 继续推进形态/状态机，直到状态机的当前动作变成 `want`（或超过 `max_sec` 的**模拟秒**）。
##
## ⚠️ **预算按迭代数算，不按 `get_process_delta_time()` 累加。**
##   实测踩坑：用真实 delta 累加时，"2.0 s" 的预算在十几次迭代内就被耗尽
##   （窗口模式下 process delta 远大于 1/60），于是**循环在还没走到 `form_on` 之前就退出了**
##   —— 表现是"等不到目标动作，捕获时已是终态"。
##   改成"一次迭代 = 一个 `DT`"之后，预算就是**模拟秒**，与 `_settle()` 的时钟严格一致。
func _wait_action(fb: FlightBody, want: String, max_sec: float) -> void:
	var budget := int(round(max_sec * 60.0))
	for i in budget:
		if fb.model_fsm != null and fb.model_fsm.current_action() == want:
			return
		fb._tick_cruise_morph(DT)
		fb._tick_model_anim(DT)
		await get_tree().physics_frame


## 再等 `sec` 秒**模拟时间**（= `sec × 60` 次迭代），期间照常推形态与状态机。
##
## ⚠️ **这一步不能省**：`current_action()` 是在 `_enter_idle()` 里**立刻**改的，
## 而这时交叉淡入（`BLEND_FORM` 0.18 s）才刚开始 —— 此刻截图会拍到
## **两个姿态的混合中间帧**。实测踩过：同一格两次运行分别量到 163 px 与 189 px，
## 差异全部来自"截在淡入的哪一帧"。等到淡入落定，读数才是可复现的。
func _wait_seconds(fb: FlightBody, sec: float) -> void:
	var budget := int(round(sec * 60.0))
	for i in budget:
		fb._tick_cruise_morph(DT)
		fb._tick_model_anim(DT)
		await get_tree().physics_frame


## 等**形态过渡动作**播到 `target`（0..1）附近，返回实际捕获到的进度（超时返回 −1）。
##
## ## 为什么不按"等固定秒数"
##
## `form_on` 的播放头是**引擎实时**推进的（`AnimationPlayer` 不认我们的 `DT`），
## 而形态/状态机是我们**逐迭代**推的 —— 两个时钟不同源。
## 按固定秒数等，等于赌"实时帧率正好是 60"；赌错就截在过渡的开头或末尾。
##
## 直接读状态机自己的 `progress()`（= `anim.progress()`）就没这个问题：
## **它就是要展示的那个量**，拿到 0.5 就是"展开到一半"，与帧率无关。
##
## ⚠️ 必须先确认 `state_name() == "form"` 再读 `progress()`：
## 非 FORM 态下 `progress()` 返回的是**上一个循环动作**的进度，会立刻误判成命中。
func _wait_form_mid(fb: FlightBody, target: float, max_frames: int) -> float:
	var seen_form := false
	for i in max_frames:
		var fsm := fb.model_fsm
		if fsm != null and fsm.state_name() == "form":
			seen_form = true
			if fsm.progress() >= target:
				return fsm.progress()
		elif seen_form:
			# 过渡已经播完 ⇒ 本次来不及截，如实返回 −1（判据会报出来，不静默）。
			return -1.0
		fb._tick_cruise_morph(DT)
		fb._tick_model_anim(DT)
		await get_tree().physics_frame
	return -1.0


## 拍两张（同一台机体、同一时刻、两个机位），算包围盒并记账。
##
## ⚠️ 两个机位**共用** `focus` 与 `cam_size` ⇒ 行与行之间、列与列之间的宽度
## **可直接相减**；"变窄"只可能是形态收了，不可能是取景变了。
func _capture(fb: FlightBody, focus: Vector3, cam_size: float,
		shots: Array, stage: int) -> void:
	for ri in ROWS.size():
		var v: String = ROWS[ri][0]
		var img := await _shoot(fb, v, focus, cam_size)
		var rec := {
			"view": ri,
			"stage": stage,
			"img": img,
			"bw": 0, "bh": 0, "cov": 0.0,
			"morph": fb.cruise_morph,
			"action": (fb.model_fsm.current_action() if fb.model_fsm != null else "?"),
		}
		if img != null:
			var box := _bbox_of_subject(img)
			rec["bw"] = box[0]
			rec["bh"] = box[1]
			rec["cov"] = box[2]
			_draw_text(img, 12, H - 16, str(int(box[0])))
		shots.append(rec)


## 拍一张。`view` = "tail"（追尾，+Z 侧）或 "top"（正上方俯视）。
##
## ⚠️ 俯视机位的 up 必须换成 **−Z（世界前）**：用默认 `Vector3.UP` 会与视线
##（朝正下方）**共线**，`looking_at()` 当场拒绝，相机停在原点。
## ⚠️ `global_position` 必须在 `add_child` **之后**设。
## ⚠️ 取景尺寸各格**共用**（`cam_size` 是调用方算好传进来的）。
func _shoot(fb: FlightBody, view: String, focus: Vector3, cam_size: float) -> Image:
	var d := maxf(cam_size, 1.0) * 2.2
	var off: Vector3
	var cam_up := Vector3.UP
	if view == "top":
		off = Vector3(0.0, d, 0.0)
		cam_up = Vector3(0.0, 0.0, -1.0)
	else:
		var el := deg_to_rad(TAIL_ELEV_DEG)
		off = Vector3(0.0, sin(el), cos(el)) * d

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = cam_size
	cam.near = 0.05
	cam.far = 9000.0
	add_child(cam)
	cam.global_position = focus + off
	cam.transform = cam.transform.looking_at(focus, cam_up)
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


## 主体（非背景）像素的包围盒宽 / 高 / 覆盖率。
##
## 背景是**纯色**（`_build_env()` 里写死的 0.60/0.63/0.68，且无阴影、无天空）
## ⇒ 阈值取通道绝对差之和 > 0.06 就足够干净，抗锯齿边缘不会把框撑大。
## ⚠️ 别用"亮度"当判据：机体上有比背景**暗**的深蓝，也有比它**亮**的白，
## 单看亮度会把深色件判成背景。
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
			var d := absf(c.r - bg.x) + absf(c.g - bg.y) + absf(c.b - bg.z)
			if d > 0.06:
				n += 1
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return [0, 0, 0.0]
	return [x1 - x0 + 1, y1 - y0 + 1,
			float(n) / float(img.get_width() * img.get_height())]


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
