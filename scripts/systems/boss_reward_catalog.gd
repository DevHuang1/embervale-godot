extends RefCounted
class_name BossRewardCatalog

const BOSS_ROSTER := preload("res://scripts/systems/boss_roster_catalog.gd")

## Alternate boss-reward directions. Existing guaranteed drops remain intact;
## this catalog is the data contract for a future post-boss choice panel.

const CHOICES := {
	"bramblewood_thornwarden": [
		{"id": "matriarch_scepter", "title": "HEARTWOOD SPEAR", "build_tag": "Nature control", "summary": "Root pressure, thorn reach, and a restorative bloom."},
		{"id": "warden_plate", "title": "THORN WARDEN PLATE", "build_tag": "Frontline guard", "summary": "Reliable defense and stagger safety against heavy strikes."},
	],
	"hushling_matriarch": [
		{"id": "matriarch_scepter", "title": "CROWN OF THE OLD ROOT", "build_tag": "Nature control", "summary": "Magic zoning, root pressure, and a healing bloom."},
		{"id": "warden_plate", "title": "MATRIARCH WARDEN PLATE", "build_tag": "Frontline guard", "summary": "Trade speed for reliable damage reduction and stagger safety."},
	],
	"moonfen_voidweaver": [
		{"id": "arcane_staff", "title": "MOONBOUGH", "build_tag": "Elemental zoning", "summary": "Long-range bursts and wide elemental control."},
		{"id": "emberweave_cloak", "title": "MOONFEN CLOAK", "build_tag": "Swift caster", "summary": "Movement and recovery for safer repositioning."},
	],
	"heartwood_cindercolossus": [
		{"id": "ember_sword", "title": "CINDERHEART BLADE", "build_tag": "Heavy strike", "summary": "Slow, devastating swings with stagger pressure."},
		{"id": "warden_plate", "title": "FURNACE WARD PLATE", "build_tag": "Frontline guard", "summary": "Thick armor to survive the Heartwood's heat."},
	],
	"mistfen_siltcrawler": [
		{"id": "arcane_staff", "title": "SILTWEAVER STAFF", "build_tag": "Elemental control", "summary": "Mist-infused bursts with watery zoning."},
		{"id": "emberweave_cloak", "title": "DROWNED SHROUD", "build_tag": "Swift caster", "summary": "Evasive movement through the fog."},
	],
	# Data-driven biome bosses share the base boss script, so repeat kills are
	# announced under their "biome_<def_id>" keys.
	"biome_thornhide_alpha": [
		{"id": "thornbite_cleaver", "title": "THORNBITE CLEAVER", "build_tag": "Relentless hunter", "summary": "Slow, wide bramble swings with a heavy rend."},
		{"id": "warden_plate", "title": "THORNHIDE WARD PLATE", "build_tag": "Frontline guard", "summary": "Steel that shrugs off thorn and claw alike."},
	],
	"biome_rootbound_warden": [
		{"id": "thornbite_cleaver", "title": "ROOTBOUND CLEAVER", "build_tag": "Relentless hunter", "summary": "A cleaver reforged against the sentinel's bark."},
		{"id": "warden_plate", "title": "SENTINEL WARD PLATE", "build_tag": "Frontline guard", "summary": "The court's last defense, worn against the court."},
	],
	"biome_fenmaw": [
		{"id": "tidecall_brand", "title": "TIDECALL BRAND", "build_tag": "Tide control", "summary": "Waves and mist-bursts for drowning control."},
		{"id": "emberweave_cloak", "title": "DROWNED SHROUD", "build_tag": "Swift caster", "summary": "Evasive movement through the fen's quiet."},
	],
	"biome_cinderhart_colossus": [
		{"id": "cinderhart_maul", "title": "CINDERHART MAUL", "build_tag": "Heavy strike", "summary": "A furnace maul that breaks ground on impact."},
		{"id": "warden_plate", "title": "FURNACE WARD PLATE", "build_tag": "Frontline guard", "summary": "Thick armor to survive the walking furnace."},
	],
	"biome_moonfen_oracle": [
		{"id": "oracle_crescent", "title": "ORACLE CRESCENT", "build_tag": "Reflex blades", "summary": "A mirrored crescent that cuts in spinning arcs."},
		{"id": "emberweave_cloak", "title": "MOONFEN CLOAK", "build_tag": "Swift caster", "summary": "Swift repositioning under the oracle's pale light."},
	],
	"boss_whispergrove_root_harrow": [
		{"id": "matriarch_scepter", "title": "HARROWBLADE", "build_tag": "Nature control", "summary": "Twin-root sword pressure with a restorative bloom."},
		{"id": "warden_plate", "title": "ROOT HARROW PLATE", "build_tag": "Frontline guard", "summary": "Layered bark armor that steadies close-range exchanges."},
	],
	"biome_bramblewood_thorn_regent": [
		{"id": "thornbite_cleaver", "title": "REGENT CLEAVER", "build_tag": "Heavy sword", "summary": "A crowned greatblade built for wide, deliberate cuts."},
		{"id": "warden_plate", "title": "THORN REGENT PLATE", "build_tag": "Frontline guard", "summary": "Dense thorn plate for surviving stagger-heavy fights."},
	],
	"biome_bramblewood_briar_widow": [
		{"id": "thornbite_cleaver", "title": "BRIAR NEEDLE", "build_tag": "Ranged pressure", "summary": "A thorn-forged weapon that rewards patient spacing."},
		{"id": "emberweave_cloak", "title": "WIDOW'S VEIL", "build_tag": "Evasive caster", "summary": "A light veil for repositioning through projectile patterns."},
	],
	"biome_mistfen_fogmaw": [
		{"id": "tidecall_brand", "title": "FOGMAW BRAND", "build_tag": "Rolling control", "summary": "Fen magic that turns a committed roll into a safe escape."},
		{"id": "warden_plate", "title": "FENWHEEL PLATE", "build_tag": "Tanky bruiser", "summary": "Weight and poise against burrow-burst impacts."},
	],
	"biome_heartwood_cinderhart": [
		{"id": "cinderhart_maul", "title": "CINDERHART MAUL", "build_tag": "Magma strike", "summary": "A furnace maul for ground-breaking close combat."},
		{"id": "warden_plate", "title": "FURNACE WARD PLATE", "build_tag": "Tanky hybrid", "summary": "Heat-scored armor that holds through mortar fire."},
	],
	"biome_heartwood_ash_bellower": [
		{"id": "cinderhart_maul", "title": "ASH BELL", "build_tag": "Artillery", "summary": "A resonant focus for long-range falling-fire skills."},
		{"id": "emberweave_cloak", "title": "BELLOWER SHROUD", "build_tag": "Flash caster", "summary": "A bright ash mantle for surviving the final form."},
	],
	"biome_moonfen_tide_oracle": [
		{"id": "oracle_crescent", "title": "TIDE CRESCENT", "build_tag": "Flying caster", "summary": "A crescent focus for moonlit water rings and bolts."},
		{"id": "emberweave_cloak", "title": "ORACLE VEIL", "build_tag": "Aerial caster", "summary": "Lightweight cloth for reading long-range spell lanes."},
	],
	"biome_moonfen_lunar_leviathan": [
		{"id": "oracle_crescent", "title": "LEVIATHAN CRESCENT", "build_tag": "Orbiting hybrid", "summary": "A lunar edge that links aerial pursuit with sweeping strikes."},
		{"id": "warden_plate", "title": "LUNAR SCALE PLATE", "build_tag": "Flash tank", "summary": "Prismatic scales that endure the leviathan's fourth form."},
	],
}

static func choices_for(boss_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var choices: Variant = CHOICES.get(boss_id, null)
	if choices == null:
		choices = CHOICES.get(BOSS_ROSTER.canonical_key_for(boss_id), [])
	for choice in choices:
		result.append((choice as Dictionary).duplicate(true))
	return result
