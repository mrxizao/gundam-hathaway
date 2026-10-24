class_name Interceptor
extends RefCounted
## 拦截弹的**纯函数工具箱**（1.2）：给来袭飞弹排名、去重、把一梭拦截弹分配给若干目标。
##
## # ⚠️ 这里原来是一个 `extends Node3D` 的节点类，节点部分已删（2026-09-21）
##
## 删掉的东西：`spawn()` / `_physics_process()` / `_intercept()` / `forward()`、
## 三个实例字段（`victim` / `shooter` / `_age`）、以及只服务于那段死代码的四个常量
## （`SPEED` / `TURN_RATE` / `FUSE_RADIUS` / `LIFETIME`）。
##
## **为什么删**：`spawn()` **一个调用点都没有**（交接文档 §8.4 / 设计文档 §3.5）。
## 真正在跑的拦截是**来袭弹自己**被"武装"（`Missile.arm_intercept()`）：
## `PlayerController._read_weapon_input()` 发一发浮游导弹、把 `intercept_target`
## 写在**那一发弹自己身上**，飞弹在半空对撞时走的是 `Missile.intercept()`。
## 所以那个节点类是一整块**没人实例化的影子实现**，而它的存在本身有害 ——
## `missile.gd` 里留着一句"`Interceptor.SPEED` = 1500 m/s"，
## 老板照着这句话提需求（"拦截的导弹速度从 1.5 改为 1.1"），
## 而那个常数**改了什么用都没有**（真正管速度的是 `Missile.INTERCEPT_SPEED_MULT`）。
## 那句注释现在也改了。
##
## 留下的 4 个静态函数是**活的**，`PlayerController` 与 `hud.gd` 都在调；
## 它们只读传进来的节点与数组，脱离场景可单测 —— 所以基类从 `Node3D` 换成
## `RefCounted`（和 `Ballistics` / `UILayout` / `InterceptAuto` 同一档）。
##
## # 与"干扰弹骗掉飞弹"的关系
##
## 两者走的是**同一个出口**（`Missile.intercept()`），所以"骗掉"和"打掉"在观感与
## 后果上完全一致 —— 飞弹在半空炸掉、不伤人。区别只是"确定"与"概率"：
## 干扰弹要靠飞弹飞进烟里，拦截弹是主动打掉。


## 按 **TTI（time to impact = 距离 / 接近速度）** 给来袭飞弹排序。
##
## ⚠️ 不能用"距离"排：离我最近的未必最先打到我 —— 迎面高速飞来的一发
## 比"在侧后方慢慢飘的一发"危险得多。TTI 才是"我还有多久"。
## 纯函数，便于单测。
static func rank_threats(me: Node3D, missiles: Array) -> Array:
	var scored: Array = []
	for m: Node in missiles:
		if m == null or not is_instance_valid(m) or not (m is Node3D):
			continue
		var mp := m as Node3D
		# 只算"冲着我来"的：飞弹的 target 是我
		if "target" in m and m.get("target") != me:
			continue
		var to := mp.global_position - me.global_position
		var dist := to.length()
		var closing := 0.0
		if "speed" in m:
			# 飞弹当前的朝向（`-Z`）与视线方向的接近分量
			var fwd := -mp.global_transform.basis.z
			closing = maxf(fwd.dot(-to.normalized()) * float(m.get("speed")), 1.0)
		scored.append({"missile": mp, "tti": dist / maxf(closing, 1.0), "dist": dist})
	scored.sort_custom(func(a, b): return a["tti"] < b["tti"])
	return scored


## 场上所有"**已经有一发可对撞的浮游导弹咬着**"的来袭弹（第十五轮新增）。
##
## 用途只有一个：**自动拦截不能重复打同一枚**。自动模式每 0.5 秒发一发，
## 而 TTI 排名在一分钟里几乎不变 —— 没有这条，前两发之后就全砸在 #1 上，
## 玩家只会看到"浮游导弹白没了"，而拦下来的还是同一枚。
##
## 判据用弹**自己身上**的 `intercept_target`（`Missile.arm_intercept()` 写的），
## 而不是"我们记过发过几次"：后者在"那一发半路被别的东西撞掉 / 到寿自毁"之后
## 就不再成立，而这一个字段是跟着弹走的。
static func engaged_targets(me: Node) -> Array:
	var out: Array = []
	if me == null or not is_instance_valid(me):
		return out
	var tree := me.get_tree()
	if tree == null:
		return out
	# 组快照走 Game 的每物理帧缓存（批 10 性能二轮）
	for m: Node in Game.group_snapshot(tree, "missiles"):
		if not is_instance_valid(m):
			continue
		var mk = m.get("intercept_target")
		if mk != null and is_instance_valid(mk):
			out.append(mk)
	return out


## 从 TTI 升序表里挑第一枚"还没被咬住"的来袭弹。
##
## **纯函数**（只读传进来的两张表），所以能脱离场景单测 —— 和 `rank_threats()` 一样。
## `engaged` 为空 = 退化成"挑最危险的那一枚"（点按路径就是直接用 `ranked[0]` 的语义）。
static func pick_available(ranked: Array, engaged: Array) -> Node3D:
	for e in ranked:
		var m = e.get("missile")
		if m == null or not is_instance_valid(m):
			continue
		if engaged.has(m):
			continue
		return m as Node3D
	return null


## 把**一梭拦截弹**分配给若干来袭弹（第十八轮 · 方案 A 的核心）。
##
## **贪心 + 两轮**，判据是**转角最小**：
##   第 1 轮：在「弹未用 ∧ 目标未用」的组合里挑转角最小的那一对 —— 于是 3 发弹尽量分给 3 个目标；
##   第 2 轮：还有剩下的弹，就派给「转角最小的那个已被占用的目标」（目标少于一梭时，几发一起咬同一枚）。
##
## ⚠️ **为什么必须按转角、不能按 TTI 顺序硬塞**：拦截弹被 `arm_intercept()` 加速 **×1.8**，
## 而转向率是 rad/s —— **速度 ×1.8 意味着转弯半径也 ×1.8**（`Missile.INTERCEPT_SPEED_MULT`
## 那段注释里记着这笔账）。把扇开的三发硬塞给"TTI 前三名"，其中两发可能要掉头去追反方向的目标，
## 结果是"打了三发拦截弹、一枚都没撞上" —— 比只武装一发还差。
##
## 纯函数（只读每发弹的 `global_position` 与机头方向），可脱离场景单测。
## 返回：`[{"missile": 拦截弹, "threat": 来袭弹}, …]`，长度 ≤ `salvo.size()`。
static func assign_targets(salvo: Array, threats: Array) -> Array:
	var pairs: Array = []
	for i in salvo.size():
		var m := salvo[i] as Node3D
		if m == null or not is_instance_valid(m):
			continue
		var fwd := -m.global_transform.basis.z
		for j in threats.size():
			var th := threats[j] as Node3D
			if th == null or not is_instance_valid(th):
				continue
			var to := th.global_position - m.global_position
			var ang := 0.0 if to.length_squared() < 0.0001 else fwd.angle_to(to.normalized())
			pairs.append({"mi": i, "ti": j, "angle": ang})
	pairs.sort_custom(func(a, b): return a["angle"] < b["angle"])

	var used_m := {}
	var used_t := {}
	var out: Array = []
	# 第 1 轮：一对一（弹与目标都不重复）
	for p in pairs:
		if out.size() >= salvo.size():
			break
		if used_m.has(p["mi"]) or used_t.has(p["ti"]):
			continue
		used_m[p["mi"]] = true
		used_t[p["ti"]] = true
		out.append({"missile": salvo[p["mi"]], "threat": threats[p["ti"]]})
	# 第 2 轮：剩下的弹派给"转角最小的那个已被占用的目标"
	for p in pairs:
		if out.size() >= salvo.size():
			break
		if used_m.has(p["mi"]):
			continue
		used_m[p["mi"]] = true
		out.append({"missile": salvo[p["mi"]], "threat": threats[p["ti"]]})
	return out
