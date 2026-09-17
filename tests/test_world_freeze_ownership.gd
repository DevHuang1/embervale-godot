extends SceneTree

## Every freeze-holding UI surface must balance its hold.
##
## Each menu freezes the world while it is open and releases it when it closes.
## This suite proves the open/close cycle and the teardown guarantee: a menu that
## is freed while still open (realm teardown, reload, low-memory recovery) must
## not leave the world paused behind it.
##
## Freeze state is global, so each menu starts from an asserted clean baseline.
## A leak is reported and cleared so one regression cannot cascade.

const MENUS: Array[String] = [
	"res://scenes/ui/diamond_shop.tscn",
	"res://scenes/ui/satchel.tscn",
	"res://scenes/ui/shop_menu.tscn",
	"res://scenes/ui/forge_menu.tscn",
	"res://scenes/ui/settings_menu.tscn",
	"res://scenes/ui/camp_menu.tscn",
	"res://scenes/ui/dungeon_select.tscn",
	"res://scenes/ui/stats_screen.tscn",
	"res://scenes/ui/quiz_menu.tscn",
]

var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs := get_root().get_node_or_null("GameState")
	if gs == null:
		_failures.append("GameState autoload is missing")
		_report()
		return
	for scene_path in MENUS:
		await _check_menu(scene_path, gs)
	_report()

func _check_menu(scene_path: String, gs: Node) -> void:
	var label := scene_path.get_file()
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_failures.append("%s could not be loaded" % label)
		return
	var menu := packed.instantiate() as CanvasLayer
	if menu == null:
		_failures.append("%s is not a CanvasLayer overlay" % label)
		return
	get_root().add_child(menu)
	await process_frame
	# Normalize before measuring: overlays must be authored hidden. If one starts
	# open it has already taken a hold, so close it and let the poll settle rather
	# than force-clearing state the menu legitimately owns.
	if menu.visible:
		_failures.append("%s is authored visible; overlays must start hidden" % label)
		menu.visible = false
		await _settle()
	if _freeze_count(gs) != 0:
		_failures.append("%s did not release the world while hidden (%d)"
			% [label, _freeze_count(gs)])
		_force_clear(gs)

	menu.visible = true
	await _settle()
	_assert_count(gs, label, 1, "freezes the world while open")

	menu.visible = false
	await _settle()
	_assert_count(gs, label, 0, "releases the world when closed")

	# Open again, then tear the menu down while it still holds its hold.
	menu.visible = true
	await _settle()
	_assert_count(gs, label, 1, "freezes the world on reopen")

	menu.free()
	await process_frame
	_assert_count(gs, label, 0, "releases the world when freed while open")

func _settle() -> void:
	await process_frame
	await process_frame

func _freeze_count(gs: Node) -> int:
	return int(gs.get("_ui_freeze_count"))

func _assert_count(gs: Node, label: String, expected: int, what: String) -> void:
	var actual := _freeze_count(gs)
	if actual != expected:
		_failures.append("%s did not correctly %s (freeze_count=%d, expected %d)"
			% [label, what, actual, expected])

func _force_clear(gs: Node) -> void:
	gs.set("_ui_freeze_count", 0)
	paused = false

func _report() -> void:
	if _failures.is_empty():
		print("WORLD FREEZE OWNERSHIP TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("WORLD FREEZE OWNERSHIP TESTS FAILED (%d)" % _failures.size())
	quit(1)
