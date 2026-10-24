extends Control
signal completed
const Dialogue = preload("res://scripts/data/pod_strike_dialogue.gd")
var video:VideoStreamPlayer
var started := false
var done := false
func _ready() -> void:
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 var black:=ColorRect.new();black.color=Color.BLACK;black.mouse_filter=Control.MOUSE_FILTER_IGNORE
 add_child(black);black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var holder:=AspectRatioContainer.new();holder.ratio=16.0/9.0;holder.stretch_mode=AspectRatioContainer.STRETCH_FIT
 holder.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(holder);holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 video=VideoStreamPlayer.new();video.expand=true;video.mouse_filter=Control.MOUSE_FILTER_IGNORE
 var stream:=VideoStreamTheora.new();stream.file=Dialogue.VIDEO
 video.stream=stream;video.bus=Settings.BUS_SFX;holder.add_child(video)
 video.finished.connect(_finished)
 hide()
func begin() -> bool:
 if started:return not done
 started=true
 if not FileAccess.file_exists(Dialogue.VIDEO):
  push_error("M04 insert video missing: "+Dialogue.VIDEO)
  _finished()
  return false
 show();video.play()
 return true
func _finished() -> void:
 if done:return
 done=true;video.stop();hide();completed.emit()
func clock() -> float:
 return video.stream_position if is_instance_valid(video) else 0.0
func set_paused(value:bool) -> void:
 if is_instance_valid(video):video.paused=value
