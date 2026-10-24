extends "res://scripts/ui/gp03_cockpit_surface.gd"
var _zorin_line_material:ShaderMaterial
const ZORIN_STATE:=preload("res://assets/models/zorin/state.res")
## Xi instrument geometry, Zorin-specific flight and weapon readouts.
func _draw()->void:
	if is_instance_valid(player) and player.profile.id==SuitProfile.Id.PSYCHO_ZAKU_TB:
		preload("res://scripts/ui/psycho_zaku_surface.gd").draw(self)
		return
	if is_instance_valid(player) and player.profile.id==SuitProfile.Id.FULL_ARMOR_TB:
		preload("res://scripts/ui/full_armor_cockpit_surface.gd").draw(self)
		return
	if not is_instance_valid(player) or player.profile.id!=SuitProfile.Id.ZORIN_SOUL:
		if is_instance_valid(_state_image):_state_image.material=_state_material
		super._draw();return
	if modules.is_empty():return
	material=null;_state_image.hide();_state_overlay.hide()
	var ink:=Color(.52,.69,1);var dim:=Color(.16,.22,.4)
	for key in ["center","left","right"]:
		var r:Rect2=modules[key]
		draw_rect(r,Color(.013,.02,.045));draw_rect(r.grow(-5),dim,false,1)
	var center:Rect2=modules.center
	_text(center.position+Vector2(14,22),"RX-110 / ZORIN SOUL",11,ink)
	var mode:int=Settings.effective_dash_screen()
	if mode==Settings.DASH_SCREEN_SILHOUETTE:
		if _zorin_line_material==null:
			_zorin_line_material=ShaderMaterial.new()
			_zorin_line_material.shader=preload("res://shaders/zorin_state_ink.gdshader")
		_state_image.material=_zorin_line_material
		_state_image.texture=ZORIN_STATE
		var area:=Rect2(center.position+Vector2(16,35),center.size-Vector2(32,70))
		var factor:=minf(area.size.x/ZORIN_STATE.get_width(),area.size.y/ZORIN_STATE.get_height())
		_state_image.size=ZORIN_STATE.get_size()*factor
		_state_image.position=area.get_center()-_state_image.size/2
		_zorin_line_material.set_shader_parameter("ink",ink if player.hp_ratio()>.5 else silhouette_color(player.hp_ratio(),player.has_ifield()))
		_state_image.show()
	elif mode==Settings.DASH_SCREEN_CONTOUR:
		_draw_screen_contour(center.position+center.size*Vector2(.5,.49),center.size.y*.27)
	else:
		var k:=minf(.72,(center.size.y-74)/(RADAR_RADIUS*2))
		var origin:=center.position+center.size*Vector2(.5,.49)
		draw_set_transform(origin-radar_center(size)*k,0,Vector2(k,k));_draw_radar();draw_set_transform(Vector2.ZERO)
	_text(center.position+Vector2(14,center.size.y-20),"MINOVSKY FLIGHT / HIT RECHARGE",10,ink)
	var sys=player.nu_systems
	if not is_instance_valid(sys):return
	for key in ["left","right"]:
		var r:Rect2=modules[key];var left:bool=key=="left"
		_text(r.position+Vector2(14,22),"WING FUNNELS" if left else "MINOVSKY BARRIER",10,ink)
		var c:=r.get_center()-Vector2(0,8);var radius:=minf(r.size.x,r.size.y)*.28
		draw_arc(c,radius,PI*.75,PI*2.25,64,dim,3,true)
		var ratio:float=sys.energy/200.0 if left else player.ifield_ratio()
		draw_arc(c,radius,PI*.75,PI*.75+PI*1.5*maxf(.001,ratio),64,ink,3,true)
		_text_center(c+Vector2(0,5),"%03d"%sys.energy if left else "%d/3"%sys.charges(),24,ink)
		if left:
			_text_center(Vector2(c.x,r.end.y-36),sys.mode_name(),11,ink)
			_text_center(Vector2(c.x,r.end.y-18),"F / ALT",10,dim)
		else:
			for i in 2:
				var y:float=r.end.y-34+i*18
				var progress:float=sys.cooldown_progress() if i==0 else sys.charge_progress()
				var label:String="冷却 %.1fs"%sys.barrier_cd if i==0 else ("充能 · 等待冷却" if sys.barrier_cd>0 and sys.charge_remaining()>0 else "充能 %.1fs"%sys.charge_remaining())
				_text(Vector2(r.position.x+14,y-4),label,9,ink)
				var track:=Rect2(r.position.x+14,y,r.size.x-28,2)
				draw_rect(track,dim);track.size.x*=clampf(progress,0,1);draw_rect(track,ink)
