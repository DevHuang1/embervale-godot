extends RefCounted
class_name BossEncounterDirector

const ROSTER := preload("res://scripts/systems/boss_roster_catalog.gd")

## Arena presentation constants are shared by every boss entry path. They do
## not alter encounter timing, damage, hitboxes, or reset semantics.
const BOSS_ENTRY_DISTANCE: float = 4.5
const ARENA_MARKER_INNER_RADIUS: float = 2.8
const ARENA_MARKER_OUTER_RADIUS: float = 3.2
const ARENA_TRIGGER_RADIUS: float = 3.0

var host: Node3D = null
var active_boss: Node3D = null
var active_encounter_id := ""
var _last_spawn_position := Vector3.ZERO

## Return a deterministic, player-facing boss entry point on the far side of
## an arena. Only X/Z are used so the caller can conform the result to terrain.
static func entry_position_for(arena_origin: Vector3, player_position: Vector3,
		entry_distance: float = BOSS_ENTRY_DISTANCE) -> Vector3:
	var approach := Vector2(player_position.x - arena_origin.x,
		player_position.z - arena_origin.z)
	var approach_direction := approach.normalized()
	if approach_direction.length_squared() <= 0.0001:
		# Fixed fallback: the boss enters from the arena's +Z side when the
		# player is exactly centered, keeping captures and saves deterministic.
		approach_direction = Vector2(0.0, -1.0)
	var distance := maxf(entry_distance, 0.0)
	return Vector3(arena_origin.x - approach_direction.x * distance,
		arena_origin.y,
		arena_origin.z - approach_direction.y * distance)

func setup(parent: Node3D) -> void:
	host = parent

func definition_for(boss_id: String) -> Dictionary:
	return ROSTER.definition_for(boss_id)

func canonical_id_for(saved_or_legacy_id: String) -> String:
	return ROSTER.canonical_id_for(saved_or_legacy_id)

func spawn_boss(encounter_id: String, practice: bool = false,
		spawn_position: Vector3 = Vector3.ZERO) -> Node3D:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return null
	if active_boss != null and is_instance_valid(active_boss):
		return active_boss
	var canonical := canonical_id_for(encounter_id)
	var definition := definition_for(canonical)
	if definition.is_empty():
		push_error("BossEncounterDirector: unknown encounter '%s'" % encounter_id)
		return null
	var scene := load(str(definition.get("scene", ROSTER.ARTICULATED_SCENE))) as PackedScene
	if scene == null:
		push_error("BossEncounterDirector: missing boss scene for '%s'" % canonical)
		return null
	var boss := scene.instantiate() as Node3D
	if boss == null:
		return null
	if "def_id" in boss:
		boss.set("def_id", canonical)
	if "is_practice" in boss:
		boss.set("is_practice", practice)
	host.add_child(boss)
	active_boss = boss
	active_encounter_id = canonical
	_last_spawn_position = spawn_position
	if spawn_position != Vector3.ZERO:
		boss.global_position = spawn_position
	if boss.has_method("set_encounter_origin"):
		boss.call("set_encounter_origin", spawn_position if spawn_position != Vector3.ZERO \
			else boss.global_position)
	if boss.has_signal("died"):
		boss.died.connect(_on_active_boss_died)
	return boss

func reset_active_boss() -> void:
	if active_boss != null and is_instance_valid(active_boss) \
			and active_boss.has_method("reset_encounter"):
		active_boss.call("reset_encounter")

func encounter_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if active_boss == null or not is_instance_valid(active_boss):
		return result
	result.append({
		"id": active_encounter_id,
		"alive": not bool(active_boss.get("is_defeated")),
		"position": active_boss.global_position,
		"practice": bool(active_boss.get("is_practice")),
	})
	return result

func _on_active_boss_died() -> void:
	active_boss = null
	active_encounter_id = ""
