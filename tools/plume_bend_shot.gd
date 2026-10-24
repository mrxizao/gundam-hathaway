extends Node3D
## 2026-09-25（轮 17）交付用：**尾焰横风形变**的像素取证。
##
## ## 要回答的三件事
##   ① 侧向冲刺时，尾焰**真的弯了吗**（不是"看着像"，是逐像素差出来的）？
##   ② 弯的**方向**对不对（横移向右 ⇒ 焰往左偏）？
##   ③ 顺飞时那一条**还是直的吗** —— 也就是说"沿喷口轴的分量被丢掉了"这件事成立？
##
## ## 机位：**俯视**（本轮唯一的新东西）
##
## 形变发生在"喷口轴 × 横风"张成的那张平面里：喷口轴 = 机体本地 +Z，
## 横风 = 机体本地 ±X。两者都在 XZ 平面内 ⇒ 只有一个机位能把这条**抛物线**
## 看全：**从正上方往下看**。
##
## 相机 `look_at(目标, up = +Z)` 反解出来的像平面：
##   像右 = −X_world，像上 = +Z_world。
## 于是：焰从机尾往**上**喷；若机体沿 +X 横移，焰就该往**右**弯。
## 这条约定是给 `_r17_bend.py` 量"横向偏移"用的，写错整张图会左右镜像。
##
## ## ⚠️ 对照组是**速度的方向**，不是"开关形变"
##
## 探针里没有一个"关掉形变"的开关（那要塞调试钩子进生产代码）。
## 用的是三档速度，同一次代码路径：
##   · `zero`  速度 0          ⇒ 相对气流为 0 ⇒ 横分量 0 ⇒ 不弯
##   · `fwd`   沿机体 −Z 前进   ⇒ 气流与喷口轴**共线** ⇒ 横分量 0 ⇒ **也不弯**
##   · `right` 沿机体 +X 横移   ⇒ 气流垂直于喷口轴 ⇒ 满弯
## `zero` 与 `fwd` 的**速度大小完全不同**（0 vs 1.1×冲刺速度），
## 而它们的焰必须**一样直** —— 这一条就把"只取横分量"钉死了；
## 若哪天有人把整矢量直接喂进 `gravity`，`fwd` 会当场弯给出来。
##
## ## ⚠️ 机体必须 `set_physics_process(false)`
##
## 与 `tools/plume_nozzle_shot.gd` 同一个坑（那里有完整现场）：
## 摆在 y=0 的机体会在**第一个物理帧**被 `CRASH_ALTITUDE` 判"撞海"并 `destroy()`，
## 抓到的只会是一团爆炸。关掉物理解算 ⇒ 位置冻住、不做撞击判定，
## 而 `_tick_effects()` 由 `_settle()` 手工按 60 Hz 调 —— 尾焰与形变照常更新。
##
## 相机也不动，所以**机体的世界基就是单位基**：本地轴 == 世界轴，
## 上面那套"像右 = −X_world"才成立（机体一旦转过，脚本的前置断言会先红）。
##
## ## ⚠️⚠️ 这套量测的**噪声地板**（先读这段再看数字）
##
## 粒子模拟按**真实帧时长**推进，而 `await process_frame` 之间的帧长本身在抖
## ⇒ 同一档抓两次，粒子相位不同。实测：`gravity` 都为 0 的 `A_zero` 与 `A_fwd`
## 两档，渲染**本应逐像素相同**，却差了几百到几千个通道；钉死种子
##（`_freeze_random()`）后仍有 2560 / 9339 个通道在差。
##
## 这个抖动去不掉（`restart()` + 固定种子也试过，见 `_one_top_view()` 那段），
## 所以改成**把它量出来当参照**：探针每台机多抓 `A_zero2` / `B_zero2`，
## `_r17_bend.py` 拿它们算出"噪声地板"并打印信噪比。
## **读数只有明显大于噪声地板时才可信** —— 形态 A 在俯视机位下被机体挡住大半，
## 它的噪声地板比形态 B 大一倍多，所以形态 A 只作对照、不出结论。
##
## ## 跑法（**不能加 --headless**，dummy 渲染器抓出来是空的）
##   godot --path <工程> res://tools/plume_bend_shot.tscn -- <输出目录>

## 想要的窗口尺寸。⚠️ 它只是"请求"：本工程的 `project.godot` 自带拉伸设定，
## 真实内容坐标恒为 1600×1600，而落盘 PNG 是窗口尺寸 —— 两套坐标都要，
## 见 `_snap()` 的返回值和 `meta_*.txt` 里记的 `img`。
const SHOT_W := 900
const SHOT_H := 900
## 静置帧数：抓图有 1~2 帧滞后，加上要让粒子把喷口周围铺满一个寿命周期。
const SETTLE := 30
## 侧冲/前冲的速度 = `profile.player_boost_speed()` × 这个系数。
## 取 >1 是为了**打满**形变量（`amount = clamp(cross / ref, 0, 1)` 会在 1.0 处饱和）
## —— 本轮要量的是"满弯到底有多弯"。
const SPEED_MULT := 1.10
## 尾气那一层要不要留在画面里。
## ⚠️ **量形变时必须 false** —— 理由见 `_set_plumes()` 那段长注释（它会冒充焰梢）。
## 交付图也不带它：俯视图上它把机体糊成灰的，焰看不清。
const SHOW_SMOKE := false

var out_dir := "user://plume_bend"
var _cam: Camera3D


func _ready() -> void:
	# 用法：`-- <输出目录> [只跑这一台]`。第二参数是**可选的**机型过滤 ——
	# 一次跑三台要两三分钟，中途出岔子就得从头再来；一台一次跑得短、也好定位。
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else out_dir
	var only := str(args[1]) if args.size() > 1 else ""
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	_build_env()

	# ⚠️⚠️ 这一段是**必须的**（第一版没有它，结果是全场第一张基线不可复现）。
	#
	# `window_set_size()` 只是**请求**，本工程又设了拉伸（`stretch/mode = canvas_items`），
	# 渲染目标尺寸要好几帧才坐实。头几帧还在旧尺寸上渲染 ⇒ 同一机位、同一状态、
	# 同一台机的"关尾焰"基线抓出来**与它自己在结尾重抓的那张差 23640 个像素**
	#（第二台机起就逐像素差 0 —— 正是"前几帧"这个特征的指纹）。
	# 差分的整个逻辑都建立在"基线可比"上，所以这里先空转一段把尺寸坐实，并把
	# 真实视口打印出来留证。
	for _i in 40:
		await get_tree().process_frame
	var vp_now := get_viewport().get_visible_rect().size
	var win_now := DisplayServer.window_get_size()
	print("### 视口坐实：content %dx%d  window %dx%d" % [
		int(vp_now.x), int(vp_now.y), win_now.x, win_now.y])

	var suits := [
		["xi", SuitProfile.xi()],
		["penelope", SuitProfile.penelope()],
		["arizeus_cruise", SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE)],
	]
	for item: Array in suits:
		if only != "" and not str(item[0]).contains(only):
			continue
		await _shoot(str(item[0]), item[1] as SuitProfile)
	print("### PLUME_BEND_DONE -> %s" % out_dir)
	get_tree().quit(0)


func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055, 0.065, 0.085)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.70, 0.76, 0.88)
	env.ambient_light_energy = 1.15
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 150, 0)
	key.light_energy = 1.7
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12, -50, 0)
	fill.light_energy = 0.7
	fill.light_color = Color(0.72, 0.82, 1.0)
	add_child(fill)


## 一台机体：建 → 冻住 → 俯视六张 + 透视两张。
func _shoot(tag: String, prof: SuitProfile) -> void:
	var holder := Node3D.new()
	holder.name = "Holder_" + tag
	add_child(holder)

	var u := FlightBody.new()
	u.name = "Suit_" + tag
	u.team = 0
	u.is_player = true
	u.profile = prof
	u.display_name = tag
	u.use_placeholder = false
	# 机头朝 −Z、机体不俯冲：正交俯视才与"喷口轴 = 本地 +Z"这条约定严格对应。
	u.set("flight_pitch_deg", 0.0)
	holder.add_child(u)
	u.global_position = Vector3.ZERO
	u.max_hp = 1000.0
	u.hp = 1000.0
	u.ifield_max = 0.0
	u.ifield_hp = 0.0
	u.fm.throttle = 1.0
	# ⚠️ 见文件头：不关物理就会在第一个物理帧撞海自爆。
	u.set_physics_process(false)
	u.set_process(false)
	await _settle(u, 6)
	if u.model_pivot != null:
		u.model_pivot.rotation_degrees = Vector3.ZERO
	await _settle(u, 2)
	print("### 随机种子钉死 %-16s %d 个粒子系统" % [tag, _freeze_random(u, 20260925)])

	# ⚠️⚠️ **基线必须与六张 `on` 图是同一个机体形态**（本轮翻的第二个车，比姿态那个更隐蔽）。
	#
	# `_pose()` 里写了 `fm.boosting = true`，而 `_tick_cruise_morph()` 的判据是
	# `want = 1.0 if (fm.boosting and not fm.hovering) else 0.0` ⇒ 六张 `on` 图
	# 都是**巡航形态**（柯西展翼）。第一版抓基线时**没调 `_pose()`**（默认 boosting = false）
	# ⇒ 基线是**常态形态**（收翼）。于是"逐像素差分"比的根本不是"有没有尾焰"，
	# 而是"收翼的柯西 vs 展翼的柯西"：
	#   · 差分图 `_dbg4_offdiff.png` 里那对鲜红的 V 形大翼就是它；
	#   · 掩膜把整机剪影当成焰，`A_zero / A_fwd / A_right` 三张量出来**逐字相同**
	#     ——"形变没生效"是个假象，真因在这。
	# 柯西是**唯一**设了 `cruise_morph = true` 的档案（`suit_profile.gd` 的 `xi()`），
	# 所以只有它中招、佩涅罗佩两张基线逐像素差 0 —— 这个"只坏一台"的指纹反过来钉死了病因。
	await _prep_baseline(u)

	# ⚠️⚠️ 姿态/形态诊断（第一版与第二版都在这里翻的车）
	#
	# 第一版抓到的 `t_off` 与六张 `on` 图**机体形态不一样**（一张收翼、一张展翼），
	# 于是"逐像素差分"根本不是在比"有没有尾焰"，而是在比"两个不同的机体" ——
	# 掩膜把整个机翼剪影都算成了焰（17k 像素），而"焰梢横向偏移"恒等于常数。
	# 所以每一张抓图都记一行（姿态 + `cruise_morph`），出问题一眼看得出来，不用靠看图猜。
	var df := FileAccess.open(out_dir.path_join("pose_%s.txt" % tag), FileAccess.WRITE)
	df.store_line("字段：case / _hover_pose / flight_pitch_deg / pivot.rot.x /"
		+ " model_root.scale.x / bounds.size.y / global_pos.y / velocity / cruise_morph")
	df.close()

	# 前置断言：机体世界基必须是单位阵，否则"本地轴 == 世界轴"这句话不成立，
	# 后面整套"像右 = −X_world"的解读全是错的。
	var basis_err := 0.0
	for i in 3:
		basis_err = maxf(basis_err, (u.global_transform.basis[i] - Basis.IDENTITY[i]).length())
	if basis_err > 1e-4:
		push_error("%s：机体世界基不是单位阵（偏差 %.6f）—— 俯视读数会整体错位" % [tag, basis_err])

	var b := u.model_bounds
	var center := b.get_center()
	var diag := b.size.length()
	var org := u.global_position
	var vp := get_viewport().get_visible_rect().size
	var ref := prof.player_boost_speed()
	var v := ref * SPEED_MULT

	# ---- 喷口世界点 ----
	var world_pts: Array[Vector3] = []
	for p: Vector3 in prof.engine_plumes:
		world_pts.append(b.position + p * b.size)

	# ---- 俯视机位 ----
	# 机位要装下"机体 + 一整条焰 + 它被吹歪的那一段"，所以取 diag 与 62 的较大者。
	# `up = +Z` 是有意的（见文件头那段像平面反解），**不能**用默认的 Vector3.UP
	#（相机朝下看、up 与视线共线 ⇒ `look_at` 直接崩）。
	var hs := maxf(diag, 62.0) * 0.74
	var target := org + center + Vector3(0.0, 0.0, diag * 0.26)
	_cam = _make_cam()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = hs * 2.0
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.global_position = target + Vector3(0.0, diag * 2.4, 0.0)
	_cam.look_at(target, Vector3(0, 0, 1))
	await get_tree().process_frame

	# (0) 关尾焰：**同一机位的静止基线**。它一套就够 —— 机位与机体形态都冻住
	#     （`_pose` + `_force_morph(1.0)` 已在上面做过），六张 `on` 图共用它，
	#     所以每张的差值都只可能来自"粒子"，不可能来自机体。
	_diag(u, tag, "t_off")
	var img_size: Vector2i = await _snap(out_dir.path_join("%s_t_off.png" % tag))
	var kp := float(img_size.x) / maxf(vp.x, 1.0)

	# ---- 元数据 ----
	var f := FileAccess.open(out_dir.path_join("meta_%s.txt" % tag), FileAccess.WRITE)
	f.store_line("tag %s" % tag)
	f.store_line("img %d %d  view_content %.1f %.1f  scale %.6f" % [
		img_size.x, img_size.y, vp.x, vp.y, kp])
	f.store_line("bounds_pos %.6f %.6f %.6f" % [b.position.x, b.position.y, b.position.z])
	f.store_line("bounds_size %.6f %.6f %.6f" % [b.size.x, b.size.y, b.size.z])
	f.store_line("center %.6f %.6f %.6f" % [center.x, center.y, center.z])
	f.store_line("target %.6f %.6f %.6f  cam_size %.6f" % [
		target.x, target.y, target.z, _cam.size])
	f.store_line("basis_err %.9f" % basis_err)
	f.store_line("plume_count %d" % prof.engine_plumes.size())
	# 形状层上限也落盘：量测脚本要靠它判断"这一台的俯视图能不能出定量结论"
	#（喷口数在上限内 = 每个口都有自己的形状层与自己的轴；超了就是 16 条焰互相重叠）。
	# 从 `FlightBody` 读，量测脚本不重写一遍 —— 改常量时不会漏。
	f.store_line("shape_max_nozzles %d" % FlightBody.PLUME_SHAPE_MAX_NOZZLES)
	f.store_line("ref_speed %.3f  speed_mult %.3f  speed %.3f" % [ref, SPEED_MULT, v])
	f.store_line("plume_color %.6f %.6f %.6f %.6f" % [
		prof.engine_plume_color.r, prof.engine_plume_color.g,
		prof.engine_plume_color.b, prof.engine_plume_color.a])
	# 喷口的世界点 → 落盘像素（俯视图专用）。`unproject_position()` 给的是**内容坐标**，
	# 而 PNG 是窗口尺寸 —— 乘 `kp` 换算，不这么做标记会整体缩放错位 2.2 倍。
	for i in world_pts.size():
		var p := prof.engine_plumes[i]
		var px := _cam.unproject_position(org + world_pts[i]) * kp
		f.store_line("nozzle %.6f %.6f %.6f -> world %.4f %.4f %.4f -> px %.2f %.2f" % [
			p.x, p.y, p.z, world_pts[i].x, world_pts[i].y, world_pts[i].z, px.x, px.y])
	f.close()

	# (1..6) 六张俯视：{形态 A, 形态 B} × {静止, 顺飞, 侧移}
	var cases := [
		["A_zero", false, Vector3.ZERO],
		["A_fwd", false, Vector3(0, 0, -v)],
		["A_right", false, Vector3(v, 0, 0)],
		["B_zero", true, Vector3.ZERO],
		["B_fwd", true, Vector3(0, 0, -v)],
		["B_right", true, Vector3(v, 0, 0)],
	]
	var first := true
	for c: Array in cases:
		await _one_top_view(u, tag, str(c[0]), bool(c[1]), c[2] as Vector3)
		_dump_gravity(u, tag, str(c[0]), first)
		first = false

	# ---- 噪声地板对照：同一档**再抓一次** ----
	#
	# 见 `_restart_plumes()` 那段。"同档两次"的差就是**这套量测的噪声地板**：
	# 它必须是 0（否则后面所有"两档之间差了多少"都失去意义）。
	# 形态 A 与形态 B 各查一个 —— 两者在俯视图里的可见程度差一个数量级
	#（A 的焰短、大半被机体挡住），噪声对它们的影响完全不同。
	for rep: Array in [["A_zero", false, Vector3.ZERO], ["B_zero", true, Vector3.ZERO]]:
		await _one_top_view(u, tag, str(rep[0]) + "2", bool(rep[1]), rep[2] as Vector3)
		var dv := _pixel_diff(
			out_dir.path_join("%s_t_%s.png" % [tag, str(rep[0])]),
			out_dir.path_join("%s_t_%s2.png" % [tag, str(rep[0])]))
		var ok := dv.x == 0 and dv.y == 0
		# ⚠️ 这里是 **print 不是 push_error**，故意的。
		# 抖动是这个探针**已知且无法消除**的（见文件头那段），它不是"失败"，
		# 而是**这套量测的分辨率**。用错误级别报它，会让以后跑的人以为探针坏了。
		print("### 噪声地板 %-16s %-9s 同一档再抓 max=%3d n>10=%6d  差=%s（预期之内）" % [
			tag, str(rep[0]), dv.x, dv.y, "0" if ok else ">0"])

	# ⚠️ 基线的**复现性自检**：同一机位、同一状态、**再抓一次** `t_off`。
	# 与开头那张逐像素比 —— 两张必须一样。不一样就说明"差分基线"这件事本身不成立。
	#
	# ⚠️ 这里必须与开头的基线**逐字同一个调用**（`_pose` 的参数、`_force_morph` 的值
	# 都要一致）：第一版这里写的是 `_pose(u, false, ...)`，与开头那个"没调 `_pose`"
	# 的基线**恰好都让形态停在 0** 才没当场炸出来 —— 换句话说这道闸门当时是"假绿"。
	# 现在两边都显式推到形态 1.0，闸门才真的在盯差异。
	_set_plumes(u, false, SHOW_SMOKE)
	await _prep_baseline(u)
	_diag(u, tag, "t_off2")
	await _snap(out_dir.path_join("%s_t_off2.png" % tag))
	_check_baseline(tag,
		out_dir.path_join("%s_t_off.png" % tag),
		out_dir.path_join("%s_t_off2.png" % tag))

	# (7)(8) 透视：后上方**偏一点**（侧移的那段弯折要看得出来；
	#        正后方会把"往左弯"整段压扁成一条线，等于没拍到）。
	# ⚠️ 先把相机切到透视再抓 —— 第一版把两张都抓在正交机位上，
	# `p_off` 被覆盖成透视版、正交那张白抓，而且两张图机位不同没法相减。
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 36.0
	var k := Vector3(0.60, 0.46, 1.0).normalized()
	_cam.global_position = org + center + k * (diag * 2.05)
	_cam.look_at(org + center, Vector3.UP)
	_set_plumes(u, false, SHOW_SMOKE)
	_pose(u, true, Vector3.ZERO)
	await _settle(u, SETTLE)
	await _snap(out_dir.path_join("%s_p_off.png" % tag))
	_pose(u, true, Vector3(v, 0, 0))
	_set_plumes(u, true, SHOW_SMOKE)
	await _settle(u, SETTLE)
	await _snap(out_dir.path_join("%s_p_on.png" % tag))

	print("### SHOT %-16s 喷口 %2d 个  ref %.0f m/s  形变 accel 常量 %.0f" % [
		tag, prof.engine_plumes.size(), ref, FlightBody.PLUME_BEND_ACCEL])
	_cam.queue_free()
	holder.queue_free()
	await get_tree().process_frame


## 把这一台**所有**尾焰粒子系统的随机种子钉死。
##
## `GPUParticles3D.use_fixed_seed` + `seed` 是 Godot 4 给的确定性开关。
## ⚠️ 它**只**钉住"每一发喷出来的粒子长什么样"（图案），**钉不住相位** ——
## 粒子模拟仍按真实帧时长推进，同一档抓两次依旧不同（实测 2560 / 9339 个通道）。
## 留着它是因为它把"图案"这一半变数去掉了，剩下的相位噪声由 `*2` 那几张量。
##
## ⚠️ 用 `in` 判一下属性存在性：不同引擎版本这个属性有无变动过，
## 没有的话这里会静默跳过（返回 0），日志里一眼能看出来。
func _freeze_random(u: FlightBody, seed_val: int) -> int:
	var n := 0
	for p: GPUParticles3D in _all_particles(u):
		if "use_fixed_seed" in p:
			p.use_fixed_seed = true
			p.seed = seed_val
			n += 1
	return n


## ⚠️ 这里**故意不重开粒子**。
##
## 试过：`GPUParticles3D.restart()` + 固定种子，想让"每次抓图都从零发射固定帧数"，
## 从而完全确定。**两头都输**：
##   ① 没换来确定性 —— 粒子模拟按**真实帧时长**推进，而 `await process_frame`
##      之间的帧长本身在抖，固定种子只钉住"这一发长什么样"、钉不住相位。
##      实测同一档两次抓图仍差 2560 / 9339 个通道。
##   ② 反而把长束**截断**了 —— 探针跑在远高于 60 fps 的渲染帧率上，`SETTLE` 那 30
##      帧只推进了很短的真实时间，而 `afterburner_dash` 的 `lifetime = 0.26 s`：
##      重开后束只长了 **43 m**，而连续发射到稳态时是 **63 m**（≈ `260 m/s × 0.26 s`）。
## 所以改成：**让粒子一直连续发射到稳态**（各档之间不熄火，`_prep_baseline` 里
## `visible = false` 并不停止发射），相位噪声则由探针多抓的 `*2` 那几张量出来。
func _one_top_view(u: FlightBody, tag: String, case_name: String,
		dash: bool, vel: Vector3) -> void:
	_pose(u, dash, vel)
	_set_plumes(u, true, SHOW_SMOKE)
	await _settle(u, SETTLE)
	_diag(u, tag, case_name)
	await _snap(out_dir.path_join("%s_t_%s.png" % [tag, case_name]))


## 把所有尾焰粒子**从零重开**。
##
## ⚠️ **当前没有调用方** —— 保留它是因为"想消掉相位噪声"这件事早晚还要再试一次，
## 而上面的注释记着它这次为什么两头都输（不消噪、还把长束截短）。将来若真要用，
## 必须先解决"按真实帧时长推进"这一条（例如配合 `fixed_fps` 与固定帧长），
## 否则重复这次失败。
func _restart_plumes(u: FlightBody) -> int:
	var n := 0
	for p: GPUParticles3D in _all_particles(u):
		if p.emitting:
			p.restart()
			n += 1
	return n


func _all_particles(root: Node) -> Array[GPUParticles3D]:
	var acc: Array[GPUParticles3D] = []
	_gather_particles(root, acc)
	return acc


func _gather_particles(root: Node, acc: Array[GPUParticles3D]) -> void:
	if root is GPUParticles3D:
		acc.append(root as GPUParticles3D)
	for c: Node in root.get_children():
		_gather_particles(c, acc)


## 两张图的逐像素差 → `(最大通道差, 差 > 10 的通道个数)`。
## 返回负值表示读图失败（`-1`）或尺寸不一致（`-2`）。
func _pixel_diff(pa: String, pb: String) -> Vector2i:
	var ia := Image.load_from_file(pa)
	var ib := Image.load_from_file(pb)
	if ia == null or ib == null:
		return Vector2i(-1, -1)
	if ia.get_size() != ib.get_size():
		return Vector2i(-2, -2)
	ia.convert(Image.FORMAT_RGBA8)
	ib.convert(Image.FORMAT_RGBA8)
	var ba := ia.get_data()
	var bb := ib.get_data()
	var worst := 0
	var over := 0
	for i in ia.get_width() * ia.get_height():
		var o := i * 4
		for c in 3:
			var dd: int = absi(ba[o + c] - bb[o + c])
			worst = maxi(worst, dd)
			if dd > 10:
				over += 1
	return Vector2i(worst, over)


## ⚠️ `t_off` 与 `t_off2` **必须走这一个函数**。
##
## 第一版是两处各写一遍，而两边**恰好都把形态停在了 0** —— 那道"复现性自检"
## 于是显示"逐像素差 0"，是**假绿**；它把真正的问题（基线形态 ≠ 六张 `on` 图的形态）
## 整个盖住了。合成一处之后，自检才真的在盯东西。
##
## 顺序也是有意的：先让形状层**亮着**跑够帧（`cruise_morph` 的插值要
## `cruise_morph_seconds` = 0.45 s ≈ 27 帧，`SETTLE` = 30 刚好盖住），
## 再整层 `visible = false` 摘掉（见 `_set_plumes()` 那段为什么不能只停 `emitting`）。
func _prep_baseline(u: FlightBody) -> void:
	_pose(u, true, Vector3.ZERO)
	_force_morph(u, 1.0)
	await _settle(u, SETTLE)
	_set_plumes(u, false, SHOW_SMOKE)
	await _settle(u, 4)


## 把巡航变形**直接推到终态**：写 `cruise_morph` **并且**把 blend shape 值自己写一遍。
##
## ⚠️ 只写 `cruise_morph` 不够：`FlightBody._tick_cruise_morph()` 在
## `is_equal_approx(cruise_morph, want)` 时**提前 return**，那个 return 跳过了
## `set_blend_shape_value()` —— 于是"值对了、机体却没变形"，而且**下一帧还是不写**。
## 这个坑在探针里必须自己补上：探针要的是"确定的终态"，不是"等 27 帧让它自己走完"。
func _force_morph(u: FlightBody, v: float) -> void:
	u.call("_collect_morph_nodes")
	u.cruise_morph = v
	for mi: MeshInstance3D in (u.get("_morph_nodes") as Array):
		if mi == null or not is_instance_valid(mi):
			continue
		var am := mi.mesh as ArrayMesh
		if am == null:
			continue
		for s in am.get_blend_shape_count():
			mi.set_blend_shape_value(s, v)


## 摆好这一档的"在不在冲刺 / 速度朝哪"。
##
## ⚠️ `translate_dash` 要**直接写**：正常路径里它由 `_apply_translate()` 每帧从
## `_qb_timer` 推出来，而这里物理是关掉的 ⇒ 不写它 `assist_dashing()` 恒 false，
## 形态 B 六张会全变成形态 A（而且"两张一样"看起来像形变没生效，很容易查错方向）。
func _pose(u: FlightBody, dash: bool, vel: Vector3) -> void:
	u.translate_mode = dash
	u.translate_dash = dash
	u.set("_qb_timer", 0.40 if dash else 0.0)
	u.fm.super_boost = false
	u.fm.boosting = true
	u.fm.throttle = 1.0
	u.fm.velocity = vel
	u.fm.speed = vel.length()


## 把这一档每个尾焰发射器**真正拿到的 `gravity`**落盘。
##
## 这是"材质真的被写了"的凭证 —— 只看图看不出"是 `gravity` 生效了、还是碰巧像"。
## 顺带记录"哪些发射器在发射"，便于判断一张图里到底哪一层在亮。
func _dump_gravity(u: FlightBody, tag: String, case_name: String, first: bool) -> void:
	var f := FileAccess.open(out_dir.path_join("gravity_%s.txt" % tag),
		FileAccess.WRITE if first else FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end(0)
	var bend: Vector3 = u.get("_plume_bend")
	f.store_line("[%s] body_bend %.4f %.4f %.4f   （机体本地，来自 _plume_bend）" % [
		case_name, bend.x, bend.y, bend.z])
	for k: String in ["_afterburner_fx", "_dash_fx", "_dash_rings"]:
		var n := u.get(k) as GPUParticles3D
		var g := _pm(n)
		f.store_line("  %-16s emitting=%-5s gravity %.4f %.4f %.4f" % [
			k, str(n != null and n.emitting), g.x, g.y, g.z])
	var idx := 0
	for item: Dictionary in (u.get("_plume_fx") as Array):
		for k2: String in ["fx", "ab", "dash", "boost"]:
			var n2 := item.get(k2) as GPUParticles3D
			if n2 == null or not is_instance_valid(n2):
				continue
			var g2 := _pm(n2)
			f.store_line("  口%d.%-5s emitting=%-5s gravity %.4f %.4f %.4f" % [
				idx, k2, str(n2.emitting), g2.x, g2.y, g2.z])
		idx += 1
	f.close()


func _pm(n: GPUParticles3D) -> Vector3:
	if n == null or not is_instance_valid(n):
		return Vector3.ZERO
	var pm := n.process_material as ParticleProcessMaterial
	return pm.gravity if pm != null else Vector3.ZERO


func _make_cam() -> Camera3D:
	var c := Camera3D.new()
	c.near = 0.05
	c.far = 8000.0
	c.current = true
	add_child(c)
	return c


## 把机体身上所有尾焰相关的粒子系统**开/关**。
##
## ⚠️ 只关 `emitting` 不够：`GPUParticles3D` 停止发射之后**已经在场的粒子还会活完
## 剩下的寿命**（0.30 s ≈ 18 帧），于是"关掉"的那一张里仍然有火。
## `visible = false` 才是同一瞬间的干净基线。
##
## ## ⚠️⚠️ 尾气（`fx` = `ExhaustSmoke`）**本轮第一次必须单独摘掉**
##
## 第一版把它一起开着，结果俯视图的差分掩膜里出现了一大团**与速度无关的**
## 灰斑（实测：`A_zero` / `A_fwd` / `A_right` 三张在 y 415~735 那几段的
## 像素数、x 均值、x 极值**逐字相同**）—— 那是世界空间的尾气在喷口附近积出来的
## 一团烟，它**不参与横风形变**（`FX.set_plume_bend()` 后面那段写着为什么不参与）。
##
## 它有两个坏处，第二个是致命的：
##   ① 交付图上它把机体糊上一层灰，纵向那条焰看不清；
##   ② "焰梢离喷口多远"这个量被它带跑 —— 烟团的极值像素**比焰还远**，
##      于是 `A_right`（真的弯了）与 `A_fwd`（不该弯）量出来**一模一样**。
## 所以本轮单独给一个开关：量形变时只留**形状层**（`ab` / `dash` / `boost`）
## 与喷口光晕，尾气整层摘掉。它与形变无关，把它留在画面里只是给尺子加噪声。
func _set_plumes(u: FlightBody, on: bool, with_smoke := true) -> void:
	for k: String in ["_afterburner_fx", "_dash_fx", "_dash_rings", "_smoke_fx"]:
		var node := u.get(k) as GPUParticles3D
		if node != null and is_instance_valid(node):
			node.visible = on
	for item: Dictionary in (u.get("_plume_fx") as Array):
		for k2: String in ["fx", "glow", "boost", "ab", "dash"]:
			var node2 := item.get(k2) as Node3D
			if node2 == null or not is_instance_valid(node2):
				continue
			if k2 == "fx" and not with_smoke:
				node2.visible = false
				continue
			node2.visible = on


## 推进 `frames` 个**渲染帧**，同时按 60 Hz 手工调 `_tick_effects()`。
## 机体已被 `set_physics_process(false)`，引擎不会再碰它，而尾焰的
## `emitting` / `amount_ratio` / **`gravity`（本轮的形变）** 全在 `_tick_effects()` 里逐帧写。
func _settle(u: FlightBody, frames: int) -> void:
	for _i in frames:
		u.call("_tick_effects", 1.0 / 60.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


## 记一行姿态。见 `_shoot()` 里那段"姿态诊断"的注释。
func _diag(u: FlightBody, tag: String, case_name: String) -> void:
	var f := FileAccess.open(out_dir.path_join("pose_%s.txt" % tag), FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end(0)
	var pivot := 0.0
	if u.model_pivot != null:
		pivot = u.model_pivot.rotation_degrees.x
	var sc := 1.0
	if u.model_root != null:
		sc = u.model_root.scale.x
	f.store_line("%-9s hp=%7.3f pitch=%5.1f pivot=%7.3f rootscale=%.4f by=%.2f py=%.2f v=%.1f cm=%.3f"
		% [case_name, u.get("_hover_pose"), u.get("flight_pitch_deg"), pivot, sc,
			u.model_bounds.size.y, u.global_position.y, u.fm.velocity.length(),
			u.cruise_morph])
	f.close()


## 基线的**复现性自检**：`t_off` 与结尾重抓的 `t_off2` 必须**逐像素相同**。
##
## 这是整套差分测量唯一的立足点 —— 两张基线不一样，"哪张 `on` 图的差值是尾焰"
## 就无从谈起。所以它**不只是打印**：差出超过阈值直接 `push_error`，
## 让回归脚本一眼看得见（而不是等量出来的角度奇怪了再回头查）。
func _check_baseline(tag: String, pa: String, pb: String) -> void:
	var dv := _pixel_diff(pa, pb)
	if dv.x < 0:
		push_error("%s：基线自检读不到图或尺寸不同（%s / %s）" % [tag, pa, pb])
		return
	var verdict := "OK" if (dv.x == 0 and dv.y == 0) else "**不可复现**"
	print("### 基线自检 %-16s max=%3d  n>10=%6d  %s" % [tag, dv.x, dv.y, verdict])
	if dv.x != 0 or dv.y != 0:
		push_error("%s：基线不可复现（max %d，差>10 的通道 %d 个）——"
			% [tag, dv.x, dv.y]
			+ "差分测量的前提不成立，先别用这一批图")


## 抓图。返回**落盘图像**的像素尺寸 —— 它和 `get_viewport().get_visible_rect()`
## **不是一回事**（工程设了拉伸）。所有"世界 → 像素"的换算都必须用落盘尺寸。
func _snap(path: String) -> Vector2i:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("抓图失败：%s" % path)
		return Vector2i.ZERO
	img.convert(Image.FORMAT_RGBA8)
	img.save_png(path)
	var sz := img.get_size()
	print("    snap %-34s %dx%d" % [path.get_file(), sz.x, sz.y])
	return sz
