extends RefCounted
const INK=Color(1,.30,.075)
const DIM=Color(.32,.10,.035)
const BG=Color(.017,.009,.006)
static func text(s,at:Vector2,value:String,font_size:int=11)->void:s._text(at,value,font_size,INK)
static func draw(s)->void:
	if s.modules.is_empty() or not is_instance_valid(s.player):return
	s.material=null;s._state_image.hide();s._state_overlay.hide()
	var p=s.player
	for key in s.modules:
		var r:Rect2=s.modules[key]
		if key in ["dial_l","dial_r","lower_l","lower_r"]:
			s.draw_circle(r.get_center(),minf(r.size.x,r.size.y)*.49,BG)
		else:
			s.draw_rect(r,BG);s.draw_rect(r.grow(-3),DIM,false,1)
	var radar:Rect2=s.modules.center;var c:=radar.get_center();var radius:=radar.size.y*.40
	for ratio in [.30,.60,1.0]:s.draw_arc(c,radius*ratio,0,TAU,64,INK if ratio==1 else DIM,1,true)
	for i in 36:
		var dir:=Vector2.from_angle(float(i)*TAU/36)
		s.draw_line(c+dir*radius*.92,c+dir*radius,INK,1,true)
	s.draw_line(c-Vector2(radius,0),c+Vector2(radius,0),DIM,1,true);s.draw_line(c-Vector2(0,radius),c+Vector2(0,radius),DIM,1,true)
	var forward:Vector3=p.forward();var right:=forward.cross(Vector3.UP).normalized()
	for target in p.contacts():
		var offset:Vector3=target.global_position-p.global_position
		var point:=Vector2(offset.dot(right),-offset.dot(forward))/6500.0
		s.draw_circle(c+point.limit_length(1)*radius,2,INK)
	s.draw_circle(c,2,INK)
	# Additional CRT graduations follow the real compass heading, not an animation loop.
	var bearing:float=atan2(-forward.x,-forward.z)
	for i in 16:
		var angle:float=float(i)*TAU/16+bearing
		var dir:=Vector2.from_angle(angle)
		s.draw_line(c+dir*radius*1.08,c+dir*radius*(1.18 if i%4==0 else 1.12),INK,1,true)
	var nose:=Vector2(sin(bearing),-cos(bearing))
	s.draw_line(c+nose*radius*.70,c+nose*radius*.91,INK,1.5,true)
	text(s,Vector2(radar.position.x+8,radar.end.y-9),"6.5 KM / %03d"%int(fposmod(rad_to_deg(bearing),360)),9)
	text(s,radar.position+Vector2(8,13),"PSYCOMMU / RADAR",9)
	# All needles use real flight data. No scripted/random indicator motion.
	for key in ["dial_l","dial_r"]:
		var r:Rect2=s.modules[key];var at:=r.get_center();var rad:=minf(r.size.x,r.size.y)*.43
		var value:float=0;var label:=""
		match key:
			"dial_l":value=clampf(p.airspeed_kmh()/8000,0,1);label="SPD"
			"dial_r":value=clampf(p.global_position.y/18000,0,1);label="ALT"
			"lower_l":value=p.jet_ratio();label="PROP"
			"lower_r":value=p.hp_ratio();label="FRAME"
		s.draw_arc(at,rad,0,TAU,48,INK,1.0,true);s.draw_arc(at,rad*.68,0,TAU,48,DIM,1,true)
		for i in 12:
			var a:float=float(i)*TAU/12;var dir:=Vector2.from_angle(a)
			s.draw_line(at+dir*rad*.82,at+dir*rad,INK,1,true)
		var angle:=lerpf(-PI*.75,PI*.75,value)
		s.draw_line(at,at+Vector2(sin(angle),-cos(angle))*rad*.72,INK,1.4,true)
		text(s,at+Vector2(-rad*.45,rad*.53),label,8)
		var numeric:="%04d"%int(p.airspeed_kmh()) if key=="dial_l" else "%05d"%int(p.global_position.y)
		text(s,at+Vector2(-rad*.39,rad*.22),numeric,10)
	# The lower round CRTs carry the live systems and weapon readouts formerly on the two flat screens.
	var scale:float=clampf(s.size.y/1080.0,.7,1.5)
	for key in ["lower_l","lower_r"]:
		var r:Rect2=s.modules[key];var at:=r.get_center();var rad:=minf(r.size.x,r.size.y)*.44
		s.draw_arc(at,rad,0,TAU,64,INK,1.2,true)
		s.draw_arc(at,rad*.88,0,TAU,64,DIM,1,true)
		if key=="lower_l":
			text(s,at+Vector2(-rad*.43,-rad*.42),"FRAME",maxi(10,int(10*scale)))
			text(s,at+Vector2(-rad*.57,-rad*.08),"AP %04d"%int(p.hp),maxi(11,int(12*scale)))
			text(s,at+Vector2(-rad*.57,rad*.25),"PROP %03d%%"%int(p.jet_ratio()*100),maxi(10,int(10*scale)))
			var fuel:=Rect2(at+Vector2(-rad*.55,rad*.43),Vector2(rad*1.10,3*scale))
			s.draw_rect(fuel,DIM);s.draw_rect(Rect2(fuel.position,Vector2(fuel.size.x*p.jet_ratio(),fuel.size.y)),INK)
		else:
			var rows:Array=p.thunderbolt_systems.hud_rows() if p.thunderbolt_systems!=null else []
			var secondary:String="双火箭" if p.thunderbolt_systems!=null and p.thunderbolt_systems.secondary_missiles else "刺雷"
			var names:Array=["光束炮",secondary,"双重炮","机枪","干扰弹","热能斧"]
			var line:float=rad*.22
			text(s,at+Vector2(-rad*.34,-rad*.66),"ARM",maxi(9,int(9*scale)))
			for i in rows.size():
				var yy:float=at.y-rad*.40+i*line
				text(s,Vector2(at.x-rad*.63,yy),names[i] if i<names.size() else str(rows[i].name),maxi(8,int(8*scale)))
				s._text_right(Vector2(at.x+rad*.63,yy),str(rows[i].value).replace("READY","RDY").replace("装填 ","R ").replace("X切换","X"),maxi(8,int(8*scale)),INK)
