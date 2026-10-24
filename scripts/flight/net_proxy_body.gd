class_name NetProxyBody
extends FlightBody
## 联机里"对手那台机"的本地代理（1.2）。
##
## 它**不做物理、不飞**：位置与姿态直接按收到的快照插值过去，
## 只保留"能被看到、能被锁定、能被看起来像在动"这三件事。
##
## 为什么不干脆用一台真的 `BanditAI`：那等于在本地同时跑两套模拟，
## 两边的结果必然分叉（同一台机在两个屏幕上位置不一样），
## 而且对手的实际操作根本无从得知 —— 代理 + 快照是这类小体量 PvP 的正解。
##
## 仍然继承 `FlightBody`：模型、夜航灯、锁定、命中特效、爆炸全都能直接复用；
## 只是把 `_think()` 覆写成"朝快照插值"，并把 `_apply_flight()` 换掉（不跑气动）。

## 快照之间的插值速率（1/s）。20 Hz 快照 + 这个速率看起来就是连续的。
@export var interp_rate := 12.0

var _want_pos := Vector3.ZERO
var _want_basis := Basis()
var _want_vel := Vector3.ZERO
var _has_state := false


func _ready() -> void:
	super._ready()
	name = "RemoteFoe"


## 收一份快照（`NetSession.unpack_state` 的产物）。
func apply_state(s: Dictionary) -> void:
	_want_pos = s["position"]
	_want_basis = s["basis"]
	_want_vel = s["velocity"]
	_has_state = true
	combat_buffs.apply_snapshot(s.get("combat",{}))
	if thunderbolt_systems!=null:thunderbolt_systems.apply_snapshot(s.get("tb",{}))
	if is_instance_valid(nu_systems): nu_systems.apply_snapshot(s.get("nu",{}))
	hp = maxf(s["hp"], 0.0)
	ifield_hp = maxf(s["ifield"], 0.0)
	# 形态（阿利宙斯）在对面切换时，本地也跟着换模型；血条照抄，不自己算
	if s["form"] != form_index and profile != null \
			and s["form"] < SuitProfile.forms_of(profile.id).size():
		switch_form(s["form"], false, false)
	if not s["alive"] and alive:
		destroy(null, "联机击坠")


## 不吃伤害：血量由对面那台机的所有者维护（谁会受伤谁说了算）。
##
## 这里**不是"什么都不做"**：本地打中了代理机体，就代表我打中了对面 ——
## 于是把这一发原样报给对面（`send_damage`），由他自己扣自己的血。
## 于是"谁的血条谁维护"，两边永远不可能出现两套血量。
func take_damage(amount: float, _source: Node3D, damage_type := Damage.Type.RAM) -> void:
	if amount > 0.0 and alive and not is_friendly_fire(_source):
		if is_instance_valid(_source) and _source.has_method("confirm_zorin_weapon_hit"):_source.confirm_zorin_weapon_hit(self,damage_type)
		if _source is FlightBody: amount *= _source.combat_buffs.damage_rate(damage_type)
		Net.send_damage(amount, damage_type)
		var parent := get_parent()
		if parent != null:
			FX.hit_spark(parent, global_position, 0.6)


## 由 main 每帧调用：朝着最近一份快照平滑过去。
func interp(delta: float) -> void:
	if not _has_state:
		return
	var k := 1.0 - exp(-interp_rate * delta)
	global_position = global_position.lerp(_want_pos, k)
	global_transform = Transform3D(
		global_transform.basis.slerp(_want_basis, k).orthonormalized(), global_position)
	velocity = _want_vel
	fm.velocity = _want_vel
	fm.speed = _want_vel.length()


## 代理机体不跑飞行模型：`FlightBody._physics_process` 里的气动推进要跳过，
## 但武器的冷却、护盾计时、特效还需要走（否则弹丸/烟雾不更新）。
func _apply_flight(_delta: float) -> void:
	pass


func _think(_delta: float) -> void:
	if saber_active():
		saber_timer=maxf(saber_timer-_delta,0.0)
		if saber_timer<=0.0:abort_saber()
