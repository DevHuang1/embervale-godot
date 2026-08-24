extends CanvasLayer
class_name MainMenu

## === Main Menu ===
## Lantern-bearer intro, continue, satchel, settings

@onready var game_state: GameState = GameState
@onready var cta_button: Button = $Root/VBox/IntroCard/IntroVBox/CTAButton
@onready var continue_button: Button = $Root/VBox/MenuButtons/ContinueButton
@onready var satchel_button: Button = $Root/VBox/MenuButtons/SatchelButton
@onready var settings_button: Button = $Root/VBox/MenuButtons/SettingsButton

func _ready() -> void:
	_check_continue_availability()
	
	cta_button.pressed.connect(_on_new_tale)
	continue_button.pressed.connect(_on_continue_tale)
	satchel_button.pressed.connect(_on_satchel)
	settings_button.pressed.connect(_on_settings)

func _check_continue_availability() -> void:
	# Enable continue only when a saved tale exists
	var has_progress = game_state.has_save()
	continue_button.disabled = not has_progress
	if not has_progress:
		continue_button.text = "CONTINUE (no tale begun)"

func _on_new_tale() -> void:
	game_state.reset()
	game_state.delete_save()
	get_tree().change_scene_to_file("res://scenes/world/grove.tscn")

func _on_continue_tale() -> void:
	game_state.load_game()
	get_tree().change_scene_to_file("res://scenes/world/grove.tscn")

func _on_satchel() -> void:
	var satchel = get_tree().root.find_child("SatchelUI", true, false)
	if satchel:
		satchel.visible = true

func _on_settings() -> void:
	var settings = get_tree().root.find_child("SettingsMenu", true, false)
	if not settings:
		var scene: PackedScene = load("res://scenes/ui/settings_menu.tscn")
		settings = scene.instantiate()
		get_tree().current_scene.add_child(settings)
	settings.open()