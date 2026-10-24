extends RefCounted
## Compact, bounded native samples; never retain full mesh arrays or live models.
const MAX_POINTS:=131072
const MAX_ENTRIES:=96
static var entries:Dictionary={}
static var point_count:=0
static var reads:=0
static func invalidate(id:int)->void:
	if entries.has(id):point_count-=int(entries[id].points.size());entries.erase(id)
static func clear()->void:
	entries.clear();point_count=0;reads=0
static func sample(mesh:Mesh)->PackedVector3Array:
	if mesh==null:return PackedVector3Array()
	var id:=mesh.get_instance_id()
	if entries.has(id):
		if entries[id].mesh.get_ref()==mesh:return entries[id].points
		invalidate(id)
	var points:=PackedVector3Array()
	for surface in mesh.get_surface_count():
		var vertices:PackedVector3Array=mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		reads+=1
		for index in range(0,vertices.size(),maxi(1,vertices.size()/1600)):points.append(vertices[index])
	if points.size()<=MAX_POINTS:
		while not entries.is_empty() and (entries.size()>=MAX_ENTRIES or point_count+points.size()>MAX_POINTS):invalidate(entries.keys()[0])
		entries[id]={"mesh":weakref(mesh),"points":points};point_count+=points.size()
		# Invalidate editor/procedural changes without keeping the mesh alive.
		var callback:=invalidate.bind(id)
		if not mesh.changed.is_connected(callback):mesh.changed.connect(callback,CONNECT_ONE_SHOT)
	return points
