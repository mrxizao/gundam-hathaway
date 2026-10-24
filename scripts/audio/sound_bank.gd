class_name SoundBank
extends RefCounted
## 音频资源表：**所有音频路径只在这一个文件里出现**。
##
## 素材来自用户提供的三个目录，复制进工程时统一改成 ASCII 路径
## （原文件名里带中文、空格、方括号、变音符，在 res:// 里容易出岔子）：
##   assets/audio/sfx/  ← 游戏\gundam voice + 游戏\g voice\...UI 音效
##   assets/audio/bgm/  ← 游戏\gundam 105 muisc
##
## 命名尽量贴近用途而不是原文件名，这样调用点读起来是"我要放锁定警报"，
## 而不是"我要放 Lock-on alarm1"。

const DIR_SFX := "res://assets/audio/sfx/"
const DIR_BGM := "res://assets/audio/bgm/"

## 音效名 → 文件名。扩展名随素材原样（mp3 / ogg / wav 混着来）。
const SFX := {
	# ---- 武器 ----
	"beam_rifle": "beam_rifle.mp3",
	"beam_saber": "beam_saber.mp3",
	"vulcan": "vulcan.mp3",
	"funnel_fire": "funnel_fire.wav",
	# ---- 爆炸 ----
	# 这三条**不是"三档大小"**，而是三种不同的用途（用户指定）：
	#   boom_m = 远处导弹爆炸    boom_s = 近处导弹爆炸    boom_l = 机体爆炸
	# M 与 S 是同一件事的两版录音（远场 / 近场），
	# 所以要在播放前按"离镜头多远"二选一 —— 靠音量衰减糊不过去，
	# 因为远场那版录音本身就更闷、尾巴更长。
	"boom_s": "boom_s.mp3",   ## 近处导弹爆炸
	"boom_m": "boom_m.mp3",   ## 远处导弹爆炸
	"boom_l": "boom_l.mp3",   ## 机体爆炸（击坠）
	# ---- 警报（三种，用在不同的警报提示上，不只是"被锁定"）----
	"alarm_lock": "alarm1.ogg",        ## 敌机锁定了你
	"alarm_missile": "alarm2.ogg",     ## 有导弹在追你
	"alarm_critical": "alarm3.ogg",    ## I 立场被击穿 / 残血 / 地形告警
	# ---- 系统 ----
	"startup": "startup.mp3",
	# ---- 阿利宙斯变形（1.1，素材由用户提供）----
	# 变形冷却 4 秒（用户指定）—— 所以这条不会连响，不需要节流表。
	"arizeus_transform": "arizeus_transform.mp3",
	# 1.2：**军刀命中**的独立音效（用户提供的素材）。
	# 之前命中复用的是挥刀的 `beam_saber`（只是压低音量），所以"挥"和"砍中"听感一样 ——
	# 那是这套音效里最后一块缺的。
	"saber_impact": "saber_impact.mp3",
	# ---- 引擎循环（循环播放，音量随速度）----
	"cruise_xi": "cruise_xi.mp3",
	"cruise_penelope": "cruise_penelope.mp3",
	# ---- 柯西座舱的巡航检测音（1.5 秒一次，只有开柯西才听得到）----
	"xi_detect": "xi_detect.ogg",
	# ---- 菜单 UI ----
	"ui_select": "ui_select.ogg",
	"ui_confirm": "ui_confirm.ogg",
	"ui_return": "ui_return.ogg",
	"ui_item": "ui_item.ogg",
	"ui_save": "ui_save.ogg",
	"ui_save2": "ui_save2.ogg",
}

## 座舱告警语音（§4.3.3）。
##
## ⚠️ **故意不与 `SFX` 合并**，尽管它们的路径规则一模一样。
## 理由：`suite_audio` 有一条门 —— **`SFX` 表里每一条都必须在磁盘上有文件**。
## 那条门本身很值钱（它挡的是"文件名写错一个字母、运行时静默没声"），
## 所以不能为了塞进 4 条**还没到货**的语音而把它变钝。
## 于是分两张表，语义也不同：
##   · `SFX`  —— 登记即承诺存在（缺一个就是 FAIL）；
##   · `VOICE` —— **允许缺失**，缺了走 `VOICE_FALLBACK` 的降级（§4.3.2）。
## 素材到货那天：把这 4 个 wav 丢进 `assets/audio/sfx/` 即可，代码一行都不用动。
const VOICE := {
	"voice_pull_up": "voice_pull_up.wav",
	"voice_missile": "voice_missile.wav",
	"voice_stall": "voice_stall.wav",
	"voice_over_g": "voice_over_g.wav",
}

## BGM 名 → 文件名
##
## 1.1：`senkou`（閃光）从结算曲挪进战斗轮换；结算与训练场用 `sweet_child`。
## 1.2 用户把结算曲的规则说细了（**按地图 + 这一局用过哪首**决定）：
##
## | 场合 | 结算曲 |
## |---|---|
## | 艾尔斯岩 | `sweet_child`（Sweet Child O' Mine） |
## | 太平洋上空 | `senkou`（閃光） |
## | 对战里那一局**用过 閃光 当战斗曲** | `special_result`（特殊结算曲） |
## | 训练场（废墟靶场） | `sweet_child` |
##
## 而**战斗轮换**分两套：
##   - **对战模式**：六首（TRACER / NDA-α / XI / **閃光** / **car5p3 / PENELOPE** / **MNE**）；
##   - **剧情挑战**：五首（**不含閃光** —— 用户："闪光在剧情不作为战斗曲用"，
##     因为它是"太平洋上空的结算曲"，在剧情里提前当战斗曲放掉就糟蹋了那一下）。
##
## ⚠️ 2026-09-21 老板给了两首新战斗曲（`澤野弘之 - car5p3 / PENELOPE`、`澤野弘之 - MNE`）：
## 它们**两套池子都进** —— 只有 `senkou` 有"留给太平洋结算"这条特例，
## 新曲没有这层身份，在剧情里当战斗曲放是对的。
const BGM := {
	"thunderbolt_main_theme": "thunderbolt_main_theme.mp3",
	"yes_girl": "yes_girl.mp3",
	"mobius": "mobius.mp3",         ## 主菜单（三首之一，见 MENU_TRACKS）
	"tracer": "tracer.mp3",         ## 战斗（对战与剧情都用 —— 不再写死"几选一"）
	"nda_alpha": "nda_alpha.mp3",   ## 战斗
	"xi": "xi.mp3",                 ## 战斗
	"senkou": "senkou.mp3",         ## 对战战斗曲 + **太平洋上空的结算曲**
	"sweet_child": "sweet_child.mp3",  ## 艾尔斯岩结算 + 训练场
	"special_result": "special_result.mp3",  ## 对战里用过閃光当战斗曲时的结算曲
	# ---- 1.2 追加的两首战斗曲（用户 2026-09-21 提供）----
	# 键名沿用歌曲名（`xi` / `nda_alpha` / `mobius` 就是这个规矩），不按机体起名：
	# `car5p3` 的正式曲名是「car5p3 / PENELOPE」，`mne` 就是「MNE」。
	"car5p3": "car5p3_penelope.mp3",   ## 战斗（佩涅罗佩主题曲）
	"mne": "mne.mp3",                  ## 战斗
	# ---- ★63-20（2026-10-08）：`D:\闪哈游戏历代音乐` 的 46 首历代曲 ----
	# ⚠️ **一首都没有进 `BATTLE_TRACKS` / `STORY_BATTLE_TRACKS`** —— 它们只进
	#   `OPT_IN_BATTLE_TRACKS`（玩家不选就不播）。这不是漏改，是本批的**全部要求**。
	# 键名 = 目标文件名的 ASCII 化；显示名见 `BATTLE_TRACK_LABELS`。
	# 原文件名 / 逐条 md5 的对照表在工作区 `_r63_20_manifest.tsv`。
	"re_i_am": "re_i_am.mp3",                                            ## RE:I AM（Aimer）
	"cerulean": "cerulean.mp3",                                          ## セルリアン（BACK-ON）
	"nibun_no_ichi": "nibun_no_ichi.mp3",                                ## ニブンノイチ（BACK-ON）
	"survivor": "survivor.mp3",                                          ## Survivor（BLUE ENCOUNT）
	"akatsuki_no_kuruma": "akatsuki_no_kuruma.mp3",                      ## 暁の車（FictionJunction,南里侑香）
	"moeagare_toshi": "moeagare_toshi.mp3",                              ## 燃え上がれ闘志 忌まわしき宿命を越えて（Kohei Tanaka）
	"waga_kokoro_meikyo_shisui": "waga_kokoro_meikyo_shisui.mp3",        ## 我が心 明鏡止水（Kohei Tanaka）
	"daybreaks_bell": "daybreaks_bell.mp3",                              ## DAYBREAK'S BELL（L'Arc〜en〜Ciel）
	"men_of_destiny": "men_of_destiny.mp3",                              ## MEN OF DESTINY（MIQ）
	"rage_of_dust": "rage_of_dust.mp3",                                  ## RAGE OF DUST（SPYAIR）
	"snooze": "snooze.mp3",                                              ## Snooze（SZA）· 也是主菜单曲
	"cage_ntv": "cage_ntv.mp3",                                          ## Cage (NTv)（SawanoHiroyuki[nZk]; Tielle）
	"anna_ni_issho": "anna_ni_issho.mp3",                                ## あんなに一绪だったのに（See-Saw）
	"beyond_the_time": "beyond_the_time.mp3",                            ## BEYOND THE TIME（TM NETWORK）
	"just_communication": "just_communication.mp3",                      ## JUST COMMUNICATION（TWO-MIX）
	"rhythm_emotion": "rhythm_emotion.mp3",                              ## RHYTHM EMOTION（TWO-MIX）
	"freesia": "freesia.mp3",                                            ## フリージア（Uru）
	"shukufuku": "shukufuku.mp3",                                        ## 祝福（YOASOBI）
	"flying_in_the_sky": "flying_in_the_sky.mp3",                        ## FLYING IN THE SKY（Yoshifumi Ushima）
	"trust_you_forever": "trust_you_forever.mp3",                        ## Trust You Forever（Yoshifumi Ushima）
	"silent_voice": "silent_voice.mp3",                                  ## サイレント・ヴォイス（ひろえ純）
	"red_birthmark": "red_birthmark.mp3",                                ## Red:birthmark（アイナ・ジ・エンド）
	"main_title": "main_title.mp3",                                      ## MAIN TITLE（三枝成彰）
	"ai_senshi": "ai_senshi.mp3",                                        ## 哀 戦士（井上大輔）
	"trust_you": "trust_you.mp3",                                        ## trust you（伊藤由奈）
	"fight_kawai": "fight_kawai.mp3",                                    ## Fight（川井憲次）
	"anime_ja_nai": "anime_ja_nai.mp3",                                  ## アニメじゃない（新井正人）
	"mou_dou_natte_mo_ii_ya": "mou_dou_natte_mo_ii_ya.mp3",              ## もうどうなってもいいや（星街すいせい）
	"yoru_ni_saku": "yoru_ni_saku.mp3",                                  ## 夜に咲く（星街すいせい）
	"the_winner": "the_winner.mp3",                                      ## THE WINNER（松原みき）
	"sassou_taru_char": "sassou_taru_char.mp3",                          ## 颯爽たるシャア（松山祐士）
	"yoake_no_shooting_star": "yoake_no_shooting_star.mp3",              ## 夜明けのShooting Star（林原めぐみ）
	"mizu_no_hoshi_e_ai_wo_komete": "mizu_no_hoshi_e_ai_wo_komete.mp3",  ## 水の星へ愛をこめて（森口博子）
	"itsuka_sora_ni_todoite": "itsuka_sora_ni_todoite.mp3",              ## いつか空に届いて（椎名恵）
	"urdr_hunt": "urdr_hunt.mp3",                                        ## Urdr-Hunt（横山克）
	"earth_nt": "earth_nt.mp3",                                          ## EARth（澤野弘之）· 也是主菜单曲
	"unicorn": "unicorn.mp3",                                            ## UNICORN（澤野弘之）
	"vigilante": "vigilante.mp3",                                        ## Vigilante（澤野弘之; mpi; R!N_Gemie）
	"colony_no_kanojo": "colony_no_kanojo.mp3",                          ## コロニーの彼女（照井順政）
	"reborn": "reborn.mp3",                                              ## Reborn（玉置成実）
	"arashi_no_naka_de_2": "arashi_no_naka_de_2.mp3",                    ## 嵐の中で輝いて（另一版）（米倉千尋）
	"arashi_no_naka_de": "arashi_no_naka_de.mp3",                        ## 嵐の中で輝いて（米倉千尋）
	"plazma": "plazma.mp3",                                              ## Plazma（米津玄師）
	"freedom": "freedom.mp3",                                            ## FREEDOM（西川貴教）
	"invoke": "invoke.mp3",                                              ## INVOKE（西川貴教）
	"z_kioku_wo_koete": "z_kioku_wo_koete.mp3",                          ## Z・刻を越えて（鮎川麻弥）
}

## 主菜单 BGM 池：**三首随机循环**（洗牌袋轮换 —— 放完一首自动换下一首，
## 一轮三首各一次，跨轮边界不重复）。真源就是这一个数组。
##
## ★63-25（用户 2026-10-08）：「EARth 和 Snooze 添加到主菜单歌曲内，和现在的
## 主菜单歌曲**三首随机循环播放**」⇒ 从"写死一首（`audio_director.gd` 里
## `Bgm.MENU` 直接 `return "mobius"`）"变成"三首轮换"。
##
## ## ⚠️ `earth_nt` / `snooze` 是**双用途**曲（本表 + `OPT_IN_BATTLE_TRACKS`）
## 同一首曲子既能当主菜单曲、也能被玩家选去当战斗曲，这是**有意的**。
## 它与下面那条「仅自选曲不许进轮换池」的纪律**不冲突** —— 那条管的是
## **战斗曲的身份**（"会不会被战斗洗牌袋自动抽到"），而主菜单是**另一套轮换**，
## 两个袋子互不相干（见 `AudioDirector._menu_bag`）。
##
## ## ⚠️⚠️ 但它带来一个**必须知道**的技术后果
## 菜单曲从此**不能循环**（循环的曲子永远不发 `finished`，也就永远等不到下一首），
## 而 `load()` 给的是**共享实例** —— `earth_nt` / `snooze` 的同一份 `loop`
## 还被战斗侧持有。⇒ `AudioDirector.play_bgm()` 里那句 `_apply_loop()` **必须先复制再改**。
## 直接改共享资源会写穿到战斗侧，症状是"对战打完一首卡住、再也不换曲"，
## 而且**一行报错都没有**（★63-20 已经栽过一次）。
##
## ⚠️ 本表与 `BATTLE_TRACKS` / `STORY_BATTLE_TRACKS` **不要求互斥**（`mobius` 不在任何
## 战斗池里；`earth_nt` / `snooze` 在仅自选表里）。但**不许把这三首塞进轮换池** ——
## 那会让玩家在战斗里被随机放到一首本不该在战斗里出现的曲子。
const MENU_TRACKS := ["mobius", "earth_nt", "snooze"]

## 对战模式的战斗曲（六首；`senkou` 也在里面 —— 用户明确允许）
const BATTLE_TRACKS := ["tracer", "nda_alpha", "xi", "senkou", "car5p3", "mne"]

## **剧情挑战**的战斗曲：五首，**不含 `senkou`**（它是留给太平洋结算的）
const STORY_BATTLE_TRACKS := ["tracer", "nda_alpha", "xi", "car5p3", "mne"]

## 「**只在被选中时才播**」的战斗曲（opt-in）。
##
## 与 `BATTLE_TRACKS` 的区别是**身份**，不是排序：
##   · `BATTLE_TRACKS` / `STORY_BATTLE_TRACKS` = **轮换池** —— 玩家什么都不做，
##     它们也会被洗牌袋抽到；
##   · `OPT_IN_BATTLE_TRACKS` = **只进自选列表、不进任何轮换池** ——
##     **玩家不选它，它一辈子不会响**。
##
## 用户 2026-09-27：「把 Sweet Child O' Mine 也加入战斗音乐自选里面（玩家不选他不触发）」。
## 那个括号就是本表存在的全部理由：直接把 `sweet_child` 塞进 `BATTLE_TRACKS`
## 会让它**自动轮播** —— 玩家一场没选就先听到了它，正好是用户禁止的那件事。
##
## ★ 2026-10-08（★63-20）：用户给了 `D:\闪哈游戏历代音乐` 的 **46 首历代曲**，
## 要求同样是「都加进游戏内，但玩家不选择就不播」⇒ 本表从 1 条涨到 **47 条**。
## ⚠️ **一首都没进 `BATTLE_TRACKS` / `STORY_BATTLE_TRACKS`** —— 那不是"忘了"，
## 是本表存在的全部意义。混进轮换池的后果见上：自动轮播、不报错、只有耳朵能发现。
##
## ⚠️ `sweet_child` **留在末位**（没有把 46 首排到它后面）：两处既有断言依赖这个位置 ——
## `suite_audio` 的「仅自选曲排在末尾」与 `suite_settings` 的 `picks.find("sweet_child")`，
## 而且老玩家背下来的菜单位置一字不变。
##
## ⚠️ 因此**本表与两个轮换池必须互斥**（同一首曲子不许同时是"会被随机放到"
## 和"不选不触发"）。`suite_audio` 有一条断言钉这个互斥 —— 混进去之后
## 没有任何报错、测试也不会红，症状只是"这首怎么自己响了"。
## （★63-20 起，`suite_battle_bgm_roster` 把这条互斥 +「抽 5 轮一次都不出现」
##   扩到本表**全体 47 条**。改本表之前先看那个套件。）
const OPT_IN_BATTLE_TRACKS := [
	# ---- 2026-10-08 追加：`D:\闪哈游戏历代音乐` 46 首（**只进自选，不进任何轮换池**）----
	# 键名 = 文件名的 ASCII 化；`#` 后面是原始素材名，便于回头对照。
	"re_i_am",                       # Aimer - RE_I AM.mp3
	"cerulean",                      # BACK-ON - セルリアン.mp3
	"nibun_no_ichi",                 # BACK-ON - ニブンノイチ.mp3
	"survivor",                      # BLUE ENCOUNT - Survivor.mp3
	"akatsuki_no_kuruma",            # FictionJunction,南里侑香 - 暁の車.mp3
	"moeagare_toshi",                # Kohei Tanaka - Moeagare Toshi Imawashiki Shukumei o Koete.mp3
	"waga_kokoro_meikyo_shisui",     # Kohei Tanaka - Waga Kokoro Meikyo Shisui - Saredo Kono Te wa Rekka no Gotoku.mp3
	"daybreaks_bell",                # L'Arc〜en〜Ciel - DAYBREAK'S BELL.mp3
	"men_of_destiny",                # MIQ - MEN OF DESTINY(1).mp3
	"rage_of_dust",                  # SPYAIR - RAGE OF DUST.mp3
	"snooze",                        # SZA - Snooze.mp3
	"cage_ntv",                      # SawanoHiroyuki[nZk]; Tielle - Cage _NTv_.mp3
	"anna_ni_issho",                 # See-Saw - あんなに一绪だったのに.mp3
	"beyond_the_time",               # TM NETWORK - BEYOND THE TIME (メビウスの宇宙を越えて).mp3
	"just_communication",            # TWO-MIX - JUST COMMUNICATION(1).mp3
	"rhythm_emotion",                # TWO-MIX - RHYTHM EMOTION(1).mp3
	"freesia",                       # Uru - フリージア.mp3
	"shukufuku",                     # YOASOBI - 祝福.mp3
	"flying_in_the_sky",             # Yoshifumi Ushima - FLYING IN THE SKY.mp3
	"trust_you_forever",             # Yoshifumi Ushima - Trust You Forever.mp3
	"silent_voice",                  # ひろえ純 - サイレント・ヴォイス.mp3
	"red_birthmark",                 # アイナ・ジ・エンド - Red_birthmark.mp3
	"main_title",                    # 三枝成彰 - MAIN TITLE (メイン・タイトル).mp3
	"ai_senshi",                     # 井上大輔 - 哀 戦士.mp3
	"trust_you",                     # 伊藤由奈 - trust you.mp3
	"fight_kawai",                   # 川井憲次 - Fight.mp3
	"anime_ja_nai",                  # 新井正人 - アニメじゃない-夢を忘れた古い地球人よ-.mp3
	"mou_dou_natte_mo_ii_ya",        # 星街すいせい - もうどうなってもいいや.mp3
	"yoru_ni_saku",                  # 星街すいせい - 夜に咲く.mp3
	"the_winner",                    # 松原みき - THE WINNER(1).mp3
	"sassou_taru_char",              # 松山祐士 - 颯爽たるシャア.mp3
	"yoake_no_shooting_star",        # 林原めぐみ - 夜明けのShooting Star.mp3
	"mizu_no_hoshi_e_ai_wo_komete",  # 森口博子 - 水の星へ愛をこめて.mp3
	"itsuka_sora_ni_todoite",        # 椎名恵 - いつか空に届いて.mp3
	"urdr_hunt",                     # 横山克 - Mobile Suit Gundam Iron-Blooded Orphans Urdr-Hunt.mp3
	"earth_nt",                      # 澤野弘之 - EARth.mp3
	"unicorn",                       # 澤野弘之 - UNICORN.mp3
	"vigilante",                     # 澤野弘之; mpi; R!N_Gemie - Vigilante.mp3
	"colony_no_kanojo",              # 照井順政 - コロニーの彼女（I_006A）.mp3
	"reborn",                        # 玉置成実 - Reborn.mp3
	"arashi_no_naka_de_2",           # 米倉千尋 - 嵐の中で輝いて(1).mp3
	"arashi_no_naka_de",             # 米倉千尋 - 嵐の中で輝いて.mp3
	"plazma",                        # 米津玄師 - Plazma(1).mp3
	"freedom",                       # 西川貴教 - FREEDOM.mp3
	"invoke",                        # 西川貴教 - INVOKE.mp3
	"z_kioku_wo_koete",              # 鮎川麻弥 - Z・刻を越えて.mp3
	# Suit-specific defaults; also available for manual playlist selection.
	"thunderbolt_main_theme",
	"yes_girl",
	# ---- 1.x 的老面孔（★63-20 起仍在末位，理由见上）----
	"sweet_child",
]

## 战斗曲的**显示名**（批 23 出击前自选开场曲）：菜单「战斗BGM」行用它。
## ⚠️ 键必须覆盖**整个自选列表**（`battle_pick_tracks()`：轮换池 + 仅自选曲），
## 不许换一套键名 —— 否则"菜单上选的"和"实际会播的"会对不上。
const BATTLE_TRACK_LABELS := {
	"thunderbolt_main_theme": "サンダーボルト・メインテーマ用",
	"yes_girl": "イエスのガール~Yes girl~",
	"tracer": "TRACER",
	"nda_alpha": "ND-ALPHA",
	"xi": "XI（Ξ高达）",
	"senkou": "閃光（senkou）",
	"car5p3": "car5p3 / PENELOPE",
	"mne": "MNE",
	# ---- ★63-20 追加：46 首历代曲的显示名（键必须覆盖**整个自选列表**）----
	# 写**曲名**而不是键名：玩家在菜单里要认的是歌，不是 `colony_no_kanojo`。
	"re_i_am": "RE:I AM",                           # Aimer - RE_I AM.mp3
	"cerulean": "セルリアン",                            # BACK-ON - セルリアン.mp3
	"nibun_no_ichi": "ニブンノイチ",                      # BACK-ON - ニブンノイチ.mp3
	"survivor": "Survivor",                         # BLUE ENCOUNT - Survivor.mp3
	"akatsuki_no_kuruma": "暁の車",                    # FictionJunction,南里侑香 - 暁の車.mp3
	"moeagare_toshi": "燃え上がれ闘志 忌まわしき宿命を越えて",        # Kohei Tanaka - Moeagare Toshi Imawashiki Shukumei o Koete.mp3
	"waga_kokoro_meikyo_shisui": "我が心 明鏡止水",        # Kohei Tanaka - Waga Kokoro Meikyo Shisui - Saredo Kono Te wa Rekka no Gotoku.mp3
	"daybreaks_bell": "DAYBREAK'S BELL",            # L'Arc〜en〜Ciel - DAYBREAK'S BELL.mp3
	"men_of_destiny": "MEN OF DESTINY",             # MIQ - MEN OF DESTINY(1).mp3
	"rage_of_dust": "RAGE OF DUST",                 # SPYAIR - RAGE OF DUST.mp3
	"snooze": "Snooze",                             # SZA - Snooze.mp3
	"cage_ntv": "Cage (NTv)",                       # SawanoHiroyuki[nZk]; Tielle - Cage _NTv_.mp3
	"anna_ni_issho": "あんなに一绪だったのに",                 # See-Saw - あんなに一绪だったのに.mp3
	"beyond_the_time": "BEYOND THE TIME",           # TM NETWORK - BEYOND THE TIME (メビウスの宇宙を越えて).mp3
	"just_communication": "JUST COMMUNICATION",     # TWO-MIX - JUST COMMUNICATION(1).mp3
	"rhythm_emotion": "RHYTHM EMOTION",             # TWO-MIX - RHYTHM EMOTION(1).mp3
	"freesia": "フリージア",                             # Uru - フリージア.mp3
	"shukufuku": "祝福",                              # YOASOBI - 祝福.mp3
	"flying_in_the_sky": "FLYING IN THE SKY",       # Yoshifumi Ushima - FLYING IN THE SKY.mp3
	"trust_you_forever": "Trust You Forever",       # Yoshifumi Ushima - Trust You Forever.mp3
	"silent_voice": "サイレント・ヴォイス",                   # ひろえ純 - サイレント・ヴォイス.mp3
	"red_birthmark": "Red:birthmark",               # アイナ・ジ・エンド - Red_birthmark.mp3
	"main_title": "MAIN TITLE",                     # 三枝成彰 - MAIN TITLE (メイン・タイトル).mp3
	"ai_senshi": "哀 戦士",                            # 井上大輔 - 哀 戦士.mp3
	"trust_you": "trust you",                       # 伊藤由奈 - trust you.mp3
	"fight_kawai": "Fight",                         # 川井憲次 - Fight.mp3
	"anime_ja_nai": "アニメじゃない",                      # 新井正人 - アニメじゃない-夢を忘れた古い地球人よ-.mp3
	"mou_dou_natte_mo_ii_ya": "もうどうなってもいいや",        # 星街すいせい - もうどうなってもいいや.mp3
	"yoru_ni_saku": "夜に咲く",                         # 星街すいせい - 夜に咲く.mp3
	"the_winner": "THE WINNER",                     # 松原みき - THE WINNER(1).mp3
	"sassou_taru_char": "颯爽たるシャア",                  # 松山祐士 - 颯爽たるシャア.mp3
	"yoake_no_shooting_star": "夜明けのShooting Star",  # 林原めぐみ - 夜明けのShooting Star.mp3
	"mizu_no_hoshi_e_ai_wo_komete": "水の星へ愛をこめて",    # 森口博子 - 水の星へ愛をこめて.mp3
	"itsuka_sora_ni_todoite": "いつか空に届いて",           # 椎名恵 - いつか空に届いて.mp3
	"urdr_hunt": "Urdr-Hunt",                       # 横山克 - Mobile Suit Gundam Iron-Blooded Orphans Urdr-Hunt.mp3
	"earth_nt": "EARth",                            # 澤野弘之 - EARth.mp3
	"unicorn": "UNICORN",                           # 澤野弘之 - UNICORN.mp3
	"vigilante": "Vigilante",                       # 澤野弘之; mpi; R!N_Gemie - Vigilante.mp3
	"colony_no_kanojo": "コロニーの彼女",                  # 照井順政 - コロニーの彼女（I_006A）.mp3
	"reborn": "Reborn",                             # 玉置成実 - Reborn.mp3
	"arashi_no_naka_de_2": "嵐の中で輝いて（另一版）",          # 米倉千尋 - 嵐の中で輝いて(1).mp3
	"arashi_no_naka_de": "嵐の中で輝いて",                 # 米倉千尋 - 嵐の中で輝いて.mp3
	"plazma": "Plazma",                             # 米津玄師 - Plazma(1).mp3
	"freedom": "FREEDOM",                           # 西川貴教 - FREEDOM.mp3
	"invoke": "INVOKE",                             # 西川貴教 - INVOKE.mp3
	"z_kioku_wo_koete": "Z・刻を越えて",                  # 鮎川麻弥 - Z・刻を越えて.mp3
	# 仅自选曲（不参与随机轮换，见 `OPT_IN_BATTLE_TRACKS`）。
	# 显示名写**曲名**而不是键名：玩家在菜单里要认的是歌，不是 `sweet_child`。
	"sweet_child": "Sweet Child O' Mine",
}


## 战斗曲的显示名（找不到就原样返回键名 —— 新曲没来得及写标签也不至于显示成空）。
static func battle_track_label(track: String) -> String:
	return str(BATTLE_TRACK_LABELS.get(track, track))


## 「战斗BGM 自选」列表的完整序列（**不含**开头那个代表"随机"的空键）：
## 轮换池 + 仅自选曲。
##
## ⚠️ **四个消费方**（`Settings.cycle_battle_bgm` / `set_battle_bgm_index` /
## `battle_bgm_index`、`MainMenu.bgm_pick_keys`）都必须从这里取。
## 以前它们各自写 `BATTLE_TRACKS` —— 分叉的症状是**菜单里选中了 A、
## 进游戏放的是 B**，而且谁都不报错。
##
## 返回**副本**：调用方要往里面塞东西（比如首位插一个"随机"）时，
## 不能把常量本身改掉。
static func battle_pick_tracks() -> Array:
	var out: Array = BATTLE_TRACKS.duplicate()
	out.append_array(OPT_IN_BATTLE_TRACKS)
	return out


## 这个键是不是一个合法的「战斗BGM 自选」值（空串 = 随机，由各自调用方处理）。
## 存档校验 / 菜单高亮都走它 —— 判据只有这一处。
static func is_battle_pick(track: String) -> bool:
	return BATTLE_TRACKS.has(track) or OPT_IN_BATTLE_TRACKS.has(track)


## 是不是「仅自选曲」（**不参与随机轮换**，只有玩家选了才会响）。
static func is_opt_in_battle_track(track: String) -> bool:
	return OPT_IN_BATTLE_TRACKS.has(track)


# ---- ★63-22：这里原来有一个 `battle_track_note()`，给「仅自选曲」在菜单里
# 加一个「（仅自选 · 不参与随机）」后缀。**用户 2026-10-08 要求去掉它，已删。**
#
# ## 为什么是"彻底删除"而不是留一个返回空串的空壳
# 留空壳的话，`suite_settings` 里那条「选歌页不再印后缀」的**源码扫描判据会变成
# 恒真** —— 菜单里那个调用点还在，只是它永远返回空串。这与 ★63-20 抓到的
# 「恒真断言不算判据」是同族问题：判决行必须**能红**，所以函数本身要不存在。
#
# ## 后缀丢掉的**信息**没有消失，它换了载体
# 那个后缀存在的唯一理由是「这类曲永远不会被随机轮到，菜单上一个字都不说的话，
# 玩家会以为随机坏了」——**这个判断依然成立**，所以信息不能真的丢。
# ⇒ 它改成了**符号语言**（不占版面、也不用每行都读一遍字）：
#   · 选歌页 / 歌单页的行首：带 `◆` 的就是「仅自选曲」（`is_opt_in_battle_track()`）；
#   · 同一个 `◆` 在歌单页还有第二义 ——「这首已经在我的歌单里」+ 序号。
# ⇒ 玩家看到 `◆` 就知道"想听它得自己动手"，而**动手的地方就是战斗歌单**
#（`Settings.battle_playlist`，★63-22 第三条需求）。两条需求在这里闭合。

## 需要循环播放的音效（引擎 / 座舱音）
const LOOPING := ["cruise_xi", "cruise_penelope"]

## 同一个音效两次触发之间的最小间隔（毫秒）。
## 火神炮 18 发/秒、小爆炸每次命中都放 —— 不做节流会变成一堵噪音墙。
const MIN_INTERVAL_MS := {
	"vulcan": 62,
	"boom_s": 70,
	"boom_m": 90,
	"alarm_missile": 900,
	"alarm_lock": 900,
	"alarm_critical": 1200,
}

## 逐条音效的**增益偏移**（dB）。表里没有的名字 = `0.0`（原样播）。
##
## ## 为什么要有这张表
##
## 音量原本散在**每一个调用点**上：`play_self("beam_rifle", -4.0)`、
## `play_3d("beam_saber", pos, -2.0)`…… 光「光束步枪」一条就有 4 处、
## 「军刀」两条共 4 处，横跨 4 个文件。于是「把步枪调大 25%」必然要改 4 个地方，
## **而且漏掉任何一处都不会报错** —— 症状是「玩家自己那一枪没变大、敌机那枪变大了」，
## 或者「挥刀变响了、砍中没变」，只能靠耳朵发现。
##
## 收到这里之后：**一个音效一个数**，`play_self` / `play_3d` 两条通道一起生效，
## 调用点一个字都不用动。
##
## ## ⚠️ 单位是 dB，不是「加 25」
##
## 用户说的「调大 25%」= **振幅 ×1.25** = `20·log10(1.25)` = **+1.9382 dB**。
## 千万不要写成 `+25.0` —— 那是 **17.78 倍**，直接削顶爆音。
## 换算一律走 `db_for_percent()`，改主意（比如再要 30%）时也只改这一处。
##
## ## 会影响哪些调用点（改这张表前先看一眼）
##
## | 音效 | 播放点与各自的基础音量 |
## |---|---|
## | `beam_rifle` | 玩家自己开枪 `-4.0` / 敌机开枪 `-2.0` / **榴弹**（复用这条音效）`-3.0` / 联机对手的观感枪声 `-6.0` |
## | `beam_saber` | 玩家挥刀 `-3.0` / 敌机挥刀 `-2.0` |
## | `saber_impact` | 砍中 `0.0` / 军刀相杀（还带 0.62~0.72 降调）`+1.5` |
##
## ⚠️ 榴弹与联机枪声是**复用** `beam_rifle` 这条音效，所以它们会跟着一起变响 ——
## 这是「按音效调」而不是「按武器调」的必然结果，是**有意**的：
## 同一段声音不该出现两种响度。真要只动步枪本体，得改成按武器加增益。
##
## 削顶余量（三条源文件峰值：-16.9 / **-6.9** / -14.2 dB）：
## 最险的一处是**玩家挥刀**（调用点 `-3.0`）⇒ 加完 1.9382 后峰值约 **-7.96 dBFS**，
## 离 0 dBFS 还有约 8 dB，不会削顶。
const GAIN_DB := {
	# 用户 2026-09-27：「光束步枪和光束军刀的音效声音调大25%」
	# 军刀命中（saber_impact）也算「军刀的音效」—— 挥刀与砍中是同一件武器的两半。
	"beam_rifle": 1.9382,
	"beam_saber": 1.9382,
	"saber_impact": 1.9382,
}

## 导弹爆炸"近 / 远"的分界距离（米）。
## 镜头在机体后约 54 m，所以 800 m 大致就是"这一发炸在我身边"与"炸在天边"的分界。
const NEAR_EXPLOSION_DISTANCE := 800.0

## 音效名 → 它该走哪条**子总线**（表里没有的名字直接进 `SFX`，即"未分类音效"）。
##
## ★63-23「音量细分」：设置页的「音量」子页给了六条通道各自的滑条，
## 而"哪条音效属于哪条通道"**只在这张表里说一次** ——
## `AudioDirector` 的四条播放通道（`play_self` / `play_3d` / `play_voice` /
## `make_loop_3d`）全部查它，所以不存在"自己开炮变响了、敌机开炮没变"这种漏一半。
##
## ## 为什么值是**字符串**而不是 `Settings.BUS_*`
## 跨文件引用常量在 `--headless` 下会撞全局类缓存的坑（本仓库统一纪律：走字符串 + 测试钉住）。
## ⚠️ 代价：写错一个字会**静默**（那条音效照旧进 `SFX`，它自己的滑条就不管用了）。
## 所以有一条闸门钉着：`suite_volume_mixer` 的
## 「表里每个值都是一条**活总线**」+「七个通道名与 `Settings` 的一套逐字相同」两节。
##
## ## 分组是"按音效"不是"按武器"（沿用 `GAIN_DB` 那条既有口径）
## `beam_rifle` 有 4 个调用点，其中**榴弹**与**联机对手的枪声**是复用这条音效的
## ⇒ 它们会跟着「步枪音量」一起变。这是有意的：同一段声音不该出现两种响度。
const SFX_BUS := {
	# ---- 武器四条通道 ----
	"vulcan": "VULCAN",
	"beam_saber": "SABER",
	"saber_impact": "SABER",
	"beam_rifle": "RIFLE",
	"funnel_fire": "FUNNEL",
	# ---- 警报（三种合成告警 + 四条座舱语音；语音缺素材时降级到的也是这三条）----
	"alarm_lock": "ALARM",
	"alarm_missile": "ALARM",
	"alarm_critical": "ALARM",
	"voice_pull_up": "ALARM",
	"voice_missile": "ALARM",
	"voice_stall": "ALARM",
	"voice_over_g": "ALARM",
	# ---- 引擎循环 ----
	"cruise_xi": "ENGINE",
	"cruise_penelope": "ENGINE",
}

## 这条音效该走哪条子总线；`""` = 未分类（调用方送 `SFX`）。
##
## ⚠️ 返回 `""` 而不是"直接返回 SFX"：`SoundBank` 是纯数据类（`RefCounted`），
## 不去读 autoload；由 `AudioDirector` 兜底成 `Settings.BUS_SFX`。
static func bus_for(name: String) -> String:
	return str(SFX_BUS.get(name, ""))

## 告警语音 → **录音缺失时**顶上的合成音效（§4.3.2 的降级路径）。
##
## ⚠️ 这张表存在的唯一理由：**"语音没录"不许变成"告警没了"**。
## 没有它的话，`play_voice()` 拿到一个不存在的 wav 就静默返回 ——
## 玩家既听不到语音、也不知道为什么，而 HUD 上的字照旧在闪，
## 于是"语音通道坏了"这件事只能靠猜。
##
## 三条挤在 `alarm_critical` 上是有意的：它们都是"立刻要命"的那一类，
## 而工程里只有三种警报合成音。音高/语义的区分交给语音本身，
## 语音没到之前"同一个警报响两次"也好过"三条里的两条不响"。
const VOICE_FALLBACK := {
	"voice_pull_up": "alarm_critical",
	"voice_missile": "alarm_missile",
	"voice_stall": "alarm_critical",
	"voice_over_g": "alarm_critical",
}


## 告警语音是不是**真的有录音**。
##
## 单独抽出来（而不是内联在 `voice_or_fallback` 里）是因为测试要能直接问
## "这一条到底有没有素材" —— 素材到货那天，断言会自己从"走降级"翻成"走录音"，
## 不需要改测试。
static func has_voice(name: String) -> bool:
	var f: String = VOICE.get(name, "")
	if f == "":
		return false
	return ResourceLoader.exists(DIR_SFX + f)


## 告警语音名 → **本次实际要播的名字**。
##
## 有录音 ⇒ 原样返回；没有 ⇒ 返回 `VOICE_FALLBACK` 里对应的合成音效名；
## 两边都没有 ⇒ 返回 ""（调用方静默跳过，HUD 的字照旧闪）。
##
## ⚠️ **返回音效名而不是 bool/路径**：`AudioDirector` 的 `_stream()` 只吃名字，
## 中间任何一次"转成路径再转回来"都会多出一处可能与 `sfx_path()` 不一致的地方。
static func voice_or_fallback(name: String, fallback := "") -> String:
	if has_voice(name):
		return name
	if fallback != "":
		return fallback
	return str(VOICE_FALLBACK.get(name, ""))


static func sfx_path(name: String) -> String:
	var f: String = SFX.get(name, "")
	if f == "":
		# 座舱语音在**另一张表**里（见 `VOICE` 的注释：它允许缺失，
		# 而 `SFX` 那条"登记即承诺存在"的回归门必须保持锋利）。
		# 这里仍然走同一条路径函数 —— 播放端不需要知道有两张表。
		f = str(VOICE.get(name, ""))
	if f == "":
		push_warning("[SoundBank] 未知音效：%s" % name)
		return ""
	return DIR_SFX + f


static func bgm_path(name: String) -> String:
	var f: String = BGM.get(name, "")
	if f == "":
		push_warning("[SoundBank] 未知 BGM：%s" % name)
		return ""
	return DIR_BGM + f


static func min_interval(name: String) -> int:
	return int(MIN_INTERVAL_MS.get(name, 0))

## 「调大百分之多少」→ dB。**纯函数**（测试直接钉边界）。
##
##   `pct = +25`  ⇒ 振幅 ×1.25 ⇒ `20·log10(1.25)` ≈ **+1.9382 dB**
##   `pct = +100` ⇒ 振幅 ×2.0  ⇒ **+6.0206 dB**
##   `pct = -50`  ⇒ 振幅 ×0.5  ⇒ **-6.0206 dB**
##   `pct = -100` ⇒ 静音（返回 -80.0 兜底：`log10(0)` 是负无穷，不能真的算）
##
## 单独抽出来是为了让「25%」这句话在代码里**可审计**：
## `GAIN_DB` 里那几个数就是它的返回值，而不是某个手抄来的近似小数。
static func db_for_percent(pct: float) -> float:
	var ratio := 1.0 + pct / 100.0
	if ratio <= 0.0001:
		return -80.0
	return 20.0 * log(ratio) / log(10.0)


## 这条音效要额外加多少 dB（表里没有 = 0.0）。
## 由 `AudioDirector` 的 `play_self()` / `play_3d()` **统一施加**，调用点不用管。
static func gain_db(name: String) -> float:
	return float(GAIN_DB.get(name, 0.0))


static func is_looping(name: String) -> bool:
	return LOOPING.has(name)


## Suit themes stay available in the playlist and loop throughout their pilot's battle.
const SUIT_BATTLE_THEMES := {
	SuitProfile.Id.FULL_ARMOR_TB: "thunderbolt_main_theme",
	SuitProfile.Id.PSYCHO_ZAKU_TB: "yes_girl",
}

static func suit_battle_track(suit_id: int) -> String:
	return str(SUIT_BATTLE_THEMES.get(suit_id,""))

static func is_suit_battle_track(track: String) -> bool:
	return SUIT_BATTLE_THEMES.values().has(track)
