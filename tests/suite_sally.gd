class_name SuiteSally
extends RefCounted
## 剧情模式的**出击循环**（DESIGN-2026-09-28 · 轮 C）。
##
## ⚠️ 按**主题**命名，不占轮次号 —— 见 `test_runner.gd` 注册表里的红字：
## 本仓库有并行会话，两边都按轮次占号时撞过一次，一个套件被同名文件**整个覆盖**
## 而 runner 照样绿。
##
## ## 这一轮落了什么（§3.2 的那条时间线）
## ```
## 战役图 → 🎬P 序章 → 简报 → 🎬B 任务前 → 标题卡 → 战斗 → 结算（军资 +N / 重来）→ 🎬D → 回战役图
## ```
## 缺的两块**故意**不在这一轮：目标系统/触发器（轮 D/E）、`mid` 槽的战斗中播片（轮 G）。
##
## ## 这一套钉的是什么
##   1. **片目表是纯数据**：`validate()` 的四条不变量逐条喂样本表验（不靠人肉看 `CLIPS`）；
##      真实表今天是**空的**，而那正是设计要求的状态（素材可选依赖 —— §7.5.5）。
##   2. **无头下不许播、也不许 await**：两条判据逐点验真值表。这条挂掉的症状是
##      "整个回归卡在出击那一步"，而且没有任何报错。
##   3. **结算页那两行文案**（军资 +N / 重来）是纯函数 ⇒ 可以逐字符钉；
##      其中"四种现有模式逐字符不变"是 §9.4 的硬约束。
##   4. **军资只加不减、重打只补差额**：`reward_for` / `reward_delta` / `credit_delta` 逐点验。
##   5. **版式纯函数**：战役图 9 行排得下、简报页目标清单**永不溢出容量**（逐关 × 逐分辨率）。
##   6. **接线**（源码扫描）：`CHALLENGE` 被拦到战役图、剧情模式的地图**不许有兜底**、
##      军资结算必须**早于** `capture_result()`、`mid` 槽一个调用点都没有。
##   7. **真流程 + 真落盘**（最后一节）：主场景 → 战役图 → 简报 → 分辨率/解锁判定；
##      军资结算走**注入的临时存档**，而玩家真实的 `user://campaign.cfg` **一个字节都不动**。

const MS := preload("res://scripts/data/mission_script.gd")
const CS := preload("res://scripts/data/campaign.gd")
const CUT := preload("res://scripts/data/cutscene_script.gd")
## 三页 UI。⚠️ 它们都是 `extends Control` 且**没有 `class_name`**（`main.gd` 里
## 也是按路径 preload 的，见那边的四个常量）⇒ 测试里只能这样取。
## （`FlightHUD` / `MainMenu` / `UILayout` / `SuiteUiStyle` 有 `class_name`，直接用。）
const CMAP := preload("res://scripts/ui/campaign_map.gd")
const BRIEF := preload("res://scripts/ui/mission_brief.gd")
const TITLE := preload("res://scripts/ui/mission_title.gd")

## 本套件自己的临时存档（**绝不碰** `user://campaign.cfg`）。
## §6.6 的第 1 条纪律：读写走注入路径 —— 套件跑一遍真流程就会写花玩家的进度，
## 而军资与解锁进度是"攒了半小时"的东西，污染一次是**实际损失**。
const TMP := "user://campaign_sally_tmp.cfg"

## 版式判据用到的四种分辨率。与 `SuiteLayout.VIEWS` 同源（1080p / 720p / 16:10 / 21:9 一档）。
const VIEWS: Array[Vector2] = [
	Vector2(1280, 720), Vector2(1600, 900), Vector2(1920, 1080), Vector2(1600, 1000),
]


# ============================================================ 工具

## 取某个顶层函数的**函数体**（从 `header` 那行到下一个顶层 `func`）。
## 与 `suite_intro` 里那份同一个做法（扫的是已剥注释的源码）。
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


## 从 `main` 的脚本常量表里按**名字**取 `Phase` 的值。
##
## ⚠️ 不能写 `main.Phase.CAMPAIGN`：`main.gd` **没有 `class_name`**（它是挂在场景根
## 节点上的 `extends Node3D`），测试里读不到它的枚举。`suite_round` 那套是同一个理由。
## 按名字取还有个好处：**加枚举成员不会让别的断言错位**（只要不改已有成员的名字）。
static func _main_phase(main: Node, name: String) -> int:
	var scr := main.get_script() as GDScript
	if scr == null:
		return -1
	var cmap: Dictionary = scr.get_script_constant_map()
	var phases = cmap.get("Phase")
	if phases is Dictionary:
		return int((phases as Dictionary).get(name, -1))
	return -1


## 造一份"通关到第 `n` 关"的进度（n=0 ⇒ 全新档）。
static func _progress_cleared(n: int) -> Dictionary:
	var p := CS.new_progress()
	for i in n:
		p["cleared_mask"] = int(p["cleared_mask"]) | (1 << i)
	return p


## 一片不存在的片（用来验"缺片 = 跳过，不是崩"）。
static func _ghost(id: String, slot: String, mission := "") -> CUT.Cutscene:
	return CUT.Cutscene.new(id, "res://assets/video/__不存在的片__.ogv", slot, mission, id)


static func run(t: T, host: Node) -> void:
	_cutscene_table(t)
	_gates(t)
	_sally_lines(t)
	_reward(t)
	_campaign_map(t)
	_brief(t)
	_title_card(t)
	_menu_entry(t)
	_wiring(t)
	await _real_flow(t, host)


# ============================================================ 1 片目表
static func _cutscene_table(t: T) -> void:
	t.suite("出击循环 / 片目表（纯数据 + 纯函数）")

	t.eq(CUT.SLOTS.size(), 4, "四个槽位（P/B/M/D）")
	t.eq(CUT.SLOTS, ["prologue", "brief", "mid", "debrief"], "槽位名与 §7.5.1 一致")
	t.eq(int(CUT.SLOT_MAX.get("mid", 0)), -1, "mid 槽不限支数（按 id 点名触发）")
	t.eq(int(CUT.SLOT_MAX.get("prologue", 0)), 1, "序章只有一支")
	t.eq(int(CUT.SLOT_MAX.get("brief", 0)), 1, "每关的任务前片只有一支")

	# ---- ★ 真实表今天**是空的**，而且这正是设计要求的状态 ----
	# 「代码必须能在'一支片都没有'的仓库里跑完整条战役」（§7.5.5）。
	t.eq(CUT.CLIPS.size(), 0, "★ 真实片目表是空的（原剧切片还没到）")
	t.eq(CUT.validate(CUT.CLIPS), "", "空表也是**合规**的（不是'表写错了'）")
	t.not_ok(CUT.has_any(CUT.CLIPS), "空表 ⇒ 素材门关闭 ⇒ P/B/D 三处一处都不起播")
	t.eq(CUT.count(CUT.CLIPS), 0, "count() 为空")
	t.eq(CUT.all(CUT.CLIPS).size(), 0, "all() 为空")

	# ---- 样本表：四条不变量逐条喂 ----
	var good: Array = [
		CUT.Cutscene.new("prologue_haozene", "res://assets/video/prologue_haozene.ogv",
			"prologue", "", "豪泽恩号劫机"),
		CUT.Cutscene.new("m04_brief", "res://assets/video/m04_brief.ogv",
			"brief", "M04", "Ξ 穿进导弹雨"),
		CUT.Cutscene.new("m04_mid_01", "res://assets/video/m04_mid_01.ogv",
			"mid", "M04", "加乌曼的座舱"),
		CUT.Cutscene.new("m04_mid_02", "res://assets/video/m04_mid_02.ogv",
			"mid", "M04", "第二支 mid"),
		CUT.Cutscene.new("m04_debrief", "res://assets/video/m04_debrief.ogv",
			"debrief", "M04", "返航"),
	]
	t.eq(CUT.validate(good), "", "一份合规的样本表通过自检")
	t.eq(CUT.count(good), 5, "样本表 5 支")
	t.eq(CUT.count_of("M04", good), 4, "M04 名下 4 支（不含序章）")
	t.eq(CUT.count_of("M01", good), 0, "M01 名下 0 支")
	t.eq(CUT.all_in_slot("M04", "mid", good).size(), 2, "mid 槽可以有 2 支")
	t.eq(CUT.all_in_slot("M04", "brief", good).size(), 1, "brief 槽 1 支")

	# ---- 按 id 取片（`Trigger` 的 `cutscene:<id>` 走这条） ----
	t.ok(CUT.by_id("m04_mid_01", good) != null, "按 id 取得到")
	t.eq(str(CUT.by_id("m04_mid_01", good).label), "加乌曼的座舱", "取到的是那一支")
	t.eq(CUT.by_id("m04_mid_09", good), null, "不认识的 id ⇒ null（**不崩**）")
	t.eq(CUT.by_id("", good), null, "空 id ⇒ null")
	t.eq(CUT.by_id("m04_mid_01", CUT.CLIPS), null,
		"★ 同样的 id 在**空表**里也取不到 ⇒ 缺片是正常路径")

	# ---- 按槽位取片（**序章专用**：它不属于任何一关，mission 是空串） ----
	t.ok(CUT.by_slot("", "prologue", good) != null, "序章走 mission=\"\" 那条全局槽")
	t.eq(str(CUT.by_slot("", "prologue", good).id), "prologue_haozene", "取到的就是序章那支")
	t.eq(CUT.by_slot("M01", "prologue", good), null, "M01 没有序章片")
	t.ok(CUT.by_slot("M04", "brief", good) != null, "M04 的任务前片取得到")
	# ⚠️ `by_slot` 是"一支"的取法：`mid` 有 2 支时它**不报错、也不说有几支**，
	# 只是把**第一支**递出来 —— 第二支就这么被漏掉了。
	# 这恰恰是 `_play_cutscene()` **不走** `by_slot` 的原因（那份清单由 `Mission` 给）。
	var mid0: CUT.Cutscene = CUT.by_slot("M04", "mid", good)
	t.ok(mid0 != null, "`mid` 有 2 支时 by_slot 照样取得到（它不会报错说'这里不该用它'）")
	t.eq(str(mid0.id), "m04_mid_01", "★ 递出来的是**第一支** ⇒ 第二支被静默漏掉")
	t.eq(CUT.all_in_slot("M04", "mid", good).size(), 2,
		"★ 要拿全 `mid` 只能用 all_in_slot()（或像 main 那样读 `Mission.slot()` 给的 id 清单）")

	# ---- 素材门：文件真的在才算 ----
	t.not_ok(CUT.has_any(good), "样本表的路径都是假的 ⇒ 素材门仍然是关闭的")
	var real: Array = [CUT.Cutscene.new("x", "res://assets/video/intro_op.ogv", "brief", "M04", "x")]
	t.ok(CUT.has_any(real), "路径真的存在 ⇒ 素材门打开")
	t.ok(bool(real[0].available()), "available() 认得出真文件")
	t.not_ok(bool(good[0].available()), "available() 认得出假文件")
	t.not_ok(bool(CUT.Cutscene.new("y", "", "brief", "M04", "y").available()),
		"空路径 ⇒ 不可用（不崩）")
	t.eq(str(good[2].slot_key()), "M04/mid", "slot_key() 是 关卡/槽位")
	t.eq(str(good[0].slot_key()), "-/prologue", "序章的 slot_key 用 - 占位")

	# ---- 四条不变量各自**必须变红**（这才是自检的意义） ----
	t.eq(CUT.validate([CUT.Cutscene.new("", "a", "brief", "M04", "")]), "有片目的 id 是空的",
		"① 空 id 被抓住")
	t.eq(CUT.validate([CUT.Cutscene.new("a", "a", "brief", "M04", ""),
		CUT.Cutscene.new("a", "b", "brief", "M05", "")]), "片目 id 重复：a",
		"① 重复 id 被抓住（`cutscene:<id>` 靠它点名，重复就没法点名了）")
	t.eq(CUT.validate([CUT.Cutscene.new("a", "a", "trailer", "M04", "")]),
		"片目 a 的 slot 非法：trailer", "② 非法槽位被抓住")
	t.eq(CUT.validate([CUT.Cutscene.new("a", "a", "prologue", "M04", "")]),
		"序章片 a 不该属于某一关（mission 应为空）", "③ 序章挂到某一关上被抓住")
	t.eq(CUT.validate([CUT.Cutscene.new("a", "a", "brief", "", "")]),
		"片目 a 是 brief 槽，必须写明属于哪一关", "④ 非序章槽没写关卡被抓住")
	t.eq(CUT.validate([CUT.Cutscene.new("a", "a", "brief", "M04", ""),
		CUT.Cutscene.new("b", "b", "brief", "M04", "")]),
		"槽位 M04/brief 超过上限（1 支）：b", "一槽一支被抓住")
	t.eq(CUT.validate([CUT.Cutscene.new("a", "a", "mid", "M04", ""),
		CUT.Cutscene.new("b", "b", "mid", "M04", ""),
		CUT.Cutscene.new("c", "c", "mid", "M04", "")]), "",
		"mid 槽**不限**支数（3 支也合规）")
	t.eq(CUT.validate([CUT.Cutscene.new("a", "a", "prologue", "", "")]), "",
		"序章必须 mission 为空 —— 这条反过来也是对的")
	# ⚠️ 不检查"文件在不在"：素材是可选依赖（缺片=跳过，不是表写错了）。
	t.eq(CUT.validate(good), "", "★ 四条不变量**都不管文件存不存在**（否则素材没到就写不了表）")


# ============================================================ 2 该不该播
static func _gates(t: T) -> void:
	t.suite("出击循环 / 该不该播（纯判据：无头必须同步跳过）")

	# 战役播片只有三条否决（**没有** `current_scene == self` 那条 —— 战役播片
	# 恰恰发生在主场景里，那条闸对它恒假，见 §7.5.3 规矩 3）。
	t.eq(CUT.SLOTS.size(), 4, "四个槽位各有一条判据要过")
	var headless := DisplayServer.get_name() == "headless"
	t.ok(headless, "本次就是在无头里跑的（下面那条'无头必须 false'才是有意义的）")

	for sup: bool in [false, true]:
		for has: bool in [false, true]:
			t.not_ok(IntroMovie.should_play_in_mission(true, sup, has),
				"headless=true, suppressed=%s, has_clip=%s ⇒ **必 false**（否则整条回归挂住）"
				% [sup, has])
	t.not_ok(IntroMovie.should_play_in_mission(false, true, true),
		"--skip-cutscenes ⇒ false")
	t.not_ok(IntroMovie.should_play_in_mission(false, false, false),
		"一支片都没有 ⇒ false")
	t.ok(IntroMovie.should_play_in_mission(false, false, true),
		"三条都不否决 ⇒ true（阳性对照：判据不是恒 false）")
	t.not_ok(IntroMovie.should_play_in_mission_now(),
		"★ `should_play_in_mission_now()` 在无头下必须是 false —— `main._play_cutscene()` 靠它")

	# 开场那条管线**一个字都不改**（`should_play()` 有**四条**否决，其中一条是
	# `current_scene == self` —— 战役那条故意没有它，见 §7.5.3 规矩 3）。
	var im_src := SuiteUiStyle._code("res://scripts/ui/intro_movie.gd")
	t.ok(im_src.contains("static func should_play_in_mission(headless: bool, suppressed: bool, has_clip: bool)"),
		"战役那条判据是**三个入参的纯函数**（逐点可验）")
	t.ok(im_src.contains("static func should_play(is_current_scene: bool, headless: bool, suppressed: bool,"),
		"开场那条仍是**四个入参**（两条管线各管各的）")
	t.not_ok(IntroMovie.should_play(true, true, false, true),
		"开场判据仍然否决无头（对照：这一条没被我的改动碰过）")
	t.ok(IntroMovie.should_play(true, false, false, true),
		"开场判据在四条都过时是 true（阳性对照：它不是恒 false）")
	t.not_ok(IntroMovie.should_play(false, false, false, true),
		"★ 开场多一条 `current_scene == self` 的闸 —— 战役那条**没有**它"
		+ "（战役播片恰恰发生在主场景里，那条闸对它恒假，所以必须另起一条判据）")

	# 标题卡自己的判据（两条否决：无头 / `--skip-cutscenes`）。
	t.not_ok(TITLE.should_play(true, false), "标题卡：无头 ⇒ false")
	t.not_ok(TITLE.should_play(false, true), "--skip-cutscenes ⇒ false")
	t.ok(TITLE.should_play(false, false), "非无头、没被抑制 ⇒ true")
	t.not_ok(TITLE.should_play_now(), "★ 无头下 `should_play_now()` 必须是 false")
	t.not_ok(TITLE.has_skip_flag(), "本次命令行里没有 --skip-cutscenes")


# ============================================================ 3 结算页两条文案
static func _sally_lines(t: T) -> void:
	t.suite("出击循环 / 结算页的两条文案（纯函数）")

	# ---- ⚠️ 最重要的一条：四种现有模式的文案**逐字符不变**（§9.4 的硬约束）----
	t.eq(FlightHUD.sally_text({}), "", "★ 非剧情模式 ⇒ 军资那行返回空串（不画）")
	t.eq(FlightHUD.result_hint({}), "Enter / Esc  回主菜单",
		"★ 非剧情模式的提示行与改造前**逐字符相同**（README 里撤掉'再战一局'那条仍然成立）")
	t.not_ok(FlightHUD.result_hint({}).contains("重来"),
		"★ 现有模式**不出现**'重来'（那是剧情模式失败时的另一条路）")

	# ---- 军资那行 ----
	t.eq(FlightHUD.sally_text({"reward": 280, "delta": 280, "win": true, "next": ""}),
		"军资 +280", "首通：直接是本局的军资")
	t.eq(FlightHUD.sally_text({"reward": 280, "delta": 280, "win": true, "next": "M02"}),
		"军资 +280　·　解锁 M02", "首通 + 解锁下一关（§6.3 的'解锁项'）")
	t.eq(FlightHUD.sally_text({"reward": 400, "delta": 120, "win": true, "next": ""}),
		"军资 +120（最好 400）", "重打且拿到更好成绩 ⇒ 显示到账 + 本关最好")
	t.eq(FlightHUD.sally_text({"reward": 400, "delta": 0, "win": true, "next": ""}),
		"军资 +0（最好 400）", "重打没超过 ⇒ 到账 0，但要说清'最好 400'（否则玩家以为丢了钱）")
	t.eq(FlightHUD.sally_text({"reward": 400, "delta": 400, "win": true, "next": ""}),
		"军资 +400", "delta 与 reward 相等时**不**重复写那个数（白占宽度）")
	t.eq(FlightHUD.sally_text({"reward": 150, "delta": 0, "win": false, "next": ""}),
		"军资 +0　·　未达成", "失败：到账 0，并说明为什么")
	t.eq(FlightHUD.sally_text({"reward": -5, "delta": -5, "win": true}),
		"军资 +0", "★ 喂负数也是 +0（'只加不减'不由调用方自觉）")
	t.eq(FlightHUD.sally_text({"win": false}),
		"军资 +0　·　未达成", "字典缺字段 ⇒ 走默认（不崩）")

	# ---- 提示行 ----
	t.eq(FlightHUD.result_hint({"win": true}, "回战役图"), "Enter / Esc  回战役图",
		"剧情模式通关 ⇒ 回**战役图**（不是回主菜单）")
	t.eq(FlightHUD.result_hint({"win": false}, "回战役图"),
		"R 重来   ·   Enter / Esc  回战役图", "★ 剧情模式失败 ⇒ 多一个 R 重来（§6.7）")
	t.ok(FlightHUD.result_hint({"win": false}, "回战役图").find("R 重来")
			< FlightHUD.result_hint({"win": false}, "回战役图").find("Enter"),
		"重来那一项排在回战役图**前面**（它是失败时的首选动作）")
	t.eq(FlightHUD.result_hint({}, "回战役图"), "Enter / Esc  回战役图",
		"非剧情模式传了别的 back_label 也照用（文案由调用方给）")

	# ---- 快照：`capture_result()` 必须把 `Game.sally_result` 抄进 `_result` ----
	var hud_src := SuiteUiStyle._code("res://scripts/ui/hud.gd")
	t.ok(hud_src.contains("_result[\"sally\"] = Game.sally_result.duplicate()"),
		"★ 结算页读的是**快照**（`capture_result` 那一刻抄下来的 `Game.sally_result`）")
	t.ok(hud_src.contains("var sally: Dictionary = _result.get(\"sally\", {})"),
		"绘制时只认快照里那一份（不回头读 Game）")
	t.ok(hud_src.contains("result_hint(sally, back_label)"),
		"提示行的文案真的来自那个纯函数（不是另写一份）")
	t.ok(hud_src.contains("sally_text(sally)"), "军资那行同理")


# ============================================================ 4 军资公式与差额
static func _reward(t: T) -> void:
	t.suite("出击循环 / 军资公式与差额（§6.3 三条硬约束）")

	# ⚠️ 本节的侧重**不是**把 `suite_campaign` 那 505 条抄一遍，而是钉住
	# "结算页上那两个数从哪来" —— 所以每个算例都写成"喂进去 ⇒ 出来多少军资"。
	t.eq(CS.KILL_CREDITS, 30, "逐机 30")
	t.eq(CS.NAMED_KILL_CREDITS, 120, "命名王牌 120（轮 F 才有人给这个数）")
	t.eq(int(CS.GRADE_BONUS["S"]), 400, "S 加 400")
	t.eq(int(CS.GRADE_BONUS["D"]), 40, "D 加 40")

	# ★ 只加不减：这张表里**一个负号都没有**。
	for k: String in CS.GRADE_BONUS.keys():
		t.gt(float(CS.GRADE_BONUS[k]), 0.0, "评价加成 %s 是正的（'只加不减'）" % k)

	var base := 260   # = M01 的 `base_reward`
	t.eq(CS.reward_for({"base": base, "grade": "S", "kills": 0, "named_kills": 0}), 660,
		"260 基础 + 400（S）+ 0 击坠 = 660")
	t.eq(CS.reward_for({"base": base, "grade": "D", "kills": 3, "named_kills": 0}), 390,
		"260 + 40（D）+ 3×30 = 390")
	t.eq(CS.reward_for({"base": base, "grade": MissionRating.NO_GRADE, "kills": 2,
		"named_kills": 0}), 320, "★ 失败（NO_GRADE）不给评价加成，但**击坠依然算数**")
	t.eq(CS.reward_for({"base": base, "grade": "S", "kills": 2, "named_kills": 1}), 840,
		"命名王牌那一台给 120、普通机 30 ⇒ 260 + 400 + 30 + 120 = 840")
	t.eq(CS.reward_for({"base": base, "grade": "A", "kills": 1, "named_kills": 5}), 690,
		"★ named_kills 被夹到 ≤ kills（260 + 280 + 1×30 + 1×120 = 690，不是 570）")
	t.eq(CS.reward_for({"base": -100, "grade": "S", "kills": -3, "named_kills": -1}), 400,
		"★ 喂负数 ⇒ base/kills 各自夹到 0，结果仍非负")
	t.eq(CS.reward_for({}), 0, "★ 空字典 ⇒ 0（不崩）")
	t.eq(CS.reward_for({"base": 260, "grade": "Z", "kills": 0}), 260,
		"不认识的字面评价 ⇒ 不加成（也不崩）")

	# ---- 差额（重打只补差额）----
	t.eq(CS.reward_delta(87, 92), 5, "§6.3 的原文算例：更好 ⇒ 补 5")
	t.eq(CS.reward_delta(92, 87), 0, "§6.3 的原文算例：更差 ⇒ 0")
	t.eq(CS.reward_delta(100, 100), 0, "一样 ⇒ 0")
	t.eq(CS.reward_delta(0, 0), 0, "都是 0 ⇒ 0")
	t.eq(CS.credit_delta(false, 0, 260), 260, "★ 首通拿**全额**（不能把'没打过'当成 best=0 去走差额）")
	t.eq(CS.credit_delta(true, 400, 260), 0, "★ 重打拿少了 ⇒ 0（不扣钱）")
	t.eq(CS.credit_delta(true, 260, 400), 140, "★ 重打拿多了 ⇒ 只补差额")
	t.eq(CS.credit_delta(true, 260, 260), 0, "重打一样 ⇒ 0")

	# ---- settle 的组合语义（结算页那两个数就从它来）----
	var fresh := CS.new_progress()
	var r1 := CS.settle(fresh, "M01", {"win": true, "grade": "A", "score": 80.0,
		"kills": 3, "base": base})
	t.eq(int(r1["reward"]), 630, "首通的 reward = 260 + 280 + 90")
	t.eq(int(r1["delta"]), 630, "首通的 delta = 全额")
	t.eq(int(r1["progress"]["credits"]), 630, "钱包进账 = delta")
	t.ok(CS.is_cleared(r1["progress"], "M01"), "首通点亮位掩码")
	t.eq(int(fresh["credits"]), 0, "★ `settle()` **不改传进去的那一份**（纯函数）")

	var r2 := CS.settle(r1["progress"], "M01", {"win": true, "grade": "S", "score": 92.0,
		"kills": 3, "base": base})
	t.eq(int(r2["reward"]), 750, "重打拿到 S ⇒ 本局值 750")
	t.eq(int(r2["delta"]), 120, "★ 只补差额 120")
	t.eq(int(r2["progress"]["credits"]), 750, "钱包 = 630 + 120")

	var r3 := CS.settle(r2["progress"], "M01", {"win": true, "grade": "D", "score": 20.0,
		"kills": 0, "base": base})
	t.eq(int(r3["delta"]), 0, "★ 打得更差 ⇒ 0（不扣钱、也不把最好成绩改坏）")
	t.eq(int(r3["progress"]["credits"]), 750, "钱包不动")
	t.eq(str(r3["progress"]["best_grade"]["M01"]), "S", "★ 最好评价仍然是 S（失败/退步不留成绩）")

	var r4 := CS.settle(r3["progress"], "M01", {"win": false, "grade": MissionRating.NO_GRADE,
		"score": 0.0, "kills": 2, "base": base})
	t.eq(int(r4["delta"]), 0, "★ 失败 ⇒ 一分钱不进")
	t.eq(int(r4["reward"]), 320, "但'本局值多少'照算（击坠算数，§4.4 的必败战要用）")

	# ---- 解锁：M01 通了 ⇒ M02 能打；M04→M05 跨章不需要额外条件 ----
	var p1 := _progress_cleared(1)
	t.ok(CS.is_unlocked(p1, "M02"), "M01 通了 ⇒ M02 可打")
	t.not_ok(CS.is_unlocked(p1, "M03"), "★ 跳关被拒（M02 没通 ⇒ M03 锁着，传递闭包天然挡住）")
	t.ok(CS.is_unlocked(CS.new_progress(), "M01"), "第一关永远开着")
	t.not_ok(CS.is_unlocked(CS.new_progress(), "M02"), "空档时 M02 锁着")
	var p4 := _progress_cleared(4)
	t.ok(CS.is_unlocked(p4, "M05"), "★ M04 → M05 跨章**不需要额外条件**（它在 MASK_ORDER 里本就相邻）")
	t.eq(CS.current_id(p4), "M05", "打完 M04 ⇒ 当前关是 M05")
	t.eq(CS.current_id(_progress_cleared(7)), "", "全通 ⇒ 没有'当前关'")
	t.eq(CS.next_id("M04"), "M05", "M04 的下一关是 M05")
	t.eq(CS.next_id("M07"), "", "最后一关没有下一关")
	t.eq(CS.cleared_count(p4), 4, "cleared_count 数得对")


# ============================================================ 5 战役图
static func _campaign_map(t: T) -> void:
	t.suite("出击循环 / 战役图（纯函数）")

	# ---- 行结构：章节标题行 + 任务行 ----
	var rs: Array = CMAP.rows()
	t.eq(MS.all().size(), 7, "七关")
	t.eq(rs.size(), 9, "★ 9 行 = 2 个章节标题 + 7 关（标题行也占一行，滚动窗口要按**行**算）")
	t.eq(str(rs[0].get("kind", "")), "head", "第 0 行是章节标题")
	t.eq(str(rs[0].get("text", "")), CS.chapter_title(1), "标题就是第一章那一串")
	t.eq(str(rs[1].get("id", "")), "M01", "第 1 行是 M01（`row_index_of` 与任务序号**不相等**）")
	t.eq(CMAP.row_index_of("M01"), 1, "M01 在 rows 里的下标是 1")
	t.eq(CMAP.row_index_of("M05"), 6, "M05 在 rows 里的下标是 6（第二章标题之后）")
	t.eq(CMAP.row_index_of("M99"), 0, "不认识的 id 退回 0（不崩）")
	var heads := 0
	for r: Dictionary in rs:
		if str(r.get("kind", "")) == "head":
			heads += 1
	t.eq(heads, 2, "两个章节标题（第三章不做）")

	# ---- 四态 ----
	var fresh := CS.new_progress()
	t.eq(CMAP.state_of(fresh, "M01"), CMAP.State.CURRENT,
		"空档 ⇒ M01 是'当前该打的那一关'")
	t.eq(CMAP.state_of(fresh, "M02"), CMAP.State.LOCKED, "空档 ⇒ M02 锁着")
	var p1 := _progress_cleared(1)
	t.eq(CMAP.state_of(p1, "M01"), CMAP.State.CLEARED, "通了 ⇒ 已通关")
	t.eq(CMAP.state_of(p1, "M02"), CMAP.State.CURRENT, "下一个没通的就是当前")
	t.eq(CMAP.state_of(p1, "M03"), CMAP.State.LOCKED, "M03 还锁着")
	# ⚠️ 顺序解锁下 `OPEN` 其实是**不可达**的（未通关的第一个必然 == current）。
	# 只有**手工改过的档**（位掩码有空档）才会出现"可出击但不是当前"。
	var gap := CS.new_progress()
	gap["cleared_mask"] = (1 << 0) | (1 << 2)   # 通了 M01 与 M03，没通 M02
	t.eq(CS.current_id(gap), "M02", "有空档时'当前关'是第一个没通的")
	t.eq(CMAP.state_of(gap, "M03"), CMAP.State.CLEARED, "M03 算已通关")
	t.eq(CMAP.state_of(gap, "M04"), CMAP.State.OPEN,
		"★ 手工档里 M04 是 OPEN（前置 M03 通了）—— 这是四态里唯一难触发的那一态")

	# ---- 状态标签：**锁着的关也要给出理由** ----
	t.eq(CMAP.state_label(fresh, "M01"), "◀ 当前", "当前关的标签")
	t.eq(CMAP.state_label(fresh, "M02"), "需通关上一关",
		"★ 锁着时给的是**理由**，不是一个孤零零的锁")
	t.eq(CMAP.state_label(p1, "M01"), "已通关", "没成绩时只说'已通关'")
	var pg := _progress_cleared(1)
	pg["best_grade"] = {"M01": "A"}
	t.eq(CMAP.state_label(pg, "M01"), "已通关 A", "有成绩时带上字母")
	t.eq(CMAP.state_label(gap, "M04"), "可出击", "OPEN 的标签")
	pg["best_grade"] = {"M01": "-"}
	t.eq(CMAP.state_label(pg, "M01"), "已通关", "成绩是空串/'-' 时不写字母")

	# ---- 任务行文案 ----
	var m01: MS.Mission = MS.by_id("M01")
	t.eq(CMAP.line_of("M01"), "M01   夜袭达沃", "行文案 = id + 标题")
	t.ok(CMAP.line_of("M99").contains("数据缺失"),
		"★ 表里没有这一关 ⇒ 用 id 兜底（返回空串会让这一行**看不见**，更难查）")
	t.ok(CMAP.line_of("M99").contains("M99"), "兜底文案里带着那个 id")

	# ---- 容量：今天**一次滚动都不该出现** ----
	t.eq(CMAP.rows().size(), 9, "行数")
	for v: Vector2 in VIEWS:
		var n := CMAP.max_rows(v)
		t.gt(float(n), 0.0, "%s：列表至少排得下一行" % v)
		t.gt(float(n), 9.0, "★ %s：9 行全排得下 ⇒ 窗口恒等于整份名单（零滚动）" % v)
		var win := MainMenu.scroll_window(rs.size(), 5, n)
		t.eq(win, Vector2i(0, rs.size()),
			"★ %s：`count <= n` ⇒ 窗口 = 整份名单（复用既有滚动语义，不新写一套）" % v)
		# 版式：列表区在脚注之上、脚注在屏内
		var l: Dictionary = CMAP.layout(v)
		t.lt((l["list"] as Rect2).end.y, (l["foot"] as Rect2).position.y,
			"%s：列表区在脚注之上（不重叠）" % v)
		t.lt((l["foot"] as Rect2).end.y, v.y, "%s：脚注在屏幕内" % v)
		t.gt((l["list"] as Rect2).size.y, 0.0, "%s：列表区高度为正" % v)

	# ---- 光标钳制（`cursor == n` 就是"返回行"）----
	var n := CS.mission_ids().size()
	t.eq(n, 7, "七个任务行")
	t.eq(n, MS.all().size(), "任务行数 = 关数")
	t.eq(CMAP.OPT_BACK, "< 返回>", "最后一档是'返回'那一行")


# ============================================================ 6 简报页
static func _brief(t: T) -> void:
	t.suite("出击循环 / 简报页（纯函数）")

	var m01: MS.Mission = MS.by_id("M01")
	var m05: MS.Mission = MS.by_id("M05")
	t.ok(m01 != null and m05 != null, "取到 M01 / M05")

	# ---- 标题与章节 ----
	t.eq(BRIEF.title_line(m01), "MISSION 01 · 夜袭达沃", "标题行 = 编号 + 任务名")
	t.eq(BRIEF.title_line(m05), "MISSION 01 · 出击奥恩贝利",
		"★ 编号取 `Mission.index`（**章内序号**），不是数组下标 —— M05 是第二章的 01")
	# ⚠️ 章节行要**同时**带 `label` 与 `title`：`label`（"第一章"）让玩家知道"走到哪了"，
	# `title`（"正当的预言之王"）才是这一章的名字。只取 `title` 会让玩家看不到"第几章"
	# （`CampaignScript.chapter_title()` 返回的正是 `title` —— 它给战役图的标题行用，不是这一行）。
	t.eq(BRIEF.chapter_line(m01), "第一章 · 正当的预言之王 · 第 1 关", "章节行 = 章 · 章名 · 关")
	t.eq(BRIEF.chapter_line(m05), "第二章 · 喀耳刻的魔女 · 第 1 关", "M05 属于第二章")
	t.eq(BRIEF.chapter_name(1), "%s · %s" % [CS.CHAPTERS[0]["label"], CS.CHAPTERS[0]["title"]],
		"★ 章名那两个字都来自 `CHAPTERS`（UI 里不另抄一份）")
	t.eq(BRIEF.chapter_name(3), "", "第三章不做 ⇒ 查不到就是空串（不崩）")
	t.eq(BRIEF.title_line(null), "", "空任务 ⇒ 空串（不崩）")
	t.eq(BRIEF.chapter_line(null), "", "同上")

	# ---- 时段键 → 中文（**真源只有一处**：标题卡也借它） ----
	t.eq(BRIEF.time_label("night"), "夜", "夜")
	t.eq(BRIEF.time_label("dusk_overcast"), "阴天黄昏", "阴天黄昏")
	t.eq(BRIEF.time_label("space"), "轨道（无昼夜）", "轨道")
	t.eq(BRIEF.time_label(""), "按地图默认", "空串 = 用地图自带的（`Mission.time_key` 的语义）")
	t.eq(BRIEF.time_label("不认识"), "按地图默认", "不认识 ⇒ 按地图默认（不崩）")

	# ---- 敌情：全部取自 Mission 已有字段 ----
	#
	# ★ 轮 50：M01「夜袭达沃」现在**一架敌机都没有** ⇒ 敌情行只剩两行。
	# 这里**分两条路**验：有敌人的关（M05）走三行版、没有敌人的关（M01）走两行版。
	var el6: Array = BRIEF.enemy_lines(m05)
	t.eq(el6.size(), 3, "有敌人的关：敌情三行")
	t.ok(str(el6[0]).begins_with("敌方："), "第一行是敌机")
	t.ok(str(el6[0]).contains(SuitProfile.by_id(m05.enemy_suit).display_name),
		"敌机名取自 `enemy_suit_name()`")
	t.ok(str(el6[1]).contains("波次"), "第二行是波次/总台数")
	t.eq(str(el6[2]), "自机：%s" % m05.player_suit_name(),
		"非 POV 关 ⇒ 第三行写'自机'")
	t.eq(BRIEF.enemy_lines(null).size(), 0, "空任务 ⇒ 空数组")

	# ★ 轮 50：**没有敌人**的关（M01）—— 两行，且第一行如实写"无"。
	var el1: Array = BRIEF.enemy_lines(m01)
	t.eq(el1.size(), 2, "★ 没有敌人的关：敌情两行（波次那行一并撤掉）")
	t.eq(str(el1[0]), "敌方：无 —— 本次是纯突袭",
		"★ 第一行如实说'没有敌人'（不是空着、也不是报'0 台'让人以为加载失败）")
	t.eq(str(el1[1]), "视角：%s" % m01.player_suit_name(),
		"★ M01 是 POV 关 ⇒ 最后一行写'视角'（玩家开的是别人）")
	t.not_ok(str(el1[0]).contains(SuitProfile.by_id(m01.enemy_suit).display_name),
		"★ **不显示** M01 的 `enemy_suit` —— 那个字段留着是给'两个座舱'断言当数据用的")

	# ---- 地图 ----
	var ml: Array = BRIEF.map_lines(m01)
	t.eq(ml.size(), 2, "地图两行")
	t.eq(str(ml[0]), m01.map_name(), "第一行是图名")
	t.eq(str(ml[1]), "%s · %s" % [m01.arena, BRIEF.time_label(m01.time_key)],
		"第二行是场地键 · 时段")
	t.eq(BRIEF.map_lines(null).size(), 0, "空任务 ⇒ 空数组")

	# ---- ★ 目标清单：主在前、次在后，而且**永不溢出容量** ----
	#
	# ⚠️ **样本改成现构造的**（原来拿 M01 的 3 条目标当样本）：
	# 轮 50 把 M01 改成“只留一条目标”的纯突袭关 ⇒ 拿真关卡数据当样本
	# 只会让这一节**改一次关卡就崩**。这里验的本来就是
	# `objective_lines()` 的**分桶与截断**（纯函数），与哪一关无关。
	var sample: MS.Mission = MS.Mission.new("MX1", "样本（构造）")
	sample.objectives = [
		MS.Objective.destroy_all(1, "主要甲"),
		MS.Objective.salvage("z", 1, "次要乙", false),
		MS.Objective.reach("z", "次要丙", false),
	]
	var ol: Array = BRIEF.objective_lines(sample, Vector2(1600, 900))
	t.eq(ol.size(), 3, "样本三条目标（1 主 + 2 次）")
	t.ok(str(ol[0]).begins_with("[主]"), "主要目标排在第一位")
	t.ok(str(ol[1]).begins_with("[次]"), "次要目标跟在后")
	t.ok(str(ol[2]).begins_with("[次]"), "两条次要都在主之后")
	t.eq(str(ol[0]), "[主] %s" % str(sample.objectives[0].label),
		"★ 文案直接取 `Objective.label`（与 HUD 目标栏**同源**，不会各说各的）")
	t.eq(BRIEF.objective_lines(null, Vector2(1600, 900)).size(), 0, "空任务 ⇒ 空数组")
	# 主次**不靠排序稳定**去猜：把一条次要目标塞到数组**最前面**，它仍必须排在主要目标之后。
	# ⚠️ 原来这里只有一句注释加一条“样本前提”断言，**样本根本没被构造出来**
	#（`swapped` 就是 M01 自己）⇒ 那句承诺一直是空的。这次真的把它构造出来。
	var swapped: MS.Mission = MS.Mission.new("MX2", "样本（倒序）")
	swapped.objectives = [
		MS.Objective.reach("z", "次要丙", false),
		MS.Objective.destroy_all(1, "主要甲"),
	]
	t.ok(not bool(swapped.objectives[0].required),
		"样本前提：这一条数组里**次要的在前**（与 `sample` 相反）")
	var sw: Array = BRIEF.objective_lines(swapped, Vector2(1600, 900))
	t.eq(str(sw[0]), "[主] 主要甲",
		"★ 次要目标排在数组前面也没用 —— 分桶看的是 `required`，不是数组顺序")
	t.eq(str(sw[1]), "[次] 次要丙", "次要的仍然在后")

	# 逐关 × 逐分辨率：清单行数 ≤ 容量（这就是"超长不溢出"的可断言形式）
	for v: Vector2 in VIEWS:
		var cap := BRIEF.max_rows(v)
		t.gt(float(cap), 0.0, "%s：目标区至少排得下一行" % v)
		for mm: MS.Mission in MS.all():
			var lines: Array = BRIEF.objective_lines(mm, v)
			t.ok(lines.size() <= cap,
				"★ %s · %s：目标清单 %d 条 ≤ 容量 %d（超长会被截断并补'…还有 N 条'）"
				% [v, mm.id, lines.size(), cap])

	# ---- 截断路径本身 ----
	# ⚠️ `1280×400` **不够矮**：那一档的容量正好是 3，三条目标一条都不会掉，
	# 于是"补一行 `…还有 N 条`"永远不出现 —— 拿它当截断样本会得到一条**永远绿的假判据**
	#（本套件首跑就是这么红的：报"没补那行"，其实是不该补）。
	# ⇒ 从 400 往下逐档找"容量 < 3"的那一档，用它的**实测容量**当期望。
	# ★ 轮 50：样本同上一节，**现构造**（不再拿 M01 的真数据）。
	var fake: MS.Mission = MS.Mission.new("MX3", "样本（截断）")
	fake.objectives = [
		MS.Objective.destroy_all(1, "甲"),
		MS.Objective.salvage("z", 1, "乙", false),
		MS.Objective.reach("z", "丙", false),
	]
	var tight_view := Vector2(1280, 400)
	for hh in range(400, 159, -20):
		if BRIEF.max_rows(Vector2(1280, hh)) < 3:
			tight_view = Vector2(1280, hh)
			break
	var tight := BRIEF.max_rows(tight_view)
	t.gt(float(tight), 0.0, "★ %s：再矮也至少留 1 行（0 行等于整页什么都看不到）" % tight_view)
	t.lt(float(tight), 3.0, "★ %s：这一档确实装不下 3 条目标 ⇒ 截断真的被走到了" % tight_view)
	var tl: Array = BRIEF.objective_lines(fake, tight_view)
	t.ok(tl.size() <= tight, "★ 截断后行数 ≤ 容量（'永不溢出'的可断言形式）")
	t.ok(str(tl[tl.size() - 1]).begins_with("…还有"),
		"★ 被截断时**补一行**'…还有 N 条'（玩家知道清单没完）")
	t.eq(str(tl[tl.size() - 1]), "…还有 %d 条" % (3 - (tl.size() - 1)),
		"补的那行报的是**没排下的条数**（3 条 − 留下的 %d 条）" % (tl.size() - 1))

	# ---- 版式：各块互不重叠、都在屏内 ----
	for v: Vector2 in VIEWS:
		var l: Dictionary = BRIEF.layout(v)
		var frame: Rect2 = l["frame"]
		var title: Rect2 = l["title"]
		var left: Rect2 = l["left"]
		var right: Rect2 = l["right"]
		var foot: Rect2 = l["foot"]
		t.near(frame.position.x, UILayout.MARGIN, 0.001, "%s：外框左 = MARGIN" % v)
		t.near(frame.size.x, UILayout.frame_width(v), 0.001, "%s：外框宽 = frame_width" % v)
		t.near(title.position.y, UILayout.MARGIN + UILayout.PAD, 0.001,
			"%s：标题条贴内容区顶" % v)
		t.gt(left.position.y, title.end.y, "%s：正文在标题条之下" % v)
		t.gt(right.position.x, left.end.x, "%s：左右两栏不重叠" % v)
		t.near(right.end.x, UILayout.content_right(v), 0.001,
			"%s：右栏右端 = 内容区右边界（与主菜单/结算同一套网格）" % v)
		t.lt(left.end.y, foot.position.y, "%s：正文在脚注之上" % v)
		t.lt(foot.end.y, v.y, "%s：脚注在屏幕内" % v)
		# 左栏内两块（战场 / 敌情）不许反过来
		var sp := BRIEF.left_split(v)
		t.gt(sp, left.position.y, "%s：左栏分界在栏顶之下" % v)
		t.lt(sp, left.end.y, "%s：左栏分界在栏底之上" % v)
		# 目标区在右栏之内
		var ob := BRIEF.objective_box(v)
		t.gt(ob.position.y, right.position.y, "%s：目标区在右栏标题之下" % v)
		t.ok(ob.end.y <= right.end.y + 0.001, "%s：目标区不越出右栏" % v)
		# ★ 电台预告：**它有自己的带**，而且这条带在正文之下、脚注之上、外框之内。
		# 这一组断言就是这一块原来的病根的反面 —— 原写法靠一个"正文底下还有没有空地"
		# 的现场条件，而那个条件**在所有分辨率下恒假** ⇒ `Mission.story` 一次都没画出来过。
		var sb: Rect2 = l["story"]
		t.eq(sb, BRIEF.story_box(v),
			"%s：`story_box()` 与 `layout()[\"story\"]` 是同一个矩形（只有一份版式）" % v)
		t.gt(sb.size.y, 0.0, "%s：电台预告的带高度为正（不是 0 —— 0 就是「白留了一块」）" % v)
		t.ok(sb.position.y >= left.end.y, "%s：它在正文之下（左栏）" % v)
		t.ok(sb.position.y >= right.end.y, "%s：它在正文之下（右栏）" % v)
		t.lt(sb.end.y, foot.position.y, "%s：它在脚注之上" % v)
		t.lt(sb.end.y, frame.end.y, "%s：它在外框之内" % v)
		t.near(sb.position.x, left.position.x, 0.001, "%s：它的左端 = 内容区左边界" % v)
		t.near(sb.size.x, left.size.x + UILayout.PAD + right.size.x, 0.001,
			"%s：它横跨左右两栏（同一套网格）" % v)

	# ---- ★ 电台预告的内容：7 关**每一关**都有话要说，而且都会被画 ----
	for mm: MS.Mission in MS.all():
		var rows := BRIEF.story_lines(mm)
		t.eq(rows.size(), 1,
			"★ %s：电台预告是 1 行（不是 0 —— 0 行等于这一块白留了）" % mm.id)
		t.eq(str(rows[0]), MS.plain(mm.story), "%s：画的就是 `Mission.story`" % mm.id)
		t.not_ok(str(rows[0]).contains("**"), "★ %s：电台预告里不许出现 `**`" % mm.id)
	t.eq(BRIEF.story_lines(null).size(), 0, "空任务 ⇒ 0 行（不崩）")

	# ---- ★ 数据里的 `**强调**` 标记：**渲染期去掉**（不是改数据）----
	# 设计稿是 Markdown，`Objective.label` / `Mission.story` 是按它的口气写的
	# ⇒ 「**不得击毙**」这种标记**原样落在了字符串里**，`draw_string()` 又不认标记，
	# 于是屏幕上会印出星号（轮 C 出图时看到的正是 `[主] 让金伯利无力化（**不得击毙**）`）。
	t.eq(MS.plain("让金伯利无力化（**不得击毙**）"), "让金伯利无力化（不得击毙）",
		"★ `**` 被去掉")
	t.eq(MS.plain(""), "", "空串 ⇒ 空串（不崩）")
	t.eq(MS.plain("没有标记的一句话"), "没有标记的一句话",
		"★ 没有标记时**逐字符不变**（幂等：不能顺手把别的字符也吃了）")
	t.eq(MS.plain("**a**b**c**"), "abc", "多段标记一起去掉")
	# 7 关 × 逐条目标：**画出来的那一份**里一个星号都不许有。
	var obj_rows := 0
	for mm: MS.Mission in MS.all():
		for ln2: String in BRIEF.objective_lines(mm, Vector2(1600, 900)):
			obj_rows += 1
			t.not_ok(ln2.contains("**"), "★ %s：目标行里不许出现 `**` —— %s" % [mm.id, ln2])
	t.gt(float(obj_rows), 0.0, "确实逐条走过了（不是空转）")

	# ---- 读数口 ----
	var b := BRIEF.new()
	t.eq(b.shown_lines().get("title", ""), "", "没装任务时读数口返回空（不崩）")
	t.eq(b.story_text(), "", "同上")
	b.open(m01)
	t.eq(str(b.shown_lines()["title"]), BRIEF.title_line(m01), "装上任务后读数口对上了")
	t.eq(str(b.shown_lines()["story"]), m01.story, "电台预告就是 `Mission.story`")
	t.eq(b.option_text(), ["出击", "返回"], "两个选项：出击 / 返回")
	t.eq(int(b.get("cursor")), 0, "光标默认在'出击'上（默认动作是去打）")
	b.close()
	t.eq(int(b.get("cursor")), 0, "关闭后仍是 0（下次 open 会重设）")
	b.free()


# ============================================================ 7 标题卡
static func _title_card(t: T) -> void:
	t.suite("出击循环 / 标题卡（§7.4：2 秒 / 可跳过 / 不引入新框架）")

	t.near(TITLE.HOLD, 2.0, 0.0001, "★ 停留就是 §7.4 定的 2 秒")
	var src := SuiteUiStyle._code("res://scripts/ui/mission_title.gd")
	t.ok(src.contains("signal finished"), "对外只有一个 finished 信号")
	t.not_ok(src.contains("Tween"), "不引入 Tween（§7.4：一页纯 `_draw()` + 一个计时器）")
	t.not_ok(src.contains("AnimationPlayer"), "不引入 AnimationPlayer")
	t.not_ok(src.contains("load(\"res://scenes/"), "没有独立场景档")
	t.ok(src.contains("const MS := preload("), "跨文件引用走 preload（不走 class_name）")

	var tc := TITLE.new()
	t.not_ok(bool(tc.get("active")), "刚建出来是关着的")
	t.eq(tc.lines().size(), 3, "三行：编号 / 任务名 / 地图·时段")
	t.eq(str(tc.lines()[1]), "", "没装任务时中间那行是空的")
	t.eq(tc.progress_ratio(), 0.0, "进度 0")
	t.ok(tc.play("M01"), "能起播")
	t.eq(str(tc.lines()[0]), "MISSION 01", "第一行是编号")
	t.eq(str(tc.lines()[1]), "夜袭达沃", "第二行是任务名")
	t.ok(str(tc.lines()[2]).contains(m01_map_name()), "第三行带地图名")
	t.ok(str(tc.lines()[2]).contains(BRIEF.time_label("night")),
		"★ 第三行的时段借的是简报页那个函数（真源只有一处，不许各写一份）")
	# 进度随 `_process` 单调增，到 2 秒收尾
	tc.call("_process", 1.0)
	t.between(tc.progress_ratio(), 0.49, 0.51, "1 秒 = 进度一半")
	t.ok(bool(tc.get("active")), "1 秒时还在播")
	tc.call("_process", 1.05)
	t.not_ok(bool(tc.get("active")), "★ 越过 2 秒 ⇒ 自己收尾（收尾信号是 main 往下走的唯一依据）")
	t.not_ok(tc.play(""), "空 id 起不来（调用方不该 await `finished`）")
	tc.free()


static func m01_map_name() -> String:
	var m: MS.Mission = MS.by_id("M01")
	return m.map_name() if m != null else ""


# ============================================================ 7.5 菜单入口（旧向导不许再走）
## 老板 2026-09-29：「现在剧情模式的入口还是之前版本的。」
##
## **病因**：菜单里选「剧情挑战」之后走的是**旧挑战的 4 页向导**
## （`Stage.SUIT` → `Stage.ENCOUNTER` → `Stage.DIFFICULTY`），
## 而其中**两页的选择在剧情模式下完全不作数** ——
##   机体页选的那台机 → 被 `Mission.player_suit` 覆盖（POV 就是这么演的）；
##   遭遇页选的那 4 场（`ChallengeScript.for_suit()`）→ 被战役图上选的那一关覆盖。
## ⇒ 玩法上等于「先做两个不作数的决定，再进战役图重做一遍」。
##
## **修法**：剧情模式**只有一步**（`step_labels()` 返回 1 项），按下去直接 `_launch()`，
## 由 main 拦到战役图 —— **选关与难度都在战役图上**（§6.1 的循环前门）。
## 这一节钉的就是「它真的只有一步」以及「难度真的搬到了战役图上」。
static func _menu_entry(t: T) -> void:
	t.suite("出击循环 / 菜单入口（剧情模式不走旧向导）")

	# ---- ① 步骤：1 步 ----
	var m := MainMenu.new()
	t.ok(m.select_mode(Game.MatchMode.CHALLENGE), "菜单里能摆到剧情模式")
	var labels: Array = m.step_labels()
	t.eq(labels.size(), 1, "★ 剧情模式只有 1 步（旧的是 4 步：模式/机体/遭遇/难度）")
	t.eq(str(labels[0]), "① 选择模式", "那一步就是「选模式」本身")
	t.eq(m.step_count(), 1, "step_count 跟着 step_labels 走（不许各写一份）")
	t.eq(m.step_index(), 0, "停在模式页 ⇒ 步骤条亮第 ① 个点（不出界）")
	# 其余四种模式**一个字都没改**（§9.4 的硬约束：不碰现有四种模式）
	m.select_mode(Game.MatchMode.VERSUS)
	t.eq(m.step_count(), 5, "对战仍是 5 步")
	m.select_mode(Game.MatchMode.SQUAD)
	t.eq(m.step_count(), 5, "小队战仍是 5 步")
	m.select_mode(Game.MatchMode.TRAINING)
	t.eq(m.step_count(), 3, "训练仍是 3 步")
	m.select_mode(Game.MatchMode.LAN)
	# ⚠️ 2026-10-11（用户：「**先创建房间之后，再在房间里面决定对战模式和机体**」）：
	# 联机从 4 步收回 **2 步** —— 「选择阵营」「选择机体」两步搬进**房间界面**。
	t.eq(m.step_count(), 2, "联机是 2 步（模式 → 创建 / 加入房间）")
	m.free()

	# ---- ② 按下去**直接出击**（源码扫描：拦在"单项分组"分支之前）----
	var menu_src := SuiteUiStyle._code("res://scripts/ui/main_menu.gd")
	var mode_body := _body(menu_src, "Stage.MODE:")
	t.ok(mode_body.length() > 0, "取到了模式页的输入分支")
	# ⚠️ 2026-10-11：这条规则**搬进了 `mode_entry_stage()`** —— 模式页有**两个入口**
	#（`_read_input()` 与极简首页 `menu_home.open_entry()`），各写一遍必然分家
	#（联机那一步漏过一次：从首页进去还是走老流程）。
	# ⇒ 判据跟着规则走：这两条改扫那个函数的体，位置关系一个字没改。
	var rule_body := _body(menu_src, "func mode_entry_stage(")
	t.ok(rule_body.length() > 0, "取到了 `mode_entry_stage()` 的体")
	t.ok(rule_body.contains("selected_mode() == Game.MatchMode.CHALLENGE"),
		"★ 规则里认得出「这一分组是剧情模式」")
	t.ok(rule_body.find("selected_mode() == Game.MatchMode.CHALLENGE")
			< rule_body.find("current_group()[\"modes\"].size() > 1"),
		"★ 拦在「单项分组 ⇒ 进下一页」**之前** —— 不拦的话它和训练/联机一样继续往机体页走")
	t.ok(mode_body.contains("_launch()"),
		"★ 剧情模式在这一页就结束（`_launch()` → main 拦到战役图）")
	t.ok(menu_src.contains("return [\"① 选择模式\"]"), "步骤表里就是不折不扣的一项")

	# ---- ③ 难度搬到战役图上 ----
	t.suite("出击循环 / 难度（从菜单挪到战役图）")

	t.eq(CMAP.difficulty_text(Difficulty.Level.EASY), "难度  ◀ 简单 ▶", "简单")
	t.eq(CMAP.difficulty_text(Difficulty.Level.NORMAL), "难度  ◀ 中等 ▶", "中等")
	t.eq(CMAP.difficulty_text(Difficulty.Level.HARD), "难度  ◀ 困难 ▶", "困难")
	# ⚠️ 名字**只从 `Difficulty.make()` 取** —— 这里拿真源再拼一遍，两边必须相等。
	for lv: int in Difficulty.all_levels():
		t.ok(CMAP.difficulty_text(lv).contains(Difficulty.make(lv).name_cn),
			"★ 难度 %d 的名字与 `Difficulty.make().name_cn` 一致（UI 里不另抄一张表）" % lv)
	t.eq(CMAP.cycle_difficulty(Difficulty.Level.NORMAL, 1), Difficulty.Level.HARD, "右 ⇒ 下一档")
	t.eq(CMAP.cycle_difficulty(Difficulty.Level.NORMAL, -1), Difficulty.Level.EASY, "左 ⇒ 上一档")
	t.eq(CMAP.cycle_difficulty(Difficulty.Level.HARD, 1), Difficulty.Level.EASY,
		"★ 在 `all_levels()` 上**循环**（困难再往右回简单）")
	t.eq(CMAP.cycle_difficulty(Difficulty.Level.EASY, -1), Difficulty.Level.HARD, "左到底是困难")
	t.eq(CMAP.cycle_difficulty(99, 1), Difficulty.Level.HARD,
		"不认识的值先落回「普通」再走（绝不返回非法值）")
	t.eq(CMAP.cycle_difficulty(-1, 0), Difficulty.Level.NORMAL, "位移 0 ⇒ 停在普通（不崩）")

	var cmap_src := SuiteUiStyle._code("res://scripts/ui/campaign_map.gd")
	var inp_body := _body(cmap_src, "func _input(")
	t.ok(inp_body.contains("KEY_LEFT"), "★ 左键能调难度")
	t.ok(inp_body.contains("KEY_RIGHT"), "★ 右键能调难度")
	t.ok(inp_body.contains("_cycle_diff("), "走同一个私有入口（不各写一份）")
	var foot_body := _body(cmap_src, "func _draw_foot(")
	t.ok(foot_body.contains("difficulty_text(level)"),
		"★ 脚注真的把它画出来（`_shown` 之外还有一层：画出来才算数）")
	t.ok(foot_body.find("difficulty_text(level)") < foot_body.find("if cursor >= ids.size()"),
		"★ 它画在「停在返回行就早退」**之前** —— 停在返回行上也看得见难度")
	t.ok(cmap_src.contains("func level_label() -> String:"), "读数口（实例身上记着哪个难度）")

	# ---- ④ main 侧的三个接口（进图落值 / 出图抄回 / 拦截时用常量）----
	var main_src := SuiteUiStyle._code("res://scripts/main.gd")
	t.ok(main_src.contains("campaign_map.level = _campaign_level"),
		"★ 进战役图时把难度**落进**那一页")
	t.ok(main_src.contains("_campaign_level = campaign_map.level"),
		"★ 离开战役图时把玩家选的难度**抄回** `_campaign_level`（唯一出口，少了它切的难度一步都不生效）")
	var open_body := _body(main_src, "func _open_campaign(")
	t.ok(open_body.contains("campaign_map.level = _campaign_level"),
		"落值在 `_open_campaign()` 里（`open()` 之后 —— 它只摆光标，不动难度）")
	var chosen_body := _body(main_src, "func _on_campaign_chosen(")
	t.ok(chosen_body.contains("_campaign_level = campaign_map.level"),
		"抄回在 `_on_campaign_chosen()` 里（「离开战役图 = 选关定案」的那一刻）")
	var load_body := _body(main_src, "func _begin_match_loading(")
	var chal_at := load_body.find("Game.MatchMode.CHALLENGE")
	t.ok(chal_at >= 0, "拦截分支在")
	var chal_tail := load_body.substr(chal_at)
	t.ok(chal_tail.contains("_open_campaign(Difficulty.Level.NORMAL)"),
		"★ 拦截时传的是**有意的常量**，不是菜单里那个玩家看不见的下标")
	t.not_ok(chal_tail.contains("_open_campaign(difficulty_level)"),
		"★ 不许再拿菜单的 `difficulty_level` 当剧情难度（那就是「隐藏的难度」）")


# ============================================================ 8 接线（源码扫描）
static func _wiring(t: T) -> void:
	t.suite("出击循环 / 接线（源码扫描）")

	var main_src := SuiteUiStyle._code("res://scripts/main.gd")

	# ---- 阶段枚举：**只加成员、不改已有成员的名字** ----
	t.ok(main_src.contains("Phase.CAMPAIGN"), "main 有 CAMPAIGN 阶段（战役图）")
	t.ok(main_src.contains("Phase.BRIEF"), "main 有 BRIEF 阶段（简报页）")

	# ---- 菜单的"出击"被拦到战役图 ----
	var load_body := _body(main_src, "func _begin_match_loading(")
	t.ok(load_body.length() > 0, "取到了 `_begin_match_loading` 的函数体")
	t.ok(load_body.contains("Game.MatchMode.CHALLENGE"),
		"★ 在**读条入口**里判模式（不是改菜单）")
	t.ok(load_body.contains("_open_campaign(Difficulty.Level.NORMAL)"),
		"★ 剧情模式的'出击'落在战役图上，而不是直接开打")
	t.ok(load_body.find("CHALLENGE") < load_body.find("_resolve_match("),
		"★ 拦在 `_resolve_match()` **之前**（否则会先被 CHALLENGE 分支拿去查 ChallengeScript）")

	# ---- 剧情模式的地图**不许有兜底** ----
	var rc_body := _body(main_src, "func _resolve_campaign_match(")
	t.ok(rc_body.length() > 0, "取到了 `_resolve_campaign_match` 的函数体")
	t.ok(rc_body.contains("MS.to_encounter(m)"),
		"波次入口走 `Mission → Encounter`（`_spawn_wave()` 一行都不用改）")
	t.ok(rc_body.contains("MapDef.by_id(mid)"), "地图来自 `Mission.map_id()`")
	t.not_ok(rc_body.contains("xi_vs_penelope"),
		"★ 剧情模式的地图**没有兜底** —— `_resolve_match()` 的 CHALLENGE 分支查不到就兜"
		+ " `xi_vs_penelope()`（太平洋），M03/M04/M05/M06 会**静默打错地图**")
	t.not_ok(rc_body.contains("ChallengeScript.for_suit"), "同上：不许从机型反查遭遇")
	t.ok(rc_body.contains("return false"), "查不到 ⇒ 返回 false（调用方退回战役图）")

	# ---- 军资结算必须早于 capture_result ----
	var pd_body := _body(main_src, "func _on_player_destroyed(")
	var fr_body := _body(main_src, "func _finish_round(")
	t.ok(pd_body.contains("_settle_campaign(false)"), "阵亡那条路先结算军资")
	t.ok(pd_body.find("_settle_campaign(") < pd_body.find("hud.capture_result("),
		"★ 阵亡：结算军资**早于** `capture_result()`（晚了那行永远显示 +0）")
	t.ok(fr_body.contains("_settle_campaign(true)"), "胜利那条路先结算军资")
	t.ok(fr_body.find("_settle_campaign(") < fr_body.find("hud.capture_result("),
		"★ 胜利：同样是先算钱再定格快照")

	# ---- 播片钩子：P / B / D 三处，`mid` 一处都没有 ----
	t.ok(main_src.contains("_play_cutscene(\"prologue\""), "P 槽接上了（序章）")
	t.ok(main_src.contains("_play_cutscene(\"brief\""), "B 槽接上了（任务前）")
	t.ok(main_src.contains("_play_cutscene(\"debrief\""), "D 槽接上了（任务后）")
	t.not_ok(main_src.contains("_play_cutscene(\"mid\""),
		"★ `mid` 槽**一个调用点都没有** —— 它要 `Trigger`（轮 D/E）来点名，轮 C 只留钩子")
	var pcs_body := _body(main_src, "func _play_cutscene(")
	t.ok(pcs_body.length() > 0, "取到了 `_play_cutscene` 的函数体")
	t.ok(pcs_body.contains("m.slot(slot)"),
		"★ 片目清单由 `Mission.cutscenes[slot]` 给（§7.5.4：顺序由 Mission 决定）")
	t.ok(pcs_body.contains("CUT.by_id("), "路径从片目表按 id 查")
	t.not_ok(pcs_body.contains("CUT.by_slot(mission_id"),
		"★ 不走 `by_slot(mission_id, …)` 当第二条路（两份清单必然分家，而且不报错）")
	t.ok(pcs_body.contains("clip.available()"), "缺片 ⇒ 跳过这一支（素材是可选的）")

	# ---- 战役图/简报页的跨文件引用 ----
	for path: String in ["res://scripts/ui/campaign_map.gd", "res://scripts/ui/mission_brief.gd"]:
		var usrc := SuiteUiStyle._code(path)
		t.ok(usrc.contains("preload(\"res://scripts/data/campaign.gd\")"),
			"%s：跨文件引用走 preload（不走 class_name，理由见 campaign.gd 头注）" % path)
		t.not_ok(usrc.contains("CampaignScript."),
			"%s：源码里不出现 `CampaignScript.`（一律走 `CS.` 别名）" % path)
		# 与 `suite_ui_style` 同一条硬规矩：右对齐**必须先量出可用宽度**再传进去。
		# ⚠️ 钉的是"注定失效的那一种写法"（宽度传 −1：宽度由字符串自己算，
		#    右对齐参数被忽略 ⇒ 文本原地不动、然后冲出屏幕），**不是**"不许右对齐"。
		#    这两页里各有一处右对齐，传的都是**正的排版宽度**
		#    （`box.size.x - 12.0` / `title.size.x`）—— 那正是对的写法。
		var right_lines := 0
		for line: String in usrc.split("\n"):
			if not line.contains("HORIZONTAL_ALIGNMENT_RIGHT"):
				continue
			right_lines += 1
			t.not_ok(line.contains("-1"),
				"%s：右对齐那一行不许把宽度写成 -1（对齐参数会被忽略）：%s"
				% [path, line.strip_edges()])
		t.gt(float(right_lines), 0.0,
			"%s：确实有一处右对齐 ⇒ 上面那条不是空转（不写死条数，改版式不会假红）" % path)
		# ★ 文案一律走 `MS.plain()` —— 数据里的 `**强调**` 标记不该画到屏幕上。
		# ⚠️ 而且**不许自己再写一份**（`replace("**", "")`）：谁另写一遍，
		# 谁就制造出"有的页面干净、有的页面带着星号"这种只在某个入口才出现的难看。
		t.ok(usrc.contains("MS.plain("), "%s：文案走 `MS.plain()`（渲染期去标记）" % path)
		t.not_ok(usrc.contains("replace(\"**\""), "%s：不自己再写一份去标记（真源只有一处）" % path)

	# ---- 播放器：`play_blocking` 必须是 static ----
	var im_src := SuiteUiStyle._code("res://scripts/ui/intro_movie.gd")
	t.ok(im_src.contains("static func play_blocking(parent: Node, id: String) -> bool:"),
		"★ `play_blocking` 是 **static** —— 它一个 `self` 都不用（自己 spawn、自己 dispose）")
	t.ok(im_src.contains("static func begin_by_id") == false,
		"`begin_by_id` 仍是**实例**方法（它改实例状态：clip_index / clip_id）")

	# ---- 片目表：真实表是**空的** ----
	var cs_src := SuiteUiStyle._code("res://scripts/data/cutscene_script.gd")
	t.ok(cs_src.contains("const CLIPS: Array = []"),
		"★ 真实片目表是空数组字面量（示例在注释里，不许抄进 const 当'已经有片了'）")
	t.not_ok(cs_src.contains("weight"), "★ 战役片目表**没有权重**（不随机；开场那条管线才随机）")

	# ---- 存档路径是**注入点**（测试不许写花玩家的档） ----
	t.ok(main_src.contains("var campaign_save_path := CS.PATH"),
		"★ 存档路径是 main 上的一个变量（默认真路径）—— §6.6 要求'读写走注入路径'")
	t.ok(main_src.contains("CS.load_progress(CS.path_for_difficulty(campaign_save_path,level))"),
		"剧情读盘先由注入路径选出对应难度组的存档")
	t.ok(main_src.contains("CS.save_progress(Game.campaign_progress, CS.path_for_difficulty(campaign_save_path,_campaign_level))"),
		"剧情写盘使用同一个注入路径和当前难度组，不能落进另一套进度")

	# ---- HUD：军资那行与'重来'都由纯函数给文案 ----
	var hud_src := SuiteUiStyle._code("res://scripts/ui/hud.gd")
	t.ok(hud_src.contains("static func sally_text(sally: Dictionary) -> String:"),
		"`sally_text` 是纯函数（static ⇒ 测试不必造 HUD）")
	t.ok(hud_src.contains("static func result_hint(sally: Dictionary, back_label := \"回主菜单\") -> String:"),
		"`result_hint` 是纯函数，且**默认值就是那句话**（四种现有模式逐字符不变）")
	t.ok(hud_src.contains("_text_right(Vector2(UILayout.content_right(size), geo[\"hint_y\"]), credit"),
		"军资右对齐到内容区右边界（避开与中间的提示行撞在一起）")

	# ---- 结算页的 'R 重来' 只能在剧情模式 + 失败时给 ----
	t.ok(main_src.contains("_can_retry()"), "结算页问了'能不能重来'")
	t.ok(main_src.contains("not bool(Game.sally_result.get(\"win\", false))"),
		"★ 重来只在**失败**时给（§3.2 的流程图里它写在'失败'那一支）")
	t.ok(main_src.contains("var r_down := Input.is_key_pressed(KEY_R)"),
		"R 没有输入动作 ⇒ 自己量边沿（直接用 is_key_pressed 会每帧重来一次）")


# ============================================================ 9 真流程
static func _real_flow(t: T, host: Node) -> void:
	t.suite("出击循环 / 真流程（主场景 + 临时存档）")

	var real := CS.PATH   # user://campaign.cfg
	var real_had := FileAccess.file_exists(real)
	var real_md5 := FileAccess.get_md5(real) if real_had else ""

	# 把 `Game` 的全局状态存起来 —— autoload 是**整个进程**共用的，
	# 本套件改过的每一项都要还回去（否则后面的套件会读到一个"剧情模式刚打完"的世界）。
	var keep := {
		"mode": Game.match_mode,
		"suit": Game.active_suit,
		"diff": Game.active_difficulty,
		"map": Game.active_map,
		"tod": Game.active_time_of_day,
		"mission": Game.active_mission,
		"chal": Game.active_challenge,
		"chal_id": Game.active_challenge_id,
		"prog": Game.campaign_progress,
		"sally": Game.sally_result,
		"kills": Game.kills,
		"enemy_suit": Game.active_enemy_suit,
	}

	CS.erase(TMP)
	var packed := load("res://scenes/main.tscn") as PackedScene
	t.ok(packed != null, "main.tscn 能加载")
	if packed == null:
		return
	var main := packed.instantiate()
	host.add_child(main)
	# ★ 注入临时存档路径：下面会**真的落盘**，但写的是临时文件。
	main.set("campaign_save_path", TMP)

	t.eq(main.get("phase"), _main_phase(main, "MENU"), "开局停在主菜单")

	# ---- ① 进战役图 ----
	main.call("_open_campaign", Difficulty.Level.NORMAL)
	await host.get_tree().process_frame
	t.eq(main.get("phase"), _main_phase(main, "CAMPAIGN"), "★ 进了战役图阶段")
	var cmap: Node = main.get("campaign_map")
	t.ok(cmap != null, "战役图节点在")
	t.ok(bool(cmap.get("active")), "战役图是开的")
	t.not_ok(bool((main.get("menu") as Node).get("active")), "主菜单**关掉了**（它的 Enter 不该被接着吃）")
	t.not_ok(bool((main.get("hud") as Node).visible), "HUD 不画")
	t.gt(float(Game.campaign_progress.size()), 0.0, "★ 进度已经读进来了（临时档不存在 ⇒ 空档）")
	t.eq(int(Game.campaign_progress.get("credits", -1)), 0, "空档军资为 0")
	t.eq(int(cmap.get("cursor")), 0, "光标停在'当前该打的那一关'（空档 ⇒ M01）")
	t.eq(str(cmap.selected_id()), "M01", "默认选中的就是 M01")
	t.eq(str(cmap.credits_text()), "军资 0", "战役图上有军资余额（§11.2 明写要）")

	# ---- ② 选关 → 简报 ----
	cmap.set("cursor", 3)
	main.call("_on_campaign_chosen", "M01")
	await host.get_tree().process_frame
	t.eq(main.get("phase"), _main_phase(main, "BRIEF"), "★ 进了简报阶段")
	var brief: Node = main.get("mission_brief")
	t.ok(bool(brief.get("active")), "简报页是开的")
	t.ok(cmap.get("active") == false, "战役图关掉了（两个页面不许同时吃输入）")
	var bm = brief.get("mission")
	t.ok(bm != null, "简报页装着这一关")
	t.eq(str(bm.id), "M01", "装的就是 M01")
	t.eq(str(main.get("_campaign_mission_id")), "M01", "main 记住了这一关（'重来'靠它）")

	# ---- ③ 简报取消 → 回战役图，**光标不丢** ----
	main.call("_on_brief_cancelled")
	await host.get_tree().process_frame
	t.eq(main.get("phase"), _main_phase(main, "CAMPAIGN"), "取消 ⇒ 回战役图（不是回主菜单）")
	t.ok(bool(cmap.get("active")), "战役图又开了")
	t.eq(int(cmap.get("cursor")), 3, "★ 光标停在原来那一行（不会把玩家弹回第一关）")
	t.eq(str(main.get("_campaign_mission_id")), "", "取消后清掉'当前关'")

	# ---- ④ 解析一关：★ 地图**必须**来自 Mission（这就是那个静默失败点）----
	t.ok(bool(main.call("_resolve_campaign_match", "M05")), "M05 解析成功")
	t.eq(Game.match_mode, Game.MatchMode.CHALLENGE, "模式 = 剧情挑战（复用 CHALLENGE，不新加枚举）")
	t.eq(Game.active_map.id, MapDef.Id.OENBELLI,
		"★ M05 的地图是奥恩贝利 —— 若走了 `_resolve_match()` 的兜底，这里会是**太平洋**")
	t.eq(Game.active_suit, SuitProfile.Id.XI, "自机 = M05 的 `player_suit`（剧情模式不选机体）")
	t.ok(Game.active_mission != null, "`active_mission` 装上了")
	t.eq(str(Game.active_mission.id), "M05", "装的就是 M05")
	t.ok(Game.active_challenge != null, "波次入口也装上了（`Mission → Encounter`）")
	t.eq(str(Game.active_challenge.id), "M05", "Encounter 的 id 与 Mission 一致")
	t.eq((Game.active_challenge.waves as Array).size(), (Game.active_mission.waves as Array).size(),
		"★ 波次数据逐项同源（`_spawn_wave()` 一行都不用改）")
	t.eq(int(Game.active_challenge.map_id), int(Game.active_mission.map_id()),
		"★ Encounter 的地图与 Mission 一致（两处指向同一张图）")
	t.not_ok(bool(main.call("_resolve_campaign_match", "M99")), "不认识的关 ⇒ false（不崩）")
	t.not_ok(bool(main.call("_resolve_campaign_match", "")), "空 id ⇒ false")
	# 解析失败的**副作用**：不该把 `Game.active_map` 改成别的图
	t.ok(bool(main.call("_resolve_campaign_match", "M03")), "M03（轨道图）也能解析")
	t.eq(Game.active_map.id, MapDef.Id.LEO, "★ M03 的地图是低地球轨道（轮 B2 那张）")

	# ---- ④b ★ 难度：在战役图上切，出击时**真的**进这一局 ----
	# 这一条是"难度搬了家"的**端到端**判据。它守的正是反面那种事故：
	# 页面上能切、`level` 也在动，而 `_campaign_level` 没人去读 ⇒ **切了不生效、还不报错**
	#（旧挑战向导也是这么藏的：没有难度页，`_launch()` 照样把 `selected_level()` 传出去）。
	main.call("_open_campaign", Difficulty.Level.NORMAL)
	await host.get_tree().process_frame
	t.eq(int(cmap.get("level")), Difficulty.Level.NORMAL, "进图时难度 = 传进来的那一档")
	cmap.call("_cycle_diff", 1)
	t.eq(int(cmap.get("level")), Difficulty.Level.HARD, "右键一档 ⇒ 困难")
	t.eq(str(cmap.level_label()), "难度  ◀ 困难 ▶", "读数口也跟上了")
	main.call("_on_campaign_chosen", "M01")
	await host.get_tree().process_frame
	t.eq(int(main.get("_campaign_level")), Difficulty.Level.HARD,
		"★ 离开战役图 ⇒ 玩家选的难度被抄进 `_campaign_level`（少这一步就是「切了不生效」）")
	t.ok(bool(main.call("_resolve_campaign_match", "M01")), "M01 就位")
	t.ok(Game.active_difficulty != null, "难度对象装上了")
	t.eq(int(Game.active_difficulty.level), Difficulty.Level.HARD,
		"★ 端到端：战役图上切的难度真的进了这一局（§9.4 的反面 —— 不许有隐藏难度）")
	# 收尾：把难度放回普通，免得影响后面几节（它们按默认档算军资与评价）。
	main.call("_open_campaign", Difficulty.Level.NORMAL)
	await host.get_tree().process_frame
	t.eq(int(cmap.get("level")), Difficulty.Level.NORMAL, "进图时按 `_campaign_level` 落值 ⇒ 回到普通")

	# ---- ⑤ 军资结算：真落盘，但落在**临时档**上 ----
	CS.erase(TMP)
	Game.campaign_progress = CS.new_progress()
	Game.kills = 2
	t.ok(bool(main.call("_resolve_campaign_match", "M01")), "M01 就位")
	main.call("_settle_campaign", true)
	t.ok(not Game.sally_result.is_empty(), "★ 结算后 `Game.sally_result` 非空（结算页靠它分家）")
	t.ok(bool(Game.sally_result.get("win", false)), "记着这是**赢**的一局")
	var rew := int(Game.sally_result.get("reward", 0))
	var del := int(Game.sally_result.get("delta", 0))
	var m01: MS.Mission = MS.by_id("M01")
	t.gt(float(rew), float(m01.base_reward), "本局军资 > 基础值（评价加成 + 击坠加成都在里面）")
	# ⚠️ `sally_result` 只装**四个数**（reward / delta / win / next —— §6.6：不把整份进度
	# 塞进 HUD 的快照），所以那个字母**不在快照里**，得从**同一套纯函数链**反推回来：
	# `FlightHUD.rating_stats()` → `MissionRating.evaluate()`，喂进去的就是
	# `_settle_campaign()` 喂的那几个读数（本流程没起过战斗 ⇒ `player` 为 null ⇒ 0/0/0）。
	# ⇒ 断言写成"两边必须相等"，**不写死数值** —— 评价权重一改（那是允许调的），
	#    这里不会变成一条假红。
	var pl: Variant = main.get("player")
	var hp_r := 0.0
	var if_hp := 0.0
	var if_max := 0.0
	if pl != null and is_instance_valid(pl):
		hp_r = float(pl.hp_ratio())
		if_hp = float(pl.ifield_hp)
		if_max = float(pl.ifield_max)
	var grade := str(MissionRating.evaluate(FlightHUD.rating_stats(
		MissionRating.Outcome.WIN, hp_r, if_hp, if_max)).get("grade", MissionRating.NO_GRADE))
	t.eq(rew, CS.reward_for({"base": m01.base_reward, "grade": grade,
		"kills": 2, "named_kills": 0}),
		"★ 结算走的确实是 `reward_for()` 那条纯函数，字母也确实来自 `MissionRating`（本局「%s」）"
		% grade)
	t.eq(del, rew, "首通 ⇒ 到账 = 全额")
	t.eq(int(Game.campaign_progress.get("credits", -1)), del, "钱包 = 到账")
	t.ok(CS.is_cleared(Game.campaign_progress, "M01"), "★ M01 被点亮")
	t.eq(str(Game.sally_result.get("next", "")), "M02", "★ 首通 ⇒ 结算页会写'解锁 M02'")
	t.ok(FileAccess.file_exists(TMP), "★ 真的落盘了（写的是临时档）")
	var loaded := CS.load_progress(TMP)
	t.eq(int(loaded.get("credits", -1)), del, "★ 读回来的军资与内存里那一份一致")
	t.ok(CS.is_cleared(loaded, "M01"), "★ 读回来的通关位也一致")
	t.ok(FlightHUD.sally_text(Game.sally_result).begins_with("军资 +"),
		"结算页那一行开头是'军资 +'")

	# 重打：同一套战果（同评价、同击坠）⇒ 只补差额 0
	main.call("_settle_campaign", true)
	t.eq(int(Game.sally_result.get("delta", -1)), 0, "★ 重打同样成绩 ⇒ 到账 0（不重复给）")
	t.eq(int(Game.campaign_progress.get("credits", -1)), del, "★ 钱包**只加不减**（不是被覆盖）")
	t.eq(str(Game.sally_result.get("next", "")), "",
		"★ 重打不再写'解锁 M02'（那会变成噪音）")

	# 重打但打得更好 ⇒ 只补差额
	Game.kills = 6
	main.call("_settle_campaign", true)
	var del2 := int(Game.sally_result.get("delta", 0))
	t.gt(float(del2), 0.0, "★ 打得更好 ⇒ 补差额")
	t.eq(int(Game.campaign_progress.get("credits", -1)), del + del2, "钱包 = 上次 + 差额")
	t.ok(FlightHUD.sally_text(Game.sally_result).contains("最好"),
		"结算页写清了'最好 N'（差额那一路）")

	# 失败 ⇒ 到账 0，而且**给'重来'**
	main.call("_settle_campaign", false)
	t.not_ok(bool(Game.sally_result.get("win", true)), "记着这是输的")
	t.eq(int(Game.sally_result.get("delta", -1)), 0, "★ 输 ⇒ 一分钱不进")
	t.eq(int(Game.campaign_progress.get("credits", -1)), del + del2, "钱包不动")
	t.ok(bool(main.call("_can_retry")), "★ 失败 ⇒ 结算页给'R 重来'")
	t.ok(FlightHUD.result_hint(Game.sally_result, "回战役图").contains("R 重来"),
		"提示行里真的写出了重来")
	main.call("_settle_campaign", true)
	t.not_ok(bool(main.call("_can_retry")), "★ 通关的结算页**不给**重来（§3.2：它只写在失败那一支）")

	# ---- ⑥ 非剧情模式：一行都不多（§9.4）----
	Game.active_mission = null
	main.call("_settle_campaign", true)
	t.ok(Game.sally_result.is_empty(), "★ `active_mission` 为空 ⇒ 清空 sally（结算页不画那一行）")
	t.eq(FlightHUD.sally_text(Game.sally_result), "", "军资那行是空串")
	t.eq(FlightHUD.result_hint(Game.sally_result), "Enter / Esc  回主菜单",
		"★ 提示行回到原来的那一句")

	# ---- ⑦ 回主菜单 = 真的离开剧情流程 ----
	main.call("_open_campaign", Difficulty.Level.NORMAL)
	await host.get_tree().process_frame
	main.call("_show_menu")
	await host.get_tree().process_frame
	t.eq(main.get("phase"), _main_phase(main, "MENU"), "回到主菜单阶段")
	t.not_ok(bool(cmap.get("active")), "战役图关掉了")
	t.not_ok(bool(brief.get("active")), "简报页也没开着")
	t.eq(str(main.get("_campaign_mission_id")), "", "★ '当前关'被清掉（留着会让下一局莫名其妙重开上一关）")
	t.ok(Game.sally_result.is_empty(), "结算快照也清了")

	# ============================================================ 收尾
	main.queue_free()
	CS.erase(TMP)
	Game.match_mode = int(keep["mode"])
	Game.active_suit = int(keep["suit"])
	Game.active_difficulty = keep["diff"]
	Game.active_map = keep["map"]
	Game.active_time_of_day = keep["tod"]
	Game.active_mission = keep["mission"]
	Game.active_challenge = keep["chal"]
	Game.active_challenge_id = str(keep["chal_id"])
	Game.campaign_progress = keep["prog"]
	Game.sally_result = keep["sally"]
	Game.kills = int(keep["kills"])
	Game.active_enemy_suit = int(keep["enemy_suit"])

	# ⚠️ 最重要的一条：本套件跑完，**玩家真实的存档逐字节没变**。
	t.eq(FileAccess.file_exists(real), real_had,
		"★ 真实存档的存在性没被改动（全程用的是注入的临时路径）")
	if real_had:
		t.eq(FileAccess.get_md5(real), real_md5, "★ 真实存档的内容逐字节没变")
	else:
		t.ok(not FileAccess.file_exists(real), "★ 本套件全程没有创建过真实存档")
