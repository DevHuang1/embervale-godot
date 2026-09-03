extends SceneTree

## === Attack Swing Animation Validation ===
## One-clock sync (body phases mirror the weapon-arc ratios with a per-phase
## floor), clean swing lifecycle (single impact, tween closed, pose restored)
## across all three combo steps including the overhead finisher.

var _impacts := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var failures := 0
	var animator := EntityAnimator.new()
	animator.mode = EntityAnimator.Mode.BIPED
	# Minimal rig: the swing kit needs arms, forearms and a visual root.
	var vis := Node3D.new()
	animator.visual_root = vis
	animator.arm_l = Node3D.new()
	animator.arm_r = Node3D.new()
	animator.forearm_l = Node3D.new()
	animator.forearm_r = Node3D.new()
	vis.add_child(animator.arm_l)
	vis.add_child(animator.arm_r)
	animator.arm_l.add_child(animator.forearm_l)
	animator.arm_r.add_child(animator.forearm_r)
	animator.add_child(vis)
	root.add_child(animator)
	await process_frame
	animator._next_fidget_at = 9999.0  # keep idle fidgets out of pose asserts
	animator.attack_impact.connect(func() -> void: _impacts += 1)

	# --- Clock math: phases mirror the arc ratios with a per-phase floor ---
	animator.set_swing_clock(0.30, 0.3, 0.3, 0.4)
	if is_equal_approx(animator._swing_windup, 0.09) \
			and is_equal_approx(animator._swing_snap, 0.09) \
			and is_equal_approx(animator._swing_settle, 0.12):
		print("PASS: swing clock mirrors arc ratios")
	else:
		failures += 1
		print("FAIL: clock phases should mirror ratios, got ",
			animator._swing_windup, "/", animator._swing_snap, "/", animator._swing_settle)
	animator.set_swing_clock(0.08, 0.28, 0.3, 0.42)
	if animator._swing_windup >= 0.045 and animator._swing_snap >= 0.045 \
			and animator._swing_settle >= 0.045:
		print("PASS: per-phase floor applied")
	else:
		failures += 1
		print("FAIL: per-phase floor not applied")

	# --- Lifecycle: three chained swings, single impact each, pose restored ---
	animator.set_swing_clock(0.30, 0.3, 0.3, 0.4)
	var base_forearm_r := animator.forearm_r.rotation.x
	for step in 3:
		_impacts = 0
		animator.combo_step = step
		animator.trigger_attack()
		if animator.anim_state != EntityAnimator.AnimState.ATTACK:
			failures += 1
			print("FAIL: combo step ", step, " did not enter ATTACK")
		var frames := 0
		while animator.anim_state == EntityAnimator.AnimState.ATTACK and frames < 600:
			await process_frame
			frames += 1
		for _drain in 12:  # let transient impact tweens (squash/unwind) finish
			await process_frame
		if animator.anim_state != EntityAnimator.AnimState.IDLE:
			failures += 1
			print("FAIL: combo step ", step, " never returned to IDLE")
		elif _impacts != 1:
			failures += 1
			print("FAIL: combo step ", step, " emitted ", _impacts, " impacts (want 1)")
		else:
			print("PASS: combo step ", step, " swung, impacted once, settled")
		if animator._attack_tween != null and animator._attack_tween.is_valid():
			failures += 1
			print("FAIL: combo step ", step, " left the swing tween running")
		var drift := absf(animator.forearm_r.rotation.x - base_forearm_r)
		if drift > 0.03:
			failures += 1
			print("FAIL: combo step ", step, " forearm did not settle home (drift ", drift, ")")
		var sdrift := float((animator.visual_root.scale - Vector3.ONE).length())
		if sdrift > 0.02:
			failures += 1
			print("FAIL: combo step ", step, " visual scale did not restore (", sdrift, ")")

	animator.queue_free()
	if failures == 0:
		print("=== Attack Swing Animation Validation ===")
		print("passes=1 failures=0")
		quit(0)
	else:
		print("ATTACK SWING ANIMATION FAILURES: ", failures)
		quit(1)