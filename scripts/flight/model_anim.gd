class_name ModelAnimator
extends RefCounted
## 模型骨骼动画的播放绑定（棒 12 测试官 / 2026-09-26）。
##
## ## 它解决什么
##
## 工程侧原来的 `FlightBody` **只把模型当"可见件"** —— 它是从
## `assets\models\<suit>\*.glb` 实例化出来、挂在 `ModelRoot` 下的一堆
## `MeshInstance3D`，**从头到尾没有一行代码碰过动画**
## （N28 实测：全仓 `.play()` 只有音频，`AnimationPlayer` 出现 0 次）。
## 于是棒 1 交付的 `fly` / `burst` / `burst_cruise` 进引擎之后**是孤儿**：
## 模型能显示、能跟着机体飞，但**动作永远停在第一帧**，且不报任何错。
##
## 这个类就是那根线：找到模型自带的 `AnimationPlayer`，按名字播。
##
## ## 为什么需要"跨文件摘动画"
##
## 交付契约是 **一个 glb 一个 Action**（`verify_action.py` 的「无多余 Action」
## 判据），所以 `fly` / `burst` / `burst_cruise` 是**三个文件**。
## 而引擎里一台机只有一个模型实例 ⇒ 只有一个 `AnimationPlayer`。
##
## 三个文件是**同一次导出、同一副骨架、同一套轨道路径**
## （实测：三件的轨道路径都是 `Xi_Rig/Skeleton3D:<骨名>`）。
## 所以这里不去重写轨道路径 —— 直接把另外两个文件里的 `Animation`
## 资源**挂到主实例的那个 AnimationPlayer 上**即可，路径天然对得上。
##
## ⚠️ 前提：`root_node` 不用动。**别自作聪明去改 root_node**
## —— 主实例自己的 `fly` 能播，就证明它的 root_node 是对的，
## 追加进来的动画用的是同一套路径字符串，自然也对。
##
## ## 对老资产零影响
##
## 游戏仓 **18 个 glb 全部 `skins: 0 / animations: 0`**（`glb_morph_probe.py` 实测），
## 没有任何一个带骨架或动画 ⇒ `setup()` 找不到 AnimationPlayer，
## `ready == false`，`play_*()` 全部退化成空操作。**老机体的行为逐位不变。**

## 主实例上的播放器（找不到就是 null）。
var player: AnimationPlayer
## 可播的动作名 → true。`has()` 查它。
var actions := {}
## 当前正在播的动作名（"" = 没在播）。
var current := ""
## 本次 setup 是否真的找到了播放器。
var ready := false
## Playback-only pose variants leave authored clips available as form baselines.
var pose_overrides: Dictionary = {}

# Only the two large flight suits opt into pose snapshots and contextual shots.
var motion_skeleton: Skeleton3D
var motion_suit := -1
var shot_rebase: Callable

func _motion_blend(action: String, blend: float) -> float:
	if not is_instance_valid(motion_skeleton) or blend <= 0.0: return blend
	if action == "shoot": blend = 0.09
	elif action == "slash": blend = 0.14
	elif action.begins_with("dash_"): blend = 0.13 if motion_suit == int(SuitProfile.Id.PENELOPE) else 0.09
	else: blend = 0.22 if motion_suit == int(SuitProfile.Id.PENELOPE) else 0.18
	# Freeze the evaluated pose, rather than letting the outgoing attack continue
	# moving beneath the blend. This also works after a non-looping dash ends.
	var snapshot := Animation.new()
	snapshot.length = 0.1
	snapshot.loop_mode = Animation.LOOP_LINEAR
	var base := _track_base()
	for bone in motion_skeleton.get_bone_count():
		for type in [Animation.TYPE_ROTATION_3D,Animation.TYPE_POSITION_3D,Animation.TYPE_SCALE_3D]:
			var tr := snapshot.add_track(type)
			snapshot.track_set_path(tr,NodePath(base+":"+str(motion_skeleton.get_bone_name(bone))))
			var value: Variant = motion_skeleton.get_bone_pose_rotation(bone)
			if type == Animation.TYPE_POSITION_3D: value = motion_skeleton.get_bone_pose_position(bone)
			elif type == Animation.TYPE_SCALE_3D: value = motion_skeleton.get_bone_pose_scale(bone)
			snapshot.track_insert_key(tr,0.0,value)
	var library := player.get_animation_library(DEFAULT_LIBRARY)
	if library.has_animation("__ace_snapshot"): library.remove_animation("__ace_snapshot")
	library.add_animation("__ace_snapshot",snapshot)
	player.play("__ace_snapshot",0.0)
	player.advance(0.0)
	return blend

func _context_shot() -> void:
	if not shot_rebase.is_valid(): return
	var source := player.get_animation("shoot")
	var clip: Animation = shot_rebase.call(source)
	var library := player.get_animation_library(DEFAULT_LIBRARY)
	if library.has_animation("__ace_live_shoot"): library.remove_animation("__ace_live_shoot")
	library.add_animation("__ace_live_shoot",clip)
	pose_overrides["shoot"] = "__ace_live_shoot"

func playback_name(action: StringName) -> StringName:
	return StringName(pose_overrides.get(str(action),str(action)))
## A paused anticipation pose remains an unfinished action until the dash arrives.
var saber_holding := false

func hold_saber_at(time: float) -> void:
	if not ready or current != "slash" or saber_holding:
		return
	player.seek(time, true)
	player.pause()
	saber_holding = true

func release_saber() -> void:
	if not saber_holding:
		return
	saber_holding = false
	if ready and current == "slash":
		player.play("slash", -1.0, 1.0, false)

## 常态循环动作名。
var idle_action := "fly"
## 一次性的"全弹发射"动作（常态形态 / 巡航形态各一个）。
var burst_action := "burst"
var burst_cruise_action := "burst_cruise"

## **巡航形态的待机循环**动作名（N42·二十一 方案 B · 2026-09-27）。
##
## 空串（默认）= 该机体没有巡航专用待机 ⇒ `ModelAnimFSM` 退回 `idle_action`。
## 18 个老资产与其余五台机体都是空串 ⇒ 行为逐位不变。
##
## ⚠️ 必须同时经 `prepare_loops()` 设为 `LOOP_LINEAR`：glTF 没有"循环"概念，
## 不设就会**播完停在末帧**，且不报任何错。
var idle_cruise_action := ""

## 进入巡航形态时先播**一次**的过渡动作名（N42·二十一）。
##
## 空串（默认）= 直接用 `BLEND_FORM` 交叉淡入切到目标待机（老路径，逐位不变）。
## 柯西 = `form_on`：0.4333 s，首帧逐位 = 常态、末帧逐位 = 巡航待机首帧。
var form_on_action := ""

## **退出**巡航形态（巡航 → 常态）时先播**一次**的过渡动作名（N42·二十二）。
##
## 空串（默认）= 用 `BLEND_FORM` 0.18 s 交叉淡入（老路径，逐位不变）。
## 柯西 = `form_off`：0.4333 s，`form_on` 的严格镜像
##（首帧逐位 = 巡航待机姿态、末帧逐位 = `fly` 首帧，中间 smoothstep 缓动）。
##
## ★ 为什么方向和 `form_on` 分开两个字段：两个方向的**起点不同**
##（`form_on` 起于常态、`form_off` 起于巡航待机），一条动作表达不了两向。
var form_off_action := ""

## 需要额外去别的 glb 里摘动作的文件表（一个文件一个 Action）。
var _extra_files: Array = []

## 主实例上的骨架（找不到就是 null）。只给 `reset_to_rest()` 用。
##
## ⚠️ 为什么这里自己再找一遍、不复用 `FlightBody._model_skel`：
## `ModelAnimFSM._enter_idle()` 也需要归位能力，而它手里**只有** `ModelAnimator`。
## 让它回头去问宿主，等于把"谁负责归位"这条契约拆到两个类里 ——
## 本工程"两处判据打架"的老毛病就是这么来的。
var _skel: Skeleton3D

## 默认动画库是否已是**本实例私有**的一份（见 `_own_default_library()` 的长说明）。
var _lib_owned := false

## 静置段是否已经建过（幂等用）。见 `REST_CLIP`。
var _rest_built := false

## 巡航归位段是否已经建过（幂等用）。见 `CRUISE_HOLD_CLIP`。
var _hold_built := false

## 基准播放速率。交付的动作是 **30 fps** 烘的，Godot 的默认 `playback_speed`
## 就是 1.0，两者一致 —— 这里留一个具名常量，免得以后有人去"补偿帧率"。
const ACTION_FPS := 30.0

## glTF 导入器把动作放在**默认动画库**里，库名是空串。
const DEFAULT_LIBRARY := &""

## 「恒定静置段」的保留名（N50）。
##
## ## 它是什么
##
## 一段**程序生成**的动画：每根骨各 3 条轨道（旋转/位移/缩放），
## 两个关键帧的值**都是该骨自己的 rest** ⇒ 播它 == 把全身写回绑定姿态，
## 与"停播"在**姿态上逐位等价**。
##
## ## 为什么非有不可（N50 实测）
##
## Godot 的 `play(name, blend)` **不是**"从骨当下的姿态混合过去"，
## 而是"从**上一段动画**的姿态混合过去"。⇒ 播放器**停着**的时候没有"上一段"，
## `blend` 参数**被完全忽略**，直接硬切。
##
## 五台机体（佩涅罗佩 / 量产牛 / 阿利宙斯常态 / 古斯塔夫 / 梅萨）按用户要求
## `model_anim_idle == ""`（不播飞行待机）⇒ 待机时播放器**是停着的** ⇒
## **每一次进入动作、每一次动作收尾，都是零混合硬切**。
##
## 实测（`tools/_n50_smoothness.gd`，逐帧全骨姿态活动量 `A[i]`，
## `J[i] = A[i] - A[i-1]`）：
##
## | | 梅萨（空待机） | 柯西（有 `fly` 待机） |
## |---|---|---|
## | 全局 `\|J\|max` | **158.93** | **18.64** |
## | 「动画 → 动画」切换的 `J` | ≈ 0（混合生效） | ≈ 0 |
## | 「→ rest」收尾的 `J` | **134 ~ 159**（硬切） | **≈ 0** |
##
## ⇒ 用户报的「每个动作过渡都有点生硬」，机械原因就是**混合没发生**，
## 与 `BLEND_*` 取多少**毫无关系**（调那些常数一个字节都不会变）。
##
## ## 为什么不做成"真动作"
##
## 它**不进 `actions`**、`has()` 查不到、`action_names()` 也列不出来 ——
## 否则会污染"动作总数 == 27/28"这类既有断言，也会被 `_prepare_loops()`
## 的前缀扫描误伤。它只有**一个用途**：占住播放器，给 `play(blend)` 提供前一段。
const REST_CLIP := &"__rest__"

## 静置段的长度（秒）。内容**恒定** ⇒ 长度只决定"多久绕一圈"，不影响姿态，
## 也不影响混合（混合时长由 `play()` 的 `blend` 参数给）。取短一点，
## 免得万一将来有人读它的进度时等太久。
const REST_HOLD_LEN := 0.5

## 「**巡航归位段**」的保留名（N56）。
##
## ## 它解决什么
##
## 用户报：「柯西在巡航模式下按 WASD 就会举枪 ⇒ **不要举枪**，只有光束步枪射击时才举枪」。
## 根因有两层（N56 §1/§2）：
##   ① 巡航形态与常态**共用同一套方向动作族**（`fly_*` / `turn_*`），而它们是**常态基准**
##      的姿态 ⇒ 一按 W 就把整条手臂从巡航位带到常态持枪位（`UpperArm.R` +89.53°）。
##   ② 松手回 `cruise_idle` **也放不下来** —— `cruise_idle` 在引擎里只剩 19 条旋转轨
##      （导入器按 "Remove Immutable Tracks" 删掉了常量轨），
##      `UpperArm.*` / `LowerArm.*` / `Hand.*` / `Thigh.*` / `Shin.*` / `Foot.*` /
##      `Chest` / `Spine` / `Hips` **一根都没有** ⇒ 那些骨**保持上一段动作的残留**
##      （`AnimationPlayer` 的规则是"没有轨道的属性保持当前值"）。
##
## ⇒ 巡航待机需要一个**能锁住臂 / 腿 / 躯干**的段。本段 = 那个段。
##
## ## 与 `REST_CLIP` 的关系：**两源合成**，不是二选一
##
## | 骨 | 取自 | 为什么 |
## |---|---|---|
## | `cruise_idle` 里**有**轨道的那些（翼 / 装甲 / 喷口，19 条） | **`cruise_idle` 原样** | 保住巡航待机的观感（否则待机会变死板） |
## | `cruise_idle` 里**没有**的（臂 / 腿 / 躯干） | **`form_on` 末帧值**，恒定 | 与 `FormWeld` 的祖先基准**同源**（N55 定的就是 `form_on` 末帧） |
## | 两个源都没有的 | 自己骨的 rest | 兜底 |
##
## ★ 为什么不直接复用 `REST_CLIP`：柯西的 rest 姿态**今天恰好**等于巡航姿态
## （N56 §1.4 实测五部位全 0.00%，连翼都是），但那是"绑定姿态恰好等于巡航形态"的**巧合**。
## 用 `REST_CLIP` 就会有两个真源（焊缝取 `form_on` 末帧、待机取 rest），
## 将来谁动了 rest 或 `form_on` ⇒ **两边错位且都不报错**。
##
## ⚠️ 与 `REST_CLIP` 一样：**只进动画库、不进 `actions`**（它不是一个"动作"，
## 别污染"动作总数 == 27/28"那类断言，也别被 `_prepare_loops()` 的前缀扫描误伤）。
const CRUISE_HOLD_CLIP := &"__cruise_hold__"


## 唯一的构造入口。`inst` = 模型实例的根；`extra_files` = 额外动作所在的 glb 路径表。
##
## ⚠️ 必须在 `inst` **已经进树**之后调 —— 摘动画那一步要实例化另一个场景，
## 没进树时 `AnimationPlayer` 拿不到 `root_node` 的解析上下文。
static func setup(inst: Node3D, extra_files: Array = []) -> ModelAnimator:
	var ma := ModelAnimator.new()
	ma._extra_files = extra_files
	if inst == null:
		return ma
	var ap := find_player(inst)
	if ap == null:
		# 没有 AnimationPlayer = 这个模型没有自带动作（老资产全是这样）。
		# **不是错误**，不 push_warning：18 个老 glb 每一个都会走到这里。
		return ma
	ma.player = ap
	ma.ready = true
	# 骨架：`reset_to_rest()` 的载体。找不到不影响任何已有路径
	#（本工程带动画的模型都自带骨架）。
	for c in inst.find_children("*", "Skeleton3D", true, false):
		ma._skel = c as Skeleton3D
		break
	# ★★ 第一件事：把这个动画库**私有化**。
	#
	# 从 glb 导入的 `AnimationLibrary` 是**共享资源** —— 同一个 `.glb`
	# 实例化出多少份，指向的都是**同一个**库对象。而下面两行都要写这个库
	#（`_graft_extras()` 往里加动作、`_prepare_loops()` 改 `loop_mode`）——
	# 不私有化就等于"改一台机，改到全部"。
	ma._own_default_library()
	for n in ap.get_animation_list():
		ma.actions[str(n)] = true
	ma._graft_extras()
	# ★★ N50：建"恒定静置段"（见 `REST_CLIP` 的长说明）。
	#    ⚠️ 必须放在 `_graft_extras()` **之后**：`_track_base()` 要从 `actions` 里的
	#    动画抄一条轨道的路径前缀，候选越多越稳（主实例自带的 `fly` 此时也在表里）。
	ma._build_rest_clip()
	ma._prepare_loops()
	return ma


## 递归找第一个 AnimationPlayer。
static func find_player(root: Node) -> AnimationPlayer:
	for c in root.find_children("*", "AnimationPlayer", true, false):
		return c as AnimationPlayer
	return null


## 去额外的 glb 里把 Action 摘过来挂到主播放器上。
##
## ⚠️ **Godot 4 的 `AnimationPlayer` 没有 `add_animation()`** ——
## 动画住在 `AnimationLibrary` 里：`AnimationMixer.add_animation_library(name, lib)`，
## 库内 `lib.add_animation(name, anim)`。glTF 导入器用的是**默认库**（名字是空串），
## 所以这里往默认库里塞，`get_animation_list()` 才能一起列出来。
## 第一版按 Godot 3 的直觉写了 `player.add_animation(...)`，
## 报的是 `Nonexistent function 'add_animation'`（不是"参数错"，容易看漏）。
##
## ⚠️ `CACHE_MODE_IGNORE` 是刻意的：这几个场景只是**动作的容器**，
## 摘完就丢。走默认缓存的话，一台机入场会把 3 份 203 网格全留在资源缓存里
## （实测每份约 4.3 MB 源 glb，展开更大），纯属白占内存。
func _graft_extras() -> void:
	if _extra_files.is_empty():
		return
	for p in _extra_files:
		var path := str(p)
		if path == "" or not ResourceLoader.exists(path):
			push_warning("[ModelAnimator] 额外动作文件不存在：%s" % path)
			continue
		var ps := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if ps == null:
			push_warning("[ModelAnimator] 额外动作文件不是 PackedScene：%s" % path)
			continue
		var tmp := ps.instantiate()
		var ap := find_player(tmp)
		if ap == null:
			push_warning("[ModelAnimator] %s 里没有 AnimationPlayer" % path)
			tmp.free()
			continue
		for n in ap.get_animation_list():
			var nm := str(n)
			if actions.has(nm):
				continue          # 同名不覆盖：主实例自己的那份优先
			var a := ap.get_animation(nm)
			if a == null:
				continue
			# 一次性动作拷一份再改 loop_mode，避免动到原资源。
			_add_into_default_library(nm, a.duplicate() as Animation)
			actions[nm] = true
		tmp.free()


## 把一个 Animation 塞进默认动画库（没有就建）。
func _add_into_default_library(action_name: String, anim: Animation) -> void:
	_own_default_library()
	var lib := player.get_animation_library(DEFAULT_LIBRARY)
	if lib == null:
		lib = AnimationLibrary.new()
		player.add_animation_library(DEFAULT_LIBRARY, lib)
	lib.add_animation(action_name, anim)


## 确保默认动画库是**本实例私有**的一份。幂等，可随便调。
##
## ## 为什么非私有化不可（2026-09-26 实测的坑）
##
## 从 glb 导入的 `AnimationLibrary` 是**共享资源**：同一个 `.glb` 实例化出多少份，
## 它们指向的就是**同一个**库对象。直接 `add_animation()` / 改 `Animation.loop_mode`
## 等于改全局那一份，于是"**这台机**摘到 2 个额外动作"会扩散成
## "**之后每一个**从同一个 glb 实例化出来的对象都带着这 2 个动作"。
##
## 实测症状：`xi_fly.glb` 的实例 `get_animation_list()` 从 1 个变成 3 个 ——
## 而且**只有在"别的代码先建过一台柯西"之后才出现**。
## 单跑那个检查套件永远是绿的（它是第一个，没有任何东西来得及污染），
## 所以这个 bug 骗过了一整轮全量回归，直到 `model_path` 换到新资产后才暴露。
##
## 深拷（`duplicate(true)`）而不是浅拷：`Animation` 本身也是共享资源，
## `_prepare_loops()` 要改 `fly.loop_mode` —— 浅拷的话照样写穿到全局。
## 代价是每台带动作的机体建体时多拷一次主实例的库（只有 `fly` 一段，量很小）。
func _own_default_library() -> void:
	if _lib_owned or player == null:
		return
	var src := player.get_animation_library(DEFAULT_LIBRARY)
	var copy := AnimationLibrary.new() if src == null else (src.duplicate(true) as AnimationLibrary)
	# 显式 `remove` 再 `add`：`add_animation_library()` 遇到已存在的名字
	# 是"替换"还是"什么都不做"，各版本行为不一致，先删最稳。
	# 这一步发生在 `setup()` 阶段（还没播任何动作），所以不会打断播放。
	if player.has_animation_library(DEFAULT_LIBRARY):
		player.remove_animation_library(DEFAULT_LIBRARY)
	player.add_animation_library(DEFAULT_LIBRARY, copy)
	_lib_owned = true


# ============================================================ 恒定静置段（N50）

## 建"恒定静置段"：全身每根骨三个通道，值都 = 该骨自己的 rest。
##
## 播它 == 把全身写回绑定姿态（与"停播"姿态上逐位等价），**但播放器仍在跑**
## ⇒ 下一次 `play(动作, blend)` 有"前一段"可混 ⇒ 过渡真的会发生。
##
## 幂等（`_rest_built`）。建不出来时**静默返回** —— 上层 `has_rest_clip()` 会拿到
## `false` 并退回 `reset_to_rest()`（老路径，姿态正确但没有混合）。
func _build_rest_clip() -> void:
	if _rest_built:
		return
	_rest_built = true
	# 两个源都为空 ⇒ 每根骨每通道都是**自己的 rest** —— 与 N50 的实现逐位相同
	#（那条路径由 `tests/suite_model_anim.gd` 的静置段断言守着）。
	_build_hold_clip(REST_CLIP, "", "")


## 建「巡航归位段」（N56）：主源 = `cruise_idle`（保住巡航待机的观感），
## 补缺源 = `form_on`（补 `cruise_idle` 在引擎里没轨道的臂 / 腿 / 躯干）。
## 详见 `CRUISE_HOLD_CLIP` 的长说明。
##
## ⚠️ **必须在动作名赋值之后调**：`idle_cruise_action` / `form_on_action` 的默认值是空串，
## 真正的内容由 `SuitProfile` 在 `ModelAnimator.setup()` **返回之后**才赋进来
##（同一个时序陷阱 N50 已经踩过一次 —— 那次是 `cruise_idle` 拿不到 `LOOP_LINEAR`）。
## ⇒ 这里**不**在 `setup()` 里建，而是由宿主的 `prepare_clips()` 触发。
##
## 只有"有巡航待机"的机体（今天 = 柯西）建得出来；其余机体 / 18 个老资产到这里就返回
## ⇒ `has_cruise_hold()` 恒 `false` ⇒ 状态机逐位走旧路径（N49 的老资产约束）。
func _build_cruise_hold_clip() -> void:
	if _hold_built:
		return
	_hold_built = true
	if idle_cruise_action == "" or not actions.has(idle_cruise_action):
		return
	_build_hold_clip(CRUISE_HOLD_CLIP, idle_cruise_action, form_on_action)


## 「归位段」的通用构造：**两源合成**。
##
## * `src_primary`（主源）—— 它的轨道**原样搬**（含动态多关键帧、含非骨架轨道；
##   插值一律归一成 LINEAR，见下方说明）。
## * `src_fallback`（补缺源）—— 只对**骨架里还没有轨道的**骨 / 通道生效，
##   取它的**末关键帧值**当恒定值。
## * 两个源都没有的 ⇒ 该骨自己的 rest。
##
## 两个源都可以传 `""` ⇒ 退化成"纯 rest 段"（= `REST_CLIP`）。
##
## ⚠️ 为什么主源要"原样搬"而不是"只取末帧"：`cruise_idle` 是循环待机，
## 它的 19 条轨里可能有真正在动的（翼 / 装甲）—— 只取末帧会把待机拍成静止图。
##
## ⚠️ 为什么插值归一成 LINEAR：glTF 导入器产出的采样轨本来就是逐帧 LINEAR
## （它已经把 CUBICSPLINE 烘成采样点），所以这里归一不会改变任何一条既有轨的观感；
## 而在新动画里手写 `INTERPOLATION_CUBIC` 会带上**默认零手柄**，把曲线压平 ——
## 那才是真正会改观感的写法。
func _build_hold_clip(clip: StringName, src_primary: String, src_fallback: String) -> bool:
	if not ready or _skel == null or player == null:
		return false
	var nb := _skel.get_bone_count()
	if nb <= 0:
		return false
	var base := _track_base()
	if base == "":
		return false
	var pri := player.get_animation(src_primary) if src_primary != "" else null
	var fbk := player.get_animation(src_fallback) if src_fallback != "" else null
	# 长度：优先跟主源一致（它的关键帧时间轴按它自己的长度铺），否则用静置段长度。
	var length := REST_HOLD_LEN
	if pri != null and pri.length > 0.0:
		length = maxf(pri.length, 0.02)
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR
	# ---- ① 主源轨道原样搬 ----
	var copied := {}
	if pri != null:
		for si in pri.get_track_count():
			var ty := pri.track_get_type(si)
			var p := pri.track_get_path(si)
			var ti := a.add_track(ty)
			a.track_set_path(ti, p)
			for k in pri.track_get_key_count(si):
				a.track_insert_key(ti, pri.track_get_key_time(si, k),
					pri.track_get_key_value(si, k))
			copied[_chan_key(p, ty)] = true
	# ---- ② 缺的骨 / 通道：补缺源末帧值，再退回 rest ----
	for i in nb:
		var rest := _skel.get_bone_rest(i)
		var path := NodePath("%s:%s" % [base, _skel.get_bone_name(i)])
		_fill_channel(a, copied, path, Animation.TYPE_ROTATION_3D,
			rest.basis.get_rotation_quaternion(), fbk, length)
		_fill_channel(a, copied, path, Animation.TYPE_POSITION_3D,
			rest.origin, fbk, length)
		_fill_channel(a, copied, path, Animation.TYPE_SCALE_3D,
			rest.basis.get_scale(), fbk, length)
	_add_into_default_library(str(clip), a)
	return true


## 「骨路径 + 轨道类型」的字典键。用它判"某骨某通道在主源里有没有"。
func _chan_key(path: NodePath, track_type: int) -> String:
	return "%s|%d" % [str(path), track_type]


## 给 `_build_hold_clip()` 补一条恒定轨（主源没覆盖到的通道）。
##
## 值优先取**补缺源的末关键帧**（= `form_on` 播完那一刻的姿态，
## 与 `FormWeld` 的祖先基准同源），补缺源没有才退到 rest。
func _fill_channel(a: Animation, copied: Dictionary, path: NodePath, track_type: int,
		rest_val: Variant, src: Animation, length: float) -> void:
	if copied.has(_chan_key(path, track_type)):
		return
	var val: Variant = rest_val
	if src != null:
		var si := _find_track(src, path, track_type)
		if si >= 0 and src.track_get_key_count(si) > 0:
			val = src.track_get_key_value(si, src.track_get_key_count(si) - 1)
	var ti := a.add_track(track_type)
	a.track_set_path(ti, path)
	a.track_insert_key(ti, 0.0, val)
	a.track_insert_key(ti, length, val)


## 在动画里找"某骨某通道"的轨道下标；没有返回 `-1`。
func _find_track(an: Animation, path: NodePath, track_type: int) -> int:
	if an == null:
		return -1
	for i in an.get_track_count():
		if an.track_get_type(i) == track_type and an.track_get_path(i) == path:
			return i
	return -1


## 从**已有动画**里抄一条轨道的"节点部分"路径（`Xi_Rig/Skeleton3D`）。
##
## ## 为什么不自己拼
##
## 轨道路径是**相对 `root_node`** 的，而各机体的根节点名不同
##（`Xi_Rig` / 别的），Skeleton3D 也未必在根的直接子级。既有动画里的路径
## 是引擎自己认得的、能播的 ⇒ 抄它必然对。
func _track_base() -> String:
	for nm in actions.keys():
		var an := player.get_animation(str(nm))
		if an == null:
			continue
		for tr in an.get_track_count():
			if an.track_get_type(tr) != Animation.TYPE_ROTATION_3D:
				continue
			var p := an.track_get_path(tr)
			if p.get_subname_count() >= 1:
				return str(p.get_concatenated_names())
	return ""


## 静置段建出来了没有。
func has_rest_clip() -> bool:
	return ready and player != null and player.has_animation(REST_CLIP)


## 播静置段：把骨写回 rest，**但保持播放器在跑**（N50）。
##
## ## 与 `reset_to_rest()` 的分工
##
## | | 骨姿态 | 播放器 | 下一次 `play(blend)` |
## |---|---|---|---|
## | `reset_to_rest()` | rest ✓ | **停止** | ✗ 没有前一段 ⇒ **硬切** |
## | `hold_rest()` | rest ✓ | **在跑** | ✓ 有前一段 ⇒ 真的混合 |
##
## ⇒ **收尾回位一律用这个**；`reset_to_rest()` 只留给"真的要复位"的场合
##（释放模型前、探针要绝对 rest 基准时）。
##
## ⚠️ 走 `player.play()` **直达**，不经 `actions` 检查 —— 静置段**故意不在**
## `actions` 里（它不是动作）。
func hold_rest(blend := 0.0, restart := false) -> void:
	if not ready or not has_rest_clip():
		return
	if not restart and current == str(REST_CLIP) and player.is_playing():
		return
	current = str(REST_CLIP)
	saber_holding = false
	player.play(playback_name(REST_CLIP), _motion_blend(str(REST_CLIP),blend), 1.0, false)


## 巡航归位段建出来了没有（N56）。见 `CRUISE_HOLD_CLIP`。
##
## `false` 的两种情形都**不是错误**：① 这个模型没有巡航待机（其余五台机体 / 18 个老资产）；
## ② 没有骨架 / 抄不到轨道路径。两种情况状态机都逐位退回旧行为。
func has_cruise_hold() -> bool:
	return ready and player != null and player.has_animation(CRUISE_HOLD_CLIP)


## 宿主在**动作名赋值之后**调一次：把按动作名才能建的段补齐（目前只有巡航归位段）。
##
## ⚠️ 与 `prepare_loops()` 同一个时序理由 —— 详见 `_build_cruise_hold_clip()`。
## 幂等，可随便调。
func prepare_clips() -> void:
	_build_cruise_hold_clip()


## 播巡航归位段：臂 / 腿 / 躯干回到**巡航位**（= `form_on` 末帧），
## 同时保留 `cruise_idle` 自己的轨（翼 / 装甲）⇒ 巡航待机的观感不变。
##
## ⚠️ 与 `hold_rest()` 一样走 `player.play()` **直达**，不经 `actions` 检查 ——
## 归位段**故意不在** `actions` 里（它不是动作）。
func hold_cruise(blend := 0.0, restart := false) -> void:
	if not ready or not has_cruise_hold():
		return
	if not restart and current == str(CRUISE_HOLD_CLIP) and player.is_playing():
		return
	current = str(CRUISE_HOLD_CLIP)
	saber_holding = false
	player.play(CRUISE_HOLD_CLIP, _motion_blend(str(CRUISE_HOLD_CLIP),blend), 1.0, false)


## **倒放**一次某段动作（N56 收枪）。返回 `true` = 这条路可行（已经/正在倒放）。
##
## ## 用途
##
## 用户方案：「射击完，短时间内没有下一发射击 ⇒ **倒放 `shoot`** 收枪」。
## 实测（N56 §1.5）：倒放**起手零接缝**（正放末帧 → 倒放 = 逐位 0.000000，因为
## `AnimationPlayer` 停播**不还原骨姿态** —— T30 那条在这里反而是优点）；
## 倒放**= 时间反演**（同位置正放 vs 倒放逐位 0.000000）；
## 倒放到 0 **自然停**（`is_playing()` → `false` ⇒ 现有 `finished()` 恰好返回 `true`）。
##
## ⚠️ **倒放本身收不到枪**：`shoot` 的**首帧 ≡ 末帧 ≡ 常态待机 `fly` 首帧**
## （两两逐位 0.000000）⇒ 倒放到底仍停在**举枪位**。它给的是"枪口按原轨迹回摆"的**过程**，
## 归位要靠随后的 `hold_cruise()`（两段接起来才全 0.00%）。
##
## ## ⚠️ 必须显式设 `LOOP_NONE`
##
## `LOOP_LINEAR` 倒放到 0 会**绕回末尾** ⇒ 变成无限"举枪 / 收枪"的循环。
## `loop_mode` 写的是**本实例私有**的那份库（`_own_default_library()` 已深拷），
## 不会污染别的机体 —— 与 `play_once()` 同一套理由、同一处写法。
##
## `restart = false` 时"已经在播这一段"就**不重新倒放**（否则每次调都把播放头拖回末尾 =
## 永远收不了枪）。返回 `true` 仍然表示"路径可行"，调用方不必区分。
func play_backwards_once(action_name: String, blend := 0.12, restart := false) -> bool:
	if not ready or not actions.has(action_name):
		return false
	if not restart and current == action_name and player.is_playing():
		return true
	current = action_name
	saber_holding = false
	var a := player.get_animation(action_name)
	if a != null:
		a.loop_mode = Animation.LOOP_NONE
	# 第三参 = 速度 −1（倒放）；第四参 = `from_end` ⇒ 从末尾起手，
	# 于是"正放播完停在哪、倒放就从哪开始"，接缝为零。
	player.play(playback_name(action_name), _motion_blend(action_name,blend), -1.0, true)
	return true


## 循环动作必须显式设 `loop_mode`。
##
## ⚠️ glTF **没有**"循环"这个概念，导入器也不会替你猜
## （`fly` 在 glTF 里就是一段 0→2.0 s 的采样），默认 `LOOP_NONE` ⇒
## 播完停在末帧。而 `fly` 是待机循环，它必须无缝接回第 1 帧。
##
## 交付报告实测：`fly` 的 `f59→f60` 与 `f1→f2` 步长比 **0.989**，
## 即首尾姿态本来就是按循环对齐的 ⇒ `LOOP_LINEAR` 是正确读法，不用做缝合。
func _prepare_loops() -> void:
	# ⚠️ 一次要覆盖**两个**待机动作：`fly`（常态）与 `cruise_idle`（巡航）。
	#    漏掉后者 ⇒ 巡航待机播完停在末帧（不循环、不报错）。
	for nm in [idle_action, idle_cruise_action]:
		if nm == "" or not actions.has(nm):
			continue
		var a := player.get_animation(str(nm))
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR
	# ★ 冲刺八向（N46）：8 段**全是循环**（首末姿态都 = 待机基准，「从待机出发、回到待机」），
	#   必须一起设。漏设的症状同巡航待机：动作播完 `finished()` 停在末帧 ——
	#   冲刺窗口 0.45 s 虽然大多短于动作时长，但**只要动作先播完就先僵住**，且不报错。
	#
	# ⚠️ 它们**没有字段**（是 8 个固定名字，由 `FlightBody` 按方向现拼），
	#   所以只能按前缀扫 `actions` —— 不能像上面那样列字段名。
	for nm in actions.keys():
		var s := str(nm)
		if not s.begins_with("dash_"):
			continue
		var a2 := player.get_animation(s)
		if a2 != null:
			a2.loop_mode = Animation.LOOP_LINEAR


## 宿主在**改过动作名之后**重跑一次循环设置。幂等，可随便调。
##
## ## 为什么非有不可（时序陷阱，2026-09-27 实测）
##
## `idle_action` / `burst_action` / `burst_cruise_action` 都带**非空默认值**，
## 所以 `setup()` 末尾那一次 `_prepare_loops()` 对它们就有效；而
## `idle_cruise_action` / `form_on_action` 的默认值是**空串** —— 真正的内容由
## `SuitProfile` 在 `setup()` **返回之后**才赋进来（`FlightBody._setup_model_anim()`
## 里 `ModelAnimator.setup()` 的下一行）。⇒ 只跑 `setup()` 那次的话，
## `cruise_idle` **拿不到 `LOOP_LINEAR`**。
##
## 症状：巡航待机播完**停在末帧**（不循环、不报错、全量回归照样全绿）。
func prepare_loops() -> void:
	_prepare_loops()


func has(action_name: String) -> bool:
	return actions.has(action_name)


func action_names() -> Array:
	var out := actions.keys()
	out.sort()
	return out


## 反复播（待机 / 循环动作）。已经在播同一个就不重启动，免得每帧重置进度。
##
## ⚠️ `restart = true` 是给**状态机**用的（见 `ModelAnimFSM`）：状态机在
## "换动作"那一次必须真的从头播，否则会接在上一段的残留进度上；
## 而状态机在 `tick()` 里每帧调的路径**绝不能**传 `true`。
## 默认 `false` ⇒ 既有调用点行为逐位不变。
func play_loop(action_name: String, blend := 0.18, restart := false) -> void:
	if not ready or not actions.has(action_name):
		return
	if not restart and current == action_name and player.is_playing():
		return
	current = action_name
	saber_holding = false
	player.play(playback_name(action_name), _motion_blend(action_name,blend))


## 播一次。**已经在这个动作里时不重启动** —— 否则每帧调一次会把
## 进度永远按在第 0 帧上（"动作播了但看不出在动"的经典成因）。
##
## ⚠️ `restart = true` 的用途与理由同 `play_loop()`：状态机的**事件驱动**入口
## （全弹发射那一帧喊一次）要重播，**帧驱动**入口（`tick()`）绝不能。
## 默认 `false` ⇒ 既有调用点行为逐位不变。
func play_once(action_name: String, blend := 0.12, restart := false) -> void:
	if not ready or not actions.has(action_name):
		return
	if not restart and current == action_name and player.is_playing():
		return
	current = action_name
	saber_holding = false
	var a := player.get_animation(action_name)
	if a != null:
		a.loop_mode = Animation.LOOP_NONE
	if action_name == "shoot": _context_shot()
	player.play(playback_name(action_name), _motion_blend(action_name,blend), 1.0, false)


## 这个动作当前播完了没有（一次性动作用完该回待机）。
func finished() -> bool:
	if not ready or current == "":
		return true
	if current == "slash" and saber_holding:
		return false
	if not player.is_playing():
		return true
	var a := player.get_animation(playback_name(current))
	if a == null:
		return true
	return player.current_animation_position >= a.length - 0.0001


## 供探针/测试读的进度（0..1）。
func progress() -> float:
	if not ready or current == "":
		return 0.0
	var a := player.get_animation(current)
	if a == null or a.length <= 0.0:
		return 0.0
	return clampf(player.current_animation_position / a.length, 0.0, 1.0)


func stop() -> void:
	if ready:
		player.stop()
	current = ""


## 停播并**把所有骨归位到 rest**（绑定姿态）。
##
## ## 为什么非有它不可
##
## `stop()` 只是让播放头别走 —— 它**不会**还原骨姿态。`AnimationPlayer` 的规则是
## 「没有轨道的属性保持当前值」，所以停播后模型会**僵在最后写入的那一帧**。
##
## 在"机体有待机动作"的年代这不构成问题：停播之后总会被 `play_loop(idle)` 接上。
## 但 N46 起**佩涅罗佩刻意没有待机动作**（用户裁决：2 秒的飞行循环违和）⇒
## 冲刺/发射这类一次性段落播完，"接下来播什么"是**空**的 ⇒ 没有本函数就会
## 停在一个冲刺姿势上，而且**不报任何错**。
##
## ## ★★ 为什么绝不能写 `Quaternion()` / `ZERO`（N47 修复，2026-09-28）
##
## `Skeleton3D` 的 pose **不是**「相对 rest 的偏移」，而是**骨骼在父空间里的
## 绝对局部变换**（本工程 T6 早就记下这条；`tools/xi_nozzle_probe.gd` 里也已实测过
## 「`set_bone_pose_position(i, Vector3.ZERO)` **不等于复位**」—— 但这条知识
## **没被搬到这里**，于是同一颗雷在 N46 又炸了一次）。
##
## ⇒ `set_bone_pose_rotation(i, Quaternion())` 不是归位，是把**方向改错**；
##   `set_bone_pose_position(i, Vector3.ZERO)` 是把骨**塌到原点**。
##
## 实测（佩涅罗佩 39 骨，净效应隔离，`_relay/n47b_fix.log`）：
##
## | 只改这一项 | 与出厂 rest 最大夹角 | 骨原点最大位移 |
## |---|---|---|
## | `rotation` → `Quaternion()` | **171.549°**（37/39 骨 > 5°） | 1.156 m |
## | `position` → `Vector3.ZERO` | 0.040°（本身无害） | **1.048 m** |
## | `scale` → `Vector3.ONE` | 0.040°（无害） | 0.000 m |
##
## 三项一起 ⇒ 模型被压成一个**尖刺团**（出图 `_relay/n47_pose/after_dash_idle.png`）。
## 用户 2026-09-28 报：「**一按下八向冲刺模型就整个乱七八糟**」——
## 佩涅罗佩没有待机动作 ⇒ 冲刺窗口（0.45 s）一结束就走到这里，
## 而且**之后没有任何动作能把它救回来** ⇒ 永久乱。
##
## 正解 = 还原成每根骨**自己的 rest**（实测与出厂 rest 差 **0.040°**、骨原点 **0.000000 m**）。
func reset_to_rest() -> void:
	saber_holding = false
	stop()
	if _skel == null:
		return
	# 官方一键复位：Godot 4.7.1 实测**存在**（早期几个版本没有 ⇒ 留回退路径）。
	if _skel.has_method("reset_bone_poses"):
		_skel.reset_bone_poses()
		return
	for i in _skel.get_bone_count():
		_skel.set_bone_pose(i, _skel.get_bone_rest(i))


## 从**资源**里直读某动作在某个时刻的全骨局部旋转，返回 `{骨名: Quaternion}`。
##
## 用途：给「巡航形态层」（`CruiseFormModifier`）取**巡航姿态基准** ——
## 上游 PIPELINE §9.2 明确写了「`burst_cruise` 的尾帧 = 巡航形态的待机」，
## 所以巡航姿态就从它的末帧读。
##
## ---- 为什么不去 `play()` + `seek()` 采样 ----
##
## 实测过：`seek()` 之后**要等一帧**骨架才被写进去（探针 `_bone_rots_at()`
## 就是为此 await 一帧）。而建体（`_setup_model_anim()`）是**同步**流程，
## 不能 await。轨道数据本来就躺在 `Animation` 资源里，**直接读**即可：
## 同步、无副作用、也不动播放头。
##
## ⚠️ CUBICSPLINE 陷阱**不适用这里**：`track_get_key_value()` 取的是
## **真值**，不含入/出切线（切线只在 glb 的 raw buffer 里占 3 倍分量）。
##
## `t` 用 `-1` = 取末帧；否则取最靠近 `t` 的那个关键帧。
## `action_name` 里每根骨的某个分量在时刻 `t` 的关键帧值。
##
## `track_type` = `Animation.TYPE_ROTATION_3D` 或 `Animation.TYPE_POSITION_3D`。
## `t < 0` ⇒ 取**末帧**（循环动作的稳定姿态）；否则取**离 `t` 最近的关键帧**。
##
## ★ N52 抽成一处：`rotations_at()` 与 `locations_at()` 必须用**同一套取样口径**，
## 否则「旋转基准取末帧、位置基准取首帧」这类错位迟早发生
##（N42·十二「两处判据打架」那类静默故障的典型）。
func _keys_at(action_name: String, t: float, track_type: int) -> Dictionary:
	var out := {}
	if not ready or not actions.has(action_name):
		return out
	var a := player.get_animation(action_name)
	if a == null:
		return out
	for tr in a.get_track_count():
		if a.track_get_type(tr) != track_type:
			continue
		var bone := _bone_of_track(a, tr)
		if bone == "":
			continue
		var n := a.track_get_key_count(tr)
		if n <= 0:
			continue
		var k := n - 1
		if t >= 0.0:
			k = 0
			var best := absf(a.track_get_key_time(tr, 0) - t)
			for i in n:
				var d := absf(a.track_get_key_time(tr, i) - t)
				if d < best:
					best = d
					k = i
		out[bone] = a.track_get_key_value(tr, k)
	return out


## 每根骨在 `t` 时刻的**局部旋转**（`{骨名: Quaternion}`）。
func rotations_at(action_name: String, t := -1.0) -> Dictionary:
	return _keys_at(action_name, t, Animation.TYPE_ROTATION_3D)


## 每根骨在 `t` 时刻的**局部位置**（`{骨名: Vector3}`）。★ N52 新增。
##
## ## 为什么需要它
##
## 形态骨「展开」这件事，**有一大半是靠位移表达的** —— 柯西那 8 根里
## `RearHang.R` 两端位置差 **1.1607**（模型本地单位）≈ **118% 身高**，
## `RearHang.L` 0.9876、`BinderBack.L/R` 0.3724 / 0.2800、`Wing.L/R` 0.1119、
## `BinderFront.L/R` 0.0953 / 0.0776。
##
## 而轮 42 的帧末焊（`FormWeld`）**只接管 rotation** ⇒ 位置一直留在当前动画手里
## ⇒ 世界变换 = **旋转取焊缝 ＋ 位移取动画**。翼板于是「以展开的角度贴回常态位置」，
## 玩家读作「翼关上了 / 飘到乱七八糟的地方」。
##
## ## ⚠️ 单位与空间：**不需要任何换算**（本轮实测，T37）
##
## glTF 的 `translation` 与 `Skeleton3D.get_bone_pose_position()` 是**同一个量**
##（父空间里的绝对局部位置，T34）：
## `fly` 时 `RearHang.R` 读 `(-0.1414, -0.2820, -0.0594)`，
## 与 `assets/models/xi/anim/xi_form_on.glb` 首帧 `t=0.0333` 的值**逐位相同**。
##
## ⚠️ 世界尺度 = 本地值 × (`target_height` / `model_native_height`)
##（柯西 28.0 / 0.9814 ≈ 28.53）⇒ 上面的 1.1607 在世界里是 **33.1 单位**。
func locations_at(action_name: String, t := -1.0) -> Dictionary:
	return _keys_at(action_name, t, Animation.TYPE_POSITION_3D)


## 从轨道路径里解出骨名（`Skeleton3D:BinderBack.L` → `BinderBack.L`）。
func _bone_of_track(a: Animation, tr: int) -> String:
	var p := a.track_get_path(tr)
	if p.get_subname_count() >= 1:
		return str(p.get_subname(0))
	# 回退：某些路径写成 `Skeleton3D/Bone` 形式
	var s := str(p)
	var i := s.rfind(":")
	if i >= 0:
		return s.substr(i + 1)
	return ""


## 从**旁路** glb 里抽一条「逐帧骨姿态曲线」，**不登记进动作表**。
##
## ---- 为什么不能用 `_graft_extras()` ----
##
## 那条路会把动画挂进播放器、进 `actions` ⇒ 它变成一个**可被播的动作**。
## 而曲线源的动画名常是 Blender 默认的 `Xi_RigAction`（不是交付契约里的动作名）：
## 登记进去会污染动作表，也会让「动作总数 == 33」这类断言失准。
## 这里**只要数据、不要可播性** —— 抽完就把临时实例 `free()` 掉，播放器一个字节都不动。
## ★ 柯西当前的源 `xi_cruise_on.glb` 恰好**本身就在动作表里**、动画名也是
## 契约名 `cruise_on`；本函数仍按"旁路抽取"处理，**不重复登记**。
##
## ---- 为什么按**下标 0** 取动画而不是按名字 ----
##
## 名字是 Blender 默认名，换一次导出就可能变；而这类「曲线源」文件的契约
## 就是**只含一个动画**（`glb_strip_anim.py --verify` 已核对）。
##
## 用途：`FormCurveModifier` 的形态曲线源（N42·十三）。
##
## 返回 `{"t0": float, "t1": float, "bones": {骨名: {"t": PackedFloat32Array, "q": Array[Quaternion]}}}`。
## `t0`/`t1` = 各骨时间轴的**并集**（曲线层的归一化轴）；取不到 ⇒ 空字典 / 空 `bones`。
## ⚠️ **不告警**：没有形态曲线的模型（18 个老资产 + 任何单形态模型）都走这里。
##
## ★★ **必须连时间一起返回**：Godot 导入器对 CUBICSPLINE 会**抽稀**
##（某根骨姿态恒定的那一段，几十个采样点被压成首尾两点），于是各骨的
## **关键帧数不同、间隔也不再相等**。只给姿态序列的话，上层只能按
## "下标 ÷ 各自帧数"取点 ⇒ 各骨节奏**各自错位**。
## 实测（N42·十三）：按时间取时这段曲线是「先 Binder、后 Wing」；
## 按下标取时 `Wing.L` 在 `morph=0.25` 就已经转了 12°（而它那时应当还是 0）。
const CURVE_CACHE_LIMIT := 32
static var _curve_cache:Dictionary={}
static func _cache_curve_result(key:String,result:Dictionary)->Dictionary:
	# Store data only: no temporary scenes, meshes, textures or mutable caller state.
	if _curve_cache.size()>=CURVE_CACHE_LIMIT and not _curve_cache.has(key):
		_curve_cache.erase(_curve_cache.keys()[0])
	_curve_cache[key]=result.duplicate(true)
	return result

func load_curve_from(path: String, bone_names: PackedStringArray) -> Dictionary:
	var out := {"t0": 0.0, "t1": 1.0, "bones": {}}
	if path == "" or not ResourceLoader.exists(path):
		return out
	var key:=path+"|"+str(FileAccess.get_modified_time(path))+"|"+var_to_bytes(bone_names).hex_encode()
	if _curve_cache.has(key):return _curve_cache[key].duplicate(true)
	var ps := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if ps == null:
		return _cache_curve_result(key,out)
	var tmp := ps.instantiate()
	var ap := find_player(tmp)
	if ap == null:
		tmp.free()
		return _cache_curve_result(key,out)
	var lst := ap.get_animation_list()
	if lst.is_empty():
		tmp.free()
		return _cache_curve_result(key,out)
	var curve_name: StringName = &"form_on" if ap.has_animation("form_on") else lst[0]
	var a := ap.get_animation(curve_name)
	if a == null:
		tmp.free()
		return _cache_curve_result(key,out)
	# `track_get_key_value()` 取的是**真值**，不含 CUBICSPLINE 的入/出切线
	# （切线只在 glb 的 raw buffer 里占 3 倍分量，导入器已还原）。
	var bones := {}
	var t0 := INF
	var t1 := -INF
	for bone: String in bone_names:
		for tr in a.get_track_count():
			if a.track_get_type(tr) != Animation.TYPE_ROTATION_3D:
				continue
			if _bone_of_track(a, tr) != bone:
				continue
			var n := a.track_get_key_count(tr)
			if n < 2:
				break          # 少于 2 帧构不成曲线 ⇒ 交给上层退回两点线性
			var ts := PackedFloat32Array()
			var qs: Array[Quaternion] = []
			for k in n:
				ts.append(a.track_get_key_time(tr, k))
				qs.append(a.track_get_key_value(tr, k))
			bones[bone] = {"t": ts, "q": qs}
			t0 = minf(t0, ts[0])
			t1 = maxf(t1, ts[n - 1])
			break
	tmp.free()
	if bones.is_empty():
		return _cache_curve_result(key,out)
	out["t0"] = t0 if is_finite(t0) else 0.0
	out["t1"] = t1 if is_finite(t1) else 1.0
	out["bones"] = bones
	return _cache_curve_result(key,out)
