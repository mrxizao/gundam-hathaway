class_name SuiteSceneGain
extends RefCounted
## 场景亮度增益 —— 本工程"环境亮度"的唯一旋钮。
##
## ⚠️ 命名按**主题**，不占轮次号 —— 见 `test_runner.gd` 注册表里的红字：
## 本仓库有并行会话，两边都按轮次占号时撞过一次，一个套件被同名文件**整个覆盖**
## 而 runner 照样绿。
##
## ## 这一套钉的是什么
##
## 这个常量身上压着**两次方向相反的需求**，所以它必须被钉住：
##
##   · 轮 12：「玩家机体明暗度和现在保持一致，场景明暗度更亮一点」⇒ `1.0 → 1.40`
##   · 轮 23：「环境亮度压暗30%」⇒ `1.40 → 0.98`（= 1.40 × 0.70）
##
## 两次都作用在**同一个数**上 —— 这本身就是一条结论：本工程"场景亮度"的入口
## 只有这一个。这里把它钉死，是为了让第三次需求不会顺手去开**第二个**入口
##（比如另一个场景专用的 `_env.tonemap_exposure` 档 —— 那是全屏量，
## 会把机体一起拖下水，与用户"机体不动"的要求直接冲突）。
##
## ## 三个必须成立的不变量
##
##   1. **`_sg()` 是唯一乘法处**（整个 `scripts/` 下只有 `world_builder.gd` 出现它），
##      而它的落点**全部赋给 `albedo*`** —— 于是"只乘 albedo、不碰 emission"
##      这条（路灯罩 / 灯箱 / 立像背光都靠它）是可断言的，不靠注释自觉。
##      ★ 剧情模式轮 B2 从 **6 → 7**：低地球轨道的人造物走 `_space_material()`，
##      它也是 `sm.albedo_color = _sg(color)` —— 轨道上的碎片 / 残骸 / 运输仓 / 卫星
##      **必须**跟着场景增益一起动，否则它们是"一张与全场景无关的贴纸"。
##   2. **机体 / 敌人逐像素不变**：它们是 GLB 自带材质，**根本不经过 `_sg()`**。
##      需求之所以成立正是靠这条边界 —— 所以这里扫的是"机体脚本里一个 `_sg(` 都没有"。
##   3. **海面挂在同一个常量上**（`SEA_GAIN_BOOST` 是倍率而非独立值）⇒
##      "整场景一起压暗"只动一个数，不会出现两份真源各自漂移。
##
## ⚠️ 与 `suite_gfx_ledger` 一样：这一套**测不了"好不好看"**
##（无头环境 RenderingServer 是 dummy，一个像素都不产生）。
## 这里钉的是数值、接线与源码结构；"屏幕上到底暗了多少"的判据在
## `tests/pixprobe.tscn` 的真渲染 A/B（`--scenegain=1.4` vs `--scenegain=0.98`）。

const WB_SRC := "res://scripts/world/world_builder.gd"
const PROBE_SRC := "res://tests/pixprobe.gd"
const SCRIPTS_DIR := "res://scripts"

## 轮 12 定的档（历史依据，别删）：「场景明暗度更亮一点」。
const R12_GAIN := 1.40
## 轮 23 的压暗系数。
const DARKEN := 0.70
## 压暗之后的目标值。
const R23_GAIN := 0.98
## 海面在场景增益之上的补偿倍率（本轮**不动**它）。
const SEA_BOOST := 1.80
## `_sg()` 的落点数。改动这个数必须是有意的 —— 见 `_struct()`。
##
## 6 = 地表远景地坪 / 沙漠树 / 通用方块 / 立面 shader tint / 岩柱（沙漠巨岩）/ 海蚀柱；
## ★ 第 7 个是剧情模式轮 B2 加的：**轨道图的人造物**（`_space_material()`）。
##   ⇒ 本工程落点数**唯一一次**变化就是这一笔 **6 → 7**（与上面「三、不变量」第 1 条同一笔账）。
##
## ⚠️ 2026-09-30（轮 43）更正：这里**曾经写成 8**，并断言「第 8 个是 09-30 00:26 新加的
##   `_add_sea_stack()`（海蚀柱）」。**那句话是错的**。拿四份历史副本对账，口径与
##   `_struct()` 逐字一致（先剥注释、再数含 `_sg(` 的行），逐份读数：
##
##   | 副本 | 日期 | 落点数 | 组成 |
##   |---|---|---|---|
##   | `world_builder.gd.r23pre` | 09-26 | 6 | **已含 `_add_sea_stack`** |
##   | `r37/world_builder.gd` | 09-28 | 6 | **已含 `_add_sea_stack`** |
##   | `leo_earth_r43c/world_builder.gd` | 09-29 17:03 | 7 | 6 + `_space_material` |
##   | 当前工程 | 09-30 | 7 | 同一组 7 个函数，逐字不变 |
##
##   ⇒ **海蚀柱从 09-26 起就在那 6 处里**，从来不是「第 8 个」。上游 `world_builder.gd`
##   自己的文档（`## ## 7 个落点`）与上面「三、不变量」第 1 条也都写着 7 —— 只有这一行在说 8。
##
## ⚠️ 加一个落点**不是「顺手多一处」**：它意味着有一类场景件过去**不跟着压暗**。
## 红在这里 = 计数该更新，但**先照上表对账再改数**（别一红就顺着红的方向调数）；
## 红在下面「落点没写在 albedo 上」= 真的写错了地方。
const SPOTS := 7
## 读**颜色分量**时用的容差。理由见 `_fn()` 顶部那段。
const CTOL := 1e-6

const DEMAND := "SceneGain / 需求：场景压暗 30%（轮 23）"
const WIRE := "SceneGain / 默认值与海面挂靠"
const FN := "SceneGain / _sg() 的行为"
const STRUCT := "SceneGain / 源码结构（唯一乘法处 · 机体不在其中）"
const KNOB := "SceneGain / 探针旋钮（A/B 可复算）"


static func run(t: T) -> void:
	t.suite(DEMAND)
	_demand(t)
	t.suite(WIRE)
	_wire(t)
	t.suite(FN)
	_fn(t)
	t.suite(STRUCT)
	_struct(t)
	t.suite(KNOB)
	_knob(t)


# ------------------------------------------------------------- 需求本身

static func _demand(t: T) -> void:
	t.near(WorldBuilder.SCENE_GAIN, R23_GAIN, 1e-12,
		"SCENE_GAIN = 0.98（轮 23「环境亮度压暗30%」）")
	# ⚠️ 用 near 而不是 eq：`1.40 * 0.70` 在 IEEE754 下**不保证**逐位等于字面量
	# `0.98`。算式要能追溯，但别拿它当逐位判据。
	t.near(WorldBuilder.SCENE_GAIN, R12_GAIN * DARKEN, 1e-9,
		"可追溯：1.40 × 0.70（轮 12 的档 × 压暗系数）")
	t.lt(WorldBuilder.SCENE_GAIN, 1.0, "方向是**压暗**（< 1.0）")
	t.lt(WorldBuilder.SCENE_GAIN, R12_GAIN, "比轮 12 的 1.40 更暗")
	# 1.40 → 0.98 恰好穿过 1.0：说明这条需求是把一个"提亮档"整个撤销并再压一点，
	# 而不是在提亮的基础上继续加码。这个关系值得留一条断言，因为它解释了
	# 为什么"压暗 30%"不是 -30% 于某个更大的基数。
	t.gt(R12_GAIN, 1.0, "轮 12 那一档是提亮（> 1.0）")
	t.lt(R23_GAIN, 1.0, "轮 23 这一档是压暗（< 1.0）")


# ------------------------------------------------------------- 接线

static func _wire(t: T) -> void:
	var w := WorldBuilder.new()
	t.near(w.scene_gain, WorldBuilder.SCENE_GAIN, 1e-12,
		"`scene_gain` 的默认值就是常量（没有第二处真源）")
	t.near(w.sea_boost, WorldBuilder.SEA_GAIN_BOOST, 1e-12,
		"`sea_boost` 的默认值就是常量")
	t.near(WorldBuilder.SEA_GAIN_BOOST, SEA_BOOST, 1e-12,
		"海面倍率仍是 1.80 —— 本轮**不动它**（它是挂在场景增益上的倍率，不是独立档）")
	# 海面最终拿到的是**乘积**（`_ocean_mat.set_shader_parameter("scene_gain", scene_gain * sea_boost)`）：
	# 轮 12 = 2.52，轮 23 = 1.764。海面**自动**跟着压暗，不需要第二处改动。
	t.near(w.scene_gain * w.sea_boost, R23_GAIN * SEA_BOOST, 1e-9,
		"海面最终倍率 = 0.98 × 1.80 = 1.764（挂了同一个常量 ⇒ 自动跟着压）")
	t.near(R12_GAIN * SEA_BOOST, 2.52, 1e-9, "（对照）轮 12 时海面是 2.52")
	t.lt(w.scene_gain * w.sea_boost, R12_GAIN * SEA_BOOST, "海面也一起压暗了")
	w.free()


# ------------------------------------------------------------- _sg() 的行为

static func _fn(t: T) -> void:
	# ⚠️⚠️ **为什么容差是 `CTOL`（1e-6）而不是 1e-9** —— 这条第一版就踩了，8 条红：
	#
	# `Color` 的分量是 **float32**，而 GDScript 的 `float` 是 **float64**。
	# 于是"用 float64 字面量构造的 `Color`"读回来必然带一点误差：
	# 实测 `0.98` 存进 `Color.r` 再读出来是 `0.98000001907348632812`
	#（相对误差 ≈ 1.2e-7 —— 正是 float32 在 1.0 附近的精度）。
	#
	# 后果：`t.near(0.98, 0.98, 1e-9)` **判 FAIL**，而它打印出来是
	# `got=0.9800 want=0.9800 ±0.0000` —— **看上去两边是同一个数**。
	# 我本来是把 1e-9 当"宽松"给的，它却把一个**完全正确**的乘法判成了错。
	# 1e-6 远大于 float32 的精度、又远小于任何有意义的差异 ⇒ 这个量级才对。
	var w := WorldBuilder.new()

	# ---- 默认档（0.98）----
	var c := w._sg(Color(1.0, 1.0, 1.0, 0.5))
	t.near(c.r, WorldBuilder.SCENE_GAIN, CTOL, "_sg(白).r = 增益")
	t.near(c.g, WorldBuilder.SCENE_GAIN, CTOL, "_sg(白).g = 增益")
	t.near(c.b, WorldBuilder.SCENE_GAIN, CTOL, "_sg(白).b = 增益")
	# ⚠️ alpha **不进乘法**：它管的是不透明度，与"明暗"是两件事。
	# 把 alpha 也乘上去会让半透明的场景件（树冠 / 立面装饰）一起变透明 —— 那是另一个 bug。
	t.near(c.a, 0.5, CTOL, "alpha 原样保留（_sg 只动 albedo 三通道）")

	# ---- 单位增益走短路分支 ----
	w.scene_gain = 1.0
	var same := w._sg(Color(0.3, 0.4, 0.5, 0.9))
	t.near(same.r, 0.3, CTOL, "gain = 1.0 时 r 原样（短路分支）")
	t.near(same.g, 0.4, CTOL, "gain = 1.0 时 g 原样")
	t.near(same.b, 0.5, CTOL, "gain = 1.0 时 b 原样")

	# ---- 单调：增益越大越亮 ----
	w.scene_gain = R23_GAIN
	var dark := w._sg(Color(1, 1, 1)).r
	w.scene_gain = R12_GAIN
	var bright := w._sg(Color(1, 1, 1)).r
	t.gt(bright, dark, "增益越大越亮（单调）")
	t.near(bright, R12_GAIN, CTOL, "1.40 档下白仍是 1.40")
	# 0.98 档下白色的 r/g/b 都 < 1 ⇒ 纯白场景件被压到白以下（正是"压暗"的本体）
	t.lt(dark, 1.0, "0.98 档下纯白被压到 1.0 以下")

	# ---- 任意增益都是精确乘法（不是插值、不是查表）----
	w.scene_gain = 0.5
	t.near(w._sg(Color(0.8, 0.6, 0.4)).r, 0.4, CTOL, "0.5 档：0.8 × 0.5 = 0.4")
	t.near(w._sg(Color(0.8, 0.6, 0.4)).b, 0.2, CTOL, "0.5 档：0.4 × 0.5 = 0.2")
	w.free()


# ------------------------------------------------------------- 源码结构

static func _struct(t: T) -> void:
	var code := _strip_comments(_src(WB_SRC))
	t.gt(code.length(), 1000, "读到 world_builder.gd 的代码（剥注释后）")

	# ---- ① 唯一乘法处：整个 scripts/ 下只有 world_builder.gd 出现 `_sg(` ----
	var owners := []
	for p: String in _gd_files(SCRIPTS_DIR):
		if _strip_comments(_src(p)).contains("_sg("):
			owners.append(p)
	t.eq(owners.size(), 1, "`_sg(` 在 scripts/ 下只出现于一个文件（实际 %d 个）" % owners.size())
	t.ok(owners.has(WB_SRC), "那一个文件就是 world_builder.gd")
	# ⚠️ 这条断言的真正含义：**机体 / 敌人 / 飞行脚本里一个 `_sg(` 都没有**。
	# 它们读的是 GLB 自带材质，压根不经过这里 —— 需求「机体明暗不动」靠的就是这条边界。
	# 若哪天有人把增益接到机体上，这一条会红，而画面只会"机体也变暗了"（不报错）。
	t.ok(not _strip_comments(_src("res://scripts/flight/flight_body.gd")).contains("_sg("),
		"机体飞行脚本里没有 `_sg(`（机体是 GLB 材质，不经场景增益）")

	# ---- ② 落点数 ----
	var spots := 0
	for line in code.split("\n"):
		var s := String(line)
		if s.contains("_sg(") and not s.strip_edges().begins_with("func "):
			spots += 1
	t.eq(spots, SPOTS, "落点数 = %d（漏一处 ⇒ 那类场景件**不跟着压暗**，且不报错）" % SPOTS)

	# ---- ③ 每一处落点都赋给 albedo（= 只乘 albedo、不碰 emission）----
	var albedo_only := true
	for line in code.split("\n"):
		var s := String(line)
		if s.contains("_sg(") and not s.strip_edges().begins_with("func "):
			if not s.contains("albedo"):
				albedo_only = false
				t.ok(false, "落点没有写在 albedo 上：%s" % s.strip_edges())
	t.ok(albedo_only,
		"%d 个落点全部赋给 `albedo_*` —— 自发光（路灯罩 / 灯箱 / 立像背光）不跟着压，它们**是光源**"
			% SPOTS)

	# ---- ④ 函数体：短路 + 三次乘法 + alpha 不参与 ----
	var body := _func_body(code, "func _sg(")
	t.gt(body.length(), 20, "取到 _sg() 的函数体")
	t.ok(body.contains("is_equal_approx(scene_gain, 1.0)"),
		"有 gain = 1.0 的短路分支（零回归要靠它逐位成立）")
	t.eq(body.count("scene_gain"), 4, "函数体里 scene_gain 出现 4 次（1 次判等 + 3 次乘法）")
	t.ok(body.contains("c.a"), "alpha 是原样带过去的（`..., c.a)`）")
	t.ok(not body.contains("c.a *"), "alpha 没有被乘（否则半透明场景件会一起变透明）")


# ------------------------------------------------------------- 探针旋钮

static func _knob(t: T) -> void:
	var px := _strip_comments(_src(PROBE_SRC))
	t.gt(px.length(), 1000, "读到 pixprobe.gd 的代码（剥注释后）")
	t.ok(px.contains("\"--scenegain\""), "探针认识 `--scenegain`")
	t.ok(px.contains("\"--seaboost\""), "探针认识 `--seaboost`")
	t.ok(px.contains("world.scene_gain = sg"), "`--scenegain` 灌的是 `world.scene_gain`")
	t.ok(px.contains("world.sea_boost = sb"), "`--seaboost` 灌的是 `world.sea_boost`")
	# ⚠️ **注入时机**：材质是在 `apply_map()` 里把颜色算死的 ⇒ 旋钮必须在**建图之前**注入。
	# 放在 `_apply_overrides()`（建图之后）的表现是**画面纹丝不动、也不报错**，
	# 会被读成"这一项没有效果"。这里用"注入行出现在开图那一行之前"来钉它。
	var i_inject := px.find("world.scene_gain = sg")
	var i_start := px.find("_main._on_start_match(")
	t.gt(i_inject, 0, "找到注入行")
	t.gt(i_start, 0, "找到开图那一行")
	t.ok(i_inject < i_start,
		"注入在开图**之前**（建完图再改不生效：材质已经把颜色算死了）")
	# conditions 里必须记 —— 与 `shot_gain` 逐字同一个道理：
	# 一张"场景 ×1.4"与一张"×0.98"的图整帧均值差着一大截，
	# 不记的话后人会把"这一轮的压暗"读成"某一轮改动把画面弄暗了"。
	t.ok(px.contains("\"scene_gain\":"), "conditions 里记了 `scene_gain`（A/B 可复算）")
	t.ok(px.contains("\"sea_boost\":"), "conditions 里记了 `sea_boost`（海面是乘积，缺它复算不出）")


# ------------------------------------------------------------- 源码辅助

static func _src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


## 去掉 `#` 之后的注释（本工程没有"字符串里带 #"的写法）。
static func _strip_comments(src: String) -> String:
	var out := ""
	for line in src.split("\n"):
		var l := String(line)
		var i := l.find("#")
		if i >= 0:
			l = l.substr(0, i)
		out += l + "\n"
	return out


## 取 `head` 之后到**同层级下一个函数**之间的正文（见 `suite_gfx_ledger._func_body()`）。
static func _func_body(src: String, head: String) -> String:
	var i := src.find(head)
	if i < 0:
		return ""
	var rest := src.substr(i + head.length())
	var out := ""
	var started := false
	for l in rest.split("\n"):
		var s := String(l)
		if s.begins_with("func "):
			break
		if started and s.length() > 0 and s[0] != "\t" and s[0] != " ":
			break
		started = true
		out += s + "\n"
	return out


## 递归收集一个目录下的所有 `.gd`（跳过隐藏目录）。
static func _gd_files(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		var full := dir_path.path_join(n)
		if d.current_is_dir():
			if not n.begins_with("."):
				out.append_array(_gd_files(full))
		elif n.ends_with(".gd"):
			out.append(full)
		n = d.get_next()
	d.list_dir_end()
	return out
