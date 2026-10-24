class_name SuiteMesserRoster
extends RefCounted
## 梅萨指挥官型 / 梅萨F01型 —— **进游戏、并在小队战的马夫蒂里能选**。
##
## ## 老板原话
## 「把**梅萨指挥官型和梅萨f01型导入游戏里面，在小队战的马夫蒂里面能选**」。
##
## ## 这一套守的是哪几件事（四件里有两件是"静默的"）
## | # | 事 | 不守住的后果 |
## |---|---|---|
## | ① | **两台机在 `by_id()` 里各有一支** | 漏了 ⇒ **静默回落成柯西**（那函数的兜底是 `return xi()`） |
## | ② | **两台机在 `kind_for_suit()` 里是马夫蒂的** | 漏了 ⇒ **静默骑喀耳刻板**（兜底是 `Kind.KILCE`） |
## | ③ | 模型资产真在、尺寸口径对 | 尺寸错 ⇒ 机体被缩放到离谱大小，但**不报错** |
## | ④ | 阵营池 / 踏板 / 编制三处**互相一致** | 跨阵营不会报错，只有玩家看见"自己人被对面开" |
##
## ★ 判据尽量写成**逐台量**（"这一池子里每一台的板都是本阵营的"），
## 而不是逐台点名 —— 后者每加一台机就要改一遍测试，而且改的人会顺手把新机漏掉。
##
## ## ★ 这一套在 N58（2026-09-29）**被自己钉红了两次**，两次都按新事实改了口径
## 原本它如实钉住"**无骨架、无动画**"（Tripo 原样导出，`skins:0 / animations:0`），
## 并写着"哪天它们过了绑定流水线，这一节会**变红**，那时按新事实改口径"。
## N58 就是那一天 —— 两台都装上了骨架（相似变换贴 M01 的 `messer_rig_v1`），
## 27 段动作也接上了。于是本节的口径翻面：
##   - `Skeleton3D` / `AnimationPlayer`：**各 0 个 → 各 1 个**；
##   - `model_anim_files`：**空 → 27 段**（与 M01 逐字同一份，理由见 `suit_profile.gd`）；
##   - `body._model_skel`：**null → 非 null**（锚点从模型骨架取，不再退占位骨架）。
## ⚠️ 保留"变红就该改口径"这条设计意图：本节钉的是**事实**，不是"永远无骨架"。
##
## ⚠️ 按**主题命名**（本仓库有并行会话，两侧都按轮次占号时撞过一次文件）。

const DATA := "MesserRoster / 数据层：两台机各有一支（不能回落柯西）"
const ASSET := "MesserRoster / 资产：模型真在、且已装骨架（27 段动作）"
const SIZE := "MesserRoster / 尺寸口径：native_height / target_height / 朝向"
const POOL := "MesserRoster / 阵营池 · 踏板 · 编制：三处必须一致"
const FLY := "MesserRoster / 真机接进去：能飞、缩放对、锚点在"


static func run(t: T, host: Node) -> void:
	t.suite(DATA)
	_data(t)
	t.suite(ASSET)
	_asset(t)
	t.suite(SIZE)
	_size(t)
	t.suite(POOL)
	_pool(t)
	t.suite(FLY)
	await _fly(t, host)


## 两台新机的 id 与基本标识。
static func _data(t: T) -> void:
	var new_ids: Array[int] = [SuitProfile.Id.MESSER_CMD, SuitProfile.Id.MESSER_F01]

	# ---- ① `by_id` 必须**逐台认人** ----
	#
	# ⚠️ 这条是本套件最值钱的一条：`by_id()` 的最后一行是 `return xi()`。
	# 加枚举值而忘了在 `by_id()` 里加分支 ⇒ `by_id(Id.MESSER_CMD)` 返回**柯西**，
	# 而且**不报任何错** —— 玩家在小队战里选"梅萨指挥官型"，
	# 出击的是柯西（模型、数值、名字全是柯西），看起来像"选了没生效"。
	# 所以这里比的不是"名字对不对"，而是 **`id` 字段本身**。
	for id: int in new_ids:
		var p := SuitProfile.by_id(id)
		t.eq(p.id, id,
			"★ by_id(%d).id == %d（漏改 by_id 分支会**静默回落柯西**，实测 id = %d）"
				% [id, id, p.id])
		t.not_ok(p.display_name.is_empty(), "id %d 有中文显示名" % id)
		t.not_ok(p.model_name.is_empty(), "id %d 有型号名" % id)

	# 阳性对照：柯西自己（证明这条判据不是"恒真"）
	t.eq(SuitProfile.by_id(SuitProfile.Id.XI).id, SuitProfile.Id.XI,
		"阳性对照：by_id(XI).id == XI")
	t.eq(SuitProfile.by_id(SuitProfile.Id.MESSER_M01).id, SuitProfile.Id.MESSER_M01,
		"阳性对照：M01 认得出自己")

	# ---- ② `id_name()` ----
	#
	# ⚠️ 它原来**两个梅萨都没有分支**，全部返回 `"XI"`（兜底也是柯西）。
	# 它当前**没有任何调用方**（于是这个错一直没人发现）——
	# 但它是个 public 的展示名入口，留着"错的答案"比删掉更危险。
	# ⇒ 顺手把三台梅萨全部补齐，并用"不再等于 XI"这条把它钉住。
	t.eq(SuitProfile.by_id(SuitProfile.Id.MESSER_CMD).id_name(), "MESSER_CMD",
		"id_name() 认得指挥官型（原来会返回 XI）")
	t.eq(SuitProfile.by_id(SuitProfile.Id.MESSER_F01).id_name(), "MESSER_F01",
		"id_name() 认得 F01型（原来会返回 XI）")
	t.eq(SuitProfile.by_id(SuitProfile.Id.MESSER_M01).id_name(), "MESSER_M01",
		"顺手补上 M01（它原来也返回 XI）")

	# ---- ③ 两台机是不同的 id（不能手滑写成同一个）----
	t.not_ok(SuitProfile.Id.MESSER_CMD == SuitProfile.Id.MESSER_F01,
		"两台新机是两个不同的 id")
	var names: Array[String] = []
	for id: int in new_ids:
		names.append(SuitProfile.by_id(id).display_name)
	t.eq(",".join(names), "梅萨指挥官型,梅萨F01型", "中文名（%s）" % ",".join(names))

	# ---- ④ `id_name()` 的三台梅萨必须互不相同（兜底不会再撞车）----
	var inames: Array[String] = []
	for id: int in [SuitProfile.Id.MESSER_M01, SuitProfile.Id.MESSER_CMD,
			SuitProfile.Id.MESSER_F01]:
		inames.append(SuitProfile.by_id(id).id_name())
	t.eq(",".join(inames), "MESSER_M01,MESSER_CMD,MESSER_F01",
		"三台梅萨的 id_name 互不相同（%s）" % ",".join(inames))


## 模型资产：文件真在、能实例化、而且**确实没有骨架/动画**。
static func _asset(t: T) -> void:
	var exp_mesh := {
		SuitProfile.Id.MESSER_CMD: 201,
		SuitProfile.Id.MESSER_F01: 182,
	}
	for id: int in exp_mesh:
		var p := SuitProfile.by_id(id)
		t.ok(ResourceLoader.exists(p.model_path),
			"%s 的模型在工程里（%s）" % [p.display_name, p.model_path])
		t.ok(p.model_path.begins_with("res://assets/models/"),
			"%s 的模型放在工程资产目录下（%s）" % [p.display_name, p.model_path])
		var res := load(p.model_path)
		t.ok(res is PackedScene, "%s 能被当成场景加载（%s）" % [p.display_name, str(res)])
		if not (res is PackedScene):
			continue
		var inst := (res as PackedScene).instantiate() as Node3D
		t.ok(inst != null, "%s 实例化出 Node3D" % p.display_name)
		if inst == null:
			continue
		# 网格数：glb 里是 201 / 182 个独立网格 —— 这里钉的是**下限式的不变量**
		#（"这是一台有细节的机体，不是占位体块"），不是那个精确数。
		# 钉精确数会让"导入器合并了网格"这种无害变化假红。
		var meshes := inst.find_children("*", "MeshInstance3D", true, false)
		t.gt(meshes.size(), 100,
			"%s 有 %d 个网格（远多于占位体块 ⇒ 真模型）" % [p.display_name, meshes.size()])
		# ---- ★ 装骨架后的现状：骨架 1 副、播放器 1 个、27 段动作留着 ----
		#
		# N58 之前这里钉的是"各 0 个"。相似变换贴过来的骨架**保方向**
		# ⇒ 逐骨局部坐标系与 M01 同构（`glb_joint_cmp.py` 实测逐关节静息旋转
		# 最大差 0.001815°，阳性对照 0.000000°、阴性对照 179.999993°）
		# ⇒ 27 条`Messer_Rig/Skeleton3D:<骨名>` 轨道路径天然全部解析得到。
		var skels := inst.find_children("*", "Skeleton3D", true, false)
		var players := inst.find_children("*", "AnimationPlayer", true, false)
		t.eq(skels.size(), 1,
			"%s 有 1 副骨架（相似变换贴自 M01 的 messer_rig_v1）" % p.display_name)
		t.eq(players.size(), 1,
			"★ %s 有 1 个 AnimationPlayer —— 主模型自带 fly 段，这是 27 段能摘到的前提（T13）"
				% p.display_name)
		t.eq(p.model_anim_files.size(), 27,
			"★ %s 挂着 27 段动作（与 M01 逐字同一份：保方向 ⇒ 局部坐标系同构）"
				% p.display_name)
		t.eq(p.model_anim_idle, "",
			"%s 的 model_anim_idle 为空串（不播飞行待机）" % p.display_name)
		inst.free()

	# 阳性对照：M01 走的是**同一套绑定成品**（三台现在同构）。
	var m01 := SuitProfile.by_id(SuitProfile.Id.MESSER_M01)
	t.eq(m01.model_anim_files.size(), 27,
		"阳性对照：梅萨M01（绑定成品）挂着 27 段动作 —— 证明上一条不是恒真")
	t.ok(SuitProfile.by_id(SuitProfile.Id.MESSER_CMD).model_anim_files
			== m01.model_anim_files,
		"★ 指挥官型的 27 段与 M01 **逐字相同**（复用，不是各导一份）")


## 尺寸口径。**这些数全部来自实测**，不是估的。
static func _size(t: T) -> void:
	# 实测（`tools/probe_model.tscn`，Godot 侧导入后的真实包围盒）：
	#   messer_cmd.glb : X 0.7462 | Y(高) **0.9756** | Z 0.7935 | 201 网格
	#   messer_f01.glb : X 0.5454 | Y(高) **0.9995** | Z 0.6675 | 182 网格
	#   messer_fly.glb : X 0.5220 | Y(高) **0.9995** | Z 0.7505 | 157 网格（对照）
	#
	# ⚠️ 一次实测踩坑值得记：**Blender 侧量带骨架的 glTF 包围盒不可信**。
	# 同一份 `messer_fly.glb`，Blender 量出 X 1.9021 / Y 2.0 / Z 2.0，
	# Godot 量出 0.5220 / 0.9995 / 0.7505 —— 差近 4 倍。
	# ⇒ `model_native_height` 的**真值来源只能是 Godot 探针**。
	var exp := {
		SuitProfile.Id.MESSER_CMD: [0.9756, 201],
		SuitProfile.Id.MESSER_F01: [0.9995, 182],
	}
	# 朝向的标尺：M01（老板看图确认过 90° 就是正的）。
	var m01 := SuitProfile.by_id(SuitProfile.Id.MESSER_M01)
	for id: int in exp:
		var p := SuitProfile.by_id(id)
		t.near(p.model_native_height, float(exp[id][0]), 0.0005,
			"%s 的 model_native_height = 实测量 %.4f" % [p.display_name, exp[id][0]])
		# 三台梅萨同档（都是 22 m 级量产机）。改这里要连着 `target_height` 一起改，
		# `FlightBody` 是按 `target_height / model_native_height` 缩放的。
		t.near(p.target_height, 22.0, 0.001,
			"%s 全高定 22.0 m（与梅萨M01 同档：都是同型量产机）" % p.display_name)
		t.gt(p.model_native_height, 0.5,
			"%s 的 native 高 ≈ 1 m（不是厘米级，也不是千米级）" % p.display_name)
		# ---- 朝向（`model_yaw_deg`）----
		#
		# ★★ 结论：**与 M01 同为 90°**。这里曾经走过两条弯路，两条都留作反面教材：
		#   ① 最初「三台梅萨**同型** ⇒ 同为 90°」—— 推理本身错了，但**结论碰巧对**
		#      （推理错在"同型 ⇒ 三份 Tripo 资产的偏航相同"；实测 M01 φ=+5.50°、
		#       本机/F01 φ≈+25.1°，三份各偏各的 —— 这条教训仍然成立）；
		#   ② 然后改成 `90 + φ`（115.10 / 115.15）—— **同一刀切了两次**：
		#      `transfer_rig_ms.py` 导出前已把脸绕 Z 转到 +X **烘进顶点**
		#      （`part_map.json` 自报 `"frame": {"forward":"+X","rotated":true}`），
		#      导出件的 φ 已经是 0 ⇒ 再加 25.1° 就是多转 ⇒ 老板 2026-09-30 真机：
		#      「现在是向左偏了」（N58 之前是「偏朝右」，**角度相同、方向相反** = 指纹）。
		#
		# 2026-09-30 实测（`_relay/tmp/yaw_recheck2.py`，纯 Python 解 glb 的骨架节点；
		# 量法 = hand_L/R 定侧向、Head−Hips 定竖直、RearWaist 定前后符号；
		# 证伪条 = **数据层**整体绕 Y 转 ±40/±12.5/±7.5/±25°，读数须精确跟变，全 OK）：
		#   M01 **+4.95°** / CMD **+4.95°** / F01 **+4.95°** ⇒ **两两差 0.00°**。
		# ⇒ 摆正生效、三台同向 ⇒ **三台用同一个 yaw**。断言直接写成"= M01"，
		#   这样"同型同朝向"这件事本身被钉住，且以后谁把摆正那一刀又加一遍会立刻红。
		t.near(p.model_yaw_deg, m01.model_yaw_deg, 0.001,
			"★ %s 的朝向修正 = M01 的 %.2f°（摆正后三台同向，不再各加 phi）"
				% [p.display_name, m01.model_yaw_deg])

	# ---- 两台新机的 native_height **不相同** ----
	# 这条不是废话：它们的 Y 跨度一个是 0.9756、一个是 0.9995。
	# ⚠️ 而 F01 的 0.9995 与 `messer_fly` **逐位相同**（纯属巧合）——
	# 所以"F01 可以照抄 fly 的 native_height"是**对的结果、错的理由**：
	# X / Z 差得很远（0.5454 vs 0.5220）。断言写成"两台新机互不相同"，
	# 而不是"F01 == fly"，正是为了不把这个巧合固化成契约。
	var nh_cmd := SuitProfile.by_id(SuitProfile.Id.MESSER_CMD).model_native_height
	var nh_f01 := SuitProfile.by_id(SuitProfile.Id.MESSER_F01).model_native_height
	t.not_ok(is_equal_approx(nh_cmd, nh_f01),
		"两台新机的 native_height 不同（%.4f vs %.4f）—— 各自量、别互相照抄"
			% [nh_cmd, nh_f01])

	# 三台梅萨的 native_height 至少要能区分出两台（别三台写成同一个数）
	var nhs: Array[float] = [SuitProfile.by_id(SuitProfile.Id.MESSER_M01).model_native_height,
		nh_cmd, nh_f01]
	t.gt(nhs.size(), 0, "三台梅萨的 native_height 都读得到")


## 阵营池 · 踏板 · 编制 —— **三处必须一致**（不一致时全都不报错）。
static func _pool(t: T) -> void:
	var mafty := BattleFormation.mafty()
	var fed := BattleFormation.federation()

	# ---- ① 池子里真有这两台，而且柯西仍是唯一的 ACE ----
	var pool := mafty.all_suits()
	t.eq(pool.size(), 4, "马夫蒂可选机体 4 台（柯西 ＋ 三台梅萨）")
	t.ok(pool.has(SuitProfile.Id.MESSER_CMD), "马夫蒂池含梅萨指挥官型")
	t.ok(pool.has(SuitProfile.Id.MESSER_F01), "马夫蒂池含梅萨F01型")
	t.ok(pool.has(SuitProfile.Id.MESSER_M01), "马夫蒂池仍含梅萨M01")
	t.ok(pool.has(SuitProfile.Id.XI), "马夫蒂池仍含柯西")
	t.eq(mafty.aces, [SuitProfile.Id.XI] as Array[int],
		"★ ACE 池**没有变**：柯西是马夫蒂唯一的 ACE（新机是量产机）")
	t.eq(mafty.mass_production,
		[SuitProfile.Id.MESSER_M01, SuitProfile.Id.MESSER_CMD,
			SuitProfile.Id.MESSER_F01] as Array[int],
		"★ 量产池 = M01 / 指挥官型 / F01型")
	t.eq(fed.all_suits().size(), 4, "联邦池包含三台ACE与古斯塔夫00")

	# ---- ② ★ 编制不许变 ----
	#
	# `lineup()` 里 AI 队友一律走 `r.mp()`，而 `mp()` 取 `mass_production[0]`。
	# ⇒ 加进池子**只影响玩家能选什么**，场上编制一格没变。
	# 这条要钉住，因为"池子变大"最容易被误读成"编制变大"。
	t.eq(mafty.mp(), SuitProfile.Id.MESSER_M01,
		"★ 编制里的量产机仍是 M01（`mp()` = mass_production[0]）—— 加池子不改编制")
	t.eq(mafty.ace(), SuitProfile.Id.XI, "编制补出来的 ACE 仍是柯西")
	t.eq(BattleFormation.unit_count_per_side(), 7,
		"每边仍是 7 台（3 编队 × 2 台 ＋ 1 ACE）")
	t.eq(BattleFormation.lineup(BattleFormation.Side.MAFTY, -1).size(), 7,
		"马夫蒂侧生成的名单仍是 7 台")
	t.eq(BattleFormation.lineup(BattleFormation.Side.MAFTY, SuitProfile.Id.MESSER_M01).size(), 7,
		"玩家选 M01 时名单仍是 7 台")
	t.eq(BattleFormation.lineup(BattleFormation.Side.MAFTY, SuitProfile.Id.MESSER_CMD).size(), 7,
		"玩家选指挥官型时名单仍是 7 台")
	t.eq(BattleFormation.lineup(BattleFormation.Side.MAFTY, SuitProfile.Id.MESSER_F01).size(), 7,
		"玩家选 F01型时名单仍是 7 台")

	# 玩家选新机时，**名单里真的有那一台，而且只有一台是玩家的**。
	for id: int in [SuitProfile.Id.MESSER_CMD, SuitProfile.Id.MESSER_F01]:
		var list := BattleFormation.lineup(BattleFormation.Side.MAFTY, id)
		var mine := 0
		var found := false
		for u: BattleFormation.Unit in list:
			if u.owner_is_player:
				mine += 1
				if u.suit == id:
					found = true
		t.eq(mine, 1, "选 id %d 时恰有 1 台归玩家开" % id)
		t.ok(found, "选 id %d 时玩家开的就是那一台（不是别的机体）" % id)

	# ---- ③ belongs_to：阵营归属的唯一判据 ----
	for id: int in [SuitProfile.Id.MESSER_CMD, SuitProfile.Id.MESSER_F01]:
		t.ok(BattleFormation.belongs_to(BattleFormation.Side.MAFTY, id),
			"id %d 属马夫蒂" % id)
		t.not_ok(BattleFormation.belongs_to(BattleFormation.Side.FEDERATION, id),
			"id %d **不**属联邦（跨阵营不会报错，只能靠断言）" % id)

	# ---- ④ ★★ 踏板：**逐台**量三处一致 ----
	#
	# `kind_for_suit()` 的兜底是 `Kind.KILCE`（联邦的板）——
	# 所以"新加一台马夫蒂机而忘了改它"表现为**这台机静默骑上联邦的板**。
	# 逐台量而不是点名两台新机：这样**以后**再加马夫蒂机也会被这条抓住。
	#
	# ⚠️ **2026-09-30（N62）：指挥官型单开第三种板（`Kind.MESSER_CMD`）。**
	# 它**仍在马夫蒂阵营池里**（所以阵营那几条不能动），但骑的不是马夫蒂那种板 ——
	# `mafty_*` 那套搭乘态模型里烤死的机体是**量产型 M01**，
	# 指挥官型骑上去会被画成量产型（机型与涂装都不对）。
	# ⇒ 这一节从"纯按阵营判"改成"**阵营逐台量 + 指挥官型单独钉**"。
	for id: int in mafty.all_suits():
		if id == SuitProfile.Id.MESSER_CMD:
			continue
		t.eq(FlightPedal.kind_for_suit(id), FlightPedal.Kind.MAFTY,
			"★ 马夫蒂池里的 id %d 骑**马夫蒂板**（%s）"
				% [id, SuitProfile.by_id(id).display_name])
	for id: int in fed.all_suits():
		t.eq(FlightPedal.kind_for_suit(id), FlightPedal.Kind.KILCE,
			"联邦池里的 id %d 骑**喀耳刻板**（%s）"
				% [id, SuitProfile.by_id(id).display_name])
	# 阳性对照：三种板**两两不同**（证明判据有区分力，不是"都在判同一个值"）
	t.not_ok(FlightPedal.Kind.MAFTY == FlightPedal.Kind.KILCE,
		"阳性对照：马夫蒂板 ≠ 喀耳刻板（判据有区分力）")
	t.not_ok(FlightPedal.Kind.MESSER_CMD == FlightPedal.Kind.MAFTY,
		"阳性对照：指挥官型板 ≠ 马夫蒂板（判据有区分力）")
	t.not_ok(FlightPedal.Kind.MESSER_CMD == FlightPedal.Kind.KILCE,
		"阳性对照：指挥官型板 ≠ 喀耳刻板（判据有区分力）")
	var cmd := SuitProfile.Id.MESSER_CMD
	var f01 := SuitProfile.Id.MESSER_F01
	t.eq(FlightPedal.kind_for_suit(cmd), FlightPedal.Kind.MESSER_CMD,
		"★ 梅萨指挥官型骑**指挥官型板**（板上烤的是它自己，不是量产型）")
	t.eq(FlightPedal.kind_for_suit(f01), FlightPedal.Kind.MAFTY,
		"梅萨F01型骑**马夫蒂板**（用户裁决：只给指挥官型开新板）")

	# ---- ④b 新板的**素材**真的接上了（不是接线但缺件）----
	#
	# `STATE_MODEL` 少一条只会静默回落成 `Vis.BOTH` 那条，
	# 表现是"某一种状态画错" ⇒ 三态逐条比，且**必须与马夫蒂那份不是同一个文件**。
	var P_CMD := FlightPedal.Kind.MESSER_CMD
	t.eq(FlightPedal.model_path_of(P_CMD, FlightPedal.Vis.BOTH),
		"res://assets/models/pedal_states/messer_cmd_both.glb",
		"指挥官型·两台都在 ⇒ messer_cmd_both.glb")
	t.eq(FlightPedal.model_path_of(P_CMD, FlightPedal.Vis.SLOT0_ONLY),
		"res://assets/models/pedal_states/messer_cmd_front.glb",
		"指挥官型·只剩一号机 ⇒ messer_cmd_front.glb")
	t.eq(FlightPedal.model_path_of(P_CMD, FlightPedal.Vis.SLOT1_ONLY),
		"res://assets/models/pedal_states/messer_cmd_back.glb",
		"指挥官型·只剩二号机 ⇒ messer_cmd_back.glb")
	t.not_ok(FlightPedal.model_path_of(P_CMD, FlightPedal.Vis.BOTH)
			== FlightPedal.model_path_of(FlightPedal.Kind.MAFTY, FlightPedal.Vis.BOTH),
		"★ 阳性对照：指挥官型的搭乘态模型**与马夫蒂那份不是同一个文件**")
	# 空板是**故意复用**马夫蒂那份（板本体逐件等价）—— 把它钉成"故意的"而不是疏漏
	t.eq(FlightPedal.model_path_of(P_CMD, FlightPedal.Vis.EMPTY),
		"res://assets/models/pedal_states/mafty_empty.glb",
		"指挥官型·空板 ⇒ 复用 mafty_empty（板本体同一块，故意共享）")

	# ---- ④c 尺寸口径：与马夫蒂**同板 ⇒ 那三张表必须逐项相同** ----
	#
	# ⚠️ 这四张表（EMPTY_NATIVE / LOADED_NATIVE / RIDER_NATIVE_H / STATE_RIDER_POS）
	# 决定了"板多大 / 人站哪儿"。它们是从**模型**里量出来的常数，
	# 新板只要哪一项抄错，表现就是"指挥官型的板突然比马夫蒂小一圈"
	# 或者"人悬空/陷进板里" —— 两种都不报错。
	t.near(FlightPedal.game_length_of(P_CMD), FlightPedal.game_length_of(FlightPedal.Kind.MAFTY),
		0.01, "★ 指挥官型板长 == 马夫蒂板长（同一块板）")
	t.near(FlightPedal.target_height_of(P_CMD, FlightPedal.Vis.EMPTY),
		FlightPedal.target_height_of(FlightPedal.Kind.MAFTY, FlightPedal.Vis.EMPTY),
		0.01, "空板厚度一致（否则下板的那一瞬间板会突然缩）")
	t.near(FlightPedal.target_height_of(P_CMD, FlightPedal.Vis.BOTH),
		FlightPedal.target_height_of(FlightPedal.Kind.MAFTY, FlightPedal.Vis.BOTH),
		0.01, "载人态厚度一致")
	# ⚠️ 不能写 `FlightPedal.slot_count()` —— 那是**实例方法**，静态调会 parse error。
	# 用 static 的 `slot_separation_m()` 代替：`STATE_RIDER_POS` 若被抄成同一份，
	# 两个挂位会重合、这个数变成 0（表现是"两台机叠在一起"）。
	t.gt(FlightPedal.slot_separation_m(P_CMD), 1.0,
		"★ 新板两个挂位之间真的有间距（同值抄错会变成 0 ⇒ 两台叠在一起）")
	t.near(FlightPedal.slot_separation_m(P_CMD),
		FlightPedal.slot_separation_m(FlightPedal.Kind.MAFTY), 0.01,
		"★ 挂位间距 == 马夫蒂（同一块板、同一套座次）")

	# ---- ⑤ 菜单：小队战按阵营列机体，所以"能选"= 进 `all_suits()` ----
	#
	# ⚠️ `MainMenu.suits_for_side()` 是**实例方法**（不能 `MainMenu.xxx()` 静态调，
	# 那样直接 parse error）⇒ 这里改成**扫实现体**：
	# 只要它取的是 `roster_of(side).all_suits()`，"进池子"与"菜单里能选到"
	# 就是**同一件事**，不需要把菜单实例化起来点一遍。
	var src := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	t.ok(src.contains("func suits_for_side(side: int) -> Array:"),
		"菜单有 `suits_for_side(side)` 这个入口")
	t.ok(src.contains("return BattleFormation.roster_of(side).all_suits()"),
		"★ 那一页的机体表**就是**阵营池（`roster_of(side).all_suits()`）"
			+ " ⇒ 「进池子」与「小队战里能选到」是同一件事")
	# 小队战确实走"按阵营过滤"这条路（否则机体页会去用那三台 ACE 的固定表）
	t.ok(src.contains("func side_filters_suits() -> bool:"),
		"菜单有 `side_filters_suits()`（决定机体页要不要按阵营过滤）")
	t.ok(src.contains("return squad_mode() or lan_mode()"),
		"★ 小队战（`squad_mode()`）**在**按阵营过滤的名单里 —— "
			+ "不然马夫蒂池子再长也影响不到那一页")

	# 那三台 ACE 的固定表（1v1 / 挑战 / 训练用）**不许**被顺手加进新机：
	# 老板这次说的是"**小队战**的马夫蒂"，不是"1v1 里也能开梅萨"。
	t.eq(MainMenu.SUITS.size(), 5,
		"★ 1v1 为5台ACE；梅萨量产机仍只进阵营池")
	t.ok(not MainMenu.SUITS.has(cmd), "1v1 表里**没有**指挥官型")
	t.ok(not MainMenu.SUITS.has(f01), "1v1 表里**没有**F01型")


## 真机接进去 —— **这是"导入游戏"这件事的行为判据**。
##
## 数据对不代表接得进去：`model_path` 写对、但模型缩放算错 / 锚点取不到，
## 在数据层一点都看不出来。所以这里真建一台 `FlightBody`。
static func _fly(t: T, host: Node) -> void:
	for id: int in [SuitProfile.Id.MESSER_CMD, SuitProfile.Id.MESSER_F01]:
		var p := SuitProfile.by_id(id)
		var body := FlightBody.new()
		body.name = "MesserProbe%d" % id
		body.profile = p
		body.use_placeholder = false
		body.flight_pitch_deg = 0.0
		host.add_child(body)
		body.set_physics_process(false)
		await host.get_tree().physics_frame
		await host.get_tree().physics_frame
		body.set_physics_process(false)

		t.ok(body.rig != null, "%s 挂着槽位骨架（提供炮口/喷口锚点）" % p.display_name)
		t.gt(body.rig.slot_names().size(), 50,
			"%s 的槽位数正常（%d 个）" % [p.display_name, body.rig.slot_names().size()])
		t.not_ok(body.rig.placeholder_visible(),
			"%s 的真模型到位了（占位体块已隐藏）" % p.display_name)

		# ★ 缩放口径：包围盒高度 = 设定全高（与 `suite_round` 同一套 ±2.5 口径）
		t.near(body.model_bounds.size.y, p.target_height, 2.5,
			"%s 的包围盒高 = 设定全高 %.0f m（实得 %.2f m）"
				% [p.display_name, p.target_height, body.model_bounds.size.y])
		t.gt(body.model_bounds.size.x, 1.0,
			"%s 的包围盒宽 > 1 m（不是被缩成一个小点）" % p.display_name)

		# ★ 炮口锚点要真的取得到 —— 这是"能打"的前提。
		# N58 起两台都**有骨架** ⇒ 走 `_collect_muzzles()` 的第一条路：
		# `anchor_from_model()` 为真（它读 `_model_skel`）⇒ 锚点从**模型骨架**取。
		# 那 13 根锚点骨是相似变换贴来的（`muzzle_L/R` 同在右拳、父级 `LowerArm.R`），
		# 与 M01 同构 ⇒ 口的位置与 M01 同档，不再依赖占位骨架的兜底。
		t.gt(body._muzzle_local.size(), 0,
			"%s 取到了 %d 个炮口（锚点从模型骨架取）"
				% [p.display_name, body._muzzle_local.size()])

		# ★ 有骨架 = **会摆动作**（T13 那条边界的另一半）
		#（见 `FlightBody._release_model_anim()`：留 null 会让早退路径崩溃）。
		t.ok(body._model_skel != null,
			"★ %s 的模型骨架非空（锚点走模型骨架那条路）" % p.display_name)
		t.eq(body.model_anim.ready, true,
			"★ %s 的动画器已就绪（有 AnimationPlayer ⇒ 27 段动作全部摘得到）"
				% p.display_name)
		t.ok(body.model_fsm != null,
			"%s 的状态机不为 null（契约：哑机也要有）" % p.display_name)

		# 飞行参数按 profile 配好了（"能飞"而不是"建出来了个摆设"）
		t.gt(body.fm.max_speed, 0.0, "%s 巡航上限 > 0（%.1f m/s）"
			% [p.display_name, body.fm.max_speed])
		t.near(body.fm.max_speed, p.player_top_speed(), 0.5,
			"%s 的巡航上限走 `player_top_speed()`（%s 的速度系数 %.2f）"
				% [p.display_name, p.display_name, p.speed_scale])

		body.queue_free()
		await host.get_tree().process_frame

	# ---- 三台梅萨同规格（派生自 `messer_m01()` 的**不变量**）----
	#
	# 这是"三台是同型机的不同变体"这句设定的**可验证形式**：
	# 调平衡时改 M01 一处，三台一起走。
	var base := SuitProfile.by_id(SuitProfile.Id.MESSER_M01)
	for id: int in [SuitProfile.Id.MESSER_CMD, SuitProfile.Id.MESSER_F01]:
		var q := SuitProfile.by_id(id)
		t.near(q.hull_hp, base.hull_hp, 0.001, "%s 装甲值 = M01" % q.display_name)
		t.near(q.ifield_hp, base.ifield_hp, 0.001, "%s I 力场 = M01" % q.display_name)
		t.near(q.shield_reduction, base.shield_reduction, 0.001,
			"%s 举盾减伤 = M01" % q.display_name)
		t.near(q.speed_scale, base.speed_scale, 0.001, "%s 速度系数 = M01" % q.display_name)
		t.near(q.turn_scale, base.turn_scale, 0.001, "%s 转向系数 = M01" % q.display_name)
		t.near(q.rifle_damage, base.rifle_damage, 0.001, "%s 步枪伤害 = M01" % q.display_name)
		t.eq(q.rifle_ammo_infinite, base.rifle_ammo_infinite,
			"%s 步枪无限弹 = M01" % q.display_name)
		t.eq(q.has_jet_gauge, base.has_jet_gauge, "%s 有燃料槽 = M01" % q.display_name)
		t.eq(q.has_missiles, base.has_missiles, "%s 无导弹 = M01" % q.display_name)
		t.eq(q.funnel_count, base.funnel_count, "%s 无浮游导弹 = M01" % q.display_name)
		t.eq(q.engine_sound, base.engine_sound, "%s 引擎音沿用 = M01" % q.display_name)

	# ---- 但**涂装色必须三台不同**（卡片/HUD 靠它区分同一池子里的三台梅萨）----
	var accents: Dictionary = {}
	for id: int in [SuitProfile.Id.MESSER_M01, SuitProfile.Id.MESSER_CMD,
			SuitProfile.Id.MESSER_F01]:
		var q := SuitProfile.by_id(id)
		t.not_ok(accents.has(q.accent), "★ %s 的强调色与前面两台不同（%s）"
			% [q.display_name, str(q.accent)])
		accents[q.accent] = id
	t.eq(accents.size(), 3, "三台梅萨三色（供卡片与 HUD 区分）")
