extends Node
## 轮 54 探针：剧情关里**玩家开局骑不骑飞行踏板** —— 逐关实测，不靠读代码推。
##
## 为什么必须实测：`_spawn_side()` 里给玩家配板的那一行藏在
## `if u.owner_is_player:` 分支里，而那个标记由 `BattleFormation.lineup()`
## 的四合一条件决定（`has_player and not player_is_ace and sq == 0 and sl == 0`）。
## M01 撒友军编队（`has_allies()`）⇒ 名单里有玩家那一格 ⇒ 顺带骑上板；
## M02 不撒友军 ⇒ 那条路根本不会被走到。
## 但"哪几关有、哪几关没有"这种事靠推理迟早翻车，所以这里把每一关都打一遍读数。
##
## 跑法（无头即可，只打读数、不抓图）：
##   godot --headless --path <工程> res://tools/_r54_pedal_probe.tscn
##
## ⚠️ 无头下 `_launch_match()` 会真的建图建单位（测试套件走的就是这条路），
## 但**不会**产生任何画面 —— 这里要的就是数字。

const MS := preload("res://scripts/data/mission_script.gd")

const IDS := ["M01", "M02", "M03", "M04", "M05", "M06", "M07"]


func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().physics_frame
	# 存档隔离：`_launch_match()` 不写档，但 `_resolve_campaign_match()` 会读
	# `Game.campaign_progress` —— 用一份全解锁的进度，免得"需通关上一关"把某关拦掉。
	Game.campaign_progress = _all_cleared()
	for id in IDS:
		await _probe(main, id)
	print("R54_PROBE_DONE")
	get_tree().quit(0)


## 一份"七关全已通关 + 军资充足"的进度（只喂给内存里的 `Game`，不落盘）。
func _all_cleared() -> Dictionary:
	var p := {"cleared": {}, "credits": 99999}
	for id in IDS:
		p["cleared"][id] = true
	return p


func _probe(main: Node, id: String) -> void:
	if not bool(main.call("_resolve_campaign_match", id)):
		print("[%s] ★ _resolve_campaign_match 返回 false（关卡被拦）" % id)
		return
	main.call("_launch_match")
	for i in 40:
		await get_tree().physics_frame
	var pl = main.get("player")
	if pl == null or not is_instance_valid(pl):
		print("[%s] ★ player 没起来（这一关拍不到读数）" % id)
		return
	var m: MS.Mission = Game.active_mission
	var board: FlightPedal = pl.pedal_owner() if pl.has_pedal() else null
	print("[%s] suit=%-14s map=%-9s ang=%7.1f  玩家有板=%-5s 板型=%-8s 板上骑手=%d"
		% [id, str(pl.profile.id_name()), str(Game.active_map.name_cn),
			m.spawn_angle_deg if m != null else 0.0,
			str(pl.has_pedal()),
			FlightPedal.kind_name(board.kind) if board != null else "—",
			board.riders.size() if board != null else 0])
	# ---- 敌机：`_attach_ai()` 的 `with_pedal` 默认 true ⇒ 量产机应当**本来就有板** ----
	var foes := Game.live_hostiles_of(pl)
	var no_board: Array = []
	for f in foes:
		if f == null or not is_instance_valid(f) or f.profile == null:
			continue
		var fb: FlightPedal = f.pedal_owner() if f.has_pedal() else null
		print("      敌机 %-14s 有板=%-5s 板型=%-8s 可骑=%s"
			% [str(f.profile.id_name()), str(f.has_pedal()),
				FlightPedal.kind_name(fb.kind) if fb != null else "—",
				str(f.profile.can_ride_pedal())])
		if f.profile.can_ride_pedal() and not f.has_pedal():
			no_board.append(str(f.profile.id_name()))
	# ---- 友军（M01 的编队）：量产僚机也应当在板上 ----
	var n_ally := 0
	var ally_no_board: Array = []
	for u in units_root_children(main):
		if u == pl or not (u is FlightBody) or u.profile == null:
			continue
		if u.team != 0:
			continue
		n_ally += 1
		if u.profile.can_ride_pedal() and not u.has_pedal():
			ally_no_board.append(str(u.profile.id_name()))
	print("      友军 %d 台 · 其中该有板却没有的：%s" % [n_ally, str(ally_no_board)])
	print("      ★ 该有板却没有的敌机：%s" % str(no_board))


## `units_root` 的子节点（玩家/僚机/敌机都在这里 —— 与 `Game.live_hostiles_of()` 无关）。
func units_root_children(main: Node) -> Array:
	var root: Node = main.get("units_root")
	if root == null or not is_instance_valid(root):
		return []
	return root.get_children()
