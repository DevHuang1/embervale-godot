extends SceneTree

const MAPS := [
	"enemy_skin_v2_albedo.png",
	"enemy_skin_v2_normal.png",
	"enemy_skin_v2_orm.png",
	"enemy_skin_v2_emission.png",
]

func _initialize() -> void:
	var failures := 0
	for filename in MAPS:
		var path := "res://assets/textures/generated/%s" % filename
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		if image == null or image.is_empty() or image.get_size() != Vector2i(1024, 1024):
			failures += 1
			print("FAIL: invalid enemy map ", filename)
			continue
		var edge_error := _edge_error(image)
		if edge_error > 0.012:
			failures += 1
			print("FAIL: enemy map seam ", filename, " error=", edge_error)
	var material := load("res://assets/materials/entity_hushling.tres") as ShaderMaterial
	if material == null:
		failures += 1
		print("FAIL: enemy material missing")
	else:
		var expected := {
			"albedo_texture": "enemy_skin_v2_albedo.png",
			"normal_texture": "enemy_skin_v2_normal.png",
			"orm_texture": "enemy_skin_v2_orm.png",
			"emission_mask": "enemy_skin_v2_emission.png",
		}
		for parameter in expected:
			var texture := material.get_shader_parameter(parameter) as Texture2D
			if texture == null or not texture.resource_path.ends_with(expected[parameter]):
				failures += 1
				print("FAIL: enemy material binding ", parameter)
	for scene_path in ["ember_warden", "mire_stalker", "relic_leech",
			"spore_weaver", "thorn_charger"]:
		if load("res://scenes/entities/%s.tscn" % scene_path) == null:
			failures += 1
			print("FAIL: realm enemy scene no longer loads: ", scene_path)
	print("ENEMY TEXTURE TESTS PASSED" if failures == 0 else "%d ENEMY TEXTURE FAILURES" % failures)
	quit(1 if failures > 0 else 0)

func _edge_error(image: Image) -> float:
	var width := image.get_width()
	var height := image.get_height()
	var total := 0.0
	for y in height:
		total += _color_error(image.get_pixel(0, y), image.get_pixel(width - 1, y))
	for x in width:
		total += _color_error(image.get_pixel(x, 0), image.get_pixel(x, height - 1))
	return total / float(width + height)

func _color_error(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
