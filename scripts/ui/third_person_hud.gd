extends RefCounted
## Third-person combat layout: curved projection, white instruments, contextual text.
## Reads existing combat state only. The cockpit continues using FlightHUD's renderer.

const WHITE := Color(0.93, 0.96, 1.0, 0.94)
const DIM := Color(0.77, 0.83, 0.90, 0.72)
const FAINT := Color(0.72, 0.79, 0.87, 0.32)
const INK := Color(0.018, 0.027, 0.045, 0.90)
const RED := Color(1.0, 0.31, 0.27)
const AMBER := Color(1.0, 0.74, 0.30)
const CYAN := Color(0.53, 0.83, 0.94)
const CONTACT_LIMIT := 3

# Only peripheral flight references move. Crosshair, target projection, radar,
# resource bars and text remain in their original screen space.
var _motion_ready := false
var _last_heading := 0.0
var pitch_offset := 0.0
var turn_offset := 0.0
var bank := 0.0

func reset_motion() -> void:
	_motion_ready = false
	pitch_offset = 0.0
	turn_offset = 0.0
	bank = 0.0

func tick_motion(b: Basis, delta: float, turn_scale := 1.0) -> void:
	if delta <= 0.0:
		return
	var fwd := -b.z.normalized()
	var heading := atan2(-fwd.x, -fwd.z)
	# Heading is undefined at a vertical nose; retain the last valid bearing.
	if Vector2(fwd.x, fwd.z).length_squared() < 0.0001:
		heading = _last_heading
	var pitch := rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))
	var roll := atan2(b.x.y, b.y.y)
	var wanted_pitch := clampf(pitch * 1.8, -52.0, 52.0)
	# Canvas Y points down: positive body roll gives a clockwise world reference.
	var wanted_bank := clampf(roll * 0.45, -deg_to_rad(12.0), deg_to_rad(12.0))
	if not _motion_ready:
		_last_heading = heading
		pitch_offset = wanted_pitch
		bank = wanted_bank
		_motion_ready = true
	var turn_rate := rad_to_deg(wrapf(heading - _last_heading, -PI, PI)) / delta
	_last_heading = heading
	var blend := 1.0 - exp(-10.0 * delta)
	pitch_offset = lerpf(pitch_offset, wanted_pitch, blend)
	bank = lerpf(bank, wanted_bank, blend)
	var wanted_turn := clampf(turn_rate * 0.22, -18.0, 18.0) * clampf(turn_scale, 0.0, 1.0)
	turn_offset = lerpf(turn_offset, wanted_turn, blend) if turn_scale > 0 else 0.0

func frame_point(center: Vector2, local: Vector2) -> Vector2:
	return center + Vector2(turn_offset, pitch_offset) + local.rotated(bank)

func corner_rail(center: Vector2, side: float, vertical: float, radar: Rect2, weapons: Rect2) -> PackedVector2Array:
	# Rotate each short rail about its own midpoint. Rotating the entire frame
	# would sweep its lower-left corner through the radar during a bank.
	var pivot := center + Vector2(side * 365, vertical * 230)
	pivot += Vector2(turn_offset * 0.5, pitch_offset * 0.45)
	var half := Vector2(side * 23, -vertical * 40).rotated(bank)
	var a := pivot - half
	var b := pivot + half
	if vertical > 0:
		var correction := maxf(0, radar.end.x + 18 - minf(a.x, b.x)) if side < 0 else minf(0, weapons.position.x - 18 - maxf(a.x, b.x))
		a.x += correction
		b.x += correction
	return PackedVector2Array([a, b])

# Absolute graduations translate continuously past a fixed current-value index.
# Shared by compass and vertical tapes; wrapping changes labels, not geometry.
static func ruler_ticks(value: float, step: float, spacing: float, extent: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var base := floori(value / step)
	var count := ceili(extent / spacing) + 1
	for i in range(base - count, base + count + 1):
		var offset := (float(i) * step - value) * spacing / step
		if absf(offset) <= extent:
			result.append({"index": i, "value": float(i) * step, "offset": offset})
	return result

static func layout(view: Vector2) -> Dictionary:
	var u := minf(view.x / 1600.0, view.y / 900.0)
	var v := view / maxf(u, 0.01)
	return {"scale": u, "view": v, "center": v * 0.5,
		"ap": Rect2(72, v.y - 174, 310, 128),
		"energy": Rect2(v.x * 0.5 - 245, v.y - 134, 490, 42),
		"radar": Rect2(280, v.y - 306, 116, 116),
		"weapons": Rect2(v.x - 390, v.y - 181, 318, 156),
		"speed": Rect2(72, v.y * 0.5 - 165, 205, 330),
		"alt": Rect2(v.x - 277, v.y * 0.5 - 165, 205, 330)}

# Left-aligned below assist and its system-event line, above the speed instrument.
static func magnifier_rect(view: Vector2) -> Rect2:
	var g := layout(view)
	var u: float = g["scale"]
	var panel_size := Vector2(240, 135) * 0.85
	return Rect2(Vector2(72, 112) * u, panel_size * u)

static func contact_indices(contacts: Array, target) -> Array[int]:
	var result: Array[int] = []
	for i in mini(contacts.size(), CONTACT_LIMIT):
		result.append(i)
	var selected := contacts.find(target) if target != null else -1
	if selected >= CONTACT_LIMIT:
		result[CONTACT_LIMIT - 1] = selected
	return result

static func draw(h) -> void:
	var g := layout(h.size)
	var u: float = g["scale"]
	var v: Vector2 = g["view"]
	var c: Vector2 = g["center"]
	h.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * u)
	_compass(h, v)
	_reticle(h, c)
	_tape(h, g["speed"], h.display_speed(h.player.airspeed_kmh()), "速度", false)
	_tape(h, g["alt"], h.player.global_position.y * h.ALT_DISPLAY_SCALE, "高度", true)
	_health(h, g["ap"])
	_energy(h, g["energy"])
	_weapons(h, g["weapons"])
	_radar(h, g["radar"])
	_status(h, v)
	_contacts(h, v)
	_target(h, u)
	_rifle_feedback(h, u)
	_notices(h, v)
	h.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func _line(h, a: Vector2, b: Vector2, col := WHITE, width := 1.0) -> void:
	h.draw_line(a + Vector2(0, 1), b + Vector2(0, 1), Color(INK, INK.a * col.a), width + 2.0, true)
	h.draw_line(a, b, col, width, true)

static func _arc(h, c: Vector2, r: float, a: float, b: float, col := WHITE, width := 1.0) -> void:
	h.draw_arc(c, r, a, b, 64, Color(INK, INK.a * col.a), width + 2.0, true)
	h.draw_arc(c, r, a, b, 64, col, width, true)

# Curves share a dark under-stroke, so white remains legible over clouds and sea.
static func _stroke(h, points: PackedVector2Array, col := WHITE, width := 1.0) -> void:
	h.draw_polyline(points, Color(INK, INK.a * col.a), width + 2.0, true)
	h.draw_polyline(points, col, width, true)

static func _bow(r: Rect2, bend: float, end := 1.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(33):
		var t := i / 32.0 * end
		points.append(r.position + Vector2(r.size.x * t, 4.0 * bend * t * (1.0 - t)))
	return points

static func _text(h, p: Vector2, text: String, fs := 12, col := WHITE) -> void:
	h._magnifier_text_rect(p, text, fs, true)
	h.draw_string_outline(h._font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, INK)
	h.draw_string(h._font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

static func _right(h, p: Vector2, text: String, fs := 12, col := WHITE) -> void:
	var w: float = h._font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_text(h, p - Vector2(w, 0), text, fs, col)

static func _center(h, p: Vector2, text: String, fs := 12, col := WHITE) -> void:
	var w: float = h._font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_text(h, p - Vector2(w * 0.5, 0), text, fs, col)

static func _bar(h, r: Rect2, ratio: float, col := WHITE) -> void:
	h.draw_rect(r.grow(2), INK)
	h.draw_rect(r, FAINT)
	h.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(ratio, 0, 1), r.size.y)), col)
	_line(h, r.position - Vector2(3, 2), r.position + Vector2(-3, r.size.y + 2), DIM)
	_line(h, r.end + Vector2(3, 2), r.end + Vector2(3, -r.size.y - 2), DIM)

static func _compass(h, v: Vector2) -> void:
	var fwd: Vector3 = h.player.forward()
	var heading := fposmod(rad_to_deg(atan2(-fwd.x, -fwd.z)), 360.0)
	var x := v.x * 0.5
	# A shallow lens arc replaces the flat ruler; labels stay horizontal.
	var top := Rect2(x - 324, 52, 648, 0)
	_stroke(h, _bow(top, 25), FAINT)
	for tick: Dictionary in ruler_ticks(heading, 2.5, 9.0, 324.0):
		var i: int = tick["index"]
		var t: float = (tick["offset"] + 324.0) / 648.0
		var at := top.position + Vector2(t * top.size.x, 100.0 * t * (1.0 - t))
		var normal := Vector2(-100.0 * (1.0 - 2.0 * t) / top.size.x, 1).normalized()
		var ht := 7.0 if i % 6 == 0 else 2.5
		_line(h, at, at + normal * ht, DIM if i % 6 == 0 else FAINT)
		if i % 12 == 0:
			_center(h, at + Vector2(0, -9), "%03d" % int(fposmod(tick["value"], 360)), 10, DIM)
	_arc(h, Vector2(x, 92), 3, 0, TAU, WHITE)
	_center(h, Vector2(x, v.y - 31), "%03d" % int(heading), 12)
	for tick: Dictionary in ruler_ticks(heading, 2.5, 12.0, 360.0):
		var i: int = tick["index"]
		if absf(tick["offset"]) < 48.0:
			continue
		var at := Vector2(x + tick["offset"], v.y - 40)
		_line(h, at, at + Vector2.UP * (6.0 if i % 6 == 0 else 2.0), FAINT)

static func _reticle(h, c: Vector2) -> void:
	var r := 112.0
	# Two short arcs retain the circular instrument without closing over the suit.
	# Ammunition stays in the weapon panel; lock/charge also use these open sectors.
	var progress := 0.0
	var locked := false
	if h.lock != null and h.lock.target != null:
		progress = clampf(h.lock.lock_ratio(), 0, 1)
		locked = h.lock.locked
	var charge: float = h.player.cannon_hold_ratio()
	for start: float in [0.10 * PI, 0.72 * PI]:
		_arc(h, c, r, start, start + 0.18 * PI, Color(DIM, 0.40))
		if progress > 0:
			_arc(h, c, r - 4, start, start + 0.18 * PI * progress, Color(WHITE if locked else AMBER, 0.65))
		if charge > 0:
			_arc(h, c, r + 5, start, start + 0.18 * PI * charge, AMBER, 1.5)
	for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		_line(h, c + direction * 15, c + direction * 24)
	# Keep the real ballistics aiming point unchanged.
	if h.player.cursor_seen and not InputSetup.using_gamepad:
		var mouse: Vector2 = h.player.aim_cursor / float(layout(h.size)["scale"])
		h._magnifier_ui_rect(Rect2(mouse - Vector2.ONE * 8, Vector2.ONE * 16), true)
		_arc(h, mouse, 5, 0, TAU, WHITE)
	# Short open corner rails echo the reference without enclosing the whole view.
	var motion = h._third_person_motion
	var g := layout(h.size)
	for side in [-1.0, 1.0]:
		for vertical in [-1.0, 1.0]:
			var rail: PackedVector2Array = motion.corner_rail(c, side, vertical, g["radar"], g["weapons"])
			var a := rail[0]
			var b := rail[1]
			_line(h, a, b, FAINT)
			var parallel := Vector2(side * 4, 0).rotated(motion.bank)
			var cap := Vector2(side * 8, -vertical * 4).rotated(motion.bank)
			_line(h, a + parallel, b + parallel, FAINT)
			_line(h, a, a + cap, DIM)
			_line(h, b, b + cap, DIM)
	# Two short horizon wings expose pitch/bank without restoring the large circle
	# or drawing a ladder over the mech. Fixed end indices make movement readable.
	for side in [-1.0, 1.0]:
		var a: Vector2 = motion.frame_point(c, Vector2(side * 154, 0))
		var b: Vector2 = motion.frame_point(c, Vector2(side * 184, 0))
		_line(h, a, b, DIM)
		_line(h, a, a + Vector2(0, 5).rotated(motion.bank), DIM)
		var index := c + Vector2(side * 209, 0)
		_line(h, index, index + Vector2(side * 8, 0), FAINT)

static func _tape(h, r: Rect2, value: float, title: String, right: bool) -> void:
	var mid := r.get_center().y
	var sign_x := -1.0 if right else 1.0
	var col := WHITE
	if right and h.player.global_position.y < h.ALT_WARN_M:
		col = RED if h.player.global_position.y < h.ALT_DANGER_M else AMBER
	# Sparse, separate strokes: an inner vertical tape and an outer bowed fan.
	var inner := r.position.x + 16 if right else r.end.x - 16
	var step := 20.0 # Display units, including the existing speed/altitude scales.
	for tick: Dictionary in ruler_ticks(value, step, 21.0, 147.0):
		var i: int = tick["index"]
		var at := Vector2(inner, mid - tick["offset"])
		var half := 7.0 if i % 3 == 0 else 4.5
		_line(h, at - Vector2(half, 0), at + Vector2(half, 0), DIM, 1.2)
	# A fixed, open index shows which graduation the numeric readout refers to.
	var tip := Vector2(inner - sign_x * 12, mid)
	_line(h, tip, tip + Vector2(-sign_x * 5, -4), WHITE)
	_line(h, tip, tip + Vector2(-sign_x * 5, 4), WHITE)
	var outer := r.end.x - 94 if right else r.position.x + 94
	for tick: Dictionary in ruler_ticks(value, step, 25.0, 150.0):
		var offset: float = -tick["offset"]
		if absf(offset) < 27.0:
			continue
		var at := Vector2(outer + sign_x * 44.0 * pow(offset / 150.0, 2), mid + offset)
		var normal := Vector2(sign_x, -88.0 * offset / (150.0 * 150.0)).normalized()
		_line(h, at - normal * 8, at + normal * 8, DIM, 1.2)
	# The reference's horizontal label / value / unit stays unboxed and readable.
	var x := r.position.x + (58.0 if right else 0.0)
	_text(h, Vector2(x, mid + 6), title, 13, DIM)
	_text(h, Vector2(x + 46, mid + 8), "%d" % int(value), 26, col)
	_text(h, Vector2(r.end.x - 15 if right else x + 131, mid + 6), "米" if right else "公里/时", 11, DIM)
	if right and absf(h.player.fm.velocity.y) > 25:
		_right(h, Vector2(r.end.x, mid + 33), "%+d m/s" % int(h.player.fm.velocity.y * h.ALT_DISPLAY_SCALE), 10, DIM)

static func _health(h, r: Rect2) -> void:
	var p = h.player
	var col := WHITE if p.hp_ratio() > 0.25 else RED
	_text(h, r.position + Vector2(0, 28), "AP", 13, DIM)
	_right(h, Vector2(r.end.x, r.position.y + 30), "%05d" % int(p.hp), 34, col)
	_bar(h, Rect2(r.position + Vector2(0, 43), Vector2(r.size.x, 4)), p.hp_ratio(), col)
	_text(h, r.position + Vector2(0, 74), "I-FIELD", 10, DIM)
	_right(h, Vector2(r.end.x, r.position.y + 74), "%03d" % int(p.ifield_hp) if p.has_ifield() else "DOWN", 14, WHITE if p.has_ifield() else RED)
	_bar(h, Rect2(r.position + Vector2(0, 82), Vector2(r.size.x, 2)), p.ifield_ratio(), WHITE if p.has_ifield() else RED)
	if p.is_nu():
		_text(h,r.position+Vector2(0,98),"浮游防护 · "+("展开" if p.nu_systems.barrier_active() else "待命"),10,DIM)
	elif p.is_sazabi():
		_text(h,r.position+Vector2(0,98),"SHIELD · "+("展开" if p.shield_up else ("CD %.1fs" % p.shield_cooldown if p.shield_cooldown>0 else "READY")),10,DIM)
	_text(h, r.position + Vector2(0, 114), p.profile.model_name, 11, DIM)

static func _energy(h, r: Rect2) -> void:
	var p = h.player
	var ratio := 1.0
	var status := "BOOST ON" if p.fm.boosting else "BOOST"
	if p.has_jet_gauge():
		ratio = p.jet_ratio()
	elif p.has_dash_limit():
		ratio = p.dash_ratio()
		if p.dash_cd > 0:
			status = "COOLDOWN %.1f" % p.dash_cd
	var col := WHITE if ratio > 0.25 else AMBER
	if ratio <= 0:
		col = RED
	_bar(h, Rect2(r.position, Vector2(r.size.x, 5)), ratio, col)
	_center(h, r.position + Vector2(r.size.x * 0.5, 25), status, 11, col if p.fm.boosting or ratio < 0.25 else DIM)
	if p.vulcan_heat > 0.05:
		_bar(h, Rect2(r.position + Vector2(72, -14), Vector2(r.size.x - 144, 2)), p.vulcan_heat, RED if p.vulcan_overheated else AMBER)
		_center(h, r.position + Vector2(r.size.x * 0.5, -22), "OVERHEAT" if p.vulcan_overheated else "HEAT", 10, AMBER)

static func _thunderbolt_weapons(h,r:Rect2)->void:
	var p=h.player;var s=p.thunderbolt_systems
	var primary="READY" if p.current_slot()=="saber" else ("装填 %.1fs"%s.primary_reload if s.primary_reload>0 else str(s.primary_ammo))
	var secondary="%.1fs"%s.secondary_cd if s.secondary_cd>0 else "READY"
	if s.psycho() and s.secondary_missiles:secondary="装填 %.1fs"%s.bazooka_reload if s.bazooka_reload>0 else str(s.bazooka_ammo)
	elif not s.psycho() and s.secondary_missiles:secondary=s.missile_status()
	var rows=[
		[p.weapon_name(),primary,h._key("fire_primary")],
		[s.secondary_name(),secondary,h._key("fire_secondary")+" · Alt切换"],
		["双重火箭" if s.psycho() else "五连导弹", ("%.1fs"%s.support_cd if s.support_cd>0 else "READY") if s.psycho() else s.missile_status(),("长按 " if s.psycho() else "")+h._key("fire_missile")],
		["机关枪" if s.psycho() else "闪光弹",("过热" if p.vulcan_overheated else "∞") if s.psycho() else s.flash_status(),h._key("fire_gun")+("" if s.psycho() else " · 再按引爆")],
		["干扰弹",str(p.flare_count),h._key("flares")],
		["热能斧" if s.psycho() else "撑盾", "不可撑盾" if s.psycho() else ("展开 %.1fs"%p.shield_timer if p.shield_up else ("CD %.1fs"%p.shield_cooldown if p.shield_cooldown>0 else "READY")),h._key("switch_weapon") if s.psycho() else h._key("shield")]]
	var width:float=(r.size.x-24)*.5
	for i in rows.size():
		var entry=rows[i]
		_weapon_cell(h,Rect2(r.position+Vector2((i%2)*(width+24),(i/2)*48),Vector2(width,40)),entry[2],entry[0],entry[1],-1,WHITE,14)
	_text(h,r.position+Vector2(0,151),"X 切换近战 · R 换弹",10,DIM)
	if p.weapons_locked():_text(h,r.position+Vector2(0,-24),"武器封锁 %.1fs"%p.thunder_lock_left,13,RED)

static func _weapon_cell(h, r: Rect2, key: String, name: String, value: String, ratio := -1.0, col := WHITE, value_size := 18) -> void:
	_text(h, r.position, name, 11, WHITE)
	_right(h, Vector2(r.end.x, r.position.y + 2), value, value_size, col)
	_line(h, r.position + Vector2(0, 10), Vector2(r.end.x, r.position.y + 10), FAINT)
	if ratio >= 0:
		_bar(h, Rect2(r.position + Vector2(0, 10), Vector2(r.size.x, 2)), ratio, col)
	_text(h, r.position + Vector2(0, 27), key, 10, DIM)

static func _sazabi_weapons(h,r:Rect2)->void:
	var p=h.player
	var s=p.sazabi_systems
	var width:float=(r.size.x-24)*.5
	var cell:=Rect2(r.position,Vector2(width,36))
	var melee:bool=p.current_slot()=="saber"
	var belly:bool=p.current_slot()=="cannon"
	var index:int=1 if p.current_slot()=="sniper" else 0
	var value:String="%.1fs" % p.saber_cooldown if melee and p.saber_cooldown>0 else ("READY" if melee else "%02d / %d" % [s.ammo[index],8 if index==1 else 18])
	if not melee and s.reload_left>0:value="装填 %.1fs" % s.reload_left
	if belly:value="蓄力中" if p.cannon_hold_ratio()>0 and not p.cannon_charging() else s.cannon_status()
	_weapon_cell(h,cell,("按住 / 松开 " if belly else "")+h._key("fire_primary"),"光束军刀" if melee else p.weapon_name(),value,p.cannon_hold_ratio() if belly else -1,AMBER if belly else WHITE,15 if belly else 18)
	cell.position.x+=width+24
	var status:String="%02d%% · %d/6" % [int(s.energy*100),6-s.lost.size()]
	if s.state==s.State.RETURNING:status="回收 %.1fs" % (3.0-s.return_age)
	if s.repair_left>0:status="CD %.1fs" % s.repair_left
	_weapon_cell(h,cell,h._key("fire_missile")+" 展开 / 回收","浮游炮",status,s.energy,AMBER if s.repair_left>0 else WHITE,15)
	cell.position=r.position+Vector2(0,58)
	if belly:
		_weapon_cell(h,cell,"蓄力1.7s · 松手发射","蓄力进度","%d%%" % int(p.cannon_hold_ratio()*100),p.cannon_hold_ratio(),AMBER,15)
	else:
		_weapon_cell(h,cell,("短按 / 长按 "+h._key("fire_secondary")) if melee else ("按住 "+h._key("fire_secondary")),"光束战斧" if melee else "精准射击",("%.1fs" % s.axe_cd if s.axe_cd>0 else "挥砍 / 投掷") if melee else ("ON" if s.scope_active() else "READY"),-1,WHITE,15)
	cell.position.x+=width+24
	_weapon_cell(h,cell,h._key("missile_mode")+" 切换","浮游炮模式",s.mode_name(),-1,WHITE,15)
	var cannon_hint:String="%s切换 · 按住%s1.7s松开" % [h._key("switch_weapon"),h._key("fire_primary")]
	if not belly:cannon_hint="腹部炮 %s · " % s.cannon_status()+cannon_hint
	_text(h,r.position+Vector2(0,113),cannon_hint,10,AMBER)
	_text(h,r.position+Vector2(0,132),"%s 切换武器 · %s 换弹 · %s 盾" % [h._key("switch_weapon"),h._key("reload"),h._key("shield")],10,DIM)
	_text(h,r.position+Vector2(0,151),"长按 %s 索敌 / 解除锁定" % h._key("flight_assist"),10,DIM)

static func _weapons(h, r: Rect2) -> void:
	var p = h.player
	if p.thunderbolt_systems!=null:_thunderbolt_weapons(h,r);return
	if p.is_sazabi():_sazabi_weapons(h,r);return
	if p.is_zorin():
		var entries:Array=preload("res://scripts/ui/zorin_hud.gd").rows(p)
		var width:float=(r.size.x-24)*.5
		for i in entries.size():
			var e:Dictionary=entries[i].duplicate()
			if i==2:e.name="六翼浮游炮";e.value="%03d / 200"%p.nu_systems.energy;e.key=InputSetup.hint("F展开/回收 · ","L2 · ")+p.nu_systems.mode_name()
			if i==3:
				var s=p.nu_systems
				var pos:Vector2=r.position+Vector2(width+24,43)
				_text(h,pos,"米诺屏障 · "+e.key,11,WHITE)
				_right(h,Vector2(pos.x+width,pos.y),"%d/3"%s.charges(),16,CYAN)
				var half:float=(width-12)*.5
				_text(h,pos+Vector2(0,19),"冷却 %.1fs"%s.barrier_cd,9,DIM)
				_text(h,pos+Vector2(half+12,19),"充能 "+("等待" if s.barrier_cd>0 and s.charge_remaining()>0 else "%.1fs"%s.charge_remaining()),9,DIM)
				_bar(h,Rect2(pos+Vector2(0,27),Vector2(half,3)),s.cooldown_progress(),CYAN)
				_bar(h,Rect2(pos+Vector2(half+12,27),Vector2(half,3)),s.charge_progress(),WHITE)
				continue
			_weapon_cell(h,Rect2(r.position+Vector2((i%2)*(width+24),(i/2)*43),Vector2(width,36)),e.key,e.name,e.value,e.get("bar",-1.0),CYAN)
		_text(h,r.position+Vector2(0,151),"X 切换 · Alt 炮模式 · 武器命中回满气槽",10,DIM)
		return
	var width := (r.size.x - 24) * 0.5
	var cell := Rect2(r.position, Vector2(width, 36))
	var slot: String = p.current_slot()
	var primary := "肩甲四炮" if p.profile.id == SuitProfile.Id.NEUE_ZIEL else ("MEGA光束炮" if p.profile.cannon_only else "光束步枪")
	var value := "%02d / %d" % [p.rifle_mag, p.rifle_count]
	var ratio: float = p.mag_ratio()
	var col := WHITE
	if p.profile.cannon_only:
		value = "%.1fs" % p.cannon_cd_left if p.cannon_cd_left>0 else ("冷却" if p.rifle_reloading else "READY")
		ratio = -1.0
	if slot == "cannon":
		primary = "腹部蓄力炮"
		value = "%.1fs" % p.cannon_cd_left if p.cannon_cd_left>0 else "READY"
		ratio = -1.0
	elif slot == "wire":
		primary = "线控机械臂"
		value = "展开" if is_instance_valid(p.active_wire_arms) else ("%.1fs" % p.wire_cd_left if p.wire_cd_left>0 else "READY")
		ratio = -1.0
	elif slot == "bazooka":
		primary = "双火箭筒"
		value = "装填 %.1fs" % p.bazooka_reload_left if p.bazooka_reload_left > 0 else "%02d / 16" % p.bazooka_mag
		ratio = float(p.bazooka_mag) / 16.0
		if p.is_nu():
			primary = "火箭筒"
			value = p.nu_systems.bazooka_status()
			ratio = float(p.nu_systems.bazooka_mag) / 4.0
	elif slot == "ram":
		primary = "主动冲撞"
		value = ("直接开炮" if p.active_grapple.attached else "冲撞中") if is_instance_valid(p.active_grapple) else ("%.1fs" % p.grapple_cd if p.grapple_cd > 0 else "1.3km")
		ratio = -1.0
	elif slot == "saber":
		primary = "光束军刀"
		value = "%.1f s" % p.saber_cooldown if p.saber_cooldown > 0 else "READY"
		ratio = -1
	elif slot == "grenade":
		primary = "腕部榴弹"
		value = "装填 %.1fs" % p.grenade_reload_left if p.grenade_reload_left > 0 else "%02d" % p.grenade_count
		ratio = -1
	elif p.has_infinite_rifle_ammo():
		value = "∞"
	elif p.rifle_reloading and not p.profile.cannon_only:
		value = "%d%%" % int(p.reload_progress() * 100)
		primary = "换弹"
		ratio = p.reload_progress()
		col = CYAN
	elif p.rifle_mag <= 0:
		col = RED
	_weapon_cell(h, cell, h._key("fire_primary"), primary, value, ratio, col)
	cell.position.x += width + 24
	var missile_value := "%03d" % p.funnel_count if p.profile.has_missiles else "—"
	var missile_name := "导弹荚舱" if p.profile.id == SuitProfile.Id.GP03D else ("普通导弹" if p.profile.id == SuitProfile.Id.NEUE_ZIEL else "浮游导弹")
	var missile_ratio := -1.0
	if p.funnel_reload_left > 0 and p.profile.has_missiles:
		missile_name = "装填"
		missile_ratio = p.funnel_reload_progress()
		missile_value = "%d%%" % int(missile_ratio * 100)
	if p.profile.id == SuitProfile.Id.GP03D:
		missile_name = "导弹舱"
		missile_value = "%d/16" % (p.funnel_count/108)
		if p.funnel_reload_left>0:
			missile_value += " · %.0fs" % ceilf(p.funnel_reload_left)
	if p.is_regz():
		missile_name = p.regz_weapons.mode_name()
		missile_value = "%03d%%" % int(p.regz_weapons.charge/2.5*100) if p.regz_weapons.irradiation else ("LOCK" if is_instance_valid(p.regz_weapons.selected) else "右键瞄准")
		missile_ratio = p.regz_weapons.charge/2.5 if p.regz_weapons.irradiation else -1.0
		if p.regz_weapons.irradiation and p.profile.form != 1:
			missile_value = "仅巡航"
			missile_ratio = -1.0
	if p.is_nu():
		missile_name = "浮游炮"
		missile_value = p.nu_systems.status_text()
		missile_ratio = p.nu_systems.energy/100.0
	_weapon_cell(h, cell, h._key("fire_secondary" if p.is_regz() else "fire_missile"), missile_name, missile_value, missile_ratio, WHITE, 13 if p.is_regz() and p.regz_weapons.irradiation else 18)
	cell.position = r.position + Vector2(0, 58)
	var gun_name := ("双火箭筒" if p.profile.id == SuitProfile.Id.GP03S else "火箭筒") if p.profile.id in [SuitProfile.Id.GP03D,SuitProfile.Id.GP03S] else ("肩甲四炮" if p.profile.id == SuitProfile.Id.NEUE_ZIEL else "火神炮")
	var gun_value := ("装填 %.1fs" % p.bazooka_reload_left if p.bazooka_reload_left > 0 else "%02d/16" % p.bazooka_mag) if p.profile.id in [SuitProfile.Id.GP03D,SuitProfile.Id.GP03S] else ("%02d轮" % p.rifle_mag if p.profile.id == SuitProfile.Id.NEUE_ZIEL else ("HOT" if p.vulcan_overheated else ("∞" if p.profile.has_vulcan() else "—")))
	if p.profile.id == SuitProfile.Id.GP03S:
		_weapon_cell(h, cell, h._key("switch_weapon"), "切换武器", p.next_slot_name(), -1)
	else:
		_weapon_cell(h, cell, h._key("fire_gun"), gun_name, gun_value, -1, RED if p.vulcan_overheated else WHITE)
	cell.position.x += width + 24
	_weapon_cell(h, cell, h._key("flares"), "干扰弹", "装填 %.1fs" % p.flare_reload_left if p.flare_reload_left > 0 else "%02d" % p.flare_count, -1, WHITE if p.flare_count > 0 else AMBER)
	# Penelope shares the primary trigger; make the cannon a readable weapon cell.
	if p.profile.id == SuitProfile.Id.PENELOPE and p.cannon_available():
		var cannon_value := "READY"
		var cannon_col := WHITE
		if p.cannon_cd_left > 0.0:
			cannon_value = "冷却 %.1fs" % p.cannon_cd_left
			cannon_col = DIM
		elif p.rifle_reloading:
			cannon_value = "换弹 %.1fs" % p.reload_timer
			cannon_col = AMBER
		elif not p.cannon_ready():
			cannon_value = "需满弹匣"
			cannon_col = AMBER
		elif p.cannon_charging():
			cannon_value = "松手发射"
			cannon_col = CYAN
		var cannon_cell := Rect2(r.position+Vector2(width+24,104),Vector2(width,36))
		_weapon_cell(h,cannon_cell,"长按 %s · 1.7s" % h._key("fire_primary"),"光束大炮",cannon_value,-1,cannon_col,13)
	var secondary: String = p.missile_mode_name()
	var extra := ""
	if p.profile.full_salvo_capacity > 1:
		extra = " · " + p.full_salvo_charge_status()
	elif p.full_salvo_cooldown > 0:
		extra = " %.0fs" % ceilf(p.full_salvo_cooldown)
	elif p.shield_up:
		extra = " · 盾 %.1fs" % p.shield_timer
	elif p.profile.id != SuitProfile.Id.PENELOPE and p.cannon_available() and p.cannon_cd_left > 0:
		extra = " · 炮 %.0fs" % ceilf(p.cannon_cd_left)
	elif p.profile.id != SuitProfile.Id.PENELOPE and p.cannon_available():
		extra = (" · X切蓄力炮" if p.profile.id == SuitProfile.Id.NEUE_ZIEL and slot != "cannon" else " · 长按蓄力") if p.cannon_ready() else " · 炮未就绪"
	if p.is_regz(): extra = " · 仅巡航可用" if p.regz_weapons.irradiation and p.profile.form != 1 else ((" · 冷却 %.0fs" % ceilf(p.cannon_cd_left)) if p.cannon_cd_left > 0.0 else " · 左键发射")
	_text(h, r.position + Vector2(0, 113), "%s%s" % [secondary, extra], 11, WHITE)
	_text(h, r.position + Vector2(0, 130), h._key("fire_secondary") + (" 精准瞄准" if p.is_nu() else ""), 10, DIM)
	if p.is_nu():
		for i in 6:
			var fin = p.nu_systems.fins[i]
			_bar(h,Rect2(r.position+Vector2(width+24+i*(width/6.0),43),Vector2(width/6.0-5,3)),fin.hp/20.0,WHITE if fin.alive else RED)
	var controls := "%s 切换" % h._key("switch_weapon")
	if not p.has_infinite_rifle_ammo() and not p.profile.cannon_only:
		controls += " · %s 换弹" % h._key("reload")
	controls += " · %s 盾" % h._key("shield")
	if p.is_nu():controls += " %.0fs"%ceilf(p.nu_systems.equipment_cd) if p.nu_systems.equipment_cd>0 else " · 长按R骗锁"
	_text(h, r.position + Vector2(0, 151), controls, 10, DIM)

# Heading-up radar uses the same live factions, world scale and mission gates as the cockpit.
static func radar_contact(relative: Vector3, forward: Vector3, radius: float, radar_range: float) -> Dictionary:
	var flat_fwd := Vector3(forward.x, 0, forward.z)
	if flat_fwd.length_squared() < 0.0001:
		flat_fwd = Vector3.FORWARD
	flat_fwd = flat_fwd.normalized()
	var flat_right := flat_fwd.cross(Vector3.UP).normalized()
	var offset := Vector2(relative.dot(flat_right), -relative.dot(flat_fwd)) * radius / radar_range
	var outside := offset.length_squared() > radius * radius
	if outside:
		offset = offset.normalized() * radius
	return {"offset": offset, "outside": outside}

static func _radar(h, r: Rect2) -> void:
	var center := r.get_center()
	var radius := r.size.x * 0.5
	var radar_range: float = h.RADAR_RANGE
	var forward: Vector3 = h.player.forward()
	var origin: Vector3 = h.player.global_position
	h.draw_circle(center, radius, Color(INK, 0.68), true, -1, true)
	_arc(h, center, radius, 0, TAU, DIM)
	for fraction: float in [0.33, 0.66]:
		_arc(h, center, radius * fraction, 0, TAU, FAINT)
	_line(h, center - Vector2(radius, 0), center + Vector2(radius, 0), FAINT)
	_line(h, center - Vector2(0, radius), center + Vector2(0, radius), FAINT)
	# Triangle = self, circles = allies, squares = enemies; color adds emphasis.
	for unit: Node3D in Game.live_allies_of(h.player):
		var contact := radar_contact(unit.global_position - origin, forward, radius, radar_range)
		var at: Vector2 = center + contact["offset"]
		var body := unit as FlightBody
		var dimmed: bool = contact["outside"] or (body != null and body.is_unlockable())
		h.draw_circle(at, 4, INK)
		h.draw_circle(at, 2.7, FAINT if dimmed else CYAN)
	for unit: Node3D in Game.live_hostiles_of(h.player):
		var contact := radar_contact(unit.global_position - origin, forward, radius, radar_range)
		var at: Vector2 = center + contact["offset"]
		if contact["outside"]:
			h.draw_circle(at, 2.4, FAINT)
			continue
		var body := unit as FlightBody
		var hidden := body != null and body.is_unlockable()
		var selected: bool = h.lock != null and h.lock.target == unit
		var col := FAINT if hidden else (RED if selected else AMBER)
		h.draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), INK)
		h.draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), col, selected, -1.0 if selected else 1.2)
		if selected:
			_arc(h, at, 7.5, 0, TAU, col, 1.4)
	# Mission beacons retain the existing per-mission visibility rules.
	for beacon: Dictionary in h.BEACONS:
		var group := str(beacon["group"])
		if not h._beacon_shown(group):
			continue
		var tag = h._beacon_tag(group)
		if tag == null:
			continue
		var contact := radar_contact(tag.global_position - origin, forward, radius, radar_range)
		var at: Vector2 = center + contact["offset"]
		var col: Color = beacon["color"]
		for i in range(4):
			_line(h, at + Vector2.UP.rotated(i * PI * 0.5) * 4.5, at + Vector2.UP.rotated((i + 1) * PI * 0.5) * 4.5, col)
	h.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -6), center + Vector2(-4, 5), center + Vector2(4, 5)]), WHITE)
	_center(h, center + Vector2(0, radius - 8), "%.1f km" % (radar_range / 1000.0), 10, DIM)

static func _status(h, v: Vector2) -> void:
	var p = h.player
	var st: Dictionary = p.assist_state()
	var detail_x := 300.0 if h.magnifier_active() else 72.0
	var status := "%s · 辅助%s" % [h.assist_hint(InputSetup.using_gamepad), "开启" if bool(st.get("on", false)) else "关闭"]
	if p.is_nu():status="辅助驾驶 · 长按G索敌/解除"
	if p.is_sazabi():status="辅助驾驶 · 长按 %s 索敌 / 解除" % h._key("flight_assist")
	if bool(st.get("collision_guard", false)):
		status = "防撞地 · 自动拉升" if st.get("collision_kind", "") == "ground" else "防撞楼 · 自动避让"
	elif bool(st.get("auto_pull", false)):
		status = "接管拉升"
	elif bool(st.get("reverse", false)):
		status = "反向巡航"
	_text(h, Vector2(72, 64), status, 11, AMBER if bool(st.get("collision_guard", false)) else (RED if bool(st.get("auto_pull", false)) else DIM))
	if h._system_event_timer > 0 and h._system_event_seen != "" and h._system_event_seen != status:
		var event: String = h._system_event_seen
		var danger := event.contains("拉起") or event.contains("接管") or event.contains("地形警告")
		_text(h, Vector2(72, 85), event, 12, RED if danger else WHITE)
	var selected = p.selected_threat()
	if selected != null:
		_text(h, Vector2(detail_x, 106), "来袭 %.1fs" % p.selected_threat_tti(), 13, RED)
	elif p.auto_intercept_active():
		_text(h, Vector2(detail_x, 106), "自动拦截", 12, CYAN)
	if p.has_pedal():
		_text(h, Vector2(detail_x, 127), "踏板 · %s 脱离" % h._key("shield"), 11, DIM)
	if Game.match_mode == Game.MatchMode.TRAINING:
		_center(h, Vector2(v.x * 0.5, 102), "靶机 %d / %d" % [Game.training_targets_down, Game.training_targets_total], 12, DIM)
	elif Game.match_mode == Game.MatchMode.CHALLENGE and Game.active_challenge != null and not h.chapter_three_active():
		_center(h, Vector2(v.x * 0.5, 102), h.challenge_progress_text(str(Game.active_challenge.title), Game.challenge_wave, ChallengeScript.wave_count(Game.active_challenge), Game.challenge_wave_remaining), 12, DIM)
	if p.profile.form_count > 1:
		_text(h, Vector2(detail_x, 148), "外壳剥离中" if p.in_transform() else p.profile.form_name(), 11, RED if p.in_transform() else DIM)
	var immunity: float = p.unlockable_seconds_left()
	if immunity > 0:
		_text(h, Vector2(detail_x, 169), "无法被锁定 %.1fs" % immunity, 11, CYAN)

static func _contacts(h, v: Vector2) -> void:
	var contacts: Array = h.player.contacts()
	var target = h.lock.target if h.lock != null else null
	var shown := contact_indices(contacts, target)
	var x := v.x - 320.0
	var y := 64.0
	_right(h, Vector2(v.x - 72, y), "CONTACTS  %02d" % contacts.size(), 10, DIM)
	for i: int in shown:
		var body = contacts[i]
		if not is_instance_valid(body):
			continue
		y += 24
		var col := WHITE if body == target else DIM
		_text(h, Vector2(x, y), "%02d  %s" % [i + 1, body.display_name], 11, col)
		var dist: float = h.player.global_position.distance_to(body.global_position)
		var scanned: bool = h.lock != null and dist <= h.lock.seeker_range
		_right(h, Vector2(v.x - 72, y), "%.1fk%s" % [dist / 1000.0, " ○" if not scanned else ""], 11, col)
	if contacts.size() > shown.size():
		_right(h, Vector2(v.x - 72, y + 22), "+%d · %s" % [contacts.size() - shown.size(), InputSetup.hint("Tab", "十字键 ↑")], 10, DIM)

static func _target(h, u: float) -> void:
	if h.lock == null or not is_instance_valid(h.lock.target) or not h.lock.target.alive:
		return
	var target = h.lock.target
	if not h._visible(target.global_position):
		var cam = h.camera
		var local: Vector3 = cam.global_basis.inverse() * (target.global_position - cam.global_position)
		var dir := Vector2(local.x, -local.y).normalized()
		if local.z > 0:
			dir = -dir
		if dir.length_squared() < 0.01:
			dir = Vector2.DOWN
		var view: Vector2 = h.size / u
		var center := view * 0.5
		var at := center + dir * minf(view.x * 0.36, view.y * 0.32)
		var side := Vector2(-dir.y, dir.x)
		_line(h, at + dir * 7, at - dir * 5 + side * 5)
		_line(h, at + dir * 7, at - dir * 5 - side * 5)
		_center(h, at + Vector2(0, 22), "%.1f km" % (h.lock.range_to_target() / 1000.0), 11, DIM)
		return
	var pos: Vector2 = h._project(target.global_position) / u
	h._magnifier_ui_rect(Rect2(pos + Vector2(-70, -56), Vector2(140, 185)), true)
	var col := WHITE if h.lock.locked else AMBER
	_arc(h, pos, 29, 0, TAU, col)
	_line(h, pos + Vector2(-38, -8), pos + Vector2(-38, 8), col)
	_line(h, pos + Vector2(38, -8), pos + Vector2(38, 8), col)
	_center(h, pos + Vector2(0, -42), target.display_name, 12, col)
	_center(h, pos + Vector2(0, 78), "%.1f km" % (h.lock.range_to_target() / 1000.0), 13, WHITE)
	h._draw_target_vitals(pos,39.0,96.0,WHITE,CYAN,u)
	var board = target.pedal_owner()
	if board != null:
		_center(h, pos + Vector2(0, 113), "踏板 %d%%" % int(board.ratio() * 100), 10, DIM)
	if not h.lock.locked:
		var why: String = h.lock.block_reason()
		_center(h, pos + Vector2(0, 95), why if why != "" else h.lock.tier_name(), 11, AMBER)
	var lead: Vector3 = h.lock.gun_lead_point(SuitProfile.vulcan_speed())
	if h.player.rifle_count <= 0 and h.lock.tier() == LockOnSystem.Tier.LOCK and h._visible(lead):
		var lead_at: Vector2 = h._project(lead) / u
		h._magnifier_ui_rect(Rect2(lead_at - Vector2.ONE * 8, Vector2.ONE * 16), true)
		_arc(h, lead_at, 7, 0, TAU, DIM)

static func _rifle_feedback(h, u: float) -> void:
	var solution: Dictionary = h.player.rifle_hud_solution()
	if solution.is_empty():
		return
	var raw: Vector3 = solution["raw_point"]
	# On a pad, the body-forward firing reference can differ from screen center.
	if (InputSetup.using_gamepad or not h.player.cursor_seen) and h._visible(raw):
		var raw_at: Vector2 = h._project(raw) / u
		h._magnifier_ui_rect(Rect2(raw_at - Vector2.ONE * 6, Vector2.ONE * 12), true)
		_arc(h, raw_at, 4, 0, TAU, WHITE)
	if not bool(solution["valid"]) or not h._visible(solution["prediction"]):
		return
	var at: Vector2 = h._project(solution["prediction"]) / u
	var active := float(solution["weight"]) > 0.0
	var blocked := bool(solution["blocked"])
	var col := AMBER if blocked else (CYAN if active else DIM)
	h._magnifier_ui_rect(Rect2(at - Vector2.ONE * 9, Vector2.ONE * 18), true)
	_arc(h, at, 5, 0, TAU, col)
	if blocked:
		_line(h, at + Vector2(-3, -3), at + Vector2(3, 3), col)
		_line(h, at + Vector2(-3, 3), at + Vector2(3, -3), col)
	elif active:
		h.draw_circle(at, 1.8, col)
		_arc(h, at, 8, PI * 0.15, PI * (0.15 + 0.7 * float(solution["weight"])), col, 1.4)
		var actual: Vector3 = solution["aim_point"]
		if h._visible(actual):
			var actual_at: Vector2 = h._project(actual) / u
			if actual_at.distance_to(at) > 9.0:
				h._magnifier_ui_rect(Rect2(actual_at - Vector2.ONE * 5, Vector2.ONE * 10), true)
				_line(h, actual_at + Vector2(-3, 0), actual_at + Vector2(3, 0), WHITE)
				_line(h, actual_at + Vector2(0, -3), actual_at + Vector2(0, 3), WHITE)
				var start := at + (actual_at - at).normalized() * 9
				var tip := at + (actual_at - at).normalized() * minf(actual_at.distance_to(at) - 4, 22)
				h._magnifier_ui_rect(Rect2(start, tip - start).abs().grow(2), true)
				_line(h, start, tip, DIM)

static func _notices(h, v: Vector2) -> void:
	var notices: Array = h._notices
	var count := mini(notices.size(), 2)
	for i in count:
		var n: Dictionary = notices[notices.size() - count + i]
		var a := clampf(float(n["t"]) / maxf(float(n["life"]), 0.01), 0, 1)
		_center(h, Vector2(v.x * 0.5, v.y * 0.5 + 190 + i * 21), str(n["text"]), 12, Color(WHITE, a))

