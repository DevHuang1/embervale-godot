extends SceneTree

## Guards the Glintmonger's Case entry point.
##
## The diamond shop existed as an orphaned scene for a while: nothing instanced
## it and the HUD button that should open it was deliberately hidden. This suite
## fails if either half of that wiring regresses.

const SHOP_SCENE := "res://scenes/ui/diamond_shop.tscn"
const WORLD_SCENES: Array[String] = [
	"res://scenes/world/grove.tscn",
	"res://scenes/world/moonfen.tscn",
]
## Every path the shop script resolves with @onready or get_node.
const REQUIRED_PATHS: Array[String] = [
	"Root/Panel/VBox/Header/DiamondsLabel",
	"Root/Panel/VBox/Scroll/ItemsVBox",
	"Root/Panel/VBox/Message",
	"Root/Panel/VBox/Footer/Close",
	"Root/Panel/VBox/Footer/UnequipAll",
]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures: Array[String] = []
	_check_scene_loads(failures)
	_check_hud_wiring(failures)
	_check_world_instances(failures)
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		print("GLINT ENTRY POINT TESTS FAILED (%d)" % failures.size())
		quit(1)
		return
	print("GLINT ENTRY POINT TESTS PASSED")
	quit(0)

func _check_scene_loads(failures: Array[String]) -> void:
	var packed := load(SHOP_SCENE) as PackedScene
	if packed == null:
		failures.append("The diamond shop scene must load: %s" % SHOP_SCENE)
		return
	var shop := packed.instantiate()
	if shop == null:
		failures.append("The diamond shop scene must instantiate")
		return
	for path in REQUIRED_PATHS:
		if shop.get_node_or_null(path) == null:
			failures.append("The diamond shop is missing node path: %s" % path)
	# Every $Path the script resolves must exist in the scene. A reparented scene
	# silently nulls the script's @onready refs otherwise, which no path list
	# kept in a separate file can catch.
	for path in _script_node_paths():
		if shop.get_node_or_null(path) == null:
			failures.append("The shop script resolves a missing node path: %s" % path)
	if not shop.has_method("open"):
		failures.append("The diamond shop must expose an open() entry point")
	shop.free()

## Pulls every `$Root/...` node path out of the shop script.
func _script_node_paths() -> Array[String]:
	var source := FileAccess.get_file_as_string("res://scripts/ui/diamond_shop.gd")
	var paths: Array[String] = []
	var regex := RegEx.new()
	regex.compile("\\$([A-Za-z0-9_]+(?:/[A-Za-z0-9_]+)+)")
	for found in regex.search_all(source):
		var path := found.get_string(1)
		if not paths.has(path):
			paths.append(path)
	return paths

func _check_hud_wiring(failures: Array[String]) -> void:
	var hud := FileAccess.get_file_as_string("res://scripts/ui/hud.gd")
	if not hud.contains("glint_button.pressed.connect(_on_glint_pressed)"):
		failures.append("The HUD GLINT button must be wired to the diamond shop")
	if not hud.contains("find_child(\"DiamondShop\""):
		failures.append("The HUD must resolve the diamond shop from the world scene")
	if not hud.contains("_update_glint_visibility"):
		failures.append("The HUD must gate the GLINT button on the shop being present")
	if hud.contains("glint_button.visible = false\n"):
		failures.append("The HUD must not unconditionally hide the GLINT button")

func _check_world_instances(failures: Array[String]) -> void:
	for scene_path in WORLD_SCENES:
		var text := FileAccess.get_file_as_string(scene_path)
		if not text.contains(SHOP_SCENE):
			failures.append("%s must instance the diamond shop" % scene_path)
		if not text.contains('name="DiamondShop"'):
			failures.append("%s must name the instance 'DiamondShop'" % scene_path)
