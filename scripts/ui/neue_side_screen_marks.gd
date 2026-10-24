extends Control
## Decorative side-display calibration; actual target lock remains on the HUD.
var _label_font := SystemFont.new()

func _ready() -> void:
	_label_font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	mouse_filter = Control.MOUSE_FILTER_IGNORE

var _scan_clock := 0.0
func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_scan_clock += delta
	queue_redraw()

func _draw() -> void:
	var k := minf(size.x/1280.0,size.y/720.0)
	var center := size*0.5
	var ink := Color(1.0,0.70,0.24,0.50)
	var step_time := floorf(_scan_clock*12.0)/12.0
	for side: float in [-1.0,1.0]:
		# Keep each cross outside the opaque cheek triangle (x = +/-439).
		# Inner side-window lane excludes the outer gameplay readout column.
		var sweep := sin(step_time*0.7+side*0.35)*22.0
		var p := center+Vector2(side*465,-12+sweep)*k
		for direction: float in [-1.0,1.0]:
			draw_dashed_line(p+Vector2(direction*8,0)*k,p+Vector2(direction*15,0)*k,ink,1.3*k,6*k,true,true)
			draw_dashed_line(p+Vector2(0,direction*8)*k,p+Vector2(0,direction*48)*k,ink,1.3*k,6*k,true,true)
		# Short staggered registration marks suggest the oblique display plane.
		for n in 3:
			var y := (-85+n*85+sweep)*k
			var x := side*(456+absf(float(n-1))*8)*k
			draw_dashed_line(center+Vector2(x,y),center+Vector2(x+side*12*k,y-6*k),Color(ink,0.42),1.1*k,5*k,true,true)

	# Printed hardware labels are fixed to the console, separate from live CRT ink.
	var mono := _label_font
	for side: float in [-1.0,1.0]:
		var p := Vector2(size.x*0.5+side*320*k,size.y*0.64+137*k)
		draw_rect(Rect2(p-Vector2(43,10)*k,Vector2(86,14)*k),Color(0.025,0.03,0.025))
		draw_string(mono,p-Vector2(37,0)*k,"NAV / BANK A" if side<0 else "PWR / BANK B",HORIZONTAL_ALIGNMENT_LEFT,-1,int(9*k),Color(0.85,0.83,0.72))
