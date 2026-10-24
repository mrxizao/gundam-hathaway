class_name MissionRating
extends RefCounted
## 任务评价（S·A·B·C）：把一局的表现压成一个字母。
##
## ⚠️ **纯函数：不读节点、不改状态。** 评价是"算出来的"，不是"从现场抄的"，
## 所以它必须能被单测直接喂一个字典来断言。这跟 `UILayout` /
## `ChaseCamera.shield_hit_ratio()` 是同一条规矩，理由也一样：这一版栽过
## "参数在动、画面不动"（`DESIGN` §4.9.4），而纯函数是唯一能钉住它的办法 ——
## 否则有人把权重改成 0，测试照样全绿。
##
## 三项权重是**有意的**：战果 0.45 > 存续 0.35 > 效率 0.20。
##   打赢但被打成筛子不该拿 S（那不是完美，那只是没死）；
##   打得漂亮但没完成也不该拿 S（那是练习，不是任务）。

enum Outcome { PENDING, WIN, LOSE }

## 等级门限（综合分 0..100），从高往低判，第一个够到的就是它。
## ⚠️ 门限是**实测过手感**才定的，不是随手分的四段（见 `suite_mission_rating`）：
##   血 95% + 护盾完好 + 压着目标时间 + 命中 60% → 94.8（S）
##   血 70% + 护盾已破 + 压着目标时间 + 命中 50% → 77.2（A）
##   血 50% + 护盾已破 + 1.5 倍时长 + 命中 40% → 67.9（B）
## 换句话说：打赢只是门槛，S 要"血基本没掉、护盾没破、打得还快"。
const GRADE_TABLE := [
	{"grade": "S", "min": 90.0},
	{"grade": "A", "min": 74.0},
	{"grade": "B", "min": 55.0},
	{"grade": "C", "min": 30.0},
	{"grade": "D", "min": 0.0},
]

const W_OBJECTIVE := 0.45
const W_SURVIVAL := 0.35
const W_TEMPO := 0.20

## 机体耐久 / I 立场在存续项里各占多少。
const HULL_PART := 70.0
const SHIELD_PART := 30.0

## 失败时**不给字母**。
## ⚠️ 这不是省事：把"没完成"和"完成得差"塞进同一个字母，
## S 的含义会从"完美"退化成"没死"。三项分项照常显示，玩家仍然看得到自己打得怎样。
const NO_GRADE := "—"


## 目标时间（秒）：在这个时长内打完，效率项的时间部分拿满分。
##
## 按"每台敌机多少秒"给，不用固定值 —— 4 台的编队战本来就该比 1v1 久，
## 固定值会让编队战永远拿不到 S（那是把"难度"错算成了"效率"）。
static func par_secs(mode: int, units: int) -> float:
	var n := float(maxi(units, 1))
	match mode:
		Game.MatchMode.TRAINING:
			return 35.0 * n
		Game.MatchMode.CHALLENGE:
			return 45.0 * n
		Game.MatchMode.SQUAD:
			return 55.0 * n
		_:
			return 120.0


## 本局的战果进度。模式的差异全部收敛在这里 —— 外面只管喂数进来。
static func progress(mode: int, win: bool, training_down: int, training_total: int,
		challenge_killed: int, challenge_total: int,
		squad_kills: int, squad_total: int) -> Dictionary:
	match mode:
		Game.MatchMode.TRAINING:
			return {"downed": training_down, "total": training_total}
		Game.MatchMode.CHALLENGE:
			return {"downed": challenge_killed, "total": challenge_total}
		Game.MatchMode.SQUAD:
			return {"downed": squad_kills, "total": squad_total}
		_:
			# 1v1 / 联机：目标就一台，"打赢"就是全部战果。
			return {"downed": 1 if win else 0, "total": 1}


static func objective_score(downed: int, total: int) -> float:
	if total <= 0:
		return 0.0
	return clampf(float(downed) / float(total), 0.0, 1.0) * 100.0


## ⚠️ `ifield_max <= 0` 时护盾项**给满**，不是给 0：
## 这台机压根没装 I 立场（"没有这个装备" ≠ "把它用光了"）。
static func survival_score(hp_ratio: float, ifield: float, ifield_max: float) -> float:
	var hull := clampf(hp_ratio, 0.0, 1.0) * HULL_PART
	var shield := SHIELD_PART
	if ifield_max > 0.0:
		shield = clampf(ifield / ifield_max, 0.0, 1.0) * SHIELD_PART
	return hull + shield


## ⚠️ 一枪没开时**只看时间**：命中率 0/0 是"没数据"，不是"打得差"，
## 把它当 0 分会逼玩家为了评分去空放几枪。
static func tempo_score(elapsed: float, par: float, accuracy: float, shots: int) -> float:
	var t := clampf(par / maxf(elapsed, 1.0), 0.0, 1.0) * 100.0
	if shots <= 0:
		return t
	var a := clampf(accuracy, 0.0, 1.0) * 100.0
	return t * 0.5 + a * 0.5


static func grade_of(score: float) -> String:
	for row: Dictionary in GRADE_TABLE:
		if score >= float(row["min"]):
			return str(row["grade"])
	return "D"


## 综合评分。`st` 的键：
##   mode / win / downed / total / units / hp_ratio / ifield / ifield_max /
##   elapsed / accuracy / shots
## 返回 {grade, graded, score, objective, survival, tempo, par_secs}
static func evaluate(st: Dictionary) -> Dictionary:
	var total := maxi(int(st.get("total", 0)), 0)
	var downed := maxi(int(st.get("downed", 0)), 0)
	var units := maxi(int(st.get("units", total)), 1)
	var par := par_secs(int(st.get("mode", Game.MatchMode.VERSUS)), units)
	var obj := objective_score(downed, total)
	var svv := survival_score(float(st.get("hp_ratio", 0.0)),
		float(st.get("ifield", 0.0)), float(st.get("ifield_max", 0.0)))
	var tmp := tempo_score(float(st.get("elapsed", 0.0)), par,
		float(st.get("accuracy", 0.0)), int(st.get("shots", 0)))
	var score := obj * W_OBJECTIVE + svv * W_SURVIVAL + tmp * W_TEMPO
	var win := bool(st.get("win", false))
	return {
		"grade": grade_of(score) if win else NO_GRADE,
		"graded": win,
		"score": score,
		"objective": obj,
		"survival": svv,
		"tempo": tmp,
		"par_secs": par,
	}
