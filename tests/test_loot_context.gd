extends SceneTree

func _init() -> void:
	var reward_script := preload("res://scripts/systems/reward_manager.gd")
	_assert_equal(reward_script.describe_drop_context("weapon", "ember_sword"), "Ember Sword · new build option")
	_assert_equal(reward_script.describe_drop_context("armor", "warden_plate"), "Warden Plate · compare in Satchel")
	_assert_equal(reward_script.describe_drop_context("material", "emberstone"), "Emberstone · crafting material · Heartwood realm")
	_assert_equal(reward_script.describe_drop_context("material", "iron_shard"), "Iron Shard · upgrade material")
	_assert_equal(reward_script.describe_drop_context("gold", ""), "")
	print("ALL LOOT CONTEXT TESTS PASSED")
	quit()

func _assert_equal(actual: Variant, expected: Variant) -> void:
	if actual != expected:
		push_error("Expected %s, got %s" % [expected, actual])
		quit(1)
