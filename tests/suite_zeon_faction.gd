extends RefCounted

static func run(t: T, _host: Node) -> void:
	t.suite("Zeon / Neue Ziel faction")
	var r := BattleFormation.roster_of(BattleFormation.Side.ZEON)
	t.eq(BattleFormation.Side.MAFTY, 0, "Existing Mafty ID unchanged")
	t.eq(BattleFormation.Side.FEDERATION, 1, "Existing Federation ID unchanged")
	t.eq(r.side, BattleFormation.Side.ZEON, "Zeon has its own roster")
	t.eq(r.name_cn, "吉翁", "Zeon display name")
	t.ok(not r.selectable, "Zeon MA excluded from squad selection")
	t.eq(BattleFormation.selectable_sides().size(), 2, "Two squad factions")
	t.ok(not BattleFormation.selectable_sides().has(r.side), "No Zeon squad entry")
	t.ok(r.all_suits()==[SuitProfile.Id.NEUE_ZIEL], "Only supplied MA")
	t.eq(r.ace(), -1, "No squad ace fallback")
	t.eq(r.mp(), -1, "No squad mass-production fallback")
	t.ok(BattleFormation.lineup(r.side, -1).is_empty(), "MA never spawns in squad lineup")
	t.ok(not BattleFormation.belongs_to(r.side, SuitProfile.Id.XI), "Mafty unit cannot belong to Zeon")
	var image := Image.new()
	t.eq(image.load(r.logo_path), OK, "Supplied Zeon emblem loads")
