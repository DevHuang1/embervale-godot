extends SceneTree

func _initialize() -> void:
	var catalog := preload("res://scripts/systems/asset_intake_catalog.gd")
	for entry in catalog.ENTRIES:
		if catalog.quality_score(entry) < 90 \
				or catalog.quality_band(entry) != "SHIP-READY":
			push_error("Reviewed asset is not ship-ready: %s" % entry.get("id", ""))
			quit(1)
			return
	var held := catalog.ENTRIES[0].duplicate(true)
	held["license"] = "UNKNOWN"
	if catalog.quality_band(held) == "SHIP-READY":
		push_error("Uncleared asset incorrectly scored ship-ready")
		quit(1)
		return
	print("ALL ASSET QUALITY SCORECARD TESTS PASSED")
	quit(0)
