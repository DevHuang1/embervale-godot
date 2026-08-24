extends SceneTree

## Headless functional check: realms bestiary, scan economy, boss
## customization storage/payload roundtrip, palette extraction, elite
## volley flag and live customization application on a real boss node.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := 0
	var gs = root.get_node("/root/GameState")
	gs.delete_save()
	gs.reset()

	# === Scan economy ===
	if gs.scans_remaining != GameState.FREE_SCANS:
		failures += 1
		print("FAIL: free scan grant wrong -> ", gs.scans_remaining)
	gs.scans_remaining = 1
	if not gs.consume_scan():
		failures += 1
		print("FAIL: consume_scan refused with 1 left")
	if gs.consume_scan():
		failures += 1
		print("FAIL: consumed at zero")
	for i in 20:
		gs.earn_scan()
	if gs.scans_remaining != GameState.MAX_SCANS:
		failures += 1
		print("FAIL: scan cap ignored -> ", gs.scans_remaining)

	# === Bestiary integrity ===
	var pool: Array = Bestiary.skill_pool("matriarch")
	if pool.size() != 4:
		failures += 1
		print("FAIL: matriarch pool size != 4")
	var seen := {}
	for sk in pool:
		if seen.has(str(sk.id)):
			failures += 1
			print("FAIL: duplicate pool id ", sk.id)
		seen[str(sk.id)] = true
		if not AudioManager.SFX_PROFILES.is_empty():
			pass
	for preset in Bestiary.boss_def("matriarch").sfx_presets:
		if not AudioManager.SFX_PROFILES.has(preset):
			failures += 1
			print("FAIL: unknown sfx preset ", preset)
	if Bestiary.realm_id_for_stage(2) != Bestiary.REALM_MISTFEN:
		failures += 1
		print("FAIL: stage 2 realm mapping")
	if int(Bestiary.WAVES[1].hard) != 1:
		failures += 1
		print("FAIL: stage-1 wave comp")
	if Bestiary.variant_for(Bestiary.REALM_HEARTWOOD, "hard").volley != true:
		failures += 1
		print("FAIL: heartwood hard tier lacks volley")

	# === Palette extraction ===
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	img.fill(Color(0.9, 0.12, 0.1))
	img.fill_rect(Rect2i(10, 10, 12, 12), Color(0.1, 0.2, 0.92))
	var pal: Array[Color] = RelicForge.extract_palette(img, 3)
	if pal.size() != 3:
		failures += 1
		print("FAIL: palette size ", pal.size())
	var vivid := false
	for c in pal:
		if absf(c.r - c.b) > 0.25:
			vivid = true
	if not vivid:
		failures += 1
		print("FAIL: palette lost the vivid subject colors")

	# === Storage + save/load roundtrip ===
	var skill_def: Dictionary = pool[0]
	gs.scans_remaining = 3
	var payload := {
		"boss_id": "matriarch",
		"skill": skill_def,
		"sfx_preset": "grave_moss",
		"palette": [Color(0.5, 0.2, 0.1).to_html(true), "#112233", "#445566"],
	}
	gs.set_boss_custom("matriarch", payload)
	if gs.get_boss_custom("matriarch").is_empty():
		failures += 1
		print("FAIL: custom not stored")
	gs.save_game()
	gs.reset()
	gs.load_game()
	if gs.scans_remaining != 3:
		failures += 1
		print("FAIL: scan count lost across load -> ", gs.scans_remaining)
	var loaded: Dictionary = gs.get_boss_custom("matriarch")
	if loaded.is_empty():
		failures += 1
		print("FAIL: custom lost across load")
	else:
		if str(loaded.skill.get("id", "")) != str(skill_def.id):
			failures += 1
			print("FAIL: pool skill lost across load")
		if str(loaded.sfx_preset) != "grave_moss":
			failures += 1
			print("FAIL: preset lost across load")

	# === Resource conversion ===
	var bc := BossCustomization.from_payload(loaded)
	if bc.palette.size() != 3:
		failures += 1
		print("FAIL: hex palette parse -> ", bc.palette.size())
	if bc.sfx_preset != "grave_moss":
		failures += 1
		print("FAIL: resource preset mismatch")
	var roundtrip: Dictionary = bc.to_payload()
	if str(roundtrip.palette[0]) != Color(0.5, 0.2, 0.1).to_html(true):
		failures += 1
		print("FAIL: hex roundtrip -> ", roundtrip.palette[0])

	# === Elite volley flag on a live hushling ===
	var hush_scene: PackedScene = load("res://scenes/entities/hushling.tscn")
	if hush_scene == null:
		failures += 1
		print("FAIL: hushling.tscn failed to load")
	else:
		var foe = hush_scene.instantiate()
		root.add_child(foe)
		if not ("thorn_volley" in foe):
			failures += 1
			print("FAIL: thorn_volley property missing")
		else:
			foe.thorn_volley = true
			if not foe.thorn_volley:
				failures += 1
				print("FAIL: volley flag did not stick")
		foe.queue_free()

	# === Live customization application on the boss ===
	var boss_scene: PackedScene = load("res://scenes/entities/boss_matriarch.tscn")
	if boss_scene == null:
		failures += 1
		print("FAIL: boss_matriarch.tscn failed to load")
	else:
		var boss = boss_scene.instantiate()
		root.add_child(boss)
		boss.apply_customization(bc)
		if boss.customization == null:
			failures += 1
			print("FAIL: customization not applied")
		if boss.sfx_profile != "grave_moss":
			failures += 1
			print("FAIL: sfx profile not applied -> ", boss.sfx_profile)
		if not is_equal_approx(boss._realm_skill_cooldown(), float(skill_def.cooldown)):
			failures += 1
			print("FAIL: pool cooldown not routed -> ", boss._realm_skill_cooldown())
		var mat = boss.get_node("Visual/Body").material_override
		if mat is ShaderMaterial:
			var tint = mat.get_shader_parameter("base_color")
			if tint == null or not (tint is Color):
				failures += 1
				print("FAIL: body palette not applied")
		elif mat == null:
			failures += 1
			print("FAIL: boss body has no material to tint")

		# Practice bosses skip rewards
		boss.is_practice = true
		var xp_before: int = gs.xp
		boss._spawn_rewards()
		if gs.xp != xp_before:
			failures += 1
			print("FAIL: practice boss granted rewards")
		boss.queue_free()

	if failures == 0:
		print("ALL BOSS CUSTOMIZATION TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(1 if failures > 0 else 0)
