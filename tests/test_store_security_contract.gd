extends SceneTree

## Headless security contract for the store path.
##
## Covers the policy rules (store_security.gd), the credential-handling guards,
## transport refusal, claim-key integrity, and a repo-wide scan that fails if a
## provider-shaped secret ever lands in a tracked source or document.
##
## Secret-shaped literals are assembled at runtime so this file cannot trip its
## own scanner.

const SECURITY := preload("res://scripts/systems/store_security.gd")
const CATALOG := preload("res://scripts/systems/web_store_catalog.gd")
const CLIENT := preload("res://scripts/systems/revenuecat_api_client.gd")
const SCRATCH_SAVE := "user://test_store_security_scratch.cfg"

var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_authority_guard()
	_test_redirect_policy()
	_test_url_policy()
	_test_id_policy()
	_test_credential_guards()
	_test_redaction()
	_test_claim_grain()
	_test_provider_row_validation()
	_test_header_injection()
	_test_expiry_semantics()
	_test_ledger_tamper_rejected_on_load()
	_test_export_carries_no_secret()
	_test_engine_redirects_disabled()
	_test_no_secret_in_repository()
	_test_no_secret_in_log_calls()
	_test_build_defaults_stay_out_of_the_repository()
	_test_build_key_sealing()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_SAVE))
	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		print("STORE SECURITY CONTRACT FAILED (%d)" % _failures.size())
		quit(1)
		return
	print("STORE SECURITY CONTRACT PASSED")
	quit(0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

func _fake_secret() -> String:
	return "sk_" + "A1b2C3d4E5f6G7h8".repeat(2)

func _game_state() -> GameState:
	return get_root().get_node_or_null("GameState") as GameState

func _test_authority_guard() -> void:
	_check(SECURITY.direct_authority_allowed(true, false),
		"the editor may use a local secret")
	_check(SECURITY.direct_authority_allowed(false, true),
		"a debug export may use a local secret")
	_check(not SECURITY.direct_authority_allowed(false, false),
		"a release export must NEVER resolve a direct secret authority")

func _test_redirect_policy() -> void:
	for code in [300, 301, 302, 303, 307, 308, 399]:
		_check(SECURITY.is_redirect(code), "HTTP %d must be treated as a redirect" % code)
	for code in [200, 201, 204, 400, 401, 500]:
		_check(not SECURITY.is_redirect(code), "HTTP %d must not be treated as a redirect" % code)

func _test_url_policy() -> void:
	var funnel := SECURITY.ALLOWED_FUNNEL_HOSTS
	_check(SECURITY.validate_url("https://signup.cat/abc123", funnel).is_empty(),
		"an allow-listed HTTPS funnel must validate")
	_check(SECURITY.validate_url("https://SIGNUP.CAT/abc123", funnel).is_empty(),
		"the host allow-list must be case-insensitive")
	_check(SECURITY.validate_url("http://signup.cat/abc123", funnel) == "insecure_scheme",
		"plain HTTP must be refused")
	_check(SECURITY.validate_url("https://evil.example/abc123", funnel) == "host_not_allowed",
		"an unknown funnel host must be refused")
	_check(SECURITY.validate_url("https://pay.rev.cat/abc123", funnel).is_empty(),
		"a RevenueCat purchase link host must validate")
	_check(SECURITY.validate_url("https://signup.cat/abc123", funnel).is_empty(),
		"a RevenueCat funnel host must validate")
	_check(SECURITY.validate_url("https://pay.rev.cat.evil.com/abc123", funnel) == "host_not_allowed",
		"a lookalike host must not pass the allow-list")
	_check(SECURITY.validate_url("https://evil.com/pay.rev.cat", funnel) == "host_not_allowed",
		"the allow-list must match the host, not the path")
	_check(SECURITY.validate_url("https://user:pw@signup.cat/x", funnel) == "url_userinfo",
		"credentials in the URL must be refused")
	_check(SECURITY.validate_url("https://signup.cat:8443/x", funnel) == "non_default_port",
		"a non-default port must be refused")
	_check(SECURITY.validate_url("https://signup.cat/x#frag", funnel) == "url_fragment",
		"a fragment must be refused")
	_check(SECURITY.validate_url("https://signup.cat/x?y=1", funnel) == "url_query",
		"a query on the funnel base must be refused")
	_check(SECURITY.validate_url("https://signup.cat/x\nHost: evil", funnel) == "url_control_chars",
		"a control character must be refused")
	_check(SECURITY.validate_url("signup.cat/x", funnel) == "insecure_scheme",
		"a scheme-relative URL must be refused")
	_check(SECURITY.validate_url("", funnel) == "empty_url", "an empty URL must be refused")
	_check(SECURITY.validate_backend_url("https://store.example.com").is_empty(),
		"an HTTPS backend must validate")
	_check(SECURITY.validate_backend_url("https://localhost:443").is_empty(),
		"a single-label backend host on the default port must validate")
	_check(SECURITY.validate_backend_url("http://store.example.com") == "insecure_scheme",
		"an insecure backend must be refused")
	_check(SECURITY.validate_backend_url("https://10.0.0.5").is_empty(),
		"a literal backend address must validate")

func _test_id_policy() -> void:
	_check(SECURITY.validate_project_id("proj1ab2c3d4").is_empty(), "a real project id must validate")
	_check(SECURITY.validate_project_id("proj_test").is_empty(), "a suffixed project id must validate")
	_check(SECURITY.validate_project_id("") == "empty_project_id", "an empty project id is invalid")
	_check(SECURITY.validate_project_id("abc123") == "project_id_prefix",
		"a project id must carry the proj prefix")
	_check(SECURITY.validate_project_id("proj abc") == "project_id_charset",
		"a project id must not contain spaces")
	_check(SECURITY.validate_project_id("proj_%2F") == "project_id_charset",
		"a project id must not contain path escapes")
	_check(SECURITY.validate_customer_id("ev_0a1b2c3d").is_empty(), "a device id must validate")
	_check(SECURITY.validate_customer_id("") == "empty_customer_id", "an empty customer id is invalid")
	_check(SECURITY.validate_customer_id("ev/../other") == "customer_id_charset",
		"a path separator in a customer id must be refused")
	_check(SECURITY.validate_customer_id("ev\nfoo") == "customer_id_charset",
		"a control character in a customer id must be refused")
	_check(SECURITY.validate_customer_id("é") == "customer_id_charset",
		"a non-ASCII customer id must be refused")

func _test_credential_guards() -> void:
	var secret := _fake_secret()
	_check(SECURITY.is_plausible_secret(secret), "a provider-shaped secret must be plausible")
	_check(not SECURITY.is_plausible_secret("sk_short"), "a short secret must be refused")
	_check(not SECURITY.is_plausible_secret("goog_" + "A1b2C3d4E5f6G7h8"),
		"an SDK key must never be accepted as a secret")
	_check(not SECURITY.is_plausible_secret("sk_" + "A1b2C3d4\r\nInjected: yes"),
		"a secret carrying a CRLF must be refused")
	_check(SECURITY.is_safe_header_value("token_value-1"), "a plain token must be header safe")
	_check(not SECURITY.is_safe_header_value("a b"), "a token with a space must be refused")
	_check(not SECURITY.is_safe_header_value(""), "an empty token must be refused")
	_check(not SECURITY.is_safe_header_value("token\r\nX: 1"),
		"a header-breaking token must be refused")

func _test_redaction() -> void:
	var secret := _fake_secret()
	var shown := SECURITY.redact(secret)
	_check(not shown.contains(secret), "redaction must never reveal the whole credential")
	_check(shown.begins_with("sk_"), "redaction may keep the key marker")
	_check(shown.ends_with(secret.substr(secret.length() - 4)),
		"redaction may keep only the trailing four characters")
	_check(not SECURITY.redact(secret).contains(secret.substr(0, 12)),
		"redaction must not reveal a leading run of the credential")

func _test_claim_grain() -> void:
	var pack: Dictionary = CATALOG.tier_for_entitlement("embermarks_cache")
	_check(str(pack.get("claim_grain", "")) == CATALOG.GRAIN_TRANSACTION,
		"a repeatable pack must declare the transaction claim grain")
	_check(CATALOG.claim_record_id(pack, -1).is_empty(),
		"a consumable must have no entitlement claim key at all")
	var key_a := CATALOG.record_id_for_transaction("embermarks_cache", "txn_a")
	var key_b := CATALOG.record_id_for_transaction("embermarks_cache", "txn_b")
	_check(key_a != key_b, "each transaction must key its own grant")
	_check(key_a == CATALOG.record_id_for_transaction("embermarks_cache", "txn_a"),
		"a transaction key must be stable across reads")
	var one_time := {"entitlement_id": "one_shot", "claim_grain": CATALOG.GRAIN_ONE_TIME}
	_check(CATALOG.claim_record_id(one_time, -1)
			== CATALOG.claim_record_id(one_time, 4_000_000_000_000),
		"a one-time tier must keep one claim key across different expiries")
	var expiring := {"entitlement_id": "sub_tier", "claim_grain": CATALOG.GRAIN_EXPIRING}
	_check(CATALOG.claim_record_id(expiring, 1) != CATALOG.claim_record_id(expiring, 2),
		"an expiring tier must key on the expiry so a renewal grants once per period")
	var errors: Array[String] = CATALOG.validate()
	_check(errors.is_empty(), "the catalog must validate: %s" % "; ".join(errors))

func _test_provider_row_validation() -> void:
	var tier: Dictionary = CATALOG.tier_for_product("embermarks_pouch")
	var row := _canonical_transaction_row(tier, "txn_row")
	_check(SECURITY.validate_provider_transaction_row(row).is_empty(),
		"a canonical transaction row must validate")
	var wrong_amount := row.duplicate(true)
	wrong_amount["price"] = int(tier.get("diamonds", 0)) + 10_000
	_check(SECURITY.validate_provider_transaction_row(wrong_amount) == "amount_mismatch",
		"an inflated amount must be rejected")
	var forged_id := row.duplicate(true)
	forged_id["provider_record_id"] = "revenuecat:embermarks_pouch:txn:forged"
	_check(SECURITY.validate_provider_transaction_row(forged_id) == "record_id_mismatch",
		"a fabricated transaction record id must be rejected")
	var missing_txn := row.duplicate(true)
	missing_txn["provider_transaction"] = ""
	_check(SECURITY.validate_provider_transaction_row(missing_txn) == "missing_transaction",
		"a transaction row without a transaction id must be rejected")
	var wrong_provider := row.duplicate(true)
	wrong_provider["provider"] = "other_provider"
	_check(SECURITY.validate_provider_transaction_row(wrong_provider) == "unknown_provider",
		"an unknown provider must be rejected")
	var uncatalogued := row.duplicate(true)
	uncatalogued["provider_product"] = "unlisted_pack"
	_check(SECURITY.validate_provider_transaction_row(uncatalogued) == "uncatalogued_product",
		"an uncatalogued product must be rejected")
	var wrong_currency := row.duplicate(true)
	wrong_currency["currency"] = "gold"
	_check(SECURITY.validate_provider_transaction_row(wrong_currency) == "currency_mismatch",
		"a non-diamond payout must be rejected")
	# The same pack cannot be claimed through its (permanently active) entitlement.
	var entitlement_row := {
		"id": str(tier.get("id", "")), "kind": "provider_embermarks",
		"price": int(tier.get("diamonds", 0)), "currency": "diamonds",
		"provider": "revenuecat",
		"provider_record_id": "revenuecat:embermarks_pouch:one_time",
		"provider_entitlement": "embermarks_pouch", "provider_expires_at": -1,
	}
	_check(SECURITY.validate_provider_row(entitlement_row) == "not_an_entitlement_pack",
		"an entitlement-keyed row for a consumable must be refused")

func _test_header_injection() -> void:
	var headers := PackedStringArray(["Accept: application/json"])
	var injected := CLIENT.with_bearer(headers, "token\r\nX-Injected: 1")
	_check(injected.size() == 1, "a header-breaking credential must not be sent")
	var valid := CLIENT.with_bearer(headers, "token_value_1")
	_check(valid.size() == 2, "a safe credential must be attached")

func _test_expiry_semantics() -> void:
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var body := JSON.stringify({"items": [
		{"entitlement_id": "zero_expiry", "expires_at": 0},
		{"entitlement_id": "negative_expiry", "expires_at": -5},
		{"entitlement_id": "past_expiry", "expires_at": now_ms - 1},
		{"entitlement_id": "lifetime", "expires_at": null},
	]})
	var parsed: Dictionary = CLIENT.parse_active_entitlements(200, body)
	var active: Array = parsed.get("active", [])
	_check(active.size() == 1, "only the null-expiry entitlement may survive (got %d)" % active.size())
	_check(str((active[0] as Dictionary).get("entitlement_id", "")) == "lifetime",
		"a numeric expiry must never be promoted to a lifetime grant")

func _test_ledger_tamper_rejected_on_load() -> void:
	var gs := _game_state()
	if gs == null:
		_failures.append("GameState autoload is missing")
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_SAVE))
	gs.save_path = SCRATCH_SAVE
	var tier: Dictionary = CATALOG.tier_for_entitlement("embermarks_cache")
	var forged := _canonical_row(tier, -1)
	forged["provider_record_id"] = "revenuecat:embermarks_cache:forged"
	forged["price"] = 999_999
	forged["currency"] = "diamonds"
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "schema_version", 5)
	cfg.set_value("progress", "purchase_ledger", [forged])
	_check(cfg.save(SCRATCH_SAVE) == OK, "the forged save fixture must write")
	_check(gs.load_game(), "the forged save fixture must load")
	_check(not gs.is_provider_claim_recorded("revenuecat:embermarks_cache:forged"),
		"a forged provider claim must not be trusted as recorded")
	var ledger: Array[Dictionary] = gs.get_purchase_ledger()
	for entry in ledger:
		if str(entry.get("id", "")) == str(tier.get("id", "")):
			_check(not entry.has("provider_record_id"),
				"an inconsistent provider row must lose its provider fields on load")
	# A real purchase of the same tier must still be granted after the forgery.
	var store := get_root().get_node_or_null("StoreManager") as StoreManager
	if store == null:
		_failures.append("StoreManager autoload is missing")
		return
	var claimed: Dictionary = store.claim_transactions([
		{"transaction_id": "txn_after_forgery", "product_id": "embermarks_cache"}])
	_check(int(claimed.get("granted", 0)) == 1,
		"a forged row must not block a legitimate purchase")

func _test_export_carries_no_secret() -> void:
	var gs := _game_state()
	var store := get_root().get_node_or_null("StoreManager") as StoreManager
	if gs == null or store == null:
		_failures.append("GameState/StoreManager autoloads are missing")
		return
	var secret := _fake_secret()
	store.configure("proj_test", secret)
	_check(store.authority_name() == "direct_editor_debug",
		"a plausible secret in an editor run must select the direct authority")
	var exported := JSON.stringify(gs.build_data_export())
	_check(not exported.contains(secret), "the support export must never contain the credential")
	_check(SECURITY.find_secret_leaks(exported).is_empty(),
		"the support export must be free of secret-shaped values")
	store.configure("", "", "", "", "")

func _test_engine_redirects_disabled() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/autoload/store_manager.gd")
	_check(source.contains("max_redirects = 0"),
		"the refresh request must disable redirect following")
	_check(source.contains("body_size_limit"),
		"the refresh request must cap the response body at the engine level")

func _test_no_secret_in_repository() -> void:
	var leaks: Array[String] = []
	_scan_directory("res://", leaks)
	_check(leaks.is_empty(),
		"no tracked source or document may contain a secret-shaped value: %s" % ", ".join(leaks))

## The shipped defaults may carry a sandbox funnel URL, which must never be
## committable, and the loader must read the same file the ignore rule covers.
func _test_build_defaults_stay_out_of_the_repository() -> void:
	var ignore := FileAccess.get_file_as_string("res://.gitignore")
	_check(ignore.contains("store_defaults.tres"),
		"the build defaults resource must be gitignored (store_defaults.tres)")
	var source := FileAccess.get_file_as_string("res://scripts/autoload/store_manager.gd")
	_check(source.contains("res://store_defaults.tres"),
		"the shipped defaults path must match the gitignored resource name")
	_check(source.contains("ResourceLoader.exists"),
		"the shipped defaults must load as a resource (a .cfg would not be exported)")
	var defaults := StoreDefaults.new()
	_check(not ("customer_id" in defaults),
		"the shipped defaults resource must have no identity field")

## The shipped resource seals the public SDK key: a literal copy-paste of the
## resource must not hand out a working key, a round trip must return exactly
## the sealed value, and anything tampered with or malformed must fail closed.
## Sealing is obfuscation (the passphrase ships in the client), so this test
## verifies the mechanics, not confidentiality.
func _test_build_key_sealing() -> void:
	var key := "test_" + "A1b2C3d4E5f6G7h8"
	var sealed := SECURITY.seal(key)
	_check(SECURITY.is_sealed(sealed), "a sealed value must carry the scheme marker")
	_check(not sealed.contains(key), "a sealed value must not contain the plaintext")
	_check(SECURITY.unseal(sealed) == key, "a sealed key must round-trip exactly")
	_check(SECURITY.seal(key) != SECURITY.seal(key),
		"two seals of one key must differ (random salt and IV)")
	_check(SECURITY.unseal(key) == "", "a plaintext value must not unseal")
	_check(SECURITY.unseal("") == "" and SECURITY.unseal("rcseal1:") == "",
		"an empty or marker-only value must fail closed")
	_check(SECURITY.unseal("rcseal1:!!!!") == "",
		"an unreadable blob must fail closed")
	var truncated := sealed.substr(0, sealed.length() - 8)
	_check(SECURITY.unseal(truncated) != key,
		"a truncated blob must never yield the key")
	var flipped := sealed.substr(0, SECURITY.SEAL_MARKER.length() + 8) + "AAAA" \
		+ sealed.substr(SECURITY.SEAL_MARKER.length() + 12)
	_check(SECURITY.unseal(flipped) != key,
		"a tampered blob must never yield the key")

	# The resource resolves a sealed key exactly like a plaintext one and fails
	# closed when the blob cannot be recovered.
	var defaults := StoreDefaults.new()
	defaults.native_api_key = key
	_check(defaults.resolved_native_api_key() == key,
		"a plaintext build resource must still resolve (dev and test fixtures)")
	defaults.native_api_key = ""
	defaults.native_api_key_sealed = sealed
	_check(defaults.resolved_native_api_key() == key,
		"a sealed build resource must resolve through the seal")
	_check(defaults.has_native_key(), "a resolved key must report as present")
	defaults.native_api_key_sealed = "rcseal1:AAAA"
	_check(defaults.resolved_native_api_key() == "",
		"an unrecoverable sealed key must fail closed")

	# Wiring: the writer seals, the store reads the resolved value, and plaintext
	# shipping is an explicit opt-out rather than the default.
	var writer := FileAccess.get_file_as_string("res://tools/write_store_defaults.gd")
	_check(writer.contains("SECURITY.seal("),
		"the defaults writer must seal the shipped public key")
	_check(writer.contains("--no-seal"),
		"plaintext shipping must stay an explicit opt-out")
	_check(writer.contains("--from-resource"),
		"the writer must be able to rotate a key out of an existing resource")
	var manager := FileAccess.get_file_as_string("res://scripts/autoload/store_manager.gd")
	_check(manager.contains("resolved_native_api_key()"),
		"the store must read the resolved (possibly sealed) shipped key")

func _test_no_secret_in_log_calls() -> void:	for path in ["res://scripts/autoload/store_manager.gd",
			"res://scripts/systems/revenuecat_api_client.gd",
			"res://scripts/systems/store_security.gd"]:
		var source := FileAccess.get_file_as_string(path)
		for line in source.split("\n"):
			var text := str(line)
			if not (text.contains("push_error") or text.contains("push_warning") \
					or text.contains("print(")):
				continue
			for forbidden in ["_direct_secret", "_account.access_token", "Bearer %s"]:
				_check(not text.contains(forbidden),
					"%s logs a credential expression: %s" % [path.get_file(), forbidden])

func _scan_directory(path: String, leaks: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		var extension := file_name.get_extension().to_lower()
		if extension not in ["gd", "md", "cfg", "tres", "json", "tscn", "gdshader"]:
			continue
		var full_path := "%s%s" % [path, file_name]
		var text := FileAccess.get_file_as_string(full_path)
		for found in SECURITY.find_secret_leaks(text):
			leaks.append("%s (%s)" % [full_path, found])
	for sub in dir.get_directories():
		if str(sub).begins_with(".") or str(sub) == "addons":
			continue
		_scan_directory("%s%s/" % [path, sub], leaks)

func _canonical_transaction_row(tier: Dictionary, transaction_id: String) -> Dictionary:
	var product_id := str(tier.get("product_id", tier.get("entitlement_id", "")))
	return {
		"id": str(tier.get("id", "")),
		"kind": "provider_embermarks",
		"price": int(tier.get("diamonds", 0)),
		"currency": "diamonds",
		"provider": "revenuecat",
		"provider_record_id": CATALOG.record_id_for_transaction(product_id, transaction_id),
		"provider_transaction": transaction_id,
		"provider_product": product_id,
	}

func _canonical_row(tier: Dictionary, expires_at_ms: int) -> Dictionary:
	var entitlement_id := str(tier.get("entitlement_id", ""))
	return {
		"id": str(tier.get("id", "")),
		"kind": "provider_embermarks",
		"price": int(tier.get("diamonds", 0)),
		"currency": "diamonds",
		"provider": "revenuecat",
		"provider_record_id": CATALOG.claim_record_id(tier, expires_at_ms),
		"provider_entitlement": entitlement_id,
		"provider_expires_at": expires_at_ms,
	}
