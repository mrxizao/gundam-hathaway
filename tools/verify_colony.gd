extends Node3D
var kept: Array[Resource] = []
var passed := 0
func check(condition: bool,label: String) -> void:
	assert(condition,label)
	passed += 1

func _ready() -> void:
	Settings.begin_isolated()
	for file in DirAccess.get_files_at("res://shaders"):
		if file.ends_with(".gdshader"):kept.append(load("res://shaders/"+file))
	var map := MapDef.colony_ruins()
	check(MapDef.versus_maps().has(map.id),"Map is selectable")
	check(MapDef.all_maps().has(map.id),"Map is registered")
	check(MapDef.by_id(map.id).code == "COLONY_RUINS","ID resolves to colony")
	check(not map.has_ground and map.body_radius == 0,"No ocean or Earth")
	check(map.cloud_density == 0,"No atmospheric cloud layers")
	Game.phase = Game.Phase.FIGHT
	Game.active_map = map
	var world := WorldBuilder.new()
	world.defer_initial_map = true
	add_child(world)
	world.apply_map(map)
	await get_tree().physics_frame
	var colony: Node3D = world.find_child("ColonyRuins",true,false)
	check(colony != null,"World builds imported colony")
	check(world.ocean == null,"No fallback islands or sea")
	check(colony.model.find_children("*","MeshInstance3D",true,false).size() == 213,"All active mesh objects imported")
	check(get_tree().get_nodes_in_group("colony_structure").size() == 195,"Solid structure collisions")
	var p := world.spawn_point(-95,world.match_spawn_radius(),world.match_player_alt())
	var foe := world.spawn_point_foe(p,85,world.match_spawn_radius())
	check(absf(p.z) < 2500 and absf(foe.z) < 2500,"Spawns inside the cylinder length")
	check(Vector2(p.x,p.y-12000).length() < 500,"Player in open central corridor")
	check(Vector2(foe.x,foe.y-12000).length() < 500,"Enemy in open central corridor")
	var sphere := SphereShape3D.new()
	sphere.radius = 18
	for position in [p,foe]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = sphere
		query.transform.origin = position
		query.collision_mask = 1
		check(get_world_3d().direct_space_state.intersect_shape(query).is_empty(),"Spawn has physical clearance")
	var storm = colony.lightning
	storm.set_process(false)
	check(storm.slots.size() == 4,"Bounded arc/audio/light pools")
	check(storm.sounds.size() == 3,"Three thunder variations")
	for sound in storm.sounds:
		check(sound.get_length() >= 3.9 and sound.data.size() > 10000,"Audible four-second thunder resource")
	check(storm.spawn_strike(true),"Interior arc generated")
	check(storm.spawn_strike(false),"Exterior arc generated")
	check(storm.strikes_inside == 1 and storm.strikes_outside == 1,"Both strike regions used")
	storm._process(1.6)
	check(storm.slots[0].audio.playing and storm.slots[1].audio.playing,"Thunder actually plays after flash delay")
	check(storm.slots[0].audio.bus == Settings.BUS_SFX,"Thunder follows sound-effect volume")
	for index in 12:
		for slot in storm.slots:slot.audio.stop();slot.sound_at=-1;slot.age=10
		storm.spawn_strike(index%2 == 0)
	check(storm.slots.size() == 4 and storm.get_child_count() == 12,"Repeated lightning cannot grow node count")
	Game.phase = Game.Phase.WIN
	storm._process(0.1)
	check(not storm.slots[0].mesh.visible and not storm.slots[0].audio.playing,"Storm quiet at results")
	var menu = load("res://scripts/ui/main_menu.gd").new()
	menu.suit_index = 0
	check(menu.active_map_list()[0] == map.id,"Thunderbolt menu offers colony first")
	menu.free()
	var old_choice: Dictionary = Net._choice.duplicate()
	var old_remote := Net.remote_suit
	Net._choice = {"suit":SuitProfile.Id.FULL_ARMOR_TB,"form":LanPlan.Form.ACE_DUEL}
	Net.remote_suit = SuitProfile.Id.PSYCHO_ZAKU_TB
	check(Net.match_map() == map.id,"LAN Thunderbolt uses the same colony map")
	Net._choice = old_choice
	Net.remote_suit = old_remote
	var storm_ref: WeakRef = weakref(storm)
	world.apply_map(MapDef.leo())
	check(storm_ref.get_ref() == null,"Changing maps frees lightning, lights and audio")
	world.queue_free()
	await get_tree().process_frame
	Settings.end_isolated()
	print("COLONY PASS ",passed," FAIL 0")
	get_tree().quit()
