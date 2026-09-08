extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs := get_root().get_node_or_null("GameState") as GameState
	var sm := get_root().get_node_or_null("ScanManager") as ScanManager
	if gs == null or sm == null:
		print("FAIL: required autoloads missing")
		quit(1)
		return
	gs.scans_remaining = 1
	var intents_before: int = gs.get_pending_cloud_intents().size()
	sm.is_scanning = false
	sm.start_scan()
	await process_frame
	if gs.scans_remaining != 0:
		print("FAIL: normal scan did not consume exactly one charge")
		quit(1)
		return
	if gs.get_pending_cloud_intents().size() <= intents_before:
		print("FAIL: scan consumption did not enqueue cloud intent")
		quit(1)
		return
	sm.is_scanning = false
	sm.start_scan()
	await process_frame
	if gs.scans_remaining != 0:
		print("FAIL: unavailable scan changed the charge")
		quit(1)
		return
	print("ALL SCAN ECONOMY TESTS PASSED")
	quit(0)
