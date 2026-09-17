extends RefCounted
class_name WeaponVisualRegistry

## Runtime visual ownership for weapon IDs. Gameplay saves keep semantic IDs;
## this table is the replaceable asset layer behind those IDs.

const WEAPON_PATHS: Dictionary = {
	"ember_sword": "res://assets/models/weapons/ember_sword.glb",
	"arcane_staff": "res://assets/models/weapons/arcane_staff.glb",
	"mug_mace": "res://assets/models/weapons/quaternius/Hammer_Double.fbx",
	"pocket_blade": "res://assets/models/weapons/quaternius/Dagger.fbx",
	"snip_twins": "res://assets/models/weapons/quaternius/Dagger_2.fbx",
	"slab_hammer": "res://assets/models/weapons/quaternius/Hammer_Double.fbx",
	"matriarch_scepter": "res://assets/models/weapons/quaternius/Spear.fbx",
	"thornmace": "res://assets/models/weapons/quaternius/Hammer_Small.fbx",
	"iron_axe": "res://assets/models/weapons/quaternius/Axe.fbx",
	"grove_spear": "res://assets/models/weapons/quaternius/Spear.fbx",
	"hunter_bow": "res://assets/models/weapons/quaternius/Bow_Wooden.fbx",
	"round_shield": "res://assets/models/weapons/quaternius/Shield_Round.fbx",
	"soda_cannon": "res://assets/models/weapons/quaternius/Hammer_Small.fbx",
	"siltcarver_blade": "res://assets/models/weapons/quaternius/Dagger_2.fbx",
	"cinderbound_maul": "res://assets/models/weapons/quaternius/Hammer_Double.fbx",
	"tideward_staff": "res://assets/models/weapons/quaternius/Spear.fbx",
	"rootbound_cleaver": "res://assets/models/weapons/quaternius/Claymore.fbx",
	"moonpact_staff": "res://assets/models/weapons/quaternius/Spear.fbx",
	"thornbite_cleaver": "res://assets/models/weapons/quaternius/Axe.fbx",
	"tidecall_brand": "res://assets/models/weapons/quaternius/Spear.fbx",
	"cinderhart_maul": "res://assets/models/weapons/quaternius/Hammer_Double.fbx",
	"oracle_crescent": "res://assets/models/weapons/quaternius/Claymore.fbx",
}

static func path_for(weapon_id: String) -> String:
	var path := str(WEAPON_PATHS.get(weapon_id, ""))
	return path if not path.is_empty() and ResourceLoader.exists(path) else ""

static func supported_ids() -> Array[String]:
	var result: Array[String] = []
	for weapon_id in WEAPON_PATHS:
		if not path_for(str(weapon_id)).is_empty():
			result.append(str(weapon_id))
	return result
