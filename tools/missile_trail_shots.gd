extends Node
## 浮游飞弹「拖尾 vs 弹道」**判据图台**（轮 40，第二版）。
##
## ## 需求原话
## 「把浮游飞弹的飞行轨迹加长，现在的浮游飞弹的拖尾太短了，拖尾要和飞行轨迹一样长」。
##
## ## ⚠️ 为什么**不**用侧视机位（第一版就是那样，拍出来全是地图背景）
## 侧视听起来对（"烟"和"它飞过的那条线"在图上可以直接比长短），但**算一下就知道不行**：
## 弹道长 11.6 km ⇒ 相机至少要退到 18 km 外才装得下（fov 60 的视野宽 = 距离 × 1.155），
## 而那一刻**烟带只有 12 m 宽**（`MissileRibbon.HALF_W 6.0 × 2`）——
## `12 / 20784 × 1600 px = 0.9 px`，**不到一个像素**。第一版实测：图上只有地图背景与云。
##
## 正解是**游戏视角**（就是追尾相机的原机位，不抢 `current`）—— 那正是用户看到
## "拖尾太短"的那个现场：
##   · 烟带近端（离相机 ~30 m）投影宽 `12 / (2×30×tan30°) × 1600 ≈ 555 px`；
##   · 远端（11.6 km）收敛到 `≈ 1.4 px`。
## 于是屏幕上是一条**从画面近处很宽、向深处收敛**的带子 —— 它铺到多远，一眼就看得出。
## 对照行（把烟带删掉）只有 650 m 的粒子柱 ⇒ 到 650 m 处就断了。**差异是量级上的。**
##
## 另加一张**近机位侧视**（距弹道 2.5 km）用来证明"是一条**连续**的带子，不是断续的团"——
## 那个距离上 12 m ⇒ 6.3 px，可见；再远就没了。
##
## ## 两行的控制变量 = **烟带的有无**（不是两个参数）
##   · `after` ：轮 40 真配置 —— 粒子球（近端厚度）**＋** `MissileRibbon` 连续烟带（长度）；
##   · `before`：把那条烟带 `queue_free()` 掉 —— 只剩粒子球，即轮 39 的观感。
## ⚠️ 不是"回退源码"复现：那样两份代码会一起变，就不能归因了。弹体本身走的是**真**
## `PlayerController.fire_funnel()`。
##
## ## 交战距离用**工程自己的基准**
## 11960 m（`world_builder.gd` 的靶机距离），不用编队战开局的 90 km —— 那个距离上
## 弹道一百多公里，任何机位都装不下，也根本不是玩家会按扳机的距离。
## 办法是把敌机直接摆到机头前方：与 `tools/probe_missile_ballistic.gd` 同款做法。
##
## ## 截断帧数两行一致
## 敌机 AI 会跑，弹道长度不可控（第一版 `before` 行飞了 420 帧没命中）
## ⇒ 两行都跑到 `MAX_FRAMES` 或命中为止，**同一时刻收工**，表格才可比。
##
## ## 跑法（**不能加 --headless**：dummy 渲染器抓出来是全黑）
##   Godot_v4.7.1-stable_win64_console.exe --path . \
##       res://tools/missile_trail_shots.tscn -- <输出目录>

const SHOT_W := 1600
const SHOT_H := 1000
## 游戏视角的拍图时刻（物理帧）。
const SHOT_AT := [70, 150]
## 侧视近机位那一张（只在真配置行拍；拍完这局就结束，不必把机位还给追随相机）。
const SIDE_AT := 170
## 弹最多追多少帧（两行同一时刻收工）。
const MAX_FRAMES := 250
## 交战距离（工程基准：`world_builder.gd` 靶机 11960 m）。
const RANGE := 12000.0
## 近机位侧视：相机离弹道的距离。⚠️ 再远这条 12 m 宽的带子就不足一个像素了。
const SIDE_DIST := 2500.0

var out_dir := "user://r40_trail"
var _tips: Array = []
var _ok_all := true
var _rows: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await _frames(30)

	# ---- 行 1：真配置（有烟带）----
	await _case("after", true)
	Game.reset()
	await _frames(6)
	# ---- 行 2：对照（把烟带删掉，只剩粒子球）----
	await _case("before", false)

	_write_sheet()
	print("\n--- 自动判据 ---")
	for rec: Array in _tips:
		_judge(str(rec[0]), bool(rec[1]))
	print("\nALL_OK=%s" % str(_ok_all))
	print("MISSILE_TRAIL_SHOTS_DONE -> ", out_dir)
	get_tree().quit(0 if _ok_all else 1)


## 一局：开战 → 把敌机摆到工程基准距离 → 玩家打一梭浮游飞弹 →
## 拍游戏视角两张 + 侧视近机位一张 → 逐帧记「弹道 / 粒子柱 / 烟带实铺」。
func _case(tag: String, with_ribbon: bool) -> void:
	var m := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(m)
	await _frames(40)
	m.call("_on_start_match", SuitProfile.Id.PENELOPE, 0)
	var me: PlayerController = null
	for i in 120:
		await _frames(1)
		me = m.get("player") as PlayerController
		if me != null and me.controls_enabled:
			break
	if me == null:
		print("SHOTS_FAILED(%s: no player)" % tag)
		return
	var foe := _find_foe(me)
	if foe == null:
		print("SHOTS_FAILED(%s: no foe)" % tag)
		return

	# ---- 把交战距离摆到工程基准（编队战开局是 90 km，那个距离上什么都看不出来）----
	var fwd := -me.global_transform.basis.z
	foe.global_position = me.global_position + fwd * RANGE + Vector3.UP * 350.0
	foe.fm.align_velocity(fwd)
	await _frames(4)
	print("\n=== %s：%s  vs  %s（摆到机头正前 %.0f m）===" % [
		tag, me.profile.display_name, foe.profile.display_name, RANGE])

	me.funnel_count = 60
	me.funnel_cooldown = 0.0
	var before := _shots_of(me).size()
	me.fire_funnel(foe)
	var ms := _shots_of(me)
	if ms.size() - before < 1:
		print("SHOTS_FAILED(%s: 没打出去)" % tag)
		return
	var shots: Array = ms.slice(before)

	# ---- 复现"轮 39 只剩粒子"：删掉烟带（控制变量 = 烟带的有无）----
	# ⚠️ 一梭 3 发**同帧**各建一条烟带、都挂**同一个弹丸容器** ⇒ 必须删**全部**。
	# 第二版只删了一条（`_ribbon_of` 返回的第一条），`before` 行画面上仍留着两条烟带，
	# 而读数却报 0.0 —— **读数与画面分家**（图和判据都还在骗人）。
	var ribbons := _all_ribbons(shots[0] as Missile)
	if not with_ribbon:
		for r: MissileRibbon in ribbons:
			r.queue_free()
		ribbons.clear()

	var lead: Missile = shots[0]
	# ⚠️ 弹命中后会自己 `queue_free()` ⇒ 收尾**不能**再拿 `lead` 去找烟带。
	# 烟带挂在**弹丸容器**上、容器比弹活得久 ⇒ 缓存的 `holder` 才是收尾的唯一凭据。
	var holder: Node = lead.get_parent()
	var trail := _trail_of(lead)
	var p0: Vector3 = lead.global_position
	var real_life := trail.lifetime if trail != null else 0.0
	var say := "无（对照行）"
	if ribbons.size() > 0:
		say = "**有**（%d 条）" % ribbons.size()
	print("  打出去 %d 发（`MISSILE_PER_SHOT`=%d）  烟带：%s"
		% [shots.size(), SuitProfile.MISSILE_PER_SHOT, say])
	print("  粒子尾迹：lifetime=%.2f s  amount=%d ⇒ 柱长上限 %.0f m" % [
		real_life, trail.amount if trail != null else -1, 4062.0 * real_life])

	var prev: Vector3 = lead.global_position
	var s := 0.0
	var worst := 1e12
	var worst_f := -1
	var v_last := 0.0
	var f := 0
	var cover := 0.0
	var leak := 0
	var side_done := false
	while f < MAX_FRAMES:
		await get_tree().physics_frame
		f += 1
		if not is_instance_valid(lead):
			break
		var p: Vector3 = lead.global_position
		var d := prev.distance_to(p)
		s += d
		v_last = d * 60.0
		prev = p
		if v_last * real_life - s < worst:
			worst = v_last * real_life - s
			worst_f = f
		# ⚠️ 每帧**从容器实时数**（不依赖任何缓存的变量）：漏删一条，读数会立刻跟着涨，
		# 于是"读数和画面分家"这件事**不可能悄悄发生**。
		var live := _all_ribbons(lead)
		if not with_ribbon and live.size() > 0:
			leak = maxi(leak, live.size())
		cover = 0.0
		for r: MissileRibbon in live:
			if is_instance_valid(r):
				cover = maxf(cover, r.covered_m())
		# 游戏视角（**不抢 `current`** —— 这就是玩家实际看到的画面）
		if f in SHOT_AT:
			await _shoot("%s_f%03d.png" % [tag, f])
		# 侧视近机位（**两行都拍**：同一机位、同一帧 ⇒ 直接对比"有带 / 无带"）
		if not side_done and f >= SIDE_AT:
			side_done = true
			var cam := _side_camera(p0, fwd)
			await _frames(2)
			cam.current = true
			await _frames(2)
			await _shoot("%s_side_f%03d.png" % [tag, f])
			cam.queue_free()

	print("  飞行 %d 帧（%.2f s）  弹道 %.1f m  末速 %.1f m/s"
		% [f, float(f) / 60.0, s, v_last])
	print("  粒子柱末段 %.1f m（按峰值标定 %.1f m）  最小富余 %+.1f m（第 %d 帧）"
		% [v_last * real_life, 4062.0 * real_life, worst, worst_f])
	var tail := ""
	if leak > 0:
		tail = "   ⚠️ 漏删 %d 条！" % leak
	print("  烟带实铺 %.1f m  ⇒  覆盖弹道 %.1f%%%s"
		% [cover, 100.0 * cover / maxf(s, 1.0), tail])
	_rows.append([tag, "有" if with_ribbon else "无", f, s, v_last,
		v_last * real_life, cover, 100.0 * cover / maxf(s, 1.0), worst])

	# ---- 判据 ----
	if with_ribbon:
		var pct := 100.0 * cover / maxf(s, 1.0)
		_tips.append(["真配置带着烟带，而且它**铺满了整条弹道**（%.1f m / %.1f m = %.1f%% ≥ 95%%）"
			% [cover, s, pct], pct >= 95.0])
		_tips.append(["粒子柱（%.0f m）明显**短于**弹道（%.0f m）—— 长度本来就不归粒子管"
			% [4062.0 * real_life, s], 4062.0 * real_life < s])
	else:
		_tips.append(["对照行的烟带**一条不剩**（漏删会让读数和画面分家）", leak == 0])
		_tips.append(["……所以实铺 0 m（**烟带才是长度的那条腿**）", cover <= 0.001])
	_tips.append(["真配置行确实有烟带、对照行确实没有（一梭 %d 发）" % shots.size(),
		(ribbons.size() > 0) == with_ribbon])

	for r: MissileRibbon in _ribbons_in(holder):
		if is_instance_valid(r):
			r.queue_free()
	m.queue_free()
	await _frames(6)


# ============================================================ 工具

## ⚠️ 按 `shooter` 过滤，**不能**用 `get_nodes_in_group()` 的下标切片 ——
## "组里最后 N 个"不保证就是刚发射的那几发（组内顺序不是插入顺序）。
func _shots_of(shooter: FlightBody) -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("missiles"):
		var s := n as Missile
		if s != null and s.shooter == shooter:
			out.append(s)
	return out


func _trail_of(s: Missile) -> GPUParticles3D:
	return s.get_node_or_null("MissileTrail") as GPUParticles3D


## 容器里**所有**烟带。
##
## ⚠️ 一梭 3 发**同帧**各建一条、**都挂同一个弹丸容器** ⇒ 只取"第一条"会漏掉另外两条
## （第二版就栽在这里：`before` 行画面上还留着两条烟带，读数却报 0.0）。
## ⚠️ 按**类型**找，不按名字：同帧三条重名，Godot 会把第 2、3 条改成自动名
## `@MeshInstance3D@NNNN`。
func _all_ribbons(m: Missile) -> Array:
	return _ribbons_in(m.get_parent() if is_instance_valid(m) else null)


## ⚠️ 按**容器**找烟带，不按弹 —— 弹是短命的（命中即 `queue_free()`），容器才是长命的那个。
func _ribbons_in(holder: Node) -> Array:
	var out: Array = []
	if holder == null or not is_instance_valid(holder):
		return out
	for ch in holder.get_children():
		if ch is MissileRibbon:
			out.append(ch)
	return out


## 离玩家最近的敌机（编队战里有多台，取最近的那台 —— 那是玩家会瞄的）。
func _find_foe(me: FlightBody) -> FlightBody:
	var best: FlightBody = null
	var bd := 1e12
	for n in get_tree().get_nodes_in_group("units"):
		var u := n as FlightBody
		if u == null or u == me or u.team == me.team:
			continue
		var d: float = u.global_position.distance_to(me.global_position)
		if d < bd:
			bd = d
			best = u
	return best


## **近机位**侧视：垂直弹道、偏上，看**发射点附近那一段**。
## ⚠️ 别把它拉远去"装下整条弹道"：12 m 宽的带子在 18 km 外不足 1 px，
## 拍出来只有地图背景（第一版实测）。
## ⚠️ `look_at` 要求节点**已在树里**（这里先 `add_child`）。
func _side_camera(p0: Vector3, fwd: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 200000.0
	add_child(cam)
	var side := fwd.cross(Vector3.UP)
	if side.length_squared() < 1e-4:
		side = fwd.cross(Vector3.RIGHT)
	side = side.normalized()
	var center := p0 + fwd.normalized() * (SIDE_DIST * 0.5)
	cam.global_position = center + side * SIDE_DIST + Vector3.UP * (SIDE_DIST * 0.35)
	cam.look_at(center, Vector3.UP)
	return cam


func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name))
	print("  SHOT %s" % name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _judge(label: String, cond: bool) -> void:
	print("  %s  %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_ok_all = false


func _write_sheet() -> void:
	var lines := PackedStringArray([
		"标签  烟带  飞行帧  弹道(m)  末速(m/s)  粒子柱(m)  烟带实铺(m)  覆盖率(%)  最小富余(m)"])
	for r: Array in _rows:
		lines.append("%s  %s  %4d  %8.1f  %8.1f  %8.1f  %10.1f  %8.1f  %+10.1f"
			% [r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8]])
	var txt := "\n".join(lines) + "\n"
	var fa := FileAccess.open(out_dir.path_join("readings.txt"), FileAccess.WRITE)
	if fa != null:
		fa.store_string(txt)
		fa.close()
	print("\n" + txt)
