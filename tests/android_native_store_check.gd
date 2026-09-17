extends Node

## QA-only scene for device verification of the RevenueCat NATIVE authority.
##
## It runs the real StoreManager refresh against the real Android plugin and
## prints one greppable verdict line, so `adb logcat` can prove the round trip
## without needing the game's HUD or a working GPU. Nothing here ships: the
## scene is only ever launched by an explicit QA export command line.

const TIMEOUT_SECONDS := 20.0

var _done := false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	var store := get_node_or_null("/root/StoreManager")
	if store == null:
		_finish("FAIL no_store_manager")
		return
	print("QA_NATIVE authority=%s available=%s" % [store.authority_name(), store.is_available()])
	if not store.is_available():
		_finish("FAIL store_unavailable")
		return
	var result: Dictionary = await store.refresh_and_claim()
	print("QA_NATIVE refresh ok=%s status=%s error=%s active=%s granted=%s skipped=%s diamonds=%s" % [
		result.get("ok", false), result.get("status", ""), result.get("error", ""),
		result.get("active", -1), result.get("granted", -1), result.get("skipped", -1),
		result.get("diamonds", -1)])
	_finish("OK" if bool(result.get("ok", false)) else "FAIL refresh")

func _finish(tag: String) -> void:
	if _done:
		return
	_done = true
	print("QA_NATIVE RESULT %s" % tag)
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()
