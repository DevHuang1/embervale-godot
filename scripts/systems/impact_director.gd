extends Node
class_name ImpactDirector

## === ImpactDirector — Screen Shake, HiStop, Debris ===
## AutoLoad that mediates camera feedback and impact debris spawning.
## All call sites: boss_base.take_damage, hero._on_landed, matriarch crown break.
##
## API:
##   apply_feedback(source, kind, world_pos, dir, strength)
##   spawn_impact_debris(source, world_pos, material, count)
##
## Feedback kinds: "hit", "heavy", "land", "death"

signal shake_requested(intensity: float, duration: float)

var _camera_rig : Node3D = null

func _ready() -> void:
	# Discover camera rig lazily
	call_deferred("_find_camera_rig")

func _find_camera_rig() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_camera_rig = scene.get_node_or_null("CameraRig")
	if _camera_rig == null:
		_camera_rig = scene.find_child("CameraRig", true, false)

# ─────────────────────────────────────────────────────────────────────────────
# Feedback
# ─────────────────────────────────────────────────────────────────────────────

func apply_feedback(
		source: Node3D,
		kind: String,
		_world_pos: Vector3,
		_direction: Vector3,
		strength: float) -> void:

	var shake   := 0.0
	var duration := 0.0
	match kind:
		"hit":
			shake    = strength * 0.18
			duration = 0.12
		"heavy":
			shake    = strength * 0.55
			duration = 0.28
		"land":
			shake    = strength * 0.22
			duration = 0.16
		"death":
			shake    = 0.65
			duration = 0.45
		_:
			shake    = strength * 0.15
			duration = 0.10

	_shake_camera(shake, duration)
	shake_requested.emit(shake, duration)

func _shake_camera(intensity: float, duration: float) -> void:
	if _camera_rig == null or not is_instance_valid(_camera_rig):
		_find_camera_rig()
	if _camera_rig == null:
		return
	if _camera_rig.has_method("add_shake"):
		_camera_rig.call("add_shake", intensity)
		return
	# Fallback: direct position jitter tween on the rig
	var original := _camera_rig.position
	var tw := _camera_rig.create_tween()
	var steps := maxi(2, int(duration / 0.04))
	for i in steps:
		var jitter := Vector3(
			randf_range(-intensity, intensity),
			randf_range(-intensity * 0.5, intensity * 0.5),
			0.0)
		tw.tween_property(_camera_rig, "position", original + jitter, duration / float(steps))
	tw.tween_property(_camera_rig, "position", original, 0.06).set_trans(Tween.TRANS_SPRING)

# ─────────────────────────────────────────────────────────────────────────────
# Debris
# ─────────────────────────────────────────────────────────────────────────────

func spawn_impact_debris(
		source: Node3D,
		world_pos: Vector3,
		material: String,
		count: int) -> void:
	if not is_instance_valid(source) or not source.is_inside_tree():
		return
	var scene_root := source.get_tree().current_scene
	if scene_root == null:
		return

	# Choose material color
	var col := Color(0.28, 0.22, 0.16)
	match material:
		"rock":    col = Color(0.30, 0.26, 0.20)
		"ember":   col = Color(0.55, 0.18, 0.06)
		"bark":    col = Color(0.22, 0.16, 0.10)
		"crystal": col = Color(0.38, 0.58, 0.88)
		"mud":     col = Color(0.24, 0.20, 0.16)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness    = 0.85

	for i in clampi(count, 1, 12):
		var shard := MeshInstance3D.new()
		var bm    := BoxMesh.new()
		bm.size = Vector3(
			randf_range(0.06, 0.18),
			randf_range(0.04, 0.14),
			randf_range(0.05, 0.16))
		shard.mesh = bm
		shard.material_override = mat
		shard.global_position = world_pos + Vector3(
			randf_range(-0.25, 0.25),
			randf_range(0.0, 0.35),
			randf_range(-0.25, 0.25))
		shard.rotation = Vector3(
			randf_range(0.0, TAU), randf_range(0.0, TAU), randf_range(0.0, TAU))
		scene_root.add_child(shard)

		var vel := Vector3(
			randf_range(-3.5, 3.5),
			randf_range(1.5, 5.0),
			randf_range(-3.5, 3.5))
		var tw := shard.create_tween()
		tw.tween_property(shard, "global_position", shard.global_position + vel, 0.6) \
			.set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(shard, "rotation",
			shard.rotation + Vector3(randf_range(-TAU, TAU), randf_range(-TAU, TAU), 0), 0.6)
		tw.tween_callback(shard.queue_free)
