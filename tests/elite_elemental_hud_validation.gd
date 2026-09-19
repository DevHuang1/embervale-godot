extends Node

var _failures: Array[String] = []
var _passes := 0

func _ready() -> void:
    await _run_validation()
    print("=== Elite + Elemental HUD Validation ===")
    print("passes=", _passes, " failures=", _failures.size())
    for failure in _failures:
        print("FAILURE: ", failure)
    get_tree().quit(1 if not _failures.is_empty() else 0)

func _run_validation() -> void:
    GameState.reset()
    var hud_scene := load("res://scenes/ui/hud.tscn") as PackedScene
    var elite_scene := load("res://scenes/entities/elite_hushling.tscn") as PackedScene
    var hushling_scene := load("res://scenes/entities/hushling.tscn") as PackedScene
    _assert_true(hud_scene != null, "HUD scene loads")
    _assert_true(elite_scene != null, "elite scene loads")
    _assert_true(hushling_scene != null, "regular enemy scene loads")
    if hud_scene == null or elite_scene == null or hushling_scene == null:
        return

    var hud := hud_scene.instantiate()
    add_child(hud)
    var elite := elite_scene.instantiate()
    elite.name = "EliteEmberWarden_Test"
    add_child(elite)
    elite.global_position = Vector3.ZERO
    var nearby := hushling_scene.instantiate()
    nearby.name = "NearbyHushling_Test"
    add_child(nearby)
    nearby.global_position = Vector3(2.0, 0.0, 0.0)
    await get_tree().process_frame

    var elemental_hud := hud.get_node_or_null("Root/CombatCard/CombatVBox/ElementalHud")
    _assert_true(elemental_hud != null, "HUD builds the elemental indicator")
    hud.show_combat_card(elite)
    GameState.enemy_target = elite
    elite.apply_elemental_status("shock", 1)
    await get_tree().process_frame
    await get_tree().process_frame
    if elemental_hud != null:
        var weapon_label: Label = elemental_hud.find_child("WeaponElement", true, false) as Label
        var target_label: Label = elemental_hud.get_node_or_null("TargetBuildup")
        _assert_true(weapon_label != null and weapon_label.text.contains("FIRE"), "HUD shows the default weapon element")
        _assert_true(target_label != null and target_label.text.contains("BUILDUP"), "HUD labels targeted elemental buildup")
        var meters := elemental_hud.get_node_or_null("BuildupMeters")
        var shock_value := -1.0
        if meters != null:
            # Each buildup row is icon + name + meter + value; find them by type
            # so adding presentation to a row never invalidates the reading.
            for row in meters.get_children():
                var row_label := ""
                var row_meter: ProgressBar = null
                for child in row.get_children():
                    if child is ProgressBar:
                        row_meter = child as ProgressBar
                    elif child is Label and row_label.is_empty():
                        row_label = (child as Label).text
                if row_label.contains("SHOCK") and row_meter != null:
                    shock_value = row_meter.value
        _assert_true(shock_value == 1.0, "HUD shows one Shock buildup stack")
        _assert_true(target_label != null and target_label.text.contains("IMMUNE FIRE,NATURE"), "HUD shows elite immunities")

    elite.apply_elemental_status("fire", 1)
    await get_tree().process_frame
    _assert_true(not elite.get_elemental_status_snapshot().has("fire"), "elite rejects Fire status")
    var nearby_hp := int(nearby.hp)
    elite.take_damage(999, Vector3.ZERO)
    await get_tree().process_frame
    _assert_true(int(nearby.hp) == nearby_hp - 8, "elite defeat damages nearby enemies")
    _assert_true(nearby.get_elemental_status_snapshot().has("shock"), "elite defeat applies chain Shock")
    _assert_true(not elite.get_elemental_status_snapshot().has("fire"), "elite remains Fire-immune")
    GameState.enemy_target = null
    hud.queue_free()
    elite.queue_free()
    nearby.queue_free()
    await get_tree().process_frame

func _assert_true(condition: bool, message: String) -> void:
    if condition:
        _passes += 1
        print("PASS: ", message)
    else:
        _failures.append(message)
        push_error("FAIL: " + message)
