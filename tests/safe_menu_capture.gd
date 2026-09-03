extends SceneTree

## Real-render landing-page capture that redirects saves to /private/tmp.
## It never reads, deletes, or overwrites the player's normal save file.

var output_path := "/private/tmp/embervale_menu_layout.png"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--out":
			output_path = args[i + 1]
	_run.call_deferred()

func _run() -> void:
	var game_state := root.get_node("/root/GameState")
	game_state.save_path = "/private/tmp/embervale_menu_capture_save.cfg"
	game_state.reset()
	var main := (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 90:
		await process_frame
	var menu := main.get_node("MainMenu")
	var card := menu.get_node("Root/HeroCard") as Control
	for path in ["HeroVBox/CTAButton", "HeroVBox/SecondaryRow/ContinueButton",
			"HeroVBox/SecondaryRow/SettingsButton", "HeroVBox/SecondaryRow/QuitButton"]:
		var action := card.get_node(path) as Control
		print("MENU RECT %s=%s inside=%s" % [path, action.get_global_rect(),
			card.get_global_rect().encloses(action.get_global_rect())])
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(output_path)
	print("SAFE MENU CAPTURE %s size=%s error=%d" % [output_path, image.get_size(), error])
	DirAccess.remove_absolute(game_state.save_path)
	quit(0 if error == OK else 1)
