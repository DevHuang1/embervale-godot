extends Node

func _ready() -> void:
	var files: Array[String] = []
	_collect("res://scripts", files)
	files.sort()
	var fails: Array[String] = []
	for path in files:
		var res = load(path)
		if res == null:
			fails.append("LOAD NULL: " + path)
			continue
		if res is GDScript and not res.can_instantiate():
			fails.append("CANNOT INSTANTIATE: " + path)
	print("checked scripts: ", files.size())
	if fails.is_empty():
		print("ALL SCRIPTS PARSE OK")
	else:
		for f in fails:
			printerr(f)
	get_tree().quit(0 if fails.is_empty() else 1)

func _collect(full_dir: String, out: Array[String]) -> void:
	var dir := DirAccess.open(full_dir)
	if dir == null:
		printerr("CANNOT OPEN DIR: ", full_dir)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		var child := full_dir + "/" + name
		if dir.current_is_dir():
			_collect(child, out)
		elif name.ends_with(".gd"):
			out.append(child)
		name = dir.get_next()