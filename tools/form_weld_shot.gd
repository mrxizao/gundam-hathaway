extends Node
## 轮 42：**形态骨帧末焊** —— 真机判据图（2 排 × 4 格）。
##
## ## 这张图要证一件事（三段式，缺一段都不算证）
##
## | 格 | 在播什么 | 焊接 | 期望 | 它在证 |
## |----|----------|------|------|--------|
## | ① | 巡航待机 | 开 | 翼**展开** | 基准 |
## | ② | `dash_f`（按前进） | **开** | 翼**仍展开** | ★ 用户报的 bug 治好了 |
## | ③ | `dash_l` + 转身窗口 | **开** | 翼**收起** | ★ 用户要的"左右才关"还在 |
## | ④ | `dash_f`（按前进） | **关**（负对照） | 翼**关上** | ★ 没有焊接时 bug 就复现 —— 因果闭合 |
##
## ② 与 ④ 是**同一段动作、同一台机体、唯一变量是焊接开关** ⇒ 两者之差只能归因给焊接。
##
## ## 判据只取俯视那一排（view = 1）
##
## 形态差落在这个自由度上：「翼板沿机身轴展开 ⇄ 收起」——
## 它在**俯视投影**里最敏感（前后向/面积），追尾机位几乎只是厚度变化
##（轮 34 实测：俯视 17.69% → 10.24%，追尾只差 ±4%）。
## 这条规矩是轮 33 那条的延续：**判一个几何自由度，机位必须垂直于它。**
## 追尾那一排是"玩家实际视角长什么样"的交代，不是判据。
##
## ## 为什么 ③ 必须排在 ④ 前面（顺序不可换）
##
## `detach()` 把焊接载体的骨架引用摘掉，是**不可逆**的一次性动作。
## ③ 要的是"焊开着、`morph` 被转身窗口压到 0"，所以必须在 ④ 之前做。
##
## ## 为什么手动 tick 而不是真按键 / 真跑冲刺
##
## 真跑冲刺机体以 ~3500 m/s 位移，几个物理帧就飞出取景框；探针也没有输入系统。
## 这里直接摆"段动作选择器" `_dash_anim_dir`（`FlightBody` 自己的字段，
## 由 `_apply_translate()` 在真机上写；本图不跑那一支，所以它不会被重置），
## 再逐迭代推 `_tick_cruise_morph → _tick_model_anim` —— 与 `_tick_effects()` 内部
## 同一顺序，只是不跑与本图无关的视觉 tick（拖尾 / 尾焰 / 闪光），
## 免得粒子污染"非背景像素"的测量。
##
## ## ★ 这张图是**第二次跑**才对的 —— 它抓出过一个探针抓不到的假绿
##
## 第一次跑（挂 `SceneTree.process_frame`）的结果：
##
##     ① 巡航态 17.69% ｜ ② 前冲·焊接开 **10.66%** ｜ ④ 前冲·焊接关 **10.66%**
##
## ② 与 ④ **逐位相同** ⇒ 焊接一点作用都没有；而同期探针读**局部 pose** 是好的（0.00°）
## —— 因为局部 pose 是渲染的**输入**，不是输出。改挂 `AnimationMixer.mixer_applied`
## （动画求值刚写完那一刻）之后 ② 才对上 ①。
## ⇒ 本图存在的意义：**判据必须落在真正被消费的那一层（像素）上。**
##
## ## ★ 第三次修正：主判据从「投影面积」换成「形态骨局部旋转」
##
## 挂点修好后，② 是 14.70%、① 是 17.69% —— 差 16.9%。**看图**才发现那 16.9% 主要
## 来自 `dash_f` 让**腿岔开、身体前倾**，不是翼。投影面积是整体剪影，把两个因素混在
## 一起，**不可归因**。⇒ 主判据改成量「形态骨自己的局部旋转离 ①（巡航态）多远」
##（① 时自拍基准，自校准）；面积降为**辅助**判据，只用来证明「像素层面也看得出来」。
## 与轮 33 / 轮 34 那条同源：**判一个自由度，读数必须落在那个自由度上。**
##
## ## 跑法（**不能加 --headless**：dummy 渲染器抓出来是空的）
##   godot --path <工程> res://tools/form_weld_shot.tscn -- <输出目录>

const W := 400
const H := 470
## 追尾机位的仰角（与轮 33 / 轮 34 的判据图同一档，便于对照）。
const TAIL_ELEV_DEG := 12.0
## 手动 tick 的固定步长：与物理帧率 60 Hz 一致，于是"帧数"直接就是时间。
const DT := 1.0 / 60.0
## 8 根形态骨（与 `FormWeld` 的焊接表一致；`Shoulder.L` 被后者的 20° 门槛滤掉）。
const FORM_BONES := [
	"Wing.L", "Wing.R",
	"BinderFront.L", "BinderFront.R",
	"BinderBack.L", "BinderBack.R",
	"RearHang.L", "RearHang.R",
]
const COLS := ["1 巡航态", "2 前冲·焊开", "3 左闪·焊开", "4 前冲·焊关(负对照)"]
const ROWS := [["tail", "追尾机位"], ["top", "俯视机位"]]

var out_dir := "user://form_weld"
## ① 巡航态时读下的 8 根形态骨**局部旋转** = 自校准基准。
##
## 之后每格量一次「离它多远」—— 这是「翼关没关」最**直接**的读数，
## 不受「动作本身让身体怎么摆」的干扰（投影面积会混入那个因素，见判据段的注释）。
var _ref_pose := {}
var _dt_used := DT


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
	# ⚠️ 取三轴最大值再放 1.25 倍：巡航态翼展接近静态包围盒上限，
	# 只按 size.y 取景会把翼尖裁掉 —— 而裁掉恰好会把"宽"量小，抵消要证的结论。
	var cam_size: float = maxf(maxf(bounds.size.x, bounds.size.y), bounds.size.z) * 1.25
	print("DIAG bounds size=(%.1f, %.1f, %.1f)  cam.size=%.2f" % [
		bounds.size.x, bounds.size.y, bounds.size.z, cam_size])

	# ---- 前置自检：焊接载体**必须在场**，否则这图什么都不用看了 ----
	var welded := fb._form_weld != null
	print("DIAG _form_weld=%s 形态骨=%d 根 被门槛滤掉=%s" % [
		"yes" if welded else "**null**",
		fb._form_weld.form_bone_count() if welded else 0,
		str(fb._form_weld.skipped) if welded else "—"])
	if not welded:
		print("FATAL: 焊接载体没建起来 ⇒ 出图无意义")
		get_tree().quit(1)
		return

	# 平移模式下 `fm.boosting` 恒 true ⇒ 巡航态常驻。照抄那个前提。
	fb.fm.boosting = true
	fb.fm.hovering = false

	var shots: Array = []

	# ---- ① 巡航态 ----
	fb._dash_anim_dir = ""
	_settle(fb, 90)
	await _wait_action(fb, "cruise_idle", 3.0)
	await _wait_seconds(fb, 0.30)
	_snapshot_ref(fb)   # ★ 基准 = ① 巡航态本身（自校准，不依赖任何外部姿态表）
	await _capture(fb, focus, cam_size, shots, 0)

	# ---- ② 前冲（按前进键）· 焊开 ⇒ 翼该保持展开 ----
	fb._dash_anim_dir = "f"
	_settle(fb, 30)
	await _capture(fb, focus, cam_size, shots, 1)

	# ---- ③ 左闪 · 焊开：转身窗口把 morph 压到 0 ⇒ 翼该收起 ----
	fb._dash_spin_t = FlightBody.QB_TIME
	fb._dash_anim_dir = "l"
	_settle(fb, 30)
	await _capture(fb, focus, cam_size, shots, 2)

	# ---- ④ 负对照：摘掉焊接，回巡航态，再按前进 ⇒ 翼该被 dash_f 写回去 ----
	fb._form_weld.detach()
	fb._dash_spin_t = 0.0
	fb._dash_anim_dir = ""
	_settle(fb, 120)
	await _wait_action(fb, "cruise_idle", 3.0)
	await _wait_seconds(fb, 0.30)
	fb._dash_anim_dir = "f"
	_settle(fb, 30)
	await _capture(fb, focus, cam_size, shots, 3)

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

	print("\n=== 形态骨帧末焊判据（非背景像素；取景全程共用 cam.size=%.2f）===" % cam_size)
	print("%-8s %-22s %-6s %-6s %-8s %-8s %-9s %-8s %-7s %s" % [
		"机位", "格", "宽", "高", "覆盖%", "morph", "离①基准", "局部残差", "焊接次数",
		"当时在播的动作"])
	var by: Dictionary = {}
	for s in shots.size():
		var r: Dictionary = shots[s]
		by["%d_%d" % [int(r["view"]), int(r["stage"])]] = r
		print("%-8s %-22s %-6d %-6d %-8.2f %-8.4f %-9.2f %-8.2f %-7d %s" % [
			ROWS[int(r["view"])][1], COLS[int(r["stage"])], int(r["bw"]), int(r["bh"]),
			float(r["cov"]) * 100.0, float(r["morph"]), float(r["gap"]), float(r["resid"]),
			int(r["welds"]), str(r["action"])])

	print("\n--- 自动判据（俯视机位）---")
	var ok_all := got == cols * rows
	var c1 := float(by["1_0"]["cov"])
	var c2 := float(by["1_1"]["cov"])
	var c3 := float(by["1_2"]["cov"])
	var c4 := float(by["1_3"]["cov"])
	var g1 := float(by["1_0"]["gap"])
	var g2 := float(by["1_1"]["gap"])
	var g3 := float(by["1_2"]["gap"])
	var g4 := float(by["1_3"]["gap"])
	# ---- 主判据：形态骨**局部旋转**离 ① 巡航态多远 ----
	#
	# ★ 主判据**不是**投影面积：面积是**整体剪影**，`dash_f` 让腿岔开、身体前倾
	#   也会改它 ⇒ 量出来的差同时含「翼关了多少」与「身体怎么摆」两个因素，**不可归因**
	#   （第一次跑就被这条糊弄了：② 14.70% vs ① 17.69% 差 16.9%，看图才知道
	#    那 16.9% 主要来自**腿部姿态**，不是翼）。
	#   形态骨的局部旋转才是「翼关没关」的直接读数 —— 与轮 33 那条同源：
	#   **判一个自由度，读数必须落在那个自由度上。**
	ok_all = _judge("① 巡航态：形态骨就是基准（离① %.2f° ≡ 0）" % g1,
		absf(g1) < 0.01) and ok_all
	ok_all = _judge("★★② 前冲·焊开 ⇒ 形态骨仍**贴在巡航**（离① 仅 %.2f° ≤ 1°）" % g2,
		g2 >= 0.0 and g2 <= 1.0) and ok_all
	ok_all = _judge("★★③ 左闪·焊开 ⇒ 形态骨按 morph 收到常态（离① %.2f° ≥ 100°）" % g3,
		g3 >= 100.0) and ok_all
	ok_all = _judge("★★④ 前冲·焊关（负对照）⇒ 被 dash_f 写回常态（离① %.2f° ≥ 100°）" % g4,
		g4 >= 100.0) and ok_all
	# ---- 辅助判据：像素层面也看得出来（否则「只在数据上成立」）----
	ok_all = _judge("① 巡航态确实展开（覆盖 %.2f%% > 10%%）" % (c1 * 100.0), c1 > 0.10) and ok_all
	ok_all = _judge("辅助：② 的剪影明显比 ④ 宽（%.2f%% > %.2f%% × 1.15）"
		% [c2 * 100.0, c4 * 100.0], c2 > c4 * 1.15) and ok_all
	ok_all = _judge("辅助：③④ 都收起（%.2f%% / %.2f%% < ① 的 85%%）"
		% [c3 * 100.0, c4 * 100.0], c3 < c1 * 0.85 and c4 < c1 * 0.85) and ok_all
	print("  追尾机位（只做交代，不判）：①② 宽 %.0f / %.0f px"
		% [float(by["0_0"]["bw"]), float(by["0_1"]["bw"])])

	var out := out_dir.path_join("form_weld_cmp.png")
	print("\nSHOT %s err=%d  拍到 %d 格  ALL_OK=%s" % [out, sheet.save_png(out), got, ok_all])
	print("  排 1 = 追尾机位 · 排 2 = 俯视机位；列 = ① 巡航态 ② 前冲·焊开 ③ 左闪·焊开 ④ 前冲·焊关")
	print("FORM_WELD_SHOT_DONE -> ", out_dir)
	get_tree().quit(0 if (got > 0 and ok_all) else 1)


## 把当前 8 根形态骨的**局部旋转**记成基准（① 巡航态调用一次）。
##
## 为什么不从 `FormWeld` 借那张巡航表：④ 那格已经把焊接 `detach()` 了，
## 而基准要在**四格之间**可比 ⇒ 用「① 自己的姿态」当基准最省事，也最自洽。
func _snapshot_ref(fb: FlightBody) -> void:
	_ref_pose.clear()
	var skel := fb._model_skel
	if skel == null:
		return
	for b in FORM_BONES:
		var bi := skel.find_bone(b)
		if bi >= 0:
			_ref_pose[b] = skel.get_bone_pose_rotation(bi)


## 当前形态骨**离 ① 巡航基准**的最大夹角（°）。基准未拍时返 -1（不伪装成 0）。
func _gap_from_ref(fb: FlightBody) -> float:
	if _ref_pose.is_empty():
		return -1.0
	var skel := fb._model_skel
	if skel == null:
		return -1.0
	var mx := 0.0
	for b: String in FORM_BONES:
		var bi := skel.find_bone(b)
		if bi < 0 or not _ref_pose.has(b):
			continue
		mx = maxf(mx, rad_to_deg(
			skel.get_bone_pose_rotation(bi).angle_to(_ref_pose[b] as Quaternion)))
	return mx


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
## ⚠️ 三个必踩的坑（抄自 `dash_stow_shot.gd` 的现场记录）：
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


## 推进 `n` 个固定步长的"逻辑帧"（不依赖真实帧率 ⇒ 形态轨迹可复现）。
func _settle(fb: FlightBody, n: int) -> void:
	for i in n:
		fb._tick_cruise_morph(DT)
		fb._tick_model_anim(DT)
		await get_tree().physics_frame


## 继续推进，直到状态机的当前动作变成 `want`（或耗尽 `max_sec` **模拟秒**）。
##
## ⚠️ 预算按**迭代数**算，不按 `get_process_delta_time()` 累加 —— 窗口模式下
## process delta 远大于 1/60，按真实 delta 累加会让循环**还没走到就退出**
##（`dash_stow_shot.gd` 踩过这个坑）。一次迭代 = 一个 `DT` ⇒ 预算就是模拟秒。
func _wait_action(fb: FlightBody, want: String, max_sec: float) -> void:
	var budget := int(round(max_sec * 60.0))
	for i in budget:
		if fb.model_fsm != null and fb.model_fsm.current_action() == want:
			return
		fb._tick_cruise_morph(DT)
		fb._tick_model_anim(DT)
		await get_tree().physics_frame


## 再等 `sec` 秒**模拟时间**，期间照常推形态与状态机。
## ⚠️ 不能省：`current_action()` 是在换动作**立刻**改的，此刻交叉淡入刚开始，
## 截图会拍到两个姿态的混合中间帧（轮 34 实测：同一格两次跑量到 163 / 189 px）。
func _wait_seconds(fb: FlightBody, sec: float) -> void:
	var budget := int(round(sec * 60.0))
	for i in budget:
		fb._tick_cruise_morph(DT)
		fb._tick_model_anim(DT)
		await get_tree().physics_frame


## 拍两张（同一台机体、同一时刻、两个机位），算包围盒并记账。
##
## ⚠️ 两个机位**共用** `focus` 与 `cam_size` ⇒ 格与格之间的宽度**可直接相减**；
## "变窄"只可能是形态收了，不可能是取景变了。
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
			# ---- 诊断：把「焊接跑没跑」与「渲染认不认」拆开 ----
			#   `resid` = 局部 pose 离巡航的残差（≈0 = 骨写对了）
			#   `welds` = 焊接累计调用次数（0 = 信号压根没触发）
			#   ⚠️ 若 `resid ≈ 0` 而**像素仍是收起态** ⇒ 局部 pose ≠ 渲染 ⇒ 挂点选错了。
			"resid": (fb._form_weld.residual_deg()
				if (fb._form_weld != null and fb._form_weld.attached()) else -1.0),
			"welds": (fb._form_weld.welds if fb._form_weld != null else -1),
			# ---- 主判据读数：形态骨**自己的**局部旋转离 ① 巡航基准多远 ----
			"gap": _gap_from_ref(fb),
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
## 背景是**纯色**（`_build_env()` 里写死的 0.60/0.63/0.68，无阴影、无天空）
## ⇒ 通道绝对差之和 > 0.06 就足够干净，抗锯齿边缘不会把框撑大。
## ⚠️ 别用"亮度"当判据：机体上有比背景**暗**的深蓝，也有比它**亮**的白。
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
