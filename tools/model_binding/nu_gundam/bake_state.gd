extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var folder:="C:/Users/MSIPC/Documents/gundam/assets/models/nu_gundam/"
	var model:Node3D=load(folder+"nu_gundam.scn").instantiate();root.add_child(model)
	var shader:=Shader.new();shader.code="shader_type spatial;render_mode unshaded;void fragment(){ALBEDO=NORMAL*.5+.5;}"
	var mat:=ShaderMaterial.new();mat.shader=shader
	for mesh in model.find_children("*","MeshInstance3D",true,false):mesh.material_override=mat
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color.BLACK;root.add_child(env)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.6;root.add_child(camera)
	root.size=Vector2i(768,768);camera.position=Vector3(1.5,1.2,-3);camera.look_at(Vector3(-.07,.67,0))
	for index in 4:
		for mesh in model.find_children("NuDock*_*","MeshInstance3D",true,false):mesh.visible=index%2==0
		for prefix in ["NuShield_*","NuBazooka_*"]:
			for mesh in model.find_children(prefix,"MeshInstance3D",true,false):mesh.visible=index<2
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		var src:=root.get_texture().get_image();src.convert(Image.FORMAT_RGBA8)
		var ink:=Image.create(768,768,false,Image.FORMAT_RGBA8);ink.fill(Color.TRANSPARENT)
		for y in range(1,767):
			for x in range(1,767):
				var c:=src.get_pixel(x,y);var edge:=0.0
				for d in [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
					var n:=src.get_pixel(x+d.x,y+d.y);edge=maxf(edge,absf(c.r-n.r)+absf(c.g-n.g)+absf(c.b-n.b))
				ink.set_pixel(x,y,Color(1,1,1,smoothstep(.05,.35,edge)))
		ink=ink.get_region(ink.get_used_rect().grow(12).intersection(Rect2i(0,0,768,768)))
		ink.generate_mipmaps();var texture:=ImageTexture.create_from_image(ink)
		assert(ResourceSaver.save(texture,folder+"state_%d.res"%index,ResourceSaver.FLAG_COMPRESS)==OK)
		ink.save_png("C:/Users/MSIPC/Documents/Codex/2026-10-08/yeu/work/nu_state_%d.png"%index)
		print("NU STATE ",index)
	model.free();quit()
