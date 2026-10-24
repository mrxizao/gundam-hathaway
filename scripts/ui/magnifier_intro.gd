extends RefCounted
## Canvas-only startup sweep; no extra viewport, particles or material instances.
const DURATION := 0.36
static func progress(age: float) -> float:
	return clampf(age/DURATION,0.0,1.0)

static func overlay(h, r: Rect2, p: float, triangle: bool, opacity: float = 1.0) -> void:
	if p >= 1.0: return
	var y := r.position.y+r.size.y*p
	var width := r.size.x*(1.0-p) if triangle else r.size.x
	var center := r.get_center().x
	var left := Vector2(center-width*0.5,y)
	var right := Vector2(center+width*0.5,y)
	var alpha := sin(p*PI)*0.65*opacity
	h.draw_line(left,right,Color(0.73,0.81,1.0,alpha),1.5,true)
	h.draw_line(left-Vector2(0,3),right-Vector2(0,3),Color(0.55,0.65,0.90,alpha*0.20),3.0,true)
