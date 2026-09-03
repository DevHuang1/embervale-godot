extends SceneTree

## Headless validation: save-file integrity and hard clamps. Guards against
## a torn or hand-edited save pushing the player into absurd/corrupt values,
## a save from a NEWER schema being silently (mis)applied, and realm ids on
## disk that are not real realms reaching the world-loading code.

var gs

func _initialize() -> void:
	_run.call_deferred()

func _write_save(sections: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for section in sections:
		for key in sections[section]:
			cfg.set_value(section, key, sections[section][key])
	cfg.save(gs.save_path)

func _run() -> void:
	var failures := 0
	gs = root.get_node("/root/GameState")
	gs.save_path = "/tmp/embervale_save_security_test.cfg"
	gs.delete_save()
	gs.reset()

	# --- Newer schema is refused, not half-applied ---
	_write_save({"meta": {"schema_version": gs.SAVE_SCHEMA_VERSION + 1},
		"progress": {"gold": 1234, "level": 40}})
	if gs.load_game():
		failures += 1
		print("FAIL: newer-schema save was accepted")

	# --- Bad stage rejected ---
	_write_save({"meta": {"schema_version": gs.SAVE_SCHEMA_VERSION},
		"progress": {"current_stage": 999}})
	if not gs.load_game():
		failures += 1
		print("FAIL: valid-schema save refused")
	elif gs.current_stage != gs.QuestStage.COMPLETE:
		failures += 1
		print("FAIL: out-of-range stage not clamped -> ", gs.current_stage)

	# --- Negative / absurd currency and level clamped ---
	_write_save({"meta": {"schema_version": gs.SAVE_SCHEMA_VERSION},
		"progress": {
			"gold": -500, "diamonds": 2_000_000_000,
			"level": 9999, "xp": -1,
			"current_realm": "moonfen", "unlocked_realms": ["moonfen"],
		}})
	if not gs.load_game():
		failures += 1
		print("FAIL: valid-schema save refused (bounds)")
	if gs.gold != 0:
		failures += 1
		print("FAIL: negative gold not clamped -> ", gs.gold)
	if gs.diamonds > gs.MAX_CURRENCY:
		failures += 1
		print("FAIL: huge diamonds not clamped -> ", gs.diamonds)
	if gs.level != gs.MAX_LEVEL:
		failures += 1
		print("FAIL: absurd level not clamped -> ", gs.level)
	if gs.xp < 0:
		failures += 1
		print("FAIL: negative xp not clamped -> ", gs.xp)

	# --- Stat corruption clamped (allocated stat overflows max_hp otherwise) ---
	_write_save({"meta": {"schema_version": gs.SAVE_SCHEMA_VERSION},
		"progress": {"stats": {"str": -99, "vit": 1_000_000,
			"dex": 3, "end": 4, "luk": 5}, "stat_points": 1_000_000}})
	if not gs.load_game():
		failures += 1
		print("FAIL: valid-schema save refused (stats)")
	if gs.stat_str < 0:
		failures += 1
		print("FAIL: negative stat not clamped -> ", gs.stat_str)
	if gs.stat_vit > gs.MAX_STAT_VALUE:
		failures += 1
		print("FAIL: huge VIT not clamped -> ", gs.stat_vit)
	if gs.stat_points > gs.MAX_STAT_POINTS:
		failures += 1
		print("FAIL: huge stat_points not clamped -> ", gs.stat_points)

	# --- Realm id on disk that is not a real realm is dropped ---
	_write_save({"meta": {"schema_version": gs.SAVE_SCHEMA_VERSION},
		"progress": {"current_realm": "sudo_boss", "unlocked_realms": ["sudo_boss"]}})
	if not gs.load_game():
		failures += 1
		print("FAIL: valid-schema save refused (realm)")
	if gs.current_realm != "bramblewood":
		failures += 1
		print("FAIL: bogus realm survived -> ", gs.current_realm)
	if "sudo_boss" in gs.unlocked_realms:
		failures += 1
		print("FAIL: bogus realm leaked into unlocked list")

	# --- Torn / garbage save yields safe defaults, never corrupt values ---
	var garbage := PackedByteArray()
	garbage.resize(64)
	for i in garbage.size():
		garbage[i] = (i * 7 + 3) % 256
	var f := FileAccess.open(gs.save_path, FileAccess.WRITE)
	f.store_buffer(garbage)
	f.close()
	gs.reset()
	gs.set_current_realm("moonfen")  # leave a marker; garbage must not keep it
	var prev_gold: int = gs.gold
	if not gs.load_game():
		pass  # refusing outright is also acceptable
	elif gs.gold < 0 or gs.level < 1 or gs.gold > gs.MAX_CURRENCY:
		failures += 1
		print("FAIL: garbage save produced unsafe values")
	gs.delete_save()

	if failures == 0:
		print("ALL SAVE SECURITY TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(1 if failures > 0 else 0)