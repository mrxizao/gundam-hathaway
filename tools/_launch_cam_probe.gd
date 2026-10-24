extends Node
## 发射段镜头「抽搐 / 莫名其妙地远」的**量测探针**（2026-09-30）。
##
## 老板原话：
## > 「**你再写一份镜头控制方案，现在的镜头还是很抽搐，而且有时候会远的莫名其妙**」
##
## 它**不拍图、不摆机位**。它让火箭真的飞，每渲染帧记一笔几何量，把两句话落成数：
##   · `dist`（米）= 相机 ↔ 箭心 距离 —— **"远"就是它漂了**
##   · `d_px`（像素）= 箭心在 1600×900 画面里**逐帧跳了多少像素** —— **"抽搐"就是它**
## `d_px` 是这套量测的主角：静止不动的一枚箭，`d_px` 该恒为 0；
## 而"画面在抽"的物理含义就是**同一个物体在相邻两帧落在不同的屏幕位置上**。
## 它同时把**相机自己的转动**算进去了（走 `camera.global_transform` 的逆变换），
## 所以"机身没动、镜头在转"也算数 —— 那同样是玩家眼里的抽。
##
## ## 四种跑法：同一段飞行、同一台相机、同一份代码，只换两件事
## | 跑法 | 相机在哪个回调里落位 | 渲染帧率上限 |
## |---|---|---|
## | `A60`  | `ChaseCamera._physics_process`（**固定 60 Hz**）← 改前的实况 | 60 |
## | `A144` | 同上 | 144 |
## | `B60`  | 渲染帧（`chase.step_now()`，紧跟 `rocket.step()`）← 改后 | 60 |
## | `B144` | 同上 | 144 |
## 读法：若 A 的 `d_px` 随帧率升高而暴涨、B 两档都≈0 ⇒
## 根因就是「火箭在 `_process`（渲染帧）积分、相机在 `_physics_process`（60 Hz）落位」
## 这对**不同钟**，与算法、与美术一点关系都没有。
##
## ## 第五种跑法 `H60`：故意卡一帧（模拟换图 / 着色器编译那种百毫秒级的长帧）
## 它只回答第二个问题：**一次长帧会不会把箭甩到"莫名其妙的地方"**。
## 长帧的 `delta` 会整份喂进 `RocketBody.step()` 的显式欧拉积分
##（`velocity += accel·dt`、`position += velocity·dt`），
## 还带着 `LEASH_M = 9000` 的安全绳 ⇒ 记 `max_track_err` 与 `leash_count` 两个自证数。
##
## ⚠️ 帧率用 `Engine.max_fps` + **关 vsync** 强制，不靠显示器刷新率：
## 要的是"可复现的一组对照"，不是"复刻这台机器的观感"。
##
## ## 为什么预热用"紧循环"而不是真等 45 秒
## 抖动只在末段（`v ≈ 13 km/s`）才量得出来，而飞到那儿真实时间要 45 s。
## 预热按 `dt = 1/60`（就是标称时间表）紧循环推进，**与真实飞行逐位同源**，
## 只是不渲染 —— 42 s 的上升在 CPU 上是几毫秒。
## ⚠️ 预热里**不 `await`**：一旦 `await` 就会插进真实的物理帧，
## 那几帧的相机位置会被记进预热（不该记）。

const ROOT := "C:/Users/MSIPC/WorkBuddy/2026-09-27-13-34-43/"
## 预热到 u 的哪一位。0.70 时箭速 ≈ 13.3 km/s、箭底 ≈ 151 km —— 抖动最凶的区间。
const WARM_U := 0.70
## 采样窗口（模拟秒）。四种跑法取同一个窗口 ⇒ 覆盖同一段 u、同一个速度量级。
const WINDOW_S := 2.0
## `H60` 那一跑卡帧的长度（秒）。换图建图实测就在 100~400 ms 这个量级。
const HITCH_S := 0.35
## 名义视口（画布上报的 `d_px` 一律按它折算，与 `_rocket_shots` 出的图同尺寸）。
const VIEW_W := 1600.0
const VIEW_H := 900.0

const RUNS := [
	{"tag": "A60", "expose": false, "fps": 60, "hitch": false},
	{"tag": "A144", "expose": false, "fps": 144, "hitch": false},
	{"tag": "B60", "expose": true, "fps": 60, "hitch": false},
	{"tag": "B144", "expose": true, "fps": 144, "hitch": false},
	{"tag": "H60", "expose": true, "fps": 60, "hitch": true},
]

var out_dir := ROOT + "_cam_probe_20260930"
var world: WorldBuilder = null
var rocket: RocketBody = null
var chase: ChaseCamera = null
var _t_sim := 0.0
## `true` ⇒ 帧率由命令行 `--fixed-fps` 给，本探针**不设 `Engine.max_fps`**
##（两处都设会互相盖，而"到底跑在几赫兹"就成了一个要读代码才能回答的问题）。
var fixed_mode := false
## 写到文件名里的后缀，两趟（vsync 限帧 / `--fixed-fps`）不互相覆盖。
var tag_suffix := ""


func _ready() -> void:
	# ⚠️ 看门狗：带窗口跑时 `_ready()` 里任何一条抛错都会静默中断协程，
	# 而 `quit()` 在最后一行 ⇒ 进程**永远不退出**（`_rocket_shots` 踩过）。
	get_tree().create_timer(600.0).timeout.connect(_on_watchdog)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		fixed_mode = args[1] == "fixed"
	if args.size() > 2:
		tag_suffix = args[2]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(960, 540))
	# ⚠️ 关 vsync + 自己限帧：不然"帧率"这一列变成了"这台显示器多少赫兹"，
	# 而这一份对照要的是**可复现**。
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	world = WorldBuilder.new()
	add_child(world)
	await get_tree().physics_frame
	Game.active_map = MapDef.pacific()
	world.apply_map(Game.active_map)
	await _frames(20)

	var rows: Array = []
	for run in RUNS:
		var row: Dictionary = await _run(run)
		rows.append(row)
	_report(rows)
	get_tree().quit()


## 跑一种配置，返回它的汇总（同时写一份逐帧 CSV）。
func _run(run: Dictionary) -> Dictionary:
	var tag: String = str(run["tag"]) + tag_suffix
	# ⚠️ `--fixed-fps` 那一路**不设** `Engine.max_fps`：两处都设会互相盖。
	Engine.max_fps = 0 if fixed_mode else int(run["fps"])
	print("== [%s] 开始：相机落位在 %s，帧率上限 %s（vsync 现状=%d，max_fps=%d）"
		% [tag, "渲染帧" if bool(run["expose"]) else "物理帧 60 Hz",
			"命令行 --fixed-fps" if fixed_mode else str(int(run["fps"])),
			DisplayServer.window_get_vsync_mode(), Engine.max_fps])

	# ---- 一台全新的相机（`externally_stepped` 是实例状态，不能带着上一跑的残留）----
	if chase != null and is_instance_valid(chase):
		chase.queue_free()
		chase = null
		await _frames(3)

	# ---- 一枚全新的箭 ----
	rocket = RocketBody.new()
	rocket.name = "ProbeRocket"
	rocket.configure(LaunchScript.ASCENT_SPAN)
	add_child(rocket)
	rocket.place_at_launch(
		LaunchScript.launch_pos() + Vector3(0.0, LaunchScript.rest_alt(), 0.0))
	# ⚠️ 不挂模型：这一段量的是**几何**（相机 ↔ 箭心），模型一个字都影响不到。
	#（挂了也只是白等 40 MB 资产的载入时间。）

	# ---- 预热：紧循环推进到 WARM_U ----
	var warm_steps := int(WARM_U * LaunchScript.ASCENT_SPAN * 60.0)
	for i in warm_steps:
		rocket.step(1.0 / 60.0, 0.0, 0.0, 0.0)
	rocket.max_track_err = 0.0
	rocket.leash_count = 0

	# ---- 挂相机：**与 `main._begin_launch()` 同一条链** ----
	chase = ChaseCamera.new()
	chase.name = "ProbeChase"
	add_child(chase)
	chase.set_target(rocket)
	chase.set_launch_view(true)
	chase.externally_stepped = bool(run["expose"])
	await _frames(6)

	# ---- 采样 ----
	var rec: Array = []
	var prev_px := Vector2.ZERO
	var prev_off := -1.0
	var prev_dist := -1.0
	var have_prev := false
	var frames := 0
	var hitch_done := false
	_t_sim = 0.0
	while _t_sim < WINDOW_S and frames < 6000:
		if bool(run["hitch"]) and not hitch_done and _t_sim >= 0.5:
			# ★ 故意卡 350 ms：下一帧的 `delta` 就是 0.35 s 上下。
			hitch_done = true
			OS.delay_msec(int(HITCH_S * 1000.0))
		await get_tree().process_frame
		frames += 1
		var delta := get_process_delta_time()
		# ★ 与 `main._tick_launch()` **同一条链、同一个次序**：先推进箭，再让相机落位。
		if rocket.u < 1.0:
			rocket.step(delta, 0.0, 0.0, 0.0)
		if bool(run["expose"]):
			chase.step_now(delta)
		_t_sim += delta

		# ---- 量：箭心落在画面的哪儿 ----
		var inv := chase.global_transform.affine_inverse()
		var loc: Vector3 = inv * rocket.global_position
		var cam_fwd := -chase.global_transform.basis.z
		var to_rocket := rocket.global_position - chase.global_position
		var dist := to_rocket.length()
		var off := 0.0
		if dist > 0.001:
			off = rad_to_deg(cam_fwd.angle_to(to_rocket))
		var px := Vector2.ZERO
		var on_screen := loc.z < -0.05
		if on_screen:
			var t2 := tan(deg_to_rad(chase.fov) * 0.5)
			var nx := loc.x / (-loc.z) / (t2 * (VIEW_W / VIEW_H))
			var ny := loc.y / (-loc.z) / t2
			px = Vector2(nx * VIEW_W * 0.5, -ny * VIEW_H * 0.5)
		var d_px := 0.0
		if have_prev and on_screen:
			d_px = px.distance_to(prev_px)
		rec.append({
			"t": _t_sim, "dt": delta, "v": rocket.speed(),
			"alt": rocket.global_position.y, "u": rocket.u,
			"dist": dist, "off": off, "px_x": px.x, "px_y": px.y, "d_px": d_px,
			"phys": Engine.get_physics_frames(), "fps": Engine.get_frames_per_second(),
			"err": (LaunchScript.ascent_pos(rocket.u) - rocket.global_position).length(),
		})
		prev_px = px
		prev_off = off
		prev_dist = dist
		have_prev = true

	_write_csv(tag, rec)
	var row := _summary(tag, run, rec)
	print("== [%s] 完：%d 帧 / 模拟 %.2f s / 实测 %.0f fps / 箭速 %.1f~%.1f km/s"
		% [tag, rec.size(), _t_sim,
			float(row["fps"]), float(row["v_lo"]) / 1000.0, float(row["v_hi"]) / 1000.0])
	return row


## 一跑的汇总。**只用第 6 帧之后的数据** —— 前几帧是"相机刚落位"的过渡
##（预热期间它根本没跟，第一帧必然是一次大跳），把它算进去等于自己造一个假读数。
func _summary(tag: String, run: Dictionary, rec: Array) -> Dictionary:
	var dpx: Array = []
	var offs: Array = []
	var dists: Array = []
	var dts: Array = []
	var v_lo := 1.0e30
	var v_hi := 0.0
	var i := 0
	for r in rec:
		i += 1
		if i <= 6:
			continue
		dpx.append(float(r["d_px"]))
		offs.append(absf(float(r["off"])))
		dists.append(float(r["dist"]))
		dts.append(float(r["dt"]))
		v_lo = minf(v_lo, float(r["v"]))
		v_hi = maxf(v_hi, float(r["v"]))
	var out := {
		"tag": tag, "expose": bool(run["expose"]), "fps_cap": int(run["fps"]),
		"frames": rec.size(), "run_s": _t_sim,
		"fps": 0.0,
		"leash": rocket.leash_count, "err": rocket.max_track_err,
		"v_lo": v_lo, "v_hi": v_hi,
		"d_px_mean": _mean(dpx), "d_px_p95": _pct(dpx, 0.95), "d_px_max": _max(dpx),
		"off_mean": _mean(offs), "off_lo": _min(offs), "off_hi": _max(offs),
		"phys_per_frame": _phys_ratio(rec),
		"dist_mean": _mean(dists), "dist_min": _min(dists), "dist_max": _max(dists),
		"dt_mean": _mean(dts), "dt_max": _max(dts),
	}
	out["fps"] = (1.0 / out["dt_mean"]) if float(out["dt_mean"]) > 0.0 else 0.0
	return out


## 渲染帧 : 物理帧。**这一列是"两个钟"的直接证据** ——
## 它等于 1.0 时两个钟同拍（相位恒定），不等于 1.0 时每帧的相位都在滑。
func _phys_ratio(rec: Array) -> float:
	var n := 0
	var first := -1
	var last := -1
	for r in rec:
		var f := int(r["phys"])
		if first < 0:
			first = f
		last = f
		n += 1
	if n <= 1 or first < 0:
		return 0.0
	return float(last - first) / float(n - 1)


func _write_csv(tag: String, rec: Array) -> void:
	var f := FileAccess.open("%s/%s_frames.csv" % [out_dir, tag], FileAccess.WRITE)
	if f == null:
		push_error("CSV 打不开：%s" % tag)
		return
	f.store_line("t_s,dt_s,v_ms,alt_m,u,dist_m,off_deg,px_x,px_y,d_px,phys_frame,fps,track_err_m")
	for r in rec:
		f.store_line("%.5f,%.5f,%.1f,%.1f,%.5f,%.4f,%.3f,%.2f,%.2f,%.3f,%d,%d,%.1f" % [
			float(r["t"]), float(r["dt"]), float(r["v"]), float(r["alt"]), float(r["u"]),
			float(r["dist"]), float(r["off"]), float(r["px_x"]), float(r["px_y"]),
			float(r["d_px"]), int(r["phys"]), int(r["fps"]), float(r["err"])])
	f.close()


## 一跑一行，写成表（同时打到 stdout，日志里能直接读）。
func _report(rows: Array) -> void:
	var lines: Array = []
	lines.append("# 发射段镜头量测 · %d 种配置" % rows.size())
	lines.append("# 箭速覆盖 %.1f~%.1f km/s（u %.2f 起）" % [
		float(rows[0]["v_lo"]) / 1000.0, float(rows[0]["v_hi"]) / 1000.0, WARM_U])
	lines.append("#")
	lines.append("| 跑法 | 相机落位 | 限帧 | 实测 fps | 物理帧/渲染帧 | 帧数 | **箭心逐帧位移 d_px（像素 / 1600×900）** | | | 离箭距离 dist（米） | | 偏离视轴 | 安全绳 |")
	lines.append("|" + "---|".repeat(13))
	lines.append("| | | | | | | 均值 | p95 | **最大** | 均值 | 极差 | 极差 | 触发 |")
	for r in rows:
		lines.append("| `%s` | %s | %s | %.0f | %.2f | %d | %.1f | %.1f | **%.1f** | %.2f | %.2f | %.1f~%.1f° | %d |" % [
			r["tag"], "渲染帧" if bool(r["expose"]) else "物理帧",
			"fixed" if fixed_mode else str(int(r["fps_cap"])),
			float(r["fps"]), float(r["phys_per_frame"]), int(r["frames"]),
			float(r["d_px_mean"]), float(r["d_px_p95"]), float(r["d_px_max"]),
			float(r["dist_mean"]), float(r["dist_max"]) - float(r["dist_min"]),
			float(r["off_lo"]), float(r["off_hi"]), int(r["leash"])])
	lines.append("| | | | | | | | | | | | |")
	lines.append("| `d_px` 均值 | 就是「机体中心在相邻两帧之间跳了多少像素」（含相机的转动） | | | | | | | | | | |")
	lines.append("| `dist` 均值 / 极差 | 刚性追尾该是 **80.92 m 恒定**；极差一栏是**「远得莫名其妙」的量化** | | | | | | | | | | |")
	lines.append("| 偏离视轴均值 | 机体中心相对**视轴**的固定夹角（≈18° 是因为视线落在箭体中段，不是抖动） | | | | | | | | | | |")
	lines.append("| `物理帧/渲染帧` | =1.0 两个钟同拍；≠1.0 每帧的采样相位都在滑（`--fixed-fps 144` 该读出 ≈0.42） | | | | | | | | | | | |")
	lines.append("| `偏离视轴` 极差 | 相机**看向哪儿**的稳定性。只报距离是不够的：B 档改前距离精确而视线跑了 115° | | | | | | | | | | | |")
	lines.append("| 安全绳触发 | `RocketBody.leash_count`：名义上升（无输入）该是 **0** | | | | | | | | | | | |")
	var text := "\n".join(lines) + "\n"
	var f := FileAccess.open(out_dir + "/0_量测汇总.md", FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	print(text)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _on_watchdog() -> void:
	print("!! 看门狗超时 ⇒ 探针某处卡住（`_ready()` 里抛错会静默中断协程）")
	get_tree().quit()


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for x in a:
		s += float(x)
	return s / float(a.size())


func _min(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var m: float = float(a[0])
	for x in a:
		m = minf(m, float(x))
	return m


func _max(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var m: float = float(a[0])
	for x in a:
		m = maxf(m, float(x))
	return m


func _pct(a: Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	var i := int(round(q * float(b.size() - 1)))
	return float(b[clampi(i, 0, b.size() - 1)])
