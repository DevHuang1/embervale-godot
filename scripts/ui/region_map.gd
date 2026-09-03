extends Control
class_name RegionMap

## Full-screen region map with fog-of-war discovery.
## Shows realms, landmarks, dungeons, and gathering areas.

var _expanded := false
var _close_button: Button
var _map_container: Control
var _fog_layer: Control
var _realm_labels: Array[Label] = []

const REALM_DATA := {
	"bramblewood": {"name": "Bramblewood", "color": Color(0.30, 0.55, 0.35), "pos": Vector2(0.3, 0.5)},
	"mistfen": {"name": "Mistfen", "color": Color(0.45, 0.50, 0.55), "pos": Vector2(0.5, 0.35)},
	"heartwood": {"name": "Heartwood", "color": Color(0.65, 0.35, 0.18), "pos": Vector2(0.7, 0.5)},
	"moonfen": {"name": "Moonfen", "color": Color(0.35, 0.40, 0.65), "pos": Vector2(0.5, 0.65)},
}

const LANDMARK_DATA := {
	"watchtower": {"name": "Abandoned Watchtower", "realm": "bramblewood", "pos": Vector2(0.2, 0.45), "glyph": "T"},
	"shrine": {"name": "Collapsed Shrine", "realm": "bramblewood", "pos": Vector2(0.35, 0.55), "glyph": "S"},
	"moonwell": {"name": "Moonwell", "realm": "moonfen", "pos": Vector2(0.45, 0.7), "glyph": "M"},
	"root_bridge": {"name": "Root Bridge", "realm": "mistfen", "pos": Vector2(0.55, 0.3), "glyph": "R"},
	"vault": {"name": "Sealed Vault", "realm": "heartwood", "pos": Vector2(0.75, 0.45), "glyph": "V"},
	"camp": {"name": "Burned Camp", "realm": "mistfen", "pos": Vector2(0.6, 0.4), "glyph": "C"},
}

func _ready() -> void:
	visible = false
	_build_ui()

func _build_ui() -> void:
	# Background dim
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Map container
	_map_container = Control.new()
	_map_container.name = "MapContainer"
	_map_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_container.offset_left = 40
	_map_container.offset_right = -40
	_map_container.offset_top = 60
	_map_container.offset_bottom = -40
	add_child(_map_container)
	# Map background
	var map_bg := ColorRect.new()
	map_bg.color = Color(0.08, 0.10, 0.09)
	map_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_container.add_child(map_bg)
	# Title
	var title := Label.new()
	title.text = "REGION MAP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_bottom = 40
	title.add_theme_font_size_override("font_size", 20)
	_map_container.add_child(title)
	# Close button
	_close_button = Button.new()
	_close_button.text = "CLOSE"
	_close_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_close_button.offset_left = -100
	_close_button.offset_bottom = 36
	_close_button.pressed.connect(_on_close)
	_map_container.add_child(_close_button)
	# Draw realm dots and landmarks
	_draw_realms()
	_draw_landmarks()

func _draw_realms() -> void:
	for realm_id in REALM_DATA:
		var data: Dictionary = REALM_DATA[realm_id]
		var dot := ColorRect.new()
		dot.name = "Realm_%s" % realm_id
		dot.color = data.color
		dot.size = Vector2(24, 24)
		dot.position = data.pos * Vector2(800, 500) - Vector2(12, 12)
		_map_container.add_child(dot)
		var label := Label.new()
		label.text = data.name
		label.position = data.pos * Vector2(800, 500) + Vector2(16, -8)
		label.add_theme_font_size_override("font_size", 12)
		_map_container.add_child(label)
		_realm_labels.append(label)

func _draw_landmarks() -> void:
	for lm_id in LANDMARK_DATA:
		var data: Dictionary = LANDMARK_DATA[lm_id]
		var glyph := Label.new()
		glyph.name = "LM_%s" % lm_id
		glyph.text = data.glyph
		glyph.position = data.pos * Vector2(800, 500) - Vector2(6, 6)
		glyph.add_theme_font_size_override("font_size", 16)
		glyph.modulate = Color(1, 0.85, 0.3)
		glyph.visible = false
		_map_container.add_child(glyph)

func toggle() -> void:
	if visible:
		_on_close()
	else:
		_open()

func _open() -> void:
	visible = true
	_update_discoveries()
	get_tree().paused = true

func _on_close() -> void:
	visible = false
	get_tree().paused = false

func _update_discoveries() -> void:
	var discovered: Dictionary = GameState.get("discovered_landmarks") if GameState.has_method("get") else {}
	if not discovered is Dictionary:
		discovered = {}
	for lm_id in LANDMARK_DATA:
		var glyph = _map_container.get_node_or_null("LM_%s" % lm_id)
		if glyph != null:
			glyph.visible = discovered.get(lm_id, false)

func discover_landmark(landmark_id: String) -> void:
	var discovered: Dictionary = GameState.get("discovered_landmarks") if GameState.has_method("get") else {}
	if not discovered is Dictionary:
		discovered = {}
	if not discovered.has(landmark_id):
		discovered[landmark_id] = true
		GameState.set("discovered_landmarks", discovered) if GameState.has_method("set") else null
		FloatingText.spawn_on_entity(get_tree().get_first_node_in_group("player"),
			"Map updated: %s" % LANDMARK_DATA.get(landmark_id, {}).get("name", landmark_id),
			Color(0.9, 0.85, 0.3), 1.5)
