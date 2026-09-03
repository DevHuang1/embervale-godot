extends Node
class_name FloatingText

## === FloatingText — Damage/Status Number Pop System ===
## Called as: FloatingText.spawn_on_entity(entity, text, color, scale?)
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
	label.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
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
