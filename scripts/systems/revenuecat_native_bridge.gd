extends RefCounted
class_name RevenueCatNativeBridge

## === RevenueCat Android SDK bridge — read-only entitlement source ===
##
## The native plugin owns the purchase-free half of RevenueCat: it configures
## the SDK with the PUBLIC SDK key and reports which entitlements the customer
## owns. Money never moves here — checkout happens on the hosted RevenueCat
## funnel — so this class only reads ownership back for StoreManager to claim
## exactly once, and no provider secret ever reaches the device.
##
## Every method degrades to a typed no-op result when the Android singleton is
## absent (desktop, editor, headless suites), so the game and its tests run
## unchanged on non-Android targets.

const API_CLIENT := preload("res://scripts/systems/revenuecat_api_client.gd")

const PLUGIN_NAME := "RevenueCatBridge"
const SIGNAL_ACTIVE_ENTITLEMENTS := "active_entitlements"
const SIGNAL_ERROR := "customer_info_error"

## The plugin's own await budget; StoreManager adds no second timeout.
const REQUEST_TIMEOUT_SECONDS := 15.0

var _singleton: Object = null
var _pending := false
var _payload := ""
var _error := ""
var _error_status := ""

## `singleton_override` exists for headless suites: they inject a fake with the
## same signals and methods, so every branch is testable without Android.
func _init(singleton_override: Object = null) -> void:
	if singleton_override != null:
		_singleton = singleton_override
	elif Engine.has_singleton(PLUGIN_NAME):
		_singleton = Engine.get_singleton(PLUGIN_NAME)
	if _singleton == null:
		return
	_singleton.connect(SIGNAL_ACTIVE_ENTITLEMENTS, _on_active_entitlements)
	_singleton.connect(SIGNAL_ERROR, _on_error)

func is_available() -> bool:
	return _singleton != null

## Configures the SDK once, with the stable device customer id as the App User
## ID. The same id is appended to the hosted funnel URL, so a web purchase and
## this reader always describe the same customer.
func configure(api_key: String, app_user_id: String) -> bool:
	if _singleton == null:
		return false
	var key := api_key.strip_edges()
	if key.is_empty():
		return false
	_singleton.configure(key, app_user_id.strip_edges())
	return true

func log_in(app_user_id: String) -> bool:
	if _singleton == null:
		return false
	var trimmed := app_user_id.strip_edges()
	if trimmed.is_empty():
		return false
	_singleton.logIn(trimmed)
	return true

func log_out() -> bool:
	if _singleton == null:
		return false
	_singleton.logOut()
	return true

## Reads the customer's active entitlements, awaiting the plugin's callback.
## Returns the same `{ok, status, error, active}` contract as the REST client,
## so StoreManager treats every authority identically.
func fetch_active_entitlements() -> Dictionary:
	if _singleton == null:
		return _failure("unavailable", "native_bridge_unavailable")
	# The plugin queues a read that arrives before the SDK is configured, so no
	# client-side wait is needed here; the request timeout covers the whole call.
	_pending = true
	_payload = ""
	_error = ""
	_error_status = ""
	_singleton.getActiveEntitlements()
	await _wait_for_response()
	if _pending:
		_pending = false
		return _failure("timeout", "native_timeout")
	if not _error.is_empty():
		return _failure(_error_status, _error)
	return API_CLIENT.parse_active_entitlements(200, _payload)

func _wait_for_response() -> void:
	var deadline := Time.get_ticks_msec() + int(REQUEST_TIMEOUT_SECONDS * 1000.0)
	while _pending and Time.get_ticks_msec() < deadline:
		var loop := Engine.get_main_loop() as SceneTree
		if loop == null:
			return
		await loop.process_frame

func _on_active_entitlements(payload: String) -> void:
	_payload = payload
	_pending = false

func _on_error(code: String, message: String) -> void:
	var status := _status_for_code(code)
	_error_status = status
	_error = "offline" if status == "offline" else code.to_lower()
	push_warning("RevenueCatNativeBridge: %s — %s" % [code, message])
	_pending = false

## Maps the SDK's error codes onto the vocabulary the store UI already speaks.
func _status_for_code(code: String) -> String:
	match code.to_upper():
		"NETWORK_ERROR", "OFFLINE_CONNECTION_ERROR":
			return "offline"
		"NOT_CONFIGURED":
			return "unconfigured"
		"INVALID_CREDENTIALS_ERROR", "INVALID_SUBSCRIBER_ATTRIBUTES_ERROR":
			return "unauthorized"
		_:
			return "provider_error"

func _failure(status: String, error: String) -> Dictionary:
	return {"ok": false, "status": status, "error": error, "active": [] as Array[Dictionary]}
