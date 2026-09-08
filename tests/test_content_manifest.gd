extends SceneTree

const MANIFEST = preload("res://scripts/systems/content_manifest.gd")

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs := root.get_node_or_null("/root/GameState") as GameState
	if gs == null:
		push_error("GameState autoload missing")
		quit(1)
		return
	var manifest: Dictionary = MANIFEST.from_registry(gs.get_content_registry())
	var errors: Array[String] = MANIFEST.validate(manifest)
	if not errors.is_empty():
		push_error("Live content manifest invalid: %s" % "; ".join(errors))
		quit(1)
		return
	var resource := MANIFEST.resource_from_registry(gs.get_content_registry()) as ContentManifestResource
	if resource == null or not resource.validate().is_empty():
		push_error("Versioned content manifest resource is not valid")
		quit(1)
		return
	var template := load("res://resources/content_manifest.tres") as ContentManifestResource
	if template == null or template.manifest_version != MANIFEST.CURRENT_VERSION:
		push_error("Project content manifest resource is missing or unversioned")
		quit(1)
		return
	var legacy: Dictionary = manifest.duplicate(true)
	legacy["manifest_version"] = 0
	legacy["content_schema"] = 0
	legacy["registry_schema"] = 0
	var migrated: Dictionary = MANIFEST.migrate(legacy)
	if int(migrated.get("manifest_version", 0)) != MANIFEST.CURRENT_VERSION \
			or not MANIFEST.validate(migrated).is_empty():
		push_error("Legacy content manifest did not migrate to a valid version")
		quit(1)
		return
	print("CONTENT MANIFEST PASSED")
	quit(0)
