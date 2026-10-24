extends Node
## 浮游导弹尾迹「粒子间距」读数探针（轮 39）。
##
## ## 用户原话
## 「浮游导弹飞行过程中的烟雾能不能浓密一点，是不是烟雾是按时间生成的
##   现在浮游导弹飞行速度加快了导致烟雾的飞行轨迹变得那么稀疏。」
##
## ⚠️ 这句话里藏着**两个可判定的判断**，本探针就是来给它们定值的：
##
##   ① 「烟雾是按时间生成的」 —— **对**。`GPUParticles3D` 的发射率就是
##      `amount / lifetime`，单位是**粒/秒**，与速度无关。
##   ② 「速度加快导致稀疏」 —— 这正是要**量**的那一项。因为
##
##          间距 = 世界速度 ÷ 发射率 = 世界速度 × lifetime ÷ amount
##
##      发射率不变而世界速度涨了 ⇒ 间距**同比**涨。
##
## ## 为什么不能只看代码里的 `speed = 90`
##
## `Missile.funnel()` 确实写着 `speed = 90.0`，但那**不是**弹体在世界的速度：
##
##   · `max_speed = SuitProfile.missile_speed() = 佩涅罗佩巡航 × 2.6`
##     = `420 × 1.55 × 2.4 × 2.6` ≈ **4062 m/s**（`accel_time = 1.7 s` 爬上去）；
##   · 更要命的是轮 13 的**载机速度继承**（`INHERIT_MUL`）：离架瞬间
##     `launch_vel = 载机速度`（佩涅罗佩巡航 1562 / 加力 2343 m/s），
##     用 `INHERIT_DECAY_TIME = 1.6 s` **线性**衰减到 0。
##
## 所以真实世界速度 = **自航速度 + 继承速度**，前 1.6 s 可达 2 km/s 量级。
## 本探针逐帧读 `global_position` 的**差分**，量的是"弹体实际飞了多远" ——
## 这是唯一不依赖"我读对了哪个字段"的口径。
##
## ## 为什么不用真的造一架载机
##
## 第一版照抄了 suite 的 `_new_unit()`（真 `FlightBody` + `Game.reset()`），
## 在没有主场景的探针里**跑不完**（4 分钟不退出）。这一版把两样都去掉：
## `launch_vel` 只是 `_physics_process()` 每帧读的一个字段，**直接赋值物理上等效**，
## 而 `target = null` 已经让制导走"直飞"分支（`_ready()` 只按 `max_speed` 反算
## `accel`，不读 `launch_vel`）⇒ 不必真发射一次。
##
## ## 跑法（**可以** `--headless`：本探针只打印数字，不碰渲染）
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       res://tools/probe_trail_density.tscn

const ALT := 3000.0
## 载机速度：佩涅罗佩**巡航**上限（`SuitProfile.penelope().player_top_speed()`）。
## 玩家常态发射就在这个量级；`PLAYER_BOOST_MULT = 1.5` 的加力是它的 1.5 倍。
const CARRIER := 1562.0
const FRAMES := 190          # ≈3.17 s @60Hz，覆盖 deploy(0.55) + 继承衰减(1.6) + 巡航

var _trail: GPUParticles3D = null


func _ready() -> void:
	_run()


func _run() -> void:
	var c := Node3D.new()
	c.name = "DensityProbeBox"
	add_child(c)

	print("=".repeat(78))
	print("[密度] 物理帧率 = %d Hz" % Engine.physics_ticks_per_second)
	print("[密度] SuitProfile.missile_speed() = %.1f m/s（= 佩涅罗佩巡航 %.1f × %.1f）"
		% [SuitProfile.missile_speed(),
			SuitProfile.missile_speed() / SuitProfile.MISSILE_SPEED_MULT,
			SuitProfile.MISSILE_SPEED_MULT])
	print("=".repeat(78))
	print("")

	var p0 := Vector3(0, ALT, 0)
	var m := Missile.funnel(c, p0, Vector3.RIGHT, null, null, 26.0)
	# 手动给继承速度（等价于从一架巡航中的佩涅罗佩上打出去）。
	m.launch_vel = Vector3.RIGHT * CARRIER

	_trail = m.get_node_or_null("MissileTrail") as GPUParticles3D
	if _trail == null:
		push_error("[密度] 尾迹发射器没找到 —— `Missile._ready()` 里没挂上？")
		get_tree().quit(3)
		return

	var rate := float(_trail.amount) / _trail.lifetime
	print("[密度] 尾迹：amount=%d  lifetime=%.3f s  local_coords=%s"
		% [_trail.amount, _trail.lifetime, str(_trail.local_coords)])
	print("[密度] ⇒ **发射率 = amount / lifetime = %.1f 粒/秒**（与速度无关 —— 这就是「按时间生成」）"
		% rate)
	print("[密度] ⇒ 间距 = 世界速度 / 发射率 = 世界速度 × %.4f / %d"
		% [_trail.lifetime, _trail.amount])
	print("")

	var pm := _trail.process_material as ParticleProcessMaterial
	# 出生粒径：`scale_min × 球直径(1.8)`。用来和间距比 —— "连不连得上"就看这个比值。
	var diam_min := 1.8 * 0.65 * 3.2
	var diam_max := 1.8 * 0.65 * 8.5
	print("[密度] 球直径：出生 %.1f ~ %.1f m（`scale 0.65` × `scale_min/max` × 球高 1.8）"
		% [diam_min, diam_max])
	if pm != null:
		print("[密度] spread=%.1f°  初速 %.1f~%.1f m/s"
			% [pm.spread, pm.initial_velocity_min, pm.initial_velocity_max])
	print("")
	print("%7s %10s %10s %10s %10s %10s %8s"
		% ["t(s)", "自航", "继承", "世界速度", "间距(m)", "柱长(m)", "间距/粒径"])

	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var prev := m.global_position
	var t := 0.0
	var wmax := 0.0
	var wsum := 0.0
	var n := 0
	var t0 := Time.get_ticks_msec()
	for i in FRAMES:
		await get_tree().physics_frame
		if Time.get_ticks_msec() - t0 > 40000:
			print("  ⚠️ 墙钟超 40 s，提前退出（物理帧没按预期推进）")
			break
		if not is_instance_valid(m):
			print("  ⚠️ 第 %d 帧弹体已消失（自毁）" % i)
			break
		t += dt
		var cur := m.global_position
		var wv := (cur - prev).length() / dt
		prev = cur
		var spacing := wv * _trail.lifetime / float(_trail.amount)
		wmax = maxf(wmax, wv)
		wsum += wv
		n += 1
		if i < 4 or i % 10 == 0:
			print("%7.2f %10.1f %10.1f %10.1f %10.1f %10.1f %8.2f"
				% [t, m.speed, m.launch_vel.length() * Missile.inherit_factor(m._age),
					wv, spacing, wv * _trail.lifetime, spacing / diam_min])

	print("")
	print("=".repeat(78))
	var wavg := wsum / maxf(float(n), 1.0)
	print("[密度] 世界速度：平均 %.0f m/s，峰值 %.0f m/s（%d 帧）" % [wavg, wmax, n])
	print("[密度] ⇒ 平均间距 **%.1f m**，峰值间距 **%.1f m**"
		% [wavg * _trail.lifetime / float(_trail.amount),
			wmax * _trail.lifetime / float(_trail.amount)])
	print("[密度] ⇒ 平均柱长 %.0f m（= 世界速度 × lifetime）" % (wavg * _trail.lifetime))
	var sp_avg := wavg * _trail.lifetime / float(_trail.amount)
	print("[密度] ⇒ **间距 / 最小粒径 = %.1f 倍**（> 1 就能看到缝，越大越稀）"
		% (sp_avg / diam_min))
	print("[密度] 参考：要让间距 ≤ 最小粒径(%.1f m)，在 %.0f m/s 下 lifetime 需 ≤ %.4f s"
		% [diam_min, wavg, diam_min * float(_trail.amount) / maxf(wavg, 1e-6)])
	var want := 8.0
	print("[密度] 参考：若目标间距 %.0f m，同一速度下 lifetime 应为 %.4f s"
		% [want, want * float(_trail.amount) / maxf(wavg, 1e-6)])
	print("=".repeat(78))
	get_tree().quit(0)
