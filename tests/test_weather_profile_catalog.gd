extends SceneTree

func _init() -> void:
	var catalog := preload("res://scripts/systems/weather_profile_catalog.gd")
	var errors: Array[String] = catalog.validate()
	if not errors.is_empty():
		push_error("Weather profile validation failed: %s" % "; ".join(errors))
		quit(1)
		return
	var high: Dictionary = catalog.for_realm("mistfen")
	var low: Dictionary = catalog.for_realm("mistfen", true)
	if int(low.get("particle_cap", 99)) >= int(high.get("particle_cap", 0)) \
			or float(low.get("ambient_variation", 1.0)) > 0.08 \
			or str(low.get("weather", "")) == str(high.get("weather", "")):
		push_error("Low-quality weather fallback is not deterministic/bounded")
		quit(1)
		return
	print("WEATHER PROFILE CATALOG PASSED")
	quit(0)
