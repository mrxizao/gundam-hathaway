extends RefCounted
## 战役播片的**片目表**（DESIGN §7.5.4）。
##
## ## 与 `IntroPlaylist` 的关系：**两条管线，共用一台播放器**
## | 件 | 管什么 | 动不动 |
## |---|---|---|
## | `IntroPlaylist` + `should_play_now()` | **进游戏时的开场动画**（随机抽一支，80/20） | ⚠️ **一个字都不改** |
## | **本表** | **战役内的四槽位播片**（P / B / M / D） | 新表 |
## | `IntroMovie` | 上面两条共用它播 | 只加方法，不改现有行为 |
##
## ★ **本表刻意没有 `weight`** —— 开场那条管线是"随机抽一支"，而战役播片**必须确定**：
## 序章必播豪泽恩号、且只播一次；`mid` 槽更是**按 `id` 点名**触发（`Trigger` 的
## `cutscene:<id>`）。随机会让"第一关之前看到什么"不可复现。
## ⇒ 顺序语义归 `Mission` 数据，**不归 roll**（DESIGN §7.5.4）。
##
## ## ⚠️ 素材不在版本控制里 ⇒ **表可以是空的**
## 老板给的原剧切片还没到。设计要求「**代码必须能在"一支片都没有"的仓库里跑完整条战役**」
## （§7.5.5）⇒ 四条槽位全部**静默跳过**，战役照常推进。**素材是可选依赖。**
## 本文件因此把"取片"做成可注入 `clips` 的纯函数：空表能验"缺片返回 null"，
## 测试注入一张临时表就能验正向（唯一性 / 一槽一支）。
##
## ## 落地轮次：轮 C 只**留钩子**
## 本文件在轮 C 建出**最小正确版**（表 + 取片 + 素材门），流程的 P / B / D 三处接上；
## 完整的四槽位（含 `mid` 的战斗中暂停播片）是**轮 G**。


## 一支片。字段与 DESIGN §7.5.4 的 `Cutscene` 一一对应。
class Cutscene extends RefCounted:
	## `"m04_brief"` / `"m05_brief_01"` —— 全局唯一（`validate()` 钉着）。
	var id := ""
	## `res://assets/video/xxx.ogv`。
	## ⚠️ Godot 核心**只认 Ogg Theora（`.ogv`）**；老板给的 mp4 要先转码
	## （`assets/video/` 里已有这么转过的先例）。
	var path := ""
	## `"prologue"` / `"brief"` / `"mid"` / `"debrief"`。
	var slot := "brief"
	## 属于哪一关（`"M04"`）。**序章为 `""`** —— 它不属于任何一关。
	var mission := ""
	## 「Ξ 穿过导弹雨」—— 给调试与图鉴用，不上面。
	var label := ""
	## 对话类可跳；关键演出可设 false。**本版没有不可跳的**。
	var skippable := true

	func _init(cid := "", cpath := "", cslot := "brief", cmission := "",
			clabel := "", cskip := true) -> void:
		id = cid
		path = cpath
		slot = cslot
		mission = cmission
		label = clabel
		skippable = cskip

	## 素材**真的在**（表里写了、文件却不在 ⇒ 这一支要跳过，不是崩）。
	func available() -> bool:
		return not path.is_empty() and ResourceLoader.exists(path)

	## 这一支在**哪一关**的哪个槽（给日志与断言用）。
	func slot_key() -> String:
		return "%s/%s" % [mission if not mission.is_empty() else "-", slot]


## 四个槽位（DESIGN §7.5.1）。**顺序有意义**：它就是"一关之内播片的先后"。
##
## | 槽位 | 何时播 | 战斗状态 | 支数 |
## |---|---|---|---|
## | `prologue` | 第一次进战役、简报之前 | 无战斗 | 全局 1 |
## | `brief` | 简报之后、出击之前 | 无战斗 | 每关 0–1 |
## | `mid` | **战斗中途**，由 `Trigger` 触发 | ★ 暂停战斗 | 每关 0–N |
## | `debrief` | 结算之后 | 无战斗 | 每关 0–1 |
const SLOTS := ["prologue", "brief", "mid", "debrief"]

## 槽位的中文名（给日志 / 调试页；**不**做 UI 文案的真源）。
const SLOT_LABELS := {
	"prologue": "序章",
	"brief": "任务前",
	"mid": "任务中",
	"debrief": "任务后",
}

## 一个槽位最多几支。`mid` 是 `-1` = 不限（按 id 点名）。
const SLOT_MAX := {"prologue": 1, "brief": 1, "debrief": 1, "mid": -1}

## ★ **片目表本体。目前为空** —— 理由见文件头（素材不在版本控制里，表可以空着跑）。
##
## 加片子时照这个形状加一项即可（**顺序无语义**，取片按 `id` / `mission+slot` 查）：
##
## ```gdscript
## const CLIPS := [
##     Cutscene.new("prologue_haozene", "res://assets/video/prologue_haozene.ogv",
##         "prologue", "", "豪泽恩号劫机"),
##     Cutscene.new("m04_brief", "res://assets/video/m04_brief.ogv",
##         "brief", "M04", "Ξ 穿进导弹雨"),
##     Cutscene.new("m04_mid_01", "res://assets/video/m04_mid_01.ogv",
##         "mid", "M04", "加乌曼的座舱"),
## ]
## ```
## ⚠️ 上面这段是**注释**，不是代码 —— 别把示例抄进 `const` 里当作"已经有片了"。
const CLIPS: Array = []


## 表里的全部片目（**只读副本语义**：调用方拿到的是一份浅拷贝的数组，改不动本表）。
static func all(clips: Array = CLIPS) -> Array:
	var out: Array = []
	out.append_array(clips)
	return out


static func count(clips: Array = CLIPS) -> int:
	return clips.size()


## 按 `id` 取片。**全局唯一**（重复由 `validate()` 抓），取不到 ⇒ **null**（不崩）。
##
## ⚠️ 返回 null 是**正常路径**，不是错误：素材没到、老板少给一支，
## 都表现为"这个槽位跳过"，而战役照常推进（§7.5.5）。
static func by_id(cid: String, clips: Array = CLIPS) -> Cutscene:
	if cid.is_empty():
		return null
	for c: Cutscene in clips:
		if c.id == cid:
			return c
	return null


## 按「哪一关 + 哪个槽位」取片。**一槽一支**（`mid` 除外，它按 id 点名）。
##
## `mission_id` 传 `""` = 序章那条全局槽（`prologue`）。
static func by_slot(mission_id: String, slot: String, clips: Array = CLIPS) -> Cutscene:
	for c: Cutscene in clips:
		if c.slot == slot and c.mission == mission_id:
			return c
	return null


## 某一关在某个槽位上的**全部**片（`mid` 会是多支；其余槽位至多 1 支 —— 由 `validate()` 钉）。
static func all_in_slot(mission_id: String, slot: String, clips: Array = CLIPS) -> Array:
	var out: Array = []
	for c: Cutscene in clips:
		if c.slot == slot and c.mission == mission_id:
			out.append(c)
	return out


## 这一关有几支片（四个槽位合计）。给"本关有没有播片"的判断与调试页用。
static func count_of(mission_id: String, clips: Array = CLIPS) -> int:
	var n := 0
	for c: Cutscene in clips:
		if c.mission == mission_id:
			n += 1
	return n


## **素材门**：表里至少有**一支**片的文件真的在。
##
## ⚠️ 与 `IntroPlaylist.has_any_clip()` 同款、互不影响：那个管开场，这个管战役。
## 空表 ⇒ false ⇒ P / B / D 三处**一处都不起播**（这就是"一支片都没有也能跑通"）。
static func has_any(clips: Array = CLIPS) -> bool:
	for c: Cutscene in clips:
		if c.available():
			return true
	return false


## 表自检：返回 `""` = 合规，否则返回**第一条**问题（中文，直接可读）。
##
## 钉四条不变量（`suite_sally` 逐条验，**注入样本表**而不是靠人肉看 CLIPS）：
##   ① `id` 非空且**全局唯一**（`Trigger` 的 `cutscene:<id>` 靠它点名）；
##   ② `slot` 必须在 `SLOTS` 里；
##   ③ **一个槽位一支**（`prologue` / `brief` / `debrief`），`mid` 不限；
##   ④ `prologue` 的 `mission` 必须是 `""`（它是全局的，不属于任何一关）。
##
## ⚠️ **不检查"文件在不在"** —— 素材是可选依赖（缺片=跳过，不是表写错了）。
static func validate(clips: Array = CLIPS) -> String:
	var seen: Dictionary = {}
	var per_slot: Dictionary = {}
	for c: Cutscene in clips:
		if c.id.is_empty():
			return "有片目的 id 是空的"
		if seen.has(c.id):
			return "片目 id 重复：%s" % c.id
		seen[c.id] = true
		if not SLOTS.has(c.slot):
			return "片目 %s 的 slot 非法：%s" % [c.id, c.slot]
		if c.slot == "prologue" and not c.mission.is_empty():
			return "序章片 %s 不该属于某一关（mission 应为空）" % c.id
		if c.slot != "prologue" and c.mission.is_empty():
			return "片目 %s 是 %s 槽，必须写明属于哪一关" % [c.id, c.slot]
		var maxn := int(SLOT_MAX.get(c.slot, 1))
		if maxn > 0:
			var k := "%s/%s" % [c.mission, c.slot]
			per_slot[k] = int(per_slot.get(k, 0)) + 1
			if int(per_slot[k]) > maxn:
				return "槽位 %s 超过上限（%d 支）：%s" % [k, maxn, c.id]
	return ""
