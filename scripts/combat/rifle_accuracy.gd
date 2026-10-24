extends RefCounted
## Actual emitted rifle projectiles only. A recorder belongs to one round;
## old projectiles keep that recorder, so reset cannot contaminate the next round.
const HISTORY_LIMIT := 4096
var round_id := "%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
var shots := 0
var effective_hits := 0
var contacts := 0
var triggers := 0
var trigger_hits := 0
var pending: Dictionary = {}
var groups: Dictionary = {}
var devices: Dictionary = {}
var outcomes: Dictionary = {}
var cohorts: Dictionary = {}
var history: Array[Dictionary] = []
var dirty := false

func begin_trigger() -> int:
	triggers += 1
	groups[triggers] = {"pending": 0, "hit": false}
	return triggers

func emitted(trigger_id: int, metadata: Dictionary) -> int:
	shots += 1
	var row := metadata.duplicate(true)
	row["projectile_id"] = shots
	row["trigger_id"] = trigger_id
	row["fired_at"] = Game.elapsed
	row["weapon"] = "normal_rifle"
	pending[shots] = row
	groups[trigger_id]["pending"] += 1
	var device := str(row.get("input", "script"))
	if not devices.has(device):
		devices[device] = {"shots": 0, "effective_hits": 0, "contacts": 0, "pending": 0}
	devices[device]["shots"] += 1
	devices[device]["pending"] += 1
	var third_person := bool(row.get("third_person", false))
	var assist := bool(row.get("assist", false))
	var version := str(row.get("version", "unknown"))
	var cohort := "%s|%s|%s|%s" % [device, "third_person" if third_person else "first_person",
		"assist_on" if assist else "assist_off", version]
	row["cohort"] = cohort
	if not cohorts.has(cohort):
		cohorts[cohort] = {"input": device, "third_person": third_person, "assist": assist,
			"version": version, "shots": 0, "effective_hits": 0, "contacts": 0, "pending": 0}
	cohorts[cohort]["shots"] += 1
	cohorts[cohort]["pending"] += 1
	dirty = true
	return shots

func settle(id: int, outcome: String, hull_loss := 0.0, field_loss := 0.0,
		contact := false, hostile_alive := false) -> void:
	if not pending.has(id):
		return
	var row: Dictionary = pending[id]
	pending.erase(id)
	var effective := hostile_alive and (hull_loss > 0.0 or field_loss > 0.0)
	row.merge({"outcome": outcome, "hull_loss": hull_loss, "field_loss": field_loss,
		"contact": contact, "effective": effective, "settled_at": Game.elapsed})
	var device := str(row.get("input", "script"))
	devices[device]["pending"] -= 1
	if contact:
		contacts += 1
		devices[device]["contacts"] += 1
	var cohort := str(row.get("cohort", ""))
	if cohorts.has(cohort):
		cohorts[cohort]["pending"] -= 1
		cohorts[cohort]["contacts"] += 1 if contact else 0
		cohorts[cohort]["effective_hits"] += 1 if effective else 0
	var group: Dictionary = groups[int(row["trigger_id"])]
	if effective:
		effective_hits += 1
		devices[device]["effective_hits"] += 1
		if not group["hit"]:
			trigger_hits += 1
			group["hit"] = true
	group["pending"] -= 1
	if group["pending"] == 0:
		groups.erase(int(row["trigger_id"]))
	outcomes[outcome] = int(outcomes.get(outcome, 0)) + 1
	history.append(row)
	if history.size() > HISTORY_LIMIT:
		history.pop_front()
	dirty = true

func accuracy(device := "") -> float:
	if device != "":
		var d: Dictionary = devices.get(device, {})
		return float(d.get("effective_hits", 0)) / maxf(float(d.get("shots", 0)), 1.0)
	return float(effective_hits) / maxf(shots, 1)

func report() -> Dictionary:
	return {"version": "rifle-aim-v1", "round_id": round_id, "shots": shots,
		"effective_hits": effective_hits, "contacts": contacts, "pending": pending.size(),
		"accuracy": accuracy(), "triggers": triggers, "trigger_hits": trigger_hits,
		"devices": devices.duplicate(true), "cohorts": cohorts.duplicate(true), "outcomes": outcomes.duplicate(true),
		"history_limit": HISTORY_LIMIT, "history": history.duplicate(true),
		"pending_projectiles": pending.values()}

func save_report() -> void:
	if shots == 0 or not dirty:
		return
	DirAccess.make_dir_recursive_absolute("user://rifle_accuracy")
	var file := FileAccess.open("user://rifle_accuracy/%s.json" % round_id, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report(), "\t"))
		dirty = false
