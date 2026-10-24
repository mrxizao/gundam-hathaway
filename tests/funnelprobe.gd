extends Node
## 浮游导弹「看得见的发射」取证探针（轮 13）。
##
## ## 为什么单独写一个，而不是加进 `pixprobe.gd`
##
## `pixprobe` 的**核心设计**是"开局后立刻 `_freeze()`，一帧游戏逻辑都不许跑" ——
## 那是它可复算的前提（它自己那份注释里记着"跑 40 帧热身导致一整轮无效数据"的代价）。
## 而"导弹从挂架上飞出去"这件事**必须让游戏逻辑跑**（导弹要飞、相机要跟）。
## 两者在架构上直接冲突；硬塞进去会把 pixprobe 的可复算性毁掉。
##
## ## 判据：**相机投影**，不是像素统计
##
## 需求是"看不见 → 看得见"。最直接的可测化是
##
##     `camera.unproject_position(导弹位置)` 落在视口内吗？
##
## 于是本探针输出"开火后第 N 秒，三发导弹各自的屏幕坐标 + 是否在视锥内"。
## 它比像素统计**硬**：像素只能回答"这块亮了没"，而"导弹在不在画面里"是几何事实 ——
## 与画质档位、场景亮度、机型全部无关，也没法被"调亮了"糊弄过去。
##
## ## 用法
##
##     godot --path . res://tests/funnelprobe.tscn -- --tag=A
##     godot --path . res://tests/funnelprobe.tscn -- --tag=B --legacy=1
##
## `--legacy=1` 把刚打出去那几发的 `launch_vel` 清零 = **精确复刻轮 13 之前的行为**
## （导弹不带载机速度）。于是 A/B 两张表就是"看得见 / 看不见"的直接对照。
##
## `--shot=1` 在每个采样点存一张 PNG —— 数字之外的最终判据仍然是眼睛。

const MAIN_SCENE := "res://scenes/main.tscn"
const PROBE_RES := Vector2i(1600, 900)
## 物理帧率。采样点之间的等待按它换算成帧数。
const PHYS_HZ := 60.0
## 采样点（开火后秒数）。
##
## ⚠️ **0.55 是关键样本**：它等于 `Missile.deploy_time`（弹射段结束、导引头刚开始接管），
## 也正是老版里"已经掉出画面"的那一刻。取一堆 0.1 秒的样本不如把这一点取准。
## 0.15 是补在 0.10/0.20 之间的一格 —— 可见窗口就落在那一小段里，
## 采样太疏的话"窗口有多宽"只能靠插值猜。
const SAMPLES: Array[float] = [0.10, 0.15, 0.20, 0.30, 0.55, 1.00]
## 开火时把敌机挪到这么远 —— 太近的话导弹一出膛就进近炸半径，
## 谈不上"看发射"（3 发会在第 1 帧就全炸掉）。
const FOE_RANGE := 2500.0

var _main: Node = null
var _tag := "R13"
var _legacy := false
var _shot := false
var _out := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_args()
	if DisplayServer.get_name() == "headless":
		push_error("funnelprobe 必须真渲染运行 —— 去掉 --headless 再来。")
		get_tree().quit(2)
		return
	await _run()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"--tag":
				_tag = kv[1]
			"--legacy":
				_legacy = int(kv[1]) != 0
			"--shot":
				_shot = int(kv[1]) != 0


func _run() -> void:
	# 与 pixprobe 同一套窗口设置（只设尺寸不切窗口模式的话，
	# 若玩家设置里是全屏，实际拿到的是屏幕原生分辨率）。
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(PROBE_RES)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await get_tree().process_frame
	await get_tree().process_frame

	var ps := load(MAIN_SCENE) as PackedScene
	if ps == null:
		push_error("加载主场景失败：%s" % MAIN_SCENE)
		get_tree().quit(4)
		return
	_main = ps.instantiate()
	add_child(_main)
	for i in 3:
		await get_tree().process_frame

	# 太平洋 + 对战：海港图视野干净（没有城市遮挡），对战模式才有敌机当目标。
	_main._on_start_match(0, 0, MapDef.Id.PACIFIC, Game.MatchMode.VERSUS)
	for i in 5:
		await get_tree().process_frame

	var pc = _main.get("player")
	var foe = _main.get("enemy")
	if pc == null or foe == null:
		push_error("没有玩家或敌机（player=%s enemy=%s）" % [str(pc), str(foe)])
		get_tree().quit(6)
		return

	# ---- 把条件**钉死**（不靠等它自然加速：那样两次跑的时间就不一样了）----
	var boost: float = SuitProfile.penelope().player_boost_speed()
	pc.fm.speed = boost
	pc.fm.align_velocity(pc.forward())
	foe.global_position = pc.global_position + pc.forward() * FOE_RANGE
	pc.funnel_cooldown = 0.0
	pc.funnel_count = maxi(pc.funnel_count, 30)
	for i in 3:
		await get_tree().process_frame

	# ---- 开火 ----
	var fired: bool = pc.fire_funnel(foe)
	var mine: Array = []
	for n: Node in get_tree().get_nodes_in_group("missiles"):
		var m := n as Missile
		if m != null and m.shooter == pc:
			mine.append(m)
			if _legacy:
				m.launch_vel = Vector3.ZERO
	var cam: Camera3D = pc.get("camera")
	print("[funnelprobe] legacy=%s fired=%s 导弹=%d 载机速度=%.0f 相机=%s" % [
		str(_legacy), str(fired), mine.size(), boost,
		"有" if cam != null else "**无**"])

	var rows: Array = []
	var elapsed := 0.0
	for s: float in SAMPLES:
		var need := int(round((s - elapsed) * PHYS_HZ))
		for i in maxi(need, 0):
			await get_tree().physics_frame
		elapsed = s
		rows.append(_sample(pc, cam, mine, s))
		if _shot:
			var img := await _grab()
			if img != null:
				var png := "res://_funnelprobe_%s_%03d.png" % [_tag, int(round(s * 100.0))]
				img.save_png(png)
				print("[funnelprobe] 截图 → %s" % png)

	_out["tag"] = _tag
	_out["stamp"] = Time.get_datetime_string_from_system()
	_out["conditions"] = {
		"map": "pacific",
		"mode": Game.match_mode,
		"legacy_no_inherit": _legacy,
		"carrier_speed": boost,
		"foe_range": FOE_RANGE,
		"inherit_mul": Missile.INHERIT_MUL,
		"inherit_decay_time": Missile.INHERIT_DECAY_TIME,
		"deploy_time": 0.55,
		"resolution": "%d x %d" % [PROBE_RES.x, PROBE_RES.y],
	}
	_out["samples"] = rows
	var f := FileAccess.open("res://_funnelprobe_%s.json" % _tag, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_out, "  "))
		f.close()

	# ---- 控制台表格（人看的那一份）----
	print("")
	print("  开火后(s) | 画面内/总 | 最近一发屏幕坐标 | 距机体(m) | 距相机(m)")
	print("  ----------+-----------+------------------+-----------+----------")
	for r: Dictionary in rows:
		var items: Array = r["items"]
		var near_txt := "(全没了)"
		var dship := -1.0
		var dcam := -1.0
		if not items.is_empty():
			var it: Dictionary = items[0]
			near_txt = "(%.0f, %.0f)" % [it["screen"][0], it["screen"][1]]
			dship = it["dist_to_ship"]
			dcam = it["dist_to_cam"]
		print("  %9.2f |    %d/%d    | %-16s | %9.0f | %8.0f" % [
			r["at"], r["visible"], r["of"], near_txt, dship, dcam])
	print("")
	get_tree().quit(0)


## 一个采样点：三发导弹各自的屏幕位置与可见性。
##
## ⚠️ `unproject_position()` **不能单独用**：对落在相机背后的点它会返回一个
## 看似合理的坐标（投影是齐次除法，背后那个负 w 会被悄悄翻正）。
## 所以可见性判据是 **`is_position_in_frustum()` 且 屏幕坐标落在视口内** —— 两个一起。
func _sample(pc: Node3D, cam: Camera3D, mine: Array, at: float) -> Dictionary:
	var vp := Vector2(1600.0, 900.0)
	if get_viewport() != null:
		vp = get_viewport().get_visible_rect().size
	var cam_pos := Vector3.ZERO
	if cam != null:
		cam_pos = cam.global_position
	var items: Array = []
	var visible_n := 0
	for n in mine:
		if not is_instance_valid(n):
			continue
		var wp: Vector3 = (n as Missile).global_position
		var in_frustum := cam != null and cam.is_position_in_frustum(wp)
		var sp := Vector2.ZERO
		if cam != null:
			sp = cam.unproject_position(wp)
		var on_screen := sp.x >= 0.0 and sp.x < vp.x and sp.y >= 0.0 and sp.y < vp.y
		if in_frustum and on_screen:
			visible_n += 1
		items.append({
			"screen": [snappedf(sp.x, 1.0), snappedf(sp.y, 1.0)],
			"in_frustum": in_frustum,
			"on_screen": on_screen,
			"dist_to_ship": snappedf(wp.distance_to(pc.global_position), 1.0),
			"dist_to_cam": snappedf(wp.distance_to(cam_pos), 1.0),
		})
	return {
		"at": at,
		"visible": visible_n,
		"of": items.size(),
		"ship_pos": [snappedf(pc.global_position.x, 1.0), snappedf(pc.global_position.y, 1.0),
			snappedf(pc.global_position.z, 1.0)],
		"cam_pos": [snappedf(cam_pos.x, 1.0), snappedf(cam_pos.y, 1.0), snappedf(cam_pos.z, 1.0)],
		"items": items,
	}


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null:
		return null
	var tex := vp.get_texture()
	if tex == null:
		return null
	return tex.get_image()
