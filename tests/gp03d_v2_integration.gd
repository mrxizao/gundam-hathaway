extends Node3D
var checks:=0
func check(value:bool,label:String)->void:
 if not value:
  push_error(label)
  get_tree().quit(1)
 assert(value,label)
 checks+=1
func _ready()->void:
 Settings.begin_isolated()
 Settings.low_end_60=false
 FlightBody.use_placeholder=false
 var shots:=Node3D.new()
 add_child(shots)
 var unit:=PlayerController.new()
 unit.profile=SuitProfile.gp03d()
 unit.team=0
 unit.is_player=true
 unit.projectile_container=shots
 add_child(unit)
 unit.set_physics_process(false)
 unit.set_process(false)
 var model:=unit.model_root.find_child("GP03D_V2",true,false)
 check(model!=null and model.get_meta("model_revision")=="2.0","Actual new asset instantiated")
 check(not unit.rig.placeholder_visible(),"No placeholder fallback")
 check(model.find_children("*","MeshInstance3D",true,false).size()==150,"All 150 supplied mesh parts preserved")
 check(model.find_child("ParentNode_001",true,false)!=null,"New Stamen core preserved")
 check(unit.model_bounds.size.distance_to(Vector3(62,38.5,140))<.05,"Calibrated dimensions unchanged")
 check(unit._muzzle_local.size()==1,"Single main cannon muzzle")
 check(unit.rig_anchor("muzzle_L").z< -69 and unit.rig_anchor("muzzle_L").x>10,"Cannon muzzle at correct tip")
 check(unit._plume_fx.size()==6,"Six propulsion mounts retained")
 for item:Dictionary in unit._plume_fx:check(item.fx.position.z>35,"Exhaust behind hull")
 check(unit.has_node("CannonHull") and unit.get_node("Hull").shape is BoxShape3D,"Both physical collision shapes retained")
 var foe:=FlightBody.new()
 foe.profile=SuitProfile.gustav00()
 foe.use_placeholder=true
 foe.team=1
 add_child(foe)
 foe.position=Vector3(14,3,-1400)
 foe.set_physics_process(false)
 foe.set_process(false)
 await get_tree().physics_frame
 check(unit.fire_beam(true,foe),"Primary beam fires")
 check(unit.fire_cannon(foe),"MEGA cannon fires")
 check(unit.active_cannon.global_position.distance_to(unit.to_global(unit.rig_anchor("muzzle_L")))<.01,"Cannon beam uses actual mesh mount")
 check(unit.fire_funnel(foe),"Missile pod fires")
 check(unit.funnel_count==1620,"One pod consumes 108 missiles")
 unit._show_blade()
 check(is_instance_valid(unit._blade_anchor),"Claw saber mounts successfully")
 unit._hide_blade()
 unit.set_model_visible(false)
 unit._tick_effects(.016)
 check(not unit.model_root.visible,"First person hides all imported geometry")
 for item:Dictionary in unit._plume_fx:check(not item.fx.visible,"First person hides rear propulsion")
 unit.set_model_visible(true)
 unit._tick_effects(.016)
 check(unit.model_root.visible,"Third person restores new model")
 check(ResourceLoader.exists("res://assets/models/distant_lod/"+unit.profile.model_path.md5_text()+".res"),"Low-end distant LOD available under new model path")
 FlightBody.use_placeholder=false
 check(unit.switch_form(1,false,true),"GP03S escape succeeds")
 await get_tree().process_frame
 check(unit.profile.id==SuitProfile.Id.GP03S,"Escape profile retained")
 check(unit.model_root.find_child("GP03D_V2",true,false)==null,"MA model detached after escape")
 check(unit.model_bounds.size.y>17 and unit.model_bounds.size.y<19,"GP03S real model loaded")
 Settings.end_isolated()
 print("GP03D V2 INTEGRATION: ",checks," PASS")
 get_tree().quit()
