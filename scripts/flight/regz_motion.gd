extends RefCounted
## Rigid mechanical joints: preserve every source mesh and its rest transform.
const PARTS := {
 "Hand.R": [
  "tripo_part_0",
  "tripo_part_34",
  "tripo_part_38",
  "tripo_part_39",
  "tripo_part_41",
  "tripo_part_92",
  "tripo_part_130",
  "tripo_part_172",
  "tripo_part_180",
  "tripo_part_185",
  "tripo_part_188",
  "tripo_part_189",
  "tripo_part_191",
  "tripo_part_213",
  "tripo_part_219"
 ],
 "Backpack": [
  "tripo_part_1",
  "tripo_part_3",
  "tripo_part_6",
  "tripo_part_10",
  "tripo_part_13",
  "tripo_part_42",
  "tripo_part_46",
  "tripo_part_47",
  "tripo_part_50",
  "tripo_part_51",
  "tripo_part_68",
  "tripo_part_69",
  "tripo_part_75",
  "tripo_part_82",
  "tripo_part_90",
  "tripo_part_91",
  "tripo_part_103",
  "tripo_part_112",
  "tripo_part_128",
  "tripo_part_131",
  "tripo_part_132",
  "tripo_part_147",
  "tripo_part_149",
  "tripo_part_154",
  "tripo_part_156",
  "tripo_part_158",
  "tripo_part_169",
  "tripo_part_171",
  "tripo_part_178",
  "tripo_part_202",
  "tripo_part_216",
  "tripo_part_229",
  "tripo_part_230",
  "tripo_part_231",
  "tripo_part_237",
  "tripo_part_238",
  "tripo_node_7650d746-e658-41b0-b757-c8d089a33828.001",
  "tripo_node_7650d746-e658-41b0-b757-c8d089a33828.002"
 ],
 "Head": [
  "tripo_part_2",
  "tripo_part_56",
  "tripo_part_57",
  "tripo_part_79",
  "tripo_part_134"
 ],
 "Weapon.R": [
  "tripo_part_4",
  "tripo_part_33",
  "tripo_part_93",
  "tripo_part_118",
  "tripo_part_137",
  "tripo_part_152",
  "tripo_part_153",
  "tripo_part_159",
  "tripo_part_161",
  "tripo_part_162",
  "tripo_part_166",
  "tripo_part_100",
  "tripo_part_108",
  "tripo_part_193",
  "tripo_part_222"
 ],
 "Hand.L": [
  "tripo_part_5",
  "tripo_part_16",
  "tripo_part_35",
  "tripo_part_36",
  "tripo_part_37",
  "tripo_part_40",
  "tripo_part_48",
  "tripo_part_120",
  "tripo_part_174",
  "tripo_part_181",
  "tripo_part_182",
  "tripo_part_186",
  "tripo_part_187"
 ],
 "Hips": [
  "tripo_part_7",
  "tripo_part_17",
  "tripo_part_18",
  "tripo_part_43",
  "tripo_part_49",
  "tripo_part_81",
  "tripo_part_133",
  "tripo_part_135",
  "tripo_part_155",
  "tripo_part_157"
 ],
 "LowerArm.L": [
  "tripo_part_8",
  "tripo_part_12",
  "tripo_part_14",
  "tripo_part_29",
  "tripo_part_98",
  "tripo_part_111",
  "tripo_part_126",
  "tripo_part_129",
  "tripo_part_136",
  "tripo_part_150",
  "tripo_part_151",
  "tripo_part_176",
  "tripo_part_177",
  "tripo_part_196",
  "tripo_part_204"
 ],
 "LowerArm.R": [
  "tripo_part_9",
  "tripo_part_124",
  "tripo_part_183",
  "tripo_part_190",
  "tripo_part_195",
  "tripo_part_199",
  "tripo_part_203",
  "tripo_part_228",
  "tripo_part_232",
  "tripo_part_242",
  "tripo_part_250"
 ],
 "Shin.R": [
  "tripo_part_11",
  "tripo_part_26",
  "tripo_part_44",
  "tripo_part_54",
  "tripo_part_63",
  "tripo_part_83",
  "tripo_part_84",
  "tripo_part_140",
  "tripo_part_209",
  "tripo_part_217",
  "tripo_part_218",
  "tripo_part_223"
 ],
 "Shoulder.R": [
  "tripo_part_15",
  "tripo_part_60",
  "tripo_part_71",
  "tripo_part_72",
  "tripo_part_110",
  "tripo_part_125",
  "tripo_part_143"
 ],
 "Chest": [
  "tripo_part_19",
  "tripo_part_20",
  "tripo_part_21",
  "tripo_part_24",
  "tripo_part_58",
  "tripo_part_61",
  "tripo_part_64",
  "tripo_part_66",
  "tripo_part_74",
  "tripo_part_76",
  "tripo_part_95",
  "tripo_part_96",
  "tripo_part_97",
  "tripo_part_104",
  "tripo_part_105",
  "tripo_part_106",
  "tripo_part_121",
  "tripo_part_145",
  "tripo_part_146",
  "tripo_part_148",
  "tripo_part_160",
  "tripo_part_163",
  "tripo_part_164",
  "tripo_part_165",
  "tripo_part_167",
  "tripo_part_168",
  "tripo_part_170",
  "tripo_part_179",
  "tripo_part_184",
  "tripo_part_194",
  "tripo_part_197",
  "tripo_part_198",
  "tripo_part_201",
  "tripo_part_206",
  "tripo_part_207",
  "tripo_part_211",
  "tripo_part_212",
  "tripo_part_220",
  "tripo_part_224",
  "tripo_part_225",
  "tripo_part_234",
  "tripo_part_236",
  "tripo_part_239",
  "tripo_part_251"
 ],
 "Thigh.R": [
  "tripo_part_23",
  "tripo_part_88",
  "tripo_part_107",
  "tripo_part_109",
  "tripo_part_119"
 ],
 "Shin.L": [
  "tripo_part_25",
  "tripo_part_45",
  "tripo_part_52",
  "tripo_part_55",
  "tripo_part_62",
  "tripo_part_85",
  "tripo_part_86",
  "tripo_part_141",
  "tripo_part_221",
  "tripo_part_226",
  "tripo_part_227",
  "tripo_part_233",
  "tripo_part_235"
 ],
 "Shoulder.L": [
  "tripo_part_27",
  "tripo_part_32",
  "tripo_part_59",
  "tripo_part_65",
  "tripo_part_70",
  "tripo_part_73",
  "tripo_part_94",
  "tripo_part_123",
  "tripo_part_138"
 ],
 "Thigh.L": [
  "tripo_part_30",
  "tripo_part_31",
  "tripo_part_87"
 ],
 "UpperArm.R": [
  "tripo_part_53",
  "tripo_part_67",
  "tripo_part_77",
  "tripo_part_173",
  "tripo_part_192"
 ],
 "UpperArm.L": [
  "tripo_part_78",
  "tripo_part_127",
  "tripo_part_175",
  "tripo_part_205",
  "tripo_part_208"
 ],
 "Foot.L": [
  "tripo_part_80",
  "tripo_part_102",
  "tripo_part_117",
  "tripo_part_139",
  "tripo_part_144",
  "tripo_part_215",
  "tripo_part_254"
 ],
 "Foot.R": [
  "tripo_part_89",
  "tripo_part_99",
  "tripo_part_101",
  "tripo_part_116",
  "tripo_part_122",
  "tripo_part_142",
  "tripo_part_214"
 ]
}

const JOINTS := [
 ["Hips","",Vector3(-0.03,-0.05,0)],
 ["Chest","Hips",Vector3(-0.03,0.12,0)],
 ["Head","Chest",Vector3(-0.03,0.32,-0.02)],
 ["Backpack","Chest",Vector3(-0.03,0.15,0.12)],
 ["Shoulder.R","Chest",Vector3(0.13,0.26,-0.02)],
 ["Shoulder.L","Chest",Vector3(-0.18,0.26,0)],
 ["UpperArm.R","Shoulder.R",Vector3(0.14,0.235,-0.03)],
 ["UpperArm.L","Shoulder.L",Vector3(-0.20,0.235,-0.01)],
 ["LowerArm.R","UpperArm.R",Vector3(0.155,0.16,-0.04)],
 ["LowerArm.L","UpperArm.L",Vector3(-0.22,0.16,-0.02)],
 ["Hand.R","LowerArm.R",Vector3(0.195,0.035,-0.08)],
 ["Hand.L","LowerArm.L",Vector3(-0.21,0.03,-0.03)],
 ["Weapon.R","Hand.R",Vector3(0.195,0.035,-0.08)],
 ["Thigh.R","Hips",Vector3(0.065,-0.06,0)],
 ["Thigh.L","Hips",Vector3(-0.125,-0.06,0)],
 ["Shin.R","Thigh.R",Vector3(0.125,-0.26,-0.02)],
 ["Shin.L","Thigh.L",Vector3(-0.17,-0.26,-0.02)],
 ["Foot.R","Shin.R",Vector3(0.15,-0.43,0.015)],
 ["Foot.L","Shin.L",Vector3(-0.17,-0.43,0.015)]
]
const REST_BARREL := Vector3(0.32690911,-0.79509686,-0.51083403)
const MUZZLE := Vector3(0.333,-0.329,-0.404)
const DASH_DIRS := {"f":Vector3(0,0,-1),"b":Vector3(0,0,1),"l":Vector3(-1,0,0),"r":Vector3(1,0,0),"fl":Vector3(-1,0,-1),"fr":Vector3(1,0,-1),"bl":Vector3(-1,0,1),"br":Vector3(1,0,1),"u":Vector3(0,1,0),"d":Vector3(0,-1,0)}
var unit
var joints: Dictionary = {}
var rest: Dictionary = {}
var muzzle: Marker3D
var ports: Array[Marker3D] = []
var bound_parts := 0
var ready := false
var aim_blend := 0.0
var charge_blend := 0.0
var fire_blend := 0.0
var clock := 0.0
var scale_m := 20.0
var cruise := false

func install(owner_unit) -> void:
 unit = owner_unit
 if unit.placeholder_only: return
 var meshes: Dictionary = {}
 for mesh in unit.model_root.find_children("*","MeshInstance3D",true,false):
  meshes[str(mesh.name)] = mesh
  meshes[str(mesh.name).replace("_001",".001").replace("_002",".002")] = mesh
 if not meshes.has("tripo_part_4"): return
 scale_m = unit.profile.target_height/unit.profile.model_native_height
 if unit.profile.form == 1:
  install_cruise(meshes)
  return
 for spec in JOINTS:
  var node := Node3D.new()
  node.name = "Regz_"+str(spec[0]).replace(".","_")
  var parent: Node3D = unit.model_root if str(spec[1]).is_empty() else joints[spec[1]]
  parent.add_child(node)
  var origin: Vector3 = spec[2]*scale_m
  if not str(spec[1]).is_empty(): origin -= rest[spec[1]]
  node.position = origin
  joints[spec[0]] = node
  rest[spec[0]] = spec[2]*scale_m
 for name in PARTS:
  for part in PARTS[name]:
   if meshes.has(part):
    meshes[part].reparent(joints[name],true)
    bound_parts += 1
 muzzle = marker("RifleMuzzle","Weapon.R",MUZZLE)
 muzzle.basis = Basis.looking_at(REST_BARREL.normalized(),Vector3.UP)
 ports.append(muzzle)
 ports.append(marker("WaistLeft","Hips",Vector3(-0.12,-0.06,-0.115)))
 ports.append(marker("WaistRight","Hips",Vector3(0.07,-0.06,-0.115)))
 ports.append(marker("ShoulderLeft","Shoulder.L",Vector3(-0.174,0.282,-0.085)))
 ports.append(marker("ShoulderRight","Shoulder.R",Vector3(0.111,0.277,-0.105)))
 unit._model_mounts["muzzle_L"] = muzzle
 unit._model_mounts["muzzle_R"] = muzzle
 ready = bound_parts == 239

func install_cruise(meshes: Dictionary) -> void:
 cruise = true
 var mount := Node3D.new()
 mount.name = "Regz_CruiseGun"
 unit.model_root.add_child(mount)
 mount.position = Vector3(0.204,-0.235,-0.187)*scale_m
 joints["CruiseGun"] = mount
 rest["CruiseGun"] = mount.position
 for part in PARTS["Weapon.R"]:
  if meshes.has(part):
   meshes[part].reparent(mount,true)
   bound_parts += 1
 muzzle = marker("CruiseMuzzle","CruiseGun",Vector3(0.205,-0.246,-0.555))
 muzzle.basis = Basis.looking_at(Vector3(0.009,-0.027,-1).normalized(),Vector3.UP)
 ports.append(muzzle)
 for point in [Vector3(-3.4,0,-6),Vector3(3.4,0,-6),Vector3(-5.6,2,-3),Vector3(5.6,2,-3)]:
  var port := Marker3D.new()
  unit.model_root.add_child(port)
  port.position = point-unit.model_root.position
  ports.append(port)
 unit._model_mounts["muzzle_L"] = muzzle
 unit._model_mounts["muzzle_R"] = muzzle
 ready = bound_parts == PARTS["Weapon.R"].size()

func marker(label: String,parent: String,point: Vector3) -> Marker3D:
 var node := Marker3D.new()
 node.name = "Regz_"+label
 joints[parent].add_child(node)
 node.position = point*scale_m-rest[parent]
 return node

func muzzle_local() -> Vector3:
 return unit.to_local(muzzle.global_position)

func port_local(index: int) -> Vector3:
 return unit.to_local(ports[clampi(index,0,ports.size()-1)].global_position)

func pose_angles(direction: Vector3, dash: float, aim: float, charge: float, firing: float) -> Dictionary:
 var forward := -direction.z
 var side := direction.x
 var vertical := direction.y
 var combat := maxf(aim,maxf(charge,firing))
 var d := dash*(1.0-combat*0.55)
 var pose := {}
 for spec in JOINTS: pose[spec[0]] = Vector3.ZERO
 pose["Chest"] = Vector3(-forward*11.0-vertical*5.0,-side*7.0,-side*9.0)*d + Vector3(-2.0*aim+4.0*charge-6.0*firing,0,0)
 pose["Head"] = Vector3(forward*5.0,side*4.0,side*3.0)*d
 pose["UpperArm.R"] = Vector3(-forward*15.0+vertical*8.0,side*4.0,8.0-side*10.0)*d + Vector3(8,10,-30)*aim + Vector3(5,7,-21)*charge + Vector3(8,10,-30)*firing
 pose["UpperArm.L"] = Vector3(-forward*12.0-vertical*5.0,side*3.0,-8.0-side*8.0)*d + Vector3(3,-4,-5)*aim + Vector3(8,-8,-18)*charge + Vector3(6,-8,-23)*firing
 pose["LowerArm.R"] = Vector3(18.0+side*6.0+vertical*5.0,0,0)*d + Vector3(42,8,0)*aim + Vector3(37,5,0)*charge + Vector3(42,8,0)*firing
 pose["LowerArm.L"] = Vector3(15.0-side*5.0-vertical*4.0,0,0)*d + Vector3(8,0,0)*aim + Vector3(12,-4,0)*charge + Vector3(16,-4,0)*firing
 pose["Shoulder.R"] = Vector3(0,0,4*charge+6*firing)
 pose["Shoulder.L"] = Vector3(0,0,-4*charge-6*firing)
 pose["Thigh.R"] = Vector3(-forward*14.0+side*11.0-vertical*10.0,side*4.0,6.0-side*7.0)*d + Vector3(-7,0,5)*charge + Vector3(-10,0,7)*firing
 pose["Thigh.L"] = Vector3(-forward*14.0-side*11.0+vertical*5.0,side*4.0,-6.0-side*7.0)*d + Vector3(-7,0,-5)*charge + Vector3(-10,0,-7)*firing
 pose["Shin.R"] = Vector3(16.0+side*8.0+maxf(direction.z,0.0)*8.0,0,0)*d + Vector3(12,0,0)*charge + Vector3(16,0,0)*firing
 pose["Shin.L"] = Vector3(16.0-side*8.0+maxf(direction.z,0.0)*8.0,0,0)*d + Vector3(12,0,0)*charge + Vector3(16,0,0)*firing
 pose["Foot.R"] = Vector3(-8,0,0)*d + Vector3(-5,0,0)*firing
 pose["Foot.L"] = Vector3(-8,0,0)*d + Vector3(-5,0,0)*firing
 return pose

func step(delta: float) -> void:
 if not ready or not is_instance_valid(muzzle): return
 clock += delta
 var aim := 0.0
 var charge := 0.0
 var firing := 1.0 if is_instance_valid(unit.active_cannon) and not unit.active_cannon.is_queued_for_deletion() else 0.0
 if unit.has_method("is_regz") and unit.is_regz() and unit.alive and unit.controls_enabled:
  aim = 1.0 if unit.regz_weapons.scope_active() else 0.0
  charge = 1.0 if unit.regz_weapons.charging() and firing<0.5 else 0.0
 if firing>0.5: aim = 0.0
 aim_blend = lerpf(aim_blend,aim,1.0-exp(-12.0*delta))
 charge_blend = lerpf(charge_blend,charge,1.0-exp(-9.0*delta))
 fire_blend = lerpf(fire_blend,firing,1.0-exp(-14.0*delta))
 var total := maxf(aim_blend+charge_blend+fire_blend,1.0)
 var combat := clampf(aim_blend+charge_blend+fire_blend,0.0,1.0)
 if cruise:
  unit.model_pivot.rotation_degrees.x -= unit._hover_pose*combat
  unit.model_pivot.rotation_degrees.x += -2.0*aim_blend+3.0*charge_blend-4.0*fire_blend+sin(clock*18.0)*0.4*fire_blend
  var gun: Node3D = joints["CruiseGun"]
  gun.position = rest["CruiseGun"]+Vector3(0,0,maxf(1.0-unit._gun_recoil_clock/0.16,0.0)*0.14)
  gun.quaternion = gun.quaternion.slerp(Quaternion.IDENTITY,1.0-exp(-12.0*delta))
  if combat>0.001:
   var correction := Quaternion(-muzzle.global_basis.z.normalized(),unit.aim_forward().normalized())
   gun.global_basis = Basis(Quaternion.IDENTITY.slerp(correction,combat))*gun.global_basis
  return
 var direction: Vector3 = DASH_DIRS.get(unit._dash_anim_dir,Vector3.ZERO).normalized()
 var dash := 0.0
 if unit._qb_timer>0.0:
  var elapsed: float = unit.QB_TIME-unit._qb_timer
  dash = smoothstep(0.0,0.06,elapsed)*(1.0-smoothstep(unit.QB_TIME-0.13,unit.QB_TIME,elapsed))
 if dash <= 0.001 and unit.is_player and unit.alive and unit.controls_enabled:
  var input: Vector2 = unit._input_pose.intent
  direction = Vector3(input.x,0.0,-input.y)
  dash = input.length()*0.38
 var pose := pose_angles(direction,dash,aim_blend/total,charge_blend/total,fire_blend/total)
 for name in joints:
  var node: Node3D = joints[name]
  var angles: Vector3 = pose[name]
  if name == "Chest": angles.x += sin(clock*22.0)*0.8*fire_blend
  var target := Basis.from_euler(angles*PI/180.0).get_rotation_quaternion()
  node.quaternion = node.quaternion.slerp(target,1.0-exp(-18.0*delta))
 var weapon: Node3D = joints["Weapon.R"]
 var recoil: float = maxf(1.0-unit._gun_recoil_clock/0.16,0.0)
 weapon.position = -REST_BARREL.normalized()*recoil*scale_m*0.007
 unit.model_pivot.rotation_degrees.x -= unit._hover_pose*combat
 # Fine wrist correction keeps the actual barrel on the independent sight ray.
 if combat>0.001:
  var desired: Vector3 = unit.aim_forward()
  var current: Vector3 = -muzzle.global_basis.z.normalized()
  var correction := Quaternion(current,desired.normalized())
  var hand: Node3D = joints["Hand.R"]
  hand.global_basis = Basis(Quaternion.IDENTITY.slerp(correction,combat))*hand.global_basis
