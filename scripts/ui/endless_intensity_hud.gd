extends RefCounted
## A compact time-driven tier table, shared by both combat views in ENDLESS only.
const Rules := preload("res://scripts/data/endless_script.gd")
const Instrument := preload("res://scripts/ui/third_person_hud.gd")
static var _panel_style: StyleBoxFlat

static func active(h) -> bool:
	return Game.is_endless() and Game.phase == Game.Phase.FIGHT and not h.cockpit_only \
		and is_instance_valid(h.player) and h.player.alive

static func readout(elapsed: float) -> Dictionary:
	var seconds := maxf(elapsed, 0.0)
	var step := Rules.enemy_step(seconds)
	var within := seconds - step * Rules.ENEMY_STEP_SECS
	var rows: Array[Dictionary] = []
	# Sliding window retains the previous tier and never caps the actual level.
	for i in range(maxi(step - 1, 0), maxi(step - 1, 0) + 5):
		rows.append({"level": i + 1, "damage": Rules.enemy_damage_mult(i * Rules.ENEMY_STEP_SECS),
			"current": i == step, "passed": i < step})
	return {"level": step + 1, "damage": Rules.enemy_damage_mult(seconds),
		"elapsed": clock(seconds), "next_in": clock(ceilf(Rules.ENEMY_STEP_SECS - within)),
		"progress": within / Rules.ENEMY_STEP_SECS, "rows": rows}

static func clock(seconds: float) -> String:
	var whole := int(maxf(seconds, 0.0))
	return "%02d:%02d" % [whole / 60, whole % 60]

static func panel_rect(view: Vector2) -> Rect2:
	var g := Instrument.layout(view)
	var v: Vector2 = g["view"]
	return Rect2(v.x * 0.5 - 232, 108, 464, 112)

static func draw(h) -> void:
	var g := Instrument.layout(h.size)
	var scale_factor: float = g["scale"]
	var r := panel_rect(h.size)
	var d := readout(Game.endless_elapsed)
	var accent := Instrument.AMBER if d["progress"] >= 0.94 else Instrument.CYAN
	h.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * scale_factor)
	# Register the whole panel for magnifier overlap, including its background.
	h._magnifier_ui_rect(r, true)
	h.draw_style_box(_background(), r)
	Instrument._text(h, r.position + Vector2(12, 20), "敌方强度  LV.%02d" % d["level"], 13, Instrument.WHITE)
	Instrument._right(h, Vector2(r.end.x - 12, r.position.y + 20), "存活  %s" % d["elapsed"], 16, Instrument.WHITE)
	var cell_w := (r.size.x - 24 - 16) / 5
	for i in 5:
		var row: Dictionary = d["rows"][i]
		var cell := Rect2(r.position + Vector2(12 + i * (cell_w + 4), 32), Vector2(cell_w, 37))
		var col := accent if row["current"] else Instrument.DIM
		if row["passed"]: col = Instrument.FAINT
		if row["current"]:
			h.draw_rect(cell, Color(accent, 0.10))
		Instrument._line(h, cell.position, Vector2(cell.end.x, cell.position.y), col, 1.5 if row["current"] else 1.0)
		Instrument._center(h, Vector2(cell.get_center().x, cell.position.y + 14), "LV.%02d" % row["level"], 10, col)
		Instrument._center(h, Vector2(cell.get_center().x, cell.position.y + 30), "×%.2f" % row["damage"], 12, col)
	var bar := Rect2(r.position + Vector2(12, 78), Vector2(r.size.x - 24, 2))
	h.draw_rect(bar, Instrument.FAINT)
	h.draw_rect(Rect2(bar.position, Vector2(bar.size.x * d["progress"], 2)), accent)
	Instrument._text(h, r.position + Vector2(12, 101), "第 %d 波 · 剩余 %d/%d" % [Game.endless_wave, Game.endless_wave_remaining, Game.endless_wave_total], 11, Instrument.DIM)
	Instrument._right(h, Vector2(r.end.x - 12, r.position.y + 101), "下次激化  %s" % d["next_in"], 11, accent)
	h.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

static func _background() -> StyleBoxFlat:
	if _panel_style != null:
		return _panel_style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.027, 0.045, 0.68)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	_panel_style = style
	return style
