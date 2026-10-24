class_name SuiteBoostShake
extends RefCounted
## **量产机槽空时镜头剧烈晃动**（2026-10-08 · 用户实测盘上 bug）。
##
## ## 用户原话
##
## 「现在古斯塔夫和梅萨系列这些量产机机体在气槽没气的时候镜头会剧烈晃动，
##   我需要你把这个剧烈晃动删了」
##
## ## 根因（不在相机里，在"输入读取 / 燃料槽裁决"的**同帧顺序**上）
##
## `PlayerController._read_flight_input()` 原来那一句是
## 「想加速 且 当前 `fm.boosting` 为假 ⇒ `camera.add_shake(0.12)`」，
## 本意是"这一帧**刚按下** Shift ⇒ 给一记点火轻推"。但它把 `fm.boosting`
## 当**上一帧的意图**读，而 `fm.boosting` 在**同一物理帧稍后**会被
## `FlightBody.resolve_jet_gauge()` **改写**
##（`flight_body.gd:874`：槽空 + 想加速 ⇒ `fm.boosting = jet_active = false`）。
##
## 于是量产机槽空还按着 Shift 时：
##
##   帧 N  ：`_read_flight_input` 读到 `fm.boosting == false` ⇒ **抖一记**，随后写 true；
##           `resolve_jet_gauge` 当帧把它压回 false。
##   帧 N+1：一模一样 ⇒ **帧帧抖一记**。
##
## 抖动池每帧 +0.12（= 7.2/s）远超 `_apply_shake()` 的 2.4/s 线性衰减
## ⇒ `_shake` 一路顶死在 **1.4（击坠级上限）** 并停在那儿 —— 这就是"剧烈晃动"。
##
## **为什么只有量产机**：ACE 机没有燃料槽，`resolve_jet_gauge()` 在
## `flight_body.gd:800` 就提前 return、**一个字都不改 `fm.boosting`**
## ⇒ 那条门只在按下 Shift 的当帧成立一次。与用户"只有古斯塔夫和梅萨系列"完全对上。
##
## ## 修法
##
## 触发改读**按键沿**（`Input.is_action_just_pressed("boost")`）：**一按一记**，
## 与槽满槽空无关；并补一条"槽空时不给点火确认"（本来就没点着火）。
##
## ## ⚠️ 本套件为什么必须有 §2 的那条「前提」
##
## 只断言"60 帧后 `_shake` 很小"是**可能空测的** —— 把抖动通道整个删掉它照样绿。
## 所以先证明**旧表达式的条件在这 60 帧里真的成立了几十次**
##（`Input.is_action_pressed` 在无头下可靠，先例见 `suite_assist_drive.gd:963`）
## ⇒ 旧代码在这些帧上必然帧帧抖一记，读数一定是 1.4。
## 两句一起才构成判据：**"旧写法会炸" + "新写法不炸"**。

const DT := 1.0 / 60.0
## 60 帧 = 1.0 s。够长：旧写法在 0.2 s 内就会把 1.4 的池子灌满。
const FRAMES := 60
## 点火那一记的名义幅度（`player_controller.gd` 里的字面量）。
const TAP := 0.12
## `_shake` 的池上限 = 击坠级（`chase_camera.gd:1033` 的 `minf(..., 1.4)`）。
const SHAKE_CAP := 1.4


static func run(t: T, host: Node) -> void:
	t.suite("BoostShake / ① 源码：点火抖动改读按键沿（旧写法已不在代码位）")
	_source(t)
	t.suite("BoostShake / ② 量产机（古斯塔夫）槽空 + 按住 Shift 60 帧 ⇒ 不再饱和")
	await _live(t, host, SuitProfile.gustav00(), "古斯塔夫", 0.0)
	t.suite("BoostShake / ③ 量产机（梅萨 M01）槽空 + 按住 Shift 60 帧 ⇒ 同上")
	await _live(t, host, SuitProfile.messer_m01(), "梅萨 M01", 0.0)
	t.suite("BoostShake / ④ 对照：槽满同一循环 ⇒ 裁决放行，读数同量级（不是通道哑了）")
	await _live(t, host, SuitProfile.gustav00(), "古斯塔夫（满槽）", 1.0)


# ================================================================ ① 源码

## 扫源码而不是只扫行为，是为了钉住**代码位**：
## 行为判据能证明"现在不炸"，但证明不了"旧写法回来了没有"（
## 复习：这份源码改回旧写法，§②/③ 会立刻红 —— 所以这一节是**双保险**，
## 顺带给出"改的是哪一行"的定位）。
##
## ⚠️ 匹配串带**前导 tab**：注释行是 `\n\t#`，永远匹配不上 `\n\tif ...`
## ⇒ 注释里怎么写那段历史都不会把这一节弄红（前一版我差点写成裸子串，会被自己的注释坑）。
static func _source(t: T) -> void:
	var src := FileAccess.get_file_as_string("res://scripts/flight/player_controller.gd")
	t.gt(float(src.length()), 1000.0, "读到 player_controller.gd（%d 字节）" % src.length())
	t.not_ok(src.contains("\n\tif want_boost and not fm.boosting"),
		"★ 旧写法（拿 `fm.boosting` 当「上一帧的意图」读）已不在**代码位** —— 它会被槽空裁决骗成帧帧成立")
	t.ok(src.contains("\n\tif Input.is_action_just_pressed(\"boost\") and not want_hover"),
		"★ 改成了按键沿（`is_action_just_pressed(\"boost\")` + 悬停门）")
	t.ok(src.contains("and (not has_jet_gauge() or jet_left > 0.0)"),
		"★ 而且槽空时**不给**点火确认（`has_jet_gauge()` / `jet_left` 门）")
	# 顺带钉住"抖动幅度没被顺手改"：修的是**触发次数**，不是把反馈删掉或调小。
	t.ok(src.contains("camera.add_shake(0.12)"),
		"点火那一记本身的幅度（0.12）没动 —— 本 bug 是「发了几次」，不是「一记多重」")
	# 机制前提的另一半：裁决确实会**改写** `fm.boosting`（否则上面那条门根本无从成立，
	# 本 bug 也就不存在 —— 这一条保证 §② 不是"在测一个不可能发生的场景"）。
	var fb := FileAccess.get_file_as_string("res://scripts/flight/flight_body.gd")
	t.ok(fb.contains("fm.boosting = jet_active"),
		"（前提）`resolve_jet_gauge()` 确实把裁决结果写回 `fm.boosting` —— 这是本 bug 的机制前提")
	t.ok(fb.contains("if not has_jet_gauge():") ,
		"（前提）ACE 机在它里面**提前 return** ⇒ 不写 `fm.boosting` ⇒ 只咬量产机")


# ================================================================ ②/③/④ 真机

## 造「一台量产机 + 一台进树的追尾相机」，然后**按产品顺序**跑 60 帧：
## `_read_flight_input()`（写 `fm.boosting`）→ `resolve_jet_gauge()`（槽空就压回 false）。
##
## ⚠️ 关掉 `pc` 的物理帧（`set_physics_process(false)`，与 `suite_ground_guard._stage` 同一手法）：
## 引擎自己跑的话帧数不可控，而"抖了几下"正是本套件要量的东西。
## ⚠️ 但**每帧仍然 `await` 一个真物理帧**：`Input.is_action_just_pressed()` 是按
## **引擎帧号**判的，不推帧的话它在循环里恒为真 ⇒ 新写法也会被灌到上限（假红）。
static func _live(t: T, host: Node, prof: SuitProfile, label: String, fuel_ratio: float) -> void:
	Game.reset()
	var c := Node3D.new()
	c.name = "BoostShakeStage"
	host.add_child(c)
	var cam := ChaseCamera.new()
	c.add_child(cam)
	cam.set_physics_process(false)   # 相机自己也不许跑（衰减由本套件显式驱动）
	cam.current = false              # 别跟真镜头抢"当前相机"
	var pc := PlayerController.new()
	pc.name = "BoostShakeProbe"
	pc.profile = prof
	pc.is_player = true
	pc.team = 0
	pc.projectile_container = c
	pc.camera = cam
	c.add_child(pc)
	pc.set_physics_process(false)
	pc.assist_on = false             # 手动飞行 ⇒ 走 `_read_flight_input()`（**默认**就是这条）
	await host.get_tree().physics_frame

	t.ok(pc.has_jet_gauge(), "（前提）%s 是**量产机**（有燃料槽）—— 这一族才会被裁决压回加力" % label)
	pc.jet_left = prof.jet_seconds * fuel_ratio
	pc.fm.boosting = false
	cam._shake = 0.0

	# ---- 按住 Shift，跑 60 帧 ----
	Input.action_press("boost")
	var held := 0
	var first_tap := -1.0
	for i in FRAMES:
		# ⚠️ **必须在调 `_read_flight_input()` 之前读** `fm.boosting`：
		# 旧表达式读的就是**函数入口**那个值（函数自己随后会把它写成 true）。
		# 在函数之后读 ⇒ 永远读到 true ⇒ 这条前提恒为 0 ⇒ **§② 变成空测**。
		var entry_boost: bool = pc.fm.boosting
		if Input.is_action_pressed("boost") and not entry_boost:
			held += 1
		pc.call("_read_flight_input", DT)
		if first_tap < 0.0 and cam._shake > 0.0:
			first_tap = cam._shake
		pc.resolve_jet_gauge(DT)      # 产品顺序：`_think()` 之后、`_apply_flight()` 之前
		await host.get_tree().physics_frame
	Input.action_release("boost")
	Input.action_release("hover")

	# ---- 前提：旧表达式的条件成立了几十次 ----
	var would_be := minf(TAP * float(held), SHAKE_CAP)
	print("[BoostShake] %s：fuel=%.0f%%｜旧表达式成立 %d/%d 帧｜旧写法会灌进 %.2f（上限 %.1f）｜"
		% [label, fuel_ratio * 100.0, held, FRAMES, would_be, SHAKE_CAP]
		+ "本次抖动池终值 %.3f｜首记读数 %.3f" % [cam._shake, first_tap])
	if fuel_ratio <= 0.0:
		t.eq(held, FRAMES,
			"（前提）槽空 + 按住 Shift ⇒ 旧表达式「想加速 且 入口 fm.boosting 为假」在 %d 帧里成立 %d 次"
				% [FRAMES, held])
		t.gt(would_be, 1.0,
			"（仪器自证）同一批帧上，旧写法会灌进 %.2f ⇒ 必然顶到 %.1f 上限（这就是「剧烈晃动」）"
				% [would_be, SHAKE_CAP])
		# 槽空 ⇒ **连一次点火确认都不给**（`has_jet_gauge() and jet_left > 0.0` 那道门）。
		# 这一条比"小于一次的量"更硬：它要求**整秒内一次都没抖**。
		t.near(cam._shake, 0.0, 0.0001,
			"★ %d 帧按住 Shift + 槽空 ⇒ 抖动池**一点没进**（%.4f）—— 旧代码这里恒为 %.1f"
				% [FRAMES, cam._shake, SHAKE_CAP])
		t.lt(first_tap, 0.0, "...而且整秒内**一次都没抖**（首记读数 %.3f < 0 = 从未进过池子）" % first_tap)
	else:
		t.eq(held, 1,
			"槽满 ⇒ 裁决**放行**、`fm.boosting` 保持 true ⇒ 旧表达式只在第 1 帧成立一次（成立 %d 次）"
				% held)
		# ---- 点火反馈本身还在（修的是「发了几次」，不是把这一记删掉）----
		t.near(first_tap, TAP, 0.0001,
			"点火那一记**还在**且**只有一记**（%.3f）：一按一记，不是「把这个功能删了」" % first_tap)
		t.near(cam._shake, TAP, 0.0001,
			"槽满 + 按住 1 s ⇒ 池里正好一记的量（%.3f）—— 按住不放不会续抖" % cam._shake)

	t.lt(cam._shake, 1.0, "★ 抖动池远低于 1.0 —— 1.0 以上就已经读成「镜头在抽筋」")

	c.free()
	await host.get_tree().process_frame
	Game.reset()
