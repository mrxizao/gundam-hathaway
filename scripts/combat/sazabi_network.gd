extends RefCounted
## Remote visuals use zero damage. Funnel HP belongs to the owning peer.
static func receive(scene,shooter:FlightBody,kind:String,origin:Vector3,direction:Vector3)->void:
	if kind.begins_with("sazabi_damage:"):
		var parts:=kind.split(":")
		if parts.size()!=4:return
		var owner_body=scene.player if parts[1]=="player" else Net.squad_bodies.get(parts[1])
		if not is_instance_valid(owner_body) or owner_body.sazabi_systems==null:return
		var s=owner_body.sazabi_systems
		if s.visual_only:return
		for drone in s.drones:
			if is_instance_valid(drone) and not drone.is_queued_for_deletion() and drone.slot==int(parts[2]):drone.take_damage(float(parts[3]),shooter)
		return
	if kind=="sazabi_stun:player":
		var victim=scene.player
		if is_instance_valid(victim) and victim.alive and not victim.in_transform() and not victim.shield_up and not victim.is_invulnerable() and (not is_instance_valid(victim.nu_systems) or not victim.nu_systems.barrier_active()):
			victim.melee_guard.impact_left=maxf(victim.melee_guard.impact_left,6.5)
			victim.melee_guard.slow_left=maxf(victim.melee_guard.slow_left,6.5)
			victim._stagger_timer=maxf(victim._stagger_timer,6.5)
		return
	if shooter.sazabi_systems==null:return
	var s=shooter.sazabi_systems
	# Only the remote player's proxy accepts presentation events from its owner.
	if not s.visual_only:return
	if kind=="sazabi_fin":
		var beam=preload("res://scripts/combat/funnel_beam.gd")
		beam.pulse(scene.projectile_container(),shooter,origin,direction,0.0,Color(.55,1,.4),.75,beam.remote_emitter(shooter,origin),true)
		Audio.play_3d("beam_rifle",origin,-9.0)
	elif kind=="sazabi_pellet":
		var shot:=Projectile.beam(scene.projectile_container(),origin,direction,shooter,0.0,Color(.55,1,.4),0.0,.65,14000.0)
		shot.set_beam_visual_width(Projectile.SAZABI_PELLET_VISUAL_WIDTH);shot.visual_only=true
		Audio.play_3d("beam_rifle",origin,-6.0)
	elif kind=="sazabi_launch":
		s.target=scene.player;s.launch()
	elif kind=="sazabi_recall":s.recall()
	elif kind.begins_with("sazabi_mode_"):
		var next_mode:=int(kind.trim_prefix("sazabi_mode_"))
		if next_mode in [0,1] and next_mode!=s.mode:s.toggle_mode()
	elif kind.begins_with("sazabi_lost_"):
		var index:=int(kind.trim_prefix("sazabi_lost_"))
		if index<0 or index>=6:return
		s.funnel_destroyed(index)
		for drone in s.drones:
			if is_instance_valid(drone) and drone.slot==index:drone.destroyed=true;drone.queue_free()
	elif kind.begins_with("sazabi_slot_"):
		var slot:=kind.trim_prefix("sazabi_slot_")
		if slot in ["rifle","sniper","saber","cannon"]:s.ai_slot=slot
	elif kind=="sazabi_axe_swing":s.axe_swing=true
	elif kind=="sazabi_belly":
		shooter.active_cannon=BeamCannon.launch(scene.projectile_container(),shooter,shooter.cannon_muzzles(),null,0.0,shooter.profile.cannon_duration,shooter.profile.cannon_color(),shooter.profile.beam_cannon_radius,1.0,0.0,false,true)
	elif kind=="sazabi_sniper":
		var offsets:Array[Vector3]=[s.motion.muzzle_local()]
		shooter.active_cannon=BeamCannon.launch(scene.projectile_container(),shooter,offsets,null,0.0,1.5,Color(.55,1,.4),5,.4)
	elif kind=="sazabi_throw":
		s.motion.throw_age=0.0
		var axe:=preload("res://scripts/combat/sazabi_axe.gd").new()
		axe.shooter=shooter;axe.direction=direction.normalized();axe.visual_only=true
		axe.model=preload("res://scripts/flight/sazabi_motion.gd").make_blade(true)
		axe.model.scale=Vector3.ONE*shooter.profile.target_height/shooter.profile.model_native_height
		scene.projectile_container().add_child(axe);axe.global_position=origin
