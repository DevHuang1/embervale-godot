extends Node3D
class_name EnemyHealthBar

## World-space enemy health plate. It reads hp/max_hp from its parent so it
## works for Hushlings, Fenlings, and BossBase without coupling to one class.
@export var bar_width: float = 1.65
@export var bar_height: float = 0.13
@export var height_offset: float = 2.35
@export var show_name_when_targeted: bool = true

var _background: MeshInstance3D
var _fill: MeshInstance3D
var _fill_material: StandardMaterial3D
var _lock_frame: MeshInstance3D
var _lock_material: StandardMaterial3D
var _name_label: Label3D
var _hp_label: Label3D
var _last_ratio := -1.0
var _source: Node
var _base_scale := 1.0
var _lock_was := false

func _ready() -> void:
    _source = get_parent()
    if _source == null:
        queue_free()
        return
    _base_scale = 1.25 if int(_source.get("max_hp")) >= 200 else 1.0
    position = Vector3(0.0, height_offset * _base_scale, 0.0)
    scale = Vector3.ONE * _base_scale
    _build_bar()
    _refresh(true)

func _process(_delta: float) -> void:
    if not is_instance_valid(_source):
        queue_free()
        return
    _refresh(false)

func _build_bar() -> void:
    var plate := Node3D.new()
    plate.name = "HealthPlate"
    add_child(plate)

    var back_mesh := QuadMesh.new()
    back_mesh.size = Vector2(bar_width, bar_height)
    var back_material := _make_material(Color(0.025, 0.018, 0.02, 0.92))
    back_mesh.material = back_material
    _background = MeshInstance3D.new()
    _background.name = "HealthBackground"
    _background.mesh = back_mesh
    _background.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    plate.add_child(_background)

    var fill_mesh := QuadMesh.new()
    fill_mesh.size = Vector2(bar_width - 0.06, bar_height - 0.035)
    _fill_material = _make_material(Color(0.20, 0.92, 0.34, 1.0))
    fill_mesh.material = _fill_material
    _fill = MeshInstance3D.new()
    _fill.name = "HealthFill"
    _fill.mesh = fill_mesh
    _fill.position = Vector3(-(bar_width - 0.06) * 0.5, 0.0, -0.006)
    _fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    plate.add_child(_fill)

    # Lock frame: lantern-orange border that only appears on the marked foe,
    # so "this is the one my lantern lit" answers itself at a glance.
    var lock_mesh := QuadMesh.new()
    lock_mesh.size = Vector2(bar_width + 0.06, bar_height + 0.05)
    _lock_material = _make_material(Color(1.0, 0.74, 0.30, 0.0))
    _lock_material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
    lock_mesh.material = _lock_material
    _lock_frame = MeshInstance3D.new()
    _lock_frame.name = "LockFrame"
    _lock_frame.mesh = lock_mesh
    _lock_frame.position = Vector3(0.0, 0.0, -0.002)
    _lock_frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _lock_frame.visible = false
    plate.add_child(_lock_frame)

    _name_label = Label3D.new()
    _name_label.name = "EnemyName"
    _name_label.position = Vector3(0.0, 0.18, 0.0)
    _name_label.font_size = 32
    _name_label.modulate = Color(1.0, 0.90, 0.72, 0.96)
    _name_label.outline_size = 6
    _name_label.outline_modulate = Color(0.03, 0.02, 0.02, 0.9)
    _name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    _name_label.no_depth_test = true
    _name_label.text = _clean_name(str(_source.name))
    plate.add_child(_name_label)

    _hp_label = Label3D.new()
    _hp_label.name = "EnemyHP"
    _hp_label.position = Vector3(0.0, -0.18, 0.0)
    _hp_label.font_size = 22
    _hp_label.modulate = Color(1.0, 0.96, 0.90, 0.9)
    _hp_label.outline_size = 4
    _hp_label.outline_modulate = Color(0.03, 0.02, 0.02, 0.9)
    _hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    _hp_label.no_depth_test = true
    plate.add_child(_hp_label)

func _make_material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.albedo_color = color
    material.disable_receive_shadows = true
    material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    return material

## Immediate damage hook used by enemy and boss damage handlers. The normal
## process refresh remains as a safety net for regeneration and scripted damage.
func notify_damage() -> void:
    if _fill == null or _fill_material == null:
        return
    _last_ratio = -1.0
    _refresh(true)
    var original := _fill_material.albedo_color
    var flash := create_tween()
    _fill_material.albedo_color = Color(1.0, 0.92, 0.62)
    flash.tween_property(_fill_material, "albedo_color", original, 0.16) \
        .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _refresh(force: bool) -> void:
    var max_hp := maxi(1, int(_source.get("max_hp")))
    var hp := clampi(int(_source.get("hp")), 0, max_hp)
    var ratio := clampf(float(hp) / float(max_hp), 0.0, 1.0)
    if force or not is_equal_approx(ratio, _last_ratio):
        _last_ratio = ratio
        _fill.scale = Vector3(maxf(ratio, 0.001), 1.0, 1.0)
        var healthy := Color(0.18, 0.92, 0.34)
        var danger := Color(0.96, 0.16, 0.10)
        _fill_material.albedo_color = danger.lerp(healthy, smoothstep(0.0, 0.72, ratio))
        _hp_label.text = "%d / %d" % [hp, max_hp]
    var defeated := bool(_source.get("is_defeated")) or hp <= 0
    visible = not defeated
    var is_locked := false
    if show_name_when_targeted:
        var game_state := get_node_or_null("/root/GameState")
        var target = game_state.enemy_target if game_state != null else null
        is_locked = target == _source
        _name_label.visible = is_locked or hp < max_hp
    if is_locked and not _lock_was:
        _lock_was = true
        _name_label.modulate = Color(1.0, 0.74, 0.30, 1.0)
        _name_label.text = "◈ %s" % _clean_name(str(_source.name))
    elif not is_locked and _lock_was:
        _lock_was = false
        _name_label.modulate = Color(1.0, 0.90, 0.72, 0.96)
        _name_label.text = _clean_name(str(_source.name))
    _lock_frame.visible = is_locked
    if is_locked and _lock_material:
        var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.006)
        _lock_material.albedo_color = Color(1.0, 0.74, 0.30,
            0.16 + 0.16 * pulse)

func _clean_name(value: String) -> String:
    var parts := value.split("@", false)
    return parts[parts.size() - 1] if not parts.is_empty() else value
