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

@onready var game_state: GameState = GameState
@onready var audio: AudioManager = AudioManager
@onready var header_label: Label = $Root/Center/Panel/VBox/Header
@onready var points_label: Label = $Root/Center/Panel/VBox/PointsLabel
@onready var rows_grid: GridContainer = $Root/Center/Panel/VBox/Rows
@onready var hp_label: Label = $Root/Center/Panel/VBox/Currencies
@onready var confirm_button: Button = $Root/Center/Panel/VBox/Footer/Confirm
@onready var reset_button: Button = $Root/Center/Panel/VBox/Footer/Reset
@onready var close_button: Button = $Root/Center/Panel/VBox/Footer/Close

func _ready() -> void:
	visible = false
	confirm_button.pressed.connect(_on_confirm)
	reset_button.pressed.connect(_on_reset)
	close_button.pressed.connect(close)
	game_state.level_up.connect(_on_level_up_refresh)

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
	hp_label.text = "HP %d/%d · 🪙 %d · 💎 %d" % [game_state.hp,
		game_state.max_hp, game_state.gold, game_state.diamonds]
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
		btn.custom_minimum_size = Vector2(52, 34)
		btn.text = "+"
		btn.disabled = game_state.stat_points - _pending_total() <= 0
		btn.pressed.connect(_on_add.bind(row.key))
		rows_grid.add_child(btn)
	confirm_button.disabled = _pending.is_empty()
	reset_button.disabled = _pending.is_empty()

func _tag(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", load("res://assets/fonts/PressStart2P-Regular.ttf"))
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.96, 0.72, 0.29))
	return l

func _label(txt: String, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_override("font", load("res://assets/fonts/VT323-Regular.ttf"))
	l.add_theme_font_size_override("font_size", 15)
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
