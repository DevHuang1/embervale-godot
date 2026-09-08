extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for profile in ["npc_human", "npc_orc", "merchant", "craftsman", "orc_brute"]:
		var path := CharacterRigLoader._any_model(profile)
		_check(not path.is_empty(), "%s resolves to an imported model" % profile)
		var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
		_check(packed != null, "%s imports as a PackedScene" % profile)
		if packed == null:
			continue
		var host := Node3D.new()
		root.add_child(host)
		_check(CharacterRigLoader.try_if_wire(host, profile), "%s mounts through CharacterRigLoader" % profile)
		var rig := host.get_node_or_null("Visual/AuthoredRig") as Node3D
		_check(rig != null and not rig.find_children("*", "MeshInstance3D", true, false).is_empty(),
			"%s exposes visible mesh geometry" % profile)
		host.queue_free()
	await process_frame
	if failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL — ", failures)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		print("FAILURE: ", message)
