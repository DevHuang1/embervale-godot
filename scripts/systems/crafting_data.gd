extends RefCounted
class_name CraftingData

## Data-driven recipe definitions for the crafting system.
## Categories: weapon, armor, potion, utility

const RECIPES := {
	# === WEAPONS ===
	"ember_sword_ii": {
		"category": "weapon", "output_id": "ember_sword", "output_qty": 1,
		"rarity": 2, "name": "Emberfang II",
		"materials": {"bramble_wood": 4, "iron_shard": 6, "emberstone": 2},
		"gold_cost": 45, "station": "forge"
	},
	"moon_staff_ii": {
		"category": "weapon", "output_id": "arcane_staff", "output_qty": 1,
		"rarity": 2, "name": "Moonbough II",
		"materials": {"fen_reed": 4, "moonmoss": 3, "crystal_fragment": 1},
		"gold_cost": 55, "station": "forge"
	},
	"thorn_mace": {
		"category": "weapon", "output_id": "thornmace", "output_qty": 1,
		"rarity": 2, "name": "Thornmace",
		"materials": {"bramble_wood": 3, "beast_hide": 2, "iron_shard": 4},
		"gold_cost": 40, "station": "forge"
	},
	# === ARMOR ===
	"bramble_plate": {
		"category": "armor", "output_id": "warden_plate", "output_qty": 1,
		"rarity": 2, "name": "Bramble Plate",
		"materials": {"iron_shard": 6, "bramble_wood": 3, "beast_hide": 2},
		"gold_cost": 50, "station": "forge"
	},
	"moonfen_cloak_recipe": {
		"category": "armor", "output_id": "moonfen_cloak", "output_qty": 1,
		"rarity": 2, "name": "Moonfen Cloak",
		"materials": {"moonmoss": 4, "moss_fiber": 5, "fen_reed": 2},
		"gold_cost": 35, "station": "forge"
	},
	"spore_wrap_recipe": {
		"category": "armor", "output_id": "spore_wrap", "output_qty": 1,
		"rarity": 1, "name": "Spore Wrap",
		"materials": {"moss_fiber": 4, "spore_dust": 3},
		"gold_cost": 20, "station": "forge"
	},
	# === POTIONS ===
	"moss_tonic": {
		"category": "potion", "output_id": "moss_tonic", "output_qty": 2,
		"rarity": 1, "name": "Moss Tonic",
		"materials": {"moss_fiber": 3, "fen_reed": 2},
		"gold_cost": 12, "station": "alchemy"
	},
	"ember_salve": {
		"category": "potion", "output_id": "ember_salve", "output_qty": 1,
		"rarity": 2, "name": "Ember Salve",
		"materials": {"emberstone": 2, "beast_hide": 1, "moss_fiber": 2},
		"gold_cost": 20, "station": "alchemy"
	},
	"moon_draught": {
		"category": "potion", "output_id": "moon_draught", "output_qty": 1,
		"rarity": 2, "name": "Moon Draught",
		"materials": {"moonmoss": 3, "crystal_fragment": 1},
		"gold_cost": 25, "station": "alchemy"
	},
	"spore_antidote": {
		"category": "potion", "output_id": "spore_antidote", "output_qty": 1,
		"rarity": 1, "name": "Spore Antidote",
		"materials": {"spore_dust": 3, "moss_fiber": 2},
		"gold_cost": 14, "station": "alchemy"
	},
	# === UTILITY ===
	# Honest bulk brew: same gold per tonic as the alchemy recipe, traded for a
	# different material mix (hide and wood instead of reed). Never a trap.
	"field_tonic_bundle": {
		"category": "utility", "output_id": "moss_tonic", "output_qty": 3,
		"rarity": 1, "name": "Field Tonic Bundle",
		"materials": {"bramble_wood": 2, "beast_hide": 2, "moss_fiber": 3},
		"gold_cost": 18, "station": "workbench"
	},
	# === EPIC (rarity 3) — needs a rare realm material ===
	"siltcarver_blade": {
		"category": "weapon", "output_id": "siltcarver_blade", "output_qty": 1,
		"rarity": 3, "name": "Siltscale Blade",
		"materials": {"crystal_fragment": 1, "spore_dust": 6, "iron_shard": 5},
		"gold_cost": 130, "station": "forge"
	},
	"cinderbound_maul": {
		"category": "weapon", "output_id": "cinderbound_maul", "output_qty": 1,
		"rarity": 3, "name": "Cinderbound Maul",
		"materials": {"monster_core": 1, "emberstone": 5, "iron_shard": 5},
		"gold_cost": 150, "station": "forge"
	},
	"tideward_staff": {
		"category": "weapon", "output_id": "tideward_staff", "output_qty": 1,
		"rarity": 3, "name": "Tideward Staff",
		"materials": {"moonmoss": 5, "crystal_fragment": 1, "fen_reed": 6},
		"gold_cost": 140, "station": "forge"
	},
	"siltband_cloak_recipe": {
		"category": "armor", "output_id": "siltband_cloak", "output_qty": 1,
		"rarity": 3, "name": "Siltscale Cloak",
		"materials": {"crystal_fragment": 1, "spore_dust": 7, "beast_hide": 4},
		"gold_cost": 120, "station": "forge"
	},
	"cinderplate_recipe": {
		"category": "armor", "output_id": "cinderplate", "output_qty": 1,
		"rarity": 3, "name": "Cinderplate",
		"materials": {"monster_core": 1, "emberstone": 5, "iron_shard": 6},
		"gold_cost": 160, "station": "forge"
	},
	# === LEGENDARY (rarity 4) — rare realm material plus a camp catalyst ===
	"rootbound_cleaver": {
		"category": "weapon", "output_id": "rootbound_cleaver", "output_qty": 1,
		"rarity": 4, "name": "Rootbound Cleaver",
		"materials": {"monster_core": 2, "camp_ember": 1, "bramble_wood": 8, "beast_hide": 5},
		"gold_cost": 260, "station": "forge"
	},
	"moonpact_staff": {
		"category": "weapon", "output_id": "moonpact_staff", "output_qty": 1,
		"rarity": 4, "name": "Moonpact Staff",
		"materials": {"crystal_fragment": 3, "moonmoss": 7, "camp_ember": 1, "fen_reed": 5},
		"gold_cost": 280, "station": "forge"
	},
	"moonsilk_vest_recipe": {
		"category": "armor", "output_id": "moonsilk_vest", "output_qty": 1,
		"rarity": 4, "name": "Moonsilk Vest",
		"materials": {"crystal_fragment": 2, "moonmoss": 6, "camp_ember": 1},
		"gold_cost": 220, "station": "forge"
	},
}

static func get_recipe(recipe_id: String) -> Dictionary:
	return RECIPES.get(recipe_id, {})

static func get_recipes_by_category(category: String) -> Array:
	var result := []
	for id in RECIPES:
		var r: Dictionary = RECIPES[id]
		if r.get("category", "") == category:
			result.append({"id": id, "data": r})
	return result

static func _game_state() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("/root/GameState") if tree != null else null

static func can_craft(recipe_id: String) -> bool:
	var recipe: Dictionary = RECIPES.get(recipe_id, {})
	if recipe.is_empty():
		return false
	var gs := _game_state()
	if gs == null:
		return false
	if int(gs.get("gold")) < int(recipe.get("gold_cost", 0)):
		return false
	for mat_id in recipe.get("materials", {}):
		var needed: int = recipe.materials[mat_id]
		if not bool(gs.call("has_material", mat_id, needed)):
			return false
	return true

static func craft(recipe_id: String) -> Dictionary:
	var recipe: Dictionary = RECIPES.get(recipe_id, {})
	if recipe.is_empty():
		return {"success": false, "message": "Unknown recipe."}
	var gs := _game_state()
	if gs == null:
		return {"success": false, "message": "Game state is unavailable."}
	if not can_craft(recipe_id):
		var missing := get_missing_materials(recipe_id)
		if not missing.is_empty():
			var first: Dictionary = missing[0]
			var display := str(first.id).replace("_", " ").capitalize()
			return {"success": false, "message": "Need %d %s (owned %d)." % [
				int(first.needed), display, int(first.owned)]}
		return {"success": false, "message": "Need %d gold." % int(
			recipe.get("gold_cost", 0))}
	return gs.call("craft_transaction",
		str(recipe.get("category", "")), str(recipe.get("output_id", "")),
		int(recipe.get("output_qty", 1)), str(recipe.get("name", recipe_id)),
		int(recipe.get("rarity", 0)), recipe.get("materials", {}),
		int(recipe.get("gold_cost", 0)))

static func get_missing_materials(recipe_id: String) -> Array:
	var recipe: Dictionary = RECIPES.get(recipe_id, {})
	var missing := []
	var gs := _game_state()
	if gs == null:
		return missing
	for mat_id in recipe.get("materials", {}):
		var needed: int = recipe.materials[mat_id]
		var owned: int = int(gs.call("get_material_qty", mat_id))
		if owned < needed:
			missing.append({"id": mat_id, "needed": needed, "owned": owned})
	return missing

## Recipe ids in a stable, player-facing order (category ladder, then name).
## The UI reads this instead of keeping its own copy, so a new recipe can never
## be craftable in data yet invisible in the satchel.
static func recipe_ids() -> Array[String]:
	var result: Array[String] = []
	var categories: Array[String] = ["weapon", "armor", "potion", "utility"]
	for category in categories:
		var ids: Array[String] = []
		for id in RECIPES:
			if str(RECIPES[id].get("category", "")) == category:
				ids.append(str(id))
		ids.sort()
		result.append_array(ids)
	return result

## What a craft actually hands the player, resolved from the live item defs.
## `name` is the granted item's name (not the recipe's marketing name) so the
## UI can prove the recipe delivers what its card promises.
static func output_preview(recipe_id: String) -> Dictionary:
	var recipe: Dictionary = RECIPES.get(recipe_id, {})
	if recipe.is_empty():
		return {}
	var gs := _game_state()
	if gs == null:
		return {}
	var output_id := str(recipe.get("output_id", ""))
	var category := str(recipe.get("category", ""))
	var qty := maxi(int(recipe.get("output_qty", 1)), 1)
	var result := {"id": output_id, "category": category, "qty": qty,
		"name": str(recipe.get("name", recipe_id)),
		"kind": category, "atk": 0, "defense": 0, "speed_mult": 1.0, "stat_line": ""}
	var definition: Dictionary = {}
	match category:
		"weapon":
			definition = (gs.get("WEAPON_DEFS") as Dictionary).get(output_id, {})
		"armor":
			definition = (gs.get("ARMOR_DEFS") as Dictionary).get(output_id, {})
		_:
			definition = (gs.get("CONSUMABLE_DEFS") as Dictionary).get(output_id, {})
	if definition.is_empty():
		return result
	if category == "weapon":
		result["atk"] = int(definition.get("atk", 0))
		result["stat_line"] = "ATK %d" % int(result["atk"])
	elif category == "armor":
		result["defense"] = int(definition.get("defense", 0))
		result["speed_mult"] = float(definition.get("speed_mult", 1.0))
		result["stat_line"] = "DEF %d · SPEED ×%.2f" % [int(result["defense"]),
			float(result["speed_mult"])]
	else:
		var item_name := str(definition.get("name", output_id)).to_upper()
		result["name"] = item_name if qty <= 1 else "%d× %s" % [qty, item_name]
		var stats_value: Variant = definition.get("stats", [])
		if stats_value is Array and not (stats_value as Array).is_empty():
			result["stat_line"] = str((stats_value as Array)[0])
		else:
			result["stat_line"] = str(definition.get("description", ""))
	return result

## Everything the player is short of, named. `summary` is the single line the
## crafting card shows, so a disabled button never leaves the player guessing
## whether it is materials or gold.
static func requirement_report(recipe_id: String) -> Dictionary:
	var recipe: Dictionary = RECIPES.get(recipe_id, {})
	if recipe.is_empty():
		return {"can_craft": false, "summary": "Unknown recipe.",
			"missing": [], "gold_short": 0}
	var gs := _game_state()
	if gs == null:
		return {"can_craft": false, "summary": "Game state is unavailable.",
			"missing": [], "gold_short": 0}
	var missing := get_missing_materials(recipe_id)
	var gold_short := maxi(int(recipe.get("gold_cost", 0)) - int(gs.get("gold")), 0)
	var parts: Array[String] = []
	for entry in missing:
		var display := str(entry.id).replace("_", " ").capitalize()
		parts.append("%s %d/%d" % [display, int(entry.owned), int(entry.needed)])
	if gold_short > 0:
		parts.append("%d more gold" % gold_short)
	return {"can_craft": missing.is_empty() and gold_short <= 0,
		"summary": "Ready to craft." if parts.is_empty() else "Short: " + ", ".join(parts),
		"missing": missing, "gold_short": gold_short}
