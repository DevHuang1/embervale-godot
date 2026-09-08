extends Node

const CONTENT_SCHEMA := preload("res://scripts/systems/content_schema.gd")
const CONTENT_REGISTRY := preload("res://scripts/systems/content_registry.gd")
const CRAFTING_DATA := preload("res://scripts/systems/crafting_data.gd")
const BESTIARY_DATA := preload("res://scripts/systems/bestiary.gd")
const BOSS_REWARD_CATALOG := preload("res://scripts/systems/boss_reward_catalog.gd")
const CLOUD_SYNC_QUEUE := preload("res://scripts/systems/cloud_sync_queue.gd")
const ASSET_INTAKE := preload("res://scripts/systems/asset_intake_catalog.gd")
const LOOT_DATA := preload("res://scripts/systems/loot_table.gd")

## === Embervale Game State (exact port from embervale-rpg) ===

# Quest progression
enum QuestStage { SEEK_SPRITE, CLAIM_SHARD, LIGHT_BEACON, COMPLETE }
enum CombatState { EXPLORING, COMBAT, VICTORY, DEFEATED }
enum ItemKind { CONSUMABLE, RELIC, QUEST }
enum ItemRarity { COMMON, UNCOMMON, RARE }

# === Raw materials: realm-specific gathering resources ===
const MATERIAL_DEFS := {
	"bramble_wood": { "name": "Bramblewood", "realm": "bramblewood", "rarity": 0 },
	"moss_fiber": { "name": "Moss Fiber", "realm": "bramblewood", "rarity": 0 },
	"fen_reed": { "name": "Fen Reed", "realm": "mistfen", "rarity": 0 },
	"emberstone": { "name": "Emberstone", "realm": "heartwood", "rarity": 1 },
	"moonmoss": { "name": "Moonmoss", "realm": "moonfen", "rarity": 1 },
	"iron_shard": { "name": "Iron Shard", "realm": "bramblewood", "rarity": 1 },
	"beast_hide": { "name": "Beast Hide", "realm": "bramblewood", "rarity": 0 },
	"spore_dust": { "name": "Spore Dust", "realm": "mistfen", "rarity": 0 },
	"crystal_fragment": { "name": "Crystal Fragment", "realm": "moonfen", "rarity": 2 },
	"monster_core": { "name": "Monster Core", "realm": "heartwood", "rarity": 2 },
	"camp_ember": { "name": "Camp Ember", "realm": "camp", "rarity": 2 },
}
var raw_materials: Dictionary = {}
var gathered_nodes: Dictionary = {}
var discovered_landmarks: Dictionary = {}

# === Weapon registry: each style drives its own attack animation + FX kit ===
const WEAPON_DEFS := {
	"mug_mace": {
		"id": "mug_mace", "name": "MUG MACE", "glyph": "mace", "style": "blunt",
		"element": "fire",
		"atk": 7, "swing_time":     0.32, "range": 8.2,
		"skills": [
			{"name": "MUG SLAM", "icon": "explosion", "type": "aoe", "cooldown": 2.0, "radius": 13.0, "dmg_mult": 1.5},
			{"name": "EMBER FLIGHT", "icon": "fire", "type": "explosion", "cooldown": 2.5, "radius": 2.6, "dmg_mult": 1.7,
				"desc": "Hurl a cinder that bursts on the marked target."},
			{"name": "SIP OF STRENGTH", "icon": "heal_bloom", "type": "heal_bloom", "cooldown": 4.5, "heal": 14,
				"desc": "Restores warmth in a verdant bloom."}
		]
	},
	"ember_sword": {
		"id": "ember_sword", "name": "EMBERFANG", "glyph": "sword", "style": "slash",
		"atk": 8, "swing_time":     0.26, "range": 8.6,
		"skills": [
			{"name": "CRESCENT CUT", "icon": "strike", "type": "strike", "cooldown": 1.5, "dmg_mult": 2.2,
				"desc": "A heavy crescent slash through the marked target."},
			{"name": "THORN WHIRL", "icon": "whirl", "type": "whirl", "cooldown": 2.5, "radius": 3.6, "dmg_mult": 1.6,
				"desc": "Spin a ring of bramble slashes around you."},
			{"name": "SUNDER DASH", "icon": "dash_strike", "type": "dash_strike", "cooldown": 3.0, "dmg_mult": 1.8,
				"desc": "Dash through the target, blade leading."}
		]
	},
	"arcane_staff": {
		"id": "arcane_staff", "name": "MOONBOUGH", "glyph": "staff", "style": "magic",
		"atk": 6, "swing_time":     0.38, "range": 10.5,
		"skills": [
			{"name": "EMBER NOVA", "icon": "explosion", "type": "explosion", "cooldown": 2.0, "radius": 3.0, "dmg_mult": 1.9,
				"desc": "Detonate an ember burst on the marked target."},
			{"name": "STAR COMET", "icon": "comet", "type": "comet", "cooldown": 4.0, "radius": 4.0, "dmg_mult": 2.8,
				"desc": "Call down a slow comet; a wide explosion follows."},
			{"name": "VERDANT BLOOM", "icon": "heal_bloom", "type": "heal_bloom", "cooldown": 4.5, "heal": 14,
				"desc": "Bloom verdant light, restoring warmth."}
		]
	},
	"matriarch_scepter": {
		"id": "matriarch_scepter", "name": "CROWN OF THE OLD ROOT", "glyph": "staff",
		"style": "magic", "element": "nature", "rarity": 4,
		"atk": 11, "swing_time":     0.42, "range": 11.0,
		"auto_bloom_every": 2, "auto_bloom_bonus": 5,
		"passive_name": "QUEEN'S GERMINATION",
		"passive_desc": "Every second basic strike blooms for +5 damage and applies Nature.",
		"source": "Defeat the Hushling Matriarch",
		"skills": [
			{"name": "THORN LANCE", "icon": "strike", "type": "strike", "cooldown": 1.8,
				"dmg_mult": 2.1, "desc": "Drive a focused thorn through the marked foe."},
			{"name": "BRAMBLE DOMINION", "icon": "nature", "type": "aoe", "cooldown": 6.0,
				"radius": 16.0, "dmg_mult": 1.7,
				"desc": "Command an entangling crown of roots around you."},
			{"name": "VERDANT REPRIEVE", "icon": "heal_bloom", "type": "heal_bloom", "cooldown": 7.0,
				"heal": 18, "desc": "Turn the old root's vigor into restored warmth."}
		]
	},
	"pocket_blade": {"id": "pocket_blade", "name": "POCKET BLADE", "glyph": "blade", "style": "slash", "element": "shadow", "atk": 5, "swing_time": 0.26, "range": 6.4,
		"skills": [
			{"name": "FLASH BANG", "icon": "explosion", "type": "explosion", "cooldown": 6.0, "radius": 4.0, "dmg_mult": 1.5},
			{"name": "QUIET STEP", "icon": "dash_strike", "type": "dash_strike", "cooldown": 3.5, "dmg_mult": 1.4},
			{"name": "SHADOW CUT", "icon": "strike", "type": "strike", "cooldown": 2.0, "dmg_mult": 1.8}
		]},
	"snip_twins": {"id": "snip_twins", "name": "SNIP TWINS", "glyph": "blade", "style": "slash", "element": "shock", "atk": 6, "swing_time": 0.32, "range": 7.2,
		"skills": [
			{"name": "SNIP DASH", "icon": "dash_strike", "type": "dash_strike", "cooldown": 3.5, "dmg_mult": 1.2},
			{"name": "SPLIT ARC", "icon": "whirl", "type": "whirl", "cooldown": 2.8, "radius": 3.2, "dmg_mult": 1.5},
			{"name": "SHEAR LINE", "icon": "strike", "type": "strike", "cooldown": 2.2, "dmg_mult": 1.9}
		]},
	"soda_cannon": {"id": "soda_cannon", "name": "SODA CANNON", "glyph": "potion", "style": "magic", "element": "water", "atk": 6, "swing_time": 0.34, "range": 7.6,
		"skills": [
			{"name": "SODA SPRAY", "icon": "comet", "type": "comet", "cooldown": 2.5, "radius": 3.0, "dmg_mult": 1.6},
			{"name": "FIZZ BURST", "icon": "explosion", "type": "explosion", "cooldown": 3.5, "radius": 3.5, "dmg_mult": 1.8},
			{"name": "COOLING SIP", "icon": "heal_bloom", "type": "heal_bloom", "cooldown": 5.0, "heal": 12}
		]},
	"slab_hammer": {"id": "slab_hammer", "name": "SLAB HAMMER", "glyph": "mace", "style": "blunt", "element": "thunder", "atk": 10, "swing_time": 0.52, "range": 9.2,
		"skills": [
			{"name": "EM PULSE", "icon": "explosion", "type": "heavy_aoe", "cooldown": 7.0, "radius": 6.0, "dmg_mult": 1.8},
			{"name": "GROUND BREAK", "icon": "explosion", "type": "aoe", "cooldown": 4.5, "radius": 4.5, "dmg_mult": 1.7},
			{"name": "IRON RECOVERY", "icon": "heal_bloom", "type": "heal_bloom", "cooldown": 6.0, "heal": 10}
		]},
	"thorn_mace": {"id": "thorn_mace", "name": "THORN MACE", "glyph": "mace", "style": "blunt", "element": "nature", "atk": 9, "swing_time": 0.40, "range": 8.5,
		"skills": [
			{"name": "THORN CRUSH", "icon": "strike", "type": "strike", "cooldown": 2.2, "dmg_mult": 2.0},
			{"name": "ROOT RING", "icon": "nature", "type": "aoe", "cooldown": 4.0, "radius": 4.0, "dmg_mult": 1.6},
			{"name": "BARK BLOOM", "icon": "heal_bloom", "type": "heal_bloom", "cooldown": 5.0, "heal": 14}
		]},
	"iron_axe": {"id": "iron_axe", "name": "IRON AXE", "glyph": "axe", "style": "slash", "element": "fire", "atk": 8, "swing_time": 0.38, "range": 8.4,
		"skills": [
			{"name": "CLEAVING ARC", "icon": "strike", "type": "strike", "cooldown": 2.0, "dmg_mult": 2.0},
			{"name": "AXE WHIRL", "icon": "whirl", "type": "whirl", "cooldown": 3.0, "radius": 3.8, "dmg_mult": 1.7},
			{"name": "HEWING DASH", "icon": "dash_strike", "type": "dash_strike", "cooldown": 3.5, "dmg_mult": 1.8}
		]},
	"grove_spear": {"id": "grove_spear", "name": "GROVE SPEAR", "glyph": "spear", "style": "slash", "element": "nature", "atk": 8, "swing_time": 0.36, "range": 10.0,
		"skills": [
			{"name": "ROOT LANCE", "icon": "strike", "type": "strike", "cooldown": 1.8, "dmg_mult": 2.0},
			{"name": "VINE REACH", "icon": "aoe", "type": "aoe", "cooldown": 3.8, "radius": 3.5, "dmg_mult": 1.5},
			{"name": "PIERCING STEP", "icon": "dash_strike", "type": "dash_strike", "cooldown": 3.0, "dmg_mult": 1.7}
		]},
	"hunter_bow": {"id": "hunter_bow", "name": "HUNTER BOW", "glyph": "bow", "style": "slash", "element": "nature", "atk": 7, "swing_time": 0.42, "range": 12.0,
		"skills": [
			{"name": "MARKED SHOT", "icon": "strike", "type": "strike", "cooldown": 1.8, "dmg_mult": 2.0},
			{"name": "BARRAGE", "icon": "explosion", "type": "explosion", "cooldown": 4.0, "radius": 3.0, "dmg_mult": 1.6},
			{"name": "HUNTER'S STEP", "icon": "dash_strike", "type": "dash_strike", "cooldown": 3.5, "dmg_mult": 1.5}
		]},
	"round_shield": {"id": "round_shield", "name": "ROUND SHIELD", "glyph": "shield", "style": "blunt", "element": "fire", "atk": 5, "swing_time": 0.46, "range": 7.0,
		"skills": [
			{"name": "SHIELD BASH", "icon": "strike", "type": "strike", "cooldown": 2.5, "dmg_mult": 1.8},
			{"name": "WARDING RING", "icon": "aoe", "type": "aoe", "cooldown": 4.5, "radius": 3.5, "dmg_mult": 1.4},
			{"name": "GUARDIAN'S BLOOM", "icon": "heal_bloom", "type": "heal_bloom", "cooldown": 6.0, "heal": 12}
		]}
}

# === Armor registry: defense reduces every hit, tint restyles the body ===
const ARMOR_DEFS := {
	"warden_plate": {
		"id": "warden_plate", "name": "WARDEN PLATE", "glyph": "shield",
		"defense": 3, "speed_mult": 1.0, "price": 60,
		"tint": Color(0.30, 0.33, 0.38), "roughness": 0.5, "metallic": 0.35,
		"desc": "Grove-forged steel. Reduces each hit by 3."
	},
	"emberweave_cloak": {
		"id": "emberweave_cloak", "name": "EMBERWEAVE CLOAK", "glyph": "cloak",
		"defense": 1, "speed_mult": 1.08, "price": 40,
		"tint": Color(0.34, 0.21, 0.12), "roughness": 0.75, "metallic": 0.0,
		"desc": "Warm-woven travel cloak. -1 damage, moves swifter."
	}
}

const SHOP_STOCK := [
	{"id": "ember_sword", "kind": "weapon", "price": 75},
	{"id": "arcane_staff", "kind": "weapon", "price": 90},
	{"id": "warden_plate", "kind": "armor", "price": 60},
	{"id": "emberweave_cloak", "kind": "armor", "price": 40},
	{"id": "moss_tonic", "kind": "potion", "price": 12, "rarity": 0},
]

@export var current_stage: QuestStage = QuestStage.SEEK_SPRITE
@export var combat_state: CombatState = CombatState.EXPLORING
@export var route_checkpoint_id: String = "grove_arrival"
@export var route_respawn_position: Vector2 = Vector2(-16, 10)
var expedition_run_id: int = 0
var activity_recovery: Dictionary = {}
var content_registry_errors: Array[String] = []

func get_content_registry() -> Dictionary:
	var objectives: Dictionary = {}
	for objective in quest_objectives:
		var objective_id := str(objective.get("id", ""))
		if not objective_id.is_empty():
			objectives[objective_id] = objective
	var skills: Dictionary = {}
	for weapon_id in WEAPON_DEFS:
		for slot in (WEAPON_DEFS[weapon_id].get("skills", []) as Array).size():
			var skill: Dictionary = WEAPON_DEFS[weapon_id]["skills"][slot].duplicate(true)
			var skill_id := "%s_skill_%d" % [str(weapon_id), slot]
			skill["id"] = skill_id
			skills[skill_id] = skill
	var quests: Dictionary = {}
	for objective_id in objectives:
		quests[str(objective_id)] = objectives[objective_id].duplicate(true)
	var registry := CONTENT_REGISTRY.snapshot(WEAPON_DEFS, ARMOR_DEFS,
		MATERIAL_DEFS, CRAFTING_DATA.RECIPES, BESTIARY_DATA.REALMS,
		BESTIARY_DATA.BOSS_DEFS, objectives)
	registry["skill"] = skills
	registry["quest"] = quests
	var loot_tables: Dictionary = {}
	for table_id in ["boss_matriarch", "chest_common", "chest_rare", "chest_boss"]:
		var table: LootTable = _catalog_loot_table(str(table_id))
		loot_tables[table_id] = {"id": table_id, "rolls_min": table.rolls_min,
			"rolls_max": table.rolls_max, "entries": table.entries.duplicate(true)}
	registry["loot_table"] = loot_tables
	# Stable semantic records for runtime families that are not owned by the
	# legacy item dictionaries yet. Paths are implementation details; saves only
	# retain these IDs and can receive replacement resources later.
	registry["enemy"] = {
		"hushling": {"id": "hushling", "scene": "res://scenes/entities/hushling.tscn"},
		"spitter": {"id": "spitter", "scene": "res://scenes/entities/spitter.tscn"},
		"thorn_charger": {"id": "thorn_charger", "scene": "res://scenes/entities/thorn_charger.tscn"},
		"fenling": {"id": "fenling", "scene": "res://scenes/entities/moonfen_fenling.tscn"},
		"moonfen_fenling": {"id": "moonfen_fenling", "scene": "res://scenes/entities/moonfen_fenling.tscn"},
		"relic_leech": {"id": "relic_leech", "scene": "res://scenes/entities/relic_leech.tscn"},
	}
	registry["npc"] = {
		"grove_trader": {"id": "grove_trader", "scene": "res://scenes/world/service_npc.tscn", "service": "shop"},
		"grove_craftsman": {"id": "grove_craftsman", "scene": "res://scenes/world/service_npc.tscn", "service": "crafting"},
	}
	registry["mount"] = {
		"grove_elk": {"id": "grove_elk", "source": "res://scripts/systems/ambient_life_field.gd", "status": "planned_replacement_safe"},
	}
	registry["animal"] = {
		"grove_butterfly": {"id": "grove_butterfly", "source": "res://scripts/systems/ambient_life_field.gd", "behavior": "bounded_wander"},
		"grove_firefly": {"id": "grove_firefly", "source": "res://scripts/systems/ambient_life_field.gd", "behavior": "bounded_wander"},
	}
	registry["vfx"] = {
		"combat_hit_burst": {"id": "combat_hit_burst", "source": "res://scripts/systems/combat_fx.gd"},
		"boss_telegraph": {"id": "boss_telegraph", "source": "res://scripts/systems/combat_fx.gd"},
	}
	registry["sfx"] = {
		"realm_ambient_bed": {"id": "realm_ambient_bed", "source": "res://scripts/systems/realm_audio_beds.gd"},
		"combat_impact": {"id": "combat_impact", "source": "res://scripts/autoload/audio_manager.gd"},
	}
	registry["terrain_material"] = {
		"whispergrove_ground": {"id": "whispergrove_ground", "source": "res://scripts/systems/world_ground_composition.gd"},
	}
	var asset_records: Dictionary = CONTENT_REGISTRY.asset_records(AssetIntakeCatalog.ENTRIES)
	for category in asset_records:
		var records: Dictionary = registry.get(category, {})
		records.merge(asset_records[category])
		registry[category] = records
	return registry

func _catalog_loot_table(table_id: String) -> LootTable:
	match table_id:
		"boss_matriarch": return LOOT_DATA.boss_matriarch()
		"chest_common": return LOOT_DATA.chest_common()
		"chest_rare": return LOOT_DATA.chest_rare()
		"chest_boss": return LOOT_DATA.chest_boss()
	return LootTable.new()

# Player stats
@export var hp: int = 100
@export var max_hp: int = 100
@export var level: int = 1
@export var xp: int = 0

# Currencies: gold buys gear at the trader; diamonds buy cosmetics only
@export var gold: int = 30
@export var diamonds: int = 0

# Quest flags
@export var shard_collected: bool = false
@export var beacon_lit: bool = false

# Class
@export var player_class: String = "Cinder Warden"
@export var class_passive: String = "Every third auto-strike blooms with 4 bonus ember damage."

# Skill cooldowns (seconds remaining), keyed "slot_0".."slot_2" per weapon kit
var skill_cooldowns: Dictionary = {}

# === Scan economy & boss customization ===
# Scans are a local currency: 5 free to start, +1 earned per boss defeat,
# hard-capped. Each scan buys one boss customization (idol mesh, palette,
# one realm skill, SFX preset) — everything else stays boss-locked.
const FREE_SCANS := 5
const MAX_SCANS := 9
const SCAN_FRAGMENTS_PER_SCAN := 10
@export var scans_remaining: int = FREE_SCANS
@export var scan_fragments: int = 0
var boss_customs: Dictionary = {}  # boss_id -> payload Dictionary
signal scans_changed(count: int)
signal scan_fragments_changed(fragments: int)
signal application_paused
signal application_resumed

# Equipment
const EQUIPMENT_SLOTS: Array[StringName] = [&"weapon", &"off_hand", &"head", &"chest",
	&"gloves", &"legs", &"boots", &"ring", &"backpack", &"mount"]
var forged_weapons: Array[Dictionary] = []
var equipped_weapon: Dictionary = WEAPON_DEFS["mug_mace"].duplicate(true)
var forged_armors: Array[Dictionary] = []
var equipped_armor: Dictionary = {}
var equipment_slots: Dictionary = {}
var loadout_presets: Dictionary = {}
const MAX_LOADOUT_PRESETS: int = 4
## Informational ownership history; never used for authorization or stats.
var purchase_ledger: Array[Dictionary] = []
var cloud_sync_queue: CloudSyncQueue = CLOUD_SYNC_QUEUE.new()
const ACTIVITY_HISTORY_CAP := 24
var activity_history: Array[String] = []

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		handle_application_paused()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		handle_application_resumed()
	elif what == NOTIFICATION_OS_MEMORY_WARNING:
		handle_low_memory_warning()

func handle_application_paused() -> void:
	## Flush the existing local save so Android process death can recover the
	## queue and progression. This never sends or grants anything remotely.
	save_game()
	application_paused.emit()

func handle_application_resumed() -> void:
	application_resumed.emit()

func handle_low_memory_warning() -> void:
	## Preserve progression first, then ask the existing quality owner to shed
	## presentation cost. No inventory, reward, or combat state is discarded.
	save_game()
	var scaler := get_node_or_null("/root/WorldState/QualityScaler")
	if scaler != null and scaler.has_method("set_mode"):
		scaler.call("set_mode", 0)

# Inventory
var inventory: Array[Dictionary] = [
	{
		"id": "moss_tonic",
		"name": "Moss Tonic",
		"kind": ItemKind.CONSUMABLE,
		"quantity": 1,
		"description": "A cool green draft steeped beneath Whispergrove's root stones.",
		"rarity": ItemRarity.COMMON,
		"stats": ["Restores 12 warmth", "Single-use remedy"],
		"use_label": "Drink",
		"glyph": "potion"
	},
	{
		"id": "hushling_thorn",
		"name": "Hushling Thorn",
		"kind": ItemKind.RELIC,
		"quantity": 0,
		"description": "A cold bramble trophy that whispers near places where shadow gathers.",
		"rarity": ItemRarity.UNCOMMON,
		"stats": ["Resonance +1", "Hushling trophy"],
		"glyph": "nature"
	},
	{
		"id": "ember_shard",
		"name": "Ember Shard",
		"kind": ItemKind.QUEST,
		"quantity": 0,
		"description": "A warm fragment of the old beacon's heart, still bright beneath the ash.",
		"rarity": ItemRarity.RARE,
		"stats": ["Beacon charge +1", "Quest relic"],
		"glyph": "quest"
	}
]

# Loot notification
@export var loot_notice: String = ""
@export var loot_count: int = 0
@export var loot_pulse: int = 0

# Combat
var auto_strike_count: int = 0
var enemy_selected: bool = false
var enemy_target: Node3D = null

# Position
@export var player_position: Vector2 = Vector2(-16, 10)

# Signals
signal hp_changed(old_hp: int, new_hp: int)
signal xp_changed(new_xp: int, new_level: int)
signal stage_changed(new_stage: QuestStage)
signal loot_received(notice: String, count: int)
signal inventory_changed
signal weapon_changed(weapon: Dictionary)
signal armor_changed(armor: Dictionary)
signal equipment_changed(slots: Dictionary)
signal gold_changed(total: int)
signal diamonds_changed(total: int)
signal level_up(new_level: int, points_granted: int)
signal stats_changed
signal cosmetics_changed
signal realm_changed(realm_id: String)
signal skill_cooldown_changed(slot: int, remaining: float)
signal quest_progress(message: String)
signal defeated
signal victory
signal mark_locked(target: Node3D)
signal mark_released
signal materials_changed
signal gathered_nodes_changed
signal upgrade_completed(item_id: String, new_level: int)
signal objective_completed(objective_id: String)
signal route_checkpoint_changed(checkpoint_id: String)

# Constants
const MAX_HP_BASE = 100
const FIRST_KILL_XP = 35
const SUBSEQUENT_KILL_XP = 10
const MOSS_TONIC_HEAL = 12
const PASSIVE_BLOOM_EVERY = 3
const PASSIVE_BLOOM_BONUS = 4
const LEVEL_2_ATK_BONUS = 3

func _get_default_weapon() -> Dictionary:
	return WEAPON_DEFS["mug_mace"].duplicate(true)

func _ready() -> void:
	reset()
	_validate_content_registry_at_startup()

func _validate_content_registry_at_startup() -> void:
	## Keep boot backward-compatible: report malformed content, but do not
	## discard a player's save or make a recoverable content issue a crash.
	content_registry_errors = CONTENT_REGISTRY.validate(get_content_registry())
	if not content_registry_errors.is_empty():
		push_error("Content registry startup validation failed: %s" % "; ".join(content_registry_errors))

func get_content_registry_errors() -> Array[String]:
	return content_registry_errors.duplicate()

func _process(delta: float) -> void:
	# Skill cooldowns recover in real time
	update_skill_cooldowns(delta)

func reset() -> void:
	var camp := get_node_or_null("/root/CampProgression")
	if camp != null and camp.has_method("reset"):
		camp.reset()
	var world_state := get_node_or_null("/root/WorldState")
	if world_state != null:
		world_state.set("weather_locked", false)
	hp = MAX_HP_BASE
	max_hp = MAX_HP_BASE
	level = 1
	xp = 0
	gold = 30
	expedition_run_id = 0
	activity_recovery = {}
	diamonds = 0
	stat_points = 0
	stat_str = 0
	stat_dex = 0
	stat_vit = 0
	stat_luk = 0
	stat_end = 0
	max_hp = max_hp_total()
	current_realm = "bramblewood"
	unlocked_realms = ["bramblewood", "mistfen", "heartwood"]
	cosmetics_owned = []
	active_sfx_profile = "vanilla"
	active_trail_color = "ffb84d"
	active_aura_color = "00000000"
	boss_first_kills = {}
	quest_reward_claims = {}
	opened_chests = {}
	active_cosmetic_ids = {}
	raw_materials = {}
	gathered_nodes = {}
	discovered_landmarks = {}
	quest_objectives = []
	pinned_objective_id = ""
	completed_quizzes = {}
	activity_history.clear()
	onboarding_completed = false
	onboarding_step = 0
	current_stage = QuestStage.SEEK_SPRITE
	route_checkpoint_id = "grove_arrival"
	route_respawn_position = Vector2(-16, 10)
	combat_state = CombatState.EXPLORING
	shard_collected = false
	beacon_lit = false
	auto_strike_count = 0
	enemy_selected = false
	enemy_target = null
	player_position = Vector2(-16, 10)
	
	forged_weapons.clear()
	equipped_weapon = _get_default_weapon()
	forged_armors.clear()
	equipped_armor = {}
	equipment_slots = _empty_equipment_slots()
	_refresh_skill_slots()

	# Reset inventory quantities only
	for item in inventory:
		if item.id == "moss_tonic":
			item.quantity = 1
		else:
			item.quantity = 0

	scans_remaining = FREE_SCANS
	scan_fragments = 0
	boss_customs = {}
	boss_reward_selections = {}
	purchase_ledger.clear()
	cloud_sync_queue.restore([])
	
	loot_notice = ""
	loot_count = 0
	loot_pulse =  0
	
	var sm := get_node_or_null("/root/StoryManager")
	if sm != null and sm.has_method("reset_payload"):
		sm.reset_payload()
	
	hp_changed.emit(0, hp)
	xp_changed.emit(xp, level)
	stage_changed.emit(current_stage)
	weapon_changed.emit(equipped_weapon)
	armor_changed.emit(equipped_armor)
	gold_changed.emit(gold)

# === Quest ===
func advance_stage(new_stage: QuestStage) -> void:
	current_stage = new_stage
	# Story progression supersedes any prior activity attempt; clear the
	# recovery banner in the same save as the new checkpoint/objectives.
	activity_recovery = {}
	set_route_checkpoint_for_stage(new_stage, false)
	quest_objectives = quest_objectives.filter(func(objective: Dictionary) -> bool:
		return not str(objective.get("id", "")).begins_with("chapter"))
	_seed_stage_objectives(new_stage)
	stage_changed.emit(new_stage)
	save_game()
	
	match new_stage:
		QuestStage.CLAIM_SHARD:
			quest_progress.emit("The Ember Shard is warm in your palm. The beacon answers from the ridge.")
		QuestStage.LIGHT_BEACON:
			quest_progress.emit("The grove remembers the way home.")
		QuestStage.COMPLETE:
			quest_progress.emit("The old road will hold its warmth until the next traveler comes through.")
		_:
			quest_progress.emit(get_quest_instruction(new_stage))

func _checkpoint_for_stage(stage: QuestStage) -> String:
	match stage:
		QuestStage.SEEK_SPRITE: return "grove_arrival"
		QuestStage.CLAIM_SHARD: return "hushling_cleared"
		QuestStage.LIGHT_BEACON: return "shard_claimed"
		QuestStage.COMPLETE: return "beacon_relit"
		_: return "grove_arrival"

## Save-safe route marker. Repeating the same marker is a no-op and never
## grants currency, advances a quest, or emits duplicate progress.
func set_route_checkpoint(checkpoint_id: String, persist: bool = true) -> bool:
	var normalized := checkpoint_id.strip_edges().to_lower()
	if normalized.is_empty() or normalized == route_checkpoint_id:
		return false
	route_checkpoint_id = normalized
	route_checkpoint_changed.emit(route_checkpoint_id)
	if persist:
		save_game()
	return true

func _respawn_for_checkpoint(checkpoint_id: String) -> Vector2:
	match checkpoint_id:
		"hushling_cleared": return Vector2(-5, -5)
		"shard_claimed": return Vector2(7, -4)
		"beacon_relit": return Vector2(5, -8)
		"camp_route": return Vector2(-3, 13)
		_: return Vector2(-16, 10)

func set_route_checkpoint_for_stage(stage: QuestStage, persist: bool = true) -> bool:
	var checkpoint := _checkpoint_for_stage(stage)
	var changed := set_route_checkpoint(checkpoint, false)
	var respawn := _respawn_for_checkpoint(checkpoint)
	if route_respawn_position != respawn:
		route_respawn_position = respawn
		changed = true
	if changed and persist:
		save_game()
	return changed

func set_route_checkpoint_for_shortcut(shortcut_id: String, persist: bool = true) -> bool:
	if shortcut_id != "camp_route":
		return false
	var changed := set_route_checkpoint(shortcut_id, false)
	var respawn := _respawn_for_checkpoint(shortcut_id)
	if route_respawn_position != respawn:
		route_respawn_position = respawn
		changed = true
	if changed and persist:
		save_game()
	return changed

func get_quest_instruction(stage: QuestStage) -> String:
	if stage == QuestStage.SEEK_SPRITE: return "Follow the pale path until the bramble sprite stirs."
	if stage == QuestStage.CLAIM_SHARD: return "The light it dropped is close. Gather it before the mist takes it."
	if stage == QuestStage.LIGHT_BEACON: return "Carry the Ember Shard to the ruined altar in the north-east grove."
	if stage == QuestStage.COMPLETE: return "The old road will hold its warmth until the next traveler comes through."
	return "Unknown quest stage"

## Stable player-facing route contract used by HUD and world guidance.
func route_objective_snapshot() -> Dictionary:
	var copy: Dictionary = get_quest_copy(current_stage)
	return {
		"stage": int(current_stage),
		"realm": current_realm,
		"checkpoint": route_checkpoint_id,
		"title": str(copy.get("title", "Current objective")),
		"instruction": str(copy.get("instruction", get_quest_instruction(current_stage))),
		"why": str(copy.get("why", "Advance along the route.")),
		"next_action": str(copy.get("next_action", "Continue forward.")),
		"objectives": get_active_objectives(),
	}

func get_quest_copy(stage: QuestStage) -> Dictionary:
	if stage == QuestStage.SEEK_SPRITE: return {"chapter": "I. The Quiet Grove", "title": "Find the Hushling", "instruction": "Follow the pale path until the bramble sprite stirs.", "why": "Learn the grove's living trail.", "risk": "One readable foe blocks the path.", "reward": "First material cache and the Ember Shard trail.", "next_action": "Follow the pale path."}
	if stage == QuestStage.CLAIM_SHARD: return {"chapter": "II. A Warm Fragment", "title": "Claim the Ember Shard", "instruction": "The light it dropped is close. Gather it before the mist takes it.", "why": "Turn the first victory into lasting power.", "risk": "The shard route crosses gathering pressure.", "reward": "A forge-ready Ember Shard.", "next_action": "Gather the marked shard."}
	if stage == QuestStage.LIGHT_BEACON: return {"chapter": "III. The Way Back", "title": "Restore the Beacon", "instruction": "Carry the Ember Shard to the ruined altar in the north-east grove.", "why": "Relight the road for the next expedition.", "risk": "An elite guards the approach.", "reward": "Beacon checkpoint and a new realm path.", "next_action": "Reach the ruined altar."}
	if stage == QuestStage.COMPLETE: return {"chapter": "IV. A Path Relit", "title": "The Grove Remembers", "instruction": "The old road will hold its warmth until the next traveler comes through.", "why": "Prepare a stronger build for future realms.", "risk": "Future expeditions add elemental pressure.", "reward": "Moonfen access and long-term mastery.", "next_action": "Open the expedition journal."}
	return {"chapter": "", "title": "", "instruction": ""}

func _seed_stage_objectives(stage: QuestStage) -> void:
	match stage:
		QuestStage.SEEK_SPRITE:
			add_objective("chapter1_hushling", "Defeat the Hushling", "kill", 1)
			add_objective("chapter1_gather", "Gather Bramblewood", "gather", 2)
		QuestStage.CLAIM_SHARD:
			add_objective("chapter2_gather", "Gather an Ember Shard", "gather", 1)
			add_objective("chapter2_craft", "Craft your first upgrade", "craft", 1)
		QuestStage.LIGHT_BEACON:
			add_objective("chapter3_beacon", "Light the old beacon", "reach", 1)
			add_objective("chapter3_elite", "Defeat the expedition elite", "kill", 1)
		QuestStage.COMPLETE:
			add_objective("chapter4_expedition", "Prepare for the next expedition", "upgrade", 1)

# === Quest Objectives ===
var quest_objectives: Array[Dictionary] = []
var pinned_objective_id: String = ""
var completed_quizzes: Dictionary = {}
const OBJECTIVE_TYPES := ["kill", "gather", "reach", "craft", "equip", "upgrade", "open_chest"]

func add_objective(id: String, description: String, type: String = "kill", target_qty: int = 1) -> void:
	if id.is_empty() or type not in OBJECTIVE_TYPES:
		return
	for obj in quest_objectives:
		if obj.get("id", "") == id:
			return
	quest_objectives.append({
		"id": id, "description": description, "type": type,
		"target_qty": target_qty, "current_qty": 0, "completed": false
	})
	inventory_changed.emit()
	save_game()

func update_objective(type: String, item_id: String = "", qty: int = 1,
		persist: bool = true) -> void:
	var sm := get_node_or_null("/root/StoryManager")
	if sm != null and sm.has_method("notify_objective"):
		sm.notify_objective(type, item_id, qty)
	var changed := false
	for obj in quest_objectives:
		if obj.get("type", "") == type and not obj.completed:
			if item_id == "" or obj.get("id", "").contains(item_id):
				obj.current_qty = mini(int(obj.get("current_qty", 0)) + qty, int(obj.get("target_qty", 1)))
				changed = true
			if obj.current_qty >= int(obj.get("target_qty", 1)):
				obj.completed = true
				if str(obj.get("id", "")) == pinned_objective_id:
					pinned_objective_id = ""
					objective_completed.emit(obj.id)
					quest_progress.emit("Objective complete: %s" % obj.description)
	inventory_changed.emit()
	if changed and persist:
		save_game()

func get_active_objectives() -> Array:
	var active := []
	for obj in quest_objectives:
		if not obj.get("completed", false):
			active.append(obj)
	return active

func pin_objective(objective_id: String) -> bool:
	for obj in quest_objectives:
		if str(obj.get("id", "")) == objective_id and not bool(obj.get("completed", false)):
			pinned_objective_id = objective_id
			save_game()
			return true
	return false

func unpin_objective(objective_id: String = "") -> bool:
	if pinned_objective_id.is_empty():
		return false
	if not objective_id.is_empty() and pinned_objective_id != objective_id:
		return false
	pinned_objective_id = ""
	save_game()
	return true

func get_pinned_objective() -> Dictionary:
	for obj in quest_objectives:
		if str(obj.get("id", "")) == pinned_objective_id and not bool(obj.get("completed", false)):
			return obj.duplicate(true)
	return {}

func clear_completed_objectives() -> void:
	quest_objectives = quest_objectives.filter(func(o): return not o.get("completed", false))
	if get_pinned_objective().is_empty():
		pinned_objective_id = ""
	save_game()

func begin_activity(activity_id: String, checkpoint_id: String = "") -> bool:
	var normalized := activity_id.strip_edges().to_lower()
	if normalized.is_empty():
		return false
	activity_recovery = {"activity_id": normalized, "status": "active",
		"checkpoint_id": checkpoint_id.strip_edges().to_lower(),
		"attempts": int(activity_recovery.get("attempts", 0)) + 1}
	save_game()
	return true

func abandon_activity() -> bool:
	if activity_recovery.is_empty() or str(activity_recovery.get("status", "")) != "active":
		return false
	activity_recovery["status"] = "abandoned"
	activity_recovery["next_action"] = "Return to the last checkpoint and begin again."
	save_game()
	return true

func fail_activity(reason: String = "The activity was interrupted.") -> bool:
	if activity_recovery.is_empty() or str(activity_recovery.get("status", "")) != "active":
		return false
	activity_recovery["status"] = "failed"
	activity_recovery["reason"] = reason.strip_edges()
	activity_recovery["next_action"] = "Retry from the recorded checkpoint; earned quest credit remains safe."
	save_game()
	return true

func get_activity_recovery() -> Dictionary:
	return activity_recovery.duplicate(true)

func clear_activity_recovery() -> void:
	activity_recovery = {}
	save_game()

# === Expedition Rewards ===
func complete_expedition(realm_id: String) -> Dictionary:
	expedition_run_id += 1
	var gold_reward := randi_range(70, 150)
	var xp_reward := randi_range(80, 150)
	add_gold(gold_reward, " +%d gold from expedition." % gold_reward)
	grant_xp(xp_reward)
	var mat_bonus := ["moss_fiber", "bramble_wood", "iron_shard", "beast_hide"]
	var material_rewards: Dictionary = {}
	for mat_id in mat_bonus:
		var qty := randi_range(1, 3)
		add_material(mat_id, qty)
		material_rewards[mat_id] = qty
	cloud_sync_queue.enqueue("expedition-reward-%d" % expedition_run_id,
		"complete_expedition", {"realm_id": realm_id, "run_id": expedition_run_id,
			"gold": gold_reward, "xp": xp_reward, "materials": material_rewards})
	quest_progress.emit("Expedition complete — %d gold, %d XP earned." % [gold_reward, xp_reward])
	clear_activity_recovery()
	return {"gold": gold_reward, "xp": xp_reward}

# === Onboarding ===
var onboarding_completed: bool = false
var onboarding_step: int = 0

const ONBOARDING_STEPS := [
	{"id": "move", "hint": "Follow the pale path through the welcome arch", "trigger": "movement", "signal": "landmark", "blocking": false},
	{"id": "attack", "hint": "The Hushling stirs. Tap it or press Attack to mark and strike", "trigger": "combat", "signal": "enemy_reveal", "blocking": false},
	{"id": "dodge", "hint": "Read the red telegraph, then use Dodge as it closes", "trigger": "dodge", "signal": "telegraph", "blocking": false},
	{"id": "pickup", "hint": "Claim the warm reward left by the defeated foe", "trigger": "loot", "signal": "reward_drop", "blocking": false},
	{"id": "gather", "hint": "Hold at the glowing resource node until the ritual completes", "trigger": "gather", "signal": "gather_node", "blocking": false},
	{"id": "craft", "hint": "The forge is ready. Compare the preview and craft your first upgrade", "trigger": "craft", "signal": "forge_preview", "blocking": false},
]

func get_onboarding_hint() -> String:
	if onboarding_completed or onboarding_step >= ONBOARDING_STEPS.size():
		return ""
	return str(ONBOARDING_STEPS[onboarding_step].get("hint", ""))

## World-facing teaching contract. UI may surface the hint, but the signal names
## keep each lesson anchored to a landmark, prop, enemy action, or reward.
func get_onboarding_teaching_signal() -> String:
	if onboarding_completed or onboarding_step >= ONBOARDING_STEPS.size():
		return ""
	return str(ONBOARDING_STEPS[onboarding_step].get("signal", ""))

func advance_onboarding() -> String:
	if onboarding_completed:
		return ""
	if onboarding_step >= ONBOARDING_STEPS.size():
		onboarding_completed = true
		save_game()
		return ""
	onboarding_step += 1
	if onboarding_step >= ONBOARDING_STEPS.size():
		onboarding_completed = true
	save_game()
	return get_onboarding_hint()

func check_onboarding_trigger(trigger: String) -> String:
	if onboarding_completed:
		return ""
	if onboarding_step < ONBOARDING_STEPS.size():
		var step: Dictionary = ONBOARDING_STEPS[onboarding_step]
		if step.get("trigger", "") == trigger:
			var next_hint := advance_onboarding()
			quest_progress.emit("Trail basics complete." if next_hint.is_empty()
				else "Next: %s" % next_hint)
			return next_hint
	return ""

# === Combat ===
func engage_enemy(enemy: Node3D) -> bool:
	if combat_state != CombatState.EXPLORING:
		return false

	enemy_target = enemy
	enemy_selected = true
	combat_state = CombatState.COMBAT
	quest_progress.emit("Target marked. Closing the distance with lantern raised.")
	mark_locked.emit(enemy)
	return true

func disengage_enemy() -> void:
	if enemy_target == null and combat_state != CombatState.COMBAT:
		return
	enemy_target = null
	enemy_selected = false
	if combat_state == CombatState.COMBAT:
		combat_state = CombatState.EXPLORING
	mark_released.emit()

func can_auto_strike() -> bool:
	return combat_state == CombatState.COMBAT and enemy_selected and enemy_target != null and is_instance_valid(enemy_target)

func perform_auto_strike() -> Dictionary:
	if not can_auto_strike():
		return {}
	
	auto_strike_count += 1
	var bloom_every := maxi(1, int(equipped_weapon.get(
		"auto_bloom_every", PASSIVE_BLOOM_EVERY)))
	var bloom_bonus := int(equipped_weapon.get(
		"auto_bloom_bonus", PASSIVE_BLOOM_BONUS))
	var is_bloom := auto_strike_count % bloom_every == 0
	var base_damage = get_base_auto_damage()
	var damage = base_damage + (bloom_bonus if is_bloom else 0)
	
	var hit_time = 0.52 if is_bloom else 0.4
	var enemy_hit_time = 0.42 if is_bloom else 0.3
	var bloom_name := str(equipped_weapon.get("passive_name", "EMBER CIRCUIT"))
	
	return {
		"damage": damage,
		"is_bloom": is_bloom,
		"hit_time": hit_time,
		"enemy_hit_time": enemy_hit_time,
		"log": "%s blooms: strike %d lands for %d." % [
			bloom_name.capitalize(), bloom_every, damage] if is_bloom \
			else "Your lantern-sabre strikes automatically for %d." % damage
	}

func get_base_auto_damage() -> int:
	var weapon_atk := int(equipped_weapon.get("atk", 8))
	return (LEVEL_2_ATK_BONUS if level >= 2 else 0) + weapon_atk \
		+ attack_damage_bonus()

## DEPRECATED: enemies no longer retaliate through GameState. A struck enemy
## now answers with its own telegraphed counter-strike — see
## Hushling._begin_counter_windup / Hero.notify_enemy_strike. Kept as an
## inert stub for save-compat with older callers/tests.
func apply_enemy_retaliation() -> Dictionary:
	return {}

func take_damage(amount: int) -> bool:
	var old_hp = hp
	hp = max(0, hp - armor_adjusted_damage(amount))
	hp_changed.emit(old_hp, hp)
	
	if hp <= 0:
		combat_state = CombatState.DEFEATED
		disengage_enemy()
		save_game()
		defeated.emit()
		return true
	save_game()
	return false

func heal(amount: int) -> int:
	var old_hp = hp
	var actual_heal = min(amount, max_hp - hp)
	hp = min(max_hp, hp + amount)
	hp_changed.emit(old_hp, hp)
	if actual_heal > 0:
		save_game()
	return actual_heal

# === Weapon kits & skill slots ===
func _refresh_skill_slots() -> void:
	# Cooldown keys follow the equipped weapon's skill kit
	var next := {}
	var skills: Array = equipped_weapon.get("skills", [])
	for i in skills.size():
		next["slot_%d" % i] = float(skill_cooldowns.get("slot_%d" % i, 0.0))
	skill_cooldowns = next

func get_skill(slot: int) -> Dictionary:
	var skills: Array = equipped_weapon.get("skills", [])
	if slot < 0 or slot >= skills.size():
		return {}
	return skills[slot]

func can_use_skill_slot(slot: int) -> bool:
	return float(skill_cooldowns.get("slot_%d" % slot, 0.0)) <= 0.0 \
		and not get_skill(slot).is_empty()

func use_skill(slot: int) -> Dictionary:
	var sk := get_skill(slot)
	if sk.is_empty():
		return {"success": false, "message": "No rite is bound to that slot."}
	var key := "slot_%d" % slot
	if float(skill_cooldowns.get(key, 0.0)) > 0.0:
		return {"success": false,
			"message": "%s gathers still (%ds)." % [sk.name, int(ceil(skill_cooldowns[key]))]}
	var needs_target: bool = sk.get("type", "") != "heal_bloom"
	if needs_target and (combat_state != CombatState.COMBAT
			or enemy_target == null or not is_instance_valid(enemy_target)):
		return {"success": false,
			"message": "Your lantern lights no foe yet — tap an enemy to mark it."}
	
	# Deliberate combat pacing: cooldowns are longer without changing damage.
	skill_cooldowns[key] = float(sk.cooldown) * 1.20
	skill_cooldown_changed.emit(slot, skill_cooldowns[key])
	return {"success": true, "slot": slot, "skill": sk}

func update_skill_cooldowns(delta: float) -> void:
	for key in skill_cooldowns:
		var old: float = skill_cooldowns[key]
		skill_cooldowns[key] = maxf(0.0, old - delta)
		if old > 0.0 and skill_cooldowns[key] <= 0.0:
			skill_cooldown_changed.emit(int(key.get_slice("_", 1)), 0.0)

func get_slot_cooldown_text(slot: int) -> String:
	var cd := float(skill_cooldowns.get("slot_%d" % slot, 0.0))
	return "%ds" % ceil(cd) if cd > 0.0 else "READY"

# === Armor ===
func armor_defense() -> int:
	return int(equipped_armor.get("defense", 0))

func armor_speed_mult() -> float:
	return float(equipped_armor.get("speed_mult", 1.0))

func armor_adjusted_damage(amount: int) -> int:
	return maxi(1, amount - armor_defense() - defense_stat())

func _empty_equipment_slots() -> Dictionary:
	var slots: Dictionary = {}
	for slot in EQUIPMENT_SLOTS:
		slots[slot] = {}
	return slots

func get_equipment_for_slot(slot: StringName) -> Dictionary:
	if slot == &"weapon":
		return equipped_weapon.duplicate(true)
	if slot == &"chest":
		return equipped_armor.duplicate(true)
	return (equipment_slots.get(slot, {}) as Dictionary).duplicate(true)

func can_equip_item(item: Dictionary, slot: StringName) -> bool:
	if item.is_empty() or slot not in EQUIPMENT_SLOTS:
		return false
	var kind := str(item.get("kind", ""))
	if slot == &"weapon":
		return kind == "" or kind == "weapon"
	if slot == &"chest":
		return kind == "" or kind == "armor"
	return str(item.get("equipment_slot", "")) == str(slot)

func equip_item_to_slot(item_id: String, slot: StringName) -> bool:
	if slot == &"weapon":
		return equip_weapon_by_id(item_id)
	if slot == &"chest":
		equip_armor(item_id)
		return str(equipped_armor.get("id", "")) == item_id
	return false

func unequip_slot(slot: StringName) -> Dictionary:
	var previous := get_equipment_for_slot(slot)
	if slot == &"weapon":
		return previous
	if slot == &"chest":
		equipped_armor = {}
		armor_changed.emit(equipped_armor)
	else:
		equipment_slots[slot] = {}
	equipment_changed.emit(equipment_slots.duplicate(true))
	save_game()
	return previous

func equip_armor(armor_id: String) -> void:
	if armor_id.is_empty():
		equipped_armor = {}
	else:
		var found := {}
		for armor in forged_armors:
			if armor.get("id", "") == armor_id:
				found = armor
				break
		equipped_armor = found.duplicate(true)
	equipment_slots[&"chest"] = equipped_armor.duplicate(true)
	armor_changed.emit(equipped_armor)
	equipment_changed.emit(equipment_slots.duplicate(true))
	if not equipped_armor.is_empty():
		check_onboarding_trigger("equip")
	save_game()

func save_loadout_preset(slot: int) -> bool:
	if slot < 0 or slot >= MAX_LOADOUT_PRESETS or equipped_weapon.is_empty():
		return false
	loadout_presets[str(slot)] = {"weapon_id": str(equipped_weapon.get("id", "")),
		"armor_id": str(equipped_armor.get("id", ""))}
	save_game()
	return true

func apply_loadout_preset(slot: int) -> bool:
	var preset: Dictionary = loadout_presets.get(str(slot), {})
	var weapon_id := str(preset.get("weapon_id", ""))
	if preset.is_empty() or weapon_id.is_empty():
		return false
	var applied := equip_weapon_by_id(weapon_id)
	if not applied and WEAPON_DEFS.has(weapon_id):
		equipped_weapon = (WEAPON_DEFS[weapon_id] as Dictionary).duplicate(true)
		_refresh_skill_slots()
		weapon_changed.emit(equipped_weapon)
		applied = true
	if not applied:
		return false
	equip_armor(str(preset.get("armor_id", "")))
	return true

func add_armor(armor: Dictionary, equip_if_none: bool = true) -> void:
	if not armor.has("id"):
		return
	var stored := armor.duplicate(true)
	for i in forged_armors.size():
		if forged_armors[i].get("id", "") == stored.id:
			forged_armors[i] = stored
			break
	if not forged_armors.any(func(item): return item.get("id", "") == stored.id):
		forged_armors.append(stored)
	inventory_changed.emit()
	if equip_if_none and equipped_armor.is_empty():
		equip_armor(stored.id)
	save_game()

# === Currency & shop ===
func record_activity(entry: String) -> void:
	var clean := entry.strip_edges()
	if clean.is_empty():
		return
	activity_history.push_front(clean)
	while activity_history.size() > ACTIVITY_HISTORY_CAP:
		activity_history.pop_back()

func get_activity_history() -> Array[String]:
	return activity_history.duplicate()

func add_gold(amount: int, notice: String = "") -> void:
	gold += amount
	gold_changed.emit(gold)
	record_activity("GOLD %s%d" % ["+" if amount >= 0 else "", amount])
	if notice:
		loot_notice = notice
		loot_count = amount
		loot_pulse += 1
		loot_received.emit(notice, amount)
	save_game()

## Diamonds buy cosmetics only — never stats. Rare by design.
func add_diamonds(amount: int, notice: String = "") -> void:
	diamonds += amount
	diamonds_changed.emit(diamonds)
	record_activity("DIAMONDS %s%d" % ["+" if amount >= 0 else "", amount])
	if notice != "":
		quest_progress.emit(notice)
	save_game()

func spend_diamonds(amount: int) -> bool:
	if diamonds < amount:
		return false
	diamonds -= amount
	diamonds_changed.emit(diamonds)
	record_activity("DIAMONDS -%d" % amount)
	save_game()
	return true

# === Progression: stats, XP curve, level-ups ===
# Five allocatable stats; every point is a real, readable power choice.
@export var stat_points: int = 0
@export var stat_str: int = 0   # +1 attack damage per point
@export var stat_dex: int = 0   # +3% attack speed, +2% move speed per point
@export var stat_vit: int = 0   # +3 max HP per point
@export var stat_luk: int = 0   # +1% crit chance, +2% crit damage per point
@export var stat_end: int = 0   # +1 defense per point

const XP_TABLE := {
	1: 0, 2: 50, 3: 120, 4: 210, 5: 330,
	6: 480, 7: 660, 8: 880, 9: 1140, 10: 1450,
}

const STAT_PRESETS: Dictionary = {
	"vanguard": {"label": "VANGUARD", "focus": "STR + END", "summary": "Close-range damage with dependable defenses.", "weights": {"str": 2, "end": 2, "vit": 1}},
	"skirmisher": {"label": "SKIRMISHER", "focus": "DEX + LUK", "summary": "Fast attacks, repositioning, and critical strikes.", "weights": {"dex": 2, "luk": 2, "vit": 1}},
	"warden": {"label": "WARDEN", "focus": "VIT + END", "summary": "Durability and recovery for learning difficult fights.", "weights": {"vit": 2, "end": 2, "str": 1}},
	"arcanist": {"label": "ARCANIST", "focus": "DEX + LUK", "summary": "Tempo and critical scaling for magic loadouts.", "weights": {"dex": 2, "luk": 2, "vit": 1}},
}

static func stat_preset(preset_id: String) -> Dictionary:
	return (STAT_PRESETS.get(preset_id.strip_edges().to_lower(), {}) as Dictionary).duplicate(true)

static func project_stat_preset(preset_id: String, points: int) -> Dictionary:
	var preset := stat_preset(preset_id)
	var weights: Dictionary = preset.get("weights", {})
	var total_weight := 0
	for weight in weights.values():
		total_weight += maxi(0, int(weight))
	var projection: Dictionary = {}
	if total_weight <= 0:
		return projection
	for key in weights:
		projection[str(key)] = int(floor(float(maxi(points, 0) * int(weights[key])) / total_weight))
	return projection

## Cumulative XP required to BE `target_level`.
func xp_to_level(target_level: int) -> int:
	if target_level <= 1:
		return 0
	if XP_TABLE.has(target_level):
		return int(XP_TABLE[target_level])
	var l := float(target_level)
	return int(1450.0 + (l - 10.0) * 200.0 * (l - 9.0) * 0.5)

func xp_to_next() -> int:
	return xp_to_level(level + 1)

func grant_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next():
		_level_up()
	xp_changed.emit(xp, level)
	save_game()

func _level_up() -> void:
	level += 1
	stat_points += 3
	var old_max := max_hp
	max_hp = max_hp_total()
	hp = mini(hp + (max_hp - old_max), max_hp)  # heal the new capacity
	hp_changed.emit(hp - (max_hp - old_max), hp)
	level_up.emit(level, 3)

## Derived stats read everywhere combat math happens.
static func soft_cap_points(points: int, threshold: int = 20,
		post_threshold_scale: float = 0.5) -> float:
	var safe_points := maxi(points, 0)
	var safe_threshold := maxi(threshold, 0)
	if safe_points <= safe_threshold:
		return float(safe_points)
	return float(safe_threshold) + float(safe_points - safe_threshold) \
		* clampf(post_threshold_scale, 0.0, 1.0)

func attack_damage_bonus() -> int:
	return int(round(soft_cap_points(stat_str)))

func attack_speed_mult() -> float:
	return 1.0 + 0.03 * soft_cap_points(stat_dex)

func move_speed_mult() -> float:
	return 1.0 + 0.02 * soft_cap_points(stat_dex)

func crit_chance() -> float:
	return clampf(0.05 + 0.01 * soft_cap_points(stat_luk), 0.0, 0.75)

func crit_damage() -> float:
	return 1.5 + 0.02 * soft_cap_points(stat_luk)

func defense_stat() -> int:
	return int(round(soft_cap_points(stat_end)))

func max_hp_total() -> int:
	return MAX_HP_BASE + int(round(3.0 * soft_cap_points(stat_vit)))

## Spend one point on "str"/"dex"/"vit"/"luk"/"end".
func allocate_stat(key: String) -> bool:
	if stat_points <= 0:
		return false
	match key:
		"str": stat_str += 1
		"dex":
			stat_dex += 1
		"vit":
			stat_vit += 1
			var old_max := max_hp
			max_hp = max_hp_total()
			hp = mini(hp + (max_hp - old_max), max_hp)
			hp_changed.emit(old_max, max_hp)
		"luk": stat_luk += 1
		"end": stat_end += 1
		_:
			return false
	stat_points -= 1
	stats_changed.emit()
	save_game()
	return true

const RESPEC_BASE_GOLD: int = 20

func respec_cost() -> int:
	return RESPEC_BASE_GOLD + maxi(0, level - 1) * 5

## Reset allocated stats into unspent points. The transaction is explicit and
## gold-only; it never changes level, XP, gear, rewards, or achievements.
func respec_stats() -> bool:
	var spent := stat_str + stat_dex + stat_vit + stat_luk + stat_end
	if spent <= 0 or gold < respec_cost():
		return false
	gold -= respec_cost()
	gold_changed.emit(gold)
	stat_points += spent
	stat_str = 0
	stat_dex = 0
	stat_vit = 0
	stat_luk = 0
	stat_end = 0
	max_hp = max_hp_total()
	hp = mini(hp, max_hp)
	stats_changed.emit()
	record_activity("RESPEC · %d POINTS · -%d GOLD" % [spent, respec_cost()])
	save_game()
	return true

# === Boss first-kills (diamond rewards, once per boss per save) ===
var boss_first_kills: Dictionary = {}
var boss_reward_selections: Dictionary = {}
var quest_reward_claims: Dictionary = {}
var opened_chests: Dictionary = {}

## True the first time this boss key is defeated; later kills return false.
func mark_boss_killed(boss_key: String) -> bool:
	if boss_first_kills.get(boss_key, false):
		return false
	boss_first_kills[boss_key] = true
	save_game()
	return true

func has_boss_killed(boss_key: String) -> bool:
	return bool(boss_first_kills.get(boss_key, false))

func choose_boss_reward(boss_id: String, reward_id: String) -> Dictionary:
	if boss_reward_selections.has(boss_id):
		return {"success": false, "reason": "already_chosen"}
	var valid := false
	for choice in BOSS_REWARD_CATALOG.choices_for(boss_id):
		if str(choice.get("id", "")) == reward_id:
			valid = true
			break
	if not valid:
		return {"success": false, "reason": "invalid_choice"}
	if WEAPON_DEFS.has(reward_id):
		var weapon: Dictionary = WEAPON_DEFS[reward_id].duplicate(true)
		if not forged_weapons.any(func(item: Dictionary) -> bool: return str(item.get("id", "")) == reward_id):
			forged_weapons.append(weapon)
		inventory_changed.emit()
	elif ARMOR_DEFS.has(reward_id):
		var armor: Dictionary = ARMOR_DEFS[reward_id].duplicate(true)
		if not forged_armors.any(func(item: Dictionary) -> bool: return str(item.get("id", "")) == reward_id):
			forged_armors.append(armor)
		inventory_changed.emit()
	else:
		return {"success": false, "reason": "missing_definition"}
	boss_reward_selections[boss_id] = reward_id
	record_activity("BOSS REWARD · %s" % reward_id)
	save_game()
	return {"success": true, "boss_id": boss_id, "reward_id": reward_id}

# === Realm travel ===
@export var current_realm: String = "bramblewood"
var unlocked_realms: Array[String] = ["bramblewood", "mistfen", "heartwood"]

## Old saves used "whispergrove" for the starting grove.
func _normalize_realm(realm_id: String) -> String:
	realm_id = "bramblewood" if realm_id == "whispergrove" else realm_id
	# Save/UI only ever reference known realms; anything else on load is a
	# corrupt or hand-edited save and must not drive dynamic scene loads.
	return realm_id if realm_id in ["bramblewood", "mistfen", "heartwood", "moonfen"] \
		else "bramblewood"

## Returns true only when this call creates a new unlock. Existing call sites
## may continue ignoring the result.
func unlock_realm(realm_id: String) -> bool:
	if realm_id in unlocked_realms:
		return false
	unlocked_realms.append(realm_id)
	save_game()
	return true

func set_current_realm(realm_id: String) -> void:
	if current_realm == realm_id:
		return
	current_realm = realm_id
	realm_changed.emit(realm_id)
	save_game()

# === Diamond cosmetics (purely visual — zero stats) ===
var cosmetics_owned: Array[String] = []
@export var active_sfx_profile: String = "vanilla"
@export var active_trail_color: String = "ffb84d"   # html hex
@export var active_aura_color: String = "00000000"  # alpha 0 = none
var active_cosmetic_ids: Dictionary = {}   # kind -> owned item id


func owns_cosmetic(id: String) -> bool:
	return id in cosmetics_owned

## kind: "sfx" | "trail" | "aura"; value payload per kind.
func purchase_cosmetic(id: String, price: int, kind: String, value: String) -> bool:
	if id in cosmetics_owned:
		return true  # already owned; equip path handles rest
	if not spend_diamonds(price):
		return false
	cosmetics_owned.append(id)
	purchase_ledger.append({"id": id, "kind": "cosmetic_%s" % kind,
		"price": maxi(0, price), "currency": "diamonds"})
	record_activity("PURCHASE · %s" % id)
	cloud_sync_queue.enqueue("purchase-cosmetic-%d" % purchase_ledger.size(),
		"purchase_cosmetic", {"item_id": id, "kind": kind, "price": maxi(0, price),
			"currency": "diamonds"})
	equip_cosmetic(kind, value, id)
	return true

func equip_cosmetic(kind: String, value: String, id: String = "") -> void:
	match kind:
		"sfx":
			active_sfx_profile = value if value != "" else "vanilla"
		"trail":
			active_trail_color = value if value != "" else "ffb84d"
		"aura":
			active_aura_color = value if value != "" else "00000000"
	if id != "":
		active_cosmetic_ids[kind] = id
		if id not in cosmetics_owned:
			cosmetics_owned.append(id)
	else:
		active_cosmetic_ids.erase(kind)
	cosmetics_changed.emit()
	save_game()

func trail_color() -> Color:
	return Color(active_trail_color)

func has_aura() -> bool:
	return Color(active_aura_color).a > 0.05

func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	record_activity("GOLD -%d" % amount)
	save_game()
	return true

func owns_shop_item(id: String) -> bool:
	for weapon in forged_weapons:
		if weapon.get("id", "") == id:
			return true
	for armor in forged_armors:
		if armor.get("id", "") == id:
			return true
	return equipped_weapon.get("id", "") == id or equipped_armor.get("id", "") == id

func buy_shop_item(id: String) -> Dictionary:
	var entry := {}
	for stock in SHOP_STOCK:
		if stock.id == id:
			entry = stock
			break
	if entry.is_empty():
		return {"success": false, "message": "The trader does not stock that."}
	if owns_shop_item(id):
		return {"success": false, "message": "That piece already travels with you."}
	if not spend_gold(int(entry.price)):
		return {"success": false,
			"message": "Not enough gold — the trader wants %d GOLD." % int(entry.price)}
	
	if entry.kind == "weapon":
		add_weapon(WEAPON_DEFS[id].duplicate(true), true,
			"%s secured from the trader's rack." % WEAPON_DEFS[id].name)
	elif entry.kind == "armor":
		add_armor(ARMOR_DEFS[id], false)
		equip_armor(id)
		loot_notice = "%s woven into your gear." % ARMOR_DEFS[id].name
		loot_count = 1
		loot_pulse += 1
		loot_received.emit(loot_notice, 1)
	else:
		add_loot(id, 1, "%s purchased from the trader." % get_item(id).get("name", id))
	purchase_ledger.append({"id": id, "kind": str(entry.kind), "price": int(entry.price),
		"currency": "gold"})
	record_activity("PURCHASE · %s" % id)
	cloud_sync_queue.enqueue("purchase-shop-%d" % purchase_ledger.size(),
		"buy_shop_item", {"item_id": id, "kind": str(entry.kind),
			"price": int(entry.price), "currency": "gold"})
	save_game()
	return {"success": true, "id": id}

func get_purchase_ledger() -> Array[Dictionary]:
	return purchase_ledger.duplicate(true)

func queue_cloud_intent(action_id: String, action: String, payload: Dictionary) -> bool:
	var queued := cloud_sync_queue.enqueue(action_id, action, payload)
	if queued:
		save_game()
	return queued

func get_pending_cloud_intents() -> Array[Dictionary]:
	return cloud_sync_queue.pending()

func mark_cloud_intent_attempted(action_id: String) -> bool:
	var marked := cloud_sync_queue.mark_attempted(action_id)
	if marked:
		save_game()
	return marked

func acknowledge_cloud_intent(action_id: String) -> bool:
	var acknowledged := cloud_sync_queue.acknowledge(action_id)
	if acknowledged:
		save_game()
	return acknowledged

# === Inventory ===
func sell_shop_item(id: String, kind: String) -> Dictionary:
	var value := 0
	if kind == "weapon":
		if equipped_weapon.get("id", "") == id:
			return {"success": false, "message": "Equip another weapon before selling this one."}
		for i in forged_weapons.size():
			if forged_weapons[i].get("id", "") == id:
				value = maxi(1, int(WEAPON_DEFS.get(id, {}).get("price", 1)) / 2)
				forged_weapons.remove_at(i)
				break
	elif kind == "armor":
		if equipped_armor.get("id", "") == id:
			return {"success": false, "message": "Equip another armor piece before selling this one."}
		for i in forged_armors.size():
			if forged_armors[i].get("id", "") == id:
				value = maxi(1, int(ARMOR_DEFS.get(id, {}).get("price", 1)) / 2)
				forged_armors.remove_at(i)
				break
	else:
		var item := get_item(id)
		if item.is_empty() or int(item.get("quantity", 0)) <= 0:
			return {"success": false, "message": "You have none of that to sell."}
		value = 6
		item.quantity -= 1
	if value <= 0:
		return {"success": false, "message": "The trader cannot buy that."}
	add_gold(value, "Sold %s for %d gold." % [id, value])
	record_activity("SOLD · %s · +%d GOLD" % [id, value])
	inventory_changed.emit()
	save_game()
	return {"success": true, "id": id, "value": value}

func get_item(item_id: String) -> Dictionary:
	for item in inventory:
		if item.id == item_id:
			return item
	return {}

func add_loot(item_id: String, amount: int, notice: String = "", display_count: int = -1) -> void:
	var item = get_item(item_id)
	if not item:
		return
	item.quantity += amount
	inventory_changed.emit()
	if notice:
		loot_notice = notice
		loot_count = display_count if display_count > 0 else amount
		loot_pulse += 1
		loot_received.emit(loot_notice, loot_count)
	check_onboarding_trigger("loot")
	save_game()

# === Raw materials ===
func add_material(material_id: String, qty: int = 1) -> void:
	if not MATERIAL_DEFS.has(material_id):
		return
	raw_materials[material_id] = int(raw_materials.get(material_id, 0)) + maxi(1, qty)
	materials_changed.emit()
	save_game()

func remove_material(material_id: String, qty: int = 1) -> bool:
	var current: int = int(raw_materials.get(material_id, 0))
	if current < qty:
		return false
	raw_materials[material_id] = current - qty
	if raw_materials[material_id] <= 0:
		raw_materials.erase(material_id)
	materials_changed.emit()
	save_game()
	return true

func has_material(material_id: String, qty: int = 1) -> bool:
	return int(raw_materials.get(material_id, 0)) >= qty

func get_material_qty(material_id: String) -> int:
	return int(raw_materials.get(material_id, 0))

## Persist gathering depletion by stable realm/node id. World nodes must use
## this dictionary instead of attempting to create dynamic GameState fields.
func set_gathered_node_state(node_id: String, state: Dictionary) -> void:
	if node_id.is_empty():
		return
	if state.is_empty():
		gathered_nodes.erase(node_id)
	else:
		gathered_nodes[node_id] = state.duplicate(true)
	gathered_nodes_changed.emit()
	save_game()

func get_gathered_node_state(node_id: String) -> Dictionary:
	var state = gathered_nodes.get(node_id, {})
	return state.duplicate(true) if state is Dictionary else {}

## One-save crafting transaction. Validate the output and complete cost before
## mutating anything, then grant the correct inventory/gear type atomically in
## memory. This prevents weapon recipes from consuming materials and vanishing
## through the consumable-only add_loot path.
func craft_transaction(category: String, output_id: String, output_qty: int,
		crafted_name: String, rarity: int, materials: Dictionary,
		gold_cost: int) -> Dictionary:
	var gear_def: Dictionary = {}
	var inventory_item: Dictionary = {}
	match category:
		"weapon":
			gear_def = WEAPON_DEFS.get(output_id, {}).duplicate(true)
		"armor":
			gear_def = ARMOR_DEFS.get(output_id, {}).duplicate(true)
		"potion", "utility":
			inventory_item = get_item(output_id)
		_:
			return {"success": false, "message": "Unsupported recipe category."}
	if gear_def.is_empty() and inventory_item.is_empty():
		return {"success": false, "message": "Crafting output is not defined."}
	if gold_cost < 0 or gold < gold_cost:
		return {"success": false, "message": "Need %d gold." % maxi(gold_cost, 0)}
	for mat_id in materials:
		var needed := int(materials[mat_id])
		if needed < 0 or not MATERIAL_DEFS.has(mat_id):
			return {"success": false, "message": "Recipe contains an invalid material."}
		if not has_material(str(mat_id), needed):
			var material_name := str(MATERIAL_DEFS[mat_id].get("name", mat_id))
			return {"success": false,
				"message": "Need %d %s." % [needed, material_name]}

	gold -= gold_cost
	for mat_id in materials:
		var remaining := get_material_qty(str(mat_id)) - int(materials[mat_id])
		if remaining > 0:
			raw_materials[mat_id] = remaining
		else:
			raw_materials.erase(mat_id)

	var qty := maxi(output_qty, 1)
	if category == "weapon":
		gear_def["name"] = crafted_name
		gear_def["rarity"] = rarity
		gear_def["crafted"] = true
		_upsert_crafted_gear(forged_weapons, gear_def)
	elif category == "armor":
		gear_def["name"] = crafted_name
		gear_def["rarity"] = rarity
		gear_def["crafted"] = true
		_upsert_crafted_gear(forged_armors, gear_def)
	else:
		inventory_item.quantity = int(inventory_item.get("quantity", 0)) + qty

	gold_changed.emit(gold)
	materials_changed.emit()
	inventory_changed.emit()
	loot_notice = "Crafted %s." % crafted_name
	loot_count = qty
	loot_pulse += 1
	loot_received.emit(loot_notice, qty)
	update_objective("craft", output_id, 1, false)
	check_onboarding_trigger("craft")
	record_activity("CRAFT · %s" % output_id)
	cloud_sync_queue.enqueue("craft-%s-%d" % [output_id, loot_pulse],
		"craft_transaction", {"category": category, "output_id": output_id,
			"quantity": qty, "gold": maxi(gold_cost, 0), "materials": materials.duplicate(true)})
	save_game()
	return {"success": true, "name": crafted_name, "qty": qty,
		"category": category, "output_id": output_id}

func _upsert_crafted_gear(collection: Array[Dictionary], gear: Dictionary) -> void:
	for i in collection.size():
		if collection[i].get("id", "") == gear.get("id", ""):
			collection[i] = gear.duplicate(true)
			return
	collection.append(gear.duplicate(true))

func add_weapon(weapon: Dictionary, equip: bool = false, notice: String = "") -> void:
	weapon = _normalize_weapon_record(weapon)
	if not weapon.has("id"):
		return
	var stored = weapon.duplicate(true)
	for i in forged_weapons.size():
		if forged_weapons[i].get("id", "") == stored.id:
			forged_weapons[i] = stored
			break
	if not forged_weapons.any(func(item): return item.get("id", "") == stored.id):
		forged_weapons.append(stored)
	if equip:
		equipped_weapon = stored.duplicate(true)
		_refresh_skill_slots()
		weapon_changed.emit(equipped_weapon)
	inventory_changed.emit()
	if notice:
		loot_notice = notice
		loot_count = 1
		loot_pulse += 1
		loot_received.emit(loot_notice, loot_count)
	save_game()

func _normalize_weapon_record(raw_weapon: Dictionary) -> Dictionary:
	var normalized := raw_weapon.duplicate(true)
	var weapon_id := str(normalized.get("id", ""))
	if WEAPON_DEFS.has(weapon_id):
		var canonical: Dictionary = WEAPON_DEFS[weapon_id]
		for key in canonical:
			if not normalized.has(key):
				normalized[key] = canonical[key].duplicate(true) if canonical[key] is Array or canonical[key] is Dictionary else canonical[key]
	if normalized.has("skill") and not normalized.has("skills"):
		normalized["skills"] = [normalized["skill"]]
	normalized.erase("skill")
	var skills: Array = normalized.get("skills", [])
	while skills.size() < 3:
		skills.append({"name": "%s RITE %d" % [str(normalized.get("name", "WEAPON")), skills.size() + 1], "icon": "strike", "type": "strike", "cooldown": 3.0, "dmg_mult": 1.2})
	normalized["skills"] = skills
	return normalized

## Grants a named drop once without replacing its saved upgrades on repeat
## clears. Returns true only when ownership was newly created.
func grant_unique_weapon(weapon_id: String, equip: bool = false,
		notice: String = "") -> bool:
	if not WEAPON_DEFS.has(weapon_id):
		return false
	if forged_weapons.any(func(item: Dictionary) -> bool:
		return str(item.get("id", "")) == weapon_id):
		return false
	add_weapon(WEAPON_DEFS[weapon_id].duplicate(true), equip, notice)
	return true

func equip_weapon_by_id(id: String) -> bool:
	for weapon in forged_weapons:
		if weapon.get("id", "") == id:
			equipped_weapon = weapon.duplicate(true)
			equipment_slots[&"weapon"] = equipped_weapon.duplicate(true)
			_refresh_skill_slots()
			weapon_changed.emit(equipped_weapon)
			equipment_changed.emit(equipment_slots.duplicate(true))
			update_objective("equip", id, 1, false)
			check_onboarding_trigger("equip")
			save_game()
			return true
	return false

# === Equipment Upgrades ===
const MAX_UPGRADE_LEVEL := 5

static func upgrade_material_cost(base_cost: int, level: int) -> int:
	return ceili(float(base_cost) * pow(1.55, float(level)))

static func upgrade_gold_cost(base_gold: int, level: int) -> int:
	return ceili(float(base_gold) * pow(1.42, float(level)))

static func upgrade_stat_gain(base_stat: int, level: int) -> int:
	return ceili(float(base_stat) * (0.08 + 0.025 * float(level)))

func get_weapon_upgrade_cost(weapon: Dictionary) -> Dictionary:
	var level: int = int(weapon.get("upgrade_level", 0))
	var upgrade_cap: int = MAX_UPGRADE_LEVEL
	var camp := get_node_or_null("/root/CampProgression")
	if camp != null and camp.has_method("weapon_upgrade_cap"):
		upgrade_cap = camp.weapon_upgrade_cap()
	if level >= upgrade_cap:
		return {"can_upgrade": false}
	var base_atk: int = int(weapon.get("atk", 8))
	var material_cost := upgrade_material_cost(4, level)
	var gold_cost := upgrade_gold_cost(30, level)
	var stat_gain := upgrade_stat_gain(base_atk, level)
	return {
		"can_upgrade": true,
		"level": level,
		"next_level": level + 1,
		"material_id": "iron_shard",
		"material_cost": material_cost,
		"gold_cost": gold_cost,
		"stat_gain": stat_gain,
		"current_atk": base_atk,
		"next_atk": base_atk + stat_gain,
	}

func upgrade_weapon(weapon_id: String) -> Dictionary:
	var weapon := {}
	for w in forged_weapons:
		if w.get("id", "") == weapon_id:
			weapon = w
			break
	if weapon.is_empty():
		return {"success": false, "message": "Weapon not found."}
	var cost := get_weapon_upgrade_cost(weapon)
	if not cost.get("can_upgrade", false):
		return {"success": false, "message": "Already at max upgrade level."}
	var mat_id: String = cost.get("material_id", "iron_shard")
	var mat_cost: int = cost.get("material_cost", 0)
	var gold_cost: int = cost.get("gold_cost", 0)
	if not has_material(mat_id, mat_cost):
		return {"success": false, "message": "Need %d %s." % [mat_cost, MATERIAL_DEFS.get(mat_id, {}).get("name", mat_id)]}
	if not spend_gold(gold_cost):
		return {"success": false, "message": "Need %d gold." % gold_cost}
	remove_material(mat_id, mat_cost)
	var new_level: int = int(weapon.get("upgrade_level", 0)) + 1
	weapon["upgrade_level"] = new_level
	weapon["atk"] = int(weapon.get("atk", 8)) + cost.get("stat_gain", 0)
	for i in forged_weapons.size():
		if forged_weapons[i].get("id", "") == weapon_id:
			forged_weapons[i] = weapon.duplicate(true)
			break
	if equipped_weapon.get("id", "") == weapon_id:
		equipped_weapon = weapon.duplicate(true)
		_refresh_skill_slots()
		weapon_changed.emit(equipped_weapon)
	inventory_changed.emit()
	upgrade_completed.emit(weapon_id, new_level)
	update_objective("upgrade", weapon_id, 1, false)
	loot_notice = "Upgraded to +%d" % new_level
	loot_count = 0
	loot_pulse += 1
	loot_received.emit(loot_notice, 0)
	record_activity("UPGRADE WEAPON · %s +%d" % [weapon_id, new_level])
	cloud_sync_queue.enqueue("upgrade-weapon-%s-%d" % [weapon_id, new_level],
		"upgrade_weapon", {"item_id": weapon_id, "level": new_level,
			"gold": gold_cost, "material_id": mat_id, "material": mat_cost})
	save_game()
	return {"success": true, "level": new_level, "atk": weapon.get("atk", 0)}

func get_armor_upgrade_cost(armor: Dictionary) -> Dictionary:
	var level: int = int(armor.get("upgrade_level", 0))
	if level >= MAX_UPGRADE_LEVEL:
		return {"can_upgrade": false}
	var base_def: int = int(armor.get("defense", 3))
	var material_cost := upgrade_material_cost(5, level)
	var gold_cost := upgrade_gold_cost(35, level)
	var stat_gain := upgrade_stat_gain(base_def, level)
	return {
		"can_upgrade": true,
		"level": level,
		"next_level": level + 1,
		"material_id": "iron_shard",
		"material_cost": material_cost,
		"gold_cost": gold_cost,
		"stat_gain": stat_gain,
		"current_def": base_def + level,
		"next_def": base_def + (level + 1) + stat_gain,
	}

func upgrade_armor(armor_id: String) -> Dictionary:
	var armor := {}
	for a in forged_armors:
		if a.get("id", "") == armor_id:
			armor = a
			break
	if armor.is_empty():
		return {"success": false, "message": "Armor not found."}
	var cost := get_armor_upgrade_cost(armor)
	if not cost.get("can_upgrade", false):
		return {"success": false, "message": "Already at max upgrade level."}
	var mat_id: String = cost.get("material_id", "iron_shard")
	var mat_cost: int = cost.get("material_cost", 0)
	var gold_cost: int = cost.get("gold_cost", 0)
	if not has_material(mat_id, mat_cost):
		return {"success": false, "message": "Need %d %s." % [mat_cost, MATERIAL_DEFS.get(mat_id, {}).get("name", mat_id)]}
	if not spend_gold(gold_cost):
		return {"success": false, "message": "Need %d gold." % gold_cost}
	remove_material(mat_id, mat_cost)
	var new_level: int = int(armor.get("upgrade_level", 0)) + 1
	armor["upgrade_level"] = new_level
	armor["defense"] = int(armor.get("defense", 3)) + cost.get("stat_gain", 0)
	for i in forged_armors.size():
		if forged_armors[i].get("id", "") == armor_id:
			forged_armors[i] = armor.duplicate(true)
			break
	if equipped_armor.get("id", "") == armor_id:
		equipped_armor = armor.duplicate(true)
		armor_changed.emit(equipped_armor)
	inventory_changed.emit()
	upgrade_completed.emit(armor_id, new_level)
	loot_notice = "Armor upgraded to +%d" % new_level
	loot_count = 0
	loot_pulse += 1
	loot_received.emit(loot_notice, 0)
	record_activity("UPGRADE ARMOR · %s +%d" % [armor_id, new_level])
	cloud_sync_queue.enqueue("upgrade-armor-%s-%d" % [armor_id, new_level],
		"upgrade_armor", {"item_id": armor_id, "level": new_level,
			"gold": gold_cost, "material_id": mat_id, "material": mat_cost})
	save_game()
	return {"success": true, "level": new_level, "defense": armor.get("defense", 0)}

const ELEMENT_SWITCH_COST := 24
const ELEMENT_SWITCHES := ["fire", "frost", "shock", "nature"]

## Checkpoint forge action: retune the equipped weapon’s elemental payload.
## This changes only the element identity; damage and skill timing stay intact.
func switch_weapon_element(element: String, cost: int = ELEMENT_SWITCH_COST) -> Dictionary:
	if element not in ELEMENT_SWITCHES:
		return {"success": false, "message": "That element is not stable enough to bind."}
	var current := str(equipped_weapon.get("element", ""))
	if current == element:
		return {"success": false, "message": "The weapon is already attuned to %s." % element.capitalize()}
	if not spend_gold(cost):
		return {"success": false, "message": "The checkpoint forge needs %d gold." % cost}
	equipped_weapon["element"] = element
	for i in forged_weapons.size():
		if forged_weapons[i].get("id", "") == equipped_weapon.get("id", ""):
			forged_weapons[i] = equipped_weapon.duplicate(true)
			break
	_refresh_skill_slots()
	weapon_changed.emit(equipped_weapon)
	loot_notice = "Weapon attuned to %s." % element.capitalize()
	loot_count = 0
	loot_pulse += 1
	loot_received.emit(loot_notice, 0)
	record_activity("ATTUNE · %s" % element.to_upper())
	cloud_sync_queue.enqueue("attune-%s-%d" % [element, loot_pulse],
		"switch_weapon_element", {"item_id": str(equipped_weapon.get("id", "")),
			"element": element, "gold": cost})
	save_game()
	return {"success": true, "message": loot_notice}

# === Scan-forged relics ===
## Turns a captured object into a wieldable kit. The player supplies only
## names — item and its three rites; every combat number is computed from
## the rarity roll inside RelicData.build_weapon_def.
func forge_relic_weapon(base: Dictionary, rarity: int, item_name: String,
		skill_names: Array) -> Dictionary:
	var def := RelicData.build_weapon_def(base, rarity, item_name, skill_names)
	add_weapon(def, true, "%s bound into your kit." % def.name)
	return def

# === Scan economy ===
func earn_scan() -> void:
	if scans_remaining >= MAX_SCANS:
		return
	scans_remaining += 1
	scans_changed.emit(scans_remaining)
	record_activity("SCAN EARNED · %d REMAINING" % scans_remaining)

func add_scan_fragment(amount: int = 1) -> void:
	if amount <= 0:
		return
	scan_fragments += amount
	record_activity("SCAN FRAGMENTS +%d" % amount)
	while scan_fragments >= SCAN_FRAGMENTS_PER_SCAN and scans_remaining < MAX_SCANS:
		scan_fragments -= SCAN_FRAGMENTS_PER_SCAN
		earn_scan()
	# Avoid stockpiling unusable fragments while scans are capped.
	scan_fragments = mini(scan_fragments, SCAN_FRAGMENTS_PER_SCAN - 1)
	scan_fragments_changed.emit(scan_fragments)
	save_game()

## True when a scan was available and is now spent.
func consume_scan() -> bool:
	if scans_remaining <= 0:
		return false
	scans_remaining -= 1
	scans_changed.emit(scans_remaining)
	record_activity("SCAN CONSUMED")
	cloud_sync_queue.enqueue("scan-consume-%d" % Time.get_ticks_msec(),
		"consume_scan", {"remaining": scans_remaining, "source": "scan_balance"})
	save_game()
	return true

# === Boss customization storage ===
func set_boss_custom(boss_id: String, payload: Dictionary) -> void:
	boss_customs[boss_id] = payload.duplicate(true)
	save_game()

func get_boss_custom(boss_id: String) -> Dictionary:
	var data: Dictionary = boss_customs.get(boss_id, {})
	return data.duplicate(true)

func use_item(item_id: String) -> String:
	var item = get_item(item_id)
	if not item or item.kind != ItemKind.CONSUMABLE or item.quantity < 1:
		return "That satchel pocket holds nothing usable right now."
	
	var restored = heal(MOSS_TONIC_HEAL)
	if restored <= 0:
		return "You save the Moss Tonic; your lantern is already at full warmth."
	
	item.quantity -= 1
	loot_notice = ""
	loot_count = 0
	inventory_changed.emit()
	save_game()
	return "You drink a Moss Tonic and recover %d warmth." % restored

# === XP / Leveling ===
# grant_xp lives in the Progression block (full curve + multi-level-ups).

# === Helpers ===
func get_cooldown_text(slot: int) -> String:
	return get_slot_cooldown_text(slot)

func get_warmth_percent() -> float:
	return hp / float(max_hp)

func is_quest_complete() -> bool:
	return current_stage == QuestStage.COMPLETE

# === Persistence ===
const SAVE_PATH := "user://embervale_save.cfg"
const CORRUPT_SAVE_PATH := "user://embervale_save.corrupt.cfg"
## Bump when the on-disk save layout changes. Loads refuse a file whose schema
## is NEWER than this build supports (it may contain fields we cannot honor).
const SAVE_SCHEMA_VERSION := 3
## Hard ceilings applied on load so a torn or hand-edited save cannot push the
## player into absurd values (e.g. a negative wallet or 64-bit stat overflow).
const MAX_LEVEL := 99
const MAX_CURRENCY := 999_999
const MAX_STAT_VALUE := 999
const MAX_STAT_POINTS := 999
var save_path: String = SAVE_PATH

## Read-only support export. Local progression is portable diagnostic data;
## paid ownership is deliberately represented as non-authoritative records and
## must be revalidated by the account provider on a new device.
func build_data_export() -> Dictionary:
	var inventory_snapshot: Dictionary = {}
	for item in inventory:
		inventory_snapshot[str(item.get("id", ""))] = int(item.get("quantity", 0))
	var asset_coverage: Dictionary = {}
	for asset in ASSET_INTAKE.inventory_downloaded_assets():
		var owner := str(asset.get("owner", ""))
		var pack := owner if not owner.is_empty() else "unassigned_review_assets"
		if not asset_coverage.has(pack):
			asset_coverage[pack] = {"gameplay": 0, "review_only": 0}
		var bucket := "gameplay" if str(asset.get("classification", "")) == "GAMEPLAY" else "review_only"
		asset_coverage[pack][bucket] = int(asset_coverage[pack][bucket]) + 1
	return {
		"format": "embervale_support_export_v1",
		"local_progress": {
			"stage": int(current_stage),
			"route_checkpoint": route_checkpoint_id,
			"realm": current_realm,
			"level": level,
			"xp": xp,
			"gold": gold,
			"diamonds": diamonds,
			"inventory": inventory_snapshot,
			"equipped_weapon": equipped_weapon.get("id", ""),
			"equipped_armor": equipped_armor.get("id", ""),
			"unlocked_realms": unlocked_realms.duplicate(),
			"activity_history": activity_history.duplicate(),
			"camp": get_node_or_null("/root/CampProgression").to_dict() if get_node_or_null("/root/CampProgression") != null else {},
		},
		"entitlements": {
			"ownership_records": purchase_ledger.duplicate(true),
			"authority": "account_provider_revalidation_required",
			"local_records_are_not_receipts": true,
		},
		"asset_coverage": asset_coverage,
	}

func has_save() -> bool:
	return FileAccess.file_exists(save_path)

func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "schema_version", SAVE_SCHEMA_VERSION)
	cfg.set_value("meta", "content_schema", CONTENT_SCHEMA.CURRENT_VERSION)
	cfg.set_value("progress", "current_stage", int(current_stage))
	cfg.set_value("progress", "route_checkpoint_id", route_checkpoint_id)
	cfg.set_value("progress", "expedition_run_id", expedition_run_id)
	cfg.set_value("progress", "activity_recovery", activity_recovery)
	cfg.set_value("progress", "route_respawn_position", route_respawn_position)
	cfg.set_value("progress", "xp", xp)
	cfg.set_value("progress", "level", level)
	cfg.set_value("progress", "hp", hp)
	cfg.set_value("progress", "gold", gold)
	cfg.set_value("progress", "diamonds", diamonds)
	cfg.set_value("progress", "shard_collected", shard_collected)
	cfg.set_value("progress", "beacon_lit", beacon_lit)
	var world_state := get_node_or_null("/root/WorldState")
	cfg.set_value("progress", "weather_locked",
		bool(world_state.get("weather_locked")) if world_state != null else false)
	var items := {}
	for item in inventory:
		items[item.id] = item.quantity
	cfg.set_value("progress", "inventory", items)
	cfg.set_value("progress", "forged_weapons", forged_weapons)
	cfg.set_value("progress", "equipped_weapon", equipped_weapon)
	cfg.set_value("progress", "forged_armors", forged_armors)
	cfg.set_value("progress", "equipped_armor", equipped_armor)
	cfg.set_value("progress", "equipment_slots", equipment_slots)
	cfg.set_value("progress", "loadout_presets", loadout_presets)
	cfg.set_value("progress", "purchase_ledger", purchase_ledger)
	cfg.set_value("progress", "cloud_sync_queue", cloud_sync_queue.pending())
	cfg.set_value("progress", "scans_remaining", scans_remaining)
	cfg.set_value("progress", "scan_fragments", scan_fragments)
	cfg.set_value("progress", "boss_customs", boss_customs)
	cfg.set_value("progress", "stat_points", stat_points)
	cfg.set_value("progress", "stats", {"str": stat_str, "dex": stat_dex,
		"vit": stat_vit, "luk": stat_luk, "end": stat_end})
	cfg.set_value("progress", "current_realm", current_realm)
	cfg.set_value("progress", "unlocked_realms", unlocked_realms)
	cfg.set_value("progress", "cosmetics_owned", cosmetics_owned)
	cfg.set_value("progress", "active_sfx_profile", active_sfx_profile)
	cfg.set_value("progress", "active_trail_color", active_trail_color)
	cfg.set_value("progress", "active_aura_color", active_aura_color)
	cfg.set_value("progress", "boss_first_kills", boss_first_kills)
	cfg.set_value("progress", "boss_reward_selections", boss_reward_selections)
	cfg.set_value("progress", "quest_reward_claims", quest_reward_claims)
	cfg.set_value("progress", "opened_chests", opened_chests)
	cfg.set_value("progress", "active_cosmetic_ids", active_cosmetic_ids)
	cfg.set_value("progress", "raw_materials", raw_materials)
	cfg.set_value("progress", "gathered_nodes", gathered_nodes)
	cfg.set_value("progress", "discovered_landmarks", discovered_landmarks)
	cfg.set_value("progress", "onboarding_completed", onboarding_completed)
	cfg.set_value("progress", "onboarding_step", onboarding_step)
	cfg.set_value("progress", "quest_objectives", quest_objectives)
	cfg.set_value("progress", "pinned_objective_id", pinned_objective_id)
	cfg.set_value("progress", "completed_quizzes", completed_quizzes)
	cfg.set_value("progress", "activity_history", activity_history)
	var camp := get_node_or_null("/root/CampProgression")
	if camp != null and camp.has_method("to_dict"):
		cfg.set_value("progress", "camp", camp.to_dict())
	var sm := get_node_or_null("/root/StoryManager")
	if sm != null and sm.has_method("save_payload"):
		cfg.set_value("story", "payload", sm.save_payload())
	cfg.save(save_path)

func load_game() -> bool:
	if not has_save():
		return false
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		# Preserve the unreadable source for recovery/support; never overwrite an
		# earlier forensic copy during repeated startup attempts.
		if not FileAccess.file_exists(CORRUPT_SAVE_PATH):
			DirAccess.copy_absolute(save_path, CORRUPT_SAVE_PATH)
		return false
	# Refuse a save written by a NEWER schema: fields it carries could not be
	# interpreted as this build expects, and honoring them would corrupt state.
	if int(cfg.get_value("meta", "schema_version", 0)) > SAVE_SCHEMA_VERSION:
		return false
	reset()
	current_stage = clamp(int(cfg.get_value("progress", "current_stage",
		QuestStage.SEEK_SPRITE)), 0, QuestStage.COMPLETE)
	route_checkpoint_id = str(cfg.get_value("progress", "route_checkpoint_id",
		_checkpoint_for_stage(current_stage))).strip_edges().to_lower()
	if route_checkpoint_id.is_empty():
		route_checkpoint_id = _checkpoint_for_stage(current_stage)
	var saved_respawn = cfg.get_value("progress", "route_respawn_position",
		_respawn_for_checkpoint(route_checkpoint_id))
	expedition_run_id = maxi(0, int(cfg.get_value("progress", "expedition_run_id", 0)))
	var saved_recovery = cfg.get_value("progress", "activity_recovery", {})
	activity_recovery = saved_recovery.duplicate(true) if saved_recovery is Dictionary else {}
	if str(activity_recovery.get("status", "")) not in ["active", "abandoned", "failed"]:
		activity_recovery = {}
	route_respawn_position = saved_respawn as Vector2 \
		if saved_respawn is Vector2 else _respawn_for_checkpoint(route_checkpoint_id)
	xp = clampi(int(cfg.get_value("progress", "xp", 0)), 0, 100_000_000)
	level = clampi(int(cfg.get_value("progress", "level", 1)), 1, MAX_LEVEL)
	hp = cfg.get_value("progress", "hp", MAX_HP_BASE)
	shard_collected = cfg.get_value("progress", "shard_collected", false)
	beacon_lit = cfg.get_value("progress", "beacon_lit", false)
	var world_state := get_node_or_null("/root/WorldState")
	if world_state != null:
		world_state.set("weather_locked",
			bool(cfg.get_value("progress", "weather_locked", false)))
	hp = clampi(hp, 0, max_hp)
	var items: Dictionary = CONTENT_SCHEMA.migrate_inventory(
		cfg.get_value("progress", "inventory", {}))
	for item in inventory:
		if items.has(item.id):
			item.quantity = maxi(0, int(items[item.id]))
	forged_weapons.clear()
	var saved_weapons = cfg.get_value("progress", "forged_weapons", [])
	if saved_weapons is Array:
		for weapon in saved_weapons:
			if weapon is Dictionary and weapon.has("id"):
				forged_weapons.append(CONTENT_SCHEMA.migrate_gear(weapon, "weapon"))
	var saved_equipped = cfg.get_value("progress", "equipped_weapon", {})
	if saved_equipped is Dictionary and saved_equipped.has("id"):
		equipped_weapon = CONTENT_SCHEMA.migrate_gear(saved_equipped, "weapon")
	else:
		equipped_weapon = _get_default_weapon()
	_refresh_skill_slots()
	gold = clampi(int(cfg.get_value("progress", "gold",
		int(cfg.get_value("progress", "embers", gold)))), 0, MAX_CURRENCY)
	diamonds = clampi(int(cfg.get_value("progress", "diamonds", diamonds)),
		0, MAX_CURRENCY)
	gold_changed.emit(gold)
	diamonds_changed.emit(diamonds)
	forged_armors.clear()
	var saved_armors = cfg.get_value("progress", "forged_armors", [])
	if saved_armors is Array:
		for armor in saved_armors:
			if armor is Dictionary and armor.has("id"):
				forged_armors.append(CONTENT_SCHEMA.migrate_gear(armor, "armor"))
	var saved_armor = cfg.get_value("progress", "equipped_armor", {})
	equipped_armor = CONTENT_SCHEMA.migrate_gear(saved_armor, "armor") \
		if saved_armor is Dictionary and saved_armor.has("id") else {}
	equipment_slots = _empty_equipment_slots()
	var saved_slots = cfg.get_value("progress", "equipment_slots", {})
	if saved_slots is Dictionary:
		for slot in EQUIPMENT_SLOTS:
			var saved_item = saved_slots.get(slot, {})
			if saved_item is Dictionary and not saved_item.is_empty():
				equipment_slots[slot] = saved_item.duplicate(true)
	equipment_slots[&"weapon"] = equipped_weapon.duplicate(true)
	equipment_slots[&"chest"] = equipped_armor.duplicate(true)
	armor_changed.emit(equipped_armor)
	equipment_changed.emit(equipment_slots.duplicate(true))
	purchase_ledger.clear()
	var saved_purchases = cfg.get_value("progress", "purchase_ledger", [])
	if saved_purchases is Array:
		for purchase in saved_purchases:
			if purchase is Dictionary and not str(purchase.get("id", "")).is_empty():
				purchase_ledger.append({"id": str(purchase.get("id", "")),
					"kind": str(purchase.get("kind", "")),
					"price": maxi(0, int(purchase.get("price", 0))),
					"currency": str(purchase.get("currency", "gold"))})
	cloud_sync_queue.restore(cfg.get_value("progress", "cloud_sync_queue", []))
	var scan_state: Dictionary = CONTENT_SCHEMA.migrate_scan_state(
		cfg.get_value("progress", "scans_remaining", FREE_SCANS),
		cfg.get_value("progress", "scan_fragments", 0), MAX_SCANS,
		SCAN_FRAGMENTS_PER_SCAN)
	scans_remaining = int(scan_state.get("scans", FREE_SCANS))
	scan_fragments = int(scan_state.get("fragments", 0))
	scans_changed.emit(scans_remaining)
	scan_fragments_changed.emit(scan_fragments)
	var saved_customs = cfg.get_value("progress", "boss_customs", {})
	boss_customs = saved_customs.duplicate(true) if saved_customs is Dictionary else {}
	stat_points = clampi(int(cfg.get_value("progress", "stat_points", 0)),
		0, MAX_STAT_POINTS)
	var saved_stats = cfg.get_value("progress", "stats", {})
	if saved_stats is Dictionary:
		stat_str = clampi(int(saved_stats.get("str", 0)), 0, MAX_STAT_VALUE)
		stat_dex = clampi(int(saved_stats.get("dex", 0)), 0, MAX_STAT_VALUE)
		stat_vit = clampi(int(saved_stats.get("vit", 0)), 0, MAX_STAT_VALUE)
		stat_luk = clampi(int(saved_stats.get("luk", 0)), 0, MAX_STAT_VALUE)
		stat_end = clampi(int(saved_stats.get("end", 0)), 0, MAX_STAT_VALUE)
	max_hp = max_hp_total()
	# Rebalance heal: bring HP up to the (possibly larger) capacity so the
	# bigger health pool reads immediately after the base-HP change.
	hp = max_hp
	hp_changed.emit(0, hp)
	current_realm = _normalize_realm(str(cfg.get_value("progress", "current_realm", "bramblewood")))
	unlocked_realms.clear()
	var saved_realms = cfg.get_value("progress", "unlocked_realms", [])
	var normalized_realms: Array[String] = []
	if saved_realms is Array:
		for r in saved_realms:
			normalized_realms.append(_normalize_realm(str(r)))
	var required_realms: Array[String] = ["bramblewood", "mistfen", "heartwood"]
	unlocked_realms = CONTENT_SCHEMA.migrate_string_list(normalized_realms, required_realms)
	cosmetics_owned.clear()
	var saved_cos = cfg.get_value("progress", "cosmetics_owned", [])
	if saved_cos is Array:
		for c in saved_cos:
			cosmetics_owned.append(str(c))
	active_sfx_profile = str(cfg.get_value("progress", "active_sfx_profile", "vanilla"))
	active_trail_color = str(cfg.get_value("progress", "active_trail_color", "ffb84d"))
	active_aura_color = str(cfg.get_value("progress", "active_aura_color", "00000000"))
	var saved_loadouts = cfg.get_value("progress", "loadout_presets", {})
	loadout_presets = saved_loadouts.duplicate(true) if saved_loadouts is Dictionary else {}
	if loadout_presets.size() > MAX_LOADOUT_PRESETS:
		var preset_keys := loadout_presets.keys()
		for index in range(MAX_LOADOUT_PRESETS, preset_keys.size()):
			loadout_presets.erase(preset_keys[index])
	var saved_fks = cfg.get_value("progress", "boss_first_kills", {})
	boss_first_kills = saved_fks.duplicate(true) if saved_fks is Dictionary else {}
	var saved_reward_choices = cfg.get_value("progress", "boss_reward_selections", {})
	boss_reward_selections = saved_reward_choices.duplicate(true) \
		if saved_reward_choices is Dictionary else {}
	var saved_quest_claims = cfg.get_value("progress", "quest_reward_claims", {})
	quest_reward_claims = saved_quest_claims.duplicate(true) \
		if saved_quest_claims is Dictionary else {}
	var saved_chests = cfg.get_value("progress", "opened_chests", {})
	opened_chests = saved_chests.duplicate(true) if saved_chests is Dictionary else {}
	var saved_ids = cfg.get_value("progress", "active_cosmetic_ids", {})
	active_cosmetic_ids = saved_ids.duplicate(true) if saved_ids is Dictionary else {}
	var saved_mats = cfg.get_value("progress", "raw_materials", {})
	raw_materials = saved_mats.duplicate(true) if saved_mats is Dictionary else {}
	var saved_gn = cfg.get_value("progress", "gathered_nodes", {})
	gathered_nodes = saved_gn.duplicate(true) if saved_gn is Dictionary else {}
	var saved_lm = cfg.get_value("progress", "discovered_landmarks", {})
	discovered_landmarks = saved_lm.duplicate(true) if saved_lm is Dictionary else {}
	onboarding_completed = bool(cfg.get_value("progress", "onboarding_completed", false))
	onboarding_step = clampi(int(cfg.get_value("progress", "onboarding_step", 0)),
		0, ONBOARDING_STEPS.size())
	var saved_objectives = cfg.get_value("progress", "quest_objectives", [])
	quest_objectives = CONTENT_SCHEMA.migrate_objectives(saved_objectives, OBJECTIVE_TYPES)
	pinned_objective_id = str(cfg.get_value("progress", "pinned_objective_id", ""))
	if get_pinned_objective().is_empty():
		pinned_objective_id = ""
	var saved_quizzes = cfg.get_value("progress", "completed_quizzes", {})
	completed_quizzes = saved_quizzes.duplicate(true) if saved_quizzes is Dictionary else {}
	var saved_activity = cfg.get_value("progress", "activity_history", [])
	activity_history.clear()
	if saved_activity is Array:
		for entry in saved_activity:
			if not str(entry).strip_edges().is_empty():
				activity_history.append(str(entry).strip_edges())
		while activity_history.size() > ACTIVITY_HISTORY_CAP:
			activity_history.pop_back()
	var camp := get_node_or_null("/root/CampProgression")
	if camp != null and camp.has_method("from_dict"):
		camp.from_dict(cfg.get_value("progress", "camp", {}))
	var sm := get_node_or_null("/root/StoryManager")
	if sm != null and sm.has_method("load_payload"):
		sm.load_payload(cfg.get_value("story", "payload", {}))
	stats_changed.emit()
	hp_changed.emit(hp, hp)
	xp_changed.emit(xp, level)
	stage_changed.emit(current_stage)
	route_checkpoint_changed.emit(route_checkpoint_id)
	inventory_changed.emit()
	weapon_changed.emit(equipped_weapon)
	return true

func _sanitize_quest_objectives(saved) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not saved is Array:
		return result
	for raw in saved:
		if not raw is Dictionary:
			continue
		var objective: Dictionary = raw
		var objective_id := str(objective.get("id", ""))
		var objective_type := str(objective.get("type", ""))
		if objective_id.is_empty() or objective_type not in OBJECTIVE_TYPES:
			continue
		var target := maxi(1, int(objective.get("target_qty", 1)))
		var current := clampi(int(objective.get("current_qty", 0)), 0, target)
		result.append({
			"id": objective_id,
			"description": str(objective.get("description", objective_id)),
			"type": objective_type,
			"target_qty": target,
			"current_qty": current,
			"completed": bool(objective.get("completed", false)) or current >= target,
		})
	return result

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


# === Interface world-freeze (ref-counted) ===
var _ui_freeze_count := 0

## Freeze the world behind an open interface. Ref-counted so stacked or
## hand-off menus (satchel -> forge -> satchel) pause and resume cleanly.
func push_world_freeze() -> void:
	_ui_freeze_count += 1
	get_tree().paused = true

## Release one interface's hold on the world; play resumes only when every
## open interface has released its hold.
func pop_world_freeze() -> void:
	_ui_freeze_count = maxi(_ui_freeze_count - 1, 0)
	if _ui_freeze_count == 0:
		get_tree().paused = false

## Hard-clear the world-freeze hold. Use when the whole gameplay scene is
## being replaced (menu -> game, game -> menu): any CanvasLayer still visible
## at that instant is freed without popping, so its push would otherwise leak
## and leave the next scene paused forever.
func clear_ui_freeze() -> void:
	_ui_freeze_count = 0
	get_tree().paused = false

## Active owned id for a cosmetic kind ("" when vanilla).
func active_cosmetic_id_for(kind: String) -> String:
	return str(active_cosmetic_ids.get(kind, ""))
