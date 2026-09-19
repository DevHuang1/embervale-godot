extends CanvasLayer
class_name MainMenu

## === Main Menu — wired to scenes/ui/main_menu.tscn ===
## Node structure from .tscn:
##   MainMenu (CanvasLayer, layer=10)
##   └── Root (Control)
##       ├── FallbackBG / Vignette / Embers / Fireflies
##       ├── Wordmark (Label)
##       ├── HeroCard (PanelContainer)
##       │   └── HeroVBox (VBoxContainer)
##       │       ├── Eyebrow / Crest / TitleLabel / SubtitleLabel / TitleRule
##       │       ├── CTAButton (Button) — "BEGIN A NEW TALE"
##       │       ├── ConfirmCard (PanelContainer, hidden)
##       │       │   └── ConfirmVBox
##       │       │       ├── ConfirmLabel
##       │       │       └── ConfirmRow
##       │       │           ├── ConfirmYes ("BEGIN ANEW")
##       │       │           └── ConfirmNo ("NOT YET")
##       │       └── SecondaryRow
##       │           ├── ContinueButton ("CONTINUE", disabled if no save)
##       │           ├── SettingsButton ("SETTINGS")
##       │           └── QuitButton ("QUIT")
##       ├── FooterHint (Label)
##       └── VersionChip (Label)

signal game_start_requested
signal load_game_requested
signal settings_requested

@onready var cta_button      : Button         = $Root/HeroCard/HeroVBox/CTAButton
@onready var confirm_card    : PanelContainer = $Root/HeroCard/HeroVBox/ConfirmCard
@onready var confirm_yes     : Button         = $Root/HeroCard/HeroVBox/ConfirmCard/ConfirmVBox/ConfirmRow/ConfirmYes
@onready var confirm_no      : Button         = $Root/HeroCard/HeroVBox/ConfirmCard/ConfirmVBox/ConfirmRow/ConfirmNo
@onready var continue_button : Button         = $Root/HeroCard/HeroVBox/SecondaryRow/ContinueButton
@onready var settings_button : Button         = $Root/HeroCard/HeroVBox/SecondaryRow/SettingsButton
@onready var quit_button     : Button         = $Root/HeroCard/HeroVBox/SecondaryRow/QuitButton

var _has_save : bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiKit.apply_parchment($Root/HeroCard)
	UiKit.apply_parchment(confirm_card)
	UiKit.style_primary_button(cta_button)
	UiKit.style_primary_button(confirm_yes)
	UiKit.style_secondary_button(confirm_no)
	UiKit.style_secondary_button(continue_button)
	UiKit.style_secondary_button(settings_button)
	UiKit.style_danger_button(quit_button)
	$Root/VersionChip.add_theme_color_override("font_color", UiKit.SAGE_BRIGHT)
	_build_crest()
	_check_continue_availability()
	_apply_responsive_frame()
	get_viewport().size_changed.connect(_apply_responsive_frame)

	# Button connections
	if cta_button:      cta_button.pressed.connect(_on_cta_pressed)
	if confirm_yes:     confirm_yes.pressed.connect(_on_confirm_yes)
	if confirm_no:      confirm_no.pressed.connect(_on_confirm_no)
	if continue_button: continue_button.pressed.connect(_on_continue)
	if settings_button: settings_button.pressed.connect(_on_settings)
	if quit_button:     quit_button.pressed.connect(_on_quit)

	# Fade in
	$Root.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property($Root, "modulate:a", 1.0, 0.65).set_trans(Tween.TRANS_QUAD)

## The authored card was a fixed 920 x 700, so on a 720 px phone both edges sat
## off-screen and the hero title was cut in half. The frame keeps the card and
## the footer hint inside the viewport and the device safe area.
func _apply_responsive_frame() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var insets := UiKit.safe_area_insets(viewport)
	var margin_x := clampf(viewport.x * 0.05, 14.0, 60.0) + float(insets["left"])
	var margin_y := clampf(viewport.y * 0.045, 14.0, 64.0) + float(insets["top"])
	var width := maxf(280.0, viewport.x - margin_x * 2.0)
	var height := maxf(280.0, viewport.y - margin_y * 2.0)
	var card := get_node_or_null("Root/HeroCard") as Control
	if card != null:
		var card_width := minf(920.0, width)
		var card_height := minf(700.0, height)
		card.anchor_left = 0.5
		card.anchor_right = 0.5
		card.anchor_top = 0.5
		card.anchor_bottom = 0.5
		card.grow_horizontal = Control.GROW_DIRECTION_BOTH
		card.grow_vertical = Control.GROW_DIRECTION_BOTH
		card.offset_left = -card_width * 0.5
		card.offset_right = card_width * 0.5
		card.offset_top = -card_height * 0.5
		card.offset_bottom = card_height * 0.5
	var footer := get_node_or_null("Root/FooterHint") as Control
	if footer != null:
		var footer_width := minf(1000.0, width)
		footer.anchor_left = 0.5
		footer.anchor_right = 0.5
		footer.anchor_top = 1.0
		footer.anchor_bottom = 1.0
		footer.grow_horizontal = Control.GROW_DIRECTION_BOTH
		footer.offset_left = -footer_width * 0.5
		footer.offset_right = footer_width * 0.5
		footer.offset_top = -(76.0 + float(insets["bottom"]))
		footer.offset_bottom = footer.offset_top + 64.0

## The crest was authored as "— ◈ —", a font glyph that renders differently in
## every locale. It is drawn chrome now: two hairlines around a copper inlay.
func _build_crest() -> void:
	var crest := get_node_or_null("Root/HeroCard/HeroVBox/Crest") as Label
	if crest == null:
		return
	crest.visible = false
	var row := HBoxContainer.new()
	row.name = "CrestRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	crest.get_parent().add_child(row)
	crest.get_parent().move_child(row, crest.get_index() + 1)
	row.add_child(_crest_rule())
	row.add_child(UiKit.diamond_marker(UiKit.EMBER, 12.0))
	row.add_child(_crest_rule())

func _crest_rule() -> Control:
	var rule := Control.new()
	rule.custom_minimum_size = Vector2(84, 6)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := ColorRect.new()
	line.color = Color(UiKit.COPPER.r, UiKit.COPPER.g, UiKit.COPPER.b, 0.34)
	line.anchor_left = 0.0
	line.anchor_right = 1.0
	line.anchor_top = 0.5
	line.anchor_bottom = 0.5
	line.offset_top = -1.0
	line.offset_bottom = 1.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.add_child(line)
	return rule

func _check_continue_availability() -> void:
	_has_save = GameState.has_save()
	continue_button.disabled = not _has_save
	var state := UiKit.action_state("available" if _has_save else "unavailable",
		"Resume the last checkpoint" if _has_save else "Start a new tale to create a save")
	continue_button.text = "CONTINUE" if _has_save else "NO SAVED TALE"
	continue_button.tooltip_text = "%s · %s" % [str(state.get("label", "")),
		str(state.get("detail", ""))]

# ─── Button handlers ──────────────────────────────────────────────────────────

func _on_cta_pressed() -> void:
	if _has_save:
		# Show confirm-overwrite card
		if confirm_card: confirm_card.visible = true
		if cta_button:   cta_button.visible   = false
	else:
		_start_new_game()

func _on_confirm_yes() -> void:
	# Delete save and start fresh
	GameState.delete_save()
	_start_new_game()

func _on_confirm_no() -> void:
	if confirm_card: confirm_card.visible = false
	if cta_button:   cta_button.visible   = true

func _on_continue() -> void:
	game_start_requested.emit()
	load_game_requested.emit()
	GameState.load_game()
	RewardManager.check_daily_bonus()
	_fade_to_game()

func _on_settings() -> void:
	settings_requested.emit()

func _on_quit() -> void:
	GameState.flush_save()
	if AudioManager != null and AudioManager.has_method("shutdown_for_exit"):
		AudioManager.shutdown_for_exit()
	get_tree().quit()

# ─── Internal ─────────────────────────────────────────────────────────────────

func _start_new_game() -> void:
	GameState.reset()
	RewardManager.check_daily_bonus()
	game_start_requested.emit()
	_fade_to_game()

func _fade_to_game() -> void:
	var tw := create_tween()
	tw.tween_property($Root, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(_load_grove)

func _load_grove() -> void:
	var scene_path := "res://scenes/world/grove.tscn"
	if ResourceLoader.exists(scene_path):
		SceneLoader.travel(scene_path)
	else:
		# Grove scene not built yet — just hide the menu overlay so whatever is in main.tscn runs
		visible = false
