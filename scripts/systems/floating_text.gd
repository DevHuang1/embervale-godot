class_name FloatingText
extends Node3D

## === Floating Combat Text ===
## Billboarded Label3D that rises and fades. Labels are pooled and reused
## instead of allocated per hit.

const LIFETIME := 0.75
const DAMAGE_LIFETIME := 0.92
const STATUS_FONT_SIZE := 42
const DAMAGE_FONT_SIZE := 56

static var _pool: Array[Label3D] = []
static var _damage_serial := 0

static func spawn(parent: Node, world_pos: Vector3, text: String, color: Color, size_scale: float = 1.0) -> void:
    if parent == null or not parent.is_inside_tree():
        return
    var label := _acquire(parent)
    if label == null:
        return
    label.text = text
    label.font_size = int(STATUS_FONT_SIZE * size_scale)
    label.outline_size = int(8 * maxf(size_scale, 1.0))
    label.modulate = color
    label.modulate.a = 1.0
    label.outline_modulate = Color(0.02, 0.03, 0.02, 0.9)
    label.global_position = world_pos + Vector3(randf_range(-0.25, 0.25), 1.35, 0)

    var tween := label.create_tween()
    tween.set_parallel(true)
    tween.tween_property(label, "position:y", label.position.y + 1.15, LIFETIME) \
        .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tween.tween_property(label, "modulate:a", 0.0, LIFETIME - 0.15).set_delay(0.15)
    tween.chain().tween_callback(func(): label.visible = false)

## Combat damage numbers use a stronger silhouette and a small horizontal drift
## so consecutive hits remain legible instead of stacking on one pixel column.
static func spawn_damage_on_entity(entity: Node3D, amount: int, critical: bool = false, color: Color = Color.BLACK) -> void:
    if entity == null or not is_instance_valid(entity) or not entity.is_inside_tree():
        return
    var label := _acquire(entity)
    if label == null:
        return
    var base_color := Color(1.0, 0.90, 0.68)
    if critical:
        base_color = Color(1.0, 0.42, 0.16)
    if color != Color.BLACK:
        base_color = color
    _damage_serial += 1
    var side := -1.0 if _damage_serial % 2 == 0 else 1.0
    var size_scale := 1.25 if critical else 1.0
    label.text = "%s%d" % ["CRIT " if critical else "", amount]
    label.font_size = int(DAMAGE_FONT_SIZE * size_scale)
    label.outline_size = int(10 * size_scale)
    label.modulate = base_color
    label.modulate.a = 1.0
    label.outline_modulate = Color(0.02, 0.015, 0.01, 0.96)
    label.global_position = entity.global_position + Vector3(side * 0.24, 1.72, 0.0)
    label.scale = Vector3.ONE * (0.72 if critical else 0.62)

    var tween := label.create_tween()
    tween.set_parallel(true)
    tween.tween_property(label, "position:y", label.position.y + (1.25 if critical else 1.0), DAMAGE_LIFETIME) \
        .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tween.tween_property(label, "position:x", label.position.x + side * 0.38, DAMAGE_LIFETIME) \
        .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    tween.tween_property(label, "scale", Vector3.ONE * (1.0 if critical else 0.9), 0.12) \
        .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tween.tween_property(label, "modulate:a", 0.0, DAMAGE_LIFETIME - 0.16).set_delay(0.16)
    tween.chain().tween_callback(func(): label.visible = false)

static func spawn_on_entity(entity: Node3D, text: String, color: Color, size_scale: float = 1.0) -> void:
    if entity == null or not is_instance_valid(entity) or not entity.is_inside_tree():
        return
    spawn(entity, entity.global_position, text, color, size_scale)

static func _acquire(parent: Node) -> Label3D:
    _pool = _pool.filter(func(l): return is_instance_valid(l))
    for label in _pool:
        if not label.visible:
            label.visible = true
            return label
    var label := Label3D.new()
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.no_depth_test = true
    label.pixel_size = 0.01
    label.font_size = STATUS_FONT_SIZE
    label.outline_size = 8
    var host := _scene_root(parent)
    if host == null:
        return null
    host.add_child(label)
    _pool.append(label)
    return label

static func _scene_root(parent: Node) -> Node:
    if parent != null and is_instance_valid(parent) and parent.is_inside_tree():
        var tree := parent.get_tree()
        return tree.current_scene if tree.current_scene != null else tree.root
    var loop := Engine.get_main_loop() as SceneTree
    return loop.root if loop != null else null
