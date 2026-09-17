extends SceneTree

## Regression: world-facing encounter ground cues must not expose square mesh
## bounds.  This checks the runtime node rather than only the source text.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var bramblewood_scene := load("res://scenes/world/grove.tscn") as PackedScene
	if bramblewood_scene == null:
		push_error("FAIL: Bramblewood scene failed to load")
		quit(1)
		return
	var world := bramblewood_scene.instantiate()
	root.add_child(world)
	current_scene = world
	for _frame in 4:
		await process_frame
	var terrain_mesh := world.get_node_or_null("Terrain/TerrainMesh") as MeshInstance3D
	var ground_material := terrain_mesh.material_override as ShaderMaterial \
		if terrain_mesh != null else null
	if ground_material == null \
			or not is_zero_approx(float(ground_material.get_shader_parameter("accent_strength"))) \
			or not is_zero_approx(float(ground_material.get_shader_parameter("ember_fleck_density"))) \
			or not is_zero_approx(float(ground_material.get_shader_parameter("ember_fleck_intensity"))):
		push_error("FAIL: terrain must not render square ground flecks")
		quit(1)
		return
	world.queue_free()
	await process_frame

	var foliage := preload("res://scripts/systems/ambient_foliage_patch.gd").new() as AmbientFoliagePatch
	foliage.setup("bramblewood", 7, 1)
	root.add_child(foliage)
	await process_frame
	var foliage_mesh := foliage.multimesh.mesh as QuadMesh if foliage.multimesh != null else null
	var foliage_material := foliage_mesh.material as StandardMaterial3D if foliage_mesh != null else null
	if foliage_material == null or foliage_material.albedo_texture == null \
			or not str(foliage_material.albedo_texture.resource_path).ends_with("/sprite_0001.png"):
		push_error("FAIL: streamed foliage must use one transparent silhouette, not the full atlas")
		quit(1)
		return
	foliage.queue_free()
	await process_frame

	var zone := preload("res://scripts/entities/encounter_zone.gd").new() as EncounterZone
	zone.name = "GroundShapeProbe"
	zone.setup("bramblewood", "elite", 0)
	root.add_child(zone)
	await process_frame

	var decal := zone.get_node_or_null("ZoneDecal") as MeshInstance3D
	var disc := decal.mesh as CylinderMesh if decal != null else null
	if disc == null:
		push_error("FAIL: encounter ground cue must use a round CylinderMesh")
		quit(1)
		return
	if disc.radial_segments < 16 or not is_equal_approx(disc.top_radius, zone.zone_radius) \
			or not is_equal_approx(disc.bottom_radius, zone.zone_radius):
		push_error("FAIL: encounter ground cue has invalid round footprint")
		quit(1)
		return
	if decal.rotation != Vector3.ZERO:
		push_error("FAIL: round ground cue should not rely on quad rotation")
		quit(1)
		return

	zone.queue_free()
	await process_frame
	print("GROUND SHAPE CONTRACT PASSED")
	quit(0)
