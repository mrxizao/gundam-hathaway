extends StaticBody3D
const Spec:=preload("res://scripts/data/zorin_spec.gd")
var controller
var index:=0
var hp:=Spec.FIN_HP
var alive:=true
var pre_left:=0.0
var post_left:=0.0
var selected:Node3D
var model:Node3D
var launch_from:=Vector3.ZERO
var return_from:=Vector3.ZERO
var deployed:=false
func _ready()->void:
	name="ZorinFin"+str(index);collision_layer=0;collision_mask=0
	var shape:=CollisionShape3D.new();shape.shape=SphereShape3D.new();shape.shape.radius=3.0;add_child(shape)
	if not FlightBody.use_placeholder:
		var scene:PackedScene=load("res://assets/models/zorin/fin_%d.scn"%index)
		model=scene.instantiate();model.scale=Vector3.ONE;add_child(model)
	else:
		var box:=MeshInstance3D.new();box.mesh=BoxMesh.new();box.scale=Vector3(1,6,.5);add_child(box);model=box
	hide()
func activate(at:Vector3)->void:
	launch_from=at;global_position=at;deployed=true;show();collision_layer=0
func prepare(target:Node3D)->bool:
	if not alive or frozen() or not is_instance_valid(target):return false
	selected=target;pre_left=Spec.PRE_SHOT;return true
func frozen()->bool:return pre_left>0 or post_left>0
func cancel_shot()->void:pre_left=0;post_left=0;selected=null
func tick_shot(delta:float)->void:
	if pre_left>0:
		pre_left=maxf(pre_left-delta,0)
		if pre_left<=0:
			fire();post_left=Spec.POST_SHOT
	elif post_left>0:post_left=maxf(post_left-delta,0)
func fire()->void:
	if not alive or not is_instance_valid(selected) or not selected.alive:return
	var body=controller.body
	var from:=global_position-global_basis.z*3.5
	var direction:Vector3=from.direction_to(selected.global_position)
	preload("res://scripts/combat/funnel_beam.gd").pulse(body.projectile_container,body,from,direction,Spec.DAMAGE*body.damage_mult,Color(1,.83,.32),1.15,self,controller.visual_only)
	Audio.play_3d("beam_rifle",from,-10.0)
	controller.record_shot(index,from,direction)
func take_damage(amount:float,source:Node3D=null,_kind:=Damage.Type.BEAM)->void:
	if not alive or not deployed or amount<=0:return
	if is_instance_valid(source) and (source==controller.body or controller.body.is_friendly_fire(source)):return
	if controller.visual_only:
		if source==Game.player and Net.is_online():
			var key=controller.body.get("net_unit_id")
			Net.send_fire("nu_fin_hit_"+str(index) if key==null else "nu_fin_ai_"+str(key)+"_"+str(index),global_position,Vector3(amount,0,0))
		return
	hp=maxf(hp-amount,0)
	if hp<=0:
		alive=false;collision_layer=0;hide();cancel_shot()
		FX.explosion(get_parent(),global_position,.3,Color(1,.8,.3))
		controller.fin_destroyed(index)
func is_alive()->bool:return alive and deployed
func reset(docked:bool)->void:
	hp=Spec.FIN_HP;alive=true;cancel_shot();deployed=not docked
	collision_layer=0 if docked else Spec.FIN_HIT_LAYER
	visible=not docked
