extends Node3D
## Seeded, explicitly sampled blast: the cockpit shot repeats the same impact.
var radius:=45.0
var fire:Array[MeshInstance3D]=[]
var smoke:Array[MeshInstance3D]=[]
var debris:Array[MeshInstance3D]=[]
var lamp:OmniLight3D
var directions:Array[Vector3]=[]
func sphere(color:Color,glow:float)->MeshInstance3D:
	var n:=MeshInstance3D.new()
	var mesh:=SphereMesh.new();mesh.radial_segments=12;mesh.rings=6;mesh.radius=1;mesh.height=2;n.mesh=mesh
	var mat:=ShaderMaterial.new();mat.shader=preload("res://shaders/m09_cinematic_blast.gdshader")
	mat.set_shader_parameter("heat",1.0 if glow>0 else 0.0)
	mat.set_shader_parameter("seed",float(get_child_count())*.731)
	n.material_override=mat;n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(n)
	return n
func _ready()->void:
	var rng:=RandomNumberGenerator.new();rng.seed=901640
	for i in 9:
		directions.append(Vector3(rng.randf_range(-1,1),rng.randf_range(.1,1),rng.randf_range(-1,1)).normalized())
		fire.append(sphere(Color(1,.28+.055*i,.035,.85),2.2))
	for i in 8:smoke.append(sphere(Color(.085+.008*i,.075+.006*i,.07+.006*i,.82),0))
	for i in 18:debris.append(sphere(Color(.8,.31,.07),1.0))
	lamp=OmniLight3D.new();lamp.omni_range=radius*7;lamp.light_color=Color(1,.46,.15);lamp.shadow_enabled=false;add_child(lamp)
	sample(-1)
func sample(age:float)->void:
	visible=age>=0 and age<5.0
	if not visible:return
	var growth:=1.0-exp(-age*9.0)
	for i in fire.size():
		var n:=fire[i];var delay:=float(i)*.025
		(n.material_override as ShaderMaterial).set_shader_parameter("age",age)
		var life:=maxf(age-delay,0)
		n.position=directions[i]*radius*.42*growth+Vector3.UP*life*radius*.15
		n.scale=Vector3.ONE*maxf(.01,radius*(.48+.025*i)*growth*(1.0-smoothstep(.25,1.8,life)))
		n.transparency=smoothstep(.45,1.8,life)
	for i in smoke.size():
		var n:=smoke[i];var direction:Vector3=directions[i]
		(n.material_override as ShaderMaterial).set_shader_parameter("age",age)
		n.position=direction*radius*.5+Vector3.UP*(radius*.2+age*radius*(.28+.045*i))
		n.scale=Vector3.ONE*radius*(.25+.12*age+.02*i)*smoothstep(0,.3,age)
		n.transparency=smoothstep(3.0,5.0,age)
	for i in debris.size():
		var n:=debris[i];var direction:Vector3=directions[i%directions.size()]
		var speed:float=radius*(1.8+float(i%5)*.3)
		n.position=direction*speed*age+Vector3.DOWN*age*age*15
		n.scale=Vector3.ONE*maxf(.08,radius*.012*(1.0-smoothstep(.7,2.0,age)))
		n.transparency=smoothstep(1.4,2.5,age)
	lamp.light_energy=12.0*exp(-age*4.0)
