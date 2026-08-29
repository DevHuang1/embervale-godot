class_name ElementalStatus
extends Node

## Lightweight elemental payload controller for enemies. One component per enemy
## keeps status state local and avoids global per-frame scans.

const MAX_ACTIVE_STATUSES := 2
const ELEMENT_COLORS := {
    "fire": Color(1.0, 0.28, 0.08),
    "frost": Color(0.35, 0.82, 1.0),
    "shock": Color(0.72, 0.48, 1.0),
    "nature": Color(0.32, 1.0, 0.42),
}

var _effects: Dictionary = {}
var _target: Node3D

func _ready() -> void:
    _target = get_parent() as Node3D
    process_priority = -4

func _process(delta: float) -> void:
    if _target == null or not is_instance_valid(_target):
        queue_free()
        return
    for element in _effects.keys().duplicate():
        var effect: Dictionary = _effects[element]
        effect["time_left"] = float(effect.get("time_left", 0.0)) - delta
        effect["tick_left"] = float(effect.get("tick_left", 0.0)) - delta
        if effect["tick_left"] <= 0.0 and float(effect.get("tick", 0.0)) > 0.0:
            effect["tick_left"] = float(effect.get("tick", 1.0))
            _tick_damage(str(element), effect)
        if float(effect["time_left"]) <= 0.0:
            _effects.erase(element)
            CombatFx.spawn_status_pulse(_target, str(element), false)
        else:
            _effects[element] = effect

func apply(element: String, intensity: int = 1) -> void:
    if _target == null or not is_instance_valid(_target):
        return
    if not ELEMENT_COLORS.has(element):
        return
    var spec := _spec_for(element)
    var existing: Dictionary = _effects.get(element, {})
    var stacks := mini(int(existing.get("stacks", 0)) + maxi(intensity, 1), int(spec.max_stacks))
    var effect := {
        "stacks": stacks,
        "time_left": float(spec.duration),
        "tick_left": minf(float(existing.get("tick_left", spec.tick)), float(spec.tick)),
        "tick": float(spec.tick),
        "damage": int(spec.damage),
        "slow": float(spec.slow),
    }
    _effects[element] = effect
    _trim_statuses()
    CombatFx.spawn_status_pulse(_target, element, true)
    if element == "fire" and _effects.has("frost"):
        _effects.erase("frost")
        CombatFx.spawn_status_reaction(_target, "melt", Color(1.0, 0.72, 0.32))
    elif element == "frost" and _effects.has("fire"):
        _effects.erase("fire")
        CombatFx.spawn_status_reaction(_target, "shatter", Color(0.60, 0.90, 1.0))
    elif element == "shock" and _effects.has("nature"):
        CombatFx.spawn_status_reaction(_target, "overcharge", Color(0.86, 0.66, 1.0))

func movement_multiplier() -> float:
    var multiplier := 1.0
    for effect in _effects.values():
        multiplier = minf(multiplier, float(effect.get("slow", 1.0)))
    return multiplier

func has_status(element: String) -> bool:
    return _effects.has(element)

func active_status_count() -> int:
    return _effects.size()

func status_snapshot() -> Dictionary:
    var snapshot := {}
    for element in _effects:
        snapshot[element] = int(_effects[element].get("stacks", 0))
    return snapshot

func _tick_damage(element: String, effect: Dictionary) -> void:
    var damage := int(effect.get("damage", 0)) * maxi(int(effect.get("stacks", 1)), 1)
    if damage <= 0 or _target == null or not _target.has_method("take_damage"):
        return
    _target.take_damage(damage, Vector3.ZERO, false)
    FloatingText.spawn_on_entity(_target, _status_label(element), ELEMENT_COLORS[element], 0.82)
    CombatFx.spawn_status_pulse(_target, element, false)

func _status_label(element: String) -> String:
    match element:
        "fire": return "BURN"
        "frost": return "CHILL"
        "shock": return "ARC"
        "nature": return "BLOOM"
        _: return "STATUS"

func _spec_for(element: String) -> Dictionary:
    match element:
        "fire":
            return {"duration": 4.0, "tick": 0.8, "damage": 2, "slow": 1.0, "max_stacks": 3}
        "frost":
            return {"duration": 3.5, "tick": 0.0, "damage": 0, "slow": 0.68, "max_stacks": 1}
        "shock":
            return {"duration": 3.0, "tick": 0.75, "damage": 1, "slow": 0.92, "max_stacks": 2}
        "nature":
            return {"duration": 3.8, "tick": 0.95, "damage": 1, "slow": 0.82, "max_stacks": 2}
        _:
            return {"duration": 0.0, "tick": 0.0, "damage": 0, "slow": 1.0, "max_stacks": 1}

func _trim_statuses() -> void:
    while _effects.size() > MAX_ACTIVE_STATUSES:
        var oldest := str(_effects.keys()[0])
        _effects.erase(oldest)
