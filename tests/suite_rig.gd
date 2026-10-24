class_name SuiteRig
extends RefCounted
## 占位槽位骨架测试。
## 槽位是本项目"真模型还没到"和"真模型到了"之间的唯一接口，
## 所以槽位名、镜像、包围盒都必须锁死 —— 改坏了飞行逻辑会静默错位。

const EXPECTED_SLOTS := [
	"head", "head_boom", "chest", "chest_boom", "monoeye",
	"waist", "backpack", "thruster_L", "thruster_R",
	"shoulder_L", "shoulder_R", "wing_L", "wing_R",
	"funnel_L", "funnel_R",
	"arm_upper_L", "arm_upper_R", "shield_L", "shield_R",
	"muzzle_L", "muzzle_R", "hand_L", "hand_R",
	"hip_L", "hip_R", "knee_L", "knee_R",
	"foot_L", "foot_R", "foot_tip_L", "foot_tip_R",
]


static func run(t: T) -> void:
	t.suite("SuitRig / 槽位")
	_slots(t)
	t.suite("SuitRig / 镜像")
	_mirror(t)
	t.suite("SuitRig / 尺寸")
	_bounds(t)
	t.suite("SuitRig / 占位件开关")
	_visibility(t)


static func _slots(t: T) -> void:
	var rig := SuitRig.new()
	rig.build()
	t.gt(rig.slot_names().size(), 50.0, "槽位数量足够（>50）")
	for name: String in EXPECTED_SLOTS:
		t.ok(rig.has_slot(name), "存在槽位 %s" % name)
	t.ok(rig.slot("head") is Node3D, "slot() 返回 Node3D 锚点")
	t.not_ok(rig.has_slot("does_not_exist"), "不存在的槽位返回 false")


static func _mirror(t: T) -> void:
	var rig := SuitRig.new()
	rig.build()
	for pair: Array in [["head_boom", "head_boom"], ["shoulder_L", "shoulder_R"],
			["muzzle_L", "muzzle_R"], ["foot_L", "foot_R"], ["wing_L", "wing_R"]]:
		var l: String = pair[0]
		var r: String = pair[1]
		if l == r:
			continue
		var a := rig.slot(l)
		var b := rig.slot(r)
		if a == null or b == null:
			t.ok(false, "镜像对 %s/%s 都存在" % [l, r])
			continue
		t.near(b.position.x, -a.position.x, 0.001, "%s 的 X 是 %s 的相反数" % [r, l])
		t.near(b.position.y, a.position.y, 0.001, "%s 与 %s 同高" % [r, l])

	# 右侧件不应出现在 X 正半轴
	var right := rig.slot("muzzle_R")
	t.lt(right.position.x, 0.0, "右炮口在 X 负半轴（+X 为右，故模型镜像在 −X）")

	# 炮口必须朝前（在机体前半球）
	var left := rig.slot("muzzle_L")
	t.lt(left.position.z, 0.0, "左炮口位于机体前半球（−Z）")

	# 喷口必须在机体后半球
	var thr := rig.slot("thruster_L")
	t.gt(thr.position.z, 0.0, "喷口位于机体后半球（+Z）")


static func _bounds(t: T) -> void:
	var rig := SuitRig.new()
	rig.build()
	var b := rig.local_bounds()
	t.between(b.size.y, 30.0, 38.0, "全高落在 30~38 m（设定 32.5 m）")
	t.between(b.size.x, 25.0, 45.0, "全宽落在 25~45 m（含肩部米诺夫斯基单元）")
	t.between(b.size.z, 12.0, 32.0, "前后厚度落在 12~32 m")
	t.lt(b.position.y, 0.0, "包围盒底部在原点下方（原点在胸口）")
	t.gt(b.position.y + b.size.y, 0.0, "包围盒顶部在原点上方")


static func _visibility(t: T) -> void:
	var rig := SuitRig.new()
	rig.build()
	t.ok(rig.placeholder_visible(), "默认显示占位件")
	rig.set_placeholder_visible(false)
	t.not_ok(rig.placeholder_visible(), "可以整体隐藏占位件（给真模型让位）")
	# 隐藏之后锚点必须还在，否则真模型接上来就取不到炮口位置
	t.ok(rig.has_slot("muzzle_L"), "隐藏占位件后槽位锚点依然存在")
	rig.set_placeholder_visible(true)
	t.ok(rig.placeholder_visible(), "可以重新显示")
