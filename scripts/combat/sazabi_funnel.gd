extends CharacterBody3D
## Independent, shootable remote weapon. It is deliberately not a lock-list MS.
const HP:=20.0
const BEFORE_SHOT:=0.05
const AFTER_SHOT:=0.1
const INTERVAL:=3.0
var controller
var slot:=0
var hp:=HP
var visual:Node3D
var age:=0.0
var next_shot:=0.0
var phase:=0
var phase_age:=0.0
var frozen:=Vector3.ZERO
var return_from:=Vector3.ZERO
var return_basis:=Basis.IDENTITY
var orbit:=Vector3.ZERO
var rng:=RandomNumberGenerator.new()
var fired_count:=0
var destroyed:=false

func _ready()->void:
	name="SazabiFunnel%d" % slot
	# Shootable weapon hitboxes must not block aircraft or enter ground-crash routing.
	collision_layer=preload("res://scripts/data/nu_spec.gd").FIN_HIT_LAYER;collision_mask=FlightBody.WORLD_LAYER
	var collision:=CollisionShape3D.new();var shape:=SphereShape3D.new();shape.radius=2.0
	collision.shape=shape;add_child(collision);add_to_group("sazabi_funnels")
	rng.seed=1733+slot*97;next_shot=1.0+slot*.5;pick_orbit()
	if visual!=null:add_child(visual)

func pick_orbit()->void:
	var angle:=rng.randf_range(0,TAU)
	var radius:=rng.randf_range(350,850)
	orbit=Vector3(cos(angle)*radius,rng.randf_range(70,200),sin(angle)*radius).limit_length(890)

func freeze()->void:
	frozen=global_position;velocity=Vector3.ZERO

func begin_return()->void:
	return_from=global_position;return_basis=global_basis.orthonormalized();phase=0;phase_age=0;velocity=Vector3.ZERO
	collision_layer=0

func take_damage(amount:float,source:Node3D,_type:=Damage.Type.BEAM)->void:
	if destroyed or amount<=0 or controller==null:return
	var body=controller.body
	if not is_instance_valid(body) or source==body or (source!=null and body.is_friendly_fire(source)):return
	if controller.visual_only:
		if source is FlightBody:
			var key: String = "player" if body.has_method("apply_state") else str(body.get("net_unit_id"))
			source._net_report_fire("sazabi_damage:"+key+":"+str(slot)+":"+str(amount),global_position,Vector3.FORWARD)
		return
	hp=maxf(0,hp-amount)
	if hp<=0:
		destroyed=true;collision_layer=0
		FX.explosion(get_parent(),global_position,.25)
		controller.funnel_destroyed(slot)
		queue_free()

func fire()->void:
	if controller==null or not controller.valid_target():return
	var body=controller.body
	var mark=controller.target
	var dir:Vector3=global_position.direction_to(mark.global_position)
	var from:=global_position+dir*4.0
	if not controller.visual_only:
		preload("res://scripts/combat/funnel_beam.gd").pulse(body.projectile_container,body,from,dir,27.0*body.damage_mult,Color(.55,1,.4),.75,self)
		body._net_report_fire("sazabi_fin",from,dir)
	Audio.play_3d("beam_rifle",from,-9)
	fired_count+=1

func _physics_process(delta:float)->void:
	step(delta)

func step(delta:float)->void:
	if controller==null or not is_instance_valid(controller.body) or not controller.body.alive:
		queue_free();return
	age+=delta
	if controller.state==controller.State.RETURNING:
		var ratio: float = clampf(controller.return_age/3.0,0,1)
		global_position=return_from.lerp(controller.home(slot),ratio)
		var dock_basis: Basis = controller.motion.docks[slot].global_basis.orthonormalized() if controller.motion!=null and slot<controller.motion.docks.size() else controller.body.global_basis
		global_basis=return_basis.slerp(dock_basis,ratio)
		return
	if controller.state!=controller.State.ACTIVE:return
	if not controller.valid_target():controller.recall();return
	var mark=controller.target
	var desired:Vector3
	if controller.mode==controller.Mode.VOLLEY:
		if controller.volley_phase>0:
			global_position=frozen;return
		var angle:=slot*TAU/6.0+TAU*clampf(controller.volley_age/3.7,0,1)
		desired=mark.global_position+Vector3(cos(angle)*480,360,sin(angle)*480)
	else:
		if phase!=0:
			global_position=frozen;phase_age+=delta
			if phase==1 and phase_age>=BEFORE_SHOT:
				fire();phase=2;phase_age=0;next_shot=age+INTERVAL
			elif phase==2 and phase_age>=AFTER_SHOT:
				phase=0;phase_age=0;pick_orbit()
			return
		desired=mark.global_position+orbit
		if age>=next_shot-BEFORE_SHOT and global_position.distance_to(mark.global_position)<1000:
			phase=1;phase_age=0;freeze();return
	velocity=(desired-global_position).limit_length(6500.0*delta)/maxf(delta,.0001)
	move_and_collide(velocity*delta)
	var toward:Vector3=global_position.direction_to(mark.global_position)
	if toward.length_squared()>.5:
		var up:=Vector3.UP if absf(toward.dot(Vector3.UP))<.98 else Vector3.RIGHT
		global_basis=Basis.looking_at(toward,up)
