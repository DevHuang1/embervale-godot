extends RefCounted
class_name RevenueCatApiClient

## === RevenueCat REST API v2 — read-only entitlement verification ===
## Pure request/response shaping: no HTTP, no key storage, no engine nodes, so
## headless suites can verify every branch with a fake transport.
##
## Security contract: REST API v2 authenticates with a project SECRET key
## (`sk_...`), and RevenueCat requires secret keys to stay out of client code.
## This class therefore never reads, stores, or logs a credential — the caller
## decides which authority supplies one:
##   * backend (shipping path): an app-scoped bearer token, proxied server-side
##   * direct  (editor/debug only): a local secret key for device QA + demo
##
## The client only ever READS entitlements. Nothing here grants, refunds, or
## mutates a customer; a write path would belong to the backend authority.

const API_BASE := "https://api.revenuecat.com/v2"
const MAX_ENTITLEMENTS := 100
const MAX_TRANSACTIONS := 100
const MAX_BODY_BYTES := 65_536
## A null `expires_at` means the entitlement never expires (one-time pack).
const LIFETIME_EXPIRY_MS := -1

static func build_active_entitlements_request(project_id: String,
		customer_id: String) -> Dictionary:
	var project := project_id.strip_edges()
	var customer := customer_id.strip_edges()
	if project.is_empty() or project.length() > 255:
		return {"ok": false, "error": "invalid_project_id", "url": "",
			"headers": PackedStringArray()}
	if customer.is_empty() or customer.length() > 1500:
		return {"ok": false, "error": "invalid_customer_id", "url": "",
			"headers": PackedStringArray()}
	var url := "%s/projects/%s/customers/%s/active_entitlements?limit=%d" % [
		API_BASE, project.uri_encode(), customer.uri_encode(), MAX_ENTITLEMENTS]
	return {"ok": true, "error": "", "url": url,
		"headers": PackedStringArray(["Accept: application/json"])}

static func with_bearer(headers: PackedStringArray, token: String) -> PackedStringArray:
	var scoped := headers.duplicate()
	var trimmed := token.strip_edges()
	# Refuse to attach anything that could break out of the header value.
	if trimmed.is_empty() or not StoreSecurity.is_safe_header_value(trimmed):
		return scoped
	scoped.append("Authorization: Bearer %s" % trimmed)
	return scoped

## Parses an `active_entitlements` response into `{ok, status, error, active}`.
## `active` holds one `{entitlement_id, expires_at_ms, source}` row per usable
## entitlement, already filtered against `now_ms` and capped. An entry whose
## expiry has already passed is never returned, so a stale cached body cannot
## resurrect a lapsed grant.
## Parses the consumable transaction list emitted by the native plugin (and any
## authority that speaks the same shape). Every row is a completed purchase, so
## there is nothing to expire: the ledger's transaction key is what makes a
## repeated read grant once and only once.
static func parse_non_subscription_transactions(status_code: int, body: String) -> Dictionary:
	var result := {"ok": false, "status": "", "error": "",
		"transactions": [] as Array[Dictionary]}
	if status_code != 200:
		result["error"] = "provider_error" if status_code >= 500 else "http_error"
		result["status"] = "http_%d" % status_code
		return result
	if body.length() > MAX_BODY_BYTES:
		result["error"] = "response_too_large"
		result["status"] = "http_200"
		return result
	var parsed := JSON.new()
	if parsed.parse(body) != OK:
		result["error"] = "malformed_response"
		result["status"] = "http_200"
		return result
	var payload: Variant = parsed.data
	if not payload is Dictionary:
		result["error"] = "malformed_response"
		result["status"] = "http_200"
		return result
	var items: Variant = (payload as Dictionary).get("items", null)
	if not items is Array:
		result["error"] = "malformed_response"
		result["status"] = "http_200"
		return result
	var transactions: Array[Dictionary] = []
	for raw in (items as Array):
		if transactions.size() >= MAX_TRANSACTIONS:
			break
		if not raw is Dictionary:
			continue
		var transaction_id := str((raw as Dictionary).get("transaction_id", "")).strip_edges()
		var product_id := str((raw as Dictionary).get("product_id", "")).strip_edges()
		if transaction_id.is_empty() or product_id.is_empty():
			continue
		var purchased_at := 0
		var raw_purchased: Variant = (raw as Dictionary).get("purchased_at", null)
		if raw_purchased is int or raw_purchased is float:
			purchased_at = int(raw_purchased)
		transactions.append({
			"transaction_id": transaction_id,
			"product_id": product_id,
			"purchased_at_ms": purchased_at,
			"source": "non_subscription_transactions",
		})
	result["ok"] = true
	result["status"] = "ok"
	result["transactions"] = transactions
	return result

## Parses the native plugin's purchase outcome into `{ok, status, error,
## product_id}`. A cancel is its own status rather than a failure, so the UI can
## stay quiet when the customer simply closed the sheet.
static func parse_purchase_result(status_code: int, body: String) -> Dictionary:
	var result := {"ok": false, "status": "error", "error": "purchase_failed",
		"product_id": ""}
	if status_code != 200:
		result["error"] = "provider_error" if status_code >= 500 else "http_error"
		result["status"] = "http_%d" % status_code
		return result
	if body.length() > MAX_BODY_BYTES:
		result["error"] = "response_too_large"
		return result
	var parsed := JSON.new()
	if parsed.parse(body) != OK:
		result["error"] = "malformed_response"
		return result
	var payload: Variant = parsed.data
	if not payload is Dictionary:
		result["error"] = "malformed_response"
		return result
	var data := payload as Dictionary
	result["product_id"] = str(data.get("product_id", "")).strip_edges()
	match str(data.get("status", "")).strip_edges().to_lower():
		"purchased":
			result["ok"] = true
			result["status"] = "purchased"
			result["error"] = ""
		"cancelled":
			result["status"] = "cancelled"
			result["error"] = "cancelled"
		_:
			var code := str(data.get("code", "")).strip_edges().to_lower()
			result["status"] = "error"
			result["error"] = code if not code.is_empty() else "purchase_failed"
	return result

static func parse_active_entitlements(status_code: int, body: String,
		now_ms: int = -1) -> Dictionary:
	var result := {"ok": false, "status": "", "error": "", "active": [] as Array[Dictionary]}
	if StoreSecurity.is_redirect(status_code):
		# A redirect is never followed and never interpreted as data: the bearer
		# header must not be replayed to wherever the response points.
		result["error"] = "redirect_refused"
		result["status"] = "http_%d" % status_code
		return result
	if status_code != 200:
		match status_code:
			401, 403:
				result["error"] = "unauthorized"
			404:
				result["error"] = "not_found"
			429:
				result["error"] = "rate_limited"
			_:
				result["error"] = "provider_error" if status_code >= 500 else "http_error"
		result["status"] = "http_%d" % status_code
		return result
	if body.length() > MAX_BODY_BYTES:
		result["error"] = "response_too_large"
		result["status"] = "http_200"
		return result
	var parsed := JSON.new()
	if parsed.parse(body) != OK:
		result["error"] = "malformed_response"
		result["status"] = "http_200"
		return result
	var payload: Variant = parsed.data
	if not payload is Dictionary:
		result["error"] = "malformed_response"
		result["status"] = "http_200"
		return result
	var items: Variant = (payload as Dictionary).get("items", null)
	if not items is Array:
		result["error"] = "malformed_response"
		result["status"] = "http_200"
		return result
	var cutoff := now_ms if now_ms >= 0 \
		else int(Time.get_unix_time_from_system() * 1000.0)
	var active: Array[Dictionary] = []
	for raw in (items as Array):
		if active.size() >= MAX_ENTITLEMENTS:
			break
		if not raw is Dictionary:
			continue
		var entitlement_id := str((raw as Dictionary).get("entitlement_id", "")).strip_edges()
		if entitlement_id.is_empty():
			continue
		var expiry := LIFETIME_EXPIRY_MS
		var raw_expiry: Variant = (raw as Dictionary).get("expires_at", null)
		if raw_expiry is int or raw_expiry is float:
			expiry = int(raw_expiry)
			# Only a null/absent expiry means lifetime. Any numeric expiry must
			# be in the future: 0 (the epoch), a past instant, or a nonsensical
			# value is lapsed and must never become a grant.
			if expiry <= cutoff:
				continue
		elif raw_expiry != null:
			# An unparseable expiry shape is not a grant either.
			continue
		active.append({"entitlement_id": entitlement_id, "expires_at_ms": expiry,
			"source": "active_entitlements"})
	result["ok"] = true
	result["status"] = "ok"
	result["active"] = active
	return result
