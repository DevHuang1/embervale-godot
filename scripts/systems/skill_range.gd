extends Node
class_name SkillRange

## === Skill Range System ===
## Tile-based range validation for both enemy and player skills.
## Uses a grid system where each tile can have different range properties.

@export var tile_size: float = 2.0
@export var max_range_tiles: int = 6

static var _instance: SkillRange = null

func _ready() -> void:
	_instance = self

static func get_instance() -> SkillRange:
	if _instance == null or not is_instance_valid(_instance):
		_instance = SkillRange.new()
	return _instance

func world_to_tile(pos: Vector3) -> Vector2i:
	return Vector2i(int(pos.x / tile_size), int(pos.z / tile_size))

func get_distance_tiles(from_pos: Vector3, to_pos: Vector3) -> int:
	var from_tile := world_to_tile(from_pos)
	var to_tile := world_to_tile(to_pos)
	return maxi(abs(from_tile.x - to_tile.x), abs(from_tile.y - to_tile.y))

func is_in_range(from_pos: Vector3, to_pos: Vector3, range_tiles: int) -> bool:
	return get_distance_tiles(from_pos, to_pos) <= range_tiles

func get_enemy_skill_range(enemy_id: String) -> int:
	return max_range_tiles

func get_player_skill_range(skill_id: String) -> int:
	return max_range_tiles