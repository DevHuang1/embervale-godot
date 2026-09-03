extends RefCounted
class_name BossCustomization

## === BossCustomization — Player-Personalised Boss Skin ===
## Set on BossBase.customization after the player scans a real object
## via ScanManager. Drives:
##   - idol_mesh      : a MeshInstance3D node the scan produced
##   - palette        : override body_tint + eye_glow on the boss
##   - skill          : one pooled skill dict replacing _realm_skill slot
##   - sfx_profile    : SFX preset id ("vanilla" = default cues)
##
## BossBase reads these fields directly. No methods needed.

## Scanned object mesh (can be null — boss keeps default silhouette)
var idol_mesh    : MeshInstance3D = null

## Color palette override (Color with alpha 0 = no override)
var body_tint    : Color = Color(0, 0, 0, 0)
var eye_glow     : Color = Color(0, 0, 0, 0)

## Realm skill slot override (empty dict = use default thorn rain)
## Must match the skill dict shape from GameState.WEAPON_DEFS[*].skills[*]
var skill        : Dictionary = {}

## SFX preset id — AudioManager.play_profile_cue(sfx_profile, "cast")
var sfx_profile  : String = "vanilla"

## Convenience constructor from a scan payload Dictionary
static func from_payload(payload: Dictionary) -> BossCustomization:
	var bc := BossCustomization.new()
	bc.sfx_profile = str(payload.get("sfx_profile", "vanilla"))
	if payload.has("skill") and payload["skill"] is Dictionary:
		bc.skill = payload["skill"]
	if payload.has("body_tint"):
		var t = payload["body_tint"]
		if t is Color:
			bc.body_tint = t
	if payload.has("eye_glow"):
		var e = payload["eye_glow"]
		if e is Color:
			bc.eye_glow = e
	return bc

func is_empty() -> bool:
	return idol_mesh == null and body_tint.a < 0.01 \
		and eye_glow.a < 0.01 and skill.is_empty() \
		and sfx_profile == "vanilla"
