extends SceneTree

## Regression suite for input that lands while a menu holds the world frozen.
##
## A menu pauses the tree, so the release of a movement key that was pressed
## before the menu opened used to be lost: the hero resumed walking on its own
## ("stick drift") until that key was pressed and released again. The manager
## now keeps observing while paused and rebuilds held state from the engine on
## resume, so the reported drift cannot come back.

const INPUT_MANAGER := preload("res://scripts/autoload/input_manager.gd")
const MOVEMENT_KEYS: Array[int] = [
	KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT,
]

var _failures: Array[String] = []
var _manager: Node = null
var _seen: Array[Vector2] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_manager = _resolve_manager()
	if _manager == null:
		push_error("InputManager is unavailable")
		quit(1)
		return
	_manager.move_input.connect(_on_move_input)
	await _test_release_over_an_open_menu_does_not_stick()
	await _test_still_held_key_keeps_moving_after_resume()
	await _test_gameplay_actions_stay_silent_while_paused()
	_clear_movement_keys()
	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		print("MENU INPUT RECOVERY TESTS FAILED (%d)" % _failures.size())
		quit(1)
		return
	print("MENU INPUT RECOVERY TESTS PASSED")
	quit(0)

func _test_release_over_an_open_menu_does_not_stick() -> void:
	_seen.clear()
	_press(KEY_W, true)
	await _settle()
	_check(_seen.size() > 0 and _seen[_seen.size() - 1].y < 0.0,
		"holding W must request forward movement")
	paused = true
	_press(KEY_W, false)
	await _settle()
	paused = false
	await _settle()
	_check(_seen[_seen.size() - 1] == Vector2.ZERO,
		"a key released while a menu froze the world must not leave the hero walking (got %s)"
			% _seen[_seen.size() - 1])

func _test_still_held_key_keeps_moving_after_resume() -> void:
	_seen.clear()
	_press(KEY_W, true)
	await _settle()
	paused = true
	await _settle()
	paused = false
	await _settle()
	_check(_seen.size() > 0 and _seen[_seen.size() - 1].y < 0.0,
		"a key still held when the menu closes must keep the hero moving")
	_press(KEY_W, false)
	await _settle()
	_check(_seen[_seen.size() - 1] == Vector2.ZERO,
		"releasing the key must stop movement")

func _test_gameplay_actions_stay_silent_while_paused() -> void:
	var fired: Array[String] = []
	var interact := func() -> void: fired.append("interact")
	var pause_toggle := func() -> void: fired.append("pause")
	_manager.interact_pressed.connect(interact)
	_manager.pause_pressed.connect(pause_toggle)
	var interact_key: int = _manager.get_key_binding("interact")
	var pause_key: int = _manager.get_key_binding("pause")
	paused = true
	_press(interact_key, true)
	_press(pause_key, true)
	await _settle()
	paused = false
	await _settle()
	_check(fired.is_empty(),
		"gameplay actions must not fire while a menu holds the world frozen (got %s)" % str(fired))
	_press(interact_key, false)
	_press(pause_key, false)
	await _settle()
	_manager.interact_pressed.disconnect(interact)
	_manager.pause_pressed.disconnect(pause_toggle)

func _resolve_manager() -> Node:
	var existing := root.get_node_or_null("InputManager")
	if existing != null:
		return existing
	var manager: Node = INPUT_MANAGER.new()
	manager.name = "InputManager"
	root.add_child(manager)
	return manager

func _on_move_input(direction: Vector2) -> void:
	_seen.append(direction)

func _press(keycode: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)

func _clear_movement_keys() -> void:
	for keycode in MOVEMENT_KEYS:
		_press(keycode, false)

func _settle() -> void:
	await process_frame
	await process_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
