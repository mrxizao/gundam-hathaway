extends "res://scripts/cinematics/sortie_director.gd"
## Reference-directed MA insert: all ribbons and beams are visual-only geometry.
const Sequence:=preload("res://scripts/data/neue_entry_script.gd")
var built:=false
var last_shot:=-1
var music:AudioStreamPlayer
var saved_bgm_pauses:Dictionary={}
var overlay_material:ShaderMaterial
var trail:MultiMeshInstance3D
var beams:MultiMeshInstance3D
var beam_core:MultiMeshInstance3D
var eye_local:=Vector3.ZERO
var head_local:=Vector3.ZERO
var melee_display:Node3D
func _create_stage()->Node3D:return preload("res://scripts/cinematics/neue_entry_stage.gd").new()
func _ready()->void:
 super._ready()
 origin=Vector3.ZERO;actor.flight_pitch_deg=0.0;actor.model_pivot.rotation_degrees.x=0.0
 head_local=actor.rig_anchor("head")
 eye_local=head_local+Vector3(-.5,-1.0,-1.2)
 viewport.transparent_bg=true
 var nebula:=ColorRect.new();nebula.mouse_filter=Control.MOUSE_FILTER_IGNORE;nebula.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var nebula_material:=ShaderMaterial.new();nebula_material.shader=preload("res://shaders/neue_entry_nebula.gdshader");nebula.material=nebula_material
 layer.add_child(nebula);layer.move_child(nebula,0)
 title.text="AMX-002 / NEUE ZIEL"
 camera.far=22000
 for child in actor.model_root.get_children():
  if child.get_script()==preload("res://scripts/flight/distant_model_lod.gd"):child.set_process(false)
 for mesh:MeshInstance3D in actor.model_root.find_children("*","MeshInstance3D",true,false):
  if mesh.name=="DistantRealModel":mesh.hide()
  else:
   mesh.visibility_range_end=0.0
   for surface in mesh.mesh.get_surface_count():
    var original:=mesh.get_active_material(surface) as StandardMaterial3D
    if original!=null:
     var mat:=original.duplicate() as StandardMaterial3D
     mat.albedo_color*=Color(.75,1.0,.56)
     mesh.set_surface_override_material(surface,mat)
 var overlay:=ColorRect.new();overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE;overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 overlay_material=ShaderMaterial.new();overlay_material.shader=preload("res://shaders/neue_entry_overlay.gdshader")
 overlay.material=overlay_material;layer.add_child(overlay);layer.move_child(overlay,2)
 trail=rods("CurvedEngineTrail",48,2.5,Color(.4,.68,1.0))
 beams=rods("CinematicBeamSalvo",20,1.1,Color(.4,1.0,.04))
 beam_core=rods("CinematicBeamCore",20,.24,Color(.95,1.0,.72))
 for player in Audio._bgm_players:saved_bgm_pauses[player]=player.stream_paused;player.stream_paused=true
 music=AudioStreamPlayer.new();music.name="MenOfDestiny";music.bus=Settings.BUS_BGM;music.process_mode=Node.PROCESS_MODE_PAUSABLE
 music.stream=load(SoundBank.bgm_path("men_of_destiny"));add_child(music);music.play()
 # Reuse the combat melee's articulated auxiliary arms and six blade mounts.
 # Drive only its pose; no attack state, target, hit checks or ammo use.
 melee_display=preload("res://scripts/combat/neue_aux_sabers.gd").new()
 actor.add_child(melee_display);melee_display.set_process(false);melee_display.hide()
 melee_display.steel.albedo_color=Color(.23,.32,.23)
 built=true;pose(0.0)
func rods(title_text:String,count:int,radius:float,color:Color)->MultiMeshInstance3D:
 var result:=MultiMeshInstance3D.new();result.name=title_text
 var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.use_colors=true
 var cylinder:=CylinderMesh.new();cylinder.height=1.0;cylinder.top_radius=radius;cylinder.bottom_radius=radius;cylinder.radial_segments=6
 var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.albedo_color=color;mat.emission_enabled=true;mat.emission=color;mat.emission_energy_multiplier=3.0;mat.vertex_color_use_as_albedo=true
 cylinder.material=mat;multi.mesh=cylinder;multi.instance_count=count;result.multimesh=multi;scene.add_child(result);return result
static func rod_transform(a:Vector3,b:Vector3)->Transform3D:
 var direction:Vector3=b-a
 if direction.length_squared()<.000001:return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*.000001),a)
 var length:=direction.length()
 # Cylinder long axis is LOCAL Y. Scale before rotation, never world-space Y.
 var basis:=Basis(Quaternion(Vector3.UP,direction/length))*Basis.from_scale(Vector3(1,length,1))
 return Transform3D(basis,(a+b)*.5)
func rod(target_multi:MultiMesh,index:int,a:Vector3,b:Vector3,color:Color)->void:
 target_multi.set_instance_transform(index,rod_transform(a,b));target_multi.set_instance_color(index,color)
func pose(delta:float)->void:
 if not built:return
 var sample:=Sequence.sample(time);var shot:int=sample.shot
 actor.position=sample.position;actor.rotation=sample.rotation
 actor.set_model_visible(shot!=6)
 actor.fm.velocity=Vector3(0,0,-actor.profile.player_top_speed())
 actor.animate_sortie(delta,1.0,true)
 var deploy:=smoothstep(6.6,7.35,time)*(1.0-smoothstep(9.6,10.2,time))
 actor._saber_visual_clock=preload("res://scripts/flight/saber_motion.gd").style(actor.profile).windup*deploy
 melee_display.clock=.18*deploy
 melee_display.visible=time>=6.6 and time<10.2
 melee_display._update_limbs()
 for blade:Node3D in melee_display.claw_blades:blade.scale*=deploy
 camera.position=sample.camera
 var target:Vector3=sample.target
 if shot==2:
  camera.position=actor.to_global(head_local+sample.camera);target=actor.to_global(head_local+sample.target)
 camera.look_at(target,Vector3.UP);camera.fov=sample.fov
 trail.visible=time<5.5 or (time>=11.6 and time<12.9)
 for i in 48:
  var a:Vector3=Sequence.position_at(maxf(0,time-float(i)*.035))
  var b:Vector3=Sequence.position_at(maxf(0,time-float(i+1)*.035))
  rod(trail.multimesh,i,a,b,Color(1,1,1)*maxf(.05,1.0-float(i)/48.0))
 beams.visible=time>=10.5 and time<12.9
 beam_core.visible=beams.visible
 for i in 20:
  var port:int=i%5
  var from:Vector3=actor._muzzle_local[port] if port<4 else actor.rig_anchor("muzzle_L")
  var direction:Vector3=(actor.global_basis*Vector3((port-2)*.25,sin(port*1.2)*.15,-1)).normalized()
  var start:Vector3=actor.to_global(from)+direction*fmod(maxf(time-10.5,0)*1900+float(i/5)*200,800)
  rod(beams.multimesh,i,start,start+direction*260,Color.WHITE)
  rod(beam_core.multimesh,i,start,start+direction*260,Color.WHITE)
 overlay_material.set_shader_parameter("sequence_time",time)
 overlay_material.set_shader_parameter("aspect",Vector2(float(viewport.size.x)/maxf(viewport.size.y,1),1))
 overlay_material.set_shader_parameter("eye_center",camera.unproject_position(actor.to_global(eye_local))/Vector2(viewport.size))
 for key in ["smoke","streaks","beam_rush"]:overlay_material.set_shader_parameter(key,sample[key])
 overlay_material.set_shader_parameter("eye_flash",sample.eye)
 if actor._engine!=null:actor._engine.volume_db=lerpf(-30,-7,smoothstep(3.6,5.5,time))
 music.volume_db=-1.0-18.0*smoothstep(Sequence.DURATION-.3,Sequence.DURATION,time)
 status.text=Sequence.TITLES[shot];fade.color.a=maxf(1.0-time/.3,smoothstep(Sequence.DURATION-.35,Sequence.DURATION,time));last_shot=shot
func cleanup(_handoff:=false)->void:
 if cleaned:return
 if is_instance_valid(music):music.stop();music.stream=null
 for player in saved_bgm_pauses:
  if is_instance_valid(player):player.stream_paused=saved_bgm_pauses[player]
 saved_bgm_pauses.clear()
 if is_instance_valid(stage):
  for world:WorldEnvironment in stage.find_children("*","WorldEnvironment",true,false):world.environment.sky=null
 super.cleanup(false)
