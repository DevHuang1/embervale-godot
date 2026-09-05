extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := (load("res://scenes/world/grove.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for frame in 15:
		await process_frame
	var hero := scene.get_node_or_null("Hero")
	var hush := scene.get_node_or_null("Hushling")
	print("COMBATPROBE hero=", hero, " hush=", hush)
	if hero == null or hush == null:
		quit(1)
		return
	# Engage + strike repeatedly until dead (exercises combat, skill marks, loot)
	hero.call("_begin_attack_target", hush)
	for i in 40:
		await create_timer(0.12).timeout
		var dead := hush.has_method("is_dead") and (hush.call("is_dead") as bool)
		if dead:
			print("COMBATPROBE hushling dead after hit ", i)
			break
		if hero.has_method("_perform_auto_strike"):
			hero.call("_perform_auto_strike", hush)
	# Exercise skill path with a valid target
	if not (hush.has_method("is_dead") and (hush.call("is_dead") as bool)):
		var gs := root.get_node("/root/GameState")
		gs.engage_enemy(hush)
		for slot in [0]:
			var result: Dictionary = gs.use_skill(slot)
			print("COMBATPROBE use_skill(", slot, ") success=", result.get("success"), " msg=", result.get("message", ""))
			var se := root.get_node("/root/SkillExecutor")
			if result.get("success", false):
				se.call("execute_skill", slot, result.get("skill", {}))
	# Wait for loot/gear path to settle
	await create_timer(1.0).timeout
	print("COMBATPROBE done; checking hero meta/impact path")
	var bridge: AnimTreeBridge = hero.get_meta("anim_bridge", null) as AnimTreeBridge
	print("COMBATPROBE hero anim_bridge=", bridge)
	var t: Variant = hero.call("_authored_impact_seconds", "light_1", 0.5)
	print("COMBATPROBE _authored_impact_seconds=", t)
	scene.queue_free()
	for frame in 3:
		await process_frame
	quit(0)