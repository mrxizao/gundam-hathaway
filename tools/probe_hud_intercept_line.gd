extends Node
## 归因探针：用户报的「艾尔斯岩地表绿线」= HUD 的**已拦截连线**（`hud.gd:1289`）。
##
## ## 为什么怀疑是 HUD
## 直接量用户截图（171×537）那条线的像素：**RGB(30,32,22)**，周围地表 RGB(15,3,0)。
## 而 HUD 调色板的 `HUD = Color(0.58, 1.0, 0.74)`（青绿）以 **alpha 0.20**
##（`hud.gd:1289` 的字面量）混到红棕地面上，算出来是 **(28,28,19)** —— 几乎逐位吻合。
## 地形那边算不出这个值：`VEG_COLOR` 走夜色增益 (0.30,0.45,0.92) 之后是 (15,24,19)，
## 色相比（G>B>R）与实测的 (G>R>B) 对不上。
##
## 那条线本身的几何也吻合：`hud.gd:1255` 的 `me_px` 默认取
## **`Vector2(size.x * 0.5, size.y * 0.92)`**（画面中央偏下），
## 再 `draw_line(me_px, mp, ...)` 拉到那枚飞弹 ⇒ 永远是"从画面中央斜着拉出去的一条线"，
## 且 `UILayout.LINE_HAIR` 是**固定像素宽**的 ⇒ 解释了用户量到的"宽度恒定"。
##
## ## 判据：A/B 两张图，唯一变量是 `engaged`
##   A `01_threat_only`：威胁缓存里有那枚来袭弹，但**没有任何弹咬着它**
##      ⇒ 应有菱形威胁框 + "TTI 2.5 s"，**不应有青线**
##   B `02_engaged_line`：给另一枚弹写上 `intercept_target = 那枚来袭弹`
##      ⇒ `Interceptor.engaged_targets()` 认出它 ⇒ **多出那条青线**
## 两张图只差这一个字段 ⇒ 青线的成因被隔离到 `hud.gd:1289` 这一行。
##
## ## 跑法（⚠️ **不能加 `--headless`**）
##   Godot_v4.7.1-stable_win64_console.exe --path . res://tools/probe_hud_intercept_line.tscn \
##       -- <输出目录>

const MAIN_SCENE := "res://scenes/main.tscn"
const SHOT_W := 1600
const SHOT_H := 900

var _main: Node = null
var _out := "user://probe_hud_line"
var _c: Node3D = null
var _foe: Missile = null
var _killer: Missile = null


func _ready() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	print("[hl] 输出目录 = ", _out)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await get_tree().process_frame
	await get_tree().process_frame

	var ps := load(MAIN_SCENE) as PackedScene
	if ps == null:
		push_error("[hl] 加载主场景失败")
		get_tree().quit(4)
		return
	_main = ps.instantiate()
	add_child(_main)
	for i in 3:
		await get_tree().process_frame

	_main._on_start_match(0, 0, MapDef.Id.ULURU, Game.MatchMode.VERSUS)
	for i in 20:
		await get_tree().process_frame

	var player: Node3D = _main.player
	if player == null:
		push_error("[hl] player 为空")
		get_tree().quit(5)
		return

	# ---- 造两枚弹：一枚"来袭"，一枚当"咬住它的拦截弹"----
	# ⚠️ 都 `set_physics_process(false)`：探针要的是**静止的构图**，
	# 让它们飞起来只会让两张图的构图不一致（那是 A/B 里最脏的一种变量）。
	# ⚠️ 位置取"玩家正前方 + 略抬"：这样 HUD 的威胁框与那条连线都落在画面里
	# （`_visible()` 为假的威胁会被 `hud.gd:1261` 直接跳过，那时 A/B 双双无信号）。
	_c = Node3D.new()
	_c.name = "ProbeMissiles"
	add_child(_c)
	var fwd: Vector3 = player.call("forward")
	var up := Vector3.UP
	_foe = Missile.new()
	_c.add_child(_foe)
	_foe.global_position = player.global_position + fwd * 3000.0 + up * 500.0
	_foe.set_physics_process(false)
	_killer = Missile.new()
	_c.add_child(_killer)
	_killer.global_position = player.global_position + fwd * 1800.0 + up * 900.0
	_killer.set_physics_process(false)
	for i in 4:
		await get_tree().process_frame

	print("[hl] foe 在 missiles 组 = %s，killer = %s"
		% [_foe.is_in_group("missiles"), _killer.is_in_group("missiles")])
	print("[hl] engaged_targets（应只有 killer 咬住后才非空）= %s"
		% str(Interceptor.engaged_targets(player)))

	# ---- 冻结：停逻辑（`_tick_threats()` 每物理帧会重刷缓存，不冻就被覆盖掉）----
	# ⚠️ **不要**像 pixprobe 那样藏 `canvas` —— 本探针要看的正是 HUD 自己。
	get_tree().paused = true

	# ---- 相机：玩家机后上方（`hud.gd:1255` 的 `me_px` 会取机体的屏幕投影）----
	var chase: Camera3D = _main.chase
	chase.set_target(null)
	chase.set_physics_process(false)
	chase.set_process(false)
	var b: Basis = player.global_transform.basis
	chase.global_position = player.global_position + b * Vector3(0.0, 9.0, 53.0)
	chase.look_at(player.global_position + b * Vector3(0.0, 2.6, 0.0), b.y)
	chase.fov = 62.0
	chase.far = 200000.0
	chase.current = true

	# ---- 手写威胁缓存（冻结之后不会被 tick 覆盖）----
	# 结构照 `player_controller.gd:1303`：`Interceptor.rank_threats()` 的返回表。
	player.set("_threats_cache", [{"missile": _foe, "tti": 2.5}])
	player.set("_threat_index", 0)

	print("[hl] ================ 出图 ================")
	# ---- A：没有任何弹咬着 foe ----
	_killer.intercept_target = null
	print("[hl] A 组：killer.intercept_target = null ⇒ engaged_targets() 应为空")
	await _shot("01_threat_only")
	# ---- B：唯一变量 —— 给 killer 写上 intercept_target ----
	_killer.intercept_target = _foe
	print("[hl] B 组：killer.intercept_target = <foe> ⇒ engaged_targets() 应含 foe")
	await _shot("02_engaged_line")
	get_tree().quit(0)


## 重画 HUD 再抓帧。
##
## ⚠️ **必须显式 `queue_redraw()`**：`paused = true` 之后 HUD 的 `_process` 不再跑，
## 没有任何东西会触发重绘（实测：不调这一行的话两张图逐位相同，
## 而日志、文件名、结束码全都正常 —— 又一个"探针在骗人"）。
func _shot(name: String) -> void:
	var hud: CanvasItem = _main.hud
	hud.queue_redraw()
	for i in 8:
		await RenderingServer.frame_post_draw
	hud.queue_redraw()
	for i in 4:
		await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	if tex == null:
		print("[hl] ⚠️ 取不到视口纹理：", name)
		return
	var img := tex.get_image()
	if img == null:
		print("[hl] ⚠️ 取不到画面：", name)
		return
	img.convert(Image.FORMAT_RGB8)
	var p := _out.path_join(name + ".png")
	img.save_png(p)
	print("[hl] shot %s -> %s" % [name, p])
