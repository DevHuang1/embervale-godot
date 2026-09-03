extends Node
class_name TargetMarker

## === TargetMarker — Lantern Lock-On Visual System ===
## Called from hero._ready():
##   TargetMarker.ensure(hero)          — creates the marker if not present
##   TargetMarker.bind_lantern(lantern) — links the lantern node
##
## When GameState.enemy_target changes, the marker:
##   - Moves a glowing ring to float above the target
##   - Pulses the ring when the hero has an attack window
##   - Shows a line/beam from the lantern toward the target
##   - Fades out when combat disengages
##
## Static factory so it works without AutoLoad.

signal target_changed(target: Node3D)
signal target_lost

# ─────────────────────────────────────────────────────────────────────────────
# Static factory / singleton-per-hero
# ─────────────────────────────────────────────────────────────────────────────

static func ensure(hero: Node3D) -> TargetMarker:
	var existing := hero.get_node_or_null("TargetMarker")
	if existing is TargetMarker:
		return existing as TargetMarker
	var tm := TargetMarker.new()
	tm.name = "TargetMarker"
	hero.add_child(tm)
	tm._hero = hero
	return tm

static func bind_lantern(lantern: Node3D) -> void:
	if lantern == null:
		return
	var hero := lantern.get_parent()
	while hero != null and not hero is CharacterBody3D:
		hero = hero.get_parent()
	if hero == null:
		return
	var tm := hero.get_node_or_null("TargetMarker") as TargetMarker
	if tm != null:
		tm._lantern = lantern

# ─────────────────────────────────────────────────────────────────────────────
# Instance
# ─────────────────────────────────────────────────────────────────────────────

var _hero    : Node3D = null
var _lantern : Node3D = null
var _target  : Node3D = null

var _ring    : MeshInstance3D = null
var _ring_mat : StandardMaterial3D = null
var _beam    : MeshInstance3D = null
var _t       : float = 0.0

func _ready() -> void:
	_hero = get_parent()
	_build_ring()
	_build_beam()
	# Connect to GameState
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		if gs.has_signal("mark_locked"):
			gs.mark_locked.connect(_on_mark_locked)
		if gs.has_signal("victory"):
			gs.victory.connect(_on_combat_end)
		if gs.has_signal("defeated"):
			gs.defeated.connect(_on_combat_end)

func _process(delta: float) -> void:
	_t += delta
	var gs := get_node_or_null("/root/GameState")
	var current_target : Node3D = null
	if gs != null:
		current_target = gs.get("enemy_target") as Node3D

	if current_target != _target:
		_target = current_target
		if _target != null:
			target_changed.emit(_target)
		else:
			target_lost.emit()

	_update_ring(delta)
	_update_beam(delta)

func _build_ring() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "LockOnRing"
	var tm := TorusMesh.new()
	tm.inner_radius  = 0.42
	tm.outer_radius  = 0.52
	tm.ring_segments = 32
	tm.rings         = 2
	_ring.mesh = tm
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color               = Color(1.0, 0.88, 0.28, 0.0)
	_ring_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.emission_enabled           = true
	_ring_mat.emission                   = Color(1.0, 0.72, 0.18)
	_ring_mat.emission_energy_multiplier = 2.2
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = _ring_mat
	_ring.rotation.x = PI * 0.5
	add_child(_ring)

func _build_beam() -> void:
	_beam = MeshInstance3D.new()
	_beam.name = "LanternBeam"
	var qm := QuadMesh.new()
	qm.size = Vector2(0.025, 1.0)
	_beam.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(1.0, 0.85, 0.45, 0.0)
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 0.75, 0.30)
	mat.emission_energy_multiplier = 1.5
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode      = BaseMaterial3D.CULL_DISABLED
	_beam.material_override = mat
	add_child(_beam)

func _update_ring(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		if _ring_mat != null:
			_ring_mat.albedo_color.a = lerpf(_ring_mat.albedo_color.a, 0.0, delta * 8.0)
		if _ring != null:
			_ring.visible = _ring_mat.albedo_color.a > 0.01
		return

	# Float ring above target
	var target_pos := _target.global_position + Vector3(0, 2.2, 0)
	_ring.global_position = target_pos + Vector3(0, sin(_t * 2.2) * 0.10, 0)
	_ring.rotation.y     += delta * 1.8

	# Alpha pulse
	var pulse := 0.55 + sin(_t * 4.5) * 0.25
	_ring_mat.albedo_color.a = lerpf(_ring_mat.albedo_color.a, pulse, delta * 6.0)
	_ring.visible = true

func _update_beam(delta: float) -> void:
	var beam_mat := _beam.material_override as StandardMaterial3D
	if _target == null or not is_instance_valid(_target) or _lantern == null:
		if beam_mat != null:
			beam_mat.albedo_color.a = lerpf(beam_mat.albedo_color.a, 0.0, delta * 8.0)
		_beam.visible = beam_mat != null and beam_mat.albedo_color.a > 0.01
		return

	var from  := _lantern.global_position
	var to    := _target.global_position + Vector3(0, 1.0, 0)
	var mid   := (from + to) * 0.5
	var dist  := from.distance_to(to)
	_beam.global_position = mid
	_beam.look_at(to, Vector3.UP)
	_beam.scale = Vector3(1.0, dist, 1.0)
	if beam_mat != null:
		beam_mat.albedo_color.a = lerpf(beam_mat.albedo_color.a, 0.30, delta * 6.0)
	_beam.visible = true

func _on_mark_locked(_flare: float) -> void:
	# Spike ring brightness on lock-on
	if _ring_mat != null:
		var tw := create_tween()
		tw.tween_property(_ring_mat, "emission_energy_multiplier", 5.5, 0.08)
		tw.tween_property(_ring_mat, "emission_energy_multiplier", 2.2, 0.35)

func _on_combat_end() -> void:
	_target = null
