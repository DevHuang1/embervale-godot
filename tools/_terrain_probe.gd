extends SceneTree

## Terrain surface probe (real renderer, not --headless):
##   godot --path . --script tools/_terrain_probe.gd
## Verifies the ground material contract the player actually sees:
##   * grove gameplay-low + full-coverage overhead shots
##   * material-zone shots (weights, flat tints) proving coherent sand/dirt/
##     grass regions instead of a single green wash
##   * river and pond waterline beaches (region sand disabled so only the
##     shoreline band can render)
##   * the Android mobile shader on the same zones (four-sampler budget)
##   * one wide + one neutral top-down shot per realm so realm palettes and
##     region coverage stay comparable across realms
## Output goes to .captures/.

const REALMS := [
	["whispergrove", "res://scenes/world/grove.tscn"],
	["bramblewood", "res://scenes/world/grove.tscn"],
	["mistfen", "res://scenes/world/mistfen.tscn"],
	["heartwood", "res://scenes/world/heartwood.tscn"],
	["moonfen", "res://scenes/world/moonfen.tscn"],
]

const MOBILE_SHADER := "res://assets/shaders/terrain_ground_mobile.gdshader"
## Uniforms the mobile shader shares with the desktop path. Copied verbatim so
## the probe renders the same realm palette/bindings through the Android shader.
const SHARED_TERRAIN_PARAMS := [
	"grass_tex", "dirt_tex", "sand_tex", "rock_tex",
	"grass_color", "grass_dry", "dirt_color", "sand_color", "stone_color",
	"realm_tint", "realm_tint_strength", "dirt_amount", "sand_amount",
	"uv_world_scale", "tex_gain", "terrain_brightness",
	"region_scale", "region_edge",
	"river_enabled", "river_base_x", "river_meander", "river_wavelen",
	"river_phase", "river_detail", "river_half_width", "river_beach",
	"pond_a", "pond_b", "pond_c",
]


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _snap(path: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		print("SKIP(no image): ", path)
		return
	DirAccess.make_dir_recursive_absolute(".captures")
	var err := img.save_png(path)
	print("SNAP ", path, " err=", err, " size=", img.get_size())


## A fresh camera per shot: realm rigs (spring arms, first-person look) keep
## overwriting the hero camera, so the probe owns its own framing. `current`
## is set AFTER the node enters the tree, or a freed predecessor's view wins.
func _add_camera(scene: Node, position: Vector3, look_at: Vector3,
		fov: float = 70.0) -> Camera3D:
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.fov = fov
	cam.global_position = position
	cam.look_at(look_at)
	cam.current = true
	return cam


## Straight-down framing without look_at: a camera whose view direction is
## parallel to UP makes look_at degenerate.
func _add_topdown_camera(scene: Node, height: float, fov: float = 70.0) -> Camera3D:
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.fov = fov
	cam.position = Vector3(0, height, 0.0)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.current = true
	return cam


func _terrain_material(scene: Node) -> ShaderMaterial:
	var terrain := scene.get_node_or_null("Terrain/TerrainMesh") as MeshInstance3D
	if terrain != null and terrain.material_override is ShaderMaterial:
		return terrain.material_override as ShaderMaterial
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override as ShaderMaterial
		if m != null and m.shader != null \
				and m.shader.resource_path.contains("terrain_ground"):
			return m
	return null


func _neutralize_lighting(scene: Node) -> void:
	var we := scene.find_child("Environment", true, false) as WorldEnvironment
	if we == null:
		for candidate in scene.find_children("*", "WorldEnvironment", true, false):
			we = candidate as WorldEnvironment
			break
	if we != null and we.environment != null:
		we.environment = we.environment.duplicate()
		we.environment.fog_enabled = false
		we.environment.volumetric_fog_enabled = false
		we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		we.environment.ambient_light_color = Color(1.0, 1.0, 1.0)
		we.environment.ambient_light_energy = 1.15
	var sun: DirectionalLight3D = null
	for candidate in scene.find_children("*", "DirectionalLight3D", true, false):
		sun = candidate as DirectionalLight3D
		break
	if sun != null:
		sun.light_energy = 1.15
		sun.light_color = Color(1.0, 1.0, 1.0)


func _mobile_material(desktop: ShaderMaterial) -> ShaderMaterial:
	var mobile := ShaderMaterial.new()
	mobile.shader = load(MOBILE_SHADER) as Shader
	for param in SHARED_TERRAIN_PARAMS:
		mobile.set_shader_parameter(param, desktop.get_shader_parameter(param))
	return mobile


func _run() -> void:
	var gs := root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()
	var qs := root.get_node_or_null("/root/WorldState/QualityScaler") as QualityScaler
	if qs != null:
		qs.set_mode(QualityScaler.Mode.HIGH)

	# --- Grove: gameplay-low + full-coverage overhead ---
	change_scene_to_file("res://scenes/world/grove.tscn")
	await _frames(120)
	var scene := current_scene
	var mat := _terrain_material(scene)
	if mat == null:
		push_error("no terrain material found")
		quit(1)
		return

	var cam := _add_camera(scene, Vector3(0, 2.6, 6), Vector3(0, 1.4, 0), 60.0)
	await _frames(4)
	_snap(".captures/terrain_low.png")

	# --- Material zones: lit ground, layer weights, flat tints ---
	_neutralize_lighting(scene)
	cam.queue_free()
	cam = _add_topdown_camera(scene, 170.0)
	mat.set_shader_parameter("moss_strength", 0.0)
	mat.set_shader_parameter("accent_strength", 0.0)
	mat.set_shader_parameter("ember_fleck_intensity", 0.0)
	await _frames(4)
	_snap(".captures/terrain_zones.png")
	mat.set_shader_parameter("debug_view", 1)
	await _frames(3)
	_snap(".captures/terrain_weights.png")
	mat.set_shader_parameter("debug_view", 0)
	mat.set_shader_parameter("tex_blend", 0.0)
	await _frames(3)
	_snap(".captures/terrain_flat_zones.png")
	mat.set_shader_parameter("tex_blend", 0.7)
	mat.set_shader_parameter("moss_strength", 0.58)

	# --- Shoreline beaches: region sand off so only the waterline band shows ---
	var realm_sand: float = float(mat.get_shader_parameter("sand_amount"))
	var realm_dirt: float = float(mat.get_shader_parameter("dirt_amount"))
	mat.set_shader_parameter("sand_amount", 0.0)
	mat.set_shader_parameter("dirt_amount", 0.0)
	var river_x: float = float(mat.get_shader_parameter("river_base_x")) \
		+ float(mat.get_shader_parameter("river_meander"))
	cam.queue_free()
	cam = _add_camera(scene, Vector3(river_x - 4.0, 14.0, 8.0),
		Vector3(river_x, -1.0, -6.0), 60.0)
	await _frames(4)
	_snap(".captures/terrain_river_beach.png")
	cam.queue_free()
	cam = _add_camera(scene, Vector3(25.0, 12.0, 22.0), Vector3(25.0, -0.5, 14.0), 60.0)
	await _frames(4)
	_snap(".captures/terrain_pond_beach.png")

	# --- Android mobile shader on the same ground ---
	mat.set_shader_parameter("sand_amount", realm_sand)
	mat.set_shader_parameter("dirt_amount", realm_dirt)
	var mobile := _mobile_material(mat)
	var terrain_mesh := scene.get_node_or_null("Terrain/TerrainMesh") as MeshInstance3D
	var desktop_override: Material = null
	if terrain_mesh != null:
		desktop_override = terrain_mesh.material_override
		terrain_mesh.material_override = mobile
	cam.queue_free()
	cam = _add_topdown_camera(scene, 170.0)
	await _frames(4)
	_snap(".captures/terrain_mobile_zones.png")
	if terrain_mesh != null:
		terrain_mesh.material_override = desktop_override

	# --- Per-realm identity: game look + neutral zone layout ---
	for entry in REALMS:
		var realm: String = entry[0]
		var realm_path: String = entry[1]
		gs.set_current_realm(realm)
		if realm == "bramblewood":
			gs.current_stage = GameState.QuestStage.COMPLETE
			gs.scans_remaining = 0
		change_scene_to_file(realm_path)
		await _frames(110)
		var realm_scene := current_scene
		var realm_cam := _add_camera(realm_scene, Vector3(0, 22, 26), Vector3(0, 0.5, -4), 62.0)
		await _frames(5)
		_snap(".captures/terrain_%s.png" % realm)
		_neutralize_lighting(realm_scene)
		realm_cam.queue_free()
		_add_topdown_camera(realm_scene, 170.0)
		await _frames(4)
		_snap(".captures/terrain_%s_zones.png" % realm)
		gs.reset()

	print("TERRAIN_PROBE_DONE")
	gs.delete_save()
	quit(0)
