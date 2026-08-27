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
## Target standing heights (world units) per profile. Measured against each
## mounted rig's actual mesh AABB at runtime, so ANY source-art unit system
## (cm FBX exports included) lands at the right size — no hand-tuned
## multipliers to drift out of date.
const PROFILE_HEIGHT := {
	"hero": 1.62,
	"hushling": 0.95,
	"fenling": 0.85,
	"boss_matriarch": 3.8,
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
	var visual := entity.get_node_or_null("Visual")
	var host: Node3D = entity
	if visual != null:
		# Prefer a "Rig" wrapper (scaled assembly) so authored models inherit
		# the entity's visual_scale; fall back to Visual itself.
		var inner := visual.get_node_or_null("Rig") as Node3D
		host = inner if inner != null else visual
		_hide_procedural(visual)
	host.add_child(rig)
	# Fit measured geometry to the profile's target height and plant the
	# feet at y≈0 — independent of the source art's unit system.
	if PROFILE_HEIGHT.has(profile):
		_fit_rig(rig, float(PROFILE_HEIGHT[profile]))

	# Animation bridge: imported clips, when present, become playable cues.
	var actors := rig.find_children("*", "AnimationPlayer", true, false)
	if not actors.is_empty():
		var player = actors[0] as AnimationPlayer
		player.playback_process_mode = AnimationPlayer.ANIMATION_PROCESS_PHYSICS
		var bridge := AnimTreeBridge.new()
		bridge.name = "AnimBridge"
		rig.add_child(bridge)
		bridge.bind(rig)
		if entity.has_method("_on_authored_impact"):
			bridge.cue_impact.connect(Callable(entity, "_on_authored_impact"))
		# Self-driving clips: poll the host entity each frame and pick the
		# matching cue (death > attack > move > idle) without any rewiring.
		# Captures are weakrefs: after death the Visual reparents into a
		# TumbleCorpse while the entity frees, so raw Node captures would
		# dangle and spam "Lambda capture was freed" every frame.
		var animator := entity.get_node_or_null("Animator")
		var entity_ref: WeakRef = weakref(entity)
		var animator_ref: WeakRef = weakref(animator)
		bridge.state_provider = func() -> Dictionary:
			var e: Object = entity_ref.get_ref()
			if e == null:
				return {}
			var st := {"dead": false, "hit": false, "attacking": false, "casting": false,
				"moving": false, "running": false, "dodging": false}
			var defeated = e.get("is_defeated")
			if defeated != null:
				st.dead = bool(defeated)
			# Use public animator values/methods instead of trying to read the
			# script's enum constant through Object.get(). The old check always
			# failed for valid EntityAnimator instances, leaving imported rigs
			# stuck in their first clip.
			var anim: Object = animator_ref.get_ref()
			if anim != null and anim.get("anim_state") != null:
				var anim_state := int(anim.get("anim_state"))
				st.dead = st.dead or anim_state == int(EntityAnimator.AnimState.DEAD)
				st.hit = anim_state == int(EntityAnimator.AnimState.HIT)
				st.attacking = anim_state == int(EntityAnimator.AnimState.ATTACK)
				st.casting = st.attacking and str(anim.get("attack_style")) == "magic"
				# Movement comes from the animator's own move_ratio (only
				# horizontal walking, excludes jumps/glides), not full 3D velocity.
				var ratio := float(anim.get("move_ratio"))
				st.moving = ratio > 0.08
				st.running = ratio > 0.65
			if anim != null and anim.get("dodge_ratio") != null:
				st.dodging = float(anim.get("dodge_ratio")) > 0.4
			return st
		entity.set_meta("anim_bridge", bridge)
	return true

## Measure the rig's merged mesh AABB (in the rig's own space) and rescale
## it uniformly so the figure stands `target_height` world units tall, then
## lower it so the lowest vertex sits at y≈0. Works for any export units.
static func _fit_rig(rig: Node3D, target_height: float) -> void:
	if rig == null:
		return
	var acc := AABB()
	var first := true
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		var to_rig: Transform3D = rig.global_transform.affine_inverse() \
			* (mi as MeshInstance3D).global_transform
		var ab: AABB = to_rig * (mi as MeshInstance3D).get_aabb()
		if first:
			acc = ab
			first = false
		else:
			acc = acc.merge(ab)
	if first or acc.size.y <= 0.001:
		return
	var k := target_height / acc.size.y
	rig.scale *= k
	# Plant feet: shift so the scaled AABB bottom lands on y=0.
	rig.position.y -= acc.position.y * rig.scale.y

# Names that stay visible when a real model mounts (light + sockets + FX
# that gear, relics and the lantern still rely on).
const _KEEP_PREFIXES := [
	"Lantern", "HandSocket", "BackSocket", "WeaponSocket",
	"SwingTrail", "DrawnBlade", "EmberTrail", "MovementDust",
	"ArmorGear",
]

static func _hide_procedural(root: Node3D) -> void:
	for child in root.get_children():
		_hide_procedural_recursive(child)

static func _hide_procedural_recursive(node: Node) -> void:
	if node is Node3D:
		var n3 := node as Node3D
		# Keep-prefixed containers (sockets, armor gear, lantern) preserve
		# their ENTIRE subtree — gear and wielded weapons mount under these
		# and must survive an authored-rig mount.
		for p in _KEEP_PREFIXES:
			if str(n3.name).begins_with(p):
				return
		if node is MeshInstance3D or node is GPUParticles3D:
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
	var rig := _find_authored_rig(entity)
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
		# Hitch onto the bone keeping the CURRENT world pose (reparent
		# preserves global). Never re-derive through inverse-basis math —
		# unit-scaled skeletons (x100 armatures) collapse that to zero.
		socket.reparent(target)

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

## Locate the mounted authored rig wherever it lives (Visual or a Rig wrapper).
static func _find_authored_rig(entity: Node) -> Node3D:
	for cand in entity.find_children("AuthoredRig", "Node3D", true, false):
		return cand as Node3D
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