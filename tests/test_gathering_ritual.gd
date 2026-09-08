extends SceneTree

func _init() -> void:
	var node_script := preload("res://scripts/world/gathering_node.gd")
	var gather: Node3D = node_script.new()
	gather.configure("fen_reed", 1, 2, 0.1, 20.0, "mistfen")
	root.add_child(gather)
	await process_frame
	var prompt := gather.get_node_or_null("PromptLabel") as Label3D
	if prompt == null or not prompt.text.contains("still-water rings") \
		or not prompt.text.contains("HOLD TO GATHER"):
		push_error("Mistfen gathering ritual was not surfaced in the prompt")
		quit(1)
		return
	print("ALL GATHERING RITUAL TESTS PASSED")
	gather.queue_free()
	quit()
