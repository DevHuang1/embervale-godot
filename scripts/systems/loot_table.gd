extends RefCounted
class_name LootTable

## === LootTable — Data-Driven Loot Roll System ===
##
## A LootTable describes what a chest, enemy, or boss can drop.
## Each entry carries a weight, a drop definition, and optional conditions.
##
## Drop definition keys (all optional except "type"):
##   type     : "gold" | "xp" | "item" | "weapon" | "armor" | "material" | "relic" | "diamond"
##   id       : item/weapon/armor/material id (from GameState registries)
##   min / max: quantity range (default 1/1)
##   weight   : relative probability weight (default 1.0)
##   rarity   : 0=common 1=uncommon 2=rare 3=epic 4=legendary (default 0)
##   guaranteed: bool — always drops regardless of roll (default false)
##   realm    : String — only drops in this realm (empty = any realm)
##   min_stage: int — quest stage gate (0 = always)
##
## === Preset tables ===
##   LootTable.bramblewood_common()
##   LootTable.bramblewood_elite()
##   LootTable.mistfen_common()
##   LootTable.heartwood_common()
##   LootTable.boss_matriarch()
##   LootTable.chest_common()
##   LootTable.chest_rare()
##   LootTable.chest_boss()
##
## === Usage ===
##   var table := LootTable.chest_rare()
##   var drops := table.roll(realm_id, quest_stage)
##   RewardManager.grant_drops(drops)

const MAX_ROLLS := 8   # safety cap per single roll call

## Entry list — each entry is a Dictionary matching the spec above
var entries : Array[Dictionary] = []
## How many non-guaranteed items to pick per roll (randomised within range)
var rolls_min : int = 1
var rolls_max : int = 3
## Luck multiplier — scales rarity weight bonus (1.0 = default)
var luck : float = 1.0

func add(entry: Dictionary) -> LootTable:
	entries.append(entry)
	return self

func set_rolls(min_r: int, max_r: int) -> LootTable:
	rolls_min = min_r
	rolls_max = max_r
	return self

# ─────────────────────────────────────────────────────────────────────────────
# Roll
# ─────────────────────────────────────────────────────────────────────────────

## Returns an Array of drop Dictionaries (type, id, quantity, rarity).
## realm_id and stage are used to filter entries.
func roll(realm_id: String = "", stage: int = 0) -> Array[Dictionary]:
	var drops : Array[Dictionary] = []

	# Collect guaranteed drops first
	for entry in entries:
		if bool(entry.get("guaranteed", false)):
			if _passes_filter(entry, realm_id, stage):
				drops.append(_resolve(entry))

	# Build eligible pool
	var pool : Array[Dictionary] = []
	for entry in entries:
		if bool(entry.get("guaranteed", false)):
			continue
		if not _passes_filter(entry, realm_id, stage):
			continue
		pool.append(entry)

	# Pick N random entries weighted by weight
	var pick_count := clampi(randi_range(rolls_min, rolls_max), 0, MAX_ROLLS)
	for _i in pick_count:
		var picked := _weighted_pick(pool)
		if picked != null:
			drops.append(_resolve(picked))

	return drops

# ─────────────────────────────────────────────────────────────────────────────
# Internals
# ─────────────────────────────────────────────────────────────────────────────

func _passes_filter(entry: Dictionary, realm_id: String, stage: int) -> bool:
	var req_realm : String = str(entry.get("realm", ""))
	if not req_realm.is_empty() and req_realm != realm_id:
		return false
	var min_stage : int = int(entry.get("min_stage", 0))
	if stage < min_stage:
		return false
	return true

func _weighted_pick(pool: Array[Dictionary]) -> Dictionary:
	if pool.is_empty():
		return {}
	var total := 0.0
	for e in pool:
		var rarity_bonus := float(int(e.get("rarity", 0))) * 0.25 * luck
		total += float(e.get("weight", 1.0)) + rarity_bonus
	var r := randf() * total
	var cumulative := 0.0
	for e in pool:
		var rarity_bonus := float(int(e.get("rarity", 0))) * 0.25 * luck
		cumulative += float(e.get("weight", 1.0)) + rarity_bonus
		if r <= cumulative:
			return e
	return pool[-1]

func _resolve(entry: Dictionary) -> Dictionary:
	var qty_min := int(entry.get("min", 1))
	var qty_max := int(entry.get("max", qty_min))
	return {
		"type":     str(entry.get("type",   "gold")),
		"id":       str(entry.get("id",     "")),
		"quantity": randi_range(qty_min, qty_max),
		"rarity":   int(entry.get("rarity", 0)),
	}

# ─────────────────────────────────────────────────────────────────────────────
# Preset tables
# ─────────────────────────────────────────────────────────────────────────────

static func bramblewood_common() -> LootTable:
	var t := LootTable.new()
	t.set_rolls(1, 2)
	t.add({"type":"gold",     "min":4,  "max":12,  "weight":3.0})
	t.add({"type":"xp",       "min":8,  "max":18,  "weight":2.5})
	t.add({"type":"material", "id":"bramble_wood", "weight":1.8, "realm":"bramblewood"})
	t.add({"type":"material", "id":"moss_fiber",   "weight":1.8, "realm":"bramblewood"})
	t.add({"type":"material", "id":"beast_hide",   "weight":1.2, "realm":"bramblewood"})
	t.add({"type":"item",     "id":"moss_tonic",   "weight":0.8, "rarity":0})
	return t

static func bramblewood_elite() -> LootTable:
	var t := LootTable.new()
	t.set_rolls(2, 3)
	t.add({"type":"gold",     "min":12, "max":28,  "weight":2.5})
	t.add({"type":"xp",       "min":22, "max":40,  "weight":2.0})
	t.add({"type":"material", "id":"iron_shard",   "weight":1.5, "rarity":1, "realm":"bramblewood"})
	t.add({"type":"material", "id":"bramble_wood", "weight":1.2})
	t.add({"type":"item",     "id":"hushling_thorn","weight":0.9,"rarity":1})
	t.add({"type":"item",     "id":"moss_tonic",   "weight":0.6, "rarity":0})
	t.add({"type":"diamond",  "min":1,  "max":2,   "weight":0.3, "rarity":2})
	return t

static func mistfen_common() -> LootTable:
	var t := LootTable.new()
	t.set_rolls(1, 2)
	t.add({"type":"gold",     "min":6,  "max":16,  "weight":2.8})
	t.add({"type":"xp",       "min":12, "max":24,  "weight":2.2})
	t.add({"type":"material", "id":"fen_reed",   "weight":2.0, "realm":"mistfen"})
	t.add({"type":"material", "id":"spore_dust", "weight":1.6, "realm":"mistfen"})
	t.add({"type":"item",     "id":"moss_tonic", "weight":0.9, "rarity":0})
	return t

static func heartwood_common() -> LootTable:
	var t := LootTable.new()
	t.set_rolls(2, 3)
	t.add({"type":"gold",     "min":10, "max":25,  "weight":2.5})
	t.add({"type":"xp",       "min":18, "max":35,  "weight":2.0})
	t.add({"type":"material", "id":"emberstone", "weight":1.8, "rarity":1, "realm":"heartwood"})
	t.add({"type":"material", "id":"monster_core","weight":1.0,"rarity":2, "realm":"heartwood"})
	t.add({"type":"item",     "id":"moss_tonic", "weight":0.7, "rarity":0})
	t.add({"type":"diamond",  "min":1,  "max":2,   "weight":0.5, "rarity":2})
	return t

static func boss_matriarch() -> LootTable:
	var t := LootTable.new()
	t.set_rolls(3, 4)
	t.add({"type":"gold",    "min":80,  "max":150, "weight":1.0, "guaranteed":true})
	t.add({"type":"xp",      "min":350, "max":500, "weight":1.0, "guaranteed":true})
	t.add({"type":"weapon",  "id":"matriarch_scepter", "weight":1.0, "rarity":4, "guaranteed":true})
	t.add({"type":"diamond", "min":4,   "max":6,   "weight":1.0, "rarity":3,  "guaranteed":true})
	t.add({"type":"item",    "id":"hushling_thorn","min":4,"max":8,"weight":2.0,"rarity":1})
	t.add({"type":"item",    "id":"moss_tonic","min":2,"max":3,"weight":1.5,"rarity":0})
	t.add({"type":"material","id":"monster_core","min":2,"max":4,,"weight":1.2,"rarity":2})
	return t

static func chest_common() -> LootTable:
	var t := LootTable.new()
	t.set_rolls(2, 3)
	t.add({"type":"gold",     "min":15, "max":35,  "weight":3.0})
	t.add({"type":"xp",       "min":20, "max":45,  "weight":2.5})
	t.add({"type":"item",     "id":"moss_tonic",   "weight":1.5, "rarity":0})
	t.add({"type":"material", "id":"bramble_wood", "weight":1.2, "realm":"bramblewood"})
	t.add({"type":"material", "id":"fen_reed",     "weight":1.2, "realm":"mistfen"})
	t.add({"type":"material", "id":"emberstone",   "weight":1.0, "rarity":1, "realm":"heartwood"})
	t.add({"type":"diamond",  "min":1,  "max":2,   "weight":0.4, "rarity":2})
	return t

static func chest_rare() -> LootTable:
	var t := LootTable.new()
	t.set_rolls(3, 5)
	t.add({"type":"gold",    "min":50,  "max":120, "weight":2.5})
	t.add({"type":"xp",      "min":60,  "max":120, "weight":2.0})
	t.add({"type":"diamond", "min":2,   "max":5,   "weight":1.5, "rarity":2})
	t.add({"type":"item",    "id":"moss_tonic","min":2,"max":3","weight":1.2,"rarity":0})
	t.add({"type":"material","id":"iron_shard","weight":1.3,"rarity":1})
	t.add({"type":"material","id":"monster_core","weight":0.9,"rarity":2})
	t.add({"type":"material","id":"crystal_fragment","weight":0.6,"rarity":2})
	t.add({"type":"weapon",  "id":"ember_sword",   "weight":0.5, "rarity":2})
	t.add({"type":"weapon",  "id":"arcane_staff",  "weight":0.4, "rarity":2})
	t.add({"type":"armor",   "id":"warden_plate",  "weight":0.5, "rarity":2})
	return t

static func chest_boss() -> LootTable:
	var t := LootTable.new()
	t.set_rolls(4, 6)
	t.add({"type":"gold",    "min":100, "max":220, "weight":1.0, "guaranteed":true})
	t.add({"type":"diamond", "min":3,   "max":8,   "weight":1.0, "rarity":3,  "guaranteed":true})
	t.add({"type":"xp",      "min":150, "max":300, "weight":1.0, "guaranteed":true})
	t.add({"type":"material","id":"monster_core","min":2,"max":4,,"weight":2.0,"rarity":2})
	t.add({"type":"material","id":"crystal_fragment","weight":1.5,"rarity":2})
	t.add({"type":"weapon",  "id":"matriarch_scepter","weight":0.8,"rarity":4})
	t.add({"type":"armor",   "id":"warden_plate",  "weight":0.9, "rarity":2})
	t.add({"type":"item",    "id":"hushling_thorn","min":4,"max":8","weight":1.2,"rarity":1})
	return t

## Build a table for a specific realm and tier (used by RewardManager)
static func for_enemy(realm_id: String, tier: String) -> LootTable:
	match realm_id:
		"mistfen":   return mistfen_common() if tier != "elite" else bramblewood_elite()
		"heartwood": return heartwood_common()
		_:
			return bramblewood_common() if tier == "normal" else bramblewood_elite()
