extends Node
class_name RewardManager

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

signal reward_granted(summary: Dictionary)   # { gold, xp, diamonds, items, materials }
signal level_up_triggered(new_level: int)
signal first_kill_reward(boss_id: String, diamonds: int)
signal daily_bonus_granted(streak: int, gold: int)

const XP_PER_LEVEL_BASE := 100
const XP_SCALE           := 1.35   # each level needs 35% more XP

@onready var _gs : Node = get_node_or_null("/root/GameState")

func _ready() -> void:
	# Check daily bonus on game start
	call_deferred("check_daily_bonus")

# ─────────────────────────────────────────────────────────────────────────────
# Enemy kill
# ─────────────────────────────────────────────────────────────────────────────

func grant_enemy_kill(realm_id: String = "bramblewood",
		tier: String = "normal", xp_bonus: int = 0) -> void:
	var table := LootTable.for_enemy(realm_id, tier)
	var drops := table.roll(realm_id, _current_stage())
	drops.append({"type": "xp", "id": "", "quantity": _enemy_xp(tier) + xp_bonus, "rarity": 0})
	grant_drops(drops)

func _enemy_xp(tier: String) -> int:
	match tier:
		"elite": return randi_range(22, 40)
		"hard":  return randi_range(12, 22)
		_:       return randi_range(6,  14)

# ─────────────────────────────────────────────────────────────────────────────
# Boss kill
# ─────────────────────────────────────────────────────────────────────────────

func grant_boss_kill(boss_id: String, first_kill: bool, realm_id: String = "bramblewood") -> void:
	var table : LootTable
	match boss_id:
		"hushling_matriarch", "moonfen_matriarch":
			table = LootTable.boss_matriarch()
		_:
			table = LootTable.chest_boss()

	var drops := table.roll(realm_id, _current_stage())
	grant_drops(drops)

	# First-kill diamond bonus + scan token
	if first_kill and _gs != null:
		var diamond_bonus := 5
		_gs.set("diamonds", int(_gs.get("diamonds") if _gs.get("diamonds") != null else 0) + diamond_bonus)
		# Earn a scan token
		var scans := int(_gs.get("scans_remaining") if _gs.get("scans_remaining") != null else 0)
		_gs.set("scans_remaining", mini(scans + 1, 9))
		first_kill_reward.emit(boss_id, diamond_bonus)
		FloatingText.spawn_on_entity(
			get_tree().current_scene,
			"FIRST KILL +%d 💎" % diamond_bonus,
			Color(1.0, 0.88, 0.28)) if get_tree().current_scene != null else null

	# Mark first kill in GameState
	if _gs != null:
		var kills : Dictionary = _gs.get("boss_first_kills") if _gs.get("boss_first_kills") != null else {}
		kills[boss_id] = true
		_gs.set("boss_first_kills", kills)
		if _gs.has_method("save_game"):
			_gs.call("save_game")

# ─────────────────────────────────────────────────────────────────────────────
# Chest
# ─────────────────────────────────────────────────────────────────────────────

func grant_chest(chest_tier: String = "common", realm_id: String = "bramblewood") -> void:
	var table : LootTable
	match chest_tier:
		"rare":  table = LootTable.chest_rare()
		"boss":  table = LootTable.chest_boss()
		_:       table = LootTable.chest_common()
	var drops := table.roll(realm_id, _current_stage())
	grant_drops(drops)

# ─────────────────────────────────────────────────────────────────────────────
# Grant drops array (core dispatcher)
# ─────────────────────────────────────────────────────────────────────────────

func grant_drops(drops: Array) -> void:
	if _gs == null:
		_gs = get_node_or_null("/root/GameState")
	if _gs == null:
		return

	var summary := { "gold": 0, "xp": 0, "diamonds": 0, "items": [], "materials": [], "weapons": [], "armors": [] }

	for drop in drops:
		var dtype    := str(drop.get("type", "gold"))
		var did      := str(drop.get("id", ""))
		var qty      := int(drop.get("quantity", 1))
		var rarity   := int(drop.get("rarity", 0))

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

			"material":
				var mats : Dictionary = _gs.get("raw_materials") if _gs.get("raw_materials") != null else {}
				mats[did] = int(mats.get(did, 0)) + qty
				_gs.set("raw_materials", mats)
				summary["materials"].append({"id": did, "qty": qty})

			"weapon":
				if not did.is_empty() and _gs.has_method("add_weapon"):
					var wdefs : Dictionary = _gs.get("WEAPON_DEFS") if _gs.get("WEAPON_DEFS") != null else {}
					if wdefs.has(did):
						_gs.call("add_weapon", wdefs[did].duplicate(true), true, "")
				summary["weapons"].append({"id": did, "rarity": rarity})

			"armor":
				if not did.is_empty() and _gs.has_method("add_armor"):
					var adefs : Dictionary = _gs.get("ARMOR_DEFS") if _gs.get("ARMOR_DEFS") != null else {}
					if adefs.has(did):
						_gs.call("add_armor", adefs[did].duplicate(true), true)
				summary["armors"].append({"id": did, "rarity": rarity})

			"relic":
				pass  # Handled by ScanManager; relics need forge flow

	# Save after all drops applied
	if _gs.has_method("save_game"):
		_gs.call("save_game")

	reward_granted.emit(summary)

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

func grant_quest_stage(stage: int) -> void:
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
	if not drops.is_empty():
		grant_drops(drops)

# ─────────────────────────────────────────────────────────────────────────────
# Daily login bonus
# ─────────────────────────────────────────────────────────────────────────────

const DAILY_BONUS_KEY := "last_daily_bonus"
const DAILY_STREAK_KEY := "daily_streak"

func check_daily_bonus() -> void:
	var cfg := ConfigFile.new()
	var save_path := "user://embervale_save.cfg"
	if cfg.load(save_path) != OK:
		return
	var last_ts  := int(cfg.get_value("daily", DAILY_BONUS_KEY,  0))
	var streak   := int(cfg.get_value("daily", DAILY_STREAK_KEY, 0))
	var now_ts   := int(Time.get_unix_time_from_system())
	var day_secs := 86400

	if now_ts - last_ts < day_secs:
		return  # Already claimed today

	# Missed a day — reset streak
	if now_ts - last_ts > day_secs * 2:
		streak = 0

	streak += 1
	var gold_bonus := 20 + streak * 10
	grant_drops([
		{"type":"gold",    "id":"", "quantity":gold_bonus, "rarity":0},
		{"type":"xp",      "id":"", "quantity":30 + streak * 8, "rarity":0},
	])

	cfg.set_value("daily", DAILY_BONUS_KEY,  now_ts)
	cfg.set_value("daily", DAILY_STREAK_KEY, streak)
	cfg.save(save_path)
	daily_bonus_granted.emit(streak, gold_bonus)

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

func _current_stage() -> int:
	if _gs == null:
		return 0
	return int(_gs.get("current_stage") if _gs.get("current_stage") != null else 0)
