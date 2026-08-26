extends SceneTree

## Headless test: ImpactDirector — style x surface profiles, weapon element
## resolution, element payloads run clean, audio cue renderers non-empty.

func _initialize() -> void:
	_run.call_deferred()
	var watchdog := create_timer(25.0)
	watchdog.timeout.connect(func():
		print("WATCHDOG TIMEOUT — test hung")
		quit(2))

func _run() -> void:
	var failures := 0
	var gs = root.get_node_or_null("/root/GameState")

	# --- Profile resolution: keys exist, surface cue layers in ---
	var p := ImpactDirector.resolve("slash", "plant")
	if p.is_empty():
		failures += 1
		print("FAIL: resolve('slash','plant') returned empty")
	elif str(p.cue) != "impact_plant":
		failures += 1
		print("FAIL: slash on plant should cue impact_plant, got ", p.cue)
	var stone := ImpactDirector.resolve("blunt", "stone")
	if not (float(stone.shake) > float(ImpactDirector.resolve("blunt", "flesh").shake)):
		failures += 1
		print("FAIL: stone surface should multiply shake up")
	var fallback := ImpactDirector.resolve("unknown_style", "unknown_surface")
	if fallback.is_empty():
		failures += 1
		print("FAIL: unknown style/surface must fall back, not break")

	# --- Element resolution: vanilla inert, relics deterministic ---
	var vanilla := ImpactDirector.element_for_weapon(
		gs.WEAPON_DEFS["mug_mace"].duplicate(true))
	if vanilla != "":
		failures += 1
		print("FAIL: vanilla weapons must stay elementless, got '%s'" % vanilla)
	var relic := RelicData.build_weapon_def(
		{"id": "mug_mace", "name": "MUG MACE", "atk": 7}, 1,
		"Test Charm", ["A", "B", "C"])
	if not (str(relic.element) in ImpactDirector.ELEMENTS):
		failures += 1
		print("FAIL: relic kit missing valid element, got '%s'" % str(relic.get("element")))
	var again := RelicData.build_weapon_def(
		{"id": "mug_mace", "name": "MUG MACE", "atk": 7}, 1,
		"Test Charm", ["A", "B", "C"])
	if str(again.element) != str(relic.element):
		failures += 1
		print("FAIL: same-name kits must keep the same element")

	# --- Surface classing by group ---
	var probe := Node3D.new()
	root.add_child(probe)
	if ImpactDirector.surface_for(probe) != "flesh":
		failures += 1
		print("FAIL: ungrouped node should class as flesh")
	probe.add_to_group("boss")
	if ImpactDirector.surface_for(probe) != "stone":
		failures += 1
		print("FAIL: boss group should class as stone")
	probe.free()

	# --- Payloads execute against a live context without errors ---
	await process_frame
	var payload := Node3D.new()
	root.add_child(payload)
	ImpactDirector.apply_element(payload, "fire", Vector3.ZERO)
	ImpactDirector.apply_element(payload, "frost", Vector3.ZERO)
	ImpactDirector.apply_element(payload, "shock", Vector3.ZERO)
	ImpactDirector.apply_element(payload, "nature", Vector3.ZERO)
	ImpactDirector.apply_strike(payload, "magic", "plant",
		Vector3(1, 0, 2), true, "shock")
	payload.free()

	# --- New cue renderers produce audible buffers ---
	var audio = root.get_node_or_null("/root/AudioManager")
	if audio == null:
		failures += 1
		print("FAIL: AudioManager autoload missing")
	else:
		for cue in ["impact_thud", "impact_plant", "impact_stone", "impact_claw",
				"elem_fire", "elem_frost", "elem_shock", "elem_nature"]:
			if audio._render_cue(cue, 0).size() == 0:
				failures += 1
				print("FAIL: cue renderer empty for ", cue)

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d FAILURES" % failures)
	quit(failures if failures > 0 else 0)
