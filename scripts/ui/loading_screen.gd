extends CanvasLayer
class_name LoadingScreen

## Realm-transition overlay: a bottom progress bar plus rotating tips, drawn
## above the scene that is being replaced.
##
## Built in code so the loader can create it without a scene dependency. It runs
## PROCESS_MODE_ALWAYS so the bar and the tips keep animating while a menu holds
## the world frozen, and every recurring effect here has a stop path: the tip
## timer stops on finish, the tip tween is killed before a new one starts, and
## finish() frees the layer even if its fade tween is cut short.

const KIT := preload("res://scripts/ui/ui_kit.gd")
const TIPS := preload("res://scripts/systems/loading_tips_catalog.gd")

const TIP_INTERVAL_SECONDS := 3.4
const TIP_FADE_SECONDS := 0.45
const FINISH_FADE_SECONDS := 0.35
const HARD_FREE_SECONDS := 1.5
const BAR_HEIGHT := 14.0

var _realm_id: String = ""
var _tip_index: int = 0
var _last_progress: float = 0.0
var _finished: bool = false

var _root: Control
var _backdrop: ColorRect
var _title_label: Label
var _status_label: Label
var _bar: ProgressBar
var _percent_label: Label
var _tip_panel: PanelContainer
var _tip_label: Label
var _tip_timer: Timer
var _hard_free_timer: Timer
var _tip_tween: Tween
var _finish_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_build()

func begin(title: String, realm_id: String = "") -> void:
	_realm_id = realm_id.strip_edges().to_lower()
	_title_label.text = title if not title.is_empty() else "Traveling"
	_status_label.text = "Preparing…"
	_bar.value = 0.0
	_percent_label.text = "0%"
	_last_progress = 0.0
	_show_tip(0)
	if _tip_timer != null:
		_tip_timer.start()

func set_progress(ratio: float) -> void:
	var clamped := clampf(ratio, 0.0, 1.0)
	if clamped < _last_progress:
		return
	_last_progress = clamped
	_bar.value = clamped
	_percent_label.text = "%d%%" % int(round(clamped * 100.0))

func progress() -> float:
	return _last_progress

func set_status(text: String) -> void:
	_status_label.text = text

func current_tip() -> String:
	return _tip_label.text

func tip_count() -> int:
	return TIPS.tips_for(_realm_id).size()

func finish() -> void:
	if _finished:
		return
	_finished = true
	if _tip_timer != null:
		_tip_timer.stop()
	_kill_tip_tween()
	if _finish_tween != null and _finish_tween.is_valid():
		_finish_tween.kill()
	_finish_tween = create_tween().set_parallel()
	# A CanvasLayer has no modulate, so fade every canvas child (backdrop,
	# labels, logo) in parallel; fading the layer itself used to raise a
	# "modulate does not exist" error and leave the screen opaque.
	for child in get_children():
		if child is CanvasItem:
			_finish_tween.tween_property(child, "modulate:a", 0.0, FINISH_FADE_SECONDS)
	_finish_tween.chain().tween_callback(queue_free)
	# Hard cap: the fade must never be the only way this layer leaves the tree.
	# The timer is a child node, so it dies with the layer instead of outliving it.
	if _hard_free_timer != null:
		_hard_free_timer.start()

func _hard_free() -> void:
	if is_inside_tree():
		queue_free()

func _exit_tree() -> void:
	if _tip_timer != null:
		_tip_timer.stop()
	if _hard_free_timer != null:
		_hard_free_timer.stop()
	_kill_tip_tween()

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = Color(KIT.BG_DEEP, 1.0)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_backdrop)

	var margin := MarginContainer.new()
	margin.name = "Bottom"
	margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# A bottom-anchored column folds the safe area into its own margins: writing
	# raw offsets here (as apply_safe_area does for full-rect panels) would move
	# the top edge off the anchor it grows from.
	var insets := KIT.safe_area_insets(get_viewport().get_visible_rect().size)
	margin.add_theme_constant_override("margin_left", 24 + int(insets["left"]))
	margin.add_theme_constant_override("margin_right", 24 + int(insets["right"]))
	margin.add_theme_constant_override("margin_bottom", 28 + int(insets["bottom"]))
	_root.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", int(KIT.theme_tokens()["typography"]["heading"]))
	_title_label.add_theme_color_override("font_color", KIT.EMBER_BRIGHT)
	header.add_child(_title_label)

	_percent_label = Label.new()
	_percent_label.name = "Percent"
	_percent_label.add_theme_font_size_override("font_size", int(KIT.theme_tokens()["typography"]["caption"]))
	_percent_label.add_theme_color_override("font_color", KIT.CREAM_DIM)
	header.add_child(_percent_label)

	_bar = ProgressBar.new()
	_bar.name = "Bar"
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.001
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0.0, BAR_HEIGHT)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.add_theme_stylebox_override("background", KIT.glass_stylebox(false, 0.35))
	_bar.add_theme_stylebox_override("fill", _bar_fill_style())
	column.add_child(_bar)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.add_theme_font_size_override("font_size", int(KIT.theme_tokens()["typography"]["caption"]))
	_status_label.add_theme_color_override("font_color", KIT.SAGE_DIM)
	column.add_child(_status_label)

	_build_tip_panel()

	_tip_timer = Timer.new()
	_tip_timer.name = "TipTimer"
	_tip_timer.wait_time = TIP_INTERVAL_SECONDS
	_tip_timer.one_shot = false
	_tip_timer.timeout.connect(_advance_tip)
	add_child(_tip_timer)

	_hard_free_timer = Timer.new()
	_hard_free_timer.name = "HardFreeTimer"
	_hard_free_timer.wait_time = HARD_FREE_SECONDS
	_hard_free_timer.one_shot = true
	_hard_free_timer.timeout.connect(_hard_free)
	add_child(_hard_free_timer)

func _bar_fill_style() -> StyleBoxFlat:
	var fill := StyleBoxFlat.new()
	fill.bg_color = KIT.EMBER
	fill.border_color = KIT.EMBER_BRIGHT
	fill.set_border_width_all(1)
	fill.set_corner_radius_all(int(BAR_HEIGHT * 0.5))
	return fill

## The tip lives in the middle of the screen so the wait teaches something
## without crowding the progress readout at the bottom.
func _build_tip_panel() -> void:
	var center := MarginContainer.new()
	center.name = "TipCenter"
	# Full width, vertically centred: a PRESET_CENTER container has no width of
	# its own, which would collapse an autowrapping label to one character.
	center.anchor_left = 0.0
	center.anchor_right = 1.0
	center.anchor_top = 0.5
	center.anchor_bottom = 0.5
	center.offset_left = 0.0
	center.offset_right = 0.0
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	var viewport_width := get_viewport().get_visible_rect().size.x
	var side_margin := int(clampf(viewport_width * 0.08, 20.0, 160.0))
	center.add_theme_constant_override("margin_left", side_margin)
	center.add_theme_constant_override("margin_right", side_margin)
	_root.add_child(center)

	_tip_panel = PanelContainer.new()
	_tip_panel.name = "TipPanel"
	_tip_panel.custom_minimum_size = Vector2(0.0, 96.0)
	_tip_panel.add_theme_stylebox_override("panel", KIT.glass_stylebox(true, 0.5))
	center.add_child(_tip_panel)

	var tip_margin := MarginContainer.new()
	tip_margin.add_theme_constant_override("margin_left", 20)
	tip_margin.add_theme_constant_override("margin_right", 20)
	tip_margin.add_theme_constant_override("margin_top", 16)
	tip_margin.add_theme_constant_override("margin_bottom", 16)
	_tip_panel.add_child(tip_margin)

	_tip_label = Label.new()
	_tip_label.name = "Tip"
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tip_label.add_theme_font_size_override("font_size", int(KIT.theme_tokens()["typography"]["body"]))
	_tip_label.add_theme_color_override("font_color", KIT.CREAM)
	tip_margin.add_child(_tip_label)

func _show_tip(index: int) -> void:
	_tip_index = index
	_tip_label.text = TIPS.tip_at(_realm_id, _tip_index)
	_tip_label.modulate.a = 1.0

func _advance_tip() -> void:
	if _finished or tip_count() == 0:
		return
	_kill_tip_tween()
	_tip_tween = create_tween()
	_tip_tween.tween_property(_tip_label, "modulate:a", 0.0, TIP_FADE_SECONDS)
	_tip_tween.tween_callback(_show_tip.bind(_tip_index + 1))
	_tip_tween.tween_property(_tip_label, "modulate:a", 1.0, TIP_FADE_SECONDS)

func _kill_tip_tween() -> void:
	if _tip_tween != null and _tip_tween.is_valid():
		_tip_tween.kill()
	_tip_tween = null
