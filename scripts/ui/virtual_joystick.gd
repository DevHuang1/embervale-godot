extends Control

class_name EmberJoystick

signal direction_changed(direction: Vector2)

@export var radius: float = 68.0
@export var deadzone: float = 0.12
@export var base_color := Color(0.06, 0.12, 0.13, 0.72)
@export var rim_color := Color(0.45, 0.72, 0.56, 0.82)
@export var knob_color := Color(0.96, 0.72, 0.29, 0.94)

var knob_offset := Vector2.ZERO
var active_pointer := -1
var mouse_active := false

func _local_pointer_position(screen_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_position

func set_layout(control_size: Vector2, new_deadzone: float, opacity: float,
		anchor: Vector2 = Vector2(-1.0, -1.0)) -> void:
	custom_minimum_size = control_size
	size = control_size
	deadzone = clampf(new_deadzone, 0.0, 0.85)
	modulate.a = clampf(opacity, 0.2, 1.0)
	if anchor.x >= 0.0 and anchor.y >= 0.0:
		position = anchor
	radius = minf(size.x, size.y) * 0.405
	_reset_direction()
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(168, 168)
	queue_redraw()

## Screen touches must be tracked at the viewport level. A Control only
## receives _gui_input while the pointer is over its rect; a virtual stick
## needs the drag and release even after the finger leaves that rect.
func _input(event: InputEvent) -> void:
	if not is_inside_tree():
		return
	if event is InputEventScreenTouch:
		var local := _local_pointer_position(event.position)
		if event.pressed and active_pointer == -1 \
				and Rect2(Vector2.ZERO, size).has_point(local):
			if claim_pointer(event.index):
				_set_from_position(local)
				get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == active_pointer:
			release_pointer(event.index)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == active_pointer:
		_set_from_position(_local_pointer_position(event.position))
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and active_pointer == -1:
			if not claim_pointer(event.index):
				return
			_set_from_position(_local_pointer_position(event.position))
			accept_event()
		elif not event.pressed and event.index == active_pointer:
			release_pointer(event.index)
			accept_event()
	elif event is InputEventScreenDrag and event.index == active_pointer:
		_set_from_position(_local_pointer_position(event.position))
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			mouse_active = true
			_set_from_position(_local_pointer_position(event.position))
		else:
			mouse_active = false
			_reset_direction()
		accept_event()
	elif event is InputEventMouseMotion and mouse_active:
		_set_from_position(_local_pointer_position(event.position))
		accept_event()

func _set_from_position(point: Vector2) -> void:
	var center := size * 0.5
	var offset := point - center
	if offset.length() > radius:
		offset = offset.normalized() * radius
	knob_offset = offset
	var output := offset / radius
	if output.length() < deadzone:
		output = Vector2.ZERO
	else:
		output = output.normalized() * ((output.length() - deadzone) / (1.0 - deadzone))
	direction_changed.emit(output)
	queue_redraw()

func _reset_direction() -> void:
	knob_offset = Vector2.ZERO
	direction_changed.emit(Vector2.ZERO)
	queue_redraw()

func _set_input_owner(pointer_id: int, owned: bool) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	# Avoid absolute-path lookups here. They emit an engine error in isolated
	# tests and make ownership cleanup less reliable during scene transitions.
	var input_manager := tree.root.get_node_or_null("InputManager")
	if input_manager != null and input_manager.has_method("set_joystick_pointer"):
		input_manager.call("set_joystick_pointer", pointer_id, owned)

func claim_pointer(pointer_id: int) -> bool:
	if active_pointer != -1 or pointer_id < 0:
		return false
	# Control has no claim_pointer API in Godot 4. Pointer ownership is tracked
	# by InputManager, while this control keeps receiving drags through its
	# normal input handling.
	active_pointer = pointer_id
	_set_input_owner(pointer_id, true)
	return true

func release_pointer(pointer_id: int) -> void:
	if pointer_id != active_pointer:
		return
	_set_input_owner(pointer_id, false)
	active_pointer = -1
	_reset_direction()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if active_pointer >= 0:
			release_pointer(active_pointer)
		mouse_active = false

func _exit_tree() -> void:
	if active_pointer >= 0:
		_set_input_owner(active_pointer, false)
	active_pointer = -1
	mouse_active = false

func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, radius + 5.0, Color(0.02, 0.04, 0.05, 0.4))
	draw_circle(center, radius, base_color)
	draw_arc(center, radius, 0.0, TAU, 64, rim_color, 3.0, true)
	draw_circle(center + knob_offset, radius * 0.38, knob_color)
	draw_arc(center + knob_offset, radius * 0.38, 0.0, TAU, 48, Color(1.0, 0.9, 0.6, 0.9), 2.0, true)
