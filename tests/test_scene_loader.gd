extends SceneTree

## Contract suite for the realm-transition loading screen.
##
## The transition used to freeze the frame while the realm loaded. What is
## verified here is the replacement contract: the overlay appears before the
## load, the bar only moves forward, tips rotate and stay realm-aware, a second
## travel while one is in flight is refused, and the overlay is always retired
## whether the load streams, falls back, or the target does not exist.

const TIPS := preload("res://scripts/systems/loading_tips_catalog.gd")
const SCREEN := preload("res://scripts/ui/loading_screen.gd")

const TARGET := "res://scenes/world/mistfen.tscn"
const TARGET_BIOME := "mistfen"
const MISSING := "res://scenes/world/not_a_real_realm.tscn"
const MAX_WAIT_FRAMES := 1200

var _failures: Array[String] = []
var _loader: Node = null

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_loader = root.get_node_or_null("SceneLoader")
	if _loader == null:
		push_error("SceneLoader autoload is missing")
		quit(1)
		return
	_test_tips_are_realm_aware_and_deterministic()
	_test_destination_titles()
	await _test_screen_progress_is_monotonic()
	await _test_tips_rotate()
	await _test_screen_finish_frees_the_layer()
	await _test_travel_refuses_a_second_request_and_retires_the_overlay()
	_test_missing_scene_is_refused()
	await _settle_world()
	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		print("SCENE LOADER TESTS FAILED (%d)" % _failures.size())
		quit(1)
		return
	print("SCENE LOADER TESTS PASSED")
	quit(0)

func _test_tips_are_realm_aware_and_deterministic() -> void:
	for realm in ["whispergrove", "bramblewood", "mistfen", "heartwood", "moonfen"]:
		var tips := TIPS.tips_for(realm)
		_check(tips.size() > TIPS.GENERAL_TIPS.size(),
			"%s must lead with realm advice before the general pool" % realm)
		_check(str(tips[0]) == str(TIPS.REALM_TIPS[realm][0]),
			"%s must open with its own first tip" % realm)
	var first := TIPS.tip_at("moonfen", 0)
	_check(first == TIPS.tip_at("moonfen", 0), "the tip order must be deterministic")
	_check(TIPS.tip_at("moonfen", TIPS.tips_for("moonfen").size()) == first,
		"the tip rotation must wrap instead of running out")
	_check(TIPS.tips_for("unknown_realm").size() == TIPS.GENERAL_TIPS.size(),
		"an unknown realm must still get the general pool")

func _test_destination_titles() -> void:
	var moonfen: Dictionary = _loader.destination_info("res://scenes/world/moonfen.tscn")
	_check(str(moonfen["title"]) == "Moonfen" and str(moonfen["realm"]) == "moonfen",
		"a realm scene must resolve its own title and tip pool (got %s)" % str(moonfen))
	var grove: Dictionary = _loader.destination_info("res://scenes/world/grove.tscn")
	_check(str(grove["realm"]) == "bramblewood",
		"the grove scene is Bramblewood for the player, not 'Grove' (got %s)" % str(grove))
	var unknown: Dictionary = _loader.destination_info("res://scenes/world/other.tscn")
	_check(str(unknown["title"]) == "Other" and str(unknown["realm"]) == "",
		"an unmapped scene must fall back to its file name and the general pool")

func _test_screen_progress_is_monotonic() -> void:
	var screen := _new_screen()
	_check(screen.progress() == 0.0, "a fresh overlay must start at zero")
	screen.set_progress(0.4)
	_check(is_equal_approx(screen.progress(), 0.4), "progress must follow the reported ratio")
	screen.set_progress(0.2)
	_check(is_equal_approx(screen.progress(), 0.4), "progress must never move backwards")
	screen.set_progress(4.0)
	_check(is_equal_approx(screen.progress(), 1.0), "progress must clamp to one")
	screen.set_progress(-3.0)
	_check(is_equal_approx(screen.progress(), 1.0), "a negative ratio must not rewind a finished bar")
	await _retire(screen)

func _test_tips_rotate() -> void:
	var screen := _new_screen("mistfen")
	_check(screen.tip_count() > 0, "a realm must offer at least one tip")
	_check(screen.current_tip() == TIPS.tip_at("mistfen", 0),
		"the overlay must open on the realm's first tip")
	var first: String = screen.current_tip()
	await _wait_seconds(SCREEN.TIP_INTERVAL_SECONDS + SCREEN.TIP_FADE_SECONDS * 2.0 + 0.4)
	_check(screen.current_tip() != first,
		"tips must rotate while the realm loads (still '%s')" % screen.current_tip())
	await _retire(screen)

func _test_screen_finish_frees_the_layer() -> void:
	var screen := _new_screen()
	screen.finish()
	screen.finish()
	await _wait_seconds(SCREEN.HARD_FREE_SECONDS + 0.3)
	_check(not screen.is_inside_tree(),
		"finish() must retire the overlay even when it is called twice")

func _test_travel_refuses_a_second_request_and_retires_the_overlay() -> void:
	_check(not _loader.is_transitioning(), "the loader must start idle")
	_check(_loader.travel(TARGET), "traveling to a real realm must be accepted")
	_check(_loader.is_transitioning(), "the loader must report a transition in flight")
	_check(_loader.travel(TARGET) == false,
		"a second travel while one is in flight must be refused")
	var screen: Node = _loader.loading_screen()
	_check(screen != null and screen.is_inside_tree(),
		"the loading overlay must be on screen while the realm streams in")
	var peak := 0.0
	var frames := 0
	while _loader.is_transitioning() and frames < MAX_WAIT_FRAMES:
		if screen != null and is_instance_valid(screen):
			peak = maxf(peak, float(screen.progress()))
		await process_frame
		frames += 1
	_check(not _loader.is_transitioning(),
		"the transition must complete (still traveling after %d frames)" % frames)
	_check(peak > 0.0, "the bar must move while the realm loads (peak %.2f)" % peak)
	_check(_loader.loading_screen() == null, "the overlay must be retired after the swap")
	_check(await _wait_until_overlay_gone(),
		"the retired overlay must leave the tree instead of lingering above the new realm")
	var scene := current_scene
	_check(scene != null and str(scene.get("biome_id")) == TARGET_BIOME,
		"the swap must land on the requested realm (got %s)" % (scene.name if scene != null else "<none>"))
	_check(not _loader.travel(MISSING), "a missing scene must never be accepted")

func _test_missing_scene_is_refused() -> void:
	_check(not _loader.travel(MISSING), "a missing scene must be refused")
	_check(not _loader.is_transitioning(), "a refused travel must not leave a transition pending")
	_check(_loader.loading_screen() == null, "a refused travel must not leave an overlay behind")

func _new_screen(realm_id: String = "") -> Node:
	var screen: Node = SCREEN.new()
	screen.name = "TestLoadingScreen"
	root.add_child(screen)
	screen.begin("Test Realm", realm_id)
	return screen

## The travel target is a real realm. Give its deferred setup a few frames to
## finish, then drop it, so the suite does not report the world's own internals
## as objects leaked by this feature.
func _settle_world() -> void:
	await _wait_frames(40)

func _retire(screen: Node) -> void:
	screen.finish()
	await _wait_seconds(SCREEN.FINISH_FADE_SECONDS + 0.25)
	_check(not screen.is_inside_tree(), "finish() must retire the overlay")

func _wait_until_overlay_gone() -> bool:
	var deadline := Time.get_ticks_msec() + 1500
	while Time.get_ticks_msec() < deadline:
		if root.get_node_or_null("LoadingScreen") == null:
			return true
		await process_frame
	return false

func _wait_frames(count: int) -> void:
	for _i in count:
		await process_frame

func _wait_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
