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

const ENV_PROJECT_ID := "EMBERVALE_REVENUECAT_PROJECT_ID"
const ENV_DIRECT_SECRET := "EMBERVALE_REVENUECAT_SECRET"
const ENV_BACKEND_URL := "EMBERVALE_STORE_BACKEND_URL"
const ENV_ACCESS_TOKEN := "EMBERVALE_STORE_ACCESS_TOKEN"
const ENV_FUNNEL_URL := "EMBERVALE_STORE_FUNNEL_URL"

enum Authority { NONE, BACKEND, DIRECT }

var _authority: Authority = Authority.NONE
var _project_id := ""
var _backend_url := ""
var _funnel_url := ""
var _direct_secret := ""
var _customer_id := ""

var _account := AccountSession.new()
var _entitlements := EntitlementService.new()
var _purchase_sync := PurchaseSyncService.new()

var _http: HTTPRequest = null
var _in_flight := false
var _last_refresh_ms := -1_000_000
var _last_result: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_config()
	reload_from_environment()
	_ensure_customer_id()

func _exit_tree() -> void:
	_free_http()

## Which credential the current configuration would use. Exposed for the
## release audit and the support export; it never reveals the credential.
func authority_name() -> String:
	match _authority:
		Authority.BACKEND:
			return "backend"
		Authority.DIRECT:
			return "direct_editor_debug"
		_:
			return "none"

func is_available() -> bool:
	return _authority != Authority.NONE and not _project_id.is_empty() \
		and not _customer_id.is_empty() \
		and (_authority != Authority.BACKEND or not _backend_url.is_empty())

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
		access_token: String = "") -> bool:
	var project := project_id.strip_edges()
	var secret := direct_secret.strip_edges()
	var backend := backend_url.strip_edges()
	var funnel := funnel_url.strip_edges()
	var token := access_token.strip_edges()
	# An all-empty call is an explicit clear, not a malformed configuration.
	if project.is_empty() and secret.is_empty() and backend.is_empty() \
			and funnel.is_empty() and token.is_empty():
		_reject()
		return false
	var problem := _validate_configuration(project, secret, backend, funnel, token)
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
	_account.configure_token(token)
	_authority = _resolve_authority()
	# Least privilege: when a stronger authority is in play, drop the secret.
	if _authority == Authority.BACKEND:
		_direct_secret = ""
	_ensure_customer_id()
	availability_changed.emit(is_available())
	return is_available()

func _validate_configuration(project: String, secret: String, backend: String,
		funnel: String, token: String) -> String:
	var problem := StoreSecurity.validate_project_id(project)
	if not problem.is_empty():
		return problem
	if not funnel.is_empty():
		problem = StoreSecurity.validate_url(funnel, StoreSecurity.ALLOWED_FUNNEL_HOSTS)
		if not problem.is_empty():
			return "funnel_%s" % problem
	if not backend.is_empty():
		problem = StoreSecurity.validate_backend_url(backend)
		if not problem.is_empty():
			return "backend_%s" % problem
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
	_authority = Authority.NONE
	availability_changed.emit(false)

## Re-reads the non-secret config file, then environment overrides. Environment
## wins so a device QA run can point at a staging project without editing files.
func reload_from_environment() -> void:
	_project_id = _env_or(ENV_PROJECT_ID, _project_id)
	_funnel_url = _env_or(ENV_FUNNEL_URL, _funnel_url)
	_backend_url = _env_or(ENV_BACKEND_URL, _backend_url)
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
	availability_changed.emit(is_available())

func load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	_project_id = str(cfg.get_value("store", "project_id", _project_id)).strip_edges()
	_funnel_url = str(cfg.get_value("store", "funnel_url", _funnel_url)).strip_edges()
	_backend_url = str(cfg.get_value("store", "backend_url", _backend_url)).strip_edges()
	_customer_id = str(cfg.get_value("store", "customer_id", _customer_id)).strip_edges()

func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("store", "project_id", _project_id)
	cfg.set_value("store", "funnel_url", _funnel_url)
	cfg.set_value("store", "backend_url", _backend_url)
	cfg.set_value("store", "customer_id", _customer_id)
	cfg.save(CONFIG_PATH)

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

## Confirms entitlements with the authority, then claims any ungranted pack.
## Returns `{ok, status, error, active, granted, skipped, diamonds}`.
func refresh_and_claim() -> Dictionary:
	return await _refresh_flow()

func _refresh_flow() -> Dictionary:
	var result := {"ok": false, "status": "unconfigured", "error": "unconfigured",
		"active": 0, "granted": 0, "skipped": 0, "diamonds": 0}
	if not is_available():
		_finish(result)
		return result
	if _in_flight:
		result["status"] = "busy"
		result["error"] = "busy"
		_finish(result)
		return result
	var now := Time.get_ticks_msec()
	if now - _last_refresh_ms < int(MIN_REFRESH_INTERVAL_SECONDS * 1000.0):
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

func _fetch_active_entitlements() -> Dictionary:
	if _authority == Authority.BACKEND:
		return await _fetch_via_backend()
	return await _fetch_direct()

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

func _http_get(url: String, headers: PackedStringArray) -> Dictionary:
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
	if _project_id.is_empty():
		return Authority.NONE
	if not _backend_url.is_empty() and _has_backend_token():
		return Authority.BACKEND
	if not _direct_secret.is_empty() and _direct_secret_allowed():
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
