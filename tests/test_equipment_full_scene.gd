extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game_state: Node = root.get_node_or_null("GameState")
	if game_state == null:
		_fail("GameState autoload missing")
		quit(1)
		return
	game_state.delete_save()
	game_state.reset()
	var main_scene := load("res://scenes/main/main.tscn") as PackedScene
	if main_scene == null:
		_fail("Main scene missing")
		quit(1)
		return
	var main := main_scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(10)
	var menu := main.get_node_or_null("MainMenu")
	if menu == null:
		_fail("Main menu missing")
	else:
		menu.call("_start_new_game")
	await create_timer(1.0).timeout
	await _frames(12)
	var grove := current_scene
	var hero := grove.get_node_or_null("Hero") if grove != null else null
	if hero == null:
		_fail("Full Grove boot did not expose Hero")
	else:
		var sword: Dictionary = game_state.WEAPON_DEFS["ember_sword"].duplicate(true)
		game_state.add_weapon(sword, true)
		await _frames(2)
		var hand := hero.get("hand_socket_l") as Node
		if str(hero.get("current_weapon").get("id", "")) != "ember_sword":
			_fail("Equipped identity did not reach Hero")
		if hand == null or not hand.has_method("has_item") or not hand.has_item():
			_fail("Equipped sword did not mount in the live left-hand socket")
		else:
			var held: Node3D = hand.get_item() as Node3D
			if held == null or held.get_parent() != hand:
				_fail("Equipped sword lost its intended hand-socket parent")
			elif held.position.length() > 1.0:
				_fail("Equipped sword pivot drifted beyond the authored palm offset")
		var trail := hero.get("swing_trail") as GPUParticles3D
		if trail == null or trail.lifetime <= 0.0 or trail.get_parent() == null:
			_fail("Weapon swing trail lacks a bounded live attachment")
		if not hero.has_method("_wait_for_animator_impact"):
			_fail("Hero lacks the shared animator impact-frame handoff")
		game_state.gold = 100
		game_state.raw_materials["iron_shard"] = 4
		var before_atk := int(game_state.equipped_weapon.get("atk", 0))
		var upgrade: Dictionary = game_state.upgrade_weapon("ember_sword")
		await _frames(2)
		if not bool(upgrade.get("success", false)):
			_fail("Equipped sword upgrade transaction failed: %s" % str(upgrade))
		elif int(game_state.equipped_weapon.get("atk", 0)) <= before_atk:
			_fail("Weapon upgrade did not increase the equipped attack stat")
		else:
			var mounted: Node = hand.get_item() if hand != null and hand.has_method("get_item") else null
			if mounted == null or mounted.get_node_or_null("UpgradeAccent") == null:
				_fail("Weapon upgrade did not refresh the live hand presentation")
			elif mounted.get_parent() != hand:
				_fail("Weapon upgrade detached the live weapon from its hand socket")
	if failures.is_empty():
		print("ALL FULL-SCENE EQUIPMENT TESTS PASSED")
		quit(0)
	else:
		print("FULL-SCENE EQUIPMENT TESTS FAILED: ", failures)
		quit(1)

func _frames(count: int) -> void:
	for _i in count:
		await process_frame

func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL: ", message)
