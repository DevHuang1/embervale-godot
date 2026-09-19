extends SceneTree

## One sheet at a time: a menu opened while another is up must retire the other,
## and closing the top sheet must never leave one behind. The HUD sits below the
## menu layers, but a sheet whose dimmer ignores input still leaves the HUD
## reachable — which is how two overlays used to stack and one never closed.

const SATELLITE_MENUS := ["SatchelUI", "DiamondShop", "SettingsMenu", "ShopMenu"]

var _failures := 0

func _initialize() -> void:
	call_deferred("_run")
	var watchdog := create_timer(60.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — test hung")
		quit(2))

func _run() -> void:
	var scene := (load("res://scenes/world/grove.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	# The HUD resolves its overlays through get_tree().current_scene, so the
	# harness must install the scene the way a realm load does.
	current_scene = scene
	for i in 12:
		await process_frame
	root.size = Vector2i(1080, 1920)
	await process_frame

	var hud := scene.get_node_or_null("HUD")
	if hud == null:
		print("FAIL: HUD missing")
		quit(1)
		return
	# Exactly one instance of each overlay: a duplicate would make every close
	# path ambiguous, which is the state the player reported.
	for menu_name in SATELLITE_MENUS:
		var found := scene.find_children(menu_name, "", true, false)
		if found.size() != 1:
			print("FAIL: %s appears %d times" % [menu_name, found.size()])
			_failures += 1

	var satchel := scene.get_node_or_null("SatchelUI") as CanvasLayer
	var glint := scene.get_node_or_null("DiamondShop") as CanvasLayer
	var settings := scene.get_node_or_null("SettingsMenu") as CanvasLayer
	var buttons := {
		"satchel": hud.get_node_or_null("Root/MetaRow/ActionRow/SatchelButton") as Button,
		"glint": hud.get_node_or_null("Root/MetaRow/ActionRow/GlintButton") as Button,
		"settings": hud.get_node_or_null("Root/MetaRow/TopRow/SettingsButton") as Button,
	}
	for key in buttons:
		if buttons[key] == null:
			print("FAIL: %s HUD button missing" % key)
			_failures += 1
	if _failures > 0:
		quit(1)
		return

	(buttons["satchel"] as Button).pressed.emit()
	await process_frame
	_check(satchel.visible and not glint.visible,
		"the satchel must open alone")

	(buttons["glint"] as Button).pressed.emit()
	await process_frame
	_check(glint.visible, "the Glint shop must open")
	_check(not satchel.visible,
		"opening the Glint shop over the satchel must retire the satchel")

	(buttons["settings"] as Button).pressed.emit()
	await process_frame
	_check(settings.visible, "settings must open")
	_check(not glint.visible,
		"opening settings over the Glint shop must retire the Glint shop")

	var close_button := settings.get_node_or_null("Root/Panel/Header/CloseButton") as Button
	if close_button == null:
		print("FAIL: settings close control missing")
		_failures += 1
	else:
		close_button.pressed.emit()
		await process_frame
		_check(not settings.visible and not satchel.visible and not glint.visible,
			"closing the last sheet must leave no menu behind")

	# The satchel toggles: a second press closes it rather than stacking one.
	(buttons["satchel"] as Button).pressed.emit()
	await process_frame
	(buttons["satchel"] as Button).pressed.emit()
	await process_frame
	_check(not satchel.visible, "the satchel toggle must close what it opened")

	if _failures == 0:
		print("MENU OVERLAY EXCLUSION TESTS PASSED")
	else:
		print("%d FAILURES" % _failures)
	quit(1 if _failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	print("FAIL: %s" % message)
