extends VBoxContainer
class_name StatsPanel

## Shared stat allocation component used by the Satchel and StatsScreen.
## Points are previewed locally and committed through one GameState transaction.

signal close_requested
signal stats_committed(summary: Dictionary)

const STAT_ROWS: Array[Dictionary] = [
	{"key": "str", "tag": "STR", "label": "Strength", "effect": "+1 attack damage"},
	{"key": "dex", "tag": "DEX", "label": "Dexterity", "effect": "+3% attack speed · +2% move"},
	{"key": "vit", "tag": "VIT", "label": "Vitality", "effect": "+3 max HP"},
	{"key": "luk", "tag": "LUK", "label": "Luck", "effect": "+1% crit chance · +2% crit dmg"},
	{"key": "end", "tag": "END", "label": "Endurance", "effect": "+1 defense"},
]

var game_state: Node
var _pending: Dictionary = {}
var _snapshot: Dictionary = {}
var _points_at_open := 0
var _points_label: Label
var _rows_grid: GridContainer
var _derived_grid: GridContainer
var _status_label: Label
var _confirm_button: Button
var _reset_button: Button

func _ready() -> void:
	game_state = get_node("/root/GameState")
	process_mode = Node.PROCESS_MODE_ALWAYS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_ui()
	game_state.stats_changed.connect(_on_stats_changed)
	game_state.level_up.connect(_on_level_up)
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()

func _build_ui() -> void:
	add_theme_constant_override("separation", 10)
	_points_label = Label.new()
	_points_label.name = "PointsLabel"
	UiKit.style_label(_points_label, &"Subtitle", 24)
	add_child(_points_label)

	_rows_grid = GridContainer.new()
	_rows_grid.name = "Rows"
	_rows_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_grid.add_theme_constant_override("h_separation", 10)
	_rows_grid.add_theme_constant_override("v_separation", 8)
	add_child(_rows_grid)

	var derived_title := Label.new()
	derived_title.name = "DerivedTitle"
	derived_title.text = "DERIVED POWER"
	UiKit.style_label(derived_title, &"Eyebrow", 20)
	add_child(derived_title)
	_derived_grid = GridContainer.new()
	_derived_grid.name = "Derived"
	_derived_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_derived_grid.add_theme_constant_override("h_separation", 10)
	_derived_grid.add_theme_constant_override("v_separation", 8)
	add_child(_derived_grid)

	var cap_note := Label.new()
	cap_note.name = "SoftCapNote"
	cap_note.text = "FIRST 20 POINTS: FULL VALUE · AFTER 20: 50% EFFECTIVE VALUE"
	cap_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(cap_note, &"Caption", 18)
	add_child(cap_note)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.style_label(_status_label, &"Caption", 18)
	add_child(_status_label)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 8)
	add_child(footer)
	_confirm_button = Button.new()
	_confirm_button.name = "Confirm"
	_confirm_button.text = "CONFIRM"
	_confirm_button.custom_minimum_size = Vector2(0, UiKit.TOUCH_TARGET_MIN)
	UiKit.style_primary_button(_confirm_button)
	_confirm_button.pressed.connect(commit_preview)
	footer.add_child(_confirm_button)
	_reset_button = Button.new()
	_reset_button.name = "Reset"
	_reset_button.text = "RESET"
	_reset_button.custom_minimum_size = Vector2(0, UiKit.TOUCH_TARGET_MIN)
	UiKit.style_secondary_button(_reset_button)
	_reset_button.pressed.connect(cancel_preview)
	footer.add_child(_reset_button)

func _apply_responsive_layout() -> void:
	if _rows_grid == null:
		return
	var compact := get_viewport().get_visible_rect().size.x < UiKit.COMPACT_BREAKPOINT
	_rows_grid.columns = 1 if compact else 2
	_derived_grid.columns = 2 if compact else 3
	_refresh()

func open() -> void:
	_snapshot = _current_stats()
	_points_at_open = game_state.stat_points
	_pending.clear()
	_status_label.text = ""
	_refresh()

func cancel_preview() -> void:
	_pending.clear()
	_status_label.text = "Preview reset. No stats were changed."
	_refresh()

func commit_preview() -> void:
	if _pending.is_empty():
		return
	var summary: Dictionary = game_state.call("commit_stat_allocation", _pending)
	if not bool(summary.get("success", false)):
		_status_label.text = str(summary.get("message", "Stat allocation failed."))
		_refresh()
		return
	_pending.clear()
	_snapshot = _current_stats()
	_points_at_open = game_state.stat_points
	_status_label.text = "Stats committed. %d points remain." % game_state.stat_points
	stats_committed.emit(summary)
	_refresh()

func _current_stats() -> Dictionary:
	return {
		"str": game_state.stat_str, "dex": game_state.stat_dex,
		"vit": game_state.stat_vit, "luk": game_state.stat_luk,
		"end": game_state.stat_end,
	}

func _base_value(key: String) -> int:
	return int(_snapshot.get(key, game_state.get("stat_%s" % key)))

func _spent(key: String) -> int:
	return int(_pending.get(key, 0))

func _pending_total() -> int:
	var total := 0
	for value in _pending.values():
		total += int(value)
	return total

func _refresh() -> void:
	if _rows_grid == null:
		return
	_points_label.text = "UNSPENT POINTS  %d  ·  PREVIEWED  %d" % [
		maxi(0, game_state.stat_points - _pending_total()), _pending_total()]
	for child in _rows_grid.get_children():
		child.queue_free()
	for row in STAT_ROWS:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(0, 70)
		card.add_theme_stylebox_override("panel", UiKit.item_card_stylebox(UiKit.SAGE_DIM))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		card.add_child(line)
		var tag := Label.new()
		tag.text = str(row.get("tag", "STAT"))
		tag.custom_minimum_size = Vector2(54, 0)
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UiKit.style_label(tag, &"Eyebrow", 20)
		tag.add_theme_color_override("font_color", UiKit.EMBER)
		line.add_child(tag)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(info)
		var title := Label.new()
		title.text = str(row.get("label", "Stat"))
		UiKit.style_label(title, &"RowLabel", 22)
		info.add_child(title)
		var effect := Label.new()
		effect.text = str(row.get("effect", ""))
		UiKit.style_label(effect, &"Caption", 18)
		info.add_child(effect)
		var value := Label.new()
		var base := _base_value(str(row.get("key", "")))
		var total := base + _spent(str(row.get("key", "")))
		value.text = "%d%s" % [total, "  (+%d)" % (total - base) if total != base else ""]
		value.custom_minimum_size = Vector2(76, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UiKit.style_label(value, &"RowLabel", 22)
		value.add_theme_color_override("font_color", UiKit.SAGE_BRIGHT if total != base else UiKit.CREAM)
		line.add_child(value)
		var add := Button.new()
		add.text = "+"
		add.custom_minimum_size = Vector2(UiKit.TOUCH_TARGET_MIN, UiKit.TOUCH_TARGET_MIN)
		add.tooltip_text = "Preview one %s point" % str(row.get("label", "stat"))
		add.disabled = game_state.stat_points - _pending_total() <= 0
		UiKit.style_secondary_button(add)
		add.pressed.connect(_on_add.bind(str(row.get("key", ""))))
		line.add_child(add)
		_rows_grid.add_child(card)

	for child in _derived_grid.get_children():
		child.queue_free()
	var derived := _preview_derived_values()
	for entry in derived:
		var label := Label.new()
		label.text = "%s\n%s" % [str(entry[0]), str(entry[1])]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiKit.style_label(label, &"Caption", 18)
		label.add_theme_color_override("font_color", entry[2])
		_derived_grid.add_child(label)
	_confirm_button.disabled = _pending.is_empty()
	_reset_button.disabled = _pending.is_empty()

func _preview_derived_values() -> Array:
	var str_total := _base_value("str") + _spent("str")
	var dex_total := _base_value("dex") + _spent("dex")
	var vit_total := _base_value("vit") + _spent("vit")
	var luk_total := _base_value("luk") + _spent("luk")
	var end_total := _base_value("end") + _spent("end")
	var attack: int = int(game_state.call("get_base_auto_damage")) + _spent("str")
	var defense: int = int(game_state.call("armor_defense")) + int(round(float(game_state.call("soft_cap_points", end_total))))
	var speed: float = (1.0 + 0.03 * float(game_state.call("soft_cap_points", dex_total))) * float(game_state.call("armor_speed_mult"))
	var crit: float = clampf(0.05 + 0.01 * float(game_state.call("soft_cap_points", luk_total)), 0.0, 0.75)
	var crit_mult: float = 1.5 + 0.02 * float(game_state.call("soft_cap_points", luk_total))
	var current_vit := _base_value("vit")
	var hp: int = int(game_state.call("max_hp_total")) + int(round(3.0 * (float(game_state.call("soft_cap_points", vit_total)) - float(game_state.call("soft_cap_points", current_vit)))))
	return [
		["ATTACK", str(attack), Color(1.0, 0.66, 0.30)],
		["DEFENSE", str(defense), Color(0.42, 0.82, 0.98)],
		["HP", str(hp), Color(0.98, 0.42, 0.42)],
		["ATTACK SPEED", "×%.2f" % speed, Color(0.48, 1.0, 0.62)],
		["CRIT CHANCE", "%d%%" % roundi(crit * 100.0), Color(1.0, 0.82, 0.34)],
		["CRIT MULT", "×%.2f" % crit_mult, Color(0.92, 0.48, 1.0)],
	]

func _on_add(key: String) -> void:
	if game_state.stat_points - _pending_total() <= 0:
		return
	_pending[key] = _spent(key) + 1
	var audio := get_tree().root.get_node_or_null("AudioManager")
	if audio != null and audio.has_method("play_ui_blip"):
		audio.call("play_ui_blip")
	_refresh()

func _on_stats_changed() -> void:
	if _pending.is_empty():
		_snapshot = _current_stats()
	_refresh()

func _on_level_up(_new_level: int, _points: int) -> void:
	_refresh()
