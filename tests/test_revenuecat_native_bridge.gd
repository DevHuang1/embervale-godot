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
const SHOP_SCENE := "res://scenes/ui/diamond_shop.tscn"
const PUBLIC_KEY := "test_" + "A1b2C3d4E5f6G7h8"

var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_absent_singleton_is_a_no_op()
	_test_public_key_validation()
	await _test_entitlement_conversion()
	await _test_transaction_read_contract()
	await _test_error_mapping()
	await _test_native_authority_claims_once()
	await _test_purchase_contract()
	await _test_native_authority_buy_delivers()
	await _test_native_pack_buttons_visibility()
	_test_build_defaults_feed_the_store()
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

func _test_transaction_read_contract() -> void:
	var absent := BRIDGE.new()
	var no_singleton: Dictionary = await absent.fetch_non_subscription_transactions()
	_check(not bool(no_singleton.get("ok", false)),
		"without a singleton the transaction read must fail, not crash")
	_check(str(no_singleton.get("status", "")) == "unavailable",
		"an absent bridge must report unavailable")

	var fake := FakeBridge.new()
	fake.transaction_response = JSON.stringify({"items": [
		{"transaction_id": "txn_a", "product_id": "embermarks_pouch", "purchased_at": 1_700_000_000_000},
		{"transaction_id": "txn_b", "product_id": "embermarks_cache", "purchased_at": 1_700_000_100_000},
		{"product_id": "embermarks_pouch"},
		{"transaction_id": "txn_c"},
	]})
	var bridge := BRIDGE.new(fake)
	var parsed: Dictionary = await bridge.fetch_non_subscription_transactions()
	_check(bool(parsed.get("ok", false)), "a transaction read must report success")
	var rows: Array = parsed.get("transactions", [])
	_check(rows.size() == 2, "malformed transaction rows must be dropped (got %d)" % rows.size())
	_check(str(rows[0].get("transaction_id", "")) == "txn_a"
			and str(rows[0].get("product_id", "")) == "embermarks_pouch",
		"a transaction row must keep its id and product")
	_check(int(rows[0].get("purchased_at_ms", 0)) == 1_700_000_000_000,
		"a transaction row must keep its purchase time")

	var broken := FakeBridge.new()
	broken.transaction_response = "{not json"
	var broken_bridge := BRIDGE.new(broken)
	var malformed: Dictionary = await broken_bridge.fetch_non_subscription_transactions()
	_check(not bool(malformed.get("ok", false)),
		"a malformed transaction body must not be treated as a purchase list")

	var offline := FakeBridge.new()
	offline.error_code = "NETWORK_ERROR"
	offline.error_message = "simulated failure"
	var offline_bridge := BRIDGE.new(offline)
	var failed: Dictionary = await offline_bridge.fetch_non_subscription_transactions()
	_check(str(failed.get("status", "")) == "offline",
		"a network failure must map to the offline status")

func _test_native_authority_claims_once() -> void:
	var store := _store()
	var gs := _game_state()
	if store == null or gs == null:
		_failures.append("GameState/StoreManager autoloads are missing")
		return
	_use_scratch_save()
	gs.reset()

	var fake := FakeBridge.new()
	# The same consumable bought twice, plus the entitlement RevenueCat keeps
	# active for it. Only the transactions are purchases.
	fake.response = JSON.stringify({"items": [
		{"entitlement_id": "embermarks_pouch", "expires_at": null},
	]})
	fake.transaction_response = JSON.stringify({"items": [
		{"transaction_id": "txn_one", "product_id": "embermarks_pouch", "purchased_at": 1},
		{"transaction_id": "txn_two", "product_id": "embermarks_pouch", "purchased_at": 2},
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

	var tier: Dictionary = CATALOG.tier_for_product("embermarks_pouch")
	var expected := int(tier.get("diamonds", 0))
	var first: Dictionary = await store.refresh_and_claim()
	_check(bool(first.get("ok", false)), "a native read must report success")
	_check(int(first.get("granted", 0)) == 2,
		"each purchase of a repeatable pack must grant once (got %d)" % int(first.get("granted", 0)))
	_check(int(first.get("diamonds", 0)) == expected * 2,
		"two purchases must deliver two packs")
	_check(gs.diamonds == expected * 2, "ember marks must be delivered exactly once per purchase")
	var second: Dictionary = await store.refresh_and_claim()
	_check(int(second.get("granted", 0)) == 0,
		"re-reading the same transactions must not grant again")
	_check(gs.diamonds == expected * 2, "a repeated refresh must not inflate the balance")
	_check(gs.is_provider_claim_recorded(CATALOG.record_id_for_transaction("embermarks_pouch", "txn_one"))
			and gs.is_provider_claim_recorded(CATALOG.record_id_for_transaction("embermarks_pouch", "txn_two")),
		"the ledger must record one transaction key per purchase")
	_check(not gs.is_provider_claim_recorded("revenuecat:embermarks_pouch:one_time"),
		"a consumable must never be recorded under an entitlement key")

	var only_entitlement := FakeBridge.new()
	only_entitlement.response = fake.response
	only_entitlement.transaction_response = JSON.stringify({"items": []})
	store.native_bridge = BRIDGE.new(only_entitlement)
	var entitlement_only: Dictionary = await store.refresh_and_claim()
	_check(int(entitlement_only.get("granted", 0)) == 0,
		"an active entitlement alone must not re-grant a consumable")
	_check(gs.diamonds == expected * 2,
		"an entitlement read must not change the balance of a consumable")
	store.configure("", "", "", "", "")

## A purchase reports status only. The claim re-reads provider state, so a
## status can never grant by itself and a cancel is never an error.
func _test_purchase_contract() -> void:
	var absent := BRIDGE.new()
	var no_singleton: Dictionary = await absent.purchase("embermarks_pouch")
	_check(str(no_singleton.get("status", "")) == "unavailable",
		"purchasing without an Android singleton must report unavailable")

	var legacy := BRIDGE.new(LegacyBridge.new())
	var unsupported: Dictionary = await legacy.purchase("embermarks_pouch")
	_check(str(unsupported.get("status", "")) == "unsupported",
		"a plugin without purchase() must report unsupported, not crash")

	var fake := FakeBridge.new()
	var bridge := BRIDGE.new(fake)
	var empty: Dictionary = await bridge.purchase("   ")
	_check(str(empty.get("status", "")) == "invalid_product",
		"an empty product id must be refused before the SDK is called")
	_check(fake.purchase_count == 0, "a refused product id must never reach the SDK")

	fake.purchase_status = "purchased"
	var bought: Dictionary = await bridge.purchase("embermarks_pouch")
	_check(bool(bought.get("ok", false)), "a completed purchase must parse as ok")
	_check(str(bought.get("status", "")) == "purchased", "the purchase status must survive")
	_check(str(bought.get("product_id", "")) == "embermarks_pouch",
		"the purchase result must name the product it bought")
	_check(fake.purchase_count == 1, "each buy must issue exactly one SDK request")

	fake.purchase_status = "cancelled"
	var cancelled: Dictionary = await bridge.purchase("embermarks_pouch")
	_check(not bool(cancelled.get("ok", false)), "a cancel must not report success")
	_check(str(cancelled.get("status", "")) == "cancelled",
		"a cancel must be its own status, not an error")

	fake.purchase_status = "error"
	fake.purchase_error_code = "NETWORK_ERROR"
	var offline: Dictionary = await bridge.purchase("embermarks_pouch")
	_check(str(offline.get("status", "")) == "offline",
		"a network failure must map onto the store vocabulary (got %s)" % offline.get("status", ""))
	_check(str(offline.get("error", "")) == "network_error",
		"the provider's own code must be preserved for support")

	fake.purchase_error_code = "SOMETHING_NEW"
	var unknown: Dictionary = await bridge.purchase("embermarks_pouch")
	_check(str(unknown.get("status", "")) == "provider_error",
		"an unmapped code must fall back to provider_error")

	var malformed := BRIDGE.new(MalformedPurchaseBridge.new())
	var broken: Dictionary = await malformed.purchase("embermarks_pouch")
	_check(not bool(broken.get("ok", false)), "a malformed purchase payload must not parse as ok")
	_check(str(broken.get("error", "")) == "malformed_response",
		"a malformed purchase payload must be named as such")

func _test_native_authority_buy_delivers() -> void:
	var store := _store()
	var gs := _game_state()
	if store == null or gs == null:
		_failures.append("GameState/StoreManager autoloads are missing")
		return
	_use_scratch_save()
	gs.reset()
	var fake := FakeBridge.new()
	fake.response = JSON.stringify({"items": []})
	fake.transaction_response = JSON.stringify({"items": []})
	fake.purchase_transaction_id = "txn_buy_one"
	store.native_bridge = BRIDGE.new(fake)
	_check(store.configure("", "", "", "", "", PUBLIC_KEY),
		"a public key alone must configure the native authority")
	var tier: Dictionary = CATALOG.tier_for_product("embermarks_pouch")
	var expected := int(tier.get("diamonds", 0))

	# Refreshing immediately before the purchase proves the buy path is not
	# throttled: a purchase that just completed must always be claimable.
	await store.refresh_and_claim()
	var bought: Dictionary = await store.buy("embermarks_pouch")
	_check(bool(bought.get("ok", false)), "a completed purchase must be claimed")
	_check(str(bought.get("status", "")) == "purchased", "the outcome must be reported")
	_check(int(bought.get("diamonds", 0)) == expected,
		"the purchase must deliver its pack (got %d)" % int(bought.get("diamonds", 0)))
	_check(gs.diamonds == expected, "ember marks must be delivered exactly once")
	_check(fake.purchase_count == 1, "exactly one SDK purchase must be started")
	_check(gs.is_provider_claim_recorded(
			CATALOG.record_id_for_transaction("embermarks_pouch", "txn_buy_one")),
		"the ledger must record the purchase's transaction key")

	# Buying the same pack again is a new transaction, so it delivers again.
	fake.purchase_transaction_id = "txn_buy_two"
	var again: Dictionary = await store.buy("embermarks_pouch")
	_check(int(again.get("diamonds", 0)) == expected,
		"a second purchase of the same pack must deliver again")
	_check(gs.diamonds == expected * 2, "two purchases must deliver two packs")

	fake.purchase_status = "cancelled"
	var cancelled: Dictionary = await store.buy("embermarks_pouch")
	_check(not bool(cancelled.get("ok", false)), "a cancelled purchase must not report success")
	_check(str(cancelled.get("status", "")) == "cancelled", "a cancel must stay a cancel")
	_check(gs.diamonds == expected * 2, "a cancelled purchase must not change the balance")
	_check(fake.purchase_count == 3, "a cancelled sheet must still have been started once")

	fake.purchase_status = "purchased"
	var before := fake.purchase_count
	var blank: Dictionary = await store.buy("   ")
	_check(str(blank.get("status", "")) == "invalid_product",
		"an empty product id must be refused")
	_check(fake.purchase_count == before, "a refused product id must never reach the SDK")
	store.configure("", "", "", "", "")

## The demo path lives in the shop UI: the Test Store buttons must appear when
## the native authority is live, and must not exist when it is not.
func _test_native_pack_buttons_visibility() -> void:
	var store := _store()
	var gs := _game_state()
	if store == null or gs == null:
		_failures.append("GameState/StoreManager autoloads are missing")
		return
	var packed := load(SHOP_SCENE) as PackedScene
	if packed == null:
		_failures.append("the diamond shop scene must load: %s" % SHOP_SCENE)
		return
	var shop := packed.instantiate()
	get_root().add_child(shop)
	shop.open()
	_check(_native_pack_row(shop) == null,
		"an unconfigured store must not offer in-app purchase buttons")

	_use_scratch_save()
	gs.reset()
	var fake := FakeBridge.new()
	fake.response = JSON.stringify({"items": []})
	fake.transaction_response = JSON.stringify({"items": []})
	store.native_bridge = BRIDGE.new(fake)
	store.configure("", "", "", "", "", PUBLIC_KEY)
	shop.close()
	shop.open()
	var row := _native_pack_row(shop)
	_check(row != null, "a live native store must offer an in-app purchase button per pack")
	if row != null:
		# Packs stack in rows, so the contract is one button per catalogued
		# product id — not one direct child per pack.
		var buttons := _buy_buttons(row)
		_check(buttons.size() == CATALOG.all().size(),
			"every catalogued pack must get one buy button (got %d)" % buttons.size())
		var expected: Array[String] = []
		for tier in CATALOG.all():
			var product_id := CATALOG.product_id_for(tier)
			if not product_id.is_empty():
				expected.append("Buy_%s" % product_id)
		for product_id in expected:
			var found := false
			for button in buttons:
				if str(button.name) == product_id:
					found = true
					break
			_check(found, "the native pack row must offer %s" % product_id)
	# SDK-only shape: no hosted funnel, so the browser row is absent and the
	# pack buttons are the whole purchase surface. Adding a funnel turns it on.
	_check(shop.find_child("BuyOnline", true, false) == null,
		"an SDK-only build must not offer a browser checkout button")
	shop.close()
	store.configure("", "", "", "https://signup.cat/link_abc", "", PUBLIC_KEY)
	shop.open()
	_check(shop.find_child("BuyOnline", true, false) != null,
		"a funnel-configured build must offer the browser checkout button")
	shop.close()
	shop.queue_free()
	store.configure("", "", "", "", "")

func _native_pack_row(shop: Node) -> Node:
	return shop.find_child("NativePacks", true, false)

## Every BUY button under the pack row, however the row is laid out.
func _buy_buttons(node: Node) -> Array[Button]:
	var found: Array[Button] = []
	for child in node.get_children():
		if child is Button:
			found.append(child as Button)
		found.append_array(_buy_buttons(child))
	return found

## A build with no environment (Android) is configured entirely by the shipped
## RESOURCE (a plain .cfg would not be exported), a device file overrides it per
## field, identity is never taken from the shipped file, and editor/CI runs
## ignore it completely.
func _test_build_defaults_feed_the_store() -> void:
	var store := _store()
	if store == null:
		_failures.append("StoreManager autoload is missing")
		return
	var defaults := "user://test_store_defaults.tres"
	var device := "user://test_store_device.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(defaults))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(device))
	store.default_config_path = defaults
	store.config_path = device
	store.load_build_defaults = true
	var build := StoreDefaults.new()
	build.project_id = "proj_build_defaults"
	build.funnel_url = "https://signup.cat/link_ship"
	build.native_api_key = PUBLIC_KEY
	_check(ResourceSaver.save(build, defaults) == OK,
		"the shipped defaults resource must be writable for the test")
	store.native_bridge = BRIDGE.new(FakeBridge.new())
	store.load_config()
	_check(store.authority_name() == "native",
		"shipped defaults alone must configure the native authority (got %s)" % store.authority_name())
	_check(store.checkout_url().begins_with("https://signup.cat/link_ship/"),
		"the shipped funnel must build the checkout URL")

	# Identity can never come from the shipped layer: the resource has no field
	# for it, and the device keeps its own id.
	_check(not ("customer_id" in StoreDefaults.new()),
		"the shipped defaults resource must have no identity field")
	_check(store.customer_id().begins_with("ev_"),
		"the device must still mint its own customer id")

	# The device file overrides one field without touching the rest.
	var device_cfg := ConfigFile.new()
	device_cfg.set_value("store", "funnel_url", "https://signup.cat/link_qa")
	device_cfg.set_value("store", "customer_id", "ev_device_identity")
	device_cfg.save(device)
	store.load_config()
	_check(store.checkout_url().begins_with("https://signup.cat/link_qa/"),
		"a device funnel must override the shipped default")
	_check(store.customer_id() == "ev_device_identity",
		"the device identity must win over the shipped default")
	_check(store.authority_name() == "native",
		"overriding one field must keep the other shipped defaults")

	# A hostile or malformed shipped resource fails closed instead of configuring.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(device))
	var hostile := StoreDefaults.new()
	hostile.funnel_url = "https://evil.example.com/checkout"
	hostile.native_api_key = "sk_" + "A1b2C3d4E5f6G7h8"
	ResourceSaver.save(hostile, defaults)
	store.load_config()
	_check(store.checkout_url().is_empty(),
		"a hostile shipped funnel must never build a checkout URL")
	_check(store.authority_name() == "none",
		"a secret-shaped shipped key must not resolve an authority")

	# The editor/CI path never reads the resource: a valid file must not
	# configure anything unless the build gate is on.
	var valid := StoreDefaults.new()
	valid.funnel_url = "https://signup.cat/link_ship"
	valid.native_api_key = PUBLIC_KEY
	ResourceSaver.save(valid, defaults)
	store.load_build_defaults = false
	store.load_config()
	_check(store.authority_name() == "none" and store.checkout_url().is_empty(),
		"editor and CI runs must not pick up a local build defaults resource")
	store.load_build_defaults = true
	store.load_config()
	_check(store.authority_name() == "native",
		"the build gate must be the only thing keeping the shipped resource out")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(defaults))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(device))
	store.config_path = "user://store.cfg"
	store.default_config_path = StoreManager.DEFAULT_CONFIG_PATH
	store.load_build_defaults = not OS.has_feature("editor")
	store.native_bridge = BRIDGE.new()
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
	signal non_subscription_transactions(payload: String)
	signal purchase_result(payload: String)
	signal customer_info_error(code: String, message: String)

	var configured := ""
	var configured_user := ""
	var fetch_count := 0
	var transaction_fetch_count := 0
	var response := ""
	var transaction_response := ""
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

	var purchase_count := 0
	var purchase_status := "purchased"
	var purchase_error_code := ""
	var purchase_transaction_id := ""

	func purchase(product_id: String) -> void:
		purchase_count += 1
		if purchase_status == "purchased" and not purchase_transaction_id.is_empty():
			# A completed purchase appears in the next transaction read, exactly
			# as the SDK reports it.
			var items: Array = []
			var parsed: Variant = JSON.parse_string(transaction_response)
			if parsed is Dictionary and (parsed as Dictionary).get("items") is Array:
				items = (parsed as Dictionary)["items"]
			items.append({"transaction_id": purchase_transaction_id,
				"product_id": product_id, "purchased_at": purchase_count})
			transaction_response = JSON.stringify({"items": items})
		var payload := JSON.stringify({"status": purchase_status, "product_id": product_id,
			"code": purchase_error_code, "message": "fake"})
		purchase_result.emit(payload)

	func getActiveEntitlements() -> void:
		fetch_count += 1
		if error_code.is_empty():
			active_entitlements.emit(response)
		else:
			customer_info_error.emit(error_code, error_message)

	func getNonSubscriptionTransactions() -> void:
		transaction_fetch_count += 1
		if error_code.is_empty():
			non_subscription_transactions.emit(transaction_response)
		else:
			customer_info_error.emit(error_code, error_message)


## A pre-purchase plugin build: same reads, no purchase() at all.
class LegacyBridge extends RefCounted:
	signal active_entitlements(payload: String)
	signal non_subscription_transactions(payload: String)
	signal customer_info_error(code: String, message: String)

	func configure(api_key: String, app_user_id: String) -> void:
		pass

	func getActiveEntitlements() -> void:
		active_entitlements.emit("")

	func getNonSubscriptionTransactions() -> void:
		non_subscription_transactions.emit("")


## Reports a purchase outcome the parser cannot trust.
class MalformedPurchaseBridge extends RefCounted:
	signal active_entitlements(payload: String)
	signal non_subscription_transactions(payload: String)
	signal purchase_result(payload: String)
	signal customer_info_error(code: String, message: String)

	func configure(api_key: String, app_user_id: String) -> void:
		pass

	func purchase(product_id: String) -> void:
		purchase_result.emit("{not json")

	func getActiveEntitlements() -> void:
		active_entitlements.emit("")

	func getNonSubscriptionTransactions() -> void:
		non_subscription_transactions.emit("")
