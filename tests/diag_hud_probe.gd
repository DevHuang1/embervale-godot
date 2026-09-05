extends SceneTree

## TEMP probe: verify HUD wiring (glyphs, action-button connections,
## attack/skill paths through InputManager, authored locomotion clips).

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var gs = root.get_node("/root/GameState")
	var im = root.get_node("/root/InputManager")
	var scene := (load("res://scenes/world/grove.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 20:
		await process_frame
	var hud = scene.find_child("HUD", true, false)
	var hero = scene.get_node_or_null("Hero")
	print("PROBE hud=", hud, " hero=", hero)
	for i in 3:
		var g = hud.skill_glyph_labels[i]
		print("PROBE glyph%d='%s'" % [i, g.text if g else "<none>"])
	var atk: Node = hud.get_node_or_null("Root/SkillBar/AttackButton")
	var atk_conns: int = atk.get_signal_connection_list("fight_pressed").size() if atk else -1
	print("PROBE attack_btn_conns=", atk_conns)
	# Dummy enemy near hero to exercise attack targeting
	var foe := Node3D.new()
	foe.name = "ProbeFoe"
	foe.add_to_group("enemy")
	foe.set("hp", 500)
	foe.set("max_hp", 500)
	foe.position = hero.global_position + Vector3(3, 0, 0)
	scene.add_child(foe)
	await process_frame
	# 1) Attack button press → InputManager → hero marks + glides in + strikes
	atk._fire()
	for i in 100:
		await physics_frame
	print("PROBE after_attack auto_strike_timer=", snappedf(hero.auto_strike_timer, 0.1),
			" attack_seq=", hero._attack_seq, " target=", gs.enemy_target)
	# 2) Skill button 0 press → InputManager → hero rite
	hud.skill_buttons[0]._fire()
	for i in 12:
		await process_frame
	print("PROBE after_skill0 combat=", gs.combat_state, " cds=", gs.skill_cooldowns)
	# 3) Locomotion: drive the hero forward, check authored clips
	var bridge = hero._anim_bridge()
	print("PROBE bridge=", bridge, " player=", bridge.player if bridge != null else null)
	for i in 40:
		im.move_input.emit(Vector2(0, -1))
		await physics_frame
	im.move_input.emit(Vector2.ZERO)
	print("PROBE locomotion anim='", bridge.player.current_animation if bridge != null and bridge.player != null else "<none>",
			"' speed=", snappedf(Vector3(hero.velocity.x, 0, hero.velocity.z).length(), 0.1))
	for i in 40:
		im.move_input.emit(Vector2(0, -1))
		await physics_frame
	im.move_input.emit(Vector2.ZERO)
	print("PROBE locomotion2 anim='", bridge.player.current_animation if bridge != null and bridge.player != null else "<none>",
			"' speed=", snappedf(Vector3(hero.velocity.x, 0, hero.velocity.z).length(), 0.1))
	for i in 30:
		await physics_frame
	print("PROBE idle anim='", bridge.player.current_animation if bridge != null and bridge.player != null else "<none>",
			"' playing=", bridge.player.is_playing() if bridge != null and bridge.player != null else false)
	scene.queue_free()
	quit(0)

