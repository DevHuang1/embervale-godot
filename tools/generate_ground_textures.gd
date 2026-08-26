extends SceneTree

## === Ground Texture Foundry (offline tool) ===
## Generates seamless tileable ground detail textures for terrain_ground:
##   - ground_grass_albedo.png — clumpy turf structure (neutral, tinted in-shader)
##   - ground_dirt_albedo.png  — cloddy soil blotches
##   - ground_sand_albedo.png  — soft dune ripples (low contrast, smooth)
##   - ground_rock_albedo.png  — fractured stone facets
##   - ground_normal.png       — shared micro-height normal for close range
##
## All maps wrap seamlessly: every noise lookup goes through a 4-corner
## blend across the tile period, so edges match exactly.
##
## Run:  Godot --headless --path . --script tools/generate_ground_textures.gd

const OUT := "res://assets/textures/generated/"
const SIZE := 512
const PERIOD := 64.0   # world units one tile spans; matches shader uv scale

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var t0 := Time.get_ticks_msec()
	_grass()
	_dirt()
	_sand()
	_rock()
	_normal_map()
	print("GROUND TEXTURE GENERATION DONE in %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)

# === Helpers ===

func _fbm(seed_v: int, freq: float, octaves: int = 4,
		kind := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.noise_type = kind
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_gain = 0.5
	return n

## Seamless 2D sample: blends four noise evaluations shifted by one tile
## period so value(period) == value(0) on both axes.
func _tile2(n: FastNoiseLite, wx: float, wz: float) -> float:
	var u := fract(wx / PERIOD)
	var v := fract(wz / PERIOD)
	var a := n.get_noise_2d(wx, wz)
	var b := n.get_noise_2d(wx - PERIOD, wz)
	var c := n.get_noise_2d(wx, wz - PERIOD)
	var d := n.get_noise_2d(wx - PERIOD, wz - PERIOD)
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)

func fract(x: float) -> float:
	return x - floor(x)

func _save(img: Image, name: String) -> void:
	img.save_png(OUT + name)
	print("  wrote %s" % name)

## Grass: layered clump masses, blade-y ridge streaks and fine grain.
func _grass() -> void:
	var clump := _fbm(101, 0.09, 4)
	var blades := _fbm(103, 0.85, 3, FastNoiseLite.TYPE_SIMPLEX)
	var ridge_n := FastNoiseLite.new()
	ridge_n.seed = 107
	ridge_n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridge_n.frequency = 0.32
	ridge_n.fractal_octaves = 3
	ridge_n.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		var wz := float(y) / float(SIZE) * PERIOD
		for x in SIZE:
			var wx := float(x) / float(SIZE) * PERIOD
			var mass := 0.58 + 0.26 * _tile2(clump, wx, wz)
			var ridge: float = 1.0 - abs(_tile2(ridge_n, wx, wz))
			var fine := _tile2(blades, wx * 7.0, wz * 7.0)
			var g := clampf(mass + 0.16 * (ridge - 0.55) + 0.14 * fine,
				0.15, 1.0)
			# Near-neutral so realm tints own the hue; faint cool bias.
			img.set_pixel(x, y, Color(g * 0.965, g, g * 1.03))
	_save(img, "ground_grass_albedo.png")

## Dirt: soft clod blotches, root flecks and crumb grain.
func _dirt() -> void:
	var clod := _fbm(211, 0.13, 4)
	var fleck := _fbm(213, 0.9, 2)
	var root := FastNoiseLite.new()
	root.seed = 217
	root.noise_type = FastNoiseLite.TYPE_CELLULAR
	root.frequency = 0.22
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		var wz := float(y) / float(SIZE) * PERIOD
		for x in SIZE:
			var wx := float(x) / float(SIZE) * PERIOD
			var base := 0.52 + 0.30 * _tile2(clod, wx, wz)
			var cells := _tile2(root, wx, wz)
			var g := clampf(base + 0.12 * cells + 0.10 * _tile2(fleck, wx, wz),
				0.18, 1.0)
			img.set_pixel(x, y, Color(g, g * 0.985, g * 0.955))
	_save(img, "ground_dirt_albedo.png")

## Sand: smooth dune macro + gentle wind ripples, deliberately low-contrast.
func _sand() -> void:
	var dune := _fbm(311, 0.035, 3)
	var warp := _fbm(313, 0.07, 2)
	var dust := _fbm(317, 1.4, 2)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		var wz := float(y) / float(SIZE) * PERIOD
		for x in SIZE:
			var wx := float(x) / float(SIZE) * PERIOD
			var drift := _tile2(dune, wx, wz) * 0.5 + 0.5
			var phase := wx * 1.35 + wz * 0.22 + _tile2(warp, wx, wz) * 7.5
			var ripple := sin(phase) * 0.055
			var g := clampf(0.68 + 0.16 * drift + ripple
				+ 0.045 * _tile2(dust, wx, wz), 0.35, 1.0)
			img.set_pixel(x, y, Color(g, g * 0.98, g * 0.93))
	_save(img, "ground_sand_albedo.png")

## Rock: faceted fracture plates with hairline cracks between them.
func _rock() -> void:
	var facet := FastNoiseLite.new()
	facet.seed = 411
	facet.noise_type = FastNoiseLite.TYPE_CELLULAR
	facet.frequency = 0.16
	var crack := _fbm(413, 0.5, 3)
	var tone := _fbm(417, 0.11, 3)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		var wz := float(y) / float(SIZE) * PERIOD
		for x in SIZE:
			var wx := float(x) / float(SIZE) * PERIOD
			var plate := _tile2(facet, wx, wz)
			var edge := 1.0 - smoothstep(0.02, 0.14, plate)
			var g := clampf(0.56 + 0.24 * _tile2(tone, wx, wz)
				+ 0.10 * _tile2(crack, wx, wz) - edge * 0.38, 0.12, 1.0)
			img.set_pixel(x, y, Color(g * 0.99, g, g * 0.97))
	_save(img, "ground_rock_albedo.png")

## Shared micro normal: sobel over a seamless multi-scale height field.
func _normal_map() -> void:
	var h1 := _fbm(511, 0.55, 3)
	var h2 := _fbm(513, 1.7, 2)
	var h3 := _fbm(517, 0.16, 3)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var strength := 1.9
	for y in SIZE:
		var wz := float(y) / float(SIZE) * PERIOD
		for x in SIZE:
			var wx := float(x) / float(SIZE) * PERIOD
			var e := PERIOD / float(SIZE)
			var hx1 := _height_at(h1, h2, h3, wx + e, wz) \
				- _height_at(h1, h2, h3, wx - e, wz)
			var hy1 := _height_at(h1, h2, h3, wx, wz + e) \
				- _height_at(h1, h2, h3, wx, wz - e)
			var nx := clampf(-hx1 * strength * 0.5, -1.0, 1.0)
			var ny := clampf(-hy1 * strength * 0.5, -1.0, 1.0)
			# Tangent-space normal encoded to RGB
			img.set_pixel(x, y, Color(nx * 0.5 + 0.5, ny * 0.5 + 0.5, 1.0))
	_save(img, "ground_normal.png")

func _height_at(a: FastNoiseLite, b: FastNoiseLite, c: FastNoiseLite,
		wx: float, wz: float) -> float:
	return _tile2(a, wx, wz) * 0.55 + _tile2(b, wx, wz) * 0.25 \
		+ _tile2(c, wx, wz) * 0.20
