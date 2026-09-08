extends SceneTree

const REGISTRY := preload("res://scripts/autoload/icon_registry.gd")

func _init() -> void:
	var registry := REGISTRY.new()
	var required := ["strike", "whirl", "dash_strike", "heal_bloom", "explosion",
		"comet", "sword", "mace", "axe", "blade", "staff", "shield", "potion",
		"nature", "quest", "cloak", "cinderhart_maul"]
	var failures: Array[String] = []
	for icon_id in required:
		if not registry.has_icon(icon_id):
			failures.append("missing icon: %s" % icon_id)
		if registry.icon_for(icon_id) == null:
			failures.append("unresolved texture: %s" % icon_id)
	if not FileAccess.file_exists("res://assets/ui/icons/raster/strike.png"):
		failures.append("raster runtime pack missing")
	if registry.has_icon("unknown_gameplay_id"):
		failures.append("unknown ID incorrectly resolves")
	if registry.icon_for("unknown_gameplay_id") != null:
		failures.append("unknown ID did not use null fallback")
	print("ICON REGISTRY TESTS PASSED" if failures.is_empty() else "FAILURES: ", failures)
	quit(1 if not failures.is_empty() else 0)
