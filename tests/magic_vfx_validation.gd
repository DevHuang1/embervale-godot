extends Node3D

func _ready() -> void:
    var shader: Shader = load("res://assets/shaders/magic_vfx.gdshader")
    assert(shader != null, "magic VFX shader must load")
    var particles := MagicVfxProfiles.create_particles("staff_orb", self)
    assert(particles != null, "staff orb profile must create particles")
    assert(particles.amount > 0, "staff orb profile must emit particles")
    assert(particles.draw_pass_1 != null, "staff orb profile must have a draw mesh")
    assert(particles.process_material != null, "staff orb profile must have a process material")
    print("PASS: magical VFX shader and staff orb profile load")
    particles.queue_free()
    get_tree().quit()
