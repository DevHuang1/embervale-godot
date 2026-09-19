extends SceneTree

## Persistence contract for the canonical GameState/SaveService boundary.
## This intentionally uses /tmp so it cannot touch a developer's real save.

const SAVE_PATH: String = "/tmp/embervale_persistence_contract.cfg"
const SAVE_SERVICE := preload("res://scripts/systems/save_service.gd")

var _game_state: GameState
var _failures: int = 0
var service: SaveService

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("PERSISTENCE CONTRACT: " + message)

func _write_config(values: Dictionary) -> bool:
	var config := ConfigFile.new()
	for section in values:
		for key in values[section]:
			config.set_value(str(section), str(key), values[section][key])
	return config.save(SAVE_PATH) == OK

func _run() -> void:
	_game_state = root.get_node_or_null("/root/GameState") as GameState
	_check(_game_state != null, "GameState autoload is missing")
	if _game_state == null:
		quit(1)
		return

	_game_state.save_path = SAVE_PATH
	_game_state.delete_save()
	_game_state.reset()
	service = SAVE_SERVICE.new()

	# Normal mutations are coalesced until an explicit flush.
	_game_state.add_material("iron_shard", 2)
	_check(_game_state.is_save_dirty(), "mutation did not mark save dirty")
	_check(not FileAccess.file_exists(SAVE_PATH),
		"coalesced mutation wrote before the flush boundary")
	_check(_game_state.flush_save(), "initial forced save failed")
	_check(FileAccess.file_exists(SAVE_PATH), "forced save did not create primary")

	# The persisted container is encrypted: a plaintext reader must not be able
	# to see the document, while the service and GameState still round-trip it.
	_check(service.is_encrypted(SAVE_PATH), "flushed save was not encrypted at rest")
	var raw_bytes := FileAccess.get_file_as_bytes(SAVE_PATH)
	_check(raw_bytes.size() > 0 and raw_bytes[0] != 0x5B,
		"encrypted save still begins like a plaintext ConfigFile document")

	# Round-trip preserves damaged HP, content, and progression state.
	_game_state.hp = 37
	_game_state.stat_vit = 4
	_game_state.max_hp = _game_state.max_hp_total()
	_game_state.gold = 111
	_game_state.current_stage = _game_state.QuestStage.CLAIM_SHARD
	_game_state.route_checkpoint_id = "hushling_cleared"
	_game_state.raw_materials["iron_shard"] = 7
	_game_state.last_daily_bonus = 123
	_game_state.daily_streak = 3
	var story: Node = root.get_node_or_null("/root/StoryManager")
	if story != null:
		story.call("trigger_event", "intro_grove")
	var camp: Node = root.get_node_or_null("/root/CampProgression")
	if camp != null:
		camp.set("camp_level", 2)
		var facilities: Dictionary = camp.get("facilities")
		facilities["forge"] = true
		camp.set("facilities", facilities)
	_check(_game_state.cloud_sync_queue.enqueue("persistence-contract", "test_action",
		{"item_id": "ember_shard"}), "cloud queue fixture could not be enqueued")
	_game_state.save_game()
	_check(_game_state.flush_save(), "round-trip save failed")
	_game_state.reset()
	_check(_game_state.load_game(), "round-trip load failed")
	_check(_game_state.hp == 37, "saved HP was replaced with full health")
	_check(_game_state.max_hp == _game_state.max_hp_total(),
		"stat-derived max HP was not restored")
	_check(_game_state.current_stage == _game_state.QuestStage.CLAIM_SHARD,
		"quest stage did not survive round-trip")
	_check(_game_state.route_checkpoint_id == "hushling_cleared",
		"route checkpoint did not survive round-trip")
	_check(_game_state.get_material_qty("iron_shard") == 7,
		"material quantity did not survive round-trip")
	_check(_game_state.last_daily_bonus == 123 and _game_state.daily_streak == 3,
		"daily bonus state did not survive round-trip")
	_check(_game_state.cloud_sync_queue.pending().size() == 1,
		"cloud sync queue did not survive round-trip")
	_check(story == null or bool(story.call("has_triggered", "intro_grove")),
		"story state did not survive round-trip")
	_check(camp == null or int(camp.get("camp_level")) == 2
		and bool(camp.call("facility_unlocked", "forge")),
		"camp state did not survive round-trip")

	# Bramblewood expansion state, Rootway unlock, and checkpoint survive a
	# round-trip as one additive save payload.
	_game_state.reset()
	_game_state.onboarding_completed = true
	_game_state.gold = 111
	_game_state.route_checkpoint_id = "rootway_shortcut"
	_game_state.route_respawn_position = Vector2(172, -208)
	_game_state.bramblewood_expansion = {
		"version": 1,
		"started": true,
		"completed": true,
		"discovered_pockets": ["split_road_oak", "rootcut_gully", "hollow_camp",
			"beacon_breach", "rootbound_court"],
	}
	_game_state.quest_reward_claims["bramblewood_expansion_complete"] = true
	if camp != null:
		camp.set("camp_level", 2)
		camp.set("facilities", {"rootway_beacon": true})
		camp.set("claimed_rewards", {"facility_rootway_beacon": true})
	_game_state.save_game()
	_check(_game_state.flush_save(), "expansion round-trip save failed")
	_game_state.reset()
	_check(_game_state.load_game(), "expansion round-trip load failed")
	var expansion_snapshot: Dictionary = _game_state.bramblewood_expansion_snapshot()
	_check(bool(expansion_snapshot.get("completed", false))
		and expansion_snapshot.get("discovered_pockets", []).size() == 5,
		"expansion state did not survive round-trip")
	_check(_game_state.route_checkpoint_id == "rootway_shortcut"
		and _game_state.route_respawn_position == Vector2(172, -208),
		"Rootway checkpoint did not survive round-trip")
	_check(camp == null or bool(camp.call("facility_unlocked", "rootway_beacon"))
		and camp.call("is_shortcut_unlocked", "bramblewood", "rootway_shortcut"),
		"Rootway facility did not survive round-trip")

	# Mini-map discovery cells survive a round-trip, stay bounded, and reject
	# duplicates or malformed entries instead of growing the save.
	_check(_game_state.mark_explored("bramblewood", 17),
		"first explored cell was not recorded")
	_check(not _game_state.mark_explored("bramblewood", 17),
		"duplicate explored cell was accepted twice")
	_check(not _game_state.mark_explored("bramblewood", -3),
		"negative explored cell was accepted")
	_game_state.mark_explored("bramblewood", 42)
	_check(_game_state.is_explored("bramblewood", 17)
		and not _game_state.is_explored("mistfen", 17),
		"explored cell lookup leaked across realms")
	_game_state.save_game()
	_check(_game_state.flush_save(), "explored-cell save failed")
	_game_state.reset()
	_check(_game_state.load_game(), "explored-cell load failed")
	_check(_game_state.is_explored("bramblewood", 17)
		and _game_state.is_explored("bramblewood", 42),
		"explored cells did not survive round-trip")
	_check(not _game_state.is_explored("bramblewood", 99),
		"unvisited cell was reported explored after load")

	# A corrupt primary falls back to the last known-good backup.
	_game_state.gold = 222
	_game_state.save_game()
	_check(_game_state.flush_save(), "backup seed save failed")
	var corrupt_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	_check(corrupt_file != null, "could not create corrupt-primary fixture")
	if corrupt_file != null:
		corrupt_file.store_string("not a ConfigFile")
		corrupt_file.close()
	_check(_game_state.load_game(), "valid backup was not recovered")
	_check(_game_state.gold == 111,
		"backup recovery loaded the corrupt primary instead of the prior save")

	# Legacy schema without the additive field gets safe defaults.
	var legacy := ConfigFile.new()
	legacy.set_value("meta", "schema_version", 3)
	legacy.set_value("progress", "current_stage", _game_state.QuestStage.COMPLETE)
	legacy.set_value("progress", "route_checkpoint_id", "beacon_relit")
	_check(legacy.save(SAVE_PATH) == OK, "could not write legacy save fixture")
	_check(not service.is_encrypted(SAVE_PATH), "legacy fixture must be plaintext")
	_game_state.reset()
	_check(_game_state.load_game(), "legacy save was not accepted")
	_check(service.is_encrypted(SAVE_PATH),
		"a legacy plaintext save was not rewritten in the encrypted format")
	var legacy_expansion: Dictionary = _game_state.bramblewood_expansion_snapshot()
	_check(not bool(legacy_expansion.get("started", false))
		and not bool(legacy_expansion.get("completed", false))
		and legacy_expansion.get("discovered_pockets", []).is_empty(),
		"legacy save did not default expansion state safely")
	var legacy_activity: Dictionary = _game_state.get_world_activity_state()
	_check((legacy_activity.get("completed", {}) as Dictionary).is_empty()
		and (legacy_activity.get("soft_unlocks", {}) as Dictionary).is_empty(),
		"legacy save did not default activity state safely")

	# Activity completion, soft unlocks, and repeatable cooldowns are additive
	# and survive the same save boundary as the rest of progression.
	_game_state.reset()
	_check(_game_state.complete_world_activity("bramblewood", "activity_cache", "one_time"),
		"one-time activity did not complete")
	_check(not _game_state.complete_world_activity("bramblewood", "activity_cache", "one_time"),
		"one-time activity completed twice")
	_check(_game_state.unlock_world_activity("bramblewood", "side_route", "Side route"),
		"soft unlock did not persist")
	_game_state.set_world_activity_cooldown("bramblewood", "patrol", 9999999999.0)
	_game_state.save_game()
	_check(_game_state.flush_save(), "activity state save failed")
	_game_state.reset()
	_check(_game_state.load_game(), "activity state load failed")
	_check(_game_state.is_world_activity_completed("bramblewood", "activity_cache")
		and _game_state.has_world_activity_unlock("bramblewood", "side_route"),
		"activity completion or soft unlock did not survive reload")
	_check(_game_state.get_world_activity_cooldown("bramblewood", "patrol") > 0.0,
		"repeatable activity cooldown did not survive reload")

	# Malformed activity payloads are discarded while core progression remains.
	var corrupt_activity := ConfigFile.new()
	corrupt_activity.set_value("meta", "schema_version", _game_state.SAVE_SCHEMA_VERSION)
	corrupt_activity.set_value("progress", "gold", 333)
	corrupt_activity.set_value("progress", "current_realm", "bramblewood")
	corrupt_activity.set_value("progress", "world_activity_state", {
		"completed": "not-a-dictionary", "cooldowns": ["bad"], "soft_unlocks": 17})
	_check(corrupt_activity.save(SAVE_PATH) == OK,
		"could not write corrupt activity fixture")
	_game_state.reset()
	_check(_game_state.load_game(), "corrupt activity fixture was rejected with core save")
	var recovered_activity: Dictionary = _game_state.get_world_activity_state()
	_check((recovered_activity.get("completed", {}) as Dictionary).is_empty()
		and (recovered_activity.get("cooldowns", {}) as Dictionary).is_empty()
		and _game_state.gold == 333,
		"corrupt activity data affected core state or was not discarded")

	# A failed replacement leaves the existing primary unchanged.
	var atomic_path := "/tmp/embervale_atomic_contract.cfg"
	service.delete_files(atomic_path)
	var original := ConfigFile.new()
	original.set_value("meta", "marker", "original")
	_check(service.write_config(original, atomic_path), "atomic seed write failed")
	var backup_directory := ProjectSettings.globalize_path(service.backup_path(atomic_path))
	DirAccess.make_dir_absolute(backup_directory)
	var replacement := ConfigFile.new()
	replacement.set_value("meta", "marker", "replacement")
	_check(not service.write_config(replacement, atomic_path),
		"forced backup failure unexpectedly replaced primary")
	var unchanged := service.load_config(atomic_path).get("config") as ConfigFile
	_check(unchanged != null
		and str(unchanged.get_value("meta", "marker", "")) == "original",
		"failed replacement damaged the existing primary")
	_check(service.is_encrypted(atomic_path),
		"a direct service write was not encrypted at rest")
	DirAccess.remove_absolute(backup_directory)
	service.delete_files(atomic_path)

	# Newer schemas are rejected without applying their values.
	_game_state.gold = 77
	_game_state.save_game()
	_check(_game_state.flush_save(), "newer-schema fixture seed failed")
	_check(_write_config({"meta": {"schema_version": _game_state.SAVE_SCHEMA_VERSION + 1},
		"progress": {"gold": 1234}}), "could not write newer-schema fixture")
	_check(not _game_state.load_game(), "newer schema was accepted")
	_check(_game_state.gold == 77, "newer schema partially changed in-memory state")

	# Runtime validation rejects invalid realms and quantities.
	_game_state.reset()
	var original_realms: Array[String] = _game_state.unlocked_realms.duplicate()
	_check(not _game_state.unlock_realm("not_a_realm"), "invalid realm was unlocked")
	_game_state.set_current_realm("not_a_realm")
	_check(_game_state.current_realm == "bramblewood",
		"invalid realm changed current realm")
	_game_state.add_material("iron_shard", 0)
	_game_state.add_material("iron_shard", -4)
	_check(_game_state.get_material_qty("iron_shard") == 0,
		"non-positive material addition changed inventory")
	_check(not _game_state.remove_material("iron_shard", -1),
		"negative material removal was accepted")
	_check(_game_state.unlocked_realms == original_realms,
		"invalid realm changed unlock list")

	# Upgrade costs debit both resources in memory before one persistence request.
	_game_state.add_weapon(_game_state.WEAPON_DEFS["ember_sword"].duplicate(true))
	_game_state.add_material("iron_shard", 100)
	_game_state.add_gold(1000)
	_game_state.flush_save()
	var gold_before: int = _game_state.gold
	var material_before: int = _game_state.get_material_qty("iron_shard")
	var upgrade := _game_state.upgrade_weapon("ember_sword")
	_check(bool(upgrade.get("success", false)), "valid weapon upgrade failed")
	_check(_game_state.gold < gold_before
		and _game_state.get_material_qty("iron_shard") < material_before,
		"successful upgrade did not debit both costs")
	_game_state.add_material("iron_shard", 10)
	_game_state.gold = 0
	var failed_gold: int = _game_state.gold
	var failed_material: int = _game_state.get_material_qty("iron_shard")
	var failed_upgrade := _game_state.upgrade_weapon("ember_sword")
	_check(not bool(failed_upgrade.get("success", false)),
		"upgrade without gold unexpectedly succeeded")
	_check(_game_state.gold == failed_gold
		and _game_state.get_material_qty("iron_shard") == failed_material,
		"failed upgrade changed gold or materials")
	_check(failed_material > 0, "upgrade fixture did not contain material cost")

	# Architectural invariant: the retired writer is not registered or called.
	var project_text := FileAccess.get_file_as_string("res://project.godot")
	var reward_text := FileAccess.get_file_as_string("res://scripts/systems/reward_manager.gd")
	_check(not project_text.contains("SaveLoadManager="),
		"retired SaveLoadManager remains an autoload")
	_check(not reward_text.contains("ConfigFile.new()"),
		"RewardManager still owns direct save-file I/O")

	_game_state.delete_save()
	if _failures == 0:
		print("PERSISTENCE CONTRACT PASSED")
	else:
		print("PERSISTENCE CONTRACT FAILED: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)
