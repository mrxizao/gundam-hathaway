extends RefCounted
const RifleTests = preload("res://tests/suite_rifle_accuracy.gd")
static func run(t: T,host: Node) -> void:
 t.suite("ReGZ Custom / loadout, forms and weapon lifecycle")
 Settings.begin_isolated()
 var old_placeholder := FlightBody.use_placeholder
 FlightBody.use_placeholder = false
 Game.reset()
 Game.active_map = MapDef.pacific()
 var stage := Node3D.new()
 host.add_child(stage)
 var p := PlayerController.new()
 p.profile = SuitProfile.regz_custom()
 p.is_player = true
 p.team = 0
 p.controls_enabled = true
 p.projectile_container = stage
 stage.add_child(p)
 p.set_physics_process(false)
 p.global_position = Vector3(0,3000,0)
 t.eq(p.rifle_mag,30,"30 round magazine")
 t.not_ok(p.profile.can_discard_rifle,"normal: discard capability disabled")
 t.not_ok(p.discard_rifle(),"normal: direct discard blocked")
 t.eq(p.rifle_count,1,"normal: rifle retained")
 t.eq(p._plume_fx.size(),4,"normal: four actual rear nozzles")
 for item in p._plume_fx:t.ok(item.has("nozzle_node"),"normal: flame follows source nozzle mesh")
 t.eq(p.flare_count,120,"120 countermeasures")
 t.eq(p.funnel_count,0,"no missile inventory")
 t.not_ok(p.profile.has_missiles,"no missile capability")
 t.ok(p.model_root.find_children("*","MeshInstance3D",true,false).size()>200,"new normal model renders")
 t.near(p.profile.player_top_speed()/SuitProfile.xi().player_top_speed(),0.65,0.0001,"normal cruise speed ratio")
 t.ok(p.toggle_form(),"Z route enters cruise")
 t.eq(p.profile.form,1,"cruise form")
 t.not_ok(p.profile.can_discard_rifle,"cruise: discard capability disabled")
 t.not_ok(p.discard_rifle(),"cruise: direct discard blocked")
 t.eq(p.rifle_count,1,"cruise: rifle retained")
 t.eq(p._plume_fx.size(),4,"cruise: four actual rear nozzles")
 for item in p._plume_fx:t.ok(item.has("nozzle_node"),"cruise: flame follows source nozzle mesh")
 t.near(p.profile.player_top_speed()/SuitProfile.arizeus(SuitProfile.ArizeusForm.CRUISE).player_top_speed(),0.95,0.0001,"cruise speed ratio")
 t.not_ok(PlayerController.assist_uses_translation(p.profile),"cruise retains Arizeus flight controls")
 p.form_cooldown=0.0
 t.ok(p.toggle_form(),"return from cruise")
 var w = p.regz_weapons
 t.not_ok(p.profile.can_ride_pedal(),"normal ReGZ cannot use a flight pedal")
 t.eq(p.configure_pedal(FlightPedal.Kind.KILCE,true),null,"forced spawn cannot bypass ReGZ pedal restriction")
 t.not_ok(p.mount_pedal(),"ReGZ cannot summon a platform")
 var previous_pad := InputSetup.using_gamepad
 for pad in [false,true]:
  InputSetup.using_gamepad=pad
  w.cancel();w.irradiation=false
  p.rifle_mag=30;p.rifle_cooldown=0.0;p.rifle_reloading=false
  w.tick(p,.016,true,true,false)
  t.eq(p.rifle_mag,29,"precision fires when primary was held before scope: "+str(pad))
  p.rifle_cooldown=0.0
  w.tick(p,.016,true,true,true)
  t.eq(p.rifle_mag,28,"precision fires without an acquired target: "+str(pad))
  var old_placeholder_for_target := FlightBody.use_placeholder
  FlightBody.use_placeholder=true
  var lost := RifleTests._foe(stage,p.global_position+p.forward()*1000.0)
  FlightBody.use_placeholder=old_placeholder_for_target
  w.selected=lost;lost.free();p.rifle_cooldown=0.0
  w.tick(p,.016,true,true,false)
  t.eq(p.rifle_mag,27,"held trigger survives target destruction: "+str(pad))
  p.rifle_cooldown=.10
  w.tick(p,.016,true,true,false)
  t.eq(p.rifle_mag,27,"precision still respects rifle cooldown: "+str(pad))
 w.cancel();InputSetup.using_gamepad=previous_pad
 p.rifle_mag=30;p.rifle_cooldown=0.0

 w.irradiation=true
 w.tick(p,3.0,true,true,true)
 t.near(w.charge,0.0,.001,"normal mode cannot charge MEGA cannon")
 t.not_ok(p.cannon_available(),"MEGA is absent from normal form loadout")
 w.fire_battery(p)
 t.eq(stage.find_children("*","BeamCannon",true,false).size(),0,"direct MEGA route cannot bypass cruise gate")
 p.form_cooldown=0.0
 p.toggle_form()
 t.not_ok(p.profile.can_ride_pedal(),"cruise ReGZ cannot use a flight pedal")
 t.eq(w.mode_name(),"MEGA光束加农炮","MEGA cannon name")
 w.irradiation=true
 w.tick(p,2.49,true,false,false)
 t.near(w.charge,2.49,0.001,"charge accumulates while held")
 w.tick(p,0.0,true,true,true)
 t.eq(stage.find_children("*","BeamCannon",true,false).size(),0,"cannot fire before 2.5 seconds")
 w.tick(p,0.01,true,false,false)
 w.tick(p,0.0,true,true,true)
 var beams: Array = []
 for child in stage.get_children():
  if child is BeamCannon: beams.append(child)
 t.eq(beams.size(),5,"five independent beams")
 if beams.size()==5:
  t.gt(beams[0].visual_scale,beams[1].visual_scale,"central beam largest")
  for beam in beams:
   t.eq(beam.color,Color(1.0,0.83,0.12),"yellow beam")
  t.lt(beams[1].local_offset.x,0.0,"left waist emitter")
  t.gt(beams[2].local_offset.x,0.0,"right waist emitter")
  t.gt(beams[3].local_offset.y,beams[1].local_offset.y,"shoulder emitter above waist")
 t.eq(p.rifle_mag,30,"irradiation does not silently consume rifle magazine")
 w.tick(p,0.1,false,false,false)
 t.near(w.charge,0.0,0.001,"release cancels charge")
 t.not_ok(w.held,"release exits mode")
 for beam in beams: beam.free()
 p.cannon_cd_left=0.0
 w.tick(p,1.0,true,false,false)
 p.fm.speed=p.profile.player_boost_speed()
 p.fm.velocity=p.forward()*p.fm.speed
 for i in 60: w.slow_flight(p,1.0/60.0)
 t.lt(p.fm.speed,p.profile.player_top_speed()*0.5,"charging actually slows flight")
 w.toggle()
 t.not_ok(w.charging(),"Alt cancels charging")
 t.near(w.charge,0.0,0.001,"Alt resets charge")
 p.rifle_mag=17
 p.flare_count=84
 p.form_cooldown=0.0
 p.toggle_form()
 t.eq(p.rifle_mag,17,"transform does not refill rifle")
 t.eq(p.flare_count,84,"transform does not refill flares")
 # Exercise the actual controller input route and shoulder camera, not only helpers.
 p.form_cooldown=0.0
 p.toggle_form()
 p.rifle_cooldown=0.0
 p.regz_weapons.irradiation=false
 var scoped_foe := RifleTests._foe(stage,p.global_position+p.forward()*1000.0)
 var locking := LockOnSystem.new()
 stage.add_child(locking)
 locking.setup(p)
 var camera := ChaseCamera.new()
 stage.add_child(camera)
 camera.target=p
 camera.set_physics_process(false)
 p.setup_refs(locking,camera)
 for frame in 60: camera.step_now(1.0/60.0)
 var normal_fov := camera.fov
 await host.get_tree().process_frame
 Input.action_press("fire_secondary")
 Input.action_press("fire_primary")
 p._read_weapon_input(0.016)
 t.eq(locking.target,scoped_foe,"left click in scope selects enemy through lock API")
 t.ok(p.precision_view_active(),"right button activates precision camera")
 for frame in 60: camera.step_now(1.0/60.0)
 t.lt(camera.fov,normal_fov*0.75,"scope actually zooms camera")
 t.gt(camera._desired_position().x-p.global_position.x,5.0,"scope actually shifts to shoulder")
 Input.action_release("fire_secondary")
 Input.action_release("fire_primary")
 p._read_weapon_input(0.016)
 t.not_ok(p.precision_view_active(),"right release restores normal camera mode")
 await host.get_tree().process_frame
 Input.action_press("missile_mode")
 p._read_view_input()
 Input.action_release("missile_mode")
 t.ok(p.regz_weapons.irradiation,"Alt switches the actual controller weapon mode")
 Input.action_press("fire_secondary")
 p.form_cooldown=0.0
 if p.profile.form != 1: p.toggle_form()
 p.cannon_cd_left=0.0
 p._read_weapon_input(1.0)
 t.gt(p.regz_weapons.charge,0.9,"right button enters irradiation charging")
 Input.action_release("fire_secondary")
 p._read_weapon_input(0.016)
 t.near(p.regz_weapons.charge,0.0,0.001,"actual right-button release cancels charge")
 stage.free()
 await host.get_tree().physics_frame
 FlightBody.use_placeholder=true
 t.suite("ReGZ Custom / real scoped projectiles against moving targets")
 var saved_pad := InputSetup.using_gamepad
 var shots := 0
 var hits := 0
 for pad in [false,true]:
  var device_hits := 0
  var device_shots := 0
  InputSetup.using_gamepad=pad
  for distance in [1000.0,3000.0,5500.0]:
   for transverse in [300.0,900.0,1600.0,2400.0]:
    var arena := RifleTests._stage(host)
    var unit := PlayerController.new()
    unit.profile=SuitProfile.regz_custom()
    unit.is_player=true
    unit.team=0
    unit.controls_enabled=true
    unit.projectile_container=arena
    arena.add_child(unit)
    unit.set_physics_process(false)
    unit.global_position=Vector3(0,3000,0)
    unit.regz_weapons.held=true
    var foe := RifleTests._foe(arena,Vector3(0,3000,-distance))
    foe.fm.velocity=Vector3(transverse,0,0)
    var mover := RifleTests.MovingTarget.new()
    mover.unit=foe
    mover.process_physics_priority=-10
    arena.add_child(mover)
    await host.get_tree().physics_frame
    var before := foe.hp
    t.ok(unit.fire_beam(true,foe),"scoped projectile emitted")
    device_shots+=1
    for frame in 45:
     await host.get_tree().physics_frame
     if Game.rifle_stats.pending.is_empty(): break
    if foe.hp<before: device_hits+=1
    arena.free()
    await host.get_tree().physics_frame
  var ratio := float(device_hits)/float(device_shots)
  print("REGZ_SCOPED_ACCURACY device=",pad," hits=",device_hits," shots=",device_shots," rate=",ratio)
  t.ok(ratio>=0.40,"scoped real projectile benchmark at least 40 percent")
  shots+=device_shots
  hits+=device_hits
 InputSetup.using_gamepad=saved_pad
 FlightBody.use_placeholder=old_placeholder
 Settings.end_isolated()
