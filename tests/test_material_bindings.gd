extends SceneTree

## Headless test: UE material wiring — every realm terrain material binds
## the scanned PBR sets, all custom shaders still parse, and the new
## world_pusher_1/2/3 shader globals are registered.

const SHADERS := [
	"res://assets/shaders/terrain_ground.gdshader",
	"res://assets/shaders/rock.gdshader",
	"res://assets/shaders/bark.gdshader",
	"res://assets/shaders/canopy.gdshader",
	"res://assets/shaders/grass_blade.gdshader",
	"res://assets/shaders/entity_body.gdshader",
]

const REALM_MATERIALS := ["bramblewood", "whispergrove", "mistfen",
	"heartwood", "moonfen"]

const BOUND_SAMPLERS := ["grass_tex", "dirt_tex", "sand_tex", "rock_tex",
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
		for sampler in BOUND_SAMPLERS:
			var tex = mat.get_shader_parameter(sampler)
			if tex == null or not (tex is Texture2D):
				failures += 1
				print("FAIL: %s unbound sampler '%s'" % [path, sampler])

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
