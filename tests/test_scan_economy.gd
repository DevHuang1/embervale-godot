extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs = get_root().get_node_or_null("GameState")
	if gs == null:
		print("FAIL: GameState autoload missing")
		quit(1)
		return
	gs.save_path = "/tmp/embervale_scan_economy_test.cfg"
	gs.delete_save()
	gs.reset()
	gs.scans_remaining = 1
	var intents_before: int = gs.get_pending_cloud_intents().size()
	if not gs.consume_scan():
		print("FAIL: consume_scan refused with 1 left")
		quit(1)
		return
	if gs.scans_remaining != 0:
		print("FAIL: consume_scan did not spend exactly one charge")
		quit(1)
		return
	if gs.get_pending_cloud_intents().size() <= intents_before:
		print("FAIL: charge consumption did not enqueue cloud intent")
		quit(1)
		return
	if gs.consume_scan():
		print("FAIL: consume_scan succeeded at zero")
		quit(1)
		return
	if gs.scans_remaining != 0:
		print("FAIL: refused consume changed the charge")
		quit(1)
		return
	gs.delete_save()
	print("ALL SCAN ECONOMY TESTS PASSED")
	quit(0)
