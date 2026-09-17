extends SceneTree

const ROSTER := preload("res://scripts/systems/boss_roster_catalog.gd")
const BOSS_SCENE: PackedScene = preload("res://scenes/entities/boss_articulated.tscn")
const EXPECTED_FLYERS := ["moonfen_tide_oracle", "moonfen_lunar_leviathan"]

var _failures := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var player := Node3D.new()
	player.name = "PoseProbePlayer"
	player.add_to_group("player")
	root.add_child(player)
	player.global_position = Vector3(0.0, 0.0, -20.0)
	for boss_id_value in ROSTER.CANONICAL_IDS:
		var boss := BOSS_SCENE.instantiate() as ArticulatedBoss
		boss.def_id = str(boss_id_value)
		boss.is_practice = true
		root.add_child(boss)
		boss.global_position = Vector3.ZERO
		await process_frame
		var rig := boss.get_node_or_null("Visual/AuthoredRig") as Node3D
		var bounds := _world_bounds(rig)
		var is_flying := bool(boss._def.get("can_fly", false))
		var expected_flying := str(boss_id_value) in EXPECTED_FLYERS
		var source_speed := float(boss._def.get("speed", 0.0))
		var expected_speed := source_speed * ROSTER.BOSS_TRAVEL_SPEED_MULTIPLIER
		if absf(boss.move_speed - expected_speed) > 0.01:
			_fail("%s continuous travel speed is not using the mobile-safe multiplier" % boss.canonical_id)
		if is_flying != expected_flying:
			_fail("%s mobility profile does not match the roster" % boss.canonical_id)
		if rig == null or absf(bounds.position.y) > 0.03:
			_fail("%s authored floor is not snapped to the gameplay floor" % boss.canonical_id)
		var start_y := boss.global_position.y
		for _frame in 30:
			await physics_frame
		var lifted := boss.global_position.y > start_y + 0.08
		if lifted != expected_flying:
			_fail("%s runtime vertical movement does not match its mobility profile" % boss.canonical_id)
		print("POSE PASS %s fly=%s vertical=%.3f depth=%.3f floor=%.4f" % [
			boss.canonical_id, str(is_flying), bounds.size.y, bounds.size.z,
			bounds.position.y])
		boss.queue_free()
		await process_frame
	player.queue_free()
	if _failures == 0:
		print("BOSS V2 POSE TEST PASSED")
	quit(0 if _failures == 0 else 1)

func _fail(message: String) -> void:
	_failures += 1
	print("FAILURE: ", message)

func _world_bounds(root: Node3D) -> AABB:
	if root == null:
		return AABB()
	var result := AABB()
	var started := false
	for mesh_value in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_value as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var local_bounds := mesh.get_aabb()
		for index in 8:
			var point := mesh.global_transform * local_bounds.get_endpoint(index)
			if not started:
				result = AABB(point, Vector3.ZERO)
				started = true
			else:
				result = result.expand(point)
	return result
