extends Node
## 一次性探针：**远端代理打出的那枚"看得见的导弹"，到底进没进本机的威胁表**。
##
## 用户报的两条联机 bug 之一：
##   「柯西vs佩涅罗佩看得到对方导弹，但是**看不到导弹拦截显示框**」
##
## `main._on_net_fire()` 的 `"funnel"` 分支会 `Missile.funnel(projectiles, origin, dir, player, shooter, 0.0)`
## —— 目标写的是**本机玩家**。而 HUD 的拦截框读 `player.threats()`，
## `threats()` 又来自 `Interceptor.rank_threats(self, _incoming_missiles())`，
## `_incoming_missiles()` 的判据是「在 `missiles` 组里 **且** `target == self`」。
##
## ⇒ 这一串只要有一环断，"看得到导弹但没有框"就是必然的。
## 探针把每一环的读数都打出来，不猜。
##
## 跑法：
##   "C:/Users/MSIPC/Desktop/Godot_v4.7.1-stable_win64_console.exe" --headless \
##       --path "C:/Users/MSIPC/Documents/gundam" res://tests/_probe_lan_threat.tscn

const MissileScript := preload("res://scripts/combat/missile.gd")
const InterceptorScript := preload("res://scripts/combat/interceptor.gd")
const HudScript := preload("res://scripts/ui/hud.gd")


func _ready() -> void:
	await _run()


func _run() -> void:
	Game.reset()
	var c := Node3D.new()
	c.name = "ThreatProbeStage"
	add_child(c)

	# ---- 本机玩家（威胁表的持有者）----
	var me := PlayerController.new()
	me.name = "LocalPlayer"
	me.is_player = true
	me.team = 0
	me.profile = SuitProfile.xi()
	me.projectile_container = c
	c.add_child(me)
	me.global_position = Vector3(0, 3000, 0)

	# ---- 远端代理（就是联机里"对面那台"的替身）----
	var foe := FlightBody.new()
	foe.name = "RemoteProxy"
	foe.team = 1
	foe.profile = SuitProfile.penelope()
	foe.projectile_container = c
	c.add_child(foe)
	foe.global_position = Vector3(0, 3000, -2000)

	await get_tree().physics_frame
	await get_tree().physics_frame

	# ---- 复刻 `main._on_net_fire()` 的 funnel 那一支（逐字照抄那几个实参）----
	var origin: Vector3 = foe.global_position
	var dir: Vector3 = (me.global_position - origin).normalized()
	var m = MissileScript.funnel(c, origin, dir, me, foe, 0.0)

	print("---- 探针：远端代理的一枚可见导弹 ----")
	print("飞弹造出来了        : %s" % (m != null))
	if m == null:
		get_tree().quit(0)
		return
	await get_tree().physics_frame
	await get_tree().physics_frame

	print("① 在 missiles 组里吗 : %s" % m.is_in_group("missiles"))
	print("② target 是本机玩家吗: %s   （target=%s / me=%s）"
		% [m.target == me, str(m.target), str(me)])
	print("③ damage             : %.1f" % float(m.get("damage")))
	print("④ intercept_capable  : %s" % str(m.get("intercept_capable")))

	var inc: Array = me.call("_incoming_missiles")
	print("⑤ `_incoming_missiles()` 命中 %d 枚" % inc.size())
	var ranked: Array = InterceptorScript.rank_threats(me, inc)
	print("⑥ `rank_threats()` 排序后 %d 条" % ranked.size())
	me.call("_refresh_threats")
	var th: Array = me.call("threats")
	print("⑦ `player.threats()`  %d 条  ← HUD 拦截框读的就是它" % th.size())
	print("⑧ `threat_layer_visible()` : %s" % str(HudScript.threat_layer_visible(me)))

	# ---- 对照：本机自己打的一发（同一套威胁表，只是 shooter 换成自己）----
	var m2 = MissileScript.funnel(c, me.global_position, -dir, foe, me, 0.0)
	await get_tree().physics_frame
	me.call("_refresh_threats")
	print("---- 对照：本机打向对面的那一发（target=对面 ⇒ 不该进我的威胁表）----")
	print("⑨ `player.threats()`  %d 条" % (me.call("threats") as Array).size())

	Game.reset()
	c.free()
	await get_tree().process_frame
	get_tree().quit(0)
