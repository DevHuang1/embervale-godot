extends SceneTree

func _init() -> void:
	var field_script := preload("res://scripts/systems/ambient_life_field.gd")
	var field: Node3D = field_script.new()
	field.setup("mistfen", 42, 4)
	root.add_child(field)
	await process_frame
	var particles := field.get_child(0) as GPUParticles3D
	if particles == null or particles.name != "Butterflies" \
		or not str(field.get_behavior_copy()).contains("ponds"):
		push_error("Mistfen ambient behavior was not applied")
		quit(1)
		return
	print("ALL AMBIENT REALM BEHAVIOR TESTS PASSED")
	field.queue_free()
	quit()
