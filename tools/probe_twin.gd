extends Node
## 双联背部炮的定位探针：打印炮口局部坐标与开火后真正生成的弹丸。
##
## 跑法：`godot --headless --path <工程> res://tools/probe_twin.tscn`
##
## ## 它为什么存在（留着它，别删）
## 阿利宙斯的第一版双联炮口是**按骨架锚点**（`rig_anchor("backpack")`）定位的，
## 结果炮口落在模型 **26% 高度**（腰以下）、离中心只有 2.9 m —— 光束从小腹里射出来，
## 前半段整段埋在机体内部，追尾镜头里**什么都看不见**。
##
## 根因是那副骨架按**佩涅罗佩线稿**定的，而阿利宙斯的模型只是被"按包围盒居中"
## 塞进同一副骨架，两者解剖结构对不上：`rig_anchor("backpack")` 实际落在
## 模型局部 y = −14.8（模型总高 33 m、y 从 −18.2 到 +14.9）。
##
## **这类"看不见"的故障不看数字是查不出来的**（截图里只是"没有光束"，
## 而弹丸其实生成了）。这个探针把三件事一次打出来：
##   1. `model_bounds` —— 真实几何，炮口应该照它定位；
##   2. `rig_anchor()` 的几个关键锚点 —— 用来**核对骨架到底对不对得上模型**；
##   3. `_muzzle_local` 与开火后弹丸的实际位置/方向/判定半径。
##
## ⚠️ 判读基准：
##   1. 炮口必须在**模型高度的 60% 以上**（上半身），否则光束会被机体自己挡住；
##   2. **半间距 = 光束可视半径 × 3**（用户指定的规则，`BACK_MUZZLE_GAP_MUL`）。
##      可视半径 = `Projectile.BEAM_VIS_RADIUS × rifle_scale`（光束是圆柱，这就是它的半径）。

func _ready() -> void:
	var c := Node3D.new()
	add_child(c)
	var u := FlightBody.new()
	u.team = 0
	u.is_player = true
	u.profile = SuitProfile.arizeus(SuitProfile.ArizeusForm.NORMAL)
	u.projectile_container = c
	c.add_child(u)
	u.global_position = Vector3(0, 3000, 0)
	await _f(8)
	u.fm.align_velocity(u.forward())

	var p := u.profile
	print("profile: pellets=%d back_mount=%s scale=%.2f mag=%d interval=%.2f dmg=%.1f"
		% [p.rifle_pellets, str(p.rifle_back_mount), p.rifle_scale,
			p.rifle_magazine, p.rifle_interval, p.rifle_damage])
	print("model_bounds = ", u.model_bounds)
	print("rig_is_null = ", u.rig == null)
	if u.rig != null:
		print("slots: backpack=%s shoulder_L=%s shoulder_R=%s muzzle_L=%s"
			% [u.rig.has_slot("backpack"), u.rig.has_slot("shoulder_L"),
				u.rig.has_slot("shoulder_R"), u.rig.has_slot("muzzle_L")])
		print("anchor backpack    = ", u.rig_anchor("backpack"))
		print("anchor shoulder_L  = ", u.rig_anchor("shoulder_L"))
		print("anchor shoulder_R  = ", u.rig_anchor("shoulder_R"))
		print("anchor muzzle_L    = ", u.rig_anchor("muzzle_L"))
	var mz: Array = u.get("_muzzle_local")
	print("_muzzle_local = ", mz)
	for i in mz.size():
		print("  world muzzle %d = %s" % [i, u.global_transform * mz[i]])

	print("in_transform = ", u.in_transform(), "  mag = ", u.rifle_mag)
	u.rifle_cooldown = 0.0
	print("fire_beam -> ", u.fire_beam(true, null))
	await _f(1)
	var n := 0
	for ch in c.get_children():
		if ch is Projectile:
			n += 1
			print("  proj: pos=%s dir=%s dmg=%.1f radius=%.2f size_mul=%.2f"
				% [ch.global_position, ch.direction, ch.damage, ch.hit_radius(), ch.size_mul])
	print("projectile count = ", n)
	print("PROBE_DONE")
	get_tree().quit(0)


func _f(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
