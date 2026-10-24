extends Node3D
## N42·二十 判据探针：**同相机**对照「游戏内巡航形态」vs「柯西巡航2.0.glb」。
##
## ## 为什么要这个探针
##
## `xi_morph_live.gd` 证明「形态层写进去了」（局部角 141.30° 等与反解报告一致），
## 但用户报「游戏里飞翼位置还是错」。而 **局部角对了 ≠ 屏幕位置对了** ——
## 世界位置由**父链**决定，且游戏里其余骨停在待机 `fly`（非中性站姿）。
##
## `_ref_shots.gd` 拍的是 `xi_fly.glb` **rest**，不是游戏内巡航 ⇒ 两者不可比。
##
## 本探针把四张图放在**同一台固定相机**下（相机由参照件包围盒一次定死）：
##   ref_normal  = 柯西常态2.0.glb
##   ref_cruise  = 柯西巡航2.0.glb
##   game_normal = 游戏内 morph=0（`fly` 首帧）
##   game_cruise = 游戏内 morph=1（生产函数推到底）
##
## ## 跑法
##   godot --path <工程> res://tools/_n42_20_cmp.tscn -- --out <目录>
##   （**必须带窗**；headless 是 dummy 渲染器，出不来图）

## 参照在工程之外 ⇒ 用 GLTFDocument 读绝对路径。
const REF_DIR := "C:/Users/MSIPC/Desktop/游戏/闪哈游戏/柯西与佩涅罗佩/柯西模型/"
const REF_CRUISE := REF_DIR + "柯西巡航2.0.glb"
const REF_NORMAL := REF_DIR + "柯西常态2.0.glb"
## 参照相对主模型的朝向修正（N42·十四 实测 −90°；转错两张图朝向不同、没法比）。
const REF_YAW_DEG := -90.0
const MAIN_PATH := "res://assets/models/xi_movie/xi_movie_rigged.scn"

## 出生高度：必须高于 `FlightBody.CRASH_ALTITUDE`，否则掉下去 ⇒ `visible=false` ⇒ 静默出空图。
const SPAWN_Y := 400.0

## 量世界位置的骨（与 `xi_morph_live.gd` 的 PROBE_BONES 同批）。
const PROBE_BONES := ["BinderBack.L", "BinderFront.R", "Wing.L", "Wing.R",
	"RearHang.L", "RearHang.R"]

## 视角：[名, 方位角°, 仰角°, 距离系数]（与 `_ref_shots.gd` 同表 ⇒ 可跨探针比对）
const VIEWS := [
	["top", 0.0, 89.0, 0.95],
	["side", 200.0, 6.0, 1.05],
]


## ★★ 绕过 modifier 的对照档：手动把 8 根形态骨写成 `curve_target_of()`。
##
## 判决用法：
##   * 这一档屏幕**变了** ⇒ modifier 通路有问题（写入没进渲染求值链）；
##   * 这一档也**不变** ⇒ 问题在更下游（骨到不了几何）。
func _shoot_manual() -> void:
	if body == null or not is_instance_valid(body):
		return
	var sk: Skeleton3D = body.get("_model_skel")
	var mod: Object = body.get("_form_curve")
	if sk == null or mod == null:
		print("  [manual] 缺骨架或形态层 ⇒ 跳过")
		return
	# 动画恢复在播（否则 pose 不更新，手动写入同样进不了求值链）。
	var ma: Object = body.get("model_anim")
	var ap: Object = ma.get("player") if ma != null else null
	if ap != null:
		ap.call("play", "fly")
		ap.set("speed_scale", 1.0)
		ap.call("seek", 0.0, true)
	mod.set("morph", 1.0)
	await get_tree().process_frame
	mod.set("active", false)          # ★ 停掉 modifier，只留手动写入
	await get_tree().process_frame
	var n := 0
	var line := "      [manual] 写入："
	for nm in PROBE_BONES:
		var bi := sk.find_bone(nm)
		if bi < 0:
			continue
		var tq: Quaternion = mod.call("curve_target_of", bi)
		sk.set_bone_pose_rotation(bi, tq)
		line += " %s=%.1f°" % [nm, rad_to_deg(tq.get_angle())]
		n += 1
	print(line)
	print("      [manual] 共写 %d 根（modifier active=false）" % n)
	await get_tree().process_frame
	await get_tree().process_frame
	await _shoot("game_manual", body)

var out_dir := ""
var body: FlightBody = null
var _cam: Camera3D = null
var _focus := Vector3.ZERO
var _radius := 1.0
## `_process()` 帧计数器。与 `FormCurveModifier.calls` 对照，判「插队点有没有被驱动」。
var frames := 0


func _process(_delta: float) -> void:
	frames += 1


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size():
			out_dir = a[i + 1]
	if out_dir == "":
		print("!! 需要 --out <目录>")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_dir.replace("\\", "/"))
	var win := get_window()
	if win != null:
		win.size = Vector2i(1600, 1000)

	print("")
	print("########## N42·二十 同相机对照：游戏内巡航 vs 柯西巡航2.0 ##########")
	_build_env()

	# ---- ① 相机由**参照件**包围盒一次定死，四张图共用 ----
	var ref := _load_glb(REF_CRUISE)
	if ref == null:
		print("!! 参照加载失败 ⇒ 停手（相机定不下来）")
		print("VERDICT: N42-20-ABORTED")
		get_tree().quit(2)
		return
	ref.rotation.y = deg_to_rad(REF_YAW_DEG)
	add_child(ref)
	await get_tree().process_frame
	await get_tree().process_frame
	var b := _bbox(ref)
	_focus = b.get_center()
	_radius = maxf(b.size.length() * 0.5, 0.5)
	print("  [相机基准] 参照 bounds center=%s size=%s radius=%.3f"
		% [str(_focus), str(b.size), _radius])
	await _shoot("ref_cruise", ref)
	remove_child(ref)
	ref.queue_free()

	var rn := _load_glb(REF_NORMAL)
	if rn != null:
		rn.rotation.y = deg_to_rad(REF_YAW_DEG)
		add_child(rn)
		await get_tree().process_frame
		await get_tree().process_frame
		await _shoot("ref_normal", rn)
		remove_child(rn)
		rn.queue_free()

	# ---- ② 游戏内（生产侧 `SuitProfile.xi()`）----
	await _build_body()
	if body == null:
		print("!! 机体没建起来")
		print("VERDICT: N42-20-ABORTED")
		get_tree().quit(3)
		return
	await _shoot_game("game_normal", 0.0)
	await _shoot_game("game_cruise", 1.0)
	# ★★ 判决实验：把 `AnimationPlayer` **完全停掉**（`stop()`，不是 `speed_scale=0`）。
	#    若本档与 `game_cruise` **不同** ⇒ 说明动画每帧把 modifier 的写入覆盖了
	#    （write 执行了、但渲染用的是动画值）——那就解释了「读数全对、屏幕不动」。
	await _shoot_game("game_cruise_stop", 1.0, true)
	# ★★ 第三判决：**绕过 modifier**，手动把 8 根形态骨写成曲线目标。
	await _shoot_manual()
	# ★★ 第四判决（最重要）：直接播 `burst_cruise` —— 离线实测这份资产是
	#    「51 根骨整段恒定在巡航姿态」（首末夹角 0.000°）⇒ 它就是一份现成的
	#    **巡航全姿态**。若这一档画面 = `柯西巡航2.0.glb` ⇒ 证明用户原话那条路
	#    （「进巡航就用巡航形态」）**不靠形态层插队也能达成**。
	await _shoot_burst_cruise()

	if body != null and is_instance_valid(body):
		body.free()
	body = null
	await get_tree().process_frame
	print("")
	print("VERDICT: N42-20-DONE")
	get_tree().quit(0)


func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.63, 0.66)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.85)
	env.ambient_light_energy = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 132, 0)
	sun.light_energy = 1.5
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, -60, 0)
	fill.light_energy = 0.55
	fill.light_color = Color(0.7, 0.8, 1.0)
	add_child(fill)


func _build_body() -> void:
	var p := SuitProfile.xi()
	p.model_path = MAIN_PATH
	var holder := Node3D.new()
	holder.name = "Holder"
	add_child(holder)
	body = FlightBody.new()
	body.name = "XiBody"
	body.profile = p
	body.is_player = true
	body.use_placeholder = false
	body.flight_pitch_deg = 0.0
	holder.add_child(body)
	body.display_name = p.display_name
	# ⚠️ 出生点必须**高于** `FlightBody.CRASH_ALTITUDE`（24 m）——写成 (0,0,Y) 会让 y=0
	# ⇒ `destroy("撞海")` ⇒ `model_root.visible=false` ⇒ **出图全空且不报错**。实测踩过一次。
	body.global_transform = Transform3D(Basis(), Vector3(0.0, SPAWN_Y, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	body.set_physics_process(false)
	print("  [装配] %s ｜ model=%s ｜ form_curve=%s"
		% [p.display_name, p.model_path, p.model_form_curve])
	var fc: Object = body.get("_form_curve")
	var cf: Object = body.get("_cruise_form")
	print("         `_form_curve`=%s  `_cruise_form`=%s"
		% ["有" if fc != null else "无", "有" if cf != null else "无"])


## 一档：按生产链路把形态推到 `morph`，出图。
##
## `stop_anim` = true 时把 `AnimationPlayer` **完全停掉**（判决"写入是否被动画覆盖"）。
func _shoot_game(tag: String, morph: float, stop_anim := false) -> void:
	if body == null or not is_instance_valid(body):
		return
	var ma: Object = body.get("model_anim")
	var ap: Object = ma.get("player") if ma != null else null
	if ap != null:
		if stop_anim:
			ap.call("stop")
			await get_tree().process_frame
		else:
			# ★★ 让 `fly` **真的在播**（`speed_scale = 1`）= 游戏里的真实状态。
			#    上一版把动画冻住（`speed_scale = 0`）⇒ 实测 `calls` 只涨到 3，
			#    少得可疑：动画不动时 `Skeleton3D` 很可能**跳过求值链** ⇒
			#    `SkeletonModifier3D._process_modification()` 压根不被调 ⇒
			#    **探针测的不是游戏行为**（游戏里 `fly` 一直在播）。
			ap.call("play", "fly")
			ap.set("speed_scale", 1.0)
			ap.call("seek", 0.0, true)
	var fm: Object = body.get("fm")
	if fm != null:
		fm.set("boosting", true)            # 巡航形态的触发条件是 boosting
	var mod: Object = body.get("_form_curve")
	if mod == null:
		mod = body.get("_cruise_form")
	body.set("cruise_morph", morph)
	if mod != null:
		# ★★★ 关键怀疑：官方文档说 `influence` 由 `Skeleton3D` 用于**混合**修改结果。
		#     若它为 0 ⇒ 回调照跑、`last_applied_deg` 照报 141°，但**屏幕完全不变**
		#     —— 与实测现象逐条吻合。先打印原值，再显式置满。
		print("      influence(原值)=%s  active=%s"
			% [str(mod.get("influence")), str(mod.get("active"))])
		mod.set("influence", 1.0)
		mod.set("morph", morph)
	body.global_transform = Transform3D(Basis(), Vector3(0.0, SPAWN_Y, 0.0))
	await get_tree().process_frame
	await get_tree().process_frame
	print("  [%s] cruise_morph=%.2f ｜ 层=%.4f ｜ 层写入度=%.4f ｜ 层调用=%s ｜ anim_stopped=%s"
		% [tag, float(body.get("cruise_morph")),
		   float(mod.get("morph")) if mod != null else -1.0,
		   float(mod.get("last_applied_deg")) if mod != null else -1.0,
		   str(mod.get("calls")) if mod != null else "-",
		   str(stop_anim)])
	# ★★ 局部角对了 ≠ 世界位置对了。这里量**骨骼世界原点**——它决定件真正落在哪。
	#    ⚠️ `origin` 是骨的 **head**：骨骼绕自身 head 旋转时它本来就不动（我上轮踩过这个坑）。
	#    判「骨到底转没转」必须读 **basis**（朝向）与 **tail**（末端）。
	var sk: Skeleton3D = body.get("_model_skel")
	if sk != null:
		var line := "      世界原点(m)："
		for nm in PROBE_BONES:
			var bi := sk.find_bone(nm)
			if bi < 0:
				line += " %s=缺" % nm
				continue
			line += " %s=%s" % [nm, str(sk.get_bone_global_pose(bi).origin)]
		print(line)
		var line2 := "      全局basis.y（朝向）："
		for nm in PROBE_BONES:
			var bi := sk.find_bone(nm)
			if bi < 0:
				continue
			var tf: Transform3D = sk.get_bone_global_pose(bi)
			line2 += " %s=(%.3f,%.3f,%.3f)" % [nm, tf.basis.y.x, tf.basis.y.y, tf.basis.y.z]
		print(line2)
		if mod != null:
			print("      回调内 read_residual_deg=%.4f" % float(mod.get("read_residual_deg")))
		# ★★ 一锤定音：`_process()` 帧数 vs `_process_modification()` 调用数。
		#    若帧数在涨而 `calls` 不涨 ⇒ `SkeletonModifier3D` **根本没被驱动**（根因）。
		var f0 := frames
		var c0 := int(mod.get("calls")) if mod != null else -1
		for k in 20:
			await get_tree().process_frame
		var c1 := int(mod.get("calls")) if mod != null else -1
		print("      ★ 20 帧观察：frames %d→%d ｜ mod.calls %d→%d"
			% [f0, frames, c0, c1])
	await _shoot(tag, body)


## ★★ 第四判决档：直接播 `burst_cruise`（一份现成的"巡航全姿态"动作）。
func _shoot_burst_cruise() -> void:
	if body == null or not is_instance_valid(body):
		return
	var fc: Object = body.get("_form_curve")
	if fc != null:
		fc.set("active", false)          # 关掉形态层，避免干扰
	var cf: Object = body.get("_cruise_form")
	if cf != null:
		cf.set("active", false)
	var ma: Object = body.get("model_anim")
	if ma == null:
		print("  [burst_cruise] 无 model_anim ⇒ 跳过")
		return
	var nm: String = str(ma.get("burst_cruise_action"))
	var ok: bool = body.call("play_model_action", nm)
	print("  [burst_cruise] play_model_action(%r) -> %s" % [nm, str(ok)])
	await get_tree().process_frame
	await get_tree().process_frame
	var ap: Object = ma.get("player")
	if ap != null:
		ap.call("seek", 0.0, true)
		ap.set("speed_scale", 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var sk: Skeleton3D = body.get("_model_skel")
	if sk != null:
		var line := "      全局basis.y（朝向）："
		for nm2 in PROBE_BONES:
			var bi := sk.find_bone(nm2)
			if bi < 0:
				continue
			var tf: Transform3D = sk.get_bone_global_pose(bi)
			line += " %s=(%.3f,%.3f,%.3f)" % [nm2, tf.basis.y.x, tf.basis.y.y, tf.basis.y.z]
		print(line)
	await _shoot("game_burst_cruise", body)


func _load_glb(path: String) -> Node3D:
	if path.begins_with("res://"):
		var ps := load(path) as PackedScene
		if ps == null:
			return null
		return ps.instantiate() as Node3D
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(path, st)
	if err != OK:
		print("!! GLTFDocument 读失败 err=%d %s" % [err, path])
		return null
	return doc.generate_scene(st) as Node3D


func _bbox(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var bb := Transform3D(mi.global_transform.basis, mi.global_transform.origin) * mi.get_aabb()
		if first:
			out = bb
			first = false
		else:
			out = out.merge(bb)
	return out


## 只把有机体那一棵子树摆平（参照与机体共用同一台固定相机）。
func _shoot(tag: String, root: Node3D) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 34.0
		_cam.near = 0.05
		_cam.far = 5000.0
		add_child(_cam)
	# ★ 取景**各按自身包围盒归一**（参照与机体各自归一）——不作「同世界坐标」假设：
	#   机体侧 `SuitProfile` 会按 `target_height` 缩放/落位，直接套参照的世界取景
	#   会变成贴脸特写（实测第一次就是这么翻的：图里只有几块翼板）。
	var c := _focus
	var r := _radius
	if root is FlightBody:
		var mb: AABB = (root as FlightBody).model_bounds
		c = root.global_transform * mb.get_center()
		r = maxf(mb.size.length() * 0.5, 0.5)
		print("  [%s 取景] center=%s size=%s radius=%.3f" % [tag, str(mb.get_center()), str(mb.size), r])
	for v in VIEWS:
		var name := str(v[0])
		var az := deg_to_rad(float(v[1]))
		var el := deg_to_rad(float(v[2]))
		var k := float(v[3])
		var dir := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
		var f := c
		_cam.global_position = f + dir * r * 2.6 * k
		_cam.look_at(f, Vector3.UP)
		_cam.current = true
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img == null:
			print("    !! %s_%s 取不到图" % [tag, name])
			continue
		var p: String = out_dir.path_join("%s_%s.png" % [tag, name])
		img.save_png(p)
		print("    saved %s" % p.get_file())
