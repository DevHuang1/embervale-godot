extends Node

var _failures: Array[String] = []
var _frames := 0
var _hero: CharacterBody3D
var _world: Node

func _ready() -> void:
    var scene := load("res://scenes/world/grove.tscn") as PackedScene
    if scene == null:
        _failures.append("Grove scene failed to load")
        _finish()
        return
    _world = scene.instantiate()
    add_child(_world)
    await get_tree().process_frame
    await get_tree().process_frame
    _hero = _world.find_child("Hero", true, false) as CharacterBody3D
    if _hero == null:
        _failures.append("Grove Hero was not found")
        _finish()
        return
    var camera = _world.find_child("CameraRig", true, false)
    if camera == null or not camera.has_method("set_camera_mode"):
        _failures.append("Third-person CameraRig was not found")
        _finish()
        return
    camera.set_camera_mode(true, true)
    for _i in 45:
        await get_tree().physics_frame
    _assert_true(camera.global_position.y > _hero.global_position.y + 0.30, "third-person camera focus stays above Hero feet")
    print("movement test hero_start=", _hero.global_position, " camera_focus=", camera.global_position)
    for i in 240:
        var phase := i % 120
        if phase < 30:
            _hero.desired_direction = Vector3(1, 0, 0)
        elif phase < 60:
            _hero.desired_direction = Vector3(0, 0, 1)
        elif phase < 90:
            _hero.desired_direction = Vector3(-1, 0, 0)
        else:
            _hero.desired_direction = Vector3(0, 0, -1)
        _hero.input_active = true
        _hero.has_move_target = false
        await get_tree().physics_frame
        _frames += 1
    _hero.input_active = false
    _hero.desired_direction = Vector3.ZERO
    print("movement test hero_end=", _hero.global_position, " frames=", _frames)
    _finish()

func _assert_true(condition: bool, message: String) -> void:
    if condition:
        print("PASS: ", message)
    else:
        _failures.append(message)
        print("FAILURE: ", message)

func _finish() -> void:
    if not _failures.is_empty():
        for failure in _failures:
            print("FAILURE: ", failure)
        get_tree().quit(1)
    else:
        print("=== Movement Runtime Validation ===")
        print("passes=1 failures=0")
        get_tree().quit(0)
