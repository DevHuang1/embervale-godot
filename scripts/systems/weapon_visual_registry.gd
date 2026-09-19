extends RefCounted
class_name WeaponVisualRegistry

## Runtime visual ownership for weapon IDs. Gameplay saves keep semantic IDs;
## this table is the replaceable asset layer behind those IDs.

const WEAPON_PATHS: Dictionary = {
	"ember_sword": "res://assets/models/weapons/ember_sword.glb",
	"arcane_staff": "res://assets/models/weapons/arcane_staff.glb",
	"mug_mace": "res://assets/models/weapons/quaternius/Hammer_Small.fbx",
	"pocket_blade": "res://assets/models/weapons/quaternius/Dagger.fbx",
	"snip_twins": "res://assets/models/weapons/quaternius/Dagger_2.fbx",
	"slab_hammer": "res://assets/models/weapons/quaternius/Hammer_Double.fbx",
	"matriarch_scepter": "res://assets/models/weapons/quaternius/Spear.fbx",
	"thornmace": "res://assets/models/weapons/quaternius/Hammer_Small.fbx",
	"thorn_mace": "res://assets/models/weapons/quaternius/Hammer_Small.fbx",
	"iron_axe": "res://assets/models/weapons/quaternius/Axe.fbx",
	"grove_spear": "res://assets/models/weapons/quaternius/Spear.fbx",
	"hunter_bow": "res://assets/models/weapons/quaternius/Bow_Wooden.fbx",
	"round_shield": "res://assets/models/weapons/quaternius/Shield_Round.fbx",
	"soda_cannon": "res://assets/models/weapons/quaternius/Spear.fbx",
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

## Forged kits are saved as `relic_<base_id>`; they wear the model of the base
## kit they were built from, so every lookup resolves through this first.
static func resolve_id(weapon_id: String) -> String:
	var resolved := weapon_id
	while resolved.begins_with("relic_"):
		resolved = resolved.trim_prefix("relic_")
	return resolved

static func path_for(weapon_id: String) -> String:
	var path := str(WEAPON_PATHS.get(resolve_id(weapon_id), ""))
	return path if not path.is_empty() and ResourceLoader.exists(path) else ""

const WEAPON_LENGTHS: Dictionary = {
	"ember_sword": 1.05, "arcane_staff": 1.65, "matriarch_scepter": 1.65,
	"mug_mace": 0.85, "slab_hammer": 0.95, "pocket_blade": 0.45,
	"snip_twins": 0.50, "soda_cannon": 1.55, "thornmace": 0.80,
	"thorn_mace": 0.85,
	"iron_axe": 0.85, "grove_spear": 1.70, "hunter_bow": 1.15,
	"round_shield": 0.62, "siltcarver_blade": 0.95, "cinderbound_maul": 1.00,
	"tideward_staff": 1.65, "rootbound_cleaver": 1.15, "moonpact_staff": 1.65,
	"thornbite_cleaver": 0.95, "tidecall_brand": 1.65, "cinderhart_maul": 1.05,
	"oracle_crescent": 1.20,
}

static func target_length(weapon_id: String) -> float:
	return float(WEAPON_LENGTHS.get(resolve_id(weapon_id), 0.9))

static func model_max_dimension(node: Node3D, accumulated: Transform3D = Transform3D.IDENTITY) -> float:
	var basis := accumulated * node.transform
	var best := 0.0
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			var size := mesh.get_aabb().size * basis.basis.get_scale()
			best = maxf(size.x, maxf(size.y, size.z))
	for child in node.get_children():
		if child is Node3D:
			best = maxf(best, model_max_dimension(child, basis))
	return best

static func normalized_scale(weapon_id: String, model: Node3D, display_scale: float = 1.0) -> float:
	var raw := model_max_dimension(model)
	if raw <= 0.0001:
		return display_scale
	return target_length(weapon_id) * display_scale / raw

static func supported_ids() -> Array[String]:
	var result: Array[String] = []
	for weapon_id in WEAPON_PATHS:
		if not path_for(str(weapon_id)).is_empty():
			result.append(str(weapon_id))
	return result
