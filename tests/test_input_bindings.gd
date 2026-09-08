extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var input_manager := root.get_node_or_null("/root/InputManager")
	if input_manager == null:
		push_error("InputManager autoload missing")
		quit(1)
		return
	input_manager.reset_key_bindings()
	if int(input_manager.get_key_binding("skill_0")) != KEY_Q:
		push_error("Default skill binding was not restored")
		quit(1)
		return
	if not input_manager.set_key_binding("skill_0", KEY_Z) \
			or int(input_manager.get_key_binding("skill_0")) != KEY_Z:
		push_error("Skill binding could not be changed")
		quit(1)
		return
	if input_manager.set_key_binding("skill_1", KEY_Z):
		push_error("Duplicate key binding was accepted")
		quit(1)
		return
	input_manager.reset_key_bindings()
	print("INPUT BINDINGS PASSED")
	quit(0)
