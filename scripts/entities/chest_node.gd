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

enum ChestTier { COMMON, RARE, BOSS }

@export_enum("common", "rare", "boss") var chest_tier  : String = "common"
@export var realm_id          : String = "bramblewood"
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

func _ready() -> void:
	_build_geometry()
	_build_interact_area()
	_build_prompt()
	_build_particles()

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
	var tw := _latch_mat.create_tween().set_loops()
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

# ─────────────────────────────────────────────────────────────────────────────
# Open
# ─────────────────────────────────────────────────────────────────────────────

func _open_chest() -> void:
	if _is_open:
		return
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

	# Grant rewards
	var rm := get_node_or_null("/root/RewardManager")
	if rm != null:
		rm.call("grant_chest", chest_tier, realm_id)
		rm.reward_granted.connect(_on_reward_granted, CONNECT_ONE_SHOT)
	else:
		# Fallback if not AutoLoaded — direct grant
		RewardManager.new().grant_chest(chest_tier, realm_id)

	chest_opened.emit(global_position, chest_tier)

	# Schedule respawn
	if respawn_time_sec > 0.0:
		var timer := get_tree().create_timer(respawn_time_sec, false)
		timer.timeout.connect(_reset_chest)

func _on_reward_granted(summary: Dictionary) -> void:
	# Show FloatingText pops for each drop type
	var y_offset := 0.0
	var pos := global_position + Vector3(0, 0.9, 0)
	var gold := int(summary.get("gold", 0))
	if gold > 0:
		FloatingText.spawn_on_entity(self, "+%d 🪙" % gold, Color(1.0, 0.85, 0.30))
		y_offset += 0.28
	var xp := int(summary.get("xp", 0))
	if xp > 0:
		FloatingText.spawn_on_entity(self, "+%d XP" % xp, Color(0.42, 0.85, 0.55))
		y_offset += 0.28
	var diamonds := int(summary.get("diamonds", 0))
	if diamonds > 0:
		FloatingText.spawn_on_entity(self, "+%d 💎" % diamonds, Color(0.55, 0.75, 1.00))

func _reset_chest() -> void:
	_is_open = false
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

## Static factory: spawn a chest in the world at the given position.
static func spawn_at(parent: Node3D, pos: Vector3,
		tier: String = "common", realm: String = "bramblewood") -> ChestNode:
	var chest := ChestNode.new()
	chest.chest_tier = tier
	chest.realm_id   = realm
	parent.add_child(chest)
	chest.global_position = pos
	return chest
