extends RefCounted
const BLUE := Color(.25,.48,1.0)
const CYAN := Color(.14,.86,1.0)
const DIM := Color(.12,.25,.48)
const STATES := [preload("res://assets/ui/cockpit/full_armor_state_front.res"),preload("res://assets/ui/cockpit/full_armor_state_oblique.res")]
static func draw(s) -> void:
	if s.modules.is_empty(): return
	s.material = null
	s._state_image.hide()
	s._state_overlay.hide()
	var p = s.player
	for key in s.modules:
		var r: Rect2 = s.modules[key]
		s.draw_rect(r,Color(.012,.026,.065))
		s.draw_rect(r.grow(-3),BLUE,false,1.2)
		s.draw_line(r.position+Vector2(6,5),r.position+Vector2(minf(26,r.size.x*.2),5),CYAN,2)
		for n in 3:
			s.draw_rect(Rect2(r.end.x-8-n*5,r.end.y-7,3,2),BLUE)
		for y in range(int(r.position.y+6),int(r.end.y-3),4):
			s.draw_line(Vector2(r.position.x+4,y),Vector2(r.end.x-4,y),Color(BLUE,.045),.6)
	var left: Rect2 = s.modules.left
	var right: Rect2 = s.modules.right
	var center: Rect2 = s.modules.center
	frame_monitor(s,left,p,false)
	frame_monitor(s,right,p,true)
	# Actual radar uses contacts and lock state, clipped into a circular CRT.
	var radius: float = minf(center.size.x,center.size.y)*.38
	var at := center.get_center()
	s.draw_circle(at,radius,Color(.015,.035,.12,.8))
	s.draw_arc(at,radius,0,TAU,64,BLUE,1.5,true)
	for tick in 32:
		var direction:=Vector2.from_angle(tick*TAU/32)
		s.draw_line(at+direction*(radius-2),at+direction*(radius-(6 if tick%4==0 else 3)),CYAN if tick%4==0 else DIM,.8,true)
	s.draw_line(at-Vector2(radius,0),at+Vector2(radius,0),DIM,.7)
	s.draw_line(at-Vector2(0,radius),at+Vector2(0,radius),DIM,.7)
	s.draw_arc(at,radius*.65,0,TAU,48,DIM,1,true)
	var factor: float = radius/s.RADAR_RADIUS
	s.draw_set_transform(at-s.radar_center(s.size)*factor,0,Vector2.ONE*factor)
	s._draw_radar()
	s.draw_set_transform(Vector2.ZERO)
	text(s,Vector2(center.position.x+4,center.position.y-5),"TACTICAL",9,CYAN)
	for key in ["upper_left","upper_right"]:
		var r: Rect2 = s.modules[key]
		var first: bool = key=="upper_left"
		var source = s.get_meta("full_armor_source",null)
		if not first and is_instance_valid(source) and source.magnifier_active() and source._mag_vp!=null:
			s.draw_texture_rect(source._mag_vp.get_texture(),Rect2(r.position+Vector2(5,18),r.size-Vector2(10,23)),false)
			text(s,r.position+Vector2(6,13),"TARGET / %.1f KM" % (source.lock.range_to_target()/1000.0),9,CYAN)
			continue
		text(s,r.position+Vector2(6,14),"PWR / BOOST" if first else "SYS / ASSIST",9,BLUE)
		var value: String = "%03d%%" % int(p.jet_ratio()*100) if first else ("ON" if p.assist_on else "OFF")
		text(s,r.position+Vector2(7,31),value,12,CYAN)
		bar(s,Rect2(r.position+Vector2(7,r.size.y-8),Vector2(r.size.x-14,2)),p.jet_ratio() if first else p.hp_ratio())
	var weapons: Rect2=s.modules.right_aux
	text(s,weapons.position+Vector2(6,14),"ARM / CONTROL",8,CYAN)
	var rows: Array=p.thunderbolt_systems.hud_rows() if p.thunderbolt_systems!=null else []
	var spacing: float=(weapons.size.y-31)/maxi(rows.size(),1)
	for i in rows.size():
		var y: float=weapons.position.y+31+i*spacing
		var label: String=str(rows[i].name).replace("空格 ","").replace("（再按引爆）","")
		var status: String=str(rows[i].value)
		var ready: bool=not (status.contains("CD") or status.contains("装填") or status.contains("过热"))
		s.draw_rect(Rect2(weapons.position.x+5,y-5,3,3),CYAN if ready else Color(1,.55,.2))
		text(s,Vector2(weapons.position.x+12,y),label,8,BLUE)
		s._text_right(Vector2(weapons.end.x-7,y+11),str(rows[i].value),9,CYAN)
		s.draw_line(Vector2(weapons.position.x+6,y+15),Vector2(weapons.end.x-6,y+15),DIM,.7)
	var inventory: Rect2=s.modules.left_aux
	text(s,inventory.position+Vector2(5,14),"ARMAMENT / 01",8,CYAN)
	var sys=p.thunderbolt_systems
	for i in 3:
		var y: float=inventory.position.y+29+i*(inventory.size.y-38)/3
		text(s,Vector2(inventory.position.x+6,y),["01  TWIN RIFLE","02  BEAM CANNON","03  MISSILE POD"][i],7,BLUE)
		var x: float=inventory.position.x+inventory.size.x*.14
		var w: float=inventory.size.x*.7
		if i==0:
			s.draw_rect(Rect2(x,y+10,w*.49,10),Color(BLUE,.22))
			s.draw_rect(Rect2(x,y+10,w*.49,10),CYAN,false,1.2)
			for barrel in 2:s.draw_rect(Rect2(x+w*.49,y+11+barrel*5,w*.5,2),CYAN,false,1.2)
			s.draw_line(Vector2(x+w*.29,y+20),Vector2(x+w*.24,y+25),CYAN,.8)
		elif i==1:
			var line:=PackedVector2Array([Vector2(x,y+10),Vector2(x+w*.62,y+10),Vector2(x+w*.73,y+13),Vector2(x+w,y+13),Vector2(x+w,y+17),Vector2(x+w*.52,y+17),Vector2(x+w*.42,y+21),Vector2(x,y+21),Vector2(x,y+10)])
			s.draw_polyline(line,BLUE,.8,true)
			s.draw_line(Vector2(x+w*.4,y+21),Vector2(x+w*.32,y+26),CYAN,.7)
		else:
			s.draw_rect(Rect2(x,y+9,w,15),BLUE,false,.7)
			for missile in 5:
				var mx: float=x+(missile+.5)*w/5
				s.draw_circle(Vector2(mx,y+16),w*.066,DIM)
				s.draw_arc(Vector2(mx,y+16),w*.066,0,TAU,10,CYAN,.6,true)
		var ratio: float=1.0
		if sys!=null:
			if i==0:ratio=float(sys.primary_ammo)/18.0 if sys.primary_reload<=0 else 1.0-sys.primary_reload/3.0
			elif i==1:ratio=sys.missile_ratio() if sys.secondary_missiles else 1.0-sys.secondary_cd/6.0
			else:ratio=sys.missile_ratio()
		bar(s,Rect2(x,y+34,w,2),ratio)
		text(s,Vector2(x,y+44),"%03d%% / LINK" % int(clampf(ratio,0,1)*100),6,DIM)

static func frame_monitor(s,r: Rect2,p,starboard: bool) -> void:
	text(s,r.position+Vector2(10,17),"MS / MONITOR 02" if starboard else "FA-78 / MONITOR 01",8,CYAN)
	var readiness: float=clampf(p.shield_timer/6.0 if p.shield_up else 1.0-p.shield_cooldown/10.0,0,1) if starboard else p.hp_ratio()
	var main_value: String=("GUARD / %.1f S" % p.shield_timer if p.shield_up else ("GUARD / READY" if p.shield_cooldown<=0 else "GUARD / %.1f S" % p.shield_cooldown)) if starboard else "AP  %04d" % int(p.hp)
	text(s,r.position+Vector2(10,33),main_value,10 if starboard else 13,CYAN)
	bar(s,Rect2(r.position+Vector2(10,39),Vector2(r.size.x-20,4)),readiness)
	# Static geometry-derived schematics; no extra model viewport during combat.
	var texture: Texture2D=STATES[1 if starboard else 0]
	var area:=Rect2(r.position+Vector2(16,47),r.size-Vector2(32,70))
	var scale: float=minf(area.size.x/texture.get_width(),area.size.y/texture.get_height())
	var extent: Vector2=texture.get_size()*scale
	for gx in range(int(area.position.x),int(area.end.x),12):s.draw_line(Vector2(gx,area.position.y),Vector2(gx,area.end.y),Color(DIM,.16),.5)
	for gy in range(int(area.position.y),int(area.end.y),12):s.draw_line(Vector2(area.position.x,gy),Vector2(area.end.x,gy),Color(DIM,.16),.5)
	s.draw_texture_rect(texture,Rect2(area.get_center()-extent*.5,extent),false,Color(.55,.86,1,1))
	for i in 11:
		var yy: float=area.position.y+area.size.y*i/10
		s.draw_line(Vector2(r.position.x+5,yy),Vector2(r.position.x+(10 if i%5==0 else 8),yy),BLUE,.7)
	for side: float in [-1.0,1.0]:
		var anchor:=area.position+area.size*Vector2(.5+side*.24,.42)
		var elbow:=anchor+Vector2(side*15,-8)
		s.draw_polyline(PackedVector2Array([anchor,elbow,elbow+Vector2(side*11,0)]),CYAN,.65,true)
		s.draw_rect(Rect2(anchor-Vector2(1,1),Vector2(2,2)),BLUE)
		text(s,elbow+Vector2(-8 if side<0 else 1,-3),"L-01" if side<0 else "R-02",6,CYAN)
	text(s,Vector2(r.end.x-33,r.position.y+32),"%03d%%" % int(readiness*100),8,BLUE)
	var origin:=area.get_center()
	var k: float=area.size.y/110.0
	var damage: float = 1.0-p.hp_ratio()
	if damage>.15:
		s.draw_rect(Rect2(origin+Vector2(-14,-23)*k,Vector2(28,22)*k),Color(1,.22,.18,.45*damage))
	text(s,Vector2(r.position.x+10,r.end.y-8),"SHIELD  "+("GUARD" if p.shield_up else "STANDBY"),10,CYAN)

static func text(s, at: Vector2, value: String, fs: int, color: Color) -> void:
	s._text(at,value,fs,color)
static func bar(s, r: Rect2, ratio: float) -> void:
	s.draw_rect(r,DIM)
	s.draw_rect(Rect2(r.position,Vector2(r.size.x*clampf(ratio,0,1),r.size.y)),CYAN)
