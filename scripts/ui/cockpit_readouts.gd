extends RefCounted
## Compact, read-only flight HUD for the panoramic cockpit.
const STYLE := preload("res://scripts/ui/third_person_hud.gd")
const INK := STYLE.WHITE
const DIM := STYLE.DIM
const FAINT := STYLE.FAINT
const FIELD := STYLE.CYAN
const AMBER := STYLE.AMBER
const RED := STYLE.RED

static func layout(view_size: Vector2) -> Dictionary:
	var instruments: Dictionary = load("res://scripts/ui/cockpit_3d.gd").instrument_layout(view_size)
	var margin := 32.0
	var side: Rect2 = instruments.left
	var width := clampf(side.position.x-margin-20.0,148.0,272.0)
	return {"speed":Rect2(margin,view_size.y*0.5-40,width,110),
		"alt":Rect2(view_size.x-margin-width,view_size.y*0.5-40,width,110),
		"health":Rect2(margin,view_size.y-140,width,100),
		"weapons":Rect2(view_size.x-margin-width,view_size.y-238,width,198),
		"contacts":Rect2(view_size.x-margin-292,26,292,222)}

func readout_layout(h) -> Dictionary:
	if h.player.profile.id == SuitProfile.Id.FULL_ARMOR_TB:
		var v: Vector2 = h.size
		return {"speed":Rect2(v*Vector2(.045,.45),v*Vector2(.18,.15)),
			"alt":Rect2(v*Vector2(.775,.45),v*Vector2(.18,.15)),
			"contacts":Rect2(v*Vector2(.755,.21),v*Vector2(.215,.22))}
	if h.player.profile.id != SuitProfile.Id.NEUE_ZIEL: return layout(h.size)
	# Side windows have clear outer lanes; nothing is printed on the solid fascia.
	var k: float = minf(h.size.x/1280.0,h.size.y/720.0)
	var w := 138.0*k
	var left := 12.0*k
	var right: float = h.size.x-left-w
	return {"speed":Rect2(left,h.size.y*0.32,w,110*k),
		"alt":Rect2(right,h.size.y*0.32,w,110*k),
		"health":Rect2(left,h.size.y*0.56,w,100*k),
		"weapons":Rect2(right,h.size.y*0.55,w,198*k),
		"contacts":Rect2(right,h.size.y*0.20,w,78*k)}

func panel(h, r: Rect2, title: String) -> void:
	# Floating captions only: no filled panels, enclosure or corner ornaments.
	if title!="": h._text(r.position+Vector2(10,18),title,11,DIM)

func flight_ticks(h, r: Rect2, value: float, right: bool) -> void:
	if h.player.is_nu():return
	if not h.cockpit_has_graduations(): return
	var x := r.position.x-8 if right else r.end.x+8
	var center := r.position.y+40
	var side := -1.0 if right else 1.0
	for tick: Dictionary in STYLE.ruler_ticks(value,20.0,16.0,68.0):
		var y: float = center-float(tick.offset)
		var length := 8.0 if int(tick.index)%3==0 else 4.0
		h.draw_line(Vector2(x,y),Vector2(x+side*length,y),FAINT,UILayout.LINE_STRUCT,true)
	h.draw_line(Vector2(x-side*3,center-3),Vector2(x,center),DIM,UILayout.LINE_STRUCT,true)
	h.draw_line(Vector2(x,center),Vector2(x-side*3,center+3),DIM,UILayout.LINE_STRUCT,true)


func bar(h, r: Rect2, ratio: float, col: Color) -> void:
	STYLE._bar(h,r,ratio,col)

func row(h, r: Rect2, y: float, name: String, value: String, col: Color = INK) -> void:
	h._text(Vector2(r.position.x+10,y),name,12,DIM)
	var available: float = r.size.x-30-h._font.get_string_size(name,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
	var font_size := 13
	while font_size>11 and h._font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>available:
		font_size-=1
	h._text_right(Vector2(r.end.x-10,y),value,font_size,col)

func speed(h) -> void:
	if h.player.profile.id == SuitProfile.Id.FULL_ARMOR_TB: return
	var p = h.player
	var r: Rect2 = readout_layout(h).speed
	var has_gauge: bool = p.has_dash_limit() or p.has_jet_gauge()
	if not has_gauge: r.size.y=78
	panel(h,r,"速度  KM/H")
	flight_ticks(h,r,h.display_speed(p.airspeed_kmh()),false)
	h._text(r.position+Vector2(10,56),str(int(h.display_speed(p.airspeed_kmh()))),32,INK)
	var ratio: float = p.dash_ratio() if p.has_dash_limit() else p.jet_ratio()
	var label := "冲刺" if p.has_dash_limit() else "推进"
	var col: Color = FIELD if ratio>=0.25 else AMBER
	var value := "%d%%" % int(ratio*100)
	if p.has_dash_limit() and p.dash_cd>0:
		value="%.1fs" % p.dash_cd
		col=AMBER
	if has_gauge:
		row(h,r,r.position.y+79,label,value,col)
		bar(h,Rect2(r.position+Vector2(10,88),Vector2(r.size.x-20,5)),ratio,col)
	if p.fm.stalled: h._text_right(r.position+Vector2(r.size.x-10,55),"失速",13,RED)
	elif p.fm.hovering: h._text_right(r.position+Vector2(r.size.x-10,55),"悬停",12,FIELD)

func altitude(h) -> void:
	if h.player.profile.id == SuitProfile.Id.FULL_ARMOR_TB: return
	var p = h.player
	var r: Rect2 = readout_layout(h).alt
	var alt: float = p.global_position.y
	var col: Color = INK if alt>=h.ALT_WARN_M else (AMBER if alt>=h.ALT_DANGER_M else RED)
	panel(h,r,"海拔  M")
	flight_ticks(h,r,alt*h.ALT_DISPLAY_SCALE,true)
	h._text_right(r.position+Vector2(r.size.x-10,56),str(int(alt*h.ALT_DISPLAY_SCALE)),32,col)
	var vs: float = p.fm.velocity.y
	row(h,r,r.position.y+79,"升降","%+d m/s" % int(vs*h.ALT_DISPLAY_SCALE),DIM if vs>-60 else AMBER)
	var fwd: Vector3 = p.forward()
	var heading := int(fposmod(rad_to_deg(atan2(fwd.x,-fwd.z)),360))
	row(h,r,r.position.y+98,"航向","%03d°" % heading,DIM)
	if p.fm.g_load>=9.0: h._text(r.position+Vector2(10,55),"%.1f G" % p.fm.g_load,12,AMBER)

func health(h) -> void:
	if h.player.profile.id == SuitProfile.Id.FULL_ARMOR_TB: return
	var p = h.player
	var r: Rect2 = readout_layout(h).health
	panel(h,r,"")
	var hp: float = p.hp_ratio()
	var col := INK if hp>0.25 else RED
	h._text(r.position+Vector2(10,42),"AP",13,DIM)
	h._text_right(r.position+Vector2(r.size.x-10,43),"%05d" % int(p.hp),26,col)
	bar(h,Rect2(r.position+Vector2(10,50),Vector2(r.size.x-20,4)),hp,col)
	row(h,r,r.position.y+76,"I-FIELD","%03d" % int(p.ifield_hp) if p.has_ifield() else "DOWN",INK if p.has_ifield() else RED)
	bar(h,Rect2(r.position+Vector2(10,83),Vector2(r.size.x-20,2)),p.ifield_ratio(),INK if p.has_ifield() else RED)
	if p.is_nu():
		row(h,r,r.position.y+98,"浮游防护","展开" if p.nu_systems.barrier_active() else "待命",DIM)
	elif p.is_sazabi():
		row(h,r,r.position.y+98,"SHIELD","展开" if p.shield_up else ("%.1fs" % p.shield_cooldown if p.shield_cooldown>0 else "READY"),DIM)


func weapon_rows(h) -> Array:
	var p = h.player
	if p.thunderbolt_systems!=null:return p.thunderbolt_systems.hud_rows()
	if p.is_zorin():return preload("res://scripts/ui/zorin_hud.gd").rows(p,true)
	var rows: Array = []
	var slot: String = p.current_slot()
	var name := "肩甲四炮" if p.profile.id == SuitProfile.Id.NEUE_ZIEL else ("主炮" if p.profile.cannon_only else "步枪")
	var value := "四炮 · %d轮" % p.rifle_mag if p.profile.id == SuitProfile.Id.NEUE_ZIEL else "枪×%d · %d/%d" % [p.rifle_count,p.rifle_mag,p.profile.rifle_magazine]
	var col: Color = INK if p.rifle_count>0 and p.rifle_mag>0 else AMBER
	var progress := -1.0
	if p.has_infinite_rifle_ammo(): value="∞"
	if p.rifle_reloading:
		value="换弹 %d%%" % int(p.reload_progress()*100)
		progress=p.reload_progress()
		col=FIELD
	if p.profile.cannon_only:
		value = "%.1fs" % p.cannon_cd_left if p.cannon_cd_left>0 else ("冷却" if p.rifle_reloading else "长按蓄力")
		progress = -1.0
	if slot=="cannon":
		name="腹部蓄力炮"
		value="%.1fs" % p.cannon_cd_left if p.cannon_cd_left>0 else "就绪"
		progress=-1.0
	elif slot=="wire":
		name = "线控臂"
		value = "展开" if is_instance_valid(p.active_wire_arms) else ("%.1fs" % p.wire_cd_left if p.wire_cd_left>0 else "就绪")
		progress = -1.0
	elif slot=="bazooka" and p.is_nu():
		name="火箭筒";value=p.nu_systems.bazooka_status();progress=float(p.nu_systems.bazooka_mag)/4.0
	elif slot=="ram":
		name="主动冲撞"
		value=("直接开炮" if p.active_grapple.attached else "冲撞中") if is_instance_valid(p.active_grapple) else ("%.1fs" % p.grapple_cd if p.grapple_cd>0 else "1.3km")
		progress=-1.0
	elif slot=="saber":
		name="军刀"
		value="突进" if p.saber_active() else ("%.1fs" % p.saber_cooldown if p.saber_cooldown>0 else "就绪")
		progress=-1
		col=INK if p.saber_cooldown<=0 else DIM
	elif slot=="grenade":
		name="榴弹"
		value="装填 %.1fs" % p.grenade_reload_left if p.grenade_reload_left>0 else "%d/%d" % [p.grenade_count,p.profile.grenade_count]
		progress=-1
		col=INK if p.grenade_count>0 else AMBER
	rows.append({"name":name,"value":value,"col":col,"bar":progress})
	if p.cannon_available():
		var state := "就绪"
		var c := DIM
		if p.cannon_cd_left>0: state="%.1fs" % p.cannon_cd_left
		elif p.rifle_reloading: state="过热 %.1fs" % p.reload_timer; c=AMBER
		elif not p.cannon_ready(): state="未就绪"; c=AMBER
		rows.append({"name":"蓄力炮","value":state,"col":c})
	if p.profile.id in [SuitProfile.Id.GP03D,SuitProfile.Id.GP03S]:
		rows.append({"name":"双火箭筒" if p.profile.id == SuitProfile.Id.GP03S else "火箭筒","value":"装填 %.1fs" % p.bazooka_reload_left if p.bazooka_reload_left>0 else "%d/16" % p.bazooka_mag,"col":INK})
	elif p.profile.id == SuitProfile.Id.NEUE_ZIEL:
		rows.append({"name":"肩甲四炮","value":"%d轮" % p.rifle_mag,"col":INK})
	elif p.profile.has_vulcan():
		rows.append({"name":"火神炮","value":"过热" if p.vulcan_overheated else "热 %d%%" % int(p.vulcan_heat*100),"col":RED if p.vulcan_overheated else (AMBER if p.vulcan_heat>=0.6 else DIM),"bar":p.vulcan_heat})
	if p.is_nu():
		rows.append({"name":"浮游炮","value":p.nu_systems.status_text(),"col":INK,"bar":p.nu_systems.energy/100.0})
		rows.append({"name":"Alt模式","value":p.nu_systems.mode_name(),"col":DIM})
	if p.profile.has_missiles:
		var value_m := "%d · %s" % [p.funnel_count,"已锁" if h.lock!=null and h.lock.locked else ("不可锁" if h._target_unlockable() else "未锁")]
		var loading: bool = p.funnel_reload_left>0
		if loading: value_m="装填 %d%%" % int(p.funnel_reload_progress()*100)
		else: value_m+=h._salvo_spread_text()
		if p.profile.id == SuitProfile.Id.GP03D:
			value_m = "%d/16舱" % (p.funnel_count/108)
			if loading: value_m += " · +1 %.0fs" % ceilf(p.funnel_reload_left)
		rows.append({"name":"导弹","value":value_m,"col":FIELD if loading else (INK if p.funnel_count>0 else AMBER),"bar":p.funnel_reload_progress() if loading else -1.0})
	var full: bool = int(p.missile_mode)==PlayerController.MissileMode.FULL_SALVO
	var secondary := "待命"
	var secondary_col := DIM
	if full:
		secondary="%.0fs" % ceilf(p.full_salvo_cooldown) if p.full_salvo_cooldown>0 else ("就绪×%d" % PlayerController.FULL_SALVO_COUNT if p.full_salvo_ready() else "弹药不足")
		if p.profile.full_salvo_capacity > 1: secondary = p.full_salvo_charge_status()
		if secondary=="弹药不足": secondary_col=AMBER
	elif p.selected_threat()!=null:
		secondary="TTI %.1fs" % p.selected_threat_tti()
		secondary_col=RED
	elif p.auto_intercept_active(): secondary="自动"
	elif p.intercept_hold_progress()>0: secondary="自动 %d%%" % int(p.intercept_hold_progress()*100)
	if p.is_nu():
		rows.append({"name":"精准射击","value":"按住右键","col":DIM})
	elif p.profile.id == SuitProfile.Id.GP03D:
		rows.append({"name":"弹仓","value":"108发 · 弱制导","col":DIM})
	else:
		if p.profile.id == SuitProfile.Id.NEUE_ZIEL:
			rows.append({"name":"普通导弹","value":"每次4发","col":DIM})
		else:
			rows.append({"name":"齐射" if full else "拦截","value":secondary,"col":secondary_col})
	rows.append({"name":"干扰弹","value":"装填 %.1fs" % p.flare_reload_left if p.flare_reload_left>0 else str(p.flare_count),"col":DIM if p.flare_count>0 else AMBER})
	if p.shield_up or p.shield_cooldown>0:
		rows.append({"name":"护盾","value":"展开 %.1fs" % p.shield_timer if p.shield_up else "冷却 %.1fs" % p.shield_cooldown,"col":FIELD if p.shield_up else DIM})
	return rows

func target(h) -> void:
	if h.lock==null or not is_instance_valid(h.lock.target): return
	var t = h.lock.target
	if not t.alive: return
	if not h._visible(t.global_position):
		h._draw_off_screen_arrow(t.global_position)
		return
	var point: Vector2 = h._project(t.global_position)
	var distance: float = h.lock.range_to_target()
	var half := clampf(2600.0/maxf(distance,200),0,1)*44+13
	var neue: bool = h.player.profile.id == SuitProfile.Id.NEUE_ZIEL
	var col: Color = Color(1.0,0.88,0.16) if neue else (INK if h.lock.locked else AMBER)
	if neue:
		h._draw_neue_dashed_lock(point,half,h.lock.locked)
	else:
		h._bracket(point,half,col,UILayout.LINE_STRUCT)
	h._text_center(point+Vector2(0,-half-12),"%.1f km" % (distance/1000),13,col)
	var state: String = "已锁" if h.lock.locked else h.lock.tier_name()
	if not h.lock.locked:
		var reason: String = h.lock.block_reason()
		if reason!="" and not reason.contains("质量"): state=reason
		h.draw_arc(point,30,-PI*0.5,-PI*0.5+TAU*h.lock.lock_ratio(),28,AMBER,UILayout.LINE_STRUCT,true)
		h.draw_arc(point,30,0,TAU,28,FAINT,UILayout.LINE_HAIR,true)
	h._draw_target_vitals(point,half+10,96,INK,FIELD)
	h._text_center(point+Vector2(0,half+52),state,12,col)
	var details := ""
	if t.ifield_max>0: details="I %d%%" % int(t.ifield_ratio()*100) if t.has_ifield() else "I 失效"
	var board = t.pedal_owner()
	if board!=null: details+=(" · " if details!="" else "")+"踏板 %d%%" % int(board.ratio()*100)
	if details!="": h._text_center(point+Vector2(0,half+70),details,11,FIELD if t.has_ifield() else AMBER)
	var lead: Vector3 = h.lock.gun_lead_point(SuitProfile.vulcan_speed())
	if h._visible(lead): h.draw_arc(h._project(lead),6,0,TAU,14,AMBER,UILayout.LINE_STRUCT,true)
	if h.player.rifle_count>0:
		var beam: Vector3 = h.lock.gun_lead_point_beam()
		if h._visible(beam):
			h.draw_arc(h._project(beam),10,0,TAU,16,FIELD,UILayout.LINE_STRUCT,true)
			if h.player.aim_assist_enabled() and Ballistics.angle_off_boresight(h.player.aim_forward(),beam-h.player.global_position)<=FlightBody.AIM_ASSIST_SNAP_DEG:
				h.draw_arc(h._project(beam),14,0,TAU,18,AMBER,UILayout.LINE_STRUCT,true)
				h._text_center(h._project(beam)+Vector2(0,26),"吸附",11,AMBER)

func weapons(h) -> void:
	if h.player.profile.id == SuitProfile.Id.FULL_ARMOR_TB: return
	if h.player.profile.id == SuitProfile.Id.SAZABI:
		_sazabi_weapons(h)
		return
	var r: Rect2 = readout_layout(h).weapons
	var rows := weapon_rows(h)
	r.size.y=34+rows.size()*21
	panel(h,r,"")
	var y := r.position.y+40
	for entry: Dictionary in rows:
		row(h,r,y,entry.name,entry.value,entry.get("col",INK))
		var amount := float(entry.get("bar",-1))
		if amount>=0: bar(h,Rect2(r.position.x+10,y+3,r.size.x-20,2),amount,entry.get("col",INK))
		y+=21

func contacts(h) -> void:
	if h.player.profile.id == SuitProfile.Id.FULL_ARMOR_TB: return
	var list: Array = h.player.contacts()
	var r: Rect2 = readout_layout(h).contacts
	var shown: Array[int] = STYLE.contact_indices(list,h.lock.target if h.lock!=null else null)
	if h.player.profile.id == SuitProfile.Id.NEUE_ZIEL and shown.size()>2: shown.resize(2)
	if h.player.profile.id == SuitProfile.Id.FULL_ARMOR_TB and shown.size()>3: shown.resize(3)
	var count := shown.size()
	r.size.y=36+count*19+(18 if list.size()>count else 0)
	panel(h,r,"CONTACTS %02d / KM" % list.size())
	var y := r.position.y+38
	for i: int in shown:
		var fb = list[i]
		if not is_instance_valid(fb): continue
		var distance: float = h.player.global_position.distance_to(fb.global_position)
		var selected: bool = h.lock!=null and h.lock.target==fb
		var scanned: bool = h.lock!=null and distance<=h.lock.seeker_range
		var col: Color = INK if selected else DIM
		h._text(Vector2(r.position.x+10,y),str(i+1),12,col)
		var name: String = fb.display_name.replace("（靶机）","")
		while h._font.get_string_size(name,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x>maxf(24,r.size.x-94):
			name=name.left(name.length()-2)+"…"
		h._text(Vector2(r.position.x+32,y),name,12,col)
		h._text_right(Vector2(r.end.x-10,y),"%.1f%s" % [distance/1000," ○" if not scanned else ""],12,col)
		if h.camera.is_position_behind(fb.global_position): h._draw_contact_arrow(Vector2(r.position.x-8,y-4),fb.global_position,col)
		y+=19
	if list.size()>count: h._text_right(Vector2(r.end.x-10,y),"+%d · %s" % [list.size()-count,InputSetup.hint("Tab","↑")],11,DIM)

func assist(h) -> float:
	if h.player.profile.id == SuitProfile.Id.FULL_ARMOR_TB: return 0.0
	var st: Dictionary = h.player.assist_state()
	var x := 42.0
	var y: float = h.size.y*0.21 if h.player.profile.id == SuitProfile.Id.NEUE_ZIEL else 40.0
	var text := "辅助 ON" if st.get("on",false) else "辅助 OFF"
	if h.player.is_nu():text="辅助驾驶 · 长按G索敌/解除"
	var col: Color = DIM
	if st.get("auto_pull",false): text="接管拉升"; col=RED
	elif st.get("reverse",false): text+=" · 反向巡航"; col=AMBER
	h._text(Vector2(x,y),text,12,col)
	if h._system_event_timer>0 and h._system_event_seen!="":
		h._text(Vector2(x,y+20),h._system_event_seen,12,DIM)
		return y+40
	return y+20


func _sazabi_weapons(h) -> void:
	var p = h.player
	var s = p.sazabi_systems
	var r: Rect2 = readout_layout(h).weapons
	var melee: bool = p.current_slot()=="saber"
	var belly: bool = p.current_slot()=="cannon"
	var index: int = 1 if p.current_slot()=="sniper" else 0
	var primary: String = "光束军刀" if melee else p.weapon_name()
	var ammo: String = ("%.1fs" % p.saber_cooldown if p.saber_cooldown>0 else "READY") if melee else "%02d/%02d" % [s.ammo[index],8 if index==1 else 18]
	if not melee and s.reload_left>0: ammo="装填 %.1fs" % s.reload_left
	if belly: ammo="蓄力中" if p.cannon_hold_ratio()>0 and not p.cannon_charging() else s.cannon_status()
	var fleet: String = "%d/6 · %d%%" % [6-s.lost.size(),int(s.energy*100)]
	if s.state==s.State.RETURNING: fleet="回收 %.1fs" % maxf(0,3-s.return_age)
	if s.repair_left>0: fleet="修复 %.1fs" % s.repair_left
	var rows: Array = [
		[primary,ammo,h._key("fire_primary")+(" 蓄力1.7s后松开" if belly else " 开火 · "+h._key("switch_weapon")+" 切换")],
		["浮游炮",fleet,h._key("fire_missile")+" 展开 / 回收"],
		["光束战斧" if melee else ("蓄力进度" if belly else "腹部蓄力炮"),("%.1fs" % s.axe_cd if s.axe_cd>0 else "挥砍 / 投掷") if melee else ("%d%%" % int(p.cannon_hold_ratio()*100) if belly else s.cannon_status()),("短按挥砍 / 长按投掷 "+h._key("fire_secondary")) if melee else ("按住"+h._key("fire_primary")+"，蓄满后松开" if belly else h._key("switch_weapon")+" 切换 · "+h._key("fire_secondary")+" 精准射击")],
		["浮游炮模式",s.mode_name(),h._key("missile_mode")+" 切换"]]
	for i in rows.size():
		var y: float = r.position.y+24+i*42
		row(h,r,y,rows[i][0],rows[i][1])
		h._text(Vector2(r.position.x+10,y+15),rows[i][2],10,DIM)
	bar(h,Rect2(r.position+Vector2(10,193),Vector2(r.size.x-20,3)),s.energy,FIELD if s.repair_left<=0 else AMBER)
