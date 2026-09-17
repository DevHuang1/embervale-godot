extends SceneTree

## Headless contract suite for the RevenueCat NATIVE authority.
##
## The Android plugin cannot exist here, so every branch is driven through an
## injected fake with the same signals and methods. What is being verified is
## the contract that matters on device: one parse path, one claim path, no
## secret, and a web purchase that can only ever be granted once.
##
## This suite points GameState at a scratch save file BEFORE it mutates
## anything, so running it can never overwrite a developer's real save.

const BRIDGE := preload("res://scripts/systems/revenuecat_native_bridge.gd")
const CATALOG := preload("res://scripts/systems/web_store_catalog.gd")
const SECURITY := preload("res://scripts/systems/store_security.gd")
const SCRATCH_SAVE := "user://test_revenuecat_native_scratch.cfg"
const PUBLIC_KEY := "test_" + "A1b2C3d4E5f6G7h8"

var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_absent_singleton_is_a_no_op()
	_test_public_key_validation()
	await _test_entitlement_conversion()
	await _test_error_mapping()
	await _test_native_authority_claims_once()
	_test_stored_config_is_revalidated()
	await _test_secret_as_public_key_is_refused()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_SAVE))
	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		print("REVENUECAT NATIVE BRIDGE TESTS FAILED (%d)" % _failures.size())
		quit(1)
		return
	print("REVENUECAT NATIVE BRIDGE TESTS PASSED")
	quit(0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _game_state() -> GameState:
	return get_root().get_node_or_null("GameState") as GameState

func _store() -> StoreManager:
	return get_root().get_node_or_null("StoreManager") as StoreManager

func _use_scratch_save() -> void:
	var gs := _game_state()
	if gs == null:
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_SAVE))
	gs.save_path = SCRATCH_SAVE

func _test_absent_singleton_is_a_no_op() -> void:
	var bridge := BRIDGE.new()
	_check(not bridge.is_available(),
		"without an Android singleton the bridge must report unavailable")
	_check(not bridge.configure(PUBLIC_KEY, "ev_123"),
		"configuring an absent bridge must report failure, not crash")
	_check(not bridge.log_in("ev_123"), "logging in an absent bridge must be a no-op")
	_check(not bridge.log_out(), "logging out an absent bridge must be a no-op")

func _test_public_key_validation() -> void:
	_check(SECURITY.validate_public_sdk_key(PUBLIC_KEY) == "",
		"a test-store public key must validate")
	_check(SECURITY.validate_public_sdk_key("goog_" + "A1b2C3d4E5f6G7h8") == "",
		"a Google Play public key must validate")
	_check(SECURITY.validate_public_sdk_key("") == "empty_public_key",
		"an empty public key must be refused")
	_check(SECURITY.validate_public_sdk_key("sk_" + "A1b2C3d4E5f6G7h8") == "public_key_prefix",
		"a secret key must never be accepted where a public key belongs")
	_check(SECURITY.validate_public_sdk_key("test_short") == "public_key_too_short",
		"an implausibly short key must be refused")
	_check(SECURITY.validate_public_sdk_key("test_" + "A".repeat(300)) == "public_key_too_long",
		"an oversized key must be refused")
	_check(SECURITY.validate_public_sdk_key("test_" + "A1b2 C3d4E5f6G7h8") == "public_key_charset",
		"a key carrying spaces must be refused")

func _test_entitlement_conversion() -> void:
	var fake := FakeBridge.new()
	var bridge := BRIDGE.new(fake)
	_check(bridge.is_available(), "an injected singleton must make the bridge available")
	_check(bridge.configure(PUBLIC_KEY, "ev_device"),
		"configure must reach the injected singleton")
	_check(fake.configured == PUBLIC_KEY, "the public key must be handed to the SDK")
	_check(fake.configured_user == "ev_device",
		"the App User ID must match the id the funnel appends")

	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	fake.response = JSON.stringify({
		"object": "list",
		"source": "revenuecat_native",
		"items": [
			{"entitlement_id": "embermarks_cache", "expires_at": null},
			{"entitlement_id": "embermarks_pouch", "expires_at": now_ms + 86_400_000},
			{"entitlement_id": "lapsed_pack", "expires_at": now_ms - 1_000},
			{"entitlement_id": "", "expires_at": null},
			"not-an-object",
		],
	})
	var parsed: Dictionary = await bridge.fetch_active_entitlements()
	_check(bool(parsed.get("ok", false)), "a well-formed payload must parse")
	var active: Array = parsed.get("active", [])
	_check(active.size() == 2, "only usable, unexpired rows must survive (got %d)" % active.size())
	var lifetime := _find_entitlement(active, "embermarks_cache")
	_check(int(lifetime.get("expires_at_ms", 0)) == -1,
		"a null expiry must survive as a lifetime entitlement")
	var expiring := _find_entitlement(active, "embermarks_pouch")
	_check(int(expiring.get("expires_at_ms", 0)) == now_ms + 86_400_000,
		"a future expiry must be preserved exactly")
	_check(_find_entitlement(active, "lapsed_pack").is_empty(),
		"an already-expired entitlement must never be returned")
	_check(fake.fetch_count == 1, "each read must issue exactly one SDK request")

	var many: Array = []
	for index in 150:
		many.append({"entitlement_id": "pack_%d" % index, "expires_at": null})
	fake.response = JSON.stringify({"items": many})
	var capped: Dictionary = await bridge.fetch_active_entitlements()
	_check((capped.get("active", []) as Array).size() == 100,
		"the row count must stay hard-capped")

	fake.response = "{not json"
	var malformed: Dictionary = await bridge.fetch_active_entitlements()
	_check(not bool(malformed.get("ok", false)), "invalid JSON must never report success")
	_check(str(malformed.get("error", "")) == "malformed_response",
		"invalid JSON must be reported as malformed (got %s)" % str(malformed.get("error", "")))

func _test_error_mapping() -> void:
	var cases := {
		"NETWORK_ERROR": "offline",
		"OFFLINE_CONNECTION_ERROR": "offline",
		"NOT_CONFIGURED": "unconfigured",
		"INVALID_CREDENTIALS_ERROR": "unauthorized",
		"UNEXPECTED_BACKEND_RESPONSE_ERROR": "provider_error",
	}
	for code in cases:
		var fake := FakeBridge.new()
		fake.error_code = str(code)
		fake.error_message = "simulated failure"
		var bridge := BRIDGE.new(fake)
		var result: Dictionary = await bridge.fetch_active_entitlements()
		_check(not bool(result.get("ok", false)), "%s must never report success" % code)
		_check(str(result.get("status", "")) == str(cases[code]),
			"%s must map to status %s (got %s)" % [code, str(cases[code]),
				str(result.get("status", ""))])

func _test_native_authority_claims_once() -> void:
	var store := _store()
	var gs := _game_state()
	if store == null or gs == null:
		_failures.append("GameState/StoreManager autoloads are missing")
		return
	_use_scratch_save()
	gs.reset()

	var fake := FakeBridge.new()
	fake.response = JSON.stringify({"items": [
		{"entitlement_id": "embermarks_cache", "expires_at": null},
	]})
	store.native_bridge = BRIDGE.new(fake)
	var configured: bool = store.configure("", "", "", "https://signup.cat/link_abc",
		"", PUBLIC_KEY)
	_check(configured, "a public key alone must configure the native authority")
	_check(store.authority_name() == "native",
		"a public key must select the native authority (got %s)" % store.authority_name())
	_check(store.is_available(), "a configured native store must be available")
	var url := store.checkout_url()
	_check(url.begins_with("https://signup.cat/link_abc/"),
		"checkout must still stay on the configured hosted funnel")
	_check(url.ends_with(store.customer_id().uri_encode()),
		"checkout must carry the same App User ID the SDK reads for")
	_check(fake.configured_user == store.customer_id(),
		"the SDK and the funnel must share one App User ID")

	var tier: Dictionary = CATALOG.tier_for_entitlement("embermarks_cache")
	var expected := int(tier.get("diamonds", 0))
	var first: Dictionary = await store.refresh_and_claim()
	_check(bool(first.get("ok", false)), "a native read must report success")
	_check(int(first.get("granted", 0)) == 1, "the first native claim must grant one pack")
	_check(int(first.get("diamonds", 0)) == expected, "the grant must match the catalogued tier")
	_check(gs.diamonds == expected, "ember marks must be delivered exactly once")
	var second: Dictionary = await store.refresh_and_claim()
	_check(int(second.get("granted", 0)) == 0,
		"a repeated native refresh must not grant again")
	_check(gs.diamonds == expected, "a repeated refresh must not inflate the balance")
	_check(gs.is_provider_claim_recorded("revenuecat:embermarks_cache:one_time"),
		"the ledger must record the native provider claim id")
	store.configure("", "", "", "", "")

func _test_stored_config_is_revalidated() -> void:
	var store := _store()
	if store == null:
		_failures.append("StoreManager autoload is missing")
		return
	var scratch := "user://test_revenuecat_native_store.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	store.config_path = scratch
	var cfg := ConfigFile.new()
	cfg.set_value("store", "funnel_url", "https://evil.example.com/checkout")
	cfg.set_value("store", "native_api_key", "sk_" + "A1b2C3d4E5f6G7h8")
	cfg.set_value("store", "customer_id", "ev_scratch")
	cfg.save(scratch)
	store.load_config()
	_check(store.checkout_url().is_empty(),
		"a stored funnel URL on a disallowed host must never build a checkout URL")
	_check(store.authority_name() == "none",
		"a stored secret-shaped key must not resolve an authority")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	store.config_path = "user://store.cfg"
	store.configure("", "", "", "", "")

func _test_secret_as_public_key_is_refused() -> void:
	var store := _store()
	if store == null:
		_failures.append("StoreManager autoload is missing")
		return
	var configured: bool = store.configure("", "", "", "", "", "sk_" + "A1b2C3d4E5f6G7h8")
	_check(not configured, "a secret key must never be accepted as a public SDK key")
	_check(store.authority_name() == "none",
		"a rejected configuration must leave no authority in place")
	store.configure("", "", "", "", "")

func _find_entitlement(rows: Array, entitlement_id: String) -> Dictionary:
	for row in rows:
		if row is Dictionary and str((row as Dictionary).get("entitlement_id", "")) == entitlement_id:
			return row as Dictionary
	return {}


## Mirrors the Android plugin's signals and methods so the GDScript half can be
## exercised without a device.
class FakeBridge extends RefCounted:
	signal active_entitlements(payload: String)
	signal customer_info_error(code: String, message: String)

	var configured := ""
	var configured_user := ""
	var fetch_count := 0
	var response := ""
	var error_code := ""
	var error_message := ""
	var sdk_configured := true

	func configure(api_key: String, app_user_id: String) -> void:
		configured = api_key
		configured_user = app_user_id

	func isConfigured() -> bool:
		return sdk_configured

	func logIn(app_user_id: String) -> void:
		configured_user = app_user_id

	func logOut() -> void:
		pass

	func getActiveEntitlements() -> void:
		fetch_count += 1
		if error_code.is_empty():
			active_entitlements.emit(response)
		else:
			customer_info_error.emit(error_code, error_message)
