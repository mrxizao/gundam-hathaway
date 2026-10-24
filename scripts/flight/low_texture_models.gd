extends RefCounted
## Generated texture-only variants. Original rigs, meshes and profile paths remain intact.
## Selection happens when a model is instantiated, never during the physics/render loop.
const DIRECTORY := "res://assets/models/low_spec/"
static func resolve_model(source:String)->String:
	if not Settings.low_spec_mode():return source
	var target:=DIRECTORY+source.md5_text()+".scn"
	if not ResourceLoader.exists(target):return source
	# A newly edited original must not be hidden by a stale generated cache.
	if FileAccess.get_modified_time(source)>FileAccess.get_modified_time(target):return source
	return target
