extends Node
## 性能探针（轮 41）——「多发导弹 + 多台机体特别卡」的**量化台**。
##
## ## 为什么先用它、不先改代码
##
## 「特别卡」不是一个可证伪的判据。要动手就必须先回答三个问题：
##   ① 卡在**哪一档**（1v1 空场？多发弹？14 台编队？两者叠加？）；
##   ② 卡在**哪一层**（脚本 / 网格重建 / 粒子 / 绘制调用 / 物理）；
##   ③ 每一项**各占多少**（没有增量分解就会改错地方，然后"好像好了一点"）。
##
## 所以本台做两件事：**分档**跑 + 用 `Performance` 单例把每档的
## 帧时间 / 进程 / 物理 / 绘制调用 / 图元 / 对象数**全部记下来**。
##
## ## 分档（每档之间只差一个变量）
##
##   ① 1v1 · 空场                   —— 基线
##   ② 1v1 · 浮游弹 ×12（HIGH）      —— 12 条烟带 + 12 个粒子发射器
##   ③ 1v1 · 浮游弹 ×36（HIGH）      —— 线性放大 3 倍，看是不是线性
##   ④ 1v1 · 全弹发射 ×100（LOW）    —— 100 弹但**没有烟带**（LOW 档不建带）
##   ⑤ 编队战 14 台 · 空场           —— 只加机体、不加弹
##   ⑥ 编队战 14 台 · 浮游弹 ×36     —— 两者叠加（用户报的那个场景）
##
## ## A/B 开关（命令行）
##
##   `-- <输出目录> [--no-ribbon] [--no-trail]`
##   `--no-ribbon`：每发弹建好烟带后立刻删掉（隔离"烟带的代价"）
##   `--no-trail` ：每发弹的 `GPUParticles3D` 尾迹删掉（隔离"粒子的代价"）
##   ⚠️ 两个开关**只动被测对象**，其它一律不碰；同一个台、同一段代码，只有这一个变量不同。
##
## ## 运行
##
##   ⚠️ **不能加 `--headless`** —— dummy 渲染器没有绘制调用/图元数，
##      帧时间也会变成"纯脚本时间"，那正是要分开量的两件事之一。
##
##   Godot_v4.7.1-stable_win64_console.exe --path . res://tools/probe_perf.tscn \
##       -- "C:/tmp/perf_a"
##
## ## 读数口径（三条，缺一条就会看错）
##
##   · **帧时间**用 `Time.get_ticks_usec()` 的**相邻帧差**，不是 `get_process_delta_time()`
##     —— 后者在引擎内部被钳过（`Engine.time_scale` / 固定步），量不出真实卡顿。
##   · **进程时间 / 物理时间**取 `Performance.TIME_PROCESS` / `TIME_PHYSICS_PROCESS`（**秒**）。
##     "帧时间涨了但进程时间没涨"⇒ 卡在**渲染**（绘制调用/图元/GPU），不在脚本。
##     "进程时间也涨了"⇒ 卡在**脚本或网格重建**（CPU）。
##   · **绘制调用 / 图元**取 `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` / `RENDER_TOTAL_PRIMITIVES_IN_FRAME`
##     （⚠️ 是 `..._PRIMITIVES_IN_FRAME`，**没有** `RENDER_TOTAL_PRIMITIVE_COUNT` 这个名字 ——
##      写错会在**加载期**直接 Parse Error，而"脚本加载失败"的表现是**进程挂住不退出**）。
##
##   ⚠️ 弹一律射向 **400 km 外的空靶**：让它们直飞满 `lifetime` 14 s
##      （烟带最长、粒子最多、最坏情形），而不是几秒就命中消失。
##
## ## `--decompose` 的**降级阶梯**（2026-10-03 轮 63 扩到 13 档）
##
##   原 10 档 = HUD / AI 脚本 / 骨骼动画 / AI 模型 / 地形 / 粒子 / 地板 / 阴影 / 细节剔除；
##   **新增 3 档**（对应"小队战闪退"取证：设计文档 §2.4 要求逐级关
##   MSAA 4×→2×→关、踏板、AI 模型、HUD）：
##
##     ⑩ MSAA → 2×      ⑪ MSAA → 关      ⑫ 隐藏载体踏板
##
##   ⇒ 这样"哪一级跨过阈值"就有了直接读数，D1 画质档不必拍脑袋。
##   ⚠️ MSAA 是**运行时**改 `get_viewport().msaa_3d`，档间立刻还原成开局值。

const WARMUP := 45
## 采样窗口（帧）。60 Hz 下 180 帧 = 3 s —— 比"导弹活满 14 s"短，
## 所以窗口内**弹数不会自然衰减**，读数不受"中途死弹"污染。
const SAMPLE := 180

var out_dir := "user://perf"
var no_ribbon := false
var no_trail := false
## `--decompose`：只跑「编队战 14 台 · 空场」并逐个子系统关掉测一遍。
var decompose := false
## `--lodshot`：不出读数，改出**真机判据图** —— 逐件细节距离剔除（`FlightBody.detail_range_end`）
## 到底看不看得见。见 `_lod_shots()`。
var lodshot := false
## `--msl`：分解档改成「编队战 14 台 + 36 发弹」，并且**每档前重建弹**。
##
## ⚠️ 为什么必须有这一档（轮 41）：`_physics_process` **每渲染帧会跑多个物理子步**
## （帧一慢就顶满 `Engine.max_physics_steps_per_frame`），所以挂在 `_physics_process`
## 上的开销在慢帧下被 **×N** 放大。只在空场（帧快、子步少）量出来的 AI 脚本开销，
## **低估了它在"特别卡"那一刻的真实代价** —— 而用户报的恰恰是那一刻。
var msl := false

## `--mag`：只跑「编队战 14 台」上**放大镜（轮 63-10 · D3b）**的 A/B —— 判据 6 的读数台。见 `_mag_pair()`。
##
## `--magrot`（轮 63-10c）：档序**每轮轮转 1 位**（5 轮 = 拉丁方）⇒ 把「档身份」与「轮内位置」解耦。
## `--magburn=<µs>`（轮 63-10c）：**位置负对照** —— 给「1 号位那一档」的每一帧注入一段**已知时长**
##   的忙等（= µs/1000 ms），看两路分解能否把它读回来。隐含 `--magrot`。
##
## 轮 63-10b 起多一档 `④ 面板档内配对`（每帧交替摘 / 装底座）⇒ 判据 6 才有「档内版」读数。
##
## 设计文档 §3.3 判据 6 的红线 = 「开 / 关放大镜的帧时差 ≤ 1.0 ms」。
## 为什么不能靠推：放大镜的 `SubViewport` 渲染的是**同一份世界**（`world_3d` 指向主视口那一份），
## ⇒ 多出来的是**整个场景再剔除一遍 + 再画一遍**（本工程约 6.9 千件 / 2.3 千材质）。
var mag := false

## `--magrot`：档序每轮轮转 1 位（拉丁方）。见 `_mag_pair()` 上方注释。
var mag_rot := false

## `--magburn=<µs>`：位置负对照注入量（微秒）。0 = 不注入。
var _mag_burn_us := 0

## `--magshots`：不出读数，改出**真机判据图** —— 放大镜面板在屏幕上的位置、镜里到底有没有东西。
## 见 `_mag_shots()`。
var magshots := false

## 交错轮数。单轮不可用（见 `_decompose` 的注释）。
const STAGE_ROUNDS := 3
## 交错轮次里每档的采样窗口（比单轮版短：总帧数要乘 轮数 × 档数）。
const STAGE_WARM := 20
const STAGE_SAMPLE := 60

## `--msl` 档的弹数（与主档的"编队战 ×36"对齐，便于横向比）。
const MSL_COUNT := 36

## ⑨ 档：逐件按"件半径 × K"设 `visibility_range_end`（米）。
##
## 493 件/台的模型里绝大多数是**几厘米的小件**，在几百米外连一个像素都不到，
## 却照样各占一次绘制调用。`GeometryInstance3D.visibility_range_end` 是**引擎自带的
## 按相机距离剔除**，per-instance、一次性设置、每帧零成本 —— 正好用来做"穷人的几何 LOD"。
const LOD_K := 2000.0
const LOD_MIN_M := 250.0
const LOD_MAX_M := 6000.0

## 八档（顺序即交错顺序；0 号是基准，每轮都测一遍）。
const STAGE_LABELS := [
	"● 基准（全开）",
	"① 关 HUD（纯代码绘制的 Control）",
	"② 关 13 台 AI 的物理脚本",
	"③ 停 14 个 AnimationPlayer（骨骼动画）",
	"④ 隐藏 13 台 AI 的模型（绘制 + 骨骼更新）",
	"⑤ 隐藏地形/世界",
	"⑥ 隐藏 80 个粒子发射器",
	"⑦ 地板：只画玩家机",
	"⑧ 13 台 AI 机体不投影（阴影 pass 减半）",
	"⑨ 关掉逐件细节剔除（A/B：正值 = 这一项值多少 ms）",
	"⑩ MSAA 降到 2×（A/B：正值 = 抗锯齿值多少 ms）",
	"⑪ MSAA 全关",
	"⑫ 隐藏载体踏板（FlightPedal ×N）",
]

var _stage_raw := {}    # 标签 -> Array[float]：每轮该档的 ms_avg
var _stage_delta := {}  # 标签 -> Array[float]：每轮「该档 ms − 同轮基准 ms」

var _rows: Array = []
var _stage_rows: Array = []
var _dummy: Node3D = null


func _ready() -> void:
	# 量的是"能干多快"，所以把两道闸都打开：不限帧、不垂直同步。
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1600, 1000))

	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	for a in args:
		if a == "--no-ribbon":
			no_ribbon = true
		if a == "--no-trail":
			no_trail = true
		if a == "--decompose":
			decompose = true
		if a == "--msl":
			msl = true
		if a == "--mag":
			mag = true
		if a == "--magrot":
			mag = true
			mag_rot = true
		if a.begins_with("--magburn="):
			mag = true
			mag_rot = true
			_mag_burn_us = int(a.substr("--magburn=".length()))
		if a == "--magshots":
			magshots = true
		if a == "--lodshot":
			lodshot = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _frames(20)

	print("\n================ 性能探针（轮 41）================")
	print("[perf] 烟带 %s · 粒子尾迹 %s · 不设帧率上限 · 垂直同步关"
		% ["开" if not no_ribbon else "**关**", "开" if not no_trail else "**关**"])
	print("[perf] 采样窗口 %d 帧（预热 %d 帧）" % [SAMPLE, WARMUP])

	if lodshot:
		await _lod_shots()
		print("\n[perf] DONE -> ", out_dir)
		get_tree().quit(0)
		return

	if decompose:
		var md := await _boot(Game.MatchMode.SQUAD)
		await _decompose(md)
		await _teardown(md)
		_write()
		print("\n[perf] DONE -> ", out_dir)
		get_tree().quit(0)
		return

	if magshots:
		var ms := await _boot(Game.MatchMode.SQUAD)
		await _mag_shots(ms)
		await _teardown(ms)
		print("\n[perf] DONE -> ", out_dir)
		get_tree().quit(0)
		return

	if mag:
		var mm := await _boot(Game.MatchMode.SQUAD)
		await _mag_pair(mm)
		await _teardown(mm)
		_write_mag()
		print("\n[perf] DONE -> ", out_dir)
		get_tree().quit(0)
		return

	# ---- 第一局：1v1（弹档全在这里）----
	var m1 := await _boot(Game.MatchMode.VERSUS)
	await _phase(m1, "1v1 · 空场", 0)
	await _phase(m1, "1v1 · 浮游弹 ×12（HIGH/烟带）", 12)
	await _phase(m1, "1v1 · 浮游弹 ×36（HIGH/烟带）", 36)
	await _phase(m1, "1v1 · 全弹发射 ×100（LOW/无烟带）", 100, Missile.Trail.LOW)
	await _teardown(m1)

	# ---- 第二局：编队战（14 台）----
	var m2 := await _boot(Game.MatchMode.SQUAD)
	await _phase(m2, "编队战 14 台 · 空场", 0)
	await _phase(m2, "编队战 14 台 · 浮游弹 ×36", 36)
	await _teardown(m2)

	_write()
	print("\n[perf] DONE -> ", out_dir)
	get_tree().quit(0)


# ============================================================ 分档


func _phase(m: Node, label: String, count: int, trail := Missile.Trail.HIGH) -> void:
	if count > 0:
		await _spawn_missiles(m, count, trail)
	await _frames(WARMUP)

	var r := await _sample(SAMPLE)
	r["label"] = label
	r["want"] = count
	r["missiles"] = _count_type(m, "Missile")
	r["ribbons"] = _count_type(m, "MissileRibbon")
	r["emitters"] = _count_type(m, "GPUParticles3D")
	r["units"] = _units(m)
	r["nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	# ---- 组成（每档统计一次，不进每帧循环）----
	# 「14 台机子 = 3800 次绘制调用」到底花在什么上？把**可见节点**与**材质份数**拆开，
	# 才能判断该合并网格、该共享材质、还是该做 LOD。
	r["meshes"] = _count_type(m, "MeshInstance3D")
	r["skel"] = _count_type(m, "Skeleton3D")
	r["shapes"] = _count_type(m, "CollisionShape3D")
	r["mats"] = _unique_materials(m)
	_rows.append(r)
	_print_row(r)

	await _clear_missiles(m)
	await _frames(10)


## 把所有导弹射向 **400 km 外的空靶**。
##
## ⚠️ 为什么不是"打个真敌机"：真敌机在 12 km 内，弹飞两三秒就命中 ⇒ 弹数随时间衰减，
## 每档的"弹数"就不是常数了，读数无法横向比。射向 400 km 外则**弹一路直飞满 14 s**，
## 窗口内弹数恒定 —— 这正是最坏情形，也是各档之间唯一可比的形态。
func _spawn_missiles(m: Node, count: int, trail: int) -> void:
	var me: PlayerController = m.get("player")
	var container: Node = m.get("projectiles")
	if me == null or container == null:
		print("[perf] !! 没有玩家或弹丸容器，跳过这一档")
		return
	var fwd := -me.global_transform.basis.z
	if _dummy == null or not is_instance_valid(_dummy):
		_dummy = Node3D.new()
		_dummy.name = "PerfDummyTarget"
		m.add_child(_dummy)
	_dummy.global_position = me.global_position + fwd * 400000.0

	var origin := me.global_position + fwd * 40.0
	for i in count:
		var side := 1.0 if i % 2 == 0 else -1.0
		var outward := (me.right() * side + me.up() * 0.45 - fwd * 0.15).normalized()
		var mm: Missile
		if trail == Missile.Trail.LOW:
			# 全弹发射：**走 `spawn` 而不是 `funnel`**（与 `_emit_full_salvo_shot()` 同一条路）。
			mm = Missile.spawn(container, origin, outward, _dummy, me, 45.0, Missile.Trail.LOW)
		else:
			mm = Missile.funnel(container, origin, outward, _dummy, me, 26.0, Missile.Trail.HIGH)
		if mm == null:
			continue
		# ---- A/B：只拿掉被测的那一件 ----
		if no_ribbon:
			var rib = mm.get("_ribbon")
			if rib is Node and is_instance_valid(rib):
				(rib as Node).queue_free()
			mm.set("_ribbon", null)
		if no_trail:
			var tr := mm.get_node_or_null("MissileTrail")
			if tr != null:
				tr.queue_free()
		# 弹要飞满 14 s ⇒ 中途不许因为"燃料"提前自毁（`lifetime` 是本类自己的字段）。
		mm.set("lifetime", 60.0)


func _clear_missiles(m: Node) -> void:
	for n in _all_type(m, "Missile"):
		(n as Node).queue_free()
	for n in _all_type(m, "MissileRibbon"):
		(n as Node).queue_free()


# ============================================================ 真机判据图 · 逐件细节距离剔除


## 判据距离（**相机到敌机**，m）。
## 120 / 700 = 近距（要求**逐像素完全相同**）；3000 / 7000 = 远距（要求**机体仍在**）。
const LOD_SHOT_DISTS := [120.0, 700.0, 3000.0, 7000.0]
## 机位相对敌机的偏移方向（斜上前方 —— 看得到机体的立体面，不是正后方一个剪影）。
const LOD_VIEW_DIR := Vector3(0.55, 0.42, 0.72)


## 为什么单独一个模式（而不是照 `probe_perf` 的读数说"看不见"）：
## `--decompose` 量的是"省多少 ms"，量不了"看不看得出来"。而这一项改的恰恰是**视觉**：
## 把亚像素的零件按距离剔掉。按 `DETAIL_LOD_K = 2000` 的推导，被剔的件在该距离处
## **不到 1 像素** —— 但这是**算出来的**，必须拿真机像素验（本工程有过"三个看起来很
## 合理的错数"）。
##
## 口径：同一台敌机、**固定机位**，每个距离拍一组（开 / 关，各连拍两张）：
##   · 每档开/关各连拍两张 ⇒ 拿"同设置的相邻帧差"当**本底**（云 / 海面 / 辉光有帧间抖动），
##     只有明显超过本底才算是这次改动造成的；
##   · 另拍一张"藏掉敌机"的 **bg** ⇒ 用来数"机体占了几像素"。
##
## ⚠️ 三处会让差分失真的东西必须让开（本工程踩过"读数与画面分家"）：
##   ① 玩家自己那台机体永远在画面正中 ⇒ 藏掉（`visible = false`）；
##   ② HUD 每帧都在重绘 ⇒ 藏掉；
##   ③ 相机必须**手动放好**，不能用追尾相机（它跟着玩家飞，位置不可控）——
##      而这一项判据的**自变量就是"相机到敌机的距离"**，机位不可控等于没量。
func _lod_shots() -> void:
	var m := await _boot(Game.MatchMode.VERSUS)
	var me: PlayerController = m.get("player") as PlayerController
	var foe: FlightBody = null
	for u in _all_type(m, "FlightBody"):
		if u != me:
			foe = u
			break
	if me == null or foe == null:
		print("[lod] !! 没找到玩家或敌机（me=%s foe=%s）" % [str(me), str(foe)])
		return
	print("[lod] 玩家 %s · 敌机 %s · 目标全高 %.1f m"
		% [str(me.profile.model_name), str(foe.profile.model_name), foe.profile.target_height])

	# ---- 让开三处干扰 ----
	var hud: Control = m.get("hud")
	if hud != null:
		hud.visible = false
	me.visible = false
	me.set_physics_process(false)
	me.set_process(false)
	foe.set_physics_process(false)
	foe.set_process(false)
	foe.set("control_input", Vector3.ZERO)
	# ⚠️ **别再漏这一条**：`set_process(false)` 只停机体自己的 `_process`，
	# 挂在模型里的 `AnimationPlayer` 是**子节点**，它照旧每帧推动 274 个零件 ——
	# 第一跑没停它，本底抖动 5.7 万像素 ≈ 机体自己的像素面积，
	# 把"改动"整个淹掉了（判据全 FAIL，而产品和改动其实都没问题）。
	for a: Node in _all_type(m, "AnimationPlayer"):
		(a as AnimationPlayer).set_process(false)
	# ⚠️ **粒子也不吃机体的 `set_process(false)`**：`GPUParticles3D` 有自己的时钟，
	# 不关就一直喷（尾焰 / 黑烟）。第一跑的"本底抖动"9.6 万像素主要就是它。
	for p: Node in _all_type(m, "GPUParticles3D"):
		(p as GPUParticles3D).emitting = false
		(p as Node3D).visible = false
	var fm = foe.get("fm")
	if fm != null:
		fm.speed = 0.0
		fm.velocity = Vector3.ZERO
	# ⚠️ 追尾相机也在跟玩家 —— 不把它 `current = false`，它会和手动机位打架。
	var chaser := m.get("camera") as Camera3D
	if chaser != null:
		chaser.current = false

	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 200000.0
	add_child(cam)
	cam.current = true

	var rows: Array = []
	for dist in LOD_SHOT_DISTS:
		var at := foe.global_position + Vector3.UP * (foe.profile.target_height * 0.12)
		var dir := (foe.global_transform.basis * LOD_VIEW_DIR).normalized()
		cam.global_position = at + dir * dist
		cam.look_at(at, Vector3.UP)
		# ⚠️ 6 帧不够：本工程开着时间性累积（TAA / 阴影 / SSAO 历史），相机一挪，
		# 历史缓冲要**几十帧**才收敛 —— 6 帧时 120 m 处的"同状态相邻帧"还有 2.6 万像素差，
		# 判据直接被自己的收敛噪声淹掉。给足 40 帧。
		await _frames(40)

		# ---- 10 张，两次「切换」前后各留一张稳态帧。----
		#
		# ⚠️ 两条口径，都是第一跑踩出来的：
		#   ① **必须相邻帧**比：世界（云 / 海面 / 辉光）自己就在动，隔几帧再比就把漂移
		#      当成了"改动"。所以每一步紧挨着拍，用"同状态相邻帧差"当本底。
		#   ② **"开→关"必须紧贴，中间不许夹隐藏/显示**：把敌机 `visible = false` 再 `true`
		#      会让**渲染历史**（TAA / 阴影 / SSAO 的累积缓冲）翻一帧 —— 实测 120 m 处
		#      凭空多出 13427 像素差，而那个距离**按公式一件都没被剔**（夹取下限 250 m）。
		#      隐藏只留到**最后**，并且给一帧让它收敛（f7）。
		#
		# f0 on · f1 on ‖ 切关 ‖ f2 off · f3 off · f4 off ‖ 切开 ‖ f5 on · f6 on ‖ 隐藏 f7 ‖ f8 bg
		await _shoot("d%d_f0_on.png" % int(dist))
		await _shoot("d%d_f1_on.png" % int(dist))
		_set_detail_lod(foe, false)
		await _shoot("d%d_f2_off.png" % int(dist))
		await _shoot("d%d_f3_off.png" % int(dist))
		await _shoot("d%d_f4_off.png" % int(dist))
		_set_detail_lod(foe, true)
		await _shoot("d%d_f5_on.png" % int(dist))
		await _shoot("d%d_f6_on.png" % int(dist))
		foe.visible = false
		await _shoot("d%d_f7_bgbad.png" % int(dist))
		await _shoot("d%d_f8_bg.png" % int(dist))
		foe.visible = true

		var cut := 0
		var total := 0
		for n: Node in _all_type(foe, "MeshInstance3D"):
			total += 1
			if FlightBody.detail_range_end(FlightBody.part_radius_m(n as MeshInstance3D)) < dist:
				cut += 1
		rows.append("%.0f m：剔 %d/%d 件" % [dist, cut, total])
		print("[lod] %s" % rows[rows.size() - 1])
	print("[lod] 汇总：", " | ".join(rows))


## 开/关逐件细节剔除。**开 = 走产品的纯函数**（单一真源）；
## 关 = `range_end = 0`（0 在 Godot 里是"不设上限"，即全画）。
func _set_detail_lod(b: FlightBody, on: bool) -> void:
	for n: Node in _all_type(b, "MeshInstance3D"):
		var mi := n as MeshInstance3D
		mi.visibility_range_end = FlightBody.detail_range_end(FlightBody.part_radius_m(mi)) if on else 0.0


func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name))
	print("  SHOT %s" % name)


# ============================================================ 非烟带子系统分解


## 逐个子系统关掉、各测一档，**测完立刻还原**。
##
## 为什么要这样量：25 ms 的编队战基准里，"AI 脚本 / 骨骼动画 / 绘制调用 / HUD / 地形"
## 各自占多少，靠读代码是猜不出来的（本工程有过"三个看起来很合理的错数"的记录）。
## 关掉一项就少一项，**差值就是它**。
##
## ⚠️ **单轮顺序测量不可用（轮 41 实测，两次背靠背运行同一份代码）**：
##   · 「● 基准」22.27 / 23.88 ms（次间差 7%）；
##   · 「① 关 HUD」省 **4.59 / 9.06 ms**（同一档差了一倍）；
##   · 「⑦ 地板」4.60 / 3.96 ms（次间差 16%）。
## ⇒ 单轮里 HUD / AI 脚本 / 模型 三者那点差**整个落在噪声里**，排出来的序是假的。
##
## 现在改成 **交错多轮 + 同轮配对**：每轮把 8 档各测一遍（基准每轮都测），
## 某档的读数取「该档 ms − **同一轮**基准 ms」，再对多轮取**中位**。
## 漂移（GPU 频率 / 热降频 / 并行会话占用）被同轮配对消掉。
func _decompose(m: Node) -> void:
	var me: PlayerController = m.get("player")
	var hud: Control = m.get("hud")
	var world: Node3D = m.get("world")
	var aps := _all_type(m, "AnimationPlayer")
	var parts := _all_type(m, "GPUParticles3D")
	var others: Array = []
	for u in _all_type(m, "FlightBody"):
		if u != me:
			others.append(u)
	print("[perf] 分解：14 台机 · %d 个 AnimationPlayer · %d 个粒子发射器 · %d 台 AI"
		% [aps.size(), parts.size(), others.size()])
	print("[perf] 交错 %d 轮 × %d 档（每档 预热 %d + 采样 %d 帧）；档间立即还原"
		% [STAGE_ROUNDS, STAGE_LABELS.size(), STAGE_WARM, STAGE_SAMPLE])
	# ---- 组成（判断"能不能合批"的三个数）----
	var n_mesh := _count_type(m, "MeshInstance3D")
	var n_mat := _unique_materials(m)
	var n_bone := _count_type(m, "CollisionShape3D")
	var n_pedal := _all_type(m, "FlightPedal").size()
	var n_pedal_mesh := 0
	for p in _all_type(m, "FlightPedal"):
		n_pedal_mesh += _count_type(p as Node, "MeshInstance3D")
	print("[perf] 组成：件 %d · 唯一材质 %d · 碰撞盒 %d · 单位 %d · 踏板 %d 块（%d 件）⇒ 每台约 %d 件 / %d 材质"
		% [n_mesh, n_mat, n_bone, _units(m), n_pedal, n_pedal_mesh,
			n_mesh / maxi(_units(m), 1), n_mat / maxi(_units(m), 1)])
	_print_lod_diag(me, others)

	var ctx := {"hud": hud, "world": world, "others": others, "aps": aps, "parts": parts,
		"root": m, "vp": m.get_viewport(), "msaa0": m.get_viewport().msaa_3d}
	print("[perf] MSAA 当前 = %d（DISABLED=%d / 2X=%d / 4X=%d / 8X=%d）· project.godot `msaa_3d`"
		% [m.get_viewport().msaa_3d, Viewport.MSAA_DISABLED, Viewport.MSAA_2X,
			Viewport.MSAA_4X, Viewport.MSAA_8X])
	# 有弹时帧更长（弹寿命 14 s，撑不满一整轮），只测四条主干，且**每档前重建弹**。
	var idx: Array = []
	if msl:
		idx = [0, 1, 2, 4]
	else:
		for i in STAGE_LABELS.size():
			idx.append(i)
	for rd in STAGE_ROUNDS:
		for i in idx:
			if msl:
				_clear_missiles(m)
				await _frames(12)
				_spawn_missiles(m, MSL_COUNT, Missile.Trail.HIGH)
				await _frames(30)
			_stage_off(i, ctx)
			await _stage(m, str(STAGE_LABELS[i]))
			_stage_on(i, ctx)
		if msl:
			_clear_missiles(m)
			await _frames(10)
		print("[perf] 第 %d/%d 轮完成" % [rd + 1, STAGE_ROUNDS])

	# ---- 同轮配对：delta = 该档 − 同一轮的基准 ----
	var base: Array = _stage_raw.get(str(STAGE_LABELS[0]), [])
	for i in STAGE_LABELS.size():
		var lab := str(STAGE_LABELS[i])
		var raw: Array = _stage_raw.get(lab, [])
		var dd: Array = []
		for k in mini(raw.size(), base.size()):
			dd.append(float(raw[k]) - float(base[k]))
		_stage_delta[lab] = dd

	print("")
	print("---- 交错多轮分解（同轮配对取中位；负值 = 关掉它省下的 ms）----")
	print("%-40s %8s %8s %8s %8s" % ["档位", "省下中位", "最小", "最大", "档ms中位"])
	for i in STAGE_LABELS.size():
		var lab := str(STAGE_LABELS[i])
		var dd: Array = _stage_delta.get(lab, [])
		var raw: Array = _stage_raw.get(lab, [])
		print("%-40s %8.2f %8.2f %8.2f %8.2f"
			% [lab, _median(dd), _min_of(dd), _max_of(dd), _median(raw)])


## 关掉第 i 档要关的东西（0 = 基准，什么都不关）。
func _stage_off(i: int, c: Dictionary) -> void:
	var hud: Control = c["hud"]
	var world: Node3D = c["world"]
	var others: Array = c["others"]
	var aps: Array = c["aps"]
	var parts: Array = c["parts"]
	match i:
		0:
			pass
		1:
			if hud != null:
				hud.visible = false
		2:
			for u in others:
				(u as Node).set_physics_process(false)
		3:
			for a in aps:
				(a as AnimationPlayer).set_process(false)
		4:
			for u in others:
				(u as Node3D).visible = false
		5:
			if world != null:
				world.visible = false
		6:
			for p in parts:
				(p as Node3D).visible = false
		7:
			if hud != null:
				hud.visible = false
			for u in others:
				(u as Node3D).visible = false
			if world != null:
				world.visible = false
			for p in parts:
				(p as Node3D).visible = false
		8:
			for u in others:
				for n in _all_type(u, "MeshInstance3D"):
					(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		9:
			for u in others:
				for n in _all_type(u, "MeshInstance3D"):
					(n as MeshInstance3D).visibility_range_end = 0.0
		10:
			(c["vp"] as Viewport).msaa_3d = Viewport.MSAA_2X
		11:
			(c["vp"] as Viewport).msaa_3d = Viewport.MSAA_DISABLED
		12:
			for p in _all_type(c["root"], "FlightPedal"):
				(p as Node3D).visible = false


## 还原第 i 档（与 `_stage_off` 一一对应 —— 档间必须完全还原，否则下一档就不是"只差一个变量"）。
func _stage_on(i: int, c: Dictionary) -> void:
	var hud: Control = c["hud"]
	var world: Node3D = c["world"]
	var others: Array = c["others"]
	var aps: Array = c["aps"]
	var parts: Array = c["parts"]
	match i:
		0:
			pass
		1:
			if hud != null:
				hud.visible = true
		2:
			for u in others:
				(u as Node).set_physics_process(true)
		3:
			for a in aps:
				(a as AnimationPlayer).set_process(true)
		4:
			for u in others:
				(u as Node3D).visible = true
		5:
			if world != null:
				world.visible = true
		6:
			for p in parts:
				(p as Node3D).visible = true
		7:
			if hud != null:
				hud.visible = true
			for u in others:
				(u as Node3D).visible = true
			if world != null:
				world.visible = true
			for p in parts:
				(p as Node3D).visible = true
		8:
			for u in others:
				for n in _all_type(u, "MeshInstance3D"):
					(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		9:
			for u in others:
				for n in _all_type(u, "MeshInstance3D"):
					var mi9 := n as MeshInstance3D
					mi9.visibility_range_end = FlightBody.detail_range_end(FlightBody.part_radius_m(mi9))
		10:
			(c["vp"] as Viewport).msaa_3d = int(c["msaa0"])
		11:
			(c["vp"] as Viewport).msaa_3d = int(c["msaa0"])
		12:
			for p in _all_type(c["root"], "FlightPedal"):
				(p as Node3D).visible = true


func _stage(m: Node, label: String) -> void:
	await _frames(STAGE_WARM)
	var r := await _sample(STAGE_SAMPLE)
	r["label"] = label
	if not _stage_raw.has(label):
		_stage_raw[label] = []
	_stage_raw[label].append(float(r["ms_avg"]))
	_stage_rows.append(r)
	print("[stage] %-40s 帧 %6.2f ms (p50 %6.2f p95 %6.2f)  %5.1f fps  进程 %5.2f  物理 %5.2f  绘制 %5d  图元 %8d"
		% [label, r["ms_avg"], r["ms_p50"], r["ms_p95"], r["fps"], r["proc_ms"], r["phys_ms"],
			int(r["draw"]), int(r["prim"])])
	await _frames(6)


static func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b: Array = a.duplicate()
	b.sort()
	return float(b[b.size() / 2])


static func _min_of(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b: Array = a.duplicate()
	b.sort()
	return float(b[0])


static func _max_of(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b: Array = a.duplicate()
	b.sort()
	return float(b[b.size() - 1])


# ============================================================ 采样


func _sample(frames: int) -> Dictionary:
	var dts: Array[float] = []
	var draws: Array[float] = []
	var prims: Array[float] = []
	var objs: Array[float] = []
	var t_proc := 0.0
	var t_phys := 0.0
	var prev := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		dts.append(float(now - prev) / 1000.0)
		prev = now
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		objs.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		t_proc += Performance.get_monitor(Performance.TIME_PROCESS)
		t_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	dts.sort()
	draws.sort()
	prims.sort()
	objs.sort()
	var n := float(maxi(frames, 1))
	return {
		"ms_avg": _mean(dts), "ms_p50": _pct(dts, 0.50), "ms_p95": _pct(dts, 0.95),
		"ms_max": dts[dts.size() - 1] if dts.size() > 0 else 0.0,
		"fps": 1000.0 / maxf(_mean(dts), 0.001),
		"proc_ms": t_proc / n * 1000.0,
		"phys_ms": t_phys / n * 1000.0,
		"draw": draws[draws.size() / 2] if draws.size() > 0 else 0.0,
		"prim": prims[prims.size() / 2] if prims.size() > 0 else 0.0,
		"robj": objs[objs.size() / 2] if objs.size() > 0 else 0.0,
	}


static func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


static func _pct(a: Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var i := clampi(int(round(p * float(a.size() - 1))), 0, a.size() - 1)
	return float(a[i])


## 样本标准差（n − 1）。用来算标准误 —— 「0.35 ms 到底算不算数」只能靠它答。
static func _sd_of(a: Array) -> float:
	if a.size() < 2:
		return 0.0
	var m := _mean(a)
	var s := 0.0
	for v in a:
		s += (float(v) - m) * (float(v) - m)
	return sqrt(s / float(a.size() - 1))


static func _fmt_arr(a: Array) -> String:
	var parts: PackedStringArray = []
	for v in a:
		parts.append("%.2f" % float(v))
	return " / ".join(parts)


# ============================================================ 计数 / 工具


func _boot(mode: int) -> Node:
	var m := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(m)
	await _frames(40)
	m.call("_on_start_match", SuitProfile.Id.PENELOPE, 0, -1, mode, -1)
	var me: PlayerController = null
	for i in 240:
		await _frames(1)
		me = m.get("player") as PlayerController
		if me != null and me.controls_enabled:
			break
	await _frames(30)
	print("[perf] 已开局：%s（模式 %d，玩家 %s）"
		% [("1v1" if mode == Game.MatchMode.VERSUS else "编队战"), mode,
			"就位" if me != null else "**没就位**"])
	return m


func _teardown(m: Node) -> void:
	if _dummy != null and is_instance_valid(_dummy):
		_dummy.queue_free()
		_dummy = null
	if m != null and is_instance_valid(m):
		m.queue_free()
	await _frames(12)


func _frames(k: int) -> void:
	for i in k:
		await get_tree().process_frame


## 按 `class_name` 抽查一类节点。
##
## ⚠️ 用 `is` 运算符，**不用** `is_class("Missile")` / `find_children(…, "Missile", …)` ——
## 后两者的 `type` 参数只按**原生类名**匹配，`class_name` 注册的脚本类名不一定命中；
## 一旦静默失配，读数会变成"0 条烟带"，而画面里烟带明明在 —— 那就是**读数与画面分家**。
func _all_type(m: Node, t: String) -> Array:
	var out: Array = []
	_collect(m, t, out)
	return out


func _collect(n: Node, t: String, out: Array) -> void:
	var hit := false
	match t:
		"Missile":
			hit = n is Missile
		"MissileRibbon":
			hit = n is MissileRibbon
		"GPUParticles3D":
			hit = n is GPUParticles3D
		"FlightBody":
			hit = n is FlightBody
		"FlightPedal":
			hit = n is FlightPedal
		_:
			hit = n.is_class(t)
	if hit:
		out.append(n)
	for c in n.get_children():
		_collect(c, t, out)


func _count_type(m: Node, t: String) -> int:
	return _all_type(m, t).size()


## 诊断：AI 离玩家多远、单台机体的件半径怎么分布。
##
## 为什么要打这两行：⑨ 档（按尺寸做距离剔除）**只有在机体确实很远时才会触发**。
## 如果 AI 全在 500 m 内，这一档量出来就是 0 —— 那是"没触发"，不是"没有用"，
## 必须靠这两行区分开（本工程有"读数与画面分家"的记录）。
func _print_lod_diag(me: PlayerController, others: Array) -> void:
	if me == null or others.is_empty():
		return
	var ds: Array = []
	for u in others:
		ds.append(me.global_position.distance_to((u as Node3D).global_position))
	ds.sort()
	print("[perf] AI 距玩家（m）：min %.0f · p50 %.0f · max %.0f" % [ds[0], ds[ds.size() / 2], ds[ds.size() - 1]])
	var b := [0, 0, 0, 0, 0]
	var meshes := _all_type(others[0], "MeshInstance3D")
	for n in meshes:
		var r := FlightBody.part_radius_m(n as MeshInstance3D)
		if r < 0.1:
			b[0] += 1
		elif r < 0.3:
			b[1] += 1
		elif r < 1.0:
			b[2] += 1
		elif r < 3.0:
			b[3] += 1
		else:
			b[4] += 1
	print("[perf] 单台件半径分布（<0.1/<0.3/<1/<3/>=3 m）：%s（共 %d 件）；K=%.0f 夹取 [%.0f, %.0f]"
		% [str(b), meshes.size(), FlightBody.DETAIL_LOD_K, FlightBody.DETAIL_LOD_MIN_M,
			FlightBody.DETAIL_LOD_MAX_M])
	var cut: Array = []
	for dist in [1000.0, 3000.0, 6000.0]:
		var n_cut := 0
		for n in meshes:
			if FlightBody.detail_range_end(FlightBody.part_radius_m(n as MeshInstance3D)) < dist:
				n_cut += 1
		cut.append("%.0f km %d 件" % [dist / 1000.0, n_cut])
	print("[perf] 逐件剔除命中数（单台 %d 件）：%s" % [meshes.size(), ", ".join(cut)])


## 场上**参战单位**数（敌我机体，含玩家那台；不含弹、不含踏板）。
func _units(m: Node) -> int:
	return _count_type(m, "FlightBody")


## 场景里**去重后**的材质份数（按 `instance_id`）。
##
## ⚠️ 这是判断"能不能合批"的第一个数：Godot 的 2D/3D 批处理按**材质 + 网格**分组，
## 每台机体各持有 240 份各不相同的材质时，绘制调用就只能是 240 次 —— 与画质无关。
func _unique_materials(m: Node) -> int:
	var seen := {}
	for n in _all_type(m, "MeshInstance3D"):
		var mi := n as MeshInstance3D
		if mi.material_override != null:
			seen[mi.material_override.get_instance_id()] = true
		var me := mi.mesh
		if me == null:
			continue
		for si in me.get_surface_count():
			var mt := me.surface_get_material(si)
			if mt != null:
				seen[mt.get_instance_id()] = true
	return seen.size()


func _print_row(r: Dictionary) -> void:
	print("[perf] %-34s 帧 %6.2f ms (p50 %6.2f / p95 %6.2f / max %6.2f)  %5.1f fps  进程 %5.2f  物理 %5.2f  绘制 %5d  图元 %8d  单位 %3d  弹 %3d  带 %3d  发射器 %3d  节点 %6d  [件 %5d  材质 %5d  骨 %3d  碰撞盒 %4d]"
		% [r["label"], r["ms_avg"], r["ms_p50"], r["ms_p95"], r["ms_max"], r["fps"],
			r["proc_ms"], r["phys_ms"], int(r["draw"]), int(r["prim"]), r["units"],
			r["missiles"], r["ribbons"], r["emitters"], r["nodes"],
			r["meshes"], r["mats"], r["skel"], r["shapes"]])


func _write() -> void:
	var path := out_dir.path_join("perf.txt")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("轮 41 性能探针 —— 烟带 %s · 粒子尾迹 %s · 不限帧 · 关垂直同步"
		% ["开" if not no_ribbon else "关", "开" if not no_trail else "关"])
	f.store_line("采样窗口 %d 帧 / 档，预热 %d 帧" % [SAMPLE, WARMUP])
	f.store_line("")
	f.store_line("标签                                帧ms均值   p50    p95    max    FPS   进程ms 物理ms 绘制调用   图元数  单位   弹  烟带 发射器   节点数     件   材质  骨  碰撞盒")
	for r in _rows:
		f.store_line("%-34s %7.2f %6.2f %6.2f %6.2f %6.1f %6.2f %6.2f %8d %9d %4d %4d %4d %5d %8d %6d %6d %4d %6d"
			% [r["label"], r["ms_avg"], r["ms_p50"], r["ms_p95"], r["ms_max"], r["fps"],
				r["proc_ms"], r["phys_ms"], int(r["draw"]), int(r["prim"]), r["units"],
				r["missiles"], r["ribbons"], r["emitters"], r["nodes"],
				r["meshes"], r["mats"], r["skel"], r["shapes"]])
	f.store_line("")
	# ---- 增量分解：每一档相对**同类空场基线**多了多少 ----
	# 1v1 的四档比第 0 行，编队战的两档比第 4 行 —— 混着比会把"机体数"和"弹数"搅在一起。
	f.store_line("---- 增量（相对同类空场基线：1v1 四档比第 1 行，编队战两档比第 5 行）----")
	f.store_line("档位                              帧ms 增量   进程ms 增量   绘制 增量   图元 增量")
	for i in _rows.size():
		if i == 0 or i == 4:
			continue
		var b: Dictionary = _rows[0] if i < 4 else _rows[4]
		var r: Dictionary = _rows[i]
		f.store_line("%-32s %8.2f %11.2f %11d %11d"
			% [r["label"], float(r["ms_avg"]) - float(b["ms_avg"]),
				float(r["proc_ms"]) - float(b["proc_ms"]),
				int(r["draw"]) - int(b["draw"]), int(r["prim"]) - int(b["prim"])])
	f.close()
	print("[perf] 表已写入 ", path)
	if _stage_raw.is_empty():
		return
	var sp := out_dir.path_join("stages.txt")
	var sf := FileAccess.open(sp, FileAccess.WRITE)
	if sf == null:
		return
	sf.store_line("轮 41 · 非烟带子系统分解（编队战 14 台 · 空场）")
	sf.store_line("交错 %d 轮 × %d 档（每档 预热 %d + 采样 %d 帧）；档间立即还原 ⇒ 一轮里只差一个变量。"
		% [STAGE_ROUNDS, STAGE_LABELS.size(), STAGE_WARM, STAGE_SAMPLE])
	sf.store_line("")
	sf.store_line("⚠️ 单轮顺序测量噪声实测 ±40%（两次背靠背运行同一份代码：同一档省下 4.59 还是 9.06 ms 都出现过）")
	sf.store_line("   ⇒ 改为**同轮配对**： 省下 = 该档 ms − **同一轮**基准 ms，再对 %d 轮取中位。负值 = 关掉它省下的 ms、即它的开销。" % STAGE_ROUNDS)
	sf.store_line("")
	sf.store_line("档位                                      省下中位    最小    最大   档ms中位")
	for i in STAGE_LABELS.size():
		var lab := str(STAGE_LABELS[i])
		var dd: Array = _stage_delta.get(lab, [])
		var raw: Array = _stage_raw.get(lab, [])
		sf.store_line("%-40s %9.2f %7.2f %7.2f %9.2f"
			% [lab, _median(dd), _min_of(dd), _max_of(dd), _median(raw)])
	sf.close()
	print("[perf] 分解表已写入 ", sp)


# ============================================================ 轮 63-10 · D3b 放大镜（判据 6）


## 判据 6 的五档标签（顺序即交错顺序；0 号每轮都测 ⇒ 同轮配对的基准）。
##
## ⚠️ 第 5 档 `④ 面板档内配对` 是轮 63-10b 加的**第二把档内尺**：前四档只能给
## 「跨档差分 `① − ③`」，而那个口径在本机的分辨率 ~±0.3 ms 与红线余量同量级 ⇒ 判不了。
## ④ 档把「门 + 摆位 + 面板三样」做成**同档内的逐帧配对**（每帧交替 `_mag_vp = null / 还原`），
## 漂移全抵；子视口那一笔仍用 ① 档自己的档内配对（推帧帧 − 其余帧）。两项都是档内量
## ⇒ 相加即得「放大镜本体」的**档内版**。**产品代码零改动**。
const MAG_LABELS := [
	"● 基准（锁定 · 按掉推帧）",
	"① 放大镜（产品原样）",
	"③ 锁定 · 底座摘掉",
	"② 无锁定（放大镜关）",
	"④ 面板档内配对（每帧交替摘 / 装底座）",
]

## 放大镜自己的轮数（比 `STAGE_ROUNDS` 多一轮：四档一组的跨档差要更稳的中位）。
const MAG_ROUNDS := 4

## `--magrot` 的轮数 —— **必须等于档数（5）**：每轮整体左移 `rd` 位，5 轮凑成一个
## **拉丁方**（每档在每个位置恰好出现一次）⇒ 两路分解
## `帧(档, 位) = μ + a[档] + b[位] + ε` 里 `a` 与 `b` 正交、都有闭式解。
##
## ⚠️ 只用 4 轮（= 非拉丁方）会出现「有的档位缺格」，`a`/`b` 不再正交 ⇒ 分解出来的
## 位置效应会和档效应混在一起 —— 那就白做了，所以轮数**写死 5**、不跟 `MAG_ROUNDS`。
const MAG_ROT_ROUNDS := 5

## ④ 档（交替档）的采样窗口 —— 比别的档长 3 倍。
##
## ⚠️ 为什么必须更长：这档要量的「门 + 摆位 + 面板三样」只有 ~0.35 ms，而本机**单帧**抖动
## σ ≈ 1.4 ms（④ 档 p50 9.05 / p95 10.44）⇒ 单帧信噪比 < 1。相邻对差分只能消掉**慢漂移**，
## 消不掉逐帧抖动 ⇒ 唯一出路是**堆样本**：180 帧 ≈ 89 对 / 轮 × 4 轮 ≈ 356 对
## ⇒ 均值标准误 ≈ σ√2/√356 ≈ 0.10 ms，才够用 2 SE 去判一条 1.00 ms 的红线。
const MAG_ALT_SAMPLE := 180

var _mag_hud: FlightHUD = null
var _mag_me: PlayerController = null
var _mag_root: Node = null
var _mag_pm0 := 0
var _mag_vp0: SubViewport = null
var _mag_frozen: Array = []
var _mag_pl: LockOnSystem = null
var _mag_foe: FlightBody = null
var _mag_suppress := false
var _mag_range0 := 0.0
var _mag_limit0 := 0
var _mag_col := {}   # 标签 -> {"ms": Array, "proc": Array, "draw": Array, "prim": Array}
var _mag_diag := {}  # 标签 -> 档末回读子视口贴图的统计
## 标签 -> {"alt": 全轮**相邻对**原始样本, "push": 同上} —— 提高精度只能靠并池堆样本。
var _mag_pool := {}
## 本次实际跑了几轮（`--magrot` 时 5 轮拉丁方，否则 4 轮）。报告里一律读它，别读常量。
var _mag_rounds_used := MAG_ROUNDS


## 把「放大镜开着」所需的状态摆好（**产品代码零改动**，只推它读的那几个量）。
##
## ⚠️ 门是 `FlightHUD.magnifier_active()`，它读 `lock.target`（有效且存活）、`rifle_count > 0`、
## `player.aim_assist_enabled()`。所以 A/B 的杠杆取 **`lock.target`**，**不取辅助驾驶开关** ——
## 用后者当杠杆会把「辅助飞行本身的开销」混进来，那是另一个变量。
##
## ⚠️ 两个必须改的锁定参数（不改的话目标会被系统自己踢掉，量出来是「压根没开」）：
##   · `seeker_range` 默认 46575 m、脱锁距离 = ×`LOCK_BREAK_MULT`(1.6) ≈ 74.5 km，
##     而编队战的 AI 在 ~90 km 外 ⇒ `_validate_group()` 下一物理帧就把它移出组。
##   · `auto_engage_limit` 必须置 0：`seeker_range` 一抬，候选表里就有东西了，
##     「② 无锁定」那一档（组是空的）会被**自动接战**塞回一个目标 ⇒ 那一档就不是基线了。
func _mag_prepare(m: Node) -> bool:
	_mag_root = m
	_mag_hud = m.get("hud") as FlightHUD
	_mag_me = m.get("player") as PlayerController
	if _mag_hud == null or _mag_me == null:
		print("[mag] ✗ 拿不到 hud / player")
		return false
	if _mag_hud._mag_vp == null:
		print("[mag] ✗ hud 里没有 `_mag_vp` —— 产品侧的放大镜底座没建起来")
		return false
	_mag_pl = _mag_me.lock
	if _mag_pl == null:
		print("[mag] ✗ `player.lock` 为 null")
		return false
	# ⚠️⚠️ 选目标必须**排掉距离过近的**：`_aim_magnifier_at()` 在「目标与自机几乎重合」时会
	# 提前 return（`dir.length_squared() < 1.0`）⇒ 相机留在 `(0, 0, 0)` 看 −Z，
	# 镜里渲的是**地图原点**，读数跟「目标机那 400 m 处的近景」毫无关系 —— 而日志一个字不报。
	# 第一次跑就是这么废的（选到的目标「距玩家 0.0 km」）⇒ 取**最远的**那台。
	var best: FlightBody = null
	var best_d := 0.0
	for u in _all_type(m, "FlightBody"):
		var fb := u as FlightBody
		if fb == _mag_me or not fb.alive:
			continue
		var d := _mag_me.global_position.distance_to(fb.global_position)
		if fb.is_hostile_to(_mag_me):
			d += 1.0e9   # 敌方优先（真机图要出人），但退化时也必须有得选
		if d > best_d:
			best_d = d
			best = fb
	_mag_foe = best
	if _mag_foe == null:
		print("[mag] ✗ 场上没有第二台存活机体")
		return false
	_mag_range0 = _mag_pl.seeker_range
	_mag_limit0 = _mag_pl.auto_engage_limit
	_mag_pl.seeker_range = 300000.0
	_mag_pl.auto_engage_limit = 0
	_mag_me.assist_on = true
	print("[mag] 就绪：目标 %s · 距玩家 %.1f km · seeker_range %.0f → 300000 m · auto_engage_limit %d → 0 · assist_on = true"
		% [_mag_foe.display_name, _mag_me.global_position.distance_to(_mag_foe.global_position) / 1000.0,
			_mag_range0, _mag_limit0])
	print("[mag] 底座：子视口 %s · 尺寸 %s · world_3d %s · far %.0f · 面板矩形 %s"
		% [_mag_hud._mag_vp.name, str(_mag_hud._mag_vp.size),
			"已接主世界（显式）" if _mag_hud._mag_vp.world_3d != null else "null（未显式接；引擎会继承主世界）",
			_mag_hud._mag_cam.far, str(_mag_hud.magnifier_rect(_mag_hud.size))])
	return true


## 仪器自检：相机**真的**摆到离目标 `MAG_CAM_DIST` 了吗？
##
## ⚠️⚠️ 这一条不可省。`_aim_magnifier_at()` 在「目标与自机几乎重合」时会提前 return
## （`dir.length_squared() < 1.0`）⇒ 相机留在 `(0, 0, 0)` 看 −Z，镜里渲的是**地图原点**，
## 三档读数照样"跑得很好看"，而日志一个字都不报。
## 本轮第一次跑就是这么废的：选到的目标「距玩家 0.0 km」。
func _mag_cam_check() -> String:
	if _mag_hud._mag_vp == null:
		return "（本档底座已摘：不渲染、不摆位）"
	var cam := _mag_hud._mag_cam
	var d := cam.global_position.distance_to(_mag_foe.global_position)
	var look := cam.global_position.direction_to(_mag_foe.global_position)
	var ang := rad_to_deg((-cam.global_transform.basis.z).angle_to(look))
	return "摆位自检：相机距目标 %7.1f m · 朝向夹角 %6.2f° ⇒ %s" % [d, ang,
		"已摆好" if absf(d - FlightHUD.MAG_CAM_DIST) < 1.0 else "**没摆到（读数作废）**"]


## 把底座从 HUD 上摘下来 / 装回去。
##
## 这是**把"放大镜"与"锁定 UI"拆开**的唯一干净杠杆：
## 门里第一条就是 `_mag_vp == null ⇒ false`（那是"底座还没建"的正常状态），
## 而锁定 `target` / 步枪 / 辅助驾驶**一个都不动** ⇒
## `● 基准 − ③ 底座摘掉` = **面板那三样绘制 + 门求值的开销**，锁定 UI 被完全抵掉。
func _mag_detach_vp() -> void:
	if _mag_vp0 == null:
		_mag_vp0 = _mag_hud._mag_vp
	_mag_hud._mag_vp = null


func _mag_attach_vp() -> void:
	if _mag_vp0 != null:
		_mag_hud._mag_vp = _mag_vp0


## 把世界冻住（`main` 子树全停）。
##
## ⚠️ 不冻的话 60 帧一档里自机还在飞、AI 还在合围：同一档三轮的绘制调用能从
## 1289 飘到 4061（本轮第一次跑就是这么废的）—— 那点差**远大于**要量的 1.0 ms。
## 冻法 = `main.process_mode = DISABLED`：**不动 `get_tree().paused`**
##（那会把探针自己一起停掉）。HUD 自己是 `PROCESS_MODE_ALWAYS`（main.gd 设的）
## ⇒ 要量的那一件事（HUD 每帧画 + 放大镜每 5 帧推一次）**照旧在跑**，其余静止。
## ⚠️ 只把 `main` 设 DISABLED **不够**（本轮实测踩到）：`DISABLED` 只让"INHERIT 的后代"跟着停，
## 而显式设过 `process_mode` 的节点（本工程不少）**自己的档位优先** ⇒ 机体照飞、
## `TIME_PHYSICS_PROCESS` 照样 6~30 ms、绘制调用一档之内从 3040 飘到 5079。
## ⇒ 必须**逐个**把这些显式档位的后代也设成 DISABLED（HUD 那一支整棵跳过）。
func _mag_freeze() -> void:
	if _mag_root == null or not is_instance_valid(_mag_root):
		return
	_mag_pm0 = _mag_root.process_mode
	var stack: Array = [_mag_root]
	var n := 0
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd.process_mode != Node.PROCESS_MODE_INHERIT or nd == _mag_root:
			if nd != _mag_hud:
				_mag_frozen.append([nd, nd.process_mode])
				nd.process_mode = Node.PROCESS_MODE_DISABLED
				n += 1
		if nd == _mag_hud:
			continue   # HUD 那一支整棵不碰（它是 ALWAYS：要量的那件事就在里面）
		for c in nd.get_children():
			stack.append(c)
	print("[mag] 世界已冻：main 子树里 %d 个节点被设成 DISABLED（含显式档位的后代；HUD 那一支跳过）"
		% n)


func _mag_thaw() -> void:
	for pair in _mag_frozen:
		var nd: Node = pair[0]
		if is_instance_valid(nd):
			nd.process_mode = int(pair[1])
	_mag_frozen.clear()
	if _mag_root != null and is_instance_valid(_mag_root):
		_mag_root.process_mode = _mag_pm0


## 门逐条（**每次采样前打一行** —— 否则三档读数一样时分不清「没差别」和「压根没开」）。
func _mag_gate_line() -> String:
	var tg := "无"
	var alv := "-"
	var lk := _mag_hud.lock
	if lk != null and lk.target != null and is_instance_valid(lk.target):
		tg = str(lk.target.display_name)
		alv = str(lk.target.alive)
	var rif := -1
	var asst := "-"
	if _mag_me != null:
		rif = _mag_me.rifle_count
		asst = str(_mag_me.aim_assist_enabled())
	return "active=%s · 子视口=%s · 目标=%s · 存活=%s · 步枪=%d · 辅助=%s" % [
		str(_mag_hud.magnifier_active()),
		"有" if _mag_hud._mag_vp != null else "**无**", tg, alv, rif, asst]


## 摆成某一档。
##
## `on` = 锁不锁（门）；`suppress` = 是否把「推帧」那一步按掉。
##
## ⚠️ `suppress` 的落实**在每帧**（见 `_frames_mag()` / `_sample_mag()`），不是在这里写一次 ——
## 因为 `_tick_magnifier()` 每帧都会重新决定要不要写 `UPDATE_ONCE`。
## 杠杆 = 每帧把 `_mag_frame` 按回 1：`_tick_magnifier()` 里 `_mag_frame += 1` 之后
## `2 % MAG_PUSH_EVERY != 0` ⇒ **永远不写 `UPDATE_ONCE`**；
## 而门、`_draw_magnifier()` 那三样（贴图 + 外框 + 一行字）**照旧全做**
## ⇒ 这一档就是「只少了那一次子视口渲染」。
func _mag_set(on: bool, suppress: bool) -> void:
	_mag_suppress = suppress
	var want: FlightBody = _mag_foe if on else null
	# ⚠️ 只在**真的变了**才赋值：`_set_main()` 没有早退，重复赋同一个目标也会
	# 走一遍 `target_changed` / `_sync_lock_signal()`，而 `lock_acquired` 会触发一次
	# `Audio.play_self("ui_confirm")` —— 那点开销会跟着采样窗口飘进来。
	if _mag_pl.target != want:
		_mag_pl.target = want
	if on:
		_mag_hud._aim_magnifier_at(_mag_foe)
		print("[mag]   %s" % _mag_cam_check())
	if suppress:
		_mag_hud._mag_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


## 把镜面抹黑（只在 ● 档开始前调一次）。
##
## 为什么必须有：`UPDATE_DISABLED` 只是**不再渲染**，贴图里**留着最后一帧**
## ⇒ 第 2、3 轮的 ● 档若不清一下，档末回读到的是**上一轮 ① 的画面**，
## 那一档「镜面全黑」这个独立证据就变成了残影、反而会把我自己骗过去。
##
## 做法：把相机 `far` 压到近平面附近、推一帧 ⇒ 那一帧什么都被裁掉 ⇒ 贴图回背景色。
## 比「把 `world_3d` 置空再放回」轻，也不碰视口与贴图对象本身。
func _mag_wipe() -> void:
	var far0 := _mag_hud._mag_cam.far
	_mag_hud._mag_cam.far = 1.5
	_mag_hud._mag_frame = 1
	_mag_hud._mag_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	_mag_hud._mag_cam.far = far0
	_mag_hud._mag_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_mag_hud._mag_frame = 1


func _frames_mag(k: int, suppress: bool) -> void:
	for i in k:
		await get_tree().process_frame
		if suppress:
			_mag_hud._mag_frame = 1


## 与 `_sample()` **同口径**，只多两件事：
##   ① 抑制档每帧把 `_mag_frame` 按回 1（见 `_mag_set()`）；
##   ② 顺带数「门开了几帧」。
##
## ⚠️ `await get_tree().process_frame` 恢复执行的时刻 = **本帧节点 `_process` 之前**
## （`SceneTree` 先发 `process_frame` 信号、再走节点 `_process`）
## ⇒ 在这里改 `_mag_frame` 对**本帧**的 `_tick_magnifier()` 生效，不必多等一帧。
func _sample_mag(frames: int, suppress: bool, alt_vp := false, burn_us := 0) -> Dictionary:
	var dts: Array[float] = []
	var pushes: Array[bool] = []
	# ⚠️ `alts[i]` = **上一帧**运行时底座在不在（`dts[i]` 量的正是上一帧）
	var alts: Array[bool] = []
	# 相邻对差分（见 `MAG_ALT_SAMPLE` 上方注释）：两侧前后紧挨 ⇒ 慢漂移彻底消掉
	var pair_alt: Array[float] = []
	var pair_push: Array[float] = []
	var draws: Array[float] = []
	var prims: Array[float] = []
	var t_proc := 0.0
	var t_phys := 0.0
	var n_active := 0
	var prev := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
		# ⚠️ 顺序：**先读** `_mag_frame`（它此刻是上一帧 tick 完的值），**再**写抑制值。
		# 上一帧是推帧 ⟺ `_mag_frame` 是 `MAG_PUSH_EVERY` 的整数倍（`_tick_magnifier()` 先自增再取模）。
		var f := _mag_hud._mag_frame
		var pf := f > 0 and f % FlightHUD.MAG_PUSH_EVERY == 0
		# ⚠️ 底座在不在也**必须在翻之前**读：此刻读到的是上一帧用过的那个状态。
		var po := _mag_hud._mag_vp != null
		if suppress:
			_mag_hud._mag_frame = 1
		if alt_vp:
			# 逐帧交替摘 / 装。摘 = `_mag_vp = null`（与 ③ 档同一个杠杆，不碰节点树本身）
			# ⇒ 上一帧「全做」、这一帧「门第一条即 false」，两帧紧挨 ⇒ 漂移几乎全抵。
			if po:
				_mag_detach_vp()
			else:
				_mag_attach_vp()
		if burn_us > 0:
			# ⚠️ 位置负对照：这段忙等**必须落在「读 `now` 之前」**才会进 `dts[i]`。
			# 量值已知（= burn_us/1000 ms）⇒ 两路分解的 `b[1]` 应读出它。
			var t_burn := Time.get_ticks_usec()
			while Time.get_ticks_usec() - t_burn < burn_us:
				pass
		var now := Time.get_ticks_usec()
		dts.append(float(now - prev) / 1000.0)
		pushes.append(pf)
		alts.append(po)
		prev = now
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		t_proc += Performance.get_monitor(Performance.TIME_PROCESS)
		t_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		if _mag_hud.magnifier_active():
			n_active += 1
	# **档内配对**：把 60 帧按「刚过去那一帧推没推」分成两堆。
	# `dts[i]` 量的是上一帧的时长 ⇒ `pushes[i]` 说的正是那一帧。
	# 这一刀比"跨档配对"更狠：两堆来自同一档、前后紧挨，漂移几乎完全抵消。
	var push_dt: Array[float] = []
	var rest_dt: Array[float] = []
	# 第二刀（`alt_vp` 那档用）：按「上一帧底座在不在」分两堆，同一把尺。
	var on_dt: Array[float] = []
	var off_dt: Array[float] = []
	for i in dts.size():
		if i == 0:
			continue
		if pushes[i]:
			push_dt.append(dts[i])
		else:
			rest_dt.append(dts[i])
		if alts[i]:
			on_dt.append(dts[i])
		else:
			off_dt.append(dts[i])
		# 相邻对：`i` 与 `i + 1` 是**紧邻的两帧**，取「有 − 无」，方向统一成正号。
		if i + 1 < dts.size():
			if alts[i] and not alts[i + 1]:
				pair_alt.append(dts[i] - dts[i + 1])
			elif alts[i + 1] and not alts[i]:
				pair_alt.append(dts[i + 1] - dts[i])
			if pushes[i] and not pushes[i + 1]:
				pair_push.append(dts[i] - dts[i + 1])
	dts.sort()
	draws.sort()
	prims.sort()
	var n := float(maxi(frames, 1))
	return {
		"ms_avg": _mean(dts),
		"ms_p50": _pct(dts, 0.50),
		"ms_p95": _pct(dts, 0.95),
		"ms_max": dts[dts.size() - 1] if dts.size() > 0 else 0.0,
		"fps": 1000.0 / maxf(_mean(dts), 0.001),
		"proc_ms": t_proc / n * 1000.0,
		"phys_ms": t_phys / n * 1000.0,
		"draw": draws[draws.size() / 2] if draws.size() > 0 else 0.0,
		"prim": prims[prims.size() / 2] if prims.size() > 0 else 0.0,
		"active": n_active,
		"push_ms": _mean(push_dt),
		"rest_ms": _mean(rest_dt),
		"n_push": push_dt.size(),
		"n_rest": rest_dt.size(),
		"on_ms": _mean(on_dt),
		"off_ms": _mean(off_dt),
		"n_on": on_dt.size(),
		"n_off": off_dt.size(),
		"pair_alt": pair_alt,
		"pair_push": pair_push,
		"n_pair_alt": pair_alt.size(),
		"n_pair_push": pair_push.size(),
	}


## 档末回读一次子视口贴图 —— **独立证据**证明这一档到底渲没渲。
##
## 为什么要这一条：三档帧时间如果落在噪声里，光看 ms 分不清
## 「放大镜很便宜」和「放大镜压根没渲」。镜面均亮读的是**引擎自己那张图**、
## 不是我们自己的记账；它同时就是「镜里有没有东西」最直接的那个数（用户看的就是这个）。
func _mag_tex_stat() -> Dictionary:
	if _mag_hud._mag_vp == null:
		return {"txt": "无底座（本档不渲染）", "mean": -1.0}
	await RenderingServer.frame_post_draw
	var tex := _mag_hud._mag_vp.get_texture()
	if tex == null:
		return {"txt": "读不到贴图", "mean": -1.0}
	var img := tex.get_image()
	if img == null:
		return {"txt": "读不到图像", "mean": -1.0}
	img.convert(Image.FORMAT_RGB8)
	var w := img.get_width()
	var h := img.get_height()
	var step := maxi(1, int(maxf(float(w), float(h)) / 60.0))
	var sum := 0.0
	var nb := 0
	var n := 0
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			var l := (c.r + c.g + c.b) / 3.0
			sum += l
			n += 1
			if l > 0.02:
				nb += 1
	var mean := sum / maxf(float(n), 1.0)
	return {"txt": "均亮 %.4f · 非黑 %d/%d" % [mean, nb, n], "mean": mean}


func _mag_col_add(label: String, r: Dictionary) -> void:
	if not _mag_col.has(label):
		_mag_col[label] = {"ms": [], "proc": [], "draw": [], "prim": [],
			"push": [], "rest": [], "n_push": [], "n_rest": [],
			"on": [], "off": [], "n_on": [], "n_off": [], "pal": [], "ppu": []}
	var cc: Dictionary = _mag_col[label]
	(cc["ms"] as Array).append(float(r["ms_avg"]))
	(cc["proc"] as Array).append(float(r["proc_ms"]))
	(cc["draw"] as Array).append(float(r["draw"]))
	(cc["prim"] as Array).append(float(r["prim"]))
	(cc["push"] as Array).append(float(r["push_ms"]))
	(cc["rest"] as Array).append(float(r["rest_ms"]))
	(cc["n_push"] as Array).append(float(r["n_push"]))
	(cc["n_rest"] as Array).append(float(r["n_rest"]))
	(cc["on"] as Array).append(float(r["on_ms"]))
	(cc["off"] as Array).append(float(r["off_ms"]))
	(cc["n_on"] as Array).append(float(r["n_on"]))
	(cc["n_off"] as Array).append(float(r["n_off"]))
	(cc["pal"] as Array).append(_median(r["pair_alt"]))
	(cc["ppu"] as Array).append(_median(r["pair_push"]))


func _mag_col_get(label: String, key: String) -> Array:
	var out: Array = []
	if _mag_col.has(label):
		var cc: Dictionary = _mag_col[label]
		if cc.has(key):
			out = cc[key]
	return out


static func _mag_delta(a: Array, b: Array) -> Array:
	var out: Array = []
	for k in mini(a.size(), b.size()):
		out.append(float(a[k]) - float(b[k]))
	return out


func _stage_mag(label: String, suppress: bool, alt_vp := false, burn_us := 0) -> void:
	# 静置：换档那一下会发 `lock_acquired`（带一次 UI 音效）—— 让它响完再进采样窗口。
	await _frames_mag(20, suppress)
	await _frames_mag(STAGE_WARM, suppress)
	print("[mag] %-24s 门：%s" % [label, _mag_gate_line()])
	# 交替档要量的信号只有 ~0.35 ms，必须用长窗口堆样本（见 `MAG_ALT_SAMPLE` 注释）。
	var n_smpl := MAG_ALT_SAMPLE if alt_vp else STAGE_SAMPLE
	var r := await _sample_mag(n_smpl, suppress, alt_vp, burn_us)
	# ⚠️ 交替档收尾**必须装回去**：末帧可能停在「摘掉」那一半 ⇒ 下一档与档末回读
	# 会看到 `_mag_vp == null`，后面每一档都变成「底座不在」而**一个字都不报**。
	if alt_vp:
		_mag_attach_vp()
	_mag_col_add(label, r)
	if not _mag_pool.has(label):
		_mag_pool[label] = {"alt": [], "push": []}
	var pool: Dictionary = _mag_pool[label]
	(pool["alt"] as Array).append_array(r["pair_alt"])
	(pool["push"] as Array).append_array(r["pair_push"])
	var ev := await _mag_tex_stat()
	_mag_diag[label] = ev
	# ⚠️ `③ 底座摘掉` 那一档 `_mag_vp` 是 **null** —— 这里直接取 `.render_target_update_mode`
	# 会在**打印行**上炸（数据其实已经入账 ⇒ 日志里只有 ERROR、读数照样有 = 假绿）。
	# 本轮真的踩到过（4 轮 4 条 SCRIPT ERROR）。
	var mode := -1
	if _mag_hud._mag_vp != null:
		mode = _mag_hud._mag_vp.render_target_update_mode
	print("[mag] %-24s 帧 %6.2f ms (p50 %6.2f p95 %6.2f)  进程 %5.2f  物理 %5.2f  绘制 %5d  图元 %8d  门开 %3d/%d  模式 %d  镜面 %s"
		% [label, r["ms_avg"], r["ms_p50"], r["ms_p95"], r["proc_ms"], r["phys_ms"],
			int(r["draw"]), int(r["prim"]), int(r["active"]), n_smpl, mode, ev["txt"]])
	print("[mag] %-24s 档内配对：推帧 %6.2f ms（%d 帧）· 非推帧 %6.2f ms（%d 帧）· 单次推帧代价 %+6.2f ms"
		% [label, r["push_ms"], int(r["n_push"]), r["rest_ms"], int(r["n_rest"]),
			float(r["push_ms"]) - float(r["rest_ms"])])
	if alt_vp:
		print("[mag] %-24s ② 档内配对（交替档）：装底座 %6.2f ms（%d 帧）· 摘底座 %6.2f ms（%d 帧）· 单帧差 %+6.2f ms"
			% [label, r["on_ms"], int(r["n_on"]), r["off_ms"], int(r["n_off"]),
				float(r["on_ms"]) - float(r["off_ms"])])
		print("[mag] %-24s **相邻对**（装 − 紧邻摘）：%d 对 ⇒ 中位 %6.2f · 均值 %6.2f ± %.2f ms（1 SE）"
			% [label, int(r["n_pair_alt"]), _median(r["pair_alt"]), _mean(r["pair_alt"]),
				_sd_of(r["pair_alt"]) / sqrt(maxf(float(int(r["n_pair_alt"])), 1.0))])
	await _frames_mag(6, suppress)


## 判据 6 的读数台。
##
## ## 五档（每轮都测 ⇒ 同轮配对；单轮顺序分解不可用，见 `_decompose()` 的注释）
##   `● 基准（锁定 · 按掉推帧）`：门开着、HUD 那三样照画，只把「推帧」按掉。
##       作用是**把 CPU 侧与渲染侧分开**。
##   `① 放大镜（产品原样）`：`① − ●` = 那一次子视口渲染（每 `MAG_PUSH_EVERY` 帧摊一次）。
##   `③ 锁定 · 底座摘掉`：`● − ③` = 面板 + 门。
##   `② 无锁定（放大镜关）`：`① − ②` = 玩家实际感到的开 / 关差。
##   `④ 面板档内配对（每帧交替摘 / 装底座）`：**轮 63-10b 加的**。档内配对量
##       「门 + 摆位 + 面板三样」；与 ① 档自己的档内配对（推帧代价 ÷ `MAG_PUSH_EVERY`）相加
##       = `① − ③` 的**档内版**（漂移全抵，不受跨档噪声支配）—— 本轮就是拿它签字的。
## 当前轮次的档序（下标数组）。`--magrot` 时把基准序整体左移 `rd` 位。
func _mag_order_for(rd: int) -> Array:
	var out: Array = []
	var n := MAG_LABELS.size()
	for k in n:
		out.append((k + rd) % n if mag_rot else k)
	return out

## 档序的可读形式（`●①③②④`），只取标签首字符。
func _mag_order_txt(order: Array) -> String:
	var s := ""
	for idx in order:
		s += str(MAG_LABELS[int(idx)]).substr(0, 1)
	return s

## 跑一档。**每一档先归一状态** —— `--magrot` 之后前驱可能是任何一档：
##   · `③` 摘掉的 `_mag_vp` 必须带回来，否则后面每一档都静默变成「底座不在」（一个字都不报）；
##   · `●` 的「抹黑镜面」跟着它走，不管它排在第几位。
func _mag_stage(idx: int, burn_us: int) -> void:
	_mag_attach_vp()
	if idx == 0:
		# ● 基准：锁定在、门开着、面板照画，只把「推帧」按掉（= 把渲染侧剥掉）
		_mag_set(true, true)
		await _mag_wipe()
		await _stage_mag(MAG_LABELS[0], true, false, burn_us)
	elif idx == 1:
		# ① 产品原样
		_mag_set(true, false)
		await _stage_mag(MAG_LABELS[1], false, false, burn_us)
	elif idx == 2:
		# ③ 锁定仍在、底座摘掉 ⇒ 只留锁定 UI（把「面板 + 门」剥掉）
		_mag_set(true, true)
		_mag_detach_vp()
		await _stage_mag(MAG_LABELS[2], true, false, burn_us)
	elif idx == 3:
		# ② 真实基线：无锁定
		_mag_set(false, false)
		await _stage_mag(MAG_LABELS[3], false, false, burn_us)
	else:
		# ④ 第二把档内尺：锁定在、推帧按掉、**每帧交替摘 / 装底座**
		#    ⇒ 单帧差 = 门求值 + 相机摆位 + 面板三样绘制（**不含**子视口渲染）
		_mag_set(true, true)
		await _stage_mag(MAG_LABELS[4], true, true, burn_us)


func _mag_pair(m: Node) -> void:
	if not _mag_prepare(m):
		return
	await _frames(20)
	_mag_freeze()
	await _frames(40)
	print("[mag] 冻结自检：物理 %.2f ms/帧（未冻时 6~30）· 绘制调用 %d（未冻时会来回飘几千）"
		% [Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	_mag_rounds_used = MAG_ROT_ROUNDS if mag_rot else MAG_ROUNDS
	print("[mag] 交错 %d 轮 × %d 档（每档 静置 20 + 预热 %d + 采样 %d 帧）；档间立即还原 ⇒ 一轮里只差一个变量%s"
		% [_mag_rounds_used, MAG_LABELS.size(), STAGE_WARM, STAGE_SAMPLE,
			"；**档序每轮轮转 1 位**（拉丁方 ⇒ 档身份与轮内位置正交）" if mag_rot else ""])
	if _mag_burn_us > 0:
		print("[mag] ⚠️ 位置负对照已开：1 号位那一档每一帧忙等 %d µs（= %.3f ms/帧）⇒ 分解的 b[1] 应读出这个值"
			% [_mag_burn_us, float(_mag_burn_us) / 1000.0])
	for rd in _mag_rounds_used:
		var order := _mag_order_for(rd)
		print("[mag] 第 %d/%d 轮 · 档序 = %s" % [rd + 1, _mag_rounds_used, _mag_order_txt(order)])
		for pos in order.size():
			var burn := _mag_burn_us if (mag_rot and pos == 0) else 0
			await _mag_stage(int(order[pos]), burn)
		print("[mag] 第 %d/%d 轮完成" % [rd + 1, _mag_rounds_used])
	# 末档若是 ③（底座被摘掉）⇒ 装回去，免得报告与档末回读看到 null。
	_mag_attach_vp()
	_mag_restore()
	_mag_report()


## 把探针动过的锁定参数还原（不还的话「下一次跑同一台」就不成立）。
func _mag_restore() -> void:
	_mag_thaw()
	if _mag_pl == null:
		return
	_mag_pl.target = null
	_mag_pl.seeker_range = _mag_range0
	_mag_pl.auto_engage_limit = _mag_limit0


func _mag_report() -> void:
	var l0 := str(MAG_LABELS[0])
	var l1 := str(MAG_LABELS[1])
	var l2 := str(MAG_LABELS[2])
	var l3 := str(MAG_LABELS[3])
	var d_ctl: Array = _mag_delta(_mag_col_get(l1, "ms"), _mag_col_get(l3, "ms"))   # ① − ② 字面口径
	var d_own: Array = _mag_delta(_mag_col_get(l1, "ms"), _mag_col_get(l2, "ms"))   # ① − ③ 放大镜本体
	var d_render: Array = _mag_delta(_mag_col_get(l1, "ms"), _mag_col_get(l0, "ms"))  # ① − ● 跨档
	var d_panel: Array = _mag_delta(_mag_col_get(l0, "ms"), _mag_col_get(l2, "ms"))  # ● − ③ 面板+门
	var d_lock: Array = _mag_delta(_mag_col_get(l2, "ms"), _mag_col_get(l3, "ms"))   # ③ − ② 锁定 UI
	var p1: Array = _mag_delta(_mag_col_get(l1, "push"), _mag_col_get(l1, "rest"))
	print("---- 放大镜 A/B（%d 轮 · 世界已冻）----" % _mag_rounds_used)
	print("%-26s %8s %8s %8s %8s %8s %7s %9s" % ["档位", "档ms中位", "Δvs●", "最小", "最大", "进程ms", "绘制", "图元"])
	for i in MAG_LABELS.size():
		var lab := str(MAG_LABELS[i])
		var ms: Array = _mag_col_get(lab, "ms")
		var dd: Array = _mag_delta(ms, _mag_col_get(l0, "ms"))
		print("%-26s %8.2f %8.2f %8.2f %8.2f %8.2f %7d %9d"
			% [lab, _median(ms), _median(dd), _min_of(dd), _max_of(dd),
				_median(_mag_col_get(lab, "proc")),
				int(_median(_mag_col_get(lab, "draw"))), int(_median(_mag_col_get(lab, "prim")))])
	print("")
	print("---- ① 档的**档内配对**（同一档里「推帧那一帧」− 「其余帧」：每帧成对、前后紧挨）----")
	print("[mag] ① 单次推帧代价：中位 %6.2f ms（min %6.2f / max %6.2f）（推帧 %d 帧 vs 其余 %d 帧）"
		% [_median(p1), _min_of(p1), _max_of(p1),
			int(_median(_mag_col_get(l1, "n_push"))), int(_median(_mag_col_get(l1, "n_rest")))])
	print("[mag] ● 同一把尺的控制组：推帧 %d 帧（按掉了，本该没有）⇒ 该档不可比"
		% int(_median(_mag_col_get(l0, "n_push"))))
	var amort := _median(p1) / float(FlightHUD.MAG_PUSH_EVERY)
	print("[mag] ⇒ 摊到每帧 = 单次推帧代价 / %d = %6.2f ms"
		% [FlightHUD.MAG_PUSH_EVERY, amort])
	print("")
	print("---- ④ 档的**档内配对**（每帧交替摘 / 装底座；推帧已按掉）----")
	var l4 := str(MAG_LABELS[4])
	var p2: Array = _mag_delta(_mag_col_get(l4, "on"), _mag_col_get(l4, "off"))
	print("[mag] ④ 两堆均值：装底座 %6.2f ms（%d 帧）· 摘底座 %6.2f ms（%d 帧）· 差 %+6.2f ms"
		% [_median(_mag_col_get(l4, "on")), int(_median(_mag_col_get(l4, "n_on"))),
			_median(_mag_col_get(l4, "off")), int(_median(_mag_col_get(l4, "n_off"))),
			_median(p2)])
	print("[mag] ④ 每轮中位（看 min/max，别看中位一个数）：%s  ⇒ 中位 %6.2f（min %+6.2f / max %+6.2f）"
		% [_fmt_arr(_mag_col_get(l4, "pal")), _median(p2), _min_of(p2), _max_of(p2)])
	# ---- 相邻对差分（全轮并池）----
	var pool4: Dictionary = _mag_pool.get(l4, {})
	var pool1: Dictionary = _mag_pool.get(l1, {})
	var pa: Array = pool4.get("alt", [])
	var pp: Array = pool1.get("push", [])
	print("[mag] ④ **相邻对差分**（装 − 紧邻摘）：合并 %d 对 ⇒ 中位 %6.2f · **均值 %6.2f ± %.2f ms**（1 SE）"
		% [pa.size(), _median(pa), _mean(pa),
			_sd_of(pa) / sqrt(maxf(float(pa.size()), 1.0))])
	print("[mag] ① **相邻对差分**（推帧 − 紧邻非推帧）：合并 %d 对 ⇒ 中位 %6.2f · **均值 %6.2f ± %.2f ms**"
		% [pp.size(), _median(pp), _mean(pp),
			_sd_of(pp) / sqrt(maxf(float(pp.size()), 1.0))])
	print("[mag] ⇒ ④ 相邻对均值 = 门 + 摆位 + 面板三样 = %6.2f ms（同一件事的跨档读数是 ●−③ %6.2f ms）"
		% [_mean(pa), _median(_mag_delta(_mag_col_get(l0, "ms"), _mag_col_get(l2, "ms")))])
	print("")
	print("---- 分解（同一轮配对，每项都是两档相减）----")
	print("[mag] ① − ●  那一次子视口渲染（每 %d 帧摊一次）：中位 %6.2f ms（min %6.2f / max %6.2f）"
		% [FlightHUD.MAG_PUSH_EVERY, _median(d_render), _min_of(d_render), _max_of(d_render)])
	print("[mag] ● − ③  面板三样绘制 + 门求值：中位 %6.2f ms（min %6.2f / max %6.2f）"
		% [_median(d_panel), _min_of(d_panel), _max_of(d_panel)])
	print("[mag] ① − ③  ⇒ **放大镜本体**（渲染 + 面板）：中位 %6.2f ms（min %6.2f / max %6.2f）"
		% [_median(d_own), _min_of(d_own), _max_of(d_own)])
	print("[mag] ③ − ②  锁定 UI（**不是放大镜的账**）：中位 %6.2f ms（min %6.2f / max %6.2f）"
		% [_median(d_lock), _min_of(d_lock), _max_of(d_lock)])
	print("[mag] ① − ②  字面口径「开 / 关」= 放大镜本体 + 锁定 UI：中位 %6.2f ms（min %6.2f / max %6.2f）"
		% [_median(d_ctl), _min_of(d_ctl), _max_of(d_ctl)])
	var addi := _median(d_own) + _median(d_lock)
	print("[mag] 加性自检：①−③ + ③−② = %6.2f ms，与 ①−② = %6.2f ms 之差 %+6.2f ms（≈ 跨档噪声）"
		% [addi, _median(d_ctl), addi - _median(d_ctl)])
	var med := _median(d_own)
	print("[mag] 判据 6 断言（放大镜本体 ①−③ ≤ 1.00 ms）：中位 %6.2f ms ⇒ %s（区间 [%.2f, %.2f]）"
		% [med, "PASS" if med <= 1.0 else "**FAIL**", _min_of(d_own), _max_of(d_own)])
	print("[mag] 判据 6 字面读法（①−② ≤ 1.00 ms）中位 %6.2f ms ⇒ %s（含锁定 UI %6.2f ms）"
		% [_median(d_ctl), "PASS" if _median(d_ctl) <= 1.0 else "**FAIL**", _median(d_lock)])
	# ---- 档内版：两项都取自档内配对（不受跨档漂移支配）----
	var p2b: Array = _mag_delta(_mag_col_get(l4, "on"), _mag_col_get(l4, "off"))
	var p1b: Array = _mag_delta(_mag_col_get(l1, "push"), _mag_col_get(l1, "rest"))
	var d_own_in: Array = []
	for k in mini(p2b.size(), p1b.size()):
		d_own_in.append(float(p2b[k]) + float(p1b[k]) / float(FlightHUD.MAG_PUSH_EVERY))
	print("[mag] 判据 6【档内版】= 面板 %6.2f + 渲染 %6.2f/%d = **%6.2f ms** ⇒ %s（区间 [%.2f, %.2f]）"
		% [_median(p2b), _median(p1b), FlightHUD.MAG_PUSH_EVERY, _median(d_own_in),
			"PASS" if _median(d_own_in) <= 1.0 else "**FAIL**",
			_min_of(d_own_in), _max_of(d_own_in)])
	# ---- 相邻对版（并池 + 1 SE）：本轮用来**签字**的那把尺 ----
	var pool4b: Dictionary = _mag_pool.get(l4, {})
	var pool1b: Dictionary = _mag_pool.get(l1, {})
	var pa2: Array = pool4b.get("alt", [])
	var pp2: Array = pool1b.get("push", [])
	var rnd := _mean(pp2) / float(FlightHUD.MAG_PUSH_EVERY)
	var se_a := _sd_of(pa2) / sqrt(maxf(float(pa2.size()), 1.0))
	var se_p := _sd_of(pp2) / float(FlightHUD.MAG_PUSH_EVERY) / sqrt(maxf(float(pp2.size()), 1.0))
	var own_m := _mean(pa2) + rnd
	var own_se := sqrt(se_a * se_a + se_p * se_p)
	var vd := "**FAIL**"
	if own_m + 2.0 * own_se <= 1.0:
		vd = "PASS"
	elif own_m - 2.0 * own_se <= 1.0:
		vd = "**边缘（2 SE 跨线 ⇒ 判不了）**"
	print("[mag] 判据 6【相邻对版】= 面板 %6.2f ± %.2f + 渲染 %6.2f ± %.2f = **%6.2f ± %.2f ms**（1 SE）⇒ %s"
		% [_mean(pa2), se_a, rnd, se_p, own_m, own_se, vd])
	print(("[mag] ↑ 相邻对（同档内**紧邻两帧**相减，慢漂移彻底消掉）+ 并池 %d/%d 对；"
		+ "判决规则 = 均值 + 2 SE 是否越 1.00 ms") % [pa2.size(), pp2.size()])
	print("")
	print("[mag] 独立证据（档末回读子视口贴图）：")
	for i in MAG_LABELS.size():
		var lab := str(MAG_LABELS[i])
		var ev: Dictionary = _mag_diag.get(lab, {})
		print("[mag]   %-24s %s" % [lab, str(ev.get("txt", "?"))])


func _write_mag() -> void:
	var path := out_dir.path_join("mag.txt")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	var l0 := str(MAG_LABELS[0])
	var l1 := str(MAG_LABELS[1])
	var l2 := str(MAG_LABELS[2])
	var l3 := str(MAG_LABELS[3])
	var l4 := str(MAG_LABELS[4])
	f.store_line("轮 63-10 · D3b 放大镜 · 判据 6（开 / 关帧时差 ≤ 1.0 ms）的读数台")
	f.store_line("轮 63-10b 起：判据 6 以【档内版】签字（面板档内配对 + 渲染档内配对/5）；跨档版仅存档")
	f.store_line("编队战 14 台 · 交错 %d 轮 × %d 档 · 每档 静置 20 + 预热 %d + 采样 %d 帧 · 同轮配对取中位"
		% [_mag_rounds_used, MAG_LABELS.size(), STAGE_WARM, STAGE_SAMPLE])
	f.store_line("探针动作：只推 player.lock.target（+ seeker_range 46575→300000、auto_engage_limit→0）；**产品代码零改动**")
	f.store_line("⚠️ 单轮顺序分解不可用（轮 41 实测 ±40% 噪声）⇒ 只认同轮配对的多轮中位与 min/max")
	f.store_line("")
	f.store_line("%-26s %9s %9s %9s %9s %9s %7s %9s %s" % ["档位", "档ms中位", "Δvs●", "最小", "最大", "进程ms", "绘制", "图元", "镜面(档末回读)"])
	for i in MAG_LABELS.size():
		var lab := str(MAG_LABELS[i])
		var ms: Array = _mag_col_get(lab, "ms")
		var dd: Array = _mag_delta(ms, _mag_col_get(l0, "ms"))
		var ev: Dictionary = _mag_diag.get(lab, {})
		f.store_line("%-26s %9.2f %9.2f %9.2f %9.2f %9.2f %7d %9d %s"
			% [lab, _median(ms), _median(dd), _min_of(dd), _max_of(dd),
				_median(_mag_col_get(lab, "proc")),
				int(_median(_mag_col_get(lab, "draw"))), int(_median(_mag_col_get(lab, "prim"))),
				str(ev.get("txt", "?"))])
	f.store_line("")
	f.store_line("---- 档内配对（同一档里「推帧那一帧」− 「其余帧」：每帧成对、前后紧挨，漂移几乎全抵）----")
	for i in MAG_LABELS.size():
		var lab := str(MAG_LABELS[i])
		var pp: Array = _mag_delta(_mag_col_get(lab, "push"), _mag_col_get(lab, "rest"))
		f.store_line("%-26s 推帧均值 %7.2f  非推帧均值 %7.2f  单次推帧代价 %8.2f  (min %8.2f / max %8.2f)"
			% [lab, _median(_mag_col_get(lab, "push")), _median(_mag_col_get(lab, "rest")),
				_median(pp), _min_of(pp), _max_of(pp)])
	var p1: Array = _mag_delta(_mag_col_get(l1, "push"), _mag_col_get(l1, "rest"))
	f.store_line("")
	f.store_line("① 单次推帧代价中位 %8.2f ms ÷ MAG_PUSH_EVERY(%d) = 每帧摊 %8.2f ms"
		% [_median(p1), FlightHUD.MAG_PUSH_EVERY, _median(p1) / float(FlightHUD.MAG_PUSH_EVERY)])
	var pp2: Array = _mag_delta(_mag_col_get(l4, "on"), _mag_col_get(l4, "off"))
	f.store_line("④ 两堆均值差（每帧交替）：中位 %8.2f  (min %8.2f / max %8.2f)"
		% [_median(pp2), _min_of(pp2), _max_of(pp2)])
	f.store_line("④ 每轮中位：%s"
		% [_fmt_arr(_mag_col_get(l4, "pal"))])
	var pa3: Array = (_mag_pool.get(l4, {}) as Dictionary).get("alt", [])
	var pp3: Array = (_mag_pool.get(l1, {}) as Dictionary).get("push", [])
	f.store_line("④ **相邻对**（装 − 紧邻摘）：%d 对 ⇒ 中位 %8.2f  均值 %8.2f ± %.2f ms (1 SE)"
		% [pa3.size(), _median(pa3), _mean(pa3), _sd_of(pa3) / sqrt(maxf(float(pa3.size()), 1.0))])
	f.store_line("① **相邻对**（推帧 − 紧邻非推帧）：%d 对 ⇒ 中位 %8.2f  均值 %8.2f ± %.2f ms (1 SE)"
		% [pp3.size(), _median(pp3), _mean(pp3), _sd_of(pp3) / sqrt(maxf(float(pp3.size()), 1.0))])
	f.store_line("")
	var d_render: Array = _mag_delta(_mag_col_get(l1, "ms"), _mag_col_get(l0, "ms"))
	var d_own: Array = _mag_delta(_mag_col_get(l1, "ms"), _mag_col_get(l2, "ms"))
	var d_lock: Array = _mag_delta(_mag_col_get(l2, "ms"), _mag_col_get(l3, "ms"))
	var d_ctl: Array = _mag_delta(_mag_col_get(l1, "ms"), _mag_col_get(l3, "ms"))
	var pp1: Array = _mag_delta(_mag_col_get(l1, "push"), _mag_col_get(l1, "rest"))
	f.store_line("① − ●  那一次子视口渲染（每 %d 帧摊一次）     中位 %8.2f  最小 %8.2f  最大 %8.2f"
		% [FlightHUD.MAG_PUSH_EVERY, _median(d_render), _min_of(d_render), _max_of(d_render)])
	f.store_line("  （档内配对独立量同一件事：单次推帧代价中位 %8.2f ÷ %d = %8.2f）"
		% [_median(pp1), FlightHUD.MAG_PUSH_EVERY, _median(pp1) / float(FlightHUD.MAG_PUSH_EVERY)])
	f.store_line("① − ③  放大镜本体（渲染 + 面板）           中位 %8.2f  最小 %8.2f  最大 %8.2f  <= 判据 6"
		% [_median(d_own), _min_of(d_own), _max_of(d_own)])
	f.store_line("③ − ②  锁定 UI（不是放大镜的账）             中位 %8.2f  最小 %8.2f  最大 %8.2f"
		% [_median(d_lock), _min_of(d_lock), _max_of(d_lock)])
	f.store_line("① − ②  字面口径「开 / 关」（本体 + 锁定 UI）  中位 %8.2f  最小 %8.2f  最大 %8.2f"
		% [_median(d_ctl), _min_of(d_ctl), _max_of(d_ctl)])
	f.store_line("")
	var d_own_in: Array = []
	for k in mini(pp2.size(), pp1.size()):
		d_own_in.append(float(pp2[k]) + float(pp1[k]) / float(FlightHUD.MAG_PUSH_EVERY))
	var rnd3 := _mean(pp3) / float(FlightHUD.MAG_PUSH_EVERY)
	var se3 := sqrt(pow(_sd_of(pa3) / sqrt(maxf(float(pa3.size()), 1.0)), 2.0)
		+ pow(_sd_of(pp3) / float(FlightHUD.MAG_PUSH_EVERY) / sqrt(maxf(float(pp3.size()), 1.0)), 2.0))
	var m3 := _mean(pa3) + rnd3
	var v3 := "FAIL"
	if m3 + 2.0 * se3 <= 1.0:
		v3 = "PASS"
	elif m3 - 2.0 * se3 <= 1.0:
		v3 = "边缘（2 SE 跨线）"
	f.store_line("判据 6【相邻对版】（面板相邻对 + 渲染相邻对/5 ≤ 1.00 ms）：%8.2f ± %.2f ms (1 SE) ⇒ %s"
		% [m3, se3, v3])
	f.store_line("判据 6【档内版·两堆均值】（仅供对照）：%8.2f  ⇒ %s  (min %8.2f / max %8.2f)"
		% [_median(d_own_in), "PASS" if _median(d_own_in) <= 1.0 else "FAIL",
			_min_of(d_own_in), _max_of(d_own_in)])
	f.store_line("判据 6【跨档版】（放大镜本体 ① − ③ ≤ 1.00 ms）：%8.2f  ⇒ %s  ← 分辨率不足，仅存档"
		% [_median(d_own), "PASS" if _median(d_own) <= 1.0 else "FAIL"])
	f.close()
	print("[mag] 表已写入 ", path)


## 真机判据图：面板在屏幕上的**位置**、镜里**有没有东西**、关掉时**画不画**。
func _mag_shots(m: Node) -> void:
	if not _mag_prepare(m):
		return
	# 真机图也要冻世界：不冻的话"关 → 开"两张图之间自机已经飞出去几百米，
	# 整帧对比就分不清"面板出现了"和"景变了"。
	_mag_freeze()
	var rect := _mag_hud.magnifier_rect(_mag_hud.size)
	var vp := _mag_hud.size
	print("[mag] 视口 %s · 面板矩形 %s · 归一化 %s"
		% [str(vp), str(rect), str(Rect2(rect.position / vp, rect.size / vp))])
	print("[mag] RECT=%d,%d,%d,%d" % [int(rect.position.x), int(rect.position.y),
		int(rect.size.x), int(rect.size.y)])
	# ① 关着（真实基线）：这一块应该是**空的** —— 连框都不该有
	_mag_set(false, false)
	await _frames(60)
	await _shoot("mag_off.png")
	# ② 开着：面板出现 + 镜里是对方机体
	_mag_set(true, false)
	await _frames(60)
	await _shoot("mag_on.png")
	var ev := await _mag_tex_stat()
	print("[mag] 镜面读数（真机）：%s" % ev["txt"])
	print("[mag] 目标 display_name = %s · 相机距目标 %.3f m · fov %.1f° · 门：%s"
		% [_mag_foe.display_name,
			_mag_hud._mag_cam.global_position.distance_to(_mag_foe.global_position),
			_mag_hud._mag_cam.fov, _mag_gate_line()])
	_mag_restore()
