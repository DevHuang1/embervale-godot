extends SceneTree

func _init() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/entities/hero.gd")
	var windup := source.find("CombatFx.spawn_telegraph(self")
	var trail := source.find("CombatFx.spawn_arc_trail(self", windup)
	var wait := source.find("await _wait_for_animator_impact()", trail)
	var damage := source.find("enemy.take_damage(damage", wait)
	if windup < 0 or trail < 0 or wait < 0 or damage < 0 \
			or not (windup < trail and trail < wait and wait < damage):
		push_error("Hero attack event order is not telegraph -> trail -> impact wait -> damage")
		quit(1)
		return
	var equipment_test := FileAccess.get_file_as_string("res://tests/test_equipment_full_scene.gd")
	if not equipment_test.contains("current_weapon") or not equipment_test.contains("swing_trail"):
		push_error("Visible weapon/trail scene coverage is missing")
		quit(1)
		return
	print("ALL ATTACK EVENT ORDER TESTS PASSED")
	quit()
