extends SceneTree

## Headless contract suite for the RevenueCat web-purchase path.
##
## No network is touched: every branch is driven through the pure API client,
## the catalog, and injected grant rows. A failure here is a real contract break
## rather than a flaky connection.
##
## This suite points GameState at a scratch save file BEFORE it mutates anything,
## so running it can never overwrite a developer's real save.

const CLIENT := preload("res://scripts/systems/revenuecat_api_client.gd")
const CATALOG := preload("res://scripts/systems/web_store_catalog.gd")
const SCRATCH_SAVE := "user://test_revenuecat_scratch.cfg"

var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_request_building()
	_test_bearer_scoping()
	_test_response_parsing()
	_test_error_mapping()
	_test_catalog()
	await _test_store_manager_offline_no_op()
	_test_store_manager_authority_selection()
	_test_claim_idempotency()
	_test_save_round_trip_preserves_claims()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_SAVE))
	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		print("REVENUECAT ENTITLEMENT TESTS FAILED (%d)" % _failures.size())
		quit(1)
		return
	print("REVENUECAT ENTITLEMENT TESTS PASSED")
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

func _test_request_building() -> void:
	var built: Dictionary = CLIENT.build_active_entitlements_request("proj_abc", "ev_123")
	_check(bool(built.get("ok", false)), "valid ids should build a request")
	var url := str(built.get("url", ""))
	_check(url.begins_with("https://api.revenuecat.com/v2/"),
		"the request must target the v2 HTTPS base")
	_check(url.contains("/projects/proj_abc/customers/ev_123/active_entitlements"),
		"the request must target the customer's active entitlements")
	_check(url.ends_with("limit=%d" % CLIENT.MAX_ENTITLEMENTS), "the page size must be capped")
	var bad_project: Dictionary = CLIENT.build_active_entitlements_request("", "ev_123")
	_check(str(bad_project.get("error", "")) == "invalid_project_id",
		"an empty project id must be rejected")
	var bad_customer: Dictionary = CLIENT.build_active_entitlements_request("proj_abc", "")
	_check(str(bad_customer.get("error", "")) == "invalid_customer_id",
		"an empty customer id must be rejected")
	var spaced: Dictionary = CLIENT.build_active_entitlements_request("proj abc", "ev 123")
	_check(not str(spaced.get("url", "")).contains(" "),
		"ids must be URL encoded before they reach the request")

func _test_bearer_scoping() -> void:
	var base := PackedStringArray(["Accept: application/json"])
	var scoped := CLIENT.with_bearer(base, "sk_test_value")
	_check(scoped.size() == 2, "a bearer header must be appended")
	_check(scoped[scoped.size() - 1] == "Authorization: Bearer sk_test_value",
		"the appended header must carry the supplied credential")
	_check(base.size() == 1, "the source header set must not be mutated")
	var blank := CLIENT.with_bearer(base, "   ")
	_check(blank.size() == 1, "a blank credential must not add an auth header")

func _test_response_parsing() -> void:
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var body := JSON.stringify({
		"object": "list",
		"items": [
			{"object": "customer.active_entitlement",
				"entitlement_id": "embermarks_cache", "expires_at": null},
			{"object": "customer.active_entitlement",
				"entitlement_id": "embermarks_pouch", "expires_at": now_ms + 86_400_000},
			{"object": "customer.active_entitlement",
				"entitlement_id": "lapsed_pack", "expires_at": now_ms - 1_000},
			{"object": "customer.active_entitlement", "entitlement_id": "", "expires_at": null},
			"not-an-object",
		],
	})
	var parsed: Dictionary = CLIENT.parse_active_entitlements(200, body)
	_check(bool(parsed.get("ok", false)), "a 200 list body must parse")
	var active: Array = parsed.get("active", [])
	_check(active.size() == 2, "only usable, unexpired rows must survive (got %d)" % active.size())
	var lifetime := _find_entitlement(active, "embermarks_cache")
	_check(not lifetime.is_empty(), "a null expiry must survive as a lifetime entitlement")
	_check(int(lifetime.get("expires_at_ms", 0)) == CLIENT.LIFETIME_EXPIRY_MS,
		"a lifetime entitlement must use the lifetime sentinel")
	var expiring := _find_entitlement(active, "embermarks_pouch")
	_check(int(expiring.get("expires_at_ms", 0)) == now_ms + 86_400_000,
		"a future expiry must be preserved exactly")
	_check(_find_entitlement(active, "lapsed_pack").is_empty(),
		"an already-expired entitlement must never be returned")

	var many: Array = []
	for index in 150:
		many.append({"entitlement_id": "pack_%d" % index, "expires_at": null})
	var capped: Dictionary = CLIENT.parse_active_entitlements(200, JSON.stringify({"items": many}))
	_check((capped.get("active", []) as Array).size() == CLIENT.MAX_ENTITLEMENTS,
		"the row count must be hard-capped")

	var malformed: Dictionary = CLIENT.parse_active_entitlements(200, "{not json")
	_check(str(malformed.get("error", "")) == "malformed_response",
		"invalid JSON must not parse into entitlements")
	var wrong_shape: Dictionary = CLIENT.parse_active_entitlements(200, JSON.stringify({"object": "list"}))
	_check(str(wrong_shape.get("error", "")) == "malformed_response",
		"a body without an items list must not parse")
	var oversized: Dictionary = CLIENT.parse_active_entitlements(200,
		"x".repeat(CLIENT.MAX_BODY_BYTES + 1))
	_check(str(oversized.get("error", "")) == "response_too_large",
		"an oversized body must be refused")

func _test_error_mapping() -> void:
	var cases := {401: "unauthorized", 403: "unauthorized", 404: "not_found",
		429: "rate_limited", 500: "provider_error", 400: "http_error"}
	for code in cases:
		var result: Dictionary = CLIENT.parse_active_entitlements(int(code), "")
		_check(str(result.get("error", "")) == str(cases[code]),
			"HTTP %d must map to %s (got %s)" % [int(code), str(cases[code]),
				str(result.get("error", ""))])
		_check(not bool(result.get("ok", false)), "a non-200 response must never be ok")

func _test_catalog() -> void:
	var errors: Array[String] = CATALOG.validate()
	_check(errors.is_empty(), "the web store catalog must validate: %s" % "; ".join(errors))
	_check(not CATALOG.tier_for_entitlement("embermarks_cache").is_empty(),
		"a catalogued entitlement must resolve to a tier")
	_check(CATALOG.tier_for_entitlement("unlisted_pack").is_empty(),
		"an unknown entitlement must not resolve")
	_check(CATALOG.tier_for_entitlement("").is_empty(),
		"an empty entitlement must not resolve")
	_check(CATALOG.record_id_for("embermarks_cache", -1) \
			== CATALOG.record_id_for("embermarks_cache", -1),
		"a record id must be stable for the same entitlement and expiry")
	_check(CATALOG.record_id_for("embermarks_cache", -1) \
			== CATALOG.record_id_for("embermarks_cache", 4_000_000_000_000),
		"a one-time tier must be keyed by entitlement alone, not by expiry")
	_check(CATALOG.record_id_for("embermarks_cache", -1) \
			!= CATALOG.record_id_for("embermarks_pouch", -1),
		"distinct entitlements must never share a record id")

func _test_store_manager_offline_no_op() -> void:
	var store := _store()
	if store == null:
		_failures.append("StoreManager autoload is missing")
		return
	store.configure("", "", "", "", "")
	_check(not store.is_available(), "an unconfigured store must be unavailable")
	_check(store.authority_name() == "none", "an unconfigured store must have no authority")
	_check(store.checkout_url().is_empty(), "an unconfigured store must not build a checkout URL")
	_check(not store.customer_id().is_empty(),
		"a device identity must exist before any purchase is attempted")
	var result: Dictionary = await store.refresh_and_claim()
	_check(not bool(result.get("ok", false)), "an unconfigured refresh must not report success")
	_check(str(result.get("status", "")) == "unconfigured",
		"an unconfigured refresh must report unconfigured")
	_check(int(result.get("granted", 0)) == 0, "an unconfigured refresh must grant nothing")
	_check(not store.last_result().is_empty(), "the last result must be observable by the UI")

func _test_store_manager_authority_selection() -> void:
	var store := _store()
	if store == null:
		_failures.append("StoreManager autoload is missing")
		return
	store.configure("proj_test", "", "https://store.example.com",
		"https://signup.cat/link_abc", "token_test")
	_check(store.authority_name() == "backend",
		"a backend URL plus a token must select the backend authority")
	_check(store.is_available(), "a backend-configured store must be available")
	var url := store.checkout_url()
	_check(url.begins_with("https://signup.cat/link_abc/"),
		"checkout must stay on the configured hosted funnel")
	_check(url.ends_with(store.customer_id().uri_encode()),
		"checkout must carry this device's App User ID")
	store.configure("proj_test", "", "https://store.example.com",
		"http://insecure.example", "token_test")
	_check(store.checkout_url().is_empty(), "a non-HTTPS funnel must not produce a checkout URL")
	store.configure("proj_test", "sk_" + "A1b2C3d4E5f6G7h8")
	_check(store.authority_name() == "direct_editor_debug",
		"a local secret must only ever select the editor/debug authority")
	store.configure("", "", "", "", "")

func _test_claim_idempotency() -> void:
	var gs := _game_state()
	var store := _store()
	if gs == null or store == null:
		_failures.append("GameState/StoreManager autoloads are missing")
		return
	_use_scratch_save()
	gs.reset()
	var tier: Dictionary = CATALOG.tier_for_product("embermarks_cache")
	var expected := int(tier.get("diamonds", 0))
	var first: Dictionary = store.claim_transactions([
		{"transaction_id": "txn_alpha", "product_id": "embermarks_cache"}])
	_check(int(first.get("granted", 0)) == 1, "a confirmed purchase must grant one pack")
	_check(int(first.get("diamonds", 0)) == expected, "the grant must match the catalogued tier")
	_check(gs.diamonds == expected, "ember marks must be delivered exactly once")
	var repeat: Dictionary = store.claim_transactions([
		{"transaction_id": "txn_alpha", "product_id": "embermarks_cache"}])
	_check(int(repeat.get("granted", 0)) == 0,
		"re-reading one transaction must never grant a second pack")
	_check(gs.diamonds == expected, "a repeated read must not inflate the balance")
	_check(gs.is_provider_claim_recorded(
		CATALOG.record_id_for_transaction("embermarks_cache", "txn_alpha")),
		"the ledger must record the transaction claim id")
	var second_purchase: Dictionary = store.claim_transactions([
		{"transaction_id": "txn_beta", "product_id": "embermarks_cache"}])
	_check(int(second_purchase.get("granted", 0)) == 1,
		"a second purchase of the same consumable must grant again")
	_check(gs.diamonds == expected * 2, "each purchase must deliver its own pack")
	var entitlement_only: Dictionary = store.claim([
		{"entitlement_id": "embermarks_cache", "expires_at_ms": -1}])
	_check(int(entitlement_only.get("granted", 0)) == 0,
		"a consumable's active entitlement must never be claimed as a purchase")
	_check(gs.diamonds == expected * 2, "an entitlement read must not change the balance")
	var unknown: Dictionary = store.claim_transactions([
		{"transaction_id": "txn_gamma", "product_id": "unlisted_pack"}])
	_check(int(unknown.get("granted", 0)) == 0 and int(unknown.get("skipped", 0)) == 1,
		"an uncatalogued product must be skipped, never guessed at")

func _test_save_round_trip_preserves_claims() -> void:
	var gs := _game_state()
	var store := _store()
	if gs == null or store == null:
		_failures.append("GameState/StoreManager autoloads are missing")
		return
	_use_scratch_save()
	gs.reset()
	var tier: Dictionary = CATALOG.tier_for_product("embermarks_pouch")
	var expected := int(tier.get("diamonds", 0))
	store.claim_transactions([
		{"transaction_id": "txn_persist", "product_id": "embermarks_pouch"}])
	_check(gs.flush_save(), "a claimed pack must persist")
	# Wipe memory, reload from disk: idempotency must survive the round trip.
	gs.reset()
	_check(gs.load_game(), "the claimed save must reload")
	_check(gs.diamonds == expected, "the reload must restore the delivered ember marks")
	_check(gs.is_provider_claim_recorded(
		CATALOG.record_id_for_transaction("embermarks_pouch", "txn_persist")),
		"transaction record ids must survive a save/load round trip")
	var repeat: Dictionary = store.claim_transactions([
		{"transaction_id": "txn_persist", "product_id": "embermarks_pouch"}])
	_check(int(repeat.get("granted", 0)) == 0,
		"a reload must never re-open an already-claimed purchase")
	_check(gs.diamonds == expected, "a reload must not inflate the balance")

func _find_entitlement(rows: Array, entitlement_id: String) -> Dictionary:
	for row in rows:
		if row is Dictionary and str((row as Dictionary).get("entitlement_id", "")) == entitlement_id:
			return row as Dictionary
	return {}
