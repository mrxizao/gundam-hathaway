extends "res://scripts/cinematics/sortie_director.gd"
## M09 only: attack, subjective replay, blackout, emergency climb and rear hold.
const Sequence:=preload("res://scripts/data/m09_launch_script.gd")
const Blast:=preload("res://scripts/cinematics/m09_launch_blast.gd")
class Pilot extends PlayerController:
	func _ready()->void:pass
var home:=Vector3.ZERO
var cockpit:FlightHUD
var proxy:PlayerController
var hangar_blast:Node3D
var base_blasts:Array[Node3D]=[]
var impact_flash:ColorRect
var radio_panel:Control
var built:=false
var audio_time:=-.001
var played:Dictionary={}
func _ready()->void:
	super._ready()
	home=origin
	# Telephoto shots must retain the animated mesh even on the low-end preset.
	for child in actor.model_root.get_children():
		if child.get_script()==preload("res://scripts/flight/distant_model_lod.gd"):child.set_process(false)
	for mesh:MeshInstance3D in actor.model_root.find_children("*","MeshInstance3D",true,false):
		if mesh.name=="DistantRealModel":mesh.hide()
		else:mesh.visibility_range_end=0.0

	stage.tractor.hide();stage.cradle.hide();stage.sample(1.4)
	title.hide()
	for side in [-1,1]:
		stage.box(stage,"ServiceRestraint",home+Vector3(side*19,2,4),Vector3(3,20,3),Color(.3,.32,.34))
		stage.box(stage,"RestraintArm",home+Vector3(side*14,11,4),Vector3(12,2,3),Color(.63,.48,.17))
		stage.box(stage,"MaintenanceCart",Vector3(side*38,9,-12),Vector3(8,6,11),Color(.3,.34,.37))
	var fill:=OmniLight3D.new();fill.position=home+Vector3(-15,40,-25);fill.omni_range=160;fill.light_energy=2.0;fill.light_color=Color(.77,.83,1);scene.add_child(fill)
	camera.free()
	var eye:=ChaseCamera.new();eye.near=.15;eye.far=40000;eye.set_physics_process(false)
	scene.add_child(eye);eye.set_physics_process(false);eye.set_process(false);camera=eye;eye.make_current()
	proxy=Pilot.new();proxy.profile=profile;proxy.controls_enabled=false;scene.add_child(proxy)
	proxy.max_hp=profile.hull_hp;proxy.hp=proxy.max_hp;proxy.ifield_max=profile.ifield_hp;proxy.ifield_hp=proxy.ifield_max
	proxy.display_name=profile.display_name;proxy.rifle_mag=profile.rifle_magazine;proxy.set_physics_process(false)
	cockpit=FlightHUD.new();cockpit.player=proxy;cockpit.camera=eye;cockpit.cinematic_first_person=true;layer.add_child(cockpit);cockpit.set_process(false)
	impact_flash=ColorRect.new();impact_flash.mouse_filter=Control.MOUSE_FILTER_IGNORE;impact_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layer.add_child(impact_flash)
	radio_panel=preload("res://scripts/ui/m09_radio_panel.gd").new();layer.add_child(radio_panel)
	fade.z_index=4095
	hangar_blast=Blast.new();hangar_blast.radius=27.0;scene.add_child(hangar_blast);hangar_blast.position=home+Vector3(14,9,-27)
	for i in 12:
		var blast:=Blast.new();blast.radius=36.0+float(i%4)*13.0;scene.add_child(blast)
		blast.position=Vector3(-650+float((i*7)%5)*260,12,-350-float((i*5)%6)*230)
		base_blasts.append(blast)
	actor.penelope_cruise_enabled=false;actor.cruise_morph=0.0
	if actor.model_anim!=null and actor.model_anim.ready:actor.model_anim.hold_rest(0.0,true);actor.model_anim.player.advance(0.0)
	built=true
	pose(0.0)
func pose(delta:float)->void:
	if not built:
		super.pose(delta);return
	var sample:Dictionary=Sequence.sample(time,home)
	actor.position=sample.position;actor.rotation=Vector3(sample.pitch,0,sample.roll)
	actor.cruise_morph=sample.morph;actor._tick_cruise_morph(0)
	var before:Vector3=Sequence.sample(maxf(time-.01,0),home).position
	var after:Vector3=Sequence.sample(minf(time+.01,Sequence.TOTAL),home).position
	actor.fm.velocity=(after-before)/.02;actor.fm.speed=actor.fm.velocity.length()
	actor.animate_sortie(delta,sample.power,time>=Sequence.IGNITION,sample.morph)
	if actor._engine!=null:actor._engine.stream_paused=time<Sequence.IGNITION
	var fp:bool=Sequence.cockpit(time)
	actor.set_model_visible(not fp)
	for item:Dictionary in actor._plume_fx:
		for key in ["fx","glow","boost","ab","dash"]:
			var effect:Node3D=item.get(key) as Node3D
			if is_instance_valid(effect):effect.visible=not fp and time>=Sequence.IGNITION
	cockpit.visible=fp
	proxy.global_transform=actor.global_transform;proxy.fm.velocity=actor.fm.velocity;proxy.fm.speed=actor.fm.speed
	var age:float=Sequence.impact_age(time)
	hangar_blast.sample(age if time<Sequence.IGNITION else -1.0)
	for i in base_blasts.size():
		var elapsed:float=time-Sequence.IGNITION+float(i%4)*.67-float(i%3)*.23
		base_blasts[i].sample(fmod(elapsed,4.3) if elapsed>=0 and time>=Sequence.IGNITION else -1.0)
	var target:Vector3=actor.position+Vector3.UP*profile.target_height*.16
	if fp:
		camera.position=actor.global_transform*actor.rig_anchor("head")+Vector3(0,0,-4)
		camera.look_at(camera.position+Vector3(0,-.04,-1)*100,Vector3.UP);camera.fov=78
		if age>=0:
			var shock:float=exp(-age*2.5)
			camera.position+=Vector3(sin(age*41),sin(age*33),0)*shock*1.4
			camera.rotation.z+=sin(age*24)*shock*.055
	elif time<Sequence.IGNITION:
		camera.position=home+Vector3(-34,15,-56);camera.look_at(target,Vector3.UP);camera.fov=54
	elif time<Sequence.ASCENT_END:
		# A ground-level telephoto pan tracks the entire climb, ending overhead.
		camera.position=Vector3(-300,18,-1550)
		camera.look_at(Vector3(-400,90,-1500).lerp(target,smoothstep(Sequence.IGNITION,Sequence.IGNITION+1.2,time)),Vector3.UP)
		var focus_fov:float=clampf(rad_to_deg(2*atan(profile.target_height*2.4/maxf(camera.position.distance_to(target),1))),1.5,60)
		camera.fov=lerpf(74,focus_fov,smoothstep(Sequence.IGNITION+.5,Sequence.IGNITION+2.7,time))
	else:
		var orbit:float=smoothstep(Sequence.ASCENT_END,Sequence.ORBIT_END,time)
		var angle:float=lerpf(PI*.5,0,orbit)
		camera.position=target+Vector3(sin(angle)*profile.target_height*3.4,profile.target_height*.5,cos(angle)*profile.target_height*3.4)
		camera.look_at(target,Vector3.UP);camera.fov=62
	impact_flash.color=Color(1,.68,.35,.55*exp(-maxf(age,0)*15) if age>=0 and time<Sequence.IGNITION else 0)
	fade.color=Color(0,0,0,Sequence.blackout(time))
	radio_panel.rows=preload("res://scripts/data/m09_dialogue.gd").intro_lines(time);radio_panel.cockpit_view=fp;radio_panel.queue_redraw()
	status.text=Sequence.stage_name(time);cockpit.queue_redraw()
	if delta>0:_audio_events()
func _audio_events()->void:
	for cue in [["hit",Sequence.IMPACT,"boom_l",-6.0],["replay",Sequence.REPLAY_IMPACT,"boom_l",-8.0],["ignition",Sequence.IGNITION,"startup",-2.0]]:
		if time>=float(cue[1]) and audio_time<float(cue[1]) and not played.has(cue[0]):
			Audio.play_self(cue[2],cue[3]);played[cue[0]]=true
	if time>=Sequence.IGNITION:
		var beat:=int((time-Sequence.IGNITION)/.85)
		if not played.has("base"+str(beat)):
			played["base"+str(beat)]=true;Audio.play_self("boom_m",-16.0)
	audio_time=time
func step(delta:float)->void:
	if cleaned:return
	time=minf(time+maxf(delta,0),Sequence.TOTAL);pose(delta)
	if time>=Sequence.TOTAL:finish()
func finish()->void:
	if cleaned:return
	time=Sequence.TOTAL;pose(0)
	cleanup(true);finished.emit()
func cleanup(handoff:=false)->void:
	if cleaned:return
	if handoff and built and is_instance_valid(main.player):
		var unit:PlayerController=main.player
		unit.global_transform=Transform3D(actor.global_basis,actor.position+Sequence.BASE_WORLD)
		unit.penelope_cruise_enabled=true;unit.cruise_morph=1;unit._tick_cruise_morph(1)
		unit.fm.hovering=false;unit.fm.boosting=true;unit.fm.throttle=.78
		unit.fm.speed=unit.profile.player_top_speed()*.55;unit.fm.velocity=-unit.global_basis.z*unit.fm.speed;unit.velocity=unit.fm.velocity
		unit.set_model_visible(true)
		main._strike_view_restore=Settings.first_person if Settings.first_person else null;Settings.first_person=false
		main.chase.set_target(unit);main.chase.first_person=false;main.chase._fpv_blend=0
		main.chase.global_transform=Transform3D(camera.global_basis,camera.position+Sequence.BASE_WORLD);main.chase.fov=camera.fov
	super.cleanup(false)
func _exit_tree()->void:
	cleanup(false)
