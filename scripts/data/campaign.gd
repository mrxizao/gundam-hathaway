class_name CampaignScript
extends RefCounted
## 剧情模式的**战役层**（DESIGN §3.1 / §6.6）：章节 → 任务清单、解锁判定、
## 进度读写（**注入路径**）、军资结算（§6.3）。
##
## ## 一句话
## 这一层只回答三件事：**下一关能不能打**、**这一局的战果值多少军资**、**进度存哪**。
##
## ## ⚠️ 为什么必须有它（不是"以后再说"）
## `README` §15 明写**「没有游戏进度存档」**（`Settings` 只存画面尺寸与音量）。
## 剧情模式的全部意义是"有前后、会丢掉、能重来" —— 没有存档就**没有"前后"**。
## ⇒ 它是 DESIGN §10 的**轮 0（硬前置）**。
##
## ## ⚠️ 三条"存档纪律"（每一条都有断言）
## 1. **读写走注入路径**：所有读写函数都收一个 `path`，默认 `user://campaign.cfg`。
##    测试**必须**传一个临时路径 —— 本工程栽过一次"测试把玩家的设置写花了"
##    （`Settings` 那边：测试照着错值还原并写进文件，跑一次测试玩家的设置就被改了）。
##    `suite_campaign` 因此还额外**逐字节**核对 `user://campaign.cfg` 没被动过。
## 2. **加载必须能承受损坏的老存档**：索引夹取、长度补齐、槽位裁剪（`clamp_loadout()`）。
##    `settings.gd` 里那条"老存档里没有这一项 ⇒ 越界崩在设置页上"是同一个坑。
## 3. **军资只增不减**：没有任何路径能算出负增量（`reward_for` / `credit_delta` 各自有下限）。
##
## ⚠️ 纯函数为主：`new_progress` / `is_unlocked` / `reward_for` / `settle` 都**不吃节点、
## 不吃时间**，喂字典就能断言。

# ⚠️ **跨文件引用走 `preload`，不走 `class_name`**。
#
# 本仓库是**并行编辑**的：新加的 `class_name` 只有在编辑器重新扫描过之后才会进
# `.godot/global_script_class_cache.cfg`；在那之前，任何 `MissionScript.xxx`
# 都会**当场编译失败**（"Identifier not found"），而 `--headless` 跑测试时
# 没有人会去刷新那份缓存。`preload` 是按路径解析的，与缓存无关。
# ⇒ 于是这一层**不依赖"编辑器有没有扫过"这件事**，无头回归随时跑得起来。
# （两条路都指向同一个脚本，不会产生第二份真源。）
const MS := preload("res://scripts/data/mission_script.gd")

# ============================================================ 表
#
## 存档里位掩码的**顺序**（bit i = 第 i 关）。
##
## ⚠️ 这份和 `MS.all()` 的返回顺序**必须一致** —— 不一致的后果是
## **老存档的进度会错位**（打通了 M03，读回来变成 M04 通关），而且**一处都不报错**。
## `suite_campaign` 直接断言两者相等 ⇒ 谁插/挪了任务，当场红。
const MASK_ORDER := ["M01", "M02", "M03", "M04", "M05", "M06", "M07", "M08", "M09", "M10", "M11", "M12"]

## 三章。第三章追加在既有七关之后，保留老存档的位序与成绩对应关系。
const CHAPTERS := [
	{"n": 1, "key": "ONE", "label": "第一章", "title": "正当的预言之王"},
	{"n": 2, "key": "TWO", "label": "第二章", "title": "喀耳刻的魔女"},
	{"n": 3, "key": "THREE", "label": "第三章", "title": "闪光的哈萨维"},
]
## 序章是**播片**、不是任务（老板：「豪泽恩号上的事情可以只用播片结束」）。
const PROLOGUE := {"key": "PROLOGUE", "label": "序章", "title": "豪泽恩号"}

## 存档路径。
const PATH := "user://campaign.cfg"

## 改装槽位（DESIGN §6.4 的老板原话：「一台机体只能带**一个上级**强化改装
## 和**三个**〔下级〕强化改装」）。
const UPGRADE_SLOTS_UP := 1
const UPGRADE_SLOTS_DOWN := 3
## 同一个下级词条**至多 2 份**（DESIGN §6.4.3：允许叠，但"三份装甲"会把存续项顶满、
## 让评价体系失效）。
const MAX_STACK_PER_ENTRY := 2

# ============================================================ 军资（§6.3）
#
## 评价加成（军资）。**只加不减**：这张表里没有一个负号。
const GRADE_BONUS := {"S": 400, "A": 280, "B": 180, "C": 100, "D": 40}
## 失败（`NO_GRADE`）**不给评价加成**，但**击坠依然算数** ——
## 这正是 DESIGN §4.4 那种"打输了也有战果"的落点（第三章的必败战要用它）。
const KILL_CREDITS := 30
## 命名王牌给更多（`NamedAce` 表，轮 F）。
const NAMED_KILL_CREDITS := 120


## 本局的军资（**纯函数**）。
##
## 输入 `st`：`{base, grade, kills, named_kills}` —— 四个数**全都已经存在或已经在
## `Mission` 数据里**（DESIGN §6.3 硬约束 2：不新增统计）。
##
## ⚠️ 三条都写在代码里而不是注释里：`base` / `kills` / `named_kills` 各自夹到 ≥ 0，
## `named_kills` 再夹到 ≤ `kills`（不许多报），返回值再夹一次 ≥ 0。
## 于是**无论喂什么进去，结果都是非负整数** —— "军资只增不减"这条不是靠调用方自觉。
static func reward_for(st: Dictionary) -> int:
	var base := maxi(int(st.get("base", 0)), 0)
	var grade := str(st.get("grade", MissionRating.NO_GRADE))
	var gb := 0
	if grade != MissionRating.NO_GRADE and GRADE_BONUS.has(grade):
		gb = int(GRADE_BONUS[grade])
	var kills := maxi(int(st.get("kills", 0)), 0)
	var named := clampi(int(st.get("named_kills", 0)), 0, kills)
	return maxi(base + gb + kills * KILL_CREDITS + named * NAMED_KILL_CREDITS, 0)


## 重打的**差额**：更好 ⇒ 只补差额，更差 ⇒ 0（DESIGN §6.3 硬约束 3）。
##
## ⚠️ **量纲是"军资"（整数），不是"分数"** —— 设计稿 §11.1 里那个
## `reward_delta(best=87.0, now=92.4) = 5.4` 的写法是拿分数举例说明"差额"这件事；
## 落地成货币时必须取整，所以这里收整数、出整数。**性质（差额 / 0）一字不差**：
## `reward_delta(87, 92) == 5`、`reward_delta(92, 87) == 0`。
static func reward_delta(best_reward: int, now_reward: int) -> int:
	return maxi(0, now_reward - best_reward)


## 首次通关拿**全额**，重打按差额。
##
## ⚠️ 不能直接把"没打过"当成 `best = 0` 去调 `reward_delta()` ——
## 那会让首通少拿 1 点（`reward - 1`），这种"差一"是查不出来的。
static func credit_delta(has_best: bool, best_reward: int, now_reward: int) -> int:
	if not has_best:
		return maxi(now_reward, 0)
	return reward_delta(best_reward, now_reward)


# ============================================================ 制作人模式（2026-09-30）
#
## ★ 制作人模式下"显示 / 判定用"的军资：**无限**。
##
## 老板原话（2026-09-30）：「……解锁各种关卡和**配件**，可以调试各种关卡……」
##
## ## 为什么"解锁配件"现在是这个形态
## 工程里**还没有商店**（`DESIGN §6.5` 的 `campaign_shop.gd` 是轮 C2 的事），
## 所以今天没有任何"买不起"的分支可以放开。唯一**今天就能落地、而且商店落地后
## 自动继续成立**的做法是：把"钱"这件事抽成一个纯函数 ——
## **商店问"买得起吗"的时候必须问 `credits_of()`，不许自己读 `progress["credits"]`**。
## 那样制作人模式就顺带覆盖了那个还没写的系统，而不是等它写完之后再补一遍。
##
## ## ⚠️ 它**绝不写进存档**
## 这是个**投影**，不是赋值：`save_progress()` 照旧写 `progress` 里那个真实余额。
## 少了这条纪律，开发者开一次制作人模式打一关，真档里的军资就变成 999999 ——
## 而那种损坏是**不可逆**的（玩家不会发现自己多了钱，只会发现难度体系失效了）。
const PRODUCER_FUNDS := 999999


## 显示 / 判定用的军资余额。`producer` 打开时恒为 `PRODUCER_FUNDS`。
static func credits_of(progress: Dictionary, producer := false) -> int:
	if producer:
		return PRODUCER_FUNDS
	return maxi(int(progress.get("credits", 0)), 0)


## 军资那一行的**唯一**文案（战役图页脚上方那一行）。
##
## ⚠️ 它把"∞"这件事收进数据层而不是留在 UI 里：`campaign_map` 只负责画，
## 换个页面要显示军资时也该调它 —— 否则"制作人模式该显示什么"就会有第二份说法。
static func credits_text(progress: Dictionary, producer := false) -> String:
	if producer:
		return "军资 ∞"
	return "军资 %d" % credits_of(progress)


## 全战役**理论最高**军资（全 S + 全部击坠 + 无命名王牌）。
##
## 用途：`campaign_shop` 的定价要拿它当分母 —— DESIGN §13 第 10 条要的是
## "全战役能买到 **2~3 件上级**"（让玩家**选**，而不是**攒齐**）。
## ⚠️ 它是**上界**（全 S 是理想值），实际到手会低一截。
static func max_reward() -> int:
	var total := 0
	for m in MS.all():
		total += reward_for({
			"base": m.base_reward,
			"grade": "S",
			"kills": m.total_enemies(),
			"named_kills": 0,
		})
	return total


# ============================================================ 进度（新档 / 夹取）
#
## 一份空档。
static func new_progress() -> Dictionary:
	return {
		"cleared_mask": 0,
		"best_grade": {},     # id -> "S".."D"（不含 NO_GRADE：失败不留成绩）
		"best_score": {},     # id -> float
		"best_reward": {},    # id -> int（"重打只补差额"的基准）
		"aces_down": [],      # 已击坠的命名王牌 id
		"aces_seen": [],      # 见过（未击坠也算）的图鉴条目
		"credits": 0,         # 军资
		"upgrades": {},       # "suit_<Id>" -> {"up": [...], "down": [...]}
		"super_hard_notice_seen": false,
		"chapter": 1,         # 当前章（战役图上高亮到哪一章）
	}


static func mission_ids() -> Array:
	var out: Array = []
	for m in MS.all():
		out.append(m.id)
	return out


## 任务 → 位掩码下标。**不认识的 id 返回 −1**（序章走的就是这一支）。
static func index_of(id: String) -> int:
	return MASK_ORDER.find(id)


## 这一关在不在战役序列里。
static func has_mission(id: String) -> bool:
	return index_of(id) >= 0


static func bit_of(id: String) -> int:
	var i := index_of(id)
	return 0 if i < 0 else (1 << i)


static func is_cleared(progress: Dictionary, id: String) -> bool:
	var i := index_of(id)
	if i < 0:
		return false
	return (int(progress.get("cleared_mask", 0)) & (1 << i)) != 0


static func cleared_count(progress: Dictionary) -> int:
	var n := 0
	for i: String in MASK_ORDER:
		if is_cleared(progress, i):
			n += 1
	return n


## 下一关（`""` = 已经是最后一关）。
static func next_id(id: String) -> String:
	var i := index_of(id)
	if i < 0 or i + 1 >= MASK_ORDER.size():
		return ""
	return str(MASK_ORDER[i + 1])


## 这一关**能不能打**。
##
## 规则只有一条：**第一关永远开着，其余要求"前一关已通关"**。
## ⚠️ 不做"跳关检测"这种东西 —— 顺序解锁的**传递闭包**已经保证了"乱序跳过被拒"
## （只通了 M01 时，M03 的前置 M02 没通 ⇒ 锁着）。多写一条判断 = 多处一个能不一致的真源。
## ⚠️ 跨章**不需要**额外条件：M04 → M05 在 `MASK_ORDER` 里本来就是相邻的。
static func is_unlocked(progress: Dictionary, id: String) -> bool:
	var i := index_of(id)
	if i < 0:
		return false
	if i == 0:
		return true
	return is_cleared(progress, str(MASK_ORDER[i - 1]))


## ★ 制作人模式下的"能不能进这一关"。
##
## ⚠️ 它与 `is_unlocked()` 是**并列的两个问题**，不是覆盖：
##   - `is_unlocked()` 答"**进度**允许吗"（第一关永远开、其余要前一关已通关）；
##   - 本函数答"**这一局**允许吗"（制作人模式打开 ⇒ 除不存在的关以外恒真）。
##
## 分成两个而不是给 `is_unlocked()` 加一个 `producer` 形参，理由是**调用方会分家**：
## `is_unlocked()` 还被"战役图上高亮到哪一章""下一关提示"那些地方念着，
## 那些地方**不该**因为制作人模式而变（"当前该打的那一关"仍然是它）。
## ⇒ `is_unlocked()` 一个字节都没改；**要"能不能进"就必须调这一个**。
##
## ⚠️ `has_mission(id)` 那道闸**留着**：制作人模式开的是"关卡锁"，
## 不是"允许进一个不存在的关"（那样 `_resolve_campaign_match()` 会 `return false`、
## 悄悄退回战役图 —— 一个"按了没反应"的症状）。
static func can_enter(progress: Dictionary, id: String, producer := false) -> bool:
	if producer:
		return has_mission(id)
	return is_unlocked(progress, id)


## 战役图上"当前该打的那一关"（= 第一个没通关的）。全通 ⇒ `""`。
static func current_id(progress: Dictionary) -> String:
	for i: String in MASK_ORDER:
		if not is_cleared(progress, i):
			return i
	return ""


## 一章的任务 id 列表（按 `MASK_ORDER`）。
static func ids_of_chapter(n: int) -> Array:
	var out: Array = []
	for m in MS.for_chapter(n):
		out.append(m.id)
	return out


static func chapter_of(id: String) -> int:
	var m = MS.by_id(id)
	return m.chapter if m != null else 0


static func chapter_title(n: int) -> String:
	for c: Dictionary in CHAPTERS:
		if int(c["n"]) == n:
			return str(c["title"])
	return ""


# ============================================================ 结算（纯函数）
#
## 把一局的战果落进进度：**返回新的一份进度，不改传进来的那一份**。
##
## 返回 `{"reward": int, "delta": int, "progress": Dictionary}`：
##   `reward` = 这一局**值多少**军资（军资公式的结果，结算页上那行"+N"）；
##   `delta`  = **实际到账**（重打只补差额；失败给 0）；
##   两者分开是有意的 —— 结算页要显示"这一局打了多少"，钱包只进 `delta`。
##
## `result`：`{win, grade, score, kills, named_kills, base, aces_down?}`
static func settle(progress: Dictionary, mission_id: String, result: Dictionary) -> Dictionary:
	var p: Dictionary = progress.duplicate(true)
	var reward := reward_for(result)
	var win := bool(result.get("win", false))
	var delta := 0

	if win and has_mission(mission_id):
		var has_best: bool = p["best_reward"].has(mission_id)
		var prev: int = int(p["best_reward"].get(mission_id, 0))
		delta = credit_delta(has_best, prev, reward)
		p["credits"] = maxi(int(p.get("credits", 0)) + delta, 0)
		p["cleared_mask"] = int(p.get("cleared_mask", 0)) | bit_of(mission_id)

		var score := float(result.get("score", 0.0))
		if not has_best or reward > prev:
			p["best_reward"][mission_id] = reward
		if not p["best_score"].has(mission_id) or score > float(p["best_score"][mission_id]):
			p["best_score"][mission_id] = score
		var grade := str(result.get("grade", MissionRating.NO_GRADE))
		# ⚠️ 失败（NO_GRADE）**不留成绩**：否则"最好成绩"会变成"打输过"。
		if grade != MissionRating.NO_GRADE and _grade_better(grade, str(p["best_grade"].get(mission_id, ""))):
			p["best_grade"][mission_id] = grade
		p["chapter"] = maxi(chapter_of(mission_id), 1)
	else:
		# 打输：不进钱、不点亮，但**图鉴"见过"照记**（见 §7.1：见过≠击坠）。
		pass

	for a: String in _str_list(result.get("aces_down", [])):
		if not p["aces_down"].has(a):
			p["aces_down"].append(a)
	for a2: String in _str_list(result.get("aces_seen", [])):
		if not p["aces_seen"].has(a2):
			p["aces_seen"].append(a2)
	return {"reward": reward, "delta": delta, "progress": p}


## 字母评价谁更好（`""` = 还没有成绩 ⇒ 任何字母都更好）。
static func _grade_better(a: String, b: String) -> bool:
	return _grade_rank(a) < _grade_rank(b)


static func _grade_rank(g: String) -> int:
	for i in MissionRating.GRADE_TABLE.size():
		if str(MissionRating.GRADE_TABLE[i]["grade"]) == g:
			return i
	return MissionRating.GRADE_TABLE.size() + 1


# ============================================================ 改装槽位（§6.4）
#
## 空挂载。
static func empty_loadout() -> Dictionary:
	return {"up": [], "down": []}


## 某台机体的挂载（**已经裁过**，可以直接用）。
static func loadout_of(progress: Dictionary, suit_id: int) -> Dictionary:
	var ups: Dictionary = progress.get("upgrades", {})
	return clamp_loadout(ups.get(_suit_key(suit_id), empty_loadout()))


## 剩下几个槽（`tier` 是 `"up"` / `"down"`）。
static func slots_left(loadout: Dictionary, tier: String) -> int:
	var cap := UPGRADE_SLOTS_UP if tier == "up" else UPGRADE_SLOTS_DOWN
	return maxi(cap - _str_list(loadout.get(tier, [])).size(), 0)


## 把一份挂载**裁进合法范围**。
##
## ⚠️ 这是"老存档 / 手改存档"的唯一防线：槽位上限、同一词条最多 2 份、空 id 丢掉。
## 没有它，一份写着 5 个下级件的存档会让 HUD 画出 5 个槽、或者让 `apply_upgrades()`
## 把同一个乘数叠 5 次 —— 而**没有任何一处报错**（数值只是"看起来生效了"）。
static func clamp_loadout(loadout: Dictionary) -> Dictionary:
	var out := empty_loadout()
	for tier: String in ["up", "down"]:
		var cap := UPGRADE_SLOTS_UP if tier == "up" else UPGRADE_SLOTS_DOWN
		var seen: Dictionary = {}
		var kept: Array = []
		for e: String in _str_list(loadout.get(tier, [])):
			if kept.size() >= cap:
				break
			var n: int = int(seen.get(e, 0))
			if n >= MAX_STACK_PER_ENTRY:
				continue
			seen[e] = n + 1
			kept.append(e)
		out[tier] = kept
	return out


static func _suit_key(suit_id: int) -> String:
	return "suit_%d" % suit_id


## 把任意"字符串序列"洗成 `Array[String]`（去空、去两端空格）。
##
## ⚠️ **必须同时认 `PackedStringArray`**：`String.split()` 返回的是 **`PackedStringArray`**，
## 而 `PackedStringArray` **不是** `Array`（`is Array` 为 false）。
## 早先这里只写了 `v is Array` ⇒ `_unpack_list()` 拿 `s.split("|")` 喂进来时
## **静默返回空数组**，于是 `aces_down` / `aces_seen` / `upgrades` 全部读回来是空的 ——
## 而值其实**正确落盘了**（`get_value` 也读得回）。一个类型判断，连带 6 条断言。
static func _str_list(v: Variant) -> Array:
	var out: Array = []
	if v == null:
		return out
	var src: Array = []
	if v is Array:
		src = v
	elif v is PackedStringArray:
		src = Array(v)
	else:
		return out
	for s: Variant in src:
		var t := str(s).strip_edges()
		if not t.is_empty():
			out.append(t)
	return out


# ============================================================ 存档（§6.6）
#
## 写档。返回 `Error`（`OK` = 写成功）。
##
## ⚠️ 用 `ConfigFile` 而不是 `JSON`：与 `Settings` 同一条路（`settings.gd:433`），
## 而且**手改得动**（排查"玩家卡在第三关"时能直接看文件）。
static func save_progress(progress: Dictionary, path := PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "cleared_mask", int(progress.get("cleared_mask", 0)))
	cfg.set_value("progress", "super_hard_notice_seen", bool(progress.get("super_hard_notice_seen",false)))
	# 逐关数组用 **CSV 字符串**而不是 Variant 数组：ConfigFile 存 Variant 数组是可行的，
	# 但导出的文本形态随类型变（`Array` / `PackedStringArray` 长得不一样），
	# 而这三条是**按下标对齐 `MASK_ORDER`** 的定长数组 —— 定长 + 定序用 CSV 最不容易出事。
	cfg.set_value("progress", "best_grade", _pack_grades(progress.get("best_grade", {})))
	cfg.set_value("progress", "best_score", _pack_floats(progress.get("best_score", {})))
	cfg.set_value("progress", "best_reward", _pack_ints(progress.get("best_reward", {})))
	cfg.set_value("progress", "aces_down", _pack_list(progress.get("aces_down", [])))
	cfg.set_value("progress", "aces_seen", _pack_list(progress.get("aces_seen", [])))
	cfg.set_value("progress", "chapter", maxi(int(progress.get("chapter", 1)), 1))
	cfg.set_value("wallet", "credits", maxi(int(progress.get("credits", 0)), 0))
	var ups: Dictionary = progress.get("upgrades", {})
	for k: String in ups.keys():
		var lo := clamp_loadout(ups[k])
		cfg.set_value("upgrades", "%s_up" % k, _pack_list(lo["up"]))
		cfg.set_value("upgrades", "%s_down" % k, _pack_list(lo["down"]))
	return cfg.save(path)


## 读档。**任何异常都退化成"空档"，绝不崩**（第一次运行 / 文件被删 / 半截文件）。
static func load_progress(path := PATH) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return new_progress()
	var p := new_progress()
	p["super_hard_notice_seen"]=bool(cfg.get_value("progress","super_hard_notice_seen",false))
	# ⚠️ 位掩码要**裁到 7 位**（★ 轮 56 起共 7 关）：老档里多出来的位会让
	# `cleared_count()` 数出 > 7，而"战役图上有 8 关"这种事是画不出来的、也说不清楚。
	#
	# ⚠️⚠️ **轮 56 的删关 + 顺位会让老档整体错位**：掩码与三条 CSV 都是**按
	# `MASK_ORDER` 下标对齐**的，而删掉的那一关（原 M04）恰好在中段 ⇒ 老档读回来是
	# 「新 M04 显示未通关、后面各关成绩整体串位」。本工程**没有版本号、也没有迁移代码**
	# （老板口径：直接删档重来）⇒ **本机 `user://campaign.cfg` 已在轮 56 一并删除**。
	p["cleared_mask"] = int(cfg.get_value("progress", "cleared_mask", 0)) \
		& ((1 << MASK_ORDER.size()) - 1)
	p["best_grade"] = _unpack_grades(str(cfg.get_value("progress", "best_grade", "")))
	p["best_score"] = _unpack_floats(str(cfg.get_value("progress", "best_score", "")))
	p["best_reward"] = _unpack_ints(str(cfg.get_value("progress", "best_reward", "")))
	p["aces_down"] = _unpack_list(cfg.get_value("progress", "aces_down", ""))
	p["aces_seen"] = _unpack_list(cfg.get_value("progress", "aces_seen", ""))
	p["credits"] = maxi(int(cfg.get_value("wallet", "credits", 0)), 0)
	p["chapter"] = clampi(int(cfg.get_value("progress", "chapter", 1)), 1, CHAPTERS.size())
	var ups: Dictionary = {}
	# ⚠️ 只遍历**存档里真的有的**那几台机体（`get_section_keys`），不遍历 `SuitProfile.Id` ——
	# 后者要依赖"枚举能不能当字典迭代"这件事，而本工程此前没有任何先例。
	# 顺带也省掉"给六台没改过的机体各建一个空挂载"。
	# ⚠️ 先问 `has_section()`：一份**没有任何改装**的档里不会写出 `[upgrades]` 段，
	# 直接 `get_section_keys("upgrades")` 会每次打印一条
	# `Cannot get keys from nonexistent section`（配置没错，但刷屏会淹掉真错）。
	var suites: Dictionary = {}
	if cfg.has_section("upgrades"):
		for k: String in cfg.get_section_keys("upgrades"):
			if k.ends_with("_up"):
				suites[k.substr(0, k.length() - 3)] = true
			elif k.ends_with("_down"):
				suites[k.substr(0, k.length() - 5)] = true
	for key: String in suites.keys():
		var up := _unpack_list(cfg.get_value("upgrades", "%s_up" % key, ""))
		var down := _unpack_list(cfg.get_value("upgrades", "%s_down" % key, ""))
		if up.is_empty() and down.is_empty():
			continue
		ups[key] = clamp_loadout({"up": up, "down": down})
	p["upgrades"] = ups
	return p


## 删档（新游戏 / 调试）。**只删自己那一个文件**。
static func erase(path := PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ---- CSV 编解码（纯函数，逐点可验）----

static func _pack_grades(d: Dictionary) -> String:
	var out: Array = []
	for id: String in MASK_ORDER:
		out.append(str(d.get(id, "-")))
	return ",".join(out)


static func _unpack_grades(csv: String) -> Dictionary:
	var d: Dictionary = {}
	var parts := csv.split(",")
	for i in mini(parts.size(), MASK_ORDER.size()):
		var g := str(parts[i]).strip_edges()
		# ⚠️ 只收 `GRADE_TABLE` 里真的有的字母。否则一份写着 `M01=Z` 的手改档
		# 会带着"Z"一路走进结算页与图鉴 —— 而画不出 Z 的 UI 不会报错，只会画成空白。
		if _is_known_grade(g):
			d[str(MASK_ORDER[i])] = g
	return d


## 是不是一个**认识**的评价字母。
##
## ⚠️ 从 `MissionRating.GRADE_TABLE` 现推，不另抄一份字面量：
## 将来表里加了 `SS`，这里自动就认了（抄一份必然忘记同步）。
static func _is_known_grade(g: String) -> bool:
	if g.is_empty() or g == "-":
		return false
	for row: Dictionary in MissionRating.GRADE_TABLE:
		if str(row.get("grade", "")) == g:
			return true
	return false


static func _pack_floats(d: Dictionary) -> String:
	var out: Array = []
	for id: String in MASK_ORDER:
		out.append("%.4f" % float(d.get(id, -1.0)))
	return ",".join(out)


static func _unpack_floats(csv: String) -> Dictionary:
	var d: Dictionary = {}
	var parts := csv.split(",")
	for i in mini(parts.size(), MASK_ORDER.size()):
		var t := str(parts[i]).strip_edges()
		if t.is_empty() or not t.is_valid_float():
			continue
		var v := t.to_float()
		if v >= 0.0:
			d[str(MASK_ORDER[i])] = v
	return d


static func _pack_ints(d: Dictionary) -> String:
	var out: Array = []
	for id: String in MASK_ORDER:
		out.append(str(int(d.get(id, -1))))
	return ",".join(out)


static func _unpack_ints(csv: String) -> Dictionary:
	var d: Dictionary = {}
	var parts := csv.split(",")
	for i in mini(parts.size(), MASK_ORDER.size()):
		var t := str(parts[i]).strip_edges()
		if t.is_empty() or not t.is_valid_int():
			continue
		var v := t.to_int()
		if v >= 0:
			d[str(MASK_ORDER[i])] = v
	return d


## 字符串列表（`aces_down` 这类）用 `|` 分隔 —— 命名王牌的 id 里可能出现 `_` 与 `-`，
## 用逗号会和"CSV"这个用途撞在一起，用竖线最不容易出错。
static func _pack_list(v: Variant) -> String:
	return "|".join(_str_list(v))


static func _unpack_list(v: Variant) -> Array:
	if v is Array or v is PackedStringArray:
		return _str_list(v)
	var s := str(v)
	if s.strip_edges().is_empty():
		return []
	return _str_list(s.split("|"))


static func super_hard_unlocked(progress:Dictionary)->bool:
	var complete_mask: int=(1<<MASK_ORDER.size())-1
	return (int(progress.get("cleared_mask",0)) & complete_mask)==complete_mask

static func path_for_difficulty(normal_path:String,level:int)->String:
	if level != Difficulty.Level.SUPER_HARD:return normal_path
	var ext:=normal_path.get_extension()
	return normal_path.get_basename()+"_super_hard"+("."+ext if ext!="" else "")
