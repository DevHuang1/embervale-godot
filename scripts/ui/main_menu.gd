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
	# Check for existing save
	var slm := get_node_or_null("/root/SaveLoadManager")
	_has_save = slm.call("has_save") if slm and slm.has_method("has_save") else false

	# Enable continue only if save exists
	if continue_button:
		continue_button.disabled = not _has_save

	# Button connections
	if cta_button:      cta_button.pressed.connect(_on_cta_pressed)
	if confirm_yes:     confirm_yes.pressed.connect(_on_confirm_yes)
	if confirm_no:      confirm_no.pressed.connect(_on_confirm_no)
	if continue_button: continue_button.pressed.connect(_on_continue)
	if settings_button: settings_button.pressed.connect(_on_settings)
	if quit_button:     quit_button.pressed.connect(_on_quit)

	# Fade in
	modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.65).set_trans(Tween.TRANS_QUAD)

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
	var slm := get_node_or_null("/root/SaveLoadManager")
	if slm and slm.has_method("delete_save"):
		slm.call("delete_save")
	_start_new_game()

func _on_confirm_no() -> void:
	if confirm_card: confirm_card.visible = false
	if cta_button:   cta_button.visible   = true

func _on_continue() -> void:
	game_start_requested.emit()
	load_game_requested.emit()
	var slm := get_node_or_null("/root/SaveLoadManager")
	if slm and slm.has_method("load_save"):
		var gs := get_node_or_null("/root/GameState")
		if gs and slm.has_method("bind"):
			slm.call("bind", gs)
		slm.call("load_save")
	_fade_to_game()

func _on_settings() -> void:
	settings_requested.emit()

func _on_quit() -> void:
	get_tree().quit()

# ─── Internal ─────────────────────────────────────────────────────────────────

func _start_new_game() -> void:
	game_start_requested.emit()
	_fade_to_game()

func _fade_to_game() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(_load_grove)

func _load_grove() -> void:
	var scene_path := "res://scenes/world/grove.tscn"
	if ResourceLoader.exists(scene_path):
		get_tree().change_scene_to_file(scene_path)
	else:
		# Grove scene not built yet — just hide the menu overlay so whatever is in main.tscn runs
		visible = false
