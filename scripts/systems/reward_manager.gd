extends Node

## === RewardManager — Centralised Reward Dispatcher (AutoLoad) ===
##
## All rewards in the game flow through here:
##   - Enemy kills → xp + loot
##   - Boss kills   → full drop table + diamonds + scan token
##   - Chest open   → loot table roll
##   - Quest stage  → milestone rewards
##   - Daily login  → streak bonus
##
## Signals let HUD / FloatingText react without being coupled to entities.
##
## Usage:
##   RewardManager.grant_enemy_kill(realm_id, tier, xp_bonus)
##   RewardManager.grant_boss_kill(boss_id, first_kill, realm_id)
##   RewardManager.grant_chest(chest_tier, realm_id)
##   RewardManager.grant_drops(drops_array)
##   RewardManager.grant_quest_stage(stage_index)
##   RewardManager.check_daily_bonus()

signal reward_granted(summary: Dictionary)   # { gold, xp, diamonds, items, materials, loot_context }
signal quest_reward_granted(completion_id: String, title: String, summary: Dictionary)
signal level_up_triggered(new_level: int)
signal first_kill_reward(boss_id: String, diamonds: int)
signal boss_reward_choice_available(boss_id: String, choices: Array)
signal daily_bonus_granted(streak: int, gold: int)

const XP_PER_LEVEL_BASE := 100
const XP_SCALE           := 1.35   # each level needs 35% more XP
const OBJECTIVE_REWARD_DROPS := {
	"kill": [
		{"type": "gold", "id": "", "quantity": 20, "rarity": 0},
		{"type": "xp", "id": "", "quantity": 35, "rarity": 0},
	],
	"gather": [
		{"type": "gold", "id": "", "quantity": 12, "rarity": 0},
		{"type": "xp", "id": "", "quantity": 20, "rarity": 0},
	],
	"reach": [
		{"type": "gold", "id": "", "quantity": 20, "rarity": 0},
		{"type": "xp", "id": "", "quantity": 30, "rarity": 0},
	],
	"craft": [
		{"type": "gold", "id": "", "quantity": 18, "rarity": 0},
		{"type": "xp", "id": "", "quantity": 30, "rarity": 0},
	],
	"equip": [
		{"type": "gold", "id": "", "quantity": 15, "rarity": 0},
		{"type": "xp", "id": "", "quantity": 25, "rarity": 0},
	],
	"upgrade": [
		{"type": "gold", "id": "", "quantity": 25, "rarity": 0},
		{"type": "xp", "id": "", "quantity": 45, "rarity": 0},
	],
	"open_chest": [
		{"type": "gold", "id": "", "quantity": 10, "rarity": 0},
		{"type": "xp", "id": "", "quantity": 15, "rarity": 0},
	],
}

@onready var _gs : Node = get_node_or_null("/root/GameState")

func _ready() -> void:
	# The menu triggers this after GameState has loaded or reset the selected
	# profile. RewardManager never reads or writes the save file directly.
	if _gs != null and _gs.has_signal("objective_completed") \
			and not _gs.objective_completed.is_connected(_on_objective_completed):
		_gs.objective_completed.connect(_on_objective_completed)

# ─────────────────────────────────────────────────────────────────────────────
# Enemy kill
# ─────────────────────────────────────────────────────────────────────────────

func grant_enemy_kill(realm_id: String = "bramblewood",
		tier: String = "normal", xp_bonus: int = 0) -> void:
	var table := LootTable.for_enemy(realm_id, tier)
	var drops := table.roll(realm_id, _current_stage())
	drops.append({"type": "xp", "id": "", "quantity": _enemy_xp(tier) + xp_bonus, "rarity": 0})
	grant_drops(drops)
	var camp := get_node_or_null("/root/CampProgression")
	if camp != null:
		camp.record_objective(realm_id, "kills")

func _enemy_xp(tier: String) -> int:
	match tier:
		"elite": return randi_range(22, 40)
		"hard":  return randi_range(12, 22)
		_:       return randi_range(6,  14)

# ─────────────────────────────────────────────────────────────────────────────
# Boss kill
# ─────────────────────────────────────────────────────────────────────────────

func grant_boss_kill(boss_id: String, first_kill: bool, realm_id: String = "bramblewood") -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("record_golden_route_signal"):
		scene.call("record_golden_route_signal", "reward_reveal")
	if _gs != null and _gs.has_method("record_activity"):
		_gs.call("record_activity", "BOSS DEFEATED · %s · %s" % [boss_id, realm_id])
	var table : LootTable
	match boss_id:
		"hushling_matriarch":       table = LootTable.boss_matriarch()
		"bramblewood_thornwarden":  table = LootTable.boss_bramblewood()
		"mistfen_siltcrawler":      table = LootTable.boss_mistfen()
		"heartwood_cindercolossus": table = LootTable.boss_heartwood()
		"moonfen_voidweaver":       table = LootTable.boss_moonfen()
		"whispergrove_root_harrow", "boss_whispergrove_root_harrow": table = LootTable.boss_matriarch()
		"bramblewood_thorn_regent", "bramblewood_briar_widow", \
		"biome_bramblewood_thorn_regent", "biome_bramblewood_briar_widow": table = LootTable.boss_bramblewood()
		"mistfen_fogmaw", "biome_mistfen_fogmaw": table = LootTable.boss_mistfen()
		"heartwood_cinderhart", "heartwood_ash_bellower", \
		"biome_heartwood_cinderhart", "biome_heartwood_ash_bellower": table = LootTable.boss_heartwood()
		"moonfen_tide_oracle", "moonfen_lunar_leviathan", \
		"biome_moonfen_tide_oracle", "biome_moonfen_lunar_leviathan": table = LootTable.boss_moonfen()
		_:                          table = LootTable.chest_boss()

	var drops := table.roll(realm_id, _current_stage())
	grant_drops(drops)
	var camp := get_node_or_null("/root/CampProgression")
	if camp != null:
		camp.record_objective(realm_id, "boss")
		if first_kill and not bool(camp.claimed_rewards.get("boss_%s" % boss_id, false)):
			camp.claimed_rewards["boss_%s" % boss_id] = true
			_gs.call("add_material", "camp_ember", 1)
			_gs.call("save_game")
	if not first_kill:
		var catalog := preload("res://scripts/systems/boss_reward_catalog.gd")
		var choices: Array[Dictionary] = catalog.choices_for(boss_id)
		if not choices.is_empty():
			if _gs != null and _gs.has_method("record_activity"):
				_gs.call("record_activity", "BOSS REWARDS AVAILABLE · %d choices" % choices.size())
			boss_reward_choice_available.emit(boss_id, choices)

	# First-kill diamond bonus + scan token
	if first_kill and _gs != null:
		var diamond_bonus := 5
		if _gs.has_method("record_activity"):
			_gs.call("record_activity", "BOSS FIRST KILL · %s" % boss_id)
		_gs.set("diamonds", int(_gs.get("diamonds") if _gs.get("diamonds") != null else 0) + diamond_bonus)
		# Earn a scan token
		var scans := int(_gs.get("scans_remaining") if _gs.get("scans_remaining") != null else 0)
		_gs.set("scans_remaining", mini(scans + 1, 9))
		first_kill_reward.emit(boss_id, diamond_bonus)
		FloatingText.spawn_on_entity(
			get_tree().current_scene,
			"FIRST KILL +%d DIAMONDS" % diamond_bonus,
			Color(1.0, 0.88, 0.28)) if get_tree().current_scene != null else null

	# Mark first kill in GameState
	if _gs != null:
		var kills : Dictionary = _gs.get("boss_first_kills") if _gs.get("boss_first_kills") != null else {}
		kills[boss_id] = true
		_gs.set("boss_first_kills", kills)
		if _gs.has_method("save_game"):
			_gs.call("save_game")
		if _gs.has_method("flush_save"):
			_gs.call("flush_save")

# ─────────────────────────────────────────────────────────────────────────────
# Chest
# ─────────────────────────────────────────────────────────────────────────────

func grant_chest(chest_tier: String = "common", realm_id: String = "bramblewood",
		source_id: String = "", source_label: String = "",
		persistent: bool = false) -> Dictionary:
	if _gs == null:
		_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		return {}
	if _gs != null and _gs.has_method("record_activity"):
		_gs.call("record_activity", "CHEST OPENED · %s · %s" % [chest_tier, realm_id])
	var drops := roll_chest_drops(chest_tier, realm_id)
	return grant_drops(drops, {
		"source": "chest",
		"source_id": source_id,
		"source_label": source_label if not source_label.is_empty() else "Chest",
		"persistent": persistent,
	})

## Roll a chest table without mutating GameState. Physical-delivery callers
## (ChestNode) use this so they can persist the exact roll before any grant is
## applied and spawn one pickup per drop.
func roll_chest_drops(chest_tier: String = "common",
		realm_id: String = "bramblewood") -> Array:
	var table : LootTable
	match chest_tier:
		"rare":  table = LootTable.chest_rare()
		"boss":  table = LootTable.chest_boss()
		_:       table = LootTable.chest_common()
	return table.roll(realm_id, _current_stage())

## Display-only summary of a chest roll. Shows the full contents for the reveal
## but never mutates GameState — `preview` tells the HUD not to announce a
## payout, because the grants happen later as each pickup is collected.
static func chest_roll_preview(drops: Array) -> Dictionary:
	var summary: Dictionary = {"gold": 0, "xp": 0, "diamonds": 0,
		"items": [], "materials": [], "weapons": [], "armors": [],
		"loot_context": [], "granted": false, "preview": true}
	for raw in drops:
		if not raw is Dictionary:
			continue
		var drop: Dictionary = raw
		var did := str(drop.get("id", ""))
		var qty := int(drop.get("quantity", 1))
		var rarity := int(drop.get("rarity", 0))
		match str(drop.get("type", "")):
			"gold":     summary["gold"] = int(summary["gold"]) + qty
			"xp":       summary["xp"] = int(summary["xp"]) + qty
			"diamond":  summary["diamonds"] = int(summary["diamonds"]) + qty
			"item":     summary["items"].append({"id": did, "qty": qty, "rarity": rarity})
			"material": summary["materials"].append({"id": did, "qty": qty})
			"weapon":   summary["weapons"].append({"id": did, "rarity": rarity})
			"armor":    summary["armors"].append({"id": did, "rarity": rarity})
	return summary

func announce_chest_roll(chest_tier: String, realm_id: String, source_id: String,
		source_label: String, drops: Array, persistent: bool) -> void:
	var summary := chest_roll_preview(drops)
	summary["source"] = "chest"
	summary["source_id"] = source_id
	summary["source_label"] = source_label if not source_label.is_empty() else "Chest"
	summary["persistent"] = persistent
	summary["chest_tier"] = chest_tier
	summary["realm"] = realm_id
	reward_granted.emit(summary)

# ─────────────────────────────────────────────────────────────────────────────
# Grant drops array (core dispatcher)
# ─────────────────────────────────────────────────────────────────────────────

func grant_drops(drops: Array, metadata: Dictionary = {}) -> Dictionary:
	if _gs == null:
		_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		return {}

	var summary: Dictionary = { "gold": 0, "xp": 0, "diamonds": 0,
		"items": [], "materials": [], "weapons": [], "armors": [],
		"loot_context": [], "granted": true }

	for drop in drops:
		var dtype    := str(drop.get("type", "gold"))
		var did      := str(drop.get("id", ""))
		var qty      := int(drop.get("quantity", 1))
		var rarity   := int(drop.get("rarity", 0))
		if _gs.has_method("record_activity"):
			var label := dtype.to_upper()
			if not did.is_empty():
				label += " · " + did.replace("_", " ").capitalize()
			_gs.call("record_activity", "DROP · %s ×%d" % [label, qty])

		match dtype:
			"gold":
				var cur := int(_gs.get("gold") if _gs.get("gold") != null else 0)
				_gs.set("gold", cur + qty)
				summary["gold"] = int(summary["gold"]) + qty
				if _gs.has_signal("gold_changed"):
					_gs.gold_changed.emit(_gs.get("gold"))

			"xp":
				_grant_xp(qty)
				summary["xp"] = int(summary["xp"]) + qty

			"diamond":
				var cur := int(_gs.get("diamonds") if _gs.get("diamonds") != null else 0)
				_gs.set("diamonds", cur + qty)
				summary["diamonds"] = int(summary["diamonds"]) + qty
				if _gs.has_signal("diamonds_changed"):
					_gs.diamonds_changed.emit(_gs.get("diamonds"))

			"item":
				if _gs.has_method("add_loot"):
					_gs.call("add_loot", did, qty, "", qty)
				summary["items"].append({"id": did, "qty": qty, "rarity": rarity})
				_add_loot_context(summary, dtype, did)

			"material":
				# Material rewards must use GameState's canonical mutation boundary so
				# validation, persistence coalescing, and inventory UI signals stay in
				# sync. Invalid or non-positive drops are not granted.
				if qty <= 0 or not GameState.MATERIAL_DEFS.has(did) \
						or not _gs.has_method("add_material"):
					continue
				_gs.call("add_material", did, qty)
				summary["materials"].append({"id": did, "qty": qty})
				_add_loot_context(summary, dtype, did)

			"weapon":
				# Constants are not instance properties; read them from the
				# GameState class directly or the lookup silently yields null and
				# the weapon is announced without ever being granted.
				if not did.is_empty() and _gs.has_method("add_weapon") \
						and GameState.WEAPON_DEFS.has(did):
					_gs.call("add_weapon",
						(GameState.WEAPON_DEFS[did] as Dictionary).duplicate(true), true, "")
					summary["weapons"].append({"id": did, "rarity": rarity})
					_add_loot_context(summary, dtype, did)

			"armor":
				if not did.is_empty() and _gs.has_method("add_armor") \
						and GameState.ARMOR_DEFS.has(did):
					_gs.call("add_armor",
						(GameState.ARMOR_DEFS[did] as Dictionary).duplicate(true), true)
					summary["armors"].append({"id": did, "rarity": rarity})
					_add_loot_context(summary, dtype, did)

			"relic":
				pass  # Handled by ScanManager; relics need forge flow

	# Save after all drops applied
	if _gs.has_method("save_game"):
		_gs.call("save_game")

	for key in metadata:
		summary[key] = metadata[key]
	reward_granted.emit(summary)
	return summary

func _add_loot_context(summary: Dictionary, drop_type: String, drop_id: String) -> void:
	var context := describe_drop_context(drop_type, drop_id)
	if context.is_empty():
		return
	var contexts: Array = summary.get("loot_context", [])
	if not contexts.has(context):
		contexts.append(context)
	summary["loot_context"] = contexts

static func describe_drop_context(drop_type: String, drop_id: String) -> String:
	## Player-facing purpose text for the reward toast and future reward panels.
	## Keep this descriptive, never an implied promise of extra stats or drops.
	match drop_type:
		"weapon":
			return "%s · new build option" % _pretty_drop_id(drop_id)
		"armor":
			return "%s · compare in Satchel" % _pretty_drop_id(drop_id)
		"material":
			var realm := _material_realm(drop_id)
			var use := _material_use(drop_id)
			return "%s · %s%s" % [_pretty_drop_id(drop_id), use, " · " + realm + " realm" if not realm.is_empty() else ""]
		"item":
			return "%s · consumable" % _pretty_drop_id(drop_id)
	return ""

static func _pretty_drop_id(drop_id: String) -> String:
	return drop_id.replace("_", " ").capitalize()

static func _material_realm(drop_id: String) -> String:
	match drop_id:
		"bramble_wood", "moss_fiber", "beast_hide": return "Bramblewood"
		"fen_reed", "spore_dust": return "Mistfen"
		"emberstone", "monster_core": return "Heartwood"
	return ""

static func _material_use(drop_id: String) -> String:
	match drop_id:
		"bramble_wood", "fen_reed", "emberstone": return "crafting material"
		"moss_fiber", "beast_hide": return "armor crafting"
		"iron_shard", "monster_core", "crystal_fragment": return "upgrade material"
		"spore_dust": return "alchemy material"
	return "crafting material"

# ─────────────────────────────────────────────────────────────────────────────
# XP + levelling
# ─────────────────────────────────────────────────────────────────────────────

func _grant_xp(amount: int) -> void:
	if _gs == null:
		return
	var old_xp   := int(_gs.get("xp")    if _gs.get("xp")    != null else 0)
	var level    := int(_gs.get("level")  if _gs.get("level")  != null else 1)
	var new_xp   := old_xp + amount
	_gs.set("xp", new_xp)
	if _gs.has_signal("xp_changed"):
		_gs.xp_changed.emit(new_xp, level)

	# Check for level-up(s)
	while new_xp >= xp_needed_for_next_level(level):
		new_xp -= xp_needed_for_next_level(level)
		level  += 1
		_gs.set("level", level)
		_gs.set("xp",    new_xp)
		var max_hp_cur := int(_gs.get("max_hp") if _gs.get("max_hp") != null else 100)
		_gs.set("max_hp", max_hp_cur + 8)
		_gs.set("hp",     mini(int(_gs.get("hp") if _gs.get("hp") != null else 100), max_hp_cur + 8))
		if _gs.has_signal("level_up"):
			_gs.level_up.emit(level, 1)
		level_up_triggered.emit(level)

func xp_needed_for_next_level(level: int) -> int:
	return int(float(XP_PER_LEVEL_BASE) * pow(XP_SCALE, level - 1))

# ─────────────────────────────────────────────────────────────────────────────
# Quest stage milestone rewards
# ─────────────────────────────────────────────────────────────────────────────

func grant_quest_stage(stage: int) -> Dictionary:
	if _gs == null:
		_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		return {}
	var claim_key := str(stage)
	if _is_quest_claimed(claim_key):
		return {}
	var drops : Array[Dictionary] = []
	match stage:
		1:  # CLAIM_SHARD
			drops = [
				{"type":"gold", "id":"", "quantity":25, "rarity":0},
				{"type":"xp",   "id":"", "quantity":50, "rarity":0},
			]
		2:  # LIGHT_BEACON
			drops = [
				{"type":"gold",     "id":"", "quantity":50, "rarity":0},
				{"type":"xp",       "id":"", "quantity":120, "rarity":0},
				{"type":"diamond",  "id":"", "quantity":2,  "rarity":2},
			]
		3:  # COMPLETE
			drops = [
				{"type":"gold",     "id":"", "quantity":100, "rarity":0},
				{"type":"xp",       "id":"", "quantity":300, "rarity":0},
				{"type":"diamond",  "id":"", "quantity":5,  "rarity":3},
			]
	if drops.is_empty():
		return {}
	_mark_quest_claim(claim_key)
	if _gs.has_method("record_activity"):
		_gs.call("record_activity", "QUEST REWARD · STAGE %d" % stage)
	var title := "Chapter %d complete" % stage
	if _gs.has_method("get_quest_copy"):
		var copy: Variant = _gs.call("get_quest_copy", stage)
		if copy is Dictionary:
			title = str((copy as Dictionary).get("title", title))
	var summary := grant_drops(drops, {
		"source": "quest_stage",
		"source_id": "stage:%d" % stage,
		"source_label": title,
		"completion_kind": "quest_stage",
	})
	if summary.is_empty():
		_unmark_quest_claim(claim_key)
		return {}
	quest_reward_granted.emit(claim_key, title, summary)
	return summary

func _on_objective_completed(objective_id: String) -> void:
	if _gs == null or not _gs.has_method("get_objective"):
		return
	var objective_variant: Variant = _gs.call("get_objective", objective_id)
	if not objective_variant is Dictionary:
		return
	var objective: Dictionary = objective_variant
	var objective_type := str(objective.get("type", ""))
	if not OBJECTIVE_REWARD_DROPS.has(objective_type):
		return
	var claim_key := "objective:%s" % objective_id
	if _is_quest_claimed(claim_key):
		return
	var drops: Array = (OBJECTIVE_REWARD_DROPS[objective_type] as Array).duplicate(true)
	if drops.is_empty():
		return
	_mark_quest_claim(claim_key)
	var title := str(objective.get("description", "Objective complete"))
	if _gs.has_method("record_activity"):
		_gs.call("record_activity", "QUEST REWARD · OBJECTIVE %s" % objective_id)
	var summary := grant_drops(drops, {
		"source": "quest_objective",
		"source_id": objective_id,
		"source_label": title,
		"completion_kind": "quest_objective",
	})
	if summary.is_empty():
		_unmark_quest_claim(claim_key)
		return
	quest_reward_granted.emit(claim_key, title, summary)

func _is_quest_claimed(claim_key: String) -> bool:
	if _gs == null:
		return false
	var claims: Variant = _gs.get("quest_reward_claims")
	return claims is Dictionary and bool((claims as Dictionary).get(claim_key, false))

func _mark_quest_claim(claim_key: String) -> void:
	if _gs == null:
		return
	var claims: Dictionary = _gs.get("quest_reward_claims") \
		if _gs.get("quest_reward_claims") is Dictionary else {}
	claims[claim_key] = true
	_gs.set("quest_reward_claims", claims)

func _unmark_quest_claim(claim_key: String) -> void:
	if _gs == null:
		return
	var claims: Variant = _gs.get("quest_reward_claims")
	if claims is Dictionary:
		(claims as Dictionary).erase(claim_key)

# ─────────────────────────────────────────────────────────────────────────────
# Daily login bonus
# ─────────────────────────────────────────────────────────────────────────────

func check_daily_bonus() -> void:
	if _gs == null or not _gs.has_method("get_daily_bonus_state"):
		return
	var saved_state: Dictionary = _gs.call("get_daily_bonus_state")
	var last_ts  := int(saved_state.get("last_claim", 0))
	var streak   := int(saved_state.get("streak", 0))
	var now_ts   := int(Time.get_unix_time_from_system())
	var day_secs := 86400

	if now_ts - last_ts < day_secs:
		return  # Already claimed today

	# Missed a day — reset streak
	if now_ts - last_ts > day_secs * 2:
		streak = 0

	streak += 1
	var gold_bonus := 20 + streak * 10
	if _gs != null and _gs.has_method("record_activity"):
		_gs.call("record_activity", "DAILY BONUS · DAY %d" % streak)
	grant_drops([
		{"type":"gold",    "id":"", "quantity":gold_bonus, "rarity":0},
		{"type":"xp",      "id":"", "quantity":30 + streak * 8, "rarity":0},
	])

	_gs.call("set_daily_bonus_state", now_ts, streak)
	_gs.call("flush_save")
	daily_bonus_granted.emit(streak, gold_bonus)

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

func _current_stage() -> int:
	if _gs == null:
		return 0
	return int(_gs.get("current_stage") if _gs.get("current_stage") != null else 0)
