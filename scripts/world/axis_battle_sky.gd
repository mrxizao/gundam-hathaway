extends Node3D
## Distant battle decoration: shared meshes, no physics bodies and no gameplay shots.
const STREAKS:=64
const FLASHES:=24
var rng:=RandomNumberGenerator.new()
var streaks: MultiMesh
var flashes: MultiMesh
var paths: Array[Dictionary]=[]
var bursts: Array[Dictionary]=[]
var observer:=Vector3.ZERO
func _ready() -> void:
	name="AxisDistantBattle";rng.seed=1988031202
	var mesh:=CylinderMesh.new();mesh.top_radius=1;mesh.bottom_radius=1;mesh.height=2;mesh.radial_segments=5;mesh.rings=1
	streaks=_batch(mesh,STREAKS,false)
	var quad:=QuadMesh.new();quad.size=Vector2(2,2)
	flashes=_batch(quad,FLASHES,true)
	for i in STREAKS: paths.append(_path(true))
	for i in FLASHES: bursts.append(_burst(true))
func _batch(mesh: Mesh,count: int,ring: bool) -> MultiMesh:
	var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_colors=true;mm.mesh=mesh;mm.instance_count=count
	var node:=MultiMeshInstance3D.new();node.multimesh=mm;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo=true;mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mat.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
	mat.emission_enabled=true;mat.emission=Color.WHITE;mat.emission_energy_multiplier=2.0;mat.no_depth_test=false
	if ring:
		mat.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED;mat.billboard_keep_scale=true;mat.cull_mode=BaseMaterial3D.CULL_DISABLED
		var img:=Image.create(128,128,false,Image.FORMAT_RGBA8)
		for y in 128:
			for x in 128:
				var d:=Vector2(x-63.5,y-63.5).length()/63.5
				var a:=exp(-pow((d-0.64)/0.055,2))*0.9+exp(-d*d*32)*0.7+exp(-pow((d-0.68)/0.18,2))*0.12
				img.set_pixel(x,y,Color(1,1,1,clampf(a,0,1)))
		img.generate_mipmaps();mat.albedo_texture=ImageTexture.create_from_image(img)
	node.material_override=mat;add_child(node);return mm
func _point() -> Vector3:
	var direction:=Vector3(rng.randf_range(-1,1),rng.randf_range(0.18,0.95),rng.randf_range(-1,1)).normalized()
	return direction*rng.randf_range(38000,85000)
func _color() -> Color:
	return [Color(1.0,0.32,0.49),Color(0.44,0.78,1.0),Color(1.0,0.83,0.38)][rng.randi_range(0,2)]
func _path(random_age: bool) -> Dictionary:
	var life:=rng.randf_range(2.5,5.0)
	return {"start":_point(),"dir":Vector3(rng.randf_range(-1,1),rng.randf_range(-0.35,0.35),rng.randf_range(-1,1)).normalized(),"speed":rng.randf_range(5000,16000),"length":rng.randf_range(900,2200),"life":life,"age":rng.randf_range(0,life) if random_age else 0.0,"color":_color()}
func _burst(random_age: bool) -> Dictionary:
	var life:=rng.randf_range(1.8,3.6)
	return {"position":_point(),"radius":rng.randf_range(650,1600),"life":life,"age":rng.randf_range(0,life) if random_age else 0.0,"color":_color()}
func _process(delta: float) -> void:
	var camera:=get_viewport().get_camera_3d()
	if is_instance_valid(camera): observer=camera.global_position
	global_position=observer
	for i in STREAKS:
		var p: Dictionary=paths[i];p.age+=delta
		if p.age>=p.life: paths[i]=_path(false);p=paths[i]
		var fade:=sin(PI*p.age/p.life)
		var basis:=Basis(Quaternion(Vector3.UP,p.dir))*Basis.from_scale(Vector3(30,p.length*0.5,30))
		streaks.set_instance_transform(i,Transform3D(basis,p.start+p.dir*p.speed*p.age))
		streaks.set_instance_color(i,Color(p.color,fade*0.65))
	for i in FLASHES:
		var b: Dictionary=bursts[i];b.age+=delta
		if b.age>=b.life: bursts[i]=_burst(false);b=bursts[i]
		var t: float=b.age/b.life;var radius: float=b.radius*(0.3+t*1.7)
		flashes.set_instance_transform(i,Transform3D(Basis().scaled(Vector3.ONE*radius),b.position))
		flashes.set_instance_color(i,Color(b.color,sin(PI*t)*(1-t)*1.3))
