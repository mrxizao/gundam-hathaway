extends "res://scripts/cinematics/sortie_director.gd"
## GP03D 2.0 cinematic. Visual effects never create live weapon projectiles.
const Sequence:=preload("res://scripts/data/gp03d_entry_script.gd")
var overlay:ColorRect
var overlay_material:ShaderMaterial
var built:=false
var last_shot:=-1
var eye_marker:Marker3D
# Surface point ray-picked from the user-marked eye on GP03D 2.0.
const EYE_LOCAL:=Vector3(.040667,3.340507,-4.521590)
var music:AudioStreamPlayer
var saved_bgm_pauses:Dictionary={}
func _create_stage()->Node3D:
 return preload("res://scripts/cinematics/gp03d_entry_stage.gd").new()
func _ready()->void:
 super._ready()
 origin=Vector3.ZERO
 actor.flight_pitch_deg=0.0;actor.model_pivot.rotation_degrees.x=0.0
 var eye_mesh:=actor.model_root.find_child("tripo_part_48_001",true,false) as MeshInstance3D
 eye_marker=Marker3D.new();eye_marker.name="EyeGlowAnchor"
 if eye_mesh!=null:
  eye_mesh.add_child(eye_marker)
  eye_marker.position=eye_mesh.to_local(actor.to_global(EYE_LOCAL))
 else:
  actor.add_child(eye_marker);eye_marker.position=EYE_LOCAL
 viewport.transparent_bg=true
 var nebula:=ColorRect.new();nebula.name="CinematicNebula";nebula.mouse_filter=Control.MOUSE_FILTER_IGNORE
 nebula.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var nebula_material:=ShaderMaterial.new();nebula_material.shader=preload("res://shaders/neue_entry_nebula.gdshader")
 nebula.material=nebula_material;layer.add_child(nebula);layer.move_child(nebula,0)
 camera.far=18000
 title.text="RX-78GP03D / DENDROBIUM"
 # Keep detailed geometry for telephoto and core close-ups on every preset.
 for child in actor.model_root.get_children():
  if child.get_script()==preload("res://scripts/flight/distant_model_lod.gd"):child.set_process(false)
 for mesh:MeshInstance3D in actor.model_root.find_children("*","MeshInstance3D",true,false):
  if mesh.name=="DistantRealModel":mesh.hide()
  else:mesh.visibility_range_end=0.0
 overlay=ColorRect.new();overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
 overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 overlay_material=ShaderMaterial.new();overlay_material.shader=preload("res://shaders/gp03d_entry_overlay.gdshader")
 overlay.material=overlay_material;layer.add_child(overlay);layer.move_child(overlay,2)
 # Pause the engine at distance; it swells as the machine reaches the camera.
 for player in Audio._bgm_players:
  saved_bgm_pauses[player]=player.stream_paused
  player.stream_paused=true
 music=AudioStreamPlayer.new();music.name="MenOfDestiny";music.bus=Settings.BUS_BGM
 music.process_mode=Node.PROCESS_MODE_PAUSABLE
 music.stream=load(SoundBank.bgm_path("men_of_destiny"))
 add_child(music);music.play()
 built=true;pose(0.0)
func pose(delta:float)->void:
 if not built:return
 var sample:=Sequence.sample(time)
 actor.set_model_visible(sample.shot!=0)
 actor.position=sample.position;actor.rotation=Vector3(0,0,sample.roll)
 actor.fm.velocity=Vector3(0,0,-actor.profile.player_top_speed())
 actor.animate_sortie(delta,sample.power,true)
 camera.position=sample.camera
 camera.look_at(sample.target,Vector3.UP);camera.fov=sample.fov
 var shot:int=sample.shot
 # Actual rear plumes are visible in the nozzle shot and the final reveal.
 for item:Dictionary in actor._plume_fx:
  for key in ["fx","glow","boost","ab","dash"]:
   var effect:Node3D=item.get(key) as Node3D
   if is_instance_valid(effect):effect.visible=shot!=0
 if actor._engine!=null:
  actor._engine.stream_paused=time<3.6
  actor._engine.volume_db=lerpf(-26.0,-6.0,smoothstep(3.6,4.6,time))
 overlay_material.set_shader_parameter("sequence_time",time)
 overlay_material.set_shader_parameter("aspect",Vector2(float(viewport.size.x)/maxf(viewport.size.y,1.0),1.0))
 overlay_material.set_shader_parameter("spark_center",sample.spark)
 overlay_material.set_shader_parameter("approach",smoothstep(.2,.8,time)*(1.0-smoothstep(4.08,4.15,time)))
 overlay_material.set_shader_parameter("streaks",sample.streaks)
 overlay_material.set_shader_parameter("line_open",sample.line)
 overlay_material.set_shader_parameter("detail_focus",smoothstep(5.3,6.5,sample.motion_time)*(1.0-smoothstep(7.35,8.9,sample.motion_time)))
 overlay_material.set_shader_parameter("rush",sample.rush)
 var trail:=PackedVector2Array()
 for i in 25:trail.append(Sequence.meteor(maxf(0.0,time-float(i)*.026)))
 overlay_material.set_shader_parameter("trail_points",trail)
 overlay_material.set_shader_parameter("trail_alpha",smoothstep(.25,.6,time)*(1.0-smoothstep(3.15,3.55,time)))
 overlay_material.set_shader_parameter("eye_flash",sample.eye)
 if is_instance_valid(music):music.volume_db=-1.0-18.0*smoothstep(Sequence.DURATION-.3,Sequence.DURATION,time)
 var eye:Vector2=camera.unproject_position(eye_marker.global_position)/Vector2(viewport.size)
 overlay_material.set_shader_parameter("eye_center",eye)
 status.text=Sequence.TITLES[shot]
 fade.color.a=maxf(1.0-time/.3,smoothstep(Sequence.DURATION-.35,Sequence.DURATION,time))
 last_shot=shot
func cleanup(_handoff:=false)->void:
 if cleaned:return
 if is_instance_valid(music):music.stop();music.stream=null
 for player in saved_bgm_pauses:
  if is_instance_valid(player):player.stream_paused=saved_bgm_pauses[player]
 saved_bgm_pauses.clear()
 # Preserve the real map spawn and the existing battle-music handoff.
 super.cleanup(false)
