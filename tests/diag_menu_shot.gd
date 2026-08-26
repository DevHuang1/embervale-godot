extends SceneTree

## Visual probe: boots the real menu WITH rendering, waits for the entrance
## animation, saves a screenshot, and dumps pairwise overlaps between
## visible landing-page controls.

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var gs = root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()

	var main: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(45)   # entrance animations settle

	var vp := root.get_viewport()
	var tex := vp.get_texture()
	var img := tex.get_image()
	img.save_png("/var/folders/t5/3pcs06_d6tnd5psczflhtgkh0000gp/T/opencode/menu_shot.png")
	print("viewport size=", Vector2i(vp.get_visible_rect().size))
	print("screenshot saved")

	var menu := main.get_node_or_null("MainMenu")
	if menu == null:
		print("no menu"); quit(0); return
	var controls: Array[Control] = []
	_collect(menu.get_node("Root"), controls)
	print("--- control rects ---")
	for c in controls:
		if not c.visible:
			continue
		print("%-28s %s" % [c.name, Rect2(c.global_position, c.size)])
	# Pairwise intersection among siblings-level controls
	for i in controls.size():
		for j in range(i + 1, controls.size()):
			var a := controls[i]
			var b := controls[j]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a):
				continue
			var ra := Rect2(a.global_position, a.size)
			var rb := Rect2(b.global_position, b.size)
			if ra.intersects(rb) and a.visible and b.visible:
				print("OVERLAP: %s <-> %s" % [a.name, b.name])
	print("SHOT DONE")
	gs.delete_save()
	quit(0)

func _collect(n: Node, out: Array[Control]) -> void:
	for c in n.get_children():
		if c is Control:
			out.append(c)
		_collect(c, out)
