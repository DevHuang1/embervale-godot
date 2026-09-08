extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs := root.get_node_or_null("/root/GameState") as GameState
	if gs == null:
		push_error("GameState autoload missing")
		quit(1)
		return
	var old_gold := gs.gold
	var old_level := gs.level
	gs.gold = maxi(gs.gold, gs.respec_cost() + 10)
	gs.stat_str = 2
	gs.stat_vit = 1
	gs.stat_points = 0
	var expected_cost := gs.respec_cost()
	if not gs.respec_stats() or gs.stat_str != 0 or gs.stat_vit != 0 \
			or gs.stat_points != 3 or gs.gold != maxi(old_gold, expected_cost + 10) - expected_cost \
			or gs.level != old_level:
		push_error("Respec transaction did not restore points exactly")
		quit(1)
		return
	if gs.respec_stats():
		push_error("Empty respec was incorrectly accepted")
		quit(1)
		return
	print("RESPEC RULES PASSED")
	quit(0)
