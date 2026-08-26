extends SceneTree

## Headless smoke test: HUD instantiation, EmberBar ghost logic,
## new CombatFx primitives, skill-cast audio cues, animator cast variants.

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(25.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — test hung")
		quit(2))

func _run() -> void:
	var failures := 0

	# --- HUD instantiates with the new layout ---
	var hud_scene: PackedScene = load("res://scenes/ui/hud.tscn")
	if hud_scene == null:
		print("FAIL: hud.tscn did not load")
		root.add_child(Node.new())  # keep tree alive
		quit(1)
		return
	var hud := hud_scene.instantiate()
	root.add_child(hud)
	print("MARK: hud added")
	await process_frame
	print("MARK: hud ready")
	await process_frame
	for path in ["Root/PlayerPlate/PlateVBox/WarmthBar", "Root/PlayerPlate/PlateVBox/ExpBar",
			"Root/PlayerPlate/PlateVBox/PlateHeader/LevelBadge",
			"Root/MetaRow/TopRow/GoldLabel", "Root/BossHealthBar/BossHPBar",
			"Root/CombatCard/CombatVBox/EnemyHPBar"]:
		if hud.get_node_or_null(path) == null:
			failures += 1
			print("FAIL: missing HUD node ", path)
	var warmth_bar = hud.get_node("Root/PlayerPlate/PlateVBox/WarmthBar")
	if not (warmth_bar is EmberBar):
		failures += 1
		print("FAIL: WarmthBar is not an EmberBar")

	# --- EmberBar ghost trail reacts to damage/heal ---
	print("MARK: bars")
	warmth_bar.max_value = 34
	warmth_bar.value = 34
	await process_frame
	warmth_bar.value = 20
	await process_frame
	for i in 10:
		await process_frame
	if warmth_bar._ghost_ratio <= warmth_bar._display_ratio - 0.001 \
			or warmth_bar._ghost_ratio < 0.5:
		failures += 1
		print("FAIL: ghost ratio did not linger above fill (",
			warmth_bar._ghost_ratio, " vs ", warmth_bar._display_ratio, ")")
	var hp_before: float = warmth_bar._display_ratio
	warmth_bar.value = 30
	for i in 20:
		await process_frame
	if warmth_bar._display_ratio <= hp_before + 0.01:
		failures += 1
		print("FAIL: display ratio did not rise on heal")

	# --- CombatFx primitives spawn without error ---
	print("MARK: fx")
	var host := Node3D.new()
	root.add_child(host)
	CombatFx.spawn_bolt(host, Vector3.ZERO, Vector3(3, 0, 0))
	CombatFx.spawn_pillar(host, Vector3.ZERO)
	CombatFx.spawn_motes(host, Vector3.ZERO, Color.RED, 4)
	CombatFx.spawn_shockwave(host, Vector3.ZERO, 2.0)
	var charge := CombatFx.spawn_charge_glow(host, Vector3.ZERO,
		Color.WHITE, 0.05, 1.2)
	if charge == null or not is_instance_valid(charge):
		failures += 1
		print("FAIL: charge glow returned no mesh")
	await create_timer(0.3).timeout

	# --- Audio cues render & cache ---
	print("MARK: audio")
	var am = root.get_node("/root/AudioManager")
	for cue in ["skill_charge", "skill_hurl", "skill_whirl_spin",
			"skill_dash_zip", "comet_fall", "heal_bloom_cue", "aura_rise"]:
		am.play_cue(cue)
		if am._get_cue_streams(cue).is_empty():
			failures += 1
			print("FAIL: cue rendered empty: ", cue)
	am.play_skill_cast("whirl")
	am.play_skill_release("explosion")
	am.play_skill_release("comet")
	am.play_skill_release("heal_bloom")

	# --- Animator accepts the new cast kinds without crashing ---
	print("MARK: animator")
	# Resolve at runtime: -s scripts compile before autoload globals exist
	var anim_script: GDScript = load("res://scripts/entities/entity_animator.gd")
	var anim = anim_script.new()
	var rig_root := Node3D.new()
	anim.visual_root = rig_root
	anim.arm_l = Node3D.new()
	anim.arm_r = Node3D.new()
	rig_root.add_child(anim.arm_l)
	rig_root.add_child(anim.arm_r)
	root.add_child(rig_root)
	root.add_child(anim)
	await process_frame
	for kind in ["hurl", "sky", "spin", "buff"]:
		anim.trigger_attack(kind)
		if not anim._attack_tween.is_valid():
			failures += 1
			print("FAIL: cast kind produced no tween: ", kind)

	# --- HUD theme applied ---
	if hud.get_node("Root/QuestLedger").get_theme_stylebox("panel") == null:
		failures += 1
		print("FAIL: quest ledger panel stylebox override missing")

	if failures == 0:
		print("ALL SMOKE TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(1 if failures > 0 else 0)
