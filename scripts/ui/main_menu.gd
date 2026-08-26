extends CanvasLayer
class_name MainMenu

## === Main Menu — Ember Glass landing page ===
## Live 3D backdrop behind a frosted hero card: wordmark, eyebrow, Cinzel
## title, primary CTA with save-guard confirm, continue + settings.

@onready var game_state: GameState = GameState
@onready var audio: AudioManager = AudioManager
@onready var root: Control = $Root
@onready var fallback_bg: ColorRect = $Root/FallbackBG
@onready var hero_card: PanelContainer = $Root/HeroCard
@onready var hero_vbox: VBoxContainer = $Root/HeroCard/HeroVBox
@onready var cta_button: Button = $Root/HeroCard/HeroVBox/CTAButton
@onready var confirm_card: PanelContainer = $Root/HeroCard/HeroVBox/ConfirmCard
@onready var confirm_yes: Button = $Root/HeroCard/HeroVBox/ConfirmCard/ConfirmVBox/ConfirmRow/ConfirmYes
@onready var confirm_no: Button = $Root/HeroCard/HeroVBox/ConfirmCard/ConfirmVBox/ConfirmRow/ConfirmNo
@onready var continue_button: Button = $Root/HeroCard/HeroVBox/SecondaryRow/ContinueButton
@onready var settings_button: Button = $Root/HeroCard/HeroVBox/SecondaryRow/SettingsButton
@onready var quit_button: Button = $Root/HeroCard/HeroVBox/SecondaryRow/QuitButton
@onready var eyebrow: Label = $Root/HeroCard/HeroVBox/Eyebrow
@onready var title_label: Label = $Root/HeroCard/HeroVBox/TitleLabel
@onready var subtitle: Label = $Root/HeroCard/HeroVBox/SubtitleLabel
@onready var wordmark: Label = $Root/Wordmark
@onready var footer_hint: Label = $Root/FooterHint
@onready var version_chip: Label = $Root/VersionChip
@onready var fireflies: CPUParticles2D = $Root/Fireflies

var _entering := false

func _ready() -> void:
	_wire_backdrop()
	# Letter-stock hero card + parchment confirm sheet sit warm against the
	# dark grove; the live backdrop (or its fallback) breathes behind them.
	UiKit.apply_parchment(hero_card)
	UiKit.apply_parchment(confirm_card, UiKit.RADIUS_BUTTON)
	_style_roles()
	_typography()
	UiKit.style_chip(version_chip, UiKit.EMBER)
	UiKit.style_chip(footer_hint, UiKit.CREAM_DIM)
	_check_continue_availability()
	# Green fireflies drift in the deep to offset the ember glow.
	if fireflies:
		fireflies.visible = true

	cta_button.pressed.connect(_on_new_tale_pressed)
	continue_button.pressed.connect(_on_continue_tale)
	settings_button.pressed.connect(_on_settings)
	confirm_yes.pressed.connect(_on_confirm_new_tale)
	confirm_no.pressed.connect(_on_cancel_new_tale)
	quit_button.pressed.connect(func():
		audio.play_ui_back()
		get_tree().quit())

	# Staggered entrance: wordmark first, then the card contents rise in
	# while the surrounding chrome fades up around the live backdrop.
	root.modulate.a = 0.0
	wordmark.modulate.a = 0.0
	create_tween().tween_property(root, "modulate:a", 1.0, 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var tw := create_tween()
	tw.tween_property(wordmark, "modulate:a", 1.0, 0.35) \
		.set_delay(0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	UiKit.stagger_entrance(hero_vbox, 0.34, 0.07, 30.0)
	# A quiet pulse on the title keeps the card from feeling static.
	_pulse_title()

func _style_roles() -> void:
	UiKit.style_primary_button(cta_button)
	UiKit.style_primary_button(confirm_yes)
	UiKit.style_secondary_button(continue_button)
	UiKit.style_secondary_button(settings_button)
	UiKit.style_secondary_button(confirm_no)
	UiKit.style_danger_button(quit_button)

func _typography() -> void:
	UiKit.style_label(wordmark, &"Wordmark")
	UiKit.style_label(eyebrow, &"Eyebrow")
	UiKit.style_label(title_label, &"Title", 62)
	UiKit.style_label(subtitle, &"Subtitle")
	UiKit.style_label(footer_hint, &"Caption")
	UiKit.style_label(version_chip, &"Caption")

func _pulse_title() -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(title_label, "self_modulate:r", 1.0, 3.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(title_label, "self_modulate:r", 0.961, 3.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	title_label.self_modulate = Color(1, 1, 1, 1)

func _wire_backdrop() -> void:
	var bd := get_tree().root.find_child("MenuBackdrop", true, false)
	fallback_bg.visible = bd == null or not bd.is_live()

func _check_continue_availability() -> void:
	continue_button.disabled = not game_state.has_save()

func _on_new_tale_pressed() -> void:
	audio.play_ui_blip()
	if game_state.has_save():
		# Swap, never stack: the confirm sheet replaces the CTA so the
		# hero card keeps one fixed footprint (no spill past the frame).
		cta_button.visible = false
		confirm_card.visible = true
		confirm_card.modulate.a = 0.0
		create_tween().tween_property(confirm_card, "modulate:a", 1.0, 0.22) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_begin_tale(true)

func _on_confirm_new_tale() -> void:
	audio.play_ui_blip()
	_begin_tale(true)

func _on_cancel_new_tale() -> void:
	audio.play_ui_back()
	confirm_card.visible = false
	cta_button.visible = true

func _on_continue_tale() -> void:
	_begin_tale(false)

func _begin_tale(fresh: bool) -> void:
	if _entering:
		return
	_entering = true
	if fresh:
		game_state.reset()
		game_state.delete_save()
	else:
		game_state.load_game()
	var tw := create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		get_tree().change_scene_to_file("res://scenes/world/grove.tscn"))

func _on_settings() -> void:
	audio.play_ui_blip()
	var settings = get_tree().root.find_child("SettingsMenu", true, false)
	if not settings:
		var scene: PackedScene = load("res://scenes/ui/settings_menu.tscn")
		settings = scene.instantiate()
		# current_scene is null when the menu boots as the initial scene —
		# fall back to root so the panel (and its BACK button) always exist.
		var host := get_tree().current_scene
		if host == null:
			host = get_tree().root
		host.add_child(settings)
	settings.open()
