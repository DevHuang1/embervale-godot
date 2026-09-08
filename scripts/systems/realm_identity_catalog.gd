extends RefCounted
class_name RealmIdentityCatalog

## Authoritative realm identity contract for traversal, gathering, ambience,
## elite composition, and landmark rewards. This is descriptive data only;
## it does not silently change combat values or traversal collision.

const PROFILES := {
	"whispergrove": {
		"loop": {"short": "follow the lantern path", "medium": "gather warm moss and help a grove sprite", "long": "complete the quiet-grove route and relight the first beacon"},
		"ecology": {"predator_prey": "thorn guardian pressures hushlings toward open clearings", "rivals": "grove wardens oppose root-spoiled sprites", "elemental_reaction": "nature effects strengthen near living growth", "hazard": "lantern-dark patches reduce safe visibility"},
		"traversal": "lantern path discovery",
		"resource_ritual": "gather warm moss beneath the welcome arch",
		"ambient_behavior": "butterflies drift between flower clearings",
		"elite_composition": "thorn guardian with two skittering hushlings",
		"landmark_reward": "grove map fragment",
		"reward": {"type": "scan_fragment", "quantity": 1},
	},
	"bramblewood": {
		"loop": {"short": "scout a thorn lane", "medium": "cut roots and defeat the route elite", "long": "clear the expedition and forge a stronger elemental loadout"},
		"ecology": {"predator_prey": "thorn chargers drive skitterers into the player path", "rivals": "root guardians contest spitter nests", "elemental_reaction": "fire clears bramble growth but increases heat pressure", "hazard": "thorn lanes punish careless positioning"},
		"traversal": "thorn-lane scouting",
		"resource_ritual": "cut bramble roots around the beacon road",
		"ambient_behavior": "fireflies gather near lantern posts at dusk",
		"elite_composition": "charger pins the route while a spitter controls space",
		"landmark_reward": "beacon route checkpoint",
		"reward": {"type": "gold", "quantity": 30},
	},
	"mistfen": {
		"loop": {"short": "cross a reed-bank route", "medium": "gather during a fog window", "long": "master visibility pressure and reveal the shortcut cache"},
		"ecology": {"predator_prey": "fen predators stalk leeches around still water", "rivals": "fenlings disrupt relic leeches competing for pools", "elemental_reaction": "shock chains through wet ground", "hazard": "fog hides telegraph distance until the warning pulse"},
		"traversal": "reed-bank and boardwalk routing",
		"resource_ritual": "draw fen reed from still-water rings",
		"ambient_behavior": "fireflies pulse above ponds and fog banks",
		"elite_composition": "fenling controller with relic leech disruption",
		"landmark_reward": "mistfen shortcut revealed",
		"reward": {"type": "material", "id": "fen_reed", "quantity": 2},
	},
	"heartwood": {
		"loop": {"short": "cross a cooling-stone lane", "medium": "harvest emberstone beside a vent", "long": "survive heat pressure and unlock the forge recipe"},
		"ecology": {"predator_prey": "cinderharts scatter ember adds from cooling vents", "rivals": "ash wardens contest vent access", "elemental_reaction": "frost dampens heat while fire extends vent hazards", "hazard": "magma cracks create short-lived unsafe ground"},
		"traversal": "cooling-stone heat-lane crossing",
		"resource_ritual": "harvest emberstone beside cooling vents",
		"ambient_behavior": "embers rise from cracks between ash trees",
		"elite_composition": "cinderhart pressure with ember adds",
		"landmark_reward": "forge recipe discovery",
		"reward": {"type": "material", "id": "emberstone", "quantity": 2},
	},
	"moonfen": {
		"loop": {"short": "cross a crystal causeway", "medium": "gather during a storm lull", "long": "combine elemental threats and claim the expedition cache"},
		"ecology": {"predator_prey": "storm spirits circle crystal fauna during lulls", "rivals": "fenlings and relic leeches fight over monolith charge", "elemental_reaction": "thunder empowers wet targets but exposes the caster", "hazard": "storm flashes mark delayed impact rings"},
		"traversal": "moon-pool and crystal-causeway route",
		"resource_ritual": "collect crystal fragments during storm lulls",
		"ambient_behavior": "storm motes orbit monoliths between thunder flashes",
		"elite_composition": "fenling and relic leech elemental combination",
		"landmark_reward": "moonfen expedition cache",
		"reward": {"type": "gold", "quantity": 45},
	},
}

static func for_realm(realm_id: String) -> Dictionary:
	return (PROFILES.get(realm_id, PROFILES["bramblewood"]) as Dictionary).duplicate(true)

static func realms() -> Array[String]:
	var ids: Array[String] = []
	for key in PROFILES.keys():
		ids.append(str(key))
	return ids
