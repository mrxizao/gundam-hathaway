extends RefCounted
const VITALS=preload("res://scripts/ui/target_vitals.gd")
static func run(t:T,host:Node)->void:
	t.suite("TargetVitals / recoil pixels and damage transitions")
	var old:=FlightBody.use_placeholder;FlightBody.use_placeholder=true;Game.reset()
	var stage:=Node3D.new();host.add_child(stage)
	var target:=FlightBody.new();target.profile=SuitProfile.xi();stage.add_child(target);target.set_physics_process(false)
	var next:=FlightBody.new();next.profile=SuitProfile.sazabi();stage.add_child(next);next.set_physics_process(false)
	var v:=VITALS.new();v.tick(target,.016)
	t.eq(v.values(target),Vector2.ONE,"initial selection displays actual vitals immediately")
	target.ifield_hp*=.5;v.tick(target,1.0/60)
	t.gt(v.values(target).x,.5,"damage transition avoids instantaneous jump")
	t.lt(v.values(target).x,1.0,"damage transition starts immediately")
	var last:float=v.values(target).x
	for i in 60:
		if i%4==0:target.ifield_hp=maxf(target.ifield_hp-3,0)
		v.tick(target,1.0/60)
		t.ok(v.values(target).x<=last,"continuous hits never reverse displayed field")
		last=v.values(target).x
	t.eq(target.hp,target.max_hp,"presentation never modifies combat HP")
	next.ifield_hp=0;next.hp=next.max_hp*.2;v.tick(next,.016)
	t.eq(v.values(next),Vector2(0,.2),"new target cannot inherit old target values")
	v.tick(null,.016);target.ifield_hp=0;v.tick(target,.016)
	t.eq(v.values(target).x,0.0,"reacquisition initializes actual depleted field")
	for scale:Vector2 in [Vector2(.6,.6),Vector2(.8,.8),Vector2.ONE,Vector2(1.5,1.5),Vector2(1.2,.9)]:
		for offset in [.0,.11,.37,.68,.99]:
			for bar:Rect2 in VITALS.geometry(Vector2(500.3,300+offset),39,96,scale):
				var physical:=Rect2(bar.position*scale,bar.size*scale)
				t.ok(physical.position.distance_to(physical.position.round())<.0001,"bar position uses whole display pixels")
				t.ok(physical.size.distance_to(physical.size.round())<.0001,"bar thickness uses whole display pixels")
				for ratio in [0.0,.001,.25,.5,1.0]:
					var fill:Rect2=VITALS.fill_rect(bar,ratio,scale)
					t.near(fill.size.x*scale.x,roundf(fill.size.x*scale.x),.0001,"fill edge remains on pixel grid")
					t.ok(fill.size.x>=0 and fill.size.x<=bar.size.x+.0001,"fill never exceeds track")
	stage.queue_free();await host.get_tree().process_frame;Game.reset();FlightBody.use_placeholder=old
