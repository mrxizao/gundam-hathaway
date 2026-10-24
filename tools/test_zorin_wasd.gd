extends Node3D
var good:=0
var bad:=0
func check(ok:bool,label:String)->void:
	if ok:good+=1;print("PASS ",label)
	else:bad+=1;push_error("FAIL "+label)
func clear_keys()->void:
	for action in ["pitch_nose_down","pitch_nose_up","roll_left","roll_right"]:Input.action_release(action)
func _ready()->void:
	await get_tree().process_frame
	Settings.begin_isolated();Game.reset();Game.active_map=MapDef.leo();Game.phase=Game.Phase.FIGHT
	FlightBody.use_placeholder=DisplayServer.get_name()=="headless"
	var p:=PlayerController.new();p.profile=SuitProfile.zorin_soul();p.is_player=true;p.team=0;add_child(p);p.set_physics_process(false);p.set_process(false);p.nu_systems.set_physics_process(false);p.position=Vector3(0,5000,0);p.controls_enabled=true
	var rig=p.model_root.find_child("ZorinSoul",true,false)
	if rig!=null:rig.set_process(false)
	var cam:=Camera3D.new();cam.near=2;cam.far=10000;cam.fov=45;add_child(cam);cam.position=p.position+Vector3(23,6,-46);cam.look_at(p.position);cam.current=true
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-35,0);light.light_energy=1.4;add_child(light)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.04,.055,.08);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color(.75,.82,1);env.environment.ambient_light_energy=.65;add_child(env)
	var layer:=CanvasLayer.new();add_child(layer);var caption:=Label.new();caption.position=Vector2(36,26);caption.add_theme_font_size_override("font_size",30);layer.add_child(caption)
	var inputs:Dictionary={"W":["pitch_nose_down",Vector3.FORWARD],"S":["pitch_nose_up",Vector3.BACK],"A":["roll_left",Vector3.LEFT],"D":["roll_right",Vector3.RIGHT]}
	var sampler=load("res://scripts/flight/zorin_rig.gd")
	var out:=OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else ""
	if out!="":DirAccess.make_dir_recursive_absolute(out)
	for assisted in [true,false]:
		p.assist_on=assisted
		for key in inputs:
			clear_keys();Input.action_press(inputs[key][0]);p._think(1.0/60)
			check(p.nu_systems.pilot_intent.distance_to(inputs[key][1])<.001,"Actual input "+key+" assist="+str(assisted))
			var pose:Dictionary=sampler.sample_pose(p)
			check(pose.flight.length()>10,"Visible held-key posture "+key+" assist="+str(assisted))
			var intent:Vector3=p.nu_systems.pilot_intent;p.nu_systems.pilot_intent=Vector3.ZERO
			var neutral:Dictionary=sampler.sample_pose(p);p.nu_systems.pilot_intent=intent
			var four_limbs:=true
			for bone in ["arm1","arm-1","fore1","fore-1","leg1","leg-1","shin1","shin-1"]:
				if (pose[bone]-neutral[bone]).length()<5.0:four_limbs=false
			check(four_limbs,"All four limbs respond "+key+" assist="+str(assisted))
			var remembered:Vector3=pose.flight
			p._think(1.0/60);check(sampler.sample_pose(p).flight.distance_to(remembered)<.001,"Held key remains active "+key)
			caption.text=key+"  /  "+str({"W":"前倾 / 收臂收腿","S":"制动 / 屈臂屈膝","A":"左移 / 左右肢体配合","D":"右移 / 左右肢体配合"}[key])
			if rig!=null:
				for i in 12:rig.step(1.0/60)
				var sk:Skeleton3D=rig.skeleton;var preserved:=true
				for i in sk.get_bone_count():
					if sk.get_bone_pose_position(i).distance_to(sk.get_bone_rest(i).origin)>.000001:preserved=false
				check(preserved,"Skeleton lengths preserved "+key)
				if assisted:
					for i in 5:await get_tree().process_frame
					await RenderingServer.frame_post_draw;get_viewport().get_texture().get_image().save_png(out.path_join(key+".png"))
			clear_keys();p._think(1.0/60)
			check(p.nu_systems.pilot_intent.is_zero_approx() and sampler.sample_pose(p).flight.is_zero_approx(),"Release returns to neutral "+key)
			if rig!=null:
				for i in 30:rig.step(1.0/60)
				check(rig.flight.quaternion.angle_to(Quaternion.IDENTITY)<.01,"Smooth return completes "+key)
	clear_keys();Input.action_press("roll_right");p._think(1.0/60)
	FlightBody.use_placeholder=true
	var remote:=NetProxyBody.new();remote.profile=SuitProfile.zorin_soul();add_child(remote);remote.set_physics_process(false);remote.nu_systems.set_physics_process(false);remote.nu_systems.apply_snapshot(p.nu_systems.snapshot())
	check(remote.nu_systems.pilot_intent==p.nu_systems.pilot_intent,"Network retains raw pilot intent")
	clear_keys();p.controls_enabled=false;p._think(1.0/60);check(p.nu_systems.pilot_intent.is_zero_approx(),"Disabled controls clear pose")
	print("ZORIN_WASD_DONE ",good," PASS / ",bad," FAIL")
	Settings.end_isolated();get_tree().quit(1 if bad else 0)
