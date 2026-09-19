extends RefCounted
class_name MobSensing

## === Mob Sensing Contract ===
## Per-archetype perception that the shared enemy AI reads: how far a creature
## sees, how wide its vision cone is, how well it hears, how far it will chase
## away from its home anchor, and how it idles. Sight is directional and
## occlusion-checked; hearing is omnidirectional and capped by both the noise's
## own radius and the listener's hearing. Leash distance is measured from the
## spawn anchor, not from the player, so kiting can never tow a mob across the
## realm. All distances are metres and all timings seconds.

const DEFAULT_PROFILE := {
	"sight_radius": 9.0,
	"sight_fov_degrees": 140.0,
	"peripheral_radius": 2.4,
	"hearing_radius": 7.0,
	"leash_radius": 18.0,
	"wander_radius": 4.0,
	"wander_interval": 4.0,
	"alert_linger": 3.0,
}

## Reading order: radius creatures (chargers) see far through a narrow arc,
## ambushers trade sight for wide hearing, stalkers keep a near-complete field
## of view, and heavy wardens hold a short, stubborn leash.
const PROFILES := {
	"charger": {
		"sight_radius": 11.5, "sight_fov_degrees": 110.0,
		"hearing_radius": 5.5, "leash_radius": 22.0,
		"wander_radius": 5.5, "wander_interval": 3.4, "alert_linger": 2.5,
	},
	"ambusher": {
		"sight_radius": 8.0, "sight_fov_degrees": 150.0, "peripheral_radius": 3.0,
		"hearing_radius": 10.0, "leash_radius": 15.0,
		"wander_radius": 2.6, "wander_interval": 2.8, "alert_linger": 5.0,
	},
	"thorn_charger": {
		"sight_radius": 13.0, "sight_fov_degrees": 100.0,
		"hearing_radius": 6.0, "leash_radius": 24.0,
		"wander_radius": 6.0, "wander_interval": 3.0, "alert_linger": 2.0,
	},
	"mire_stalker": {
		"sight_radius": 9.5, "sight_fov_degrees": 175.0,
		"hearing_radius": 8.5, "leash_radius": 20.0,
		"wander_radius": 4.5, "wander_interval": 3.6, "alert_linger": 4.0,
	},
	"ember_warden": {
		"sight_radius": 8.5, "sight_fov_degrees": 130.0,
		"hearing_radius": 5.0, "leash_radius": 13.0,
		"wander_radius": 2.2, "wander_interval": 5.5, "alert_linger": 3.5,
	},
	"spore_weaver": {
		"sight_radius": 7.5, "sight_fov_degrees": 120.0,
		"hearing_radius": 12.0, "leash_radius": 17.0,
		"wander_radius": 3.2, "wander_interval": 4.6, "alert_linger": 3.0,
	},
	"relic_leech": {
		"sight_radius": 8.0, "sight_fov_degrees": 140.0,
		"hearing_radius": 7.5, "leash_radius": 26.0,
		"wander_radius": 5.0, "wander_interval": 4.2, "alert_linger": 4.5,
	},
	"spitter": {
		# Ranged standoff: the longest vision of the swarm, thin hearing, and a
		# short wander leash so it keeps its firing lane.
		"sight_radius": 12.0, "sight_fov_degrees": 150.0,
		"hearing_radius": 6.5, "leash_radius": 20.0,
		"wander_radius": 3.0, "wander_interval": 4.4, "alert_linger": 4.0,
	},
	"fenling": {
		"sight_radius": 10.0, "sight_fov_degrees": 155.0,
		"hearing_radius": 9.0, "leash_radius": 19.0,
		"wander_radius": 5.0, "wander_interval": 3.0, "alert_linger": 3.5,
	},
	"moonfen_fenling": {
		"sight_radius": 10.5, "sight_fov_degrees": 160.0,
		"hearing_radius": 9.5, "leash_radius": 21.0,
		"wander_radius": 5.2, "wander_interval": 2.8, "alert_linger": 3.0,
	},
	"elite": {
		"sight_radius": 13.0, "sight_fov_degrees": 180.0, "peripheral_radius": 3.2,
		"hearing_radius": 10.0, "leash_radius": 30.0,
		"wander_radius": 3.0, "wander_interval": 6.0, "alert_linger": 6.0,
	},
}

## Sane bounds every profile must respect; the relationship checks below are the
## ones a designer can plausibly get backwards.
const BOUNDS := {
	"sight_radius": [5.0, 18.0],
	"sight_fov_degrees": [60.0, 360.0],
	"peripheral_radius": [0.5, 5.0],
	"hearing_radius": [2.0, 16.0],
	"leash_radius": [8.0, 40.0],
	"wander_radius": [0.0, 12.0],
	"wander_interval": [1.0, 12.0],
	"alert_linger": [0.5, 10.0],
}

static func profile_for(archetype: String) -> Dictionary:
	var result: Dictionary = DEFAULT_PROFILE.duplicate()
	var override: Dictionary = PROFILES.get(archetype, {})
	for key in override:
		result[key] = override[key]
	return result

static func archetypes() -> Array[String]:
	var names: Array[String] = []
	for archetype in PROFILES:
		names.append(str(archetype))
	names.append("hushling")
	names.sort()
	return names

## Frontal vision cone in the XZ plane. Both vectors only need a horizontal
## component; a zero-length forward or offset never counts as seen.
static func in_sight_cone(forward: Vector3, to_target: Vector3,
		fov_degrees: float) -> bool:
	var flat_forward := Vector3(forward.x, 0.0, forward.z)
	var flat_target := Vector3(to_target.x, 0.0, to_target.z)
	if flat_forward.length_squared() < 0.0001 or flat_target.length_squared() < 0.0001:
		return false
	var cos_limit := cos(deg_to_rad(clampf(fov_degrees, 0.0, 360.0) * 0.5))
	return flat_forward.normalized().dot(flat_target.normalized()) >= cos_limit

## Hearing ignores the vision cone and folds the noise's own radius together
## with the listener's range: a loud crash reaches a hard-of-hearing warden and
## a whisper reaches nobody.
static func hears(noise_position: Vector3, noise_radius: float,
		listener_position: Vector3, hearing_radius: float) -> bool:
	if noise_radius <= 0.0:
		return false
	return noise_position.distance_to(listener_position) \
		<= minf(noise_radius, hearing_radius)

## Data contract for tests and tooling. Returns one message per violation so a
## design change cannot quietly ship an unplayable profile.
static func validate() -> Array[String]:
	var failures: Array[String] = []
	for archetype in archetypes():
		var profile := profile_for(archetype)
		for key in BOUNDS:
			var bounds: Array = BOUNDS[key]
			var value := float(profile.get(key, -1.0))
			if value < float(bounds[0]) or value > float(bounds[1]):
				failures.append("%s.%s=%s outside %s" % [archetype, key, value, bounds])
		if float(profile.peripheral_radius) >= float(profile.sight_radius):
			failures.append("%s peripheral_radius must stay inside sight_radius" % archetype)
		if float(profile.leash_radius) <= float(profile.sight_radius):
			failures.append("%s leash_radius must exceed sight_radius" % archetype)
		if float(profile.wander_radius) >= float(profile.leash_radius):
			failures.append("%s wander_radius must stay inside leash_radius" % archetype)
	return failures
