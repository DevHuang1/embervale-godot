class_name CharacterRigLoader
extends RefCounted

## === Authored-Model Drop-In ===
## Loads an optional rigged character (assets/models/<profile>.glb or .gltf)
## and mounts it on the existing entity, hiding the procedural ghost body.
## When no model file is present every call is a silent no-op, so the
## primitive prototype stays fully playable until an artist ships real art.
##
## Profiles currently wired:
##   hero            -> assets/models/hero.fbx
##   hushling        -> assets/models/hushling.fbx
##   boss_matriarch  -> assets/models/boss_matriarch.fbx
#
# Scale per profile knocks big exports down to the proxy footprint.
const PROFILE_SCALE := {
	"hero": 0.82,
}

static func _any_model(profile: String) -> String:
	for ext in ["glb", "gltf", "fbx"]:
		var p := "res://assets/models/%s.%s" % [profile, ext]
		if ResourceLoader.exists(p):
			return p
	return ""

static func has_model(profile: String) -> bool:
	return _any_model(profile) != ""

## Try to wire a loaded model onto the entity. Returns true only when a
## model was actually mounted. Safe to call in _ready of any entity.
static func try_if_wire(entity: Node3D, profile: String) -> bool:
	if entity == null:
		return false
	var path := _any_model(profile)
	if path == "":
		return false
	var pack := load(path) as PackedScene
	if pack == null:
		return false
	var rig: Node3D = pack.instantiate() as Node3D
	if rig == null:
		return false
	rig.name = "AuthoredRig"
	# Scale the figure to sit naturally in the capsule world: profile-scale
	# handles export unit differences, then the mounted rig's AABB sizes
	# the final so feet plant at y≈0 regardless of the source art.
	var profile_scale := float(PROFILE_SCALE.get(profile, 1.0))
	rig.scale = Vector3.ONE * profile_scale
	var visual := entity.get_node_or_null("Visual")
	if visual != null:
		_hide_procedural(visual)
		visual.add_child(rig)
	else:
		entity.add_child(rig)
	# AABB feet-plant only for profiles we've tuned; untuned rigs keep
	# their authored origin exactly as before.
	if PROFILE_SCALE.has(profile):
		_fit_rig_to_ground(rig)

	# Animation bridge: imported clips, when present, become playable cues.
	var actors := rig.find_children("*", "AnimationPlayer", true, false)
	if not actors.is_empty():
		var player = actors[0] as AnimationPlayer
		player.playback_process_mode = AnimationPlayer.ANIMATION_PROCESS_PHYSICS
		var bridge := AnimTreeBridge.new()
		bridge.name = "AnimBridge"
		rig.add_child(bridge)
		bridge.bind(rig)
		# Self-driving clips: poll the host entity each frame and pick the
		# matching cue (death > attack > move > idle) without any rewiring.
		var animator := entity.get_node_or_null("Animator")
		bridge.state_provider = func() -> Dictionary:
			var st := {"dead": false, "attacking": false, "casting": false,
				"moving": false, "running": false, "dodging": false}
			var defeated = entity.get("is_defeated")
			if defeated != null:
				st.dead = bool(defeated)
			if animator != null and animator.get("anim_state") != null \
					and animator.get("mode") != null \
					and animator.get("AnimState") != null:
				var anim_state := int(animator.anim_state)
				st.attacking = anim_state == int(animator.AnimState.ATTACK)
				st.casting = st.attacking and str(animator.get("attack_style")) == "magic"
				# movement comes from the animator's own move_ratio (only
				# horizontal walking, excludes jumps/glides), not full 3D
				# velocity which would trigger walking in mid-air.
				var ratio := float(animator.get("move_ratio"))
				st.moving = ratio > 0.08
				st.running = ratio > 0.65
			if animator != null and animator.get("dodge_ratio") != null:
				st.dodging = float(animator.get("dodge_ratio")) > 0.4
			return st
		entity.set_meta("anim_bridge", bridge)
	return true

## AABB-fit a tuned profile's rig to the proxy footprint: reads the lowest
## mesh vertex (the feet) in the rig's own space and lowers the root until
## it sits at the hero's foot line, so big exports neither float nor sink
## regardless of source units or standing height.
static func _fit_rig_to_ground(rig: Node3D) -> void:
	if rig == null:
		return
	var lowest := 0.0
	var found := false
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		if not mi is MeshInstance3D:
			continue
		var mesh := mi as MeshInstance3D
		var aabb := mesh.get_aabb()
		if aabb.size.y <= 0.001:
			continue
		var local_bottom := rig.to_local(mesh.to_global(aabb.position))
		if not found or local_bottom.y < lowest:
			lowest = local_bottom.y
			found = true
	if not found or absf(lowest) < 0.001:
		return
	rig.position.y -= lowest

# Names that stay visible when a real model mounts (light + sockets + FX
# that gear, relics and the lantern still rely on).
const _KEEP_PREFIXES := [
	"Lantern", "HandSocket", "BackSocket", "WeaponSocket",
	"SwingTrail", "DrawnBlade", "EmberTrail", "MovementDust",
]

static func _hide_procedural(root: Node3D) -> void:
	for child in root.get_children():
		_hide_procedural_recursive(child)

static func _hide_procedural_recursive(node: Node) -> void:
	if node is Node3D:
		var n3 := node as Node3D
		if node is MeshInstance3D or node is GPUParticles3D:
			for p in _KEEP_PREFIXES:
				if str(n3.name).begins_with(p):
					return
			if not n3.visible:
				return
			n3.visible = false
		for child in n3.get_children():
			_hide_procedural_recursive(child)

## Bind the documented socket targets to AttachmentSocket entries by
## socket_id, so gear/relic/weapon visuals follow the model's bones.
## Each target may be a scene-tree node name or a Skeleton3D bone name;
## bone targets get a BoneAttachment3D hitched to the bone on the fly.
static func bind_sockets(entity: Node3D, mapping: Dictionary) -> void:
	if entity == null:
		return
	var rig := entity.get_node_or_null("Visual/AuthoredRig") as Node3D
	if rig == null:
		return
	for socket_id in mapping:
		var target_name: String = str(mapping[socket_id])
		var target: Node3D = _find_socket_target(rig, target_name)
		if target == null:
			continue
		var socket: AttachmentSocket = _find_attachment_socket(entity, str(socket_id))
		if socket == null:
			# Create a fresh socket posed at the rig bone
			socket = AttachmentSocket.new()
			socket.name = "Mount_%s" % str(socket_id)
			socket.socket_id = str(socket_id)
			var host := entity.get_node_or_null("Visual") as Node3D
			if host:
				host.add_child(socket)
			socket.global_transform = target.global_transform
		# Keep the socket's authored pose relative to the new target so the
		# weapon never pops: reparent first, then re-apply the delta.
		var rel := socket.global_transform * target.global_transform.affine_inverse()
		socket.reparent(target)
		socket.global_transform = rel

static func _find_attachment_socket(host: Node, socket_id: String) -> AttachmentSocket:
	var direct := host.get_node_or_null("Visual/%s" % socket_id) as AttachmentSocket
	if direct != null:
		return direct
	for cand in host.find_children("*", "AttachmentSocket", true, false):
		var s := cand as AttachmentSocket
		if s == null:
			continue
		if s.socket_id == socket_id:
			return s
	return null

## Resolve a socket target by name: first a Node3D child anywhere in the
## rig, then a Skeleton3D bone (mounting a BoneAttachment3D on the bone).
static func _find_socket_target(rig: Node3D, name: String) -> Node3D:
	for child in rig.find_children("*", "Node3D", true, false):
		if child.name == name or str(child.name).to_lower() == name.to_lower():
			return child as Node3D
	for cand in rig.find_children("*", "Skeleton3D", true, false):
		var skeleton := cand as Skeleton3D
		if skeleton == null:
			continue
		if skeleton.find_bone(name) >= 0:
			var attach := BoneAttachment3D.new()
			attach.name = "BoneAttachment_%s" % name
			attach.bone_name = name
			skeleton.add_child(attach)
			return attach as Node3D
	return null