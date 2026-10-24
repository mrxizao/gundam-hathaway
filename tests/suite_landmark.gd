class_name SuiteLandmark
extends RefCounted

## 「**只读信标**」判据：**运输仓**（LEO）与 **内阁成员所在酒店**（达沃中央针塔，M01 的目标）。
##
## ## 这一套在钉什么
##
## 两条信标共用**同一套机制**（`hud.gd._draw_beacons()` 逐条读 `BEACONS` 表），
## 于是有一整类**不会报错的失败**只有这里钉得住：
##
## | 症状 | 为什么会静默 |
## |---|---|
## | 屏幕上什么都不画 | 组名对不上（表里引常量 vs 建图时写字面量） |
## | 信标被 AI 咬 / 被打掉 | 它混进了 `units` 组（那就只剩一个开关在守） |
## | 框画在**塔腰**上 | 显示锚点直接用了**打中判定**那组的组员坐标 |
## | 「全城最高的楼」莫名变红 | 纯显示锚点挂在 `_terrain_root` 上，被"扫根子女"的判据算进去 |
## | 两条信标同一个颜色 | 表里复制粘贴时忘了改 `color`（"要去的地方"与"要打的东西"不可分） |
##
## ## 为什么必须有**真图**
##
## 信标是**运行时**建的（`Marker3D`），源码扫描证明不了"组里到底有几个、挂在谁身上、
## 在不在 `units`"。所以本套起一局真场景、切到**达沃**再量。
##
## ⚠️ 运输仓那三条已经在 `suite_space_map` 里钉过一遍（那边有 LEO 图）。
## 这里**有意重复**它们是"两条信标共用同一套保证"的证据 —— 只要有一条漏了某一条，
## 两个套件就会分家。

const HUD := preload("res://scripts/ui/hud.gd")
const HUD_PATH := "res://scripts/ui/hud.gd"
const WB_PATH := "res://scripts/world/world_builder.gd"
const MS := preload("res://scripts/data/mission_script.gd")

## 信标表里两条的**顺序**也是约定：0 = 运输仓、1 = 酒店。
## ⚠️ 顺序写进断言不是为了好看 —— 上面"颜色语义"那两条靠它定位，
## 换了顺序就会把"绿/红"判反（而两条都能画出来，肉眼很难发现）。
const BEACON_POD := 0
const BEACON_HOTEL := 1


static func run(t: T, host: Node) -> void:
	_table(t)
	_gate(t)
	await _live(t, host)


# ============================================================ ① 表（纯函数 + 源码）
static func _table(t: T) -> void:
	t.suite("Landmark · 只读信标表")

	# 三个组名两两不同。⚠️ 合并任意两个都会**静默**出错：
	#   · 显示组并进打中组 ⇒ 框画在"某个段盒的心"上（塔腰 ~ 塔顶之间乱跳）；
	#   · 打中组并进显示组 ⇒ 信标进了 `units` 那条链（能被咬、能被结算）。
	t.ok(WorldBuilder.HOTEL_TAG_GROUP != "", "酒店信标组名非空")
	t.ok(WorldBuilder.HOTEL_TAG_GROUP != WorldBuilder.HOTEL_GROUP,
		"★ 酒店：**显示**组 ≠ **打中**组（%s / %s）"
			% [WorldBuilder.HOTEL_TAG_GROUP, WorldBuilder.HOTEL_GROUP])
	t.ok(WorldBuilder.HOTEL_TAG_GROUP != WorldBuilder.POD_TAG_GROUP,
		"★ 酒店信标组 ≠ 运输仓信标组（复制粘贴最容易撞的一处）")
	t.ok(WorldBuilder.POD_TAG_GROUP != WorldBuilder.HOTEL_GROUP,
		"运输仓的显示组 ≠ 酒店的打中组")

	# 表覆盖：恰好两条，且引的是**建图那两个常量**（不是字面量）。
	t.eq(HUD.BEACONS.size(), 3, "信标表包含运输仓、酒店、英勇号三条")
	var g0 := str((HUD.BEACONS[BEACON_POD] as Dictionary)["group"])
	var g1 := str((HUD.BEACONS[BEACON_HOTEL] as Dictionary)["group"])
	t.eq(g0, WorldBuilder.POD_TAG_GROUP, "第 0 条是运输仓，组名引 `WorldBuilder` 的常量")
	t.eq(g1, WorldBuilder.HOTEL_TAG_GROUP, "第 1 条是酒店，组名引 `WorldBuilder` 的常量")
	t.ok(g0 != g1, "两条的组名互不重复")
	for b: Dictionary in HUD.BEACONS:
		t.ok(str(b["label"]) != "", "「%s」有显示名" % str(b["group"]))
		t.ok(b["color"] is Color, "「%s」的颜色是 Color" % str(b["group"]))

	# 颜色语义：**绿 = 要去的地方；红 = 要打的东西**。
	# ⚠️ 这一条钉的是"别把两条刷成同一个色" —— 那会让"目的地"与"射击目标"
	# 在屏幕上不可分（玩家只能靠读字），而两条都画得出来、肉眼很难发现。
	t.eq(HUD.BEACONS[BEACON_POD]["color"], HUD.HUD,
		"运输仓是 `HUD`（绿）：**自己要去的地方**")
	t.eq(HUD.BEACONS[BEACON_HOTEL]["color"], HUD.DANGER,
		"酒店是 `DANGER`（红）：**要打的东西**（绿会读成「我方设施、别打」，是主动误导）")

	# 画法只有**一处**：主视图与雷达都逐条读同一张表。
	var hud_src := SuiteUiStyle._code(HUD_PATH)
	t.eq(hud_src.count("BEACONS :="), 1, "信标表只有一份定义")
	t.eq(hud_src.count("func _draw_beacons("), 1, "`_draw_beacons()` 只有一处定义")
	t.eq(hud_src.count("_draw_pod_marker"), 0, "旧的单条函数已撤（不留第二套画法）")
	t.eq(hud_src.count("for b: Dictionary in BEACONS"), 2,
		"★ 主视图与雷达**都**逐条读 `BEACONS`（一处画框、一处画雷达方框）")

	# 建图侧：两个组各自**只**在对应的建图函数里被登记一次。
	var wb_src := SuiteUiStyle._code(WB_PATH)
	t.eq(wb_src.count("add_to_group(HOTEL_TAG_GROUP)"), 1,
		"酒店信标只登记一处（多一处 ⇒ 屏幕上有两个框 / 两个雷达刻度）")
	t.eq(wb_src.count("add_to_group(POD_TAG_GROUP)"), 1, "运输仓信标只登记一处")


# ============================================================ ①b 按关显示
## ★★ 2026-10-01 老板：
## > 「**运输仓只在 M04 和 M03 加进来就好了，其他时候就不要标在地图里**」
## > 「包括**迪拜塔 M01 的标记，不要在 M02 加进来**」
##
## ## 这一节钉的是**判据的归属**：显示与否由**关卡**说了算，不由**图**说了算
##
## 最容易静默的一处是 **M01 / M02** —— 两关用的是**同一张达沃图**，
## 一个要框、一个不要。只要有人把判据改回"按图判 / 组里有没有节点"，
## M02 就会**多出一个框而不报错** —— 那条路本来就是这么错的：
## 酒店是达沃的一部分，M02 也跑在达沃图上 ⇒ 跟着画了。
## **M04 / M06** 是同一件事在太平洋图上的翻版（运输仓按图建在太平洋，
## 而 M06「海上袭击」不该有它）。
static func _gate(t: T) -> void:
	t.suite("Landmark · 按关显示（M03/M04 才有运输仓 · M01 才有酒店）")

	# ---- 默认值 ----
	# ⚠️ 默认反过来（`true`）的代价是"七关里有五关凭空多一个框"。
	var tmp: MS.Mission = MS.Mission.new("TMP", "临时")
	t.eq(tmp.pod_beacon, false, "★ 新字段默认 `false`（没写它的关一条都不标）")
	t.eq(tmp.beacon_groups().size(), 0, "★ 没写任何字段的关 ⇒ 信标表为空")
	t.ok(not tmp.shows_beacon(WorldBuilder.HOTEL_TAG_GROUP), "默认不标酒店")
	t.ok(not tmp.shows_beacon(WorldBuilder.POD_TAG_GROUP), "默认不标运输仓")

	# ---- 组名字面量与建图侧**逐字相同**（跨模块）----
	# 写错一个字母的表现是"屏幕上什么都不画"，**一处都不报错**。
	t.eq(MS.Mission.POD_TAG_GROUP, WorldBuilder.POD_TAG_GROUP,
		"★ `Mission.POD_TAG_GROUP` 与 `WorldBuilder.POD_TAG_GROUP` 逐字相同")
	t.eq(MS.Mission.HOTEL_TAG_GROUP, WorldBuilder.HOTEL_TAG_GROUP,
		"★ `Mission.HOTEL_TAG_GROUP` 与 `WorldBuilder.HOTEL_TAG_GROUP` 逐字相同")
	# ⚠️⚠️ 而**显示组 ≠ 打中组**（`hotel_target` vs `davao_hotel`）——
	# 这条是"酒店那一支为什么不能直接把 `landmark_group` 当组名用"的判据。
	# 写成本节最容易犯的错正好就是"顺手把 `landmark_group` 塞进信标表"：
	# 那样屏幕上一个框都不会有（组里根本没有成员），**且一处都不报错**。
	t.ok(MS.Mission.HOTEL_TAG_GROUP != WorldBuilder.HOTEL_GROUP,
		"★★ 显示组（`hotel_target`）≠ 打中组（`davao_hotel`）—— 别拿 `landmark_group` 当信标组名")

	# ---- 逐关表 = **老板那句话的可执行形式** ----
	# 每项 = [酒店标不标, 运输仓标不标]。
	var want := {
		"M01": [true, false],    # 酒店 ✓（它的 `landmark_group` 就是那座塔）
		"M02": [false, false],   # ★ **同一张达沃图**，不标
		"M03": [false, true],    # 运输仓 ✓
		"M04": [false, true],    # 运输仓 ✓（这一关它只是演出道具）
		"M05": [false, false],
		"M06": [false, false],   # ★ **同一张太平洋图**，不标
		"M07": [false, false],
	}
	for mid: String in want.keys():
		var m: MS.Mission = MS.by_id(mid)
		t.ok(m != null, "找到 %s" % mid)
		if m == null:
			continue
		var w: Array = want[mid]
		t.eq(m.shows_beacon(WorldBuilder.HOTEL_TAG_GROUP), bool(w[0]),
			"%s：酒店信标 %s" % [mid, ("标" if bool(w[0]) else "不标")])
		t.eq(m.shows_beacon(WorldBuilder.POD_TAG_GROUP), bool(w[1]),
			"%s：运输仓信标 %s" % [mid, ("标" if bool(w[1]) else "不标")])

	# ---- 酒店那一条是**派生**的，不是第二份手写数据 ----
	# 要不要标 = `landmark_group` 非不非空（同一件事的两面）；
	# 但**组名不取 `landmark_group`** —— 那是打中组的名字，见上面那条不等式。
	# 两份手写数据迟早分家，而分家的表现是最难查的一类："**框在那儿、目标却不走**"。
	var m1: MS.Mission = MS.by_id("M01")
	t.ok(not m1.landmark_group.is_empty(), "M01 有 `landmark_group`")
	t.eq(m1.beacon_groups(), PackedStringArray([WorldBuilder.HOTEL_TAG_GROUP]),
		"★ M01 的信标表 = [`hotel_target`]（由 `landmark_group` 定**要不要**）")
	t.eq(m1.beacon_groups().size(), 1, "★ 而且只有一条（多一条 = 屏幕上两个框）")
	t.ok(not m1.beacon_groups().has(m1.landmark_group),
		"★★ 而且里面**没有** `davao_hotel`（那是打中组 ⇒ 画不出任何东西）")

	# ---- 自由遭遇（4 场）一条都不标 ----
	# 它们也有 `active_mission`（`free_from_encounter()` 派生的），
	# 但没有任何一关在"要打这座塔 / 接这只仓"。
	var fr := MS.free_all()
	t.gt(float(fr.size()), 0.0, "自由遭遇表非空（否则下面那条是空转）")
	for fm: MS.Mission in fr:
		t.eq(fm.beacon_groups().size(), 0, "自由遭遇「%s」不标任何信标" % fm.id)

	# ---- HUD 侧：**两个消费者共用一个闸门** ----
	var hud_src := SuiteUiStyle._code(HUD_PATH)
	t.eq(hud_src.count("func _beacon_shown("), 1, "闸门只有一个定义")
	t.eq(hud_src.count("if not _beacon_shown("), 2,
		"★ 主视图的框与雷达上的方框**都**过闸门（漏一处 = 只对了一半的画面）")

	# ⚠️ 判据必须问**关卡**、不能问**图** —— 这是这一节存在的全部理由。
	# 源码判据在**剥过注释**的正文上做（`_code()` 已剥），否则注释里那几段
	# 论证（本来就写着 `MapDef` 这些字）会把假绿喂进来。
	var gate := _func_body(hud_src, "_beacon_shown")
	t.ok(gate != "", "取到 `_beacon_shown()` 的正文")
	t.ok(gate.contains("Game.active_mission"), "★ 闸门读的是 `Game.active_mission`（当前关卡）")
	t.ok(not gate.contains("MapDef"), "★★ 闸门里**没有**按图判（`MapDef` 一个字都不该出现）")
	t.ok(not gate.contains("group =="),
		"★ 闸门里没有 `if group == …`（哪一关标哪几条全在 `Mission` 一侧）")


# ============================================================ ② 真图（达沃）
static func _live(t: T, host: Node) -> void:
	t.suite("Landmark · 真图（达沃）")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	host.add_child(main)
	await host.get_tree().process_frame
	var world: Node = main.get("world")
	t.ok(world != null, "世界已建出")
	world.call("apply_map", MapDef.by_id(MapDef.Id.DAVAO))
	await host.get_tree().physics_frame

	var hotel: Array = host.get_tree().get_nodes_in_group(WorldBuilder.HOTEL_GROUP)
	t.eq(hotel.size(), 5, "酒店**打中**组 = 4 段塔身 + 塔尖（顶灯不进组）")
	var spire := _find_named(hotel, "NeedleSpire")
	t.ok(spire != null, "找到塔尖那件几何")

	var tags: Array = host.get_tree().get_nodes_in_group(WorldBuilder.HOTEL_TAG_GROUP)
	t.eq(tags.size(), 1, "★ 达沃图上恰好**一个**酒店信标（多一个 ⇒ 屏幕上两个框）")
	if tags.size() == 1:
		var tag := tags[0] as Node3D
		t.ok(tag != null, "信标是个 `Node3D`")
		t.eq(str(tag.name), "HotelTarget", "名字叫 `HotelTarget`")
		t.ok(not str(tag.name).begins_with("Pod"),
			"⚠️ 名字**不以 `Pod` 开头**（`suite_space_map._pods_aabb()` 按该前缀扫子树量外框）")
		t.ok(not (tag is MeshInstance3D), "信标**没有网格**（⇒ 不污染 `_subtree_aabb` 那类测量）")

		# ★★ 「可显示但不可被攻击」的**结构性保证**：它不是靠一个开关，
		# 而是靠它根本不在武器门 / AI 的判定链上。
		t.ok(not tag.is_in_group("units"),
			"★★ 信标**不在** `units` 组（⇒ 不进锁定候选表、AI 不会咬）")
		t.ok(not tag.has_method("take_damage"), "★★ 信标没有 `take_damage`（⇒ 打不掉）")
		t.ok(not tag.has_method("is_hostile_to"), "★★ 信标没有 `is_hostile_to`（⇒ 不会被当敌人）")
		var in_units := 0
		for u: Node in host.get_tree().get_nodes_in_group("units"):
			if str(u.name) == "HotelTarget":
				in_units += 1
		t.eq(in_units, 0, "★★ `units` 组里没有任何信标节点（在实建场景里数一遍）")

		# 位置：**塔尖顶** = 塔尖盒心 + 半个盒高。
		# ⚠️ 期望值**从几何本身推**（`MeshInstance3D.scale.y` 就是那件盒的 y 边长，
		# 见 `_add_box()` 的 `mi.scale = size`），不从 `CITY_SHAPE.needle_mul` 抄 ——
		# 抄一次就等于把"塔有多高"变成了第二份真源，改倍率时这条会假绿。
		if spire != null:
			var mesh := (spire as Node).get_node_or_null("Mesh") as MeshInstance3D
			t.ok(mesh != null, "塔尖那件几何有 `Mesh` 子节点（`_add_box()` 的约定）")
			if mesh != null:
				var half := mesh.scale.y * 0.5
				t.ok(half > 0.0, "针高为正（%.1f m）" % mesh.scale.y)
				var want := (spire as Node3D).global_position.y + half
				t.near(tag.global_position.y, want, 1.0,
					"★ 信标在**塔尖顶**（塔尖盒心 + 半盒高 = %.0f m）" % want)
				t.near(tag.global_position.x, (spire as Node3D).global_position.x, 1.0,
					"信标在塔的轴线上（x）")
				t.near(tag.global_position.z, (spire as Node3D).global_position.z, 1.0,
					"信标在塔的轴线上（z）")
			# 而且它比打中组里最高的那件**还高**（"塔尖顶"这句话的可证伪形式）。
			var spire_top := -1.0e30
			for h: Node in hotel:
				if h is Node3D:
					spire_top = maxf(spire_top, (h as Node3D).global_position.y)
			t.gt(tag.global_position.y, spire_top, "★ 而且高于打中组里最高的那件")

		# ★★ 挂载点：**不做 `_terrain_root` 的直接子节点**。
		# 实测理由（2026-09-30）：`suite_round` 的「酒店确实是全城最高的楼」判据扫的是
		# `_terrain_root` 的**直接子节点**取最高的那个、只排掉 `HOTEL_GROUP` 成员与
		# `Needle*` 名字 ⇒ 信标挂在根上会**把它自己**算成"全城最高的东西"，
		# 那条断言必红、且读数长成"酒店 8418 < 信标 9065"这种莫名其妙的样子。
		# ⇒ 凡"只用来显示"的锚点，先问一句"**谁会来扫这棵子树**"。
		var troot: Node = world.get("_terrain_root")
		t.ok(troot != null, "拿到达沃的地表根")
		t.ok(tag.get_parent() != troot,
			"★★ 信标**不是** `_terrain_root` 的直接子节点（否则会被「扫根子女」的判据算进去）")
		t.ok(_is_under(tag, troot), "但它仍在这棵子树里（换图时会跟着一起清掉）")

	# 信标是**按图**建的、不是全局开关：达沃上不该有运输仓的信标。
	t.eq(host.get_tree().get_nodes_in_group(WorldBuilder.POD_TAG_GROUP).size(), 0,
		"达沃图上没有运输仓信标（⇒ 信标是**按图**建的，不是全局开关）")

	# ---- ★★ 闸门的**活证据**：同一张达沃图，换关卡换答案 ----
	#
	# ⚠️ 这一段就是老板那句话的**判别器**。改前 M02 会跟着 M01 一起画框，
	# 因为判据是"图上有没有这个节点" —— 而两关用的是**同一张图**。
	#
	# ⚠️ 这里只调 `_beacon_shown()`，**不同步节点**：它是纯判据
	#（"这一关要不要它"），而"节点在不在组里"由上面前半段与 `suite_space_map` 管。
	# 两块分开钉，正是为了"M06 没有运输仓框"这条能在**不建太平洋图**的前提下验。
	var hud: Node = main.get("hud")
	t.ok(hud != null, "拿到 HUD")
	var prev_mission = Game.active_mission
	if hud != null:
		Game.active_mission = null
		t.ok(not bool(hud.call("_beacon_shown", WorldBuilder.HOTEL_TAG_GROUP)),
			"★ 没有关卡（对战 / 挑战 / 训练 / LAN）⇒ 一条都不标")
		Game.active_mission = MS.by_id("M01")
		t.ok(bool(hud.call("_beacon_shown", WorldBuilder.HOTEL_TAG_GROUP)),
			"★ M01（达沃）⇒ 标酒店")
		Game.active_mission = MS.by_id("M02")
		t.ok(not bool(hud.call("_beacon_shown", WorldBuilder.HOTEL_TAG_GROUP)),
			"★★ M02（**同一张达沃图**）⇒ 不标（判据是关卡，不是图）")
		Game.active_mission = MS.by_id("M03")
		t.ok(bool(hud.call("_beacon_shown", WorldBuilder.POD_TAG_GROUP)),
			"★ M03 ⇒ 标运输仓")
		Game.active_mission = MS.by_id("M06")
		t.ok(not bool(hud.call("_beacon_shown", WorldBuilder.POD_TAG_GROUP)),
			"★ M06（**同一张太平洋图**）⇒ 不标运输仓")
	Game.active_mission = prev_mission

	main.queue_free()
	await host.get_tree().process_frame


# ============================================================ 工具
## 取某个函数在**剥过注释**的源码里的正文（`func <name>(` 到下一个顶格 `func`）。
##
## ⚠️ 为什么需要它：`_code()` 只剥注释，`count("xxx")` 仍然会命中**别的函数里**
## 的同名调用。要断言"某个判据**只**在闸门里、别的字一个都不许有"，
## 就得先把正文切出来。hud.gd 的函数全是顶格写的，按行找下一个 `func` 即可。
static func _func_body(src: String, fname: String) -> String:
	var i := src.find("func " + fname + "(")
	if i < 0:
		return ""
	var out: Array = []
	var lines := src.substr(i).split("\n")
	for k in lines.size():
		var s := str(lines[k])
		if k > 0 and (s.begins_with("func ") or s.begins_with("static func ")):
			break
		out.append(s)
	return "\n".join(out)

static func _find_named(nodes: Array, n: String) -> Node:
	for x: Node in nodes:
		if str(x.name) == n:
			return x
	return null


static func _is_under(n: Node, root: Node) -> bool:
	if root == null:
		return false
	var p := n.get_parent()
	while p != null:
		if p == root:
			return true
		p = p.get_parent()
	return false
