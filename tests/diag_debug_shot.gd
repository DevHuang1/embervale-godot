extends SceneTree

## Terrain visual bisection probe:
##   dbg_weights   - debug_view=1 layer-weight visualization (albedo sanity)
##   dbg_low       - QualityScaler LOW (omni shadows off, pom off)
##   dbg_wide_high - elevated wide angle at HIGH tier
##   dbg_high      - gameplay camera at HIGH tier (shadows on, pom 2)

const OUT := "/var/folders/t5/3pcs06_d6tnd5psczflhtgkh0000gp/T/kilo"

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _snap(fname: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT + "/" + fname)
	print("saved ", fname)

func _terrain_mat() -> ShaderMaterial:
	var scene := current_scene
	if scene == null:
		return null
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override
		if m is ShaderMaterial and (m as ShaderMaterial).shader != null \
				and (m as ShaderMaterial).shader.resource_path.ends_with(
					"terrain_ground.gdshader"):
			return m
	return null

func _run() -> void:
	var gs := root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()
	change_scene_to_file("res://scenes/world/grove.tscn")
	await _frames(150)

	var mat := _terrain_mat()
	if mat == null:
		push_error("no terrain material found")
		quit(1)
		return

	# A: layer weights
	mat.set_shader_parameter("debug_view", 1)
	await _frames(5)
	_snap("dbg_weights.png")
	mat.set_shader_parameter("debug_view", 0)

	# A2: plain red StandardMaterial - shader vs geometry bisection
	var terrain_mi: MeshInstance3D = null
	for mi in current_scene.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_override == mat:
			terrain_mi = mi
			break
	if terrain_mi != null:
		print("terrain aabb=", terrain_mi.get_aabb(),
			" xform=", terrain_mi.global_transform)
		print("terrain visible=", terrain_mi.is_visible_in_tree(),
			" layers=", terrain_mi.layers,
			" cast_shadow=", terrain_mi.cast_shadow)
		var mesh_res := terrain_mi.mesh as ArrayMesh
		if mesh_res != null and mesh_res.get_surface_count() > 0:
			var arrs := mesh_res.surface_get_arrays(0)
			var vs := arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var ins := arrs[Mesh.ARRAY_INDEX] as PackedInt32Array
			print("MESH: surfaces=", mesh_res.get_surface_count(),
				" verts=", vs.size(), " indices=", ins.size())
		var cam := root.get_camera_3d()
		if cam != null:
			print("ACTIVE CAM: ", cam.get_path(), " cull_mask=", cam.cull_mask,
				" far=", cam.far, " near=", cam.near)
		for occ in current_scene.find_children("*", "OccluderInstance3D", true, false):
			print("OCCLUDER FOUND: ", (occ as OccluderInstance3D).get_path())
		# Giant floating red slab: can this mesh render AT ALL?
		var flat := StandardMaterial3D.new()
		flat.albedo_color = Color(0.9, 0.05, 0.05)
		terrain_mi.material_override = flat
		terrain_mi.layers = 0xFFFFF
		terrain_mi.scale = Vector3(2, 1, 2)
		terrain_mi.global_position = Vector3(0, 8, 0)
		await _frames(6)
		_snap("dbg_giantslab.png")
		terrain_mi.scale = Vector3.ONE
		terrain_mi.global_position = Vector3.ZERO
		terrain_mi.material_override = mat
		await _frames(3)

	var qs := root.get_node("/root/WorldState/QualityScaler")
	var old_cam := root.get_viewport().get_camera_3d()

	# B: LOW tier - shadows + pom off
	qs.set_mode(0)
	await _frames(10)
	_snap("dbg_low.png")

	# C: HIGH tier wide angle
	qs.set_mode(2)
	await _frames(5)
	var cam := Camera3D.new()
	current_scene.add_child(cam)
	cam.global_position = Vector3(0, 26, 16)
	cam.look_at(Vector3.ZERO)
	cam.current = true
	await _frames(10)
	_snap("dbg_wide_high.png")

	# D: gameplay camera, HIGH tier
	if old_cam != null:
		old_cam.current = true
	cam.queue_free()
	await _frames(10)
	_snap("dbg_high.png")

	print("DEBUG SHOT DONE")
	gs.delete_save()
	quit(0)
