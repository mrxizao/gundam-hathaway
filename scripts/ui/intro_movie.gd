class_name IntroMovie
extends Control
## 开场动画层：进游戏第一眼看到的东西（`main._ready()` 之后、主菜单**之前**）。
##
## ## 需求（用户原话）
##   ① 「我们做一个进游戏一开头就会播的动画系统」；
##   ② 「右下角有小字提醒按任意键跳过进入游戏」；
##   ③ 「有 20% 的几率在播动画 2（马夫蒂劫持演说）」→ 见 `IntroPlaylist`。
##
## ## 分层：为什么画面节点的**兄弟顺序**是这套实现的命门
## Godot 的 CanvasItem 绘制顺序是「**父先子后**」。所以"视频在最底层、提示字在它上面、
## 黑幕在最上面"这三层，**不能**用"父节点画提示 + 子节点播视频"来实现 ——
## 那样视频会把提示盖掉（提示是父节点画的，永远先画）。
## 于是这里把三层摊平成**三个兄弟**，靠加进 `CanvasLayer` 的先后决定层序：
##
##   [ 1 ] ColorRect 黑底            ← `spawn()` 先加
##   [ 2 ] AspectRatioContainer 视频 ← 里面的 VideoStreamPlayer 按 16:9 装框（见 `VIDEO_ASPECT`）
##   [ 3 ] IntroMovie 自己           ← 最后加；`_draw()` 里先画提示、再画黑幕
##
## 黑幕画在提示**之后** ⇒ 淡出时提示被一起吃掉，不用另外管它的 alpha。
##
## ## 谁该播：`should_play()` 的每一条否决都有具体代价
##   1. `headless` —— 无头渲染是 dummy，一个像素都不产生；而 178 s 的视频在这里
##      只会白烧解码时间，回归要跑几百遍。
##   2. `is_current_scene == false` —— **只在"真的开局"时播**。
##      本仓库所有截图/探针工具与全部测试套件，都是把 `main.tscn` 当**子节点**挂进
##      自己的场景里跑的（`get_tree().current_scene` 是**它们**的根）。这条闸一刀切掉
##      11 个工具 + 全部套件，**不需要任何调用方改一行**，而且以后新加的工具自动免疫。
##   3. `suppressed` —— 命令行给一个 `--skip-intro`（开发时不想一遍遍看开头）。
##   4. `has_clips == false` —— `assets/video/` 缺失时**优雅退化**成直接进主菜单，
##      而不是黑屏卡住。
##
## ⚠️ 「无头下不播」还附带一个**必须保住**的性质：无头里 `_show_menu()` 依旧是
## `_ready()` 里**同步**跑完的。否则一堆"实例化完主场景就断言菜单状态"的用例会集体变红 ——
## 这条性质在 `suite_intro.gd` 里有专门断言，别把动画做成延后一帧起播。

## 播完（自然播完 / 被跳过，两者都走淡出）后发一次。`main` 用它来开主菜单。
signal finished

## 淡出时长。跳过的那一刻不该"啪"地切断 —— 半秒黑幕收尾，和工程的其它转场一个量级。
const FADE_OUT := 0.45

## 看门狗的富余量：片长之外再多给这么多秒，之后强制收尾。
##
## ⚠️ 看门狗**不是**"以防万一"，是**必须**有的：本层唯一的下场是 `finished` → `main` 去开
## 主菜单。只要 `finished` 一次都没来（解码器卡住 / 源文件被截断 / `play()` 没真起来），
## 玩家就被**永远摁在黑屏上**，而且没有任何输入能救 —— 那时屏幕上一个字都没有，
## 玩家甚至不知道该按什么。超时之后走的是**同一条**淡出收尾，表现上就是"片子提前结束了"。
const WATCHDOG_SLACK := 5.0
## 读不到片长时的兜底上限。**不能**因为"读不到片长"就取消看门狗 —— 那正好是最需要它的时候。
const WATCHDOG_FALLBACK := 300.0

## 片子都是 1280×720。
##
## ⚠️ 窗口比例**不一定**是 16:9：本工程 `stretch/aspect = expand`，实机全屏
## 2560×1600（16:10）时画布是 1600×1000 —— 这时把视频直接铺满 Control 矩形，
## 就是**纵向拉长 11%**（片头 SUNRISE 那两个圆点会变成椭圆，一眼看得出来）。
## 所以视频必须装进 `AspectRatioContainer`（官方文档给全屏视频的标准做法），
## 比例不符时留黑边而不是拉伸。
const VIDEO_ASPECT := 16.0 / 9.0

## 右下角提示。**这是玩家可见的唯一文案**，字面量就写在这儿（见 `HINT_KB`）。
##
## ⚠️ 「按任意键」是真的任意键：键盘任意键 / 手柄任意键 / 鼠标任意键都算
## （见 `_input()`）。但**摇杆的轴**不算 —— 手柄漂移会凭空吃掉整段开场动画。
const HINT_KB := "按任意键跳过进入游戏"
const HINT_PAD := "按任意键 / 手柄键跳过进入游戏"
const HINT_MARGIN := 26.0
const HINT_FS := 15
## 提示下面那条短线（和 HUD 的线语言同源：极细、低透明度，只做"这里有个可交互点"的暗示）。
const HINT_RULE := 34.0

const HUD := Color(0.58, 1.0, 0.74)
const NEUTRAL := Color(0.92, 0.95, 1.0)
const OUTLINE := Color(0.0, 0.02, 0.04, 0.9)

## 战役播片的片目表（DESIGN §7.5.4）。
##
## ⚠️ 走 `preload` 而**不是** `class_name`：本仓库是并行编辑的，新加的 `class_name`
## 在编辑器重新扫描 `.godot/global_script_class_cache.cfg` 之前**不在全局类缓存里**，
## 跨文件引用会当场编译失败（这条在 `mission_script.gd` 的嵌套类注释里已记过一次）。
const CS := preload("res://scripts/data/cutscene_script.gd")

## 本帧实际播的是哪一支（`IntroPlaylist.CLIPS` 的下标）。测试与探针读它。
var clip_index := -1

## 战役播片时，这一支的 `CutsceneScript` 片目 id（开场那条管线恒为 `""`）。
##
## ⚠️ 与 `clip_index` 是**两个坐标系的同一个位置**：前者是"开场表的下标"，
## 后者是"战役表的 id"。不合成一个字段，是因为两条管线的**真源不同**
## （`IntroPlaylist` 靠下标 + 权重，`CutsceneScript` 靠 id + 无权重）。
var clip_id := ""

var _video: VideoStreamPlayer
## 视频外面那层保比例的容器、以及它下面的黑底（`dispose()` 要一起收走）。
var _holder: AspectRatioContainer
var _backdrop: ColorRect
var _fade := 0.0
## 起播以来的秒数（看门狗用）。
var _t := 0.0
## 本支片子的时长（看门狗的上限）；读不到时为 `WATCHDOG_FALLBACK`。
var _length := 0.0
var _skipping := false
var _done := false
var _armed := false
## 起播时按 `Settings.bgm_volume` 算出的基准音量（dB）。淡出时在它基础上往下压。
var _base_db := 0.0
var _font: Font


# ============================================================ 该不该播（纯判据）

## **纯函数**：四条否决各自独立，给定输入必得唯一结果 —— 于是四种否决可以逐条验。
static func should_play(is_current_scene: bool, headless: bool, suppressed: bool,
		has_clips: bool) -> bool:
	return is_current_scene and not headless and not suppressed and has_clips


## 把"这台机器 / 这次运行"翻译成上面那四个布尔。
##
## ⚠️ 必须在 `main._ready()` 里**同步**读 `get_tree().current_scene`：
## 真开局时引擎在**进 `_ready()` 之前**就已经把主场景设成 current_scene 了
## （工具场景同理，实测 `_ready()` 里读到的就是自己）。若改成延后一帧再判，
## 无头下 `_show_menu()` 就跟着晚一帧，一批"实例化完就断言菜单"的用例会红。
static func should_play_now(node: Node) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	return should_play(
		node.get_tree().current_scene == node,
		DisplayServer.get_name() == "headless",
		_has_skip_flag(),
		IntroPlaylist.has_any_clip())


## `--skip-intro` 的判定。
##
## ⚠️ **两张命令行表都要扫**：Godot 把 `--` **之后**的参数放进
## `OS.get_cmdline_user_args()`，`OS.get_cmdline_args()` 里**没有**它们。
## 只看后者的话，`godot --path . <场景> -- <输出目录> --skip-intro` 这种写法
## **静默失效** —— 开关"存在"、代码"看着对"、跑起来毫无作用（本轮实测第一次就是这么漏的，
## 是靠真机跑两遍对比才发现的）。本工程 `test_runner._want_resume()` 是同款写法。
static func _has_skip_flag() -> bool:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if str(a) == "--skip-intro":
			return true
	return false


## 建一套（黑底 + 保比例视频 + 本层），按层序挂进 `parent`，返回本节点（失败返回 null）。
##
## ⚠️ **顺序就是层序**（Godot 绘制「父先子后、兄弟按序」）：黑底 → 视频 → 自己。
## 别调换 —— 视频必须在提示字下面，黑幕必须在最上面。
static func spawn(parent: Node) -> IntroMovie:
	if parent == null:
		return null

	# ---- 层 1：黑底 ----
	# 窗口不是 16:9 时视频会留黑边（见 `VIDEO_ASPECT`），没有这层黑底的话，
	# 黑边里露出来的是背后的 3D 世界与菜单 —— 看着像"游戏没加载完"。
	var backdrop := ColorRect.new()
	backdrop.name = "IntroBackdrop"
	backdrop.color = Color(0.0, 0.0, 0.0, 1.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(backdrop)
	# 锚点必须**进树之后**再设：`set_anchors_and_offsets_preset(PRESET_FULL_RECT)`
	# 要问父级的可锚定矩形，不在树里拿到的是空矩形。
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# ---- 层 2：视频（套在保比例容器里）----
	var holder := AspectRatioContainer.new()
	holder.name = "IntroVideo"
	holder.ratio = VIDEO_ASPECT
	holder.stretch_mode = AspectRatioContainer.STRETCH_FIT
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var video := VideoStreamPlayer.new()
	video.name = "IntroVideoPlayer"
	video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	video.process_mode = Node.PROCESS_MODE_ALWAYS
	# `expand` 让视频跟随容器的矩形（而不是反过来把容器撑成视频的 720p）。
	# 容器已经按 16:9 算好了内框 ⇒ 铺满即等比。
	video.expand = true
	holder.add_child(video)
	video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# ---- 层 3：提示字与黑幕（`_draw` 里画的）----
	var movie := IntroMovie.new()
	movie.name = "IntroMovie"
	movie.process_mode = Node.PROCESS_MODE_ALWAYS
	movie._video = video
	movie._holder = holder
	movie._backdrop = backdrop
	parent.add_child(movie)
	return movie


# ============================================================ 生命周期

func _ready() -> void:
	add_to_group("story_skip_movies")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 不吃鼠标：任意键的判定走 `_input()`（它不受 mouse_filter 影响），
	# 而 GUI 层不该被这层挡住。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	if _font == null:
		_font = ThemeDB.fallback_font
	visible = false
	set_process(false)
	set_process_input(false)


## 起播。返回 false = 起不来（素材缺失 / 装不上解码器 / 视频兄弟丢了），
## 调用方应当**原样退场**（`dispose()`）并直接进主菜单。
##
## `force_index` 只给测试与探针用：跳过随机、指定播哪一支（-1 = 正常随机）。
func begin(force_index := -1) -> bool:
	if _armed:
		return true
	clip_index = force_index if force_index >= 0 else IntroPlaylist.pick_index(randf())
	return _begin_path(str(IntroPlaylist.clip_at(clip_index)["path"]))


# ============================================================ 战役播片（DESIGN §7.5）

## ## 为什么要第二套判据：`should_play_now()` 的头号闸对它**恒为 false**
## `should_play_now()` 的第一条否决是 `current_scene == self`（"只在真开局时播"），
## 那是为了让 **11 个工具 + 全部测试套件** 自动免疫 —— 它们把 `main.tscn` 当
## **子节点**挂进自己的场景里跑，`current_scene` 是**它们**的根。
## 而战役播片**恰恰发生在主场景里**，这条闸对它恒假（DESIGN §7.5.3 规矩 3）。
##
## ⇒ 第二套判据只剩**三条**否决：`headless` / `--skip-cutscenes` / 素材缺失。
## ⚠️ 第一条是硬性的：**无头下必须"立即返回、绝不暂停"** ——
## 否则 `await finished` 永不回来，**整个回归会挂住**。
## （开场不播只是少看一段；战斗播片不播是**跑不完**。）

## **纯函数**：三条否决各自独立，给定输入必得唯一结果（与 `should_play()` 同款写法，
## 于是"无头必须 false"这件事可以被**逐点验**而不是靠跑一遍看会不会挂）。
static func should_play_in_mission(headless: bool, suppressed: bool, has_clip: bool) -> bool:
	return not headless and not suppressed and has_clip


## 把"这台机器 / 这次运行"翻译成上面那三个布尔。
static func should_play_in_mission_now() -> bool:
	return should_play_in_mission(
		DisplayServer.get_name() == "headless",
		_has_skip_cutscenes_flag(),
		CS.has_any())


## `--skip-cutscenes` 的判定。
## ⚠️ 与 `_has_skip_flag()` 同款：**两张命令行表都要扫** —— Godot 把 `--` **之后**的参数
## 放进 `OS.get_cmdline_user_args()`，只看 `get_cmdline_args()` 会让这种写法**静默失效**。
static func _has_skip_cutscenes_flag() -> bool:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if str(a) == "--skip-cutscenes":
			return true
	return false


## 按 **id** 播指定的一支（`begin()` 只有 `pick_index(randf())` 那条随机路径）。
##
## ⚠️ 战役播片**必须确定**：序章必播豪泽恩号、且只播一次 —— 随机会让
## "第一关之前看到什么"不可复现（`IntroPlaylist` 的注释已经为这条辩过一次）。
##
## 返回 false = 起不来（id 不在表里 / 素材缺失 / 解码器装不上 / 视频兄弟丢了）。
## **调用方应当原样继续**（战役照常推进）—— 缺片是**可选依赖**，不是错误。
func begin_by_id(id: String) -> bool:
	if _armed:
		return true
	var c: CS.Cutscene = CS.by_id(id)
	if c == null:
		push_warning("战役播片表里没有这一支，跳过：%s" % id)
		return false
	# 按 id 起播时 `clip_index` 无意义（那是**开场表**的下标）⇒ 置 -1，
	# 让"这一支来自哪条管线"在读数上一眼可辨。
	clip_index = -1
	clip_id = id
	return _begin_path(c.path, "战役播片")


## 起播并 **await 到收尾**（自然播完 / 被跳过 / 看门狗强制收尾，**三者都回来**）。
##
## ★ 这是"战斗中播片"的入口（`Trigger` 的 `cutscene:<id>`，DESIGN §7.5.3）：
## 调用方把它夹在 `get_tree().paused = true` 与 `= false` 之间，
## 靠本层的 `PROCESS_MODE_ALWAYS` 在暂停里照样播。
##
## ⚠️ **无头 / 素材缺失 ⇒ 立即返回 false，绝不 `await`**（见 `should_play_in_mission_now()`）。
## ⚠️ **暂停的解开归调用方**：本方法只管播完、不碰 `paused` ——
##   这样"谁开的暂停谁关"是唯一一处，三条收尾路径（自然 / 跳过 / 看门狗）
##   不可能各自漏解一条（`_finish()` 已经是收尾的唯一出口）。
##
## ⚠️ **`static` 是必须的，不是风格问题**：本方法**一个 `self` 都不用** ——
##   它自己 `spawn()` 一台、播完自己 `dispose()`。写成实例方法的话调用方得先
##   `spawn()` 一台出来**只为了喊一声**，那一台还会被 `dispose()` 掉（因为
##   `_armed` 为假），于是白造一个节点。GDScript 的 `await` 在 `static` 里是允许的。
static func play_blocking(parent: Node, id: String) -> bool:
	if not should_play_in_mission_now():
		return false
	var movie := IntroMovie.spawn(parent)
	if movie == null:
		return false
	if not movie.begin_by_id(id):
		movie.dispose()
		return false
	await movie.finished
	movie.dispose()
	return true


## 真正的起播实现（开场与战役**两条管线共用**）。
##
## ⚠️ `what` 只进 `push_warning` 的文案。开场那条路径传默认值 ⇒
## 那两条告警的字面量与改造前**逐字相同**（`suite_intro` 钉着开场行为）。
func _begin_path(path: String, what := "开场动画") -> bool:
	if _armed:
		return true
	if _video == null or not is_instance_valid(_video):
		return false
	if not ResourceLoader.exists(path):
		push_warning("%s素材缺失，跳过：%s" % [what, path])
		return false
	var st := load(path) as VideoStream
	if st == null:
		push_warning("%s装不上解码器（核心只认 .ogv / Ogg Theora），跳过：%s" % [what, path])
		return false
	_video.stream = st
	# 看门狗用的片长。读不到就退回兜底上限 —— 绝不因此把看门狗关掉（见 `_process`）。
	_length = _video.get_stream_length()
	if _length <= 0.0:
		_length = WATCHDOG_FALLBACK
	# 音轨走工程的 **BGM 总线** ⇒ 设置页那根「BGM」滑条同时管着开场动画的音量，
	# 不需要为它单开一项设置。
	_video.bus = Settings.BUS_BGM
	# ⚠️ `linear_to_db(0)` 是 -inf，会让整条总线变成 NaN 级的静音；夹一个地板值给它。
	_base_db = linear_to_db(clampf(Settings.bgm_volume, 0.0001, 1.0))
	_video.volume_db = _base_db
	if not _video.finished.is_connected(skip):
		# 自然播完与"被跳过"走**同一条**淡出收尾 —— 两套收尾迟早会走偏一套。
		_video.finished.connect(skip)
	_video.play()
	_armed = true
	visible = true
	set_process(true)
	set_process_input(true)
	queue_redraw()
	return true


## 跳过（也是"自然播完"的共用入口）。幂等。
func skip() -> void:
	if not _armed or _done or _skipping:
		return
	_skipping = true


## 起不来时的**原样**退场：黑底、容器、视频一起带走，别留下空节点占着那几层。
func dispose() -> void:
	if _video != null and is_instance_valid(_video):
		_video.stop()
	for n: Node in [_video, _holder, _backdrop]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_video = null
	_holder = null
	_backdrop = null
	queue_free()


func _process(delta: float) -> void:
	_t += delta
	if not _skipping:
		# 看门狗：见 `WATCHDOG_SLACK` 的注释 —— 没有它，`finished` 不来就是永久黑屏。
		# 注意判据里用的是 `_length`（读不到片长时已经是兜底上限），**不做"读不到就放过"的分支**。
		if _armed and _t > _length + WATCHDOG_SLACK:
			push_warning("开场动画超过片长仍未结束（%.1fs > %.1fs），看门狗强制收尾"
				% [_t, _length])
			skip()
		# ⚠️ 上面的 `return` 有讲究：本帧刚被 `skip()` 翻成"正在收尾"的，
		# 黑幕从**下一次** `_process` 才开始涨（差一帧，肉眼看不见）。测试别按"一帧到位"写。
		return
	_fade = minf(_fade + delta / FADE_OUT, 1.0)
	if _video != null and is_instance_valid(_video):
		# 声音跟着黑幕一起收 —— 否则画面已经黑了，最后半秒的台词还孤零零地拖着。
		_video.volume_db = _base_db + linear_to_db(maxf(1.0 - _fade, 0.0001))
	if _fade >= 1.0:
		_finish()
	queue_redraw()


## 「按任意键」的判定口。
##
## ⚠️ 只认**按下沿**（`pressed and not echo`）：长按会刷出一串 `echo` 事件，
## 而"键还按着"不该被重复当成跳过。
## ⚠️ **不接受 `InputEventJoypadMotion`**：摇杆漂移是持续事件，会凭空吃掉整段动画。
## 用户说的"任意键"在这里落到"任意键/任意按钮"。
func _input(event: InputEvent) -> void:
	if not _armed or _done or _skipping:
		return
	var hit := false
	if event is InputEventKey:
		var k := event as InputEventKey
		hit = k.pressed and not k.echo
	elif event is InputEventJoypadButton:
		hit = (event as InputEventJoypadButton).pressed
	elif event is InputEventMouseButton:
		hit = (event as InputEventMouseButton).pressed
	if not hit:
		return
	# 吃掉这一下。菜单/暂停/重绑页都还在树上，不吃掉的话同一个按键会被
	# 下层界面再读一次（"同一个按键被两个界面各吃一次"是本工程踩过多次的坑）。
	get_viewport().set_input_as_handled()
	skip()


func _finish() -> void:
	if _done:
		return
	_done = true
	_armed = false
	_fade = 1.0
	visible = false
	set_process(false)
	set_process_input(false)
	if _video != null and is_instance_valid(_video):
		_video.stop()
		_video.visible = false
	finished.emit()


# ============================================================ 绘制

func _draw() -> void:
	# 顺序即层序：先提示、后黑幕 ⇒ 淡出时提示被一起吃掉（不用单独管它的 alpha）。
	if _fade < 1.0:
		_draw_hint()
	if _fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, _fade), true)


## 右下角那行小字。**坐标全部按当前视口算**，不写死 1600×900 ——
## 设置页能换分辨率（`RESOLUTIONS`），写死的话换个分辨率提示就飘出去了。
func _draw_hint() -> void:
	var s := InputSetup.hint(HINT_KB, HINT_PAD)
	var tw := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FS).x
	var right := size.x - HINT_MARGIN
	var base := size.y - HINT_MARGIN
	var pos := Vector2(right - tw, base)
	# 一条贴在提示下方的短线，作为"这里能操作"的锚点（同 HUD 的线语言：细、低透明度）
	var y := base + 9.0
	draw_line(Vector2(right - tw - HINT_RULE, y), Vector2(right - tw + tw, y),
		FlightHUD.deco_white(0.28), UILayout.LINE_HAIR)
	# 深色描边 + 亮色正文：无论画面上是暗景还是白闪，这行字都读得出来。
	draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FS,
		UILayout.OUTLINE_BODY, OUTLINE)
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FS, NEUTRAL)


## 供测试/探针读的画布文案（`_draw()` 是私有的，光看源码"有没有那个字面量"不够稳）。
func hint_text() -> String:
	return InputSetup.hint(HINT_KB, HINT_PAD)


## 当前黑幕不透明度（0 = 全画面视频，1 = 全黑）。测试用它验"跳过真的在淡出"。
func fade_amount() -> float:
	return _fade
