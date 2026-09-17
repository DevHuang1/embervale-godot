extends StaticBody3D
class_name ChestNode

## === ChestNode — Interactive 3D Chest Entity ===
##
## Place in scene. Configure chest_tier, realm_id, respawn_time_sec.
##
## On hero interact (Area3D overlap + InputManager.interact_pressed):
##   1. Animates open (lid lifts, glow burst, particle cascade)
##   2. Rolls LootTable via RewardManager.grant_chest()
##   3. Displays per-item FloatingText pops above the chest
##   4. Locks for respawn_time_sec (visual glow dims), then resets
##
## Procedural geometry — no .glb needed:
##   - Stone/wood base (BoxMesh)
##   - Arched lid (CylinderMesh half)
##   - Iron band accents (thin BoxMesh strips)
##   - Emissive latch (sphere, color = tier color)
##   - Particle cascade on open

signal chest_opened(position: Vector3, tier: String)
signal chest_reset(position: Vector3)
signal chest_locked(message: String)

enum ChestTier { COMMON, RARE, BOSS }

@export_enum("common", "rare", "boss") var chest_tier  : String = "common"
@export var realm_id          : String = "bramblewood"
@export var chest_id          : String = ""
@export var chest_label       : String = ""
@export var required_boss_key : String = ""
@export_enum("persistent", "respawnable") var persistence_mode: String = "persistent"
@export var respawn_time_sec  : float  = 120.0
@export var interact_radius   : float  = 2.5

# Visual state
var _is_open       : bool = false
var _lid_node      : Node3D = null
var _latch_mat     : StandardMaterial3D = null
var _glow_light    : OmniLight3D = null
var _particles     : GPUParticles3D = null
var _prompt_label  : Label3D = null
var _hero_nearby   : bool = false
var _hero_ref      : Node3D = null
var _respawn_timer : Timer = null

## Public interaction contract used by Hero's nearby-interactable router.
## The backing state remains private so callers cannot consume a reward by
## changing the presentation flag.
var opened: bool:
	get:
		return _is_open

# Tier palette
const TIER_COLORS := {
	"common": Color(0.70, 0.55, 0.22),
	"rare":   Color(0.32, 0.55, 0.90),
	"boss":   Color(0.95, 0.72, 0.18),
}
const TIER_GLOW := {
	"common": 0.8,
	"rare":   1.8,
	"boss":   3.2,
}
const LOOT_DROP_SCRIPT := preload("res://scripts/systems/loot_drop.gd")
## Drop types delivered as physical walk-over pickups. Everything else
## (xp / diamonds / materials) is granted instantly at open, mirroring enemies.
const PHYSICAL_DROP_TYPES: Array[String] = ["gold", "item", "weapon", "armor"]

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("chest")
	add_to_group("structure")
	_build_geometry()
	_build_interact_area()
	_build_target_body()
	_build_prompt()
	_build_particles()
	_check_persistence()

# ─────────────────────────────────────────────────────────────────────────────
# Geometry
# ─────────────────────────────────────────────────────────────────────────────

func _build_geometry() -> void:
	var tier_col : Color = TIER_COLORS.get(chest_tier, TIER_COLORS["common"])

	# Base
	var base := MeshInstance3D.new()
	base.name = "ChestBase"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.72, 0.52, 0.50)
	base.mesh = bm
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.22, 0.16, 0.10)
	base_mat.roughness    = 0.90
	base_mat.metallic     = 0.05
	base.material_override = base_mat
	base.position.y = 0.26
	add_child(base)

	# Iron bands (2 horizontal strips)
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = Color(0.28, 0.26, 0.24)
	band_mat.roughness    = 0.55
	band_mat.metallic     = 0.72
	for z in [-0.15, 0.15]:
		var band := MeshInstance3D.new()
		var bbm  := BoxMesh.new()
		bbm.size = Vector3(0.74, 0.06, 0.04)
		band.mesh = bbm
		band.material_override = band_mat
		band.position = Vector3(0, 0.28, z)
		add_child(band)

	# Lid (rotatable)
	_lid_node = Node3D.new()
	_lid_node.name = "ChestLid"
	_lid_node.position = Vector3(0, 0.53, -0.23)
	add_child(_lid_node)

	var lid := MeshInstance3D.new()
	var lbm := BoxMesh.new()
	lbm.size = Vector3(0.72, 0.22, 0.50)
	lid.mesh = lbm
	lid.material_override = base_mat
	lid.position = Vector3(0, 0.0, 0.23)
	_lid_node.add_child(lid)

	# Latch (emissive gem)
	var latch := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.055
	sm.height = 0.10
	latch.mesh = sm
	_latch_mat = StandardMaterial3D.new()
	_latch_mat.albedo_color               = tier_col
	_latch_mat.emission_enabled           = true
	_latch_mat.emission                   = tier_col
	_latch_mat.emission_energy_multiplier = TIER_GLOW.get(chest_tier, 0.8)
	latch.material_override = _latch_mat
	latch.position = Vector3(0, 0.54, 0.255)
	add_child(latch)

	# Glow light
	_glow_light = OmniLight3D.new()
	_glow_light.light_color  = tier_col
	_glow_light.light_energy = TIER_GLOW.get(chest_tier, 0.8) * 0.5
	_glow_light.omni_range   = 2.8
	_glow_light.position.y   = 0.55
	add_child(_glow_light)

	# Idle pulse tween
	var tw: Tween = create_tween().set_loops()
	tw.tween_property(_latch_mat, "emission_energy_multiplier",
		TIER_GLOW.get(chest_tier, 0.8) * 1.6, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_latch_mat, "emission_energy_multiplier",
		TIER_GLOW.get(chest_tier, 0.8) * 0.5, 1.2).set_trans(Tween.TRANS_SINE)

# ─────────────────────────────────────────────────────────────────────────────
# Interact area
# ─────────────────────────────────────────────────────────────────────────────

func _build_interact_area() -> void:
	var area := Area3D.new()
	area.name = "InteractArea"
	area.collision_layer = 0
	area.collision_mask  = 1 << 0  # player layer
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = interact_radius
	cs.shape   = sph
	area.add_child(cs)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	add_child(area)

## A ray-targetable body so the hero's facing ray can select the chest they are
## aiming at. It sits on the pickup layer plus the default layer so it is
## visible to interaction queries without joining the hero's movement mask
## (which excludes both), so it never blocks walking.
func _build_target_body() -> void:
	collision_layer = (1 << 0) | (1 << 3)
	collision_mask  = 0
	var cs := CollisionShape3D.new()
	cs.name = "InteractTarget"
	var box := BoxShape3D.new()
	box.size = Vector3(0.78, 0.70, 0.58)
	cs.shape = box
	cs.position.y = 0.35
	add_child(cs)

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_hero_nearby = true
	_hero_ref    = body
	if _prompt_label != null:
		_prompt_label.visible = not _is_open

func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_hero_nearby = false
	_hero_ref    = null
	if _prompt_label != null:
		_prompt_label.visible = false

# ─────────────────────────────────────────────────────────────────────────────
# Prompt label
# ─────────────────────────────────────────────────────────────────────────────

func _build_prompt() -> void:
	_prompt_label = Label3D.new()
	_prompt_label.name    = "InteractPrompt"
	_prompt_label.text    = "[Interact] Open"
	_prompt_label.font_size = 52
	_prompt_label.modulate = Color(1.0, 0.92, 0.55)
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.no_depth_test = true
	_prompt_label.position.y = 1.1
	_prompt_label.visible  = false
	add_child(_prompt_label)

# ─────────────────────────────────────────────────────────────────────────────
# Particles
# ─────────────────────────────────────────────────────────────────────────────

func _build_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.name    = "LootBurst"
	_particles.amount  = 32
	_particles.lifetime = 1.2
	_particles.emitting  = false
	_particles.one_shot  = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape        = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.direction             = Vector3(0, 1, 0)
	pm.spread                = 120.0
	pm.initial_velocity_min  = 1.5
	pm.initial_velocity_max  = 4.0
	pm.gravity               = Vector3(0, -2.5, 0)
	pm.scale_min             = 0.06
	pm.scale_max             = 0.20
	pm.color = TIER_COLORS.get(chest_tier, TIER_COLORS["common"])
	_particles.process_material = pm
	_particles.position.y = 0.55
	add_child(_particles)

# ─────────────────────────────────────────────────────────────────────────────
# Input
# ─────────────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _is_open or not _hero_nearby:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_open_chest()

## WorldManager and mobile controls use the same interaction contract as
## landmarks and gathering nodes. Keyboard input still reaches the legacy
## unhandled-input path above, while touch/controller activation calls this.
func interact() -> void:
	_open_chest()

# ─────────────────────────────────────────────────────────────────────────────
# Open
# ─────────────────────────────────────────────────────────────────────────────

func _open_chest() -> void:
	if _is_open:
		return
	var lock_message := _lock_message()
	if not lock_message.is_empty():
		chest_locked.emit(lock_message)
		var gs_locked := get_node_or_null("/root/GameState")
		if gs_locked != null and gs_locked.has_signal("quest_progress"):
			gs_locked.quest_progress.emit(lock_message)
		return

	# Roll first, then claim. RewardManager only rolls here; the physical loot is
	# granted on pickup. A persistent chest records its claim and its exact
	# remaining drops in one save before anything is spawned, so a reload can
	# neither lose uncollected loot nor let the chest pay out twice.
	var rm := get_node_or_null("/root/RewardManager")
	if rm == null or not rm.has_method("roll_chest_drops"):
		push_warning("ChestNode: RewardManager unavailable; chest remains unopened")
		return
	var drops: Array = rm.call("roll_chest_drops", chest_tier, realm_id)
	if drops.is_empty():
		return

	var physical: Array = []
	var instant: Array = []
	for raw in drops:
		if not raw is Dictionary:
			continue
		var drop: Dictionary = raw
		if str(drop.get("type", "")) in PHYSICAL_DROP_TYPES:
			physical.append(drop)
		else:
			instant.append(drop)

	var persistent := _uses_persistent_claim()
	if persistent:
		var gs_claim := get_node_or_null("/root/GameState")
		if gs_claim == null or not gs_claim.has_method("begin_chest_claim"):
			push_warning("ChestNode: claim API unavailable; chest remains unopened")
			return
		if not bool(gs_claim.call("begin_chest_claim", chest_id, physical)):
			return  # already claimed (or rejected)

	# Instant rewards (xp / diamonds / materials) land immediately.
	if not instant.is_empty():
		rm.call("grant_drops", instant, {
			"source": "chest", "source_id": chest_id,
			"source_label": chest_label, "persistent": false,
		})

	_is_open = true
	if _prompt_label != null:
		_prompt_label.visible = false

	# Animate lid open
	var tw := _lid_node.create_tween()
	tw.tween_property(_lid_node, "rotation:x", -PI * 0.62, 0.38).set_trans(Tween.TRANS_BACK)

	# Latch flare
	if _latch_mat != null:
		var tw2 := create_tween()
		tw2.tween_property(_latch_mat, "emission_energy_multiplier", 8.5, 0.10)
		tw2.tween_property(_latch_mat, "emission_energy_multiplier", 0.1, 0.60)

	# Glow flash
	if _glow_light != null:
		var tw3 := create_tween()
		tw3.tween_property(_glow_light, "light_energy", 4.5, 0.12)
		tw3.tween_property(_glow_light, "light_energy", 0.1, 0.55)

	# Particles
	if _particles != null:
		_particles.restart()
		_particles.emitting = true

	# CombatFx burst
	CombatFx.spawn_burst(self, global_position + Vector3(0, 0.6, 0),
		TIER_COLORS.get(chest_tier, TIER_COLORS["common"]), 22, 5.0, 0.5, 0.18)
	CombatFx.spawn_ring(self, global_position, 1.2,
		TIER_COLORS.get(chest_tier, TIER_COLORS["common"]), 0.45)

	# One reveal listing the rolled contents; grants happen as drops are picked up.
	rm.call("announce_chest_roll", chest_tier, realm_id, chest_id, chest_label,
		drops, persistent)

	_spawn_loot_drops(physical, persistent)

	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("update_objective"):
		gs.call("update_objective", "open_chest", chest_id, 1)

	chest_opened.emit(global_position, chest_tier)

	_schedule_respawn()

func _lock_message() -> String:
	if required_boss_key.is_empty():
		return ""
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("has_boss_killed") \
			and bool(gs.call("has_boss_killed", required_boss_key)):
		return ""
	var boss_label := required_boss_key.replace("biome_", "").replace("_", " ").capitalize()
	return "Locked · Defeat %s first." % boss_label

func _uses_persistent_claim() -> bool:
	return not chest_id.is_empty() and persistence_mode == "persistent"

func _schedule_respawn() -> void:
	if _uses_persistent_claim() or respawn_time_sec <= 0.0:
		return
	if _respawn_timer == null:
		_respawn_timer = Timer.new()
		_respawn_timer.name = "RespawnTimer"
		_respawn_timer.one_shot = true
		_respawn_timer.timeout.connect(_on_respawn_timer_timeout)
		add_child(_respawn_timer)
	_respawn_timer.wait_time = clampf(respawn_time_sec, 0.1, 3600.0)
	_respawn_timer.start()

func _on_respawn_timer_timeout() -> void:
	_reset_chest()

func _loot_offset(index: int, total: int) -> Vector3:
	var count := maxi(total, 1)
	var angle := TAU * float(index) / float(count)
	var radius := 0.35 + 0.06 * float(index % 3)
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

## Spawn one physical pickup per rolled drop. Chest id + slot index are carried
## so the pickup can clear its persisted pending slot on collection.
func _spawn_loot_drops(physical: Array, persistent: bool) -> void:
	var origin := global_position + Vector3(0, 0.55, 0)
	var claim_id := chest_id if persistent else ""
	for i in physical.size():
		LOOT_DROP_SCRIPT.spawn_drop(self, origin + _loot_offset(i, physical.size()),
			physical[i], claim_id, i)

func _reset_chest() -> void:
	_is_open = false
	if _respawn_timer != null:
		_respawn_timer.stop()
	# Close lid
	var tw := _lid_node.create_tween()
	tw.tween_property(_lid_node, "rotation:x", 0.0, 0.35).set_trans(Tween.TRANS_SPRING)
	# Restore glow
	if _latch_mat != null:
		var tw2 := create_tween()
		tw2.tween_property(_latch_mat, "emission_energy_multiplier",
			TIER_GLOW.get(chest_tier, 0.8), 0.5)
	if _glow_light != null:
		var tw3 := create_tween()
		tw3.tween_property(_glow_light, "light_energy",
			TIER_GLOW.get(chest_tier, 0.8) * 0.5, 0.5)
	chest_reset.emit(global_position)

func _check_persistence() -> void:
	if not _uses_persistent_claim():
		return
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	var opened_chests: Dictionary = gs.get("opened_chests") \
		if gs.get("opened_chests") is Dictionary else {}
	if not bool(opened_chests.get(chest_id, false)):
		return
	_is_open = true
	if _prompt_label != null:
		_prompt_label.visible = false
	if _lid_node != null:
		_lid_node.rotation.x = -PI * 0.62
	if _glow_light != null:
		_glow_light.light_energy = 0.1
	if _latch_mat != null:
		_latch_mat.emission_energy_multiplier = 0.1
	# Restore any loot that was rolled but not yet picked up. Deferred so a
	# runtime-built chest has its final world position before drops spawn.
	call_deferred("_restore_pending_drops")

## Respawn the persisted remainder of a claimed chest's roll. Consumed slots are
## stored as null and skipped, so a reload mid-collection restores only what was
## never picked up.
func _restore_pending_drops() -> void:
	if not _uses_persistent_claim() or not is_inside_tree():
		return
	var gs := get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("get_pending_chest_drops"):
		return
	var drops: Array = gs.call("get_pending_chest_drops", chest_id)
	if drops.is_empty():
		return
	var origin := global_position + Vector3(0, 0.55, 0)
	for i in drops.size():
		if drops[i] == null:
			continue
		LOOT_DROP_SCRIPT.spawn_drop(self, origin + _loot_offset(i, drops.size()),
			drops[i], chest_id, i)

## Apply a realm-layout chest definition before adding the node to the scene.
## Returns false for malformed definitions so bad content cannot create an
## anonymous reward source.
func configure_from_definition(definition: Dictionary) -> bool:
	var id := str(definition.get("id", "")).strip_edges()
	if id.is_empty():
		return false
	chest_id = id
	chest_label = str(definition.get("label", id.replace("_", " ").capitalize()))
	realm_id = str(definition.get("realm", realm_id))
	required_boss_key = str(definition.get("boss_key", "")) \
		if str(definition.get("type", "")) == "boss_gated" else ""
	persistence_mode = str(definition.get("persistence", "persistent")).to_lower()
	if persistence_mode not in ["persistent", "respawnable"]:
		persistence_mode = "persistent"
	respawn_time_sec = maxf(0.0, float(definition.get("respawn_time_sec", 0.0)))
	chest_tier = tier_for_rarity(int(definition.get("rarity", 0)))
	return true

static func tier_for_rarity(rarity: int) -> String:
	if rarity >= 4:
		return "boss"
	if rarity >= 2:
		return "rare"
	return "common"

## Static factory: spawn a chest in the world at the given position.
static func spawn_at(parent: Node3D, pos: Vector3,
		tier: String = "common", realm: String = "bramblewood", id: String = "") -> ChestNode:
	var chest := ChestNode.new()
	chest.chest_tier = tier
	chest.realm_id   = realm
	chest.chest_id   = id
	chest.persistence_mode = "persistent" if not id.is_empty() else "respawnable"
	parent.add_child(chest)
	chest.global_position = pos
	return chest
