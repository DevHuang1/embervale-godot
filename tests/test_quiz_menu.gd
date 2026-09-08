extends SceneTree

func _initialize() -> void:
	var scene := load("res://scenes/ui/quiz_menu.tscn") as PackedScene
	if scene == null:
		print("FAIL: quiz menu scene missing")
		quit(1)
		return
	var menu := scene.instantiate()
	root.add_child(menu)
	await process_frame
	if menu.get_node_or_null("Root/VBox/Question") == null \
		or menu.get_node_or_null("Root/VBox/Answers") == null:
		print("FAIL: quiz menu answer surface missing")
		quit(1)
		return
	print("ALL QUIZ MENU TESTS PASSED")
	quit(0)
