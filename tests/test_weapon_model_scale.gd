extends SceneTree

func _init() -> void:
	var registry := preload("res://scripts/systems/weapon_visual_registry.gd")
	var failures := 0
	var checked := 0
	for raw_id in registry.WEAPON_PATHS:
		var weapon_id := str(raw_id)
		var path := registry.path_for(weapon_id)
		if path.is_empty():
			failures += 1
			print("FAIL: registry path missing for ", weapon_id)
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			failures += 1
			print("FAIL: model does not load for ", weapon_id)
			continue
		var model := packed.instantiate() as Node3D
		if model == null:
			failures += 1
			print("FAIL: model is not a Node3D for ", weapon_id)
			continue
		var raw_length := registry.model_max_dimension(model)
		if raw_length <= 0.01:
			failures += 1
			print("FAIL: model has no measurable geometry for ", weapon_id)
			continue
		checked += 1
		var target := registry.target_length(weapon_id)
		var displayed := raw_length * registry.normalized_scale(weapon_id, model)
		if absf(displayed - target) > target * 0.02:
			failures += 1
			print("FAIL: %s normalizes to %.3fm instead of %.3fm"
				% [weapon_id, displayed, target])
		if displayed < 0.30 or displayed > 2.0:
			failures += 1
			print("FAIL: %s hand length %.3fm is outside the readable band" % [weapon_id, displayed])
		model.free()
	for kit in ["mug_mace", "pocket_blade", "snip_twins", "soda_cannon", "slab_hammer"]:
		if not registry.WEAPON_LENGTHS.has(kit):
			failures += 1
			print("FAIL: forge kit has no authored length: ", kit)
		var relic_id := "relic_%s" % kit
		if registry.resolve_id(relic_id) != kit:
			failures += 1
			print("FAIL: forged kit id does not resolve: ", relic_id)
		if registry.path_for(relic_id).is_empty():
			failures += 1
			print("FAIL: forged kit has no wieldable model: ", relic_id)
		if not is_equal_approx(registry.target_length(relic_id), registry.target_length(kit)):
			failures += 1
			print("FAIL: forged kit length diverges from its base: ", relic_id)
	if registry.resolve_id("ember_sword") != "ember_sword":
		failures += 1
		print("FAIL: resolve_id rewrote a canonical id")
	if checked == 0:
		failures += 1
		print("FAIL: no weapon models were measurable")
	if failures == 0:
		print("ALL WEAPON MODEL SCALE TESTS PASSED (%d models)" % checked)
	else:
		print("%d FAILURES" % failures)
	quit(1 if failures > 0 else 0)
