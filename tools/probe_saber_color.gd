extends Node
## 军刀配色判据探针（**只读**：不改工程，只出图 + 逐像素取色）。
##
## ## 它要回答的那个问题
##
## 用户：「**柯西光束军刀要是绿色的啊**」。
## 配置侧（`SuitProfile.xi()` 的 `saber_beam_color`）写着绿，但**配置是输入、屏幕是输出** ——
## 军刀是 **additive 混合**，外刃外面还叠一层 `lerp(主色, 白, 0.72)` 的内芯（能量 12.0）
## ⇒ **完全可能配的是绿、屏幕上烧成一片白**。判据必须落在**像素**上。
##
## ## 判据（5 条）
##
## | # | 层 | 判据 |
## |---|---|---|
## | ① | 配置 | `FX.saber_tint_of(saber_beam_color)` 的色相落在**绿带**（80°~170°）且饱和度 ≥ 0.40 |
## | ② | 配置 | 主色**已指定**（α > 0 ⇒ 内芯/残影/点光都由它推，不是老粉白） |
## | ③ | **像素** | 亮刀造成的**变化像素**里，绿占多数（`绿 / 变化 ≥ 0.50`）|
## | ④ | **像素** | 变化像素里**没有成片白**（`白 ≤ 绿`）—— 整把刀烧白时这条红 |
## | ⑤ | **像素** | 变化像素的**平均色相**在绿带内、**平均饱和度** ≥ 0.25（"读得出是绿"而非"发灰的光"）|
##
## ## ★ 三个方法学要点（每条都是踩出来的）
##
## 1. **必须做逐像素差集（亮刀 − 无刀）**：柯西身上自带绿像素（实测无刀那格就有 11668 个），
##    直接数绿会把机体涂装算进刀刃 ⇒ 必须只看**颜色真的变了**的像素。
## 2. **机位必须垂直于「刀轴」**：刀是一根细长圆柱，视线顺着刀轴时它在画面上只有一个点。
##    方位角由 `fb._blade` 的世界朝向**现算**（N48·T38：判一个自由度，机位要垂直于它）。
## 3. **`_slash()` 的目标必须是真 `FlightBody`**：它内部会 `tgt.take_damage(...)`；
##    拿一个裸 `Node3D` 当目标会在 L3870 抛 `Nonexistent function 'take_damage'`
##    ⇒ 斩击弧那条生产路径**根本没走到**，图里也没有弧（第一版就是这么被骗过去的）。
##    ⚠️ 另：`_slash()` 收尾会 `_end_saber()` **把刀收起来**，所以「亮刀+斩」那一格要
##      先斩再补一次 `_show_blade()`。
##
## ## 跑法（**不能加 `--headless`**：dummy 渲染器抓出来是空的）
##   godot --path <工程> res://tools/probe_saber_color.tscn -- <输出目录>
##
## ## ⚠️ 背景刻意用**近黑**
##
## 判「一道 additive 光刃是什么颜色」深底才量得准（浅底会把一切洗成灰白、且背景自带色相）。

const W := 480
const H := 540
## 绿带（色相 0~1）。80° = 0.222，170° = 0.472。
const HUE_LO := 0.222
const HUE_HI := 0.472
## 单个像素算「绿」的饱和度门槛。
const SAT_MIN := 0.30
## 单个像素算「白（烧掉）」的门槛。
const WHITE_SAT_MAX := 0.12
const WHITE_VAL_MIN := 0.85
## 「这个像素不是背景」的亮度门槛。
##
## ⚠️ 必须**贴着背景色**取（背景 `(0.06,0.07,0.09)` ⇒ v = 0.09），不能凭感觉取 0.20：
##   取高了会把"暗、但确实存在的光刃"整片判成背景，读数恒为 0 而**不报任何错**。
const BG_V := 0.12
## 「这个像素变了」的门槛（RGB 通道差之和，0~3）。
const DIFF_MIN := 0.10
## ③ 的门槛：变化像素里绿的比例。
const GREEN_SHARE_MIN := 0.50
## ⑤ 的门槛：变化像素的平均饱和度。
const MEAN_SAT_MIN := 0.25

var out_dir := "user://saber_color"
var _ok_all := true
## 两个机位的仰角（**方位**由「垂直于刀轴、且站在刀这一侧」现算）。
const ELEVS := [8.0, 30.0]
## 两个机位的**相机方向**（单位向量，由 `perp` 与仰角现算）。
var _cam_dirs: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(W, H))

	_build_env()
	await get_tree().physics_frame

	FlightBody.use_placeholder = false
	var p := SuitProfile.xi()
	var fb := await _mount(p, Vector3(0.0, 3000.0, 0.0))
	# ★★★ 这里**绝对不能** `fb.set_process(false)` —— 本轮第三、四次拍空的真凶。
	#
	# `_show_blade()` 是 **Tween 淡入**的（additive 材质的 `albedo_color.a` 从 0 起），
	# 而 `Tween` 默认走 `TWEEN_PROCESS_IDLE`、**绑定在创建它的那个节点上** ⇒
	# 把 `fb` 的 `process` 关掉，tween 永远不推进 ⇒ 刀**几何全对**
	# （世界 AABB 11.1 单位、8 个角投影全落在画面里）却**渲染为全透明** ⇒ 屏幕 0 像素变化。
	#
	# 这是一种最阴的静默失效：`visible=true`、材质 albedo 是绿的、发光强度 7.0、
	# 包围盒尺寸合理 —— 每一项"体检"都正常，**只有画面是黑的**。
	# 判据必须落在像素上才有意义；而像素要动，就得让 tween 跑 ⇒ **只关物理**（`_mount()` 里已做）。

	# ============================================================ 段 1：配置层
	print("\n" + "=".repeat(96))
	print("[段 1] 配置层 —— 计划里那把刀是什么颜色")
	print("=".repeat(96))
	var tint: Color = p.saber_beam_color
	var t0 := FX.saber_tint_of(tint)
	print("  saber_beam_color = %s  α=%.2f" % [str(tint), tint.a])
	print("  主色  saber_tint_of  = %s  h=%.1f° s=%.2f v=%.2f" % [
		str(t0), t0.h * 360.0, t0.s, t0.v])
	for pair: Array in [["内芯 saber_core_of ", FX.saber_core_of(tint)],
			["残影 saber_ghost_of", FX.saber_ghost_of(tint)],
			["点光 saber_light_of", FX.saber_light_of(tint)]]:
		var c: Color = pair[1]
		print("  %s = %s  h=%.1f° s=%.2f" % [str(pair[0]), str(c), c.h * 360.0, c.s])
	_ok_all = _judge("① 主色在**绿带**（h=%.1f° ∈ [%.0f°, %.0f°]，s=%.2f ≥ %.2f）" % [
		t0.h * 360.0, HUE_LO * 360.0, HUE_HI * 360.0, t0.s, SAT_MIN],
		t0.h >= HUE_LO and t0.h <= HUE_HI and t0.s >= SAT_MIN) and _ok_all
	_ok_all = _judge("② 主色**已指定**（α > 0 ⇒ 内芯/残影/点光都由它推，不是老粉白）",
		tint.a > 0.0) and _ok_all

	# ============================================================ 段 2：像素层
	print("\n" + "=".repeat(96))
	print("[段 2] 像素层 —— 屏幕上到底是什么颜色（**逐像素差集**：亮刀 − 无刀）")
	print("=".repeat(96))
	var hand: Node3D = null
	if fb.rig != null and fb.rig.has_slot("hand_L"):
		hand = fb.rig.slot("hand_L")
	print("  hand_L = %s" % ("有" if hand != null else "**没有** —— 刀挂不上，下面读数无意义"))
	if hand == null:
		print("\nVERDICT: SABER-PROBE-INVALID（挂刀锚点缺失）")
		get_tree().quit(1)
		return

	# `_slash()` 需要 `projectile_container` 非 null（生产里由世界层注入）。
	# ⚠️ 测试里必须**复刻这一步**，否则它会静默跳过 FX。
	if fb.projectile_container == null:
		fb.projectile_container = fb
	# ★ 目标必须是**真 FlightBody**（否则 `tgt.take_damage()` 抛错、斩击弧走不到）。
	# 用第二台柯西当靶：它站在 300 单位外，取景 30 单位 ⇒ 不会进画。
	var enemy := await _mount(SuitProfile.xi(), Vector3(300.0, 3000.0, 0.0))
	fb._show_blade()
	# ★ 等够 tween 走完（见上面 `_ready()` 里那段注释：tween 走 idle，得等 idle 帧）。
	await _settle(45)
	if fb._blade == null:
		print("  **刀根节点没建起来**（`_show_blade()` 没挂上）⇒ 下面无意义")
		print("\nVERDICT: SABER-PROBE-INVALID")
		get_tree().quit(1)
		return
	# ---- 机位由**刀自己的世界包围盒**定：既保证拍得到，又能顺便量出刀的**真实尺寸** ----
	#
	# ⚠️ 第一版是"手的位置 + 沿刀轴 8 单位"当取景中心 —— **拍不到刀**（画面下方全黑）。
	#   与其猜，不如把刀的 AABB 算出来：中心当取景中心、尺寸当取景大小。
	#   顺带这是一条**独立判据**：刀挂在手骨上会继承骨架缩放（`target_height/native_height` ≈ 28.5）
	#   ⇒ 一旦缩放链有问题，刀会变成几百单位的巨物，AABB 会立刻暴露。
	var bl: Node3D = fb._blade
	var aabb := _world_aabb(bl)
	print("  **刀的世界包围盒** position=%s size=%s（模型高 28.0 ⇒ 刀长约 %.2f 倍身高）" % [
		str(aabb.position), str(aabb.size), aabb.size.length() / 28.0])
	var dir: Vector3 = (-bl.global_transform.basis.z).normalized()
	# ---- ★ 相机必须放在**刀所在的那一侧**，否则机体把刀挡掉 ----
	#
	# 上一版用球坐标 `az = yaw + 90°` 定机位，结果相机落到 **−X** 侧，
	# 而柯西左手握着刀（x ≈ +6.7）⇒ **整个机体挡在相机和刀之间**，
	# 窄景、全景里都是一片黑（实测「变化像素」只有 100）。
	# 正解：取其**垂直方向** `perp = cross(刀轴, UP)`，再按「刀相对机体的偏移方向」
	# 校正符号 —— 相机站在刀这一侧，机体就挡不住。
	var perp := dir.cross(Vector3.UP)
	if perp.length() < 1e-4:
		perp = Vector3.RIGHT
	perp = perp.normalized()
	var body := fb.global_position
	if Vector3(aabb.get_center().x - body.x, 0.0, aabb.get_center().z - body.z).dot(perp) < 0.0:
		perp = -perp
	_cam_dirs = [
		(perp * cos(deg_to_rad(ELEVS[0])) + Vector3.UP * sin(deg_to_rad(ELEVS[0]))).normalized(),
		(perp * cos(deg_to_rad(ELEVS[1])) + Vector3.UP * sin(deg_to_rad(ELEVS[1]))).normalized(),
	]
	var focus: Vector3 = aabb.get_center()
	var cam_size: float = maxf(maxf(aabb.size.x, aabb.size.y), aabb.size.z) * 1.45
	print("  刀轴 dir=%s  垂直向量 perp=%s（相机站这一侧）" % [str(dir), str(perp)])
	print("  取景中心=%s  cam.size=%.2f" % [str(focus), cam_size])
	# ---- 刀的**可见性自证**：节点在不在、缩放是不是 1、材质是什么 ----
	#
	# ⚠️ 上一版只打印了包围盒就以为拍得到 —— 结果**窄取景下画面上什么都没有**。
	#   于是这里把「刀这个节点到底以什么形态存在」全打出来，别靠猜。
	var bs := bl.global_transform.basis.get_scale()
	print("  刀根 global scale=%s  可见=%s  子节点=%d" % [str(bs), str(bl.visible), bl.get_child_count()])
	# ---- ★ 祖先链可见性：本轮"挂上去就 0 像素"的**唯一**可能入口 ----
	#
	# 段 2.0 的 D 组已经反证：**同一位置、同一相机、同一个生产函数** `FX.beam_blade()` 建的刀
	# 是**可见且纯绿**的（非背景 4934 个、最亮 `(0.5569,1.0,0.6941)`）。
	# ⇒ 刀的材质、几何、渲染**全都没问题** ⇒ "挂到柯西手上就不可见"只能是**挂载链**的问题。
	# ⚠️ `Node3D.visible` 只看**自己**；整条链里**任何一层**关掉，子节点都不渲染，
	#   而 `visible` / `global_transform` / 包围盒**全都照常**（= 静默失效的标准形态）。
	print("  刀 in_tree=%s  is_visible_in_tree=%s  父=%s" % [
		str(bl.is_inside_tree()), str(bl.is_visible_in_tree()),
		str(bl.get_parent().name if bl.get_parent() != null else "-")])
	var anc: Node = bl
	var chain: Array = []
	while anc != null and chain.size() < 14:
		var mark := ""
		if anc is Node3D:
			mark += " vis=%s" % str((anc as Node3D).visible)
		if anc is MeshInstance3D:
			mark += " layers=%d" % (anc as MeshInstance3D).layers
		chain.append("%s%s" % [anc.name, mark])
		anc = anc.get_parent()
	print("  刀的祖先链（自身 → 根）：%s" % " ← ".join(PackedStringArray(chain)))
	# ★ 挂载可见性必须**在这里**就读下来（段 2.6 才打印）。
	#   ⚠️ 后面段 2.5 会调 `fb._slash(enemy)`，而 `_slash()` 收尾会 `_end_saber()`
	#   ⇒ `_hide_blade()` ⇒ `bl` 被 `queue_free()`。到段 2.6 再读它就是
	#   `Cannot call method 'is_visible_in_tree' on a previously freed instance` —— **脚本当场中断**
	#   （`_ready` 抛错 ⇒ 后面的 `_sheet()` 不执行、`get_tree().quit()` 也不执行 ⇒ 进程挂住不退）。
	var mount_ok := bl.is_visible_in_tree()
	var mount_parent := str(bl.get_parent().name)
	var mount_bad: Array = []
	if not mount_ok:
		var a2: Node = bl
		while a2 != null:
			if a2 is Node3D and not (a2 as Node3D).visible:
				mount_bad.append(a2.name)
			a2 = a2.get_parent()
	for c in bl.get_children():
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			var mat := mi.get_active_material(0)
			var alb := "-"
			var emi := "-"
			if mat is StandardMaterial3D:
				var sm: StandardMaterial3D = mat
				alb = str(sm.albedo_color)
				emi = "%.2f" % sm.emission_energy_multiplier
			print("    %-12s 可见=%s  材质 albedo=%s  发光强度=%s" % [
				mi.name, str(mi.visible), alb, emi])

	# ★★ 刀 AABB 的 8 个角（世界坐标）—— 用于**投影自证**。
	#
	# ⚠️ **踩过的坑（本轮第三次拍空）**：窄景全黑时，"变化像素" 仍读到 28 个 ——
	#   那 28 个**与机位无关**（两个不同仰角读数逐位相同），来自 `_draw_text` 的**标签文字**：
	#   `"无刀"` 与 `"亮刀"` 是两个**不同的汉字**，画在同一坐标 ⇒ 差集把字形差异当成刀。
	#   ⇒ ① 标签一律画到**副本**（下面 `_label()`），`_report()` 只吃干净原图；
	#      ② 拍空了必须有**独立自证**（投影范围 + 画面最亮像素），不能靠"变化像素 > 0"当"拍到了"。
	var blade_pts: Array = []
	for k in 8:
		blade_pts.append(aabb.get_endpoint(k))
	# ★ 机体包围盒：`-14` 这种"猜的偏移"本轮已被证明不可靠（全景里机体偏在左下角）。
	var ba := _body_aabb(fb)
	print("  **机体世界包围盒** position=%s size=%s ⇒ 中心 %s" % [
		str(ba.position), str(ba.size), str(ba.get_center())])
	print("  刀中心距机体中心 %.2f（若远大于机体半高 ⇒ 刀确实被甩在体外）" % [
		(ba.get_center() - aabb.get_center()).length()])

	# ============================================================ 段 2.0：相机校准
	#
	# ⚠️ 本轮连续三次"**投影自证说刀在画面中央、画面却是纯背景**"。
	#   根因是上一版把 `cam.unproject_position()` 的输出当成了"拍到了"的证据 ——
	#   而它**只用相机自己的矩阵**，相机就算完全没接管视口也照样算得出"画面内"。
	#   这一段用**校准球**做反证：一个不受光纯红的球放在**焦点**上（= 刀中心），
	#   它若也拍不到，问题就在相机/视口，**与刀无关**（两者的修法完全不同）。
	print("\n" + "=".repeat(96))
	print("[段 2.0] 相机校准 —— 焦点固定为刀中心；放一个不受光纯红校准球做反证")
	print("=".repeat(96))
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.0
	sm.height = 4.0
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(1.0, 0.15, 0.15)
	sm.material = bm
	ball.mesh = sm
	add_child(ball)
	ball.global_position = focus
	await _settle(3)
	var vp_now := get_viewport().get_visible_rect().size
	print("  视口 %.0fx%.0f（`window_set_size(%d,%d)` **没生效**）" % [
		vp_now.x, vp_now.y, W, H])
	fb._hide_blade()
	await _settle(3)
	var g_a := _stat(await _shoot_at(_cam_dirs[0], focus, cam_size))
	print("  A 校准球 · 现状(size=%.2f)      → 非背景 %d 个 ｜ 最亮 %s @%s" % [
		cam_size, g_a["lit"], str(g_a["peak"]), str(g_a["at"])])
	var g_b := _stat(await _shoot_at(_cam_dirs[0], focus, 200.0))
	print("  B 校准球 · 放宽(size=200)       → 非背景 %d 个 ｜ 最亮 %s @%s" % [
		g_b["lit"], str(g_b["peak"]), str(g_b["at"])])
	var g_c := _stat(await _shoot_at(Vector3.UP, focus, 200.0))
	print("  C 校准球 · 俯视(from +Y,size=200) → 非背景 %d 个 ｜ 最亮 %s @%s" % [
		g_c["lit"], str(g_c["peak"]), str(g_c["at"])])
	ball.queue_free()
	await _settle(3)
	# --- 组 D/E：**自由刀** —— 用**生产函数** `FX.beam_blade()` 建一把刀，直接挂在探针
	#     根节点上（不经柯西的手）。用来把「刀的材质/渲染」与「挂到骨节点下」这两件事**分开**：
	#       D 组可见 ⇒ 生产路径本身没问题，之前拍空是**挂载/祖先链**的问题；
	#       D 组不可见 ⇒ `FX.beam_blade()` 的材质有问题（就是用户说的"不是绿的"的真身）。
	var free_blade: Node3D = FX.beam_blade(15.0, p.saber_beam_color)
	add_child(free_blade)
	free_blade.global_position = focus
	await _settle(3)
	print("  D 自由刀（`FX.beam_blade()` 直挂焦点，不经柯西的手）visible=%s in_tree=%s 子=%d" % [
		str(free_blade.visible), str(free_blade.is_visible_in_tree()), free_blade.get_child_count()])
	var g_d := _stat(await _shoot_at(_cam_dirs[0], focus, cam_size))
	print("    现状(size=%.2f)   → 非背景 %d 个 ｜ 最亮 %s @%s" % [
		cam_size, g_d["lit"], str(g_d["peak"]), str(g_d["at"])])
	var g_e := _stat(await _shoot_at(_cam_dirs[0], focus, 60.0))
	print("    放宽(size=60)     → 非背景 %d 个 ｜ 最亮 %s @%s" % [
		g_e["lit"], str(g_e["peak"]), str(g_e["at"])])
	free_blade.queue_free()
	await _settle(3)

	var shots: Array = []
	for vi in ELEVS.size():
		# --- 格 0：无刀基线 ---
		fb._hide_blade()
		await _settle(30)
		var img0 := await _shoot(vi, focus, cam_size, blade_pts)
		shots.append({"view": vi, "col": 0, "img": _label(img0, "无刀")})
		# --- 格 1：亮刀（走生产路径 `_show_blade()`）---
		fb._show_blade()
		await _settle(30)
		var img1 := await _shoot(vi, focus, cam_size, blade_pts)
		shots.append({"view": vi, "col": 1, "img": _label(img1, "亮刀")})
		# --- 格 2：亮刀 + 斩击弧（走生产路径 `_slash()`）---
		fb._slash(enemy)
		# ⚠️ 斩击弧是 **tween 出来的**（从 0 摊开）。只等 3 帧它还没张开、拍出来是个点。
		await _settle(10)
		fb._show_blade()          # ⚠️ `_slash()` 收尾会 `_end_saber()` 把刀收起来
		var img2 := await _shoot(vi, focus, cam_size)
		shots.append({"view": vi, "col": 2, "img": _label(img2, "亮刀+斩")})

	# ============================================================ 段 2.5：自由刀（判据来源）
	#
	# ★ 判据 ③④⑤ **必须**用自由刀，理由见上面"祖先链"那段：
	#   生产挂载点 `rig.slot("hand_L")` 的祖先里有一个 `Placeholder`（= `SuitRig` 的
	#   `_placeholder_root`）—— **有真模型时它被 `set_placeholder_visible(false)` 关掉**
	#   ⇒ 挂在它下面的刀**整条被藏掉**，那一格必然全黑。
	#
	#   ⚠️ 而「黑」**不是**「颜色不对」，是「根本没显示」。两者混在一个 VERDICT 里
	#   会把"挂载坏了"误读成"配色没生效" —— 本轮就是在这个歧义上绕了四圈。
	#   所以：**配色判据走这里（世界挂载、渲染路径与生产完全同一个函数），
	#   挂载问题单独出一份 VERDICT（段 2.6）**。
	print("\n" + "=".repeat(96))
	print("[段 2.5] 自由刀 —— 同一个 `FX.beam_blade()`，挂在**世界上**（判据 ③④⑤ 的来源）")
	print("=".repeat(96))
	var fb_free: Node3D = FX.beam_blade(15.0, p.saber_beam_color)
	add_child(fb_free)
	# ⚠️ `beam_blade()` 把刃放在**根节点前 -9 单位**处（`z = -(len*0.5 + 1.5)`），
	#   所以要让**刃的中心**落在取景中心上，根节点得沿 +Z 反推 9 单位。
	#   漏了这一步 ⇒ 刀偏在画面一侧、还有一半伸出画外（第一版实测投影 x∈[893,1825]，右边被切）。
	fb_free.global_position = focus + Vector3(0.0, 0.0, 15.0 * 0.5 + 1.5)
	await _settle(3)
	var fba := _world_aabb(fb_free)
	print("  自由刀 AABB position=%s size=%s（刀长参数 15.0 ⇒ 世界 %.2f，中心应≈取景中心 %s）" % [
		str(fba.position), str(fba.size), fba.size.length(), str(fba.get_center())])
	var free_pts: Array = []
	for k in 8:
		free_pts.append(fba.get_endpoint(k))
	# ★ 两个机位各拍一组，判据取**更保守**的那个：只测一个方位角 = 只测一个自由度。
	var f_rows: Array = []
	for fi in ELEVS.size():
		fb_free.visible = false
		await _settle(3)
		var fim0 := await _shoot(fi, focus, cam_size, free_pts)
		shots.append({"view": fi + 1, "col": 0, "img": _label(fim0, "无刀")})
		fb_free.visible = true
		await _settle(3)
		var fim1 := await _shoot(fi, focus, cam_size, free_pts)
		shots.append({"view": fi + 1, "col": 1, "img": _label(fim1, "亮刀")})
		fb._slash(enemy)
		await _settle(10)
		var fim2 := await _shoot(fi, focus, cam_size)
		shots.append({"view": fi + 1, "col": 2, "img": _label(fim2, "亮刀+斩")})
		f_rows.append(_report("自由刀 %.0f°" % ELEVS[fi], fim0, fim1))
	fb_free.queue_free()
	await _settle(3)

	# ⚠️ 这里**曾经**有一排"全景自证"（焦点=机体 AABB 中心）。本轮把它删了，原因值得记：
	#   `_body_aabb(fb)` 被污染了 —— 实测给出 `size=(27.7, 3012.5, 32.8)`（机体才 28 高），
	#   于是取景被撑到 `cam.size=3765`，刀在画面里只剩 **3×1 像素**（"拍到了"但等于没拍到）。
	#   污染源是 `fb` 子树里 `top_level` 的 FX 子节点（`_slash()` 的斩击弧挂在 `projectile_container`
	#   上也一样）—— 它们的 `global_transform` 与机体无关，却照样被递归算进包围盒。
	#   ⇒ **"用一个自身不可靠的读数去取景，只会得到另一张不可靠的图"**。
	#   现在自证改由三重硬读数承担：**投影范围 + 非背景像素数 + 画面最亮像素及其坐标**。

	var share := 1.0
	var white_over := 0.0
	var mean_sat := 1.0
	var changed_min := 1e9
	var hue_ok := true
	var hue_worst := -1.0
	for r: Dictionary in f_rows:
		share = minf(share, float(r["share"]))
		white_over = maxf(white_over, float(r["white"]) / maxf(float(r["green"]), 1.0))
		mean_sat = minf(mean_sat, float(r["mean_sat"]))
		changed_min = minf(changed_min, float(r["changed"]))
		var h := float(r["mean_hue"])
		if h < HUE_LO or h > HUE_HI:
			if not hue_ok:
				hue_worst = minf(hue_worst, h)
			else:
				hue_worst = h
			hue_ok = false
	_ok_all = _judge("③ 变化像素里**绿占多数**（最保守机位 %.3f ≥ %.2f ｜ 变化像素 %.0f）" % [
		share, GREEN_SHARE_MIN, changed_min], share >= GREEN_SHARE_MIN) and _ok_all
	_ok_all = _judge("④ 变化像素里**没有成片白**（白/绿 最大 %.3f ≤ 1.00）" % white_over,
		white_over <= 1.0) and _ok_all
	_ok_all = _judge("⑤ **每个**机位的平均色相都在绿带（%d 个机位全过）且最保守饱和度 %.3f ≥ %.2f%s" % [
		f_rows.size(), mean_sat, MEAN_SAT_MIN,
		"" if hue_ok else "  ← 越界机位 h=%.1f°" % (hue_worst * 360.0)],
		hue_ok and mean_sat >= MEAN_SAT_MIN) and _ok_all

	# ============================================================ 段 2.6：挂载（独立结论）
	#
	# 这一条**不进 `_ok_all`**：它回答的是"真机上有没有这把刀"，与"这把刀是什么颜色"是两件事。
	# 现在它是 **FAIL** —— 而它恰好解释了"为什么在游戏里看不到绿刀"。
	print("\n" + "=".repeat(96))
	print("[段 2.6] 挂载可见性 —— 生产挂载点（`rig.slot(\"hand_L\")`）的整条祖先链")
	print("=".repeat(96))
	print("  %s  ⑥ `%s` 的 `is_visible_in_tree()` = %s（`visible` 只看自己 ⇒ 单看它是 true，是**祖先**关掉的）" % [
		"PASS" if mount_ok else "FAIL", mount_parent, str(mount_ok)])
	if not mount_ok:
		print("      ⇒ 链上 `visible == false` 的节点：%s" % str(mount_bad))
		print("      ⇒ `SuitRig._placeholder_root` 在**有真模型时**被 `set_placeholder_visible(false)` 关掉，")
		print("         而手部 / 炮口 / 喷口这些**锚点**都挂在它下面 ⇒ **挂在锚点上的东西一起被藏掉**。")
		print("         ⚠️ 这是**挂载**问题，不是配色问题（`_blade` 的材质本身是绿的，见段 1 / 段 2.5）。")
	print("\nVERDICT-MOUNT: %s" % ("MOUNT-OK（真机上看得见这把刀）" if mount_ok
		else "MOUNT-INVISIBLE（真机上这把刀**不显示** —— 与颜色无关）"))

	_sheet(shots, 3, 3, "saber_color.png")
	print("\nVERDICT: %s" % ("SABER-GREEN-OK（屏幕上确实是绿的）" if _ok_all
		else "SABER-NOT-GREEN（配的是绿、屏幕上不是 —— 见上面哪一条红）"))
	get_tree().quit(0 if _ok_all else 1)


## 画面统计（自证用）：非背景像素数 + 画面最亮像素及其位置。
##
## 只给一个"变化像素"数字是不够的：它为 0 时分不清「没渲染」与「渲染了但被门槛滤掉」。
func _stat(img: Image) -> Dictionary:
	if img == null:
		return {"lit": 0, "peak": "N/A", "at": Vector2i.ZERO}
	img.convert(Image.FORMAT_RGBA8)
	var d := img.get_data()
	var w := img.get_width()
	var h := img.get_height()
	var lit := 0
	var peak_v := -1.0
	var peak := Color.BLACK
	var at := Vector2i.ZERO
	for i in w * h:
		var c := Color(d[i * 4] / 255.0, d[i * 4 + 1] / 255.0, d[i * 4 + 2] / 255.0)
		if c.v > peak_v:
			peak_v = c.v
			peak = c
			at = Vector2i(i % w, int(float(i) / float(w)))
		if c.v >= BG_V:
			lit += 1
	return {"lit": lit, "peak": peak, "at": at}


## 给一格图打标签 —— **返回的是副本**。
##
## ⚠️ 必须副本：差集比较的是「同一机位的无刀 vs 亮刀」两张原图，
##   若把 `"无刀"` / `"亮刀"` 直接画进原图，**两个不同汉字的字形差异**会被当成"刀造成的颜色变化"
##   （实测污染 28 个纯白像素，且两个仰角读数逐位相同 ⇒ 一眼可辨的假信号）。
func _label(src: Image, text: String) -> Image:
	if src == null:
		return null
	var im := src.duplicate()
	_draw_text(im, 12, H - 16, text)
	return im


## 一个 `Node` **子树**里所有 `MeshInstance3D` 的世界包围盒。
##
## ⚠️ 必须递归：机体的网格挂在**骨节点**下（`rig` 的骨是 `Node3D` 子链），
##   只看直接子节点会一个都取不到（`_world_aabb()` 就是那样的，它只适用于刀那种扁平结构）。
func _body_aabb(root: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n
			if mi.mesh != null:
				var a: AABB = mi.mesh.get_aabb()
				# ★ 剔除**离群的巨大网格**：实测 `fb` 子树里有一个 mesh 的局部 AABB 高达
				#   **3012 单位**（机体才 28 高）—— 动态生成的拖尾/尾焰条带 AABB 未刷新时就是这样。
				#   不剔除 ⇒ 取景被撑到 3765 ⇒ 刀在画面里只剩 **3×1 像素**（"拍到了"但等于没拍到）。
				if maxf(maxf(a.size.x, a.size.y), a.size.z) > 200.0:
					print("      [机体 AABB] 跳过 `%s`：局部尺寸 %s 过大（>200，疑为动态网格）" % [
						mi.name, str(a.size)])
				else:
					var t: Transform3D = mi.global_transform
					for i in 8:
						var p: Vector3 = t * a.get_endpoint(i)
						if first:
							out = AABB(p, Vector3.ZERO)
							first = false
						else:
							out = out.expand(p)
		for c in n.get_children():
			stack.append(c)
	return out


## 逐像素差集：只在「颜色真的变了」的像素上分类（排除机体自带的绿）。
func _report(tag: String, img0: Image, img1: Image) -> Dictionary:
	if img0 == null or img1 == null:
		return {"changed": 0, "green": 0, "white": 0, "share": 0.0,
			"mean_sat": 0.0, "mean_hue": -1.0}
	img0.convert(Image.FORMAT_RGBA8)
	img1.convert(Image.FORMAT_RGBA8)
	var a := img0.get_data()
	var b := img1.get_data()
	var n := img0.get_width() * img0.get_height()
	var changed := 0
	var green := 0
	var white := 0
	var sr := 0.0
	var sg := 0.0
	var sb := 0.0
	var sc := 0
	# ★ 自证读数：**变化像素为 0 时也要能分辨「刀没渲染」与「刀渲染了但我判定门槛太严」**。
	#   前者 `lit == 0`，后者 `lit` 很大。缺了这两个数就只能靠猜。
	#   ⚠️ `peak` 还必须**无条件**更新：只统计 v≥门槛的像素时，画面全黑与"有暗光但没到门槛"
	#      两种情况的 `peak` 都是黑 ⇒ 读数分辨不出，本轮就被它误导过。
	var lit := 0
	var peak := Color.BLACK
	var peak_at := Vector2i.ZERO
	var iw := img1.get_width()
	for i in n:
		var r0 := a[i * 4] / 255.0
		var g0 := a[i * 4 + 1] / 255.0
		var b0 := a[i * 4 + 2] / 255.0
		var r1 := b[i * 4] / 255.0
		var g1 := b[i * 4 + 1] / 255.0
		var b1 := b[i * 4 + 2] / 255.0
		var c1 := Color(r1, g1, b1)
		if c1.v > peak.v:
			peak = c1
			peak_at = Vector2i(i % iw, int(float(i) / float(iw)))
		if c1.v >= BG_V:
			lit += 1
		if absf(r1 - r0) + absf(g1 - g0) + absf(b1 - b0) < DIFF_MIN:
			continue
		var c := c1
		if c.v < BG_V:
			continue
		changed += 1
		if c.s >= SAT_MIN and c.h >= HUE_LO and c.h <= HUE_HI:
			green += 1
			sr += r1
			sg += g1
			sb += b1
			sc += 1
		elif c.s < WHITE_SAT_MAX and c.v > WHITE_VAL_MIN:
			white += 1
	var mean := Color.BLACK
	if sc > 0:
		mean = Color(sr / sc, sg / sc, sb / sc)
	print("    %-12s 变化=%d ｜ 绿=%d 白=%d（%.3f）｜ 绿像素均色 %s h=%.1f° s=%.2f" % [
		tag, changed, green, white, float(green) / maxf(float(changed), 1.0),
		str(mean), mean.h * 360.0, mean.s])
	print("    %-12s [自证] 非背景像素 %d 个 ｜ 画面最亮像素 %s v=%.3f @%s（若最亮即背景 0.09 ⇒ 光刃压根没进画面）" % [
		"", lit, str(peak), peak.v, str(peak_at)])
	return {"changed": changed, "green": green, "white": white,
		"share": float(green) / maxf(float(changed), 1.0),
		"mean_sat": mean.s, "mean_hue": mean.h, "lit": lit}


func _sheet(shots: Array, cols: int, rows: int, fname: String) -> void:
	var sheet := Image.create(W * cols, H * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.06, 0.07, 0.09))
	for s in shots:
		var rec: Dictionary = s
		var img: Image = rec["img"]
		if img == null:
			continue
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, Vector2i(W, H)),
			Vector2i(W * int(rec["col"]), H * int(rec["view"])))
	for ci in range(1, cols):
		sheet.fill_rect(Rect2i(W * ci, 0, 2, H * rows), Color(0.42, 0.48, 0.58))
	for ri in range(1, rows):
		sheet.fill_rect(Rect2i(0, H * ri, W * cols, 2), Color(0.42, 0.48, 0.58))
	var out := out_dir.path_join(fname)
	print("\nSHOT %s err=%d（列 = [无刀 / 亮刀 / 亮刀+斩]，排 = [①生产挂载·仰角8° / ②自由刀·仰角8° / ③自由刀·仰角30°]）" % [
		out, sheet.save_png(out)])


func _judge(label: String, cond: bool) -> bool:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	return cond


# ================================================================ 工具

func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	# 近黑底：量 additive 光刃的**自身颜色**（浅底会把一切都洗白、且背景自带色相）。
	env.background_color = Color(0.06, 0.07, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.45, 0.52)
	env.ambient_light_energy = 0.80
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, 20.0, 0.0)
	key.light_energy = 1.2
	add_child(key)


func _mount(p: SuitProfile, at: Vector3) -> FlightBody:
	var holder := Node3D.new()
	add_child(holder)
	var fb := FlightBody.new()
	fb.team = 0
	fb.profile = p
	holder.add_child(fb)
	fb.global_transform = Transform3D(Basis(), at)
	fb.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame
	fb._hover_pose = fb.flight_pitch_deg
	return fb


## 等 `n` 个 **idle + 物理**帧。
##
## ⚠️ 必须两种都等：`Tween`（刀淡入）走 **idle**、姿态/骨骼走 **physics**，
##   只等一种就会读到"另一个时钟还没走完"的中间态。
func _settle(n := 3) -> void:
	for i in n:
		await get_tree().process_frame
		await get_tree().physics_frame


## 一个节点下所有 `MeshInstance3D` 的世界包围盒（工具用：既取景、又量真实尺寸）。
func _world_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in root.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi: MeshInstance3D = c
		if mi.mesh == null:
			continue
		var a: AABB = mi.mesh.get_aabb()
		var t: Transform3D = mi.global_transform
		for i in 8:
			var p: Vector3 = t * a.get_endpoint(i)
			if first:
				out = AABB(p, Vector3.ZERO)
				first = false
			else:
				out = out.expand(p)
	return out


func _shoot(vi: int, focus: Vector3, cam_size: float, probe: Array = []) -> Image:
	return await _shoot_at(_cam_dirs[vi], focus, cam_size, probe)


## `cam_dir` = **从取景中心指向相机**的单位向量（由调用方按「垂直于刀轴、站在刀这一侧」算好）。
##
## `probe` = 一组世界坐标点：**建完相机后把它们投影回画面像素坐标并打印**。
## 这是「拍空了」的**决定性诊断** —— 若这些点落在 `[0,W]×[0,H]` 之外，是**取景算错**；
## 若落在之内却是黑图，那是**渲染/可见性**问题。两者的修法完全不同，必须先分清。
func _shoot_at(cam_dir: Vector3, focus: Vector3, cam_size: float, probe: Array = []) -> Image:
	var d := maxf(cam_size, 1.0) * 2.2
	var off := cam_dir * d
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = cam_size
	cam.near = 0.05
	cam.far = 9000.0
	add_child(cam)
	cam.global_position = focus + off
	cam.transform = cam.transform.looking_at(focus, Vector3.UP)
	cam.current = true
	for f in 2:
		await get_tree().process_frame
	# ★ 一条**必须打**的读数：`unproject_position()` 只用相机自己的矩阵，
	#   它**不依赖相机是否真的在渲染** ⇒ "投影落画面内"证明不了"相机拍到了"。
	#   只有这一句能分辨「相机没接管视口」与「相机拍到了但内容没渲染」。
	print("      [相机] pos=%s size=%.2f near=%.2f far=%.1f d=%.1f ｜ viewport.camera==cam ? %s" % [
		str(cam.global_position), cam.size, cam.near, cam.far, off.length(),
		str(get_viewport().get_camera_3d() == cam)])
	if not probe.is_empty():
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for p: Vector3 in probe:
			var px := cam.unproject_position(p)
			lo = lo.min(px)
			hi = hi.max(px)
		var vp := get_viewport().get_visible_rect().size
		print("      [投影自证] 视口=%.0fx%.0f  探针点像素范围 x∈[%.0f,%.0f] y∈[%.0f,%.0f]（视口内 = [0,%.0f]×[0,%.0f]）"
			% [vp.x, vp.y, lo.x, hi.x, lo.y, hi.y, vp.x, vp.y])
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	cam.queue_free()
	await get_tree().process_frame
	if img == null:
		return null
	img.convert(Image.FORMAT_RGBA8)
	# ★ 按 **W:H 比例居中裁剪**再缩放 —— ⛔ 不能直接 `resize(W, H)`。
	#   实测 `DisplayServer.window_set_size()` 请求**没生效**，视口是 1600×1000（比例 1.60），
	#   而 W:H = 480:540 = 0.89 ⇒ 直接 resize 会把画面**横向压扁 1.8 倍**，
	#   细节被抹平（细长光刃最吃亏），而且"拍到了"与"没拍到"的差别会被糊掉。
	var vp := Vector2(img.get_width(), img.get_height())
	var ar := float(W) / float(H)
	var cw := vp.x
	var ch := cw / ar
	if ch > vp.y:
		ch = vp.y
		cw = ch * ar
	var rect := Rect2i(Vector2i(roundi((vp.x - cw) * 0.5), roundi((vp.y - ch) * 0.5)),
		Vector2i(roundi(cw), roundi(ch)))
	var sub := img.get_region(rect)
	sub.resize(W, H, Image.INTERPOLATE_LANCZOS)
	return sub


## 极简 5×7 点阵（工具自包含、不引字体资源）。
func _draw_text(img: Image, x: int, y: int, text: String) -> void:
	if img == null:
		return
	var glyphs := {
		"无": ["10101", "10101", "10101", "10101", "10101", "10101", "10101"],
		"刀": ["11111", "10001", "11111", "10001", "11111", "10001", "10001"],
		"亮": ["01000", "11111", "00000", "01110", "10001", "11111", "10001"],
		"斩": ["11111", "00010", "00100", "01000", "10000", "11111", "00000"],
		"＋": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
	}
	var cx := x
	for ch in text:
		var rows: Array = glyphs.get(ch, glyphs["刀"])
		for ry in rows.size():
			var row: String = rows[ry]
			for rx in row.length():
				if row[rx] != "1":
					continue
				for dy in 2:
					for dx in 2:
						var px := cx + rx * 2 + dx
						var py := y + ry * 2 + dy
						if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
							img.set_pixel(px, py, Color(1, 1, 1))
		cx += 2 * 5 + 4
