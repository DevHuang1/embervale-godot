extends RefCounted
class_name DiscoveryCodex

## === Discovery Codex ===
## First-encounter introductions for every mob kind and realm structure kind.
## Each record is the player-facing identity: a name, a one-line title, a small
## piece of realm history, and the skills (mobs) or features (structures) the
## player is about to deal with. The HUD shows a record once per save the first
## time the player meets that creature or place.
##
## Skill names mirror what the enemy scripts actually cast (Thorn Rush,
## Spore Cloud, Mire Cloak, ...) so the introduction never promises a move the
## creature does not have.

const KIND_MOB := "mob"
const KIND_STRUCTURE := "structure"

## Scene/registry ids that resolve to another record instead of their own
## silhouette (the generic charger/ambusher aliases reused by spawn pockets).
const MOB_ALIASES := {
	"charger": "thorn_charger",
	"ambusher": "mire_stalker",
	"moonfen_fenling": "fenling",
}

const MOBS := {
	"hushling": {
		"name": "HUSHLING",
		"title": "bramble sprite",
		"story": "Hushlings bud from the grove's oldest root-knots, half moss and half mischief. They guard the path in short lunges and burst into thorn when they feel cornered.",
		"skills": [
			{"name": "Hop Lunge", "desc": "A short commit that closes the last few paces."},
			{"name": "Thorn Burst", "desc": "A ring of brambles erupts around it when pressed."},
		],
	},
	"spitter": {
		"name": "SPITTER",
		"title": "venom caster",
		"story": "A hushling that never learned to close the distance. It keeps its standoff and lobs hissing venom in a high arc, punishing anyone who holds still.",
		"skills": [
			{"name": "Venom Glob", "desc": "An arcing spit that splashes where it lands."},
			{"name": "Standoff Instinct", "desc": "It backs away to keep the fight at range."},
		],
	},
	"elite_hushling": {
		"name": "ELITE EMBER WARDEN",
		"title": "ember-forged hushling",
		"story": "Hushlings that fed on emberstone grow a cinder core. Fire and nature slide off the bark, and the core detonates when the body finally falls.",
		"skills": [
			{"name": "Elemental Rejection", "desc": "Fire and nature washes off without a mark."},
			{"name": "Ember Detonation", "desc": "The core bursts on death — step away."},
		],
	},
	"fenling": {
		"name": "FENLING",
		"title": "still-water sprite",
		"story": "Born where moonlight pools on quiet water, fenlings skim the shallows and answer a stranger's weight with frost. They keep to the reeds until the fog favours them.",
		"skills": [
			{"name": "Frost Burst", "desc": "A cold snap that slows the blood."},
			{"name": "Reed Volley", "desc": "A scatter of spore-tipped needles at range."},
		],
	},
	"thorn_charger": {
		"name": "THORN CHARGER",
		"title": "bramble ram",
		"story": "A boar-shaped knot of bramble that only knows one direction. It announces the rush with a lowered crown and a long scraping breath.",
		"skills": [
			{"name": "Bramble Charge", "desc": "A straight-line rush that knocks the wind out."},
			{"name": "Ram Horns", "desc": "A planted headbutt for anyone who stands ground."},
		],
	},
	"mire_stalker": {
		"name": "MIRE STALKER",
		"title": "fen ambusher",
		"story": "It waits under the waterline until the reeds hide its fins, then strikes from behind. The cloak holds until its next blow lands.",
		"skills": [
			{"name": "Shadow Strike", "desc": "It slips behind you and strikes before you turn."},
			{"name": "Mire Cloak", "desc": "Reed-shadow turns aside the first blow."},
		],
	},
	"spore_weaver": {
		"name": "SPORE WEAVER",
		"title": "spore spinner",
		"story": "The weaver seeds the air with choking spores and lets the fight come to it. Break its sacs and the cloud thins.",
		"skills": [
			{"name": "Spore Cloud", "desc": "A lingering haze that bites at the lungs."},
			{"name": "Skittering Retreat", "desc": "It keeps its distance while the cloud works."},
		],
	},
	"ember_warden": {
		"name": "EMBER WARDEN",
		"title": "heartwood sentinel",
		"story": "Wardens were set to watch the vents and never stood down. Their disc shields drink fire and answer with a ring of flame.",
		"skills": [
			{"name": "Inferno Shield", "desc": "A burning guard that answers melee."},
			{"name": "Vent Step", "desc": "It circles toward the nearest heat."},
		],
	},
	"relic_leech": {
		"name": "RELIC LEECH",
		"title": "shard feeder",
		"story": "It nests in old vaults feeding on loose relic light. Its siphon pulls warmth through armour and mends its own hurts with what it takes.",
		"skills": [
			{"name": "Soul Siphon", "desc": "It drinks life on the hit and heals."},
			{"name": "Vault Ambush", "desc": "It waits coiled beside old stone."},
		],
	},
}

## Structures are gated per authored instance (each gate, watch or camp gets its
## own first meeting) but share the kind's history and features.
const STRUCTURES := {
	"arch": {
		"name": "OLD-ROAD ARCH",
		"title": "gate of the agreed border",
		"story": "The first roads were marked with arches where a realm's edge was agreed. The moss remembers the treaty even when the masons are long gone.",
		"features": [
			{"name": "Waypoint", "desc": "A fixed point to steer by on the route."},
			{"name": "Threshold", "desc": "Crossing it marks the realm's claim."},
		],
	},
	"watch": {
		"name": "LANTERN WATCH",
		"title": "light for late travellers",
		"story": "Watchers kept a flame for anyone arriving after dark and a dry step for anyone caught in the fog. The tower still offers both.",
		"features": [
			{"name": "Vantage", "desc": "High ground that reads the whole approach."},
			{"name": "Shelter", "desc": "A safe pause on a long route."},
		],
	},
	"shrine": {
		"name": "WAYFARER SHRINE",
		"title": "offering to the road",
		"story": "Travellers traded a handful of coin for safe passage here. The basin is dry now, but the habit of leaving something behind has not died.",
		"features": [
			{"name": "Offering", "desc": "Spend a little for the road's favour."},
			{"name": "Rest", "desc": "A quiet place to steady yourself."},
		],
	},
	"ruins": {
		"name": "OLD RITE CIRCLE",
		"title": "stones older than the realms",
		"story": "The stones were set in a ring before the realms were named. Something was sealed here, or something was welcomed — the carvings disagree.",
		"features": [
			{"name": "Relic cache", "desc": "Old light lingers in the fallen stone."},
			{"name": "Elite ground", "desc": "Whatever nests here fights to keep it."},
		],
	},
	"camp": {
		"name": "FORESTER CAMP",
		"title": "cold camp on the rootway",
		"story": "Foresters slept here while they mapped the rootways. They left in a hurry or never came back, and their caches were never emptied.",
		"features": [
			{"name": "Supply cache", "desc": "Tools and stores left behind."},
			{"name": "Checkpoint", "desc": "A known point to return to."},
		],
	},
	"basin": {
		"name": "STILL POOL",
		"title": "rain caught in old masonry",
		"story": "Rainwater collects in a bowl of old masonry and the roots below keep it clear. The pool has never quite dried, even in the hot realms.",
		"features": [
			{"name": "Water source", "desc": "A landmark you can see from the path."},
			{"name": "Gathering ground", "desc": "Materials root thickly around it."},
		],
	},
	"spire": {
		"name": "BRIAR SPIRE",
		"title": "root driven through stone",
		"story": "A spear of root and stone pushed up from something below. It marks how far the realm's claim has grown, and how far it still wants to.",
		"features": [
			{"name": "Landmark", "desc": "A silhouette visible across the realm."},
			{"name": "Elite nests", "desc": "The strong claim the high ground."},
		],
	},
}

static func has_mob(kind: String) -> bool:
	var resolved := MOB_ALIASES.get(kind, kind) as String
	return MOBS.has(resolved)

static func mob_record(kind: String) -> Dictionary:
	var resolved := MOB_ALIASES.get(kind, kind) as String
	if not MOBS.has(resolved):
		return {}
	var record: Dictionary = (MOBS[resolved] as Dictionary).duplicate(true)
	record["kind"] = resolved
	record["type"] = KIND_MOB
	record["bullets_label"] = "SKILLS"
	record["bullets"] = record.get("skills", [])
	return record

static func has_structure(kind: String) -> bool:
	return STRUCTURES.has(kind)

static func structure_record(kind: String, display_name: String = "",
		realm: String = "") -> Dictionary:
	if not STRUCTURES.has(kind):
		return {}
	var record: Dictionary = (STRUCTURES[kind] as Dictionary).duplicate(true)
	record["kind"] = kind
	record["type"] = KIND_STRUCTURE
	record["bullets_label"] = "FEATURES"
	record["bullets"] = record.get("features", [])
	if not display_name.strip_edges().is_empty():
		record["name"] = display_name.strip_edges().to_upper()
	if not realm.is_empty():
		record["realm"] = realm
	return record

static func mob_kinds() -> Array[String]:
	var result: Array[String] = []
	for kind in MOBS:
		result.append(str(kind))
	return result

static func structure_kinds() -> Array[String]:
	var result: Array[String] = []
	for kind in STRUCTURES:
		result.append(str(kind))
	return result

## Catalog contract used by startup validation and the discovery tests: every
## record carries identity, history and at least one actionable bullet.
static func validate() -> Array[String]:
	var errors: Array[String] = []
	for kind in MOBS:
		var record: Dictionary = MOBS[kind]
		for field in ["name", "title", "story"]:
			if str(record.get(field, "")).strip_edges().is_empty():
				errors.append("Mob record %s missing %s" % [kind, field])
		if (record.get("skills", []) as Array).is_empty():
			errors.append("Mob record %s has no skills" % kind)
		for skill_value in record.get("skills", []):
			var skill := skill_value as Dictionary
			if str(skill.get("name", "")).strip_edges().is_empty() \
					or str(skill.get("desc", "")).strip_edges().is_empty():
				errors.append("Mob record %s has an unnamed skill" % kind)
	for kind in STRUCTURES:
		var record: Dictionary = STRUCTURES[kind]
		for field in ["name", "title", "story"]:
			if str(record.get(field, "")).strip_edges().is_empty():
				errors.append("Structure record %s missing %s" % [kind, field])
		if (record.get("features", []) as Array).is_empty():
			errors.append("Structure record %s has no features" % kind)
	return errors

## Every kind the enemy registry can spawn must resolve to a record, and every
## structure kind an authored realm profile can place must too.
static func coverage_errors(spawnable_kinds: Array, structure_kinds: Array) -> Array[String]:
	var errors: Array[String] = []
	for kind_value in spawnable_kinds:
		if not has_mob(str(kind_value)):
			errors.append("Enemy kind without a codex record: %s" % str(kind_value))
	for kind_value in structure_kinds:
		if not has_structure(str(kind_value)):
			errors.append("Structure kind without a codex record: %s" % str(kind_value))
	return errors
