class_name MagicVfxProfiles
extends RefCounted

## Reusable, mobile-safe GPUParticles3D configuration for Embervale spells.
## The profiles intentionally use one shared shader and small particle counts.
## They are visual-only; damage, targeting, and gameplay timing remain in the
## calling attack system.

const MAGIC_SHADER_PATH := "res://assets/shaders/magic_vfx.gdshader"

const PROFILES := {
    "sword_slash": {
        "color": Color(1.0, 0.55, 0.14, 1.0),
        "edge": Color(1.0, 0.94, 0.52, 1.0),
        "amount": 8,
        "lifetime": 0.24,
        "scale": 0.20,
        "spread": 12.0,
        "velocity": 2.0,
        "gravity": Vector3(0, -0.8, 0),
        "intensity": 1.7,
        "streak": 1.4,
    },
    "staff_orb": {
        "color": Color(0.32, 0.78, 1.0, 1.0),
        "edge": Color(0.84, 0.96, 1.0, 1.0),
        "amount": 7,
        "lifetime": 0.42,
        "scale": 0.24,
        "spread": 7.0,
        "velocity": 1.8,
        "gravity": Vector3(0, 0.0, 0),
        "intensity": 2.3,
        "streak": 0.8,
    },
    "fire_burst": {
        "color": Color(1.0, 0.24, 0.04, 1.0),
        "edge": Color(1.0, 0.84, 0.30, 1.0),
        "amount": 18,
        "lifetime": 0.46,
        "scale": 0.18,
        "spread": 48.0,
        "velocity": 4.4,
        "gravity": Vector3(0, -3.2, 0),
        "intensity": 2.8,
        "streak": 1.1,
    },
    "frost_burst": {
        "color": Color(0.20, 0.68, 1.0, 1.0),
        "edge": Color(0.84, 0.98, 1.0, 1.0),
        "amount": 16,
        "lifetime": 0.52,
        "scale": 0.17,
        "spread": 55.0,
        "velocity": 3.8,
        "gravity": Vector3(0, -1.1, 0),
        "intensity": 2.5,
        "streak": 0.9,
    },
    "shock_chain": {
        "color": Color(0.52, 0.42, 1.0, 1.0),
        "edge": Color(0.92, 0.82, 1.0, 1.0),
        "amount": 14,
        "lifetime": 0.38,
        "scale": 0.15,
        "spread": 70.0,
        "velocity": 5.0,
        "gravity": Vector3(0, 0.5, 0),
        "intensity": 2.9,
        "streak": 1.7,
    },
    "nature_reaction": {
        "color": Color(0.22, 1.0, 0.42, 1.0),
        "edge": Color(0.84, 1.0, 0.58, 1.0),
        "amount": 16,
        "lifetime": 0.60,
        "scale": 0.15,
        "spread": 62.0,
        "velocity": 2.8,
        "gravity": Vector3(0, 1.0, 0),
        "intensity": 2.15,
        "streak": 0.75,
    },
    "boss_transition": {
        "color": Color(1.0, 0.20, 0.06, 1.0),
        "edge": Color(1.0, 0.78, 0.34, 1.0),
        "amount": 26,
        "lifetime": 0.90,
        "scale": 0.22,
        "spread": 80.0,
        "velocity": 3.6,
        "gravity": Vector3(0, 2.0, 0),
        "intensity": 2.7,
        "streak": 1.0,
    },
}

static func create_particles(profile_name: String, parent: Node3D,
        local_position: Vector3 = Vector3.ZERO, mobile: bool = false) -> GPUParticles3D:
    if parent == null:
        return null
    var profile: Dictionary = PROFILES.get(profile_name, PROFILES["staff_orb"])
    var particles := GPUParticles3D.new()
    particles.name = "MagicVFX_%s" % profile_name
    particles.position = local_position
    particles.amount = int(profile.amount) if not mobile else maxi(4, int(profile.amount) / 2)
    particles.lifetime = float(profile.lifetime)
    particles.one_shot = true
    particles.explosiveness = 0.86
    particles.randomness = 0.28
    particles.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
    particles.draw_pass_1 = _make_quad(float(profile.scale), profile)
    particles.process_material = _make_process_material(profile)
    parent.add_child(particles)
    particles.emitting = true
    particles.finished.connect(particles.queue_free)
    return particles

static func create_trail(profile_name: String, parent: Node3D,
        mobile: bool = false) -> GPUParticles3D:
    var particles := create_particles(profile_name, parent, Vector3.ZERO, mobile)
    if particles:
        particles.one_shot = false
        particles.explosiveness = 0.0
        particles.lifetime = minf(particles.lifetime, 0.34)
    return particles

static func _make_quad(size: float, profile: Dictionary) -> QuadMesh:
    var quad := QuadMesh.new()
    quad.size = Vector2(size, size)
    quad.orientation = PlaneMesh.FACE_Z
    var material := ShaderMaterial.new()
    material.shader = load(MAGIC_SHADER_PATH)
    material.set_shader_parameter("core_color", profile.color)
    material.set_shader_parameter("edge_color", profile.edge)
    material.set_shader_parameter("intensity", float(profile.intensity))
    material.set_shader_parameter("streak_strength", float(profile.streak))
    material.set_shader_parameter("swirl_strength", 0.32)
    material.set_shader_parameter("depth_fade_distance", 0.0)
    quad.material = material
    return quad

static func _make_process_material(profile: Dictionary) -> ParticleProcessMaterial:
    var process := ParticleProcessMaterial.new()
    process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    process.emission_sphere_radius = 0.08
    process.direction = Vector3(0, 1, 0)
    process.spread = float(profile.spread)
    process.initial_velocity_min = float(profile.velocity) * 0.72
    process.initial_velocity_max = float(profile.velocity) * 1.18
    process.gravity = profile.gravity
    process.scale_min = 0.62
    process.scale_max = 1.18
    process.damping_min = 0.7
    process.damping_max = 1.8
    process.color = Color(1, 1, 1, 0.92)
    return process
