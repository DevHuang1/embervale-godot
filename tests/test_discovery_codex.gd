extends SceneTree

## === Discovery Codex / First-Encounter Intro Validation ===
## - Every spawnable enemy kind and authored structure kind has a codex record
##   with a name, a title, a story and at least one named skill/feature.
## - First meetings fire exactly once per save and survive save/load.
## - The director triggers on real proximity to a creature kind and to an
##   authored structure instance, and the HUD presents one auto-dismissing
##   card without ever capturing pointer input.

const CODEX := preload("res://scripts/systems/discovery_codex.gd")

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(60.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — discovery test hung")
		quit(2))

func _run() -> void:
	var failures := 0
	var gs := root.get_node("/root/GameState")
	gs.save_path = "/tmp/embervale_discovery_%d.cfg" % OS.get_process_id()
	gs.delete_save()
	gs.reset()

	failures += _check_catalog()
	failures += _check_first_meeting_gate(gs)
	failures += _check_save_round_trip(gs)
	failures += await _check_card()
	failures += await _check_world_integration(gs)

	if failures == 0:
		print("ALL DISCOVERY CODEX TESTS PASSED")
	else:
		print("%d DISCOVERY FAILURES" % failures)
	quit(0 if failures == 0 else 1)

## Every record must carry identity, history and at least one actionable bullet,
## and no spawnable kind may be missing a record.
func _check_catalog() -> int:
	var f := 0
	for error in CODEX.validate():
		f += 1
		print("FAIL: codex validation -> %s" % error)
	var spawnable: Array = []
	for kind in EnemyVisualRegistry.ENEMY_SCENES.keys():
		spawnable.append(str(kind))
	var structure_kinds: Array = []
	for realm in ["whispergrove", "bramblewood", "mistfen", "heartwood", "moonfen"]:
		for value in RealmLayoutData.profile(realm).get("structures", []):
			structure_kinds.append(str((value as Dictionary).get("kind", "")))
	for error in CODEX.coverage_errors(spawnable, structure_kinds):
		f += 1
		print("FAIL: codex coverage -> %s" % error)
	# Aliases resolve to their canonical silhouette instead of inventing one.
	if str(CODEX.mob_record("moonfen_fenling").get("kind", "")) != "fenling":
		f += 1
		print("FAIL: moonfen_fenling should resolve to the fenling record")
	if str(CODEX.mob_record("hushling").get("bullets_label", "")) != "SKILLS":
		f += 1
		print("FAIL: mob records must label their bullets as skills")
	if str(CODEX.structure_record("shrine").get("bullets_label", "")) != "FEATURES":
		f += 1
		print("FAIL: structure records must label their bullets as features")
	if f == 0:
		print("PASS: codex covers every spawnable creature and structure kind")
	return f

func _check_first_meeting_gate(gs: Node) -> int:
	var f := 0
	if gs.has_discovered_record("mob:hushling"):
		f += 1
		print("FAIL: a fresh save should not know the hushling")
	if not gs.discover_record("mob:hushling"):
		f += 1
		print("FAIL: first discovery should report itself as new")
	if gs.discover_record("mob:hushling"):
		f += 1
		print("FAIL: repeat discovery must not report as new")
	if not gs.has_discovered_record("mob:hushling"):
		f += 1
		print("FAIL: discovery was not recorded")
	for i in GameState.DISCOVERY_RECORD_CAP + 40:
		gs.discover_record("mob:probe_%d" % i)
	if gs.discovered_records.size() > GameState.DISCOVERY_RECORD_CAP:
		f += 1
		print("FAIL: discovery records exceeded their hard cap (%d)"
			% gs.discovered_records.size())
	if f == 0:
		print("PASS: discovery gate is once-per-save and capped")
	return f

func _check_save_round_trip(gs: Node) -> int:
	var f := 0
	gs.discover_record("structure:test_round_trip")
	gs.save_game()
	var before: Dictionary = gs.discovered_records.duplicate()
	gs.reset()
	if gs.has_discovered_record("structure:test_round_trip"):
		f += 1
		print("FAIL: reset should clear discovered records")
	if not gs.load_game():
		f += 1
		print("FAIL: discovery save did not reload")
	elif not gs.has_discovered_record("structure:test_round_trip"):
		f += 1
		print("FAIL: discovered record did not survive save/load")
	elif gs.discovered_records.get("structure:test_round_trip", false) != before.get(
			"structure:test_round_trip", false):
		f += 1
		print("FAIL: discovered record changed across save/load")
	if f == 0:
		print("PASS: discovered records round-trip through the save")
	return f

func _check_card() -> int:
	var f := 0
	var card_script := preload("res://scripts/ui/discovery_card.gd")
	var panel := card_script.new()
	root.add_child(panel)
	await process_frame
	var record := CODEX.mob_record("hushling")
	panel.open_for(record)
	if not panel.visible or panel.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		f += 1
		print("FAIL: discovery card is not a visible, input-transparent notice")
	var name_label := panel.find_child("DiscoveryName", true, false) as Label
	var story := panel.find_child("DiscoveryStory", true, false) as Label
	var bullets := panel.find_children("DiscoveryBullet", "Label", true, false)
	if name_label == null or name_label.text != "HUSHLING":
		f += 1
		print("FAIL: discovery card did not name the creature")
	if story == null or not story.text.contains("root-knots"):
		f += 1
		print("FAIL: discovery card did not carry the codex story")
	if bullets.size() < 1:
		f += 1
		print("FAIL: discovery card did not list any skills")
	var dismissed := [false]
	panel.dismissed.connect(func() -> void: dismissed[0] = true)
	panel.dismiss()
	if panel.visible or not dismissed[0]:
		f += 1
		print("FAIL: discovery card did not dismiss")
	panel.queue_free()
	await process_frame
	if f == 0:
		print("PASS: discovery card carries name, story and skills")
	return f

## Real-world integration: the HUD's director fires on proximity to a spawned
## creature kind and to an authored structure, exactly once each.
func _check_world_integration(gs: Node) -> int:
	var f := 0
	gs.delete_save()
	gs.reset()
	gs.set_current_realm("bramblewood")
	var scene: Node = (load("res://scenes/world/grove.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for i in 4:
		await process_frame
	var hud := scene.get_node_or_null("HUD") as Node
	if hud == null:
		f += 1
		print("FAIL: grove has no HUD to host the discovery director")
		scene.queue_free()
		await process_frame
		return f
	var director := hud.get_node_or_null("DiscoveryDirector")
	if director == null:
		f += 1
		print("FAIL: HUD did not create the discovery director")
	var hero := scene.find_child("Hero", true, false) as Node3D

	# A creature kind met for the first time.
	var mob_scene := load(EnemyVisualRegistry.scene_for("spore_weaver")) as PackedScene
	var mob := mob_scene.instantiate() as Node3D
	scene.add_child(mob)
	mob.global_position = hero.global_position + Vector3(4.0, 0.0, 0.0)
	await create_timer(0.8).timeout
	if not gs.has_discovered_record("mob:spore_weaver"):
		f += 1
		print("FAIL: meeting a spore weaver did not record a discovery")
	var cards := _discovery_cards(hud)
	if cards.is_empty():
		f += 1
		print("FAIL: meeting a spore weaver did not present a card")
	else:
		var card := cards[0] as Control
		# The introduction sits below the enemy plate and never captures input,
		# so it cannot cover or swallow the fight it describes.
		if card.global_position.y < 330.0:
			f += 1
			print("FAIL: discovery card overlaps the combat card band (y=%.0f)"
				% card.global_position.y)
		if card.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			f += 1
			print("FAIL: discovery card captures pointer input")
	var serial_before := int(hud.get("_discovery_serial"))
	# A second creature of the same kind stays silent.
	var mob_two := mob_scene.instantiate() as Node3D
	scene.add_child(mob_two)
	mob_two.global_position = hero.global_position + Vector3(0.0, 0.0, 4.0)
	await create_timer(0.8).timeout
	if int(hud.get("_discovery_serial")) != serial_before:
		f += 1
		print("FAIL: repeat creature kind triggered a second introduction")

	# An authored structure kind met for the first time.
	var structure := Node3D.new()
	structure.name = "Structure_probe_shrine"
	structure.add_to_group("structure")
	structure.set_meta("structure_id", "probe_shrine")
	structure.set_meta("structure_kind", "shrine")
	var label := Label3D.new()
	label.name = "StructureLabel"
	label.text = "PROBE SHRINE"
	structure.add_child(label)
	scene.add_child(structure)
	structure.global_position = hero.global_position + Vector3(-5.0, 0.0, 0.0)
	await create_timer(0.8).timeout
	if not gs.has_discovered_record("structure:probe_shrine"):
		f += 1
		print("FAIL: meeting an authored shrine did not record a discovery")

	mob.queue_free()
	mob_two.queue_free()
	scene.queue_free()
	await process_frame
	if f == 0:
		print("PASS: director fires on first creature and structure meetings")
	return f

func _discovery_cards(hud: Node) -> Array:
	return hud.find_children("DiscoveryCard", "PanelContainer", true, false)
