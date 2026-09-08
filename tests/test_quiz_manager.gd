extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var qm := root.get_node_or_null("/root/QuizManager") as Node
	var gs := root.get_node_or_null("/root/GameState") as GameState
	if qm == null or gs == null:
		print("FAIL: quiz autoloads missing")
		quit(1)
		return
	gs.reset()
	gs.gold = 0
	var wrong: Dictionary = qm.call("submit", 0, 1)
	if not bool(wrong.get("success", false)) or bool(wrong.get("correct", true)):
		print("FAIL: wrong answer contract")
		quit(1)
		return
	var right: Dictionary = qm.call("submit", 0, 0)
	if not bool(right.get("correct", false)) or gs.gold != 12:
		print("FAIL: correct quiz reward contract")
		quit(1)
		return
	var repeat: Dictionary = qm.call("submit", 0, 0)
	if bool(repeat.get("success", true)) or gs.gold != 12:
		print("FAIL: quiz reward duplicated")
		quit(1)
		return
	print("ALL QUIZ MANAGER TESTS PASSED")
	quit(0)
