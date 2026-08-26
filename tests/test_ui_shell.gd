extends SceneTree

## Headless smoke: Ember Glass UI shell boots, theme + fonts apply, the
## live backdrop contains the world, and the save-guarded CTA flow lands
## in the grove with a visible HUD.

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func():
		print("WATCHDOG TIMEOUT")
		quit(3))
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var failures := 0
	var gs = root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()

	var main_scene: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	current_scene = main_scene
	await _frames(12)

	# --- Shell structure ---
	var menu := main_scene.get_node_or_null("MainMenu")
	var backdrop := main_scene.get_node_or_null("MenuBackdrop")
	if menu == null or backdrop == null:
		failures += 1
		print("FAIL: MainMenu/MenuBackdrop missing from shell")
	if not backdrop.is_live():
		failures += 1
		print("FAIL: 3D backdrop reports not live (fallback engaged)")
	if not menu.get_node("Root/HeroCard/HeroVBox/CTAButton") is Button:
		failures += 1
		print("FAIL: CTA missing")
	if not menu.get_node("Root/HeroCard/HeroVBox/SecondaryRow/QuitButton") is Button:
		failures += 1
		print("FAIL: QUIT button missing from landing page")

	# --- Project theme is wired and styled ---
	if ThemeDB.get_project_theme() == null:
		failures += 1
		print("FAIL: gui/theme/custom not applied")
	var title: Label = menu.get_node("Root/HeroCard/HeroVBox/TitleLabel")
	var f := title.get_theme_font(&"font", &"Title")
	var f_path := f.resource_path if f != null else ""
	if f is FontVariation and f.base_font != null:
		f_path = f.base_font.resource_path
	if not f_path.contains("Cinzel"):
		failures += 1
		print("FAIL: Title variation not resolving to Cinzel, got ", f)

	# --- Backdrop containment: hostiles parked, not roaming ---
	await _frames(3)
	for e in get_nodes_in_group("enemy"):
		if e.visible or e.is_physics_processing():
			failures += 1
			print("FAIL: hostile not contained behind menu: ", e.name)

	# --- Save-guarded confirm flow ---
	gs.save_game()
	menu._check_continue_availability()
	if menu.get_node("Root/HeroCard/HeroVBox/SecondaryRow/ContinueButton").disabled:
		failures += 1
		print("FAIL: continue still disabled with a save present")
	menu._on_new_tale_pressed()
	if not menu.get_node("Root/HeroCard/HeroVBox/ConfirmCard").visible:
		failures += 1
		print("FAIL: confirm card not shown despite existing save")
	menu._on_cancel_new_tale()
	menu._begin_tale(true)
	await create_timer(1.0).timeout
	await _frames(5)
	if current_scene == null or current_scene.name != "Grove":
		failures += 1
		print("FAIL: expected Grove scene after Begin, got ",
			current_scene.name if current_scene else "<null>")
	else:
		var hud := current_scene.get_node_or_null("HUD")
		if hud == null or not hud.visible:
			failures += 1
			print("FAIL: HUD not visible after entering the tale")

	gs.delete_save()
	if failures == 0:
		print("ALL UI SHELL TESTS PASSED")
	else:
		print("UI SHELL TESTS FAILED: ", failures)
	quit(1 if failures > 0 else 0)
