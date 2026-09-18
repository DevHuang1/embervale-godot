extends Node

## Owns realm and scene transitions.
##
## A travel used to call change_scene_to_file() directly, which froze the frame
## while the whole realm loaded. Instead the overlay is shown first and the
## target scene streams in on a worker thread, so the bar and tips keep drawing;
## the swap happens in one frame once the scene is ready. Headless runs (tests,
## QA scenes) take the same path, so the contract is identical everywhere.
##
## Every request is idempotent while in flight: a second travel() is refused, so
## a gate touched twice or a menu clicked twice cannot double-load or leave the
## overlay behind.

signal transition_started(scene_path: String, title: String)
signal transition_finished(scene_path: String)

const LOADING_SCREEN := preload("res://scripts/ui/loading_screen.gd")

## Scene base name -> (display title, tip realm id). Anything unlisted travels
## under its file name with the general tip pool.
const DESTINATIONS := {
	"main": {"title": "Embervale", "realm": ""},
	"grove": {"title": "Entering Bramblewood", "realm": "bramblewood"},
	"moonfen": {"title": "Entering Moonfen", "realm": "moonfen"},
	"whispergrove": {"title": "Entering Whispergrove", "realm": "whispergrove"},
	"mistfen": {"title": "Entering Mistfen", "realm": "mistfen"},
	"heartwood": {"title": "Entering Heartwood", "realm": "heartwood"},
}

var _active: bool = false
var _pending_path: String = ""
var _screen: LoadingScreen = null
var _phase: String = ""

func _ready() -> void:
	# The overlay must keep animating while a menu holds the world frozen.
	process_mode = Node.PROCESS_MODE_ALWAYS

func is_transitioning() -> bool:
	return _active

func pending_path() -> String:
	return _pending_path

func loading_screen() -> LoadingScreen:
	return _screen

## Starts a transition. Returns false when the request was refused (already
## traveling, empty path, or a scene that does not exist).
func travel(scene_path: String, title: String = "") -> bool:
	if _active:
		return false
	var path := scene_path.strip_edges()
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("SceneLoader: refusing to travel to missing scene '%s'" % scene_path)
		return false
	_active = true
	_pending_path = path
	_phase = ""
	var info := destination_info(path)
	var resolved_title := title if not title.is_empty() else str(info["title"])
	_show_screen(resolved_title, str(info["realm"]))
	transition_started.emit(path, resolved_title)
	var err := ResourceLoader.load_threaded_request(path, "PackedScene")
	if err != OK:
		return _finish_with_direct_load("threaded request refused (error %d)" % err)
	return true

func destination_info(scene_path: String) -> Dictionary:
	var key := scene_path.get_file().get_basename().to_lower()
	if DESTINATIONS.has(key):
		return (DESTINATIONS[key] as Dictionary).duplicate(true)
	return {"title": key.capitalize(), "realm": ""}

func _process(_delta: float) -> void:
	if not _active or _pending_path.is_empty():
		return
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_pending_path, progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var ratio := 0.0
			if progress.size() > 0:
				ratio = float(progress[0])
			_report(ratio)
		ResourceLoader.THREAD_LOAD_LOADED:
			_complete()
		_:
			_finish_with_direct_load("threaded load failed")

func _complete() -> void:
	var packed := ResourceLoader.load_threaded_get(_pending_path) as PackedScene
	if packed == null:
		_finish_with_direct_load("threaded load returned no scene")
		return
	_report(1.0)
	_swap(packed)

func _finish_with_direct_load(reason: String) -> bool:
	## Fallback keeps the player moving: a load that cannot stream still swaps in
	## the same frame it finishes, and the overlay is always retired.
	var packed := ResourceLoader.load(_pending_path, "PackedScene") as PackedScene
	if packed == null:
		push_error("SceneLoader: %s and the direct load of '%s' failed" % [reason, _pending_path])
		_retire_screen()
		_active = false
		_pending_path = ""
		return false
	_report(1.0)
	_swap(packed)
	return true

func _swap(packed: PackedScene) -> void:
	var tree := get_tree()
	var finished := _pending_path
	if tree == null:
		_active = false
		_pending_path = ""
		return
	var err := tree.change_scene_to_packed(packed)
	if err != OK:
		push_error("SceneLoader: change_scene_to_packed failed (error %d) for '%s'" % [err, finished])
	_retire_screen()
	_active = false
	_pending_path = ""
	transition_finished.emit(finished)

func _show_screen(title: String, realm_id: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	if _screen != null and is_instance_valid(_screen):
		_screen.finish()
	_screen = LOADING_SCREEN.new()
	_screen.name = "LoadingScreen"
	tree.root.add_child(_screen)
	_screen.begin(title, realm_id)

func _retire_screen() -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen.finish()
	_screen = null

func _report(ratio: float) -> void:
	if _screen == null or not is_instance_valid(_screen):
		return
	_screen.set_progress(ratio)
	var phase := phase_for(ratio)
	if phase != _phase:
		_phase = phase
		_screen.set_status(phase)

## The status line names what the load is doing instead of sitting on one word
## for the whole wait.
func phase_for(ratio: float) -> String:
	if ratio <= 0.0:
		return "Preparing…"
	if ratio < 0.6:
		return "Streaming terrain…"
	if ratio < 1.0:
		return "Building the realm…"
	return "Ready"
