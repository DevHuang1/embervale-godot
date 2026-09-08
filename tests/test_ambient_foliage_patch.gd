extends SceneTree

func _init() -> void:
	var script := load("res://scripts/systems/ambient_foliage_patch.gd") as GDScript
	var patch: MultiMeshInstance3D = script.new()
	patch.setup("moonfen", 4242, 999)
	if patch.multimesh == null or patch.multimesh.instance_count != 64:
		push_error("ambient foliage cap or setup failed")
		quit(1)
		return
	var first := patch.multimesh.get_instance_transform(0)
	var second: MultiMeshInstance3D = script.new()
	second.setup("moonfen", 4242, 999)
	if first != second.multimesh.get_instance_transform(0):
		push_error("ambient foliage seed is not deterministic")
		quit(1)
		return
	print("ALL AMBIENT FOLIAGE TESTS PASSED")
	quit()
