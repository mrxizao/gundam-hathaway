extends MultiMeshInstance3D
## GP03's physical missile simulation stays in the salvo. Only trail history is batched here.
const STYLE=preload("res://scripts/world/missile_ribbon.gd")
const HOLD_SECONDS:=1.5
var capacity:=512
var count:=0
var spacing:=STYLE.SPACING
var points:Image
var metadata:Image
var points_texture:ImageTexture
var meta_texture:ImageTexture
var material:ShaderMaterial
var counts:=PackedInt32Array()
var last:=PackedVector3Array()
var dirty:=false
var clock:=0.0
func configure(total:int,reach:float,center:Vector3)->void:
	count=total
	capacity=256 if Settings.effects_quality==0 else STYLE.MAX_POINTS
	spacing=STYLE.SPACING*(2.0 if Settings.effects_quality==0 else 1.0)
	counts.resize(total);last.resize(total)
	points=Image.create(capacity,total,false,Image.FORMAT_RGBAF)
	metadata=Image.create(total,1,false,Image.FORMAT_RGBAF)
	points_texture=ImageTexture.create_from_image(points);meta_texture=ImageTexture.create_from_image(metadata)
	material=ShaderMaterial.new();material.shader=preload("res://shaders/gp03d_xi_ribbon.gdshader")
	material.set_shader_parameter("path_points",points_texture);material.set_shader_parameter("path_meta",meta_texture)
	material.set_shader_parameter("segments_per_missile",capacity-1)
	material.set_shader_parameter("half_width",STYLE.HALF_W);material.set_shader_parameter("base_alpha",STYLE.ALPHA)
	material.set_shader_parameter("fade_seconds",STYLE.FADE_TIME);material.set_shader_parameter("hold_seconds",HOLD_SECONDS)
	material.set_shader_parameter("fade_near",STYLE.FADE_NEAR_M);material.set_shader_parameter("fade_full",STYLE.FADE_FULL_M)
	material.set_shader_parameter("edge_mask",STYLE._edge_mask())
	var quad:=QuadMesh.new();quad.material=material
	multimesh=MultiMesh.new();multimesh.transform_format=MultiMesh.TRANSFORM_3D;multimesh.mesh=quad;multimesh.instance_count=total*(capacity-1)
	for i in multimesh.instance_count:multimesh.set_instance_transform(i,Transform3D.IDENTITY)
	multimesh.custom_aabb=AABB(center-Vector3.ONE*reach,Vector3.ONE*reach*2)
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
func push_point(index:int,at:Vector3,time:float)->void:
	clock=time
	var n:=counts[index]
	if n==0:
		points.set_pixel(0,index,Color(at.x,at.y,at.z,time));last[index]=at;n=1
	elif last[index].distance_to(at)>=spacing and n<capacity-2:
		points.set_pixel(n,index,Color(at.x,at.y,at.z,time));last[index]=at;n+=1
	points.set_pixel(n,index,Color(at.x,at.y,at.z,time))
	counts[index]=n
	metadata.set_pixel(index,0,Color(n+1,0,0,1));dirty=true
func _process(_delta:float)->void:
	if material==null:return
	material.set_shader_parameter("simulation_time",clock)
	if dirty:
		dirty=false;points_texture.update(points);meta_texture.update(metadata)
