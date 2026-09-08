extends CanvasLayer
class_name StatsScreen

## === Embersona — Stat Allocation ===
## Snapshot → preview allocations → confirm applies to GameState.
## Diamonds never appear here; this is earned power only.

const STAT_ROWS := [
	{"key": "str", "tag": "STR", "label": "Strength", "effect": "+1 attack damage"},
	{"key": "dex", "tag": "DEX", "label": "Dexterity", "effect": "+3% atk speed · +2% move"},
	{"key": "vit", "tag": "VIT", "label": "Vitality", "effect": "+3 max HP, heals it too"},
	{"key": "luk", "tag": "LUK", "label": "Luck", "effect": "+1% crit chance · +2% crit dmg"},
	{"key": "end", "tag": "END", "label": "Endurance", "effect": "+1 defense"},
]

var _pending := {}          # key -> points spent in this session
var _snapshot := {}         # stats when opened
var _points_at_open := 0
var _preset_status: Label
var _comparison_status: Label
var _loadout_status: Label

@onready var game_state: GameState = GameState
@onready var audio: AudioManager = AudioManager
@onready var header_label: Label = $Root/Center/Panel/VBox/Header
@onready var points_label: Label = $Root/Center/Panel/VBox/PointsLabel
@onready var rows_grid: GridContainer = $Root/Center/Panel/VBox/Rows
@onready var hp_label: Label = $Root/Center/Panel/VBox/Currencies
@onready var cap_note: Label = $Root/Center/Panel/VBox/SoftCapNote
@onready var confirm_button: Button = $Root/Center/Panel/VBox/Footer/Confirm
@onready var reset_button: Button = $Root/Center/Panel/VBox/Footer/Reset
@onready var close_button: Button = $Root/Center/Panel/VBox/Footer/Close

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS  # stay interactive while the world is frozen
	_freeze_was_visible = visible
	UiKit.apply_parchment($Root/Center/Panel)
	UiKit.style_primary_button(confirm_button)
	UiKit.style_secondary_button(reset_button)
	UiKit.style_secondary_button(close_button)
	_build_preset_preview()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	confirm_button.pressed.connect(_on_confirm)
	reset_button.pressed.connect(_on_reset)
	close_button.pressed.connect(close)
	game_state.level_up.connect(_on_level_up_refresh)

func _apply_responsive_layout() -> void:
	var metrics := UiKit.responsive_metrics(get_viewport().get_visible_rect().size)
	var panel := $Root/Center/Panel as Control
	var compact := bool(metrics.get("compact", false))
	panel.custom_minimum_size = Vector2(
		minf(740.0, maxf(320.0, get_viewport().get_visible_rect().size.x - 56.0)),
		560.0)
	rows_grid.columns = 2 if compact else 4

func open() -> void:
	_snapshot = {
		"str": game_state.stat_str, "dex": game_state.stat_dex,
		"vit": game_state.stat_vit, "luk": game_state.stat_luk,
		"end": game_state.stat_end,
	}
	_points_at_open = game_state.stat_points
	_pending.clear()
	visible = true
	_refresh()

func _build_preset_preview() -> void:
	var section := VBoxContainer.new()
	section.name = "BuildPresetPreview"
	var title := Label.new()
	title.text = "BUILD GUIDE  ·  PREVIEW ONLY"
	UiKit.style_label(title, &"Eyebrow", 13)
	section.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	section.add_child(row)
	for preset_id in ["vanguard", "skirmisher", "warden", "arcanist"]:
		var preset: Dictionary = game_state.stat_preset(preset_id)
		var button := Button.new()
		button.text = str(preset.get("label", preset_id.to_upper()))
		button.custom_minimum_size = Vector2(112, 42)
		button.tooltip_text = "%s · %s" % [str(preset.get("focus", "")),
			str(preset.get("summary", ""))]
		UiKit.style_secondary_button(button)
		button.pressed.connect(_on_preset_preview.bind(preset_id))
		row.add_child(button)
	_preset_status = Label.new()
	_preset_status.text = "Choose a guide to preview its focus; your stats will not change."
	_preset_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(_preset_status, &"Caption", 12)
	section.add_child(_preset_status)
	_comparison_status = Label.new()
	_comparison_status.name = "BuildComparison"
	_comparison_status.text = "CURRENT  —  choose a guide to compare projected stats."
	_comparison_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(_comparison_status, &"Caption", 12)
	section.add_child(_comparison_status)
	_loadout_status = Label.new()
	_loadout_status.text = "LOADOUT PRESETS · Save the equipped weapon and armor by slot."
	_loadout_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(_loadout_status, &"Caption", 12)
	section.add_child(_loadout_status)
	for slot in GameState.MAX_LOADOUT_PRESETS:
		var loadout_row := HBoxContainer.new()
		loadout_row.name = "LoadoutSlot_%d" % slot
		var slot_label := Label.new()
		slot_label.text = "SLOT %d  ·  %s" % [slot + 1, _loadout_summary(slot)]
		slot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		loadout_row.add_child(slot_label)
		var save_button := Button.new()
		save_button.text = "SAVE"
		UiKit.style_secondary_button(save_button)
		save_button.pressed.connect(_save_loadout.bind(slot, slot_label))
		loadout_row.add_child(save_button)
		var apply_button := Button.new()
		apply_button.text = "APPLY"
		UiKit.style_secondary_button(apply_button)
		apply_button.disabled = not game_state.loadout_presets.has(str(slot))
		apply_button.pressed.connect(_apply_loadout.bind(slot))
		loadout_row.add_child(apply_button)
		section.add_child(loadout_row)
	$Root/Center/Panel/VBox.add_child(section)

func _loadout_summary(slot: int) -> String:
	var preset: Dictionary = game_state.loadout_presets.get(str(slot), {})
	if preset.is_empty():
		return "EMPTY"
	return "%s / %s" % [str(preset.get("weapon_id", "-")), str(preset.get("armor_id", "-"))]

func _save_loadout(slot: int, slot_label: Label) -> void:
	if not game_state.save_loadout_preset(slot):
		_loadout_status.text = "SAVE FAILED · Equip a weapon before saving a loadout."
		return
	slot_label.text = "SLOT %d  ·  %s" % [slot + 1, _loadout_summary(slot)]
	_loadout_status.text = "SUCCESS · Loadout slot %d saved." % (slot + 1)

func _apply_loadout(slot: int) -> void:
	if game_state.apply_loadout_preset(slot):
		_loadout_status.text = "SUCCESS · Loadout slot %d equipped." % (slot + 1)
	else:
		_loadout_status.text = "FAILED · That loadout is unavailable."

func _on_preset_preview(preset_id: String) -> void:
	var preset: Dictionary = game_state.stat_preset(preset_id)
	if _preset_status == null or preset.is_empty():
		return
	_preset_status.text = "PREVIEW · %s  ·  %s\n%s" % [
		str(preset.get("label", "")), str(preset.get("focus", "")),
		str(preset.get("summary", ""))]
	var projection := game_state.project_stat_preset(preset_id, game_state.stat_points)
	_preset_status.text += "\nNEXT %d POINTS → %s" % [game_state.stat_points, str(projection)]
	if _comparison_status != null:
		_comparison_status.text = "CURRENT  STR %d · DEX %d · VIT %d · LUK %d · END %d\nPREVIEW  %s" % [
			game_state.stat_str, game_state.stat_dex, game_state.stat_vit,
			game_state.stat_luk, game_state.stat_end, str(projection)]

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

func close() -> void:
	if not _pending.is_empty():
		_on_reset()
	visible = false
	audio.play_ui_cancel()

func _spent(key: String) -> int:
	return int(_pending.get(key, 0))

func _base_value(key: String) -> int:
	return int(_snapshot.get(key, 0))

func _refresh() -> void:
	header_label.text = "EMBERSONA — LV %02d %s" % [game_state.level,
		str(game_state.player_class)]
	points_label.text = "Unspent stat points: %d" % (game_state.stat_points)
	hp_label.text = "HP %d/%d · GOLD %d · DIAMONDS %d" % [game_state.hp,
		game_state.max_hp, game_state.gold, game_state.diamonds]
	cap_note.text = "FIRST 20 POINTS: FULL VALUE  ·  AFTER 20: 50% EFFECTIVE VALUE"
	for child in rows_grid.get_children():
		child.queue_free()
	for row in STAT_ROWS:
		rows_grid.add_child(_tag(row.tag))
		var cur := _base_value(row.key) as int
		var pend := _spent(row.key)
		rows_grid.add_child(_label("%s (%s)" % [row.label, row.effect],
			Color(0.56, 0.67, 0.45)))
		rows_grid.add_child(_value_label(cur, cur + pend))
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(64, 48)
		btn.text = "+"
		UiKit.style_secondary_button(btn)
		btn.disabled = game_state.stat_points - _pending_total() <= 0
		btn.pressed.connect(_on_add.bind(row.key))
		rows_grid.add_child(btn)
	confirm_button.disabled = _pending.is_empty()
	reset_button.disabled = _pending.is_empty()

func _tag(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", load("res://assets/fonts/PressStart2P-Regular.ttf"))
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", UiKit.EMBER)
	return l

func _label(txt: String, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.style_label(l, &"Caption", 15)
	l.add_theme_color_override("font_color", col)
	return l

func _value_label(base: int, total: int) -> Label:
	var changed := total != base
	var l := _label("%d%s" % [total, "" if not changed else "  ( +%d )" % (total - base)],
		Color(0.5, 1.0, 0.55) if changed else Color(0.9, 0.9, 0.85))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l

func _pending_total() -> int:
	var n := 0
	for k in _pending:
		n += int(_pending[k])
	return n

## Points stay in the wallet during preview; Confirm commits them.
func _on_add(key: String) -> void:
	if game_state.stat_points - _pending_total() <= 0:
		return
	_pending[key] = _spent(key) + 1
	audio.play_ui_blip()
	_refresh()

func _on_level_up_refresh(_new_level: int, _points: int) -> void:
	if visible:
		_refresh()

func _on_confirm() -> void:
	for key in _pending:
		for i in int(_pending[key]):
			game_state.allocate_stat(key)
	_pending.clear()
	audio.play_forge_success()
	_refresh()

func _on_reset() -> void:
	game_state.stat_points = _points_at_open
	_pending.clear()
	game_state.stats_changed.emit()
	audio.play_ui_back()
	_refresh()
