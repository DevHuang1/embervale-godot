extends Node

var _failures: Array[String] = []
var _passes := 0

func _ready() -> void:
    await _run_validation()
    print("=== Skill VFX Validation ===")
    print("passes=", _passes, " failures=", _failures.size())
    for failure in _failures:
        print("FAILURE: ", failure)
    get_tree().quit(1 if not _failures.is_empty() else 0)

func _run_validation() -> void:
    var from_pos := Vector3(-1.0, 1.0, 0.0)
    var to_pos := Vector3(4.0, 1.35, -2.0)
    CombatFx.spawn_skill_ribbon(self, from_pos, to_pos, Color(0.96, 0.38, 0.16, 0.9), 0.48, 0.22)
    CombatFx.spawn_vibrant_trail(self, from_pos, to_pos,
        Color(0.95, 0.24, 0.12, 0.9), Color(1.0, 0.92, 0.36, 0.95), 5)
    CombatFx.spawn_bolt(self, from_pos, to_pos,
        Color(0.68, 0.38, 1.0, 0.95), 0.08, 0.22)
    await get_tree().process_frame
    var ribbon := get_node_or_null("SkillRibbon") as MeshInstance3D
    var core := get_node_or_null("SkillRibbonCore") as MeshInstance3D
    _assert_true(ribbon != null, "skill ribbon is spawned")
    _assert_true(core != null, "skill ribbon has a hot core")
    for node in [ribbon, core]:
        if node == null:
            continue
        _assert_true(node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "skill ribbon disables shadow casting")
        var mesh := node.mesh as ArrayMesh
        _assert_true(mesh != null and mesh.get_surface_count() == 1, "skill ribbon uses one lightweight ArrayMesh surface")
        if mesh != null and mesh.get_surface_count() > 0:
            var material := mesh.surface_get_material(0) as StandardMaterial3D
            _assert_true(material != null, "skill ribbon has a StandardMaterial3D")
            if material != null:
                _assert_true(material.blend_mode == BaseMaterial3D.BLEND_MODE_ADD, "skill ribbon uses additive blending")
                _assert_true(material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "skill ribbon is unshaded for readable color")

    for index in range(10):
        var hue := float(index) / 10.0
        CombatFx.spawn_skill_ribbon(self, Vector3.ZERO, Vector3(0, 0.5, -3.0), Color(0.5 + hue * 0.4, 0.7, 1.0, 0.8), 0.3, 0.5)
    _assert_true(CombatFx._trail_ribbons.size() <= CombatFx.MAX_TRAIL_RIBBONS, "skill ribbon pool stays capped")
    await get_tree().process_frame
    await get_tree().process_frame
    _assert_true(CombatFx._trail_ribbons.size() <= CombatFx.MAX_TRAIL_RIBBONS, "skill ribbon pool remains capped after cleanup")
    await get_tree().create_timer(0.65).timeout
    _assert_true(get_node_or_null("SkillRibbon") == null, "skill ribbon cleans itself up after its fade")

func _assert_true(condition: bool, message: String) -> void:
    if condition:
        _passes += 1
        print("PASS: ", message)
    else:
        _failures.append(message)
        push_error("FAIL: " + message)
