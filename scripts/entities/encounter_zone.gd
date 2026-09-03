extends Area3D
class_name EncounterZone

## === EncounterZone — Dynamic Enemy Encounter Trigger ===
## Placed by ProceduralWorldGenerator.
## When the hero enters the zone, spawns a pack of enemies via Bestiary.
## After all enemies are defeated, the zone becomes inactive for this session.
## Visual: ground circle telegraph, glowing emissive decal.
##
## Usage:
##   var zone := EncounterZone.new()
##   zone.setup(realm_id, tier, stage)

signal pack_cleared
signal pack_spawned(enemies: Array)

@export_enum("normal", "hard", "elite") var tier   : String = "normal"
@export var realm_id  : String = "bramblewood"
@export var stage     : int    = 0
@export var zone_radius : float = 5.5

var _active  : bool = true
var _enemies : Array[Node3D] = []
var _decal   : MeshInstance3D = null
var _decal_mat : StandardMaterial3D = null
var _t       : float = 0.0
var _spawned : bool  = false

func _ready() -> void:
	collision_layer = 0
	collision_mask  = 1 << 0   # player only
	_build_collision()
	_build_visual()
	body_entered.connect(_on_body_entered)

func setup(p_realm: String, p_tier: String, p_stage: int) -> void:
	realm_id = p_realm
	tier     = p_tier
	stage    = p_stage
	if _decal_mat:
		_decal_mat.emission = _tier_color()

# ─── Collision ────────────────────────────────────────────────────────────────

func _build_collision() -> void:
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = zone_radius; cy.height = 3.5
	cs.shape = cy; add_child(cs)

# ─── Visual ───────────────────────────────────────────────────────────────────

func _build_visual() -> void:
	_decal = MeshInstance3D.new()
	_decal.name = "ZoneDecal"
	var qm := QuadMesh.new()
	qm.size = Vector2(zone_radius * 2.0, zone_radius * 2.0)
	_decal.mesh = qm
	_decal_mat = StandardMaterial3D.new()
	_decal_mat.albedo_color = Color(_tier_color().r, _tier_color().g, _tier_color().b, 0.18)
	_decal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_decal_mat.emission_enabled = true
	_decal_mat.emission = _tier_color()
	_decal_mat.emission_energy_multiplier = 0.42
	_decal_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_decal.material_override = _decal_mat
	_decal.rotation.x = -PI * 0.5
	_decal.position.y  = 0.04
	add_child(_decal)

	# Ambient light for the zone
	var light := OmniLight3D.new()
	light.light_color  = _tier_color()
	light.light_energy = 0.35
	light.omni_range   = zone_radius * 1.4
	light.position.y   = 0.5
	add_child(light)

func _tier_color() -> Color:
	match tier:
		"elite": return Color(1.00, 0.22, 0.08)
		"hard":  return Color(1.00, 0.65, 0.12)
		_:       return Color(0.42, 0.88, 0.42)

# ─── Trigger ──────────────────────────────────────────────────────────────────

func _on_body_entered(body: Node3D) -> void:
	if not _active or _spawned: return
	if not body.is_in_group("player"): return
	_spawned = true
	_flash_activate()
	call_deferred("_spawn_pack")

func _flash_activate() -> void:
	if _decal_mat == null: return
	var tw := create_tween()
	tw.tween_property(_decal_mat, "emission_energy_multiplier", 2.5, 0.15)
	tw.tween_property(_decal_mat, "emission_energy_multiplier", 0.42, 0.45)

func _spawn_pack() -> void:
	var parent := get_parent() if get_parent() else get_tree().current_scene
	if parent == null: return

	# Get variant from Bestiary
	var variant : Dictionary = Bestiary.variant_for(realm_id, tier)
	if variant.is_empty(): return

	var kind : String = str(variant.get("kind", "hushling"))
	var scene_path := _scene_for_kind(kind)
	if not ResourceLoader.exists(scene_path): return
	var scn : PackedScene = load(scene_path)
	if scn == null: return

	var count := 2 if tier == "normal" else (3 if tier == "hard" else 4)
	var spawned : Array[Node3D] = []

	for i in count:
		var enemy : Node3D = scn.instantiate()
		parent.add_child(enemy)
		var ang := TAU * float(i) / float(count)
		enemy.global_position = global_position + Vector3(cos(ang)*3.2, 0, sin(ang)*3.2)

		# Apply CharacterModelData configuration
		var md := CharacterModelData.for_realm(realm_id, tier)
		if md != null:
			md.configure_entity(enemy)
		if enemy.has_method("configure_archetype"):
			enemy.call("configure_archetype", kind)

		# Connect death signal
		if enemy.has_signal("died"):
			enemy.died.connect(_on_enemy_died.bind(enemy))

		spawned.append(enemy)
		_enemies.append(enemy)
		CombatFx.spawn_spawn_portal(self, enemy.global_position, _tier_color())

	pack_spawned.emit(spawned)

	# Update WorldState combat intensity
	var ws := get_node_or_null("/root/WorldState")
	if ws and ws.has_method("set_combat_intensity"):
		ws.call("set_combat_intensity", 0.6 if tier == "normal" else 0.85)

func _scene_for_kind(kind: String) -> String:
	match kind:
		"spitter":         return "res://scenes/entities/spitter.tscn"
		"fenling",\
		"moonfen_fenling": return "res://scenes/entities/moonfen_fenling.tscn"
		"relic_leech":     return "res://scenes/entities/relic_leech.tscn"
		_:                 return "res://scenes/entities/hushling.tscn"

func _on_enemy_died(enemy: Node3D) -> void:
	_enemies.erase(enemy)
	# Prune dead references
	_enemies = _enemies.filter(func(e): return is_instance_valid(e) and not bool(e.get("is_defeated") if e.get("is_defeated") != null else false))
	if _enemies.is_empty():
		_active = false
		_on_pack_cleared()

func _on_pack_cleared() -> void:
	pack_cleared.emit()
	# Grant rewards
	var rm := get_node_or_null("/root/RewardManager")
	if rm:
		rm.call("grant_enemy_kill", realm_id, tier, 0)
	# Fade out zone decal
	if _decal_mat:
		var tw := create_tween()
		tw.tween_property(_decal_mat, "albedo_color:a", 0.0, 1.0)
		tw.tween_property(_decal_mat, "emission_energy_multiplier", 0.0, 1.0)
	# Reset WorldState combat intensity
	var ws := get_node_or_null("/root/WorldState")
	if ws and ws.has_method("set_combat_intensity"):
		ws.call("set_combat_intensity", 0.0)

# ─── Process ──────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _active or _spawned: return
	_t += delta
	if _decal_mat:
		_decal_mat.emission_energy_multiplier = 0.25 + sin(_t * 1.8) * 0.18
