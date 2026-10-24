extends Node3D
## ★63-14 核心 · 量产型ν高达 **军刀 + 大炮** 真机取证。
##
## 用户原话：「给量产型牛高达增加光束军刀和光束大炮」。
##
## ⚠️ **不能加 `--headless`** —— dummy 渲染器一个像素都不产生，抓出来全黑。
##
## 跑法：godot --path <工程> res://tools/_r63_14_core_arms_shot.tscn -- <输出目录>
##
## ## 这个探针要证的两件事（都**只能**靠真机像素）
##   ① **军刀真的挂在核心的"真手骨"上并且看得见** —— 这是本工程栽过的真实 bug：
##      旧实现把刀挂在**被隐藏的占位骨架**上 ⇒ 节点在树里、判定照算、**一个像素不显示**，
##      而当时那两条断言（"节点存在 / 在树里"）**全绿**。核心的模型是 `nu_mp_fly.glb`，
##      它有没有真骨 `hand_L` 是**资产事实**，只有渲染出来才算数。
##   ② **大炮真的从核心的炮口射出可见光柱** —— 核心的炮是 ★63-14 新开的，
##      它走 `cannon_muzzles()`（= 核心自己的 `muzzle_L/R` 骨），此前从没在核心上跑过。
##
## ## 为什么用 `SubViewport`（★63-13 的教训，别再踩）
## 主视口 `get_viewport().get_texture().get_image()` **抓到的帧可能与所设相机无关**
##（同一机位连拍三张逐位相同、连自检盒子都不渲染）。子视口这条路 ★63-10/★63-13 已证可读：
## 相机放进子视口、`render_target_update_mode = UPDATE_ALWAYS`、`size` 由探针定死。
##
## ## 为什么必须**正交相机**
## 透视相机下"手在机体前方 ⇒ 离相机更近 ⇒ 必然更粗"，这个效应会盖掉要量的大小。
## `PROJECTION_ORTHOGONAL` + `KEEP_HEIGHT` ⇒ 像素宽 = 世界宽 × (视口高 / `size`)，与深度无关。
##
## ## 差分配对的纪律（这三条是本探针最要紧的东西）
## ① **只允许一个差异**：军刀那两张只有 `_blade.visible` 一开一关。
##    ⚠️ **不能**拿"起手前 / 起手后"当配对 —— 起手会 `play_model_action("slash")`，
##    整条手臂都在动，差分里混着手臂位移，量出来的"刀长"是假的。
##    所以：起手之后**先把动作冻住**（`player.speed_scale = 0`），再 toggle 刀本身。
## ② **量测时必须把机体藏掉 —— 但只能藏 `model_root`，绝不能藏 FlightBody 本身**：
##    刀的锚点 `_blade_anchor` 是 `add_child` 挂在 **FlightBody** 下的
##    （`flight_body.gd:4716`，注释明写"不在 `model_root` 里"）⇒ `u.visible = false`
##    会把刀**一起**藏掉，两张图全黑、差分为 0（实测 `FAIL: 没有任何亮像素`）。
##    而侧视时机体本来就会挡住刀身近端（实测量到 171.0 px，真实 192.86 px，−11.8%）
##    ⇒ 藏 `model_root` 一石二鸟：机体不在、刀身全长可见、`off` 那张全黑。
##    观感另出一张 `14_b_saber_side`（机体 + 刀同框，**不用于量测**）。
## ③ **大炮要藏整根 `beam`，不能只藏 `_core / _glow`** —— `BeamCannon._physics_process()`
##    每帧会把这两个 `visible` 重设回 `true`（它自己的淡出逻辑）；而且炮口粒子是
##    **持续发射**的，不停掉、不等它亡，就会在柱旁堆出一团亮云，把差分 bbox 撑到
##    204 x 284 px（柱本体应是 814 x 48 px）。
##
## ## 台子体检（与产品无关的那一问）
## 自检盒 4 m × 8 m 纯青（**不是绿** —— 军刀/光柱都是加色混合，会把它洗成别的颜色）。
##
## ## 产物
##   14_a_plain.png        核心 · 平飞（对照：没有刀）
##   14_b_saber_side.png   核心 · 军刀亮 —— **观感图**：机体 + 刀同框（侧视，**不用于量测**）
##   14_b_saber_on/off.png 核心 · 刀亮 / 刀藏 —— **量测用**：**机体已藏**，差分 = 纯刀身
##   14_ref_box/plain.png  自检盒 开 / 关（差分 = 盒子）
##   14_c_cannon.png       核心 · 大炮整体（机体 + 柱 + 炮口粒子，观感）
##   14_c_beam_on/off.png  核心 · 只留柱 / 全藏（差分 = 柱体）
##   14_d_xi_on/off.png    **柯西** · 军刀亮 / 刀藏（**正对照**：证明本台子画得出刀）
##   core_arms_geom.txt    几何读数（给纯 Pillow 的量测脚本用，**不读被验证的源码**）

const ORTHO_SABER := 70.0
const ORTHO_CANNON := 320.0
const WALL_M := 300.0
const VIEW_W := 1600
const VIEW_H := 900
const Y_ALT := 3000.0
const BOX_M := Vector3(4.0, 8.0, 4.0)

var out := "user://r63_14_core_arms"
var sub: SubViewport
var cam: Camera3D
var last := Vector2i.ZERO
var box: MeshInstance3D

# 读数
var g := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(VIEW_W, VIEW_H))

	# ---- 黑底、环境光、关雾 ----
	#
	# ⚠️ **必须给光**：无光时 PBR 材质渲染成**纯黑** ⇒ 观感图里机体等于不存在
	#    （实测：`14_b_saber_side` 上只剩一个自发光绿点 + 一道刀，"机体 + 刀同框"
	#    这句话在图上是假的）。
	#    给光**不影响任何判据** —— 量测那几张（军刀 / 光柱）里机体本来就被藏掉，
	#    自检盒又是 `SHADING_MODE_UNSHADED`，背景是 `BG_COLOR` 纯黑 ⇒ 加光前后逐位不变。
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.65, 0.74)
	env.ambient_light_energy = 0.85
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_energy = 1.5
	key.rotation_degrees = Vector3(-42.0, 32.0, 0.0)
	key.shadow_enabled = false
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.name = "RimLight"
	rim.light_energy = 0.8
	rim.rotation_degrees = Vector3(-18.0, 205.0, 0.0)
	rim.shadow_enabled = false
	add_child(rim)

	# ---- 子视口 + 正交相机 ----
	sub = SubViewport.new()
	sub.name = "ArmsViewport"
	sub.size = Vector2i(VIEW_W, VIEW_H)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.own_world_3d = false
	sub.transparent_bg = false
	add_child(sub)
	cam = Camera3D.new()
	cam.name = "ArmsCam"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = ORTHO_SABER
	cam.near = 1.0
	cam.far = 90000.0
	sub.add_child(cam)
	cam.make_current()

	# ---- 自检盒：4 m × 8 m，**青色**（军刀紫 / 光柱紫都不会把它洗成青）----
	box = MeshInstance3D.new()
	box.name = "RefBox"
	var bm := BoxMesh.new()
	bm.size = BOX_M
	box.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(0.0, 1.0, 1.0)
	box.material_override = bmat
	add_child(box)
	box.visible = false

	# ---- 挡板：把 10 km 的光柱截到 ~300 m（不可见，只参与射线）----
	var wall := StaticBody3D.new()
	wall.name = "StageWall"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(8000.0, 8000.0, 4.0)
	cs.shape = bs
	wall.add_child(cs)
	wall.collision_layer = 1        # = BeamCannon.WORLD_LAYER
	wall.collision_mask = 0
	add_child(wall)
	# 机体朝 −Z ⇒ 挡板放在 −Z 侧
	wall.global_position = Vector3(0.0, Y_ALT, -WALL_M)

	# ---- 光柱容器（`FlightBody.projectile_container`）----
	var bcontainer := Node3D.new()
	bcontainer.name = "BeamContainer"
	add_child(bcontainer)

	# ============================================================ 核心 · 量产型ν高达
	var core := SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU)
	var u := _body(core, 0, true)
	u.projectile_container = bcontainer
	await _frames(8)                     # 模型 / 骨架 / 动作库就绪
	_orient_and_freeze(u)
	await _frames(2)

	g["core_has_saber"] = core.has_saber
	g["core_cannon_enabled"] = core.cannon_enabled
	g["saber_blade_front"] = core.saber_blade_front
	g["core_weapon_slots"] = "|".join(core.weapon_slots())
	g["unit_pos"] = _v(u.global_position)
	g["unit_fwd"] = _v(u.forward())

	# ---------- A 对照：还没有刀 ----------
	# ⚠️ **必须先摆相机**：`cam` 是 `Camera3D.new()`，默认停在**世界原点 (0,0,0)**，
	#    而机体在 (0, 3000, 0) ⇒ 不摆位拍出来是**空场景**
	#    （首版实测：`14_a_plain.png` 与空着的 `14_c_beam_off.png` **md5 逐位相同**
	#     `2b8a8642`，"对照"其实什么都没照到）。这里用**骨头**取手的位置（不需要刀），
	#    机位与后面军刀那两张一致 ⇒ A 与 B 天然构成"无刀 / 有刀"同框对照。
	var hand0 := _hand_world(u)
	_mid_pose(u, hand0 + u.forward() * (core.saber_blade_front * 0.5))
	await _frames(3)
	_diag("A0", "核心平飞（无刀）")
	await _shot("14_a_plain")

	# ---------- B 军刀 ----------
	var ok_saber: bool = u.try_saber(null)
	g["try_saber"] = ok_saber
	await _frames(4)
	_freeze_pose(u)
	var hand := _hand_world(u)
	g["hand_world"] = _v(hand)
	g["hand_screen"] = _v2(cam.unproject_position(hand))
	g["blade_null"] = u._blade == null
	if u._blade == null:
		push_error("SHOT_FAILED(核心没有刀 —— try_saber 没建出 _blade)")
	else:
		g["blade_visible_in_tree"] = u._blade.is_visible_in_tree()
		g["blade_parent_is_anchor"] = u._blade.get_parent() == u._blade_anchor
		g["blade_off_world"] = "%.4f" % u._blade.global_position.distance_to(hand)
		# 相机对准刀身中段：刀沿机头 −Z，从手骨往外 15 m
		_mid_pose(u, hand + u.forward() * (core.saber_blade_front * 0.5))
		await _frames(3)
		g["blade_root_screen"] = _v2(cam.unproject_position(u._blade.global_position))
		g["blade_tip_screen"] = _v2(cam.unproject_position(
			hand + u.forward() * core.saber_blade_front))
		# 观感图：机体 + 刀同框（**这张不用于量测**）
		await _shot("14_b_saber_side")
		# ⚠️ 量测必须**只藏机体模型 `model_root`**，**绝不能藏 FlightBody 自己** ——
		#    刀的锚点 `_blade_anchor` 是 `add_child` 挂在 **FlightBody** 下面的
		#    （`flight_body.gd:4716`，注释明写"不在 `model_root` 里"）⇒
		#    `u.visible = false` 会把刀**一起**藏掉 ⇒ 两张图都是全黑、差分为 0
		#    （首版实测就是 `FAIL: 没有任何亮像素`）。
		#    而侧视时机体本来就会挡住刀身近端（再首版：量到 171.0 px，真实 192.86 px）
		#    ⇒ 藏掉 `model_root` 正好一石二鸟：机体不在，刀身全长可见。
		u.model_root.visible = false
		await _frames(3)
		if u.model_root.visible:
			push_error("SHOT_FAILED(model_root.visible 被别处覆盖回 true —— 请改用公开 API)")
		await _shot("14_b_saber_on")
		u._blade.visible = false
		await _frames(3)
		await _shot("14_b_saber_off")
		u._blade.visible = true
		await _frames(2)

	# ---------- 自检盒（与上面两张**同机位 / 同 size / 同姿态**）----------
	box.global_position = _hand_world(u) + u.forward() * (core.saber_blade_front * 0.5)
	if u._blade != null:
		u._blade.visible = false
	box.visible = true
	await _frames(3)
	await _shot("14_ref_box")
	box.visible = false
	await _frames(3)
	await _shot("14_ref_plain")
	g["ppm_saber"] = float(VIEW_H) / ORTHO_SABER
	g["ref_box_m"] = _v(BOX_M)

	# ---------- C 大炮 ----------
	u.model_root.visible = true      # ⚠️ B 段把机体藏了；观感图 `14_c_cannon` 要看得见机体
	u.abort_saber()
	await _frames(3)
	var fired: bool = u.fire_cannon(null)
	g["fire_cannon"] = fired
	g["cannon_available"] = u.cannon_available()
	g["cannon_ready_before"] = true       # fire_cannon 成功即证明当时 ready
	g["muzzles"] = str(u.cannon_muzzles().size())
	var muz := _muzzle_world(u)
	g["muzzle_world"] = _v(muz)
	var beam: Node3D = u.active_cannon
	if beam == null:
		push_error("SHOT_FAILED(核心没造出 BeamCannon —— fire_cannon 返回 %s)" % str(fired))
	else:
		await _frames(30)                 # 展开动画 0.12 s ≈ 7.2 帧 ⇒ 30 帧足够
		var bc := beam.get("_core") as MeshInstance3D
		var bg := beam.get("_glow") as MeshInstance3D
		g["beam_children"] = str(beam.get_child_count())
		if bc != null:
			g["beam_len"] = "%.3f" % bc.scale.y
			g["beam_near_r"] = "%.3f" % (bc.mesh as CylinderMesh).bottom_radius
		if bg != null:
			g["beam_glow_r"] = "%.3f" % (bg.mesh as CylinderMesh).bottom_radius
		# 整体观感（机体 + 柱 + 炮口粒子）
		cam.size = ORTHO_CANNON
		_cam_at_side(muz + u.forward() * (WALL_M * 0.45), u.forward(), 2000.0)
		await _frames(3)
		g["muzzle_screen_cannon"] = _v2(cam.unproject_position(muz))
		g["ppm_cannon"] = float(VIEW_H) / ORTHO_CANNON
		await _shot("14_c_cannon")
		# 只留柱体（机体藏起来）⇒ on / off 差分 = 柱。
		#
		# ⚠️ 两条**必须**的纪律 —— 首轮两条都踩了，量出来的"柱"根本是别的两样东西：
		#   ① 藏**整根** `beam`，不能只设 `_core / _glow .visible = false`：
		#      `BeamCannon._physics_process()` **每帧**都会把这两个 visible 重设回 true
		#      （那是它自己的淡出逻辑 `fade > 0.01`），下一帧就把柱点亮了。
		#      **父节点 hidden 才压得住子节点。**
		#   ② 先把炮口粒子 `emitting = false` 并**等它消亡**（`FX.cannon_muzzle` 寿命 0.42 s
		#      ⇒ 45 帧足够）。粒子是**持续发射**的，会在柱旁堆出一团几百像素高的亮云，
		#      把差分的 bbox 整个撑歪（首轮量到 204 x 284 px，而柱本体应是 814 x 48 px）。
		u.visible = false
		_stop_particles(beam)
		await _frames(45)
		await _shot("14_c_beam_on")
		beam.visible = false
		await _frames(4)
		await _shot("14_c_beam_off")
		beam.visible = true
		u.visible = true

	# ============================================================ D 正对照：柯西
	# 目的只有一个：**证明这个台子画得出刀**。没有它的话，"核心那张没有刀"
	# 既可能是产品没挂上，也可能是台子根本不渲染 —— 两者分不开。
	var uxi := _body(SuitProfile.xi(), 1, true)
	await _frames(8)
	_orient_and_freeze(uxi)
	if uxi.try_saber(null):
		await _frames(4)
		_freeze_pose(uxi)
		if uxi._blade != null:
			var h2 := _hand_world(uxi)
			g["xi_hand_world"] = _v(h2)
			_mid_pose(uxi, h2 + uxi.forward() * (SuitProfile.xi().saber_blade_front * 0.45))
			await _frames(3)
			await _shot("14_d_xi_on")
			uxi._blade.visible = false
			await _frames(3)
			await _shot("14_d_xi_off")
			uxi._blade.visible = true
		else:
			push_error("SHOT_FAILED(柯西没有刀)")

	_write_geom()
	print("CORE_ARMS_DONE out=%s" % out)
	get_tree().quit(0)


# ------------------------------------------------------------------ 摆位（**探针行为，不是产品行为**）

## 造一台机体。⚠️ `use_placeholder` 是 **static**：显式写 false，
## 保证走的是**真模型真骨**那条路（这是本节 ① 的前置）。
func _body(suit: SuitProfile, team: int, as_player: bool) -> FlightBody:
	FlightBody.use_placeholder = false
	var u := FlightBody.new()
	u.team = team
	u.is_player = as_player
	u.profile = suit
	u.global_position = Vector3(0.0, Y_ALT, 0.0)
	add_child(u)
	return u


## 把机体摆成"朝 −Z、速度 0"并**冻住物理** —— 之后它就是一个位姿已知的静物。
func _orient_and_freeze(u: FlightBody) -> void:
	u.fm.speed = 0.0
	u.fm.throttle = 0.0
	u.fm.velocity = Vector3.ZERO
	u.global_position = Vector3(0.0, Y_ALT, 0.0)
	u.look_at(u.global_position + Vector3(0.0, 0.0, -1.0), Vector3.UP)
	u.set_physics_process(false)


## 冻住挥刀动作（`slash`）—— 手臂不再随时间移动，之后 toggle 刀身才是**唯一**差异。
func _freeze_pose(u: FlightBody) -> void:
	if u.model_anim != null and u.model_anim.player != null:
		u.model_anim.player.speed_scale = 0.0
	if u._blade_anchor != null:
		u._sync_blade_anchor()


func _hand_world(u: FlightBody) -> Vector3:
	if u._model_skel == null:
		return u.global_position
	var idx := u._bone_index("hand_L")
	if idx < 0:
		return u.global_position
	return (u._model_skel.global_transform
		* u._model_skel.get_bone_global_pose(idx)).origin


func _muzzle_world(u: FlightBody) -> Vector3:
	var offs := u.cannon_muzzles()
	if offs.is_empty():
		return u.global_position
	var mid := Vector3.ZERO
	for o: Vector3 in offs:
		mid += o
	return u.global_transform * (mid / float(offs.size()))


func _mid_pose(u: FlightBody, look: Vector3) -> void:
	cam.size = ORTHO_SABER
	_cam_at_side(look, u.forward(), 500.0)


## 相机放到"垂直于机头方向"的一侧（用 `fwd × UP` 当侧向），再抬 `SHIFT` 米，
## 免得机体压在画面正中把刀挡住。
const SHIFT := 0.0
func _cam_at_side(pt: Vector3, fwd: Vector3, dist: float) -> void:
	var side := fwd.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	cam.global_position = pt + side * dist
	cam.look_at(pt, Vector3.UP)
	cam.global_position -= cam.global_transform.basis.y * SHIFT


# ------------------------------------------------------------------ 口径

func _v(v: Vector3) -> String:
	return "%.4f,%.4f,%.4f" % [v.x, v.y, v.z]


func _v2(v: Vector2) -> String:
	return "%.2f,%.2f" % [v.x, v.y]


func _diag(tag: String, note: String) -> void:
	print("DIAG[%s] %s" % [tag, note])
	print("  子视口 size=%s update=%d own_world_3d=%s"
		% [str(sub.size), sub.render_target_update_mode, str(sub.own_world_3d)])
	print("  相机 proj=%d keep_aspect=%d size=%.2f near=%.2f far=%.2f"
		% [cam.projection, cam.keep_aspect, cam.size, cam.near, cam.far])
	var e: Environment = get_world_3d().environment
	print("  环境 = %s bg=%s fog=%s"
		% ["null" if e == null else "ok",
			"?" if e == null else str(e.background_color),
			"?" if e == null else str(e.fog_enabled)])


func _write_geom() -> void:
	var f := FileAccess.open(out.path_join("core_arms_geom.txt"), FileAccess.WRITE)
	if f == null:
		print("GEOM_WRITE_FAILED")
		return
	f.store_line("img_w=%d" % last.x)
	f.store_line("img_h=%d" % last.y)
	f.store_line("view_h=%d" % VIEW_H)
	f.store_line("ortho_saber=%.6f" % ORTHO_SABER)
	f.store_line("ortho_cannon=%.6f" % ORTHO_CANNON)
	f.store_line("wall_m=%.6f" % WALL_M)
	for k in g.keys():
		f.store_line("%s=%s" % [k, g[k]])
	f.close()
	for k in g.keys():
		print("GEOM %s=%s" % [k, g[k]])


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var tex := sub.get_texture()
	if tex == null:
		print("SHOT_FAILED(no texture) %s" % name)
		return
	var img := tex.get_image()
	if img == null:
		print("SHOT_FAILED(no image) %s" % name)
		return
	last = Vector2i(img.get_width(), img.get_height())
	var path := out.path_join("%s.png" % name)
	print("SHOT %s  %dx%d  err=%d" % [path, last.x, last.y, img.save_png(path)])


## 停掉一棵子树里所有粒子发射器。**只停发射不够，还要等寿命跑完**（见调用点）。
## `FX.cannon_muzzle` 造的是**持续发射**的粒子 ⇒ 不停就会一直堆亮云、把差分撑歪。
func _stop_particles(n: Node) -> void:
	for c in n.get_children():
		if c is GPUParticles3D:
			(c as GPUParticles3D).emitting = false
		elif c is CPUParticles3D:
			(c as CPUParticles3D).emitting = false


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
