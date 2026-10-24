extends Node
## **着色器编译 lint** —— 把 `res://shaders/` 下每一份 `.gdshader` 都真编译一次。
##
## ## 为什么需要它（2026-09-30 的教训）
## `shaders/rocket_flame.gdshader` 里写着 GDScript 的 `:=`（GLSL 里没有这种东西）⇒
## 整份着色器**编译失败**，那条火焰**一个像素都不画**。
##
## 而当时的状况是：
##   · `suite_rocket_launch` 里 **42 条**火焰断言**全绿**（它们查的是源码子串与节点结构）；
##   · 全量回归 **8543 PASS / 0 FAIL**；
##   · 引擎只在 stderr 打一行 `SHADER ERROR: Expected a ',' or ';'`，
##     **不会让任何一条断言变红**（GDScript 侧没有"这份 shader 编过了吗"的 API）。
## ⇒ "这段特效做没做"与"这段特效编译失败"在测试报告里**长得一模一样**。
##
## ## 它的办法：让它被编译，然后**去日志里 grep**
## 判据不在这个脚本里（它没法读自己的 stderr）—— 判据是：
##   ```
##   godot --headless --path . res://tools/_shader_lint.tscn 2>&1 | grep "SHADER ERROR"
##   ```
## 有输出 = 有坏掉的着色器，而且 Godot 会把**文件与行号**一起打出来。
##
## ## ⚠️ 为什么必须真的挂进树
## 只 `load()` 一份 `Shader` **不会**触发编译（延迟到第一次被某份材质推给渲染服务器）。
## ⇒ 这里给每份着色器造一个 `ShaderMaterial` + 一个 `BoxMesh` 并 `add_child()`。
## ⚠️ 无头（dummy 渲染器）下这一步是**同步**编译，所以跑完 `await` 两帧就够；
## 带窗口时是异步的，所以留 10 帧。
##
## 跑法（headless 就够，这个 lint 与画面对不对无关）：
##   godot --headless --path <工程> res://tools/_shader_lint.tscn

func _ready() -> void:
	var dir := DirAccess.open("res://shaders")
	if dir == null:
		# ⚠️ 文案里不许出现未转义的 ASCII 双引号（GDScript 会报 `Expected closing ")"`）。
		push_error("打不开 res://shaders ⇒ 这个 lint 什么都没检查（而它看起来是「通过」）")
		get_tree().quit(1)
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".gdshader"):
			names.append(f)
		f = dir.get_next()
	names.sort()
	var bad := 0
	for nm in names:
		var p := "res://shaders/" + nm
		var sh := load(p) as Shader
		if sh == null:
			push_error("载不到着色器：%s" % p)
			bad += 1
			continue
		var mat := ShaderMaterial.new()
		mat.shader = sh
		var mi := MeshInstance3D.new()
		mi.name = nm.get_basename()
		mi.mesh = BoxMesh.new()
		# ⚠️ 用 `material_override`（节点级）而不是 `mesh.material`：
		# 这里的唯一目的是"把它推给渲染服务器一次"，节点级最不容易和别人的材质混。
		mi.material_override = mat
		add_child(mi)
	# ⚠️⚠️ 这一行**不许出现**那个要 grep 的字符串本身（`SHADER` + 空格 + `ERROR`）——
	# 写了它，`grep -c` 至少回 1，于是这个 lint **永远"有错"**，
	# 而"永远有错"的判据等于没有判据（会被当成噪声忽略掉）。第一版就是这么写的。
	print("SHADER_LINT 已提交编译 %d 份着色器（%d 份载入失败）⇒ 下面若有编译器报错就是坏的那几份"
		% [names.size(), bad])
	# ⚠️ 无头下同步编译，这一等只是保证渲染服务器的命令队列被冲掉。
	for i in 10:
		await get_tree().physics_frame
	print("SHADER_LINT_DONE")
	get_tree().quit(0)
