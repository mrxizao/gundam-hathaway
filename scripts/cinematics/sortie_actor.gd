extends FlightBody
## Visual-only FlightBody: never registers as a player, target or combat unit.
var sortie_morph := -1.0
func _tick_cruise_morph(delta:float)->void:
	if sortie_morph>=0.0:
		cruise_morph=sortie_morph
		super._tick_cruise_morph(0.0)
	else:
		super._tick_cruise_morph(delta)
func _ready()->void:
	is_player=true;collision_layer=0;collision_mask=0
	form_index=maxi(profile.form,0)
	_apply_profile_to_flight()
	max_hp=profile.hull_hp;hp=max_hp
	_build_visual();_build_attachments();_collect_morph_nodes()
	set_process(false);set_physics_process(false)
	if is_instance_valid(_detect_timer):_detect_timer.stop()
	for light in _nav_lights:light["node"].hide()
	if model_anim!=null and model_anim.ready:
		model_anim.player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
func animate_sortie(delta:float,power:float,cruise:bool,morph:float=-1.0)->void:
	sortie_morph=morph
	fm.throttle=power;fm.boosting=cruise and power>.3;fm.hovering=false
	penelope_cruise_enabled=cruise
	_tick_effects(delta)
	_update_engine_audio(delta)
	if model_anim!=null and model_anim.ready:
		if profile.id==SuitProfile.Id.XI and morph>0.0 and morph<1.0:
			model_anim.player.play("form_on")
			model_anim.player.seek(model_anim.player.get_animation("form_on").length*morph,true)
			model_anim.player.advance(0.0)
		else:
			if cruise:model_anim.hold_cruise(0.0)
			model_anim.player.advance(delta)

	if morph>=0.0:_weld_form_bones()
