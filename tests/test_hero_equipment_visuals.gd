extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game_state := root.get_node("/root/GameState")
	game_state.set("save_path", "/private/tmp/embervale_equipment_visual_test.cfg")
	game_state.reset()
	game_state.add_weapon(game_state.WEAPON_DEFS["ember_sword"], true)
	game_state.add_armor(game_state.ARMOR_DEFS["warden_plate"], true)
	var scene := (load("res://scenes/world/grove.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for frame in 12:
		await process_frame
	var hero := scene.get_node_or_null("Hero")
	var failures := 0
	for pair in [["ArmorSocket_chest", "Torso"], ["ArmorSocket_shoulder_l", "Shoulder.L"],
			["ArmorSocket_shoulder_r", "Shoulder.R"]]:
		var socket := hero.find_child(pair[0], true, false) as AttachmentSocket
		if socket == null or not str(socket.get_parent().name).contains(str(pair[1]).replace(".", "_")):
			failures += 1
			print("FAIL: armor socket is not following ", pair[1])
	var plate := hero.find_child("WardenBreastplate", true, false) as MeshInstance3D
	if plate == null or not (plate.material_override is ShaderMaterial):
		failures += 1
		print("FAIL: textured breastplate material missing")
	else:
		var material := plate.material_override as ShaderMaterial
		if material.get_shader_parameter("normal_tex") == null \
				or material.get_shader_parameter("orm_tex") == null:
			failures += 1
			print("FAIL: armor PBR texture bindings missing")
	var hand := hero.find_child("HandSocketL", true, false) as AttachmentSocket
	var weapon: Node3D = hand.get_item() if hand != null else null
	if weapon == null or weapon.position.length() <= 0.001:
		failures += 1
		print("FAIL: sword grip calibration missing")
	print("HERO EQUIPMENT VISUAL TESTS PASSED" if failures == 0 else "%d HERO EQUIPMENT VISUAL FAILURES" % failures)
	scene.queue_free()
	for frame in 3:
		await process_frame
	quit(1 if failures > 0 else 0)
