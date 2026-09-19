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
## The shipped form of the key: sealed by `tools/write_store_defaults.gd` so a
## literal copy-paste of the resource does not yield a usable key. Sealing is
## obfuscation (the passphrase ships in the same client), not confidentiality.
@export var native_api_key_sealed := ""
@export var project_id := ""
@export var funnel_url := ""
@export var backend_url := ""
## Low-privilege app token for the backend authority. It can only read the
## entitlements of the RevenueCat customer the game names — the provider secret
## stays on the server — so it is a rotatable client credential, not a secret.
## It is validated as a safe header value before it is ever sent.
@export var access_token := ""

const RESOURCE_PATH := "res://store_defaults.tres"

static func load_shipped() -> StoreDefaults:
	if not ResourceLoader.exists(RESOURCE_PATH):
		return null
	return ResourceLoader.load(RESOURCE_PATH) as StoreDefaults

## The key the store should use: a plaintext value is honored (local/dev
## resources and test fixtures), otherwise the sealed field is unsealed. An
## unrecoverable value resolves to "" so the store fails closed.
func resolved_native_api_key() -> String:
	var plain := native_api_key.strip_edges()
	if not plain.is_empty():
		return plain
	return StoreSecurity.unseal(native_api_key_sealed)

func has_native_key() -> bool:
	return not resolved_native_api_key().is_empty()
