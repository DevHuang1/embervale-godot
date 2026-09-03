extends Hushling
class_name EliteHushling

## Elite Ember Warden: a durable Hushling that rejects Fire/Nature payloads
## and detonates a bounded chain reaction when defeated.

const IMMUNE_ELEMENTS := ["fire", "nature"]
const CHAIN_RADIUS := 5.8
const CHAIN_DAMAGE := 8
var _chain_triggered := false
var _elite_core: MeshInstance3D = null
var _elite_core_material: StandardMaterial3D = null

func _ready() -> void:
    max_hp = 72
    base_atk = 7
    move_speed = 2.6       # Slower than base Hushling (was 2.9)
    lunge_speed = 9.0
    burst_cooldown = 5.5
    counter_windup = 0.72
    special_cooldown = 9.0
    thorn_volley = true
    archetype = "elite"
    super._ready()
    _build_elite_core()

func apply_elemental_status(element: String, intensity: int = 1) -> void:
    if element in IMMUNE_ELEMENTS:
        var immune_color := Color(1.0, 0.58, 0.18) if element == "fire" else Color(0.42, 1.0, 0.50)
        CombatFx.spawn_status_pulse(self, element, false)
        FloatingText.spawn_on_entity(self, "IMMUNE", immune_color, 0.86)
        return
    super.apply_elemental_status(element, intensity)

func get_elemental_immunities() -> Array[String]:
    return IMMUNE_ELEMENTS.duplicate()

func take_damage(amount: int, knockback_dir: Vector3, critical: bool = false) -> void:
    super.take_damage(amount, knockback_dir, critical)
    if is_defeated:
        return
    var tier := "elite_hit" if critical or amount >= 18 else "medium"
    ImpactDirector.apply_feedback(self, tier, global_position + Vector3.UP * 0.8,
        knockback_dir, 1.0 if critical else 0.82)

func die() -> void:
    if _chain_triggered:
        return
    _chain_triggered = true
    _trigger_chain_reaction()
    super.die()

func _build_elite_core() -> void:
    var core := MeshInstance3D.new()
    core.name = "EliteCore"
    var mesh := SphereMesh.new()
    mesh.radius = 0.24
    mesh.height = 0.48
    mesh.radial_segments = 12
    mesh.rings = 6
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(1.0, 0.30, 0.08)
    material.emission_enabled = true
    material.emission = Color(1.0, 0.18, 0.03)
    material.emission_energy_multiplier = 2.0
    mesh.material = material
    core.mesh = mesh
    core.material_override = material
    core.position = Vector3(0, 0.28, 0.0)
    visual.add_child(core)
    _elite_core = core
    _elite_core_material = material
    var pulse := core.create_tween().set_loops()
    pulse.tween_property(core, "scale", Vector3.ONE * 1.18, 0.42) \
        .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    pulse.tween_property(core, "scale", Vector3.ONE * 0.88, 0.42) \
        .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _process(_delta: float) -> void:
    if _elite_core_material != null and not is_defeated:
        _elite_core_material.emission_energy_multiplier = 1.8 + 0.35 * sin(Time.get_ticks_msec() * 0.004)

func _trigger_chain_reaction() -> void:
    var reaction_color := Color(1.0, 0.40, 0.10)
    # A chain detonation is a major impact: brief time compression plus a
    # high-priority shake, both capped and reduced automatically on mobile.
    ImpactDirector.apply_feedback(self, "elemental_chain", global_position + Vector3.UP * 0.9,
        Vector3.FORWARD, 1.1)
    CombatFx.spawn_status_reaction(self, "chain", reaction_color)
    CombatFx.spawn_vibrant_trail(self, global_position + Vector3(0, 0.35, 0),
        global_position + Vector3(0, 1.25, 0), reaction_color,
        Color(1.0, 0.92, 0.42, 0.92), 4)
    for foe in get_tree().get_nodes_in_group("enemy"):
        if foe == self or not is_instance_valid(foe) or not (foe is Node3D):
            continue
        if global_position.distance_to(foe.global_position) > CHAIN_RADIUS:
            continue
        if foe.has_method("is_dead") and foe.is_dead():
            continue
        var direction := global_position.direction_to(foe.global_position)
        if foe.has_method("take_damage"):
            foe.take_damage(CHAIN_DAMAGE, direction, false)
        if foe.has_method("apply_elemental_status"):
            foe.apply_elemental_status("shock", 1)
        CombatFx.spawn_vibrant_trail(self,
            global_position + Vector3(0, 0.55, 0),
            foe.global_position + Vector3(0, 0.55, 0),
            reaction_color, Color(0.78, 0.52, 1.0, 0.9), 4)
