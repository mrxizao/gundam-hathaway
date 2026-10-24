extends RefCounted
const MS := preload("res://scripts/data/mission_script.gd")
const C := preload("res://scripts/data/comms.gd")
const D := preload("res://scripts/flight/comms_director.gd")
static func run(t: T) -> void:
	t.suite("DavaoIntro / mission isolation and radio ownership")
	t.ok(MS.m01().davao_intro, "M01 has sea opening")
	for id in ["M02","M03","M04","M05","M06","M07"]:
		t.not_ok(MS.by_id(id).davao_intro, id+" opening unchanged")
	t.ok(MS.m04().pod_strike, "M04 continuous cinematic preserved")
	var radio := D.new()
	for id: String in ["davao_sibet_01","davao_bridge_01","davao_gawman_01"]:
		t.ok(radio.push(id), "opening radio can play")
		radio.tick(.01)
		t.eq(radio.live()[0]["line"]["text"], C.radio(id)["text"], "existing dialogue preserved")
		radio.tick(10.0)
		t.eq(radio.live().size(),0,"radio finishes before next shot")
	var prayer := "为不幸卷入战火中的亡灵而祈祷"
	t.ok(radio.push("davao_gawman_02",prayer),"prayer can use requested wording")
	radio.tick(.01)
	var line: Dictionary = radio.live()[0]["line"]
	t.eq(line["text"],prayer,"prayer wording exact")
	t.eq(line["speaker"],"加乌曼","prayer speaker preserved")
	t.eq(line["src"],C.radio("davao_gawman_02")["src"],"source attribution preserved")
	t.near(line["secs"],C.hold_secs(prayer,C.STYLE_RADIO),.0001,"hold duration matches displayed wording")
	t.not_ok(radio.push("davao_gawman_02"),"hotel hit cannot repeat prayer")
	radio.tick(10.0)
	var seen := radio.seen_count()
	radio.tick_mission(MS.m01(),{"elapsed":100.0,"landmark_hits":1})
	t.eq(radio.seen_count(),seen,"normal battle triggers reuse cinematic deduplication")
	t.eq(radio.queued(),0,"no repeated opening after control release")
	radio.clear()
	t.ok(radio.push("davao_gawman_02",prayer),"retry can replay prayer")
	t.eq(C.radio("davao_gawman_02")["text"],"向诸位陪葬者的在天之灵表示哀悼","override never mutates dialogue data")
