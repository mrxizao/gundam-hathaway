class_name SuiteProducer
extends RefCounted
## **制作人模式**（隐藏的密码入口）· 2026-09-30。
##
## ## 需求原文
## > 「在设置菜单新增一个密码系统，**藏到最地下看不到的地方**（手柄滑动选项可以选到），
## >  选到之后输入密码 **20060606** 然后按 enter 打开**制作人模式**，
## >  解锁各种关卡和配件，可以调试各种关卡，**制作人模式每次打开游戏都必须手动开启**。」
##
## ## 拆成七组断言（每一组对应原话里的一个分句）
## | 组 | 钉住的那句话 |
## |---|---|
## | ① 密码（纯函数） | 「输入密码 20060606」（判定只有一份实现、只收数字、只认那 8 位） |
## | ② 不落盘 | 「**每次打开游戏都必须手动开启**」（写盘的那两个文件里一个字都不许出现它） |
## | ③ 隐形行 | 「**藏到最地下看不到的地方**（手柄滑动选项可以选到）」（不画、但在名单末尾、到得了） |
## | ④ 密码页 | 「选到之后输入密码……按 enter」（一页打字界面 + 它接在轮询/绘制/保险丝上） |
## | ⑤ 端到端（菜单） | 「打开制作人模式」（真的 create 一个菜单、真提交、真翻转开关） |
## | ⑥ 战役图 | 「**解锁各种关卡**……可以调试各种关卡」（锁全开、军资 ∞、**都不写档**） |
## | ⑦ 接线 | 两头接上（main 把开关搬进战役图页） |
##
## ## 为什么判定钉在纯函数与源码结构上，而不是注入按键
## 本仓库反复吃过这一条：**无头环境里 `Input.action_press` 的 `just_pressed` 帧戳不可靠**
##（`suite_tutorial` 实测 40 次注入漏一次；`suite_fpv` 也为此把安全性钉在确定事实上）。
## ⇒ 这里把"密码对不对"钉在 `PROD.accepts()`、"按下 Enter 会怎样"钉在
## `submit_password()` / `_activate_producer()`（两个**不碰输入**的函数），
## 而"它们接在界面上哪一处"钉在**源码扫描**（`Stage.PASSWORD` 出现在轮询/绘制/保险丝三处）。
##
## ⚠️ 它**不改玩家的任何存档**：战役进度那一节走**注入的临时路径**（`TMP`），
## 跑完 `erase()` 掉；`settings.cfg` 只**读**不写（见 `_not_persisted()` 的说明）。

const PROD := preload("res://scripts/data/producer.gd")
const CS := preload("res://scripts/data/campaign.gd")
const CMAP := preload("res://scripts/ui/campaign_map.gd")

const MENU_SRC := "res://scripts/ui/main_menu.gd"
const GAME_SRC := "res://scripts/autoload/game.gd"
const CAMPAIGN_SRC := "res://scripts/data/campaign.gd"
const SETTINGS_SRC := "res://scripts/autoload/settings.gd"
const CMAP_SRC := "res://scripts/ui/campaign_map.gd"
const MAIN_SRC := "res://scripts/main.gd"

## 临时存档（**绝不碰** `user://campaign.cfg`）。
const TMP := "user://producer_tmp.cfg"

const VIEWS: Array[Vector2] = [
	Vector2(1280, 720), Vector2(1600, 900), Vector2(1920, 1080), Vector2(2560, 1440),
]


static func run(t: T) -> void:
	_password(t)
	_not_persisted(t)
	_hidden_row(t)
	_password_page(t)
	_menu_end_to_end(t)
	_campaign_map(t)
	_wiring(t)
	# ⚠️ 收尾：把开关关回去（它是**会话级**的，但本进程还要跑别的套件 ——
	# 留着开着的话，后面任何"战役图应该锁着"的断言都会莫名其妙地红）。
	Game.set_producer_mode(false)
	t.not_ok(Game.producer_mode, "套件跑完后制作人模式已关回去（不留给下一个套件）")


# ============================================================ 工具

## 取某个 `func`/`static func` 的函数体（从表头那行到下一个函数之前）。
static func _body(src: String, header: String) -> String:
	var i := src.find(header)
	if i < 0:
		return ""
	var lines := src.substr(i).split("\n")
	var out: Array = [str(lines[0])]
	for k in range(1, lines.size()):
		var s := str(lines[k])
		if s.begins_with("func ") or s.begins_with("static func "):
			break
		out.append(s)
	return "\n".join(out)


## 一份"什么都没打过的"空档。
static func _fresh() -> Dictionary:
	return CS.new_progress()


# ============================================================ ① 密码

static func _password(t: T) -> void:
	t.suite("制作人模式 / 密码（纯函数）")

	# ---- 就是老板给的那一串 ----
	t.eq(PROD.CODE, "20060606", "★ 密码就是老板指定的 20060606（唯一真源在这个常量里）")
	t.ok(PROD.accepts("20060606"), "★ 输入 20060606 ⇒ 通过")
	t.not_ok(PROD.accepts(""), "空输入不通过")
	t.not_ok(PROD.accepts("20060607"), "错一位不通过")
	t.not_ok(PROD.accepts("60606"), "少几位不通过")
	t.not_ok(PROD.accepts("020060606"), "多一位（前面垫 0）不通过")
	t.not_ok(PROD.accepts("2006060"), "只输到第 7 位不通过")

	# ---- 洗输入：只留数字 ----
	t.eq(PROD.sanitize("20060606"), "20060606", "洗一遍原样")
	t.eq(PROD.sanitize(""), "", "空串洗成空串")
	t.eq(PROD.sanitize("abc"), "", "全是字母 ⇒ 空（不会拼出一个假的长度）")
	t.eq(PROD.sanitize("2a0b0c6-0606"), "20060606", "★ 字母与符号被剔掉（电话键盘式输入的手滑不会导致失败）")
	t.eq(PROD.sanitize("  20060606  "), "20060606", "两端空格同样被剔掉")
	t.eq(PROD.sanitize("123456789012345").length(), PROD.MAX_LEN,
		"★ 长度被截到 MAX_LEN（≥ %d 位）" % PROD.MAX_LEN)
	t.ok(PROD.MAX_LEN >= PROD.CODE.length() + 2,
		"★ MAX_LEN 比密码至少长 2 格 —— 多按一下永远还能靠退格改回来" +
		"（写死 8 的话第 9 下直接丢失，看起来像键盘卡了）")

	# ---- 宽松的 `accepts` vs 严格的 `matches` ----
	t.ok(PROD.accepts("20060606abc"), "★ `accepts` 收原始串（自己洗）⇒ 多打的字母不影响")
	t.ok(not PROD.matches("20060606abc"),
		"★ `matches` 只认**已经洗过**的串（输入框里存的就是洗过的，多打的字根本进不去）")
	t.ok(PROD.matches("20060606"), "洗过的串直接比")
	t.not_ok(PROD.matches("2006060"), "差一位不通过")
	t.not_ok(PROD.matches(""), "空串不通过")

	# ---- 回显：点数而不是明文 ----
	var e := PROD.echo("20060606")
	t.eq(e.count("●"), 8, "★ 回显 8 个点（位数看得见）")
	t.not_ok(e.contains("2"), "★ 回显里**不出现明文数字**（密码框不该把密码印在屏幕上）")
	t.gt(float(PROD.echo("", true).length()), 0.0,
		"一位都没输入时也有东西可画（空框看着像页坏了）")
	t.not_ok(PROD.echo("", false).contains("●"), "光标不亮的那一帧没有点也没有数字")
	t.eq(PROD.typed_count("20060606"), 8, "读数口：已输入位数")
	t.eq(PROD.typed_count("2006-0606"), 8, "读数口也走洗输入（与回显同源）")

	# ---- 文案（**唯一真源**：改密码本子却忘了改提示，是"图上说着一件事"的经典形状）----
	t.gt(float(PROD.LABEL.length()), 0.0, "那一行有名字（`%s`）" % PROD.LABEL)
	t.gt(float(PROD.ON_TEXT.length()), 0.0, "开启后的读数非空")
	t.gt(float(PROD.WRONG.length()), 0.0, "密码不对的红字非空")
	t.not_ok(PROD.WRONG.contains(PROD.CODE),
		"★ 提示里**不许出现密码**（哪怕只是「差几位」这种也等于把答案给猜的人）")
	t.gt(float(PROD.HINT_KEY.length()), 0.0, "密码页有键盘键位说明")
	t.gt(float(PROD.HINT_PAD.length()), 0.0, "密码页有手柄那一行说明")


# ============================================================ ② 不落盘

## ★ 老板那句「制作人模式**每次打开游戏都必须手动开启**」的判据。
##
## ## 为什么是"源码扫描 + 一次真实往返"两条
## "不落盘"这件事**不能靠"我记得没写"**：`save_config()` / `save_progress()` 里加一行
## 只要两秒钟，而且**加完之后一切照常绿**（下次开游戏它自己开着，没有任何报错）。
## ⇒ ① 扫那两个**会写盘**的文件的**代码**（注释已剥掉），一个字都不许出现；
##    ② 真跑一次 `save_progress()` → `load_progress()` 往返，逐键比对。
static func _not_persisted(t: T) -> void:
	t.suite("制作人模式 / 不落盘（每次开游戏都得手动开）")

	var settings_code := SuiteUiStyle._code(SETTINGS_SRC)
	var campaign_code := SuiteUiStyle._code(CAMPAIGN_SRC)
	var game_code := SuiteUiStyle._code(GAME_SRC)

	# ---- ① 两个写盘的文件里一个字都不许有 ----
	t.eq(settings_code.count("producer"), 0,
		"★ `settings.gd` 的代码里**一次都没出现** producer（画面/音频设置那条链完全不认识它）")
	t.eq(_body(campaign_code, "static func save_progress").count("producer"), 0,
		"★ `save_progress()` 里没有 producer（进度档里不会多出一个调试开关）")
	t.eq(_body(campaign_code, "static func new_progress").count("producer"), 0,
		"`new_progress()` 里也没有（档里根本不存在这个键）")

	# ---- ② `reset()` 不许清它（每一关都会调 reset，清了等于"只能用一次"）----
	var reset_body := _body(game_code, "func reset()")
	t.gt(float(reset_body.length()), 0.0, "取到了 `Game.reset()` 的函数体")
	t.eq(reset_body.count("producer"), 0,
		"★ `Game.reset()` **不清**制作人模式（它是会话级的，每一关都清 = 连着调试两关就失效）")

	# ---- ③ 真的写一次盘，看文件里有没有它 ----
	CS.erase(TMP)
	# 开着制作人模式去落一次盘 —— 这正是"最危险的时刻"（如果有人把它写进档，就是这里）。
	Game.set_producer_mode(true)
	var p := _fresh()
	if CS.save_progress(p, TMP) != OK:
		t.ok(false, "临时档写失败了（后面的往返断言无意义）")
		Game.set_producer_mode(false)
		return
	var raw := FileAccess.get_file_as_string(TMP)
	t.gt(float(raw.length()), 0.0, "临时档读得回来")
	t.eq(raw.count("producer"), 0, "★ 开着制作人模式落盘 ⇒ 档里**依然没有** producer")
	t.eq(raw.count("20060606"), 0, "★ 密码本身**不落盘**（不能靠翻存档把密码读出来）")

	var back := CS.load_progress(TMP)
	t.not_ok(back.has("producer"), "★ 读回来也没有这个键（往返一致）")
	t.eq(int(back.get("credits", -1)), 0,
		"★ 军资**没有被写成 ∞** —— `credits_of()` 是投影、不是赋值" +
		"（写成 999999 的话，开发者开一次模式打一关，真档就永久坏了）")
	t.eq(int(p.get("credits", -1)), 0,
		"★ `save_progress()` 也**不改传进去的那一份**（纯函数，与 `settle()` 同一条纪律）")
	CS.erase(TMP)
	Game.set_producer_mode(false)

	# ---- ④ `settings.cfg` 只读不写：**不替玩家重写自己的设置** ----
	# ⚠️ 刻意**不调** `Settings.save_config()` 来做这条：那会把玩家真实的设置文件
	# 整个重写一遍（本工程栽过一次"测试把玩家的设置写花了"，见 `campaign.gd` §6.6 第 1 条）。
	# "写不写"这件事由上面那条源码扫描负责，这里只核"现在盘上的那份里没有它"。
	if FileAccess.file_exists(Settings.CONFIG_PATH):
		var cfg_text := FileAccess.get_file_as_string(Settings.CONFIG_PATH)
		t.eq(cfg_text.count("producer"), 0, "盘上现有的 settings.cfg 里没有 producer")
	t.gt(float(settings_code.count("save_config(")), 0.0,
		"（对照）`settings.gd` 确实有写盘函数 —— 上面那条「没有 producer」不是在扫一个空壳文件")


# ============================================================ ③ 隐形行

static func _hidden_row(t: T) -> void:
	t.suite("制作人模式 / 隐形行（藏到最地下看不到的地方）")

	var n := MainMenu.SETTING_ROWS.size()
	var last := MainMenu.producer_row()
	t.eq(last, n - 1, "★ 隐形行是**最后一行**（`producer_row()` 与名单长度同源）")
	t.eq(str(MainMenu.SETTING_ROWS[last]["key"]), MainMenu.PRODUCER_KEY,
		"最后那一行就是它")
	# ⚠️ 台账本身的历史：
	#   ★63-22 把这一行从 14 改成 15（设置页新增「战斗歌单」，插在 `battle_bgm` 后面）
	#   ★63-23 把这一行从 15 改成 16（设置页新增「音量细分」，插在 `sfx` 后面）
	# 这是一条**台账式**断言（数名单再跟常量比），改动名单就必须同步它 ——
	# 不同步的症状是"本批全绿、交付后别人跑全量红一条"。
	t.eq(n, 16, "设置页共 16 行（15 个真设置 + 1 个隐形行）")

	# ---- 画不画：**一等函数**，逐行量 ----
	t.ok(MainMenu.setting_row_hidden(last), "★ 关着的时候**不画**（名字/读数/高亮一个像素都没有）")
	t.not_ok(MainMenu.setting_row_hidden(last, true),
		"★ 开着的时候**显形**（否则「开了就再也找不到开关、只能重启游戏关掉」 —— 那是陷阱）")
	for i in n:
		if i == last:
			continue
		t.not_ok(MainMenu.setting_row_hidden(i),
			"第 %d 行照常画（隐形规则没有顺带波及别的行）" % i)
	t.ok(MainMenu.setting_row_hidden(-1), "越界（负）⇒ 当成「不画」，不崩")
	t.ok(MainMenu.setting_row_hidden(999), "越界（超上界）⇒ 同上")

	# ---- 名字：只有一份真源 ----
	t.eq(MainMenu.setting_label(last), PROD.LABEL,
		"★ 那一行的名字来自 `producer.gd`（表里存的是空串，名字在 `setting_label()` 现取）")
	for i in n:
		if i == last:
			continue
		t.gt(float(MainMenu.setting_label(i).length()), 0.0,
			"第 %d 行有正经标题（`setting_label()` 没有把别人的名字一起吞掉）" % i)

	# ---- 绘制循环真的按它判 ----
	var menu_code := SuiteUiStyle._code(MENU_SRC)
	t.ok(menu_code.contains("if setting_row_hidden(i, Game.producer_mode):"),
		"★ 绘制循环**按 `setting_row_hidden()` 跳过** —— 而不是「画的时候记得避开」" +
		"（那是 `mission_brief` 那条恒假条件的形状：写个没人复核的条件决定画不画）")
	t.ok(menu_code.contains("setting_label(i)"),
		"★ 标题也走 `setting_label()`（不直接读 row[\"label\"]）")

	# ---- 到得到（老板那句「手柄滑动选项可以选到」）----
	t.ok(menu_code.contains("posmod(setting_row + ny, SETTING_ROWS.size())"),
		"设置页的上下导航按**整份名单**（含隐形行）取模 ⇒ 从「返回」再往下就是它")
	t.eq(posmod((n - 2) + 1, n), last,
		"★ 停在「返回」(下标 %d) 再按一下「下」 ⇒ 落在隐形行上" % (n - 2))

	# ---- 它是个"按 Enter 执行"的行，不是"左右拧值"的行 ----
	var m := MainMenu.new()
	t.ok(bool(m.call("_setting_is_action", MainMenu.PRODUCER_KEY)),
		"★ 隐形行算 action 行（左右拧它对它没有任何意义，只会让人以为这一行坏了）")
	t.not_ok(str(m.call("_setting_value_text", MainMenu.PRODUCER_KEY)) != ""
		and not Game.producer_mode,
		"关着的时候读数算出来是空串（那一行本来也不画）")
	m.free()


# ============================================================ ④ 密码页

static func _password_page(t: T) -> void:
	t.suite("制作人模式 / 密码页")

	# ---- 阶段枚举与导航轴 ----
	t.gt(MainMenu.Stage.PASSWORD, MainMenu.Stage.FPV_CONFIRM, "`Stage.PASSWORD` 加在枚举末尾")
	t.eq(MainMenu.nav_axis(MainMenu.Stage.PASSWORD), MainMenu.Nav.NONE,
		"★ 密码页**没有导航轴**（它是打字的一页，上下左右一个都不该动）")

	var menu_code := SuiteUiStyle._code(MENU_SRC)

	# ---- 三处接线：轮询 / 绘制 / 保险丝 ----
	t.ok(menu_code.contains("Stage.PASSWORD:\n\t\t\t_read_password_input()"),
		"★ 输入轮询接上了密码页（`_read_input()` 的分支）")
	t.ok(menu_code.contains("Stage.PASSWORD:\n\t\t\t_draw_password_stage()"),
		"★ 绘制接上了密码页（`_draw()` 的分支）")
	var input_body := _body(menu_code, "func _input(event: InputEvent)")
	t.gt(float(input_body.length()), 0.0, "取到了 `_input()` 的函数体")
	t.ok(input_body.contains("stage == Stage.PASSWORD"),
		"★ Esc 保险丝认密码页（按键表坏掉时玩家仍然退得出去 —— "+
		"这是这道保险丝的全部价值：输入系统出问题的症状永远是「没反应」）")
	t.ok(input_body.contains("KEY_BACKSPACE"), "退格自己处理（字符输入只能走原始事件）")
	t.ok(input_body.contains("PROD.sanitize("),
		"★ 收数字**只走 `PROD.sanitize()`**（这里再写一遍「只收 0-9」，回显与判定就会分家）")

	# ---- P 键必须被排除在"打开设置页"之外 ----
	t.ok(menu_code.contains("stage != Stage.PASSWORD"),
		"★ 密码页排除在「P 打开设置页」之外（不排除的话返回会被记成密码页 ⇒ 一条绕不出去的回路）")

	# ---- 两个手势汇到同一处 ----
	t.ok(menu_code.contains("_activate_producer()"),
		"隐形行上的 Enter 走 `_activate_producer()`（开 / 关两支都在里面）")
	t.ok(menu_code.contains("Game.set_producer_mode(true)"),
		"唯一写入口：`Game.set_producer_mode(true)`")
	t.ok(not menu_code.contains("producer_mode = true"),
		"★ 菜单**不直接写** `Game.producer_mode = true`（绕过唯一写入口就再也没有一处能审计它）")

	# ---- 版式：面板与输入框在各分辨率下都在内容区里 ----
	for v: Vector2 in VIEWS:
		var box := MainMenu.password_panel(v)
		var fr := MainMenu.password_field_rect(v)
		t.ok(box.size.x <= 560.001, "%s：密码面板不宽于 560（拉满整屏看着像报错页）" % v)
		t.ok(box.position.x >= UILayout.MARGIN - 0.001,
			"%s：面板左沿不越出外框线" % v)
		t.ok(box.position.x + box.size.x <= v.x - UILayout.MARGIN + 0.001,
			"%s：面板右沿不越出外框线" % v)
		t.ok(box.position.y >= MainMenu.PANEL_TOP - 0.001, "%s：面板顶不高于内容区顶" % v)
		t.ok(box.position.y + box.size.y <= MainMenu.content_bottom(v) + 0.001,
			"%s：面板底不越出内容区底" % v)
		t.ok(fr.position.x >= box.position.x and fr.position.x + fr.size.x
			<= box.position.x + box.size.x + 0.001, "%s：输入框横向在面板里" % v)
		t.ok(fr.position.y >= box.position.y and fr.position.y + fr.size.y
			<= box.position.y + box.size.y + 0.001, "%s：输入框纵向在面板里" % v)


# ============================================================ ⑤ 端到端（菜单）

static func _menu_end_to_end(t: T) -> void:
	t.suite("制作人模式 / 端到端（真菜单实例）")

	Game.set_producer_mode(false)
	var m := MainMenu.new()
	m.set("stage", MainMenu.Stage.SETTINGS)
	m.set("setting_row", MainMenu.producer_row())

	# ---- 错密码 ----
	t.not_ok(bool(m.call("submit_password", "12345678")), "错密码 ⇒ 不通过")
	t.not_ok(Game.producer_mode,
		"★ 错密码**一个字节都没改**（`Game.producer_mode` 仍是 false）")
	t.eq(str(m.get("pw_input")), "", "失败后输入被清空（不留着上一次那 8 位，免得玩家以为已经输好了）")
	t.eq(str(m.get("pw_msg")), PROD.WRONG, "失败后写的是那一句红字（文案来自唯一真源）")
	t.not_ok(bool(m.get("pw_ok")), "红字（不是绿字）")

	# ---- 对密码 ----
	t.ok(bool(m.call("submit_password", "20060606")), "★ 对密码 ⇒ 通过")
	t.ok(Game.producer_mode, "★ 制作人模式**真的开了**")
	t.eq(str(m.get("pw_msg")), PROD.DONE, "结果行写成「已开启」")
	t.ok(bool(m.get("pw_ok")), "那一行是绿的")
	t.not_ok(MainMenu.setting_row_hidden(int(m.get("setting_row")), Game.producer_mode),
		"★ 开完回到设置页 ⇒ 那一行**显形**了（`setting_row_hidden` 在实例身上也成立）")

	# ---- 再按一次 = 关（关不需要密码）----
	m.call("_activate_producer")
	t.not_ok(Game.producer_mode, "★ 已开启时再按 Enter ⇒ **直接关掉**（门只挡危险的那一侧）")
	t.eq(int(m.get("stage")), MainMenu.Stage.SETTINGS, "关掉不跳页，停在设置页")

	# ---- 关着的时候按一次 = 进密码页 ----
	m.call("_activate_producer")
	t.eq(int(m.get("stage")), MainMenu.Stage.PASSWORD, "★ 关着的时候按 Enter ⇒ 进密码页")
	m.set("pw_input", "2006")            # 假装输了半截
	m.set("pw_msg", PROD.WRONG)
	m.call("_open_password")
	t.eq(str(m.get("pw_input")), "", "★ 每次进密码页都把上一次的输入清掉")
	t.eq(str(m.get("pw_msg")), "", "结果行也清掉（留着红字会让人以为刚输的就错了）")

	# ---- 洗输入这一层不许被绕过（回显与判定同源）----
	m.set("pw_input", PROD.sanitize("20a06-0606x"))
	t.eq(str(m.get("pw_input")), PROD.CODE, "洗过的输入就是那 8 位")
	t.ok(bool(m.call("submit_password", str(m.get("pw_input")))), "也能通过（同一条链）")
	Game.set_producer_mode(false)
	m.free()
	t.not_ok(Game.producer_mode, "清场：开关关回去")


# ============================================================ ⑥ 战役图

static func _campaign_map(t: T) -> void:
	t.suite("制作人模式 / 战役图（解锁所有关卡 · 调试用）")

	var fresh := _fresh()

	# ---- 纯函数：锁全开 ----
	t.not_ok(CS.can_enter(fresh, "M07", false), "（对照）不开制作人模式：M07 锁着")
	t.ok(CS.can_enter(fresh, "M07", true), "★ 开着：M07 也能进")
	t.not_ok(CS.can_enter(fresh, "M99", true),
		"★ 但**不存在的关**仍然进不去（`has_mission` 那道闸留着 —— "+
		"否则按下去会被 `main` 悄悄退回战役图，症状是「按了没反应」）")
	t.not_ok(CS.is_unlocked(fresh, "M07"),
		"★ `is_unlocked()` **一个字节都没改**（它答的是「进度允许吗」，另一条问题是 `can_enter`）")
	for id: String in CS.mission_ids():
		t.ok(CS.can_enter(fresh, id, true), "开着 ⇒ %s 可进" % id)

	# ---- 四态：只有"锁着"那一档被吃掉 ----
	t.eq(CMAP.state_of(fresh, "M01", true), CMAP.State.CURRENT,
		"★ 「当前该打的那一关」照旧写「当前」（那是事实，不该因为开了调试模式就消失）")
	t.eq(CMAP.state_of(fresh, "M07", false), CMAP.State.LOCKED, "（对照）不开：锁着")
	t.eq(CMAP.state_of(fresh, "M07", true), CMAP.State.OPEN, "★ 开着：可出击")
	var p1 := _fresh()
	p1["cleared_mask"] = 1 << 0
	t.eq(CMAP.state_of(p1, "M01", true), CMAP.State.CLEARED, "★ 通了的照旧「已通关」")
	t.eq(CMAP.state_label(p1, "M01", true), "已通关", "标签也是")
	t.eq(CMAP.state_label(fresh, "M07", true), "可出击", "★ 开着时锁着的那一关写成「可出击」")
	# ★ "屏幕上不会再出现任何一把锁"
	for id: String in CS.mission_ids():
		t.not_ok(CMAP.state_of(fresh, id, true) == CMAP.State.LOCKED,
			"★ 开着制作人模式 ⇒ %s 不再是 LOCKED（图上不会再有锁）" % id)

	# ---- 军资：显示 ∞，但**不写档** ----
	t.eq(CS.credits_text(fresh, false), "军资 0", "（对照）不开：照常写余额")
	t.eq(CS.credits_text(fresh, true), "军资 ∞", "★ 开着：写 ∞")
	t.eq(CS.credits_of(fresh, true), CS.PRODUCER_FUNDS, "读数口 = PRODUCER_FUNDS")
	t.gt(float(CS.PRODUCER_FUNDS), float(CS.max_reward()),
		"★ ∞ 那个数**大于全战役理论最高军资**（「什么配件都买得起」才对得起「解锁配件」这句话）")

	# ---- 真页面：两态各来一遍（注入 progress，不读盘）----
	#
	# ⚠️ 光标下标**必须是"任务"下标**（`CS.mission_ids()` 里的位置），**不是**
	# `row_index_of()` 那个"行"下标 —— 后者把章节标题行也算进去，两者不等。
	# 首跑时这里写的是 `CMAP.row_index_of("M07")` ⇒ 越界 ⇒ `_choose()` 走
	# `cursor >= ids.size()` 提前 `cancelled.emit()`，于是**下面那条"不开 ⇒ 不发信号"
	# 的对照断言也是因为同一个越界而变绿的** —— 它压根没在对照。这正是本仓库
	# 反复吃过的"对照两帧必须同类相比"在断言层的翻版。
	var m_index := int(CS.mission_ids().find("M07"))
	var cm := CMAP.new()
	cm.set("progress", fresh)
	cm.set("producer", false)
	cm.set("cursor", m_index)
	t.eq(str(cm.call("selected_id")), "M07",
		"★ 先钉住光标真的停在 M07 上（否则下面两条会因为'越界静默拒绝'而假绿）")
	t.gt(CMAP.row_index_of("M07"), m_index,
		"★ 顺带钉住那个静默陷阱：`cursor` 是**任务**下标、`row_index_of()` 是**行**下标" +
		"（中间夹章节标题行）⇒ 两者不等、不能互换")
	t.eq(str(cm.call("credits_text")), "军资 0", "不开 ⇒ 页面上的读数照旧")
	var got: Array = []
	cm.mission_chosen.connect(func(id: String) -> void: got.append(id))
	cm.call("_choose")
	t.eq(got.size(), 0, "（对照）锁着的关按下去**不发信号**（明确拒绝）")

	cm.set("producer", true)
	t.eq(str(cm.call("credits_text")), "军资 ∞", "★ 开着 ⇒ 页面上写 ∞")
	cm.call("_choose")
	t.eq(got.size(), 1, "★ 开着 ⇒ 同一个 M07 按下去真的发信号了（不是「图上能选、按下去被拒」）")
	t.eq(str(got[0]) if got.size() > 0 else "", "M07", "选中的就是 M07")
	cm.free()

	# ---- 页面的 producer 是**注入**的，不自己去读 Game ----
	var cmap_code := SuiteUiStyle._code(CMAP_SRC)
	t.ok(cmap_code.contains("var producer := false"),
		"★ 页面上有个 `producer` 字段（注入，与 `progress` 同一条分工）")
	t.eq(cmap_code.count("Game.producer_mode"), 0,
		"★ 战役图页**不读** `Game.producer_mode`（读全局是 `main` 的事 —— "+
		"测试才能喂任意组合而不必动 `Game`）")
	t.ok(cmap_code.contains("CS.can_enter(progress, id, producer)"),
		"★ `_choose()` 走 `can_enter()`（那层「进度 ∪ 制作人模式」的合成就只有一份）")
	t.eq(cmap_code.count("CS.is_unlocked("), 0,
		"★ 页面里**不再直接**调 `is_unlocked()`（否则就是随时会分家的第二份判定）")


# ============================================================ ⑦ 接线

static func _wiring(t: T) -> void:
	t.suite("制作人模式 / 接线")

	var main_code := SuiteUiStyle._code(MAIN_SRC)
	t.ok(main_code.contains("campaign_map.producer = Game.producer_mode"),
		"★ `main._open_campaign()` 每次进图把开关搬进战役图页" +
		"（不是缓存 ⇒ 开完开关回主菜单再进图就生效，不需要重启游戏）")

	# ⚠️ 顺序：`campaign_map.open()` 之后才算"这一页就绪"（与 `campaign_map.level` 同一条）。
	t.ok(main_code.find("campaign_map.level = _campaign_level")
			< main_code.find("campaign_map.producer = Game.producer_mode"),
		"★ 两个落值都排在 `open()` 之后（沿用难度那一行的既有顺序，别各写各的）")

	var game_code := SuiteUiStyle._code(GAME_SRC)
	t.ok(game_code.contains("var producer_mode := false"),
		"`Game.producer_mode` 默认 false（新进程里恒关着）")
	t.ok(game_code.contains("func set_producer_mode(on: bool)"),
		"有唯一写入口 `Game.set_producer_mode()`")
	t.not_ok(Game.producer_mode, "★ 本进程此刻它是关的（谁都没偷偷开着）")

	# ---- 那两个"会写盘"的函数一个字都不提它（与 ② 同一条，放在这一节再点一次）----
	t.eq(SuiteUiStyle._code(SETTINGS_SRC).count("producer"), 0,
		"★ `settings.gd` 完全不认识 producer（「每次开游戏手动开」就靠这个）")
	t.eq(_body(SuiteUiStyle._code(CAMPAIGN_SRC), "static func save_progress").count("producer"), 0,
		"★ `save_progress()` 也完全不认识它")
