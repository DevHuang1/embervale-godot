extends RefCounted
class_name DiamondCatalog

## === The Glintmonger's Case — Diamond Cosmetics (data) ===
## Diamonds buy looks and voice ONLY. Every item here is a sidegrade:
## prettier SFX, trail colors, body auras. No stat lines exist on this shelf.
## Pure data class — no autoload/UI dependencies, so headless audits can
## compile it directly (autoload identifiers are unavailable to --script mode).

const ITEMS := [
	{"id": "scan_pack_5", "kind": "scan_pack", "price": 4.99,
		"name": "Divining Lens Pack", "desc": "5 camera scans + 1 bonus reroll. No guaranteed legendary result.",
		"duplicate_behavior": "Extra scans fill the capped balance; no duplicate weapon is forced.",
		"restore_path": "Restore purchases through the account provider."},
	{"id": "sfx_starlight", "kind": "sfx", "price": 6,
		"name": "Starlight Strikes", "desc": "Bright crystalline combat voice.",
		"value": "ember_glass"},
	{"id": "sfx_shadowstep", "kind": "sfx", "price": 6,
		"name": "Shadow Step", "desc": "Deep moss-dark combat voice.",
		"value": "grave_moss"},
	{"id": "sfx_emberbloom", "kind": "sfx", "price": 6,
		"name": "Ember Bloom", "desc": "Resinous, hollow-grove voice.",
		"value": "hollow_resin"},
	{"id": "trail_aurora", "kind": "trail", "price": 4,
		"name": "Aurora Trail", "desc": "Teal-green blade ribbons.",
		"value": "73f2d9"},
	{"id": "trail_bloodmoon", "kind": "trail", "price": 4,
		"name": "Bloodmoon Trail", "desc": "Crimson blade ribbons.",
		"value": "ff4d47"},
	{"id": "aura_lostlantern", "kind": "aura", "price": 8,
		"name": "Lantern of the Lost", "desc": "Violet soul-shine aura.",
		"value": "8a63ff55"},
	{"id": "aura_crownlight", "kind": "aura", "price": 8,
		"name": "Crown of Light", "desc": "Warm halo-gold aura.",
		"value": "ffd27a55"},
]