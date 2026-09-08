extends RefCounted
class_name ContentManifest

const CURRENT_VERSION: int = 1
const SCHEMA = preload("res://scripts/systems/content_schema.gd")
const REGISTRY = preload("res://scripts/systems/content_registry.gd")

static func from_registry(registry: Dictionary) -> Dictionary:
	return {"manifest_version": CURRENT_VERSION, "content_schema": SCHEMA.CURRENT_VERSION,
		"registry_schema": REGISTRY.CURRENT_VERSION, "registry": registry.duplicate(true)}

static func resource_from_registry(registry: Dictionary) -> Resource:
	var resource := ContentManifestResource.new()
	resource.manifest_version = CURRENT_VERSION
	resource.content_schema = SCHEMA.CURRENT_VERSION
	resource.registry_schema = REGISTRY.CURRENT_VERSION
	resource.registry = registry.duplicate(true)
	return resource

static func validate(manifest: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if int(manifest.get("manifest_version", 0)) != CURRENT_VERSION:
		errors.append("Unsupported content manifest version")
	if int(manifest.get("content_schema", 0)) != SCHEMA.CURRENT_VERSION:
		errors.append("Unsupported content schema version")
	var registry: Dictionary = manifest.get("registry", {})
	errors.append_array(REGISTRY.validate(registry))
	return errors

static func migrate(manifest: Variant) -> Dictionary:
	if not manifest is Dictionary:
		return {"manifest_version": CURRENT_VERSION, "content_schema": SCHEMA.CURRENT_VERSION,
			"registry_schema": REGISTRY.CURRENT_VERSION, "registry": {}}
	var source: Dictionary = manifest
	var result := source.duplicate(true)
	result["manifest_version"] = CURRENT_VERSION
	result["content_schema"] = SCHEMA.CURRENT_VERSION
	result["registry_schema"] = REGISTRY.CURRENT_VERSION
	if not result.get("registry", {}) is Dictionary:
		result["registry"] = {}
	return result
