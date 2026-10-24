extends RefCounted

static func run(t: T, _host: Node) -> void:
	t.suite("自动装填 / 全机体弹匣与独立计时")
	for profile in [SuitProfile.xi(), SuitProfile.penelope(), SuitProfile.arizeus(), SuitProfile.gp03d(), SuitProfile.neue_ziel()]:
		var u := FlightBody.new()
		u.profile = profile
		u.rifle_count = 1
		u.rifle_mag = 0
		u._auto_reload_empty_weapons()
		t.ok(u.rifle_reloading,"%s 空匣自动换弹" % profile.id)
		var duration: float = u.reload_timer
		u._tick_weapons(duration * 0.5)
		t.near(u.reload_timer,duration * 0.5,0.001,"自动检查不重置换弹进度")
		u._tick_weapons(duration * 0.5 + 0.01)
		t.eq(u.rifle_mag,profile.rifle_magazine,"完成后恢复整匣")
		t.not_ok(u.rifle_reloading,"完成后解除装填门禁")
		u.free()
	var infinite := FlightBody.new()
	infinite.profile = SuitProfile.messer_m01()
	infinite.rifle_count = 1
	infinite.rifle_mag = 0
	infinite._auto_reload_empty_weapons()
	t.not_ok(infinite.rifle_reloading,"无限弹药不插入换弹")
	infinite.free()
	var gp := FlightBody.new()
	gp.profile = SuitProfile.gp03d()
	gp.rifle_count = 0
	gp.rifle_mag = 0
	gp.funnel_mag_size = 1728
	gp.funnel_count = 0
	gp.bazooka_mag = 0
	gp.flare_count = 0
	gp._auto_reload_empty_weapons()
	t.not_ok(gp.rifle_reloading,"已丢弃武器不会重新生成")
	t.near(gp.bazooka_reload_left,FlightBody.GP03_BAZOOKA_RELOAD,0.001,"火箭筒沿用现有装填时间")
	gp._tick_weapons(10.0)
	t.eq(gp.funnel_count,108,"GP03按原有节奏补充导弹舱")
	gp._tick_weapons(10.0)
	t.eq(gp.flare_count,FlightBody.FLARE_MAG_SIZE,"干扰弹自动补满")
	t.eq(gp.bazooka_mag,FlightBody.GP03_BAZOOKA_MAG,"火箭筒自动补满")
	gp.free()
	var player := PlayerController.new()
	player.profile = SuitProfile.gustav00_armed()
	player._grenade_init = true
	player.grenade_count = 0
	player._grenade_cd = 1.0
	player._tick_weapons(0.25)
	t.near(player._grenade_cd,0.75,0.001,"榴弹射击冷却每帧只递减一次")
	t.near(player.grenade_reload_left,PlayerController.GRENADE_AUTO_RELOAD_TIME,0.001,"榴弹空匣自动装填")
	t.ok(player.slot_available("grenade"),"装填时仍可保留榴弹武装选择")
	player._tick_weapons(PlayerController.GRENADE_AUTO_RELOAD_TIME)
	t.eq(player.grenade_count,player.profile.grenade_count,"无需输入即可补满榴弹")
	player.free()
