extends RefCounted
class ConfigMain extends "res://scripts/main.gd":
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
static func run(t:T,host:Node)->void:
	Settings.begin_isolated();Game.reset();Net.close()
	t.suite("Axis restriction / both selected suits, never one alone")
	var main:=ConfigMain.new();host.add_child(main);main.set_process(false)
	var menu:=MainMenu.new();host.add_child(menu);menu.set_process(false);menu.mode_index=0
	for local in [SuitProfile.Id.NU_GUNDAM,SuitProfile.Id.SAZABI,SuitProfile.Id.XI]:
		for remote in [SuitProfile.Id.NU_GUNDAM,SuitProfile.Id.SAZABI,SuitProfile.Id.XI,SuitProfile.Id.PENELOPE]:
			var restricted:bool=local in [SuitProfile.Id.NU_GUNDAM,SuitProfile.Id.SAZABI] and remote in [SuitProfile.Id.NU_GUNDAM,SuitProfile.Id.SAZABI]
			Net.announce_choice(local,0,LanPlan.Form.ACE_DUEL);Net.remote_suit=remote;Net.remote_side=1;Net.remote_form=LanPlan.Form.ACE_DUEL
			t.ok(Net.valid_pair(),"both special and mixed rooms remain readyable")
			t.eq(Net.requires_axis(local,remote),restricted,"shared rule requires both special suits")
			t.eq(Net.match_map(),MapDef.Id.AXIS if restricted else MapDef.Id.PACIFIC,"LAN map agrees with pair-only rule")
			menu.suit_index=MainMenu.SUITS.find(local);menu.enemy_index=menu.enemy_pool().find(remote)
			t.eq(menu.active_map_list(),[MapDef.Id.AXIS] if restricted else MapDef.versus_maps(),"offline map selection remains unrestricted for one special suit")
			for mode in [Game.MatchMode.VERSUS,Game.MatchMode.LAN]:
				main._resolve_match(local,Difficulty.Level.NORMAL,MapDef.Id.DAVAO,mode,remote)
				t.eq(Game.active_map.id,MapDef.Id.AXIS if restricted else MapDef.Id.DAVAO,"actual match preserves selected map for mixed pair")
		menu.suit_index=MainMenu.SUITS.find(local);Net.remote_suit=-1
		t.not_ok(Net.requires_axis(local,-1),"pending remote choice cannot impose restriction")
	Net.announce_choice(SuitProfile.Id.GP03D,1,LanPlan.Form.ACE_DUEL);Net.remote_suit=SuitProfile.Id.NEUE_ZIEL
	t.ok(Net.valid_pair(),"large MA pairing remains supported");t.eq(Net.match_map(),MapDef.Id.LEO,"large MA keeps orbit")
	Net.remote_suit=SuitProfile.Id.SAZABI;t.not_ok(Net.valid_pair(),"large MA restriction remains intact")
	for suit in [SuitProfile.Id.NU_GUNDAM,SuitProfile.Id.SAZABI]:
		t.ok(Net.valid_room_choice(suit,0,LanPlan.Form.ACE_DUEL),"both suits retain LAN eligibility")
		main._resolve_match(suit,Difficulty.Level.NORMAL,MapDef.Id.AXIS,Game.MatchMode.TRAINING)
		t.eq(Game.active_map.id,MapDef.Id.RANGE,"training keeps dedicated map")
	main.queue_free();menu.queue_free();Net.close();Game.reset();Settings.end_isolated()
	await host.get_tree().process_frame;await host.get_tree().process_frame
