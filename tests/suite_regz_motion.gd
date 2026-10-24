extends RefCounted
static func advance(unit,frames := 90) -> void:
 for frame in frames: unit._tick_effects(1.0/60.0)
static func barrel_axis(mesh: MeshInstance3D) -> Vector3:
 var points: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
 var center := Vector3.ZERO
 for point in points: center += mesh.global_transform*point
 center /= float(points.size())
 var axis := Vector3(0.3,0.7,0.5).normalized()
 for iteration in 24:
  var next := Vector3.ZERO
  for point in points:
   var offset: Vector3 = mesh.global_transform*point-center
   next += offset*offset.dot(axis)
  axis = next.normalized()
 return axis
static func run(t: T,host: Node) -> void:
 t.suite("ReGZ Motion / real rigid parts, weapon poses and tracked emitters")
 Settings.begin_isolated()
 var old_placeholder := FlightBody.use_placeholder
 FlightBody.use_placeholder = false
 Game.active_map = MapDef.pacific()
 var arena := Node3D.new()
 host.add_child(arena)
 var unit := PlayerController.new()
 unit.profile = SuitProfile.regz_custom()
 unit.is_player=true
 unit.controls_enabled=true
 unit.team=0
 unit.projectile_container=arena
 arena.add_child(unit)
 unit.set_process(false)
 unit.set_physics_process(false)
 unit.position=Vector3(0,3000,0)
 unit.fm.speed=500.0
 unit.fm.velocity=Vector3(0,0,-500)
 unit.flight_pitch_deg=18.0
 unit.fm.hovering=false
 var motion = unit._regz_motion
 t.ok(motion.ready,"mechanical motion rig installed")
 t.eq(motion.bound_parts,239,"all 239 source parts retained and bound")
 var before_velocity: Vector3 = unit.fm.velocity
 var before_ammo: int = unit.rifle_mag
 var physics_position: Vector3 = unit.position
 var barrel := unit.model_root.find_child("tripo_part_4",true,false) as MeshInstance3D
 var sights: Array = []
 for id in [100,108,193,222]:
  var sight := unit.model_root.find_child("tripo_part_%d" % id,true,false) as Node3D
  t.eq(sight.get_parent(),motion.joints["Weapon.R"],"rifle sight follows gun, not leg")
  sights.append([sight,sight.transform])
 unit.regz_weapons.held=true
 unit.regz_weapons.irradiation=false
 unit.aim_dir=Vector3(0.09,0.10,-1).normalized()
 advance(unit)
 var aim_hand: Vector3 = motion.joints["Hand.R"].global_position
 var aim_chest: Quaternion = motion.joints["Chest"].quaternion
 t.gt(absf(barrel_axis(barrel).dot(unit.aim_forward())),0.995,"actual barrel geometry aims at sight ray while flying")
 t.lt(unit._rifle_origin().distance_to(motion.muzzle.global_position),0.001,"actual projectile origin follows animated gun")
 t.gt(motion.joints["LowerArm.R"].rotation_degrees.x,25.0,"precision mode actually raises forearm")
 # Fire an actual projectile from the posed, raised gun into a real hostile collider.
 var target := FlightBody.new()
 target.profile=SuitProfile.gustav00_armed()
 target.placeholder_only=true
 target.team=1
 arena.add_child(target)
 target.set_physics_process(false)
 target.position=unit.position+unit.aim_forward()*1000.0
 target.ifield_hp=0.0
 target.hp=10000.0
 target.fm.velocity=Vector3.ZERO
 await host.get_tree().physics_frame
 var target_hp: float = target.hp
 unit.rifle_cooldown=0.0
 t.ok(unit.fire_beam(true,target),"raised rifle emits a real projectile")
 var projectile: Projectile
 for child in arena.get_children():
  if child is Projectile: projectile=child
 t.ok(projectile != null,"real muzzle projectile exists")
 if projectile != null:
  t.lt(projectile.global_position.distance_to(motion.muzzle.global_position),0.001,"shot starts at the visible raised muzzle")
 for frame in 20:
  await host.get_tree().physics_frame
  if target.hp<target_hp: break
 t.lt(target.hp,target_hp,"raised rifle shot deals actual damage")
 before_ammo=unit.rifle_mag
 target.free()
 unit.regz_weapons.irradiation=true
 unit.regz_weapons.tick(unit,3.0,true,false,false)
 advance(unit)
 t.not_ok(unit.regz_weapons.charging(),"normal form does not enter cannon brace")
 unit.regz_weapons.fire_battery(unit)
 t.eq(arena.find_children("*","BeamCannon",true,false).size(),0,"normal form cannot emit MEGA cannon")
 for record in sights: t.ok(record[0].transform.is_equal_approx(record[1]),"small gun parts remain rigidly attached in all poses")
 t.eq(unit.position,physics_position,"poses never move physical unit")
 t.eq(unit.fm.velocity,before_velocity,"poses never change flight velocity")
 t.eq(unit.rifle_mag,before_ammo,"poses never consume ammunition")
 for child in arena.get_children():
  if child is BeamCannon: child.free()
 unit.regz_weapons.cancel()
 advance(unit)
 t.lt(motion.joints["UpperArm.R"].rotation.length(),0.001,"right release recovers original stance")
 t.lt(motion.joints["LowerArm.R"].rotation.length(),0.001,"right release lowers forearm")
 t.suite("ReGZ Motion / eight-direction and vertical quick boosts")
 var signatures: Array = []
 for direction in ["f","b","l","r","fl","fr","bl","br","u","d"]:
  unit._dash_anim_dir=direction
  unit._qb_dir=motion.DASH_DIRS[direction].normalized()
  for frame in 45:
   unit._qb_timer=unit.QB_TIME-0.15
   unit._tick_effects(1.0/60.0)
  var signature: Array = []
  for joint in ["Chest","UpperArm.R","UpperArm.L","Thigh.R","Thigh.L","Shin.R","Shin.L"]:
   var node: Node3D = motion.joints[joint]
   t.ok(node.global_transform.is_finite(),"finite joint in "+direction)
   signature.append(node.quaternion)
  for previous in signatures:
   var different := false
   for index in signature.size():
    if signature[index].angle_to(previous[index])>0.02: different=true
   t.ok(different,"distinct limb and torso motion for "+direction)
  signatures.append(signature)
 unit._qb_timer=0.0
 unit._dash_anim_dir=""
 advance(unit)
 t.lt(motion.joints["Shin.R"].rotation.length(),0.001,"dash recovers to rest")
 t.suite("ReGZ Motion / live quick-boost commit and recovery")
 t.not_ok(unit.profile.dash_spin_visual,"own limb animation is not hidden by inherited full-body spin")
 unit.assist_on=true
 unit.translate_mode=true
 for direction in ["f","b","l","r","fl","fr","bl","br","u","d"]:
  unit.global_basis=Basis.IDENTITY
  unit.position=Vector3(0,3000,0)
  unit._qb_timer=0.0
  unit.dash_cd=0.0
  unit.dash_charge=1.0
  unit.fm.boosting=true
  unit.translate_dir=motion.DASH_DIRS[direction].normalized()
  unit.request_quick_boost()
  unit._apply_translate(1.0/60.0)
  t.eq(unit._dash_anim_dir,direction,"real quick-boost commit selects "+direction)
  t.gt(unit._qb_timer,0.0,"real boost starts its motion envelope")
  unit._tick_effects(1.0/60.0)
  t.ok(motion.joints["Chest"].global_transform.is_finite(),"committed motion updates actual mesh joints")
 unit._qb_timer=0.0
 unit._dash_anim_dir=""
 t.suite("ReGZ Motion / cruise lifecycle and actual rifle muzzle")
 t.ok(unit.switch_form(1),"cruise switch still works")
 var cruise = unit._regz_motion
 t.ok(cruise.ready and cruise.cruise,"cruise uses its own gun mount instead of humanoid joints")
 t.eq(cruise.bound_parts,15,"cruise retains all gun components")
 unit.cannon_cd_left=0.0
 unit.regz_weapons.fire_battery(unit)
 var cannon_count := 0
 for child in arena.get_children():
  if child is BeamCannon:
   cannon_count+=1
   child.set_physics_process(false)
   child._physics_process(.016)
   t.lt(child.local_offset.distance_to(cruise.port_local(child.emitter_index)),.001,"cruise MEGA beam follows actual emitter")
 t.eq(cannon_count,5,"cruise retains five-beam MEGA pattern")
 for child in arena.get_children():
  if child is BeamCannon: child.free()
 unit.active_cannon=null
 unit.regz_weapons.irradiation=false
 unit.regz_weapons.held=true
 advance(unit)
 t.gt((-cruise.muzzle.global_basis.z).normalized().dot(unit.aim_forward()),0.995,"cruise gun also follows sight")
 t.lt(unit._rifle_origin().distance_to(cruise.muzzle.global_position),0.001,"cruise projectile leaves actual gun")
 t.ok(unit.switch_form(0),"return restores normal rig")
 t.ok(unit._regz_motion.ready and unit._regz_motion.bound_parts==239,"normal rig rebuilt without stale joint references")
 arena.free()
 await host.get_tree().process_frame
 FlightBody.use_placeholder=old_placeholder
 Settings.end_isolated()
