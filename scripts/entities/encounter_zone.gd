extends Area3D
class_name EncounterZone

const CONTENT_REGISTRY := preload("res://scripts/systems/content_registry.gd")
const ECOLOGY := preload("res://scripts/systems/ecology_tactics_catalog.gd")

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
signal ecology_choice_changed(choice_id: String, choice_text: String)

@export_enum("normal", "hard", "elite") var tier   : String = "normal"
@export var realm_id  : String = "bramblewood"
@export var stage     : int    = 0
@export var zone_radius : float = 5.5
## Authored-pocket metadata. Dressing systems can use this to place readable
## approach/reveal/reward/exit markers without changing encounter mechanics.
@export var pocket_id: String = ""
@export var approach_label: String = "Approach"
@export var reveal_label: String = "Threat revealed"
@export var reward_label: String = "Reward"
@export var exit_label: String = "Exit sightline"

var _active  : bool = true
var _enemies : Array[Node3D] = []
var _decal   : MeshInstance3D = null
var _decal_mat : StandardMaterial3D = null
var _reward_marker: Label3D = null
var _t       : float = 0.0
var _spawned : bool  = false
var ecology_rule: Dictionary = {}
var ecology_choice_id: String = ""
var ecology_modifiers: Dictionary = {}

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
	ecology_rule = ECOLOGY.rule_for(realm_id)
	ecology_choice_id = ""
	ecology_modifiers = {}
	if not ecology_rule.is_empty():
		reveal_label = "Threat revealed · %s" % str(ecology_rule.get("trigger", ""))
	if _decal_mat:
		_decal_mat.emission = _tier_color()

func ecology_choices() -> Array[Dictionary]:
	if ecology_rule.is_empty():
		return []
	return [{"id": "primary", "label": str(ecology_rule.get("choice", "")),
		"consequence": str(ecology_rule.get("consequence", ""))},
		{"id": "defer", "label": "Wait and read the arena",
		"consequence": "Keep the default encounter pressure."}]

func choose_ecology_tactic(choice_id: String) -> bool:
	if _spawned or ecology_rule.is_empty() or not ["primary", "defer"].has(choice_id):
		return false
	ecology_choice_id = choice_id
	var choices := ecology_choices()
	var selected: Dictionary = choices[0 if choice_id == "primary" else 1]
	ecology_modifiers = ecology_rule.get("primary_modifiers", {}).duplicate(true) \
		if choice_id == "primary" else {}
	if _decal_mat != null:
		_decal_mat.emission = _tier_color().lightened(0.18 if choice_id == "primary" else 0.0)
	ecology_choice_changed.emit(choice_id, str(selected.get("label", "")))
	return true

func pocket_contract() -> Dictionary:
	## Stable authoring contract for realm dressing and QA tooling. The zone's
	## trigger, enemy count, damage, and reward behavior remain unchanged.
	return {
		"id": pocket_id if not pocket_id.is_empty() else name.to_snake_case(),
		"realm": realm_id,
		"tier": tier,
		"approach": approach_label,
		"reveal": reveal_label,
		"combat": "Readable combat space",
		"ecology": ecology_rule.duplicate(true),
		"ecology_choice": ecology_choice_id,
		"ecology_modifiers": ecology_modifiers.duplicate(true),
		"reward": reward_label,
		"exit": exit_label,
	}

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

	_reward_marker = Label3D.new()
	_reward_marker.name = "RewardMarker"
	_reward_marker.text = "REWARD"
	_reward_marker.font_size = 32
	_reward_marker.outline_size = 8
	_reward_marker.modulate = Color(1.0, 0.86, 0.42, 0.0)
	_reward_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_reward_marker.no_depth_test = true
	_reward_marker.position = Vector3(0.0, 1.8, 0.0)
	_reward_marker.visible = false
	add_child(_reward_marker)

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
	_play_pocket_reveal()
	call_deferred("_spawn_pack")

func _play_pocket_reveal() -> void:
	## A short authored reveal gives the pocket a readable arrival beat without
	## pausing gameplay or taking ownership of movement/input.
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("record_golden_route_signal"):
		scene.call("record_golden_route_signal", "encounter_pocket")
		if tier == "elite":
			scene.call("record_golden_route_signal", "bounded_telegraphs")
	var camera := scene.get_node_or_null("CameraRig") if scene != null else null
	if camera != null and camera.has_method("play_focus_moment"):
		camera.call("play_focus_moment", self, Vector3(0.0, 4.2, 6.8),
			Vector3(0.0, 0.35, 0.0), 1.1 if tier == "normal" else 1.35)

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
	var fallback := "res://scenes/entities/hushling.tscn"
	match kind:
		"spitter":         fallback = "res://scenes/entities/spitter.tscn"
		"fenling",\
		"moonfen_fenling": fallback = "res://scenes/entities/moonfen_fenling.tscn"
		"relic_leech":     fallback = "res://scenes/entities/relic_leech.tscn"
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("get_content_registry"):
		return CONTENT_REGISTRY.resolve_asset_path(gs.get_content_registry(), "enemy", kind, fallback)
	return fallback

func _on_enemy_died(enemy: Node3D) -> void:
	_enemies.erase(enemy)
	# Prune dead references
	_enemies = _enemies.filter(func(e): return is_instance_valid(e) and not bool(e.get("is_defeated") if e.get("is_defeated") != null else false))
	if _enemies.is_empty():
		_active = false
		_on_pack_cleared()

func _on_pack_cleared() -> void:
	pack_cleared.emit()
	if tier == "elite":
		var gs := get_node_or_null("/root/GameState")
		if gs != null and gs.has_method("update_objective"):
			gs.call("update_objective", "kill", "chapter3_elite", 1)
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
	_reveal_reward_marker()

func _reveal_reward_marker() -> void:
	if _reward_marker == null or not is_instance_valid(_reward_marker):
		return
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("record_golden_route_signal"):
		scene.call("record_golden_route_signal", "valuable_drop" if tier == "elite" else "reward_reveal")
	_reward_marker.text = str(reward_label).to_upper()
	_reward_marker.visible = true
	_reward_marker.modulate = Color(1.0, 0.86, 0.42, 0.0)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_reward_marker, "modulate:a", 1.0, 0.18)
	tw.tween_interval(4.0)
	tw.tween_property(_reward_marker, "modulate:a", 0.0, 0.55)
	tw.tween_callback(_reward_marker.queue_free)

# ─── Process ──────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _active or _spawned: return
	_t += delta
	if _decal_mat:
		_decal_mat.emission_energy_multiplier = 0.25 + sin(_t * 1.8) * 0.18
