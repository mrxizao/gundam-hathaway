class_name SuiteMissionRating
extends RefCounted
## 任务评价（S·A·B·C）+ 波次计时。
##
## 这一批最想防的是**"评价看起来有、其实没生效"**：
## 综合分是三项加权，任何一项的权重被改成 0，画面上照样有个字母在跳。
## 所以这里不只断言"等级对不对"，还断言**三项权重各自都真的在动**
## （第 5 节那三条差值）—— 沿用 §4.9.4 的教训：参数在动、画面不动是最难查的错。

const RATING_SRC := "res://scripts/data/mission_rating.gd"
const HUD_SRC := "res://scripts/ui/hud.gd"
const GAME_SRC := "res://scripts/autoload/game.gd"
const MAIN_SRC := "res://scripts/main.gd"

## 评价两行的基线（相对 `result_layout` 的 title_y）。
## 与 `hud._draw_result_rating()` 里的两个数必须一致 —— 改了一处忘了另一处，
## 表现是"评价压在栏目框上"，而这种错在 headless 里只有靠这条断言抓得到。
const RATING_LINE1 := 118.0
const RATING_LINE2 := 140.0
## 提示行字号（hud 里是 22），算"内容有没有被挤出屏幕"要用。
const HINT_FS := 22.0


static func run(t, _host) -> void:
	_weights(t)
	_grades(t)
	_parts(t)
	_par(t)
	_progress(t)
	_no_grade_on_loss(t)
	_bounds(t)
	_wiring(t)
	_layout(t)


# ---------------------------------------------------------------- 1. 三项权重

## 权重都是活的：**任何一项被改成 0，这里立刻红**。
##
## 做法是把"只有这一项变了"的两份输入拿来做差：
##   战果 100/0 差 45.0 · 存续 100/0 差 35.0 · 效率 100/0 差 20.0
## 直接断言"综合分 == 公式"是没用的 —— 那只是把代码抄一遍。
static func _weights(t) -> void:
	t.suite("任务评价 / 三项权重都真的在动")
	t.near(MissionRating.W_OBJECTIVE + MissionRating.W_SURVIVAL + MissionRating.W_TEMPO,
		1.0, 0.001, "三项权重之和 = 1.0")
	t.gt(MissionRating.W_OBJECTIVE, MissionRating.W_SURVIVAL, "战果权重 > 存续（完成度优先）")
	t.gt(MissionRating.W_SURVIVAL, MissionRating.W_TEMPO, "存续权重 > 效率（活着比快重要）")

	var all := _st(1, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
	var no_obj := _st(0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
	var no_svv := _st(1, 0.0, 0.0, 100.0, 1.0, 0.0, 0.0)
	var no_tmp := _st(1, 1.0, 0.0, 0.0, 1.0e6, 0.0, 0.0)

	var a := MissionRating.evaluate(all)
	var b := MissionRating.evaluate(no_obj)
	var c := MissionRating.evaluate(no_svv)
	var d := MissionRating.evaluate(no_tmp)

	t.near(float(a["score"]) - float(b["score"]),
		MissionRating.W_OBJECTIVE * 100.0, 0.01, "战果项权重 = 0.45（去掉它掉 45 分）")
	t.near(float(a["score"]) - float(c["score"]),
		MissionRating.W_SURVIVAL * 100.0, 0.01, "存续项权重 = 0.35（去掉它掉 35 分）")
	t.near(float(a["score"]) - float(d["score"]),
		MissionRating.W_TEMPO * 100.0, 0.01, "效率项权重 = 0.20（去掉它掉 20 分）")
	t.near(float(a["score"]), 100.0, 0.01, "三项满分 → 综合 100")


# ---------------------------------------------------------------- 2. 等级门限

static func _grades(t) -> void:
	t.suite("任务评价 / 等级门限")
	t.eq(MissionRating.grade_of(100.0), "S", "100 → S")
	t.eq(MissionRating.grade_of(90.0), "S", "90 整 → S（门限取等号）")
	t.eq(MissionRating.grade_of(89.9), "A", "89.9 → A")
	t.eq(MissionRating.grade_of(74.0), "A", "74 整 → A")
	t.eq(MissionRating.grade_of(73.9), "B", "73.9 → B")
	t.eq(MissionRating.grade_of(55.0), "B", "55 整 → B")
	t.eq(MissionRating.grade_of(54.9), "C", "54.9 → C")
	t.eq(MissionRating.grade_of(30.0), "C", "30 整 → C")
	t.eq(MissionRating.grade_of(0.0), "D", "0 → D")
	# 门限必须**单调递减**：表写反了（比如 A 排在 S 前面）会让所有人永远拿 D
	var prev := 1e9
	for row_v in MissionRating.GRADE_TABLE:
		var row: Dictionary = row_v
		t.lt(float(row["min"]), float(prev), "门限表严格递减（%s）" % str(row["grade"]))
		prev = float(row["min"])
	t.eq(MissionRating.GRADE_TABLE[MissionRating.GRADE_TABLE.size() - 1]["grade"], "D",
		"表尾是 D（兜底档）")


# ---------------------------------------------------------------- 3. 三个分项

static func _parts(t) -> void:
	t.suite("任务评价 / 三个分项各自的定义")
	# 战果
	t.near(MissionRating.objective_score(1, 1), 100.0, 0.001, "打掉唯一目标 = 100")
	t.near(MissionRating.objective_score(0, 1), 0.0, 0.001, "一个没打掉 = 0")
	t.near(MissionRating.objective_score(3, 4), 75.0, 0.001, "4 台打掉 3 = 75")
	t.near(MissionRating.objective_score(9, 4), 100.0, 0.001, "超额也封顶 100")
	t.near(MissionRating.objective_score(1, 0), 0.0, 0.001, "总数为 0 → 0（不除零）")

	# 存续
	t.near(MissionRating.survival_score(1.0, 0.0, 0.0), 100.0, 0.001, "满血 = 100")
	t.near(MissionRating.survival_score(0.0, 0.0, 100.0), 0.0, 0.001, "空血 + 护盾打穿 = 0")
	t.near(MissionRating.survival_score(1.0, 0.0, 100.0), 70.0, 0.001,
		"满血 + 护盾全破 = 70（护盾占 30）")
	# ⚠️ 这一条是"没装 I 立场"的机体：不能因为 `ifield_max == 0` 就扣它 30 分。
	t.near(MissionRating.survival_score(0.5, 0.0, 0.0), 65.0, 0.001,
		"没装 I 立场时护盾项给满（半血 = 35 + 30）")
	t.near(MissionRating.survival_score(-1.0, -5.0, 100.0), 0.0, 0.001, "负值夹到 0")

	# 效率
	t.near(MissionRating.tempo_score(120.0, 120.0, 0.0, 0), 100.0, 0.001,
		"压着目标时间打完 = 100")
	t.near(MissionRating.tempo_score(240.0, 120.0, 0.0, 0), 50.0, 0.001,
		"拖到 2 倍时长 = 50")
	t.near(MissionRating.tempo_score(0.0, 120.0, 0.0, 0), 100.0, 0.001,
		"时长 0 也封顶 100（不除零）")
	# ⚠️ 一枪没开时命中率是"没数据"，不是"打得差"：只按时间算。
	t.near(MissionRating.tempo_score(120.0, 120.0, 0.0, 0), 100.0, 0.001,
		"没开枪时只看时间（0/0 不当 0 分）")
	t.near(MissionRating.tempo_score(120.0, 120.0, 0.5, 10), 75.0, 0.001,
		"开了枪则时间 / 命中各占一半")


# ---------------------------------------------------------------- 4. 目标时间

static func _par(t) -> void:
	t.suite("任务评价 / 目标时间按模式与台数给")
	t.near(MissionRating.par_secs(Game.MatchMode.VERSUS, 1), 120.0, 0.001, "1v1 目标 120 s")
	t.near(MissionRating.par_secs(Game.MatchMode.LAN, 1), 120.0, 0.001, "联机同 1v1")
	# 多机局本来就该更久 —— 固定值会让编队战永远拿不到 S（那是把难度错算成效率）
	t.near(MissionRating.par_secs(Game.MatchMode.TRAINING, 6), 210.0, 0.001,
		"训练 6 架靶机 = 6 × 35 s")
	t.near(MissionRating.par_secs(Game.MatchMode.CHALLENGE, 5), 225.0, 0.001,
		"挑战 5 台 = 5 × 45 s")
	t.near(MissionRating.par_secs(Game.MatchMode.SQUAD, 4), 220.0, 0.001,
		"编队战 4 台 = 4 × 55 s")
	t.near(MissionRating.par_secs(Game.MatchMode.SQUAD, 0), 55.0, 0.001,
		"台数 0 兜底成 1（不除零）")
	t.gt(MissionRating.par_secs(Game.MatchMode.SQUAD, 4),
		MissionRating.par_secs(Game.MatchMode.VERSUS, 1), "多机局的目标时间更长")


# ---------------------------------------------------------------- 5. 战果进度

static func _progress(t) -> void:
	t.suite("任务评价 / 战果进度按模式取数")
	var v := MissionRating.progress(Game.MatchMode.VERSUS, true, 0, 0, 0, 0, 0, 0)
	t.eq(int(v["downed"]), 1, "1v1 打赢 → 打掉 1")
	t.eq(int(v["total"]), 1, "1v1 总数 1")
	var vl := MissionRating.progress(Game.MatchMode.VERSUS, false, 0, 0, 0, 0, 0, 0)
	t.eq(int(vl["downed"]), 0, "1v1 打输 → 打掉 0")

	var tr := MissionRating.progress(Game.MatchMode.TRAINING, true, 5, 8, 0, 0, 0, 0)
	t.eq(int(tr["downed"]), 5, "训练读靶机进度（5 / 8）")
	t.eq(int(tr["total"]), 8, "训练总数是靶机总数")

	var ch := MissionRating.progress(Game.MatchMode.CHALLENGE, true, 0, 0, 3, 7, 0, 0)
	t.eq(int(ch["downed"]), 3, "挑战读波次击坠数（3 / 7）")
	t.eq(int(ch["total"]), 7, "挑战总数是全场敌机数")

	var sq := MissionRating.progress(Game.MatchMode.SQUAD, true, 0, 0, 0, 0, 2, 4)
	t.eq(int(sq["downed"]), 2, "编队战读击坠数（2 / 4）")
	t.eq(int(sq["total"]), 4, "编队战总数是敌方编制数")


# ---------------------------------------------------------------- 6. 失败不给字母

## ⚠️ 失败**不给** S/A/B/C —— 把"没完成"和"完成得差"塞进同一把尺子，
## S 的含义会从"完美"退化成"没死"。分项照常显示。
static func _no_grade_on_loss(t) -> void:
	t.suite("任务评价 / 失败不予评级")
	var lose := MissionRating.evaluate(_st(0, 0.0, 0.0, 100.0, 1.0, 0.0, 0.0, false))
	t.eq(str(lose["grade"]), MissionRating.NO_GRADE, "失败 → 不给字母")
	t.not_ok(bool(lose["graded"]), "失败 → graded = false")
	# 分项照常算出来：玩家还是看得到自己打得怎样
	t.near(float(lose["tempo"]), 100.0, 0.001, "失败也照常显示效率分")
	t.near(float(lose["objective"]), 0.0, 0.001, "失败的战果是 0")

	var win := MissionRating.evaluate(_st(1, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0))
	t.ok(bool(win["graded"]), "胜利 → graded = true")
	t.not_ok(str(win["grade"]) == MissionRating.NO_GRADE, "胜利一定给字母")


# ---------------------------------------------------------------- 7. 边界

static func _bounds(t) -> void:
	t.suite("任务评价 / 综合分不越界")
	var cases := [
		_st(1, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0),
		_st(0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0),
		_st(1, -3.0, -1.0, -1.0, -5.0, 2.0, 30),
		_st(9, 9.0, 9.0, 9.0, 1.0e9, 9.0, 30),
	]
	for st_v in cases:
		var st: Dictionary = st_v
		var r := MissionRating.evaluate(st)
		t.between(float(r["score"]), 0.0, 100.0, "综合分落在 0..100（got %.2f）" % float(r["score"]))
		t.between(float(r["objective"]), 0.0, 100.0, "战果分落在 0..100")
		t.between(float(r["survival"]), 0.0, 100.0, "存续分落在 0..100")
		t.between(float(r["tempo"]), 0.0, 100.0, "效率分落在 0..100")
	# 空字典也不能崩：少写一个键不该把结算画面搞没
	var empty := MissionRating.evaluate({})
	t.between(float(empty["score"]), 0.0, 100.0, "空输入不崩且落在 0..100")
	t.eq(str(empty["grade"]), MissionRating.NO_GRADE, "空输入视为未达成")


# ---------------------------------------------------------------- 8. 接线

static func _wiring(t) -> void:
	t.suite("任务评价 / 接线（HUD · main · Game）")
	# HUD 的取数入口：字段必须齐，缺一个 evaluate 就会静默退化成 0 分
	var st := FlightHUD.rating_stats(MissionRating.Outcome.WIN, 0.8, 50.0, 100.0)
	for k in ["mode", "win", "downed", "total", "units", "hp_ratio", "ifield",
			"ifield_max", "elapsed", "accuracy", "shots"]:
		t.ok(st.has(k), "rating_stats 带齐字段：%s" % k)
	t.ok(bool(st["win"]), "WIN → win = true")
	t.near(float(st["hp_ratio"]), 0.8, 0.001, "hp_ratio 透传（不在这儿另取一次）")
	t.near(float(st["ifield"]), 50.0, 0.001, "ifield 透传")
	t.near(float(st["ifield_max"]), 100.0, 0.001, "ifield_max 透传")
	var lose_st := FlightHUD.rating_stats(MissionRating.Outcome.LOSE, 0.0, 0.0, 0.0)
	t.not_ok(bool(lose_st["win"]), "LOSE → win = false")

	# 波次计时：Game 上有这个字段，且每局清零
	t.ok(Game.challenge_wave_times is Array, "Game.challenge_wave_times 存在")
	t.ok(_src(GAME_SRC).contains("challenge_wave_times.clear()"),
		"Game.reset() 里清空波次用时（不清会串到下一局）")

	# main 的三处结算必须带 outcome，否则评价块永远是空的（画面上就是"没有评价"）
	# ⚠️ 从 **2 → 3**（2026-09-30 轮 E）：触发器接上之后多了一条**玩家还活着**的
	# 失败路（`_mission_lose()`，数据里 M01..M05 的 `hp<0.25 → end:lose` 走它）。
	# 它与 `_on_player_destroyed()` 的区别是**没有残骸、不需要 `_death_anchor`**，
	# 所以是两条独立的结算入口，不是复制粘贴。
	var m := _src(MAIN_SRC)
	t.eq(m.count("capture_result(MissionRating.Outcome."), 3,
		"main 三处结算都带 outcome（阵亡 / 触发器判负 / 获胜）")
	t.ok(m.contains("capture_result(MissionRating.Outcome.WIN)"), "打赢那处传 WIN")
	t.ok(m.contains("capture_result(MissionRating.Outcome.LOSE)"), "阵亡那处传 LOSE")
	# 波次用时：两处"这一波清完了"都要记账
	t.eq(m.count("_close_wave()"), 3, "main 里 _close_wave 一处定义 + 两处调用")


# ---------------------------------------------------------------- 9. 版式

## 评价两行夹在副标题与两栏之间：挤了会压字，超了会压到栏框上。
## headless 里看不到画面，所以只能这么钉。
static func _layout(t) -> void:
	t.suite("任务评价 / 版式装得下")
	for view: Vector2 in [Vector2(1600, 900), Vector2(1280, 720), Vector2(1920, 1080)]:
		var geo := FlightHUD.result_layout(view)
		var top := float(geo["title_y"])
		var boxes: Array = geo["boxes"]
		var box_top := float((boxes[0] as Rect2).position.y) - top
		t.gt(box_top, RATING_LINE2 + 4.0, "%s：评价第二行在两栏之上" % view)
		t.gt(RATING_LINE1 - 94.0, 18.0, "%s：评价第一行不压住副标题" % view)
		# 提示行（字号 22）不能被挤出屏幕 —— 720p 是最紧的一档
		t.lt(float(geo["hint_y"]) + HINT_FS, view.y, "%s：底部提示没被挤出屏幕" % view)
		t.gt(float(geo["hint_y"]), float((boxes[0] as Rect2).position.y) + float(geo["box_h"]),
			"%s：提示行在两栏下方" % view)


# ---------------------------------------------------------------- 工具

## 造一份 evaluate() 的输入。参数顺序刻意排成"战果 → 存续 → 效率"。
static func _st(downed: int, hp_ratio: float, ifield: float, ifield_max: float,
		elapsed: float, accuracy: float, shots: int, win := true) -> Dictionary:
	return {
		"mode": Game.MatchMode.VERSUS,
		"win": win,
		"downed": downed,
		"total": 1,
		"units": 1,
		"hp_ratio": hp_ratio,
		"ifield": ifield,
		"ifield_max": ifield_max,
		"elapsed": elapsed,
		"accuracy": accuracy,
		"shots": shots,
	}


static func _src(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s
