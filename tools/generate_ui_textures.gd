extends SceneTree

## === UI Texture Foundry (offline tool) ===
## Generates the procedural UI surface textures referenced by UiKit:
##   - ui_parchment_paper.png  — warm parchment albedo w/ fiber grain + edge vignette
##   - ui_parchment_ink.png    — ink-wash edge/darken mask (greyscale, alpha-friendly)
##   - ui_ink_wash.png         — translucent watercolor bleed for dialog backdrops
##
## Hand-painted masters can replace any of these PNGs later at the same
## resolution/path — the resource bindings won't change.
##
## Run:  Godot --headless --path . --script tools/generate_ui_textures.gd

const OUT := "res://assets/textures/generated/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var t0 := Time.get_ticks_msec()
	_parchment_paper()
	_parchment_ink()
	_ink_wash()
	print("UI TEXTURE GENERATION DONE in %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)

# === Helpers ===

func _fbm(seed_v: int, freq: float, octaves: int = 4) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_gain = 0.5
	return n

func _new_img(size: int, fmt := Image.FORMAT_RGBA8) -> Image:
	return Image.create(size, size, false, fmt)

func _save(img: Image, name: String) -> void:
	img.save_png(OUT + name)

## Parchment: warm cream base with fine fiber grain and a soft vignette so
## edges darken — reads as aged paper under the frosted panels.
func _parchment_paper() -> void:
	var size := 512
	var fiber := _fbm(71, 120.0, 3)
	var pore := _fbm(73, 48.0, 3)
	var img := _new_img(size)
	for y in size:
		for x in size:
			var fx := float(x) / float(size)
			var fy := float(y) / float(size)
			var f := 0.5 - sqrt(pow(fx - 0.5, 2.0) + pow(fy - 0.5, 2.0))
			var vignette := clampf(0.38 + f * 0.62, 0.0, 1.0)
			var g := fiber.get_noise_2d(x, y) * 0.5 + 0.5
			var p := pore.get_noise_2d(x * 3.0, y * 3.0) * 0.5 + 0.5
			var warmth := 0.92 + p * 0.08
			var paper := Color(
				clampf(vignette * (0.92 - (1.0 - warmth) * 0.04), 0.0, 1.0),
				clampf(vignette * warmth * 0.86, 0.0, 1.0),
				clampf(vignette * (0.72 - (1.0 - warmth) * 0.05), 0.0, 1.0),
				1.0)
			# fiber grain modulation
			paper.r += (g - 0.5) * 0.035
			paper.g += (g - 0.5) * 0.042
			paper.b += (g - 0.5) * 0.028
			img.set_pixel(x, y, paper)
	_save(img, "ui_parchment_paper.png")

## Ink-wash edge mask: greyscale dark near corners/edges, near-zero in center.
## Used as a luminance mask to tint panel borders an inky dark.
func _parchment_ink() -> void:
	var size := 512
	var crack := _fbm(77, 9.0, 2)
	var spl := _fbm(79, 34.0, 3)
	var img := _new_img(size)
	for y in size:
		for x in size:
			var fx := float(x) / float(size)
			var fy := float(y) / float(size)
			var d := minf(minf(fx, 1.0 - fx), minf(fy, 1.0 - fy))
			var edge := smoothstep(0.55, 0.08, d)
			var c := crack.get_noise_2d(x, y) * 0.5 + 0.5
			var s := spl.get_noise_2d(x, y) * 0.5 + 0.5
			var m := clampf(edge * 0.78 + c * 0.18 + s * 0.12, 0.0, 1.0)
			img.set_pixel(x, y, Color(m, m, m, m))
	_save(img, "ui_parchment_ink.png")

## Translucent ink wash: a faint bleeding stain centered with a darkened
## perimeter, used as a dialog backdrop to ground floating sheets.
func _ink_wash() -> void:
	var size := 512
	var wash := _fbm(83, 5.2, 3)
	var img := _new_img(size)
	for y in size:
		for x in size:
			var fx := float(x) / float(size)
			var fy := float(y) / float(size)
			var r := sqrt(pow(fx - 0.5, 2.0) + pow(fy - 0.5, 2.0))
			var bloom := clampf(1.0 - r * 2.1, 0.0, 1.0)
			var w := wash.get_noise_2d(x * 2.0, y * 2.0) * 0.5 + 0.5
			var a := clampf(smoothstep(0.0, 0.55, bloom) * (0.22 + w * 0.09), 0.0, 0.55)
			img.set_pixel(x, y, Color(0.06, 0.09, 0.07, a))
	_save(img, "ui_ink_wash.png")
