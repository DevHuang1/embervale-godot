extends Control
class_name MiniMap

## === Realm Mini-Map ===
## Custom-drawn top-left map: realm-tinted field, discovered landmarks,
## pulsing player dot. Tap to expand/collapse. Never shows enemies —
## discovery stays the point.

signal minimap_toggled(expanded: bool)

const SMALL := 148.0
const BIG := 264.0
const SMALL_LEGEND_HEIGHT := 18.0
const BIG_LEGEND_HEIGHT := 38.0
const POLL_INTERVAL := 0.15
const MAX_MARKERS := 64

var expanded := false
var markers: Array[Dictionary] = []   # {pos, kind, glyph, label, color}
var realm_name := "Whispergrove"
var _poll := 0.0
var _pulse_t := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(SMALL, SMALL + SMALL_LEGEND_HEIGHT)
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
	var legend_height := BIG_LEGEND_HEIGHT if expanded else SMALL_LEGEND_HEIGHT
	custom_minimum_size = Vector2(side, side + legend_height)
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
		_refresh_world_markers()
		queue_redraw()

func _refresh_world_markers() -> void:
	var next: Array[Dictionary] = []
	var seen: Dictionary = {}
	var append_marker := func(node: Node3D, kind: String, glyph: String, color: Color) -> void:
		if node == null or not is_instance_valid(node):
			return
		var key := "%s:%s" % [kind, node.get_instance_id()]
		if seen.has(key):
			return
		seen[key] = true
		next.append({"pos": node.global_position, "kind": kind, "glyph": glyph,
			"label": node.name, "color": color})
	for node_value in get_tree().get_nodes_in_group("interactable"):
		var node := node_value as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var kind := "structure"
		var glyph := "S"
		var color := Color(0.78, 0.74, 0.62)
		if node is ServiceNpc:
			kind = "craftsman" if node.service_kind == "forge" else "trader"
			glyph = "C" if kind == "craftsman" else "T"
			color = Color(0.45, 0.86, 0.66) if kind == "craftsman" else Color(1.0, 0.74, 0.29)
		elif node is RealmActivityBeacon:
			kind = "event"
			glyph = "E"
			color = Color(0.46, 0.82, 1.0)
		elif node is Landmark or node is ChestNode:
			kind = "structure"
			glyph = "S"
			color = Color(0.78, 0.74, 0.62)
		elif node.is_in_group("portal") or "portal" in node.name.to_lower() \
				or "gate" in node.name.to_lower():
			kind = "portal"
			glyph = "P"
			color = Color(0.82, 0.55, 1.0)
		append_marker.call(node, kind, glyph, color)
	for node_value in get_tree().get_nodes_in_group("structure"):
		append_marker.call(node_value as Node3D, "structure", "S", Color(0.78, 0.74, 0.62))
	for node_value in get_tree().get_nodes_in_group("portal"):
		append_marker.call(node_value as Node3D, "portal", "P", Color(0.82, 0.55, 1.0))
	for node_value in get_tree().get_nodes_in_group("event"):
		append_marker.call(node_value as Node3D, "event", "E", Color(0.46, 0.82, 1.0))
	for node_value in get_tree().get_nodes_in_group("task"):
		append_marker.call(node_value as Node3D, "task", "!", Color(1.0, 0.88, 0.38))
	for node_value in get_tree().get_nodes_in_group("quest_marker"):
		var node := node_value as Node3D
		if node != null and is_instance_valid(node):
			append_marker.call(node, "task", "!", Color(1.0, 0.88, 0.38))
	for node_value in get_tree().get_nodes_in_group("interactable"):
		var node := node_value as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var node_name := node.name.to_lower()
		if ("quest" in node_name or "objective" in node_name) and not node is ServiceNpc:
			append_marker.call(node, "task", "!", Color(1.0, 0.88, 0.38))
	# A few authored route landmarks predate the marker groups. Discover them
	# by stable scene naming so old realm scenes still expose their objectives.
	var current_scene := get_tree().current_scene
	if current_scene != null:
		for node_value in current_scene.find_children("*", "Node3D", true, false):
			var node := node_value as Node3D
			if node == null or not is_instance_valid(node):
				continue
			var route_name := node.name.to_lower()
			if not ("questboard" in route_name or "shardspawn" in route_name
					or "beaconspawn" in route_name or "gate" in route_name):
				continue
			var route_glyph := "!" if "quest" in route_name or "shard" in route_name \
				else ("E" if "beacon" in route_name else "P")
			var route_color := Color(1.0, 0.88, 0.38) if route_glyph == "!" \
				else (Color(0.46, 0.82, 1.0) if route_glyph == "E" else Color(0.82, 0.55, 1.0))
			append_marker.call(node, "route_%s" % route_glyph, route_glyph, route_color)
	next.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("label", a.get("glyph", ""))) < str(b.get("label", b.get("glyph", "")))
	)
	if next.size() > MAX_MARKERS:
		next.resize(MAX_MARKERS)
	markers = next

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
	var v := clampf((world_xz.z - b.position.y) / b.size.y, 0.0, 1.0)
	return center + Vector2(u * 2.0 - 1.0, v * 2.0 - 1.0) * radius

func _draw() -> void:
	var legend_height := BIG_LEGEND_HEIGHT if expanded else SMALL_LEGEND_HEIGHT
	var side := minf(size.x, size.y - legend_height)
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
		var marker_color: Color = m.get("color", Color.WHITE)
		draw_circle(p, 6.0, Color(0.02, 0.04, 0.04, 0.9))
		draw_circle(p, 4.0, marker_color)
		draw_string(get_theme_default_font(), p + Vector2(-4, -7),
			str(m.glyph), HORIZONTAL_ALIGNMENT_CENTER, 10, 10, marker_color)
		if expanded:
			var kind_label := str(m.get("kind", "site")).replace("_", " ").to_upper()
			var label := "%s · %s" % [kind_label,
				str(m.get("label", "")).replace("_", " ").to_upper()]
			if label.length() > 18:
				label = label.substr(0, 18) + "…"
			draw_string(get_theme_default_font(), p + Vector2(9, 4), label,
				HORIZONTAL_ALIGNMENT_LEFT, 122, 9, Color(0.95, 0.92, 0.84))

	# Player dot: amber, gentle pulse
	var pp := _project(_player_pos(), center, radius * 0.94)
	var pulse := 3.4 + sin(_pulse_t * 3.2) * 1.1
	draw_circle(pp, pulse + 2.5, Color(1.0, 0.72, 0.29, 0.25))
	draw_circle(pp, pulse, Color(1.0, 0.84, 0.45, 1.0))

	draw_string(get_theme_default_font(),
		Vector2(size.x * 0.5 - 46.0, side + 10.0), realm_name.to_upper(),
		HORIZONTAL_ALIGNMENT_CENTER, 96, 10, Color(0.85, 0.90, 0.82))
	if expanded:
		draw_string(get_theme_default_font(), Vector2(8.0, side + 22.0),
			"T TRADER   C CRAFT   S SITE   ! TASK", HORIZONTAL_ALIGNMENT_LEFT,
			size.x - 16.0, 9, Color(0.90, 0.86, 0.74))
		draw_string(get_theme_default_font(), Vector2(8.0, side + 35.0),
			"E EVENT   P PORTAL", HORIZONTAL_ALIGNMENT_LEFT, size.x - 16.0, 9,
			Color(0.90, 0.86, 0.74))
	else:
		draw_string(get_theme_default_font(), Vector2(4.0, side + 10.0),
			"T C S ! E P", HORIZONTAL_ALIGNMENT_CENTER, size.x - 8.0, 9,
			Color(0.90, 0.86, 0.74))

func _realm_id() -> String:
	var gs := get_node_or_null("/root/GameState")
	return str(gs.current_realm) if gs else "bramblewood"
