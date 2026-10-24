extends Control
## Messer common cockpit. Vector instruments and transparent canopy graduations.
const SUITS := [SuitProfile.Id.MESSER_M01,SuitProfile.Id.MESSER_CMD,SuitProfile.Id.MESSER_F01]
const PINK := Color(0.82,0.39,0.52,0.83)
const GOLD := Color(0.91,0.62,0.32,0.80)
const VIOLET := Color(0.65,0.57,0.88,0.85)
const DIM := Color(0.48,0.43,0.65,0.50)
const SHELL := Color(0.23,0.24,0.21)
const GLASS := Color(0.055,0.045,0.13,0.98)
var hud: Control
var clock:=0.0
var _refresh:=0.0
var preview_pitch:=0.0
var preview_bank:=0.0
var preview_look:=0.0
var font: Font
var _styles: Dictionary = {}
static func supports(id: int) -> bool:
	return id in SUITS
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	font=ThemeDB.fallback_font
func sync(source: Control,enabled: bool,delta: float) -> void:
	hud=source;visible=enabled
	if not enabled: return
	size=source.size
	clock+=delta;_refresh-=delta
	if _refresh<=0:
		_refresh=1.0/30.0;queue_redraw()
func line(a: Vector2,b: Vector2,color: Color,width:=1.0) -> void:
	draw_line(a,b,Color(0.01,0.015,0.025,color.a*0.65),width+1.8,true)
	draw_line(a,b,color,width,true)
func text(at: Vector2,value: String,color:=VIOLET,height:=11) -> void:
	draw_string(font,at+Vector2(1,1),value,HORIZONTAL_ALIGNMENT_LEFT,-1,height,Color(0.01,0.01,0.03,0.85))
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,height,color)
func arc(c: Vector2,r: float,a: float,b: float,color: Color,width:=1.0) -> void:
	draw_arc(c,r,a,b,maxi(12,int(absf(b-a)*r/5)),color,width,true)
func tick(c: Vector2,r: float,angle: float,length: float,color: Color,width:=1.0) -> void:
	var d:=Vector2.from_angle(angle);line(c+d*r,c+d*(r-length),color,width)
func panel(rect: Rect2) -> void:
	draw_style_box(_style(SHELL,Color(0.065,0.07,0.075),9),rect.grow(9))
	draw_style_box(_style(GLASS,Color(0.46,0.42,0.40),3),rect)
func _style(fill: Color,edge: Color,width: int) -> StyleBoxFlat:
	var key:=str(fill)+str(edge)+str(width)
	if _styles.has(key): return _styles[key]
	var box:=StyleBoxFlat.new();box.bg_color=fill
	box.border_color=edge;box.set_border_width_all(width);box.set_corner_radius_all(10)
	_styles[key]=box
	return box
func _draw() -> void:
	if font==null or not is_instance_valid(hud) or not is_instance_valid(hud.player): return
	var p: FlightBody=hud.player
	var k:=minf(size.x/1600.0,size.y/900.0)
	var center:=size*0.5
	var pitch:=preview_pitch
	var bank:=preview_bank
	var look:=preview_look
	var heading:=0.0
	if is_instance_valid(hud.camera):
		var f: Vector3=-hud.camera.global_basis.z
		pitch=asin(clampf(f.y,-1,1))
		heading=atan2(f.x,-f.z)
		bank=atan2(hud.camera.global_basis.x.y,hud.camera.global_basis.y.y)
		var local_f: Vector3=p.global_basis.inverse()*f
		look=asin(clampf(local_f.y,-1,1))
	_canopy(center,k,pitch,bank,heading)
	var c:=Vector2(center.x,size.y*1.005+clampf(look,-0.65,0.25)*size.y*0.65)
	# The lower shell remains rigid; looking down reveals the complete instrument cluster.
	draw_set_transform(c,0,Vector2.ONE*k)
	_main_dial(p)
	for side in [-1,1]:
		draw_set_transform(Vector2(c.x+side*335*k,minf(c.y+22*k,size.y-100*k)),-side*0.38,Vector2.ONE*k)
		_pod(p,side)
		draw_set_transform(Vector2(c.x+side*605*k,minf(c.y+3*k,size.y-88*k)),-side*0.12,Vector2.ONE*k)
		_wing(p,side)
	draw_set_transform(Vector2.ZERO)
	# Sparse flight data belongs at the edge of the canopy, not in the aiming aperture.
	text(Vector2(center.x-330*k,center.y-228*k),"Me02R",Color(PINK,0.55),int(13*k))
	text(Vector2(center.x+225*k,center.y+235*k),"TAC / M   IFF",DIM,int(9*k))
func _canopy(c: Vector2,k: float,pitch: float,bank: float,heading: float) -> void:
	var r:=292.0*k
	# Angular, interrupted arcs from the reference: the central sight stays open.
	for side in [-1,1]:
		var a: float=-0.85 if side==1 else PI-0.85
		arc(c,r,a,a+1.70,Color(PINK,0.20),2*k)
		arc(c,r+8*k,a+0.15,a+1.52,Color(PINK,0.10),1*k)
		for n in 13:
			var t: float=a+n*1.70/12
			tick(c,r,t,(13 if n%3==0 else 6)*k,Color(PINK,0.44),1.4*k)
	for deg in [45,135,225,315]:
		var a:=deg_to_rad(float(deg))
		for offset in [-4,4]:
			tick(c,r+17*k,a+offset*0.001,34*k,GOLD,2.5*k)
	for n in range(-6,7):
		var x:=c.x+n*16*k+fposmod(heading*120*k,16*k)
		line(Vector2(x,c.y-r+6*k),Vector2(x,c.y-r+(23 if n==0 else 13 if n%3==0 else 8)*k),GOLD,1.3*k)
		line(Vector2(x,c.y+r-6*k),Vector2(x,c.y+r-(23 if n==0 else 13 if n%3==0 else 8)*k),Color(GOLD,0.50),1.3*k)
	for side in [-1,1]:
		line(c+Vector2(side*(292-17),-4)*k,c+Vector2(side*(292+20),-4)*k,GOLD,3*k)
		line(c+Vector2(side*(292-17),4)*k,c+Vector2(side*(292+20),4)*k,GOLD,3*k)
	# World horizon and pitch graduation move with the real camera attitude.
	draw_set_transform(c,-bank,Vector2.ONE)
	var shift:=clampf(pitch,-1.2,1.2)*210*k
	for i in range(-3,4):
		var y: float=shift+i*48*k
		if absf(y)>220*k: continue
		var w: float=(110 if i==0 else 50)*k
		line(Vector2(-w,y),Vector2(-12*k,y),Color(VIOLET,0.34),1*k)
		line(Vector2(12*k,y),Vector2(w,y),Color(VIOLET,0.34),1*k)
		line(Vector2(0,y-8*k),Vector2(0,y+8*k),Color(VIOLET,0.22),1*k)
	draw_set_transform(Vector2.ZERO)
	# Right-hand ladder scrolls continuously rather than only changing its number.
	var scroll:=fposmod(pitch*210*k,24*k)
	for n in range(-9,10):
		var y:=c.y+n*24*k+scroll
		line(Vector2(c.x+195*k,y),Vector2(c.x+(180 if n%3==0 else 188)*k,y),Color(PINK,0.46),1.2*k)
	for n in range(-3,4):
		var y: float=c.y+n*62*k
		line(Vector2(c.x+216*k,y),Vector2(c.x+216*k,y+44*k),Color(PINK,0.52),2*k)
		line(Vector2(c.x+221*k,y),Vector2(c.x+221*k,y+44*k),Color(PINK,0.25),1*k)
	text(c+Vector2(-420,8)*k,"SPD",DIM,int(10*k))
	text(c+Vector2(-420,31)*k,"%04d" % int(hud.player.airspeed_kmh()*hud.SPEED_DISPLAY_SCALE),VIOLET,int(21*k))
	text(c+Vector2(350,8)*k,"ALT",DIM,int(10*k))
	text(c+Vector2(350,31)*k,"%05d" % int(hud.player.global_position.y*hud.ALT_DISPLAY_SCALE),VIOLET,int(21*k))
	# Curved sector conductor and small purple joints along the lower canopy.
	for side in [-1,1]:
		for n in 7:
			var x: float=c.x+side*(310+n*68)*k
			var y: float=size.y*(0.84+0.045*float(n)/7.0)
			line(Vector2(x,y),Vector2(x+side*52*k,y+12*k),Color(PINK,0.33),2*k)
			line(Vector2(x,y+5*k),Vector2(x+side*52*k,y+17*k),Color(PINK,0.16),1*k)
		line(Vector2(c.x+side*580*k,32*k),Vector2(c.x+side*72*k,88*k),Color(PINK,0.26),2*k)
	line(Vector2(c.x-72*k,88*k),Vector2(c.x,111*k),Color(PINK,0.33),2*k)
	line(Vector2(c.x,111*k),Vector2(c.x+72*k,88*k),Color(PINK,0.33),2*k)
func _main_dial(p: FlightBody) -> void:
	var c:=Vector2.ZERO
	# Concentric mechanical bezel with an inset violet glass face.
	draw_circle(c,254,Color(0.025,0.03,0.035))
	draw_circle(c,248,SHELL)
	arc(c,245,PI,TAU,Color(0.45,0.44,0.36),5)
	arc(c,236,0,TAU,Color(0.10,0.12,0.12),10)
	draw_circle(c,219,Color(0.025,0.025,0.045))
	draw_circle(c,205,GLASS)
	for i in 6: arc(c,199-i*3,0,TAU,Color(PINK,0.15),2)
	for n in 72:
		var a:=n*TAU/72
		tick(c,204,a,14 if n%6==0 else 6,Color(PINK,0.68),2 if n%6==0 else 1)
		if n%6==0: tick(c,181,a,11,Color(GOLD,0.70),2)
	for n in 18:
		var a:=0.2+n*0.16
		arc(c,212,a,a+0.11,Color(PINK,0.65),9)
	for side in [-1,1]:
		var bolt:=Vector2(side*185,-173)
		draw_circle(bolt,15,SHELL);draw_circle(bolt,8,Color(0.06,0.07,0.065));draw_circle(bolt,4,Color(0.29,0.29,0.24))
	line(Vector2(-20,-241),Vector2(20,-241),Color(0.95,0.09,0.12),4)
	text(Vector2(-64,-156),"MESSER / FLIGHT",VIOLET,12)
	line(Vector2(0,-144),Vector2(0,124),Color(GOLD,0.35),1)
	# Left electronics: genuine health and shield state, segmented like the reference.
	text(Vector2(-147,-113),"AP",DIM,10)
	text(Vector2(-147,-88),"%05d" % int(p.hp),VIOLET,24)
	_segments(Vector2(-147,-71),136,p.hp/maxf(p.max_hp,1.0),PINK)
	text(Vector2(-147,-42),"SHIELD",DIM,10)
	_segments(Vector2(-147,-28),136,p.shield_ratio(),VIOLET)
	text(Vector2(-147,7),"SPD  %04d" % int(p.airspeed_kmh()*hud.SPEED_DISPLAY_SCALE),VIOLET,15)
	text(Vector2(-147,29),"ALT  %05d" % int(p.global_position.y*hud.ALT_DISPLAY_SCALE),VIOLET,15)
	text(Vector2(-147,59),"BOOST",DIM,10)
	_segments(Vector2(-147,70),136,clampf(p.fm.throttle,0,1),GOLD)
	text(Vector2(-142,112),"ASSIST ON" if p.get("assist_on") else "MANUAL",PINK,11)
	text(Vector2(26,-113),"RIFLE",DIM,10)
	text(Vector2(26,-88),"%02d" % p.rifle_mag,PINK,24)
	# Right-hand machine status schematic. No decorative false target contacts.
	for rect in [Rect2(47,-58,42,18),Rect2(38,-32,60,42),Rect2(9,-22,20,45),Rect2(107,-22,20,45),Rect2(42,-6,21,72),Rect2(75,-6,21,72)]:
		draw_rect(rect,Color(VIOLET,0.09));draw_rect(rect,Color(VIOLET,0.40),false,1)
	for n in 9:
		var y: float=-52+n*17
		var x: float=25+float(n%3)*9
		line(Vector2(x,y),Vector2(x-9,y+5),Color(VIOLET,0.22))
		line(Vector2(x-9,y+5),Vector2(x-9,y+14),Color(VIOLET,0.22))
		draw_rect(Rect2(131,-54+n*17,10,7),Color(PINK,0.27),false,1)
	for y in range(-110,105,17):
		line(Vector2(137,y),Vector2(151,y),Color(PINK,0.42),2)
	text(Vector2(20,107),"Me02R / SYSTEM",PINK,12)
	for side in [-1,1]:
		line(Vector2(side*270,180),Vector2(side*230,232),Color(0.08,0.10,0.10),22)
func _segments(at: Vector2,width: float,value: float,color: Color) -> void:
	for i in 16:
		draw_rect(Rect2(at+Vector2(i*width/16,0),Vector2(width/16-2,5)),color if i<float(16)*clampf(value,0,1) else Color(color,0.15))
func _pod(p: FlightBody,side: int) -> void:
	var rect:=Rect2(-58,-103,116,220)
	var outer:=_style(SHELL,Color(0.075,0.08,0.075),9);outer.set_corner_radius_all(55)
	draw_style_box(outer,rect.grow(10))
	var glass:=_style(GLASS,Color(0.47,0.43,0.38),3);glass.set_corner_radius_all(53)
	draw_style_box(glass,rect)
	arc(Vector2(0,-44),47,PI,TAU,Color(PINK,0.55),3)
	arc(Vector2(0,57),47,0,PI,Color(PINK,0.55),3)
	for n in 9:
		line(Vector2(-44,-34+n*12),Vector2(-36,-34+n*12),Color(PINK,0.55),2)
	if side==-1:
		text(Vector2(-26,-41),"RIFLE",VIOLET,10)
		text(Vector2(-24,-14),"%02d" % p.rifle_mag,PINK,25)
		text(Vector2(-26,7),"RELOAD" if p.rifle_reloading else "READY",DIM,9)
		_segments(Vector2(-26,23),56,1.0-p.reload_timer/maxf(p.profile.rifle_reload_time,0.1),VIOLET)
		text(Vector2(-25,55),"SABER",VIOLET,10)
		text(Vector2(-25,75),"ARMED",PINK,10)
	else:
		text(Vector2(-27,-41),"THRUST",VIOLET,10)
		text(Vector2(-25,-13),"%02d" % int(p.fm.throttle*100),PINK,25)
		text(Vector2(-25,10),"BOOST" if p.fm.boosting else "CRUISE",DIM,9)
		_segments(Vector2(-26,24),56,p.fm.throttle,GOLD)
		text(Vector2(-25,57),"FLARE",VIOLET,10)
		text(Vector2(-25,79),"%02d" % p.flare_count,PINK,18)
func _wing(p: FlightBody,side: int) -> void:
	panel(Rect2(-120,-72,240,144))
	if side==-1:
		text(Vector2(-103,-48),"TACTICAL",DIM,10)
		var c:=Vector2(0,10)
		for r in [22,43,61]: arc(c,r,0,TAU,Color(VIOLET,0.20),1)
		line(c+Vector2(-65,0),c+Vector2(65,0),Color(VIOLET,0.20))
		line(c+Vector2(0,-61),c+Vector2(0,61),Color(VIOLET,0.20))
		for body in Game.units:
			if not is_instance_valid(body) or body==p or not body.alive: continue
			var local: Vector3=p.global_basis.inverse()*(body.global_position-p.global_position)
			var v:=Vector2(local.x,local.z)*0.012
			if v.length()>60: v=v.normalized()*60
			draw_rect(Rect2(c+v-Vector2(2,2),Vector2(4,4)),PINK if p.is_hostile_to(body) else VIOLET)
		line(c+Vector2(-4,4),c+Vector2(0,-4),GOLD,2);line(c+Vector2(0,-4),c+Vector2(4,4),GOLD,2)
	else:
		text(Vector2(-102,-47),"WEAPON SYSTEM",DIM,10)
		text(Vector2(-102,-20),"RIFLE   %02d" % p.rifle_mag,VIOLET,13)
		text(Vector2(-102,4),"GRENADE %02d" % p.grenade_count,PINK,13)
		_segments(Vector2(-102,20),193,p.hp/maxf(p.max_hp,1),VIOLET)
		text(Vector2(-102,48),p.profile.model_name,DIM,10)

