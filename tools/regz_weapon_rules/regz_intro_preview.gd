extends Node
func _ready() -> void:
	Settings.begin_isolated();Game.phase=Game.Phase.MENU
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);DisplayServer.window_set_size(Vector2i(1600,900))
	var menu:=MainMenu.new();add_child(menu)
	menu.stage=MainMenu.Stage.SUIT
	menu.suit_index=menu.active_suit_list().find(SuitProfile.Id.REGZ_CUSTOM)
	assert(menu.suit_index>=0)
	menu.queue_redraw()
	for frame in 12:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("C:/Users/MSIPC/Documents/Codex/2026-10-08/yeu/outputs/regz_weapon_rules/introduction.png")
	Settings.end_isolated();print("REGZ INTRO PREVIEW COMPLETE");get_tree().quit()
