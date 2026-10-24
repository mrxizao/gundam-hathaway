extends Node3D
var checks:=0
var failures:=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:
  failures+=1
  push_error(label)
func unit(team:int):
 var u=FlightBody.new()
 u.profile=SuitProfile.xi()
 u.placeholder_only=true
 u.team=team
 add_child(u)
 u.set_physics_process(false)
 u.hp=500
 u.max_hp=500
 u.ifield_hp=0
 u.position=Vector3(0,3000,0)
 return u
func _ready():
 var a=unit(1)
 var d=unit(0)
 d.is_player=true
 a.position.z=-500
 a.look_at(d.position)
 Game.units.assign([a,d])
 check(a.try_saber(d),"incoming attack starts")
 check(d.melee_guard.elapsed==0,"two-second defensive bar starts")
 check(absf(d.melee_guard.WINDOW-0.2)<0.000001,"strict window width")
 check(not a._try_clash(0.016),"sustained charge cannot auto clash")
 var center:float=d.melee_guard.center
 d.melee_guard.elapsed=center-0.10001
 check(not d.melee_guard.can_guard(d),"before green fails")
 d.melee_guard.elapsed=center-0.1
 check(d.melee_guard.can_guard(d),"green leading edge inclusive")
 d.melee_guard.elapsed=center+0.1
 check(d.melee_guard.can_guard(d),"green trailing edge inclusive")
 d.melee_guard.elapsed=center+0.10001
 check(not d.melee_guard.can_guard(d),"after green fails")
 d.melee_guard.elapsed=center
 var hp:float=d.hp
 check(d.try_saber(a),"melee button triggers guard")
 check(d.clash_count==1 and a.clash_count==1,"success uses symmetric clash")
 check(d.hp==hp,"successful guard prevents damage")
 check(not a.saber_active(),"incoming attack cancelled")
 a.queue_free()
 d.queue_free()
 await get_tree().process_frame
 a=unit(1)
 d=unit(0)
 a.position.z=-300
 a.look_at(d.position)
 Game.units.assign([a,d])
 d.fm.speed=1000
 d.fm.velocity=Vector3(0,0,-1000)
 d.velocity=d.fm.velocity
 a._slash(d)
 check(absf(d.hp-(500.0-a.profile.saber_damage*2.405))<0.001,"additional 30 percent damage increase")
 check(d.weapons_locked(),"weapon lock applied")
 check(absf(d.fm.speed-100)<0.001,"instant 90 percent slowdown")
 check(absf(d.velocity.length()-100)<0.001,"actual movement slowed")
 for method in ["fire_gun","fire_beam"]:check(not d.call(method,true,a),"primary blocked "+method)
 for method in ["fire_cannon","fire_funnel","fire_wire_arms","fire_bazooka","fire_gp03s_bazookas","try_gp03_grapple","try_saber"]:check(not d.call(method,a),"weapon blocked "+method)
 d.velocity=Vector3(2000,0,0)
 d.fm.velocity=d.velocity
 d.fm.speed=2000
 d.melee_guard.limit(d)
 check(d.velocity.length()<=100.001 and d.fm.speed<=100.001,"acceleration cannot bypass slow")
 d.melee_guard.tick(d,2.99)
 check(d.weapons_locked(),"lock lasts through 2.99 seconds")
 d.melee_guard.tick(d,0.01)
 check(not d.weapons_locked(),"lock expires at 3 seconds")
 check(d.melee_guard.slow_left>0,"slow remains after weapons unlock")
 d.melee_guard.tick(d,0.99)
 check(d.melee_guard.slow_left>0,"slow lasts through 3.99 seconds")
 d.melee_guard.tick(d,0.01)
 check(d.melee_guard.slow_left==0,"slow expires at four seconds")
 var speed:float=d.fm.speed
 d.velocity=Vector3(500,0,0)
 d.melee_guard.limit(d)
 check(d.velocity.length()>400,"movement restriction released")
 d.melee_guard.elapsed=0
 d.melee_guard.tick(d,2.0)
 check(d.melee_guard.elapsed==2.0,"bar expires at two seconds")
 a.queue_free()
 d.queue_free()
 await get_tree().process_frame
 var original_hz:=Engine.physics_ticks_per_second
 for hz in [30,60,120]:
  Engine.physics_ticks_per_second=hz
  for parry in [false,true]:
   a=unit(1)
   d=unit(0)
   d.is_player=true
   a.position.z=-500
   a.look_at(d.position)
   Game.units.assign([a,d])
   await get_tree().physics_frame
   check(a.try_saber(d),"physical approach starts")
   for frame in hz*2:
    d.melee_guard.tick(d,1.0/hz)
    if parry and d.melee_guard.can_guard(d):d.try_saber(a)
    a._physics_process(1.0/hz)
    if d.clash_count>0 or d.hp<500:break
    await get_tree().physics_frame
   if parry:
    check(d.clash_count==1 and d.hp==500,"timed input blocks real moving rush")
   else:
    check(d.hp<500 and d.weapons_locked(),"unblocked moving rush hits and disables weapons")
   a.queue_free()
   d.queue_free()
   await get_tree().process_frame
 Engine.physics_ticks_per_second=original_hz
 # Repeated hits refresh the duration, rather than multiplying the slow to 99%.
 a=unit(1)
 d=unit(0)
 Game.units.assign([a,d])
 d.fm.speed=1000
 d.fm.velocity=Vector3(0,0,-1000)
 d.velocity=d.fm.velocity
 d.take_damage(1,a,Damage.Type.SABER)
 d.take_damage(1,a,Damage.Type.SABER)
 check(absf(d.melee_guard.speed_cap-100)<0.001,"slow does not stack beyond 90 percent")
 for frame in 179:
  d._physics_process(1.0/60)
  check(d.velocity.length()<=100.01,"real flight cannot accelerate through slow")
 check(d.weapons_locked(),"real flight preserves 3-second lock")
 d._physics_process(1.0/60)
 check(not d.weapons_locked(),"real flight releases lock on schedule")
 print("MELEE_GUARD ",checks-failures," PASS / ",failures," FAIL")
 a.queue_free()
 d.queue_free()
 Game.units.clear()
 await get_tree().process_frame
 get_tree().quit(1 if failures>0 else 0)
