extends RefCounted
const INK=Color(1,.38,.12,.8)
static func draw(h)->void:
	var v:Vector2=h.size;var k:=v.y/720.0
	var aim:Vector2=h._fpv_reticle_position()
	if aim.is_finite():
		for sign in [-1,1]:
			h.draw_line(aim+Vector2(sign*8,0)*k,aim+Vector2(sign*21,0)*k,INK,1.2,true)
			h.draw_line(aim+Vector2(0,sign*8)*k,aim+Vector2(0,sign*16)*k,INK,1.2,true)
		h.draw_circle(aim,1.5*k,INK)
		h._draw_cannon_charge_ring(aim)
	# Limited monitor markings: no spherical horizon rings or full-screen decorative arcs.
	for side in [-1.0,1.0]:
		var x:float=v.x*(.5+side*.15)
		for n in 7:
			var y:float=v.y*(.28+n*.041)
			h.draw_line(Vector2(x,y),Vector2(x+side*(8 if n%3==0 else 4)*k,y),Color(INK,.4),1,true)
	h._text(v*Vector2(.397,.14),"PSYCOMMU  /  DIRECT SIGHT",int(10*k),INK)
	if is_instance_valid(h.lock) and is_instance_valid(h.lock.target) and not h.camera.is_position_behind(h.lock.target.global_position):
		var target=h.lock.target;var at:Vector2=h._project(target.global_position)
		# Targets below the monitor edge remain on the central radar instead of over solid console.
		if at.x>v.x*.025 and at.x<v.x*.975 and at.y>v.y*.12 and at.y<v.y*.65:
			var r:=19*k
			for sign in [-1.0,1.0]:
				h.draw_line(at+Vector2(sign*r,-r),at+Vector2(sign*r,r),INK,1.2,true)
				h.draw_line(at+Vector2(sign*r,-r),at+Vector2(sign*(r-7*k),-r),INK,1.2,true)
			h._text(at+Vector2(-r,-r-25*k),target.display_name,int(11*k),INK)
			h._draw_target_vitals(at,r+8*k,50*k,INK,Color(1,.60,.20),k)
			if not h.lock.locked:h._text(at+Vector2(-r,-r-39*k),"ACQ %02d%%"%int(h.lock.quality*100),int(9*k),INK)
			h._text(at+Vector2(-r,-r-9*k),"%.1f KM"%(h.player.global_position.distance_to(target.global_position)/1000),int(10*k),INK)
	h._draw_threat_layer();h._draw_allies();h._draw_beacons()
	h._draw_comms();h._draw_notices();h._draw_endless_intensity();h._draw_phase_overlay()
