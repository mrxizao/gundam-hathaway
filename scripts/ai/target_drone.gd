class_name TargetDrone
extends FlightBody
## 训练模式的靶机：古斯塔夫00型。**不还手**，只按固定航线绕着靶场飞。
##
## 为什么它不是 `BanditAI` 的一个难度档：
##   - BanditAI 的全部价值在"追着玩家咬"（四态机 / 提前量 / 丢枪规则），
##     靶机一条都不需要；
##   - 靶机要的是**可预测**：航线固定、不打人，玩家才能专注练手感。
##     可预测 = 训练模式存在的理由，所以这里宁可重写一个 40 行的 AI，
##     也不去 BanditAI 里塞一堆 `if training`。
##
## 它仍然是 `FlightBody`：模型、损伤、锁定、HUD 目标框全部复用。
## 血量给得很低（一梭子就能打掉），因为"打靶"的重点是命中感，不是消耗战。

## 巡航高度（米）。与靶场的探照灯塔同高，靶机在灯下穿过来时最好认。
@export var patrol_altitude := 2600.0
## 航线半径（米）。三架靶机各自错开，形成一条"环形跑道"。
@export var patrol_radius := 5200.0
## 转弯速率的下限（度/秒）。太大会像战斗机，太小会飞出场地。
@export var turn_limit := 26.0

## 航线圆心（世界坐标）。main 在撒靶机时按场地给。
var patrol_center := Vector3.ZERO
## 在圆周上的相位（弧度）。同型靶机错开相位就不会挤在一起。
var phase := 0.0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	super._ready()
	_rng.seed = int(phase * 1000.0) + 17
	# 靶机没有 I 立场、血也薄：训练的目标是"打中"，不是"磨盾"
	display_name = "古斯塔夫00（靶机）"


## 只做一件事：把机头压向"圆周上前方一点"的目标点。
## 速度固定在巡航档，不加速不悬停 —— 靶机忽快忽慢会让提前量练习失去意义。
func _think(delta: float) -> void:
	var target_point := _waypoint()
	var desired := target_point - global_position
	if desired.length_squared() < 1.0:
		return
	_steer(desired.normalized())
	fm.hovering = false
	fm.boosting = false
	fm.throttle = 0.72


## 下一个航点：当前相位再往前一点点（用"离圆心的角度"推进，而不是按时间算，
## 这样即使速度变了也不会突然跳到圆周的另一边）。
func _waypoint() -> Vector3:
	var rel := global_position - patrol_center
	var ang := atan2(rel.z, rel.x)
	if rel.length_squared() < 1.0:
		ang = phase
	var step := deg_to_rad(turn_limit) * 0.6
	var next := ang + step
	return patrol_center + Vector3(cos(next), 0.0, sin(next)) * patrol_radius \
		+ Vector3(0, patrol_altitude, 0)


## 和 BanditAI 同一套转向控制器（机体坐标系的 atan2），只是没有武器与状态机。
func _steer(desired_dir: Vector3) -> void:
	var local := global_transform.basis.inverse() * desired_dir.normalized()
	var fwd_comp := -local.z
	var pitch_ang := atan2(local.y, fwd_comp)
	var roll_ang := atan2(local.x, fwd_comp)
	control_input = Vector3(
		clampf(pitch_ang / 0.55, -1.0, 1.0),
		0.0,
		clampf(-roll_ang / 0.62, -1.0, 1.0))
