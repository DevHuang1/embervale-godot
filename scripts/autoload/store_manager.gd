extends Node

## === Web purchase authority — RevenueCat Funnels + Stripe ===
##
## Contract
##  - Offline and unconfigured are first-class no-ops. No store config means the
##    game plays exactly as before; nothing here blocks or gates local play.
##  - A purchase is provider-confirmed, then recorded as an auditable row in the
##    gameplay ledger. Provider state never replaces the gameplay database.
##  - Grants are idempotent: one provider record id is claimable once, so a
##    refresh loop, a restart, or a save reload cannot double-grant ember marks.
##  - A RevenueCat secret key is NEVER part of an exported client. The shipping
##    authority is a backend proxy holding an app-scoped bearer token; the
##    direct-secret authority is editor/debug-only and refuses release exports.
##  - The native authority carries no secret at all: the Android plugin is
##    configured with the PUBLIC SDK key and only READS the customer's
##    entitlements, so the device never needs a backend or a secret to claim.
##
## Resource lifetime: at most one refresh in flight, a hard 15 s timeout, a hard
## cap on claimed rows per refresh, and the request node is freed on exit.

signal availability_changed(available: bool)
signal refresh_started
signal refresh_finished(result: Dictionary)
signal purchase_claimed(grants: int, diamonds: int)

const REFRESH_TIMEOUT_SECONDS := 15.0
const MIN_REFRESH_INTERVAL_SECONDS := 5.0
const MAX_CLAIMS_PER_REFRESH := 8
## A single pack can never be worth more than this, whatever a body claims.
const MAX_GRANT_DIAMONDS_PER_CLAIM := 10_000
const CONFIG_PATH := "user://store.cfg"
## Build-time defaults for targets with no environment (Android): the same
## non-secret values as a `res://` RESOURCE compiled into the build. A plain
## `.cfg` would not ship (the exporter only packs resources), which is why this
## is a `StoreDefaults` resource and not another config file. It is gitignored so
## a sandbox funnel URL never reaches the repository, it is read before the
## device file so a debug device can still override it, and it carries no
## identity at all: every install mints its own customer id.
const DEFAULT_CONFIG_PATH := "res://store_defaults.tres"
## Both paths are overridable so headless suites can exercise loading without
## touching the developer's real store configuration.
var config_path := CONFIG_PATH
var default_config_path := DEFAULT_CONFIG_PATH
## Editor and CI runs use the environment instead of the shipped file, so a
## developer's local defaults can never change editor or test behavior. An
## exported build is exactly the case that needs the file.
var load_build_defaults := not OS.has_feature("editor")

const ENV_PROJECT_ID := "EMBERVALE_REVENUECAT_PROJECT_ID"
const ENV_DIRECT_SECRET := "EMBERVALE_REVENUECAT_SECRET"
const ENV_BACKEND_URL := "EMBERVALE_STORE_BACKEND_URL"
const ENV_ACCESS_TOKEN := "EMBERVALE_STORE_ACCESS_TOKEN"
const ENV_FUNNEL_URL := "EMBERVALE_STORE_FUNNEL_URL"
## The public SDK key is not a secret: it identifies the app to RevenueCat.
const ENV_NATIVE_KEY := "EMBERVALE_REVENUECAT_PUBLIC_KEY"

enum Authority { NONE, BACKEND, NATIVE, DIRECT }

var _authority: Authority = Authority.NONE
var _project_id := ""
var _backend_url := ""
var _funnel_url := ""
var _direct_secret := ""
var _native_api_key := ""
var _customer_id := ""

## Injectable so headless suites can drive the native authority without Android.
var native_bridge: RevenueCatNativeBridge = null

var _account := AccountSession.new()
var _entitlements := EntitlementService.new()
var _purchase_sync := PurchaseSyncService.new()

var _http: HTTPRequest = null
var _in_flight := false
var _last_refresh_ms := -1_000_000
var _last_result: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	native_bridge = RevenueCatNativeBridge.new()
	load_config()
	reload_from_environment()
	_ensure_customer_id()
	# The SDK must be configured with the App User ID the funnel appends, so
	# this runs only after a customer id exists.
	_sync_native_bridge()

func _exit_tree() -> void:
	_free_http()

## Which credential the current configuration would use. Exposed for the
## release audit and the support export; it never reveals the credential.
func authority_name() -> String:
	match _authority:
		Authority.BACKEND:
			return "backend"
		Authority.NATIVE:
			return "native"
		Authority.DIRECT:
			return "direct_editor_debug"
		_:
			return "none"

func is_available() -> bool:
	if _authority == Authority.NONE or _customer_id.is_empty():
		return false
	if _authority == Authority.BACKEND:
		return not _backend_url.is_empty()
	if _authority == Authority.NATIVE:
		# The SDK reader needs no project id: the public key identifies the app.
		return native_bridge != null and native_bridge.is_available()
	return not _project_id.is_empty()

func availability_state() -> String:
	if not is_available():
		return "unavailable"
	if _in_flight:
		return "pending"
	return "ready"

func last_result() -> Dictionary:
	return _last_result.duplicate(true)

func customer_id() -> String:
	if _account.is_authenticated():
		return _account.account_id
	return _customer_id

func configure(project_id: String, direct_secret: String = "",
		backend_url: String = "", funnel_url: String = "",
		access_token: String = "", native_api_key: String = "") -> bool:
	var project := project_id.strip_edges()
	var secret := direct_secret.strip_edges()
	var backend := backend_url.strip_edges()
	var funnel := funnel_url.strip_edges()
	var token := access_token.strip_edges()
	var native_key := native_api_key.strip_edges()
	# An all-empty call is an explicit clear, not a malformed configuration.
	if project.is_empty() and secret.is_empty() and backend.is_empty() \
			and funnel.is_empty() and token.is_empty() and native_key.is_empty():
		_reject()
		return false
	var problem := _validate_configuration(project, secret, backend, funnel, token, native_key)
	if not problem.is_empty():
		# Fail closed: nothing from a rejected configuration is retained. The
		# store simply stays unavailable, so this is a warning, not a crash; and
		# the message never echoes a credential.
		_reject()
		push_warning("StoreManager: rejected store configuration (%s)." % problem)
		return false
	_project_id = project
	_backend_url = backend.trim_suffix("/")
	_funnel_url = funnel.trim_suffix("/")
	_direct_secret = secret
	_native_api_key = native_key
	_account.configure_token(token)
	_authority = _resolve_authority()
	# Least privilege: when a stronger authority is in play, drop the secret.
	if _authority == Authority.BACKEND or _authority == Authority.NATIVE:
		_direct_secret = ""
	_ensure_customer_id()
	_sync_native_bridge()
	availability_changed.emit(is_available())
	return is_available()

## Hands the SDK the public key and the stable device customer id. A customer id
## must exist first: configuring the SDK anonymously would create a second
## customer that the hosted funnel knows nothing about.
func _sync_native_bridge() -> void:
	if native_bridge == null or _authority != Authority.NATIVE:
		return
	var id := customer_id()
	if id.is_empty() or _native_api_key.is_empty():
		return
	native_bridge.configure(_native_api_key, id)

func _validate_configuration(project: String, secret: String, backend: String,
		funnel: String, token: String, native_key: String = "") -> String:
	var native_problem := StoreSecurity.validate_public_sdk_key(native_key) \
		if not native_key.is_empty() else ""
	if not native_problem.is_empty():
		return native_problem
	# The native reader identifies the app by its public key alone, so a
	# project id is only required by the authorities that call the REST API.
	if project.is_empty() and native_key.is_empty():
		return "empty_project_id"
	if not project.is_empty():
		var project_problem := StoreSecurity.validate_project_id(project)
		if not project_problem.is_empty():
			return project_problem
	if not funnel.is_empty():
		var funnel_problem := StoreSecurity.validate_url(funnel, StoreSecurity.ALLOWED_FUNNEL_HOSTS)
		if not funnel_problem.is_empty():
			return "funnel_%s" % funnel_problem
	if not backend.is_empty():
		var backend_problem := StoreSecurity.validate_backend_url(backend)
		if not backend_problem.is_empty():
			return "backend_%s" % backend_problem
	if not token.is_empty() and not StoreSecurity.is_safe_header_value(token):
		return "backend_token_unsafe"
	if not secret.is_empty() and not StoreSecurity.is_plausible_secret(secret):
		return "implausible_secret"
	return ""

func _reject() -> void:
	_project_id = ""
	_direct_secret = ""
	_backend_url = ""
	_funnel_url = ""
	_native_api_key = ""
	_authority = Authority.NONE
	availability_changed.emit(false)

## Re-reads the non-secret config file, then environment overrides. Environment
## wins so a device QA run can point at a staging project without editing files.
func reload_from_environment() -> void:
	_project_id = _env_or(ENV_PROJECT_ID, _project_id)
	_funnel_url = _env_or(ENV_FUNNEL_URL, _funnel_url)
	_backend_url = _env_or(ENV_BACKEND_URL, _backend_url)
	_native_api_key = _env_or(ENV_NATIVE_KEY, _native_api_key)
	var token := _env_or(ENV_ACCESS_TOKEN, "")
	if not token.is_empty():
		_account.configure_token(token)
	# The secret is read from the environment only: it is never written to
	# disk and never committed, so a public repository cannot leak it.
	var secret := OS.get_environment(ENV_DIRECT_SECRET).strip_edges()
	if not secret.is_empty():
		if StoreSecurity.is_plausible_secret(secret):
			_direct_secret = secret
		else:
			_direct_secret = ""
			push_warning("StoreManager: ignored %s because it is not a plausible provider secret." % ENV_DIRECT_SECRET)
	_authority = _resolve_authority()
	_sync_native_bridge()
	availability_changed.emit(is_available())

func load_config() -> void:
	# Precedence is build defaults (res://) -> device file (user://) -> process
	# environment (applied by reload_from_environment later). Each later source
	# overrides per field; an empty field never clears an earlier source, while
	# a present-but-invalid one fails closed and clears the field it attacked.
	if load_build_defaults:
		_apply_shipped_defaults(default_config_path)
	_apply_config_file(config_path, true)
	# Leave a consistent authority after loading: boot continues with the
	# environment overlay, but a direct caller (tests, tools) must not observe
	# configured fields next to a stale `none` authority.
	_authority = _resolve_authority()

## Re-validates the shipped resource over the current values, with the same
## fail-closed rules as a stored file: a malformed or hostile value clears the
## field it attacked instead of half-configuring the store.
func _apply_shipped_defaults(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var defaults := ResourceLoader.load(path) as StoreDefaults
	if defaults == null:
		push_warning("StoreManager: ignored the shipped defaults because it is not a StoreDefaults resource.")
		return
	_apply_project(defaults.project_id)
	_apply_funnel(defaults.funnel_url)
	_apply_backend(defaults.backend_url)
	_apply_access_token(defaults.access_token)
	# A sealed field that cannot be recovered is corrupt or hostile, not absent:
	# clear the key instead of leaving an earlier source's value in place.
	if defaults.native_api_key.strip_edges().is_empty() \
			and not defaults.native_api_key_sealed.strip_edges().is_empty() \
			and defaults.resolved_native_api_key().is_empty():
		_native_api_key = ""
		push_warning("StoreManager: ignored a shipped key that could not be unsealed.")
	else:
		_apply_native_key(defaults.resolved_native_api_key())

func _apply_project(project_id: String) -> void:
	var project := project_id.strip_edges()
	if not project.is_empty():
		_project_id = project

func _apply_funnel(funnel_url: String) -> void:
	var funnel := funnel_url.strip_edges()
	if funnel.is_empty():
		return
	_funnel_url = funnel if StoreSecurity.validate_url(
		funnel, StoreSecurity.ALLOWED_FUNNEL_HOSTS).is_empty() else ""
	if _funnel_url.is_empty():
		push_warning("StoreManager: ignored a shipped funnel URL that is not an allowed hosted link.")

func _apply_backend(backend_url: String) -> void:
	var backend := backend_url.strip_edges()
	if backend.is_empty():
		return
	_backend_url = backend if StoreSecurity.validate_backend_url(backend).is_empty() else ""
	if _backend_url.is_empty():
		push_warning("StoreManager: ignored a shipped backend URL that is not a safe HTTPS endpoint.")

## The backend authority authenticates with a low-privilege app token that is
## rotatable by rewriting the shipped resource. A value that could not be sent
## as a header is dropped rather than half-applied, exactly like a bad key.
func _apply_access_token(access_token: String) -> void:
	var token := access_token.strip_edges()
	if token.is_empty():
		return
	if not StoreSecurity.is_safe_header_value(token):
		# A value that cannot be sent as a header is hostile or corrupt, not
		# absent: drop any earlier token instead of letting it survive a
		# tampered resource.
		push_warning("StoreManager: ignored a shipped access token that is not a safe header value.")
		_account.configure_token("")
		return
	_account.configure_token(token)

func _apply_native_key(native_api_key: String) -> void:
	var native_key := native_api_key.strip_edges()
	if native_key.is_empty():
		return
	_native_api_key = native_key if StoreSecurity.validate_public_sdk_key(native_key).is_empty() else ""
	if _native_api_key.is_empty():
		push_warning("StoreManager: ignored a shipped key that is not a plausible public SDK key.")

## Re-validates one store config file over the current values. A tampered,
## hand-edited, or malformed value is dropped rather than trusted, so a bad key
## or a hostile host can never half-configure the store.
func _apply_config_file(path: String, allow_identity: bool) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	_project_id = str(cfg.get_value("store", "project_id", _project_id)).strip_edges()
	if allow_identity:
		var identity := str(cfg.get_value("store", "customer_id", _customer_id)).strip_edges()
		if not identity.is_empty():
			_customer_id = identity
	var funnel := str(cfg.get_value("store", "funnel_url", "")).strip_edges()
	if not funnel.is_empty():
		_funnel_url = funnel if StoreSecurity.validate_url(
			funnel, StoreSecurity.ALLOWED_FUNNEL_HOSTS).is_empty() else ""
		if _funnel_url.is_empty():
			push_warning("StoreManager: ignored a stored funnel URL that is not an allowed hosted link.")
	var backend := str(cfg.get_value("store", "backend_url", "")).strip_edges()
	if not backend.is_empty():
		_backend_url = backend if StoreSecurity.validate_backend_url(backend).is_empty() else ""
		if _backend_url.is_empty():
			push_warning("StoreManager: ignored a stored backend URL that is not a safe HTTPS endpoint.")
	# The public SDK key is designed to ship, so it may live in either file.
	var native_key := str(cfg.get_value("store", "native_api_key", "")).strip_edges()
	if not native_key.is_empty():
		_native_api_key = native_key if StoreSecurity.validate_public_sdk_key(native_key).is_empty() else ""
		if _native_api_key.is_empty():
			push_warning("StoreManager: ignored a stored key that is not a plausible public SDK key.")

func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("store", "project_id", _project_id)
	cfg.set_value("store", "funnel_url", _funnel_url)
	cfg.set_value("store", "backend_url", _backend_url)
	cfg.set_value("store", "customer_id", _customer_id)
	cfg.set_value("store", "native_api_key", _native_api_key)
	cfg.save(config_path)

## True when this build has a hosted funnel at all. An SDK-only build has no
## funnel, so the UI drops the browser row instead of offering a button that can
## only fail.
func has_hosted_checkout() -> bool:
	return not _funnel_url.is_empty()

## The hosted checkout URL for this customer. Exposed so the release audit and
## device QA can verify the App User ID hand-off without opening a browser.
func checkout_url() -> String:
	if not is_available() or _funnel_url.is_empty():
		return ""
	var url := "%s/%s" % [_funnel_url.trim_suffix("/"), customer_id().uri_encode()]
	return url if url.begins_with("https://") else ""

## Opens the hosted RevenueCat funnel for this customer. The App User ID is
## appended so the web purchase lands on the same customer the app reads back.
func open_web_store() -> bool:
	var url := checkout_url()
	if url.is_empty():
		return false
	_purchase_sync.begin_provider_purchase()
	return OS.shell_open(url) == OK

## Fire-and-forget refresh; the UI observes the signals instead of awaiting.
func request_refresh() -> void:
	_refresh_flow()

## A hosted checkout finishes in the browser, so the purchase lands while the
## game is in the background. Coming back re-checks the provider immediately
## rather than making the player find RESTORE; the gate is only armed while a
## checkout is open, and a plain return with no checkout does nothing.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_IN \
			and what != NOTIFICATION_WM_WINDOW_FOCUS_IN:
		return
	if not _purchase_sync.provider_returned():
		return
	# Forced: a purchase that just completed must be claimable even if the shop
	# refreshed seconds before the browser opened.
	refresh_and_claim.call_deferred(true)

## Confirms entitlements with the authority, then claims any ungranted pack.
## Returns `{ok, status, error, active, granted, skipped, diamonds}`.
## `force` skips the refresh throttle: a purchase that just completed must be
## claimable immediately, even if the shop refreshed seconds earlier.
func refresh_and_claim(force: bool = false) -> Dictionary:
	return await _refresh_flow(force)

## Starts a purchase through the native SDK and claims whatever it delivered.
## The Test Store answers this with its simulated sheet, so the whole
## buy -> provider read -> exactly-once claim loop can be demonstrated and
## tested with no store account and no payment provider. Returns
## `{ok, status, error, product_id, granted, diamonds}`.
func buy(product_id: String) -> Dictionary:
	var wanted := product_id.strip_edges()
	var result := {"ok": false, "purchased": false, "status": "unavailable",
		"error": "unavailable", "product_id": wanted, "granted": 0, "diamonds": 0}
	if wanted.is_empty():
		result["status"] = "invalid_product"
		result["error"] = "invalid_product"
		return result
	if _authority != Authority.NATIVE or native_bridge == null \
			or not native_bridge.is_available():
		return result
	var purchase: Dictionary = await native_bridge.purchase(wanted)
	result["status"] = str(purchase.get("status", "error"))
	result["error"] = str(purchase.get("error", "purchase_failed"))
	if not bool(purchase.get("ok", false)):
		return result
	result["purchased"] = true
	# The purchase's own return value never grants: the claim re-reads provider
	# state, so only a purchase the provider reports is delivered.
	var claimed: Dictionary = await refresh_and_claim(true)
	result["granted"] = int(claimed.get("granted", 0))
	result["diamonds"] = int(claimed.get("diamonds", 0))
	result["ok"] = bool(claimed.get("ok", false))
	if not result["ok"]:
		# The purchase stands even when the follow-up read failed; the status
		# explains why delivery is still pending.
		result["status"] = str(claimed.get("status", "claim_failed"))
		result["error"] = str(claimed.get("error", "claim_failed"))
	return result

func _refresh_flow(force: bool = false) -> Dictionary:
	var result := {"ok": false, "status": "unconfigured", "error": "unconfigured",
		"active": 0, "granted": 0, "skipped": 0, "diamonds": 0}
	if not is_available():
		_finish(result)
		return result
	if _in_flight:
		if not force:
			result["status"] = "busy"
			result["error"] = "busy"
			_finish(result)
			return result
		# A completed purchase must not be dropped because a periodic refresh
		# happened to be running: wait for it, then re-read.
		var wait_until := Time.get_ticks_msec() + int(REFRESH_TIMEOUT_SECONDS * 1000.0)
		while _in_flight and Time.get_ticks_msec() < wait_until:
			var loop := Engine.get_main_loop() as SceneTree
			if loop == null:
				break
			await loop.process_frame
		if _in_flight:
			result["status"] = "busy"
			result["error"] = "busy"
			_finish(result)
			return result
	var now := Time.get_ticks_msec()
	if not force and now - _last_refresh_ms < int(MIN_REFRESH_INTERVAL_SECONDS * 1000.0):
		result["status"] = "rate_limited"
		result["error"] = "rate_limited"
		_finish(result)
		return result
	_in_flight = true
	_last_refresh_ms = now
	refresh_started.emit()
	var active: Array[Dictionary] = []
	var transport := await _fetch_active_entitlements()
	result["status"] = str(transport.get("status", "error"))
	result["error"] = str(transport.get("error", ""))
	if bool(transport.get("ok", false)):
		active = transport.get("active", [] as Array[Dictionary])
		result["active"] = active.size()
		_entitlements.apply_server_snapshot(_as_snapshots(active))
		var claimed := claim(active)
		result["granted"] = int(claimed.get("granted", 0))
		result["skipped"] = int(claimed.get("skipped", 0))
		result["diamonds"] = int(claimed.get("diamonds", 0))
		var txn_transport := await _fetch_non_subscription_transactions()
		if bool(txn_transport.get("ok", false)):
			var transactions: Array[Dictionary] = txn_transport.get(
				"transactions", [] as Array[Dictionary])
			result["transactions"] = transactions.size()
			var txn_claimed := claim_transactions(transactions)
			result["granted"] = int(result["granted"]) + int(txn_claimed.get("granted", 0))
			result["skipped"] = int(result["skipped"]) + int(txn_claimed.get("skipped", 0))
			result["diamonds"] = int(result["diamonds"]) + int(txn_claimed.get("diamonds", 0))
		result["ok"] = true
	_in_flight = false
	_finish(result)
	return result

## Records every ungranted, catalogued entitlement through the gameplay ledger.
## Unknown entitlements are counted as skipped, never guessed at.
func claim(active: Array[Dictionary]) -> Dictionary:
	var grants: Array[Dictionary] = []
	var skipped := 0
	for entry in active:
		if grants.size() >= MAX_CLAIMS_PER_REFRESH:
			break
		var entitlement_id := str(entry.get("entitlement_id", "")).strip_edges()
		var tier := WebStoreCatalog.tier_for_entitlement(entitlement_id)
		if tier.is_empty():
			skipped += 1
			continue
		if str(tier.get("claim_grain", "")) == WebStoreCatalog.GRAIN_TRANSACTION:
			# A repeatable consumable's entitlement never lapses, so an active
			# entitlement is not a purchase event. Those packs are claimed from
			# the transaction list; claiming here would double-grant the first
			# purchase and refuse every later one.
			continue
		var expiry := int(entry.get("expires_at_ms", RevenueCatApiClient.LIFETIME_EXPIRY_MS))
		# The tier's own claim grain decides the key, so a later body carrying a
		# different expiry cannot mint a second grant for a one-time pack.
		var record_id := WebStoreCatalog.claim_record_id(tier, expiry)
		var game_state := _game_state()
		if game_state != null and game_state.is_provider_claim_recorded(record_id):
			skipped += 1
			continue
		var grant_diamonds := int(tier.get("diamonds", 0))
		if grant_diamonds <= 0 or grant_diamonds > MAX_GRANT_DIAMONDS_PER_CLAIM:
			skipped += 1
			continue
		grants.append({
			"id": str(tier.get("id", "")),
			"kind": "provider_embermarks",
			"diamonds": grant_diamonds,
			"provider": "revenuecat",
			"provider_record_id": record_id,
			"provider_entitlement": entitlement_id,
			"provider_expires_at": expiry,
		})
	var granted := 0
	var diamonds := 0
	var game_state := _game_state()
	if not grants.is_empty() and game_state != null:
		var outcome: Dictionary = game_state.grant_provider_entitlements(grants)
		granted = int(outcome.get("granted", 0))
		diamonds = int(outcome.get("diamonds", 0))
	if granted > 0:
		_purchase_sync.provider_purchase_finished()
		purchase_claimed.emit(granted, diamonds)
	return {"granted": granted, "skipped": skipped, "diamonds": diamonds}

## Records every ungranted consumable transaction through the gameplay ledger.
## Each transaction grants once, so buying the same pack again delivers again
## while re-reading the same transaction never does.
func claim_transactions(transactions: Array[Dictionary]) -> Dictionary:
	var grants: Array[Dictionary] = []
	var skipped := 0
	for entry in transactions:
		if grants.size() >= MAX_CLAIMS_PER_REFRESH:
			break
		var product_id := str(entry.get("product_id", "")).strip_edges()
		var transaction_id := str(entry.get("transaction_id", "")).strip_edges()
		var tier := WebStoreCatalog.tier_for_product(product_id)
		if tier.is_empty() or transaction_id.is_empty() \
				or str(tier.get("claim_grain", "")) != WebStoreCatalog.GRAIN_TRANSACTION:
			skipped += 1
			continue
		var record_id := WebStoreCatalog.claim_record_id_for_transaction(tier, transaction_id)
		var game_state := _game_state()
		if game_state != null and game_state.is_provider_claim_recorded(record_id):
			skipped += 1
			continue
		var grant_diamonds := int(tier.get("diamonds", 0))
		if grant_diamonds <= 0 or grant_diamonds > MAX_GRANT_DIAMONDS_PER_CLAIM:
			skipped += 1
			continue
		grants.append({
			"id": str(tier.get("id", "")),
			"kind": "provider_embermarks",
			"diamonds": grant_diamonds,
			"provider": "revenuecat",
			"provider_record_id": record_id,
			"provider_transaction": transaction_id,
			"provider_product": product_id,
		})
	var granted := 0
	var diamonds := 0
	var game_state := _game_state()
	if not grants.is_empty() and game_state != null:
		var outcome: Dictionary = game_state.grant_provider_entitlements(grants)
		granted = int(outcome.get("granted", 0))
		diamonds = int(outcome.get("diamonds", 0))
	if granted > 0:
		_purchase_sync.provider_purchase_finished()
		purchase_claimed.emit(granted, diamonds)
	return {"granted": granted, "skipped": skipped, "diamonds": diamonds}

## Consumable transactions exist only where the authority can see the store
## purchase list: the native reader, or the backend proxy's `/transactions`
## route. Without one, a pack that is granted once per purchase could never be
## granted at all, so this reports `unsupported` rather than pretending the
## customer has no purchases.
func _fetch_non_subscription_transactions() -> Dictionary:
	if _authority == Authority.NATIVE:
		if native_bridge == null or not native_bridge.is_available():
			return {"ok": false, "status": "unavailable",
				"error": "native_bridge_unavailable",
				"transactions": [] as Array[Dictionary]}
		return await native_bridge.fetch_non_subscription_transactions()
	if _authority == Authority.BACKEND:
		var request := backend_transactions_request()
		if request.is_empty():
			return {"ok": false, "status": "unconfigured",
				"error": "backend_token_missing", "transactions": [] as Array[Dictionary]}
		return await _http_get(str(request.get("url", "")),
			request.get("headers", PackedStringArray()),
			func(status: int, body: String) -> Dictionary:
				return RevenueCatApiClient.parse_non_subscription_transactions(status, body))
	return {"ok": false, "status": "unsupported",
		"error": "transactions_unsupported", "transactions": [] as Array[Dictionary]}

## The backend transaction read: the same bearer token and route shape as the
## entitlement read, on the page the game claims consumables from. Exposed for
## the headless suites, which cannot open a socket.
func backend_transactions_request() -> Dictionary:
	if _authority != Authority.BACKEND:
		return {}
	var client := BackendApiClient.new(_backend_url)
	client.configure_token(_account.access_token)
	if not client.can_request():
		return {}
	var base := _backend_url.trim_suffix("/")
	return {
		"url": "%s/transactions?customer_id=%s" % [base, customer_id().uri_encode()],
		"headers": client.authorization_headers(),
	}

func _fetch_active_entitlements() -> Dictionary:
	if _authority == Authority.BACKEND:
		return await _fetch_via_backend()
	if _authority == Authority.NATIVE:
		return await _fetch_via_native()
	return await _fetch_direct()

## The SDK reader needs no secret and no server: it reads the same customer the
## hosted funnel wrote to, then hands the rows to the shared parser.
func _fetch_via_native() -> Dictionary:
	if native_bridge == null or not native_bridge.is_available():
		return {"ok": false, "status": "unavailable",
			"error": "native_bridge_unavailable", "active": [] as Array[Dictionary]}
	return await native_bridge.fetch_active_entitlements()

func _fetch_direct() -> Dictionary:
	var built := RevenueCatApiClient.build_active_entitlements_request(
		_project_id, customer_id())
	if not bool(built.get("ok", false)):
		return {"ok": false, "status": "invalid_request",
			"error": str(built.get("error", "invalid_request"))}
	var headers := RevenueCatApiClient.with_bearer(
		built.get("headers", PackedStringArray()), _direct_secret)
	return await _http_get(str(built.get("url", "")), headers)

## The backend returns the same shape as RevenueCat's `active_entitlements`
## list, so one parser serves both authorities.
func _fetch_via_backend() -> Dictionary:
	var client := BackendApiClient.new(_backend_url)
	client.configure_token(_account.access_token)
	if not client.can_request():
		return {"ok": false, "status": "unconfigured", "error": "backend_token_missing"}
	var base := _backend_url.trim_suffix("/")
	var url := "%s/entitlements/active?customer_id=%s" % [base, customer_id().uri_encode()]
	return await _http_get(url, client.authorization_headers())

func _http_get(url: String, headers: PackedStringArray,
		parser: Callable = Callable()) -> Dictionary:
	if not url.begins_with("https://"):
		return {"ok": false, "status": "invalid_request", "error": "insecure_url"}
	var http := _ensure_http()
	var err := http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_free_http()
		return {"ok": false, "status": "offline", "error": "request_failed"}
	var response: Array = await http.request_completed
	_free_http()
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS:
		var status := "timeout" if int(response[0]) == HTTPRequest.RESULT_TIMEOUT \
			else "offline"
		if int(response[0]) == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			status = "redirect_refused"
		return {"ok": false, "status": status, "error": status}
	var body := (response[3] as PackedByteArray).get_string_from_utf8()
	if parser.is_valid():
		return parser.call(int(response[1]), body)
	return RevenueCatApiClient.parse_active_entitlements(int(response[1]), body)

func _ensure_http() -> HTTPRequest:
	if _http == null or not is_instance_valid(_http):
		_http = HTTPRequest.new()
		_http.name = "StoreRefreshRequest"
		_http.timeout = REFRESH_TIMEOUT_SECONDS
		# A redirect is never followed: the Authorization header must not be
		# replayed to wherever a response points. The engine also refuses to
		# buffer more than the parser is willing to read.
		_http.max_redirects = 0
		_http.body_size_limit = RevenueCatApiClient.MAX_BODY_BYTES
		add_child(_http)
	return _http

func _free_http() -> void:
	if _http != null and is_instance_valid(_http):
		_http.queue_free()
	_http = null

func _finish(result: Dictionary) -> void:
	_last_result = result.duplicate(true)

func _as_snapshots(active: Array[Dictionary]) -> Array:
	var rows: Array = []
	for entry in active:
		rows.append({
			"entitlement_id": str(entry.get("entitlement_id", "")),
			"active": true,
			"expires_at": int(entry.get("expires_at_ms",
				RevenueCatApiClient.LIFETIME_EXPIRY_MS)),
		})
	return rows

## Shipping exports must never carry a RevenueCat secret key, so the direct
## authority is unavailable there even when the variable is set.
func _direct_secret_allowed() -> bool:
	return OS.has_feature("editor") or OS.is_debug_build()

func _resolve_authority() -> Authority:
	# Precedence: an explicit backend proxy first, then the secret-free native
	# reader, then the editor/debug secret. A configured-but-weaker authority is
	# never silently downgraded into a different one.
	if not _project_id.is_empty() and not _backend_url.is_empty() and _has_backend_token():
		return Authority.BACKEND
	if not _native_api_key.is_empty() and native_bridge != null and native_bridge.is_available():
		return Authority.NATIVE
	if not _project_id.is_empty() and not _direct_secret.is_empty() and _direct_secret_allowed():
		return Authority.DIRECT
	return Authority.NONE

## The backend authority authenticates with an app-scoped bearer token, which
## can exist before a full account login completes.
func _has_backend_token() -> bool:
	return not _account.access_token.strip_edges().is_empty()

func _ensure_customer_id() -> void:
	# A tampered or malformed stored identity is replaced rather than trusted.
	if not StoreSecurity.validate_customer_id(_customer_id).is_empty():
		_customer_id = ""
	if not _customer_id.is_empty():
		return
	_customer_id = "ev_" + Crypto.new().generate_random_bytes(16).hex_encode()
	save_config()

func _env_or(name: String, fallback: String) -> String:
	var value := OS.get_environment(name).strip_edges()
	if value.is_empty():
		return fallback
	return value

func _game_state() -> GameState:
	return get_node_or_null("/root/GameState") as GameState
