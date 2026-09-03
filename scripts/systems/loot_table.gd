extends RefCounted
class_name LootTable

## Deterministic loot tables for enemies, chests, and bosses.
## Each entry uses weighted random with rarity tiers.

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]

# Drop entry format: { id, chance, qty_min, qty_max, rarity_min, rarity_max }
# gold entry: { gold_min, gold_max }

static func roll_enemy(archetype: String) -> Dictionary:
	var table := _enemy_table(archetype)
	return _roll(table)

static func roll_chest(chest_rarity: int) -> Dictionary:
	var table := _chest_table(chest_rarity)
	return _roll(table)

static func roll_boss(boss_id: String) -> Dictionary:
	var table := _boss_table(boss_id)
	return _roll(table)

static func _roll(table: Dictionary) -> Dictionary:
	var result := {"gold": 0, "materials": [], "gear": null}
	result.gold = randi_range(table.get("gold_min", 3), table.get("gold_max", 9))
	for drop in table.get("drops", []):
		if randf() <= float(drop.get("chance", 0.0)):
			var qty := randi_range(drop.get("qty_min", 1), drop.get("qty_max", 1))
			var mat_id: String = drop.get("id", "")
			if qty > 0 and mat_id != "" and GameState.MATERIAL_DEFS.has(mat_id):
				result.materials.append({"id": mat_id, "qty": qty})
	if table.has("gear"):
		var g: Dictionary = table.gear
		if randf() <= float(g.get("chance", 0.0)):
			var rarity := randi_range(g.get("rarity_min", 1), g.get("rarity_max", 3))
			result.gear = {"rarity": rarity, "kind": g.get("kind", "weapon")}
	return result

static func _apply_drop(drop: Dictionary, result: Dictionary) -> void:
	if randf() <= float(drop.get("chance", 0.0)):
		var qty := randi_range(drop.get("qty_min", 1), drop.get("qty_max", 1))
		var mat_id: String = drop.get("id", "")
		if qty > 0 and mat_id != "" and GameState.MATERIAL_DEFS.has(mat_id):
			result.materials.append({"id": mat_id, "qty": qty})

static func _enemy_table(archetype: String) -> Dictionary:
	match archetype:
		"charger":
			return {
				"gold_min": 5, "gold_max": 12,
				"drops": [
					{"id": "beast_hide", "chance": 0.35, "qty_min": 1, "qty_max": 2},
					{"id": "iron_shard", "chance": 0.20, "qty_min": 1, "qty_max": 1},
				],
				"gear": {"chance": 0.03, "rarity_min": 1, "rarity_max": 2, "kind": "weapon"}
			}
		"ambusher":
			return {
				"gold_min": 4, "gold_max": 10,
				"drops": [
					{"id": "spore_dust", "chance": 0.40, "qty_min": 1, "qty_max": 2},
					{"id": "moss_fiber", "chance": 0.25, "qty_min": 1, "qty_max": 1},
				],
				"gear": {"chance": 0.02, "rarity_min": 1, "rarity_max": 2, "kind": "armor"}
			}
		"elite":
			return {
				"gold_min": 15, "gold_max": 35,
				"drops": [
					{"id": "iron_shard", "chance": 0.60, "qty_min": 1, "qty_max": 3},
					{"id": "crystal_fragment", "chance": 0.25, "qty_min": 1, "qty_max": 1},
					{"id": "monster_core", "chance": 0.15, "qty_min": 1, "qty_max": 1},
				],
				"gear": {"chance": 0.12, "rarity_min": 2, "rarity_max": 4, "kind": "weapon"}
			}
		_:
			return {
				"gold_min": 3, "gold_max": 9,
				"drops": [
					{"id": "moss_fiber", "chance": 0.30, "qty_min": 1, "qty_max": 2},
					{"id": "bramble_wood", "chance": 0.20, "qty_min": 1, "qty_max": 1},
				],
				"gear": {"chance": 0.02, "rarity_min": 1, "rarity_max": 2, "kind": "weapon"}
			}

static func _chest_table(chest_rarity: int) -> Dictionary:
	match chest_rarity:
		1: # Common
			return {
				"gold_min": 18, "gold_max": 40,
				"drops": [
					{"id": "moss_fiber", "chance": 0.50, "qty_min": 1, "qty_max": 3},
					{"id": "bramble_wood", "chance": 0.40, "qty_min": 1, "qty_max": 2},
				],
				"gear": {"chance": 0.08, "rarity_min": 1, "rarity_max": 2, "kind": "weapon"}
			}
		2: # Uncommon
			return {
				"gold_min": 30, "gold_max": 60,
				"drops": [
					{"id": "iron_shard", "chance": 0.50, "qty_min": 1, "qty_max": 3},
					{"id": "fen_reed", "chance": 0.35, "qty_min": 1, "qty_max": 2},
					{"id": "beast_hide", "chance": 0.25, "qty_min": 1, "qty_max": 2},
				],
				"gear": {"chance": 0.15, "rarity_min": 2, "rarity_max": 3, "kind": "weapon"}
			}
		3: # Rare
			return {
				"gold_min": 50, "gold_max": 100,
				"drops": [
					{"id": "emberstone", "chance": 0.45, "qty_min": 1, "qty_max": 3},
					{"id": "moonmoss", "chance": 0.35, "qty_min": 1, "qty_max": 2},
					{"id": "crystal_fragment", "chance": 0.20, "qty_min": 1, "qty_max": 1},
				],
				"gear": {"chance": 0.25, "rarity_min": 3, "rarity_max": 4, "kind": "weapon"}
			}
		4: # Epic
			return {
				"gold_min": 80, "gold_max": 160,
				"drops": [
					{"id": "crystal_fragment", "chance": 0.50, "qty_min": 1, "qty_max": 2},
					{"id": "emberstone", "chance": 0.40, "qty_min": 2, "qty_max": 4},
					{"id": "monster_core", "chance": 0.25, "qty_min": 1, "qty_max": 1},
				],
				"gear": {"chance": 0.35, "rarity_min": 3, "rarity_max": 5, "kind": "weapon"}
			}
		_: # Legendary
			return {
				"gold_min": 120, "gold_max": 250,
				"drops": [
					{"id": "monster_core", "chance": 0.60, "qty_min": 1, "qty_max": 2},
					{"id": "crystal_fragment", "chance": 0.50, "qty_min": 2, "qty_max": 3},
					{"id": "emberstone", "chance": 0.40, "qty_min": 2, "qty_max": 4},
				],
				"gear": {"chance": 0.50, "rarity_min": 4, "rarity_max": 5, "kind": "weapon"}
			}

static func _boss_table(boss_id: String) -> Dictionary:
	match boss_id:
		"thornhide_alpha":
			return {
				"gold_min": 70, "gold_max": 150,
				"drops": [
					{"id": "monster_core", "chance": 1.0, "qty_min": 1, "qty_max": 2},
					{"id": "bramble_wood", "chance": 0.80, "qty_min": 3, "qty_max": 5},
					{"id": "iron_shard", "chance": 0.60, "qty_min": 2, "qty_max": 4},
				],
				"gear": {"chance": 0.40, "rarity_min": 3, "rarity_max": 5, "kind": "weapon"}
			}
		"fenmaw":
			return {
				"gold_min": 80, "gold_max": 160,
				"drops": [
					{"id": "monster_core", "chance": 1.0, "qty_min": 1, "qty_max": 2},
					{"id": "fen_reed", "chance": 0.80, "qty_min": 3, "qty_max": 5},
					{"id": "spore_dust", "chance": 0.60, "qty_min": 2, "qty_max": 4},
				],
				"gear": {"chance": 0.45, "rarity_min": 3, "rarity_max": 5, "kind": "armor"}
			}
		"matriarch":
			return {
				"gold_min": 120, "gold_max": 220,
				"drops": [
					{"id": "monster_core", "chance": 1.0, "qty_min": 2, "qty_max": 3},
					{"id": "crystal_fragment", "chance": 1.0, "qty_min": 2, "qty_max": 4},
					{"id": "moonmoss", "chance": 0.70, "qty_min": 3, "qty_max": 5},
				],
				"gear": {"chance": 0.60, "rarity_min": 4, "rarity_max": 5, "kind": "weapon"}
			}
		_:
			return {
				"gold_min": 50, "gold_max": 120,
				"drops": [
					{"id": "monster_core", "chance": 1.0, "qty_min": 1, "qty_max": 2},
				],
				"gear": {"chance": 0.30, "rarity_min": 3, "rarity_max": 5, "kind": "weapon"}
			}
