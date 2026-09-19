extends Control
class_name MiniMap

## === Realm Mini-Map ===
## Custom-drawn top-left map. The realm terrain is seamless, so the map is a
## player-centred window rather than a fixed world rectangle: realm-tinted
## field, authored route and water, heightfield relief shading, a discovery fog
## that only clears where the player has actually been, discovered landmarks,
## pulsing player dot. Guidance markers beyond the window clamp to the rim so
## objectives never vanish. Never shows enemies — discovery stays the point.
## Tap to expand/collapse.

signal minimap_toggled(expanded: bool)

const SMALL := 148.0
const BIG := 264.0
const SMALL_LEGEND_HEIGHT := 18.0
const BIG_LEGEND_HEIGHT := 38.0
const POLL_INTERVAL := 0.15
const MAX_MARKERS := 64
## Minimum drawn separation between two decorative markers on the disc, and
## between two expanded labels.
const MARKER_MIN_SPACING := 6.5
const LABEL_MIN_SPACING := 30.0
## Map window: world metres shown across the disc. The window follows the
## player, so route, water and relief stay legible anywhere in the seamless
## world instead of collapsing into a dot on a two-kilometre field.
const MAP_SPAN := 280.0
const MAP_PADDING := 0.94
## Discovery grid: world-anchored square cells. Fixed metre size keeps the
## reveal patch the same size in every realm; the lattice is bounded so saved
## cell indices stay small and lookup stays cheap.
const GRID_CELL_METERS := 12.0
const GRID_COLS := 256
const GRID_ROWS := 256
const FOG_REVEAL_CELLS := 2
## Hillshade response per metre of height difference between neighbouring
## lattice samples.
const RELIEF_SLOPE := 0.35
const HEIGHT_CACHE_LIMIT := 8192

## Marker priority for the MAX_MARKERS truncation. Quest-critical guidance must
## survive a crowded map: decorative landmarks are dropped first, never the
## objective, route, or portal markers.
const PRIORITY_QUEST := 0
const PRIORITY_ACTIVITY := 1
const PRIORITY_NPC := 2
const PRIORITY_STRUCTURE := 4

var expanded := false
var markers: Array[Dictionary] = []   # {pos, kind, glyph, label, color, priority}
var realm_name := "Whispergrove"
var _poll := 0.0
var _pulse_t := 0.0
var _explored: Dictionary = {}
var _explored_realm := ""
var _heights: Dictionary = {}
var _heights_realm := ""
var _relief_terrain: TerrainRelief = null

func _ready() -> void:
	_apply_box(SMALL, SMALL_LEGEND_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Tap to expand the realm map"

## The map owns its box: custom_minimum_size only enforces a floor, so the
## HUD-allocated rect has to be re-applied on both toggle directions.
func _apply_box(side: float, legend_height: float) -> void:
	custom_minimum_size = Vector2(side, side + legend_height)
	size = custom_minimum_size

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
	_apply_box(side, legend_height)
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
		_refresh_realm_label()
		_refresh_world_markers()
		_refresh_discovery()
		queue_redraw()

func _refresh_realm_label() -> void:
	var def: Dictionary = Bestiary.WORLD_REALMS.get(_realm_id(), {})
	realm_name = str(def.get("name", realm_name))

## Reveals the cells around the player and mirrors the persisted set. Cells are
## the only thing the map trusts for "you have been here"; markers inside
## unexplored cells stay hidden.
func _refresh_discovery() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	var realm := _realm_id()
	if _explored_realm != realm:
		_explored_realm = realm
		_explored.clear()
		for value in gs.call("explored_cells_for", realm):
			_explored[int(value)] = true
	var player_cell := _cell_of(_player_pos())
	for dy in range(-FOG_REVEAL_CELLS, FOG_REVEAL_CELLS + 1):
		for dx in range(-FOG_REVEAL_CELLS, FOG_REVEAL_CELLS + 1):
			var col := player_cell.x + dx
			var row := player_cell.y + dy
			if col < 0 or row < 0 or col >= GRID_COLS or row >= GRID_ROWS:
				continue
			var index := row * GRID_COLS + col
			if _explored.has(index):
				continue
			if bool(gs.call("mark_explored", realm, index)):
				_explored[index] = true

## World-anchored lattice origin, so a given world position always maps to the
## same saved cell regardless of where the window happens to be.
func _grid_origin() -> Vector2:
	return Vector2(-GRID_COLS, -GRID_ROWS) * GRID_CELL_METERS * 0.5

func _cell_of(world_xz: Vector3) -> Vector2i:
	var origin := _grid_origin()
	var col := int(floor((world_xz.x - origin.x) / GRID_CELL_METERS))
	var row := int(floor((world_xz.z - origin.y) / GRID_CELL_METERS))
	return Vector2i(clampi(col, 0, GRID_COLS - 1), clampi(row, 0, GRID_ROWS - 1))

func _cell_index_of_pos(pos: Vector3) -> int:
	var cell := _cell_of(pos)
	return cell.y * GRID_COLS + cell.x

func _marker_revealed(marker: Dictionary) -> bool:
	# Guidance (quest, activity, event, portal) always shows; decorative
	# landmarks and services must be found by exploring their cell first.
	if int(marker.get("priority", PRIORITY_STRUCTURE)) <= PRIORITY_ACTIVITY:
		return true
	return _explored.has(_cell_index_of_pos(marker.get("pos", Vector3.ZERO)))

func _refresh_world_markers() -> void:
	var next: Array[Dictionary] = []
	var seen: Dictionary = {}
	var append_marker := func(node: Node3D, kind: String, glyph: String, color: Color,
			priority: int = PRIORITY_STRUCTURE) -> void:
		if node == null or not is_instance_valid(node):
			return
		if node.is_in_group("activity_marker") and not node.visible:
			return
		var key := "%s:%s" % [kind, node.get_instance_id()]
		if seen.has(key):
			return
		seen[key] = true
		next.append({"pos": node.global_position, "kind": kind, "glyph": glyph,
			"label": node.name, "color": color, "priority": priority})
	for node_value in get_tree().get_nodes_in_group("interactable"):
		var node := node_value as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var kind := "structure"
		var glyph := "S"
		var color := Color(0.78, 0.74, 0.62)
		if node.is_in_group("activity_marker"):
			var activity: Dictionary = node.call("activity_contract") \
				if node.has_method("activity_contract") else {}
			var activity_type := str(activity.get("type", ""))
			kind = "activity"
			glyph = "A"
			color = Color(0.82, 0.66, 1.0)
			if activity_type in ["combat_patrol", "combat_ambush"]:
				glyph = "!"
				color = Color(1.0, 0.42, 0.20)
			elif activity_type == "gathering":
				glyph = "G"
				color = Color(0.42, 0.92, 0.58)
			elif activity_type == "beacon":
				glyph = "B"
				color = Color(0.42, 0.78, 1.0)
			elif activity_type == "cache":
				glyph = "$"
				color = Color(1.0, 0.76, 0.28)
		elif node is ServiceNpc:
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
		append_marker.call(node, kind, glyph, color, _marker_priority(kind, glyph))
	for node_value in get_tree().get_nodes_in_group("structure"):
		append_marker.call(node_value as Node3D, "structure", "S",
			Color(0.78, 0.74, 0.62), PRIORITY_STRUCTURE)
	for node_value in get_tree().get_nodes_in_group("portal"):
		append_marker.call(node_value as Node3D, "portal", "P",
			Color(0.82, 0.55, 1.0), PRIORITY_ACTIVITY)
	for node_value in get_tree().get_nodes_in_group("event"):
		append_marker.call(node_value as Node3D, "event", "E",
			Color(0.46, 0.82, 1.0), PRIORITY_ACTIVITY)
	for node_value in get_tree().get_nodes_in_group("activity"):
		append_marker.call(node_value as Node3D, "activity", "A",
			Color(0.82, 0.66, 1.0), PRIORITY_ACTIVITY)
	for node_value in get_tree().get_nodes_in_group("task"):
		append_marker.call(node_value as Node3D, "task", "!",
			Color(1.0, 0.88, 0.38), PRIORITY_QUEST)
	for node_value in get_tree().get_nodes_in_group("quest_marker"):
		var node := node_value as Node3D
		if node != null and is_instance_valid(node):
			append_marker.call(node, "task", "!", Color(1.0, 0.88, 0.38), PRIORITY_QUEST)
	for node_value in get_tree().get_nodes_in_group("interactable"):
		var node := node_value as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var node_name := node.name.to_lower()
		if ("quest" in node_name or "objective" in node_name) and not node is ServiceNpc:
			append_marker.call(node, "task", "!", Color(1.0, 0.88, 0.38), PRIORITY_QUEST)
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
			append_marker.call(node, "route_%s" % route_glyph, route_glyph, route_color, PRIORITY_QUEST)
	next.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var priority_a := int(a.get("priority", PRIORITY_STRUCTURE))
		var priority_b := int(b.get("priority", PRIORITY_STRUCTURE))
		if priority_a != priority_b:
			return priority_a < priority_b
		return str(a.get("label", a.get("glyph", ""))) < str(b.get("label", b.get("glyph", "")))
	)
	if next.size() > MAX_MARKERS:
		next.resize(MAX_MARKERS)
	markers = next

## Priority for a marker classified through the interactable loop.
func _marker_priority(kind: String, glyph: String) -> int:
	if kind.begins_with("route") or glyph == "!":
		return PRIORITY_QUEST
	if kind in ["activity", "event", "portal"]:
		return PRIORITY_ACTIVITY
	if kind in ["craftsman", "trader", "task"]:
		return PRIORITY_NPC
	return PRIORITY_STRUCTURE

func _map_color() -> Color:
	var def: Dictionary = Bestiary.WORLD_REALMS.get(_realm_id(), {})
	return def.get("map_color", Color(0.14, 0.22, 0.18))

func _player_pos() -> Vector3:
	var gs := get_node_or_null("/root/GameState")
	return Vector3(gs.player_position.x, 0, gs.player_position.y) if gs \
		else Vector3.ZERO

## The map window always centres on the player: the seamless world has no
## meaningful fixed extent for the two open realms, and a following window
## keeps the authored route, ponds and relief at a readable scale.
func _view_center() -> Vector2:
	var player := _player_pos()
	return Vector2(player.x, player.z)

func _view_rect() -> Rect2:
	var half := MAP_SPAN * 0.5
	return Rect2(_view_center() - Vector2(half, half), Vector2(MAP_SPAN, MAP_SPAN))

## Uniform metres-to-pixels scale. The window is square, so keying the scale to
## its half-diagonal inscribes the whole window inside the disc and no cell or
## marker can poke past the rim.
func _view_scale(radius: float) -> float:
	var half_diagonal := MAP_SPAN * 0.5 * sqrt(2.0)
	return radius * MAP_PADDING / maxf(half_diagonal, 0.001)

func _project(world_xz: Vector3, center: Vector2, radius: float) -> Vector2:
	var view := _view_center()
	return center + Vector2(world_xz.x - view.x, world_xz.z - view.y) \
		* _view_scale(radius)

## Half-open lattice range [col0, col1) x [row0, row1) covering the window.
func _visible_cell_bounds() -> Vector4i:
	var rect := _view_rect()
	var origin := _grid_origin()
	var col0 := clampi(int(floor((rect.position.x - origin.x) / GRID_CELL_METERS)),
		0, GRID_COLS)
	var col1 := clampi(int(ceil((rect.end.x - origin.x) / GRID_CELL_METERS)),
		0, GRID_COLS)
	var row0 := clampi(int(floor((rect.position.y - origin.y) / GRID_CELL_METERS)),
		0, GRID_ROWS)
	var row1 := clampi(int(ceil((rect.end.y - origin.y) / GRID_CELL_METERS)),
		0, GRID_ROWS)
	return Vector4i(col0, row0, maxi(col1, col0), maxi(row1, row0))

func _cell_rect(center: Vector2, radius: float, col: int, row: int) -> Rect2:
	return _run_rect(center, radius, col, col + 1, row)

## Batched span for one row of cells [col_start, col_end). Unexplored fog is
## uniform, so whole runs merge into one rect instead of hundreds of tiny
## quads; the span is clipped to the window so nothing draws past the disc.
func _run_rect(center: Vector2, radius: float, col_start: int, col_end: int,
		row: int) -> Rect2:
	var origin := _grid_origin()
	var window := _view_rect()
	var x0 := maxf(origin.x + float(col_start) * GRID_CELL_METERS,
		window.position.x)
	var x1 := minf(origin.x + float(col_end) * GRID_CELL_METERS, window.end.x)
	var z0 := maxf(origin.y + float(row) * GRID_CELL_METERS, window.position.y)
	var z1 := minf(origin.y + float(row + 1) * GRID_CELL_METERS, window.end.y)
	var p0 := _project(Vector3(x0, 0.0, z0), center, radius)
	var p1 := _project(Vector3(x1, 0.0, z1), center, radius)
	return Rect2(p0, p1 - p0)

func _terrain_node() -> TerrainRelief:
	if _relief_terrain != null and is_instance_valid(_relief_terrain):
		return _relief_terrain
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene == null:
		return null
	_relief_terrain = scene.find_child("Terrain", true, false) as TerrainRelief
	return _relief_terrain

## Memoised heightfield sample on the world-anchored lattice. Only samples the
## window and its one-cell margin need are ever computed, and the cache is
## dropped when the realm changes or grows past a hard cap.
func _height_at_lattice(col: int, row: int) -> float:
	var key := row * (GRID_COLS + 1) + col
	if _heights.has(key):
		return float(_heights[key])
	var terrain := _terrain_node()
	if terrain == null or not terrain.has_method("height_at"):
		return 0.0
	var origin := _grid_origin()
	var value := float(terrain.call("height_at",
		origin.x + float(col) * GRID_CELL_METERS,
		origin.y + float(row) * GRID_CELL_METERS))
	_heights[key] = value
	return value

## North-west hillshade over the window, so ridges, hollows and the carved pond
## basins read before any marker does.
func _draw_relief(center: Vector2, radius: float) -> void:
	var terrain := _terrain_node()
	if terrain == null or not terrain.has_method("height_at"):
		return
	var realm := _realm_id()
	if _heights_realm != realm:
		_heights_realm = realm
		_heights.clear()
	if _heights.size() > HEIGHT_CACHE_LIMIT:
		_heights.clear()
	var cells := _visible_cell_bounds()
	var col0 := cells.x
	var row0 := cells.y
	var col1 := cells.z
	var row1 := cells.w
	# Warm the lattice first so the shading pass only reads memoised values.
	for row in range(row0, mini(row1 + 1, GRID_ROWS + 1)):
		for col in range(col0, mini(col1 + 1, GRID_COLS + 1)):
			_height_at_lattice(col, row)
	var base := _map_color()
	var dark := Color(0.045, 0.065, 0.055)
	var light := Color(0.60, 0.62, 0.50)
	for row in range(row0, row1):
		for col in range(col0, col1):
			var h := _height_at_lattice(col, row)
			var hx := _height_at_lattice(col + 1, row)
			var hz := _height_at_lattice(col, row + 1)
			var shade := clampf(0.5 + (hx - h) * RELIEF_SLOPE
				+ (hz - h) * RELIEF_SLOPE * 0.66, 0.0, 1.0)
			var tint := base.lerp(dark, (1.0 - shade) * 0.68)
			tint = tint.lerp(light, maxf(shade - 0.55, 0.0) * 0.55)
			draw_rect(_cell_rect(center, radius, col, row),
				Color(tint.r, tint.g, tint.b, 1.0))

## Authored realm trail; the discovery fog covers the parts not yet reached.
func _draw_route(center: Vector2, radius: float) -> void:
	var route: Array = RealmLayoutData.profile(_realm_id()).get("route", [])
	if route.size() < 2:
		return
	var color := Color(0.90, 0.86, 0.72, 0.55)
	var previous := Vector2.ZERO
	var previous_near := false
	var started := false
	for value in route:
		if not value is Vector3:
			continue
		var point := _project(value as Vector3, center, radius)
		var near := point.distance_to(center) <= radius
		if started and (near or previous_near):
			draw_line(previous, point, color, 2.4, true)
		previous = point
		previous_near = near
		started = true

## Authored ponds from the shared ground composition, in the realm's water hue.
func _draw_water(center: Vector2, radius: float) -> void:
	var specs := WorldGroundComposition.pond_specs(_realm_id())
	if specs.is_empty():
		return
	var window := _view_rect()
	var scale := _view_scale(radius)
	var fill := Color(0.30, 0.55, 0.68, 0.95)
	var rim := Color(0.10, 0.20, 0.27, 0.95)
	for spec in specs:
		var definition: Dictionary = spec
		var pond_center: Vector2 = definition.get("center", Vector2.ZERO)
		if not window.has_point(pond_center):
			continue
		var point := _project(Vector3(pond_center.x, 0.0, pond_center.y),
			center, radius)
		var pond_radius := maxf(3.0, float(definition.get("radius", 3.0)) * scale)
		draw_circle(point, pond_radius + 0.9, rim)
		draw_circle(point, pond_radius, fill)

## Discovery layer: everything the player has not reached stays dark, so the
## map itself is the progress bar for exploration.
func _draw_discovery(center: Vector2, radius: float) -> void:
	var fog := Color(0.015, 0.025, 0.030, 0.97)
	var cells := _visible_cell_bounds()
	for row in range(cells.y, cells.w):
		var run_start := -1
		for col in range(cells.x, cells.z + 1):
			var hidden := col < cells.z \
				and not _explored.has(row * GRID_COLS + col)
			if hidden and run_start < 0:
				run_start = col
			elif not hidden and run_start >= 0:
				draw_rect(_run_rect(center, radius, run_start, col, row), fog)
				run_start = -1

## Landmarks. Guidance outside the window clamps to the rim so an objective is
## never simply missing; decorative markers outside are culled instead.
func _marker_in_window(pos: Vector3) -> bool:
	var window := _view_rect()
	var margin := GRID_CELL_METERS * 2.0
	return pos.x >= window.position.x - margin and pos.x <= window.end.x + margin \
		and pos.z >= window.position.y - margin and pos.z <= window.end.y + margin

## Marker de-clutter. Hub scenes stack a dozen decorative markers inside a few
## pixels; guidance always survives, but a decorative marker that would paint
## on top of one already drawn is dropped so the crowded areas stay readable.
func _declutter_markers(center: Vector2, radius: float) -> Array[Dictionary]:
	var visible: Array[Dictionary] = []
	var drawn: Array[Vector2] = []
	for m in markers:
		if not _marker_revealed(m):
			continue
		var pos: Vector3 = m.get("pos", Vector3.ZERO)
		var guidance := int(m.get("priority", PRIORITY_STRUCTURE)) <= PRIORITY_ACTIVITY
		var point := _project(pos, center, radius)
		if not guidance and _marker_in_window(pos):
			var crowded := false
			for previous in drawn:
				if previous.distance_to(point) < MARKER_MIN_SPACING:
					crowded = true
					break
			if crowded:
				continue
		drawn.append(point)
		visible.append(m)
	return visible

func _draw_markers(center: Vector2, radius: float) -> void:
	var labeled: Array[Vector2] = []
	for m in _declutter_markers(center, radius):
		var pos: Vector3 = m.get("pos", Vector3.ZERO)
		var marker_color: Color = m.get("color", Color.WHITE)
		if not _marker_in_window(pos):
			if int(m.get("priority", PRIORITY_STRUCTURE)) > PRIORITY_ACTIVITY:
				continue
			var direction := _project(pos, center, radius) - center
			if direction.length() < 0.001:
				continue
			var edge := center + direction.normalized() * (radius - 7.0)
			draw_circle(edge, 4.6, Color(0.02, 0.04, 0.04, 0.9))
			draw_circle(edge, 2.8, marker_color)
			continue
		var p := _project(pos, center, radius)
		draw_circle(p, 6.0, Color(0.02, 0.04, 0.04, 0.9))
		draw_circle(p, 4.0, marker_color)
		draw_string(get_theme_default_font(), p + Vector2(-4, -7),
			str(m.get("glyph", "")), HORIZONTAL_ALIGNMENT_CENTER, 10, 10, marker_color)
		if expanded:
			var overlap := false
			for previous in labeled:
				if previous.distance_to(p) < LABEL_MIN_SPACING:
					overlap = true
					break
			if overlap:
				continue
			labeled.append(p)
			var kind_label := str(m.get("kind", "site")).replace("_", " ").to_upper()
			var label := "%s · %s" % [kind_label,
				str(m.get("label", "")).replace("_", " ").to_upper()]
			if label.length() > 18:
				label = label.substr(0, 18) + "…"
			draw_string(get_theme_default_font(), p + Vector2(9, 4), label,
				HORIZONTAL_ALIGNMENT_LEFT, 122, 9, Color(0.95, 0.92, 0.84))

func _draw() -> void:
	var legend_height := BIG_LEGEND_HEIGHT if expanded else SMALL_LEGEND_HEIGHT
	var side := minf(size.x, size.y - legend_height)
	var center := Vector2(size.x * 0.5, side * 0.5)
	var radius := side * 0.5 - 4.0
	var map_color := _map_color()

	# Backing disc + realm field
	draw_circle(center, radius + 3.0, Color(0.03, 0.05, 0.05, 0.85))
	draw_circle(center, radius, Color(map_color.r, map_color.g,
		map_color.b, 0.72))

	# Ground detail under the markers: relief, then trail, then water.
	_draw_relief(center, radius)
	_draw_route(center, radius)
	_draw_water(center, radius)
	_draw_discovery(center, radius)
	_draw_markers(center, radius)

	# Player dot: amber, gentle pulse, always the centre of the follow window.
	var pulse := 3.4 + sin(_pulse_t * 3.2) * 1.1
	draw_circle(center, pulse + 2.5, Color(1.0, 0.72, 0.29, 0.25))
	draw_circle(center, pulse, Color(1.0, 0.84, 0.45, 1.0))

	# Realm rim last: it trims the square relief/fog cells back to the disc.
	var realm_def: Dictionary = Bestiary.REALMS.get(_realm_id(), {})
	var mist: Color = realm_def.get("mist_tint", Color(0.65, 0.75, 0.72))
	draw_arc(center, radius, 0.0, TAU, 56, Color(mist.r, mist.g, mist.b, 0.9),
		2.5, true)

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
