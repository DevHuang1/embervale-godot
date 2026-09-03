extends Node

var _failures: Array[String] = []
var _passes := 0

func _ready() -> void:
    await _run_validation()
    print("=== Enemy Health Bar Validation ===")
    print("passes=", _passes, " failures=", _failures.size())
    for failure in _failures:
        print("FAILURE: ", failure)
    get_tree().quit(1 if not _failures.is_empty() else 0)

func _run_validation() -> void:
    _assert_true(GameState.MAX_HP_BASE == 100, "Hero base HP constant is 100")
    GameState.reset()
    _assert_true(GameState.max_hp == 100 and GameState.hp == 100, "Hero starts at 100 / 100 HP")
    var enemy_scene := load("res://scenes/entities/hushling.tscn") as PackedScene
    _assert_true(enemy_scene != null, "Hushling scene loads")
    if enemy_scene == null:
        return
    var enemy := enemy_scene.instantiate()
    add_child(enemy)
    await get_tree().process_frame
    var bar := enemy.get_node_or_null("EnemyHealthBar") as EnemyHealthBar
    _assert_true(bar != null, "Hushling receives a floating health bar")
    if bar == null:
        enemy.queue_free()
        return
    var fill := bar.get_node_or_null("HealthPlate/HealthFill") as MeshInstance3D
    var hp_label := bar.get_node_or_null("HealthPlate/EnemyHP") as Label3D
    var lock_sigil := bar.get_node_or_null("HealthPlate/LockFrame") as MeshInstance3D
    _assert_true(fill != null, "health bar has a fill mesh")
    _assert_true(hp_label != null, "health bar shows numeric HP")
    _assert_true(lock_sigil != null, "health bar has a lantern lock sigil")
    if lock_sigil != null:
        _assert_true(lock_sigil.mesh is ArrayMesh and not lock_sigil.mesh is QuadMesh,
            "lantern mark uses ring geometry instead of a square quad")
        GameState.engage_enemy(enemy)
        await get_tree().process_frame
        _assert_true(lock_sigil.visible, "lantern ring appears on the marked enemy")
    if hp_label != null:
        _assert_true(hp_label.text == "28 / 28", "new enemy bar starts at the enemy max HP")
    enemy.take_damage(7, Vector3.ZERO)
    await get_tree().process_frame
    _assert_true(int(enemy.hp) == 21, "enemy HP decreases normally")
    if fill != null:
        _assert_true(fill.scale.x < 0.80, "bar fill visibly reflects HP loss")
    if hp_label != null:
        _assert_true(hp_label.text == "21 / 28", "numeric HP reflects damage")
    var damage_number_found := false
    for label in get_tree().current_scene.find_children("*", "Label3D", true, false):
        if label is Label3D and (label as Label3D).text == "7":
            damage_number_found = true
            break
    _assert_true(damage_number_found, "damage number pops above the wounded enemy")
    FloatingText.spawn_damage_on_entity(enemy, 21, true)
    await get_tree().process_frame
    var critical_number_found := false
    for label in get_tree().current_scene.find_children("*", "Label3D", true, false):
        if label is Label3D and (label as Label3D).text == "CRIT 21":
            critical_number_found = true
            _assert_true((label as Label3D).font_size <= 70,
                "critical popup typography stays compact")
            break
    _assert_true(critical_number_found, "critical damage uses the emphasized damage style")
    enemy.take_damage(100, Vector3.ZERO)
    await get_tree().process_frame
    _assert_true(not bar.visible, "floating bar hides when the enemy is defeated")
    enemy.queue_free()
    await get_tree().process_frame

func _assert_true(condition: bool, message: String) -> void:
    if condition:
        _passes += 1
        print("PASS: ", message)
    else:
        _failures.append(message)
        push_error("FAIL: " + message)
