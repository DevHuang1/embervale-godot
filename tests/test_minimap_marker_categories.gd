extends SceneTree

## Mini-map contract: marker categories stay wired, the discovery layers exist
## and stay bounded, and the player-follow window projects, gates, and culls
## correctly for a live map node. Uses /tmp so it cannot touch a real save.

const SAVE_PATH := "/tmp/embervale_minimap_marker_categories.cfg"

var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/ui/minimap.gd")
	var world_source := FileAccess.get_file_as_string("res://scripts/systems/world_manager.gd")
	var required := ["trader", "craftsman", "structure", "task", "event", "portal",
		"get_nodes_in_group(\"interactable\")", "MAX_MARKERS", "SMALL_LEGEND_HEIGHT",
		"T C S ! E P", "E EVENT   P PORTAL", "quest_board.add_to_group(\"task\")",
		"beacon_spawn.add_to_group(\"event\")",
		# Detail layers requested by the minimap backlog item.
		"func _draw_route", "func _draw_water", "func _draw_relief",
		"func _draw_discovery", "func _draw_markers", "GRID_CELL_METERS",
		"GRID_COLS", "GRID_ROWS", "FOG_REVEAL_CELLS", "MAP_SPAN",
		"mark_explored", "explored_cells_for", "pond_specs", "height_at",
		"func _marker_revealed", "func _marker_in_window",
		"func _declutter_markers"]
	for token in required:
		if not source.contains(token) and not world_source.contains(token):
			_failures.append("missing minimap category contract: %s" % token)

	var gs := root.get_node_or_null("/root/GameState")
	if gs != null:
		gs.set("save_path", SAVE_PATH)
		gs.call("delete_save")
		gs.call("reset")

	var map := (load("res://scripts/ui/minimap.gd") as GDScript).new() as Control
	map.set_process(false)
	root.add_child(map)
	var center := Vector2(74.0, 74.0)
	var radius := 66.0

	# The window is the contract now: its centre projects to the disc centre and
	# its corners still land inside the rim (the scale keys to the half-diagonal).
	var view_center: Vector2 = map.call("_view_center") as Vector2
	var projected: Vector2 = map.call("_project",
		Vector3(view_center.x, 0.0, view_center.y), center, radius) as Vector2
	if projected.distance_to(center) > 0.01:
		_failures.append("view center does not project to the map center")
	var window: Rect2 = map.call("_view_rect") as Rect2
	var corner_projected: Vector2 = map.call("_project",
		Vector3(window.position.x, 0.0, window.position.y), center, radius) as Vector2
	if corner_projected.distance_to(center) > radius:
		_failures.append("window corner projects outside the map disc")
	var span := float(map.get("MAP_SPAN"))
	if span <= 0.0 or float(window.size.x) != span or float(window.size.y) != span:
		_failures.append("map window is not a positive square span")

	# The window follows the player: moving the player must move the window.
	if gs != null:
		gs.set("player_position", Vector2(100.0, -50.0))
		var first: Vector2 = map.call("_view_center") as Vector2
		gs.set("player_position", Vector2(300.0, 120.0))
		var second: Vector2 = map.call("_view_center") as Vector2
		if first.distance_to(Vector2(100.0, -50.0)) > 0.01 \
				or second.distance_to(Vector2(300.0, 120.0)) > 0.01:
			_failures.append("map window does not follow the player")
		gs.set("player_position", Vector2(0.0, 0.0))

	# Guidance outside the window clamps to the rim; decoration outside is
	# culled, and anything inside passes the window test.
	var structure := {"pos": Vector3(window.position.x + window.size.x * 0.4, 0.0,
		window.position.y + window.size.y * 0.2), "priority": 4}
	var quest := {"pos": structure["pos"], "priority": 0}
	if not bool(map.call("_marker_in_window", structure["pos"])):
		_failures.append("marker inside the window was culled")
	var far := Vector3(window.position.x - window.size.x * 3.0, 0.0,
		window.position.y - window.size.y * 3.0)
	if bool(map.call("_marker_in_window", far)):
		_failures.append("marker far outside the window passed the window test")

	# Discovery gating: decorative markers wait for their cell, guidance never
	# does. Cell indexing is world-anchored, so moving the window cannot change
	# which cell a landmark belongs to.
	map.set("_explored", {})
	if gs != null:
		gs.set("player_position", Vector2(0.0, 0.0))
	if bool(map.call("_marker_revealed", structure)):
		_failures.append("undiscovered structure marker was revealed")
	if not bool(map.call("_marker_revealed", quest)):
		_failures.append("quest marker was hidden by discovery fog")
	var index := int(map.call("_cell_index_of_pos", structure["pos"]))
	if gs != null:
		gs.set("player_position", Vector2(500.0, -400.0))
	if int(map.call("_cell_index_of_pos", structure["pos"])) != index:
		_failures.append("world-anchored cell index moved with the window")
	map.set("_explored", {index: true})
	if not bool(map.call("_marker_revealed", structure)):
		_failures.append("explored structure marker stayed hidden")

	# Discovery records the player's neighbourhood, persists it, and leaves
	# everything beyond the reveal radius dark.
	if gs != null:
		gs.call("reset")
		gs.set("player_position", Vector2(200.0, -150.0))
		map.set("_explored", {})
		map.set("_explored_realm", "")
		map.call("_refresh_discovery")
		var grid_cols := int(map.get("GRID_COLS"))
		var player_cell: Vector2i = map.call("_cell_of", Vector3(200.0, 0.0, -150.0))
		var center_index := player_cell.y * grid_cols + player_cell.x
		var realm := str(gs.get("current_realm"))
		if not bool(gs.call("is_explored", realm, center_index)):
			_failures.append("discovery did not persist the player's cell")
		if not (map.get("_explored") as Dictionary).has(center_index):
			_failures.append("discovery did not mirror the player's cell")
		var far_index := player_cell.y * grid_cols + player_cell.x + 3
		if bool(gs.call("is_explored", realm, far_index)):
			_failures.append("discovery revealed a cell beyond its radius")

	# Marker de-clutter: a decorative pile-up collapses, guidance never does.
	if gs != null:
		gs.set("player_position", Vector2.ZERO)
	var pile := Vector3.ZERO
	var far_pos := pile + Vector3(80.0, 0.0, 0.0)
	var pile_index := int(map.call("_cell_index_of_pos", pile))
	var far_index := int(map.call("_cell_index_of_pos", far_pos))
	if pile_index != far_index:
		map.set("_explored", {pile_index: true, far_index: true})
		var pile_markers: Array[Dictionary] = [
			{"pos": pile, "priority": 4, "color": Color.WHITE, "glyph": "S", "kind": "structure", "label": "a"},
			{"pos": pile, "priority": 4, "color": Color.WHITE, "glyph": "S", "kind": "structure", "label": "b"},
			{"pos": pile, "priority": 0, "color": Color.WHITE, "glyph": "!", "kind": "task", "label": "c"},
			{"pos": far_pos, "priority": 4, "color": Color.WHITE, "glyph": "S", "kind": "structure", "label": "d"},
		]
		map.set("markers", pile_markers)
		var visible: Array = map.call("_declutter_markers", center, radius)
		var labels: Array[String] = []
		for m in visible:
			labels.append(str((m as Dictionary).get("label", "")))
		if labels != ["a", "c", "d"]:
			_failures.append("marker de-clutter kept the wrong set: %s" % [labels])
	else:
		_failures.append("pile-up test positions collapsed to one cell")
	map.queue_free()

	if gs != null:
		gs.call("delete_save")

	if _failures.is_empty():
		print("MINIMAP MARKER CATEGORY TESTS PASSED")
	else:
		print("FAILURES: ", _failures)
	quit(1 if not _failures.is_empty() else 0)
