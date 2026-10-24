class_name PlayerController
extends FlightBody
## 玩家机：把键鼠 / 手柄输入翻译成 FlightBody 的控制输入，并驱动全部武器。
##
## ## 1.1：鼠标不再操纵机头（用户要求）
##
## 原先是"鼠标位置 → 机头该往哪转"（`_apply_mouse_aim`），于是**视角与瞄准是同一件事**。
## 用户 1.1 把它拆开：
##   - **鼠标只负责锁定**：光标指到哪台敌机就选中哪台，选中即开始锁定，锁定后一直保持；
##   - **机头只由键盘 / 手柄操纵**（WASD + QE + 摇杆）；
##   - **Alt = 切换锁定镜头**（开关式，不是按住；锁定掉了自动退出）。
## 所以这一版把 `_apply_mouse_aim()` 整套删掉了。
## 好处不只是"符合需求"：鼠标瞄准与键盘操纵原本会互相打架
## （键盘一动准星就被收回机头），拆开之后两种输入各管一摊，再也不用抢。
##
## ## 键位
##   W / ↑   推杆 → 机头下沉          S / ↓   拉杆 → 机头抬起
##   A D / ← →   左 / 右滚转          Q E     左 / 右偏航
##   **鼠标移动 = 选目标**（光标罩住敌机即选中）· **Alt = 锁定镜头开关**
##   **鼠标左键   光束步枪**（无限弹，但需要还有枪）
##   **鼠标右键   光束军刀劈砍**（锁定且在吸附范围内会高速突进过去）
##   空格         火神炮（按住连发）
##   F            浮游导弹（需先锁定）
##   **Z          变形**（阿利宙斯：巡航形态 ↔ 常态；核心形态不可手动切换）
##   **Shift      加速模式** · **Ctrl       悬停**
##   **R          光束步枪换弹** · **G  丢弃一把光束步枪**（仅柯西）
##   C 干扰弹 / T 举盾 / Tab 切换目标 / V 回头看 / I 俯仰反转 / Esc 暂停
##
## ## 辅助驾驶 · 平移模式（2026-09-22）
##   **长按 G 开启辅助驾驶后**（两种情形保持上面的飞行操纵、不走平移：
##   **阿利宙斯巡航形态**、以及**骑在飞行踏板上** —— 见 `assist_uses_translation`）：
##   W 前 / S 后 / A 左 / D 右 · Q 升 / E 降 · **Shift = 闪避冲刺（点按）**
##   手柄：左摇杆 前后左右 · 右摇杆 前推升/后拉降 · X 闪避冲刺
##
##   二调（2026-09-22 晚，用户反馈）：辅助驾驶**保持自动加速飞行** —— 机体永远
##   以加力极速沿机头自动飞，WASD/QE 只是在底速上叠加平移修正；Shift 改成
##   **装甲核心式闪避冲刺**（点按触发、窗口直冲、结束回落），不再"按住才动"。
##   阿利宙斯巡航形态：辅助保持原样，Shift = **超级加速**（极速再 ×1.35）。
##   冲刺 / 超级加速时机尾亮起**连贯拖尾光条**（BoostTrail）。

func is_sazabi() -> bool:
	return profile!=null and profile.id==SuitProfile.Id.SAZABI

var regz_weapons = preload("res://scripts/combat/regz_weapons.gd").new()
func is_regz() -> bool:
	return profile != null and profile.id == SuitProfile.Id.REGZ_CUSTOM
func is_zorin() -> bool:
	return profile!=null and profile.id==SuitProfile.Id.ZORIN_SOUL

func is_nu() -> bool:
	return profile != null and profile.id == SuitProfile.Id.NU_GUNDAM
func precision_suit() -> bool:
	return is_regz() or is_nu()
func _ready() -> void:
	super._ready()
	if is_nu() or is_sazabi() or is_zorin() or SuitProfile.is_thunderbolt(profile.id): assist_on = true
func precision_view_active() -> bool:
	return (sazabi_systems.scope_active() if is_sazabi() and sazabi_systems!=null else (precision_suit() and regz_weapons.scope_active())) and alive and controls_enabled and not in_transform()
func precision_focus_target() -> Node3D:
	if not precision_view_active(): return null
	var focus: Node3D = sazabi_systems.selected if is_sazabi() and sazabi_systems!=null else regz_weapons.selected
	if not is_instance_valid(focus):focus=lock.target if lock!=null else null
	if not is_instance_valid(focus) or focus.is_queued_for_deletion(): return null
	if focus is FlightBody and (not focus.alive or not is_hostile_to(focus)): return null
	return focus


var _precision_free_forward := Vector3.ZERO
func precision_free_direction() -> Vector3:
	if not precision_view_active() or precision_focus_target() != null or Settings.first_person:
		return Vector3.ZERO
	return _precision_free_forward if _precision_free_forward.length_squared() > 0.5 else forward()

func _move_precision_free_mouse(relative: Vector2) -> void:
	var direction := precision_free_direction()
	if direction.length_squared() < 0.5: return
	var yaw := atan2(-direction.x,-direction.z) - relative.x*0.0025
	var pitch := clampf(asin(clampf(direction.y,-1.0,1.0))-relative.y*0.0025,deg_to_rad(-85.0),deg_to_rad(85.0))
	_precision_free_forward = Vector3(-sin(yaw)*cos(pitch),sin(pitch),-cos(yaw)*cos(pitch))

func _tick_precision_free_flight(delta: float) -> void:
	var direction := precision_free_direction()
	if direction.length_squared() < 0.5:
		_precision_free_forward = Vector3.ZERO
		return
	_precision_free_forward = direction
	aim_cursor = get_viewport().get_visible_rect().size*0.5
	set_aim_direction(direction)
	global_basis = global_basis.slerp(Basis.looking_at(direction,Vector3.UP),1.0-exp(-12.0*delta)).orthonormalized()


const RifleSolution = preload("res://scripts/combat/rifle_aim_solution.gd")
## Comparison switch for controlled A/B captures; does not alter missile lock.
var rifle_assist_v1 := true
var _rifle_input_active := false
var _rifle_candidate: FlightBody = null
var _rifle_pending: FlightBody = null
var _rifle_candidate_time := 0.0
var _rifle_selected_id := 0
var _rifle_last_solution: Dictionary = {}

func rifle_raw_ray() -> Dictionary:
	# A previous mouse position must not steer rifle shots after switching to a pad.
	if not InputSetup.using_gamepad and mouse_lock_enabled and cursor_seen:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			return {"origin": cam.project_ray_origin(aim_cursor),
				"direction": cam.project_ray_normal(aim_cursor)}
	return {"origin": global_position, "direction": forward()}

func _rifle_origin() -> Vector3:
	if is_sazabi() and sazabi_systems!=null:return global_transform*sazabi_systems.motion.muzzle_local()
	if is_nu():return global_transform*_rifle_muzzle_local(0)
	if precision_suit() and _regz_motion != null and _regz_motion.ready: return global_transform * _rifle_muzzle_local(0)
	return global_transform * _muzzle_local[0] if not _muzzle_local.is_empty() else global_position

func _rifle_eligible(foe, ray: Dictionary, cone: float) -> bool:
	if not is_instance_valid(foe) or not foe is FlightBody or not foe.alive \
			or foe.is_queued_for_deletion() or not is_hostile_to(foe):
		return false
	var offset: Vector3 = foe.global_position - ray["origin"]
	if offset.dot(ray["direction"]) <= 0.0:
		return false
	if Ballistics.angle_off_boresight(ray["direction"], offset) > cone:
		return false
	return RifleSolution.clear_path(self, ray["origin"], foe.global_position, foe) \
		and RifleSolution.clear_path(self, _rifle_origin(), foe.global_position, foe)

func _tick_rifle_aim(delta: float) -> void:
	_rifle_last_solution = {}
	if not rifle_assist_v1 or rifle_count <= 0:
		_rifle_candidate = null
		_rifle_pending = null
		_rifle_candidate_time = 0.0
		return
	var ray := rifle_raw_ray()
	var selected = lock.target if lock != null else null
	var selected_id: int = selected.get_instance_id() if is_instance_valid(selected) else 0
	if selected_id != _rifle_selected_id:
		_rifle_candidate = null
		_rifle_pending = null
		_rifle_candidate_time = 0.0
		_rifle_selected_id = selected_id
	# Explicit lock keeps the existing outer cone. Nearby alternatives use a much
	# smaller intent cone and never write lock.target or the flight face_target.
	if _rifle_eligible(selected, ray, AIM_ASSIST_CONE_DEG):
		_rifle_candidate = selected
		_rifle_pending = null
		_rifle_candidate_time = 0.0
	else:
		var cone := 4.0
		var best: FlightBody = null
		var best_angle := INF
		for foe in Game.live_hostiles_of(self):
			if global_position.distance_to(foe.global_position) > 6000.0:
				continue
			if not _rifle_eligible(foe, ray, cone):
				continue
			var angle := Ballistics.angle_off_boresight(ray["direction"], foe.global_position - ray["origin"])
			# A small score advantage keeps crossing contacts from flickering.
			var score := angle - (0.25 if foe == _rifle_candidate else 0.0)
			if score < best_angle:
				best_angle = score
				best = foe
		if not _rifle_eligible(_rifle_candidate, ray, cone):
			_rifle_candidate = null
		if best != _rifle_pending:
			_rifle_pending = best
			_rifle_candidate_time = 0.0
		_rifle_candidate_time += delta
		var hold := 0.10 if InputSetup.using_gamepad else 0.06
		if best != null and (best_angle <= 0.35 or _rifle_candidate_time >= hold):
			_rifle_candidate = best
	_rifle_last_solution = rifle_solution(_rifle_origin(), selected)

func rifle_solution(origin: Vector3, selected = null) -> Dictionary:
	var ray := rifle_raw_ray()
	if (precision_suit() and regz_weapons.scope_active()) or (is_sazabi() and precision_view_active()):
		var scoped = sazabi_systems.selected if is_sazabi() else (regz_weapons.selected if is_instance_valid(regz_weapons.selected) else selected)
		if regz_weapons.eligible(self,scoped):
			var scoped_result := RifleSolution.solve(origin,ray["origin"],ray["direction"],scoped,profile.rifle_steady_speed,false)
			scoped_result["aim_point"] = scoped_result["prediction"]
			scoped_result["weight"] = 1.0
			scoped_result["correction_deg"] = scoped_result["error_deg"]
			scoped_result["version"] = "nu-precision-v1" if is_nu() else "regz-precision-v1"
			return scoped_result
	var target = _rifle_candidate if is_instance_valid(_rifle_candidate) else selected
	var assistance := _rifle_eligible(target, ray, 4.0)
	var result := RifleSolution.solve(origin, ray["origin"], ray["direction"], target,
		profile.rifle_steady_speed, assistance)
	if result["valid"] and assistance:
		var clear := RifleSolution.clear_path(self, origin, result["prediction"], target) and RifleSolution.clear_path(self, ray["origin"], target.global_position, target)
		if not clear:
			result = RifleSolution.solve(origin, ray["origin"], ray["direction"], target,
				profile.rifle_steady_speed, false)
			result["blocked"] = true
	return result

func rifle_hud_solution() -> Dictionary:
	if not rifle_assist_v1 or Settings.first_person or current_slot() != "rifle" \
			or rifle_count <= 0 or in_transform():
		return {}
	if not _rifle_last_solution.is_empty():
		return _rifle_last_solution
	return rifle_solution(_rifle_origin(), lock.target if lock != null else null)

func aim_point(origin: Vector3, target: Node3D, lead: bool, projectile_speed: float,
		beam_model := false, assist := false) -> Vector3:
	if ((precision_suit() and regz_weapons.scope_active()) or (is_sazabi() and precision_view_active())) and beam_model and assist and regz_weapons.eligible(self,target):
		_rifle_last_solution = rifle_solution(origin,target)
		return _rifle_last_solution["aim_point"]
	if rifle_assist_v1 and beam_model and assist and not lead:
		_rifle_last_solution = rifle_solution(origin, target)
		return _rifle_last_solution["aim_point"]
	return super.aim_point(origin, target, lead, projectile_speed, beam_model, assist)

func rifle_shot_metadata() -> Dictionary:
	var s := _rifle_last_solution
	var selected = lock.target if lock != null else null
	return {"input": ("gamepad" if InputSetup.using_gamepad else "keyboard_mouse") if controls_enabled and _rifle_input_active and not Game.rifle_metrics_test_mode else "script",
		"assist": rifle_assist_v1 or assist_on or precision_view_active(), "third_person": not Settings.first_person,
		"version": str(s.get("version",RifleSolution.VERSION)) if rifle_assist_v1 else "baseline",
		"model": profile.model_name, "form": profile.form_name(),
		"selected_id": selected.get_instance_id() if is_instance_valid(selected) else 0,
		"target_id": int(s.get("target_id", 0)), "error_deg": float(s.get("error_deg", 0)),
		"correction_deg": float(s.get("correction_deg", 0)), "weight": float(s.get("weight", 0)),
		"flight_time": float(s.get("flight_time", 0)), "blocked": bool(s.get("blocked", false)),
		"physics_frame": Engine.get_physics_frames(),
		"angular_speed_deg": rad_to_deg(target_angular_speed()),
		"ray_origin": _rifle_vector(s.get("ray_origin", global_position)),
		"raw_point": _rifle_vector(s.get("raw_point", global_position)),
		"aim_point": _rifle_vector(s.get("aim_point", global_position)),
		"prediction": _rifle_vector(s.get("prediction", global_position))}

func target_angular_speed() -> float:
	if not is_instance_valid(_rifle_candidate):
		return 0.0
	var offset := _rifle_candidate.global_position - global_position
	var relative := _rifle_candidate.fm.velocity - fm.velocity
	return offset.cross(relative).length() / maxf(offset.length_squared(), 1.0)

func _rifle_vector(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


signal notice(text: String, seconds: float)

var lock: LockOnSystem
var camera: ChaseCamera

var invert_pitch := false
## INTRO 阶段不接受操作，避免开场就把飞机扎进海里。
var controls_enabled := false

## 调试 / 截图 / 演示用：打开后由 debug_input 取代键盘。
var debug_input_enabled := false
var debug_input := Vector3.ZERO
var debug_throttle := 0.75
var _penelope_shift = preload("res://scripts/flight/penelope_shift.gd").new()
var debug_boost := false
var debug_hover := false

## 本帧的加速程度 0..1，供镜头 FOV 与速度线使用。
var boost_intensity := 0.0

## ---- 滚转回正辅助（第十四轮 A3，来自玩家实测）----
##
## 反馈原话："那个冲刺的时候机体为啥会一直顺时针转" +
## "手柄动一下**左**摇杆的左右两边机子就会开始转圈"。
##
## 直接原因是**死区太小**（原来是 0.12）：滚转是**速率型**轴，
## 摇杆回中的那点误差（旧手柄能到 0.15~0.2）被逐帧积分成持续滚转，
## 表现就是"手没动，机子自己在转"。死区提到 0.20 之后这条症状从根上消失。
##
## 但"机体一直保持上一次的坡度"在夜战里同样很难读姿态，所以再加一层**可关**的辅助：
## 松杆 `ROLL_LEVEL_DELAY` 秒之后，按**当前坡度**温和回正。
## ⚠️ 注意它改的是**坡度**（重力方向与机体上方量出来的夹角），
## 不是一个"慢慢归零的输入值" —— 后者对一个速率型轴等于什么都没做。
var roll_level_assist := true
var _roll_idle := 0.0

var _was_locked := false
## 长按识别（1.2）：丢枪 0.6 s。**只剩键盘 R 这一个入口**（★63-9 B6）。
##
## ⚠️ ★63-9 B6：原来还有一个 `_hold_discard_b`（绑 `shield` = 键盘 T / 手柄 B 的长按）——
## 用户实测报「把长按 t 的丢枪去掉，保留 t 撑盾的功能」。
## 它造成的实际观感比“误丢枪”更糟：**举盾就是要一直按住的**，于是每次举盾都会走一遍
## 丢枪判定 —— 柯西会真的把枪丢出去，其他机体会在 0.6 s 后弹一句「本机不能丢弃步枪」
##（`_try_discard_rifle()` 里那条）。⇒ **整个分支删掉**，不是“加个条件”。
## 长按 R（换弹键）保留：它离举盾远、用户没报，而且现在是丢枪唯一的入口了。
var _hold_discard_r := HoldAction.new()
var _discard_warned := false
## 批 1（多目标锁定）：**长按 Tab = 把候选敌机加入锁定组**（键鼠侧）。
## 手柄侧不走这里，走 `InputSetup.PAD_HOLD`（那里有"三处同源"的机制）。
var _hold_add_lock := HoldAction.new()
## 手柄"点按 / 长按分家"的那些长按实例：`{触发动作名: HoldAction}`。
## 内容由 `InputSetup.PAD_HOLD` 决定（数据在那边，理由见它自己的注释）——
## 2026-09-21 起有两条：**长按 L3 = 修复**、**长按十字键 → = 呼叫/搭乘踏板**。
var _pad_holds: Dictionary = {}


func _init() -> void:
	# 丢枪：按住 0.6 s 才算（方案指定）。短按仍然是换弹，各走各的判定。
	# ⚠️ ★63-9 B6：`shield`（T / 手柄 B）那一路已删，见 `_hold_discard_r` 的声明处。
	_hold_discard_r.configure(0.6)
	# 长按 Tab：秒数**必须**从 `InputSetup` 读（与手柄那条同源），
	# 不要在这里写 0.45 —— 那就成了"两个数"，而它们迟早会不一致。
	_hold_add_lock.configure(InputSetup.ADD_LOCK_HOLD_SECS)
	# 手柄的长按二义表：这里只负责**按表建实例**，动作名与秒数都从 `InputSetup` 读，
	# 免得"表里写着 0.6 s、代码里配成 0.45 s"这种对不上的老毛病。
	for trigger: String in InputSetup.PAD_HOLD:
		var h := HoldAction.new()
		h.configure(float(InputSetup.PAD_HOLD[trigger]["secs"]))
		_pad_holds[trigger] = h
	# 手柄 L1 的双模（点按 / 按住自动）**不走 `HoldAction`**：见 `InterceptAuto` 的注释 ——
	# 点按必须"按下即发"，而 HoldAction 是"松手才判定"。阈值是那边的常量，这里不用配。
	# （原来这里有一句 `_hold_threat_pad.configure(0.45)`，而那个变量**从来没有被 tick 过**：
	#  第十五轮清掉了这对"配好了却没接线"的死代码。）
	# 全弹发射**不走 HoldAction**（第十八轮改过一次：先是"长按 F 蓄力"，后来老板定了
	# "用导弹系统模式触发"）—— 它现在由 `missile_mode` 决定右键 / L1 的语义，见那一节。
	# 辅助飞行开关：0.45 s（方案指定）
	_hold_assist.configure(0.45)
## 脱出飞升突进的播报边沿（见 `_tick_escape_feedback`）。
var _escape_announced := false


func setup_refs(lock_sys: LockOnSystem, cam: ChaseCamera) -> void:
	lock = lock_sys
	if is_nu() and lock!=null:lock.auto_engage_limit=0
	camera = cam
	if is_sazabi() and lock!=null:lock.auto_engage_limit=0
	# ---- 军刀相杀（1.2）----
	#
	# `saber_clashed` 是 `FlightBody` 发的；`notice` 只在本类上（HUD 用它弹中央提示），
	# 所以"相杀"那句话必须在这一层接、不能在 `FlightBody` 里直接 emit。
	# ⚠️ 用 `is_connected` 兜一下：`setup_refs` 在 `main` 里可能被重入
	#（`spawn_round()` 会在开局与"回菜单再开一局"两条路上各走一次）。
	if not saber_clashed.is_connected(_on_saber_clashed):
		saber_clashed.connect(_on_saber_clashed)
	# ---- 军刀命中的镜头正反馈（批 10 打击感）----
	#
	# `saber_hit` 也是 `FlightBody` 发的：玩家**砍中**时给一记镜头脉冲
	#（FOV 快扩快收 + 轻抖）。之前镜头只回答"我挨了多少"，不回答"我打中了" ——
	# 砍中时玩家自己也在顿帧里，没有这条的话"砍到了"全靠火花与音效撑。
	# AI 命中不接（`BanditAI` 不走 `setup_refs`，天然只对玩家生效）。
	if not saber_hit.is_connected(_on_saber_hit):
		saber_hit.connect(_on_saber_hit)
	# ---- QB 起跑的"爆冲"反馈（批 11 手感）----
	#
	# `quick_boost_started` 也是 `FlightBody` 发的（只在窗口真的开起来时发）：
	# 起跑那一瞬给一记镜头脉冲 + 喷口爆闪 —— 装甲核心 QB 的突进感一半在
	# "点火的那一帧"，没有反馈的话点按 Shift 只是一条速度曲线。
	if not quick_boost_started.is_connected(_on_quick_boost_started):
		quick_boost_started.connect(_on_quick_boost_started)


## 砍中敌机：镜头正反馈（见 `setup_refs` 里那段说明）。
func _on_saber_hit(_target: Node3D) -> void:
	if camera != null and camera.is_inside_tree():
		camera.add_impact_pulse(1.0)


## QB 起跑（批 11 手感）：镜头一记脉冲 + 尾部喷口爆闪。
##
## 幅度刻意压在受击之下、和军刀命中（1.0）错开 —— 起跑是**正向**反馈，
## 要"脆"不要"重"；方向就是起跑方向（爆闪沿它拉长）。
## 挂 `get_parent()` 与其它 FX 的归宿一致（机体被回收时特效不悬空）。
func _on_quick_boost_started(dir: Vector3) -> void:
	if camera != null and camera.is_inside_tree():
		camera.add_impact_pulse(0.85)
		camera.add_shake(0.28)
	var par := get_parent()
	if par != null:
		var tail := global_position - forward() * (model_bounds.size.z * 0.45)
		FX.qb_burst(par, tail, dir)


## 相杀时的玩家侧反馈：一行中央提示 + 镜头摇一下。
##
## 为什么必须给反馈：相杀的判定比命中**优先**（100 m > 78 m），
## 所以玩家的体感是"我冲上去了、军刀没砍中、还被打飞了" ——
## 不给一句话，那看起来就是**军刀失灵**。
func _on_saber_clashed(_opponent: Node3D) -> void:
	notice.emit("相杀！双方脱锁弹开", 1.6)
	if camera != null:
		camera.add_shake(0.7)
		# 相杀是整局最重的碰撞：抖之外再加一记 FOV 脉冲（批 10 打击感）。
		camera.add_impact_pulse(1.4)


## 每一发浮游导弹离架 —— 给一次镜头轻顶（DESIGN §4.10）。
##
## ⚠️ 覆写 `FlightBody._on_funnel_launch()` 就是"**AI 发弹不抖玩家**"的分界线：
## `fire_funnel()` 是玩家与 AI 共用的，而 `BanditAI` 不覆写这个钩子 ⇒ 天然不抖。
## 若改成在循环里判 `is_player`，AI 那一路迟早会漏（见基类的注释）。
func _on_funnel_launch() -> void:
	if camera != null:
		camera.add_launch_shake(ChaseCamera.LAUNCH_KICK_FUNNEL)


func _think(delta: float) -> void:
	if is_zorin() and is_instance_valid(nu_systems):nu_systems.capture_pilot_input()
	if precision_suit() and (not controls_enabled or not alive): regz_weapons.cancel()
	if not controls_enabled:
		_penelope_shift.reset()
		fm.super_boost = false
		control_input = Vector3.ZERO
		# 平移状态一并清掉：禁控期间不能按最后一份 translate_dir 继续滑行
		translate_mode = false
		translate_dir = Vector3.ZERO
		translate_fwd = Vector3.ZERO
		translate_dash = false
		# 倒飞（★63-9 · D2）也要清：`_read_translate_input()` **不重写**它
		#（它是开关、不是每帧输入）⇒ 不清的话，恢复控制那一帧会带着旧状态继续倒飞。
		translate_reverse = false
		_qb_pending = false
		fm.boosting = false
		fm.hovering = false
		boost_intensity = move_toward(boost_intensity, 0.0, delta * 4.0)
		return

	if debug_input_enabled:
		control_input = debug_input
		fm.throttle = clampf(debug_throttle, 0.0, 1.0)
		fm.boosting = debug_boost
		fm.hovering = debug_hover
		# ⚠️ 这里**不再**硬写 `boost_intensity`：那会让观感在辅助模式下变成"常驻"。
	# 观感统一由 `_apply_flight()` 跟着 `fm.boosting` 缓动（见那里），
	# 于是手动加力与辅助驾驶都会点亮它，退出后自然回落。
		# 调试/截图模式下也允许鼠标摆准星：截图剧本要拍到"准星指着敌机"那一帧，
		# 而 debug 分支不走下面的 `_read_aim_input()`。
		_read_aim_input()
		return

	# ---- 辅助驾驶 · 平移模式路由（2026-09-22）----
	#
	# 开关先于读取：本帧切到什么模式，下面就要按什么模式读输入。
	#   - 辅助开 + **既非阿利宙斯巡航形态、也没骑在板上** → **平移**：
	#     自动加速飞行 + WASD 平移修正 / QE 升降 / Shift 点按闪避
	#     （手柄：左摇杆 / 右摇杆升降 / X 闪避）—— 见 _read_translate_input；
	#   - 其余（辅助关 / 阿利宙斯巡航形态 / **骑飞行踏板**）→ 原有飞行读取，
	#     一字未改（骑板那条例外见 `assist_uses_translation`，2026-09-28）。
	_tick_assist_toggle(delta)
	# ---- 平移模式总开关（**单一写入点**）----
	# ⚠️ 批 8 首版漏了这一行：输入照样读、FlightBody 的 `_apply_translate` 永远进不去，
	# 表现就是"辅助开着，WASD/QE/Shift 按了全没反应"（单测还全绿 —— 测的是纯函数）。
	# ⚠️ `has_pedal()` 必须在这一行就带上：这里是模式的**唯一写入点**，
	# 而下面 `_tick_assist()` / `_apply_flight()` 读的是 `translate_mode` 本身、
	# 不再各自重算判据。以前那种"三处各写一遍 `assist_uses_translation(profile)`"
	# 的写法在加条件时会漏掉一处 —— 漏了不报错，只是骑板时两处口径不一致。
	translate_mode = assist_on and assist_uses_translation(profile, has_pedal())
	# 倒飞开关（★63-9 · D2）：**必须在 `translate_mode` 写完之后** ——
	# 它读的就是刚写好的这个字段（判据同源，不重算）。见 `_tick_reverse_toggle()`。
	_tick_reverse_toggle()
	if translate_mode:
		_read_translate_input(delta)
	else:
		_read_flight_input(delta)
	# ⚠️ 轮 36：这里原来调 `_read_lock_input()`（鼠标罩住谁就锁谁）。整段已删——
	# 锁定对象只能由 Tab（`cycle_target`）与数字键（`select_contact`）发起。
	# `aim_cursor` 仍由上面的 `_input()` 在鼠标移动时记录，准星照常跟着走。
	_tick_contacts()
	_read_aim_input()
	_tick_rifle_aim(delta)
	# 第十五轮：威胁表**先刷新、再读输入** —— 这个顺序不是随便放的：
	# `_read_weapon_input()` 里的手柄拦截要按"此刻最危险的那一枚"出手，
	# 而 `_mark_intercept_missile()` 必须在**同一帧**、**发扳机之后**才武装
	# （跨帧 = 武装到上一次打出的那一发，表现是"偶尔打出一发普通导弹"）。
	_refresh_threats()
	_rifle_input_active = true
	_read_weapon_input(delta)
	_rifle_input_active = false
	_read_view_input()
	_tick_escape_feedback()
	_tick_holds(delta)
	_tick_threats(delta)
	# 辅助驾驶放**最后**：这一帧里任何先前的写入都不会把它盖掉（见 `_apply_flight` 的兜底）。
	_tick_assist(delta)
	_tick_penelope_shift(delta)


func _tick_penelope_shift(delta: float) -> void:
	if not SuitProfile.is_thunderbolt(profile.id) and (profile.id != SuitProfile.Id.PENELOPE or profile.form != 0):
		_penelope_shift.reset()
		return
	var tap: bool = _penelope_shift.tick(delta,Input.is_action_pressed("boost"))
	fm.super_boost = _penelope_shift.super_active and not fm.hovering
	if tap and can_quick_boost():
		if not translate_mode:
			var fwd := -global_transform.basis.z
			translate_dir = fwd*Input.get_axis("pitch_nose_up","pitch_nose_down") + global_transform.basis.x*Input.get_axis("roll_left","roll_right") + Vector3.UP*Input.get_axis("yaw_right","yaw_left")
		request_quick_boost()
	if not translate_mode:
		fm.boosting = fm.super_boost or _qb_pending or _qb_timer > 0.0


## 长按识别（1.2）：**丢弃光束步枪**。
##
## **只剩一个入口**：按住 **R**（= `reload`）0.6 秒。同一个键短按仍然是换弹，
## 不冲突：换弹读的是 `just_pressed`，丢枪要按住。
## 手柄上的等价入口是 **Y**（`PAD_BINDINGS["reload"]`）—— **不是 B**：
## B 是举盾，★63-9 B6 已按用户要求把 `shield` 那一路整条删掉。
##
## ⚠️ **不可逆的动作必须有提示**：这是方案里点名的一条 ——
## “长按 R 换弹的人按久了会误丢枪，没有提示这个改键一定会被骂”。
## 所以过半程就播一句「继续按住将丢弃光束步枪」，松手后重置。
## ⚠️ 提示的进度只跟**丢枪自己那个** `HoldAction` 走。★63-9 B6 之前这里取的是
## `maxf(R, shield)` 两个进度 —— 拿“举盾按了多久”当丢枪的预警，是实打实的误报。
func _tick_holds(delta: float) -> void:
	var r := Input.is_action_pressed("reload") and not is_sazabi() and not SuitProfile.is_thunderbolt(profile.id)
	if _hold_discard_r.tick(delta, r) == HoldAction.Result.LONG:
		_try_discard_rifle()
	var p := _hold_discard_r.progress()
	if p > 0.5 and not _discard_warned:
		_discard_warned = true
		notice.emit("继续按住将丢出盾牌和火箭筒" if is_nu() else "继续按住将丢弃光束步枪", 1.1)
	elif p <= 0.0:
		_discard_warned = false

	# ---- 键鼠：**长按 Tab = 加入锁定组**（批 1 · 多目标锁定）----
	#
	# ⚠️ 与手柄那一支**互斥**：手柄上 `switch_target` 就是十字键 ↑，
	# 而它走下面的 `PAD_HOLD`。两条同时生效会让一次长按触发两次加锁
	#（第二次只是被 `ADD_LOCK_COOLDOWN` 顺手挡掉 —— 那是"恰好没事"，不是设计）。
	# 秒数两边同源（`InputSetup.ADD_LOCK_HOLD_SECS`），见那个常量的注释。
	if not InputSetup.using_gamepad:
		if _hold_add_lock.tick(delta, Input.is_action_pressed("switch_target")) \
				== HoldAction.Result.LONG:
			_try_add_lock()
	else:
		_hold_add_lock.tick(delta, false)

	# ---- 手柄的长按二义（`InputSetup.PAD_HOLD`，2026-09-21 为量产机补的）----
	#
	# 「修复」与「呼叫 / 搭乘飞行踏板」原来在手柄上**根本没有入口**
	#（手柄 17 键全满），而这两件事恰恰是古斯塔夫 / 梅萨的招牌
	#（能骑踏板 + 每场 3 个修复包）。现在按"点按 / 长按分家"补上：
	#   **长按 L3 = 修复** · **长按十字键 → = 呼叫 / 搭乘踏板**
	#
	# ⚠️ 只在 `using_gamepad` 时判定：键鼠上这两个动作有自己的直达键（U / N），
	# 而 `transform` / `switch_weapon` 在键盘上分别是 Z / X —— 不加这道门的话，
	# 键鼠玩家按住 X 切武器 0.6 s 会莫名其妙开始修复。键鼠那一支让计时归零。
	if InputSetup.using_gamepad:
		for trigger: String in _pad_holds:
			var h: HoldAction = _pad_holds[trigger]
			if h.tick(delta, Input.is_action_pressed(trigger)) == HoldAction.Result.LONG:
				_run_pad_hold(str(InputSetup.PAD_HOLD[trigger]["hold_action"]))
	else:
		for trigger: String in _pad_holds:
			(_pad_holds[trigger] as HoldAction).tick(delta, false)


## 执行一条"手柄长按二义"的目标动作（表在 `InputSetup.PAD_HOLD`）。
##
## 用 `match` 而不是把方法名当字符串调用：字符串调用在改名字之后**不会报错**，
## 只会变成"长按了没反应"（本工程对这类静默失败格外警惕）。
func _run_pad_hold(action: String) -> void:
	match action:
		"repair":
			_try_repair()
		"ride_pedal":
			_try_ride_pedal()
		"add_lock":
			_try_add_lock()
		"toggle_fpv":
			# 轮 25：手柄上 17 键全满，视角切换只能挂在"长按回头键"上
			#（点按 Back 仍是按住回头看，见 `PAD_HOLD["look_back"]` 的阈值说明）。
			# 走的是与键盘 F1 **同一个**函数 —— 两条路只有一个状态机。
			Settings.toggle_first_person()
		_:
			push_warning("[PlayerController] 未知的手柄长按动作：%s" % action)


## 长按 Tab（键鼠）/ 长按十字键 ↑（手柄）：把候选表里质量最高的敌机加入锁定组。
##
## 失败必须**说出来** —— "按了没反应"和"按键坏了"在玩家眼里是同一件事，
## 本工程为此栽过多次（见 `_full_salvo_fail_reason()` 的注释）。
func _try_add_lock() -> void:
	if lock == null:
		return
	if lock.add_lock_nearest():
		notice.emit("锁定组 %d/%d" % [lock.lock_group.size(), lock.max_locks], 1.0)
		if camera != null:
			camera.add_shake(0.10)
		return
	notice.emit(_add_lock_reason(), 1.2)


## "为什么加不进锁定组" —— 一句**照着能做**的话。
func _add_lock_reason() -> String:
	if lock == null:
		return "无火控系统"
	if lock.lock_group.size() >= lock.max_locks:
		return "锁定组已满（%d 个）" % lock.max_locks
	return "附近没有已建立航迹的敌机（先用机头对准它）"


## 用掉一个修复包开始修复。**键鼠按 U / 手柄长按 L3 共用这一个入口** ——
## 失败原因必须说出来（"按了没反应"和"按键坏了"在玩家眼里是同一件事）。
func _try_repair() -> void:
	if start_repair():
		return
	if repair_active():
		notice.emit("正在修复中", 0.9)
	elif repair_packs <= 0:
		notice.emit("修复包已用完", 1.2)
	else:
		notice.emit("耐久已满，无需修复", 0.9)


## 呼叫 / 搭乘 / 脱离飞行踏板。**键鼠按 N / 手柄长按十字键 → 共用这一个入口**。
##
## 这两台量产机（古斯塔夫00 / 梅萨M01）的招牌就是能骑板 —— ACE 机不可骑。
func _try_ride_pedal() -> void:
	if has_pedal():
		# 已经在板上 → 这一次算**脱离**（举盾键 T / 手柄 B 也脱离，见 `_read_flight_input`）
		dismount_pedal()
		notice.emit("已脱离飞行踏板", 1.2)
	elif mount_pedal():
		# ⚠️ 提示里的键位**必须按设备换**（`InputSetup.hint`）：手柄上没有"空格"和"T"，
		# 印出来就是让玩家去按一个按不出来的键 —— 第十五轮那类事故。
		notice.emit("已搭乘飞行踏板 · %s = 踏板火神炮 · %s = 脱离"
			% [InputSetup.hint("空格", "R1"), InputSetup.hint("T", "B")], 2.4)
	else:
		notice.emit(pedal_fail_reason(), 1.8)


func _try_discard_rifle() -> void:
	if is_nu():
		nu_systems.discard_equipment()
		return
	if profile == null or not profile.can_discard_rifle:
		notice.emit("本机不能丢弃步枪", 1.0)
		return
	if not discard_rifle():
		notice.emit("没有可丢弃的步枪", 1.0)


## 脱出飞升突进的播报（1.2）。
##
## 提示音必须由**玩家侧**发：`notice` 是 `PlayerController` 的信号，
## `FlightBody` 里没有它（在那里发会直接编译不过）。
## 而且突进期间玩家按什么都没反应，所以这两句话是必须的 ——
## 没有它，玩家的体感是"突然失控 1.25 秒"。
func _tick_escape_feedback() -> void:
	var now := escape_dash_active()
	if now and not _escape_announced:
		_escape_announced = true
		notice.emit("核心脱出 —— 飞升突进", 1.8)
	elif not now and _escape_announced:
		_escape_announced = false
		notice.emit("恢复操作", 1.0)


# ============================================================ 鼠标：只负责准星
#
# 这条路走过了三档，别把中间那档当现状：
#
#   1.1   "鼠标只负责锁定" —— 光标罩住谁就把谁设成锁定目标；
#   轮 36 "**鼠标只管准星**"（用户原话，锁定系统重修的一部分）——
#         锁定对象**只能**由 Tab / 数字键发起，光标飘过去**绝不会**换目标。
#
# 所以这里现在只剩与锁定无关的事：把光标的屏幕位置记下来。
# 它供 `_read_aim_input()` 算弹道方向、供 HUD 画准星、供 `_cursor_missile()` 选拦截目标。
# **它不再驱动 `LockOnSystem`。**

## 关掉之后鼠标完全不参与（无头测试与截图脚本用：它们没有真实鼠标事件，
## 光标恒在 (0,0)，开着的话准星会一直钉在屏幕左上角）。
var mouse_lock_enabled := true
## **来袭飞弹**的拾取半径（像素）。比一般目标大一半 ——
## 用户反馈："调大一些对方导弹的选择框"（框画大了，拾取也要跟着放宽，
## 否则"看得见却点不中"，比框小还难受）。
const MISSILE_PICK_RADIUS := 220.0
## ---- 轮 41：`MOUSE_GAIN` 已删除，这里记一笔它为什么走 ----
##
## 它原来是「准星离屏幕中心多远 = 满偏转」的**操纵杆增益**（0.55），
## 从"鼠标操纵机头"那一版原样带过来，只作用于弹道方向。
## 问题在于**准星不是按它画的**：`hud.gd::_draw_aim_cursor()` 把准星直接画在
## `player.aim_cursor`（原始鼠标像素）上，而增益给出的偏角恒为 `atan(0.55*|m|)`
## （单轴上限 28.81°）—— 两个量只在屏幕中心相等，越往外差得越多。
## 症状就是用户报的「向上发射光束步枪，子弹还是会朝前」。
## 现在弹道方向直接取 `cam.project_ray_normal(aim_cursor)`，与准星像素同源，
## 这个增益没有存在的位置了。取证：`tools/probe_aim_cursor_offset.gd`。
## 最近一次光标的屏幕位置（HUD 画准星、`_read_aim_input()` 算弹道、`_cursor_missile()` 都用它）。
var aim_cursor := Vector2.ZERO
## 这一局里有没有真的收到过鼠标移动事件。
## HUD 靠它决定画不画那个准星 —— 手柄 / 无头测试里没有鼠标，画一个钉在 (0,0) 的圈很难看。
var cursor_seen := false

# ⚠️ **轮 36 删掉的三样东西**，别以为是漏了：
#   · `MOUSE_PICK_RADIUS`（"光标罩住即选中"的半径）
#   · `MOUSE_SWITCH_HYSTERESIS`（换目标的像素迟滞）
#   · `_suppress_mouse_lock`（"数字键点过名 → 鼠标先让位"的跨帧压制）
# 三样全部只为"鼠标选锁定目标"服务，而那件事已经不存在了。
# 数字键仍然走 `select_contact()` → `LockOnSystem.select_target()`，
# 只是不必再"压住鼠标"—— 现在没有第二个写者。


func _input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null and not (is_instance_valid(camera) and camera.is_head_looking()):
		cursor_seen = true
		aim_cursor = mm.position
		_move_precision_free_mouse(mm.relative)
		if precision_free_direction().length_squared() > 0.5:
			aim_cursor = get_viewport().get_visible_rect().size*0.5


## ---- 鼠标准星（1.1：只管"打哪儿"，不管"往哪飞"）----
##
## 用户前后给了两句话，这两句必须**同时**成立：
##   1. "把鼠标调整视角删掉" / "鼠标不影响视角" → 鼠标**绝不碰** `control_input`；
##   2. "光束步枪和火神炮的射击方向跟随鼠标操控的准星" → 鼠标**要**决定 `aim_dir`。
## 所以这里是当年那套 `_apply_mouse_aim()` 的**一半**：只算方向，不打杆。
## 好处是弹道跟着准星走（想打哪打哪），而机头仍然只由键盘/手柄操纵 ——
## 鼠标不会在你压杆的时候把机头拽走。
## 弹道怎么跟着走：`aim_forward()` 在 `aim_dir` 非零时返回它，
## 而 `FlightBody.aim_point()`（炮口交汇点）与 HUD 的准星都读 `aim_forward()`，
## 于是"准星画在哪"和"子弹打向哪"必然一致 —— 这条从第一版就没变过。
func _read_aim_input() -> void:
	# Looking around is head movement, not a new weapon aim command.
	if is_instance_valid(camera) and camera.is_head_looking(): return
	if not mouse_lock_enabled or not cursor_seen:
		set_aim_direction(Vector3.ZERO)
		return
	var vp := get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null:
		return
	var vs := vp.get_visible_rect().size
	if vs.x <= 1.0 or vs.y <= 1.0:
		return
	# 用**已经记下来的光标位置**（`_input` 每次鼠标移动都会更新），
	# 而不是在这里再问一次 `get_mouse_position()`：后者在无头测试里恒为 (0,0)，
	# 会让"准星指哪儿"变成"永远指左上角"，测试根本没法摆准星。
	# ⚠️ **弹道方向 = 相机穿过准星像素的那条射线**（`project_ray_normal`），
	# 不是「把像素偏移乘一个操纵杆增益」。老公式给出的偏角是 `atan(GAIN*|m|)`
	# （单轴上限 28.81°），与鼠标像素**不是同一个量**：屏幕中心两者相等，
	# 越往外差得越多。实测（`tools/probe_aim_cursor_offset.gd`，真 ChaseCamera）：
	#
	#   准星位置                   准星承诺仰角  弹道实际仰角   误差     光束落点/准星
	#   屏幕正上方 (0.50, 0.03)      +30.06°      +20.53°      9.52°      48%
	#   屏幕正左   (0.03, 0.50)       −3.90°       −5.58°     23.75°      30%
	#   左上角     (0.03, 0.03)      +21.60°      +18.84°     21.07°      34%
	#   用户截图那帧 (0.25, 0.331)    +6.62°       +3.27°     16.44°      32%
	#
	# 也就是「准星指到头顶、弹道只抬到一半」，玩家读成"向上发射还是会朝前"。
	# 换成射线之后 `aim_forward()` 与准星像素**同源**：准星画在哪，子弹就打向哪。
	#
	# ⚠️ 副作用要认：可偏角从 ±28.81°（对角 37.88°）放宽到**屏幕角落的射线角**
	#（1600x900 + fov 73 实测约 ±50°）。这是「准星 = 弹道」的必然结果 ——
	# 若哪天觉得偏得太松，要加的是**偏角上限 + 把准星一起夹到同一个上限**，
	# 而不是把这条换回增益（那样两件事又会分家）。
	var ray := cam.project_ray_normal(aim_cursor)
	if ray.length_squared() > 0.25:
		set_aim_direction(ray)


## 轮 36：**这里原来是 `_read_lock_input()`** —— 每帧把光标罩住的敌机设为锁定目标。
##
## 用户口径「鼠标只管准星」之后整段删除：锁定对象只能由
## **Tab 点按**（`cycle_target()`）与**数字键**（`select_contact()`）发起。
## 光标飘过敌机时**什么都不会发生**（HUD 的准星仍然会变色，见 `_draw_aim_cursor()`，
## 那只是"准星指着谁"的读数，不带任何锁定语义）。
##
## 顺带清掉的三样（都只为上面那段服务）：
## `MOUSE_PICK_RADIUS` / `MOUSE_SWITCH_HYSTERESIS` / `_suppress_mouse_lock`。


func _read_flight_input(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_invert"):
		invert_pitch = not invert_pitch
		# 俯仰反转是"操作方案换挡"，同样走系统提示行（不进中央 toast）。
		_system_say("俯仰%s" % ("反转" if invert_pitch else "恢复"))

	var kp := Input.get_axis("pitch_nose_down", "pitch_nose_up")
	if invert_pitch:
		kp = -kp
	var kr := Input.get_axis("roll_right", "roll_left")
	var ky := Input.get_axis("yaw_right", "yaw_left")

	# 键盘 + 手柄摇杆（两者同等对待，都是"主动操纵"）。
	# 1.1 起鼠标不再参与操纵：机头只由这里决定，鼠标只管准星与锁定
	# （准星在 `_read_aim_input()` 里算，它写的是 `aim_dir`，不碰 control_input）。
	var pad := _pad_axis()
	var roll_in := clampf(kr + pad.z, -1.0, 1.0)
	control_input = Vector3(
		clampf(kp + pad.x, -1.0, 1.0),
		clampf(ky + pad.y, -1.0, 1.0),
		_roll_assist(roll_in, delta))

	fm.set_throttle_axis(
		Input.is_action_pressed("throttle_up"),
		Input.is_action_pressed("throttle_down"),
		delta)
	# 手柄油门：右摇杆的 Y 轴（模拟量）。**不能只靠油门键** ——
	# 手柄上原本根本没有油门入口（`[` `]` 是键盘专属），玩家只能卡在出生时的 78%，
	# 既顶不到巡航上限也收不回来。轴上没有任何 `just_pressed` 可言，
	# 所以这里按"偏多少就按比例推多少"处理，和键盘的步进并存。
	var pad_thr := _pad_throttle()
	if pad_thr != 0.0:
		fm.throttle = clampf(fm.throttle + pad_thr * PAD_THROTTLE_RATE * delta, 0.0, 1.0)

	# 悬停优先级高于加速：两个一起按就以悬停为准（避免"既想停又想冲"的歧义）
	var want_hover := Input.is_action_pressed("hover")
	var want_boost := Input.is_action_pressed("boost") and not want_hover
	# 加力**起跑**的一记轻推（批 11 手感）：FOV 由 boost_intensity 渐变（约 0.3 s），
	# 缺的是"点火那一帧"的确认感 —— 一点轻抖就够，别抢受击的戏。
	# 巡航形态辅助也走这里（它 Shift 同时触发超级加速，那边另有一记脉冲）。
	#
	# ⚠️⚠️ **触发必须读按键沿，不许读 `not fm.boosting`**（2026-10-08 用户实测 bug）。
	#
	# 旧写法是 `want_boost and not fm.boosting`，本意是"这一帧刚按下 Shift"，
	# 但 `fm.boosting` 在**同一物理帧稍后**会被 `FlightBody.resolve_jet_gauge()`
	# **改写**（`flight_body.gd:874`：槽空 ⇒ `fm.boosting = jet_active = false`）。
	# ⇒ 量产机（有燃料槽）槽空还按着 Shift 时，这里刚写进去的 `true` 当帧就被压回
	#   `false` ⇒ **下一帧 `not fm.boosting` 又成立** ⇒ `add_shake(0.12)` **帧帧都发**。
	#   抖动池每帧 +0.12（= 7.2/s）远超 `_apply_shake()` 的 2.4/s 线性衰减
	#   ⇒ `_shake` 一路顶死在 **1.4（击坠级上限）** 并停在那儿。用户原话：
	#   「古斯塔夫和梅萨系列这些量产机机体在气槽没气的时候镜头会剧烈晃动」。
	#   ACE 机没有槽，`resolve_jet_gauge()` 在 `flight_body.gd:800` 提前 return、
	#   一个字都不改 `fm.boosting` ⇒ 这条只咬量产机 —— 与用户"只有这些量产机"完全对上。
	# ⇒ 改读 `is_action_just_pressed`：**一按一记**，与槽满槽空无关。
	# ⚠️ 顺带一条正确性：槽空时本来就没点着火，不该给"点火确认"这一记。
	# ⚠️ 别把这条改成"盯 `fm.boosting` 的 false→true 沿" —— 那要跨帧记忆，
	#   而这个函数在 `_think()` 里跑、`resolve_jet_gauge()` 在它之后跑，
	#   读到的永远是"本帧裁决前被覆盖过的值"，正是本次 bug 的形状。
	if Input.is_action_just_pressed("boost") and not want_hover \
			and (not has_jet_gauge() or jet_left > 0.0) \
			and camera != null and camera.is_inside_tree():
		camera.add_shake(0.12)
	fm.hovering = want_hover
	fm.boosting = want_boost
	# 举盾是**按一次**（举 5 秒、冷却 1 秒），不是按住 —— 见 FlightBody.raise_shield()。
	# 所以这里用 just_pressed；按住不放不会续盾。
	#
	# ⚠️ **骑飞行踏板时，同一个 T 改读成"脱离踏板"**（1.2 载具系统）。
	# 举盾在板上本来就不可用（踏板形态禁用军刀与悬停，盾也一样），
	# 所以这个键在骑乘状态下没有别的含义 —— 一钮两义、靠骑乘状态分。
	# （平移模式下也要举盾/脱板 —— 抽成 _read_shield_key()，两条路共用。）
	_read_shield_key()

	var want_intensity := 1.0 if want_boost else 0.0
	boost_intensity = move_toward(boost_intensity, want_intensity, delta * 3.5)


## 举盾 / 骑板脱离（T / 手柄 B）——**飞行读取与平移读取共用的那一段**。
## 平移模式下没有"不举盾"的道理：它是武器/防御动作，与怎么飞无关。
func _read_shield_key() -> void:
	if Input.is_action_just_pressed("shield"):
		if has_pedal():
			dismount_pedal()
			notice.emit("已脱离飞行踏板", 1.2)
		else:
			raise_shield()


# ============================================================ 辅助驾驶 · 平移模式（2026-09-22）

## 辅助驾驶在**这份机体表**上走不走"平移模式"。
##
## 用户原话："辅助驾驶模式开启之后，wasd 键就变为前后左右，qe 就是上升和下降，
## shift 就变为朝着输入方向冲刺，**但是阿利宙斯变形之后的辅助模式依然保持现状**，
## 不过他的 shift 就变成超级加速"。
##
## 所以判据是**形态**而不是机体：阿利宙斯手动变形（Z）进入**巡航形态**后，
## 辅助仍是原来那套"姿态修正 + 常驻加力"，Shift 升级为超级加速（见 _tick_assist）；
## 它的常态 / 核心形态，以及柯西 / 佩涅罗佩 / 两台量产机，辅助全走平移。
##
## ---- 第二条例外：**骑着飞行踏板**（2026-09-28 用户要求）----
##
## 需求原话：「**飞行踏板在辅助驾驶模式下操控方式和阿利宙斯巡航态一样**」。
##
## 为什么它该和巡航形态归到同一档、而不是继续走平移：
##   - 踏板是**载具**，它的全部性格都长在气动上 —— `RIDE_THROTTLE_RESPONSE`
##     （加速 / 减速响应 ×1.45）与 `RIDE_TURN_MUL`（转向 ×0.8）是乘在
##     `fm.accel / fm.pitch_rate` 上的（`apply_pedal_flight_bonus()`），
##     而平移模式**根本不走气动**（`FlightBody._apply_translate()` 直接改
##     `fm.velocity`）⇒ 站在板上却按平移开，等于把踏板的两条特性**全丢掉**，
##     玩家拿到的是一块"什么都不加的板"。
##   - 平移模式的招牌动作是左右冲刺时的**机身转身 360°**（轮 33）。在一块
##     长平台上是"板跟着人一起转"，与"板是载具"的观感直接冲突。
##   - 设定上两者本就是**同一类东西**：都是"高速直冲、转弯吃亏"的形态
##     （那边的 `ARIZEUS_CRUISE_TURN` = 0.62 是同一根轴上的另一档）。
##
## ⇒ 骑板时辅助**保持飞行操纵**（姿态修正 + 常驻加力），Shift = **超级加速**
##   —— 与巡航形态逐字走同一条支路。
##
## ## ⚠️ 它**不是**「这台机骑不骑得了板」的同义词
##
## 触发条件是**此刻真的站在板上**（`FlightBody.has_pedal()`），不是机体属性。
## 所以同一台梅萨：在板上走巡航态那套操纵，按 T 下板立刻回到平移 ——
## 分界两侧读的都是真状态，不靠型号猜，也不需要重开一局。
##
## ⚠️ **写成静态纯函数**：测试不建场景就能钉这条分界（suite_assist_drive）。
## 骑板状态由调用方以参数传进来（`has_pedal()`），它自己**不读场景树** ——
## 教学（`tutorial_director`）与 HUD 也拿它当判据源。
static func assist_uses_translation(p: SuitProfile, riding_pedal := false) -> bool:
	if riding_pedal:
		return false
	if p != null and p.id == SuitProfile.Id.REGZ_CUSTOM and p.form == 1: return false
	return p == null or not (p.id in [SuitProfile.Id.GP03D,SuitProfile.Id.NEUE_ZIEL] or (p.id == SuitProfile.Id.ARIZEUS \
		and p.form == SuitProfile.ArizeusForm.CRUISE))


## 平移模式的每帧输入（辅助开 + 非巡航形态时替代 _read_flight_input）。
##
## ## 键位语义（沿用既有动作名，**不新增 InputMap 动作**）
## 同一颗键在两种模式里语义不同 —— 这是"一钮两义、靠模式分"的老做法
##（T 举盾/脱板、空格火神炮/踏板炮都是先例）：
##   键盘：W 前 / S 后 / A 左 / D 右 / Q 升 / E 降 / Shift 闪避冲刺（点按）
##   手柄：左摇杆 前后左右 / 右摇杆 前推升·后拉降 / X 闪避冲刺
##
## ## 自动飞行（二调 2026-09-22，用户："辅助驾驶模式下依然保持加速飞行啊，自动飞行"）
## 辅助驾驶不是"停下来等输入的开车"——机体**永远以加力极速沿机头自动飞**
##（fm.boosting 意愿恒 true；量产机槽空由 resolve_jet_gauge 裁决，底速退巡航）。
## WASD/QE 只是在底速上**叠加**平移修正（镜头系，权重见 FlightBody.TRANSLATE_OFFSET）：
##   W 推快 / S 收慢 / A·D 横移（机头跟随速度矢量 → 自然压坡转弯）/ Q·E 升降。
##   ⚠️ **W 的推快幅度只有其余方向的 15%**（2026-09-29 用户要求：「辅助驾驶模式下按 w
##   的加速速率下调到 15% 左右」）—— 满杆 W 只比自动飞行底速快约 6.5%；
##   S / A / D / Q / E 的修正权重一个字没动。见 `FlightBody.TRANSLATE_FWD_SCALE`。
##
## ## Shift = 装甲核心式闪避冲刺（**点按**，不按住）
## just_pressed 触发一次 `request_quick_boost()`：方向 = 当前输入方向、没输入朝机头，
## 窗口 / 速度倍数 / 燃料代价全在 FlightBody 的 QB_* 常数。
##
## ## 方向基准用**镜头**不用机头
## "前"必须是屏幕里的前（追尾镜头的水平朝向），否则机体一旦俯冲，
## "W 前"就会把玩家按进海里 —— 开车没有"往车头扎的方向开"这种操作。
## 镜头不可用（无头测试）时退回机体水平朝向。
func _read_translate_input(delta: float) -> void:
	_read_shield_key()
	# 键盘：get_axis(负, 正) —— W 是 pitch_nose_down，所以"前后"取反向轴
	var mv := Input.get_axis("pitch_nose_up", "pitch_nose_down")     # W=+1 前
	var strafe := Input.get_axis("roll_left", "roll_right")          # D=+1 右
	var lift := Input.get_axis("yaw_right", "yaw_left")              # Q=+1 升
	# 手柄：左摇杆 Y 推前是 −1 → 取负成"前"；右摇杆 Y 前推是 −1 → 取负成"升"
	var dev := active_joypad()
	if dev >= 0:
		mv += -_dead(Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
		strafe += _dead(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X))
		lift += -_dead(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y), PAD_DEADZONE_YAW)
	mv = clampf(mv, -1.0, 1.0)
	strafe = clampf(strafe, -1.0, 1.0)
	lift = clampf(lift, -1.0, 1.0)
	var b := global_transform.basis
	if camera != null and camera.is_inside_tree():
		b = camera.global_transform.basis
	var cf := -Vector3(b.z.x, 0.0, b.z.z)
	var cr := Vector3(b.x.x, 0.0, b.x.z)
	# 镜头接近垂直俯仰时水平分量会趋零 —— 退回机体朝向，再不行退回世界轴向
	if cf.length_squared() < 0.0001 or cr.length_squared() < 0.0001:
		cf = -Vector3(global_transform.basis.z.x, 0.0, global_transform.basis.z.z)
		cr = Vector3(global_transform.basis.x.x, 0.0, global_transform.basis.x.z)
	if cf.length_squared() < 0.0001:
		cf = Vector3.FORWARD
	if cr.length_squared() < 0.0001:
		cr = Vector3.RIGHT
	# ⚠️ 保留模拟量（长度 ≤ 1，不再强制归一）：轻推轻移，闪避方向才单独归一
	var axis_f := cf.normalized()
	var want := axis_f * mv + cr.normalized() * strafe + Vector3.UP * lift
	var wl := want.length()
	translate_dir = want if wl <= 1.0 else want.normalized()
	# ★ **W（向前推杆）那一份单独留档**（2026-09-29 用户：「辅助驾驶模式下按 w 的
	#   加速速率下调到 15% 左右」）：速度层要对它单独降档
	#（`FlightBody.TRANSLATE_FWD_SCALE`），而 `translate_dir` 自己语义不变 ——
	#   闪避方向、八向动画、左右冲刺转身判据全都读它，在这里削会连带改掉"冲刺朝哪冲"。
	#   ⚠️ 用**同一个**归一化系数 `wl`：满杆 W+D 时 `translate_dir` 会被归一化，
	#   前向那一份不跟着缩的话，对角输入下 W 的降档比例会被放大成"几乎没降"。
	#   ⚠️ 只有 `mv > 0`（W / 左摇杆推前）算"向前"；S 的负分量留在 `translate_dir`
	#   里走满权重 —— 用户要的是"按 w 的降"，不是"前后一起降"。
	translate_fwd = axis_f * (maxf(mv, 0.0) * (1.0 if wl <= 1.0 else 1.0 / wl))
	# Shift / 手柄 X：**点按**触发闪避（just_pressed；按住不叠加、不重复触发）
	# 冲刺限制条（批 10）：ACE 机条空或 CD 中点按 → 当场给一条原因，
	# 不让玩家在"按了没反应"里猜（与燃料槽空同一条铁律：稀缺资源必须看得见）。
	if Input.is_action_just_pressed("boost") and not ((profile.id == SuitProfile.Id.PENELOPE and profile.form == 0) or SuitProfile.is_thunderbolt(profile.id)):
		if not can_quick_boost():
			# 限制机（ACE）：条空 / CD 中，当场给原因
			if dash_cd > 0.0:
				notice.emit("冲刺能量耗尽 —— 冷却 %.1f 秒" % dash_cd, 1.2)
			else:
				notice.emit("冲刺能量不足", 1.2)
		elif has_jet_gauge() and jet_left <= 0.0:
			# 量产机：槽空时 fm.boosting 会被 resolve_jet_gauge 否掉，
			# 冲刺请求在 _apply_translate 里被静默丢掉 —— 这里补一条原因
			#（判据与 resolve_jet_gauge 的否决门同源：jet_left > 0 才放行）。
			notice.emit("燃料不足，无法闪避", 1.2)
		else:
			request_quick_boost()
	# 机头朝向目标（二调 2026-09-22，用户："不断使玩家机体朝向被锁定的敌方机体"）：
	# 把锁定目标递给 FlightBody，机头在 _apply_translate 里持续转向它。
	if lock != null and lock.target != null and is_instance_valid(lock.target):
		face_target = lock.target
	else:
		face_target = null
	# 姿态输入清零：平移模式不走气动；留着旧值的话，切回巡航/关辅助的那一帧
	# 会让机头突然按最后一次的 WASD 打杆
	control_input = Vector3.ZERO
	fm.hovering = false
	fm.super_boost = false
	# 自动加速飞行：意愿恒 true —— 量产机槽空由 resolve_jet_gauge 裁决；
	# 真正的速度合成（底速 + 修正 + 闪避窗口）在 FlightBody._apply_translate
	fm.boosting = true
	boost_intensity = move_toward(boost_intensity, 1.0, delta * 3.0)


# ============================================================ 手柄

## 摇杆死区（第十四轮 A3）。**这个数是被玩家实测逼出来的**：
##
## 俯仰与滚转是**速率型**轴（`FlightModel._step_attitude` 按 rad/s 积分），
## 于是"摇杆没回正"不是"轻微偏移"，而是**持续转圈**。原来的 0.12 对真实手柄
## 太小了 —— 旧手柄的回中误差普遍在 0.15~0.2，逐帧积分出来的就是
## "手没碰摇杆，机子在滚"。提到 0.20，与本工程既有的
## `PAD_THROTTLE_DEADZONE = 0.22` 同一个量级。
const PAD_DEADZONE := 0.20
## 偏航单独给一档：它是"看那个方向"，不给足会拖手感，而且偏航漂移不会
## 像滚转那样越积越大（偏航不改变任何姿态基准）。
const PAD_DEADZONE_YAW := 0.16

## 滚转回正辅助：松杆多久开始回正 / 回正强度（占满杆的比例）。
const ROLL_LEVEL_DELAY := 0.6
const ROLL_LEVEL_RATE := 0.55
## 小于这个坡度不管（弧度 ≈ 11.5°）：否则平飞时会被数值噪声推来推去。
const ROLL_LEVEL_MIN_BANK := 0.20

## 当前活动手柄编号，没有就返回 −1。
static func active_joypad() -> int:
	var pads := Input.get_connected_joypads()
	return pads[0] if not pads.is_empty() else -1


static func _dead(raw: float, deadzone := PAD_DEADZONE) -> float:
	# 摇杆回中不准是常态，死区见 PAD_DEADZONE 的说明（第十四轮从 0.12 提到 0.20）
	return 0.0 if absf(raw) < deadzone else clampf(raw, -1.0, 1.0)


## 机体**坡度**（弧度）。正 = 左滚（右翼抬起），与 `control_input.z` 同号。
##
## 定义：机体上方向量相对世界上方向偏了多少，符号取在机头轴上。
## 用 `forward()` 而不是世界 -Z，所以俯冲/爬升时这个量依然是"坡度"本身。
func _bank_angle() -> float:
	var up := global_transform.basis.y
	var fwd := forward()
	var s := up.cross(Vector3.UP).dot(fwd)
	var c := Vector3.UP.dot(up)
	if absf(s) < 0.000001 and absf(c) < 0.000001:
		return 0.0
	return atan2(s, c)


## 滚转回正辅助（第十四轮 A3）。返回本帧真正写进 `control_input.z` 的滚转量。
##
## 三条自我约束，缺一条都会变成"摇杆被抢"：
##   1. **玩家在滚就立刻让位**（输入非零 → 空闲计时清零，原样返回）；
##   2. 松杆要满 `ROLL_LEVEL_DELAY` 秒才介入（短暂松杆是正常的操纵动作）；
##   3. 只按**坡度**给一个温和的修正量，坡度小到 `ROLL_LEVEL_MIN_BANK` 就不管。
func _free_roll_cruise() -> bool:
	return profile != null and ((profile.id == SuitProfile.Id.REGZ_CUSTOM and profile.form == 1) \
		or (profile.id == SuitProfile.Id.ARIZEUS and profile.form == SuitProfile.ArizeusForm.CRUISE))


func _roll_assist(roll_in: float, delta: float) -> float:
	if not roll_level_assist:
		_roll_idle = 0.0
		return roll_in
	if absf(roll_in) > 0.001:
		_roll_idle = 0.0
		return roll_in
	_roll_idle += delta
	if _roll_idle < (1.5 if _free_roll_cruise() else ROLL_LEVEL_DELAY):
		return roll_in
	var bank := _bank_angle()
	if absf(bank) < ROLL_LEVEL_MIN_BANK:
		return roll_in
	# 坡度为正（左滚、右翼抬起）→ 要往右滚才能回正，所以取负号
	var want := clampf(-bank / (PI * 0.5), -1.0, 1.0)
	return clampf(roll_in + want * ROLL_LEVEL_RATE * (0.2 if _free_roll_cruise() else 1.0), -1.0, 1.0)


## 摇杆 → 操纵量。
##
## 布局刻意做成"左摇杆 = 俯仰 + 滚转、右摇杆 X = 偏航"：
## 和主机空战游戏一致，也和键盘的 W/S + A/D + Q/E 一一对应。
##
## 符号约定见 FlightModel._step_attitude：x = 俯仰（正 = 抬头）、
## y = 偏航（正 = 左偏）、z = 滚转（正 = 左滚）。
## Godot 左摇杆往上推是 −1，而"推杆低头"是真实操纵杆约定 ——
## 所以俯仰直接用 ly（推前 → −1 → 低头 ✓），滚转/偏航取负。
func _pad_axis() -> Vector3:
	var dev := active_joypad()
	if dev < 0:
		return Vector3.ZERO
	var lx := _dead(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X))
	var ly := _dead(Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
	var rx := _dead(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), PAD_DEADZONE_YAW)
	return Vector3(ly, -rx, -lx)


## 手柄油门的推杆速率（满偏时每秒变化的油门比例）。
## 约 1.1 秒从 0 推满，和键盘 `[` `]` 的 0.85/s 是同一个量级。
const PAD_THROTTLE_RATE := 1.0
## 油门死区。比操纵的死区大一点：右手拇指同时还要管偏航，
## 一点点漂移就让油门自己爬会很烦。
const PAD_THROTTLE_DEADZONE := 0.22


## 右摇杆 Y → 油门量（−1 收 / +1 加 / 0 不动）。
##
## Godot 约定：摇杆**往上推是 −1**，而"推上 = 加油门"，所以取负号。
func _pad_throttle() -> float:
	var dev := active_joypad()
	if dev < 0:
		return 0.0
	var raw := Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y)
	if absf(raw) < PAD_THROTTLE_DEADZONE:
		return 0.0
	return clampf(-raw, -1.0, 1.0)


# ============================================================ 武器

## 读武器与拦截的输入。
##
## `delta` 只有**手柄的拦截状态机**用得上（`InterceptAuto.update()` 要累计按住了多久），
## 其余每一条都是边沿/持续判定，不看 delta。
# ---- 左键"松手发射 + 蓄力"（阿利宙斯常态 / 巡航；2026-09-28 用户指定）----
#
# 用户原话：「阿利宙斯的开枪逻辑从**按下鼠标发射**变为**松开鼠标发射**」，
# 以及「光束步枪模式下长按鼠标左键 1.7s 进入蓄力模式，蓄力模式可以一直蓄力
# （伤害和光束大炮的时间不变），松手会释放一发……超级激光炮」。
#
# ⚠️ 这三件事是**一条链**、不能拆开做：
#   ① 按下不开火  →  ② 按满 1.7 s 时弹匣仍然是满的（大炮的硬门槛）
#                →  ③ 松手时按"有没有进蓄力"决定放炮还是打普通一发
# 若做成"按下先打一发、按满再进蓄力"，①就没意义了，而 ② 永远不成立
# （常态/巡航的弹夹只有 2 发，打掉一发就不满）。
#
# ---- 2026-09-29：佩涅罗佩也拿到这门炮，但**只有她**是"条件路由" ----
# 用户：「把阿利宙斯的光束大炮也给佩涅罗佩」＋ 拍板「**保住连发**」。
# 所以上面这条链对她**只在"按下那一刻 `cannon_ready()`"的那一次按住里**启用；
# 其余按次一个字节都不走这里、逐帧走老路按住连发 —— 见 `rifle_press_route()`。
##
## 左键已经按住了多久（秒）。
var _fire_hold := 0.0
## 是否已经进入蓄力态（按住满 `cannon_charge_time` 且当时 `cannon_ready()`）。
var _cannon_charging := false
## 进入蓄力之后又蓄了多久（秒）。**只喂给 HUD 的脉冲动画** ——
## 用户点名"伤害和光束大炮的时间不变"，所以它不许参与任何数值。
var _cannon_charged := 0.0
## 这一按次是否已经提示过"为什么蓄不了"（防止按住不放时每帧刷屏）。
var _charge_denied := false

## **这一按次左键走哪条路**的锁存值。只由 `latch_rifle_route()` 写。
##
## `true` = 走"蓄力 / 松手发射"那条；`false` = 走老路"按住连发"。
##
## ⚠️ 它是**锁存**的、不是每帧重算的：`cannon_ready()` 会随弹匣 / 冷却 / 过热
## 逐帧变化，逐帧重判会让一个"按下时能蓄力"的按次在弹匣被换满的那一刻
## **突然开始连发**（玩家按着不动、枪自己响了）—— 而那时他已经在蓄力态里了。
var _rifle_press_cannon := false


## 按下那一刻该走"蓄力 / 松手发射"那条路吗？
##
## **纯函数** —— 不读 Input、不改任何状态，所以判定与负对照都能直接单测。
##
## ## 两种"有大炮"的机体（组合语义见 `SuitProfile.rifle_fire_on_release` 的注释）
##   · 阿利宙斯常态 / 巡航：`rifle_fire_on_release` 为真 ⇒ **恒**走松手路；
##   · 佩涅罗佩（2026-09-29 用户：「把阿利宙斯的光束大炮也给佩涅罗佩」）：
##     只有 `cannon_enabled` 为真 ⇒ **"按下这一刻 `cannon_ready()`"** 才走蓄力路，
##     其余按次照旧按住连发 —— 用户拍板选的就是这个：她的步枪是
##     1 门 / 6 发 / 0.82 s 的洒水枪，"松手单发"会把连射废掉。
##
## ## ⚠️ 为什么必须在这里判、而且只在按下那一帧判
## 老路**每帧**都在打，第一发就把弹匣打掉 ⇒ 到 1.7 s 时 `cannon_ready()` 的
## "弹夹全满"永远不成立 —— **大炮结构上放不出来、而且不报错**（静默失败）。
func rifle_press_route() -> bool:
	if profile != null and profile.id in [SuitProfile.Id.NEUE_ZIEL,SuitProfile.Id.SAZABI]:
		return false # Belly cannon has its own slot; rifle triggers retain normal fire.
	if profile == null:
		return false
	if profile.rifle_fire_on_release:
		return true
	return profile.cannon_enabled and cannon_ready()


## 取一次路由并**锁死整个按次**（同一按次里再调只有 `press_frame` 为真的那次会生效）。
##
## ⚠️ `press_frame` 是**参数**，不在这里直接读 `Input.is_action_just_pressed`：
## 无头回归里 `just_pressed` 的帧戳**实测不可靠**（`tutorial_director.gd:47` 有实测
## 记录：连续注入 40 次一次都不触发）⇒ 直接读的话本函数在测试里恒不执行，
## 判据会退化成"永远走老路"的假绿。生产调用方只有一处（`_read_weapon_input()`），
## 传的就是真实的 `Input.is_action_just_pressed("fire_primary")`。
func latch_rifle_route(press_frame: bool) -> void:
	if not press_frame:
		return
	_rifle_press_cannon = rifle_press_route()


## 这一按次锁定的路由（只读；写入点只有 `latch_rifle_route()`）。
func rifle_press_is_cannon() -> bool:
	return _rifle_press_cannon


func _read_release_rifle(delta: float, target: Node3D) -> void:
	if Input.is_action_just_pressed("fire_primary"):
		_fire_hold = 0.0
		_cannon_charging = false
		_cannon_charged = 0.0
		_charge_denied = false

	if Input.is_action_pressed("fire_primary"):
		_fire_hold += delta
		if not _cannon_charging and not _charge_denied \
				and _fire_hold >= profile.cannon_charge_time:
			if cannon_ready():
				_cannon_charging = true
				notice.emit("蓄力 —— 松手发射", 1.2)
			else:
				# 只在"按住够了却蓄不了"的那一刻说一次原因。
				# 不提示的话玩家只会觉得"按了没反应"——本工程为这类静默失败栽过多次。
				_charge_denied = true
				notice.emit(cannon_blocked_reason(), 1.6)
		if _cannon_charging:
			_cannon_charged += delta

	if Input.is_action_just_released("fire_primary"):
		if _cannon_charging:
			if not fire_cannon(target):
				notice.emit(cannon_blocked_reason(), 1.4)
			# 抖动在 `_on_cannon_fired()` 里（`fire_cannon()` 会调它）——
			# 让"打出去了"和"镜头震"成对发生，而不是在这里再判一次成功与否。
		elif current_slot() == "rifle" and not profile.cannon_only:
			_shoot_rifle_now(target)
		else:
			notice.emit("按住左键蓄力大炮",0.8)
		_fire_hold = 0.0
		_cannon_charging = false
		_cannon_charged = 0.0
		_charge_denied = false


## 松手/点按打一发普通光束。**与老的"按住连发"分支逐条对齐**
##（弹匣门槛、提示文案都同一套），只是触发时机从"按下"挪到"松手"。
func _shoot_rifle_now(target: Node3D) -> void:
	if rifle_count <= 0:
		notice.emit("步枪已全部丢弃", 1.4)
		return
	if rifle_mag <= 0:
		notice.emit("自动换弹中…", 1.4)
		return
	if fire_beam(true, target):
		# N49：射击动作（`shoot`）。**只在真的打出光束之后** —— 上面那两条早退
		#（枪全丢了 / 弹匣空）按键不该有动作，与 `raise_shield()` / `try_saber()` 同一口径。
		#
		# ⚠️ 刻意与镜头震动**分开写**，不并进原来那条短路表达式：
		#   `if fire_beam(...) and camera != null:` —— 把动作塞进去会在
		#   `camera == null`（探针场景就没有 camera）时**静默不播动作**。
		#
		# ★ N56：`can_stow = true` = 声明"这一下是**火器**，打完之后如果一段时间不再打，
		#   就该收枪（倒放 ＋ 归位）"。军刀 / 举盾 / 变身那几条**不声明** ⇒ 行为逐位不变。
		#   ⛔ 别把 `can_stow` 做成默认 `true`：那样拿刀砍完也会走收枪流程
		#     （而 `FormWeld` / 归位段只管形态，不管"刀该不该收"）。
		play_model_action("shoot", true)
		if camera != null:
			camera.add_shake(0.22)


func _on_gp03s_escape() -> void:
	weapon_index = 0
	_fire_hold = 0.0
	_cannon_charging = false
	_cannon_charged = 0.0
	_rifle_press_cannon = false
	_full_salvo_left = 0

func _cancel_cannon_charge() -> void:
	if _cannon_charging:
		notice.emit("蓄力中断", 0.9)
	_cannon_charging = false
	_cannon_charged = 0.0
	_fire_hold = 0.0
	# ⚠️ **刻意不重置 `_rifle_press_cannon`**：路由是"这一按次"的属性。
	#   在这里清掉的话，阿利宙斯会在蓄力被取消之后（比如变形 / 硬直那一瞬间）
	#   **中途切进老路** ⇒ 玩家按着不动、枪自己开始连发 —— 那不是他要的。
	#   锁存值只在下一次"刚按下"时被 `latch_rifle_route()` 改写。


## 蓄不了的原因（给玩家看的一句话）。**与 `cannon_ready()` 的每一条门禁一一对应** ——
## 加了一条新门禁却忘了在这里说，玩家就只会看到"按了没反应"。
func cannon_blocked_reason() -> String:
	if not cannon_available():
		return "本形态没有蓄力激光炮"
	if cannon_cd_left > 0.0:
		return "大炮冷却 %.1fs" % cannon_cd_left
	if rifle_reloading and profile.id not in [SuitProfile.Id.GP03D,SuitProfile.Id.NEUE_ZIEL,SuitProfile.Id.SAZABI]:
		return "步枪过热中 —— 还要 %.1fs" % reload_timer
	if rifle_mag < profile.rifle_magazine and profile.id not in [SuitProfile.Id.GP03D,SuitProfile.Id.NEUE_ZIEL,SuitProfile.Id.SAZABI]:
		return "弹夹不满 —— 大炮只能在满弹夹时使用"
	return "现在放不出蓄力炮"


## 按住左键的进度 0..1（相对 `cannon_charge_time`）。HUD 画"快进蓄力了"的那个环。
func cannon_hold_ratio() -> float:
	if profile == null or profile.cannon_charge_time <= 0.0:
		return 0.0
	return clampf(_fire_hold / profile.cannon_charge_time, 0.0, 1.0)


## 是否已经在蓄力态（松手就会放炮）。
func cannon_charging() -> bool:
	return _cannon_charging


## 蓄力开始之后过了多少秒。**只给 HUD 的脉冲用**，不参与任何数值。
func cannon_charged_seconds() -> float:
	return _cannon_charged


## 覆写 `FlightBody._on_funnel_launch()` 那一套：**只有玩家拿得到 `camera`**。
## 蓄力激光炮是这台机最重的一发，抖动给到 0.90（军刀吸附 0.45 / 榴弹 0.40 作参照）。
func _on_cannon_fired() -> void:
	if camera != null:
		camera.add_shake(0.90)


func grapple_charge_route() -> bool:
	return current_slot() == "ram" and profile.id == SuitProfile.Id.GP03D and (is_instance_valid(active_grapple) or _fire_hold > 0.0 or _cannon_charging)


func _read_weapon_input(delta: float) -> void:
	if thunderbolt_systems!=null:
		thunderbolt_systems.input(delta);return
	if is_zorin() and nu_systems!=null:
		nu_systems.input(delta)
		return
	if is_sazabi() and sazabi_systems!=null:
		sazabi_systems.input(delta)
		return
	if weapons_locked():
		_cannon_charging = false
		_fire_hold = 0.0
		return
	if precision_suit():
		regz_weapons.tick(self,delta,Input.is_action_pressed("fire_secondary"),Input.is_action_pressed("fire_primary"),Input.is_action_just_pressed("fire_primary"))
	var target: Node3D = lock.target if lock != null else null
	# 全弹发射的冷却与分批节拍：**每帧都要走**（和按没按键无关），所以放在最前面
	_tick_full_salvo(delta)
	# 腕部榴弹炮：装填计时 + **备弹的懒初始化**（每匣 5 发，打空自动装填，见 `SuitProfile.grenade_count`）。
	# ⚠️ 初始化要**每帧检查**，不能只在切武器时做：玩家一辈子不切武器的话，
	# 榴弹那一格会一直显示"已打空"—— 那是假的，而且很难查。
	if not _grenade_init and profile != null:
		_grenade_init = true
		grenade_count = profile.grenade_count

	# --- 鼠标左键：光束步枪 ---
	#
	# 这里分成两条路，**由机体表决定**（`SuitProfile.rifle_fire_on_release` 与
	# `SuitProfile.cannon_enabled`，组合语义见前者的字段注释）：
	#
	#   · 老路（绝大多数机体）：**按住就连发**。下面那个 `elif` 一个字都没动。
	#   · 阿利宙斯常态 / 巡航：**松开才发射**，且按住满 1.7 s 进蓄力
	#     （用户 2026-09-28 指定）。见 `_read_release_rifle()`。
	#   · 佩涅罗佩（2026-09-29）：**只有"按下那一刻 `cannon_ready()`"的那一次按住**
	#     走上面那条；其余按次落回老路，按住照旧连发（用户拍板「保住连发」）。
	#
	# ★ 路由**只取一次、整个按次锁死** —— 见 `latch_rifle_route()`。
	#   放在槽位判断**之外**：任何一次"刚按下"都重取路由，免得
	#   "在军刀槽上按住、再切回步枪"这种按次吃到上一次的陈旧锁存值。
	latch_rifle_route(Input.is_action_just_pressed("fire_primary"))
	if profile.id == SuitProfile.Id.GP03D and is_instance_valid(active_grapple) and active_grapple.attached:
		# A successful ram already lines up the muzzle: no charging or weapon switch.
		_fire_hold = 0.0
		_cannon_charging = false
		_cannon_charged = 0.0
		_charge_denied = false
		if Input.is_action_pressed("fire_primary") and cannon_ready():
			fire_cannon(active_grapple.victim)
	elif current_slot() == "cannon" or grapple_charge_route():
		var charge_target: Node3D = active_grapple.victim if is_instance_valid(active_grapple) and current_slot() == "ram" else target
		_read_release_rifle(delta,charge_target)
	elif current_slot() == "rifle" and not precision_suit():
		if _rifle_press_cannon:
			_read_release_rifle(delta, target)
		elif Input.is_action_pressed("fire_primary"):
			if rifle_count <= 0:
				if Input.is_action_just_pressed("fire_primary"):
					notice.emit("步枪已全部丢弃", 1.4)
			elif rifle_mag <= 0:
				if Input.is_action_just_pressed("fire_primary"):
					notice.emit("自动换弹中…", 1.4)
			elif fire_beam(true, target):
				# ★★★ N57：**老路也要播 `shoot`** —— 这一行修的是「开枪时手臂完全不动」。
				#
				# 此前全工程**只有**阿利宙斯（`profile.rifle_fire_on_release == true`）那条路
				# 会播动作：`_read_release_rifle()` → `_shoot_rifle_now()` → `play_model_action()`。
				# 而老路（按住连发；该字段**默认 `false`**，**柯西走的就是这条**）从头到尾
				# 一个动作调用都没有 ⇒ 玩家按左键**打得出光束、HUD 弹匣在减、但手臂一动不动**。
				#   ⛔ 这**不是**"动作没装"：`shoot` 段在引擎里、`request_action()` 也接得对，
				#     缺的只是**老路这一条分支里的调用点**（T27「可播 ≠ 会播」的第二次踩：
				#     调用方存在，但只存在于**另一条分支**）。
				#
				# ⚠️ 必须与 `camera` 判空**拆开写**（原代码是 `fire_beam(...) and camera != null`）：
				#   动作若塞进同一条短路表达式，`camera == null`（探针 / 无镜头场景）时
				#   会**静默不播动作** —— 与 `_shoot_rifle_now()` 里那条注释是同一个坑。
				#
				# `can_stow = true` 的语义（N56）："这是火器，打完一段时间不再打就收枪"。
				#   ⛔ 不会外溢到别的机体 —— `ModelAnimFSM._stow_eligible()` 要求
				#     `_want_form == Form.CRUISE` **且** `anim.has_cruise_hold()`，
				#     而只有柯西建得出巡航归位段 ⇒ 其余五台的收枪逻辑**早退**、行为逐位不变。
				#   ⛔ 军刀 / 举盾 / 变身那几条**不声明** `can_stow`（拿刀砍完不该走收枪流程）。
				#
				# ⚠️ 连发时的重播语义：`fire_beam()` 在 `rifle_cooldown > 0` 时**早退 false**
				#   ⇒ 本分支只在"这一帧真打出一发"时进入（天然是**事件**，不是每帧）。
				#   柯西 `rifle_interval` = 0.78 s > `shoot` 段长 0.400 s ⇒ 每发都自然重播。
				play_model_action("shoot", true)
				if camera != null:
					camera.add_shake(0.22)

	if current_slot() == "bazooka" and not is_nu() and Input.is_action_pressed("fire_primary"):
		if fire_gp03s_bazookas(target) and camera != null:
			camera.add_shake(0.38)

	if current_slot() == "wire" and Input.is_action_just_pressed("fire_primary"):
		if not fire_wire_arms(target):
			notice.emit("线控臂：锁定6km内目标 · 冷却%.0fs" % ceilf(wire_cd_left),1.1)

	# --- R：光束步枪换弹 ---
	if Input.is_action_just_pressed("reload") and (profile.id == SuitProfile.Id.GP03D or (profile.id == SuitProfile.Id.GP03S and current_slot() == "bazooka")):
		reload_bazooka()
	if is_nu() and current_slot() == "bazooka" and Input.is_action_just_pressed("reload"):
		nu_systems.reload_bazooka()
	if Input.is_action_just_pressed("reload") and not profile.cannon_only and (profile.id != SuitProfile.Id.GP03S or current_slot() == "rifle") and not (is_nu() and current_slot()=="bazooka"):
		if rifle_count <= 0:
			notice.emit("没有步枪可换弹", 1.2)
		elif rifle_mag >= profile.rifle_magazine:
			notice.emit("弹匣已满", 0.9)
		elif reload_rifle():
			notice.emit("换弹中…", 0.9)

	# --- X 短按 / 十字键 → / R2 短按：**切换武器**（光束步枪 ↔ 光束军刀）---
	#
	# ⚠️ 这一段是我漏掉的**调用点**：上一轮我把 `switch_weapon()` 与键位都写好了，
	# 却没有在输入循环里读那个动作 —— 方法成了死代码，表现就是
	# "按 X 没反应、切不到军刀"，而右键又已经给了导弹拦截，**军刀因此完全无法使用**
	# （用户实测："没法砍啊，因为现在键位是冲突的"）。
	# 教训：**绑了键一定要有读取点**，否则等于没做。
	if Input.is_action_just_pressed("switch_weapon"):
		switch_weapon()
	# 形态边界 / 武器不在手：核心形态没有军刀、古斯塔夫打光榴弹 ——
	# 还停在那件武器上会让左键突然没反应，所以**自动退到步枪**
	#（比"左键失灵"这种无声的失败好）。
	if current_slot() != "rifle" and not slot_available(current_slot()):
		weapon_index = 0
	# 蓄力途中被切走 / 形态变了 ⇒ **取消**（不然松手时会打出一发玩家没在瞄的炮）。
	if _cannon_charging and ((current_slot() not in ["rifle","cannon"] and not grapple_charge_route()) or not cannon_available()):
		_cancel_cannon_charge()

	# --- 鼠标左键（当前武器 = 腕部榴弹炮）：**古斯塔夫00 专属**（1.2 第二十六轮）---
	#
	# 老板："给古斯塔夫加入新武器，腕部榴弹炮，备弹 5 发，伤害 70。"
	# 它走**当前武器**这条线（R2 / 鼠标左键），不新增按键 —— 手柄 17 个入口全满。
	# 弹药计数在**玩家侧**（`grenade_count`）：它是每匣 5 发，打空自动装填的挂载弹药，
	# 不随换弹恢复，也不该被 AI 的武器逻辑牵连。
	if current_slot() == "grenade" and Input.is_action_just_pressed("fire_primary"):
		if grenade_count <= 0:
			notice.emit("榴弹自动装填中…", 1.4)
		elif _grenade_cd > 0.0:
			notice.emit("榴弹装填中…", 0.6)
		elif fire_grenade(target):
			if camera != null:
				camera.add_shake(0.40)
			notice.emit("腕部榴弹炮 · 剩 %d 发" % grenade_count, 1.0)

	# --- 鼠标左键（当前武器 = 光束军刀）：劈砍（带吸附）---
	#
	# 1.2 用户要求："武器切换之后，能选择鼠标左键使用的是光束步枪还是光束军刀"。
	# 所以左键是"**使用当前武器**"，而不是"固定步枪"；军刀从右键搬到这里。
	if current_slot() == "ram" and not grapple_charge_route() and Input.is_action_just_pressed("fire_primary"):
		if try_gp03_grapple(target):
			notice.emit("冲撞抓取 · 按住左键蓄力，松开发射", 1.3)
			if camera != null:
				camera.add_shake(0.45)
		else:
			notice.emit("冲撞：目标需在1.3km内，等待冷却", 1.0)

	if current_slot() == "saber" and Input.is_action_just_pressed("fire_primary"):
		if not profile.has_saber:
			notice.emit("本形态没有光束军刀", 1.4)
		else:
			var magnet := target != null and lock != null and lock.locked \
				and lock.range_to_target() <= profile.player_saber_magnet
			if try_saber(target):
				if magnet and camera != null:
					camera.add_shake(0.45)
					notice.emit("军刀吸附突进", 0.8)
			elif saber_cooldown > 0.0:
				notice.emit("军刀冷却中", 0.7)

	# --- 鼠标右键 / 手柄 L1：**专职拦截来袭飞弹**（1.2；第十五轮接上了手柄那一路）---
	#
	# 同一个动作 `fire_secondary`，两种设备**两种读法**（判据 `_intercept_pad_mode()`）：
	#
	#   **键鼠**：点中飞弹的框 → 选中它 **并立刻发射**（用户原话："鼠标右键直接负责
	#   拦截导弹的选择"、"按下鼠标右键选中要拦截的对象之后直接发射导弹"）。
	#   这一段**第十五轮一个字都没改**。
	#
	#   **手柄**：没有指针可点 —— 硬要它"点在框上"就是让玩家必然失败。
	#   所以目标由系统按 TTI 选，玩家只决定"什么时候打"：
	#   **点按 = 拦一发；按住 = 自动拦（每秒 2 枚，专打最危险的、还没被咬住的）**。
	#   见 `_tick_pad_intercept()`。
	#   ⚠️ 它必须**每帧都跑**（松手那一帧要靠它归零），所以不能塞进 `just_pressed` 里面。
	# ⚠️⚠️ **第十八轮：这两个入口干什么，由"导弹系统模式"决定**（用户指定）——
	#   拦截模式     → 右键 = 选中并发射拦截弹；L1 = 拦一发 / 按住自动拦（原行为）
	#   全弹发射模式 → 右键 / L1 = **一次 100 发**（**30 s** 冷却，见 `FULL_SALVO_COOLDOWN`
	#   与 `fire_full_salvo`；这里原写"20 s"，与常量 `30.0` 对不上，★63-23 顺手更正）
	# 所以这一段不能再"只按设备分流"，必须先看模式。
	var want_full := missile_mode == MissileMode.FULL_SALVO or profile.id in [SuitProfile.Id.GP03D,SuitProfile.Id.NEUE_ZIEL]
	# ⚠️ **不走手柄拦截分支 ⇒ 状态机必须收尾**（★63-23）：
	#   `_tick_pad_intercept()` 是**唯一**会归零 `_intercept_auto` 的地方，而它只在
	#   "手柄 + 拦截模式"下被调。于是玩家**按住 L1 进了自动拦截之后**，只要
	#   ① 鼠标被碰一下（`InputSetup` 切回键鼠）或 ② 按十字键 ← 切到全弹发射模式，
	#   它就再没人调 ⇒ `active` **卡在 true** ⇒ HUD 永远显示"自动拦截 ON"（**假状态**），
	#   `_was_pressed` 也一起留着 ⇒ 下次真按住时"按下沿立刻一发"会丢掉。
	#   收尾**走的就是"松手那一帧"那条原始路径**（`update(0, false, false)`）——
	#   不新增 API、不新增一条要维护的清状态分支。
	var pad_intercept := _intercept_pad_mode() and not want_full and profile.id != SuitProfile.Id.NEUE_ZIEL
	if not pad_intercept:
		_intercept_auto.update(0.0, false, false)
	if precision_suit():
		pass
	elif profile.id == SuitProfile.Id.NEUE_ZIEL:
		if Input.is_action_just_pressed("fire_secondary"):
			if not fire_wire_arms(target):
				notice.emit("线控炮：锁定6km内目标，等待冷却", 1.0)
	elif pad_intercept:
		_tick_pad_intercept(delta)
	elif Input.is_action_just_pressed("fire_secondary"):
		if want_full:
			_fire_full_salvo_or_notice(target)
		else:
			var picked := _cursor_missile()
			if picked != null:
				_select_threat_node(picked)
				_intercept_pending = picked
				_intercept_requested = true
				_autofire_intercept = true
			else:
				notice.emit("右键要点在来袭飞弹的框上", 0.9)

# --- U：开始修复（1.2 用户要求："按 u 键开始修复机体，每次战斗三个修复包"）---
	# ⚠️ 手柄上**没有 U**，走的是"长按 L3"（见 `_tick_holds` 与 `InputSetup.PAD_HOLD`）。
	if Input.is_action_just_pressed("repair"):
		_try_repair()

	# --- 空格：火神炮 ---
	#
	# ⚠️ **骑板时这一颗键改打"踏板的火神机枪"**（1.2 用户指定：
	# "空格在骑板时改成踏板火神炮"）。一钮两义、靠骑乘状态分 ——
	# 和 `T`（举盾 / 骑板时=脱离）、`A`（确认 / 长按辅助）是同一套做法。
	#
	# 为什么不是"两门炮一起打"：用户的分工是"**领队机操控踏板、另一台负责踏板的武器**"，
	# 而玩家操控的总是领机 —— 所以骑板时他的空格给踏板那门炮，
	# 自己机体那门交给僚机/后台（`FlightPedal.gun_operator()`）。
	if Input.is_action_pressed("fire_gun"):
		if has_pedal():
			if fire_pedal_gun(true, target) and camera != null:
				camera.add_shake(0.10)
		elif fire_gun(true, target) and camera != null:
			camera.add_shake(0.07)

	# --- N：载具系统 —— 呼叫 / 搭乘飞行踏板 ---
	#
	# 用户：「踏板要有搭乘键和脱离键，类似载具系统。按键还能呼叫飞行踏板到自己的位置来」。
	# 搭乘与呼叫合成一个动作（"我要上板"）：失败时把原因播出来，
	# 否则玩家（尤其是开着 ACE 机的那种）会以为"按了没反应"。
	if Input.is_action_just_pressed("ride_pedal"):
		# ⚠️ 手柄上**没有 N**，走的是"长按十字键 →"（见 `_tick_holds`）—— 这一条
		# 就是"把古斯塔夫和梅萨做手柄适配"的核心：能骑板是它们的招牌。
		_try_ride_pedal()

	# --- F：**就是发射导弹**；辅助驾驶下打出的那一发是"可对撞"的（1.2 用户澄清）---
	#
	# 语义**不再由"选没选中威胁"决定** —— 那会把 F 变成两个键。
	# 现在由**辅助驾驶**决定：关着 = 浮游导弹；开着 = 这一发能对撞（拦截）。
	# ⚠️ 这里**不再生成独立的 Interceptor 节点**：拦截就是这一发导弹自己的
	# 对撞判定（见 `Missile._check_intercept`），"用发射的导弹和对面的导弹对撞"
	# 才是用户要的效果。原来的 `fire_interceptor()` 已经删掉。
	if assist_on and Input.is_action_just_pressed("fire_missile") and selected_threat() != null:
		# 辅助驾驶下按 F 也能拦：目标就是"当前选中"（键盘 B 选的那一个，或手柄点按 L1 选出来的）。
		# ⚠️ 必须**显式写进 `_intercept_pending`** —— 武装那一步（`_mark_intercept_missile`）
		# 已经不再读全局选中状态了，见那里的注释。
		_intercept_pending = selected_threat()
		_intercept_requested = true
		if camera != null:
			camera.add_shake(0.12)
	# --- F：浮游导弹（核心形态没有导弹，门禁读 profile.has_missiles）---
	# `_autofire_intercept`：右键点中飞弹之后的"立刻发射"——走同一条路径，
	# 于是门禁（有没有导弹 / 有没有锁定）与标记逻辑都只有一份。
	#
	# ⚠️ **本次扳机之后压多长的冷却**（批 26，2026-09-22 用户指定）：
	# 「拦截飞弹开枪间隔和浮游飞弹**一样**」——
	#   · **非自动路径**（点按 F / 右键 / 长按 F）：**不传**（-1）→ 走通用发射器冷却
	#     `profile.funnel_interval`（0.42 s），与浮游飞弹**完全同一条闸**。
	#     （批 21 曾改成 CD = 0，结果长按 F 每帧过闸、一秒泼出去一堆 —— 就是那条被撤回。）
	#   · **自动拦截路径**（手柄长按 L2/L1）：传 0、节奏由状态机 `SHOT_INTERVAL`（0.42 s）
	#     管。不能走通用冷却 —— 扳机整拍落在 0.42 s 上，与冷却归零是浮点赛跑，
	#     输一次就 `_blocked` +1、两次就放弃自动模式（历史教训：第十五轮的 0.16 专用冷却）。
	# ⚠️⚠️ 判据**只能是 `_intercept_auto_shot`（"这一发来自自动整拍"）**，
	#   不许再写 `_intercept_auto.active`（"自动模式开着"）—— 那会把
	#   **`fire_missile` 那一支的手动按住**也变成零冷却 ⇒ 每帧一梭（★63-23 实测）。
	# AI 仍传自己的 `ai_cd`（bandit_ai 内），不受影响。
	var salvo := 0.0 if _intercept_auto_shot else -1.0
	# ⚠️ 第十八轮**取消**了"长按 F / L2 = 全弹发射"这条：全弹发射现在由**导弹系统模式**
	# 决定（切到该模式后，鼠标右键 / L1 就是它）—— 见上面那一段。
	# 留着两条触发路径只会让"按住 F 到底会发生什么"变得说不清（而且它与"点按=普通一梭"共键）。
	if is_nu() and Input.is_action_just_pressed("fire_missile"):
		nu_systems.deploy(target)
	if (Input.is_action_pressed("fire_missile") or _autofire_intercept) and not is_nu():
		_autofire_intercept = false
		# ⚠️ 与 `_autofire_intercept` 一起清 —— 它只对"这一帧"有效，绝不许跨帧粘着。
		_intercept_auto_shot = false
		if not profile.has_missiles:
			if Input.is_action_just_pressed("fire_missile"):
				notice.emit("本形态没有浮游导弹 —— 只有光束步枪与火神炮", 1.8)
		elif lock == null or not lock.locked:
			if Input.is_action_just_pressed("fire_missile"):
				notice.emit("未锁定目标", 1.2)
		elif funnel_count <= 0:
			if Input.is_action_just_pressed("fire_missile"):
				notice.emit("浮游导弹耗尽", 1.2)
		else:
			# 第十八轮：**记下"这一梭从第几个 child 开始"** —— 武装那一步
			# （`_mark_intercept_missile`）靠它把本梭的**全部**三发认出来（见 `_fired_salvo()`）。
			# ⚠️ 快照与发射必须**紧挨着**：中间只要有人往容器里塞了别的东西
			# （干扰弹也进同一个容器），认出来的"本梭"就会多出几发。
			_salvo_from = _salvo_child_count()
			# ⚠️ 发射的镜头抖动**不在这里**（2026-09-21）：那是"**每一发离架**"的事，
			# 由 `_on_funnel_launch()` 逐发打（FlightBody 的钩子，本类覆写）。
			# 放在这里会变成"每次扳机抖一次"，与三发的观感脱节，见 DESIGN §4.10。
			if not fire_funnel(target, salvo):
				# ⚠️ 上面的门禁都过了，却还是没打出来（`fire_funnel()` 内部还剩"冷却 / 变形"两条闸）
				# → **必须把拦截请求清掉**。武装那一步靠"这一帧新长出来的那几发"定位；
				# 请求留着而这一帧没有新弹，它就会去武装**上一发**（好几秒前打出、已经飞远的那一枚）。
				# 玩家看到的是"拦截毫无规律地生效 / 不生效"—— 自动拦截每秒 5 发，错乱会被放大得很快。
				_salvo_from = -1
				_intercept_requested = false
				_intercept_pending = null

	# --- Z：变形（阿利宙斯：巡航 ↔ 常态，冷却 4 秒）---
	if Input.is_action_just_pressed("transform") and profile.id == SuitProfile.Id.PENELOPE and profile.form == 0:
		penelope_cruise_enabled = not penelope_cruise_enabled
		notice.emit("变形 —— 巡航形态" if penelope_cruise_enabled else "变形 —— 常态",1.6)
	elif Input.is_action_just_pressed("transform"):
		if toggle_form():
			if precision_suit(): regz_weapons.cancel()
			notice.emit("变形 —— %s" % profile.form_name(), 1.6)
			if camera != null:
				camera.add_shake(0.3)
		elif form_cooldown > 0.0:
			notice.emit("变形冷却 %.1fs" % form_cooldown, 1.2)
		else:
			notice.emit("本形态不能变形" if switchable_forms().size() > 1
				else "本机没有变形机构", 1.4)

	# ⚠️ **`discard_rifle` 不是一个 InputMap 动作**（1.2 起退役，见
	# `InputSetup.RETIRED_ACTIONS`）。丢枪只由"长按 R / 长按 B"那条代码路径
	# 调 `discard_rifle()`（见 `_tick_holds`）。这里原来还留着一个
	# `is_action_just_pressed("discard_rifle")` 的调用点 —— 每帧刷一行
	# `ERROR: The InputMap action "discard_rifle" doesn't exist`，
	# 一轮测试能刷上千行，真错误全被淹掉（README §20.8 记着的欠账，第十四轮清掉）。

	if Input.is_action_just_pressed("flares"):
		if not deploy_flares():
			notice.emit("干扰弹耗尽", 1.2)
		elif projectile_container != null:
			# 第十八轮：**"干扰弹 = 确定性清屏"需要一个视觉承诺**。
			# 从这一轮起，来袭弹会被**无条件**诱向最近的干扰源、并在 55 m 内自爆
			# （见 `Missile._maybe_break_lock` / `SMOKE_KILL_RADIUS`）——
			# 用户原话是"被热诱弹骗到的导弹都会冲向大量烟雾中然后在烟雾中爆炸"，
			# 所以烟必须真的放出来，而且**寿命 ≥ 有效期 3.0 s**（`smoke_burst` 的 `life` 参数）。
			#
			# ⚠️ 放在**调用点**而不是 `deploy_flares()` 内部：`flight_body.gd` 此刻正被并行的
			# 另一个会话高频改写，这一轮刻意不碰它（见 `GUNDAM_HANDOFF.md` §7）。
			# 等它空下来，这两行应该挪回 `deploy_flares()` 里 —— 那里才是它的家。
			FX.smoke_burst(projectile_container, global_position, 4.6, 3.5)
			FX.smoke_burst(projectile_container, global_position + Vector3(0, 6.0, 0), 3.4, 3.5)

	if Input.is_action_just_pressed("switch_target") and lock != null and not InputSetup.using_gamepad:
		lock.cycle_target()


## 回头看 / 导弹系统模式。
##
## ⚠️ **第十八轮：锁定镜头不再有自己的键**。用户原话："把 alt 和十字键 ← 的锁定功能
## 集成到辅助驾驶模式里面"。它现在由 `_tick_assist()` 驱动：辅助开启且已锁定时，
## 镜头自动跟住目标；关掉辅助就回追尾镜头 —— 于是"看一眼"的动作不再需要玩家操心。
##
## 空出来的 Alt / 十字键 ← 改成**导弹系统模式切换**：拦截 ⇄ 全弹发射。
## ⚠️ 模式**必须常驻可见**（HUD 右下角那一行 + 中央读数）：它改变"鼠标右键 / L1 干什么"，
## 藏起来玩家按右键时就会以为按键坏了 —— 本工程为"语义变了却不显示"栽过。
func _read_view_input() -> void:
	if (is_nu() or is_zorin()) and Input.is_action_just_pressed("missile_mode"):
		nu_systems.cycle_mode()
		_system_say("浮游炮："+nu_systems.mode_name())
		return
	if precision_suit() and Input.is_action_just_pressed("missile_mode"):
		regz_weapons.toggle()
		_system_say("右键：" + regz_weapons.mode_name())
		return
	if camera == null:
		return
	camera.set_look_back(Input.is_action_pressed("look_back"))
	if not is_sazabi() and thunderbolt_systems==null and Input.is_action_just_pressed("missile_mode"):
		missile_mode = MissileMode.INTERCEPT if missile_mode == MissileMode.FULL_SALVO \
			else MissileMode.FULL_SALVO
		# ⚠️ 走 `_system_say()`（左上角那一行），**不是**中央那摞 toast ——
		# 老板："切换拦截系统……的提示都还在中间啊"。
		_system_say("导弹系统：%s" % missile_mode_name())
		# 音效也跟着分：切到"全弹发射"是进攻性的，切回"拦截"是收手
		Audio.play_ui("ui_confirm" if missile_mode == MissileMode.FULL_SALVO else "ui_return")


## HUD 需要知道"锁定刚刚发生/丢失"来播提示。
## 1.1 起脱锁有具体原因（击坠 / 对方脱锁 / 超出距离），提示里一并说出来 ——
## "LOCK LOST" 三个字对玩家没有信息量。
func update_lock_feedback() -> void:
	if lock == null:
		return
	if lock.locked and not _was_locked:
		_was_locked = true
		notice.emit("LOCK ON", 1.0)
	elif not lock.locked and _was_locked:
		_was_locked = false
		var why := lock.last_lost_reason
		notice.emit(("LOCK LOST · %s" % why) if why != "" else "LOCK LOST", 1.4)
# ============================================================ 飞弹拦截（1.2，方案③）

## 当前选中的来袭威胁下标（-1 = 没选）。
var _threat_index := -1
## 辅助驾驶下这一帧打出的导弹要不要标记成"可拦截"（打完就清）。
var _intercept_requested := false
## **这一发扳机打完之后，要武装成"咬住哪一枚"**（第十五轮新增）。
##
## 为什么不能像以前那样从 `_threat_index` 里读：手柄的**自动拦截**每 0.5 秒一发、
## 目标是"最危险的、还没被咬住的那一枚"，它一次一发地变；
## 靠"全局选中状态"隐式传参只能传当前选中这一个，而且会和"玩家手工选的目标"打架。
## 所以目标改成**显式传参**：发扳机之前写进来，`_mark_intercept_missile()` 取走就清空。
var _intercept_pending: Node3D = null
## 手柄 L1 的双模状态机（点按 = 拦一发 / 按住 = 每秒 2 枚自动拦）。见 `InterceptAuto`。
var _intercept_auto := InterceptAuto.new()
## 这一梭开打**之前**容器里有几个 child（第十八轮）。
##
## 用途：`fire_funnel()` 一梭往 `projectile_container` 里 add_child 三发，
## 于是"调用前后数一次 child 数"就能**准确知道这一梭是哪几发**。
## ⚠️ 为什么不问 `FlightBody.last_salvo`（那本来是更干净的自报数）：
## `flight_body.gd` 此刻正被并行的另一个会话高频改写，这一轮**刻意不碰它**
## （见 `GUNDAM_HANDOFF.md` §7 的并行纪律）。等它空下来可以把这段换成自报数。
var _salvo_from := -1
## 「全弹发射」（第十八轮）：冷却 / 分批剩余 / 分批节拍 / 目标。
var full_salvo_charges := 3
var full_salvo_cooldown := 0.0
var _full_salvo_left := 0
var _full_salvo_timer := 0.0
var _full_salvo_target: Node3D = null
## 全弹发射的**分配表**（批 1，多目标锁定）：`spread[i]` 分到 `parts[i]` 发。
##
## ⚠️ 为什么在 `fire_full_salvo()` 里**一次算完**、而不是在 `_emit_full_salvo_shot()`
## 里按发现算：后者会让"组中途掉了一个人"这件事把分配抖散 ——
## 前 30 发按 3 人分、后 70 发按 2 人分，而且总数还对不上 100。
## 表算一次、发的时候按序号查，才是确定的。
##
## 单目标时它就是 `[target] / [100]` —— 与改动前逐位相同。
var _full_salvo_spread: Array = []
var _full_salvo_parts: Array = []
var _threat_key_latch := false
var _threats_cache: Array = []


## 按 **TTI** 排序的来袭飞弹（HUD 与 `F` 都用它）。
func threats() -> Array:
	return _threats_cache


## 当前选中的来袭飞弹。
##
## ⚠️ **不要**写 `var m: Node3D = _threats_cache[i]["missile"]`：
## 飞弹会自爆（对撞 / 撞地 / 到寿），缓存里那一格随时可能已经是被释放的实例，
## 而"把已释放实例赋给带类型标注的变量"会直接抛
## **"Trying to assign invalid previously freed instance"**（用户实测报的就是这个）。
## 正确姿势：先取成**无类型**变量 → 判 `is_instance_valid` → 再 `as` 转。
func selected_threat() -> Node3D:
	if _threat_index < 0 or _threat_index >= _threats_cache.size():
		return null
	var raw = _threats_cache[_threat_index].get("missile")
	if raw == null or not is_instance_valid(raw):
		return null
	return raw as Node3D


func selected_threat_tti() -> float:
	if _threat_index < 0 or _threat_index >= _threats_cache.size():
		return 0.0
	return float(_threats_cache[_threat_index]["tti"])


## 刷新威胁表（**只读世界，不读输入**）。
##
## 第十五轮把它从 `_tick_threats()` 里拆出来，因为它必须在**读输入之前**跑：
## 手柄的拦截在这一刻就要知道"现在最危险的是哪一枚"。
func _refresh_threats() -> void:
	_threats_cache = Interceptor.rank_threats(self, _incoming_missiles())


## 处理"选威胁"按键（键盘 B）+ 武装这一帧刚打出的那一发。
##
## 为什么拦截目标必须**显式选**：`F` 的语义在"选中威胁"之后变成打拦截弹 ——
## 如果这个切换是自动的，玩家按 F 打出一发拦截弹会当成 bug。
## 所以选中状态必须一直显示在 HUD 上（"当前选中：来袭飞弹 #2"）。
##
## ⚠️ 手柄**没有**"手工选威胁"的键位（15 个入口在第十五轮已经全满了）。
## 它走的是另一条路：**系统按 TTI 选、玩家只决定何时开火** —— 见 `_tick_pad_intercept()`。
func _tick_threats(delta: float) -> void:
	if _threat_index >= _threats_cache.size():
		_threat_index = _threats_cache.size() - 1
	# 用边沿而不是 `is_action_just_pressed`：B 同时是"长按丢枪"，
	# just_pressed 会在长按丢枪开始时顺手选一次威胁。
	var pressed := Input.is_action_pressed("select_threat")
	if pressed and not _threat_key_latch:
		_threat_key_latch = true
		if _threats_cache.is_empty():
			_threat_index = -1
			notice.emit("没有来袭飞弹", 1.0)
		else:
			_threat_index = posmod(_threat_index + 1, _threats_cache.size())
			notice.emit("拦截目标：来袭飞弹 #%d（TTI %.1f s）"
				% [_threat_index + 1, float(_threats_cache[_threat_index]["tti"])], 1.6)
	elif not pressed:
		_threat_key_latch = false
	# 目标没了（被打掉 / 自己炸了）→ 取消选中，F 立刻回到"打浮游导弹"
	if _threat_index >= 0 and selected_threat() == null:
		_threat_index = -1
	# 这一帧按过 F（辅助驾驶）→ 把刚打出的那一发标记成可拦截
	if _intercept_requested:
		_mark_intercept_missile()


## 场上所有"冲着我来"的飞弹。
func _incoming_missiles() -> Array:
	var out: Array = []
	# 组快照走 Game 的每物理帧缓存（批 10 性能二轮）
	for m: Node in Game.group_snapshot(get_tree(), "missiles"):
		if m is Node3D and is_instance_valid(m) and "target" in m and m.get("target") == self:
			out.append(m)
	return out


# ⚠️ 第十五轮删掉了两样东西，**都是死代码**：
#   - `_cycle_threat()`：注释写着"键盘 B 点按 / 手柄 R2 长按都走这里"，
#     但**一个调用点都没有**（键盘 B 那条路在 `_tick_threats()` 里自己走了一遍）。
#     手柄现在也不手工选威胁了（自动模式按 TTI 选），所以它没有存在的理由。
#   - `var _hold_threat_pad := HoldAction.new()`：configure 过 0.45，**却从来没被 tick 过**。
# 死代码的危险不在于多几行：它会让下一个读代码的人以为"手柄已经能选威胁了"。
# ============================================================ 辅助飞行（1.2）

## 辅助飞行是否开启。默认**关**：这是一套"帮忙"的系统，不该替玩家做决定。
var assist_on := false
var _assist := FlightAssist.new()
const CollisionGuard := preload("res://scripts/flight/assist_collision_guard.gd")
var _collision_guard := CollisionGuard.new()
var _hold_assist := HoldAction.new()
var _assist_warned := false
## 硬兜底是否正在接管俯仰（第十四轮）。
var _auto_pull_up := false
## 地形告警的**边沿**（★ 63-15）：只在"进入告警态"那一帧说一次。
## 没有它的话，告警态里每帧都会重发提示与音效。
var _terrain_warn_on := false
## 接管的**最短保持时间**（秒）。防"拉一帧、松一帧"的抖动：
## 解除接管要求"在爬升 **且** 飞出地面探头的视界"同时成立，再叠这一档，
## 手感上才是"一次干脆的改出"，而不是贴着地面抽搐。
const AUTO_PULL_MIN_HOLD := 1.0
var _auto_pull_hold := 0.0
## **系统提示行**：一按就"切了某个模式/方案"的那些提示，全部走这一条。
##
## 老板两轮反馈叠出来的：
##   ① "辅助飞行……另外**自动改出的这些提示也移开**"；
##   ② "**切换拦截系统**和**切换手柄操作**的这些提示**都还在中间**啊，
##      能不能移到别的地方去"。
##
## 所以它不是"辅助专用"，而是**"我按了一下，某个东西换挡了"这一类消息的通道**：
##   辅助飞行开/关 · 自动改出接管/交还 · 导弹系统（拦截 ⇄ 全弹发射）· 武器切换 · 俯仰反转。
##
## ⚠️ 它**不走 `notice`**（那是屏幕中下方那摞通用 toast，留给战斗事件：
## 击坠 / 波次 / 拦截弹 / 锁定 / 变形……），而是随 `assist_state()["event"]`
## 交给左上角那一行 —— 提示贴在状态区，中央留给战斗。
##
## ⚠️ 换位置 ≠ 静默：左上角那块本来就把「辅助驾驶 接管拉升」印成红色，
## 这一行只是补上"刚刚发生了什么"。而且**有声**（切模式/开关都各带一个 UI 音）。
## ⚠️ 只存**最后一次**：连着发生两件事时后来者覆盖前者（提示是给"当下"看的）。
var system_event := ""


## 记一条系统提示（走左上角那一行，见 `system_event`）。
func _system_say(text: String) -> void:
	system_event = text


## 开关：**长按 0.45 s**（方案指定：无破坏性，所以可以再长按关掉）。
##
## ⚠️ 2026-09-22 从 `_tick_assist()` 里拆出来单独一个函数：开关判定必须在
## **读取飞行输入之前**跑完 —— 本帧是"平移模式"还是"巡航保持现状"，
## 取决于这一帧结束时 `assist_on` 是什么，读取路由（`_think`）要按它分流。
func _tick_assist_toggle(delta: float) -> void:
	if is_sazabi():
		assist_on=true
		if _hold_assist.tick(delta,Input.is_action_pressed("flight_assist"))==HoldAction.Result.LONG and lock!=null:
			if lock.target!=null:lock.target=null;_system_say("解除锁定")
			else:cycle_contact()
		return
	if is_nu():
		assist_on = true
		if lock!=null:lock.auto_engage_limit=0
		if _hold_assist.tick(delta,Input.is_action_pressed("flight_assist"))==HoldAction.Result.LONG and lock!=null:
			if is_instance_valid(lock.target):lock._drop_target("解除索敌");_system_say("已解除索敌")
			else:
				lock._refresh_candidates();lock.cycle_target();_system_say("索敌" if is_instance_valid(lock.target) else "周围没有可锁定敌机")
		return
	var pressed := Input.is_action_pressed("flight_assist")
	var assist_action := _hold_assist.tick(delta, pressed)
	if SuitProfile.is_thunderbolt(profile.id) and assist_action == HoldAction.Result.SHORT and lock != null:
		lock.auto_engage_limit = 0
		lock._drop_target("解除锁定")
		_system_say("解除锁定")
	if assist_action == HoldAction.Result.LONG:
		assist_on = not assist_on
		_system_say("辅助驾驶 %s" % ("开启" if assist_on else "关闭"))
		Audio.play_ui("ui_confirm" if assist_on else "ui_return")
	if _hold_assist.progress() > 0.5 and not _assist_warned:
		_assist_warned = true
		_system_say("继续按住将%s辅助驾驶" % ("关闭" if assist_on else "开启"))
	elif not _hold_assist.holding():
		_assist_warned = false


## 辅助驾驶的每帧接管（在 `_think()` 最后调 —— 这一帧里任何先前的写入都不会
## 把它盖掉，见 `_apply_flight` 的兜底）。
##
## ## 两条路（2026-09-22；二调晚同日）
##   - **平移模式**（辅助开 + 非阿利宙斯巡航形态 + **没骑板**）：镜头对准玩家机体
##     （不再双机框定）、锁定跟随保留；姿态修正、索敌油门、"替你按住 Shift"
##     全部不适用 —— 方向与闪避已由 `_read_translate_input()` 写好，
##     位移与"机头朝锁定敌机"在 `FlightBody._apply_translate()` 里执行。
##   - **保持飞行操纵**（阿利宙斯巡航形态 / **骑飞行踏板**）：原有姿态修正 +
##     常驻加力不动，Shift 升级为**超级加速**。
##
## ⚠️ 判据直接读 `translate_mode`（`_think()` 里刚写好的那个字段），**不重算** ——
## 它是"这一帧到底走哪条路"的单一真源；重算就会和 `_apply_flight()` 分家，
## 而那种分家**不报错**，只是同一帧里两处按不同的模式改写同一个机体。

## 倒着飞开关（★63-9 · D2）。
##
## 用户原话：「在辅助驾驶模式下，CTRL 键按下可以切换飞行模式：按下 ctrl 会变成
## 倒着飞，w 就变成减速，s 就变成加速。」
##
## ## 为什么门是 `translate_mode`、不是"辅助开着"
## CTRL（动作名 `hover`）在**普通飞行**里是悬停（`flight_model.gd` 的"极猛刹车"），
## 只有在平移模式下它是**空键** —— `_read_translate_input()` 全文不读 `hover`。
## 而阿利宙斯巡航形态与骑飞行踏板时辅助虽然也开着，那两支走的是普通飞行读取
##（见 `assist_uses_translation`）⇒ 门必须与 `translate_mode` 同源：
## 在那些形态里把 CTRL 变成空键，比今天的悬停更糟（按下去什么都不发生）。
##
## ## 读**动作名**、不读键码
## 用 `Input.is_action_just_pressed("hover")` —— 玩家在设置里把"悬停"改绑到别的键
## 之后倒飞跟着走（键位只有一处真源：`InputSetup`）。
##
## ## 三个清零点（防语义残留）
##   ① 离开平移模式（关辅助 / 变形巡航 / 骑上踏板）⇒ 本函数第一句清零；
##   ② `controls_enabled = false`（结算 / 暂停禁控）⇒ `_think()` 的哨兵段清零；
##   ③ 玩家自己再按一次 CTRL。
## 少任何一个，"关掉辅助之后 CTRL 忽然又变成悬停、机体却还在倒飞"就会出现。
##
## ⚠️ **不翻机头**：`translate_reverse` 只进 `FlightBody._apply_translate()` 的
## **速度层**，`global_transform` 一个字节不改 ⇒ 锁定 / 弹道 / 军刀吸附 /
## 炮口锚点全部逐位不变（设计文档 §3.2 的 ①(b)：只翻速度方向）。
func _tick_reverse_toggle() -> void:
	if not translate_mode:
		translate_reverse = false
		return
	if Input.is_action_just_pressed("hover"):
		translate_reverse = not translate_reverse
		# 换挡类提示走**左上角系统提示行**（中央那摞 toast 留给战斗事件）——
		# 与「辅助驾驶 开启/关闭」同一个通道、同一个音效约定。
		_system_say("反向巡航 %s" % ("开启" if translate_reverse else "关闭"))
		Audio.play_ui("ui_confirm" if translate_reverse else "ui_return")


func _tick_assist(delta: float) -> void:
	if not assist_on:
		fm.super_boost = false
		_auto_pull_up = false
		_collision_guard.reset()
		if camera != null:
			camera.frame_both = false
			# 第十八轮：锁定镜头**并进辅助飞行** —— 关掉辅助就回追尾镜头
			camera.set_lock_view(false)
		return
	var tgt: Node3D = null
	if lock != null and lock.target != null and is_instance_valid(lock.target):
		tgt = lock.target
	# Cruise precision observes the target without asking the autopilot to chase it.
	if precision_view_active() and profile.form == 1: tgt = null
	# 想保持的距离：导引头射程的四成 —— 足够远到有时间反应，
	# 又足够近到步枪与火神炮都在有效射程内。
	var preferred := 0.0
	if lock != null:
		preferred = lock.seeker_range * 0.4
	# **视觉**：
	#   - 平移模式（二调 2026-09-22，用户："镜头锁定对准玩家机体"）：
	#     **关掉双机框定**（frame_both 会把镜头拽远去装下敌机），镜头专心
	#     对准玩家机体的追尾机位；锁定跟随保留（机头本来就朝敌机，视线一致）。
	#   - 保持飞行操纵的老辅助（巡航形态 / 骑板）：保留双机框定 + 锁定跟随。
	if camera != null:
		camera.frame_both = not translate_mode
		# ⚠️ 第十八轮：**锁定镜头由辅助飞行驱动**（用户指定：把 Alt / 十字键 ← 的锁定功能
		# 集成到辅助驾驶里）。判据挂 `tgt`（辅助自己认的那个目标）而不是 `lock.locked`：
		# 两者在这条路径上指的是同一台机，而 `tgt` 还已经过了 `is_instance_valid` ✅。
		camera.set_lock_view(tgt != null)
	# ---- 平移模式：**防撞地照样要跑**（★ 63-9 · B3）----
	#
	# 原实现是这里一句 `if translate_mode: return`，而 `_assist.update()` 与整段「松手改出」
	# 都在它**后面** ⇒ 辅助驾驶下只要走平移模式（绝大多数机体在辅助下的默认路，
	# 见 `assist_uses_translation`）：**防撞地一次都不执行**。用户报的「防撞地未生效」
	# 首先就是这条结构性缺失。
	#
	# ⚠️ 但「把代码挪到 return 之前」本身**不够**：`FlightBody._apply_translate()`
	# 直接改 `fm.velocity`、**一个字都不读 `control_input`** ⇒ 平移模式下写
	# `control_input = Vector3(1.0, ...)` 等于什么都没做（观感是「提示弹了、机体照样扎进地里」）。
	# 所以「满杆抬头」这个动作按模式分家，见 `_pull_up_command()`。
	#
	# ⚠️ 量「玩家有没有在压杆」的口径也要跟着换（下面传的是 `translate_dir.y`）：
	# 平移模式**没有俯仰杆** —— `_read_translate_input()` 每帧把 `control_input` 清零（`:734`），
	# 真正的「往下」是 **Q/E 升降**，落在 `translate_dir` 的 y 分量上。
	# 传 `control_input.x`（恒 0）等于告诉辅助「玩家永远没在压杆」，于是「按着 E
	# 往地里扎」也会被夺杆 —— 正好是老板点名不许的那件事。
	if translate_mode:
		_assist.update(self, tgt, preferred, delta, translate_dir.y)
		_tick_auto_pull(delta)
		_tick_terrain_warn()
		# 姿态修正与「替你按住 Shift」不属于平移模式
		return
	# 用户要求：**辅助驾驶期间保持加速模式**。
	# 直接压 fm.boosting —— 飞行模型里它决定速度上限，等于"替你按住 Shift"。
	fm.boosting = true
	# **超级加速**（2026-09-22，用户指定"他的 shift 就变成超级加速"）：
	# 只有走到这里的（阿利宙斯巡航形态 + 辅助开）才可能为真；
	# `_read_flight_input()` 里那行按"辅助且 Shift"预置的值在这一支才是有效语义。
	# 起跑边沿（批 11）：超级加速进入的**那一帧**给一记脉冲 —— 持续的 FOV 档
	# 在相机里（FOV_SUPER_BONUS），这里补的是"点火"的瞬间确认。
	var sb := Input.is_action_pressed("boost")
	if sb and not fm.super_boost and camera != null and camera.is_inside_tree():
		camera.add_impact_pulse(0.6)
		camera.add_shake(0.18)
	fm.super_boost = sb
	_assist.update(self, tgt, preferred, delta, control_input.x)
	_tick_terrain_warn()
	if _tick_auto_pull(delta):
		return

	control_input = Vector3(
		clampf(control_input.x + _assist.input.x, -1.0, 1.0),
		control_input.y,
		clampf(control_input.z + _assist.input.z, -1.0, 1.0))
	# 油门偏置同样是"加"：夹到合法区间，玩家手里那一挡仍然是主导
	if not fm.hovering:
		fm.throttle = clampf(fm.throttle + _assist.throttle_bias * delta, 0.0, 1.0)
## **地形告警**（★ 63-15）：**只提醒、绝不改出**。
##
## 老板 2026-10-07 拍板：`GROUND_GUARD_ALT = 50 m` 字面一字不动，
## "极速俯冲拉不回来"当工程边界接受。
## 于是 50 m **之上**只做一件事：**让玩家来得及反应**。
##
## ⚠️ 不碰 `translate_dir` / `control_input` / `fm` —— 与 `_tick_auto_pull()` 的分工就在这里：
##   那一个才是夺杆，且只在 50 m 之下才许说话。
##
## ⚠️ **已接管时不重报**：那时 `_tick_auto_pull()` 自己会发
##   "自动改出 · 接管俯仰"，两条提示叠在一起反而看不清。
func _tick_terrain_warn() -> void:
	_terrain_warn_on = false



## 松手改出（防撞地）的状态机。返回 true = **本帧已接管**，调用方应立刻 return。
##
## ★ 63-9 · B3：抽成独立方法，唯一理由是**两种模式都要跑** ——
##   · 平移模式（辅助开 + 非巡航形态 + 没骑板）：以前在 `_tick_assist()` 的
##     `if translate_mode: return` 处直接早退 ⇒ 防撞地一次都不执行；
##   · 飞行操纵（阿利宙斯巡航形态 / 骑板）：走原来的老路，**顺序一字未动**。
##
## 老板两次澄清后的口径：
##   「玩家在辅助模式下主动冲向地面哪怕离地面只有 10 m，
##   **只要玩家松手就要立刻抬升海拔**」。
## 所以触发看的是**输入**不是高度：压杆期间一点不干预；一松手且
## 探头看得到地面 ⇒ 本帧立刻满抬头；一直拉到「在爬升 **且** 飞出探头视界」
## 才交还。第一版做成「到危险高度就夺杆」是错的：会在玩家主动俯冲时把杆抢走。
##
## ⚠️ **接管必须说**：进/出各一次提示 + 地形告警音。这个工程里明确禁止静默夺杆
## （「按了没反应」和「按键坏了」在玩家眼里是同一件事）。
## 顺带补上一条一直没接的线：`sound_bank` 里 `alarm_critical` 的注释本来就写着
## 「I 立场被击穿 / 残血 / **地形告警**」，而代码里一直只用在残血那一条上。
##
## ⚠️ 调用它**之前**必须已经调过 `_assist.update()` —— `release_pull` 与
## `ground_time` 都是那里刷新的。两个调用点各自负责这件事。
func _tick_auto_pull(_delta: float) -> bool:
	# Last-moment rescue is the sole ground control path; retire the old pitch takeover.
	_auto_pull_up = false
	_auto_pull_hold = 0.0
	return false



## 接管期间往飞行层写「满杆抬头」。**口径按模式分**（★ 63-9 · B3）。
##
## ⚠️ 平移模式**没有俯仰杆**：`FlightBody._apply_translate()` 直接改 `fm.velocity`，
## 它**一个字都不读 `control_input`**。平移模式下真正的抬头旋钮是**升降（Q/E）**，
## 也就是 `translate_dir` 的 y 分量（`_read_translate_input()` 里唯一带 y 的那一项）。
##
## 三个写点，缺一不可：
##   ① `translate_dir = UP` —— 顶成满杆上升（飞行操纵里那一记 `control_input.x = 1`）；
##   ② `translate_fwd = ZERO` —— 它是 W 那一份的留档，`_apply_translate()` 拿
##      `dir − fwd_part` 算「除前进之外的全部」、再给前向单独打 0.15 折；
##      留着上一帧 W 的旧值，那个减法会把上升这一份也当成「前进」一起削掉 85%；
##   ③ `face_target = null` —— 这是**余量**那一笔，也是最容易被漏掉的一笔：
##      有目标时 `_apply_translate()` 的底速方向是**朝目标的全 3D 机头**，
##      目标在下方时「朝目标飞」本身就是一条俯冲指令。接管期间的净垂速
##      = `(TRANSLATE_OFFSET − sin θ) · v`（θ = 目标在水平线下的夹角，`TRANSLATE_OFFSET = 0.65`）：
##        θ = 10° ⇒ 净升 +0.48 v；θ = 30° ⇒ +0.15 v；θ = 40° ⇒ **+0.007 v ≈ 0**
##      ⇒ 不清它，「帮它拉起来」在俯角一大就退化成「既不升也不降」。
##      清掉之后底速退回**机头水平投影**，净垂速恒为 `+0.65 v`（≈ 33° 爬升）。
##      ⚠️ 下一帧 `_read_translate_input()` 会按锁定重写它，所以只影响接管这段时间。
##      ⚠️ 只清 `face_target`，**不动** `face_target_override`（测试通道、优先级更高）——
##      清它会把测试自己摆的姿态参照一起清掉。
##
## ⚠️ 飞行操纵那一支**保持原样**（满抬头 + 压平坡度）：`suite_round14` 的
## `_assist_ground_guard` 逐条钉住了 `1.0` / `0.4` / `boosting=false`，改一个字都要重跑。
func _pull_up_command() -> void:
	if translate_mode:
		translate_dir = Vector3.UP
		translate_fwd = Vector3.ZERO
		face_target = null
		return
	control_input = Vector3(1.0, control_input.y, clampf(control_input.z, -0.4, 0.4))


# ------------------------------------------------------------ 拦截弹的标记

## 把"刚打出的那一发"标记成可拦截（辅助驾驶下）。
##
## 用"容器里最后一个自己发射的导弹"来定位，而不是改 `fire_funnel()` 的返回值 ——
## 把这一帧打出的那一**梭**全部武装成拦截弹，并给每发分配一枚来袭弹（第十八轮 · 方案 A）。
##
## ## 为什么必须"一梭三发全武装"（而不是只武装最后一发）
##
## 老实现只武装"容器里最后一个自己打出的弹"，于是**一次扳机 = 一个拦截目标**；
## 而来袭弹是**按梭**来的（AI 一梭三发 / 0.42 s）—— 玩家的拦截速率因此只有来袭速率的
## 一半到三分之一，**再准的手也拦不完**（算术见 `aiwork/gundam-missile-defense-plan.md` §1）。
## 把一梭里的三发都武装，吞吐直接 **×3**，而且**不花额外弹药、不改任何速率**：
## 那两发本来就在打出去了，只是以前没有对撞资格。
##
## ## 目标从哪来
##   - `_intercept_pending`（玩家**显式选**的那一枚：右键点框 / 手柄自动选 / 辅助驾驶下的 F）
##     一定有弹去咬它 —— 显式选择永远优先；
##   - 其余按 TTI 顺序补，并**跳过已经被别的拦截弹咬住的**（`Interceptor.engaged_targets`）。
##
## 分配本身是纯函数 `Interceptor.assign_targets()`（**最小转角**贪心）——理由见那里：
## 拦截弹加速 ×1.8 ⇒ 转弯半径也 ×1.8，硬塞给"TTI 前三名"会让两发去追反方向的目标。
func _mark_intercept_missile() -> void:
	# ⚠️ 闸门放在**方法内部**，而不是只靠调用点判：
	# 否则任何一次直接调用都会把"刚打出的那一梭"标记成可拦截，
	# 结果是**所有导弹都能拦截**（等于把拦截白送）。
	# 这是测试抓出来的 —— 原来只有 `_tick_threats` 在判 `_intercept_requested`。
	if not _intercept_requested:
		return
	_intercept_requested = false
	# ⚠️ 目标改成**显式取参**（第十五轮）：手柄的自动拦截图的是"最危险的、还没被咬住的
	# 那一枚"，它每 0.2 秒就换一个 —— **不能**再从全局选中状态里读。
	# ⚠️ 取法照抄 `selected_threat()` 那套（那是本文件踩过的坑）：先取**无类型**变量、
	# 判 `is_instance_valid`、再 `as` 转 —— 直接赋给带类型标注的变量会抛
	# "Trying to assign invalid previously freed instance"（目标可能就在这一帧被打掉）。
	var raw_mark = _intercept_pending
	_intercept_pending = null
	var mark: Node3D = null
	if raw_mark != null and is_instance_valid(raw_mark):
		mark = raw_mark as Node3D

	var salvo := _fired_salvo()
	if salvo.is_empty():
		return
	var threats := _salvo_threats(mark)
	if threats.is_empty():
		# 没有可咬的目标 → 仍然全部武装成"可对撞"的弹：
		# 撞上任何**冲我来的**弹都会同归于尽（`Missile._check_intercept` 的判据）
		for m in salvo:
			(m as Missile).arm_intercept(null)
		notice.emit("拦截弹已发射 —— 与来袭飞弹对撞", 1.8)
		return
	var pairs := Interceptor.assign_targets(salvo, threats)
	for p in pairs:
		var fm := p["missile"] as Missile
		if fm != null and is_instance_valid(fm):
			# ⚠️ **一次性把三件事做齐**（标记可对撞 / 咬住目标 / 速度 ×1.8），
			# 见 `Missile.arm_intercept()` —— 尤其是 `accel` 必须跟着重算，
			# 否则加速时间会变成 1.8 倍，等于把速度加成吃回去一半。
			fm.arm_intercept(p["threat"])
	var n := pairs.size()
	notice.emit(("拦截弹 ×%d 已分配目标" % n) if n > 1
		else "拦截弹已发射 —— 已咬住来袭飞弹", 1.8)


## 容器现有几个 child（`fire_funnel()` 之前记一次，见 `_fired_salvo()`）。
func _salvo_child_count() -> int:
	var c: Node = projectile_container if projectile_container != null else get_parent()
	return -1 if c == null else c.get_child_count()


## 这一帧 `fire_funnel()` **实际打出的那几发**（第十八轮）。
##
## 判据 = "**容器里这一帧新长出来的 Missile**"：发射走 `fire_funnel()`，
## 它把一梭 add_child 到 `projectile_container`，所以调用前后各数一次 child 数就够了。
## ⚠️ 不用老的"容器里最后一个 `Missile`"：一梭三发时它只能给出**一发**，
## 而同帧还可能混进别的弹（干扰弹也进同一个容器，所以这里还要筛 `shooter == self`）。
## ⚠️ 快照（`_salvo_from`）用完就清，避免下一帧被重复消费。
func _fired_salvo() -> Array:
	var out: Array = []
	var c: Node = projectile_container if projectile_container != null else get_parent()
	var from := _salvo_from
	_salvo_from = -1
	if c == null:
		return out
	var n := c.get_child_count()
	# ⚠️ **没有快照时（`from < 0`）退化成"最近的那一梭"**：直接调用 `_mark_intercept_missile()`
	# 的场合不会经过发射那一行（测试就是、"将来别的接线点"也会），拿不到 `_salvo_from`。
	# 判据取**最后 `MISSILE_PER_SHOT` 个自己打出的弹** —— 正好是一梭的粒度，
	# 而它仍然比老行为（只认最后一发）更接近现在的意图。
	# ⚠️ 生产路径**永远有快照**（F 分支里紧挨着 `fire_funnel` 写），发射失败时快照与请求一起清，
	# 所以这里不会误伤"好几秒前打出去的弹"。
	var per_shot := profile.funnel_per_shot if profile != null else SuitProfile.MISSILE_PER_SHOT
	var lo := from if from >= 0 else maxi(0, n - per_shot)
	for i in range(lo, n):
		var m := c.get_child(i) as Missile
		if m != null and is_instance_valid(m) and m.shooter == self:
			out.append(m)
	return out


## 这一梭要咬的目标：`primary`（玩家显式选的）排第一，其余按 TTI 补，跳过已被咬住的。
func _salvo_threats(primary: Node3D) -> Array:
	var out: Array = []
	var engaged: Array = Interceptor.engaged_targets(self)
	if primary != null and is_instance_valid(primary):
		out.append(primary)          # 显式选择**无条件**排第一（哪怕已经有人在咬它）
	for e in _threats_cache:
		var m = e.get("missile")
		if m == null or not is_instance_valid(m) or out.has(m) or engaged.has(m):
			continue
		out.append(m)
	return out
# ------------------------------------------------------------ 鼠标选中来袭飞弹

## 光标底下的来袭飞弹（和"光标罩住敌机"用同一套投影判定）。
##
## 这里自己算投影、不去问 HUD：HUD 每帧都要画，而"光标压在哪个框上"是个纯几何问题，
## 不值得为它加一条 HUD→PlayerController 的状态同步（`_cursor_target()` 也是这么做的）。
func _cursor_missile() -> Node3D:
	if camera == null or not camera.is_inside_tree():
		return null
	var best: Node3D = null
	# 飞弹的拾取半径**比敌机更大**（用户反馈框太小、点不中）：
	# 敌机是"瞄准"的目标，飞弹是"急着点"的目标，两者手感不该共用一个数。
	var best_d := float(MISSILE_PICK_RADIUS)
	for i in _threats_cache.size():
		var raw = _threats_cache[i].get("missile")
		if raw == null or not is_instance_valid(raw):
			continue
		var m := raw as Node3D
		if m == null or camera.is_position_behind(m.global_position):
			continue
		var d := camera.unproject_position(m.global_position).distance_to(aim_cursor)
		if d < best_d:
			best_d = d
			best = m
	return best


## 把某一枚飞弹选为拦截目标（写进 `_threat_index`，HUD 会高亮它）。
func _select_threat_node(m: Node3D) -> void:
	for i in _threats_cache.size():
		if _threats_cache[i]["missile"] == m:
			_threat_index = i
			notice.emit("拦截目标：来袭飞弹 #%d（TTI %.1f s）"
				% [i + 1, float(_threats_cache[i]["tti"])], 1.6)
			return
# ============================================================ 手柄的拦截（第十五轮）

## 这一帧的 `fire_secondary` 该按**哪种设备**解释。
##
## **唯一判据**（别在别处再判第二次 —— 两个地方各判一次就是"两个写者"，本工程踩过）：
## 最近一次输入来自手柄（`InputSetup.using_gamepad`，键鼠一动它就自动切回来），
## 或者**从未见过鼠标移动**（手柄玩家 `cursor_seen` 恒为 false；键鼠玩家第一次动鼠标就置真）。
##
## ⚠️ 为什么不干脆"看摇杆有没有输入"：Godot 的 `is_action_just_pressed()` **不告诉你**
## 是哪个设备按的。设备归属只能由 `InputSetup` 那一条统一追踪来回答。
func _intercept_pad_mode() -> bool:
	return InputSetup.using_gamepad or not cursor_seen


## 手柄的拦截入口（**每帧都调，不管按没按** —— 松手那一帧要靠它归零）。
##
## 三种出手：
##   - **按下沿**：立刻 1 发（"点按可以拦截一发"）；
##   - **按住 ≥ 0.45 s**：进自动模式，之后**每 0.5 秒 1 发**（= 每秒 2 枚），
##     每发都挑"最危险的、**还没被咬住**的"那一枚；
##   - **松手**：退出自动模式（状态机自己归零）。
##
## ⚠️ 发送顺序铁律（四步必须**同一帧**内按此顺序）：
##   **写 `_intercept_pending` → 置 `_autofire_intercept` → 本函数后面那段 F 分支真的打出扳机
##   → `_tick_threats()` 里武装**。跨帧 = 武装到上一次打出的那一发，
##   表现是"偶尔打出一发普通导弹"，只在连按时出现。
func _tick_pad_intercept(delta: float) -> void:
	var tapped := Input.is_action_just_pressed("fire_secondary")
	var held := Input.is_action_pressed("fire_secondary")
	var can := _can_intercept()
	var shots := _intercept_auto.update(delta, held, can)
	# 状态机因为"连续发不出去"而退出了 → **必须说话**，不能静默失效
	if _intercept_auto.exhausted:
		_intercept_auto.clear_exhausted()
		_intercept_blocked_notice()
	elif tapped and shots == 0 and not can:
		# 点按那一下发不出去 —— 玩家至少要知道为什么
		_intercept_blocked_notice()
	for i in shots:
		# 点按：优先打"玩家选中的那一枚"（显式选择永远优先）；
		# 自动：跳过"已经被咬住"的 —— 否则两发之后全砸在 TTI #1 上。
		var mark := _pad_pick_threat(not tapped)
		if mark == null:
			break
		_select_threat_node(mark)
		_intercept_pending = mark
		_intercept_requested = true
		_autofire_intercept = true
		# ★ 与上面那个**分开**：只有这一个才是"本帧零冷却"的判据（见 `_intercept_auto_shot`）。
		_intercept_auto_shot = true


## 手柄这一发该打谁。
## `skip_engaged` = 跳过"已经有一发拦截弹咬着"的那一枚（自动模式用，见 `Interceptor.engaged_targets`）。
func _pad_pick_threat(skip_engaged: bool) -> Node3D:
	if not skip_engaged:
		var cur := selected_threat()
		if cur != null:
			return cur
	var engaged: Array = []
	if skip_engaged:
		engaged = Interceptor.engaged_targets(self)
	return Interceptor.pick_available(_threats_cache, engaged)


## 此刻打得出拦截弹吗。判据与 `fire_funnel()` 里的门禁**一一对应** ——
## 不一一对应就会变成"状态机以为能打、发射器却拒绝"，表现就是**按着没反应**，
## 而那是最难查的一类故障（本工程为它栽过好几次）。
func _can_intercept() -> bool:
	if profile != null and profile.id in [SuitProfile.Id.GP03D,SuitProfile.Id.NEUE_ZIEL]:
		return false
	if profile == null or not profile.has_missiles:
		return false
	if lock == null or not lock.locked:
		return false
	if funnel_count <= 0 or funnel_cooldown > 0.0 or in_transform():
		return false
	if projectile_container == null:
		return false
	return not _threats_cache.is_empty()


## 发不出去时给一句**照着能做**的话。顺序 = 从最具体的原因开始排。
##
## 最后那一条是用户实测踩到的：手柄玩家看见"右键要点在来袭飞弹的框上"是**纯粹的误导**
## —— 他既没有右键，也看不见那个框（框画在鼠标分支里）。
func _intercept_blocked_notice() -> void:
	if _threats_cache.is_empty():
		notice.emit("没有来袭飞弹", 1.0)
	elif profile == null or not profile.has_missiles:
		notice.emit("本形态没有拦截弹（浮游导弹）", 1.6)
	elif lock == null or not lock.locked:
		notice.emit("先锁定敌机（手柄十字键 ↑）才能发射拦截弹", 2.0)
	elif funnel_count <= 0 or funnel_reload_left > 0.0:
		# 批 14：总量无限、打空自动换弹 —— "耗尽"改成换弹状态
		notice.emit("浮游导弹换弹中", 1.4)
	elif funnel_cooldown > 0.0 or in_transform():
		notice.emit("拦截弹冷却中", 0.8)


## HUD 用：自动拦截是否正开着（**常驻读数** —— 系统在替玩家开火，玩家必须看得见）。
func auto_intercept_active() -> bool:
	return _intercept_auto.active


## HUD 用：按住 L1 进自动模式的进度 0..1。
func intercept_hold_progress() -> float:
	if _intercept_auto.active:
		return 1.0
	return _intercept_auto.progress()


# ============================================================ 导弹系统模式 / 全弹发射（第十八轮）

## 导弹系统模式：决定 **鼠标右键 / L1** 干什么。
##
## 用户原话："把 alt 和十字键 ← 改成导弹系统模式切换，在拦截模式下鼠标右键和左肩键就是拦截，
## 全弹发射模式下就是发射 100 枚导弹。全弹发射有内置 20s 的 cd，**切换模式不影响 cd 运转**"。
enum MissileMode { INTERCEPT, FULL_SALVO }
var missile_mode := MissileMode.INTERCEPT

## 一次「全弹发射」打多少发（用户指定："一口气射出一百发导弹"）。
const FULL_SALVO_COUNT := 100
## 冷却（秒）。老板先定 20 s、改成 60 s，批 14 改回 **30 s**（用户指定：
## "全弹发射的cd改为30s"）。**切换模式不影响它的运转** ——
## 所以它在 `_tick_full_salvo()` 里**无条件**递减（那个函数每帧都调，与当前模式无关）。
const FULL_SALVO_COOLDOWN := 30.0
## 分批：每个物理帧放几发 / 两批之间隔多久。
## ⚠️ 100 发一次性 `add_child` 会造成一帧的卡顿（每发都带尾迹粒子），
## 而"一波一波涌出去"本来就更壮观 —— 这一条同时是**性能**与**观感**的选择。
const FULL_SALVO_PER_TICK := 5
const FULL_SALVO_TICK_GAP := 0.035


## 全弹发射就绪吗（HUD 读它画"就绪 / 冷却 / 弹药不足"）。
## 批 14：换弹中也不算就绪（弹夹不够 100 发照样放不出）。
func full_salvo_charge_status() -> String:
	var status := "%d/%d" % [full_salvo_charges,profile.full_salvo_capacity]
	if full_salvo_cooldown > 0.0: status += " · +1 %.0fs" % ceilf(full_salvo_cooldown)
	return status

func full_salvo_ready() -> bool:
	if profile != null and profile.id == SuitProfile.Id.NEUE_ZIEL:
		return funnel_count > 0 and funnel_cooldown <= 0.0 and funnel_reload_left <= 0.0 and projectile_container != null and not is_staggered() and not in_transform()
	if profile != null and profile.id == SuitProfile.Id.GP03D:
		return funnel_count >= 108 and funnel_cooldown <= 0.0 and projectile_container != null and not in_transform() and not is_staggered()
	return (full_salvo_charges > 0 if profile != null and profile.full_salvo_capacity > 1 else full_salvo_cooldown <= 0.0) and _full_salvo_left <= 0 \
		and profile != null and profile.has_missiles \
		and funnel_reload_left <= 0.0 \
		and funnel_count >= FULL_SALVO_COUNT and projectile_container != null \
		and not in_transform() and not is_staggered()


## 按下「全弹发射」：扣弹、起冷却、开始分批涌出。返回是否真的放出去了。
func fire_full_salvo(target_unit: Node3D) -> bool:
	if profile != null and profile.id == SuitProfile.Id.NEUE_ZIEL:
		return fire_funnel(target_unit)
	if profile != null and profile.id == SuitProfile.Id.GP03D:
		return fire_funnel(target_unit)
	if target_unit == null or not is_instance_valid(target_unit) or not full_salvo_ready():
		return false
	funnel_count -= FULL_SALVO_COUNT
	if profile.full_salvo_capacity > 1:
		full_salvo_charges -= 1
		if full_salvo_cooldown <= 0.0: full_salvo_cooldown = profile.full_salvo_recharge
	else:
		full_salvo_cooldown = FULL_SALVO_COOLDOWN
	# 批 14：这一梭可能刚好打空弹夹（100/100）—— 打空自动换弹，与单发路径同规
	_funnel_check_reload()
	_full_salvo_left = FULL_SALVO_COUNT
	_full_salvo_timer = 0.0
	_full_salvo_target = target_unit
	# 批 1（多目标锁定）：100 发按**已稳定锁定**的成员数平分（见 `_build_full_salvo_spread`）。
	_build_full_salvo_spread(target_unit)
	_funnel_slot = 0
	Game.funnels_fired += 1
	Audio.play_self("funnel_fire", -1.0)
	funnel_fired.emit()
	# 模型动作：全弹发射那一段骨骼动画（`burst` / `burst_cruise`）。
	#
	# ⚠️ **放在 `notice.emit()` 与相机抖动之前无所谓，但必须放在
	# `return true` 之前** —— 这一行是"玩家真的按下去了"的**唯一收口**
	# （辅助驾驶与手柄两条路都经过它）。放在调用方就会出现
	# "AI 开炮有动作、玩家开炮没动作"这种半截接线。
	#
	# 没有动作的形态（老资产 / 还没换模型的柯西）这里直接返回 false，无副作用。
	play_full_burst()
	if camera != null:
		camera.add_shake(0.5)
	notice.emit("全弹发射 —— %d 发" % FULL_SALVO_COUNT, 2.2)
	return true


## 为什么发不出去。**必须能照着做** —— 手柄上"按着没反应"是最难自己发现的一类失败。
func _full_salvo_fail_reason() -> String:
	if profile == null or not profile.has_missiles:
		return "本形态没有浮游导弹"
	if lock == null or not lock.locked:
		return "未锁定目标"
	if _full_salvo_left > 0:
		return "全弹发射进行中"
	if full_salvo_cooldown > 0.0 and (profile.full_salvo_capacity <= 1 or full_salvo_charges <= 0):
		return "全弹发射冷却 %.0f s" % ceilf(full_salvo_cooldown)
	if funnel_reload_left > 0.0:
		return "浮游导弹换弹中"
	if funnel_count < FULL_SALVO_COUNT:
		return "弹夹浮游导弹不足 %d 发（现有 %d）" % [FULL_SALVO_COUNT, funnel_count]
	if in_transform() or is_staggered():
		return "变形 / 脱板失能中，无法全弹发射"
	return "无法全弹发射"


## 冷却与分批节拍（每帧调，见 `_read_weapon_input`）。
func _tick_full_salvo(delta: float) -> void:
	if profile != null and profile.full_salvo_capacity > 1:
		if full_salvo_charges < profile.full_salvo_capacity:
			full_salvo_cooldown -= delta
			while full_salvo_cooldown <= 0.000001 and full_salvo_charges < profile.full_salvo_capacity:
				full_salvo_charges += 1
				full_salvo_cooldown += profile.full_salvo_recharge
			if full_salvo_charges == profile.full_salvo_capacity: full_salvo_cooldown = 0.0
	else:
		full_salvo_cooldown = maxf(full_salvo_cooldown - delta, 0.0)
	if _full_salvo_left <= 0:
		return
	_full_salvo_timer -= delta
	if _full_salvo_timer > 0.0:
		return
	_full_salvo_timer = FULL_SALVO_TICK_GAP
	for _i in mini(FULL_SALVO_PER_TICK, _full_salvo_left):
		_emit_full_salvo_shot()
		_full_salvo_left -= 1


## 全弹发射的一发：从**螺旋展开**的方向弹出去 —— 一百发要开成一朵花，而不是叠成一条线。
##
## 每发都 `arm_intercept(null)`：于是这一波**同时**是一堵拦截墙
## （任何"冲我来的"弹撞上它都会同归于尽，见 `Missile._check_intercept` 的判据）。
## ⚠️ 代价是它的速度也吃了 ×1.8 —— 100 发 2041 m/s 的弹幕，是这一轮最强的进攻手段，
## 要收的话应该收 `FULL_SALVO_COUNT` 或冷却，而不是把它拆成"不可拦截"。
func _emit_full_salvo_shot() -> void:
	if projectile_container == null or profile == null:
		return
	var n := FULL_SALVO_COUNT - _full_salvo_left
	var side := 1.0 if _funnel_slot % 2 == 0 else -1.0
	_funnel_slot += 1
	var slot := "funnel_L" if side > 0.0 else "funnel_R"
	# ⚠️ 与 `FlightBody.fire_funnel()` 同一口径：`global_transform *`，不是 `global_position +`。
	# 理由见那里的注释（`rig_anchor()` 给的是**机体局部空间**的向量）。
	var origin := global_transform * rig_anchor(slot)
	# 黄金角螺旋（相邻两发方位差 ≈137.5°）：整批在空间里铺得最匀
	var a := float(n) * 2.399963
	var outward := (right() * (cos(a) * side)
		+ up() * (0.30 + 0.80 * absf(sin(a)))
		+ forward() * (0.15 - 0.35 * cos(a))).normalized()
	# ⚠️ 尾迹档位传 `LOW`（DESIGN §4.4「性能」）：这 100 发若和正常扳机一样用
	# `Trail.HIGH`（70 粒子/发），就是 **7000 粒子/秒** 的尾迹 —— 会直接把帧率打下去。
	# 而弹幕的观感本来就是"一整片烟"，单发看不清并不影响它。
	var m := Missile.funnel(projectile_container, origin, outward, _full_salvo_target_for(n), self,
		profile.funnel_damage * damage_mult, Missile.Trail.LOW)
	m.arm_intercept(null)
	Game.missiles_fired += 1
	# 全弹发射的每一发也给一次镜头后坐（2026-09-21）。
	# ⚠️ 原来这条路上**一处 `add_shake` 都没有** —— 100 发是场上最大的动作，
	# 镜头却一点不动（DESIGN §4.10.1 缺口 2）。
	# 幅度用 `LAUNCH_KICK_SALVO`（**0.14/发**）：0.02 那一版实测峰值恒为 0.000
	# （`_apply_shake()` 是线性衰减，单发输入必须压过阈值才不被整块吃掉），
	# 等于"场上最大的动作"在镜头上什么都没有。见 DESIGN §4.10.2 与 §4.9.4。
	if camera != null:
		camera.add_launch_shake(ChaseCamera.LAUNCH_KICK_SALVO)


## 全弹发射要打向谁们：单目标时 = `[primary]`（旧行为），多目标时把 100 发平分。
##
## ⚠️ 这一条是**必须**的，不是可选的美化：不分散的话"锁 3 个"在玩家看来就是
## "100 发全砸一个，而且还能顺手锁两个" —— 那是纯收益，火力分散这个代价就不存在了。
##
## ⚠️ 与浮游导弹那条同源：K 取**已稳定锁定**的成员数（`locked_in_group()`），
## 不取组大小。刚 `add_lock` 进来、层级还停在 TRACK 的成员不该分到弹。
## 因此"锁 3 个"要先付出"把三个人都跟到 LOCK"的时间，这才是取舍。
func _build_full_salvo_spread(primary: Node3D) -> void:
	_full_salvo_spread.clear()
	_full_salvo_parts.clear()
	var group: Array[FlightBody] = []
	if lock != null:
		group = lock.locked_in_group()
	if group.is_empty():
		_full_salvo_spread = [primary]
		_full_salvo_parts = [FULL_SALVO_COUNT]
		return
	var parts := LockOnSystem.salvo_split(FULL_SALVO_COUNT, group.size())
	for i in group.size():
		if parts[i] <= 0:
			continue
		_full_salvo_spread.append(group[i])
		_full_salvo_parts.append(parts[i])


## 第 `n` 发（0 起）该打谁。单目标时恒等于 `_full_salvo_target`（旧行为）。
func _full_salvo_target_for(n: int) -> Node3D:
	var acc := 0
	for i in _full_salvo_parts.size():
		acc += int(_full_salvo_parts[i])
		if n < acc:
			var u: Node3D = _full_salvo_spread[i] as Node3D
			if u != null:
				return u
	return _full_salvo_target


## 当前模式的名字（切换提示与 HUD 共用）。
func missile_mode_name() -> String:
	if is_nu() or is_zorin(): return "浮游炮 · "+nu_systems.mode_name()+" · Alt切换"
	if precision_suit(): return regz_weapons.mode_name() + " · Alt切换"
	if profile != null and profile.id == SuitProfile.Id.NEUE_ZIEL:
		return "线控炮 · 6km"
	if profile != null and profile.id == SuitProfile.Id.GP03D:
		return "导弹舱 · 弱制导"
	return "全弹发射" if missile_mode == MissileMode.FULL_SALVO else "拦截"


## 当前模式"怎么用"的一句话（**设备感知**：手柄上没有右键，印右键就是误导）。
func missile_mode_hint() -> String:
	if is_nu(): return InputSetup.hint("F展开浮游炮 · Alt切模式 · 右键精准瞄准","L2展开浮游炮 · 模式键切换 · L1精准瞄准")
	if precision_suit(): return "仅巡航模式可用 · Alt切换" if regz_weapons.irradiation and profile.form != 1 else "按住右键 · 左键发射 · Alt切换"
	if profile != null and profile.id == SuitProfile.Id.NEUE_ZIEL:
		return InputSetup.hint("右键 = 线控炮 · F = 导弹","L1 = 线控炮")
	if profile != null and profile.id == SuitProfile.Id.GP03D:
		return InputSetup.hint("F / 右键 = 发射1舱（108发）", "L1 = 发射1舱（108发）")
	if missile_mode == MissileMode.FULL_SALVO:
		return InputSetup.hint("右键 = 全弹发射", "L1 = 全弹发射")
	return InputSetup.hint("右键 = 拦截飞弹", "L1 = 拦一发 / 按住自动拦")


## 按模式触发全弹发射；失败就把**照着能做**的原因播出来
##（手柄上"按了没反应"是最难自己发现的一类失败，工程里栽过多次）。
func _fire_full_salvo_or_notice(target_unit: Node3D) -> void:
	if not fire_full_salvo(target_unit):
		notice.emit(_full_salvo_fail_reason(), 1.8)
# ============================================================ 附近敌机列表（1.2 第十六轮）

## 用户原话：「右上角显示周围的敌机列表（按 123 能切换已扫描的敌机）」。
##
## 两个词在这里被钉死成可执行的判据：
##
## **「周围的敌机」** = 场上所有还活着的敌机（这一版最多也就几架），
## **没有射程过滤** —— 这是试出来的：训练局里四架靶机绕 5.2 km 的圈飞、玩家在 7 km 外出生，
## 按"导引头射程"过滤的话右上角只剩两行，而雷达上明明有四个回波。
## 列表少一架不是"简洁"，是**玩家会据此判断"周围只有两架"**。
## 唯一不进列表的是柯西丢枪后的"不可被锁定"窗口（雷达上它也是暗的）。
##
## **「已扫描」** = 本机火控已经建立航迹 = 在导引头射程（`lock.seeker_range`）之内。
## 超距的照旧列出来、距离后面标「未扫描」、整行压暗 —— 看得见、但**按数字键选不上**，
## 而且会给一句说明（不是"按了没反应"）。
## 更远的敌机在雷达上照旧有回波（`_draw_radar()` 画的是全部敌机）。
##
## **「第 n 架」** = 列表里的第 n 行，而列表只有一份真源：
## HUD 画的是它（`FlightHUD._draw_contact_list`）、数字键选的是它、
## 连"画几行带号"都由 `CONTACT_KEYS.size()` 决定。三处对不上的可能性从结构上被消掉。
##
## ⚠️ **编号只发一次**（`rank_contacts` 是纯函数，可以直接单测）：
## 上一帧已经在表里的敌机保持原号，新出现的排在后面。
## 若改成"每帧按距离重排"，两架敌机交叉而过时 1 号和 2 号会在
## **玩家读到列表和按下按键之间偷偷换人** —— 那比没有这个功能更坏。
## 代价是序号不保证"1 号最近"，所以列表每一行都印着距离，由玩家自己判断。

## 列表的**编号槽位**：第 n 个 `CONTACT_KEYS` ↔ 列表第 n 行。
## HUD 给前 `CONTACT_KEYS.size()` 行发号牌，第 10 架起才退回"其余 N 架 · Tab 循环"。
##
## ⚠️ **1 – 9 全绑**（用户第二轮明确"不止 123"）。这一版场上一共也就几架、
## 9 个槽位用不完，但"够不够用"不该由玩家去猜 —— 列表里有号就能按，
## 按不到才需要退回去循环。**0 键故意不绑**：它没有对应的序号，
## 绑上去只会变成"按了没反应"（这个工程最恨的那类）。
const CONTACT_KEYS := ["select_contact_1", "select_contact_2", "select_contact_3",
	"select_contact_4", "select_contact_5", "select_contact_6",
	"select_contact_7", "select_contact_8", "select_contact_9"]

## 本帧的编号表（HUD 右上角与数字键共用这一份）。
var _contacts_cache: Array = []


## HUD 右上角要画的那份名单。
func contacts() -> Array:
	return _contacts_cache


## **纯函数**：把这一帧"能锁的敌机"并进上一帧的编号表。
##
## 规则只有两条：**还在的老面孔保持原号**（相对顺序也不动），**新面孔排在最后**。
## 不排序 —— 那是调用方的事（`_refresh_contacts()` 已经按距离排过 `live`）。
static func rank_contacts(live: Array, previous: Array) -> Array:
	var out: Array = []
	for c in previous:
		if is_instance_valid(c) and live.has(c) and not out.has(c):
			out.append(c)
	for c in live:
		if not out.has(c):
			out.append(c)
	return out


func _refresh_contacts() -> void:
	var live: Array = []
	for h: Node3D in Game.live_hostiles_of(self):
		var fb := h as FlightBody
		if fb == null:
			continue
		# 柯西丢枪后的"不可被锁定"窗口：不进列表（`select_target()` 也会拒，
		# 雷达上它同样是暗的）。除此之外**一律列出**，哪怕超距 —— 见上面的说明。
		if fb.is_unlockable():
			continue
		live.append(fb)
	# 按**距离**排队（近的拿前面的号）：于是"按 1 / 2 / 3"优先够到最近的那几架，
	# 超距的那些自然排在后面。老面孔的号由 `rank_contacts` 保住。
	live.sort_custom(func(a, b):
		return global_position.distance_to((a as Node3D).global_position) \
			< global_position.distance_to((b as Node3D).global_position))
	_contacts_cache = rank_contacts(live, _contacts_cache)


## 数字键 1 / 2 / 3 → 选列表里的第 n 架。
func _tick_contacts() -> void:
	_refresh_contacts()
	for i in CONTACT_KEYS.size():
		if Input.is_action_just_pressed(CONTACT_KEYS[i]):
			select_contact(i + 1)
	if InputSetup.using_gamepad and Input.is_action_just_pressed("switch_target"):
		cycle_contact()


## 手柄 ↑ 按敌机列表顺序切换，与数字键共用 select_contact 的选择规则。
## 跳过未扫描目标；不受机头候选锥或现有锁定组限制，也不会自动清空当前目标。
func cycle_contact() -> bool:
	if lock == null:
		return false
	_refresh_contacts()
	var count := _contacts_cache.size()
	var current := _contacts_cache.find(lock.target)
	for step in range(1, count + 1):
		var index := (current + step) % count
		var raw = _contacts_cache[index]
		if not is_instance_valid(raw):
			continue
		var contact := raw as FlightBody
		if contact != null and global_position.distance_to(contact.global_position) <= lock.seeker_range:
			return select_contact(index + 1)
	notice.emit("周围没有已扫描的敌机", 1.2)
	return false


## 选中列表里的第 `n` 架（从 1 起）。返回是否真的选上了。
##
## 三种"选不上"都要给一句人话，否则和"按了没反应"没有区别：
## 表里没有第 n 架 / 那一架这一帧刚被释放 / 它已经超出锁定距离。
func select_contact(n: int) -> bool:
	if lock == null:
		return false
	if n < 1 or n > _contacts_cache.size():
		if _contacts_cache.is_empty():
			notice.emit("周围没有已扫描的敌机", 1.2)
		else:
			notice.emit("敌机列表里只有 %d 架" % _contacts_cache.size(), 1.2)
		return false
	# ⚠️ 先取成**无类型**变量再判有效性：这一格随时可能是同帧被击坠 / 释放的实例，
	# 直接赋给带类型标注的变量会抛 "Trying to assign invalid previously freed instance"
	# （`selected_threat()` 那边踩过同一个坑，见它的注释）。
	var raw = _contacts_cache[n - 1]
	if raw == null or not is_instance_valid(raw):
		return false
	var fb := raw as FlightBody
	if fb == null or not fb.alive:
		return false
	if lock.target == fb:
		notice.emit("%d 号已经是锁定目标" % n, 0.9)
		return true
	if not lock.select_target(fb):
		# 唯一会走到这里的情形：超出导引头射程（列表里它标着"未扫描"）。
		# 报出距离，玩家才知道"再靠近多少就能锁"。
		notice.emit("%d 号尚未扫描 · 超出锁定距离（%.1f km）" % [n,
			global_position.distance_to(fb.global_position) / 1000.0], 1.6)
		return false
	notice.emit("锁定 %d 号 · %s" % [n, fb.display_name], 1.2)
	return true


## ★63-9 · D3a：辅助瞄准的门 = 辅助驾驶开关（覆写 `FlightBody` 的虚函数）。
##
## 用户原话：「给光束步枪加入辅助瞄准模式，辅助驾驶模式下自动开启」。
## 门就取 `assist_on` 本身，**不新增开关** —— 两个开关会造出
## 「辅助开着、代瞄没开」这种玩家看不出来的状态。
##
## ⚠️ 必须走覆写：`FlightBody.aim_point()` 里直接读 `assist_on` 是**解析期**错误
##（字段声明在本文件），那会让整套件编译不过、末尾的节被静默吃掉。
func aim_assist_enabled() -> bool:
	return assist_on


## 辅助驾驶**这一刻在做什么**（HUD 左上角那块状态行读它）。
##
## 只回传布尔，不回传 `FlightAssist` 实例：HUD 每帧都要画，不该拿到一个
## 每帧都在变的可变对象，也不该有机会去改它。
func assist_state() -> Dictionary:
	return {
		"on": assist_on,
		"aim": assist_on and (absf(_assist.input.x) > 0.001 or absf(_assist.input.z) > 0.001),
		"range": assist_on and absf(_assist.throttle_bias) > 0.001,
		"avoid": assist_on and (_assist.obstacle_time < FlightAssist.AVOID_TIME
			or _assist.ground_time < FlightAssist.AVOID_TIME or _collision_guard.active),
		"collision_guard": assist_on and _collision_guard.active,
		"collision_kind": _collision_guard.kind if assist_on else "",
		# 硬兜底正在接管俯仰（第十四轮）：HUD 要能把它画出来 ——
		# 玩家在这几秒里推杆是没反应的，不给指示就会被当成"按键坏了"。
		"auto_pull": _auto_pull_up or (assist_on and _collision_guard.active and _collision_guard.kind == "ground"),
		# 倒着飞中（★63-9 · D2）：HUD 左上角在"辅助驾驶 开启"右边补一格。
		# ⚠️ 不给指示的话，玩家按了 CTRL 只会看到"机体忽然倒着飞了"= 像是 bug
		#（工程铁律：不许静默改状态）。
		"reverse": translate_reverse,
		# 系统提示行（开/关、切模式、切武器、接管/交还）—— 画在左上角那一行的右边，
		# **不是屏幕中央**。见 `system_event` 的注释。
		"event": system_event,
	}
## 辅助驾驶的**最后一道保险**：在飞行模型步进之前把加速按住。
##
## 用户实测："进入辅助飞行模式之后自动进入加速模式，不需要玩家一直按住 Shift"
## —— 放在 `_tick_assist()` 里会被同帧更晚的代码盖掉，而这里是 `_apply_flight()`
## 的第一行，**飞行模型不可能在 boosting=false 的状态下步进**。
func _apply_flight(delta: float) -> void:
	# ⚠️ 第十四轮例外：**硬兜底接管期间不按住加速**。
	# 加速会把拉升半径按比例撑大（半径 ≈ v/ω），近地时"保持加速"等于"加大撞地概率"。
	# 少了这个例外，`_tick_assist()` 里那句 `fm.boosting = false` 会被这里盖掉 ——
	# 而且**看不出任何异常**，只是"自动改出好像不太好使"。
	# ⚠️ 平移模式（2026-09-22）也排除：boosting 已由 _read_translate_input /
	# _apply_translate 按"是否冲刺"写好，这里再硬压 true 会把"松开冲刺"盖成常驻加力。
	# ⚠️ 读 `translate_mode` 而不是重算判据：骑板那条例外（2026-09-28）只写在
	# `_think()` 的单一写入点上，这里跟着它走就不会出现"两处口径不一致"。
	if assist_on and not _auto_pull_up and not _collision_guard.active and not translate_mode:
		fm.boosting = true
	# **视觉也要跟上**（1.2 用户要求："进入辅助模式之后就一直保持着 fov 拉高 + 速度线的模式"）：
	# FOV 与速度线读的是 `boost_intensity`，而它原本只跟"按没按 Shift"，
	# 于是物理上已经在加速、画面上却什么都没有。这里一起顶满 —— 用户要的是
	# "进辅助就一直保持那个观感"，不是"还要按住 Shift 才有"。
	# ⚠️ 这里**不再**硬写 `boost_intensity`：那会让观感在辅助模式下变成"常驻"。
	# 观感统一由 `_apply_flight()` 跟着 `fm.boosting` 缓动（见那里），
	# 于是手动加力与辅助驾驶都会点亮它，退出后自然回落。
	# 加速的**观感**（FOV 拉高 + 屏幕速度线）跟着**物理加速状态**走，而不是跟着 Shift 键：
	# 手动加力、辅助驾驶（自动把 boosting 顶成 true）都会点亮它；两者都没有时缓动回落。
	# 用户原话："能不能在进入加速（手动加速和自动驾驶）的时候再开"。
	var want_boost_fx := 1.0 if fm.boosting else 0.0
	boost_intensity = move_toward(boost_intensity, want_boost_fx, delta * 3.0)
	super._apply_flight(delta)
	_tick_precision_free_flight(delta)
	_level_assist_hull(delta)


## Correct bank only: keep climb, aim direction and flight velocity intact.
func _level_assist_hull(delta: float) -> void:
	if not assist_on or Settings.first_person or not controls_enabled or not alive:
		return
	if _escape_timer > 0.0 or saber_active(): return
	var free_cruise := _free_roll_cruise()
	# Cruise aerobatics have priority; return gently only after the pilot settles.
	if free_cruise and (control_input.length_squared() > 0.0025 or _roll_idle < 1.5): return
	var frame := global_basis.orthonormalized()
	var forward := -frame.z
	var up := Vector3.UP - forward * forward.dot(Vector3.UP)
	if up.length_squared() < 0.0001: return
	up = up.normalized()
	var turn := translate_dir.x if translate_mode else control_input.y
	var desired_up := up.rotated(forward, deg_to_rad(-10.0 * clampf(turn,-1.0,1.0)))
	var correction := atan2(forward.dot(frame.y.cross(desired_up)),frame.y.dot(desired_up))
	var step := correction * (1.0-exp(-(0.65 if free_cruise else 6.0)*maxf(delta,0.0)))
	var rate := deg_to_rad(20.0 if free_cruise else 150.0)
	step = clampf(step,-rate*delta,rate*delta)
	global_basis = frame.rotated(forward,step).orthonormalized()


func _face() -> Node3D:
	# Keep weapon lock intact while flight temporarily stops chasing a target
	# through the ground or a building. The original target resumes on release.
	if assist_on and _collision_guard.active:
		return null
	if precision_view_active():
		if profile.form == 1: return null
		if assist_on and precision_focus_target() != null: return precision_focus_target()
	return super._face()


func _before_flight_move(delta: float) -> bool:
	if precision_suit(): regz_weapons.slow_flight(self,delta)
	if not assist_on or not controls_enabled or not alive:
		_collision_guard.reset()
		return false
	var was_active: bool = _collision_guard.active
	fm.velocity = _collision_guard.solve(self, fm.velocity, delta, map_has_ground(), CRASH_ALTITUDE)
	if _collision_guard.active:
		fm.speed = fm.velocity.length()
		fm.boosting = false
		fm.super_boost = false
		# Cancel a committed quick boost toward the obstacle; no extra charge/refund.
		_qb_timer = 0.0
		_qb_pending = false
		translate_dash = false
		if not translate_mode and fm.speed > 1.0:
			var direction := fm.velocity.normalized()
			if absf(direction.y) < 0.98:
				global_basis = global_basis.slerp(Basis.looking_at(direction, Vector3.UP), 1.0 - exp(-4.0 * delta)).orthonormalized()
	if _collision_guard.active != was_active:
		if _collision_guard.active:
			_system_say("防撞地 · 自动拉升" if _collision_guard.kind == "ground" else "防撞楼 · 自动避让")
			Audio.play_self("alarm_critical", -3.0)
		else:
			_system_say("避让完成 · 操纵已交还")
	_rescue_ground(delta)
	# Ground limits travel only; it must not feed a new nose direction into flight.
	return _collision_guard.active


# ============================================================ 武器切换（1.2）

## 当前武器**槽位的下标**（进 `SuitProfile.weapon_slots()`）。
##
## 0 号**永远是步枪**：HUD 的装备行用"是不是 0 号"判断当前是不是步枪，那是接口。
## 古斯塔夫00 的槽位 = 步枪 / **腕部榴弹炮** / 光束军刀（1.2 第二十六轮）。
##
## 用户原要求："武器切换之后，能选择鼠标左键使用的是光束步枪还是光束军刀"。
## 火神炮（空格）与浮游导弹（F）仍然各自独立 —— 它们有"按住连发""需要锁定"的
## 特殊语义，塞进"当前武器"会让左键的行为难以预期。
var weapon_index := 0
## 腕部榴弹炮的**备弹**（每匣 5 发，打空自动装填，见 `SuitProfile.grenade_count`）。
##
## ⚠️ 计数放在**玩家侧**而不是 `FlightBody`：一是它不随换弹恢复，
## 二是 `flight_body.gd` 正被并行的另一个会话频繁改写 —— 能不碰就不碰。
var grenade_count := 0
var _grenade_init := false
## 榴弹的装填间隔计时（慢速重武器，见 `SuitProfile.grenade_interval`）。
var _grenade_cd := 0.0
const GRENADE_AUTO_RELOAD_TIME := 12.0
var grenade_reload_left := 0.0

func _tick_weapons(delta: float) -> void:
	super._tick_weapons(delta)
	if not alive or profile == null: return
	_grenade_cd = maxf(0.0,_grenade_cd-delta)
	if not profile.has_grenade: return
	if not _grenade_init:
		_grenade_init = true
		grenade_count = profile.grenade_count
	if grenade_reload_left > 0.0:
		grenade_reload_left = maxf(0.0,grenade_reload_left-delta)
		if grenade_reload_left <= 0.0: grenade_count = profile.grenade_count
	if grenade_count <= 0 and grenade_reload_left <= 0.0 and profile.grenade_count > 0:
		grenade_reload_left = GRENADE_AUTO_RELOAD_TIME

## 右键点中飞弹后的"立刻发射"标记（见 `_read_weapon_input`）。
var _autofire_intercept := false
## ★ **只**由 `_tick_pad_intercept()` 置真：本帧这一发**来自"自动拦截的整拍"**。
##
## ⚠️ 它与 `_autofire_intercept` **必须分开** —— 只有它是"该给零冷却"的判据。
##
## 起因（★63-23 实机 bug「按住拦截时会突然泼出一堆导弹」）：原来 `salvo` 的开关写的是
## `_intercept_auto.active`，那是"**自动模式开着**"，不是"**这一发来自自动整拍**"。
## 于是只要自动模式开着（按住 L1 ≥ 0.45 s 之后就一直开着），
## **任何**走 `fire_missile` 那一支的输入都拿到 0 冷却 ⇒ `fire_funnel()` 里
## `funnel_cooldown = 0.0` ⇒ **下一帧立刻又能发 ⇒ 每帧一梭**。
## 实测（`tests/_probe_overfire.tscn`）：拦截+浮游同按 1 s = **60 扳机**（应为 2.4）；
## 更狠的是只要自动模式开着、**鼠标被碰一下**（`InputSetup` 切回键鼠、状态机再没人归零）
## ⇒ 之后**只按浮游**也是 60 扳机/秒。
##
## 分开之后还顺手修好了批 26 的一处漏网：**右键点中飞弹的"立刻发射"**
## 也会置 `_autofire_intercept`，而批 26 明确要求它走通用冷却 0.42 s（不是 0）——
## 此前若自动模式恰好开着，它同样拿到了 0。
var _intercept_auto_shot := false


## 当前武器槽位名（`"rifle"` / `"grenade"` / `"saber"`）。
## **所有"当前武器是什么"都读它** —— 以前 `weapon_index == 0/1` 写死在三个地方。
func current_slot() -> String:
	if profile == null:
		return "rifle"
	return slot_at(profile.weapon_slots(), weapon_index)


## 槽位表里第 `i` 项（表空时兜底成步枪；下标越界退回 0 号）。
static func slot_at(slots: Array[String], i: int) -> String:
	if slots.is_empty():
		return "rifle"
	return slots[clampi(i, 0, slots.size() - 1)]


## 这件武器**此刻还能不能用**（打空了 / 手上没有就不算）。
## 判据只写一次：`switch_weapon()` 的跳过、左键的自动退回都读它。
func slot_available(slot: String) -> bool:
	match slot:
		"sniper":
			return is_sazabi()
		"bazooka":
			return profile != null and profile.id in [SuitProfile.Id.GP03S,SuitProfile.Id.NU_GUNDAM]
		"ram":
			return profile != null and profile.id == SuitProfile.Id.GP03D
		"cannon":
			return cannon_available()
		"wire":
			return profile != null and profile.id == SuitProfile.Id.NEUE_ZIEL
		"grenade":
			return profile != null and profile.has_grenade and (grenade_count > 0 or grenade_reload_left > 0.0)
		"saber":
			return profile != null and profile.has_saber
		"rifle":
			return rifle_count > 0
	return false


## 槽位名 → 给人看的名字。**唯一一份映射**：`weapon_name()` 与 HUD 的"下一件是什么"共用。
static func slot_display_name(slot: String) -> String:
	match slot:
		"sniper":
			return "长距离光束步枪"
		"bazooka":
			return "双火箭筒"
		"ram":
			return "主动冲撞"
		"cannon":
			return "腹部蓄力炮"
		"wire":
			return "线控机械臂"
		"grenade":
			return "腕部榴弹炮"
		"saber":
			return "光束军刀"
	return "光束步枪"


func weapon_name() -> String:
	if thunderbolt_systems!=null:
		if current_slot()=="saber":return "热能斧" if thunderbolt_systems.psycho() else ("盾牌冲撞" if shield_up else "光束军刀")
		return "光束火箭筒" if thunderbolt_systems.psycho() else "二连装光束步枪"
	if is_zorin() and current_slot()=="rifle":return "Pak43A化学枪"
	if is_sazabi():return "光束霰弹枪" if current_slot()=="rifle" else ("长距离光束步枪" if current_slot()=="sniper" else ("腹部蓄力炮" if current_slot()=="cannon" else "近战模式"))
	if is_nu() and current_slot()=="bazooka": return "火箭筒"
	if current_slot() == "rifle" and profile.id == SuitProfile.Id.NEUE_ZIEL:
		return "肩甲米加粒子炮"
	if current_slot() == "rifle" and profile.cannon_only:
		return "MEGA光束炮"
	return slot_display_name(current_slot())


## **下一件能切到的武器名**（HUD 那一行"切过去会变成什么"用）。
##
## ⚠️ 它**只读**，不切换 —— 和 `switch_weapon()` 用同一套"跳过拿不到的"规则，
## 不然 HUD 会预告一件实际切不过去的武器（"按下去没变成你写的那件"是最难查的一类）。
## 一件都切不到时返回空串。
func next_slot_name() -> String:
	if profile == null:
		return ""
	var slots := profile.weapon_slots()
	var n := slots.size()
	for step in range(1, n + 1):
		var slot := slot_at(slots, (weapon_index + step) % n)
		if slot_available(slot):
			return "肩甲米加粒子炮" if slot == "rifle" and profile.id == SuitProfile.Id.NEUE_ZIEL else ("MEGA光束炮" if slot == "rifle" and profile.cannon_only else slot_display_name(slot))
	return ""


## 发射一枚腕部榴弹（古斯塔夫00 专属，1.2 第二十六轮）。
##
## 走 `Projectile`（实弹、非制导）：**慢速大弹丸**，命中直接结算 70 伤害。
## ⚠️ 刻意**不做提前量**：260 m/s 下 1 km 要飞 3.8 秒，提前量会大到没有意义 ——
## 榴弹是"朝准星方向打出去、看它飞过去"的武器（这也正是它和光束的观感差别）。
func fire_grenade(_target: Node3D) -> bool:
	if profile == null or not profile.has_grenade or projectile_container == null:
		return false
	if grenade_count <= 0 or _grenade_cd > 0.0 or in_transform():
		return false
	grenade_count -= 1
	if grenade_count <= 0: grenade_reload_left = GRENADE_AUTO_RELOAD_TIME
	_grenade_cd = profile.grenade_interval
	# 炮口取**腕部**：挂点锚 + 一点右/前偏移。不借用步枪枪口 —— 那样两件武器
	# 从同一个点喷出来，看不出换了一件。
	# ⚠️ 轮 13：挂点锚走 `global_transform *`（机体局部 → 世界）。
	# `right()` / `forward()` 本身就是**世界空间**的单位向量，照旧直接加。
	var origin := global_transform * rig_anchor("funnel_R") + right() * 5.0 + forward() * 4.0
	var dir := aim_dir if aim_dir.length_squared() > 0.0001 else forward()
	Projectile.spawn(projectile_container, origin, dir, self, profile.grenade_damage,
		Color(1.0, 0.72, 0.35), Damage.Type.VULCAN, profile.grenade_speed, 1.0, 3.2)
	Audio.play_3d("beam_rifle", origin, -3.0)
	return true


## 切换武器（X 短按 / 手柄十字键 → / R2 短按）：**按 `weapon_slots()` 循环**。
## **跳过当前拿不到的**：核心形态没有军刀、古斯塔夫打光了榴弹 ——
## 那就停在步枪上（而不是让左键变成"按了没反应的键"）。
func switch_weapon() -> bool:
	if profile == null:
		return false
	var slots := profile.weapon_slots()
	var n := slots.size()
	var from_slot := current_slot()
	for step in range(1, n + 1):
		var idx := (weapon_index + step) % n
		var slot := slot_at(slots, idx)
		if not slot_available(slot):
			continue
		if profile.id == SuitProfile.Id.GP03S and (saber_active() or _saber_visual_tail > 0.0):
			return false
		weapon_index = idx
		if profile.id == SuitProfile.Id.GP03S:
			gp03s_equip(slot)
		# ⚠️ 切武器也走系统提示行（左上角），不进中央 toast：老板说的"**切换手柄操作**的提示"
		# 指的就是这一类 —— 按一下换了个方案，信息贴在状态区就够了。
		_system_say("武器：%s" % weapon_name())
		Audio.play_ui("ui_select")
		_play_slot_transition(from_slot, slot)
		return true
	# 一件都切不动：把原因说清楚（"按了没反应"和"按键坏了"在玩家眼里是同一件事）
	if n <= 1:
		notice.emit("本形态没有可切换的武器", 1.2)
	else:
		notice.emit("其余武器都打空了", 1.2)
	return false


## 军刀槽的**一进一出**各播一次过渡动作（N49）：`trans_fly_to_slash` / `trans_slash_to_fly`。
##
## ## 触发时机 = 武器槽**跨过 `saber` 边界**那一刻
##
## 交付里这两段是**一对方向相反**的过渡（"从飞行姿态进到近战姿态" / 反之），
## 对应的是**模式切换**，不是挥刀 ——
## 挥刀另有 `slash`（在 `FlightBody.try_saber()` 里播）。两者不是同一件事：
## 一段是"拔出来"，一段是"砍下去"。
##
## ## ⚠️ 只在**真的跨边界**时播
##
## 步枪 ↔ 榴弹之间来回切**不该有任何动作**（否则每次换武器都要抖一下）。
## `from == to` 的重复切换也天然落空 —— 上面 `switch_weapon()` 成功时
## `slot` 必然 ≠ 旧槽（`step` 从 1 起），所以这里只需判"跨没跨 saber"。
func _play_slot_transition(from_slot: String, to_slot: String) -> void:
	if from_slot == to_slot:
		return
	if to_slot == "saber" and from_slot != "saber":
		play_model_action("trans_fly_to_slash")
	elif from_slot == "saber" and to_slot != "saber":
		play_model_action("trans_slash_to_fly")
## 修复的播报（1.2）。
##
## ⚠️ `notice` 是 **PlayerController** 的信号，`FlightBody` 里没有 ——
## 修复逻辑在 FlightBody 上，但"开始/结束"这两句话必须由玩家侧说
##（和脱出飞升突进那处是同一个坑，我犯了两次，所以在这里写明）。
var _repair_announced := false


func _tick_repair_feedback() -> void:
	var now := repair_active()
	if now and not _repair_announced:
		_repair_announced = true
		notice.emit("开始修复 —— 剩 %d 包" % repair_packs, 1.6)
	elif not now and _repair_announced:
		_repair_announced = false
		notice.emit("修复结束", 1.0)



## Last-frame ground rescue: cancel the descent before collision/death is evaluated.
func _rescue_ground(delta: float, force := false) -> bool:
	if not assist_on or not controls_enabled or not alive or not map_has_ground():
		return false
	var policy = FlightAssist.GroundPolicy
	var clearance: float = policy.height_at(self,global_position+Vector3.UP*1000.0)-1000.0
	var threshold: float = policy.trigger_height(self)
	var next_point := global_position + fm.velocity*maxf(delta,0.0)
	# Probe from above the candidate point so terrain rising into the path is seen.
	var probe := Vector3(next_point.x,global_position.y+1000.0,next_point.z)
	var predicted: float = policy.height_at(self,probe) - (probe.y-next_point.y)
	if not force and clearance > threshold+0.001:
		if predicted >= threshold or fm.velocity.y >= 0.0:
			return false
		# A long/high-speed frame may cross the boundary. Land the step on it;
		# do not start an ascent while the suit is still high above the ground.
		fm.velocity.y += (threshold-predicted)/maxf(delta,0.000001)
	else:
		if clearance < threshold:
			global_position.y += threshold-clearance
		fm.velocity.y = maxf(fm.velocity.y,0.0)
	fm.speed = fm.velocity.length()
	velocity = fm.velocity
	fm.boosting = false;fm.super_boost = false
	_qb_timer = 0.0;_qb_pending = false;translate_dash = false
	_auto_pull_up = false;_auto_pull_hold = 0.0
	return true

func _prevent_ground_crash() -> bool:
	return _rescue_ground(0.0,true)
