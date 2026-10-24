extends RefCounted
## Keep the hollow colony traversable through real openings, with solid double-sided surfaces.
const DEBRIS_COUNT := 32

static func _solid(mesh:MeshInstance3D,shape:ConcavePolygonShape3D)->void:
	shape.backface_collision=true
	var body:=StaticBody3D.new()
	body.name="ColonySolid"
	body.collision_layer=1;body.collision_mask=0
	var collision:=CollisionShape3D.new();collision.shape=shape
	body.add_child(collision);mesh.add_child(body)
	body.add_to_group("colony_structure")

static func prepare(model:Node3D)->void:
	var fragments:Array[MeshInstance3D]=[]
	var shapes:Dictionary={}
	for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if not mesh.visible or mesh.mesh==null:continue
		var bodies:=mesh.find_children("*","StaticBody3D",true,false)
		for body:StaticBody3D in bodies:
			body.collision_layer=1;body.collision_mask=0
			for collision:CollisionShape3D in body.find_children("*","CollisionShape3D",true,false):
				collision.disabled=false
				if collision.shape is ConcavePolygonShape3D:collision.shape.backface_collision=true
		if bodies.is_empty():
			var shape:=mesh.mesh.create_trimesh_shape()
			_solid(mesh,shape)
			shapes[mesh.mesh]=shape
		if str(mesh.name).begins_with("Animated fragment"):fragments.append(mesh)
	if fragments.is_empty():return
	var debris:=Node3D.new();debris.name="OuterColonyDebris";model.add_child(debris)
	var rng:=RandomNumberGenerator.new();rng.seed=240108
	for index in DEBRIS_COUNT:
		var source:=fragments[index%fragments.size()]
		var chunk:=MeshInstance3D.new();chunk.name="OuterWreck%02d"%index
		chunk.mesh=source.mesh;chunk.material_override=source.material_override
		for surface in source.mesh.get_surface_count():
			chunk.set_surface_override_material(surface,source.get_surface_override_material(surface))
		debris.add_child(chunk)
		# Evenly spaced outside the cylinder; no geometry in the central spawn corridor.
		var angle:=TAU*float(index)/DEBRIS_COUNT+rng.randf_range(-.06,.06)
		var radius:=rng.randf_range(1550,2600)
		var scale_factor:=rng.randf_range(.8,2.0)
		var orientation:=Basis.from_euler(Vector3(rng.randf_range(-PI,PI),rng.randf_range(-PI,PI),rng.randf_range(-PI,PI)))*scale_factor
		var center:=Vector3(cos(angle)*radius,sin(angle)*radius,rng.randf_range(-4100,4100))
		chunk.transform=Transform3D(orientation,center-orientation*source.mesh.get_aabb().get_center())
		if not shapes.has(source.mesh):shapes[source.mesh]=source.mesh.create_trimesh_shape()
		_solid(chunk,shapes[source.mesh])
