extends Control
## Flat optical-monitor graphics, composited behind the opaque cabin shell.
var hud: Control
var refresh:=0.0
const BLUE:=Color(.27,.44,1,.76)
const CYAN:=Color(.24,.84,1,.92)
const DIM:=Color(.11,.25,.49,.58)
const PALE:=Color(.67,.83,1,.9)
static func sight(h,at: Vector2) -> void:
	var k: float=clampf(h.size.y/900.0,.65,1.5)
	for side: float in [-1.0,1.0]:
		h.draw_line(at+Vector2(side*9,-5)*k,at+Vector2(side*17,-5)*k,CYAN,1.2,true)
		h.draw_line(at+Vector2(side*17,-5)*k,at+Vector2(side*17,5)*k,CYAN,1.2,true)
		h.draw_line(at+Vector2(side*17,5)*k,at+Vector2(side*9,5)*k,CYAN,1.2,true)
	h.draw_circle(at,1.1,CYAN)
	h.draw_polyline(PackedVector2Array([at+Vector2(-5,23)*k,at+Vector2(0,28)*k,at+Vector2(5,23)*k]),Color(.98,.46,.24),1.3,true)
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
func _process(delta: float) -> void:
	if not is_visible_in_tree():return
	refresh-=delta
	if refresh<=0:refresh=.1;queue_redraw()
func label(at: Vector2,value: String,fs: int,color: Color) -> void:
	draw_string(ThemeDB.fallback_font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,color)
func route(points: Array,color: Color=BLUE,width: float=1.0) -> void:
	var line:=PackedVector2Array()
	for point: Vector2 in points:line.append(point*size)
	draw_polyline(line,color,width,true)
func segment_bar(r: Rect2,amount: float,ink: Color=CYAN) -> void:
	for i in 24:
		var width: float=r.size.x/24
		draw_rect(Rect2(r.position+Vector2(i*width,0),Vector2(width*.64,r.size.y)),ink if i<24*amount else DIM)
func _draw() -> void:
	var v:=size
	var p=hud.player if is_instance_valid(hud) else null
	if not is_instance_valid(p):return
	var k:=minf(v.x/1600.0,v.y/900.0)
	for mirrored in [false,true]:
		var points:=PackedVector2Array()
		for point: Vector2 in [Vector2(.025,.12),Vector2(.265,.18),Vector2(.274,.595),Vector2(.035,.615),Vector2(.025,.12)]:
			points.append(Vector2(1-point.x if mirrored else point.x,point.y)*v)
		draw_polyline(points,BLUE,1,true)
		var sign: float=-1 if mirrored else 1
		var x: float=(.96 if mirrored else .04)*v.x
		for n in 17:
			var y: float=v.y*(.22+n*.018)
			draw_line(Vector2(x,y),Vector2(x+sign*(8 if n%4==0 else 4)*k,y),CYAN if n%4==0 else DIM,1,true)
		# Channel tabs follow each screen's sloping top edge.
		for n in 3:
			var tx: float=(.047+n*.039) if not mirrored else (.953-n*.039-.028)
			var ty: float=.144+n*.009
			var tab:=Rect2(v*Vector2(tx,ty),v*Vector2(.028,.014))
			draw_rect(tab,Color(.06,.13,.29,.65));draw_rect(tab,BLUE,false,.8)
			label(tab.position+Vector2(3,9)*k,["OPT","NAV","TGT"][n],maxi(6,int(7*k)),CYAN)
		var left: float=v.x*(.765 if mirrored else .047)
		var top: float=v.y*.40
		var affine:=Transform2D(Vector2(1,sign*.12),Vector2(sign*.025,1),Vector2.ZERO)
		var telemetry_origin:=Vector2(left,top)
		affine.origin=telemetry_origin-affine*telemetry_origin
		draw_set_transform_matrix(affine)
		var fs:=maxi(7,int(10*k))
		label(Vector2(left,top),"ALT / VERTICAL" if mirrored else "SPD / THRUST",fs,BLUE)
		var value: int=int(p.global_position.y*hud.ALT_DISPLAY_SCALE) if mirrored else int(hud.display_speed(p.airspeed_kmh()))
		var readout_ink: Color=PALE
		if mirrored and p.global_position.y<hud.ALT_WARN_M:readout_ink=Color(1,.64,.22) if p.global_position.y>=hud.ALT_DANGER_M else Color(1,.28,.19)
		label(Vector2(left,top+29*k),"%05d" % value,maxi(14,int(23*k)),readout_ink)
		label(Vector2(left+100*k,top+28*k),"M" if mirrored else "KM/H",fs,CYAN)
		var amount: float=clampf((p.fm.velocity.y+200)/400,0,1) if mirrored else (p.dash_ratio() if p.has_dash_limit() else p.jet_ratio())
		segment_bar(Rect2(left,top+40*k,v.x*.17,3*k),amount,Color(1,.63,.2) if (not mirrored and amount<.25) or (mirrored and p.fm.velocity.y< -60) else CYAN)
		var detail: String="V/S  %+04d" % int(p.fm.velocity.y*hud.ALT_DISPLAY_SCALE) if mirrored else ("DASH  %03d%%" if p.has_dash_limit() else "BOOST  %03d%%") % int(amount*100)
		label(Vector2(left,top+60*k),detail,fs,CYAN)
		var forward: Vector3=p.forward()
		var heading:=int(fposmod(rad_to_deg(atan2(forward.x,-forward.z)),360))
		var status: String="HDG %03d  / RCS ON" % heading if mirrored else ("STALL / WARNING" if p.fm.stalled else ("HOVER / ACTIVE" if p.fm.hovering else ("SHIELD / GUARD" if p.shield_up else "SHIELD / STANDBY")))
		label(Vector2(left,top+76*k),status,maxi(7,int(8*k)),Color(1,.28,.19) if not mirrored and p.fm.stalled else BLUE)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		var anchor:=Vector2(left,v.y*.565)
		label(anchor,"R-CAM / 02" if mirrored else "L-CAM / 01",maxi(7,int(8*k)),CYAN)
		for n in 5:
			draw_rect(Rect2(anchor+Vector2(n*13,7)*k,Vector2(8,2)*k),BLUE if n<3 else DIM)
		# Broken sensor registration track remains entirely in the side display.
		var track:=PackedVector2Array()
		for point: Vector2 in [Vector2(.045,.31),Vector2(.12,.325),Vector2(.14,.35),Vector2(.253,.365)]:
			track.append(Vector2(1-point.x if mirrored else point.x,point.y)*v)
		draw_polyline(track,Color(BLUE,.26),.8,true)
		var channel: Vector2=Vector2(v.x*(.93 if mirrored else .065),v.y*.195)
		label(channel,"02" if mirrored else "01",maxi(7,int(9*k)),CYAN)
		for n in 3:
			draw_rect(Rect2(channel+Vector2(0,5+n*5)*k,Vector2(9+n*3,2)*k),DIM)
	# Contacts are retained in the right optical screen instead of the old floating list.
	var contacts: Array=p.contacts()
	if not contacts.is_empty():
		var at:=v*Vector2(.765,.225)
		label(at,"CONTACT / %02d" % contacts.size(),maxi(7,int(8*k)),BLUE)
		for i in mini(3,contacts.size()):
			var target=contacts[i]
			if not is_instance_valid(target):continue
			var name: String=str(target.display_name).replace("（靶机）","").left(18)
			var value: String="%02d  %s  %.1f KM" % [i+1,name,p.global_position.distance_to(target.global_position)/1000.0]
			label(at+Vector2(0,(i+1)*13)*k,value,maxi(7,int(8*k)),CYAN if hud.lock!=null and hud.lock.target==target else DIM)
	# Sparse split registration above the central combat lane.
	route([Vector2(.318,.17),Vector2(.395,.17),Vector2(.405,.18),Vector2(.45,.18)])
	route([Vector2(.682,.17),Vector2(.605,.17),Vector2(.595,.18),Vector2(.55,.18)])
	label(v*Vector2(.321,.159),"FWD / OPTICAL",maxi(7,int(8*k)),DIM)
	label(v*Vector2(.601,.159),"SENSOR LINK",maxi(7,int(8*k)),DIM)
