extends RefCounted
const CRT:=Color(.38,.68,1)
const DIM:=Color(.13,.27,.44)
static func state_index(player)->int:
	return (1 if player.nu_systems.deployed() else 0)+(2 if player.nu_systems.equipment_cd>0 else 0)
static func draw(s)->void:
	if s.modules.is_empty():return
	if s._gp03_screen_ink==null:
		s._gp03_screen_ink=ShaderMaterial.new();s._gp03_screen_ink.shader=preload("res://shaders/gp03_hud_ink.gdshader")
	s.material=s._gp03_screen_ink;s._state_image.hide();s._state_overlay.hide()
	for key in ["center","left","right"]:
		var r:Rect2=s.modules[key];s.draw_rect(r,Color(.012,.023,.045));s.draw_rect(r.grow(-5),DIM,false,1)
	var r:Rect2=s.modules.center
	s._text(r.position+Vector2(16,23),"RX-93  /  ν GUNDAM",11,CRT)
	var mode:int=Settings.effective_dash_screen()
	if mode==Settings.DASH_SCREEN_SILHOUETTE:
		s._state_image.texture=load("res://assets/models/nu_gundam/state_%d.res"%state_index(s.player))
		var area:=Rect2(r.position+r.size*Vector2(.1,.16),r.size*Vector2(.8,.67))
		var texture:Texture2D=s._state_image.texture
		var factor:=minf(area.size.x/texture.get_width(),area.size.y/texture.get_height())
		s._state_image.size=texture.get_size()*factor;s._state_image.position=area.get_center()-s._state_image.size/2
		s._state_material.set_shader_parameter("mask_caption",false);s._state_material.set_shader_parameter("ink",CRT);s._state_image.show()
	elif mode==Settings.DASH_SCREEN_CONTOUR:
		s._draw_screen_contour(r.position+r.size*Vector2(.5,.49),r.size.y*.27)
	else:
		var c:=r.position+r.size*Vector2(.5,.49);var radius:=r.size.y*.29
		for ratio in [.33,.66,1.0]:s.draw_arc(c,radius*ratio,0,TAU,64,DIM,1,true)
		var forward:Vector3=s.player.forward();var right:=forward.cross(Vector3.UP).normalized()
		for contact in s.player.contacts():
			var delta:Vector3=contact.global_position-s.player.global_position
			var point:=Vector2(delta.dot(right),-delta.dot(forward))/6500.0
			s.draw_circle(c+point.limit_length(1)*radius,2.2,CRT)
		s.draw_circle(c,2.5,CRT)
	s._text(r.position+Vector2(16,r.size.y-21),"FIN %s"%s.player.nu_systems.mode_name(),10,CRT)
	s._text_right(Vector2(r.end.x-16,r.end.y-21),s.player.nu_systems.status_text(),12,CRT)
	for side in ["left","right"]:
		var panel:Rect2=s.modules[side];var roll:bool=side=="right"
		var value:float=rad_to_deg(s.player.rotation.z) if roll else clampf(s.player.fm.throttle,0,1)*100
		s._text(panel.position+Vector2(14,22),"ATTITUDE" if roll else "THRUST",10,CRT)
		s._text_right(Vector2(panel.end.x-14,panel.position.y+22),"%+.1f°"%value if roll else "%d%%"%value,12,CRT)
		var c:=panel.position+panel.size*Vector2(.5,.46);var radius:=minf(panel.size.x,panel.size.y)*.25
		s.draw_arc(c,radius,0,TAU,64,DIM,1,true)
		var angle:float=deg_to_rad(value if roll else lerpf(-100,100,value/100))
		s.draw_line(c,c+Vector2(sin(angle),-cos(angle))*(radius-9),CRT,1.5,true)
		s._text_center(Vector2(c.x,panel.position.y+panel.size.y*.8),"LEVEL" if roll else ("BOOST" if s.player.fm.boosting else "CRUISE"),10,CRT)
		var bar:=Rect2(panel.position+Vector2(16,panel.size.y-20),Vector2(panel.size.x-32,4))
		s.draw_rect(bar,DIM);s.draw_rect(Rect2(bar.position,Vector2(bar.size.x*(clampf(absf(value)/60,0,1) if roll else value/100),4)),CRT)
