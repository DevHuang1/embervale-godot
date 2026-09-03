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
		"category": "weapon", "output_id": "mug_mace", "output_qty": 1,
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
	"moonfen_cloak": {
		"category": "armor", "output_id": "emberweave_cloak", "output_qty": 1,
		"rarity": 2, "name": "Moonfen Cloak",
		"materials": {"moonmoss": 4, "moss_fiber": 5, "fen_reed": 2},
		"gold_cost": 35, "station": "forge"
	},
	"spore_wrap": {
		"category": "armor", "output_id": "emberweave_cloak", "output_qty": 1,
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
		"category": "potion", "output_id": "moss_tonic", "output_qty": 1,
		"rarity": 2, "name": "Ember Salve",
		"materials": {"emberstone": 2, "beast_hide": 1, "moss_fiber": 2},
		"gold_cost": 20, "station": "alchemy"
	},
	"moon_draught": {
		"category": "potion", "output_id": "moss_tonic", "output_qty": 1,
		"rarity": 2, "name": "Moon Draught",
		"materials": {"moonmoss": 3, "crystal_fragment": 1},
		"gold_cost": 25, "station": "alchemy"
	},
	"spore_antidote": {
		"category": "potion", "output_id": "moss_tonic", "output_qty": 2,
		"rarity": 1, "name": "Spore Antidote",
		"materials": {"spore_dust": 3, "moss_fiber": 2},
		"gold_cost": 14, "station": "alchemy"
	},
	# === UTILITY ===
	"gathering_satchel": {
		"category": "utility", "output_id": "moss_tonic", "output_qty": 1,
		"rarity": 1, "name": "Gathering Satchel",
		"materials": {"bramble_wood": 2, "beast_hide": 2, "moss_fiber": 3},
		"gold_cost": 18, "station": "workbench"
	},
	"lantern_oil": {
		"category": "utility", "output_id": "moss_tonic", "output_qty": 1,
		"rarity": 1, "name": "Lantern Oil",
		"materials": {"spore_dust": 2, "fen_reed": 2},
		"gold_cost": 10, "station": "workbench"
	},
	"iron_repair_kit": {
		"category": "utility", "output_id": "moss_tonic", "output_qty": 1,
		"rarity": 1, "name": "Iron Repair Kit",
		"materials": {"iron_shard": 3, "beast_hide": 1},
		"gold_cost": 15, "station": "workbench"
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
