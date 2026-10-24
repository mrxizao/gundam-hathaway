class_name SuitePodStrike
extends RefCounted
const PS := preload("res://scripts/data/pod_strike_script.gd")
const MS := preload("res://scripts/data/mission_script.gd")
const MAIN_S := preload("res://scripts/main.gd")
class InsertStub extends Control:
	var starts := 0
	func begin() -> bool:
		starts+=1
		return true
static func run(t: T) -> void:
	var dialogue=preload("res://scripts/data/pod_strike_dialogue.gd")
	t.suite("PodStrike / radio dialogue and blocking video")
	var expected:Array[String]=[]
	for i in range(1126,1138):expected.append("h1:%04d" % i)
	for i in range(1148,1163):expected.append("h1:%04d" % i)
	var actual:Array[String]=[]
	for cue in dialogue.CUES+dialogue.VIDEO_CUES:
		actual.append(cue[2])
		t.ok(not dialogue.Bank.plain_of(cue[2]).is_empty(),"dialogue source exists")
	actual.sort();expected.sort()
	t.eq(actual,expected,"all 27 requested lines appear once")
	t.eq(dialogue.active_lines(8.99,true).size(),0,"no early Amuro subtitle")
	t.eq(dialogue.active_lines(9.01,true)[0].id,"h1:1155","Amuro long line at video nine seconds")
	t.eq(dialogue.active_lines(10.01,true).size(),2,"second line does not erase long line at ten seconds")
	var director=preload("res://scripts/cinematics/pod_strike_director.gd").new()
	var video:=InsertStub.new();director.insert_video=video
	t.near(director.advance_timeline(59.0,.5),59.5,.0001,"normal clock before insertion")
	t.near(director.advance_timeline(59.9,.2),60.0,.0001,"frame crossing lands exactly at insert boundary")
	t.eq(video.starts,1,"start insert once")
	t.near(director.advance_timeline(60.0,30.0),60.0,.0001,"timeline stays frozen through entire video")
	director._insert_finished()
	t.near(director.advance_timeline(60.0,.25),60.25,.0001,"EOF resumes remaining cinematic at sixty seconds")
	t.eq(video.starts,1,"insert does not replay after EOF")
	director.free();video.free()
	t.suite("PodStrike / approved 90-second timeline")
	for pair in [[PS.T_ORBIT_END,17.0],[PS.T_PACIFIC,23.0],[PS.T_INTERCEPT,42.0],[PS.T_CHARGE,50.3],[PS.T_FIRE,52.0],[PS.T_CUT,52.8],[PS.T_ENEMY_WIDE,60.0],[PS.T_ENEMY_EYE,66.0],[PS.T_ESCAPE,72.0],[PS.T_FLYOUT,75.0],[PS.T_CLOUD_RUSH,78.0],[PS.T_XI_FRONT,84.0],[PS.T_ORBIT_FINISH,88.0],[PS.TOTAL,90.0]]:
		t.near(pair[0],pair[1],.0001,"approved timing")
	var last_alt:=PS.altitude(0)
	for frame in 5401:
		var altitude:=PS.altitude(frame/60.0)
		t.ok(altitude>=3500.0 and altitude<=last_alt+.01,"transport remains above ground and descends monotonically")
		last_alt=altitude
	for cut in [PS.T_ORBIT_END,PS.T_PACIFIC,PS.T_REVEAL,PS.T_BURN,PS.T_HIT,PS.T_ESCAPE]:
		t.lt(absf(PS.altitude(cut+.0001)-PS.altitude(cut-.0001)),.1,"descent position continuous at cut")
	t.suite("PodStrike / requested post-impact storyboard")
	t.eq(PS.stage_at(PS.T_CUT),PS.Stage.XI_REACT,"impact returns to Xi transport cockpit")
	t.ok(PS.inside_pod(PS.T_CUT+.4),"post-impact Xi viewport is black under cockpit UI")
	t.eq(PS.stage_at(PS.T_ENEMY_WIDE),PS.Stage.ENEMY_PUSH,"Penelope third-person shot precedes cockpit")
	t.eq(PS.stage_at(PS.T_ENEMY_EYE),PS.Stage.ENEMY_EYE,"dolly arrives in Penelope cockpit")
	t.near(PS.T_ESCAPE-PS.T_ENEMY_EYE,6.0,.001,"six-second cockpit hold before Xi escapes")
	t.eq(PS.stage_at(PS.T_ESCAPE),PS.Stage.ESCAPE,"escape begins while still watching from enemy cockpit")
	t.eq(PS.stage_at(PS.T_FLYOUT),PS.Stage.FLYOUT,"continuous exit follows escape reveal")
	t.eq(PS.stage_at(PS.T_CLOUD_RUSH),PS.Stage.CLOUD_RUSH,"camera rushes through cloud")
	t.eq(PS.stage_at(PS.T_XI_FRONT),PS.Stage.XI_FRONT,"camera reaches Xi front then orbits")
	t.eq(PS.stage_at(PS.T_ORBIT_FINISH),PS.Stage.HANDOFF,"rear third-person view established")
	t.near(PS.TOTAL-PS.T_ORBIT_FINISH,2.0,.001,"two seconds locked in final third-person shot")
	t.not_ok(PS.done(PS.TOTAL-.001),"no early player control")
	t.ok(PS.done(PS.TOTAL),"release only after complete final hold")
	t.near(PS.T_FIRE-PS.T_CHARGE,1.7,.001,"weapon charge cue preserved")
	t.near(PS.beam_secs(),.8,.001,"rapid sweep preserved")
	t.near(PS.sweep_aim(PS.T_HIT,Vector3.ZERO).length(),0.0,.01,"impact still coincides with beam crossing transport")
	t.ok(PS.escape_pos(PS.T_ESCAPE).is_equal_approx(PS.pod_pos(PS.T_ESCAPE)),"Xi escape starts at transport, no teleport")
	t.suite("PodStrike / continuous fly-through geometry")
	var enemy_eye:=Vector3(-5600,8000,-6800)
	var xi:=Transform3D(Basis.IDENTITY,Vector3(-600,5700,-2000))
	var end:=xi*Vector3(0,18,-110)
	t.ok(PS.fly_camera(PS.T_FLYOUT,enemy_eye,Basis.IDENTITY,xi).is_equal_approx(enemy_eye),"fly-through starts at same enemy eye position")
	t.ok(PS.fly_camera(PS.T_XI_FRONT,enemy_eye,Basis.IDENTITY,xi).is_equal_approx(end),"fly-through ends exactly at orbit start")
	var cloud_anchor:=Vector3(-3500,4800,-4500)
	t.ok(PS.fly_camera((PS.T_FLYOUT+PS.T_XI_FRONT)*.5,enemy_eye,Basis.IDENTITY,xi,cloud_anchor).distance_to(cloud_anchor)<.01,"fly-through intersects actual chosen cloud centre")
	t.ok(PS.fly_camera(PS.T_XI_FRONT,enemy_eye,Basis.IDENTITY,xi,cloud_anchor).is_equal_approx(end),"cloud routing does not alter front-shot endpoint")
	var previous:=enemy_eye
	var lowest:=INF
	var peak_speed:=0.0
	var dt: float=(PS.T_XI_FRONT-PS.T_FLYOUT)/100.0
	var finite:=true
	var unmasked:=true
	for i in range(101):
		var time: float=PS.T_FLYOUT+float(i)*dt
		var point:=PS.fly_camera(time,enemy_eye,Basis.IDENTITY,xi)
		finite=finite and point.is_finite()
		unmasked=unmasked and PS.transition_black(time)==0.0
		lowest=minf(lowest,point.y)
		if i>0:peak_speed=maxf(peak_speed,point.distance_to(previous)/dt)
		previous=point
	t.ok(finite,"all sampled camera positions finite")
	t.ok(unmasked,"continuous path never hidden by a black cut")
	t.lt(lowest,5500.0,"trajectory dives through cloud altitudes")
	t.gt(peak_speed,2000.0,"middle traversal conveys high speed")
	t.lt(PS.fly_camera(PS.T_FLYOUT+.001,enemy_eye,Basis.IDENTITY,xi).distance_to(enemy_eye),.1,"exit has zero starting relative velocity")
	t.lt(PS.fly_camera(PS.T_XI_FRONT-.001,enemy_eye,Basis.IDENTITY,xi).distance_to(end),.1,"arrival eases into orbit without a jump")
	for time: float in [PS.T_PACIFIC,PS.T_REVEAL,PS.T_BURN,PS.T_INTERCEPT,PS.T_FIRE,PS.T_HIT]:
		var pod:=PS.pod_pos(time)
		var eye:=PS.cam_pos(time,pod)
		var direction:=eye.direction_to(PS.cam_look(time,pod,Vector3.ZERO))
		var separation:=rad_to_deg(acos(clampf(direction.dot(eye.direction_to(pod)),-1.0,1.0)))
		t.ok(separation<PS.camera_fov(time)*.45,"transport stays framed before impact")
	t.suite("PodStrike / mission isolation and control gate")
	for mission in MS.all(): t.eq(mission.pod_strike,mission.id=="M04","only M04 uses cinematic")
	_live(t)

static func _live(t: T) -> void:
	t.suite("PodStrike / ★ 运行时收尾（演出结束必须交还操控）")
	# ---- 摆成「演出进行中」----
	var m: Node3D = MAIN_S.new()
	# 相机要一只**真**的 chase（收尾会写 `externally_stepped` 与 `fov`）——
	# 塞一只纯 `Camera3D` 会缺属性而报 SCRIPT ERROR，那就不是在验流程了。
	var cam := ChaseCamera.new()
	m.set("chase", cam)
	m.set("phase", MAIN_S.Phase.POD_STRIKE)
	m.set("_strike_t", PS.TOTAL - 0.5)
	m.set("_strike_cut", false)
	# 模拟 `_begin_pod_strike()` 已起过本关开场曲（M04 的 `bgm != ""`）。
	m.set("_strike_bgm_live", true)
	cam.externally_stepped = true
	cam.fov = PS.CAM_FOV
	# `Game.phase` 是**全局状态**（autoload）⇒ 验完必须还回去，
	# 否则后面那些读 `Game.phase` 的套件会莫名其妙地红。
	var saved_gphase: int = Game.phase
	Game.set_phase(Game.Phase.INTRO)
	# 真的把本场那一首起起来：这样「不切歌」才是**可证伪**的
	#（若 `_start_fight()` 的闸门被拿掉，`play_bgm(BATTLE)` 会再轮换一首 ⇒ 当场变红）。
	Audio.set_story_mode(false)
	Audio.request_battle_open("car5p3")
	Audio.play_bgm(Audio.Bgm.BATTLE)
	var track_before := Audio.current_bgm_track()
	t.eq(track_before, "car5p3", "（前置）本场开场曲起得来（起不来则下一条是空判）")

	# ---- ★ 真的步进：一帧跨过 TOTAL ----
	m.call("_tick_pod_strike", 1.0)

	t.eq(int(m.get("phase")), int(MAIN_S.Phase.FIGHT),
		"★★ 演出到点 ⇒ `phase` 推进到 FIGHT（漏了收尾调用的话它**永远停在 POD_STRIKE**）")
	t.eq(int(Game.phase), int(Game.Phase.FIGHT),
		"★★ `Game.phase` 跟着到 FIGHT（`player.controls_enabled` 正是在这条路上被打开的）")
	t.near(float(m.get("_strike_t")), 0.0, 0.0001,
		"★★ 收尾把 `_strike_t` 归零（演出真的退出了，不是「镜头切了但还在演」）")
	t.ok(not bool(cam.externally_stepped),
		"★★ 相机交还给正常的追尾逻辑（`externally_stepped` 回 false）")
	t.near(float(cam.fov), float(cam.base_fov), 0.001,
		"★★ 长焦被**还原**（不还原 = 整局战斗长焦，而且**不报错**）")
	t.eq(bool(m.get("_strike_bgm_live")), false,
		"★★ 演出起的 BGM 被 `_start_fight()` **消费一次**（闸门没被绕过的代码形态）")
	t.eq(Audio.current_bgm_track(), track_before,
		"★★ 演出 → 战斗**不切歌**（老板：「演出 11 秒播放，然后也作为本关的 bgm」）")

	# ---- 负对照：还没到 TOTAL 就不许收尾 ----
	m.set("phase", MAIN_S.Phase.POD_STRIKE)
	m.set("_strike_t", PS.TOTAL - 0.5)
	m.call("_tick_pod_strike", 0.1)
	t.eq(int(m.get("phase")), int(MAIN_S.Phase.POD_STRIKE),
		"★ 负对照：没到 TOTAL 就不收尾（`done()` 是「到点」不是「大致到了」）")
	t.ok(float(m.get("_strike_t")) > 0.0,
		"★ 演出中的 `_strike_t` 正常累加（" + str(snappedf(float(m.get("_strike_t")), 0.01)) + "）")

	# ---- 还原全局状态（不给后面的套件留坑）----
	Game.set_phase(saved_gphase)
	Audio.stop_bgm(0.0)
	Audio.requested_battle_open = ""
	# ⚠️ 用 `free()` 而不是 `queue_free()`：后者只是**排队**，而 `--only` 跑完就退出的
	# 进程等不到那一帧的 flush ⇒ 退出时打
	#   WARNING: 2 ObjectDB instances were leaked at exit
	#   ERROR:   1 resources still in use at exit
	# 而交付判据里「四类报错计数」会把那条 `ERROR` 算进去。
	# 它们**不在树里**（本节刻意不 `add_child`）⇒ `free()` 安全：
	# 没有 `_exit_tree` / `_notification` 钩子，也不参与组与信号。
	m.free()
	cam.free()


static func _read(p: String) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s
