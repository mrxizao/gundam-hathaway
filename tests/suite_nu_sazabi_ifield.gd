extends RefCounted
const THIRD = preload("res://scripts/ui/third_person_hud.gd")
const COCKPIT = preload("res://scripts/ui/cockpit_readouts.gd")
class Readout extends RefCounted:
	var player:PlayerController
	var size:=Vector2(1600,900)
	var _font:Font=ThemeDB.fallback_font
	var texts:Array[String]=[]
	var fills:Array[Rect2]=[]
	func _magnifier_text_rect(_p,_s,_fs,_x):pass
	func _magnifier_ui_rect(_r,_x):pass
	func draw_string_outline(_f,_p,_s,_a,_w,_fs,_sz,_c):pass
	func draw_string(_f,_p,s,_a,_w,_fs,_c):texts.append(s)
	func draw_rect(r,_c):fills.append(r)
	func draw_line(_a,_b,_c,_w,_aa):pass
	func _text(_p,s,_fs,_c):texts.append(s)
	func _text_right(_p,s,_fs,_c):texts.append(s)

static func run(t:T,host:Node)->void:
	Settings.begin_isolated();Game.reset()
	var old:=FlightBody.use_placeholder;FlightBody.use_placeholder=true
	var stage:=Node3D.new();host.add_child(stage)
	var foe:=FlightBody.new();foe.profile=SuitProfile.gustav00();foe.team=1;stage.add_child(foe);foe.set_physics_process(false)
	for profile:SuitProfile in [SuitProfile.nu_gundam(),SuitProfile.sazabi()]:
		t.suite(profile.display_name+" / independent I-field")
		var p:=PlayerController.new();p.profile=profile;p.is_player=true;p.team=0;stage.add_child(p)
		p.set_physics_process(false);p.position=Vector3(0,5000,0)
		if p.is_nu():p.nu_systems.set_physics_process(false)
		t.near(p.ifield_max,SuitProfile.xi().ifield_hp,.001,"same base durability as Xi, scaling applied once")
		t.gt(p.ifield_max,0,"I-field starts enabled")
		t.eq(p.ifield_hp,p.ifield_max,"sortie starts full")
		var hp:=p.hp
		for kind in Damage.Type.values():
			p.ifield_hp=p.ifield_max;p.hp=hp;p.take_damage(10,foe,kind)
			t.near(p.hp,hp,.001,"field protects hull for damage type %d"%kind)
			t.near(p.ifield_hp,p.ifield_max-Damage.ifield_cost(10,kind),.001,"existing absorption efficiency %d"%kind)
		p.ifield_hp=5;p.hp=hp;p.take_damage(12,foe,Damage.Type.BEAM)
		t.eq(p.ifield_hp,0.0,"overload empties field")
		t.near(p.hp,hp-7,.001,"only overflow reaches hull")
		t.not_ok(p.has_ifield(),"depletion updates combat state")
		p.take_damage(10,foe,Damage.Type.BEAM)
		t.near(p.hp,hp-17,.001,"subsequent beam reaches hull")
		p.start_repair();p._tick_repair(60)
		t.eq(p.ifield_hp,0.0,"repair does not regenerate field")
		var h:=Readout.new();h.player=p
		THIRD._health(h,Rect2(30,700,300,124))
		t.ok(h.texts.has("I-FIELD") and h.texts.has("DOWN"),"third-person shows depleted field")
		h.texts.clear();COCKPIT.new().health(h)
		t.ok(h.texts.has("I-FIELD") and h.texts.has("DOWN"),"cockpit shows depleted field")
		p.ifield_hp=p.ifield_max;h.texts.clear();THIRD._health(h,Rect2(30,700,300,124))
		t.ok(h.texts.has("%03d"%int(p.ifield_hp)),"third-person shows actual field points")
		p.shield_up=true;p.take_damage(10,foe,Damage.Type.BEAM)
		t.eq(p.ifield_hp,p.ifield_max,"physical shield still blocks rifle before field")
		p.shield_up=false
		if p.is_nu():
			var sys=p.nu_systems
			sys.mode=sys.Mode.DEFENSE;sys.state=sys.State.ACTIVE;sys.energy=100;sys.cooldown_left=0
			for fin in sys.fins:fin.global_position=p.global_position
			t.ok(sys.barrier_active(),"independent fin barrier can still activate")
			for kind in Damage.Type.values():p.take_damage(100,foe,kind)
			t.eq(p.ifield_hp,p.ifield_max,"fin barrier protects base field")
			sys.energy=0;p.take_damage(10,foe,Damage.Type.BEAM)
			t.near(p.ifield_hp,p.ifield_max-10,.001,"base field remains after fin energy exhaustion")
		else:
			var energy:float=p.sazabi_systems.energy
			p.take_damage(10,foe,Damage.Type.BEAM)
			t.eq(p.sazabi_systems.energy,energy,"I-field hits do not spend funnel energy")
		p.queue_free();await host.get_tree().process_frame
	stage.queue_free();await host.get_tree().process_frame
	FlightBody.use_placeholder=old;Game.reset();Settings.end_isolated()
