extends RefCounted
class_name ForgeCatalog

const TIER_NAMES: Array[String] = ["Common", "Uncommon", "Rare", "Epic", "Legendary"]

const TIER_COSTS: Array[Dictionary] = [
	{"bramble_wood": 4},
	{"bramble_wood": 6, "moss_fiber": 4},
	{"iron_shard": 5, "beast_hide": 3, "spore_dust": 3},
	{"iron_shard": 6, "beast_hide": 4, "moonmoss": 3, "crystal_fragment": 2},
	{"monster_core": 2, "emberstone": 5, "crystal_fragment": 4},
]

const FAMILY_BY_KIND := {
	"hushling": "swarm",
	"charger": "brute",
	"thorn_charger": "brute",
	"spitter": "caster",
	"spore_weaver": "caster",
	"mire_stalker": "stalker",
	"fenling": "stalker",
	"moonfen_fenling": "stalker",
	"ambusher": "stalker",
	"relic_leech": "stalker",
	"ember_warden": "warden",
}

const FAMILY_LABELS := {
	"swarm": "swarm foes",
	"brute": "brutes",
	"caster": "casters",
	"stalker": "stalkers",
	"warden": "wardens",
}

const BOSS_LABELS := {
	"whispergrove_root_harrow": "the Root Harrow",
}

const BLUEPRINTS := {
	"mug_mace": {"unlock": {"family": "swarm", "count": 2}},
	"snip_twins": {"unlock": {"family": "brute", "count": 2}},
	"soda_cannon": {"unlock": {"family": "caster", "count": 2}},
	"pocket_blade": {"unlock": {"family": "stalker", "count": 2}},
	"slab_hammer": {"unlock": {"boss": "whispergrove_root_harrow"}},
}

static func blueprint_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in BLUEPRINTS:
		ids.append(str(id))
	return ids

static func blueprint(id: String) -> Dictionary:
	return BLUEPRINTS.get(id, {}).duplicate(true)

static func tier_count() -> int:
	return TIER_COSTS.size()

static func tier_cost(tier: int) -> Dictionary:
	var index := clampi(tier, 0, TIER_COSTS.size() - 1)
	return TIER_COSTS[index].duplicate(true)

static func tier_name(tier: int) -> String:
	return TIER_NAMES[clampi(tier, 0, TIER_NAMES.size() - 1)]

static func family_for_kind(kind: String) -> String:
	var key := kind.strip_edges().to_lower()
	if key.is_empty():
		return ""
	if FAMILY_BY_KIND.has(key):
		return str(FAMILY_BY_KIND[key])
	for mapped in FAMILY_BY_KIND:
		if key.contains(str(mapped)):
			return str(FAMILY_BY_KIND[mapped])
	return ""

static func family_label(family: String) -> String:
	return str(FAMILY_LABELS.get(family, family))

static func boss_label(boss_key: String) -> String:
	return str(BOSS_LABELS.get(boss_key, boss_key))
