## 临时 parse 检查（跑完即删）。
##
## 为什么要有它：全套回归要跑 12 分钟，而**语法错误**只需 3 秒就能发现。
## 先在这里把"改过的每个脚本能否被 Godot 解析"过一遍，再去跑回归。
extends SceneTree

func _initialize() -> void:
	var paths := [
		"res://tests/suite_cruise_form.gd",
		"res://tests/suite_model_anim.gd",
		"res://scripts/flight/form_curve_modifier.gd",
		"res://scripts/flight/cruise_form_modifier.gd",
		"res://scripts/flight/model_anim.gd",
		"res://scripts/flight/flight_body.gd",
		"res://scripts/data/suit_profile.gd",
		"res://tools/xi_anim_probe.gd",
	]
	var bad := 0
	for p: String in paths:
		var s: Variant = load(p)
		# ⚠️ 判据**不能**只写 `s != null` —— Godot 对**解析失败**的脚本照样返回
		#    一个非 null 的 GDScript 对象。实测（2026-09-27，`tools/_probe_load.gd`）：
		#      坏脚本：null=false ｜ can_instantiate()=**false** ｜ methods=**0** ｜ base=""
		#      好脚本：null=false ｜ can_instantiate()=true   ｜ methods≥8 ｜ base=真基类
		#      不存在：null=true
		#    只判非 null ⇒ 闸门**恒真**，语法错被静默放过（本轮踩到）。
		var ok: bool = s is GDScript and (s as GDScript).can_instantiate()
		if not ok:
			bad += 1
		print("PARSE-%s  %s" % ["OK   " if ok else "**FAIL**", p])
	print("⇒ 失败 %d / %d" % [bad, paths.size()])
	print("VERDICT: PARSE-CHECK-%s" % ("PASS" if bad == 0 else "FAIL"))
	quit()
