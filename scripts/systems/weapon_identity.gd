extends RefCounted
class_name WeaponIdentity

## === Per-weapon presentation identity ===
## Gameplay never reads this file. It only decides how a weapon *feels* in the
## hand: trail shape, trail palette, and the accent used for hand glow and
## impact garnish. Style drives the motion and element drives the color, so a
## frost cleaver and a fire cleaver share a silhouette but never a look — which
## is what stops every weapon reading as the same ember puff.

const PROFILES: Dictionary = {
	"slash": {
		"amount": 40, "lifetime": 0.26, "size": 0.15, "radius": 0.20,
		"velocity_min": 0.20, "velocity_max": 1.10, "spread": 150.0,
		"gravity": Vector3(0.0, -0.6, 0.0), "glow": 1.0,
	},
	"blunt": {
		"amount": 26, "lifetime": 0.34, "size": 0.24, "radius": 0.26,
		"velocity_min": 0.10, "velocity_max": 0.55, "spread": 180.0,
		"gravity": Vector3(0.0, -2.4, 0.0), "glow": 0.85,
	},
	"magic": {
		"amount": 46, "lifetime": 0.42, "size": 0.12, "radius": 0.24,
		"velocity_min": 0.05, "velocity_max": 0.45, "spread": 180.0,
		"gravity": Vector3(0.0, 0.5, 0.0), "glow": 1.15,
	},
}

## Elements the weapon data actually uses. Missing entries fall back to ember
## rather than white, so an unmapped element never reads as a placeholder.
const ELEMENT_COLORS: Dictionary = {
	"fire": Color(1.0, 0.55, 0.16),
	"frost": Color(0.55, 0.85, 1.0),
	"shock": Color(0.98, 0.94, 0.55),
	"nature": Color(0.45, 0.85, 0.45),
	"shadow": Color(0.62, 0.42, 0.95),
	"water": Color(0.35, 0.68, 0.95),
	"arcane": Color(0.82, 0.52, 1.0),
	"thunder": Color(0.85, 0.92, 1.0),
}

static func profile_for(style: String) -> Dictionary:
	var key := style.strip_edges().to_lower()
	var chosen: Variant = PROFILES.get(key, PROFILES["slash"])
	return (chosen as Dictionary).duplicate()

static func element_color(element: String) -> Color:
	var key := element.strip_edges().to_lower()
	var value: Variant = ELEMENT_COLORS.get(key, Color(1.0, 0.74, 0.30))
	return value as Color

## Trail ramp: a hot core that cools to nothing, so the arc reads as motion
## rather than a static glow.
static func trail_ramp(element: String) -> Gradient:
	var accent := element_color(element)
	var hot := accent.lightened(0.45)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(hot.r, hot.g, hot.b, 0.95))
	ramp.set_color(1, Color(accent.r, accent.g, accent.b, 0.0))
	return ramp

## Applies one profile to an existing trail, so a weapon swap retunes the arc
## in place instead of rebuilding particle nodes mid-fight.
static func apply_to_trail(trail: GPUParticles3D, style: String, element: String) -> void:
	if trail == null or not is_instance_valid(trail):
		return
	var profile := profile_for(style)
	trail.amount = int(profile.get("amount", 34))
	trail.lifetime = float(profile.get("lifetime", 0.28))
	var proc := trail.process_material as ParticleProcessMaterial
	if proc == null:
		return
	proc.spread = float(profile.get("spread", 180.0))
	proc.initial_velocity_min = float(profile.get("velocity_min", 0.1))
	proc.initial_velocity_max = float(profile.get("velocity_max", 0.6))
	proc.gravity = profile.get("gravity", Vector3.ZERO) as Vector3
	proc.scale_min = float(profile.get("size", 0.15)) * 3.4
	proc.scale_max = float(profile.get("size", 0.15)) * 7.0
	proc.emission_sphere_radius = float(profile.get("radius", 0.22))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = trail_ramp(element)
	proc.color_ramp = ramp_tex
