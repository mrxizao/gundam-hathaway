extends RefCounted
## Gameplay rules for the supplied lower-volume adaptation. Coordinates are game metres.
const FESTIVAL := Vector3(5400,26,-30600)
# Player-supplied marked overhead map: blue = opening, red = interception net.
const S18 := Vector3(42000,3500,36500)
const LURE_START := Vector3(-2500,3500,-47000)
# Keep M11 at its authored location when the M12 net is moved.
const DUEL_START := Vector3(3000,3500,37000)
const LURE_RADIUS := 4000.0
const CITY_RADIUS := 12000.0
const REPEL_HP := 0.30
const DUEL_HP := 0.20
static func below_hp(ratio: float, threshold: float) -> bool:
	return ratio < threshold
static func in_lure_zone(target: Vector3, center := S18, radius := LURE_RADIUS) -> bool:
	return radius > 0.0 and target.distance_squared_to(center) <= radius*radius
static func in_city(target: Vector3, center: Vector3) -> bool:
	var offset := target-center; offset.y=0
	return offset.length_squared() <= CITY_RADIUS*CITY_RADIUS

# These are adaptation lines from the user's battle excerpt, not film-source bank IDs.
const RADIO := {
	"M08": [[2.0,"通讯员","周边多个方向发现米诺夫斯基粒子散布！"],
		[7.0,"凯奈斯","不是四面进攻，是让我们分不清方向。所有机体起飞！"],
		[14.0,"通讯员","西方高速目标！是高达仿制机！"],
		[21.0,"凯奈斯","打开防御壁！"],[26.0,"梅因扎","还来不及——"]],
	"M09": [], # Full supplied script is event-driven in m09_radio.gd.
	"M10": [[2.0,"凯奈斯","雷恩，潜伏在南侧。别只想着决斗。记住防御壁的位置。"],
		[10.0,"通讯员","南方发现高达！"],
		[18.0,"凯奈斯","电力集中到S18线！"],[25.0,"梅因扎","人员撤离中。集中供电准备完成。"]],
	"M11": [[2.0,"哈萨维","珀涅罗珀……这次动作变了。"],
		[9.0,"雷恩","不会再让你随意穿过去！"],
		[18.0,"凯奈斯","别在城市正上方击坠！把敌人引出去！"],
		[26.0,"梅因扎","地下回路仍能工作，防御壁可启动！"]],
	"M12": [[2.0,"凯奈斯","告诉雷恩，把高达带到S18！"],
		[9.0,"雷恩","收到。我会配合防线行动。"],
		[18.0,"哈萨维","就是现在！"]],
}
