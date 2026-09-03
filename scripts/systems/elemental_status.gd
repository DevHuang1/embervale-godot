extends Node
class_name ElementalStatus

## === ElementalStatus — Elemental Status Effects + Combo Reactions ===
## Attached to every entity (Hero, Hushling, BossBase) via:
##   elemental_status = preload("res://scripts/systems/elemental_status.gd").new()
##   elemental_status.name = "ElementalStatus"
##   add_child(elemental_status)
##
## Status types: fire, nature, ice, arcane, lightning, poison
##
## === Reaction table ===
##   fire    + nature    → IGNITE   : 2× DoT for 3s, visual fire overlay
##   fire    + ice       → STEAM    : AOE damage pulse + vision obscure
##   fire    + arcane    → OVERLOAD : Explosive burst, stun 0.5s
##   nature  + ice       → FROSTROOT: Root 2s + slow field
##   nature  + poison    → SPOREBLOOM: Heal-deny + spore cloud radius
##   arcane  + lightning → ARCBURST : Chain lightning to nearby enemies
##   ice     + lightning → SHATTER  : Brittle — next hit crits + knockback
##   fire    + lightning → PLASMA   : DoT ignores armor
##   poison  + arcane    → CORROSION: Reduces target armor to 0 for 4s
##
## The entity's EntityAnimator and CombatFx handle the visual output.
## Status is driven per-tick via process(), not polling.

signal status_applied(element: String, duration: float)
signal status_expired(element: String)
signal reaction_triggered(reaction: String, attacker: Node3D)

enum Element { NONE, FIRE, NATURE, ICE, ARCANE, LIGHTNING, POISON }

# Active statuses: element → { time_left, stacks, attacker }
var _active : Dictionary = {}
var _entity : Node3D = null
var _t      : float  = 0.0

# Reaction cooldown to prevent chain-triggering
var _reaction_cooldown : float = 0.0
const REACTION_CD := 0.85

func _ready() -> void:
	_entity = get_parent() as Node3D

func _process(delta: float) -> void:
	_t += delta
	_reaction_cooldown = maxf(0.0, _reaction_cooldown - delta)
	var expired := []
	for elem in _active:
		_active[elem]["time_left"] -= delta
		if _active[elem]["time_left"] <= 0.0:
			expired.append(elem)
		else:
			_tick_dot(elem, delta)
	for e in expired:
		_active.erase(e)
		status_expired.emit(e)
		_clear_shader_overlay(e)

# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

## Apply an element to this entity. Returns the reaction name if one triggered.
func apply(element: String, duration: float, attacker: Node3D = null) -> String:
	var reaction := ""

	# Check for reaction before overwriting
	if _reaction_cooldown <= 0.0:
		reaction = _check_reaction(element, attacker)

	# Stack or refresh
	if _active.has(element):
		_active[element]["time_left"] = maxf(_active[element]["time_left"], duration)
		_active[element]["stacks"]    = mini(_active[element]["stacks"] + 1, 3)
	else:
		_active[element] = { "time_left": duration, "stacks": 1, "attacker": attacker }
		status_applied.emit(element, duration)
		_apply_shader_overlay(element)

	return reaction

func clear(element: String) -> void:
	if _active.has(element):
		_active.erase(element)
		status_expired.emit(element)
		_clear_shader_overlay(element)

func clear_all() -> void:
	for e in _active.keys():
		status_expired.emit(e)
		_clear_shader_overlay(e)
	_active.clear()

func has_status(element: String) -> bool:
	return _active.has(element) and _active[element]["time_left"] > 0.0

func get_stacks(element: String) -> int:
	return int(_active.get(element, {}).get("stacks", 0))

func get_active_elements() -> Array:
	return _active.keys()

# ─────────────────────────────────────────────────────────────────────────────
# Reaction table
# ─────────────────────────────────────────────────────────────────────────────

const REACTIONS := {
	["fire",    "nature"]:    "ignite",
	["fire",    "ice"]:       "steam",
	["fire",    "arcane"]:    "overload",
	["nature",  "ice"]:       "frostroot",
	["nature",  "poison"]:    "sporebloom",
	["arcane",  "lightning"]: "arcburst",
	["ice",     "lightning"]: "shatter",
	["fire",    "lightning"]: "plasma",
	["poison",  "arcane"]:    "corrosion",
}

func _check_reaction(incoming: String, attacker: Node3D) -> String:
	for pair in REACTIONS:
		var a : String = pair[0]
		var b : String = pair[1]
		if (incoming == b and has_status(a)) or (incoming == a and has_status(b)):
			var reaction : String = REACTIONS[pair]
			_reaction_cooldown = REACTION_CD
			_trigger_reaction(reaction, attacker)
			reaction_triggered.emit(reaction, attacker)
			return reaction
	return ""

func _trigger_reaction(reaction: String, attacker: Node3D) -> void:
	if _entity == null or not is_instance_valid(_entity):
		return
	match reaction:
		"ignite":
			# 2× DoT for 3s — represented by refreshing fire with boosted stacks
			_active["fire"] = { "time_left": 3.0, "stacks": 3, "attacker": attacker }
			_fx_burst(Color(1.0, 0.42, 0.08), 12, 4.0)
		"steam":
			_deal_reaction_damage(attacker, 18)
			_fx_burst(Color(0.85, 0.85, 0.90, 0.6), 22, 2.5)
			# Clear both
			clear("fire"); clear("ice")
		"overload":
			_deal_reaction_damage(attacker, 28)
			_fx_burst(Color(1.0, 0.55, 0.80), 18, 5.5)
			_stun(0.5)
			clear("fire"); clear("arcane")
		"frostroot":
			_stun(2.0)
			_fx_burst(Color(0.45, 0.75, 1.00, 0.8), 14, 3.0)
			clear("nature"); clear("ice")
		"sporebloom":
			_fx_burst(Color(0.55, 0.85, 0.30, 0.7), 16, 3.5)
			# Heal-deny: suppress entity healing for 5s (stored as "sporebloom" pseudo-status)
			_active["sporebloom_deny"] = { "time_left": 5.0, "stacks": 1, "attacker": attacker }
			clear("nature"); clear("poison")
		"arcburst":
			_chain_lightning(attacker, 3, 6.0, 22)
			_fx_burst(Color(0.70, 0.50, 1.00), 14, 4.5)
			clear("arcane"); clear("lightning")
		"shatter":
			# Next hit crits — store as a flag
			_active["shatter_primed"] = { "time_left": 8.0, "stacks": 1, "attacker": attacker }
			_fx_burst(Color(0.60, 0.88, 1.00), 12, 3.5)
			clear("ice"); clear("lightning")
		"plasma":
			_active["fire"] = { "time_left": 5.0, "stacks": 3, "attacker": attacker }
			_active["plasma_armor_pierce"] = { "time_left": 5.0, "stacks": 1, "attacker": attacker }
			_fx_burst(Color(0.90, 0.30, 1.00), 14, 4.5)
			clear("lightning")
		"corrosion":
			_active["corrosion"] = { "time_left": 4.0, "stacks": 1, "attacker": attacker }
			_fx_burst(Color(0.45, 0.72, 0.22, 0.85), 14, 3.5)
			clear("poison"); clear("arcane")

# ─────────────────────────────────────────────────────────────────────────────
# DoT ticks
# ─────────────────────────────────────────────────────────────────────────────

const DOT_INTERVAL := 0.75

var _dot_timers : Dictionary = {}

func _tick_dot(element: String, delta: float) -> void:
	if element not in ["fire", "poison", "plasma_armor_pierce"]:
		return
	_dot_timers[element] = _dot_timers.get(element, 0.0) - delta
	if _dot_timers[element] <= 0.0:
		_dot_timers[element] = DOT_INTERVAL
		var stacks := int(_active[element].get("stacks", 1))
		var damage := 0
		match element:
			"fire":    damage = 4 * stacks
			"poison":  damage = 3 * stacks
			"plasma_armor_pierce": damage = 6 * stacks
		if damage > 0 and _entity.has_method("take_damage"):
			var attacker := _active[element].get("attacker") as Node3D
			_entity.call("take_damage", damage,
				Vector3.ZERO if attacker == null else _entity.global_position.direction_to(attacker.global_position))

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

func _deal_reaction_damage(attacker: Node3D, amount: int) -> void:
	if _entity == null or not _entity.has_method("take_damage"):
		return
	var dir := Vector3.ZERO
	if attacker != null and is_instance_valid(attacker):
		dir = _entity.global_position.direction_to(attacker.global_position) * -1.0
	_entity.call("take_damage", amount, dir)

func _stun(duration: float) -> void:
	if _entity == null:
		return
	if _entity.get("stun_timer") != null:
		_entity.set("stun_timer", maxf(float(_entity.get("stun_timer")), duration))

func _chain_lightning(attacker: Node3D, jumps: int, radius: float, damage: int) -> void:
	if _entity == null or not _entity.is_inside_tree():
		return
	var hit : Array[Node3D] = [_entity]
	var source_pos := _entity.global_position
	for _j in jumps:
		var best : Node3D = null
		var best_d := radius
		for candidate in _entity.get_tree().get_nodes_in_group("enemy"):
			if candidate in hit or not is_instance_valid(candidate):
				continue
			var d := candidate.global_position.distance_to(source_pos)
			if d < best_d:
				best_d = d
				best = candidate
		if best == null:
			break
		if best.has_method("take_damage"):
			best.call("take_damage", damage, source_pos.direction_to(best.global_position))
		_fx_burst_at(best.global_position + Vector3(0, 1, 0), Color(0.70, 0.50, 1.00), 8, 4.5)
		hit.append(best)
		source_pos = best.global_position

func _fx_burst(color: Color, amount: int, speed: float) -> void:
	if _entity == null or not _entity.is_inside_tree():
		return
	CombatFx.spawn_burst(_entity, _entity.global_position + Vector3(0, 0.8, 0),
		color, amount, speed, 0.5, 0.18)

func _fx_burst_at(pos: Vector3, color: Color, amount: int, speed: float) -> void:
	if _entity == null or not _entity.is_inside_tree():
		return
	CombatFx.spawn_burst(_entity, pos, color, amount, speed, 0.5, 0.16)

# ─────────────────────────────────────────────────────────────────────────────
# Shader overlay (drives entity_body.gdshader elemental params)
# ─────────────────────────────────────────────────────────────────────────────

const ELEMENT_COLORS := {
	"fire":      Color(1.00, 0.42, 0.08),
	"nature":    Color(0.40, 0.88, 0.28),
	"ice":       Color(0.42, 0.75, 1.00),
	"arcane":    Color(0.70, 0.30, 1.00),
	"lightning": Color(0.95, 0.95, 0.35),
	"poison":    Color(0.50, 0.85, 0.25),
}

func _apply_shader_overlay(element: String) -> void:
	if _entity == null:
		return
	var col : Color = ELEMENT_COLORS.get(element, Color(1, 1, 1))
	_set_shader_param("elemental_color",    col)
	_set_shader_param("elemental_intensity", 1.2)

func _clear_shader_overlay(element: String) -> void:
	# Only clear if no other elements remain
	if _active.is_empty():
		_set_shader_param("elemental_intensity", 0.0)

func _set_shader_param(param: String, value: Variant) -> void:
	if _entity == null:
		return
	for child in _entity.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var mat := mi.material_override as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter(param, value)
