extends RefCounted
class_name WeaponCombatProfiles

## Central presentation/commitment data for weapon families. Damage remains in
## GameState so changing animation feel cannot silently rebalance a save.
const DEFAULT_STYLE := "slash"
const PROFILES := {
	"blunt": {
		"identity": "Breaker",
		"decision": "Commit to a slower crushing arc for the strongest contact read.",
		"anticipation_ratio": 0.42,
		"contact_ratio": 0.24,
		"recovery_ratio": 0.34,
		"swing_amplitude": 0.90,
		"lunge_speed": 2.65,
		"heavy_hold_ms": 460,
		"heavy_mode": "shockwave",
		"heavy_damage_mult": 2.2,
		"impact_weight": 1.0,
		"authored_impact_fraction": 0.56,
	},
	"slash": {
		"identity": "Duelist",
		"decision": "Use the quickest commitment and a passing heavy to stay mobile.",
		"anticipation_ratio": 0.22,
		"contact_ratio": 0.33,
		"recovery_ratio": 0.45,
		"swing_amplitude": 1.0,
		"lunge_speed": 3.75,
		"heavy_hold_ms": 330,
		"heavy_mode": "passing_cut",
		"heavy_damage_mult": 2.2,
		"impact_weight": 0.72,
		"authored_impact_fraction": 0.44,
	},
	"magic": {
		"identity": "Controller",
		"decision": "Keep distance; charged attacks detonate at the marked target.",
		"anticipation_ratio": 0.52,
		"contact_ratio": 0.16,
		"recovery_ratio": 0.32,
		"swing_amplitude": 0.48,
		"lunge_speed": 0.35,
		"heavy_hold_ms": 520,
		"heavy_mode": "remote_burst",
		"heavy_damage_mult": 2.2,
		"impact_weight": 0.82,
		"authored_impact_fraction": 0.58,
	},
}

static func for_style(style: String) -> Dictionary:
	return PROFILES.get(style, PROFILES[DEFAULT_STYLE]).duplicate(true)

static func for_weapon(weapon: Dictionary) -> Dictionary:
	return for_style(str(weapon.get("style", DEFAULT_STYLE)))

static func timing_is_valid(profile: Dictionary) -> bool:
	var total := float(profile.get("anticipation_ratio", 0.0)) \
		+ float(profile.get("contact_ratio", 0.0)) \
		+ float(profile.get("recovery_ratio", 0.0))
	return absf(total - 1.0) <= 0.001
