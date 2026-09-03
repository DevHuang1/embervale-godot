extends SceneTree

## === Character Texture Foundry (offline tool) ===
## Generates the PBR texture sets referenced by the v2 entity_body shader:
##   - shared tiling detail normal + albedo grain
##   - hero / boss tangent-space normals + glTF-style ORM (R=AO G=Rough B=Metal)
##   - hushling pod emission mask, hero lantern-glow masks (+ ember variant)
##
## Hand-painted masters can replace any of these PNGs later at the same
## resolution/path — the material bindings won't change.
##
## Run:  Godot --headless --path . --script tools/generate_character_textures.gd

const OUT := "res://assets/textures/generated/"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var t0 := Time.get_ticks_msec()
	if "--enemy-v2-only" in OS.get_cmdline_user_args():
		_enemy_skin_v2()
		print("ENEMY V2 TEXTURES DONE in %d ms" % (Time.get_ticks_msec() - t0))
		quit(0)
		return
	_detail_grain()
	_detail_normal()
	_write_hero_set()
	_hero_ember_variant()
	_hushling_set()
	_boss_set()
	print("TEXTURE GENERATION DONE in %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)

## Regenerable derivative pass for the selected image-generated enemy master.
## The master is never modified; edge wrapping, contrast limiting, normal, ORM,
## and emission extraction always write sibling runtime maps.
func _enemy_skin_v2() -> void:
	var source := Image.load_from_file(OUT + "enemy_skin_v2_master.png")
	if source == null or source.is_empty():
		push_error("Missing enemy_skin_v2_master.png")
		return
	source.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	var size := source.get_width()
	var albedo := source.duplicate()
	var wrap_band := 96
	# Pair and blend opposite borders. At the edge both samples receive the
	# same average; the blend falls away smoothly before the focal region.
	for y in size:
		for x in wrap_band:
			var opposite := size - 1 - x
			var weight := pow(1.0 - float(x) / float(wrap_band), 2.0)
			var average: Color = (albedo.get_pixel(x, y) + albedo.get_pixel(opposite, y)) * 0.5
			albedo.set_pixel(x, y, albedo.get_pixel(x, y).lerp(average, weight))
			albedo.set_pixel(opposite, y, albedo.get_pixel(opposite, y).lerp(average, weight))
	for x in size:
		for y in wrap_band:
			var opposite := size - 1 - y
			var weight := pow(1.0 - float(y) / float(wrap_band), 2.0)
			var average: Color = (albedo.get_pixel(x, y) + albedo.get_pixel(x, opposite)) * 0.5
			albedo.set_pixel(x, y, albedo.get_pixel(x, y).lerp(average, weight))
			albedo.set_pixel(x, opposite, albedo.get_pixel(x, opposite).lerp(average, weight))
	var height := _new_img(size)
	var orm := _new_img(size)
	var emission := _new_img(size)
	for y in size:
		for x in size:
			var color: Color = albedo.get_pixel(x, y)
			# Mip-safe compression: retain plate hierarchy without harsh black seams.
			var luminance: float = color.get_luminance()
			var compressed: float = 0.5 + (luminance - 0.5) * 0.78
			color *= compressed / maxf(luminance, 0.06)
			color.r = clampf(color.r, 0.09, 0.78)
			color.g = clampf(color.g, 0.09, 0.78)
			color.b = clampf(color.b, 0.10, 0.82)
			albedo.set_pixel(x, y, color)
			luminance = color.get_luminance()
			height.set_pixel(x, y, Color(luminance, luminance, luminance))
			var crevice: float = clampf((0.48 - luminance) * 2.1, 0.0, 1.0)
			var cyan: float = clampf((color.b + color.g) * 0.5 - color.r - 0.08, 0.0, 1.0)
			orm.set_pixel(x, y, Color(1.0 - crevice * 0.55,
				clampf(0.63 + crevice * 0.25 - cyan * 0.18, 0.38, 0.94), 0.0))
			emission.set_pixel(x, y, Color(cyan, cyan, cyan))
	_save(albedo, "enemy_skin_v2_albedo.png")
	_normal_from_height(height, size, 3.0, "enemy_skin_v2_normal.png")
	_save(orm, "enemy_skin_v2_orm.png")
	_save(emission, "enemy_skin_v2_emission.png")

# === Helpers ===

func _fbm(seed_v: int, freq: float, octaves: int = 4) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_gain = 0.5
	return n

func _ridged(seed_v: int, freq: float) -> FastNoiseLite:
	var n := _fbm(seed_v, freq)
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_DIV
	return n

func _new_img(size: int) -> Image:
	return Image.create(size, size, false, Image.FORMAT_RGB8)

func _save(img: Image, name: String) -> void:
	img.save_png(OUT + name)

## Central-difference tangent-space normal map from a grayscale height field.
func _normal_from_height(height: Image, size: int, strength: float,
		name_: String) -> void:
	var out := _new_img(size)
	for y in size:
		for x in size:
			var xl := height.get_pixel((x - 1 + size) % size, y).r
			var xr := height.get_pixel((x + 1) % size, y).r
			var yu := height.get_pixel(x, (y - 1 + size) % size).r
			var yd := height.get_pixel(x, (y + 1) % size).r
			var dx := (xl - xr) * strength
			var dy := (yu - yd) * strength
			var inv := 1.0 / sqrt(dx * dx + dy * dy + 1.0)
			out.set_pixel(x, y, Color(
				clampf(-dx * inv * 0.5 + 0.5, 0.0, 1.0),
				clampf(-dy * inv * 0.5 + 0.5, 0.0, 1.0),
				clampf(inv * 0.5 + 0.5, 0.0, 1.0)))
	_save(out, name_)

# === Sets ===

## Shared close-up albedo grain: woven leather/cloth value variation.
func _detail_grain() -> void:
	var size := 512
	var n := _fbm(11, 26.0, 5)
	var weave := _fbm(12, 90.0, 2)
	var img := _new_img(size)
	for y in size:
		for x in size:
			var g := clampf(n.get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0)
			var w := sin(float(x) * 3.14159 * 0.5) * sin(float(y) * 3.14159 * 0.5)
			g = clampf(g * 0.82 + (w * 0.5 + 0.5) * 0.18
				+ weave.get_noise_2d(x, y) * 0.06, 0.0, 1.0)
			img.set_pixel(x, y, Color(g, g, g))
	_save(img, "detail_grain.png")

## Shared 512 tiling micro-normal for close-up inspection.
func _detail_normal() -> void:
	var size := 512
	var n := _fbm(21, 34.0, 4)
	var h := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var v := clampf(n.get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0)
			h.set_pixel(x, y, Color(v, v, v))
	_normal_from_height(h, size, 2.2, "detail_normal.png")

func _hero_height(size: int) -> Image:
	# Hooded-cloth folds: stretched vertical drape noise + patch stitching
	var folds := _fbm(31, 9.0, 5)
	var drape := _fbm(32, 3.0, 3)
	var stitch := _fbm(33, 60.0, 2)
	var h := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var fy := float(y) / float(size)
			var v := folds.get_noise_2d(x, y * 0.45) * 0.55 \
				+ drape.get_noise_2d(x * 0.7, y) * 0.30 \
				+ stitch.get_noise_2d(x, y) * 0.08 \
				+ smoothstep(0.85, 1.0, fy) * 0.07
			v = clampf(v * 0.5 + 0.5, 0.0, 1.0)
			h.set_pixel(x, y, Color(v, v, v))
	return h

func _write_hero_set() -> void:
	var size := 1024
	var h := _hero_height(size)
	_normal_from_height(h, size, 3.4, "hero_normal.png")

	var crevice := _fbm(35, 14.0, 4)
	var speck := _fbm(36, 48.0, 3)
	var img := _new_img(size)   # ORM
	for y in size:
		for x in size:
			var cr := clampf(crevice.get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0)
			var ao := clampf(1.0 - pow(cr, 2.4) * 0.55, 0.25, 1.0)
			var rough := clampf(0.68 + cr * 0.22
				+ speck.get_noise_2d(x, y) * 0.10, 0.35, 1.0)
			var metal := (0.65 if speck.get_noise_2d(x + 91, y) > 0.86 else 0.0)
			img.set_pixel(x, y, Color(ao, rough, metal))
	_save(img, "hero_orm.png")
	_save(h, "hero_height_master.png")

	# Lantern-glow mask: mottled warm patches gate belt-lantern spill
	var veins := _ridged(37, 11.0)
	var mask := _new_img(size)
	for y in range(0, size, 2):
		for x in range(0, size, 2):
			var v := clampf(pow(absf(veins.get_noise_2d(x, y)), 1.6) * 1.8, 0.0, 1.0)
			var c := Color(v, v * 0.92, v * 0.8)
			mask.set_pixel(x, y, c)
			if x + 1 < size and y + 1 < size:
				mask.set_pixel(x + 1, y, c)
				mask.set_pixel(x, y + 1, c)
				mask.set_pixel(x + 1, y + 1, c)
	_save(mask, "hero_emission_mask.png")

func _hero_ember_variant() -> void:
	# Ember-forged tier: tighter grain, hotter vein density, lower roughness
	var size := 1024
	var h := _hero_height(size)
	_normal_from_height(h, size, 4.1, "hero_ember_normal.png")
	var crevice := _fbm(45, 16.0, 4)
	var speck := _fbm(46, 52.0, 3)
	var img := _new_img(size)
	for y in size:
		for x in size:
			var cr := clampf(crevice.get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0)
			var ao := clampf(1.0 - pow(cr, 2.0) * 0.5, 0.3, 1.0)
			var rough := clampf(0.52 + cr * 0.18, 0.28, 0.9)
			var metal := (0.8 if speck.get_noise_2d(x + 17, y) > 0.80 else 0.0)
			img.set_pixel(x, y, Color(ao, rough, metal))
	_save(img, "hero_ember_orm.png")
	var veins := _ridged(47, 14.0)
	var mask := _new_img(size)
	for y in range(0, size, 2):
		for x in range(0, size, 2):
			var v := clampf(pow(absf(veins.get_noise_2d(x, y)), 1.1) * 2.4, 0.0, 1.0)
			var c := Color(v, v * 0.55, v * 0.3)
			mask.set_pixel(x, y, c)
			if x + 1 < size and y + 1 < size:
				mask.set_pixel(x + 1, y, c)
				mask.set_pixel(x, y + 1, c)
				mask.set_pixel(x + 1, y + 1, c)
	_save(mask, "hero_ember_emission_mask.png")

func _hushling_set() -> void:
	# Hand-painted Bramble Sprite set. The body wears a violet-moss mottle
	# (grayscale ~0.5 so the albedo_texture multiply leaves the material's
	# base_color intact), and the SAME pod field drives albedo pods, the
	# normal height (raised mint knobs) and the emission mask — so glowing
	# pods sit exactly on painted pods, never floating.
	var size := 512
	var mottle := _fbm(51, 6.5, 4)
	var crevice := _fbm(53, 14.0, 3)
	var pod_warps := _fbm(52, 13.0, 2)
	var pod_val := _fbm(54, 6.5, 4)
	var img := _new_img(size)     # albedo (violet-moss, pods mint)
	var h := Image.create(size, size, false, Image.FORMAT_RGB8)
	var orm := _new_img(size)     # R=ao G=rough B=metal
	var mask := _new_img(size)
	for y in size:
		for x in size:
			var warp := pod_warps.get_noise_2d(x, y) * 40.0
			var pod := clampf(smoothstep(0.18, 0.52,
				pod_val.get_noise_2d(x + warp, y)), 0.0, 1.0)
			var m := clampf(mottle.get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0)
			var cr := clampf(crevice.get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0)
			# Violet-moss body, brighter in the crevices, mint pods on top
			var alb := Color(0.46 + cr * 0.12, 0.42 + cr * 0.10, 0.55 + m * 0.06)
			var pod_c := Color(0.44, 0.78, 0.62)
			alb = alb.lerp(pod_c, pod * 0.85)
			img.set_pixel(x, y, alb)
			# Height: pod knobs rising out of a wrinkled skin
			var val := pod * 0.55 + m * 0.25 + cr * 0.2
			h.set_pixel(x, y, Color(val, val, val))
			# ORM: AO deep in the wrinkles, rough bark skin, no metal
			var ao := clampf(1.0 - cr * 0.5, 0.25, 1.0)
			var rough := clampf(0.55 + m * 0.3 + pod * 0.1, 0.4, 1.0)
			orm.set_pixel(x, y, Color(ao, rough, 0.0))
			mask.set_pixel(x, y, Color(pod, pod, pod))
	_normal_from_height(h, size, 3.2, "hushling_normal.png")
	_save(img, "hushling_albedo.png")
	_save(orm, "hushling_orm.png")
	_save(mask, "hushling_emission_mask.png")

func _boss_set() -> void:
	var size := 1024
	# Bark: deep vertical striations + gnarl knots
	var striate := _fbm(61, 42.0, 4)
	var gnarl := _fbm(62, 5.0, 4)
	var moss := _fbm(63, 8.0, 3)
	var h := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var v := striate.get_noise_2d(x * 2.6, y * 0.55) * 0.62 \
				+ gnarl.get_noise_2d(x, y) * 0.38
			h.set_pixel(x, y, Color(clampf(v * 0.5 + 0.5, 0.0, 1.0),
				clampf(moss.get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0), 0.5))
	_normal_from_height(h, size, 4.6, "boss_bark_normal.png")

	var img := _new_img(size)   # ORM: moss creeps AO + roughness
	for y in size:
		for x in size:
			var m := clampf(moss.get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0)
			var ao := clampf(0.45 + (1.0 - m) * 0.55, 0.3, 1.0)
			var rough := clampf(0.78 + m * 0.18, 0.4, 1.0)
			var metal := (0.3 if moss.get_noise_2d(x + 55, y) > 0.93 else 0.0)
			img.set_pixel(x, y, Color(ao, rough, metal))
	_save(img, "boss_orm.png")

	# Hollow heart glow mask: a hot core bleeding outward
	var heart := _fbm(64, 4.0, 3)
	var mask := _new_img(size)
	for y in size:
		for x in size:
			var dx := (float(x) / float(size)) - 0.5
			var dy := (float(y) / float(size)) - 0.5
			var r := sqrt(dx * dx + dy * dy) * 2.0
			var v := clampf((heart.get_noise_2d(x, y) * 0.4 + 0.6)
				* smoothstep(0.75, 0.1, r), 0.0, 1.0)
			mask.set_pixel(x, y, Color(v, v, v))
	_save(mask, "boss_heart_mask.png")
