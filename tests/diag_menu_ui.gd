extends SceneTree

## Interaction probe: landing-page confirm swap + settings open/close.
## Simulates real presses and measures the hero card against its content.

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func():
		print("WATCHDOG TIMEOUT")
		quit(3))
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
	await _frames(12)

	var menu := main.get_node_or_null("MainMenu")
	if menu == null:
		print("FAIL: no MainMenu")
		quit(1)
		return

	var card: PanelContainer = menu.get_node("Root/HeroCard")
	var vbox: VBoxContainer = card.get_node("HeroVBox")
	var cta: Button = vbox.get_node("CTAButton")
	var confirm: PanelContainer = vbox.get_node("ConfirmCard")
	print("idle: card=%s content_min=%s" % [card.size, vbox.get_combined_minimum_size()])

	# --- Confirm flow (no save): should start the tale, not show confirm.
	# With a save: confirm must REPLACE the CTA, never stack below it.
	gs.save_game()
	menu._on_new_tale_pressed()
	await _frames(4)
	print("confirm shown=%s cta_hidden=%s" % [confirm.visible, not cta.visible])
	if confirm.visible and cta.visible:
		print("FAIL: confirm stacked below CTA (overlap)")

	# Cancel restores
	var no_btn: Button = confirm.get_node("ConfirmVBox/ConfirmRow/ConfirmNo")
	no_btn.pressed.emit()
	await _frames(2)
	print("after_cancel: confirm_visible=%s cta_visible=%s" % [
		confirm.visible, cta.visible])

	# --- Settings open/close from the landing page
	menu._on_settings()
	await _frames(6)
	var settings := root.find_child("SettingsMenu", true, false)
	if settings == null:
		print("FAIL: SettingsMenu missing after open")
		gs.delete_save()
		quit(1)
		return
	print("settings visible=%s layer=%s" % [settings.visible, settings.layer])
	var back: Button = settings.get_node("Root/Panel/VBox/BackButton")
	back.pressed.emit()
	await _frames(3)
	print("settings_after_back visible=%s" % settings.visible)
	if settings.visible:
		print("FAIL: BACK did not close settings")

	print("PROBE DONE")
	gs.delete_save()
	quit(0)
