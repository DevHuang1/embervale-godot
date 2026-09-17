extends Node
## Stable gameplay-id to UI icon resolver. SVGs are authored, transparent,
## Android-safe fallbacks until the generated raster pack is imported.
const ICONS: Dictionary = {
	"strike": "res://assets/ui/icons/strike.svg",
	"attack": "res://assets/ui/icons/attack.svg",
	"whirl": "res://assets/ui/icons/whirl.svg",
	"dash_strike": "res://assets/ui/icons/dash_strike.svg",
	"heal_bloom": "res://assets/ui/icons/heal_bloom.svg",
	"explosion": "res://assets/ui/icons/explosion.svg",
	"comet": "res://assets/ui/icons/comet.svg",
	"dodge": "res://assets/ui/icons/dodge.svg",
	"jump": "res://assets/ui/icons/jump.svg",
	"sword": "res://assets/ui/icons/strike.svg",
	"mace": "res://assets/ui/icons/attack.svg",
	"axe": "res://assets/ui/icons/strike.svg",
	"blade": "res://assets/ui/icons/strike.svg",
	"shield": "res://assets/ui/icons/shield.svg",
	"staff": "res://assets/ui/icons/comet.svg",
	"potion": "res://assets/ui/icons/heal_bloom.svg",
	"fire": "res://assets/ui/icons/explosion.svg",
	"nature": "res://assets/ui/icons/heal_bloom.svg",
	"quest": "res://assets/ui/icons/comet.svg",
	"ember_sword": "res://assets/ui/icons/strike.svg",
	"emberfang": "res://assets/ui/icons/strike.svg",
	"thornbite_cleaver": "res://assets/ui/icons/strike.svg",
	"cinderhart_maul": "res://assets/ui/icons/attack.svg",
	"matriarch_scepter": "res://assets/ui/icons/comet.svg",
	"tidecall_brand": "res://assets/ui/icons/comet.svg",
	"oracle_crescent": "res://assets/ui/icons/whirl.svg",
	"mug_mace": "res://assets/ui/icons/attack.svg",
	"thornmace": "res://assets/ui/icons/attack.svg",
	"moonbough": "res://assets/ui/icons/comet.svg",
	"warden_plate": "res://assets/ui/icons/attack.svg",
	"emberweave_cloak": "res://assets/ui/icons/dodge.svg",
	"spore_wrap": "res://assets/ui/icons/dodge.svg",
	"moonfen_cloak": "res://assets/ui/icons/dodge.svg",
	"cloak": "res://assets/ui/icons/dodge.svg",
	"moss_tonic": "res://assets/ui/icons/heal_bloom.svg",
	"backpack": "res://assets/ui/icons/attack.svg",
	"siltcarver_blade": "res://assets/ui/icons/strike.svg",
	"cinderbound_maul": "res://assets/ui/icons/attack.svg",
	"tideward_staff": "res://assets/ui/icons/comet.svg",
	"rootbound_cleaver": "res://assets/ui/icons/strike.svg",
	"moonpact_staff": "res://assets/ui/icons/comet.svg",
	"siltband_cloak": "res://assets/ui/icons/dodge.svg",
	"cinderplate": "res://assets/ui/icons/attack.svg",
	"moonsilk_vest": "res://assets/ui/icons/dodge.svg",
	"ember_salve": "res://assets/ui/icons/heal_bloom.svg",
	"moon_draught": "res://assets/ui/icons/heal_bloom.svg",
	"spore_antidote": "res://assets/ui/icons/heal_bloom.svg",
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
