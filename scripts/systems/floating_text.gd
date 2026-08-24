class_name FloatingText
extends Node3D

## === Floating Combat Text ===
## Billboarded Label3D that rises and fades. Labels are pooled and
## reused instead of allocated per hit.

const LIFETIME := 0.75

static var _pool: Array[Label3D] = []

static func spawn(parent: Node, world_pos: Vector3, text: String, color: Color) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var label := _acquire(parent)
	label.text = text
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

static func spawn_on_entity(entity: Node3D, text: String, color: Color) -> void:
	if entity == null or not is_instance_valid(entity) or not entity.is_inside_tree():
		return
	spawn(entity.get_tree().current_scene, entity.global_position, text, color)

static func _acquire(parent: Node) -> Label3D:
	_pool = _pool.filter(func(l): return is_instance_valid(l))
	for l in _pool:
		if not l.visible:
			l.visible = true
			return l
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.01
	label.font_size = 64
	label.outline_size = 12
	_scene_root(parent).add_child(label)
	_pool.append(label)
	return label

static func _scene_root(parent: Node) -> Node:
	var scene := parent.get_tree().current_scene
	return scene if scene else parent.get_tree().root