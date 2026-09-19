extends SceneTree

## Headless test: the Embervale app-icon contract.
##
## Every shipped icon layer exists at its exact size, the adaptive layers stay
## inside the 66dp safe circle (the part a launcher mask can never crop), the
## themed layer is a pure white silhouette, and the project/Android export
## settings actually point at them — so a rebuild cannot quietly ship the Godot
## logo again.

const ICON_DIR := "res://assets/branding/app_icon"

const LAYERS := {
	"app_icon_1024.png": Vector2i(1024, 1024),
	"app_icon_512.png": Vector2i(512, 512),
	"app_icon_launcher_192.png": Vector2i(192, 192),
	"app_icon_foreground_432.png": Vector2i(432, 432),
	"app_icon_background_432.png": Vector2i(432, 432),
	"app_icon_monochrome_432.png": Vector2i(432, 432),
	"app_icon_mark_512.png": Vector2i(512, 512),
}

# The adaptive safe zone is a 66dp circle on the 108dp canvas: 66/108.
const SAFE_RADIUS := 0.611
const SAFE_ALPHA := 0.2

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(25.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — test hung")
		quit(2))

func _run() -> void:
	for file_name in LAYERS:
		_check_layer(file_name, LAYERS[file_name])
	for file_name in ["app_icon_foreground_432.png", "app_icon_monochrome_432.png",
			"app_icon_mark_512.png"]:
		_check_transparent_corners(file_name)
	_check_safe_zone("app_icon_foreground_432.png")
	_check_safe_zone("app_icon_monochrome_432.png")
	_check_safe_zone("app_icon_mark_512.png")
	_check_opaque("app_icon_1024.png")
	_check_opaque("app_icon_512.png")
	_check_opaque("app_icon_launcher_192.png")
	_check_opaque("app_icon_background_432.png")
	_check_themed_tint()
	_check_icon_presence()
	_check_settings()
	_check_android_preset()

	if _failures == 0:
		print("ALL APP ICON TESTS PASSED")
	else:
		print("%d FAILURES" % _failures)
	quit(1 if _failures > 0 else 0)

func _check_layer(file_name: String, expected: Vector2i) -> void:
	var image := _load_image(file_name)
	if image == null:
		return
	if image.get_size() != expected:
		_fail("%s is %s, expected %s" % [file_name, image.get_size(), expected])

## The masked layers must be honest alpha, not a dark plate the mask would crop.
func _check_transparent_corners(file_name: String) -> void:
	var image := _load_image(file_name)
	if image == null:
		return
	var last := image.get_width() - 1
	for corner in [Vector2i(0, 0), Vector2i(last, 0), Vector2i(0, last),
			Vector2i(last, last)]:
		if image.get_pixel(corner.x, corner.y).a > 0.02:
			_fail("%s is not transparent at its corners" % file_name)
			return

func _check_safe_zone(file_name: String) -> void:
	var image := _load_image(file_name)
	if image == null:
		return
	var half := float(image.get_width()) * 0.5
	var worst := 0.0
	var visible := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a <= SAFE_ALPHA:
				continue
			visible += 1
			var radius := Vector2(float(x) + 0.5 - half, float(y) + 0.5 - half).length() / half
			worst = maxf(worst, radius)
	if visible == 0:
		_fail("%s is empty" % file_name)
		return
	if worst > SAFE_RADIUS:
		_fail("%s bleeds past the adaptive safe zone (%.3f > %.3f)" % [
			file_name, worst, SAFE_RADIUS])

func _check_opaque(file_name: String) -> void:
	var image := _load_image(file_name)
	if image == null:
		return
	var minimum := 255
	for y in image.get_height():
		for x in image.get_width():
			minimum = mini(minimum, int(round(image.get_pixel(x, y).a * 255.0)))
	if minimum < 255:
		_fail("%s is not fully opaque (min alpha %d)" % [file_name, minimum])

## Android tints the themed layer, so its colour must carry no hue of its own.
func _check_themed_tint() -> void:
	var image := _load_image("app_icon_monochrome_432.png")
	if image == null:
		return
	var opaque := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a <= SAFE_ALPHA:
				continue
			opaque += 1
			if not is_equal_approx(pixel.r, 1.0) or not is_equal_approx(pixel.g, 1.0) \
					or not is_equal_approx(pixel.b, 1.0):
				_fail("monochrome layer carries colour at (%d, %d)" % [x, y])
				return
	if opaque == 0:
		_fail("monochrome layer has no visible pixels")

## The lockup has to actually read as an icon: a warm mark on a dark plate.
func _check_icon_presence() -> void:
	for file_name in ["app_icon_1024.png", "app_icon_512.png"]:
		var image := _load_image(file_name)
		if image == null:
			continue
		var size := image.get_width()
		var center := image.get_pixel(size / 2, int(size * 0.42))
		var corner := image.get_pixel(size / 32, size / 32)
		if center.r + center.g + center.b < 1.2:
			_fail("%s has no lit center" % file_name)
		if corner.r + corner.g + corner.b > 0.6:
			_fail("%s has no dark field" % file_name)

func _check_settings() -> void:
	for setting in ["application/config/icon", "application/boot_splash/image"]:
		var path := str(ProjectSettings.get_setting(setting, ""))
		if path.is_empty():
			_fail("%s is unset — the export would fall back to the engine icon" % setting)
		elif not ResourceLoader.exists(path):
			_fail("%s points at a missing file: %s" % [setting, path])

## The preset is not tracked in git, so a fresh checkout legitimately has none:
## the settings above still apply. When it is present, its icon slots must be
## wired or Android ships the template's Godot drawables.
func _check_android_preset() -> void:
	if not FileAccess.file_exists("res://export_presets.cfg"):
		print("NOTE: export_presets.cfg absent — skipping Android icon slot check")
		return
	var config := ConfigFile.new()
	if config.load("res://export_presets.cfg") != OK:
		_fail("export_presets.cfg could not be parsed")
		return
	var section := ""
	for index in 64:
		var candidate := "preset.%d" % index
		if not config.has_section(candidate):
			continue
		if str(config.get_value(candidate, "platform", "")) == "Android":
			section = candidate
			break
	if section.is_empty():
		_fail("no Android export preset found")
		return
	var options := section + ".options"
	for option in ["launcher_icons/main_192x192",
			"launcher_icons/adaptive_foreground_432x432",
			"launcher_icons/adaptive_background_432x432",
			"launcher_icons/adaptive_monochrome_432x432",
			"splash_screen/icon"]:
		var path := str(config.get_value(options, option, ""))
		if path.is_empty():
			_fail("Android preset %s is unset" % option)
		elif not ResourceLoader.exists(path):
			_fail("Android preset %s points at a missing file: %s" % [option, path])

func _load_image(file_name: String) -> Image:
	var path := "%s/%s" % [ICON_DIR, file_name]
	if not ResourceLoader.exists(path):
		_fail("missing icon layer: %s" % path)
		return null
	var texture := load(path) as Texture2D
	if texture == null:
		_fail("icon layer is not a texture: %s" % path)
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		_fail("icon layer produced no pixels: %s" % path)
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
