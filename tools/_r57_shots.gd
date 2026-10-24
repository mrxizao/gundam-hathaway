extends Node
## M04「重力」开场演出的**真机判据图**。
##
## 轮 57 建台；**轮 58（2026-10-01）大改构图**：仓立起来、×2.8、高度 10 000 m、
## 佩涅罗佩改恒距 **9.5 km**、机位改**长焦**（11°）。同时补了**演出结束之后的一拍**
## —— 那是 R5（「演出之后没法继续操控柯西」）的可见判据。
##
## ## 为什么必须是真机图（不能 `--headless`）
## 这一轮交付的东西**全是画面**：运输仓在不在太平洋海面上、HUD 有没有「运输仓」信标、
## 佩涅罗佩有没有从上方压进画面、**光束柱是不是照在仓体上**、切镜后是不是玩家背后视角。
## 无头用 dummy 渲染器 ⇒ **一个像素都不产生**（工程里 `_r53_shots.gd` / `shots_sally.gd`
## 的头注都写着这一条）。
##
## ## 走的是**真入口**，不是探针摆位
## 玩家那条路：注入临时档（M01~M03 通关）→ 战役图选 M04 → 简报页确认
## → `_sortie_campaign("M04")` → `_begin_pod_strike()`。
## 演出**一帧都没快进** —— 按 `_strike_t` 的**自然推进**抓帧（`_tick_pod_strike()` 由
## `_process` 那条真路径驱动）。
##
## ## 跑法
##   godot --path <工程> --resolution 1600x1000 res://tools/_r57_shots.tscn -- <输出目录>
##
## 判据（看图时该问的事，按新构图重写）：
##   ⓪ ★★ 仓**立着**、且**大圆面（推进簇）朝下** —— `01`/`02` 里最容易看出来；
##   ① 仓在**云顶之上**（10 000 m）、下面是完整的宝石环礁与云海，HUD 有
##      「运输仓」信标（仓很大，信标应该贴在它上）；
##   ② 佩涅罗佩在 **9.5 km** 外（长焦 11° 下约 **14 px**）—— 它会很小，
##      靠 HUD 标签辨认；机头朝仓（而不是朝别处）；
##   ③ 光束柱**照在仓体上** —— 这是「必须**显式** `set_aim_direction()`」那条坑的判据
##      （只 `look_at()` 的话柱会射向别处，而且**一处都不报错**）；
##   ④ 仓真的**起火**（柱照上去 1.1 s 之后）；
##   ④b 起火之后它**在往下沉**：`05`（5.8）→ `06`（7.5）→ `07`（7.85，切镜前
##      一帧 = 满值）三张**并排对比**才看得出位移量与趋势；
##   ④c ★ `07_pod_bottom` 是**最坏构图**：沉到最低时有没有压住 HUD 中央区；
##   ⑤ 切镜那一段是**玩家（柯西）背后**的视角（长焦已还回 68°）；
##   ⑥ ★★ **演出结束之后** (`09_…`) —— 这一拍是 R5 的判据。而且光看图不够：
##      同时看日志里的 `AFTER_STRIKE` 与 `AFTER_STRIKE_MOVE` 两行（下面有注）。

const MScript := preload("res://scripts/main.gd")
const CS := preload("res://scripts/data/campaign.gd")

## 本台的临时档（**绝不碰** `user://campaign.cfg`）。
const TMP := "user://campaign_shots_r57.cfg"
const W := 1600
const H := 1000

## 抓帧的时刻（`_strike_t` 秒）与标签。顺序即时间顺序。
## ⚠️ 标签里不再出现 "on_sea"：仓现在在 **10 000 m**（云顶之上），
## 而不是海面上。这一组时刻沿用轮 57（时间线本身没改）。
const SHOTS := [
	[0.6, "01_pod_standing"],
	[2.0, "02_penelope_approach"],
	[3.2, "03_charge"],
	[4.6, "04_beam_on_pod"],
	[5.8, "05_pod_burning"],
	[7.5, "06_pod_sinking"],
	[7.85, "07_pod_bottom"],
	[9.0, "08_cut_to_player"],
]

var main: Node
var out_dir := "user://_r57_shots"
var _i := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(W, H))

	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(45)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(W, H))
	await _frames(10)
	print("display = %s  viewport = %s" % [DisplayServer.get_name(),
		str(get_viewport().get_visible_rect().size)])
	main.set("campaign_save_path", TMP)

	# ---- 造档：M01~M03 通关 ⇒ M04 在战役图上"可出击" ----
	CS.erase(TMP)
	var p := CS.new_progress()
	p["cleared_mask"] = (1 << 3) - 1
	p["chapter"] = 2
	CS.save_progress(p, TMP)

	main.call("_open_campaign", Difficulty.Level.NORMAL)
	await _frames(16)
	main.call("_on_campaign_chosen", "M04")
	await _frames(20)
	print("BRIEF 打开：mission=%s" % str(Game.active_mission.id if Game.active_mission != null else "?"))
	main.call("_on_brief_confirmed")

	# ---- 等演出开始（简报播片 + 建图 + 标题卡都要走完）----
	var guard := 0
	while int(main.get("phase")) != MScript.Phase.POD_STRIKE and guard < 3000:
		guard += 1
		await get_tree().physics_frame
	if guard >= 3000:
		push_error("SHOTS_FAILED(等不到 POD_STRIKE，phase=%d)" % int(main.get("phase")))
		get_tree().quit(1)
		return
	print("POD_STRIKE 开始（等了 %d 物理帧）· chase.externally_stepped=%s"
		% [guard, str(main.get("chase").get("externally_stepped"))])

	# ---- 按 `_strike_t` 的自然推进逐点抓帧 ----
	while _i < SHOTS.size():
		if int(main.get("phase")) != MScript.Phase.POD_STRIKE:
			print("演出提前结束（已抓 %d 张）" % _i)
			break
		var t := float(main.get("_strike_t"))
		if t >= float(SHOTS[_i][0]):
			await _shot(str(SHOTS[_i][1]), t)
			_i += 1
			continue
		await get_tree().physics_frame

	print("抓帧 %d / %d" % [_i, SHOTS.size()])

	# ============================================================ ★ 轮 58：演出**结束之后**
	#
	# R5 的 bug 是「演完之后没法操控柯西」：镜头照切、**看上去演完了**，
	# 可 `_strike_t` 还在跑、`phase` 永远停在 `POD_STRIKE`
	# ⇒ `player.controls_enabled` 永远 false。
	#
	# 所以这一拍**必须出图**，而且还要打两行**可读读数**（判据不靠肉眼）：
	#   · `AFTER_STRIKE`：`phase` 离开 `POD_STRIKE`、`controls_enabled`、
	#     `externally_stepped`、`fov`（应已还回 `base_fov` 68）、当前 BGM；
	#   · `AFTER_STRIKE_MOVE`：**按住油门 1.5 s，速度真的变了**——
	#     「能操控」这件事最终的判据（锁着不给操控时这个数不会动）。
	var g2 := 0
	while int(main.get("phase")) == MScript.Phase.POD_STRIKE and g2 < 3600:
		g2 += 1
		await get_tree().physics_frame
	await _frames(30)
	var ply: Variant = main.get("player")
	var ok_ply: bool = ply != null and is_instance_valid(ply)
	var ctl: bool = ok_ply and bool(ply.get("controls_enabled"))
	var v0 := 0.0
	if ok_ply:
		v0 = (ply.get("velocity") as Vector3).length()
	# ⚠️ 用 `Input.action_press()` 而不是造 `InputEventKey`：后者还要算修正量，
	# 而「按住」这件事 `action_press` 表达得最直接（它写的就是
	# `Input.is_action_pressed()` 的答案）。
	Input.action_press("throttle_up")
	await _frames(90)
	var v1 := 0.0
	if ok_ply:
		v1 = (ply.get("velocity") as Vector3).length()
	Input.action_release("throttle_up")
	print("AFTER_STRIKE  phase=%d  controls_enabled=%s  externally_stepped=%s  fov=%.1f  bgm=%s"
		% [int(main.get("phase")), str(ctl),
		   str(main.get("chase").get("externally_stepped")),
		   float(main.get("chase").get("fov")), Audio.current_bgm_track()])
	print("AFTER_STRIKE_MOVE  按住油门 1.5 s：speed %.1f -> %.1f  %s"
		% [v0, v1, "变了" if v1 > v0 + 1.0 else "**没变 ⇒ 操控没交还**"])
	await _shot("09_after_strike_controllable", float(main.get("_strike_t")))

	CS.erase(TMP)
	print("SHOTS done -> %s" % out_dir)
	get_tree().quit(0)


func _shot(tag: String, t: float) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, tag]
	var err := img.save_png(path)
	var foe: Variant = main.get("_strike_foe")
	var beam: Variant = main.get("_strike_beam")
	print("SHOT %s  %dx%d  err=%d  t=%.2f  foe=%s  beam=%s"
		% [path, img.get_width(), img.get_height(), err, t,
			"有" if (foe != null and is_instance_valid(foe)) else "无",
			"在" if (beam != null and is_instance_valid(beam)) else "无"])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
