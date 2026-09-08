extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs := get_root().get_node_or_null("GameState") as GameState
	if gs == null:
		print("FAIL: GameState autoload missing")
		quit(1)
		return
	gs.scans_remaining = 0
	gs.scan_fragments = 9
	gs.add_scan_fragment()
	if gs.scans_remaining != 1 or gs.scan_fragments != 0:
		print("FAIL: ten fragments did not convert to one scan")
		quit(1)
		return
	gs.scans_remaining = gs.MAX_SCANS
	gs.scan_fragments = 9
	gs.add_scan_fragment()
	if gs.scans_remaining != gs.MAX_SCANS or gs.scan_fragments != 9:
		print("FAIL: capped scan inventory did not retain bounded fragments")
		quit(1)
		return
	print("ALL SCAN FRAGMENT TESTS PASSED")
	quit(0)
