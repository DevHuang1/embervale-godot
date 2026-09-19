extends Node
class_name DiscoveryDirector

## === Discovery Director ===
## Watches the world for the first time the player comes near a creature kind
## or an authored structure, and asks the codex plus GameState whether that
## record has already been introduced. Presentation belongs to the HUD; this
## node only decides *what* is new, once, and emits it.
##
## Bosses are deliberately excluded: they already own a boss-intro sweep and
## their lesson catalogs, so a second overlay would fight them.

signal record_discovered(record: Dictionary)

const CODEX := preload("res://scripts/systems/discovery_codex.gd")
const LAYOUT := preload("res://scripts/world/realm_layout_data.gd")

const POLL_SECONDS := 0.25
## "Meeting" a creature is close enough to read its silhouette; structures are
## met at nameplate range. Both are inside the range the HUD already uses for
## the combat card, so nothing fires from off-screen.
const MOB_RADIUS := 13.0
const STRUCTURE_RADIUS := 11.0
## One poll emits at most one record so a camp full of new creatures trickles
## into the HUD instead of stampeding it.
const ENEMY_GROUP := "enemy"
const BOSS_GROUP := "boss"
const STRUCTURE_GROUP := "structure"

var _world: Node3D = null
var _poll_in: float = 0.0

func setup(world_root: Node3D) -> void:
	_world = world_root
	_poll_in = POLL_SECONDS
	set_process(true)

func _process(delta: float) -> void:
	if _world == null or not is_instance_valid(_world):
		return
	_poll_in -= delta
	if _poll_in > 0.0:
		return
	_poll_in = POLL_SECONDS
	_poll()

func _poll() -> void:
	var hero := _hero()
	if hero == null:
		return
	if _poll_mobs(hero):
		return
	_poll_structures(hero)

func _hero() -> Node3D:
	for candidate in get_tree().get_nodes_in_group("player"):
		var player := candidate as Node3D
		if player != null and is_instance_valid(player):
			return player
	return null

func _poll_mobs(hero: Node3D) -> bool:
	var nearest: Node3D = null
	var nearest_distance := MOB_RADIUS
	for candidate in get_tree().get_nodes_in_group(ENEMY_GROUP):
		var enemy := candidate as Node3D
		if enemy == null or not is_instance_valid(enemy) or enemy.is_in_group(BOSS_GROUP):
			continue
		if enemy.has_method("is_dead") and bool(enemy.call("is_dead")):
			continue
		var distance := hero.global_position.distance_to(enemy.global_position)
		if distance < nearest_distance:
			nearest = enemy
			nearest_distance = distance
	if nearest == null:
		return false
	var kind := _mob_kind(nearest)
	if kind.is_empty():
		return false
	var record := CODEX.mob_record(kind)
	if record.is_empty():
		return false
	var record_id := "mob:%s" % kind
	if not _game_state().discover_record(record_id):
		return false
	record["id"] = record_id
	record["node"] = nearest
	record["realm"] = _realm_id()
	record_discovered.emit(record)
	return true

func _poll_structures(hero: Node3D) -> bool:
	var nearest: Node3D = null
	var nearest_distance := STRUCTURE_RADIUS
	for candidate in get_tree().get_nodes_in_group(STRUCTURE_GROUP):
		var structure := candidate as Node3D
		if structure == null or not is_instance_valid(structure):
			continue
		# Only authored map structures carry a kind; chests and props share the
		# group but are not places.
		var kind := str(structure.get_meta("structure_kind", ""))
		if kind.is_empty():
			continue
		var distance := hero.global_position.distance_to(structure.global_position)
		if distance < nearest_distance:
			nearest = structure
			nearest_distance = distance
	if nearest == null:
		return false
	var kind := str(nearest.get_meta("structure_kind", ""))
	var instance_id := str(nearest.get_meta("structure_id", ""))
	if instance_id.is_empty():
		instance_id = kind
	var record := CODEX.structure_record(kind, _structure_label(nearest), _realm_id())
	if record.is_empty():
		return false
	var record_id := "structure:%s" % instance_id
	if not _game_state().discover_record(record_id):
		return false
	record["id"] = record_id
	record["node"] = nearest
	record_discovered.emit(record)
	return true

## Subclasses name their own silhouette through `discovery_kind()`; a plain
## enemy falls back to its exported archetype.
func _mob_kind(enemy: Node) -> String:
	if enemy.has_method("discovery_kind"):
		return str(enemy.call("discovery_kind")).strip_edges()
	var archetype = enemy.get("archetype")
	return str(archetype).strip_edges() if archetype != null else ""

func _structure_label(structure: Node) -> String:
	var label := structure.get_node_or_null("StructureLabel") as Label3D
	if label != null and not label.text.strip_edges().is_empty():
		return label.text
	var display = structure.get("display_name")
	return str(display) if display != null else ""

func _realm_id() -> String:
	if _world == null:
		return ""
	return LAYOUT.visual_realm_for(_world)

func _game_state() -> Node:
	return get_node_or_null("/root/GameState")
