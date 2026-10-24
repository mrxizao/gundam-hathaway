extends "res://scripts/ui/hud.gd"
## Read-only instrument surface. No gameplay processing, audio or nested HUDs.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	radar_frame_visible = false
	_state_image = TextureRect.new()
	_state_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_state_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_state_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform vec4 ink: source_color = vec4(0.64,0.60,0.83,1.0);
uniform bool mask_caption = false;
void fragment() {
	vec3 source = texture(TEXTURE,UV).rgb;
	float l = dot(source,vec3(0.2126,0.7152,0.0722));
	// Preserve source line contrast; edge extraction loses details after mipmapping.
	float a = smoothstep(0.25,0.68,l)*texture(TEXTURE,UV).a;
	if(mask_caption && UV.x<0.24 && UV.y<0.26) { a=0.0; }
	if(UV.x>0.987) { a=0.0; }
	COLOR=vec4(ink.rgb,a*ink.a);
}"""
	_state_material = ShaderMaterial.new()
	_state_material.shader = shader
	_state_image.material = _state_material
	add_child(_state_image)
	_state_image.hide()
	_state_overlay = Control.new()
	_state_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_state_overlay.draw.connect(_draw_state_annotations)
	add_child(_state_overlay)
	_state_overlay.hide()
	set_process(false)

func _process(_delta: float) -> void:
	pass

var modules: Dictionary = {}
var _state_overlay: Control
var _state_image: TextureRect
var _state_material: ShaderMaterial
var _state_textures: Dictionary = {}
const STATE_FILES := ["xi","penelope","arizeus","core_nu","","cruise"]
const STATE_TEXTURES := {
	0:preload("res://assets/cockpit_states/xi.res"),
	1:preload("res://assets/cockpit_states/penelope.res"),
	2:preload("res://assets/cockpit_states/arizeus.res"),
	3:preload("res://assets/cockpit_states/core_nu.res"),
	5:preload("res://assets/cockpit_states/cruise.res"),
	6:preload("res://assets/models/gp03d_v2/state.res"),
	7:preload("res://assets/models/neue_ziel/state.res"),
	8:preload("res://data/sazabi_models/state.res")
}
const INK := Color(0.48,0.44,0.72)
const FAINT := Color(0.24,0.23,0.4)

func _draw() -> void:
	if modules.is_empty() or not is_instance_valid(player): return
	if player.profile.id == SuitProfile.Id.NEUE_ZIEL:
		_draw_neue_instruments()
		return
	var rect: Rect2 = modules["center"]
	for key in ["center","left","right"]:
		var r: Rect2 = modules[key]
		draw_rect(r,Color(0.035,0.032,0.105))
		draw_rect(r.grow(-3),FAINT,false,1.0)
	var mode: int = Settings.effective_dash_screen()
	_state_image.visible = mode == Settings.DASH_SCREEN_SILHOUETTE
	_state_overlay.visible = _state_image.visible
	_state_overlay.size = size
	_state_overlay.queue_redraw()
	if mode == Settings.DASH_SCREEN_SILHOUETTE:
		_draw_supplied_state(rect)
	elif mode == Settings.DASH_SCREEN_CONTOUR:
		_main_circuits(rect)
		_draw_screen_contour(rect.position+rect.size*Vector2(0.5,0.51),rect.size.y*0.28)
	else:
		_main_circuits(rect)
		var k := 0.68
		var target := rect.position+rect.size*Vector2(0.5,0.48)
		_open_radar_frame(target,RADAR_RADIUS*k)
		draw_set_transform(target-radar_center(size)*k,0,Vector2(k,k))
		_draw_radar()
		draw_set_transform(Vector2.ZERO)
	for key in ["left","right"]:
		var side: Rect2 = modules[key]
		var lay := side_regions(side,key == "right")
		_side_ring(lay["dial_center"],float(lay["dial_radius"]),key == "right")
		_side_circuit(side)
		_side_plate(side,key == "right")
		_draw_side_readout(side,lay,key == "right")
		_side_mechanics(side,lay,key == "right")
	_screen_edge_details(rect)

static func side_regions(r: Rect2, mirrored := false) -> Dictionary:
	return {"dial_center":r.position+r.size*Vector2(0.44 if mirrored else 0.56,0.43),"dial_radius":minf(r.size.x*0.24,r.size.y*0.225),"bar":Rect2(r.position+r.size*Vector2(0.09,0.89),r.size*Vector2(0.82,0.055)),"mode_y":r.position.y+r.size.y*0.81,"title_y":r.position.y+20.0,"decoration_bottom":r.position.y+r.size.y*0.73}

func _draw_side_readout(r: Rect2, lay: Dictionary, roll: bool) -> void:
	var value: float = clampf(player.fm.throttle,0,1)
	var col := HUD
	var mode := "CRUISE"
	var angle := dash_dial_angle(value)
	var text := "%d%%" % int(value*100)
	var ticks := dash_thrust_ticks()
	if roll:
		angle = float(attitude_readout(player.global_transform.basis)["horizon_roll_deg"])
		value = clampf(absf(angle)/DASH_ROLL_RANGE,0,1)
		text = "%+.1f°" % angle
		mode = "LEVEL" if absf(angle)<0.5 else ("R" if angle>0 else "L")
		col = NEUTRAL
		ticks = dash_roll_ticks()
	elif player.fm.super_boost:
		mode = "SUPER"
		col = IFIELD
	elif player.fm.boosting:
		mode = "BOOST"
		col = WARN
	elif player.has_dash_limit() and player.dash_cd>0:
		mode = "DASH CD"
	_side_header(r,lay["title_y"],"ROLL" if roll else "THRUST",text)
	_side_dial(lay["dial_center"],lay["dial_radius"],ticks,angle,col,roll)
	_side_mode(r,lay["mode_y"],mode,col)
	var bar: Rect2 = lay["bar"]
	draw_rect(bar.grow(2),Color(0.018,0.022,0.04))
	_draw_dash_pips(bar,value,col,roll)
	# An etched socket frames the existing ten cells without crossing the mode row.
	draw_line(bar.position-Vector2(0,2),Vector2(bar.end.x,bar.position.y-2),FAINT,0.8,true)
	draw_line(Vector2(bar.position.x,bar.end.y+2),bar.end+Vector2(0,2),Color(0.12,0.11,0.21),0.8,true)
	for side: float in [-1.0,1.0]:
		var x := bar.get_center().x+side*(bar.size.x/2+3)
		draw_polyline(PackedVector2Array([Vector2(x-side*3,bar.position.y-2),Vector2(x,bar.position.y-2),Vector2(x,bar.end.y+2),Vector2(x-side*3,bar.end.y+2)]),INK,0.8,true)

func _side_header(r: Rect2, baseline: float, title: String, value: String) -> void:
	var a := r.position+Vector2(10,6)
	var b := Vector2(r.end.x-10,r.position.y+22)
	var points := PackedVector2Array([a+Vector2(3,0),Vector2(b.x,a.y),b-Vector2(3,0),Vector2(a.x,b.y)])
	draw_colored_polygon(points,Color(0.06,0.055,0.13,0.8))
	draw_line(Vector2(a.x,b.y),Vector2(a.x+48,b.y),FAINT,0.7,true)
	draw_line(Vector2(b.x-52,b.y),b,FAINT,0.7,true)
	_text(Vector2(r.position.x+15,baseline-1),title,9,Color(0.65,0.61,0.80))
	_text_right(Vector2(r.end.x-15,baseline),value,12,NEUTRAL)

func _side_mode(r: Rect2, baseline: float, word: String, col: Color) -> void:
	var width := maxf(44,_font.get_string_size(word,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x+18)
	var c := Vector2(r.get_center().x,baseline-4)
	var points := PackedVector2Array([c+Vector2(-width/2+3,-6),c+Vector2(width/2,-6),c+Vector2(width/2-3,6),c+Vector2(-width/2,6),c+Vector2(-width/2+3,-6)])
	draw_colored_polygon(points,Color(0.055,0.05,0.115))
	draw_polyline(points,FAINT,0.8,true)
	var dot := c+Vector2(-width/2+7,0)
	draw_colored_polygon(PackedVector2Array([dot+Vector2(0,-1.6),dot+Vector2(1.6,0),dot+Vector2(0,1.6),dot+Vector2(-1.6,0)]),Color(col,0.7))
	_text_center(Vector2(c.x+4,baseline-1),word,10,NEUTRAL)

func _side_ring(c: Vector2, radius: float, mirrored: bool) -> void:
	# The anime's rose annulus is a stack of solid sectors with recessed joints.
	var direction := -1.0 if mirrored else 1.0
	draw_arc(c,radius+5,0,TAU,96,Color(0.09,0.075,0.15),13.0,true)
	for band in 3:
		var rr := radius+1.5+band*3.0
		for sector in 6:
			var a := (sector*TAU/6+0.025)*direction
			var b := ((sector+1)*TAU/6-0.025)*direction
			var col := Color(0.29,0.21,0.34) if band==1 else Color(0.39,0.29,0.44)
			draw_arc(c,rr,minf(a,b),maxf(a,b),18,col,2.0,true)
	for rr: float in [radius-1.0,radius+3.0,radius+9.0]:
		draw_arc(c,rr,0,TAU,96,FAINT,0.8,true)
	# A lit upper lip and lower recess give depth without turning the screen into metal.
	draw_arc(c,radius+10,PI,TAU,48,Color(0.57,0.49,0.66),1.0,true)
	draw_arc(c,radius+10,0,PI,48,Color(0.12,0.1,0.22),1.5,true)
	for sector in 6:
		var d := Vector2.from_angle(sector*TAU/6*direction)
		draw_line(c+d*(radius+1),c+d*(radius+9),Color(0.065,0.055,0.12),2.0,true)
		var p := c+d*(radius+6)
		draw_line(p-Vector2(-d.y,d.x)*2,p+Vector2(-d.y,d.x)*2,INK,0.8,true)

	for sector in 6:
		var a := (sector*TAU/6+0.39)*direction
		var radial := Vector2.from_angle(a)
		var tangent := Vector2(-radial.y,radial.x)
		var p := c+radial*(radius+5)
		draw_line(p-tangent*3,p+tangent*3,Color(0.11,0.085,0.18),2.0,true)
		draw_line(p-tangent*2-radial,p+tangent*2-radial,Color(0.43,0.34,0.51),0.7,true)

func _side_dial(c: Vector2, radius: float, ticks: Array, angle: float, col: Color, roll: bool) -> void:
	# Keep calibration away from the central reticle and the live pointer.
	draw_arc(c,radius-2,0,TAU,80,INK,1.0,true)
	draw_arc(c,radius-8,0,TAU,80,FAINT,0.8,true)
	for n in 48:
		var d := Vector2.from_angle(float(n)*TAU/48)
		var length := 4.0 if n%4==0 else 2.0
		draw_line(c+d*(radius-3),c+d*(radius-3-length),INK if n%4==0 else FAINT,0.8,true)
	for deg_v: float in ticks:
		if posmod(int(round(deg_v)),30)!=0: continue
		var d := dash_dial_tip(Vector2.ZERO,1.0,deg_v)
		draw_line(c+d*(radius-11),c+d*(radius-15),INK,1.0,true)
	# Calibrated live arc shares the original dial conversion and range limits.
	var low := float(ticks.front())
	var high := float(ticks.back())
	var a0 := deg_to_rad(low)-PI/2
	var a1 := deg_to_rad(high)-PI/2
	draw_arc(c,radius-10,a0,a1,60,Color(0.20,0.18,0.33),1.0,true)
	var start := 0.0 if roll else low
	var stop := clampf(angle,low,high)
	if absf(stop-start)>0.1:
		var active_start := deg_to_rad(minf(start,stop))-PI/2
		var active_end := deg_to_rad(maxf(start,stop))-PI/2
		draw_arc(c,radius-10,active_start,active_end,48,Color(col,0.55),1.2,true)
	for value: float in [low,0.0,high]:
		var d := dash_dial_tip(Vector2.ZERO,1.0,value)
		draw_line(c+d*(radius-10),c+d*(radius-15),INK,1.0,true)
	for sector in 3:
		var a := sector*TAU/3+0.16
		draw_arc(c,radius*0.46,a,a+1.5,20,FAINT,0.8,true)
	var triangle := PackedVector2Array()
	for n in 4: triangle.append(c+Vector2.from_angle(-PI/2+n*TAU/3)*radius*0.28)
	draw_polyline(triangle,FAINT,0.8,true)
	var nd := dash_dial_tip(Vector2.ZERO,1.0,angle)
	var np := Vector2(-nd.y,nd.x)
	var needle := PackedVector2Array([c+nd*(radius-14),c+np*2.5-nd*3,c-np*2.5-nd*3])
	draw_colored_polygon(needle,Color(0.03,0.035,0.08))
	draw_colored_polygon(needle,Color(col,0.65))
	needle.append(needle[0])
	draw_polyline(needle,col,1.0,true)
	draw_circle(c,3.0,Color(0.03,0.035,0.08))
	draw_arc(c,2.5,0,TAU,20,col,0.8,true)
	draw_circle(c,1.2,col)

func _side_mechanics(r: Rect2, lay: Dictionary, mirrored: bool) -> void:
	var c: Vector2 = lay["dial_center"]
	var radius: float = lay["dial_radius"]
	var sign := -1.0 if mirrored else 1.0
	for angle: float in [-2.3,-0.65,0.75]:
		var a := angle*sign
		var p := c+Vector2.from_angle(a)*(radius+4)
		var tangent := Vector2.from_angle(a+PI/2)
		var outward := Vector2.from_angle(a)
		var points := PackedVector2Array([p+tangent*7+outward*4,p-tangent*7+outward*4,p-tangent*4-outward*3,p-outward*8,p+tangent*4-outward*3])
		var shadow := PackedVector2Array()
		for v: Vector2 in points: shadow.append(v+Vector2(1.5,2))
		draw_colored_polygon(shadow,Color(0.025,0.025,0.06,0.8))
		draw_colored_polygon(points,Color(0.27,0.25,0.39))
		points.append(points[0])
		draw_polyline(points,Color(0.58,0.53,0.76),1.0,true)
		var inset := PackedVector2Array()
		for v: Vector2 in points: inset.append(p+(v-p)*0.65)
		draw_polyline(inset,INK,0.8,true)
		draw_circle(p-outward,1.3,Color(0.055,0.05,0.11))
		# Short retaining tabs attach to the annulus rather than the text footer.
		var tab := p+outward*6
		draw_line(tab-tangent*3,tab+tangent*3,INK,2.0,true)
	# Mirrored bus traces and recessed connector slots live outside the dial.
	for n in 3:
		var y := 0.37+n*0.095
		var x := 0.83 if not mirrored else 0.17
		var slot := r.position+r.size*Vector2(x,y)
		draw_rect(Rect2(slot-Vector2(2.5,4),Vector2(5,8)),Color(0.035,0.035,0.085))
		draw_line(slot-Vector2(0,2),slot+Vector2(0,2),INK,1.0,true)
	for n in 9:
		var x := 0.13+n*0.013
		if mirrored: x=1.0-x
		var p := r.position+r.size*Vector2(x,0.23)
		draw_line(p,p+Vector2(0,4 if n%3==0 else 2),FAINT,0.8,true)

static func state_page_layout(rect: Rect2) -> Dictionary:
	return {"center":rect.position+rect.size*Vector2(0.5,0.53),"radius":minf(rect.size.y*0.30,rect.size.x*0.22)}

func _draw_supplied_state(rect: Rect2) -> void:
	var key: int = 7 if player.profile.id == SuitProfile.Id.NEUE_ZIEL else (6 if player.profile.id == SuitProfile.Id.GP03D else silhouette_key(player.profile.id,player.profile.form))
	if not STATE_TEXTURES.has(key):
		# New suits without supplied artwork use the existing geometric fallback.
		_state_image.hide()
		_state_image.texture = null
		var layout := state_page_layout(rect)
		_draw_screen_silhouette(layout["center"],layout["radius"])
		_status_strip(rect)
		return
	if not _state_textures.has(key):
		_state_textures[key] = STATE_TEXTURES[key]
	var texture: Texture2D = _state_textures[key]
	_state_image.texture = texture
	var area := Rect2(rect.position+rect.size*Vector2(0.22,0.08),rect.size*Vector2(0.56,0.77))
	var factor := minf(area.size.x/texture.get_width(),area.size.y/texture.get_height())
	_state_image.size = texture.get_size()*factor
	_state_image.position = area.get_center()-_state_image.size/2
	_state_material.set_shader_parameter("mask_caption",key in [2,5])
	var color := silhouette_color(clampf(player.hp_ratio(),0,1),player.has_ifield())
	# Preserve damage semantics; normal artwork follows the animation's lavender ink.
	_state_material.set_shader_parameter("ink",Color(0.64,0.60,0.83) if player.hp_ratio()>0.5 else color)
	# Broad, stepped funnel rail is separate from the annotation layer above the image.
	var funnel := [Vector2(0.035,0.35),Vector2(0.14,0.43),Vector2(0.14,0.55),Vector2(0.31,0.69),Vector2(0.37,0.855),Vector2(0.63,0.855),Vector2(0.69,0.69),Vector2(0.86,0.55),Vector2(0.86,0.43),Vector2(0.965,0.35)]
	_rail(rect,funnel,4.0)
	for inset in 2:
		var d := float(inset)*0.012
		_path(rect,[Vector2(0.04+d,0.38),Vector2(0.16+d,0.46),Vector2(0.16+d,0.54),Vector2(0.33+d,0.68),Vector2(0.38+d,0.83-d),Vector2(0.62-d,0.83-d),Vector2(0.67-d,0.68),Vector2(0.84-d,0.54),Vector2(0.84-d,0.46),Vector2(0.96-d,0.38)],FAINT)
	_status_strip(rect)
	for n in 9:
		var x := 0.44+n*0.015
		_path(rect,[Vector2(x,0.88),Vector2(x,0.887 if n%2 else 0.895)],FAINT)

func _draw_state_annotations() -> void:
	if modules.is_empty() or not is_instance_valid(player): return
	if player.profile.id == SuitProfile.Id.NEUE_ZIEL:
		_draw_neue_annotations()
		return
	var r: Rect2 = modules["center"]
	var canvas := _state_overlay
	# Draw above the supplied line art so opaque source pixels cannot bury labels.
	for side: float in [-1.0,1.0]:
		var words := ["HEAD","ARM","LEG"] if side<0 else ["FRAME","DRIVE","SYSTEM"]
		for n in 3:
			var y := 0.18+n*0.22+(0.045 if side>0 else 0.0)
			var center := r.position+r.size*Vector2(0.5+side*(0.28 if n!=1 else 0.23),y)
			var w := 24.0
			var h := 4.5
			var points := PackedVector2Array([center+Vector2(-w+4,-h),center+Vector2(w,-h),center+Vector2(w-4,h),center+Vector2(-w,h),center+Vector2(-w+4,-h)])
			canvas.draw_colored_polygon(points,Color(0.085,0.08,0.18,0.94))
			canvas.draw_polyline(points,INK,0.8,true)
			canvas.draw_line(center+Vector2(-w+6,-h+2),center+Vector2(w-4,-h+2),FAINT,0.8,true)
			canvas.draw_string(_font,center+Vector2(-19,2.8),words[n],HORIZONTAL_ALIGNMENT_CENTER,38,7,Color(0.60,0.56,0.78))
			var elbow := center+Vector2(-side*31,0)
			var target := r.position+r.size*Vector2(0.5+side*(0.07 if n==0 else 0.12),y+0.065)
			canvas.draw_polyline(PackedVector2Array([center-Vector2(side*w,0),elbow,target]),FAINT,0.8,true)
			canvas.draw_circle(target,1.3,INK)
			canvas.draw_line(center+Vector2(-19,8),center+Vector2(-9,8),FAINT,0.8,true)
	for side: float in [-1.0,1.0]:
		for n in 4:
			var p := r.position+r.size*Vector2(0.5+side*(0.20 if n%2==0 else 0.24),0.13+n*0.20)
			canvas.draw_polyline(PackedVector2Array([p+Vector2(-side*5,0),p,p+Vector2(0,5)]),FAINT,1.0,true)
		for n in 7:
			var p := r.position+r.size*Vector2(0.5+side*0.35,0.20+n*0.085)
			canvas.draw_line(p,p+Vector2(side*(5 if n%3==0 else 2),0),FAINT,1.0,true)

func _open_radar_frame(c: Vector2, radius: float) -> void:
	# Four clipped brackets integrate into the angular main display; no circular plate.
	for x: float in [-1.0,1.0]:
		for y: float in [-1.0,1.0]:
			var corner := c+Vector2(x,y)*(radius+3)
			draw_polyline(PackedVector2Array([corner-Vector2(x*11,0),corner-Vector2(x*4,0),corner-Vector2(0,y*4),corner-Vector2(0,y*11)]),INK,1.0,true)
	# Broken inner range arcs keep distance cues without enclosing the radar.
	for fraction: float in [0.33,0.66]:
		for quadrant in 4:
			var angle := quadrant*PI/2+0.22
			draw_arc(c,radius*fraction,angle,angle+0.55,12,FAINT,1.0,true)
	for sign: float in [-1.0,1.0]:
		for fraction: float in [0.33,0.66,1.0]:
			var p := c+Vector2(sign*radius*fraction,0)
			draw_line(p-Vector2(0,2),p+Vector2(0,2),INK,1.0,true)

func _path(rect: Rect2, points: Array, col: Color) -> void:
	var p := PackedVector2Array()
	for v: Vector2 in points: p.append(rect.position+v*rect.size)
	draw_polyline(p,col,1.0,true)

func _rail(r: Rect2, points: Array, width: float) -> void:
	var line := PackedVector2Array()
	for v: Vector2 in points: line.append(r.position+v*r.size)
	draw_polyline(line,Color(0.07,0.065,0.14),width+2.0,true)
	draw_polyline(line,Color(0.29,0.27,0.44),width,true)
	var lip := PackedVector2Array()
	for p: Vector2 in line: lip.append(p-Vector2(0,0.7))
	draw_polyline(lip,INK,0.8,true)

func _main_circuits(r: Rect2) -> void:
	_rail(r,[Vector2(0.08,0.14),Vector2(0.14,0.085),Vector2(0.38,0.085),Vector2(0.45,0.18),Vector2(0.55,0.18),Vector2(0.62,0.085),Vector2(0.86,0.085),Vector2(0.92,0.14)],2.8)
	_rail(r,[Vector2(0.08,0.15),Vector2(0.16,0.42),Vector2(0.25,0.42),Vector2(0.35,0.855),Vector2(0.65,0.855),Vector2(0.75,0.42),Vector2(0.84,0.42),Vector2(0.92,0.15)],3.0)
	for n in 3:
		var d := n*0.012
		_path(r,[Vector2(0.085+d,0.16),Vector2(0.145+d,0.11+d),Vector2(0.375,0.11+d),Vector2(0.44,0.205+d),Vector2(0.56,0.205+d),Vector2(0.625,0.11+d),Vector2(0.855-d,0.11+d),Vector2(0.915-d,0.16)],INK if n==0 else FAINT)
		_path(r,[Vector2(0.10+d,0.18),Vector2(0.19+d,0.49),Vector2(0.36+d,0.83-d),Vector2(0.64-d,0.83-d),Vector2(0.81-d,0.49),Vector2(0.90-d,0.18)],FAINT)
	for side: float in [-1.0,1.0]:
		for n in 8:
			var x := 0.5+side*(0.045+n*0.013)
			_path(r,[Vector2(x,0.067),Vector2(x+side*0.01,0.047)],FAINT)
		var c := r.position+r.size*Vector2(0.5+side*0.28,0.66)
		_cheek(c,r.size.y*0.145,side)
		_ring(c,r.size.y*0.085,false)
		for n in 4:
			_instrument_key(c+Vector2(-side*(8+n*4),-23+n*14),5.5,-side)
		# Static calibration glyphs occupy the shoulders, outside all live radar contacts.
		for row in 2:
			for n in 4:
				var p := r.position+r.size*Vector2(0.5+side*(0.20+n*0.024),0.27+row*0.035)
				draw_polyline(PackedVector2Array([p+Vector2(-1.5,1.5),p+Vector2(0,-1.5),p+Vector2(1.5,1.5)]),FAINT,0.7,true)
		# Peripheral calibration and stepped chevrons leave the radar area open.
		for n in 18:
			var y := 0.28+n*0.024
			var x := 0.5+side*(0.32-(y-0.28)*0.12)
			_path(r,[Vector2(x,y),Vector2(x+side*(0.013 if n%4==0 else 0.006),y)],FAINT)
		for n in 2:
			var x := 0.5+side*(0.31+n*0.015)
			_path(r,[Vector2(x-side*0.012,0.20),Vector2(x,0.22),Vector2(x-side*0.012,0.24)],INK)
		for n in 4:
			var x := 0.5+side*(0.18+n*0.018)
			_path(r,[Vector2(x,0.89),Vector2(x-side*0.01,0.87)],FAINT)
	_status_strip(r)
	if Settings.effective_dash_screen() == Settings.DASH_SCREEN_RADAR:
		for n in 3:
			_instrument_key(r.position+r.size*Vector2(0.45+n*0.05,0.215+(0.015 if n==1 else 0)),6.0,1)
		_path(r,[Vector2(0.43,0.265),Vector2(0.47,0.265),Vector2(0.5,0.285),Vector2(0.53,0.265),Vector2(0.57,0.265)],FAINT)
	# Lower control cluster sits below the radar's range caption.
	for n in 2:
		var d := n*0.013
		_path(r,[Vector2(0.405-d,0.77),Vector2(0.43-d,0.825+d),Vector2(0.57+d,0.825+d),Vector2(0.595+d,0.77)],INK if n==0 else FAINT)
	for n in 3: _instrument_key(r.position+r.size*Vector2(0.45+n*0.05,0.79),5.0,1)
	for n in 7:
		var x := 0.455+n*0.015
		_path(r,[Vector2(x,0.88),Vector2(x,0.886 if n%2 else 0.894)],FAINT)

func _instrument_key(c: Vector2, radius: float, side: float) -> void:
	var points := PackedVector2Array()
	for v: Vector2 in [Vector2(-0.65,-0.7),Vector2(0.55,-0.7),Vector2(0.8,0),Vector2(0.25,0.85),Vector2(-0.8,0.35)]:
		points.append(c+Vector2(v.x*side,v.y)*radius)
	draw_colored_polygon(points,Color(0.28,0.26,0.42))
	points.append(points[0])
	draw_polyline(points,INK,0.8,true)
	var inset := PackedVector2Array()
	for p: Vector2 in points: inset.append(c+(p-c)*0.65)
	draw_polyline(inset,FAINT,0.8,true)
	draw_line(c-Vector2(1,0),c+Vector2(1,0),INK,0.8,true)

func _cheek(c: Vector2, radius: float, side: float) -> void:
	var points := PackedVector2Array()
	for v: Vector2 in [Vector2(-0.8,-0.72),Vector2(-0.35,-1.18),Vector2(0.38,-1.05),Vector2(1.05,0.38),Vector2(0.5,0.92),Vector2(-0.72,0.82),Vector2(-1.04,0.22)]:
		points.append(c+Vector2(v.x*side,v.y)*radius)
	draw_colored_polygon(points,Color(0.085,0.082,0.15))
	for factor: float in [1.0,0.91,0.85]:
		var outline := PackedVector2Array()
		for p: Vector2 in points: outline.append(c+(p-c)*factor)
		outline.append(outline[0])
		draw_polyline(outline,INK if factor==0.91 else FAINT,1.0,true)

func _badge(c: Vector2, radius: float, side: float) -> void:
	var points := PackedVector2Array([c+Vector2(-0.8*side,-0.75)*radius,c+Vector2(0.9*side,-0.4)*radius,c+Vector2(-0.2*side,0.9)*radius,c+Vector2(-0.8*side,-0.75)*radius])
	draw_colored_polygon(points,Color(0.2,0.19,0.32))
	draw_polyline(points,INK,1.0,true)
	draw_circle(c,1.2,FAINT)

func _hex(c: Vector2, radius: float, col: Color) -> void:
	var p := PackedVector2Array()
	for i in 7: p.append(c+Vector2(cos(i*TAU/6),sin(i*TAU/6))*radius)
	draw_polyline(p,col,1.0,true)

func _ring(c: Vector2,radius: float, clamps := true) -> void:
	# Broad rose-grey annulus under fine ticks, rather than seven equal hairlines.
	draw_arc(c,radius+4,0,TAU,96,Color(0.31,0.23,0.36),7.0,true)
	for i in 7:
		draw_arc(c,radius+i*1.35,0,TAU,96,Color(0.51,0.35,0.49,0.8) if i%2==0 else FAINT,1.0,true)
	for a: float in [0.05,2.15,4.25]:
		draw_arc(c,radius+7,a,a+0.72,24,Color(0.5,0.4,0.59),2.0,true)
	if not clamps: return
	for a: float in [0.4,2.5,4.6]:
		var p := c+Vector2.from_angle(a)*(radius+5)
		var tri := PackedVector2Array()
		for i in 4: tri.append(p+Vector2.from_angle(a+i*TAU/3)*7)
		draw_colored_polygon(tri,Color(0.14,0.14,0.25))
		draw_polyline(tri,INK,1.0,true)

func _side_circuit(r: Rect2) -> void:
	for n in 3:
		var d := n*0.02
		_path(r,[Vector2(0.08,0.055+d*0.4),Vector2(0.2,0.055+d*0.4),Vector2(0.28,0.035+d*0.4),Vector2(0.72,0.035+d*0.4),Vector2(0.8,0.055+d*0.4),Vector2(0.92,0.055+d*0.4)],INK if n==1 else FAINT)
		# Lower corners stop above the reserved mode and segment-bar footer.
		_path(r,[Vector2(0.08,0.65+d*0.4),Vector2(0.17,0.65+d*0.4),Vector2(0.24,0.71+d*0.4),Vector2(0.29,0.71+d*0.4)],FAINT)
		_path(r,[Vector2(0.92,0.65+d*0.4),Vector2(0.83,0.65+d*0.4),Vector2(0.76,0.71+d*0.4),Vector2(0.71,0.71+d*0.4)],FAINT)
	# Short broken rails frame the side dial without crossing its text rows.
	for side: float in [-1.0,1.0]:
		for n in 3:
			var x := 0.5+side*(0.39-n*0.02)
			_path(r,[Vector2(x,0.25),Vector2(x-side*0.07,0.32),Vector2(x-side*0.07,0.62),Vector2(x,0.69)],INK if n==1 else FAINT)

func _side_plate(r: Rect2, mirrored: bool) -> void:
	# A fork on the outer side and a cutout jaw on the inner side frame an offset dial.
	var shapes := [
		[Vector2(0.06,0.23),Vector2(0.12,0.18),Vector2(0.20,0.27),Vector2(0.20,0.33),Vector2(0.26,0.37),Vector2(0.26,0.56),Vector2(0.20,0.60),Vector2(0.20,0.67),Vector2(0.12,0.72),Vector2(0.06,0.66)],
		[Vector2(0.21,0.26),Vector2(0.29,0.17),Vector2(0.45,0.17),Vector2(0.40,0.20),Vector2(0.31,0.20),Vector2(0.24,0.28)],
		[Vector2(0.78,0.33),Vector2(0.92,0.28),Vector2(0.94,0.37),Vector2(0.88,0.41),Vector2(0.88,0.55),Vector2(0.94,0.59),Vector2(0.92,0.66),Vector2(0.78,0.61),Vector2(0.81,0.55),Vector2(0.81,0.41)],
		[Vector2(0.79,0.18),Vector2(0.94,0.18),Vector2(0.94,0.25),Vector2(0.87,0.29)],
		[Vector2(0.85,0.61),Vector2(0.94,0.65),Vector2(0.94,0.72),Vector2(0.76,0.72)]
	]
	for shape: Array in shapes:
		var points := PackedVector2Array()
		for v: Vector2 in shape:
			if mirrored: v.x=1-v.x
			points.append(r.position+v*r.size)
		var shadow := PackedVector2Array()
		for p: Vector2 in points: shadow.append(p+Vector2(0,1.5))
		draw_colored_polygon(shadow,Color(0.025,0.023,0.055))
		draw_colored_polygon(points,Color(0.21,0.20,0.32))
		points.append(points[0])
		draw_polyline(points,INK,1.0,true)
		var center := Vector2.ZERO
		for i in points.size()-1: center += points[i]
		center /= points.size()-1
		var inner := PackedVector2Array()
		for p: Vector2 in points: inner.append(center+(p-center)*0.72)
		draw_polyline(inner,Color(0.10,0.095,0.18),1.0,true)
	# Recessed vertical bus and corner fasteners are static panel artwork.
	for n in 2:
		var x := 0.12+n*0.055
		if mirrored: x=1-x
		var slot := Rect2(r.position+r.size*Vector2(x,0.36),Vector2(3,38))
		draw_rect(slot,Color(0.045,0.04,0.095))
		draw_line(slot.position+Vector2(-1,1),slot.position+Vector2(-1,37),FAINT,0.7,true)
		for i in 6:
			var p := slot.position+Vector2(0,3+i*6)
			draw_line(p,p+Vector2(2,0),INK,0.7,true)
	for v: Vector2 in [Vector2(0.12,0.27),Vector2(0.12,0.65),Vector2(0.91,0.34),Vector2(0.91,0.62)]:
		if mirrored: v.x=1-v.x
		var p := r.position+r.size*v
		draw_circle(p,1.7,Color(0.045,0.04,0.095))
		draw_line(p-Vector2(0.8,0),p+Vector2(0.8,0),FAINT,0.7,true)

func _status_strip(r: Rect2) -> void:
	# Two banks of bevel-shaped cells with a central separator, as in both anime pages.
	for side: float in [-1.0,1.0]:
		for n in 7:
			var c := r.position+r.size*Vector2(0.5+side*(0.075+n*0.06),0.94)
			var w := r.size.x*0.023
			var h := r.size.y*0.026
			var points := PackedVector2Array([c+Vector2(-w*0.68,-h),c+Vector2(w*0.68,-h),c+Vector2(w,0),c+Vector2(w*0.68,h),c+Vector2(-w*0.68,h),c+Vector2(-w,0)])
			draw_colored_polygon(points,Color(0.08,0.075,0.14))
			for factor: float in [1.0,0.73]:
				var line := PackedVector2Array()
				for p: Vector2 in points: line.append(c+(p-c)*factor)
				line.append(line[0])
				draw_polyline(line,INK if factor==0.73 else FAINT,1.0,true)
			for i in 3:
				draw_line(c+Vector2(-3+i*2,-1),c+Vector2(-3+i*2,1),FAINT,1.0,true)
		for n in 2:
			var x := 0.5+side*(0.035+n*0.012)
			_path(r,[Vector2(x+side*0.01,0.92),Vector2(x,0.94),Vector2(x+side*0.01,0.96)],INK)

func _screen_edge_details(r: Rect2) -> void:
	for side: float in [-1.0,1.0]:
		var x := 0.5+side*0.45
		for n in 5:
			var c := r.position+r.size*Vector2(x,0.12+n*0.065)
			var points := PackedVector2Array([c+Vector2(-5,-3),c+Vector2(0,-5),c+Vector2(5,-3),c+Vector2(5,3),c+Vector2(0,5),c+Vector2(-5,3)])
			draw_colored_polygon(points,Color(0.13,0.13,0.23))
			points.append(points[0])
			draw_polyline(points,FAINT,1.0,true)
			draw_line(c-Vector2(2,0),c+Vector2(2,0),INK,1.0,true)
			draw_line(c+Vector2(-3,5),c+Vector2(-5,8),FAINT,0.8,true)
		for n in 18:
			var y := 0.055+n*0.017
			var px := x-side*0.035
			_path(r,[Vector2(px,y),Vector2(px-side*(0.012 if n%3==0 else 0.006),y+0.007)],FAINT)




var _neue_mono: SystemFont

func _draw_neue_instruments() -> void:
	var amber := Color("ffb23e")
	var green := Color("74ff9a")
	var rect: Rect2 = modules["center"]
	var mode: int = Settings.effective_dash_screen()
	_state_image.visible = mode == Settings.DASH_SCREEN_SILHOUETTE
	_state_overlay.visible = _state_image.visible
	_state_overlay.size = size
	_state_overlay.queue_redraw()
	for key in ["center","left","right"]:
		var r: Rect2 = modules[key]
		draw_rect(r,Color(0.025,0.045,0.038))
		draw_rect(r.grow(-5),Color(0.25,0.3,0.23),false,2)
		for n in range(0,int(r.size.y),4):
			draw_line(r.position+Vector2(7,n),Vector2(r.end.x-7,r.position.y+n),Color(0.22,0.36,0.28,0.12),1)
	if mode == Settings.DASH_SCREEN_SILHOUETTE:
		_draw_neue_state(rect)
		_state_material.set_shader_parameter("ink",green if player.hp_ratio()>0.5 else silhouette_color(player.hp_ratio(),player.has_ifield()))
	elif mode == Settings.DASH_SCREEN_CONTOUR:
		_draw_screen_contour(rect.get_center(),rect.size.y*0.36)
	else:
		var k := minf(rect.size.y/280.0,rect.size.x/360.0)*0.7
		var center := rect.get_center()
		draw_set_transform(center-radar_center(size)*k,0,Vector2(k,k))
		_draw_radar()
		draw_set_transform(Vector2.ZERO)
	if _neue_mono == null:
		_neue_mono = SystemFont.new()
		_neue_mono.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	var mono := _neue_mono
	var k := rect.size.x/240.0
	var frame := int(Time.get_ticks_msec()*0.012)
	var label := "NZ-002 / SYS"
	draw_string(mono,rect.position+Vector2(10,15)*k,label,HORIZONTAL_ALIGNMENT_LEFT,-1,int(9*k),amber)
	draw_string(mono,rect.position+Vector2(10,rect.size.y/k-7)*k,"T+%02d:%02d" % [frame/720,(frame/12)%60],HORIZONTAL_ALIGNMENT_LEFT,-1,int(8*k),green)
	var warning := player.hp_ratio()<0.25
	draw_circle(rect.end-Vector2(12,11)*k,2*k,Color("ff4433") if warning else green)
	for key in ["left","right"]:
		var r: Rect2 = modules[key]
		var right: bool = key == "right"
		draw_rect(Rect2(r.position+Vector2(8,7)*k,Vector2(r.size.x-16*k,14*k)),Color(0.08,0.12,0.085))
		draw_string(mono,r.position+Vector2(12,17)*k,"PWR / 02" if right else "ARM / 01",HORIZONTAL_ALIGNMENT_LEFT,-1,int(9*k),amber)
		var labels := ["THR", "AP", "ALT"] if right else ["BEAM", "HULL", "SPD"]
		var values := [clampf(player.fm.throttle,0,1),player.hp_ratio(),clampf(player.global_position.y/2000.0,0,1)] if right else [clampf(float(player.rifle_mag)/maxf(1,player.profile.rifle_magazine),0,1),player.hp_ratio(),clampf(player.fm.speed/300.0,0,1)]
		for row in 3:
			var y := r.position.y+(35+row*28)*k
			draw_string(mono,Vector2(r.position.x+12*k,y),labels[row],HORIZONTAL_ALIGNMENT_LEFT,-1,int(8*k),amber)
			draw_string(mono,Vector2(r.end.x-32*k,y),"%02d" % int(values[row]*99),HORIZONTAL_ALIGNMENT_LEFT,-1,int(9*k),green)
			for tick in 10:
				var x := r.position.x+12*k+tick*(r.size.x-24*k)/10
				draw_rect(Rect2(x,y+5*k,(r.size.x-24*k)/10-2*k,5*k),green if tick<int(values[row]*10) else Color(0.07,0.15,0.10))


func _draw_neue_state(rect: Rect2) -> void:
	var tex: Texture2D = STATE_TEXTURES[7]
	_state_image.texture = tex
	var area := Rect2(rect.position+rect.size*Vector2(0.30,0.18),rect.size*Vector2(0.40,0.66))
	var scale_factor := minf(area.size.x/tex.get_width(),area.size.y/tex.get_height())
	_state_image.size = tex.get_size()*scale_factor
	_state_image.position = area.get_center()-_state_image.size/2
	_state_material.set_shader_parameter("mask_caption",false)


func _draw_neue_annotations() -> void:
	var r: Rect2 = modules["center"]
	var amber := Color("ffb23e")
	for side: float in [-1.0,1.0]:
		for n in 3:
			var y := r.position.y+r.size.y*(0.22+n*0.27)
			var x := r.position.x+r.size.x*(0.06 if side<0 else 0.77)
			var label: String = ["SENSOR","ARM","I-FIELD"][n] if side<0 else ["DRIVE","THRUST","HULL"][n]
			_state_overlay.draw_string(_neue_mono if _neue_mono != null else _font,Vector2(x,y),label,HORIZONTAL_ALIGNMENT_LEFT,-1,10,amber)
			_state_overlay.draw_line(Vector2(x,y+4),Vector2(x+r.size.x*0.16,y+4),Color(amber,0.5),1)
