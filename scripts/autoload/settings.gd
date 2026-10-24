extends Node
## 画面与音频设置（autoload 名 `Settings`）。
##
## ## 为什么单独做成一个 autoload
## 这几项要在"主菜单里改"和"游戏里用"之间共享，而且 **AudioDirector 建播放器时就要知道
## 该送去哪条总线**，所以本节点必须比 `Audio` 先 ready —— autoload 的 ready 顺序就是
## 在 project.godot 里的声明顺序，本节点排在 Audio 之前。
##
## ## 总线
## 原来所有声音都直接进 Master，一个音量旋钮只能一起调。现在分两层：
##   Master → BGM（音乐）
##          → SFX（音效总闸）
##                 → VULCAN / SABER / RIFLE / FUNNEL / ALARM / ENGINE
## 总线是**代码建的**而不是写 .tres：工程里没有 audio bus 资源文件，
## 多一个二进制资源不如多十行可读的代码。
##
## ⚠️ 那六条细分通道**挂在 `SFX` 下面**，不是直接挂 Master：
## 「音效音量」的语义因此一个字没变（它仍然是所有音效的总闸，拉到 0 全场安静），
## 每条细分只是它底下的一个 sub-trim。**面板上的层级与总线树是同一棵树。**

signal changed

const CONFIG_PATH := "user://settings.cfg"

## 当前**实际**使用的存档路径。平时恒等于 `CONFIG_PATH`；跑测试时由
## `begin_isolated()` 指向临时档 ⇒ 玩家的档一个字节都不碰（见文件末「测试隔离」）。
var _config_path := CONFIG_PATH

## 隔离嵌套层数（> 0 = 正在跑测试）。
var _isolate_depth := 0

const BUS_BGM := "BGM"
const BUS_SFX := "SFX"

## 「音量细分」的六条**子总线**（全部 `send` 到 `SFX`）。
##
## ## 为什么是子总线，而不是"播放时乘一个系数"
## 三件事各自都足以否掉系数方案：
##   ① **BGM 的淡入淡出用 Tween 直接写 `volume_db`**（`AudioDirector._crossfade()`）——
##      系数一旦也写进 `volume_db`，下一次淡入淡出就把它**整个冲掉**；
##   ② **引擎是常驻循环**，玩家调音量时它正在响 —— 总线音量是**立即生效**的，
##      而"播放时乘一次"对已经在播的那个播放器毫无作用；
##   ③ "拖到 0 就该真静音"这件事，总线有 `set_bus_mute()` 这个**准确**语义，
##      不必靠 `-80 dB` 硬凑。
##
## ## 名称是 ASCII 的，且**在 `SoundBank.SFX_BUS` 里被引用**
## 那张表（音效名 → 子总线名）写的是**字符串**。跨文件引用数组常量在
## `--headless` 下有全局类缓存的坑（本仓库统一纪律），所以走字符串；
## 代价是"写错一个字"会**静默**（那条音效照旧进 SFX），
## 所以有一条闸门钉着：`suite_volume_mixer` 的「表里的总线名都是活总线」一节。
const BUS_VULCAN := "VULCAN"      ## 机枪（vulcan）
const BUS_SABER := "SABER"        ## 光束军刀（挥刀 + 命中）
const BUS_RIFLE := "RIFLE"        ## 光束步枪（含复用的榴弹 / 联机枪声）
const BUS_FUNNEL := "FUNNEL"      ## 浮游飞弹
const BUS_ALARM := "ALARM"        ## 警报（锁定 / 导弹 / 临界 + 座舱告警语音）
const BUS_ENGINE := "ENGINE"      ## 引擎循环（cruise_xi / cruise_penelope）

## 总线建立顺序 —— **父必须排在子前面**。
##
## ⚠️ `set_bus_send()` 找的是**已存在的总线名**，顺序反了子总线会静默挂到
## Master 上：面板上那条滑条还在、还能拖，但它**不再被「音效音量」管**。
## 那种错不报错、不红，只有"把音效拉到 0 却还有机枪声"能发现。
const BUS_ORDER := [
	BUS_BGM, BUS_SFX,
	BUS_VULCAN, BUS_SABER, BUS_RIFLE, BUS_FUNNEL, BUS_ALARM, BUS_ENGINE,
]

## 总线 → 它的父总线。表里没有的（`BGM` / `SFX`）直接送 `Master`。
const BUS_PARENT := {
	BUS_VULCAN: BUS_SFX,
	BUS_SABER: BUS_SFX,
	BUS_RIFLE: BUS_SFX,
	BUS_FUNNEL: BUS_SFX,
	BUS_ALARM: BUS_SFX,
	BUS_ENGINE: BUS_SFX,
}

## 总线 → 存这条总线音量的**变量名**。**唯一真源。**
##
## `set_volume()` / `volume()` / `apply_audio()` / `load_config()` 四处全部查它，
## 所以"加了总线却忘了写某一处"在结构上不可能发生。
## ⚠️ 值必须是 `var` 的**逐字**拼写：`set()` / `get()` 按字符串找，
## 拼错是**运行时静默**的 —— 那条总线永远停在初值，拖滑条没反应。
const BUS_VAR := {
	BUS_BGM: "bgm_volume",
	BUS_SFX: "sfx_volume",
	BUS_VULCAN: "vulcan_volume",
	BUS_SABER: "saber_volume",
	BUS_RIFLE: "rifle_volume",
	BUS_FUNNEL: "funnel_volume",
	BUS_ALARM: "alarm_volume",
	BUS_ENGINE: "engine_volume",
}

## 画面尺寸预设。全部 16:9，和工程基准 1600×900、拉伸模式 canvas_items 一致。
const RESOLUTIONS := [
	{"label": "1280 × 720", "size": Vector2i(1280, 720)},
	{"label": "1600 × 900", "size": Vector2i(1600, 900)},
	{"label": "1920 × 1080", "size": Vector2i(1920, 1080)},
	{"label": "2560 × 1440", "size": Vector2i(2560, 1440)},
]

## 音量步进：一次按键调 5%。
const VOLUME_STEP := 0.05

var resolution_index := 1     ## 默认 1600 × 900，和工程基准一致
var fullscreen := false
var bgm_volume := 0.80
var sfx_volume := 0.90

## 六条细分通道的音量。**默认一律 1.0（= 0 dB）**，这本身是一条硬不变量：
## 默认值下推给引擎的每条子总线都是 0 dB ⇒ 玩家不去动它，
## **改动前后的声音逐位一致**（只有动过滑条的机器才听得出差别）。
var vulcan_volume := 1.0
var saber_volume := 1.0
var rifle_volume := 1.0
var funnel_volume := 1.0
var alarm_volume := 1.0
var engine_volume := 1.0

# ============================================================ 镜头（第十四轮 A4）
#
# 来源是玩家实测的两句话："主要是场景太黑了加上**画面一直在晃**"、
# "我不是特别晕 3d，但玩这个还是有点难受吧"。
#
# ⚠️ 三条都是**设置项，不是我去改常数**。`chase_camera.roll_blend` 的 0.62
# 是当年明确定过的取舍（"纯跟机体滚会在倒飞时天地颠倒晕人，纯跟世界滚又没有缠斗感"），
# 直接把它改小只是把眩晕推给另一批玩家 —— 可调才是真解决。

## 镜头滚转跟随的三档：0 = 保持水平，1 = 完全跟着机体滚。
const CAM_ROLL_STEPS := [0.20, 0.45, 0.62]
const CAM_ROLL_LABELS := ["保持水平", "半跟随", "跟随机体"]
## 镜头抖动三档（0 = 完全关掉）。
const CAM_SHAKE_STEPS := [0.0, 0.5, 1.0]
const CAM_SHAKE_LABELS := ["关", "低", "标准"]

## 默认档取"半跟随"（0.45）：比原来的 0.62 收敛一档，但保留缠斗感。
var cam_roll_index := 1
var cam_shake_index := 2
## 降低动态：一键把 FOV 随速度张开、屏幕速度线、镜头抖动全部关掉，
## 并把滚转跟随压到最低档。给"就是想安静地飞"的玩家一个开关。
var reduce_motion := false

# ============================================================ 第一人称（轮 20）
#
# 需求原文：「做一个第一人称模式，然后把第一人称模式的开关放到设置里面，
# 再加一个开关提醒：开启本模式会导致强烈的 3d 眩晕，是否还要开启？」
#
# ## 为什么它是一个**要过一道确认**的开关
#
# 本作已经有三个降眩晕旋钮（镜头滚转 / 镜头抖动 / 降低动态），但那些都是
# "把已有视角调温和"。第一人称是**反方向**的一步：它把视点从五十米外搬到
# 机体头部，天地线跟着机体滚、地面以最大角速度从视野下方掠过 ——
# 这是所有 3D 内容里最容易诱发晕动症的一档。
#
# 所以：**默认关**，且开启必须过一道"是否还要开启？"的确认（见 `main_menu.gd`
# 的 `Stage.FPV_CONFIRM`）。关掉它永远不需要确认 —— 提示只挡危险的那一侧。
var first_person := false

## 开启前的警示语。**唯一真源**：设置页的确认对话框直接画它，
## 测试也断言它 —— 文案只写一份，改口径时不会出现"弹窗说的和说明说的不一样"。
const FPV_WARNING := "开启本模式会导致强烈的 3D 眩晕，是否还要开启？"

## 环境光遮蔽（SSAO）开关（批 10 性能优化）。
##
## 默认**关**。理由：SSAO 是渲染管线里最贵的屏幕空间特效之一，而在本作的场景尺度上
##（129 km 见方、机体最小也要 28 m、镜头距离几十米起步）它几乎画不出可感知的暗角
## —— 真正提供"体积感"的是雾、辉光与顶点色明暗。花大钱买不出来的效果，默认不买；
## 想要的玩家可以在设置里打开（设置页「环境光遮蔽」一行，立即生效并存档）。
var low_end_60 := true
var quality_preset := 0
var render_scale_index := 2
var dynamic_resolution := true
var shadow_quality := 0
var effects_quality := 0
var magnifier_quality := 0
var ssao := false

## 三渲二（卡通渲染后处理）开关（批 17 立项，批 K · 轮 4 改默认值）。
##
## ⚠️⚠️ **默认从 `true` 改成 `false`** —— 理由不是"性能"，是**画面**。
##
## 批 17 立项时的设计意图是"整个游戏的渲染更三渲二 2d 风格化"
##（参考教程 BV1PGBiBvEFG），所以默认开。但那个效果**从立项起一直没渲染过**
##（`cel_post.gdshader` 的顶点写了个翻转 y 的映射 ⇒ 屏幕空间绕序反转 ⇒
##  被 `cull_back` 整片剔除；表现是"改 uniform 完全没效果"，而日志全绿）。
##
## 批 K · 轮 3 把它修活的**当场**就炸了：实测同机位 PNG 从 1,505,785 B 变成
## 741,080 B，画面里**棕色天空被拆成饱和的红、地面与楼体暗面整片归零**
##（用户原话："**地图光照一塌糊涂，什么都看不见了**"）。
##
## 根因有两条，一条已修一条修不掉：
##   ① 逐通道量化拆色相、归零暗部 —— **已修**（改成亮度域量化 + 等比缩放色度）；
##   ② `screen_texture` 快照里**没有透明几何** ⇒ **云全部消失**
##      （云是 alpha 混合几何；而本面片 `render_priority = 100` 排在最后画）
##      —— **修不掉**，要修得把 3D 世界渲进 `SubViewport` 再做后处理。
##
## ⚠️ 更关键的是：**整个工程的所有画质调校都是在"没有这个后处理"的画面上做的**
##（奥恩贝利的环境光剂量、太平洋的波浪淡出、沙漠植被的反照率……每一格都是）。
## 把它打开 = 一次性改变全画面，那些调校全部作废。
##
## ⇒ 默认关。想开的人可以在设置页打开（代码路径仍然完整、数学已修对）。
## 生效路径：main.gd 监听 changed 后显示/隐藏全屏 cel 面片。
var cel_shading := false


## 实际生效的滚转跟随量（`reduce_motion` 打开时强制最低档）。
func cam_roll_blend() -> float:
	if reduce_motion:
		return CAM_ROLL_STEPS[0]
	return CAM_ROLL_STEPS[clampi(cam_roll_index, 0, CAM_ROLL_STEPS.size() - 1)]


## 实际生效的抖动倍率（`reduce_motion` 打开时为 0）。
func cam_shake_scale() -> float:
	if reduce_motion:
		return 0.0
	return CAM_SHAKE_STEPS[clampi(cam_shake_index, 0, CAM_SHAKE_STEPS.size() - 1)]


## FOV 动态倍率。0 = FOV 恒定（加速不再张开视野）。
func cam_motion_scale() -> float:
	return 0.0 if reduce_motion else 1.0


func cycle_cam_roll(step: int) -> void:
	cam_roll_index = posmod(cam_roll_index + step, CAM_ROLL_STEPS.size())
	save_config()
	changed.emit()


func cycle_cam_shake(step: int) -> void:
	cam_shake_index = posmod(cam_shake_index + step, CAM_SHAKE_STEPS.size())
	save_config()
	changed.emit()


func set_reduce_motion(on: bool) -> void:
	reduce_motion = on
	save_config()
	changed.emit()


## 第一人称开关。它是**状态**的事（存档 + 广播），**不问**"要不要先提醒一下"。
## 分开的理由一直没变：警告是**界面**的事（要能取消、要能默认停在"否"）。
##
## ⚠️ **轮 25 起没有任何调用方会弹眩晕警告了**（需求原文：改成 F1 切换、
## 不用显示强烈 3D 眩晕提示、相关代码不用删、可以自由切换）：
##   - 设置页那一行已从 `MainMenu.SETTING_ROWS` 撤掉 ⇒ 门的部件仍在，但没有入口；
##   - 战斗中的入口是 **F1** / **长按手柄 Back**（都汇到 `toggle_first_person()`），
##     按用户要求**刻意不过门**。
func set_first_person(on: bool) -> void:
	first_person = on
	save_config()
	changed.emit()


## 第一人称 ⇄ 第三人称**翻转**（轮 25，唯一实现）。
##
## 为什么不让调用方自己写 `set_first_person(not first_person)`：
##   ① 这是"唯一实现"—— 键盘 F1 与手柄长按 Back 两条路只有一个状态机；
##   ② 纯逻辑、**可被无头测试直接调用** —— 注入按键在无头里不可靠
##      （见 `suite_fpv` 里那条"按键会怎样一律改钉常量与函数"的规矩）。
## 返回翻转**之后**的状态，调用方要发提示音 / 印提示可以直接用。
##
## ⚠️ 它**刻意不过眩晕门**（用户要求"自由切换"）；门的部件仍在，见上面那段注释。
func toggle_first_person() -> bool:
	set_first_person(not first_person)
	return first_person


func first_person_label() -> String:
	return "开（座舱视角）" if first_person else "关"


# ============================================================ 中央屏显示模式（轮 31）
#
# 需求原文：「按 m 键可以切换中间屏幕显示的是雷达还是机体剪影还是小地图（等高线地形图）」。
#
# ## 为什么模式放这里、而不是放 HUD 里
#
# 与 `first_person` 同一条理由：它是**跨场景存活的玩家偏好**（换机体、重开一局都该还在），
# 而且**唯一真源只能有一份** —— M 键（`main.gd`）、重绑页（`InputSetup.BINDINGS`）、
# 操作说明（`HELP_SECTIONS`）三处都要读它。放进 HUD 的话 HUD 每局重建，
# 玩家按 M 切好的模式一进新局就回默认值 —— 那属于"看着只是没记住、其实是两个真源"。
#
# ## 三模式共用同一个圆盘
#
# 屏幕**形状不变、只换内容**（外框那圈弧三种模式都画，见 `FlightHUD._draw_radar`）——
# 这才是"切换屏幕显示的内容"该有的手感：像按了面板上一个拨轮，不是换了一台仪表。
const DASH_SCREEN_RADAR := 0
const DASH_SCREEN_SILHOUETTE := 1
const DASH_SCREEN_CONTOUR := 2
const DASH_SCREEN_COUNT := 3
## 三种模式的名字（顺序 = 上面常量的顺序）。帮助面板与切换提示共用这一份。
const DASH_SCREEN_NAMES := ["雷达", "机体剪影", "地形等高线"]
var dash_screen_mode := DASH_SCREEN_RADAR


## 切到下一种屏幕模式 —— **M 键的唯一实现**（同 `toggle_first_person()` 的用法：
## 状态机只此一份，键盘那条路只负责叫它）。
##
## 返回**切换之后**的模式下标，调用方要印提示 / 播提示音可以直接用。
func cycle_dash_screen() -> int:
	dash_screen_mode = posmod(dash_screen_mode + 1, DASH_SCREEN_COUNT)
	save_config()
	changed.emit()
	return dash_screen_mode


## 直接设定模式（给"记住上次"以外的入口留的；下标夹取，越界不崩）。
func set_dash_screen_mode(idx: int) -> void:
	dash_screen_mode = clampi(idx, 0, DASH_SCREEN_COUNT - 1)
	save_config()
	changed.emit()


func dash_screen_label() -> String:
	return str(DASH_SCREEN_NAMES[clampi(dash_screen_mode, 0, DASH_SCREEN_COUNT - 1)])


## 中央屏**实际显示**的档位（轮 35）。
##
## 第三人称下**恒为雷达** —— 机主原话：「第三人称模式下按 m 不能切换除了雷达以外的」。
##
## ⚠️ 只改「显示什么」，**不改** `dash_screen_mode`：那是玩家在座舱里的偏好（跨场景
## 存活），回座舱要原样回来。M 键本身在 `main.gd` 侧也挡了（`and Settings.first_person`）
## —— 两条一起才叫「切不动」：一条管「按键无效」，一条管「屏上是什么」。
func effective_dash_screen() -> int:
	return dash_screen_mode if first_person else DASH_SCREEN_RADAR


## SSAO 开关（批 10）。立即生效靠**消费方每帧读**：`WorldBuilder._process` 把它
## 写进 Environment（一个布尔赋值，零成本），不额外拉信号线。
const RENDER_SCALES := [0.5, 0.67, 0.75, 0.85, 1.0]
## Only the low preset (or its custom derivative) gets aggressive visual budgets.
## Balanced keeps its existing 60 Hz cap without inheriting the 750 Ti reductions.
func low_spec_mode() -> bool:
	return quality_preset==0 or (quality_preset==3 and low_end_60 and effects_quality==0)

func render_scale() -> float:
	return RENDER_SCALES[clampi(render_scale_index,0,4)]
func magnifier_hz() -> float:
	return [15.0,30.0,60.0][clampi(magnifier_quality,0,2)]
func set_quality_preset(index: int) -> void:
	quality_preset=clampi(index,0,2)
	low_end_60=quality_preset<2
	render_scale_index=[2,3,4][quality_preset]
	dynamic_resolution=quality_preset==0
	shadow_quality=quality_preset
	effects_quality=quality_preset
	magnifier_quality=mini(quality_preset,1)
	save_config()
func adjust_performance(key: String,dir: int) -> void:
	match key:
		"render_scale": render_scale_index=clampi(render_scale_index+dir,0,4)
		"dynamic_resolution": dynamic_resolution=dir>0
		"shadows": shadow_quality=clampi(shadow_quality+dir,0,2)
		"effects": effects_quality=clampi(effects_quality+dir,0,2)
		"magnifier_quality": magnifier_quality=clampi(magnifier_quality+dir,0,2)
	quality_preset=3 # custom
	save_config()
func set_low_end_60(on: bool) -> void:
	set_quality_preset(0 if on else 2)


func set_ssao(on: bool) -> void:
	ssao = on
	save_config()
	changed.emit()


func ssao_label() -> String:
	return "开" if ssao else "关（推荐）"


## 三渲二开关（批 17）。
func set_cel_shading(on: bool) -> void:
	cel_shading = on
	save_config()
	changed.emit()


func cel_shading_label() -> String:
	return "开（卡通渲染）" if cel_shading else "关"


## 战斗 BGM 自选（批 23）：出击前在设置页决定**本场开场曲**。
##
## ""（默认）= **随机**（开场曲也走洗牌袋）；否则是 `SoundBank.battle_pick_tracks()`
## 里的一个键（轮换池 **或** 仅自选曲）—— 下一场战斗的开场就放它，
## **放完之后剩余的歌照旧随机轮流**（AudioDirector 会把洗牌袋重洗）
##。
##
## ⚠️ 可选范围比轮换池**大**：`SoundBank.OPT_IN_BATTLE_TRACKS`（如 Sweet Child
## O' Mine）只在这个列表里、不在任何轮换池里 ⇒ 玩家不选它就不会响。
## 别把这个不变量"顺手统一"成 `BATTLE_TRACKS`（见 `SoundBank` 里那段注释）。
##
## ⚠️ 这是**选择**而不是一次性请求：不主动清空 —— 玩家选了 TRACER 就每场
## 开场都是 TRACER，想换回随机把这一行拨回「随机」即可（与"画面尺寸"等
## 其它设置行同一心智模型）。
var battle_bgm_pick := ""

# ============================================================ ★63-22 战斗歌单
#
# 需求原文（用户 2026-10-08）：「做一个自定义歌单战斗歌单系统，玩家可以选择 6 首
# 歌曲作为自己的战斗歌单，循环播放」。
#
# ## 它和上面「战斗BGM」（`battle_bgm_pick`）**正交**，别把两者混起来
# | | 决定什么 | 管多久 |
# |---|---|---|
# | `battle_bgm_pick` | 本场的**第一首** | 一首放完就交回轮换 |
# | `battle_playlist` | 第二首起的**轮换池** | 整局（循环） |
# ⇒ 四种组合（都不设 / 只设单曲 / 只设歌单 / 都设）各有唯一、可解释的行为。
# 谁在哪儿生效见 `AudioDirector.bgm_name()` 的三层优先级。
#
# ## ⚠️ 「循环播放」= **整体随机循环**（用户拍板 Q7 原话加了「随机」二字）
# 即"一轮里每首各出现一次 + 一轮放完重洗"，不是"按加入顺序"，也不是
# "每首自己首尾相接"。这正是 `AudioDirector.bag_next()` 现成的洗牌袋语义
# ⇒ 播放侧**一行都不新写**，只换一个池子参数。
#
# ## ⚠️ 唯一的真源就是下面这个变量
# `AudioDirector` **不做镜像**（镜像 = 两边可能不同步 = "歌单设了却不生效，
# 而且不报错"）。它只在每次取有效池时读这里，发现变了就清洗牌袋。

## 歌单容量上限。用户原话：「选择 6 首歌曲」。
const PLAYLIST_MAX := 6

## `toggle_playlist_track()` 的返回值 —— **四态**，UI 靠它选音效与提示文案。
##
## ⚠️ 为什么要这么细：歌单页的 `Enter` 是 **toggle**（加入/移出同一键）。
## 如果只有"成功/失败"两态，"满员被拒"和"成功加入"都会播 `ui_confirm`，
## 玩家的听觉反馈就是**错的** —— 而屏幕上的字他未必在看。
const PLAYLIST_ADDED := 0
const PLAYLIST_REMOVED := 1
const PLAYLIST_REJECTED_FULL := 2
const PLAYLIST_REJECTED_BAD_TRACK := 3

## 玩家的战斗歌单。**空数组 = 没设**（用模式默认池，与今天的行为一致）。
##
## 顺序 = **加入顺序**（页头就按它显示 `1.Plazma 2.UNICORN …`），
## 但**播放顺序是随机的**（洗牌袋）—— 两者不同，提示行里写了一句避免误解。
var battle_playlist: Array[String] = []


## 这首歌在歌单里吗。
func in_playlist(track: String) -> bool:
	return battle_playlist.has(track)


## 它在歌单里的**序号**（1 起；`0` = 不在）。页头与行尾标记都读它 ——
## "序号"和"在不在"是同一个问题的两面，不给两个函数。
func playlist_slot(track: String) -> int:
	var i := battle_playlist.find(track)
	return i + 1 if i >= 0 else 0


## 歌单的读数（设置页那一行 / 子屏副标题）。
##
## ⚠️ 空歌单**不能只印 `0/6`**：那样玩家分不清"我什么都没设"和"我设了但没存上"。
func playlist_label() -> String:
	if battle_playlist.is_empty():
		return "未设置（用默认曲池）"
	return "%d/%d 首" % [battle_playlist.size(), PLAYLIST_MAX]


## 规范化：剔掉非法键、去重、截到 `PLAYLIST_MAX`。
##
## 剔掉非法的键而不是**整单丢弃** —— 与 `battle_bgm_pick` 的哲学一致
##（曲目改名 / 删曲要优雅退化）。一套曲删掉一首 ⇒ 剩 5 首照常生效，
## 玩家只会发现少了一首，不会"歌单没了"。
func normalize_playlist(tracks: Array) -> Array[String]:
	var out: Array[String] = []
	for x in tracks:
		var k := str(x).strip_edges()
		if not SoundBank.is_battle_pick(k) or out.has(k):
			continue
		out.append(k)
		if out.size() >= PLAYLIST_MAX:
			break
	return out


## 整单替换（**规范化的唯一入口**：去重 / 剔非法 / 截断都在 `normalize_playlist()`）。
func set_battle_playlist(tracks: Array) -> void:
	battle_playlist = normalize_playlist(tracks)
	save_config()


## 加入 / 移出（歌单页的 `Enter`）。返回**四态**常量，UI 靠它选音效。
func toggle_playlist_track(track: String) -> int:
	if not SoundBank.is_battle_pick(track):
		return PLAYLIST_REJECTED_BAD_TRACK
	var i := battle_playlist.find(track)
	if i >= 0:
		battle_playlist.remove_at(i)
		save_config()
		return PLAYLIST_REMOVED
	if battle_playlist.size() >= PLAYLIST_MAX:
		return PLAYLIST_REJECTED_FULL
	battle_playlist.append(track)
	save_config()
	return PLAYLIST_ADDED


func clear_playlist() -> void:
	if battle_playlist.is_empty():
		return
	battle_playlist.clear()
	save_config()


## 存档里读到的歌单值 → `Array`（`normalize_playlist()` 的入参类型）。
##
## 可能是 `Array[String]`（本工程自己写的）/ `Array`（玩家手改过存档）/
## `PackedStringArray`（别的引擎版本或外部工具写的）。
## ⚠️ 必须归一：`PackedStringArray` 直接丢进 `for x in tracks` 也能跑，
## 但 `.has()` / `.find()` 在两种类型上的行为差别会在别的地方冒出来 ——
## 这类"能用但类型不对"是最难查的一类。
static func _stored_playlist(v: Variant) -> Array:
	if v is PackedStringArray:
		return Array(v)
	if v is Array:
		return v
	return []


## 循环切换：随机 → 曲池顺序 → 绕回随机。左右两个方向都支持。
func cycle_battle_bgm(dir: int) -> void:
	var options: Array = [""] + SoundBank.battle_pick_tracks()
	var i := options.find(battle_bgm_pick)
	if i < 0:
		i = 0
	i = posmod(i + dir, options.size())
	battle_bgm_pick = str(options[i])
	save_config()


## 选歌页（批 24）用：按**选项序号**直接设定。0 = 随机，1.. 与自选列表同序。
## ⚠️ 选项序列与 `cycle_battle_bgm` 同源（`[""] + SoundBank.battle_pick_tracks()`），
## 两边不许分叉。
func set_battle_bgm_index(idx: int) -> void:
	var options: Array = [""] + SoundBank.battle_pick_tracks()
	battle_bgm_pick = str(options[clampi(idx, 0, options.size() - 1)])
	save_config()


## 当前自选值在**选歌页**里的序号（随机 / 找不到 = 0）。
func battle_bgm_index() -> int:
	if battle_bgm_pick == "":
		return 0
	var i: int = SoundBank.battle_pick_tracks().find(battle_bgm_pick)
	return i + 1 if i >= 0 else 0


func battle_bgm_label() -> String:
	if battle_bgm_pick == "":
		return "随机"
	return SoundBank.battle_track_label(battle_bgm_pick)


func cam_roll_label() -> String:
	if reduce_motion:
		return "%s（降低动态）" % CAM_ROLL_LABELS[0]
	return CAM_ROLL_LABELS[clampi(cam_roll_index, 0, CAM_ROLL_LABELS.size() - 1)]


func cam_shake_label() -> String:
	if reduce_motion:
		return "%s（降低动态）" % CAM_SHAKE_LABELS[0]
	return CAM_SHAKE_LABELS[clampi(cam_shake_index, 0, CAM_SHAKE_LABELS.size() - 1)]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	load_config()
	apply_all()


# ============================================================ 总线

func _ensure_buses() -> void:
	# ⚠️ 顺序 = `BUS_ORDER`（父在前）。理由与"顺序反了的症状"见那个常量的注释。
	for bus_name: String in BUS_ORDER:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, str(BUS_PARENT.get(bus_name, "Master")))


func bus_index(bus_name: String) -> int:
	return AudioServer.get_bus_index(bus_name)


## 把 0..1 的线性音量写进总线。0 直接静音而不是靠 -80 dB 硬凑。
func _apply_volume(bus_name: String, v: float) -> void:
	var idx := bus_index(bus_name)
	if idx < 0:
		return
	var clamped := clampf(v, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, clamped <= 0.0001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(clamped, 0.0001)))


# ============================================================ 应用

func apply_all() -> void:
	apply_display()
	apply_audio()
	changed.emit()


## 把**每一条**总线的音量推给引擎。
##
## ⚠️ 加通道时**只改 `BUS_VAR`** —— 这一节、`set_volume()`、`volume()`、
## `load_config()` 四处全部查那张表。
## 上一版是 `_apply_volume(BUS_BGM, …)` + `_apply_volume(BUS_SFX, …)` 两行手写，
## 照那个写法加到八条就是八行，而**漏一行不会有任何报错**：
## 那条总线永远停在上一次的值（拖滑条没反应，或者开机后还是旧的）。
func apply_audio() -> void:
	_ensure_buses()
	for bus_name: String in BUS_ORDER:
		_apply_volume(bus_name, volume(bus_name))


## 应用窗口尺寸 / 全屏。
##
## 顺序很重要：**先切窗口模式再设尺寸**。反过来的话，从全屏切回窗口时会先用全屏的
## 尺寸去设窗口，然后再切模式，中间会闪一下一个铺满屏幕的窗口。
func apply_display() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var size: Vector2i = RESOLUTIONS[clampi(resolution_index, 0, RESOLUTIONS.size() - 1)]["size"]
	DisplayServer.window_set_size(size)
	# 居中：改了尺寸还贴着左上角会很别扭
	var screen := DisplayServer.screen_get_size()
	if screen.x > size.x and screen.y > size.y:
		DisplayServer.window_set_position((screen - size) / 2)


# ============================================================ 修改

func set_resolution(index: int) -> void:
	resolution_index = posmod(index, RESOLUTIONS.size())
	fullscreen = false          # 选具体尺寸就意味着要窗口模式
	apply_display()
	save_config()
	changed.emit()


func cycle_resolution(step: int) -> void:
	set_resolution(resolution_index + step)


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply_display()
	save_config()
	changed.emit()


## 总线名 → 存这条总线音量的变量名（`""` = 不是本工程的总线）。
## **唯一的换算点**：`set_volume()` / `volume()` / `apply_audio()` / `load_config()` 全走它。
func _volume_var(bus_name: String) -> String:
	return str(BUS_VAR.get(bus_name, ""))


func set_volume(bus_name: String, v: float) -> void:
	var key := _volume_var(bus_name)
	if key == "":
		# 未知总线：**什么都不做**。
		# ⚠️ 老写法是 `if BGM … else sfx_volume = …` ⇒ 一个拼错的总线名会**悄悄改掉
		# 音效总音量**，而调用点以为自己在调别的东西。现在它是明确的 no-op。
		return
	var clamped := clampf(v, 0.0, 1.0)
	set(key, clamped)
	_apply_volume(bus_name, clamped)
	save_config()
	changed.emit()


## 这条总线当前是多少（0..1 线性）。未知总线返回 0.0。
func volume(bus_name: String) -> float:
	var key := _volume_var(bus_name)
	return float(get(key)) if key != "" else 0.0


func resolution_label() -> String:
	if fullscreen:
		return "全屏"
	return str(RESOLUTIONS[clampi(resolution_index, 0, RESOLUTIONS.size() - 1)]["label"])


# ============================================================ 存档

# ============================================================ 测试隔离（★63-11）
#
# ## 病（实测复现）
# 套件里写「**默认值**应当是 X」这类断言时，读的若是**运行时值**，而运行时值来自玩家的
# `user://settings.cfg` —— 玩家按过一次 F1，回归就**永久**多一条红。实测：把玩家档里的
# `first_person` 置成 `true`、**工程源码一行没动** ⇒ `--only=suite_rocket_launch`
# 读 `440 PASS / 1 FAIL`（失败项 = `对照：Settings.first_person 默认也是 false`）。
# 这类红**长得和回归一模一样**，最贵的是它会让人去查代码 —— 而代码是对的。
#
# ## 药
# 跑测试时把 `PERSISTED_VARS` 这 19 个置回**声明默认**，并把读写路径**重定向到临时档**：
#   ① 「断言默认值」天然成立；
#   ② 玩家的 `user://settings.cfg` **一个字节都不碰**（连"写完再还原"都不需要）；
#   ③ 套件里 `save_config()` / `load_config()` 照常工作，只是落在临时档上。
#
# 默认值取法 = **新开一个本脚本的实例**（`new()`）—— 它的属性初始化器逐条跑过，
# 读到的就是 `var x := …` 的字面量。
# ⚠️ **别改成在这里写死常量**：那样 `settings.gd` 改默认值时这里会**静默不同步**。
# 闸门见 `tests/suite_settings_isolation.gd`（清单对账 + 路径同源 + 「默认值取自 new()」）。
#
# ⚠️ 只改**数据层**（测试读的就是它），**刻意不调 `apply_all()`** —— 避免在 headless 下
# 动窗口 / 音频总线，把副作用面收窄到 0。实测依据：`suite_settings` 的音量断言每条都
# 先自己 `set_volume()` 再比 `AudioServer`，与初值无关。

## 隔离期用的临时档。
const ISOLATED_PATH := "user://settings.cfg.suiteiso"

## 被隔离的持久化变量清单 —— **必须**与 `save_config()` 写出的那 19 个逐字一致。
## ⚠️ 将来加持久化项时忘了加到这里 ⇒ 隔离会**静默漏掉它**、而所有断言照样绿。
## 有闸门对账（`suite_settings_isolation` 的「清单对账」一节）。
const PERSISTED_VARS := [
	"resolution_index", "fullscreen", "bgm_volume", "sfx_volume",
	"cam_roll_index", "cam_shake_index", "reduce_motion", "first_person",
	"dash_screen_mode", "low_end_60", "quality_preset", "render_scale_index", "dynamic_resolution", "shadow_quality", "effects_quality", "magnifier_quality", "ssao", "cel_shading", "battle_bgm_pick",
	# ★63-22：战斗歌单。⚠️ 它进这张表还多担一件事 ——
	# `effective_battle_pool()` 读的就是 `battle_playlist`，而套件里
	# "设成默认池、验默认行为"的断言必须不受**玩家自己的歌单**影响。
	# 进了这张表 ⇒ 隔离期它被置回 `[]` ⇒ 那些断言天然成立。漏加的话，
	# "我这儿绿、交出去红"就会以幽灵红的形式出现。
	"battle_playlist",
	# ★63-23：六条音量细分通道。它们**必须**在这张表里，否则隔离期读的是
	# 玩家自己拖过的值 ⇒ 「默认 100%」这类断言在别人机器上红。
	"vulcan_volume", "saber_volume", "rifle_volume",
	"funnel_volume", "alarm_volume", "engine_volume",
]

## 进入隔离前的玩家真值（只在最外层记一次）。
var _isolate_snapshot := {}


## 当前实际使用的存档路径。平时 = `CONFIG_PATH`，隔离期 = `ISOLATED_PATH`。
func config_path() -> String:
	return _config_path


## 是否处于隔离态（跑测试时恒真）。
func is_isolated() -> bool:
	return _isolate_depth > 0


## 进入隔离态。可嵌套（只有最外层真的做事，内层只计数）。
func begin_isolated() -> void:
	if _isolate_depth > 0:
		_isolate_depth += 1
		return
	_isolate_snapshot = {}
	for k: String in PERSISTED_VARS:
		_isolate_snapshot[k] = get(k)
	_config_path = ISOLATED_PATH
	var fresh: Node = (get_script() as GDScript).new() as Node
	for k: String in PERSISTED_VARS:
		set(k, fresh.get(k))
	fresh.free()
	# 临时档也写成「出厂状态」⇒ 套件里 `load_config()` 读回来的仍然一致，
	# 隔离不会因为某条 `load_config()` 而破掉。
	save_config()
	_isolate_depth = 1


## 退出隔离态：还原玩家真值 + 删临时档。玩家的档自始至终没被碰过。
func end_isolated() -> void:
	if _isolate_depth <= 0:
		return
	_isolate_depth -= 1
	if _isolate_depth > 0:
		return
	for k: String in _isolate_snapshot:
		set(k, _isolate_snapshot[k])
	_isolate_snapshot = {}
	_config_path = CONFIG_PATH
	if FileAccess.file_exists(ISOLATED_PATH):
		DirAccess.remove_absolute(ISOLATED_PATH)


func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "resolution_index", resolution_index)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("audio", "bgm_volume", bgm_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	# ★63-23：六条细分通道。⚠️ **必须一行一个裸变量名**（理由见下面 `battle_playlist`
	# 那一段：清单对账读的是第三个实参本身）⇒ 这里不许改成循环写。
	# 好消息是"写盘这一侧"已经被闸门钉死了：`save_config()` 写出的每一项都必须在
	# `PERSISTED_VARS` 里、且反向不许有多余项 ⇒ 漏写一条会红，不会静默。
	cfg.set_value("audio", "vulcan_volume", vulcan_volume)
	cfg.set_value("audio", "saber_volume", saber_volume)
	cfg.set_value("audio", "rifle_volume", rifle_volume)
	cfg.set_value("audio", "funnel_volume", funnel_volume)
	cfg.set_value("audio", "alarm_volume", alarm_volume)
	cfg.set_value("audio", "engine_volume", engine_volume)
	cfg.set_value("camera", "roll_index", cam_roll_index)
	cfg.set_value("camera", "shake_index", cam_shake_index)
	cfg.set_value("camera", "reduce_motion", reduce_motion)
	cfg.set_value("camera", "first_person", first_person)
	# 中央屏显示模式（轮 31）。放 `ui` 段而不是 `camera`：它跟镜头没关系，
	# 是"面板上那个拨轮停在哪一档"。
	cfg.set_value("ui", "dash_screen", dash_screen_mode)
	cfg.set_value("quality", "low_end_60", low_end_60)
	cfg.set_value("quality", "quality_preset", quality_preset)
	cfg.set_value("quality", "render_scale_index", render_scale_index)
	cfg.set_value("quality", "dynamic_resolution", dynamic_resolution)
	cfg.set_value("quality", "shadow_quality", shadow_quality)
	cfg.set_value("quality", "effects_quality", effects_quality)
	cfg.set_value("quality", "magnifier_quality", magnifier_quality)
	cfg.set_value("quality", "ssao", ssao)
	cfg.set_value("quality", "cel_shading", cel_shading)
	# 迁移标记（见 `load_config()`）：有它之后才认存档里的 `cel_shading`。
	cfg.set_value("quality", "cel_migrated", true)
	cfg.set_value("audio", "battle_bgm", battle_bgm_pick)
	# ★63-22 战斗歌单：直接存**数组**。
	#
	# ⚠️ 刻意**不用** `";".join(...)` 之类的"打包成字符串"写法 ——
	# `suite_settings_isolation` 的「清单对账」是扫 `cfg.set_value(...)` 的**第三个实参**
	# 来对账 `PERSISTED_VARS` 的，它读到的必须是**一个裸变量名**。
	# 写成函数调用的话对账会把它当成另一个变量名 ⇒ 两条对账一起红。
	# （实测踩过：`";".join(PackedStringArray(battle_playlist))` 让闸门报了
	#  "漏掉的：['\";\".join(PackedStringArray(battle_playlist))']"。闸门是对的，写法是错的。）
	# ⇒ 这一行同时是一条纪律：**持久化项的写盘实参照抄上面那些，别在这里做转换**。
	cfg.set_value("audio", "battle_playlist", battle_playlist)
	cfg.save(_config_path)


func load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_config_path) != OK:
		return   # 第一次运行：用默认值
	resolution_index = int(cfg.get_value("display", "resolution_index", resolution_index))
	fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
	# ★63-23：音量**八条一次循环读完**（`BUS_VAR` 是唯一真源）。
	# ⚠️ 读盘这一侧**允许**循环（闸门只扫 `save_config()` 的实参）——
	# 而循环正是这边该用的写法：手写八条 `clampf(float(cfg.get_value(...)))` 一定会漏一条，
	# 漏掉的那条症状是"下次开机这条滑条自己回到 100%"，不报错、不红，只有玩家会发现。
	# 未知的 `bus_name` 不会出现：`BUS_ORDER` 与 `BUS_VAR` 是同一份名单。
	for bus_name: String in BUS_ORDER:
		var vol_key := str(BUS_VAR[bus_name])
		set(vol_key, clampf(float(cfg.get_value("audio", vol_key, get(vol_key))), 0.0, 1.0))
	resolution_index = clampi(resolution_index, 0, RESOLUTIONS.size() - 1)
	# 镜头：**索引必须夹取**，否则老存档里没有这几项、或以后档位数量变了，
	# 会直接越界（`CAM_ROLL_STEPS[i]` 崩在这里，而设置页一进去就崩）
	cam_roll_index = clampi(int(cfg.get_value("camera", "roll_index", cam_roll_index)),
		0, CAM_ROLL_STEPS.size() - 1)
	cam_shake_index = clampi(int(cfg.get_value("camera", "shake_index", cam_shake_index)),
		0, CAM_SHAKE_STEPS.size() - 1)
	reduce_motion = bool(cfg.get_value("camera", "reduce_motion", reduce_motion))
	first_person = bool(cfg.get_value("camera", "first_person", first_person))
	# 中央屏模式：**必须夹取**（老存档里没有这一项、或以后档数变了，
	# 越界会让 `DASH_SCREEN_NAMES[i]` 当场崩在设置页上 —— 与上面几个索引同一条理由）。
	dash_screen_mode = clampi(int(cfg.get_value("ui", "dash_screen", dash_screen_mode)),
		0, DASH_SCREEN_COUNT - 1)
	low_end_60 = bool(cfg.get_value("quality", "low_end_60", low_end_60))
	quality_preset = clampi(int(cfg.get_value("quality", "quality_preset", quality_preset)),0,3)
	render_scale_index = clampi(int(cfg.get_value("quality", "render_scale_index", render_scale_index)),0,4)
	dynamic_resolution = bool(cfg.get_value("quality", "dynamic_resolution", dynamic_resolution))
	shadow_quality = clampi(int(cfg.get_value("quality", "shadow_quality", shadow_quality)),0,2)
	effects_quality = clampi(int(cfg.get_value("quality", "effects_quality", effects_quality)),0,2)
	magnifier_quality = clampi(int(cfg.get_value("quality", "magnifier_quality", magnifier_quality)),0,2)
	ssao = bool(cfg.get_value("quality", "ssao", ssao))
	# ⚠️ 老存档一次性迁移（批 K · 轮 4）：存档里那个 `cel_shading` 是在
	# **本效果还没在工作**（顶点绕序 bug，改 uniform 完全没效果）的时候写下去的
	# ⇒ 那个 `true` **从来不是玩家的有效选择** —— 它开与关画面逐位相同。
	# 而它现在**真的会生效**，代价是拆色相 + 云全部消失 ⇒ 老存档强制关一次。
	#
	# 幂等：写盘时记下 `quality/cel_migrated`，之后玩家自己开的开关会被尊重
	#（不这么做的话，玩家在设置页打开、存档、下次进来又被强制关掉）。
	if bool(cfg.get_value("quality", "cel_migrated", false)):
		cel_shading = bool(cfg.get_value("quality", "cel_shading", cel_shading))
	else:
		cel_shading = false
	# 战斗 BGM 自选：读回来要**过自选列表校验** —— 存档里的键可能来自旧版本
	#（曲目改名 / 删曲），不带校验就会选中一首根本不存在的歌。
	# ⚠️ 校验的是 `is_battle_pick()`（轮换池 + 仅自选曲）而不是 `BATTLE_TRACKS`：
	# 后者会把玩家存下来的 Sweet Child O' Mine **静默退回「随机」**，
	# 表现为"我明明选过它，重开又变随机了"。
	var pick := str(cfg.get_value("audio", "battle_bgm", ""))
	battle_bgm_pick = pick if pick == "" or SoundBank.is_battle_pick(pick) else ""
	# ★63-22 战斗歌单：**逐项**过校验（曲目改名 / 删曲 / 版本回退都会留下非法键）。
	# ⚠️ 与上面 `battle_bgm_pick` 同一个哲学 —— **不整单丢弃**：不合法的项剔除、
	# 其余保留。删掉一首歌不该让玩家丢掉整张歌单。
	# ⚠️ 老存档里没有这个键 ⇒ 读到 `[]` ⇒ `[]` = 无歌单，
	# 行为与加这个功能之前**逐字一致**。
	# ⚠️ 这里**不调 `save_config()`**：读一次就把玩家档重写一遍是没有必要的写盘。
	battle_playlist = normalize_playlist(
		_stored_playlist(cfg.get_value("audio", "battle_playlist", [])))
