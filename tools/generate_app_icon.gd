extends SceneTree

## === Embervale app-icon foundry (offline tool) ===
##
## Renders the Embervale app mark — an ember flame inside a copper vale-ring on
## a dark vale field — into every slot the Android export and the project icon
## need. One deterministic recipe, no imported art, so the family stays cohesive
## and a rebuild reproduces the same layers.
##
##   app_icon_1024.png             full-bleed master (store art / future iOS)
##   app_icon_512.png              project icon (window + export fallback)
##   app_icon_launcher_192.png     legacy Android launcher (full-bleed)
##   app_icon_foreground_432.png   adaptive foreground (safe-zone, transparent)
##   app_icon_background_432.png   adaptive background (opaque)
##   app_icon_monochrome_432.png   themed icon, Android 13+ (white on alpha)
##   app_icon_mark_512.png         boot splash + Android 12 splash mark
##
## Run: godot --headless --path . --script tools/generate_app_icon.gd

const OUT_DIR := "res://assets/branding/app_icon"

const MASTER_SIZE := 1024
const ADAPTIVE_SIZE := 432
const LAUNCHER_SIZE := 192
const MARK_SIZE := 512

# Adaptive icons live on a 108dp canvas whose visible mask is 72dp and whose
# safe zone is a 66dp circle: 66/108 = 0.611 of the half-canvas.
const SAFE_RADIUS := 0.611
# The mark's own extent (ring outer edge) in mark space; every layer scales it.
const MARK_EXTENT := 0.888
const MASTER_SCALE := 0.84
# Every masked layer keeps a small margin inside the safe circle, so the ring's
# own anti-aliased edge cannot touch the boundary a launcher mask can crop.
const ADAPTIVE_SCALE := SAFE_RADIUS / MARK_EXTENT * 0.96
const MONO_SCALE := 0.72
const MARK_SCALE := SAFE_RADIUS / MARK_EXTENT * 0.96

# Brand palette, mirroring the UiKit tokens so icon and UI cannot drift.
const VALE_DEEP := Color(0.008, 0.014, 0.012)
const VALE := Color(0.043, 0.094, 0.078)
const VALE_RIM := Color(0.075, 0.145, 0.118)
const EMBER := Color(0.961, 0.722, 0.255)
const EMBER_BRIGHT := Color(1.0, 0.84, 0.47)
const EMBER_DEEP := Color(0.78, 0.49, 0.16)
const COPPER := Color(0.847, 0.549, 0.318)
const CREAM := Color(1.0, 0.976, 0.91)

# Mark geometry, in mark space (y up).
const RING_RADIUS := 0.86
const RING_HALF_WIDTH := 0.028
const FLAME_BASE_Y := -0.62
const FLAME_TIP_Y := 0.68
const FLAME_HALF_WIDTH := 0.27
const CORE_CENTER := Vector2(0.0, -0.30)
const CORE_SCALE := 0.50
const SPARKS := [
	{"pos": Vector2(0.42, 0.40), "radius": 0.030},
	{"pos": Vector2(0.55, 0.14), "radius": 0.022},
	{"pos": Vector2(0.30, 0.62), "radius": 0.017},
]

var _grain: FastNoiseLite

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_grain = FastNoiseLite.new()
	_grain.seed = 0x456D62657276  # "Emberv"
	_grain.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_grain.frequency = 0.018

	var master := _render_master(MASTER_SIZE)
	var written := _save(master, "app_icon_%d.png" % MASTER_SIZE)
	written += _save(_downscale(master, 512), "app_icon_512.png")
	written += _save(_downscale(master, LAUNCHER_SIZE),
		"app_icon_launcher_%d.png" % LAUNCHER_SIZE)

	written += _save(_render_mark(ADAPTIVE_SIZE, ADAPTIVE_SCALE, false),
		"app_icon_foreground_%d.png" % ADAPTIVE_SIZE)
	written += _save(_render_background(ADAPTIVE_SIZE),
		"app_icon_background_%d.png" % ADAPTIVE_SIZE)
	written += _save(_render_mark(ADAPTIVE_SIZE, MONO_SCALE, true),
		"app_icon_monochrome_%d.png" % ADAPTIVE_SIZE)
	written += _save(_render_mark(MARK_SIZE, MARK_SCALE, false),
		"app_icon_mark_%d.png" % MARK_SIZE)

	print("APP ICON WRITTEN: %d layers in %d ms" % [written, Time.get_ticks_msec() - t0])
	quit(0 if written == 7 else 1)

# === Layers ===

func _render_master(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	var edge := _edge_for(size, MASTER_SCALE)
	for y in size:
		var ny := 1.0 - (float(y) + 0.5) / half
		for x in size:
			var nx := (float(x) + 0.5) / half - 1.0
			var u := Vector2(nx, ny)
			var bg := _background(u, x, y)
			var mark := _mark_color(u / MASTER_SCALE, edge, false)
			img.set_pixel(x, y, _over(Color(bg.r, bg.g, bg.b, 1.0), mark))
	return img

func _render_mark(size: int, scale: float, monochrome: bool) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	var edge := _edge_for(size, scale)
	for y in size:
		var ny := 1.0 - (float(y) + 0.5) / half
		for x in size:
			var nx := (float(x) + 0.5) / half - 1.0
			var m := Vector2(nx, ny) / scale
			if m.length() > 1.25:
				continue
			img.set_pixel(x, y, _mark_color(m, edge, monochrome))
	return img

func _render_background(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	for y in size:
		var ny := 1.0 - (float(y) + 0.5) / half
		for x in size:
			var nx := (float(x) + 0.5) / half - 1.0
			img.set_pixel(x, y, _background(Vector2(nx, ny), x, y))
	return img

# === Painting ===

## Opaque vale field: a dark radial falloff, a warm ember bloom behind the
## flame, fine grain, and a vignette so the master reads as one plate.
func _background(u: Vector2, x: int, y: int) -> Color:
	var r := Vector2(u.x, u.y - 0.08).length()
	var field := VALE_DEEP.lerp(VALE, clampf(1.0 - r * 0.72, 0.0, 1.0))
	field = field.lerp(VALE_RIM, clampf(0.55 - u.y * 0.35, 0.0, 1.0) * 0.16)
	var bloom := clampf(exp(-pow(r / 0.58, 2.0)) * 0.50, 0.0, 1.0)
	field = field.lerp(EMBER_DEEP, bloom * 0.34)
	var grain := _grain.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
	field.r += (grain - 0.5) * 0.018
	field.g += (grain - 0.5) * 0.022
	field.b += (grain - 0.5) * 0.016
	field *= 1.0 - 0.22 * smoothstep(0.55, 1.42, u.length())
	return Color(clampf(field.r, 0.0, 1.0), clampf(field.g, 0.0, 1.0),
		clampf(field.b, 0.0, 1.0), 1.0)

## The mark itself, back to front: warm halo, copper ring, ember flame, sparks.
func _mark_color(m: Vector2, edge: float, monochrome: bool) -> Color:
	var flame := _flame_sdf(m)
	if monochrome:
		# Themed icons must survive a single-tint mask: flame only, no hairline.
		return Color(1.0, 1.0, 1.0, _cover(flame, edge))
	var out := Color(0.0, 0.0, 0.0, 0.0)
	var halo := clampf(exp(-maxf(flame, 0.0) * 7.0) * 0.34, 0.0, 1.0)
	out = _over(out, Color(EMBER_DEEP.r, EMBER_DEEP.g, EMBER_DEEP.b, halo))
	var ring := absf(m.length() - RING_RADIUS) - RING_HALF_WIDTH
	var ring_col := COPPER.lerp(EMBER, clampf(m.y * 0.5 + 0.5, 0.0, 1.0))
	out = _over(out, Color(ring_col.r, ring_col.g, ring_col.b,
		_cover(ring, edge) * 0.88))
	var core := _flame_sdf((m - CORE_CENTER) / CORE_SCALE + CORE_CENTER)
	var column := smoothstep(FLAME_BASE_Y, 0.02, m.y)
	var flame_col := EMBER_DEEP.lerp(EMBER, column).lerp(
		EMBER_BRIGHT, smoothstep(0.0, FLAME_TIP_Y, m.y))
	var core_w := _cover(core, edge * 1.6) * (1.0 - smoothstep(0.0, 0.45, m.y)) * 0.78
	flame_col = flame_col.lerp(CREAM, clampf(core_w, 0.0, 1.0))
	out = _over(out, Color(flame_col.r, flame_col.g, flame_col.b, _cover(flame, edge)))
	for spark in SPARKS:
		var spark_a := _cover(_sd_circle(m, spark["pos"], spark["radius"]), edge)
		if spark_a > 0.0:
			out = _over(out, Color(EMBER_BRIGHT.r, EMBER_BRIGHT.g, EMBER_BRIGHT.b, spark_a))
	return out

## Straight-alpha "top over base", so layers compose without alpha math at the
## call site.
func _over(base: Color, top: Color) -> Color:
	var a := top.a + base.a * (1.0 - top.a)
	if a <= 0.0001:
		return Color(0.0, 0.0, 0.0, 0.0)
	var keep := base.a * (1.0 - top.a)
	return Color(
		(top.r * top.a + base.r * keep) / a,
		(top.g * top.a + base.g * keep) / a,
		(top.b * top.a + base.b * keep) / a,
		a)

## A flame tongue: widest a quarter of the way up, then a long taper to a point
## at `tip_y`. The lean bends the axis as it rises, so the pair of tongues reads
## as fire rather than as a leaf. The tongue is cut off below `base_y`; the root
## ellipse supplies the rounded base.
func _flame_tongue(p: Vector2, base_y: float, tip_y: float, half_width: float,
		lean: float) -> float:
	var span := maxf(tip_y - base_y, 0.0001)
	var t := clampf((p.y - base_y) / span, 0.0, 1.0)
	var width := half_width * _taper(t)
	var center_x := lean * pow(t, 1.5)
	return maxf(maxf(absf(p.x - center_x) - width, p.y - tip_y), base_y - p.y)

## Peak-normalized tongue profile: a quick rise from the base and a long, thin
## taper to the tip, which is what separates fire from a leaf at 48 px.
func _taper(t: float) -> float:
	return 3.5 * pow(t, 0.55) * pow(1.0 - t, 1.6)

func _flame_sdf(m: Vector2) -> float:
	var body := _flame_tongue(m, FLAME_BASE_Y, FLAME_TIP_Y, FLAME_HALF_WIDTH, -0.26)
	var second := _flame_tongue(m, FLAME_BASE_Y + 0.30, FLAME_TIP_Y - 0.42,
		FLAME_HALF_WIDTH * 0.56, 0.34)
	var root := _sd_ellipse(m, Vector2(0.0, FLAME_BASE_Y + 0.12), Vector2(0.27, 0.22))
	return _smin(_smin(body, second, 0.07), root, 0.14)

# === Signed-distance helpers ===

func _sd_circle(p: Vector2, center: Vector2, radius: float) -> float:
	return (p - center).length() - radius

func _sd_ellipse(p: Vector2, center: Vector2, radii: Vector2) -> float:
	var q := p - center
	return (Vector2(q.x / radii.x, q.y / radii.y).length() - 1.0) * minf(radii.x, radii.y)

func _smin(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)

## Coverage of a one-pixel-wide edge; anti-aliasing follows the layer resolution.
func _cover(distance: float, edge: float) -> float:
	return clampf(0.5 - distance / edge, 0.0, 1.0)

func _edge_for(size: int, scale: float) -> float:
	return (2.0 / float(size)) * 1.35 / scale

func _downscale(source: Image, size: int) -> Image:
	var img := source.duplicate() as Image
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return img

func _save(img: Image, file_name: String) -> int:
	var path := "%s/%s" % [OUT_DIR, file_name]
	if img.save_png(path) != OK:
		push_error("Could not write app icon: %s" % path)
		return 0
	print("  %s  %dx%d" % [file_name, img.get_width(), img.get_height()])
	return 1
