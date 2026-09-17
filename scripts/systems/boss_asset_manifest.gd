extends RefCounted
class_name BossAssetManifest

## Reviewable asset contract for the canonical boss roster. V2 assets are
## authored GLBs with a deterministic procedural fallback in boss_articulated.

const BOSS_PROFILES: Array[Dictionary] = [
	{"id": "whispergrove_root_harrow", "realm": "whispergrove", "weapon": "dual_root_blades", "style": "root_harrow"},
	{"id": "bramblewood_thorn_regent", "realm": "bramblewood", "weapon": "thorn_greatsword", "style": "thorn_regent"},
	{"id": "bramblewood_briar_widow", "realm": "bramblewood", "weapon": "briar_needles", "style": "briar_widow"},
	{"id": "mistfen_fogmaw", "realm": "mistfen", "weapon": "fenwheel_maw", "style": "fogmaw"},
	{"id": "heartwood_cinderhart", "realm": "heartwood", "weapon": "magma_fists", "style": "cinderhart"},
	{"id": "heartwood_ash_bellower", "realm": "heartwood", "weapon": "ash_bell_focus", "style": "ash_bellower"},
	{"id": "moonfen_tide_oracle", "realm": "moonfen", "weapon": "tide_orbs", "style": "tide_oracle"},
	{"id": "moonfen_lunar_leviathan", "realm": "moonfen", "weapon": "lunar_crescent", "style": "lunar_leviathan"},
]

const WEAPON_PROFILES: Array[Dictionary] = [
	{"id": "dual_root_blades", "boss_id": "whispergrove_root_harrow", "attachment": "WeaponL/WeaponR"},
	{"id": "thorn_greatsword", "boss_id": "bramblewood_thorn_regent", "attachment": "WeaponL/WeaponR"},
	{"id": "briar_needles", "boss_id": "bramblewood_briar_widow", "attachment": "MuzzleL/MuzzleR"},
	{"id": "fenwheel_maw", "boss_id": "mistfen_fogmaw", "attachment": "FogWheel"},
	{"id": "magma_fists", "boss_id": "heartwood_cinderhart", "attachment": "MagmaFist"},
	{"id": "ash_bell_focus", "boss_id": "heartwood_ash_bellower", "attachment": "Focus"},
	{"id": "tide_orbs", "boss_id": "moonfen_tide_oracle", "attachment": "TideOrb_0..3"},
	{"id": "lunar_crescent", "boss_id": "moonfen_lunar_leviathan", "attachment": "WeaponL/WeaponR"},
]

const MATERIAL_FAMILIES: Array[Dictionary] = [
	{"id": "boss_body_shader", "source": "res://assets/materials/entity_boss.tres", "use": "authoritative hit flash and phase tint"},
	{"id": "boss_v2_pbr", "source": "res://tools/blender/build_boss_roster_v2.py", "atlas": "res://assets/textures/bosses_v2/boss_v2_atlas.png", "orm": "res://assets/textures/bosses_v2/boss_v2_orm.png", "normal": "res://assets/textures/bosses_v2/boss_v2_normal.png", "use": "authored layered PBR body, armor, and identity surfaces"},
	{"id": "boss_procedural_fallback", "source": "res://scripts/entities/boss_articulated.gd", "use": "fallback only when the V2 GLB cannot mount"},
]

const BOSS_V2_TEXTURES: Array[String] = [
	"res://assets/textures/bosses_v2/boss_v2_atlas.png",
	"res://assets/textures/bosses_v2/boss_v2_orm.png",
	"res://assets/textures/bosses_v2/boss_v2_normal.png",
]

const VFX_FAMILIES: Array[String] = [
	"boss_telegraph", "boss_muzzle_flash", "boss_projectile_trail", "boss_ground_crack",
	"boss_thorn_burst", "boss_magma_impact", "boss_mist_burst", "boss_moon_ring",
	"boss_regen_aura", "boss_phase_shift", "boss_defeat", "boss_root_blade",
	"boss_regent_cleave", "boss_briar_mine", "boss_fog_roll", "boss_bell_wave",
	"boss_tide_glyph", "boss_lunar_breath", "boss_seed_spiral", "boss_root_rupture",
	"boss_needle_fan", "boss_petal_ring", "boss_burrow_erupt", "boss_magma_mortar",
	"boss_ash_mortar", "boss_flare_wall", "boss_bell_regen", "boss_tide_bolt",
	"boss_moon_tide_ring", "boss_oracle_split", "boss_crescent_sweep", "boss_orbit_barrage",
]

const SFX_FAMILIES: Array[String] = [
	"boss_sword", "boss_limb_slam", "boss_projectile", "boss_roll", "boss_burrow",
	"boss_flight", "boss_regen", "boss_armor_break", "boss_phase", "boss_sfx_defeat",
]

static func registry() -> Dictionary:
	var result := {"boss": {}, "prop": {}, "vfx": {}, "sfx": {}}
	for profile in BOSS_PROFILES:
		var boss_id := str(profile.get("id", ""))
		result["boss"][boss_id] = {
			"id": boss_id, "realm": str(profile.get("realm", "")),
			"scene": "res://scenes/entities/boss_articulated.tscn",
			"owner": "res://scripts/entities/boss_articulated.gd",
			"weapon_profile": str(profile.get("weapon", "")),
			"model_profile": "boss_v2_%s" % boss_id,
			"model_path": "res://assets/models/bosses_v2/boss_%s.glb" % boss_id,
			"source_path": "res://tools/blender/build_boss_roster_v2.py",
			"mobility": "articulated_layered_v2",
			"style": str(profile.get("style", "default")),
		}
	for weapon in WEAPON_PROFILES:
		var weapon_id := str(weapon.get("id", ""))
		result["prop"][weapon_id] = {
			"id": weapon_id, "owner": "res://scripts/entities/boss_articulated.gd",
			"attachment": str(weapon.get("attachment", "")),
		}
	for vfx_id in VFX_FAMILIES:
		var vfx_source := "res://scripts/systems/boss_skill_vfx.gd" \
			if str(vfx_id).begins_with("boss_") else "res://scripts/systems/combat_fx.gd"
		result["vfx"][vfx_id] = {"id": vfx_id, "source": vfx_source}
	for sfx_id in SFX_FAMILIES:
		result["sfx"][sfx_id] = {"id": sfx_id, "source": "res://scripts/autoload/audio_manager.gd"}
	return result

static func profile_for(boss_id: String) -> Dictionary:
	var canonical := str(boss_id)
	for profile in BOSS_PROFILES:
		if str(profile.get("id", "")) == canonical:
			return profile.duplicate(true)
	return {}

static func model_profile_for(boss_id: String) -> String:
	var canonical := str(boss_id)
	return "boss_v2_%s" % canonical if not profile_for(canonical).is_empty() else ""

static func model_path_for(boss_id: String) -> String:
	var canonical := str(boss_id)
	return "res://assets/models/bosses_v2/boss_%s.glb" % canonical \
		if not profile_for(canonical).is_empty() else ""

static func socket_map_for(_boss_id: String) -> Dictionary:
	return {
		"SOCKET_Hand_R": "Hand_R", "SOCKET_Hand_L": "Hand_L",
		"SOCKET_VFX_Chest": "Chest", "SOCKET_VFX_Foot_L": "Foot_L",
		"SOCKET_VFX_Foot_R": "Foot_R", "SOCKET_VFX_Muzzle_L": "Hand_L",
		"SOCKET_VFX_Muzzle_R": "Hand_R", "SOCKET_VFX_Weapon_L": "Weapon_L",
		"SOCKET_VFX_Weapon_R": "Weapon_R", "SOCKET_VFX_Crown": "Head",
	}

static func validate() -> Array[String]:
	var errors: Array[String] = []
	for texture_path in BOSS_V2_TEXTURES:
		if not ResourceLoader.exists(texture_path) and not FileAccess.file_exists(texture_path):
			errors.append("Boss V2 texture missing: %s" % texture_path)
	var records := registry()
	for category in records:
		for asset_id in records[category]:
			var record: Dictionary = records[category][asset_id]
			if str(record.get("id", "")) != str(asset_id):
				errors.append("Boss manifest id mismatch: %s/%s" % [category, asset_id])
			for path_key in ["scene", "source", "owner", "model_path", "source_path"]:
				var path := str(record.get(path_key, ""))
				if not path.is_empty() and not ResourceLoader.exists(path) \
						and not FileAccess.file_exists(path):
					errors.append("Boss manifest path missing: %s" % path)
	return errors
