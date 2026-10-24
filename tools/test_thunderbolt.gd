extends Node3D
var count:=0
func check(value:bool,label:String)->void:
	assert(value,label);count+=1
func _ready()->void:
	Game.phase=Game.Phase.FIGHT
	var bodies=[]
	for id in [SuitProfile.Id.FULL_ARMOR_TB,SuitProfile.Id.PSYCHO_ZAKU_TB]:
		var body=FlightBody.new();body.profile=SuitProfile.by_id(id);body.team=bodies.size();body.projectile_container=self
		add_child(body);body.set_physics_process(false);bodies.append(body)
		check(body.thunderbolt_systems!=null,"systems installed")
		check(body.flare_mag_size()==90,"90 decoys")
		check(body.profile.is_ace(),"ace")
		check(body.profile.speed_scale==SuitProfile.zorin_soul().speed_scale,"speed inherited")
		check(Net.valid_room_choice(id,0,LanPlan.Form.ACE_DUEL),"LAN ace allowed")
		check(not Net.valid_room_choice(id,0,LanPlan.Form.SQUAD),"squad excluded")
	var fa=bodies[0];var z=bodies[1];z.position=Vector3(0,0,-500)
	check(fa.raise_shield(),"shield starts");check(fa.shield_timer==6,"shield 6 seconds")
	fa._tick_shield(6);check(fa.shield_cooldown==10 and not fa.shield_up,"cooldown starts after 6 seconds")
	check(not z.raise_shield(),"psycho cannot shield")
	var s=z.thunderbolt_systems
	check(s.primary(),"beam fires");check(s.primary_ammo==2,"3 round magazine")
	check(z.active_cannon.duration==2.5 and z.active_cannon.dps==120,"2.5 second 120 DPS")
	s.primary_cd=0;s.primary();s.primary_cd=0;s.primary()
	check(s.primary_reload==9 and s.primary_ammo==0,"automatic 9 second reload")
	s.step(9);check(s.primary_ammo==3,"reload completes")
	check(s.secondary(),"sting fires");check(s.secondary_cd==11.5,"sting CD")
	s.secondary_missiles=true;check(s.secondary(),"independent bazooka");check(s.bazooka_ammo==58,"dual consumes 2")
	check(s.support(),"heavy rockets");check(s.support_cd==12,"heavy CD")
	fa.apply_thunder_status("sting");check(fa.weapons_locked() and fa.thunder_lock_left==7,"sting locks 7 seconds")
	check(is_equal_approx(fa.combat_buffs.movement_rate(fa),.1),"sting 90% slow")
	fa._tick_weapons(7);check(not fa.weapons_locked(),"weapons restored")
	var before=z.position;z.apply_thunder_status("ram",Vector3.RIGHT)
	check(is_equal_approx(z.position.distance_to(before),3000),"3km knockback")
	check(is_equal_approx(z.combat_buffs.movement_rate(z),.05),"ram 95% slow")
	var visual=z.model_root.find_child("Thunderbolt",true,false)
	var nozzle_before={}
	for index in [13,14,23,33]:
		var nozzle=visual.model.find_child("Part_%03d"%index,true,false)
		check(nozzle.get_parent().name=="Backpack","nozzle belongs to backpack")
		nozzle_before[index]=nozzle.global_transform
	z.saber_state=FlightBody.SaberState.CHARGE;z._saber_visual_clock=.3
	for frame in 30:visual._process(1.0/60)
	for index in nozzle_before:
		var nozzle=visual.model.find_child("Part_%03d"%index,true,false)
		check(nozzle.global_transform.is_equal_approx(nozzle_before[index]),"arm motion cannot move backpack nozzle")
	check(visual.joints.ArmL.rotation.length()>.5,"arm really moved during nozzle test")
	z.saber_state=FlightBody.SaberState.IDLE;z.thunderbolt_systems.shot_pose=2.5
	for frame in 30:visual._process(1.0/60)
	for index in nozzle_before:
		var nozzle=visual.model.find_child("Part_%03d"%index,true,false)
		check(nozzle.global_transform.is_equal_approx(nozzle_before[index]),"right arm shooting cannot move backpack nozzle")
	check(visual.joints.ArmR.rotation.x>1.0,"right arm really raised during nozzle test")
	check(not fa.profile.saber_double and fa.profile.saber_blade_rear==0,"Full Armor uses a single blade")
	fa._show_blade()
	check(fa._blade.get_child_count()==2,"one blade half with outer and inner glow only")
	print("THUNDERBOLT PASS ",count)
	for audio in get_tree().root.find_children("*","AudioStreamPlayer3D",true,false):audio.stop();audio.stream=null
	for audio in get_tree().root.find_children("*","AudioStreamPlayer",true,false):audio.stop();audio.stream=null

	for child in get_children():child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()
