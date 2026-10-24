extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var model := (load("res://assets/models/gp03d_v2/gp03d_v2.scn") as PackedScene).instantiate()
	root.add_child(model)
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded; void fragment(){ ALBEDO=NORMAL*0.5+0.5; }"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for mi: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		mi.material_override = mat
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	world.environment = env
	root.add_child(world)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 158.0
	root.add_child(cam)
	root.size = Vector2i(768,768)
	cam.position = Vector3(125,160,-155)
	cam.look_at(Vector3(0,2,6))
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("C:/Users/MSIPC/Documents/Codex/2026-10-07/c-users-msipc-documents-gundam-2/work/gp03d_v2/state_preview.png")
	img.convert(Image.FORMAT_RGBA8)
	var src: Image = img.duplicate()
	img = Image.create(768,768,false,Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	var box := Rect2i()
	for y in range(1,img.get_height()-1):
		for x in range(1,img.get_width()-1):
			var c := src.get_pixel(x,y)
			var edge := 0.0
			for step in [Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0),Vector2i(0,-1)]:
				var neighbor := src.get_pixel(x+step.x,y+step.y)
				edge = maxf(edge,absf(c.r-neighbor.r)+absf(c.g-neighbor.g)+absf(c.b-neighbor.b))
			var alpha := smoothstep(0.035,0.35,edge)
			img.set_pixel(x,y,Color(1,1,1,alpha))
	box = img.get_used_rect().grow(6).intersection(Rect2i(0,0,img.get_width(),img.get_height()))
	img = img.get_region(box)
	var preview := img.duplicate() as Image
	for y in preview.get_height():
		for x in preview.get_width():
			var a := preview.get_pixel(x,y).a
			preview.set_pixel(x,y,Color(a,a,a,1))
	preview.save_png("C:/Users/MSIPC/Documents/Codex/2026-10-07/c-users-msipc-documents-gundam-2/work/gp03d_v2/line_preview.png")
	img.generate_mipmaps()
	var texture := ImageTexture.create_from_image(img)
	assert(ResourceSaver.save(texture,"res://assets/models/gp03d_v2/state.res",ResourceSaver.FLAG_COMPRESS)==OK)
	img.save_png("C:/Users/MSIPC/Documents/Codex/2026-10-07/c-users-msipc-documents-gundam-2/work/gp03d_v2/state.png")
	quit()
