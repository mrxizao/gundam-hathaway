extends RefCounted
const FIN_COUNT:=6
const FIN_HP:=20.0
# Projectile-only hitboxes: do not block moving MS or count as world geometry.
const FIN_HIT_LAYER:=1 << 2
const ENERGY_MAX:=100.0
const DRAIN:=[3.0,5.0,8.0]
const COOLDOWN:=25.0
const DEFENSE_COOLDOWN:=33.0
const SEQUENCE_INTERVAL:=3.0
const VOLLEY_INTERVAL:=4.0
const PRE_SHOT:=.09
const POST_SHOT:=.1
const DAMAGE:=27.0
const ORBIT_LIMIT:=900.0
const BEAM_SPEED:=16000.0
const LAUNCH_STAGGER:=.25
const RETURN_TIME:=1.0
const MODE_NAMES:=["依次射击","齐射","防御"]
# Bazooka: ten-round magazine with guided rounds and unlimited reloads.
const BAZOOKA_MAG:=10
const BAZOOKA_DAMAGE:=70.0
const BAZOOKA_RELOAD:=8.5
const BAZOOKA_INTERVAL:=.8
const BAZOOKA_SPEED:=5200.0
const BAZOOKA_SEEK_RANGE:=12000.0
const BAZOOKA_SEEK_DOT:=0.3420201433 # 70 degree half-angle
const BAZOOKA_TURN_RATE:=3.8
const BAZOOKA_TURN_DECAY:=0.02
