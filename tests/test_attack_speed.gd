extends SceneTree

## === Attack Speed & Swing Timing Validation ===
## The attack-feel pass must have: faster hero weapon swing arcs, a faster
## base strike cadence, a longer combo window so chains still connect at the
## higher cadence, dexterity scaling the visible arc (starter dex = 0 keeps
## authored timing), and untouched weapon-family commitment ratios.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := 0

	# Hero weapons swing faster than the pre-tuning baselines.
	var baselines := {
		"mug_mace": 0.38, "ember_sword": 0.30,
		"arcane_staff": 0.44, "matriarch_scepter": 0.48,
	}
	var gs: Node = root.get_node("GameState")
	for id in baselines:
		var t := float(gs.WEAPON_DEFS[id].get("swing_time", 1.0))
		if t >= float(baselines[id]):
			failures += 1
			print("FAIL: ", id, " swing_time did not speed up: ", t)
		else:
			print("PASS: ", id, " swing_time ", t, "s < ", baselines[id], "s")

	# Combo window grew so chains connect at the higher cadence.
	if float(EntityAnimator.COMBO_WINDOW) < 0.65:
		failures += 1
		print("FAIL: COMBO_WINDOW did not grow: ", EntityAnimator.COMBO_WINDOW)
	else:
		print("PASS: COMBO_WINDOW = ", EntityAnimator.COMBO_WINDOW)

	# Starter dex is 0: base cadence/multiplier stays 1.0; dex scales on top.
	if not is_equal_approx(gs.attack_speed_mult(), 1.0):
		failures += 1
		print("FAIL: starter attack_speed_mult should be 1.0, got ", gs.attack_speed_mult())
	else:
		print("PASS: starter attack_speed_mult = 1.0")

	# Weapon families keep their distinct commitment ratios (totals = 1.0).
	for style in ["blunt", "slash", "magic"]:
		if not WeaponCombatProfiles.timing_is_valid(WeaponCombatProfiles.for_style(style)):
			failures += 1
			print("FAIL: profile timing broke for ", style)
	print("PASS: weapon family commitment ratios intact")

	# Hero cadence constant dropped below the old 1.15s base. Read from an
	# out-of-tree instance: _ready never runs, so no world context is needed
	# and no harness-only script errors are emitted.
	var hero: Node = (load("res://scenes/entities/hero.tscn") as PackedScene).instantiate()
	if float(hero.auto_strike_cooldown) >= 0.95:
		failures += 1
		print("FAIL: hero auto_strike_cooldown did not speed up: ", hero.auto_strike_cooldown)
	else:
		print("PASS: auto_strike_cooldown = ", hero.auto_strike_cooldown, "s")
	hero.free()

	if failures == 0:
		print("=== Attack Speed Validation ===")
		print("passes=1 failures=0")
		quit(0)
	else:
		print("ATTACK SPEED FAILURES: ", failures)
		quit(1)