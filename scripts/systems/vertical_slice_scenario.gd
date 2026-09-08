extends RefCounted
class_name VerticalSliceScenario

const TEMP_SAVE_PATH: String = "/tmp/embervale_vertical_slice_scenario.cfg"

static func setup_clean() -> Dictionary:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return {}
	var gs: Node = tree.root.get_node_or_null("GameState")
	if gs == null:
		return {}
	gs.save_path = TEMP_SAVE_PATH
	gs.delete_save()
	gs.reset()
	var camp: Node = tree.root.get_node_or_null("CampProgression")
	var telemetry: Node = tree.root.get_node_or_null("AndroidProfileTelemetry")
	if telemetry != null and telemetry.has_method("reset_route_events"):
		telemetry.reset_route_events()
	return {"save_path": TEMP_SAVE_PATH, "camp": camp.to_dict() if camp != null else {}, "stage": int(gs.current_stage), "checkpoint": gs.route_checkpoint_id}

static func cleanup() -> void:
	if FileAccess.file_exists(TEMP_SAVE_PATH):
		DirAccess.remove_absolute(TEMP_SAVE_PATH)
