extends CanvasLayer
class_name BossAltar

## === Shape Your Foe — Boss Altar ===
## Pre-boss customization gate. Choose a trophy palette claimed from felled
## bosses (starter palettes are always available), pick ONE skill from the
## boss's realm pool and an SFX preset, then Lock In to spend one lens charge.
## Declining keeps the default boss; cancel/close counts as declining and
## never consumes a charge.
##
## Emits `resolved(customized: bool)` exactly once, then the opener unpauses
## the world and frees this layer.

signal resolved(customized: bool)

@onready var game_state: GameState = GameState
@onready var audio: AudioManager = AudioManager

@onready var title_label: Label = $Root/VBox/Title
@onready var scan_line: Label = $Root/VBox/ScanLine
@onready var locked_blurb: Label = $Root/VBox/LockedBlurb
@onready var action_row: HBoxContainer = $Root/VBox/ActionRow
@onready var default_button: Button = $Root/VBox/ActionRow/DefaultButton
@onready var status_label: Label = $Root/VBox/Status
@onready var exit_button: Button = $Root/VBox/ExitButton
@onready var custom_box: VBoxContainer = $Root/VBox/CustomBox
@onready var palette_tag: Label = $Root/VBox/CustomBox/PaletteTag
@onready var palette_row: HBoxContainer = $Root/VBox/CustomBox/PaletteRow
@onready var skill_grid: GridContainer = $Root/VBox/CustomBox/SkillGrid
@onready var sfx_row: HBoxContainer = $Root/VBox/CustomBox/SfxRow
@onready var summary: Label = $Root/VBox/CustomBox/Summary
@onready var lock_button: Button = $Root/VBox/CustomBox/LockRow/LockButton

const BOSS_ID := "matriarch"
const PRESET_LABELS := {
	"hollow_resin": "HOLLOW RESIN",
	"grave_moss": "GRAVE MOSS",
	"ember_glass": "EMBER GLASS",
}

var practice := false
var _palette: Array[Color] = []
var _selected_skill: Dictionary = {}
var _selected_preset := "vanilla"
var _selected_trophy: Dictionary = {}
var _trophy_buttons: Dictionary = {}
var _resolved := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiKit.apply_glass($Root)
	UiKit.style_secondary_button(exit_button)
	var def := Bestiary.boss_def(BOSS_ID)
	title_label.text = "SHAPE YOUR FOE"
	locked_blurb.text = str(def.get("locked_blurb", ""))
	scan_line.text = "The lens holds %d charge%s." % [game_state.scans_remaining,
		"" if game_state.scans_remaining == 1 else "s"]
	status_label.text = ""
	custom_box.visible = true
	lock_button.disabled = true
	lock_button.text = "LOCK IN · 1 LENS CHARGE"

	var scan_button := get_node_or_null("Root/VBox/ActionRow/ScanButton")
	if scan_button != null:
		scan_button.queue_free()
	var rescan_button := get_node_or_null("Root/VBox/CustomBox/LockRow/RescanButton")
	if rescan_button != null:
		rescan_button.queue_free()

	default_button.pressed.connect(func(): _resolve(false))
	lock_button.pressed.connect(_on_lock_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	_build_trophy_row()
	_build_skill_cards()
	_build_sfx_buttons()
	_apply_responsive_frame()
	get_viewport().size_changed.connect(_apply_responsive_frame)

func _apply_responsive_frame() -> void:
	UiKit.apply_menu_frame(get_node_or_null("Root") as Control,
		get_viewport().get_visible_rect().size, 80.0, 60.0)

func _on_exit_pressed() -> void:
	audio.play_ui_back()
	_resolve(false)

func _trophy_unlocked(trophy: Dictionary) -> bool:
	var boss_key := str(trophy.get("unlock_boss", ""))
	if boss_key.is_empty():
		return true
	return game_state.has_boss_killed(boss_key)

func _trophy_lock_label(trophy: Dictionary) -> String:
	var boss_key := str(trophy.get("unlock_boss", ""))
	if boss_key.is_empty():
		return ""
	var boss_name := str(Bestiary.boss_def(boss_key).get("name", boss_key))
	return "LOCKED — DEFEAT %s" % boss_name.to_upper()

func _build_trophy_row() -> void:
	var trophies: Array = Bestiary.boss_def(BOSS_ID).get("trophies", [])
	var panel := PanelContainer.new()
	panel.name = "TrophyPanel"
	panel.add_theme_stylebox_override("panel", UiKit.glass_stylebox(false, 0.85))
	var box := VBoxContainer.new()
	box.name = "TrophyBox"
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var tag := Label.new()
	tag.text = "TROPHY PALETTE · CLAIMED FROM FELLED BOSSES"
	UiKit.style_label(tag, &"Eyebrow", 20)
	box.add_child(tag)

	var row := HBoxContainer.new()
	row.name = "TrophyRow"
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)

	var first_unlocked: Dictionary = {}
	for raw in trophies:
		if not raw is Dictionary:
			continue
		var trophy: Dictionary = raw
		var button := Button.new()
		button.name = "Trophy_%s" % str(trophy.get("id", "unknown"))
		button.text = str(trophy.get("name", "TROPHY")).to_upper()
		button.custom_minimum_size = Vector2(0, 54)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.disabled = not _trophy_unlocked(trophy)
		if button.disabled:
			button.text = "%s\n%s" % [str(trophy.get("name", "TROPHY")).to_upper(),
				_trophy_lock_label(trophy)]
			button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(_on_trophy_selected.bind(trophy, button))
		row.add_child(button)
		_trophy_buttons[str(trophy.get("id", ""))] = button
		if button.disabled:
			continue
		if first_unlocked.is_empty():
			first_unlocked = trophy

	custom_box.add_child(panel)
	custom_box.move_child(panel, 0)
	if not first_unlocked.is_empty():
		_apply_trophy(first_unlocked)
		var button: Button = _trophy_buttons.get(str(first_unlocked.get("id", "")), null)
		if button != null:
			button.button_pressed = true

func _on_trophy_selected(trophy: Dictionary, btn: Button) -> void:
	for other_id in _trophy_buttons:
		var other: Button = _trophy_buttons[other_id]
		if other != btn:
			other.button_pressed = false
	if not btn.button_pressed:
		_selected_trophy = {}
		_palette.clear()
	else:
		_apply_trophy(trophy)
	audio.play_ui_blip()
	_refresh_lock()

func _apply_trophy(trophy: Dictionary) -> void:
	_selected_trophy = trophy.duplicate(true)
	_palette.clear()
	var colors: Array = trophy.get("palette", [])
	for color in colors:
		if color is Color:
			_palette.append(color)
	_paint_palette_swatches()
	palette_tag.text = "TROPHY PALETTE · %s" % str(trophy.get("name", "")).to_upper()

func _paint_palette_swatches() -> void:
	for child in palette_row.get_children():
		child.queue_free()
	for col in _palette:
		var swatch := Panel.new()
		swatch.custom_minimum_size = Vector2(44, 30)
		var style := StyleBoxFlat.new()
		style.bg_color = col
		style.set_corner_radius_all(4)
		swatch.add_theme_stylebox_override("panel", style)
		palette_row.add_child(swatch)

func _build_skill_cards() -> void:
	for sk in Bestiary.skill_pool(BOSS_ID):
		var btn := Button.new()
		btn.text = "%s\n%s" % [str(sk.name).to_upper(), str(sk.desc)]
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(230, 84)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_font_size_override("font_size", 18)
		btn.pressed.connect(_on_skill_selected.bind(sk.get("id", ""), btn))
		skill_grid.add_child(btn)

func _build_sfx_buttons() -> void:
	for preset in Bestiary.boss_def(BOSS_ID).get("sfx_presets", []):
		var btn := Button.new()
		btn.text = PRESET_LABELS.get(str(preset), str(preset).to_upper())
		btn.toggle_mode = true
		btn.add_theme_font_size_override("font_size", 18)
		btn.pressed.connect(_on_preset_selected.bind(str(preset), btn))
		sfx_row.add_child(btn)

func _on_skill_selected(skill_id: String, btn: Button) -> void:
	for other in skill_grid.get_children():
		if other is Button and other != btn:
			other.button_pressed = false
	if not btn.button_pressed:
		_selected_skill = {}
	else:
		for sk in Bestiary.skill_pool(BOSS_ID):
			if str(sk.get("id", "")) == skill_id:
				_selected_skill = sk
				break
	audio.play_ui_blip()
	_refresh_lock()

func _on_preset_selected(preset: String, btn: Button) -> void:
	for other in sfx_row.get_children():
		if other is Button and other != btn:
			other.button_pressed = false
	_selected_preset = preset if btn.button_pressed else "vanilla"
	audio.play_profile_cue(_selected_preset, "cast")
	_refresh_lock()

func _refresh_lock() -> void:
	lock_button.disabled = _selected_skill.is_empty() or _selected_trophy.is_empty()
	if _selected_skill.is_empty():
		summary.text = "Choose one rite from her pool to complete the binding."
		return
	summary.text = "%s replaces %s · %d/%ds CD · %s palette · SFX %s" % [
		str(_selected_skill.get("name", "")),
		str(Bestiary.boss_def(BOSS_ID).get("default_skill_label", "")),
		1, int(_selected_skill.get("cooldown", 12)),
		str(_selected_trophy.get("name", "")),
		PRESET_LABELS.get(_selected_preset, "VANILLA"),
	]

func _on_lock_pressed() -> void:
	if _selected_skill.is_empty() or _selected_trophy.is_empty():
		return
	if not game_state.consume_scan():
		status_label.text = "No lens charges remain — the default wakes."
		_resolve(false)
		return
	game_state.set_boss_custom(BOSS_ID, {
		"boss_id": BOSS_ID,
		"skill": _selected_skill,
		"sfx_preset": _selected_preset,
		"palette": _palette.map(func(c): return c.to_html(true)),
	})
	audio.play_victory()
	_resolve(true)

func _resolve(customized: bool) -> void:
	if _resolved:
		return
	_resolved = true
	resolved.emit(customized)

func _exit_tree() -> void:
	if not _resolved:
		_resolved = true
		var gs := get_node_or_null("/root/GameState")
		if gs != null and gs.has_method("pop_world_freeze"):
			gs.call("pop_world_freeze")
