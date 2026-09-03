extends Node
class_name PackCoordinator

## === Pack AI Coordinator ===
## Singleton/autoload blackboard for Hushling group behaviour.
## Enemies register themselves on spawn and de-register on death.
## Each physics tick they pull their assigned role from the board.
##
## Roles
## ─────
##   ATTACKER  — up to max_concurrent_attackers may close and strike at once.
##               An enemy becomes an attacker when it lunges.
##   FLANKER   — 2 designated enemies approach from angles > 90° from current
##               attacker(s) to prevent the player from trivially kiting.
##   ORBITER   — all remaining enemies hold at orbit distance and feint.
##
## Flank arc assignment
## ────────────────────
##   The coordinator divides the 360° around the player into equal arcs,
##   one per registered enemy. Each enemy is given a target bearing
##   (world-space angle from player) that is updated each frame.
##   Attackers ignore their arc and charge directly.
##   Flankers receive arcs on the player's sides (±60°–±120°).
##   Orbiters fill the remainder, evenly spaced.
##
## Telegraph sync
## ──────────────
##   When one enemy begins its lunge telegraph, the coordinator notifies
##   all other attackers to delay their own telegraphs by sync_delay,
##   preventing overlapping simultaneous attacks.
##
## Usage
##   Add PackCoordinator to AutoLoad as "PackCoordinator" in project.godot, OR
##   instantiate it in world_manager.gd and pass a reference to each enemy.
##
##   In Hushling._ready():
##       PackCoordinator.register(self)
##   In Hushling.die() / queue_free():
##       PackCoordinator.unregister(self)
##   In Hushling._update_pattern():
##       var role = PackCoordinator.get_role(self)
##       var arc  = PackCoordinator.get_target_arc(self)   # radians from +Z
##       if role == PackCoordinator.Role.ATTACKER: ...

signal attacker_changed(new_attacker: Node3D)
signal telegraph_started(attacker: Node3D, delay: float)

enum Role { ORBITER, FLANKER, ATTACKER }

## Maximum enemies attacking simultaneously (not counting flankers feinting)
@export var max_concurrent_attackers : int = 2
## Seconds an enemy must wait after another enemy's telegraph before it can lunge
@export var sync_delay               : float = 0.55
## Angle (radians) within which an enemy is considered "in front of player"
@export var front_arc                : float = PI * 0.5
## Minimum arc separation between two orbiting enemies (radians)
@export var min_orbit_sep            : float = 0.45

# Internal state
var _members   : Array[Node3D] = []
var _roles     : Dictionary   = {}   # Node3D → Role
var _arcs      : Dictionary   = {}   # Node3D → float (target bearing, radians)
var _attack_lock_until : Dictionary = {}  # Node3D → int (msec)
var _last_telegraph_msec : int = -9999

var _player    : Node3D = null

func _ready() -> void:
	set_process(true)

func _process(_delta: float) -> void:
	_player = _find_player()
	if _player == null or _members.is_empty():
		return
	_assign_roles()
	_assign_arcs()

# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

func register(enemy: Node3D) -> void:
	if enemy in _members:
		return
	_members.append(enemy)
	_roles[enemy]            = Role.ORBITER
	_arcs[enemy]             = 0.0
	_attack_lock_until[enemy] = 0

func unregister(enemy: Node3D) -> void:
	_members.erase(enemy)
	_roles.erase(enemy)
	_arcs.erase(enemy)
	_attack_lock_until.erase(enemy)

## Returns the current role assigned to this enemy.
func get_role(enemy: Node3D) -> Role:
	return _roles.get(enemy, Role.ORBITER)

## Returns the target bearing (radians, world-space from +Z) this enemy
## should aim for when circling the player.
func get_target_arc(enemy: Node3D) -> float:
	return _arcs.get(enemy, 0.0)

## Returns the Vector3 world position this enemy should target to reach
## its assigned arc position at the given orbit_distance from the player.
func get_arc_position(enemy: Node3D, orbit_distance: float) -> Vector3:
	if _player == null:
		return enemy.global_position
	var ang := _arcs.get(enemy, 0.0)
	return _player.global_position + Vector3(sin(ang), 0.0, cos(ang)) * orbit_distance

## Returns true if this enemy is allowed to start its attack lunge right now.
## Enforces max_concurrent_attackers and sync_delay.
func can_attack(enemy: Node3D) -> bool:
	if _roles.get(enemy, Role.ORBITER) == Role.ORBITER:
		return false
	var now := Time.get_ticks_msec()
	if now < _attack_lock_until.get(enemy, 0):
		return false
	# Count currently active attackers
	var active := 0
	for m in _members:
		if is_instance_valid(m) and _is_actively_attacking(m):
			active += 1
	return active < max_concurrent_attackers

## Call this when an enemy begins its lunge telegraph.
## Notifies other enemies to stagger their attacks.
func notify_telegraph(attacker: Node3D) -> void:
	var now := Time.get_ticks_msec()
	_last_telegraph_msec = now
	# Lock all other potential attackers for sync_delay
	for m in _members:
		if m == attacker or not is_instance_valid(m):
			continue
		var delay_ms := int(sync_delay * 1000.0 * randf_range(0.85, 1.15))
		_attack_lock_until[m] = now + delay_ms
	telegraph_started.emit(attacker, sync_delay)

# ─────────────────────────────────────────────────────────────────────────────
# Role assignment
# ─────────────────────────────────────────────────────────────────────────────

func _assign_roles() -> void:
	# Prune dead members
	_members = _members.filter(func(m): return is_instance_valid(m))

	var player_pos := _player.global_position
	var count      := _members.size()
	if count == 0:
		return

	# Sort by distance to player (closest first → most likely attacker)
	_members.sort_custom(func(a, b):
		return a.global_position.distance_squared_to(player_pos) \
			 < b.global_position.distance_squared_to(player_pos))

	var attacker_slots := min(max_concurrent_attackers, count)
	var flanker_slots  := min(2, count - attacker_slots)

	for i in count:
		var m := _members[i]
		if i < attacker_slots:
			_roles[m] = Role.ATTACKER
		elif i < attacker_slots + flanker_slots:
			_roles[m] = Role.FLANKER
		else:
			_roles[m] = Role.ORBITER

# ─────────────────────────────────────────────────────────────────────────────
# Arc assignment
# ─────────────────────────────────────────────────────────────────────────────

func _assign_arcs() -> void:
	if _player == null:
		return

	var player_pos := _player.global_position
	# Player's forward arc center (based on player facing)
	var player_fwd := -_player.global_transform.basis.z
	var base_ang   := atan2(player_fwd.x, player_fwd.z)  # radians

	var attackers  : Array = []
	var flankers   : Array = []
	var orbiters   : Array = []

	for m in _members:
		if not is_instance_valid(m):
			continue
		match _roles.get(m, Role.ORBITER):
			Role.ATTACKER: attackers.append(m)
			Role.FLANKER:  flankers.append(m)
			Role.ORBITER:  orbiters.append(m)

	# Attackers: aim directly at player (arc = bearing from player → behind player)
	for m in attackers:
		var dir_to_enemy := m.global_position - player_pos
		_arcs[m] = atan2(dir_to_enemy.x, dir_to_enemy.z)

	# Flankers: ±90° from the base angle (player's sides)
	var flank_angles := [base_ang + PI * 0.5, base_ang - PI * 0.5]
	for i in flankers.size():
		_arcs[flankers[i]] = flank_angles[i % 2]

	# Orbiters: evenly spaced around remaining arc, minimum separation enforced
	if not orbiters.is_empty():
		var step := TAU / float(orbiters.size())
		# Start orbiters from behind the player to avoid overlapping flankers
		var orbit_start := base_ang + PI
		for i in orbiters.size():
			var candidate := orbit_start + step * float(i)
			# Ensure minimum separation from flankers
			var too_close := false
			for fa in flank_angles:
				var diff := abs(wrapf(candidate - fa, -PI, PI))
				if diff < min_orbit_sep:
					candidate += min_orbit_sep * sign(candidate - fa)
					too_close = true
					break
			_arcs[orbiters[i]] = candidate

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node3D

func _is_actively_attacking(enemy: Node3D) -> bool:
	if not enemy.has_method("get") or enemy.get("current_pattern") == null:
		return false
	var p := int(enemy.get("current_pattern"))
	# Pattern enum values for attacking states: LUNGE=2, WINDUP=3, CHARGE_RUSH=7, SPECIAL_ACTIVE=13
	return p in [2, 3, 7, 13]
