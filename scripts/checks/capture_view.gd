extends SceneTree

## Headless capture: load the grove, advance frames, save the root viewport
## to a PNG so the terrain/view can be inspected for the "hill texture"
## covering-the-view bug.

var _frames := 0
var _hero: Node3D = null

func _init() -> void:
	var path := "res://scenes/world/grove.tscn"
	var scene := load(path) as PackedScene
	if scene == null:
		print("FAIL load:", path)
		quit(1)
		return
	var inst := scene.instantiate() as Node3D
	root.add_child(inst)
	_hero = inst.get_node_or_null("Hero")
	print("LOADED grove, hero=", _hero != null)

func _process(_delta: float) -> bool:
	_frames += 1
	# Let the world settle, camera snap to hero, a few physics frames.
	if _frames == 80:
		_capture("/tmp/grove_static.png")
		# Simulate "moving": shove the hero forward a bit so the camera
		# swings and we can catch any motion-dependent overlay.
		if _hero != null and _hero.has_method("global_translate"):
			_hero.global_translate(Vector3(0, 0, -6.0))
	elif _frames == 130:
		_capture("/tmp/grove_moving.png")
		print("CAPTURED both")
		quit(0)
	return false

func _capture(p: String) -> void:
	var vp := get_root()
	var tex := vp.get_texture()
	if tex == null:
		print("FAIL no viewport texture")
		return
	var img := tex.get_image()
	if img == null:
		print("FAIL no image")
		return
	var err := img.save_png(p)
	print("SAVED", p, "err=", err, "size=", img.get_size())
