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

var _camera    : Camera3D = null
var _bosses    : Array[Node3D] = []
var _enemies   : Array[Node3D] = []
var _biomes    : Array[Node3D] = []
var _frame     : int = 0

# Cache of all MeshInstance3D children per registered node
var _boss_meshes   : Dictionary = {}   # Node → Array[MeshInstance3D]
var _enemy_meshes  : Dictionary = {}
var _biome_meshes  : Dictionary = {}

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
