# -*- coding: utf-8 -*-
"""
把《闪光的哈萨维》第 1/2 部的**台词剧本 CSV** 导入成 Godot 能直接 `preload` 的
GDScript 台词库。

    python tools/import_script.py            # 读 data/script/*.csv -> 写 scripts/data/comms_bank.gd

## 为什么是「生成 .gd」而不是「运行时读 CSV」

1. 本工程**全部数据层都是纯 GDScript**（`mission_script.gd` / `campaign.gd` / `suit_profile.gd`
   …），没有一处运行时读 `res://` 文本。导入器不新开第二条路。
2. 运行时读盘会引入「文件在不在 / 编码对不对 / 解析失败静默返回 null」这一整类**静默失败**，
   而它们全都**只在打包后才暴露**。
3. 生成 .gd ⇒ 无 IO、无 GC 抖动、无头下逐字确定 —— 套件可以直接逐条断言。

## 为什么源 CSV 也留在工程里（`data/script/`）

那才是**真源**。本文件是它的**投影**。留副本是为了「几年后还能重建」——
老板自己的流程也是「改数据文件、一键重建」，两边同一条纪律。
`data/script/.gdignore` 让 Godot 的资源扫描器跳过这个目录（CSV 有内建导入器，
不跳过的话编辑器会拿它当翻译表去导，报一堆看不懂的警告）。

## 三条不许违反的规矩

- **正文一字不改**。`speaker` 列存**原文说话人**；归一后的名字另存 `canon` 列。
  要修的是 `ALIAS` 表（显式、可见、有断言钉着），不是正文。
- **别名表只收「同一个人、两种写法」**。米海莎 / 米涅切 / 艾梅拉尔妲是**三个人**
  （老板核过日文标签），不许并；`艾梅` 与 `艾梅拉尔妲` 也**不并**（存疑，见文件末尾）。
- **说话人不做「猜」**。源里 `Name` 全是字幕组署名 `NTP`，说话人是上一轮**逐条推断**的产物。
  本文件只做搬运与归一，不新增推断。
"""

import csv
import io
import os
import re
import sys
import collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "data", "script")
OUT_GD = os.path.join(ROOT, "scripts", "data", "comms_bank.gd")

H1 = os.path.join(SRC_DIR, "h1_dialogue.csv")
H2 = os.path.join(SRC_DIR, "h2_dialogue.csv")

# ---------------------------------------------------------------- 别名表
# 闪哈1 用「哈萨维/凯奈斯/加乌曼/修盖斯特/凯利亚」，闪哈2 用「哈萨韦/肯尼斯/高曼/休格斯特/凯莉娅」。
# 这是**同一个人在两部片子里的不同译名**，不是两个人。
#
# ⚠️ 2026-09-30 老板口径：米海莎 / 米涅切 / 艾梅拉尔妲 **是三个人，别并**。
# ⚠️ `艾梅`(h1, 10 条) 与 `艾梅拉尔妲`(h2, 14 条) **故意不并** —— 没有确证，
#    宁可留两个名字让人看见，也不要静默合并（合并错了是查不回来的）。
ALIAS = [
    ("哈萨韦", "哈萨维"),
    ("肯尼斯", "凯奈斯"),
    ("高曼", "加乌曼"),
    ("休格斯特", "修盖斯特"),
    ("凯莉娅", "凯利亚"),
    ("金伯利·少佐", "金伯利"),
]

# 心声：`琪琪的心声` / `哈萨韦的心声` / `雷恩的心声`
VOICE_RE = re.compile(r"^(.+?)的(?:心声)$")

KIND_MAP = {
    "对白": "对白",
    "台词": "对白",
    "心声": "心声",
    "音响": "音响",
    "歌词": "歌词",
    "片头曲歌词": "歌词",
    "片尾曲歌词": "歌词",
    "插入歌歌词": "歌词",
    "画面说明": "画面",
    "制作署名": "署名",
}


def canon_of(raw):
    """原文说话人 -> 归一规范名。不在表里就原样返回（**不猜**）。

    ⚠️ 用**前缀替换**而不是整串相等：源里有一批「X 的部下 / X 的机械师B / X 粗重的喘息声」
    这类**复合名**（`肯尼斯的部下`、`哈萨韦粗重的喘息声`）。只认整串相等的话，
    它们全都会**静默留在旧译名上**，而 `by_speaker("凯奈斯")` 少数几条 —— 查不出来的那种错。
    前缀替换会把 `肯尼斯的部下` 变成 `凯奈斯的部下`（保留「部下」这个身份词）。
    """
    s = (raw or "").strip()
    s = re.sub(r"[\u25c6\s]+$", "", s)      # 剥掉存疑标记 ◆
    m = VOICE_RE.match(s)
    if m:
        s = m.group(1)
    for a, b in sorted(ALIAS, key=lambda kv: -len(kv[0])):
        if s.startswith(a):
            return b + s[len(a):]
    return s


def doubt_of(raw):
    return "\u25c6" in (raw or "")


def read_h1():
    rows = list(csv.DictReader(io.StringIO(
        io.open(H1, "rb").read().decode("utf-8-sig"))))
    out = []
    for r in rows:
        out.append({
            "id": "h1:%04d" % int(r["\u5e8f\u53f7"]),
            "film": "h1",
            "seg": (r["\u6bb5\u843d"] or "").strip(),
            "scene": (r["\u573a"] or "").strip(),
            "t": (r["\u5f00\u59cb\u65f6\u95f4"] or "").strip(),
            "speaker": (r["\u8bf4\u8bdd\u4eba(\u63a8\u65ad)"] or "").strip(),
            "kind": KIND_MAP.get((r["\u7c7b\u578b"] or "").strip(), "\u5bf9\u767d"),
            "text": (r["\u4e2d\u6587(\u7b80\u4f53)"] or "").strip(),
        })
    return out


def read_h2():
    rows = list(csv.DictReader(io.StringIO(
        io.open(H2, "rb").read().decode("utf-8-sig"))))
    out = []
    for r in rows:
        out.append({
            "id": "h2:%04d" % int(r["\u5e8f\u53f7"]),
            "film": "h2",
            "seg": (r["\u6bb5\u843d"] or "").strip(),
            "scene": (r["\u573a"] or "").strip(),
            "t": (r["\u5f00\u59cb\u65f6\u95f4"] or "").strip(),
            "speaker": (r["\u8bf4\u8bdd\u4eba(\u5f52\u5e76)"] or "").strip(),
            "kind": KIND_MAP.get((r["\u7c7b\u578b"] or "").strip(), "\u5bf9\u767d"),
            "text": (r["\u4e2d\u6587"] or "").strip(),
        })
    return out


def gd_str(s):
    r"""GDScript 双引号字符串字面量，**正文逐字保留**。

    ⚠️ 两件容易踩的事：
    1. 反斜杠必须先转义（否则 `\N` 之类会把后面的字符吃掉）。
    2. 源里**真的**有一处 ASCII 引号（`"Just take one deep breath"`，空姐的英语台词）。
       那是**数据**，不是我们的排版选择 —— 所以这里走 `\"` 转义，
       **不许**按「GDScript 里别写裸引号」那条惯例把正文改成 `「」`（那会改掉真源）。
       本仓库那条惯例针对的是**自己写**的断言消息/注释，不是搬运来的数据。
    """
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    lines = read_h1() + read_h2()
    for r in lines:
        r["canon"] = canon_of(r["speaker"])
        r["doubt"] = doubt_of(r["speaker"])

    # ---- 自检（生成前先把坏数据拦下来）----
    ids = [r["id"] for r in lines]
    dup = [k for k, v in collections.Counter(ids).items() if v > 1]
    assert not dup, "\u91cd\u590d id: %r" % dup[:5]
    empty = [r["id"] for r in lines if not r["text"]]
    assert not empty, "\u7a7a\u6b63\u6587: %r" % empty[:5]
    # ⚠️ 归一是**投影**，不能反过来污染真源：原文列必须还留着异写
    assert any(r["speaker"] == "\u54c8\u8428\u97e6" for r in lines if r["film"] == "h2"), \
        "\u539f\u6587\u5217\u4e0d\u8be5\u88ab\u5f52\u4e00\u6d17\u6389"
    for r in lines:
        for a, _b in ALIAS:
            assert a not in r["canon"], "\u5f52\u4e00\u6f0f\u4e86 %r -> %r" % (a, r["canon"])
        # ⚠️ **说话人为空是合法的**（源里有 94 + 704 条没有归属），不许当成坏数据 ——
        # 但「原文有名字、归一后反而没了」一定是别名表写错了，必须当场拦下。
        assert (r["speaker"] == "") == (r["canon"] == ""), \
            "\u5f52\u4e00\u540e\u540d\u5b57\u4e22\u4e86: %s %r -> %r" % (r["id"], r["speaker"], r["canon"])

    # ---- 统计（写进文件头，方便肉眼核）----
    per_film = collections.Counter(r["film"] for r in lines)
    kinds = collections.Counter(r["kind"] for r in lines)
    doubt_n = sum(1 for r in lines if r["doubt"])
    chars = collections.Counter(r["canon"] for r in lines
                                if r["kind"] in ("\u5bf9\u767d", "\u5fc3\u58f0")
                                and r["canon"] != "")
    segs = len(set((r["film"], r["seg"]) for r in lines))

    body = []
    add = body.append
    add("# =====================================================================")
    add("#  scripts/data/comms_bank.gd —— **导入的剧本原句库**")
    add("#")
    add("#  ⚠️ **本文件是自动生成的，别手改** —— 改它会下次重建就丢。")
    add("#     重建：`python tools/import_script.py`")
    add("#     真源：`data/script/h1_dialogue.csv` + `data/script/h2_dialogue.csv`")
    add("#           （即老板交付的两份台词剧本：说话人标注版 / 结构化表）")
    add("#")
    add("#  ## 这是什么")
    add("#  《闪光的哈萨维》第 1 部 + 第 2 部**逐条台词**，带说话人、段落、场、时间码。")
    add("#  工程里三个地方要它：**电台**（战斗中的通讯）、**字幕**、**人物对话**。")
    add("#")
    add("#  ## 三条不许违反的规矩（与 tools/import_script.py 头部同源）")
    add("#  1. **正文一字不改**。`speaker` 列是**原文说话人**（真源）；归一后的名字另存")
    add("#     `canon` 列。要修的是 `ALIAS` 表，不是正文。")
    add("#  2. **别名表只收「同一个人、两种写法」**。米海莎 / 米涅切 / 艾梅拉尔妲是**三个人**")
    add("#     （老板核过日文标签），不许并；`艾梅` 与 `艾梅拉尔妲` 也**不并**（存疑）。")
    add("#  3. **说话人不做「猜」**。源里 `Name` 全是字幕组署名 `NTP`，说话人是**逐条推断**的。")
    add("#     本文件只搬运 + 归一，不新增推断。置信度低的原句带 `doubt` 标记。")
    add("#")
    add("#  ## 规模（生成时统计，仅供肉眼核；**判据一律现算**，不许写死在这里）")
    add("#  - 第 1 部 %d 条 / 第 2 部 %d 条 / 合计 **%d 条**，跨 %d 个段落"
        % (per_film["h1"], per_film["h2"], len(lines), segs))
    add("#  - 类型：%s" % "、".join("%s %d" % (k, v) for k, v in kinds.most_common()))
    add("#  - 存疑（原标注带 ◆）**%d 条**" % doubt_n)
    add("#  - 有对白的主要角色：%s"
        % "、".join("%s %d" % (k, v) for k, v in chars.most_common(14)))
    add("#")
    add("#  ## 为什么是「数组的数组」而不是「字典的数组」")
    add("#  %d 条 × 9 个键名（键名在 GDScript 里是**每条各存一份**字符串）会白胖一倍。"
        % len(lines))
    add("#  字段下标用下面的 `F_*` 常量，**别在调用处写数字**。")
    add("# =====================================================================")
    add("extends RefCounted")
    add("")
    add("## 一行 = %d 个字段：9 个本体 + 1 个存疑标记。顺序即下面 `F_*` 的顺序。"
        % 10)
    add("const F_ID := 0        ## `\"h1:0003\"`（`film:CSV序号`，可回查真源）")
    add("const F_FILM := 1      ## `\"h1\"` / `\"h2\"`")
    add("const F_SEG := 2       ## 段落号 `\"02\"`")
    add("const F_SCENE := 3     ## 场号 `\"02-01\"`")
    add("const F_TIME := 4      ## 开始时间 `\"00:01:17.270\"`（轮 G 播片字幕要用到毫秒）")
    add("const F_SPEAKER := 5   ## **原文说话人**（真源，一字未改；可能带尾随 ◆）")
    add("const F_CANON := 6     ## 归一后的规范名（`canon_of()` 的产物）")
    add("const F_KIND := 7      ## `对白` / `心声` / `音响` / `歌词` / `画面` / `署名`")
    add("const F_TEXT := 8      ## 正文（**一字未改**）")
    add("")
    add("## ★ 存疑标记 `◆` 的**另存位** —— 与 `F_SPEAKER` 分开是为了：")
    add("## 调用方要「显示名字」时不必每次去 `strip(\"◆\")`（那是渲染细节泄漏进调用方）。")
    add("const F_DOUBT := 9")
    add("")
    add("const FIELD_COUNT := 10")
    add("")
    add("const LINES: Array = [")
    for r in lines:
        add("\t[%s, %s, %s, %s, %s, %s, %s, %s, %s, %s]," % (
            gd_str(r["id"]), gd_str(r["film"]), gd_str(r["seg"]), gd_str(r["scene"]),
            gd_str(r["t"]), gd_str(r["speaker"]), gd_str(r["canon"]),
            gd_str(r["kind"]), gd_str(r["text"]),
            "true" if r["doubt"] else "false",
        ))
    add("]")
    add("")

    src = "\n".join(body) + "\n\n" + TAIL
    io.open(OUT_GD, "w", encoding="utf-8", newline="\n").write(src)

    b = io.open(OUT_GD, "rb").read()
    print("wrote %s" % OUT_GD)
    print("  bytes %d | lines %d | CRLF %d lone_LF %d"
          % (len(b), b.count(b"\n"), b.count(b"\r\n"), b.count(b"\n") - b.count(b"\r\n")))
    print("  \u6761\u76ee %d (h1 %d / h2 %d) | \u5b58\u7591 %d | \u6bb5\u843d %d"
          % (len(lines), per_film["h1"], per_film["h2"], doubt_n, segs))
    print("  \u7c7b\u578b %s" % dict(kinds))
    return 0


TAIL = u'''# ============================================================ 查询
## 全部条目（**只读**，别改 —— 这是数据，不是状态）。
static func all() -> Array:
	return LINES


static func count() -> int:
	return LINES.size()


static func by_id(id: String) -> Array:
	for r in LINES:
		if r[F_ID] == id:
			return r
	return []


## 找不到就返回空串（**不兜到别处** —— 与 `MissionScript.map_id_for()` 那条纪律同源）。
static func text_of(id: String) -> String:
	var r := by_id(id)
	return "" if r.is_empty() else str(r[F_TEXT])


## 原文说话人（`F_SPEAKER`，可能带尾随 ◆）。**只有电台选句对账用得上它** ——
## 平时要显示名字请用 `speaker_of()`（那是归一名）。
static func raw_speaker_of(id: String) -> String:
	var r := by_id(id)
	return "" if r.is_empty() else str(r[F_SPEAKER])


## ★ **给电台用的正文**：剥掉 h2 正文前缀里的「（说话人）」。
##
## 为什么需要它 —— 两部片子的正文**结构不一样**（老板提醒过这一点）：
##   · 闪哈1 单栏：`说话人` 另有一列，正文就是 `冒牌高达！`；
##   · 闪哈2 是 `中文 ｜ 日文` 双栏的遗留：**说话人被包在中文栏里**，`（雷恩）冒牌高达！`。
## 电台的框里已经画了呼号，直接搬正文会画成「雷恩：雷恩：冒牌高达！」。
##
## ⚠️ **只在括号内容 == 这一行的说话人时**才剥（原文名与归一名都认）。
##    无脑剥「第一个括号」会把 `（男A粗重的喘息声）`、`（高尔夫等人的呐喊声）`
##    这类**整条正文就是括号**的行剥成空串。
## ⚠️ 只剥**最外层第一个**括号组。像 `（伊拉姆）嗯？ （凯莉娅）那个叫琪琪的女孩`
##    这种**两个人合并在同一行**的条目，剥完还留着第二个括号
##    ⇒ 电台选句时**不许选它**（判据在 `tests/suite_comms.gd` 的「台词的正文能直接画」）。
static func plain_of(id: String) -> String:
	var r := by_id(id)
	if r.is_empty():
		return ""
	var t := str(r[F_TEXT])
	if not t.begins_with("（"):
		return t
	var e := t.find("）")
	if e <= 0:
		return t
	var inner := t.substr(1, e - 1).strip_edges()
	var raw := str(r[F_SPEAKER]).strip_edges()
	var canon := str(r[F_CANON])
	if inner != raw and (canon == "" or inner != canon):
		return t
	return t.substr(e + 1).strip_edges()


static func speaker_of(id: String) -> String:
	var r := by_id(id)
	return "" if r.is_empty() else str(r[F_CANON])


static func kind_of(id: String) -> String:
	var r := by_id(id)
	return "" if r.is_empty() else str(r[F_KIND])


static func exists(id: String) -> bool:
	return not by_id(id).is_empty()


static func by_film(film: String) -> Array:
	var out: Array = []
	for r in LINES:
		if r[F_FILM] == film:
			out.append(r)
	return out


static func by_segment(film: String, seg: String) -> Array:
	var out: Array = []
	for r in LINES:
		if r[F_FILM] == film and r[F_SEG] == seg:
			out.append(r)
	return out


## 某个角色说的话（**按规范名**）。`kinds` 留空 = 对白 + 心声（不含音响/歌词）。
static func by_speaker(canon: String, kinds: Array = []) -> Array:
	var use := kinds if not kinds.is_empty() else ["\u5bf9\u767d", "\u5fc3\u58f0"]
	var out: Array = []
	for r in LINES:
		if r[F_CANON] == canon and use.has(r[F_KIND]):
			out.append(r)
	return out


## 出场角色（**只数对白/心声**；`音响` 是「爆炸音」这类，不是人）。
## ⚠️ **没归属的那一批不算角色**（源里 h1 有 94 条、h2 有 704 条没有说话人）。
## 它们按空串混进来的症状是列表第一名显示成一个空名字、条数还最大 —— 一眼看不出是 bug。
## 返回 `[["哈萨维", 544], ...]`，按条数降序（同数按名字升序，保证顺序确定）。
static func characters(film: String = "") -> Array:
	var n := {}
	for r in LINES:
		if film != "" and r[F_FILM] != film:
			continue
		var k: String = r[F_KIND]
		if k != "对白" and k != "心声":
			continue
		var c: String = r[F_CANON]
		if c == "":
			continue
		n[c] = int(n.get(c, 0)) + 1
	var out: Array = []
	for c in n:
		out.append([c, int(n[c])])
	out.sort_custom(func(a, b): return a[1] > b[1] or (a[1] == b[1] and a[0] < b[0]))
	return out


## 存疑条目（原标注带 `◆`）——「拿不准的」都在这里，核这几条最划算。
static func doubtful(film: String = "") -> Array:
	var out: Array = []
	for r in LINES:
		if bool(r[F_DOUBT]) and (film == "" or r[F_FILM] == film):
			out.append(r)
	return out


## 子串检索（大小写敏感，中文无所谓）。`limit <= 0` = 不限。
static func search(q: String, limit := 0) -> Array:
	var out: Array = []
	if q == "":
		return out
	for r in LINES:
		if str(r[F_TEXT]).find(q) >= 0:
			out.append(r)
			if limit > 0 and out.size() >= limit:
				break
	return out


# ============================================================ 角色名归一
## 原文写法 -> 规范名。**只有「同一个人两种译名」才进来。**
##
## ⚠️ 这张表必须与 `tools/import_script.py` 里的 `ALIAS` **逐对一致** ——
## 导入器用它生成 `F_CANON` 列，这里供运行时（玩家输入的名字、别的数据文件里的写法）
## 现查。两处不一致的症状是「库里的名字归一了、别处引用的没归一」，
## 于是 `by_speaker("哈萨维")` 少数几条。
const ALIAS := {
	"\u54c8\u8428\u97e6": "\u54c8\u8428\u7ef4",       # 第 2 部译名 -> 第 1 部译名
	"\u80af\u5c3c\u65af": "\u51ef\u5948\u65af",
	"\u9ad8\u66fc": "\u52a0\u4e4c\u66fc",
	"\u4f11\u683c\u65af\u7279": "\u4fee\u76d6\u65af\u7279",
	"\u51ef\u8389\u5a05": "\u51ef\u5229\u4e9a",
	"\u91d1\u4f2f\u5229\u00b7\u5c11\u4f50": "\u91d1\u4f2f\u5229",
}


static func canon_of(raw: String) -> String:
	var s := raw.strip_edges()
	while s.ends_with("\u25c6"):
		s = s.substr(0, s.length() - 1).strip_edges()
	var i := s.find("\u7684\u5fc3\u58f0")
	if i > 0:
		s = s.substr(0, i)
	# ⚠️ **前缀替换**（与 `tools/import_script.py` 的 `canon_of()` 同一套逻辑）：
	# 源里有 `\u80af\u5c3c\u65af\u7684\u90e8\u4e0b` / `\u54c8\u8428\u97e6\u7c97\u91cd\u7684\u5598\u606f\u58f0` 这类复合名，
	# 只认整串相等会把它们**静默留在旧译名上**。长键优先（`\u91d1\u4f2f\u5229\u00b7\u5c11\u4f50` 必须排在 `\u91d1\u4f2f\u5229` 之前）。
	var keys := ALIAS.keys()
	keys.sort_custom(func(a, b): return a.length() > b.length())
	for k in keys:
		if s.begins_with(k):
			return str(ALIAS[k]) + s.substr(k.length())
	return s
'''

if __name__ == "__main__":
    sys.exit(main())
