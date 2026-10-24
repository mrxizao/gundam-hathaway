extends RefCounted
static func draw(h) -> void:
	var p = h.player
	if not is_instance_valid(p) or not p.alive or Game.phase != Game.Phase.FIGHT: return
	var state = p.combat_buffs
	var green := Color(0.4,1.0,0.65)
	var origin := Vector2(h.size.x*0.5-110,110)
	if p.is_nu():
		var label: String = "精神感应共鸣  %.1fs" % state.resonance_left if state.active() else "共鸣  %03d%%" % roundi(state.gauge)
		h._text_center(origin+Vector2(110,0),label,12,green)
		var bar := Rect2(origin+Vector2(0,8),Vector2(220,3))
		h.draw_rect(bar,Color(0.03,0.1,0.06,0.75))
		bar.size.x *= state.resonance_left/state.RESONANCE_SECONDS if state.active() else state.gauge/100.0
		h.draw_rect(bar,green)
		if state.immune(): h._text_center(origin+Vector2(110,29),"无敌屏障 %.1fs" % state.protection_left,11,green)
	elif p.is_sazabi():
		var victim = state.active_victim.get_ref() if state.active_victim != null else null
		if not is_instance_valid(victim):
			for other in p.get_tree().get_nodes_in_group("units"):
				if other is FlightBody and p.is_hostile_to(other) and other.combat_buffs.kick_left > 0:
					victim = other
					break
		var label := "夏亚飞踢 · 二次近战命中触发"
		if is_instance_valid(victim) and victim.combat_buffs.kick_left>0: label="夏亚飞踢 %.1fs" % victim.combat_buffs.kick_left
		elif state.kick_cd>0: label="夏亚飞踢 冷却 %.1fs" % state.kick_cd
		h._text_center(origin+Vector2(110,0),label,11,Color(1,.65,.5))
	if state.kick_left>0:
		h._text_center(Vector2(h.size.x*.5,158),"夏亚飞踢 %.1fs · 减速%d%% · 15%%斩杀" % [state.kick_left,70 if p.is_zorin() else 40],12,Color(1,.48,.35))
	if not state.active(): return
	# Slow, low-opacity edge pulse. The central aiming area stays clear.
	var phase: float = state.age
	var pulse: float = 0.035+0.015*sin(phase*3.0)
	for i in 8:
		var a: float = pulse*(1.0-float(i)/8)
		var ink := Color(green,a)
		var band: float = 5.0
		h.draw_rect(Rect2(i*band,0,band,h.size.y),ink)
		h.draw_rect(Rect2(h.size.x-(i+1)*band,0,band,h.size.y),ink)
		h.draw_rect(Rect2(0,i*band,h.size.x,band),ink)
		h.draw_rect(Rect2(0,h.size.y-(i+1)*band,h.size.x,band),ink)
	for i in 24:
		var side: int = i%4
		var u: float = fposmod(i*.173+phase*.025,1.0)
		var margin: float = 14+22*sin(phase*.8+i)*sin(phase*.8+i)
		var point := Vector2(margin,u*h.size.y)
		if side==1: point=Vector2(h.size.x-margin,u*h.size.y)
		elif side==2: point=Vector2(u*h.size.x,margin)
		elif side==3: point=Vector2(u*h.size.x,h.size.y-margin)
		h.draw_circle(point,1.5+float(i%3)*.5,Color(green,.30))
