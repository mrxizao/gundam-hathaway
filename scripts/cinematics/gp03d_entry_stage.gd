extends Node3D
## No airport or collision geometry: a small, deterministic cinematic star field.
var runway:=false
var adelaide_launch:=false
var launch_point:=Vector3.ZERO
func _ready()->void:
 var environment:=Environment.new()
 environment.background_mode=Environment.BG_CLEAR_COLOR
 environment.background_color=Color(.009,.015,.036)
 environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 environment.ambient_light_color=Color(.55,.68,1.0)
 environment.ambient_light_energy=.72
 environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
 environment.glow_enabled=true
 environment.glow_intensity=.9
 var world:=WorldEnvironment.new();world.environment=environment;add_child(world)
 for item in [Vector3(-30,-35,0),Vector3(25,135,0)]:
  var light:=DirectionalLight3D.new();light.rotation_degrees=item
  light.light_energy=2.0 if item.x<0 else 1.1
  light.light_color=Color(.85,.91,1) if item.x<0 else Color(.28,.52,1)
  add_child(light)
 var stars:=MultiMeshInstance3D.new()
 var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.use_colors=true
 var point:=SphereMesh.new();point.radius=1.5;point.height=3;point.radial_segments=6;point.rings=3
 var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.vertex_color_use_as_albedo=true
 point.material=material;multi.mesh=point;multi.instance_count=500
 var rng:=RandomNumberGenerator.new();rng.seed=3083
 for i in multi.instance_count:
  var direction:=Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1)).normalized()
  multi.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*rng.randf_range(.5,1.8)),direction*rng.randf_range(1600,6500)))
  multi.set_instance_color(i,Color(.42,.6,.95)*rng.randf_range(.3,.9))
 stars.multimesh=multi;add_child(stars)
func fit_transport_support(_bounds:AABB)->void:pass
func sample(_time:float)->void:pass
