extends SceneTree

## Deterministic, renderer-neutral alpha sprites for cinematic combat FX.
## These stay tiny and monochrome so Godot can tint and mip them cheaply.

const OUT := "res://assets/textures/generated/vfx"
const SIZE := 128


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_write("spark.png", _spark)
	_write("smoke.png", _smoke)
	_write("crescent.png", _crescent)
	_write("impact_star.png", _impact_star)
	_write("distortion.png", _distortion)
	_write("ring.png", _ring)
	print("VFX SPRITE FOUNDRY: PASS")
	quit(0)


func _write(file_name: String, sampler: Callable) -> void:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var uv: Vector2 = (Vector2(x, y) + Vector2(0.5, 0.5)) / float(SIZE)
			var alpha: float = clampf(float(sampler.call(uv)), 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	image.save_png("%s/%s" % [OUT, file_name])


func _spark(uv: Vector2) -> float:
	var raw: Vector2 = (uv - Vector2(0.5, 0.5)) * 2.0
	var p := Vector2(absf(raw.x), absf(raw.y))
	var blade: float = exp(-p.x * 18.0) * exp(-p.y * 3.2)
	var core: float = exp(-(p.x * p.x + p.y * p.y) * 22.0)
	return maxf(blade, core)


func _smoke(uv: Vector2) -> float:
	var p: Vector2 = (uv - Vector2(0.5, 0.5)) * 2.0
	var r: float = p.length()
	var wobble: float = sin(uv.x * 31.0 + uv.y * 17.0) * 0.035 \
		+ sin(uv.x * 13.0 - uv.y * 29.0) * 0.025
	return 1.0 - smoothstep(0.32 + wobble, 0.94 + wobble, r)


func _crescent(uv: Vector2) -> float:
	var p: Vector2 = (uv - Vector2(0.48, 0.52)) * 2.0
	var outer: float = 1.0 - smoothstep(0.72, 0.82, p.length())
	var cut: float = 1.0 - smoothstep(0.54, 0.64,
		(p - Vector2(0.28, -0.06)).length())
	return clampf(outer - cut, 0.0, 1.0)


func _impact_star(uv: Vector2) -> float:
	var raw: Vector2 = (uv - Vector2(0.5, 0.5)) * 2.0
	var p := Vector2(absf(raw.x), absf(raw.y))
	var radial: float = exp(-(p.x * p.x + p.y * p.y) * 9.0)
	var cross: float = maxf(exp(-p.x * 22.0) * exp(-p.y * 2.8),
		exp(-p.y * 22.0) * exp(-p.x * 2.8))
	var diag: float = exp(-absf(p.x - p.y) * 18.0) * exp(-(p.x + p.y) * 3.0)
	return maxf(radial, maxf(cross, diag * 0.7))


func _distortion(uv: Vector2) -> float:
	var r: float = (uv - Vector2(0.5, 0.5)).length() * 2.0
	return exp(-pow((r - 0.55) * 8.0, 2.0)) * (1.0 - smoothstep(0.75, 1.0, r))


## Crisp hollow ring for high-contrast, non-blooming telegraphs. The band is
## kept thin and hard-edged so it reads through additive FX and fog; the soft
## inner wash stops it disappearing when seen edge-on.
func _ring(uv: Vector2) -> float:
	var r: float = (uv - Vector2(0.5, 0.5)).length() * 2.0
	var band: float = 1.0 - smoothstep(0.58, 0.80, r)
	var hollow: float = smoothstep(0.16, 0.30, r)
	return clampf(band * hollow + (1.0 - smoothstep(0.05, 0.18, r)) * 0.08, 0.0, 1.0)
