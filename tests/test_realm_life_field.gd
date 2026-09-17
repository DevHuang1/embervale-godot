extends SceneTree

## Focused contract for deterministic, non-gameplay world-life presentation.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var field_script := preload("res://scripts/world/realm_life_field.gd")
	var first: RealmLifeField = field_script.new()
	var second: RealmLifeField = field_script.new()
	first.configure("moonfen", 9123, "orbit", 99, "moonfen_test", "Crystal Causeway")
	second.configure("moonfen", 9123, "orbit", 99, "moonfen_test", "Crystal Causeway")
	root.add_child(first)
	root.add_child(second)
	await process_frame
	var first_mesh := first.get_node_or_null("LifeAgents") as MultiMeshInstance3D
	var second_mesh := second.get_node_or_null("LifeAgents") as MultiMeshInstance3D
	if first_mesh == null or second_mesh == null:
		push_error("realm life MultiMesh missing")
		quit(1)
		return
	if first_mesh.multimesh.instance_count != 8 or second_mesh.multimesh.instance_count != 8:
		push_error("realm life agent cap failed")
		quit(1)
		return
	if first_mesh.visibility_range_end != 78.0:
		push_error("realm life visibility bound failed")
		quit(1)
		return
	for index in 8:
		if first_mesh.multimesh.get_instance_transform(index) != \
				second_mesh.multimesh.get_instance_transform(index):
			push_error("realm life seed is not deterministic")
			quit(1)
			return
	first.set_label_visible(true)
	if not bool(first.get_node("LifeLabel").visible):
		push_error("realm life approach label did not become visible")
		quit(1)
		return
	first.queue_free()
	second.queue_free()
	print("REALM LIFE FIELD PASSED")
	quit()
