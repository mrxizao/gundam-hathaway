extends Node
## 轮 55 真机探针：M03「接货」= **零敌机 + 飞到柯西收纳仓 0.6 km 内即判胜**。
##
## 老板原话：「接货这一关不要设置敌人，将机体靠近柯西收纳仓 0.6 km 内就可以视作任务成功」
##
## ## 为什么要**真起一局**而不是只跑纯函数判据
##
## 纯函数判据（`suite_campaign` 那 11 条）钉的是"分派对了没"，
## 而这一轮真正新增的是一条**运行时链**：
##   `main._tick_mission_zones()`（每帧）→ 写 `Game.zone_reached`
##   → `Game._end_state()["zones"]` → `Objective.done()` 的 REACH 分支
##   → `Game._evaluate_end()` → `set_phase(WIN)`
## 这条链上每一环都可能"名字对、没人调"：`_evaluate_end()` **全工程没有周期性调用者**
## （唯一触发点是 `notify_destroyed()`）—— 也就是说，如果 `main` 那边忘了主动
## `recheck_end()`，"飞到了"这件事**永远不会结算**，而且**一处都不报错**。
## ⇒ 只有真起一局、真把机体挪进去、再看 `Game.phase`，才能证明它**整条通**。
##
## ## 两组读数（互为负对照）
##
##   · 放在 **800 m**（球外）⇒ 不许判胜（证明"判胜不是开局就成立"）；
##   · 放在 **550 m**（球内）⇒ 判胜（证明"是那一个球在做功"）。
##   两个距离都**用 `Zone.clearance()` 量的**（同一套几何），不是手算的欧氏距离。
##
## 跑法：
##   无头（只取读数）: godot --headless --path <工程> res://tools/_m03_reach_probe.tscn
##   出图（**不能加 `--headless`**）: godot --path <工程> res://tools/_m03_reach_probe.tscn -- <输出目录>

const MS := preload("res://scripts/data/mission_script.gd")
const WB := preload("res://scripts/world/world_builder.gd")
# ⚠️ `Campaign` **不是 autoload**（project.godot 的 [autoload] 只有 InputSetup / Settings /
# Audio / Game / Net）⇒ 直接写 `Campaign.xxx` 会报 `Identifier "Campaign" not declared`。
# 工程惯例就是这条 `CS` 别名（main.gd / campaign_map.gd / mission_brief.gd / suite_campaign.gd 一致）。
const CS := preload("res://scripts/data/campaign.gd")

## 两次摆放的距离（球心到机体的**距离**，米）。半径 600 ⇒ 800 在外 / 550 在内。
const D_OUT := 800.0
const D_IN := 550.0

var out := "user://m03_reach"
var main: Node
var _idx := 0
var _want_shots := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
		_want_shots = true
	DirAccess.make_dir_recursive_absolute(out)

	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	if _want_shots:
		DisplayServer.window_set_size(Vector2i(1600, 900))
	await _frames(45)

	await _run()

	print("M03_REACH_DONE -> %s" % out)
	get_tree().quit(0)


func _run() -> void:
	# 存档隔离：`_resolve_campaign_match()` 会读 `Game.campaign_progress`。
	Game.campaign_progress = _all_cleared()
	if not bool(main.call("_resolve_campaign_match", "M03")):
		print("[M03] ★ _resolve_campaign_match 返回 false（关卡被拦）")
		return
	main.call("_launch_match")
	await _frames(60)

	var pl = main.get("player")
	if pl == null or not is_instance_valid(pl):
		print("[M03] ★ player 没起来")
		return
	var m: MS.Mission = Game.active_mission
	if m == null:
		print("[M03] ★ active_mission 为空")
		return

	# ---------------------------------------------------------------- ① 静态读数
	var zone: MS.Zone = m.zone("orbit_cargo")
	var pod := WB.SPACE_POD_POS
	print("[M03] mission=%s 《%s》 player=%s" % [m.id, m.title, str(pl.profile.id_name())])
	print("[M03] has_enemies=%-5s  wave_count=%d  total_enemies=%d  win_on_clear=%s"
		% [str(m.has_enemies()), m.wave_count(), m.total_enemies(), str(m.win_on_clear)])
	print("[M03] 目标：%s  kind=%s  target=%s"
		% [str(m.objectives[0].label), MS.Objective.kind_name(m.objectives[0].kind),
			str(m.objectives[0].target)])
	print("[M03] zone=%s  shape=%s  center=%s  radius=%.1f m  use=%s"
		% [str(zone.id), zone.shape_name(), str(zone.center), zone.outer_radius(), zone.use_name()])
	print("[M03] 建图运输仓 SPACE_POD_POS=%s  （球心与它逐位相同 = %s）"
		% [str(pod), str(zone.center == pod)])

	# 场上到底有几台敌对单位 —— **数一遍**，别只信 `has_enemies()`。
	var foes := _count_enemies(pl)
	print("[M03] ★ 场上敌对单位 = %d 台（玩家 = 1 台，其余全算敌/友）" % foes)
	print("[M03] phase=%s（开局，玩家离接收点 %.1f m）"
		% [str(Game.phase), (pl.global_position - pod).length()])

	if _want_shots:
		_idx += 1
		await _shot("%02d_M03_spawn" % _idx)

	# ---------------------------------------------------------------- ② 球外 800 m
	await _place(pl, pod, D_OUT, m)
	print("[M03] --- 球外对照 ---")
	print("[M03] 距离=%.1f m  clearance=%.1f（<0 即在球外）  zone_reached=%s  phase=%s"
		% [(pl.global_position - pod).length(), zone.clearance(pl.global_position),
			str(Game.zone_reached.get(zone.id, false)), str(Game.phase)])

	# ---------------------------------------------------------------- ③ 球内 550 m
	await _place(pl, pod, D_IN, m)
	print("[M03] --- 球内 ---")
	print("[M03] fps=%.1f（真机渲染重 ⇒ `_process` 的帧率**不等于** physics 的 60 Hz）"
		% Engine.get_frames_per_second())
	print("[M03] 距离=%.1f m  clearance=%.1f（>0 即在球内）  zone_reached=%s  phase=%s"
		% [(pl.global_position - pod).length(), zone.clearance(pl.global_position),
			str(Game.zone_reached.get(zone.id, false)), str(Game.phase)])
	print("[M03] ★ 判胜 = %s（期望 true）" % str(Game.phase == Game.Phase.WIN))

	if _want_shots:
		_idx += 1
		await _shot("%02d_M03_at_%dm" % [_idx, int(D_IN)])
		# 侧视：看运输仓与机体（**关 HUD / 摘 current** 那套老规矩）
		var keep := _pod_cam(pl, pod)
		await _frames(6)
		_reaim_pod(keep, pl, pod)
		await _frames(1)
		_idx += 1
		await _shot("%02d_M03_pod_side" % _idx)
		_restore_cams(keep)


## 把机体摆在离球心 `dist` 米处（方向取"当前所在的水平方位"，没有就取 +X）。
##
## ⚠️ 摆放之后**等 `_settle()`**（不是等 physics 帧）—— 见 `_settle()` 那段：
## Zone 检测挂在 `main._process()`，只等 physics 帧会在**真机低帧率**下读到假红。
## 同时 `FlightBody` 自己有积分步进，读数必须是"跑过几帧之后的真实位置"。
func _place(pl, pod: Vector3, dist: float, m: MS.Mission) -> void:
	var dir: Vector3 = pod - pl.global_position
	dir.y = 0.0
	if dir.length() < 1.0:
		dir = Vector3.RIGHT
	dir = dir.normalized()
	pl.global_position = pod + dir * dist
	# 让机体朝向球心（顺手也让相机看得到目标）
	var look: Vector3 = pod - pl.global_position
	if look.length() > 1.0:
		pl.look_at(pod, Vector3.UP)
	await _settle(3)


func _count_enemies(pl) -> int:
	var root: Node = main.get("units_root")
	if root == null or not is_instance_valid(root):
		return -1
	var n := 0
	for u in root.get_children():
		if u == pl or not (u is FlightBody):
			continue
		if u.profile == null:
			continue
		if u.is_hostile_to(pl):
			n += 1
	return n


func _all_cleared() -> Dictionary:
	# ⚠️ 必须用**真形状** `Campaign.new_progress()` —— 它带 `cleared_mask` / `best_reward` /
	# `chapter` / `upgrades` 这些键。曾经手搓成 `{"cleared": {...}, "credits": 99999}`：
	# 形状不对 ⇒ `Campaign.settle()` 读 `p["best_reward"]` 直接抛
	#   SCRIPT ERROR: Invalid access to property or key 'best_reward' on ... 'Dictionary'
	# **运行期 SCRIPT ERROR 不进 PASS/FAIL 账** ⇒ 只在日志里冒两条，非常容易漏看。
	# 关号**不写死**：拿 `MASK_ORDER` 的长度算掩码，任务表增删时这里自动跟上。
	var p: Dictionary = CS.new_progress()
	var n := CS.MASK_ORDER.size()
	p["cleared_mask"] = (1 << n) - 1
	p["credits"] = 999999
	# 自证：这份假档**真的**是"全通"，而不是我以为的全通。
	# ⚠️ 用显式 if + print，**不用 `assert`** —— GDScript 的 `assert` 是**函数**（必须带括号），
	# 而且一旦失败会**中断函数**、让 `get_tree().quit(0)` 永不执行 ⇒ **进程挂死**。
	var n_clear := CS.cleared_count(p)
	print("[M03] 假档：MASK_ORDER=%d 关  cleared_count=%d  credits_of=%d  %s"
		% [n, n_clear, CS.credits_of(p), "OK" if n_clear == n else "★ 没造成全通"])
	return p


## 摆一台"看着运输仓"的相机（**遍历摘 current + 关 HUD**）。
## ⚠️ 诊断机位挂在**机体**下（不是世界坐标）——机体会飞，挂世界坐标几帧就被甩出画面。
func _pod_cam(pl, pod: Vector3) -> Dictionary:
	var keep := {"cams": [], "hud": null, "pl": pl, "pod": pod}
	for c in main.find_children("*", "Camera3D", true, false):
		if c is Camera3D:
			keep["cams"].append({"cam": c, "cur": (c as Camera3D).current})
			(c as Camera3D).current = false
	var hud = main.get("hud")
	if hud != null and is_instance_valid(hud):
		keep["hud"] = hud
		hud.visible = false
	var cam := Camera3D.new()
	cam.name = "M03PodCam"
	cam.fov = 45.0
	main.add_child(cam)
	var key := DirectionalLight3D.new()
	key.name = "M03Key"
	key.light_energy = 1.2
	key.shadow_enabled = false
	key.light_specular = 0.0
	cam.add_child(key)
	keep["mine"] = cam
	return keep


func _reaim_pod(keep: Dictionary, pl, pod: Vector3) -> void:
	var cam = keep.get("mine")
	if cam == null or not is_instance_valid(cam):
		print("[pod] REAIM_FAILED")
		return
	# ★ 机位要沿**垂直于连线**的方向退避，⛔ 不是沿连线退避。
	#   沿连线退避时，相机若落在"机体与中点之间"，一回头机体就在**身后**了——
	#   轮 55 实测：`mid + away * 130` 得到 cam→pl 与 cam→mid 夹角 **139°**，
	#   图上只剩运输仓（机体 0 像素）。而"看不见"这件事**不会报错**。
	var dir: Vector3 = (pl.global_position - pod)
	dir.y = 0.0
	if dir.length() < 1.0:
		dir = Vector3.RIGHT
	dir = dir.normalized()
	var side: Vector3 = Vector3.UP.cross(dir)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var mid: Vector3 = (pl.global_position + pod) * 0.5
	var span: float = (pl.global_position - pod).length()
	# 退避距离按**两者间距**缩放：fov 45°、16:9 下要框住 span 米，侧向距离约需 span × 0.95。
	var back: float = maxf(240.0, span * 0.95)
	cam.global_position = mid + side * back + Vector3.UP * (span * 0.28)
	cam.look_at(mid, Vector3.UP)
	cam.current = true
	# ★ 自证读数：夹角 < 90° ⇒ 机体真的在相机前方（不是身后）。
	#   这条比"图看着对"强 —— 它是一个**数**，能变红。
	var to_pl: Vector3 = (pl.global_position - cam.global_position)
	var to_mid: Vector3 = (mid - cam.global_position)
	var ang: float = rad_to_deg(to_pl.angle_to(to_mid))
	print("[pod] cam=%s  cur_cam_now=%s  pl=%s  pod=%s"
		% [str(cam.global_position), str(get_viewport().get_camera_3d()),
			str(pl.global_position), str(pod)])
	print("[pod] span=%.1f m  back=%.1f m  cam→pl 与 cam→mid 夹角 = %.1f°（< 90° ⇒ 两者都在相机前方）%s"
		% [span, back, ang, "OK" if ang < 90.0 else "★ 机体在相机身后"])


func _restore_cams(keep: Dictionary) -> void:
	var cam = keep.get("mine")
	if cam != null and is_instance_valid(cam):
		cam.queue_free()
	for e in keep.get("cams", []):
		if e["cam"] != null and is_instance_valid(e["cam"]):
			(e["cam"] as Camera3D).current = e["cur"]
	var hud = keep.get("hud")
	if hud != null and is_instance_valid(hud):
		hud.visible = true


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null:
		print("SHOT_FAILED(no viewport) ", name)
		return
	var img := vp.get_texture().get_image() if vp.get_texture() != null else null
	if img == null:
		print("SHOT_FAILED(no image) ", name)
		return
	var path := out.path_join("%s.png" % name)
	print("SHOT %s  %dx%d  err=%d"
		% [path, img.get_width(), img.get_height(), img.save_png(path)])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## 同时等 **process 帧** 与 **physics 帧** —— Godot 里这是**两个独立时钟**。
##
## ⚠️ 本探针栽过一次，而且**只在真机（带窗口、2560x1600）才暴露**：
## `_place()` 原本只 `await _frames(2)`（= 2 个 **physics** 帧），而 Zone 进入检测挂在
## `main._process()` 里。真机渲染重 ⇒ `_process` 帧率可以远低于 physics 的 60 Hz ⇒
## **2 个 physics 帧里可能一个 process 帧都没有** ⇒ 检测压根没跑 ⇒ 读到 `phase=2`
## —— 看着像"产品没判胜"，其实是**探针没等够**。无头下渲染几乎免费 ⇒ 帧率极高 ⇒
## **把这个坑完全盖住了**（同一份代码，两种读数）。
## ⇒ 判据：凡"要等某条挂在 `_process` 的逻辑跑过"，就必须**等 process 帧**。
func _settle(n: int) -> void:
	for i in n:
		await get_tree().process_frame
		await get_tree().physics_frame
