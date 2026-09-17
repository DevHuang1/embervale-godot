extends Node
class_name MobileLodController

## === Mobile Performance / LOD Controller ===
##
## Manages visibility and geometry complexity for all procedural nodes
## (overkill boss, hushling graphics, biome builders) to stay within
## mobile GPU budget.
##
## Strategy:
##   TIER 0 (< 12m from camera): full geometry — all nodes active
##   TIER 1 (12–22m):            reduce particle counts, hide micro-detail
##   TIER 2 (22–35m):            hide secondary meshes, keep silhouette only
##   TIER 3 (> 35m):             hide entirely (off-screen or very distant)
##
## Per-entity budget:
##   Boss  : max 48 MeshInstance3D nodes visible at full LOD; 16 at TIER 2
##   Enemy : max 12 MeshInstance3D nodes at full LOD; 4 at TIER 2
##   Biome : max 80 static meshes visible in any frame; Verlet chains disabled > TIER 1
##
## Usage:
##   var lod := MobileLodController.new()
##   add_child(lod)
##   lod.setup(camera_node)
##   lod.register_boss(overkill_boss_node)
##   lod.register_enemy(overkill_hushling_node)
##   lod.register_biome(biome_builder_node)

const TIER0_DIST : float = 12.0
const TIER1_DIST : float = 22.0
const TIER2_DIST : float = 35.0

const BOSS_FULL_LIMIT  : int = 48
const BOSS_MID_LIMIT   : int = 16
const ENEMY_FULL_LIMIT : int = 12
const ENEMY_MID_LIMIT  : int = 4
const BIOME_FULL_LIMIT : int = 80
const BIOME_MID_LIMIT  : int = 32

# Update interval — checking every physics frame is too expensive on mobile
const UPDATE_EVERY_N_FRAMES : int = 6

## Opt-in micro-detail: any descendant in this group is hidden past TIER 1.
## Explicit opt-in keeps the detail LOD from culling silhouettes it cannot
## judge (mesh order inside a rig is not a reliable "importance" signal).
const MICRO_DETAIL_GROUP : String = "lod_micro"

var _camera    : Camera3D = null
var _bosses    : Array[Node3D] = []
var _enemies   : Array[Node3D] = []
var _biomes    : Array[Node3D] = []
var _frame     : int = 0

# Cache of all MeshInstance3D children per registered node
var _boss_meshes   : Dictionary = {}   # Node → Array[MeshInstance3D]
var _enemy_meshes  : Dictionary = {}
var _biome_meshes  : Dictionary = {}

# Distance detail LOD: presentation-only (shadows + opted-in micro meshes).
# State is keyed by instance id, never by object reference, so a freed entry
# can always be pruned without touching an invalid instance.
var _detail      : Array[Node3D] = []
var _detail_ids  : Array[int] = []
var _detail_state : Dictionary = {}   # instance id → {meshes, shadows, micro}

# Particle systems per registered node (for count reduction)
var _boss_particles  : Dictionary = {}
var _biome_particles : Dictionary = {}
var _biome_sbs       : Dictionary = {}  # Node → SpringBoneSystem

func setup(camera: Camera3D) -> void:
	_camera = camera

func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame % UPDATE_EVERY_N_FRAMES != 0:
		return
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
	if _camera == null:
		return
	var cam_pos := _camera.global_position
	for boss in _bosses:
		if is_instance_valid(boss):
			_update_boss_lod(boss, cam_pos)
	for enemy in _enemies:
		if is_instance_valid(enemy):
			_update_enemy_lod(enemy, cam_pos)
	for biome in _biomes:
		if is_instance_valid(biome):
			_update_biome_lod(biome, cam_pos)
	_prune_detail()
	for detail in _detail:
		if is_instance_valid(detail):
			_update_detail_lod(detail, cam_pos)

# ─────────────────────────────────────────────────────────────────────────────
# Registration
# ─────────────────────────────────────────────────────────────────────────────

func register_boss(node: Node3D) -> void:
	if node in _bosses:
		return
	_bosses.append(node)
	_boss_meshes[node]   = _collect_meshes(node)
	_boss_particles[node] = _collect_particles(node)

func register_enemy(node: Node3D) -> void:
	if node in _enemies:
		return
	_enemies.append(node)
	_enemy_meshes[node] = _collect_meshes(node)

func register_biome(node: Node3D) -> void:
	if node in _biomes:
		return
	_biomes.append(node)
	_biome_meshes[node]   = _collect_meshes(node)
	_biome_particles[node] = _collect_particles(node)
	# Find SpringBoneSystem children
	for child in node.get_children():
		if child is SpringBoneSystem:
			_biome_sbs[node] = child
			break

## Register a bounded, self-contained prop or actor for presentation LOD.
## Only shadow casting is tiered automatically; mesh culling applies solely to
## descendants the content explicitly tags with MICRO_DETAIL_GROUP. Freed
## entries are pruned by the update loop, so any despawn path is safe.
func register_detail(node: Node3D) -> void:
	if node == null:
		return
	var id := node.get_instance_id()
	if _detail_state.has(id):
		return
	var meshes := _collect_meshes(node)
	var shadows : Dictionary = {}
	for mesh in meshes:
		shadows[mesh] = mesh.cast_shadow
	var micros : Array[Node3D] = []
	for child in node.find_children("*", "Node3D", true, false):
		if child.is_in_group(MICRO_DETAIL_GROUP):
			micros.append(child as Node3D)
	_detail_state[id] = {"meshes": meshes, "shadows": shadows, "micro": micros}
	_detail_ids.append(id)
	_detail.append(node)

## Detail-LOD state for a registered node (empty when it is not registered).
func detail_state(node: Node3D) -> Dictionary:
	if node == null:
		return {}
	return _detail_state.get(node.get_instance_id(), {})

func registered_detail_count() -> int:
	return _detail_state.size()

func _prune_detail() -> void:
	var index := _detail.size() - 1
	while index >= 0:
		if not is_instance_valid(_detail[index]):
			_detail_state.erase(_detail_ids[index])
			_detail_ids.remove_at(index)
			_detail.remove_at(index)
		index -= 1

func _update_detail_lod(node: Node3D, cam_pos: Vector3) -> void:
	var dist := node.global_position.distance_to(cam_pos)
	var near := dist <= TIER1_DIST
	var state := detail_state(node)
	var meshes : Array = state.get("meshes", [])
	var shadows : Dictionary = state.get("shadows", {})
	for mesh in meshes:
		if not is_instance_valid(mesh):
			continue
		var original : int = int(shadows.get(mesh, GeometryInstance3D.SHADOW_CASTING_SETTING_ON))
		mesh.cast_shadow = original if near \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for micro in state.get("micro", []):
		if is_instance_valid(micro):
			(micro as Node3D).visible = near

func unregister(node: Node3D) -> void:
	_bosses.erase(node)
	_enemies.erase(node)
	_biomes.erase(node)
	_boss_meshes.erase(node)
	_enemy_meshes.erase(node)
	_biome_meshes.erase(node)
	_boss_particles.erase(node)
	_biome_particles.erase(node)
	_biome_sbs.erase(node)
	var detail_id := node.get_instance_id()
	_detail_state.erase(detail_id)
	var detail_index := _detail_ids.find(detail_id)
	if detail_index >= 0:
		_detail_ids.remove_at(detail_index)
		_detail.remove_at(detail_index)

# ─────────────────────────────────────────────────────────────────────────────
# LOD updates
# ─────────────────────────────────────────────────────────────────────────────

func _update_boss_lod(boss: Node3D, cam_pos: Vector3) -> void:
	var dist := boss.global_position.distance_to(cam_pos)
	var meshes : Array = _boss_meshes.get(boss, [])
	var particles : Array = _boss_particles.get(boss, [])

	if dist > TIER2_DIST:
		# TIER 3: show only 8 core meshes (silhouette)
		_show_n(meshes, 8)
		_set_particles_active(particles, false)
	elif dist > TIER1_DIST:
		# TIER 2: 16 meshes, no particles
		_show_n(meshes, BOSS_MID_LIMIT)
		_set_particles_active(particles, false)
	elif dist > TIER0_DIST:
		# TIER 1: 32 meshes, reduced particles
		_show_n(meshes, 32)
		_set_particle_amounts(particles, 0.4)
	else:
		# TIER 0: full detail
		_show_all(meshes)
		_set_particles_active(particles, true)
		_set_particle_amounts(particles, 1.0)

func _update_enemy_lod(enemy: Node3D, cam_pos: Vector3) -> void:
	var dist := enemy.global_position.distance_to(cam_pos)
	var meshes : Array = _enemy_meshes.get(enemy, [])

	if dist > TIER2_DIST:
		_show_n(meshes, 2)  # core gem + body only
	elif dist > TIER1_DIST:
		_show_n(meshes, ENEMY_MID_LIMIT)
	elif dist > TIER0_DIST:
		_show_n(meshes, 8)
	else:
		_show_all(meshes)

func _update_biome_lod(biome: Node3D, cam_pos: Vector3) -> void:
	var dist := biome.global_position.distance_to(cam_pos)
	var meshes   : Array = _biome_meshes.get(biome, [])
	var particles : Array = _biome_particles.get(biome, [])
	var sbs      : SpringBoneSystem = _biome_sbs.get(biome, null)

	if dist > TIER2_DIST:
		# Hide most biome geometry — just the boundary/ground
		_show_n_from_back(meshes, 6)
		_set_particles_active(particles, false)
		if sbs != null:
			sbs.set_process(false)
	elif dist > TIER1_DIST:
		_show_n(meshes, BIOME_MID_LIMIT)
		_set_particles_active(particles, false)
		if sbs != null:
			sbs.set_process(false)
	elif dist > TIER0_DIST:
		_show_n(meshes, BIOME_FULL_LIMIT)
		_set_particle_amounts(particles, 0.5)
		if sbs != null:
			sbs.set_process(true)
	else:
		_show_all(meshes)
		_set_particles_active(particles, true)
		_set_particle_amounts(particles, 1.0)
		if sbs != null:
			sbs.set_process(true)

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

func _collect_meshes(root: Node) -> Array[MeshInstance3D]:
	var result : Array[MeshInstance3D] = []
	_collect_meshes_recursive(root, result)
	return result

func _collect_meshes_recursive(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes_recursive(child, result)

func _collect_particles(root: Node) -> Array[GPUParticles3D]:
	var result : Array[GPUParticles3D] = []
	_collect_particles_recursive(root, result)
	return result

func _collect_particles_recursive(node: Node, result: Array[GPUParticles3D]) -> void:
	if node is GPUParticles3D:
		result.append(node as GPUParticles3D)
	for child in node.get_children():
		_collect_particles_recursive(child, result)

func _show_all(meshes: Array) -> void:
	for m in meshes:
		if is_instance_valid(m):
			m.visible = true

func _show_n(meshes: Array, n: int) -> void:
	# Show first N (most important, added first in build order), hide the rest
	for i in meshes.size():
		if is_instance_valid(meshes[i]):
			(meshes[i] as MeshInstance3D).visible = i < n

func _show_n_from_back(meshes: Array, n: int) -> void:
	# Show last N (ground/boundary added last in biome builders)
	var start := maxi(0, meshes.size() - n)
	for i in meshes.size():
		if is_instance_valid(meshes[i]):
			(meshes[i] as MeshInstance3D).visible = i >= start

func _set_particles_active(particles: Array, active: bool) -> void:
	for p in particles:
		if is_instance_valid(p):
			(p as GPUParticles3D).emitting = active

func _set_particle_amounts(particles: Array, fraction: float) -> void:
	for p in particles:
		if is_instance_valid(p):
			var gp := p as GPUParticles3D
			gp.emitting = true
			# Clamp amount to at least 4 so bursts still fire
			gp.amount = maxi(4, int(gp.amount * fraction))

## Returns current performance tier for a world position (0=best, 3=hidden).
func get_tier(world_pos: Vector3) -> int:
	if _camera == null:
		return 0
	var d := _camera.global_position.distance_to(world_pos)
	if d > TIER2_DIST:  return 3
	if d > TIER1_DIST:  return 2
	if d > TIER0_DIST:  return 1
	return 0
