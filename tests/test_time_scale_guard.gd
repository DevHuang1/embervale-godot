extends SceneTree

func _init() -> void:
	Engine.time_scale = 1.0
	var guard := preload("res://scripts/autoload/time_scale_guard.gd").new()
	root.add_child(guard)
	guard.slow_motion("skill:test", 0.08, 0.5)
	if Engine.time_scale != 1.0 or not guard.active_leases().is_empty():
		push_error("Time scale guard accepted a global slowdown lease")
		quit(1)
		return
	guard.cancel_owner_leases("skill:")
	Engine.time_scale = 1.0
	print("TIME SCALE GUARD PASSED")
	quit(0)
