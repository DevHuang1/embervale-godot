extends Resource
class_name StoreDefaults

## === Shipped store defaults ===
## Build-time store values that must exist INSIDE an exported build, because
## Android has no environment variables. Plain `.cfg` files are not packed by
## the exporter (only resources are), so these values live in a resource:
## `res://store_defaults.tres`, which is gitignored and written by
## `tools/write_store_defaults.gd` before an export.
##
## Editor and CI runs never read this resource (`StoreManager.load_build_defaults`
## is off there), so a developer's local file cannot change editor or test
## behavior. There is deliberately no identity field: every install mints its own
## customer id into `user://store.cfg`, so two installs can never share one
## purchase history. Only public values belong here; a secret (`sk_...`) is
## refused by the same validation the rest of the store uses.

@export var native_api_key := ""
@export var project_id := ""
@export var funnel_url := ""
@export var backend_url := ""

const RESOURCE_PATH := "res://store_defaults.tres"

static func load_shipped() -> StoreDefaults:
	if not ResourceLoader.exists(RESOURCE_PATH):
		return null
	return ResourceLoader.load(RESOURCE_PATH) as StoreDefaults
