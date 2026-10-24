extends Node
## 阿利宙斯「匀速弹速 + 蓄力激光炮」真机取证（2026-09-28，轮 31 收尾）。
##
## ⚠️ **不能加 `--headless`** —— 无头用的是 dummy 渲染器，一个像素都不产生，
## 抓出来是全黑。这个脚本的全部意义就是"能真的看到"。
##
## 跑法：
##   godot --path <工程> res://tools/cannon_shot.tscn -- <输出目录>
##
## ## 四件事，每件都要"数字"和"画面"两条证据
##   A **匀速弹速**：先纯测量（不截图）⇒ 每帧位移恒为 10900/60 = 181.6667 m；
##     再降 `Engine.time_scale` 连拍 ⇒ 光束停在近处、四张能并排看
##   B **真输入端到端**：`Input.action_press("fire_primary")` 按住 1.8 s
##     ⇒ `cannon_charging()` 为真 ⇒ 松手放炮。**这一段是唯一能证明"输入真的接线了"
##     的证据** —— 套件里扫的是源码结构。
##   C **蓄力环两态**：按住 0.9 s（未满的在长的弧）/ 蓄满（脉动整环），各出整屏 + 局部放大
##   D **激光柱**：柱长读数（10 km）+ 炮口飞溅 + 4 s 持续伤害
##
## ## ⚠️ 三个坑都写在出事的那一行旁边
##   1. 机体不能摆在 y=0（`FlightBody.CRASH_ALTITUDE` 判撞海 → 抓到满屏爆炸花瓣）；
##   2. `aim_cursor` 是**内容坐标**，不是窗口/落盘尺寸；
##   3. **`_shot()` 很慢**（存一次 PNG ≈ 100 ms ≈ 6 个物理帧）——
##      "量每帧位移"那一遍**一帧截图都不能插**，否则量到的是 8 帧的和（实测
##      181.667 → 1453.333 = 181.667×8，判据会凭空假绿/假红）。
##
## ## 与 `capture_fpv.gd` 的一个区别
## 本脚本**不改任何 Settings**（没有要改的档位），所以没有"结尾还原"那一段。
## 唯一的全局改动是 `Engine.time_scale`，用完立刻还回 1.0。

const SHOT_W := 1600
const SHOT_H := 900
## 连拍时把时间放慢到这个倍率：否则每次截图之间光束已经飞出几公里，
## 四张图各拍一个孤零零的远点，"在动"这件事反而看不出来。
const SLOW_MO := 0.15

var main: Node
var out_dir := "user://captures_cannon"
var _idx := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))

	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await _frames(10)

	var menu = main.get("menu")
	if menu != null and is_instance_valid(menu):
		menu.close_menu()
	await _frames(10)
	main.call("_on_start_match", SuitProfile.Id.ARIZEUS, Difficulty.Level.NORMAL,
		MapDef.Id.ULURU, Game.MatchMode.VERSUS)
	await _frames(30)
	main.call("_start_fight")
	await _frames(20)

	var p := _p()
	if p == null:
		push_error("CANNON_SHOT_FAILED(no player)")
		get_tree().quit(1)
		return
	_setup_match(p)
	await _settle_camera()

	await _phase_beam(p)
	await _phase_real_input(p)
	await _phase_cannon(p)

	Engine.time_scale = 1.0
	print("CANNON_SHOT_DONE idx=%d out=%s" % [_idx, out_dir])
	get_tree().quit(0)


## 玩家与敌机的初始状态。
func _setup_match(p: Node) -> void:
	# 常态形态（用户拍板：大炮只给常态 + 巡航；核心·量产型ν高达不给）
	p.profile = SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL)
	p.max_hp = 99999.0
	p.hp = 99999.0
	p.ifield_max = 9999.0
	p.ifield_hp = 9999.0
	p.rifle_mag = p.profile.rifle_magazine
	p.cannon_cd_left = 0.0

	# ⚠️ 机体不能摆在 y=0：`FlightBody.CRASH_ALTITUDE := 24.0` 会在第一个物理帧
	# 就判"撞海"并 `destroy()` —— 模型被拆走、原地炸开一团爆炸特效，
	# 抓到的是满屏花瓣（`plume_nozzle_shot.gd` 第一版栽过，注释留在那里）。
	p.global_position = Vector3(3000.0, 900.0, 1500.0)
	p.fm.velocity = Vector3.ZERO
	p.fm.align_velocity(p.forward())

	p.debug_input_enabled = true
	p.debug_input = Vector3.ZERO
	p.debug_throttle = 0.0
	p.debug_boost = false
	p.debug_hover = false
	# ⚠️ 两个都要 true 才会走"用 aim_cursor 算方向"那条路
	#（`_read_aim_input()` 第一句 `if not mouse_lock_enabled or not cursor_seen: 归零`）。
	p.mouse_lock_enabled = true
	p.cursor_seen = true

	var e := _e()
	if e != null:
		e.max_hp = 99999.0
		e.hp = 99999.0
		# I 立场清零：量伤害时不要被护盾吃掉（读数会变成"护盾还剩多少"）
		e.ifield_max = 0.0
		e.ifield_hp = 0.0
		e.flare_count = 0
		# 冻在原地当靶子，免得它飞走把画面与判据都搅乱
		e.set_physics_process(false)
		e.fm.velocity = Vector3.ZERO
	print("CANNON_SHOT profile=%s mag=%d 敌机=%s"
		% [p.profile.display_name, p.rifle_mag, str(e != null)])


# ============================================================ A 匀速弹速

func _phase_beam(p: Node) -> void:
	print("---- A1 匀速弹速：纯测量（一帧截图都不插）----")
	var e := _e()
	if e != null:
		# 靶机挪到**侧上方 1200 m**：A 要拍的是"弹丸在飞"，不是"打到谁"。
		# 摆在正前方的话弹丸几帧就撞上它、连拍还没跑完就没了。
		e.global_position = p.global_position + p.forward() * 1200.0 \
			+ p.global_transform.basis.x * 900.0 + Vector3(0.0, 500.0, 0.0)

	_aim_at(p, p.global_position + p.forward() * 6000.0)
	await _pin(p, 4)

	p.rifle_cooldown = 0.0
	p.rifle_mag = p.profile.rifle_magazine
	var before := _kids(p)
	if not p.fire_beam(true, null):
		push_error("CANNON_SHOT_FAILED(beam not fired)")
		return
	var proj := _new_projectile(p, before)
	if proj == null:
		push_error("CANNON_SHOT_FAILED(no projectile)")
		return

	var mz: Array = p.get("_muzzle_local")
	var t0: Vector3 = p.global_position
	if mz.size() > 0:
		t0 = p.global_transform * (mz[0] as Vector3)
	print("BEAM_ORIGIN %s" % _v(t0))
	var prev: Vector3 = proj.global_position
	var steps := 0
	for i in 6:
		await _pin(p, 1)
		if not is_instance_valid(proj):
			print("BEAM frame=%d 弹丸已消失（撞到东西 / 出界）" % i)
			break
		var now: Vector3 = proj.global_position
		print("BEAM frame=%d step=%.4f m travelled=%.3f m"
			% [i, now.distance_to(prev), now.distance_to(t0)])
		prev = now
		steps += 1
	print("BEAM ref: 匀速每帧应为 10900/60 = %.4f m；两段制出膛段只有 2880/60 = %.1f m"
		% [10900.0 / 60.0, 2880.0 / 60.0])
	print("BEAM 机头不飘时每帧位移应当逐帧相等（量了 %d 帧）" % steps)

	# ---- A2 连拍：放慢时间 + **侧向机位** ----
	#
	# ⚠️ 为什么必须要侧向机位：光束是**沿飞行方向**的细长圆柱（52 m × 3.2 = 166 m），
	# 从追尾机位看过去是**正对着它的横截面**（8 m 粗），再加上前景就是机体本身，
	# 四张图里"弹丸在哪儿"根本读不出来（第一版就是这么空欢喜一场：
	# `screen=(829,406)` 明明在画面内，图上却什么也看不见）。
	# 垂直于弹道看，166 m 的弹体与它**一帧一步**的位移才是可见的。
	print("---- A2 连拍（Engine.time_scale = %.2f + 侧向机位）----" % SLOW_MO)
	p.rifle_cooldown = 0.0
	p.rifle_mag = p.profile.rifle_magazine
	Engine.time_scale = SLOW_MO
	_side_cam(t0, p)
	before = _kids(p)
	if not p.fire_beam(true, null):
		Engine.time_scale = 1.0
		return
	proj = _new_projectile(p, before)
	print("BEAM 慢放下每帧位移 = %.2f m（= 181.6667 × %.2f）"
		% [10900.0 / 60.0 * SLOW_MO, SLOW_MO])
	for i in 4:
		await _pin(p, 1)
		_diag(p, proj)
		await _shot("10_beam_f%d" % i)
		if proj != null and is_instance_valid(proj):
			var trav: float = proj.global_position.distance_to(t0)
			print("BEAM 慢放 frame=%d travelled=%.1f m" % [i, trav])
			# 落盘给 Python 拼图用 —— 图上标的数字必须是**这一跑**量到的，
			# 抄上一次跑的数会在"换机位/换时间倍率"之后悄悄变成谎话。
			var bf := FileAccess.open(out_dir.path_join("beam_frames.txt"),
				FileAccess.WRITE if i == 0 else FileAccess.READ_WRITE)
			if bf != null:
				if i == 0:
					bf.store_line("frame=%d travelled=%.1f" % [i, trav])
				else:
					bf.seek_end()
					bf.store_line("frame=%d travelled=%.1f" % [i, trav])
				bf.close()
	Engine.time_scale = 1.0
	print("BEAM time_scale 已还回 %.2f" % Engine.time_scale)
	_side_cam_off()
	await _frames(3)


## 架一台**垂直于弹道**的相机（弹丸正侧方），拍完由 `_side_cam_off()` 撤掉。
func _side_cam(muzzle: Vector3, p: Node) -> void:
	var fwd: Vector3 = p.forward()
	var side: Vector3 = p.global_transform.basis.x.normalized()
	var cam := Camera3D.new()
	cam.name = "SideCam"
	cam.near = 0.5
	cam.far = 90000.0
	cam.fov = 40.0
	add_child(cam)
	cam.global_position = muzzle + side * 340.0 + Vector3(0.0, 70.0, 0.0) - fwd * 40.0
	cam.look_at(muzzle + fwd * 520.0, Vector3.UP)
	cam.current = true
	print("SIDE_CAM pos=%s 看向 %s" % [_v(cam.global_position), _v(muzzle + fwd * 520.0)])


func _side_cam_off() -> void:
	var c := get_node_or_null("SideCam") as Camera3D
	if c != null:
		c.queue_free()
	var chase = main.get("chase")
	if chase != null and is_instance_valid(chase):
		chase.current = true


## 弹丸到底在屏幕哪儿 —— "看不见"必须先分清是**没画**、**画在画外**、还是**太暗**。
func _diag(p: Node, proj: Node) -> void:
	if proj == null or not is_instance_valid(proj):
		print("DIAG 弹丸已失效")
		return
	var vp := get_viewport()
	var cam := vp.get_camera_3d()
	var mi: Node = proj.get_child(0) if proj.get_child_count() > 0 else null
	var px := cam.unproject_position(proj.global_position)
	print("DIAG proj=%s  cam=%s  canvas=%s  behind=%s  screen=(%.0f, %.0f)"
		% [_v(proj.global_position), _v(cam.global_position),
			str(vp.get_visible_rect().size), str(cam.is_position_behind(proj.global_position)),
			px.x, px.y])
	if mi is MeshInstance3D:
		var m := mi as MeshInstance3D
		print("DIAG   mesh visible=%s scale=%s origin=%s"
			% [str(m.visible), str(m.scale), _v(m.global_position)])


# ============================================================ B/C 蓄力（真实输入）

## **这一段的全部价值在"真"字**：走的是键盘/鼠标事件 → `_read_weapon_input()`
## → `_read_release_rifle()` → `fire_cannon()` 的完整链路。
## 套件里只能扫源码结构，"函数都写好了但没人读"这种坏法扫不出来。
func _phase_real_input(p: Node) -> void:
	print("---- B 蓄力：真实输入 ----")
	var e := _e()
	if e != null:
		e.global_position = p.global_position + p.forward() * 2200.0
	_aim_at(p, p.global_position + p.forward() * 2200.0)
	await _pin(p, 3)

	# ⚠️ 真实输入这一段必须**关掉 debug 输入**：`debug_input_enabled` 时
	# `_physics_process()` 在读完瞄准方向之后就 `return` 了，
	# `_read_weapon_input()` **整个不执行** ⇒ 按火键按到天荒地老也不会蓄力。
	p.debug_input_enabled = false
	p.rifle_mag = p.profile.rifle_magazine
	p.rifle_cooldown = 0.0
	p.cannon_cd_left = 0.0
	p.rifle_reloading = false
	p.reload_timer = 0.0
	await _frames(3)

	# 把真实光标钉到屏幕中心，免得"鼠标在哪"让准星乱跑
	Input.warp_mouse(Vector2(SHOT_W, SHOT_H) * 0.5)
	await _frames(2)
	Input.action_press("fire_primary")
	var charged_seen := false
	for i in 108:                       # 108 / 60 = 1.8 s > 门槛 1.7 s
		await get_tree().physics_frame
		if not charged_seen and p.cannon_charging():
			charged_seen = true
			print("CHARGE entered at %.3f s（门槛 %.2f s）"
				% [float(i + 1) / 60.0, p.profile.cannon_charge_time])
		if i == 54:                     # 0.9 s：**未满**的在长的弧
			print("CHARGE hold_ratio=%.3f charging=%s（应为“在长的弧”）"
				% [p.cannon_hold_ratio(), str(p.cannon_charging())])
			await _shot("20_charge_arc")
			await _crop("20b_charge_arc_zoom", 3)
		if i == 105:                    # 1.75 s：已进蓄力态 ⇒ 脉动整环
			print("CHARGE hold_ratio=%.3f charging=%s charged=%.2fs"
				% [p.cannon_hold_ratio(), str(p.cannon_charging()),
					p.cannon_charged_seconds()])
			await _shot("21_charge_full")
			await _crop("21b_charge_full_zoom", 3)
	print("CHARGE_RESULT charging=%s（真机：%s）"
		% [str(p.cannon_charging()), "真" if charged_seen else "**假** —— 输入没接上"])
	Input.action_release("fire_primary")
	# ⚠️ **松手之后不能只等一帧就读** —— 实测等 1 帧时 `active_cannon` 还是 null，
	#    于是"D 段又发了一发" ⇒ 两条柱叠着打，4 秒伤害量成 **278.2 ≈ 2×140**。
	#    根因是 `Input.action_release()` 的"just_released"帧戳与 `_physics_process` 的
	#    对齐关系（`is_action_just_released` 只在**它自己那一帧**为真），
	#    所以这里轮询到真的打出来为止，并把**第几帧**打出来记下来。
	var fired_at := -1
	for i in 8:
		await get_tree().physics_frame
		if p.active_cannon != null:
			fired_at = i
			break
	print("CHARGE release 之后 active_cannon=%s cd=%.2f reload=%s timer=%.2f mag=%d  松手后第 %d 帧打出来"
		% [str(p.active_cannon != null), p.cannon_cd_left, str(p.rifle_reloading),
			p.reload_timer, p.rifle_mag, fired_at + 1])
	await _shot("22_cannon_fired")


# ============================================================ D 激光柱

## 柱长 / 飞溅 / 4 秒伤害。
##
## ⚠️ 这一段用 `debug_input_enabled` + **手动钉住瞄准方向**，而不是靠真实鼠标：
## 真实鼠标在无头/自动化里只能 warp 到窗口中心，而"屏幕中心"和"敌机所在的世界方向"
## 差着追尾相机的俯角（`MOUSE_GAIN` 那套增益已在轮 41 删除）——
## 上一次跑就是这么把 4 秒伤害量成了 0.0。
## 输入链路本身在 B 段已经真跑过了；这里要的是**可复现的**几何。
func _phase_cannon(p: Node) -> void:
	print("---- D 激光柱 ----")
	var e := _e()
	if e == null:
		print("CANNON 没有敌机，跳过 D")
		return
	# ⚠️ 先把 B 段那发柱体清掉：不清的话两条柱会**同时照在同一台靶机**上，
	#    "4 秒掉 140" 会被量成 278.2（实测），而这条断言照样"看着挺对"。
	if p.active_cannon != null and is_instance_valid(p.active_cannon):
		p.active_cannon.queue_free()
		p.active_cannon = null
	await _frames(3)
	# 靶机正前方 2200 m（既在柱内，又远到能看出柱体的长度）
	e.global_position = p.global_position + p.forward() * 2200.0
	e.ifield_max = 0.0
	e.ifield_hp = 0.0
	e.hp = e.max_hp

	p.debug_input_enabled = true
	p.rifle_mag = p.profile.rifle_magazine
	p.rifle_cooldown = 0.0
	p.cannon_cd_left = 0.0
	p.rifle_reloading = false
	p.reload_timer = 0.0
	p.fm.velocity = Vector3.ZERO
	p.fm.align_velocity(p.forward())

	# 准星画在敌机上（纯视觉），方向则由 `aim_dir` 钉死
	_aim_at(p, e.global_position)
	var wish: Vector3 = (e.global_position - p.global_position).normalized()
	p.set_aim_direction(wish)
	# ⚠️ **必须冻住 `_physics_process`**：不然 `_read_aim_input()` 每帧都会
	# 用 `aim_cursor` 把 `aim_dir` 覆盖掉，上面那行白写。
	p.set_physics_process(false)
	await _frames(2)

	var hp0: float = e.hp + e.ifield_hp
	if not p.fire_cannon(e):
		print("CANNON fire_cannon 被拒绝（弹夹/冷却/过热？）")
		return
	var cd: Node3D = p.active_cannon
	# ⚠️ **方向与长度都要等 `_place()` 跑过再读**：`fire_cannon()` 只是把节点建出来，
	#    摆姿态在它的第一个 `_physics_process` 里。建完立刻读，读到的是
	#    `core` 的单位阵（`basis.y` = UP ⇒ 朝向 dot 读到 0.0027），
	#    长度读到的是"展开口只走了 41.7%" 的 4166.7 m。两条都是**假的**。
	await _frames(12)
	var core: MeshInstance3D = null
	if cd != null and is_instance_valid(cd):
		core = cd.get("_core") as MeshInstance3D
	var aim_dir := Vector3.ZERO
	if core != null:
		aim_dir = core.global_transform.basis.y.normalized()
	print("CANNON fired=%s  朝向 dot(指向敌机)=%.4f（1.0 才算真指着它）"
		% [str(cd != null), aim_dir.dot(wish)])
	print("CANNON 柱长=%.1f m（MAX_LEN=%.0f；展开动画 0.12 s 之后才是真长度）"
		% [core.scale.y if core != null else -1.0, BeamCannon.MAX_LEN])
	await _shot("23_cannon_column")

	# ---- 炮口飞溅特写 ----
	await _closeup_on_muzzles(p)
	await _shot("24_muzzle_closeup")

	# ---- 4 s 持续伤害 ----
	var frames := 0
	while frames < 260 and cd != null and is_instance_valid(cd):
		await get_tree().physics_frame
		frames += 1
	var hp1: float = e.hp + e.ifield_hp
	print("CANNON_DMG 柱体存活 %d 帧（%.2f s）靶机掉血 %.1f（期望 ≈ 35×4 = 140）"
		% [frames, float(frames) / 60.0, hp0 - hp1])
	print("CANNON 柱体 4 s 后还在吗：%s（应为 false）"
		% str(cd != null and is_instance_valid(cd)))


## 把相机挪到炮口旁边拍特写（双联炮 + 飞溅粒子 + 柱根）。
##
## 做法是**把自己的相机设成 current**：`Camera3D.current = true` 会自动把别的相机
## 置 false，不需要去动追尾相机自己的状态（那会被它的 `_physics_process` 写回）。
func _closeup_on_muzzles(p: Node) -> void:
	var mz: Array[Vector3] = p.cannon_muzzles()
	if mz.is_empty():
		print("CLOSEUP 没有炮口（`cannon_muzzles()` 空）")
		return
	var mid := Vector3.ZERO
	for m: Vector3 in mz:
		mid += p.global_transform * m
	mid /= float(mz.size())
	var fwd: Vector3 = p.forward()
	var side: Vector3 = p.global_transform.basis.x
	var cam := Camera3D.new()
	cam.name = "CloseupCam"
	cam.near = 0.5
	cam.far = 90000.0
	cam.fov = 42.0
	add_child(cam)
	cam.global_position = mid - fwd * 42.0 + side * 34.0 + Vector3(0.0, 14.0, 0.0)
	cam.look_at(mid + fwd * 260.0, Vector3.UP)
	cam.current = true
	print("CLOSEUP 炮口 %d 个 mid=%s" % [mz.size(), _v(mid)])
	await _frames(4)


# ============================================================ 工具

func _p() -> Node:
	var n = main.get("player")
	return n if (n != null and is_instance_valid(n)) else null


func _e() -> Node:
	var n = main.get("enemy")
	return n if (n != null and is_instance_valid(n)) else null


## 让准星指向世界里的某个点。
##
## ⚠️ `aim_cursor` 是**内容坐标**（`get_visible_rect()`）—— 与 `unproject_position()`
## 同一个空间。**不是**窗口尺寸、更不是落盘 PNG 的尺寸；工程设了拉伸，
## 三个量常常互不相等（`plume_nozzle_shot.gd` 在那上面栽过一次，标记整体错位 2.222 倍）。
func _aim_at(p: Node, world: Vector3) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null or cam.is_position_behind(world):
		p.aim_cursor = vp.get_visible_rect().size * 0.5
		return
	p.aim_cursor = cam.unproject_position(world)


## 把机体钉住（速度清零）并等 `n` 个物理帧。
##
## 不钉的话 `debug_throttle = 0` 只保证"不加速"，机体仍会缓慢下坠/漂移，
## 弹道起点每帧都在变 —— 连拍的"每帧位移"就混进了机体位移。
func _pin(p: Node, n: int) -> void:
	for i in n:
		p.fm.velocity = Vector3.ZERO
		await get_tree().physics_frame


func _kids(p: Node) -> Array:
	var c = p.get("projectile_container")
	if c == null or not is_instance_valid(c):
		return []
	return c.get_children()


## 找出刚刚新增的那颗弹丸（`fire_beam()` 之后）。
func _new_projectile(p: Node, before: Array) -> Node:
	var after := _kids(p)
	for ch in after:
		if before.has(ch):
			continue
		if ch is Projectile:
			return ch
	return null


func _v(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## 等追尾相机**追上机体**再开拍。
##
## ⚠️ 这一段是必须的，不是"保险起见"：`_setup_match()` 把机体瞬移到
## (3000, 900, 1500)，而追尾相机是**平滑跟随**的 —— 不等它，相机还挂在十几公里外
## （实测 `cam=(863, 1607, -12965)`，离机体 13 km），
## 于是 52 m × 3.2 = 166 m 长的光束在屏幕上只剩几个像素，
## "匀速光束看不看得见"这件事根本没被拍到（第一版就是这么空欢喜一场）。
## 判据用"相机到机体的距离收敛到正常跟随距离"，不是"等固定帧数"。
func _settle_camera(max_frames := 600) -> void:
	var cam = main.get("chase")
	var p := _p()
	if cam == null or p == null:
		return
	var want: float = (cam.offset as Vector3).length()
	var prev := INF
	var stable := 0
	for i in max_frames:
		await get_tree().physics_frame
		if not is_instance_valid(cam):
			return
		var d: float = cam.global_position.distance_to(p.global_position)
		if d < want * 1.6 and absf(d - prev) < 0.35:
			stable += 1
			if stable >= 10:
				print("CAMERA settled 距离=%.1f m（期望 %.1f，用了 %d 帧）" % [d, want, i + 1])
				return
		else:
			stable = 0
		prev = d
	print("CAMERA **没等到就位**（上限 %d 帧）—— 后面的图可能取景不对" % max_frames)


func _grab() -> Image:
	var vp := get_viewport()
	if vp == null:
		return null
	var tex := vp.get_texture()
	if tex == null:
		return null
	return tex.get_image()


func _shot(name: String) -> void:
	_idx += 1
	await RenderingServer.frame_post_draw
	var img := _grab()
	if img == null:
		return
	var path := out_dir.path_join("%s.png" % name)
	print("SHOT %s err=%d" % [path, img.save_png(path)])


## 屏幕中心那块**局部放大** —— 蓄力环半径只有 30 px，整屏图里读不出"弧长到几分之几"。
func _crop(name: String, zoom: int) -> void:
	await RenderingServer.frame_post_draw
	var img := _grab()
	if img == null:
		return
	var half := 150
	var cx := img.get_width() / 2
	var cy := img.get_height() / 2
	var x := clampi(cx - half, 0, maxi(img.get_width() - 1, 0))
	var y := clampi(cy - half, 0, maxi(img.get_height() - 1, 0))
	var w := mini(half * 2, img.get_width() - x)
	var h := mini(half * 2, img.get_height() - y)
	var sub := img.get_region(Rect2i(x, y, w, h))
	sub.resize(w * zoom, h * zoom, Image.INTERPOLATE_NEAREST)
	var path := out_dir.path_join("%s.png" % name)
	print("CROP %s (%dx%d → %dx%d) err=%d"
		% [path, w, h, w * zoom, h * zoom, sub.save_png(path)])
