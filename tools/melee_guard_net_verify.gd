extends Node3D
func _ready():
 var main=load("res://scripts/main.gd").new()
 var player:=PlayerController.new()
 player.profile=SuitProfile.xi()
 player.is_player=true
 player.team=0
 player.placeholder_only=true
 add_child(player)
 player.set_physics_process(false)
 player.ifield_hp=0
 player.position=Vector3(0,3000,0)
 var foe:=NetProxyBody.new()
 foe.profile=SuitProfile.penelope()
 foe.team=1
 foe.placeholder_only=true
 add_child(foe)
 foe.set_physics_process(false)
 foe.position=player.position+Vector3(0,0,-500)
 foe.look_at(player.position)
 main.phase=main.Phase.FIGHT
 main.projectiles=self
 main.player=player
 main.remote_proxy=foe
 Game.units.assign([player,foe])
 main._on_net_fire("saber_rush",foe.position,Vector3.BACK)
 assert(foe.saber_active() and player.melee_guard.elapsed==0,"remote melee creates defensive prompt")
 player.melee_guard.elapsed=player.melee_guard.center
 assert(player.try_saber(foe),"guard remote rush")
 var hp:=player.hp
 main._on_net_damage(10,Damage.Type.SABER)
 assert(player.hp==hp,"late packet after successful parry is discarded")
 player.saber_cooldown=0
 player.melee_guard.elapsed=2
 player.melee_guard.result=""
 player.try_saber(foe)
 main._on_net_fire("saber_parry",foe.position,Vector3.FORWARD)
 assert(not player.saber_active(),"remote parry stops local attack")
 main._on_net_fire("saber_rush",foe.position,Vector3.BACK)
 main._on_net_fire("saber_stop",foe.position,Vector3.BACK)
 assert(not foe.saber_active(),"remote stop clears telegraph")
 print("MELEE_GUARD_NET 5 PASS / 0 FAIL")
 main.free()
 player.queue_free()
 foe.queue_free()
 Game.units.clear()
 await get_tree().process_frame
 get_tree().quit()
