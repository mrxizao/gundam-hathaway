extends "res://scripts/cinematics/gp03d_entry_stage.gd"
func _ready()->void:
 super._ready()
 # Nebula is a canvas backdrop: no per-cinematic radiance cubemap allocation.
 var world:WorldEnvironment=find_children("*","WorldEnvironment",true,false)[0]
 world.environment.background_mode=Environment.BG_CLEAR_COLOR
