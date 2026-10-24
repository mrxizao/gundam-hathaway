extends Node3D
## N44：把**指定骨**名下的网格全部隐藏后重渲，用来做「那个小方块是谁」的**净效应隔离**。
##
## ## 为什么这是个决定性实验
##
## `_n44_shot.tscn` 的图里，机体腿下方浮着一个无贴图灰方块，且**摆 `fly` / `slash`
## 它都停在原地** ⇒ 它一定挂在**不随动作动的骨**上（`Root` 一类）。
## 而 `_relay/pen_stray_scan.py` 显示 `bone == Root` 下恰好有 **7 件 2~3 三角形的碎片**。
##
## 于是判据很干脆：**隐藏 `Root` 名下的件 → 方块消失 ⇒ 归因成立**；
## 若方块还在 ⇒ 假设被证伪，再找别的骨。这比"从坐标反推屏幕位置"可靠得多
## （零件表与 `verify.txt` 的坐标列序不一致，反推容易翻车）。
##
## 跑法（不能加 `--headless`）：
##   godot --path <工程> res://tools/_n44_hide.tscn -- <输出目录> Root

const MAIN := "res://assets/models/penelope_movie/penelope_movie_rigged.scn"
const BG := Color(0.12, 0.14, 0.18)
const FOCUS := Vector3(0.0, 0.5, 0.0)
const RADIUS := 0.75

var _cam: Camera3D
var out_dir := "user://n44_hide"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = str(args[0])
	var hide_bones: Array = []
	for i in range(1, args.size()):
		hide_bones.append(str(args[i]))
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1280, 720))

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = BG
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.86, 0.88, 0.93)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var prof := SuitProfile.penelope()
	var ps := load(prof.model_path) as PackedScene
	var inst := ps.instantiate() as Node3D
	add_child(inst)
	var ma := ModelAnimator.setup(inst, prof.model_anim_files)
	ma.idle_action = prof.model_anim_idle
	ma.prepare_loops()

	var sk := _first_skeleton(inst)
	print("=== 骨 -> 网格件数（按件数降序）===")
	var by_bone := {}
	var total := 0
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.skin == null:
			continue
		total += 1
		var b := _sole_bone(mi, sk)
		var nm := str(b)
		by_bone[nm] = int(by_bone.get(nm, 0)) + 1
	print("  有蒙皮网格 %d 件" % total)
	var keys: Array = by_bone.keys()
	keys.sort_custom(func(a, b): return int(by_bone[a]) > int(by_bone[b]))
	for k in keys:
		print("  %-14s %3d 件" % [k, int(by_bone[k])])

	# 隐藏
	var hid := 0
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.skin == null:
			continue
		if hide_bones.has(_sole_bone(mi, sk)):
			mi.visible = false
			hid += 1
	print("★ 隐藏 %s 名下的网格 = %d 件" % [str(hide_bones), hid])

	_cam = Camera3D.new()
	_cam.fov = 34.0
	_cam.near = 0.02
	_cam.far = 200.0
	_cam.current = true
	add_child(_cam)

	if ma.has("fly"):
		ma.play_loop("fly", 0.0, true)
	await _frames(40)
	for v in [["front", 180.0, 6.0], ["left", 270.0, 8.0]]:
		await _place(float(v[1]), float(v[2]))
		await _save("hide%s_%s" % [str(hide_bones[0]) if hide_bones.size() > 0 else "none", str(v[0])])

	print("")
	print("VERDICT: N44-HIDE-DONE  → %s" % out_dir)
	get_tree().quit(0)


## ★ 坑：Godot 的 glTF 导入器给出的 `Skin` **bind 数为 0**（实测 328/328 件都是 `get_bind_count()==0`）。
##   本工程「每件一个顶点组、权重 1.0」的权重实际落在 **mesh 的 `ARRAY_BONES`/`ARRAY_WEIGHTS`** 里，
##   所以骨名只能从顶点数组反查（取权重 > 0.5 的那一个槽位）。用 `skin.get_bind_bone()` 会一路拿到 0 件。
func _sole_bone(mi: MeshInstance3D, sk: Skeleton3D) -> String:
	var names := {}
	for s in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(s)
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var n := bones.size() / 4
		for v in n:
			for k in 4:
				if wts[v * 4 + k] > 0.5:
					var b := bones[v * 4 + k]
					if b >= 0 and b < sk.get_bone_count():
						names[sk.get_bone_name(b)] = true
	if names.size() == 1:
		return str(names.keys()[0])
	if names.size() == 0:
		return "NOSKIN"
	return "MULTI(%d)" % names.size()


func _first_skeleton(n: Node) -> Skeleton3D:
	for c in n.find_children("*", "Skeleton3D", true, false):
		return c as Skeleton3D
	return null


func _place(az_deg: float, el_deg: float) -> void:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	var dir := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
	_cam.global_position = FOCUS + dir * RADIUS * 2.8
	_cam.look_at(FOCUS, Vector3.UP)
	await _frames(3)


func _save(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("    !! %s 取不到图" % tag)
		return
	var p: String = out_dir.path_join(tag + ".png")
	img.save_png(p)
	print("    saved %s" % p.get_file())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
