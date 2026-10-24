class_name SuiteComms
extends RefCounted

## 轮 E 的判据：**导入的剧本库** + **通讯台词表** + **播放器** + **HUD 接线**。
##
## ## 这一套在钉什么
##
## 这个功能有一整类**不会报错的失败**，全都在这里钉住：
##
## | 症状 | 为什么会静默 | 本套里哪一条 |
## |---|---|---|
## | 电台按了没反应 | `Trigger.eval` 看不懂就返回 false、动作查不到就什么都不做 | ③ id 全覆盖（双向） |
## | 台词说错人 / 说错话 | 库里两条 id 撞车、或兜底到别的 id | ① 无重 id · ② 不兜底 |
## | 第二局带着第一局的触发记录 | `fired` 写进了被 7 关共享的数据 | ⑥ `fired` 不落数据 |
## | 电台框压住姿态仪 | 版式算在两处，只有某个分辨率才撞上 | ⑦ 跨文件版式不变量 |
## | 存档里混进通讯状态 | 有人顺手 `save` 了一下 | ⑧ 不落盘 |
##
## ## 为什么可以读 `hud.gd` 的常量
##
## ⑦ 里要断言"电台框不许压到姿态仪"，而姿态仪半径是 **`hud.gd` 的常量**。
## 在测试里抄一个 56 就等于把"两处各写一份"这个病搬进测试 —— 所以直接
## `preload("res://scripts/ui/hud.gd")` 读它。顺带这件事**验证了 `hud.gd` 能编译**
##（它不编译的话这一行 `preload` 就红了），这比单独一句源码扫描值钱。

const BANK := preload("res://scripts/data/comms_bank.gd")
const COMMS := preload("res://scripts/data/comms.gd")
const DIR := preload("res://scripts/flight/comms_director.gd")
const MS := preload("res://scripts/data/mission_script.gd")
const HUD := preload("res://scripts/ui/hud.gd")

const BANK_PATH := "res://scripts/data/comms_bank.gd"
const COMMS_PATH := "res://scripts/data/comms.gd"
const DIR_PATH := "res://scripts/flight/comms_director.gd"
const MS_PATH := "res://scripts/data/mission_script.gd"
const HUD_PATH := "res://scripts/ui/hud.gd"
const MENU_PATH := "res://scripts/ui/main_menu.gd"
const MAIN_PATH := "res://scripts/main.gd"
const SETTINGS_PATH := "res://scripts/autoload/settings.gd"
const CAMPAIGN_PATH := "res://scripts/data/campaign.gd"

## 源剧本的条数（老板交付时**逐条数过**，这里是从 CSV 重算出来的）。
## ⚠️ 这两个数是**钉住"导入没有丢行"**的：源改了必须一起改，改了套件会红 ——
## 这正是要的效果（"悄悄少导 30 条"没有任何别的症状）。
const H1_ROWS := 1318
const H2_ROWS := 1731
## 源里标注为存疑（带 `◆`）的条数。
const DOUBT_ROWS := 132

const KINDS := ["对白", "心声", "音响", "歌词", "画面", "署名"]


static func run(t: T) -> void:
	_bank(t)
	_table(t)
	_id_coverage(t)
	_scenes(t)
	_director(t)
	_triggers(t)
	_layout(t)
	_persistence_and_wiring(t)
	_hud_text(t)


# ============================================================ ① 剧本库
static func _bank(t: T) -> void:
	t.suite("Comms · 剧本库（导入）")
	t.eq(BANK.count(), H1_ROWS + H2_ROWS, "总条数 = 两部剧本行数之和")
	t.eq(BANK.by_film("h1").size(), H1_ROWS, "第 1 部行数")
	t.eq(BANK.by_film("h2").size(), H2_ROWS, "第 2 部行数")

	# 每行的字段数必须一致（少一个字段的话 `F_TEXT` 会读到 bool 上，静默）
	var bad_fields := 0
	var empty_text := 0
	var bad_kind := 0
	var ids := {}
	var dup := 0
	for r in BANK.all():
		var row: Array = r
		if row.size() != BANK.FIELD_COUNT:
			bad_fields += 1
			continue
		if str(row[BANK.F_TEXT]).strip_edges() == "":
			empty_text += 1
		if not KINDS.has(str(row[BANK.F_KIND])):
			bad_kind += 1
		var id := str(row[BANK.F_ID])
		if ids.has(id):
			dup += 1
		ids[id] = true
	t.eq(bad_fields, 0, "每行都是 FIELD_COUNT 个字段")
	t.eq(empty_text, 0, "没有空正文")
	t.eq(bad_kind, 0, "类型只出现在白名单 KINDS 里")
	t.eq(dup, 0, "id 没有重复")
	t.eq(ids.size(), BANK.count(), "id 数 == 行数")
	t.eq(BANK.doubtful().size(), DOUBT_ROWS, "存疑条数与源一致")

	# 抽样回查真源（防"整体错位一行"这一类 —— 它不会让任何计数变化）
	t.eq(BANK.text_of("h1:0003"), "我去为您准备", "h1:0003 与源第 3 行一致")
	t.eq(BANK.kind_of("h1:0003"), "对白", "h1:0003 是对白")
	t.eq(BANK.speaker_of("h1:0003"), "空姐", "h1:0003 的说话人")
	t.ok(BANK.text_of("h2:0001") != "", "h2:0001 有正文（第 2 部首行是音响）")
	t.eq(BANK.kind_of("h2:0001"), "音响", "h2:0001 是音响，不是对白")
	t.eq(BANK.text_of("h1:9999"), "", "查不到的 id ⇒ 空串，**不兜底**")
	t.not_ok(BANK.exists("h1:9999"), "exists 对查不到的 id 为假")

	# ★ 正文里的 ASCII 引号：导入时**必须转义而不是改字**。
	# 这一条同时证明两件事：① 转义写对了（否则文件根本编译不过）；
	# ② 没有按"GDScript 里别写裸引号"那条惯例把**数据**改成「」。
	var q := BANK.search("Just take one deep breath", 3)
	t.ok(q.size() >= 1, "能搜到那句带 ASCII 引号的英文台词")
	if q.size() >= 1:
		var txt := str((q[0] as Array)[BANK.F_TEXT])
		t.ok(txt.contains("\""), "它的正文**逐字保留**了 ASCII 引号（没有被改成「」）")

	# 归一：只认表里那几对，**不认识的绝不动**
	t.eq(BANK.canon_of("哈萨韦"), "哈萨维", "第 2 部译名归一")
	t.eq(BANK.canon_of("肯尼斯的部下"), "凯奈斯的部下",
		"复合名走前缀替换（只认整串相等的话它会**静默留在旧译名上**）")
	t.eq(BANK.canon_of("琪琪的心声"), "琪琪", "心声剥后缀")
	t.eq(BANK.canon_of("黄毛路人"), "黄毛路人", "不在表里的名字一个字都不改")
	t.eq(BANK.canon_of("哈萨韦◆"), "哈萨维", "归一顺带剥掉存疑标记")
	# ★ 反向：**归一后不许还有异写残留**
	var residual := 0
	for r in BANK.all():
		var row: Array = r
		var c := str(row[BANK.F_CANON])
		for a in BANK.ALIAS.keys():
			if c.find(str(a)) >= 0:
				residual += 1
	t.eq(residual, 0, "规范名列里没有任何异写残留")

	# 名册：**空名不是一个角色**
	var chars := BANK.characters()
	t.ok(chars.size() > 0, "有名册")
	var top: Array = chars[0]
	t.eq(str(top[0]), "哈萨维", "条数最多的是哈萨维（不是那个空名字）")
	var empty_named := 0
	for c in chars:
		if str((c as Array)[0]) == "":
			empty_named += 1
	t.eq(empty_named, 0, "名册里没有空名（源里 704 条没有说话人，不算角色）")

	# 三译对照里的三个人**不许并**（老板核过日文标签）
	for name in ["米海莎", "米涅切", "艾梅拉尔妲"]:
		t.ok(BANK.characters("h2").size() > 0, "第 2 部名册非空（%s）" % name)
	t.not_ok(BANK.canon_of("米海莎") == BANK.canon_of("米涅切"),
		"米海莎 与 米涅切 是两个人，不许并")
	t.not_ok(BANK.canon_of("米海莎") == BANK.canon_of("艾梅拉尔妲"),
		"米海莎 与 艾梅拉尔妲 是两个人，不许并")
	t.not_ok(BANK.canon_of("艾梅") == BANK.canon_of("艾梅拉尔妲"),
		"`艾梅`(第1部) 与 `艾梅拉尔妲`(第2部) **存疑，故意不并**")


# ============================================================ ② 台词表
static func _table(t: T) -> void:
	t.suite("Comms · 台词表（游戏侧）")
	var ids := COMMS.radio_ids()
	t.ok(ids.size() >= 20, "电台台词表里有一批台词（%d 条）" % ids.size())

	var bad_style := 0
	var bad_secs := 0
	var empty_speaker := 0
	var no_src := 0
	var bad_text := 0
	var bad_speaker := 0
	var bracket := 0
	var worst_text := ""
	var worst_speaker := ""
	for id in ids:
		var line := COMMS.radio(str(id))
		if line.is_empty():
			continue
		if not COMMS.STYLES.has(str(line["style"])):
			bad_style += 1
		if float(line["secs"]) <= 0.0:
			bad_secs += 1
		if str(line["speaker"]) == "":
			empty_speaker += 1
		var src := str(line["src"])
		if src == "" or not BANK.exists(src):
			no_src += 1
			continue
		# ★★ 本套唯一真正管用的那条：**电台就是原句，一个字都不许差**。
		#
		# 上一版这里只查「`src` 能不能查到」，于是 `finser_01` 的 `src` 指着
		# `h1:0991`（舰桥那句「3号 芬萨 OK了」）而正文写着「三号机，芬萨——这边全清了！」
		# —— **指针对了、句子是另一句、说话人也不是同一个人**，套件全绿。
		# 「查得到」和「是同一句」之间隔着一整类静默失败，本轮把它堵上。
		var want_text := BANK.plain_of(src)
		var want_speaker := BANK.speaker_of(src)
		if str(line["text"]) != want_text:
			bad_text += 1
			worst_text = "%s: %s ≠ %s" % [id, str(line["text"]), want_text]
		if str(line["speaker"]) != want_speaker:
			bad_speaker += 1
			worst_speaker = "%s: %s ≠ %s" % [id, str(line["speaker"]), want_speaker]
		# h2 的正文带「（说话人）」前缀；**两个人合并在同一行**的条目剥不干净
		# ⇒ 画出来会是「雷恩：（雷恩）哪里跑」或「伊拉姆：嗯？ （凯莉娅）…」。
		if str(line["text"]).contains("（"):
			bracket += 1
	t.eq(bad_style, 0, "每条台词的样式都在 STYLES 白名单里")
	t.eq(bad_secs, 0, "每条台词的在场时长 > 0")
	t.eq(empty_speaker, 0, "每条台词都有呼号/来源名")
	t.eq(no_src, 0, "★ **每一条**电台都挂着剧本原句（本轮起不许有「原创台词」，%d 条没有）" % no_src)
	t.eq(bad_text, 0, "★ 正文**逐字等于** `BANK.plain_of(src)`（不等的那条 → %s）" % worst_text)
	t.eq(bad_speaker, 0, "★ 说话人逐字等于 `BANK.speaker_of(src)`（不等的那条 → %s）" % worst_speaker)
	t.eq(bracket, 0, "正文里不残留「（说话人）」前缀/第二个括号（%d 条）" % bracket)

	t.eq(str(COMMS.radio("davao_ken_01")["speaker"]), "凯奈斯", "davao_ken_01 是凯奈斯")
	t.eq(str(COMMS.radio("radio:davao_ken_01")["id"]), "davao_ken_01", "带 `radio:` 前缀也能查")
	t.eq(str(COMMS.radio("oenbelli_broadcast_01")["style"]), COMMS.STYLE_ALERT,
		"金伯利对记者那段是**单向播报**，不是呼号通讯")
	t.ok(COMMS.radio("查不到的东西").is_empty(), "查不到的 id ⇒ 空字典，**不兜到别的 id**")
	t.ok(COMMS.line("查不到的东西").is_empty(), "统一入口同样不兜底")

	# ★ 待拍板表本轮**空了** —— 不是因为老板指认了，是因为「布林」那条开场台词
	#   换成了原句（说话人从原句来，不再由我们指定）⇒ 没有需要指认的人了。
	#   判据跟着翻面：上一版钉"非空 + 写清依据"，现在钉"空"。
	t.eq(COMMS.PENDING.size(), 0,
		"PENDING 已清空（`blinks` 那个待办，随「电台必须是原句」一起取消）")

	# 时长函数：单调、有上下限
	var a := COMMS.hold_secs("短", COMMS.STYLE_RADIO)
	var b := COMMS.hold_secs("这是一句相当长的电台台词，长到需要两行才放得下", COMMS.STYLE_RADIO)
	t.ok(b > a, "长句在场更久")
	t.between(a, 1.0, 5.2, "短句被下限托住")
	t.between(b, 1.0, 5.2, "长句被上限截住（电台不能赖着不走，它最多叠三条）")
	t.eq(COMMS.reveal_count("abcdef", 0.0), 0, "打字机 t=0 时一个字都没出来")
	t.eq(COMMS.reveal_count("abcdef", 999.0), 6, "t 足够大 ⇒ 全部打出来")
	t.eq(COMMS.reveal_count("abcdef", -1.0), 0, "负时间 ⇒ 0（不返回负数）")


# ============================================================ ③ id 全覆盖（双向）
static func _id_coverage(t: T) -> void:
	t.suite("Comms · id 全覆盖（双向）")
	# ★ 扫描**整个 scripts/** 去掉注释后的源码，找所有 `radio:<id>`。
	# 只扫 mission_script.gd 是不够的：将来别处（比如轮 G 的播片表）也可能写
	# `radio:`，而那种"新加了一处没加的台词"正是本套要拦的。
	var used := {}
	for path in _all_scripts("res://scripts"):
		var code := SuiteUiStyle._code(path)
		for id in _find_radio_ids(code):
			used[id] = path
	var missing: Array = []
	for id in used.keys():
		if not COMMS.has_radio(str(id)):
			missing.append(str(id))
	t.eq(missing.size(), 0,
		"源码里出现的每个 `radio:<id>` 台词表里都有（缺：%s）" % str(missing))
	t.ok(used.size() >= 20, "扫到的电台引用有 %d 个" % used.size())

	# ★ 反向：台词表里的每一条都得**至少被引用一次** ——
	# 孤儿台词 = "写了永远不播"，它和"缺台词"一样是静默的。
	var orphans: Array = []
	for id in COMMS.radio_ids():
		if not used.has(str(id)):
			orphans.append(str(id))
	t.eq(orphans.size(), 0, "没有孤儿台词（写了却没有任何一关引用：%s）" % str(orphans))

	# 注释里的那个 `radio:ken_11` 不该被算进来（它是 ACTION_KINDS 的举例）
	t.not_ok(used.has("ken_11"),
		"注释里的举例 id 不算引用（`_code()` 剥注释在起作用）")


## 递归列出 `scripts/` 下所有 .gd。
static func _all_scripts(root: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var p := root.path_join(name)
		if dir.current_is_dir():
			out.append_array(_all_scripts(p))
		elif name.ends_with(".gd"):
			out.append(p)
		name = dir.get_next()
	dir.list_dir_end()
	return out


## 从**代码**里抽出所有 `radio:<id>`。
##
## ⚠️ 用 `RegEx` 而不是 `find("radio:")`：后者会把 `radio:` 后面接的东西
## 一直取到行尾（引号、逗号全带上），于是"缺台词"的报错里 id 是脏的、没法直接查。
static func _find_radio_ids(code: String) -> Array:
	var re := RegEx.new()
	re.compile("radio:([a-z0-9_]+)")
	var out: Array = []
	for m in re.search_all(code):
		var id := m.get_string(1)
		if not out.has(id):
			out.append(id)
	return out


# ============================================================ ④ 场景
static func _scenes(t: T) -> void:
	t.suite("Comms · 场景（字幕 / 对白）")
	var ids := COMMS.scene_ids()
	t.ok(ids.size() >= 2, "有场景（%d 段）" % ids.size())
	var bad_id := 0
	var bad_style := 0
	var total_lines := 0
	for sid in ids:
		var sc := COMMS.scene(str(sid))
		if sc.is_empty():
			continue
		if not COMMS.STYLES.has(str(sc["style"])):
			bad_style += 1
		var want: int = (COMMS.SCENES[str(sid)] as Dictionary)["ids"].size()
		var got: int = (sc["lines"] as Array).size()
		total_lines += got
		# ★ 这两个数必须相等：`COMMS.scene()` 对**库里查不到**的 id 是"跳过"，
		# 所以少一条就说明场景里写了库里没有的 id —— 而它**不会报错**。
		if got != want:
			bad_id += 1
	t.eq(bad_id, 0, "每段场景的台词条数 == 它引用的 id 数（没有查不到的 id）")
	t.eq(bad_style, 0, "场景样式都在白名单里")
	t.ok(total_lines >= 10, "场景一共 %d 条台词" % total_lines)

	var hornze := COMMS.scene("prologue_hornze")
	t.eq(str(hornze["style"]), COMMS.STYLE_DIALOGUE, "序章那段是**对白**")
	var lines: Array = hornze["lines"]
	var first: Dictionary = lines[0]
	t.eq(str(first["speaker"]), "空姐", "第一条是空姐")
	t.eq(str(first["text"]), "我去为您准备", "正文来自剧本库（没有第二份副本）")
	# 老板的两次纠正：这一段里"点破"的全是琪琪，哈萨维只有被动应答
	var ha := 0
	var qi := 0
	for l in lines:
		var d: Dictionary = l
		if str(d["speaker"]) == "哈萨维":
			ha += 1
		elif str(d["speaker"]) == "琪琪":
			qi += 1
	t.ok(qi > ha, "琪琪（%d 句）多于哈萨维（%d 句）—— 口径：洞察=琪琪、克制=哈萨维" % [qi, ha])
	t.eq(ha, 2, "哈萨维在这一段恰好两句，且都是被动应答")

	t.eq(str((COMMS.scene("mafty_declaration")["lines"] as Array)[0]["speaker"]),
		"马夫蒂(宣言)", "宣言那段来自库里的原始说话人")


# ============================================================ ⑤ 播放器
static func _director(t: T) -> void:
	t.suite("Comms · 播放器（队列 / 去重 / 打字机）")
	var d := DIR.new()
	t.ok(d.push("davao_sibet_01"), "推一条已知电台 ⇒ 排上")
	t.not_ok(d.push("davao_sibet_01"), "同一句再推 ⇒ 不重播（电台一句只说一次）")
	t.not_ok(d.push("根本不存在的 id"), "查不到的 id ⇒ 不排、不崩")
	t.eq(int(d.missing().get("根本不存在的 id", 0)), 1, "查不到的 id 被记进 missing()")
	t.eq(d.missing().size(), 1, "missing() 里就这一条")
	t.eq(d.queued(), 1, "队列里 1 条")
	t.eq(d.live_of(COMMS.STYLE_RADIO).size(), 0, "还没 tick ⇒ 还没上场")

	d.tick(0.016)
	var live: Array = d.live_of(COMMS.STYLE_RADIO)
	t.eq(live.size(), 1, "tick 之后上场")
	t.eq(d.queued(), 0, "队列清空")
	var e: Dictionary = live[0]
	var line: Dictionary = e["line"]
	t.eq(str(line["id"]), "davao_sibet_01", "上场的就是刚推的那条")
	# ★ 寿命**从进场那一帧的 0 开始** —— 补位发生在"推进在场条目"之后。
	#   反过来（补位时也吃一次 delta）进场首帧的透明度就会跟着帧长变：
	#   10ms 的帧与 33ms 的帧会画出两种样子。**别把这条改成 0.016**。
	t.near(float(e["t"]), 0.0, 0.001, "刚上场那一帧：这一条的寿命从 0 起算")
	d.tick(0.016)
	t.near(float(live[0]["t"]), 0.016, 0.001, "再 tick 一次，在场计时在走")
	t.near(d.clock(), 0.032, 0.001, "总时钟照推（clock() 与单条寿命不是一回事）")

	# 淡入 / 淡出：三个点（0 / 进场完成 / 停留中）
	t.near(DIR.alpha_of(0.0, line), 0.0, 0.001, "t=0 全透明")
	t.near(DIR.alpha_of(DIR.FADE_IN, line), 1.0, 0.001, "淡入结束 ⇒ 全不透明")
	t.near(DIR.alpha_of(DIR.FADE_IN + float(line["secs"]) * 0.5, line), 1.0, 0.001,
		"停留期间一直全不透明")
	t.ok(DIR.alpha_of(DIR.life_secs(line), line) <= 0.01, "寿命尽头 ⇒ 已淡出")
	t.near(DIR.alpha_of(-1.0, line), 0.0, 0.001, "负时间 ⇒ 0（不返回负数）")

	# 打字机：单调、封顶
	t.eq(DIR.reveal_of(0.0, line), 0, "还没开始打")
	t.eq(DIR.reveal_of(999.0, line), str(line["text"]).length(), "打完 ⇒ 等于全文字数")
	t.eq(DIR.shown_text(0.0, line), "", "t=0 显示空串")
	t.eq(DIR.shown_text(999.0, line), str(line["text"]), "打完了显示全文")

	# 过期
	d.tick(30.0)
	t.eq(d.live_of(COMMS.STYLE_RADIO).size(), 0, "时间过去 ⇒ 退场")

	# ---- 四条兰互不抢位 ----
	var d2 := DIR.new()
	d2.push("davao_ken_01")
	t.ok(d2.play_scene("mafty_declaration") == 5, "场景 5 条全排上")
	d2.tick(0.016)
	t.eq(d2.live_of(COMMS.STYLE_RADIO).size(), 1, "电台兰 1 条")
	# ★ 字幕兰同时只能有 1 条：跨样式**不排队**（电台不该等字幕放完才报敌情）
	t.eq(d2.live_of(COMMS.STYLE_SUBTITLE).size(), 1, "字幕兰最多 1 条")
	t.eq(d2.queued(), 4, "剩下的字幕在队列里等自己那条兰空出来")
	# 电台兰最多 3 条
	var d3 := DIR.new()
	d3.push("davao_ken_01")
	d3.push("davao_ken_02")
	d3.push("davao_gawman_03")
	d3.push("leo_ira_01")
	d3.tick(0.016)
	t.eq(d3.live_of(COMMS.STYLE_RADIO).size(), DIR.RADIO_MAX, "电台兰上限就是 RADIO_MAX")
	t.eq(d3.queued(), 1, "第 4 条排队（不是被丢掉 —— 丢掉就等于「少了一句台词」）")

	# ---- 队列上限 + clear ----
	var d4 := DIR.new()
	var sc := COMMS.scene("mafty_declaration")
	var fake := {"id": "x", "speaker": "s", "text": "t", "src": "", "style": COMMS.STYLE_RADIO,
		"secs": 2.0}
	for i in DIR.MAX_QUEUE + 8:
		fake["id"] = "x%d" % i
		d4.enqueue_line(fake.duplicate())
	t.eq(d4.queued(), DIR.MAX_QUEUE, "队列封顶在 MAX_QUEUE（丢最老的）")
	t.ok(sc != null, "场景取出正常")
	d4.clear()
	t.eq(d4.queued(), 0, "clear() 清空队列")
	t.eq(d4.live().size(), 0, "clear() 清空在场")
	t.eq(d4.seen_count(), 0, "clear() 清空去重表")
	t.eq(d4.missing().size(), 0, "d4 自己没查过东西 ⇒ missing 空")

	# ⚠️ `missing()` **不随 clear() 清掉**（它是"数据写错了"的证据，跨局保留才看得见）
	var d5 := DIR.new()
	d5.push("还是不存在的 id")
	d5.clear()
	t.eq(d5.missing().size(), 1, "clear() 不清 missing（跨局保留才看得出「每局都栽在同一处」）")

	# 总开关
	var d6 := DIR.new()
	d6.set_enabled(false)
	t.not_ok(d6.push("davao_ken_01"), "总开关关着 ⇒ 推不进去")
	t.eq(d6.queued(), 0, "关着的时候队列不动")


# ============================================================ ⑥ 触发器 · 演出侧
static func _triggers(t: T) -> void:
	t.suite("Comms · 触发器演出侧")
	var m := MS.m01()
	t.ok(m != null, "拿到 M01")
	var d := DIR.new()

	# 初始（什么都没发生）不该触发任何东西
	var p0 := d.tick_mission(m, {})
	t.eq(p0.size(), 0, "空状态 ⇒ 没有动作触发")
	t.eq(d.fired_count("M01"), 0, "空状态 ⇒ 没记触发")

	# elapsed>=5 ⇒ radio:davao_sibet_01（**演出侧，自己吃掉**）
	var p1 := d.tick_mission(m, {"elapsed": 5.0})
	t.eq(d.fired_count("M01"), 1, "只触发了那一条")
	t.eq(d.queued(), 1, "电台台词进了队列")
	t.eq(p1.size(), 0, "`radio:` **不交还**给 main（演出侧自己消化）")

	# 幂等：同一状态再来一遍，不该重复
	var p2 := d.tick_mission(m, {"elapsed": 5.0})
	t.eq(d.fired_count("M01"), 1, "同一条不重复触发")
	t.eq(d.queued(), 1, "队列没有变长（`fired` 在起作用）")
	t.eq(p2.size(), 0, "重复调用也没有新动作")

	# 游戏侧动作**必须交还**（main 才刷得了波、切得了目标、结得了局）
	#
	# ★ 轮 50：M01 的触发器表**整批换过了**
	#（一架敌机都没有 ⇒ `kills>=1` / `kills>=3` / `zone_ratio>=0.6`
	#  这几条条件已经不存在；胜利条件从
	#  `all_of:kills>=3,zone_ratio>=0.6` 改成了 `landmark_hits>=1`）。
	# 新表里唯一产生**游戏侧动作**的是 `all_done → end:win`，
	# 其余四条全是 `radio:` ⇒ 状态字典得把 `all_done` 喂进去。
	#
	# ⚠️ 刻意**不**传 `hp_ratio`：`MissionScript._value()` 对 `hp` 缺键读
	# **1.0（满血）** ⇒ `hp<0.25` 不会误触 `end:lose`。下面那条 `eq(5)`
	# 同时把这件事钉住了。
	var p3 := d.tick_mission(m, {"elapsed": 50.0, "landmark_hits": 1, "all_done": true})
	var kinds: Array = []
	for a in p3:
		kinds.append(str((a as Dictionary)["kind"]))
	t.ok(kinds.has("end"), "`end:win` 交还给了 main（kinds=%s）" % str(kinds))
	t.ok(kinds.has("radio") == false, "交还的里面**没有** radio（那个被自己吃掉了）")
	t.eq(d.fired_count("M01"), 5,
		"★ 恰好记下 5 条（`elapsed>=4` / `>=20` / `>=45` + `landmark_hits>=1` + `all_done`）"
		+ "；`hp<0.25` **没被误触**（缺键 ⇒ 按满血算）")

	# `fired` 记在**这里**，不在数据里
	var ms_code := SuiteUiStyle._code(MS_PATH)
	t.eq(ms_code.count("fired"), 0,
		"`mission_script.gd` 的**代码**里没有 fired（已触发的唯一持有者是 CommsDirector）")

	# 一关一档：两关的触发记录不许互相干扰
	var m2 := MS.m02()
	var d7 := DIR.new()
	d7.tick_mission(m, {"elapsed": 5.0})
	t.eq(d7.fired_count("M02"), 0, "没跑过 M02 ⇒ M02 的触发记录是空的")
	d7.tick_mission(m2, {"elapsed": 4.0})
	t.eq(d7.fired_count("M02"), 1, "M02 记下了自己那一条")
	t.eq(d7.fired_count("M01"), 1, "M01 的记录不受影响")

	# ★ 每一关的每一条 `radio:` 都必须真的能推出来（不是"表里有、触发推不出来"）
	var bad: Array = []
	for mm in MS.all():
		for tr in mm.triggers:
			if MS.Trigger.action_kind(str(tr.do_what)) != "radio":
				continue
			var arg := MS.Trigger.action_arg(str(tr.do_what))
			if not COMMS.has_radio(arg):
				bad.append("%s:%s" % [mm.id, arg])
	t.eq(bad.size(), 0, "七关所有 `radio:` 动作都能解析出台词（缺：%s）" % str(bad))

	# ---------------------------------------------------------- ★★ 接线（2026-09-30 补）
	#
	# 老板 2026-09-30 的原话：「**没看到电台啊**」。根因就在这一段 ——
	# `CommsDirector` 的触发求值**从来没被调用过**（`main.gd` 里一处 `comms` 都没有），
	# 所以游戏里一条电台都不会出现；而 `hud.comms.tick()` 照跑、队列永远空，
	# **一处都不报错**。这就是"显示这一半做完 ≠ 用户看得见"。
	var main_src := SuiteUiStyle._code(MAIN_PATH)
	t.eq(main_src.count("hud.comms.tick_mission("), 1,
		"★ `main.gd` 里**恰好一处**触发求值（求值只有一方，两处就会各推一半）")
	# ⚠️ `contains("_tick_mission_triggers()")` 是**假判据**：那句 `func
	# _tick_mission_triggers() -> void:` 的**函数声明本身**就含这个子串 ⇒
	# 就算把 `_process` 里那一行调用删掉，它照样绿。**数出现次数**才是真的：
	#   1 次 = 只有定义（没接） / 2 次 = 定义 + 一处调用。
	# 这两个数一起把「定义了不调」与「调了两处」**都**钉住。
	t.eq(main_src.count("_tick_mission_triggers()"), 2,
		"★ `_tick_mission_triggers()` 恰好 2 处 = **一处定义 + 一处每帧调用**"
		+ "（只有 1 处就是「定义了不调」，= 和没接一样）")
	t.eq(main_src.count("func _tick_mission_triggers()"), 1,
		"而且它只被定义一次（两处定义会让求值各推一半）")
	var hud_src2 := SuiteUiStyle._code(HUD_PATH)
	t.eq(hud_src2.count("tick_mission("), 0,
		"HUD 不做触发求值（它只管画 —— 分工是「main 求值 / HUD 显示」）")

	# ---- `keys_of()`：一条 `when` 依赖哪些键 ----
	t.eq(str(MS.Trigger.keys_of("hp<0.2")), str(PackedStringArray(["hp_ratio"])),
		"`hp` 归一成 `hp_ratio`（`_value()` 就是这么读的：两个名字读同一个键）")
	t.eq(str(MS.Trigger.keys_of("hp_ratio<=0.5")), str(PackedStringArray(["hp_ratio"])),
		"同一个键写两次只算一次")
	t.eq(str(MS.Trigger.keys_of("all_done")), str(PackedStringArray(["all_done"])),
		"`all_done` 是特殊形式，读的就是 `all_done`")
	t.eq(str(MS.Trigger.keys_of("enter:orbit_cargo")), str(PackedStringArray(["zones"])),
		"`enter:X` 读的是 `zones` 那张表，不是 `X` 本身")
	t.eq(str(MS.Trigger.keys_of("wave_cleared:0")), str(PackedStringArray(["waves_cleared"])),
		"`wave_cleared:N` 读 `waves_cleared`")
	t.eq(str(MS.Trigger.keys_of("all_of:elapsed>=3,kills>=1")),
		str(PackedStringArray(["elapsed", "kills"])), "组合形态逐项拆开")
	t.eq(str(MS.Trigger.keys_of("all_of:(any_of:elapsed>=3,kills>=1),landmark_hits>=1")),
		str(PackedStringArray(["elapsed", "kills", "landmark_hits"])), "嵌套括号递归展开")
	t.eq(MS.Trigger.keys_of("").size(), 0, "空串 ⇒ 空（同 `eval()` 的 fail-closed）")
	t.eq(MS.Trigger.keys_of("看不懂的写法").size(), 0, "看不懂 ⇒ 空")

	# ---------------------------------------------------------- ★★ 安全阀
	#
	# **任何** `when` 都不该在"什么都没发生"（空状态）时就成立 ——
	# `<` 形态缺省 0 ⇒ 恒真正是这个病最短的形式；它一旦混进要动手的动作里，
	# "把触发器接上"就等于"让它无条件成立"，而**一处都不报错**。
	var spurious: Array = []
	for mm2 in MS.all():
		for tr2 in mm2.triggers:
			if MS.Trigger.eval(str(tr2.when), {}):
				spurious.append("%s:%s(%s)" % [mm2.id, str(tr2.id), str(tr2.when)])
	# M06 已改为袭击关；仅 M07 仍有 `protected_alive<1`。它们依赖的键本轮**没有源**，
	# 所以被 `main._trigger_is_sourced()` 那道闸跳过 + `push_warning`。
	# ⚠️ 这个数**掉了是好事**（有人把那两关的受保护单位统计接上了），
	# 但那时要**一起**把 `Game.trigger_keys_sourced()` 补上，否则它会被白白跳过。
	t.eq(spurious.size(), 1,
		"空状态下自己就成立的触发器仅剩 M07 一条，靠那道闸拦着：%s" % str(spurious))

	# ---- `trigger_state()` 与 `trigger_keys_sourced()` 必须**对得上** ----
	var st := Game.trigger_state(m)
	var have := Game.trigger_keys_sourced()
	var undeclared: Array = []
	for k: String in st.keys():
		if not have.has(k):
			undeclared.append(k)
	t.eq(undeclared.size(), 0,
		"★ `trigger_state()` 写进去的每个键都在 `trigger_keys_sourced()` 里声明过（多出：%s）"
			% str(undeclared))
	for k2: String in ["elapsed", "kills", "landmark_hits", "all_done"]:
		t.ok(st.has(k2), "`trigger_state()` 喂了 `%s`" % k2)
	# ⚠️ **没有玩家时 `hp_ratio` 故意不写** ⇒ `_value()` 读缺省 1.0（满血）⇒ `hp<0.2` 不成立。
	# 这是 fail-closed 的方向：玩家已经没了的时候不该再判一次"重伤失败"。
	t.ok(not st.has("hp_ratio"),
		"★★ 没有玩家时**不写** `hp_ratio`（缺省 1.0 ⇒ `hp<0.2` 不成立，fail-closed）")

	# 没源的键——**列出来**。这份清单就是轮 D/G/H 的待办：往数据里加一条依赖新键的
	# 触发器，这里会**当场变红**（而不是等玩家发现"这一关少了半场戏"）。
# ⚠️ 轮 56：删掉 M04「打捞」之后 `salvaged` **掉了出去** —— 那不是"接上了源"，
#   而是**没人再引用**它（旧 M04 是唯一写 `salvaged>=N` 的那一关）。
# ⚠️ 轮 55：`zones` 也**掉了出去**，但原因与上一条**相反** —— 它是真的**接上了源**：
#   生产者 `main._tick_mission_zones()`（每帧），消费者 M03 的 `enter:orbit_cargo` 与 `Objective.done()` 的 REACH 分支，
#   并且 `Game.trigger_keys_sourced()` 里已声明。
#   ⇒ 这条清单从 6 降到 5 **是好事**（与 `protected_alive` 掉出去时要做的事——补源——不同）。
	var unsourced: Array = []
	for mm3 in MS.all():
		for tr3 in mm3.triggers:
			for k3: String in MS.Trigger.keys_of(str(tr3.when)):
				if not have.has(k3) and not unsourced.has(k3):
					unsourced.append(k3)
	unsourced.sort()
	t.eq(str(unsourced), str(PackedStringArray(["protected_alive",
		"target_hp_ratio", "waves_cleared", "zone_ratio"])),
		"★ 当前未接入状态源的触发键恰好这 4 个（属轮 D/G/H；补一个必须同时补 `trigger_state()`）")


# ============================================================ ⑦ 版式（跨文件不变量）
static func _layout(t: T) -> void:
	t.suite("Comms · 版式")
	var v := Vector2(1600.0, 900.0)
	var ceil_y := v.y - HUD.HEALTH_BLOCK_TOP_FROM_BOTTOM - DIR.RADIO_BOTTOM_PAD
	var floor_y := v.y * 0.5 + HUD.SPEED_BLOCK_BOTTOM_PAD + 8.0

	var cols := DIR.radio_columns(v, floor_y, ceil_y)
	t.eq(cols, 3, "1600×900 下电台排 3 条")

	# ★ 跨文件不变量：电台框**必须让开姿态仪的整个盘**。
	# 姿态仪圆盘直径是 `hud.ATTITUDE_RADIUS * 2`，从 `content_left` 起画；
	# 电台框从 `content_left + RADIO_LEFT_INSET` 起 —— 差一点就会盖住盘的右半边，
	# 而这件事只在"同时有电台 + 姿态仪正在显示"时才看得见。
	t.ok(DIR.RADIO_LEFT_INSET >= HUD.ATTITUDE_RADIUS * 2.0,
		"电台框让开姿态仪整盘（inset %.0f >= 直径 %.0f）"
			% [DIR.RADIO_LEFT_INSET, HUD.ATTITUDE_RADIUS * 2.0])

	# 最上面那一条不许顶到速度块
	var top := DIR.radio_rect(v, 0, cols, ceil_y)
	t.ok(top.position.y >= floor_y - 0.01,
		"最上面一条（y=%.1f）在速度块下界（%.1f）之下" % [top.position.y, floor_y])
	# 最下面那一条的底边贴着血条上方（从下往上排的证据）
	var bot := DIR.radio_rect(v, cols - 1, cols, ceil_y)
	t.near(bot.end.y, ceil_y, 0.01, "最新一条的底边 = 血条上方那条线")
	t.ok(bot.position.y > top.position.y, "从下往上排（最新的在下面）")
	# 不许画出内容区右边
	t.ok(bot.end.x <= v.x - UILayout.MARGIN + 0.01, "电台框不越过内容区右边界")

	var r2 := DIR.radio_rect(v, 0, cols, ceil_y)
	t.near(r2.position.x, UILayout.content_left(v) + DIR.RADIO_LEFT_INSET, 0.01,
		"左边缘 = content_left + RADIO_LEFT_INSET")

	# 1280×720 窗口矮，条数必须自动收紧（不是硬画 3 条去压速度块）。
	#
	# ⚠️ 这里钉**具体条数**，不钉"1..3" —— 范围断言会把"收紧了"和"压根没收敛"**一起放过去**
	# （本仓库的老毛病：判据宽到自己都不认识）。算式：
	#   ceil 594 − floor 480 = **114**；一条要 `RADIO_ROW_H + RADIO_GAP` = 62 + 6 = **68**
	#   ⇒ int(114 / 68) = **1**（两条要 130 > 114）。
	# 改 `RADIO_ROW_H` / `RADIO_GAP` / 那两个 PAD 时这条会红 —— **那是故意的**。
	#
	# ⚠️ 下面 `floor2` 是**照抄** `hud._draw_radio_lane()` 里那一行算式的。
	# 那边改了这里必须跟着改：`radio_columns()` 刻意不收 "速度块" 概念（一个约束一处算式），
	# 所以套件只能自己摆一份调用方该算的东西。
	var v2 := Vector2(1280.0, 720.0)
	var ceil2 := v2.y - HUD.HEALTH_BLOCK_TOP_FROM_BOTTOM - DIR.RADIO_BOTTOM_PAD
	var floor2 := v2.y * 0.5 + HUD.SPEED_BLOCK_BOTTOM_PAD + 8.0
	var cols2 := DIR.radio_columns(v2, floor2, ceil2)
	t.near(ceil2 - floor2, 114.0, 0.01, "720p 电台可用高 = 594 − 480 = 114")
	t.eq(cols2, 1, "★ 720p 下电台只排得下 1 条（114 < 68×2）")
	t.ok(cols2 < cols, "720 排得下 %d 条 < 900 的 %d 条（按窗口收紧）" % [cols2, cols])
	t.ok(DIR.radio_rect(v2, 0, cols2, ceil2).position.y >= floor2 - 0.01,
		"720 下最上面一条也不压速度块")

	# 极端窗口不返回越界矩形
	t.ok(DIR.radio_columns(v, 900.0, 100.0) >= 1, "上界在下界之上时也给 1 条（不返回 0 或负数）")
	t.ok(DIR.centered_rect(v, 800.0, 1).size.x > 0.0, "居中条宽度为正")
	t.ok(DIR.centered_rect(v, 800.0, 1).position.x > 0.0, "居中条在屏幕内")

	# 居中条真的居中
	var c := DIR.centered_rect(v, 800.0, 2)
	t.near(c.position.x + c.size.x * 0.5, v.x * 0.5, 0.01, "居中条水平居中")
	t.near(c.end.y, 800.0, 0.01, "居下条的底边 = 给定底边")

	# ★★ 字幕与人物对话**共用屏幕下中这一条带**：同时在场时不许重叠。
	#
	# 这一条是 `tools/shots_comms.gd` 的 `05_all_lanes` 抓出来的（2026-09-30）：
	# 字幕与对白各自单拍一张都完美 —— 两条都居中、都用 `centered_rect()`、
	# 宽度都由同一个 `max_w` 决定 —— 于是同时在场时是**像素级精确重合**
	# （不是"挨着"，是外面那圈框线叠成一根、大字号那行直接压住小字号那行）。
	# 单拍任何一张都看不出来，只有四条兰一起摆上才现形。
	var st_both := DIR.band_stack(v, 800.0, 1, 1)
	var s_rect: Rect2 = st_both["subtitle"]
	var d_rect: Rect2 = st_both["dialogue"]
	t.not_ok(s_rect.intersects(d_rect), "字幕与对白同时在场 ⇒ 两条框不相交")
	t.near(d_rect.end.y, 800.0, 0.01, "对白贴给定底边（它在下面）")
	t.ok(s_rect.end.y <= d_rect.position.y,
		"字幕整条在对白**上沿之上**（字幕底 %.0f <= 对白顶 %.0f）"
			% [s_rect.end.y, d_rect.position.y])
	t.near(s_rect.end.y, d_rect.position.y - DIR.BAND_STACK_GAP, 0.01,
		"两条之间的缝 = BAND_STACK_GAP")
	# 缺一条时剩下那条的位置**必须不变** —— 单拍时的样子就是最终样子
	# （否则"字幕一个人在场"和"字幕+对白"两种画面下字幕会跳一下）。
	var st_sub := DIR.band_stack(v, 800.0, 1, 0)
	t.near((st_sub["subtitle"] as Rect2).end.y, 800.0, 0.01,
		"只有字幕时它贴底边（不因为「对白可能会来」就提前抬高）")
	t.eq((st_sub["dialogue"] as Rect2).size, Vector2.ZERO, "不在场的那条是空矩形")
	var st_dlg := DIR.band_stack(v, 800.0, 0, 1)
	t.near((st_dlg["dialogue"] as Rect2).end.y, 800.0, 0.01, "只有对白时它贴底边")
	var st_none := DIR.band_stack(v, 800.0, 0, 0)
	t.eq((st_none["subtitle"] as Rect2).size, Vector2.ZERO, "两条都不在场 ⇒ 都空")
	t.eq((st_none["dialogue"] as Rect2).size, Vector2.ZERO, "两条都不在场 ⇒ 都空")
	# 折行数不同时也不许撞 —— 这正是"拿一个常量去顶上面那条的高度"会栽的地方
	var st_deep := DIR.band_stack(v, 800.0, 3, 2)
	t.not_ok((st_deep["subtitle"] as Rect2).intersects(st_deep["dialogue"] as Rect2),
		"字幕 3 行 / 对白 2 行时也不重叠（缝随对白框高走，不是常量）")
	t.near((st_deep["subtitle"] as Rect2).end.y,
		(st_deep["dialogue"] as Rect2).position.y - DIR.BAND_STACK_GAP, 0.01,
		"对白折到 2 行 ⇒ 字幕跟着上移（缝固定，高度跟着）")
	# 缝必须 > 0：两条各有一圈外框，零距离时两根线会叠成一根更粗的线
	t.ok(DIR.BAND_STACK_GAP > 0.0, "缝是正的（两根框线不许叠在一起）")

	# ★★ 电台兰 × 下中那条带：**x 上天然重叠，只能靠 y 错开**。
	#
	# 这是 `tools/shots_comms.gd` 的 `05_all_lanes` 抓到的**第二处**相撞
	# （第一处是上面的字幕 × 对白）。1600 宽下电台框 `x ∈ [190, 570]`、
	# 下中带 `x ∈ [340, 1260]` —— 而"电台下界 = 血条上方(774)"与
	# "带子底边 = `_band_bottom_y()`(768)"只差 6 px ⇒ 有一行字幕在场时
	# 字幕框的左边就横切在电台框上。
	#
	# 决定"谁让谁"的算式**只有一处**：`CommsDirector.radio_ceil_y()`。
	# 这里钉的就是"它真的把两者分开了"，而不是钉某个具体数字。
	var rb_blood := v.y - HUD.HEALTH_BLOCK_TOP_FROM_BOTTOM - DIR.RADIO_BOTTOM_PAD
	t.near(DIR.radio_ceil_y(rb_blood, INF), rb_blood, 0.01,
		"下中条不在场 ⇒ 电台下界就是血条口径（不许无条件抬）")
	var rb_band1 := DIR.band_stack(v, 800.0, 1, 0)
	var rb_band3 := DIR.band_stack(v, 800.0, 3, 0)
	var rb_top1 := (rb_band1["subtitle"] as Rect2).position.y
	var rb_top3 := (rb_band3["subtitle"] as Rect2).position.y
	t.ok(DIR.radio_ceil_y(rb_blood, rb_top1) < rb_blood, "一行字幕在场 ⇒ 电台被压上去")
	t.ok(DIR.radio_ceil_y(rb_blood, rb_top3) < DIR.radio_ceil_y(rb_blood, rb_top1),
		"三行字幕压得比一行更狠（带子越高、电台越矮）")
	# 压完之后：排出来的电台框**一条也不许**与带子相交
	for lines: int in [1, 3]:
		var rb_b := DIR.band_stack(v, 800.0, lines, 0)
		var rb_band: Rect2 = rb_b["subtitle"]
		var rb_ceil := DIR.radio_ceil_y(rb_blood, rb_band.position.y)
		var rb_n := DIR.radio_columns(v, floor_y, rb_ceil)
		var rb_hit := 0
		for i in rb_n:
			if DIR.radio_rect(v, i, rb_n, rb_ceil).intersects(rb_band):
				rb_hit += 1
		t.eq(rb_hit, 0, "字幕 %d 行时：排出来的 %d 条电台框一条都不与带子相交"
			% [lines, rb_n])
		t.ok(rb_ceil >= floor_y - 0.01 or rb_n == 1,
			"字幕 %d 行时上界仍在下界之上（%.0f >= %.0f）或已被压到 1 条"
				% [lines, rb_ceil, floor_y])
	t.ok(DIR.RADIO_BAND_GAP > 0.0, "电台与带子之间也有正缝")

	# 播报条：顶部两行**不许压到告警区**（告警从 y=130 起）
	var al := DIR.alert_rect(v, 2, HUD.COM_ALERT_TOP)
	t.ok(al.end.y <= 130.0,
		"播报条底边（%.0f）停在告警区（130）上面" % al.end.y)

	# 折行：**唯一实现**在 UILayout（别处不许再抄一份）
	var menu_code := SuiteUiStyle._code(MENU_PATH)
	t.eq(menu_code.count("UILayout.wrap"), 1, "主菜单的折行转调 UILayout.wrap")
	t.eq(menu_code.count("for ch: String in para"), 0,
		"主菜单里**不再有**第二份折行实现")
	var ul_code := SuiteUiStyle._code("res://scripts/ui/ui_layout.gd")
	t.eq(ul_code.count("static func wrap"), 1, "UILayout 里就一份折行")
	t.eq(SuiteUiStyle._code(HUD_PATH).count("for ch: String in para"), 0,
		"HUD 里也没有第二份折行")


# ============================================================ ⑧ 不落盘 + 接线
static func _persistence_and_wiring(t: T) -> void:
	t.suite("Comms · 不落盘 / 接线")
	# 通讯是**会话级**的：一句台词不该进存档。
	var set_code := SuiteUiStyle._code(SETTINGS_PATH)
	var cam_code := SuiteUiStyle._code(CAMPAIGN_PATH)
	t.eq(set_code.count("comms"), 0, "settings.gd 的代码里没有 comms（它不落盘）")
	t.eq(cam_code.count("comms"), 0, "campaign.gd 的代码里没有 comms")
	# 反向对照：这两个文件**确实**是写盘的（否则上面两条在"文件是空的"时也成立）
	t.ok(set_code.count("save") > 0, "settings.gd 确实是写盘的那一个（反向对照）")
	t.ok(cam_code.count("save_progress") > 0, "campaign.gd 确实有 save_progress（反向对照）")

	var dir_code := SuiteUiStyle._code(DIR_PATH)
	t.eq(dir_code.count("FileAccess"), 0, "播放器不读文件")
	t.eq(dir_code.count("user://"), 0, "播放器不碰 user://")
	t.eq(dir_code.count("ConfigFile"), 0, "播放器不用 ConfigFile")

	# ---- HUD 接线 ----
	var hud_code := SuiteUiStyle._code(HUD_PATH)
	t.ok(hud_code.count("CommsDirectorScript.new()") == 1,
		"HUD 自己建一个播放器（且只有一处）")
	t.ok(hud_code.count("comms.tick(delta)") == 1, "HUD 每帧推它")
	t.ok(hud_code.count("_draw_comms()") >= 2, "`_draw_comms()` 有定义也有调用点")
	# 绘制顺序：通讯必须在阶段叠加层**之前**（否则结算页上浮着最后一句台词）
	var i_comms := hud_code.find("_draw_comms()")
	var i_phase := hud_code.find("_draw_phase_overlay()")
	t.ok(i_comms >= 0 and i_phase >= 0 and i_comms < i_phase,
		"`_draw_comms()` 排在 `_draw_phase_overlay()` 之前")

	# 台词正文走**唯一**的 `plain()`（不许自己 replace 星号）
	t.eq(hud_code.count("replace(\"**\""), 0,
		"HUD 里没有第二份 `**` 去标记（唯一转换点是 MissionScript.plain）")

	# `Game.reset()` 不碰通讯（它的复位由 HUD 生命周期负责，不该被 reset 顺手清掉去重表）
	t.eq(SuiteUiStyle._code("res://scripts/autoload/game.gd").count("comms"), 0,
		"Game 里没有 comms（播放器的持有者是 HUD）")


# ============================================================ ⑨ HUD 文案（零敌机关）
## ★ 轮 55：M03「接货」改成**零敌机**之后，挑战进度那一行会印出
## 「波次 1 / 0」—— 分子来自 `challenge_wave + 1`、分母是 `wave_count()`，
## 零波次时分子恒为 1、分母是 0 ⇒ 屏幕上那是一句**假话**（这关压根没有波次）。
##
## 判据读的是**纯函数** `FlightHUD.challenge_progress_text()`，不是截图：
##   ① 零波次 ⇒ 文案里不许出现「波次」二字；
##   ② 有波次 ⇒ 与轮 55 之前**逐字符相同**（回归闸门）；
##   ③ 期望值从**真源**推（`M03` → `to_encounter()` → `wave_count()`），不手写名单；
##   ④ 非空洞性：反面必须能印出「波次 N / M」，否则 ① 是空判据；
##   ⑤ **接线**：`hud.gd` 里画画那一处必须真的调用这个纯函数
##      （只定义不调用 = 和没改一样，这是本套件反复钉的那一类静默失败）。
static func _hud_text(t: T) -> void:
	t.suite("Comms · HUD 文案（零敌机关）")

	# ---- ① 零波次：不许印波次号 ----
	var zero := FlightHUD.challenge_progress_text("接货", 0, 0, 0)
	t.ok(not zero.contains("波次"),
		"★ 零波次时文案里没有「波次」（否则就是「波次 1 / 0」这句假话）：got=%s" % zero)
	t.ok(not zero.contains("/"),
		"★ 零波次时也没有「/」（分子分母都不该出现）：got=%s" % zero)
	t.ok(zero.contains("无敌人"), "★ 零波次时改说「无敌人」：got=%s" % zero)
	t.ok(zero.contains("接货"), "标题照旧带上（别把整行都删了）：got=%s" % zero)

	# ---- ② 有波次：与轮 55 之前逐字符相同（回归闸门）----
	t.eq(FlightHUD.challenge_progress_text("接货", 0, 3, 2),
		"挑战 · 接货   波次 1 / 3   本波剩 2",
		"★ 有波次时输出与轮 55 之前**逐字符相同**（回归闸门）")
	t.eq(FlightHUD.challenge_progress_text("接货", 2, 3, 0),
		"挑战 · 接货   波次 3 / 3   本波剩 0", "末波同样对（`wave` 是 0 基）")

	# ---- ③ 期望值从真源推 ----
	var e03: ChallengeScript.Encounter = MS.to_encounter(MS.by_id("M03"))
	t.ok(e03 != null, "M03 能转成 Encounter（`to_encounter()` 不是空壳）")
	if e03 != null:
		var wc := ChallengeScript.wave_count(e03)
		t.eq(wc, 0, "★ M03 真源的波次数 = 0（从 `MS.all()` 那份数据推出来的）")
		var real := FlightHUD.challenge_progress_text(str(e03.title), 0, wc, 0)
		t.ok(not real.contains("波次"),
			"★★ 真源推出来的 M03 文案里没有「波次」：got=%s" % real)

	# ---- ④ 非空洞性：反面必须能印出「波次 N / M」----
	var one := FlightHUD.challenge_progress_text("X", 0, 2, 1)
	t.ok(one.contains("波次") and one.contains(" / "),
		"★ 反面：「波次 N / M」没有被全局删掉（否则上面几条都是空判据）：got=%s" % one)

	# ---- ⑤ 接线：画画那一处必须真的调用它 ----
	var hud_src := SuiteUiStyle._code(HUD_PATH)
	# 1 处定义 + 1 处调用 = 2；只有 1 处就是「定义了不调」，那种状态和没改一样。
	t.eq(hud_src.count("challenge_progress_text("), 2,
		"★ `hud.gd` 里 `challenge_progress_text(` 恰好 2 处 = **一处定义 + 一处调用**")
	t.eq(hud_src.count("波次 %d / %d"), 1,
		"★ 旧拼接只剩纯函数里那一份（= 2 说明画画处还自己拼了一遍，假话会回来）")
