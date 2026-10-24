extends RefCounted
## Swept broad phase only. Callers retain their original exact hit tests and order.
const CELL_SIZE:=512.0
const MAX_QUERY_CELLS:=64
const MAX_MISSILE_CELLS:=64
static var tick:=-1
static var snapshot:Array=[]
static var cells:Dictionary={}
static var nodes:Dictionary={}
static var ranks:Dictionary={}
static var wide:Dictionary={}
static func clear()->void:
	tick=-1;snapshot=[];cells.clear();nodes.clear();ranks.clear();wide.clear()
static func cell(point:Vector3)->Vector3i:
	return Vector3i(floori(point.x/CELL_SIZE),floori(point.y/CELL_SIZE),floori(point.z/CELL_SIZE))
static func insert(node:Node3D)->void:
	var id:=node.get_instance_id()
	var previous=node.get("_prev_pos")
	var current:=node.global_position
	if not previous is Vector3 or previous==Vector3.ZERO:previous=current
	var lo:=cell(current.min(previous));var hi:=cell(current.max(previous))
	var size:=hi-lo+Vector3i.ONE
	if size.x*size.y*size.z>MAX_MISSILE_CELLS:wide[id]=true;return
	for x in range(lo.x,hi.x+1):
		for y in range(lo.y,hi.y+1):
			for z in range(lo.z,hi.z+1):
				var key:=Vector3i(x,y,z)
				if not cells.has(key):cells[key]={}
				cells[key][id]=true
static func moved(node:Node3D)->void:
	# Multiple physics substeps have distinct ticks. Within a step keep both old
	# and new cells, so processing order cannot hide a crossing projectile.
	if tick==Engine.get_physics_frames() and nodes.has(node.get_instance_id()):insert(node)
static func forget(node:Node3D)->void:
	var id:=node.get_instance_id();nodes.erase(id);ranks.erase(id);wide.erase(id)
	if nodes.is_empty():clear()
static func query(tree:SceneTree,from:Vector3,to:Vector3,radius:float)->Array:
	var members:=Game.group_snapshot(tree,"missiles")
	if members.size()<12:return members
	# Manual tooling may teleport projectiles between queries; the native physics
	# path sends moved() after every movement. Keep the original path outside it.
	if not Engine.is_in_physics_frame():return members
	if tick!=Engine.get_physics_frames() or not is_same(snapshot,members):
		clear();tick=Engine.get_physics_frames();snapshot=members
		for i in members.size():
			var node=members[i]
			if not is_instance_valid(node) or not node is Node3D:continue
			var id:int=node.get_instance_id();nodes[id]=node;ranks[id]=i;insert(node)
	# Extra broad-phase margin absorbs float rounding at large orbital coordinates.
	var expansion:=Vector3.ONE*(maxf(radius,0)+1.0)
	var lo:=cell(from.min(to)-expansion);var hi:=cell(from.max(to)+expansion)
	var size:=hi-lo+Vector3i.ONE
	if size.x*size.y*size.z>MAX_QUERY_CELLS:return members
	var found:Dictionary=wide.duplicate()
	for x in range(lo.x,hi.x+1):
		for y in range(lo.y,hi.y+1):
			for z in range(lo.z,hi.z+1):
				var bucket:Dictionary=cells.get(Vector3i(x,y,z),{})
				if bucket.size()*5>=members.size()*3:return members
				for id in bucket:found[id]=true
	if found.size()*5>=members.size()*3:return members
	var ordered:Array=[]
	for id in found:
		if nodes.has(id) and is_instance_valid(nodes[id]):ordered.append(id)
	ordered.sort_custom(func(a,b):return int(ranks[a])<int(ranks[b]))
	var result:Array=[]
	for id in ordered:result.append(nodes[id])
	return result
