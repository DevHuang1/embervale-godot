extends Node

## === FloatingText — Damage/Status Number Pop System ===
## Called as: FloatingText.spawn_on_entity(entity, text, color, scale?)
class_name FloatingText
##
## Each pop: a Label3D that floats upward, scales in, then fades out.
## No external font required — uses the project theme font if set,
## or Godot's built-in default. Text is billboard-facing.
##
## Static factory — no AutoLoad needed; call from any context.

const DEFAULT_SCALE   : float = 0.055
const RISE_HEIGHT     : float = 1.05
const DURATION        : float = 1.10
const FADE_START_AT   : float = 0.55  # fraction of duration before fade begins
const POP_SCALE_MULT  : float = 1.45  # momentary scale-up at start

static func spawn_on_entity(
		entity: Node3D,
		text: String,
		color: Color,
		font_scale: float = DEFAULT_SCALE) -> void:

	if entity == null or not is_instance_valid(entity) or not entity.is_inside_tree():
		return
	var tree := entity.get_tree()
	if tree == null:
		return
	var scene_root := tree.current_scene
	if scene_root == null:
		return

	var label := Label3D.new()
	label.text          = text
	label.modulate      = color
	label.font_size     = 64          # internal resolution; visual size set by scale
	label.outline_size  = 6
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.72)
	label.billboard     = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.double_sided  = true
	label.alpha_cut     = Label3D.ALPHA_CUT_DISABLED

	# Spawn slightly above entity centre + random horizontal scatter
	var offset := Vector3(
		randf_range(-0.22, 0.22),
		1.20,
		randf_range(-0.12, 0.12))
	scene_root.add_child(label)
	label.global_position = entity.global_position + offset
	label.scale = Vector3.ONE * font_scale * 0.01   # start tiny

	# Animate: pop scale + rise + fade
	var tw := label.create_tween()
	tw.set_parallel(true)

	# Scale pop
	tw.tween_property(label, "scale",
		Vector3.ONE * font_scale * POP_SCALE_MULT, 0.10).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_property(label, "scale",
		Vector3.ONE * font_scale, 0.14).set_trans(Tween.TRANS_SPRING)

	# Rise
	tw.tween_property(label, "global_position",
		label.global_position + Vector3(0, RISE_HEIGHT, 0),
		DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Fade (after FADE_START_AT fraction)
	tw.tween_interval(DURATION * FADE_START_AT)
	tw.chain().tween_property(label, "modulate:a",
		0.0, DURATION * (1.0 - FADE_START_AT)).set_trans(Tween.TRANS_QUAD)

	tw.chain().tween_callback(label.queue_free)

# ─────────────────────────────────────────────────────────────────────────────
# Damage numbers (pooled Label3D)
# ─────────────────────────────────────────────────────────────────────────────

const LIFETIME        := 0.75
const DAMAGE_LIFETIME := 0.92
const STATUS_FONT_SIZE := 42
const DAMAGE_FONT_SIZE := 56

static var _label_pool: Array[Label3D] = []
static var _damage_serial := 0

## Combat damage numbers use a stronger silhouette and a small horizontal
## drift so consecutive hits remain legible instead of stacking on one
## pixel column. Labels are pooled and reused instead of allocated per hit.
static func spawn_damage_on_entity(entity: Node3D, amount: int,
		critical: bool = false, color: Color = Color.BLACK) -> void:
	if entity == null or not is_instance_valid(entity) or not entity.is_inside_tree():
		return
	var label := _acquire_label(entity)
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

static func _acquire_label(parent: Node) -> Label3D:
	_label_pool = _label_pool.filter(func(l): return is_instance_valid(l))
	for pooled in _label_pool:
		if not pooled.visible:
			pooled.visible = true
			return pooled
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
	_label_pool.append(label)
	return label

static func _scene_root(parent: Node) -> Node:
	if parent != null and is_instance_valid(parent) and parent.is_inside_tree():
		var tree := parent.get_tree()
		return tree.current_scene if tree.current_scene != null else tree.root
	return null

