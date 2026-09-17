extends CanvasLayer
class_name StatsScreen

## Compatibility wrapper for callers that open a dedicated stats overlay.
## Rendering and allocation live in the same StatsPanel used by SatchelUI.

@onready var game_state: Node = get_node("/root/GameState")
@onready var panel: Control = $Root/Center/Panel
@onready var title: Label = $Root/Center/Panel/Header/Title
@onready var close_button: Button = $Root/Center/Panel/Header/CloseButton
@onready var stats_panel: StatsPanel = $Root/Center/Panel/VBox/StatsPanel
var _freeze_was_visible := false
var _freeze_held := false

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.add_theme_stylebox_override("panel", UiKit.parchment_stylebox())
	UiKit.style_button(close_button, UiKit.SAGE)
	close_button.pressed.connect(close)
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()

func _process(_delta: float) -> void:
	if visible == _freeze_was_visible:
		return
	_freeze_was_visible = visible
	if visible:
		game_state.push_world_freeze()
		_freeze_held = true
	else:
		_release_world_freeze()

func _apply_responsive_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var compact := viewport_size.x < UiKit.COMPACT_BREAKPOINT
	panel.custom_minimum_size = Vector2(
		minf(740.0, maxf(320.0, viewport_size.x - 56.0)),
		minf(680.0, maxf(420.0, viewport_size.y - 56.0)))
	if compact:
		panel.custom_minimum_size.x = maxf(320.0, viewport_size.x - 56.0)

func open() -> void:
	title.text = "STATS · LV %02d" % game_state.level
	stats_panel.open()
	visible = true

func close() -> void:
	stats_panel.cancel_preview()
	visible = false

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
