extends SceneTree

func _init() -> void:
	var beacon_script := preload("res://scripts/world/realm_activity_beacon.gd")
	var beacon: Node3D = beacon_script.new()
	beacon.name = "TestActivityBeacon"
	beacon.configure("heartwood")
	root.add_child(beacon)
	await process_frame
	var label := beacon.get_node_or_null("ActivityLabel") as Label3D
	if label == null or not label.text.contains("cooling-stone") \
		or not label.text.contains("forge recipe"):
		push_error("Realm activity beacon did not use the catalog traversal identity")
		quit(1)
		return
	print("ALL REALM ACTIVITY BEACON TESTS PASSED")
	beacon.queue_free()
	quit()
