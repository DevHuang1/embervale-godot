extends CanvasLayer
class_name SettingsMenu

## === Settings ===
## Volume sliders bound to AudioManager, persisted via its ConfigFile.

@onready var audio: AudioManager = AudioManager
@onready var game_state: GameState = GameState
@onready var master_slider: HSlider = $Root/Panel/Margin/VBox/Scroll/Rows/MasterRow/MasterSlider
@onready var music_slider: HSlider = $Root/Panel/Margin/VBox/Scroll/Rows/MusicRow/MusicSlider
@onready var sfx_slider: HSlider = $Root/Panel/Margin/VBox/Scroll/Rows/SfxRow/SfxSlider
@onready var back_button: Button = $Root/Panel/Margin/VBox/Footer/BackButton
@onready var quit_game_button: Button = $Root/Panel/Margin/VBox/Footer/QuitGameButton
@onready var settings_panel: Control = $Root/Panel
@onready var rows_box: VBoxContainer = $Root/Panel/Margin/VBox/Scroll/Rows
@onready var close_button: Button = $Root/Panel/Header/CloseButton
var _listening_action: String = ""
var _binding_status: Label = null
var _binding_section: VBoxContainer = null
var _binding_labels: Dictionary = {}

func _ready() -> void:
	$Root/Panel.add_theme_stylebox_override("panel", UiKit.glass_stylebox())
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	process_mode = Node.PROCESS_MODE_ALWAYS  # stay interactive while the world is frozen
	UiKit.style_secondary_button(back_button)
	UiKit.style_danger_button(quit_game_button)
	UiKit.style_secondary_button(close_button)
	close_button.pressed.connect(_on_back_pressed)
	master_slider.value = audio.master_volume
	music_slider.value = audio.music_volume
	sfx_slider.value = audio.sfx_volume

	master_slider.value_changed.connect(_on_master_changed)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	back_button.pressed.connect(_on_back_pressed)
	quit_game_button.pressed.connect(_on_quit_pressed)
	if InputManager.has_signal("pause_pressed"):
		InputManager.pause_pressed.connect(_on_pause_pressed)
	_insert_audio_section()
	_add_settings_section("Video", UiKit.COPPER)
	_build_quality_row()
	_build_world_view_row()
	_build_frame_rate_row()
	_add_settings_section("Controls", UiKit.COPPER)
	_build_camera_row()
	_build_look_sensitivity_row()
	_build_motion_row()
	_build_mobile_controls_row()
	_build_key_bindings_section()
	_add_settings_section("Combat Feedback", UiKit.COPPER)
	_build_landing_fx_row()
	_build_recovery_assist_row()
	_build_telegraph_assist_row()
	_build_color_safe_telegraph_row()
	_add_settings_section("Accessibility", UiKit.MOON)
	_build_touch_target_row()
	_build_text_scale_row()
	_build_data_export_row()

## Settings groups its rows under headers so a long scroll reads as sections
## instead of one undifferentiated list of dropdowns.
func _add_settings_section(title: String, accent: Color) -> void:
	if rows_box == null:
		return
	rows_box.add_child(UiKit.section_header(title, accent))

## The three volume sliders are authored in the scene, so their header is
## inserted ahead of them rather than appended after the runtime rows.
func _insert_audio_section() -> void:
	if rows_box == null:
		return
	var header := UiKit.section_header("Audio", UiKit.COPPER)
	rows_box.add_child(header)
	rows_box.move_child(header, 0)

func _apply_responsive_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var metrics := UiKit.responsive_metrics(viewport_size)
	var margin := float(metrics.get("safe_margin", UiKit.SAFE_MARGIN_COMPACT))
	var width := clampf(viewport_size.x - margin * 2.0, 320.0, 760.0)
	var height := clampf(viewport_size.y - margin * 2.0, 360.0, 1500.0)
	settings_panel.offset_left = -width * 0.5
	settings_panel.offset_right = width * 0.5
	settings_panel.offset_top = -height * 0.5
	settings_panel.offset_bottom = height * 0.5
	var compact := bool(metrics.get("compact", true))
	$Root/Panel/Margin.add_theme_constant_override("margin_left", 14 if compact else 20)
	$Root/Panel/Margin.add_theme_constant_override("margin_right", 14 if compact else 20)
	$Root/Panel/Margin/VBox.add_theme_constant_override("separation", 10 if compact else 14)

## ESC toggles the menu. Handled HERE (not via InputManager) because the
## InputManager autoload won't receive input while get_tree().paused is true,
## whereas this menu runs PROCESS_MODE_ALWAYS and still sees keys. Connecting
## the pause_pressed signal keeps the ESC key's intent intact AND makes the
## pause path testable; the _unhandled_input guard dedupes the two routes
## firing for the same press (the signal emits on key-press too).
func _unhandled_input(event: InputEvent) -> void:
	if not _listening_action.is_empty() and event is InputEventKey \
			and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_binding_status.text = "Binding cancelled"
		else:
			var changed := InputManager.set_key_binding(_listening_action, event.keycode)
			_binding_status.text = "BOUND %s" % OS.get_keycode_string(event.keycode) \
				if changed else "KEY IN USE · CHOOSE ANOTHER"
			_build_key_bindings_section_refresh(_binding_section, _binding_labels)
			_listening_action = ""
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		_handle_pause_toggle()
		get_viewport().set_input_as_handled()

func _on_pause_pressed() -> void:
	_handle_pause_toggle()

func _build_mobile_controls_row() -> void:
	var vbox: VBoxContainer = rows_box
	_add_mobile_slider(vbox, "Joystick size", "joystick_scale", 0.75, 1.45, 1.0)
	_add_mobile_slider(vbox, "Action button size", "action_scale", 0.75, 1.35, 1.0)
	_add_mobile_slider(vbox, "Control opacity", "opacity", 0.55, 1.0, 0.92)
	var row := HBoxContainer.new()
	row.name = "MobileLayoutRow"
	var label := Label.new()
	label.text = "Layout"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option := OptionButton.new()
	option.add_item("Right-handed")
	option.add_item("Left-handed")
	var config := ConfigFile.new()
	config.load(AudioManager.SETTINGS_PATH)
	option.selected = 1 if str(config.get_value("mobile_controls", "layout", "standard")) == "left_handed" else 0
	option.item_selected.connect(func(index: int) -> void:
		_save_mobile_value("layout", "left_handed" if index == 1 else "standard")
	)
	row.add_child(option)
	vbox.add_child(row)

func _add_mobile_slider(vbox: VBoxContainer, label_text: String, key: String,
		minimum: float, maximum: float, fallback: float) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = key
	slider.custom_minimum_size = Vector2(150, 32)
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.05
	var config := ConfigFile.new()
	config.load(AudioManager.SETTINGS_PATH)
	slider.value = clampf(float(config.get_value("mobile_controls", key, fallback)), minimum, maximum)
	slider.value_changed.connect(func(value: float) -> void: _save_mobile_value(key, value))
	row.add_child(slider)
	vbox.add_child(row)

func _save_mobile_value(key: String, value: Variant) -> void:
	var config := ConfigFile.new()
	config.load(AudioManager.SETTINGS_PATH)
	config.set_value("mobile_controls", key, value)
	config.save(AudioManager.SETTINGS_PATH)

func _handle_pause_toggle() -> void:
	if visible:
		audio.play_ui_back()
		visible = false
	else:
		open()

## First/third-person choice is available on mobile and desktop. Desktop also
## has the V shortcut, but this persisted picker remains the authoritative UI.
func _build_camera_row() -> void:
	var vbox: VBoxContainer = rows_box
	var row := HBoxContainer.new()
	row.name = "CameraViewRow"
	var label := Label.new()
	label.text = "Camera"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option := OptionButton.new()
	option.name = "CameraViewOption"
	option.add_item("Third Person")
	option.add_item("First Person")
	option.tooltip_text = "Tap to move; joystick to steer. Mobile: drag anywhere on the right side of the screen to turn the camera and pinch to zoom. Desktop: left/right-drag or horizontal wheel to turn the camera, wheel to zoom."
	var config := ConfigFile.new()
	config.load(AudioManager.SETTINGS_PATH)
	var current := str(config.get_value("gameplay", "camera_view", "third_person"))
	option.selected = 1 if current == "first_person" else 0
	option.item_selected.connect(func(index: int) -> void:
		var mode := "first_person" if index == 1 else "third_person"
		var camera_rig := get_tree().root.find_child("CameraRig", true, false)
		if camera_rig != null and camera_rig.has_method("set_view_mode"):
			camera_rig.call("set_view_mode", mode)
		else:
			var settings := ConfigFile.new()
			settings.load(AudioManager.SETTINGS_PATH)
			settings.set_value("gameplay", "camera_view", mode)
			settings.save(AudioManager.SETTINGS_PATH)
		audio.play_ui_blip())
	row.add_child(option)
	vbox.add_child(row)
	_move_hint_below(row)

## The camera help paragraph is authored in the scene above the runtime rows, so
## it is re-seated directly under the row it actually explains.
func _move_hint_below(row: Control) -> void:
	var hint := get_node_or_null("Root/Panel/Margin/VBox/Scroll/Rows/HintLabel") as Control
	if hint == null or row == null or hint.get_parent() != row.get_parent():
		return
	hint.get_parent().move_child(hint, row.get_index() + 1)

## One slider scales every camera look gesture: third-person drag orbit and
## first-person free-look. The rig owns the multiplier and persists it with the
## other camera preferences; the slider only reports the player's choice.
func _build_look_sensitivity_row() -> void:
	var vbox: VBoxContainer = rows_box
	var row := HBoxContainer.new()
	row.name = "CameraSensitivityRow"
	var label := Label.new()
	label.text = "Camera Sensitivity"
	label.tooltip_text = "How far a drag turns the camera, in third person and first person. Persists across realms and restarts."
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = "CameraSensitivitySlider"
	slider.custom_minimum_size = Vector2(150, 32)
	slider.min_value = CameraRig.MIN_LOOK_SENSITIVITY
	slider.max_value = CameraRig.MAX_LOOK_SENSITIVITY
	slider.step = 0.1
	slider.value = _current_look_sensitivity()
	slider.value_changed.connect(func(value: float) -> void: _apply_look_sensitivity(value))
	row.add_child(slider)
	vbox.add_child(row)
	_move_hint_below(row)

func _current_look_sensitivity() -> float:
	var camera_rig := get_tree().root.find_child("CameraRig", true, false)
	if camera_rig != null and camera_rig.has_method("get_look_sensitivity"):
		return clampf(float(camera_rig.call("get_look_sensitivity")),
			CameraRig.MIN_LOOK_SENSITIVITY, CameraRig.MAX_LOOK_SENSITIVITY)
	var config := ConfigFile.new()
	config.load(AudioManager.SETTINGS_PATH)
	return clampf(float(config.get_value("gameplay", "camera_sensitivity", 1.0)),
		CameraRig.MIN_LOOK_SENSITIVITY, CameraRig.MAX_LOOK_SENSITIVITY)

func _apply_look_sensitivity(value: float) -> void:
	var camera_rig := get_tree().root.find_child("CameraRig", true, false)
	if camera_rig != null and camera_rig.has_method("set_look_sensitivity"):
		camera_rig.call("set_look_sensitivity", value)
		return
	var settings := ConfigFile.new()
	settings.load(AudioManager.SETTINGS_PATH)
	settings.set_value("gameplay", "camera_sensitivity", value)
	settings.save(AudioManager.SETTINGS_PATH)

## Adaptive-quality picker: Low / Auto / High, persisted by QualityScaler.
func _build_quality_row() -> void:
	var scaler := get_node_or_null("/root/WorldState/QualityScaler")
	if scaler == null:
		return
	var vbox: VBoxContainer = rows_box
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

## Presentation-only distance picker. Reduced keeps gameplay and collision
## intact while hiding distant world geometry and shrinking streamed rings.
func _build_world_view_row() -> void:
	var scaler := get_node_or_null("/root/WorldState/QualityScaler")
	if scaler == null:
		return
	var vbox: VBoxContainer = rows_box
	var row := HBoxContainer.new()
	row.name = "WorldViewRow"
	var label := Label.new()
	label.text = "World View"
	label.tooltip_text = "Reduced hides far scenery and uses a shorter view distance for older phones. Gameplay, collision, and quest logic are unchanged."
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var option := OptionButton.new()
	option.name = "WorldViewOption"
	option.add_item("Full")
	option.add_item("Reduced")
	option.selected = clampi(int(scaler.get("world_view_mode")), 0, 1)
	option.item_selected.connect(func(index: int) -> void:
		scaler.call("set_world_view_mode", index)
		audio.play_ui_blip())
	row.add_child(option)
	vbox.add_child(row)

## Frame-rate picker: Default (vsync) / 60 / 30, persisted by QualityScaler and
## re-applied at boot + every scene change so the choice survives restarts.
func _build_frame_rate_row() -> void:
	var scaler := get_node_or_null("/root/WorldState/QualityScaler")
	if scaler == null:
		return
	var vbox: VBoxContainer = rows_box
	var row := HBoxContainer.new()
	row.name = "FrameRateRow"
	var label := Label.new()
	label.text = "Frame Rate"
	label.tooltip_text = "Caps the target frame rate. 30 FPS saves battery and runs cooler; Default uses the display's vsync."
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var option := OptionButton.new()
	option.name = "FrameRateOption"
	for item in ["Default", "60 FPS", "30 FPS"]:
		option.add_item(item)
	option.selected = clampi(int(scaler.get("frame_rate_mode")), 0, 2)
	option.item_selected.connect(func(idx: int) -> void:
		scaler.call("set_frame_rate", idx)
		audio.play_ui_blip())
	row.add_child(option)
	vbox.add_child(row)

func _build_landing_fx_row() -> void:
	var vbox: VBoxContainer = rows_box
	var row := HBoxContainer.new()
	row.name = "LandingFxRow"
	row.custom_minimum_size.y = UiKit.TOUCH_TARGET_MIN
	var label := Label.new()
	label.text = "Landing FX"
	label.tooltip_text = "Controls landing squash, dust, camera impact, debris, and sound intensity."
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var option := OptionButton.new()
	option.name = "LandingFxOption"
	for item in ["Full", "Reduced", "Off"]:
		option.add_item(item)
	var hero := get_tree().root.find_child("Hero", true, false)
	var current := "full"
	if hero != null and hero.has_method("get_landing_fx_mode"):
		current = str(hero.call("get_landing_fx_mode"))
	option.selected = ["full", "reduced", "off"].find(current)
	option.item_selected.connect(func(index: int) -> void:
		_save_landing_fx_mode(["full", "reduced", "off"][index])
		audio.play_ui_blip())
	row.add_child(label)
	row.add_child(option)
	vbox.add_child(row)

func _save_landing_fx_mode(mode: String) -> void:
	var normalized := mode.to_lower()
	if normalized not in ["full", "reduced", "off"]:
		return
	var hero := get_tree().root.find_child("Hero", true, false)
	if hero != null and hero.has_method("set_landing_fx_mode"):
		hero.call("set_landing_fx_mode", normalized)
	else:
		var config := ConfigFile.new()
		config.load(AudioManager.SETTINGS_PATH)
		config.set_value("accessibility", "landing_fx", normalized)
		config.save(AudioManager.SETTINGS_PATH)

func _build_motion_row() -> void:
	var camera_rig := get_tree().root.find_child("CameraRig", true, false)
	if camera_rig == null:
		return
	var vbox: VBoxContainer = rows_box
	var row := HBoxContainer.new()
	row.name = "MotionFeedbackRow"
	var label := Label.new()
	label.text = "Motion Feedback"
	label.tooltip_text = "Controls camera shake intensity for comfort and accessibility."
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option := OptionButton.new()
	option.name = "MotionFeedbackOption"
	var modes := ["Full", "Mobile", "Reduced", "Off"]
	for mode in modes:
		option.add_item(mode)
	var config := ConfigFile.new()
	config.load(AudioManager.SETTINGS_PATH)
	var current := str(config.get_value("gameplay", "motion_feedback",
		str(camera_rig.get("feedback_mode"))))
	option.selected = maxi(0, modes.find(current.capitalize()))
	option.item_selected.connect(func(index: int) -> void:
		var mode: String = str(modes[index]).to_lower()
		camera_rig.set("feedback_mode", mode)
		get_tree().call_group("screen_fx", "set_motion_feedback", mode)
		var settings := ConfigFile.new()
		settings.load(AudioManager.SETTINGS_PATH)
		settings.set_value("gameplay", "motion_feedback", mode)
		settings.save(AudioManager.SETTINGS_PATH)
		audio.play_ui_blip())
	row.add_child(option)
	vbox.add_child(row)

func _build_recovery_assist_row() -> void:
	var vbox: VBoxContainer = rows_box
	var row := HBoxContainer.new()
	row.name = "RecoveryAssistRow"
	var label := Label.new()
	label.text = "Recovery Assist"
	label.tooltip_text = "Adds a small capped dodge grace window. Damage, rewards, and achievements do not change."
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option := OptionButton.new()
	option.name = "RecoveryAssistOption"
	option.add_item("Off")
	option.add_item("On")
	var config := ConfigFile.new()
	config.load(AudioManager.SETTINGS_PATH)
	var enabled := bool(config.get_value("gameplay", "recovery_assist", false))
	option.selected = 1 if enabled else 0
	option.item_selected.connect(func(index: int) -> void:
		var settings := ConfigFile.new()
		settings.load(AudioManager.SETTINGS_PATH)
		settings.set_value("gameplay", "recovery_assist", index == 1)
		settings.save(AudioManager.SETTINGS_PATH)
		var hero := get_tree().root.find_child("Hero", true, false)
		if hero != null and "accessibility_recovery_assist" in hero:
			hero.set("accessibility_recovery_assist", index == 1)
		audio.play_ui_blip())
	row.add_child(option)
	vbox.add_child(row)

func _build_telegraph_assist_row() -> void:
	var vbox: VBoxContainer = rows_box
	var row := HBoxContainer.new()
	row.name = "TelegraphAssistRow"
	var label := Label.new()
	label.text = "Telegraph Clarity"
	label.tooltip_text = "Extends enemy wind-ups by up to 25%; damage and rewards stay unchanged."
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option := OptionButton.new()
	option.name = "TelegraphAssistOption"
	option.add_item("Off")
	option.add_item("On")
	var config := ConfigFile.new()
	config.load(AudioManager.SETTINGS_PATH)
	option.selected = 1 if bool(config.get_value("gameplay", "telegraph_assist", false)) else 0
	option.item_selected.connect(func(index: int) -> void:
		var settings := ConfigFile.new()
		settings.load(AudioManager.SETTINGS_PATH)
		settings.set_value("gameplay", "telegraph_assist", index == 1)
		settings.save(AudioManager.SETTINGS_PATH)
		for enemy in get_tree().get_nodes_in_group("enemy"):
			if "accessibility_telegraph_assist" in enemy:
				enemy.set("accessibility_telegraph_assist", index == 1)
		audio.play_ui_blip())
	row.add_child(option)
	vbox.add_child(row)

func _build_touch_target_row() -> void:
	var vbox: VBoxContainer = rows_box
	var row := HBoxContainer.new()
	row.name = "TouchTargetSizeRow"
	var label := Label.new()
	label.text = "Touch Target Size"
	label.tooltip_text = "Enlarges combat controls without changing their timing or damage."
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option := OptionButton.new()
	option.name = "TouchTargetSizeOption"
	var sizes := ["100%", "125%", "150%"]
	for size in sizes:
		option.add_item(size)
	var config := ConfigFile.new()
	config.load(AudioManager.SETTINGS_PATH)
	var saved_scale := clampf(float(config.get_value("accessibility", "touch_target_scale", 1.0)), 1.0, 1.5)
	option.selected = clampi(roundi((saved_scale - 1.0) / 0.25), 0, sizes.size() - 1)
	_apply_touch_target_scale(saved_scale)
	option.item_selected.connect(func(index: int) -> void:
		var scale := 1.0 + float(index) * 0.25
		var settings := ConfigFile.new()
		settings.load(AudioManager.SETTINGS_PATH)
		settings.set_value("accessibility", "touch_target_scale", scale)
		settings.save(AudioManager.SETTINGS_PATH)
		_apply_touch_target_scale(scale)
		audio.play_ui_blip())
	row.add_child(option)
	vbox.add_child(row)

func _build_color_safe_telegraph_row() -> void:
	var vbox: VBoxContainer = rows_box
	var row := HBoxContainer.new()
	row.name = "ColorSafeTelegraphRow"
	var label := Label.new()
	label.text = "Telegraph Shape + Text"
	label.tooltip_text = "Adds a high-contrast DANGER cue so warnings do not rely on color alone."
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option := OptionButton.new()
	option.name = "ColorSafeTelegraphOption"
	option.add_item("Off")
	option.add_item("On")
	var config := ConfigFile.new()
	config.load(AudioManager.SETTINGS_PATH)
	option.selected = 1 if bool(config.get_value("accessibility", "color_safe_telegraphs", false)) else 0
	option.item_selected.connect(func(index: int) -> void:
		var settings := ConfigFile.new()
		settings.load(AudioManager.SETTINGS_PATH)
		settings.set_value("accessibility", "color_safe_telegraphs", index == 1)
		settings.save(AudioManager.SETTINGS_PATH)
		audio.play_ui_blip())
	row.add_child(option)
	vbox.add_child(row)

func _build_text_scale_row() -> void:
	var vbox: VBoxContainer = rows_box
	var row := HBoxContainer.new()
	row.name = "TextScaleRow"
	var label := Label.new()
	label.text = "Text Size"
	label.tooltip_text = "Scales readable UI text without changing gameplay timing."
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option := OptionButton.new()
	option.name = "TextScaleOption"
	var sizes := ["100%", "115%", "130%"]
	for size in sizes:
		option.add_item(size)
	var config := ConfigFile.new()
	config.load(AudioManager.SETTINGS_PATH)
	var saved_scale := clampf(float(config.get_value("accessibility", "text_scale", 1.0)), 1.0, 1.3)
	option.selected = clampi(roundi((saved_scale - 1.0) / 0.15), 0, sizes.size() - 1)
	_apply_text_scale(saved_scale)
	option.item_selected.connect(func(index: int) -> void:
		var scale := 1.0 + float(index) * 0.15
		var settings := ConfigFile.new()
		settings.load(AudioManager.SETTINGS_PATH)
		settings.set_value("accessibility", "text_scale", scale)
		settings.save(AudioManager.SETTINGS_PATH)
		_apply_text_scale(scale)
		audio.play_ui_blip())
	row.add_child(option)
	vbox.add_child(row)

func _apply_text_scale(scale: float) -> void:
	UiKit.apply_accessibility_text_scale(get_tree().current_scene, scale)
	UiKit.apply_accessibility_text_scale(self, scale)

func _apply_touch_target_scale(scale: float) -> void:
	for control in get_tree().get_nodes_in_group("combat_action_controls"):
		if control is FightButton:
			(control as FightButton).accessibility_touch_scale = scale

func _build_key_bindings_section() -> void:
	var vbox: VBoxContainer = rows_box
	var section := VBoxContainer.new()
	section.name = "KeyBindingsSection"
	_binding_section = section
	section.add_child(UiKit.section_header("Key Bindings", UiKit.COPPER))
	_binding_status = Label.new()
	_binding_status.text = "Select an action, then press a key"
	_binding_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(_binding_status, &"Caption", 18)
	section.add_child(_binding_status)
	var labels := {"scan": "Scan", "skill_0": "Skill 1", "skill_1": "Skill 2",
		"skill_2": "Skill 3", "interact": "Interact", "pause": "Pause",
		"dodge": "Dodge", "jump": "Jump"}
	_binding_labels = labels
	for action in labels:
		var button := Button.new()
		button.name = "Bind_%s" % str(action)
		button.text = "%s: %s" % [str(labels[action]), OS.get_keycode_string(InputManager.get_key_binding(str(action)))]
		button.custom_minimum_size = Vector2(0, 44)
		UiKit.style_secondary_button(button)
		button.pressed.connect(func() -> void:
			_listening_action = str(action)
			_binding_status.text = "PRESS A KEY FOR %s · ESC CANCELS" % str(labels[action]).to_upper())
		section.add_child(button)
	var reset := Button.new()
	reset.name = "ResetKeyBindings"
	reset.text = "RESET DEFAULT KEYS"
	UiKit.style_secondary_button(reset)
	reset.pressed.connect(func() -> void:
		InputManager.reset_key_bindings()
		_binding_status.text = "DEFAULT KEYS RESTORED"
		_build_key_bindings_section_refresh(section, labels))
	section.add_child(reset)
	vbox.add_child(section)

func _build_key_bindings_section_refresh(section: VBoxContainer, labels: Dictionary) -> void:
	for child in section.get_children():
		if child is Button and child.name.begins_with("Bind_"):
			var action := str(child.name.trim_prefix("Bind_"))
			(child as Button).text = "%s: %s" % [str(labels.get(action, action)),
				OS.get_keycode_string(InputManager.get_key_binding(action))]

func _build_data_export_row() -> void:
	var vbox: VBoxContainer = rows_box
	var section := VBoxContainer.new()
	section.name = "DataExportSection"
	section.add_child(UiKit.section_header("Support Data", UiKit.COPPER))
	var note := Label.new()
	note.text = "Local progress exports are diagnostic. Paid ownership is revalidated by your account provider.\nA local reset clears this device's progress only; it cannot cancel or restore provider-owned purchases."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(note, &"Caption", 18)
	section.add_child(note)
	var button := Button.new()
	button.name = "CopySupportExport"
	button.text = "COPY SUPPORT EXPORT"
	button.tooltip_text = "Copies a safe, non-authoritative support payload to the clipboard."
	button.custom_minimum_size = Vector2(0, 48)
	UiKit.style_secondary_button(button)
	button.pressed.connect(func() -> void:
		var payload := game_state.build_data_export()
		DisplayServer.clipboard_set(JSON.stringify(payload))
		note.text = "Copied. Do not share payment receipts or secrets in screenshots."
		audio.play_ui_blip())
	section.add_child(button)
	vbox.add_child(section)

func open() -> void:
	visible = true

## Public close, so a surface opening over this one retires it instead of
## stacking a second sheet on top of it.
func close() -> void:
	if not visible:
		return
	visible = false

## Return to the main menu: persist settings + progress, then release the
## world-freeze. clear_ui_freeze() is the hard reset here — this menu is
## freed by change_scene_to_file() while visible, so a normal pop would leak
## the freeze count into main.tscn and leave it paused forever.
func _on_quit_pressed() -> void:
	audio.save_settings()
	game_state.save_game()
	audio.play_ui_back()
	game_state.clear_ui_freeze()
	SceneLoader.travel("res://scenes/main/main.tscn")

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
var _freeze_held := false

## Freeze/resume the world whenever this interface toggles, whichever
## code path opened or closed it. On the landing (main menu) there is no
## world to freeze, so the pause is skipped — the backdrop keeps animating
## and no freeze hold can leak into the gameplay scene afterwards.
func _poll_world_freeze() -> void:
	if visible == _freeze_was_visible:
		return
	_freeze_was_visible = visible
	var on_landing := false
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path == "res://scenes/main/main.tscn":
		on_landing = true
	if on_landing:
		return
	if visible:
		game_state.push_world_freeze()
		_freeze_held = true
	else:
		_release_world_freeze()

func _process(_delta: float) -> void:
	_poll_world_freeze()

func _on_back_pressed() -> void:
	audio.play_ui_back()
	close()

## A menu freed while it still holds the world must not leave it paused behind
## it. Every freeze-holding surface shares this guarantee, matching the altar's
## teardown behaviour.
func _exit_tree() -> void:
	_release_world_freeze()

func _release_world_freeze() -> void:
	if not _freeze_held:
		return
	_freeze_held = false
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("pop_world_freeze"):
		gs.call("pop_world_freeze")
