extends SceneTree

## Debug: inspect DestructibleProp child structure after _ready.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var prop := DestructibleProp.create("pot")
	root.add_child(prop)
	await process_frame
	await process_frame
	print("children:")
	for c in prop.get_children():
		print("  - ", c.name, " (", c.get_class(), ")")
	print("lookup 'CollisionShape3D': ", prop.get_node_or_null("CollisionShape3D"))
	quit(0)
