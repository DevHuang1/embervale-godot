extends SceneTree

const GAME_STATE_SCRIPT := preload("res://scripts/autoload/game_state.gd")
const STORE_SECURITY := preload("res://scripts/systems/store_security.gd")

func _initialize() -> void:
	var state := GAME_STATE_SCRIPT.new()
	state.record_activity("TEST EVENT")
	state.purchase_ledger.append({"id": "cosmetic_test", "kind": "cosmetic_trail",
		"price": 10, "currency": "diamonds"})
	state.purchase_ledger.append({
		"id": "ember_cache", "kind": "provider_embermarks", "price": 180,
		"currency": "diamonds", "provider": "revenuecat",
		"provider_record_id": "revenuecat:embermarks_cache:one_time",
		"provider_entitlement": "embermarks_cache", "provider_expires_at": -1})
	var payload: Dictionary = state.build_data_export()
	# A support diagnostic must never carry a credential or provider secret.
	var serialized := JSON.stringify(payload)
	if not STORE_SECURITY.find_secret_leaks(serialized).is_empty():
		push_error("Support export contains a secret-shaped value")
		quit(1)
		return
	var settings_source := FileAccess.get_file_as_string("res://scripts/ui/settings_menu.gd")
	if not settings_source.contains("local reset clears this device's progress only"):
		push_error("Settings does not explain local reset versus provider ownership")
		quit(1)
		return
	if str(payload.get("format", "")) != "embervale_support_export_v1":
		push_error("Export format marker missing")
		quit(1)
		return
	var entitlements: Dictionary = payload.get("entitlements", {})
	if not bool(entitlements.get("local_records_are_not_receipts", false)) \
			or str(entitlements.get("authority", "")) == "":
		push_error("Export did not distinguish local records from entitlements")
		quit(1)
		return
	var local: Dictionary = payload.get("local_progress", {})
	if not (local.get("activity_history", []) as Array).has("TEST EVENT"):
		push_error("Export omitted local activity history")
		quit(1)
	var coverage: Dictionary = payload.get("asset_coverage", {})
	if coverage.is_empty() or not coverage.has("unassigned_review_assets"):
		push_error("Export omitted downloaded-asset coverage classifications")
		quit(1)
	print("ALL DATA EXPORT TESTS PASSED")
	state.free()
	quit(0)
