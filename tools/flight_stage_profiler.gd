extends RefCounted
static var enabled:=false
static var values:Dictionary={}
static func begin()->int:
	return Time.get_ticks_usec() if enabled and Engine.get_physics_frames()%11==0 else 0
static func finish(stage:String,id:int,begin_us:int)->void:
	if begin_us==0:return
	var elapsed:=Time.get_ticks_usec()-begin_us
	var key:=stage+"/"+str(id)
	if not values.has(key):values[key]={"calls":0,"total_us":0,"max_us":0}
	values[key].calls+=1;values[key].total_us+=elapsed;values[key].max_us=maxi(values[key].max_us,elapsed)
