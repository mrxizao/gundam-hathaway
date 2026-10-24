extends Node
## 全局对局状态 —— "谁在场、谁死了、这一局算谁赢" 的唯一真源。
##
## 刻意保持无类型（Node3D）与低耦合：它不认识 FlightBody，
## 只按鸭子类型调用 `is_alive()` / `is_hostile_to()`。

enum Phase { MENU, INTRO, FIGHT, WIN, LOSE }

## 对局模式：
##   1.1 起：1v1 对战 / 训练模式（靶场打靶机）；
##   1.2 追加：剧情挑战 / 局域网联机；
##   1.2 第二十轮追加：**编队战**（`SQUAD`）—— 两边各 3 个量产编队 + 1 台 ACE。
##   ★63-24 追加：**无限强化演习**（`ENDLESS`）—— 波次无限、局内选卡强化、被击坠即终止。
##
## ⚠️⚠️ 新成员**一律追加在末尾**，不许插中间：`MatchMode` 的值会被写进
## `Game.match_mode`、被 `match` 和 `==` 到处比，插一个值进去会让**后面所有取值整体位移**，
## 而错位的表现是"某一局跑成了另一种模式"，**编译期一个字都不报**
##（`spawn_round()` 那一串 `elif` 会安静地走进另一个分支）。
enum MatchMode { VERSUS, TRAINING, CHALLENGE, LAN, SQUAD, ENDLESS }

signal phase_changed(new_phase: int)
signal unit_spawned(unit: Node3D)
signal unit_destroyed(unit: Node3D, killer: Node3D)
## ★ 轮 50：**剧情关的地标被打中了**。
##
## 只由 `Projectile` 在扫掠命中“带着 `WorldBuilder.HOTEL_GROUP`”的物体时发出。
## ⚠️ 它**不是**击毁事件：那栋楼不掉血、不消失，只是“被打中了一下”。
signal landmark_hit(landmark: Node3D, hitter: Node3D)

var phase: int = Phase.INTRO
var player: Node3D = null
var units: Array[Node3D] = []

## 单调时钟（秒）。所有"持续 N 秒"的效果都以它为基准 ——
## 用 Game.clock 而不是 Time.get_ticks_msec()，无头测试里可以直接推它。
var clock := 0.0

## 本局配置（主菜单选的）。main.gd 在开局前写入。
var active_suit: int = SuitProfile.Id.XI
var active_difficulty: Difficulty = null
var active_time_of_day: TimeOfDay = null
## 本局地图（1.1）。靶场那张图只会在训练模式里出现。
var active_map: MapDef = null
var match_mode: int = MatchMode.VERSUS
## 对战模式里玩家指定的敌机（1.2）。`-1` = 由 main 自动挑"另一台"。
var active_enemy_suit := -1

## 编队战（1.2 第二十轮）：本局的阵营与编制。
##
## `active_side` 是**玩家这一边**的阵营（`BattleFormation.Side`）；
## 名字里带 active_ 是为了和 `active_suit` / `active_map` 那批保持一致。
## `active_side` 为 −1 表示"还没选"（老模式不走编队，读它不会用到）。
var active_side := -1
## 本局双方各出了几台（含玩家的那台）。结算与 HUD 读它。
## 由 `main.spawn_squad()` 按 `BattleFormation` 的编制算出来写进去。
var squad_units_per_side := 0

## 联机（局域网）本机选的**对战形式**（`LanPlan.Form`）。
##
## ⚠️ 它只是**本机那一票**：两台机器都选王牌战，这一局才是王牌战
##（`LanPlan.resolve_form()`）。菜单在**出击那一刻**写入（`MainMenu._launch()`）。
## 默认是 `SQUAD`（小队战）—— 也就是"没有这一项之前"的行为。
##
## ⚠️ `main._lan_plan_now()` 读的是 `Net.choice_of("form", 这里)` ——
## 也就是说**它只是兜底值**。真正算数的是 `Net.announce_choice()` 存下的那一份
##（那才是真的发出去的东西），两者可能不一致：联机这条路里 `Game.*` 历史上
## 从来没人在对局开始前写过。完整理由见 `NetSession.choice_of()` 的注释。
var active_lan_form: int = LanPlan.Form.SQUAD

# ============================================================ ★63-24 无限强化演习（`ENDLESS`）
#
# 这一节装的全是**局内状态**：`Game` 是 autoload ⇒ 这些变量跨局是活的，
# 不显式清零就会被上一局污染（设计 §9.2 点名的那条）。
# ⚠️ **只读战绩**（"最好到第几波"）**不在这里** —— 它跨局持久、写独立文件，是另一回事（R5）。

## 局内状态机（`EndlessScript.Phase`：IDLE / WAVE / CLEARING / INTERMISSION / BONUS / OVER）。
##
## 不标嵌套枚举的类型（`EndlessScript.Phase`）：autoload 引用嵌套类要靠 `preload` 才稳，
## 这里存 int —— 与 `active_lan_form` / `active_mission` 同一取舍。
var endless_phase: int = 0

## 当前波次号，**从 1 开始**（0 = 第一波还没开）。
##
## ⚠️ 口径必须与 `EndlessScript` **逐字一致**：那一整套判定的 `n` 都是"从 1 开始"
##（`is_ace_wave(n)` 判 `n % WAVE_ACE_EVERY == 0`，即第 5 / 10 / 15 波是强敌波）。
## 这里要是从 0 起，强敌波与奖励轮会**整体错开一波**，而且不报错。
var endless_wave := 0

## **演习总时长**（秒，含间歇轮）。
##
## ⚠️⚠️ 不能拿 `Game.elapsed` 顶替：那个**只在 `Phase.FIGHT` 累加** ⇒ 间歇轮期间它不走，
## 于是"在选卡界面慢慢磨"变成对自己有利（时间档涨得慢 = 敌人更弱）。
## 时间档（`EndlessScript.enemy_step`）与奖励轮档位读的都是**这一个**。
var endless_elapsed := 0.0

## 本波还剩几架没被击坠（归零 ⇒ `CLEARING`）/ 本波计划刷几架。
var endless_wave_remaining := 0
var endless_wave_total := 0

## **已拿到的卡 id**（含开局自选的 3 张）。`EndlessScript.player_has_radical()` 的输入。
##
## ⚠️ 存 `id` 而不是存 `UpgradeCard` 实例：这个文件是 autoload，不该攥着一批
## 带 `Callable` 的对象（也方便判据直接比字符串）。
var endless_owned: Array[String] = []

## `endless_owned` 的**平行数组**：每一张卡各自的**品质**（`UpgradeCard.Tier`）。
##
## ⚠️⚠️ 为什么必须单独存一份品质：`UpgradeCard.by_id(id, tier)` 的 `tier` 不能省 ——
## **同一个词条名（id）在每一档各有一张卡**（`.id` 是词条名，不是"这一张"的名字）。
## 局内抽到的卡可能是 ADVANCED / PERFECT / RADICAL（§6.3 的抽取），
## 拿 `BASIC` 去找回来会**静默换成基础档那一张**（数字全对不上，而一处都不报错）。
##
## ⚠️ 与 `endless_owned` **同长同序**：两处只在 `main.spawn_endless()` 与
## `main._take_endless_card()` 里成对写入。
var endless_owned_tier: Array[int] = []

## ★ 开局自选的 3 张基础卡 id（R14 / 设计 §5.6），**菜单在开局前写**。
##
## ⚠️⚠️ 它**绝对不能**在 `Game.reset()` 里清 —— 与 `tutorial_requested` 是同一个坑：
## 链路是"菜单先写 → `spawn_round()` 里的 `Game.reset()` 再清"，清了等于白写
##（`tutorial_mode` 正因此**在真实开局里从未生效过**，1.2 第二十六轮才修）。
## ⇒ 正确链路照抄教学那套：菜单写**请求** → `reset()` 不碰它 →
##    `main.spawn_endless()` 在 reset **之后**把它落成 `endless_owned` 并消费掉。
var endless_pick_request: Array[String] = []

## 本轮间歇轮 / 奖励轮的候选卡 id（3 张）。选卡逻辑与 HUD 共读这一个。
var endless_hand: Array[String] = []

## 本轮手牌的**品质**（`UpgradeCard.Tier`）。奖励轮恒 `PERFECT`（§6.2 / Q4）。
##
## HUD 靠它把 id 还原成卡（`UpgradeCard.by_id(id, endless_hand_tier)`）——
## `draw_hand()` 只从同一档的池里取，所以一定找得回来（`draw_hand_ids()` 的头注）。
var endless_hand_tier: int = 0

## 本轮**要塞进几张**（普通轮恒 1；奖励轮按局内总时长 1/2/3，R10）与本轮**已塞几张**。
##
## ⚠️ 两张卡都要：`want` 是规则（`EndlessScript.round_picks()`），
## `got` 是进度（HUD 的"3 选 2 · 已选 1"读它）—— 合成一个数就没法回答
## "还差几张"与"这轮总该拿几张"这两个不同的问题。
var endless_hand_want := 0
var endless_hand_got := 0

## 焦点下标（`0 .. endless_hand.size()-1`）。
##
## ⚠️ 倒计时归零时**落的就是这一张**（§7.2 边界表第 1 行：不惩罚、不阻塞）。
## ⇒ 焦点必须是一个"玩家看得见"的东西（HUD 高亮它），否则超时自动选会像随机。
var endless_focus := 0

## 玩家**正在操作卡片**（移动焦点 / 查看详情）⇒ 倒计时**暂停**（§7.2 读法 A）。
## `endless_operate_secs` 是"这一段操作**累计暂停掉**的秒数"，选定后由
## `EndlessScript.refund_time()` **加回**剩余时间（= 用户那句"根据选卡的时间再延长相应的秒数"）。
##
## ⚠️ 每次输入都重置成 `true` 并把计时清零，**松开后由 `Main` 立刻置回 `false`**
## —— 换句话说：只要玩家还在动，倒计时就不走。
var endless_operating := false
var endless_operate_secs := 0.0

## 距**上一次按键**过了多久（秒）。
##
## ⚠️ 必须与 `endless_operate_secs` 分开：前者回答"这一帧还在操作吗"
##（`< EndlessScript.OPERATE_GRACE` ⇒ 在），后者回答"这一段一共暂停了多久"（要回补的量）。
##
## ⚠️⚠️ 少了这个宽限，`operating` 就会变成"动过就永久暂停" ⇒ 玩家按一次 Tab 之后走开，
## 倒计时**永远不走**、超时自动选也永远不触发 ⇒ **这一局卡死在间歇轮里**
##（而 §7.2 那两条边界 ——"一直不动 ⇒ 超时自动选"与"一直动手不选 ⇒ 不设上限"——
##  会退化成同一句话，等于其中一条从没被实现）。见 `EndlessScript.OPERATE_GRACE`。
var endless_operate_idle := 0.0

## 本轮倒计时剩余 / 总时长（秒）。总时长是画倒计时条的分母（§7.2 的"回补"会改剩余）。
var endless_intermission_left := 0.0
var endless_intermission_total := 0.0

## ★ 敌机强化系数 —— `BanditAI` 的 `reinforce` **唯一**乘它（设计 §6.4.3）。
##
## ⚠️⚠️ **非演习模式必须恒为 1.0**（判据 `NO_TOUCH_OTHERS`）：这是一处全工程共用的乘法，
## 留着上一局的残留值会让**所有既有难度套件的读数静默漂移**，而没有任何一条测试会红。
## ⇒ 不靠"记得改回来"：`reset()` 把它**钉回 1.0**，演习局里由 `_tick_endless()` 每帧覆写。
var endless_enemy_reinforce := 1.0

## 剧情挑战（1.2）：本局的遭遇脚本。null = 不是挑战局。
var active_challenge: ChallengeScript.Encounter = null
## 菜单选中的挑战 id（main 在 start_match 时用它去查 `ChallengeScript`）。
var active_challenge_id := ""
## ★ 轮 C：剧情模式**当前那一关**（`MissionScript.Mission`）。非剧情模式恒为 `null`。
##
## ## 与 `active_challenge` 并存，不是取代
## `active_challenge` 是**波次管线**的入口（`main._spawn_wave()` 只认它的 `waves`），
## 而 `Mission` 的 `waves` 与 `Encounter` 的**是同一个类型**（都来自 `ChallengeScript.Wave`）
## ⇒ 出击时把 `mission.to_encounter()` 填进 `active_challenge`，**整套波次管线一行不改**
## （DESIGN §5.1 的「升级，不是重写」）。
## `active_mission` 则装着**波次管线上游的那一层**：目标 / 触发器 / 播片槽 / 基础军资。
##
## ⚠️ 不给它标类型：`MissionScript.Mission` 是**嵌套类**，而本文件（autoload）
## 在并行编辑下引用嵌套类要靠 `preload` 才稳（见 `mission_script.gd` 里那段说明）。
## 类型只在读取处（`main` / `hud`）经 `preload` 的别名标注。
var active_mission = null
## ★ 轮 50：本局**地标被打中**的次数（“夜袭达沃”的胜利条件就数它）。
##
## 与 `challenge_*` 一样属于“这一局的状态” ⇒ `reset()` 里必须清零。
var mission_events: Dictionary = {}
var landmark_hits := 0

## ★ 轮 55：本局玩家**到过**哪些 `Zone`（zone id → true）。
##
## 语义是“**到过**”而不是“此刻在里面” —— 与 `Trigger` 的 `enter:X`（“玩家进过某个 Zone”）
## 和 `Objective` 的 `REACH`（“**到达**”）是同一个口径：碰到一次就永久算数。
## 锁存还有一条工程理由：玩家以 600+ km/h 掠过一个小球时，“进去那一帧”与
## “判定那一帧”可能差一帧 ⇒ 锁存让“飞过那一下”不会被相位差吃掉。
##
## ⚠️ 生产者是 `main._tick_mission_zones()`（每帧）；消费者两处：
##   · `_end_state()[“zones”]` → `Objective.done()` 的 `REACH` 分支（按目标自己的 zone id 查）；
##   · `trigger_state()[“zones”]` → `Trigger` 的 `enter:X`。
## ⚠️ 与 `landmark_hits` 同一条理由：**每局清零**，否则上一局飞过的区会让这一关开局即通关。
var zone_reached := {}


## ★ 轮 50：地标被弹体扫掠命中的**唯一记账口**（由 `Projectile` 调用）。
##
## ⚠️ 这里**只记账 + 发信号 + 重算一次胜负**；真正决定“算不算赢”的仍然是
## `_evaluate_end()` 那**一个出口**（它读 `MissionScript` 的 `all_required_done()`）。
## 刻意**不**在这里直接 `set_phase(Phase.WIN)` —— 否则胜利条件会分裂成两处，
## 以后改判胜规则得改两个地方、漏一个就静默不一致。
##
## ⚠️⚠️ 必须在这里**主动**调一次 `_evaluate_end()`：
## 它在全工程只有 `notify_destroyed()` 一个调用方（**没有任何周期性调用者**）。
## 而 M01 这一局**一架敌机都不会爆** ⇒ 不主动调的话，
## 玩家打中了楼、画面一切正常、**永远不结算**。
func is_strike_target(landmark: Node3D, hitter: Node3D) -> bool:
	return is_instance_valid(landmark) and is_instance_valid(hitter) and hitter == player and active_mission != null \
		and not active_mission.landmark_group.is_empty() and landmark.is_in_group(active_mission.landmark_group)

func note_landmark_hit(landmark: Node3D, hitter: Node3D) -> void:
	landmark_hits += 1
	landmark_hit.emit(landmark, hitter)
	_evaluate_end()
## ★ 轮 C：本关的结算结果 —— `CampaignScript.settle()` 的
## `{reward, delta, progress}`（DESIGN §6.3）。
## 空字典 = 非剧情模式（此时结算页**不显示军资那一行**）。
##
## ⚠️ 它是**快照**：结算页可能比战斗活得久（玩家残骸 2.2 s 后就释放了），
## 所以 `main` 在结算那一刻把它算好放在这里，HUD 只读不算 ——
## 与 `hud.capture_result()` 那套"一切取自快照"是同一条规矩。
var sally_result: Dictionary = {}
## ★ 轮 C：剧情模式的**内存进度**（`CampaignScript` 那份字典：通关位掩码 / 最好评价 /
## 军资余额 / 改装槽位 / 图鉴）。
##
## 真源是 `user://campaign.cfg`，这里是它在内存里的那一份 ——
## **进战役图时读、每次结算后写**（`main._open_campaign()` / `main._settle_campaign()`）。
## 放在 `Game` 上是为了让战役图页与结算页**不必自己去读盘**
##（读盘是 `main` 的事，与 `Game.active_mission` / `sally_result` 同一条分工）。
##
## ⚠️ `Game.reset()` **不清它** —— 它是**跨关卡**的玩家资产，不是"这一局"的状态。
## 清它的只有"新游戏"那条路（`CampaignScript.erase()`）。
var campaign_progress: Dictionary = {}
var super_hard_unlocked := false
## 局域网对战（1.2）的状态文案，由 NetSession 写、HUD 读。
## 放在 Game 上是为了让 HUD 不必认识网络层（它只画一行字）。
var lan_status := ""
## 联机里"对面已经没了"（收到对方的阵亡通知）。
var lan_remote_dead := false
## 当前波次（从 0 开始）/ 本波还剩几架 / 全场敌机总数 / 已击坠数。
## HUD 的挑战进度条与结算页都读这几个数。
var challenge_wave := 0
var challenge_wave_remaining := 0
var challenge_total := 0
var challenge_killed := 0
## 每一波各用了多少秒（结算页的"波次用时"），**按清完的顺序追加**。
## 只有挑战模式会写它；别的模式它是空的，结算页也就不显示那一段。
## ⚠️ 必须在 `reset()` 里清空 —— 不清的话上一局的波次会跟着结算页一起显示出来。
var challenge_wave_times: Array[float] = []

## 训练模式：靶机总数 / 已击破。HUD 的左下角与结算页读它。
var training_targets_total := 0
var training_targets_down := 0

## **新手教学**（1.2）：训练模式里选「新手教学」时为真。
##
## 它不改玩法（还是那片靶场、还是那些不还手的靶机），只**多一层引导**：
## 分步提示 + 机体特色详解面板。
## 所以它对 `main.spawn_training()` 的唯一影响是"HUD 多画一块"。
##
## ⚠️ 必须在 `reset()` 里清掉：不清的话"打过一次教学，之后每次打靶都挂着教学面板"。
var tutorial_mode := false
## 菜单在**开局前**写的教学请求（`main_menu._launch`）。
##
## ⚠️ 为什么不直接写 `tutorial_mode`：`spawn_round()` 里的 `Game.reset()`
## 会把它清掉 —— 菜单先写、reset 后清，等于白写（实测教学面板因此在
## 真实开局里从未显示过，1.2 第二十六轮修复）。
## 正确链路：菜单写**请求** → `spawn_round` 在 reset **之后**把它落成
## `tutorial_mode` 并消费掉（不留给下一局）。
var tutorial_requested := false

# ============================================================ ★ 制作人模式（2026-09-30）
#
## **制作人模式**（开发者模式）：解锁全部关卡与配件、便于逐关调试。
##
## ## 需求原文（老板）
## > 「在设置菜单新增一个密码系统，藏到最地下看不到的地方（手柄滑动选项可以选到），
## >  选到之后输入密码 20060606 然后按 enter 打开制作人模式，解锁各种关卡和配件，
## >  可以调试各种关卡，**制作人模式每次打开游戏都必须手动开启**。」
##
## ## ⚠️ 「每次打开游戏都必须手动开启」落实为：**它根本不落盘**
## 这一行**不上** `Settings.save_config()`（那里存的都是"下次还想要"的偏好），
## 也**不进** `CampaignScript.save_progress()` 的进度档。
## 每次进程启动它都是 `false`，只能靠那个隐藏入口 + 密码打开。
## ⇒ 判据是两条：① 新进程里它恒为 `false`；
##            ② `settings.gd` / `campaign.gd` 这两个**会写盘**的文件里
##               **一个字都不许出现 `producer`**（源码扫描，见 `suite_producer`）。
##
## ## ⚠️ `reset()` **不清它** —— 这是有意的
## `Game.reset()` 是"这一局重开"（每一关都会调）。而在制作人模式下连着调试好几关
## 恰恰是它存在的意义 —— 每进一关就被清掉的话，这个开关等于只能用一次。
## 清它的只有进程结束本身，以及玩家在设置页手动关掉（`set_producer_mode(false)`）。
##
## ## 它影响哪些地方（今天只有三处，都是**读**，没有一处是"改档"）
## | 落点 | 效果 |
## |---|---|
## | `campaign_map.producer`（由 `main._open_campaign()` 落值） | 7 关全可进（`CampaignScript.can_enter()`） |
## | 同上 —— 军资那一行 | 显示 `军资 ∞`（`CampaignScript.credits_text()`） |
## | `main_menu` 设置页那一行 | 开启后**显形**（否则开了就再也找不到、只能重启游戏） |
var producer_mode := false


## 打开 / 关上制作人模式。**唯一写入口**。
##
## ⚠️ 不在这里发信号、也不在这里 `queue_redraw()`：消费方（设置页 / 战役图）
## 都是"每一帧重画"的面板，且都在**下一次 `open()` 时**读它
##（与 `Game.active_mission` / `sally_result` 同一条分工：状态在这、怎么用归调用方）。
## ⚠️ 它**不写任何配置** —— 理由见上面那段"不落盘"。
func set_producer_mode(on: bool) -> void:
	producer_mode = on


## ★63-24：这一局是不是**无限强化演习**。
##
## 收口成一个谓词的唯一理由：消费方（`main` / `hud` / `bandit_ai`）都要问同一件事，
## 各写一遍 `match_mode == Game.MatchMode.ENDLESS` 就会出现"改一处漏一处"
##（`training_mode()` / `challenge_mode()` 那一族就是这个形状）。
func is_endless() -> bool:
	return match_mode == MatchMode.ENDLESS

## unit(instance id) -> LockOnSystem。"丢枪强行解除对方锁定"要用它反查对手的锁定系统。
var _locks := {}

## 本局统计
var elapsed := 0.0
var kills := 0
var losses := 0
## 僚机损失（2026-09-22 阵营系统完善）：**相对玩家**的同队机被击坠数。
## 判据与锁定/军刀同源（`is_hostile_to`），在 `notify_destroyed` 里记。
var allies_lost := 0
## 友军火力拦截（同上）：`take_damage` 的友军闸门每拦一次 +1。
## 结算页用它回答"这一局我的火力线扫过自己人多少次" —— 拦截不该是无声的。
var friendly_fire_blocked := 0
var shots_fired := 0
var hits := 0
var missiles_fired := 0
var missiles_hit := 0

# ---------------------------------------------------------------- 结算菜单用
#
# "战斗经过"是一份带时间戳的事件流水。刻意用**事件**而不是每帧采样：
# 结算时玩家想看的是"什么时候被击穿了护盾、什么时候放掉了最后一把枪"，
# 而不是 60 Hz 的状态曲线。
## 每条 { "t": 发生时刻（秒）, "text": 说明 }
var battle_log: Array[Dictionary] = []
const LOG_LIMIT := 60

## 损耗
var damage_taken := 0.0        ## 打到机体上的伤害
var ifield_taken := 0.0        ## 自己的 I 立场被消耗掉的量
var gun_shots := 0
var beam_shots := 0
var rifle_stats = preload("res://scripts/combat/rifle_accuracy.gd").new()
var _rifle_report_wait := 0.0
## Test runners opt out of human samples, including injected input events.
var rifle_metrics_test_mode := false
var funnels_fired := 0
var rifles_discarded := 0
var saber_hits := 0
## 军刀**相杀**次数（1.2）。双方在对撞窗口内都用军刀才计一次。
var saber_clashes := 0
var flares_used := 0
## 击毁的**飞行踏板**数（1.2）。结算页的"损耗与战果"用它 ——
## 打掉踏板是这一版新加的一类战果，不记下来的话玩家在结算里看不到自己做过这件事。
var pedals_destroyed := 0
var ifield_broken_self := false
var ifield_broken_foe := false

## 战果
var damage_dealt := 0.0
var ifield_dealt := 0.0
var locks_acquired := 0
var locks_lost := 0
var missiles_incoming := 0


## ---- 每物理帧缓存（批 10 性能二轮，2026-09-22）----
##
## 两个热点都长一个样：**同一帧里很多消费者反复扫同一批节点**，
## 而每次 `get_nodes_in_group` / 每次重建敌我列表都是一次新数组分配：
##   · `Projectile._missile_in_path`（每弹每物理帧）、`Missile._check_intercept`
##     （每弹每物理帧）、`incoming_missiles()`（每台 AI 每帧）……全都在扫
##     "missiles" 组 —— 百发齐射 + 拦截弹满天飞的一帧，光组查询就是几百次数组分配；
##   · `Game.live_hostiles_of` 被每台机的 LockOnSystem、HUD 雷达、AI 选目标、
##     威胁表各调一次 —— O(机数²) 次遍历 + 每次一份新 Array。
##
## 缓存键 = 物理帧号（`Engine.get_physics_frames()`），跨帧自动失效。
## **语义代价是一物理帧的陈旧**（本帧新出生的节点下一帧才可见）——
## 对"拦截 / 威胁 / 选目标"这类邻近度判定完全无感；而"死亡可见性"靠
## 命中时**原地剔除**保住（见 `_prune_unit_list`），死掉的单位同一帧内就会消失。
var _snap_tree: SceneTree = null
var _snap_tick := -1
var _snaps := {}
var _snap_members := {}
var _unit_tick := -1
var _hostile_snaps := {}
var _ally_snaps := {}


## "group" 组成员的**本物理帧共享快照**。返回的数组是共享的，
## 消费者只许读、不许改（有效性自检照旧自己做 —— 与直接扫组一致）。
func group_snapshot(tree: SceneTree, group: String) -> Array:
	if tree == null:
		return []
	if _snap_tree != tree:
		if is_instance_valid(_snap_tree) and _snap_tree.node_removed.is_connected(_snapshot_node_removed):
			_snap_tree.node_removed.disconnect(_snapshot_node_removed)
		_snap_tree = tree
		tree.node_removed.connect(_snapshot_node_removed)
		_snap_tick = -1
	var tick := Engine.get_physics_frames()
	if _snap_tick != tick:
		_snap_tick = tick
		_snaps.clear()
		_snap_members.clear()
	if not _snaps.has(group):
		var members := tree.get_nodes_in_group(group)
		_snaps[group] = members
		for node: Node in members:
			var id := node.get_instance_id()
			if not _snap_members.has(id):
				_snap_members[id] = []
			if not _snap_members[id].has(group):
				_snap_members[id].append(group)
	return _snaps[group]


func _snapshot_node_removed(node: Node) -> void:
	# The tree emits this before destruction. Only removals of cached members
	# invalidate snapshots; unrelated HUD/particle churn keeps the hot path cached.
	# IDs do not retain nodes or connect one signal per projectile.
	var id := node.get_instance_id()
	if _snap_members.has(id):
		for group: String in _snap_members[id]:
			_snaps.erase(group)
		_snap_members.erase(id)



## 还没死的敌方单位（本物理帧内共享一份；死亡项命中时原地剔除）。
func live_hostiles_of(unit: Node3D) -> Array[Node3D]:
	return _cached_unit_list(unit, _hostile_snaps, true)


## `live_hostiles_of()` 的同款缓存版（互补判据原样保留，见下）。
func live_allies_of(unit: Node3D) -> Array[Node3D]:
	return _cached_unit_list(unit, _ally_snaps, false)


func _cached_unit_list(unit: Node3D, cache: Dictionary, hostile: bool) -> Array[Node3D]:
	var tick := Engine.get_physics_frames()
	if _unit_tick != tick:
		_unit_tick = tick
		cache.clear()
	if not cache.has(unit):
		var built: Array[Node3D] = []
		for u: Node3D in units:
			if u == unit or not is_instance_valid(u) or u.is_queued_for_deletion():
				continue
			if not u.has_method("is_alive") or not u.is_alive():
				continue
			if u.has_method("is_hostile_to") and u.is_hostile_to(unit) == hostile:
				built.append(u)
		cache[unit] = built
	var arr: Array[Node3D] = cache[unit]
	# 命中也可能带着"本帧早些时候死掉"的条目（缓存建立之后才被击坠）——
	# 原地剔除，保证调用方拿到的永远是活人；判据与建表时完全一致。
	for i in range(arr.size() - 1, -1, -1):
		var u: Node3D = arr[i]
		if not is_instance_valid(u) or u.is_queued_for_deletion() \
				or not u.has_method("is_alive") or not u.is_alive():
			arr.remove_at(i)
	return arr


func _exit_tree() -> void:
	rifle_stats.save_report()


func _process(delta: float) -> void:
	clock += delta
	_rifle_report_wait -= delta
	if _rifle_report_wait <= 0.0:
		rifle_stats.save_report()
		_rifle_report_wait = 1.0 if phase in [Phase.WIN, Phase.LOSE] else 5.0
	if phase == Phase.FIGHT:
		elapsed += delta


## 记一条战斗经过。t 用本局已过时间，所以结算菜单上的时间轴是自洽的。
func log_event(text: String) -> void:
	battle_log.append({"t": elapsed, "text": text})
	if battle_log.size() > LOG_LIMIT:
		battle_log.pop_front()


## 结算菜单用：把事件流水格式化成 "[mm:ss] 文本"。
func log_lines() -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in battle_log:
		var t: float = e.get("t", 0.0)
		out.append("%02d:%02d  %s" % [int(t) / 60, int(t) % 60, str(e.get("text", ""))])
	return out


## 清空一局的全部状态（重开时调用）。
func reset() -> void:
	rifle_stats.save_report()
	rifle_stats = preload("res://scripts/combat/rifle_accuracy.gd").new()
	_rifle_report_wait = 0.0
	phase = Phase.INTRO
	player = null
	units.clear()
	_locks.clear()
	elapsed = 0.0
	kills = 0
	losses = 0
	allies_lost = 0
	friendly_fire_blocked = 0
	shots_fired = 0
	hits = 0
	missiles_fired = 0
	missiles_hit = 0
	battle_log.clear()
	damage_taken = 0.0
	ifield_taken = 0.0
	gun_shots = 0
	beam_shots = 0
	funnels_fired = 0
	rifles_discarded = 0
	saber_hits = 0
	saber_clashes = 0
	flares_used = 0
	pedals_destroyed = 0
	ifield_broken_self = false
	ifield_broken_foe = false
	damage_dealt = 0.0
	ifield_dealt = 0.0
	locks_acquired = 0
	locks_lost = 0
	missiles_incoming = 0
	# 靶机总数由 main 在撒靶机时写入，这里只清"打掉了几架"。
	training_targets_down = 0
	# 新手教学：不清的话"打过一次教学，之后每次打靶都挂着教学面板"。
	tutorial_mode = false
	# 挑战进度同理：脚本本身（active_challenge）由 main 注入，进度每局清零。
	challenge_wave = 0
	challenge_wave_remaining = 0
	challenge_total = 0
	challenge_killed = 0
	challenge_wave_times.clear()
	# ★ 轮 C：军资结算快照**每局清零** —— 与上面几个挑战进度同款理由：
	# 不清的话，上一局的 "+N" 会跟着下一局的结算页一起显示出来。
	sally_result = {}
	# ★ 轮 50：地标命中计数**每局清零** —— 与 `sally_result` 同一条理由：
	# 不清的话，上一局在达沃打中的那一枪会让这一关**开局即通关**。
	mission_events.clear()
	landmark_hits = 0
	# ★ 轮 55：`zone_reached` 同理 —— 不清的话，上一局飞过的运输仓接收区
	# 会让 M03 在**开局那一帧**就满足 `REACH` ⇒ 结算页直接跳出来。
	zone_reached.clear()
	# ★63-24：无限强化演习的**局内状态**逐项归零（设计 §9.2）。
	#
	# ⚠️ 这一批是 autoload 上的变量 ⇒ 跨局是活的；不清的话"第二局开局就带着上一局的
	# 波次号 / 已拿卡 / 敌机强化倍率"，而画面看起来一切正常。
	# 判据：连续开两局，第二局起始状态与第一局**逐字段一致**（`suite_endless` 的 `RESET` 分节）。
	endless_phase = 0                      # EndlessScript.Phase.IDLE
	endless_wave = 0
	endless_elapsed = 0.0
	endless_wave_remaining = 0
	endless_wave_total = 0
	endless_owned.clear()
	endless_owned_tier.clear()
	endless_hand.clear()
	# ★ 间歇轮那一组：手牌品质 / 该拿几张 / 已拿几张 / 焦点 / 操作计时。
	#
	# ⚠️ `endless_operating` 也必须归零：不清的话，上一局在"正在操作卡片"那一帧
	# 结束的话，下一局的第 1 波里倒计时**一开局就是暂停的**（玩家看不见任何东西，
	# 只表现为"这一局怎么一直不刷下一波"）。
	endless_hand_tier = 0
	endless_hand_want = 0
	endless_hand_got = 0
	endless_focus = 0
	endless_operating = false
	endless_operate_secs = 0.0
	endless_operate_idle = 0.0
	endless_intermission_left = 0.0
	endless_intermission_total = 0.0
	# ⚠️⚠️ 钉回 1.0 而不是"清零"：它是一个**乘法因子**，0 会让敌机强化变成"完全不开火"，
	# 而残留的 >1 值会污染非演习模式。1.0 = 与"没有这个模式之前"逐位相同。
	endless_enemy_reinforce = 1.0
	# ⚠️ **故意不清 `endless_pick_request`** —— 它是"菜单刚写下、还没被消费"的**请求**，
	# 而 `reset()` 恰恰发生在它被消费**之前**（`spawn_round()` 第一步就是 reset）。
	# 清了 = 玩家的自选 3 张卡在真实开局里永远收不到（与 `tutorial_requested` 同款坑）。


## 登记某台机的锁定系统。
func register_lock(unit: Node3D, lock) -> void:
	if unit == null:
		return
	_locks[unit.get_instance_id()] = lock


## 某台机被击坠时，**立刻**把指向它的锁定目标清掉。
##
## 为什么必须"在击坠那一瞬间"做，而不是等锁定系统自己在下一个物理帧发现：
## `LockOnSystem.target` 存的是**强引用**，而全库有 6 处读取点都是**带类型赋值**
## （`var t: FlightBody = lock.target`、`chase.aim_target = lock.target` …）。
## 在"节点已释放，但锁定系统还没清"的那一帧里，这些写法会直接抛
## `previously freed` —— 表现是**随机报错**（敌人爆掉的同一帧刚好在画 HUD 就会中招）。
##
## 在源头清掉之后，那些读取点不必各自加判断：**数据不该在缓存里过期**。
func forget_locks_of(unit: Node3D) -> void:
	if unit == null:
		return
	for key: int in _locks.keys():
		var lk = _locks[key]
		if lk == null or not is_instance_valid(lk):
			continue
		lk.force_drop_if_target(unit)


func lock_of(unit: Node3D) -> Variant:
	if unit == null or not is_instance_valid(unit):
		return null
	var l = _locks.get(unit.get_instance_id())
	if l == null:
		return null
	if not is_instance_valid(l):
		return null
	return l


## 取"正在跟 unit 敌对的那一方"的锁定系统（1v1 场景下就是对手）。
func lock_of_opponent_of(unit: Node3D) -> Variant:
	for u: Node3D in units:
		if u == unit or not is_instance_valid(u):
			continue
		if u.has_method("is_hostile_to") and u.is_hostile_to(unit):
			return lock_of(u)
	return null


func register(unit: Node3D) -> void:
	if unit == null or units.has(unit):
		return
	units.append(unit)
	unit.tree_exiting.connect(_on_unit_exiting.bind(unit), CONNECT_ONE_SHOT)
	unit_spawned.emit(unit)


func _on_unit_exiting(unit: Node3D) -> void:
	units.erase(unit)


func mark_player(unit: Node3D) -> void:
	player = unit


func set_phase(p: int) -> void:
	if phase == p:
		return
	phase = p
	phase_changed.emit(p)


## 还没死的敌方单位 / 同队单位：实现在上面（每物理帧缓存版，批 10 性能二轮）。
## ⚠️ 互补判据（"is_hostile_to" 一真一假、同一套存活判据）在 `_cached_unit_list`
## 里是**同一段代码**—— 不可能出现"某台既不算敌人也不算队友"的空洞。


func live_player() -> Node3D:
	if is_instance_valid(player) and not player.is_queued_for_deletion() \
			and player.has_method("is_alive") and player.is_alive():
		return player
	return null


## 由被击坠单位自己调用。
func notify_destroyed(unit: Node3D, killer: Node3D) -> void:
	if unit == player:
		losses += 1
	elif killer == player:
		kills += 1
	# ---- 僚机损失记账（2026-09-22 阵营系统完善）----
	# 判"**相对玩家**是不是同队"，而不是"是不是玩家亲手打死的"：
	# 僚机撞地自毁、被流弹蹭死都算损失，结算页要如实报。
	# 守卫与 `live_allies_of` 同一套（player 有效 + 双方都是机体 + 非敌对）。
	if unit != player and player != null and is_instance_valid(player):
		var victim := unit as FlightBody
		var pf := player as FlightBody
		if victim != null and pf != null and not victim.is_hostile_to(pf):
			allies_lost += 1
	# 训练模式：打掉的每一架靶机都记一笔（HUD 左下角 "5 / 8" 读的就是它）。
	# 判据用"不是玩家"而不是"killer 是玩家"：靶机撞地自毁也该算消耗掉一架，
	# 否则玩家可能永远打不完这一局。
	if match_mode == MatchMode.TRAINING and unit != player:
		training_targets_down += 1
	unit_destroyed.emit(unit, killer)
	_evaluate_end()


func _evaluate_end() -> void:
	if phase != Phase.FIGHT:
		return
	if live_player() == null:
		set_phase(Phase.LOSE)
		return
	# ★ 轮 50：剧情关的**目标门** —— 只在 `win_on_clear == false` 的关上启用。
	#
	# ⚠️ 位置故意放在“场上无敌对单位”**之前**：将来要是出现
	# “一边打一边去突袭地标”的关，它也必须进得来这道门。
	#
	# ⚠️⚠️ **只在 opt-in 的关上替代**老判胜 ⇒ 其余关（`win_on_clear` 默认 true）
	# 的判胜路径**逐位不变**。
	# （⚠️ **不写数量**：这里原本写着「其余七关」，而 8→7 关重构之后它就是错的了。）
	# 当初写成“只要是剧情关就要求 `all_required_done()`”是**错的**：
	# `Objective.done()` 里除 DESTROY_ALL / STRIKE 之外那 8 种 kind 读的键
	#（zone_destroyed / protected_alive / salvaged / in_zone …）**运行时没人写**，
	# `_i()` 一律拿到 0 ⇒ 恒假 ⇒ 那几关会**静默地变成打不赢**。门必须默认关着。
	# （⚠️ 不写具体关号：它们会随任务表增删而变——原本写的「M03..M07」就是这么过期的。）
	if active_mission != null and not bool(active_mission.win_on_clear):
		if active_mission.all_required_done(_end_state()):
			set_phase(Phase.WIN)
		return
	# ★63-24：**无限强化演习永不判胜**（设计 §10）—— 它没有"最后一波"，只有"被击坠"。
	#
	# ⚠️ 为什么不能靠下面那条挑战波次守卫：演习**不走**挑战波次管线
	#（`active_challenge` 恒为 `null`）⇒ `active_challenge != null and …`
	# 根本不成立，直接落到 `set_phase(Phase.WIN)`。
	# 而"清完一波 → 1.2 s 收尾 → 间歇轮 → 下一波"这一圈里**必然**有一段场上空场
	# ⇒ 不拦的话**第一波清空就弹胜利结算**（症状与设计 §4.3 点名的卡点同源）。
	#
	# ⚠️⚠️ 位置必须夹在「玩家已经没了」那条**之后**、判胜那条**之前**：
	# 本模式的终止条件是"玩家被击坠"，走的是上面的 `Phase.LOSE` —— 拦太早会连终止一起拦掉。
	if match_mode == MatchMode.ENDLESS:
		return
	if player != null and live_hostiles_of(player).is_empty():
		# ⚠️ 挑战模式：**还有没刷出来的波次时不许判胜**。
		#
		# 用户报的 bug：清掉两台古斯塔夫之后结算直接跳出来。根因是信号顺序 ——
		# 第二台爆掉的那一帧里，"场上没有敌机"这个判断成立，
		# 而"刷下一波"要等 `main` 的 `destroyed` 回调（甚至要等坟场计时器）。
		# 于是判胜抢在刷怪前面跑，玩家看到的是一张胜利结算而不是阿利宙斯。
		#
		# 这里用**波次表**判而不是"等一会儿再看"：波次是数据，不会有时序问题。
		if active_challenge != null and challenge_wave + 1 < ChallengeScript.wave_count(active_challenge):
			return      # 交给 main 刷下一波，胜负等最后一批清完再说
		set_phase(Phase.WIN)


## ★ 轮 50：**公开**的“再判一次胜负”入口 —— 给“事件驱动、但不在
## `notify_destroyed()` 那条路上”的胜利条件用（M01：打中地标）。
##
## ⚠️ 为什么要一个公开壳：胜负的**唯一出口**是 `_evaluate_end()`（私有约定），
## 外面的 `main` 不许自己 `set_phase(WIN)` —— 一旦开了那个口子，
## “谁判胜”就分裂成两处，以后改规则漏一处就静默不一致。
## ⇒ 外面要重算，只能走这里。
##
## ⚠️ 幂等：连续调它只会跑同一条判断，`set_phase()` 自己挡同值
## ⇒ 不会重复发信号。调用方**不必**关心“我是不是已经算过了”。
func recheck_end() -> void:
	_evaluate_end()


## ★ 轮 50：喂给 `MissionScript` 的**运行时状态字典**（剧情关目标判定的唯一入口）。
##
## ⚠️ 只喂字典、**不许**让 `mission_script.gd` 去读 `Game.*` ——
## 那个文件是“纯数据 + 纯函数”（轮 C 铁律），一读 autoload 就没法逐点验。
##
## ⚠️⚠️ 键必须与 `Objective.done()` 分派表里读的**完全对上**：少一个键 ⇒
## `_i()/_f()/_b()` 一律拿到 0 / 0.0 / false ⇒ 那一类目标**永远不成立、且不报错**
##（表现只是“这一关打不赢”）。多喂的键无害。
## ⇒ 将来让某一关 opt-in（`win_on_clear = false`）时，**先在这里补键**。
##
## 当前覆盖的 kind：`STRIKE`(landmark_hits) / `DESTROY_ALL`(killed + total)
## / `SURVIVE`(elapsed) / `REACH`(zones)。其余 kind 所需的键**故意留空**
##（缺省 0 ⇒ 恒假 ⇒ fail-closed，不会把“没接”误判成“已达成”）。
func _end_state() -> Dictionary:
	return {
		"mission_events": mission_events.duplicate(),
		"landmark_hits": landmark_hits,
		"killed": challenge_killed,
		"total": challenge_total,
		"elapsed": elapsed,
		# ★ 轮 55：`REACH`（“抵达”）—— zone id → 玩家到过没有（**精确**的那一份）。
		# `Objective.done()` 拿目标自己的 `target`（就是 zone id）来查它 ⇒ 一关有
		# 两个 `REACH` 目标时，到过一个**不会**把另一个也算完成。
		# ⚠️ 不给聚合键 `in_zone`：那是“到过任意一个区”，粒度不够 —— 留着它就是
		#    “一条能把两件事混成一件的捷径”，而 `done()` 只在**调用方显式喂**时才回退到它。
		"zones": zone_reached.duplicate(),
	}


## ★ 轮 E：喂给 `CommsDirector.tick_mission()` 的**触发器**状态字典。
##
## ⚠️ 它是 `_end_state()`（目标门那套键）**再加几个触发器专有的**，不是另起一份 ——
## 触发器的 `when` 能读的键（`Trigger.KEYS`）比目标门多出 `hp` / `all_done` / `kills`。
##
## ⚠️ `hp` 只在**玩家还活着**时才写：`Trigger._value()` 对 `hp` 读的就是 `hp_ratio`，
## 缺省 **1.0**（`float(st.get("hp_ratio", 1.0))`）。这是**有意的 fail-closed 方向** ——
## 玩家没了的时候 `hp<0.2` 不该成立（那一局已经由 `_on_player_destroyed()` 那条路
## 结算掉了）；写成 0.0 会让"自己刚爆掉"和"被判重伤失败"在相邻两帧里各发生一次。
##
## ⚠️ 这里写进去的键**必须**同时出现在 `trigger_keys_sourced()` 里 ——
## 那两处是一条链的两半，谁少一个都会静默（详见那张表的注释）。
func trigger_state(m) -> Dictionary:
	var st := _end_state()
	st["kills"] = kills
	var p := live_player()
	if p != null:
		st["hp_ratio"] = p.hp_ratio()
	st["all_done"] = m != null and bool(m.all_required_done(st))
	return st


## ★ 轮 E：`trigger_state()` **这一帧真能作数**的键。
##
## ⚠️⚠️ 这是"接线"这件事的**安全阀**，不是可有可无的文档：
## `Trigger.eval()` 对**没有源的键**不是中性的 —— `>=` 形态缺省 0 ⇒ 恒假（安全的半边），
## `<` 形态缺省 0 ⇒ **恒真**（危险的那半边）。于是"把触发器接上"这个**动作本身**
## 会把"我还没实现的功能"变成"它无条件成立的功能"，而且**一处都不报错**。
##
## 现实里那一条：M06/M07 的 `protected_alive<1`（全工程没有任何地方统计"受保护单位"
## ⇒ 缺省 0 ⇒ 恒真）⇒ 一接线那两关**开局即判负**。
## ⇒ 消费方（`main._tick_mission_triggers()`）动手前先问一句
## "这条 `when` 依赖的每个键都在这张表里吗"，不在就**跳过 + `push_warning`**。
##
## **本轮还没有源的**（数据里已经写了、运行时还不作数 —— 属轮 D/G/H）：
##   `salvaged`（**轮 56 起没有关卡在用**）/ `intercepted`（M06）
##   / `protected_alive`（M06/M07）/ `zone_ratio`（M05）/ `target_hp_ratio`（M04）
##   / `waves_cleared`（M07 的 `wave_cleared:0` —— `challenge_wave` 只在**挑战模式**
##   里维护，剧情关拿它当"已清波数"是错的，所以**不**写进表里骗自己）。
## ⚠️ 往这张表里加一个键 = 声明"我有源了"，同时得保证 `trigger_state()` 真写了它。
func trigger_keys_sourced() -> PackedStringArray:
	return PackedStringArray(["elapsed", "kills", "killed", "total", "landmark_hits",
		"hp_ratio", "all_done", "zones", "mission_events"])


## 命中率（0..1），HUD 结算用。
func accuracy() -> float:
	if shots_fired <= 0:
		return 0.0
	return float(hits) / float(shots_fired)
