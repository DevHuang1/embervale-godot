extends CanvasLayer
class_name SettingsMenu

## === Settings ===
## Volume sliders bound to AudioManager, persisted via its ConfigFile.

@onready var audio: AudioManager = AudioManager
@onready var master_slider: HSlider = $Root/Panel/VBox/MasterRow/MasterSlider
@onready var music_slider: HSlider = $Root/Panel/VBox/MusicRow/MusicSlider
@onready var sfx_slider: HSlider = $Root/Panel/VBox/SfxRow/SfxSlider
@onready var back_button: Button = $Root/Panel/VBox/BackButton
@onready var quit_game_button: Button = $Root/Panel/VBox/QuitGameButton

func _ready() -> void:
	UiKit.apply_glass($Root/Panel)
	process_mode = Node.PROCESS_MODE_ALWAYS  # stay interactive while the world is frozen
	_freeze_was_visible = visible
	UiKit.style_secondary_button(back_button)
	UiKit.style_danger_button(quit_game_button)
	master_slider.value = audio.master_volume
	music_slider.value = audio.music_volume
	sfx_slider.value = audio.sfx_volume

	master_slider.value_changed.connect(_on_master_changed)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	back_button.pressed.connect(_on_back_pressed)
	quit_game_button.pressed.connect(func():
		audio.save_settings()
		get_tree().quit())
	_build_quality_row()

## Adaptive-quality picker: Low / Auto / High, persisted by QualityScaler.
func _build_quality_row() -> void:
	var scaler := get_node_or_null("/root/WorldState/QualityScaler")
	if scaler == null:
		return
	var vbox: VBoxContainer = $Root/Panel/VBox
	var row := HBoxContainer.new()
	row.name = "QualityRow"
	var label := Label.new()
	label.text = "Quality"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option := OptionButton.new()
	option.name = "QualityOption"
	for item in ["Low", "Auto", "High"]:
		option.add_item(item)
	option.selected = clampi(int(scaler.mode), 0, 2)
	option.item_selected.connect(func(idx: int) -> void:
		scaler.set_mode(idx)
		audio.play_ui_blip())
	row.add_child(option)
	vbox.add_child(row)
	vbox.move_child(row, vbox.get_children().find(back_button))

func open() -> void:
	visible = true

func _on_master_changed(value: float) -> void:
	audio.set_master_volume(value)
	audio.save_settings()

func _on_music_changed(value: float) -> void:
	audio.set_music_volume(value)
	audio.save_settings()

func _on_sfx_changed(value: float) -> void:
	audio.set_sfx_volume(value)
	audio.save_settings()
	audio.play_ui_blip()

var _freeze_was_visible := false

## Freeze/resume the world whenever this interface toggles, whichever
## code path opened or closed it.
func _poll_world_freeze() -> void:
	if visible == _freeze_was_visible:
		return
	_freeze_was_visible = visible
	if visible:
		game_state.push_world_freeze()
	else:
		game_state.pop_world_freeze()

func _process(_delta: float) -> void:
	_poll_world_freeze()

func _on_back_pressed() -> void:
	audio.play_ui_back()
	visible = false
