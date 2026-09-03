extends SceneTree

## Ground-focused probe: boots a realm, hides everything except terrain,
## prints live shader params, snaps a straight-down ground shot.
##   godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
##     --script tests/diag_ground_probe.gd -- --scene res://scenes/world/heartwood.tscn --out /tmp/g.png

var _scene := "res://scenes/world/grove.tscn"
var _out := "/tmp/ground_probe.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(0, args.size() - 1, 2):
		match args[i]:
			"--scene":
				_scene = args[i + 1]
			"--out":
				_out = args[i + 1]
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _snap(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path, " ", img.get_size())


func _run() -> void:
	var gs = root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()
	if gs.get("current_realm") != null:
		pass # realm resolved by biome_id in scene
	change_scene_to_file(_scene)
	await _frames(120)
	# Force a consistent bright-morning sun so realm palettes are comparable
	# (the day/night start time is otherwise random and dusk blue-washes warm biomes).
	var dn2 := root.get_node_or_null("DayNightCycle")
	if dn2 == null and current_scene != null:
		for n6 in current_scene.get_children():
			if str(n6.get_script().resource_path if n6.get_script() else "").contains("day_night"):
				dn2 = n6
				break
	if dn2 != null and "time_of_day" in dn2:
		dn2.set("time_of_day", 0.28)
		await _frames(5)
	var trelief: Node = null
	# find TerrainRelief's mesh by traversing current scene
	var cur := current_scene
	if cur != null:
		var stack: Array = [cur]
		while not stack.is_empty():
			var n2 = stack.pop_back()
			if n2 is MeshInstance3D and n2.name == "TerrainMesh":
				trelief = n2
				break
			stack.append_array(n2.get_children())
		# Lighting diagnosis: what is actually tinting the surface?
		var we := trelief.get_node_or_null("../WorldEnvironment")
		if we == null:
			var stack2: Array = [cur]
			while not stack2.is_empty():
				var n3 = stack2.pop_back()
				if n3 is WorldEnvironment:
					we = n3
					break
				stack2.append_array(n3.get_children())
		if we != null and we.environment != null:
			var env: Environment = we.environment
			print("  ENV ambient=", env.ambient_light_color,
				" energy=", env.ambient_light_energy,
				" src=", env.ambient_light_source,
				" fog=", env.fog_light_color,
				" fogden=", env.fog_density)
		for n4 in cur.get_children():
			if n4 is DirectionalLight3D:
				print("  SUN color=", n4.light_color, " energy=", n4.light_energy)
		var dn := root.get_node_or_null("DayNightCycle")
		if dn == null:
			for n5 in cur.get_children():
				if n5.name.to_lower().contains("daynight") or n5.get_script() != null \
						and str(n5.get_script().resource_path).contains("day_night"):
					dn = n5
					break
		if dn != null:
			for prop in ["time_of_day", "day_time", "hour", "phase"]:
				if dn.get(prop) != null:
					print("  DAYNIGHT ", prop, " = ", dn.get(prop))
		# Hide all siblings (vegetation, entities, props) for pure-ground view
	if trelief != null:
		var mat: ShaderMaterial = trelief.material_override
		print("MAT shader=", mat.shader.resource_path)
		for k in ["tex_saturation", "tex_gain", "tex_blend", "grass_color",
				"terrain_brightness", "uv_world_scale", "realm_tint"]:
			print("  param ", k, " = ", mat.get_shader_parameter(k))
		# Hide all siblings (vegetation, entities, props) for pure-ground view
		for child in trelief.get_parent().get_children():
			if child != trelief and child is Node3D:
				child.visible = false
		# Scene-root particle volumes (mist/fireflies) sit ABOVE the ground and
		# can dominate a straight-down probe — suppress for diagnosis.
		var we2: WorldEnvironment = null
		for n7 in cur.get_children():
			if n7 is GPUParticles3D:
				n7.emitting = false
				n7.visible = false
			elif n7 is WorldEnvironment:
				we2 = n7
		# Straight-down camera near gameplay altitude
		var cam := Camera3D.new()
		cur.add_child(cam)
		cam.make_current()
		cam.global_position = Vector3(0.0, 12.0, 0.0)
		cam.look_at(Vector3(0.0, 0.0, 0.001))
		cam.near = 0.05
		cam.far = 120.0
		await _frames(30)
		_snap(_out)
		# Second shot with fog off: isolates aerial-perspective tint.
		if we2 != null and we2.environment != null:
			we2.environment.fog_enabled = false
			await _frames(10)
			_snap(_out.replace(".png", "_nofog.png"))
		print("GROUND PROBE DONE")
	else:
		print("NO TERRAIN MESH FOUND")
	gs.delete_save()
	quit(0)
