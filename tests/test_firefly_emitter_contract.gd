extends SceneTree

## Regression: world firefly cards must stay disabled after boot and after the
## day/night controller evaluates its night-time branch.

const WORLD_SCENES: Array[String] = [
	"res://scenes/world/grove.tscn",
	"res://scenes/world/moonfen.tscn",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var game_state := root.get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.set("save_path", "/private/tmp/embervale_firefly_contract.cfg")
		game_state.call("reset")

	for scene_path in WORLD_SCENES:
		var packed := load(scene_path) as PackedScene
		if packed == null:
			push_error("FAIL: world scene missing: %s" % scene_path)
			quit(1)
			return
		var scene := packed.instantiate()
		root.add_child(scene)
		current_scene = scene
		for _frame in 4:
			await process_frame

		var fireflies := scene.get_node_or_null("Fireflies") as GPUParticles3D
		if fireflies == null or fireflies.amount < 1 or fireflies.emitting \
				or not fireflies.get_meta("ground_effect_disabled", false):
			push_error("FAIL: fireflies must be disabled after boot: %s" % scene_path)
			quit(1)
			return

		var day_night := scene.get_node_or_null("DayNightCycle") as DayNightCycle
		if day_night != null:
			day_night.call("_discover_env")
			day_night.set("time_of_day", 0.82)
			day_night.call("_apply_tod")
		if fireflies.emitting:
			push_error("FAIL: day/night must not re-enable disabled fireflies: %s" % scene_path)
			quit(1)
			return

		scene.queue_free()
		await process_frame

	print("FIREFLY EMITTER CONTRACT PASSED")
	quit(0)
