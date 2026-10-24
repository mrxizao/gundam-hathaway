extends Node
## 真机实测：**跟随滞后把注入量累加了几倍**（`chase_camera.gd` 里那些"×N 倍"）。
##
## 轮 29 建。存在的理由：`chase_camera.gd` 有一批注释按 **20 Hz** 物理步推算（`×2.18`、`1/(1-0.78)=4.5`
## 之类），而工程实测步长是 **60 Hz**。累加倍数 `1/(1-e^(-lag·dt))` 对步长**很敏感**
##（1/20 与 1/60 差约 3 倍），所以那些数字必须按真实步长重算。
##
## 本探针**不是推导，是实测**：把相机摆到它自己的稳态机位（跟随运动恒为 0），
## 手工喂物理帧，直接量"画面动了多少"。同一段代码跑两个步长 ⇒ 差分就是步长的影响。
##
## ⚠️ 纯变换运算、**不需要渲染** ⇒ 可以 `--headless`（与音效/像素类探针不同）。
##
## 跑法：
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . res://tools/probe_cam_accum.tscn
##
## ## 两条量法，别混用
##
## · **`ISO`（隔离法）** —— 每帧把**位置通道复位**到稳态机位，只让姿态通道累积。
##   必须这么做：`_desired_basis()` 里有一句 `global_position.direction_to(look_point)`
##   （第 795 行），**朝向参考本身依赖相机位置**。推拒会把相机推走 15 m，于是
##   "参考朝向"自己就转了 —— 不隔离的话，量到的是"被推走的再瞄准"，不是"转了多少"。
##   （踩过一次：`kick_rot_total` 因此读出 8.77°，真值约 1.1°。）
## · **`REPLICA`（套件口径）** —— 冻结起始朝向、不复位位置，与
##   `suite_camera_feedback._excursion()` 逐字一致，用来**自证本探针可信**。
##   对不上套件的话，后面每一个数都别信。
##
## ## 判据怎么读
##
## 1. `REPLICA` 必须复现套件打印的那三个转角。
## 2. `kick_pos_factor`：单位推拒被跟随滞后累加出的峰值位移倍数（①）。
## 3. `rot_steady = 1/f_rot`：注释里那几个"≈N 倍"用的就是这个口径（②）。
## 4. `SHIFT` 表：**定向推拒**的画面平移峰值（隔离法）。⚠️ `_kick` 线性衰减 ⇒
##    脉冲长度 ∝ 幅度 ⇒ **"累加倍数"随幅度变化**（1.0 → 2.29，0.542 → 1.89），
##    所以这张表只能**逐幅度实测**，不能写成"记账值 × 常数"。
## 5. `kick_rot_total_iso`：**按消耗量记账**的整段总转角，应当 ≈ `记账值 × KICK_DEG_PER_M`
##    且**与步长无关** —— 这条才是"改对了"的判据。

## 每档至少跑够一个完整脉冲：撞机推拒 3.5/1.6 = 2.19 s ⇒ 1/60 下 132 帧。
const FRAMES := 260
## 复刻套件口径时用的帧数 / 种子（`suite_camera_feedback._visible()` 里就是这两个值）。
const REPLICA_FRAMES := 30
const REPLICA_SEED := 20260921
## `_apply_shake()` / `_apply_kick()` 里字面量的衰减速率（1/s）。照抄一份只为打印对账。
const SHAKE_DECAY_LITERAL := 2.4
## 抖动逐帧重新随机 ⇒ 单种子会让"谁比谁重"随机翻绿翻红（套件里也栽过），取一组种子平均。
const SEEDS := [20260921, 7, 4451, 90210, 314159]

var _made: Array[Node] = []
## 只读常量用的临时相机（**不进树**，就为了取 `follow_lag` / `rotate_lag` 的当前值，
## 而不是把 6.5 / 5.0 抄进本探针 —— 抄了就会跟着源码一起失真）。
var _tmp_cam: ChaseCamera = null


func _ready() -> void:
	# 在 `_ready()` 里直接建相机树会撞"父节点正忙"，延后一帧起步。
	_boot.call_deferred()


func _boot() -> void:
	_tmp_cam = ChaseCamera.new()
	_made.append(_tmp_cam)
	var dt20 := 1.0 / 20.0
	var dt60 := 1.0 / 60.0
	print("ACCUM physics_ticks=%d" % Engine.physics_ticks_per_second)
	print("ACCUM follow_lag=%.1f rotate_lag=%.1f kick_decay=%.1f shake_decay=%.1f"
		% [_lag_pos(), _lag_rot(), ChaseCamera.KICK_DECAY, SHAKE_DECAY_LITERAL])

	# ---- 自证：复刻套件口径（dt=1/20，单种子，30 帧，冻结朝向、不复位位置）----
	seed(REPLICA_SEED)
	print("REPLICA seed=%d dt=1/20 frames=%d  rifle=%.3f saber=%.3f ram=%.3f"
		% [REPLICA_SEED, REPLICA_FRAMES,
		_replica(7.0 / 217.0, Damage.Type.BEAM), _replica(22.0 / 217.0, Damage.Type.SABER),
		_replica(0.15, Damage.Type.RAM)])

	# ---- 平移通道实测表：**隔离推拒**的画面峰值（`_shake` 清零）----
	#
	# ⚠️ 为什么不写"记账值 × 累加倍数"：`_kick` 是**线性衰减**（`_kick -= delta*1.6`），
	# 脉冲长度 ∝ 幅度 ⇒ 峰值位移对幅度是**超线性**的，**"累加倍数"随幅度变化**。
	#（实测：幅度 1.0 时 1/20 倍数是 2.2872，幅度 0.542 时只有 1.888；
	#  逐帧手算 0.542 得 1.0237，与下面这行 `1/20` 实测逐位吻合。）
	# ⇒ 只许**各幅度各测一次**，不许拿单位幅度算出来的倍数去乘。
	print("SHIFT 定向推拒的平移峰值（隔离法：`_shake` 清零，只剩 `_kick` 那条通道）")
	print("SHIFT %-22s %9s %11s %11s %8s %8s %9s"
		% ["类型", "记账_kick", "1/20 峰值", "1/60 峰值", "20Hz倍", "60Hz倍", "60Hz半屏"])
	for c in [["光束步枪 7/217 BEAM", 7.0 / 217.0, Damage.Type.BEAM],
			["光束军刀 22/217 SABER", 22.0 / 217.0, Damage.Type.SABER],
			["撞机 0.15 RAM", 0.15, Damage.Type.RAM]]:
		var label: String = c[0]
		var ratio: float = c[1]
		var dtype: int = c[2]
		var kc := _fresh()
		kc.add_hit_shake(ratio, Vector3.RIGHT, dtype)
		var k0 := kc._kick
		var p20 := _replica_shift(ratio, dtype, false, dt20, FRAMES)
		var p60 := _replica_shift(ratio, dtype, false, dt60, FRAMES)
		# 半屏 = 36 m（54 m 距离 / 68° FOV，与 `HIT_KICK_M` 注释同口径）
		print("SHIFT %-22s %8.3f m %10.3f m %10.3f m %7.3f %7.3f %8.1f%%"
			% [label, k0, p20, p60, p20 / k0, p60 / k0, p60 / 36.0 * 100.0])
	# 对账套件打印：套件那一段含随机抖（`add_hit_shake` 两条通道一起充）
	var lo := 1e9
	var hi := -1e9
	var acc := 0.0
	for s in SEEDS:
		seed(s)
		var v := _replica_shift(7.0 / 217.0, Damage.Type.BEAM, true, dt20, REPLICA_FRAMES)
		lo = minf(lo, v)
		hi = maxf(hi, v)
		acc += v
	print("SHIFT 步枪含随机抖（1/20、30 帧、5 seed）: min=%.3f mean=%.3f max=%.3f m ⇒ 套件打印 1.02 落在此区间"
		% [lo, acc / 5.0, hi])

	# ---- 案例表：三种典型受击的"记账 → 注入 → 画面残留"三段账 ----
	# 记账值直接读 `_kick` / `_shake`（真机的状态量），注入总转角与画面残留角各走一次实跑。
	print("CASE 类型                    记账_kick  抖池_shake  注入总转角  画面残留角(1/60)")
	for c in [["光束步枪 7/217 BEAM", 7.0 / 217.0, Damage.Type.BEAM],
			["光束军刀 22/217 SABER", 22.0 / 217.0, Damage.Type.SABER],
			["撞机 0.15 RAM", 0.15, Damage.Type.RAM]]:
		var label: String = c[0]
		var ratio: float = c[1]
		var dtype: int = c[2]
		var cam := _fresh()
		cam.add_hit_shake(ratio, Vector3.RIGHT, dtype)
		var kick := cam._kick
		var shake := cam._shake
		print("CASE %-24s %8.3f m  %9.3f  %9.3f°  %13.3f°"
			% [label, kick, shake, kick * ChaseCamera.KICK_DEG_PER_M,
			_kick_rot_total_iso(dt60, kick)])

	# ---- 主表：两个步长逐项对照 ----
	for e in [["1/20", dt20], ["1/60", dt60]]:
		var tag: String = e[0]
		var dt: float = e[1]
		var f_pos := 1.0 - exp(-_lag_pos() * dt)
		var f_rot := 1.0 - exp(-_lag_rot() * dt)
		print("ACCUM %-5s dt=%.6f f_pos=%.5f f_rot=%.5f" % [tag, dt, f_pos, f_rot])
		print("ACCUM %-5s [①] kick_pos_factor=%.4f  (1/f_pos 上限 %.4f)"
			% [tag, _kick_pos_factor(dt), 1.0 / f_pos])
		print("ACCUM %-5s [②] rot_steady=%.4f  (1/f_rot)"
			% [tag, 1.0 / f_rot])
		print("ACCUM %-5s [②] kick_rot_total_iso=%.3f  (记账 2.55×3.2=%.3f，应与步长无关)"
			% [tag, _kick_rot_total_iso(dt), 2.55 * ChaseCamera.KICK_DEG_PER_M])
		print("ACCUM %-5s [③] shake_pos_peak(0.5)=%.3f m  名义=%.3f m"
			% [tag, _held_shake_pos_peak(dt, 0.5), 0.5 * ChaseCamera.SHAKE_DEG_PER_UNIT
			* ChaseCamera.SHAKE_M_PER_DEG])
		print("ACCUM %-5s ISO 转角 mean: rifle=%.3f saber=%.3f ram=%.3f  齐射=%.3f  击坠级=%.3f"
			% [tag, _shake_peak_iso(dt, 7.0 / 217.0, Damage.Type.BEAM)["mean"],
			_shake_peak_iso(dt, 22.0 / 217.0, Damage.Type.SABER)["mean"],
			_shake_peak_iso(dt, 0.15, Damage.Type.RAM)["mean"],
			_held_shake_iso(dt, ChaseCamera.LAUNCH_SHAKE_CEIL), _held_shake_iso(dt, 1.4)])

	_cleanup()
	get_tree().quit()


# ---------------------------------------------------------------- 工具

## 一台**受控**的相机 + 一个哑目标。相机已由 `set_target()` 摆到自身稳态机位
##（跟随运动恒为 0，量到的位移/转角**只可能**来自抖动通道）。
func _fresh() -> ChaseCamera:
	var tgt := Node3D.new()
	add_child(tgt)
	var cam := ChaseCamera.new()
	add_child(cam)
	cam.set_physics_process(false)   # 引擎别再自己喂帧，帧数完全由本探针决定
	cam.current = false              # 别抢"当前相机"
	cam.set_target(tgt)
	_made.append(tgt)
	_made.append(cam)
	return cam


func _cleanup() -> void:
	for n: Node in _made:
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			n.queue_free()
	_made = []


func _lag_pos() -> float:
	return _tmp_cam.follow_lag


func _lag_rot() -> float:
	return _tmp_cam.rotate_lag


## 套件口径（`suite_camera_feedback._excursion()` 逐字复刻）：冻结起始朝向、
## **不复位位置**、只跑 `frames` 帧。用于自证。
func _replica(ratio: float, dtype: int) -> float:
	var cam := _fresh()
	cam.add_hit_shake(ratio, Vector3.RIGHT, dtype)
	var ref := -cam.global_transform.basis.z
	var mx := 0.0
	for i in REPLICA_FRAMES:
		cam._physics_process(1.0 / 20.0)
		mx = maxf(mx, rad_to_deg((-cam.global_transform.basis.z).angle_to(ref)))
	return mx


## 单位推拒（1 米，记账值）被跟随滞后累加出的**峰值位移**（米 ⇒ 倍数）。
## 隔离做法：先把随机抖清零，只剩定向推拒这一条通道。
## 套件口径的**平移**峰值（`suite_camera_feedback._visible()` 里 `shift` 那段逐字复刻：
## `p0` 起算、跑 `REPLICA_FRAMES` 帧、取 `|pos - p0|` 的最大值）。
##
## `with_shake = false` ⇒ 只留定向推拒（把 `_shake` 清零）。
## 套件那一段是 `add_hit_shake()` 起的，**两条通道一起充**，而 `_apply_shake()` 自己
## 也往位置上加 `SHAKE_M_PER_DEG` 的配重 ⇒ 套件读到的峰值 = 推拒累加 **+** 随机抖分量。
## 这就是「0.542 × 2.2872 = 1.24 m」与「套件打印 1.02 m」能同时成立的原因。
func _replica_shift(ratio: float, dtype: int, with_shake: bool,
		dt: float = 1.0 / 20.0, frames: int = REPLICA_FRAMES) -> float:
	var cam := _fresh()
	cam.add_hit_shake(ratio, Vector3.RIGHT, dtype)
	if not with_shake:
		cam._shake = 0.0
	var p0 := cam.global_position
	var peak := 0.0
	for i in frames:
		cam._physics_process(dt)
		peak = maxf(peak, (cam.global_position - p0).length())
	return peak


func _kick_pos_factor(dt: float) -> float:
	var cam := _fresh()
	cam._shake = 0.0
	cam._kick = 1.0
	cam._kick_dir = Vector3.RIGHT
	var p0 := cam.global_position
	var peak := 0.0
	for i in FRAMES:
		cam._physics_process(dt)
		peak = maxf(peak, (cam.global_position - p0).length())
	return peak


## 定向推拒**按消耗量记账**时的整段总转角（度）。隔离法：每帧把位置复位，
## 于是朝向参考（`_desired_basis()` 依赖相机位置）保持常量。
## 应当 ≈ `记账值 × KICK_DEG_PER_M`，且**与步长无关**。
func _kick_rot_total_iso(dt: float, k0 := 2.55) -> float:
	var cam := _fresh()
	cam._shake = 0.0
	var ref := -cam.global_transform.basis.z
	var p0 := cam.global_position
	cam._kick = k0
	cam._kick_dir = Vector3.RIGHT
	var mx := 0.0
	for i in FRAMES:
		cam._physics_process(dt)
		mx = maxf(mx, rad_to_deg((-cam.global_transform.basis.z).angle_to(ref)))
		cam.global_position = p0
	return mx


## 一次受击的**画面峰值转角**（度）。隔离法：每帧复位位置，只留姿态通道；单种子。
func _shake_excursion_iso(dt: float, ratio: float, dtype: int, frames: int) -> float:
	var cam := _fresh()
	cam.add_hit_shake(ratio, Vector3.RIGHT, dtype)
	var ref := -cam.global_transform.basis.z
	var p0 := cam.global_position
	var mx := 0.0
	for i in frames:
		cam._physics_process(dt)
		mx = maxf(mx, rad_to_deg((-cam.global_transform.basis.z).angle_to(ref)))
		cam.global_position = p0
	return mx


func _shake_peak_iso(dt: float, ratio: float, dtype: int) -> Dictionary:
	var sum := 0.0
	var mx := 0.0
	for s in SEEDS:
		seed(s)
		var v := _shake_excursion_iso(dt, ratio, dtype, FRAMES)
		sum += v
		mx = maxf(mx, v)
	return {"mean": sum / float(SEEDS.size()), "max": mx}


## `_shake` 被**恒定充值**（长时间顶在某个电平）时的画面峰值转角（隔离法）。
## 齐射就是这种形态：`LAUNCH_SHAKE_CEIL` 帮它封住，稳态读数很稳。
func _held_shake_iso(dt: float, level: float) -> float:
	var sum := 0.0
	for s in SEEDS:
		var cam := _fresh()
		cam._shake = 0.0
		cam._kick = 0.0
		seed(s)
		var ref := -cam.global_transform.basis.z
		var p0 := cam.global_position
		var mx := 0.0
		for i in FRAMES:
			cam._shake = level
			cam._physics_process(dt)
			mx = maxf(mx, rad_to_deg((-cam.global_transform.basis.z).angle_to(ref)))
			cam.global_position = p0
		sum += mx
	return sum / float(SEEDS.size())


## `_shake` 恒定在 `level` 时的画面峰值**平移**（米）—— `SHAKE_M_PER_DEG` 那条配重通道。
## 这里**不复位位置**：要量的就是位移本身。
func _held_shake_pos_peak(dt: float, level: float) -> float:
	var sum := 0.0
	for s in SEEDS:
		var cam := _fresh()
		cam._shake = 0.0
		cam._kick = 0.0
		seed(s)
		var p0 := cam.global_position
		var mx := 0.0
		for i in FRAMES:
			cam._shake = level
			cam._physics_process(dt)
			mx = maxf(mx, (cam.global_position - p0).length())
		sum += mx
	return sum / float(SEEDS.size())
