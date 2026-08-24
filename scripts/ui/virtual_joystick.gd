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

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(168, 168)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and active_pointer == -1:
			active_pointer = event.index
			_set_from_position(event.position)
			accept_event()
		elif not event.pressed and event.index == active_pointer:
			active_pointer = -1
			_reset_direction()
			accept_event()
	elif event is InputEventScreenDrag and event.index == active_pointer:
		_set_from_position(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			mouse_active = true
			_set_from_position(event.position)
		else:
			mouse_active = false
			_reset_direction()
		accept_event()
	elif event is InputEventMouseMotion and mouse_active:
		_set_from_position(event.position)
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

func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, radius + 5.0, Color(0.02, 0.04, 0.05, 0.4))
	draw_circle(center, radius, base_color)
	draw_arc(center, radius, 0.0, TAU, 64, rim_color, 3.0, true)
	draw_circle(center + knob_offset, radius * 0.38, knob_color)
	draw_arc(center + knob_offset, radius * 0.38, 0.0, TAU, 48, Color(1.0, 0.9, 0.6, 0.9), 2.0, true)
