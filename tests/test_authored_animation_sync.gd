extends SceneTree

## Imported animation cues must preserve attack intent and own contact timing
## whenever a matching clip exists. Missing clips retain procedural fallback.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := 0
	var animator := EntityAnimator.new()
	animator.mode = EntityAnimator.Mode.BIPED
	root.add_child(animator)
	animator.attack_style = "slash"
	animator.combo_step = 0
	animator.trigger_attack()
	if animator.authored_attack_cue != "light_1":
		failures += 1
		print("FAIL: first slash did not request light_1")
	animator.combo_step = 1
	animator.trigger_attack()
	if animator.authored_attack_cue != "light_2":
		failures += 1
		print("FAIL: second slash did not preserve combo cue")
	animator.trigger_attack("heavy")
	if animator.authored_attack_cue != "heavy":
		failures += 1
		print("FAIL: heavy intent was collapsed to a light cue")
	animator.attack_style = "magic"
	animator.trigger_attack()
	if animator.authored_attack_cue != "cast":
		failures += 1
		print("FAIL: magic basic did not request cast cue")

	var bridge := AnimTreeBridge.new()
	var player := AnimationPlayer.new()
	bridge.add_child(player)
	root.add_child(bridge)
	var library := AnimationLibrary.new()
	var attack := Animation.new()
	attack.length = 1.0
	library.add_animation("HumanArmature|swordAttackJump", attack)
	player.add_animation_library("", library)
	bridge.bind(bridge)
	if not bridge.has_cue("light_1") or not bridge.has_cue("light_2") \
			or not bridge.has_cue("heavy"):
		failures += 1
		print("FAIL: current single authored attack cannot back compatible cues")
	if bridge.has_cue("death"):
		failures += 1
		print("FAIL: missing clips must not claim authored ownership")

	var state := {"attacking": true, "attack_cue": "heavy",
		"impact_fraction": 0.56}
	bridge.state_provider = func() -> Dictionary: return state
	var impacts := {"count": 0}
	bridge.cue_impact.connect(func(_cue: String) -> void: impacts.count += 1)
	# Wait on the physics clock, not create_timer: AnimationPlayer advances on
	# physics ticks, and headless idle time drifts ahead of them. 48 ticks =
	# 0.80s, comfortably past the 0.56s heavy impact threshold.
	for _i in 48:
		await physics_frame
	if bridge.current_cue() != "heavy" or int(impacts.count) != 1:
		failures += 1
		print("FAIL: authored heavy did not emit exactly one profile-timed impact ",
			"cue=", bridge.current_cue(), " impacts=", impacts.count,
			" elapsed=", bridge._cue_elapsed, " playing=", player.is_playing())
	for _i in 18:
		await physics_frame

	animator.queue_free()
	bridge.queue_free()
	print("ALL AUTHORED ANIMATION SYNC TESTS PASSED" if failures == 0 \
		else "%d AUTHORED ANIMATION SYNC FAILURES" % failures)
	quit(0 if failures == 0 else 1)
