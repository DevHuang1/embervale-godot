extends RefCounted
class_name AssetIntakeCatalog

## Small, typed intake registry for third-party art. Gameplay data references
## stable IDs, while this catalog keeps provenance and review state visible.
## An entry is not shippable until its local license evidence exists.

const REQUIRED_FIELDS: Array[String] = [
	"id", "pack", "package_version", "source_url", "license", "license_file", "category",
	"realm", "purpose", "mobile_status", "poly_budget", "texture_budget",
	"animation_coverage", "collision_status", "android_fallback",
	"scale_pivot", "import_settings", "runtime_owner", "runtime_use_case", "runtime_paths"
]
const APPROVED_LICENSES: Array[String] = ["CC0 1.0", "MIT", "Apache-2.0"]
const APPROVED_ASSET_EXTENSIONS: Array[String] = [".fbx", ".glb", ".gltf", ".obj", ".png", ".jpg", ".jpeg", ".svg", ".wav", ".ogg"]

const ENTRIES: Array[Dictionary] = [
	{
		"id": "kenney_nature",
		"pack": "Kenney Nature Kit",
		"package_version": "local-download-2026-09",
		"source_url": "https://kenney.nl/assets/nature-kit",
		"license": "CC0 1.0",
		"license_file": "res://assets/models/kenney_nature/License.txt",
		"category": "environment",
		"realm": "all",
		"purpose": "trees, rocks, logs, mushrooms",
		"mobile_status": "reviewed",
		"poly_budget": "reviewed",
		"texture_budget": "reviewed",
		"animation_coverage": "not_applicable",
		"collision_status": "reviewed",
		"android_fallback": "approved",
		"scale_pivot": "reviewed",
		"import_settings": "reviewed",
		"runtime_owner": "scripts/systems/grove_dressing.gd",
		"runtime_use_case": "Whispergrove and Bramblewood tree, rock, log, and mushroom dressing",
		"runtime_paths": ["res://assets/models/kenney_nature/Models/tree_detailed.fbx",
			"res://assets/models/kenney_nature/Models/tree_default.fbx",
			"res://assets/models/kenney_nature/Models/rock_smallA.fbx",
			"res://assets/models/kenney_nature/Models/rock_largeA.fbx"],
	},
	{
		"id": "kenney_graveyard",
		"pack": "Kenney Graveyard Kit",
		"package_version": "local-download-2026-09",
		"source_url": "https://kenney.nl/assets/graveyard-kit",
		"license": "CC0 1.0",
		"license_file": "res://assets/models/kenney_graveyard/License.txt",
		"category": "environment",
		"realm": "mistfen",
		"purpose": "graves, altar, coffin, fence",
		"mobile_status": "reviewed",
		"poly_budget": "reviewed",
		"texture_budget": "reviewed",
		"animation_coverage": "not_applicable",
		"collision_status": "reviewed",
		"android_fallback": "approved",
		"scale_pivot": "reviewed",
		"import_settings": "reviewed",
		"runtime_owner": "scripts/systems/grove_dressing.gd",
		"runtime_use_case": "realm ruin signature props and Mistfen graveyard dressing",
		"runtime_paths": ["res://assets/models/kenney_graveyard/Models/altar-stone.fbx",
			"res://assets/models/kenney_graveyard/Models/fence.fbx",
			"res://assets/models/kenney_graveyard/Models/candle.fbx",
			"res://assets/models/kenney_graveyard/Models/grave.fbx",
			"res://assets/models/kenney_graveyard/Models/coffin.fbx"],
	},
	{
		"id": "kenney_foliage_sprites",
		"pack": "Kenney Foliage Sprites",
		"package_version": "local-download-2026-09",
		"source_url": "https://kenney.nl/assets/foliage-sprites",
		"license": "CC0 1.0",
		"license_file": "res://assets/ambient/kenney_foliage_sprites/License.txt",
		"category": "foliage",
		"realm": "all",
		"purpose": "grass, flowers, bushes, field detail",
		"mobile_status": "reviewed",
		"poly_budget": "reviewed",
		"texture_budget": "reviewed",
		"animation_coverage": "not_applicable",
		"collision_status": "not_applicable",
		"android_fallback": "approved",
		"scale_pivot": "reviewed",
		"import_settings": "reviewed",
		"runtime_owner": "scripts/systems/ambient_foliage_patch.gd",
		"runtime_use_case": "bounded grass and field-detail patches in streamed realm chunks",
		"runtime_paths": ["res://assets/ambient/kenney_foliage_sprites/Vector/foliageSprites_flat.svg"],
	},
	{
		"id": "kenney_survival",
		"pack": "Kenney Survival Kit",
		"package_version": "local-download-2026-09",
		"source_url": "https://kenney.nl/assets/survival-kit",
		"license": "CC0 1.0",
		"license_file": "res://assets/models/kenney_survival/License.txt",
		"category": "props",
		"realm": "all",
		"purpose": "barrels, bedrolls, bottles, fences, tents",
		"mobile_status": "reviewed",
		"poly_budget": "reviewed",
		"texture_budget": "reviewed",
		"animation_coverage": "not_applicable",
		"collision_status": "reviewed",
		"android_fallback": "approved",
		"scale_pivot": "reviewed",
		"import_settings": "reviewed",
		"runtime_owner": "scripts/systems/grove_dressing.gd",
		"runtime_use_case": "camp props and Survival Kit tent/barrel dressing near route landmarks",
		"runtime_paths": ["res://assets/models/kenney_survival/Models/tent.fbx",
			"res://assets/models/kenney_survival/Models/bedroll.fbx",
			"res://assets/models/kenney_survival/Models/barrel.fbx",
			"res://assets/models/kenney_survival/Models/bottle.fbx",
			"res://assets/models/kenney_survival/Models/barrel-open.fbx",
			"res://assets/models/kenney_survival/Models/fence.fbx"],
	},
	{
		"id": "kenney_tower_defense",
		"pack": "Kenney Tower Defense Kit",
		"package_version": "local-download-2026-09",
		"source_url": "https://kenney.nl/assets/tower-defense-kit",
		"license": "CC0 1.0",
		"license_file": "res://assets/models/kenney_tower_defense/License.txt",
		"category": "props",
		"realm": "heartwood",
		"purpose": "crystals, rocks, tree detail",
		"mobile_status": "reviewed",
		"poly_budget": "reviewed",
		"texture_budget": "reviewed",
		"animation_coverage": "not_applicable",
		"collision_status": "reviewed",
		"android_fallback": "approved",
		"scale_pivot": "reviewed",
		"import_settings": "reviewed",
		"runtime_owner": "scripts/systems/grove_dressing.gd",
		"runtime_use_case": "Heartwood crystal and detail-rock realm accents",
		"runtime_paths": ["res://assets/models/kenney_tower_defense/Models/detail-crystal.fbx",
			"res://assets/models/kenney_tower_defense/Models/detail-rocks.fbx",
			"res://assets/models/kenney_tower_defense/Models/detail-tree.fbx"],
	},
	{
		"id": "kenney_mini_dungeon",
		"pack": "Kenney Mini Dungeon",
		"package_version": "local-download-2026-09",
		"source_url": "https://kenney.nl/assets/mini-dungeon",
		"license": "CC0 1.0",
		"license_file": "res://assets/models/kenney_mini_dungeon/License.txt",
		"category": "characters",
		"realm": "all",
		"purpose": "human, orc, and dungeon props",
		"mobile_status": "reviewed",
		"poly_budget": "reviewed",
		"texture_budget": "reviewed",
		"animation_coverage": "partial_fallback",
		"collision_status": "reviewed",
		"android_fallback": "approved",
		"scale_pivot": "reviewed",
		"import_settings": "reviewed",
		"runtime_owner": "scripts/systems/character_rig_loader.gd",
		"runtime_use_case": "merchant, craftsman, human, and orc service/encounter characters",
		"runtime_paths": ["res://assets/models/kenney_mini_dungeon/Models/character-human.fbx",
			"res://assets/models/kenney_mini_dungeon/Models/character-orc.fbx"],
	},
	{
		"id": "kenney_mini_dungeon_props",
		"pack": "Kenney Mini Dungeon",
		"package_version": "local-download-2026-09",
		"source_url": "https://kenney.nl/assets/mini-dungeon",
		"license": "CC0 1.0",
		"license_file": "res://assets/models/kenney_mini_dungeon/License.txt",
		"category": "props", "realm": "all",
		"purpose": "landmark chest, banner, column, wall, and chair props",
		"mobile_status": "reviewed", "poly_budget": "reviewed",
		"texture_budget": "reviewed", "animation_coverage": "not_applicable",
		"collision_status": "reviewed", "android_fallback": "approved",
		"scale_pivot": "reviewed", "import_settings": "reviewed",
		"runtime_owner": "scripts/systems/grove_dressing.gd",
		"runtime_use_case": "bounded dungeon props at authored realm landmarks",
		"runtime_paths": [
			"res://assets/models/kenney_mini_dungeon/Models/chest.fbx",
			"res://assets/models/kenney_mini_dungeon/Models/banner.fbx",
			"res://assets/models/kenney_mini_dungeon/Models/column.fbx",
			"res://assets/models/kenney_mini_dungeon/Models/wall.fbx",
			"res://assets/models/kenney_mini_dungeon/Models/chair.fbx",
			"res://assets/models/kenney_mini_dungeon/Models/barrel.fbx",
			"res://assets/models/kenney_mini_dungeon/Models/floor.fbx"],
	},
	{
		"id": "quaternius_weapons",
		"pack": "Quaternius Medieval Weapons",
		"package_version": "local-download-2026-09",
		"source_url": "https://quaternius.com/packs/medievalweapons.html",
		"license": "CC0 1.0",
		"license_file": "res://assets/models/weapons/quaternius/LICENSES.md",
		"category": "props", "realm": "all",
		"purpose": "runtime hand weapons and intentional missing-asset fallbacks",
		"mobile_status": "reviewed", "poly_budget": "reviewed",
		"texture_budget": "reviewed", "animation_coverage": "not_applicable",
		"collision_status": "not_applicable", "android_fallback": "approved",
		"scale_pivot": "reviewed", "import_settings": "reviewed",
		"runtime_owner": "scripts/systems/weapon_visual_registry.gd",
		"runtime_use_case": "hero hand weapon visuals for mace, blades, and hammer fallbacks",
		"runtime_paths": [
			"res://assets/models/weapons/quaternius/Hammer_Double.fbx",
			"res://assets/models/weapons/quaternius/Dagger.fbx",
			"res://assets/models/weapons/quaternius/Dagger_2.fbx"],
	},
	{
		"id": "quaternius_realm_creatures",
		"pack": "Quaternius Animated Animals",
		"package_version": "local-download-2026-09",
		"source_url": "https://quaternius.com/",
		"license": "CC0 1.0",
		"license_file": "res://assets/models/enemies/quaternius/LICENSES.md",
		"category": "characters", "realm": "all",
		"purpose": "visible realm enemy silhouettes",
		"mobile_status": "reviewed", "poly_budget": "reviewed",
		"texture_budget": "reviewed", "animation_coverage": "partial_fallback",
		"collision_status": "reviewed", "android_fallback": "approved",
		"scale_pivot": "reviewed", "import_settings": "reviewed",
		"runtime_owner": "scripts/systems/enemy_visual_registry.gd",
		"runtime_use_case": "frog, rat, snake, spider, and wasp models mounted on realm combat archetypes",
		"runtime_paths": [
			"res://assets/models/enemies/quaternius/Frog.fbx",
			"res://assets/models/enemies/quaternius/Rat.fbx",
			"res://assets/models/enemies/quaternius/Snake_angry.fbx",
			"res://assets/models/enemies/quaternius/Spider.fbx",
			"res://assets/models/enemies/quaternius/Wasp.fbx"],
	},
]

static func validate_entries(entries: Array[Dictionary] = ENTRIES) -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for entry in entries:
		for field in REQUIRED_FIELDS:
			if not entry.has(field) or str(entry[field]).strip_edges().is_empty():
				errors.append("Missing asset intake field '%s'" % field)
		var asset_id := str(entry.get("id", "")).strip_edges()
		if asset_id.is_empty() or seen.has(asset_id):
			errors.append("Duplicate or empty asset intake ID: %s" % asset_id)
		seen[asset_id] = true
		if str(entry.get("license", "")) == "UNKNOWN":
			errors.append("Uncleared license for asset: %s" % asset_id)
		if str(entry.get("license", "")) not in APPROVED_LICENSES:
			errors.append("License requires legal review for asset: %s" % asset_id)
		if not str(entry.get("source_url", "")).begins_with("https://"):
			errors.append("Asset source must use HTTPS: %s" % asset_id)
		for status_field in ["poly_budget", "texture_budget", "animation_coverage",
			"collision_status", "android_fallback"]:
			if str(entry.get(status_field, "")) in ["unknown", "pending", "rejected"]:
				errors.append("Unapproved %s for asset: %s" % [status_field, asset_id])
		var license_file := str(entry.get("license_file", ""))
		if not license_file.is_empty() and not FileAccess.file_exists(license_file):
			errors.append("Missing local license evidence for asset: %s" % asset_id)
		var runtime_paths: Array = entry.get("runtime_paths", [])
		if runtime_paths.is_empty():
			errors.append("Missing runtime asset path for pack: %s" % asset_id)
		var owner_path := str(entry.get("runtime_owner", "")).strip_edges()
		var owner_file := owner_path if owner_path.begins_with("res://") \
			else "res://" + owner_path
		var owner_source := FileAccess.get_file_as_string(owner_file) \
			if FileAccess.file_exists(owner_file) else ""
		if owner_source.is_empty() and not owner_path.is_empty():
			errors.append("Missing runtime owner source for asset: %s" % asset_id)
		for runtime_path in runtime_paths:
			var path_string := str(runtime_path)
			var extension := path_string.get_extension().to_lower()
			if not path_string.begins_with("res://assets/"):
				errors.append("Runtime asset must stay under res://assets/: %s" % path_string)
			if extension.is_empty() or not ("." + extension) in APPROVED_ASSET_EXTENSIONS:
				errors.append("Unsupported runtime asset extension for %s: %s" % [asset_id, path_string])
			if not FileAccess.file_exists(path_string):
				errors.append("Missing runtime asset path for %s: %s" % [asset_id, runtime_path])
			elif not owner_source.contains(path_string.get_file()):
				errors.append("Runtime owner does not reference %s: %s" % [path_string, owner_path])
			else:
				var resource := load(path_string)
				if resource == null:
					errors.append("Runtime asset failed to import for %s: %s" % [asset_id, path_string])
				elif resource is PackedScene:
					var instance := (resource as PackedScene).instantiate()
					var meshes := instance.find_children("*", "MeshInstance3D", true, false)
					if meshes.is_empty():
						errors.append("Imported model has no MeshInstance3D for %s: %s" % [asset_id, path_string])
					else:
						_validate_model_import(instance, asset_id, path_string, errors)
					instance.free()
				elif resource is Texture2D:
					var texture := resource as Texture2D
					if texture.get_width() <= 0 or texture.get_height() <= 0:
						errors.append("Imported texture has invalid dimensions for %s: %s" % [asset_id, path_string])
	return errors

static func _validate_model_import(instance: Node, asset_id: String,
		path: String, errors: Array[String]) -> void:
	var node_3d := instance as Node3D
	if node_3d != null:
		var root_position := node_3d.position
		var root_rotation := node_3d.rotation
		var root_scale := node_3d.scale
		if not _finite_vector3(root_position) or not _finite_vector3(root_rotation):
			errors.append("Imported model has invalid root transform for %s: %s" % [asset_id, path])
		if not _finite_vector3(root_scale) or root_scale.length() < 0.001 \
				or root_scale.length() > 100.0:
			errors.append("Imported model has implausible root scale for %s: %s" % [asset_id, path])
	var material_count := 0
	var animation_count := 0
	for child in instance.find_children("*", "Node", true, false):
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.mesh != null:
				material_count += mesh_instance.mesh.get_surface_count()
		if child is AnimationPlayer:
			animation_count += (child as AnimationPlayer).get_animation_list().size()
	if material_count > 24:
		errors.append("Imported model exceeds 24 material surfaces for %s: %s" % [asset_id, path])
	if str(path).contains("character") and animation_count == 0:
		errors.append("Character import has no animation library for %s: %s" % [asset_id, path])

static func _finite_vector3(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

static func reviewed_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in ENTRIES:
		if str(entry.get("mobile_status", "")) == "reviewed":
			result.append(entry.duplicate(true))
	return result

static func quality_score(entry: Dictionary) -> int:
	var score := 0
	if str(entry.get("license", "")) in APPROVED_LICENSES and not str(entry.get("license_file", "")).is_empty():
		score += 20
	if str(entry.get("source_url", "")).begins_with("https://"):
		score += 10
	if str(entry.get("mobile_status", "")) == "reviewed":
		score += 20
	if str(entry.get("poly_budget", "")) == "reviewed":
		score += 15
	if str(entry.get("texture_budget", "")) == "reviewed":
		score += 15
	if str(entry.get("collision_status", "")) in ["reviewed", "not_applicable"]:
		score += 10
	if str(entry.get("android_fallback", "")) == "approved":
		score += 10
	return score

static func quality_band(entry: Dictionary) -> String:
	var score := quality_score(entry)
	return "SHIP-READY" if score >= 90 else ("REVIEW" if score >= 70 else "HOLD")

static func inventory_downloaded_assets() -> Array[Dictionary]:
	## Inventory source files without treating importer metadata as game content.
	## Every file is classified so unused variants remain an explicit decision.
	var inventory: Array[Dictionary] = []
	var claimed: Dictionary = {}
	for entry in ENTRIES:
		for runtime_path in entry.get("runtime_paths", []):
			claimed[str(runtime_path)] = str(entry.get("id", ""))
	for root_path in ["res://assets/models", "res://assets/ambient"]:
		_collect_asset_files(root_path, claimed, inventory)
	return inventory

static func _collect_asset_files(path: String, claimed: Dictionary,
		inventory: Array[Dictionary]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for name in directory.get_files():
		var file_path := path.path_join(name)
		var extension := name.get_extension().to_lower()
		if extension in ["import", "txt", "md", "url"]:
			continue
		var classification := "GAMEPLAY" if claimed.has(file_path) else "REVIEW_ONLY"
		inventory.append({"path": file_path, "classification": classification,
			"owner": str(claimed.get(file_path, ""))})
	for name in directory.get_directories():
		_collect_asset_files(path.path_join(name), claimed, inventory)
