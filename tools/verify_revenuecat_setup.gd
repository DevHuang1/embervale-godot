extends SceneTree

## Live RevenueCat setup check — run after configuring the dashboard.
##
##   EMBERVALE_REVENUECAT_PROJECT_ID=projXXXXXXXX \
##   EMBERVALE_REVENUECAT_SECRET=sk_XXXXXXXX \
##   EMBERVALE_STORE_CUSTOMER_ID=ev_XXXXXXXX \
##   godot --headless --path . --script tools/verify_revenuecat_setup.gd
##
## It uses the same request builder, response parser and catalog as the game, so
## a pass here means the app would resolve the same entitlement. Nothing is
## written: the check is read-only, so it can be run before a demo safely.
##
## The secret is only ever printed redacted, and it is read from the environment
## so it never has to exist in a file or in this repository.

const CLIENT := preload("res://scripts/systems/revenuecat_api_client.gd")
const CATALOG := preload("res://scripts/systems/web_store_catalog.gd")
const SECURITY := preload("res://scripts/systems/store_security.gd")
const SAVE_SERVICE := preload("res://scripts/systems/save_service.gd")

const SAVE_PATH := "user://embervale_save.cfg"

var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var project_id := OS.get_environment("EMBERVALE_REVENUECAT_PROJECT_ID").strip_edges()
	var secret := OS.get_environment("EMBERVALE_REVENUECAT_SECRET").strip_edges()
	var customer_id := OS.get_environment("EMBERVALE_STORE_CUSTOMER_ID").strip_edges()
	var funnel_url := OS.get_environment("EMBERVALE_STORE_FUNNEL_URL").strip_edges()

	print("=== Embervale x RevenueCat setup check ===")
	# With no environment at all, validate the shipped device defaults instead:
	# an APK gets its non-secret config from res://store_defaults.cfg, and that
	# file can be checked offline before a build (see the dashboard runbook).
	if project_id.is_empty() and secret.is_empty() and customer_id.is_empty():
		if _check_shipped_defaults():
			return
	_check_inputs(project_id, secret, customer_id, funnel_url)
	if not _failures.is_empty():
		_report()
		return
	print("  project  : %s" % project_id)
	print("  customer : %s" % customer_id)
	print("  secret   : %s (redacted)" % SECURITY.redact(secret))
	print("  catalog  : %s" % ", ".join(_catalog_ids()))

	var active := await _fetch_active(project_id, customer_id, secret)
	if active.is_empty() and _failures.is_empty():
		print("  0 active entitlements. The customer exists but owns nothing yet — " +
			"complete a sandbox purchase or grant a promotional entitlement.")
	_report()

## Offline check of the resource an exported Android build actually reads.
## Shapes only: no secret is needed, nothing is written, and network is not
## touched. Returns false when the file does not exist, so the environment
## check runs.
func _check_shipped_defaults() -> bool:
	const PATH := "res://store_defaults.tres"
	if not ResourceLoader.exists(PATH):
		return false
	var defaults := load(PATH) as StoreDefaults
	if defaults == null:
		_failures.append("Shipped defaults are not a StoreDefaults resource.")
		_report()
		return true
	print("  device defaults: %s" % PATH)
	var project_id := defaults.project_id.strip_edges()
	var funnel_url := defaults.funnel_url.strip_edges()
	var native_key := defaults.native_api_key.strip_edges()
	print("  project  : %s" % ("set" if not project_id.is_empty() else "absent"))
	print("  checkout : %s" % ("set" if not funnel_url.is_empty() else "absent"))
	print("  identity : device-minted (never shipped)")
	if not project_id.is_empty():
		var problem := SECURITY.validate_project_id(project_id)
		if not problem.is_empty():
			_failures.append("Shipped project_id is rejected (%s)." % problem)
	# SDK-only builds are valid: the native reader needs no funnel and no
	# project id. A funnel is optional and only checked when present.
	if not funnel_url.is_empty():
		var problem := SECURITY.validate_url(funnel_url, SECURITY.ALLOWED_FUNNEL_HOSTS)
		if not problem.is_empty():
			_failures.append("Shipped funnel_url is rejected (%s)." % problem)
	if not native_key.is_empty():
		var problem := SECURITY.validate_public_sdk_key(native_key)
		if not problem.is_empty():
			_failures.append("Shipped native_api_key is rejected (%s)." % problem)
	if funnel_url.is_empty() and native_key.is_empty():
		_failures.append("Shipped defaults carry neither a native_api_key nor a funnel_url; "
			+ "the build cannot reach RevenueCat.")
	if "customer_id" in defaults:
		_failures.append("Shipped defaults must not carry a customer_id; the device mints its own.")
	for leak in SECURITY.find_secret_leaks(FileAccess.get_file_as_string(PATH)):
		_failures.append("Shipped defaults contain a secret-shaped value (%s)." % leak)
	if _failures.is_empty():
		print("SHIPPED DEFAULTS VALID")
		quit(0)
		return true
	for failure in _failures:
		print("FAIL: %s" % failure)
	print("SHIPPED DEFAULTS INVALID (%d)" % _failures.size())
	quit(1)
	return true

func _check_inputs(project_id: String, secret: String, customer_id: String,
		funnel_url: String) -> void:
	var problem := SECURITY.validate_project_id(project_id)
	if not problem.is_empty():
		_failures.append("%s is missing or malformed (%s)." % ["EMBERVALE_REVENUECAT_PROJECT_ID", problem])
	if not SECURITY.is_plausible_secret(secret):
		_failures.append("EMBERVALE_REVENUECAT_SECRET is missing or not a plausible sk_ key.")
	if customer_id.is_empty():
		_failures.append("EMBERVALE_STORE_CUSTOMER_ID is required: use the App User ID the "
			+ "purchase was made with (the app's ev_... id, or your funnel URL id).")
	else:
		problem = SECURITY.validate_customer_id(customer_id)
		if not problem.is_empty():
			_failures.append("EMBERVALE_STORE_CUSTOMER_ID is malformed (%s)." % problem)
	var catalog_errors: Array[String] = CATALOG.validate()
	if not catalog_errors.is_empty():
		_failures.append("Web catalog is invalid: %s" % "; ".join(catalog_errors))
	if not funnel_url.is_empty():
		problem = SECURITY.validate_url(funnel_url, SECURITY.ALLOWED_FUNNEL_HOSTS)
		if not problem.is_empty():
			_failures.append("EMBERVALE_STORE_FUNNEL_URL is rejected (%s)." % problem)
		else:
			print("  checkout : %s/%s" % [funnel_url.trim_suffix("/"),
				customer_id.uri_encode()])

func _fetch_active(project_id: String, customer_id: String, secret: String) -> Array:
	var built := CLIENT.build_active_entitlements_request(project_id, customer_id)
	if not bool(built.get("ok", false)):
		_failures.append("Could not build the request: %s" % str(built.get("error", "")))
		return []
	var http := HTTPRequest.new()
	http.timeout = 15.0
	http.max_redirects = 0
	http.body_size_limit = CLIENT.MAX_BODY_BYTES
	get_root().add_child(http)
	var headers := CLIENT.with_bearer(built.get("headers", PackedStringArray()), secret)
	if headers.size() < 2:
		_failures.append("The credential was refused by the header guard.")
		http.queue_free()
		return []
	var started := http.request(str(built.get("url", "")), headers, HTTPClient.METHOD_GET)
	if started != OK:
		_failures.append("Request could not start (error %d)." % started)
		http.queue_free()
		return []
	var response: Array = await http.request_completed
	http.queue_free()
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS:
		_failures.append("Transport failed (result %d). Check connectivity; a redirect "
			+ "or TLS failure is refused by design." % int(response[0]))
		return []
	var body := (response[3] as PackedByteArray).get_string_from_utf8()
	var parsed := CLIENT.parse_active_entitlements(int(response[1]), body)
	if not bool(parsed.get("ok", false)):
		_failures.append("RevenueCat answered HTTP %d: %s" % [int(response[1]),
			str(parsed.get("error", ""))])
		return []
	var active: Array = parsed.get("active", [])
	print("  active   : %d entitlement(s)" % active.size())
	var claimed := _claimed_record_ids()
	var grantable := 0
	var diamonds := 0
	for row in active:
		var entry: Dictionary = row
		var entitlement_id := str(entry.get("entitlement_id", ""))
		var tier := CATALOG.tier_for_entitlement(entitlement_id)
		var expiry := int(entry.get("expires_at_ms", CLIENT.LIFETIME_EXPIRY_MS))
		var expiry_text := "lifetime" if expiry == CLIENT.LIFETIME_EXPIRY_MS \
			else Time.get_datetime_string_from_unix_time(int(expiry / 1000.0), true) + "Z"
		if tier.is_empty():
			print("    - %s (%s): NOT IN THE WEB CATALOG — the app would ignore it"
				% [entitlement_id, expiry_text])
			continue
		var record_id := CATALOG.claim_record_id(tier, expiry)
		if record_id in claimed:
			print("    - %s (%s): already claimed on this device (%d ember marks)"
				% [entitlement_id, expiry_text, int(tier.get("diamonds", 0))])
			continue
		grantable += 1
		diamonds += int(tier.get("diamonds", 0))
		print("    - %s (%s): claimable as %s for %d ember marks"
			% [entitlement_id, expiry_text, str(tier.get("id", "")),
				int(tier.get("diamonds", 0))])
	if grantable > 0:
		print("  result   : RESTORE in game would deliver %d pack(s), %d ember marks"
			% [grantable, diamonds])
	return active

## Reads the gameplay save read-only, so the check never mutates progress.
## Goes through SaveService so the encrypted container and a legacy plaintext
## save are both handled by the same reader the game uses.
func _claimed_record_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	var loaded := SAVE_SERVICE.new().load_config(SAVE_PATH)
	var cfg := loaded.get("config") as ConfigFile
	if cfg == null:
		return ids
	var ledger: Variant = cfg.get_value("progress", "purchase_ledger", [])
	if not ledger is Array:
		return ids
	for entry in (ledger as Array):
		if entry is Dictionary:
			var record_id := str((entry as Dictionary).get("provider_record_id", ""))
			if not record_id.is_empty():
				ids.append(record_id)
	return ids

func _catalog_ids() -> Array[String]:
	var ids: Array[String] = []
	for tier in CATALOG.all():
		ids.append(str(tier.get("entitlement_id", "")))
	return ids

func _report() -> void:
	if _failures.is_empty():
		print("SETUP CHECK PASSED")
		quit(0)
		return
	for failure in _failures:
		print("FAIL: %s" % failure)
	print("SETUP CHECK FAILED (%d)" % _failures.size())
	quit(1)
