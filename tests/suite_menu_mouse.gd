class_name SuiteMenuMouse
extends RefCounted
## 主菜单**鼠标操控**测试（★63-19 · 阶段 1：主链 10 页）。
##
## ## 这一套守的是哪件事
##
## 老板：「做一个鼠标能操控主菜单子菜单的系统」（右键 = 返回、滚轮 = 移动焦点、
## 悬停播 `ui_select`）。
##
## 会出事的地方**不是"鼠标不工作"**，而是这几种**不报错、不红、只有人眼能看出来**的形状：
##
## | 形状 | 表现 | 守它的是哪一节 |
## |---|---|---|
## | 命中矩形与绘制矩形是**两份写法** | 看着点这一行，实际选了另一行 | `GEO`（源码）+ `HIT`（几何） |
## | `first` 被写死成 0（照抄 `map_row_rect()` 那一族） | 列表一滚动就整体错位 | `HIT` + `NC/nc-first` |
## | 鼠标另写一套输入分支 | 键盘能走、鼠标走到某一页断掉 | `INTENT`（9+10 处（含无尽配置）同源） |
## | 鼠标与键盘的**闸门不是同一个** | 留下一发过期的点击、在下一页落地 | `GATE` |
##
## ## 判据为什么能这么写
##
## `row_rect()` / `row_at_point()` 是 **static 纯函数**（不读 `Input`、不读节点状态），
## 和 `nav_delta_y()` / `scroll_window()` 同一个理由：**可测**。
## 命中测试的边界因此可以在这里直接喂坐标断言，不用去跑真机。
##
## ⚠️ `_list_geometry()` 只读 `size` ⇒ **不必把 `MainMenu` 挂进树**（挂了反而会被
## `_ready()` 的 `PRESET_FULL_RECT` 改掉测试给的那个尺寸）。
##
## ## 两条负对照（NC）
##
## 每条判据都要能**在违规输入上变红**，否则它只是恒真的装饰：
##   · `nc-first`：把 `first` 换成 0 ⇒ 同一像素必须给出**另一个答案**；
##   · `nc-split`：同一个扫描器在**故意违规**的假源码上必须报违规；
##     并且 10 条"唯一真源"断言不是靠**注释被误剥**才通过的（原始源码里注释确实提过
##     `list_metrics(`，剥掉之后必须没有）。
##
## ⚠️ 按**主题命名**（本仓库有并行会话，两侧都按轮次占号时撞过一次文件）。

const GEO := "MenuMouse / 行几何的唯一真源：绘制与命中共用一份（源码扫描）"
const HIT := "MenuMouse / 命中：返回的是列表下标（不是屏幕行号）"
const EDGE := "MenuMouse / 边界：缝 / 面板外 / 空列表"
const INTENT := "MenuMouse / 鼠标意图折成键盘的三个量（源码扫描）"
const GATE := "MenuMouse / 闸门与键盘同帧 + 不改 mouse_filter（源码扫描）"
const NC := "MenuMouse / 负对照：这些判据真的会红"

const SRC := "scripts/ui/main_menu.gd"

## 阶段 1 的 10 页：`[Stage 值, 枚举名, 绘制函数名]`。
##
## ⚠️ 写成函数返回而不是 `const`：把别的脚本的枚举值（`MainMenu.Stage.MODE`）
## 塞进 `const` 数组是否算编译期常量，各版本行为不必赌。
static func _pages() -> Array:
	return [
		[MainMenu.Stage.MODE, "MODE", "_draw_mode_stage"],
		[MainMenu.Stage.BATTLE, "BATTLE", "_draw_battle_stage"],
		[MainMenu.Stage.SIDE, "SIDE", "_draw_side_stage"],
		[MainMenu.Stage.SUIT, "SUIT", "_draw_suit_stage"],
		[MainMenu.Stage.ENEMY, "ENEMY", "_draw_enemy_stage"],
		[MainMenu.Stage.DIFFICULTY, "DIFFICULTY", "_draw_difficulty_stage"],
		[MainMenu.Stage.TRAINING, "TRAINING", "_draw_training_stage"],
		[MainMenu.Stage.MAP, "MAP", "_draw_map_stage"],
		[MainMenu.Stage.ENCOUNTER, "ENCOUNTER", "_draw_encounter_stage"],
		[MainMenu.Stage.FPV_CONFIRM, "FPV_CONFIRM", "_draw_fpv_confirm_stage"],
		[MainMenu.Stage.LAN, "LAN", "_draw_lan_lobby"],
	]

## 阶段 1 **之外**的页（它们没有行几何，鼠标点不到；但必须显式如此）。
const OUTSIDE := [ "SETTINGS", "KEYS", "BGM", "PASSWORD"]

## 版式助手：`_draw_*_stage()` **不许**直接调它们 —— 一律经由 `_list_geometry()`。
const LAYOUT_FNS := ["list_metrics(", "settings_metrics(", "keys_metrics(",
	"suit_window(", "suit_card_rects(", "list_row_rect(", "scroll_window(",
	"mode_row_rect(", "battle_row_rect(", "map_row_rect(", "difficulty_row_rect("]


static func run(t: T, _host: Node) -> void:
	t.suite(GEO)
	_geo(t)
	t.suite(HIT)
	_hit(t)
	t.suite(EDGE)
	_edge(t)
	t.suite(INTENT)
	_intent(t)
	t.suite(GATE)
	_gate(t)
	t.suite(NC)
	_nc(t)


# ---------------------------------------------------------------- 判据工具

## 在一个函数体里找出所有**裸的**版式调用。
##
## ⚠️ 全套只有**这一个**扫描器：`_geo()` 拿它扫 10 个真函数（应为空），
## `_nc()` 拿它扫一段**故意违规**的假源码（应非空）—— 后者就是它的负对照：
## 扫描器若退化成"永远返回空"，那条 NC 会先红。
static func _bare_layout_calls(code: String, head: String) -> Array:
	var body := SuiteMenuFrame._func_body(code, head)
	var out: Array = []
	for fn: String in LAYOUT_FNS:
		if body.contains(fn):
			out.append(fn)
	return out


# ---------------------------------------------------------------- 1 唯一真源

## 绘制与命中必须是**同一份**行几何。
static func _geo(t: T) -> void:
	var code := SuiteUiStyle._code(SRC)
	var pages := _pages()
	t.eq(pages.size(), 11, "主链与联机页共 11 页")

	var lg := SuiteMenuFrame._func_body(code, "func _list_geometry()")
	t.ok(lg != "", "`_list_geometry()` 存在（不然整套都是空转）")

	for row: Array in pages:
		var nm := str(row[1])
		var head := "func %s()" % str(row[2])
		var body := SuiteMenuFrame._func_body(code, head)
		t.ok(body != "", "`%s` 存在" % str(row[2]))
		t.eq(_bare_layout_calls(code, head), [],
			"`%s`（%s 页）里没有裸的版式调用 ⇒ 绘制与命中不会分成两份" % [str(row[2]), nm])
		t.ok(body.contains("_list_geometry()") or body.contains("_fpv_layout()"),
			"`%s` 确实经由 `_list_geometry()` / `_fpv_layout()` 取行几何" % str(row[2]))
		# 反过来：`_list_geometry()` 必须**覆盖**这 10 页（少一页 ⇒ 那一页整页点不到）
		t.ok(lg.contains("Stage.%s:" % nm),
			"`_list_geometry()` 有 `Stage.%s` 分支（缺了 ⇒ 那一页整页点不到）" % nm)
	# 阶段 1 之外的页**不许**悄悄拿到一份行几何
	for outside: String in OUTSIDE:
		t.not_ok(lg.contains("Stage.%s:" % outside),
			"`Stage.%s` 不在阶段 1 里（不许悄悄给它一份行几何）" % outside)

	# 机体页的卡片矩形是**按屏幕槽位**排的 —— 这份换算只许有一处
	var cards := SuiteMenuFrame._func_body(code, "func _geo_cards()")
	t.ok(cards.contains("suit_card_rects(size, win.y)"),
		"卡片矩形仍由 `suit_card_rects()` 给（不是自己算一份 x 递增）")
	t.ok(cards.contains("clampi(suit_index"),
		"……并照抄绘制侧那条 `clampi`（绘制路径不该依赖输入路径的礼貌）")
	# 训练页的 `PANEL_TOP` 覆盖搬进了真源（留在绘制侧就是第二份版式）
	var gl := SuiteMenuFrame._func_body(code, "func _geo_list(")
	t.ok(gl.contains("top_override"), "`_geo_list()` 接受 `top_override`（训练页要它）")
	t.ok(lg.contains("PANEL_TOP"), "`_list_geometry()` 把训练页的 `PANEL_TOP` 覆盖交给 `_geo_list()`")


# ---------------------------------------------------------------- 2 命中

## 点 → **列表下标**。难点全在"滚动窗口"上：屏幕第 0 行是列表下标 `first`。
static func _hit(t: T) -> void:
	var view := Vector2(1600, 900)

	# ---- ① 合成一个"放不下、必须滚动"的列表：first ≠ 0 ----
	#
	# ⚠️ 行数与行高是**算过**的：1600×900 的内容区大约放得下 9 行 72 高（60+12），
	# 40 行必然溢出。第一版写 12 行 48 高，结果**它放得下** ⇒ `first` 恒为 0,
	# 整节的"滚动"前提根本没成立（三条断言当场红 —— 这正是"前提也要断言"的用处）。
	var count := 40
	var met := MainMenu.list_metrics(view, count, 60.0, 12.0, 60.0)
	var shown := int(met["shown"])
	t.lt(float(shown), float(count), "40 行在 900 高里放不下（几何真的进入滚动区）")
	t.gt(float(shown), 1.0, "……但也不是只剩一两行（否则下面按窗口遍历没有意义）")
	var win := MainMenu.scroll_window(count, 10, shown)
	t.gt(float(win.x), 0.0, "焦点停在第 10 行 ⇒ 窗口首行不是 0（正是写死 0 会错的场合）")
	var g := {"kind": MainMenu.Geo.LIST, "count": count, "first": win.x, "shown": win.y,
		"m": met, "rects": []}

	t.eq(MainMenu.row_at_point(view, g,
		MainMenu.row_rect(view, g, win.x).get_center()), win.x,
		"屏幕第 0 行的中心 ⇒ 返回列表下标 first（%d），不是 0" % win.x)

	# ---- ② 窗口内每一行往返一致 ----
	for k in int(win.y):
		var i := int(win.x) + k
		var r: Rect2 = MainMenu.row_rect(view, g, i)
		t.eq(MainMenu.row_at_point(view, g, r.get_center()), i,
			"第 %d 行往返一致（绘制矩形中心 ⇒ 命中该行）" % i)
	# 窗口**外**的行：它的绘制矩形已经在屏幕外，点它必须点不到
	t.eq(MainMenu.row_at_point(view, g, MainMenu.row_rect(view, g, 0).get_center()), -1,
		"窗口外的行（下标 0，此刻在屏幕上方）点不到 —— 返回 −1 而不是 0")

	# ---- ③ 真实页面：`_list_geometry()` 算出来的行，点回去必须还是它自己 ----
	var m := MainMenu.new()
	m.size = view
	for row: Array in _pages():
		var nm := str(row[1])
		var st: int = int(row[0])
		if st == MainMenu.Stage.FPV_CONFIRM:
			continue           # 眩晕框走 `_fpv_layout()`（无 `_font` 时说明文字为空），见 ④
		m.set("stage", st)
		var gl: Dictionary = m._list_geometry()
		var cnt := int(gl["count"])
		if cnt <= 0:
			continue
		var fst := int(gl["first"])
		var sh := int(gl["shown"])
		t.between(float(fst), 0.0, float(cnt - 1), "%s：first 落在 [0, count)" % nm)
		t.between(float(sh), 1.0, float(cnt), "%s：shown 落在 [1, count]" % nm)
		for k2 in sh:
			var i2 := fst + k2
			var r2: Rect2 = MainMenu.row_rect(m.size, gl, i2)
			t.eq(MainMenu.row_at_point(m.size, gl, r2.get_center()), i2,
				"%s：第 %d 行往返一致" % [nm, i2])

	# ---- ④ 机体页：卡片按**屏幕槽位**排，名单下标 = first + 槽位 ----
	#
	# 全工程唯一一处"矩形下标 ≠ 名单下标"。写反的表现是"点第 1 张卡选中第 2 台机"，
	# 而且只在名单比窗口长的时候才看得出来。
	m.set("stage", MainMenu.Stage.SUIT)
	var gs: Dictionary = m._list_geometry()
	t.eq(int(gs["kind"]), MainMenu.Geo.CARDS, "机体页的几何种类是 CARDS")
	t.eq(int(gs["count"]), m.active_suit_list().size(), "卡片数 = 本局可选机体数")
	var rects: Array = gs["rects"]
	t.eq(rects.size(), int(gs["shown"]), "屏幕上的卡片张数 = 窗口的 shown")
	for slot in int(gs["shown"]):
		var idx := int(gs["first"]) + slot
		t.eq(MainMenu.row_rect(m.size, gs, idx), rects[slot],
			"机体页名单下标 %d 的矩形 = 屏幕槽位 %d" % [idx, slot])
		t.eq(MainMenu.row_at_point(m.size, gs, (rects[slot] as Rect2).get_center()), idx,
			"机体页点屏幕槽位 %d ⇒ 返回**名单下标** %d（不是槽位号）" % [slot, idx])
	t.eq(MainMenu.row_rect(m.size, gs, int(gs["first"]) - 1), Rect2(),
		"窗口左侧的名单下标没有屏幕矩形（返回空 Rect2，不是硬算一个）")

	# ---- ⑤ 眩晕框：两个选项行也要能点（`_fpv_layout()` 是唯一真源）----
	m.set("stage", MainMenu.Stage.FPV_CONFIRM)
	var gf: Dictionary = m._list_geometry()
	t.eq(int(gf["kind"]), MainMenu.Geo.FIXED, "眩晕框的几何种类是 FIXED")
	t.eq(int(gf["count"]), MainMenu.FPV_CONFIRM_ROWS.size(),
		"……行数 = `FPV_CONFIRM_ROWS.size()`（不是写死的 2）")
	for k3 in int(gf["count"]):
		var r3: Rect2 = MainMenu.row_rect(m.size, gf, k3)
		t.eq(MainMenu.row_at_point(m.size, gf, r3.get_center()), k3,
			"眩晕框第 %d 行往返一致（以前它内联在绘制里 ⇒ 鼠标点不到）" % k3)
	# 默认停在「否」（下标 0）—— 鼠标划过去也不能把默认值改掉，那是靠 `_set_focus` 之外没人写
	var fv := SuiteUiStyle._code(SRC)
	t.ok(SuiteMenuFrame._func_body(fv, "func _list_geometry()").contains("Geo.FIXED")
		or SuiteMenuFrame._func_body(fv, "func _list_geometry()").contains("_geo_fixed"),
		"`_list_geometry()` 给眩晕框的是 FIXED 分支")

	m.queue_free()


# ---------------------------------------------------------------- 3 边界

static func _edge(t: T) -> void:
	var view := Vector2(1600, 900)
	var met := MainMenu.list_metrics(view, 5, 60.0, 12.0, 60.0)
	var g := {"kind": MainMenu.Geo.LIST, "count": 5, "first": 0, "shown": int(met["shown"]),
		"m": met, "rects": []}
	var top := float(met["top"])
	var row_h := float(met["row_h"])
	var gap := float(met["gap"])
	var x := UILayout.MARGIN + 40.0
	var right_edge := UILayout.MARGIN + UILayout.frame_width(view)

	# ---- ① 行与行之间的缝**算命中上面那一行** ----
	# 缝里返回 −1 会让玩家觉得"点在两行中间没反应"，手感像坏了。
	t.eq(MainMenu.row_at_point(view, g, Vector2(x, top + row_h + gap * 0.5)), 0,
		"第 0 行与第 1 行之间的缝 ⇒ 命中**上面**那一行（0）")
	t.eq(MainMenu.row_at_point(view, g, Vector2(x, top + row_h)), 0,
		"第 0 行的下沿（含）⇒ 仍是第 0 行")

	# ---- ② 面板外一律 −1（不许"鼠标到屏幕边缘就选中最后一行"）----
	t.eq(MainMenu.row_at_point(view, g, Vector2(x, top - 1.0)), -1, "行块**上方** ⇒ −1")
	t.eq(MainMenu.row_at_point(view, g,
		Vector2(x, MainMenu.list_bottom_y(0, int(met["shown"]), met) + 1.0)), -1,
		"行块**下方** ⇒ −1")
	t.eq(MainMenu.row_at_point(view, g, Vector2(UILayout.MARGIN - 1.0, top + 1.0)), -1,
		"外框**左侧**（MARGIN 之外）⇒ −1")
	t.eq(MainMenu.row_at_point(view, g, Vector2(right_edge + 1.0, top + 1.0)), -1,
		"外框**右侧**（frame 之外）⇒ −1")
	# 而边界内侧必须命中（否则上面四条"外"是废的 —— 全返回 −1 也算"通过"）
	t.eq(MainMenu.row_at_point(view, g, Vector2(UILayout.MARGIN + 1.0, top + 1.0)), 0,
		"外框左边界**内侧** ⇒ 命中第 0 行")
	t.eq(MainMenu.row_at_point(view, g, Vector2(right_edge - 1.0, top + 1.0)), 0,
		"外框右边界**内侧** ⇒ 命中第 0 行")

	# ---- ③ 空列表 / 阶段 1 之外的页 ⇒ −1 ----
	t.eq(MainMenu.row_at_point(view,
		{"kind": MainMenu.Geo.LIST, "count": 0, "first": 0, "shown": 0, "m": met, "rects": []},
		Vector2(x, top + 1.0)), -1, "空列表（count=0）⇒ −1")
	t.eq(MainMenu.row_at_point(view,
		{"kind": MainMenu.Geo.NONE, "count": 0, "first": 0, "shown": 0, "m": {}, "rects": []},
		Vector2(x, top + 1.0)), -1, "`Geo.NONE`（阶段 1 之外的页）⇒ −1")
	t.eq(MainMenu.row_at_point(view,
		{"kind": MainMenu.Geo.NONE, "count": 9, "first": 0, "shown": 9, "m": {}, "rects": []},
		Vector2(x, top + 1.0)), -1,
		"`Geo.NONE` 就算谎报 count=9 也点不到（拒绝「给个默认矩形」这种兜底）")

	# ---- ④ 真实页面里"整块放得下" ⇒ `first` 恒为 0 ----
	#
	# 这正是**视觉零位移**的前提：改造前 10 页的绘制侧都把首行写死成 0，
	# 而 `scroll_window()` 在放得下时给出的也正是 0 ⇒ 逐像素相同。
	var m := MainMenu.new()
	m.size = view
	for row: Array in _pages():
		var st: int = int(row[0])
		if st == MainMenu.Stage.FPV_CONFIRM:
			continue
		m.set("stage", st)
		var gg: Dictionary = m._list_geometry()
		if int(gg["kind"]) != MainMenu.Geo.LIST:
			continue
		t.eq(int(gg["first"]), 0,
			"%s：整块放得下 ⇒ first = 0（与改造前写死的 0 逐像素相同）" % str(row[1]))
	m.queue_free()


# ---------------------------------------------------------------- 4 意图同源

static func _intent(t: T) -> void:
	var code := SuiteUiStyle._code(SRC)
	var ri := SuiteMenuFrame._func_body(code, "func _read_input()")

	# ---- ① 消费点：意图折成的三个量 ----
	t.ok(ri.contains("_mi_back = _mouse_intent == Intent.BACK"), "折出 `_mi_back`")
	t.ok(ri.contains("_mi_ok = _mouse_intent == Intent.CONFIRM"), "折出 `_mi_ok`")
	t.ok(ri.contains("_mi_d = _mouse_wheel"), "折出 `_mi_d`（滚轮是累积的相对量）")
	t.ok(ri.contains("_mouse_intent = Intent.NONE"), "消费后立刻清掉点击意图（不会用两次）")
	t.ok(ri.contains("_mouse_wheel = 0"), "滚轮也清零（下一帧从头数）")

	# ---- ② 10 处（含无尽配置）返回 / 10 处（含无尽配置）推进：**每一处**都接了鼠标 ----
	# 漏一处 = "键盘能走、鼠标走到那一页断掉"，而且只有走到那一页才发现。
	t.eq(ri.count('is_action_just_pressed("menu_back") or _mi_back)'), 10,
		"`_read_input()` 的 10 处（含无尽配置）返回**全部**接了 `_mi_back`")
	t.eq(ri.count('is_action_just_pressed("fire_gun") or _mi_ok)'), 10,
		"……10 处（含无尽配置）推进**全部**接了 `_mi_ok`")
	# 反查：别处**不许**再出现这两个已改写的形态（防止有人在别的函数里也改一份）
	t.eq(code.count('is_action_just_pressed("menu_back") or _mi_back)'), 10,
		"全工程的这 10 处（含无尽配置）都在 `_read_input()` 里（没有第二份鼠标返回路径）")

	# ---- ③ 滚轮只在键盘没给方向时补位（两个来源不叠加）----
	t.ok(ri.contains("if nav_d == 0:"), "滚轮补位前先判 `nav_d == 0`（键盘优先）")
	t.ok(ri.contains("nav_d = _mi_d"), "……然后才用滚轮的增量")
	t.lt(float(ri.find("nav_d = _mi_d")), float(ri.find("match stage:")),
		"滚轮补位在 `match stage:` **之前**（每个分支都吃到同一个 `nav_d`）")

	# ---- ④ 眩晕警告框：三个量都接了（它不在 `_read_input()` 的 match 里）----
	var fv := SuiteMenuFrame._func_body(code, "func _read_fpv_confirm_input()")
	t.ok(fv.contains("_mi_d"), "眩晕框：滚轮接了 `_mi_d`")
	t.ok(fv.contains("_mi_back"), "眩晕框：右键接了 `_mi_back`（= Esc / P）")
	t.ok(fv.contains("_mi_ok"), "眩晕框：左键接了 `_mi_ok`（只有停在「是」上才真写）")

	# ---- ⑤ 阶段 1 之外的页**不许**偷接一半（半接比不接更难查）----
	for outside: String in ["_read_password_input", "_read_settings_input",
			"_read_keys_input", "_read_bgm_input"]:
		t.not_ok(SuiteMenuFrame._func_body(code, "func %s()" % outside).contains("_mi_"),
			"`%s()` 不在阶段 1 里 ⇒ 一个 `_mi_` 都不该出现" % outside)
	# LAN now supports mouse input on every subpage, including the ready room.
	for reader: String in ["_read_lan_input","_read_lan_adv_input","_read_lan_rooms_input","_read_lan_room_input"]:
		var lan_body := SuiteMenuFrame._func_body(code,"func %s()" % reader)
		for intent: String in ["_mi_ok","_mi_back","_mi_d"]:
			t.ok(lan_body.contains(intent),"LAN %s consumes %s" % [reader,intent])
	# 那一处重名陷阱：`_read_password_input()` 与眩晕框有**同一行**返回代码
	t.eq(code.count("or Input.is_action_just_pressed(\"open_settings\"):"), 2,
		"`menu_back or open_settings` 在工程里仍是 2 处（眩晕框 + 密码页）—— 改一处别误伤另一处")
	t.not_ok(SuiteMenuFrame._func_body(code, "func _read_password_input()").contains("_mi_back"),
		"……而**只有眩晕框**那一处被接了鼠标（密码页没动）")


# ---------------------------------------------------------------- 5 闸门

static func _gate(t: T) -> void:
	var code := SuiteUiStyle._code(SRC)
	var hb := SuiteMenuFrame._func_body(code, "func _handle_mouse(event: InputEvent)")
	var proc := SuiteMenuFrame._func_body(code, "func _process(delta: float)")
	var gate := "active and input_lockout <= 0.0 and not _await_release"

	# ---- ① 「设意图」与「消费意图」用的是**同一个**闸门 ----
	# 不同则会出现"这一帧设了、下一帧才消费"—— 那一发点击会落到别的地方。
	t.ok(hb.contains(gate), "`_handle_mouse()` 的闸门 = 键盘那一串（逐字相同）")
	t.ok(proc.contains(gate), "`_process()` 调 `_read_input()` 的闸门 = 同一串")
	t.ok(proc.contains("_mouse_intent_frame != Engine.get_process_frames()"),
		"`_process()` 收尾作废过期意图（意图只活一帧，不会留一发点击到下一页）")

	# ---- ② 事件 → 意图 的映射 ----
	t.ok(hb.contains("MOUSE_BUTTON_LEFT"), "认左键")
	t.ok(hb.contains("Intent.CONFIRM"), "……左键 = 推进")
	t.ok(hb.contains("MOUSE_BUTTON_RIGHT"), "认右键")
	t.ok(hb.contains("Intent.BACK"), "……右键 = 返回")
	t.ok(hb.contains("MOUSE_BUTTON_WHEEL_UP"), "认滚轮上")
	t.ok(hb.contains("_mouse_wheel -= 1"), "……滚轮上 = −1（`nav_delta_y()` 约定 −1 = 上）")
	t.ok(hb.contains("MOUSE_BUTTON_WHEEL_DOWN"), "认滚轮下")
	t.ok(hb.contains("_mouse_wheel += 1"), "……滚轮下 = +1")
	t.ok(hb.contains("if not visible:"), "菜单不可见 ⇒ 直接返回（不许改索引）")
	t.ok(hb.contains("mb.pressed"), "只在**按下**那一下算数（松开不再来一次）")

	# ---- ③ ★63-19b 滚轮后屏蔽悬停 ----
	#
	# 这一条是**真机诊断逼出来的**：滚轮把焦点从第 N 行挪到第 N+1 行，
	# 但光标还在第 N 行上。此时系统若补发一发 motion（**触摸板双指滑必发**、
	# 高精度滚轮常发），`_hover_focus()` 会把焦点**拽回第 N 行** ⇒ "滚不动"。
	# 真实鼠标滚轮（光标静止）不触发 ⇒ **手测很难发现**，只有探针的 `warp` 能稳定复现。
	var hfb := SuiteMenuFrame._func_body(code, "func _hover_focus(i: int)")
	t.ok(code.contains("const WHEEL_HOVER_MUTE"), "有 `const WHEEL_HOVER_MUTE`（屏蔽时长）")
	t.ok(code.contains("var _hover_mute_until"), "有 `var _hover_mute_until`（截止时刻）")
	t.eq(hb.count("_hover_mute_until = _time + WHEEL_HOVER_MUTE"), 2,
		"滚轮**上/下两个分支各设一次**（漏一个方向 = 只有一边会被拽回）")
	t.ok(hfb.contains("if _time < _hover_mute_until:"), "`_hover_focus()` 先判屏蔽窗")
	t.lt(float(hfb.find("_hover_mute_until")), float(hfb.find("_focus_index()")),
		"……而且判在 `_focus_index()` **之前**（否则窗内仍会播 `ui_select`）")
	t.ok(SuiteMenuFrame._func_body(code, "func open_menu(").contains("_hover_mute_until = 0.0"),
		"`open_menu()` 清掉屏蔽窗（上次菜单里的滚轮不该影响这次）")

	# ---- ④ ★63-19c 鼠标位置取自**事件自带**的 `position` ----
	#
	# 同样是**真机竞态逼出来的**：`get_local_mouse_position()` 读的是
	# "当前 OS 光标在哪儿"，而这一发事件讲的是"它**发生在**哪儿" —— 光标移动是
	# **异步**的（Windows 的 `WM_MOUSEMOVE` 要好几帧生效），事件到了光标还没挪到位
	# ⇒ 读到旧坐标 ⇒ 悬停算错行。
	# ★63-19 实测：连跑 10 次真机探针**红 3~4 次**，且**每次红的项都不一样** ——
	# 竞态的指纹。改成事件自带坐标后 10/10 全绿。
	#
	# ⚠️ `hb` 来自 `SuiteUiStyle._code()`，**注释已剥掉** ⇒ 这几条不会被自己
	#    注释里的函数名绊倒（`nc-comment` 咬的就是这件事）。
	t.not_ok(hb.contains(":= get_local_mouse_position()"),
		"`_handle_mouse()` **不许**读 `get_local_mouse_position()`（那是异步的当前光标）")
	t.ok(hb.contains("(event as InputEventMouse).position"),
		"位置取自事件自带的 `position`（这一发事件说自己在哪儿就是哪儿）")
	t.ok(hb.contains("if not (event is InputEventMouse):"),
		"取 `position` 之前先守 `InputEventMouse`（否则 `as` 会给出 null）")

	# ---- ③ 悬停：要音效 + **一帧最多一次** ----
	var hf := SuiteMenuFrame._func_body(code, "func _hover_focus(i: int) -> void")
	t.ok(hf.contains("Audio.play_ui(\"ui_select\")"), "悬停播 `ui_select`（用户拍板要）")
	t.ok(hf.contains("_hover_sfx_frame"), "……但同一帧只响一次（划过长列表不会连响十几声）")
	t.ok(hf.contains("i == _focus_index()"), "焦点没变 ⇒ 不响也不改（不是每次移动都响）")
	t.ok(hf.contains("_set_focus(i)"), "……焦点变了才落下去（悬停不推进，只移焦点）")

	# ---- ④ 不动事件流：`mouse_filter` 保持全工程惯例 ----
	t.not_ok(hb.contains("mouse_filter"),
		"`_handle_mouse()` 不去动 `mouse_filter`（`Node._input()` 本来就不受它影响）")
	t.ok(SuiteMenuFrame._func_body(code, "func _ready()").contains("MOUSE_FILTER_IGNORE"),
		"……全屏 Control 仍是 `MOUSE_FILTER_IGNORE`（事件流一个字没改）")
	t.ok(SuiteMenuFrame._func_body(code, "func _input(event: InputEvent)").contains("_handle_mouse(event)"),
		"`_input()` 里接了 `_handle_mouse(event)`")

	# ---- ⑤ 副作用对齐：换焦点必须连"池子变了"一起带走 ----
	var sf := SuiteMenuFrame._func_body(code, "func _set_focus(i: int) -> void")
	t.ok(sf.contains("suit_index = 0"),
		"`_set_focus()` 阵营页分支把 `suit_index` 归零（换阵营 ⇒ 池子换了）")
	t.ok(sf.contains("encounter_index = 0"),
		"`_set_focus()` 机体页分支把 `encounter_index` 归零（换机体 ⇒ 遭遇表重算）")
	# 右键**不移焦点**（"我只想退出去，机体怎么换了"）
	t.eq(hb.count("_hover_focus(row_at_point("), 2,
		"`_handle_mouse()` 只在**两处**移焦点：鼠标移动 + 左键（右键不移）")

	# ---- ⑥ 换页时清干净 ----
	t.ok(SuiteMenuFrame._func_body(code, "func open_menu(lockout := 0.35) -> void").contains("_mouse_intent = Intent.NONE"),
		"`open_menu()` 清掉上次攒下的鼠标意图（进菜单不会先跳一格）")


# ---------------------------------------------------------------- 6 负对照

## 每条判据都要能**在违规输入上变红**。这三条是这一套的自检：
## 若哪天判据被写成了恒真的装饰，它们会先红。
static func _nc(t: T) -> void:
	# ---- nc-first：`first` 是真的输入，不是装饰 ----
	#
	# 旧写法（`map_row_rect()` / `mode_row_rect()` 那一族）把首行**写死成 0**。
	# 照抄它做命中测试，滚动时"屏幕第 0 行"会被读成列表下标 0 ——
	# 这一条证明：同一像素在两个 `first` 下给出的答案**不同**。
	var view := Vector2(1280, 720)
	var met := MainMenu.list_metrics(view, 40, 60.0, 12.0, 60.0)
	var win := MainMenu.scroll_window(40, 10, int(met["shown"]))
	var good := {"kind": MainMenu.Geo.LIST, "count": 40, "first": win.x, "shown": win.y,
		"m": met, "rects": []}
	var wrong := {"kind": MainMenu.Geo.LIST, "count": 40, "first": 0, "shown": win.y,
		"m": met, "rects": []}
	var p := MainMenu.row_rect(view, good, win.x).get_center()
	var a := MainMenu.row_at_point(view, good, p)
	var b := MainMenu.row_at_point(view, wrong, p)
	t.gt(float(win.x), 0.0, "NC 前置：这个窗口的首行不是 0（否则两答案本来就该相同）")
	t.eq(a, win.x, "NC：带 `first` ⇒ 屏幕第 0 行读作 %d" % win.x)
	t.eq(b, 0, "NC：把 `first` 写死成 0 ⇒ 同一像素读作 0")
	t.not_ok(a == b, "NC：两答案不同 ⇒ 「`first` 必须传下去」这条判据**真的会红**")

	# ---- nc-split：扫描器不许退化成"永远返回空" ----
	var bad_src := "func _draw_fake_stage():\n" \
		+ "\tvar m := list_metrics(size, 3, 1.0, 1.0, 2.0)\n" \
		+ "\tvar r := list_row_rect(size, 0, 0, m)\n"
	var hit := _bare_layout_calls(bad_src, "func _draw_fake_stage()")
	t.gt(float(hit.size()), 0.0, "NC：扫描器在**故意违规**的源码上必须报违规")
	t.eq(hit.size(), 2, "NC：……而且报出 2 种（`list_metrics` + `list_row_rect`）")
	var ok_src := "func _draw_ok_stage():\n" \
		+ "\tvar g := _list_geometry()\n" \
		+ "\tvar r := row_rect(size, g, 0)\n"
	t.eq(_bare_layout_calls(ok_src, "func _draw_ok_stage()"), [],
		"NC：同一个扫描器在合规源码上返回空（两个方向都钉住 ⇒ 判据不是恒真）")

	# ---- nc-comment：那 10 条不是"靠注释被误剥"才通过的 ----
	#
	# `_draw_mode_stage()` 的注释里**确实**写着 `list_metrics()`（解释行高自适应）。
	# 原始源码必须含它、剥掉注释之后必须不含它 —— 否则"没有裸调用"可能是因为
	# 扫描器把整行代码当成注释吞了。
	var raw := SuiteUiStyle._src(SRC)
	var code := SuiteUiStyle._code(SRC)
	t.gt(float(SuiteMenuFrame._func_body(raw, "func _draw_mode_stage()").count("list_metrics(")), 0.0,
		"NC 前置：原始源码里 `_draw_mode_stage()` 的**注释**确实提到过 `list_metrics(`")
	t.not_ok(SuiteMenuFrame._func_body(code, "func _draw_mode_stage()").contains("list_metrics("),
		"NC：剥掉注释之后同一函数里没有它（判据读的是代码，不是文字）")
	# 而且剥注释**不是**把代码也一起吞掉：同一个函数体里 `_list_geometry()` 必须还在
	t.ok(SuiteMenuFrame._func_body(code, "func _draw_mode_stage()").contains("_list_geometry()"),
		"NC：……但代码部分完好（`_list_geometry()` 还在 ⇒ 不是把整段吞了）")
