extends SceneTree

## Headless regression: attack one-shots must settle anim_state back to IDLE.
## Guards the EntityAnimator state machine against ATTACK wedges:
## - BLOB pounce resets via its completion callback (tween path)
## - mid-pounce re-trigger (tween kill/restart) still settles
## - hit mid-pounce leaves no stale ATTACK behind (guarded callback skips)
## - missing-limb fallbacks reset instead of wedging every variant

func _initialize() -> void:
	_run.call_deferred()

func _seconds(s: float) -> void:
	await create_timer(s).timeout

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var failures := 0
	var animator_script: GDScript = load("res://scripts/entities/entity_animator.gd")
	var attack: int = animator_script.AnimState.ATTACK
	var idle: int = animator_script.AnimState.IDLE

	var hushling: Node = (load("res://scenes/entities/hushling.tscn") as PackedScene).instantiate()
	root.add_child(hushling)
	await _frames(5)
	var animator: Node = hushling.get_node("Animator")
	# Node exports don't resolve on runtime instantiation; wire the visual
	# root by hand so the real pounce tween variant gets exercised.
	if animator.visual_root == null:
		animator.visual_root = hushling.get_node("Visual")

	animator.trigger_attack()
	if animator.anim_state != attack:
		failures += 1
		print("FAIL: anim_state not ATTACK right after trigger_attack")
	await _seconds(0.8)
	if animator.anim_state != idle:
		failures += 1
		print("FAIL: anim_state stuck at ", animator.anim_state, " after pounce (want IDLE=0)")

	animator.trigger_attack()
	await _seconds(0.12)
	animator.trigger_attack()
	await _seconds(0.8)
	if animator.anim_state != idle:
		failures += 1
		print("FAIL: anim_state stuck after mid-pounce re-trigger")

	animator.trigger_attack()
	await _seconds(0.10)
	animator.trigger_hit()
	await _frames(2)
	if animator.anim_state == attack:
		failures += 1
		print("FAIL: anim_state still ATTACK immediately after mid-pounce hit")
	await _seconds(0.9)
	if animator.anim_state != idle:
		failures += 1
		print("FAIL: anim_state stuck after mid-pounce hit")

	hushling.queue_free()
	await _frames(2)

	# --- Missing-limb fallbacks must never leave ATTACK (hardening) ---
	var bare := Node3D.new()
	bare.set_script(animator_script)
	root.add_child(bare)
	await _frames(2)

	for kind in ["", "slash", "heavy", "buff", "hurl", "sky", "spin"]:
		bare.attack_style = "slash"
		bare.mode = 0
		bare.trigger_attack(kind)
		if bare.anim_state != idle:
			failures += 1
			print("FAIL: degenerate BIPED '", kind, "' left anim_state ", bare.anim_state)
	bare.attack_style = "magic"
	bare.trigger_attack("")
	if bare.anim_state != idle:
		failures += 1
		print("FAIL: degenerate cast left anim_state ", bare.anim_state)
	bare.mode = 1
	bare.attack_style = "slash"
	bare.trigger_attack("")
	if bare.anim_state != idle:
		failures += 1
		print("FAIL: degenerate BLOB pounce left anim_state ", bare.anim_state)
	bare.mode = 2
	bare.trigger_attack("")
	if bare.anim_state != idle:
		failures += 1
		print("FAIL: degenerate BRUTE slam left anim_state ", bare.anim_state)

	bare.queue_free()
	await _frames(2)

	if failures == 0:
		print("ALL ANIM STATE RESET TESTS PASSED")
	else:
		print("ANIM STATE RESET TESTS FAILED: ", failures)
	quit(1 if failures > 0 else 0)
