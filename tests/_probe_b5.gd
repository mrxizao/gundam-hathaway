extends Node
## **临时窄入口**（批 5 施工自检用）。**不是判据** —— 判据永远是
## `tests/test_runner.tscn` 的 `PASS / FAIL` 汇总行。
##
## 跑法：`godot --headless --path <工程> res://tests/_probe_b5.tscn`
##
## 选这几套的理由（每一条都对着一处改动）：
##   - `CameraFeedback` —— 本批主战场：新信号 `ifield_hit` + 护盾期抖动的
##                         可见性（§4.9.2⑤）。**放最前**：它自带场景实例化。
##   - `Damage`         —— `_apply_damage()` 被改了（新增一条 emit），
##                         两层减伤 / 效率表 / 打空护盾那几条必须原样绿
##   - `Abilities`      —— 护盾相关数值最密的套件（佩涅罗佩 ×1.30 等）
##   - `Round`          —— 结算与爆壳路径都走 `take_damage`
##
## ⚠️ 改了 `ChaseCamera` / `FlightBody` / `main.gd`：先跑 --import 刷缓存再跑本入口。

func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("========= GUNDAM 无头测试（批 5 窄入口，**不是判据**）=========")
	var t := T.new()
	await SuiteCameraFeedback.run(t, self)
	await SuiteDamage.run(t, self)
	await SuiteAbilities.run(t, self)
	await SuiteRound.run(t, self)
	print("============================================================")
	t.report()
	get_tree().quit(1 if t.failed > 0 else 0)
