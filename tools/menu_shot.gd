extends Control
## 轮 42：菜单 / 读条「文案撤除」的真机判据图台。
##
## ⚠️ **为什么不去 boot `main.tscn`**（`probe_perf` / `missile_trail_shots` 那条路）：
## 2026-09-30 01:2x 并行会话正在改 `world_builder.gd` / `launch_script.gd`（发射台那批），
## `main.gd` 依赖它们 ⇒ **`main.tscn` 整棵起不来**（`Failed to compile depended scripts`）。
## 而本轮判据**只在菜单 + 读条上**，这两个都是自带 `_ready()`、`_draw()` 无守卫的 `Control`
##（`MainMenu`、`LoadingScreen`）⇒ 直接 `new` 出来挂树上就能画，不必等别人。
## ⚠️ 这也意味着本台子**只能验菜单/读条**，别拿它去验世界里的东西。
##
## 用法（**不能加 `--headless`**：dummy 渲染器截不出像素）：
##   Godot_v4.7.1-stable_win64_console.exe --path <工程> res://tools/menu_shot.tscn -- <输出目录>

## 每档多等几帧。⚠️ 轮 41 的教训：渲染历史（TAA）要几十帧才收敛，6 帧不够 ——
## 菜单是 2D 静态层，本来不敏感，但这一条别改小。
const SETTLE := 40

var _out := ""
var _menu: MainMenu
var _load: LoadingScreen


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://menu_shot"
	DirAccess.make_dir_recursive_absolute(_out)
	printerr("[menushot] out = %s" % _out)
	printerr("[menushot] viewport = %s" % str(get_viewport().get_visible_rect().size))
	await _run()
	printerr("[menushot] DONE")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## 截当前视口。⚠️ 必须等 `frame_post_draw`：早一帧拿到的还是上一帧的画布。
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png("%s/%s.png" % [_out, name])
	printerr("[menushot] %-18s %dx%d  err=%d" % [name, img.get_width(), img.get_height(), err])


func _run() -> void:
	# ============================================================ 菜单
	_menu = MainMenu.new()
	_menu.name = "MenuProbe"
	add_child(_menu)
	await _frames(4)
	printerr("[menushot] 菜单进树：visible=%s size=%s" % [str(_menu.visible), str(_menu.size)])

	# 每页取一次。索引都留默认（0），除敌人页外都不依赖下标。
	var pages: Array = [
		["01_模式页", MainMenu.Stage.MODE],
		["02_对战子页", MainMenu.Stage.BATTLE],
		["03_机体页", MainMenu.Stage.SUIT],
		["04_敌人页", MainMenu.Stage.ENEMY],
		["05_难度页", MainMenu.Stage.DIFFICULTY],
		["06_地图页", MainMenu.Stage.MAP],
		["07_训练页", MainMenu.Stage.TRAINING],
	]
	for p: Array in pages:
		_menu.stage = int(p[1])
		_menu.queue_redraw()
		await _frames(SETTLE)
		await _shot(str(p[0]))

	# ---- 敌人页换一台**不同型**的敌机：镜像提示那一行应当整条消失 ----
	# （`suit_index = 0` 是柯西，`ENEMY_SUITS[0]` 也是柯西 ⇒ 上面那张是镜像分支。）
	_menu.enemy_index = 1
	_menu.stage = MainMenu.Stage.ENEMY
	_menu.queue_redraw()
	await _frames(SETTLE)
	await _shot("08_敌人页_非镜像")

	# ---- 编队战：机体页/阵营页（按阵营过滤，卡片数会变）----
	_menu.mode_index = 1
	_menu.suit_index = 0
	_menu.stage = MainMenu.Stage.SUIT
	_menu.queue_redraw()
	await _frames(SETTLE)
	await _shot("09_机体页_编队战")
	_menu.mode_index = 0

	# ---- ★ 轮 44：机体卡 ⑦「燃料槽」那条文案（改过 ⇒ 必须出真机图）----
	#
	# ⚠️ 只有**梅萨族与古斯塔夫族**有燃料槽，而它们只在**编队战的阵营池**里可选：
	#   马夫蒂 = [柯西, 梅萨M01, 梅萨指挥官型, 梅萨F01]（量产机在**后**面）
	#   联邦   = [佩涅罗佩, 阿利宙斯, 古斯塔夫00]
	#   ⇒ `suit_index` 必须跟着池子走。写死 0 会截到柯西 / 佩涅罗佩，
	#     **⑦ 那一条根本不会画出来**（它只在 `has_jet_gauge` 的机上出现）。
	_menu.select_mode(Game.MatchMode.SQUAD)
	for trio: Array in [["12_机体页_马夫蒂_梅萨M01", 0, 1],
			["13_机体页_联邦_古斯塔夫00", 1, 2]]:
		_menu.side_index = int(trio[1])
		_menu.suit_index = int(trio[2])
		_menu.stage = MainMenu.Stage.SUIT
		_menu.queue_redraw()
		await _frames(SETTLE)
		await _shot(str(trio[0]))
	# ---- ★★ 轮 44：⑦「燃料槽」那条**正文**的真机渲染 ----
	#
	# ⚠️ 这是一个**探针摆位**，**不是可达界面** —— 必须写清楚，否则下一个人会以为玩家能这么进：
	#   · `SuitProfile.features()`（⑦ 那条的数据源）**只有一个绘制消费者**：`_draw_suit_features()`；
	#   · 它**只在训练页**被调（`_draw_training_stage()`）；
	#   · 而 `Stage.TRAINING` 只在 `training_mode()` 里可达 ⇒ 那一刻
	#     `side_filters_suits()` 为 false ⇒ 机体池 = `MainMenu.SUITS`
	#     = [柯西, 佩涅罗佩, 阿利宙斯]（三台 ACE，`suite_round17` 钉着不许放量产机）；
	#   · ⑦ 的渲染条件是 `has_jet_gauge` ⇒ 只有梅萨族 / 古斯塔夫为真。
	# ⇒ **「训练页 + 有槽的机体」这个组合当前导航流到不了**，⑦ 那条正文在成品里从来没被印出来过
	#   （pre-existing，不是本轮引入的）。
	# 但 `_draw()` 只按 `stage` 分派（**不按模式**，见 L2199）⇒ 把 `stage` 直接摆到 TRAINING、
	# 同时让机体池走阵营池，就能让生产的绘制函数去画生产的字符串。
	# 本轮要看的是**排版**（新正文比旧的长了一截 ⇒ 会不会冲出右边界），
	# 这件事只有像素能答。
	for trio2: Array in [["14_训练页探针_马夫蒂_梅萨M01", 0, 1],
			["15_训练页探针_联邦_古斯塔夫00", 1, 2]]:
		_menu.select_mode(Game.MatchMode.SQUAD)
		_menu.side_index = int(trio2[1])
		_menu.suit_index = int(trio2[2])
		_menu.stage = MainMenu.Stage.TRAINING
		_menu.queue_redraw()
		await _frames(SETTLE)
		await _shot(str(trio2[0]))
	# 把模式还回去 —— 本台子后面只剩读条，但别留脏状态给下一个人。
	_menu.select_mode(Game.MatchMode.VERSUS)
	_menu.side_index = 0
	_menu.suit_index = 0
	_menu.queue_redraw()

	_menu.queue_free()
	await _frames(3)

	# ============================================================ 读条
	_load = LoadingScreen.new()
	_load.name = "LoadingProbe"
	add_child(_load)
	await _frames(4)
	printerr("[menushot] 读条进树：visible=%s size=%s" % [str(_load.visible), str(_load.size)])
	_load.open("太平洋群岛 · 夜")
	await _frames(SETTLE)
	await _shot("10_读条_刚开")
	_load.advance(0.55, "重塑地表……")
	await _frames(SETTLE)
	await _shot("11_读条_半程")
	await _load.finish()
	await _frames(4)
	printerr("[menushot] 读条 finish 后 visible=%s" % str(_load.visible))
	_load.queue_free()
	await _frames(2)
