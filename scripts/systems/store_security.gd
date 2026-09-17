extends RefCounted
class_name StoreSecurity

## === Store security policy (pure and headless-testable) ===
## One auditable place for every rule that decides whether a store URL may be
## opened, whether a credential may travel, and whether a persisted provider
## claim may be trusted. No HTTP, no autoloads, no key storage.
##
## Nothing in this file ever returns or prints a full credential: evidence is
## redacted, so a failing check can be reported without leaking the value.

## RevenueCat-hosted purchase surfaces. A custom domain must be added here
## deliberately; an unknown host is never opened. Both hosts are matched
## exactly, so a lookalike like `pay.rev.cat.evil.com` is not accepted.
const ALLOWED_FUNNEL_HOSTS: Array[String] = ["signup.cat", "pay.rev.cat"]
const ALLOWED_API_HOSTS: Array[String] = ["api.revenuecat.com"]

const REDIRECT_RANGE_START := 300
const REDIRECT_RANGE_END := 399
const MAX_URL_LENGTH := 2048
const MAX_PROJECT_ID_LENGTH := 255
const MAX_CUSTOMER_ID_LENGTH := 1500
const MIN_SECRET_LENGTH := 16
const MAX_HOST_LENGTH := 253

## The only code paths allowed to hold a provider secret are the editor and a
## debug export. A release export must never resolve a direct authority.
static func direct_authority_allowed(is_editor: bool, is_debug_build: bool) -> bool:
	return is_editor or is_debug_build

static func is_redirect(status_code: int) -> bool:
	return status_code >= REDIRECT_RANGE_START and status_code <= REDIRECT_RANGE_END

## Returns "" when the URL is safe to hand to `OS.shell_open` or an HTTP client,
## otherwise a stable error code. HTTPS only, no userinfo, no fragment, default
## port only, ASCII host, and an allow-listed host when a list is supplied.
static func validate_url(url: String, allowed_hosts: Array[String]) -> String:
	var trimmed := url.strip_edges()
	if trimmed.is_empty():
		return "empty_url"
	if trimmed.length() > MAX_URL_LENGTH:
		return "url_too_long"
	for index in trimmed.length():
		var code := trimmed.unicode_at(index)
		if code <= 32 or code == 127:
			return "url_control_chars"
	if not trimmed.begins_with("https://"):
		return "insecure_scheme"
	var rest := trimmed.substr("https://".length())
	if rest.contains("#"):
		return "url_fragment"
	if rest.contains("@"):
		return "url_userinfo"
	if rest.contains("?"):
		return "url_query"
	var authority := rest
	var slash := rest.find("/")
	if slash >= 0:
		authority = rest.substr(0, slash)
	if authority.is_empty():
		return "missing_host"
	var host := authority
	var colon := authority.find(":")
	if colon >= 0:
		host = authority.substr(0, colon)
		if authority.substr(colon + 1) != "443":
			return "non_default_port"
	if not _is_host_name(host, false):
		return "invalid_host"
	if not allowed_hosts.is_empty() and not _host_allowed(host, allowed_hosts):
		return "host_not_allowed"
	return ""

## The backend proxy is our own server, so it may be a bare host or a literal
## address, but it still must be HTTPS with no userinfo or non-default port.
static func validate_backend_url(url: String) -> String:
	var basic := validate_url(url, [])
	if basic == "host_not_allowed" or basic == "invalid_host":
		return _validate_loose_host(url)
	return basic

static func _validate_loose_host(url: String) -> String:
	var rest := url.strip_edges().substr("https://".length())
	var authority := rest
	var slash := rest.find("/")
	if slash >= 0:
		authority = rest.substr(0, slash)
	var host := authority
	var colon := authority.find(":")
	if colon >= 0:
		host = authority.substr(0, colon)
		if authority.substr(colon + 1) != "443":
			return "non_default_port"
	if _is_ipv4(host):
		return ""
	if not _is_host_name(host, true):
		return "invalid_host"
	return ""

static func validate_project_id(project_id: String) -> String:
	var trimmed := project_id.strip_edges()
	if trimmed.is_empty():
		return "empty_project_id"
	if trimmed.length() > MAX_PROJECT_ID_LENGTH:
		return "project_id_too_long"
	if not trimmed.begins_with("proj"):
		return "project_id_prefix"
	for index in trimmed.length():
		var code := trimmed.unicode_at(index)
		var alnum := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) \
			or (code >= 97 and code <= 122)
		if not alnum and code != 95 and code != 45:
			return "project_id_charset"
	return ""

## Customer ids travel as a URL path segment, so path separators and non
## printable characters are refused before they can reach a request.
static func validate_customer_id(customer_id: String) -> String:
	var trimmed := customer_id.strip_edges()
	if trimmed.is_empty():
		return "empty_customer_id"
	if trimmed.length() > MAX_CUSTOMER_ID_LENGTH:
		return "customer_id_too_long"
	for index in trimmed.length():
		var code := trimmed.unicode_at(index)
		if code < 33 or code > 126:
			return "customer_id_charset"
		if code == 47 or code == 92 or code == 37:
			return "customer_id_charset"
	return ""

## A plausible provider secret: long, prefixed, no header-breaking characters.
static func is_plausible_secret(value: String) -> bool:
	var trimmed := value.strip_edges()
	if trimmed.length() < MIN_SECRET_LENGTH:
		return false
	if not trimmed.begins_with("sk_"):
		return false
	return is_safe_header_value(trimmed)

## Header injection guard: printable ASCII with no spaces, CR, LF, or tab.
static func is_safe_header_value(value: String) -> bool:
	if value.is_empty():
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		if code < 33 or code > 126:
			return false
	return true

## Diagnostics-only rendering. Reveals the scheme marker and the last four
## characters, never enough to reconstruct the credential.
static func redact(value: String) -> String:
	var trimmed := value.strip_edges()
	if trimmed.is_empty():
		return ""
	var marker := "sk_" if trimmed.begins_with("sk_") else ""
	var tail := trimmed.substr(maxi(0, trimmed.length() - 4))
	return "%s***%s" % [marker, tail]

## Scans text for anything shaped like a provider secret or a bearer value.
## The returned evidence is redacted so a report cannot leak what it found.
static func find_secret_leaks(text: String) -> Array[String]:
	var leaks: Array[String] = []
	for pattern in ["\\bsk_[A-Za-z0-9_\\-]{16,}", "\\bBearer\\s+[A-Za-z0-9_\\-\\.]{16,}"]:
		var regex := RegEx.new()
		if regex.compile(pattern) != OK:
			continue
		for found in regex.search_all(text):
			leaks.append(redact(found.get_string().replace("Bearer ", "")))
	return leaks

## A persisted provider row is trusted only when it is internally consistent
## with the catalog: known entitlement, canonical record id, catalog amount.
## Tampering therefore cannot block or fabricate a legitimate claim.
static func validate_provider_row(row: Dictionary) -> String:
	if str(row.get("provider", "")) != "revenuecat":
		return "unknown_provider"
	var entitlement_id := str(row.get("provider_entitlement", "")).strip_edges()
	var tier := WebStoreCatalog.tier_for_entitlement(entitlement_id)
	if tier.is_empty():
		return "uncatalogued_entitlement"
	var expiry := int(row.get("provider_expires_at", -2))
	if str(row.get("provider_record_id", "")) \
			!= WebStoreCatalog.record_id_for(entitlement_id, expiry):
		return "record_id_mismatch"
	if str(row.get("currency", "")) != "diamonds":
		return "currency_mismatch"
	if int(row.get("price", 0)) != int(tier.get("diamonds", 0)) \
			or int(row.get("price", 0)) <= 0:
		return "amount_mismatch"
	if str(row.get("id", "")) != str(tier.get("id", "")):
		return "tier_id_mismatch"
	return ""

static func _host_allowed(host: String, allowed_hosts: Array[String]) -> bool:
	var lowered := host.to_lower()
	for allowed in allowed_hosts:
		if lowered == str(allowed).to_lower():
			return true
	return false

static func _is_host_name(host: String, allow_single_label: bool = false) -> bool:
	if host.is_empty() or host.length() > MAX_HOST_LENGTH:
		return false
	if host.begins_with(".") or host.ends_with(".") or host.contains(".."):
		return false
	var labels := host.split(".", false)
	if labels.size() < 2 and not allow_single_label:
		return false
	if labels.is_empty():
		return false
	for label in labels:
		if label.is_empty() or label.length() > 63:
			return false
		if label.begins_with("-") or label.ends_with("-"):
			return false
		for index in label.length():
			var code := label.unicode_at(index)
			var alnum := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) \
				or (code >= 97 and code <= 122)
			if not alnum and code != 45:
				return false
	return true

static func _is_ipv4(host: String) -> bool:
	var parts := host.split(".", false)
	if parts.size() != 4:
		return false
	for part in parts:
		if part.is_empty() or part.length() > 3:
			return false
		for index in part.length():
			var code := part.unicode_at(index)
			if code < 48 or code > 57:
				return false
		if int(part) > 255:
			return false
	return true
