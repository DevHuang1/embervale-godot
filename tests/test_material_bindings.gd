extends SceneTree

## Headless test: UE material wiring — every realm terrain material binds
## the scanned PBR sets, all custom shaders still parse, and the new
## world_pusher_1/2/3 shader globals are registered.

const SHADERS := [
	"res://assets/shaders/terrain_ground.gdshader",
	"res://assets/shaders/terrain_ground_layers.gdshader",
	"res://assets/shaders/rock.gdshader",
	"res://assets/shaders/bark.gdshader",
	"res://assets/shaders/canopy.gdshader",
	"res://assets/shaders/grass_blade.gdshader",
	"res://assets/shaders/entity_body.gdshader",
]

const REALM_MATERIALS := ["bramblewood", "whispergrove", "mistfen",
	"heartwood", "moonfen"]

const BOUND_SAMPLERS := ["grass_tex", "dirt_tex", "sand_tex", "rock_tex",
	"moss_tex", "mud_tex",
	"grass_norm", "dirt_norm", "sand_norm", "rock_norm",
	"grass_rough", "dirt_rough", "sand_rough", "rock_rough"]

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(25.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — test hung")
		quit(2))

func _run() -> void:
	var failures := 0

	for path in SHADERS:
		var sh := load(path) as Shader
		if sh == null:
			failures += 1
			print("FAIL: shader failed to parse: ", path)

	for realm in REALM_MATERIALS:
		var path := "res://assets/materials/terrain_%s.tres" % realm
		if not ResourceLoader.exists(path):
			failures += 1
			print("FAIL: missing realm material: ", path)
			continue
		var mat := load(path) as ShaderMaterial
		if mat == null or mat.shader == null:
			failures += 1
			print("FAIL: realm material invalid: ", path)
			continue
		if not mat.shader.resource_path.ends_with("terrain_ground.gdshader"):
			failures += 1
			print("FAIL: realm material does not use terrain_ground shader: ", path)
		for sampler in BOUND_SAMPLERS:
			var tex = mat.get_shader_parameter(sampler)
			if tex == null or not (tex is Texture2D):
				failures += 1
				print("FAIL: %s unbound sampler '%s'" % [path, sampler])
		var moss_strength := float(mat.get_shader_parameter("moss_strength"))
		var moisture_strength := float(mat.get_shader_parameter("moisture_strength"))
		if moss_strength <= 0.0 or moisture_strength <= 0.0:
			failures += 1
			print("FAIL: %s has no readable moss/moisture profile" % path)

	for surface in ["moss", "mud"]:
		var surface_path := "res://assets/textures/stylized/%s_v2/albedo.png" % surface
		var surface_texture := load(surface_path) as Texture2D
		if surface_texture == null or surface_texture.get_width() > 512:
			failures += 1
			print("FAIL: %s is missing or exceeds the mobile texture size budget" % surface_path)
		var import_text := FileAccess.get_file_as_string(surface_path + ".import")
		if not import_text.contains("mipmaps/generate=true"):
			failures += 1
			print("FAIL: %s has mipmaps disabled" % surface_path)

	# --- Entity v3 material pass ---
	const ENTITY_MATERIALS := ["entity_hero", "entity_hero_ember", "entity_hushling", "entity_boss"]
	for em_name in ENTITY_MATERIALS:
		var mp := "res://assets/materials/%s.tres" % em_name
		if not ResourceLoader.exists(mp):
			failures += 1
			print("FAIL: missing entity material: ", mp)
			continue
		var em := load(mp) as ShaderMaterial
		if em == null or em.shader == null:
			failures += 1
			print("FAIL: entity material invalid: ", mp)
			continue
		if not em.shader.resource_path.ends_with("entity_body.gdshader"):
			failures += 1
			print("FAIL: %s not an entity_body material" % mp)

	for pusher in ["world_pusher_1", "world_pusher_2", "world_pusher_3"]:
		var globals: Dictionary = ProjectSettings.get_setting(
			"shader_globals/%s" % pusher, {})
		if globals.is_empty() or str(globals.get("type", "")) != "vec4":
			failures += 1
			print("FAIL: %s shader global not declared as vec4" % pusher)

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(failures if failures > 0 else 0)
