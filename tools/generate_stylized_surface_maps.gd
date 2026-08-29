extends SceneTree

## Builds runtime-ready stylized PBR maps from the selected albedo masters.
## Masters are never overwritten. The edge pass pairs opposite texels and
## feathers the correction inward, which gives mip-safe, exactly matching
## borders without blurring the middle of the painted texture.
##
## Run:
##   godot --headless --path . --script tools/generate_stylized_surface_maps.gd

const ROOT := "res://assets/textures/stylized"
const SIZE := 1024
const SEAM_WIDTH := 72

const SURFACES := {
	"grass": {"normal": 2.1, "roughness": 0.86},
	"dirt": {"normal": 1.7, "roughness": 0.91},
	"sand": {"normal": 1.15, "roughness": 0.88},
	"rock": {"normal": 2.35, "roughness": 0.78},
	"bark": {"normal": 2.45, "roughness": 0.84},
	"wood": {"normal": 1.85, "roughness": 0.80},
	"clay": {"normal": 1.35, "roughness": 0.73},
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures := 0
	for surface: String in SURFACES:
		var source_path := "%s/%s/albedo_master.png" % [ROOT, surface]
		var image := Image.load_from_file(source_path)
		if image == null or image.is_empty():
			push_error("Missing stylized master: %s" % source_path)
			failures += 1
			continue
		image.convert(Image.FORMAT_RGBA8)
		image.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
		var albedo := _make_periodic(image)
		var surface_root := "%s/%s" % [ROOT, surface]
		albedo.save_png("%s/albedo.png" % surface_root)
		_make_normal(albedo, float(SURFACES[surface]["normal"])) \
			.save_png("%s/normal.png" % surface_root)
		_make_roughness(albedo, float(SURFACES[surface]["roughness"])) \
			.save_png("%s/roughness.png" % surface_root)
		var edge_error := _edge_error(albedo)
		print("STYLIZED_SURFACE %s edge_error=%.6f" % [surface, edge_error])
		if edge_error > 0.004:
			push_error("Seam tolerance exceeded for %s" % surface)
			failures += 1
	print("STYLIZED SURFACE FOUNDRY: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(failures)


func _make_periodic(source: Image) -> Image:
	var out := source.duplicate()
	# Pair left/right texels and feather the shared average toward the center.
	for y in SIZE:
		for x in SEAM_WIDTH:
			var opposite := SIZE - 1 - x
			var t := smoothstep(0.0, float(SEAM_WIDTH - 1), float(x))
			var a: Color = source.get_pixel(x, y)
			var b: Color = source.get_pixel(opposite, y)
			var average: Color = (a + b) * 0.5
			out.set_pixel(x, y, average.lerp(a, t))
			out.set_pixel(opposite, y, average.lerp(b, t))
	# Do the same vertically after the horizontal correction so corners agree.
	var horizontal := out.duplicate()
	for x in SIZE:
		for y in SEAM_WIDTH:
			var opposite := SIZE - 1 - y
			var t := smoothstep(0.0, float(SEAM_WIDTH - 1), float(y))
			var a: Color = horizontal.get_pixel(x, y)
			var b: Color = horizontal.get_pixel(x, opposite)
			var average: Color = (a + b) * 0.5
			out.set_pixel(x, y, average.lerp(a, t))
			out.set_pixel(x, opposite, average.lerp(b, t))
	return out


func _make_normal(albedo: Image, strength: float) -> Image:
	var out := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		var ym := wrapi(y - 1, 0, SIZE)
		var yp := wrapi(y + 1, 0, SIZE)
		for x in SIZE:
			var xm := wrapi(x - 1, 0, SIZE)
			var xp := wrapi(x + 1, 0, SIZE)
			var dx := _height(albedo.get_pixel(xp, y)) - _height(albedo.get_pixel(xm, y))
			var dy := _height(albedo.get_pixel(x, yp)) - _height(albedo.get_pixel(x, ym))
			var normal := Vector3(-dx * strength, -dy * strength, 1.0).normalized()
			out.set_pixel(x, y, Color(normal.x * 0.5 + 0.5,
				normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5, 1.0))
	return out


func _make_roughness(albedo: Image, base: float) -> Image:
	var out := Image.create(SIZE, SIZE, false, Image.FORMAT_L8)
	for y in SIZE:
		for x in SIZE:
			var lum := _height(albedo.get_pixel(x, y))
			# Dark creases are slightly rougher; raised painted planes catch a
			# broader highlight. Keep the range tight to avoid mobile shimmer.
			var rough := clampf(base + (0.5 - lum) * 0.18, 0.58, 0.96)
			out.set_pixel(x, y, Color(rough, rough, rough, 1.0))
	return out


func _height(color: Color) -> float:
	return color.r * 0.299 + color.g * 0.587 + color.b * 0.114


func _edge_error(image: Image) -> float:
	var maximum := 0.0
	for i in SIZE:
		maximum = maxf(maximum, _color_delta(
			image.get_pixel(0, i), image.get_pixel(SIZE - 1, i)))
		maximum = maxf(maximum, _color_delta(
			image.get_pixel(i, 0), image.get_pixel(i, SIZE - 1)))
	return maximum


func _color_delta(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
