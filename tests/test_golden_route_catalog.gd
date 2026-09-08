extends SceneTree

func _init() -> void:
	var catalog := preload("res://scripts/systems/golden_route_catalog.gd")
	var errors: Array[String] = catalog.validate()
	if not errors.is_empty():
		push_error("Golden Route catalog invalid: %s" % ", ".join(errors))
		quit(1)
		return
	if str(catalog.BEATS[0].get("recovery", "")) != "grove_arrival" \
			or str(catalog.BEATS[-1].get("recovery", "")) != "beacon_relit":
		push_error("Golden Route recovery endpoints are not save-safe")
		quit(1)
		return
	for beat in catalog.BEATS:
		if beat.get("required_signals", []).size() < 2:
			push_error("Route beat lacks actionable acceptance signals: %s" % beat.get("id", ""))
			quit(1)
			return
	print("ALL GOLDEN ROUTE CATALOG TESTS PASSED")
	quit()
