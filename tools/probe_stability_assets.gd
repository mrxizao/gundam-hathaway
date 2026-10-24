extends Node
var gaps:Array[float]=[]
func _process(delta:float)->void:gaps.append(delta)
func payload(root:Node)->int:
	var seen:Dictionary={};var bytes:=0
	for node in root.find_children("*","MeshInstance3D",true,false):
		var materials:Array=[]
		for i in node.mesh.get_surface_count():materials.append(node.get_active_material(i))
		for material in materials:
			if material==null:continue
			for property in material.get_property_list():
				if property.type!=TYPE_OBJECT:continue
				var value=material.get(property.name)
				if value is Texture2D and not seen.has(value.get_instance_id()):
					seen[value.get_instance_id()]=true
					var image:Image=value.get_image()
					if image!=null:bytes+=image.get_data_size()
	return bytes
func _ready()->void:
	Settings.begin_isolated();var original:=0;var reduced:=0
	for name in ["normal","shotgun","sniper","shield","axe"]:
		var source:String="res://data/sazabi_models/"+name+".scn"
		var target:String="res://assets/models/low_spec/"+source.md5_text()+".scn"
		var a:PackedScene=ResourceLoader.load(source,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
		var root:=a.instantiate();var before:=payload(root);root.free();a=null
		var b:PackedScene=ResourceLoader.load(target,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
		root=b.instantiate();var after:=payload(root);root.free();b=null
		original+=before;reduced+=after
		print("TEXTURE_PAYLOAD ",name," original_bytes=",before," low_bytes=",after)
		await get_tree().process_frame
	print("TEXTURE_TOTAL original_bytes=",original," low_bytes=",reduced)
	Settings.set_quality_preset(0);FlightBody.use_placeholder=false
	gaps.clear();var start:=Time.get_ticks_msec()
	var resources:=await preload("res://scripts/flight/loadout_warmup.gd").warm(self,preload("res://scripts/flight/loadout_warmup.gd").paths([SuitProfile.Id.SAZABI]))
	print("REAL_WARMUP resources=",resources.size()," elapsed_ms=",Time.get_ticks_msec()-start," ui_frames=",gaps.size())
	resources.clear();Settings.end_isolated();get_tree().quit()
