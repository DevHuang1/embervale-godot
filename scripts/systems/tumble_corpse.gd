class_name TumbleCorpse
extends RigidBody3D

## === Death physics: tumble corpses (+ boss ragdoll attempt) ===
## On kill, the entity's visual reparents into this rigid body, takes the
## killing impulse, tumbles against the environment, sinks and fades.
## A static registry caps concurrent corpses per quality tier. For rigged
## bosses, try_ragdoll() makes a best-effort PhysicalBoneSimulator3D
## conversion and reports success; callers fall back to a tumble corpse.

const LIFETIME := 2.6
const FADE_SINK := 0.55

# Environment-only contact: corpses never shove the living.
const LAYER_CORPSE := 1 << 6
const MASK_ENVIRONMENT := 1 << 5

static var _live: Array[TumbleCorpse] = []

## Concurrent corpse budget (QualityScaler.corpse_pool_size: 2/4/6).
static var max_corpses: int = 6


## Detach a visual into a fresh rigid shell and give it the killing blow.
static func launch(visual: Node3D, impulse: Vector3,
		lifetime: float = LIFETIME) -> TumbleCorpse:
	if visual == null or not visual.is_inside_tree():
		return null
	var tree := visual.get_tree()
	var scene := tree.current_scene if tree != null else null
	if scene == null and tree != null:
		scene = tree.root   # bare/test trees and scene-change windows
	if scene == null:
		return null
	while _live.size() >= maxi(max_corpses, 1):
		_live[0].finish()
	var body := TumbleCorpse.new()
	body.name = "TumbleCorpse"
	body.collision_layer = LAYER_CORPSE
	body.collision_mask = MASK_ENVIRONMENT
	body.physics_material_override = PhysicsMaterial.new()
	body.physics_material_override.bounce = 0.22
	body.physics_material_override.friction = 0.9
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.48
	shape.shape = sphere
	shape.position = Vector3(0, 0.45, 0)
	body.add_child(shape)
	scene.add_child(body)
	body.global_position = Vector3(visual.global_position.x, 0.0,
		visual.global_position.z)
	visual.reparent(body)
	body.linear_velocity = impulse
	var spin := clampf(impulse.length(), 2.0, 7.0)
	body.angular_velocity = Vector3(
		randf_range(-spin, spin), randf_range(-spin * 0.4, spin * 0.4),
		randf_range(-spin, spin))
	_live.append(body)
	tree.create_timer(lifetime).timeout.connect(body._sink)
	return body


## Best-effort per-bone ragdoll for rigged characters. Returns true when a
## usable physical bone chain was activated (caller keeps the entity posed
## by physics); false means "use a tumble corpse".
static func try_ragdoll(skeleton_root: Node3D, impulse: Vector3) -> bool:
	if not ClassDB.class_exists("PhysicalBoneSimulator3D"):
		return false
	var skeleton: Skeleton3D = null
	for cand in skeleton_root.find_children("*", "Skeleton3D", true, false):
		skeleton = cand
		break
	if skeleton == null or skeleton.get_bone_count() < 10:
		return false
	const KEY_BONES := ["hip", "spine", "chest", "head", "arm", "hand",
		"thigh", "leg", "calf", "foot"]
	var made := 0
	for i in skeleton.get_bone_count():
		var bone_name := str(skeleton.get_bone_name(i)).to_lower()
		var matched := false
		for key in KEY_BONES:
			if bone_name.contains(key):
				matched = true
				break
		if not matched:
			continue
		var pb := PhysicalBone3D.new()
		pb.bone_name = skeleton.get_bone_name(i)
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
		pb.joint_rotation = Vector3(0.0, 0.0, deg_to_rad(15.0))
		pb.collision_layer = LAYER_CORPSE
		pb.collision_mask = MASK_ENVIRONMENT
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.16
		cs.shape = sph
		pb.add_child(cs)
		skeleton.add_child(pb)
		made += 1
	if made < 4:
		return false
	var sim := PhysicalBoneSimulator3D.new()
	skeleton.add_child(sim)
	sim.physical_bones_start_simulation()
	# A shove sells the collapse even though bones carry their own weight
	var first := skeleton.find_child("PhysicalBone3D*", true, false) \
		as PhysicalBone3D
	if first != null:
		first.apply_central_impulse(impulse)
	return true


func _sink() -> void:
	var tween := create_tween()
	tween.tween_property(self, "position:y", position.y - 0.7, FADE_SINK)
	tween.tween_callback(finish)


func finish() -> void:
	_live.erase(self)
	queue_free()


func _exit_tree() -> void:
	_live.erase(self)
