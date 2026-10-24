extends Node
var hud: FlightHUD
var p: PlayerController
var checks:=0
func check(ok: bool,message: String) -> void:
	if not ok: push_error(message);get_tree().quit(1)
	else: checks+=1;print("PASS ",message)
func frames(n: int) -> void:
	for i in n: await get_tree().process_frame
func _ready() -> void:
	Settings.begin_isolated();Settings.first_person=true;Game.phase=Game.Phase.FIGHT
	var world:=Node3D.new();add_child(world)
	FlightBody.use_placeholder=true
	p=PlayerController.new();p.profile=SuitProfile.messer_m01();world.add_child(p)
	FlightBody.use_placeholder=false
	p.set_process(false);p.set_physics_process(false);p.visible=false
	p.global_position=Vector3(0,4200,0);p.fm.speed=280;p.fm.throttle=0.72
	var cam:=ChaseCamera.new();world.add_child(cam);cam.set_process(false);cam.global_position=p.global_position
	var layer:=CanvasLayer.new();add_child(layer)
	var bg:=ColorRect.new();bg.color=Color(0.08,0.12,0.20);bg.z_index=-5;bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layer.add_child(bg)
	hud=FlightHUD.new();hud.player=p;hud.camera=cam;hud.lock=LockOnSystem.new();hud.lock.unit=p;world.add_child(hud.lock)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layer.add_child(hud)
	hud.set_process(false)
	await frames(4)
	var cockpit=hud._cockpit_3d
	for id in [SuitProfile.Id.MESSER_M01,SuitProfile.Id.MESSER_CMD,SuitProfile.Id.MESSER_F01]:
		p.profile=SuitProfile.by_id(id);cockpit._process(0.1)
		check(cockpit.visible and cockpit.messer.visible,"Messer variant enabled "+str(id))
		check(cockpit.cockpit_family(id)==4,"Dedicated common family "+str(id))
	check(cockpit.view.render_target_update_mode==SubViewport.UPDATE_DISABLED,"No redundant 3D instrument rendering")
	check(not cockpit.panorama.visible and not cockpit.texture_rect.visible,"Legacy shells hidden")
	if not DisplayServer.get_name()=="headless":
		var out:=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(out)
		for pose in ["forward","look_down","bank"]:
			cam.rotation=Vector3(deg_to_rad(-28) if pose=="look_down" else deg_to_rad(12) if pose=="bank" else 0,0,deg_to_rad(25) if pose=="bank" else 0)
			cockpit._process(0.1);hud.queue_redraw();await frames(6);await RenderingServer.frame_post_draw
			check(get_viewport().get_texture().get_image().save_png(out.path_join(pose+".png"))==OK,"Rendered "+pose)
	Settings.first_person=false;cockpit._process(0.1);check(not cockpit.visible and not cockpit.messer.visible,"Third person remains unchanged")
	Settings.first_person=true;Game.phase=Game.Phase.WIN;cockpit._process(0.1);check(not cockpit.visible,"No instruments over settlement")
	Game.phase=Game.Phase.FIGHT
	p.profile=SuitProfile.xi();cockpit._process(0.1);check(cockpit.visible and not cockpit.messer.visible and cockpit.last_family==0,"Switch back to Xi cockpit")
	hud.queue_free();world.queue_free();Settings.end_isolated();await frames(2)
	print("MESSER_COCKPIT_DONE ",checks," PASS / 0 FAIL");get_tree().quit()


