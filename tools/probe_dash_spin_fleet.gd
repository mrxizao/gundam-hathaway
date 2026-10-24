extends Node3D
## 「谁做左右冲刺转身」—— **跨机体**判据探针（2026-09-29 · N53 / N53b）。
##
## 用户原话：「除了柯西以外的其他机体都不做翻滚转身」；
## 同日追加：「阿利宙斯可以做左右冲刺转身」。
##
## ## 被验的东西只有一行配置
## `SuitProfile.dash_spin_visual`：默认 `false`，显式打开的只有
## **`SuitProfile.xi()`** 与 **`SuitProfile.arizeus()`** 两处；
## 消费点也**唯一** = `FlightBody._start_dash_spin()` 的早退。
##
## ## 但它难在「证明一件没发生的事」
## 「不转」至少有**四种**成因，读数全是 0，肉眼与断言都分不开：
##   ① 开关关着（我们要的）；② 模型没加载（`model_visible()` 早退）；
##   ③ 没进平移模式（压根没走到起手）；④ 这一记没被判成横向（`lat` 不够大）。
## ⇒ **单看「角度 == 0」是恒真断言**（T35：没有证伪条的断言 = 恒真断言）。
##
## ## 所以每台机体都在**同一个节点、同一份 model** 上跑两轮，B 组 = **把开关翻转**
##   · **A 组** = 配置原值 —— 这轮的**交付判据**；
##   · **B 组** = 把该 profile **副本**的 `dash_spin_visual` **取反**再跑一遍 —— **证伪条**。
##
##   ⇒ 一条统一规则：**A 与 B 必须在「转 / 不转」上相反**。
##     · **期望转**的机体（柯西 / 阿利宙斯常态 / 核心量产牛）：`A > 5.5` **且** `B ≈ 0`；
##     · **期望不转**的机体（佩涅罗佩 / 古斯塔夫 / 梅萨）：`A ≈ 0` **且** `B > 5.5`。
##
##   ★ 这比"只把开关打开"强一档：**两个方向都被证明**。只测"关→开能转"，
##     说明不了"开着的那些真的是这行配置在起作用"；现在柯西的 B 组必须**停住**，
##     才证明它那 6.283 是这行配置给的，而不是别的什么把它转起来的。
##
##   ★ 任一侧不符 ⇒ 探针红，并把 `ready / model_visible / translate_mode` 打出来。
##     `B` 该转却没转 ⇒ 这台机压根没走到那一步（②③④ 之一）⇒ A 的读数**不成立为证据**。
##
##   ⚠️ **期望值写死在 `CASES` 里**，⛔ 不从 `dash_spin_visual` 推 —— 从被测对象推期望
##      就是把被测对象当判据：配置一改错，判据跟着一起错，**永远绿**。
##
##   ⚠️ **一个例外，且有独立判据**：阿利宙斯**巡航形态**在
##      `PlayerController.assist_uses_translation()` 里恒为 `false` ⇒ 它**根本不进平移模式**
##      ⇒ `_apply_translate()` 不跑 ⇒ 转身窗口连"被写入"的机会都没有。
##      对这种机体 A 与 B **都是 0**（那不是"没测到"，是"这条路不存在"）
##      ⇒ 判据输出 `N/A` 并额外断言「确实没进平移模式」。⛔ 不并进上面那条。
##      ★ 这也正是 `arizeus()` **不按形态分支**写 `true` 的原因：约束的真源留在
##        `assist_uses_translation()` 那一处，判据用 `N/A` 表达"不适用"，**不靠配置表达**。
##
##   ⚠️ B 组只改**内存里的 profile 对象**，⛔ 一个字节都不碰工程文件；
##      跑完立刻改回原值（这台机的 `pc` 随即 `queue_free()`）。
##
## ## 出图（**4 列**：`A@3 | A@9 | A@15 | B@15`）
## 俯视机位（`up = −Z` ⇒ 屏幕上方 = 世界前）：**机头在水平面里扫一圈是俯视图最擅长的读数**，
## 追尾机位会被"机头被速度矢量拽着偏"掩盖（`dash_spin_shot.gd` 的结论）。
## 前 3 格 = A 组窗口内第 3 / 9 / 15 帧（实测扫到 ≈ 32° / 131° / 248°）；
## 第 4 格 = B 组（开关取反后）**同一帧 15** ⇒ 每排自带对照：
##   前 3 格在变、第 4 格是 0°   ⇒ 「A 在转、翻掉就停」；
##   前 3 格一致（0°）、第 4 格转 ⇒ 「A 不转、翻掉才转」。
##
## ⚠️ 图证只用**每格拍下时的角度**（控制台 `[图证]`），⛔ 不用"相邻格逐像素差"：
##    本场景机体带引擎焰与粒子，逐像素差被尾焰主导 —— 实测「同朝向两格」与
##    「差 248° 两格」落在同一量级（0.0307 vs 0.0290），**分不开**。
##
## ## 跑法（**不能加 `--headless`**：dummy 渲染器抓出来是空图）
##   godot --path <工程> --fixed-fps 60 res://tools/probe_dash_spin_fleet.tscn -- <输出目录>
##   ⚠️ headless 下探针会**自动降级**成只读数、不出图（判据一条不少，且快得多）。

const W := 420
const H := 460
## 拼图列数：`A@3 | A@9 | A@15 | B@15`（`_sheet()` 与 `_burst()` 的采样表必须一致）。
const COLS := 4
## 俯视相机的离地高度（正交投影 ⇒ 只影响裁切面，不影响大小）。
const TOP_DIST := 260.0
## 出图时的机体**锚点**。每帧把机体钉回这里 —— 见 `_burst()` 里的说明。
const ORIGIN := Vector3(0.0, 3000.0, 0.0)
## 等就绪的帧数上限：真模型（含剥离后的 glb）在这一档内加载完，实测远小于它。
const READY_MAX := 300
## 就绪后额外再等几帧，让物理/形态插值落到稳态。
const STABLE := 30
## 两轮之间回正的空档。转身窗口 0.45 s = 27 帧，留 40 帧有余量。
const GAP := 40
## A 组的采样帧（`request_quick_boost()` 之后第几帧）—— 与注释里的角度同步改。
## ⚠️ 必须在**同一记冲刺**里取，跨记取到的是两次不同的扫角，**画面上分不出来**。
const SAMPLE_AT := [3, 9, 15]
## 「真的转了」的门限（弧度）。与 `tests/suite_assist_drive.gd` 同源（5.5 rad ≈ 315°）。
const SPIN_MIN := 5.5

## 期望值的显示文本（只用于控制台，判据读的是 `CASES` 里的整数）。
const EXPECT_TEXT := {1: "转", 0: "不转", -1: "N/A"}

## [显示名, `SuitProfile.Id` 的整数值, form（−1 = 走 `by_id`）, 期望（1 转 / 0 不转 / −1 N/A）]
##   `enum Id { XI, PENELOPE, ARIZEUS, GUSTAV00, MESSER_M01 }`
##   `enum ArizeusForm { CRUISE, NORMAL, CORE_NU }`
##
## ⚠️ **期望值写死在这里**（不从 `dash_spin_visual` 推）：从被测对象推期望
##    就是把被测对象当判据 ⇒ 配置改错了判据跟着一起错、**永远绿**。
## ⚠️ 阿利宙斯**巡航形态**标 `−1`（N/A）是**结构**造成的，不是配置造成的 ——
##    见文件头「一个例外，且有独立判据」。
const CASES := [
	["柯西", 0, -1, 1],
	["佩涅罗佩", 1, -1, 0],
	["阿利宙斯常态", 2, 1, 1],
	["阿利宙斯巡航", 2, 0, -1],
	["核心量产牛", 2, 2, 1],
	["古斯塔夫00", 3, -1, 0],
	["梅萨M01", 4, -1, 0],
]

var out_dir := "user://probe_dash_spin_fleet"
var _cam: Camera3D
var _ok := true
## 能不能抓画面。`--headless` 下 dummy 渲染器抓出来是**纯黑**（且会让每帧变慢得多，
## 实测 7 台要 15 分钟）⇒ 自动降级成**只读数不出图**，判据一条不少。
var _can_shoot := true


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = str(args[0])
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(W, H))
	_build_env()
	await get_tree().physics_frame

	# ⚠️ 用真模型跑（不是占位盒）：占位盒的 `model_visible()` 恒 true，
	#   会把"模型没加载"这条失效路径**掩盖**掉，而它正是本探针要排除的四种成因之一。
	FlightBody.use_placeholder = false

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.05
	_cam.far = 4000.0
	_cam.current = true
	add_child(_cam)

	print("=== 「谁做左右冲刺转身」跨机体判据（%d 台）===" % CASES.size())
	print("  ★ 判据：B 组 = 把开关**取反** ⇒ **A 与 B 必须在「转/不转」上相反**：")
	print("      期望转的（A > %.1f）翻掉必须≈0；期望不转的（A ≈ 0）翻掉必须 > %.1f。" % [SPIN_MIN, SPIN_MIN])
	print("  ⚠️ 期望值写死在 CASES 里，**不从配置推**（推了就永远绿）。" )
	_can_shoot = DisplayServer.get_name() != "headless"
	if not _can_shoot:
		print("  ⚠️ headless 模式 ⇒ 只读数、不出图（dummy 渲染器抓出来是黑图）")
	print("  %-14s %-5s %-5s %-6s %8s %8s   %s" % [
		"机体", "配置", "期望", "就绪", "A(rad)", "B(rad)", "判定"])

	var rows: Array = []
	for ci in CASES.size():
		var c: Array = CASES[ci]
		var label: String = str(c[0])
		var expect := int(c[3])
		var prof := _profile(int(c[1]), int(c[2]))
		var r := await _run(label, prof, expect)
		rows.append(r)
		if r == null:
			_ok = false
			print("  %-14s —— 读数缺失（`_run` 抛错，见上面 SCRIPT ERROR）" % label)
			continue
		var verdict := _verdict(r)
		# ⚠️ `N/A`（结构上不适用）**不算红**，但必须打出来 —— 静默跳过就是另一种失效。
		if not verdict.begins_with("OK") and not verdict.begins_with("N/A"):
			_ok = false
		print("  %-14s %-5s %-5s %-6s %8.3f %8.3f   %s" % [
			label, "true" if bool(r["cfg"]) else "false",
			str(EXPECT_TEXT.get(expect, "?")),
			"%d帧" % int(r["ready_frames"]),
			float(r["a"]), float(r["b"]), verdict])
		if not bool(r["ready"]):
			print("      ⚠️ 这台没就绪（model_visible=%s translate_mode=%s）⇒ A 组的 0 **不成立为证据**"
				% [str(r["model_visible"]), str(r["translate"])])
		var piv := ", ".join(PackedStringArray([
			"A·pivot %.1f°" % float(r["a_pivot"]), "B·pivot %.1f°" % float(r["b_pivot"])]))
		print("      （被消费层 `spin_pivot.rotation_degrees.y` 峰值：%s）" % piv)

	# ---- 拼图：每台**一排 4 格** = A 组 3 帧 ＋ B 组（开关取反后）的同一末帧 ----
	#   ⇒ 每排**自带对照**，不用再单独排一行证伪条（旧版是"一律打开"，只有一台能对照）。
	var sheet_rows: Array = []
	for r in rows:
		if r == null:
			continue
		var sa: Array = r["snaps"]
		if sa.is_empty():
			continue
		sheet_rows.append({
			"label": str(r["label"]),
			"imgs": sa + (r["snaps_b"] as Array),
		})
	var out := out_dir.path_join("dash_spin_fleet.png")
	print("")
	if sheet_rows.is_empty():
		# ⚠️ `Image.create(w, **0**)` 会直接报 `The Image height specified (0 pixels)
		#    must be greater than 0`（`_sheet()` 里 `H * n`）⇒ 空表必须在这里挡住。
		#    走到这里 = headless（自动降级）⇒ 不是错误，只是没图。
		print("SHOT 跳过（没有可拼的画面）：headless / 全部机体都没抓到帧")
	else:
		var sheet := _sheet(sheet_rows)
		var err := sheet.save_png(out)
		print("SHOT %s err=%d（%d 排 × %d 格）" % [out, err, sheet_rows.size(), COLS])
	# ⚠️ GDScript **没有列表推导**（`[x for i in n]` 会报 `Expected closing "]"`）⇒ 老实写循环。
	var labels: Array = []
	for i in sheet_rows.size():
		labels.append("%d.%s" % [i + 1, str(sheet_rows[i]["label"])])
	print("  行序：%s" % " | ".join(PackedStringArray(labels)))
	print("  读法：俯视机位、屏幕上方 = 世界前。格 0/1/2 = A 组窗口内第 3/9/15 帧，第 4 格 = B 组（开关取反后）同帧 15。")
	print("        ★ 判别只看**前 3 格彼此**：三格机头指向递变 ⇒ A **在转**；三格基本重合 ⇒ A **不转**。")
	print("        ★ 第 4 格是**对照**（两种排都应与前 3 格不同）：期望不转的排用它证明「这台机**能**转，只是配置关着」。")
	print("        ⚠️ 图上分不出「没转」与「没拍上」⇒ 每排另配 `[图证]`（采样帧角度 ＋ 相邻格平均像素差）。")
	print("VERDICT: %s" % ("DASH-SPIN-FLEET-OK" if _ok else "DASH-SPIN-FLEET-BAD"))
	print("DASH_SPIN_FLEET_DONE -> ", out_dir)
	get_tree().quit(0 if _ok else 1)


## 逐台判定。**返回文本里必须体现"凭什么"** —— 只说 OK 的判据，红了没法定位。
## ⚠️ 参数故意**不标类型**：`_run()` 抛错时会返回 `null`，标了 `Dictionary` 连
##    调用处都会炸在类型检查上，反而看不到"读数缺失"这句人话。
func _verdict(r) -> String:
	if r == null or not (r is Dictionary) or not r.has("ready"):
		return "BAD 无读数"
	if not bool(r["ready"]):
		return "BAD 未就绪 ⇒ A 组不可采信"
	# ★ 结构上不进平移模式的机体（阿利宙斯巡航形态）：**单独一条判据**。
	#   ⛔ 不并进下面那条 —— 它的 B 组也必然不转，并进去就会被读成"探针没测到"。
	if not bool(r["want_translate"]):
		if bool(r["translate"]):
			return "BAD 声明不进平移模式却进了"
		return "N/A 不进平移模式（结构上不会转身）"
	var a := float(r["a"])
	var b := float(r["b"])
	# ★ 判据读的是**写死的期望值**，⛔ 不是配置 —— 从被测对象推期望 = 判据永远绿。
	var expect := int(r["expect"])
	if expect == 1:
		# 期望转：A 必须真的转，**且把开关翻掉必须停住**（证明这行配置就是成因）。
		if a <= SPIN_MIN:
			return "BAD 应转却没转（A=%.3f）" % a
		if b > 1.0e-9:
			return "BAD 翻掉开关后仍在转（B=%.6f）⇒ A 的转不是这行配置给的" % b
		return "OK 应转：A 真转（%.3f）＋ 翻掉就停" % a
	if expect != 0:
		return "BAD `CASES` 里的期望值写了 %d（只认 1/0/−1）" % expect
	# 期望不转：A 必须精确 0，**且把开关翻上去必须真的转**（否则那个 0 不成立为证据）。
	if a > 1.0e-9:
		return "BAD A 组不该转却转了（%.6f）" % a
	if b <= SPIN_MIN:
		return "BAD B 组翻上去也没转 ⇒ A 的 0 不是证据"
	return "OK 不应转：A=0 ＋ 翻上去真转（%.3f）" % b


func _profile(id: int, form: int) -> SuitProfile:
	if form >= 0:
		return SuitProfile.by_id_form(id, form)
	return SuitProfile.by_id(id)


## 一台机体：装一次、跑 A 组（配置原值）→ 空档 → 跑 B 组（开关**取反**）→ 释放。
func _run(label: String, base: SuitProfile, expect: int) -> Dictionary:
	var holder := Node3D.new()
	add_child(holder)
	var pc := PlayerController.new()
	pc.name = "SpinProbe"
	pc.profile = base
	pc.is_player = true
	pc.team = 0
	pc.controls_enabled = true
	holder.add_child(pc)
	pc.assist_on = true
	pc.global_position = ORIGIN

	# ⚠️ 这两个必须在**就绪循环之前**声明：GDScript 局部变量是**顺序解析**的，
	#    写在循环下面会报 `Identifier "want_translate" not declared in the current scope`。
	var cfg: bool = base.dash_spin_visual
	# ★★ 有一台机体**结构上**到不了转身那条路：`assist_uses_translation()` 对
	#    **阿利宙斯巡航形态**恒返回 `false` ⇒ 不进平移模式 ⇒ `_apply_translate()`
	#    不跑 ⇒ 转身窗口永不开启（`dash_spin` 连被写入的机会都没有）。
	#    对这种机体，B 组（开关**取反**）**也**不会转 —— 那不是"没测到"，而是"这条路不存在"。
	#    ⛔ 混在一起判会把 N/A 读成红：判据必须能表达"不适用"。
	var want_translate: bool = PlayerController.assist_uses_translation(base, false)

	# ---- 等就绪：**轮询**而不是写死帧数（写死既慢又会在慢机上假红）----
	# ⚠️ 就绪条件要按这台机**该不该进平移模式**分：给"结构上不进"的机器
	#    等 `translate_mode` 会白等满 `READY_MAX` 帧，而且等到了才是异常。
	var ready := false
	var rf := 0
	for i in READY_MAX:
		await get_tree().physics_frame
		rf = i + 1
		if pc.model_visible() and (pc.translate_mode or not want_translate):
			ready = true
			break
	for i in STABLE:
		await get_tree().physics_frame
	# ---- 相机：挂在机体下、**每帧**对齐它正上方（见 `_process()`）----
	#
	# ⛔ 不要"设一次相机位置就完事"。`await RenderingServer.frame_post_draw`
	#    **可能跨帧**（本帧的 post_draw 已经发过 ⇒ 等下一次），中间插进一整个迭代
	#    （physics + process）⇒ 机体又跑了 58 m，而正交取景只有 ~40 m 宽 ⇒ **整机出画**。
	#    本轮前两版就是这么翻的：**读数分毫不差、图上整排是空的**，光看数字发现不了。
	# ✅ 位置**每帧**由 `pc.global_position` 现算 ⇒ 渲染用哪一帧就跟哪一帧。
	# ✅ 转身是**纯视觉层**（`spin_pivot`），与机体在哪无关 ⇒ 每帧钉住机体位置
	#    （`_burst()` 里）不改判据的任何一位，只让画面背景稳定。
	_attach_cam(pc)
	# 取景**该台共用**（按**静止**包围盒定死）：若按每格自己的包围盒取景，
	# 缩放会跟着变，"看起来在转"与"看起来被放大了"就分不出来（`dash_spin_shot.gd` 的教训）。
	var mb: AABB = pc.model_bounds
	_cam.size = maxf(maxf(mb.size.x, mb.size.z), 1.0) * 1.45

	# ---- A 组 ----
	# ⚠️ 阿利宙斯巡航形态**不出图**：它不进平移模式（`N/A`），真跑时无输入会掉高度，
	#    拍到的多半是空画面 —— 出它反而让人以为"这里没测"。
	#    ⇒ 出一台"没有画面的排"不如不出，`_ready()` 的拼图会跳过空排。
	# ⚠️ 采样表要在**声明之后**用（GDScript 局部变量顺序解析）：`at_a` 放在这里。
	var at_a: Array = SAMPLE_AT if want_translate else []
	var a := await _burst(pc, at_a)
	var snaps_a: Array = a["snaps"]
	if _can_shoot and not snaps_a.is_empty():
		# ★ 自证读数：判据图上的"整排是空的"与"这台机没转身"**在图上分不出来**，
		#   必须另有一个数 —— 本轮前两版就是图像全空、读数全对，光看数字发现不了。
		print("      [自证] 采样时机体 %s（cam.size=%.1f）" % [_offscreen_probe(pc), _cam.size])
	# ★★ 相机自证（**无论能不能抓图都打**）："图是空的"有至少四种成因（相机停在原点 /
	#    current 被抢 / 取景尺寸离谱 / 机体确实不在画面里），四种的图**长得一模一样**。
	#    这四个读数能把它们一次分开。
	print("      [相机] gp=%s size=%.1f current=%s 视口相机一致=%s ｜ 机体 gp=%s" % [
		str(_cam.global_transform.origin), _cam.size, str(_cam.current),
		str(get_viewport().get_camera_3d() == _cam), str(pc.global_position)])
	for i in GAP:
		await get_tree().physics_frame
	# ---- B 组（证伪条）：把开关**取反**（⛔ 不是一律打开）----
	#   ★ 期望转的机体 ⇒ 取反后必须**停住**；期望不转的 ⇒ 取反后必须**转起来**。
	#     两个方向都被证明，才排除"这台机压根走不到这条路"（T35：没有证伪条的断言 = 恒真断言）。
	#   ★ B 组只采**末帧**（`SAMPLE_AT` 的最后一格）：用来与本排第 2 格（A@末帧）直接对照。
	base.dash_spin_visual = not cfg
	var at_b: Array = [SAMPLE_AT[SAMPLE_AT.size() - 1]] if want_translate else []
	var bv := await _burst(pc, at_b)
	var snaps_b: Array = bv["snaps"]
	base.dash_spin_visual = cfg
	# ★★ 【图证】判据图**自己**要能被验：图上的"整排一模一样"与"这台机没转身"
	#    在**图上分不出来**（T49 的老坑：读数一位不差、图整排是空的）。
	#    ⇒ 把"每格拍下时转了多少度"一起打出来 ⇒ 判据图**自带刻度**：
	#      格 0/1/2 的角度明显递增、而图上三格却长得一样 ⇒ **图骗了你**（出画 / 没拍上）。
	#    ⛔ 这里**不用**"相邻格逐像素差"当图证 —— 试过，本场景不可用：机体带引擎焰与
	#       粒子，逐像素差被尾焰主导。实测佩涅罗佩「同朝向两格」0.0307、
	#       「差 248° 两格」0.0290 —— **同一量级，分不开**（而柯西那排也不过 0.053）。
	#       图证必须选**被转身支配**的量，不是全画面的量。
	if _can_shoot and not (a["angles"] as Array).is_empty():
		print("      [图证] 每格拍下时的 `dash_spin`：A=%s° ｜ B=%s°（图上应能看到这个角差）" % [
			_deg_list(a["angles"]), _deg_list(bv["angles"])])
	# ⚠️ 这两个读数必须在 `queue_free()` **之前**取：free 之后 `pc` 是
	#   `previously freed`，读它会报 `Nonexistent function in base 'previously freed'`
	#   —— 而那个错**只中断当前函数**，`_run()` 于是返回 `null`，
	#   上层拿 `null` 当字典用又是一串错，整条链的读数**全丢**（本轮第一次跑就是这么翻的）。
	var mv := pc.model_visible()
	var tm := pc.translate_mode
	# ⚠️ 相机是 `pc` 的子节点 ⇒ 必须**先摘下来**再 free，否则连相机一起被回收，
	#   下一台机体就没有渲染源了（而且不报错，只是全黑）。
	_detach_cam()
	holder.queue_free()
	await get_tree().physics_frame
	return {
		"label": label, "cfg": cfg, "expect": expect,
		"ready": ready, "ready_frames": rf,
		"want_translate": want_translate,
		"model_visible": mv, "translate": tm,
		"a": a["peak"], "a_pivot": a["pivot"],
		"b": bv["peak"], "b_pivot": bv["pivot"],
		"snaps": snaps_a, "snaps_b": snaps_b,
	}


## 真跑一记向左冲刺，量窗口内 `dash_spin` 与**被消费层**（`spin_pivot.rotation_degrees.y`）峰值。
##
## ⚠️ 走的是生产链路：`Input`（roll_left）+ `request_quick_boost()` ⇒ `_apply_translate()`
##    ⇒ `_start_dash_spin(_qb_dir)` ⇒ `_dash_spin_t = QB_TIME` ⇒ 逐帧推进。
##    ⛔ 直接写 `pc.dash_spin` 只能证明"赋值能生效"，与本轮改的那个开关无关。
##
## `at` = 要抓图的帧号列表（`[]` ⇒ 一轮下来不抓图，但峰值照量）。
##   两轮传**不同的表**：A 组要 3 帧看推进，B 组只要末帧做对照。
func _burst(pc: FlightBody, at: Array) -> Dictionary:
	var peak := 0.0
	var pivot := 0.0
	var snaps: Array = []
	var angles: Array = []
	Input.action_press("roll_left")
	for i in 6:
		await get_tree().physics_frame
		pc.global_position = ORIGIN
	pc.request_quick_boost()
	for i in 36:
		await get_tree().physics_frame
		# ★ **钉住位置**：转身窗口的推进（`_dash_spin_t -= delta`）与位移无关，
		#   `_start_dash_spin()` 的横向判定也只读 `global_transform.basis` 与 `_qb_dir`
		#   ⇒ 钉住它**不改判据的任何一位**，只让相机不用追一个每帧跑 58 m 的目标。
		#   ⛔ 钉的是 `global_position`（不动 `velocity`）：`move_and_slide()` 照跑。
		pc.global_position = ORIGIN
		peak = maxf(peak, absf(pc.dash_spin))
		if pc.spin_pivot != null and is_instance_valid(pc.spin_pivot):
			pivot = maxf(pivot, absf(pc.spin_pivot.rotation_degrees.y))
		if _can_shoot and at.has(i):
			await RenderingServer.frame_post_draw
			var im := get_viewport().get_texture().get_image()
			if im != null:
				im.convert(Image.FORMAT_RGBA8)
				# ⚠️ `window_set_size()` 在 Windows 上会被 DPI 顶掉 ⇒ 必须缩放到目标尺寸，
				#   否则拼图各格宽度不一致（`blit_rect` 会直接报格式/尺寸错）。
				im.resize(W, H, Image.INTERPOLATE_LANCZOS)
				snaps.append(im)
				# ★ 把"这一格拍的时候转了多少度"一起记下来 ⇒ 判据图**自带刻度**：
				#   格 0/1/2 的角度若明显递增，而图上三格却长得一样 ⇒ **图骗了你**（出画/没拍上）。
				angles.append(rad_to_deg(absf(pc.dash_spin)))
	Input.action_release("roll_left")
	return {"peak": peak, "pivot": pivot, "snaps": snaps, "angles": angles}


## 世界正俯视的相机基：绕 X 转 −90° ⇒ 视线朝 **−Y**，相机自身的 up（+Y）被送到 **−Z**
## ⇒ 屏幕上方 = 世界前（"机头朝上"就是 0°，读图最省事）。
## ⚠️ 用 `looking_at()` 会与视口里的 `Vector3.UP` **共线**而当场被拒（相机停在原点、
##    不报错）—— 直接给基，绕开这个坑（`dash_spin_shot.gd` 踩过）。
var _top_basis := Basis(Vector3(1.0, 0.0, 0.0), -PI / 2.0)


## 相机每帧对齐到**机体正上方**。
##
## ## 位置为什么必须每帧现算
## `_burst()` 里 `await RenderingServer.frame_post_draw` **可能跨帧**（本帧的
## post_draw 已发过 ⇒ 等下一次）⇒ 中间插进一整个迭代（physics + process）⇒
## 机体又跑了 58 m。**只在采样前设一次相机**的写法在这里必然出画，而且
## **读数照旧全对** —— 本轮前两版就是这么翻的。
## ⇒ 每帧由当前 `pc.global_position` 现算：渲染用哪一帧，相机就跟到哪一帧。
##
## ## 朝向为什么不跟着机体
## `pc` 冲刺时会俯仰/压坡（`_hover_pose` 约 18° 前倾）。跟着它拍出来是斜视角，
## 「机头在水平面里扫一圈」就读不出来了 ⇒ 朝向固定用 `_top_basis`。
func _process(_delta: float) -> void:
	if _cam == null or not is_instance_valid(_cam):
		return
	var host := _cam.get_parent() as Node3D
	if host == null or host == self:
		return
	_cam.global_transform = Transform3D(_top_basis,
		host.global_position + Vector3(0.0, TOP_DIST, 0.0))


## 把相机挂到机体下（⇒ 渲染时刻的位置天然同步），离开时再挂回来。
##
## ⚠️⚠️ **这里踩过一个"两个条件正好写反"的坑**：第一版写成
##     `if 父 != null and 父 != self: 父.remove_child(...)` —— 可**父就是 `self` 时
##     才是最需要摘的那种**。于是 `remove_child` 没执行，`add_child` 直接报
##     `Can't add child … already has a parent`，**而那是非致命错误**：脚本继续跑、
##     读数一位不差（`dash_spin` 6.283 / 0.000）、只有**图是空的**。
##     ⇒ 摘除一律"**有父就摘**"，摘完再挂；挂完再校验一次并 `push_error`。
func _attach_cam(pc: FlightBody) -> void:
	var par := _cam.get_parent()
	if par != null:
		par.remove_child(_cam)
	pc.add_child(_cam)
	_cam.position = Vector3(0.0, TOP_DIST, 0.0)
	_cam.rotation = Vector3.ZERO
	_cam.current = true
	if _cam.get_parent() != pc:
		push_error("[N53] 相机挂载失败 ⇒ 判据图会是空的（**读数不受影响，所以只能靠这一句发现**）")


func _detach_cam() -> void:
	var par := _cam.get_parent()
	if par != null:
		par.remove_child(_cam)
	add_child(_cam)
	_cam.position = Vector3.ZERO
	_cam.rotation = Vector3.ZERO


## 当前姿态下机体**有没有出画**的自证读数（世界水平偏移，米）。
##
## ⚠️ 判据图上"整排是空的"与"这台机没转身"是**两回事**，图上分不出来
##    —— 必须另给一个数。`max(x, z)` 取包围盒水平跨度，`cam.size` 是视口**高**，
##    视口宽 ≈ `cam.size × (W/H)`；只要水平偏移 < 半个视口宽就还在画面里。
func _offscreen_probe(pc: FlightBody) -> String:
	var ba := _body_aabb(pc)
	var d := ba.get_center() - ORIGIN
	var half_w: float = _cam.size * float(W) / float(H) * 0.5
	return "偏移(dx=%.1f dz=%.1f 米) ｜ 半视口宽 %.1f 米 ⇒ %s" % [
		d.x, d.z, half_w, "在画面内" if absf(d.x) < half_w and absf(d.z) < half_w else "**出画**"]


## 把角度数组拼成 `"32,131,248"` 这种人读文本（空数组给 `"—"`）。
func _deg_list(a: Array) -> String:
	if a.is_empty():
		return "—"
	var parts: Array = []
	for v in a:
		parts.append("%.0f" % float(v))
	return ",".join(PackedStringArray(parts))


## 机体**世界**可见几何的包围盒（`model_root` 下所有可见 `MeshInstance3D`）。
##
## ⚠️ **不参与取景**（取景固定不动，见 `_run()` 里的说明）。留在这里只为上面那条
##    自证读数 —— 本轮前两版的教训就是"图上空白"没有任何数字能对照。
func _body_aabb(pc: FlightBody) -> AABB:
	var out := AABB()
	var first := true
	for c: Node in pc.model_root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


## `COLS` 列拼图。`rows[i] = {"label": String, "imgs": Array[Image]}`。
## 行宽按 `COLS` 定死（**不是**按 `imgs.size()`）：某台机缺图时不会把排版挤乱。
func _sheet(rows: Array) -> Image:
	var n := rows.size()
	var sheet := Image.create(W * COLS, H * n, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.07, 0.08, 0.10))
	for ri in n:
		var r: Dictionary = rows[ri]
		var imgs: Array = r["imgs"]
		for k in imgs.size():
			if k >= COLS:
				break
			var img: Image = imgs[k]
			if img == null:
				continue
			sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i(k * W, ri * H))
		# 只画数字（点阵字体只有数字与负号）⇒ 行号 + 格号，行序在控制台里对照。
		_draw_text(sheet, 12, ri * H + 12, str(ri + 1))
		for k in imgs.size():
			if k >= COLS:
				break
			_draw_text(sheet, k * W + 12, ri * H + 30, str(k))
	for k in range(1, COLS):
		sheet.fill_rect(Rect2i(k * W, 0, 2, H * n), Color(0.42, 0.48, 0.58))
	for ri in range(1, n):
		sheet.fill_rect(Rect2i(0, ri * H, W * COLS, 2), Color(0.42, 0.48, 0.58))
	return sheet


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
	key.rotation_degrees = Vector3(-52.0, 20.0, 0.0)
	key.light_energy = 1.8
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12.0, 200.0, 0.0)
	fill.light_energy = 0.6
	fill.light_color = Color(0.74, 0.84, 1.0)
	add_child(fill)


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
