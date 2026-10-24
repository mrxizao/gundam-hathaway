extends RefCounted
## GP03's pale modular instrument rack. All coordinates share the existing safe layout.
static func build(c, modules: Dictionary) -> void:
	var pale := Color(0.58,0.60,0.63)
	var dark := Color(0.045,0.054,0.065)
	var steel := Color(0.26,0.29,0.33)
	var center: Rect2 = modules.center
	# Raised central shroud and its recessed longitudinal grip.
	c._box(Rect2(center.position+Vector2(-12,-19),Vector2(center.size.x+24,10)),16,1,pale)
	c._box(Rect2(center.get_center().x-42,center.position.y-15,84,3),1,10,dark)
	for side in ["left","right"]:
		var r: Rect2 = modules[side]
		# Two small equipment blocks over the lower monitor bank.
		var auxiliary := Rect2(r.position+Vector2(12,-47),Vector2(r.size.x-24,29))
		c._box(auxiliary.grow(5),15,-3,pale)
		c._box(auxiliary.grow(-2),2,7,dark)
		for n in 4:
			var x: float = auxiliary.position.x+13+n*18
			c._box(Rect2(x,auxiliary.position.y+9,7,7),2,10,Color(0.12,0.25,0.42) if n<3 else Color(0.55,0.24,0.12))
		# Ribbed armrest attachments and inset switch plates.
		var x: float = r.position.x-15 if side == "left" else r.end.x+5
		c._box(Rect2(x,r.position.y+25,10,r.size.y-31),18,-8,pale)
		for n in 6:
			c._box(Rect2(x+2,r.position.y+37+n*15,6,4),2,3,steel)
		# Under-screen physical keys are distinct from live CRT contents.
		for n in 6:
			c._box(Rect2(r.position.x+20+n*23,r.end.y+5,12,4),3,17,steel)
	# Center bezel knobs and a single guarded red switch.
	for sign: float in [-1.0,1.0]:
		var x: float = center.get_center().x+sign*(center.size.x/2+10)
		c._box(Rect2(x-3,center.end.y-34,6,17),5,25,steel)
	c._box(Rect2(center.get_center().x-11,center.end.y+4,22,5),4,17,Color(0.42,0.13,0.10))
