extends Node
## 浮游飞弹「弹道长度 vs 尾迹长度」探针（轮 40）。
##
## ## 需求原话
## 「把浮游飞弹的飞行轨迹加长，现在的浮游飞弹的拖尾太短了，拖尾要和飞行轨迹一样长」。
##
## ## 本探针回答两个数
##   ① **弹道有多长**（发射 → 命中，逐帧差分 `global_position` 累加）；
##   ② **尾迹每时每刻盖得住它吗**（`v(t) × lifetime ≥ s(t)`，逐帧核）。
##
## ② 是那条需求**唯一可判定的形式** —— "一样长"不是形容词，是这条不等式。
## 尾迹的 `lifetime` / `amount` 一律**从真弹的拖尾节点上读**，不在这里写死
## （写死的话改了 `fx.gd` 探针也不会知道，正是"改了常量但没接上"那类事故）。
##
## ## 为什么距离要当参数
## 「拖尾够不够长」**强依赖交战距离**，而这个工程里从 2 km（贴身缠斗）到
## 20.7 km（`lock_break_range()`，锁定上限）都有可能。所以距离必须能传进来：
##
##     ... --headless --path . res://tools/probe_missile_ballistic.tscn -- 12000
##
## 不传时用 2 km（`DEFAULT_RANGE`）。
## 工程自己的"典型交战距离"基准是**靶机 11960 m / 锁定 20700 m**（见
## `world_builder.gd` 那句 `11960/20700 ≈ 0.578`）。
##
## ## 为什么不能从代码里读弹道
##   · `Missile.lifetime = 14 s` 是**自毁**上限，不是实际飞行时间；
##   · `funnel()` 里的 `speed = 90` 是自航**初速**，不是世界速度（还要叠
##     `accel_time` 爬升与轮 13 的载机速度继承）；
##   · 真正的飞行距离取决于**什么时候命中** —— 只有跑一次才知道。
##
## ## 跑法（**可以** `--headless`：只打印数字，不碰渲染）
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       res://tools/probe_missile_ballistic.tscn -- 12000

const ALT := 3000.0
## 不传距离时的默认值。2 km = "能看见敌机、值得按扳机"的贴身距离。
const DEFAULT_RANGE := 2000.0
## 兜底：目标 20 km 时弹要飞 ~5 s（300 帧），留足 20 s。
const MAX_FRAMES := 1200

var range_m := DEFAULT_RANGE


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		range_m = maxf(float(args[0]), 200.0)
	_run()


func _run() -> void:
	var c := Node3D.new()
	c.name = "BallisticBox"
	add_child(c)
	# 载机：高速（佩涅罗佩**巡航**上限量级）—— 轮 13 的速度继承会让弹出膛就带着
	# 这个初速，是"现实中玩家看到的弹道"的常态。
	var me := _unit(c, 0, Vector3(0, ALT, 0), true)
	me.fm.speed = 1560.0
	var foe := _unit(c, 1, Vector3(0, ALT, -range_m))
	await _frames(6)
	print("[mb] 目标距离 %.0f m，载机速率 %.1f m/s" % [range_m, me.fm.velocity.length()])

	var dir := (Vector3.RIGHT * 0.30 + Vector3.UP * 0.45 - Vector3.FORWARD * 0.15).normalized()
	var m := Missile.funnel(c, me.global_position, dir, foe, me, 26.0)
	var trail := _trail_of(m)
	if trail == null:
		print("[mb] !! 没找到拖尾粒子节点（`FX.missile_trail` 没被调到？）")
		get_tree().quit(2)
		return
	var ribbon := _ribbon_of(m)
	if ribbon == null:
		print("[mb] !! 没找到烟带（HIGH 档应当有 —— 见 `Missile._ready()` 那段）")
	else:
		var rp := ribbon.get_parent()
		print("[mb] 烟带挂点 = %s（应为**弹丸容器**，不是弹自己），采样间距 %.0f m"
			% ["<无父节点>" if rp == null else rp.name, MissileRibbon.SPACING])
	var life := trail.lifetime
	var amt := trail.amount
	print("[mb] 拖尾实配 lifetime=%.2f s  amount=%d  fixed_fps=%d  ⇒ 柱长上限 %.0f m"
		% [life, amt, trail.fixed_fps, life * Missile.new().max_speed])

	var prev: Vector3 = m.global_position
	var total := 0.0
	var f := 0
	var v_last := 0.0
	var worst := 1e12
	var worst_f := -1
	while is_instance_valid(m) and f < MAX_FRAMES:
		await get_tree().physics_frame
		f += 1
		if not is_instance_valid(m):
			break
		var p: Vector3 = m.global_position
		var d := prev.distance_to(p)
		total += d
		v_last = d * 60.0
		prev = p
		# 判据：这一帧的柱长盖得住已经飞过的距离吗
		var slack := v_last * life - total
		if slack < worst:
			worst = slack
			worst_f = f
		if f % 30 == 0:
			print("[mb] f=%-4d 累计 %8.1f m  本帧速度 %7.1f m/s  富余 %+9.1f m"
				% [f, total, v_last, slack])

	var hit := not is_instance_valid(m)
	print("[mb] ==== 结果 ====")
	print("[mb] 飞行 %d 帧（%.2f s）  弹道 %8.1f m  末速度 %7.1f m/s"
		% [f, float(f) / 60.0, total, v_last])
	print("[mb] 弹体已消失（命中/自毁）：%s   末段柱长 %.1f m"
		% [str(hit), v_last * life])
	print("[mb] ★ 全程最小富余（柱长 − 已飞距离）= %+.1f m（第 %d 帧）"
		% [worst, worst_f])
	if ribbon != null and is_instance_valid(ribbon):
		var cover := ribbon.covered_m()
		print("[mb] 烟带 released=%s  采样点 %d  实铺长度 %8.1f m"
			% [str(ribbon.is_released()), ribbon.point_count(), cover])
		var trunc := ""
		if ribbon.point_count() >= MissileRibbon.MAX_POINTS:
			trunc = "（点数已顶到上限 %d —— 真飞满 14 s 会更长）" % MissileRibbon.MAX_POINTS
		print("[mb] ★★ 烟带覆盖 / 弹道 = %.1f%%  %s"
			% [100.0 * cover / maxf(total, 1.0), trunc])
	print("[mb]    %s" % ("盖得住 ✓" if worst >= 0.0 else "**盖不住** ✗（差 %.0f m）" % -worst))
	print("[mb] ---- 同一条弹道下，其它 lifetime 会怎样（纯算术对照）----")
	for l: float in [0.16, 0.95, 2.80]:
		print("[mb]   lifetime=%.2f s ⇒ 峰值柱长 %7.0f m  %s"
			% [l, l * Missile.new().max_speed,
				"盖得住" if l * Missile.new().max_speed >= total else "差 %.0f m" % (total - l * Missile.new().max_speed)])
	get_tree().quit(0)


func _trail_of(s: Missile) -> GPUParticles3D:
	return s.get_node_or_null("MissileTrail") as GPUParticles3D


## 烟带挂在**弹的父容器**上（不是弹的子节点）⇒ 只能从容器里按类型找。
## 用**类型**找而不是按名字：名字是 `MissileRibbon._init()` 里设的，改了名这里不该失配。
func _ribbon_of(s: Missile) -> MissileRibbon:
	var holder := s.get_parent()
	if holder == null:
		return null
	for ch in holder.get_children():
		if ch is MissileRibbon:
			return ch as MissileRibbon
	return null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _unit(container: Node3D, team: int, pos: Vector3, as_player := false) -> FlightBody:
	var u := FlightBody.new()
	u.team = team
	u.is_player = as_player
	u.profile = SuitProfile.penelope() if team == 0 else SuitProfile.xi()
	u.display_name = "T%d" % team
	u.projectile_container = container
	container.add_child(u)
	u.global_position = pos
	u.max_hp = 400.0
	u.hp = 400.0
	u.ifield_max = 0.0
	u.ifield_hp = 0.0
	u.fm.speed = 260.0
	u.fm.throttle = 0.78
	u.fm.align_velocity(u.forward())
	return u
