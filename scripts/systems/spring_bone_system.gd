extends Node3D
class_name SpringBoneSystem

## === Verlet Spring Bone System ===
## Reusable secondary-motion component for tendrils, hair, cloth, root chains.
## Works on any entity — Hushling tendrils, Matriarch crown roots, Hero cape.
##
## Usage (example for Hushling tendrils):
##   var sbs := SpringBoneSystem.new()
##   add_child(sbs)
##   sbs.add_chain(tendril_root_node, 6, 0.28, Color(0.14, 1.0, 0.38))
##   # chains are driven every frame automatically.

@export var gravity          : Vector3 = Vector3(0.0, -5.8, 0.0)
@export var stiffness        : float   = 0.12   # 0=limp, 1=rigid
@export var damping          : float   = 0.88   # velocity retention per frame
@export var wind_strength    : float   = 0.22
@export var wind_frequency   : float   = 0.60
@export var floor_y          : float   = -99.0
@export var constraint_iters : int     = 3      # solver precision

const MAX_CHAINS := 64

class Chain:
	var links: Array = []   # Array[Dictionary]: pos, prev, world_anchor, len, node
	var total_length: float = 0.0
	var turbulence_phase: float = 0.0

var _chains: Array[Chain] = []
var _t: float = 0.0

func _process(delta: float) -> void:
	_t += delta
	for chain in _chains:
		_simulate(chain, delta)

# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

## Add a chain of segments hanging from anchor_node.
## Visual meshes are auto-created using mesh_radius.
func add_chain(anchor_node: Node3D, segment_count: int = 5,
		mesh_radius: float = 0.035, mesh_color: Color = Color.WHITE) -> Chain:
	if _chains.size() >= MAX_CHAINS:
		push_warning("SpringBoneSystem: MAX_CHAINS reached")
		return null

	var chain := Chain.new()
	chain.turbulence_phase = randf() * TAU
	var seg_len := 0.22
	chain.total_length = seg_len * segment_count

	for i in segment_count + 1:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = maxf(mesh_radius * (1.0 - float(i) * 0.06), 0.006)
		sm.height  = sm.radius * 2.0
		mi.mesh    = sm
		var mat    := StandardMaterial3D.new()
		mat.albedo_color = mesh_color
		mat.emission_enabled = true
		mat.emission = mesh_color
		mat.emission_energy_multiplier = 0.65
		mi.material_override = mat
		add_child(mi)

		chain.links.append({
			"node":    mi,
			"pos":     anchor_node.global_position + Vector3(0, -i * seg_len, 0),
			"prev":    anchor_node.global_position + Vector3(0, -i * seg_len, 0),
			"anchor":  i == 0,
			"anchor_node": anchor_node,
			"seg_len": seg_len,
		})
	_chains.append(chain)
	return chain

## Add a chain from an explicit world position instead of a node.
func add_chain_at(world_pos: Vector3, segment_count: int = 5,
		seg_len: float = 0.22, mesh_radius: float = 0.035,
		mesh_color: Color = Color.WHITE) -> Chain:
	if _chains.size() >= MAX_CHAINS:
		return null
	var chain := Chain.new()
	chain.turbulence_phase = randf() * TAU
	chain.total_length = seg_len * segment_count
	for i in segment_count + 1:
		var mi := MeshInstance3D.new()
		if i < segment_count:
			var sm := SphereMesh.new()
			sm.radius = maxf(mesh_radius * pow(0.88, i), 0.005)
			sm.height  = sm.radius * 2.0
			mi.mesh    = sm
		else:
			# Terminal tapered tip
			var cm := CylinderMesh.new()
			cm.bottom_radius = maxf(mesh_radius * 0.35, 0.004)
			cm.top_radius    = 0.0
			cm.height        = seg_len * 0.6
			mi.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = mesh_color
		mat.emission_enabled = true
		mat.emission = mesh_color
		mat.emission_energy_multiplier = 0.55
		mi.material_override = mat
		add_child(mi)
		chain.links.append({
			"node":     mi,
			"pos":      world_pos + Vector3(0, -i * seg_len, 0),
			"prev":     world_pos + Vector3(0, -i * seg_len, 0),
			"anchor":   i == 0,
			"world_anchor_pos": world_pos,
			"seg_len":  seg_len,
		})
	_chains.append(chain)
	return chain

## Remove all chains and free their visual nodes.
func clear_chains() -> void:
	for chain in _chains:
		for lnk in chain.links:
			if lnk.has("node") and is_instance_valid(lnk["node"]):
				lnk["node"].queue_free()
	_chains.clear()

## Apply an external impulse to the tips of all chains (e.g. on hit).
func apply_impulse(direction: Vector3, strength: float) -> void:
	for chain in _chains:
		var n := chain.links.size()
		if n < 2:
			continue
		var tail: Dictionary = chain.links[n - 1]
		tail["prev"] = tail["pos"] - direction.normalized() * strength * 0.08

# ─────────────────────────────────────────────────────────────────────────────
# Simulation
# ─────────────────────────────────────────────────────────────────────────────

func _simulate(chain: Chain, delta: float) -> void:
	var wind := _wind_at(chain, _t)
	var accel := (gravity + wind) * (delta * delta)

	# Verlet integrate
	for i in chain.links.size():
		var lnk: Dictionary = chain.links[i]
		if lnk["anchor"]:
			# Pin the anchor to its node/world position
			var apos: Vector3
			if lnk.has("anchor_node") and is_instance_valid(lnk["anchor_node"]):
				apos = (lnk["anchor_node"] as Node3D).global_position
			elif lnk.has("world_anchor_pos"):
				apos = lnk["world_anchor_pos"]
			else:
				apos = lnk["pos"]
			lnk["pos"]  = apos
			lnk["prev"] = apos
			lnk["node"].global_position = apos
			continue

		var vel := (lnk["pos"] - lnk["prev"]) * damping
		var new_pos := lnk["pos"] + vel + accel
		new_pos.y   = maxf(new_pos.y, floor_y)
		lnk["prev"]  = lnk["pos"]
		lnk["pos"]   = new_pos

	# Distance constraints (multiple iterations for stability)
	for _iter in constraint_iters:
		for i in range(1, chain.links.size()):
			var a: Dictionary = chain.links[i - 1]
			var b: Dictionary = chain.links[i]
			var diff := b["pos"] - a["pos"]
			var dist := diff.length()
			if dist < 0.00001:
				continue
			var target := b["seg_len"]
			var corr   := diff * ((dist - target) / dist) * 0.5
			# Stiffness: allow spring stretch proportional to (1-stiffness)
			var flex := 1.0 - clampf(stiffness, 0.0, 1.0)
			corr *= flex
			if not a["anchor"]:
				a["pos"] += corr
			b["pos"] -= corr

	# Apply positions to visual nodes
	for lnk in chain.links:
		if is_instance_valid(lnk["node"]):
			lnk["node"].global_position = lnk["pos"]
		# Orient each segment toward the next
	for i in range(chain.links.size() - 1):
		var a: Dictionary = chain.links[i]
		var b: Dictionary = chain.links[i + 1]
		var dir := (b["pos"] - a["pos"])
		if dir.length_squared() > 0.0001 and is_instance_valid(a["node"]):
			var basis := Basis.looking_at(-dir, Vector3.UP)
			a["node"].global_transform.basis = basis

func _wind_at(chain: Chain, t: float) -> Vector3:
	var ph := chain.turbulence_phase
	return Vector3(
		sin(t * wind_frequency + ph) * wind_strength,
		0.0,
		cos(t * wind_frequency * 0.73 + ph * 1.37) * wind_strength * 0.65)
