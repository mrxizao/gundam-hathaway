extends Node
## **临时**诊断（第十七轮）：量"踏板挂在骑手脚下"的实际几何关系。
##
## 为什么需要它：`FlightPedal._align_to_rider()` 的位置是从骑手的 `model_bounds`
## 反推的，而那个盒子**各机不同**（梅萨 22 m、佩涅罗佩含 FF 单元 32.5 m、
## 阿利宙斯包围盒还带一圈垂直尾翼）。光看游戏里的夜景截图分不出
## "插进机体里"和"稳稳托在脚下"，所以这里把两个包围盒都打出来对。
##
## 跑法（不能加 --headless，要真渲染）：
##   godot --path <工程> res://tools/round17_pedal_probe.tscn -- <输出目录>

const SHOT_W := 900
const SHOT_H := 700
var out_dir := "user://round17_pedal_probe"
var _idx := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(SHOT_W, SHOT_H))
	await get_tree().physics_frame

	# 干净环境：中亮灰背景（和 `model_shots` 同一套，能同时看清亮件和黑色废料）
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.58, 0.60, 0.64)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.86)
	env.ambient_light_energy = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 128, 0)
	sun.light_energy = 1.6
	add_child(sun)

	await _probe(SuitProfile.messer_m01(), false)
	await _probe(SuitProfile.messer_m01(), true)
	await _probe(SuitProfile.penelope(), true)
	await _probe(SuitProfile.xi(), true)
	print("PEDAL_PROBE_DONE -> ", out_dir)
	get_tree().quit(0)


func _probe(suit: SuitProfile, with_pedal: bool) -> void:
	var holder := Node3D.new()
	add_child(holder)
	var fb := BanditAI.new()
	fb.name = "Probe%d" % _idx
	fb.team = 1
	fb.profile = suit
	fb.difficulty = Difficulty.make(Difficulty.Level.NORMAL)
	fb.projectile_container = holder
	holder.add_child(fb)
	fb.global_position = Vector3(0.0, 3000.0, 0.0)
	fb.set_physics_process(false)
	await get_tree().physics_frame

	var b: AABB = fb.model_bounds
	var tag := "%s%s" % [suit.display_name, " + 踏板" if with_pedal else ""]
	print("\n==== %s ====" % tag)
	print("  骑手 model_bounds: pos.y=%.2f  size=%s  下沿 y=%.2f  上沿 y=%.2f" % [
		b.position.y, str(b.size), b.position.y, b.position.y + b.size.y])

	if with_pedal:
		fb.configure_pedal()
		await get_tree().physics_frame
		var pd: FlightPedal = fb.pedal
		if pd == null:
			print("  ⚠️ 踏板没挂上")
		else:
			var pbox := _aabb_of(pd)
			print("  踏板 节点 position.y = %.2f  scale = %.3f" % [pd.position.y, pd.scale.y])
			print("  踏板 本机包围盒: size=(%.2f, %.2f, %.2f)  局部下沿 y=%.2f 上沿 y=%.2f" % [
				pbox.size.x, pbox.size.y, pbox.size.z, pbox.position.y, pbox.position.y + pbox.size.y])
			var gap := b.position.y - (pbox.position.y + pbox.size.y)
			print("  踏板 节点数=%d 网格数=%d 可见=%s" % [
				pd.get_child_count(),
				pd.find_children("*", "MeshInstance3D", true, false).size(),
				str(pd.visible)])
			print("  → 骑手下沿 − 踏板上沿 = %.2f m" % gap)
			if gap < 0.0:
				print("  ⚠️ 踏板**插进机体** %.2f m —— 对位公式有错" % absf(gap))
			elif gap > 3.0:
				print("  ⚠️ 踏板离脚底太远（%.2f m 的空隙），看着会像悬空" % gap)
			else:
				print("  ✅ 踏板托在脚下，空隙 %.2f m" % gap)

	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.near = 0.02
	cam.far = 4000.0
	add_child(cam)
	cam.current = true
	# 取景照抄 `tools/model_shots.gd`（那套已经证明能拍全）。
	var box_all := b
	if with_pedal and fb.has_pedal():
		box_all = box_all.merge(_aabb_of(fb.pedal))
	var focus := box_all.get_center()
	var radius := maxf(box_all.size.length() * 1.6, 0.05)
	var a := deg_to_rad(215.0)
	cam.global_position = focus + Vector3(sin(a) * radius, radius * 0.25, cos(a) * radius)
	cam.look_at(focus, Vector3.UP)
	print("  相机 pos=%s focus=%s r=%.2f 视口=%s" % [
		str(cam.global_position.round()), str(focus.round()), radius,
		str(get_viewport().get_visible_rect().size)])
	# ⚠️ **这个探针拍不出可用截图**（试了三版：`current` 入树顺序、取景半径、
	# 显式 viewport 尺寸，拍出来都是一片背景灰，四张图字节完全相同）。
	# 不再和它缠斗：它的价值在**数字**（上面那两个包围盒的对位量），
	# 而"踏板长什么样、挂得对不对"由游戏内截图（`round17_shots.tscn`）与
	# 模型四方位图（`model_shots.tscn`）负责。下面这段抓图保留着，
	# 万一以后换了渲染后端能用了就有现成的。
	for i in 4:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	_idx += 1
	var img := get_viewport().get_texture().get_image()
	if img != null:
		var p := out_dir.path_join("%02d_%s.png" % [_idx,
			tag.replace(" ", "_").replace("·", "")])
		print("  SHOT %s err=%d" % [p, img.save_png(p)])
	cam.queue_free()
	holder.queue_free()
	await get_tree().physics_frame


## 节点在**自己父节点坐标系**下的可见网格包围盒（与 `FlightBody._measure_visible_meshes` 同口径）。
func _aabb_of(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv: Transform3D = n.get_parent().global_transform.affine_inverse()
	for c: Node in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var a: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out
