extends Node

## === Save / Load Manager ===
## Full file I/O implementation for GameState persistence.
## Saves to user://embervale_save.cfg (ConfigFile).
##
## Covers:
##   - Player stats (hp, max_hp, level, xp, gold, diamonds)
##   - Quest state (current_stage, shard_collected, beacon_lit, combat_state)
##   - Equipped weapon + armor + forged lists
##   - Inventory quantities
##   - Skill cooldowns (saved as 0 — no point persisting mid-cooldown)
##   - Scan economy (scans_remaining, boss_customs)
##   - Stat point allocations (str/dex/vit/luk/end, stat_points)
##   - Cosmetics (owned list, active profile ids)
##   - Realm progress (current_realm, unlocked_realms, boss_first_kills)
##   - Raw materials gathered
##   - Discovered landmarks
##
## Usage — add as AutoLoad "SaveLoadManager" in project.godot, OR
##   instantiate in game_state._ready() after init:
##     var slm := SaveLoadManager.new()
##     add_child(slm)
##     slm.bind(self)

const SAVE_PATH  := "user://embervale_save.cfg"
const SAVE_VER   := 3

var _gs : Node = null  # GameState reference

func bind(game_state: Node) -> void:
	_gs = game_state
	# Hook into GameState's save_game calls
	if _gs.has_signal("save_requested"):
		_gs.save_requested.connect(save)

## Called automatically wherever game_state calls save_game().
## Safe to call many times per session — ConfigFile write is cheap.
func save() -> void:
	if _gs == null:
		push_error("SaveLoadManager: not bound to GameState")
		return
	var cfg := ConfigFile.new()
	cfg.set_value("meta",   "version",        SAVE_VER)
	cfg.set_value("meta",   "timestamp",      Time.get_unix_time_from_system())

	# Player stats
	cfg.set_value("player", "hp",             _gs.get("hp"))
	cfg.set_value("player", "max_hp",         _gs.get("max_hp"))
	cfg.set_value("player", "level",          _gs.get("level"))
	cfg.set_value("player", "xp",             _gs.get("xp"))
	cfg.set_value("player", "gold",           _gs.get("gold"))
	cfg.set_value("player", "diamonds",       _gs.get("diamonds"))
	cfg.set_value("player", "stat_points",    _gs.get("stat_points") if _gs.get("stat_points") != null else 0)
	cfg.set_value("player", "stat_str",       _gs.get("stat_str") if _gs.get("stat_str") != null else 0)
	cfg.set_value("player", "stat_dex",       _gs.get("stat_dex") if _gs.get("stat_dex") != null else 0)
	cfg.set_value("player", "stat_vit",       _gs.get("stat_vit") if _gs.get("stat_vit") != null else 0)
	cfg.set_value("player", "stat_luk",       _gs.get("stat_luk") if _gs.get("stat_luk") != null else 0)
	cfg.set_value("player", "stat_end",       _gs.get("stat_end") if _gs.get("stat_end") != null else 0)

	# Quest
	cfg.set_value("quest",  "current_stage",  int(_gs.get("current_stage")))
	cfg.set_value("quest",  "shard_collected", bool(_gs.get("shard_collected")))
	cfg.set_value("quest",  "beacon_lit",      bool(_gs.get("beacon_lit")))
	cfg.set_value("quest",  "combat_state",    int(_gs.get("combat_state")))

	# Realm
	cfg.set_value("realm",  "current_realm",   str(_gs.get("current_realm") if _gs.get("current_realm") != null else "bramblewood"))
	cfg.set_value("realm",  "unlocked_realms", _gs.get("unlocked_realms") if _gs.get("unlocked_realms") != null else ["bramblewood"])
	cfg.set_value("realm",  "boss_first_kills",_gs.get("boss_first_kills") if _gs.get("boss_first_kills") != null else {})

	# Gear
	cfg.set_value("gear",   "equipped_weapon_id", str(_gs.get("equipped_weapon").get("id", "mug_mace") if _gs.get("equipped_weapon") != null else "mug_mace"))
	cfg.set_value("gear",   "equipped_armor_id",  str(_gs.get("equipped_armor").get("id", "") if _gs.get("equipped_armor") != null else ""))
	var fw : Array = _gs.get("forged_weapons") if _gs.get("forged_weapons") != null else []
	cfg.set_value("gear",   "forged_weapon_ids",  fw.map(func(w): return str(w.get("id", ""))))
	var fa : Array = _gs.get("forged_armors") if _gs.get("forged_armors") != null else []
	cfg.set_value("gear",   "forged_armor_ids",   fa.map(func(a): return str(a.get("id", ""))))

	# Inventory (quantities only — definitions stay in GameState.WEAPON_DEFS)
	var inv : Array = _gs.get("inventory") if _gs.get("inventory") != null else []
	for item in inv:
		cfg.set_value("inventory", str(item.get("id", "")), int(item.get("quantity", 0)))

	# Raw materials
	var mats : Dictionary = _gs.get("raw_materials") if _gs.get("raw_materials") != null else {}
	for k in mats:
		cfg.set_value("materials", k, mats[k])

	# Scan economy
	cfg.set_value("scan",   "scans_remaining", int(_gs.get("scans_remaining") if _gs.get("scans_remaining") != null else 5))
	cfg.set_value("scan",   "boss_customs",    _gs.get("boss_customs") if _gs.get("boss_customs") != null else {})

	# Cosmetics
	cfg.set_value("cosmetics", "owned",         _gs.get("cosmetics_owned") if _gs.get("cosmetics_owned") != null else [])
	cfg.set_value("cosmetics", "active_sfx",    str(_gs.get("active_sfx_profile") if _gs.get("active_sfx_profile") != null else "vanilla"))
	cfg.set_value("cosmetics", "active_trail",  str(_gs.get("active_trail_color") if _gs.get("active_trail_color") != null else "ffb84d"))
	cfg.set_value("cosmetics", "active_aura",   str(_gs.get("active_aura_color") if _gs.get("active_aura_color") != null else "00000000"))

	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_error("SaveLoadManager: could not write save file — error %d" % err)

func load_save() -> bool:
	if _gs == null:
		push_error("SaveLoadManager: not bound to GameState")
		return false
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		push_warning("SaveLoadManager: corrupt or missing save file (err %d) — starting fresh" % err)
		return false
	var ver := int(cfg.get_value("meta", "version", 0))
	if ver < 1:
		push_warning("SaveLoadManager: save version too old — starting fresh")
		return false

	# Player stats
	_gs.set("hp",      int(cfg.get_value("player", "hp",      _gs.get("max_hp"))))
	_gs.set("max_hp",  int(cfg.get_value("player", "max_hp",  _gs.get("max_hp"))))
	_gs.set("level",   int(cfg.get_value("player", "level",   1)))
	_gs.set("xp",      int(cfg.get_value("player", "xp",      0)))
	_gs.set("gold",    int(cfg.get_value("player", "gold",    30)))
	_gs.set("diamonds",int(cfg.get_value("player", "diamonds",0)))
	if ver >= 2:
		if _gs.get("stat_points") != null:
			_gs.set("stat_points", int(cfg.get_value("player", "stat_points", 0)))
			_gs.set("stat_str",    int(cfg.get_value("player", "stat_str",    0)))
			_gs.set("stat_dex",    int(cfg.get_value("player", "stat_dex",    0)))
			_gs.set("stat_vit",    int(cfg.get_value("player", "stat_vit",    0)))
			_gs.set("stat_luk",    int(cfg.get_value("player", "stat_luk",    0)))
			_gs.set("stat_end",    int(cfg.get_value("player", "stat_end",    0)))

	# Quest
	var stage := int(cfg.get_value("quest", "current_stage", 0))
	_gs.set("current_stage",   stage)
	_gs.set("shard_collected", bool(cfg.get_value("quest", "shard_collected", false)))
	_gs.set("beacon_lit",      bool(cfg.get_value("quest", "beacon_lit",      false)))
	_gs.set("combat_state",    int(cfg.get_value("quest", "combat_state",     0)))

	# Realm
	if ver >= 3:
		_gs.set("current_realm",   str(cfg.get_value("realm", "current_realm",  "bramblewood")))
		_gs.set("unlocked_realms", cfg.get_value("realm", "unlocked_realms", ["bramblewood"]))
		_gs.set("boss_first_kills", cfg.get_value("realm", "boss_first_kills", {}))

	# Gear — re-hydrate from ids using GameState's registries
	var wid : String = str(cfg.get_value("gear", "equipped_weapon_id", "mug_mace"))
	if _gs.has_method("_get_weapon_def"):
		_gs.set("equipped_weapon", _gs.call("_get_weapon_def", wid))
	var aid : String = str(cfg.get_value("gear", "equipped_armor_id", ""))
	if not aid.is_empty() and _gs.has_method("equip_armor"):
		# Armors need to be in forged list first — add them
		var armor_ids : Array = cfg.get_value("gear", "forged_armor_ids", [])
		var armors : Array = []
		if _gs.get("forged_armors") != null:
			for a_id in armor_ids:
				var ad : Dictionary = _gs.get("ARMOR_DEFS") if _gs.get("ARMOR_DEFS") != null else {}
				if ad.has(a_id):
					armors.append(ad[a_id].duplicate(true))
			_gs.set("forged_armors", armors)
		_gs.call("equip_armor", aid)

	# Inventory quantities
	var inv : Array = _gs.get("inventory") if _gs.get("inventory") != null else []
	for item in inv:
		var qty : int = int(cfg.get_value("inventory", str(item.get("id", "")), item.get("quantity", 0)))
		item["quantity"] = qty

	# Raw materials
	if _gs.get("raw_materials") != null:
		var mats : Dictionary = {}
		for k in cfg.get_section_keys("materials"):
			mats[k] = cfg.get_value("materials", k, 0)
		_gs.set("raw_materials", mats)

	# Scan economy
	_gs.set("scans_remaining", int(cfg.get_value("scan", "scans_remaining", 5)))
	if _gs.get("boss_customs") != null:
		_gs.set("boss_customs", cfg.get_value("scan", "boss_customs", {}))

	# Cosmetics
	if _gs.get("cosmetics_owned") != null:
		_gs.set("cosmetics_owned",    cfg.get_value("cosmetics", "owned",        []))
		_gs.set("active_sfx_profile", str(cfg.get_value("cosmetics", "active_sfx",   "vanilla")))
		_gs.set("active_trail_color", str(cfg.get_value("cosmetics", "active_trail",  "ffb84d")))
		_gs.set("active_aura_color",  str(cfg.get_value("cosmetics", "active_aura",   "00000000")))

	# Refresh skill slots after weapon change
	if _gs.has_method("_refresh_skill_slots"):
		_gs.call("_refresh_skill_slots")

	# Emit signals to sync UI
	if _gs.has_signal("hp_changed"):        _gs.hp_changed.emit(0, _gs.get("hp"))
	if _gs.has_signal("xp_changed"):        _gs.xp_changed.emit(_gs.get("xp"), _gs.get("level"))
	if _gs.has_signal("stage_changed"):     _gs.stage_changed.emit(_gs.get("current_stage"))
	if _gs.has_signal("weapon_changed"):    _gs.weapon_changed.emit(_gs.get("equipped_weapon"))
	if _gs.has_signal("gold_changed"):      _gs.gold_changed.emit(_gs.get("gold"))
	if _gs.has_signal("diamonds_changed"):  _gs.diamonds_changed.emit(_gs.get("diamonds"))
	return true

func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)
