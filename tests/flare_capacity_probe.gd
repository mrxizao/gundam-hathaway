extends Node
func _ready() -> void:
	var body := FlightBody.new()
	for id: int in [SuitProfile.Id.GP03D,SuitProfile.Id.NEUE_ZIEL,SuitProfile.Id.XI]:
		body.profile = SuitProfile.new()
		body.profile.id = id
		var expected := 30 if id == SuitProfile.Id.XI else 120
		assert(body.flare_mag_size() == expected)
		body.flare_count = 0
		body.flare_reload_left = 0.01
		body._tick_weapons(0.02)
		assert(body.flare_count == expected)
	body.free()
	print("FLARE CAPACITY: 6 PASS")
	get_tree().quit()
