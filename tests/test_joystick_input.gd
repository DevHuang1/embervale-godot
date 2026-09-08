extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	var joystick_source := FileAccess.get_file_as_string("res://scripts/ui/virtual_joystick.gd")
	var input_source := FileAccess.get_file_as_string("res://scripts/autoload/input_manager.gd")
	_check(joystick_source.contains("set_joystick_pointer"), "joystick claims pointer ownership")
	_check(input_source.contains("_joystick_pointer_ids"), "input manager tracks joystick pointers")
	_check(input_source.contains("_is_joystick_pointer"), "input manager filters joystick pointers")
	var joystick := EmberJoystick.new()
	joystick.set_layout(Vector2(200, 200), 0.1, 0.8, Vector2(20, 20))
	root.add_child(joystick)
	var outputs: Array[Vector2] = []
	joystick.direction_changed.connect(func(value: Vector2) -> void: outputs.append(value))
	joystick._set_from_position(Vector2(190, 100))
	_check(outputs.size() > 0 and outputs.back().x > 0.5, "drag emits rightward movement")
	joystick._reset_direction()
	_check(outputs.back().is_zero_approx(), "release resets movement")
	_check(joystick.size == Vector2(200, 200), "layout updates control size")
	_check(is_equal_approx(joystick.modulate.a, 0.8), "layout updates opacity")
	# All 8 usable directions must produce a non-degenerate normalized vector.
	# A joystick that "cannot move in all directions" fails this gate by
	# collapsing one whole axis to zero once the knob reaches the rim.
	var azimuths := [
		Vector2(199, 100), Vector2(100, 1), Vector2(1, 100), Vector2(100, 199),
		Vector2(170, 30), Vector2(170, 170), Vector2(30, 170), Vector2(30, 30),
	]
	var rim_unit := Vector2(1.0, 0.0)
	for i in azimuths.size():
		joystick._set_from_position(azimuths[i])
		var out: Vector2 = outputs.back()
		_check(out.length() > 0.5, "azimuth %d reaches rim magnitude" % i)
		if i % 2 == 0:
			_check(absf(out.x) > 0.2, "azimuth %d keeps its horizontal component" % i)
		else:
			_check(absf(out.y) > 0.2, "azimuth %d keeps its vertical component" % i)
		if i in [0, 4]:
			_check(out.dot(rim_unit) > 0.5, "azimuth %d points right of screen" % i)
	joystick._reset_direction()
	# A drag that leaves the control rect must keep producing movement: the
	# engine routes it here because claim_pointer registers capture in super.
	joystick.claim_pointer(7)
	joystick._set_from_position(Vector2(500, 400))
	_check(not outputs.back().is_zero_approx(), "outside-rect drag still emits a direction")
	joystick.release_pointer(7)
	joystick.queue_free()
	print("JOYSTICK INPUT CONTRACT PASSED" if failures.is_empty() else "FAILURES: ", failures)
	quit(1 if not failures.is_empty() else 0)

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
