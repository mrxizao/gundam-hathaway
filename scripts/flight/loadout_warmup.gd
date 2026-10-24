extends RefCounted
## Read only the selected loadout, with at most two IO jobs and no global pinning.
const MAX_JOBS:=2
static func paths(ids:Array)->Array[String]:
	var result:Array[String]=[]
	if FlightBody.use_placeholder:return result
	for id in ids:
		if int(id)<0:continue
		var profile:=SuitProfile.by_id(int(id))
		var list:Array[String]=[]
		if not profile.model_path.is_empty():list.append(profile.model_path)
		if profile.id==SuitProfile.Id.SAZABI:
			for weapon in ["shotgun","sniper","shield","axe"]:list.append("res://data/sazabi_models/"+weapon+".scn")
		for path in list:
			var resolved:=preload("res://scripts/flight/low_texture_models.gd").resolve_model(path)
			if not result.has(resolved) and ResourceLoader.exists(resolved):result.append(resolved)
	return result
static func warm(owner:Node,requested:Array[String],progress:Callable=Callable())->Array[Resource]:
	var held:Array[Resource]=[];var pending:Array[String]=[];var active:Array[String]=[]
	for path in requested:
		if not pending.has(path):pending.append(path)
	var total:=pending.size();var done:=0;var tree:=owner.get_tree()
	while not pending.is_empty() or not active.is_empty():
		while active.size()<MAX_JOBS and not pending.is_empty():
			var path:String=pending.pop_front()
			if ResourceLoader.has_cached(path):
				var cached:=ResourceLoader.load(path)
				if cached!=null:held.append(cached)
				done+=1;continue
			var error:=ResourceLoader.load_threaded_request(path,"PackedScene",false)
			if error in [OK,ERR_BUSY]:active.append(path)
			else:done+=1;push_warning("Loadout warmup unavailable: "+path)
		for i in range(active.size()-1,-1,-1):
			var status:=ResourceLoader.load_threaded_get_status(active[i])
			if status==ResourceLoader.THREAD_LOAD_IN_PROGRESS:continue
			if status==ResourceLoader.THREAD_LOAD_LOADED:
				var resource:=ResourceLoader.load_threaded_get(active[i])
				if resource!=null:held.append(resource)
			else:push_warning("Loadout resource failed: "+active[i])
			active.remove_at(i);done+=1
		if progress.is_valid():progress.call(done,total)
		if not pending.is_empty() or not active.is_empty():await tree.process_frame
	return held
