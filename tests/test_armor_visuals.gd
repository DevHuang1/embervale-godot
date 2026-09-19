extends SceneTree

## Armor visual contract: registry records stay in sync with ARMOR_DEFS, model
## records resolve to loadable CC0 props, and the hero mounts a rigid model on
## its skeleton bone with measured normalization.

const TEST_MODEL := "res://assets/models/weapons/quaternius/Shield_Round.fbx"
const TEST_LENGTH := 0.60

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func():
		print("WATCHDOG TIMEOUT")
		quit(3))
	_run.call_deferred()

func _frames(n: int) -> void:
	for _i in n:
		await process_frame

## True rendered size of a subtree, in world units.
func _world_size(root: Node3D) -> float:
	var bounds := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		var box: AABB = (node as Node3D).global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))

func _run() -> void:
	var failures := 0
	var registry := preload("res://scripts/systems/armor_visual_registry.gd")
	var armor_defs: Dictionary = GameState.ARMOR_DEFS
	for armor_id in registry.ARMOR_VISUALS:
		var id := str(armor_id)
		if not armor_defs.has(id):
			failures += 1
			print("FAIL: armor visual record has no ARMOR_DEFS entry: ", id)
		var record: Dictionary = registry.record_for(id)
		var kind := str(record.get("kind", ""))
		if kind not in ["procedural", "model"]:
			failures += 1
			print("FAIL: unknown armor visual kind for %s: %s" % [id, kind])
		if kind == "model":
			if registry.model_path(id).is_empty():
				failures += 1
				print("FAIL: model armor has no loadable path: ", id)
			if registry.model_bone(id).is_empty():
				failures += 1
				print("FAIL: model armor has no seat bone: ", id)
			var target := registry.model_length(id)
			if target < 0.1 or target > 2.5:
				failures += 1
				print("FAIL: model armor length out of band: %s %.2f" % [id, target])
		elif not registry.path_for(id).is_empty():
			failures += 1
			print("FAIL: procedural armor resolved a model path: ", id)
	if registry.is_model("warden_plate"):
		failures += 1
		print("FAIL: procedural armor reported as model")

	var gs = root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()

	var scene: Node = (load("res://scenes/world/grove.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(15)
	var hero := scene.get_node_or_null("Hero")
	if hero == null:
		print("FAIL: hero missing from grove")
		quit(1)
		return

	gs.add_armor(GameState.ARMOR_DEFS["warden_plate"].duplicate(true), false)
	gs.equip_armor("warden_plate")
	await _frames(4)
	var gear := hero.find_child("ArmorGear", true, false)
	if gear == null:
		failures += 1
		print("FAIL: procedural armor gear root missing after equip")
	else:
		var meta_record: Dictionary = gear.get_meta("visual_record", {})
		if str(meta_record.get("kind", "")) != "procedural":
			failures += 1
			print("FAIL: gear root did not record the procedural armor visual")

	var mounted: bool = hero.call("_mount_armor_model_record", {
		"kind": "model", "path": TEST_MODEL, "bone": "Torso",
		"length": TEST_LENGTH,
	})
	await _frames(2)
	if not mounted:
		failures += 1
		print("FAIL: model armor record did not mount")
	else:
		var sockets: Array = hero.find_children("ArmorSocket_model*", "Node3D", true, false)
		if sockets.is_empty():
			failures += 1
			print("FAIL: mounted armor model has no bone socket")
		else:
			var socket: Node3D = sockets[0]
			var parent := socket.get_parent()
			if parent == null or not str(parent.name).contains("Torso"):
				failures += 1
				print("FAIL: armor socket did not bind to the Torso bone (parent=%s)"
					% str(parent.name if parent != null else "<none>"))
			var measured := _world_size(socket)
			if absf(measured - TEST_LENGTH) > TEST_LENGTH * 0.08:
				failures += 1
				print("FAIL: armor model renders at %.3fm instead of %.3fm"
					% [measured, TEST_LENGTH])

	var bad: bool = hero.call("_mount_armor_model_record", {
		"kind": "model", "path": "res://assets/models/missing_armor.fbx",
	})
	if bad:
		failures += 1
		print("FAIL: missing armor path reported a mount")

	gs.delete_save()
	if failures == 0:
		print("ALL ARMOR VISUAL TESTS PASSED")
	else:
		print("ARMOR VISUAL TESTS FAILED: ", failures)
	quit(1 if failures > 0 else 0)
