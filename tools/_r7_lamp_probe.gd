extends Node
## 读数探针：**路灯实例数 + 灯亮不亮**（从**建好的场景**读回来）。
##
## ⚠️⚠️ 2026-09-28（B4 之后）**整篇重写**。原版是"**逐点复刻**
## `_build_city_street_lamps()` 的走法（同一套判据、同一个起点相位）"——
## 那在 B4 之后就成了**第二份真源**：实现已改成
## 「消费 `_city_dry_spans`（C1 段内裁剪的产物）＋ 两侧各一排」，
## 而复刻本还在自己扫整条格线、单排、没有半径门之外的任何 C1 语义
## ⇒ 它给出的数**已经与真正建出来的灯无关**，而且**不会报错**（数字看着照样合理）。
## ⇒ 现在只做两件事：**建城** → **数 `MultiMesh.instance_count`**。
##   数字对不上时，只可能是"实现变了"，不可能"复刻没跟上"。
##
## ## 读什么（每条都是"用户能看见的那件事"的机械表达）
## | # | 量 | 为什么 |
## |---|---|---|
## | 1 | `CityLampPoles` 的实例数 | 灯**杆**（用户原话："路灯灯柱得建"） |
## | 2 | `CityStreetLights` 的实例数 | 灯**头**（每根杆一个） |
## | 3 | 灯头材质的 `emission_enabled` | **"但是灯不亮"** —— 这一条就是它的机械表达：<br>`POSTS_ONLY` ⇒ **false**；`FULL` ⇒ **true** |
## | 4 | 杆/头是否**一一对应** | 两个 MultiMesh 必须同长（只有头 ⇒ 空中的光点；只有杆 ⇒ 暗点） |
## | 5 | 是不是**两侧各一排** | 灯到所属格线的横向距离应当有两个值（`±off`），**不再是 0**（旧版灯压在路中心线上） |
##
## 可 `--headless`：只读 `instance_count` / `material_override` 这些**属性**，
## 不读变换矩阵 —— dummy 渲染器下回读全零的是 `get_instance_transform()`。
##（第 5 条要读变换 ⇒ 单独标了 `--headless` 下会退化，见 `_sides()`。）
##
##   godot --headless --path <工程> res://tools/_r7_lamp_probe.tscn

var _w: WorldBuilder


func _ready() -> void:
	_w = WorldBuilder.new()
	add_child(_w)
	await get_tree().physics_frame
	print("==== 路灯：从建好的场景读回来 ====")
	print("  （基线：奥恩贝利 = 死城但**要建杆** ⇒ POSTS_ONLY；达沃 = FULL）")
	print("")
	for m: MapDef in [MapDef.oenbelli(), MapDef.davao()]:
		_w.apply_map(m)
		await get_tree().physics_frame
		await get_tree().physics_frame
		_report(m)
	print("")
	print("==== 判据 ====")
	print("  ① 两城都必须有杆、有头（`city_lights != NONE`）")
	print("  ② 奥恩贝利：emission_enabled = **false**（建了但不亮）")
	print("  ③ 达沃：emission_enabled = **true**")
	print("  ④ poles == heads（一一对应）")
	get_tree().quit()


func _report(m: MapDef) -> void:
	var poles := _mmi("CityLampPoles")
	var heads := _mmi("CityStreetLights")
	var np := 0
	var nh := 0
	if poles != null and poles.multimesh != null:
		np = poles.multimesh.instance_count
	if heads != null and heads.multimesh != null:
		nh = heads.multimesh.instance_count
	var em := "（无节点）"
	if heads != null and heads.material_override is StandardMaterial3D:
		var sm := heads.material_override as StandardMaterial3D
		em = ("**true**（亮）" if sm.emission_enabled else "**false**（不亮）")
	print("[%s]  city_lights = %s" % [m.name_cn, _mode_name(m.city_lights)])
	print("      杆 %d / 头 %d   ⇒ %s" % [np, nh,
		("一一对应 ✓" if np == nh else "**不相等 ✗**")])
	print("      灯头材质 emission_enabled = %s" % em)
	print("      两侧偏移：%s" % _sides(heads))
	print("")


## 逐盏核"**两侧各一排**"，而且核到**档位**上。
##
## ⚠️ 第一版这里写的是 `min(|x−最近x格线|, |z−最近z格线|)` —— **错的**：
## 一盏灯只**属于一条**格线，另一轴上的位置是**沿线的任意点**
## ⇒ 那个 `min` 拿噪声去和真值比大小，读数什么也证明不了
##（实测第一版只能给出 `100 m ×136 / 30 m ×264` 这种没法解释的混合）。
##
## 正确判法：一盏灯要么在"**x = gx·格距**"那条线上（则该灯 `|dx|` 必须**正好**等于
## 档位 `gx` 对应的偏移），要么在"**z = gz·格距**"那条线上（则 `|dz|` 必须正好等于
## 档位 `gz` 对应的偏移）。两条候选里**恰有一条**应当命中。
## 命中的那条顺便给出**符号**（`+off` / `−off`）⇒ 两侧各有灯才算"两侧各一排"。
func _sides(heads: MultiMeshInstance3D) -> String:
	if heads == null or heads.multimesh == null:
		return "（无节点）"
	var cb := WorldBuilder.ARENA_RADIUS / float(WorldBuilder.CITY_GRID)
	var widths: Array[float] = [WorldBuilder.CITY_ROAD_W_TRUNK,
		WorldBuilder.CITY_ROAD_W_ARTERIAL, WorldBuilder.CITY_ROAD_W_LOCAL]
	var offs: Array[float] = []
	for w: float in widths:
		offs.append(maxf(w * 0.5 - 30.0, 20.0))
	var hist := {}
	var amb := 0
	var miss := 0
	var n := heads.multimesh.instance_count
	for i in n:
		var p := heads.multimesh.get_instance_transform(i).origin
		var gx := roundi(p.x / cb)
		var gz := roundi(p.z / cb)
		var dx := p.x - float(gx) * cb
		var dz := p.z - float(gz) * cb
		# 候选 A：灯在 x = gx·cb 这条（沿 Z 走）线上 ⇒ 档位由 gx 定
		var ok_a := absf(absf(dx) - offs[_tier(gx)]) < 1.0
		# 候选 B：灯在 z = gz·cb 这条（沿 X 走）线上 ⇒ 档位由 gz 定
		var ok_b := absf(absf(dz) - offs[_tier(gz)]) < 1.0
		if not ok_a and not ok_b:
			miss += 1
			continue
		if ok_a and ok_b:
			amb += 1
			continue
		var t := _tier(gx) if ok_a else _tier(gz)
		var sg := (1.0 if dx > 0.0 else -1.0) if ok_a else (1.0 if dz > 0.0 else -1.0)
		var key := "%s 偏 %+.0f m" % [_tier_name(t), offs[t] * sg]
		hist[key] = int(hist.get(key, 0)) + 1
	var keys := hist.keys()
	keys.sort()
	var out := "\n        共 %d 盏；命中单一候选 %d 盏" % [n, n - amb - miss]
	for k: Variant in keys:
		out += "\n          %s  ×%d" % [str(k), int(hist[k])]
	if amb > 0:
		out += "\n        ⚠️ 两条候选同时命中 %d 盏（x 线与 z 线在这一点上无法区分）" % amb
	if miss > 0:
		out += "\n        ⚠️⚠️ **两条都不命中 %d 盏** ⇒ 有灯既不在任何格线的墙属偏移上" % miss
	return out


## 格线档位：`gi == 0` 主干 / `gi % 5 == 0` 次干 / 其余支路
##（与 `_build_city_street_infra()` 的 C3 判据同源）。
func _tier(gi: int) -> int:
	if gi == 0:
		return 0
	return 1 if gi % 5 == 0 else 2


func _tier_name(t: int) -> String:
	match t:
		0:
			return "主干"
		1:
			return "次干"
	return "支路"


func _mmi(n: String) -> MultiMeshInstance3D:
	return _w._terrain_root.get_node_or_null(n) as MultiMeshInstance3D


func _mode_name(v: int) -> String:
	match v:
		MapDef.CityLights.NONE:
			return "NONE"
		MapDef.CityLights.POSTS_ONLY:
			return "POSTS_ONLY"
		MapDef.CityLights.FULL:
			return "FULL"
	return "?%d" % v
