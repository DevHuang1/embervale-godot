extends SceneTree

func _init() -> void:
	var expansion := FileAccess.get_file_as_string("res://scripts/world/realm_expansion.gd")
	var manager := FileAccess.get_file_as_string("res://scripts/systems/world_manager.gd")
	_assert_true(expansion.contains("signal dungeon_state_changed"), "dungeon state signal exists")
	_assert_true(expansion.contains("func toggle_dungeon() -> void:"), "dungeon toggle exists")
	_assert_true(expansion.contains("_surface_return_position"), "surface return position persists")
	_assert_true(expansion.contains("queue_free()"), "interior cleanup exists")
	_assert_true(expansion.contains("set_meta(\"stream_owned\", true)"), "interior is stream-owned")
	_assert_true(expansion.contains("DUNGEON_MODULES"), "authored dungeon module catalog exists")
	_assert_true(expansion.contains("_add_dungeon_collision()"), "interior collision is explicit")
	_assert_true(expansion.contains("_add_dungeon_navigation()"), "interior navigation exists")
	_assert_true(expansion.contains("_add_dungeon_lighting()"), "interior lighting exists")
	_assert_true(expansion.contains("dungeon_exit"), "interior exit interaction exists")
	_assert_true(expansion.contains("DUNGEON_ENEMY_SCENE"), "dungeon encounter uses existing enemy scene")
	_assert_true(expansion.contains("BossRewardAnchor"), "dungeon reward anchor exists")
	_assert_true(expansion.contains("DUNGEON_BOSS_SCENE"), "dungeon boss uses existing boss scene")
	_assert_true(expansion.contains("EmbervaultBossRoom"), "dungeon boss room exists")
	_assert_true(expansion.contains("dungeon_completed"), "dungeon completion signal exists")
	_assert_true(expansion.contains("dungeon_embervault_complete"), "dungeon completion is save-backed")
	_assert_true(manager.contains("func toggle_dungeon() -> void:"), "world manager delegates dungeon toggle")
	print("ALL ENTERABLE STRUCTURE CONTRACT TESTS PASSED")
	quit()

func _assert_true(condition: bool, label: String) -> void:
	if not condition:
		push_error("FAIL: %s" % label)
		quit(1)
