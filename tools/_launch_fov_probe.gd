extends Node
## 发射段「FOV 速度项」的**量测探针**（2026-09-30 晚）。
##
## ## 要回答的问题
## `ChaseCamera._update_fov()` 里那一段是**鸭子类型**读目标的速度：
## ```gdscript
## if t.has_method("speed_fov_mix"):          # 目标自报（0…1）
##     sp = clampf(t.speed_fov_mix(), 0.0, 1.0)
## elif t.has_method("airspeed_kmh"):          # 通用窗口（机体域 300…1900 km/h）
##     sp = clampf((t.airspeed_kmh() - 300.0) / 1600.0, 0.0, 1.0)
## ```
## `RocketBody` 原本**两个都没有** ⇒ `sp` 恒 0 ⇒ 整个 60 s 上升里 FOV 恒 68°，
## 最后 35 km/s 一点广角都不张。
##
## 本探针把**整段上升的 FOV 曲线**落成数：每一帧走 `main._tick_launch()` 的
## **同一条链、同一个次序** —— 先 `rocket.step(dt)`、再 `chase.step_now(dt)` ——
## 记 `u / 高度 / 速度 / sp / FOV`。
##
## ## 三趟对照（同一份探针，只改工程侧的实现）
## | tag | 工程状态 | FOV 曲线 |
## |---|---|---|
## | `before` | 两个方法都没有 | 恒 68.00°（速度项**是死的**） |
## | `after` | 只加 `airspeed_kmh()`（吃通用窗口） | 68° → **90°**，但**第 8 s 就顶死**、之后 44 s 一动不动（平台占 79%） |
## | `soft` | 加 `speed_fov_mix()`（对数响应） | 68.00° → 79.8°，**全程连续**张开、无平台 |
##
## ⚠️ 只看「极差」会被 `after` 骗到：它极差 22°（最大），但那是把
## 「速度项是死的」换成了「速度项 3/4 时间不动」。**主判据是 `t95`**
##（FOV 走完 95% 行程的时刻占全程的比例）：越大越"全程都在张"。
##
## ## 为什么**不做**倒计时那 8 s
## 倒计时期间 `main._tick_launch()` 在 `_launch_countdown > 0` 分支里**早退**，
## 压根不调 `rocket.step()`（箭浸在水里静止）⇒ 速度 0、`sp` 0、FOV 68°。
## 那 8 s 在研究"速度项有没有活"这件事上不含任何信息，故从 `u = 0` 起跑。
##
## ## 命令行
## ```
## godot --headless --path . res://tools/_launch_fov_probe.tscn -- [out_dir] [tag]
## ```
## `tag` 写进文件名（`before_fov.csv` / `after_fov.csv` / `soft_fov.csv`），互不覆盖。
##
## ⚠️ 纯几何 + 纯标量，**不需要窗口**（不读 MultiMesh、不抓帧）⇒ 可以 headless。
## 仍挂看门狗：`_ready()` 里任何一条抛错都会静默中断协程，`quit()` 到不了。

const ROOT := "C:/Users/MSIPC/WorkBuddy/2026-09-27-13-34-43/"

## 采样步长 = 标称时间表（与 `main._tick_launch()` 的 dt 同量级）。
const DT := 1.0 / 60.0
## 上升名义 60 s ⇒ 3 600 步。多给 5% 余量，防止 `u` 最后一位的浮点残差。
const MAX_STEPS := 5000

var out_dir := ROOT + "_fov_probe"
var tag := "run"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		tag = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().create_timer(240.0).timeout.connect(_on_watchdog)

	var rocket := RocketBody.new()
	rocket.name = "FovProbeRocket"
	rocket.configure(LaunchScript.ASCENT_SPAN)
	add_child(rocket)
	rocket.place_at_launch(
		LaunchScript.launch_pos() + Vector3(0.0, LaunchScript.rest_alt(), 0.0))

	var chase := ChaseCamera.new()
	chase.name = "FovProbeChase"
	add_child(chase)
	# ⚠️ `set_target()` 必须在 `set_launch_view()` **之前**：后者会立刻落位一次。
	chase.set_target(rocket)
	chase.set_launch_view(true)
	chase.externally_stepped = true
	# 相机自己也是"刚建好"的状态 —— 先让它落一次位，再开始记。
	chase.step_now(DT)

	_run(rocket, chase)
	get_tree().quit()


func _run(rocket: RocketBody, chase: ChaseCamera) -> void:
	var rec: Array = []
	var t := 0.0
	var steps := 0
	while rocket.u < 1.0 and steps < MAX_STEPS:
		rocket.step(DT, 0.0, 0.0, 0.0)
		chase.step_now(DT)
		t += DT
		steps += 1
		rec.append({
			"t_s": t, "u": rocket.u, "alt_m": rocket.global_position.y,
			"v_ms": rocket.speed(),
			"kmh": rocket.airspeed_kmh() if rocket.has_method("airspeed_kmh") else 0.0,
			# ★ `sp` = **相机真正吃到的那一个**（目标自报优先）。
			#   `sp_old` = 旧那条通用窗口，只留作对照 —— 改前它才是相机吃的。
			"sp": rocket.speed_fov_mix() if rocket.has_method("speed_fov_mix")
				else clampf(((rocket.airspeed_kmh() if rocket.has_method("airspeed_kmh")
					else 0.0) - 300.0) / 1600.0, 0.0, 1.0),
			"sp_old": clampf(((rocket.airspeed_kmh() if rocket.has_method("airspeed_kmh")
				else 0.0) - 300.0) / 1600.0, 0.0, 1.0),
			"fov": chase.fov,
			"dist_m": chase.global_position.distance_to(rocket.global_position),
		})
	_write_csv(rec)
	_milestones(rec)
	print("== [%s] 完：%d 步 / 模拟 %.2f s / u 终值 %.6f / 箭速终值 %.0f m/s"
		% [tag, steps, t, rocket.u, rocket.speed()])


## 每 5 s 一行 —— 这一份就是"FOV 随速度怎么走"的读数表。
func _milestones(rec: Array) -> void:
	print("== [%s] 里程碑（每 5 s 一行）" % tag)
	print("     t(s)    u      高度(km)  速度(m/s)  速度(km/h)   sp      FOV(°)")
	var next := 0.0
	for r: Dictionary in rec:
		if float(r["t_s"]) + 1e-9 < next:
			continue
		next += 5.0
		print("   %6.1f  %.4f  %8.2f  %9.1f  %10.1f  %.4f  %6.2f"
			% [r["t_s"], r["u"], float(r["alt_m"]) / 1000.0, r["v_ms"], r["kmh"],
				r["sp"], r["fov"]])
	# ---- 三个判据数 ----
	var f0: float = rec[0]["fov"]
	var fmax := 0.0
	var hi := 0.0
	var hi_old := 0.0
	var t_first_open := -1.0
	for r: Dictionary in rec:
		var f := float(r["fov"])
		fmax = maxf(fmax, f)
		hi = maxf(hi, float(r["sp"]))
		hi_old = maxf(hi_old, float(r["sp_old"]))
		if t_first_open < 0.0 and float(r["sp"]) > 0.001:
			t_first_open = float(r["t_s"])
	print("== [%s] 判据：" % tag)
	print("   · FOV 首值 %.2f° / 峰值 %.2f° / 全程极差 %.2f°" % [f0, fmax, fmax - f0])
	if t_first_open < 0.0:
		print("   · `sp` **全程为 0**（速度项是死的 —— 目标两个方法都没有）")
	else:
		print("   · `sp` 首次 > 0 于 t = %.2f s（前 %.1f%% 的上升里速度项是死的）"
			% [t_first_open, 100.0 * t_first_open / float(rec[-1]["t_s"])])
		print("   · `sp` 峰值 %.4f（离 1.0 还剩 %.4f ⇒ %s）"
			% [hi, 1.0 - hi, "★ 顶死" if hi >= 1.0 - 1e-6 else "没触顶"])
		print("   · 对照：旧通用窗口 `sp_old` 峰值 %.4f ⇒ %s"
			% [hi_old, "会顶死" if hi_old >= 1.0 - 1e-6 else "不顶死"])
	# ---- ★★ 主判据：`t95`（FOV 走完 95% 行程的时刻占全程的比例）----
	#
	# 只看"极差"会被骗：一条"前 8 s 冲到顶、之后 44 s 一动不动"的曲线
	# 极差也是 22°，比本方案（12°）还大 —— 但那是"速度项 3/4 时间不动"。
	# `t95` 越大 ⇒ 张开越铺满全程。
	var t95 := -1.0
	var mark := f0 + 0.95 * (fmax - f0)
	for r: Dictionary in rec:
		if t95 < 0.0 and float(r["fov"]) >= mark:
			t95 = float(r["t_s"])
	if t95 < 0.0:
		print("   · `t95` 测不到（FOV 没动过）")
	else:
		print("   · ★ `t95` = %.2f s ⇒ 全程的 %.1f%%（越大越「全程都在张」；"
			% [t95, 100.0 * t95 / float(rec[-1]["t_s"])]
			+ "「8 s 顶死」那档只有 ~20%）")
	print("   · FOV 全程非减：%s" % ("是" if _is_monotone(rec) else "★ 否（有回撤）"))
	print("   · `dist` 极差 %.4f m（应与 `LAUNCH_OFFSET.length()` 逐位相等）"
		% _range(rec, "dist_m"))


## FOV 是否全程非减（`lerp` 平滑下允许 1e-4 的数值抖动）。
func _is_monotone(rec: Array) -> bool:
	var prev := -1.0e9
	for r: Dictionary in rec:
		var f := float(r["fov"])
		if f < prev - 1e-4:
			return false
		prev = f
	return true


func _range(rec: Array, key: String) -> float:
	var lo: float = rec[0][key]
	var hi: float = rec[0][key]
	for r: Dictionary in rec:
		lo = minf(lo, float(r[key]))
		hi = maxf(hi, float(r[key]))
	return hi - lo


func _write_csv(rec: Array) -> void:
	var p := out_dir + "/" + tag + "_fov.csv"
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		push_error("写不了 %s" % p)
		return
	f.store_line("t_s,u,alt_m,v_ms,kmh,sp,sp_old,fov,dist_m")
	for r: Dictionary in rec:
		f.store_line("%.5f,%.6f,%.3f,%.3f,%.3f,%.6f,%.6f,%.4f,%.4f"
			% [r["t_s"], r["u"], r["alt_m"], r["v_ms"], r["kmh"], r["sp"],
				r["sp_old"], r["fov"], r["dist_m"]])
	f.close()
	print("== [%s] CSV → %s（%d 行）" % [tag, p, rec.size()])


func _on_watchdog() -> void:
	push_error("探针超时（240 s）—— 大概率 `_ready()` 里抛错后协程静默中断")
	get_tree().quit()
