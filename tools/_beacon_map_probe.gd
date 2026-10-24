extends Node
## 2026-10-01 真机探针：**只读信标按关显示**。
##
## 老板原话：
## > 「**运输仓只在 M04 和 M03 加进来就好了，其他时候就不要标在地图里**」
## > 「包括**迪拜塔 M01 的标记，不要在 M02 加进来**」
##
## ## 为什么必须出图
##
## 这条改动的**全部内容**就是"屏幕上那个框有没有画出来" ——
## 源码扫描最多证明"调了闸门"，证明不了"框真的没了"。
##
## 更要紧的是：**判别器是"同一张图、换一关"**。
## M01 / M02 用的是**同一张达沃图**（`m01().arena == m02().arena == "DAVAO"`），
## 纯数据判据测不出这件事 —— 而改前的 bug 恰恰就是"按图判"：
## 只要达沃图上建了酒店信标节点，M02 也跟着画。
##
## ## 一组三张图（A / B / C）
##
## | # | `Game.active_mission` | 应当 |
## |---|---|---|
## | A | `M01`（夜袭达沃） | 塔尖顶一个**红框** + 「内阁成员所在酒店  x.x km」 |
## | B | **`M02`**（同一张图、同一个机位） | **没有框** |
## | C | `null`（对战 / 挑战 / 训练 / LAN 那一类） | **没有框** |
##
## B、C 两张与 A **只差一个字段**，机位 / 地图 / 机体一个字都没动 ⇒
## 图上的差异只可能来自那一个字段。
##
## ## 判据（能变红，不靠肉眼）
##
## 数**信标投影点周围 ±150 px 窗口**里 `FlightHUD.DANGER` 色
##（`Color(1, 0.3, 0.26)` = RGB 255/76/66，容差 ±24）的像素：
##
## | | 窗口内红像素 | 实测 |
## |---|---|---|
## | A | **> 500** | **1373** |
## | B | **≤ 80** | **13** |
## | C | **≤ 80** | **9 ~ 18** |
## | A / max(B, C) | **≥ 10** | **76 ~ 105** |
##
## ⚠️⚠️ **两个坑，都实测踩过**：
##
## ① **不能按"全帧"判**：全帧里 B / C 有 1213 / 1303 个红 —— 画面上本来就有别的红、
##    恒在且与信标无关（左上「导弹警报：拦截（右键·拦截飞弹）」、右下那一列武器键位图例、
##    中下「挑战 夜袭达沃 无敌人」）。⇒ 判据必须收到信标自己那一小块。
## ② **也不能写成"B / C 恰好为 0"**：窗口里永远有**塔自己那颗红色航空顶灯**
##    （`_city_needle_tower()` 针尖那颗；窗口跟着信标投影走 ⇒ 它恒在窗口内），
##    亮度还随**自动曝光**浮动（实测 13 ~ 18）。⇒ 量出这个**本底**、给上限、
##    再用**倍数**兜底。写成 `== 0` 会**恒红**，那是判据的错，不是产品的错。
##
## ⚠️ 窗口坐标要过 `_proj_img()`：`hud._project()` 给的是**设计空间**，
## 而真机出图是 2560×1600（`window_set_size` 在本机不生效）。
##
## ## 跑法
##   出图（**不能加 `--headless`**）: godot --path <工程> res://tools/_beacon_map_probe.tscn -- <输出目录>
##   只取读数（无头也行，但出不了图）: godot --headless --path <工程> res://tools/_beacon_map_probe.tscn

const MS := preload("res://scripts/data/mission_script.gd")
const WB := preload("res://scripts/world/world_builder.gd")
const CS := preload("res://scripts/data/campaign.gd")

## 信标那个红（`hud.gd` 的 `DANGER`）。判据就数它的像素。
const DANGER_RGB := Color(1.0, 0.30, 0.26)

## 判据用的**方形窗口**半边长（图片像素），以信标投影点为中心。
##
## 够大：框本身最大 `half = 44 + 13 = 57 px`（设计空间，×1.6 = 91 px），
## 框下那行字在 `+ half + 30` 再往下、字高约 13 → 折合不到 **150 px**。
const WIN_HALF := 150

## 判据阈值（**实测值**，2026-10-01）：
##   · A（M01）窗口内红 = **1373** ⇒ 门槛 500 留了 2.7 倍余量；
##   · B / C 窗口内红 = **13 / 9 ~ 18** ⇒ 上限 80。
##
## ⚠️ B / C 那十几个红**不是信标** —— 那是**塔自己那颗红色航空顶灯**
##（`_city_needle_tower()` 针尖上那颗，注释写着"4900 m 高的塔尖在真实世界里
## 必须是红色航空障碍灯"）。窗口跟着信标投影走 ⇒ 那颗顶灯**永远在窗口里**；
## 而它的亮度随**自动曝光**变（实测 B 13 / C 18），所以数不是常数。
## ⚠️ 于是判据**不能**写成"B / C 恰好为 0" —— 它会**恒红**，
## 那是判据的错，不是产品的错。⇒ 量出这个**本底**、给上限，再用**倍数**兜底
##（A 至少是本底的 10 倍，实测 76~105 倍）。
const A_MIN := 500
const NOISE_MAX := 80
const A_RATIO := 10.0

var out := "user://beacon_map"
var main: Node
var _want_shots := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
		_want_shots = true
	DirAccess.make_dir_recursive_absolute(out)

	# ⚠️ 看门狗：带窗口跑的时候，`_ready()` 里任何一处抛错都会**静默中断协程**，
	# 于是 `get_tree().quit()` 永远到不了 —— 进程挂死、日志停在一半。
	# （本工程踩过；无头下反而看不出问题。）
	var wd := Timer.new()
	wd.wait_time = 180.0
	wd.one_shot = true
	wd.autostart = true
	wd.timeout.connect(func() -> void:
		print("BEACON_MAP_WATCHDOG_TIMEOUT（180 s 没跑完，强制退出）")
		get_tree().quit(2))
	add_child(wd)

	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	if _want_shots:
		DisplayServer.window_set_size(Vector2i(1600, 900))
	await _frames(45)

	await _run()

	print("BEACON_MAP_DONE -> %s" % out)
	get_tree().quit(0)


func _run() -> void:
	# ---- ⓪ 纯数据表：七关 × 两条信标（**不出图也能读**）----
	_data_table()

	# ---- 起一局 M01 ----
	# ⚠️ 存档隔离：`_resolve_campaign_match()` 会读 `Game.campaign_progress`，
	# 没通关的档会把 M01 直接拦住（探针挂在"关卡被拦"上，而不是挂在被测的东西上）。
	Game.campaign_progress = _all_cleared()
	if not bool(main.call("_resolve_campaign_match", "M01")):
		print("[beacon] ★ `_resolve_campaign_match(\"M01\")` 返回 false（关卡被拦）")
		return
	main.call("_launch_match")
	await _frames(60)

	var pl = main.get("player")
	if pl == null or not is_instance_valid(pl):
		print("[beacon] ★ player 没起来")
		return
	var hud: Node = main.get("hud")
	if hud == null or not is_instance_valid(hud):
		print("[beacon] ★ hud 没起来")
		return

	var tag := _first(WB.HOTEL_TAG_GROUP)
	if tag == null:
		print("[beacon] ★ 达沃图上找不到酒店信标节点（%s）" % WB.HOTEL_TAG_GROUP)
		return
	var at := (tag as Node3D).global_position
	print("[beacon] 地图=%s  信标组=%s  节点=%s"
		% [str(Game.active_map.id), WB.HOTEL_TAG_GROUP, str((tag as Node3D).name)])
	print("[beacon] 酒店信标位置=%s" % str(at))

	# ---- 把机体摆到"看得见塔"的地方 ----
	# 塔顶 ~8.4 km ⇒ 机体摆在**同一高度带**上，既不触发拉起告警
	#（`PULL_UP_ALTITUDE = 420`）、也让塔与信标都进画面。
	pl.global_position = at + Vector3(-2600.0, -500.0, -2600.0)
	pl.look_at(at, Vector3.UP)
	await _settle(4)
	print("[beacon] 机体=%s  离信标 %.0f m  敌机 %d 台"
		% [str(pl.global_position), pl.global_position.distance_to(at), _count_enemies(pl)])

	# ---- A / B / C ----
	var rA: Array = await _case("A", "M01", MS.by_id("M01"), pl, hud, at)
	var rB: Array = await _case("B", "M02", MS.by_id("M02"), pl, hud, at)
	var rC: Array = await _case("C", "null", null, pl, hud, at)

	var a := int(rA[0])
	var b := int(rB[0])
	var c := int(rC[0])
	var noise := maxi(b, c)
	print("[beacon] ================= 判据汇总 =================")
	print("[beacon] A(M01)=%d  B(M02)=%d  C(null)=%d   本底=max(B,C)=%d"
		% [a, b, c, noise])
	print("[beacon] ① A > %d            → %s（%d）" % [A_MIN, _yn(a > A_MIN), a])
	print("[beacon] ② B ≤ %d            → %s（%d）" % [NOISE_MAX, _yn(b <= NOISE_MAX), b])
	print("[beacon] ③ C ≤ %d            → %s（%d）" % [NOISE_MAX, _yn(c <= NOISE_MAX), c])
	print("[beacon] ④ A ≥ %.0f × 本底    → %s（倍数 %.1f）"
		% [A_RATIO, _yn(float(a) >= A_RATIO * float(maxi(noise, 1))),
			float(a) / float(maxi(noise, 1))])
	# ⚠️ `_beacon_shown()` 三条也要一起看 —— 像素那三条证明"画面上有没有"，
	# 这三条证明"HUD 认的是哪一关"（两者分家才是最难查的那种）。
	print("[beacon] ⑤ _beacon_shown：A=true B=false C=false → %s"
		% _yn(bool(rA[1]) and not bool(rB[1]) and not bool(rC[1])))

	# 收尾：把这一局还原成它本来该有的样子（免得日志后半段是假状态）。
	Game.active_mission = MS.by_id("M01")


## 一次"换关卡 → 等两帧 → 数红 → 出图"。返回 `[窗口内红像素, _beacon_shown]`。
func _case(tag: String, label: String, m, pl, hud, at: Vector3) -> Array:
	Game.active_mission = m
	await _settle(2)

	var shown := false
	if hud.has_method("_beacon_shown"):
		shown = bool(hud.call("_beacon_shown", WB.HOTEL_TAG_GROUP))
	var want := label == "M01"

	var vp := get_viewport()
	var img: Image = null
	if vp != null and vp.get_texture() != null:
		img = vp.get_texture().get_image()

	# 信标在**屏幕**上的位置（用 HUD 自己那套投影 —— 见 `_proj_img()`）。
	var visible := bool(hud.call("_visible", at))
	var p := _proj_img(hud, at, img)

	var red := -1
	var loose := -1
	var full := -1
	if img != null:
		var rc := _red_count_in(img, p, WIN_HALF)
		red = int(rc[0])
		loose = int(rc[1])
		full = int(_red_count_in(img, Vector2(-1.0, -1.0), -1)[0])

	print("[beacon] ---- %s: active_mission = %s ----" % [tag, label])
	print("[beacon] %s  `_beacon_shown(酒店)` = %s（期望 %s）%s"
		% [tag, str(shown), str(want), "" if shown == want else "  ★ 不符"])
	print("[beacon] %s  在视野内 = %s   投影 = (%d, %d)   窗口 = ±%d px"
		% [tag, str(visible), int(p.x), int(p.y), WIN_HALF])
	print("[beacon] %s  窗口内 DANGER 像素 = %d（期望 %s）%s   [宽松红判 = %d]"
		% [tag, red,
			("> %d" % A_MIN) if want else ("≤ %d" % NOISE_MAX),
			"" if ((red > A_MIN) if want else (red <= NOISE_MAX)) else "  ★ 不符",
			loose])
	print("[beacon] %s  （对照：全帧 %d 个 —— 那些是键位图例之类的别的红，与信标无关）"
		% [tag, full])

	if _want_shots:
		var name := "%s_%s_hotel_frame" % [tag, label.to_lower()]
		await _shot(name)
	return [red, shown]


## `true` / `false` 的短写法，只给日志用。
func _yn(v: bool) -> String:
	return "OK" if v else "★ 不符"


## 七关 × 两条信标要不要标。**与 `suite_landmark._gate()` 同一份判据**，
## 印在这里是为了让交付日志自带那张表（不用翻套件源码）。
func _data_table() -> void:
	print("[beacon] ---- 纯数据：七关 × 两条信标 ----")
	print("[beacon] %-6s %-14s %-14s" % ["关", "酒店(hotel_target)", "运输仓(pod_target)"])
	for m: MS.Mission in MS.all():
		print("[beacon] %-6s %-16s %-16s" % [
			m.id,
			("标" if m.shows_beacon(WB.HOTEL_TAG_GROUP) else "不标"),
			("标" if m.shows_beacon(WB.POD_TAG_GROUP) else "不标")])
	for fm: MS.Mission in MS.free_all():
		print("[beacon] %-6s %-16s %-16s（自由遭遇）" % [
			fm.id,
			("标" if fm.shows_beacon(WB.HOTEL_TAG_GROUP) else "不标"),
			("标" if fm.shows_beacon(WB.POD_TAG_GROUP) else "不标")])


# ============================================================ 工具
## **全帧**里等于 `DANGER` 的像素数。返回 `[严格数, 宽松数]`。
##
## ⚠️ **只用来做对照读数**（交付日志里那条"全帧有多少红"）——**判据不用它**。
## 判据走 `_red_count_in()` 的信标局部窗口，理由见文件头那段（全帧恒有别的红）。
##
## ⚠️ 逐字节走 `get_data()`，不逐像素调 `get_pixel()`：后者在 2560×1600 上
## 一次要十几秒（真机窗口尺寸被引擎忽略，见工作区笔记），会把探针拖过看门狗。
func _red_count() -> Array:
	var vp := get_viewport()
	if vp == null or vp.get_texture() == null:
		return [-1, -1]
	return _red_count_in(vp.get_texture().get_image(), Vector2(-1.0, -1.0), -1)


## 数 `img` 里等于 `DANGER` 的像素。
##
## `half < 0` ⇒ **全帧**；否则只数以 `p` 为中心、边长 `2 * half` 的**正方形窗口**。
##
## ⚠️ 窗口坐标是**图片像素**，而 `hud._project()` 给的是**设计空间**（1600×1000）——
## 真机窗口尺寸被引擎忽略、实际出图 2560×1600 ⇒ 必须先过 `_proj_img()` 乘那个 `k`。
func _red_count_in(img: Image, p: Vector2, half: int) -> Array:
	if img == null:
		return [-1, -1]
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var x0 := 0
	var x1 := w - 1
	var y0 := 0
	var y1 := h - 1
	if half > 0:
		x0 = maxi(0, int(p.x) - half)
		x1 = mini(w - 1, int(p.x) + half)
		y0 = maxi(0, int(p.y) - half)
		y1 = mini(h - 1, int(p.y) + half)
	# ⚠️ `Color8()` 给的是 **0..1** 的分量，拿它跟 0..255 的字节比 ⇒ 恒 0 命中。
	# 这里一律化成 0..255 的整数再比。
	var wr := int(round(DANGER_RGB.r * 255.0))
	var wg := int(round(DANGER_RGB.g * 255.0))
	var wb := int(round(DANGER_RGB.b * 255.0))
	var strict := 0
	var loose := 0
	var data := img.get_data()
	for y in range(y0, y1 + 1):
		var base := y * w * 4
		for x in range(x0, x1 + 1):
			var i := base + x * 4
			var r := data[i]
			var g := data[i + 1]
			var b := data[i + 2]
			if absi(r - wr) <= 24 and absi(g - wg) <= 24 and absi(b - wb) <= 24:
				strict += 1
			if r >= 150 and g <= 130 and b <= 130:
				loose += 1
	return [strict, loose]


## 世界点 → **图片像素**坐标。
##
## ⚠️ 不是恒 1.6：`DisplayServer.window_set_size()` 在本机**不生效**（探针图恒 2560×1600），
## 而 `hud._project()` 给的是 HUD 自己的设计空间 ⇒ 两轴分别缩一次；
## 将来那条"窗口尺寸不生效"被修掉，这里会**自动跟上**（而不是硬编码 1.6 悄悄画歪）。
func _proj_img(hud: Node, at: Vector3, img: Image) -> Vector2:
	var p: Vector2 = hud.call("_project", at)
	if img == null:
		return p
	var hs: Vector2 = hud.size
	if hs.x <= 1.0 or hs.y <= 1.0:
		return p
	return Vector2(p.x * float(img.get_width()) / hs.x,
		p.y * float(img.get_height()) / hs.y)


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


func _first(group: String) -> Node:
	for n in get_tree().get_nodes_in_group(group):
		if is_instance_valid(n):
			return n
	return null


func _all_cleared() -> Dictionary:
	# ⚠️ 必须用**真形状** `Campaign.new_progress()`（见 `_m03_reach_probe` 那段教训：
	# 手搓成 `{"cleared": …}` 会让 `Campaign.settle()` 抛运行期 SCRIPT ERROR，
	# 而**运行期 SCRIPT ERROR 不进 PASS/FAIL 账**）。
	var p: Dictionary = CS.new_progress()
	var n := CS.MASK_ORDER.size()
	p["cleared_mask"] = (1 << n) - 1
	p["credits"] = 999999
	print("[beacon] 假档：MASK_ORDER=%d 关  cleared=%d  %s"
		% [n, CS.cleared_count(p), "OK" if CS.cleared_count(p) == n else "★ 没造成全通"])
	return p


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null or vp.get_texture() == null:
		print("SHOT_FAILED(no viewport) ", name)
		return
	var img := vp.get_texture().get_image()
	if img == null:
		print("SHOT_FAILED(no image) ", name)
		return
	var path := out.path_join("%s.png" % name)
	print("SHOT %s  %dx%d  err=%d"
		% [path, img.get_width(), img.get_height(), img.save_png(path)])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## 同时等 **process 帧** 与 **physics 帧**（两个独立时钟，见 `_m03_reach_probe`）。
func _settle(n: int) -> void:
	for i in n:
		await get_tree().process_frame
		await get_tree().physics_frame
