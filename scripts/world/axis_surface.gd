extends Node3D
## Deterministic, tiled solid asteroid surface. No atmosphere or vegetation.
const TILE := 12000.0
const HALF := 8
static var noise: FastNoiseLite
var material: ShaderMaterial
static func height_at(x: float,z: float) -> float:
	if noise==null:
		noise=FastNoiseLite.new();noise.seed=19880312;noise.frequency=0.00038
		noise.noise_type=FastNoiseLite.TYPE_SIMPLEX_SMOOTH;noise.fractal_octaves=4
	var n:=noise.get_noise_2d(x,z)
	var corridor:=x-650.0*sin(z*0.00023)
	var ridge:=exp(-pow((absf(corridor)-2600.0)/1100.0,2.0))
	var crags:=pow(1.0-absf(noise.get_noise_2d(x*0.45+9811,z*0.45)),4.0)
	return 100.0+noise.get_noise_2d(x*3.5,z*3.5)*(45+ridge*90)+n*220.0+ridge*(850.0+crags*850.0)+crags*180.0
func build() -> void:
	name="AxisSurface"
	material=ShaderMaterial.new();material.shader=preload("res://shaders/axis_rock.gdshader")
	for iz in range(-HALF,HALF):
		for ix in range(-HALF,HALF):
			_tile(ix,iz,48 if abs(ix)<2 and abs(iz)<2 else 16)
	_rocks()
	_earth()
	var battle:=preload("res://scripts/world/axis_battle_sky.gd").new();add_child(battle)
func _tile(ix: int,iz: int,steps: int) -> void:
	var verts:=PackedVector3Array();var normals:=PackedVector3Array();var indices:=PackedInt32Array()
	for z in steps+1:
		for x in steps+1:
			var wx:=ix*TILE+float(x)*TILE/steps;var wz:=iz*TILE+float(z)*TILE/steps
			verts.append(Vector3(wx,height_at(wx,wz),wz))
			var nx:=height_at(wx-18,wz)-height_at(wx+18,wz)
			var nz:=height_at(wx,wz-18)-height_at(wx,wz+18)
			normals.append(Vector3(nx,36,nz).normalized())
	for z in steps:
		for x in steps:
			var a:=z*(steps+1)+x;var b:=a+1;var c:=a+steps+1;var d:=c+1
			indices.append_array(PackedInt32Array([a,b,c,b,d,c]))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=verts;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var visual:=MeshInstance3D.new();visual.mesh=mesh;visual.material_override=material
	visual.name="RockTile_%d_%d" % [ix,iz];visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	var body:=StaticBody3D.new();body.name="AxisGround";body.collision_layer=1;body.collision_mask=0
	body.add_to_group("avoidance_ground");body.add_to_group("axis_ground")
	var shape:=CollisionShape3D.new();shape.shape=mesh.create_trimesh_shape();shape.shape.backface_collision=true;body.add_child(shape);add_child(body)
func _rocks() -> void:
	var rng:=RandomNumberGenerator.new();rng.seed=35513552
	var mesh:=SphereMesh.new();mesh.radial_segments=9;mesh.rings=5;mesh.radius=1;mesh.height=2
	var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=mesh;mm.instance_count=180
	for i in 180:
		var x:=rng.randf_range(-18000,18000);var z:=rng.randf_range(-18000,18000)
		var scale:=Vector3(rng.randf_range(35,125),rng.randf_range(30,155),rng.randf_range(40,180))
		var position:=Vector3(x,height_at(x,z)-scale.y*0.22,z)
		var transform:=Transform3D(Basis(Vector3.UP,rng.randf_range(-PI,PI)).scaled(scale),position)
		mm.set_instance_transform(i,transform)
		# Physics ellipsoids approximate the visible boulders; touching them is also safe.
		var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0
		body.transform=Transform3D(Basis(Vector3.UP,0),position);body.add_to_group("avoidance_ground");body.add_to_group("axis_ground")
		var collision:=CollisionShape3D.new();var sphere:=SphereShape3D.new();sphere.radius=minf(scale.x,minf(scale.y,scale.z))
		collision.shape=sphere;body.add_child(collision);add_child(body)
	var instance:=MultiMeshInstance3D.new();instance.name="AxisBoulders";instance.multimesh=mm;instance.material_override=material;add_child(instance)
func _earth() -> void:
	var mesh:=SphereMesh.new();mesh.radius=170000;mesh.height=340000;mesh.radial_segments=96;mesh.rings=48
	var globe:=MeshInstance3D.new();globe.name="AxisEarth";globe.mesh=mesh
	globe.position=Vector3(220000,170000,-340000)
	var mat:=ShaderMaterial.new();mat.shader=preload("res://shaders/axis_earth.gdshader");mat.set_shader_parameter("sun_dir",Vector3(0.6,0.45,0.65).normalized())
	globe.material_override=mat;globe.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(globe)
