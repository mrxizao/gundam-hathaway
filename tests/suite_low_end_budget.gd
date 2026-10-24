extends RefCounted
static func run(t:T,host:Node) -> void:
 t.suite("Low-end 60 / bounded visuals and real model LOD")
 var previous:Dictionary={}
 for key in Settings.PERSISTED_VARS:previous[key]=Settings.get(key)
 var menu:=preload("res://scripts/ui/main_menu.gd").new()
 var home:=preload("res://scripts/ui/menu_home.gd").new();home.menu=menu;home.settings_tab=4
 t.eq(home.setting_indices().size(),6,"Performance tab exposes all six controls")
 t.ok(home.TABS.has("性能"),"Visible performance tab exists")
 home.free();menu.free()
 Settings.set_quality_preset(0)
 t.near(Settings.render_scale(),.75,.001,"Low preset sets render scale")
 t.ok(Settings.dynamic_resolution and Settings.shadow_quality==0,"Low preset disables shadows and allows adaptive scale")
 Settings.adjust_performance("render_scale",1)
 t.near(Settings.render_scale(),.85,.001,"Manual resolution adjustment")
 t.eq(Settings.quality_preset,3,"Manual changes mark preset custom")
 Settings.set_quality_preset(0)
 var container:=Node3D.new();host.add_child(container)
 var first:Missile
 for i in 80:
  var missile:=Missile.funnel(container,Vector3(i*5,1000,0),Vector3.FORWARD,null,null)
  missile.set_physics_process(false)
  if i==0:first=missile
 t.eq(host.get_tree().get_node_count_in_group("budget_missile_smoke"),64,"Smoke emitter count bounded across full salvo")
 t.eq(host.get_tree().get_node_count_in_group("budget_missile_ribbons"),24,"Long trail count bounded across full salvo")
 t.eq(container.get_child_count(),104,"All eighty missiles retained alongside 24 ribbons")
 t.eq(first.get_node("MissileTrail").amount,12,"Low-end trail particle budget")
 var second:=container.get_child(2) as Missile
 t.ok(second!=null and first.get_child(0).mesh==second.get_child(0).mesh,"Missile bodies share one mesh resource")
 for id in 9:
  var profile:=SuitProfile.by_id(id)
  var path:="res://assets/models/distant_lod/"+profile.model_path.md5_text()+".res"
  var mesh:=load(path) as Mesh
  t.ok(mesh!=null and mesh.get_surface_count()==1,"Actual silhouette merged for "+profile.id_name())
 var old_placeholder:=FlightBody.use_placeholder
 FlightBody.use_placeholder=false
 var unit:=FlightBody.new();unit.profile=SuitProfile.xi();container.add_child(unit)
 unit.set_physics_process(false)
 FlightBody.use_placeholder=old_placeholder
 var lod:=unit.model_root.get_node("DistantRealModel") as MeshInstance3D
 t.near(lod.visibility_range_begin,1200.0,.001,"Distant model begins after 1.2 km")
 t.ok(lod.visible,"Low-end enables actual-model LOD")
 var controller:=unit.model_root.get_child(unit.model_root.get_child_count()-2)
 Settings.set_quality_preset(2)
 controller._process(.3)
 t.ok(not lod.visible,"Original quality restores full model visibility")
 container.free()
 await host.get_tree().process_frame
 t.eq(host.get_tree().get_node_count_in_group("budget_missile_smoke"),0,"Smoke budget released on match cleanup")
 for key in previous:Settings.set(key,previous[key])
