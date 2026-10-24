extends "res://tests/gp03d_entry_probe.gd"
func owner_scene()->FakeMain:
 var main:=FakeMain.new();add_child(main)
 main.units_root=Node3D.new();main.add_child(main.units_root)
 main.projectiles=Node3D.new();main.add_child(main.projectiles)
 main.chase=ChaseCamera.new();main.add_child(main.chase);main.chase.set_physics_process(false)
 main.hud=Control.new();main.add_child(main.hud)
 main.world=FakeWorld.new();main.add_child(main.world)
 FlightBody.use_placeholder=true
 main.player=PlayerController.new();main.player.profile=SuitProfile.neue_ziel();main.units_root.add_child(main.player)
 main.player.set_process(false);main.player.set_physics_process(false);main.player.controls_enabled=true
 main.player.position=Vector3(300,2000,900)
 FlightBody.use_placeholder=false
 return main
func _ready()->void:
 Settings.begin_isolated();Settings.low_end_60=true
 var main:=owner_scene();var previous:=main.player.position
 var original_units:=Game.units.size()
 var director:=preload("res://scripts/cinematics/neue_entry_director.gd").new()
 director.setup(main);main.add_child(director)
 check(director.actor.model_root.find_child("NeueZiel",true,false)!=null,"Real Neue Ziel model loaded")
 check(Game.units.size()==original_units,"Cinematic actor never registers for combat")
 check(not main.player.controls_enabled and not main.hud.visible,"Combat/HUD suspended")
 check(director.music.playing and director.music.stream==load(SoundBank.bgm_path("men_of_destiny")),"MEN OF DESTINY plays")
 check(director.music.bus==Settings.BUS_BGM,"Existing BGM volume respected")
 var timeline=preload("res://scripts/data/sortie_script.gd")
 check(timeline.supported(SuitProfile.neue_ziel()),"Neue Ziel launch routing enabled")
 check(is_equal_approx(timeline.duration(SuitProfile.neue_ziel()),15.2),"Reference sequence duration")
 for t in [1.5,4.8,6.1,8.0,11.0,12.4,14.0]:
  director.time=t;director.pose(.016)
  check(director.camera.position.is_finite() and director.actor.position.is_finite(),"Finite camera and actor")
  check(director.last_shot==timeline.stage_at(SuitProfile.neue_ziel(),t),"Shared sequence agrees with director")
  check(main.projectiles.get_child_count()==0,"Visual beams never spawn combat projectiles")
  if DisplayServer.get_name()!="headless":
   for frame in 8:await get_tree().process_frame
   await RenderingServer.frame_post_draw
   get_viewport().get_texture().get_image().save_png("C:/Users/MSIPC/Documents/Codex/2026-10-07/c-users-msipc-documents-gundam-2/work/neue_entry/shot_%.1f.png"%t)
 check(director.melee_display.get_script()==preload("res://scripts/combat/neue_aux_sabers.gd"),"Reuses existing combat melee animation")
 check(director.melee_display.limbs.size()==4 and director.melee_display.claw_blades.size()==2,"Four auxiliary arms and two original claw blade mounts")
 director.time=6.6;director.pose(0.0)
 var folded:Vector3=director.melee_display.limbs[0].blade.position
 director.time=8.0;director.pose(0.0)
 check(director.melee_display.visible,"Arms visible in frontal reveal")
 check(director.melee_display.limbs[0].blade.position.distance_to(folded)>15.0,"Actual melee arm geometry extends")
 check(director.actor.saber_state==FlightBody.SaberState.IDLE,"Display never enters a combat attack state")
 check(main.projectiles.get_child_count()==0,"Melee display creates no damaging projectiles")
 director.time=14.0;director.pose(0.0)
 check(not director.melee_display.visible,"Auxiliary melee display hidden outside its shot")
 check(not director.actor.model_root.visible,"Final beam corridor hides exterior MA")
 director.time=11.0;director.pose(.016)
 check(director.beams.visible and director.beams.multimesh.instance_count==20,"Twenty visual beam streaks")
 for i in 20:
  var port:int=i%5
  var intended:Vector3=(director.actor.global_basis*Vector3((port-2)*.25,sin(port*1.2)*.15,-1)).normalized()
  var transform:Transform3D=director.rod_transform(Vector3.ZERO,intended*260.0)
  if DisplayServer.get_name()!="headless":transform=director.beams.multimesh.get_instance_transform(i)
  check(transform.basis.y.normalized().dot(intended)>.9999,"Beam long axis follows firing direction")
  check(absf(transform.basis.y.length()-260.0)<.01,"Beam length scales on its local axis")
 var signals:=[0];director.finished.connect(func():signals[0]+=1)
 director.finish();director.finish()
 check(signals[0]==1,"Natural finish exactly once")
 check(main.player.controls_enabled and main.hud.visible,"Controls and HUD restored")
 check(main.player.position==previous,"Map spawn unchanged")
 check(not director.music.playing,"Intro music stops on finish")
 director.queue_free();await get_tree().process_frame
 var skipped:=preload("res://scripts/cinematics/neue_entry_director.gd").new();skipped.setup(main);main.add_child(skipped);skipped.time=.8
 var event:=InputEventKey.new();event.pressed=true;event.keycode=KEY_SPACE;skipped._unhandled_input(event)
 check(skipped.cleaned and main.player.controls_enabled,"Skip restores gameplay")
 skipped.queue_free();main.queue_free()
 for frame in 4:await get_tree().process_frame
 Settings.end_isolated();print("NEUE ENTRY: ",checks," PASS");get_tree().quit()
