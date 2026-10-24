extends Node
## **临时窄入口**（批 3 施工自检用）。**不是判据** —— 判据永远是
## `tests/test_runner.tscn` 的 `PASS / FAIL` 汇总行。
##
## 为什么需要它：全量入口要十几分钟，而批 3 的改动面只压在这几套上 ——
## 改一个尾迹档位不值得等一轮全量。跑完**必须**再跑一次全量（否则"没红"只说明这几套没红）。
##
## 跑法：`godot --headless --path <工程> res://tests/_probe_b3.tscn`
##
## 选这几套的理由（每一条都对着一处改动）：
##   - `Flight`         —— suite_flight 新增了「手感基线」一节（§4.5）
##   - `Ballistics`     —— 弹丸/导弹的公共数学
##   - `Combat`         —— 导弹的生成与近炸（missile.gd 改了 `_ready` / `_detonate`）
##   - `Layout`         —— HUD 对齐线（§4.7 会往 UILayout 加东西）
##   - `MultiLock`      —— `fire_funnel()` 是它改坏的**第一现场**（加了弹射烟）
##   - `CameraFeedback` —— `_emit_full_salvo_shot()` 是它改坏的**第一现场**（加了档位参数）
##   - `HudInstruments` —— 批 2 的，防回退
##   - `MissileSmoke`   —— 本批新增（§4.4）
##   - `UiStyle`        —— 本批新增（§4.7）—— 它扫源码，所以也会抓到
##                         `hud.gd` 被别处改坏（右对齐 / 描边宽度 / 线宽）

func _ready() -> void:
	await get_tree().process_frame
	print("")
	print("========= GUNDAM 无头测试（批 3 窄入口，**不是判据**）=========")
	var t := T.new()
	SuiteFlight.run(t)
	SuiteBallistics.run(t)
	await SuiteCombat.run(t, self)
	SuiteLayout.run(t, self)
	await SuiteMultiLock.run(t, self)
	await SuiteCameraFeedback.run(t, self)
	await SuiteHudInstruments.run(t, self)
	await SuiteMissileSmoke.run(t, self)
	SuiteUiStyle.run(t, self)
	print("============================================================")
	t.report()
	get_tree().quit(1 if t.failed > 0 else 0)
