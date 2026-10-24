class_name SuiteIntro
extends RefCounted
## 开场动画（进游戏一开头播的那一段）。
##
## ⚠️ 命名按**主题**，不占轮次号 —— 见 `test_runner.gd` 注册表里的红字：
## 本仓库有并行会话，两边都按轮次占号时撞过一次，一个套件被同名文件**整个覆盖**
## 而 runner 照样绿。
##
## ## 需求（用户原话）
##   ① 「我们做一个进游戏一开头就会播的动画系统」；
##   ② 「右下角有小字提醒按任意键跳过进入游戏」；
##   ③ 「有 20% 的几率在播动画 2（马夫蒂劫持演说）」。
##
## ## 这一套钉的是什么
##   1. **概率**：`IntroPlaylist.pick_index()` 是纯函数 ⇒ 20% 可以**逐点验**边界
##      （0.799 → 第 0 支，0.800 → 第 1 支）。这不是"跑一万次看分布"。
##   2. **素材真的在**：两个 `.ogv` 存在、够大、能 `load()` 成 `VideoStreamTheora`。
##      Godot 核心**只认 Ogg Theora**，所以"扩展名是 .ogv"本身是一条格式门。
##   3. **谁该播**：`should_play()` 的四条否决逐条验；`should_play_now()` 在无头下必须是 false。
##   4. **回归保护**（最容易出事的一条）：无头里 `_show_menu()` 仍必须**同步**跑完 ——
##      否则一批"实例化完主场景就断言菜单状态"的用例会集体变红。
##   5. **接线**：`main.gd` 里动画确实挡在 `_show_menu()` 前面，且两条收尾路径都对。

## 取某个顶层函数的**函数体**（从 `header` 那行到下一个顶层 `func`）。
##
## ⚠️ 自己写而不是用 `SuiteUiStyle` 里的：那一份是给"线宽实参"用的，落点不一样。
## 这里扫的是 `_code()`（已剥注释）的产物，所以要接收剥好注释的源码。
static func _body(src: String, header: String) -> String:
	var i := src.find(header)
	if i < 0:
		return ""
	var lines := src.substr(i).split("\n")
	var out: Array = [str(lines[0])]
	for k in range(1, lines.size()):
		var s := str(lines[k])
		if s.begins_with("func ") or s.begins_with("static func "):
			break
		out.append(s)
	return "\n".join(out)


static func run(t: T, host: Node) -> void:
	# ---------------------------------------------------------------- 1 选片表
	t.suite("开场动画 / 选片表（纯函数）")
	t.eq(IntroPlaylist.CLIPS.size(), 2,
		"表里恰好两支：开头动画 + 马夫蒂劫持演说")
	t.near(IntroPlaylist.total_weight(), 1.0, IntroPlaylist.WEIGHT_EPS,
		"权重和收敛到 1.0（小于 1 会让尾部 roll 被兜到最后一支、大于 1 会让最后一项抽不到）")
	t.near(float(IntroPlaylist.CLIPS[1]["weight"]), 0.20, IntroPlaylist.WEIGHT_EPS,
		"第 2 支（马夫蒂劫持演说）的权重就是用户要的 20%")
	t.eq(str(IntroPlaylist.CLIPS[0]["id"]), "op", "第 1 支是开头动画")
	t.eq(str(IntroPlaylist.CLIPS[1]["id"]), "mafty", "第 2 支是马夫蒂劫持演说")

	# —— 20% 的**边界**：这是整条需求里唯一"算错了也看不出来"的地方，所以逐点钉死。
	t.eq(IntroPlaylist.pick_index(0.0), 0, "roll=0.0 → 开头动画")
	t.eq(IntroPlaylist.pick_index(0.5), 0, "roll=0.5 → 开头动画")
	t.eq(IntroPlaylist.pick_index(0.799), 0, "roll=0.799（差一点到 0.8）→ 仍是开头动画")
	t.eq(IntroPlaylist.pick_index(0.80), 1, "roll=0.80（正好踩线）→ 换成马夫蒂劫持演说")
	t.eq(IntroPlaylist.pick_index(0.999), 1, "roll=0.999 → 马夫蒂劫持演说")
	t.eq(IntroPlaylist.pick_index(1.0), 1,
		"roll=1.0（理论上不出现）兜到最后一支，绝不返回越界下标")
	t.eq(IntroPlaylist.pick_index(-0.5), 0, "负 roll 也落在第 1 支，不越界")

	t.eq(IntroPlaylist.clip_at(-9), IntroPlaylist.CLIPS[0], "clip_at 负下标夹取")
	t.eq(IntroPlaylist.clip_at(99), IntroPlaylist.CLIPS[1], "clip_at 越界夹取")
	t.eq(str(IntroPlaylist.pick_random().get("id", "")).is_empty(), false,
		"pick_random 返回完整片目（有 id）")

	# 格式门：Godot 核心只认 Ogg Theora，扩展名写错就永远播不出来。
	var bad_ext: Array = []
	for c: Dictionary in IntroPlaylist.CLIPS:
		if not str(c["path"]).ends_with(".ogv"):
			bad_ext.append(str(c["id"]))
	t.eq(bad_ext.size(), 0,
		"每一支素材都是 .ogv（Godot 核心只认 Ogg Theora，mp4/webm 一律不行）")
	t.eq(str(IntroPlaylist.CLIPS[0]["path"]), "res://assets/video/intro_op.ogv",
		"第 1 支指向开头动画的转码产物")
	t.eq(str(IntroPlaylist.CLIPS[1]["path"]), "res://assets/video/intro_mafty.ogv",
		"第 2 支指向马夫蒂劫持演说的转码产物")

	# ---------------------------------------------------------------- 2 素材门
	t.suite("开场动画 / 素材门（真的转码进来了）")
	t.ok(IntroPlaylist.has_any_clip(), "has_any_clip() 为真（至少一支素材在位）")
	for c: Dictionary in IntroPlaylist.CLIPS:
		var path := str(c["path"])
		t.ok(ResourceLoader.exists(path), "素材在位：%s" % path)
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			t.ok(false, "打不开素材：%s" % path)
			continue
		var sz := f.get_length()
		f.close()
		t.gt(float(sz), 1000000.0,
			"%s 大于 1 MB（不是占位空文件），实为 %.1f MB" % [str(c["id"]), float(sz) / 1048576.0])
	# 只把小的那支真的 load 一次：65 MB 那支在这里解一遍纯属白烧时间，
	# 而"能不能 load"这件事两支同源（同一套转码参数、同一个解码器）。
	var small := load("res://assets/video/intro_op.ogv")
	t.ok(small is VideoStreamTheora,
		"开头动画能 load 成 VideoStreamTheora（解码器在位，不是只认了扩展名）")

	# ---------------------------------------------------------------- 3 纯判据
	t.suite("开场动画 / 该不该播（纯判据）")
	t.ok(IntroMovie.should_play(true, false, false, true),
		"真开局（主场景 + 有窗口 + 没被抑制 + 素材在位）⇒ 播")
	t.not_ok(IntroMovie.should_play(false, false, false, true),
		"不是主场景（被工具/套件当子节点挂起来跑）⇒ 不播")
	t.not_ok(IntroMovie.should_play(true, true, false, true),
		"无头 ⇒ 不播（无头渲染是 dummy，一个像素都不产生，只会白烧解码时间）")
	t.not_ok(IntroMovie.should_play(true, false, true, true),
		"命令行给了 --skip-intro ⇒ 不播")
	t.not_ok(IntroMovie.should_play(true, false, false, false),
		"素材缺失 ⇒ 不播（要优雅退化成直接进菜单，不能黑屏卡住）")

	# `should_play_now()` 的环境探测：无头这一台必须判 false。
	t.not_ok(IntroMovie.should_play_now(host),
		"should_play_now() 在本机无头环境下为 false")
	t.not_ok(IntroMovie.should_play_now(null), "传 null 不炸，判 false")
	var loose := Node.new()
	host.add_child(loose)
	t.not_ok(IntroMovie.should_play_now(loose),
		"不在主场景位上（current_scene 不是它）⇒ false —— 这条闸一刀切掉全部截图探针与套件")
	loose.queue_free()

	# ---------------------------------------------------------------- 4 分层与跳过
	t.suite("开场动画 / 分层与跳过")
	var box := CanvasLayer.new()
	host.add_child(box)
	var m := IntroMovie.spawn(box)
	t.ok(m != null, "spawn() 返回了控制器")
	t.eq(box.get_child_count(), 3, "spawn 恰好挂三个节点（黑底 + 视频 + 本层）")
	if box.get_child_count() == 3:
		# ⚠️ 顺序就是层序（Godot 绘制「父先子后、兄弟按序」）：黑底 → 视频 → 本层。
		# 视频必须先于本层，否则它会盖住提示字与黑幕。
		t.eq(str(box.get_child(0).name), "IntroBackdrop",
			"第 1 个是黑底 —— 窗口不是 16:9 时视频会留黑边，黑边里不能露出背后的 3D 世界")
		t.ok(box.get_child(0) is ColorRect, "黑底是个 ColorRect")
		var holder := box.get_child(1)
		t.eq(str(holder.name), "IntroVideo", "第 2 个是视频层")
		t.ok(holder is AspectRatioContainer,
			"视频套在 AspectRatioContainer 里 —— 直接铺满会把 16:9 拉成窗口比例（实机全屏是 16:10）")
		t.near(float(holder.get("ratio")), 16.0 / 9.0, 0.001, "容器比例就是 16:9")
		t.eq(holder.get("stretch_mode"), AspectRatioContainer.STRETCH_FIT,
			"用 FIT（比例不符时留黑边）而不是裁切/拉伸")
		if holder.get_child_count() > 0:
			t.eq(str(holder.get_child(0).name), "IntroVideoPlayer", "容器里就是播放器")
			t.ok(holder.get_child(0) is VideoStreamPlayer, "它是 VideoStreamPlayer")
		else:
			t.ok(false, "保比例容器里应当有一个播放器")
		t.eq(box.get_child(2), m, "第 3 个是控制器自己 —— 提示与黑幕画在最后 ⇒ 盖住视频")

	var fired := [false]
	m.finished.connect(func() -> void: fired[0] = true)

	t.near(m.fade_amount(), 0.0, 0.0001, "没起播时黑幕是 0")
	t.ok(m.begin(0), "begin(0) 起播成功（素材在 + 解码器在）")
	t.eq(m.clip_index, 0, "强制指定播第 0 支（开头动画）")
	t.near(m.fade_amount(), 0.0, 0.0001, "起播那一刻黑幕仍是 0（不该一上来就遮着）")
	t.ok(m.hint_text().contains("跳过进入游戏"),
		"提示文案里有「跳过进入游戏」（真的会被 _draw_hint 画出来）")

	m.skip()
	m.call("_process", IntroMovie.FADE_OUT * 0.5)
	t.gt(m.fade_amount(), 0.0, "按下跳过之后黑幕开始涨（不是硬切）")
	t.lt(m.fade_amount(), 1.0, "刚到半程还没全黑")
	t.ok(m.visible, "半程时本层还在（正在淡出）")

	m.call("_process", IntroMovie.FADE_OUT)
	t.near(m.fade_amount(), 1.0, 0.0001, "走完 FADE_OUT 就全黑")
	t.ok(fired[0], "全黑之后发 finished（main 靠它去开主菜单）")
	t.not_ok(m.visible, "收尾之后本层不再可见")

	m.dispose()
	var leaked: Array = []
	for i in box.get_child_count():
		if not box.get_child(i).is_queued_for_deletion():
			leaked.append(box.get_child(i).name)
	t.eq(leaked.size(), 0,
		"dispose() 把黑底 / 容器 / 视频**一起**带走（不留空节点占着那几层），漏了：%s" % str(leaked))
	box.queue_free()

	# ---- 看门狗：`finished` 不来时不许把玩家永远摁在黑屏上 ----
	# 本层唯一的下场是 `finished` → main 开主菜单。解码器卡住 / 源被截断时那条信号不来，
	# 玩家就卡在全黑的界面上、连"该按什么"都不知道 —— 这条兜底是必须有的。
	var box2 := CanvasLayer.new()
	host.add_child(box2)
	var m2 := IntroMovie.spawn(box2)
	t.ok(m2.begin(0), "第二套也起播成功（看门狗用例）")
	t.gt(float(m2.get("_length")), 0.0,
		"起播时拿到了看门狗的上限（读不到片长时是兜底值，绝不为此关掉看门狗）")
	t.near(m2.fade_amount(), 0.0, 0.0001, "看门狗用例开始前黑幕是 0")
	# 把上限改到极小，模拟「早就该播完却一直没结束」
	m2.set("_length", 0.5)
	m2.set("_t", 0.0)
	m2.call("_process", 0.2)
	t.near(m2.fade_amount(), 0.0, 0.0001, "还没越过「上限 + 富余」⇒ 什么都不做")
	m2.call("_process", IntroMovie.WATCHDOG_SLACK + 0.5)
	t.ok(bool(m2.get("_skipping")),
		"越过「上限 + 富余」后看门狗**触发**了收尾（否则 finished 不来就是永久黑屏）")
	# ⚠️ 触发与淡出不是同一帧：`skip()` 只是把状态翻成"正在收尾"，黑幕从**下一次**
	# `_process` 才开始涨。断言写成一帧到位会假红。
	m2.call("_process", 0.1)
	t.gt(m2.fade_amount(), 0.0, "……而且下一帧真的开始淡出（走的是和「按任意键」同一条收尾）")
	m2.dispose()
	box2.queue_free()

	# ---------------------------------------------------------------- 5 回归保护
	t.suite("开场动画 / 无头下主场景照旧同步进菜单")
	var packed := load("res://scenes/main.tscn") as PackedScene
	t.ok(packed != null, "main.tscn 能加载为 PackedScene")
	if packed != null:
		var main := packed.instantiate()
		host.add_child(main)
		t.eq(main.get("intro"), null,
			"无头下**没有**起开场动画（intro 为 null）")
		# ⚠️ 这两条是本套件最重要的一条回归保护：`_show_menu()` 必须在这一帧里就已经跑完。
		# `input_lockout` 新建实例时是 0.0，只有 `open_menu()` 会把它顶到 0.35 ——
		# 所以它大于 0 就证明"菜单真的被打开了"，而不是"默认值恰好也对"。
		var menu: Node = main.get("menu")
		t.ok(menu != null, "主菜单节点在")
		t.gt(float(menu.get("input_lockout")), 0.0,
			"主菜单**同步**打开了（open_menu 的锁已上）—— 若把动画改成延后一帧起播，这条会红")
		t.eq(Game.phase, Game.Phase.MENU,
			"Game 的阶段已被推进到 MENU（默认是 INTRO，所以这条也证明 _show_menu() 跑过了）")
		t.eq(main.get("phase"), main.Phase.MENU, "main 自己也在 MENU 阶段")
		main.queue_free()

	# ---------------------------------------------------------------- 6 接线扫描
	t.suite("开场动画 / 接线（源码扫描）")
	var im_src := SuiteUiStyle._code("res://scripts/ui/intro_movie.gd")
	t.ok(im_src.contains("signal finished"), "本层对外只有 finished 一个信号")
	t.ok(im_src.contains("AspectRatioContainer"),
		"视频走保比例容器（实机全屏 2560×1600 = 16:10，直接铺满会把 16:9 拉长 11%）")
	t.ok(im_src.contains("VIDEO_ASPECT"), "比例是常量，不是散在代码里的字面量")
	t.ok(im_src.contains("get_cmdline_user_args"),
		"--skip-intro 的判定**同时**扫 user args（`--` 之后的参数不在 get_cmdline_args() 里，只看后者会静默失效）")
	var draw_body := _body(im_src, "func _draw_hint(")
	t.ok(draw_body.length() > 0, "取到了 _draw_hint 的函数体")
	t.ok(draw_body.contains("HINT_KB"),
		"提示文案的常量**真的被画出来**（_draw_hint 消费了它，不是写了个没人用的常量）")
	t.ok(draw_body.contains("draw_string"),
		"用的是 draw_string（工程 UI 全是代码绘制，没有 Label 节点）")
	t.eq(IntroMovie.HINT_KB, "按任意键跳过进入游戏",
		"提示文案就是用户要的那句")
	var input_body := _body(im_src, "func _input(")
	t.ok(input_body.contains("InputEventKey") and input_body.contains("InputEventJoypadButton")
		and input_body.contains("InputEventMouseButton"),
		"任意键 = 键盘键 + 手柄按钮 + 鼠标键")
	t.not_ok(input_body.contains("InputEventJoypadMotion"),
		"**摇杆轴不算**：手柄漂移会凭空吃掉整段开场动画")
	t.ok(input_body.contains("set_input_as_handled"),
		"跳过那一下必须吃掉（否则会被下层界面再读一次）")
	t.ok(_body(im_src, "func _process(").contains("linear_to_db"),
		"淡出时声音跟着黑幕一起收，不留半句孤零零的台词")

	var main_src := SuiteUiStyle._code("res://scripts/main.gd")
	var ready_body := _body(main_src, "func _ready(")
	t.ok(ready_body.contains("_maybe_play_intro()"),
		"启动路径里问了「要不要播开场动画」")
	t.ok(ready_body.contains("_show_menu()"),
		"同级还留着原来的直接进菜单（无头/工具走的就是这一支）")
	t.ok(ready_body.contains("if not _maybe_play_intro():"),
		"是「播得起来就交给动画、否则立刻进菜单」的写法")
	var intro_body := _body(main_src, "func _maybe_play_intro(")
	t.ok(intro_body.contains("IntroMovie.should_play_now(self)"),
		"该不该播全交给那条纯判据（不散在 main 里）")
	t.ok(intro_body.contains("IntroMovie.spawn(canvas)"),
		"层挂在 canvas 上（于是它排在 HUD / 菜单 / 读条之后 ⇒ 画在最上面）")
	t.ok(intro_body.contains("menu.close_menu()"),
		"动画期间关掉菜单 —— 不只为了看不见：不关的话跳过键会被菜单再吃一次")
	t.ok(intro_body.contains("hud.visible = false"), "动画期间不画 HUD")
	t.ok(intro_body.contains("intro.dispose()"),
		"起不来时原样退场（同时退回 false，让调用方去进菜单）")
	var fin_body := _body(main_src, "func _on_intro_finished(")
	t.ok(fin_body.contains("_show_menu()"),
		"动画结束（播完 / 跳过）才真正进主菜单")
