extends SceneTree

func _init() -> void:
	var zone_script := preload("res://scripts/entities/encounter_zone.gd")
	var zone: Area3D = zone_script.new()
	zone.reward_label = "Fen reliquary"
	root.add_child(zone)
	await process_frame
	zone._reveal_reward_marker()
	var marker := zone.get_node_or_null("RewardMarker") as Label3D
	if marker == null or marker.text != "FEN RELIQUARY" or not marker.visible:
		push_error("Reward marker did not reveal the authored reward label")
		quit(1)
		return
	print("ALL ENCOUNTER REWARD MARKER TESTS PASSED")
	zone.queue_free()
	quit()
