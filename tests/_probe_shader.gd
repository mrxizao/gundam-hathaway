extends SceneTree
## 一次性探针（批 19）：真渲染上下文里强制编译 cel_post，抓 shader 编译错误。
## 无头回归测不出 shader 编译失败（RenderingServer 是 dummy），必须开窗口跑。

func _init() -> void:
	var sh := load("res://shaders/cel_post.gdshader") as Shader
	print("probe: shader loaded = %s" % (sh != null))
	if sh == null:
		print("probe: RESULT=LOAD_FAILED")
		quit(1)
		return
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var rect := ColorRect.new()
	rect.material = mat
	rect.size = Vector2(64, 64)
	root.add_child(rect)
	# 等 5 帧：渲染线程真正编译 shader
	for i in 5:
		await process_frame
	print("probe: RESULT=RENDERED_5_FRAMES")
	quit(0)
