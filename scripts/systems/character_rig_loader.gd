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

## Returns true if a .glb model was mounted, false for silent no-op.
static func try_if_wire(entity: Node3D, profile: String) -> bool:
	var path := MODEL_BASE_PATH + profile + ".glb"
	if not ResourceLoader.exists(path):
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

	# Remove any previously mounted AuthoredRig
	var prev := visual.get_node_or_null("AuthoredRig")
	if prev != null:
		prev.queue_free()

	# Instantiate and mount
	var rig := packed.instantiate()
	rig.name = "AuthoredRig"
	visual.add_child(rig)

	# Wire EntityAnimator to the authored AnimationPlayer
	var animator := entity.get_node_or_null("Animator") as EntityAnimator
	if animator != null:
		var anim_player := rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if anim_player != null:
			animator.set_visual_root(rig)
			# The EntityAnimator detects the AnimationPlayer in set_visual_root
			# and suppresses procedural tweens automatically.

	return true

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
	var rig := visual.get_node_or_null("AuthoredRig")
	if rig == null:
		return

	for socket_id in socket_map:
		var bone_name : String = socket_map[socket_id]
		# Find socket node
		var socket := _find_socket(entity, socket_id)
		if socket == null:
			continue
		# Find bone node in rig
		var bone := rig.find_child(bone_name, true, false)
		if bone == null:
			continue
		# Reparent socket under bone, keeping world transform
		var world_xform := socket.global_transform
		socket.get_parent().remove_child(socket)
		bone.add_child(socket)
		socket.global_transform = world_xform

static func _find_socket(entity: Node3D, socket_id: String) -> Node:
	for child in entity.get_children():
		if child.get("socket_id") == socket_id:
			return child
	return _find_socket_recursive(entity, socket_id)

static func _find_socket_recursive(node: Node, socket_id: String) -> Node:
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
		var path := MODEL_BASE_PATH + p + ".glb"
		if ResourceLoader.exists(path):
			_loaded[p] = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE)
		else:
			_loaded[p] = null
