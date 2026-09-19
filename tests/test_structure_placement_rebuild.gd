extends SceneTree

## Guards structure placement against same-frame name collisions: rebuilding the
## surface structures twice in one frame (or on top of an untracked leftover)
## must leave every node under its canonical Structure_<id> name, because
## lookups and tests resolve structures by that name.

var _passes := 0
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(720, 1280)
	var packed := load("res://scenes/world/grove.tscn") as PackedScene
	_assert_true(packed != null, "grove scene loads")
	if packed == null:
		_finish()
		return
	var world := packed.instantiate()
	root.add_child(world)
	for _i in 20:
		await process_frame
	var gs := root.get_node_or_null("GameState")
	var expansion := world.get_node_or_null("RealmExpansion")
	_assert_true(gs != null, "GameState is available")
	_assert_true(expansion != null, "RealmExpansion is available")
	if gs == null or expansion == null:
		_finish()
		return

	gs.set("current_realm", "bramblewood")
	expansion.call("_place_structures", "bramblewood")
	expansion.call("_place_structures", "bramblewood")
	_assert_canonical(world, expansion, "same realm rebuilt twice in one frame")

	expansion.call("_place_structures", "whispergrove")
	expansion.call("_place_structures", "bramblewood")
	_assert_canonical(world, expansion, "realm switch rebuilt in one frame")

	expansion.call("_place_structures", "")
	expansion.call("_place_structures", "")
	_assert_canonical(world, expansion, "empty realm rebuilt twice in one frame")

	# A structure removed outside this system still holds its canonical name for
	# the rest of the frame; the rebuild must sweep it instead of being renamed.
	var tracked: Dictionary = expansion.get("_structures")
	for id in tracked.keys():
		var node := tracked[id] as Node3D
		if node != null and is_instance_valid(node):
			world.remove_child(node)
			node.free()
	tracked.clear()
	var leftover := Node3D.new()
	leftover.name = "Structure_bramble_keep"
	world.add_child(leftover)
	expansion.call("_place_structures", "")
	_assert_canonical(world, expansion, "untracked leftover on an empty-realm rebuild")

	_finish()

func _assert_canonical(world: Node3D, expansion: Node, label: String) -> void:
	var tracked: Dictionary = expansion.get("_structures")
	_assert_true(not tracked.is_empty(), "%s places structures" % label)
	var expected := {}
	for id in tracked:
		expected["Structure_%s" % str(id)] = true
	for id in tracked:
		var node := tracked[id] as Node3D
		_assert_true(node != null and is_instance_valid(node),
			"%s keeps %s alive" % [label, str(id)])
		if node != null:
			_assert_true(str(node.name) == "Structure_%s" % str(id),
				"%s keeps %s canonical (got %s)" % [label, str(id), str(node.name)])
	var seen := {}
	for child in world.get_children():
		if not str(child.name).begins_with("Structure_"):
			continue
		_assert_true(expected.has(str(child.name)),
			"%s leaves no renamed sibling %s" % [label, str(child.name)])
		_assert_true(not seen.has(str(child.name)),
			"%s leaves no duplicate %s" % [label, str(child.name)])
		seen[str(child.name)] = true

func _assert_true(condition: bool, message: String) -> void:
	if condition:
		_passes += 1
	else:
		_failures.append(message)

func _finish() -> void:
	print("=== Structure Placement Rebuild Validation ===")
	print("passes=", _passes, " failures=", _failures.size())
	for failure in _failures:
		print("FAILURE: ", failure)
	quit(1 if not _failures.is_empty() else 0)
