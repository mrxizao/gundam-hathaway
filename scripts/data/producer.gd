extends RefCounted
## **制作人模式**（开发者模式）的纯数据层 —— 密码与输入规范化的**唯一真源**。
##
## ## 需求原文（老板，2026-09-30）
## > 「在设置菜单新增一个密码系统，**藏到最地下看不到的地方**（手柄滑动选项可以选到），
## >  选到之后输入密码 **20060606** 然后按 enter 打开**制作人模式**，
## >  解锁各种关卡和配件，可以调试各种关卡，**制作人模式每次打开游戏都必须手动开启**。」
##
## ## 这一个文件负责"三件半"事（每一件都只有这一份）
## 1. **密码本身**（`CODE`）与判定（`accepts` / `matches`）；
## 2. **输入的规范化**（`sanitize`：只留数字、截到 `MAX_LEN`）——
##    ⚠️ 输入框的回显与判定**必须同源**：各写一份的经典症状是
##    "框里看着是对的、按下去说不对"（本仓库吃过好几回"两处各写一份"的亏）。
## 3. **它在界面上的那几个字**（`LABEL` / `ON_TEXT` / `PROMPT` / `WRONG` / `DONE`）——
##    文案与判据分家的话，改了密码本子却忘了改框里的提示，一样是"图上说着一件事"。
##    （另有半件事：`funds_note()` —— 制作人模式**不做**的那一件，
##     写在 `campaign.gd` 的 `credits_of()` 那边，见那里的注释。）
##
## ## ⚠️ 它**不是安全设施**，别把它当天牢
## 这是同人游戏的"开发者后门"，不是账号系统：密码明文写在源码里、
## 目的是"别让玩家不小心按到"。真正的门是**隐蔽性**（藏在设置页最底下那一行、
## 默认不画）与**不持久化**（每次开游戏都得重输，见 `Game.producer_mode`）。
## ⇒ 因此**不做**哈希、不做混淆：那只会让下一个来改这个门的人多花十分钟找它，
## 而挡不住任何一个会打开 `scripts/` 的人。
##
## ## ⚠️ 跨文件引用走 `preload`，不走 `class_name`
## 本仓库是并行编辑的：新加的 `class_name` 要等编辑器扫过才会进
## `.godot/global_script_class_cache.cfg`，而 `--headless` 跑测试时没人刷那份缓存
## ⇒ 那样写会当场 `Identifier not found`。`preload` 按路径解析，与缓存无关。
## （`campaign.gd` / `campaign_map.gd` 开头那两段说的是同一条纪律。）

## 密码。**这就是那句话里的 20060606**。
const CODE := "20060606"

## 输入长度上限。
##
## ⚠️ 比密码长两格：**不写 8**。写 8 的话，玩家多按一个数字就再也删不回去
##（输入被截断在 8 位、第 9 下直接丢失，看起来像"键盘卡了"）；
## 留两格余量之后"多按了"永远能靠退格改回来，而判定仍然只认 `CODE`。
const MAX_LEN := 10

## 设置页那一行的标题（**只在制作人模式已开启时才会被画出来**，见
## `MainMenu.setting_row_hidden()` —— 那一行默认是隐形的）。
const LABEL := "制作人模式"

## 已开启时那一行的右侧读数。
const ON_TEXT := "开（Enter 关闭）"

## 密码页的标题带与说明。
const TITLE := "密 码"
const SUBTITLE := "输入开发者密码 · 只对本次运行有效，关掉游戏就没了"
const PROMPT := "输入密码后按 Enter"

## 密码不对时的红字。**不写"密码错误"之外的信息** ——
## 提示"差几位 / 是对的但不全"等于把密码告诉猜的人。
const WRONG := "密码不正确"

## 通过时的字。它会留在密码页上（这一页此时已经没人看了，但再进来还看得见）。
const DONE := "制作人模式已开启"

## 密码页的键位说明（键盘那一行与手柄那一行）。
const HINT_KEY := "数字键输入        退格删除        Enter 确认        Esc 返回"
const HINT_PAD := "（密码只能用键盘输入）        B 返回"


## 把任意输入洗成"可判定的形态"：**只留数字**，并截到 `MAX_LEN`。
##
## ⚠️ 它同时是**回显**与**判定**的上游（两处都调它）——
## 只在判定里洗而回显里不洗，就会出现"框里是 `20a6`、判定按 `206` 算"这种
## 没人查得出来的错位。
static func sanitize(raw: String) -> String:
	var out := ""
	for i in raw.length():
		var c := raw[i]
		if c >= "0" and c <= "9":
			out += c
			if out.length() >= MAX_LEN:
				break
	return out


## 这一段输入是不是密码（把 `raw` 洗一遍再比）。
static func accepts(raw: String) -> bool:
	return sanitize(raw) == CODE


## 把"能不能开"合成一个答案：段输入已经洗过，直接比。
##
## ⚠️ 与 `accepts()` 是**同一件事的两种输入形态**：`accepts` 收原始串（自己洗），
## 这个收**已经洗过的串**（输入框里存的就一直是洗过的）。
## 分成两个而不是"到处都调 `accepts`"：`accepts` 每次都要重扫一遍字符串，
## 而输入框每按一下都会问一次。
static func matches(clean: String) -> bool:
	return clean == CODE


## 回显：把已输入的位数写成 `●●●●●●●●` 的形式 + 一个光标。
##
## ⚠️ **回显的是点数而不是数字**：这是密码框，即使门是自家的，
## 也不该让"旁边的人一眼看走整串密码" —— 而"按了几下"这件事照样看得见
##（位数是玩家唯一需要的反馈：按错了立刻能数出来）。
static func echo(clean: String, blink_on := true) -> String:
	var n := clean.length()
	var s := ""
	for i in n:
		s += "●"
	s += "▌" if blink_on else " "
	# 一个都没输入时先给一个空框的形状，否则那一行是空的、看着像页坏了。
	if n == 0:
		return "▌" if blink_on else "　"
	return s


## 密码页上被输入的数字**一共几位**（读数口，给测试与探针用）。
static func typed_count(clean: String) -> int:
	return sanitize(clean).length()
