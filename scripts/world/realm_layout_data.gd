extends RefCounted
class_name RealmLayoutData

const BOSS_ARENA_MIN_SEPARATION: float = 36.0
const BOSS_ARENA_CLEARANCE_RADIUS: float = 6.4

## Hand-authored gameplay routes for the five realms. Coordinates are kept in
## world-local space so inherited realm scenes can share systems without
## sharing the same exploration flow.

const PROFILES := {
	"whispergrove": {
		"route": [Vector3(0, 0, 2), Vector3(-7, 0, -7), Vector3(4, 0, -15), Vector3(15, 0, -10), Vector3(32, 0, -30), Vector3(50, 0, -46), Vector3(66, 0, -60)],
		"checkpoint": Vector3(-5, 0.35, -5),
		"arena": Vector3(66, 0.1, -60),
		"cave": Vector3(18, 0.7, 3),
		"dungeon_name": "ROOTWARD HOLLOW",
"chests": [
		{"id": "whisper_moss_cache", "pos": Vector3(-12, 0.48, -9), "label": "MOSSKEEPER CACHE", "rarity": 2, "type": "instant"},
		{"id": "whisper_shrine_cache", "pos": Vector3(8, 0.48, -18), "label": "SHRINE OFFERING", "rarity": 2, "type": "instant"},
		{"id": "whisper_hidden_cache", "pos": Vector3(20, 0.48, -4), "label": "HIDDEN ROOT CACHE", "rarity": 3, "type": "instant"},
		{"id": "whisper_farwatch_cache", "pos": Vector3(46, 0.48, -40), "label": "FARWATCH CACHE", "rarity": 3, "type": "instant"},
	],
		"enemies": ["hushling", "spitter", "elite_hushling"],
		"resources": [
			{"id": "moss_fiber", "pos": Vector3(-8, 0, -8), "yield": 3},
			{"id": "bramble_wood", "pos": Vector3(5, 0, -16), "yield": 2},
			{"id": "iron_shard", "pos": Vector3(16, 0, -7), "yield": 2},
			{"id": "moonmoss", "pos": Vector3(40, 0, -34), "yield": 3},
		],
		"encounters": [
			{"scene": "spore_weaver", "pos": Vector3(5, 0.2, -13)},
			{"scene": "relic_leech", "pos": Vector3(17, 0.2, -6)},
			{"scene": "thorn_charger", "pos": Vector3(55, 0.2, -50)},
		],
		"spawn_pockets": [
			{"id": "wg_path_mouth", "pos": Vector3(14, 0, -7), "tier": "normal", "count": 2, "radius": 22.0},
			{"id": "wg_root_bend", "pos": Vector3(24, 0, -22), "tier": "normal", "count": 3, "radius": 24.0},
			{"id": "wg_farwatch", "pos": Vector3(48, 0, -44), "tier": "hard", "count": 3, "radius": 26.0},
			{"id": "wg_west_hollow", "pos": Vector3(-30, 0, -24), "tier": "normal", "count": 3, "radius": 26.0},
			{"id": "wg_ridge_shade", "pos": Vector3(-16, 0, -44), "tier": "hard", "count": 2, "radius": 24.0},
			{"id": "wg_beyond_arena", "pos": Vector3(84, 0, -78), "tier": "hard", "count": 3, "radius": 24.0},
		],
		"structures": [
			{"id": "wg_road_arch", "kind": "arch", "pos": Vector3(18, 0, -14), "label": "MOSSBOUND ARCH"},
			{"id": "wg_watchtower", "kind": "watch", "pos": Vector3(-24, 0, -30), "label": "LANTERN WATCH"},
			{"id": "wg_shrine", "kind": "shrine", "pos": Vector3(34, 0, -26), "label": "WAYFARER SHRINE"},
			{"id": "wg_ruin_circle", "kind": "ruins", "pos": Vector3(-40, 0, -48), "label": "OLD RITE CIRCLE"},
			{"id": "wg_scout_camp", "kind": "camp", "pos": Vector3(52, 0, -36), "label": "SCOUT CAMP"},
			{"id": "wg_basin", "kind": "basin", "pos": Vector3(-8, 0, -52), "label": "STILL POOL"},
		],
	},
	"bramblewood": {
		"route": [Vector3(0, 0, 2), Vector3(9, 0, -5), Vector3(14, 0, -16), Vector3(2, 0, -24), Vector3(-16, 0, -40), Vector3(-38, 0, -62), Vector3(-60, 0, -84), Vector3(-78, 0, -104)],
		"checkpoint": Vector3(7, 0.35, -4),
		"arena": Vector3(-78, 0.1, -104),
		"cave": Vector3(16, 0.7, -17),
		"dungeon_name": "THORN-SUNK BURROW",
		"expansion_pockets": [
			{"id": "split_road_oak", "position": Vector3(20, 0, -48),
				"role": "landmark", "landmark_id": "bramblewood_split_road_oak",
				"display_name": "SPLIT-ROAD OAK", "checkpoint_id": "bramblewood_expansion_start",
				"reward_marker": "bramblewood_split_road_oak",
				"approach_label": "The road forks beneath the old oak.",
				"reveal_label": "A root-marked trail leads deeper into Bramblewood.",
				"reward_label": "Route landmark discovered", "exit_label": "Keep the amber beacon in sight."},
			{"id": "rootcut_gully", "position": Vector3(46, 0, -86),
				"role": "gathering", "checkpoint_id": "rootcut_gully",
				"reward_marker": "rootcut_materials",
				"approach_label": "The roots have split the earth into a narrow lane.",
				"reveal_label": "The gully is rich with cutwood and iron shards.",
				"reward_label": "Route materials secured", "exit_label": "Follow the cut roots north-west."},
			{"id": "hollow_camp", "position": Vector3(82, 0, -124),
				"role": "discovery", "landmark_id": "bramblewood_hollow_camp",
				"display_name": "HOLLOW FORESTER CAMP", "checkpoint_id": "hollow_camp",
				"reward_marker": "bramblewood_hollow_forester_cache",
				"approach_label": "A cold camp sits beneath a wall of living bark.",
				"reveal_label": "The foresters left one cache behind.",
				"reward_label": "Forester cache", "exit_label": "The breached beacon burns beyond the camp."},
			{"id": "beacon_breach", "position": Vector3(124, 0, -164),
				"role": "elite_encounter", "encounter_tier": "elite",
				"checkpoint_id": "beacon_breach",
				"encounter": {"tier": "elite", "enemy_kind": "thorn_charger", "count": 4},
				"reward_marker": "beacon_breach_clear",
				"approach_label": "Thorns close around a broken beacon ring.",
				"reveal_label": "An Elder Thorn guards the passage.",
				"reward_label": "BEACON BREACH CLEARED", "exit_label": "The root court is ahead."},
			{"id": "rootbound_court", "position": Vector3(172, 0, -208),
				"role": "boss", "boss_id": "rootbound_warden",
				"checkpoint_id": "rootbound_court",
				"encounter": {"tier": "boss", "boss_id": "rootbound_warden", "phase": "root_court"},
				"reward_marker": "rootway_beacon",
				"approach_label": "The forest floor rises into a ring of roots.",
				"reveal_label": "The Rootbound Warden answers the broken beacon.",
				"reward_label": "ROOTWAY BEACON UNLOCKED", "exit_label": "Return through the Rootway."},
		],
		"side_bosses": [
			{"id": "bramblewood_briar_widow", "position": Vector3(134, 0, -220),
				"display_name": "BRIAR WIDOW", "arena_radius": 13.0},
		],
		"chests": [
			{"id": "mountain_cache", "pos": Vector3(13, 0.48, -10), "label": "THORNBOUND CACHE", "rarity": 2, "type": "instant"},
			{"id": "root_cache", "pos": Vector3(1, 0.48, -26), "label": "AMBUSH SPOILS", "rarity": 2, "type": "instant"},
			{"id": "bramble_elite_cache", "pos": Vector3(-17, 0.48, -14), "label": "WIDOW'S HOARD", "rarity": 3, "type": "boss_gated", "boss_key": "biome_bramblewood_briar_widow"},
			{"id": "bramble_deepwood_cache", "pos": Vector3(-54, 0.48, -76), "label": "DEEPWOOD CACHE", "rarity": 3, "type": "instant"},
		],
		"enemies": ["elite_hushling", "hushling", "spitter"],
		"resources": [
			{"id": "bramble_wood", "pos": Vector3(10, 0, -8), "yield": 3},
			{"id": "beast_hide", "pos": Vector3(3, 0, -23), "yield": 2},
			{"id": "iron_shard", "pos": Vector3(-13, 0, -16), "yield": 3},
			{"id": "monster_core", "pos": Vector3(-46, 0, -66), "yield": 2},
		],
		"encounters": [
			{"scene": "thorn_charger", "pos": Vector3(12, 0.2, -14)},
			{"scene": "spore_weaver", "pos": Vector3(-11, 0.2, -18)},
			{"scene": "mire_stalker", "pos": Vector3(-44, 0.2, -64)},
		],
		"spawn_pockets": [
			{"id": "bw_thornlane", "pos": Vector3(2, 0, -22), "tier": "hard", "count": 3, "radius": 24.0},
			{"id": "bw_rootcut_watch", "pos": Vector3(-14, 0, -30), "tier": "normal", "count": 3, "radius": 26.0},
			{"id": "bw_deepwood_1", "pos": Vector3(-34, 0, -52), "tier": "hard", "count": 4, "radius": 28.0},
			{"id": "bw_deepwood_2", "pos": Vector3(-56, 0, -78), "tier": "hard", "count": 4, "radius": 28.0},
			{"id": "bw_beyond_arena", "pos": Vector3(-96, 0, -122), "tier": "elite", "count": 3, "radius": 24.0},
			{"id": "bw_east_verge", "pos": Vector3(38, 0, -30), "tier": "normal", "count": 3, "radius": 26.0},
			{"id": "bw_south_margin", "pos": Vector3(-24, 0, -84), "tier": "normal", "count": 3, "radius": 26.0},
		],
		"structures": [
			{"id": "bw_thorn_gate", "kind": "arch", "pos": Vector3(25, 0, -9), "label": "THORN GATE"},
			{"id": "bw_watchtower", "kind": "watch", "pos": Vector3(-26, 0, -24), "label": "WINDLESS WATCH"},
			{"id": "bw_widow_shrine", "kind": "shrine", "pos": Vector3(-50, 0, -60), "label": "WIDOW SHRINE"},
			{"id": "bw_forester_ruins", "kind": "ruins", "pos": Vector3(-66, 0, -92), "label": "ROOT-CUT RUINS"},
			{"id": "bw_hunter_camp", "kind": "camp", "pos": Vector3(-18, 0, -70), "label": "THORNBOUND CAMP"},
			{"id": "bw_mud_basin", "kind": "basin", "pos": Vector3(30, 0, -52), "label": "CHOKED POOL"},
			{"id": "bw_spire", "kind": "spire", "pos": Vector3(-88, 0, -70), "label": "BRIAR SPIRE"},
		],
	},
	"mistfen": {
		"route": [Vector3(0, 0, 2), Vector3(-8, 0, -4), Vector3(-15, 0, -14), Vector3(-26, 0, -26), Vector3(-42, 0, -48), Vector3(-60, 0, -72), Vector3(-76, 0, -96)],
		"checkpoint": Vector3(-7, 0.35, -3),
		"arena": Vector3(-76, 0.1, -96),
		"cave": Vector3(-7, 0.7, -25),
		"dungeon_name": "DROWNED OSSUARY",
		"chests": [
			{"id": "mistfen_reed_cache", "pos": Vector3(-15, 0.48, -8), "label": "REED-WRAPPED CHEST", "rarity": 2, "type": "instant"},
			{"id": "mistfen_sunken_cache", "pos": Vector3(-2, 0.48, -26), "label": "SUNKEN RELIQUARY", "rarity": 3, "type": "boss_gated", "boss_key": "biome_mistfen_fogmaw"},
			{"id": "mistfen_maw_cache", "pos": Vector3(15, 0.48, -15), "label": "FOGMAW'S TITHE", "rarity": 3, "type": "boss_gated", "boss_key": "biome_mistfen_fogmaw"},
			{"id": "mistfen_deepfen_cache", "pos": Vector3(-52, 0.48, -66), "label": "DEEP-FEN RELIQUARY", "rarity": 4, "type": "instant"},
		],
		"enemies": ["spitter", "hushling", "elite_hushling"],
		"resources": [
			{"id": "fen_reed", "pos": Vector3(-10, 0, -6), "yield": 3},
			{"id": "spore_dust", "pos": Vector3(-6, 0, -23), "yield": 3},
			{"id": "moss_fiber", "pos": Vector3(12, 0, -18), "yield": 2},
			{"id": "crystal_fragment", "pos": Vector3(-44, 0, -54), "yield": 3},
		],
		"encounters": [
			{"scene": "mire_stalker", "pos": Vector3(-13, 0.2, -13)},
			{"scene": "spore_weaver", "pos": Vector3(10, 0.2, -20)},
			{"scene": "relic_leech", "pos": Vector3(-50, 0.2, -62)},
		],
		"spawn_pockets": [
			{"id": "mf_reed_walk", "pos": Vector3(-22, 0, -4), "tier": "normal", "count": 3, "radius": 24.0},
			{"id": "mf_boardwalk", "pos": Vector3(-26, 0, -28), "tier": "hard", "count": 3, "radius": 26.0},
			{"id": "mf_deepfen_1", "pos": Vector3(-40, 0, -46), "tier": "hard", "count": 4, "radius": 28.0},
			{"id": "mf_deepfen_2", "pos": Vector3(-58, 0, -70), "tier": "elite", "count": 3, "radius": 26.0},
			{"id": "mf_beyond_arena", "pos": Vector3(-94, 0, -114), "tier": "hard", "count": 4, "radius": 24.0},
			{"id": "mf_east_bank", "pos": Vector3(28, 0, -22), "tier": "normal", "count": 3, "radius": 26.0},
			{"id": "mf_north_shallows", "pos": Vector3(-10, 0, -58), "tier": "normal", "count": 3, "radius": 26.0},
		],
		"structures": [
			{"id": "mf_reed_arch", "kind": "arch", "pos": Vector3(-28, 0, -18), "label": "REED ARCH"},
			{"id": "mf_drowned_watch", "kind": "watch", "pos": Vector3(20, 0, -14), "label": "DROWNED WATCH"},
			{"id": "mf_mire_shrine", "kind": "shrine", "pos": Vector3(-38, 0, -36), "label": "MIRE SHRINE"},
			{"id": "mf_ossuary_ruins", "kind": "ruins", "pos": Vector3(-64, 0, -84), "label": "OSSUARY RUINS"},
			{"id": "mf_reed_camp", "kind": "camp", "pos": Vector3(-22, 0, -56), "label": "REED CAMP"},
			{"id": "mf_still_pool", "kind": "basin", "pos": Vector3(6, 0, -40), "label": "STILL POOL"},
			{"id": "mf_spire", "kind": "spire", "pos": Vector3(-84, 0, -62), "label": "FEN SPIRE"},
		],
	},
	"heartwood": {
		"route": [Vector3(0, 0, 2), Vector3(5, 0, -9), Vector3(-5, 0, -17), Vector3(7, 0, -27), Vector3(34, 0, -40), Vector3(72, 0, -56), Vector3(112, 0, -66), Vector3(150, 0, -72)],
		"checkpoint": Vector3(5, 0.35, -8),
		"arena": Vector3(150, 0.1, -72),
		"cave": Vector3(-8, 0.7, -18),
		"dungeon_name": "CINDER-ROOT VAULT",
		"side_bosses": [
			{"id": "heartwood_ash_bellower", "position": Vector3(-120, 0, -40),
				"display_name": "ASH BELLOWER", "arena_radius": 14.0},
		],
		"chests": [
			{"id": "heartwood_ash_cache", "pos": Vector3(-7, 0.48, -12), "label": "ASHEN CACHE", "rarity": 2, "type": "instant"},
			{"id": "heartwood_forge_cache", "pos": Vector3(8, 0.48, -28), "label": "FORGEMASTER CHEST", "rarity": 3, "type": "instant"},
			{"id": "heartwood_ember_cache", "pos": Vector3(22, 0.48, -17), "label": "CINDERHART RELIQUARY", "rarity": 4, "type": "boss_gated", "boss_key": "biome_heartwood_cinderhart"},
			{"id": "heartwood_rise_cache", "pos": Vector3(104, 0.48, -64), "label": "ASHEN RISE CACHE", "rarity": 4, "type": "instant"},
		],
		"enemies": ["elite_hushling", "spitter", "elite_hushling"],
		"resources": [
			{"id": "emberstone", "pos": Vector3(4, 0, -11), "yield": 3},
			{"id": "iron_shard", "pos": Vector3(-4, 0, -18), "yield": 3},
			{"id": "monster_core", "pos": Vector3(15, 0, -24), "yield": 2},
			{"id": "emberstone", "pos": Vector3(96, 0, -60), "yield": 4},
		],
		"encounters": [
			{"scene": "ember_warden", "pos": Vector3(-3, 0.2, -16)},
			{"scene": "thorn_charger", "pos": Vector3(15, 0.2, -22)},
			{"scene": "ember_warden", "pos": Vector3(100, 0.2, -62)},
		],
		"spawn_pockets": [
			{"id": "hw_cinder_path", "pos": Vector3(18, 0, -10), "tier": "normal", "count": 3, "radius": 24.0},
			{"id": "hw_ash_rise_1", "pos": Vector3(34, 0, -42), "tier": "hard", "count": 4, "radius": 28.0},
			{"id": "hw_ash_rise_2", "pos": Vector3(70, 0, -58), "tier": "hard", "count": 4, "radius": 28.0},
			{"id": "hw_vent_field", "pos": Vector3(108, 0, -68), "tier": "elite", "count": 3, "radius": 26.0},
			{"id": "hw_beyond_arena", "pos": Vector3(168, 0, -90), "tier": "hard", "count": 4, "radius": 24.0},
			{"id": "hw_basalt_shelf", "pos": Vector3(30, 0, -6), "tier": "normal", "count": 3, "radius": 26.0},
			{"id": "hw_ash_circle", "pos": Vector3(-40, 0, -60), "tier": "normal", "count": 3, "radius": 26.0},
		],
		"structures": [
			{"id": "hw_ember_arch", "kind": "arch", "pos": Vector3(-6, 0, -30), "label": "EMBER ARCH"},
			{"id": "hw_forge_watch", "kind": "watch", "pos": Vector3(40, 0, -30), "label": "FORGE WATCH"},
			{"id": "hw_cinder_shrine", "kind": "shrine", "pos": Vector3(78, 0, -60), "label": "CINDER SHRINE"},
			{"id": "hw_forge_ruins", "kind": "ruins", "pos": Vector3(146, 0, -56), "label": "FORGE RUINS"},
			{"id": "hw_smith_camp", "kind": "camp", "pos": Vector3(24, 0, -56), "label": "SMITH REFUGE"},
			{"id": "hw_magma_basin", "kind": "basin", "pos": Vector3(-58, 0, -30), "label": "MAGMA BASIN"},
			{"id": "hw_ash_spire", "kind": "spire", "pos": Vector3(-96, 0, -80), "label": "ASH SPIRE"},
		],
	},
	"moonfen": {
		"route": [Vector3(0, 0, 2), Vector3(10, 0, 4), Vector3(17, 0, -7), Vector3(24, 0, -20), Vector3(12, 0, -27), Vector3(-6, 0, -27), Vector3(-22, 0, -20), Vector3(-28, 0, -8)],
		"checkpoint": Vector3(9, 0.35, 3),
		"arena": Vector3(-28, 0.1, -8),
		"cave": Vector3(8, 0.7, -20),
		"dungeon_name": "LUNAR UNDERTIDE",
		"side_bosses": [
			{"id": "moonfen_lunar_leviathan", "position": Vector3(26, 0, 24),
				"display_name": "LUNAR LEVIATHAN", "arena_radius": 16.0},
		],
		"chests": [
			{"id": "moonfen_islet_cache", "pos": Vector3(17, 0.48, -3), "label": "ISLET CACHE", "rarity": 2, "type": "instant"},
			{"id": "moonfen_tide_cache", "pos": Vector3(3, 0.48, -21), "label": "UNDERTIDE CHEST", "rarity": 3, "type": "boss_gated", "boss_key": "biome_moonfen_tide_oracle"},
			{"id": "moonfen_lunar_cache", "pos": Vector3(-18, 0.48, -5), "label": "LUNAR RELIQUARY", "rarity": 4, "type": "boss_gated", "boss_key": "biome_moonfen_tide_oracle"},
			{"id": "moonfen_deepdrift_cache", "pos": Vector3(-24, 0.48, 2), "label": "DEEP-DRIFT CACHE", "rarity": 4, "type": "instant"},
		],
		"enemies": ["moonfen_fenling", "spitter", "elite_hushling"],
		"resources": [
			{"id": "moonmoss", "pos": Vector3(12, 0, 1), "yield": 3},
			{"id": "crystal_fragment", "pos": Vector3(7, 0, -19), "yield": 2},
			{"id": "fen_reed", "pos": Vector3(-13, 0, -12), "yield": 3},
			{"id": "moonmoss", "pos": Vector3(-20, 0, -26), "yield": 3},
		],
		"encounters": [
			{"scene": "relic_leech", "pos": Vector3(15, 0.2, -6)},
			{"scene": "mire_stalker", "pos": Vector3(-12, 0.2, -16)},
			{"scene": "moonfen_fenling", "pos": Vector3(-24, 0.2, -22)},
		],
		"spawn_pockets": [
			{"id": "mof_islet", "pos": Vector3(-4, 0, -11), "tier": "normal", "count": 3, "radius": 22.0},
			{"id": "mof_east_drift", "pos": Vector3(22, 0, -22), "tier": "hard", "count": 3, "radius": 22.0},
			{"id": "mof_undertide", "pos": Vector3(6, 0, -27), "tier": "hard", "count": 3, "radius": 22.0},
			{"id": "mof_west_drift", "pos": Vector3(-18, 0, -22), "tier": "hard", "count": 3, "radius": 22.0},
			{"id": "mof_north_shelf", "pos": Vector3(0, 0, 14), "tier": "normal", "count": 3, "radius": 22.0},
			{"id": "mof_stormwatch", "pos": Vector3(-22, 0, 8), "tier": "normal", "count": 3, "radius": 22.0},
		],
		"structures": [
			{"id": "mof_moonrise_arch", "kind": "arch", "pos": Vector3(26, 0, 2), "label": "MOONRISE ARCH"},
			{"id": "mof_drowned_watch", "kind": "watch", "pos": Vector3(-8, 0, -28), "label": "DROWNED WATCH"},
			{"id": "mof_mire_shrine", "kind": "shrine", "pos": Vector3(8, 0, 20), "label": "STORM SHRINE"},
			{"id": "mof_monolith_ring", "kind": "ruins", "pos": Vector3(-24, 0, -26), "label": "MONOLITH RING"},
			{"id": "mof_storm_shelter", "kind": "camp", "pos": Vector3(4, 0, 18), "label": "STORMWATCH SHELTER"},
			{"id": "mof_crystal_basin", "kind": "basin", "pos": Vector3(-26, 0, 8), "label": "CRYSTAL BASIN"},
		],
	},
}

static func profile(realm_id: String) -> Dictionary:
	return (PROFILES.get(realm_id, PROFILES["bramblewood"]) as Dictionary).duplicate(true)

## Shared-grove presentation follows progression, not the normalized save realm.
## Before the expedition is unlocked, the bramblewood scene is the
## Whispergrove map; afterwards it becomes the extended Bramblewood map.
static func visual_realm_for(world: Node) -> String:
	var biome := ""
	if world != null and "biome_id" in world:
		biome = str(world.get("biome_id"))
	var game_state := world.get_node_or_null("/root/GameState") if world != null else null
	if biome == "bramblewood":
		if game_state != null:
			var unlocked := bool(game_state.get("onboarding_completed")) \
				or int(game_state.get("current_stage")) >= 3
			if not unlocked:
				return "whispergrove"
		return biome
	if not biome.is_empty() and PROFILES.has(biome):
		return biome
	if game_state != null:
		var active := str(game_state.get("current_realm"))
		if PROFILES.has(active):
			return active
	return "bramblewood"

## All boss-capable centers that can exist in a realm. Expansion boss pockets
## are included so streamed clearance and spacing checks share this source.
static func boss_anchor_points(realm_id: String) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var realm_profile := profile(realm_id)
	var arena_value: Variant = realm_profile.get("arena", Vector3.ZERO)
	if arena_value is Vector3:
		var arena := arena_value as Vector3
		result.append(Vector2(arena.x, arena.z))
	var side_values: Variant = realm_profile.get("side_bosses", [])
	if side_values is Array:
		for side_value in side_values:
			if not side_value is Dictionary:
				continue
			var side_definition := side_value as Dictionary
			var side_position: Variant = side_definition.get("position", Vector3.ZERO)
			if side_position is Vector3:
				var side := side_position as Vector3
				result.append(Vector2(side.x, side.z))
	var pocket_values: Variant = realm_profile.get("expansion_pockets", [])
	if pocket_values is Array:
		for pocket_value in pocket_values:
			if not pocket_value is Dictionary:
				continue
			var pocket := pocket_value as Dictionary
			if str(pocket.get("role", "")) != "boss":
				continue
			var pocket_position: Variant = pocket.get("position", Vector3.ZERO)
			if pocket_position is Vector3:
				var boss_pocket := pocket_position as Vector3
				result.append(Vector2(boss_pocket.x, boss_pocket.z))
	return result

## Runtime worlds can expose the shared grove's current visual profile while
## already owning the extended Bramblewood route. Include both profiles so
## terrain and streaming clearances are ready before the route is unlocked.
static func boss_anchor_points_for_world(world: Node) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var realms: Array[String] = [visual_realm_for(world)]
	if world != null and "biome_id" in world:
		var biome := str(world.get("biome_id"))
		if PROFILES.has(biome) and biome not in realms:
			realms.append(biome)
	for realm_id in realms:
		for anchor in boss_anchor_points(realm_id):
			if anchor not in result:
				result.append(anchor)
	return result

## Every gameplay anchor a realm's frozen terrain must flatten so authored
## content (travel gates, chests, gathering nodes, set-pieces, pockets and
## structures) stands on level ground. Terrain relief and content builders read
## this one list instead of a hardcoded copy that drifts when routes move.
static func flatten_anchors(realm_id: String) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var realm_profile := profile(realm_id)
	var route_values: Variant = realm_profile.get("route", [])
	if route_values is Array:
		for route_value in route_values:
			if route_value is Vector3:
				var waypoint := route_value as Vector3
				result.append(Vector2(waypoint.x, waypoint.z))
	for key in ["chests", "resources", "encounters", "spawn_pockets", "structures"]:
		var values: Variant = realm_profile.get(key, [])
		if not values is Array:
			continue
		for value in values:
			if not value is Dictionary:
				continue
			var definition := value as Dictionary
			var position: Variant = definition.get("pos", definition.get("position", Vector3.ZERO))
			if position is Vector3:
				var point := position as Vector3
				result.append(Vector2(point.x, point.z))
	for anchor in boss_anchor_points(realm_id):
		result.append(anchor)
	return result

## Same contract as `boss_anchor_points_for_world`: a shared grove scene can
## present one realm while already owning another realm's extended route.
static func flatten_anchors_for_world(world: Node) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var realms: Array[String] = [visual_realm_for(world)]
	if world != null and "biome_id" in world:
		var biome := str(world.get("biome_id"))
		if PROFILES.has(biome) and biome not in realms:
			realms.append(biome)
	for realm_id in realms:
		for anchor in flatten_anchors(realm_id):
			if anchor not in result:
				result.append(anchor)
	return result

static func resolve_realm(world: Node) -> String:
	var active := ""
	if world != null:
		var game_state := world.get_node_or_null("/root/GameState")
		if game_state != null:
			active = str(game_state.get("current_realm"))
	if PROFILES.has(active):
		return active
	if world != null and "biome_id" in world:
		var biome := str(world.get("biome_id"))
		if PROFILES.has(biome):
			return biome
	return "bramblewood"
