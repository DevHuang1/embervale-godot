extends Control
class_name MiniMap

## === Realm Mini-Map ===
## Custom-drawn top-left map: realm-tinted field, discovered landmarks,
## pulsing player dot. Tap to expand/collapse. Never shows enemies —
## discovery stays the point.

signal minimap_toggled(expanded: bool)

const SMALL := 148.0
const BIG := 264.0
const POLL_INTERVAL := 0.15

var expanded := false
var markers: Array[Dictionary] = []   # {pos: Vector3 world, glyph: String}
var realm_name := "Whispergrove"
var _poll := 0.0
var _pulse_t := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(SMALL, SMALL + 22)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Tap to expand the realm map"

func set_realm(id: String) -> void:
	var def: Dictionary = Bestiary.WORLD_REALMS.get(id, {})
	realm_name = str(def.get("name", "Bramblewood"))
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_toggle()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		_toggle()
		accept_event()

func _toggle() -> void:
	expanded = not expanded
	var side := BIG if expanded else SMALL
	custom_minimum_size = Vector2(side, side + 22)
	minimap_toggled.emit(expanded)
	audio_blip()
	queue_redraw()

func audio_blip() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am:
		am.play_ui_blip()

func _process(delta: float) -> void:
	_pulse_t += delta
	_poll -= delta
	if _poll <= 0.0:
		_poll = POLL_INTERVAL
		queue_redraw()

func _bounds() -> Rect2:
	var gs := get_node_or_null("/root/GameState")
	var id: String = gs.current_realm if gs else "bramblewood"
	var def: Dictionary = Bestiary.WORLD_REALMS.get(id, {})
	return def.get("bounds", Rect2(-46, -34, 92, 68))

func _map_color() -> Color:
	var gs := get_node_or_null("/root/GameState")
	var id: String = gs.current_realm if gs else "bramblewood"
	var def: Dictionary = Bestiary.WORLD_REALMS.get(id, {})
	return def.get("map_color", Color(0.14, 0.22, 0.18))

func _player_pos() -> Vector3:
	var gs := get_node_or_null("/root/GameState")
	return Vector3(gs.player_position.x, 0, gs.player_position.y) if gs \
		else Vector3.ZERO

func _project(world_xz: Vector3, center: Vector2, radius: float) -> Vector2:
	var b := _bounds()
	var u := clampf((world_xz.x - b.position.x) / b.size.x, 0.0, 1.0)
	var v := clampf((world_xz.y - b.position.y) / b.size.y, 0.0, 1.0)
	return center + Vector2(u * 2.0 - 1.0, v * 2.0 - 1.0) * radius

func _draw() -> void:
	var side := minf(size.x, size.y - 22.0)
	var center := Vector2(size.x * 0.5, side * 0.5)
	var radius := side * 0.5 - 4.0

	# Backing disc + realm field
	draw_circle(center, radius + 3.0, Color(0.03, 0.05, 0.05, 0.85))
	draw_circle(center, radius, Color(_map_color().r, _map_color().g,
		_map_color().b, 0.72))
	var realm_def: Dictionary = Bestiary.REALMS.get(_realm_id(), {})
	var mist: Color = realm_def.get("mist_tint", Color(0.65, 0.75, 0.72))
	draw_arc(center, radius, 0.0, TAU, 56, Color(mist.r, mist.g, mist.b, 0.9), 2.5, true)

	# Landmarks
	for m in markers:
		var p := _project(m.pos, center, radius * 0.94)
		draw_string(get_theme_default_font(), p + Vector2(-7, 6),
			str(m.glyph), HORIZONTAL_ALIGNMENT_CENTER, 16, 13)

	# Player dot: amber, gentle pulse
	var pp := _project(_player_pos(), center, radius * 0.94)
	var pulse := 3.4 + sin(_pulse_t * 3.2) * 1.1
	draw_circle(pp, pulse + 2.5, Color(1.0, 0.72, 0.29, 0.25))
	draw_circle(pp, pulse, Color(1.0, 0.84, 0.45, 1.0))

	draw_string(get_theme_default_font(),
		Vector2(size.x * 0.5 - 46.0, side + 16.0), realm_name.to_upper(),
		HORIZONTAL_ALIGNMENT_CENTER, 96, 10, Color(0.85, 0.90, 0.82))

func _realm_id() -> String:
	var gs := get_node_or_null("/root/GameState")
	return str(gs.current_realm) if gs else "bramblewood"
