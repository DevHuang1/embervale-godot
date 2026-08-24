extends CanvasLayer
class_name SettingsMenu

## === Settings ===
## Volume sliders bound to AudioManager, persisted via its ConfigFile.

@onready var audio: AudioManager = AudioManager
@onready var master_slider: HSlider = $Root/Panel/VBox/MasterRow/MasterSlider
@onready var music_slider: HSlider = $Root/Panel/VBox/MusicRow/MusicSlider
@onready var sfx_slider: HSlider = $Root/Panel/VBox/SfxRow/SfxSlider
@onready var back_button: Button = $Root/Panel/VBox/BackButton

func _ready() -> void:
	master_slider.value = audio.master_volume
	music_slider.value = audio.music_volume
	sfx_slider.value = audio.sfx_volume

	master_slider.value_changed.connect(_on_master_changed)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	back_button.pressed.connect(_on_back_pressed)

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

func _on_back_pressed() -> void:
	audio.play_ui_back()
	visible = false
