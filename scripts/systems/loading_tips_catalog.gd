extends RefCounted
class_name LoadingTipsCatalog

## Tips shown while a realm transition streams in.
##
## The pool is realm-aware: a travel to a realm leads with advice that matters
## there and then falls back to general play tips, so the loading screen teaches
## the next few minutes instead of only decorating the wait. Order is
## deterministic (no RNG) so the rotation is testable and repeat visits do not
## shuffle what a player just read.

const GENERAL_TIPS: Array[String] = [
	"Hold the interact action to GATHER, OPEN, or PICK UP — the HUD names the live action.",
	"Enemies telegraph with a bright ring before the strike. Step out of the ring.",
	"Dodging through an attack costs nothing; standing in it costs health.",
	"Scan a foe to learn its weakness before you commit to the fight.",
	"Salvage gear you have outgrown instead of hoarding it in the satchel.",
	"Camp upgrades persist across realms — spend embers before you travel.",
	"Elites guard a realm's best loot. Clear the room before you engage.",
	"A recipe lists what it still needs; gather the missing piece before crafting.",
	"Realm gates only open once the current objective is complete.",
	"Your objective tracker always names the next step — check it after every fight.",
]

const REALM_TIPS := {
	"whispergrove": [
		"Whispergrove teaches by play: follow the lit path and read the prompts.",
		"Resource nodes here respawn, so a full satchel is never wasted.",
	],
	"bramblewood": [
		"Bramblewood punishes standing still — thorn pressure arrives in waves.",
		"Ambushes start from the treeline; keep the camera wide when the fog thickens.",
	],
	"mistfen": [
		"Mistfen hides enemies until they are close. Scan early, fight late.",
		"Status effects linger in the fen — clear them before the next pull.",
	],
	"heartwood": [
		"Heartwood runs hot: heat builds while you fight and drains while you move.",
		"Elite pressure is constant here; break line of sight to reset a chase.",
	],
	"moonfen": [
		"Moonfen rewards water routes — shallow paths are faster than the banks.",
		"Magic threats combine elements here; watch for the second element.",
	],
}

static func known_realms() -> Array[String]:
	var realms: Array[String] = []
	for realm in REALM_TIPS:
		realms.append(str(realm))
	realms.sort()
	return realms

static func tips_for(realm_id: String, limit: int = 0) -> Array[String]:
	var tips: Array[String] = []
	var key := realm_id.strip_edges().to_lower()
	if REALM_TIPS.has(key):
		for tip in REALM_TIPS[key]:
			tips.append(str(tip))
	for tip in GENERAL_TIPS:
		tips.append(str(tip))
	if limit > 0 and tips.size() > limit:
		tips.resize(limit)
	return tips

static func tip_at(realm_id: String, index: int) -> String:
	var tips := tips_for(realm_id)
	if tips.is_empty():
		return ""
	return tips[posmod(index, tips.size())]
