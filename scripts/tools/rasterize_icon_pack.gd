extends SceneTree

## One-shot build tool for the Android UI icon runtime pack.
## SVG remains the editable source; PNG is the bounded runtime representation.
const SOURCE_DIR := "res://assets/ui/icons"
const OUTPUT_DIR := "res://assets/ui/icons/raster"
const OUTPUT_SIZE := 128

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var files := DirAccess.get_files_at(SOURCE_DIR)
	var written := 0
	for file_name in files:
		if not file_name.ends_with(".svg"):
			continue
		var texture := load(SOURCE_DIR + "/" + file_name) as Texture2D
		if texture == null:
			push_error("Could not load icon source: %s" % file_name)
			continue
		var image := texture.get_image()
		if image == null or image.is_empty():
			push_error("Icon source produced an empty image: %s" % file_name)
			continue
		image.convert(Image.FORMAT_RGBA8)
		image.resize(OUTPUT_SIZE, OUTPUT_SIZE, Image.INTERPOLATE_LANCZOS)
		var output := OUTPUT_DIR + "/" + file_name.get_basename() + ".png"
		var error := image.save_png(output)
		if error != OK:
			push_error("Could not write icon: %s" % output)
			continue
		written += 1
	print("RASTER ICON PACK WRITTEN: %d icons at %dx%d" % [written, OUTPUT_SIZE, OUTPUT_SIZE])
	quit(0 if written > 0 else 1)
