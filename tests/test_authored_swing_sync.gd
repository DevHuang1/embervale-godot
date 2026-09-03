extends SceneTree

## === Authored Swing Sync Validation ===
## The visible hero is the authored FBX rig: the bridge must own the attack
## cues, report the clip's real impact moment (with per-cue speed), and
## restart the swing clip on every new attack even when the cue repeats.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := 0
	var scene := load("res://scenes/world/grove.tscn") as PackedScene
	var world := scene.instantiate()
	root.add_child(world)
	await process_frame
	await process_frame

	var hero := world.find_child("Hero", true, false)
	var bridge := hero.get_meta("anim_bridge", null) as AnimTreeBridge
	if hero == null or bridge == null or bridge.player == null:
		print("FAIL: hero authored bridge missing")
		quit(1)
		return

	# The real hero rig owns the attack cues.
	if bridge.has_cue("light_1") and bridge.has_cue("heavy"):
		print("PASS: hero rig owns light_1/heavy cues")
	else:
		failures += 1
		print("FAIL: hero rig lacks attack cues")

	# cue_impact_time = clip length x impact fraction / per-cue speed.
	var frac := 0.44  # slash profile authored impact fraction
	var impact_t := bridge.cue_impact_time("light_1", frac)
	var clip_len := bridge.player.get_animation(bridge._resolve("light_1")).length
	var expected := clip_len * frac / 1.25
	if absf(impact_t - expected) <= 0.001:
		print("PASS: light_1 impact at ", snappedf(impact_t, 0.001),
			"s (clip ", snappedf(clip_len, 0.001), "s @ 1.25x)")
	else:
		failures += 1
		print("FAIL: cue_impact_time ", impact_t, " != ", expected)

	# swing_serial bumps on every trigger_attack.
	var animator := hero.get_node("Animator")
	var serial0 := int(animator.swing_serial)
	animator.attack_style = "slash"
	animator.combo_step = 0
	animator.trigger_attack()
	if int(animator.swing_serial) == serial0 + 1:
		print("PASS: swing_serial increments per attack")
	else:
		failures += 1
		print("FAIL: swing_serial did not increment")

	# Same cue + new serial must restart the clip (drive the bridge directly).
	var st := {"dead": false, "attacking": true, "moving": false, "running": false,
		"hit": false, "dodging": false, "attack_cue": "light_1",
		"impact_fraction": frac, "attack_serial": int(animator.swing_serial)}
	bridge.state_provider = func() -> Dictionary: return st
	bridge._process(0.016)
	if bridge.current_cue() != "light_1":
		failures += 1
		print("FAIL: bridge did not pick up the attack cue, got ", bridge.current_cue())
	for _i in 12:
		await process_frame
	var pos_before: float = bridge.player.current_animation_position
	animator.swing_serial += 1
	st["attack_serial"] = int(animator.swing_serial)
	bridge._process(0.016)
	await process_frame
	var pos_after: float = bridge.player.current_animation_position
	if bridge.current_cue() == "light_1" and pos_after < pos_before:
		print("PASS: same-cue attack restarted the swing clip (",
			snappedf(pos_before, 0.001), "s -> ", snappedf(pos_after, 0.001), "s)")
	else:
		failures += 1
		print("FAIL: same-cue attack did not restart the clip (",
			snappedf(pos_before, 0.001), "s -> ", snappedf(pos_after, 0.001), "s)")

	world.queue_free()
	if failures == 0:
		print("=== Authored Swing Sync Validation ===")
		print("passes=1 failures=0")
		quit(0)
	else:
		print("AUTHORED SWING SYNC FAILURES: ", failures)
		quit(1)