extends Node

var _failures: Array[String] = []
var _passes := 0

func _ready() -> void:
    await _run_validation()
    print("=== Elemental Status Validation ===")
    print("passes=", _passes, " failures=", _failures.size())
    for failure in _failures:
        print("FAILURE: ", failure)
    get_tree().quit(1 if not _failures.is_empty() else 0)

func _run_validation() -> void:
    var enemy_scene := load("res://scenes/entities/hushling.tscn") as PackedScene
    _assert_true(enemy_scene != null, "Hushling scene loads for status testing")
    if enemy_scene == null:
        return
    var enemy := enemy_scene.instantiate()
    add_child(enemy)
    await get_tree().process_frame
    _assert_true(enemy.has_method("apply_elemental_status"), "enemy exposes elemental status application")
    _assert_true(enemy.get_node_or_null("ElementalStatus") != null, "enemy owns a local status controller")

    enemy.apply_elemental_status("fire", 1)
    await get_tree().process_frame
    var statuses: Dictionary = enemy.get_elemental_status_snapshot()
    _assert_true(statuses.get("fire", 0) == 1, "fire status applies one stack")
    await get_tree().create_timer(0.86).timeout
    _assert_true(int(enemy.hp) == 26, "burn deals its first timed damage tick")

    enemy.apply_elemental_status("frost", 1)
    await get_tree().process_frame
    statuses = enemy.get_elemental_status_snapshot()
    _assert_true(statuses.has("frost") and not statuses.has("fire"), "frost cancels an active burn")
    var status_controller := enemy.get_node("ElementalStatus")
    _assert_true(status_controller.movement_multiplier() < 0.7, "frost slows enemy movement")

    enemy.apply_elemental_status("fire", 1)
    await get_tree().process_frame
    statuses = enemy.get_elemental_status_snapshot()
    _assert_true(statuses.has("fire") and not statuses.has("frost"), "fire cancels an active frost")
    var reaction_found := false
    for label in get_tree().current_scene.find_children("*", "Label3D", true, false):
        if label is Label3D and (label as Label3D).text == "MELT":
            reaction_found = true
            break
    _assert_true(reaction_found, "fire and frost create a visible MELT reaction")

    enemy.apply_elemental_status("fire", 4)
    await get_tree().process_frame
    statuses = enemy.get_elemental_status_snapshot()
    _assert_true(statuses.get("fire", 0) == 3, "fire stacks remain capped at three")

    enemy.apply_elemental_status("nature", 1)
    enemy.apply_elemental_status("shock", 1)
    await get_tree().process_frame
    _assert_true(enemy.get_elemental_status_snapshot().size() <= 2, "active status count remains bounded")
    enemy.queue_free()
    await get_tree().process_frame

func _assert_true(condition: bool, message: String) -> void:
    if condition:
        _passes += 1
        print("PASS: ", message)
    else:
        _failures.append(message)
        push_error("FAIL: " + message)
