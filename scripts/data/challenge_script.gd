class_name ChallengeScript
extends RefCounted
## 剧情挑战表（1.2）：**玩家选谁，就按剧情遭遇谁、在哪张图上遭遇**。
##
## 用户给的规则（原文）：
##   - 选 **柯西**：可以遭遇 **佩涅罗佩（太平洋上空）**，也可以遭遇 **阿利宙斯（艾尔斯岩）**；
##   - 选 **佩涅罗佩**：只能遭遇 **柯西（太平洋上空）**；
##   - 选 **阿利宙斯**：只能遭遇 **柯西（艾尔斯岩）**；
##   - **柯西遭遇阿利宙斯时**：阿利宙斯先不出场，先出**两台古斯塔夫00**；
##     两台都打掉之后，阿利宙斯才**从上方出场**。
##
## 于是"挑战"= 一组(waves)：每一波是一批敌方单位，前一波清空才刷下一波。
## 波次的存在让"先打杂兵再打 BOSS"这件事变成**数据**而不是散在 main 里的 if。

## 一波敌人。
class Wave extends RefCounted:
	## 这一波要出几架。
	var count := 1
	## 用哪台机（`SuitProfile.Id`）。
	var suit: int = SuitProfile.Id.PENELOPE
	## 出场高度（米）。普通波次跟对战一样（3200 上下）；
	## BOSS 波次更高 —— 用户要求阿利宙斯"从上方出场"。
	var altitude := 3200.0
	## 出场方位角（度）。两架杂兵左右分开，从玩家前方两侧压上来。
	var spread_deg := 0.0
	## 出场之后的 AI 状态：`BanditAI.State.SEEK` 就是"先找目标"。
	## 从上方登场的 BOSS 用 ATTACK（它一出现就压着你打）。
	var aggressive := false

	func _init(n: int, s: int, alt := 3200.0, spread := 0.0, aggr := false) -> void:
		count = n
		suit = s
		altitude = alt
		spread_deg = spread
		aggressive = aggr

	## 这一波敌机的名字（HUD 提示与战斗日志用）。
	func suit_name() -> String:
		return SuitProfile.by_id(suit).display_name


## 一组遭遇：玩家机体 → 敌机 + 地图 + 波次 + 标题/简报。
class Encounter extends RefCounted:
	var id := ""
	var player_suit: int = SuitProfile.Id.XI
	var enemy_suit: int = SuitProfile.Id.PENELOPE
	var map_id: int = MapDef.Id.PACIFIC
	var title := ""
	var brief := ""
	## 挑战简报里显示的"剧情背景"（一句话）。
	var story := ""
	var waves: Array = []

	func enemy_name() -> String:
		return SuitProfile.by_id(enemy_suit).display_name

	func map_name() -> String:
		return MapDef.by_id(map_id).name_cn


## 全部遭遇。**顺序就是菜单里的顺序**：先按玩家机体分组，组内按剧情顺序。
static func all() -> Array:
	return [
		xi_vs_penelope(),
		xi_vs_arizeus(),
		penelope_vs_xi(),
		arizeus_vs_xi(),
	]


static func xi_vs_penelope() -> Encounter:
	var e := Encounter.new()
	e.id = "XI_VS_PENELOPE"
	e.player_suit = SuitProfile.Id.XI
	e.enemy_suit = SuitProfile.Id.PENELOPE
	e.map_id = MapDef.Id.PACIFIC
	e.title = "Ξ 对 RX-104FF"
	e.brief = "太平洋上空 · 1v1"
	e.story = "马夫蒂的Ξ高达迎击凯奈斯投入战线的佩涅罗佩。姐妹机的第一次交锋。"
	e.waves = [Wave.new(1, SuitProfile.Id.PENELOPE, 3450.0)]
	return e


static func xi_vs_arizeus() -> Encounter:
	var e := Encounter.new()
	e.id = "XI_VS_ARIZEUS"
	e.player_suit = SuitProfile.Id.XI
	e.enemy_suit = SuitProfile.Id.ARIZEUS
	e.map_id = MapDef.Id.ULURU
	e.title = "Ξ 对 TX-ff104"
	e.brief = "艾尔斯岩 · 先清三台古斯塔夫，再从上方迎击阿利宙斯"
	# 1.2 用户给的文案。注意用户原句里的"三台**台**古斯塔夫"是重复了一个量词，
	# 这里按"三台古斯塔夫"写入（否则那行会读起来别扭）。
	e.story = "艾尔斯岩上空，留下来殿后的Ξ柯西高达撞上喀耳刻部队的三台古斯塔夫；" \
		+ "干掉它们之后，灰色的钢铁巨兽从天空上压下来。"
	e.waves = [
		# 第一波：两台量产机（**没有浮游导弹**），左右分开压上来
		# ⚠️ 1.2 用户要求：**三台**（原为两台）。`_spawn_wave()` 里按 `wave.count`
		# 均匀分配方位角，所以这里只改数量即可，不必动出场逻辑。
		Wave.new(3, SuitProfile.Id.GUSTAV00, 3200.0, 62.0),
		# 第二波：阿利宙斯从上方入场（用户要求"从上方出场"）
		Wave.new(1, SuitProfile.Id.ARIZEUS, 6200.0, 0.0, true),
	]
	return e


static func penelope_vs_xi() -> Encounter:
	var e := Encounter.new()
	e.id = "PENELOPE_VS_XI"
	e.player_suit = SuitProfile.Id.PENELOPE
	e.enemy_suit = SuitProfile.Id.XI
	e.map_id = MapDef.Id.PACIFIC
	e.title = "RX-104FF 对 Ξ"
	e.brief = "太平洋上空 · 1v1"
	e.story = "佩涅罗佩追上了Ξ高达。拦截者与猎物，同一片太平洋上空。"
	e.waves = [Wave.new(1, SuitProfile.Id.XI, 3450.0)]
	return e


static func arizeus_vs_xi() -> Encounter:
	var e := Encounter.new()
	e.id = "ARIZEUS_VS_XI"
	e.player_suit = SuitProfile.Id.ARIZEUS
	e.enemy_suit = SuitProfile.Id.XI
	e.map_id = MapDef.Id.ULURU
	e.title = "TX-ff104 对 Ξ"
	e.brief = "艾尔斯岩 · 1v1"
	e.story = "练习机阿利宙斯在艾尔斯岩上空挡下了Ξ高达 —— 它本是过去亡灵的幻影。"
	e.waves = [Wave.new(1, SuitProfile.Id.XI, 3450.0)]
	return e


## 某台机体的挑战列表。柯西有两场，另外两台各一场。
static func for_suit(suit_id: int) -> Array:
	var out: Array = []
	for e: Encounter in all():
		if e.player_suit == suit_id:
			out.append(e)
	return out


static func by_id(id: String) -> Encounter:
	for e: Encounter in all():
		if e.id == id:
			return e
	return null


## 一场挑战的总波次数 / 总敌机数（HUD 的"进度"与测试用）。
static func wave_count(e: Encounter) -> int:
	return e.waves.size() if e != null else 0


static func total_enemies(e: Encounter) -> int:
	if e == null:
		return 0
	var n := 0
	for w: Wave in e.waves:
		n += w.count
	return n
