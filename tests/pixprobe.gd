extends Node
## 画质**像素统计探针**（1.2.3 批 A / 方案 §5.2）。
##
## ## 为什么需要它
## 画质改动在无头回归里**零信号** —— headless 的 RenderingServer 是 dummy，
## shader 根本不编译、`_draw()` 不产生像素。于是"改了到底生效没有、生效了多少"
## 这一段没有任何自动化手段（`tests/test_runner.gd` 里的 5200 多条断言一条都管不着）。
##
## 本工具补的就是这一段：**真渲染**跑一局固定的战斗，把画面量化成一组可复算的数。
##
## ## 它能做什么 / 不能做什么（⚠️ 必须写在这里，防止后人当它是"画质自动化验收"）
##   ✔ 证明"metallic 从 0 改到 0.45 之后，机体区高光占比从 X% 变成 Y%"
##   ✔ 证明"体积雾开之后天空亮度分布变了多少"、"这一项花了多少毫秒 / 多少 draw call"
##   ✘ **不能证明"更好看"** —— 观感只有人眼能判。本工具只做 A/B，不做审美判决。
##
## ## 基线的脆弱性（方案 §5.2 已写）
## 像素统计的基线**只要渲染代码一改就失效**。所以它只适合"改动前后对比（A/B）"，
## **不适合做永久阈值断言** —— 这与逻辑回归（写死数字的门）本质不同，必须分开存放：
## 逻辑门在 `tests/suite_*.gd`（进回归链），本工具的基线在它输出的 JSON 里（不进回归链，
## 见方案 §9 #7：它需要真渲染，进 CI 只会让回归变慢且测不到东西）。
##
## ## 跑法（**不能加 `--headless`**，加了拿不到图）
##   Godot_v4.7.1-stable_win64_console.exe --path <工程目录> res://tests/pixprobe.tscn \
##       -- --tag=before [--tod=night] [--map=pacific] [--frames=24]
##
## ## 固定条件（可复算的前提，方案 §5.2 第 1 条"决定性"）
## 地图 / 时段 / 机型 / 对手 / 分辨率 / 机位偏移 / 渲染帧数 **全部固定**。
## 机位用**相对玩家机体的定长偏移**（而不是世界坐标）—— 这样即使出生点漂了，
## 构图仍然一致；机体朝向由 `_place()` 的 `look_at` 决定，也是确定的。
##
## ## 输出
##   ① `res://_pixprobe_<tag>.json`（完整数据，供 A/B 对比）
##   ② stdout 上的一行摘要（人眼看结论用）

const MAIN_SCENE := "res://scenes/main.tscn"
## 与 `ChaseCamera.offset` 同款的后上方跟随偏移。探针不改它 ——
## 用**玩家实际看到的那个机位**来测，测出来的才是玩家看到的画质。
const CAM_OFFSET := Vector3(0.0, 9.0, 53.0)
const CAM_LOOK_UP := 2.6
const CAM_FOV := 62.0
## 动画时钟的默认钉值（秒）。**任何**一张图都钉在同一个值上 ⇒ 两张不同参数的图
## 之间也只剩"参数"这一个变量（批 J）。想要别的相位用 `--animtime=<秒>`。
const ANIM_PIN := 50.0
## 固定渲染分辨率。工程基准 1600×900（`project.godot`），探针跟着走。
const PROBE_RES := Vector2i(1600, 900)
## 冻结后空转这么多帧再采样：建图 / 材质 / 云的实例化、shader 编译、后处理链都要时间，
## 第一帧必然是半成品（实测过：不等帧的话贴图还是灰的）。
## Vulkan 的管线缓存是冷启动 —— 不等帧直接采样，第一帧能到 300+ ms（那是 shader 编译，
## 不是特效开销），帧时间表就全废了。40 帧在 600 fps 下只有 ~70 ms，可以忽略。
##
## ⚠️ **空转不能用"跑游戏逻辑帧"**：那会让机位漂（见 `_run()` 里的血泪注释）。
## 冻结之后的 `frame_post_draw` 空转同样把管线烘热，但**一帧游戏逻辑都不跑**。
const WARMUP_FRAMES := 40
## 帧时间测多少帧。604 fps 下 60 帧只要 100 ms —— 帧数给足才能压掉抖动。
const TIME_FRAMES := 60
## 直方图分组数。16 组足够看出"色带变少"（组与组之间出现空档 = 有台阶）。
const HIST_BINS := 16
## 边缘密度的高频算子阈值（亮度差）。0.06 是"肉眼能看出这条边"的量级。
const EDGE_THRESHOLD := 0.06
## 「高光」与「暗部」的亮度门。0.85 用于金属高光占比（方案 §2.2 的判据）。
const HL_LUM := 0.85
const DARK_LUM := 0.15

var _main: Node = null
var _tag := "run"
var _warmup := WARMUP_FRAMES
var _map := "pacific"
var _tod := ""          # "" = 用地图自带时段
## 可选：给一份基线 JSON 的相对路径（`res://...`），跑完附一张 A/B 差异表。
## 这是方案 §5.2 要的"与基线对比、输出差异表"，也是本工具的主要用法。
var _baseline := ""
## 机位覆盖（`--bodycam=<米>`，轮 23）。
##
## ⚠️ **为什么必须有它**：默认机位（`CAM_OFFSET`）是"玩家视角"的后上方偏移，
## 它**经常完全拍不到玩家机体**（达沃夜战实测：画面里只有俯瞰的城市，
## 机体不在视野内 —— 掩码图上根本找不到机体那一块）。
## 于是「场景增益不动机体」这条 —— 本工具**本该能回答**的问题 ——
## 用默认机位根本验不了，而结果看上去毫无异常（两张图照样出一堆差值、
## 照样能写出一张"看起来很有说服力"的表）。
##
## >0 = 把相机放到机体正**后方**这个距离（米），抬头比例与 `CAM_OFFSET` 相同
## ⇒ 机体占满画面，任何"机体像素被动了"都会在差分图上直接现身。
## 0 = 默认机位（**零回归**：不传这个参数时行为与从前逐位相同）。
var _bodycam := 0.0
## 画质项**运行时覆盖**（见 `_apply_overrides()`）。键 → 值都是字符串，直接来自命令行。
##
## 为什么要它：A/B 对比不该靠"来回改工程代码再跑两次" —— 那样中间态会掺进来
##（改了一半、忘了改回来、Godot 又重导入一次资源…），而且两次跑的工程状态不同就没法归因。
## 现在改成：**同一份工程代码**，用参数把某一项单独拧回去，一次跑出 A/B。
var _overrides := {}
var _out := {}
## 存图增益（`--gain`）。先存这里、等 `conditions` 建好再写进 JSON ——
## 在那里直接写 `_out["conditions"]` 会**键不存在崩掉整个 `_run()`**（试过一次）。
var _shot_gain := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_args()
	if DisplayServer.get_name() == "headless":
		push_error("pixprobe 必须真渲染运行 —— 去掉 --headless 再来。")
		get_tree().quit(2)
		return
	await _run()


## 用户参数（`--` 之后的那些）。没给就是固定默认值 —— 默认值本身构成基线条件。
func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"--tag": _tag = kv[1]
			"--frames": _warmup = maxi(int(kv[1]), 4)
			"--map": _map = kv[1]
			"--tod": _tod = kv[1]
			"--baseline": _baseline = kv[1]
			# 机位覆盖（轮 23）：把相机拉到机体正后方，保证机体在画面里。
			"--bodycam": _bodycam = maxf(float(kv[1]), 0.0)
			# 画质项覆盖：--msaa=2 / --deband=0 / --adjust=0 / --glowlevels=0
			# 1.2.3 批 E/G 新增：--detail=0 / --sss=0 / --cloudsun=0 / --facade=0
			# 以及 --sunaz=<度>（**只转云的主光方向**，不动太阳本身，见 `_apply_overrides`）
			# 与 --lookmoon=1（把相机摆成**逆光**，见那里的血泪注释）
			"--msaa", "--deband", "--adjust", "--glowlevels", \
			"--detail", "--sss", "--cloudsun", "--facade", "--sunaz", "--lookmoon", \
			"--fadefar", "--citycam", "--shot", "--gain", "--aim", "--waves", "--seacam", \
			"--shoal", "--matblend", "--ripple", "--veg", "--topcam", \
			"--mottle", "--mottlelen", "--mist", "--misttop", "--mistfall", \
			"--mistemit", "--misted", "--mistspan", "--animtime", "--foglen", "--fogspread", \
			"--seafade", "--amb", "--sunpow", \
			"--cel", "--ambsrc", "--ambcol", "--skycon", "--amben", "--pitch", "--yaw", \
			"--postmix", "--steps", "--postsatin", "--skyproc", "--skyrad", "--postinten", \
			"--celpaint", "--celprio", "--celshape", "--celoff", "--celz", \
			"--trees", "--aimoasis", "--lift", "--bands", "--portlights", "--porten", "--portshadow", \
			"--scenegain", "--seaboost":
				_overrides[kv[0].substr(2)] = kv[1]


func _run() -> void:
	# ⚠️ 必须**同时**切窗口模式与尺寸：只设尺寸的话，若玩家设置里是全屏
	#（`Settings.fullscreen`），窗口仍是全屏 —— 实测第一次跑拿到的是 **2560×1600**
	#（笔记本屏的原生分辨率），而不是探针要的 1600×900。
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(PROBE_RES)
	# ⚠️ **关掉 vsync 与限帧**：测帧时间必须这样做，否则量到的是"刷新率"而不是"这一项特效的开销"
	#（实测：开 vsync 时 `TIME_FPS` 恒为 3、`TIME_PROCESS` 恒为 297 ms，两组采样一字不差 ——
	#  那是节流，不是渲染成本）。
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
	# autoload 与 3D 世界就绪
	for i in 3:
		await get_tree().process_frame

	# ---- 开一局（走**同步**入口，与测试同一路径；不走读条那条协程，探针要确定性）----
	# 参数：机体 / 难度 / 地图 / 模式 / 对手
	#   0 = 佩涅罗佩（玩家的默认机，也是骨骼槽位表的原型机）
	#   0 = NORMAL 难度；对手 -1 = 自动挑（对战模式挑"另一台"）
	#
	# ⚠️⚠️ **靶场必须用训练模式**（实测撞出来的第二个"探针在骗人"的坑）：
	# `main.gd:302` 写着「靶场是训练专用图，别的模式选到它时**回退到群岛**」。
	# 第一轮用 VERSUS 跑 `--map=range`，实际渲染的是**太平洋图**，而探针在 `conditions`
	# 里照抄了自己请求的那个名字（`"map": "range"`）—— 于是两张完全不同的地图
	# 给出了**逐位相同**的像素统计（`full.mean_lum` 都是 0.03720），
	# 而报告读起来毫无异常。**"记录的条件"必须等于"实际发生的条件"**，否则 A/B 是假的。
	var mode := Game.MatchMode.TRAINING if _map_id() == MapDef.Id.RANGE \
		else Game.MatchMode.VERSUS
	# ---- 场景亮度增益 `--scenegain=<倍>`（轮 12）----
	#
	# ⚠️⚠️ **必须在开图这一步之前注入**，所以它**不能**放进 `_apply_overrides()`：
	# `world_builder` 的材质是在 `apply_map()` 里把颜色算死的（`_sg()` 只在建材质时
	# 乘一次），而 `_apply_overrides()` 跑在 `_freeze()` 之后（第 174 行）= 建图之后。
	# 放那儿的表现是**画面纹丝不动、也不报错** —— 会被读成"这一项没有效果"，
	# 与本工程"探针在骗人"那些坑是同一个形状。
	if _overrides.has("scenegain") and _main.get("world") != null:
		var sg := maxf(float(_overrides["scenegain"]), 0.0)
		_main.world.scene_gain = sg
		print("[pixprobe] 场景增益 ×%.3f（在建图之前注入）" % sg)
	# `--seaboost=<倍>`：海面在场景增益之上的**补偿倍率**（见 `SEA_GAIN_BOOST` 的说明）。
	# ⚠️ 零回归要用 `--scenegain=1 --seaboost=1` **两个一起**给：只给前者的话海面
	# 仍被乘 1.8，拿不到"与基线逐字节相同"这个判据。
	if _overrides.has("seaboost") and _main.get("world") != null:
		var sb := maxf(float(_overrides["seaboost"]), 0.0)
		_main.world.sea_boost = sb
		print("[pixprobe] 海面补偿 ×%.3f（在建图之前注入）" % sb)
	_main._on_start_match(0, 0, _map_id(), mode)
	if _tod != "":
		_main.world.apply_map(_build_map_with_tod())

	# ⚠️⚠️ **当场冻结，一帧游戏逻辑都不许跑**（这条是实测撞出来的，代价是一整轮无效数据）：
	# 原来的写法是先让游戏自由跑 40 帧"热身"，结果**画面不可复算** ——
	# 那 40 帧里玩家机体在飞（`_place()` 给了 260 m/s），而两次跑的温度/帧率不同
	#（747 fps vs 343 fps）⇒ 40 帧覆盖的**时间**不同 ⇒ 机体飞的距离不同 ⇒
	# 冻结时的机位不同 ⇒ 两次 `full.mean_lum` 直接差了 18%，下半屏甚至从"有内容"变成"全黑"。
	# 那份 A/B 表看起来"改动效果巨大"，其实全是机位漂移。
	# **渲染管线的热身不需要跑游戏逻辑** —— 下面用 `frame_post_draw` 空转即等效。
	_freeze()
	_apply_overrides()
	for i in _warmup:
		await RenderingServer.frame_post_draw

	# ---- 采样 ----
	var ft := await _frame_metrics()
	var img := await _grab()
	if img == null:
		push_error("取画面失败（get_viewport().get_texture().get_image() 返回空）")
		get_tree().quit(5)
		return
	# ---- 存 PNG（`--shot=1`）：**画质的最终判据是眼睛，不是均值** ----
	#
	# ⚠️ 为什么必须有这一条（本轮第三次栽在"数字看着很干净、结论却是错的"上）：
	# 均值/stddev/直方图只能回答"变了多少"，**回答不了"变成什么样了"**。
	# 实测撞到的具体例子：`--citycam=300` 的整帧 `mean_lum = 0.0032` ——
	#   · 光看数字，那是"几乎全黑"，会顺手写成"这一档没测到东西"；
	#   · 看图才知道是**相机贴在一面不反光的墙前**（构图问题，不是画质问题）。
	# 两个结论的下一步动作完全相反，而数字分不开它们。
	# 存图几乎不花代价，就该默认开着（`--shot=1`）。
	if _overrides.has("shot") and int(_overrides["shot"]) != 0:
		var png := "res://_pixprobe_%s.png" % _tag
		# `--gain=<倍>`：**只提亮存出来的 PNG，不动统计口径**。
		# 理由：本工程有一张"阴天黄昏的死城"（oenbelli），实拍整帧 `mean_lum` 只有 0.003 量级 ——
		# 直接存出来是一块黑，**肉眼判不了结构**，会误判成"这一档没测到东西"。
		# 增益必须**记录进 conditions**，否则后人会拿一张 ×8 的图去和别人 ×1 的图比较。
		var shot := img
		var gain := 1.0
		if _overrides.has("gain"):
			gain = maxf(float(_overrides["gain"]), 0.0)
			if not is_equal_approx(gain, 1.0):
				shot = img.duplicate() as Image
				shot.adjust_bcs(gain, 1.0, 1.0)
		var err := shot.save_png(png)
		# ⚠️ **不能在这里写 `_out["conditions"]`**：`conditions` 是在后面（`_out` 组装那段）
		# 才建的，这里它还不存在 ⇒ `Invalid access to property or key 'conditions'`，
		# 而这个错误在 `-> void` 的函数里**直接中断 `_run()`** ——
		# 现场表现是"PNG 存出来了、日志却停在 `Godot Engine v...`"，看起来像没跑。
		# 所以改成先存在成员变量里，等 `conditions` 建好再一起写进去。
		_shot_gain = snappedf(gain, 0.01)
		print("[pixprobe] 截图 → %s (err=%d, %d×%d, 增益 ×%s)" % [
			png, err, shot.get_width(), shot.get_height(), str(gain)])
	# 「平时那样跑」的帧时间（含 HUD 与游戏逻辑）放在**取完图之后**再测 ——
	# 那时画面已经进 JSON 了，解冻不会污染任何已采到的数。
	var ft_live := await _frame_metrics_live()

	_out["tag"] = _tag
	_out["stamp"] = Time.get_datetime_string_from_system()
	# ⚠️ **条件是"实际建出来的那张图"，不是命令行请求的那张**。
	# 请求值也留着（`requested_*`）—— 两者不一致就必须在表里看得见，
	# 因为"请求靶场、实际拿到群岛"这种事**不会报任何错**，只会让 A/B 变成假的。
	var act := Game.active_map
	_out["conditions"] = {
		"map": act.code.to_lower() if act != null else "?",
		"map_id": act.id if act != null else -1,
		"requested_map": _map,
		"requested_map_id": _map_id(),
		"map_matches_request": act != null and act.id == _map_id(),
		"tod": _tod if _tod != "" else "(地图自带)",
		"tod_deg": str(act.time_of_day.sun_rotation_deg) if act != null else "?",
		"suit": 0,
		"mode": Game.match_mode,
		"resolution": "%d x %d" % [img.get_width(), img.get_height()],
		"requested_resolution": "%d x %d" % [PROBE_RES.x, PROBE_RES.y],
		"viewport_visible_rect": str(get_viewport().get_visible_rect().size),
		"warmup_frames": _warmup,
		"overrides": _overrides,
		"window_mode": DisplayServer.window_get_mode(),
		"window_focused": get_window() != null and get_window().has_focus(),
		# 存图增益（`--gain`）。**必须记**：一张 ×3 的图和一张 ×1 的图长得完全不同，
		# 后人拿它们对比就会得出"这批改动把画面提亮了 3 倍"这种荒唐结论。
		"shot_gain": _shot_gain,
		# 场景亮度增益（`--scenegain`，轮 12）。**必须记** —— 与 `shot_gain` 逐字同一个道理：
		# 一张"场景 ×1.4"的图和一张"场景 ×1.0"的图，整帧均值差着一大截，
		# 后人拿它们做 A/B 会把"提亮的效果"读成"这一轮改动把画面弄亮了"。
		"scene_gain": _main.world.scene_gain if _main.get("world") != null else 1.0,
		# 海面补偿倍率（`--seaboost`）。与 `scene_gain` **分开记**：海面最终拿到的是
		# 两者的乘积，只记一个的话 A/B 复算不出来海面当时到底是几档。
		"sea_boost": _main.world.sea_boost if _main.get("world") != null else 1.0,
		# 机位覆盖（`--bodycam`）。**必须记**：默认机位与近距机位拍的是两个不同的构图，
		# 拿"近距机位"的统计去和"默认机位"的旧基线比，差的全是机位、不是这次改动。
		"bodycam": _bodycam,
	}
	_out["render_config"] = _render_config()
	# `frame_time` = **冻结后的稳态**，探针的一切对比都以它为基准（可复算）。
	# `frame_time_live` = 平时那样跑（含 HUD 那层 2D），取完图之后才测，只作参考。
	_out["frame_time"] = ft
	_out["frame_time_live"] = ft_live
	_out["regions"] = _all_regions(img)
	_out["shade_mats"] = _shade_mat_report()
	# 世界材质的**实况**（1.2.3 批 E/G）：这一节存在的唯一理由是——
	# "改了 uniform"与"那个 uniform 到达了真正在画的材质"是两件事。
	# 第一轮实测：`--sss=0` 改完之后画面**逐字节不变**，光看像素表分不清
	# "这一项在数学上恒为 0"与"这个开关没接到材质上"（两者都长成一片 `+0.0000`）。
	# 所以把材质里的实际值也写进 JSON：A/B 的每一格都能回溯到"当时材质是什么状态"。
	_out["world_mats"] = _world_mat_report()
	_out["hud"] = {"player_hp": _num(_main.player, "hp"), "enemy_present": _main.enemy != null}
	if _baseline != "":
		_out["diff_vs_baseline"] = _diff_against(_baseline)

	var json := JSON.stringify(_out, "  ")
	var path := "res://_pixprobe_%s.json" % _tag
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(json)
		f.close()
		print("[pixprobe] 已写出 %s" % path)
	else:
		push_warning("写 %s 失败（res:// 不可写？）—— 完整数据只留在 stdout" % path)
	print("[pixprobe] ==== SUMMARY tag=%s ====" % _tag)
	var wm: Dictionary = _out.get("world_mats", {})
	var oc: Dictionary = wm.get("ocean", {}) if wm.get("ocean") is Dictionary else {}
	print("[pixprobe] 条件: 实际地图=%s(请求 %s, 一致=%s) 模式=%s 时段=%s" % [
		str(_out["conditions"].get("map")), str(_out["conditions"].get("requested_map")),
		str(_out["conditions"].get("map_matches_request")),
		str(_out["conditions"].get("mode")), str(_out["conditions"].get("tod"))])
	print("[pixprobe] 材质实况: 地表 %s 份 / 云 %s 带 / 立面 %s 份；海面 crest_sss=%s moon_dir=%s view·moon=%s" % [
		str(wm.get("terrain_count")), str(wm.get("cloud_count")), str(wm.get("facade_count")),
		str(oc.get("crest_sss")), str(oc.get("moon_dir")), str(oc.get("view_dot_moon"))])
	# 立面是否可读**只看这一行**：`out_count` 等于总数就说明"关掉立面"在数学上没差，
	# 那 A/B 表上的 +0.0000 是距离造成的，不是接线断了。
	var fd: Dictionary = wm.get("facade_dist", {}) if wm.get("facade_dist") is Dictionary else {}
	if not fd.is_empty():
		print("[pixprobe] 立面距离: %s 栋 %s~%s m（中位 %s）；淡出 %s→%s；近/中/外=%s/%s/%s mean_near_f=%s ⇒ %s" % [
			str(fd.get("count")), str(fd.get("min")), str(fd.get("max")), str(fd.get("median")),
			str(fd.get("fade_near")), str(fd.get("fade_far")),
			str(fd.get("in_count")), str(fd.get("mid_count")), str(fd.get("out_count")),
			str(fd.get("mean_near_f")), str(fd.get("verdict"))])
	print(json)
	print("[pixprobe] ==== END ====")
	get_tree().quit(0)


# ============================================================ 固定条件

func _map_id() -> int:
	match _map:
		"uluru": return MapDef.Id.ULURU
		"oenbelli": return MapDef.Id.OENBELLI
		# ⚠️ 1.3 批 M 新加：达沃（夜袭的活港都）。**必须在这里登记**，
		# 否则 `--map=davao` 会静默回落到太平洋图 —— 探针照样出一张图、
		# 判据照样跑，只是拍的是另一张地图（第 156 行那条血泪注释记的就是这件事）。
		"davao": return MapDef.Id.DAVAO
		"range": return MapDef.Id.RANGE
		# ⚠️ 剧情模式轮 B2 新加：低地球轨道（M03 接货那一关）。**同样必须在这里登记**，
		# 理由与上面达沃那条逐字相同 —— 不登记就静默回落太平洋图，而报告里写的还是
		# `"map": "leo"`。轨道图与太平洋图在像素上**天差地别**（一个近黑满是星点、
		# 一个蓝到发白），所以这次回落会被肉眼抓住；但登记这件事**不能靠肉眼兜**。
		"leo": return MapDef.Id.LEO
	return MapDef.Id.PACIFIC


## 覆盖时段用的地图副本（探针专用：只改 time_of_day，其余照抄）。
func _build_map_with_tod() -> MapDef:
	var m := MapDef.by_id(_map_id())
	var preset := TimeOfDay.Preset.NIGHT
	match _tod:
		"day": preset = TimeOfDay.Preset.DAY
		"dusk": preset = TimeOfDay.Preset.DUSK
	m.time_of_day = TimeOfDay.make(preset)
	return m


## 冻结画面：暂停全树（物理/脚本停，渲染继续）+ 关掉 HUD 层 + 把相机钉在固定机位。
##
## ⚠️ 顺序：**先摆相机再暂停没用**（`_physics_process` 会在暂停前再跑一次），
## 所以先 `paused = true` 再摆位。
func _freeze() -> void:
	var tree := get_tree()
	tree.paused = true
	# HUD 是 CanvasLayer，画在 3D 之上 —— 留着它统计到的"机体区"会混进仪表
	if _main.canvas != null:
		_main.canvas.visible = false
	var chase: Camera3D = _main.chase
	if chase == null or _main.player == null:
		return
	chase.set_target(null)
	chase.set_physics_process(false)
	chase.set_process(false)
	var p: Vector3 = _main.player.global_position
	var b: Basis = _main.player.global_transform.basis
	# 与 ChaseCamera 同款的相对偏移（机体坐标系）—— 出生点漂了构图也一样
	# 机位：默认是玩家视角的后上方偏移；`--bodycam` 把它拉到机体正后方近处 ——
	# ⚠️ 默认机位**常常拍不到机体**，那时"场景增益不动机体"根本无从验证
	#（两张图照样出差值、照样能写出表）。见 `_bodycam` 的说明。
	var off := CAM_OFFSET
	if _bodycam > 0.0:
		off = Vector3(0.0, _bodycam * (CAM_OFFSET.y / CAM_OFFSET.z), _bodycam)
	chase.global_position = p + b * off
	chase.look_at(p + b * Vector3(0.0, CAM_LOOK_UP, 0.0), b.y)
	chase.fov = CAM_FOV
	chase.current = true
	if _bodycam > 0.0:
		print("[pixprobe] 机位：机体正后方 %.1f m（--bodycam，默认机位常常拍不到机体）" % _bodycam)


## 画质项的**运行时覆盖** —— 这是本工具能做 A/B 的关键（见 `_overrides` 的理由）。
##
## 每个参数都把某一项"拧回去"，拧到哪就是哪，**工程代码一个字不动**：
##   `--msaa=<0..3>`       视口 MSAA（0=关 / 1=2× / 2=4× / 3=8×）
##   `--deband=<0|1>`      视口去色带
##   `--adjust=<0|1>`      Environment 的色彩分级
##   `--glowlevels=0`      把辉光分层还原成**引擎默认**（2/3/4 = 0.8/0.4/0.1，其余 0）
##   `--detail=0`          地表细节（法线扰动 + 颗粒）**全关**（批 E）
##   `--sss=0`             海面浪尖透光**关**（批 E）
##   `--cloudsun=0`        云的主光方向受光**关**（退回"只有上亮下暗"，批 E）
##   `--facade=0`          城市楼体立面**关**（退回 1.2 的纯色楼体，批 G）
##   `--sunaz=<度>`        **只**把云的主光方位转到这个角度（不动太阳本身）——
##                         用来直接回答"云到底有没有按主光方向受光"：
##                         同一机位、同一时段，只改这一个方位，云区的亮度分布
##                         要是**一点不变**，那这一项就没生效（旧口径必然如此）。
##   `--fadefar=<米>`      把城市立面的**淡出远端**拉到这个距离（`facade_fade_far`）。
##                         只改远端、不动近端 —— 用来回答"立面是**被淡出吃掉**了，
##                         还是**根本没接到楼体上**"（见 `_apply_overrides` 里的说明）。
##   `--citycam=<米>`      把相机搬到**离玩家最近的一栋楼**前方这个距离上看它。
##                         ⚠️ **测城市近景细节必须用这个**（理由见 `_apply_overrides`）。
##   `--aim=<前缀>:<米>`   把相机搬到**世界里名字以该前缀开头的节点**前方这个距离
##                         上看它（例：`--aim=FujiSphere:1200`）。
##                         用来回答"画面上那个东西到底是什么"—— 它同时也是
##                         **画质最终判据（眼睛）**的取证手段：像素统计能证明
##                         "这里有变化"，只有一张特写能证明"这个变化是对的"。
##   `--pitch=<度>`        **配合 `--aim`** 改机位仰角（默认 ≈ +9.6°，即 `CAM_OFFSET`）。
##                         `0` = 与目标等高、水平看；负角 = 降到目标之下；
##                         大正角 = 俯视目标顶面。夹在 ±89°（90° 会让 `look_at` 翻转）。
##   `--yaw=<度>`          **配合 `--aim`** 改机位方位角。默认 `0` = 从 +Z 侧看；
##                         `-90` = 从 -X 侧看，`+90` = 从 +X 侧看。
##                         ⚠️ **"走进一条通道"必须靠 pitch+yaw**：默认那个
##                         "+Z 侧、+9.6° 仰角"是从上后方看一栋楼的构图，
##                         站在几公里外斜看永远答不了"机体能不能从这条缝里飞过去"；
##                         而"门框在哪儿"还可能整体**不在 +Z 那一侧**
##                        （港区龙门吊的两条腿是沿 X 分开的）。
##                         ⚠️ 两个角一起夹在 ±89°；都不给时行为与旧版**逐位相同**。
##   ⚠️ `--aim` 的坐标对 `MultiMeshInstance3D` 取的是**实例质心**（那些节点的
##      `global_position` 恒为 (0,0,0)，直接拿会静默把相机搬到世界原点）。
##   `--portlights=0|1`    港区泛光灯（`PortFloodLights`，6 颗 `OmniLight3D`）**开关**。
##                         这是**归因**旋钮：关掉之后画面还剩下多少亮度，
##                         就是"环境光 + 自发光"贡献的总量。
##                         ⚠️ 与全城其他灯火不同，这一批是**真光源**（会照亮货柜
##                         与码头面）；判断"堆场黑"是"没光"还是"材质吃掉光"，
##                         全靠这一个开关。
##   `--porten=<能量>`     **只**改那 6 颗灯的 `light_energy`（射程/颜色不动）。
##                         这是**剂量表**旋钮：一次运行扫多档就能定下常量，
##                         不必"改一次 `CITY_PORT_FLOOD_ENERGY` 重跑一次"。
##                         ⚠️ 4800 m 射程下 `Light3D` 的衰减既不是 1/d² 也不是线性，
##                         **预算不出应该填多少** —— 只能量。
##   `--portshadow=0|1`    **只**改那 6 颗灯的 `shadow_enabled`。判据是
##                         `frame_time.wall_ms_per_frame`（真实开销）＋画面。
##                         ⚠️ **问完的答案是「不要开」**（轮 7 实测，三机位 A/B）：
##                         平均亮度 **−18.5 / −7.5 / −16.5**、变化像素 64%/27%/41%
##                         —— 堆场整片掉黑、近景出 shadow acne；而开销只有
##                         `wall_ms` +0.03~0.05 ms。原因是**几何**：灯只比自己的
##                         悬臂高 24 m，360 m 悬臂投到地面被放大 ≈27 倍。
##                         完整推导见 `world_builder.gd` 的 `shadow_enabled` 处。
##                         ⚠️ `draw_calls` / `primitives` 对这个旋钮**完全不动**
##                         （阴影 pass 不计入这两个计数器）—— 只看它们会误判成
##                         "旋钮没接线"，必须配 `wall_ms` 与像素差分。
##   `--lookmoon=1`        把相机**转成逆光**（方位对齐天体、仰角与机位不变）。
##                         ⚠️ **逆光类效果必须这样才测得出来**：海面浪尖透光用
##                         `-dot(view_dir, moon_dir)` 加权，默认机位月亮在相机背后
##                         ⇒ 该权重恒为 0 ⇒ 关掉它画面**逐字节不变**，
##                         看起来像"接线断了"（见 `_apply_overrides` 里的血泪注释）。
##   `--mist=<密度>`       `0` = 把贴海薄雾整个关掉（`FogVolume.visible = false`）；
##                         其他值 = 直接写 `FogMaterial.density`。⚠️ **工程值 0.00028 是 no-op**
##                         （实测在 45 / 200 / 800 / 1500 m 四个高度上都**逐位为零**）。
##   `--misttop=<米>`      雾板顶高（同时把板底钉在水面：`position.y = top/2`）。
##   `--mistfall=<数>`     `height_falloff`（板内的垂直衰减）。
##   `--misted=<0..1>`     `edge_fade`（水平边缘淡出）。**拧到 0 是对照**：
##                         雾箱 90 km 宽、相机在 20.7 km 处 ⇒ 淡出带很可能正盖着镜头。
##   `--mistspan=<米>`     雾板水平边长。工程值 90000 ⇒ 往朝外方向看，
##                         箱沿只在 24.3 km 处，而 45 m 高的海面地平线在 24 km —— **几乎重合**。
##   `--mistemit=<倍率>`   自发光通道等比放大。⚠️ 它是**悬崖式**的：低密度下 ×2/×5/×10
##                         逐位相同，×40 会越过辉光阈值引爆 bloom（+982%）。
##   `--foglen=<米>`       体雾**光程上限**（`Environment.volumetric_fog_length`）。
##                         默认 4000 —— 这是"薄雾在高空看不见"的隐形闸门之一。
##   `--fogspread=<数>`    `volumetric_fog_detail_spread`。⚠️ **默认就是 2.0**
##                         ⇒ 传 `--fogspread=2.0` 等于没拧（踩过：两档量出来逐位相同）。
##
## ⚠️ 只提供"拧回默认"这一个方向：**不给"拧到工程值"**，免得把工程的真源
##（`world_builder.gd` 里那组数）在探针里再抄一遍 —— 两份字面量迟早对不上。
func _apply_overrides() -> void:
	# ---- 动画时钟：**无条件**钉住（批 J）----
	#
	# ⚠️ 放在 `_overrides.is_empty()` 提前返回**之前**：可复算必须是**默认行为**，
	# 而不是"记得加一个参数才有"。这一点是被一次假 A/B 逼出来的 ——
	# 起因是 `ocean.gdshader` / `sky.gdshader` 用的是引擎内建的 `TIME`
	#（开机以来的墙钟时间，两次跑必然不同）。实测：**完全相同的参数**连跑两次，
	# 整帧均值只差 +0.99%（看着"可复算"），但画面**下三分之一的水面**逐行差到 **−64%**。
	# 而"某个区域内亮度整体变了"与"加了一层雾"**在数字上无法区分** ⇒
	# 本轮海雾的 A/B 数字全是相位漂移。
	# 详细记账见 `WorldBuilder._advance_anim_time()` 的注释。
	var wpin: WorldBuilder = _main.world if _main.world != null else null
	if wpin != null:
		var at := ANIM_PIN
		if _overrides.has("animtime"):
			at = float(_overrides["animtime"])
		wpin.pin_anim_time(at)
		print("[pixprobe] 动画时钟钉在 %.2f s（海面与星空不再随 `TIME` 漂）" % at)

	if _overrides.is_empty():
		return
	var vp := get_viewport()
	if _overrides.has("msaa"):
		vp.msaa_3d = clampi(int(_overrides["msaa"]), Viewport.MSAA_DISABLED, Viewport.MSAA_8X)
	if _overrides.has("deband"):
		vp.use_debanding = int(_overrides["deband"]) != 0
	if _overrides.has("foglen"):
		# ---- 体雾的**光程上限**（批 J · 轮 1）----
		#
		# ⚠️ 这是"海雾在玩家视角看不见"的真正原因，而不是密度不够：
		# 追尾相机在 **3200 m** 高度、水平朝看，画面下沿（31° 俯角）那条射线
		# 落到海面要走 **5.3 km**，而它进入雾板（板顶 160 m）时距离已经是 **5.9 km**。
		# 而 `Environment.volumetric_fog_length` 只有 4000 ⇒ **整条射线都在积分范围之外**
		# ⇒ 实测 A/B **逐位为零**（`--seacam=45` 贴海机位却看得清清楚楚）。
		#
		# 光程给长了代价是"同样的步数摊到更远" ⇒ 可能出现条带，
		# 要配 `volumetric_fog_detail_spread`；所以这里顺带给一个 `--fogspread`。
		var fl := maxf(float(_overrides["foglen"]), 1.0)
		var wf := _main.world as WorldBuilder
		if wf != null and wf._env != null:
			wf._env.volumetric_fog_length = fl
	if _overrides.has("fogspread"):
		var fs := maxf(float(_overrides["fogspread"]), 0.0)
		var wg := _main.world as WorldBuilder
		if wg != null and wg._env != null:
			wg._env.volumetric_fog_detail_spread = fs

	# ---- 材质侧的覆盖（批 E / G）----
	# ⚠️ 这一段**必须放在下面 `env == null` 那个提前返回之前**：
	# 材质与环境是两个独立的开关面，环境拿不到不该把材质也一起跳过。
	var w: Node = _main.world if _main.world != null else null
	if w != null:
		if _overrides.has("detail") and int(_overrides["detail"]) == 0:
			for m in w._terrain_mats:
				m.set_shader_parameter("detail_strength", 0.0)
				m.set_shader_parameter("detail_grain", 0.0)
		if _overrides.has("sss") and int(_overrides["sss"]) == 0 and w._ocean_mat != null:
			w._ocean_mat.set_shader_parameter("crest_sss", 0.0)
		if _overrides.has("seafade") and w._ocean_mat != null:
			# ---- 海面**距离淡出**（`ocean.gdshader` 的 `detail_fade`）----
			#
			# ⚠️ 起因：用户"**太平洋上空没法看到波浪的渲染材质，看着还是和之前一样**"。
			# 诊断（真渲染实测）：`fade = 1/(1 + 三维距离 × 0.0022)`
			# ⇒ 3.2 km 高空平视时整片可见海面的 fade 只有 **0.083~0.124**
			# ⇒ 长涌浪的法线增益与 `crest` 提亮都被压掉 90% ⇒ **海面读成一块平的深蓝板**。
			#
			# ⚠️ 而且这个自变量**选错了**：`fade` 想表达的是"海面细节随距离压平"，
			# 那是**沿水面**的现象，该用水平距离；用三维距离的话，
			# **俯视时"高度"也被算成了距离** —— 一个 800 m 正下方俯视的海面
			# 与一个 800 m 外的海面会被同等压平。
			#
			# ⚠️ 还有一层：它原本还要兼"抗远处闪烁/摩尔纹"，而那个职责
			# 在批 H 轮 3 之后**已经由微波的 `keep`（按 mpp 淡出）接管了**——
			# mpp 判据是**同一把尺子**（`terrain._oct_fade`），且是按被淡出那一层
			# 自己的波长算的，比"按距离一刀切"正确得多。
			# ⇒ 于是 `detail_fade` 剩下的唯一职责是"远处海面并入地平色"，
			# 而那个已经有 `horizon_start/end` 在做了。
			var sf := maxf(float(_overrides["seafade"]), 0.0)
			w._ocean_mat.set_shader_parameter("detail_fade", sf)
		if _overrides.has("waves") and w._ocean_mat != null:
			# ---- 海面长涌浪几何位移（批 H · 轮 1）----
			# `--waves=0` = 几何退回"一块平的板" ⇒ 与工程值 A/B，
			# 于是"海面从平板变成有浪的水面"到底改了多少画面是可测的。
			# 本工程凡是新增一项观感改动，都必须能这样被**单独拧掉**。
			w._ocean_mat.set_shader_parameter("wave_amp", float(_overrides["waves"]))
		if _overrides.has("shoal") and w._ocean_mat != null:
			# ---- 水下礁盘（批 H · 轮 1）----
			# 太平洋图的"地形"就在水下（那张图没有地表网格），
			# `--shoal=0` 把它拧回去 ⇒ 与工程值 A/B。
			w._ocean_mat.set_shader_parameter("shoal_amount", float(_overrides["shoal"]))
		if _overrides.has("ripple") and w._ocean_mat != null:
			# ---- 海面微波细节（批 H · 轮 3）----
			# `--ripple=0` 把短波法线拧回去 ⇒ 与工程值 A/B。
			# ⚠️ 这一项**只在近处有信号**（shader 自己按屏幕像素淡出），
			# 所以机位必须贴海（`--seacam=60` 这个量级），3 km 高空拍是拍不出差别的 ——
			# 那不是"没生效"，是"那个距离上本来就不该有微波"。
			w._ocean_mat.set_shader_parameter("ripple_amount", float(_overrides["ripple"]))
		if _overrides.has("matblend"):
			# ---- 地表材质分层（批 H · 轮 2）----
			# `--matblend=0` 把地表打回「各向同性的单层噪声」（轮 1 的状态），
			# 于是"层理到底带来了多少"是可测的。
			var mb := float(_overrides["matblend"])
			for m in w._terrain_mats:
				m.set_shader_parameter("mat_blend", mb)
		if _overrides.has("veg"):
			# ---- 稀疏植被覆盖（批 I · 轮 5，用户："艾尔斯岩地上要有 7% 左右
			#      不均匀的植被覆盖"）----
			# `--veg=0` 把植被整层拧掉 ⇒ 与工程值 A/B。
			# ⚠️ 这一项的判据里**有一条是量出来的**：`--topcam` 正下方俯视 +
			# `--perf` 里的 `veg_fraction`（按色相分类统计绿色像素占比）≈ 7%。
			# 只看"有没有绿色"是不够的 —— 覆盖率是个数，不是个感觉。
			var vv := float(_overrides["veg"])
			for m in w._terrain_mats:
				m.set_shader_parameter("veg_amount", vv)
		if _overrides.has("mottle") or _overrides.has("mottlelen"):
			# ---- 地表颜色斑驳（批 I · 轮 7，用户："地面看起来都是大色块，
			#      不够细致，多搞点细节"）----
			# `--mottle=0` 把斑驳整层拧掉 ⇒ 与工程值 A/B（**保留** wavelength，
			# 所以"波长挑得对不对"这件事不会混进强度对照里）。
			# `--mottlelen=<米>` 单独扫波长。
			#
			# ⚠️ 这一项的判据是**统计量**，不是"看着更细"：
			#   · `--shot` 存 PNG → `_imgstat.py` 的 `stddev_lum`（**开 vs 关**要高）；
			#     但它同时会把"整体变亮/变暗"混进来 ⇒ 必须**同时**看 `mean_lum`
			#     有没有漂移（这一层围绕 1.0 居中，均值**不应该**动；
			#     动了就说明某个通道的乘子写成了非中心对称，见 shader 里那段）；
			#   · 边缘密度（`edge_density`）也应该升 —— 斑驳是**颜色**层，
			#     它在近景会造出比 `detail_*` 更密的边缘。
			# 只盯 `stddev_lum` 会被"整层变亮"骗过去，这条在批 H 已经吃过一次。
			if _overrides.has("mottle"):
				var mv := float(_overrides["mottle"])
				for m in w._terrain_mats:
					m.set_shader_parameter("mottle", mv)
			if _overrides.has("mottlelen"):
				var ml := maxf(float(_overrides["mottlelen"]), 2.0)
				for m in w._terrain_mats:
					m.set_shader_parameter("mottle_wavelength", ml)
		# ⚠️ `misted` / `mistspan` **必须一起列进来**：它们是海雾那四个旋钮的同族，
		# 只传 `--misted=0.0` 而不传 `--mist` 时，漏列就会让整块**根本不执行** ——
		# 表现是"这个旋钮没接线"，而实际上请求值连读都没读。（本轮 EF* 那几张
		# 恰好都带着 `--mist=0.0060`，所以没暴露；这类"靠同事参数顺带生效"的漏项
		# 是 A/B 里最容易被当成"旋钮无效"的一类。）
		if _overrides.has("mist") or _overrides.has("misttop") \
				or _overrides.has("mistfall") or _overrides.has("mistemit") \
				or _overrides.has("misted") or _overrides.has("mistspan"):
			# ---- 贴海薄雾（批 J · 轮 1，用户："海面上方一带要有一层薄薄的雾气"）----
			# `--mist=0` 把这一层整个关掉（`visible = false`）⇒ 与工程值 A/B。
			# ⚠️ 关掉它**同时**要让判据能分辨"雾没生效"与"雾生效了但看不见"：
			# 所以 A/B 的读法不是"看着像不像"，而是
			#   ① `--shot` 存的两张 PNG 逐像素作差（`_imgstat.py` / `_rowprof.py`），
			#      **差异必须集中在海面那一带**，而不是整屏均匀抬亮
			#      （整屏抬亮说明 `volumetric_fog_density` 的基底给大了，
			#        那是个全局量，会把天空和机体一起糊掉）；
			#   ② **差异必须非零**。这一条是 2026-09-23 补的，而且它是本轮最贵的一课：
			#      原来的工程值 `0.00028` 在 45 / 200 / 800 / 1500 m 四个高度上
			#      **全部逐位为零**（"开着"的图和"关掉"的图 **md5 相同**）——
			#      也就是说它的所有"接线"都对，而画面上**根本不存在**。
			#      ⇒ 任何一条画质 A/B，第一条判据永远是"逐位为零就是没生效"。
			#   ③ 俯视（`--topcam`）**不是"几乎无差异"**（那是照错的传递函数推出来的旧判据）。
			#      实测工程值下俯视整帧 **−17.2%**，而且**浪花细节一个不丢**。
			#      正确的判据是"**细节保留 + 幅度小于掠射**"：
			#      掠射（45 m）+18.0% / 俯视 −17.2%，两者量级相近但**形状完全不同**
			#      （一个是地平线一条带，一个是整屏均匀压暗）。
			#      ⇒ 判"各向异性"要看**逐行剖面**，不是看整帧均值 ——
			#        整帧均值在这里会给出"两者差不多"的错误结论。
			if _overrides.has("mist"):
				var md := maxf(float(_overrides["mist"]), 0.0)
				if w._sea_mist != null:
					w._sea_mist.visible = md > 0.0
					var mfm := w._sea_mist.material as FogMaterial
					if mfm != null:
						mfm.density = md
			if _overrides.has("misttop"):
				var mt := maxf(float(_overrides["misttop"]), 4.0)
				if w._sea_mist != null:
					var ms: Vector3 = w._sea_mist.size
					w._sea_mist.size = Vector3(ms.x, mt, ms.z)
					w._sea_mist.position = Vector3(0.0, mt * 0.5, 0.0)
			if _overrides.has("mistfall"):
				var mf2 := maxf(float(_overrides["mistfall"]), 0.0)
				if w._sea_mist != null:
					var fm2 := w._sea_mist.material as FogMaterial
					if fm2 != null:
						fm2.height_falloff = mf2
			if _overrides.has("mistspan"):
				# ---- 雾板的水平边长（米）----
				#
				# ⚠️ 工程值 `span = 90000`、中心在世界原点；出生点在 `SPAWN_RADIUS = 20700`
				# ⇒ **往朝外的方向看，箱子边沿只在 24.3 km 处**，而 45 m 高的海面地平线
				# 在 24 km —— 两者**几乎重合**。也就是说露出来的那一层雾，
				# 正好在它最该最浓的地方**结束**。这条必须能拧开做对照。
				var ms3 := maxf(float(_overrides["mistspan"]), 1000.0)
				if w._sea_mist != null:
					var mv: Vector3 = w._sea_mist.size
					w._sea_mist.size = Vector3(ms3, mv.y, ms3)
			if _overrides.has("misted"):
				# ---- 边缘淡出（`FogMaterial.edge_fade`）----
				#
				# ⚠️ 这个旋钮是为一个**几何巧合**加的：雾箱是 `span = 90000` 的方盒、
				# 中心在世界原点，而玩家出生点在 `SPAWN_RADIUS = 20700` 处
				# ⇒ **相机离箱心 20.7 km、只到半边长（45 km）的 46%**。
				# 若 Godot 的边缘淡出是按"离最近那个面的距离"衰减的，
				# 那么 `edge_fade = 0.55` 就意味着淡出带从面往里伸 `0.55 × 45000 = 24.75 km`
				# ⇒ **相机正好落在淡出带里**，镜头跟前这半张图的海雾会被悄悄抹掉，
				# 而远处（离对面那个面 65 km）是满的。
				# 那会表现为"雾带只剩一半、近处没有" —— 与"密度不够"在数字上分不开。
				# 所以必须能把它拧到 0 做一次对照。
				var me2 := clampf(float(_overrides["misted"]), 0.0, 1.0)
				if w._sea_mist != null:
					var fm4 := w._sea_mist.material as FogMaterial
					if fm4 != null:
						fm4.edge_fade = me2
			if _overrides.has("mistemit"):
				# ---- 自发光倍率（批 J · 轮 1 调参用）----
				#
				# ⚠️ 为什么必须有这个旋钮，而不是"把密度加上去"：
				# 实测（2026-09-23，时钟钉住后）工程值 `density = 0.00028` 的
				# 像素差**精确为 0**；`×4.3` 时地平线那一行**变暗** −64%；
				# `×21` 才转成变亮 +868%。
				# 也就是体积雾在夜里的**反照率项几乎不产光**（没有光可反照），
				# 低密度时它先当"吸光层"，只有密度高到自发光项压过吸收才变亮。
				# 而用户要的是"**薄薄的**雾气" —— 提密度会把这一层做厚、做浑。
				# ⇒ 正解是**保持薄（低密度）+ 把自发光（多重散射替身）提上去**。
				var me := maxf(float(_overrides["mistemit"]), 0.0)
				if w._sea_mist != null:
					var fm3 := w._sea_mist.material as FogMaterial
					if fm3 != null:
						var e0: Color = fm3.emission
						fm3.emission = Color(e0.r * me, e0.g * me, e0.b * me)
		if _overrides.has("cloudsun") and int(_overrides["cloudsun"]) == 0:
			for m in w._cloud_mats:
				m.set_shader_parameter("sun_shade", 0.0)
		if _overrides.has("facade") and int(_overrides["facade"]) == 0:
			for m in w._city_facade_cache.values():
				m.set_shader_parameter("facade_strength", 0.0)
		if _overrides.has("fadefar"):
			# ---- 把淡出远端推远（批 G · **第一轮 A/B 无法归因后的补强**）----
			#
			# ⚠️ 血泪：第一轮拿 `--facade=0` 对 `--map=oenbelli` 做 A/B，8 个区域
			# **逐个逐位相同**（`full.mean_lum` 差 −0.0002）。这有两种完全不同的解释：
			#   ① **淡出吃掉**：`facade_fade_near/far = 970/1950` 之外
			#      `near_f` 就是 0，立面本来就不画 —— 相机在 1.5~2 km 轨道看城，
			#      整个城区都可能落在淡出之后；
			#   ② **没接上**：窗格根本没附着到楼体上。
			# 而这两个数原来是**写死在 shader 里的字面量**，运行时拧不动 ⇒
			# 光靠"关掉 facade_strength"分不开这两者。
			#
			# 提成 uniform 之后就能一次跑三个条件做**三分法**：
			#   A. `--facade=0`                        基线（关了）
			#   B. 不给参数（工程值 970/1950）          ← A≈B 说明范围内没有立面
			#   C. `--facade=0 --fadefar=999999`        把淡出彻底推开再看关了有没有差
			# 若 C ≈ A（仍然逐位不变）⇒ 窗格**根本没接到楼体上**（去查
			# `_city_block_at → _add_city_body → _add_box` 的 facade 传参链）；
			# 若 C 明显 ≠ A ⇒ 是淡出吃掉的，调 `CITY_FACADE_FADE_*` 即可。
			#
			# 只推远端：近端留在工程值，免得连"什么时候开始淡"都一起动，
			# 那就从"关掉一样东西"变成"改了两样东西"。
			for m in w._city_facade_cache.values():
				m.set_shader_parameter("facade_fade_far", float(_overrides["fadefar"]))
		if _overrides.has("sunaz"):
			# 只推给**云材质**：太阳节点本身（方向光）不动 ——
			# 不然"云的受光方向"和"场景阴影方向"两个变量会一起变，A/B 就没法归因了。
			var rot: Vector3 = w.sun.rotation_degrees
			var cdir := WorldBuilder.celestial_dir(
				Vector3(rot.x, float(_overrides["sunaz"]), rot.z))
			for m in w._cloud_mats:
				m.set_shader_parameter("sun_dir", cdir)
		if _overrides.has("lookmoon"):
			# ---- 逆光机位（1.2.3 批 E · **第一轮 A/B 测出来的必需项**）----
			#
			# ⚠️ 血泪：海面"浪尖透光"用的是 `back = -dot(view_dir, moon_dir)` ——
			# 它按定义**只在"玩家朝着月亮看"时非零**。而默认机位是"跟在机体后上方、
			# 顺着机体朝向"：太平洋图的时段里月亮正好在**相机背后** ⇒ `back = 0`
			# ⇒ 关掉 `crest_sss` 之后**画面逐字节不变**，A/B 表上一整片 `+0.0000`。
			# 那**不是**"这一项没接线"，而是"**在非逆光机位上，这一项在数学上就等于 0**"
			# —— 分不清这两者，就会把一条正确的实现当成没生效去乱改。
			#
			# 所以测逆光类效果**必须显式摆一个逆光机位**。这里**只转方位、
			# 保持原来的仰角与机位**（仰角从当前朝向反解）—— 否则连构图都换了，
			# A/B 就不是"只动一个变量"了。
			var ch := _main.chase as Camera3D
			if ch != null and w.sun != null:
				var sd := WorldBuilder.celestial_dir(w.sun.rotation_degrees)
				var flat := Vector3(sd.x, 0.0, sd.z)
				if flat.length() > 0.0001:
					flat = flat.normalized()
					# 相机朝向是 `-Z`（Godot 惯例），从它反解仰角
					var fwd := -ch.global_transform.basis.z
					var elev := asin(clampf(fwd.normalized().y, -1.0, 1.0))
					var dir := Vector3(
						flat.x * cos(elev), sin(elev), flat.z * cos(elev)).normalized()
					ch.look_at(ch.global_position + dir * 1000.0, Vector3.UP)
		if _overrides.has("citycam"):
			# ---- 城市特写机位（1.2.3 批 G · **第三轮"机位不对"的修复**）----
			#
			# ⚠️⚠️ 血泪（这是本轮第三次栽在"**记录的条件必须等于实际发生的条件**"上）：
			#
			# 前两轮拿出生点机位给城市立面做 A/B，`--facade=0` 只差 −0.0002，
			# 于是怀疑"接线断了"。把距离**量出来**才发现真相：
			#   · 奥恩贝利城区直径 **64 km**（`ARENA_RADIUS` 64400，16 格 × 4025 m）；
			#   · 出生点在 `SPAWN_RADIUS = 20700 m` 的环上（角度 −95°）；
			#   · **实测相机到最近一栋楼 3092.9 m，到一半的楼 30845.8 m，最远 48672.4 m**。
			#
			# 而窗格开间是 **5.2 m**。本工程 1600×900、竖直 fov 62° ⇒ 每米占 `748.9/d` 像素：
			#   · 3092 m 处 5.2 m 开间 = **1.3 px**（已经低于奈奎斯特）；
			#   · 30845 m 处 = **0.13 px**。
			# ⇒ **在出生点机位上，米制窗格在数学上就不可分辨** —— 淡出把它掐掉是对的，
			#   不是接线问题。`--fadefar=999999` 把淡出彻底推开后差值仍只有 −0.0009，
			#   正是"楼在画面里只占几个像素"的必然结果。
			#
			# 结论：**要判"城市近景细节好不好"，就必须把相机搬到楼跟前。**
			# 这个参数就是干这个的：找**离玩家最近的一栋**（保证是玩家真会飞过的那批楼，
			# 而不是随机挑一栋 40 km 外的），按与追尾相机**同款的上后方夹角**摆位，
			# 只把距离换成给定的米数 —— 这样与原生构图同源，读数才有可比性。
			var dist := maxf(float(_overrides["citycam"]), 20.0)
			var frames := _city_frames(w._terrain_root)
			var ch2 := _main.chase as Camera3D
			if frames.is_empty():
				push_warning("--citycam：没找到任何楼体节点，机位没动")
			elif ch2 == null:
				push_warning("--citycam：chase 相机为空，机位没动")
			else:
				var cam0 := ch2.global_position
				var best: Vector3 = frames[0]["pos"]
				var btop: Vector3 = frames[0]["top"]
				var bsize: Vector3 = frames[0]["size"]
				var bd := cam0.distance_to(best)
				for f in frames:
					var d := cam0.distance_to(f["pos"])
					if d < bd:
						bd = d
						best = f["pos"]
						btop = f["top"]
						bsize = f["size"]
				# 瞄**包围盒顶面中心**而不是节点原点：原点在楼的中部，
				# 直接按它摆位会把相机塞进墙里（实测整帧 mean_lum = 0.0032）。
				# 与 `_freeze()` 同一个偏移方向（上后方）—— 与原生构图同源，读数才可比。
				var off := CAM_OFFSET.normalized()
				ch2.global_position = btop + off * dist
				ch2.look_at(btop, Vector3.UP)
				ch2.fov = CAM_FOV
				ch2.current = true
				print("[pixprobe] 城市特写机位：目标顶面 %s（楼体 %s 尺寸 %s），机位 %s，距离 %.0f m（原生最近 %.0f m）" % [
					str(btop), str(best), str(bsize), str(ch2.global_position), dist, bd])

		if _overrides.has("aim"):
			# ---- 任意物件特写机位 `--aim=<节点名前缀>:<距离米>``（1.2.3 批 E）----
			#
			# 用途：把相机搬到世界里**某个具体节点**跟前去看它一眼 —— 用来回答
			# "画面上那个东西到底是什么"。第一个用户是奥恩贝利的地标球体
			#（`FujiSphere`）：用户在实机截图里看到一个悬在天上的黑球，无法判断
			# 是设计如此还是渲染 bug，需要一张能认出它的特写。
			#
			# ⚠️ 为什么不能拿 `--citycam` 代劳：那个只认 `Tower_/Block_/Slab_` 这些
			# **楼体**前缀（见 `_city_body_positions`），地标球体 `FujiSphere` 不在其中。
			#
			# ⚠️ 也**不能**把这段写成"按名字硬编码 FujiSphere"：地标还有立像、会展中心、
			# 中央塔，下一次同样的问题会以另一个名字出现。做成通用的前缀匹配，
			# 顺带让"球体/塔/立像到底长什么样"这件事随时可查。
			var spec := String(_overrides["aim"]).split(":")
			var want := spec[0] if spec.size() > 0 else ""
			var adist := maxf(float(spec[1]) if spec.size() > 1 else 800.0, 20.0)
			var hits := _find_all_by_prefix(w._terrain_root, want)
			var ch3 := _main.chase as Camera3D
			# 先无条件把所有命中打出来 —— 这一段的价值不在"有没有找到"，
			# 而在"**它们各自在哪里**"：同名前缀下有视觉节点与碰撞节点两份坐标时，
			# 这一行表格就是 bug 的证据本身。
			for h in hits:
				var h3 := h as Node3D
				print("[pixprobe] --aim 命中：%s（%s）local=%s global=%s" % [
					h.name, h.get_class(),
					str(h3.position) if h3 != null else "—",
					str(h3.global_position) if h3 != null else "—"])
			# 相机瞄谁？三级优先，**顺序本身就是判据**：
			#   ① 名字与该前缀**完全相同**的节点（`--aim=FujiSphere` ⇒ 就是那个球，
			#      不是同前缀的 `FujiSphereRing` / `FujiSphereBody`）；
			#   ② 否则第一个 `MeshInstance3D` —— **看得见的东西优先**；
			#   ③ 否则第一个 `Node3D`。
			#
			# ⚠️ ②③ 这个"看得见优先"必须写死：要是先撞上碰撞体，取到的会是一个
			# **正确但看不见**的坐标，拍出来的图会证明"位置没问题"，
			# 而屏幕上那个错位的几何体照样在那儿 —— 取证反而变成了包庇。
			var tgt_node: Node3D = null
			for h in hits:
				if String(h.name) == want and h is Node3D:
					tgt_node = h as Node3D
					break
			if tgt_node == null:
				for h in hits:
					if h is MeshInstance3D:
						tgt_node = h as Node3D
						break
			if tgt_node == null:
				for h in hits:
					if h is Node3D:
						tgt_node = h as Node3D
						break
			if want.is_empty():
				push_warning("--aim：用法是 --aim=<节点名前缀>:<距离米>，机位没动")
			elif hits.is_empty():
				push_warning("--aim：世界里没有名字以 %s 开头的节点，机位没动" % want)
			elif ch3 == null:
				push_warning("--aim：chase 相机为空，机位没动")
			elif tgt_node == null:
				push_warning("--aim：%s 那一批里没有 Node3D，机位没动" % want)
			else:
				# ⚠️ 用 `_aim_point()` 而**不是** `global_position`：
				# 对 MultiMesh 那类节点，后者恒为 (0,0,0)（见该函数的注释）。
				var tgt := _aim_point(tgt_node)
				# ---- 机位方位角 `--yaw=<度>` + 仰角 `--pitch=<度>`（1.3 批 M · 轮 5）----
				#
				# ⚠️ 没有这两个旋钮，`--aim` 就**只有一个机位**：从 +Z 侧、+9.6° 仰角
				#（`CAM_OFFSET` 的 `(0, 9, 53)`）。那个机位是为"看一栋楼/一个地标"
				# 设计的，于是所有"**走进去**"的取证都拍不出来：
				#   - `--pitch` 负角 ⇒ 能站到"船底那条 370 m 净空槽"里水平看这条槽；
				#   - `--pitch` 大正角 ⇒ 能俯视船顶面（判断"屋面板是不是一块死板"）；
				#   - `--yaw` ⇒ 能绕到**侧面**。港区龙门吊的两条腿是**沿 X 分开**的，
				#     站在 +Z 一侧看到的是吊臂的长侧面 —— 那个"门"永远不在画面里。
				# 这三件事都是**玩法通道**的取证，不是观感取证：站在几公里外斜看，
				# 永远答不了"机体能不能从这条缝里飞过去"。
				#
				# ⚠️ 夹在 ±89°：90° 时视线与 `look_at` 的上向量共线 ⇒ 相机翻转
				#（同 `--topcam` 那段踩过的坑）。
				var pdeg := rad_to_deg(asin(clampf(CAM_OFFSET.normalized().y, -1.0, 1.0)))
				var ydeg := 0.0
				if _overrides.has("pitch"):
					pdeg = clampf(float(_overrides["pitch"]), -89.0, 89.0)
				if _overrides.has("yaw"):
					ydeg = float(_overrides["yaw"])
				var pr := deg_to_rad(pdeg)
				var yr := deg_to_rad(ydeg)
				var off := Vector3(sin(yr) * cos(pr), sin(pr), cos(yr) * cos(pr))
				ch3.global_position = tgt + off * adist
				ch3.look_at(tgt, Vector3.UP)
				ch3.fov = CAM_FOV
				ch3.current = true
				# 这张图的**证词**就是这一行：少了它，图只能证明"有个黑球"，
				# 证不了"这个黑球是哪一个、它在哪"。
				var mmn := tgt_node as MultiMeshInstance3D
				print("[pixprobe] 物件特写机位：瞄 %s（%s%s）%s，机位 %s，距离 %.0f m，方位 %+.1f° 仰角 %+.1f°；同前缀共 %d 个命中" % [
					tgt_node.name, tgt_node.get_class(),
					"×%d 个实例的质心" % mmn.multimesh.instance_count \
						if (mmn != null and mmn.multimesh != null) else "",
					str(tgt), str(ch3.global_position), adist, ydeg, pdeg, hits.size()])
		if _overrides.has("seacam"):
			# ---- 贴海低空机位（批 H · 轮 1）----
			# 海面的长涌浪位移（`wave_amp`）只有**低空**才看得见：在 3200 m 的出生点
			# 机位上，4 m 的浪摆在 20 km 外是**亚像素**。
			#
			# ⚠️ 只压 y、不动朝向是没用的：`_freeze()` 把相机对准了 3200 m 高的机体，
			# 压下来之后就会**朝着天拍**。所以朝向同时改成**水平**指向机体方位
			#（高度差丢掉）——于是画面里是「海面 + 地平线」，机体不挡镜头
			#（它在 3.2 km 高的天上，正好在视野之外）。
			var chS := _main.chase as Camera3D
			if chS == null:
				push_warning("--seacam：chase 相机为空，机位没动")
			elif _main.player == null:
				push_warning("--seacam：玩家为空，机位没动")
			else:
				var gy := maxf(float(_overrides["seacam"]), 5.0)
				var pp: Vector3 = _main.player.global_position
				var cp: Vector3 = chS.global_position
				chS.global_position = Vector3(cp.x, gy, cp.z)
				var flat := Vector3(pp.x - cp.x, 0.0, pp.z - cp.z)
				if flat.length() < 0.001:
					flat = Vector3(0.0, 0.0, -1.0)
				flat = flat.normalized()
				chS.look_at(chS.global_position + flat * 1000.0, Vector3.UP)
				chS.fov = CAM_FOV
				chS.current = true
				print("[pixprobe] 贴海机位：%.0f m 高，水平朝 %s（机体在 %.0f m，画面外）" % [
					gy, str(flat), pp.y])

		if _overrides.has("aimoasis"):
			# ---- 绿洲特写机位 `--aimoasis=<模式>:<距离米>`（批 K · 轮 2）----
			#
			# ## 为什么不能拿 `--aim` 代劳（轮 1 就是这么栽的）
			# 轮 1 的 `J_tree_close`（`--aim=DesertTrees:110`）拍出来是一张
			# **16 KB 的纯色空帧**，而日志里 `err=0`、没有 `world == null`
			# —— 也就是说它**报告自己成功了**。
			# 根因：`--aim` 把相机放在 `目标 + CAM_OFFSET.normalized() × 距离`，
			# 那个偏移的 y 分量只有 0.167 ⇒ 110 m 抬 **18.4 m**，
			# 而沙漠地面在那一带是 **~37 m** ⇒ **相机埋进沙丘里面**，
			# 拍到的是地形网格的近裁剪面。
			#（`--aim` 是为地标球体写的，球心在天上、`MultiMesh` 的原点在原点，
			#  两者从来不会碰上一个"地面比相机高"的情况。）
			#
			# ## 所以这个机位**自己管高度**，而且目标是"有树的地方"
			# 目标取**绿洲团心**（那里必然有树、有草），高度取
			# `max(0.30 × 距离, 55 m)`：
			#   · `0.30 × 距离` 保证俯角恒定 ≈ 17° ⇒ 换距离不会换构图；
			#   · `55 m` 是"必在地面之上"的下限。⚠️ 注意它**不是**安全下限：
			#     沙丘最高 `24 + 26 + 10 = 60 m`，55 m 仍可能低于丘顶 ——
			#     大距离时由 `0.30 × 距离` 兜住（260 m 时是 78 m）。
			var wbo := _main.world as WorldBuilder
			var cho := _main.chase as Camera3D
			if wbo == null or cho == null or wbo.desert_oasis_sites.is_empty():
				push_warning("--aimoasis：world/chase 为空、或绿洲没撒出来（非沙漠图？），机位没动")
			else:
				var so := String(_overrides["aimoasis"]).split(":")
				var mode := so[0] if so.size() > 0 else "big"
				var odist := maxf(float(so[1]) if so.size() > 1 else 260.0, 40.0)
				var best_i := 0
				if mode == "big":
					# 半径最大的那一团：单团形态最容易看清（树的形状、草的读感）。
					for i in wbo.desert_oasis_sites.size():
						if wbo.desert_oasis_sites[i].z > wbo.desert_oasis_sites[best_i].z:
							best_i = i
				elif mode == "heavy":
					# 树最多的那一团（按 `r² × 核心` 代理）：用来证明"**有树木**"。
					for i in wbo.desert_oasis_sites.size():
						var si: Vector4 = wbo.desert_oasis_sites[i]
						var sb: Vector4 = wbo.desert_oasis_sites[best_i]
						if si.z * si.z * si.w > sb.z * sb.z * sb.w:
							best_i = i
				else:
					best_i = clampi(int(mode), 0, wbo.desert_oasis_sites.size() - 1)
				var site: Vector4 = wbo.desert_oasis_sites[best_i]
				var gy: float = wbo._desert_dune_height(site.x, site.y)
				var tgt := Vector3(site.x, gy + 12.0, site.y)
				var oy := maxf(odist * 0.30, 55.0)
				cho.global_position = tgt + Vector3(0.0, oy, odist)
				cho.look_at(tgt, Vector3.UP)
				cho.fov = CAM_FOV
				cho.current = true
				print("[pixprobe] 绿洲特写机位：模式 %s ⇒ 第 %d 团 r=%.0f core=%.2f 心 (%.0f, %.0f)；地面 %.1f m，机位 %s（抬 %.0f m），距离 %.0f m；共 %d 团" % [
					mode, best_i, site.z, site.w, site.x, site.y, gy,
					str(cho.global_position), oy, odist, wbo.desert_oasis_sites.size()])

	if _overrides.has("topcam"):
		# ---- 正下方俯视机位（批 I · 轮 5）----
		# 用来**量**植被覆盖率：把相机搬到机体正上方 `--topcam=<米>` 处、镜头垂直朝下。
		#
		# ⚠️ 为什么不能用 `--aim` 或 `--seacam` 代替：
		# `--aim` 是斜看（近处被透视拉长，覆盖率会被近景那一圈主导），
		# `--seacam` 是水平看（画面里根本没有"一块地"，覆盖率无从谈起）。
		# 覆盖率必须**按面积**测 ⇒ 只能垂直俯视，且视场里**不能有天空**
		#（天空像素不是地表，混进来会把分母搞错）。
		#
		# ⚠️ 朝向**直接给欧拉角**而不是 `look_at`：正下方看时"上方向"与视线平行，
		# `look_at` 的上向量退化（(0,1,0) 与视线共线）⇒ 会翻转/报错。
		# `rotation_degrees.x = -90` 就是"绕 X 转 -90°"⇒ 相机默认的 -Z 指向世界 -Y（正下）。
		var chT := _main.chase as Camera3D
		if chT == null:
			push_warning("--topcam：chase 相机为空，机位没动")
		elif _main.player == null:
			push_warning("--topcam：玩家为空，机位没动")
		else:
			var th := maxf(float(_overrides["topcam"]), 20.0)
			var tp: Vector3 = _main.player.global_position
			chT.global_position = Vector3(tp.x, th, tp.z)
			chT.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
			chT.fov = CAM_FOV
			chT.current = true
			# 视场边长（米）—— 覆盖率的分母就是这个方框
			var half := tan(deg_to_rad(CAM_FOV * 0.5)) * th
			print("[pixprobe] 俯视机位：%.0f m 高 ⇒ 视场约 %.0f × %.0f m（垂直向下，全为地表）" % [
				th, half * 2.0 * 1.7778, half * 2.0])

	var env: Environment = _main.world._env if _main.world != null else null
	if env == null:
		return
	if _overrides.has("lift"):
		# ---- 机位**统一抬高** `--lift=<米>`（批 K · 轮 2）----
		#
		# 存在理由只有一条，但很硬：**任何"瞄地面目标"的机位都可能把相机埋进地形**，
		# 而那种失败拍出来的是一张**纯色图、`err=0`**（见 `--aimoasis` 那段）。
		# 与其给每个机位各写一遍下限，不如给一个能在**所有机位之后**生效的旋钮：
		# 出了这种图，加 `--lift=80` 就能立刻判断"是不是埋进去了"。
		# ⚠️ 只抬 y、不动朝向 —— 抬完之后视线会略微朝下偏，那一帧的用途是
		# "确认相机到底在不在外面"，不是构图。
		var chL := _main.chase as Camera3D
		if chL != null:
			chL.global_position.y += float(_overrides["lift"])
			print("[pixprobe] --lift：机位抬高 %.0f m ⇒ %s" % [
				float(_overrides["lift"]), str(chL.global_position)])
		else:
			push_warning("--lift：chase 相机为空，没抬")
	if _overrides.has("adjust"):
		env.adjustment_enabled = int(_overrides["adjust"]) != 0
	if _overrides.has("glowlevels") and int(_overrides["glowlevels"]) == 0:
		var defaults := [0.0, 0.8, 0.4, 0.1, 0.0, 0.0, 0.0]
		for i in 7:
			env.set("glow_levels/%d" % (i + 1), defaults[i])
	if _overrides.has("amb"):
		# ---- 环境光强度（`Environment.ambient_light_energy`）----
		#
		# ⚠️ 起因：用户"**奥恩贝利…地面和楼房暗面依旧看不到**"。
		# 本工程夜里/阴天黄昏的**唯一**填充光是环境光，而环境光走的是
		# `ambient_light_source = SKY` + `sky_contribution = 1.0`
		# ⇒ 它的颜色与强度**完全由天空决定**。所以"暗面看不见"可能是三件事：
		#   ① 环境光**强度**不够（就是这个旋钮）；
		#   ② 天空本身太暗 ⇒ 环境光色偏暗（那是 `sky.gdshader` / 时段预设的事）；
		#   ③ 材质的**反照率**太黑（`ground_swatch` 只有 (0.16,0.15,0.14)）。
		# 三者在像素上分不开 ⇒ 必须有一个能单独拧①的旋钮，否则调参只能靠猜。
		env.ambient_light_energy = maxf(float(_overrides["amb"]), 0.0)
	# ---- ⚠️ 批 K · 轮 1② 实测：上面那个 `--amb` 是**死旋钮** ----
	#
	# `--amb=0.0 / 2.0 / 3.0` 三档与不传**逐位相同**（`_k2_stat.py` 的 mean 同为
	# 0.2296、darkσ 同为 0.00107）。根因不是"接线断了"，是**引擎语义**：
	# `ambient_light_source = SKY` 且 `ambient_light_sky_contribution = 1.0` 时，
	# 环境色被**天空辐射整体替换**，`ambient_light_color × ambient_light_energy`
	# 那一项的权重是 0 ⇒ `energy` 无论取多少都不进画面。
	#
	# 这件事的**危害**在于它长得完全像"参数没接上"：`_build_environment()` 里
	# 那行 `env.ambient_light_energy = 0.85` 读起来是在调填充光，**实际什么也没调**。
	# 所以后面加 `--ambsrc` / `--skycon` 两个旋钮，把那条被权重 0 掐掉的支路
	# **显式打开**，才能做"环境光到底有没有到地上"的归因。
	if _overrides.has("ambsrc"):
		# 1 = DISABLED / 2 = COLOR / 3 = SKY（与 `Environment.AMBIENT_SOURCE_*` 同值）
		env.ambient_light_source = int(_overrides["ambsrc"])
	if _overrides.has("ambcol"):
		var partsP := (_overrides["ambcol"] as String).split(",")
		if partsP.size() == 3:
			env.ambient_light_color = Color(float(partsP[0]), float(partsP[1]),
				float(partsP[2]))
	if _overrides.has("skycon"):
		env.ambient_light_sky_contribution = clampf(float(_overrides["skycon"]), 0.0, 1.0)
	# `--amben=<倍>`：**只有**在 `--skycon=0`（或 `--ambsrc=2`）时才有意义 ——
	# 见上面那段：`sky_contribution = 1.0` 时 `energy` 的权重是 0。
	#
	# ⚠️ 这个旋钮是给"剂量表"用的（`_pix_m6.sh`）：达沃的夜城填充光要选一档
	# **实测出来**的能量，而不是拍脑袋写一个数。`_k2_stat.py` 那套
	#（crush% / darkσ / 整帧 mean）就是在这里量出来的。
	# ⚠️ 与 `--amb` 的区别：那个是 1.2 时代的老旋钮，**在 sky_contribution=1 下空转**
	#（所以它才被留在这里当反例）。这一个直接写 `ambient_light_energy`，
	# 配合 `--skycon=0` 才真的进画面。
	if _overrides.has("amben"):
		env.ambient_light_energy = maxf(float(_overrides["amben"]), 0.0)
	# ---- ⚠️ 天空那条支路**实测近乎为零**，先试"是不是没烘出来" ----
	#
	# `D_skycon0 ≡ D_both`（md5 相同）已经把机制钉死了：环境光在
	# `sky_contribution = 1.0` 时**完全取天空辐射**。而 `D_base` 的 `darkσ` 只有
	# **0.00107**、`crush` 高到 **36%**，换成一个 `color(0.35) × 1.0` 的显式环境光
	# 之后 `darkσ` 直接跳到 **0.0347（×32）**。⇒ 天空辐射送进 BRDF 的量**约等于 0**，
	# 而**可见天空本身是明亮的**（截图上那片褐色云、`sky.gdshader` 的地平线色
	# 转线性后约 0.4）—— 两者对不上，所以"天空太暗"这个解释**不成立**，
	# 更像是"天空的 radiance cubemap 根本没生成 / 没被用上"。
	#
	# Godot 的自定义 sky shader 走 `Sky.process_mode` + `Sky.radiance_size`
	# 两个参数来决定"那张 cubemap 怎么烘"。所以这两个旋钮是**分化测试**：
	#   · `--skyproc=3`（REALTIME）逐帧重烘 ⇒ 若画面立刻亮起来，是"没烘"；
	#   · `--skyrad=5`（512）抬高 cubemap 分辨率 ⇒ 若只有它有用，是"烘得太粗"；
	#   · 两个都无效 ⇒ 换 `sky_contribution < 1` + 显式环境色（见 `--skycon`），
	#     即**不再依赖这条支路**，把 `ambient_light_energy` 那行重新变成真旋钮。
	if _overrides.has("skyproc"):
		if env.sky != null:
			env.sky.process_mode = int(_overrides["skyproc"])
	if _overrides.has("skyrad"):
		if env.sky != null:
			env.sky.radiance_size = int(_overrides["skyrad"])
	if _overrides.has("cel"):
		# ---- 三渲二后处理的**总开关**（`main.gd` 的 `CelPost` 全屏面片）----
		#
		# ⚠️ 这是本轮**最该先做的那一步**，理由：`cel_post.gdshader` 是
		# `unshaded` + `blend_mix` 的全屏面片，`ALBEDO = c`（c 取自 `hint_screen_texture`）。
		# 它同时做**色阶量化**（`color_steps = 6` / `posterize_mix = 0.6`）与
		# **饱和度提纯**（1.18）。这两步都在**暗部**有最大相对影响：
		# 量化把 [0, 1/6) 整段映到 0，提饱和又把暗部的色差压向灰 ⇒
		# "地面与楼房暗面看不见"完全可能是**后处理做的**，而不是光照不够。
		# 光照与后处理这两条路在全局统计上**长得一模一样** ⇒ 必须能单独关掉一个。
		#
		# ⚠️ 关掉它只是**归因手段**，不是修法：三渲二是本作的美术风格，
		# 修法是让**进后处理之前**的暗部足够亮/足够有层次，而不是把后处理去掉。
		if _main.cel_quad != null:
			_main.cel_quad.visible = int(_overrides["cel"]) != 0
	# ---- ⚠️ 单独拧 `posterize_mix`：把"量化"从"总开关"里摘出来 ----
	#
	# `--cel=0` 一口气关掉三样（量化 / 提饱和 / 深度描边），**三者都往暗部压** ⇒
	# 只关总开关的话，"暗部为什么黑"仍然分不到量化头上。而这三个的自由度完全不同：
	#   · 量化（`posterize_mix`）是[暗部**整段清零**]的元凶候选 —— 可单独降；
	#   · 提饱和（`saturation`）只压色差、不怎么动亮度；
	#   · 描边（`outline_*`）只在**边缘**上色，与"整片暗面"无关。
	# ⇒ 所以先把 `posterize_mix` 单独拧到 0 拍一张：若暗部就是它清的，这一张立刻看出来。
	if _main.cel_quad != null and _main.cel_quad.material_override is ShaderMaterial:
		var cmat := _main.cel_quad.material_override as ShaderMaterial
		if _overrides.has("postmix"):
			cmat.set_shader_parameter("posterize_mix",
				clampf(float(_overrides["postmix"]), 0.0, 1.0))
		if _overrides.has("steps"):
			cmat.set_shader_parameter("color_steps",
				clampf(float(_overrides["steps"]), 2.0, 64.0))
		if _overrides.has("postsatin"):
			cmat.set_shader_parameter("saturation",
				clampf(float(_overrides["postsatin"]), 0.0, 2.0))
		# ⚠️ `intensity` 是后处理的**总开关强度**（0 = 原画面）。
		# `--postinten=0 --postsatin=1.0` 合起来就是一条**恒等透传**：
		# 量化被 `×intensity` 关掉、饱和度退回 1.0、描边也被 `×intensity` 关掉
		# ⇒ 面片输出的应当**逐位等于**不开后处理的画面。
		# 用它把"后处理在改色"与"后处理采样/色彩空间就不对"分开。
		if _overrides.has("postinten"):
			cmat.set_shader_parameter("intensity",
				clampf(float(_overrides["postinten"]), 0.0, 1.0))
	# ---- ⚠️⚠️ 决定性判定：**这个面片到底有没有在画**（批 K · 轮 3）----
	#
	# 背景：`--postmix=1.0 --steps=2`（硬量化到 2 阶）与 base 的 PNG **md5 逐位相同**，
	# 而"量化到 2 阶"在数学上**不可能是自己不变**（除非画面本来就是纯 2 阶色阶）。
	# 两张图都是 1.13 MB 的正常帧（不是空白帧）⇒ 面片确实没参与渲染。
	#
	# ⚠️ 但"改 uniform 没效果"**还不能**直接推出"没在画"——uniform 名字写错、
	# 材质被换掉、`set_shader_parameter` 打在了另一份 ShaderMaterial 上，都会给出
	# 一模一样的"零差异"。所以必须有一个**与 uniform 无关**的判定：
	# 把 fragment 换成**输出纯色**，画了就是整屏纯色，没画就一点变化都没有。
	#
	# ⚠️ 内联 shader **照抄** `cel_post.gdshader` 的 `render_mode` 与 `vertex()`
	#（逐字复制）：这样顶点覆盖 / 裁剪 / 深度 / 混合行为与真 shader 完全一致，
	# 唯一变量就是 fragment 是否执行 ⇒ 隔离干净。
	# 若这一改**没有**变成纯色，说明问题在**顶点/实例层**（渲染顺序、剔除、可见性），
	# 而不是 fragment ⇒ 下一步该查实例而不是 shader。
	# ---- `--celoff=<米>`：把面片从"相机前 1 m"拉开 ----
	#
	# ⚠️⚠️ **实测根因就藏在这 1 米里**：诊断字段打出
	#   `cam_near = 1.2` / `cam_dist = 1.0004` / `cam_in_view = false`
	# ⇒ 面片**贴在近平面的内侧**，相机判定它不在视锥内。
	# 而 `main.gd` 的注释只针对了"视锥剔除"（用 `extra_cull_margin = 10000`），
	# **没有针对近平面** —— `extra_cull_margin` 只放大 CPU 侧剔除用的 AABB，
	# 对 GPU 的近平面裁剪一点作用都没有。
	# 这个旋钮把距离拉开，用来分清"是近平面吃掉的"还是"顶点写法本身不生效"。
	if _main.cel_quad != null and _overrides.has("celoff"):
		_main.cel_quad.position = Vector3(0.0, 0.0,
			-maxf(float(_overrides["celoff"]), 0.1))
	if _main.cel_quad != null and _overrides.has("celpaint"):
		var rgb: PackedStringArray = str(_overrides["celpaint"]).split(",")
		var pr := float(rgb[0]) / 255.0 if rgb.size() > 0 else 1.0
		var pg := float(rgb[1]) / 255.0 if rgb.size() > 1 else 0.0
		var pb := float(rgb[2]) / 255.0 if rgb.size() > 2 else 0.0
		# `--celz=<clip z>`：内联面片写的 clip-space z。
		# ⚠️ 工程值 0.0 —— 而那**正好是裁剪面边界**。这个旋钮就是为了验
		# "是不是 z 落在边界上被裁掉了"：0.5 / 0.999 若能看到纯色而 0.0 看不到，
		# 就是边界裁剪；全部看不到则与 z 无关。
		var cz := float(_overrides["celz"]) if _overrides.has("celz") else 0.0
		var dbg := Shader.new()
		dbg.code = "\n".join([
			"shader_type spatial;",
			"render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;",
			"void vertex() {",
			"	POSITION = vec4(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0, %s, 1.0);" % str(cz),
			"}",
			"void fragment() {",
			"	ALBEDO = vec3(%f, %f, %f);" % [pr, pg, pb],
			"	ALPHA = 1.0;",
			"}",
		])
		var dbg_mat := ShaderMaterial.new()
		dbg_mat.shader = dbg
		_main.cel_quad.material_override = dbg_mat
		if _overrides.has("celprio"):
			dbg_mat.render_priority = int(_overrides["celprio"])
	if _main.cel_quad != null and _overrides.has("celprio") \
			and not _overrides.has("celpaint"):
		# 单独拧排序：面片在透明队列里 `render_priority` 默认 0，而尾焰/光晕那些 FX
		# 也是 0 ⇒ 谁后画取决于**深度排序**。这一项单独把它顶到 100（最后画）。
		var pm := _main.cel_quad.material_override as ShaderMaterial
		if pm != null:
			pm.render_priority = int(_overrides["celprio"])
	# ---- `--celshape=1`：**另起一个新实例**，配置逐字照抄 `cel_quad` ----
	#
	# 目的：把"**这个实例**坏了"与"**这套配置**坏了"分开。
	#   · 新建的画了、原来没画 ⇒ 问题在 `cel_quad` 这个实例（被谁改了 / 被剔了）；
	#   · 两个都没画 ⇒ 问题在配置本身（顶点写法 / render_mode / 挂载位置）。
	# 两者下一步动作完全不同，而没有这一项就分不开。
	if _overrides.has("celshape") and _main.chase != null:
		var mode := int(_overrides["celshape"])
		var mk := Shader.new()
		var mk_lines := [
			"shader_type spatial;",
			"render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;",
		]
		# `celshape=2`：**不写 POSITION** 的普通写法（顶点走正常 MVP）。
		# 用来把"顶点覆盖写法不生效"与"整个实例不被渲染"分开：
		# 模式 2 若画出来（画面正中一个绿方块）⇒ 引擎能渲染 chase 的子节点，
		# 问题在 `POSITION` 覆盖那一支；模式 2 也不画 ⇒ 问题在挂载/剔除。
		if mode == 3:
			# `celshape=3`：**照常做顶点变换，但用 `POSITION` 覆盖输出**（手动 MVP。
			# 用来把"支路整体不生效"与"原来那个值不对"分开：
			#   画出来 ⇒ 支路能用，原方案只是**值**不对（修 shader 里那一行即可）；
			#   画不出来 ⇒ 支路整体不生效（必须换成"几何铺满屏幕"）。
			mk_lines.append("void vertex() {")
			mk_lines.append("	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);")
			mk_lines.append("}")
		elif mode == 4:
			# `celshape=4`：用 **`VERTEX.xy`**（QuadMesh size=2 ⇒ ±1）当 clip xy。
			# 与 mode 5 成对，用来分清"原方案不画"是 `UV` 还是 `z=0` 造成的。
			# ⚠️ mode 4/5 的实例位置都放在 **-5 m**（near 之外）：这样三种结果互斥且可判 ——
			#   铺满纯绿   ⇒ `POSITION` 生效**且**这个值可用；
			#   中央小方块 ⇒ `POSITION` **没**生效（退回普通变换，正是 `shape2` 的样子）；
			#   什么都没有   ⇒ 该值让三角形退化/被裁。
			mk_lines.append("void vertex() {")
			mk_lines.append("	POSITION = vec4(VERTEX.xy, 0.0, 1.0);")
			mk_lines.append("}")
		elif mode == 5:
			# `celshape=5`：直接把 `UV` 当 clip xy —— 若 `UV` 在 vertex() 可用，
			# 应画出**右上四分之一屏**的绿块（UV∈[0,1] ⇒ NDC 的 [0,1]）。
			mk_lines.append("void vertex() {")
			mk_lines.append("	POSITION = vec4(UV.x, UV.y, 0.0, 1.0);")
			mk_lines.append("}")
		elif mode == 11:
			# ⚠️⚠️ **假说的验证**：只把 y 的映射从"翻转"改成"不翻转"，
			# 其余与 mode 1（原方案）逐字相同。若这一发画出**全屏纯绿**，
			# 就坐实"原方案不渲染 = 那一行翻转了 y ⇒ 屏幕空间绕序反转 ⇒ 背面剔除"。
			mk_lines.append("void vertex() {")
			mk_lines.append("	POSITION = vec4(UV.x * 2.0 - 1.0, UV.y * 2.0 - 1.0, 0.0, 1.0);")
			mk_lines.append("}")
		elif mode == 12:
			# 反向对照：**故意翻转 x**（其余同 mode 11）。按假说应当**不画**
			#（与 base 逐位相同）—— 若它反而画了，说明"绕序"模型是错的。
			mk_lines.append("void vertex() {")
			mk_lines.append("	POSITION = vec4(1.0 - UV.x * 2.0, UV.y * 2.0 - 1.0, 0.0, 1.0);")
			mk_lines.append("}")
		elif mode == 8:
			# x 取负（屏幕左半 × 下半）：判"取负"本身是否有问题
			mk_lines.append("void vertex() {")
			mk_lines.append("	POSITION = vec4(-UV.x, UV.y, 0.0, 1.0);")
			mk_lines.append("}")
		elif mode == 9:
			# y 取负：与 mode 5 成对，判 y 方向
			mk_lines.append("void vertex() {")
			mk_lines.append("	POSITION = vec4(UV.x, -UV.y, 0.0, 1.0);")
			mk_lines.append("}")
		elif mode == 10:
			# x 跨 0（全宽）、y 非负 —— 把"跨 0"从"y 翻转"里摘出来
			mk_lines.append("void vertex() {")
			mk_lines.append("	POSITION = vec4(UV.x * 2.0 - 1.0, UV.y, 0.0, 1.0);")
			mk_lines.append("}")
		elif mode == 6 or mode == 7:
			# `celshape=6 / 7`：把"铺满"的 ±1 缩一点点（0.99 / 0.5）。
			# 判据：若 6 能画出几乎全屏的绿块而 mode 1（原方案，正好 ±1）不能，
			# 就坐实**顶点落在 NDC 边界 ±1 上会被整体裁掉**（浮点边界）。
			var k := 0.99 if mode == 6 else 0.5
			mk_lines.append("void vertex() {")
			mk_lines.append("	POSITION = vec4((UV.x * 2.0 - 1.0) * %s, (1.0 - UV.y * 2.0) * %s, 0.0, 1.0);"
				% [str(k), str(k)])
			mk_lines.append("}")
		elif mode != 2:
			mk_lines.append("void vertex() {")
			mk_lines.append("	POSITION = vec4(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0, 0.0, 1.0);")
			mk_lines.append("}")
		mk_lines.append("void fragment() {")
		mk_lines.append("	ALBEDO = vec3(0.0, 1.0, 0.0);")
		mk_lines.append("	ALPHA = 1.0;")
		mk_lines.append("}")
		mk.code = "\n".join(mk_lines)
		var mk_mat := ShaderMaterial.new()
		mk_mat.shader = mk
		var mk_q := MeshInstance3D.new()
		mk_q.name = "CelPostDebugShape"
		var mk_plane := QuadMesh.new()
		mk_plane.size = Vector2(2.0, 2.0)
		mk_q.mesh = mk_plane
		mk_q.material_override = mk_mat
		mk_q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mk_q.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mk_q.extra_cull_margin = 10000.0
		_main.chase.add_child(mk_q)
		if mode >= 3 and mode <= 12:
			mk_q.position = Vector3(0.0, 0.0, -5.0)
		elif mode == 2:
			mk_q.position = Vector3(0.0, 0.0, -3.0)
		else:
			mk_q.position = Vector3(0.0, 0.0, -1.0)
		# 原来的实例**留着**（这是对照的一半），只把它藏掉，好让新实例的画面不被覆盖。
		if _main.cel_quad != null and mode != 0:
			_main.cel_quad.visible = false
	# ---- 绿洲：**把树和地面绿斑分成两层单独拧**（批 K · 轮 1③）----
	#
	# 为什么必须分开：`--veg=0` 只关 shader 那一层（地上的绿），
	# **树是真几何、不受它影响**。而用户的三条要求里"要有树木"是独立的一条，
	# 所以"地上没绿"和"树没撒上"是**两个不同的失败模式**，
	# 但它们在一张图上都表现成"看不见绿洲"。
	# ⇒ 各自一个旋钮，A/B 才分得开。
	if _overrides.has("trees") and _main.world != null:
		var wt := _main.world as WorldBuilder
		if wt != null and wt._terrain_root != null:
			var tn := wt._terrain_root.get_node_or_null("DesertTrees")
			if tn != null:
				tn.visible = int(_overrides["trees"]) != 0
	# ---- 城市装饰层的分层开关（批 K · 轮 4）----
	#
	# ⚠️ 存在的理由：**近景里出现了规则锯齿**，而候选成因有三个
	#（楼体线脚 / 裙房檐口 / 本来就有的东西）。
	# 靠看图**分不出来** —— 人眼对"上一张长什么样"的记忆不可靠。
	# 一个开关 + 一次逐位 A/B 才能在**一次**运行里把它钉死。
	# 与 `--trees` 同一条规矩：一层一个旋钮，A/B 才分得开。
	if _overrides.has("bands") and _main.world != null:
		var wb2 := _main.world as WorldBuilder
		if wb2 != null and wb2._terrain_root != null:
			var bn := wb2._terrain_root.get_node_or_null("CityBands")
			if bn != null:
				bn.visible = int(_overrides["bands"]) != 0
	if _overrides.has("portlights") or _overrides.has("porten") or _overrides.has("portshadow"):
		# ---- 港区泛光灯（1.3 批 M · 轮 6）----
		#
		# 两个旋钮**故意分开**，因为它们要回答两个不同的问题：
		#
		#   · `--portlights=0/1` —— 关掉整批（`visible = false`，Godot 会把不
		#     可见的 `Light3D` 从光照计算里摘掉）⇒ 回答"这片堆场现在的亮度里，
		#     **有多少是这 6 颗灯照出来的**"。这是**归因**旋钮。
		#   · `--porten=<值>` —— 只改能量 ⇒ 回答"**该给多少**"。这是**剂量表**。
		#
		# ⚠️ 为什么剂量表必须走探针而不能"改常量 + 重跑"：
		# 4800 m 射程下 `Light3D` 的衰减既不是纯 1/d² 也不是线性，没有可用的
		# 解析式去预算一个 `light_energy`（我一开始按 1/d² 估的量级差了两位）。
		# 扫一次五档、把 `mean_lum` / `dark_ratio` 列出来，比"改一次猜一次"快得多，
		# 而且**留下的是一张表**，下一个调这张图的人可以直接查。
		#
		# ⚠️ 这两个旋钮是**运行时**改已建好的节点（不重建场景），所以它们与
		# `--citycam` / `--bands` 是同一类：只动"看得见什么"，不动"建了什么"。
		# 需要"建的时候就不同"的 A/B（比如比较两座城的几何）必须走常量。
		var wpl := _main.world as WorldBuilder
		if wpl != null and wpl._terrain_root != null:
			var flood := wpl._terrain_root.get_node_or_null("PortFloodLights")
			if flood == null:
				push_warning("--portlights/--porten：世界里没有 `PortFloodLights`"
					+ "（这张图的 `map.city_lights` 是关的？）")
			else:
				if _overrides.has("portlights"):
					flood.visible = int(_overrides["portlights"]) != 0
				if _overrides.has("porten"):
					var e := maxf(float(_overrides["porten"]), 0.0)
					var n := 0
					for ch in flood.get_children():
						if ch is OmniLight3D:
							(ch as OmniLight3D).light_energy = e
							n += 1
					print("[pixprobe] 港区泛光灯：%d 颗的 light_energy 设为 %.0f" % [n, e])
				# ---- `--portshadow=1`：给那 6 颗灯**开实时阴影**（1.3 批 M · 轮 7）----
				#
				# 回答的是"该不该开"，而判据**只能是量出来的**：
				# 6 盏 `omni_range = 4800 m` 的阴影在 Godot 里是 cube shadow map，
				# 代价随"覆盖范围内的几何量"走，没有任何可预算的解析式
				#（同 `CITY_PORT_FLOOD_ENERGY` 那条——射程/范围类参数只有可测量的值）。
				# 读 `frame_time.wall_ms_per_frame` 与 `draw_calls`，同时看画面。
				# ⚠️ 答案已定：**不开**（亮度 −7.5~−18.5、画面掉黑 + acne，而
				# 开销仅 +0.03~0.05 ms ⇒ 否掉它的是几何不是性能）。详见文档头。
				if _overrides.has("portshadow"):
					var sh := int(_overrides["portshadow"]) != 0
					var ns := 0
					for ch2 in flood.get_children():
						if ch2 is OmniLight3D:
							(ch2 as OmniLight3D).shadow_enabled = sh
							ns += 1
					print("[pixprobe] 港区泛光灯：%d 颗的 shadow_enabled 设为 %s" % [ns, str(sh)])
	if _overrides.has("sunpow"):
		# ---- 主光强度（`DirectionalLight3D.light_energy`）----
		# ⚠️ 只用来做**归因**：把主光拧到 0 之后"还剩下多少亮"
		# 就是环境光+自发光贡献的总量。没有这一步分不清
		# "暗面黑"是"没有填充光"还是"填充光被材质吃掉了"。
		var wl: Node = _main.world if _main.world != null else null
		if wl != null and wl.sun != null:
			wl.sun.light_energy = maxf(float(_overrides["sunpow"]), 0.0)


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


# ============================================================ 帧时间

## 帧时间。**以墙钟为准**，Godot 的 monitor 只作附注。
##
## ## 三处坑（方案 §5.3 的伪代码在本环境**全部不可用**，这里按实测改）
##   ① `Performance.RENDER_TOTAL_TIME` **在 Godot 4 里根本不存在** —— 解析期就报
##      `Cannot find member "RENDER_TOTAL_TIME"`，整个脚本加载失败。
##      Godot 4 的 `Performance.Monitor` 只有 DRAW_CALLS / PRIMITIVES / OBJECTS 三个渲染项。
##   ② `Performance.TIME_FPS` / `TIME_PROCESS` **在本机给出恒定假值**：
##      实测恒为 **3.0 fps / ~300 ms**，而同一时刻的**墙钟帧率是 387（未冻结）/ 604（冻结）**
##      —— 差 **200 倍**，而且关掉 vsync（`VSYNC_DISABLED` + `Engine.max_fps = 0`）
##      之后这两个数**一个字都不变**。拿它们当"特效开销"会得出
##      "加了特效帧时间没变"这种完全错误的结论。**唯一可信的是墙钟。**
##   ③ GPU 帧时间要走 `Viewport.get_measured_render_time_gpu()`（不是 Performance），
##      本平台返回 0（不可用）—— 所以**守卫式读取，拿不到就记 -1**，
##      **不要拿 0 当"不花时间"**（那是与事实相反的结论）。
func _frame_metrics(frames := TIME_FRAMES) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	for i in frames:
		await RenderingServer.frame_post_draw
	var dt := float(Time.get_ticks_usec() - t0) / 1000000.0
	return {
		# ---- 权威：墙钟（关 vsync 后的真实开销）----
		"wall_fps": snappedf(float(frames) / maxf(dt, 0.000001), 0.1),
		"wall_ms_per_frame": snappedf(dt * 1000.0 / float(frames), 0.001),
		"samples": frames,
		# ---- 附注：Godot monitor（**本机不可信**，见函数头 ②）----
		"monitor_fps": snappedf(Performance.get_monitor(Performance.TIME_FPS), 0.1),
		"monitor_time_process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"render_gpu_ms": _gpu_ms(),
		# ---- 这两个**可用**（随渲染状态变化，实测冻结/未冻结差 13 vs 230：
		#      差额来自 HUD 那层 2D，探针把 `canvas` 隐藏之后自然掉下来）----
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	}


func _gpu_ms() -> float:
	var vp := get_viewport()
	if vp != null and vp.has_method("get_measured_render_time_gpu"):
		var g := float(vp.call("get_measured_render_time_gpu"))
		if g > 0.0:
			return snappedf(g * 1000.0, 0.001)
	return -1.0


## 解冻后再测一次帧时间（"平时那样跑"：树在跑、HUD 那层 2D 也画）。
##
## ⚠️ **只能在取完图之后调用** —— 它会把画面状态破坏掉（机体开始飞）。
## 单独拿它做基准是没意义的（它不是可复算的画面），只用来回答
## "稳态那 1.3 ms 之外，HUD 与游戏逻辑又花了多少"。
func _frame_metrics_live() -> Dictionary:
	get_tree().paused = false
	if _main.canvas != null:
		_main.canvas.visible = true
	for i in 5:
		await get_tree().process_frame
	return await _frame_metrics()


# ============================================================ 渲染配置快照

## 把当时的画质配置抓下来 —— 报告要引用"这一版到底开了什么"，
## 而不是靠人回忆。ProjectSettings 读的是**工程设置**，`get_viewport()` 读的是
## **实际生效值**（两者在启动参数覆盖时会不同，一起记下来才可复算）。
func _render_config() -> Dictionary:
	var vp := get_viewport()
	var env: Environment = _main.world._env if _main.world != null else null
	var d := {
		"msaa_project": int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", -1)),
		"msaa_viewport": vp.msaa_3d,
		"msaa_enum_2x": Viewport.MSAA_2X,
		"msaa_enum_4x": Viewport.MSAA_4X,
		"msaa_enum_8x": Viewport.MSAA_8X,
		"deband_project": bool(ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_debanding", false)),
		"deband_viewport": vp.use_debanding,
		"screen_space_aa": vp.screen_space_aa,
		"near": _main.chase.near if _main.chase != null else 0.0,
		"far": _main.chase.far if _main.chase != null else 0.0,
		"fov": _main.chase.fov if _main.chase != null else 0.0,
	}
	if env != null:
		d["env"] = {
			"tonemap": env.tonemap_mode,
			"tonemap_white": env.tonemap_white,
			"exposure": _read_env(env, "tonemap_exposure"),
			"ssao": env.ssao_enabled,
			"ssil": env.ssil_enabled,
			"ssr": env.ssr_enabled,
			"volumetric_fog": env.volumetric_fog_enabled,
			# ⚠️ 体积雾的**光程上限**必须记进报告：它是"海雾在玩家视角看不见"
			# 的那条隐形闸门（默认 4000 m，而画面下沿的射线要走到 5.9 km 才进雾板）。
			# 不记的话，`--foglen` 拧没拧上、拧到多少，事后从 JSON 里看不出来。
			"volumetric_fog_length": _read_env(env, "volumetric_fog_length"),
			"volumetric_fog_detail_spread": _read_env(env, "volumetric_fog_detail_spread"),
			"volumetric_fog_density": _read_env(env, "volumetric_fog_density"),
			"volumetric_fog_albedo": env.volumetric_fog_albedo,
			"volumetric_fog_emission": env.volumetric_fog_emission,
			"fog_density": env.fog_density,
			"fog_aerial": env.fog_aerial_perspective,
			"glow": env.glow_enabled,
			"glow_intensity": env.glow_intensity,
			"glow_bloom": env.glow_bloom,
			"glow_hdr_threshold": env.glow_hdr_threshold,
			"glow_levels": _glow_levels(env),
			"adjustment": env.adjustment_enabled,
			"adjustment_contrast": _read_env(env, "adjustment_contrast"),
			"adjustment_saturation": _read_env(env, "adjustment_saturation"),
			"ambient_energy": env.ambient_light_energy,
			# ⚠️ 这三个是**批 K · 轮 1② 补的**，理由是上一条实测教训：
			# `ambient_light_energy` 单独记下来会误导 —— 它在
			# `sky_contribution = 1.0` 时是死值。**必须把它的"生效前提"
			# 一起记**，否则事后看 JSON 会得出"environment 调了 0.85，
			# 所以地上有填充光"这种与画面相反的错误结论。
			"ambient_source": env.ambient_light_source,
			"ambient_sky_contribution": _read_env(env, "ambient_light_sky_contribution"),
			"ambient_color": env.ambient_light_color,
		}
	# ⚠️ `sun` 在 WorldBuilder 上，不在 main 上（main 只转发尺度常量，见它的注释）
	var sun: DirectionalLight3D = _main.world.sun if _main.world != null else null
	if sun != null:
		d["sun"] = {
			"energy": sun.light_energy,
			"shadow_max_distance": sun.directional_shadow_max_distance,
			"shadow_bias": sun.shadow_bias,
			"shadow_normal_bias": sun.shadow_normal_bias,
			"light_angular_distance": sun.light_angular_distance,
		}
	if _main.cel_quad != null:
		d["cel_post_visible"] = _main.cel_quad.visible
		# ---- ⚠️⚠️ 批 K · 轮 3：`cel_quad` **不参与渲染** —— 把实例状态全打出来 ----
		#
		# 为什么必须打到 JSON 里而不是靠推理：六发实测（`--celpaint=255,0,0` 纯红、
		# `--celshape=1` 另起新实例纯绿）**PNG 全部 1,688,694 字节、一模一样**，
		# 连 `--cel=0` 也一样 ⇒ 面片确定没画。但"没画"有**至少四种**互斥的原因，
		# 而下一条动作完全不同：
		#   · 不在可见树的 visible 链上（某个祖先 invisible）⇒ 改挂载点；
		#   · 相机 `cull_mask` 与实例 `layers` 不匹配 ⇒ 改图层；
		#   · 被视锥/近平面剔除（相机的 near 比面片距离还大）⇒ 改距离或 margin；
		#   · 材质/shader 没生效（fallback 成透明）⇒ 改材质。
		# 这些**光看源码一条都分不出来**（源码里 `visible = true`、图层默认、margin 巨大、
		# 材质也挂上了 —— 全是对的）。所以把可观测量直接落盘。
		var cq: MeshInstance3D = _main.cel_quad
		var ccam: Camera3D = _main.chase
		var cel_d: Dictionary = {
			"visible": cq.visible,
			"visible_in_tree": cq.is_visible_in_tree(),
			"parent": String(cq.get_parent().name) if cq.get_parent() != null else "<无>",
			"layers": cq.layers,
			"extra_cull_margin": cq.extra_cull_margin,
			"mesh_surfaces": cq.mesh.get_surface_count() if cq.mesh != null else -1,
			"aabb": cq.get_aabb(),
			"global_pos": cq.global_position,
			"has_override": cq.material_override != null,
			"mat_priority": (cq.material_override.render_priority
				if cq.material_override is Material else -9999),
		}
		if ccam != null:
			cel_d["cam_pos"] = ccam.global_position
			cel_d["cam_dist"] = ccam.global_position.distance_to(cq.global_position)
			cel_d["cam_near"] = ccam.near
			cel_d["cam_far"] = ccam.far
			cel_d["cam_cull_mask"] = ccam.cull_mask
			cel_d["cam_current"] = ccam.current
			cel_d["cam_in_view"] = ccam.is_position_in_frustum(cq.global_position)
		d["cel_post"] = cel_d
	# ---- 绿洲实况（批 K · 轮 1③）----
	#
	# ⚠️ 这两个数是**唯一在"无头"与"真渲染"两侧都读得到**的绿洲量
	#（`MultiMesh.get_instance_transform()` 在无头下读回来全是单位变换，
	#  所以 `_build_desert_oasis()` 特意把 CPU 侧的位姿留在了 `desert_tree_xf`）。
	# 不记的话，"树到底撒了没撒、撒了几棵"就只能靠看图 ——
	# 而"看图"在一张 1600×900 的高空俯视图上根本数不清 1.7 万棵树。
	if _main.world != null:
		var wb := _main.world as WorldBuilder
		if wb != null:
			d["oasis"] = {
				"sites": wb.desert_oasis_sites.size(),
				"trees": wb.desert_tree_xf.size(),
				"mask_ready": wb._veg_mask_tex != null,
				"scale": wb.desert_tree_scale,
				"census": wb.desert_chain_census(),
			}
	return d


func _read_env(env: Environment, key: String) -> float:
	var v: Variant = env.get(key)
	return float(v) if v != null else -1.0


## 世界材质（地表 / 海面 / 云 / 城市立面）里那几个 1.2.3 批 E/G 的 uniform 的**实际值**。
##
## ⚠️ 记的是"材质上现在是什么"，不是"命令行请求了什么" —— 请求值与实况值的差
## 正是"开关没接上"这一类 bug 的唯一可见形态。
##
## ⚠️⚠️ **两个 Godot 陷阱在这里叠在一起**（实测：报告整整静默空了 5/6 次）：
##
##   ① **`get_shader_parameter()` 读不到 shader 源码里的默认值**。一个 uniform 只要
##       GDScript 从没对它调用过 `set_shader_parameter()`，读回来就是 `null` ——
##       `sun_shade` 正是这种（它靠 `cloud.gdshader` 里声明的 `= 1.0`）。
##       所以这里**用 `_pnum()` 把 null 原样记成 JSON null**，并把它解读为
##       "未显式设置 ⇒ 走 shader 默认值"，而不是当成 0（那会得出相反的结论）。
##   ② **`float(null)` 会抛 `Invalid call. Nonexistent 'float' constructor`**，
##       函数**中途异常返回 null** —— 而返回类型写的是 `-> Dictionary`，
##       于是 Godot 把这个 null **悄悄变成空字典 `{}`**：调用方分不出
##       "报告就是空的"与"报告炸了"。**声明返回类型会把运行时错误洗成合法空值。**
##       所以下面每个数都走 `_pnum()`，并且在最后加一道"空报告 = 至少留一条错误"的兜底。
func _world_mat_report() -> Dictionary:
	var w: Node = _main.world if _main.world != null else null
	if w == null:
		return {"error": "world == null"}
	var d := {}
	# 地表：逐份列出（不同地表用不同频率，只看"开没开"会漏掉"频率传错"）
	var terr := []
	for m in w._terrain_mats:
		terr.append({
			"detail_strength": _pnum(m.get_shader_parameter("detail_strength")),
			"detail_grain": _pnum(m.get_shader_parameter("detail_grain")),
			"detail_scale": _pnum(m.get_shader_parameter("detail_scale")),
			"use_vertex_color": m.get_shader_parameter("use_vertex_color"),
		})
	d["terrain_count"] = w._terrain_mats.size()
	d["terrain"] = terr
	if w._ocean_mat != null:
		d["ocean"] = {
			"crest_sss": _pnum(w._ocean_mat.get_shader_parameter("crest_sss")),
			"moon_dir": str(w._ocean_mat.get_shader_parameter("moon_dir")),
			"glitter_strength": _pnum(w._ocean_mat.get_shader_parameter("glitter_strength")),
			# 相机是不是真的在逆光位（`back = -dot(view_dir, moon_dir)` 的正负号）
			"view_dot_moon": _view_dot_moon(),
		}
	else:
		d["ocean"] = null
	# 贴海薄雾（1.2.3 批 J）：**必须记**，理由与 `world_mats` 整节相同 ——
	# "`--mist=0` 改了 `visible`" 与 "它真的让那一层不画了" 是两件事。
	# 少了这一节，一个"开关没接上"的 A/B 会表现为**没有像素差**，
	# 而结论会被写成"薄雾看不见" —— 正好把因果说反了。
	# ⚠️ 它**不在** `world_mats` 的其余各节里：`FogVolume` 不是"世界里的某个材质"，
	# 而且关它走的是 `visible = false`（不是把密度设 0）⇒ 关着时材质值一个字都不变。
	# 所以这一节看的是 `visible` / `size` / `bottom_y`，不是密度。
	d["sea_mist"] = _sea_mist_report(w)
	var clouds := []
	for m in w._cloud_mats:
		clouds.append({
			"sun_shade": _pnum(m.get_shader_parameter("sun_shade")),
			"sun_dir": str(m.get_shader_parameter("sun_dir")),
		})
	d["cloud_count"] = w._cloud_mats.size()
	d["cloud"] = clouds
	var facades := []
	for k in w._city_facade_cache.keys():
		var m: ShaderMaterial = w._city_facade_cache[k]
		facades.append({
			"key": str(k),
			"facade_strength": _pnum(m.get_shader_parameter("facade_strength")),
			"metallic_value": _pnum(m.get_shader_parameter("metallic_value")),
			"pane_rough": _pnum(m.get_shader_parameter("pane_rough")),
			"bay_w": _pnum(m.get_shader_parameter("bay_w")),
			# 淡出两端**必须逐份记**：它们是 1.2.3 批 G 唯一由 `--fadefar` 拧的项，
			# 漏记就会出现"报告说 970/1950、画面却是永不淡出"这种对不上的账。
			"fade_near": _pnum(m.get_shader_parameter("facade_fade_near")),
			"fade_far": _pnum(m.get_shader_parameter("facade_fade_far")),
		})
	d["facade_count"] = w._city_facade_cache.size()
	d["facade"] = facades
	d["city_body_count"] = w._city_body_count
	d["facade_dist"] = _facade_dist_report()
	if d.is_empty():
		# 兜底：空报告必须**能被看出来是异常**，不能长得像"没有东西可报"
		d["error"] = "空报告（不该发生）"
	return d


## 相机到城区楼体的**实测距离分布** —— 城市立面到底可不可读，全由这个数决定。
##
## ⚠️ 为什么非要有这一节：立面 shader 里 `k_near = wall * pane * near_f`，
## 而 `near_f = 1 - smoothstep(facade_fade_near, facade_fade_far, view_dist)`。
## 于是 `view_dist >= facade_fade_far` 时 **`k_near` 恒为 0 ⇒ `ALBEDO` 逐位相当于
## "立面全关"**（只剩粗糙度那一路还有差）。第一轮实测 `--facade=0` 只差 −0.0002 时，
## 光看像素表**分不清**两件完全不同的事：
##   ① 相机离城区**全程都在淡出之外** ⇒ 立面本来就不画。这**不是 bug**，
##      是"这个机位看不到窗格"——该动的是距离数（或者该承认这个机位测不了）；
##   ② 窗格**根本没附着到楼体上**（`_add_box` 的 facade 传参断了）——那是真 bug。
## 两者在 A/B 表上**都**长成一片 `+0.0000`。
##
## 把距离量出来，判据就退化成一行算术：`near` 计数为 0 ⇒ 是①，不是②。
## 这正是本轮"记录的条件必须等于实际发生的条件"的第二次应用
##（第一次是靶场被静默回退到 pacific）。
func _facade_dist_report() -> Dictionary:
	var w: Node = _main.world if _main.world != null else null
	var ch: Camera3D = _main.chase
	if w == null or ch == null:
		return {"error": "world 或 chase 为空"}
	# 楼体挂在 `_terrain_root` 下，名字带类别前缀（与套件 `_first_material` 同口径，
	# 递归找是因为体量可能嵌在分区子节点里 —— 只扫一层会漏）。
	var pos := _city_body_positions(w._terrain_root)
	if pos.is_empty():
		return {"error": "没找到任何楼体节点（前缀过滤没匹配上）"}
	var cam := ch.global_position
	var ds := []
	for p in pos:
		ds.append(cam.distance_to(p))
	ds.sort()
	# 淡出两端**从材质上读**（读不到才退回 shader 默认值）——
	# 这样 `--fadefar` 拧过之后，报告里的判据也跟着变，不会拿旧数去解释新画面。
	var near_v: Variant = _facade_uniform(w, "facade_fade_near")
	var far_v: Variant = _facade_uniform(w, "facade_fade_far")
	var near_f := float(near_v) if near_v != null else 970.0
	var far_f := float(far_v) if far_v != null else 1950.0
	var c_in := 0    # 距离 < 近端 ⇒ near_f = 1，立面**满对比**
	var c_mid := 0   # 近端~远端之间 ⇒ 部分淡出
	var c_out := 0   # 距离 > 远端 ⇒ near_f = 0，**立面等于没开**
	var sum_nf := 0.0
	for d in ds:
		var dd := float(d)
		if dd <= near_f:
			c_in += 1
			sum_nf += 1.0
		elif dd >= far_f:
			c_out += 1
		else:
			c_mid += 1
			# 与 shader 同一个 smoothstep 口径（不抄公式就没法归因）
			sum_nf += 1.0 - smoothstep(near_f, far_f, dd)
	var verdict := ""
	if c_in == 0 and c_mid == 0:
		verdict = "淡出吃掉（%d/%d 全在淡出之外）⇒ 该调距离，不是没接线" % [c_out, ds.size()]
	elif c_out == 0 and c_mid == 0:
		verdict = "全部满对比（%d 个都在近端内）⇒ 关掉立面应当立刻可见" % c_in
	else:
		verdict = "混合（近 %d / 淡出中 %d / 淡出外 %d）" % [c_in, c_mid, c_out]
	return {
		"count": ds.size(),
		"min": snappedf(float(ds[0]), 0.1),
		"median": snappedf(float(ds[ds.size() / 2]), 0.1),
		"max": snappedf(float(ds[ds.size() - 1]), 0.1),
		"fade_near": near_f,
		"fade_far": far_f,
		"in_count": c_in,       # near_f = 1
		"mid_count": c_mid,     # 0 < near_f < 1
		"out_count": c_out,     # near_f = 0 ⇒ ALBEDO 与"关掉立面"逐位相同
		"mean_near_f": snappedf(sum_nf / float(ds.size()), 0.001),
		"verdict": verdict,
	}


## 递归收集楼体节点（前缀过滤口径**只写在这里一处**）。
##
## 每项是 `{"pos": 节点原点, "top": 世界包围盒的顶面中心, "size": 世界包围盒尺寸}`。
##
## ⚠️ `top` 不是多余的：楼体尺寸烘在实例 scale 上，`global_position` 只是**节点原点**
##（在楼的中部）。第一版 `--citycam` 瞄的就是 `pos`，于是 `--citycam=300` 对一栋
## 上百米高的楼**直接把相机塞进了墙里**（实拍整帧 `mean_lum = 0.0032`，近黑）。
## 用包围盒顶面中心瞄准，才是"从外面看这栋楼"。
func _city_frames(root: Node) -> Array:
	var prefixes := ["Tower_", "Podium_", "Crown_", "Block_", "Slab_", "Tower", "Podium"]
	var out := []
	if root == null:
		return out
	var stack := [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var nm := String(n.name)
		var hit := false
		for p in prefixes:
			if nm.begins_with(p):
				hit = true
				break
		if hit:
			var n3 := n as Node3D
			if n3 != null:
				out.append(_node_frame(n3))
		for c in n.get_children():
			stack.append(c)
	return out


## 一个节点（或它第一个 MeshInstance3D 子节点）的世界包围盒摘要。
func _node_frame(n3: Node3D) -> Dictionary:
	var pos := n3.global_position
	var top := pos
	var size := Vector3.ZERO
	var mi: MeshInstance3D = null
	for c in n3.get_children():
		mi = c as MeshInstance3D
		if mi != null:
			break
	if mi != null:
		var aabb := mi.get_aabb()
		var xf := mi.global_transform
		# 八个角都投到世界空间再取包围盒（实例带旋转，只投 min/max 两个角会错）
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for i in 8:
			var corner := aabb.get_endpoint(i)
			var wp := xf * corner
			lo = Vector3(minf(lo.x, wp.x), minf(lo.y, wp.y), minf(lo.z, wp.z))
			hi = Vector3(maxf(hi.x, wp.x), maxf(hi.y, wp.y), maxf(hi.z, wp.z))
		size = hi - lo
		top = Vector3((lo.x + hi.x) * 0.5, hi.y, (lo.z + hi.z) * 0.5)
	return {"pos": pos, "top": top, "size": size}


## 深度优先收集**所有**名字以 `prefix` 开头的节点（`--aim` 用）。
##
## ⚠️ 刻意**返回全部而不是第一个**：`world_builder.gd` 里一个地标往往是一个
## `StaticBody3D` 套一个 `MeshInstance3D`，两者**各有一份坐标**。只取第一个
## 会随机拿到其中一个 —— 而"视觉在哪 / 碰撞在哪"不一致本身就是要抓的 bug。
## （`_city_fuji_tv` 就栽在这上面：见 `--aim` 那段注释。）
##
## 用前缀而不是全名：容得下 `FujiShaft-1` 这类带后缀的名字，
## 也不要求调用方记得住到底是 `FujiSphere` 还是 `FujiSphereBody`。
func _find_all_by_prefix(root: Node, prefix: String) -> Array:
	var out := []
	if root == null or prefix.is_empty():
		return out
	var stack := [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if String(n.name).begins_with(prefix):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


## 某个节点**实际占着的位置** —— `--aim` 的坐标来源（1.3 批 M · 轮 5）。
##
## ⚠️ 为什么不能直接用 `global_position`：`MultiMeshInstance3D` 的节点原点是
## **恒为 (0, 0, 0) 的**，真正的位置在 `multimesh` 的每条实例变换里。
## 于是 `--aim=PortStacks:420` 会把相机搬到**世界原点上方 58 m**，
## 拍回来的是一张"不知道哪里的空地" —— 而且 **`err=0`、png 体积正常、
## 零警告**，从日志上完全看不出机位错了（本轮实测踩到）。
## 这个工程里"想看一眼"的东西有一大半是 MultiMesh
##（`PortStacks` / `CityWindows` / `CityBeacons` / `CityLamps` / `SandsShipLights`
## / `PortCraneLights` / `DesertOasis*`），所以这一处必须修。
##
## 取**实例质心**而不是第 0 个实例：这些批次动辄几百个实例、随机撒在一个大范围里，
## 第 0 个可能落在边角上；质心才代表"这一批东西的中心"，
## 也正是"这批东西在哪儿"这个问题的答案。
func _aim_point(n: Node3D) -> Vector3:
	var mm := n as MultiMeshInstance3D
	if mm == null or mm.multimesh == null or mm.multimesh.instance_count <= 0:
		return n.global_position
	var c := Vector3.ZERO
	var ic := mm.multimesh.instance_count
	for i in ic:
		c += mm.multimesh.get_instance_transform(i).origin
	return mm.global_transform * (c / float(ic))


## 只是上面那批的位置列表（距离统计用）。
func _city_body_positions(root: Node) -> Array:
	var out := []
	for f in _city_frames(root):
		out.append(f["pos"])
	return out


## 从任一份立面材质上读回某个 uniform（材质为空就返回 null）。
func _facade_uniform(w: Node, name: String) -> Variant:
	for m in w._city_facade_cache.values():
		var v: Variant = m.get_shader_parameter(name)
		if v != null:
			return v
	return null


## 数字读回：`null` 原样返回为 `null`（JSON null = "未显式设置，走 shader 默认值"）。
## 见 `_world_mat_report()` 头部的陷阱 ②：直接写 `float(x)` 会炸，
## 而炸了的函数在 `-> Dictionary` 返回类型下会变成空字典。
static func _pnum(v: Variant) -> Variant:
	return float(v) if v != null else null


## 相机视线与天体方向的夹角判据，**两种口径都报**（逆光类效果的可读性诊断）。
##
## ⚠️ **判据必须与 shader 里那个公式同口径**，否则诊断会误导：
## `ocean.gdshader` 第一版用三维 `-dot(view_dir, moon_dir)`，实测在本工程固定的
## 58° 月亮下 `dot3d` 恒为正（水平反向被垂直同向抵消）⇒ 权重 0；改成水平口径后
## 才是有效的那个数。所以这里两个都给，哪一个在主导一眼可见。
##
## `-dot > 0` 才是逆光；这个数在 0 附近或为负，就说明"浪尖透光"这一类按逆光加权的效果
## **在当前机位上数学上等于 0** —— 与"没接线"完全是两回事，必须能在数据里区分。
func _view_dot_moon() -> Dictionary:
	var w: Node = _main.world
	var ch: Camera3D = _main.chase
	if w == null or ch == null or w.sun == null:
		return {"dot3d": null, "dot_horiz": null}
	var sd := WorldBuilder.celestial_dir(w.sun.rotation_degrees).normalized()
	var cam := ch.global_position
	# 取画面正前方、地平线以下约 20° 的一点当地表采样点（海面就在那儿）
	var fwd := -ch.global_transform.basis.z
	var probe_pt := cam + fwd * 3000.0 + Vector3(0.0, -1200.0, 0.0)
	var view_dir := (cam - probe_pt).normalized()
	var vf := Vector3(view_dir.x, 0.0, view_dir.z)
	var mf := Vector3(sd.x, 0.0, sd.z)
	var horiz := 0.0
	if vf.length() > 0.0001 and mf.length() > 0.0001:
		horiz = -vf.normalized().dot(mf.normalized())
	return {
		"dot3d": snappedf(view_dir.dot(sd), 0.0001),
		"dot_horiz": snappedf(horiz, 0.0001),
		"back_horiz_sq": snappedf(horiz * horiz, 0.0001),
	}


func _glow_levels(env: Environment) -> Array:
	var a: Array = []
	for i in range(1, 8):
		var v: Variant = env.get("glow_levels/%d" % i)
		a.append(float(v) if v != null else -1.0)
	return a


# ============================================================ 像素统计

## 机体材质实例数（方案 §2.6 的判据）。**这一项无头也能测**，顺手在这里一起记，
## 这样"画质批次"的 JSON 里同时有像素与材质两张表。
## 贴海薄雾的**实况**（1.2.3 批 J）。
##
## ⚠️ 为什么单列一节，而不是塞进 `world_mats` 的其余部分：
## `FogVolume` + `FogMaterial` 不是"世界里的某个材质"，而关它的方式是
## **`visible = false`**（不是把密度设 0 —— 密度 0 的 `FogVolume` 仍要参与 raymarch）。
## 于是"关"的那一半**材质值一个字都不变**，`world_mats` 两两相同在这里是**正常**的，
## 不能当成"开关没接上"。真正要看的三个数是：
##   · `visible`  —— false ⇒ 这一层不参与 raymarch（非太平洋图零代价）
##   · `size`     —— 全尺寸（`FogVolume.size` 是**全尺寸**不是半尺寸）
##   · `bottom_y` —— 应当是 0（底面贴水面）；非 0 说明中心没按 `h/2` 抬
func _sea_mist_report(w: Node) -> Variant:
	var fv: FogVolume = w._sea_mist
	if fv == null:
		return null
	var fm: FogMaterial = fv.material as FogMaterial
	if fm == null:
		return {"visible": fv.visible, "error": "material 不是 FogMaterial"}
	return {
		"visible": fv.visible,
		"shape": fv.shape,
		"size": str(fv.size),
		"pos_y": _pnum(fv.position.y),
		"bottom_y": _pnum(fv.position.y - fv.size.y * 0.5),
		"density": _pnum(fm.density),
		"albedo": str(fm.albedo),
		"emission": str(fm.emission),
		"height_falloff": _pnum(fm.height_falloff),
		"edge_fade": _pnum(fm.edge_fade),
	}


func _shade_mat_report() -> Dictionary:
	var d := {"player": 0, "enemy": 0, "total": 0}
	if _main.player != null:
		d["player"] = _main.player._shade_mats.size()
	if _main.enemy != null:
		d["enemy"] = _main.enemy._shade_mats.size()
	d["total"] = int(d["player"]) + int(d["enemy"])
	d["expect_messer_fix"] = "梅萨 157 surface ⇒ 去重后应远小于 157"
	return d


func _num(node: Node, prop: String) -> float:
	if node == null:
		return -1.0
	var v: Variant = node.get(prop)
	return float(v) if v != null else -1.0


## 全屏 + 中心框 + 九宫格。
##
## 中心框（屏幕正中 40%）是**机体的投影位置** —— 相机钉在机体正后上方，
## 机体恒在画面中央，所以"金属度有没有把高光提上来"看这一格最直接（方案 §2.2 的判据）。
func _all_regions(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	# ⚠️ `get_data()` **只调一次**：它每次返回一份新的 PackedByteArray（千万字节级），
	# 十个区域各取一次 = 十份拷贝，实测能把统计拖到几百毫秒。传下去共用。
	var data := img.get_data()
	var d := {
		"full": _stats(data, w, Rect2i(0, 0, w, h)),
		"center": _stats(data, w, Rect2i(int(w * 0.30), int(h * 0.30), int(w * 0.40), int(h * 0.40))),
	}
	var cw := int(w / 3.0)
	var ch := int(h / 3.0)
	for row in 3:
		for col in 3:
			var x := col * cw
			var y := row * ch
			# 最后一列/行吃掉除不尽的余数。
			# ⚠️ 必须写 `w - x` / `h - y`，不能写 `w - cw` / `h - ch` ——
			# 后者比实际剩余的大，矩形溢出到图外 → 逐像素读越界
			#（实测：`Out of bounds get index` + 下半屏三个格子全空）。
			var ww := (w - x) if col == 2 else cw
			var hh := (h - y) if row == 2 else ch
			d["g%d%d" % [row, col]] = _stats(data, w, Rect2i(x, y, ww, hh))
	return d


## 一个矩形区域的可复算统计量。`data` 是整张图的 RGBA8 字节（调用方取一次共用）。
##
## 亮度用 Rec.709（与 `cel_post.gdshader` 里量化用的那组权重一致 ——
## 同一条画面在 shader 和探针里必须是同一个"亮度"，否则判据对不上）。
func _stats(data: PackedByteArray, img_w: int, r: Rect2i) -> Dictionary:
	var sum_r := 0.0
	var sum_g := 0.0
	var sum_b := 0.0
	var sum_l := 0.0
	var sum_l2 := 0.0
	var n := 0
	var hl := 0
	var dark := 0
	var edge_n := 0
	var edge_d := 0
	var hist := PackedInt32Array()
	hist.resize(HIST_BINS)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			# FORMAT_RGBA8：每像素 4 字节
			var o := (y * img_w + x) * 4
			var cr := float(data[o]) / 255.0
			var cg := float(data[o + 1]) / 255.0
			var cb := float(data[o + 2]) / 255.0
			var lum := 0.2126 * cr + 0.7152 * cg + 0.0722 * cb
			sum_r += cr
			sum_g += cg
			sum_b += cb
			sum_l += lum
			sum_l2 += lum * lum
			n += 1
			if lum >= HL_LUM:
				hl += 1
			if lum < DARK_LUM:
				dark += 1
			hist[clampi(int(lum * HIST_BINS), 0, HIST_BINS - 1)] += 1
			# 边缘密度：与右邻像素的亮度差（横向一阶）
			if x + 1 < r.end.x:
				var o2 := (y * img_w + x + 1) * 4
				var l2 := 0.2126 * float(data[o2]) / 255.0 \
					+ 0.7152 * float(data[o2 + 1]) / 255.0 \
					+ 0.0722 * float(data[o2 + 2]) / 255.0
				edge_d += 1
				if absf(l2 - lum) > EDGE_THRESHOLD:
					edge_n += 1
	if n == 0:
		return {}
	var mean_l := sum_l / float(n)
	var var_l := maxf(sum_l2 / float(n) - mean_l * mean_l, 0.0)
	# 直方图"被用到的组数" —— 色带 = 相邻组之间出现空档，用这个数看趋势
	var used := 0
	for b in hist:
		if b > 0:
			used += 1
	return {
		"px": n,
		"mean_r": snappedf(sum_r / float(n), 0.0001),
		"mean_g": snappedf(sum_g / float(n), 0.0001),
		"mean_b": snappedf(sum_b / float(n), 0.0001),
		"mean_lum": snappedf(mean_l, 0.0001),
		"stddev_lum": snappedf(sqrt(var_l), 0.0001),
		"highlight_ratio": snappedf(float(hl) / float(n), 0.00001),
		"dark_ratio": snappedf(float(dark) / float(n), 0.00001),
		"edge_density": snappedf(float(edge_n) / maxf(float(edge_d), 1.0), 0.00001),
		"hist_bins_used": used,
		"hist": hist,
	}


# ============================================================ A/B 差异表

## 与一份基线 JSON 对比，输出 `[基线值, 本次值, 差值]` 三元组表。
##
## ⚠️ 差异只能说明**"变了多少"**，不能说明"变好了"（见文件头）。
## 而且它只在两份的**渲染代码**相同时才可比 —— 这正是"基线随渲染改动必然失效"的含义，
## 所以本工具只做 A/B，不做永久阈值断言（方案 §5.2）。
func _diff_against(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"error": "读不到基线：%s" % path}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"error": "基线不是合法 JSON 对象：%s" % path}
	var base: Dictionary = parsed
	var d := {
		"baseline_tag": base.get("tag", "?"),
		"baseline_stamp": base.get("stamp", "?"),
		"metrics": {},
		"regions": {},
	}
	var mine_ft: Dictionary = _out.get("frame_time", {})
	var base_ft: Dictionary = base.get("frame_time", {})
	for key in ["wall_ms_per_frame", "wall_fps", "draw_calls", "primitives"]:
		d["metrics"][key] = _pair(float(base_ft.get(key, 0.0)), float(mine_ft.get(key, 0.0)))
	d["metrics"]["shade_mats_total"] = _pair(
		float((base.get("shade_mats", {}) as Dictionary).get("total", 0)),
		float((_out.get("shade_mats", {}) as Dictionary).get("total", 0)))
	var keys := ["full", "center", "g00", "g01", "g02", "g10", "g11", "g12", "g20", "g21", "g22"]
	var fields := ["mean_lum", "stddev_lum", "highlight_ratio", "edge_density",
		"mean_r", "mean_g", "mean_b", "hist_bins_used"]
	var base_regions: Dictionary = base.get("regions", {})
	var my_regions: Dictionary = _out.get("regions", {})
	for k in keys:
		var b: Dictionary = base_regions.get(k, {})
		var m: Dictionary = my_regions.get(k, {})
		var row := {}
		for fd in fields:
			row[fd] = _pair(float(b.get(fd, 0.0)), float(m.get(fd, 0.0)))
		d["regions"][k] = row
	return d


## `[旧, 新, 差]`。差 = 新 − 旧，正数表示变大。
func _pair(old_v: float, new_v: float) -> Array:
	return [snappedf(old_v, 0.00001), snappedf(new_v, 0.00001), snappedf(new_v - old_v, 0.00001)]
