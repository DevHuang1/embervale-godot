extends SceneTree

func _init() -> void:
	var catalog := preload("res://scripts/systems/vertical_slice_catalog.gd")
	var errors: Array[String] = catalog.validate()
	if not errors.is_empty():
		push_error("Vertical slice catalog invalid: %s" % "; ".join(errors))
		quit(1)
		return
	if catalog.SET["hero_loadout"].get("weapon_id", "") != "thorn_mace":
		push_error("Starter hero loadout is missing the intended weapon")
		quit(1)
		return
	var roles: Dictionary = {}
	for faction in catalog.SET["enemy_factions"]:
		roles[str(faction.get("role", ""))] = true
	if roles.size() != 3:
		push_error("Enemy factions do not cover three distinct encounter roles")
		quit(1)
		return
	for resource_info in catalog.loadable_resources():
		var resource_path := str(resource_info.get("path", ""))
		if not ResourceLoader.exists(resource_path):
			push_error("Vertical slice resource is not registered: %s" % resource_info.get("id", ""))
			quit(1)
			return
	# The ambient script has no autoload dependency and is safe to compile here.
	if load(str(catalog.SET["animal"].get("script", ""))) == null:
		push_error("Ambient animal/life script failed to load")
		quit(1)
		return
	print("VERTICAL SLICE CATALOG PASSED")
	quit(0)
