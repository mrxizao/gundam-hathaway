extends CanvasLayer
## Above both cockpit and third-person HUD; cannot intercept input or cover menus.
var unit
var white: ColorRect
func _ready() -> void:
	name = "FlashbangWhiteout"
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	white = ColorRect.new()
	white.color = Color.WHITE
	white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(white)
	white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	refresh()

func _process(_delta: float) -> void:
	refresh()

func refresh() -> void:
	visible = is_instance_valid(unit) and unit.alive and unit.is_player and unit.flash_blind_left > 0 and Game.phase == Game.Phase.FIGHT and not get_tree().paused
