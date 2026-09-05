extends Node

var hide_hero := true

func _ready() -> void:
	var scene: Node = load("res://scenes/world/grove.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var heroes := get_tree().get_nodes_in_group("player")
	var hero := heroes[0] as Node3D
	print("DIAG hero=", hero)
	var cam: Camera3D = null
	for n in get_tree().root.get_children():
		cam = _find_cam(n)
		if cam: break
	print("DIAG cam=", cam)
	if cam and hero:
		cam.global_position = hero.global_position + Vector3(0, 1.8, -3.0)
		cam.look_at(hero.global_position + Vector3(0, 1.1, 0), Vector3.UP)
		cam.current = true
		if hide_hero:
			hero.visible = false
		print("DIAG aimed=", cam.current, " hide=", hide_hero)

func _find_cam(n: Node) -> Camera3D:
	if n is Camera3D: return n
	for c in n.get_children():
		var r := _find_cam(c)
		if r: return r
	return null
