extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs := root.get_node_or_null("/root/GameState") as GameState
	if gs == null:
		push_error("GameState autoload missing")
		quit(1)
		return
	var seen: Dictionary = {}
	for id in gs.WEAPON_DEFS:
		var definition: Dictionary = gs.WEAPON_DEFS[id]
		if str(definition.get("id", "")) != str(id) or seen.has(id):
			push_error("Invalid or duplicate weapon ID: %s" % id)
			quit(1)
			return
		seen[id] = true
	seen.clear()
	for id in gs.ARMOR_DEFS:
		var definition: Dictionary = gs.ARMOR_DEFS[id]
		if str(definition.get("id", "")) != str(id) or seen.has(id):
			push_error("Invalid or duplicate armor ID: %s" % id)
			quit(1)
			return
		seen[id] = true
	for recipe_id in CraftingData.RECIPES:
		var recipe: Dictionary = CraftingData.RECIPES[recipe_id]
		var output_id := str(recipe.get("output_id", ""))
		var category := str(recipe.get("category", ""))
		var valid_output := category == "weapon" and gs.WEAPON_DEFS.has(output_id) \
			or category == "armor" and gs.ARMOR_DEFS.has(output_id) \
			or category in ["potion", "utility"] and output_id == "moss_tonic"
		if not valid_output or int(recipe.get("gold_cost", -1)) < 0:
			push_error("Recipe %s has unreachable output: %s" % [recipe_id, output_id])
			quit(1)
			return
	for realm_id in Bestiary.REALMS:
		var realm: Dictionary = Bestiary.REALMS[realm_id]
		if str(realm.get("id", "")) != str(realm_id) \
			or str(realm.get("archetype", "")).is_empty() \
			or str(realm.get("boss_key", "")).is_empty():
			push_error("Invalid realm identity: %s" % realm_id)
			quit(1)
			return
		var variants: Dictionary = Bestiary.VARIANTS.get(realm_id, {})
		for tier in ["normal", "hard", "elite"]:
			var variant: Dictionary = variants.get(tier, {})
			if variant.is_empty() or str(variant.get("kind", "")).is_empty() \
				or int(variant.get("hp", 0)) <= 0:
				push_error("Missing %s variant for realm %s" % [tier, realm_id])
				quit(1)
				return
	for realm_id in RealmIdentityCatalog.PROFILES:
		var identity: Dictionary = RealmIdentityCatalog.PROFILES[realm_id]
		for field in ["traversal", "resource_ritual", "ambient_behavior",
			"elite_composition", "landmark_reward", "reward"]:
			if not identity.has(field):
				push_error("Realm identity %s missing %s" % [realm_id, field])
				quit(1)
				return
	for boss_id in Bestiary.BOSS_DEFS:
		var boss: Dictionary = Bestiary.BOSS_DEFS[boss_id]
		if str(boss_id).is_empty() or str(boss.get("name", "")).is_empty():
			push_error("Invalid boss identity: %s" % boss_id)
			quit(1)
			return
		for skill in boss.get("skill_pool", []):
			if not skill is Dictionary or str(skill.get("id", "")).is_empty():
				push_error("Boss %s has an invalid skill-pool entry" % boss_id)
				quit(1)
				return
	print("ALL CONTENT REGISTRY INTEGRITY TESTS PASSED")
	quit()
