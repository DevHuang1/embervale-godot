extends SceneTree

## Runtime probe: boots realm scenes and dumps hero weapon-socket state and
## boss script/AI validity so "weapons disappeared / boss not moving" can be
## reproduced headless.
##   godot --headless --path . --script tests/diag_weapon_boss_probe.gd -- --scene res://scenes/world/grove.tscn

var _scene := "res://scenes/world/grove.tscn"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(0, args.size() - 1, 2):
		if args[i] == "--scene":
			_scene = args[i + 1]
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	print("=== PROBE scene=", _scene, " ===")
	var pack := load(_scene) as PackedScene
	if pack == null:
		print("PROBE-FAIL: scene not loadable: ", _scene)
		quit(1)
		return
	var world := pack.instantiate()
	root.add_child(world)
	await _frames(90)

	var hero := root.get_tree().get_first_node_in_group("player") as Node
	if hero == null:
		print("PROBE: no player node in scene")
	else:
		print("hero weapon id=", hero.get("current_weapon").get("id", ""))
		print("hero _has_hand_weapon=", hero.get("_has_hand_weapon"))
		for sock_name in ["HandSocketL", "HandSocketR", "BackSocket"]:
			var sock := hero.get_node_or_null(NodePath(sock_name)) 
			if sock == null:
				var cands := (hero as Node).find_children("*", "AttachmentSocket", true, false)
				for c in cands:
					if c.socket_id == ("hand_l" if sock_name == "HandSocketL" else "hand_r" if sock_name == "HandSocketR" else "back"):
						sock = c
						break
			if sock == null:
				print("  ", sock_name, ": MISSING")
				continue
			var occ: bool = sock.is_occupied()
			var att = sock.get_attachment() if occ else null
			print("  ", sock_name, ": occupied=", occ,
				" attached=", att.name if att else "none",
				" vis=", att.visible if att else "-",
				" in_tree_visible=", att.is_visible_in_tree() if att else "-",
				" parent=", att.get_parent().name if att else "-",
				" global_pos=", att.global_position if att else "-")
		var blade := (hero as Node).find_child("DrawnBlade", true, false)
		print("  DrawnBlade vis=", blade.visible if blade else "missing",
			" in_tree_vis=", blade.is_visible_in_tree() if blade else "-")

	# Boss inspection
	var bosses := root.get_tree().get_nodes_in_group("boss")
	if bosses.is_empty():
		bosses = (world as Node).find_children("*", "CharacterBody3D", true, false).filter(
			func(n: Node) -> bool: return str(n.name).to_lower().contains("boss"))
	print("PROBE: boss nodes=", bosses.size())
	for boss in bosses:
		var s = boss.get_script()
		print("  boss=", boss.name, " script=", s.resource_path if s else "NULL",
			" has_ai=", boss.has_method("_update_ai"),
			" vel=", boss.get("velocity"), " pos=", boss.global_position)
	await _frames(60)
	for boss in bosses:
		print("  boss=", boss.name, " pos_after=", boss.global_position,
			" vel=", boss.get("velocity"))

	world.queue_free()
	await _frames(2)

	# --- Boss AI movement check: boss_biome + fake player must pursue ---
	var gs = root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()
	var boss_pack := load("res://scenes/entities/boss_biome.tscn") as PackedScene
	if boss_pack != null:
		var boss := boss_pack.instantiate()
		boss.set("def_id", "fenmaw")
		root.add_child(boss)
		var fake_player := Node3D.new()
		fake_player.add_to_group("player")
		fake_player.position = Vector3(12, 0.5, 6)
		root.add_child(fake_player)
		await _frames(5)
		var pos_before: Vector3 = boss.global_position
		await _frames(60)
		var pos_after: Vector3 = boss.global_position
		var moved := pos_before.distance_to(pos_after)
		print("BOSS-MOVE: script=", "OK" if boss.has_method("_update_ai") else "NULL",
			" moved=", snappedf(moved, 0.01), " vel=", boss.get("velocity"))
		if not boss.has_method("_update_ai") or moved < 0.2:
			print("BOSS-MOVE FAIL: boss did not pursue player")
		else:
			print("BOSS-MOVE OK")
		boss.queue_free()
		fake_player.queue_free()

	print("=== PROBE DONE ===")
	quit(0)