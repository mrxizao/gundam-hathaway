extends RefCounted
const D:=preload("res://scripts/data/m09_dialogue.gd")
const Radio:=preload("res://scripts/flight/m09_radio.gd")
const Comms:=preload("res://scripts/flight/comms_director.gd")
static func run(t:T)->void:
	t.suite("M09Radio / exact script import, provenance and trigger coverage")
	var source:String=FileAccess.get_file_as_string(D.SOURCE)
	t.eq(D.LINES.size(),51,"all supplied character lines imported")
	var ids:Dictionary={};var coverage:Dictionary={}
	for number in range(1,D.LINES.size()+1):
		var line:Dictionary=D.entry(number);var packet:Dictionary=D.packet(number)
		t.ok(source.contains(line.text),"dialogue exactly matches supplied text")
		t.not_ok(ids.has(line.id),"stable unique radio identifier");ids[line.id]=true
		t.eq(packet.text,line.text,"no stage directions or shortening inserted")
		t.ok(packet.src.begins_with(D.SOURCE),"source remains separately attributable")
		t.gt(packet.secs,float(line.text.length())/5.5,"enough time to read full sentence")
		if line.speaker!="雷恩":t.ok(packet.speaker.contains("敌方") or packet.speaker.contains("马夫蒂"),"opposing-side speech cannot look like Raine's own channel")
		if "独白" in line.kind:t.ok(packet.speaker.contains("独白"),"monologue label preserved")
	for cue in D.INTRO:
		coverage[cue[2]]=int(coverage.get(cue[2],0))+1
		t.ok(cue[0]<13.1 or cue[0]>=14,"no caption begins during full black")
	for group in D.GROUPS.values():
		for number in group:coverage[number]=int(coverage.get(number,0))+1
	t.eq(coverage.size(),51,"every imported line has a cinematic or event route")
	for number in coverage:t.eq(coverage[number],1,"no line assigned to conflicting routes")
	t.suite("M09Radio / real-event gates, no repeats and stale-line suppression")
	var radio:=Radio.new();var comms:=Comms.new()
	radio.observe({"elapsed":3,"city_distance":30000,"messer_distance":24000,"messer_alive":3,"messer_down":0})
	t.ok(radio.fired.has("opening"),"opening thoughts start after launch")
	t.not_ok(radio.fired.has("city"),"city alert waits for approach")
	t.not_ok(radio.fired.has("first_down"),"kill dialogue cannot fire on elapsed time")
	radio.observe({"elapsed":25,"city_distance":12000,"messer_distance":2000,"messer_alive":2,"messer_down":1,"dashing":true,"xi_distance":20000})
	t.ok(radio.fired.has("city") and radio.fired.has("counterattack") and radio.fired.has("first_down"),"approach, contact and actual kill select their event groups")
	var queued:int=radio.pending.size();radio.notify("first_down",true)
	t.eq(radio.pending.size(),queued,"repeated kill callback does not duplicate a group")
	radio.context["messer_alive"]=1
	t.not_ok(radio.valid_line(39),"two enemies remaining cannot play after a second kill")
	radio.context["messer_alive"]=0
	t.not_ok(radio.valid_line(25),"dead enemy group cannot keep talking")
	radio.notify("xi_retreat",true);radio.begin_result(comms)
	t.ok(radio.won,"victory selects closing reflections")
	for number in radio.pending:t.ok(number>=44,"combat queue cannot leak into victory reflections")
	var delivered:Dictionary={}
	for step in 30:
		radio.drain(comms);comms.tick(.1)
		for entry in comms.live():delivered[entry.line.id]=true
		comms.tick(30)
	t.eq(delivered.size(),8,"withdrawal and all four ending reflections are reachable")
	t.eq(radio.pending.size(),0,"ending drains without blocking results")
	radio.free()
