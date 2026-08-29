extends SceneTree

## Headless visual-pass validation.
## - Every realm scene boots without script errors (autoloads initialized).
## - The active terrain material binds the stylized albedo/normal/roughness
##   masters (regression guard: scanned PBR or missing samplers fail here).
## - Moonfen keeps its fen water shader + ReflectionProbe and stylized stone.
## Uses the existing Bestiary biome mapping so realm ids stay source-of-truth.

const REALMS := ["bramblewood", "whispergrove", "mistfen", "heartwood", "moonfen"]

const STYLIZED_SAMPLERS := [
	"grass_tex", "grass_norm", "grass_rough",
	"dirt_tex", "dirt_norm", "dirt_rough",
	"sand_tex", "sand_norm", "sand_rough",
	"rock_tex", "rock_norm", "rock_rough",
]

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(60.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — realm visuals test hung")
		quit(2))

func _run() -> void:
	var failures := 0
	var finals := 0
	var gs := root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()

	for realm in REALMS:
		var scene_path: String = Bestiary.biome_scene(realm) \
			if realm != "whispergrove" else "res://scenes/world/grove.tscn"
		if not ResourceLoader.exists(scene_path):
			failures += 1
			print("FAIL: realm scene missing -> ", realm, " ", scene_path)
			continue
		# Whispergrove renders through the shared grove (biome bramblewood).
		gs.set_current_realm(realm)
		var scene: Node = (load(scene_path) as PackedScene).instantiate()
		root.add_child(scene)
		for i in 6:
			await process_frame

		var terrain := _find_terrain_material(scene)
		if terrain == null:
			failures += 1
			print("FAIL: no terrain_ground material in ", realm)
			scene.queue_free()
			continue
		for sampler in STYLIZED_SAMPLERS:
			var tex = terrain.get_shader_parameter(sampler)
			if tex == null or not (tex is Texture2D):
				failures += 1
				print("FAIL: %s unbound samplers -> %s" % [realm, sampler])
				continue
			var t := tex as Texture2D
			if t.resource_path.is_empty() or not t.resource_path.contains("stylized"):
				failures += 1
				print("FAIL: %s sampler %s not bound to stylized master (%s)"
					% [realm, sampler, t.resource_path])

		if realm == "moonfen":
			failures += _check_moonfen(scene, failures)

		scene.queue_free()
		await process_frame
		finals += 1
		gs.reset()

	if finals == 0:
		failures += 1
		print("FAIL: no realm scene could boot")

	if failures == 0:
		print("ALL REALM VISUAL TESTS PASSED (booted=%d)" % finals)
	else:
		print("%d FAILURES" % failures)
	quit(0 if failures == 0 else 1)


func _find_terrain_material(scene: Node) -> ShaderMaterial:
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m := mi.material_override as ShaderMaterial
		if m != null and m.shader != null \
				and m.shader.resource_path.contains("terrain_ground.gdshader"):
			return m
	return null


## Moonfen visual contract: fen water shader on the water plane, a live
## ReflectionProbe for glints, and stylized stone used by the ruin dressing.
func _check_moonfen(scene: Node, failures: int) -> int:
	var f := 0
	var water := scene.find_children("WaterPlane", "MeshInstance3D", true, false)
	if water.is_empty():
		f += 1
		print("FAIL: moonfen missing WaterPlane")
	else:
		var mat := (water[0] as MeshInstance3D).material_override as ShaderMaterial
		if mat == null or mat.shader == null \
				or not mat.shader.resource_path.contains("water_fen.gdshader"):
			f += 1
			print("FAIL: moonfen WaterPlane does not use water_fen shader")
	var probes := scene.find_children("FenReflection", "ReflectionProbe", true, false)
	if probes.is_empty():
		f += 1
		print("FAIL: moonfen missing ReflectionProbe")
	# Stylized stone rebound on the ruin dressing material (material_override
	# and per-surface materials both count).
	var found_stylized := false
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var candidates: Array[ShaderMaterial] = []
		var ov := (mi as MeshInstance3D).material_override as ShaderMaterial
		if ov != null:
			candidates.append(ov)
		var mesh := (mi as MeshInstance3D).mesh
		if mesh != null:
			for s in mesh.get_surface_count():
				var sm := mesh.surface_get_material(s) as ShaderMaterial
				if sm != null:
					candidates.append(sm)
		for sm in candidates:
			if sm.shader == null:
				continue
			if not sm.shader.resource_path.contains("rock.gdshader"):
				continue
			var albedo = sm.get_shader_parameter("rock_albedo_tex") as Texture2D
			if albedo != null and albedo.resource_path.contains("stylized/rock"):
				found_stylized = true
				break
		if found_stylized:
			break
	if not found_stylized:
		f += 1
		print("FAIL: moonfen rock shader not bound to stylized rock masters")
	return f