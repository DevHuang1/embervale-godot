extends Node
class_name CharacterRigLoader

## === CharacterRigLoader — Authored Model Drop-In System ===
## Called by every entity _ready() as:
##   CharacterRigLoader.try_if_wire(entity, profile_name) -> bool
##   CharacterRigLoader.bind_sockets(entity, socket_map)
##   CharacterRigLoader.has_model(profile_name) -> bool
##
## Loads a .glb from res://assets/models/<profile>.glb if it exists,
## mounts it under entity/Visual/AuthoredRig, and wires the EntityAnimator
## to use the .glb's AnimationPlayer instead of procedural tweens.
##
## If the .glb doesn't exist the call is a silent no-op — entities fall back
## to their procedural silhouette bodies. This matches the original intent:
## "silent no-op until the model ships."
##
## Socket binding: maps socket_id → bone_name so AttachmentSocket nodes
## reparent under the matching bone after the rig mounts.

const MODEL_BASE_PATH := "res://assets/models/"

# Model registry (populated by try_if_wire on first load)
static var _loaded : Dictionary = {}   # profile → PackedScene or null

# ─────────────────────────────────────────────────────────────────────────────
# Static API (called as CharacterRigLoader.method(...))
# ─────────────────────────────────────────────────────────────────────────────

## Returns true if a model was mounted, false for silent no-op.
## A validated .glb wins over a legacy .fbx when both exist (see _any_model);
## the legacy FBX here is exactly what puts the authored Knight on the hero.
static func try_if_wire(entity: Node3D, profile: String) -> bool:
	var path := _any_model(profile)
	if path.is_empty():
		return false

	# Cache the PackedScene
	if not _loaded.has(profile):
		var scene : PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE)
		_loaded[profile] = scene
	var packed : PackedScene = _loaded.get(profile)
	if packed == null:
		return false

	# Find or create the Visual node
	var visual := entity.get_node_or_null("Visual")
	if visual == null:
		visual = Node3D.new()
		visual.name = "Visual"
		entity.add_child(visual)

	# The authored rig lives inside an existing procedural rig subtree when
	# one is present (Hero has Visual/Rig), otherwise directly under Visual.
	# Mounting inside the same subtree keeps the model in the same space the
	# ghost body used, so sockets/armor/weapon alignment keeps working.
	var rig_parent := visual as Node3D
	var rig_sub := visual.get_node_or_null("Rig") as Node3D
	if rig_sub != null:
		rig_parent = rig_sub

	# Remove any previously mounted AuthoredRig
	var prev := rig_parent.get_node_or_null("AuthoredRig")
	if prev != null:
		prev.queue_free()

	# Instantiate and mount
	var rig: Node3D = packed.instantiate()
	rig.name = "AuthoredRig"
	rig_parent.add_child(rig)

	# Legacy FBX armatures frequently export at a different scale than the
	# procedural model they replace (Blender cm-unit exports come in huge).
	# `authored_rig_height` (>0, world units) normalises the mounted model to
	# the host's authored height; 0 keeps the authored .glb size untouched.
	var target_height := float(entity.get("authored_rig_height"))
	if target_height > 0.01:
		_normalize_height(rig, target_height)

	# A drop-in authored model replaces the procedural silhouette. Entities
	# opt in via `replace_procedural_on_mount`; bosses (which layer FX onto
	# their authored frame) stay fully untouched.
	if bool(entity.get("replace_procedural_on_mount")):
		_hide_replaced_visuals(rig_parent, rig)

	# Wire AnimTreeBridge so gameplay cues can drive the imported
	# AnimationPlayer. The bridge binds lazily — hosts that never ask for a
	# cue keep using the procedural animator untouched.
	var bridge := entity.get_node_or_null("AnimBridge") as AnimTreeBridge
	if bridge == null:
		bridge = AnimTreeBridge.new()
		bridge.name = "AnimBridge"
		entity.add_child(bridge)
	bridge.bind(rig)
	entity.set_meta("anim_bridge", bridge)

	# The EntityAnimator stays the gameplay *clock* (impact/footfall events).
	# Its exported node paths are left pointing at the procedural tree; hosts
	# that need authored impact timing read the bridge via
	# entity.get_meta("anim_bridge", ...) — never the removed set_visual_root.
	return true

## Uniformly scale the mounted rig so its world-space height hits
## `target_height` metres. Meshes are measured through their actual world
## transform, so exports with baked transforms or scaled children just work.
static func _normalize_height(rig: Node3D, target_height: float) -> void:
	var h := _world_height(rig)
	if h <= 0.001:
		return
	rig.scale *= Vector3.ONE * (target_height / h)

static func _world_height(root: Node3D) -> float:
	var box := AABB()
	var started := false
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		var xf := m.global_transform
		for i in 8:
			var wp: Vector3 = xf * m.get_aabb().get_endpoint(i)
			if not started:
				box = AABB(wp, Vector3.ZERO)
				started = true
			else:
				box = box.expand(wp)
	return box.size.y if started else 0.0

## Hide the procedural silhouette the mounted rig replaces. Weapon/armor
## meshes riding AttachmentSockets are preserved (they re-parent onto the
## model bones), and hero lantern glow stays so gameplay light/beam sources
## never vanish from under the new model.
static func _hide_replaced_visuals(rig_parent: Node3D, keep: Node3D) -> void:
	for child in rig_parent.get_children():
		if child == keep or not child is Node3D:
			continue
		var n := child as Node3D
		if _inside_socket(n) or _is_keep_visual(n):
			continue
		if n is MeshInstance3D:
			n.visible = false
			continue
		# Container node: hide only leaf meshes, never socket host anchors.
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m == null or _inside_socket(m) or _is_keep_visual(m):
				continue
			m.visible = false

static func _inside_socket(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is AttachmentSocket or p.get("socket_id") != null:
			return true
		p = p.get_parent()
	return false

## Gameplay visuals that must survive a model swap (lantern glow/beam source).
static func _is_keep_visual(n: Node) -> bool:
	return str(n.name).to_lower().contains("lantern")

## Returns true if a model has been successfully loaded for this profile.
static func has_model(profile: String) -> bool:
	return _loaded.has(profile) and _loaded[profile] != null

## Reparents AttachmentSocket nodes under matching bones after rig mount.
## socket_map: { "socket_id": "BoneName", ... }
static func bind_sockets(entity: Node3D, socket_map: Dictionary) -> void:
	if not has_model("") and _loaded.is_empty():
		return  # No rigs mounted yet — fast exit
	var visual := entity.get_node_or_null("Visual")
	if visual == null:
		return
	var rig := visual.find_child("AuthoredRig", true, false) as Node3D
	if rig == null:
		return

	for socket_id in socket_map:
		var bone_name : String = socket_map[socket_id]
		# Find socket node
		var socket := _find_socket(entity, socket_id)
		if socket == null:
			continue
		# Find bone anchor in rig. Authored models (FBX/GLB) keep every bone
		# *inside* one Skeleton3D node, so a name-based find_child() never
		# matches — fall back to a Skeleton3D lookup and attach through a
		# BoneAttachment3D named after the bone (dots sanitized, e.g.
		# "Shoulder.L" → "Shoulder_L") so consumers can still find the anchor
		# by node name.
		var bone := rig.find_child(bone_name, true, false)
		if bone == null:
			var skeleton := _find_skeleton(rig)
			if skeleton != null and skeleton.find_bone(bone_name) >= 0:
				bone = _bone_anchor(skeleton, bone_name)
		if bone == null:
			continue
		# Reparent socket under bone, keeping world transform
		var world_xform: Transform3D = socket.global_transform
		socket.get_parent().remove_child(socket)
		bone.add_child(socket)
		socket.global_transform = world_xform

## First Skeleton3D in the mounted rig, depth-first.
static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

## Reusable BoneAttachment3D for a bone. The node name is the sanitized bone
## name so gameplay code and tests can locate the anchor without knowing the
## skeleton layout.
static func _bone_anchor(skeleton: Skeleton3D, bone_name: String) -> BoneAttachment3D:
	var anchor_name := bone_name.replace(".", "_").replace(":", "_")
	var existing := skeleton.get_node_or_null(anchor_name) as BoneAttachment3D
	if existing != null and existing.bone_idx == skeleton.find_bone(bone_name):
		return existing
	var anchor := BoneAttachment3D.new()
	anchor.name = anchor_name
	skeleton.add_child(anchor)
	anchor.bone_idx = skeleton.find_bone(bone_name)
	return anchor

static func _find_socket(entity: Node3D, socket_id: String) -> Node3D:
	for child in entity.get_children():
		if child.get("socket_id") == socket_id:
			return child
	return _find_socket_recursive(entity, socket_id)

static func _find_socket_recursive(node: Node, socket_id: String) -> Node3D:
	for child in node.get_children():
		if child.get("socket_id") == socket_id:
			return child
		var found := _find_socket_recursive(child, socket_id)
		if found != null:
			return found
	return null

## Preload all known models at startup (call once from main scene _ready).
static func preload_all() -> void:
	var profiles := [
		"hero", "hushling", "fenling", "moonfen_fenling",
		"boss_matriarch", "boss_whispergrove_rootwarden", "boss_whispergrove_dewseer",
	]
	for p in profiles:
		var path: String = MODEL_BASE_PATH + p + ".glb"
		if ResourceLoader.exists(path):
			_loaded[p] = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE)
		else:
			_loaded[p] = null

## Resolve which authored asset exists for a profile. A validated .glb wins
## over a legacy .fbx; returns "" when neither is present. Used by tests and
## by try_if_wire callers that need the exact mounted path.
static func _any_model(profile: String) -> String:
	for ext in ["glb", "fbx"]:
		var path: String = MODEL_BASE_PATH + profile + "." + ext
		if ResourceLoader.exists(path):
			return path
	return ""

