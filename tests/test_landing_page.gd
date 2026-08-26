extends SceneTree

## Headless smoke: the landing page wears its Ember Glass polish — parchment
## hero surfaces, role-styled buttons (primary / secondary / danger), theme-
## routed typography, firefly ambience, and the generated UI textures load
## without an import cache.

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func():
		print("WATCHDOG TIMEOUT")
		quit(3))
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _check(failures: int, cond: bool, msg: String) -> int:
	if not cond:
		print("FAIL: ", msg)
		return failures + 1
	return failures

func _run() -> void:
	var failures := 0
	var gs = root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()

	# --- Design-system primitives ---
	var tex = UiKit._ui_tex("ui_parchment_paper")
	failures = _check(failures, tex != null and tex is Texture2D,
		"generated parchment texture did not load headless")
	if tex != null:
		failures = _check(failures, tex.get_size() == Vector2(512, 512),
			"parchment texture wrong size: " + str(tex.get_size()))
	var sb := UiKit.parchment_stylebox()
	failures = _check(failures,
		sb is StyleBoxFlat and sb.bg_color == UiKit.PARCHMENT_BG,
		"parchment stylebox missing its warm stock color")
	var probe := Button.new()
	UiKit.style_secondary_button(probe)
	failures = _check(failures,
		probe.get_theme_color("font_hover_color") == UiKit.SAGE_BRIGHT,
		"secondary button role not applied")
	UiKit.style_danger_button(probe)
	failures = _check(failures,
		probe.get_theme_color("font_hover_color") == UiKit.DANGER_BRIGHT,
		"danger button role not applied")
	probe.queue_free()

	# --- Landing page boot ---
	var main_scene: Node = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	current_scene = main_scene
	await _frames(12)
	var menu := main_scene.get_node_or_null("MainMenu")
	if menu == null:
		print("FAIL: MainMenu missing from shell")
		print("LANDING PAGE TESTS FAILED: ", failures + 1)
		quit(1)
		return

	# --- Parchment surfaces ---
	var hero: PanelContainer = menu.get_node("Root/HeroCard")
	failures = _check(failures, hero.get_node_or_null("ParchmentVeil") != null,
		"hero card missing its parchment fiber veil")
	var hero_sb := hero.get_theme_stylebox("panel") as StyleBoxFlat
	failures = _check(failures,
		hero_sb != null and hero_sb.bg_color == UiKit.PARCHMENT_BG,
		"hero card panel not parchment styled")
	var confirm: PanelContainer = menu.get_node("Root/HeroCard/HeroVBox/ConfirmCard")
	failures = _check(failures, confirm.get_node_or_null("ParchmentVeil") != null,
		"confirm card missing its parchment veil")

	# --- Button roles on the landing page ---
	var cta: Button = menu.get_node("Root/HeroCard/HeroVBox/CTAButton")
	failures = _check(failures,
		cta.get_theme_color("font_hover_color") == Color(1, 1, 0.94),
		"CTA not styled ember-lit primary")
	var cont: Button = menu.get_node("Root/HeroCard/HeroVBox/SecondaryRow/ContinueButton")
	failures = _check(failures,
		cont.get_theme_color("font_hover_color") == UiKit.SAGE_BRIGHT,
		"CONTINUE not styled secondary")
	var quit_b: Button = menu.get_node("Root/HeroCard/HeroVBox/SecondaryRow/QuitButton")
	failures = _check(failures,
		quit_b.get_theme_color("font_hover_color") == UiKit.DANGER_BRIGHT,
		"QUIT not styled danger")
	var yes: Button = menu.get_node(
		"Root/HeroCard/HeroVBox/ConfirmCard/ConfirmVBox/ConfirmRow/ConfirmYes")
	failures = _check(failures,
		yes.get_theme_color("font_hover_color") == Color(1, 1, 0.94),
		"confirm-yes not styled primary")

	# --- Typography routed through the shared theme ---
	var title: Label = menu.get_node("Root/HeroCard/HeroVBox/TitleLabel")
	failures = _check(failures, title.theme_type_variation == &"Title",
		"title not routed through the Title variation")
	var hint: Label = menu.get_node("Root/FooterHint")
	failures = _check(failures, hint.text.contains("\n"),
		"footer hint should carry its controls onto a second line")
	var chip: Label = menu.get_node("Root/VersionChip")
	failures = _check(failures, chip.has_theme_color_override("font_color"),
		"version chip missing its tint override")

	# --- Atmosphere ---
	var flies := menu.get_node_or_null("Root/Fireflies") as CPUParticles2D
	failures = _check(failures, flies != null and flies.visible,
		"firefly ambience missing or hidden")

	# --- Entrance completes ---
	await create_timer(1.0).timeout
	await _frames(3)
	var wordmark: Label = menu.get_node("Root/Wordmark")
	failures = _check(failures, wordmark.modulate.a > 0.95,
		"wordmark entrance never faded in")

	gs.delete_save()
	if failures == 0:
		print("ALL LANDING PAGE TESTS PASSED")
	else:
		print("LANDING PAGE TESTS FAILED: ", failures)
	quit(1 if failures > 0 else 0)
