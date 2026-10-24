extends Node
## 无头测试入口。
##
## 跑法（判据只看下面的 "N PASS / M FAIL" 汇总行，不看退出码）：
##   godot --headless --path C:\Users\MSIPC\Documents\gundam res://tests/test_runner.tscn
##
## 为什么用「场景」而不是 `--script`：`--script` 模式不会实例化 autoload，
## 而 `Game` 这个 autoload 是战斗系统的唯一真源，测不了它等于没测。
##
## ⚠️ **第十八·二十一轮起这里有两道保险**（实现都在 `tests/t.gd` 末尾那一节）：
##
##   ① **单实例闸门**（`T.guard_single_instance()`）：检测到 GUI 版 Godot（编辑器 / 游戏）
##      或另一个测试进程正在用这个工程就**拒绝运行**。起因是 2026-09-20 那天的
##      「Godot 特别容易崩」—— 真相是两个实例同时写 `.godot/`：
##      `global_script_class_cache.cfg` / `uid_cache.bin` / `imported/` 互相覆盖，
##      于是 autoload 与 class_name 解析不到，满屏 `Identifier not found: Game`。
##      确要并行：用**工程副本**，或加 `--allow-concurrent` 强行跑（自担风险）。
##
##   ② **坏掉的套件不拖垮整轮**（`T.run_suite()`）：以前 21 个套件是无条件顺序调用的，
##      任何一个编译不过 → `SuiteXxx.run` 成了「GDScript 上不存在的函数」→ **整轮当场中断**，
##      连「哪些是绿的」都问不出来（当天就发生过：跑到第 33 行 `SuiteRound17` 就死）。
##      现在改成：那一个套件记一条 FAIL 并点名，其余照跑，报告末尾单独列一段
##      「未能执行的套件」。
##
## 表驱动：加套件只改下面这张表。
## 每行 = `[路径, 显示名, 是否 async, 是否传 host]`
##   ⚠️ 后两项**不是多余的**：套件签名不统一 —— `Flight/Ballistics/Rig` 的 `run(t)` 只收一个参数，
##   而 `Layout/Gamepad` 与其余全是 `run(t, host)`；`Flight/Ballistics/Rig/Layout/Gamepad` 是同步的
##   （原来就没 await）。写错会直接报 "Too many arguments"（我第一版就写错了）。
const SUITES := [
	["res://tests/suite_lan_axis_suits.gd", "LanAxisSuits", true, true],
	["res://tests/suite_sazabi_collision.gd", "SazabiCollision", true, true],
	["res://tests/suite_sazabi_funnel_visual.gd", "SazabiFunnelVisual", true, true],
	["res://tests/suite_target_vitals.gd", "TargetVitals", true, true],
	["res://tests/suite_nu_sazabi_ifield.gd", "NuSazabiIfield", true, true],
	["res://tests/suite_nu_sazabi_motion.gd", "NuSazabiMotion", true, true],
	["res://tests/suite_sazabi_belly.gd", "SazabiBelly", true, true],
	["res://tests/suite_sazabi.gd", "Sazabi", true, true],
	["res://tests/suite_sazabi_model.gd", "SazabiModel", true, true],
	["res://tests/suite_sazabi_network.gd", "SazabiNetwork", true, true],
	["res://tests/suite_stability_20261018.gd", "Stability20261018", true, true],
	["res://tests/suite_day7_performance.gd", "Day7Performance", true, true],
	["res://tests/suite_nu_defense_collision.gd", "NuDefenseCollision", true, true],
	["res://tests/suite_nu_gundam.gd", "NuGundam", true, true],
	["res://tests/suite_nu_model.gd", "NuModel", true, true],
	["res://tests/suite_adelaide_landmark_detail.gd", "AdelaideLandmarkDetail", true, true],
	["res://tests/suite_m09_core_escape.gd", "M09CoreEscape", true, true],
	["res://tests/suite_adelaide_roof_detail.gd", "AdelaideRoofDetail", true, true],
	["res://tests/suite_m04_no_escape.gd", "M04NoEscape", true, true],
	["res://tests/suite_adelaide_building_modules.gd", "AdelaideBuildingModules", true, true],
	["res://tests/suite_m09_radio_runtime.gd", "M09RadioRuntime", true, true],
	["res://tests/suite_m09_radio.gd", "M09Radio", false, false],
	["res://tests/suite_road_surface.gd", "RoadSurface", true, true],
	["res://tests/suite_m09_launch.gd", "M09Launch", false, false],
	["res://tests/suite_adelaide_ground.gd", "AdelaideGround", true, true],
	["res://tests/suite_adelaide_surface_trial.gd", "AdelaideSurfaceTrial", true, true],
	["res://tests/suite_xi_final_tail.gd", "XiFinalTail", true, true],
	["res://tests/suite_cinematic_performance.gd", "CinematicPerformance", true, true],
	["res://tests/suite_cinematic_atmosphere.gd", "CinematicAtmosphere", true, true],
	["res://tests/suite_adelaide_cinematic_detail.gd", "AdelaideCinematicDetail", true, true],
	["res://tests/suite_cinematic_lighting.gd", "CinematicLighting", true, true],
	["res://tests/suite_cinematic_materials.gd", "CinematicMaterials", true, true],
	["res://tests/suite_regz_precision_camera.gd", "ReGZPrecisionCamera", true, true],
	["res://tests/suite_odysseus_pedal.gd", "OdysseusPedal", true, true],
	["res://tests/suite_xi_final.gd", "XiFinal", true, true],
	["res://tests/suite_sonic_cloud.gd", "SonicCloud", true, true],
	["res://tests/suite_sea_flight_wake.gd", "SeaFlightWake", true, true],
	["res://tests/suite_arizeus_v2.gd", "ArizeusV2", true, true],
	["res://tests/suite_regz_custom.gd", "ReGZCustom", true, true],
	["res://tests/suite_ground_audit.gd", "GroundAudit", true, true],
	["res://tests/suite_ground_rescue.gd", "GroundRescue", true, true],
	["res://tests/suite_input_pose.gd", "InputPose", true, true],
	["res://tests/suite_regz_motion.gd", "ReGZMotion", true, true],
	["res://tests/suite_penelope_movie.gd", "PenelopeMovie", true, true],
	["res://tests/suite_xi_movie.gd", "XiMovie", true, true],
	["res://tests/suite_xi_cruise_motion.gd", "XiCruiseMotion", true, true],
	["res://tests/suite_ace_motion.gd", "AceMotion", true, true],
	["res://tests/suite_net_visuals.gd", "NetVisuals", true, true],
	["res://tests/suite_gp03s.gd", "GP03S", true, true],
	["res://tests/suite_auto_reload.gd", "AutoReload", true, true],
 ["res://tests/suite_lan_lobby.gd", "LanLobby", false, true],
	["res://tests/suite_low_end_budget.gd", "LowEndBudget", true, true],
	["res://tests/suite_neue_ziel.gd", "NeueZiel", true, true],
	["res://tests/suite_gp03d.gd", "GP03D", true, true],
	["res://tests/suite_zeon_faction.gd", "ZeonFaction", false, true],
	["res://tests/suite_music_settings.gd", "MusicSettings", false, true],
	["res://tests/suite_fly_motion.gd", "FlyMotion", true, true],
	["res://tests/suite_performance_loading.gd", "PerformanceLoading", true, true],
	["res://tests/suite_super_boss.gd", "SuperBoss", true, true],
	["res://tests/suite_super_boss_live.gd", "SuperBossLive", true, true],
	["res://tests/suite_super_hard.gd", "SuperHard", true, true],
	["res://tests/suite_hard_ai_skills.gd", "HardAISkills", true, true],
	["res://tests/suite_gun_motion.gd", "GunMotion", true, true],
	["res://tests/suite_sortie_launch.gd", "SortieLaunch", true, true],
	["res://tests/suite_sortie_entry.gd", "SortieEntry", true, true],
	["res://tests/suite_weapon_origins.gd", "WeaponOrigins", true, true],
	["res://tests/suite_weapon_mounted_origins.gd", "WeaponMountedOrigins", true, true],
	["res://tests/suite_collision_guard.gd", "CollisionGuard", true, true],
	["res://tests/suite_saber_motion.gd", "SaberMotion", true, true],
	["res://tests/suite_rifle_accuracy.gd", "RifleAccuracy", true, true],
	["res://tests/suite_third_person_hud.gd", "ThirdPersonHUD", false, true],
	["res://tests/suite_environment_detail.gd", "EnvironmentDetail", true, true],
	["res://tests/suite_flight.gd", "Flight", false, false],
	["res://tests/suite_ballistics.gd", "Ballistics", false, false],
	["res://tests/suite_rig.gd", "Rig", false, false],
	["res://tests/suite_layout.gd", "Layout", false, true],
	["res://tests/suite_damage.gd", "Damage", true, true],
	["res://tests/suite_abilities.gd", "Abilities", true, true],
	["res://tests/suite_combat.gd", "Combat", true, true],
	["res://tests/suite_audio.gd", "Audio", true, true],
	["res://tests/suite_battle_bgm_roster.gd", "BattleBgmRoster", false, true],
	# ★63-22：自定义战斗歌单（数据 / 持久化 / 轮换 / 接线）。
	["res://tests/suite_bgm_playlist.gd", "BgmPlaylist", false, true],
	# ★63-22：试听。`async = true` —— 它要**真的等 2.4 秒**去采样渐入曲线
	#（Tween 由 SceneTree 驱动，与音频驱动无关 ⇒ headless 里也能拿到可红的证据）。
	["res://tests/suite_bgm_preview.gd", "BgmPreview", true, true],
	["res://tests/suite_settings.gd", "Settings", true, true],
	["res://tests/suite_pad_target.gd", "PadTarget", true, true],
	["res://tests/suite_gamepad.gd", "Gamepad", false, true],
	["res://tests/suite_pause.gd", "Pause", true, true],
	["res://tests/suite_input.gd", "Input", true, true],
	["res://tests/suite_round.gd", "Round", true, true],
	["res://tests/suite_round14.gd", "Round14", true, true],
	["res://tests/suite_round15.gd", "Round15", true, true],
	["res://tests/suite_round16.gd", "Round16", true, true],
	["res://tests/suite_round17.gd", "Round17", true, true],
	["res://tests/suite_round18.gd", "Round18", true, true],
	["res://tests/suite_round19.gd", "Round19", true, true],
	["res://tests/suite_round20.gd", "Round20", true, true],
	["res://tests/suite_round21.gd", "Round21", true, true],
	["res://tests/suite_worldscale.gd", "WorldScale", true, true],
	# ⚠️ **按主题命名，不按轮次**：这个仓库有另一个会话在并行编辑，两边都按"轮次"
	# 占编号时撞过一次 —— 本套件（地图放大）第一版叫 `suite_round22.gd`，
	# 把对方同一编号的教学套件整个覆盖掉了。现在两份各自用语义名，互不占号。
	["res://tests/suite_tutorial.gd", "Tutorial", true, true],
	# 编队战的搭乗（六台量产机都在板上 + 接近敌人下板）—— 同样按主题命名。
	["res://tests/suite_squad_ride.gd", "SquadRide", true, true],
	["res://tests/suite_lan_plan.gd", "LanPlan", true, true],
	["res://tests/suite_lan_spawn.gd", "LanSpawn", true, true],
	# 联机**代理同步**（批 2）：快照发得出去 + 代理每帧被推向快照（缺一现象照旧）。
	["res://tests/suite_net_sync.gd", "NetSync", true, true],
	# 联机**房间 + 密码**（批 4 §六）：房间号 ⇒ 端口一处真源 + 握手合成一个包 + 主机验密门。
	# ⚠️ 同样**按主题命名**，不占轮次编号（并行会话按轮次占号时撞过文件）。
	["res://tests/suite_lan_room.gd", "LanRoom", true, true],
	# 困难模式的难度（全弹发射之后太容易）—— 按主题命名。
	["res://tests/suite_hardmode.gd", "HardMode", true, true],
	# ---- 1.2.1：相杀修复 / 友军误伤 / 踏板呼叫 / 镜头反馈 ----
	# ⚠️ 全部**按主题命名**，一个轮次编号都不占（本仓库有并行会话，
	# 两侧都按轮次占号时撞过一次：一个套件被同名文件整个覆盖，而 runner 照样绿）。
	["res://tests/suite_friendly_fire.gd", "FriendlyFire", true, true],
	["res://tests/suite_saber_clash.gd", "SaberClash", true, true],
	["res://tests/suite_pedal_call.gd", "PedalCall", true, true],
	["res://tests/suite_camera_feedback.gd", "CameraFeedback", true, true],
	# 2026-10-08：量产机槽空时镜头剧烈晃动 —— 点火抖动的触发原来读 fm.boosting 当
	# 「上一帧的意图」，被 resolve_jet_gauge() 的槽空裁决骗成**帧帧成立**（chase_camera
	# 的抖动池被灌到 1.4 上限）。改读按键沿 + 槽空不给点火确认。
	# ⚠️ 第 3 列 true：要 await 真物理帧（is_action_just_pressed 按引擎帧号判）。
	# ⚠️ 第 4 列 true：要 host 才能把相机 / 机体挂进树。
	["res://tests/suite_boost_shake.gd", "BoostShake", true, true],
	# ---- ★63-9 · D4 · 敌方机体坠毁提醒（两道门：击毁回调 + `Game.phase == FIGHT`）----
	# 按**主题**命名，不占轮次编号（本仓库有并行会话）。
	["res://tests/suite_enemy_down.gd", "EnemyDown", true, true],
	# ---- ★63-9 · B4 · 小队战的「敌方 ACE」听玩家选择（纯函数 + 菜单池 + 端到端）----
	# 按**主题**命名，不占轮次编号。
	["res://tests/suite_squad_ace.gd", "SquadAce", true, true],
	["res://tests/suite_mission_speed.gd", "MissionSpeed", true, true],
	["res://tests/suite_smoke_density.gd", "SmokeDensity", true, true],
	["res://tests/suite_ground_guard.gd", "GroundGuard", true, true],
	["res://tests/suite_reverse_fly.gd", "ReverseFly", true, true],
	# ---- 轮 63-9 · B5：ACE 强制进攻节拍（12s/4s → 9s/5s）----
	["res://tests/suite_ace_pressure.gd", "AcePressure", true, true],
	# ---- 轮 63-9 · D3a：光束步枪辅助瞄准（保护驾驶开关 = 模式门）----
	["res://tests/suite_aim_assist.gd", "AimAssist", true, true],
	# ---- 轮 63-10 · D3b：放大镜（全工程唯一的 SubViewport + 专属相机，屏幕右上空白处）----
	["res://tests/suite_magnifier.gd", "Magnifier", true, true],
	# ---- 1.2.1：批 1 · 多目标锁定（锁定组 ≤3 / 火力按人数分散）----
	["res://tests/suite_multi_lock.gd", "MultiLock", true, true],
	# ---- 轮 36 · 锁定系统重修：**锁定对象只由玩家切换**（不自动补位 / 鼠标只管准星）----
	# 同样**按主题命名**，不占轮次编号（并行会话按轮次占号时撞过文件）。
	["res://tests/suite_lock_manual.gd", "LockManual", true, true],
	# ---- 1.2.1：批 2 · HUD 仪表（姿态仪 / 高度带 / 告警状态机 / 语音通道）----
	["res://tests/suite_hud_instruments.gd", "HudInstruments", true, true],
	# ---- 1.2.1：批 3 · 观感与手感（导弹烟幕 §4.4 / UI 风格约束 §4.7）----
	["res://tests/suite_missile_smoke.gd", "MissileSmoke", true, true],
	["res://tests/suite_ui_style.gd", "UiStyle", false, true],
	# ---- 批 28 · 换弹 / 浮游导弹装填的**滚动读条**（2026-09-22 用户指定）----
	# 同样**按主题命名**，不占轮次编号（并行会话按轮次占号时撞过文件）。
	["res://tests/suite_reload_gauge.gd", "ReloadGauge", true, true],
	# ---- 批 29 · 主菜单**纵向骨架**重排（内容区随屏高伸缩 / 行高自适应 / 提示锚底）----
	["res://tests/suite_menu_frame.gd", "MenuFrame", false, true],
	# ---- 1.2.3 · 批 E/G · **地图**画质：地表细节 / 云的主光受光 / 海面浪尖透光 / 城市立面 ----
	# ⚠️ 第 3 列必须是 true：最后一节要在真地图上建图（`await` 一帧让世界就绪）。
	# ⚠️ 这一套**测不了"好不好看"**（无头环境的 RenderingServer 是 dummy，一个像素都不产生）。
	#    它钉的是接线、源码事实、以及"新抽取有没有扰动既有随机序列"。
	#    真正的好坏要靠 `tests/pixprobe.tscn` 的真渲染 A/B。
	["res://tests/suite_gfx_map.gd", "GfxMap", true, true],
	# ---- 1.2.3 · 批 I 收口 / 批 J · **画质记账**（奈奎斯特 / 海雾 / 斑驳）----
	# ⚠️ 第 3 列 true：海雾那一节要真建一个 WorldBuilder 并 `await` 一帧。
	# ⚠️ 同样**测不了"好不好看"**：这里算的是账（`size/seg` 对波长）、
	#    查的是接线与运行期属性。观感判据在 `tests/pixprobe.tscn` 的
	#    `--mist` / `--mottle` / `--topcam`。
	# ⚠️ **按主题命名**（不占轮次号）—— 见下面那段红字。
	["res://tests/suite_gfx_ledger.gd", "GfxLedger", true, true],
	# ---- 1.3：任务评价（S·A·B·C / 波次计时）----
	["res://tests/suite_mission_rating.gd", "MissionRating", false, true],
	# ---- 1.2.1：批 7 · 测试断点续跑（--resume 跳过上一轮已绿的套件）----
	["res://tests/suite_resume.gd", "Resume", false, true],
	# ---- 1.2.1：批 8 · 辅助驾驶平移模式 + 三机速度收敛 + 拖尾光条 ----
	# ⚠️ 第 3 列必须是 true（async_call）：套件里有 await（平移开关接线节要真跑物理帧），
	#    写 false 的话协程没人等，整节断言一条都不会执行（还安静得很）。
	["res://tests/suite_assist_drive.gd", "AssistDrive", true, true],
	# ---- 1.2.1：批 10 · 读条系统（进入战斗地图前的加载层 + 分阶段建图）----
	# ⚠️ 第 3 列必须是 true：三节里两节有 await（读条界面等帧、开局协程走完整流程）。
	["res://tests/suite_loading.gd", "Loading", true, true],
	# ---- 1.2.1：批 11 · 手感：突进感与运动感（诱导阻力 / QB 爆冲 / 侧倾 / 超级 FOV）----
	# ⚠️ 第 3 列必须是 true：QB / 侧倾 / 特效三节有 await（真跑物理帧）。
	["res://tests/suite_motion_feel.gd", "MotionFeel", true, true],
	# ---- 第一人称（座舱视角）+ 设置开关 + 眩晕警告门（轮 20）。
	# ⚠️ 按主题命名，不占轮次编号（本仓库有并行会话，两侧都按轮次占号时撞过一次文件）。
	# ⚠️ 第 3、4 列都必须是 true：要 host（造机体与相机进树）且套件里有 await
	#    （相机必须进树才读得到 global_transform，见套件头部的说明）。
	["res://tests/suite_fpv.gd", "FPV", true, true],
	# ---- **特效形态与细节**（烟 / 尾焰 / 爆炸 / 收口时机）----
	# 按主题命名，不占轮次编号（本仓库有并行会话，两边都按轮次占号时撞过一次文件）。
	# ⚠️ 第 3、4 列都必须是 true：要 host（造机体进树）且套件里有 await（真跑物理帧）。
	["res://tests/suite_straight_jets.gd", "StraightJets", true, true],
	["res://tests/suite_fx_plume.gd", "FxPlume", true, true],
	# ---- **浮游导弹的跟踪能力**（轮 15：−25%）。
	# 按主题命名，不占轮次编号（同一条规矩，见上面那段）。
	# ⚠️ 第 3、4 列都必须是 true：要 host（造机体与靶机进树）且套件里有 await（真跑物理帧量转角）。
	["res://tests/suite_funnel_guidance.gd", "FunnelGuidance", true, true],
	# ---- **阿利宙斯的匀速弹速与蓄力激光炮**（2026-09-28）。
	# 按主题命名，不占轮次编号（同一条规矩，见上面那段红字）。
	# ⚠️ 第 3、4 列都必须是 true：要 host（造机体与激光柱进树）
	#    且套件里有 await（真跑物理帧量激光柱的持续伤害）。
	["res://tests/suite_arizeus_cannon.gd", "ArizeusCannon", true, true],
	# ---- **佩涅罗佩的蓄力激光炮 + 「保住连发」的输入路由**（2026-09-29）。
	# 按主题命名，不占轮次编号（同一条规矩，见上面那段红字）。
	# ⚠️ 第 3、4 列都必须是 true：路由 / 门禁 / 输入层 A/B 三节都要真跑物理帧。
	["res://tests/suite_penelope_cannon.gd", "PenelopeCannon", true, true],
	# ---- 1.2.1：批 4 · 按键自定义（§4.8）。
	# ⚠️ **必须排最后**：它会真的改 InputMap 与 user://keybinds.cfg，
	# 排前面会把其它套件的"InputMap == 出厂表"断言搞红。
	# 不占轮次编号 —— 改这一行时把上面那条规矩一起读一遍。
	["res://tests/suite_model_anim.gd", "ModelAnim", true, true],
	["res://tests/suite_model_fsm.gd", "ModelFSM", true, true],
	["res://tests/suite_cruise_form.gd", "CruiseForm", true, true],
	# ---- **场景亮度增益**（本工程"环境亮度"的唯一旋钮）。
	# 轮 12「场景明暗度更亮一点」⇒ 1.0→1.40；轮 23「环境亮度压暗30%」⇒ 1.40→0.98。
	# 按主题命名，不占轮次编号（同一条规矩，见上面那段红字）。
	# ⚠️ 第 3、4 列**都必须是 false**：整套是纯函数 + 源码扫描 —— 没有 await，
	#    也不需要 host（`_sg()` 在**未进树**的 `WorldBuilder.new()` 上就能调）。
	#    写成 true 会让 runner 传一个多余的 host 参数 ⇒ "Too many arguments"。
	["res://tests/suite_scene_gain.gd", "SceneGain", false, false],
	# ---- **开场动画**（进游戏一开头播的那一段）。
	# ⚠️ 按主题命名，不占轮次编号（本仓库有并行会话，两侧都按轮次占号时撞过一次文件）。
	# ⚠️ 第 3 列 false / 第 4 列 true：没有 await，但要 host（造一次主场景验"无头下
	#    菜单照旧同步进"）。两列写反会直接报 "Too many arguments"。
	["res://tests/suite_intro.gd", "Intro", false, true],
	# ---- **剧情模式**（轮 0 存档 + 轮 A 数据层：7 关目标 / 触发器 / 军资 / 进度）。
	# ⚠️ **按主题命名，不占轮次号**（本仓库有并行会话，两侧都按轮次占号时撞过一次文件）。
	# ⚠️ 第 3、4 列**都必须是 false**：整套是纯函数 + 源码扫描 —— 没有 await，
	#    也不需要 host（`MissionScript` / `CampaignScript` 的数据层喂字典就能验）。
	#    写成 true 会让 runner 传一个多余的 host 参数 ⇒ "Too many arguments"。
	["res://tests/suite_campaign.gd", "Campaign", false, false],
	["res://tests/suite_keybind.gd", "Keybind", false, true],
	# ---- **主菜单「对战模式」子页**（把王牌战 / 小队战收进一个小菜单）。
	# ⚠️ 按主题命名，不占轮次号（本仓库有并行会话，两侧都按轮次占号时撞过一次文件）。
	# ⚠️ 第 3 列 false（整套没有 await，同步跑）；第 4 列 true ——
	#    套件签名是 `run(t, _host)`（本仓库绝大多数套件都带 host 位），
	#    第 4 列写 false 会变成"少传一个参数"，直接 TypeError。
	["res://tests/suite_menu_groups.gd", "MenuGroups", false, true],
	# ---- **局域网「王牌战」**（两人各一台、没有编制也没有僚机）。
	# ⚠️ 第 3、4 列都必须是 true：最后一节要走真正的开局入口 `_on_start_match()`
	#    并把一局真的撒出来（要 host 造主场景 + 有 await 跑物理帧数机体）。
	["res://tests/suite_ace_duel.gd", "AceDuel", true, true],
	# ---- **低地球轨道**（剧情模式轮 B2：本工程第一张**没有地表**的地图）。
	# ⚠️ 按主题命名，不占轮次号（本仓库有并行会话，两侧都按轮次占号时撞过一次文件）。
	# ⚠️ 第 3、4 列**都必须是 true**：第 3 节要在真世界里建一次图并 `await physics_frame`，
	#    而且要用 `host` 挂住那个 `WorldBuilder`（射线判据要它进树才有物理世界）。
	["res://tests/suite_space_map.gd", "SpaceMap", true, true],
	# ---- 2026-09-29 · 梅萨指挥官型 / F01型进小队战马夫蒂（**按主题命名**，不占轮次号）----
	# ⚠️ 第 3 列（async）必须是 **true**：最后一节要在真场景里把一个 `FlightBody`
	#    建出来，量"这台无骨架的模型接进去之后能不能飞、缩放对不对"
	#    —— 那一步要 `await` 一帧（`_ready` 之后才算建完）。
	["res://tests/suite_messer_roster.gd", "MesserRoster", true, true],
	# ---- N57 · **老路开火必须播 `shoot`**（用户真机反馈「开枪还是没有抬手动作」）----
	# ⚠️ 第 3、4 列都必须是 true：本套件的两节都要**搭一台真玩家控制器**
	#    （`PlayerController` ＋ 真模型 ＋ 输入注入）并 `await physics_frame`
	#    让 `_think()` → `_read_weapon_input()` 真的跑起来。
	# ★ 它与其他套件的关键区别：**只走输入层**（`Input.action_press`），
	#   ⛔ 不直接调 `play_model_action()` —— 上一轮就是直接调 API 因而漏掉了真根因。
	["res://tests/suite_fire_action.gd", "FireAction", true, true],
	# ---- 2026-09-29 · 剧情模式**轮 C：出击循环**（战役图 / 简报 / 标题卡 / 军资 / 重来）----
	# ⚠️ 按主题命名，不占轮次号（本仓库有并行会话，两侧都按轮次占号时撞过一次文件）。
	# ⚠️ 第 3、4 列**都必须是 true**：最后一节要在真场景里走一遍
	#    "主场景 → 战役图 → 简报 → 解析 → 军资结算 → 回主菜单"，
	#    每一跳都要 `await` 一帧（`_process` 的相位分支要跑过），而且要 `host` 挂主场景。
	["res://tests/suite_sally.gd", "Sally", true, true],
	# ---- ★ **马夫蒂火箭发射段**（剧情模式 M03 的前置演出：太平洋 → 近地轨道）----
	# 老板原话：「玩家需要操控火箭从太平洋发射到近地轨道，中间需要做无缝切换房间，
	# 可以在发射过程中做切换，通过云层来挡住玩家视线，然后在后台偷偷加载切换房间，
	# 然后切换到近地轨道中离柯西运输仓 200 km 的地方。」
	#
	# ⚠️ 按主题命名，不占轮次编号（本仓库有并行会话，两侧都按轮次占号时撞过一次文件）。
	# ⚠️ 第 3 列（async）**必须是 true**：⑥ 节要真的建两张图（太平洋 → LEO）
	#    并逐帧推云幕，整段都在 `await process_frame`。
	#    ⚠️ 而且它**不能**排在任何"会改 InputMap"的套件之前 —— 本套件虽然不读
	#    `Input.*`，但 ④ 节会跑 3600 步真物理，排在键位套件后面最省事。
	["res://tests/suite_rocket_launch.gd", "RocketLaunch", true, true],
	# ---- 2026-09-30 · **制作人模式**（设置页最底下的隐形行 + 密码 20060606）----
	# 老板原话：「设置菜单新增一个密码系统，藏到最地下看不到的地方（手柄滑动选项可以选到），
	# 选到之后输入密码 20060606 然后按 enter 打开制作人模式，解锁各种关卡和配件，可以调试
	# 各种关卡，制作人模式每次打开游戏都必须手动开启。」
	#
	# ⚠️ 按主题命名，不占轮次号（本仓库有并行会话，两侧都按轮次占号时撞过一次文件）。
	# ⚠️ 第 3、4 列**都必须是 false**：整套是纯函数 + 源码扫描 + 真建 MainMenu / 战役图实例
	#    （都不进树）—— 全套**没有一处 `await`**，也不需要 `host`（把 `settings.gd` 只读地
	#    扫一遍源码即可）。写成 `true` 会多传一个参数 ⇒ `Too many arguments` 编译失败。
	["res://tests/suite_producer.gd", "Producer", false, false],
	# ---- 2026-09-30 · **通讯（电台 / 字幕 / 对白）**（闪哈 1/2 台词剧本导入 + 轮 E 的落点）----
	# 老板原话：「这两份是闪哈一闪哈2的台词剧本，你导入进去，根据这个去做电台和字幕和人物对话。」
	#
	# ⚠️ 按主题命名，不占轮次号（本仓库有并行会话，两侧都按轮次占号时撞过一次文件）。
	# ⚠️ 第 3、4 列**都必须是 false**：整套是纯函数 + 源码扫描 + 真建 CommsDirector 实例
	#    （不进树、不读盘、不 await）—— 全套**没有一处 `await`**，也不需要 `host`。
	["res://tests/suite_comms.gd", "Comms", false, false],
	# ---- 2026-09-30 · **只读信标**（运输仓 / 内阁成员所在酒店）----
	# 老板原话：「顺便你把要对着迪拜塔（游戏内名字"内阁成员所在酒店"）
	# 也设置一个类似柯西运输仓的锁定」。
	#
	# ⚠️ 第 3、4 列**都是 true**（与上面 Comms 那条相反）：这一套要**真起一局场景**、
	#   切到**达沃**再量 —— 信标是运行时建的 `Marker3D`，"组里有几个、挂在谁身上、
	#   在不在 `units`"这三件事源码扫描证明不了。
	["res://tests/suite_landmark.gd", "Landmark", true, true],
	# 轮 51：剧情关敌方编制（M03 / M06 不出现王牌机）。纯静态读表，不进树、不 await。
	["res://tests/suite_mission_aces.gd", "MissionAces", false, false],
	# 轮 54：**关卡里双方量产机都踩板出击**（老板：「古斯塔夫出击的时候应该要踩着
	# 飞行踏板的」→ 追问后定为「剧情关双方量产机都配板」）。
	# ⚠️ 第 3、4 列都是 true：这一套要**真起 5 局**（M01 / M02 / M03 / M05
	# + 一局 1v1 反面对照）并真读 `has_pedal()` / `pedal_owner()`，
	# 源码扫描证明不了「板上到底有没有人」这种运行时事实。
	["res://tests/suite_mission_pedal.gd", "MissionPedal", true, true],
	# 轮 57：M04「重力」的**开场演出**（佩涅罗佩用光束大炮轰柯西运输仓 → 再进对决）。
	# 老板原话：「重力这一关我说要先做佩涅罗佩使用光束大炮攻击柯西运输仓，
	# 然后再是玩家操控柯西和佩涅罗佩对决。」
	#
	# ⚠️ 按主题命名，不占轮次号（本仓库有并行会话，两侧都按轮次占号时撞过一次文件）。
	# ⚠️ 第 3、4 列**都必须是 false**：整套是纯函数逐点验 + 源码扫描 + 读
	#    `WorldBuilder` 的静态常量，**不进树、不读盘、不 await**，也不需要 `host`
	#    （同 `suite_campaign` 那一档）。写成 `true` 会多传参数 ⇒ `Too many arguments`。
	["res://tests/suite_chapter_three.gd", "ChapterThree", false, false],
	["res://tests/suite_davao_intro.gd", "DavaoIntro", false, false],
	["res://tests/suite_pod_strike.gd", "PodStrike", false, false],
	["res://tests/suite_mission_bgm.gd", "MissionBgm", false, false],
	# ★ 轮 63-11：**套件不许读玩家的持久化状态**。
	# 病（实测）：玩家档里 `first_person=true` ⇒ `suite_rocket_launch` 读 440 PASS / 1 FAIL，
	# 而工程源码一行没动（那条断言本意是「默认也是 false」，读的却是运行时值）。
	# 药：`Settings.begin_isolated()` / `end_isolated()`（本文件 `_ready()` 起止各一句）。
	# 本套件钉接线 + 语义 + 清单对账；纯源码扫描 + 只读 `Settings` 状态，**不进树、不读环境**。
	["res://tests/suite_settings_isolation.gd", "SettingsIsolation", false, false],
	# ★ 轮 63-19：**鼠标操控主菜单**（右键 = 返回 / 滚轮 = 移动焦点 / 悬停播 ui_select），
	# 阶段 1 = 主链 10 页（模式 / 对战 / 阵营 / 机体 / 敌机 / 难度 / 训练 / 地图 / 遭遇 / 眩晕框）。
	#
	# ⚠️ 按主题命名，不占轮次号（本仓库有并行会话，两侧都按轮次占号时撞过一次文件）。
	# ⚠️ 第 3 列（async）必须是 **false**：整套是**纯函数 + 源码扫描**，没有一处 await。
	#    写成 true 会让 runner 去 await 一个不作协程的调用（整节断言安静地不执行）。
	# ⚠️ 第 4 列（host）必须是 **true**：套件签名是 `run(t, _host)`（本仓库绝大多数
	#    套件都带 host 位）；写 false 会变成"少传一个参数"⇒ 直接 TypeError。
	#    但 `_host` **用不到** —— `_list_geometry()` 只读 `size`，把尺寸设进实例就能量；
	#    **挂了树反而会被 `_ready()` 的 `PRESET_FULL_RECT` 改掉测试给的那个尺寸**。
	["res://tests/suite_menu_mouse.gd", "MenuMouse", false, true],
	# ★63-23 音量细分（武器/警报/BGM/引擎 八条总线 + 设置页「音量细分」子页）。
	# ⚠️ 按**主题**命名、不占轮次号（轮号会被并行会话撞；`suite_roundNN` 那种
	#    名字留给“整轮验收”，本套件只盯音量这一件事，所以叫 VolumeMixer）。
	# 第 3 列 false：整套没有一处 await（播放器创建是同步的）。
	# 第 4 列 true：要 host 的树去摸 `current_scene`（`play_3d` 挂在场景下面）。
	["res://tests/suite_volume_mixer.gd", "VolumeMixer", false, true],
	# ★63-24「无限强化演习」（新游戏模式）—— 芯片库（5 类型 × 4 品质）/ 品质抽取 /
	# 波次编排 / 敌人时间档爬升 / 幂等施加。
	# ⚠️ 第 3 列 false：整套是**纯函数 + 源码扫描**，没有一处 await。
	# ⚠️ 第 4 列 true：签名是 `run(t, _host)`（与 MenuMouse 同款；`_host` 用不到）。
	["res://tests/suite_menu_home.gd", "MenuHome", false, true],
	["res://tests/suite_endless.gd", "Endless", false, true],
	# ★63-24 R4：上面那套是**纯函数 + 源码扫描** ⇒ 它证明不了"真跑起来不卡死"。
	# 这一套真起一局演习、真清波、真选卡、连打 6 波（含奖励轮 + 超时自动选）。
	# ⚠️ 第 3 列 true：要 `await` 真帧（起局 / 清敌机都要让帧走）。
	# ⚠️ 第 4 列 true：要 `host` 才能 `instantiate` main.tscn。
	["res://tests/suite_endless_live.gd", "EndlessLive", true, true],
	# 2026-10-09：进战斗时引擎音的"突然爆音" —— 起播值 -60 dB 与稳态值之间
	# **没有过渡**，出生那一帧一帧跨完 58 dB（整队同时起同一个循环音，相干相加）。
	# 修法 = 起播淡入，且稳态逐位不变。
	# ⚠️ 第 3 列 true：第 2/3 节要 await 真帧回收临时节点。
	["res://tests/suite_audio_engine_fade.gd", "AudioEngineFade", true, true],
]

func _ready() -> void:
	Game.rifle_metrics_test_mode = true
	# 等一帧，让 autoload 与物理世界就绪
	await get_tree().process_frame
	var t := T.new()
	if t.guard_single_instance():
		get_tree().quit(3)        # 3 = 「没有运行」（退出码不是判据，但别与 0/1 混）
		return
	# ★ 轮 63-11：跑测试期间把 `Settings` 的 12 个持久化变量钉回**声明默认**，
	# 并把它的存档路径重定向到临时档 ⇒ ①「断言默认值」天然成立；
	# ② 玩家的 `user://settings.cfg` 一个字节都不碰。
	# 为什么必须做：玩家按过一次 F1，`suite_rocket_launch` 里那条「顺带核一下默认也是 false」
	# 的对照断言就会永久变红，而工程源码一行没动（实测 `440 PASS / 1 FAIL`）。
	# ⚠️ 必须在这里（**循环之前**）—— 写在循环后面的话，第一条套件就已经读到玩家档了。
	Settings.begin_isolated()
	t.resume = _want_resume()
	if t.resume:
		print("⚠️ --resume：上一轮已绿的套件将被跳过（本次非完整回归）")
		t.write_ledger_run_start()
	var only := _want_only()
	if only != "":
		print("")
		print("⚠️⚠️⚠️ --only=%s：**这不是完整回归**，只跑了名字（或路径）含这个子串的套件。" % only)
		print("       它的 PASS 数**不能**用来判断'有没有别的套件被改红'。")
		print("       交付前必须再跑一次不带 `--only` 的完整回归。")
		print("")
	print("")
	print("================ GUNDAM 无头测试 ================")
	for row: Array in SUITES:
		if only != "" and not str(row[0]).contains(only):
			continue
		await t.run_suite(str(row[0]), str(row[1]), self, bool(row[2]), bool(row[3]))
	print("================================================")
	Settings.end_isolated()   # ★ 轮 63-11：还原玩家真值 + 删临时档（配套上面那句）
	t.report()
	get_tree().quit(1 if t.failed > 0 else 0)

func _want_resume() -> bool:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if str(a) == "--resume":
			return true
	return false


## `--only=<子串>`：只跑路径含该子串的套件。
##
## ⚠️ 存在的理由：改一个套件里的两条断言、却要跑 **6 分钟**全量，会让"多验证一次"
## 变成一件有成本的事 —— 而上一批正好栽在"该验证的时候省了那一次"上面。
## 有了它，`--only=suite_gfx_map` 只要几十秒。
##
## ⚠️⚠️ 它**必须**在报告里喊出来：`t.report()` 那一行 `NNNN PASS` 长得和完整回归
## 一模一样，中间少跑了几十个套件**在数字上看不出来**（这正是本工程反复吃亏的
## "记录的条件必须等于实际发生的条件"）。
func _want_only() -> String:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--only="):
			return s.substr(7)
	return ""

