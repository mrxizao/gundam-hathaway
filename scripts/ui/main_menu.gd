class_name MainMenu
extends Control
const HOME_VIEW := preload("res://scripts/ui/menu_home.gd")
const MENU_VISUALS := preload("res://scripts/ui/menu_visuals.gd")
const TEXT_TILT_SHADER := preload("res://shaders/menu_text_tilt.gdshader")
## 开局前的主菜单：**选模式（对战 / 训练）→ 选机体 → 选难度 → 选地图**。
##
## 1.1 重排：三台可选机体（柯西 / 佩涅罗佩 / 阿利宙斯）、两张对战地图
## （太平洋群岛 / 艾尔斯岩）、外加一个训练模式。
##   - **对战模式**：机体 → 难度 → 地图 → 出击（1v1）
##   - **训练模式**：机体 → 出击（直接落在靶场，四个步骤里跳过难度与地图 ——
##     靶机不还手，"敌机难度"没有意义；靶场是训练专用图，也不给选）
##
## 游戏固定夜战（三张图都是夜，只是雾与云的颜色不同），所以没有"选时段"这一步。
##
## 和 HUD 一样是纯 `_draw()` 画出来的，没有 .tscn、没有贴图、没有 Label 节点。
## 页面底部常驻**操作说明**（数据来自 InputSetup.HELP_SECTIONS，和游戏内的
## 右下角键位提示共用同一份，改键位不会两处对不上）。

signal start_match(suit_id: int, difficulty_level: int, map_id: int, mode: int, enemy_suit_id: int)

## 菜单的页。
##   `BATTLE`   = **「对战模式」子页**（本轮）：选 王牌战 / 小队战。
##   `SIDE`     = 小队战 / 联机专用（选择阵营）；
##   `TRAINING` = **训练模式专用**（1.2 第二十五轮）：用户要求
##                「新手教学**和靶场在同一页面**」 —— 所以这一页**同时列出**
##                「自由打靶」与「新手教学」两项，而不是再开一个模式。
##
##   `PASSWORD` = **密码页**（2026-09-30）：设置页最底下那个**隐形行**按 Enter 进来的。
##                输对了才开制作人模式（`Game.producer_mode`）。它**不在步骤条上**
##                （`step_labels()` 不认它），也不在任何"玩家会走到"的链路上 ——
##                唯一的入口是那一行（见 `setting_row_hidden()`）。
##
##   `ENDLESS`  = ★63-24 **无限强化演习的开局配置页**：从基础卡池里**自选 3 张**
##                （设计 §5.6 / R14）。**勾满 3 张之前确认键不响应** ——
##                不默认帮玩家随机填满，否则"自选"这件事名存实亡。
##
## ⚠️ 新成员**追加在末尾**（`PASSWORD` 之后 ⇒ `ENDLESS = 15`），不许插中间：
## `Stage` 的值被到处 `match` / 比较，`PASSWORD` 那一段还专门写过"它不在步骤条上"，
## 插一个进去会让 `PASSWORD` 不再是最末位那个"特殊页"。
enum Stage { MODE, BATTLE, SIDE, SUIT, TRAINING, ENEMY, DIFFICULTY, MAP, ENCOUNTER, LAN, SETTINGS, KEYS, BGM, FPV_CONFIRM, PASSWORD, ENDLESS }

## 导航轴：`X` = 横（A / D），`Y` = 竖（W / S）。
enum Nav { NONE, X, Y }

## 某一页用哪个轴导航。
##
## ⚠️ 这张表存在的唯一理由：**版式的轴和输入的轴必须是同一个**。
## 用户实测报过一个真 bug ——「这个位置明明是上下选的但是只能用 a 或 d」：
## 敌人页画的是 `map_row_rect()` 的**竖排行**，输入却走了 `_nav_x()`。
## 更早一次同源 bug 是 `_nav_x()` 和 `_nav_y()` **都**认 Q / E，
## 于是「按一下不知道会跳到哪」—— 修法就是把两个轴严格分开。
##
## 轴**不能散落在 `_read_input()` 的每个分支里**：那样加一页就会漏一处
## （敌人页就是这么漏掉的）。写在这里当数据 —— 输入查表，测试也查同一张表。
##
## 判据是**版式**，不是页面语义：全工程唯一横排的是机体页的卡片
## （`suit_card_rects()` 的 x 递增），其余每一页都是
## `PANEL_TOP + i * (行高 + 行距)` 的竖排行（`mode_row_rect` / `map_row_rect` /
## `difficulty_row_rect`），所以全部走竖轴。
static func nav_axis(s: int) -> int:
	match s:
		Stage.SUIT:
			return Nav.X
		# ⚠️ **阵营页原来是 `Nav.X`，那是错的（2026-09-21 用户："选阵营的时候按键还是乱的"）。**
		#
		# 写这条的人以为阵营页是横向两栏（注释原文："只有两项，横向排"），
		# 但 `_draw_side_stage()` 从落地第一天起画的就是**竖排行**：
		# `PANEL_TOP + float(i) * (ROW_H + ROW_GAP)`，两行上下叠。
		# 于是版式与轴相反 —— 玩家按 W / S 没反应、按 A / D 才动，
		# 而页脚提示还理直气壮地印着"A / D 选择阵营"。
		#
		# 这正是本函数开头警告过的那种事故（敌人页同款），只是方向反了。
		# **修法是让轴跟着版式走，而不是把版式改成横排**：阵营行里有一块徽记方格 +
		# 名字 + "可出击机体：…" + 编制一行，竖排是唯一排得下的方向。
		# 训练项目页（1.2 第二十五轮）：两项「自由打靶 / 新手教学」，**竖排**
		#（照 `map_row_rect()` 的行）⇒ 轴必须是 `Nav.Y`。
		# ⚠️ 别照抄阵营页那段教训的反面：那里是"版式竖排却给了横轴"，
		# 这里是新页，**先定版式（竖排）再定轴（Y）**，两者一致。
		# ★63-24：演习的开局配置页画的是**竖排的卡行**（照 `map_row_rect()` 那一族），
		# 所以轴是 `Nav.Y`。⚠️ 这一条同样是"**先定版式、再定轴**"：
		# `_draw_endless_stage()` 与 `_list_geometry()` 都是 `PANEL_TOP + i * (行高 + 行距)`，
		# 上下移动焦点的键必须是 W / S。判据在 `suite_menu_groups` 的轴分节。
		Stage.TRAINING, Stage.SIDE, Stage.MODE, Stage.ENEMY, Stage.ENCOUNTER, \
		Stage.DIFFICULTY, Stage.MAP, Stage.LAN, Stage.SETTINGS, Stage.KEYS, Stage.BGM, \
		Stage.BATTLE, Stage.FPV_CONFIRM, Stage.ENDLESS:
			return Nav.Y
		# ⚠️ 密码页**没有导航轴**（`Nav.NONE`）：它是**打字**的一页，
		# 上下左右一个都不该动（按了就"光标跑到别处"是最难解释的一种手感）。
		# 显式写出来而不是靠"落到函数末尾" —— 靠兜底的话，将来有人把默认值
		# 改成 `Nav.Y`（"新页大概都要上下选"）就会静默地给这一页装上导航。
		Stage.PASSWORD:
			return Nav.NONE
	return Nav.NONE

## 顶层模式页的行。**一个分组 = 一次"选模式"点击**。
##
## 顺序即显示顺序。五项：**对战模式 / 剧情挑战 / 强化演习 / 训练模式 / 局域网联机**。
##
## ★63-24 新增第 5 组「强化演习」：位置**跟在剧情挑战之后** ——
## 判据用的是本段末尾那条规矩（**按玩法主次排，不按 1.1 平铺表的相对位置排**）：
## 它是一个**完整的主玩法单机模式**（波次无限 + 局内选卡 + 被击坠终止），
## 与剧情挑战同属"单人 · 真内容"那一档；而训练模式是**练习用的旁支**（注释原文），
## 联机是另一个轴（PvP）。⇒ 主玩法三个连着，旁支与联机留在后面。
## ⚠️ 这是**产品口味**上的一次拍板（设计 §11.1 只写了"新增第 5 组"、没说排哪儿）。
##    要挪位置只需改这张表 —— 表是顺序的**唯一真源**，`modes_breadcrumb()` 会跟着走。
##
## ## 为什么"对战模式"是一个分组（2026-09-29 上轮）
## 老板：「把**王牌战和小队战整合到一个对战模式的小菜单中**」。原来这两项是**并列**在
## 模式页上的两行，各自顶着"模式"的名分，看起来像两种互不相干的玩法；
## 实际上它们是同一个位置下的**两种形式**（1v1 单挑 / 阵营编队），
## 差别只在"这一局有多少台机、谁开哪台"。
##
## ⚠️ 两者依旧是**两个 `Game.MatchMode`**（`VERSUS` / `SQUAD`，一个字都没改）——
## 变的只是**入口的层数**。所以 `step_labels()` / `spawn_versus()` / `spawn_squad()`
## 那一整条链一个字都不用动，`Game.match_mode` 的值也照旧。
##
## ## 单项分组不再多按一次
## 剧情挑战只有一种玩法、训练模式只有一个项目、联机的形式在联机页里选
## ⇒ 它们的分组只有一项，按下去**直接进下一页**（不弹一个只有一行的子菜单）。
## 于是"要不要子菜单"这件事只由**数据**决定：`modes.size() > 1`。
##
## ## 剧情挑战（`CHALLENGE`）：1.2 隐藏 → 2026-09-29 恢复入口 → **轮 C 换成剧情模式**
## 它在 1.2 版第二十轮被从入口**隐藏**（README §22.1），做法就是把它从这张表里去掉 ——
## **功能一件都没删**（`ChallengeScript`、遭遇页 `Stage.ENCOUNTER`、
## `_draw_encounter_stage()`、`spawn_challenge()`、波次与结算逻辑，以及第二十轮那一整套
## 测试全部原样保留），所以"藏起来"从来是**一个数据项**，恢复也只是把它加回来：
## 链路（`challenge_mode()` → `Stage.ENCOUNTER` → `Stage.DIFFICULTY` → `_launch()`）
## 在这段注释还写着"不在表里"的时候就一直是通的。
##
## 恢复的时机：剧情模式的数据层已经就位 —— 轮 0 的进度存档（`CampaignScript`）、
## 轮 A 的 `MissionScript` / 7 关数据、轮 B 的 4 场 `Encounter` ⇄ `Mission` 迁移。
##
## ★ **2026-09-29（轮 C）：入口不再走旧向导。** 老板原话：「现在剧情模式的入口还是之前版本的。」
## 病因就是上面那条链路 —— 它把玩家送进**旧挑战的 4 页向导**（机体 / 遭遇 / 难度），
## 而那三页里**有两页的选择在剧情模式下完全不作数**：
##   - 机体页选的那台机 → 被 `Mission.player_suit` 覆盖（§9.5 的 POV 就是这么演的）；
##   - 遭遇页选的那 4 场（`ChallengeScript.for_suit()`）→ 被战役图上选的那一关覆盖。
## ⇒ 现在它**只有一步**（`step_labels()` 返回 `["① 选择模式"]`），按下去直接 `_launch()`，
##    由 `main._begin_match_loading()` 拦到**战役图**（§6.1 的循环前门）。
## **选关与难度都在战役图上** —— 所以这不是"砍功能"，是把那两个决定搬到了它们该在的页面。
## ⚠️ `Stage.ENCOUNTER` / `_draw_encounter_stage()` **一行都没删**（还有别的调用点与测试钉着它），
##    它只是**剧情模式不再经过**它。判据在 `suite_round`：剧情模式的可达页只有 `Stage.MODE`。
##
## ⚠️ **它自成一组**，不与"对战模式"合并：挑战是**单人 · 剧情向**玩法
##（"还原剧情"的固定对手与波次），不是"对战"的第三种形式 ——
## 塞进对战模式子页会让"选形式"那一步冒出一个**不是形式**的选项
##（子页那一行的名字就叫「对战模式」，可站在那里选剧情挑战是说不通的）。
##
## ⚠️ 位置在**第二位**（对战模式之后、训练模式之前）：2026-10-01 老板要求
## 「剧情挑战放到第二位，训练模式放到第三位」—— 主玩法（战役）往上提一格，
## 训练是练习用的旁支，跟在它后面更顺。
## ⚠️ 这次**推翻了** 2026-09-29 那次「照 1.1 平铺表的相对位置排」（那时训练在前、
## 挑战在后，见 README §22.9）。顺序从此按**玩法主次**定，不再去翻那份老表。
##
## ⚠️ 它是**单项分组**，而且这一组是**唯一**一个"按下去就出击"的
##（判据是 `selected_mode() == CHALLENGE`，见 `Stage.MODE` 的确认分支）。
const MODE_GROUPS := [
	{"name": "对战模式", "modes": [Game.MatchMode.VERSUS, Game.MatchMode.SQUAD],
		"lines": ["王牌战（1v1 单挑）· 小队战（阵营编队）",
			"进去先选形式，再选机体 / 难度 / 地图"]},
	{"name": "剧情挑战", "modes": [Game.MatchMode.CHALLENGE], "lines": []},
	{"name": ENDLESS_TITLE, "modes": [Game.MatchMode.ENDLESS], "lines": []},
	{"name": "训练模式", "modes": [Game.MatchMode.TRAINING], "lines": []},
	{"name": "局域网联机", "modes": [Game.MatchMode.LAN], "lines": []},
]

## 「对战模式」在 `MODE_GROUPS` 里的下标 —— 唯一有子页的那一组。
const BATTLE_GROUP := 0


## 菜单里**全部**模式（按显示顺序摊平）。
##
## ⚠️ 它回答的是"**允许哪些模式**"，**不是**"模式页有几行" ——
## 后者是 `MODE_GROUPS.size()`（**5 组**）。分组之前这两件事恰好是同一个数
##（`MODES.size()`），现在必须分开：把 `all_modes().size()`（**6**）当行数用，
## 排版就会按 6 行去算 5 行，最后一行凭空伸到面板外面。
## ★63-24 又加了一组「强化演习」⇒ 这两个数**再次同时变大、依旧不相等**
##（5 组 / 6 个模式）—— 这正是本函数存在的意义：**永远别把它们当成一个数**。
static func all_modes() -> Array:
	var out: Array = []
	for g: Dictionary in MODE_GROUPS:
		out.append_array(g["modes"])
	return out


## 「对战模式」子页的两项：**王牌战 / 小队战**。
##
## 它是**唯一**有子页的分组（训练只有一个项目、剧情挑战只有一种玩法；
## 联机的形式在联机页里选，
## 因为它和"主机 / 加入"是同一次决定）。
static func battle_modes() -> Array:
	return MODE_GROUPS[BATTLE_GROUP]["modes"]


## 模式页标题带下面那行面包屑 —— **从 `MODE_GROUPS` 现推**。
##
## ⚠️ 它以前是**写死的一个字符串**，于是"恢复剧情挑战入口"之后
## **图上还是三项**（模式页已经是四行）—— 而且**不报错**，只有人眼能看出来。
## 这类"菜单多了一行、面包屑没跟上"的漏法正是本工程最怕的形状：
## 同一个事实有两份写法，改了一份另一份不动。现在它只有一份真源。
##
## 格式：有子页的那一组把形式列在括号里（`对战模式（王牌战 / 小队战）`），
## 单项分组直接用那一组的名字 —— 而单项分组的名字本来就借自 `mode_info()`
## （见 `group_info()`），所以这里也不会出现第二种说法。
static func modes_breadcrumb() -> String:
	var parts: Array = []
	for i in MODE_GROUPS.size():
		var ms: Array = MODE_GROUPS[i]["modes"]
		if ms.size() <= 1:
			parts.append(str(group_info(i)["name"]))
			continue
		var subs: Array = []
		for mode: Variant in ms:
			subs.append(str(mode_info(int(mode))["name"]))
		parts.append("%s（%s）" % [str(MODE_GROUPS[i]["name"]), " / ".join(subs)])
	return " · ".join(parts)


## 顶层模式页某一行要显示的名字与说明。
##
## ⚠️ **单项分组直接借 `mode_info()` 那两行**：那一页上的"训练模式"必须是
## 训练模式自己的文案（"靶场打靶 · 靶机不还手"……），在这里再写一份就会有两份说法，
## 改了一处另一处不动 —— 那正是本工程反复出问题的形状。
static func group_info(i: int) -> Dictionary:
	var g: Dictionary = MODE_GROUPS[clampi(i, 0, MODE_GROUPS.size() - 1)]
	var ms: Array = g["modes"]
	if ms.size() == 1:
		var info := mode_info(int(ms[0]))
		return {"name": str(info["name"]), "lines": info["lines"], "mode": int(ms[0])}
	return {"name": str(g["name"]), "lines": g.get("lines", []), "mode": int(ms[0])}
## 玩家可选的机体。**三台 ACE**（第二十二轮下半起）。
##
## ## 第二十二轮下半：量产机从这里撤掉了
## 用户原话：「把**王牌机对战**里面的古斯塔夫和梅萨都移除，**敌人选择**里面的也一样」，
## 随后补了一句：「**小队作战里面的保留**」。
##
## 撤掉的是**"可选"**，不是"删除机体" —— 两台量产机仍然活在工程里：
##   - **编队战**（小队作战）的编制表 BattleFormation 里它们是主力：
##     马夫蒂 = 梅萨M01，联邦·喀耳刻部队 = 古斯塔夫00。**这条明确要保留**；
##   - **剧情挑战**的波次里有古斯塔夫00；
##   - **训练模式**的四架靶机仍是古斯塔夫00（不还手的那份 gustav00()）。
##
## 所以这两张表管的是"**1v1 / 王牌机对战里能挑谁**"，
## 而量产机的位置是"编队里的杂兵"，不该出现在单挑菜单里。
## ⚠️ 判据同时钉住了两面：`suite_round17::_wiring()` 既断言这里**没有**量产机，
## 也断言编队战编制表里**有**量产机 —— 少钉一面就会有人"顺手统一"掉另一半。

const SUITS := [SuitProfile.Id.XI, SuitProfile.Id.XI_FINAL, SuitProfile.Id.PENELOPE, SuitProfile.Id.ZORIN_SOUL, SuitProfile.Id.ARIZEUS, SuitProfile.Id.REGZ_CUSTOM, SuitProfile.Id.NU_GUNDAM, SuitProfile.Id.SAZABI, SuitProfile.Id.GP03D, SuitProfile.Id.NEUE_ZIEL, SuitProfile.Id.FULL_ARMOR_TB, SuitProfile.Id.PSYCHO_ZAKU_TB]

## 对手卡片的排序基表；实际候选仍按阵营及专属对决规则筛选。
const ENEMY_SUITS := [SuitProfile.Id.XI, SuitProfile.Id.XI_FINAL, SuitProfile.Id.PENELOPE, SuitProfile.Id.ZORIN_SOUL, SuitProfile.Id.ARIZEUS, SuitProfile.Id.REGZ_CUSTOM, SuitProfile.Id.NU_GUNDAM, SuitProfile.Id.SAZABI, SuitProfile.Id.GP03D, SuitProfile.Id.NEUE_ZIEL]

## **这一边能选的机体**。
##
## ⚠️ 三类模式要走**同一个**按阵营过滤的入口（第二十二轮下半：联机也选阵营）：
##   - **编队战**：阵营决定能开哪些机（马夫蒂 2 台 / 联邦 3 台）；
##   - **联机**：用户的规则里"同一阵营"是**同乘的前提之一**，
##     所以联机也先选阵营、机体页按阵营列（**含量产机** —— 同乘要求两人都选量产机）；
##   - 其余（1v1 / 挑战 / 训练）：仍是那三台 ACE 的固定表。
##
## 用一个函数收口，是为了让"能不能选跨阵营的机体"只有一个答案 ——
## 跨阵营的选择会让 `LanPlan` 的同队判定直接失效（那正是同乘规则自相矛盾的来源）。
func suits_for_side(side: int) -> Array:
	return BattleFormation.roster_of(side).all_suits()


## 本模式要不要按阵营过滤机体表。
func side_filters_suits() -> bool:
	return squad_mode() or (lan_mode() and selected_lan_form() == LanPlan.Form.SQUAD)


## 当前这一页在列的机体（编队战/联机看阵营，其余看 `SUITS`）。
func active_suit_list() -> Array:
	if side_filters_suits():
		return suits_for_side(side_index_to_side())
	return SUITS if selected_mode() in [Game.MatchMode.VERSUS,Game.MatchMode.ENDLESS] or lan_mode() else [SuitProfile.Id.XI, SuitProfile.Id.XI_FINAL, SuitProfile.Id.SAZABI, SuitProfile.Id.REGZ_CUSTOM, SuitProfile.Id.NU_GUNDAM, SuitProfile.Id.PENELOPE, SuitProfile.Id.ARIZEUS]


## 菜单里的阵营下标（0 = 马夫蒂 / 1 = 联邦）→ `BattleFormation.Side`。
func side_choices() -> Array[int]:
	# LAN formation assumes two factions with MP squads; keep those existing choices.
	return [BattleFormation.Side.MAFTY,BattleFormation.Side.FEDERATION]

func side_index_to_side() -> int:
	var choices := side_choices()
	return choices[clampi(side_index,0,choices.size()-1)]


## 这一局是不是编队战。
func squad_mode() -> bool:
	return selected_mode() == Game.MatchMode.SQUAD
const LEVELS := [Difficulty.Level.EASY, Difficulty.Level.NORMAL, Difficulty.Level.HARD]

## 设置页的行。顺序即显示顺序。
## "value" 只用于占位，真正显示的文字在 `_setting_value_text()` 里按类型算。
##
## 镜头三行是第十四轮 A4（玩家实测："画面一直在晃"、"我不是特别晕 3d，
## 但玩这个还是有点难受"）。**它们必须是设置项而不是我去改常数**：
## `chase_camera.roll_blend` 的 0.62 是当年调过的取舍（见那个文件的注释），
## 再拧一次只是把眩晕推给另一批人，做成可调才是真解决。
##
## ★ **跨文件引用走 `preload`，不走 `class_name`**（本仓库的统一纪律，理由见
## `campaign.gd` 开头那段）：新加的 `class_name` 只有编辑器重新扫过之后才进
## `.godot/global_script_class_cache.cfg`，而 `--headless` 跑测试时没人去刷那份缓存
## ⇒ 那样写会当场 `Identifier not found`。`producer.gd` 是给这个隐藏入口用的，
## 所以它**没有 `class_name`**、只从这条 `preload` 进来。
const PROD := preload("res://scripts/data/producer.gd")

## 隐形行（制作人模式那一行）的 key。
##
## ⚠️ 它**必须定义在 `SETTING_ROWS` 之前**（常量只能后向引用）；
## 而且**只能有这一份**：输入分支、绘制分支、`_setting_is_action()` 全按它比对，
## 写第二个字面量 "producer" 就是本仓库最常见的那个坑（改一处漏一处）。
const PRODUCER_KEY := "producer"

const SETTING_ROWS := [
	{"key": "resolution", "label": "画面尺寸"},
	{"key": "fullscreen", "label": "显示模式"},
	{"key": "bgm", "label": "BGM 音量"},
	{"key": "sfx", "label": "音效音量"},
	# ★63-23：Enter 进**音量细分页**（八条通道各一根滑条）。
	# ⚠️ 它**不是**一个"能左右拧的值"，是一整个子页面 —— 与 `battle_playlist`
	# 同一形状 ⇒ `_setting_step()` 里也显式排除了它（不排除就是白吃一次输入）。
	{"key": "volume", "label": "音量细分"},
	# 批 23 出击前自选：本场开场曲（"" = 随机；放完剩余的歌照旧随机轮流）。
	{"key": "battle_bgm", "label": "战斗BGM"},
	# ★63-22：自定义战斗歌单。与上一行**正交** —— 上一行管"本场第一首"，
	# 这一行管"第二首起的轮换池"（见 `Settings.battle_playlist` 的说明）。
	# ⚠️ 插在 `battle_bgm` 后面（**不是末尾**）：末位那几行有"必须留最后"的约束
	#（见本表尾部的注释），插错位置会改变"退出游戏"那一行的语义。
	{"key": "battle_playlist", "label": "战斗歌单"},
	{"key": "cam_roll", "label": "镜头滚转"},
	{"key": "cam_shake", "label": "镜头抖动"},
	# ---- 轮 25：**「第一人称视角」这一行已撤掉** ----
	#
	# 需求原文（用户，轮 25）：「把第一人称和第三人称切换按钮从设置菜单里面调到 F1 键，
	# 然后把眩晕警告先保留，但是隐藏着，以后我们可以把它放到别的地方去，
	# 现在先隐藏，做第一人称第三人称随意切换的形式。」
	#
	# ⚠️ **只撤了这一行，门本身一个部件都没删**：`Stage.FPV_CONFIRM`、
	# `_open_fpv_confirm()`、`_read_fpv_confirm_input()`、`FPV_CONFIRM_ROWS`、
	# `FPV_CONFIRM_YES`、`fpv_confirm_row`、绘制分支、Esc 保险丝**全在**。
	# 因为这一页就是门的**唯一入口**（`_setting_step` 的右拨与 Enter 两个手势
	# 都汇到 `_open_fpv_confirm()`），撤掉它等于让弹窗**不可达**，不是删掉它。
	# ⇒ **要把旧行为整条恢复，把这一行加回来就够了。**
	# 新的入口是战斗中的 **F1** 与 **长按手柄 Back**，两者都刻意不过门。
	{"key": "motion", "label": "降低动态"},
	{"key": "low_end_60", "label": "画质预设"},
	{"key": "render_scale", "label": "3D 渲染比例"},
	{"key": "dynamic_resolution", "label": "动态分辨率"},
	{"key": "shadows", "label": "动态阴影"},
	{"key": "effects", "label": "特效质量"},
	{"key": "magnifier_quality", "label": "放大镜刷新"},
	{"key": "ssao", "label": "环境光遮蔽"},
	{"key": "cel", "label": "三渲二渲染"},
	{"key": "keys", "label": "按键设置"},
	{"key": "quit", "label": "退出游戏"},
	{"key": "back", "label": "返回"},
	# ============================================================ ★ 隐形行（2026-09-30）
	#
	# 需求原文（老板）：「在设置菜单新增一个密码系统，**藏到最地下看不到的地方**
	#（手柄滑动选项可以选到），选到之后输入密码 20060606 然后按 enter 打开制作人模式」。
	#
	# ## 它是怎么"藏到最地下"的 —— 三件事各管一段，一件都不能少
	#   ① **在名单的最后**（`SETTING_ROWS` 末尾）⇒ 光标要一路按到底才够得着；
	#   ② **不画**（`setting_row_hidden()` = true）⇒ 名字、读数、选中高亮，
	#      一个像素都没有 —— 停在它上面时**整页看起来就是"没选中任何东西"**；
	#   ③ **仍然可选中**：导航按 `SETTING_ROWS.size()` 取模，所以"从「返回」再往下"
	#      就是它。这就是老板那句「手柄滑动选项可以选到」—— 到得了，但看不见。
	#
	# ⚠️ 它必须留在最后一行：`_draw_settings_stage()` 与 `settings_metrics()` 都按
	# 整份名单算行数，"夹在中间"会让上下相邻两行之间凭空多出一条空白
	#（那比藏起来更像 bug）。
	#
	# ⚠️ `label` 是**空串**：这一行的名字只有一份真源（`producer.gd` 的 `LABEL`），
	# 由 `setting_label()` 现取 —— 表里再抄一遍就是"两处各写一份"。
	# 它默认不画，所以空串不会被看见；开启后才显形，那时候 `setting_label()` 会给名字。
	{"key": PRODUCER_KEY, "label": "", "hidden": true},
]


## 隐形行在名单里的下标（= 最后一行）。**唯一换算点**。
static func producer_row() -> int:
	return SETTING_ROWS.size() - 1


## 设置页第 `i` 行的**标题**。
##
## ⚠️ 为什么要过一道函数、而不是绘制循环直接读 `row["label"]`：
## 制作人模式那一行的名字只有一份真源（`producer.gd` 的 `LABEL`），
## 表里那一格是空串（见 `SETTING_ROWS` 末尾那段）—— 名字在这里现取。
## ⇒ "改密码本子却忘了改这一行"在两份写法下都不会发生。
static func setting_label(i: int) -> String:
	if i < 0 or i >= SETTING_ROWS.size():
		return ""
	var row: Dictionary = SETTING_ROWS[i]
	if str(row.get("key", "")) == PRODUCER_KEY:
		return PROD.LABEL
	return str(row.get("label", ""))


## 设置页第 `i` 行**画不画** —— 这一段就是老板那句「藏到最地下**看不到**的地方」。
##
## ★ 它被抽成**一等函数**，而不是"在绘制循环里记得 `continue`"：
## 这正是 `mission_brief.STORY_H` 那条教训的落点 —— **"画不画"必须是版式的输出，
## 不能是一个"写在画画的地方、靠人记得"的条件**（那一处恒假了整整一轮没人发现）。
## 现在判据能直接量它（`suite_producer` 逐行量），改动不可能静默失效。
##
## 规则有两半：
##   1. **`hidden` 的行不画** —— 名字、读数、选中高亮全都不画
##      （停在它上面时整页看起来就是"什么都没选中"）；
##   2. **例外**：`producer` 那一行在制作人模式**已开启**时显形。
##      ⚠️ 没有这一条，"开了就再也找不到开关、只能重启游戏关掉" ——
##      一个开得开、关不掉的开关是陷阱（对照 `_open_fpv_confirm()` 那条取舍：
##      **门只挡危险的那一侧**；开启要密码、关闭不要，所以关掉这条路不必藏着）。
##      ⚠️ 这个例外**不可能被普通玩家看见**：显形的前提是先输对过密码。
static func setting_row_hidden(i: int, producer_on := false) -> bool:
	if i < 0 or i >= SETTING_ROWS.size():
		return true
	if not bool(SETTING_ROWS[i].get("hidden", false)):
		return false
	return not (str(SETTING_ROWS[i].get("key", "")) == PRODUCER_KEY and producer_on)

## 战斗BGM 选歌页（批 24）的选中项：0 = 随机，1.. 与战斗曲池同序。
## 滚动窗口不落盘 —— 输入/绘制时现算（与模式/敌机页同一套 `scroll_window`）。
var bgm_row := 0

# ============================================================ ★63-23 音量细分
#
# 需求原文（用户 2026-10-08）：「做一个音量调节系统：武器（机枪，军刀，步枪，
# 浮游飞弹）音量，警报音量，bgm音量，引擎音量」。
#
# ## 为什么是**设置页的第二个子屏**而不是新加 `Stage`
# 照上面 ★63-22 那条约定（子屏不新增 `Stage` 枚举值）。而这一页尤其适合：
# 它本来就是**设置页的一部分**（离开它要退回设置页），不像选歌页那样另有一整套语义。
# 代价是 `Stage.SETTINGS` 这一个值下面要分派输入 / 绘制 / 焦点三处 —— 三处都写了。
#
# ## 为什么不是"平铺七行到设置页"
# 设置页现在 14 行，900 高刚好一屏画得下（`suite_round` 有一条断言钉着）。
# 再加七行 ⇒ 可见行数不满足 ⇒ 必须把"900 高下全画得出来"这条判据改弱。
# **为了让新功能上线而削弱一条既有判据，是这一轮明确不要的代价。**

## 设置页主屏。
const SET_SUB_MAIN := 0
## ★63-23 音量细分页。
const SET_SUB_VOLUME := 1

## 设置页当前子屏（`Stage.SETTINGS` 内部）。
var settings_sub := SET_SUB_MAIN

## 音量细分页选中的行（`volume_rows()` 的下标）。
var volume_row := 0

# ============================================================ ★63-22 战斗曲册两页
#
# ## 本工程的约定：**子屏不新增 `Stage` 枚举值**
# 照 `LAN_SUB_MAIN/ADV/ROOMS` 的做法。`Stage` 被 `_draw()` / `_read_input()` /
# `nav_axis()` / `suite_round` 四处逐个列举 ⇒ 加一个值要同步改四处，
# 漏一处的症状同样是"没反应"。子屏只在**已经分派进来的那一页内部**分叉。
#
# ## 为什么是两个子屏而不是把歌单挤进选歌页（用户拍板 Q12「新子屏」）
# 选歌页的 `Enter` = **设定本场开场曲**（已有行为，一字不改）；
# 歌单页的 `Enter` = **加入/移出**（toggle）。同一页里放两个不同的 `Enter` 语义
# 才是真的危险 —— 分成两屏之后，玩家按 `Enter` 之前**眼前是什么页面**已经说明了一切。

## 选歌页（本场第一首）。
const BGM_SUB_PICK := 0
## ★63-22 战斗歌单页。
const BGM_SUB_LIST := 1

## 当前子屏（`Stage.BGM` 内部）。
var bgm_sub := BGM_SUB_PICK
## 歌单页选中的行（`bgm_pick_keys()` 的下标，与 `bgm_row` 同一套序列）。
var playlist_row := 0

## 歌单页底部的**结果行**（空 = 不画）。被拒（满员 / 切到随机行）时写它。
##
## ⚠️ 与 `bgm_row` 分开：它是"上一次操作的答案"，换行不该把它清掉
##（"我按了没反应"是玩家最怕的那种反馈，留一句话在那儿最省事）。
var bgm_msg := ""

## 上一次 `_tick_bgm_page()` 判定时，"我在不在战斗曲册那两个页面上"。
## ⚠️ 只在**变化的那一帧**做事（压低/恢复菜单 BGM、停试听），所以它必须是个状态。
var _bgm_page_on := false

## 歌单页页头的高度（面板顶部那一行只读摘要）。见 `bgm_list_panel_rect()`。
##
## ⚠️ 它**参与版式计算**（作为 `reserve_top` 的一部分），不是"画上去就算" ——
## 理由见 `bgm_list_panel_rect()` 的注释。
const BGM_HEAD_H := 34.0
## 行尾标记：**「仅自选曲」**（★63-22 取代了原来的「（仅自选 · 不参与随机）」后缀）。
##
## 同一个符号在两个页面各有一层意思，且**互不冲突**：
##   · 选歌页：带 `◆` ⇒ 这首**不会被随机轮到**（`SoundBank.is_opt_in_battle_track()`）；
##   · 歌单页：带 `◆N` ⇒ 这首**已经在我的歌单里**，序号 N（`Settings.playlist_slot()`）。
## 两页的行尾都是"这一行的状态"，不会同时出现两种含义。
const BGM_OPT_IN_MARK := "◆"

## 第一人称眩晕警告（轮 20）的两个选项。**下标 0 必须是「否」**。
## 顺序就是安全性：光标每次进来都停在下标 0，所以"连按确认"永远关不掉这道门。
const FPV_CONFIRM_ROWS := ["否 · 保持关闭", "是 · 开启第一人称"]
## 「是」的下标。抽成常量是为了让输入（`_read_fpv_confirm_input`）与绘制
##（`_draw_fpv_confirm_stage`）读**同一个数** —— 写死 0/1 四处的话，
## 哪天有人把选项顺序调过来，就会出现"框里高亮的是「否」、按下去却开启了"。
const FPV_CONFIRM_YES := 1

var stage := Stage.MODE
## 训练项目页选中的项：0 = **自由打靶**、1 = **新手教学**。
##
## 用户要求「新手教学**和靶场在同一页面**」—— 所以它们是**同一页的两行**。
## 这个下标就是那一页的选择。
var training_item := 0
## 训练项目表（下标与 `training_item` 对应）。
const TRAINING_ITEMS := ["自由打靶", "新手教学"]
var mode_index := 0
## 「对战模式」子页里选中的形式下标（`battle_modes()` 的下标）。
##
## 与 `mode_index` 是**两层**：`mode_index` 是顶层分组（对战 / 训练 / 联机），
## 这一项只在**对战模式那一组**里生效 —— 而"当前这一局是什么模式"由
## `selected_mode()` 把两层合成一个答案给出去（别在别处自己拼）。
var battle_index := 0
## 编队战（1.2 第二十轮）里玩家选的阵营下标：0 = 马夫蒂 / 1 = 地球联邦军。
## **只有编队战会走这一页**，其它模式不读它。
var side_index := 0
var suit_index := 0
var enemy_index := 0
var diff_index := 1
var map_index := 0
## 挑战模式：当前遭遇在 `encounters()` 里的下标。
var encounter_index := 0
## ★63-24 无限强化演习 · 开局配置页的焦点行（`endless_pool()` 的下标）。
##
## ⚠️ 焦点行**不是**"已选中的卡" —— 已选的是 `endless_picks`（下面那一项）。
## 这一个只回答"光标现在停在哪一行"，与 `training_item` / `map_index` 同级。
var endless_index := 0
## ★63-24 已勾选的卡（存 `UpgradeCard.id`）。
##
## ## 为什么存 `id` 而不是存下标
## 下标是"在 `endless_pool()` 里的位置"，而那个池子**随自机变化**
##（`UpgradeCard.basic_pool()` 过 `viable_for`：柯西的池里没有重炮卡）。
## 玩家从柯西换成佩涅罗佩，同一个下标会指到**另一张卡**，
## 于是"我明明选了装甲强化，出击后拿到的是别的"—— 且不报错。
## `id` 是词条自己的名字，跨池稳定。
##
## ⚠️ 三条口径（设计 §5.6）：① 3 张必须**互不相同**；② 不能重复选同一张；
##    ③ **不默认帮玩家填满** —— 不足 3 张时确认键不响应（见 `_read_input()`）。
var endless_picks: Array[String] = []
## 卡池缓存：`_draw()` 与 `_read_input()` **每帧**都要问"池子里有哪些卡"，
## 而每次现算 = 新建一份 profile + 几十个 `UpgradeCard`（带 `Callable`）。
## 键是**机体 id**：换机体才失效，所以不会读到过期的那一份。
var _endless_pool_cache: Array[UpgradeCard] = []
var _endless_pool_key := -1
## 设置页当前选中的行。
var setting_row := 0
## 长按连调用的计时器（见 `_step_dir`）。
var _repeat_timer := 0.0
## `_step_dir()` 的**输出**：这一下是"刚推过去"（true）还是长按连发出来的（false）。
## 存在这里而不是返回值里 —— 见 `_step_dir()` 的说明。
var _step_fresh := false
## 进设置页之前停在哪一页，返回时回到原处。
var _settings_return_stage := Stage.SUIT
## 第一人称眩晕警告（`Stage.FPV_CONFIRM`）当前选中的项。
##
## ⚠️ **下标 0 必须是「否」**，而且每次进入都重置回 0（见 `_read_settings_input()`）——
## 这道警告的全部价值在于"它默认不让你过"。默认停在「是」的话，
## 玩家一路连按确认就会顺手把最晕的模式打开，那还不如不做这道门。
var fpv_confirm_row := 0
## ---- 密码页（`Stage.PASSWORD`，2026-09-30 的隐藏入口）----
#
## 已输入的数字（**已经过 `PROD.sanitize()`**：只会有 0-9，长度 ≤ `PROD.MAX_LEN`）。
##
## ⚠️ 回显与判定**读的是同一个串**（`PROD.echo(pw_input)` / `PROD.matches(pw_input)`）——
## 各存一份的话会出现"框里是 8 位、判定按 6 位算"这种没人查得出来的错位。
## ⚠️ 它**不进存档**，也不该进：这是"这一次输入到哪了"，不是设置项。
var pw_input := ""
## 密码页上的结果行（空 = 不画）。红字 / 绿字由 `pw_ok` 决定。
var pw_msg := ""
var pw_ok := true
## ---- 按键设置子页（批 4 · §4.8.7）----
var keys_row := 0         ## 重绑页选中的行（keys_flat() 的下标）
var keys_slot := 0        ## 行内选中的键格（slot）
var keys_scroll := 0      ## 可视窗口顶部的行下标
var waiting_bind := false ## 等待按键态
var wait_action := ""
var wait_slot := -1
var keys_msg := ""        ## 页脚结果 / 冲突提示（空 = 不画）
var keys_msg_ok := true   ## false = 红字（冲突 / 拒绝）
## 等待态选中的槽种类（"key"/"mouse"/"pad"；批 10 手柄槽混行后必须分开换算）。
var wait_kind := ""
var _keys_r_hold := 0.0   ## R 按住时长（点按 = 恢复本行，长按 0.6 s = 全部恢复）
var _keys_r_all_done := false
## Esc 保险丝处理过的帧号：同一帧里 InputMap 的 menu_back 不许再退一层
var _esc_fuse_frame := -1
var active := true
## 输入锁，由 main 在阶段切换时设置。
##
## 光靠计时锁**不够**：实测那一下"回主菜单"的按键，其输入事件有时会延迟很多帧才被
## flush 出来，于是菜单在计时锁早就过期之后才第一次看到它 —— 按一下键被两个界面各吃一次，
## "回主菜单"顺带把菜单也推进了一步（玩家跳过了选机体）。
##
## 所以这里不靠时间，靠**边沿**：菜单打开后必须先观察到确认键处于"松开"状态，
## 才承认之后的按下。这样上一个界面的那一下按键（无论何时被 flush）都一定被吞掉。
var input_lockout := 0.0
var _await_release := true

var _home_view: Control
var _font: Font
var _time := 0.0
var _choice_age := 0.0
var _choice_key := ""
var _text_tilt := Vector2.ZERO
var _pointer_tilt_active := false
var _tilt_label: Label
var _tilt_material: ShaderMaterial
## "退出游戏"的二次确认窗口（秒）。见 `_read_input()`：手柄上 B 就是返回，
## 在选机体这一页按一下 B 直接退游戏太容易误触了。
var _quit_armed := 0.0
const QUIT_CONFIRM_WINDOW := 2.5
## ★63-19b 滚轮后**屏蔽悬停**的时长（秒）。
##
## ⚠️ 为什么需要它：滚轮把焦点从第 N 行挪到第 N+1 行，但**光标还在第 N 行上**。
## 此时系统若补发一发 `InputEventMouseMotion`（**触摸板双指滑**必发、
## 高精度滚轮也常发），`_hover_focus()` 就会把焦点**拽回第 N 行** ——
## 表现为"滚不动 / 滚一下跳回来"。真实鼠标滚轮（光标静止、驱动不发 motion）
## 不会触发，所以**光靠真机手测很难发现**（探针的 `warp` 才把它稳定复现）。
const WHEEL_HOVER_MUTE := 0.15
const WARN := Color(1.0, 0.74, 0.22)

## ---------------------------------------------------------------- 版式
##
## 主菜单和结算菜单、战斗 HUD **共用同一套网格**（见 `UILayout`）。
## 规则只有一条，但它是硬规则：
##
##   **每一块面板都从 `MARGIN` 铺到 `屏幕宽 − MARGIN`；面板里的文字落在
##     `content_left()` / `content_right()` 上。**
##
## 改之前是三块面板各写各的宽度再各自居中（机体卡 500×2、难度行 760、
## 设置面板 620），而底部那块操作说明面板是通栏的 —— 一屏之内四个宽度、
## 四条不重合的边，看起来就是"没排过版"。现在四块面板共用同一条外框线。
##
## 纵向也分成固定的四段，**每一页都一样**（页面切换时面板不会上下跳）：
##
## ```
##   46   步骤条（① ② 左对齐 / ⚙ 设置在右）           STEP_Y
##   70 ┌ 标题带（100 高：LOGO 或页标题）┐              TITLE_TOP..TITLE_TOP+TITLE_BAND
##  190 ┌ 内容区（**随屏幕高伸缩**）┐                    PANEL_TOP..content_bottom()
##  H−70 └ 页脚提示带（锚定屏幕底边）┘                  hint_y()
## ```
##
## ⚠️ **2026-09-22（批 24）：底部常驻「操作说明」面板删除了**（用户原话：
## 「这块板没人看啊，你要不删了把」—— 截图指向主菜单底部那块三栏键位表）。
## 键位说明并没有从游戏里消失：**游戏内 H / 帮助与重绑页仍然全量可查**，
## 菜单底部这块只是"常驻复读"。
##
## ⚠️ **2026-09-22（批 29）：内容区改成"随屏幕高伸缩"，行高自适应、整块居中。**
## 批 24 删掉底部面板之后留了个尾巴：内容仍然按 `LIST_END`（660）这条**写死的**线
## 收尾，于是 900 高的窗口里 **660..900 那 240 px 永远是空的**（截图上一眼就是
## "内容挤在上半屏、下面一大片空"），而且星空也只铺到 660 —— 那一带连背景颗粒
## 都没有，看着就是一块黑洞。
##
## 现在三件事一起改：
##   ① 内容区底边 = `content_bottom()`（**由屏幕高算**，不再是 660）；
##   ② 页脚提示行**锚定屏幕底边**（`hint_y()`）—— 每页底部都有一条收口；
##   ③ 列表行高按"内容区还剩多少"**自适应放大**（`list_metrics()`，上限见
##      各 `*_ROW_MAX`），整块在内容区里**垂直居中**。
## 于是任意分辨率下都是"上中下三段撑满"，而不是"内容堆在上半屏"。
## ```
const STEP_Y := 46.0
const TITLE_TOP := 70.0
const TITLE_BAND := 100.0
const PANEL_TOP := 190.0
const PANEL_GAP := 52.0
## ⚠️ 批 29：原来的 `HINT_GAP`（"提示行紧跟面板的间隙"）退役了。
## 提示行现在锚定屏幕底边，见 `HINT_BASELINE_LIFT` 与 `hint_y()`。
## 机体卡高度：**由内容区高度算出来**（见 `card_h()`），不再是一个写死的数。
##
## 下限 356：卡里排得最满的是阿利宙斯（比另两台多一行"形态名"），它的文案区
## 到 ~350 收尾 —— 低于这个数就会把背景文案截掉（那正是第一版的坏样子）。
## 上限 440：再高就只是空白了（卡内元素会跟着**伸缩**，但文案本身只有那么长）。
## 卡片内容是**从上往下排**的，所以卡加高之后多出来的空间分给"数值条行距 +
## 段落呼吸 + 文案行数"（`_draw_suit_card()` 里按卡高算），不是变成卡内空白。
const CARD_H_MIN := 356.0
const CARD_H_MAX := 440.0
## 一行一张的卡式行（难度 / 地图 / 阵营 / 训练项目 / 遭遇）。
## `ROW_H` 是**最小行高**（"还放得下几行"的判据），行数少时放大到 `ROW_MAX` ——
## 三行的难度页、两行的地图页在 900 高窗口里因此不再缩在屏幕上半截。
const ROW_H := 96.0
const ROW_GAP := 16.0
const ROW_MAX := 136.0
## 行数 ≤ 2 的页（**地图 / 阵营**）用这一档上限。
##
## 两行页按 `ROW_MAX` 只有 2×136 = 272，内容区 640 高的话上下各留 184 ——
## 那还是"内容缩在中间、上下两片空"。所以这两页允许放到更高（一行 200）。
const ROW_MAX_FEW := 200.0
## 模式行高。`MODE_ROW_H` 是**最小行高**（= "还放得下几行"的判据），
## `MODE_ROW_MAX` 是**放大上限**（行数少的时候行更高，但不能高到一行占半屏）。
##
## 历史（留给下一个往 `MODE_GROUPS` 里加东西的人）：模式页过去靠**手调行高**避坑 ——
## 4 个模式时 96+16 会排到 622、5 个模式时 78+10 排到 620，两次都压到底部面板上
##（玩家看到的就是"主菜单排版乱了"）。62+6 之后五行落在 190..524。
## ⚠️ 那是"按行数硬调"。**批 29 起不用再调了**：行高由 `list_metrics()`
## 按内容区高度算出来（行数多了先变矮、到 `MODE_ROW_H` 为止，再放不下就走滚动窗口）。
## 2026-09-29 收官时这一页是 **4 行**（`MODE_GROUPS.size()` = 对战 / 剧情挑战 / 训练 / 联机）：
## 「王牌战 / 小队战」收进子页让它从 4 行变 3 行，剧情挑战恢复入口又回到 4 行。
## 两次都没有调过这里的数字 —— 行高由 `list_metrics()` 自适应
##（4 行时落在 `MODE_ROW_H` 与 `MODE_ROW_MAX` 之间），这正是它该有的样子。
const MODE_ROW_H := 62.0
const MODE_ROW_GAP := 16.0
const MODE_ROW_MAX := 88.0
## 敌机行：`ENEMY_SUITS` 现在是**三台**，行高按"最多五台"留的余量（64+4）。
## 批 29 起这个余量只是"最小行高"：三台时行会被放大到 `ENEMY_ROW_MAX`（更饱满），
## 名单再长也只是先压回 64 再滚动 —— 不用再手调。
const ENEMY_ROW_H := 64.0
const ENEMY_ROW_GAP := 4.0
const ENEMY_ROW_MAX := 104.0
## 联机行：4 行 + 一行"状态："。`LAN_ROW_H` 同样是最小行高（4 行必然放得下），
## 行数少时放大到 `LAN_ROW_MAX`。
const LAN_ROW_H := 74.0
const LAN_ROW_GAP := 6.0
const LAN_ROW_MAX := 108.0
## 设置行高。**第十四轮从 48 压到 36**（当时设置页一下多了三行镜头项，
## 48×9 + 40 会排到 662、压到底部面板上）。批 29 起 36 是**最小行高**：
## 13 行在 900 高窗口里自动放大到 ~47 把内容区铺满，多到放不下才滚动。
const SETTING_ROW_H := 36.0
const SETTING_ROW_MAX := 52.0
## 列表面板（设置 / 选歌 / 重绑）里"行块之外"的固定占用：
## 面板顶到行块顶 8 px、行块底到面板底 12 px。面板高度 = 行块高 + 这两个数，
## 居中时也必须按"面板整体"算，否则面板会从内容区里伸出去。
const PANEL_PAD_TOP := 8.0
const PANEL_PAD_BOTTOM := 12.0
## 重绑页行高与可视行数（行数比设置页多，用滚动窗口装下全部可重绑动作）。
## 行高同样在 [30, 46] 之间自适应；窗口容量仍是 `KEY_PAGE_ROWS` 行。
const KEY_ROW_H := 30.0
const KEY_ROW_MAX := 46.0
const KEY_PAGE_ROWS := 12
## 重绑页的行序：**按 HELP_SECTIONS 的分组顺序**（§4.8.7）。
## 锁死的动作（menu_back / pause / confirm）**不列** —— 防自锁第①层的 UI 侧体现。
## ⚠️ 批 10：手柄按键**进了**自定义（§4.8.5 旧规"手柄不进自定义"已按用户要求推翻）——
## 每行的手柄槽显示在键盘槽后面，等待态按手柄键即可重绑（B 保留为取消）。
const KEY_GROUPS := [
	["飞行", ["pitch_nose_up", "pitch_nose_down", "roll_left", "roll_right",
		"yaw_left", "yaw_right", "throttle_up", "throttle_down",
		"boost", "hover", "transform", "look_back", "cockpit_freelook", "toggle_invert"]],
	["武器", ["fire_primary", "fire_secondary", "switch_weapon", "reload",
		"fire_gun", "fire_missile", "repair", "shield", "ride_pedal", "flares"]],
	["锁定 / 系统", ["select_threat", "flight_assist", "missile_mode",
		"switch_target", "select_contact_1", "select_contact_2",
		"select_contact_3", "select_contact_4", "select_contact_5",
		"select_contact_6", "select_contact_7", "select_contact_8",
		"select_contact_9", "open_settings",
		# 轮 25：F1 第一人称切换（可重绑）。`suite_keybind` 要求 `BINDINGS` 里
		# 每个可重绑动作都在这张表里有一行，少一行它就红。
		"toggle_fpv",
		# 轮 31：M 中央屏切换（可重绑）。`suite_keybind` 要求 `BINDINGS` 里
		# 每个可重绑动作在这张表里都有一行 —— 少一行它就红。
		"cycle_dash_screen"]],
]
## ---- 内容区（批 29：由屏幕高算出来，不再是一条写死的 660）----
##
## 页脚提示带的高度：提示行本身 + 上下呼吸。内容区底边 = 屏幕底 − MARGIN − HINT_BAND。
## 900 高 → 830；720 高 → 650（比批 24 的 660 还往下让，因为 720 下也没别的东西了）。
const HINT_BAND := 46.0
## 提示行基线距屏幕**底边**的距离（锚底）。900 高 → 870，720 高 → 690。
## 锚底是这一轮的关键：提示行原来是"紧跟在内容下面"，于是内容短的时候
## 提示行浮在屏幕中上部、下面还是一大片空 —— 现在它永远贴着底边收口。
const HINT_BASELINE_LIFT := 30.0


## 通栏面板矩形：左右边界 = 屏幕外框线，与结算菜单两栏、操作说明面板完全重合。
static func panel_rect(view: Vector2, top: float, height: float) -> Rect2:
	return Rect2(UILayout.MARGIN, top, UILayout.frame_width(view), height)


## 两张（1.1 起是三张）机体卡：最左/最右外边缘落在面板外框线上，卡与卡之间留 `PANEL_GAP`。
## 卡片内部文字用 `UILayout.PAD` 内缩 —— 于是卡片里的数值列右端
## 与战斗 HUD、结算菜单的数值列是**同一条竖线**。
##
## 张数改成跟着 `SUITS.size()` 走：1.1 加进阿利宙斯之后，
## 写死"两张"的那一版会把第三张卡直接画出屏幕。
## 机体卡高度（批 29 起由内容区高度算出来，不再是写死的 340）。
## 见 `CARD_H_MIN` / `CARD_H_MAX` 的说明。
## `0.78` 是"卡片占内容区的比例"：留出上下各一成的呼吸，同时尽量让卡本身大一点。
static func card_h(view: Vector2) -> float:
	return clampf(content_height(view) * 0.78, CARD_H_MIN, CARD_H_MAX)


## 机体卡的顶（整排卡在内容区里**垂直居中**）。
static func cards_top(view: Vector2) -> float:
	return PANEL_TOP + maxf((content_height(view) - card_h(view)) * 0.5, 0.0)


## 机体卡的矩形 —— **纯几何**：把 `count` 张卡等宽铺满整个外框宽度。
##
## `count` 默认取 `SUITS.size()` ⇒ **旧调用点与 `suite_layout` 的断言继续有效**
##（它们要的就是"全部可选机体"那一档）。
## ⚠️ 2026-09-29 起 `count` 的语义是「**屏幕上这一次画几张**」，**不再是「名单有几台」** ——
## 名单可能比这长，长出来的部分靠 `suit_window()` 滚进视野（见下）。
## 编队战 / 联机按阵营过滤之后张数会变（马夫蒂 4 台 / 联邦 3 台），那时显式传窗口的张数。
static func suit_card_rects(view: Vector2, count := SUITS.size()) -> Array[Rect2]:
	var n := maxi(count, 1)
	var w := (UILayout.frame_width(view) - PANEL_GAP * float(n - 1)) / float(n)
	var h := card_h(view)
	var top := cards_top(view)
	var out: Array[Rect2] = []
	for i in n:
		out.append(Rect2(UILayout.MARGIN + float(i) * (w + PANEL_GAP), top, w, h))
	return out


## 机体卡片的**横向窗口**：返回 `Vector2i(首张卡的名单下标, 这一次画几张)`。
##
## ## 为什么 2026-09-29 要加这个（而不是继续"有几台就画几张"）
## 老板要求把梅萨指挥官型 / F01型加进**小队战的马夫蒂**，那个阵营的可选机体因此
## 从 2 台变 **4 台** —— 而 `max_cards()` 在 1280 / 1600 下都是 **3**（见那里的推导）
## ⇒ 4 张卡每张只剩 349 px，**低于 `CARD_MIN_W = 376` 这个可读下限**。
## 这正是 `CARD_MIN_W` 的注释早就预言过的那一刻：
## 「把第 4/5 台机加回 `SUITS` 或某个阵营的 `all_suits()`，卡片立刻又会挤」。
##
## ## 为什么选"横向窗口"，不是当年被否掉的另外两条
## §4.7 第 5 项当年在「两行 3+2 布局」与「横向滚动」之间选了**两条都不做** ——
## 因为那时 1v1 的可选机体刚收成 3 台，"问题自己消失了"。
## 现在的数据变了（**必须**让第 4 台能被选到），而两条里的取舍没变：
##   - **两行 3+2**：要新引进一套"两行卡"的几何（`card_h` 要减半、
##     数值列线要重新推导），且"只有 3 台却排成 3+2"更难看 —— 否决；
##   - **横向窗口**：**复用工程既有的 `scroll_window()` / `_draw_scroll_indicator()` 语义**
##     （模式页 / 敌机页 / 键位页 / 联机页 / 设置页全在用），轴向从 Y 换成 X 而已 —— 选中。
##
## ★ 关键性质：**3 台及以下的名单，窗口恒等于整份名单**
##（`scroll_window` 在 `count <= n` 时返回 `(0, count)`）⇒ 其余模式与联邦侧的
##   版式、行为、像素**一个都没变**，只多了一个"放得下就什么都不画"的指示器。
static func suit_window(count: int, index: int, view: Vector2) -> Vector2i:
	return scroll_window(count, index, max_cards(view))


## 机体卡的最小可读宽度（px）。
##
## ## 这个数怎么来的（不是拍的）
##
## 它是 **1280×720**（工程支持的最小分辨率）下、面板里放 **3 张卡**时每张的实际宽度 ——
## 也就是"三台机**并列比较**"这个版式的下限：
## ```
## (frame_width(1280) − PANEL_GAP × 2) / 3 = (1232 − 104) / 3 = 376.0
## ```
## `suite_layout` 会**重算一遍**这个式子来核对常量没被顺手改掉。
##
## ## 它守的是哪件事（设计文档 §4.7 第 5 项 / 交接文档 §8.2）
##
## 原问题：「机体页横向窗口 —— **5 张卡每张仅 ~334 px**」，当时的备选是
## **两行 3+2 布局**，或者沿用主菜单已有的滚动系统。
##
## **结论：两条都不做。** 第二十二轮下半把 1v1 的可选机体从 5 台收成 **3 台 ACE**，
## 而编队战 / 联机按阵营过滤后最多是**联邦的 3 台**（佩涅罗佩 / 阿利宙斯 / 古斯塔夫 00）——
## 每张卡从 ~334 px 回到 1600 宽下的 ~448 px、1280 宽下的 376 px，
## 两行布局要解决的问题**自己消失了**；而"只有 3 台却排成 3+2"反而更难看。
##
## ⚠️ **2026-09-29：这条结论的前提被数据推翻了** —— 马夫蒂侧加了梅萨指挥官型 / F01型，
## 可选机体变成 **4 台**（柯西 ＋ 三台梅萨），"最多 3 台"不再成立。
## 两条备选里**取"沿用主菜单已有的滚动系统"那一半**（另一条"两行 3+2"仍然不做，
## 理由不变：它要新引进一套几何，而且"3 台却排成 3+2"依旧难看）——
## 落实为 `suit_window()`，见那里的整段说明。
##
## ⚠️ **它仍然是"可读下限"，从来不是"张数上限"** —— 这两件事在上面那一刻分开了：
## 下限由 `max_cards()` 折成"这一屏最多排几张"，超过的部分走 `suit_window()` 滚进来。
## 所以「第 4 台加进来」现在的处置**不是**"把卡压窄"（那会破这条下限），
## 而是"**排 3 张 + 让第 4 张能滚到**"。`suite_layout._menu()` 拿
## `max_cards()` 与 `suit_window()` 两个一起去量这件事：
## **窗口容量不得超过物理容量，且名单里每一台都必须能滚进窗口**。
const CARD_MIN_W := 376.0


## 这套版式在 `view` 下最多排得下几张机体卡（由 `suit_card_rects()` 的定义反推）。
##
## ⚠️ 它答的是**物理容量**（"一屏塞得下几张而不破 `CARD_MIN_W`"），
## **不是**"名单允许有几台"。这两件事自 2026-09-29 起由 `suit_window()` 分工：
## 这里是容量，`suit_window()` 拿它当窗口大小去翻名单。
## 1920 宽下它 = **4**（所以超宽屏上马夫蒂的 4 台是**一屏排开、不滚动**的）。
##
## `w(n) = (frame − gap·(n−1)) / n ≥ CARD_MIN_W`
## `  ⇒ n ≤ (frame + gap) / (CARD_MIN_W + gap)`
static func max_cards(view: Vector2) -> int:
	var span := UILayout.frame_width(view) + PANEL_GAP
	return maxi(1, int(floor(span / (CARD_MIN_W + PANEL_GAP))))


## 这份名单（`count` 台）在当前分辨率下**一屏排得下**吗。
##
## ⚠️ 它答的是"要不要滚动"，**不是"这份名单合不合法"**（见 `suit_window()`）——
## 排不下现在是**走窗口滚**，不是错误。所以别把它当成新的张数门槛。
static func cards_fit(view: Vector2, count: int) -> bool:
	return count <= max_cards(view)


## 难度 / 地图两页共用同一种"一行一张"的版式：铺到外框线、右端落在数值线上。
## 行高由 `list_metrics()` 按页内行数自适应（批 29）。
static func map_row_rect(view: Vector2, i: int) -> Rect2:
	var m := list_metrics(view, MapDef.versus_maps().size(), ROW_H, ROW_GAP, ROW_MAX_FEW)
	return list_row_rect(view, i, 0, m)


## ⚠️ 模式页**走窗口**画（`list_row_rect`，见 `_draw_mode_stage()`），
## 于是这个函数改成它的第一窗口特例 —— **但必须留着**：
## `suite_round._menu_axis()` 用**它**去量"模式页是竖排行"，
## 如果它和真正画图的那条路径分家，那条测试就变成在量一个没人用的函数
##（"量的是真版式"这个前提会静默失效）。
##
## ⚠️ 行数取 `MODE_GROUPS.size()`（**3 组**），不是 `all_modes().size()`（4 个模式）——
## 分组之后"这一页有几行"和"工程里有几个模式"不再是同一个数。
## Main entries share this width in drawing and mouse hit testing.
static func compact_mode_metrics(view: Vector2, metrics: Dictionary) -> Dictionary:
	var m := metrics.duplicate()
	m["width"] = minf(UILayout.frame_width(view) * 0.78, 960.0)
	m["left"] = (view.x - float(m["width"])) * 0.5
	return m


static func mode_row_rect(view: Vector2, i: int) -> Rect2:
	var m := compact_mode_metrics(view, list_metrics(view, MODE_GROUPS.size(), MODE_ROW_H, MODE_ROW_GAP, MODE_ROW_MAX))
	return list_row_rect(view, i, 0, m)


## 「对战模式」子页（王牌战 / 小队战）的行矩形。
## 与 `mode_row_rect()` 同一套版式，只是行数是那一组的形式个数。
static func battle_row_rect(view: Vector2, i: int) -> Rect2:
	var m := compact_mode_metrics(view, list_metrics(view, battle_modes().size(), MODE_ROW_H, MODE_ROW_GAP, MODE_ROW_MAX))
	return list_row_rect(view, i, 0, m)


static func difficulty_row_rect(view: Vector2, i: int) -> Rect2:
	var m := list_metrics(view, Difficulty.all_levels(Game.super_hard_unlocked).size(), ROW_H, ROW_GAP, ROW_MAX)
	return list_row_rect(view, i, 0, m)


## 选歌页（批 24）的选项键序列（下标 = `bgm_row`）：0 = 随机，其后与**自选列表**同序。
##
## ⚠️ 与 `Settings.cycle_battle_bgm` / `set_battle_bgm_index` / `battle_bgm_index`
## 是**同一份序列**（`[""] + SoundBank.battle_pick_tracks()`）—— 四个消费方，
## 一处定义都不许分叉：分叉的症状是"菜单里选中的是这首、进游戏放的是那首"，
## 而且不报任何错。
static func bgm_pick_keys() -> Array:
	var keys := [""]
	keys.append_array(SoundBank.battle_pick_tracks())
	return keys


## 列表面板（设置 / 选歌 / 重绑）的版式：行块之外还要算上下面板的上下内边距。
static func list_panel_metrics(view: Vector2, count: int, min_h: float, max_h: float) -> Dictionary:
	return list_metrics(view, count, min_h, 0.0, max_h, PANEL_PAD_TOP, PANEL_PAD_BOTTOM)


## 列表面板的外框：顶 = 行块顶 − `PANEL_PAD_TOP`，高 = 行块高 + 上下内边距。
static func list_panel_rect(view: Vector2, m: Dictionary) -> Rect2:
	var h := float(m["block_h"]) + PANEL_PAD_TOP + PANEL_PAD_BOTTOM
	return panel_rect(view, float(m["top"]) - PANEL_PAD_TOP, h)


static func settings_metrics(view: Vector2) -> Dictionary:
	return list_panel_metrics(view, SETTING_ROWS.size(), SETTING_ROW_H, SETTING_ROW_MAX)


static func settings_panel_rect(view: Vector2) -> Rect2:
	# 批 24：行数已超过一屏能放下的量 —— 面板高度只按**真的画得出的行数**算，
	# 多出来的行走滚动窗口（与模式/敌机页同一套机制）。
	return list_panel_rect(view, settings_metrics(view))


## 提示行的 y：**锚定屏幕底边**（批 29）。
##
## 原来是"跟在所属面板下面、再钳到不出屏"，于是内容短的时候提示行浮在屏幕
## 中上部、下面还是一大片空。现在所有页面共用这一条底线 —— 翻页时提示行不跳，
## 它和内容区之间的空隙天然就是页脚带（`HINT_BAND`）。
static func hint_y(view: Vector2) -> float:
	return view.y - HINT_BASELINE_LIFT


# ============================================================ 内容区与列表版式
#
# 一页能放几行、每行多高，**全部由版式算出来**（`list_metrics()`），不写死。
#
# ⚠️ 为什么必须有它（这是踩过两次的坑）：模式 4 → 5、敌机 3 → 5 这两次扩容
# **都排到了底部面板上**，玩家看到的是"行和操作说明叠在一起"（"主菜单排版乱了"）。
# 根因不是哪一行写错了，而是**行数写死在 `for i in X.size()` 里、能放几行却是
# 版式决定的** —— 加内容的人只能靠记性避坑。
#
# 批 29 之后这个函数还多担一件事：**行高自适应**。行数少的时候行会变高
#（上限 `*_ROW_MAX`）把内容区撑满，行数多的时候先压回最小行高、再放不下才滚动。
# 于是"下面太空"不会以"换个分辨率又空了"的形式回来。
#
# 三条不变量（`suite_round` / `suite_menu_frame` 真的量，不是背下来的结论）：
#   1. 窗口长度不超过可见行数；
#   2. **聚焦项一定在窗口里** —— 否则玩家看不见自己选到哪一行了；
#   3. 放得下时 `first == 0` 且窗口 = 全部（指示条不画：一个永远不动的滚动条
#      会让人以为下面还有内容）。

## 内容区底边：屏幕底 − `MARGIN` − 页脚提示带。
static func content_bottom(view: Vector2) -> float:
	return view.y - UILayout.MARGIN - HINT_BAND


## 内容区高度（`PANEL_TOP` 到 `content_bottom()`）。900 高 → 640（批 24 之前只有 436）。
static func content_height(view: Vector2) -> float:
	return maxf(content_bottom(view) - PANEL_TOP, 1.0)


## 一段矩形（行）的**垂直中心 + 偏移**。行内文字一律走它 + `text_vcenter()` ——
## 行高会自适应，所以"r.position.y + 38.0"这种写死基线必须全部退役：
## 行变高了、字还挤在顶上，看起来就是"行里空了一半"。
static func row_center(r: Rect2, offset := 0.0) -> float:
	return r.position.y + r.size.y * 0.5 + offset


## 字号 `fs` 在行矩形里**垂直居中**时的文字基线（= `baseline_block()` 的单行特例）。
static func text_vcenter(r: Rect2, fs: int) -> float:
	return baseline_block(r, 1, 0.0, fs)


## 把 `lines` 行、行距 `step`、首行字号 `fs` 的**一行文字块整体垂直居中**在行矩形里，
## 返回**首行的基线** y。
##
## 行高会自适应（`list_metrics()`），所以行内所有"写死的基线"（原来那堆
## `r.position.y + 38.0`）必须换成它 —— 否则行变高了、字还挤在顶上，
## 看起来就是"行里空了一半"，比原来还难看。
##
## 推导：整块高度取 `(lines−1)·step + fs`，块心落在行心；
## `0.85·fs` 是"基线到块顶"的经验值（文字面框大致在基线上方 0.35 em 居中）。
static func baseline_block(r: Rect2, lines: int, step: float, fs: int) -> float:
	var span := float(maxi(lines - 1, 0)) * step + float(fs)
	return row_center(r, -span * 0.5 + float(fs) * 0.85)


## 列表版式：一次算出这一页的**行高 / 行数 / 首行位置**。
##
## 返回 `{ "row_h", "gap", "shown", "block_h", "top", "fit", "count", "avail" }`：
##   - `shown`   = 真正画得下的行数（`≤ count`，至少 1）
##   - `row_h`   = 放大后的行高，钳在 `[min_h, max_h]`
##   - `block_h` = 整块高度（含行距）
##   - `top`     = **第一行的顶**（整块在内容区里垂直居中之后）
##   - `fit`     = 按 `min_h` 能放几行（= "这一页要不要滚动"的判据）
##
## ## 为什么要"先按最小行高算 fit，再用 shown 反推行高"
## 行高和"放得下几行"互相依赖（行高↑ ⇒ 行数↓ ⇒ 又有空间 ⇒ 行高↑…），
## 直接解是个不收敛的循环。所以两步走：**先定"最多画几行"**（用最小行高，最保守），
## **再在这一行数下把行高摊开**。行数永远只减不增，就不会出现"放大行高之后
## 最后一行掉出内容区"这种自相矛盾的结果。
##
## `reserve_top` / `reserve_bottom` 是行块之外的固定占用（列表面板的内边距）——
## 居中要按"面板整体"算，所以它们必须参与 `avail` 与 `top`。
static func list_metrics(view: Vector2, count: int, min_h: float, gap: float, max_h: float,
		reserve_top := 0.0, reserve_bottom := 0.0) -> Dictionary:
	var reserve := reserve_top + reserve_bottom
	var avail_total := content_height(view)
	var avail := maxf(avail_total - reserve, min_h)
	var safe_gap := maxf(gap, 0.0)
	var fit := maxi(int(floor((avail + safe_gap) / maxf(min_h + safe_gap, 0.001))), 1)
	var shown := clampi(count, 1, fit)
	var row_h := clampf((avail - safe_gap * float(shown - 1)) / float(shown), min_h,
		maxf(max_h, min_h))
	var block_h := row_h * float(shown) + safe_gap * float(shown - 1)
	# 整块（含 reserve）在内容区里居中；只许往下让，不上浮到标题带里。
	var total_h := block_h + reserve
	var top := PANEL_TOP + maxf((avail_total - total_h) * 0.5, 0.0) + reserve_top
	return {
		"row_h": row_h, "gap": safe_gap, "shown": shown, "block_h": block_h,
		"top": top, "fit": fit, "count": count, "avail": avail,
	}


## 一页最多放几行（按**最小行高**算，最保守的那一档）。
## 至少 1 行 —— 一行都放不下也必须是"能选出东西的一页"，不能变成空页
##（空页的表现是"这一页什么都没有"，比排得难看难查得多）。
static func rows_that_fit(view: Vector2, min_h: float, gap: float, reserve := 0.0) -> int:
	return int(list_metrics(view, 1 << 20, min_h, gap, min_h, 0.0, reserve)["fit"])


## 滚动窗口：返回 `Vector2i(首行, 行数)`。
##
## **不循环**：到头就停住（`clampi`）。循环滚动会让"最后一项"和"第一项"贴在一起，
## 玩家分不清自己是不是已经回到开头 —— 那是最容易被当成 bug 的手感。
## 窗口尽量让聚焦项居中，但靠边时不再越界（所以第一项时 `first` 恒 0）。
static func scroll_window(count: int, index: int, visible: int) -> Vector2i:
	if count <= 0:
		return Vector2i(0, 0)
	var n := clampi(visible, 1, count)
	if count <= n:
		return Vector2i(0, count)
	return Vector2i(clampi(index - n / 2, 0, count - n), n)


## 竖排列表里的第 `i` 行（**`i` 是列表下标，不是屏幕序号**）。
## `first` = 窗口首行（窗口外的行会落到屏幕外，调用方只画窗口内的），
## `m` = `list_metrics()` 的结果（行高与"整块居中"之后的首行位置都在里面）。
static func list_row_rect(view: Vector2, i: int, first: int, m: Dictionary) -> Rect2:
	var row_h := float(m["row_h"])
	var gap := float(m["gap"])
	return Rect2(float(m.get("left", UILayout.MARGIN)), float(m["top"]) + float(i - first) * (row_h + gap),
		float(m.get("width", UILayout.frame_width(view))), row_h)


## 列表底部 y：**按窗口里真的画了几行算，不是按总数** —— 提示行/状态行跟着它走。
static func list_bottom_y(first: int, shown: int, m: Dictionary) -> float:
	var row_h := float(m["row_h"])
	var gap := float(m["gap"])
	return float(m["top"]) + float(shown) * (row_h + gap) - gap


## 滚动指示：右边缘一条细轨 + 滑块 + 右上角的 `▲ 3/5 ▼`。
##
## 只画"还有内容"的那一侧箭头：两边都画等于没说。
## 放得下时**什么都不画**（见上面第 3 条不变量）。
func _draw_scroll_indicator(count: int, index: int, visible: int, m: Dictionary,
		count_label := true) -> void:
	if count <= visible or count <= 0:
		return
	var w := scroll_window(count, index, visible)
	# 轨道的上下端跟着**行块**走（批 29 起行块会在内容区里居中，不再是固定的
	# `PANEL_TOP..list_bottom()`）—— 否则滚动条会拖到列表外面去。
	var top := float(m["top"])
	var bottom := list_bottom_y(w.x, w.y, m)
	var track_x := list_row_rect(size, w.x, w.x, m).end.x - 12.0
	var track_h := bottom - top
	if track_h <= 1.0:
		return
	draw_rect(Rect2(track_x, top, 3.0, track_h), Color(1.0, 1.0, 1.0, 0.10), true)
	var thumb_h := maxf(track_h * float(w.y) / float(count), 24.0)
	var span := maxi(count - w.y, 1)
	var thumb_y := top + (track_h - thumb_h) * float(w.x) / float(span)
	draw_rect(Rect2(track_x - 1.0, thumb_y, 5.0, thumb_h), Color(0.62, 0.86, 1.0, 0.85), true)
	# 计数标签排**行块的右上方**（原来是 `PANEL_TOP - 8` 那条固定空带）。
	#
	# ★63-22：`count_label` = false 的页面**不画它** —— 歌单页的行块右上方是
	# **页头**（只读歌单摘要 + `N/6`），两者会叠在同一块位置上。
	# 别用"把计数挪到别处"来绕：那一行本来就只有一块地方，挪到哪儿都会撞上别的东西。
	if count_label:
		_text_right(Vector2(track_x, top - 8.0),
			"%s %d/%d %s" % ["▲" if w.x > 0 else " ", index + 1, count,
				"▼" if w.x + w.y < count else " "], 13, Color(0.62, 0.86, 1.0))


# ============================================================ 标题 LOGO
#
# 用户给的 `title.png`（機動戦士ガンダム 閃光のハサウェイ）是**白字黑底**，
# 已经由 `tools/make_title_logo.gd` 按亮度抠成带 alpha 的贴图，运行时就是一张普通透明贴图。
#
# 贴图**取不到也不能让菜单坏掉**：`title_texture()` 找不到文件就返回 null，
# 绘制处退回原来的文字标题。这样"资源被挪走/名字改错"最坏也只是少一张图。
const TITLE_LOGO_PATH := "res://assets/ui/title.png"
## LOGO 在标题带里的目标高度；宽度按贴图原始比例算（1144×340 ≈ 3.36:1）。
const TITLE_LOGO_H := 96.0

static var _title_tex: Texture2D = null
static var _title_tex_tried := false


static func title_texture() -> Texture2D:
	if not _title_tex_tried:
		_title_tex_tried = true
		if ResourceLoader.exists(TITLE_LOGO_PATH):
			_title_tex = load(TITLE_LOGO_PATH) as Texture2D
	return _title_tex


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	if _font == null:
		_font = ThemeDB.fallback_font
	_tilt_material = ShaderMaterial.new()
	_tilt_material.shader = TEXT_TILT_SHADER
	_tilt_label = Label.new()
	_tilt_label.name = "SelectedMenuText"
	_tilt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tilt_label.material = _tilt_material
	MENU_VISUALS.prepare_selected_text(_tilt_label, _font, OUTLINE)
	_tilt_label.hide()
	add_child(_tilt_label)
	_home_view = HOME_VIEW.new()
	add_child(_home_view)
	_home_view.setup(self)
	# 初始不处理。进菜单由 main 调 open_menu() 打开。
	set_process(false)


## 由 main 调用：进入菜单。先关输入并上锁，锁走完 _process 自己恢复。
##
## ⚠️ 这里必须从**第一页**开始（1.1 起第一页是"选择模式"）。
## 早先写的是 `stage = Stage.SUIT`（那时第一页是选机体），加进模式页之后
## 忘了改这一行：`_show_menu()` 里明明设了 MODE，紧接着就被 `open_menu()` 覆盖成 SUIT，
## 表现就是**进游戏直接跳到选机体**、玩家根本没机会先选"对战 / 训练"
## （用户实测反馈的"开始游戏先选择模式先"就是这个）。
func open_menu(lockout := 0.35) -> void:
	stage = Stage.MODE
	# ★63-19：换页时把鼠标意图清干净（上次菜单里攒下的点击/滚轮不该在这里落地）。
	_mouse_intent = Intent.NONE
	_mouse_intent_frame = -1
	_mouse_wheel = 0
	_hover_mute_until = 0.0
	visible = true
	active = false
	input_lockout = lockout
	_await_release = true
	set_process(true)
	queue_redraw()


## 由 main 调用：离开菜单。
##
## **必须把 `_process` 一起停掉**，光设 `visible = false` 是不够的 ——
## Control 隐藏了照样会 `_process`。不停的话会出现这个隐蔽 bug：
## 结算页那一下 Enter 会被 main（回主菜单）和菜单（推进到下一步）**在同一帧各吃一次**，
## 于是玩家按一下键跳过了"选机体"，而且因为菜单此时已经停在"选难度"，
## 下一次 Enter 就直接开局。这个和 main/菜单谁先处理无关，是"菜单压根不该在跑"。
func close_menu() -> void:
	active = false
	visible = false
	set_process(false)
	_tick_bgm_page()


func _process(delta: float) -> void:
	_tick_super_notice(delta)
	_time += delta
	# 等待对手的秒表（见 `_lan_wait_elapsed`）：只要在等就一直在走。
	if _lan_wait:
		_lan_wait_elapsed += delta
	_update_pad_edges()
	if stage == Stage.SETTINGS and (not is_instance_valid(_home_view) or _home_view.can_adjust()):
		# ★63-23：设置页有两个子屏，左/右调值各走自己的步进器。
		# ⚠️ 两个步进器**共用** `_step_dir()` 里那套长按连调 ——
		# 各写一份的症状是"音量页调值没有连发"，而那是只有手指知道的差别。
		if settings_sub == SET_SUB_VOLUME:
			_volume_step(delta)
		else:
			_setting_step(delta)
	_tick_bgm_page()
	# 锁计时。锁走完之后自己把 active 打开 —— 这样不依赖 main 与菜单谁先处理这一帧。
	if input_lockout > 0.0:
		input_lockout = maxf(input_lockout - delta, 0.0)
		if input_lockout <= 0.0 and visible:
			active = true
	# 先等按键松开：上一个界面的那一下输入可能延迟很多帧才到，必须整个吞掉
	if _await_release:
		if not Input.is_action_pressed("confirm") and not Input.is_action_pressed("fire_gun"):
			_await_release = false
	if active and input_lockout <= 0.0 and not _await_release:
		_read_input()
	# ★63-19 鼠标意图只活一帧：这一帧没被 `_read_input()` 消费掉的，就地作废 ——
	# 免得留下「一发过期的点击」在下一帧、在另一个页面上落地。
	# （正常必然同帧消费：`_handle_mouse()` 的闸门与本行**逐字相同**。）
	if _mouse_intent_frame != Engine.get_process_frames():
		_mouse_intent = Intent.NONE
	_mouse_wheel = 0
	# Both input devices share selection; the pointer controls only the text plane.
	var choice := _presentation_choice()
	if choice != _choice_key:
		_choice_key = choice
		_choice_age = 0.0
	else:
		_choice_age += delta
	var target := Vector2.ZERO
	var index := _focus_index()
	if _pointer_tilt_active and index >= 0 and not InputSetup.using_gamepad:
		var g := _list_geometry()
		if not g.is_empty():
			target = MENU_VISUALS.tilt_target(get_local_mouse_position(), row_rect(size, g, index), Settings.reduce_motion)
	_text_tilt = Vector2.ZERO if Settings.reduce_motion else _text_tilt.lerp(target, 1.0 - exp(-delta * 14.0))
	if is_instance_valid(_home_view): _home_view.sync(delta)
	# 退出确认窗口倒计时
	_quit_armed = maxf(_quit_armed - delta, 0.0)
	queue_redraw()


func selected_suit() -> int:
	# ⚠️ 走 `active_suit_list()` 而不是直接 `SUITS[suit_index]`：
	# 编队战里机体池是**按阵营过滤**的（马夫蒂 3 台 / 联邦 2 台），
	# 而 `suit_index` 是那个小池子里的下标。
	var lst := active_suit_list()
	if lst.is_empty():
		return SuitProfile.Id.XI
	return lst[clampi(suit_index, 0, lst.size() - 1)]


## ★63-9 B4：**敌机页现在列的是哪几台** —— 这个池子**随模式（和阵营）变**。
##
## · **对战**：还是原来那三台（`ENEMY_SUITS`，含跨阵营的柯西 —— 镜像战靠它，
##   而且「选谁就打谁」本来就是对战那一条路的需求）。
## · **编队战**：只能是**敌方阵营的 ACE 池**。玩家先选阵营，敌方就是另一阵营：
##     玩家选马夫蒂 ⇒ 敌方 = 联邦 ⇒ {佩涅罗佩, 阿利宙斯}
##     玩家选联邦   ⇒ 敌方 = 马夫蒂 ⇒ {柯西}
##
## ⚠️ 编队战下**不能**沿用写死的 `ENEMY_SUITS`：它含柯西，而柯西是**马夫蒂**的 ACE ——
## 玩家选联邦时把柯西送到对面就是**跨阵营**，正是 `battle_formation.gd` 头注里
## 已经踩过、且**不会报任何错**的那类坑（只能靠不变量测试抓）。
func enemy_pool() -> Array:
	if SuitProfile.is_thunderbolt(selected_suit()):return [SuitProfile.thunderbolt_opponent(selected_suit())]
	if squad_mode():
		return BattleFormation.roster_of(
			BattleFormation.opposing(side_index_to_side())).aces
	return [SuitProfile.Id.GP03D, SuitProfile.Id.NEUE_ZIEL] if selected_suit() in [SuitProfile.Id.GP03D, SuitProfile.Id.NEUE_ZIEL] else ENEMY_SUITS.filter(func(id):return id not in [SuitProfile.Id.GP03D,SuitProfile.Id.NEUE_ZIEL])


## 敌机页当前的下标 —— **夹在池子范围内**。
##
## ⚠️ 必须夹：`enemy_pool()` 的长短**随模式与阵营变**（编队战里把阵营从联邦
## 换成马夫蒂，候选就从 2 台掉到 1 台），而 `enemy_index` 是**跨模式留下来的**成员
## 变量。不夹的话，上一局挑的是池子里第 2 台，这一局直接越界（`_draw` 当场抛错）。
func enemy_index_now() -> int:
	var pool := enemy_pool()
	if pool.is_empty():
		return 0
	return clampi(enemy_index, 0, pool.size() - 1)


## 当前选中的敌机（对战 / 编队战共用；编队战下它就是**敌方 ACE**）。
func selected_enemy() -> int:
	var pool := enemy_pool()
	if pool.is_empty():
		return SuitProfile.Id.PENELOPE
	return pool[enemy_index_now()]


func selected_level() -> int:
	var levels:=Difficulty.all_levels(Game.super_hard_unlocked)
	return levels[clampi(diff_index,0,levels.size()-1)]


func active_map_list() -> Array:
	if endless_mode():return [MapDef.Id.LEO]
	var opponent := Net.remote_suit if lan_mode() else selected_enemy()
	if Net.requires_axis(selected_suit(),opponent):
		return [MapDef.Id.AXIS]
	if selected_suit() in [SuitProfile.Id.GP03D, SuitProfile.Id.NEUE_ZIEL]:
		return [MapDef.Id.LEO]
	if SuitProfile.is_thunderbolt(selected_suit()):
		return [MapDef.Id.COLONY_RUINS]
	return MapDef.versus_maps()


func selected_map() -> int:
	var maps := active_map_list()
	return maps[clampi(map_index, 0, maps.size() - 1)]


## 光标所在的分组（顶层模式页那一行）。
func current_group() -> Dictionary:
	return MODE_GROUPS[clampi(mode_index, 0, MODE_GROUPS.size() - 1)]


## 是不是停在了「对战模式」那一组上（只有它有子页）。
func in_battle_group() -> bool:
	return mode_index == BATTLE_GROUP


## **这一局是什么模式** —— 两层（分组 + 形式）在这里合成**一个**答案。
##
## ⚠️ 单项分组（训练 / 联机）**不看 `battle_index`**：那一组只有一项，
## 而 `battle_index` 是给对战模式用的（"上次在王战页选了小队战"不该影响训练局）。
func selected_mode() -> int:
	var ms: Array = current_group()["modes"]
	if ms.size() <= 1:
		return int(ms[0])
	return int(ms[clampi(battle_index, 0, ms.size() - 1)])


## 把菜单直接摆到"选了某个模式"的状态：找到它所属的分组并**连组内形式一起摆好**。
##
## 存在的理由是可测与可靠：`MODE_GROUPS` 是唯一真源，而"模式 → 分组 → 形式"
## 这条换算到处都要用（测试、以及将来任何"从外部指定模式"的入口）。
## 以前调用方自己写 `mode_index = MODES.find(mode)` —— 那样一旦找不到就是 **−1**，
## 而**负下标会取到最后一个元素**（悄悄变成"联机"），红得莫名其妙（这个坑踩过一次）。
## 找不到模式时这里**什么都不改**，`false` 是唯一的信号。
func select_mode(mode: int) -> bool:
	for gi in MODE_GROUPS.size():
		var ms: Array = MODE_GROUPS[gi]["modes"]
		var at := ms.find(mode)
		if at < 0:
			continue
		mode_index = gi
		if ms.size() > 1:
			battle_index = at
		return true
	return false


func training_mode() -> bool:
	return selected_mode() == Game.MatchMode.TRAINING


func challenge_mode() -> bool:
	return selected_mode() == Game.MatchMode.CHALLENGE


func lan_mode() -> bool:
	return selected_mode() == Game.MatchMode.LAN


# ============================================================ ★63-24 无限强化演习

## 开局自选几张（设计 §5.6 / R14：**3 张**）。
const ENDLESS_PICK_COUNT := 3
## 那一行"还差几张"的提示语要用的主语（页面与页脚各印一次，别写两份字面量）。
const ENDLESS_TITLE := preload("res://scripts/data/endless_script.gd").MODE_TITLE

## 这一局是不是无限强化演习。
func endless_mode() -> bool:
	return selected_mode() == Game.MatchMode.ENDLESS


## 开局配置页的**可选卡池** —— 真源在 `UpgradeCard.basic_pool()`（数据层）。
##
## ⚠️ 这里**不写第二份名单**：池子随自机变（`viable_for` 过 `has_saber` /
## `cannon_enabled` 这类能力谓词），抄一份到菜单里 = 加了新词条菜单里看不到，
## 而"看不到"**不报错**（设计 §11.1 第 8 条原本写的 `const ENDLESS_CARDS` 池，
## 现在由这个函数取代）。
## ⚠️ `SuitProfile.by_id()` 每次新建一份 —— 这里只用它**读**那两个谓词，写不到静态表。
static func endless_pool(suit_id: int) -> Array[UpgradeCard]:
	return UpgradeCard.basic_pool(SuitProfile.by_id(suit_id))


## 当前自机的卡池（带缓存，键是机体 id）。
func endless_pool_now() -> Array[UpgradeCard]:
	var sid := selected_suit()
	if _endless_pool_key != sid or _endless_pool_cache.is_empty():
		_endless_pool_cache = endless_pool(sid)
		_endless_pool_key = sid
	return _endless_pool_cache


## 配置页最后那一行是「出击」**行动行**（照设置页动作行的做法，
## 见 `_setting_is_action()`）—— 勾卡与出击**共用一个确认键**，
## 所以出击必须有自己的行，不能与"勾选第 N 张卡"挤在同一个按键语义里。
## ⇒ 列表长度 = 卡池 + 1。
func endless_row_count() -> int:
	return endless_pool_now().size() + 1


## 焦点是不是停在「出击」行动行上。
func endless_is_action_row() -> bool:
	return endless_index >= endless_pool_now().size()


## 勾满 3 张了吗 —— **出击闸门**（不足 3 张时确认键不响应）。
func endless_ready() -> bool:
	return endless_picks.size() >= ENDLESS_PICK_COUNT


## 还差几张（页脚提示用）。
func endless_missing() -> int:
	return maxi(ENDLESS_PICK_COUNT - endless_picks.size(), 0)


func endless_has(cid: String) -> bool:
	return endless_picks.has(cid)


## 勾选 / 取消一张卡。返回是否真的改变了选择（调用方据此决定要不要播音效）。
##
## 两条规则都收口在这里：① 满了**不再接受新的** —— 而不是顶掉一张
##（顶掉哪一张没法解释给玩家听，而且"我明明按了却没反应"比"满了"更难懂）；
## ② 同一张再按一次 = 取消。
func endless_toggle(cid: String) -> bool:
	var at := endless_picks.find(cid)
	if at >= 0:
		endless_picks.remove_at(at)
		return true
	if endless_picks.size() >= ENDLESS_PICK_COUNT:
		return false
	endless_picks.append(cid)
	return true


## 机体换了 ⇒ 卡池换了 ⇒ 把**不在新池里**的勾选剔掉。
##
## ⚠️ 剔的判据是"这一张还在不在池里"（按 `id`），**不是"全部清空"**：
## 玩家勾了 3 张、退回上一层又进来（还是同一台机），清空会让他白勾一次。
## ⚠️ 但也**必须剔**：柯西没有大炮 ⇒ 池里没有重炮卡 ⇒ 留着那条 `id` 的话，
## `_launch()` 会把一张**这台机根本装不上**的卡交给 main，
## 而 `UpgradeCard.by_id()` 找得到它（全库里有）、施加时静默写进了不存在的字段。
func endless_prune_picks() -> void:
	var legal := {}
	for c in endless_pool_now():
		legal[c.id] = true
	var kept: Array[String] = []
	for cid: String in endless_picks:
		if legal.has(cid):
			kept.append(cid)
	endless_picks = kept
	endless_index = clampi(endless_index, 0, maxi(endless_pool_now().size() - 1, 0))


## 当前机体在挑战脚本里的可选遭遇（柯西两场，另外两台各一场）。
func encounters() -> Array:
	return ChallengeScript.for_suit(selected_suit())


func selected_encounter() -> ChallengeScript.Encounter:
	var list := encounters()
	if list.is_empty():
		return null
	return list[clampi(encounter_index, 0, list.size() - 1)]


## 「在模式页按下确认」之后**该去哪一页** —— **唯一真源**（两个入口都只调它）。
##
## 返回 `-1` = 这一路**不经过页面**、直接出击（剧情模式：选完就被 `main` 拦到战役图）。
##
## ⚠️⚠️ 为什么必须有这个函数（2026-10-11）：模式页有**两个入口** ——
##   · `_read_input()` 的 `Stage.MODE` 分支（键鼠 / 手柄 / 鼠标点击都在这一支）；
##   · 极简首页 `menu_home.open_entry()`（它自己接输入、自己设 `stage`）。
## 两边各写一遍 `if/elif` 的后果是**改一处、从另一处进去还是老流程** ——
## 联机那一步就这么漏过一次：`_read_input()` 已经改成"直接进联机页"，
## 但从首页点「局域网联机」**仍然先走 阵营 → 机体 两页**（看起来像没改）。
## ⇒ 规则收在这里，两个入口谁也不许再自己判。
func mode_entry_stage() -> int:
	if selected_mode() == Game.MatchMode.CHALLENGE:
		# 剧情模式只有一步（`step_labels()`）：选完模式就出击。
		return -1
	if current_group()["modes"].size() > 1:
		# 「对战模式」有两个形式 ⇒ 进子页再挑（王牌战 / 小队战）。
		return Stage.BATTLE
	if lan_mode():
		# ★ 2026-10-11（用户：「**先创建房间之后，再在房间里面决定对战模式和机体**」）：
		# 联机**不再**先走「选阵营 → 选机体」两步 —— 选完模式**直接进联机页**建房 / 加入；
		# 阵营、机体、对战形式都在**房间界面**里决定（`LOBBY_ROWS`）。
		# 那两步原先排在建房**之前**，等于逼玩家先做两个随时会被房间设置推翻的决定
		#（房间里一改对抗形式，机体表就换了）。
		# ⇒ 联机 `step_labels()` 从 4 步变 2 步，`step_index(Stage.LAN)` 从 3 变 1。
		return Stage.LAN
	# 其余：小队战要按阵营过滤机体表 ⇒ 先阵营；王牌战 / 训练直接选机体。
	return Stage.SIDE if side_filters_suits() else Stage.SUIT


## 流程步数：对战 5 步（模式/机体/敌人/难度/地图）、挑战 4 步（模式/机体/遭遇/**难度**）、
## 训练 2 步、联机 2 步（模式/出战）。
##
## 挑战为什么**要**难度页（用户已拍板）：挑战是"剧情还原"，难度是"玩家自己选的强度"，
## 两者不冲突。反过来把难度钉死，打不过时唯一的出路就变成"换机体"，
## 而挑战的机体选择恰恰是剧情的一部分 —— 那等于逼玩家放弃剧情。
## 更要紧的是：不显示难度页**不代表没有难度** —— `_launch()` 照旧把 `selected_level()`
## 传出去，于是挑战局的难度变成"菜单里那个下标当时的值"（默认中等，或被上一局对战改过），
## 一个玩家看不见却真实生效的隐藏状态。这是必须修掉的一类。
func step_labels() -> Array:
	match selected_mode():
		Game.MatchMode.SQUAD:
			# 编队战六步：比对战多一步"选择阵营"（阵营决定能开哪些机）。
			return ["① 选择模式", "② 选择阵营", "③ 选择机体", "④ 选择难度", "⑤ 选择地图"]
		Game.MatchMode.CHALLENGE:
			# ★ 轮 C（2026-09-29）：**剧情模式只有一步** —— 选完模式就出击。
			#
			# 旧的挑战向导是 4 页（模式 / 机体 / 遭遇 / 难度），那是**上一版**的流程：
			# 机体页选的那台机、遭遇页选的那 4 场（`ChallengeScript.for_suit()`），
			# 在剧情模式下**两样都被丢掉** —— 机体由 `Mission.player_suit` 定、
			# 关卡由**战役图**选（见 `main._resolve_campaign_match()`）。
			# 留着那两页 = 先逼玩家做两个**不作数**的决定，再进战役图重做一遍。
			#
			# ⇒ 这一页选完直接 `_launch()`，main 把它拦到**战役图**（§6.1 的循环前门）。
			# 选关与难度都在那一页上 —— 所以这一条**不是**"少了一步"，
			# 而是那一步（选关）**搬到了它该在的地方**。
			return ["① 选择模式"]
		Game.MatchMode.TRAINING:
			# 1.2 第二十五轮：训练多一步"选训练项目"（自由打靶 / 新手教学）。
			# 用户要求"新手教学和靶场在**同一页面**"，所以它们是**同一页的两行**，
			# 而不是两个模式。
			return ["① 选择模式", "② 选择机体", "③ 训练项目"]
		Game.MatchMode.LAN:
			# ⚠️ 2026-10-11（用户：「**先创建房间之后，再在房间里面决定对战模式和机体**」）：
			# 联机从 **4 步**收回 **2 步** —— 「选择阵营」「选择机体」两步**搬进房间界面**。
			#
			# 这不算"砍功能"：那两步在**建房之前**做，等于先逼玩家做两个**随时会被
			# 房间设置推翻**的决定（房间里一改对抗形式，机体表就换了 —— 王牌战只认
			# 三台 ACE，小队战按阵营过滤）。搬进房间之后，决定顺序与"谁能改"
			#（房间设置归主机、双方都看得见）才对得上。
			return ["① 选择模式", "② 创建 / 加入房间"]
		Game.MatchMode.ENDLESS:
			# ★63-24：三步 —— 选模式 → 选机体 → 改装配置（自选 3 张基础卡，§5.6）。
			#
			# ⚠️ 这一版**没有地图页**：地图由 `main._resolve_match()` 的 `ENDLESS`
			# 分支强制给一张（设计 §11.3 第 25 条），所以流程里没有"选地图"这一步。
			# 难度同理不给 —— 本模式的强度曲线是**局内时间**一条轴（§6.4 拍板），
			# 玩家在开局前选难度等于给它加第二条轴。
			return ["① 选择模式", "② 选择机体", "③ 改装配置"]
		_:
			return ["① 选择模式", "② 选择机体", "③ 选择敌人", "④ 选择难度", "⑤ 选择地图"]


func step_count() -> int:
	return step_labels().size()


## 步骤条上要亮第几个点。
## 按"这个 Stage 在流程里排第几"算，而不是按 Stage 的枚举值 ——
## 枚举顺序和流程顺序是两件事（`ENCOUNTER` 在枚举里排在 `MAP` 后面，
## 但在挑战流程里它是第 3 步）。
func step_index() -> int:
	match stage:
		Stage.MODE, Stage.BATTLE:
			# 「对战模式」子页**算第 ① 步的一部分**（"选模式"这件事还没结束）：
			# 子页不是新的一步，所以 `step_labels()` 一个字都不用改 ——
			# 分组只是把"选模式"这一个决策拆成两屏显示而已。
			return 0
		Stage.SIDE:
			return 1
		Stage.SUIT:
			# 编队战 / 联机里机体页是第 3 步（第 2 步是阵营），其余模式是第 2 步。
			return 2 if side_filters_suits() else 1
		Stage.TRAINING:
			# 训练项目是第 3 步（模式 → 机体 → 项目）。
			return 2
		Stage.ENEMY, Stage.ENCOUNTER:
			return 2
		Stage.DIFFICULTY:
			# 对战/挑战都有难度页（挑战是第 4 步）；训练没有这一页
			return 2 if training_mode() else 3
		Stage.MAP:
			return 4
		Stage.LAN:
			# ⚠️ 2026-10-11：联机流程收回"模式 → 创建 / 加入房间"（`step_labels()` 印 2 步），
			# 联机页是其中的第 2 步（下标 1）。
			# ⚠️ 这个分支以前缺失 → 返回 −1 → **联机页的步骤条一个点都不亮**
			#（和"地图页永远点不亮"是同一类漏）。改流程时**必须同步改这里**，
			# 否则步骤条会指着上一页。
			return 1
		Stage.ENDLESS:
			# ★63-24：演习是"模式 → 机体 → 改装配置"三步，配置页是第 ③ 步（下标 2）。
			# ⚠️ 漏了这一条的表现与联机页当年一模一样：**步骤条一个点都不亮**，
			# 而且不报错（`step_index()` 落到末尾 `return -1`）。
			return 2
	return -1


## 退出游戏。
##
## 顺手把设置存一次：玩家可能在设置页调完音量就直接退了，
## 不存的话那些改动会丢（虽然每次改动其实都已经存过，这里是双保险）。
func quit_game() -> void:
	Settings.save_config()
	get_tree().quit()


## 设置页里"按 Enter 执行"的那些行（不是左右调值的那种）。
##
## ⚠️ 制作人模式那一行**也算**（`PRODUCER_KEY`）：它在不开时是隐形的，
## 但它不是一个"能左右拧的值" —— 左右拧它只会让人以为这一行坏了
##（隐形行本来就已经"看着像没选中任何东西"了）。开它的手势只有一个：Enter。
func _setting_is_action(key: String) -> bool:
	return key == "back" or key == "quit" or key == "keys" or key == PRODUCER_KEY


# ============================================================ 手柄导航

## 左摇杆的"刚推过去"边沿值（−1 / 0 / +1），每帧更新一次。
##
## ⚠️ 十字键**必须显式认**（1.2 改动之后）：它原来绑在 `roll_*/pitch_*` 上，
## 菜单"顺带"就能导航；但那一轮为了"每个方向做功能键"把十字键改成了
## 飞行功能（↑ 切换目标 / ↓ 干扰弹 / ← 锁定镜头 / → 切换武器），
## 于是**手柄在菜单里彻底不能导航了**（用户实测："选择还是乱的"）。
## 现在两条轴的判定里把这四个动作也认下来 —— 键盘鼠标与手柄各走各的，
## 而"菜单 vs 飞行"是阶段互斥的，所以一键两义在这里是安全的。
## **摇杆是轴，没有 just_pressed 的概念**，只能自己判"过阈值的那一下"，
## 否则一直推着会每帧都触发、选项狂奔。
var _pad_dx := 0
var _pad_dy := 0
var _pad_x_prev := 0.0
var _pad_y_prev := 0.0


func _update_pad_edges() -> void:
	var dev := PlayerController.active_joypad()
	var x := 0.0 if dev < 0 else Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
	var y := 0.0 if dev < 0 else Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
	_pad_dx = _edge(x, _pad_x_prev)
	_pad_dy = _edge(y, _pad_y_prev)
	_pad_x_prev = x
	_pad_y_prev = y


static func _edge(v: float, prev: float) -> int:
	if v > 0.55 and prev <= 0.55:
		return 1
	if v < -0.55 and prev >= -0.55:
		return -1
	return 0


## 摇杆当前是否还推着（长按连调要用）。
func _pad_held_x() -> int:
	var dev := PlayerController.active_joypad()
	if dev < 0:
		return 0
	var v := Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
	if v > 0.55:
		return 1
	if v < -0.55:
		return -1
	return 0


## 横向导航：键盘 / 十字键 / 左摇杆三选一，返回 −1 / 0 / +1。
func _nav_x() -> int:
	var d := 0
	# ⚠️ **只用 A/D**（1.2 用户反馈："主菜单的 ad 和 ws 的选择很难受，乱七八糟的"）。
	# 原来这里把 `yaw_left/right`（Q/E）也当横选，而 `_nav_y()` 同样认它们 ——
	# 于是 Q/E 同时喂给两个轴，"按一下不知道会跳到哪"。现在严格分工：
	# **横 = A/D，竖 = W/S**，Q/E 退出菜单导航。
	if Input.is_action_just_pressed("roll_left") or Input.is_action_just_pressed("missile_mode"):
		d = -1
	elif Input.is_action_just_pressed("roll_right") or Input.is_action_just_pressed("switch_weapon"):
		d = 1
	return d if d != 0 else _pad_dx


## 菜单纵向导航用哪些动作（数组顺序 = 优先权）。
##
## ⚠️ **菜单的"上"是 `pitch_nose_down`（W / ↑）** —— 看着像写反了，但它是对的。
## 两套约定本来就不一样：
##   - **飞行**走"真实操纵杆"约定（Ace Combat 同款，见 README §2）：
##     `pitch_nose_up` = 拉杆 = **S / ↓** → 机头抬起；
##   - **菜单**走标准 UI 约定：**W / ↑ = 上一个，S / ↓ = 下一个**。
## 动作名是按**飞行**语义起的，所以"菜单的上"只能落在 `pitch_nose_down` 上。
##
## 1.2 用户实测报的 bug 就是这两套约定被混用了：
## 「整个主菜单的上下选择都是颠倒的，按 s 往上按 w 往下」——
## 当时 `_nav_y()` 直接把 `pitch_nose_up`（= S / ↓）当成"上"。
## ⚠️ 注意它**同时**把方向键也弄反了（↓ 也是 `pitch_nose_up`）—— 四个键是一起错的，
## 所以"对调这两组"就能一次修好四个，而不是给 W/S 打一个特例补丁。
##
## 手柄那一侧**不需要**同样处理：`JOY_AXIS_LEFT_Y` 是"往下为正"，
## `_pad_dy` 推杆向下给 +1，本来就对得上标准 UI 约定（别顺手把它也翻了）。
const NAV_UP_ACTIONS := ["pitch_nose_down", "switch_target"]
const NAV_DOWN_ACTIONS := ["pitch_nose_up", "flares"]


## 纵向导航：键盘 / 十字键 / 左摇杆三选一，返回 −1 / 0 / +1（**−1 = 上**）。
func _nav_y() -> int:
	var pressed: Array = []
	for a: String in NAV_UP_ACTIONS + NAV_DOWN_ACTIONS:
		if Input.is_action_just_pressed(a):
			pressed.append(a)
	var d := nav_delta_y(pressed)
	return d if d != 0 else _pad_dy


## 纯函数：给定"本帧被按下的动作名"，返回纵向导航增量（**−1 = 上**）。
##
## 抽成纯函数只有一个理由：**可测**。`_nav_y()` 自己那部分逻辑读的是
## `Input.is_action_just_pressed`，而它在无头环境里靠注入不可靠
## （工程里早有结论，见 `suite_round._result_flow()` 的注释），
## 所以把"方向 → 增量"这一段拿出来，测试就能不注入任何输入地锁住它。
##
## ⚠️ 只测"`NAV_UP_ACTIONS` 里有 W"是**不够**的：万一哪天这里把正负号写反，
## 那几条照样全绿 —— 行为本身必须单独锁一条。
static func nav_delta_y(pressed_actions: Array) -> int:
	for a: String in NAV_UP_ACTIONS:
		if pressed_actions.has(a):
			return -1
	for a: String in NAV_DOWN_ACTIONS:
		if pressed_actions.has(a):
			return 1
	return 0


## 按 `nav_axis()` 查出来的轴取本页的导航增量（−1 / 0 / +1）。
func _axis_delta(axis: int) -> int:
	match axis:
		Nav.X:
			return _nav_x()
		Nav.Y:
			return _nav_y()
	return 0


func _read_input() -> void:
	# ---- ★63-19 鼠标意图：**就在消费点折成与键盘相同的三个量**。----
	# 鼠标不另写一套 `match stage` —— 它只产出意图；折成
	# `_mi_back` / `_mi_ok` / `_mi_d` 之后，由下面**同一段键盘代码**消费。
	# 否则必然出现"键盘能走、鼠标走到某一页断掉"，而且只有走到那一页才发现。
	_mi_back = _mouse_intent == Intent.BACK
	_mi_ok = _mouse_intent == Intent.CONFIRM
	_mi_d = _mouse_wheel
	_mouse_intent = Intent.NONE
	_mouse_wheel = 0
	if is_instance_valid(_home_view) and _home_view.handles_stage():
		_home_view.read_input()
		return
	# 设置页可以从任何一步用 P 打开（也可以再按一次 P 关掉）。
	# ⚠️ 重绑页不响应 P：换键按到一半被拽去别的页，玩家会不知道自己刚改了什么。
	# ⚠️ 密码页同理**必须排除**：P 在这里只会把 `_settings_return_stage` 记成
	# `PASSWORD`，于是"返回设置页"会把人送回密码页 —— 一条绕不出去的回路。
	# 密码页里的 P 走 `_read_password_input()`，语义和 Esc 一样（返回）。
	if stage != Stage.SETTINGS and stage != Stage.KEYS and stage != Stage.BGM \
			and stage != Stage.PASSWORD \
			and Input.is_action_just_pressed("open_settings"):
		_settings_return_stage = stage
		# ★63-23：从外面按 P 进来，一定落在**设置页主屏**。
		# 目前"音量细分"只能退到主屏、退不出设置，所以 `settings_sub` 不可能带进来 ——
		# 但这一行是"将来有人给音量页加了直达出口"时的安全网（漏了的话，
		# 玩家下次按 P 会**直接掉进音量页**，而他会以为设置页变了）。
		settings_sub = SET_SUB_MAIN
		stage = Stage.SETTINGS
		Audio.play_ui("ui_confirm")
		return

	# 本页的导航增量：**查 `nav_axis()` 那张表**，不在这里逐页写轴
	# （敌人页就是"逐页写"漏掉的那一处：版式是竖排行，输入却写了横轴）。
	var nav_d := _axis_delta(nav_axis(stage))
	# 鼠标滚轮：键盘没给方向时才用它（同帧两个来源不叠加）。
	if nav_d == 0:
		nav_d = _mi_d

	match stage:
		Stage.MODE:
			# 第一页按 Esc / 手柄 B = 退出游戏。这是"返回上一层"的统一语义：
			# 结算页 Esc 回主菜单，主菜单第一步 Esc 就退出。
			#
			# ⚠️ 但**必须两次确认**：手柄上 B 就是 menu_back，
			# 而这一页正好是玩家最爱乱按的一页 —— 一下 B 就把游戏关掉太狠了。
			# 第一次按只是把页脚提示换成"再按一次退出"，窗口内再按才真退。
			if (Input.is_action_just_pressed("menu_back") or _mi_back):
				if _quit_armed > 0.0:
					quit_game()
				else:
					_quit_armed = QUIT_CONFIRM_WINDOW
					Audio.play_ui("ui_return")
				return
			var dm := nav_d
			if dm != 0:
				mode_index = posmod(mode_index + dm, MODE_GROUPS.size())
				Audio.play_ui("ui_select")
			if (Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("fire_gun") or _mi_ok):
				# ★ 轮 C：**剧情模式在这一页就结束**（它是 1 步，见 `step_labels()`）——
				# 它的"选关"发生在**战役图**上，机体与地图由 `Mission` 定。
				# ⚠️ 必须拦在下面那个"单项分组"分支**之前**：剧情挑战也是单项分组，
				# 不拦的话它会像训练/联机那样继续往机体页走 —— 而那正是这一版要拿掉的旧向导。
				# ⚠️ 同理**不能**靠"把 `Stage.SUIT` 的确认改成直接出击"来修：
				# 那样玩家还是得先看一眼机体页（选的那台机还不作数）。
				# ⚠️ 去哪一页由 `mode_entry_stage()` 一个函数说了算（**唯一真源**）——
				# 极简首页 `menu_home.open_entry()` 走的是**同一个**函数。
				# 各写一遍 if/elif 的后果是"改一处、从另一处进去还是老流程"（联机漏过一次）。
				var nxt := mode_entry_stage()
				if nxt < 0:
					# 剧情模式：选完模式直接出击（`main` 拦到战役图）。
					_launch()
					return
				stage = nxt
				Audio.play_ui("ui_confirm")
		Stage.BATTLE:
			# 「对战模式」子页：两项（王牌战 / 小队战），竖排。
			var db := nav_d
			if db != 0:
				battle_index = posmod(battle_index + db, battle_modes().size())
				Audio.play_ui("ui_select")
			if (Input.is_action_just_pressed("menu_back") or _mi_back):
				stage = Stage.MODE
				Audio.play_ui("ui_return")
			elif (Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("fire_gun") or _mi_ok):
				# 小队战要选阵营（阵营过滤机体表），王牌战不需要（三台 ACE 不分阵营）。
				stage = Stage.SIDE if side_filters_suits() else Stage.SUIT
				Audio.play_ui("ui_confirm")
		Stage.SIDE:
			var ds := nav_d
			if ds != 0:
				side_index = posmod(side_index + ds, side_choices().size())
				# 换阵营 ⇒ 池子换了 ⇒ 机体下标必须归零。
				# 不归零的话"马夫蒂选到第 2 台、切到联邦"会停在不存在的下标上
				#（联邦只有 2 台可选），表现是卡片高亮丢失或索引越界。
				suit_index = 0
				Audio.play_ui("ui_select")
			if (Input.is_action_just_pressed("menu_back") or _mi_back):
				# 从哪来的回哪去：对战模式那一组走的是子页，训练/联机直接在第一页。
				stage = Stage.BATTLE if in_battle_group() else Stage.MODE
				Audio.play_ui("ui_return")
			elif (Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("fire_gun") or _mi_ok):
				stage = Stage.SUIT
				Audio.play_ui("ui_confirm")
		Stage.SUIT:
			var dx := nav_d
			if dx != 0:
				var n := active_suit_list().size()
				suit_index = posmod(suit_index + dx, maxi(n, 1))
				# 换机体之后，挑战遭遇表要跟着重算（柯西有两场、另外两台各一场），
				# 否则会指着上一台机的脚本（越界或串戏）。
				encounter_index = 0
				# ★63-24：演习的卡池也跟着换（柯西没有重炮卡）⇒ 剔掉装不上的勾选。
				# 与 `encounter_index = 0` 是同一件事的两面：换机体 ⇒ 下游那张表要重算。
				endless_prune_picks()
				Audio.play_ui("ui_select")
			if (Input.is_action_just_pressed("menu_back") or _mi_back):
				# 联机/小队战都先经过阵营页；对战模式那一组再往上一层是子页。
				if side_filters_suits():
					stage = Stage.SIDE
				else:
					stage = Stage.BATTLE if in_battle_group() else Stage.MODE
				Audio.play_ui("ui_return")
			elif (Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("fire_gun") or _mi_ok):
				Audio.play_ui("ui_confirm")
				if challenge_mode():
					stage = Stage.ENCOUNTER
				elif training_mode():
					# 1.2 第二十五轮：训练多了"选训练项目"这一步（自由打靶 / 新手教学）。
					stage = Stage.TRAINING
				elif lan_mode():
					stage = Stage.LAN
				elif endless_mode():
					# ★63-24：演习多了"自选 3 张基础卡"这一步（§5.6 / R14）。
					# ⚠️ 换机体之后池子变过（`endless_prune_picks()`），所以进配置页前
					# 再把焦点钳一次 —— 不然光标会停在一个不存在的行上。
					endless_index = clampi(endless_index, 0,
						maxi(endless_pool_now().size() - 1, 0))
					stage = Stage.ENDLESS
				else:
					stage = Stage.ENEMY
		Stage.ENEMY:
			# ⚠️ 这里以前是 `_nav_x()` —— 就是用户实测那条
			# 「这个位置明明是上下选的但是只能用 a 或 d」。本页画的是
			# `map_row_rect()` 的竖排行，轴必须由 `nav_axis()` 给（现在给的是竖轴）。
			var de := nav_d
			if de != 0:
				enemy_index = posmod(enemy_index + de, maxi(enemy_pool().size(), 1))
				Audio.play_ui("ui_select")
			if (Input.is_action_just_pressed("menu_back") or _mi_back):
				stage = Stage.SUIT
				Audio.play_ui("ui_return")
			elif (Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("fire_gun") or _mi_ok):
				stage = Stage.DIFFICULTY
				Audio.play_ui("ui_confirm")
		Stage.ENCOUNTER:
			var denc := nav_d
			if denc != 0:
				encounter_index = posmod(encounter_index + denc, maxi(encounters().size(), 1))
				Audio.play_ui("ui_select")
			if (Input.is_action_just_pressed("menu_back") or _mi_back):
				stage = Stage.SUIT
				Audio.play_ui("ui_return")
			elif (Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("fire_gun") or _mi_ok):
				# 挑战不是"选完遭遇就开打"——下一步是**难度**（用户已拍板：
				# 挑战保留难度选择）。地图由剧情决定，所以挑战永远走不到地图页。
				stage = Stage.DIFFICULTY
				Audio.play_ui("ui_confirm")
		Stage.DIFFICULTY:
			var dy := nav_d
			if dy != 0:
				diff_index = posmod(diff_index + dy, Difficulty.all_levels(Game.super_hard_unlocked).size())
				Audio.play_ui("ui_select")
			if (Input.is_action_just_pressed("menu_back") or _mi_back):
				# 返回上一层：对战回"选择敌人"，挑战回"选择遭遇"
				stage = Stage.ENCOUNTER if challenge_mode() else Stage.ENEMY
				Audio.play_ui("ui_return")
			elif (Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("fire_gun") or _mi_ok):
				Audio.play_ui("ui_confirm")
				if challenge_mode():
					_launch()      # 挑战没有地图页（地图由剧情决定）
				else:
					stage = Stage.MAP
		Stage.TRAINING:
			# 训练项目：两项（自由打靶 / 新手教学），竖排。
			var dt := nav_d
			if dt != 0:
				training_item = posmod(training_item + dt, TRAINING_ITEMS.size())
				Audio.play_ui("ui_select")
			if (Input.is_action_just_pressed("menu_back") or _mi_back):
				stage = Stage.SUIT
				Audio.play_ui("ui_return")
			elif (Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("fire_gun") or _mi_ok):
				Audio.play_ui("ui_confirm")
				_launch()
		Stage.ENDLESS:
			# ★63-24 无限强化演习 · 开局配置页（§5.6 / R14）：从基础卡池里**自选 3 张**。
			#
			# 版式 = 竖排的卡行 + 最后一行的「出击」行动行 ⇒ 轴走 `nav_axis()` 给的 `Nav.Y`。
			#
			# ⚠️ 确认键在这里有**两种语义**（勾卡 / 出击），靠"焦点在不在行动行上"分流 ——
			# 与设置页那种"值行 + 动作行混排"是同一套做法（`_setting_is_action()`）。
			var dpool := endless_pool_now()
			var dde := nav_d
			if dde != 0:
				endless_index = posmod(endless_index + dde, maxi(endless_row_count(), 1))
				Audio.play_ui("ui_select")
			if (Input.is_action_just_pressed("menu_back") or _mi_back):
				stage = Stage.SUIT
				Audio.play_ui("ui_return")
			elif (Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("fire_gun") or _mi_ok):
				if endless_is_action_row():
					# **出击闸门**：不足 3 张**不响应**（设计 §5.6）。
					# ⚠️ 不帮玩家随机填满 —— 那会让"自选"这件事名存实亡。
					# 给一声 `ui_return` 而不是静音：静默的"按了没反应"是最难懂的手感。
					if not endless_ready():
						Audio.play_ui("ui_return")
						return
					Audio.play_ui("ui_confirm")
					_launch()
				else:
					var card: UpgradeCard = dpool[endless_index]
					if endless_toggle(card.id):
						Audio.play_ui("ui_confirm")
					else:
						# 已经 3 张还去勾第 4 张 ⇒ 明确拒绝（有声音）。
						Audio.play_ui("ui_return")
		Stage.MAP:
			var dmap := nav_d
			if dmap != 0:
				map_index = posmod(map_index + dmap, active_map_list().size())
				Audio.play_ui("ui_select")
			if (Input.is_action_just_pressed("menu_back") or _mi_back):
				stage = Stage.DIFFICULTY
				Audio.play_ui("ui_return")
			elif (Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("fire_gun") or _mi_ok):
				_launch()
		Stage.LAN:
			_read_lan_input()
		Stage.SETTINGS:
			_read_settings_input()
		Stage.KEYS:
			_read_keys_input()
		Stage.BGM:
			_read_bgm_input()
		Stage.FPV_CONFIRM:
			_read_fpv_confirm_input()
		Stage.PASSWORD:
			_read_password_input()


## 出击：把本局配置交给 main。
##
## 挑战模式的"地图 / 敌人"**由剧情脚本决定**，所以这里传 `-1`，
## 由 main 去查 `ChallengeScript`（而不是让菜单自己拼一套规则）。
func _launch() -> void:
	active = false
	Audio.play_ui("ui_confirm")
	var suit := selected_suit()
	var mode := selected_mode()
	var map_id := -1
	var enemy_suit := -1
	if mode == Game.MatchMode.VERSUS:
		map_id = selected_map()
		enemy_suit = selected_enemy()
	elif mode == Game.MatchMode.TRAINING:
		# 1.2 第二十五轮：训练项目页的第 2 项就是**新手教学**。
		#
		# ⚠️ 写**请求**而不是直接写 `tutorial_mode`：`spawn_round()` 里的
		# `Game.reset()` 会清掉 `tutorial_mode` —— 直接写等于白写（实测教学
		# 面板因此在真实开局里从未显示过）。正确链路见 `main.spawn_round`：
		# reset 之后由它把请求落成正式开关并消费掉。
		Game.tutorial_requested = (training_item == 1)
	elif mode == Game.MatchMode.SQUAD:
		# 编队战（1.2 第二十轮）：地图照旧可选；阵营是玩家在上一步选的 ——
		# 它决定「这一边能开的机」。
		#
		# ★63-9 B4：**敌方 ACE 现在也听玩家的**（用户报的 bug：「小队战选择敌方是
		# 阿利宙斯会变成佩涅罗佩来」）。原注释写的是「敌机由编制决定（不选敌机）」，
		# 但敌机页在编队战下**照样能拨、能选中** —— 界面允许玩家做一个被静默丢弃的
		# 决定，那是最坏的一种：不报错，也不生效。
		# 量产的**僚机**仍然由编制决定（`lineup()` 里一律走 `r.mp()`），
		# 变的只是「对面那台 ACE 是谁」。
		map_id = selected_map()
		Game.active_side = side_index_to_side()
		enemy_suit = selected_enemy()
	elif mode == Game.MatchMode.CHALLENGE:
		var enc := selected_encounter()
		Game.active_challenge_id = enc.id if enc != null else ""
	elif mode == Game.MatchMode.LAN:
		# 联机的地图与敌机由网络层决定（对手就是另一台人开的机）
		map_id = Net.match_map()
		# ---- 本机选的对战形式**必须在这里落进 `Game`**（本轮）----
		#
		# ⚠️ 少了这一行，"王牌战"这个形式在真实对局里**永远不会生效**：
		# 这一局是按双方选择算出来的（`main._lan_plan_now()` → `LanPlan.build()`），
		# 而 `Game.active_lan_form` 是那条链上的兜底值 —— 它一直是默认的
		# 「小队战」（因为在此之前**没有任何人写过它**）。于是即便两人都选了王牌战，
		# 本机那一票仍读作小队战 ⇒ `resolve_form()` 判出小队战，**且两台机器都不报错**。
		#
		# 写在这里（而不是 `_begin_lan_wait()`）是刻意的：`_launch()` 才是"配置定案"
		# 的那一刻，和它上面 `Game.active_side` / `Game.tutorial_requested` 同一层语义。
		# 它在 `spawn_lan()` 之前跑完，所以 `_lan_plan_now()` 读得到。
		#
		# ⚠️ 但**不要**把它当成唯一真源：`main._lan_plan_now()` 读的是
		# `Net.choice_of("form", …)`（= 真的发出去的那一份），这里只是兜底 / 落盘。
		# 哪一天有人把这一行挪走，王牌战仍然能打 —— 靠的是那一份，不是这一行。
		Game.active_lan_form = Net.choice_of("form", selected_lan_form())
		Game.active_side = Net.choice_of("side", side_index_to_side())
		suit = Net.choice_of("suit", suit)
	elif mode == Game.MatchMode.ENDLESS:
		# ★63-24 无限强化演习：玩家在开局前选的只有「自机 + 3 张基础卡」。
		# 地图由 `main._resolve_match()` 的 `ENDLESS` 分支强制给一张（设计 §11.3 第 25 条），
		# 难度同理不给 —— 本模式的强度曲线是**局内时间**一条轴（§6.4 拍板）。
		#
		# ⚠️⚠️ 写**请求**（`endless_pick_request`）而**不是**直接写 `endless_owned`：
		# `spawn_round()` 第一步就是 `Game.reset()`，它会把这个模式的局内状态清干净 ——
		# 直接写等于白写（`tutorial_mode` 正因此在真实开局里从未生效过，1.2 第二十六轮才修）。
		# 正确链路：这里写请求 → `reset()` 不碰它 → `main.spawn_endless()` 在 reset 之后落地并消费。
		Game.endless_pick_request = endless_picks.duplicate()
	start_match.emit(suit, selected_level(), map_id, mode, enemy_suit)


## 设置页：上/下选行，左/右改值，Enter/Esc/P 返回。
##
## ★63-23：`Stage.SETTINGS` 挂了**两个子屏**（主屏 / 音量细分），用 `settings_sub` 分派 ——
## 与 `Stage.BGM` / `Stage.LAN` 同一套做法（子屏不新增 `Stage` 枚举值）。
func _read_settings_input() -> void:
	# Esc 保险丝已经在本帧处理过返回（见 `_input()`），这一帧别再退一层
	if Engine.get_process_frames() == _esc_fuse_frame:
		return
	if settings_sub == SET_SUB_VOLUME:
		_read_volume_input()
		return
	var ny := _axis_delta(nav_axis(Stage.SETTINGS))
	if ny != 0:
		setting_row = posmod(setting_row + ny, SETTING_ROWS.size())
		Audio.play_ui("ui_select")

	var back := Input.is_action_just_pressed("menu_back") \
		or Input.is_action_just_pressed("open_settings")
	var key := str(SETTING_ROWS[setting_row]["key"])
	if Input.is_action_just_pressed("confirm") \
			and (_setting_is_action(key) or key == "battle_bgm" \
			or key == "battle_playlist" or key == "first_person" \
			or key == "volume"):
		if key == "quit":
			quit_game()
			return
		if key == "volume":
			# ★63-23：Enter 进**音量细分页**（八条通道各一根滑条）。
			# 与「战斗BGM」「按键设置」同一形状。
			# ⚠️ 必须显式复位焦点行与连调计时器：不复位 `volume_row` 的话，
			# 上次停在第 8 行、这次一进去就停在第 8 行（玩家以为进错了页）；
			# 不复位 `_repeat_timer` 的话，进页那一下可能立刻连调一步。
			settings_sub = SET_SUB_VOLUME
			volume_row = 0
			_repeat_timer = 0.36
			Audio.play_ui("ui_confirm")
			return
		if key == "keys":
			stage = Stage.KEYS
			keys_row = 0
			keys_slot = 0
			keys_scroll = 0
			keys_msg = ""
			Audio.play_ui("ui_confirm")
			return
		if key == "battle_bgm":
			# 批 24：Enter 进**选歌页**（可滚动列表逐首挑）。
			# A/D 循环切换仍然保留 —— 设置行上左右拧和进页细选两条路都通。
			#
			# ★63-22：这一页现在是**选歌页**那一个子屏（`Stage.BGM` 挂两个子屏）。
			# ⚠️ 必须显式复位 `bgm_sub`：不然"上次从歌单页退出来"会让这一行
			# 指向歌单页 —— 玩家按「战斗BGM」却进了「战斗歌单」。
			stage = Stage.BGM
			bgm_sub = BGM_SUB_PICK
			bgm_row = Settings.battle_bgm_index()
			bgm_msg = ""
			Audio.play_ui("ui_confirm")
			return
		if key == "battle_playlist":
			# ★63-22：Enter 进**歌单页**（同样的 54 项列表，但 Enter 是加入/移出）。
			# ⚠️ 这一行**没有左右调值**：它不是一个"值"，是一整个子页面
			#（`_setting_step` 里也显式排除了它，见那边）。
			stage = Stage.BGM
			bgm_sub = BGM_SUB_LIST
			playlist_row = 0
			bgm_msg = ""
			Audio.play_ui("ui_confirm")
			return
		if key == "first_person":
			# Enter 与"往右拨"走**同一条**路（`_open_fpv_confirm()`）——
			# 手柄上 A 键是"激活这一行"的自然手势，不给它留路玩家会以为这一行坏了。
			#
			# ⚠️ 轮 25：`SETTING_ROWS` 里已经没有 `first_person` 了，
			# 所以这个分支**当前不可达**。刻意留着（用户："相关代码不用删"）——
			# 那一行加回来它就原样复活。
			_open_fpv_confirm()
			return
		if key == PRODUCER_KEY:
			# ★ 隐形行（2026-09-30）。`_activate_producer()` 里分两支：
			# 关着 ⇒ 进密码页；已开着 ⇒ **直接关掉**（关不需要密码，见那里的注释）。
			_activate_producer()
			return
		back = true
	if back:
		stage = _settings_return_stage
		Audio.play_ui("ui_return")


## 第一人称的眩晕警告（轮 20）——**两个入口共用的唯一实现**。
##
## 需求原文：「再加一个开关提醒：开启本模式会导致强烈的 3d 眩晕，是否还要开启？」
##
## 与 `battle_bgm` 那一行的区别：那一行是"进一个子页面挑选项"，这一行是**过一道门**。
## 门的默认位置是关着的（`fpv_confirm_row = 0` = 否）—— 这是整件事的重点，
## 理由见那个变量的注释。
##
## ⚠️ 已经开着的时候**不再问**：这道门守的是"别不小心打开"，不是"不许改主意"。
## 要关掉往左拨一下就行（`_setting_step` 里那条路一点摩擦都没有）。
func _open_fpv_confirm() -> void:
	if Settings.first_person:
		Audio.play_ui("ui_item", -14.0)
		return
	fpv_confirm_row = 0          # 每次进来都回到「否」
	stage = Stage.FPV_CONFIRM
	Audio.play_ui("ui_confirm")


## 眩晕警告：上/下选「否 / 是」，Enter 执行，Esc / P 取消（= 不开启）。
##
## ⚠️ 选「否」与按 Esc 是**同一件事**（都不改设置），所以不做区分 ——
## 多一种"什么都不做的出口"只是多一条要维护、且可能和别的出口分叉的路径。
##
## ⚠️ 这里**没有长按连发**（只有 `nav_axis` 的边沿判定），所以不存在
## "长按把它重新弹出来"的问题 —— 那一层防护在入口那边（`_setting_step` 的 `fresh`）。
func _read_fpv_confirm_input() -> void:
	# Esc 保险丝已在本帧处理过返回（见 `_input()`），这一帧别再退一层
	if Engine.get_process_frames() == _esc_fuse_frame:
		return
	var ny := _axis_delta(nav_axis(Stage.FPV_CONFIRM))
	if ny == 0:
		ny = _mi_d
	if ny != 0:
		fpv_confirm_row = clampi(fpv_confirm_row + ny, 0, 1)
		Audio.play_ui("ui_select")
	if _mi_back or Input.is_action_just_pressed("menu_back") \
			or Input.is_action_just_pressed("open_settings"):
		stage = Stage.SETTINGS
		Audio.play_ui("ui_return")
		return
	if _mi_ok or Input.is_action_just_pressed("confirm"):
		# 只有停在「是」上才真的写；「否」= 关掉这个框，设置一个字都不动。
		if fpv_confirm_row == FPV_CONFIRM_YES:
			Settings.set_first_person(true)
			Audio.play_ui("ui_confirm")
		else:
			Audio.play_ui("ui_return")
		stage = Stage.SETTINGS


# ============================================================ ★ 制作人模式（2026-09-30）
#
# 需求原文见 `Setting_ROWS` 末尾那段与 `Game.producer_mode`。
#
# ## 这一节里三件事的分工（一件都不许搬走）
#   `_activate_producer()` —— **隐形行上的那一下 Enter 该干什么**（开 / 关两支）；
#   `_open_password()`     —— 进密码页（清干净上一次的输入与结果）；
#   `submit_password()`    —— **判定的唯一实现**（通过 ⇒ 打开开关、写结果行）；
#   `_read_password_input()` —— 轮询：返回 / Enter（字符在 `_input()` 里收）。
#
# ⚠️ `submit_password()` **独立于界面**：它收一串字符就能跑完判定与写入，
# 所以测试不必去注入按键（无头环境的 `just_pressed` 帧戳不可靠，这条结论
# `suite_tutorial` / `suite_fpv` 都吃过）。判据钉在它身上，输入那一层只钉接线。

## 隐形行上的 Enter。**开要密码、关不要。**
##
## 与 `_open_fpv_confirm()` 是同一条取舍（见那里"已经开着的时候不再问"）：
## **门只挡危险的那一侧**。开启会改变整个战役的解锁与军资读法，那要密码；
## 关上只是回到原样，多按一下确认键就能做到，没有理由再设一道门。
func _activate_producer() -> void:
	if Game.producer_mode:
		Game.set_producer_mode(false)
		Audio.play_ui("ui_return")
		return
	_open_password()


## 进密码页。**每次进来都把上一次的输入与结果清掉** ——
## 留着上一次那 8 个点的话，玩家会以为"已经输好了，直接按 Enter 就行"。
func _open_password() -> void:
	pw_input = ""
	pw_msg = ""
	pw_ok = true
	stage = Stage.PASSWORD
	Audio.play_ui("ui_confirm")


## 提交一串密码。**判定的唯一实现**（读键那条路只是把输入喂进来）。
##
## 通过 ⇒ 打开制作人模式，返回 `true`；不通过 ⇒ 写红字、清空输入，返回 `false`。
##
## ⚠️ 不通过时**把输入清空**而不是留着：留着的话玩家分不清"是我没删干净、
## 还是刚才那 8 位确实不对"（对应地，`PROD.MAX_LEN` 留了两格余量，
## 所以"多按了一下"永远还能靠退格改回来）。
##
## ⚠️ 它**不关页面**（`stage` 留给调用方）：这样测试能在不驱动帧循环的情况下
## 反复提交（对 / 错 / 空），而界面那一层只负责"通过后回设置页"。
func submit_password(typed: String) -> bool:
	if PROD.accepts(typed):
		Game.set_producer_mode(true)
		pw_input = ""
		pw_msg = PROD.DONE
		pw_ok = true
		return true
	pw_input = ""
	pw_msg = PROD.WRONG
	pw_ok = false
	return false


## 密码页的轮询输入：Esc / P 返回；Enter 判定（字符在 `_input()` 里收）。
##
## ⚠️ 通过之后**回设置页**（而不是留在这里）：那一行此时已经**显形**了
##（`setting_row_hidden(i, true)` = false），玩家一眼就能看见"制作人模式 开"
## —— 那比在这一页印一行绿字更结实（绿字会随这一页一起被关掉）。
func _read_password_input() -> void:
	# Esc 保险丝已在本帧处理过返回（见 `_input()`），这一帧别再退一层
	if Engine.get_process_frames() == _esc_fuse_frame:
		return
	if Input.is_action_just_pressed("menu_back") \
			or Input.is_action_just_pressed("open_settings"):
		stage = Stage.SETTINGS
		pw_input = ""
		pw_msg = ""
		Audio.play_ui("ui_return")
		return
	if Input.is_action_just_pressed("confirm"):
		if submit_password(pw_input):
			Audio.play_ui("ui_confirm")
			stage = Stage.SETTINGS
		else:
			Audio.play_ui("ui_return")


## 密码页的版式（纯函数，测试直接量它）。
##
## 一块居中的窄面板：上面是输入框、下面是结果行。宽度跟着外框但**不超过 560**
##（密码框拉满整屏看着像报错页）；高度是定值 —— 这一页没有列表，
## "随内容伸缩"在这里没有意义。
static func password_panel(view: Vector2) -> Rect2:
	var w := minf(UILayout.frame_width(view), 560.0)
	var h := 176.0
	return Rect2((view.x - w) * 0.5,
		PANEL_TOP + maxf((content_height(view) - h) * 0.5, 0.0), w, h)


## 输入框在密码面板里的矩形（纯函数：输入框与光标的位置只有一个算法）。
static func password_field_rect(view: Vector2) -> Rect2:
	var box := password_panel(view)
	return Rect2(box.position.x + 40.0, box.position.y + 38.0, box.size.x - 80.0, 48.0)


## 密码页：标题带 + 居中面板（输入框 / 结果行）+ 页脚键位提示。
##
## ⚠️ 回显走 `PROD.echo()`（**点**而不是数字）—— 密码框不印明文，
## 但"按了几下"照样看得见：位数是玩家唯一需要的反馈（数得出来就够改错了）。
func _draw_password_stage() -> void:
	_draw_title_band(PROD.TITLE, PROD.SUBTITLE, Color(0.95, 0.80, 0.35), false)
	var box := password_panel(size)
	draw_rect(box, Color(0.04, 0.08, 0.13, 0.94), true)
	draw_rect(box, Color(0.28, 0.42, 0.54), false, UILayout.LINE_STRUCT)

	var fr := password_field_rect(size)
	draw_rect(fr, Color(0.02, 0.05, 0.09, 0.90), true)
	draw_rect(fr, WARN, false, UILayout.LINE_STRUCT)
	# 光标闪烁：与重绑页等待态、暂停菜单同一条写法（`int(_time*2) % 2`），
	# 一眼看得出"这一页还活着、正在等你按"。
	var blink := int(_time * 2.0) % 2 == 0
	_text(Vector2(fr.position.x + 18.0, text_vcenter(fr, 26)),
		PROD.echo(pw_input, blink), 26, Color(0.95, 0.92, 0.70))
	_text_right(Vector2(fr.position.x + fr.size.x - 18.0, text_vcenter(fr, 14)),
		PROD.PROMPT, 14, Color(0.55, 0.64, 0.74))

	if not pw_msg.is_empty():
		_text(Vector2(box.position.x + 40.0, box.position.y + box.size.y - 34.0),
			pw_msg, 17,
			Color(0.55, 1.0, 0.74) if pw_ok else Color(1.0, 0.55, 0.45))

	_draw_hint(PROD.HINT_KEY, PROD.HINT_PAD)


## ★63-22 两个子屏（选歌页 / 歌单页）**共用**的焦点落点 —— 写行 + 提示音 + 试听。
##
## ⚠️ 这是**试听的唯一触发点**：两个子屏都调它，谁都不许自己再写一份。
##
## ⚠️ 为什么不挂在 `_set_focus()` 上：用户拍板 Q6「键盘移到」⇒ 这一页
## **不做鼠标几何**（`_list_geometry()` 仍是 `Geo.NONE`）⇒ `_set_focus()` 的
## BGM 分支只会被 `_hover_focus()` 调到，而它永远不会在这一页被调 ——
## 那是**死代码**，挂在死代码上的钩子等于没挂，而且"看起来接好了"最骗人。
func _bgm_set_row(i: int) -> void:
	if i < 0:
		return
	if i != _bgm_focus_row():
		_bgm_write_row(i)
		Audio.play_ui("ui_select")
	Audio.preview_bgm(_bgm_row_track())


## 当前子屏的焦点行。
func _bgm_focus_row() -> int:
	return playlist_row if bgm_sub == BGM_SUB_LIST else bgm_row


## 写焦点行 —— **两个子屏唯一不同的那一处**。
## 其余（提示音、试听）都在漏斗里，这正是"漏斗"的形状：
## 共用的部分收在一处，不同的部分做成一个极小的回调。
func _bgm_write_row(i: int) -> void:
	if bgm_sub == BGM_SUB_LIST:
		playlist_row = i
	else:
		bgm_row = i


## 焦点行对应的曲键（`""` = 选歌页那一行「随机（洗牌袋轮换）」，它背后没有具体的曲）。
func _bgm_row_track() -> String:
	var keys := bgm_pick_keys()
	var i := _bgm_focus_row()
	return "" if i < 0 or i >= keys.size() else str(keys[i])


## ★63-22 歌单页的 `Enter`：加入 / 移出切换（用户拍板 Q13「复用 `confirm`」）。
##
## ## ⚠️ 页内一键两义：本批**唯一**的新风险，所以要靠"五件套"把它按下去
## 玩家想"加入"，却因为**已经加入了**而变成"移出" —— 这是 toggle 的固有风险。
## 防它的手段全部落在这个函数与绘制侧：行尾 `◆N` + 页头 `N/6` + 底部提示写清两义
## + **两个方向播不同音效** + **满员被拒也不许听着像成功**。
##
## ## ⚠️ 只读 `confirm`，**不跟 `fire_gun`**
## 照抄选歌页的写法。手柄上 `A` 同时绑 `confirm` 与 `flight_assist`（长按 0.45 s 区分）；
## 菜单项那一族写成 `confirm or fire_gun` 是它们自己的用法，这一页跟了的话
## "长按 A"就多出一个含义，与"长按 = 辅助飞行"的心智撞车。
## 这条有源码扫描判据钉着（`suite_bgm_playlist`）。
func _playlist_toggle_row(i: int) -> void:
	var keys := bgm_pick_keys()
	if i < 0 or i >= keys.size():
		return
	var track := str(keys[i])
	var r := Settings.toggle_playlist_track(track)
	if r == Settings.PLAYLIST_ADDED:
		bgm_msg = ""
		Audio.play_ui("ui_confirm")
	elif r == Settings.PLAYLIST_REMOVED:
		bgm_msg = ""
		Audio.play_ui("ui_return")
	elif r == Settings.PLAYLIST_REJECTED_FULL:
		bgm_msg = "歌单已满 %d 首 —— 再按一次可移出，或先去别的行移出一首" % Settings.PLAYLIST_MAX
		Audio.play_ui("ui_return")
	else:
		# 只剩「随机（洗牌袋轮换）」那一行：它不是一个曲键，谈不上加入。
		bgm_msg = "这一行是「随机」，请先选一首具体的曲子"
		Audio.play_ui("ui_return")


## 战斗BGM 两个子屏**共用**一个读输入函数（键位完全相同，只有 `Enter` 按子屏分叉）。
##
## 选歌页（批 24）：上/下（或 A/D）选歌，`Enter` 当场选定开场曲，Esc/P 回设置页。
## 歌单页（★63-22）：上/下选歌，`Enter` 加入/移出，Esc/P 回**选歌页**。
##
## 竖排滚动列表 —— `scroll_window` 与模式/敌机页同源，三条不变量同一套
##（窗口 ≤ 可见行数 / 聚焦项必在窗口里 / 放得下时不画滚动条）。
##
## ⚠️ **换行只许走 `_bgm_set_row()`**：试听挂在那个漏斗上，自己写一行
## `bgm_row = …` 会让"选歌页有试听、歌单页没有"这种半残状态出现，
## 而且**只有走到那一页才发现**。判据里有一条源码扫描钉这个。
func _read_bgm_input() -> void:
	# Esc 保险丝已在本帧处理过返回（见 `_input()`），这一帧别再退一层
	if Engine.get_process_frames() == _esc_fuse_frame:
		return
	var ny := _axis_delta(nav_axis(Stage.BGM))
	var d := ny
	# 左右键是上下移动的**别名**（与选歌页同一套）—— 这一页是单列，没有横向可去的地方，
	# 而玩家在列表上顺手推左右是常态。两页必须一致，否则"在选歌页能用的键在歌单页失灵"。
	if Input.is_action_just_pressed("roll_left") or Input.is_action_just_pressed("yaw_left"):
		d = -1
	elif Input.is_action_just_pressed("roll_right") or Input.is_action_just_pressed("yaw_right"):
		d = 1
	if d != 0:
		_bgm_set_row(posmod(_bgm_focus_row() + d, bgm_pick_keys().size()))
	if Input.is_action_just_pressed("menu_back"):
		# 歌单页先退回选歌页（**一层一层退**）—— 与 `_input()` 里 Esc 保险丝的分支逐字对应。
		if bgm_sub == BGM_SUB_LIST:
			bgm_sub = BGM_SUB_PICK
			bgm_msg = ""
		else:
			stage = Stage.SETTINGS
		Audio.play_ui("ui_return")
		return
	if Input.is_action_just_pressed("confirm"):
		if bgm_sub == BGM_SUB_LIST:
			_playlist_toggle_row(_bgm_focus_row())
		else:
			Settings.set_battle_bgm_index(bgm_row)
			bgm_msg = ""
			Audio.play_ui("ui_confirm")


## 左/右调值的**方向**，带长按连调。返回 −1 / 0 / +1。
##
## 单次按键只走 5%（音量），从 0 调到 100 要按 20 次太难受；
## 所以首次按下后 0.36 秒开始连发，之后每 0.055 秒一步。
## 不用 `is_action_just_pressed` 的连发是因为 Godot 的键盘重复依赖系统设置，
## 在有些机器上根本不触发。
##
## ## ★63-23 为什么把它从 `_setting_step()` 里抽出来
## **设置页主屏**（`_setting_step`）与**音量细分页**（`_volume_step`）要的是同一档手感。
## 各写一份的症状是"音量页调值没有连发 / 快慢不一样"——
## 那是只有手指能发现的差别，看代码看不出来。
##
## `_step_fresh` 是**输出**：这一下是"刚推过去"还是长按连发出来的。
## 需要它的只有第一人称那一行（"过一道门"的行不能吃长按：
## 长按会让"关掉警告框 → 又被长按重新弹出来"变成一个循环）。
func _step_dir(delta: float) -> int:
	var dir := 0
	_step_fresh = false
	if Input.is_action_just_pressed("roll_left") or Input.is_action_just_pressed("yaw_left"):
		dir = -1
		_step_fresh = true
		_repeat_timer = 0.36
	elif Input.is_action_just_pressed("roll_right") or Input.is_action_just_pressed("yaw_right"):
		dir = 1
		_step_fresh = true
		_repeat_timer = 0.36
	elif _pad_dx != 0:
		# 摇杆推过去的那一下
		dir = _pad_dx
		_step_fresh = true
		_repeat_timer = 0.36
	else:
		_repeat_timer = maxf(_repeat_timer - delta, 0.0)
		if _repeat_timer <= 0.0:
			var held := 0
			if Input.is_action_pressed("roll_left") or Input.is_action_pressed("yaw_left"):
				held = -1
			elif Input.is_action_pressed("roll_right") or Input.is_action_pressed("yaw_right"):
				held = 1
			else:
				held = _pad_held_x()
			if held != 0:
				dir = held
				_repeat_timer = 0.055
	return dir


func _setting_step(delta: float) -> void:
	var key := str(SETTING_ROWS[setting_row]["key"])
	# ⚠️ `battle_playlist`（★63-22）与 `volume`（★63-23）**都不是**能左右拧的值 ——
	# 它们是**一整个子页面**。不排除的话，左右键落到 `match key` 的兜底（什么都不做）
	# 而**白吃掉一次输入**，玩家的感觉是"这一行按了没反应"。
	# 这里与 `_setting_is_action()` 分开写，是因为那个函数同时决定**绘制走哪个分支**
	#（它会让这一行画成"Enter 退出"那种动作行）。
	if _setting_is_action(key) or key == "battle_playlist" or key == "volume":
		return
	var dir := _step_dir(delta)
	var fresh := _step_fresh
	if dir == 0:
		return
	_apply_setting_delta(dir, fresh)


func _apply_setting_delta(dir: int, fresh := true) -> void:
	var key := str(SETTING_ROWS[setting_row]["key"])
	match key:
		"resolution":
			Settings.cycle_resolution(dir)
		"fullscreen":
			Settings.set_fullscreen(dir > 0)
		"bgm":
			# ⚠️ 公式统一写 `Settings.volume(...) + 步进`，不再读裸变量
			# （★63-23：八条通道共用一套写法；读到别的通道的值是这类改动最经典的错）。
			Settings.set_volume(Settings.BUS_BGM,
				Settings.volume(Settings.BUS_BGM) + float(dir) * Settings.VOLUME_STEP)
		"sfx":
			Settings.set_volume(Settings.BUS_SFX,
				Settings.volume(Settings.BUS_SFX) + float(dir) * Settings.VOLUME_STEP)
		"battle_bgm":
			# 战斗 BGM 自选（批 23）：随机 → 曲池顺序 → 绕回，双向循环
			Settings.cycle_battle_bgm(dir)
		"cam_roll":
			Settings.cycle_cam_roll(dir)
		"cam_shake":
			Settings.cycle_cam_shake(dir)
		"first_person":
			# 往右 = 试着开启（→ 眩晕警告）；往左 = 直接关掉（不弹任何东西）。
			# ⚠️ 只认 `fresh`（见上面那个变量的注释）：长按不该反复弹警告框。
			# ⚠️ 轮 25：这一行已不在 `SETTING_ROWS` 里 ⇒ 本分支当前不可达，
			# 与 `_read_settings_input` 里那一段一起**刻意保留**。
			#
			# 这里**自带音效并 return**，为的是不吃函数末尾那一下统一的 `ui_item`——
			# 走警告框时会和 `_open_fpv_confirm()` 里的 `ui_confirm` 叠成双响。
			if not fresh:
				return
			if dir > 0:
				_open_fpv_confirm()
			else:
				Settings.set_first_person(false)
				Audio.play_ui("ui_item", -14.0)
			return
		"motion":
			# 单项开关：往右是开、往左是关（不是循环），免得"再推一下又变回去"
			Settings.set_reduce_motion(dir > 0)
		"low_end_60":
			Settings.set_quality_preset(clampi(mini(Settings.quality_preset,2)+dir,0,2))
		"render_scale", "dynamic_resolution", "shadows", "effects", "magnifier_quality":
			Settings.adjust_performance(key,dir)
		"ssao":
			# 同款单项开关（批 10 性能优化：默认关，开了才吃那笔屏幕空间特效的开销）
			Settings.set_ssao(dir > 0)
		"cel":
			# 三渲二开关（批 17）：默认开 —— 这是本作选定的视觉方向，不是加餐。
			Settings.set_cel_shading(dir > 0)
	Audio.play_ui("ui_item", -14.0)


# ============================================================ 按键设置页（批 4 · §4.8.7）

## 重绑页的扁平行序（顺序 = KEY_GROUPS = HELP_SECTIONS 的分组顺序）。
static func keys_flat() -> Array[String]:
	var out: Array[String] = []
	for g: Array in KEY_GROUPS:
		for a in g[1]:
			out.append(str(a))
	return out


## 一行的键格文本：键盘槽在前，**手柄槽跟在后面**（批 10：手柄进自定义）；
## 没有键盘槽的（纯鼠标动作）显示鼠标槽。
func _slot_labels(action: String) -> Array[String]:
	var out: Array[String] = []
	var ks := InputSetup.bound_keys(action)
	if not ks.is_empty():
		for k: int in ks:
			out.append(InputSetup.key_label(k))
	else:
		for b: int in InputSetup.bound_buttons(action):
			out.append(InputSetup.mouse_label(b))
	for p: int in InputSetup.bound_pads(action):
		out.append(InputSetup.pad_label(p))
	if out.is_empty():
		out.append("未绑定")
	return out


## 与 `_slot_labels()` **逐位平行**的槽类型表（"key" / "mouse" / "pad"）。
##
## ⚠️ 为什么需要它：等待态选中的 `keys_slot` 是**显示行里的下标**，
## 而 `try_rebind()` 要的是**对应那张表里的下标** —— 键盘槽和手柄槽混在一行之后，
## 两者不再相等，必须按种类换算（见 `_capture_rebind`）。
func _slot_kinds(action: String) -> Array[String]:
	var out: Array[String] = []
	var ks := InputSetup.bound_keys(action)
	if not ks.is_empty():
		for k: int in ks:
			out.append("key")
	else:
		for b: int in InputSetup.bound_buttons(action):
			out.append("mouse")
	for p: int in InputSetup.bound_pads(action):
		out.append("pad")
	if out.is_empty():
		out.append("none")
	return out


func keys_metrics(view: Vector2) -> Dictionary:
	# 窗口容量仍是 `KEY_PAGE_ROWS` 行（可重绑动作 30+ 条，不可能一屏排完）；
	# 屏幕太矮时窗口跟着缩（`rows_that_fit`），行高再在框内自适应撑饱满。
	var cap := mini(KEY_PAGE_ROWS,
		rows_that_fit(view, KEY_ROW_H, 0.0, PANEL_PAD_TOP + PANEL_PAD_BOTTOM))
	return list_metrics(view, cap, KEY_ROW_H, 0.0, KEY_ROW_MAX, PANEL_PAD_TOP, PANEL_PAD_BOTTOM)


func keys_panel_rect(view: Vector2) -> Rect2:
	return list_panel_rect(view, keys_metrics(view))


## 重绑页输入。等待态的按键捕获在 `_input()` 里 —— 那是唯一拿得到原始事件的地方。
func _read_keys_input() -> void:
	if waiting_bind:
		# 手柄 B / Esc 取消（批 10 起手柄按键可以当新绑定，但 B 永远留着反悔）
		if Input.is_action_just_pressed("menu_back"):
			waiting_bind = false
			wait_action = ""
			keys_msg = ""
			Audio.play_ui("ui_return")
		return
	# Esc 保险丝已经在本帧处理过返回（见 `_input()`），这一帧别再叠加
	if Engine.get_process_frames() == _esc_fuse_frame:
		return
	var rows := keys_flat()
	if rows.is_empty():
		return
	if Input.is_action_just_pressed("menu_back"):
		stage = Stage.SETTINGS
		Audio.play_ui("ui_return")
		return
	var ny := _axis_delta(nav_axis(Stage.KEYS))
	if ny != 0:
		keys_row = posmod(keys_row + ny, rows.size())
		keys_slot = 0
		Audio.play_ui("ui_select")
	var nx := _nav_x()
	var slots := _slot_labels(rows[keys_row])
	if nx != 0 and slots.size() > 1:
		keys_slot = posmod(keys_slot + nx, slots.size())
		Audio.play_ui("ui_select")
	# 可视窗口跟着光标滚。⚠️ 窗口行数必须与画图那一侧**同一个来源**
	#（`_key_window_rows()`）—— 分开写就会出现"画出来的行滚不到"或"滚过去是空的"。
	var cap := _key_window_rows()
	keys_scroll = clampi(keys_scroll, keys_row - cap + 1, keys_row)
	keys_scroll = clampi(keys_scroll, 0, maxi(rows.size() - cap, 0))
	if Input.is_action_just_pressed("confirm"):
		wait_action = rows[keys_row]
		wait_slot = keys_slot
		# 记下选中槽的种类（key/mouse/pad）—— 手柄槽混进同一行之后，
		# 显示下标 ≠ 表内下标，捕获时要按它换算（见 _capture_rebind）。
		var kinds := _slot_kinds(wait_action)
		wait_kind = kinds[clampi(keys_slot, 0, kinds.size() - 1)]
		waiting_bind = true
		keys_msg = ""
		Audio.play_ui("ui_select")
	# R 点按 = 恢复本行默认；长按 0.6 s = 全部恢复（复用「点按 / 长按分家」，
	# 不新增键位 —— 和 `PAD_HOLD` 同一个思路）。
	# ⚠️ 走**物理键**读 R、不走 InputMap：它是本页自己的功能键，不是 reload 动作 ——
	# 用户把换弹改到 J 上时，页脚提示依然是 R，还是真话。
	if Input.is_physical_key_pressed(KEY_R):
		_keys_r_hold += get_process_delta_time()
		if _keys_r_hold >= 0.6 and not _keys_r_all_done:
			_keys_r_all_done = true
			InputSetup.reset_all()
			keys_msg = "已恢复全部出厂键位"
			keys_msg_ok = true
			Audio.play_ui("ui_return")
	elif _keys_r_hold > 0.0:
		if not _keys_r_all_done:
			InputSetup.reset_action(rows[keys_row])
			keys_msg = "已恢复「%s」的出厂键位" % InputSetup.action_name(rows[keys_row])
			keys_msg_ok = true
		_keys_r_hold = 0.0
		_keys_r_all_done = false


## 等待态捕获到键 → 原子重绑。结果印在页脚；
## 冲突必须**报占用者**（§4.8.3："Tab 已被「切换目标」占用"才是可操作的）。
func _capture_rebind(ev: InputEvent) -> void:
	waiting_bind = false
	# 显示下标 → **种类内**下标：键盘槽永远在行首（下标相等）；
	# 手柄槽排在键盘/鼠标槽后面，要减去前面同种类槽的个数（批 10）。
	var slot_for_api := wait_slot
	if wait_kind == "pad" or wait_kind == "mouse":
		var kinds := _slot_kinds(wait_action)
		var same := 0
		for i in mini(wait_slot, kinds.size()):
			if kinds[i] == wait_kind:
				same += 1
		slot_for_api = same
	var res: Dictionary = InputSetup.try_rebind(wait_action, slot_for_api, ev)
	var keyname := ""
	if ev is InputEventKey:
		keyname = InputSetup.key_label((ev as InputEventKey).physical_keycode)
	elif ev is InputEventJoypadButton:
		keyname = InputSetup.pad_label((ev as InputEventJoypadButton).button_index)
	else:
		keyname = InputSetup.mouse_label((ev as InputEventMouseButton).button_index)
	match int(res["code"]):
		InputSetup.Bind.OK:
			keys_msg = "「%s」→ %s" % [InputSetup.action_name(wait_action), keyname]
			keys_msg_ok = true
			Audio.play_ui("ui_confirm")
		InputSetup.Bind.CONFLICT:
			keys_msg = "\"%s\" 已被「%s」占用" % [keyname, InputSetup.action_name(str(res["conflict"]))]
			keys_msg_ok = false
			Audio.play_ui("ui_return")
		InputSetup.Bind.RESERVED:
			keys_msg = "「%s」不允许改键（防自锁）" % InputSetup.action_name(wait_action)
			keys_msg_ok = false
			Audio.play_ui("ui_return")
		_:
			keys_msg = "这个键不能用作绑定（修饰键 / 无效事件）"
			keys_msg_ok = false
			Audio.play_ui("ui_return")
	wait_action = ""


## 重绑页一屏画几行 = `keys_metrics()` 的 `shown`。
## **滚动钳位与绘制必须共用这一个数**，理由见 `_read_keys_input()` 里的注释。
func _key_window_rows() -> int:
	return int(keys_metrics(size)["shown"])


func _draw_keys_stage() -> void:
	_draw_title_band("按 键 设 置", "选中键格按 Enter 换键 · 改动立即保存",
		Color(0.75, 0.88, 1.0), false)
	var m := keys_metrics(size)
	var r := list_panel_rect(size, m)
	MENU_VISUALS.panel(self, r)
	var left := r.position.x + UILayout.PAD
	var right := r.position.x + r.size.x - UILayout.PAD
	var rows := keys_flat()
	var hi := mini(keys_scroll + _key_window_rows(), rows.size())
	for idx in range(keys_scroll, hi):
		var action := rows[idx]
		var rr := list_row_rect(size, idx, keys_scroll, m)
		var ry := text_vcenter(rr, 16)
		var on := idx == keys_row
		if on:
			MENU_VISUALS.selected_line(self, rr)
		var name_col := Color(0.90, 0.96, 1.0) if on else Color(0.62, 0.72, 0.84)
		_choice_text(Vector2(left, ry), InputSetup.action_name(action), 16, name_col, on)
		# 键格：一个动作可有多个物理键（slot），左右在格间移动
		var slots := _slot_labels(action)
		var sx := left + 240.0
		for si in slots.size():
			var sel := on and si == keys_slot
			var cell_col := Color(0.95, 0.80, 0.35) if sel else Color(0.66, 0.78, 0.90)
			_text(Vector2(sx, ry), str(slots[si]), 15, cell_col,
				UILayout.WEIGHT_EMPH if sel else -1)
			sx += 112.0
		if on and not waiting_bind:
			_text_right(Vector2(right, ry), "Enter 换键", 13, Color(0.55, 0.64, 0.74))
	# 滚动指示（批 29 补）：这一页 30+ 行、窗口只放得下十来行 —— 原来只有页脚提示，
	# 玩家看不出"下面还有一大半"。指示器的轨道跟着行块走（`m["top"]`）。
	_draw_scroll_indicator(rows.size(), keys_row, _key_window_rows(), m)
	# 页脚：等待态 → 结果 / 冲突 → 常驻提示（都锚在同一行底线上）
	if waiting_bind:
		_draw_hint("请按新键…（Esc 取消）", "请按新键…（B 取消）")
	elif keys_msg != "":
		var mc := Color(0.55, 1.0, 0.74) if keys_msg_ok else Color(1.0, 0.55, 0.45)
		_text(Vector2(UILayout.content_left(size), hint_y(size)), keys_msg, 15, mc)
	else:
		_draw_hint(
			"Enter 换键        R 恢复本行 · 长按 R 全部恢复        Esc 返回",
			"左摇杆 / 十字键 选择        A 换键        B 返回")


# ============================================================ 绘制

var _lore_scroll: Dictionary = {}
var _lore_regions: Array[Dictionary] = []

func _draw() -> void:
	_lore_regions.clear()
	if is_instance_valid(_tilt_label): _tilt_label.hide()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.08, 0.86), true)
	_draw_starfield()
	if is_instance_valid(_home_view):
		_home_view.sync(0.0)
		if _home_view.visible: return

	match stage:
		Stage.MODE:
			_draw_mode_stage()
		Stage.BATTLE:
			_draw_battle_stage()
		Stage.SIDE:
			_draw_side_stage()
		Stage.SUIT:
			_draw_suit_stage()
		Stage.ENEMY:
			_draw_enemy_stage()
		Stage.DIFFICULTY:
			_draw_difficulty_stage()
		Stage.TRAINING:
			_draw_training_stage()
		Stage.MAP:
			_draw_map_stage()
		Stage.ENCOUNTER:
			_draw_encounter_stage()
		Stage.LAN:
			_draw_lan_stage()
		Stage.SETTINGS:
			# ★63-23：`Stage.SETTINGS` 挂了**两个子屏**（主屏 / 音量细分），
			# 用 `settings_sub` 分派（与 `Stage.BGM` / `Stage.LAN` 同一套做法）。
			if settings_sub == SET_SUB_VOLUME:
				_draw_volume_stage()
			else:
				_draw_settings_stage()
		Stage.KEYS:
			_draw_keys_stage()
		Stage.BGM:
			# ★63-22：`Stage.BGM` 挂了**两个子屏**（选歌页 / 歌单页），用 `bgm_sub` 分派。
			if bgm_sub == BGM_SUB_LIST:
				_draw_bgm_list_stage()
			else:
				_draw_bgm_stage()
		Stage.FPV_CONFIRM:
			_draw_fpv_confirm_stage()
		Stage.ENDLESS:
			_draw_endless_stage()
		Stage.PASSWORD:
			_draw_password_stage()

	_draw_step_bar()


## **阵营页**（1.2 第二十轮，只有编队战会走到）。
##
## 两行横排，每行一个阵营：名字 + 这个阵营**能开哪些机** + 编制一句话。
## ⚠️ 必须把"能开哪些机"印出来 —— 用户要的是"**不同阵营的小队能选择的机体不同**"，
## 而这个差异如果只体现在下一页的卡片数量上，玩家在选边时根本不知道自己会失去什么。
func _draw_side_stage() -> void:
	_draw_title_band("小队战 · 选择阵营", "两边各 3 个量产编队 + 1 台 ACE",
		Color(0.75, 0.88, 1.0), false)
	# 两行阵营 —— 行高自适应（`ROW_H`..`ROW_MAX`），整块在内容区里居中。
	# ★63-19：行几何改读 `_list_geometry()`（唯一真源）。这一页原来把 `0` 写死在
	# `list_row_rect(size, i, 0, m)` 里 —— 两行放得下时它恰好等于窗口首行，
	# 一旦放不下就是"看着点这一行、实际选了另一行"。
	var g := _list_geometry()
	for i in side_choices().size():
		var side_i: int = side_choices()[i]
		var r := BattleFormation.roster_of(side_i)
		var rect := row_rect(size, g, i)
		var focused := (i == side_index)
		MENU_VISUALS.row(self, rect, WARN, focused)
		var x := UILayout.content_left(size)
		# ---- 阵营标志（1.2：用户给的 LOGO 图）----
		#
		# 竖排在**行左侧**的一块固定方格里，等比缩放、居中。
		# 为什么固定格子而不是按图片尺寸放：两张图的长宽比不同
		#（马夫蒂 485×657 偏瘦、联邦 663×757 偏方），
		# 按各自尺寸放会让文字起始位置在两百之间跳。
		var box_h := rect.size.y - 16.0
		var box_w := 96.0
		var box := Rect2(x, rect.position.y + 8.0, box_w, box_h)
		_draw_roster_logo(r, box)
		var tx := x + box_w + 16.0
		# 三行文字（阵营名 22 + 可选机体 14 + 编制 13）整块垂直居中。
		var ty := baseline_block(rect, 3, 20.0, 22)
		_choice_text(Vector2(tx, ty), r.name_cn, 22,
			WARN if focused else Color(0.42, 0.52, 0.62), focused)
		# 可选机体：把池子列全（ACE ＋ 量产），这是"阵营差异"的唯一可见处。
		var names: Array[String] = []
		for id: int in r.all_suits():
			names.append(_menu_profile(id).display_name)
		_text(Vector2(tx, ty + 20.0), "可出击机体：" + " / ".join(names), 14,
			Color(0.66, 0.78, 0.90))
		_text(Vector2(tx, ty + 40.0),
			("重型MA单机编制 · 无飞行踏板" if side_i == BattleFormation.Side.ZEON else "量产编队 ×%d（每队 %d 台 · 一块踏板）  ·  ACE ×%d"
				% [BattleFormation.SQUADS_PER_SIDE, BattleFormation.UNITS_PER_SQUAD,
					BattleFormation.ACES_PER_SIDE]), 13, Color(0.45, 0.55, 0.66))
	# ⚠️ 提示行必须与 `nav_axis(Stage.SIDE)` 一致。这一页画的是**竖排行**，
	# 所以是 W / S（+ 十字键 ↑↓ / 左摇杆），不能再印"A / D"。
	_draw_hint(
		"W / S 选择阵营        Enter / 空格 确认        Esc 返回",
		"十字键 ↑↓ / 左摇杆 选择阵营        A 确认        B 返回")


## 阵营 LOGO 的纹理缓存（路径 → Texture2D）。
##
## ⚠️ **必须在 `_draw()` 之外缓存**。实测：在 `_draw()` 里每帧 `load(path)`
## 画出来是**一块纯白**，而同一段代码画那张**被缓存过的** `title.png` 完全正常。
## 两者的差别只有"取纹理的方式" —— 所以这里照 `title_texture()` 的做法缓存一份。
##
## （文件本身没问题：用 Python 独立解码 + Godot 的 `Image` 读像素都是对的，
##   金色 `(255,176,37)`、底色 `(12,22,35)`、近白像素 0%。）
var _faction_logo_cache: Dictionary = {}


func _faction_logo_tex(path: String) -> Texture2D:
	if _faction_logo_cache.has(path):
		return _faction_logo_cache[path] as Texture2D
	var t := load(path) as Texture2D
	_faction_logo_cache[path] = t
	return t


## 在给定方格里**等比缩放、居中**画一个阵营标志。
##
## ⚠️ 等比缩放用 `min(框宽/图宽, 框高/图高)`，**不能各轴独立拉伸** ——
## 两张 LOGO 的长宽比不同（马夫蒂偏瘦、联邦偏方），拉满格子会把徽记压扁变形。
##
## 图片加载失败时**不画**（返回 false），并由调用方留白：宁可空一块，
## 也不要一个红色占位方块 —— 那会被当成"LOGO 长这样"。
func _draw_roster_logo(r: BattleFormation.Roster, box: Rect2) -> bool:
	if r.logo_path == "" or not ResourceLoader.exists(r.logo_path):
		return false
	var tex := _faction_logo_tex(r.logo_path)
	if tex == null:
		return false
	var ts := tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return false
	# ⚠️ 等比缩放（`min`）而不是各轴拉满：两张 LOGO 的长宽比不同
	#（马夫蒂 485×657 偏瘦、联邦 663×757 偏方），拉满会把徽记压变形。
	var s := minf(box.size.x / ts.x, box.size.y / ts.y)
	var draw_size := ts * s
	var at := box.position + (box.size - draw_size) * 0.5
	draw_texture_rect(tex, Rect2(at, draw_size), false)
	return true


## 标题带（`TITLE_TOP` 起、高 `TITLE_BAND`）。
##
## 每一页**都占同样的高度**：第一页放 LOGO 贴图，第二、三页放文字标题 ——
## 高度一样，页面切换时下面的主面板就不会上下跳。
## LOGO 不存在时第一页退回文字标题（见 `title_texture()` 的说明）。
func _draw_title_band(title: String, subtitle: String, title_col: Color, with_logo := false) -> void:
	var left := UILayout.content_left(size)
	var tex := title_texture()
	if tex != null:
		# **LOGO 常驻左上角**（1.2 用户要求："title 图标要一直在主菜单的左上角位置"）。
		# 原来它只在第一页出现（`with_logo`），翻到第二、三页就没了 ——
		# 观感上是"标题在页与页之间跳来跳去"。
		# 第一页维持原样（LOGO 本身就是标题）；其它页把页面标题排在它右边，
		# 这样"我现在在哪一页"仍然一眼可见。
		var h := TITLE_LOGO_H
		var w := h * float(tex.get_width()) / float(tex.get_height())
		# LOGO 自带透明底，直接画；纵向居中在标题带里
		draw_texture_rect(tex, Rect2(left, TITLE_TOP + (TITLE_BAND - h) * 0.5, w, h), false)
		if with_logo:
			return
		left += w + 20.0
	# 没有 LOGO（或这一页不放 LOGO）：文字标题也落在同一条左边界上
	_text(Vector2(left + 12.0, TITLE_TOP + 42.0), title, 28, MENU_VISUALS.TEXT)
	if subtitle != "":
		_text(Vector2(left + 12.0, TITLE_TOP + 70.0), subtitle, 13, MENU_VISUALS.MUTED)
	draw_line(Vector2(UILayout.content_left(size), TITLE_TOP + TITLE_BAND + 8.0), Vector2(UILayout.content_right(size), TITLE_TOP + TITLE_BAND + 8.0), Color(MENU_VISUALS.EDGE, 0.7), UILayout.LINE_HAIR)


func _draw_starfield() -> void:
	# ⚠️ 星星铺满**整个屏幕**（批 29）。原来按 `LIST_END`（660）铺，下半屏连背景
	# 颗粒都没有 —— 那一块空白因此更像"界面坏了"而不是"留白"。
	# 颗数按面积走：分辨率变了密度不变。
	var n := maxi(int(size.x * size.y / 14000.0), 40)
	for i in n:
		var x := fmod(float(i) * 137.51, size.x)
		var y := fmod(float(i) * 71.13, size.y)
		var tw := 0.35 + 0.35 * sin(_time * 1.6 + float(i))
		draw_circle(Vector2(x, y), 1.0, Color(0.7, 0.85, 1.0, tw * 0.5))


## 顶部步骤条：左边是流程步骤（落在内容区左边界上），右边是"随时可进的设置"。
## 设置不是流程里的一步，所以它挂在右边界上，而不是挤进步骤里。
##
## 训练模式只有两步（模式 / 机体）—— 难度与地图对它没有意义，
## 步骤条就只画两步。**步骤条必须和实际流程一致**：印着四步却只走两步，
## 玩家会以为界面卡住了。
func _draw_step_bar() -> void:
	# ⚠️ **必须用 `step_labels()`**：这里曾经自己硬编码一份 4 项的旧列表，于是
	#   - 敌人页顶栏写着"③ 选择难度"，而页面是"选择敌人"（用户截图为证）；
	#   - 对战的第 5 步"选择地图"**永远点不亮**（`step_index()` 返回 4，落在 4 项之外）；
	#   - 挑战页印的也是错的（"③ 选择难度"应是"③ 选择遭遇"）。
	# 真源只有一个：`step_labels()`。这里再写一份就是给同一类 bug 留位置。
	var labels := step_labels()
	var cur := step_index()
	var x := UILayout.content_left(size)
	for i in labels.size():
		var on := i == cur
		var done := i < cur
		var col := MENU_VISUALS.FOCUS if on else (Color(0.53, 0.67, 0.65) if done else Color(0.35, 0.43, 0.50))
		var fs := 16 if on else 14
		_text(Vector2(x, STEP_Y), labels[i], fs, col)
		if on:
			# 当前步骤下面压一条指示线：比只换颜色更容易一眼定位
			var w := _font.get_string_size(labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_rect(Rect2(x, STEP_Y + 7.0, w, 2.0), col, true)
		x += clampf((UILayout.content_width(size) - 200.0) / maxf(float(labels.size()), 1.0), 130.0, 172.0)
	var sc := Color(0.55, 1.0, 0.74) if stage == Stage.SETTINGS else Color(0.42, 0.52, 0.62)
	_text_right(Vector2(UILayout.content_right(size), STEP_Y),
		InputSetup.hint("⚙ 设置（P）", "⚙ 设置（Start）"), 15, sc)


## 页脚提示行：左端对齐内容区、**锚定屏幕底边**（批 29）。
## 页与页之间这条线不动 —— 翻页时提示行不跳，页面底部也永远有个收口。
func _draw_hint(keyboard: String, pad: String) -> void:
	var left := UILayout.content_left(size)
	var right := UILayout.content_right(size)
	var y := hint_y(size)
	draw_line(Vector2(left, y - 28), Vector2(right, y - 28), Color(MENU_VISUALS.EDGE, 0.55), UILayout.LINE_HAIR)
	var hint := InputSetup.hint(keyboard, pad)
	if not InputSetup.using_gamepad and stage in [Stage.MODE, Stage.BATTLE, Stage.SIDE, Stage.SUIT, Stage.TRAINING, Stage.ENEMY, Stage.DIFFICULTY, Stage.MAP, Stage.ENCOUNTER]:
		hint = "鼠标悬停 / 点击    ·    " + hint
	_text(Vector2(left, y), hint, 14, MENU_VISUALS.MUTED)


# ============================================================ 联机页（1.2）

## **房间 + 密码**。这一页只管"收集玩家意图"，规则一条都不在这里写：
## 房间号 ↔ 端口、密码判定、广播报文格式全在 `LanRoom`（纯数据层，可无头单测）。
##
## 工程里没有任何 Control 节点（菜单全是 `_draw()` 画的），所以几个输入栏也自己实现：
## 一个"正在编辑"的字段用 `InputEventKey.unicode` 收字符，回车确认、退格删除。
##
## ⚠️ **行下标只有下面这一份**。历史上「地址 / 端口」那两行的下标 2 / 3
## 在 `_read_lan_input()` 与 `_input()`（原始字符输入）里**各写了一遍**，
## 插一行就得同时改两处，而"改漏一处"的症状是**那一栏收不到键盘**
##（页面上完全看不出来）。⇒ 现在一律走命名常量，字面量一个都不许有。

## 行下标（`LAN_ROWS` 的下标）—— **唯一真源**。
##
## ⚠️ 2026-10-11 用户拍板：「**先创建房间之后，再在房间里面决定对战模式和机体**」
## ⇒ 这一页**不再有「对战形式」那一行**：形式与机体都在**房间界面**里决定
## （`LOBBY_ROWS` 那 6 行）。理由与判据见 `LAN_FORMS` 的注释。
const LAN_ROW_CREATE := 0        ## 建房（端口由房间号导出）
const LAN_ROW_JOIN := 1          ## 加入
const LAN_ROW_CODE := 2          ## 房间号（可编辑）
const LAN_ROW_PASS := 3          ## 密码（可空 = 公开房）
const LAN_ROW_SEARCH := 4        ## 搜索房间（广播发现）
const LAN_ROW_ADV := 5           ## 高级（地址 / 端口）
const LAN_ROWS := ["创建房间", "加入房间", "房间号", "密码", "搜索房间",
	"高级（地址 / 端口）"]

## 高级子页的两行。
const LAN_ADV_ADDR := 0
const LAN_ADV_PORT := 1
const LAN_ADV_ROWS := ["地址", "端口"]

## 本页的三个**子模式**。
##
## ⚠️ 刻意**不新增 `Stage` 枚举值**：「高级」与「房间列表」是这一页内部的两屏，
## 而 `MainMenu.Stage` 被 `_draw()` / `_read_input()` / `suite_round` 四处逐个列举
##（加一个值要同步改 4 处，漏一处的症状同样是"没反应"）。
const LAN_SUB_MAIN := 0
const LAN_SUB_ADV := 1
const LAN_SUB_ROOMS := 2

## 正在编辑的字段（`_lan_field()` 的返回值）—— **唯一真源**。
## 字符输入 `_input()` 与光标绘制都问它，不各自去猜下标。
const LAN_FIELD_NONE := 0
const LAN_FIELD_ADDR := 1
const LAN_FIELD_PORT := 2
const LAN_FIELD_CODE := 3
const LAN_FIELD_PASS := 4

## 房间号 / 密码 / 广播报文的规则层。本页只调它，一条规则都不重写。
const LanRoom := preload("res://scripts/data/lan_room.gd")

var lan_row := LAN_ROW_CREATE
var lan_editing := false
var lan_sub := LAN_SUB_MAIN
var lan_adv_row := LAN_ADV_ADDR
## 玩家输的房间号（洗过的 6 位；空 = 还没生成）。
var lan_code := ""
## 玩家输的密码（明文只活在内存里；出门与判定一律走 `LanRoom.auth_hash()`）。
var lan_pass := ""
## 房间列表：搜到的房 + 当前选中下标（`lan_sub == LAN_SUB_ROOMS` 时才画）。
var lan_rooms: Array = []
var lan_room_sel := 0
## 建房用的随机源。**只建一次**：每次新建 `RandomNumberGenerator` 会拿到同一个种子。
var _lan_rng := RandomNumberGenerator.new()

## 联机可选的对战形式。⚠️ **下标 0 是小队战** —— 它是 `Game.active_lan_form`
## 的默认值，也就是"这一项不存在之前"联机唯一的行为（`LanPlan.Form` 有完整理由）。
##
## ⚠️ **2026-10-11 起这一页没有它的 UI 行了**：形式在**房间界面**里决定
##（用户：「先创建房间之后，再在房间里面决定对战模式和机体」）。
## 这张表仍然留着，因为它是**房间内那两行**的读数来源，也是"建房那一刻先报哪一档"的默认值。
const LAN_FORMS := [LanPlan.Form.SQUAD, LanPlan.Form.ACE_DUEL]
## 当前选中的形式（`LAN_FORMS` 的下标）。
##
## ⚠️ 进房间之后它**每帧被房间同步**（`_read_lan_room_input()` 里那条
## `LAN_FORMS.find(Net.choice_of("form", ...))`）⇒ 房间里的选择立刻反映到
## `selected_lan_form()`，而 `active_suit_list()` 跟着换表
##（王牌战 = 三台 ACE；小队战 = 按阵营过滤）。
var lan_form_choice := 0
## 已经按下「主机 / 加入」、正在**等对手的选择到齐**（见 `Net.choices_ready()`）。
##
## ⚠️ 这一段等待是必须的，不是"顺手加个进度提示"：这一局是按**双方的选择**算出来的
##（`LanPlan.build()`），而"出生之后改选择"等于重建整场。少一条选择就会退到兜底值，
## 于是两台机器各算出一局不同的对局 —— 一边场上 2 台、另一边 14 台，**两边都不报错**。
var _lan_wait := false
var lan_lobby_row := 0
var _lan_resolving := false
var _lan_resolve_serial := 0
var _lan_port_override := false
const LOBBY_ROWS := ["王牌战", "小队战", "阵营", "机体", "准备", "离开房间"]
## 已经等了多久（秒）。由 `_process(delta)` 累加，`_begin_lan_wait()` 归零。
##
## ⚠️ 计时放在 `_process()` 而不是 `_read_lan_input()`：那个函数只在 `active`
## 且没被输入锁挡着时跑，而"等对手"必须**一直在走表** —— 否则玩家一切换窗口
## 倒计时就停了（症状是"永远等不完"）。
var _lan_wait_elapsed := 0.0


## 当前选中的对战形式（`LanPlan.Form`）。
func selected_lan_form() -> int:
	return LAN_FORMS[clampi(lan_form_choice, 0, LAN_FORMS.size() - 1)]


## 形式的显示名（唯一的写法 —— 联机页与测试都读它）。
static func lan_form_label(form: int) -> String:
	return "王牌战 · 一人一台 1v1" if form == LanPlan.Form.ACE_DUEL \
		else "小队战 · 阵营编队"


## 能不能出击：**双方的选择都到齐了**。
##
## 规则本体在 `NetSession.launch_ready()`（纯 static，可单测），
## `Net.choices_ready()` = 那条规则 + 本机的实时状态。菜单**只调，不重写**：
## 这一条守的是"两台机器算同一局"，而**两份判断分家**正是那条失败最常见的来源
##（判据少一样就退到兜底值，两台机器各算出一局、两边都不报错）。


func _read_lan_input() -> void:
	# Esc 保险丝已经在本帧处理过返回（见 `_input()`），这一帧别再退一层
	if Engine.get_process_frames() == _esc_fuse_frame:
		return
	if _lan_resolving:
		if Input.is_action_just_pressed("menu_back") or _mi_back: _cancel_lan()
		return
	if _lan_wait:
		_read_lan_room_input()
		return

	# ---- 两个子屏各自处理自己的输入（进去之后就不再看主列表的行号）----
	if lan_sub == LAN_SUB_ADV:
		_read_lan_adv_input()
		return
	if lan_sub == LAN_SUB_ROOMS:
		_read_lan_rooms_input()
		return

	var dy := _axis_delta(nav_axis(Stage.LAN))
	if dy == 0: dy = _mi_d
	if dy != 0 and not lan_editing:
		lan_row = posmod(lan_row + dy, LAN_ROWS.size())
		Audio.play_ui("ui_select")
	if Input.is_action_just_pressed("menu_back") or _mi_back:
		if lan_editing:
			lan_editing = false
		else:
			_cancel_lan()
		Audio.play_ui("ui_return")
		return
	if lan_editing:
		_edit_lan_field()
		return
	if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("fire_gun") or _mi_ok:
		match lan_row:
			LAN_ROW_CREATE:
				_lan_start_host()
			LAN_ROW_JOIN:
				_lan_start_join()
			LAN_ROW_CODE, LAN_ROW_PASS:
				lan_editing = true
				Audio.play_ui("ui_select")
			LAN_ROW_SEARCH:
				lan_sub = LAN_SUB_ROOMS
				lan_room_sel = 0
				lan_rooms = []
				if LanBrowser.start_browse():
					Audio.play_ui("ui_select")
				else:
					Audio.play_ui("ui_return")
			LAN_ROW_ADV:
				lan_sub = LAN_SUB_ADV
				lan_adv_row = LAN_ADV_ADDR
				Audio.play_ui("ui_select")


## 建房。⚠️ 没输房间号就**自动生成**（老板拍板：主机生成 + 可复制），
## 生成后立刻写进剪贴板 —— 这是"可复制"在没有新增输入动作的前提下的落点
##（加一个可重绑动作要同步 5~6 张表，为一次复制不值当）。
func _lan_start_host() -> void:
	if not LanRoom.code_ok(lan_code):
		_lan_rng.randomize()
		lan_code = LanRoom.new_code(_lan_rng)
	var auth := LanRoom.auth_hash(lan_pass)
	if Net.host_room(lan_code, auth) != OK:
		Audio.play_ui("ui_return")
		return
	# 广播出去，别人就能在「搜索房间」里看见本房；`locked` 只回答"要不要密码"。
	LanBrowser.host_beacon(lan_code, Net.port, selected_lan_form(), lan_pass != "")
	DisplayServer.clipboard_set(lan_code)
	Audio.play_ui("ui_confirm")
	_begin_lan_wait()


## 加入。⚠️ 房间号不合法就**什么都不做**（而不是连一个必然失败的端口）——
## 端口是从房间号导出来的，宁可让玩家看见读数栏里那句"先输入 6 位房间号"。
func _lan_start_join(endpoint: Dictionary = {}) -> void:
	if _lan_resolving or not LanRoom.code_ok(lan_code):
		Audio.play_ui("ui_return")
		return
	var destination := endpoint.duplicate()
	if destination.is_empty():
		for room: Dictionary in LanBrowser.rooms():
			if String(room.get("code", "")) == lan_code:
				destination = room
				break
	# A room code identifies the room, not the machine hosting it. Resolve its
	# beacon before using the default loopback address on another player's PC.
	if destination.is_empty() and Net.address in ["", "127.0.0.1", "localhost", "::1"]:
		_lan_resolving = true
		_lan_resolve_serial += 1
		var ticket := _lan_resolve_serial
		var wanted := lan_code
		Game.lan_status = "正在查找房间 " + wanted + " 的主机地址…"
		var browsing := LanBrowser.start_browse()
		var deadline := Time.get_ticks_msec() + 3500
		while browsing and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
			if ticket != _lan_resolve_serial: return
			for room: Dictionary in LanBrowser.rooms():
				if String(room.get("code", "")) == wanted:
					destination = room
					break
			if not destination.is_empty(): break
		LanBrowser.stop_browse()
		_lan_resolving = false
		if destination.is_empty():
			Game.lan_status = "未找到该房间：确认房主已建房，或在高级中填写房主地址"
			Audio.play_ui("ui_return")
			return
	var addr := String(destination.get("ip", Net.address))
	var room_port := int(destination.get("port", Net.port if _lan_port_override else LanRoom.port_of_room(lan_code)))
	if Net.join_room(lan_code, addr, LanRoom.auth_hash(lan_pass), room_port) != OK:
		Audio.play_ui("ui_return")
		return
	Audio.play_ui("ui_confirm")
	_begin_lan_wait()


## 高级子页（地址 / 端口）—— 跨网段时才用得到。
func _read_lan_adv_input() -> void:
	var dy := _axis_delta(nav_axis(Stage.LAN))
	if dy == 0: dy = _mi_d
	if dy != 0 and not lan_editing:
		lan_adv_row = posmod(lan_adv_row + dy, LAN_ADV_ROWS.size())
		Audio.play_ui("ui_select")
	if Input.is_action_just_pressed("menu_back") or _mi_back:
		if lan_editing:
			lan_editing = false
		else:
			lan_sub = LAN_SUB_MAIN
		Audio.play_ui("ui_return")
		return
	if lan_editing:
		_edit_lan_field()
		return
	if Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("fire_gun") or _mi_ok:
		lan_editing = true
		Audio.play_ui("ui_select")


## 房间列表：选中即加入 —— 所以这里**不需要玩家再抄一遍房间号**。
func _read_lan_rooms_input() -> void:
	# ⚠️ 每帧重取：`LanBrowser` 里那几条会在 3 秒收不到广播后自然过期，
	# 而"列表里留着一个点不进去的幽灵房"是最容易让人以为程序坏了的那种 bug。
	lan_rooms = LanBrowser.rooms()
	var n := lan_rooms.size()
	lan_room_sel = clampi(lan_room_sel, 0, maxi(n - 1, 0))
	var dy := _axis_delta(nav_axis(Stage.LAN))
	if dy == 0: dy = _mi_d
	if dy != 0 and n > 0:
		lan_room_sel = posmod(lan_room_sel + dy, n)
		Audio.play_ui("ui_select")
	if Input.is_action_just_pressed("menu_back") or _mi_back:
		LanBrowser.stop_browse()
		lan_sub = LAN_SUB_MAIN
		Audio.play_ui("ui_return")
		return
	if n > 0 and (Input.is_action_just_pressed("confirm")
			or Input.is_action_just_pressed("fire_gun") or _mi_ok):
		var r: Dictionary = lan_rooms[lan_room_sel]
		# 广播把**真实端口**与**房主的 IP** 一起带回来了 ⇒ 不必靠房间号反推端口，
		# 也就没有"两个房间号撞同一个端口"的歧义。
		lan_code = String(r.get("code", ""))
		Net.address = String(r.get("ip", Net.address))
		Net.port = int(r.get("port", Net.port))
		LanBrowser.stop_browse()
		lan_sub = LAN_SUB_MAIN
		_lan_start_join(r)


## 正在编辑哪个字段 —— **唯一真源**（`_input()` 与绘制都问它）。
func _lan_field() -> int:
	if not lan_editing:
		return LAN_FIELD_NONE
	if lan_sub == LAN_SUB_ADV:
		return LAN_FIELD_ADDR if lan_adv_row == LAN_ADV_ADDR else LAN_FIELD_PORT
	if lan_row == LAN_ROW_CODE:
		return LAN_FIELD_CODE
	if lan_row == LAN_ROW_PASS:
		return LAN_FIELD_PASS
	return LAN_FIELD_NONE


## 退格：按 `_lan_field()` 决定删哪一条。**与 `_lan_type()` 同一处口径**。
func _lan_backspace() -> void:
	match _lan_field():
		LAN_FIELD_ADDR:
			Net.address = Net.address.substr(0, maxi(Net.address.length() - 1, 0))
		LAN_FIELD_PORT:
			_lan_port_override = true
			Net.port = int(str(Net.port).substr(0, maxi(str(Net.port).length() - 1, 0)))
		LAN_FIELD_CODE:
			lan_code = lan_code.substr(0, maxi(lan_code.length() - 1, 0))
		LAN_FIELD_PASS:
			lan_pass = lan_pass.substr(0, maxi(lan_pass.length() - 1, 0))


## 收一个字符。
##
## ⚠️ 洗输入**只走 `LanRoom.sanitize_*()`**：这里再写一遍"只收 0-9"，
## 回显与判定就会分家（`producer.gd` 开头那段说的是同一条纪律）。
func _lan_type(ch: String) -> void:
	match _lan_field():
		LAN_FIELD_ADDR:
			if (ch >= "0" and ch <= "9") or ch == ".":
				if Net.address.length() < 20:
					Net.address += ch
		LAN_FIELD_PORT:
			_lan_port_override = true
			if ch >= "0" and ch <= "9" and str(Net.port).length() < 5:
				Net.port = int(str(Net.port) + ch)
		LAN_FIELD_CODE:
			lan_code = LanRoom.sanitize_code(lan_code + ch)
		LAN_FIELD_PASS:
			lan_pass = LanRoom.sanitize_pass(lan_pass + ch)


## 收拾联机这一摊：退出等待态、停广播、断连接（**回不回上层由调用方定**）。
##
## ⚠️ 三件事**必须成对**：只停广播不断连接 ⇒ 对手还能连进来、而本机已经不认这一局；
## 只断连接不停广播 ⇒ 房间列表里留一个"幽灵房"（别人搜得到、连不上）。
## ⚠️ `Net.close()` 会把 `Game.lan_status` 清空 —— 想留一句话就得写在它**之后**。
func _lan_teardown() -> void:
	_lan_resolve_serial += 1
	_lan_resolving = false
	_lan_wait = false
	_lan_wait_elapsed = 0.0
	LanBrowser.stop()
	Net.close()


## 彻底放弃这次联机、回机体选择页（`menu_back` / Esc 的语义）。
func _cancel_lan() -> void:
	_lan_teardown()
	# ⚠️ 2026-10-11：联机现在**从模式页直接进**（不再经过机体页）
	# ⇒ 退出去要回**模式页**。回 `Stage.SUIT` 会把玩家丢进一个"从没来过、
	# 也不再属于联机流程"的页面上（而且是**静默**的：页面照画）。
	stage = Stage.MODE


## 开主机 / 加入之后：把本机的三个选择交给网络层，然后**等对手的选择**。
##
## ⚠️ 选择必须在这里交给网络层，而不是等 `main._resolve_match()` ——
## 那一步在**出击那一刻**才跑，而"主机等待对手加入"这段时间里 `Game.active_suit`
## 还是**上一局**的值（`NetSession._choice` 的注释里有完整说明）。
##
## ⚠️ 密码也走这条链：`_my_auth` 由 `host_room()` / `join_room()` 写进网络层，
## 再由 `_send_hello()` 和那三个选择**合成一个包**发出去（`_rpc_hello4`）。
## ⇒ "密码"没有自己的状态机，少一个同步点。
func _begin_lan_wait() -> void:
	Net.announce_choice(selected_suit(), side_index_to_side(), selected_lan_form())
	_lan_wait = true
	lan_lobby_row = 4
	_lan_wait_elapsed = 0.0


## 收字符编辑地址 / 端口。
## 字符输入必须走 `_input()`（`Input.parse_input_events` 那种"回放"在本工程里没有用武之地），
## 这里只保留一个"编辑态还在不在"的检查 —— 真正的字符处理在 `_input()` 里。
func _edit_lan_field() -> void:
	if Input.is_action_just_pressed("menu_back"):
		lan_editing = false


## 原始事件处理。三件事，全部要拿**未经 InputMap 加工**的事件：
## ① **写死 Esc 的保险丝（§4.8.4 第③层）** —— 不经过 InputMap。只要按键表、
##    配置文件、或用户的改动把 `menu_back` 弄没了，玩家还能靠 Esc 从设置页 /
##    重绑页退出去。它看起来"和 InputMap 重复"，但价值恰恰在于**不依赖 InputMap**：
##    输入系统出问题的症状永远是"没反应"，而"没反应"是最难归因的一种失败。
## ② 重绑页等待态的按键捕获（只有这里拿得到原始事件）。
## ③ 联机页编辑态的键盘字符输入（原有逻辑，见函数尾部）。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_pointer_tilt_active = true
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_pointer_tilt_active = false
	if visible and is_instance_valid(_home_view) and _home_view.handles_stage():
		_home_view.route_event(event)
		return
	_handle_mouse(event)
	if active and (stage == Stage.SETTINGS or stage == Stage.KEYS \
			or stage == Stage.BGM or stage == Stage.FPV_CONFIRM \
			or stage == Stage.PASSWORD or stage == Stage.LAN) \
			and event is InputEventKey:
		var esc := event as InputEventKey
		if esc.pressed and not esc.echo and esc.keycode == KEY_ESCAPE:
			if stage == Stage.LAN:
				# 联机页：Esc 与 `menu_back` 同义（底行就写着「（Esc 取消）」）。
				# ⚠️ 必须是**独立**分支 —— 落到下面那条逻辑里会把它判成"回设置页"。
				# ⚠️ 次序与 `_read_lan_input()` 保持一致：编辑态先退一层，不退页。
				if lan_editing:
					lan_editing = false
				else:
					_cancel_lan()
				Audio.play_ui("ui_return")
				# 告诉轮询路径：这一帧的返回已经处理过，别再退一层
				_esc_fuse_frame = Engine.get_process_frames()
				get_viewport().set_input_as_handled()
				return
			if stage == Stage.KEYS and waiting_bind:
				waiting_bind = false   # 等待态的取消也走保险丝（不走 InputMap）
				wait_action = ""
			else:
				# 选歌页 / 重绑页 / 眩晕警告框都回设置页；设置页本身回它的来路
				#
				# ⚠️ 眩晕警告框从 Esc 退出去 = **什么都不改**（`_read_fpv_confirm_input`
				# 之后不会再跑，因为 stage 已经变回 SETTINGS）。
				# 这正是这道保险丝的价值：警告框卡住时玩家永远有一条不生效的出口。
				if stage == Stage.SETTINGS and settings_sub == SET_SUB_VOLUME:
					# ★63-23：音量细分子屏**只退一层**（回设置页主屏），
					# 与 `_read_volume_input()` 里 `menu_back` 的分支逐字对应。
					# 少了这一支，Esc 会一次跨两层（音量页 → 菜单来路），
					# 而 Esc 与 P 在同一页上行为不同是最容易让人以为"按键坏了"的那种不一致。
					settings_sub = SET_SUB_MAIN
				elif stage == Stage.BGM and bgm_sub == BGM_SUB_LIST:
					# ★63-22：歌单页**只退一层**（回选歌页），与 `_read_bgm_input()` 里
					# `menu_back` 的分支逐字对应。少了这一支，Esc 会一次跨两层
					#（歌单页 → 设置页），而 Esc 与 `menu_back` 在同一页上行为不同
					# 是最容易让人以为"按键坏了"的那种不一致。
					bgm_sub = BGM_SUB_PICK
					bgm_msg = ""
				elif stage == Stage.KEYS or stage == Stage.BGM \
						or stage == Stage.FPV_CONFIRM or stage == Stage.PASSWORD:
					stage = Stage.SETTINGS
				else:
					stage = _settings_return_stage
			keys_msg = ""
			pw_input = ""
			pw_msg = ""
			Audio.play_ui("ui_return")
			# 告诉轮询路径：这一帧的返回已经处理过，别再退一层
			_esc_fuse_frame = Engine.get_process_frames()
			get_viewport().set_input_as_handled()
			return
	# ---- 密码页的数字输入（**只有原始事件拿得到字符**）----
	#
	# ⚠️ 与联机页的地址/端口输入是同一条路（见本函数尾部）：字符走 `InputEventKey.unicode`，
	# 退格自己处理 —— `InputMap` 里的动作名是不分字符的，靠 `is_action_just_pressed`
	# 永远拿不到"刚才按的是哪一个数字键"。
	# ⚠️ 洗输入**只走 `PROD.sanitize()`**：这里再写一遍"只收 0-9"，回显与判定就会分家。
	if active and stage == Stage.PASSWORD and event is InputEventKey:
		var pk := event as InputEventKey
		if pk.pressed and not pk.echo:
			if pk.keycode == KEY_BACKSPACE:
				pw_input = pw_input.substr(0, maxi(pw_input.length() - 1, 0))
				pw_msg = ""          # 一改输入就把上一次的结果收掉（红字留着会让人以为又错了）
				get_viewport().set_input_as_handled()
				return
			if pk.unicode > 0:
				var ch := char(pk.unicode)
				if ch >= "0" and ch <= "9":
					pw_input = PROD.sanitize(pw_input + ch)
					pw_msg = ""
					get_viewport().set_input_as_handled()
				return
	if active and stage == Stage.KEYS and waiting_bind:
		if event is InputEventKey:
			var kcap := event as InputEventKey
			# 滤掉长按产生的重复事件与纯修饰键（只按下 Shift 不算一次绑定）
			if kcap.pressed and not kcap.echo \
					and not InputSetup._is_modifier_key(kcap.physical_keycode):
				_capture_rebind(kcap)
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton:
			var mcap := event as InputEventMouseButton
			if mcap.pressed:
				_capture_rebind(mcap)
				get_viewport().set_input_as_handled()
		elif event is InputEventJoypadButton:
			# 手柄按键（批 10：手柄进自定义）。**B 例外**：它落回 `_read_keys_input`
			# 的轮询取消（menu_back 动作）—— 等待态永远留着"按 B 反悔"这条路，
			# 否则手柄玩家按错一格就被锁死在等待态里。
			var jcap := event as InputEventJoypadButton
			if jcap.pressed and jcap.button_index != JOY_BUTTON_B:
				_capture_rebind(jcap)
				get_viewport().set_input_as_handled()
		return
	if stage != Stage.LAN or not lan_editing:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		lan_editing = false
		return
	if k.keycode == KEY_BACKSPACE:
		_lan_backspace()
		return
	if k.unicode <= 0:
		return
	_lan_type(char(k.unicode))


## 本页的**三个子屏**都从这里进（`Stage` 枚举不新增值，见 `LAN_SUB_*`）。
func _draw_lan_stage() -> void:
	_draw_title_band("局域网联机", "同一局域网内两人对打 · 一人建房、一人加入",
		Color(0.62, 0.92, 1.0), false)
	match lan_sub:
		LAN_SUB_ADV:
			_draw_lan_adv()
		LAN_SUB_ROOMS:
			_draw_lan_rooms()
		_:
			_draw_lan_main()
	_draw_lan_footer()


## 主列表（7 行）。放得下的行数由版式算（批 29 的做法）。
func _draw_lan_main() -> void:
	if _lan_wait:
		_draw_lan_lobby()
		return
	var g := _list_geometry()
	for i in range(g.first,g.first+g.shown):
		_draw_lan_row(row_rect(size,g,i),i,i==lan_row)
	_draw_scroll_indicator(g.count,lan_row,g.shown,g.m)


## 高级子页（地址 / 端口）—— 跨网段的手工通道。
func _draw_lan_adv() -> void:
	var g := _list_geometry()
	for i in range(g.first,g.first+g.shown):
		_draw_lan_adv_row(row_rect(size,g,i),i,i==lan_adv_row)
	_draw_scroll_indicator(g.count,lan_adv_row,g.shown,g.m)


## 房间列表（广播发现的结果）。
func _draw_lan_rooms() -> void:
	if lan_rooms.is_empty():
		_text(Vector2(UILayout.content_left(size), LAN_ROW_H + 120.0),
			"正在搜索局域网里的房间…（Esc 返回）", 20, Color(0.72, 0.82, 0.94))
		return
	var g := _list_geometry()
	for i in range(g.first,g.first+g.shown):
		_draw_lan_room_row(row_rect(size,g,i),i,i==lan_room_sel)
	_draw_scroll_indicator(g.count,lan_room_sel,g.shown,g.m)


## 状态行 + 提示行。三条子屏共用（免得三份文案各自漂开）。
func _draw_lan_footer() -> void:
	var st := Game.lan_status
	if st == "":
		st = "尚未连接"
	if _lan_wait:
		st = "房间 " + lan_code + " · " + ("房主" if Net.role == Net.Role.HOST else "加入方")
		st += " · " + Game.lan_status

	_text(Vector2(UILayout.content_left(size), _lan_list_bottom() + 26.0),
		"状态：" + st, 15, Color(0.95, 0.80, 0.35))
	_draw_hint(_lan_hint_key(), "十字键 / 左摇杆 选择 · A 确认 · B 返回")


## 当前子屏的列表底边（状态行贴着它排）。
func _lan_list_bottom() -> float:
	if _lan_wait:
		var lm := list_metrics(size, LOBBY_ROWS.size(), LAN_ROW_H, LAN_ROW_GAP, LAN_ROW_MAX)
		var lw := scroll_window(LOBBY_ROWS.size(), lan_lobby_row, int(lm["shown"]))
		return list_bottom_y(lw.x, lw.y, lm)
	match lan_sub:
		LAN_SUB_ADV:
			var ma := list_metrics(size, LAN_ADV_ROWS.size(), LAN_ROW_H, LAN_ROW_GAP, LAN_ROW_MAX)
			var wa := scroll_window(LAN_ADV_ROWS.size(), lan_adv_row, int(ma["shown"]))
			return list_bottom_y(wa.x, wa.y, ma)
		LAN_SUB_ROOMS:
			if lan_rooms.is_empty():
				return LAN_ROW_H + 120.0
			var mr := list_metrics(size, lan_rooms.size(), LAN_ROW_H, LAN_ROW_GAP, LAN_ROW_MAX)
			var wr := scroll_window(lan_rooms.size(), lan_room_sel, int(mr["shown"]))
			return list_bottom_y(wr.x, wr.y, mr)
	var m := list_metrics(size, LAN_ROWS.size(), LAN_ROW_H, LAN_ROW_GAP, LAN_ROW_MAX)
	var w := scroll_window(LAN_ROWS.size(), lan_row, int(m["shown"]))
	return list_bottom_y(w.x, w.y, m)


func _lan_hint_key() -> String:
	if _lan_wait:
		return "W / S 选择 · ← / → 调整 · Enter 确认 / 准备 · Esc 离开房间"
	if lan_sub == LAN_SUB_ROOMS:
		return "W / S 选择 · Enter 加入这一间 · Esc 回到列表"
	if lan_sub == LAN_SUB_ADV:
		return "W / S 选择 · Enter 编辑 · Esc 回到列表"
	var extra := ""
	if lan_row == LAN_ROW_PASS:
		extra += "　·　" + LanRoom.PASS_NOTE
	return "W / S 选择 · Enter 访问 / 开始编辑 · Esc 返回" + extra


## 主列表每一行的读数 —— **纯函数**。
## `suite_lan_room` 拿它验"`LAN_ROWS` 的每一行都有绘制消费者"（防"加了行但没画"）。
func lan_row_value(row: int) -> String:
	match row:
		LAN_ROW_CREATE:
			return "端口 " + str(LanRoom.port_of_room(lan_code))
		LAN_ROW_JOIN:
			if not LanRoom.code_ok(lan_code):
				return "先输入 6 位房间号"
			return Net.address + " : " + str(LanRoom.port_of_room(lan_code))
		LAN_ROW_CODE:
			if lan_code == "":
				return "（未设置 · 建房时自动生成）"
			return lan_code
		LAN_ROW_PASS:
			if lan_pass == "":
				return LanRoom.PASS_OPEN_TEXT
			var dots := ""
			for i in lan_pass.length():
				dots += "●"
			return dots
		LAN_ROW_SEARCH:
			return "已搜到 " + str(lan_rooms.size()) + " 个"
		LAN_ROW_ADV:
			return Net.address + " : " + str(Net.port)
	return ""


## 高级子页每一行的读数（同样是纯函数）。
func lan_adv_value(row: int) -> String:
	if row == LAN_ADV_ADDR:
		return Net.address
	return str(Net.port)


func _draw_lan_row(r: Rect2, row: int, focused: bool) -> void:
	_draw_lan_row_base(r, LAN_ROWS[row], lan_row_value(row), _lan_row_hint(row),
		focused, _lan_field() != LAN_FIELD_NONE and row == lan_row, "")


func _draw_lan_adv_row(r: Rect2, row: int, focused: bool) -> void:
	_draw_lan_row_base(r, LAN_ADV_ROWS[row], lan_adv_value(row),
		"跨网段时才需要改（日常用房间号）", focused,
		_lan_field() != LAN_FIELD_NONE and row == lan_adv_row, "")


func _draw_lan_room_row(r: Rect2, row: int, focused: bool) -> void:
	var info: Dictionary = lan_rooms[row]
	var code := String(info.get("code", ""))
	_draw_lan_row_base(r, code, "", "Enter 加入这一间", focused, false,
		LanRoom.room_line(code, int(info.get("form", 0)),
			int(info.get("players", 0)), bool(info.get("locked", false))))


## 三张列表共用的行画法（左标题 / 中读数 或 中副文 / 右注）。
##
## ⚠️ 边框一律 `UILayout.LINE_STRUCT`：`suite_ui_style` 扫 `draw_*` 的**实参原文**，
## 要求字面出现 `UILayout.LINE_*`、且**一个数字都不许有**。
func _draw_lan_row_base(r: Rect2, title: String, value: String, note: String,
		focused: bool, editing: bool, sub_text: String) -> void:
	var col := Color(0.62, 0.92, 1.0)
	MENU_VISUALS.row(self, r, col, focused)
	var left := r.position.x + UILayout.PAD
	var right := r.position.x + r.size.x - UILayout.PAD
	var y := text_vcenter(r, 22)
	_choice_text(Vector2(left, y), title, 22, col, focused)
	if sub_text != "":
		_text(Vector2(left + 168.0, y), sub_text, 20, Color(0.95, 0.80, 0.35))
	else:
		if editing:
			value += "_"
		_text(Vector2(left + 420.0, y), value, 20, Color(0.95, 0.80, 0.35))
	if note != "":
		_text_right(Vector2(right, y), note, 14, Color(0.66, 0.78, 0.90))


## 主列表每行的右侧注（"按下去会发生什么"）。
func _lan_row_hint(row: int) -> String:
	match row:
		LAN_ROW_CREATE:
			return "Enter 建房（房间号自动生成并复制）"
		LAN_ROW_JOIN:
			return "Enter 加入"
		LAN_ROW_SEARCH:
			return "Enter 搜索"
		LAN_ROW_ADV:
			return "Enter 打开"
	return ""


# ============================================================ ★63-23 音量细分页

## 音量细分页的通道清单：`{"label": 显示名, "bus": Settings 的总线名}`。
##
## ## 为什么是**函数**而不是 `const`
## `const` 里**不能引用 autoload**（`Settings.BUS_VULCAN` 在常量求值期还不存在，
## 解析器直接报错）。所以名单在运行时构造 —— 好处是**总线名只写一份**
##（就是 `Settings.BUS_*` 那几个常量）：写成 `const` 表的话，"`"VULCAN"` 少打一个字母"
## 会**静默**退化成"这根滑条拖了没反应"，而且不报错、不红。
##
## ## 顺序 = 面板上的顺序，也 = 「从总到细」的阅读顺序
## BGM / 音效总闸在最上面，六条细分跟在后面 —— 与总线树
##（`SFX` → 六个子通道）是同一棵树，玩家看到的就是实际发生的。
##
## ## ⚠️ 每一行的 `bus` 必须是一条**活总线**
## 有两节判据钉着（`suite_volume_mixer`）：
##   ① 每个 `bus` 都在 `AudioServer` 里存在；
##   ② 这把清单里的总线名与 `Settings.BUS_ORDER` 是**同一套**（不多不少）。
## 少了它们，`_volume_step()` 里的 `Settings.volume(bus)` 会返回 0.0 而 `set_volume`
## 变成 no-op ⇒ 滑条画得出来、拖不动。
static func volume_rows() -> Array:
	return [
		{"label": "BGM", "bus": Settings.BUS_BGM},
		{"label": "音效（总闸）", "bus": Settings.BUS_SFX},
		{"label": "武器 · 机枪", "bus": Settings.BUS_VULCAN},
		{"label": "武器 · 光束军刀", "bus": Settings.BUS_SABER},
		{"label": "武器 · 光束步枪", "bus": Settings.BUS_RIFLE},
		{"label": "武器 · 浮游飞弹", "bus": Settings.BUS_FUNNEL},
		{"label": "警报（含座舱语音）", "bus": Settings.BUS_ALARM},
		{"label": "引擎", "bus": Settings.BUS_ENGINE},
	]


## 音量细分页的调值：左/右步进 5%（长按连调与设置页主屏同一档）。
##
## ⚠️ 总线名从 `volume_rows()` **现取**（不是另写一份 switch）——
## 这样"面板上第 N 行是哪条总线"只有一个答案。
func _volume_step(delta: float) -> void:
	var rows := volume_rows()
	if rows.is_empty():
		return
	var dir := _step_dir(delta)
	if dir == 0:
		return
	var i := clampi(volume_row, 0, rows.size() - 1)
	var bus := str(rows[i]["bus"])
	Settings.set_volume(bus, Settings.volume(bus) + float(dir) * Settings.VOLUME_STEP)


## 音量细分页：上/下选通道，左/右调值（Esc / P 退**一层**回设置页主屏）。
##
## ⚠️ 这里**没有**"左右键当上下用"那条别名 —— 与选歌页相反。
## 原因：这一页左右键**已经有活干**（调值），是设置页那一套。
## 照抄选歌页的别名会让"左右到底调不调值"变成一个看页面的谜题。
func _read_volume_input() -> void:
	# Esc 保险丝已经在本帧处理过返回（见 `_input()`），这一帧别再退一层
	if Engine.get_process_frames() == _esc_fuse_frame:
		return
	var ny := _axis_delta(nav_axis(Stage.SETTINGS))
	if ny != 0:
		volume_row = posmod(volume_row + ny, maxi(volume_rows().size(), 1))
		Audio.play_ui("ui_select")
	var back := Input.is_action_just_pressed("menu_back") \
		or Input.is_action_just_pressed("open_settings")
	if back:
		# 只退**一层**：回设置页主屏（不是直接退出设置）。
		# ⚠️ 与 `_input()` 里那条 Esc 保险丝的分支**逐字对应** ——
		# 两边不一致的症状是"Esc 与 P 在同一页上行为不同"，最容易被当成按键坏了。
		settings_sub = SET_SUB_MAIN
		Audio.play_ui("ui_return")


## 音量细分页的绘制。版式与设置页主屏同一套（`list_panel_metrics` + `scroll_window`），
## 八行 ⇒ 900 高下全画得出来，不用滚动。
func _draw_volume_stage() -> void:
	_draw_title_band("音量 · 各通道",
		"改动立即生效 · 0% = 真静音 · 音效（总闸）拉到 0 全场安静",
		Color(0.75, 0.88, 1.0), false)
	var rows := volume_rows()
	var m := list_panel_metrics(size, rows.size(), SETTING_ROW_H, SETTING_ROW_MAX)
	var vis := int(m["shown"])
	var win := scroll_window(rows.size(), volume_row, vis)
	var r := list_panel_rect(size, m)
	MENU_VISUALS.panel(self, r)
	var left := r.position.x + UILayout.PAD
	var right := r.position.x + r.size.x - UILayout.PAD

	for i in range(win.x, win.x + win.y):
		var rr := list_row_rect(size, i, win.x, m)
		var ry := text_vcenter(rr, 18)
		var on := i == volume_row
		if on:
			MENU_VISUALS.selected_line(self, rr)
		var bus := str(rows[i]["bus"])
		var v := Settings.volume(bus)
		_choice_text(Vector2(left, ry), str(rows[i]["label"]), 18,
			Color(0.90, 0.96, 1.0) if on else Color(0.62, 0.72, 0.84), on)
		# 音量条与主屏那两根**共用** `_draw_volume_bar()`：同一根条在两个页面里
		# 长得不一样（刻度/箭头/宽度任一不同）会让人以为量的是不同的东西。
		# 数值列右端 = 内容区右边界（与设置页同一条线）。
		_draw_volume_bar(right - 246.0, ry, 150.0, v, on)
		_text_right(Vector2(right, ry), "%d%%" % int(round(v * 100.0)), 18,
			Color(0.95, 0.80, 0.35) if on else Color(0.70, 0.80, 0.92))

	_draw_scroll_indicator(rows.size(), volume_row, vis, m)
	_draw_hint(
		"W / S 选择通道        A / D 或 Q / E 调整（长按连调）        P 或 Esc 返回",
		"十字键 / 左摇杆 选择        左摇杆 ←→ 调整        Start / B 返回")


# ============================================================ 设置页

func _setting_value_text(key: String) -> String:
	match key:
		"resolution":
			return Settings.resolution_label()
		"fullscreen":
			return "全屏" if Settings.fullscreen else "窗口"
		"bgm":
			return "%d%%" % int(round(Settings.bgm_volume * 100.0))
		"sfx":
			return "%d%%" % int(round(Settings.sfx_volume * 100.0))
		"battle_bgm":
			return Settings.battle_bgm_label()
		"battle_playlist":
			# ★63-22：印"几首 / 上限"，空歌单印一句人话（只印 `0/6` 分不清
			# "没设"和"没存上"）。见 `Settings.playlist_label()`。
			return Settings.playlist_label()
		"cam_roll":
			return Settings.cam_roll_label()
		"cam_shake":
			return Settings.cam_shake_label()
		"first_person":
			return Settings.first_person_label()
		"motion":
			return "开（最低动态）" if Settings.reduce_motion else "关"
		"low_end_60":
			return ["低画质 / 750 Ti · 60帧优先","平衡","高画质","自定义"][Settings.quality_preset]
		"render_scale": return ("%d%% · 最高720p" if Settings.low_spec_mode() else "%d%%") % int(round(Settings.render_scale()*100))
		"dynamic_resolution": return "开" if Settings.dynamic_resolution else "关"
		"shadows": return ["关闭","近景","完整"][Settings.shadow_quality]
		"effects": return ["精简","标准","完整"][Settings.effects_quality]
		"magnifier_quality": return "%d Hz" % int(Settings.magnifier_hz())
		"ssao":
			return Settings.ssao_label()
		"cel":
			return Settings.cel_shading_label()
		"producer":
			# ★ 隐形行（2026-09-30）。关着的时候这一行的读数**谁也不会看到**
			#（那一行整个不画，见 `setting_row_hidden()`）—— 所以它答的其实是
			# "开了之后这一行该写什么"。
			# ⚠️ 文案的唯一真源是 `producer.gd`（`ON_TEXT`），这里不另写一句：
			# "改密码本子却忘了改这一行"是两处各写一份的经典症状。
			return PROD.ON_TEXT if Game.producer_mode else ""
	return ""


func _draw_settings_stage() -> void:
	_draw_title_band("设 置", "改动立即生效，并自动保存到 user://settings.cfg",
		Color(0.75, 0.88, 1.0), false)

	# 行高按内容区自适应（36..52）：行数够多时面板会撑到内容区高度，
	# 屏幕再矮才回落到最小行高 + 滚动窗口（与模式/敌机页同一套机制）。
	# ⚠️ 行数**不写死在这里**（`SETTING_ROWS` 是唯一真源）：2026-09-30 加了那个
	# 隐形行之后就是 14 行 —— 写死一个数的话，加行的人只能靠记性避坑
	#（"模式 4 → 5 / 敌机 3 → 5 两次都排到底部面板上"就是那么来的）。
	var m := settings_metrics(size)
	var r := list_panel_rect(size, m)
	MENU_VISUALS.panel(self, r)
	var left := r.position.x + UILayout.PAD
	var right := r.position.x + r.size.x - UILayout.PAD

	# 三条不变量同一套：窗口 ≤ 可见行数 / 聚焦项必在窗口里 / 放得下时不画指示条。
	var vis := int(m["shown"])
	var win := scroll_window(SETTING_ROWS.size(), setting_row, vis)
	for i in range(win.x, win.x + win.y):
		# ★ 隐形行（2026-09-30）：**"画不画"由 `setting_row_hidden()` 回答**，
		# 而不是"画的时候记得跳过" —— 后者是 `mission_brief` 那条恒假条件的形状
		#（写一个没人复核的条件决定画不画，静默失效一整轮）。这里判据能直接量。
		# ⇒ 停在它上面时这一页看起来就是"什么都没选中"，这就是老板那句
		#   「藏到最地下**看不到**的地方」。
		if setting_row_hidden(i, Game.producer_mode):
			continue
		var key := str(SETTING_ROWS[i]["key"])
		var rr := list_row_rect(size, i, win.x, m)
		var ry := text_vcenter(rr, 18)
		var on := i == setting_row
		if on:
			MENU_VISUALS.selected_line(self, rr)

		var label_col := Color(0.90, 0.96, 1.0) if on else Color(0.62, 0.72, 0.84)
		# ⚠️ 标题走 `setting_label()`（不直接读 `row["label"]`）：制作人模式那一行的
		# 名字只有一份真源在 `producer.gd` 里，见那个函数的说明。
		_choice_text(Vector2(left, ry), setting_label(i), 18, label_col, on)

		if _setting_is_action(key):
			# ⚠️ 制作人模式那一行的提示是「Enter 关闭」：它在这里被画出来 ⇒ 它一定
			# 是**开着**的（关着时整行不画），而 Enter 那一下就是关掉它。
			# 三处必须一致：提示、`_activate_producer()` 的分支、`PROD.ON_TEXT`。
			var hint := "Enter 返回" if key == "back" \
				else ("Enter 设置" if key == "keys" \
				else ("Enter 关闭" if key == PRODUCER_KEY else "Enter 退出"))
			var hcol := Color(1.0, 0.55, 0.45) if key == "quit" else Color(0.95, 0.80, 0.35)
			_text_right(Vector2(right, ry), hint, 16,
				hcol if on else Color(0.55, 0.64, 0.74))
			continue

		if key == "volume":
			# ★63-23：这一行藏着一个子页面（音量细分页）。
			# ⚠️ 它**没有值** ⇒ 不画音量条，只把入口亮出来（与 `battle_bgm` 的
			# "⏎ 选曲" 同一形状）。落到下面那条分支的话，`_setting_value_text("volume")`
			# 返回空串，右列一片空白 —— 玩家看不出这一行能按。
			_text_right(Vector2(right, ry), "Enter 展开", 16,
				Color(0.95, 0.80, 0.35) if on else Color(0.55, 0.64, 0.74))
			continue

		if key == "bgm" or key == "sfx":
			# 音量条右端给数值列让出位置：数值列右端 = 内容区右边界（全局同一条线）
			_draw_volume_bar(right - 246.0, ry, 150.0, Settings.volume(
				Settings.BUS_BGM if key == "bgm" else Settings.BUS_SFX), on)
		var val := _setting_value_text(key)
		if key == "battle_bgm" and on:
			# 这一行藏着一个子页面：聚焦时把入口亮出来（Enter / 手柄 A 进选歌页）
			val += "   ⏎ 选曲"
		if key == "battle_playlist" and on:
			# ★63-22 同上：这一行也藏着一个子页面（歌单页）。
			# 文案用「编辑」而不是「选曲」—— 选歌页是在**挑一首**，
			# 歌单页是在**编一张单**，两件事在玩家嘴里不是同一个动词。
			val += "   ⏎ 编辑"
		if key == "first_person" and on and not Settings.first_person:
			# 这一行藏着一道**警告**：聚焦时把入口亮出来（Enter / 手柄 A 弹警告框）。
			# 已经开着就不加 —— 那时候按下去什么都不会发生，亮个"⏎ 开启"是撒谎。
			val += "   ⏎ 开启"
		_text_right(Vector2(right, ry), val, 18,
			Color(0.95, 0.80, 0.35) if on else Color(0.70, 0.80, 0.92))

	_draw_scroll_indicator(SETTING_ROWS.size(), setting_row, vis, m)
	_draw_hint(
		# ⚠️ 轮 25：「第一人称视角」那一行撤了，提示里那句「开启第一人称」就成了**假话**
		# （页面上根本没有那一行可开）。改成指向新的入口 —— 玩家来设置页找它，
		# 至少能在这儿看到"它搬去 F1 了"。
		"W / S 选择        A / D 或 Q / E 调整        Enter 选曲        F1 视角切换        P 或 Esc 返回",
		"十字键 / 左摇杆 选择        左摇杆 ←→ 调整        A 选曲        长按 Back 视角切换        Start / B 返回")


## **战斗BGM 选歌页**（批 24）：竖排可滚动列表 —— 第一项「随机」，
## 其后与战斗曲池同序。Enter 当场选定（`Settings.set_battle_bgm_index`）：
## 本场出击开场就放它，放完之后剩余的歌照旧洗牌袋随机（见 AudioDirector）。
##
## ★63-22 三处变化：
##   ① **行首加 `◆`** 取代原来的「（仅自选 · 不参与随机）」后缀（用户要求去掉后缀，
##      但那条信息必须留着 —— 见 `SoundBank` 里删掉那个函数时写的说明）；
##   ② 右列多一态 **`歌单 N`**（这首已经在玩家的战斗歌单里）；
##   ③ 划到哪首就会**自动试听 15 秒**（触发点在 `_bgm_set_row()`，不在这里）。
func _draw_bgm_stage() -> void:
	_draw_title_band("战斗BGM · 选择开场曲",
		"选中的歌是本场第一首；放完之后剩余曲轮流播放 · %s = 只在自选或歌单里播放"
			% BGM_OPT_IN_MARK,
		Color(0.75, 0.88, 1.0), false)
	var keys := bgm_pick_keys()
	var m := list_panel_metrics(size, keys.size(), SETTING_ROW_H, SETTING_ROW_MAX)
	var vis := int(m["shown"])
	var win := scroll_window(keys.size(), bgm_row, vis)
	var r := list_panel_rect(size, m)
	MENU_VISUALS.panel(self, r)
	var left := r.position.x + UILayout.PAD
	var right := r.position.x + r.size.x - UILayout.PAD

	for i in range(win.x, win.x + win.y):
		var rr := list_row_rect(size, i, win.x, m)
		var ry := text_vcenter(rr, 18)
		var on := i == bgm_row
		if on:
			MENU_VISUALS.selected_line(self, rr)
		var key := str(keys[i])
		# ★63-22：`◆` 前缀（用**等宽占位**，不带的行补三个空格）——
		# 补齐宽度是为了让 54 行的标题左端仍然对齐；不补的话两种行的文字会错开。
		var mark := BGM_OPT_IN_MARK + " " if SoundBank.is_opt_in_battle_track(key) else "   "
		var label := "随机（洗牌袋轮换）" if key == "" \
			else mark + SoundBank.battle_track_label(key)
		_choice_text(Vector2(left, ry), label, 18,
			Color(0.90, 0.96, 1.0) if on else Color(0.62, 0.72, 0.84), on)
		# 右列四态：当前开场曲 / 已在歌单 / 聚焦可定 / 无事发生
		# —— 一眼分清"选过的""已经收进歌单的"和"正指着的"。
		var right_text := ""
		if Settings.battle_bgm_pick == key:
			right_text = "✓ 当前开场曲"
		elif Settings.in_playlist(key):
			right_text = "歌单 %d" % Settings.playlist_slot(key)
		elif on:
			right_text = "Enter 选定"
		_text_right(Vector2(right, ry), right_text, 16,
			Color(0.95, 0.80, 0.35) if right_text != "" else Color(0.55, 0.64, 0.74))

	_draw_scroll_indicator(keys.size(), bgm_row, vis, m)
	_draw_hint(
		"W / S / A / D 选择（划到即试听 15 秒）        Enter 选定开场曲        P 或 Esc 返回",
		"十字键 / 左摇杆 选择（划到即试听）        A 选定        Start / B 返回")


# ============================================================ ★63-22 战斗歌单页

## 歌单页的行版式。
##
## ⚠️ 页头（只读的歌单摘要）**必须参与行数计算**，不能"画上去就算"：
## 实测 1600×900 下标题带底线在 `y = TITLE_TOP + TITLE_BAND + 8 = 178`、
## `PANEL_TOP = 190` —— 中间只有 **12 px**，所以页头放在面板**外**
## 物理上不可能（这不是取舍，是没地方）。⇒ 它走 `reserve_top`：
##   · `reserve_top = PANEL_PAD_TOP + BGM_HEAD_H` ⇒ `avail` 少 `BGM_HEAD_H`
##     ⇒ 可见行数 17 → **16**（这是必须付的账，不是 bug）；
##   · 面板矩形另算（`bgm_list_panel_rect()`），比 `list_panel_rect()` 多垫一个 head。
##
## ⚠️ 只做一条会各自出症状，两条**都要**：
##   ① 只垫面板、不 reserve ⇒ 行块按 17 行排 ⇒ **最后一行掉出面板**；
##   ② 只 reserve、不垫面板 ⇒ 面板顶边不动 ⇒ **页头与第一行重叠**。
## 判据直接量这两条（`suite_bgm_playlist` 的版式节）。
static func bgm_list_metrics(view: Vector2) -> Dictionary:
	return list_metrics(view, bgm_pick_keys().size(), SETTING_ROW_H, 0.0, SETTING_ROW_MAX,
		PANEL_PAD_TOP + BGM_HEAD_H, PANEL_PAD_BOTTOM)


## 歌单页的面板外框：顶边比"第一行顶 − `PANEL_PAD_TOP`"再往上让出页头那一条。
static func bgm_list_panel_rect(view: Vector2, m: Dictionary) -> Rect2:
	return panel_rect(view,
		float(m["top"]) - PANEL_PAD_TOP - BGM_HEAD_H,
		float(m["block_h"]) + PANEL_PAD_TOP + PANEL_PAD_BOTTOM + BGM_HEAD_H)


## 页头矩形（**只读**的歌单摘要）。抽成函数是为了让"页头有没有和第一行重叠"
##、"面板有没有把页头装进去"这两件事能被直接量，而不是靠人看截图。
static func bgm_head_rect(view: Vector2, m: Dictionary) -> Rect2:
	var r := bgm_list_panel_rect(view, m)
	return Rect2(r.position.x + UILayout.PAD, r.position.y + PANEL_PAD_TOP,
		r.size.x - UILayout.PAD * 2.0, BGM_HEAD_H)


## 页头的摘要文字（`◆ 歌单：1.Plazma 2.UNICORN …`）。
##
## ⚠️ 截断按**像素宽度**走，不按首数：6 首的曲名长度差得很远
##（`Sweet Child O' Mine` 比 `Plazma` 宽三倍），按首数截在某些组合下会溢出面板。
## ⚠️ 截断时把**还剩几首**说出来 —— 否则玩家看到 3 个名字会以为歌单里只有 3 首。
func _bgm_playlist_head_text(max_w: float) -> String:
	var pl := Settings.battle_playlist
	if pl.is_empty():
		return "%s 歌单：（空 · 用默认曲池）" % BGM_OPT_IN_MARK
	var head := "%s 歌单：" % BGM_OPT_IN_MARK
	var tail := ""
	for i in pl.size():
		var piece := "%d.%s" % [i + 1, SoundBank.battle_track_label(pl[i])]
		var sep := "  " if i > 0 else ""
		if _font.get_string_size(head + tail + sep + piece,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x > max_w:
			return head + tail + "  … 还有 %d 首" % (pl.size() - i)
		tail += sep + piece
	return head + tail


## ★63-22 **战斗歌单页**：从 54 首自选列表里挑 1~6 首，作为**第二首起的轮换池**。
##
## ## 版式 = **单列**（用户拍板 Q13「复用 `Enter`」的直接后果）
## 只有一个 `Enter` 可用 ⇒ **没有按键留给"换栏"** ⇒ 原设计的
##「左候选 + 右 6 槽可聚焦」作废：候选是唯一可聚焦的列，歌单本身在**页头只读**列出。
##
## ## ⚠️ 页内一键两义（本批唯一的新风险）的五个抓手
## `Enter` = **加入 / 移出切换**，所以"我想加入"可能因为**已经加过**而变成"移出"。
## 抓手：① 行尾 `◆N`（已经排在单里，序号 N）；② 页头 `1.Plazma 2.UNICORN…` + `N/6`；
## ③ 副标题写清两义与"播放顺序随机"；④ 两个方向**播不同音效**；
## ⑤ 满员被拒也播 `ui_return`（绝不让它听着像成功）。见 `_playlist_toggle_row()`。
func _draw_bgm_list_stage() -> void:
	var n := Settings.battle_playlist.size()
	# ⚠️ 被拒的提示（`bgm_msg`）挂在**副标题**上而不是页面底部：
	# 底部那条位置已经被 `_draw_hint()` 的分隔线占掉了（面板底 830 与分隔线 842 之间
	# 只有 12 px），硬塞只会和提示行叠在一起。副标题这一行本来就空着，而且更显眼。
	var sub := "空歌单 = 用默认曲池 · Enter 加入（最多 %d 首）" % Settings.PLAYLIST_MAX if n == 0 \
		else "Enter 加入 / 再按一次移出 · 已有 %d/%d 首 · 播放顺序随机（不是加入顺序）" \
			% [n, Settings.PLAYLIST_MAX]
	if not bgm_msg.is_empty():
		sub += "      ⚠ " + bgm_msg
	_draw_title_band("战斗BGM · 我的战斗歌单", sub, Color(0.75, 0.88, 1.0), false)

	var keys := bgm_pick_keys()
	var m := bgm_list_metrics(size)
	var vis := int(m["shown"])
	var win := scroll_window(keys.size(), playlist_row, vis)
	var r := bgm_list_panel_rect(size, m)
	MENU_VISUALS.panel(self, r)
	var left := r.position.x + UILayout.PAD
	var right := r.position.x + r.size.x - UILayout.PAD

	# ---- 页头：**只读**的歌单摘要（按加入顺序）----
	var hd := bgm_head_rect(size, m)
	var hy := text_vcenter(hd, 17)
	_text(Vector2(left, hy), _bgm_playlist_head_text(hd.size.x - 90.0), 17,
		Color(1.0, 0.82, 0.42) if n > 0 else Color(0.62, 0.72, 0.84))
	_text_right(Vector2(right, hy), "%d/%d" % [n, Settings.PLAYLIST_MAX], 17,
		Color(1.0, 0.62, 0.45) if n >= Settings.PLAYLIST_MAX else Color(0.55, 0.64, 0.74))
	draw_line(Vector2(left, hd.end.y), Vector2(right, hd.end.y),
		Color(MENU_VISUALS.EDGE, 0.55), UILayout.LINE_HAIR)

	for i in range(win.x, win.x + win.y):
		var rr := list_row_rect(size, i, win.x, m)
		var ry := text_vcenter(rr, 18)
		var on := i == playlist_row
		if on:
			MENU_VISUALS.selected_line(self, rr)
		var key := str(keys[i])
		# ⚠️ 这一页**不加**"仅自选"那个 `◆` 前缀：`◆` 在这一页已经被"在单里 + 序号"
		# 用掉了，两种含义共用一个符号会让人分不清"已加入"和"仅自选"。
		# 仅自选的信息由行尾那个**没有序号**的暗 `◆` 表达（见下）。
		var label := "随机（洗牌袋轮换）" if key == "" else SoundBank.battle_track_label(key)
		_choice_text(Vector2(left, ry), label, 18,
			Color(0.90, 0.96, 1.0) if on else Color(0.62, 0.72, 0.84), on)
		var slot := Settings.playlist_slot(key)
		var right_text := ""
		if slot > 0:
			right_text = "%s %d" % [BGM_OPT_IN_MARK, slot]
		elif SoundBank.is_opt_in_battle_track(key):
			right_text = BGM_OPT_IN_MARK
		elif on:
			right_text = "Enter 加入"
		_text_right(Vector2(right, ry), right_text, 16,
			Color(0.95, 0.80, 0.35) if slot > 0 else (
				Color(0.68, 0.74, 0.60) if right_text != "" else Color(0.55, 0.64, 0.74)))

	# ⚠️ `count_label = false`：行块右上方是**页头**，计数会与它叠在一起（见那边注释）。
	_draw_scroll_indicator(keys.size(), playlist_row, vis, m, false)
	_draw_hint(
		"W / S / A / D 选择（划到即试听 15 秒）        Enter 加入 / 再按一次移出        P 或 Esc 返回",
		"十字键 / 左摇杆 选择（划到即试听）        A 加入或移出        Start / B 返回")


## ★63-22：**试听与菜单 BGM 压低的唯一进入/离开判定点**。
##
## 实现侧的关键是**别去追每一条离开路径**（出击 / 回设置页 / 回主菜单 / Esc /
## 手柄 B / P 键 / 关卡启动…）—— 只在每帧判一句"我现在还在不在这两个页面上"。
## 一处声明，全局成立；少一条路径的症状是"试听在战斗里还在响"，而且很难复现。
##
## ⚠️ 判据是 `visible and stage == Stage.BGM`：两个子屏共用 `Stage.BGM`，
## 所以它天然覆盖两页；`visible == false`（菜单被关掉）也算离开。
## ⚠️ 只在**变化的那一帧**做事（`_bgm_page_on`）：不然每帧都会 kill/create Tween。
func _tick_bgm_page() -> void:
	var on := visible and stage == Stage.BGM
	if on == _bgm_page_on:
		return
	_bgm_page_on = on
	if on:
		Audio.set_menu_duck(Audio.MENU_DUCK_DB)
	else:
		Audio.set_menu_duck(0.0)
		Audio.stop_preview()


## **第一人称的眩晕警告**（轮 20）—— 画成一块居中的面板。
##
## 需求原文：「再加一个开关提醒：开启本模式会导致强烈的 3d 眩晕，是否还要开启？」
##
## 四件事必须一眼可见，缺一条这道门就只是装饰：
##   ① **风险本身**（"强烈的 3D 眩晕"）—— 最大最醒目的一行，警示色；
##   ② **不是没有退路** —— 下面几行小字写明这个模式到底改变什么，
##      玩家才知道自己将要面对的是什么（只说"会晕"是恐吓，不是告知）；
##   ③ **默认停在「否」** —— 光标停在下标 0，高亮跟着走；
##   ④ **文字与设置同源** —— 警示语取 `Settings.FPV_WARNING`，不在这里另写一份。
##      "弹窗说的"和"测试断言的 / 说明里写的"不是同一句，是这类警告最典型的失效方式。
func _draw_fpv_confirm_stage() -> void:
	_draw_title_band("第一人称视角", "开启前请先读一遍风险提示", WARN, false)

	# ★63-19：这一页的版式原来是**内联**的（全工程唯一一处没走版式助手的行）
	# ⇒ 鼠标点不到。现在提成 `_fpv_layout()`，绘制与命中共用同一份。
	# （`h` 那条"面板按内容实算"的注释也一起搬过去了。）
	var fl := _fpv_layout()
	var w := float(fl["w"])
	var x := float(fl["x"])
	var top := float(fl["top"])
	var notes: Array = fl["notes"]
	var row_rects: Array = fl["rects"]
	var row_h := 50.0
	var row_gap := 10.0
	var pr := Rect2(x, top, w, float(fl["h"]))
	draw_rect(pr, Color(0.05, 0.09, 0.13, 0.97), true)
	draw_rect(pr, Color(1.0, 0.62, 0.30), false, UILayout.LINE_STRUCT)

	var y := top + 46.0
	_text(Vector2(x + 38.0, y), Settings.FPV_WARNING, 26, WARN)
	y += 34.0 + 14.0
	for s: String in notes:
		_text(Vector2(x + 38.0, y), s, 17, Color(0.72, 0.82, 0.92))
		y += 23.0
	y += 20.0

	for i in FPV_CONFIRM_ROWS.size():
		var rr := row_rects[i] as Rect2
		var on := i == fpv_confirm_row
		MENU_VISUALS.row(self, rr, WARN, on)
		var ry := text_vcenter(rr, 19)
		_choice_text(Vector2(rr.position.x + 20.0, ry), str(FPV_CONFIRM_ROWS[i]), 19,
			Color(0.92, 1.0, 0.94) if on else Color(0.62, 0.72, 0.84), on)
		# 右列把两档的**后果**各写一句：「是」有多重、「否」维持什么现状。
		if i == FPV_CONFIRM_YES:
			_text_right(Vector2(rr.position.x + rr.size.x - 20.0, ry),
				"座舱视角 · 本项目里最晕的一档", 15,
				Color(1.0, 0.62, 0.45) if on else Color(0.55, 0.64, 0.74))
		else:
			_text_right(Vector2(rr.position.x + rr.size.x - 20.0, ry),
				"默认 · 保持现在的追尾镜头", 15,
				Color(0.55, 1.0, 0.74) if on else Color(0.55, 0.64, 0.74))
		y += row_h + row_gap

	_draw_hint(
		"W / S 选择        Enter 确认        Esc / P 取消（默认停在「否」）",
		"十字键 / 左摇杆 选择        A 确认        B / Start 取消")


## 音量条。0% 与 100% 都画出来，让"到底调到头没有"一眼可见。
## 左右两侧各画一个箭头表示"这个值可以调" —— 不要画在条子上，会糊成一团。
func _draw_volume_bar(x: float, y: float, w: float, v: float, on: bool) -> void:
	var bar := Rect2(x, y - 8.0, w, 10.0)
	draw_rect(bar, Color(0.0, 0.0, 0.0, 0.5), true)
	var col := Color(0.55, 1.0, 0.74) if on else Color(0.45, 0.66, 0.84)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(v, 0.0, 1.0), bar.size.y)), col, true)
	draw_rect(bar, Color(col.r, col.g, col.b, 0.4), false, UILayout.LINE_STRUCT)
	# 每 10% 一道刻度，方便估读
	for i in range(1, 10):
		var lx := bar.position.x + bar.size.x * float(i) / 10.0
		draw_line(Vector2(lx, bar.position.y), Vector2(lx, bar.position.y + bar.size.y),
			Color(0, 0, 0, 0.45), UILayout.LINE_HAIR)
	var ac := Color(0.55, 1.0, 0.74) if on else Color(0.42, 0.52, 0.62)
	_text_right(Vector2(x - 12.0, y), "◀", 14, ac)
	_text(Vector2(x + w + 12.0, y), "▶", 14, ac)


func _draw_suit_stage() -> void:
	# 标题带**只放 LOGO，没有下面那行小字** —— 用户要求删掉
	# "夜 战 模 式 · 1v1 空中缠斗"（那行字在 LOGO 下面反而显得挤）。
	_draw_title_band("机动战士高达 闪光的哈萨维", "", Color(0.75, 0.88, 1.0), true)

	var lst := active_suit_list()
	# ⚠️ 用**局部**的 `sel` 而不是直接改 `suit_index`：`_draw_*` 不该写状态。
	#
	# 名单比窗口长时（马夫蒂 4 台、1280/1600 下只排得下 3 张）必须靠 `suit_window()`
	# 把选中项**滚进视野** —— 否则玩家按 A/D 选到第 4 台时，
	# 屏幕上四张卡里**一张高亮的都没有**（`idx == sel` 对窗口内任何一张都不成立），
	# 看起来就是"按了没反应、然后自己跳到别的地方"。
	#
	# `clampi` 兜的是"切阵营后名单变短"那条已有的坑（`Stage.SIDE` 里已归零，
	# 这里再兜一次）：绘制路径不该依赖输入路径的礼貌。
	# ★63-19：`sel` / 窗口 / 卡片矩形统一由 `_list_geometry()` 给（同上一条理由）。
	var g := _list_geometry()
	var sel := int(g["sel"])
	var win := Vector2i(int(g["first"]), int(g["shown"]))
	var rects: Array = g["rects"]
	for i in win.y:
		var idx := win.x + i
		_draw_suit_card(rects[i] as Rect2, _menu_profile(lst[idx]), idx == sel)
	_draw_suit_scroll(lst.size(), sel, win)

	_draw_hint(
		"A / D 切换        Enter / 空格 确认        Esc 返回",
		"左摇杆 / 十字键 选择        A 确认        B 返回")


## 机体页的**横向**滚动指示：卡片行下方一条横轨 + 滑块 + `◀ 2/4 ▶`。
##
## 与竖排列表的 `_draw_scroll_indicator()` 是同一套语义（**放得下就什么都不画** ——
## 那是最要紧的一条：3 台机的页面因此与加窗口之前**逐像素相同**），
## 只是轨道的位置不同：竖排画在列表**右侧**，横排画在卡片行**下方**（横排的"边"在下）。
##
## ⚠️ 位置**从版式算出来**（`cards_top() + card_h()`），不是写死的 y：
## 卡片高度由内容区高度自适应（`card_h()` 在 356..440 浮动），写死 y 会在 720 高窗口里
## 把轨道压到卡片上、在 1080 高里浮在半空。
## 装不下时**宁可不画** —— 少一个提示只是"少了提示"，压住卡片/提示行是"看起来坏了"。
func _draw_suit_scroll(count: int, index: int, win: Vector2i) -> void:
	if count <= win.y or count <= 0:
		return
	var x0 := UILayout.content_left(size)
	var x1 := UILayout.content_right(size)
	var y := cards_top(size) + card_h(size) + 16.0
	if y >= content_bottom(size) - 6.0:
		return
	var track_w := x1 - x0
	draw_rect(Rect2(x0, y, track_w, 3.0), Color(1.0, 1.0, 1.0, 0.10), true)
	var thumb_w := maxf(track_w * float(win.y) / float(count), 30.0)
	var span := maxi(count - win.y, 1)
	var thumb_x := x0 + (track_w - thumb_w) * float(win.x) / float(span)
	draw_rect(Rect2(thumb_x, y - 1.0, thumb_w, 5.0), Color(0.62, 0.86, 1.0, 0.85), true)
	# 计数标签只画"还有内容"的那一侧箭头（两边都画等于没说）—— 与竖排同款文案。
	_text_right(Vector2(x1, y - 8.0),
		"%s %d/%d %s" % ["◀" if win.x > 0 else " ", index + 1, count,
			"▶" if win.x + win.y < count else " "], 13, Color(0.62, 0.86, 1.0))


## 机体卡片：1.1 起是**三栏并列**（柯西 / 佩涅罗佩 / 阿利宙斯），所以内部改成单栏纵排。
##
## 为什么不做成"两栏卡片 + 横向滚动"：三台机是**并列比较**的关系
## （谁更快、谁更硬、谁能变形），横着藏的第三张卡等于让玩家看不到它。
## 代价是每张卡只有约 460 px 宽，内容必须压缩 —— 于是：
##   - 背景文案压到 11 px / 4 行，衍生形态压到 2 行（还放不下就不画，`_wrap` 会截断）；
##   - 数值条仍是四行，但行距从 30 收到 22；
##   - 底部的"装备 + 特色"合成一行。
## 固定偏移而不是顺排：三张卡的背景长短差很多，顺排会让数值条错位、对比起来很难看
## （这条是最早那一版就踩过的坑）。
func _draw_suit_card(r: Rect2, p: SuitProfile, focused: bool) -> void:
	var edge := p.accent if focused else Color(0.25, 0.35, 0.45)
	MENU_VISUALS.row(self, r, edge, focused)
	if focused:
		var glow := 3.0
		draw_rect(r.grow(glow), Color(edge.r, edge.g, edge.b, 0.22), false, UILayout.LINE_STRUCT)
	draw_rect(Rect2(r.position + Vector2(16, 0), Vector2(r.size.x - 32, 2)), Color(edge, 0.6), true)

	var left := r.position.x + UILayout.PAD
	var right := r.position.x + r.size.x - UILayout.PAD
	var inner := right - left
	var y := r.position.y
	var dim := Color(0.66, 0.76, 0.88)

	_choice_text(Vector2(left, y + 34.0), p.display_name, 23, edge, focused)
	_text(Vector2(left, y + 50.0), p.model_name, 10, Color(0.62, 0.72, 0.85))
	draw_line(Vector2(left, y + 60.0), Vector2(right, y + 60.0),
		Color(edge.r, edge.g, edge.b, 0.25), UILayout.LINE_HAIR)

	# ---- 形态（多形态机体才有：这一行是阿利宙斯与其他两台最大的区别）----
	var sy := 60.0
	if p.form_count > 1:
		_text(Vector2(left, y + sy + 18.0), "▌ " + " / ".join(p.form_names), 11,
			Color(0.92, 0.78, 0.45))
		draw_line(Vector2(left, y + sy + 28.0), Vector2(right, y + sy + 28.0),
			Color(0.20, 0.28, 0.38), UILayout.LINE_HAIR)
		sy += 28.0

	# ---- 数值条（右端 = 卡片内右边界 = 全局数值列）----
	# ⚠️ `off` 是**相对卡片顶的偏移**，行 y 必须写成 `y + off`。
	# 第一版把它写成 `y + sy`，而 sy 里已经含了 y —— 四行数值条被推到卡片外面，
	# 卡片中段空出一大片、背景文案整段看不见（截图上一眼就是"版式坏了"）。
	#
	# ⚠️ 批 29：卡高会随内容区变化，所以**卡内的偏移也要跟着伸缩** ——
	# 否则卡片加高之后只是"下半截多出一块空白"。增量按 `grow`（相对最小卡高）
	# 分配：数值条行距 + 段落呼吸（文案区自己算行数，见下）。
	var grow := maxf(r.size.y - CARD_H_MIN, 0.0)
	var stat_step := 22.0 + grow * 0.10
	var sec_gap := grow * 0.15
	var off := sy + 28.0
	_stat_row(left, y + off, inner, "机体耐久", p.hull_hp / SuitProfile.hull_bar_ref(),
		"%d" % int(p.hull_hp), edge)
	_stat_row(left, y + off + stat_step, inner, "I 立场",
		p.ifield_hp / SuitProfile.ifield_bar_ref(), "%d" % int(p.ifield_hp), edge)
	_stat_row(left, y + off + stat_step * 2.0, inner, "举盾减伤", p.shield_reduction,
		"%d%%" % int(p.shield_reduction * 100.0), edge)
	# 归一化的分母从 0.4 放宽到 0.6：两台机现在都是 1.30，
	# 用 0.4 会让两条都顶到 100% 满格，看不出"转向统一了"这件事。
	_stat_row(left, y + off + stat_step * 3.0, inner, "机动性",
		clampf((p.turn_scale - 0.8) / 0.6, 0.0, 1.0), "%.2f" % p.turn_scale, edge)

	# ---- 装备与速度（数值列右端仍是全局那条线）----
	var eq_off := off + stat_step * 3.0 + 28.0 + sec_gap
	draw_line(Vector2(left, y + eq_off - 12.0), Vector2(right, y + eq_off - 12.0),
		Color(0.20, 0.28, 0.38), UILayout.LINE_HAIR)
	# ⚠️ 屏上这个"巡航 N m/s"是**显示域**的数：实际速度已经 ×SPEED_REAL_MULT（1.5），
	# 这里除回去，于是玩家看到的数字与 2026-09-25 之前完全一样。
	_text(Vector2(left, y + eq_off),
		"巡航 %d m/s" % int(round(SuitProfile.speed_to_display(p.player_top_speed()))), 12,
		Color(0.72, 0.82, 0.92))
	_text_right(Vector2(right, y + eq_off), "%s ×%d · 弹匣 %d · 导弹 ×%d"
		% ["肩炮" if p.id == SuitProfile.Id.NEUE_ZIEL else ("主炮" if p.cannon_only else "步枪"), 4 if p.id == SuitProfile.Id.NEUE_ZIEL else p.rifle_count, p.rifle_magazine, p.funnel_count], 11, Color(0.72, 0.82, 0.92))
	# ⚠️ 2026-09-30：这里原画 `p.blurb`（"特色：……"，`can_discard_rifle` 时染橙）——
	# 用户点名删掉菜单里的机体特色描述。
	# ⚠️ **背景文案（下面的 `lore` / `sub_lore`）保留** —— 用户原话"介绍机体的背景的
	# 还挺好的"，那一段不在这次要删的名单里。
	# ⚠️ `· 速度 ×%.2f` 是搭在这行上的**相对倍率**；绝对速度在上一行"巡航 N m/s"里
	#（`player_top_speed()` 已经含 `speed_scale`）⇒ 删这行不丢数值。

	# ---- 背景文案（左栏原来的主要内容，现在压在卡片下半部分）----
	#
	# ⚠️ 批 29：卡高会随内容区放大（`CARD_H_MIN`..`CARD_H_MAX`），多出来的空间
	# **归文案区** —— 所以这里按"还排得下几行"算，而不是写死 4 行。
	# 写死的话卡片加高之后下半截就是一块空白，那不叫"更饱满"，叫"卡里空了一块"。
	# 特色行撤了 ⇒ 分隔线跟着上移，不留 30 px 空带。（上一道分隔线是提前 12 px，
	# 所以这里同样把"文字底到线"留 10 px。）
	var lore_off := eq_off + 20.0 + sec_gap
	draw_line(Vector2(left, y + lore_off - 10.0), Vector2(right, y + lore_off - 10.0),
		Color(0.20, 0.28, 0.38), UILayout.LINE_HAIR)
	# 完整换行，按可见行窗口滚动；背景与操作说明均不截断。
	var room := maxf(r.size.y - lore_off - 10.0, 26.0)
	var rows: Array[String] = _wrap(p.lore, inner - 12.0, 11, 10000).duplicate()
	var lore_count := rows.size()
	if p.sub_lore != "":
		rows.append("▌ " + p.sub_title)
		rows.append_array(_wrap(p.sub_lore, inner - 12.0, 11, 10000))
	var cap := maxi(int((room - 19.0) / 13.0), 1)
	var maximum := maxi(rows.size() - cap, 0)
	var first := clampi(int(_lore_scroll.get(p.id, 0)), 0, maximum)
	_lore_scroll[p.id] = first
	var region := Rect2(left, y + lore_off - 5.0, inner, room)
	_lore_regions.append({"rect":region, "id":p.id, "max":maximum})
	var ly := y + lore_off + 6.0
	for index in range(first, mini(first + cap, rows.size())):
		var col := dim if index < lore_count else Color(0.66, 0.72, 0.80)
		if index == lore_count: col = Color(0.92, 0.78, 0.45)
		_text(Vector2(left, ly), rows[index], 11, col)
		ly += 13.0
	if maximum > 0:
		var track := Rect2(right - 4.0, region.position.y + 4.0, 3.0, cap * 13.0)
		draw_rect(track, Color(1, 1, 1, 0.12))
		var thumb_h := maxf(track.size.y * float(cap) / float(rows.size()), 12.0)
		var thumb_y := track.position.y + (track.size.y - thumb_h) * float(first) / float(maximum)
		draw_rect(Rect2(track.position.x, thumb_y, 3.0, thumb_h), Color(edge, 0.8))
		_text(Vector2(left, y + r.size.y - 8.0), "滚轮查看介绍  %d/%d" % [first + 1, maximum + 1], 10, Color(0.62, 0.76, 0.86))



## 背景文案（`lore`）保底行数：矮窗口 / 矮卡片时至少画这么多。
const LORE_LINES := 4
## 背景文案的上限行数（卡加高时最多画到这儿；再长也只是把同一段话摊得更开）。
const LORE_LINES_MAX := 12
const SUB_LORE_LINES := 2


## 一条数值：左侧名称、中间条、**右侧数值右对齐到 `x + w`**。
## 右端对齐这件事必须自己量宽度（`_text_right`），不能靠 `draw_string` 的对齐参数 ——
## 见 `FlightHUD._text_right` 的注释：宽度传 −1 时 Godot 会忽略对齐。
func _stat_row(x: float, y: float, w: float, label: String, ratio: float, value: String, col: Color) -> void:
	_text(Vector2(x, y), label, 12, Color(0.60, 0.70, 0.82))
	var bar := Rect2(x + 76.0, y - 9.0, maxf(w - 76.0 - 46.0, 40.0), 8.0)
	draw_rect(bar, Color(0.0, 0.0, 0.0, 0.5), true)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(ratio, 0.0, 1.0), bar.size.y)),
		Color(col.r, col.g, col.b, 0.85), true)
	draw_rect(bar, Color(col.r, col.g, col.b, 0.35), false, UILayout.LINE_STRUCT)
	_text_right(Vector2(x + w, y), value, 12, col)


# ============================================================ 模式页

## 模式页：**对战模式 / 剧情挑战 / 训练模式 / 局域网联机**，一行一个。
##
## 这是流程的第一步 —— 训练模式不是"难度"或"地图"的一个取值，
## 它换的是**这一局的目标**（打靶 vs 击坠），所以必须是流程的第一步。
##
## ⚠️ 这一页的行数是 `MODE_GROUPS.size()`（**4**），**一处都没写死**：
## 「王牌战 / 小队战」收进子页时它从 4 行变过 3 行，剧情挑战恢复入口又回到 4 行 ——
## 两次都没有手调过任何常数（`list_metrics()` 自己按行数自适应行高）。
## ⚠️ 标题带下那行小字**由 `modes_breadcrumb()` 从表里现推**：
## 它以前是写死的，于是恢复入口之后"图上还是三项"，而**不报错**。
# ==================================================== ★63-24 无限强化演习 · 开局配置页

## 配置页的一行高（**勾选清单**：比模式行矮、比设置行高，一屏能看十来条）。
const ENDLESS_ROW_H := 58.0
const ENDLESS_ROW_GAP := 6.0
const ENDLESS_ROW_MAX := 84.0


## 芯片五类型的配色。
##
## 抽成静态函数（而不是在绘制里内联一个 `match`）只有一个理由：**可测** ——
## 判据能直接查"5 类各有各的颜色"，而不是去截图里找色块。
## 与 `mode_color()` / `_level_color()` 同一套做法。
##
## ⚠️ 真源已搬到 `CardStyle.type_color()` —— **局内三选一面板**（`FlightHUD`）要画
## 同一批芯片，颜色就有了第二个消费方。本函数**保留原签名**（判据直接查它）但只是转调，
## 免得变成"菜单一套色、局内另一套色"而两边都不报错。
static func card_color(ty: int) -> Color:
	return CardStyle.type_color(ty)


## 演习的开局配置页：**从基础卡池里自选 3 张**（设计 §5.6 / R14）。
##
## ⚠️ 卡池来自 `UpgradeCard.basic_pool()`（数据层），**不是**这里写死的一份名单 ——
## 写死就变成两份真源：加一条词条菜单里看不到，而且**不报错**。
func _draw_endless_stage() -> void:
	var p := _menu_profile(selected_suit())
	_draw_title_band(ENDLESS_TITLE + " · 出击配置",
		"已选机体：%s        基础卡池自选 %d 张（已勾选 %d / %d）"
			% [p.display_name, ENDLESS_PICK_COUNT, endless_picks.size(), ENDLESS_PICK_COUNT],
		p.accent, false)

	# 行几何走 `_list_geometry()`（**唯一真源**）—— 绘制与鼠标命中共用同一份。
	# ⚠️ 漏了那条分支的后果是 `Geo.NONE`：**鼠标完全点不到这一页**（设计 §11.1 第 10 条）。
	var g := _list_geometry()
	var m: Dictionary = g["m"]
	var shown := int(g["shown"])
	var first := int(g["first"])
	var pool := endless_pool_now()
	for i in range(first, first + shown):
		var rect := row_rect(size, g, i)
		if i < pool.size():
			_draw_endless_row(rect, pool[i], i == endless_index)
		else:
			# 最后那一行是「出击」行动行（见 `endless_row_count()`）。
			_draw_endless_action_row(rect, i == endless_index)
	_draw_scroll_indicator(endless_row_count(), endless_index, shown, m)

	# 页脚：**还差几张**要一直印着 —— 出击闸门不该靠玩家自己数。
	var need := endless_missing()
	if need > 0:
		_draw_hint(
			"W / S 选择        Enter 勾选        还差 %d 张才能出击        Esc 返回" % need,
			"十字键 / 左摇杆 选择        A 勾选        还差 %d 张才能出击        B 返回" % need)
	else:
		_draw_hint(
			"W / S 选择        Enter 勾选 / 出击        Esc 返回",
			"十字键 / 左摇杆 选择        A 勾选 / 出击        B 返回")


## 配置页的一行芯片。
##
## 左边那个方块是**勾选框** —— 刻意**不画字形的对勾**：本工程用 CJK 字库，
## `✓` / `√` / `☑` 这几个字形能不能画出来要看字库里有没有，
## 而"打不出来"在 Godot 里是**画成豆腐块或不画**，不报错。画方块是零风险的写法。
func _draw_endless_row(r: Rect2, card: UpgradeCard, focused: bool) -> void:
	var on := endless_picks.has(card.id)
	var col := card_color(card.type)
	# `primary = on`：已勾选的那几行右边多一个箭头标记（`MENU_VISUALS.row` 自带）。
	MENU_VISUALS.row(self, r, col, focused, on)
	var left := r.position.x + UILayout.PAD + 26.0
	var box := Rect2(left, row_center(r, -9.0), 18.0, 18.0)
	if on:
		draw_rect(box, col, true)
	else:
		draw_rect(box, Color(0.42, 0.50, 0.58), false, UILayout.LINE_HAIR)
	var tx := left + 30.0
	_choice_text(Vector2(tx, text_vcenter(r, 20)), card.name, 20,
		col if (focused or on) else Color(0.55, 0.64, 0.74), focused)
	_text(Vector2(tx + 190.0, baseline_block(r, 1, 0.0, 13)), card.line, 13,
		Color(0.68, 0.78, 0.90))
	_text(Vector2(r.end.x - UILayout.PAD - 66.0, text_vcenter(r, 12)),
		card.type_name(), 12, col)


## 配置页最后那一行：「出击」。
##
## ⚠️ **勾满 3 张之前它是灰的、按了也不走**（设计 §5.6 的出击闸门）。
## 表现上刻意"有响应但明说原因"（灰 + 黄字"还差 N 张"），而不是静默吃掉那一下按键。
func _draw_endless_action_row(r: Rect2, focused: bool) -> void:
	var ready := endless_ready()
	var col := Color(0.62, 0.94, 0.72) if ready else WARN
	MENU_VISUALS.row(self, r, col, focused)
	var left := r.position.x + UILayout.PAD + 26.0
	_choice_text(Vector2(left, text_vcenter(r, 22)), "出击", 22,
		col if ready else Color(0.70, 0.66, 0.52), focused)
	var note: String = ("已勾满 %d 张 · 进场即生效" % ENDLESS_PICK_COUNT) if ready \
		else ("还差 %d 张（从基础卡池里自选，三张互不重复）" % endless_missing())
	_text(Vector2(left + 120.0, text_vcenter(r, 14)), note, 14,
		Color(0.68, 0.80, 0.90) if ready else WARN)


func _draw_mode_stage() -> void:
	_draw_title_band("选择模式", modes_breadcrumb(),
		Color(0.75, 0.88, 1.0), false)
	# ⚠️ 画的是**窗口**而不是全部（`rows_that_fit()` 的说明）：模式多起来
	# 就是从这里压到底部面板的。行高由 `list_metrics()` 按内容区自适应 ——
	# 行数少时每行更高（撑满内容区），再长只是先压回最小行高再滚动。
	# ★63-19：行几何改读 `_list_geometry()`（唯一真源），绘制与命中共用同一份。
	var g := _list_geometry()
	var m: Dictionary = g["m"]
	var vis := int(g["shown"])
	var win := Vector2i(int(g["first"]), vis)
	for i in range(win.x, win.x + win.y):
		_draw_group_row(row_rect(size, g, i), i, i == mode_index)
	_draw_scroll_indicator(MODE_GROUPS.size(), mode_index, vis, m)
	if _quit_armed > 0.0:
		# 手柄上 B 就是 menu_back —— "按一下 B 直接退游戏"太危险，所以退游戏要两次确认
		_text(Vector2(UILayout.content_left(size), hint_y(size)),
			InputSetup.hint("再按一次 Esc 退出游戏（%.0f）" % _quit_armed,
				"再按一次 B 退出游戏（%.0f）" % _quit_armed), 15, WARN)
	else:
		_draw_hint(
			"W / S 选择        Enter 确认        Esc 退出游戏",
			"十字键 / 左摇杆 选择        A 确认        B 退出游戏")


## 「对战模式」子页：**王牌战 / 小队战**两行。
##
## 版式与模式页**逐像素相同**（同一个 `_draw_mode_row()`），
## 因为它们是同一种东西 —— 只是"选模式"这个决策被拆成了两屏罢了。
func _draw_battle_stage() -> void:
	_draw_title_band("对战模式", "王牌战 = 1v1 单挑 · 小队战 = 阵营编队（3 编队 × 2 台 + 1 台 ACE）",
		Color(0.75, 0.88, 1.0), false)
	var modes := battle_modes()
	# ★63-19：同上，行几何走 `_list_geometry()`。
	var g := _list_geometry()
	var m: Dictionary = g["m"]
	var vis := int(g["shown"])
	var win := Vector2i(int(g["first"]), vis)
	for i in range(win.x, win.x + win.y):
		_draw_mode_row(row_rect(size, g, i), int(modes[i]), i == battle_index)
	_draw_scroll_indicator(modes.size(), battle_index, vis, m)
	_draw_hint(
		"W / S 选择        Enter 确认        Esc 返回",
		"十字键 / 左摇杆 选择        A 确认        B 返回")


## 顶层模式页的一行：**一个分组**（对战模式 / 剧情挑战 / 训练模式 / 局域网联机）。
##
## 单项分组（剧情挑战 / 训练 / 联机）直接把它那唯一一个模式的文案拿来用（`group_info()`），
## 所以这三行的口径永远只有一份。
func _draw_group_row(r: Rect2, gi: int, focused: bool) -> void:
	var info := group_info(gi)
	_draw_list_row(r, str(info["name"]), info["lines"], mode_color(int(info["mode"])), focused)
	_text(Vector2(r.position.x + 30.0, text_vcenter(r, 12)), "%02d" % (gi + 1), 12, MENU_VISUALS.FOCUS if focused else MENU_VISUALS.MUTED)


## 一行模式。文案的取舍：**左边一句话说清"这一局干什么"，右边写"几个人、在哪打"**。
func _draw_mode_row(r: Rect2, mode: int, focused: bool) -> void:
	var info := mode_info(mode)
	_draw_list_row(r, str(info["name"]), info["lines"], mode_color(mode), focused)
	_text(Vector2(r.position.x + 30.0, text_vcenter(r, 12)), "%02d" % (battle_modes().find(mode) + 1), 12, MENU_VISUALS.FOCUS if focused else MENU_VISUALS.MUTED)


## 卡式行的**版式本体**（模式行 / 分组行共用）。
##
## 抽出来是为了让"分组行"和"模式行"长得**逐像素一样**：它们是同一张列表里的
## 相邻行，谁的字号或行距差一档，一眼就看得出没排过版。改版式只改这一处。
@warning_ignore("unused_parameter")
func _draw_list_row(r: Rect2, name: String, lines: Array, col: Color, focused: bool) -> void:
	MENU_VISUALS.row(self, r, col, focused, true)
	var left := r.position.x + 88.0
	var y := text_vcenter(r, 30)
	_choice_text(Vector2(left, y), name, 30, MENU_VISUALS.MUTED, focused)


static func mode_color(mode: int) -> Color:
	match mode:
		Game.MatchMode.CHALLENGE:
			return Color(1.0, 0.78, 0.32)
		Game.MatchMode.TRAINING:
			return Color(1.0, 0.62, 0.30)
		Game.MatchMode.LAN:
			return Color(0.62, 0.92, 1.0)
		# ★63-24：演习用一个**与上面四种都不同**的色（品红偏紫）——
		# 它是模式页新增的那一行，颜色撞了会让"我加的这一项怎么没显出来"看不出来。
		Game.MatchMode.ENDLESS:
			return Color(0.92, 0.62, 0.98)
	return Color(0.52, 0.86, 1.0)


## 模式的文案与两个右列标签。抽成静态函数是为了让测试能直接查
## "四种模式都写清楚了没有"，而不是去截图里找字。
static func mode_info(mode: int) -> Dictionary:
	match mode:
		# ⚠️ **2026-09-21 修过的坑**：老板报"主菜单有两个对战模式"。
		# 根因不是多画了一行，而是 `SQUAD` **没有自己的分支**，
		# 落到了函数末尾的默认分支 —— 于是"小队战"和 1v1 顶着
		# **一模一样的名字与描述**（都叫"对战模式 / 与另一台机体 1v1"）并排显示。
		# 教训：`match` 的默认分支是给"真的没有特例"兜底的，
		# **枚举多了一个取值就必须在这里多一个分支**，否则 UI 会静默显示成错的。
		Game.MatchMode.SQUAD:
			return {
				"name": "小队战",
				"lines": ["按阵营编队出战 · 3 编队 × 2 台 + 1 台 ACE",
					"选阵营 → 选机体 → 选难度 → 选地图（敌人由阵营决定）"],
				"tag": "编队战",
				"tag2": "ACE 对抗",
			}
		Game.MatchMode.CHALLENGE:
			# ★ 轮 C：这一行**必须跟入口一起改**。
			# 它原来写的是**旧挑战**的形态（「按剧情遭遇固定的对手与地图」）——
			# 入口换成"选完模式直接进战役图"之后，那一句就成了
			# **图上说着一件事、按下去是另一件事**。
			# 这与 §22.9 那条写死的面包屑是同一个形状（改一处、另一处不动，且不报错）。
			# ⚠️ `lines` 是**直接画到屏幕上**的字（不像注释），所以这里**不能**写 `**` 标记。
			return {
				"name": "剧情挑战",
				"lines": ["按战役图逐关推进（有解锁顺序 · 三章 12 关）",
					"选完模式直接进战役图 —— 选关与难度都在那一页"],
				"tag": "三章战役",
				"tag2": "简报 / 出击 / 结算",
			}
		Game.MatchMode.TRAINING:
			return {
				"name": "训练模式",
				"lines": ["靶场打靶 · 靶机不还手", "选机体即可出击（固定落在废墟靶场）"],
				"tag": "靶机 4 架",
				"tag2": "只有你在开火",
			}
		Game.MatchMode.LAN:
			return {
				"name": "局域网联机",
				"lines": ["同一局域网两个人对打（一台做主机）", "主机 / 加入 + IP 与端口"],
				"tag": "2 人 PvP",
				"tag2": "UDP 直连",
			}
		Game.MatchMode.ENDLESS:
			# ★63-24：**必须有这一分支**。漏了会**静默落到下面那个 `VERSUS` 兜底**
			# ⇒ 模式页上这一行顶着"王牌战 / 与另一台机体 1v1 单挑"的名字与说明，
			# 而按下去是演习。这正是 2026-09-21 那次"两个对战模式"的同款事故
			#（`match` 的默认分支是给"真的没有特例"兜底的，枚举多一个取值就得补一个分支）。
			#
			# ⚠️ `lines` 是**直接画到屏幕上**的字（不像注释）⇒ 这里**不能**写 `**` 标记。
			return {
				"name": ENDLESS_TITLE,
				"lines": ["波次无限 · 每清一波自选一张改装芯片强化自己",
					"被击坠即终止 —— 看你能撑到第几波"],
				"tag": "单机 · 无限波次",
				"tag2": "局内即焚",
			}
	# 默认分支 = `VERSUS`（王牌战）。1v1 单挑：自己挑机体 / 敌机 / 难度 / 地图。
	# 名字从"对战模式"改成"王牌战"是老板点名的：一个"对战"位置下只有两种形式，
	# 王牌战（1v1）与小队战（阵营编队），不能再出现两行都叫"对战"。
	return {
		"name": "王牌战",
		"lines": ["与另一台机体 1v1 单挑", "选机体 → 选敌人 → 选难度 → 选地图"],
		"tag": "1v1 击坠",
		"tag2": "对手会还手",
	}


# ============================================================ 敌人页（对战）

## 1.2：对战模式可以**自己挑敌人**（用户要求）。
## 三台机都能选 —— 包括"跟自己一样"的镜像战（柯西打柯西）。
func _draw_enemy_stage() -> void:
	var me := _menu_profile(selected_suit())
	_draw_title_band("选择敌人", "自机：%s" % me.display_name, me.accent, false)
	# ⚠️ 敌机页的行高不能沿用 96：当初 `ENEMY_SUITS` 是五台，五行会排到 740
	#（比模式页还惨）。行高换成 `ENEMY_ROW_H`（64+4）。现在只有三台，余量还在。
	# 窗口仍按版式算 —— 别把行高改回去。
	# ★63-9 B4：列的是 `enemy_pool()` —— 对战三台，编队战是**敌方阵营的 ACE 池**。
	var pool := enemy_pool()
	var cur := enemy_index_now()
	var g := _list_geometry()
	var m: Dictionary = g["m"]
	var vis := int(g["shown"])
	var win := Vector2i(int(g["first"]), vis)
	for i in range(win.x, win.x + win.y):
		_draw_enemy_row(row_rect(size, g, i),
			_menu_profile(pool[i]), i == cur, pool[i] == selected_suit())
	_draw_scroll_indicator(pool.size(), cur, vis, m)
	_draw_hint(
		"W / S 选择        Enter 确认        Esc 返回",
		"左摇杆 / 十字键 选择        A 确认        B 返回")


func _draw_enemy_row(r: Rect2, p: SuitProfile, focused: bool, mirror: bool) -> void:
	var col := p.accent
	MENU_VISUALS.row(self, r, col, focused)

	var left := r.position.x + UILayout.PAD
	var right := r.position.x + r.size.x - UILayout.PAD
	# 三列各自垂直居中（行高 64..92 自适应，基线不能写死）：
	# 左列 = 机名 26 + 型名 12，中列 = 镜像战提示（只有选到同型敌机时才画），右列 = 耐久 15 + 巡航 14。
	var y := baseline_block(r, 2, 22.0, 26)
	_choice_text(Vector2(left, y), p.display_name, 26, col, focused)
	_text(Vector2(left, y + 22.0), p.model_name, 12, Color(0.62, 0.72, 0.85))
	# ⚠️ 2026-09-30：中列原来画 `p.blurb`（"特色：……"）—— 用户点名删掉菜单里的机体特色。
	# 只留下面这条**功能性提示**（它说的不是特色，是"这一局敌机和你同型"）。
	# ⚠️ `SuitProfile.blurb` 数据保留：不画 ≠ 删数据。
	if mirror:
		_text(Vector2(left + 320.0, text_vcenter(r, 13)), "镜像战：和自机同型", 13,
			Color(0.95, 0.80, 0.35))
	var ry := baseline_block(r, 2, 24.0, 15)
	_text_right(Vector2(right, ry), "耐久 %d · I 立场 %d" % [int(p.hull_hp), int(p.ifield_hp)],
		15, col)
	_text_right(Vector2(right, ry + 24.0), "巡航 %d m/s · 速度 ×%.2f"
		% [int(round(SuitProfile.speed_to_display(p.player_top_speed()))), p.speed_scale],
		14, Color(0.80, 0.88, 0.98))


# ============================================================ 遭遇页（挑战）

## 1.2 剧情挑战：每台机体的遭遇是固定的一组（柯西两场，另外两台各一场）。
## 这一页把"打谁 / 在哪打 / 有几波"一次说清 —— 挑战的乐趣在于还原剧情，
## 所以简报要写得像任务书，而不是一串数值。
func _draw_encounter_stage() -> void:
	var me := _menu_profile(selected_suit())
	_draw_title_band("选择遭遇", "剧情挑战 · 自机：%s" % me.display_name, me.accent, false)
	var list := encounters()
	if list.is_empty():
		_text(Vector2(UILayout.content_left(size), PANEL_TOP + 40.0),
			"本机没有挑战剧本", 20, WARN)
		return
	var g := _list_geometry()
	for i in list.size():
		_draw_encounter_row(row_rect(size, g, i), list[i], i == encounter_index)
	_draw_hint(
		"W / S 选择        Enter 出击        Esc 返回",
		"十字键 / 左摇杆 选择        A 出击        B 返回")


func _draw_encounter_row(r: Rect2, e: ChallengeScript.Encounter, focused: bool) -> void:
	var col := MapDef.by_id(e.map_id).accent
	MENU_VISUALS.row(self, r, col, focused)

	var left := r.position.x + UILayout.PAD
	var right := r.position.x + r.size.x - UILayout.PAD
	var y := text_vcenter(r, 24)
	_choice_text(Vector2(left, y), e.title, 24, col, focused)
	_text(Vector2(left, y + 21.0), "%s · %s" % [e.map_name(), e.brief], 13, Color(0.66, 0.78, 0.90))
	_text(Vector2(left + 430.0, y), e.story, 13, Color(0.70, 0.80, 0.92))
	# 右列：波次结构（"先清杂兵再打 BOSS"这件事必须在出击前就看得见）
	var lines: Array[String] = []
	for i in e.waves.size():
		var w: ChallengeScript.Wave = e.waves[i]
		lines.append("第 %d 波：%s ×%d" % [i + 1, w.suit_name(), w.count])
	var ry := baseline_block(r, lines.size() + 1, 22.0, 15)
	_text_right(Vector2(right, ry), "敌机 %d 波 / 共 %d 架"
		% [ChallengeScript.wave_count(e), ChallengeScript.total_enemies(e)], 15, col)
	for i in lines.size():
		_text_right(Vector2(right, ry + 22.0 + float(i) * 18.0), lines[i], 13,
			Color(0.80, 0.88, 0.98))

# ============================================================ 地图页

func _draw_map_stage() -> void:
	_draw_title_band("选择地图", "选择本次出击区域", Color(0.75, 0.88, 1.0), false)
	var maps := active_map_list()
	# Draw only the shared visible window; short viewports scroll the remaining maps.
	# ★63-19：行几何改读 `_list_geometry()`（唯一真源），绘制与命中共用同一份。
	var g := _list_geometry()
	var first := int(g["first"])
	var shown := int(g["shown"])
	for i in range(first, first + shown):
		_draw_map_row(row_rect(size, g, i), MapDef.by_id(maps[i]), i == map_index)
	_draw_scroll_indicator(maps.size(), map_index, shown, g["m"])
	_draw_hint(
		"W / S 选择        Enter 出击        Esc 返回",
		"十字键 / 左摇杆 选择        A 出击        B 返回")


func _draw_map_row(r: Rect2, m: MapDef, focused: bool) -> void:
	var col := m.accent
	MENU_VISUALS.row(self, r, col, focused)

	var left := r.position.x + UILayout.PAD
	var right := r.position.x + r.size.x - UILayout.PAD
	var y := text_vcenter(r, 26)
	# 地表色板：一块 46×46 的方块代表这张图的地表主色（比写"红土"直观）。
	# 跟着行心走（行高 96..124 自适应）。
	var sw := Rect2(left, row_center(r, -23.0), 46.0, 46.0)
	draw_rect(sw, m.ground_swatch, true)
	draw_rect(sw, Color(col.r, col.g, col.b, 0.55), false, UILayout.LINE_STRUCT)
	_choice_text(Vector2(left + 62.0, y), m.name_cn, 26, col, focused)
	# ⚠️ 2026-09-30：这里原画 `m.blurb`（"原作战场 · 一望无际的夜海 / 贴海低飞与穿云缠斗"）。
	# 用户点名删掉地图描述 ⇒ 左列只留色板 + 图名，右列仍是"夜战 / 代号"。
	# ⚠️ `MapDef.*.blurb` 数据保留：`suite_space_map`（断言含"再入"）与
	# `suite_round14`（断言不含"岛"）都在读它 —— 清数据会当场踩红。
	var ry := baseline_block(r, 2, 24.0, 16)
	_text_right(Vector2(right, ry), "夜战", 16, col)
	_text_right(Vector2(right, ry + 24.0), m.code, 14, Color(0.80, 0.88, 0.98))


## **训练项目页**（1.2 第二十五轮）。
##
## 用户要求：「加入新手教学模式，**和靶场在同一页面**，新手教学模式有
## **每个机体的特色详解**」。
##
## 所以这一页**同时**做两件事：
##   ① 上面两行是训练项目（**自由打靶** / **新手教学**）—— "同一页面"就落在这里；
##   ② 下面整块是**当前所选机体的特色详解**（`SuitProfile.features()`），
##      选教学之前就能读完。
##
## ⚠️ 左边那一列是**竖排**的（照 `map_row_rect()`），所以这一页的导航轴
## 必须是 `Nav.Y`（见 `nav_axis()` 里那两条同源事故的注释）。
func _draw_training_stage() -> void:
	var p := _menu_profile(selected_suit())
	_draw_title_band("训练 · 选择项目", "已选机体：%s" % p.display_name, p.accent, false)

	# ⚠️ 这一页分两段：上面两行（训练项目）+ 下面整块（机体特色详解）。
	# 所以两行**靠内容区顶**排、不参与"整块居中" —— 居中会让详解只剩半屏，
	# 而详解正是这一页的主角。行高仍走 `list_metrics()`（自适应）。
	# ★63-19：`m["top"] = PANEL_TOP` 这条覆盖**搬进了 `_list_geometry()`** ——
	# 覆盖值留在绘制侧就变成第二份版式，命中测试会跟着错（点第 1 行选中别处）。
	var g := _list_geometry()
	var m: Dictionary = g["m"]
	var feat_top := list_bottom_y(0, int(m["shown"]), m) + 34.0
	for i in TRAINING_ITEMS.size():
		var rect := row_rect(size, g, i)
		var focused := (i == training_item)
		MENU_VISUALS.row(self, rect, WARN, focused)
		var x := UILayout.content_left(size)
		_choice_text(Vector2(x, text_vcenter(rect, 22)), str(TRAINING_ITEMS[i]), 22,
			WARN if focused else Color(0.42, 0.52, 0.62), focused)
		var sub := ""
		if i == 0:
			sub = "在废墟靶场自由打靶 · 四架靶机不还手 · 练手感与提前量"
		else:
			sub = "分步引导 + 这台机的特色详解 · 靶机同样不还手"
		_text(Vector2(x + 180.0, baseline_block(rect, 1, 0.0, 14)), sub, 14,
			Color(0.66, 0.78, 0.90))

	# ---- 机体特色详解 ----
	#
	# ⚠️ 放在**选教学之前**：玩家要先知道"这台机有什么"，才谈得上"要不要学它"。
	# 所以它不是教学里才显示的一页，而是训练项目页的一部分。
	_draw_suit_features(p, feat_top)
	# 页脚提示行（批 29 起每页都锚在同一条底线上）。这一页是竖排两行，
	# 所以提示写 W / S —— 与 `nav_axis(Stage.TRAINING)` 一致。
	_draw_hint(
		"W / S 选择项目        Enter 确认        Esc 返回",
		"十字键 / 左摇杆 选择        A 确认        B 返回")


## 画一台机体的**特色详解**（从 `y` 往下，一行一条）。
##
## ⚠️ 条数是**数据驱动**的（`SuitProfile.features()`），不是写死的五条：
## 每台机的特征数量本来就不一样（有导弹的 / 没导弹的、ACE / 量产）。
## 行高按剩余空间自适应，条数多了也不会溢出到操作面板上。
func _draw_suit_features(p: SuitProfile, y0: float) -> void:
	var feats := p.features()
	if feats.is_empty():
		return
	var x := UILayout.content_left(size)
	var bottom := content_bottom(size) - 6.0
	var avail := maxf(bottom - y0, 40.0)
	var row_h := clampf(avail / float(feats.size()), 26.0, 52.0)
	_text(Vector2(x, y0), "【%s 特色详解】" % p.display_name, 15, p.accent)
	var y := y0 + 22.0
	for f: Dictionary in feats:
		if y + row_h > bottom:
			break
		_text(Vector2(x, y), "· " + str(f["title"]), 14, WARN)
		# 正文用暗一档：一条里有"标题亮 + 正文暗"才扫得动。
		_text(Vector2(x + 300.0, y), str(f["body"]), 13, Color(0.62, 0.72, 0.84))
		y += row_h


func _draw_difficulty_stage() -> void:
	var p := _menu_profile(selected_suit())
	# 挑战下这一页的标题要写清"难度影响什么、不影响什么"。
	# ⚠️ 此刻**只能写今天为真的话**：难度只改敌机的速度与伤害倍率，
	# 挑战的波次结构、出场高度与"阿利宙斯从上方入场"都是剧情脚本写死的，与难度无关。
	# 等锁定改造的方案 §4.3（阿利宙斯猎杀残血柯西的锁定覆盖）落地之后，
	# 这里还要补一句"猎杀锁定不受难度影响"——现在写上去就是骗玩家。
	var sub := "已选机体：%s" % p.display_name
	if challenge_mode():
		var enc := selected_encounter()
		sub = "剧情挑战 · %s —— 难度只改敌机的速度与伤害" % (enc.title if enc != null else "—")
	_draw_title_band("选择难度", sub, p.accent, false)

	var g := _list_geometry()
	var m: Dictionary = g["m"]
	for i in Difficulty.all_levels(Game.super_hard_unlocked).size():
		_draw_difficulty_row(row_rect(size, g, i),
			Difficulty.make(Difficulty.all_levels(Game.super_hard_unlocked)[i]), i == diff_index)

	if challenge_mode():
		# 挑战的"难度不改变什么"在这里再说一次（这也是玩家最容易误解的一处）
		# 现状（"难度只改敌机速度与伤害"）再补上 1.2 的猎杀规则 ——
		# 方案 §4.3 落地之后，这句话必须写出来：否则玩家会以为"选简单能躲过 BOSS 阶段"，
		# 那是最伤信任的一类误导。
		var ty := list_bottom_y(0, int(m["shown"]), m) + 26.0
		_text(Vector2(UILayout.content_left(size), ty),
			"剧情固定：波次结构、出场高度、敌机编成均与难度无关", 14, WARN)
		_text(Vector2(UILayout.content_left(size), ty + 20.0),
			"⚠ 阿利宙斯的「猎杀锁定」（柯西 40% 血以下）不受难度影响：三个难度都是 0.255 秒",
			14, Color(1.0, 0.42, 0.36))

	_draw_hint(
		"W / S 选择        Enter 出击        Esc 返回",
		"十字键 / 左摇杆 选择        A 出击        B 返回")


## 难度行：名字与丢枪规则在左，**速度 / 伤害右对齐到内容区右边界**
## （和战斗 HUD 的弹药栏、结算菜单的"损耗与战果"落在同一条竖线上）。
##
## 数字只出现在右侧那一列：`blurb` 里不再重复速度/伤害 ——
## 早先左右两边印同一组数，看起来像排版出错（见 `Difficulty.summary()` 的注释）。
func _draw_difficulty_row(r: Rect2, d: Difficulty, focused: bool) -> void:
	var col := _level_color(d.level)
	MENU_VISUALS.row(self, r, col, focused)

	var left := r.position.x + UILayout.PAD
	var right := r.position.x + r.size.x - UILayout.PAD
	# 左列：难度名 26（单行居中）；右列：速度 / 伤害两行居中。
	var y := text_vcenter(r, 26)
	_choice_text(Vector2(left, y), d.name_cn, 26, col, focused)
	# ⚠️ 2026-09-30：这里原画 `d.blurb`（"半血丢枪一次 · 仅解除锁定 / 不给自己无敌期"）。
	# 用户点名删掉每个模式的特色描述 ⇒ 丢枪规则只留在 `Difficulty` 数据里
	#（`difficulty.gd`，不画 ≠ 删数据）。
	# 原有难度保持两行；超级困难另列王牌强化，避免数值看起来与困难相同。
	var enhanced:=d.level==Difficulty.Level.SUPER_HARD
	var ry := baseline_block(r, 3 if enhanced else 2, 24.0, 16)
	_text_right(Vector2(right, ry), "速度 ×%.1f" % d.speed_mult, 16, col)
	if enhanced:
		_text_right(Vector2(right, ry+24), "王牌机血量 +%d%%" % roundi((d.ace_hull_mult-1)*100),16,col)
		_text_right(Vector2(right, ry+48), "伤害 ×%.1f · 王牌额外 +%d%%" % [d.damage_mult,roundi((d.ace_damage_mult-1)*100)],16,Color(.80,.88,.98))
	else:
		_text_right(Vector2(right, ry + 24.0), "伤害 ×%.1f" % d.damage_mult, 16,
			Color(0.80, 0.88, 0.98))


# ============================================================ 操作说明

## 底部常驻的操作说明。数据来自 InputSetup.HELP_SECTIONS —— 和游戏内键位提示同源。
##
## 面板外框与结算菜单两栏**严格重合**（都取自 `UILayout`），抽成纯函数是为了能被
## `suite_layout.gd` 直接断言 —— "三屏对齐"不该靠人对着截图看。
## （批 24：原 `help_panel_rect` / `_draw_help_panel` 已随面板一起删除 ——
##  键位说明的完整版仍在游戏内帮助与重绑页。）


# ============================================================ 文本工具

const OUTLINE := Color(0.0, 0.02, 0.04, 0.9)


## 按像素宽度折行。中文没有空格，不能按词断，只能逐字量宽度。
## 不折的话长句子会直接冲出卡片边缘被裁掉 —— 第一版就是这么翻车的。
##
## ⚠️ **实现已搬到 `UILayout.wrap()`**（2026-09-30，加通讯字幕时）。
## 原先这里是唯一一份，HUD 的字幕要么抄一份、要么共用 —— 抄一份的症状是
## "同一段文字在主菜单和字幕里断行位置不同"，而这种错没有判据会红。
## 这个薄壳留着是为了：① 调用点（`main_menu` 里十几处）一行不改；
## ② `Array[String]` 的返回类型在这儿钉死。
# Menu-only immutable snapshots; gameplay continues to receive independent profiles.
var _menu_profiles: Dictionary = {}
var _menu_wraps: Dictionary = {}
func _menu_profile(id: int) -> SuitProfile:
	if not _menu_profiles.has(id):
		_menu_profiles[id] = SuitProfile.by_id(id)
	return _menu_profiles[id]

func _wrap(text: String, max_w: float, fs: int, max_lines: int) -> Array[String]:
	var key := [text, max_w, fs, max_lines, _font.get_instance_id() if _font != null else 0]
	if not _menu_wraps.has(key):
		# Bound memory when viewport width changes repeatedly.
		if _menu_wraps.size() >= 256: _menu_wraps.clear()
		_menu_wraps[key] = UILayout.wrap(_font, text, max_w, fs, max_lines)
	return _menu_wraps[key]


func _presentation_choice() -> String:
	var index := _focus_index()
	match stage:
		# ★63-23：设置页也是子屏（主屏 / 音量细分）⇒ 焦点各是一个变量。
		Stage.SETTINGS: index = volume_row if settings_sub == SET_SUB_VOLUME else setting_row
		Stage.KEYS: index = keys_row
		# ★63-22：两个子屏的焦点各是一个变量 ⇒ 走 `_bgm_focus_row()`（唯一真源）。
		# 写死 `bgm_row` 的话，在歌单页里换行不会触发"选择变化"（文字倾斜动画不重来）。
		Stage.BGM: index = _bgm_focus_row()
		Stage.LAN: index = _focus_index()
	# 第三段：联机页是子屏，BGM 页**也是**子屏（★63-22），设置页同样是（★63-23）——
	# 切子屏同样算"选择变了"，否则从音量细分退回主屏时，
	# 画面上那句"刚选中"的高亮不会重置。
	var sub := 0
	if stage == Stage.LAN:
		sub = lan_sub
	elif stage == Stage.BGM:
		sub = bgm_sub
	elif stage == Stage.SETTINGS:
		sub = settings_sub
	return "%d:%d:%d" % [stage, index, sub]


func _choice_text(pos: Vector2, label: String, fs: int, col: Color, focused: bool, weight := -1) -> void:
	if focused and is_instance_valid(_tilt_label):
		var extent := Vector2(_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, _font.get_height(fs))
		var scale := MENU_VISUALS.focus_scale(_choice_age, true, Settings.reduce_motion)
		_tilt_label.text = label
		if _tilt_label.get_theme_font_size("font_size") != fs:
			_tilt_label.add_theme_font_size_override("font_size", fs)
		_tilt_label.size = extent
		_tilt_label.scale = Vector2.ONE * scale
		_tilt_label.position = pos - Vector2(0, _font.get_ascent(fs)) - extent * (scale - 1.0) * 0.5
		_tilt_material.set_shader_parameter("pivot", extent * 0.5)
		_tilt_material.set_shader_parameter("tilt", _text_tilt)
		_tilt_material.set_shader_parameter("camera_distance", maxf(320.0, extent.x * 2.0))
		_tilt_label.show()
		return
	draw_string(_font, pos + Vector2(0, 2), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0,0.005,0.012,0.30))
	_text(pos, label, fs, col, weight)


func _text(pos: Vector2, s: String, fs: int, col: Color, weight := -1) -> void:
	draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		UILayout.outline_for(weight), OUTLINE)
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _text_center(pos: Vector2, s: String, fs: int, col: Color, weight := -1) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := pos - Vector2(w * 0.5, 0)
	draw_string_outline(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		UILayout.outline_for(weight), OUTLINE)
	draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## 右对齐：`pos` 是文本**右端**的位置。设置页的数值列要用。
func _text_right(pos: Vector2, s: String, fs: int, col: Color, weight := -1) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := pos - Vector2(w, 0)
	draw_string_outline(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		UILayout.outline_for(weight), OUTLINE)
	draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _level_color(level: int) -> Color:
	match level:
		Difficulty.Level.EASY:
			return Color(0.45, 0.92, 0.62)
		Difficulty.Level.HARD:
			return Color(1.0, 0.42, 0.36)
		Difficulty.Level.SUPER_HARD:
			return Color(1.0, 0.28, 0.16)
	return Color(1.0, 0.78, 0.30)


# ============================================================ 鼠标操控菜单（★63-19）
#
# 需求：「做一个鼠标能操控主菜单子菜单的系统」（右键 = 返回、滚轮 = 移动焦点、悬停播 ui_select）。
#
# ## 一条不许破的红线
#
# ⚠️⚠️ **禁止为命中测试再写一份行矩形。**
# 一旦命中矩形与绘制矩形是两份写法，就会出现「看着点在这一行、实际选了另一行」，
# 而且**不报错、不红、只有人眼能看出来** —— 与本工程反复出问题的形状（
# `modes_breadcrumb()` 曾经写死、敌人页轴与版式相反）是同一类。
# ⇒ 所以 `_list_geometry()` 是**行几何的唯一真源**，**绘制与命中都读它**。
#    判据见 `tests/suite_menu_mouse.gd`：10 个 `_draw_*_stage()` 里不许再有裸的
#    `list_metrics(` / `suit_window(` / `suit_card_rects(`。
#
# ## 为什么走 `_input()` 而不改 `mouse_filter`
#
# `Node._input()` **不受 `mouse_filter` 影响**（它只影响 `_gui_input()`）⇒ 现在就能收到鼠标事件；
# 而全工程的全屏 Control 一律 `MOUSE_FILTER_IGNORE`（`hud.gd` / `pause_menu.gd` /
# `loading_screen.gd` …）—— **保持这个惯例**，不去动事件流。
#
# ## 鼠标与键盘怎么保证不分家
#
# 鼠标**不另写一套 `match stage`**：它只产生一个「意图」，折成与键盘相同的三个量
# （`_mi_back` / `_mi_ok` / `_mi_d`），由 `_read_input()` **在同一处**消费。
# 否则必然出现「键盘能走、鼠标走到某一页断掉」—— 而且**只有走到那一页才发现**。

## 本页「行几何」的种类。
enum Geo { NONE, LIST, CARDS, FIXED }

## 鼠标意图（**点击类**）：每帧最多一条。
## ⚠️ 滚轮**不在这里** —— 它是相对量，一帧里可能滚好几格，见 `_mouse_wheel`。
enum Intent { NONE, CONFIRM, BACK }

var _mouse_intent := Intent.NONE
## 设下这条意图的那一帧（`_process()` 末尾按它作废过期的意图）。
var _mouse_intent_frame := -1
## 滚轮累积量（−1 = 上一行，+1 = 下一行）。**不去重**：一帧滚三格就该走三行，
## 去重会让快速滚动变成"一格一格挪"、手感发黏。
var _mouse_wheel := 0
## 本帧已经为「鼠标悬停」播过 `ui_select` 了吗 —— **一帧最多响一次**：
## 快速划过一列时，同一帧里会连着跨过好几行，不限流就会连响好几声。
var _hover_sfx_frame := -1
## 滚轮后**屏蔽悬停**的截止时刻（`_time` 刻度）。见 `const WHEEL_HOVER_MUTE`。
## ⚠️ `_handle_mouse()` 在 `_input()` 里读 `_time`，拿到的是**上一帧**的值 ——
## 误差 ≤ 1 帧（16 ms），对 0.15 s 的窗没有影响。
var _hover_mute_until := 0.0
## `_read_input()` 把鼠标意图折成的三个量（键盘路径**同一段代码**也读它们）。
var _mi_back := false
var _mi_ok := false
var _mi_d := 0


## 竖排列表：`list_metrics()` + `scroll_window()`。
##
## `top_override` < 0 = 不覆盖（保持 `list_metrics()` 的「整块居中」）。
## ⚠️ 训练页的 `m["top"] = PANEL_TOP` **必须在这里给** —— 留在绘制侧就变成第二份版式，
## 命中测试会跟着错（点在第 1 行却选中别处）。
func _geo_list(count: int, row_h: float, gap: float, max_h: float, sel: int,
		top_override := -1.0) -> Dictionary:
	var m := list_metrics(size, count, row_h, gap, max_h)
	if stage == Stage.MODE or stage == Stage.BATTLE:
		m = compact_mode_metrics(size, m)
	if top_override >= 0.0:
		m["top"] = top_override
	var win := scroll_window(count, sel, int(m["shown"]))
	return {"kind": Geo.LIST, "count": count, "first": win.x, "shown": win.y, "m": m, "rects": []}


## 横排卡片（只有机体页）：`suit_window()` + `suit_card_rects()`。
##
## ⚠️ `rects` 是**按屏幕槽位**排的（下标 0..shown−1），名单下标是 `first + 槽位` ——
## `row_rect()` / `row_at_point()` 负责这次换算，别在调用方各写一遍。
func _geo_cards() -> Dictionary:
	var lst := active_suit_list()
	# ⚠️ 与 `_draw_suit_stage()` **同一条** `clampi`：绘制路径不该依赖输入路径的礼貌。
	var sel := clampi(suit_index, 0, maxi(lst.size() - 1, 0))
	var win := suit_window(lst.size(), sel, size)
	return {"kind": Geo.CARDS, "count": lst.size(), "first": win.x, "shown": win.y,
		"m": {}, "rects": suit_card_rects(size, win.y), "sel": sel}


## 内联固定行（眩晕警告框）：矩形由调用方给出。
func _geo_fixed(rects: Array, sel: int) -> Dictionary:
	return {"kind": Geo.FIXED, "count": rects.size(), "first": 0, "shown": rects.size(),
		"m": {}, "rects": rects, "sel": sel}


## **本页行几何的唯一真源** —— 绘制与命中都只许读它。
func _list_geometry() -> Dictionary:
	match stage:
		Stage.MODE:
			return _geo_list(MODE_GROUPS.size(), MODE_ROW_H, MODE_ROW_GAP, MODE_ROW_MAX,
				mode_index)
		Stage.BATTLE:
			return _geo_list(battle_modes().size(), MODE_ROW_H, MODE_ROW_GAP, MODE_ROW_MAX,
				battle_index)
		Stage.SIDE:
			return _geo_list(side_choices().size(), ROW_H, ROW_GAP, ROW_MAX_FEW, side_index)
		Stage.SUIT:
			return _geo_cards()
		Stage.TRAINING:
			# ⚠️ `PANEL_TOP` 这条覆盖（这一页上两行靠内容区顶排、不参与整块居中）
			# 必须由这里给：留在绘制侧就是第二份版式，命中会跟着错。
			return _geo_list(TRAINING_ITEMS.size(), ROW_H, ROW_GAP, ROW_MAX, training_item,
				PANEL_TOP)
		Stage.ENEMY:
			return _geo_list(enemy_pool().size(), ENEMY_ROW_H, ENEMY_ROW_GAP, ENEMY_ROW_MAX,
				enemy_index_now())
		Stage.DIFFICULTY:
			return _geo_list(Difficulty.all_levels(Game.super_hard_unlocked).size(), ROW_H, ROW_GAP, ROW_MAX, diff_index)
		Stage.MAP:
			return _geo_list(active_map_list().size(), ROW_H, ROW_GAP, ROW_MAX_FEW, map_index)
		Stage.ENCOUNTER:
			return _geo_list(encounters().size(), ROW_H, ROW_GAP, ROW_MAX, encounter_index)
		Stage.ENDLESS:
			# ★63-24：卡池 + **最后一行的「出击」行动行**（见 `endless_row_count()`）。
			# ⚠️⚠️ 分支必须在这里，不是在绘制侧自己算 rect —— 落在末尾的
			# `Geo.NONE` 上时**鼠标完全点不到这一页**，而键盘照样能用
			#（表现是"手柄/键盘都好好的，鼠标怎么点都没反应"，设计 §11.1 第 10 条点名的坑）。
			return _geo_list(endless_row_count(), ENDLESS_ROW_H, ENDLESS_ROW_GAP,
				ENDLESS_ROW_MAX, endless_index)
		Stage.LAN:
			if _lan_wait: return _geo_list(LOBBY_ROWS.size(),LAN_ROW_H,LAN_ROW_GAP,LAN_ROW_MAX,lan_lobby_row)
			if lan_sub == LAN_SUB_ADV: return _geo_list(LAN_ADV_ROWS.size(),LAN_ROW_H,LAN_ROW_GAP,LAN_ROW_MAX,lan_adv_row)
			if lan_sub == LAN_SUB_ROOMS: return _geo_list(lan_rooms.size(),LAN_ROW_H,LAN_ROW_GAP,LAN_ROW_MAX,lan_room_sel)
			return _geo_list(LAN_ROWS.size(),LAN_ROW_H,LAN_ROW_GAP,LAN_ROW_MAX,lan_row)
		Stage.FPV_CONFIRM:
			return _geo_fixed(_fpv_layout()["rects"], fpv_confirm_row)
	# SETTINGS / KEYS / BGM / PASSWORD：阶段 1 不做鼠标（`Geo.NONE` ⇒ 点不到）。
	return {"kind": Geo.NONE, "count": 0, "first": 0, "shown": 0, "m": {}, "rects": []}


## 第 `i` 行（**列表下标**）的矩形。
##
## ⚠️ `i` 不是「屏幕第几行」—— 窗口滚动时，屏幕第 0 行是列表下标 `first`。
## 用 `mode_row_rect()` / `map_row_rect()` 那一族（它们的 `first` 恒为 0）来点选，
## 一滚动就整体错位 ⇒ **本函数是它们的位置的唯一正确替代**。
static func row_rect(view: Vector2, g: Dictionary, i: int) -> Rect2:
	match int(g.get("kind", Geo.NONE)):
		Geo.LIST:
			return list_row_rect(view, i, int(g["first"]), g["m"])
		Geo.CARDS:
			var cr: Array = g["rects"]
			var cs := i - int(g["first"])
			return cr[cs] if cs >= 0 and cs < cr.size() else Rect2()
		Geo.FIXED:
			var fr: Array = g["rects"]
			return fr[i] if i >= 0 and i < fr.size() else Rect2()
	return Rect2()


## 点命中哪一行 —— 返回**列表下标**；点在面板外返回 `−1`。
##
## 抽成 static 纯函数**只有一个理由：可测**（同 `nav_delta_y()`）：
## 它不读 `Input`、不读节点状态 ⇒ 无头环境里可以直接喂坐标断言。
##
## 三条边界（都写死并测）：
##   ① 返回的是**列表下标**，不是屏幕序号 ⇒ 滚动时 `row_at_point(屏幕第 0 行) == first`；
##   ② 行与行之间的**缝算命中上面那一行** —— 缝里返回 −1 会让玩家觉得
##      「点在两行中间没反应」，手感像坏了；
##   ③ **面板外一律 −1** —— 不许「鼠标移到屏幕边缘就选中最后一行」。
static func row_at_point(view: Vector2, g: Dictionary, p: Vector2) -> int:
	if int(g.get("count", 0)) <= 0:
		return -1
	var kind := int(g.get("kind", Geo.NONE))
	if kind == Geo.LIST:
		var shown := int(g["shown"])
		if shown <= 0:
			return -1
		var m: Dictionary = g["m"]
		var row_h := float(m["row_h"])
		var gap := maxf(float(m["gap"]), 0.0)
		var top := float(m["top"])
		# 行的横向范围与 `list_row_rect()` **同一式子**（`MARGIN` 起、`frame_width()` 宽）。
		var bounds := list_row_rect(view, int(g["first"]), int(g["first"]), m)
		if p.x < bounds.position.x or p.x > bounds.end.x:
			return -1
		if p.y < top or p.y > list_bottom_y(0, shown, m):
			return -1
		var step := maxf(row_h + gap, 0.001)
		var slot := clampi(int(floor((p.y - top) / step)), 0, shown - 1)
		return int(g["first"]) + slot
	if kind == Geo.CARDS or kind == Geo.FIXED:
		var rects: Array = g["rects"]
		var base := int(g["first"]) if kind == Geo.CARDS else 0
		for i in rects.size():
			if (rects[i] as Rect2).has_point(p):
				return base + i
	return -1


## 眩晕警告框的**版式**（面板 + 两个选项行）—— 绘制与命中共用。
##
## ⚠️ 它原来是**内联在 `_draw_fpv_confirm_stage()` 里**的（全工程唯一一处没走版式助手的行）
## ⇒ 鼠标点不到。这里提出来当唯一真源，两边的 y 算式**逐字一致**。
func _fpv_layout() -> Dictionary:
	var left := UILayout.content_left(size)
	var right := UILayout.content_right(size)
	var w := minf(right - left, 900.0)
	var x := (size.x - w) * 0.5
	var notes := _wrap("视角会移到机体头部、贴着机头前缘；地平线跟着机体滚转，"
		+ "地面与建筑群会以最大角速度从视野下方掠过。", w - 76.0, 17, 3)
	var row_h := 50.0
	var row_gap := 10.0
	# 面板高度按内容**实算**（警告 + 说明 + 两个选项 + 内边距），不写死 ——
	# 以后改字号或加减说明行都不会溢出到面板外面。
	var h := 56.0 + 34.0 + 14.0 + float(notes.size()) * 23.0 + 20.0 \
		+ float(FPV_CONFIRM_ROWS.size()) * (row_h + row_gap) + 34.0
	var top := maxf(140.0, (size.y - h) * 0.5)
	var y := top + 46.0 + 34.0 + 14.0 + float(notes.size()) * 23.0 + 20.0
	var rows: Array = []
	for i in FPV_CONFIRM_ROWS.size():
		rows.append(Rect2(x + 38.0, y, w - 76.0, row_h))
		y += row_h + row_gap
	return {"x": x, "w": w, "h": h, "top": top, "notes": notes, "rects": rows}


## 本页当前焦点（列表下标）。**与键盘共用同一个变量** ⇒ 键盘一按就接管。
func _focus_index() -> int:
	match stage:
		Stage.MODE:
			return mode_index
		Stage.BATTLE:
			return battle_index
		Stage.SIDE:
			return side_index
		Stage.SUIT:
			return clampi(suit_index, 0, maxi(active_suit_list().size() - 1, 0))
		Stage.TRAINING:
			return training_item
		Stage.ENEMY:
			return enemy_index_now()
		Stage.DIFFICULTY:
			return diff_index
		Stage.MAP:
			return map_index
		Stage.ENCOUNTER:
			return encounter_index
		Stage.ENDLESS:
			# ★63-24：焦点行 = `endless_index`（含最后那一行「出击」行动行）。
			# ⚠️ 钳到 `endless_row_count() - 1`：鼠标悬停会喂来一个"行下标"，
			# 卡池缩了（换机体）之后它可能越界 ⇒ 不钳的话焦点会停到不存在的行上，
			# 表现为"高亮没了、按键没反应"。
			return clampi(endless_index, 0, maxi(endless_row_count() - 1, 0))
		Stage.LAN:
			return lan_lobby_row if _lan_wait else (lan_room_sel if lan_sub == LAN_SUB_ROOMS else (lan_adv_row if lan_sub == LAN_SUB_ADV else lan_row))
		Stage.FPV_CONFIRM:
			return fpv_confirm_row
	return -1


## 把焦点移到 `i`（**只移焦点，不推进**）。
##
## ⚠️ 每个分支都必须照抄 `_read_input()` 同页分支里"换焦点"的**全部副作用**：
##   · 阵营页换阵营 ⇒ 池子换了 ⇒ `suit_index` 归零；
##   · 机体页换机体 ⇒ 遭遇表要重算 ⇒ `encounter_index` 归零。
## 漏一条，鼠标划一圈就会把状态弄成键盘走不出来的样子。
func _set_focus(i: int) -> void:
	match stage:
		Stage.MODE:
			mode_index = i
		Stage.BATTLE:
			battle_index = i
		Stage.SIDE:
			side_index = i
			suit_index = 0
		Stage.SUIT:
			suit_index = i
			encounter_index = 0
			# ★63-24：与 `_read_input()` 的机体页分支**逐条对齐** —— 换机体 ⇒ 演习的
			# 卡池也换 ⇒ 剔掉装不上的勾选。漏了这一条，鼠标划过机体页就会留下
			# 一批"这台机装不上"的勾选，而键盘走同样的路却不会。
			endless_prune_picks()
		Stage.TRAINING:
			training_item = i
		Stage.ENEMY:
			enemy_index = i
		Stage.DIFFICULTY:
			diff_index = i
		Stage.MAP:
			map_index = i
		Stage.ENCOUNTER:
			encounter_index = i
		Stage.ENDLESS:
			# ★63-24：只移焦点。这一页"换行"**没有任何副作用**（池子不随焦点变），
			# 所以这里就一行 —— 与上面那些"照抄副作用"的分支不同，别硬加。
			endless_index = clampi(i, 0, maxi(endless_row_count() - 1, 0))
		Stage.LAN:
			if _lan_wait: lan_lobby_row = clampi(i,0,LOBBY_ROWS.size()-1)
			elif lan_sub == LAN_SUB_ROOMS: lan_room_sel = clampi(i,0,maxi(0,lan_rooms.size()-1))
			elif lan_sub == LAN_SUB_ADV: lan_adv_row = clampi(i,0,LAN_ADV_ROWS.size()-1)
			else: lan_row = clampi(i,0,LAN_ROWS.size()-1)
		Stage.FPV_CONFIRM:
			fpv_confirm_row = clampi(i, 0, 1)


## 鼠标悬停：把焦点移过去。**不推进**，只移焦点。
##
## 用户拍板「悬停要音效」，所以焦点真的变了就播 `ui_select`；
## 但**一帧最多响一次** —— 快速划过长列表时，同一帧会连着跨过好几行。
func _hover_focus(i: int) -> void:
	# ★63-19b 滚轮刚移完焦点：这段时间内**忽略悬停**。
	# 光标没动，但系统仍可能补一发 motion（触摸板双指滑 / 高精度滚轮），
	# 那一发会把滚轮刚移到的焦点**拽回光标那一行** ⇒ 用户感觉"滚不动"。
	if _time < _hover_mute_until:
		return
	if i < 0 or i == _focus_index():
		return
	_set_focus(i)
	var frame := Engine.get_process_frames()
	if _hover_sfx_frame != frame:
		_hover_sfx_frame = frame
		Audio.play_ui("ui_select")


## 鼠标事件总入口（★63-19）。**不改 `mouse_filter`** —— `Node._input()` 不受它影响。
##
## 闸门与键盘对齐：
##   hover      → 只要 `visible`（菜单没开就不该改索引）
##   点击 / 滚轮 → 要 `active and input_lockout <= 0 and not _await_release`
##                —— **与 `_process()` 调 `_read_input()` 的条件逐字相同**，
##                这样"设了意图"与"消费意图"必然发生在同一帧，不会留下一条过期的点击。
func _handle_mouse(event: InputEvent) -> void:
	if not visible:
		return
	# ⚠️⚠️ 位置取自**事件自带**的 `position`，**不用** `get_local_mouse_position()`。
	# 后者读的是"当前 OS 光标在哪儿"，与"这一发事件发生在哪儿"**是两件事**：
	# 光标移动是**异步**的（Windows 的 `WM_MOUSEMOVE` 要好几帧才生效）⇒
	# 事件已经派发、光标还没挪到位 ⇒ 读到的是**旧位置** ⇒ 悬停算错行。
	# ★63-19 实测：连跑 10 次真机探针红 3~4 次，**每次红的项都不一样**
	#（悬停 / 卡片悬停 / 滚轮 轮流红）—— 这是竞态的指纹，不是某条逻辑写错。
	# 菜单是铺满视口的 `Control`（无变换）⇒ 事件坐标与控件局部坐标同系。
	if not (event is InputEventMouse):
		return
	var mpos := (event as InputEventMouse).position
	if event is InputEventMouseMotion:
		_hover_focus(row_at_point(size, _list_geometry(), mpos))
		return
	if not (active and input_lockout <= 0.0 and not _await_release):
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	# 指针位于介绍区时，滚轮只翻阅文案，不切换机体。
	if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		for entry in _lore_regions:
			if (entry["rect"] as Rect2).has_point(mpos) and int(entry["max"]) > 0:
				var direction := -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1
				_lore_scroll[entry["id"]] = clampi(int(_lore_scroll.get(entry["id"], 0)) + direction * 3, 0, int(entry["max"]))
				queue_redraw()
				get_viewport().set_input_as_handled()
				return
	# 滚轮：相对量，**累积**（一帧滚三格就走三行）。
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_mouse_wheel -= 1
		_hover_mute_until = _time + WHEEL_HOVER_MUTE
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_mouse_wheel += 1
		_hover_mute_until = _time + WHEEL_HOVER_MUTE
		return
	var mi := Intent.NONE
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if stage == Stage.LAN and row_at_point(size,_list_geometry(),mpos) < 0: return
		mi = Intent.CONFIRM
		# 左键「一次点击到位」：点在**别的行**上就先把焦点移过去，
		# 之后 `_read_input()` 会用与键盘**完全相同**的那段代码去推进。
		_hover_focus(row_at_point(size, _list_geometry(), mpos))
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		mi = Intent.BACK
		# ⚠️ 右键**故意不**移焦点：它的语义是"退一层"，本来就没有目标行。
		# 顺手改掉选中项的效果是"我只想退出去，机体怎么换了"。
	if mi == Intent.NONE:
		return
	_mouse_intent = mi
	_mouse_intent_frame = Engine.get_process_frames()


func _read_lan_room_input() -> void:
	if Input.is_action_just_pressed("menu_back") or _mi_back:
		_cancel_lan()
		return
	if Net.role == Net.Role.NONE:
		_lan_wait = false
		return
	if Net.start_committed:
		_lan_wait = false
		LanBrowser.stop()
		_launch()
		return
	if Net.role == Net.Role.CLIENT and not Net.choices_ready() and _lan_wait_elapsed >= Net.LAN_WAIT_TIMEOUT:
		var connected := Net.peer_ready
		_lan_teardown()
		Game.lan_status = "房间信息同步超时：请确认双方游戏版本一致" if connected else "连接超时：请检查主机地址和 UDP 防火墙"
		return
	lan_form_choice = maxi(0, LAN_FORMS.find(Net.choice_of("form", selected_lan_form())))
	if Net.role == Net.Role.HOST:
		LanBrowser.update_beacon(2 if Net.peer_ready else 1, selected_lan_form())
	var dy := _axis_delta(nav_axis(Stage.LAN))
	if dy == 0: dy = _mi_d
	if dy != 0: lan_lobby_row = posmod(lan_lobby_row + dy, LOBBY_ROWS.size())
	var dx := _nav_x()
	var confirm := Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("fire_gun") or _mi_ok
	if dx == 0 and not confirm: return
	var step := dx if dx != 0 else 1
	match lan_lobby_row:
		0, 1:
			Net.request_form(LanPlan.Form.ACE_DUEL if lan_lobby_row == 0 else LanPlan.Form.SQUAD)
			suit_index = 0
		2:
			side_index = posmod(side_index + step, side_choices().size())
			suit_index = 0
			Net.announce_choice(selected_suit(), side_index_to_side(), selected_lan_form())
		3:
			suit_index = posmod(suit_index + step, active_suit_list().size())
			Net.announce_choice(selected_suit(), side_index_to_side(), selected_lan_form())
		4:
			if confirm: Net.set_ready(not Net.local_ready)
		5:
			if confirm: _cancel_lan()
	Audio.play_ui("ui_select")

func _draw_lan_lobby() -> void:
	var g := _list_geometry()
	for i in range(g.first,g.first+g.shown):
		var value := ""
		match i:
			0: value = "已选" if Net.choice_of("form",-1) == LanPlan.Form.ACE_DUEL else "一人一台 · 无 AI 僚机"
			1: value = "已选" if Net.choice_of("form",-1) == LanPlan.Form.SQUAD else "阵营编队 · AI 僚机"
			2: value = BattleFormation.side_name(side_index_to_side())
			3: value = _menu_profile(Net.choice_of("suit", selected_suit())).display_name
			4:
				value = "本机 " + ("已准备" if Net.local_ready else "未准备")
				value += " / 对方 " + ("已准备" if Net.remote_ready else ("未准备" if Net.choices_ready() else ("同步选择中" if Net.peer_ready else "连接中" if Net.role == Net.Role.CLIENT else "等待加入")))
		var hint := "双方准备后开始" if i == 4 else "更换选择将取消双方准备"
		if i == 4 and Net.choices_ready() and not Net.valid_pair(): hint = Net.invalid_pair_reason()
		if i == 5: hint = "断开连接并返回机体选择"
		if i == 3:
			hint = "地图：" + MapDef.by_id(Net.match_map()).name_cn
			if Net.remote_suit >= 0: hint += " · 对方：" + _menu_profile(Net.remote_suit).display_name
		_draw_lan_row_base(row_rect(size,g,i), LOBBY_ROWS[i], value, hint, i == lan_lobby_row, false, "")
	_draw_scroll_indicator(g.count,lan_lobby_row,g.shown,g.m)


var _super_notice:PanelContainer
var _super_notice_left:=0.0
func show_super_hard_notice()->void:
	if not is_instance_valid(_super_notice):
		_super_notice=PanelContainer.new();_super_notice.name="SuperHardUnlockNotice";_super_notice.z_index=100
		_super_notice.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_super_notice)
		_super_notice.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		_super_notice.offset_left=-356;_super_notice.offset_top=-118;_super_notice.offset_right=-32;_super_notice.offset_bottom=-52
		var panel:=StyleBoxFlat.new();panel.bg_color=Color(.025,.05,.065,.96);panel.border_color=Color(.45,1,.65,.9)
		panel.set_border_width_all(1);panel.set_content_margin_all(18);_super_notice.add_theme_stylebox_override("panel",panel)
		var label:=Label.new();label.text="超级困难模式已开放";label.add_theme_font_size_override("font_size",20)
		if _font!=null:label.add_theme_font_override("font",_font)
		label.add_theme_color_override("font_color",Color(.75,1,.85));label.mouse_filter=Control.MOUSE_FILTER_IGNORE;_super_notice.add_child(label)
	_super_notice_left=8.0;_super_notice.modulate.a=1.0;_super_notice.show()
func _tick_super_notice(delta:float)->void:
	if not is_instance_valid(_super_notice) or not _super_notice.visible:return
	_super_notice_left=maxf(0,_super_notice_left-delta)
	_super_notice.modulate.a=minf(1,_super_notice_left)
	if _super_notice_left<=0:_super_notice.hide()
