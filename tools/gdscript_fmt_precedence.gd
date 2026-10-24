extends SceneTree
## 最小复现：GDScript 里「跨行的 `+` 与 `%`」到底怎么结合？
## 跑法：godot --headless --path . --script res://tools/gdscript_fmt_precedence.gd

func _initialize() -> void:
	var a := 77
	var b := 1.2833
	var c := 0.5

	# ① 单行、无拼接（对照组）
	print("① ", "v=%d f=%.2f" % [a, b])

	# ② 两个字符串字面量用 `+` 拼，`%` 在**第二段**之后（就是套件里那个写法）
	print("② ", "head %d/%.2f" 
		+ " tail %.4f"
		% [a, b, c])

	# ③ 先拼好再格式化（明确括号）
	var s := "head %d/%.2f" + " tail %.4f"
	print("③ ", s % [a, b, c])

	# ④ 括号把 `+` 括起来再 `%`
	print("④ ", ("head %d/%.2f" + " tail %.4f") % [a, b, c])

	quit()
