extends "res://scripts/ui/cockpit_surface.gd"
## Dedicated GP03 CRT skin; other suits retain their original display renderer.
const CRT := Color(0.38,0.68,1.0)
const CRT_DIM := Color(0.13,0.27,0.44)
const CRT_BG := Color(0.012,0.023,0.045)

var _gp03_screen_ink: ShaderMaterial

func _draw() -> void:
	if is_instance_valid(player) and player.profile.id==SuitProfile.Id.NU_GUNDAM:
		preload("res://scripts/ui/nu_cockpit_surface.gd").draw(self)
		return
	if not is_instance_valid(player) or player.profile.id not in [SuitProfile.Id.GP03D,SuitProfile.Id.SAZABI]:
		material = null
		super._draw()
		return
	if modules.is_empty(): return
	if _gp03_screen_ink == null:
		_gp03_screen_ink = ShaderMaterial.new()
		_gp03_screen_ink.shader = preload("res://shaders/gp03_hud_ink.gdshader")
	material = _gp03_screen_ink
	_state_image.hide()
	_state_overlay.hide()
	for key in ["center","left","right"]:
		var r: Rect2 = modules[key]
		draw_rect(r,CRT_BG)
		draw_rect(r.grow(-5),CRT_DIM,false,1.0)
		# Subtle scan lines stay static to avoid flicker.
		for y in range(int(r.position.y+8),int(r.end.y-7),4):
			draw_line(Vector2(r.position.x+7,y),Vector2(r.end.x-7,y),Color(CRT,0.035),0.6)
	var r: Rect2 = modules.center
	_text(r.position+Vector2(16,23),instrument_title(player.profile.id),11,CRT)
	draw_line(r.position+Vector2(15,32),Vector2(r.end.x-15,r.position.y+32),CRT_DIM,1.0)
	var mode: int = Settings.effective_dash_screen()
	if mode == Settings.DASH_SCREEN_SILHOUETTE:
		_state_image.texture = STATE_TEXTURES[8 if player.profile.id == SuitProfile.Id.SAZABI else 6]
		var area := Rect2(r.position+r.size*Vector2(0.10,0.17),r.size*Vector2(0.80,0.64))
		var factor := minf(area.size.x/_state_image.texture.get_width(),area.size.y/_state_image.texture.get_height())
		_state_image.size = _state_image.texture.get_size()*factor
		_state_image.position = area.get_center()-_state_image.size/2
		_state_material.set_shader_parameter("mask_caption",false)
		_state_material.set_shader_parameter("ink",CRT if player.hp_ratio()>0.5 else silhouette_color(player.hp_ratio(),player.has_ifield()))
		_state_image.show()
	elif mode == Settings.DASH_SCREEN_CONTOUR:
		_draw_screen_contour(r.position+r.size*Vector2(0.5,0.49),r.size.y*0.27)
	else:
		var k := minf(0.72,(r.size.y-74.0)/(RADAR_RADIUS*2.0))
		var origin := r.position+r.size*Vector2(0.5,0.49)
		draw_set_transform(origin-radar_center(size)*k,0,Vector2(k,k))
		_draw_radar()
		draw_set_transform(Vector2.ZERO)
	var status := "FRAME NORMAL" if player.hp_ratio()>0.5 else "FRAME DAMAGE"
	var color := CRT if player.hp_ratio()>0.5 else WARN
	_text(r.position+Vector2(16,r.size.y-21),status,10,color)
	_text_right(Vector2(r.end.x-16,r.end.y-21),"%03d%%" % int(player.hp_ratio()*100),12,color)
	_gp03_dial(modules.left,false)
	_gp03_dial(modules.right,true)

static func instrument_title(suit_id: int) -> String:
	return "MSN-04  /  SAZABI" if suit_id == SuitProfile.Id.SAZABI else "RX-78GP03  /  ORCHIS"

func _gp03_dial(r: Rect2, roll: bool) -> void:
	var angle := float(attitude_readout(player.global_transform.basis).horizon_roll_deg) if roll else dash_dial_angle(clampf(player.fm.throttle,0,1))
	var origin := r.position+r.size*Vector2(0.5,0.46)
	var radius := minf(r.size.x,r.size.y)*0.25
	_text(r.position+Vector2(14,22),"ATTITUDE" if roll else "THRUST",10,CRT)
	var value := "%+.1f°" % angle if roll else "%d%%" % int(clampf(player.fm.throttle,0,1)*100)
	_text_right(Vector2(r.end.x-14,r.position.y+22),value,12,CRT)
	draw_arc(origin,radius,0,TAU,64,CRT_DIM,1.0,true)
	var ticks := ([] if player.profile.id == SuitProfile.Id.SAZABI else dash_roll_ticks()) if roll else ([] if player.profile.id == SuitProfile.Id.SAZABI else dash_thrust_ticks())
	for tick: float in ticks:
		var a := deg_to_rad(tick)
		var direction := Vector2(sin(a),-cos(a))
		draw_line(origin+direction*(radius-5),origin+direction*radius,CRT,1.0,true)
	var direction := Vector2(sin(deg_to_rad(angle)),-cos(deg_to_rad(angle)))
	draw_line(origin,origin+direction*(radius-9),CRT,1.5,true)
	draw_circle(origin,2,CRT)
	var text := "LEVEL" if roll else ("BOOST" if player.fm.boosting else "CRUISE")
	if roll and absf(angle)>=0.5: text = "BANK R" if angle>0 else "BANK L"
	_text_center(Vector2(origin.x,r.position.y+r.size.y*0.80),text,10,CRT)
	var ratio := clampf(absf(angle)/DASH_ROLL_RANGE,0,1) if roll else clampf(player.fm.throttle,0,1)
	for i in 10:
		var cell := Rect2(r.position+Vector2(16+i*(r.size.x-32)/10,r.size.y-20),Vector2((r.size.x-32)/10-3,4))
		draw_rect(cell,CRT if i<ceili(ratio*10) else CRT_DIM)
