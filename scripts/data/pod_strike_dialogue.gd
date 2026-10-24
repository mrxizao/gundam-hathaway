extends RefCounted
const Bank = preload("res://scripts/data/comms_bank.gd")
const INSERT_AT := 60.0
const VIDEO := "res://assets/video/m04_amuro_insert.ogv"
const CUES := [
	[0.8,3.6,"h1:1126"],
	[4.8,2.4,"h1:1127"],
	[7.5,4.1,"h1:1128"],
	[12.0,4.6,"h1:1129"],
	[17.2,3.0,"h1:1130"],
	[20.5,3.8,"h1:1131"],
	[25.0,2.8,"h1:1132"],
	[28.2,2.9,"h1:1133"],
	[31.4,1.9,"h1:1134"],
	[33.6,2.0,"h1:1135"],
	[36.0,3.8,"h1:1136"],
	[40.0,1.8,"h1:1153"],
	[42.0,2.5,"h1:1148"],
	[44.6,3.0,"h1:1149"],
	[47.8,1.4,"h1:1150"],
	[49.4,1.8,"h1:1151"],
	[51.4,2.0,"h1:1152"],
	[53.5,2.8,"h1:1154"],
	[60.1,1.8,"h1:1157"],
	[62.2,2.0,"h1:1158"],
	[64.5,2.6,"h1:1159"],
	[68.0,1.6,"h1:1160"],
	[70.0,3.8,"h1:1161"],
	[74.2,3.2,"h1:1162"],
	[84.3,4.2,"h1:1137"],
 ]
const VIDEO_CUES := [[9.0,4.75,"h1:1155"],[10.0,3.75,"h1:1156"]]
static func active_lines(clock: float, in_video := false) -> Array[Dictionary]:
	var out:Array[Dictionary]=[]
	for cue in (VIDEO_CUES if in_video else CUES):
		if clock<cue[0] or clock>=cue[0]+cue[1]:continue
		var age:float=clock-cue[0]
		var alpha:float=minf(1.0,age/.12)*minf(1.0,(cue[0]+cue[1]-clock)/.18)
		out.append({"id":cue[2],"text":Bank.plain_of(cue[2]),"speaker":Bank.speaker_of(cue[2]),"alpha":alpha})
	return out
