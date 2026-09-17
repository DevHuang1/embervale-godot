extends RefCounted
class_name BossRosterCatalog

## Canonical data for the new articulated boss roster. The render rig is shared;
## this catalog owns the combat identity that makes each boss feel different.

const ARTICULATED_SCENE := "res://scenes/entities/boss_articulated.tscn"
## Travel speed is deliberately conservative for readable boss spacing and a
## calmer mobile combat frame. Skill timing and roll impulse remain authored
## per skill; this only scales continuous chase/orbit travel.
const BOSS_TRAVEL_SPEED_MULTIPLIER := 0.72

const CANONICAL_IDS: Array[String] = [
	"whispergrove_root_harrow",
	"bramblewood_thorn_regent",
	"bramblewood_briar_widow",
	"mistfen_fogmaw",
	"heartwood_cinderhart",
	"heartwood_ash_bellower",
	"moonfen_tide_oracle",
	"moonfen_lunar_leviathan",
]

const LEGACY_ALIASES := {
	"matriarch": "whispergrove_root_harrow",
	"hushling_matriarch": "whispergrove_root_harrow",
	"res://scripts/entities/boss_hushling_matriarch.gd": "whispergrove_root_harrow",
	"bramblewood_thornwarden": "bramblewood_thorn_regent",
	"res://scripts/entities/boss_bramblewood_thornwarden.gd": "bramblewood_thorn_regent",
	"thornhide_alpha": "bramblewood_thorn_regent",
	"rootbound_warden": "bramblewood_thorn_regent",
	"mistfen_siltcrawler": "mistfen_fogmaw",
	"fenmaw": "mistfen_fogmaw",
	"heartwood_cindercolossus": "heartwood_cinderhart",
	"cinderhart_colossus": "heartwood_cinderhart",
	"moonfen_voidweaver": "moonfen_tide_oracle",
	"moonfen_oracle": "moonfen_tide_oracle",
}

const SKILL_VFX_FAMILIES: Dictionary = {
	# Each current skill owns a visual grammar. The combat kind can still be
	# shared (projectile/area/etc.); the telegraph and impact presentation is
	# intentionally unique per skill identity.
	"root_sword_combo": "boss_root_blade", "seed_burst": "boss_seed_spiral",
	"regent_cleave": "boss_regent_cleave", "root_crash": "boss_root_rupture",
	"needle_salvo": "boss_needle_fan", "briar_mine": "boss_briar_mine",
	"widow_bloom": "boss_petal_ring", "fog_roll": "boss_fog_roll",
	"burrow_burst": "boss_burrow_erupt", "furnace_pound": "boss_magma_impact",
	"magma_mortar": "boss_magma_mortar", "ash_mortar": "boss_ash_mortar",
	"flare_wall": "boss_flare_wall", "bell_regen": "boss_bell_regen",
	"tide_bolt": "boss_tide_bolt", "moon_tide_ring": "boss_moon_tide_ring",
	"oracle_split": "boss_oracle_split", "lunar_breath": "boss_lunar_breath",
	"crescent_sweep": "boss_crescent_sweep", "orbit_barrage": "boss_orbit_barrage",
}

const DEFINITIONS := {
	"whispergrove_root_harrow": {
		"name": "ROOT HARROW",
		"title": "the Blade Beneath the Moss",
		"realm": "whispergrove",
		"scene": ARTICULATED_SCENE,
		"hp": 540, "atk": 13, "speed": 4.7, "scale": 1.0,
		"body_height": 3.8, "body_width": 1.55, "limb_style": "thorn_blades",
		"palette": [Color(0.12, 0.24, 0.15), Color(0.32, 1.0, 0.48), Color(0.82, 0.62, 0.22)],
		"movement_mode": "chase", "attack_style": "hybrid",
		"attack_range": 4.4, "chase_player": true, "can_fly": false, "can_roll": false,
		"form_count": 1, "armor_profile": [0, 2, 3, 4], "flash_level": 0.5,
		"sfx_profile": "hollow_resin",
		"skills": [
			{"id": "root_sword_combo", "kind": "sword", "cooldown": 3.8, "range": 4.8, "damage": 19, "radius": 2.8, "anticipation": 0.52, "active": 0.18, "recovery": 0.34, "sfx": "sword", "color": Color(0.50, 1.0, 0.42)},
			{"id": "seed_burst", "kind": "projectile", "cooldown": 7.0, "range": 14.0, "damage": 14, "projectile_count": 3, "spread": 0.18, "anticipation": 0.72, "active": 0.12, "recovery": 0.36, "sfx": "projectile", "color": Color(0.42, 1.0, 0.56), "element": "nature"},
		],
		"diamond_reward": 5,
		"rewards": {"xp": 260, "loot": {"hushling_thorn": 4}, "first_kill_materials": {"bramble_wood": 3, "iron_shard": 2}},
	},
	"bramblewood_thorn_regent": {
		"name": "THORN REGENT",
		"title": "the Crowned Bulwark",
		"realm": "bramblewood",
		"scene": ARTICULATED_SCENE,
		"hp": 760, "atk": 16, "speed": 2.9, "scale": 1.16,
		"body_height": 4.8, "body_width": 2.2, "limb_style": "greatsword_guard",
		"palette": [Color(0.10, 0.18, 0.08), Color(0.92, 0.42, 0.12), Color(0.34, 0.76, 0.22)],
		"movement_mode": "chase", "attack_style": "sword",
		"attack_range": 5.2, "chase_player": true, "can_fly": false, "can_roll": false,
		"form_count": 2, "armor_profile": [6, 10, 14, 18], "flash_level": 0.35,
		"sfx_profile": "hollow_resin",
		"skills": [
			{"id": "regent_cleave", "kind": "sword", "cooldown": 3.2, "range": 5.4, "damage": 26, "radius": 3.4, "anticipation": 0.76, "active": 0.22, "recovery": 0.42, "sfx": "sword", "color": Color(1.0, 0.54, 0.16)},
			{"id": "root_crash", "kind": "area", "cooldown": 8.0, "range": 8.0, "damage": 30, "radius": 4.2, "anticipation": 1.0, "active": 0.24, "recovery": 0.55, "sfx": "slam", "color": Color(0.92, 0.38, 0.10), "min_form": 1},
		],
		"diamond_reward": 7,
		"rewards": {"xp": 380, "loot": {"hushling_thorn": 6}, "first_kill_materials": {"bramble_wood": 5, "iron_shard": 4}},
	},
	"bramblewood_briar_widow": {
		"name": "BRIAR WIDOW",
		"title": "the Root-Sewn Sniper",
		"realm": "bramblewood",
		"scene": ARTICULATED_SCENE,
		"hp": 610, "atk": 15, "speed": 0.0, "scale": 1.04,
		"body_height": 4.2, "body_width": 1.75, "limb_style": "spider_needles",
		"palette": [Color(0.14, 0.08, 0.12), Color(0.96, 0.18, 0.46), Color(0.56, 0.26, 0.72)],
		"movement_mode": "stationary", "attack_style": "ranged",
		"attack_range": 18.0, "chase_player": false, "can_fly": false, "can_roll": false,
		"form_count": 3, "armor_profile": [2, 3, 4, 6], "flash_level": 0.9,
		"regen": {"uses": 2, "amount_pct": 0.10, "below_pct": 0.58, "cooldown": 19.0},
		"sfx_profile": "grave_moss",
		"skills": [
			{"id": "needle_salvo", "kind": "projectile", "cooldown": 4.5, "range": 22.0, "damage": 15, "projectile_count": 5, "spread": 0.34, "anticipation": 0.62, "active": 0.12, "recovery": 0.38, "sfx": "projectile", "color": Color(1.0, 0.26, 0.52), "element": "nature"},
			{"id": "briar_mine", "kind": "area", "cooldown": 8.0, "range": 18.0, "damage": 22, "radius": 3.0, "anticipation": 0.85, "active": 0.22, "recovery": 0.46, "sfx": "cast", "color": Color(0.72, 0.22, 0.68), "min_form": 1},
			{"id": "widow_bloom", "kind": "regen", "cooldown": 21.0, "range": 2.0, "damage": 0, "radius": 3.2, "anticipation": 1.2, "active": 0.25, "recovery": 0.5, "sfx": "regen", "color": Color(0.54, 1.0, 0.38), "min_form": 2},
		],
		"diamond_reward": 6,
		"rewards": {"xp": 340, "loot": {"hushling_thorn": 5, "spore_dust": 2}, "first_kill_materials": {"bramble_wood": 4}},
	},
	"mistfen_fogmaw": {
		"name": "FOGMAW",
		"title": "the Fenwheel",
		"realm": "mistfen",
		"scene": ARTICULATED_SCENE,
		"hp": 820, "atk": 17, "speed": 3.8, "scale": 1.12,
		"body_height": 3.2, "body_width": 2.5, "limb_style": "jaw_wheel",
		"palette": [Color(0.08, 0.18, 0.22), Color(0.28, 0.88, 1.0), Color(0.30, 0.62, 0.70)],
		"movement_mode": "roll", "attack_style": "melee",
		"attack_range": 4.2, "chase_player": true, "can_fly": false, "can_roll": true,
		"form_count": 2, "armor_profile": [7, 10, 13, 16], "flash_level": 0.45,
		"sfx_profile": "grave_moss",
		"skills": [
			{"id": "fog_roll", "kind": "roll", "cooldown": 6.8, "range": 14.0, "damage": 28, "radius": 2.8, "anticipation": 0.48, "active": 1.05, "recovery": 0.48, "roll_speed": 11.0, "sfx": "roll", "color": Color(0.30, 0.88, 1.0)},
			{"id": "burrow_burst", "kind": "area", "cooldown": 8.5, "range": 10.0, "damage": 32, "radius": 4.0, "anticipation": 0.86, "active": 0.25, "recovery": 0.52, "sfx": "burrow", "color": Color(0.20, 0.64, 0.80), "min_form": 1},
		],
		"diamond_reward": 6,
		"rewards": {"xp": 430, "loot": {"moss_tonic": 3, "fen_reed": 4}, "first_kill_materials": {"fen_reed": 4}},
	},
	"heartwood_cinderhart": {
		"name": "CINDERHART",
		"title": "the Walking Furnace",
		"realm": "heartwood",
		"scene": ARTICULATED_SCENE,
		"hp": 960, "atk": 20, "speed": 2.6, "scale": 1.2,
		"body_height": 5.2, "body_width": 2.5, "limb_style": "magma_fists",
		"palette": [Color(0.20, 0.06, 0.025), Color(1.0, 0.22, 0.035), Color(1.0, 0.64, 0.12)],
		"movement_mode": "chase", "attack_style": "hybrid",
		"attack_range": 5.0, "chase_player": true, "can_fly": false, "can_roll": false,
		"form_count": 2, "armor_profile": [8, 12, 16, 20], "flash_level": 0.7,
		"sfx_profile": "ember_glass",
		"skills": [
			{"id": "furnace_pound", "kind": "area", "cooldown": 4.4, "range": 6.0, "damage": 34, "radius": 4.0, "anticipation": 0.82, "active": 0.24, "recovery": 0.46, "sfx": "slam", "color": Color(1.0, 0.30, 0.06)},
			{"id": "magma_mortar", "kind": "projectile", "cooldown": 7.5, "range": 18.0, "damage": 27, "projectile_count": 2, "spread": 0.12, "anticipation": 0.92, "active": 0.18, "recovery": 0.48, "sfx": "projectile", "color": Color(1.0, 0.42, 0.06), "element": "fire", "min_form": 1},
		],
		"diamond_reward": 8,
		"rewards": {"xp": 520, "loot": {"emberstone": 5, "monster_core": 2}, "first_kill_materials": {"emberstone": 5}},
	},
	"heartwood_ash_bellower": {
		"name": "ASH BELLOWER",
		"title": "the Bell of Falling Fire",
		"realm": "heartwood",
		"scene": ARTICULATED_SCENE,
		"hp": 780, "atk": 18, "speed": 0.0, "scale": 1.08,
		"body_height": 4.6, "body_width": 1.95, "limb_style": "bell_caster",
		"palette": [Color(0.12, 0.075, 0.06), Color(1.0, 0.34, 0.08), Color(1.0, 0.78, 0.30)],
		"movement_mode": "stationary", "attack_style": "ranged",
		"attack_range": 20.0, "chase_player": false, "can_fly": false, "can_roll": false,
		"form_count": 3, "armor_profile": [3, 4, 5, 7], "flash_level": 1.0,
		"regen": {"uses": 2, "amount_pct": 0.08, "below_pct": 0.52, "cooldown": 22.0},
		"sfx_profile": "ember_glass",
		"skills": [
			{"id": "ash_mortar", "kind": "projectile", "cooldown": 4.2, "range": 24.0, "damage": 18, "projectile_count": 4, "spread": 0.30, "anticipation": 0.58, "active": 0.14, "recovery": 0.34, "sfx": "projectile", "color": Color(1.0, 0.44, 0.10), "element": "fire"},
			{"id": "flare_wall", "kind": "area", "cooldown": 8.5, "range": 22.0, "damage": 25, "radius": 3.6, "anticipation": 0.88, "active": 0.24, "recovery": 0.48, "sfx": "cast", "color": Color(1.0, 0.76, 0.18), "min_form": 1},
			{"id": "bell_regen", "kind": "regen", "cooldown": 24.0, "range": 2.0, "damage": 0, "radius": 3.8, "anticipation": 1.3, "active": 0.24, "recovery": 0.55, "sfx": "regen", "color": Color(1.0, 0.58, 0.18), "min_form": 2},
		],
		"diamond_reward": 8,
		"rewards": {"xp": 500, "loot": {"emberstone": 4, "moss_tonic": 2}, "first_kill_materials": {"emberstone": 4}},
	},
	"moonfen_tide_oracle": {
		"name": "TIDE ORACLE",
		"title": "the Sky Beneath the Water",
		"realm": "moonfen",
		"scene": ARTICULATED_SCENE,
		"hp": 880, "atk": 19, "speed": 2.0, "scale": 1.08,
		"body_height": 4.4, "body_width": 1.55, "limb_style": "floating_tide",
		"palette": [Color(0.05, 0.10, 0.26), Color(0.20, 0.86, 1.0), Color(0.64, 0.40, 1.0)],
		"movement_mode": "fly_stationary", "attack_style": "ranged",
		"attack_range": 22.0, "chase_player": false, "can_fly": true, "can_roll": false,
		"form_count": 3, "armor_profile": [2, 3, 5, 7], "flash_level": 1.0,
		"sfx_profile": "grave_moss",
		"skills": [
			{"id": "tide_bolt", "kind": "projectile", "cooldown": 3.8, "range": 26.0, "damage": 19, "projectile_count": 3, "spread": 0.20, "anticipation": 0.55, "active": 0.12, "recovery": 0.32, "sfx": "projectile", "color": Color(0.22, 0.88, 1.0), "element": "frost"},
			{"id": "moon_tide_ring", "kind": "area", "cooldown": 7.5, "range": 24.0, "damage": 24, "radius": 4.5, "anticipation": 0.90, "active": 0.22, "recovery": 0.46, "sfx": "cast", "color": Color(0.42, 0.58, 1.0), "min_form": 1},
			{"id": "oracle_split", "kind": "projectile", "cooldown": 8.8, "range": 26.0, "damage": 21, "projectile_count": 6, "spread": 0.55, "anticipation": 0.95, "active": 0.16, "recovery": 0.50, "sfx": "cast", "color": Color(0.72, 0.48, 1.0), "element": "shadow", "min_form": 2},
		],
		"diamond_reward": 9,
		"rewards": {"xp": 560, "loot": {"moonmoss": 5, "crystal_fragment": 3}, "first_kill_materials": {"moonmoss": 5}},
	},
	"moonfen_lunar_leviathan": {
		"name": "LUNAR LEVIATHAN",
		"title": "the Orbiting Deep",
		"realm": "moonfen",
		"scene": ARTICULATED_SCENE,
		"hp": 1100, "atk": 22, "speed": 4.0, "scale": 1.24,
		"body_height": 4.8, "body_width": 2.0, "limb_style": "leviathan_wings",
		"palette": [Color(0.07, 0.06, 0.22), Color(0.38, 0.42, 1.0), Color(0.92, 0.38, 0.96)],
		"movement_mode": "fly_chase", "attack_style": "hybrid",
		"attack_range": 7.0, "chase_player": true, "can_fly": true, "can_roll": false,
		"form_count": 4, "armor_profile": [4, 6, 8, 11], "flash_level": 1.0,
		"sfx_profile": "grave_moss",
		"skills": [
			{"id": "lunar_breath", "kind": "projectile", "cooldown": 4.8, "range": 24.0, "damage": 24, "projectile_count": 4, "spread": 0.28, "anticipation": 0.64, "active": 0.14, "recovery": 0.38, "sfx": "projectile", "color": Color(0.56, 0.46, 1.0), "element": "shadow"},
			{"id": "crescent_sweep", "kind": "sword", "cooldown": 4.0, "range": 7.4, "damage": 34, "radius": 4.5, "anticipation": 0.66, "active": 0.20, "recovery": 0.40, "sfx": "sword", "color": Color(0.96, 0.42, 1.0), "min_form": 1},
			{"id": "orbit_barrage", "kind": "projectile", "cooldown": 8.5, "range": 26.0, "damage": 22, "projectile_count": 8, "spread": 0.72, "anticipation": 1.0, "active": 0.18, "recovery": 0.55, "sfx": "cast", "color": Color(0.28, 0.72, 1.0), "element": "shock", "min_form": 2},
		],
		"diamond_reward": 10,
		"rewards": {"xp": 680, "loot": {"moonmoss": 7, "crystal_fragment": 4}, "first_kill_materials": {"crystal_fragment": 4}},
	},
}

static func canonical_id_for(boss_id: String) -> String:
	var clean := boss_id.strip_edges()
	if DEFINITIONS.has(clean):
		return clean
	if LEGACY_ALIASES.has(clean):
		return str(LEGACY_ALIASES[clean])
	if clean.begins_with("biome_"):
		var without_prefix := clean.trim_prefix("biome_")
		if DEFINITIONS.has(without_prefix):
			return without_prefix
		if LEGACY_ALIASES.has(without_prefix):
			return str(LEGACY_ALIASES[without_prefix])
	if clean.begins_with("boss_"):
		var boss_without_prefix := clean.trim_prefix("boss_")
		if DEFINITIONS.has(boss_without_prefix):
			return boss_without_prefix
		if LEGACY_ALIASES.has(boss_without_prefix):
			return str(LEGACY_ALIASES[boss_without_prefix])
	return clean

static func definition_for(boss_id: String) -> Dictionary:
	var canonical := canonical_id_for(boss_id)
	var result := (DEFINITIONS.get(canonical, {}) as Dictionary).duplicate(true)
	if not result.is_empty():
		result["id"] = canonical
		if not result.has("intro"):
			result["intro"] = "%s answers the arena." % str(result.get("name", "The boss")).capitalize()
	if not result.is_empty():
		for skill_value in result.get("skills", []):
			if not skill_value is Dictionary:
				continue
			var skill := skill_value as Dictionary
			var skill_id := str(skill.get("id", ""))
			if not skill.has("vfx_family") and SKILL_VFX_FAMILIES.has(skill_id):
				skill["vfx_family"] = SKILL_VFX_FAMILIES[skill_id]
	if not result.is_empty() and not result.has("skill_definitions"):
		result["skill_definitions"] = (result.get("skills", []) as Array).duplicate(true)
	if not result.is_empty() and not result.has("projectile_pattern"):
		result["projectile_pattern"] = "spread" if result.get("attack_style", "") \
			in ["ranged", "hybrid"] else "none"
	if not result.is_empty() and not result.has("regen_policy"):
		result["regen_policy"] = (result.get("regen", {}) as Dictionary).duplicate(true)
	return result

static func scene_for(boss_id: String) -> String:
	var definition := definition_for(boss_id)
	return str(definition.get("scene", ARTICULATED_SCENE))

static func gameplay_key_for(boss_id: String) -> String:
	var canonical := canonical_id_for(boss_id)
	var definition := definition_for(canonical)
	return "boss_%s" % canonical if str(definition.get("realm", "")) == "whispergrove" \
		else "biome_%s" % canonical

## Save keys are allowed to arrive as canonical ids, old biome ids, old script
## paths, or the explicit boss_/biome_ forms used by gates and quests. Unknown
## test/content keys remain untouched for backwards compatibility.
static func canonical_key_for(saved_or_legacy_id: String) -> String:
	var clean := saved_or_legacy_id.strip_edges()
	var raw := clean
	if clean.begins_with("biome_") or clean.begins_with("boss_"):
		raw = clean.trim_prefix("biome_").trim_prefix("boss_")
	var canonical := canonical_id_for(raw)
	if not DEFINITIONS.has(canonical):
		return clean
	return gameplay_key_for(canonical)

static func aliases_for(canonical_id: String) -> Array[String]:
	var result: Array[String] = [canonical_id]
	for alias in LEGACY_ALIASES:
		if str(LEGACY_ALIASES[alias]) == canonical_id:
			result.append(str(alias))
	return result

static func all_definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for boss_id in CANONICAL_IDS:
		result.append(definition_for(boss_id))
	return result
