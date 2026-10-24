extends SceneTree
## 一次性工具：把 Godot 4.7.1 里 `Environment` 的**真实**属性名列出来。
##
## ⚠️ 为什么要这个工具：这批工程的规矩是"**属性名不猜**"。
## 踩过的坑 —— `StandardMaterial3D` 上**没有** `specular`（是 `metallic_specular`）、
## `ArrayMesh` **没有** `material`（要 `material_override`）：两次都是
## `--check-only` 语法闸查不出、只在真渲染时报 "Invalid assignment/set index"。
## 所以任何"我要 set 一个属性"的动作之前，先在这里 dump 一遍。
##
## 用法：
##   Godot_v4.7.1-stable_win64_console.exe --headless --path <工程> \
##     --script res://tools/dump_env_props.gd -- fog
##   第二个参数是**名字过滤**（可省，省了列全部）。
func _init() -> void:
	var filter := ""
	var argv := OS.get_cmdline_user_args()
	if argv.size() > 0:
		filter = argv[0].to_lower()

	var env := Environment.new()
	print("=== Environment 属性（过滤 '%s'）===" % filter)
	for p in env.get_property_list():
		var nm := String(p["name"])
		# 只列真正可写的脚本属性（跳过 category/group 这类组织用的条目）
		if p["type"] == TYPE_NIL:
			continue
		if not (p["usage"] & PROPERTY_USAGE_EDITOR):
			continue
		if filter != "" and not nm.to_lower().contains(filter):
			continue
		var val = env.get(nm)
		print("  %-42s type=%-3d  value=%s" % [nm, p["type"], str(val)])

	print("=== Viewport / WorldEnvironment 侧的相关开关 ===")
	print("  提示：体积雾在 Environment 上以 volumetric_fog_ 开头；")
	print("  高度雾是 fog_height / fog_height_density（与 fog_mode 无关，两者共存）。")
	quit()
