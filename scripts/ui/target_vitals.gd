extends RefCounted
## Presentation only. Combat HP, target projection and lock behavior stay authoritative.
var _identity := 0
var _ratios := Vector2.ONE

func tick(target:FlightBody,delta:float)->void:
	if not is_instance_valid(target) or not target.alive:
		_identity=0
		return
	var actual:=Vector2(target.ifield_ratio(),target.hp_ratio())
	if _identity!=target.get_instance_id():
		_identity=target.get_instance_id()
		_ratios=actual
		return
	# About 95% settled in 0.15s; continuous hits cannot restart a timer.
	_ratios=_ratios.lerp(actual,1.0-exp(-20.0*maxf(delta,0.0)))
	for i in 2:
		if absf(_ratios[i]-actual[i])<0.0001:_ratios[i]=actual[i]

func values(target:FlightBody)->Vector2:
	if _identity!=target.get_instance_id():
		return Vector2(target.ifield_ratio(),target.hp_ratio())
	return _ratios

static func geometry(point:Vector2,top:float,width:float,pixel_scale:Vector2)->Array[Rect2]:
	var scale:=pixel_scale.max(Vector2(.01,.01))
	var at:=((point+Vector2(-width*.5,top))*scale).round()/scale
	var w:=maxf(roundf(width*scale.x),1.0)/scale.x
	var field:=Rect2(at,Vector2(w,maxf(roundf(3.0*scale.y),2.0)/scale.y))
	var hull_at:=at+Vector2(0,roundf(11.0*scale.y)/scale.y)
	return [field,Rect2(hull_at,Vector2(w,maxf(roundf(4.0*scale.y),3.0)/scale.y))]

static func fill_rect(bar:Rect2,ratio:float,pixel_scale:Vector2)->Rect2:
	var sx:=maxf(pixel_scale.x,.01)
	return Rect2(bar.position,Vector2(roundf(bar.size.x*clampf(ratio,0,1)*sx)/sx,bar.size.y))
