extends SceneTree

const REGISTRY := preload("res://scripts/systems/content_registry.gd")

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs := root.get_node_or_null("/root/GameState") as GameState
	if gs == null:
		push_error("GameState autoload missing")
		quit(1)
		return
	var registry: Dictionary = gs.get_content_registry()
	if not gs.get_content_registry_errors().is_empty():
		push_error("Startup content registry gate reported errors: %s" % "; ".join(gs.get_content_registry_errors()))
		quit(1)
		return
	if int(registry.get("schema_version", 0)) != REGISTRY.CURRENT_VERSION:
		push_error("Runtime registry schema version missing")
		quit(1)
		return
	var errors := REGISTRY.validate(registry)
	if not errors.is_empty():
		push_error("Canonical content registry invalid: %s" % "; ".join(errors))
		quit(1)
		return
	if REGISTRY.lookup(registry, "weapon", "mug_mace").is_empty():
		push_error("Canonical registry lookup failed")
		quit(1)
		return
	if registry.get("material", {}).is_empty() or not registry.has("objective"):
		push_error("Runtime registry omitted materials or objectives")
		quit(1)
		return
	var invalid := {"weapon": {"shared": {"id": "shared"}, "other": {"id": "shared"}}}
	if REGISTRY.validate(invalid).is_empty():
		push_error("Canonical registry did not reject duplicate IDs")
		quit(1)
		return
	var missing_reference := {"enemy": {"broken": {"id": "broken", "scene": "res://missing_scene.tscn"}}}
	if REGISTRY.validate(missing_reference).is_empty():
		push_error("Canonical registry did not reject missing references")
		quit(1)
		return
	print("ALL CONTENT REGISTRY ADAPTER TESTS PASSED")
	quit()
