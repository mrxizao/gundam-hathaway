extends RefCounted
const NAMES:=["空调机组","风管","检修舱","天线","栏杆","落水管","门框","遮檐","护柱","排水口","维修盖","配电箱"]
static func emit(w:Object,kind:int,p:Vector3,variant:int=0)->void:
	match kind:
		0:
			w.box(p+Vector3(0,.6,0),Vector3(14,1.2,10),0);w.box(p+Vector3(0,3.5,0),Vector3(12,5,8),2)
			for x:float in [-3,3]:w.box(p+Vector3(x,6.2,0),Vector3(4,.5,5),3,2)
			for n in 4:w.box(p+Vector3(0,2+n*.8,-4.1),Vector3(10,.18,.25),3,2)
		1:
			w.box(p+Vector3(0,1.6,0),Vector3(18,3.2,4),2);w.box(p+Vector3(7,3.5,0),Vector3(4,7.0,4),2)
			for x:float in [-6,0,6]:w.box(p+Vector3(x,1.6,0),Vector3(.35,3.5,4.4),3,6)
		2:
			w.box(p+Vector3(0,2,0),Vector3(10,4,9),0);w.box(p+Vector3(0,4.3,0),Vector3(11,.6,10),5);w.box(p+Vector3(0,1.8,-4.6),Vector3(3,3.6,.25),2)
		3:
			w.box(p+Vector3(0,.6,0),Vector3(5,1.2,5),0);w.box(p+Vector3(0,4.5,0),Vector3(.45,8,.45),2)
			for y:float in [4,6.5]:w.box(p+Vector3(0,y,0),Vector3(6,.25,.25),2)
		4:
			for x:float in [-9,0,9]:w.box(p+Vector3(x,2,0),Vector3(.3,4,.3),2)
			for y:float in [1.7,3.8]:w.box(p+Vector3(0,y,0),Vector3(18,.3,.3),2)
		5:
			w.box(p+Vector3(0,5,0),Vector3(.6,10,.6),2)
			for y:float in [1,5,9]:w.box(p+Vector3(0,y,0),Vector3(1,.25,1),3,6)
		6:
			for x:float in [-5,5]:w.box(p+Vector3(x,7,0),Vector3(.65,14,1),2)
			w.box(p+Vector3(0,14,0),Vector3(10.7,.65,1),2)
		7:
			w.box(p+Vector3(0,0,0),Vector3(22,1,8),2)
			for x:float in [-8,8]:w.box(p+Vector3(x,-2,1),Vector3(.5,4,.5),2)
		8:
			for x:float in [-5,0,5]:w.box(p+Vector3(x,1.3,0),Vector3(.8,2.6,.8),2);w.box(p+Vector3(x,2.1,0),Vector3(.85,.3,.85),3,4)
		9:
			w.box(p+Vector3(0,.12,0),Vector3(5,.24,3),2)
			for x:float in [-1.8,-.9,0,.9,1.8]:w.box(p+Vector3(x,.27,0),Vector3(.25,.1,2.6),3,2)
		10:
			w.box(p+Vector3(0,.15,0),Vector3(7,.3,6),2);w.box(p+Vector3(0,.34,0),Vector3(6,.15,5),3,6)
		11:
			w.box(p+Vector3(0,2.4,0),Vector3(5,4.8,2),2);w.box(p+Vector3(0,2.6,-1.1),Vector3(4,3.8,.25),3,1)
static func placements(parcel:Dictionary)->Array[Dictionary]:
	var rect:Rect2=parcel.bounds;var h:float=parcel.height;var style:int=parcel.style
	var rng:=RandomNumberGenerator.new();rng.seed=int(parcel.seed)^0x5A19C2
	var slots:Array[Vector2]=[Vector2(-.32,-.32),Vector2(.32,-.32),Vector2(-.32,.31),Vector2(0,-.34),Vector2(-.35,0),Vector2(-.18,-.34)]
	var result:Array[Dictionary]=[];var count:=4+int(rng.randi()%3)
	for i in count:
		var slot:Vector2=slots[(i+int(parcel.seed)%slots.size()+slots.size())%slots.size()]
		var kind:int=[0,1,2,3,4,9,10][int(rng.randi()%7)]
		if kind==3 and absf(slot.x)<.2:kind=0
		var y:=h+.7
		if style==4:y+=6.0*(1.0-absf(slot.x)*2.0)
		result.append({"kind":kind,"position":Vector3(slot.x*rect.size.x,y,slot.y*rect.size.y)})
	for row:Dictionary in [{"kind":5,"x":-.43,"y":h-10.0},{"kind":6,"x":0.0,"y":0.0},{"kind":7,"x":0.0,"y":15.0},{"kind":8,"x":-.12,"y":0.0},{"kind":11,"x":.17,"y":0.0}]:
		result.append({"kind":row.kind,"position":Vector3(float(row.x)*rect.size.x,float(row.y),-rect.size.y*.5+8)})
	return result
