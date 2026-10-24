extends RefCounted
static func run(t: T, host: Node) -> void:
	t.suite("LAN ready room / canonical deployment and MA rules")
	Settings.begin_isolated()
	var saved_choice: Dictionary = Net._choice.duplicate()
	var saved_team := Net.local_team
	var saved_remote := [Net.remote_suit,Net.remote_side,Net.remote_form]
	var main: Node = load("res://scripts/main.gd").new()
	for pair in [[0,1,0,1],[0,0,0,0],[3,3,0,0]]:
		var host_suit: int = pair[0]
		var guest_suit: int = pair[1]
		var host_side: int = pair[2]
		var guest_side: int = pair[3]
		var signatures: Array = []
		for team in [0,1]:
			Net.local_team = team
			Net._choice = {"suit":host_suit if team == 0 else guest_suit,"side":host_side if team == 0 else guest_side,"form":LanPlan.Form.SQUAD}
			Net.remote_suit = guest_suit if team == 0 else host_suit
			Net.remote_side = guest_side if team == 0 else host_side
			Net.remote_form = LanPlan.Form.SQUAD
			var plan = main._lan_plan_now()
			var lists: Dictionary = main._lan_canonical_lineups(plan)
			var local_count := 0
			var remote_count := 0
			var ai_keys: Array = []
			for side in [0,1]:
				var units: Array = lists["mine" if side == 0 else "theirs"]
				for u: BattleFormation.Unit in units:
					if u.owner_is_player: local_count += 1
					elif u.owner_is_client: remote_count += 1
					else:
						var canonical: int = side if team == 0 or plan.same_team else 1-side
						ai_keys.append("%d:%d:%d:%d" % [canonical,u.squad,u.slot,u.suit])
			t.eq(local_count,1,"exactly one local pilot")
			t.eq(remote_count,1,"exactly one remote pilot")
			ai_keys.sort()
			signatures.append(ai_keys)
		t.eq(signatures[0],signatures[1],"same AI slots and types on both peers")
	t.ok(Net.valid_room_choice(SuitProfile.Id.GP03D,1,LanPlan.Form.ACE_DUEL),"GP03 allowed in LAN ace duel")
	t.ok(Net.valid_room_choice(SuitProfile.Id.NEUE_ZIEL,1,LanPlan.Form.ACE_DUEL),"Neue Ziel allowed in LAN ace duel")
	t.not_ok(Net.valid_room_choice(SuitProfile.Id.GP03D,1,LanPlan.Form.SQUAD),"GP03 excluded from squads")
	t.eq(MainMenu.LOBBY_ROWS[0],"王牌战","separate ace choice")
	t.eq(MainMenu.LOBBY_ROWS[1],"小队战","separate squad choice")

	# ---- 流程：**先建房，再在房间里决定**（2026-10-11 用户拍板）----
	# 用户原话：「先创建房间之后，再在房间里面决定对战模式和机体。」
	t.not_ok(str(MainMenu.LAN_ROWS).contains("对战形式"),
		"联机主页**没有**「对战形式」行（形式进房间再选）")
	t.eq(MainMenu.LOBBY_ROWS.size(), 6, "房间界面 6 行")
	for want in ["王牌战", "小队战", "阵营", "机体", "准备"]:
		t.ok(str(MainMenu.LOBBY_ROWS).contains(want),
			"房间界面里有「" + want + "」这一项")
	# 模式页选中「局域网联机」确认之后**直接进联机页** —— 不经过阵营 / 机体页。
	# ⚠️ 判据取"那一支**窗口内**有没有 Stage.SIDE / Stage.SUIT"，
	# 而不是全文 `contains`：全文里当然还有它们（小队战那条链还在用）。
	var src := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	var i_lan := src.find("elif lan_mode():")
	t.gt(float(i_lan), 0.0, "模式页确认分支里联机是**独立一支**")
	if i_lan >= 0:
		var win := src.substr(i_lan, 360)
		t.ok(win.contains("stage = Stage.LAN"),
			"……那一支**直接**进 `Stage.LAN`")
		t.not_ok(win.contains("Stage.SIDE") or win.contains("Stage.SUIT"),
			"……那一支里不许出现 `Stage.SIDE` / `Stage.SUIT`（不再先选阵营 / 机体）")
	t.eq(int(MainMenu.LAN_FORMS.size()), 2, "形式表仍是两种（房间内那两行读它）")

	# ⚠️⚠️ 模式页有**两个入口**（`_read_input()` 与极简首页 `menu_home.open_entry`），
	# 两边必须走**同一个** `mode_entry_stage()` —— 各写一遍 if/elif 的后果是
	# 「改一处、从另一处进去还是老流程」（联机那一步就这么漏过一次：
	# 从首页点「局域网联机」仍然先走 阵营 → 机体）。
	var home_src := FileAccess.get_file_as_string("res://scripts/ui/menu_home.gd")
	t.ok(home_src.contains("mode_entry_stage()"),
		"极简首页的进入逻辑走**共用的** `mode_entry_stage()`")
	t.not_ok(home_src.contains("Stage.SIDE if"),
		"……首页里不许再自己写一遍 `Stage.SIDE if ... else Stage.SUIT`（两份判断必然分家）")
	var menu_src := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	t.ok(menu_src.contains("func mode_entry_stage() -> int:"),
		"`mode_entry_stage()` 是这条规则的唯一真源")
	t.ok(menu_src.contains("return Stage.LAN"),
		"……它在联机那一支返回 `Stage.LAN`（不经过阵营 / 机体页）")

	# ---- 行为：**两个入口**点「局域网联机」都必须直接落在联机页 ----
	# 用户 2026-10-11：「这里的选择阵营和机体还有啊」—— 当时 `_read_input()` 已经改对了，
	# 但**极简首页**（`menu_home.open_entry`）自己还有一份进入逻辑 ⇒ 从首页进去仍走老流程。
	# 下面两条把**两个入口**都真的走一遍（不是扫源码）。
	var lan_group := -1
	for gi in MainMenu.MODE_GROUPS.size():
		if (MainMenu.MODE_GROUPS[gi]["modes"] as Array).has(Game.MatchMode.LAN):
			lan_group = gi
	t.gt(float(lan_group), -1.0, "（前提）MODE_GROUPS 里有「局域网联机」那一组")
	if lan_group >= 0:
		var menu2 := MainMenu.new()
		host.add_child(menu2)
		menu2.set_process(false)
		menu2.set_process_input(false)
		menu2.set("mode_index", lan_group)
		# ① 规则函数本身
		t.eq(menu2.mode_entry_stage(), MainMenu.Stage.LAN,
			"规则函数：联机那一组 ⇒ `Stage.LAN`")
		# ② 极简首页那一入口（首页前 N 项与 `MODE_GROUPS` 同序）
		var ui: Control = menu2._home_view
		ui.open_entry(lan_group)
		t.eq(menu2.stage, MainMenu.Stage.LAN,
			"★ 从**极简首页**点「局域网联机」直接进联机页（不经过阵营 / 机体）")
		t.not_ok(menu2.stage == MainMenu.Stage.SIDE or menu2.stage == MainMenu.Stage.SUIT,
			"……而且没有落在阵营页 / 机体页上")
		menu2.free()
	Net._choice = saved_choice
	Net.local_team = saved_team
	Net.remote_suit = saved_remote[0]
	Net.remote_side = saved_remote[1]
	Net.remote_form = saved_remote[2]
	main.free()
	Settings.end_isolated()
