extends "res://scripts/cinematics/sortie_director.gd"
## Packaged video intro. Reuses the cinematic pause/skip/restore contract.
var video:VideoStreamPlayer
var saved_bgm:Dictionary={}
var initialized:=false
static func video_path(id:int)->String:
	return "res://assets/video/sazabi_sortie.ogv" if id==SuitProfile.Id.SAZABI else "res://assets/video/nu_sortie.ogv"
func _ready()->void:
	saved_units_mode=main.units_root.process_mode;saved_projectile_mode=main.projectiles.process_mode
	saved_camera_mode=main.chase.process_mode;saved_hud_mode=main.hud.process_mode
	saved_hud_visible=main.hud.visible;saved_controls=main.player.controls_enabled
	main.units_root.process_mode=Node.PROCESS_MODE_DISABLED;main.projectiles.process_mode=Node.PROCESS_MODE_DISABLED
	main.chase.process_mode=Node.PROCESS_MODE_DISABLED;main.hud.process_mode=Node.PROCESS_MODE_DISABLED;main.hud.hide();main.player.controls_enabled=false
	for sound in main.units_root.find_children("*","AudioStreamPlayer3D",true,false):
		paused_audio[sound]=sound.stream_paused;sound.stream_paused=true
	for sound in Audio._bgm_players:
		saved_bgm[sound]=sound.stream_paused;sound.stream_paused=true
	layer=CanvasLayer.new();layer.layer=70;add_child(layer)
	var background:=ColorRect.new();background.color=Color.BLACK;background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layer.add_child(background)
	var frame:=AspectRatioContainer.new();frame.ratio=16.0/9.0;frame.stretch_mode=AspectRatioContainer.STRETCH_FIT
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layer.add_child(frame)
	video=VideoStreamPlayer.new();video.expand=true;video.bus=Settings.BUS_SFX;frame.add_child(video)
	var stream:=VideoStreamTheora.new();stream.file=video_path(profile.id);video.stream=stream
	var hint:=Label.new();hint.text=InputSetup.hint("空格 / Esc 跳过","A / B 跳过");layer.add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT);hint.position=Vector2(-240,-40)
	video.finished.connect(finish);initialized=true;video.play()
	if not FileAccess.file_exists(stream.file):call_deferred("finish")
func pose(_delta:float)->void:pass
func step(delta:float)->void:
	if cleaned:return
	time+=maxf(delta,0)
	# Watchdog also handles an unreadable/truncated stream without blocking play.
	if time>(13.0 if profile.id==SuitProfile.Id.SAZABI else 10.0):finish()
func cleanup(_handoff:=false)->void:
	if cleaned or not initialized:return
	if is_instance_valid(video):video.stop()
	for sound in saved_bgm:
		if is_instance_valid(sound):sound.stream_paused=saved_bgm[sound]
	saved_bgm.clear()
	super.cleanup(false)
func _exit_tree()->void:
	if initialized and not cleaned and is_instance_valid(main):cleanup(false)
