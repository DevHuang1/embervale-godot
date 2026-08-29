extends Node

## === Embervale Game State (exact port from embervale-rpg) ===

# Quest progression
enum QuestStage { SEEK_SPRITE, CLAIM_SHARD, LIGHT_BEACON, COMPLETE }
enum CombatState { EXPLORING, COMBAT, VICTORY, DEFEATED }
enum ItemKind { CONSUMABLE, RELIC, QUEST }
enum ItemRarity { COMMON, UNCOMMON, RARE }

# === Weapon registry: each style drives its own attack animation + FX kit ===
const WEAPON_DEFS := {
	"mug_mace": {
		"id": "mug_mace", "name": "MUG MACE", "glyph": "☕", "style": "blunt",
		"element": "fire",
		"atk": 7, "swing_time": 0.38, "range": 8.2,
		"skills": [
			{"name": "MUG SLAM", "type": "aoe", "cooldown": 2.0, "radius": 13.0, "dmg_mult": 1.5},
			{"name": "EMBER FLIGHT", "type": "explosion", "cooldown": 2.5, "radius": 2.6, "dmg_mult": 1.7,
				"desc": "Hurl a cinder that bursts on the marked target."},
			{"name": "SIP OF STRENGTH", "type": "heal_bloom", "cooldown": 4.5, "heal": 14,
				"desc": "Restores warmth in a verdant bloom."}
		]
	},
	"ember_sword": {
		"id": "ember_sword", "name": "EMBERFANG", "glyph": "🗡", "style": "slash",
		"atk": 8, "swing_time": 0.30, "range": 8.6,
		"skills": [
			{"name": "CRESCENT CUT", "type": "strike", "cooldown": 1.5, "dmg_mult": 2.2,
				"desc": "A heavy crescent slash through the marked target."},
			{"name": "THORN WHIRL", "type": "whirl", "cooldown": 2.5, "radius": 3.6, "dmg_mult": 1.6,
				"desc": "Spin a ring of bramble slashes around you."},
			{"name": "SUNDER DASH", "type": "dash_strike", "cooldown": 3.0, "dmg_mult": 1.8,
				"desc": "Dash through the target, blade leading."}
		]
	},
	"arcane_staff": {
		"id": "arcane_staff", "name": "MOONBOUGH", "glyph": "🪄", "style": "magic",
		"atk": 6, "swing_time": 0.44, "range": 10.5,
		"skills": [
			{"name": "EMBER NOVA", "type": "explosion", "cooldown": 2.0, "radius": 3.0, "dmg_mult": 1.9,
				"desc": "Detonate an ember burst on the marked target."},
			{"name": "STAR COMET", "type": "comet", "cooldown": 4.0, "radius": 4.0, "dmg_mult": 2.8,
				"desc": "Call down a slow comet; a wide explosion follows."},
			{"name": "VERDANT BLOOM", "type": "heal_bloom", "cooldown": 4.5, "heal": 14,
				"desc": "Bloom verdant light, restoring warmth."}
		]
	}
}

# === Armor registry: defense reduces every hit, tint restyles the body ===
const ARMOR_DEFS := {
	"warden_plate": {
		"id": "warden_plate", "name": "WARDEN PLATE", "glyph": "🛡",
		"defense": 3, "speed_mult": 1.0, "price": 60,
		"tint": Color(0.30, 0.33, 0.38), "roughness": 0.5, "metallic": 0.35,
		"desc": "Grove-forged steel. Reduces each hit by 3."
	},
	"emberweave_cloak": {
		"id": "emberweave_cloak", "name": "EMBERWEAVE CLOAK", "glyph": "🧥",
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

# Player stats
@export var hp: int = 100
@export var max_hp: int = 100
@export var level: int = 1
@export var xp: int = 0

# Currencies: 🪙 gold buys gear at the trader; 💎 diamonds buy cosmetics only
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
@export var scans_remaining: int = FREE_SCANS
var boss_customs: Dictionary = {}  # boss_id -> payload Dictionary
signal scans_changed(count: int)

# Equipment
var forged_weapons: Array[Dictionary] = []
var equipped_weapon: Dictionary = WEAPON_DEFS["mug_mace"].duplicate(true)
var forged_armors: Array[Dictionary] = []
var equipped_armor: Dictionary = {}

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
		"glyph": "🧪"
	},
	{
		"id": "hushling_thorn",
		"name": "Hushling Thorn",
		"kind": ItemKind.RELIC,
		"quantity": 0,
		"description": "A cold bramble trophy that whispers near places where shadow gathers.",
		"rarity": ItemRarity.UNCOMMON,
		"stats": ["Resonance +1", "Hushling trophy"],
		"glyph": "⌁"
	},
	{
		"id": "ember_shard",
		"name": "Ember Shard",
		"kind": ItemKind.QUEST,
		"quantity": 0,
		"description": "A warm fragment of the old beacon's heart, still bright beneath the ash.",
		"rarity": ItemRarity.RARE,
		"stats": ["Beacon charge +1", "Quest relic"],
		"glyph": "◆"
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

func _process(delta: float) -> void:
	# Skill cooldowns recover in real time
	update_skill_cooldowns(delta)

func reset() -> void:
	hp = MAX_HP_BASE
	max_hp = MAX_HP_BASE
	level = 1
	xp = 0
	gold = 30
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
	opened_chests = {}
	active_cosmetic_ids = {}
	current_stage = QuestStage.SEEK_SPRITE
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
	_refresh_skill_slots()

	# Reset inventory quantities only
	for item in inventory:
		if item.id == "moss_tonic":
			item.quantity = 1
		else:
			item.quantity = 0

	scans_remaining = FREE_SCANS
	boss_customs = {}
	
	loot_notice = ""
	loot_count = 0
	loot_pulse = 0
	
	hp_changed.emit(0, hp)
	xp_changed.emit(xp, level)
	stage_changed.emit(current_stage)
	weapon_changed.emit(equipped_weapon)
	armor_changed.emit(equipped_armor)
	gold_changed.emit(gold)

# === Quest ===
func advance_stage(new_stage: QuestStage) -> void:
	current_stage = new_stage
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

func get_quest_instruction(stage: QuestStage) -> String:
	if stage == QuestStage.SEEK_SPRITE: return "Follow the pale path until the bramble sprite stirs."
	if stage == QuestStage.CLAIM_SHARD: return "The light it dropped is close. Gather it before the mist takes it."
	if stage == QuestStage.LIGHT_BEACON: return "Carry the Ember Shard to the ruined altar in the north-east grove."
	if stage == QuestStage.COMPLETE: return "The old road will hold its warmth until the next traveler comes through."
	return "Unknown quest stage"

func get_quest_copy(stage: QuestStage) -> Dictionary:
	if stage == QuestStage.SEEK_SPRITE: return {"chapter": "I. The Quiet Grove", "title": "Find the Hushling", "instruction": "Follow the pale path until the bramble sprite stirs."}
	if stage == QuestStage.CLAIM_SHARD: return {"chapter": "II. A Warm Fragment", "title": "Claim the Ember Shard", "instruction": "The light it dropped is close. Gather it before the mist takes it."}
	if stage == QuestStage.LIGHT_BEACON: return {"chapter": "III. The Way Back", "title": "Restore the Beacon", "instruction": "Carry the Ember Shard to the ruined altar in the north-east grove."}
	if stage == QuestStage.COMPLETE: return {"chapter": "IV. A Path Relit", "title": "The Grove Remembers", "instruction": "The old road will hold its warmth until the next traveler comes through."}
	return {"chapter": "", "title": "", "instruction": ""}

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
	var is_bloom = (auto_strike_count % PASSIVE_BLOOM_EVERY == 0)
	var base_damage = get_base_auto_damage()
	var damage = base_damage + (PASSIVE_BLOOM_BONUS if is_bloom else 0)
	
	var hit_time = 0.52 if is_bloom else 0.4
	var enemy_hit_time = 0.42 if is_bloom else 0.3
	
	return {
		"damage": damage,
		"is_bloom": is_bloom,
		"hit_time": hit_time,
		"enemy_hit_time": enemy_hit_time,
		"log": "Ember Circuit blooms: your third auto-strike lands for %d." % damage if is_bloom else "Your lantern-sabre strikes automatically for %d." % damage
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
	armor_changed.emit(equipped_armor)
	save_game()

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
func add_gold(amount: int, notice: String = "") -> void:
	gold += amount
	gold_changed.emit(gold)
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
	if notice != "":
		quest_progress.emit(notice)
	save_game()

func spend_diamonds(amount: int) -> bool:
	if diamonds < amount:
		return false
	diamonds -= amount
	diamonds_changed.emit(diamonds)
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
func attack_damage_bonus() -> int:
	return stat_str

func attack_speed_mult() -> float:
	return 1.0 + 0.03 * float(stat_dex)

func move_speed_mult() -> float:
	return 1.0 + 0.02 * float(stat_dex)

func crit_chance() -> float:
	return clampf(0.05 + 0.01 * float(stat_luk), 0.0, 0.75)

func crit_damage() -> float:
	return 1.5 + 0.02 * float(stat_luk)

func defense_stat() -> int:
	return stat_end

func max_hp_total() -> int:
	return MAX_HP_BASE + 3 * stat_vit

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

# === Boss first-kills (diamond rewards, once per boss per save) ===
var boss_first_kills: Dictionary = {}
var opened_chests: Dictionary = {}

## True the first time this boss key is defeated; later kills return false.
func mark_boss_killed(boss_key: String) -> bool:
	if boss_first_kills.get(boss_key, false):
		return false
	boss_first_kills[boss_key] = true
	save_game()
	return true

# === Realm travel ===
@export var current_realm: String = "bramblewood"
var unlocked_realms: Array[String] = ["bramblewood", "mistfen", "heartwood"]

## Old saves used "whispergrove" for the starting grove.
func _normalize_realm(realm_id: String) -> String:
	return "bramblewood" if realm_id == "whispergrove" else realm_id

func unlock_realm(realm_id: String) -> void:
	if realm_id in unlocked_realms:
		return
	unlocked_realms.append(realm_id)
	save_game()

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
			"message": "Not enough gold — the trader wants %d 🪙." % int(entry.price)}
	
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
	return {"success": true, "id": id}

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
	save_game()

func add_weapon(weapon: Dictionary, equip: bool = false, notice: String = "") -> void:
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

func equip_weapon_by_id(id: String) -> bool:
	for weapon in forged_weapons:
		if weapon.get("id", "") == id:
			equipped_weapon = weapon.duplicate(true)
			_refresh_skill_slots()
			weapon_changed.emit(equipped_weapon)
			save_game()
			return true
	return false

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

## True when a scan was available and is now spent.
func consume_scan() -> bool:
	if scans_remaining <= 0:
		return false
	scans_remaining -= 1
	scans_changed.emit(scans_remaining)
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

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "current_stage", int(current_stage))
	cfg.set_value("progress", "xp", xp)
	cfg.set_value("progress", "level", level)
	cfg.set_value("progress", "hp", hp)
	cfg.set_value("progress", "gold", gold)
	cfg.set_value("progress", "diamonds", diamonds)
	cfg.set_value("progress", "shard_collected", shard_collected)
	cfg.set_value("progress", "beacon_lit", beacon_lit)
	var items := {}
	for item in inventory:
		items[item.id] = item.quantity
	cfg.set_value("progress", "inventory", items)
	cfg.set_value("progress", "forged_weapons", forged_weapons)
	cfg.set_value("progress", "equipped_weapon", equipped_weapon)
	cfg.set_value("progress", "forged_armors", forged_armors)
	cfg.set_value("progress", "equipped_armor", equipped_armor)
	cfg.set_value("progress", "scans_remaining", scans_remaining)
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
	cfg.set_value("progress", "opened_chests", opened_chests)
	cfg.set_value("progress", "active_cosmetic_ids", active_cosmetic_ids)
	cfg.save(SAVE_PATH)

func load_game() -> bool:
	if not has_save():
		return false
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return false
	reset()
	current_stage = cfg.get_value("progress", "current_stage", QuestStage.SEEK_SPRITE)
	xp = cfg.get_value("progress", "xp", 0)
	level = cfg.get_value("progress", "level", 1)
	hp = cfg.get_value("progress", "hp", MAX_HP_BASE)
	shard_collected = cfg.get_value("progress", "shard_collected", false)
	beacon_lit = cfg.get_value("progress", "beacon_lit", false)
	hp = clampi(hp, 0, max_hp)
	var items: Dictionary = cfg.get_value("progress", "inventory", {})
	for item in inventory:
		if items.has(item.id):
			item.quantity = maxi(0, int(items[item.id]))
	forged_weapons.clear()
	var saved_weapons = cfg.get_value("progress", "forged_weapons", [])
	if saved_weapons is Array:
		for weapon in saved_weapons:
			if weapon is Dictionary and weapon.has("id"):
				forged_weapons.append(weapon.duplicate(true))
	var saved_equipped = cfg.get_value("progress", "equipped_weapon", {})
	if saved_equipped is Dictionary and saved_equipped.has("id"):
		equipped_weapon = saved_equipped.duplicate(true)
	else:
		equipped_weapon = _get_default_weapon()
	_refresh_skill_slots()
	gold = int(cfg.get_value("progress", "gold",
		int(cfg.get_value("progress", "embers", gold))))
	diamonds = int(cfg.get_value("progress", "diamonds", diamonds))
	gold_changed.emit(gold)
	diamonds_changed.emit(diamonds)
	forged_armors.clear()
	var saved_armors = cfg.get_value("progress", "forged_armors", [])
	if saved_armors is Array:
		for armor in saved_armors:
			if armor is Dictionary and armor.has("id"):
				forged_armors.append(armor.duplicate(true))
	var saved_armor = cfg.get_value("progress", "equipped_armor", {})
	equipped_armor = saved_armor.duplicate(true) \
		if saved_armor is Dictionary and saved_armor.has("id") else {}
	armor_changed.emit(equipped_armor)
	scans_remaining = clampi(
		int(cfg.get_value("progress", "scans_remaining", FREE_SCANS)), 0, MAX_SCANS)
	scans_changed.emit(scans_remaining)
	var saved_customs = cfg.get_value("progress", "boss_customs", {})
	boss_customs = saved_customs.duplicate(true) if saved_customs is Dictionary else {}
	stat_points = int(cfg.get_value("progress", "stat_points", 0))
	var saved_stats = cfg.get_value("progress", "stats", {})
	if saved_stats is Dictionary:
		stat_str = int(saved_stats.get("str", 0))
		stat_dex = int(saved_stats.get("dex", 0))
		stat_vit = int(saved_stats.get("vit", 0))
		stat_luk = int(saved_stats.get("luk", 0))
		stat_end = int(saved_stats.get("end", 0))
	max_hp = max_hp_total()
	# Rebalance heal: bring HP up to the (possibly larger) capacity so the
	# bigger health pool reads immediately after the base-HP change.
	hp = max_hp
	hp_changed.emit(0, hp)
	current_realm = _normalize_realm(str(cfg.get_value("progress", "current_realm", "bramblewood")))
	unlocked_realms.clear()
	var saved_realms = cfg.get_value("progress", "unlocked_realms", [])
	if saved_realms is Array:
		for r in saved_realms:
			unlocked_realms.append(_normalize_realm(str(r)))
	for realm_id in ["bramblewood", "mistfen", "heartwood"]:
		if realm_id not in unlocked_realms:
			unlocked_realms.append(realm_id)
	cosmetics_owned.clear()
	var saved_cos = cfg.get_value("progress", "cosmetics_owned", [])
	if saved_cos is Array:
		for c in saved_cos:
			cosmetics_owned.append(str(c))
	active_sfx_profile = str(cfg.get_value("progress", "active_sfx_profile", "vanilla"))
	active_trail_color = str(cfg.get_value("progress", "active_trail_color", "ffb84d"))
	active_aura_color = str(cfg.get_value("progress", "active_aura_color", "00000000"))
	var saved_fks = cfg.get_value("progress", "boss_first_kills", {})
	boss_first_kills = saved_fks.duplicate(true) if saved_fks is Dictionary else {}
	var saved_chests = cfg.get_value("progress", "opened_chests", {})
	opened_chests = saved_chests.duplicate(true) if saved_chests is Dictionary else {}
	var saved_ids = cfg.get_value("progress", "active_cosmetic_ids", {})
	active_cosmetic_ids = saved_ids.duplicate(true) if saved_ids is Dictionary else {}
	stats_changed.emit()
	hp_changed.emit(hp, hp)
	xp_changed.emit(xp, level)
	stage_changed.emit(current_stage)
	inventory_changed.emit()
	weapon_changed.emit(equipped_weapon)
	return true

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


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

## Active owned id for a cosmetic kind ("" when vanilla).
func active_cosmetic_id_for(kind: String) -> String:
	return str(active_cosmetic_ids.get(kind, ""))
