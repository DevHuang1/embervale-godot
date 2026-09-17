extends SceneTree

## Regression: authored props are normalized before they enter the scene tree.
## The test intentionally keeps the prop off-tree so a future global_transform
## access fails in the same way as the original boot error.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var dressing_script := load("res://scripts/systems/grove_dressing.gd") as GDScript
	_assert_true(dressing_script != null, "GroveDressing script loads")
	if dressing_script == null:
		quit(1)
		return

	var dressing := dressing_script.new() as Node3D
	var prop := Node3D.new()
	prop.name = "OffTreeProp"
	prop.scale = Vector3(1.0, 2.0, 1.0)
	var visual := Node3D.new()
	visual.scale = Vector3(1.0, 1.5, 1.0)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	mesh.mesh = box
	visual.add_child(mesh)
	prop.add_child(visual)
	dressing.add_child(prop)

	_assert_true(not mesh.is_inside_tree(), "nested imported mesh remains off-tree during normalization")
	dressing.call("_normalize_authored_prop", prop, 6.0)
	_assert_true(is_equal_approx(prop.scale.x, 1.15),
		"off-tree normalization applies the authored scale multiplier")
	_assert_true(is_equal_approx(prop.scale.y, 2.30),
		"off-tree normalization includes nested and root Y scale")

	dressing.free()
	print("GROVE DRESSING LIFECYCLE PASSED")
	quit(0)

func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		push_error("FAIL: " + message)
		quit(1)
