class_name SuiteModelAnim
extends RefCounted
## 模型自带骨骼动画的**绑定门**（棒 12 测试官 · 2026-09-26）。
##
## ## 为什么要有这一套
##
## 138 段动作的交付契约是「**Action 名全在且无多余**」，而这条契约
## **在引擎侧从来没有被验过**：全仓 0 个 `AnimationPlayer.play()`（N28），
## 锚点来自程序化的 `SuitRig`（硬编码佩涅罗佩槽位表，N30）。
## 于是"名字对不对"和"锚点跟不跟"这两件事**没有任何自动手段**——
## 而它们一旦错，138 段全部白做，且**不报任何错**。
##
## 这一套钉的就是这两件事：
##   ① **名字**：生产清单里**每一件** glb 都真的只有那一个 Action，且名字逐字等于契约；
##   ② **跟随**：动作播起来时，生产侧的锚点**确实在动**（对照旧路径恒 0）。
##
## ⚠️ 它**不测好不好看**。动作的观感只有人眼能判，判据在
## `tools/xi_anim_probe.tscn --shots` 出的帧图里（每个锚点带一颗彩色标记球）。

const XI_DIR := "res://assets/models/xi/"
## ★ N56 巡航归位段（`__cruise_hold__`）的两个**源**（见 `_cruise_hold()` 的长说明）。
const FORM_ON := XI_DIR + "anim/xi_form_on.glb"
const CRUISE_IDLE := XI_DIR + "anim/xi_cruise_idle.glb"
## 期望的「文件 → 动作名 → 时长(s)」= **`SuitProfile.xi().model_anim_files` 的镜像**
##（35 条剥壳动作件，在 `anim/` 子目录下；主模型 `xi_fly.glb` 自带 `fly`，不在此表）。
##
## ⚠️ 2026-09-27 起本表**每加一件资产就要跟着加**（`_profiles` 里有一条
## 「与生产清单逐条同序相同」的集合断言把关 —— 漏加会当场变红，不会静默漂移）。
##   ① 3 → 32 条：柯西 33 段动作**全量**装进工程（主模型自带 `fly` ＋ 32 件 extras）；
##      旧的 3 条指向 `assets/models/xi/` **根目录的旧完整版**（v12 骨架、
##      每件 4.3 MB、含 202 张贴图），它们既不进生产清单、也不再被任何代码加载，
##      留着只会让"名字对不对"这条契约测在一批死文件上。
##   ② 32 → 35 条（N42·二十一 方案 B ＋ N42·二十二 回程过渡）：
##      `form_on` / `form_off` / `cruise_idle` 三件 —— 见 `SuitProfile.xi()`
##      里「★ 巡航形态（3）」那一段。
##
## 时长口径：glTF 采样器 `input` 访问器 `max`（秒），30 fps 烘焙。
## ⚠️ 是 `max` 而不是「跨度」：`form_on` 14 帧的**跨度**是 0.4333 s，
##    但采样器落在 0.0333..0.4667 ⇒ 本表填 **0.4667**（`xi_cruise_on` 同理）。
## 逐条与 `_relay/list_anim_meta.py` 的输出对齐（该脚本可重新生成本表）。
const EXPECTED := [
	["anim/xi_burst.glb", "burst", 1.3333],
	["anim/xi_burst_cruise.glb", "burst_cruise", 1.3333],
	["anim/xi_cruise_on.glb", "cruise_on", 0.4667],
	["anim/xi_shield.glb", "shield", 1.8667],
	["anim/xi_shoot.glb", "shoot", 0.4000],
	["anim/xi_slash.glb", "slash", 1.5000],
	# ---- ★ 巡航形态（3 · N42·二十一 方案 B / N42·二十二 回程）----
	["anim/xi_form_on.glb", "form_on", 0.4667],
	["anim/xi_form_off.glb", "form_off", 0.4667],
	["anim/xi_cruise_idle.glb", "cruise_idle", 0.0667],
	["anim/xi_trans_burst_to_fly.glb", "trans_burst_to_fly", 0.4000],
	["anim/xi_trans_fly_to_burst.glb", "trans_fly_to_burst", 0.3333],
	["anim/xi_trans_fly_to_slash.glb", "trans_fly_to_slash", 0.2667],
	["anim/xi_trans_slash_to_fly.glb", "trans_slash_to_fly", 0.3333],
	["anim/xi_dash_b.glb", "dash_b", 0.4000],
	["anim/xi_dash_bl.glb", "dash_bl", 0.4000],
	["anim/xi_dash_br.glb", "dash_br", 0.4000],
	["anim/xi_dash_f.glb", "dash_f", 0.4000],
	["anim/xi_dash_fl.glb", "dash_fl", 0.4000],
	["anim/xi_dash_fr.glb", "dash_fr", 0.4000],
	["anim/xi_dash_l.glb", "dash_l", 0.4000],
	["anim/xi_dash_r.glb", "dash_r", 0.4000],
	["anim/xi_fly_b.glb", "fly_b", 2.0000],
	["anim/xi_fly_bl.glb", "fly_bl", 2.0000],
	["anim/xi_fly_br.glb", "fly_br", 2.0000],
	["anim/xi_fly_f.glb", "fly_f", 2.0000],
	["anim/xi_fly_fl.glb", "fly_fl", 2.0000],
	["anim/xi_fly_fr.glb", "fly_fr", 2.0000],
	["anim/xi_fly_l.glb", "fly_l", 2.0000],
	["anim/xi_fly_r.glb", "fly_r", 2.0000],
	["anim/xi_turn_pitch_down.glb", "turn_pitch_down", 1.2000],
	["anim/xi_turn_pitch_up.glb", "turn_pitch_up", 1.2000],
	["anim/xi_turn_roll_L.glb", "turn_roll_L", 1.2000],
	["anim/xi_turn_roll_R.glb", "turn_roll_R", 1.2000],
	["anim/xi_turn_yaw_L.glb", "turn_yaw_L", 1.2000],
	["anim/xi_turn_yaw_R.glb", "turn_yaw_R", 1.2000],
]
## 13 根锚点骨 —— 与 `clip_manifest.csv` 的 `xi-skeleton` 行、以及
## `SuitRig.PARTS` 的语义槽位名逐字一致。**少一根就等于少一个可用锚点。**
const ANCHOR_BONES := [
	"head", "chest", "waist",
	"hand_L", "hand_R", "shield_L", "shield_R",
	"muzzle_L", "muzzle_R",
	"thruster_L", "thruster_R",
	"vulcan_port", "vulcan_stbd",
]
## 骨架骨数 —— **交付契约**：交付件 `Skeleton3D.get_bone_count()` 必须与 rig 定版一致。
## ⚠️ 2026-09-27 **N42·十七**：柯西 rig 定版升到 **`xi_rig_v16`（50 → 51 骨）** ——
##    新增 `ChestVent`（父级 `Chest`，承载 `tripo_part_82`/`tripo_part_86` 的**纯平移 113.42 mm**，
##    旋转恒为 0 ⇒ 别用"角度"筛它）⇒ 33 段成品 `anim/xi_*.glb` 全部重导为 **51 骨**。
##    ★ 加/删骨（哪怕是纯平移骨、哪怕骨架签名之外什么都看不出）**必须同步改这里**，
##      否则本套件 23 条契约断言会整批变红，而现象只是一个数字。
const BONE_COUNT := 51


static func run(t: T, host: Node) -> void:
	t.suite("ModelAnim / 交付契约（名字）")
	_contract(t)
	t.suite("ModelAnim / 档案接线")
	_profiles(t)
	t.suite("ModelAnim / 摘动作的资源隔离")
	await _isolation(t, host)
	t.suite("ModelAnim / 锚点来源与跟随")
	await _anchors(t, host)
	t.suite("ModelAnim / 归位到 rest")
	await _reset_to_rest(t, host)
	t.suite("ModelAnim / 空待机的收尾混合载体（N50）")
	await _rest_hold(t, host)
	t.suite("ModelAnim / 巡航归位段（N56）")
	await _cruise_hold(t, host)


## ★ 摘动作**不许污染共享资源**。
##
## ## 为什么要单独钉这一条
##
## 从 glb 导入的 `AnimationLibrary` 是**共享资源**：同一个 `.glb` 实例化出多少份，
## 指向的都是同一个库对象。`ModelAnimator.setup()` 往默认库里 `add_animation()`
## 摘进 `burst` / `burst_cruise` —— 不私有化的话改的是**全局那一份**。
##
## 症状（2026-09-26 实测）：`xi_fly.glb` 的实例 `get_animation_list()` 从 1 个
## 变成 3 个。**而且只有在"别的代码先建过一台柯西"之后才出现。**
##
## ⇒ 这正是「本套件单跑全绿、全量回归才红」的那类 bug：
##   `_contract(t)` 是本套件第一段，跑它的时候还没有任何东西来得及污染，
##   所以它**永远看不见**这个缺陷。这一条刻意先建一台柯西**制造**污染条件，
##   再从磁盘重新 `load()` 一次去验 —— 顺序反了它就白测。
static func _isolation(t: T, host: Node) -> void:
	# ---- 制造条件：先真的建一台柯西（会触发 ModelAnimator.setup ⇒ 摘动作）----
	var body := FlightBody.new()
	body.name = "IsolationBody"
	body.profile = SuitProfile.xi()
	body.use_placeholder = false
	body.flight_pitch_deg = 0.0
	host.add_child(body)
	# ⚠️ **立刻**冻物理：测试场景是个没有地面的空世界，物理一开机体会在
	# 头几个物理帧内坠落触发 `destroy(…, "撞海")`（日志里会看到
	# `[destroy] MESSER: 撞海`），而 `destroy()` 会关掉 `model_root.visible`。
	# 本段只数动作个数、不受可见性影响，但留着坠毁会污染日志、也拖慢退出。
	body.set_physics_process(false)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	body.set_physics_process(false)
	# ⚠️ **别硬编码动作个数** —— 交付件每加一件都会把这里顶红
	#（N42·二十一 加 `cruise_idle`/`form_on` 2 件、N42·二十二 加 `form_off` 1 件）。
	# 本条判据的**本意**是"每个登记的文件都贡献了**恰好一个**可播动作，
	# 外加主模型自带的 `fly`" ⇒ 直接拿登记表算期望值：
	# 缺件（文件不在 / 导不进来）、多件（一个 glb 带两个 Action）都会当场对不上。
	var want_actions: int = SuitProfile.xi().model_anim_files.size() + 1
	t.ok(body.model_anim.action_names().size() >= want_actions,
		"（前置）真柯西身上 %d 个动作齐 —— 主模型 fly ＋ model_anim_files %d 件"
		% [want_actions, want_actions - 1])
	body.free()
	await host.get_tree().process_frame

	# ---- 验证：共享资源没被写穿 ----
	# `load()` 走缓存 ⇒ 如果库被污染，这里拿到的就是被污染的那份。
	for row: Array in EXPECTED:
		var path: String = XI_DIR + str(row[0])
		var ps := load(path) as PackedScene
		if ps == null:
			t.ok(false, "重新加载 %s 失败" % row[0])
			continue
		var inst := ps.instantiate()
		var ap := ModelAnimator.find_player(inst)
		if ap == null:
			t.ok(false, "%s 重新加载后没有 AnimationPlayer" % row[0])
			inst.free()
			continue
		var names: PackedStringArray = ap.get_animation_list()
		t.eq(names.size(), 1,
			"★ %s 仍只有 1 个 Action（建过一台柯西之后，实测 %d 个）"
			% [row[0], names.size()])
		if names.size() >= 1:
			t.eq(str(names[0]), str(row[1]),
				"★ %s 的动作名没被别的动作顶掉（仍是 '%s'）" % [row[0], row[1]])
		inst.free()


## 生产清单每一件的**动作名与时长**。这是"能不能按名查表"的唯一自动判据。
static func _contract(t: T) -> void:
	for row: Array in EXPECTED:
		var path: String = XI_DIR + str(row[0])
		t.ok(ResourceLoader.exists(path), "资产存在且已导入 %s" % row[0])
		if not ResourceLoader.exists(path):
			continue
		var ps := load(path) as PackedScene
		t.ok(ps != null, "%s 是 PackedScene" % row[0])
		if ps == null:
			continue
		var inst := ps.instantiate()
		# ---- 骨架 ----
		var skel: Skeleton3D = null
		for c in inst.find_children("*", "Skeleton3D", true, false):
			skel = c as Skeleton3D
			break
		t.ok(skel != null, "%s 带 Skeleton3D" % row[0])
		if skel != null:
			t.eq(skel.get_bone_count(), BONE_COUNT, "%s 骨数 = %d" % [row[0], BONE_COUNT])
			var missing: Array = []
			for b: String in ANCHOR_BONES:
				if skel.find_bone(b) < 0:
					missing.append(b)
			t.eq(missing.size(), 0, "%s 13 根锚点骨齐全（缺 %s）" % [row[0], str(missing)])
		# ---- 动作：**只有一个**，且名字逐字相等 ----
		var ap := ModelAnimator.find_player(inst)
		t.ok(ap != null, "%s 带 AnimationPlayer" % row[0])
		if ap != null:
			var names: PackedStringArray = ap.get_animation_list()
			t.eq(names.size(), 1, "%s 里只有 1 个 Action" % row[0])
			if names.size() >= 1:
				t.eq(str(names[0]), str(row[1]),
					"%s 的动作名逐字 = '%s'（Godot 不加前缀）" % [row[0], row[1]])
				var a := ap.get_animation(names[0])
				t.near(a.length, float(row[2]), 0.05,
					"%s 时长 ≈ %.4f s" % [row[0], float(row[2])])
		inst.free()


## 档案接线：只有柯西配了额外动作文件，别的机体一个都没配
##（老资产零影响的前提 —— 18 个老 glb 实测 `skins: 0 / animations: 0`）。
static func _profiles(t: T) -> void:
	var p := SuitProfile.xi()
	t.eq(p.model_anim_files.size(), EXPECTED.size(), "柯西配了 %d 个动作文件" % EXPECTED.size())
	# ★ 表必须是生产清单的**镜像**，不能只是"条数对上"：
	#   光比 size，仍挡不住"表里多一件、清单里少一件"（数目相抵、逐条动作名也各自对）。
	#   ⇒ 把 `EXPECTED` 里每条拼回全路径，与 `model_anim_files` **逐条同序**比一次。
	#   这条是"上面那张表会不会悄悄失同步"的唯一把关，改清单就必须跟着改表。
	var mirror: Array[String] = []
	for row: Array in EXPECTED:
		mirror.append(XI_DIR + str(row[0]))
	t.eq(str(p.model_anim_files), str(mirror),
		"镜像表与生产清单**逐条同序相同**（%d 件）" % mirror.size())
	for f: String in p.model_anim_files:
		t.ok(ResourceLoader.exists(f), "档案里的动作文件存在：%s" % f)
	t.eq(p.model_anim_idle, "fly", "待机动作名 = fly")
	t.eq(p.model_anim_burst, "burst", "全弹发射动作名 = burst")
	t.eq(p.model_anim_burst_cruise, "burst_cruise", "巡航版全弹发射动作名 = burst_cruise")
	# ⚠️ 2026-09-26（棒 12）起 `model_path` **已经**换成带骨的那件了 ——
	# 那个"前提是 `cruise_on` 到位"的条件由 `CruiseFormModifier` 满足
	#（`cruise_on` 的骨骼版，形态基准直接取自 `burst_cruise` 末帧，不需要新动作）。
	# `cruise_morph` 开关照旧为真：它现在同时驱动 blend shape（老路径）
	# 与骨骼形态层（新路径），两条并列，谁在场谁生效。
	t.ok(p.cruise_morph, "柯西开着巡航变形（新路径由骨骼形态层承载，见 CruiseFormModifier）")
	t.ok(p.model_path.ends_with("xi_movie_rigged.scn"),
		"柯西 `model_path` 指向带骨的新资产（%s）" % p.model_path.get_file())
	# 别的机体一个都不许配 —— 「只给柯西接线」是"老资产零影响"的前提。
	# 这里点名枚举而不用"遍历所有档案"，是因为本工程没有 `SuitProfile.all()`
	#（档案是静态工厂，每个 `Id` 一个），枚举能写全、也不会随新机体静默漏检。
	#
	# ★ 2026-09-28（N44）：**佩涅罗佩已接线**（27 段）⇒ 它从这张「老资产」表里
	#   **移出**，改成下面单独判它自己的登记。⛔ 不是把断言删掉 —— 「其余机体仍是 0」
	#   这条语义**逐字未变**，变的只是样本集合跟着事实走。
	#   ⚠️ **将来哪台接线了，就把它从这里移到下面那段**（⛔ 别直接删）。
	# ★ 2026-09-28（N49）：**四台机体全部接线**（各 27~28 段）⇒ 原来这条
	#   「别的机体一个都不许配」**语义已不成立**：它当时的前提是"只有柯西接线"，
	#   靠"其余为空"来防误接线。现在改成**正向对账** —— 每台登记的段数必须
	#   **等于它实装的那一套**，一个不多一个不少。
	#   ⛔ 不是把断言删掉：「防漏配 / 防多配 / 防配错台」这件事原样保留，
	#   只是判据从"空"换成"等于期望值"。⚠️ 期望值写在这里，
	#   **加动作资产时要同步改这张表**（§8 R5）。
	var tables := {
		"阿利宙斯(常态)": [SuitProfile.arizeus(), 28],
		"阿利宙斯(核心·量产型ν高达)": [SuitProfile.arizeus(SuitProfile.ArizeusForm.CORE_NU), 27],
		"古斯塔夫": [SuitProfile.gustav00(), 27],
		"梅萨 M01": [SuitProfile.messer_m01(), 27],
	}
	for label: String in tables:
		var row: Array = tables[label]
		var f: SuitProfile = row[0]
		t.eq(f.model_anim_files.size(), int(row[1]),
			"%s 登记的段数 == 实装段数（%d）" % [label, int(row[1])])
	# 巡航形态**仍走老路径**（交付侧没有巡航形态的绑定件 ⇒ 主模型还是无骨架旧件）
	# ⇒ 它必须是 0，而且这条**要留着**：它是下面两处「老资产零影响」测试的**样本来源**
	#   （`suite_model_fsm._mute()` / `suite_cruise_form._zero()` 都换成它了）。
	t.eq(SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE).model_anim_files.size(), 0,
		"阿利宙斯巡航形态仍是老路径（无绑定件 ⇒ 无动作；它同时是老路径样本）")
	t.not_ok(p.model_anim_files.size() == 0, "柯西确实配了动作文件（上面那条别写反）")

	# ---- ★ N44：佩涅罗佩（第二台接线的机体）----
	# ★ 主模型必须是**自带动作**的那一件（`penelope_fly.glb` = `rig_v3` + `fly`）——
	#   `ModelAnimator.setup()` 以「主实例里有没有 `AnimationPlayer`」为判据，
	#   拿 0 动画的纯绑定件当主模型 ⇒ `ready=false`、27 段**一段都装不进去且不报错**。
	var pen := SuitProfile.penelope()
	t.eq(pen.model_anim_files.size(), 27,
		"佩涅罗佩登记 27 段（主模型自带 fly ⇒ 可播 28）")
	# ★ N46（2026-09-28 用户裁决）：「飞行待机动作就别加进去了……很违和」
	#   ⇒ 佩涅罗佩 `model_anim_idle` **刻意置空**（主模型自带的 `fly` 是 2.0 s / 60 帧
	#   的循环，飞行时一直在动）。置空后飞行中静止在绑定姿态 —— 与 N44 之前那件
	#   无动画的 `rx104_penelope.glb` 观感一致。
	#   ⚠️ 这条**不是**"漏配"：柯西的 `fly` 一行未动（上一段已断言）。
	t.eq(pen.model_anim_idle, "", "佩涅罗佩不播飞行待机（N46 用户裁决，刻意置空）")
	t.ok(pen.model_path.ends_with("penelope_movie_rigged.scn"),
		"佩涅罗佩 `model_path` 指向**自带动作**的那件（%s）" % pen.model_path.get_file())
	# 新版佩涅罗佩已导入双向巡航变形。
	t.eq(pen.model_anim_idle_cruise, "cruise_idle", "新版佩涅罗佩登记巡航保持动作")
	t.eq(pen.model_anim_form_on, "form_on", "新版佩涅罗佩登记变形动作")
	t.eq(pen.model_anim_form_off, "form_off", "新版佩涅罗佩登记反向变形动作")
	t.eq(pen.model_form_curve, pen.model_path, "新版佩涅罗佩使用本机机械曲线")
	# ★ `burst` / `burst_cruise` **刻意保持默认值**（不是漏配）：拿不到动作时
	#   `burst_action_for_form()` 返回 `""` ⇒ `request_burst()` 安全退化；
	#   将来补了 `penelope_burst.glb`（动画名 `burst`）会自动生效。
	t.eq(pen.model_anim_burst, "burst", "佩涅罗佩 burst 保持默认（前瞻性，不是漏配）")
	for f2: String in pen.model_anim_files:
		t.ok(ResourceLoader.exists(f2), "档案里的动作文件存在：%s" % f2)


## 锚点：**来源**（必须命中模型骨架）与**跟随**（动作播起来必须动）。
##
## 跟随的那条对照是关键：同一动作、同一时刻，占位骨架那条路的锚点行程恒为 0
## —— 那就是 N30 说的"动作播起来时模型在动、锚点不动"。
static func _anchors(t: T, host: Node) -> void:
	var p := SuitProfile.xi()
	# 显式写死带骨的那件（而不是依赖档案的当前值）—— 本段判的是**模型骨架**，
	# 换了档案不该让这一段的语义跟着漂。
	p.model_path = SuitProfile.xi().model_path
	var body := FlightBody.new()
	body.profile = p
	body.is_player = true
	body.use_placeholder = false
	body.flight_pitch_deg = 0.0
	host.add_child(body)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame

	t.eq(body.model_anim != null and body.model_anim.ready, true, "绑定建立起来了")
	var from_model := 0
	for b: String in ANCHOR_BONES:
		if body.anchor_from_model(b):
			from_model += 1
	t.eq(from_model, ANCHOR_BONES.size(), "13 根锚点全部取自模型骨架（实测 %d）" % from_model)
	# N5：柯西单手持枪 ⇒ 两个炮口槽位重合
	var ml: Vector3 = body.rig_anchor("muzzle_L")
	var mr: Vector3 = body.rig_anchor("muzzle_R")
	t.lt(ml.distance_to(mr), 1.0e-4, "muzzle_L 与 muzzle_R 重合（单手持枪，距离 %.6f m）" % ml.distance_to(mr))
	# 锚点与骨的真实世界位姿之差 ⇒ 同源，应当 ≈ 0
	t.lt(body.anchor_follow_error("muzzle_R"), 1.0e-3,
		"锚点与骨位姿之差 %.6f m" % body.anchor_follow_error("muzzle_R"))

	# ---- 跟随：播 `burst`，量炮口行程 ----
	body.set_physics_process(false)
	var skel: Skeleton3D = body._model_skel
	t.ok(skel != null, "拿到模型骨架")
	if skel == null:
		body.free()
		return
	# 旧路径的对照点：完全照抄绑定之前的 `rig_anchor()` 算法。
	var suit0 := _suit_rig_anchor(body, "muzzle_R")
	var m0: Vector3 = body.rig_anchor("muzzle_R")
	body.model_anim.play_once("burst")
	var model_travel := 0.0
	var suit_travel := 0.0
	for _f in 60:
		await host.get_tree().process_frame
		model_travel = maxf(model_travel, m0.distance_to(body.rig_anchor("muzzle_R")))
		suit_travel = maxf(suit_travel, suit0.distance_to(_suit_rig_anchor(body, "muzzle_R")))
	# 60 帧里只要动作真在播，炮口一定挪得动 —— 门槛取 0.1 m
	#（实测 `burst` 全程 3.58 m，这里只跑一段，取一个"明显非零"的门）。
	t.gt(model_travel, 0.10, "★ 锚点随动作移动：muzzle_R 行程 %.4f m" % model_travel)
	t.lt(suit_travel, 1.0e-6, "对照：占位骨架同一动作下行程 %.9f m（旧路径恒 0）" % suit_travel)
	body.set_physics_process(true)
	body.free()


## 绑定之前 `rig_anchor()` 的算法（占位骨架那条路），只用于对照。
static func _suit_rig_anchor(body: FlightBody, slot: String) -> Vector3:
	if body.rig == null:
		return Vector3.ZERO
	var s := body.rig.slot(slot)
	if s == null:
		return Vector3.ZERO
	return body.model_pivot.transform * (body.model_root.position + body.rig.transform * s.position)


## ★★ N47（2026-09-28）：`reset_to_rest()` 必须**真的**回到 rest。
##
## ## 为什么非有它不可
##
## 用户报：「**一按下八向冲刺模型就整个乱七八糟**」。根因 = N46 把佩涅罗佩的
## `model_anim_idle` 置空（用户裁决：飞行待机违和）⇒ `ModelAnimFSM._enter_idle()`
## 一拿到空待机就走 `anim.reset_to_rest()`；而那个实现按「pose 是相对 rest 的偏移」
## 把三项写成 `Quaternion()` / `ZERO` / `ONE` —— **错**：`Skeleton3D` 的 pose 是
## 骨骼在**父空间里的绝对局部变换**。实测模型被压成一个尖刺团
##（出图 `_relay/n47_pose/after_dash_idle.png`，修前 vs 修后 `n47_pose_fixed/`）。
##
## ## 三条判据（缺一不可）
##
##   ① **前置**：动作真的把姿态改动了 —— 否则下面两条会**空洞地**通过；
##   ② **正判**：`reset_to_rest()` 之后与**出厂 rest** 最大夹角 < 1°、骨原点位移 < 1e-4 m；
##   ③ ★ **证伪条**：故意用旧写法（三个 setter 归零）必须**离 rest 很远**（> 90°）。
##      没有 ③ 的话，② 在「把 `reset_to_rest()` 写空」时也会绿 —— 恒真断言。
static func _reset_to_rest(t: T, host: Node) -> void:
	var pen := SuitProfile.penelope()
	var ps := load(pen.model_path) as PackedScene
	t.ok(ps != null, "佩涅罗佩主模型可载入（%s）" % pen.model_path.get_file())
	if ps == null:
		return
	var inst := ps.instantiate() as Node3D
	host.add_child(inst)
	await host.get_tree().process_frame

	var skel: Skeleton3D = null
	for c in inst.find_children("*", "Skeleton3D", true, false):
		skel = c as Skeleton3D
		break
	t.ok(skel != null, "拿到佩涅罗佩骨架")
	if skel == null:
		inst.free()
		return

	var ma := ModelAnimator.setup(inst, pen.model_anim_files)
	t.ok(ma.ready, "动画器建立起来了（主模型自带 AnimationPlayer）")
	if not ma.ready:
		inst.free()
		return

	# ---- 参照：出厂 rest ----
	var rest := _snap(skel)

	# ---- ① 前置断言：动作真的写进去了 ----
	var moved := 0.0
	if ma.has("dash_r"):
		ma.player.play("dash_r")
		ma.player.seek(0.2, true)
		await _pump(host, 3)
		moved = _max_angle(rest[0], _snap(skel)[0])
	t.gt(moved, 5.0, "（前置）冲刺动作真的改动了姿态：与 rest 最大 %.3f°" % moved)

	# ---- ② 正判 ----
	ma.reset_to_rest()
	await _pump(host, 3)
	var ok_pose := _snap(skel)
	t.eq(ok_pose[0].size(), skel.get_bone_count(), "姿态快照覆盖全部 %d 骨" % skel.get_bone_count())
	t.lt(_max_angle(rest[0], ok_pose[0]), 1.0,
		"★ reset_to_rest() 后与出厂 rest 最大夹角 %.4f°（应 < 1°）" % _max_angle(rest[0], ok_pose[0]))
	t.lt(_max_origin_delta(rest[1], ok_pose[1]), 1.0e-4,
		"★ reset_to_rest() 后骨原点最大位移 %.6f m（应 < 1e-4）"
		% _max_origin_delta(rest[1], ok_pose[1]))

	# ---- ③ ★ 证伪条：旧写法必须离 rest 很远（证明 ② 不是恒真断言）----
	ma.reset_to_rest()
	await _pump(host, 2)
	for i in skel.get_bone_count():
		skel.set_bone_pose_rotation(i, Quaternion())
		skel.set_bone_pose_position(i, Vector3.ZERO)
		skel.set_bone_pose_scale(i, Vector3.ONE)
	await _pump(host, 3)
	var bad := _snap(skel)
	t.gt(_max_angle(rest[0], bad[0]), 90.0,
		"★ 证伪条：旧的「三个 setter 归零」离 rest %.3f°（> 90° ⇒ 正判不是恒真）"
		% _max_angle(rest[0], bad[0]))
	t.gt(_max_origin_delta(rest[1], bad[1]), 0.5,
		"★ 证伪条：旧的「三个 setter 归零」骨原点位移 %.4f m（> 0.5 m）"
		% _max_origin_delta(rest[1], bad[1]))

	# ---- 收拾干净（⛔ 别把污染留给下一段）----
	ma.reset_to_rest()
	await _pump(host, 2)
	inst.free()


## 读一遍全骨 pose。返回 `[局部旋转字典, 骨原点字典]`（骨架空间）。
static func _snap(skel: Skeleton3D) -> Array:
	var q := {}
	var p := {}
	for i in skel.get_bone_count():
		var bn := skel.get_bone_name(i)
		q[bn] = skel.get_bone_pose_rotation(i)
		p[bn] = skel.get_bone_global_pose(i).origin
	return [q, p]


## 两个姿态字典的最大四元数夹角（度）。
##
## ★★ 取角用 `4·asin(‖a−b‖/2)`（见 `_q_angle_deg()`），**⛔ 不是 `2·acos(|dot|)`**。
##
##   原写法（N56 统一修正）在**近单位元处病态**：`acos(1−ε) ≈ √(2ε)` 把误差
##   **开平方根**，而 pose 四元数是 float32、来回一趟带 ~2e-7 模长缺陷
##   ⇒ 两个**逐分量只差 1e-8** 的姿态被印成 **0.0396°**。
##   本函数的两处调用容差是 1.0° / 90.0°，所以这个假地板**当时没让红**——
##   但它是个**会骗人的读数**，谁把容差一收紧就会炸。
##
##   ⚠️ 也**不能**图省事换成 `2·asin(max|Δc|)`：那个只在"起止同轴"时精确，
##   一般情形最坏**低估到 θ/√2**（实测 90° 读成 65.53°）。
##   `4·asin(‖a−b‖/2)` 是**对拍验证过的**：任意相位逐点精确 ＋ 噪声地板 ~1e-5°。
static func _max_angle(a: Dictionary, b: Dictionary) -> float:
	var worst := 0.0
	for k in a:
		if not b.has(k):
			continue
		worst = maxf(worst, _q_angle_deg(a[k] as Quaternion, b[k] as Quaternion))
	return worst


## 两四元数夹角（度），精确 ＋ 低噪声版。推导与对拍见 `_max_angle()` 的说明，
## 对拍脚本 = `_relay/_n56_angle_metric_cmp.py`。
static func _q_angle_deg(a: Quaternion, b: Quaternion) -> float:
	var q := b
	if a.dot(b) < 0.0:
		q = -b
	return rad_to_deg(4.0 * asin(clampf((a - q).length() * 0.5, 0.0, 1.0)))


static func _max_origin_delta(a: Dictionary, b: Dictionary) -> float:
	var worst := 0.0
	for k in a:
		if not b.has(k):
			continue
		worst = maxf(worst, (a[k] as Vector3).distance_to(b[k] as Vector3))
	return worst


static func _pump(host: Node, n: int) -> void:
	for _f in n:
		await host.get_tree().process_frame


# ============================================================ N50：空待机的混合载体

## ★★ N50（2026-09-28）：空待机的收尾必须有**混合载体**，否则过渡是硬切。
##
## ## 为什么非有这一条
##
## 用户报「**每个动作过渡都有点生硬**」。根因**不是** `BLEND_*` 取多少，而是
## **混合压根没发生**：Godot 的 `play(name, blend)` 是"从**上一段动画**的姿态
## 混过去"，播放器**停着**的时候没有"上一段" ⇒ `blend` 参数被完全忽略 ⇒ 硬切。
##
## 五台机体（佩涅罗佩 / 量产牛 / 阿利宙斯常态 / 古斯塔夫 / 梅萨）
## `model_anim_idle == ""`（用户要求不播飞行待机）⇒ 待机时**播放器是停着的**
## ⇒ **每一次进入动作、每一次动作收尾，都是零混合硬切**。
##
## 实测（`tools/_n50_smoothness.gd`，逐帧全骨姿态活动量 `A`、`J = A[i]-A[i-1]`）：
##
## | | 梅萨（空待机） | 柯西（有 `fly` 待机） |
## |---|---|---|
## | 全局 `\|J\|max` | **158.93** | **18.64** |
## | 「→ rest」收尾的 `J` | **134 ~ 159**（硬切） | **≈ 0 ~ 5** |
##
## ## 判据（★ 正判 + 证伪条，按 N47 T35 的规矩）
##
##   ① 正判：静置段建出来了，且**不污染动作表**（`has()` / `action_names()` 都查不到）；
##   ② 正判：空待机时播放器**在跑**、骨姿态 == 出厂 rest；
##   ③ ★ **证伪条**：直调 `reset_to_rest()` ⇒ `is_playing()` 必须变**假**。
##      没有 ③ 的话，② 在「把 `hold_rest()` 换成 `reset_to_rest()`」时照样绿 —— 恒真断言。
##   ④ 正判（生产路径）：`request_action()` → 播完 → 回 IDLE 之后，**载体没丢**。
static func _rest_hold(t: T, host: Node) -> void:
	var p := SuitProfile.messer_m01()
	t.eq(p.model_anim_idle, "", "（前置）梅萨待机置空 —— 空待机正是这一段的被测对象")
	var ps := load(p.model_path) as PackedScene
	t.ok(ps != null, "梅萨主模型可载入（%s）" % p.model_path.get_file())
	if ps == null:
		return
	var inst := ps.instantiate() as Node3D
	host.add_child(inst)
	await host.get_tree().process_frame
	var skel: Skeleton3D = null
	for c in inst.find_children("*", "Skeleton3D", true, false):
		skel = c as Skeleton3D
		break
	t.ok(skel != null, "拿到梅萨骨架")
	if skel == null:
		inst.free()
		return
	var ma := ModelAnimator.setup(inst, p.model_anim_files)
	t.ok(ma.ready, "动画器建立起来了（主模型自带 AnimationPlayer）")
	if not ma.ready:
		inst.free()
		return
	# ★★ 必须**复刻生产路径**的这一步赋值（`FlightBody._setup_model_anim()` 的活）。
	#
	# ⚠️ 本段第一版漏了它 ⇒ `ma.idle_action` 留着**默认值 `"fly"`** ⇒
	#   `idle_action_for_form()` 拿到 `"fly"`（梅萨主模型自带这段）⇒ 走的是
	#   "有飞行待机"的**老路**，压根到不了 `_begin_rest()` —— 现象是 5 条断言
	#   一起红（动作名 got=fly、姿态离 rest 16°/0.1476 m，那正是 `fly` 的姿势）。
	#   ⇒ **"空待机"这个前提不是模型自带的，是 profile 赋进来的**；
	#      测它就必须把 profile 那一半也搬过来。
	# ⚠️ `prepare_loops()` 必须在赋值**之后**再跑一次（时序陷阱，见 `ModelAnimator`）。
	ma.idle_action = p.model_anim_idle
	ma.burst_action = p.model_anim_burst
	ma.burst_cruise_action = p.model_anim_burst_cruise
	ma.idle_cruise_action = p.model_anim_idle_cruise
	ma.form_on_action = p.model_anim_form_on
	ma.form_off_action = p.model_anim_form_off
	ma.prepare_loops()
	t.eq(ma.idle_action, "", "（前置）动画器的待机名确实是空串 —— 空待机是赋进来的，不是模型自带的")
	var rest := _snap(skel)

	# ---- ① 静置段建出来了，且**不污染动作表** ----
	t.ok(ma.has_rest_clip(), "★ 静置段建出来了（has_rest_clip() == true）")
	t.not_ok(ma.has(str(ModelAnimator.REST_CLIP)), "★ 静置段**不是**动作（has() 查不到）")
	t.ok(not ma.action_names().has(str(ModelAnimator.REST_CLIP)),
		"★ 静置段不在 action_names() 里（否则会顶红「动作总数」那批断言）")

	# ---- ② 空待机：播放器**在跑** + 姿态 == 出厂 rest ----
	var fsm := ModelAnimFSM.create(ma)
	await _pump(host, 3)
	t.eq(fsm.current_action(), "", "空待机 ⇒ 状态机动作名仍是空串（对外语义没变）")
	t.ok(ma.player.is_playing(),
		"★★ 空待机时播放器**在跑**（下一次 play(blend) 才有前一段可混）")
	var d_ang := _max_angle(rest[0], _snap(skel)[0])
	var d_org := _max_origin_delta(rest[1], _snap(skel)[1])
	t.lt(d_ang, 1.0, "★ 播静置段时姿态 == 出厂 rest（最大 %.4f°）" % d_ang)
	t.lt(d_org, 1.0e-4, "★ 播静置段时骨原点 == 出厂 rest（最大 %.6f m）" % d_org)

	# ---- ③ ★ 证伪条：旧写法必须让播放器**停着** ----
	ma.reset_to_rest()
	await _pump(host, 2)
	t.not_ok(ma.player.is_playing(),
		"★ 证伪条：reset_to_rest() 之后播放器停着 ⇒ ②「在跑」不是恒真断言")

	# ---- ④ 生产路径：动作播完回 IDLE，**载体没丢** ----
	var act := "shoot"
	if not ma.has(act):
		for cand in ["slash", "shield", "dash_f", "fly_f"]:
			if ma.has(cand):
				act = cand
				break
	ma.hold_rest(0.0)
	await _pump(host, 2)
	var f2 := ModelAnimFSM.create(ma)
	t.ok(f2.request_action(act), "（前置）%s 起播（走 request_action）" % act)
	var t0 := Time.get_ticks_msec()
	while f2.state == ModelAnimFSM.State.ACTION and Time.get_ticks_msec() - t0 < 4000:
		await host.get_tree().process_frame
		f2.tick(0.016)
	t.eq(f2.state, ModelAnimFSM.State.IDLE,
		"★ %s 播完回 IDLE（实测 %d ms）" % [act, Time.get_ticks_msec() - t0])
	t.eq(f2.current_action(), "", "★ 回 IDLE 后动作名为空串")
	t.ok(ma.player.is_playing(),
		"★★ N50 核心：收尾之后播放器**仍在跑** ⇒ 下一次进入/收尾真的会混合")
	# ⚠️⚠️ **混合要时间，必须按墙钟等**：`_enter_idle()` 用的是
	#   `hold_rest(BLEND_BURST_OUT = 0.18 s)`，而 headless 里 `process_frame`
	#   之间的**真实 delta 极小**（引擎跑得飞快）⇒ `await` 几帧的累计时间
	#   远不够走完混合，读到的还是"动作末帧 → rest"的中途姿态
	#   （本段第二版就是这么红的：差 16.0°，那正是 `shoot` 末帧离 rest 的距离）。
	#   按墙钟等 400 ms，引擎的真实时间真的走过去了，混合才真的完成。
	var tw := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < 400:
		await host.get_tree().process_frame
	var d_ang2 := _max_angle(rest[0], _snap(skel)[0])
	t.lt(d_ang2, 1.0, "★★ 收尾（含 0.18 s 混合）之后姿态回到 rest（最大 %.4f°）" % d_ang2)

	# ---- 收拾干净（⛔ 别把污染留给下一段）----
	ma.reset_to_rest()
	await _pump(host, 2)
	inst.free()


# ============================================================ N56：巡航归位段

## ★★ N56（2026-09-29）：巡航待机需要一段**能锁住臂 / 腿 / 躯干**的段。
##
## ## 为什么非有不可
##
## 用户报：「柯西在巡航模式下按 WASD 就会举枪 ⇒ **不要举枪**，只有光束步枪射击时才举枪」。
## 根因两层：
##
##   ① 巡航与常态**共用**同一套方向动作族（`fly_*` / `turn_*`），而它们是**常态基准**
##      的姿态 ⇒ 一按 W 就把整条手臂从巡航位带到常态持枪位（`UpperArm.R` +89.53°）；
##   ② 松手回 `cruise_idle` **也放不下来** —— 它在引擎里只剩 19 条旋转轨
##      （导入器按 Remove Immutable Tracks 删掉了常量轨），
##      臂 / 腿 / 躯干**一根都没有** ⇒ 那些骨保持上一段动作的残留
##      （`AnimationPlayer` 的规则是「没有轨道的属性保持当前值」）。
##
## ⇒ 本段 = 一个**程序生成**的段，把「翼等巡航特征」照抄 `cruise_idle`、
##   把「臂 / 腿 / 躯干」用 `form_on` 的末帧值**恒定**锁住（与 `FormWeld` 的祖先基准同源）。
##
## ## 判据（★ 正判 + 证伪条，按 N47 T35 的规矩）
##
##   ① 前置：`cruise_idle` 里**确实没有**臂 / 腿 / 躯干的轨道（否则本段就不必存在）；
##   ② ★ **证伪条**：`prepare_clips()` **之前** `has_cruise_hold()` 必须为假；
##   ③ 正判：建出来后为真，且**不是动作**（`has()` / `action_names()` 都查不到）；
##   ④ 正判：**两源合成**逐通道成立（`cruise_idle` 有轨的 == `cruise_idle`；
##      没轨的 == `form_on` 末帧；两源都没有的 == 自己骨的 rest）；
##   ⑤ 正判：轨数 == **51 骨 × 3 通道**（漏一根骨就是「那根骨保持残留」）；
##   ⑥ ★ **证伪条**：把 `idle_cruise_action` 留空（其余五台机体走的就是这条路）
##      ⇒ 必须**建不出来** —— 证明它挂在「这个模型有巡航待机」上，⛔ 不是「所有机体都有」。
static func _cruise_hold(t: T, host: Node) -> void:
	var p := SuitProfile.xi()
	t.eq(p.model_anim_idle_cruise, "cruise_idle", "（前置）柯西登记了巡航待机动作名")
	t.eq(p.model_anim_form_on, "form_on", "（前置）柯西登记了 form_on")
	var ps := load(p.model_path) as PackedScene
	t.ok(ps != null, "柯西主模型可载入（%s）" % p.model_path.get_file())
	if ps == null:
		return
	var inst := ps.instantiate() as Node3D
	host.add_child(inst)
	await host.get_tree().process_frame
	var skel: Skeleton3D = null
	for c in inst.find_children("*", "Skeleton3D", true, false):
		skel = c as Skeleton3D
		break
	if skel == null:
		t.ok(false, "拿到柯西骨架（前置条件）")
		inst.free()
		return
	var ma := ModelAnimator.setup(inst, [FORM_ON, CRUISE_IDLE])
	t.ok(ma.ready, "动画器建立起来了（前置条件）")
	if not ma.ready:
		inst.free()
		return
	# ★ 复刻生产路径：`SuitProfile` 在 `setup()` 返回**之后**才把这两个名字赋进来
	#（`FlightBody._setup_model_anim()`），所以 `prepare_loops()` 与 `prepare_clips()`
	#  都必须在这之后 —— 时序陷阱见 `ModelAnimator.prepare_loops()` 的长说明。
	ma.idle_cruise_action = p.model_anim_idle_cruise
	ma.form_on_action = p.model_anim_form_on
	ma.prepare_loops()

	# ---- ① 前置：`cruise_idle` 里臂 / 腿 / 躯干**确实一根轨道都没有** ----
	var ci: Animation = ma.player.get_animation("cruise_idle")
	t.ok(ci != null, "（前置）`cruise_idle` 在播放器上")
	if ci == null:
		inst.free()
		return
	var base := ""
	if ci.get_track_count() > 0:
		base = str(ci.track_get_path(0)).get_slice(":", 0)
	t.ok(base != "", "（前置）从 `cruise_idle` 的轨道路径里取到了骨基路径（%s）" % base)
	var ci_chan := {}
	for i in ci.get_track_count():
		ci_chan[_chan_key(ci.track_get_path(i), ci.track_get_type(i))] = true
	var watch := ["UpperArm.R", "LowerArm.R", "Hand.R", "Thigh.L", "Shin.L", "Foot.L",
		"Chest", "Spine", "Hips"]
	var ci_hit := 0
	for bn in watch:
		if ci_chan.has(_chan_key(NodePath("%s:%s" % [base, bn]), Animation.TYPE_ROTATION_3D)):
			ci_hit += 1
	var movie := p.model_path.ends_with("xi_movie_rigged.scn")
	if movie:
		t.eq(ci_hit,watch.size(),"movie idle explicitly restores all watched joints")
		t.eq(ci.get_track_count(),skel.get_bone_count()*3,"movie idle retains complete constant channels")
	else:
		t.eq(ci_hit,0,"legacy sparse idle requires fallback channels")
		t.lt(ci.get_track_count(),skel.get_bone_count()*3,"legacy idle remains sparse")

	# ---- ② ★ 证伪条：建之前必须为假 ----
	t.not_ok(ma.has_cruise_hold(),
		"★ ② 证伪条：`prepare_clips()` **之前** has_cruise_hold() 为假（③ 才不是恒真断言）")

	# ---- ③ 建出来了，且**不污染动作表** ----
	ma.prepare_clips()
	t.ok(ma.has_cruise_hold(), "★ ③ 巡航归位段建出来了（has_cruise_hold() == true）")
	t.not_ok(ma.has(str(ModelAnimator.CRUISE_HOLD_CLIP)),
		"★ ③ 归位段**不是**动作（has() 查不到）")
	t.ok(not ma.action_names().has(str(ModelAnimator.CRUISE_HOLD_CLIP)),
		"★ ③ 也不在 action_names() 里（否则会顶红「动作总数」那批断言）")

	var hold: Animation = ma.player.get_animation(str(ModelAnimator.CRUISE_HOLD_CLIP))
	t.ok(hold != null, "（前置）归位段在播放器上")
	var fo: Animation = ma.player.get_animation("form_on")
	t.ok(fo != null, "（前置）`form_on` 在播放器上")
	if hold == null or fo == null:
		inst.free()
		return

	# ---- ⑤ 每一根骨、每一条通道都要有轨（漏一根 = 那根骨保持残留）----
	t.eq(hold.get_track_count(), skel.get_bone_count() * 3,
		"★ ⑤ 轨数 == 骨数 × 3（%d 骨 ⇒ 期望 %d，实测 %d）"
		% [skel.get_bone_count(), skel.get_bone_count() * 3, hold.get_track_count()])

	# ---- ④ 逐通道核对**两源合成** ----
	var n_pri := 0
	var n_fbk := 0
	var n_rest := 0
	var bad: Array = []
	for i in hold.get_track_count():
		var ty := hold.track_get_type(i)
		var path := hold.track_get_path(i)
		var bn := str(path).get_slice(":", 1)
		var got: Variant = hold.track_get_key_value(i, hold.track_get_key_count(i) - 1)
		var want: Variant = null
		var src := ""
		if ci_chan.has(_chan_key(path, ty)):
			var vi := _find_track(ci, path, ty)
			if vi >= 0 and ci.track_get_key_count(vi) > 0:
				want = ci.track_get_key_value(vi, 0)
				src = "cruise_idle"
				n_pri += 1
		if want == null:
			var fi := _find_track(fo, path, ty)
			if fi >= 0 and fo.track_get_key_count(fi) > 0:
				want = fo.track_get_key_value(fi, fo.track_get_key_count(fi) - 1)
				src = "form_on"
				n_fbk += 1
		if want == null:
			want = _rest_val(skel, bn, ty)
			src = "rest"
			n_rest += 1
		if want == null or not _same_val(got, want):
			bad.append("%s/%s(源=%s)" % [bn, _chan_name(ty), src])
	t.eq(bad.size(), 0,
		"★ ④ 逐通道两源合成全对（错 %d 条：%s）" % [bad.size(), str(bad).substr(0, 200)])
	t.eq(n_pri + n_fbk + n_rest, hold.get_track_count(),
		"★ ④ 每条通道都有明确的源（cruise_idle %d / form_on %d / rest 兜底 %d）"
		% [n_pri, n_fbk, n_rest])
	if movie:
		t.eq(n_fbk+n_rest,0,"complete movie idle requires no missing-channel fallback")
	else:
		t.gt(n_fbk+n_rest,0,"legacy sparse idle gains its missing channels")

	t.gt(n_pri, 0, "★ ④ 「照抄 cruise_idle 的」通道 > 0（%d 条）—— 巡航观感没被换掉" % n_pri)

	# ---- 收拾干净 ----
	inst.free()

	# ---- ⑥ ★ 证伪条：没有巡航待机的机体（其余五台走的就是这条路）----
	var inst2 := ps.instantiate() as Node3D
	host.add_child(inst2)
	await host.get_tree().process_frame
	var ma2 := ModelAnimator.setup(inst2, [FORM_ON, CRUISE_IDLE])
	ma2.prepare_clips()
	t.not_ok(ma2.has_cruise_hold(),
		"★ ⑥ 证伪条：`idle_cruise_action` 留空 ⇒ 建不出来（③ 不是恒真断言）")
	inst2.free()


# ============================================================ 工具（N56 归位段用）

## 通道标识（轨道路径 ＋ 类型）。与 `ModelAnimator._chan_key()` **故意**各自一份：
## 测试要能独立于被测量代码算出期望值（共用一份的话，改错了会两边一起错）。
static func _chan_key(path: NodePath, track_type: int) -> String:
	return "%s|%d" % [str(path), track_type]


static func _chan_name(track_type: int) -> String:
	match track_type:
		Animation.TYPE_ROTATION_3D:
			return "rot"
		Animation.TYPE_POSITION_3D:
			return "pos"
		Animation.TYPE_SCALE_3D:
			return "scl"
	return "?"


static func _find_track(an: Animation, path: NodePath, track_type: int) -> int:
	for i in an.get_track_count():
		if an.track_get_type(i) == track_type and an.track_get_path(i) == path:
			return i
	return -1


static func _rest_val(skel: Skeleton3D, bone: String, track_type: int) -> Variant:
	var i := skel.find_bone(bone)
	if i < 0:
		return null
	var rest := skel.get_bone_rest(i)
	match track_type:
		Animation.TYPE_ROTATION_3D:
			return rest.basis.get_rotation_quaternion()
		Animation.TYPE_POSITION_3D:
			return rest.origin
		Animation.TYPE_SCALE_3D:
			return rest.basis.get_scale()
	return null


## ★★ 判"是不是同一个值"**不能**用 `2·acos(|dot|)` 这个夹角公式（N56 实测踩到）。
##
## 它在**接近单位元处是病态的**：`acos(1−ε) ≈ √(2ε)`，把误差**开了平方根**。
## 而 `Animation` 的旋转轨是**按 float32 存的**，`get_bone_rest()` 是 float64
## ⇒ 值来回一趟带 ~6e-8 的模长缺陷，`dot` 报 `0.99999994`
## ⇒ 夹角算出来 **6.9e-4 rad = 0.0396°**，比"真的一样"该有的量级大**三到四个数量级**。
## 实测症状：4 条通道（`head` / `hand_L` / `hand_R` / `shield_L`，两源都没有、
## 都退回 rest）打印出来**逐位一样**，却被判成"错"。
##
## ⇒ 改成**逐分量**比，容差按 float32 定（1e-5 ≈ 0.066°，仍远小于任何两个真实源的差：
##   `UpperArm.R` 的"举枪"基准差是 89.53°）。
## 双覆盖：`q` 与 `−q` 是同一次旋转 ⇒ 先按 `dot` 的符号把 `b` 翻正再逐分量比。
static func _same_val(a: Variant, b: Variant) -> bool:
	if a is Quaternion:
		var qa := a as Quaternion
		var qb := b as Quaternion
		if qa.dot(qb) < 0.0:
			qb = -qb
		return (absf(qa.x - qb.x) < 1.0e-5 and absf(qa.y - qb.y) < 1.0e-5
			and absf(qa.z - qb.z) < 1.0e-5 and absf(qa.w - qb.w) < 1.0e-5)
	if a is Vector3:
		return (a as Vector3).distance_to(b as Vector3) < 1.0e-5
	return str(a) == str(b)
