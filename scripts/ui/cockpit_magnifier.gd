extends RefCounted
## Inverted panoramic target monitor. Reuses the existing camera and viewport.
static func rect(view: Vector2) -> Rect2:
	var scale := minf(1.0,minf(view.x/1600.0,view.y/900.0))
	var height := 208.0*scale
	var width := height/0.8660254
	return Rect2(Vector2(42,maxf(92,view.y*0.11)),Vector2(width,height))

static func vertices(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position,r.position+Vector2(r.size.x,0),r.position+Vector2(r.size.x*0.5,r.size.y)])

static func corners(h, points: PackedVector2Array, col: Color) -> void:
	for i in 3:
		var a := points[i]
		var b := points[(i+1)%3]
		h.draw_line(a,a.lerp(b,0.27),col,UILayout.LINE_STRUCT,true)
		h.draw_line(a.lerp(b,0.73),b,col,UILayout.LINE_STRUCT,true)

static func draw(h, texture: Texture2D) -> void:
	var r := rect(h.size)
	var intro: float = preload("res://scripts/ui/magnifier_intro.gd").progress(h._mag_intro_age)
	var reveal := smoothstep(0.0,0.32,intro)
	var growth := 0.88+0.12*(1.0-pow(1.0-intro,3.0))
	r = Rect2(r.get_center()-r.size*growth*0.5,r.size*growth)
	var points := vertices(r)
	# Center crop the wide source, preserving its aspect ratio inside this tall monitor.
	var source_aspect := float(texture.get_width())/maxf(texture.get_height(),1)
	var u_span := (r.size.x/r.size.y)/source_aspect
	var uv := PackedVector2Array([Vector2(0.5-u_span*0.5,0),Vector2(0.5+u_span*0.5,0),Vector2(0.5,1)])
	h.draw_polygon(points,PackedColorArray([Color(1,1,1,reveal)]),uv,texture)
	var center := (points[0]+points[1]+points[2])/3.0
	var inset := PackedVector2Array()
	for point: Vector2 in points: inset.append(center+(point-center)*0.94)
	var col := Color(0.68,0.67,0.83,0.78*reveal)
	col = col.lerp(Color(0.80,0.86,1.0,reveal),sin(intro*PI)*0.30)
	corners(h,points,col)
	corners(h,inset,Color(col,0.40))
	# Broken inner triangle echoes the animation without covering the target.
	var inner := PackedVector2Array()
	for point: Vector2 in points: inner.append(center+(point-center)*0.53)
	corners(h,inner,Color(col,0.34))
	preload("res://scripts/ui/magnifier_intro.gd").overlay(h,r,intro,true)
	var distance: float = h.player.global_position.distance_to(h.lock.target.global_position)/1000.0
	h._text_right(Vector2(r.end.x,r.position.y-9),"ZOOM  %.1f km" % distance,11,col)
