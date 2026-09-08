extends RefCounted
class_name WeatherProfileCatalog

## Bounded atmosphere profiles. Presentation can be reduced by quality tier;
## gameplay timing, collision, and telegraphs never read these values.
const PROFILES: Dictionary = {
	"whispergrove": {"weather": "pollen_breeze", "fog_density": 0.010, "particle_cap": 18, "ambient_variation": 0.12, "low_fallback": "clear_breeze"},
	"bramblewood": {"weather": "thorn_wind", "fog_density": 0.014, "particle_cap": 16, "ambient_variation": 0.16, "low_fallback": "clear_wind"},
	"mistfen": {"weather": "reed_fog", "fog_density": 0.022, "particle_cap": 14, "ambient_variation": 0.10, "low_fallback": "thin_fog"},
	"heartwood": {"weather": "ember_drift", "fog_density": 0.012, "particle_cap": 12, "ambient_variation": 0.18, "low_fallback": "ash_still"},
	"moonfen": {"weather": "crystal_storm", "fog_density": 0.018, "particle_cap": 14, "ambient_variation": 0.20, "low_fallback": "quiet_motes"},
}

static func validate() -> Array[String]:
	var errors: Array[String] = []
	for realm_id in RealmIdentityCatalog.PROFILES:
		var profile: Dictionary = PROFILES.get(str(realm_id), {})
		if str(profile.get("weather", "")).is_empty() or str(profile.get("low_fallback", "")).is_empty():
			errors.append("Weather profile missing identity/fallback: %s" % realm_id)
		if float(profile.get("fog_density", -1.0)) < 0.0 or float(profile.get("fog_density", 1.0)) > 0.08:
			errors.append("Weather fog exceeds readability bound: %s" % realm_id)
		if int(profile.get("particle_cap", -1)) < 0 or int(profile.get("particle_cap", 99)) > 24:
			errors.append("Weather particle cap exceeds Android bound: %s" % realm_id)
		if float(profile.get("ambient_variation", -1.0)) < 0.0 or float(profile.get("ambient_variation", 1.0)) > 0.25:
			errors.append("Weather ambient variation exceeds bound: %s" % realm_id)
	return errors

static func for_realm(realm_id: String, low_quality: bool = false) -> Dictionary:
	var profile: Dictionary = (PROFILES.get(realm_id, PROFILES["bramblewood"]) as Dictionary).duplicate(true)
	if low_quality:
		profile["weather"] = profile.get("low_fallback", "clear")
		profile["particle_cap"] = mini(int(profile.get("particle_cap", 0)), 6)
		profile["ambient_variation"] = minf(float(profile.get("ambient_variation", 0.0)), 0.08)
	return profile
