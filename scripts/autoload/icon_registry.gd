extends Node
## Stable gameplay-id to UI icon resolver. SVGs are authored, transparent,
## Android-safe fallbacks until the generated raster pack is imported.
const ICONS: Dictionary = {
	# --- combat + rite marks (shared by HUD, satchel and hero panel) ---
	"strike": "res://assets/ui/icons/strike.svg",
	"attack": "res://assets/ui/icons/attack.svg",
	"whirl": "res://assets/ui/icons/whirl.svg",
	"dash_strike": "res://assets/ui/icons/dash_strike.svg",
	"heal_bloom": "res://assets/ui/icons/heal_bloom.svg",
	"explosion": "res://assets/ui/icons/explosion.svg",
	"comet": "res://assets/ui/icons/comet.svg",
	"dodge": "res://assets/ui/icons/dodge.svg",
	"jump": "res://assets/ui/icons/jump.svg",
	"shield": "res://assets/ui/icons/shield.svg",
	"aoe": "res://assets/ui/icons/aoe.svg",
	# --- weapon families: one silhouette per shape, never one blade for all ---
	"sword": "res://assets/ui/icons/sword.svg",
	"blade": "res://assets/ui/icons/dagger.svg",
	"greatsword": "res://assets/ui/icons/greatsword.svg",
	"dagger": "res://assets/ui/icons/dagger.svg",
	"spear": "res://assets/ui/icons/spear.svg",
	"axe": "res://assets/ui/icons/axe.svg",
	"mace": "res://assets/ui/icons/mace.svg",
	"maul": "res://assets/ui/icons/maul.svg",
	"staff": "res://assets/ui/icons/staff.svg",
	"scepter": "res://assets/ui/icons/scepter.svg",
	# --- armour ---
	"plate": "res://assets/ui/icons/plate.svg",
	"cloak": "res://assets/ui/icons/cloak.svg",
	"vest": "res://assets/ui/icons/vest.svg",
	# --- consumables, materials, relics ---
	"potion": "res://assets/ui/icons/potion.svg",
	"ore": "res://assets/ui/icons/ore.svg",
	"relic": "res://assets/ui/icons/relic.svg",
	# --- elements ---
	"fire": "res://assets/ui/icons/element_fire.svg",
	"frost": "res://assets/ui/icons/element_frost.svg",
	"shock": "res://assets/ui/icons/element_shock.svg",
	"nature": "res://assets/ui/icons/element_nature.svg",
	# --- realm sigils ---
	"sigil_bramble": "res://assets/ui/icons/sigil_bramble.svg",
	"sigil_wave": "res://assets/ui/icons/sigil_wave.svg",
	"sigil_root": "res://assets/ui/icons/sigil_root.svg",
	"sigil_moon": "res://assets/ui/icons/sigil_moon.svg",
	# --- named weapons ---
	"ember_sword": "res://assets/ui/icons/sword.svg",
	"emberfang": "res://assets/ui/icons/sword.svg",
	"thornbite_cleaver": "res://assets/ui/icons/axe.svg",
	"cinderhart_maul": "res://assets/ui/icons/maul.svg",
	"matriarch_scepter": "res://assets/ui/icons/scepter.svg",
	"tidecall_brand": "res://assets/ui/icons/staff.svg",
	"oracle_crescent": "res://assets/ui/icons/dagger.svg",
	"mug_mace": "res://assets/ui/icons/mace.svg",
	"thornmace": "res://assets/ui/icons/mace.svg",
	"moonbough": "res://assets/ui/icons/staff.svg",
	"arcane_staff": "res://assets/ui/icons/staff.svg",
	"pocket_blade": "res://assets/ui/icons/dagger.svg",
	"snip_twins": "res://assets/ui/icons/dagger.svg",
	"slab_hammer": "res://assets/ui/icons/maul.svg",
	"siltcarver_blade": "res://assets/ui/icons/sword.svg",
	"cinderbound_maul": "res://assets/ui/icons/maul.svg",
	"tideward_staff": "res://assets/ui/icons/staff.svg",
	"rootbound_cleaver": "res://assets/ui/icons/axe.svg",
	"moonpact_staff": "res://assets/ui/icons/staff.svg",
	# --- named armour ---
	"warden_plate": "res://assets/ui/icons/plate.svg",
	"cinderplate": "res://assets/ui/icons/plate.svg",
	"emberweave_cloak": "res://assets/ui/icons/cloak.svg",
	"spore_wrap": "res://assets/ui/icons/cloak.svg",
	"moonfen_cloak": "res://assets/ui/icons/cloak.svg",
	"siltband_cloak": "res://assets/ui/icons/cloak.svg",
	"moonsilk_vest": "res://assets/ui/icons/vest.svg",
	# --- consumables ---
	"moss_tonic": "res://assets/ui/icons/potion.svg",
	"ember_salve": "res://assets/ui/icons/potion.svg",
	"moon_draught": "res://assets/ui/icons/potion.svg",
	"spore_antidote": "res://assets/ui/icons/potion.svg",
	# --- materials ---
	"iron": "res://assets/ui/icons/ore.svg",
	"raw_iron": "res://assets/ui/icons/ore.svg",
	"iron_scrap": "res://assets/ui/icons/ore.svg",
	"ember_shard": "res://assets/ui/icons/ore.svg",
	"moon_shard": "res://assets/ui/icons/ore.svg",
	"spore_sac": "res://assets/ui/icons/ore.svg",
	"heartwood_core": "res://assets/ui/icons/relic.svg",
	"quest": "res://assets/ui/icons/relic.svg",
}

func _runtime_path(source_path: String) -> String:
	var file_name := source_path.get_file().get_basename()
	var raster_path := "res://assets/ui/icons/raster/%s.png" % file_name
	return raster_path if ResourceLoader.exists(raster_path) else source_path

func has_icon(id: String) -> bool:
	return ICONS.has(id) and ResourceLoader.exists(_runtime_path(str(ICONS[id])))

func icon_for(item_id_or_skill_id: String) -> Texture2D:
	var path := str(ICONS.get(item_id_or_skill_id, ""))
	path = _runtime_path(path) if not path.is_empty() else ""
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
