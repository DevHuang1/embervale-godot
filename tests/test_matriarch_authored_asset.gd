extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	_assert_true(CharacterRigLoader._any_model("boss_matriarch") \
		== "res://assets/models/boss_matriarch.glb",
		"validated GLB takes precedence while the FBX remains available as fallback")
	var packed := load("res://scenes/entities/boss_matriarch.tscn") as PackedScene
	_assert_true(packed != null, "Matriarch gameplay scene loads")
	if packed == null:
		_finish()
		return
	var boss := packed.instantiate()
	root.add_child(boss)
	await process_frame
	await process_frame
	var rig := boss.find_child("AuthoredRig", true, false) as Node3D
	_assert_true(rig != null, "authored Matriarch GLB mounts on the gameplay boss")
	if rig == null:
		boss.queue_free()
		_finish()
		return
	var procedural_body := boss.get_node_or_null("Visual/Body") as MeshInstance3D
	_assert_true(procedural_body != null and not procedural_body.visible,
		"authored rig replaces the procedural capsule silhouette")

	var lod_counts := {0: 0, 1: 0, 2: 0}
	var custom_mask_meshes := 0
	var lod_ranges_valid := {0: true, 1: true, 2: true}
	for candidate in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh := candidate as MeshInstance3D
		var mesh_name := str(mesh.name).to_upper()
		var lod := -1
		if mesh_name.ends_with("_LOD0"):
			lod = 0
			lod_ranges_valid[0] = bool(lod_ranges_valid[0]) \
				and is_equal_approx(mesh.visibility_range_end, 20.0)
		elif mesh_name.ends_with("_LOD1"):
			lod = 1
			lod_ranges_valid[1] = bool(lod_ranges_valid[1]) \
				and is_equal_approx(mesh.visibility_range_begin, 18.0) \
				and is_equal_approx(mesh.visibility_range_end, 36.0)
		elif mesh_name.ends_with("_LOD2"):
			lod = 2
			lod_ranges_valid[2] = bool(lod_ranges_valid[2]) \
				and is_equal_approx(mesh.visibility_range_begin, 34.0) \
				and is_zero_approx(mesh.visibility_range_end)
		if lod >= 0:
			lod_counts[lod] += 1
		if mesh.mesh != null and mesh.mesh.get_surface_count() > 0 \
				and (mesh.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0:
			custom_mask_meshes += 1
	_assert_true(lod_counts[0] > lod_counts[1] and lod_counts[1] > lod_counts[2] \
		and lod_counts[2] > 0,
		"all three silhouettes exist with progressively fewer mesh pieces")
	_assert_true(bool(lod_ranges_valid[0]), "all LOD0 pieces use the near range")
	_assert_true(bool(lod_ranges_valid[1]), "all LOD1 pieces use the middle range")
	_assert_true(bool(lod_ranges_valid[2]), "all LOD2 pieces use the far range")
	_assert_true(custom_mask_meshes > 0,
		"Godot import retains the Blender RealmMask vertex colors")

	for socket_name in ["SOCKET_Hand_R", "SOCKET_Hand_L", "SOCKET_VFX_Chest",
			"SOCKET_VFX_Foot_L", "SOCKET_VFX_Foot_R"]:
		_assert_true(rig.find_child(socket_name, true, false) != null,
			"authored rig exposes %s" % socket_name)
	var players := rig.find_children("*", "AnimationPlayer", true, false)
	_assert_true(not players.is_empty(), "authored rig imports an AnimationPlayer")
	if not players.is_empty():
		var names := " ".join(Array((players[0] as AnimationPlayer).get_animation_list())) \
			.to_lower()
		for token in ["idle", "attack1_slam", "cast_rootprison", "buff_phase",
				"hit_heavy", "death_forward"]:
			_assert_true(names.contains(token), "authored clips include %s" % token)
	var bridge := boss.get_meta("anim_bridge", null) as AnimTreeBridge
	_assert_true(bridge != null and bridge.has_cue("idle") \
		and bridge.has_cue("light_1") and bridge.has_cue("cast") \
		and bridge.has_cue("buff") and bridge.has_cue("hit") \
		and bridge.has_cue("death"),
		"animation bridge resolves every shipped Matriarch gameplay cue")
	boss.queue_free()
	await process_frame
	_finish()

func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures.append(message)
		print("FAILURE: ", message)

func _finish() -> void:
	if failures.is_empty():
		print("RESULT: PASS")
		quit(0)
	else:
		print("RESULT: FAIL — ", failures)
		quit(1)
