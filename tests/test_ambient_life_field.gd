extends SceneTree

func _init() -> void:
	var script := load("res://scripts/systems/ambient_life_field.gd") as GDScript
	var field: Node3D = script.new()
	field.call("setup", "moonfen", 9001, 99)
	var particles := field.get_node_or_null("Butterflies") as GPUParticles3D
	if particles == null or particles.amount != 16 or particles.lifetime != 12.0:
		push_error("ambient life cap or lifetime failed")
		quit(1)
		return
	if particles.visibility_aabb.size != Vector3(34.0, 5.0, 34.0):
		push_error("ambient life visibility bounds failed")
		quit(1)
		return
	print("ALL AMBIENT LIFE TESTS PASSED")
	quit()
