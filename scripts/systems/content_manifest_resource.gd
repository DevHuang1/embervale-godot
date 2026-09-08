extends Resource
class_name ContentManifestResource

## Editor/import-friendly envelope for the semantic content registry. Gameplay
## still consumes the live registry; this resource is a versioned review/build
## artifact and does not become save data.

@export var manifest_version: int = 1
@export var content_schema: int = 1
@export var registry_schema: int = 1
@export var registry: Dictionary = {}

func validate() -> Array[String]:
	var manifest := {
		"manifest_version": manifest_version,
		"content_schema": content_schema,
		"registry_schema": registry_schema,
		"registry": registry,
	}
	return ContentManifest.validate(manifest)
