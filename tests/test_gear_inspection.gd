extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := load("res://scenes/ui/satchel.tscn") as PackedScene
	if scene == null:
		print("FAIL: satchel scene missing")
		quit(1)
		return
	var satchel := scene.instantiate()
	root.add_child(satchel)
	await process_frame
	var weapon: Dictionary = GameState.WEAPON_DEFS["ember_sword"].duplicate(true)
	satchel.call("_on_inspect_weapon", weapon)
	var selected: Label = satchel.get("_selected_item_label")
	if selected == null or not selected.text.contains("vs") or not selected.text.contains("SALVAGE"):
		print("FAIL: weapon inspection comparison missing")
		quit(1)
		return
	var armor: Dictionary = GameState.ARMOR_DEFS["warden_plate"].duplicate(true)
	satchel.call("_on_inspect_armor", armor)
	if not selected.text.contains("DEFENSIVE GEAR") or not selected.text.contains("SOURCE"):
		print("FAIL: armor inspection context missing")
		quit(1)
		return
	satchel.queue_free()
	print("ALL GEAR INSPECTION TESTS PASSED")
	quit(0)
